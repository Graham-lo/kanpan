import Foundation
import Testing
@testable import KanpanData
import KanpanCore
import KanpanNetwork

/// 持仓量到底覆盖到哪儿。
///
/// 界面上那句「这个周期币安不提供持仓量历史」被删掉之前，这一组用例先把事实钉下来：
/// 归档站（`OISource.archiveEpoch` = 2020-09-01）起的每一天都有，而 `chartSeries`
/// 会把它们按图表周期的日历桶聚起来——**1w / 1M / 1y 一根不缺地画得出来**。
/// 真正的边界只有两条：往前到 2020-09-01 为止，以及源的粒度是五分钟。
@Suite("持仓量覆盖边界：2020-09 起，最细五分钟")
struct OIIntervalCoverageTests {

  private static let day: Int64 = 86_400_000
  private static let end = Aggregator.utcMs(year: 2026, month: 9, day: 1)

  /// 归档站那几年：每天一条。
  ///
  /// 真实的归档是一天 288 条五分钟采样，而 `chartSeries` 每个桶只留最后一条，
  /// 所以对「这个周期画不画得出来」这个问题，按天喂和按五分钟喂是同一件事。
  private static func archivePoints(from: Int64 = OISource.archiveEpoch,
                                    to: Int64 = end) -> [OIPoint] {
    stride(from: from, through: to, by: Int(day)).enumerated().map {
      OIPoint(time: $0.element, value: 1000 + Double($0.offset))
    }
  }

  /// 按真实日历造这个周期的 K 线（1M 的月长不等、1y 的闰年都交给 `Aggregator`）。
  private static func calendarBars(_ interval: Interval, from: Int64, to: Int64) -> BarSeries {
    let count = Int((to - from) / day) + 1
    let daily = BarSeries(symbol: "BTCUSDT", interval: .d1,
                          bars: makeBars(t0: from, step: day, count: count))
    return interval == .d1 ? daily : Aggregator.bucket(series: daily, into: interval)
  }

  @Test("1w / 1M / 1y 从 2020-09 到今天整条都有持仓量",
        arguments: [Interval.w1, .mo1, .y1])
  func longIntervalsDrawEndToEnd(interval: Interval) {
    let bars = Self.calendarBars(interval, from: OISource.archiveEpoch, to: Self.end)
    let aligned = OISource.chartSeries(Self.archivePoints(), interval: interval).aligned(to: bars)
    #expect(bars.count > 5, "\(interval.rawValue) 只造出 \(bars.count) 根，样本太短说明不了问题")
    #expect(aligned.count == bars.count)
    // 一根都不许空：这些周期上「画不出来」从来不是交易所的限制。
    let blanks = aligned.filter { !$0.isFinite }.count
    #expect(blanks == 0, "\(interval.rawValue) 有 \(blanks) 根空着")
    // 而且是真的一条会动的线，不是一条压平的直线。
    #expect(Set(aligned).count > 1)
  }

  @Test("1d 以下也一样，一路到 5 分钟", arguments: [Interval.d1, .h4, .h1, .m5])
  func shortIntervalsDrawToo(interval: Interval) {
    let from = Aggregator.bucketStart(ms: Self.end - 30 * Self.day, interval: interval)
    var times: [Int64] = []
    var t = from
    while t <= Self.end { times.append(t); t += interval.stepMs }
    var bars = BarSeries(symbol: "BTCUSDT", interval: interval,
                         bars: makeBars(t0: from, step: interval.stepMs, count: times.count))
    bars.openTime = times
    let raw = stride(from: from, through: Self.end, by: 300_000 as Int).enumerated().map {
      OIPoint(time: $0.element, value: 1000 + Double($0.offset))
    }
    let aligned = OISource.chartSeries(raw, interval: interval).aligned(to: bars)
    #expect(aligned.count == bars.count)
    #expect(aligned.filter { !$0.isFinite }.isEmpty)
  }

  @Test("1m / 3m 比源还细：不是没有，是一条按五分钟走的阶梯", arguments: [Interval.m1, .m3])
  func finerThanTheSourceStillDraws(interval: Interval) {
    let raw = (0..<3).map { OIPoint(time: Int64($0) * 300_000, value: 10 + Double($0)) }
    let count = interval == .m1 ? 15 : 5          // 两边都覆盖到 840_000 ms 以内
    let bars = BarSeries(symbol: "BTCUSDT", interval: interval,
                         bars: makeBars(t0: 0, step: interval.stepMs, count: count))
    let aligned = OISource.chartSeries(raw, interval: interval).aligned(to: bars)
    #expect(aligned.filter { !$0.isFinite }.isEmpty, "\(interval.rawValue) 上持仓量不该留空")
    // 阶梯：相邻几根共用一个值，一共只有三档。
    #expect(Set(aligned).count == 3)
  }

  @Test("边界是 2020-09-01：更早的那几根是真的没有，不是周期的问题")
  func nothingBeforeTheArchiveEpoch() {
    let start = Aggregator.utcMs(year: 2019, month: 10, day: 1)
    let stop = Aggregator.utcMs(year: 2021, month: 3, day: 1)
    let bars = Self.calendarBars(.mo1, from: start, to: stop)
    let aligned = OISource.chartSeries(Self.archivePoints(to: stop), interval: .mo1).aligned(to: bars)
    for (i, value) in aligned.enumerated() {
      let month = bars.time(at: i)
      if month < Aggregator.utcMs(year: 2020, month: 9, day: 1) {
        #expect(!value.isFinite, "\(month) 早于归档起点，不该凭空有值")
      } else {
        #expect(value.isFinite, "\(month) 在归档范围内，不该空着")
      }
    }
  }

  @Test("近 30 天这一段用的是原生 period，不是唯一的一段")
  func restWindowIsOnlyTheRecentHalf() {
    // 30 天只是 REST 那一段的长度，越过它的部分走归档 / 网关，不是「到此为止」。
    #expect(OISource.restWindowMs == 30 * 86_400_000)
    #expect(OISource.archiveEpoch == Aggregator.utcMs(year: 2020, month: 9, day: 1))
    // 长周期没有原生 period，靠 5 分钟归档按桶聚上去（`chartSeries`）。
    #expect(Interval.w1.oiPeriod == nil)
    #expect(Interval.mo1.oiPeriod == nil)
    #expect(Interval.y1.oiPeriod == nil)
    // 一次能问到的历史跨度：十年封顶，长周期够从 2020-09 一口气问到今天。
    let span = OISource.historySpan(step: Interval.y1.stepMs)
    #expect(span >= Self.end - OISource.archiveEpoch)
  }
}
