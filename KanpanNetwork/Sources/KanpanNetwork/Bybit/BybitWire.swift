import Foundation
import KanpanCore

/// Bybit 行情推送的协议（交给通用的 `VenueStream`）。
///
/// 一条连接、多个订阅：`{"op":"subscribe","args":["tickers.BTCUSDT","kline.1.BTCUSDT","publicTrade.BTCUSDT"]}`，
/// 一条最多 10 个 args；切品种只发 `unsubscribe` / `subscribe`，不重连。每 20 秒发一句 `{"op":"ping"}`。
/// 订阅的最小单位就是 Bybit 的 topic 字符串（`tickers.BTCUSDT`）。
///
/// - 24h 行情与标记价是同一个频道 `tickers.*`（标记价、指数价、费率、下次结算都在里面），delta 只带变化的字段，
///   由 `BybitDTO.TickerBook` 按品种合并（一条连接一份）。
/// - K 线：14 档里除了 1y 都有原生推送；没有原生档的（1y）订逐笔在本地拼末根。
/// - 没有盘口与主动方向这一层（能力位 `hasMicrostructure = false`），`aggTrade` / `depth` 不订。
///
/// 网关线路上连的是 kanpan-api 的中继（`/v1/market/ws/bybit?category=linear`），帧原样转发。
public struct BybitWire: VenueWire {
  public typealias Sub = String

  /// `tickers.*` 的合并簿（同一条连接上所有品种共用）。
  let tickers: BybitDTO.TickerBook

  public init() { tickers = BybitDTO.TickerBook() }

  public var name: String { BybitVenue.displayName }
  public var controlGapMs: Double { BybitVenue.controlGapMs }
  public var keepAlive: VenueKeepAlive? { VenueKeepAlive(text: BybitVenue.pingText, everyMs: BybitVenue.pingEveryMs) }

  public func subs(_ topics: [StreamTopic]) -> Set<String> {
    var out = Set<String>()
    for topic in topics {
      let symbol = BybitVenue.symbol(topic.symbol)
      switch topic {
      case .kline(_, let iv):
        if let wire = BybitVenue.interval(iv) { out.insert(BybitVenue.klineTopic(wire, symbol)) }
        else { out.insert(BybitVenue.tradeTopic(symbol)) }
      case .trade: out.insert(BybitVenue.tradeTopic(symbol))
      case .ticker, .markPrice: out.insert(BybitVenue.tickerTopic(symbol))
      case .aggTrade, .depth: break
      }
    }
    return out
  }

  /// 一帧最多 10 个 args，按 topic 排序取前面那些。
  public func nextBatch(_ pending: Set<String>) -> [String] {
    Array(pending.sorted().prefix(BybitVenue.maxArgsPerMessage))
  }

  public func control(_ op: VenueControl, _ subs: [String]) throws -> String {
    try Self.control(op.rawValue, subs)
  }

  public func decode(_ text: String) -> VenueWireFrame<String> {
    let frame = BybitDTO.wire(text, tickers: tickers)
    return VenueWireFrame(payloads: frame.payloads, confirmed: frame.confirmed,
                          error: frame.error, rejected: frame.rejected)
  }

  public func label(_ sub: String) -> String { sub }

  /// Bybit 的控制帧（行情推送与订单流那条连接共用这一种写法）：`{"args":[…],"op":"subscribe"}`。
  static func control(_ op: String, _ args: [String]) throws -> String {
    let obj: [String: Any] = ["op": op, "args": args]
    return String(decoding: try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]), as: UTF8.self)
  }
}
