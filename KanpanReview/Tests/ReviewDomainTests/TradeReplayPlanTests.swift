import XCTest
import KanpanCore
import ReviewDomain

/// 交易回放（自动复盘 3d）的纯算术：用哪个周期、停在哪、播到哪收尾、进度线怎么换算、
/// 图上只画已经发生的成交、浮动盈亏按方向算。
final class TradeReplayPlanTests: XCTestCase {
  private let hour: Int64 = 3_600_000
  /// 2026-09-21 00:00 UTC（周一）。
  private let monday: Int64 = 1_789_948_800_000

  private func fill(_ n: Int, _ time: Int64, _ side: TradeSide, _ price: Decimal, _ qty: Decimal, _ role: FillRole) -> RoundFill {
    RoundFill(id: "f\(n)", orderId: "o\(n)", time: time, side: side, positionSide: .both, price: price, qty: qty,
              quoteQty: price * qty, commission: 0, commissionAsset: "USDT", realizedPnl: 0, maker: false,
              role: role, split: false)
  }

  private func round(_ direction: TradeDirection, fills: [RoundFill], opened: Int64, closed: Int64?,
                     open: Decimal = 100, close: Decimal? = 110) -> TradeRound {
    TradeRound(id: "00000000-0000-8000-8000-000000000001", venue: "binance", market: "usd_m", symbol: "BTCUSDT",
               accountTag: "primary", positionSide: .both, direction: direction,
               status: closed == nil ? .open : .closed, quoteAsset: "USDT", openedAt: opened, closedAt: closed,
               holdingMs: closed.map { $0 - opened }, openAvgPrice: open, closeAvgPrice: closed == nil ? nil : close,
               openedQty: 1, closedQty: 1, maxQty: 1, peakNotional: 100, leverage: 10, realizedPnl: 0,
               commission: 0, commissionByAsset: [:], commissionUnpriced: false, funding: 0, netPnl: 0,
               fills: fills, updatedAt: 1)
  }

  // MARK: - 倍速由我挑（整趟 20–40 秒，1× / 2× / 4×）

  func testPacePicksTheSlowestStepThatFitsFortySeconds() {
    let fixed = TradeReplayPlan.holdMs + 2 * TradeReplayPlan.pauseMs
    // 走查量到的那一笔：1 小时 48 根，1× 要 51 秒多 → 2×，约 27 秒。
    XCTAssertEqual(ReplayPace.speed(bars: 48, fixedMs: fixed), 2)
    XCTAssertTrue(ReplayPace.target.contains(Int(ReplayPace.seconds(bars: 48, speed: 2, fixedMs: fixed))))
    // 短单：1× 就在 40 秒里，不往快里赶。
    XCTAssertEqual(ReplayPace.speed(bars: 30, fixedMs: fixed), 1)
    XCTAssertEqual(ReplayPace.speed(bars: 5), 1)
    // 长单：2× 也超，4×。
    XCTAssertEqual(ReplayPace.speed(bars: 120, fixedMs: fixed), 4)
    // 再长也封顶 4×，不再往上加。
    XCTAssertEqual(ReplayPace.speed(bars: 800), 4)
    XCTAssertEqual(ReplayPace.speed(bars: -3), 1)
  }

  // MARK: - 周期怎么挑（用户 2026-09-28 定的顺序）

  /// 人自己的周期在前：这笔在他那张图上落在 10–200 根里就用它，哪怕服务端给了别的。
  func testUsersOwnIntervalWinsWhenTheTradeFitsOnIt() {
    let opened = monday, closed = monday + 6 * hour
    // 15 分：6 小时 = 25 根，在 10–200 里。
    XCTAssertEqual(TradeReplayPlan.interval(preferred: .m15, spec: "1h", openedAt: opened, closedAt: closed), .m15)
    // 1 分：361 根，超了 200——退到服务端那份。
    XCTAssertEqual(TradeReplayPlan.interval(preferred: .m1, spec: "1h", openedAt: opened, closedAt: closed), .h1)
    // 4 时：2 根，不到 10——同样退到服务端那份。
    XCTAssertEqual(TradeReplayPlan.interval(preferred: .h4, spec: "5m", openedAt: opened, closedAt: closed), .m5)
    // 周线不参与（对不齐交易所开盘，一笔也只剩一两根）。
    XCTAssertEqual(TradeReplayPlan.interval(preferred: .w1, spec: "1h", openedAt: opened, closedAt: closed + 100 * 24 * hour), .h1)
  }

