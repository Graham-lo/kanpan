import Foundation
import KanpanCore

/// 实时合成的那点规矩（§4.4），抽成纯类型——回放器和单测都直接驱动它，
/// 不用起网络、不用等时间。
///
/// - `k.x == false` → 覆盖末根；`k.x == true` 或 `k.t > 末根` → 追加。
/// - 比末根还早的事件丢掉（乱序到达）。
/// - 补缺期间收到的 WS 事件排队，补完按 openTime 去重合并。
/// 一次逐笔折线的落点。
public enum TickFold: Sendable, Equatable {
  /// 没动序列：价格不合法、时间比末根还早、补缺中、或者序列还空着。
  case ignored
  /// 折在末根上。
  case updated
  /// 跨了周期边界，开了新的一根。
  case appended
}

public struct FeedComposer: Sendable {
  public private(set) var series: BarSeries
  /// 补缺期间排队的事件。
  public private(set) var queued: [Bar] = []
  public private(set) var isBackfilling = false
  /// 丢掉的过期事件数，日志和验收用。
  public private(set) var droppedStale = 0
  /// 最后一次 `applyTick` 折进来的撮合时间。REST 对表时靠它判断末根的收盘是不是
  /// 我们自己折出来的——是的话就别让慢一拍的 REST 把价格盖回去。
  public private(set) var lastTickMs: Int64 = 0
  /// 收到过 `x=true` 的最大 openTime：这一根交易所自己宣布收线了，是定论。
  public private(set) var lastClosedTime: Int64 = 0
  public private(set) var wsRevision: UInt64 = 0
  private var lastEvent: KlineEvent?
  private var lastTradeID: Int64?

  public init(series: BarSeries) { self.series = series }

  public var interval: Interval { series.interval }
  public var lastOpen: Int64 { series.lastTime }

  // ------------------------------------------------------------------ WS

  /// 吃一条 kline 事件。返回序列有没有变。
  @discardableResult
  public mutating func apply(_ ev: KlineEvent) -> Bool {
    guard ev.symbol.uppercased() == series.symbol.uppercased(),
          ev.bar.isValidMarketBar, ev.interval == series.interval.rawValue else { return false }
    if let old = lastEvent {
      guard ev.openTime >= old.openTime else { droppedStale += 1; return false }
      if ev.openTime == old.openTime {
        if old.closed || ev == old { return false }
        if old.eventTime > 0 {
          if ev.eventTime < old.eventTime { return false }
          if ev.eventTime == old.eventTime, (ev.lastTradeID ?? -1) <= (old.lastTradeID ?? -1) { return false }
        }
      }
    }
    lastEvent = ev
    wsRevision &+= 1
    // x=true 是交易所宣布这根收线了。记下来，别让慢一拍的 REST 快照再把它改回去。
    if ev.closed { lastClosedTime = max(lastClosedTime, ev.bar.openTime) }
    return apply(bar: ev.bar)
  }

  @discardableResult
  public mutating func apply(bar: Bar) -> Bool {
    guard bar.isValidMarketBar else { return false }
    if isBackfilling {
      queued.append(bar)
      return false
    }
    if series.count > 0, bar.openTime < series.lastTime {
      droppedStale += 1
      return false
    }
    return series.upsert(bar)
  }

  // ------------------------------------------------------------------ 逐笔折线

  /// 把一次报价折进当前那根。
  ///
  /// Retained for legacy recordings and explicit trade fallback. Production now uses
  /// authoritative cumulative kline frames on /market; never sum trade volumes into
  /// those frames concurrently or treat a quote as a real trade.
  ///
  /// - Parameters:
  ///   - qty: 成交量。挂单心跳（`bookTicker`）传 0，只动价不动量。
  ///   - allowAppend: 允许跨桶开新的一根。只有真成交才给 true——用买一卖一的中间价
  ///     去开一根的开盘价，开出来的是一个从没成交过的价。
  @discardableResult
  public mutating func applyTick(price: Double, qty: Double = 0, timeMs: Int64,
                                 allowAppend: Bool = true, tradeID: Int64? = nil) -> TickFold {
    guard price.isFinite, price > 0, timeMs >= lastTickMs else { return .ignored }
    if timeMs == lastTickMs, (tradeID ?? -1) <= (lastTradeID ?? -1) { return .ignored }
    // 补缺期间不折：REST 马上就要拿权威值整段盖过来，这会儿改末根只会打架。
    guard !isBackfilling, series.count > 0 else { return .ignored }
    let t = Aggregator.bucketStart(ms: timeMs, interval: series.interval)
    let last = series.lastTime
    if t < last {
      droppedStale += 1
      return .ignored
    }
    let vol = (qty.isFinite && qty > 0) ? qty : 0
    if t == last {
      let before = series.bar(at: series.count - 1)
      var b = before
      b.high = max(b.high, price)
      b.low = min(b.low, price)
      b.close = price
      b.volume += vol
      // 逐笔里没有主动买卖方向这一列，所以只要真折进了成交量，这一根的主动买量
      // 就不再和成交量对得上了：留着旧值等于把这笔成交整个算成主动卖。作废掉，
      // CVD 那一层会把它当缺口，而不是当成一根凭空砸下来的柱子。
      // 量没动（挂单心跳只改价）时不动它——那一根的主动买量还是有效的。
      if vol > 0 { b.takerBuy = .nan }
      lastTickMs = timeMs; lastTradeID = tradeID
      // 挂单心跳一秒能来几十条，价没动的那些别往上抛——上面是按这个返回值决定
      // 要不要重画的，一根没变的末根重画多少次都是同一张图。
      guard b != before else { return .ignored }
      _ = series.upsert(b)
      return .updated
    }
    guard allowAppend else { return .ignored }
    _ = series.upsert(Bar(openTime: t, open: price, high: price, low: price, close: price, volume: vol))
    lastTickMs = timeMs; lastTradeID = tradeID
    return .appended
  }

