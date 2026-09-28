import XCTest
@testable import KanpanCore

// 主力订单流 · 扫描半径（10%）与退出半径（15%）之间的滞回带。
//
// 线上 2026-09-28：XRP 现货 1.63 那面约 40 万、一直没动的卖墙离中间价 +9.9%，价格一摆，
// 原来每跨出 10% 一次就结束一次、跨回来又当新单起，一天被切成几十截（全天失联七成在一分钟内同档复现）。
// 手机端更糟：走出 10% 后桶不在扫描结果里、那一档本地又「知道」，于是两拍后判成「已撤销、剩 0」。
// 现在挂着的单出了 15% 才失联；10%–15% 之间直接查那一个桶照常判还在 / 撤单 / 成交；新单仍只在 10% 以内起。
// 与服务端 kanpan-api `orderflow_history::model` 的同名用例对齐（提交 93e8610c）。

final class OrderFlowExitRadiusTests: XCTestCase {
  /// 步长 1 美元，永续门槛 500 万（退出线 250 万）。
  private let thresholds = OrderFlowThresholds(spot: 1_000_000, usdtPerp: 5_000_000, coinPerp: 5_000_000,
                                               delivery: 5_000_000, step: 1)
  private let okx = OrderFlowVenue(exchange: "okx", label: "OKX", product: .usdtPerp, instrument: "ETH-USDT-SWAP",
                                   notional: .linear(multiplier: 1), sequenceModel: .previousFinalExact,
                                   snapshotInBand: true)
  private var seq: Int64 = 0
  private let million = 1_000_000.0

  /// 买一 `best`、卖一 `best + 1`（中间价 `best + 0.5`）；1000 那档挂 `bidWall` 美元的买墙，1225 那档挂 `askWall` 美元的卖墙。
  /// 各档离中间价：买一 1110 → 买墙 −9.95%、卖墙 +10.31%；买一 1117 → 买墙 −10.51%、卖墙 +9.62%；
  /// 买一 1162 → 买墙 −13.98%；买一 1190 → 买墙 −16.0%。
  private func book(best: Double, bidWall: Double, askWall: Double = 0) -> BookSnapshot {
    var bids = [BookLevel(price: best, quantity: 1)]
    if bidWall > 0 { bids.append(BookLevel(price: 1_000, quantity: bidWall / 1_000)) }
    var asks = [BookLevel(price: best + 1, quantity: 1)]
    if askWall > 0 { asks.append(BookLevel(price: 1_225, quantity: askWall / 1_225)) }
    seq += 1
    return BookSnapshot(lastUpdateID: seq, requestedLevels: 1_000, bids: bids, asks: asks)
  }

  private func feed(_ model: inout OrderFlowModel, best: Double, bidWall: Double, askWall: Double = 0) {
    XCTAssertEqual(model.ingest(okx.id, .snapshot(book(best: best, bidWall: bidWall, askWall: askWall)), nowMs: 0), .none)
  }

  private func model() -> OrderFlowModel {
    var model = OrderFlowModel(symbol: "ETHUSDT", thresholds: thresholds)
    model.addVenue(okx)
    _ = model.connectionOpened(okx.id)
    return model
  }

  /// 一面 600 万的买墙在 −9.95% 处挂出来（0 ms 起、500 ms 确认）。
  private func wallAtTheEdge() -> OrderFlowModel {
    var m = model()
    feed(&m, best: 1_110, bidWall: 6 * million)
    _ = m.evaluate(nowMs: 0)
    _ = m.evaluate(nowMs: 500)
    XCTAssertEqual(m.orders.count, 1)
    XCTAssertTrue(m.orders.first?.isLive ?? false)
    return m
  }

