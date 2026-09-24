import Foundation
import KanpanCore

/// Coinbase 现货的 `level2`：流内 snapshot + update，恒走直连（网关的 Coinbase hub 不收 level2）。
/// 一条连接只放一本簿：`sequence_num` 是整条连接的序号，放两本就分不清谁断了档。
///
/// - 同一条连接订 `level2`、`market_trades`、`heartbeats`。`sequence_num` 是**整条连接**的序号，
///   所以心跳、订阅回执、成交帧也各发一条空增量把序号推过去，否则本地簿会误判断档。
/// - l2 的 `side` 是 `bid` / `offer`；snapshot 的请求档数记成两侧较多的一侧 + 1（整本都在）。
/// - `market_trades` 的 `side` 是主动方（BUY 吃卖盘）；只收 `update`，开头那份 `snapshot` 是旧成交，不计。
///
/// 解码对应原项目 `bit-orderbook-coinbase/src/lib.rs:709` 与 `:869`。
public struct CoinbaseLevel2Adapter: DepthFeedAdapter {
  public static let streamURL = URL(string: "wss://\(CoinbaseEndpoints.streamHost)")!

  public let book: DepthBook
  public var books: [DepthBook] { [book] }
  /// Coinbase 的产品代号（`BTC-USD`）。
  var symbol: String { book.venue.instrument }
  let sockets: any WSSocketFactory

  public init(book: DepthBook, sockets: any WSSocketFactory = URLSessionSocketFactory()) {
    self.book = book
    self.sockets = sockets
  }

  public var name: String { "Coinbase \(symbol)" }

  public var streamURLs: [URL] { [Self.streamURL] }

  public func connect(candidate: Int) async throws -> any WSSocket {
    let socket = try await sockets.connect(to: Self.streamURL)
    do {
      for (channel, products) in [("level2", [symbol]), ("market_trades", [symbol]), ("heartbeats", [])] {
        var obj: [String: Any] = ["type": "subscribe", "channel": channel]
        if !products.isEmpty { obj["product_ids"] = products }
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        try await socket.send(String(decoding: data, as: UTF8.self))
      }
    } catch {
      await socket.cancel()
      throw error
    }
    return socket
  }

  public func decode(_ text: String) -> [VenueMessage] {
    decodeMessages(text).map { VenueMessage(book.id, $0) }
  }

  private func decodeMessages(_ text: String) -> [DepthMessage] {
    guard let frame = DepthWire.object(text), let seq = DepthWire.integer(frame["sequence_num"]) else { return [] }
    let advance = DepthMessage.delta(BookDelta(firstUpdateID: seq, finalUpdateID: seq, previousFinalUpdateID: nil))
    let events = frame["events"] as? [[String: Any]] ?? []
    switch frame["channel"] as? String {
    case "l2_data", "level2":
      var bids: [BookLevel] = [], asks: [BookLevel] = []
      var snapshot = false
      var time: Int64?
      for event in events where (event["product_id"] as? String) == symbol {
        if event["type"] as? String == "snapshot" { snapshot = true; bids = []; asks = [] }
        for u in event["updates"] as? [[String: Any]] ?? [] {
          guard let p = DepthWire.number(u["price_level"]), let q = DepthWire.number(u["new_quantity"]),
                p > 0, q >= 0, p.isFinite, q.isFinite else { continue }
          let level = BookLevel(price: p * book.priceFactor, quantity: q * book.quantityFactor)
          switch u["side"] as? String {
          case "bid": bids.append(level)
          case "offer", "ask": asks.append(level)
          default: continue
          }
          if let t = (u["event_time"] as? String).flatMap(CoinbaseDTO.isoMs) { time = max(time ?? t, t) }
        }
      }
      if snapshot {
        return [.snapshot(BookSnapshot(lastUpdateID: seq, requestedLevels: max(bids.count, asks.count) + 1,
                                       bids: bids, asks: asks, eventTimeMs: time))]
      }
      return [.delta(BookDelta(firstUpdateID: seq, finalUpdateID: seq, previousFinalUpdateID: nil,
                               bids: bids, asks: asks, eventTimeMs: time ?? 0))]
    case "market_trades":
      var out = [advance]
      for event in events where event["type"] as? String == "update" {
        for t in event["trades"] as? [[String: Any]] ?? [] {
          guard (t["product_id"] as? String) == symbol,
                let p = DepthWire.number(t["price"]), let q = DepthWire.number(t["size"]), p > 0, q > 0 else { continue }
          let hit: BookSide
          switch (t["side"] as? String)?.uppercased() {
          case "BUY": hit = .ask
          case "SELL": hit = .bid
          default: continue
          }
          out.append(.trade(book.trade(price: p, quantity: q, hit: hit,
                                       timeMs: (t["time"] as? String).flatMap(CoinbaseDTO.isoMs) ?? 0)))
        }
      }
      return out
    default:
      // 心跳、订阅回执：只推进序号。
      return [advance]
    }
  }
}