  // ------------------------------------------------------------------ 补缺

  /// 断线重连时先进这个状态：WS 事件只排队不落序列。
  public mutating func beginBackfill() {
    isBackfilling = true
  }

  /// REST 补缺回来了：先按 openTime 合并，再把排队的事件补上。
  @discardableResult
  public mutating func endBackfill(with bars: [Bar]) -> Int {
    let before = series.count
    merge(bars)
    isBackfilling = false
    let q = queued
    queued.removeAll()
    for b in q { _ = apply(bar: b) }
    return series.count - before
  }

  /// 这根已经封了吗——封了就不许被一份更旧的快照改回去。
  ///
  /// 两条途径，满足一条就算封：序列里已经有更晚的一根（后面那根开出来的那一刻，
  /// 前面这根就不可能再有成交了），或者收到过它的 `x=true`。
  private func isSealed(_ t: Int64) -> Bool {
    if series.count > 0, t < series.lastTime { return true }
    return lastClosedTime > 0 && t <= lastClosedTime
  }

  /// 按 openTime 去重合并任意一段（可能与已有重叠、可能整段更新）。
  /// 同一个 openTime 以传进来的为准——网络上后到的是更新的。
  ///
  /// 唯一的例外是这一段的**最后一根**：REST 的 `klines` 回的是「请求那一刻」的快照，
  /// 末尾那根是还在走的半根，不是定论。一次往返几百毫秒，回来时 WS 早把这根推完、
  /// 甚至已经开了下一根了——拿半根盖回去就等于把收线值抹掉，而 `apply(bar:)` 之后
  /// 又会把这根的 kline 报文当成乱序丢掉，这根就永远定格在半截上（量偏小、收盘
  /// 停在快照那一刻的价）。所以已经封了的那根，快照的半根一律不许碰。
  ///
  /// 这一段里除末根之外的每一根，在快照眼里都已经收线，是权威值，照收不误。
  public mutating func merge(_ bars: [Bar], preservingLiveTail: Bool = false) {
    guard !bars.isEmpty else { return }
    if series.count == 0 {
      series = BarSeries(symbol: series.symbol, interval: series.interval, bars: BinanceREST.dedup(bars))
      return
    }
    var m: [Int64: Bar] = [:]
    m.reserveCapacity(series.count + bars.count)
    for i in 0..<series.count { m[series.time(at: i)] = series.bar(at: i) }
    // 不假设入参有序：取最大的那个 openTime 当「还在走的那根」。
    let live = bars.lazy.map(\.openTime).max()
    for b in bars {
      if preservingLiveTail, b.openTime == series.lastTime { continue }
      // 只挡「快照的半根 vs 我们手上封好的同一根」。手上没有的那根照样得接上，
      // 不然中间会留个洞。
      if b.openTime == live, m[b.openTime] != nil, isSealed(b.openTime) { continue }
      m[b.openTime] = b
    }
    let merged = m.keys.sorted().map { m[$0]! }
    series = BarSeries(symbol: series.symbol, interval: series.interval, bars: merged)
  }

  /// 向前补历史。返回真正接上去的根数。
  @discardableResult
  public mutating func prepend(_ bars: [Bar]) -> Int {
    let before = series.count
    series.prepend(bars)
    return series.count - before
  }

  /// 整段换掉（切品种 / 周期、REST 拉满一屏）。
  public mutating func replace(_ s: BarSeries) {
    series = s
    queued.removeAll()
    isBackfilling = false
    lastTickMs = 0
    lastClosedTime = 0
    lastEvent = nil; lastTradeID = nil
    wsRevision = 0
  }

  /// REST 对表：拿权威值盖回来，但**当前那根的收盘留我们自己的**。
  ///
  /// 为什么不直接 `merge`：REST 比逐笔慢一拍（一次往返 200~400ms），整根盖过去
  /// 最新价会肉眼可见地往回跳一下，一秒跳一次就成了抖动。所以已收线的那些照单全收，
  /// 还在走的那根只取它的 open（权威）、把高低取并集、量取两者的大者，收盘看
  /// 这根有没有被我们折过——折过就是我们的更新。
  @discardableResult
  public mutating func reconcile(_ bars: [Bar]) -> Bool {
    guard !bars.isEmpty else { return false }
    guard series.count > 0 else { merge(bars); return true }
    let lastT = series.lastTime
    let mine = series.bar(at: series.count - 1)
    let liveClose = lastTickMs > 0
      && Aggregator.bucketStart(ms: lastTickMs, interval: series.interval) == lastT
    let patched: [Bar] = bars.map { b in
      guard b.openTime == lastT else { return b }
      var m = b
      m.high = max(b.high, mine.high)
      m.low = min(b.low, mine.low)
      // 主动买量跟着成交量走：哪一份的量被采纳，就用哪一份的主动买量，
      // 否则会出现「REST 的主动买量配上本地折出来的更大成交量」这种对不上的组合。
      if mine.volume > b.volume { m.volume = mine.volume; m.takerBuy = mine.takerBuy }
      if !m.takerBuy.isFinite, m.volume == mine.volume { m.takerBuy = mine.takerBuy }
      if liveClose { m.close = mine.close }
      return m
    }
    let before = series
    merge(patched)
    return series != before
  }
}
