import Foundation
import KanpanCore

/// OKX 行情推送的协议（交给通用的 `VenueStream`）。一个 `OKXWire` 只管一个端点：
/// public（`tickers` / `trades` / `mark-price` / `funding-rate`）或 business（`candle*`）——
/// OKX 的 K 线频道只在 business 端点上。`OKXProvider.makeStream` 各开一条，用 `SplitVenueStream` 合成一条。
///
/// - 订阅 `{"op":"subscribe","args":[{"channel":"tickers","instId":"BTC-USDT-SWAP"},…]}`，
///   一帧最多 12 个 args（中继的放行上限），可以混着频道；切品种只发 `unsubscribe` / `subscribe`，不重连。
///   帧里只有 `op` 与 `args`：中继按 `deny_unknown_fields` 校验，多一个键整帧丢掉。
/// - 回执 `{"event":"subscribe","arg":{…}}` 算这一个订阅生效；数据帧 `{"arg":{…},"data":[…]}`。
/// - 报错 `{"event":"error","code":"60012","msg":"…"}` 不说是哪个订阅，归到最近一发控制帧上（`VenueStream` 管）。
/// - 保活：每 20 秒发字面量 `ping`，回字面量 `pong`（OKX 30 秒没有帧就断）。
///
/// 网关线路上连的是 kanpan-api 的中继 `/v1/market/ws/okx[?endpoint=business]`，帧原样转发。
public struct OKXWire: VenueWire {
  /// 订阅的最小单位：一个频道上的一个 instId。
  public struct Sub: Hashable, Comparable, Sendable {
    var channel: String
    var instID: String
    public static func < (a: Sub, b: Sub) -> Bool { (a.channel, a.instID) < (b.channel, b.instID) }
  }

  public let endpoint: OKXVenue.Endpoint
  /// 这条连接上记着的最近一笔资金费率（`mark-price` 帧捎上它）。
  let memo = OKXDTO.FundingMemo()

  public init(endpoint: OKXVenue.Endpoint) { self.endpoint = endpoint }

  public var name: String { "\(OKXVenue.displayName) \(endpoint.rawValue)" }
  public var controlGapMs: Double { OKXVenue.controlGapMs }
  public var keepAlive: VenueKeepAlive? { VenueKeepAlive(text: OKXVenue.pingText, everyMs: OKXVenue.pingEveryMs) }

  /// 上层的订阅落在哪个端点上。没有对应频道的（主动成交、五档盘口：能力位里就没有）给 nil。
  public static func endpoint(of topic: StreamTopic) -> OKXVenue.Endpoint? {
    switch topic {
    case .kline(_, let iv): OKXVenue.candleChannel(iv) == nil ? nil : .business
    case .ticker, .markPrice, .trade: .public
    case .aggTrade, .depth: nil
    }
  }

  /// 订阅 → 频道。不在这个端点上的、没有对应频道的直接丢掉。标记价连带订资金费率（OKX 分成两个频道）。
  public func subs(_ topics: [StreamTopic]) -> Set<Sub> {
    var out = Set<Sub>()
    for topic in topics where Self.endpoint(of: topic) == endpoint {
      let inst = OKXVenue.instID(topic.symbol)
      switch topic {
      case .kline(_, let iv):
        if let channel = OKXVenue.candleChannel(iv) { out.insert(Sub(channel: channel, instID: inst)) }
      case .ticker: out.insert(Sub(channel: "tickers", instID: inst))
      case .markPrice:
        out.insert(Sub(channel: "mark-price", instID: inst))
        out.insert(Sub(channel: "funding-rate", instID: inst))
      case .trade: out.insert(Sub(channel: "trades", instID: inst))
      case .aggTrade, .depth: break
      }
    }
    return out
  }

  /// 一帧最多 `maxArgsPerFrame` 个，频道可以混着。
  public func nextBatch(_ pending: Set<Sub>) -> [Sub] {
    Array(pending.sorted().prefix(OKXVenue.maxArgsPerFrame))
  }

  public func control(_ op: VenueControl, _ subs: [Sub]) throws -> String {
    try Self.control(op.rawValue, subs.map { ($0.channel, $0.instID) })
  }

  public func decode(_ text: String) -> VenueWireFrame<Sub> {
    guard text != OKXVenue.pongText, let frame = OKXDTO.Frame(text) else { return .ignored }
    switch frame.event {
    case "error"?:
      let message = frame.msg ?? String(text.prefix(200))
      return VenueWireFrame(error: "\(frame.code ?? "?") \(message)", rejected: Self.named(in: message))
    case "subscribe"?:
      guard let channel = frame.channel, let inst = frame.instID else { return .ignored }
      return VenueWireFrame(confirmed: [Sub(channel: channel, instID: inst)])
    case .some:
      // unsubscribe 回执、notice（服务升级前的预告）、channel-conn-count：只说明连接活着。
      return .ignored
    case nil:
      guard let channel = frame.channel, let inst = frame.instID else { return .ignored }
      return VenueWireFrame(payloads: OKXDTO.payloads(frame, memo: memo),
                            confirmed: [Sub(channel: channel, instID: inst)])
    }
  }

  /// 报错正文里点了名的那一个订阅。OKX 对不存在的品种 / 频道回
  /// `60018 Wrong URL or channel:tickers,instId:FOO-USDT-SWAP doesn't exist…`；认不出就是 nil
  /// （归到最近一发控制帧上，一帧最多 12 个）。
  static func named(in message: String) -> [Sub]? {
    guard let c = message.range(of: "channel:"), let i = message.range(of: ",instId:", range: c.upperBound..<message.endIndex) else {
      return nil
    }
    let channel = String(message[c.upperBound..<i.lowerBound])
    let inst = String(message[i.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "-" })
    guard !channel.isEmpty, !inst.isEmpty, !channel.contains(" ") else { return nil }
    return [Sub(channel: channel, instID: inst)]
  }

  public func label(_ sub: Sub) -> String { "\(sub.channel) \(sub.instID)" }

  /// OKX 的控制帧（行情推送与订单流那条连接共用这一种写法）：只有 `op` 与 `args` 两个键。
  static func control(_ op: String, _ args: [(channel: String, instID: String)]) throws -> String {
    let obj: [String: Any] = ["op": op, "args": args.map { ["channel": $0.channel, "instId": $0.instID] }]
    return String(decoding: try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]), as: UTF8.self)
  }
}
