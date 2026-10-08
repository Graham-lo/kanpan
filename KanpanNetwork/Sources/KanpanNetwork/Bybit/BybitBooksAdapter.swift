import Foundation
import KanpanCore

/// Bybit 一条连接上的几本簿（同一个 category：现货 `BTCUSDT`、U 本位 `BTCUSDT` / `1000PEPEUSDT`、
/// 币本位 `BTCUSD` / 币本位交割 `BTCUSDH26`），不分线路一律经 kanpan-api 的中继
/// `/v1/market/ws/bybit?category=spot|linear|inverse`（上游 `wss://stream.bybit.com/v5/public/<category>`，
/// 帧原样转发）——国内直连不了 Bybit，和 OKX 同一个做法。一个 category 一条（或几条）连接。
///
/// - 连上后自己发订阅：`{"op":"subscribe","args":["orderbook.1000.BTCUSDT","publicTrade.BTCUSDT",…]}`。
///   中继一条订阅消息最多 10 个 args、一条连接最多同时订 24 个 topic，所以一条连接最多 `maxBooks` 本，
///   一条消息最多 5 本。
/// - `orderbook.1000`：首帧 `type=snapshot`（每侧 1000 档），之后 `type=delta`；`data.u` 是这本簿的更新号，
///   严格 +1（2026-10-08 三个 category 录了 1.3 万帧，没有一次跳号）→ 序号模型 `strictIncrementing`
///   （`sequenceModel`，要改只改这一处）。`u == 1` 的 snapshot 是 Bybit 那边服务重启，本地整本重来
///   （`BookSnapshot.restartsSequence`）。数量 `0` 删档。
///   每侧只维护盘口最近 1000 档：窗口外不推、被挤出窗口的推 0，快照标 `slidingWindow`（同 OKX 400 档）。
/// - 一本接不上序号：只退订再订那一本的 `orderbook.1000`（Bybit 会重发一帧 snapshot），同连接别的簿不动。
/// - `publicTrade` 的 `S` 是主动方（Buy 吃卖盘）；`L`、`BT`、`RPI`、`seq` 不用。
/// - 每 20 秒发一句 `{"op":"ping"}`；回来的 `{"success":true,"ret_msg":"pong","op":"ping"}`
///   （或 `{"op":"pong",…}`）与订阅回执 `{"success":true,"op":"subscribe"}` 都不带 topic，解码直接忽略。
/// - 数量原样给（现货与 U 本位是币数，币本位是张数，一张 1 美元），名义美元由 `OrderFlowNotional` 换。
///
/// 中继地址、保活、控制帧的写法来自 `BybitVenue` / `BybitWire`，解帧是 `BybitDTO.orderFlow`（Bybit 唯一的报文解码）。
public struct BybitBooksAdapter: DepthFeedAdapter {
  public enum Category: String, Sendable, CaseIterable {
    case spot, linear, inverse

    var label: String {
      switch self {
      case .spot: "现货"
      case .linear: "U 本位"
      case .inverse: "币本位"
      }
    }
  }

  /// 三个 category 都是一本簿一个 `u`、严格 +1。录帧发现跳号时改成别的模型只改这里。
  public static let sequenceModel: DepthSequenceModel = .strictIncrementing
  /// `orderbook.1000` 每侧 1000 档（滑动窗口）。
  public static let snapshotLevels = 1000
  /// 一条连接最多几本（中继一条连接最多 24 个 topic，一本 orderbook + publicTrade 两个）。
  public static let maxBooks = 12
  /// 一条订阅消息最多几本（一条消息最多 10 个 args，一本两个）。
  static let booksPerMessage = BybitVenue.maxArgsPerMessage / 2

  public let category: Category
  public let books: [DepthBook]
  /// kanpan-api 主机（`MarketRoute.apiHosts`，主在前）。
  let gateways: [String]
  let sockets: any WSSocketFactory
  private let byInstrument: [String: DepthBook]

  public init(category: Category, books: [DepthBook], gateways: [String],
              sockets: any WSSocketFactory = URLSessionSocketFactory()) {
    self.category = category
    self.books = Array(books.prefix(Self.maxBooks))
    self.gateways = gateways; self.sockets = sockets
    var map: [String: DepthBook] = [:]
    for book in self.books { map[book.venue.instrument] = book }
    byInstrument = map
  }

  /// 一本簿归哪个 category：交割按面值口径分（反向是币本位交割，正向是 U 本位交割）。
  static func category(_ product: OrderFlowProduct, _ notional: OrderFlowNotional) -> Category {
    switch product {
    case .spot: .spot
    case .usdtPerp: .linear
    case .coinPerp: .inverse
    case .delivery:
      if case .inverse = notional { .inverse } else { .linear }
    }
  }

  public var name: String { "\(BybitVenue.displayName)\(category.label) \(books.map(\.venue.instrument).joined(separator: ","))" }

  public var streamURLs: [URL] { BybitVenue.relayStreams(hosts: gateways, category: category.rawValue) }

  public var keepAlive: DepthKeepAlive? { DepthKeepAlive(text: BybitVenue.pingText, everyMs: BybitVenue.pingEveryMs) }

  static func bookTopic(_ instrument: String) -> String { BybitVenue.bookTopic(levels: snapshotLevels, instrument) }
  static func tradeTopic(_ instrument: String) -> String { BybitVenue.tradeTopic(instrument) }

  static func message(_ op: String, _ args: [String]) -> String? { try? BybitWire.control(op, args) }

  /// 订阅消息（一条最多 `booksPerMessage` 本，即 10 个 args）。
  var subscribeMessages: [String] {
    stride(from: 0, to: books.count, by: Self.booksPerMessage).compactMap { start in
      let chunk = books[start..<min(start + Self.booksPerMessage, books.count)]
      return Self.message("subscribe", chunk.flatMap {
        [Self.bookTopic($0.venue.instrument), Self.tradeTopic($0.venue.instrument)]
      })
    }
  }

  /// 单本重订：退订再订这一本的 `orderbook.1000`，Bybit 给它重发一帧 snapshot。成交不动。
  public func resubscribeMessages(venueID: String) -> [String]? {
    guard let book = books.first(where: { $0.id == venueID }) else { return nil }
    let topic = Self.bookTopic(book.venue.instrument)
    let out = ["unsubscribe", "subscribe"].compactMap { Self.message($0, [topic]) }
    return out.count == 2 ? out : nil
  }

  public func connect(candidate: Int) async throws -> any WSSocket {
    let socket = try await sockets.connect(to: try url(candidate))
    do {
      for message in subscribeMessages { try await socket.send(message) }
    } catch {
      await socket.cancel()
      throw error
    }
    return socket
  }

  public func decode(_ text: String) -> [VenueMessage] {
    BybitDTO.orderFlow(text, books: byInstrument, levels: Self.snapshotLevels)
  }
}
