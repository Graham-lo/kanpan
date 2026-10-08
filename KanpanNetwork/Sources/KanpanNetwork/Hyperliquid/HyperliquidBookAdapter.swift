import Foundation
import KanpanCore

/// Hyperliquid 一条连接上的几本簿（永续，合约代号就是币名：`BTC`、`ETH`、`kPEPE`），
/// 不分线路一律经 kanpan-api 的中继 `/v1/market/ws/hyperliquid`（上游 `wss://api.hyperliquid.xyz/ws`，帧原样转发）。
///
/// - 连上后每本发两句订阅：
///   `{"method":"subscribe","subscription":{"type":"l2Book","coin":"BTC","nSigFigs":4}}` 与
///   `{"method":"subscribe","subscription":{"type":"trades","coin":"BTC"}}`。一条连接最多 `maxBooks` 本。
/// - `l2Book` 每一帧都是整本簿（每侧 20 档，价格按 4 位有效数字聚合成格：BTC 10、ETH 1、SOL 0.1、kPEPE 1e-6），
///   没有序号、不推增量 → 序号模型 `snapshotOnly`：每帧整本替换，`data.time` 只当事件时间与 `lastUpdateID`。
///   快照标 `slidingWindow`（20 档以外不知道）。
/// - `trades` 的 `side` 是主动方（`B` 吃卖盘，`A` 吃买盘）。
/// - 每 30 秒发一句 `{"method":"ping"}`；回来的 `{"channel":"pong"}` 与订阅回执 `subscriptionResponse` 解码直接忽略。
///   冷门币可能很久没有成交、盘口也不动（整本没变就不推），所以 60 秒没帧才算断（`silenceMs`）。
/// - 数量是币数（`kPEPE` 是千枚），名义美元由 `OrderFlowNotional` 换。
public struct HyperliquidBookAdapter: DepthFeedAdapter {
  /// 一条连接最多几本（中继的订阅配额：一本 l2Book + trades 两个）。
  public static let maxBooks = 8
  /// `l2Book` 每侧 20 档。
  public static let snapshotLevels = 20
  /// 价格聚合位数（4 位有效数字，档距够宽、20 档覆盖得开）。
  public static let significantFigures = 4
  static let relayPath = "/v1/market/ws/hyperliquid"
  static let pingEveryMs: Double = 30_000
  static let pingText = #"{"method":"ping"}"#
  static let silence: Double = 60_000

  public let books: [DepthBook]
  /// kanpan-api 主机（`MarketRoute.apiHosts`，主在前）。
  let gateways: [String]
  let sockets: any WSSocketFactory
  private let byCoin: [String: DepthBook]

  public init(books: [DepthBook], gateways: [String],
              sockets: any WSSocketFactory = URLSessionSocketFactory()) {
    self.books = Array(books.prefix(Self.maxBooks))
    self.gateways = gateways; self.sockets = sockets
    var map: [String: DepthBook] = [:]
    for book in self.books { map[book.venue.instrument] = book }
    byCoin = map
  }

  public var name: String { "Hyperliquid \(books.map(\.venue.instrument).joined(separator: ","))" }

  public var streamURLs: [URL] { Self.gatewayStreams(gateways, path: Self.relayPath, streams: []) }

  public var keepAlive: DepthKeepAlive? { DepthKeepAlive(text: Self.pingText, everyMs: Self.pingEveryMs) }

  public var silenceMs: Double? { Self.silence }

  static func message(_ method: String, type: String, coin: String) -> String? {
    var subscription: [String: Any] = ["type": type, "coin": coin]
    if type == "l2Book" { subscription["nSigFigs"] = significantFigures }
    let obj: [String: Any] = ["method": method, "subscription": subscription]
    guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return nil }
    return String(decoding: data, as: UTF8.self)
  }

  var subscribeMessages: [String] {
    books.flatMap { book in
      ["l2Book", "trades"].compactMap { Self.message("subscribe", type: $0, coin: book.venue.instrument) }
    }
  }

  /// 单本重订：退订再订这一本的 `l2Book`（每帧整本，本来就不会接不上；留着给 `.reset` 之类兜底）。
  public func resubscribeMessages(venueID: String) -> [String]? {
    guard let book = books.first(where: { $0.id == venueID }) else { return nil }
    let out = ["unsubscribe", "subscribe"].compactMap { Self.message($0, type: "l2Book", coin: book.venue.instrument) }
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
    guard let frame = DepthWire.object(text) else { return [] }
    switch frame["channel"] as? String {
    case "l2Book": return decodeBook(frame["data"])
    case "trades": return decodeTrades(frame["data"])
    default: return []
    }
  }

  private func decodeBook(_ raw: Any?) -> [VenueMessage] {
    guard let data = raw as? [String: Any], let coin = data["coin"] as? String, let book = byCoin[coin],
          let time = DepthWire.integer(data["time"]),
          let sides = data["levels"] as? [Any], sides.count == 2,
          let bids = levels(sides[0], book), let asks = levels(sides[1], book),
          bids.count <= Self.snapshotLevels, asks.count <= Self.snapshotLevels else { return [] }
    return [VenueMessage(book.id, .snapshot(BookSnapshot(lastUpdateID: time, requestedLevels: Self.snapshotLevels,
                                                         bids: bids, asks: asks, eventTimeMs: time,
                                                         slidingWindow: true)))]
  }

  /// 一侧 `[{"px","sz","n"}]` → `[[px, sz]]` 交给簿统一换算（价格口径、数量口径）。
  private func levels(_ raw: Any, _ book: DepthBook) -> [BookLevel]? {
    guard let items = raw as? [[String: Any]] else { return nil }
    var pairs: [[Any]] = []
    pairs.reserveCapacity(items.count)
    for item in items {
      guard let px = item["px"], let sz = item["sz"] else { return nil }
      pairs.append([px, sz])
    }
    return book.levels(pairs)
  }

  private func decodeTrades(_ raw: Any?) -> [VenueMessage] {
    guard let items = raw as? [[String: Any]] else { return [] }
    var out: [VenueMessage] = []
    for t in items {
      guard let coin = t["coin"] as? String, let book = byCoin[coin] else { continue }
      // 价量解得开却不是有限值或越界：整帧丢掉并记一笔（坏帧里别的成交同样不可信）。
      guard let p = DepthWire.number(t["px"]), let q = DepthWire.number(t["sz"]),
            p > 0, q >= 0, p.isFinite, q.isFinite else { WireNumber.noteDropped(); return [] }
      guard q > 0, let side = t["side"] as? String, side == "B" || side == "A" else { continue }
      out.append(VenueMessage(book.id, .trade(book.trade(price: p, quantity: q, hit: side == "B" ? .ask : .bid,
                                                         timeMs: DepthWire.integer(t["time"]) ?? 0))))
    }
    return out
  }
}