  /// 服务端也没有：按持仓时长挑，让这笔落在 30–60 根里；够不着挑最近的，一样近取小的。
  func testFallbackPutsTheTradeIntoThirtyToSixtyBars() {
    func pick(_ hours: Double) -> Interval {
      TradeReplayPlan.interval(preferred: nil, spec: nil, openedAt: monday, closedAt: monday + Int64(hours * Double(hour)))
    }
    XCTAssertEqual(pick(0.75), .m1)     // 46 根 1 分
    XCTAssertEqual(pick(3), .m5)        // 37 根 5 分
    XCTAssertEqual(pick(6), .m15)       // 25 根 15 分（离 30 差 5），5 分是 73 根（差 13）
    XCTAssertEqual(pick(23), .h1)       // 24 根 1 时
    XCTAssertEqual(pick(24 * 7), .h4)   // 43 根 4 时
    XCTAssertEqual(pick(24 * 60), .d1)  // 61 根 1 天
    // 不认得的服务端周期（或月线）当作没有。
    XCTAssertEqual(TradeReplayPlan.interval(preferred: nil, spec: "1M", openedAt: monday, closedAt: monday + 3 * hour), .m5)
  }

  func testBarsCountsBothEnds() {
    XCTAssertEqual(TradeReplayPlan.bars(.h1, from: monday + 10 * 60_000, to: monday + 10 * 60_000), 1)
    XCTAssertEqual(TradeReplayPlan.bars(.h1, from: monday + 59 * 60_000, to: monday + 61 * 60_000), 2)
  }

  // MARK: - 起点、停顿、收尾

  func testStartPausesAndStopAreCountedOnTheChosenInterval() throws {
    let open = monday + 34 * hour, add = monday + 38 * hour + 5 * 60_000, close = monday + 57 * hour + 30 * 60_000
    let r = round(.long, fills: [fill(1, open, .buy, 100, 1, .open), fill(2, add, .buy, 130, 2, .add),
                                 fill(3, close, .sell, 140, 3, .close)], opened: open, closed: close)
    let plan = try XCTUnwrap(TradeReplayPlan(round: r, spec: nil, preferred: nil))
    XCTAssertEqual(plan.interval, .h1)
    XCTAssertEqual(plan.openBar, open)
    XCTAssertEqual(plan.closeBar, monday + 57 * hour)
    XCTAssertEqual(plan.startBar, open - 20 * hour, "进来先静止在开仓前 20 根")
    XCTAssertEqual(plan.stopBar, monday + 62 * hour, "平仓后 5 根停")
    XCTAssertTrue(plan.pauses(at: plan.openBar))
    XCTAssertTrue(plan.pauses(at: plan.closeBar))
    XCTAssertFalse(plan.pauses(at: monday + 38 * hour), "加仓那根不停")
    XCTAssertTrue(plan.isOpenBar(plan.openBar))
    XCTAssertFalse(plan.finished(at: plan.stopBar - hour))
    XCTAssertTrue(plan.finished(at: plan.stopBar))
    let window = plan.fetchWindow(spec: nil)
    XCTAssertEqual(window.start, plan.startBar - 300 * hour, "起点再往前取 300 根给指标热身")
    XCTAssertEqual(window.end, plan.stopBar + hour)
    // 服务端窗口周期对得上才包进来。
    let wide = plan.fetchWindow(spec: TradeChartSpec(interval: "1h", start: open - 40 * hour, end: close + 30 * hour))
    XCTAssertEqual(wide.start, open - 40 * hour - 300 * hour)
    XCTAssertEqual(wide.end, close + 30 * hour)
    XCTAssertEqual(plan.fetchWindow(spec: TradeChartSpec(interval: "5m", start: 0, end: .max)).end, window.end)
  }

  func testOpenPositionsAreNotReplayed() {
    XCTAssertNil(TradeReplayPlan(round: round(.long, fills: [], opened: monday, closed: nil), spec: nil, preferred: nil))
  }

  // MARK: - 只画已经发生的、浮动盈亏

