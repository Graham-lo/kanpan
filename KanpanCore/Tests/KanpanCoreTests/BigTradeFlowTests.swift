import XCTest
@testable import KanpanCore

// 大单与爆仓 · 分钟桶、服务端接缝、弹层摘要、爆仓（照 Web/tests/orderflow-bigtags.test.ts 搬）。

final class BigTradeFlowTests: XCTestCase {
  /// 2026-10-08 02:00 UTC = 北京时间 10:00。
  let t0: Int64 = 1_791_424_800_000
  let m = BigTradeFlow.minuteMs

  private func flow(cut: Double = 1000) -> BigTradeFlow {
    var f = BigTradeFlow(symbol: "SOLUSDT")
    f.record(timeMs: t0 - 3_600_000, price: 0, usd: 1, buy: true, cut: cut)  // 只为记下大单线
    return f
  }

  /// 连着心跳 [a, b]（每半秒一拍）。
  private func beats(_ f: inout BigTradeFlow, _ a: Int64, _ b: Int64) {
    var t = a
    while t <= b { f.beat(nowMs: t, ok: true); t += 500 }
  }

  func testRecordBucketsBigTradesByMinute() {
    var f = flow()
    XCTAssertTrue(f.record(timeMs: t0 + 1_000, price: 100, usd: 5_000, buy: true, cut: 1000))
    XCTAssertTrue(f.record(timeMs: t0 + 20_000, price: 101, usd: 2_000, buy: true, cut: 1000))
    XCTAssertTrue(f.record(timeMs: t0 + 59_999, price: 99, usd: 3_000, buy: false, cut: 1000))
    XCTAssertFalse(f.record(timeMs: t0 + 30_000, price: 99, usd: 999, buy: false, cut: 1000), "不到大单线不记")
    XCTAssertTrue(f.record(timeMs: t0 + m, price: 99, usd: 4_000, buy: false, cut: 1000))
    XCTAssertEqual(f.minutes[t0], BigTradeCell(buyUsd: 7_000, sellUsd: 3_000, buyCount: 2, sellCount: 1))
    XCTAssertEqual(f.minutes[t0 + m], BigTradeCell(sellUsd: 4_000, sellCount: 1))
    XCTAssertEqual(f.prints.count, 4)
    XCTAssertEqual(f.lastTradeMs, t0 + m, "最近一笔成交不论大小")
    XCTAssertEqual(f.lastBig?.timeMs, t0 + m)
    XCTAssertEqual(f.lastBig?.buy, false)
  }

  func testServerCutWinsOverLocal() {
    var f = flow(cut: 1000)
    f.merge(BigTradeFlowPage(tracked: true, bigUsd: 5_000, rows: []), nowMs: t0)
    XCTAssertEqual(f.cut, 5_000)
    XCTAssertFalse(f.record(timeMs: t0, price: 1, usd: 4_000, buy: true, cut: 1000), "服务端的大单线优先")
  }

  func testCoverJoinsBeatsAndBreaksAfterGap() {
    var f = flow()
    beats(&f, t0, t0 + 30_000)
    XCTAssertEqual(f.cover.count, 1)
    f.beat(nowMs: t0 + 30_000 + 10_001, ok: true)
    XCTAssertEqual(f.cover.count, 2, "隔 10 秒以上另起一段")
    XCTAssertTrue(f.covered(t0, t0 + 30_000, nowMs: t0 + 40_001))
    XCTAssertFalse(f.covered(t0, t0 + 40_000, nowMs: t0 + 40_001))
    // 正在走的那根（b 在未来）：覆盖没断就算
    XCTAssertTrue(f.covered(t0 + 40_001, t0 + 100_000, nowMs: t0 + 40_001))
  }

