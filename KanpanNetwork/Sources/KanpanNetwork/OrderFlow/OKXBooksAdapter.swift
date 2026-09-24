import Foundation
import KanpanCore

/// OKX 一条连接上的几本簿（现货 `BTC-USDT`、U 本位永续 `BTC-USDT-SWAP`、币本位永续 `BTC-USD-SWAP`、
/// 交割 `BTC-USD-260925`……），不分线路一律经 kanpan-api 的中继 `/v1/market/ws/okx`
/// （上游 `wss://ws.okx.com:8443/ws/v5/public`，帧原样转发）——手机在国内直连不了 OKX。
///
/// - 连上后自己发订阅：`{"op":"subscribe","args":[{"channel":"books","instId":…},{"channel":"trades",…}]}`。
///   中继一条订阅消息最多 12 个 args、一条连接最多同时订 24 个，所以一条连接最多 `maxBooks` 本，
///   一条消息最多 6 本。
/// - `books`（400 档）首帧 `action=snapshot`（prevSeqId = -1），之后 `update` 按各自 instId 的
///   seqId / prevSeqId 首尾相接；序号倒退（OKX 那边重置过）就整本重来。
///   checksum 不校验，只靠序号。
/// - 数量原样给（现货是币数，永续 / 交割是张数），名义美元由 `OrderFlowNotional` 按面值换
///   （正向 price × 张数 × ctVal，反向 张数 × 面值）。
/// - `trades` 的 `side` 是主动方（buy 吃卖盘）。
/// - OKX 30 秒没有帧就断，冷门交割可能半分钟没有变动，所以每 20 秒发一句 `ping`（中继只放行这一句），
///   回来的 `pong` 不是 JSON，解码直接忽略。
///
/// 解码对应原项目 `bit-orderbook-okx/src/lib.rs:878 decode_depth_message`。
public struct OKXBooksAdapter: DepthFeedAdapter {
  public static let snapshotLevels = 400
  /// 一条连接最多几本（中继 MAX_OKX_SUBSCRIPTIONS = 24，一本 books + trades 两个）。
  public static let maxBooks = 12
  /// 一条订阅消息最多几本（中继 MAX_OKX_ARGS = 12）。
  static let booksPerMessage = 6
  static let relayPath = "/v1/market/ws/okx"
  static let pingEveryMs: Double = 20_000

  public let books: [DepthBook]
  /// 网关候选（`MarketRoute.gateways`，主在前）。
  let gateways: [String]
  let sockets: any WSSocketFactory
  private let byInstrument: [String: DepthBook]

  public init(books: [DepthBook], gateways: [String],
              sockets: any WSSocketFactory = URLSessionSocketFactory()) {
    self.books = Array(books.prefix(Self.maxBooks))
    self.gateways = gateways; self.sockets = sockets
    var map: [String: DepthBook] = [:]
    for book in self.books { map[book.venue.instrument] = book }
    byInstrument = map
  }

  public var name: String { "OKX \(books.map(\.venue.instrument).joined(separator: ","))" }

  public var streamURLs: [URL] { Self.gatewayStreams(gateways, path: Self.relayPath, streams: []) }

  public var keepAlive: DepthKeepAlive? { DepthKeepAlive(text: "ping", everyMs: Self.pingEveryMs) }

  /// 订阅消息（一条最多 `booksPerMessage` 本）。
  var subscribeMessages: [String] {
    stride(from: 0, to: books.count, by: Self.booksPerMessage).compactMap { start in
      let chunk = books[start..<min(start + Self.booksPerMessage, books.count)]
      let args: [[String: String]] = chunk.flatMap { book in
        [["channel": "books", "instId": book.venue.instrument],
         ["channel": "trades", "instId": book.venue.instrument]]
      }
      let obj: [String: Any] = ["op": "subscribe", "args": args]
      guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return nil }
      return String(decoding: data, as: UTF8.self)
    }
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
    guard let message = DepthWire.object(text), message["event"] == nil,
          let arg = message["arg"] as? [String: Any],
          let instID = arg["instId"] as? String, let book = byInstrument[instID],
          let items = message["data"] as? [[String: Any]] else { return [] }
    switch arg["channel"] as? String {
    case "trades":
      return items.compactMap { t in
        guard let p = DepthWire.number(t["px"]), let q = DepthWire.number(t["sz"]),
              p > 0, q > 0, p.isFinite, q.isFinite,
              let side = t["side"] as? String, side == "buy" || side == "sell" else { return nil }
        return VenueMessage(book.id, .trade(book.trade(price: p, quantity: q, hit: side == "buy" ? .ask : .bid,
                                                       timeMs: DepthWire.integer(t["ts"]) ?? 0)))
      }
    case "books":
      guard let action = message["action"] as? String, items.count == 1 else { return [] }
      let item = items[0]
      guard let seq = DepthWire.integer(item["seqId"]),
            let bids = book.levels(item["bids"]), let asks = book.levels(item["asks"]) else { return [] }
      let time = DepthWire.integer(item["ts"])
      switch action {
      case "snapshot":
        return [VenueMessage(book.id, .snapshot(BookSnapshot(lastUpdateID: seq, requestedLevels: Self.snapshotLevels,
                                                             bids: bids, asks: asks, eventTimeMs: time)))]
      case "update":
        guard let previous = DepthWire.integer(item["prevSeqId"]) else { return [] }
        // 序号倒退：OKX 那边重置过，整本重来。
        if seq < previous { return [VenueMessage(book.id, .reset)] }
        return [VenueMessage(book.id, .delta(BookDelta(firstUpdateID: seq, finalUpdateID: seq,
                                                      previousFinalUpdateID: previous,
                                                      bids: bids, asks: asks, eventTimeMs: time ?? 0)))]
      default:
        return []
      }
    default:
      return []
    }
  }
}
