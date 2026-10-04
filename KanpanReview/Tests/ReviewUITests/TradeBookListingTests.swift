import Foundation
import Testing
import KanpanCore
import ReviewDomain
@testable import ReviewUI

/// 交易那一半列表与战绩的口径：短名分得清计价（审查 R8）、按天分组认年份（审查 R17）。
@MainActor struct TradeBookListingTests {
  private func round(_ n: Int, symbol: String = "BTCUSDT", closed: Int64, net: Decimal = 1) -> TradeRound {
    TradeRound(id: String(format: "00000000-0000-8000-8000-%012d", n), venue: "binance", market: "usd_m",
               symbol: symbol, accountTag: "primary", positionSide: .both, direction: .long, status: .closed,
               quoteAsset: symbol.hasSuffix("USDC") ? "USDC" : "USDT", openedAt: closed - 60_000, closedAt: closed,
               holdingMs: 60_000, openAvgPrice: 100, closeAvgPrice: 101, openedQty: 1, closedQty: 1, maxQty: 1,
               peakNotional: 100, leverage: 5, realizedPnl: net, commission: 0, commissionByAsset: [:],
               commissionUnpriced: false, funding: 0, netPnl: net, fills: [], updatedAt: 1)
  }
  private var shanghai: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    value.firstWeekday = 2
    return value
  }
  private func ms(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Int64 {
    let date = shanghai.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    return Int64(date.timeIntervalSince1970 * 1000)
  }

  /// BTCUSDT 与 BTCUSDC 以前都写成「BTC」，战绩「按品种」还拿它当行 id，两行撞 id。
  @Test func statsRowsKeyedBySymbol() {
    let rounds = [round(1, symbol: "BTCUSDT", closed: 1_000_000, net: 5), round(2, symbol: "BTCUSDC", closed: 2_000_000, net: 3)]
    let rows = TradeStatisticsList.symbolRows(rounds)
    #expect(rows.map(\.id) == ["BTCUSDT", "BTCUSDC"])
    #expect(rows.map(\.name) == ["BTC", "BTC/USDC"])
    #expect(Set(rows.map(\.id)).count == rows.count)
  }

  @Test func shortSymbolShowsNonUSDTQuote() {
    #expect(TradeLabels.shortSymbol("binance/usd_m/BTCUSDT") == "BTC")
    #expect(TradeLabels.shortSymbol("binance/usd_m/BTCUSDC") == "BTC/USDC")
    #expect(TradeLabels.shortSymbol("coinbase/spot/BTC-USD") == "BTC/USD")
    #expect(round(1, symbol: "ETHUSDT", closed: 0).shortSymbol == "ETH")
  }

  /// 去年 3 月 5 日和今年 3 月 5 日以前标题一样（「3 月 5 日 周X」不带年），被并成一组。
  @Test func daysGroupByCalendarDayAndShowYearOutsideThisYear() {
    let now = ms(2026, 10, 4, 15)
    let items = [round(1, closed: ms(2026, 10, 4, 9)), round(2, closed: ms(2026, 10, 3, 23)),
                 round(3, closed: ms(2026, 3, 5)), round(4, closed: ms(2026, 3, 5, 8)),
                 round(5, closed: ms(2025, 3, 5)), round(6, closed: ms(2026, 10, 4, 0) - 1)].map { TradeItem(round: $0) }
    let days = TradeBookList.days(items, calendar: shanghai, now: now)
    #expect(days.map(\.title) == ["今天", "昨天", "3 月 5 日 周四", "2025 年 3 月 5 日 周三"])
    #expect(days.map { $0.items.map(\.round.id) } == [[items[0].id], [items[1].id, items[5].id], [items[2].id, items[3].id], [items[4].id]])
    #expect(Set(days.map(\.id)).count == days.count)
  }
}
