import Foundation
import Testing

@testable import KanpanCore

/// 带洞的等距序列：下标 ↔ 时间必须还是真时间。
///
/// 省掉 `openTime` 列是一条快路，前提是整段严格等距（`openTime[i] == t0 + i*step`）。
/// 交易所停盘、REST 缺根、聚合缺桶都会让这个前提破掉，而一旦破了还照 `t0 + i*step` 推，
/// 洞后面每一根的时间都会整体前移一格——图上的十字光标、画线吸附、`merge` 去重建的
/// 字典键全跟着错，而且错时间会被写回序列，越修越乱。
@Suite("带洞序列的时间")
struct SeriesGapTests {
  private static let t0: Int64 = 1_700_000_000_000
  private static let step: Int64 = Interval.m1.stepMs

  private func bar(_ t: Int64, _ v: Double) -> Bar {
    Bar(openTime: t, open: v, high: v + 1, low: v - 1, close: v + 0.5, volume: v * 10)
  }

  /// 第 k 格（k 是「本来该在的那一格」）的 bar。
  private func slot(_ k: Int64) -> Bar { bar(Self.t0 + k * Self.step, Double(k)) }

  @Test("中间缺一根，后面每一根的时间不能整体前移")
  func holeDoesNotShiftTheTail() {
    let slots: [Int64] = [0, 1, 2, 4, 5]          // 第 3 格缺了
    let s = BarSeries(symbol: "BTCUSDT", interval: .m1, bars: slots.map { slot($0) })
    #expect(!s.openTime.isEmpty, "带洞的序列必须把真实 openTime 留着")
    for (i, k) in slots.enumerated() {
      #expect(s.time(at: i) == Self.t0 + k * Self.step, "第 \(i) 根应是第 \(k) 格")
    }
    #expect(s.lastTime == Self.t0 + 5 * Self.step)
    #expect(s.index(atTime: Double(Self.t0 + 5 * Self.step)) == 4)
  }

  @Test("洞被补上之后整段回到严格等距的快路")
  func filledSeriesGoesBackToTheFastPath() {
    let s = BarSeries(symbol: "BTCUSDT", interval: .m1, bars: (0..<6).map { slot(Int64($0)) })
    #expect(s.openTime.isEmpty, "严格等距就该省掉这一列")
    for i in 0..<s.count { #expect(s.time(at: i) == Self.t0 + Int64(i) * Self.step) }
  }

  @Test("跨过一个洞追加末根，前面那些根的时间一根不动")
  func appendAcrossAHoleKeepsEarlierTimes() {
    var s = BarSeries(symbol: "BTCUSDT", interval: .m1, bars: (0..<3).map { slot(Int64($0)) })
    #expect(s.openTime.isEmpty)
    s.append(slot(7))                              // 第 3~6 格全缺
    #expect(s.count == 4)
    for i in 0..<3 { #expect(s.time(at: i) == Self.t0 + Int64(i) * Self.step) }
    #expect(s.lastTime == Self.t0 + 7 * Self.step)
    // 再折一笔进末根：`upsert` 认的是 `lastTime`，它错了这一笔就会开出第五根。
    s.upsert(bar(Self.t0 + 7 * Self.step, 99))
    #expect(s.count == 4 && s.close.last == 99.5)
  }

  @Test("补历史接上的一段不连续时，两边的时间都要对")
  func prependWithAGapKeepsBothSidesHonest() {
    var s = BarSeries(symbol: "BTCUSDT", interval: .m1, bars: (5..<8).map { slot(Int64($0)) })
    s.prepend([slot(0), slot(1)])                  // 第 2~4 格缺
    #expect(s.count == 5)
    #expect(s.firstTime == Self.t0)
    for (i, k) in [0, 1, 5, 6, 7].enumerated() {
      #expect(s.time(at: i) == Self.t0 + Int64(k) * Self.step, "第 \(i) 根应是第 \(k) 格")
    }
    // 把中间补齐：整段重新严格等距，列该丢掉。
    let whole = BarSeries(symbol: "BTCUSDT", interval: .m1, bars: (0..<8).map { slot(Int64($0)) })
    #expect(whole.openTime.isEmpty)
    #expect(whole.lastTime == Self.t0 + 7 * Self.step)
  }

  @Test("补历史接得严丝合缝时仍然走快路")
  func contiguousPrependStaysOnTheFastPath() {
    var s = BarSeries(symbol: "BTCUSDT", interval: .m1, bars: (3..<6).map { slot(Int64($0)) })
    s.prepend((0..<3).map { slot(Int64($0)) })
    #expect(s.count == 6)
    #expect(s.openTime.isEmpty, "接严实了就该把列重新省掉")
    for i in 0..<6 { #expect(s.time(at: i) == Self.t0 + Int64(i) * Self.step) }
  }

  @Test("不等距周期永远带着 openTime，不许被当成等距省掉")
  func irregularIntervalsAlwaysKeepTheColumn() {
    // 故意造一段「正好等于名义步长」的月线：等距周期会省列，不等距周期不许省。
    let times = (0..<4).map { Int64($0) * Interval.mo1.stepMs }
    let s = BarSeries(symbol: "BTCUSDT", interval: .mo1, bars: times.map { bar($0, 1) })
    #expect(!s.openTime.isEmpty)
  }

  /// 空的月线序列往里 append 第一根，也必须带着列。
  ///
  /// `materializeTimes()` 对空序列摊出来的仍是空列，所以「摊完再看列空不空」这个
  /// 判法会把 1M/1y 的第一根漏掉——同一根 bar，append 出来的和
  /// `init(symbol:interval:bars:)` 造出来的就不是同一条序列了。
  @Test("空的不等距序列追加第一根，列不能漏掉")
  func firstAppendOnEmptyIrregularSeriesKeepsTheColumn() {
    let t = Int64(1_700_000_000_000)
    let b = bar(t, 7)
    var s = BarSeries(symbol: "BTCUSDT", interval: .mo1, t0: 0,
                      open: [], high: [], low: [], close: [], volume: [])
    s.append(b)
    #expect(s.openTime == [t])
    #expect(s.time(at: 0) == t)
    #expect(s == BarSeries(symbol: "BTCUSDT", interval: .mo1, bars: [b]))
  }
}
