import Foundation
import KanpanCore

/// 实时合成的那点规矩（§4.4），抽成纯类型——回放器和单测都直接驱动它，
/// 不用起网络、不用等时间。
///
/// - `k.x == false` → 覆盖末根；`k.x == true` 或 `k.t > 末根` → 追加。
/// - 比末根还早的事件丢掉（乱序到达）。
/// - 补缺期间收到的 WS 事件排队，补完按 openTime 去重合并。
public struct FeedComposer: Sendable {
  public private(set) var series: BarSeries
  /// 补缺期间排队的事件。
  public private(set) var queued: [Bar] = []
  public private(set) var isBackfilling = false
  /// 丢掉的过期事件数，日志和验收用。
  public private(set) var droppedStale = 0

  public init(series: BarSeries) { self.series = series }

  public var interval: Interval { series.interval }
  public var lastOpen: Int64 { series.lastTime }

  // ------------------------------------------------------------------ WS

  /// 吃一条 kline 事件。返回序列有没有变。
  @discardableResult
  public mutating func apply(_ ev: KlineEvent) -> Bool {
    guard ev.symbol.uppercased() == series.symbol.uppercased() else { return false }
    return apply(bar: ev.bar)
  }

  @discardableResult
  public mutating func apply(bar: Bar) -> Bool {
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

  /// 按 openTime 去重合并任意一段（可能与已有重叠、可能整段更新）。
  /// 同一个 openTime 以传进来的为准——网络上后到的是更新的。
  public mutating func merge(_ bars: [Bar]) {
    guard !bars.isEmpty else { return }
    if series.count == 0 {
      series = BarSeries(symbol: series.symbol, interval: series.interval, bars: BinanceREST.dedup(bars))
      return
    }
    var m: [Int64: Bar] = [:]
    m.reserveCapacity(series.count + bars.count)
    for i in 0..<series.count { m[series.time(at: i)] = series.bar(at: i) }
    for b in bars { m[b.openTime] = b }
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
  }
}
