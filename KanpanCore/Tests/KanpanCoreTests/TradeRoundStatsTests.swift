import Foundation
import Testing
@testable import KanpanCore

// 交易侧战绩、分组、「上周」周报卡、自动截图周期（方案 3.4、协议 4.3）。

@Suite struct TradeRoundStatsTests {
  typealias F = TradeFixture

  /// 直接造一个已平仓回合（统计只看回合字段，不必从成交拼）。
  static func round(_ id: String, symbol: String = "BTCUSDT", _ direction: TradeDirection = .long,
                    net: String, realized: String? = nil, commission: String = "0", funding: String = "0",
                    openedAt: Int64, holding: Int64, open: Bool = false) -> TradeRound {
    TradeRound(id: id, venue: "binance", market: "usd_m", symbol: symbol, accountTag: "primary",
               positionSide: .both, direction: direction, status: open ? .open : .closed, quoteAsset: "USDT",
               openedAt: openedAt, closedAt: open ? nil : openedAt + holding, holdingMs: open ? nil : holding,
               openAvgPrice: 100, closeAvgPrice: open ? nil : 100, openedQty: 1, closedQty: open ? 0 : 1,
               maxQty: 1, peakNotional: 100, leverage: nil,
               realizedPnl: F.d(realized ?? net), commission: F.d(commission), commissionByAsset: [:],
               commissionUnpriced: false, funding: F.d(funding), netPnl: F.d(net), fills: [],
               updatedAt: openedAt + holding)
  }

