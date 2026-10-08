import Foundation
import KanpanCore

/// Coinbase 行情推送的协议（交给通用的 `VenueStream`）。
///
/// 连上之后先订一个 `heartbeats` 频道：Coinbase 对一段时间没有任何消息的订阅会主动断开，心跳每秒一帧，
/// 顺带就是「传输层还通着」的证据。之后按频道发 `{"type":"subscribe","channel":…,"product_ids":[…]}`，
/// 一帧只说一个频道；切品种只发 `unsubscribe` / `subscribe`，不重连。
/// `{"type":"error"}` 帧不说是哪个品种，归到最近一发控制帧上（`VenueStream` 管）。
///
/// 网关线路上连的是 kanpan-api 的 hub，它说的是和 Coinbase 一模一样的协议。
public struct CoinbaseWire: VenueWire {
  /// 订阅的最小单位：一个频道上的一个品种。
  public struct Sub: Hashable, Comparable, Sendable {
    var channel: String
    var product: String
    public static func < (a: Sub, b: Sub) -> Bool { (a.channel, a.product) < (b.channel, b.product) }
  }

  private static let decoder = JSONDecoder()

  public init() {}

  public var name: String { CoinbaseVenue.displayName }
  public var controlGapMs: Double { CoinbaseVenue.controlGapMs }

  /// 订阅 → 频道。没有对应频道的（标记价、盘口……能力位里就没有）直接忽略。
  public func subs(_ topics: [StreamTopic]) -> Set<Sub> {
    var out = Set<Sub>()
    for topic in topics {
      let product = CoinbaseVenue.productID(topic.symbol)
      switch topic {
      case .kline(_, let iv) where iv == CoinbaseVenue.candleInterval: out.insert(Sub(channel: "candles", product: product))
      case .kline, .trade: out.insert(Sub(channel: "market_trades", product: product))
      case .ticker: out.insert(Sub(channel: "ticker", product: product))
      case .markPrice, .aggTrade, .depth: break
      }
    }
    return out
  }

  /// 一帧只说一个频道：挑排序最前的那个频道，把它的品种都放进去。
  public func nextBatch(_ pending: Set<Sub>) -> [Sub] {
    guard let channel = pending.min()?.channel else { return [] }
    return pending.filter { $0.channel == channel }.sorted()
  }

  public func control(_ op: VenueControl, _ subs: [Sub]) throws -> String {
    try Self.control(op.rawValue, channel: subs.first?.channel ?? "", products: subs.map(\.product))
  }

  public func openingFrames() throws -> [String] {
    [try Self.control("subscribe", channel: "heartbeats", products: [])]
  }

  public func decode(_ text: String) -> VenueWireFrame<Sub> {
    guard let data = text.data(using: .utf8),
          let frame = try? Self.decoder.decode(CoinbaseDTO.Frame.self, from: data) else { return .ignored }
    if frame.type == "error" {
      return VenueWireFrame(error: frame.message ?? String(text.prefix(200)))
    }
    return VenueWireFrame(
      payloads: CoinbaseDTO.payloads(frame, candleInterval: CoinbaseVenue.candleInterval),
      confirmed: CoinbaseDTO.confirmedSubs(frame).map { Sub(channel: $0.channel, product: $0.product) })
  }

  public func label(_ sub: Sub) -> String { "\(sub.channel) \(sub.product)" }

  /// Coinbase 的控制帧（行情推送与订单流那条连接共用这一种写法）。
  static func control(_ type: String, channel: String, products: [String]) throws -> String {
    var obj: [String: Any] = ["type": type, "channel": channel]
    if !products.isEmpty { obj["product_ids"] = products }
    return String(decoding: try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]), as: UTF8.self)
  }
}
