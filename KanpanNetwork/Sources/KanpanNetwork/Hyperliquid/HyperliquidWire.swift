import Foundation
import KanpanCore

/// Hyperliquid 行情推送的协议（交给通用的 `VenueStream`）。
///
/// - 一帧只说一个订阅：`{"method":"subscribe","subscription":{"type":"candle","coin":"BTC","interval":"1m"}}`、
///   `{"type":"trades","coin":"BTC"}`、`{"type":"activeAssetCtx","coin":"BTC"}`；退订把 `method` 换成 `unsubscribe`。
///   coin 一律是上游原名（`kPEPE`），由 `HyperliquidVenue.coin` 从品种键译回。
/// - 24h 行情与标记价都来自 `activeAssetCtx`（价、额、标记价、持仓量、费率一帧全有），两个订阅合成一个；
///   每一帧同时出一条 `Ticker` 和一条标记价（带一小时费率与下一个整点）。
/// - 订上 `trades` 后第一帧是最近成交的回放，那些成交早就在 REST 的 K 线里了，再折一次成交量就重复了：
///   订阅发出之后第一帧里早于发出时刻的成交丢掉（经网关时 hub 可能已经替别人订着、不再回放，所以按时刻判，不整帧丢）。
/// - 保活每 20 秒 `{"method":"ping"}`，回来的 `{"channel":"pong"}` 是空帧。
/// - `error` 帧：正文里贴着出错的订阅就点名，`Already subscribed` 当作已生效；中继认不出的上行直接丢（不回错），
///   由 `VenueStream` 的首帧窗口兜底。
///
/// 网关线路上连的是 kanpan-api 的中继 `/v1/market/ws/hyperliquid`，帧与直连一字不差。
public struct HyperliquidWire: VenueWire {
  /// 订阅的最小单位：一个频道上的一个币（K 线再带周期）。
  public struct Sub: Hashable, Comparable, Sendable {
    var type: String
    var coin: String
    var interval: String?
    public static func < (a: Sub, b: Sub) -> Bool {
      (a.type, a.coin, a.interval ?? "") < (b.type, b.coin, b.interval ?? "")
    }

    static func candle(_ coin: String, _ interval: String) -> Sub { Sub(type: "candle", coin: coin, interval: interval) }
    static func trades(_ coin: String) -> Sub { Sub(type: "trades", coin: coin) }
    static func assetCtx(_ coin: String) -> Sub { Sub(type: "activeAssetCtx", coin: coin) }

    init(type: String, coin: String, interval: String? = nil) {
      self.type = type; self.coin = coin; self.interval = type == "candle" ? interval : nil
    }

    init?(_ s: HyperliquidDTO.Subscription) {
      switch s.type {
      case "candle":
        guard let iv = s.interval else { return nil }
        self.init(type: s.type, coin: s.coin, interval: iv)
      case "trades", "activeAssetCtx": self.init(type: s.type, coin: s.coin)
      default: return nil
      }
    }
  }

  /// 刚发出 `trades` 订阅、还在等回放帧的币 → 发出时刻（毫秒）。`decode` 不能改值类型，所以放在引用里；
  /// 一个 `VenueStream` 一份（`makeStream` 每次新建一个 wire）。
  final class Replays: @unchecked Sendable {
    private let lock = NSLock()
    private var since: [String: Int64] = [:]
    func reset() { lock.lock(); since = [:]; lock.unlock() }
    func arm(_ coin: String, at ms: Int64) { lock.lock(); since[coin] = ms; lock.unlock() }
    func disarm(_ coin: String) { lock.lock(); since[coin] = nil; lock.unlock() }
    /// 这一帧是不是订上之后的第一帧：是就交出发出时刻，并把这个币放下。
    func take(_ coin: String) -> Int64? {
      lock.lock(); defer { lock.unlock() }
      return since.removeValue(forKey: coin)
    }
  }

  private let replays = Replays()
  let names: HyperliquidNames
  let clock: @Sendable () -> Date

  public init() { self.init(names: HyperliquidVenue.names, clock: { Date() }) }
  init(names: HyperliquidNames, clock: @escaping @Sendable () -> Date) { self.names = names; self.clock = clock }

  private var nowMs: Int64 { Int64(clock().timeIntervalSince1970 * 1000) }

  public var name: String { HyperliquidVenue.displayName }
  public var controlGapMs: Double { HyperliquidVenue.controlGapMs }
  public var keepAlive: VenueKeepAlive? {
    VenueKeepAlive(text: HyperliquidVenue.pingText, everyMs: HyperliquidVenue.streamPingEveryMs)
  }

  /// 上层的订阅 → 这一家的订阅。没有对应频道的（主动成交、盘口——能力位里本来就没有；6h 这类聚出来的周期）丢掉。
  public func subs(_ topics: [StreamTopic]) -> Set<Sub> {
    var out = Set<Sub>()
    for topic in topics {
      let coin = HyperliquidVenue.coin(topic.symbol, names: names)
      switch topic {
      case .kline(_, let iv):
        if let name = HyperliquidVenue.interval(iv) { out.insert(.candle(coin, name)) }
      case .trade: out.insert(.trades(coin))
      case .ticker, .markPrice: out.insert(.assetCtx(coin))
      case .aggTrade, .depth: break
      }
    }
    return out
  }