  static let shanghai: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return c
  }()

  @Test("汇总：胜率、盈亏比、期望值、费用占毛利、最大连亏、平均持仓；持仓中的不算")
  func summary() throws {
    let t = F.t0
    let rounds = [
      Self.round("a", net: "30", realized: "32", commission: "2", openedAt: t, holding: F.hour),
      Self.round("b", net: "-10", realized: "-9", commission: "1", openedAt: t + F.day, holding: F.hour),
      Self.round("c", net: "-5", realized: "-4", commission: "0.5", funding: "-0.5", openedAt: t + 2 * F.day, holding: 3 * F.hour),
      Self.round("d", net: "0", openedAt: t + 3 * F.day, holding: F.hour),
      Self.round("e", net: "-1", openedAt: t + 4 * F.day, holding: F.hour),
      Self.round("f", net: "15", realized: "16", commission: "1", openedAt: t + 5 * F.day, holding: F.hour),
      Self.round("open", net: "999", openedAt: t + 6 * F.day, holding: 0, open: true),
    ]
    let s = RoundStats.summarize(rounds)
    #expect(s.count == 6 && s.wins == 2 && s.losses == 3)
    #expect(s.winRate == F.d("0.333333"))
    #expect(s.netPnl == 29 && s.grossPnl == 34)
    #expect(s.commission == F.d("4.5") && s.funding == F.d("-0.5") && s.fees == 5)
    #expect(s.feeShareOfGross == F.d("0.147059"), "5 ÷ 34")
    #expect(s.averageWin == F.d("22.5") && s.averageLoss == F.d("-5.33333333"))
    #expect(s.rewardRisk == F.d("4.2188"), "22.5 ÷ 5.33333333")
    #expect(s.expectancy == F.d("4.83333333"))
    #expect(s.longestLosingStreak == 2, "b、c 连亏两笔；d 打平断开，e 另起一笔")
    #expect(s.averageHoldingMs == (8 * F.hour) / 6)
    #expect(s.best?.id == "a" && s.worst?.id == "b")
    #expect(RoundStats.summarize([]).winRate == nil)
  }

  @Test("分组：品种、方向、持仓时长档、开仓时段（本地四段）、周几")
  func grouping() throws {
    // 2026-09-21 是周一；上海时间 03:00 / 09:00 / 15:00 / 21:00。
    let monday3am: Int64 = 1_789_930_800_000
    let rounds = [
      Self.round("a", symbol: "BTCUSDT", .long, net: "10", openedAt: monday3am, holding: 30 * F.minute),
      Self.round("b", symbol: "ETHUSDT", .short, net: "-4", openedAt: monday3am + 6 * F.hour, holding: 2 * F.hour),
      Self.round("c", symbol: "BTCUSDT", .short, net: "3", openedAt: monday3am + 12 * F.hour, holding: 2 * F.day),
      Self.round("d", symbol: "SOLUSDT", .long, net: "1", openedAt: monday3am + 18 * F.hour + F.day, holding: 8 * F.day),
    ]
    let sym = RoundStats.bySymbol(rounds)
    #expect(sym.map(\.key) == ["BTCUSDT", "SOLUSDT", "ETHUSDT"], "按净盈亏从高到低")
    #expect(sym[0].summary.count == 2 && sym[0].summary.netPnl == 13)

    let dir = RoundStats.byDirection(rounds)
    #expect(dir.map(\.key) == [.long, .short] && dir[1].summary.netPnl == -1)

    let hold = RoundStats.byHolding(rounds)
    #expect(hold.map(\.key) == [.underHour, .hourToDay, .dayToWeek, .overWeek])
    #expect(HoldingBucket(holdingMs: F.hour) == .hourToDay && HoldingBucket(holdingMs: F.hour - 1) == .underHour)
    #expect(HoldingBucket(holdingMs: 7 * F.day) == .overWeek)

    let session = RoundStats.bySession(rounds, calendar: Self.shanghai)
    #expect(session.map(\.key) == [.night, .morning, .afternoon, .evening])
    #expect(session.map(\.summary.count) == [1, 1, 1, 1])

    let week = RoundStats.byWeekday(rounds, calendar: Self.shanghai)
    #expect(week.map(\.key.index) == [1, 2])
    #expect(week.map(\.key.title) == ["周一", "周二"])
    #expect(week[0].summary.count == 3)
  }

  @Test("上周周报：周界是本地时区周一 00:00，周日 23:59:59 平的算上周，周一零点平的算本周")
  func weeklyBoundary() throws {
    let thisMonday: Int64 = 1_790_524_800_000  // 2026-09-28 00:00 上海
    let lastMonday: Int64 = 1_789_920_000_000  // 2026-09-21 00:00 上海
    let wednesday: Int64 = 1_790_751_600_000   // 2026-09-30 15:00 上海

    for now in [thisMonday, wednesday, thisMonday + 7 * F.day - 1] {
      let (start, end) = WeeklyReport.lastWeekBounds(now: now, calendar: Self.shanghai)
      #expect(start == lastMonday && end == thisMonday, "now = \(now)")
    }
    let (s2, e2) = WeeklyReport.lastWeekBounds(now: thisMonday - 1, calendar: Self.shanghai)
    #expect(s2 == lastMonday - 7 * F.day && e2 == lastMonday, "周日深夜看的「上周」还是再往前那一周")

    let rounds = [
      Self.round("sunday-late", net: "5", openedAt: thisMonday - 1_000 - F.hour, holding: F.hour),
      Self.round("monday-zero", net: "100", openedAt: thisMonday - F.hour, holding: F.hour),
      Self.round("first-second", net: "-2", openedAt: lastMonday - F.hour, holding: F.hour),
      Self.round("before", net: "-50", openedAt: lastMonday - F.hour - 1, holding: F.hour),
      Self.round("open", net: "7", openedAt: lastMonday + F.hour, holding: 0, open: true),
    ]
    let report = WeeklyReport.lastWeek(rounds, now: wednesday, calendar: Self.shanghai)
    #expect(report.summary.count == 2)
    #expect(report.summary.netPnl == 3)
    #expect(report.summary.best?.id == "sunday-late" && report.summary.worst?.id == "first-second")
    #expect(report.summary.winRate == F.d("0.5"))
  }

  @Test("自动截图周期：≤4h → 5m，≤2d → 1h，≤14d → 4h，否则 1d（边界含等号）")
  func chartInterval() {
    #expect(ReviewChartInterval.forHolding(0) == .m5)
    #expect(ReviewChartInterval.forHolding(4 * F.hour) == .m5)
    #expect(ReviewChartInterval.forHolding(4 * F.hour + 1) == .h1)
    #expect(ReviewChartInterval.forHolding(2 * F.day) == .h1)
    #expect(ReviewChartInterval.forHolding(2 * F.day + 1) == .h4)
    #expect(ReviewChartInterval.forHolding(14 * F.day) == .h4)
    #expect(ReviewChartInterval.forHolding(14 * F.day + 1) == .d1)
  }

  @Test("截图时间窗：前后各留 max(10 根, 时长四分之一)，对齐周期，右端不越过现在")
  func chartWindow() {
    let open: Int64 = 1_790_000_100_000  // 能被 5 分钟整除
    let w = ReviewChartInterval.window(openedAt: open, closedAt: open + F.hour, now: open + F.day)
    #expect(w.interval == .m5)
    #expect(w.start == open - 50 * F.minute && w.end == open + F.hour + 50 * F.minute)

    let long = ReviewChartInterval.window(openedAt: open, closedAt: open + 8 * F.day, now: open + 8 * F.day + F.hour)
    #expect(long.interval == .h4)
    #expect(long.end <= open + 8 * F.day + F.hour && long.end % (4 * F.hour) == 0)
    #expect(long.start <= open - 2 * F.day && long.start % (4 * F.hour) == 0)
  }
}
