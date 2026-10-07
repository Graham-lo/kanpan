import Foundation
import Testing
import KanpanChart
import KanpanCore
@testable import Kanpan

// 十字线读数挪进周期条那一行（2026-10-08 走查）：一行「时间 · 开 高 低 收 · 涨跌幅」，
// 放不下先收开高低、再收时间；收盘价与涨跌幅总在。

@Suite("十字线读数：周期条那一行")
@MainActor struct CrosshairBandReadoutTests {
  // 2023-11-14 22:13:20 UTC = 2023-11-15 06:13 +08:00。
  private let t0: Int64 = 1_700_000_000_000

  private func context(_ interval: Interval, _ bars: [Bar]) -> CrosshairContext {
    let series = BarSeries(symbol: "binance/usd_m/BTCUSDT", interval: interval, bars: bars)
    return CrosshairContext(seriesSource: { series }, symbol: "binance/usd_m/BTCUSDT", interval: interval,
                            decimals: 1, offsetMinutes: .fixed(480), enabled: true)
  }

  private var bars: [Bar] {
    [Bar(openTime: t0, open: 100, high: 101, low: 99, close: 100, volume: 1),
     Bar(openTime: t0 + 3_600_000, open: 100, high: 103, low: 99.5, close: 102, volume: 1)]
  }

  @Test("三档文案：全量 → 收掉开高低 → 再收时间")
  func threeFits() throws {
    let r = try #require(crosshairBandReadout(Crosshair(index: 1, price: 101), context(.h1, bars)))
    #expect(r.time == "11-15 07:13")
    #expect(r.text(.full) == "11-15 07:13 · 开 100.0 高 103.0 低 99.5 收 102.0 · +2.00%")
    #expect(r.text(.closeOnly) == "11-15 07:13 · 收 102.0 · +2.00%")
    #expect(r.text(.bare) == "收 102.0 · +2.00%")
    // 越往后越短，`ViewThatFits` 才退得下去。
    #expect(r.text(.full).count > r.text(.closeOnly).count)
    #expect(r.text(.closeOnly).count > r.text(.bare).count)
  }

  @Test("涨跌幅相对上一根收盘；第一根相对自己开盘；平写 0.00%")
  func changeBase() throws {
    let first = try #require(crosshairBandReadout(Crosshair(index: 0, price: nil), context(.h1, bars)))
    #expect(first.change == "0.00%")
    let down = [Bar(openTime: t0, open: 100, high: 100, low: 90, close: 100, volume: 1),
                Bar(openTime: t0 + 3_600_000, open: 100, high: 100, low: 90, close: 95, volume: 1)]
    #expect(crosshairBandReadout(Crosshair(index: 1, price: nil), context(.h1, down))?.change == "-5.00%")
  }

  @Test("日线及以上只写日期")
  func dailyWritesDateOnly() throws {
    let r = try #require(crosshairBandReadout(Crosshair(index: 0, price: nil), context(.d1, bars)))
    #expect(r.time == "2023-11-15")
  }

  @Test("副图上的十字线照给读数；序列对不上、下标越界不给")
  func paneAndMismatch() {
    let ctx = context(.h1, bars)
    #expect(crosshairBandReadout(Crosshair(index: 1, price: nil, pane: .vol), ctx) != nil)
    #expect(crosshairBandReadout(Crosshair(index: 5, price: nil), ctx) == nil)
    var other = ctx; other.symbol = "binance/usd_m/ETHUSDT"
    #expect(crosshairBandReadout(Crosshair(index: 1, price: nil), other) == nil)
  }
}