  func testSeamUsesServerBeforeCoverAndLocalAfter() {
    var f = flow()
    // 服务端：t0 .. t0+4m 每分钟一行；t0+2m 那分钟没有行（在跟 = 没成交）
    let rows = [0, 1, 3, 4].map { BigTradeFlowPage.Row(minuteMs: t0 + Int64($0) * m, buyUsd: 10_000, sellUsd: 1_000) }
    f.merge(BigTradeFlowPage(tracked: true, bigUsd: nil, rows: rows), nowMs: t0 + 5 * m)
    // 本机从 t0+3m 起整分钟在记
    beats(&f, t0 + 3 * m, t0 + 6 * m)
    f.record(timeMs: t0 + 3 * m + 5_000, price: 100, usd: 2_000, buy: true, cut: 1000)
    f.record(timeMs: t0 + 1 * m + 5_000, price: 100, usd: 7_777, buy: true, cut: 1000)  // 覆盖之前：服务端那行为准
    let now = t0 + 6 * m
    let a = f.sum(t0, t0 + 3 * m, nowMs: now)
    XCTAssertEqual(a.buyUsd, 20_000)
    XCTAssertEqual(a.sellUsd, 2_000)
    XCTAssertNil(a.buyCount, "有服务端的行就没有笔数")
    XCTAssertTrue(a.has)
    let b = f.sum(t0 + 3 * m, t0 + 4 * m, nowMs: now)
    XCTAssertEqual(b.buyUsd, 2_000, "整分钟在覆盖区间里：用本机的")
    XCTAssertEqual(b.buyCount, 1)
    let gap = f.sum(t0 + 2 * m, t0 + 3 * m, nowMs: now)
    XCTAssertTrue(gap.has)
    XCTAssertEqual(gap.total, 0)
    XCTAssertEqual(gap.buyCount, 0)
  }

  func testUntrackedUsesLocalOnly() {
    var f = flow()
    f.merge(BigTradeFlowPage(tracked: false, bigUsd: nil, rows: []), nowMs: t0)
    f.record(timeMs: t0 + 5_000, price: 100, usd: 2_000, buy: false, cut: 1000)
    let s = f.sum(t0, t0 + m, nowMs: t0 + m)
    XCTAssertEqual(s.sellUsd, 2_000)
    XCTAssertEqual(s.sellCount, 1)
    XCTAssertFalse(f.sum(t0 - 10 * m, t0, nowMs: t0 + m).has)
  }

  func testFetchFromIsThreeDaysThenIncremental() {
    var f = flow()
    XCTAssertEqual(f.serverFetchFrom(nowMs: t0), t0 - BigTradeFlow.keepMs)
    f.merge(BigTradeFlowPage(tracked: true, bigUsd: nil, rows: [.init(minuteMs: t0 - m, buyUsd: 1, sellUsd: 0)]), nowMs: t0)
    XCTAssertEqual(f.serverFetchFrom(nowMs: t0), t0 - m)
  }

  func testPruneDropsOldMinutesPrintsAndServerRows() {
    var f = flow()
    f.record(timeMs: t0, price: 100, usd: 5_000, buy: true, cut: 1000)
    f.merge(BigTradeFlowPage(tracked: true, bigUsd: nil, rows: [.init(minuteMs: t0, buyUsd: 1, sellUsd: 0),
                                                                 .init(minuteMs: t0 + BigTradeFlow.keepMs, buyUsd: 1, sellUsd: 0)]),
            nowMs: t0)
    f.beat(nowMs: t0 + BigTradeFlow.printKeepMs + 1, ok: false)
    XCTAssertTrue(f.prints.isEmpty, "逐笔价位只留 2 小时")
    f.beat(nowMs: t0 + BigTradeFlow.keepMs + m, ok: false)
    XCTAssertNil(f.minutes[t0])
    XCTAssertNil(f.serverRows[t0])
    XCTAssertEqual(f.serverRange?.lowerBound, t0 + BigTradeFlow.keepMs)
  }