  /// 价格把墙推到 −10.5%、再到 −14%：同一条单一直挂着、照样更新名义；到 −16% 才失联，按最后一次看到的时刻结束。
  /// 原来一出 10% 就走撤单确认，两拍后判成「已撤销、剩 0」。
  func testAWallDriftingPastTenPercentStaysLiveUntilFifteen() throws {
    var m = wallAtTheEdge()
    feed(&m, best: 1_117, bidWall: 6 * million)
    _ = m.evaluate(nowMs: 1_000)
    _ = m.evaluate(nowMs: 1_500)
    XCTAssertEqual(m.orders.count, 1)
    XCTAssertTrue(m.orders[0].isLive, "−10.5%：还在 15% 以内，接着跟")

    feed(&m, best: 1_162, bidWall: 7 * million)
    _ = m.evaluate(nowMs: 2_000)
    _ = m.evaluate(nowMs: 2_500)
    XCTAssertEqual(m.orders.count, 1)
    let live = m.orders[0]
    XCTAssertTrue(live.isLive, "−14%：还在 15% 以内，接着跟")
    XCTAssertEqual(live.firstSeenMs, 0, "还是最早那一条")
    XCTAssertEqual(live.notional, 7 * million, accuracy: 1, "10% 外也照样读名义")

    feed(&m, best: 1_190, bidWall: 7 * million)
    _ = m.evaluate(nowMs: 3_000)
    let ended = m.orders[0]
    XCTAssertEqual(ended.status, .lost, "−16%：出了退出半径，失联而不是撤单")
    XCTAssertEqual(ended.endMs, 2_500, "按最后一次看到的时刻结束")
    XCTAssertNil(ended.vanishedNotional, "失联不记消失名义")
    _ = m.evaluate(nowMs: 3_500)
    XCTAssertEqual(m.orders.count, 1, "15% 外不起新单")
  }

  /// 价格来回摆、两面墙轮流跨 10% 线：各自始终是同一条，不结束、不重起。
  func testWallsSwingingAcrossTheScanLineStayOneOrderEach() {
    var m = model()
    feed(&m, best: 1_110, bidWall: 6 * million, askWall: 6 * million)
    _ = m.evaluate(nowMs: 0)
    _ = m.evaluate(nowMs: 500)   // 买墙（−9.95%）出现；卖墙 +10.31% 不起
    feed(&m, best: 1_117, bidWall: 6 * million, askWall: 6 * million)
    _ = m.evaluate(nowMs: 1_000)
    _ = m.evaluate(nowMs: 1_500) // 卖墙（+9.62%）出现；买墙 −10.51% 接着跟
    var now: Int64 = 1_500
    for k in 0..<20 {
      now += 500
      feed(&m, best: k % 2 == 0 ? 1_110 : 1_117, bidWall: 6 * million, askWall: 6 * million)
      _ = m.evaluate(nowMs: now)
    }
    XCTAssertEqual(m.orders.count, 2, "来回跨 10% 线不该切成好几截：\(m.orders.map { ($0.side, $0.status, $0.firstSeenMs) })")
    XCTAssertTrue(m.orders.allSatisfy(\.isLive))
    XCTAssertEqual(m.orders.first { $0.side == .bid }?.firstSeenMs, 0)
    XCTAssertEqual(m.orders.first { $0.side == .ask }?.firstSeenMs, 1_000)
  }

