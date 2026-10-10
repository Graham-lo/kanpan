import Foundation
import Testing
@testable import KanpanCore

/// `BarSeries.closedCount(nowMs:)`：末根的收盘时刻到没到。
@Suite("已收线根数")
struct BarSeriesClosedTests {
  static func series(_ interval: Interval, opens: [Int64]) -> BarSeries {
    BarSeries(symbol: "BTCUSDT", interval: interval,
              bars: opens.map { Bar(openTime: $0, open: 1, high: 1, low: 1, close: 1, volume: 0) })
  }

  @Test("空序列是 0")
  func empty() {
    #expect(Self.series(.m15, opens: []).closedCount(nowMs: 1_000_000) == 0)
  }

  @Test("等距周期：末根收盘时刻之前算还在走，到点（含恰好相等）整段已收线")
  func regular() {
    let step = Interval.m15.stepMs
    let s = Self.series(.m15, opens: [0, step, 2 * step])
    #expect(s.closedCount(nowMs: 2 * step) == 2)
    #expect(s.closedCount(nowMs: 3 * step - 1) == 2)
    #expect(s.closedCount(nowMs: 3 * step) == 3)
    #expect(s.closedCount(nowMs: 10 * step) == 3)
  }

  @Test("月线按日历月：一月那根要到二月 1 日才收")
  func monthly() {
    // 2026-01-01T00:00:00Z、2026-02-01T00:00:00Z
    let jan: Int64 = 1_767_225_600_000, feb: Int64 = 1_769_904_000_000
    let s = Self.series(.mo1, opens: [jan])
    #expect(s.closedCount(nowMs: feb - 1) == 0)
    #expect(s.closedCount(nowMs: feb) == 1)
  }
}