  /// Hyperliquid 一帧只能说一个订阅。
  public func nextBatch(_ pending: Set<Sub>) -> [Sub] {
    pending.min().map { [$0] } ?? []
  }

  public func control(_ op: VenueControl, _ subs: [Sub]) throws -> String {
    guard let sub = subs.first else { throw FeedError.badResponse("空的订阅") }
    if sub.type == "trades" {
      if op == .subscribe { replays.arm(sub.coin, at: nowMs) } else { replays.disarm(sub.coin) }
    }
    return try Self.control(op.rawValue, sub)
  }

  /// 新连接：上一条连接上等着的回放作废（这条连接上的订阅会重新发一遍、重新记）。
  public func openingFrames() throws -> [String] {
    replays.reset()
    return []
  }

  public func decode(_ text: String) -> VenueWireFrame<Sub> {
    guard let frame = HyperliquidDTO.frame(text) else { return .ignored }
    switch frame.channel {
    case "candle":
      var payloads: [StreamPayload] = []
      var confirmed: [Sub] = []
      for row in HyperliquidDTO.candles(frame.data) {
        // 周期认不出（不是看盘 14 档里 Hyperliquid 原生的那几档）：整帧丢。原来原样塞进 `KlineEvent.interval`，
        // 上层拿一个不存在的周期名去找图。
        guard let iv = Interval(rawValue: row.interval), HyperliquidVenue.interval(iv) == row.interval else {
          WireNumber.noteDropped()
          return .ignored
        }
        confirmed.append(.candle(row.coin, row.interval))
        payloads.append(.kline(KlineEvent(symbol: HyperliquidVenue.key(row.coin), interval: row.interval,
                                          openTime: row.bar.openTime, closed: false, bar: row.bar,
                                          eventTime: nowMs)))
      }
      return VenueWireFrame(payloads: payloads, confirmed: confirmed)

    case "trades":
      guard let trades = HyperliquidDTO.trades(frame.data) else { return .ignored }
      var payloads: [StreamPayload] = []
      var confirmed = Set<Sub>()
      var since: [String: Int64] = [:]
      for t in trades {
        // 每个币这一帧只问一次：是不是订上之后的第一帧。
        if confirmed.insert(.trades(t.coin)).inserted, let sentMs = replays.take(t.coin) { since[t.coin] = sentMs }
        // 订上之后的第一帧：早于订阅发出时刻的是回放，不收。
        if let sentMs = since[t.coin], t.timeMs < sentMs { continue }
        guard t.size > 0 else { continue }
        payloads.append(.trade(TradeEvent(symbol: HyperliquidVenue.key(t.coin), price: t.price, qty: t.size,
                                          timeMs: t.timeMs, tradeID: t.tid)))
      }
      // 同一帧里是按时间升序的，保险起见再排一次（`sort` 是稳定的）。
      payloads.sort { a, b in
        guard case .trade(let x) = a, case .trade(let y) = b else { return false }
        return x.timeMs < y.timeMs
      }
      return VenueWireFrame(payloads: payloads, confirmed: confirmed.sorted())

    case "activeAssetCtx":
      guard let update = HyperliquidDTO.assetCtx(frame.data) else { return .ignored }
      let coin = update.coin, ctx = update.ctx
      let now = nowMs
      var payloads: [StreamPayload] = []
      if let ticker = HyperliquidDTO.ticker(coin: coin, ctx: ctx, timeMs: now) { payloads.append(.ticker(ticker)) }
      if let mark = ctx.markPx, mark > 0 {
        payloads.append(.markPrice(symbol: HyperliquidVenue.key(coin), price: mark,
                                   tick: HyperliquidDTO.markTick(ctx, nowMs: now)))
      }
      return VenueWireFrame(payloads: payloads, confirmed: [.assetCtx(coin)])

    case "subscriptionResponse":
      guard let s = HyperliquidDTO.subscribed(frame.data), let sub = Sub(s) else { return .ignored }
      return VenueWireFrame(confirmed: [sub])

    case "error":
      let message = (frame.data as? String) ?? String(text.prefix(200))
      let named = HyperliquidDTO.errorSubscription(message).flatMap(Sub.init)
      // 重发订阅撞上「已经订着」：说明它是生效的，不是被拒。
      if message.localizedCaseInsensitiveContains("already subscribed") {
        return named.map { VenueWireFrame(confirmed: [$0]) } ?? .ignored
      }
      return VenueWireFrame(error: message, rejected: named.map { [$0] })

    default:
      // pong 以及别的频道：只说明连接活着。
      return .ignored
    }
  }

  public func label(_ sub: Sub) -> String {
    sub.interval.map { "\(sub.type) \(sub.coin) \($0)" } ?? "\(sub.type) \(sub.coin)"
  }

  /// Hyperliquid 的控制帧。字段与中继白名单一一对得上（多一个字段中继就丢）。
  static func control(_ method: String, _ sub: Sub) throws -> String {
    var subscription: [String: Any] = ["type": sub.type, "coin": sub.coin]
    if let iv = sub.interval { subscription["interval"] = iv }
    let obj: [String: Any] = ["method": method, "subscription": subscription]
    return String(decoding: try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]), as: UTF8.self)
  }
}
