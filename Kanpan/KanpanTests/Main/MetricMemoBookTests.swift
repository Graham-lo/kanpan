import Foundation
import Testing
import KanpanCore
@testable import Kanpan

/// 外部指标换品种先画旧的（体感 2026-10-07）。
@Suite("外部指标换回来先摆上")
struct MetricMemoBookTests {
  @Test("记下、按品种 + 周期取回；空的那几份不占位")
  func remembersPerSymbolAndInterval() {
    var book = MetricMemoBook()
    let points = [OIPoint(time: 1, value: 0.5), OIPoint(time: 2, value: 0.6)]
    book.remember(symbol: "binance/usd_m/BTCUSDT", interval: .h1,
                  points: [.taker: points, .lsr: []], regions: [.taker: (from: 1, to: 2)])
    let row = book.entry(symbol: "binance/usd_m/BTCUSDT", interval: .h1)
    #expect(row?[.taker]?.points == points)
    #expect(row?[.taker]?.region?.to == 2)
    #expect(row?[.lsr] == nil)
    #expect(book.entry(symbol: "binance/usd_m/BTCUSDT", interval: .h4) == nil)
    book.remember(symbol: "binance/usd_m/ETHUSDT", interval: .h1, points: [.lsr: []], regions: [:])
    #expect(book.entry(symbol: "binance/usd_m/ETHUSDT", interval: .h1) == nil)
    book.forget()
    #expect(book.rows.isEmpty && book.order.isEmpty)
  }

  @Test("最多记 24 份，扔最久没换过来的")
  func capsAtLimit() {
    var book = MetricMemoBook()
    for i in 0..<(MetricMemoBook.limit + 5) {
      book.remember(symbol: "S\(i)", interval: .h1, points: [.taker: [OIPoint(time: 1, value: 1)]], regions: [:])
    }
    #expect(book.rows.count == MetricMemoBook.limit)
    #expect(book.entry(symbol: "S0", interval: .h1) == nil)
    #expect(book.entry(symbol: "S\(MetricMemoBook.limit + 4)", interval: .h1) != nil)
  }

  @Test("没报视野先按最右一屏取")
  func defaultWindowIsTheRightmostScreen() {
    let w = MetricMemoBook.defaultWindow(lastTime: 1_000_000, step: 1_000)
    #expect(w.to == 1_001_000)
    #expect(w.span == 201_000)
  }
}
