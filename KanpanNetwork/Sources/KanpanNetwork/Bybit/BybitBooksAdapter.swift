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
  /// 一条订阅消息最多几本（中继一条消息最多 10 个 args）。
  static let booksPerMessage = 5
  static let relayPath = "/v1/market/ws/bybit"
  static let pingEveryMs: Double = 20_000
  static let pingText = #"{"op":"ping"}"#

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

  public var name: String { "Bybit\(category.label) \(books.map(\.venue.instrument).joined(separator: ","))" }

  public var streamURLs: [URL] {
    gateways.compactMap { host in
      guard var c = URLComponents(string: "wss://" + host), c.host != nil, c.user == nil else { return nil }
      c.path = Self.relayPath
      c.queryItems = [URLQueryItem(name: "category", value: category.rawValue)]
      return c.url
    }
  }

  public var keepAlive: DepthKeepAlive? { DepthKeepAlive(text: Self.pingText, everyMs: Self.pingEveryMs) }

  static func bookTopic(_ instrument: String) -> String { "orderbook.\(snapshotLevels).\(instrument)" }
  static func tradeTopic(_ instrument: String) -> String { "publicTrade.\(instrument)" }

  static func message(_ op: String, _ args: [String]) -> String? {
    let obj: [String: Any] = ["op": op, "args": args]
    guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return nil }
    return String(decoding: data, as: UTF8.self)
  }

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
    guard let frame = DepthWire.object(text), let topic = frame["topic"] as? String else { return [] }
    if topic.hasPrefix("orderbook.") { return decodeBook(frame, topic: topic) }
    if topic.hasPrefix("publicTrade.") { return decodeTrades(frame, topic: topic) }
    return []
  }

  private func decodeBook(_ frame: [String: Any], topic: String) -> [VenueMessage] {
    guard let data = frame["data"] as? [String: Any],
          let symbol = data["s"] as? String, let book = byInstrument[symbol],
          topic == Self.bookTopic(symbol),
          let u = DepthWire.integer(data["u"]),
          let bids = book.levels(data["b"]), let asks = book.levels(data["a"]) else { return [] }
    let time = DepthWire.integer(frame["ts"])
    switch frame["type"] as? String {
    case "snapshot":
      guard bids.count <= Self.snapshotLevels, asks.count <= Self.snapshotLevels else { return [] }
      return [VenueMessage(book.id, .snapshot(BookSnapshot(lastUpdateID: u, requestedLevels: Self.snapshotLevels,
                                                           bids: bids, asks: asks, eventTimeMs: time,
                                                           slidingWindow: true, restartsSequence: u == 1)))]
    case "delta":
      return [VenueMessage(book.id, .delta(BookDelta(firstUpdateID: u, finalUpdateID: u, previousFinalUpdateID: nil,
                                                    bids: bids, asks: asks, eventTimeMs: time ?? 0)))]
    default:
      return []
    }
  }

  private func decodeTrades(_ frame: [String: Any], topic: String) -> [VenueMessage] {
    guard let items = frame["data"] as? [[String: Any]] else { return [] }
    var out: [VenueMessage] = []
    for t in items {
      guard let symbol = t["s"] as? String, let book = byInstrument[symbol], topic == Self.tradeTopic(symbol) else { continue }
      // 价量解得开却不是有限值或越界：整帧丢掉并记一笔（坏帧里别的成交同样不可信）。
      guard let p = DepthWire.number(t["p"]), let q = DepthWire.number(t["v"]),
            p > 0, q >= 0, p.isFinite, q.isFinite else { WireNumber.noteDropped(); return [] }
      guard q > 0, let side = t["S"] as? String, side == "Buy" || side == "Sell" else { continue }
      out.append(VenueMessage(book.id, .trade(book.trade(price: p, quantity: q, hit: side == "Buy" ? .ask : .bid,
                                                         timeMs: DepthWire.integer(t["T"]) ?? 0))))
    }
    return out
  }
}
