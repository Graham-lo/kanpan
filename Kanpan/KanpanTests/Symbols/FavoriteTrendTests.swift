import Foundation
import Testing
import KanpanCore

@testable import Kanpan

/// 自选行 24 小时走势线与涨跌药丸闪动（2026-10-08 视觉与交互整改）。全程无网络。
@Suite("自选走势线与药丸闪")
@MainActor
struct FavoriteTrendTests {
  private static let now: Int64 = 1_800_000_000_000
  private static let step: Int64 = 900_000

  /// 从 now 往回 n 根 15 分钟线，收盘依次是 closes。
  private static func bars(_ closes: [Double], open: Double = 100, back: Int? = nil) -> [Bar] {
    let n = back ?? closes.count
    return closes.enumerated().map { i, c in
      let t = now - Int64(n - 1 - i) * step
      let o = i == 0 ? open : closes[i - 1]
      return Bar(openTime: t, open: o, high: max(o, c), low: min(o, c), close: c, volume: 1)
    }
  }

  @Test("只留最近 24 小时，起点取窗口第一根的开盘")
  func keepsLast24Hours() throws {
    // 120 根（30 小时），只该留下最后 97 根。
    let closes = (0..<120).map { 100 + Double($0) }
    let trend = try #require(FavoriteTrend.make(bars: Self.bars(closes), now: Self.now))
    #expect(trend.closes.count == FavoriteTrend.capacity)
    #expect(trend.closes.last == closes.last)
    #expect(trend.open == closes[120 - 97 - 1])
  }

  @Test("少于两根、价不成数时不给线")
  func rejectsDegenerate() {
    #expect(FavoriteTrend.make(bars: Self.bars([101]), now: Self.now) == nil)
    #expect(FavoriteTrend.make(bars: Self.bars([101, .nan]), now: Self.now) == nil)
    #expect(FavoriteTrend.make(bars: Self.bars([101, 0]), now: Self.now) == nil)
    // 全是 24 小时以前的：一根都不留。
    let old = Self.bars([101, 102, 103]).map {
      Bar(openTime: $0.openTime - 2 * FavoriteTrend.window, open: $0.open, high: $0.high,
          low: $0.low, close: $0.close, volume: 1)
    }
    #expect(FavoriteTrend.make(bars: old, now: Self.now) == nil)
  }

  @Test("尾点接最新价，涨跌按尾点对起点")
  func tailFollowsLivePrice() throws {
    let trend = try #require(FavoriteTrend.make(bars: Self.bars([101, 102]), now: Self.now))
    #expect(trend.points(last: nil) == [101, 102])
    #expect(trend.points(last: 99) == [101, 99])
    #expect(trend.points(last: .nan) == [101, 102])
    #expect(abs(trend.change(last: nil) - 0.02) < 1e-12)
    #expect(trend.change(last: 99) < 0)
  }

  @Test("走势落到按行那一格：同值不重复改，超出上限淘汰旧的")
  func setTrendLandsOnCell() {
    let storage = MemoryPrefsStorage()
    let store = SymbolPrefsStore(storage: storage, key: "t")
    let m = SymbolPickerModel(catalog: SymbolFixtures.catalog, tickers: [], store: store)
    let key = "binance/usd_m/BTCUSDT"
    let cell = m.quoteCell(key)
    #expect(cell.trend == nil)
    let nowDate = Date(timeIntervalSince1970: Double(Self.now) / 1000)
    m.setTrend(key, Self.bars([101, 102, 103]), now: nowDate)
    #expect(cell.trend?.closes == [101, 102, 103])
    // 先取走势、后露面的那一行也拿得到。
    m.setTrend("binance/usd_m/ETHUSDT", Self.bars([10, 11]), now: nowDate)
    #expect(m.quoteCell("binance/usd_m/ETHUSDT").trend?.closes == [10, 11])
    // 画不出线的一段不抹掉已有的。
    m.setTrend(key, [], now: nowDate)
    #expect(cell.trend?.closes == [101, 102, 103])
  }
}