  func testTapeMergesAndBarsAggregateByOpens() {
    var f = flow()
    f.merge(BigTradeFlowPage(tracked: true, bigUsd: nil, rows: [.init(minuteMs: t0, buyUsd: 3_000, sellUsd: 0),
                                                                 .init(minuteMs: t0 + 2 * m, buyUsd: 0, sellUsd: 0)]),
            nowMs: t0 + 3 * m)
    beats(&f, t0 + 3 * m, t0 + 5 * m)
    f.record(timeMs: t0 + 3 * m + 1, price: 100, usd: 2_000, buy: false, cut: 1000)
    f.record(timeMs: t0 + 4 * m + 1, price: 100, usd: 5_000, buy: true, cut: 1000)
    let tape = f.tape(nowMs: t0 + 5 * m, floor: 10_000)
    XCTAssertEqual(tape.minutes, [t0, t0 + 3 * m, t0 + 4 * m], "没大单的分钟不进")
    let bars = tape.bars(opens: [t0, t0 + 3 * m], lastEnd: t0 + 6 * m)
    XCTAssertEqual(bars.buy, [3_000, 5_000])
    XCTAssertEqual(bars.sell, [0, 2_000])
    XCTAssertEqual(tape.sum(t0 + 3 * m, t0 + 4 * m).sell, 2_000)
    XCTAssertEqual(tape.lastBigMs, t0 + 4 * m + 1)
  }

  func testEqualityFollowsVersion() {
    var a = flow()
    let b = a
    XCTAssertEqual(a, b)
    a.beat(nowMs: t0, ok: true)
    XCTAssertNotEqual(a, b, "新起一段覆盖算变化")
    let c = a
    a.beat(nowMs: t0 + 500, ok: true)
    XCTAssertEqual(a, c, "覆盖往后接不算（界面用 now 自己算）")
  }

  // MARK: - 摘要

  func testDayStartIsBeijingMidnight() {
    let utc1559 = Int64(1_791_388_740_000)  // 2026-10-07 15:59 UTC
    XCTAssertEqual(BigTradeDigest.dayStart8(utc1559), 1_791_302_400_000)  // 2026-10-06 16:00 UTC
    XCTAssertEqual(BigTradeDigest.dayStart8(utc1559 + m), utc1559 + m)
  }

  func testWindowsBarHourToday() {
    var f = flow()
    beats(&f, t0 - 3 * 3_600_000, t0 + 15 * m)
    f.record(timeMs: t0 - 2 * 3_600_000, price: 1, usd: 9_000, buy: true, cut: 1000)  // 今日、不在近 1 小时
    f.record(timeMs: t0 - 30 * m, price: 1, usd: 4_000, buy: false, cut: 1000)        // 近 1 小时
    f.record(timeMs: t0 + 14 * m, price: 1, usd: 2_000, buy: true, cut: 1000)        // 本根
    let w = BigTradeDigest.windows(f, barT0: t0, barT1: t0 + 15 * m, nowMs: t0 + 15 * m - 1)
    XCTAssertEqual(w.bar.buyUsd, 2_000)
    XCTAssertEqual(w.hour.buyUsd, 2_000)
    XCTAssertEqual(w.hour.sellUsd, 4_000)
    XCTAssertEqual(w.today.buyUsd, 11_000)
    XCTAssertEqual(w.today.buyCount, 2)
  }

  func testLadderLocalPricesAndServerTypical() {
    var f = flow()
    f.merge(BigTradeFlowPage(tracked: true, bigUsd: nil, rows: [.init(minuteMs: t0 - 10 * m, buyUsd: 6_000, sellUsd: 1_000),
                                                                 .init(minuteMs: t0 - 9 * m, buyUsd: 6_000, sellUsd: 0)]),
            nowMs: t0)
    beats(&f, t0, t0 + 3 * m)
    f.record(timeMs: t0 + 10, price: 100.4, usd: 2_000, buy: true, cut: 1000)
    f.record(timeMs: t0 + 20, price: 101.9, usd: 3_000, buy: false, cut: 1000)
    f.record(timeMs: t0 + 30, price: 120, usd: 3_000, buy: false, cut: 1000)  // 五档以外不进
    let typical: (Int64) -> Double? = { $0 == self.t0 - 10 * self.m ? 99.5 : nil }  // 第二行取不到 K 线：不算
    let rows = BigTradeDigest.ladder(f, step: 1, price: 100.7, nowMs: t0 + 3 * m, typical: typical)
    XCTAssertEqual(rows.count, 11)
    XCTAssertEqual(rows.first?.price, 105)
    XCTAssertEqual(rows.last?.price, 95)
    XCTAssertEqual(rows.first { $0.price == 100 }?.buyUsd, 2_000)
    XCTAssertEqual(rows.first { $0.price == 101 }?.sellUsd, 3_000)
    XCTAssertEqual(rows.first { $0.price == 99 }?.buyUsd, 6_000)
    XCTAssertEqual(rows.first { $0.price == 99 }?.sellUsd, 1_000)
    XCTAssertEqual(rows.reduce(0) { $0 + $1.buyUsd + $1.sellUsd }, 12_000)
  }