  /// 10%–15% 之间被撤掉：照常两拍确认、判已撤销，消失的按峰值算；同一面墙在 10% 外重新挂出来不当新单，
  /// 回到 10% 以内才重新起。
  func testAWallPulledBetweenScanAndExitRadiusIsCancelled() throws {
    var m = wallAtTheEdge()
    feed(&m, best: 1_117, bidWall: 6 * million)
    _ = m.evaluate(nowMs: 1_000)
    feed(&m, best: 1_117, bidWall: 0)
    _ = m.evaluate(nowMs: 1_500)
    _ = m.evaluate(nowMs: 2_000)
    let o = m.orders[0]
    XCTAssertEqual(o.status, .cancelled, "10% 外、15% 内照样判得出撤单")
    XCTAssertEqual(o.endMs, 1_500)
    XCTAssertEqual(try XCTUnwrap(o.vanishedNotional), 6 * million, accuracy: 1)

    feed(&m, best: 1_117, bidWall: 6 * million)
    _ = m.evaluate(nowMs: 2_500)
    _ = m.evaluate(nowMs: 3_000)
    _ = m.evaluate(nowMs: 3_500)
    XCTAssertEqual(m.orders.count, 1, "新单只在 10% 以内起")

    feed(&m, best: 1_110, bidWall: 6 * million)
    _ = m.evaluate(nowMs: 4_000)
    _ = m.evaluate(nowMs: 4_500)
    XCTAssertEqual(m.orders.filter(\.isLive).map(\.firstSeenMs), [4_000], "回到 10% 以内按新单重新确认")
  }

  /// 10%–15% 之间被吃掉九成：成交照常记到这一桶上，消失后判已成交。
  func testAWallEatenBetweenScanAndExitRadiusIsFilled() {
    var m = wallAtTheEdge()
    feed(&m, best: 1_117, bidWall: 6 * million)
    _ = m.evaluate(nowMs: 1_000)
    _ = m.ingest(okx.id, .trade(OrderFlowTrade(price: 1_000.4, quantity: 6_000 * 0.9, hitSide: .bid, timeMs: 0)),
                 nowMs: 1_200)
    feed(&m, best: 1_117, bidWall: 0)
    _ = m.evaluate(nowMs: 1_500)
    _ = m.evaluate(nowMs: 2_000)
    let o = m.orders[0]
    XCTAssertEqual(o.status, .filled)
    XCTAssertEqual(o.endMs, 1_500)
    XCTAssertGreaterThan(o.filledNotional, 5 * million)
  }

  /// 单桶读法：整桶合计、记下名义最大那一档的价，不受扫描半径限制；与扫描结果同一套桶号。
  func testVenueBookReadsASingleBucketBeyondTheScanRadius() throws {
    var venue = VenueBook(venue: okx)
    _ = venue.connectionOpened()
    let snapshot = BookSnapshot(lastUpdateID: 1, requestedLevels: 1_000,
                                bids: [BookLevel(price: 1_117, quantity: 1), BookLevel(price: 1_000.5, quantity: 2_000),
                                       BookLevel(price: 1_000, quantity: 1_000), BookLevel(price: 999.9, quantity: 5)],
                                asks: [BookLevel(price: 1_118, quantity: 1)])
    XCTAssertEqual(venue.ingest(.snapshot(snapshot), nowMs: 0), .none)
    let scheme = try XCTUnwrap(BucketScheme(step: 1))
    let wall = try XCTUnwrap(venue.bucket(BucketKey(side: .bid, index: 1_000), scheme: scheme))
    XCTAssertEqual(wall.notional, 1_000 * 1_000 + 1_000.5 * 2_000, accuracy: 1e-6)
    XCTAssertEqual(wall.price, 1_000.5)
    XCTAssertEqual(try XCTUnwrap(venue.bucket(BucketKey(side: .bid, index: 999), scheme: scheme)).notional,
                   999.9 * 5, accuracy: 1e-6)
    XCTAssertNil(venue.bucket(BucketKey(side: .ask, index: 1_000), scheme: scheme), "另一侧、空桶")
    XCTAssertNil(venue.buckets(scheme: scheme, radiusBps: OrderFlowDefaults.scanRadiusBps)?[BucketKey(side: .bid, index: 1_000)],
                 "−10.5% 外（中间价 1117.5）：不在扫描结果里")
    let wide = try XCTUnwrap(venue.buckets(scheme: scheme, radiusBps: OrderFlowDefaults.exitRadiusBps))
    XCTAssertEqual(wide[BucketKey(side: .bid, index: 1_000)]?.notional ?? 0, wall.notional, accuracy: 1e-6,
                   "和按半径扫出来的同一个数")
  }
}
