import Testing
@testable import KanpanCore

/// 月线 / 年线的日历步进只有 `UTCCalendar` 一份；复盘桥、对比线、复盘契约都调它。
@Suite("UTC 日历步进")
struct UTCCalendarTests {
  private let jan31 = Aggregator.utcMs(year: 2024, month: 1, day: 31) + 3_600_000 * 13 + 60_000 * 7

  @Test("加月夹到月末，时分秒保留；闰年二月是 29 日")
  func addingMonthsClampsToMonthEnd() {
    #expect(UTCCalendar.adding(months: 1, to: jan31)
            == Aggregator.utcMs(year: 2024, month: 2, day: 29) + 3_600_000 * 13 + 60_000 * 7)
    #expect(UTCCalendar.adding(months: 0, to: jan31) == jan31)
    let mar1 = Aggregator.utcMs(year: 2023, month: 3, day: 1)
    #expect(UTCCalendar.adding(months: -1, to: mar1) == Aggregator.utcMs(year: 2023, month: 2, day: 1))
  }

  @Test("完整月数：差一毫秒就不算这个月")
  func wholeMonths() {
    let start = Aggregator.utcMs(year: 2024, month: 1, day: 1)
    let apr1 = Aggregator.utcMs(year: 2024, month: 4, day: 1)
    #expect(UTCCalendar.wholeMonths(from: start, to: apr1) == 3)
    #expect(UTCCalendar.wholeMonths(from: start, to: apr1 - 1) == 2)
    #expect(UTCCalendar.wholeMonths(from: start, to: start) == 0)
  }

  @Test("按周期走 n 根：等距按步长，月线按日历月，年线按十二个月")
  func intervalAdvancing() {
    let t = Aggregator.utcMs(year: 2024, month: 2, day: 1)
    #expect(Interval.h4.advancing(t, by: 3) == t + 3 * Interval.h4.stepMs)
    #expect(Interval.w1.advancing(t, by: -1) == t - Interval.w1.stepMs)
    #expect(Interval.mo1.advancing(t, by: 1) == Aggregator.utcMs(year: 2024, month: 3, day: 1))
    #expect(Interval.y1.advancing(Aggregator.utcMs(year: 2024, month: 1, day: 1), by: 1)
            == Aggregator.utcMs(year: 2025, month: 1, day: 1))
    // 月线的下一根就是 Aggregator 分出来的下一个桶起点。
    var bucket = Aggregator.utcMs(year: 2023, month: 11, day: 1)
    for _ in 0..<5 {
      let next = Interval.mo1.advancing(bucket, by: 1)
      #expect(Aggregator.bucketStart(ms: next, interval: .mo1) == next)
      #expect(next > bucket)
      bucket = next
    }
  }
}