  func testNearestWallsOnlyLiveAndSummedPerBucket() {
    func order(_ side: BookSide, _ bucket: Int64, _ price: Double, _ usd: Double, _ status: BigOrder.Status = .live,
               venue: String = "binance:usdtPerp:SOLUSDT") -> BigOrder {
      BigOrder(venueID: venue, exchange: "binance", product: .usdtPerp, side: side, bucket: bucket, price: price,
               firstSeenMs: t0, status: status, initialNotional: usd, notional: usd, threshold: 1)
    }
    let orders = [order(.ask, 102, 102, 1_000_000), order(.ask, 102, 102.2, 500_000, venue: "okx:usdtPerp:SOL"),
                  order(.ask, 105, 105, 9_000_000), order(.ask, 101, 101, 9_000_000, .cancelled),
                  order(.bid, 98, 98, 2_000_000), order(.bid, 99, 99.5, 700_000), order(.bid, 103, 103, 1, .live)]
    let w = BigTradeDigest.nearestWalls(orders, mid: 100)
    XCTAssertEqual(w.ask?.bucket, 102)
    XCTAssertEqual(w.ask?.usd, 1_500_000)
    XCTAssertEqual(w.ask?.price, 102)
    XCTAssertEqual(w.bid?.price, 99.5)
    XCTAssertEqual(w.bid?.usd, 700_000)
  }

  // MARK: - 爆仓

  func testLiquidationSumMaxAndWindow() {
    var book = LiquidationBook(base: "SOL")
    book.merge(LiquidationPage(tracked: true, rows: [
      LiquidationRow(minuteMs: t0, longUsd: 100, shortUsd: 50, count: 2, maxUsd: 80, maxPrice: 10, maxIsLong: true),
      LiquidationRow(minuteMs: t0 + m, longUsd: 0, shortUsd: 900, count: 1, maxUsd: 900, maxPrice: 11, maxIsLong: false,
                     maxExchange: .okx),
      LiquidationRow(minuteMs: t0 + 2 * m, longUsd: 5, shortUsd: 0, count: 1, maxUsd: 5, maxPrice: 9),
    ]), nowMs: t0 + 3 * m)
    let s = book.sum(t0, t0 + 2 * m)
    XCTAssertEqual(s.longUsd, 100)
    XCTAssertEqual(s.shortUsd, 950)
    XCTAssertEqual(s.count, 3)
    XCTAssertEqual(s.max?.maxUsd, 900)
    XCTAssertEqual(s.max?.maxExchange, .okx)
    XCTAssertEqual(book.fetchFrom(nowMs: t0 + 3 * m), t0 + 2 * m - LiquidationBook.overlapMs)
    XCTAssertEqual(LiquidationBook(base: "X").fetchFrom(nowMs: t0), t0 - LiquidationBook.keepMs)
  }

  func testLiquidationPruneAndTimeline() {
    var book = LiquidationBook(base: "SOL")
    let cell = Int64(15 * 60_000)
    let now = t0 + 7 * m
    book.merge(LiquidationPage(tracked: true, rows: [
      LiquidationRow(minuteMs: now - LiquidationBook.keepMs - m, longUsd: 1, shortUsd: 0, count: 1),
      LiquidationRow(minuteMs: t0, longUsd: 10, shortUsd: 0, count: 1),
      LiquidationRow(minuteMs: t0 - cell, longUsd: 0, shortUsd: 20, count: 1),
    ]), nowMs: now)
    XCTAssertEqual(book.rows.count, 2, "超过 3 天的行丢掉")
    let line = book.timeline(nowMs: now)
    XCTAssertEqual(line.count, 96)
    XCTAssertEqual(line[95].longUsd, 10)
    XCTAssertEqual(line[94].shortUsd, 20)
  }
}