  func testMarksNeverLeakTheFutureAndAverageFollowsAdds() throws {
    let open = monday + 34 * hour, add = monday + 38 * hour, close = monday + 57 * hour
    let r = round(.long, fills: [fill(1, open, .buy, 100, 1, .open), fill(2, add, .buy, 130, 2, .add),
                                 fill(3, close, .sell, 140, 3, .close)], opened: open, closed: close)
    let plan = try XCTUnwrap(TradeReplayPlan(round: r, spec: nil, preferred: nil))
    XCTAssertTrue(plan.visibleMarks(through: open - hour).isEmpty)
    XCTAssertEqual(plan.visibleMarks(through: open).count, 1)
    XCTAssertEqual(plan.visibleMarks(through: add).count, 2)
    XCTAssertEqual(plan.visibleMarks(through: close).count, 3)
    XCTAssertNil(plan.entryAverage(through: open - hour))
    XCTAssertEqual(try XCTUnwrap(plan.entryAverage(through: open)), 100, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(plan.entryAverage(through: add)), 120, accuracy: 1e-9)
    XCTAssertEqual(plan.entrySegments(through: open - hour), [])
    XCTAssertEqual(plan.entrySegments(through: open + 2 * hour),
                   [TradeReplayPlan.Segment(from: open, to: open + 2 * hour, price: 100)])
    XCTAssertEqual(plan.entrySegments(through: close + 3 * hour),
                   [TradeReplayPlan.Segment(from: open, to: add, price: 100),
                    TradeReplayPlan.Segment(from: add, to: close, price: 120)],
                   "虚线从开仓那根画到平仓那根，加仓处换一段，不往平仓后延")
    // 多单：涨 10% 是 +0.1；持仓前后没有胶囊。
    XCTAssertEqual(try XCTUnwrap(plan.floatingReturn(close: 110, at: open)), 0.1, accuracy: 1e-9)
    XCTAssertNil(plan.floatingReturn(close: 110, at: open - hour))
    XCTAssertNil(plan.floatingReturn(close: 110, at: close))
  }

  func testShortFloatingReturnFlipsSign() throws {
    let open = monday, close = monday + 6 * hour
    let r = round(.short, fills: [fill(1, open, .sell, 200, 1, .open), fill(2, close, .buy, 180, 1, .close)],
                  opened: open, closed: close, open: 200, close: 180)
    let plan = try XCTUnwrap(TradeReplayPlan(round: r, spec: nil, preferred: nil))
    XCTAssertEqual(try XCTUnwrap(plan.floatingReturn(close: 190, at: plan.openBar)), 0.05, accuracy: 1e-9,
                   "空单价格往下走是赚")
    XCTAssertEqual(plan.marks.map(\.buy), [false, true])
    XCTAssertEqual(plan.marks.map(\.entry), [true, false])
  }

  func testMissingFillsFallBackToRoundAverages() throws {
    let plan = try XCTUnwrap(TradeReplayPlan(round: round(.long, fills: [], opened: monday, closed: monday + 3 * hour),
                                             spec: nil, preferred: nil))
    XCTAssertEqual(plan.marks.count, 2)
    XCTAssertEqual(plan.marks[0].price, 100); XCTAssertEqual(plan.marks[1].price, 110)
    XCTAssertEqual(plan.closeBar, monday + 3 * hour)
  }

  // MARK: - 进度线

  func testTrackMapsBothWaysAndReportsCrossedMarks() {
    let track = ReviewReplayTrack(lower: 100, upper: 200, marks: [120, 180])
    XCTAssertEqual(track.fraction(of: 100), 0)
    XCTAssertEqual(track.fraction(of: 150), 0.5)
    XCTAssertEqual(track.fraction(of: 300), 1, "越界夹住")
    XCTAssertEqual(track.index(at: 0.5), 150)
    XCTAssertEqual(track.index(at: 0.204), 120)
    XCTAssertEqual(track.index(at: -1), 100)
    XCTAssertEqual(track.markFractions, [0.2, 0.8])
    XCTAssertTrue(track.crossesMark(from: 110, to: 125))
    XCTAssertTrue(track.crossesMark(from: 190, to: 180), "往回拖踩上刻度也算")
    XCTAssertFalse(track.crossesMark(from: 120, to: 125), "从刻度上起手不算")
    XCTAssertFalse(track.crossesMark(from: 130, to: 170))
    XCTAssertEqual(ReviewReplayTrack(lower: 5, upper: 5).fraction(of: 5), 1)
  }
}
