import XCTest
@testable import KanpanCore

// 主力订单流 · 簿的覆盖范围：本地看不见的档是「不知道」，不是「没了」。
//
// - 快照被截断（币安合约 REST 1000 档、现货 5000 档）：快照最远一档以外、增量又没推过的价位看不见——
//   挂在那里的单不判撤单、不判失联、不记消失名义、也不开始撤单确认；价格把它推出 15%（退出半径）才按
//   最后一次**真看到**的时刻失联结束。
// - OKX `books` 400 档是滑动窗口：被挤出窗口的一档推 0，和真撤单长得一样；只有窗口最深一档以内才算知道。
// - 裁过远处的簿：保留区间到过的最高下沿以外同理（裁掉的、拒收的都在那外面）。

final class OrderFlowCoverageBookTests: XCTestCase {
  private func level(_ price: Double, _ quantity: Double) -> BookLevel { BookLevel(price: price, quantity: quantity) }
  private func delta(_ id: Int64, bids: [BookLevel] = [], asks: [BookLevel] = []) -> BookDelta {
    BookDelta(firstUpdateID: id, finalUpdateID: id, previousFinalUpdateID: nil, bids: bids, asks: asks)
  }

  /// OKX 式窗口 4 档：买 99、98、97、96，卖 101…104。
  private func windowBook() throws -> LocalBook {
    var book = LocalBook(sequenceModel: .strictIncrementing)
    book.retainBps = 2 * OrderFlowDefaults.scanRadiusBps
    try book.replaceFromStreamSnapshot(BookSnapshot(
      lastUpdateID: 1, requestedLevels: 4, bids: (0..<4).map { level(99 - Double($0), 1) },
      asks: (0..<4).map { level(101 + Double($0), 1) }, slidingWindow: true))
    return book
  }

  /// 盘口新挂一档把最深那档挤出窗口（推 0）：那一档读成「不知道」；窗口以内删掉的仍是「知道、没了」。
  func testSlidingWindowExitIsUnknownButInsideCancelIsKnown() throws {
    var book = try windowBook()
    XCTAssertTrue(book.knows(.bid, price: 96))
    XCTAssertFalse(book.knows(.bid, price: 95), "窗口最深一档以外：不知道")
    try book.apply(delta(2, bids: [level(99.5, 1), level(96, 0)]))
    XCTAssertFalse(book.knows(.bid, price: 96), "被挤出窗口：不知道，不是撤单")
    XCTAssertTrue(book.knows(.bid, price: 97))
    // 真撤掉最深那一档：第 5 档（95）补进窗口、落在它更深处，撤掉的那档仍在窗口内。
    try book.apply(delta(3, bids: [level(97, 0), level(95, 2)]))
    XCTAssertTrue(book.knows(.bid, price: 97), "窗口内撤掉：知道、没了")
    XCTAssertTrue(book.knows(.bid, price: 96), "补进来的 95 在更深处，96 又回到窗口里（空的）")
    XCTAssertFalse(book.knows(.bid, price: 94))
    // 卖侧对称。
    try book.apply(delta(4, asks: [level(100.5, 1), level(104, 0)]))
    XCTAssertFalse(book.knows(.ask, price: 104))
    XCTAssertTrue(book.knows(.ask, price: 103))
  }

  /// 整本簿都比窗口小（表不满）：整侧都知道。窗口的簿不裁远处（表本来就封顶窗口档数）。
  func testSlidingWindowNotFullKnowsEverythingAndIsNotTrimmed() throws {
    var book = LocalBook(sequenceModel: .strictIncrementing)
    book.retainBps = 2 * OrderFlowDefaults.scanRadiusBps
    try book.replaceFromStreamSnapshot(BookSnapshot(
      lastUpdateID: 1, requestedLevels: 400, bids: [level(99, 1), level(50, 1)], asks: [level(101, 1), level(300, 1)],
      slidingWindow: true))
    _ = book.forEachLevel(withinBps: OrderFlowDefaults.scanRadiusBps) { _, _, _ in }
    XCTAssertEqual(book.quantity(at: 50, side: .bid), 1, "窗口的簿不裁远处")
    XCTAssertEqual(book.quantity(at: 300, side: .ask), 1)
    XCTAssertTrue(book.knows(.bid, price: 10))
    try book.apply(delta(2, bids: [level(50, 0)]))
    XCTAssertTrue(book.knows(.bid, price: 50), "表不满说明整本都在窗口里：删掉就是没了")
  }

  /// 最深价缓存：撤掉最深一档后下一次问才重算，结果和整表找最小一致。
  func testWorstPriceCacheTracksTheDeepestLevel() throws {
    var book = try windowBook()
    for id in Int64(2)...400 {
      // 在 90…98.9 里随机加删，最优价 99 不动。
      let p = 90 + Double((id * 37) % 90) / 10
      try book.apply(delta(id, bids: [level(p, id % 3 == 0 ? 0 : 1)]))
      let expected = book.bids.levels.keys.min()
      XCTAssertEqual(book.bids.worstPrice(), expected)
      var copy = book.bids
      XCTAssertEqual(copy.worstPrice(), expected)
    }
  }

  /// 整本快照（不截断）的簿裁过远处以后：保留区间到过的最高下沿以外「表里没有」不再等于没有；
  /// 价格回来以后仍是不知道（裁掉、拒收的都在那外面），增量推到的才知道。
  func testTrimmedRegionOfAFullBookIsUnknown() throws {
    var book = LocalBook(sequenceModel: .strictIncrementing)
    book.retainBps = 2 * OrderFlowDefaults.scanRadiusBps
    try book.replaceFromStreamSnapshot(BookSnapshot(
      lastUpdateID: 1, requestedLevels: 1_000, bids: [level(99, 1), level(90, 1), level(70, 1)],
      asks: [level(101, 1), level(130, 1)]))
    XCTAssertEqual(book.quantity(at: 70, side: .bid), 0, "−30%：整本写进来就裁掉")
    XCTAssertTrue(book.knows(.bid, price: 85))
    XCTAssertFalse(book.knows(.bid, price: 70), "裁掉的地方：不知道")
    XCTAssertFalse(book.knows(.ask, price: 130))
    // 中间价涨到 110（下沿 88）又回到 100：85 那一带期间一直在保留区间外，推来的正数都被拒收过，仍是不知道。
    try book.apply(delta(2, bids: [level(109.5, 1)], asks: [level(101, 0), level(110.5, 1)]))
    _ = book.forEachLevel(withinBps: OrderFlowDefaults.scanRadiusBps) { _, _, _ in }
    try book.apply(delta(3, bids: [level(109.5, 0), level(85, 4)], asks: [level(100.5, 1)]))
    XCTAssertEqual(book.quantity(at: 85, side: .bid), 0, "当时在保留区间外，拒收")
    XCTAssertFalse(book.knows(.bid, price: 85))
    _ = book.forEachLevel(withinBps: OrderFlowDefaults.scanRadiusBps) { _, _, _ in }
    try book.apply(delta(4, bids: [level(86, 3), level(87, 0)]))
    XCTAssertTrue(book.knows(.bid, price: 86), "回到保留区间后推来的：表里有")
    XCTAssertTrue(book.knows(.bid, price: 87), "回到保留区间后推成 0 的：知道是空的")
    XCTAssertFalse(book.knows(.bid, price: 85))
    XCTAssertTrue(book.knows(.bid, price: 89), "一直在保留区间里的：表里没有就是没有")
  }

  /// 覆盖范围随增量扩大：快照以外的价位被增量推到（加量或推 0）就知道了。
  func testCoverageWidensWhenDeltasReachFurther() throws {
    var book = LocalBook(sequenceModel: .strictIncrementing)
    book.retainBps = 2 * OrderFlowDefaults.scanRadiusBps
    try book.replaceFromStreamSnapshot(BookSnapshot(
      lastUpdateID: 1, requestedLevels: 2, bids: [level(99, 1), level(98, 1)], asks: [level(101, 1), level(102, 1)]))
    _ = book.forEachLevel(withinBps: OrderFlowDefaults.scanRadiusBps) { _, _, _ in }
    XCTAssertFalse(book.knows(.bid, price: 92))
    XCTAssertFalse(book.knows(.ask, price: 108))
    try book.apply(delta(2, bids: [level(92, 5)], asks: [level(108, 0)]))
    XCTAssertTrue(book.knows(.bid, price: 92))
    XCTAssertTrue(book.knows(.ask, price: 108))
    XCTAssertFalse(book.knows(.bid, price: 93), "推到的那一档才知道，不整段放宽（币安只推变了的档）")
  }
}

final class OrderFlowCoverageModelTests: XCTestCase {
  /// 步长 1 美元，永续门槛 500 万。
  private let thresholds = OrderFlowThresholds(spot: 1_000_000, usdtPerp: 5_000_000, coinPerp: 5_000_000,
                                               delivery: 5_000_000, step: 1)
  private let venue = OrderFlowVenue(exchange: "okx", label: "OKX", product: .usdtPerp, instrument: "ETH-USDT-SWAP",
                                     notional: .linear(multiplier: 1), sequenceModel: .strictIncrementing,
                                     snapshotInBand: true)
  private let million = 1_000_000.0
  private var seq: Int64 = 1

  private func level(_ price: Double, _ quantity: Double) -> BookLevel { BookLevel(price: price, quantity: quantity) }

  private func push(_ model: inout OrderFlowModel, bids: [BookLevel] = [], asks: [BookLevel] = [], nowMs: Int64) {
    seq += 1
    XCTAssertEqual(model.ingest(venue.id, .delta(BookDelta(firstUpdateID: seq, finalUpdateID: seq, previousFinalUpdateID: nil,
                                                          bids: bids, asks: asks)), nowMs: nowMs), .none)
  }

  /// 读回一条挂在 1000（离中间价 1110.5 −9.95%）的 600 万买墙；新快照只盖到 1109（被截断）。
  private func restoredFarWall(savedAtMs: Int64) -> OrderFlowModel {
    let wall = BigOrder(venueID: venue.id, exchange: venue.label, product: .usdtPerp, side: .bid, bucket: 1_000,
                        price: 1_000, firstSeenMs: 0, initialNotional: 6 * million, notional: 6 * million,
                        threshold: 5 * million)
    var model = OrderFlowModel(symbol: "ETHUSDT", thresholds: thresholds,
                               restored: OrderFlowJournal(symbol: "ETHUSDT", step: 1, savedAtMs: savedAtMs, orders: [wall]))
    model.addVenue(venue)
    _ = model.connectionOpened(venue.id)
    _ = model.ingest(venue.id, .snapshot(BookSnapshot(
      lastUpdateID: 1, requestedLevels: 3, bids: [level(1_110, 1), level(1_109.5, 1), level(1_109, 1)],
      asks: [level(1_111, 1), level(1_111.5, 1), level(1_112, 1)])), nowMs: savedAtMs)
    return model
  }

  /// 快照盖不到的远墙：一拍拍评估下去既不撤单、也不失联、不记消失名义；价格把它推出 15% 才失联，
  /// 结束时刻是存盘那一刻（最后一次真看到），不是走出去那一拍。
  func testFarWallOutsideCoverageIsNeitherCancelledNorLost() throws {
    var m = restoredFarWall(savedAtMs: 5_000)
    for k in 0..<20 { _ = m.evaluate(nowMs: 6_000 + Int64(k) * 500) }
    XCTAssertEqual(m.orders.count, 1)
    let o = m.orders[0]
    XCTAssertTrue(o.isLive, "看不见不等于没了：\(o.status)")
    XCTAssertNil(o.endMs)
    XCTAssertNil(o.vanishedNotional)
    XCTAssertEqual(o.notional, 6 * million, "看不见时名义不动")

    // 卖一涨到 1180（买墙 −15.3%）：出了退出半径，失联。
    push(&m, bids: [level(1_179, 1)], asks: (0..<3).map { level(1_111 + Double($0) / 2, 0) } + [level(1_180, 1)], nowMs: 16_000)
    _ = m.evaluate(nowMs: 16_500)
    let ended = m.orders[0]
    XCTAssertEqual(ended.status, .lost)
    XCTAssertEqual(ended.endMs, 5_000, "按最后一次真看到（存盘那一刻）结束；原来看不见的每一拍都记成「看到」，会结束在 16000")
    XCTAssertNil(ended.vanishedNotional)
  }

  /// 覆盖随增量扩大：远墙那一档被推到（量变了）就看得见、照常续；再被推成 0 就知道没了，两拍确认判撤单。
  func testCoverageWidensAndThenTheWallIsCancelled() throws {
    var m = restoredFarWall(savedAtMs: 5_000)
    _ = m.evaluate(nowMs: 6_000)
    _ = m.evaluate(nowMs: 6_500)
    push(&m, bids: [level(1_000, 7_000)], nowMs: 7_000)
    _ = m.evaluate(nowMs: 7_000)
    XCTAssertEqual(m.orders.count, 1)
    XCTAssertEqual(m.orders[0].notional, 7 * million, accuracy: 1, "推到了：看得见，名义跟上")
    XCTAssertEqual(m.orders[0].firstSeenMs, 0, "同一条单续上")
    push(&m, bids: [level(1_000, 0)], nowMs: 7_200)
    _ = m.evaluate(nowMs: 7_500)
    _ = m.evaluate(nowMs: 8_000)
    let o = m.orders[0]
    XCTAssertEqual(o.status, .cancelled, "推成 0：知道没了")
    XCTAssertEqual(o.endMs, 7_500)
    XCTAssertEqual(try XCTUnwrap(o.vanishedNotional), 7 * million, accuracy: 1)
  }

  /// 看不见的那几拍不能攒成「连续两拍没了」：确认开始后变成看不见，确认作废。
  func testInvisibleTicksResetACancelConfirmation() throws {
    var m = restoredFarWall(savedAtMs: 5_000)
    push(&m, bids: [level(1_000, 6_000)], nowMs: 5_500)
    _ = m.evaluate(nowMs: 6_000)
    push(&m, bids: [level(1_000, 1_000)], nowMs: 6_200)  // 跌到 100 万（退出线 250 万以下）：开始确认
    _ = m.evaluate(nowMs: 6_500)
    XCTAssertTrue(m.orders[0].isLive)
    // 簿重连、新快照又只盖到盘口：这一档看不见了。
    _ = m.connectionOpened(venue.id)
    seq = 1
    _ = m.ingest(venue.id, .snapshot(BookSnapshot(
      lastUpdateID: 1, requestedLevels: 3, bids: [level(1_110, 1), level(1_109.5, 1), level(1_109, 1)],
      asks: [level(1_111, 1), level(1_111.5, 1), level(1_112, 1)])), nowMs: 6_800)
    for k in 0..<4 { _ = m.evaluate(nowMs: 7_000 + Int64(k) * 500) }
    XCTAssertTrue(m.orders[0].isLive, "看不见的几拍不算「没了」")
    // 又被推到、仍在退出线下：从头确认两拍。
    push(&m, bids: [level(1_000, 1_000)], nowMs: 9_000)
    _ = m.evaluate(nowMs: 9_000)
    XCTAssertTrue(m.orders[0].isLive, "确认从头算，第一拍不结束")
    _ = m.evaluate(nowMs: 9_500)
    XCTAssertEqual(m.orders[0].status, .cancelled)
    XCTAssertEqual(m.orders[0].endMs, 9_000)
  }

  /// OKX 窗口：墙被挤出 400 档窗口（推 0）不判撤单；回到窗口照常续；在窗口内真撤掉才判撤单。
  func testOKXWindowExitDoesNotCancelButARealCancelDoes() throws {
    var m = OrderFlowModel(symbol: "ETHUSDT", thresholds: thresholds)
    m.addVenue(venue)
    _ = m.connectionOpened(venue.id)
    _ = m.ingest(venue.id, .snapshot(BookSnapshot(
      lastUpdateID: 1, requestedLevels: 4, bids: [level(1_110, 1), level(1_050, 1), level(1_020, 1), level(1_000, 6_000)],
      asks: [level(1_111, 1), level(1_112, 1), level(1_113, 1), level(1_114, 1)], slidingWindow: true)), nowMs: 0)
    _ = m.evaluate(nowMs: 0)
    _ = m.evaluate(nowMs: 500)
    XCTAssertEqual(m.orders.count, 1)
    // 盘口新挂 1100：1000 被挤出窗口。
    push(&m, bids: [level(1_100, 1), level(1_000, 0)], nowMs: 600)
    for k in 0..<6 { _ = m.evaluate(nowMs: 1_000 + Int64(k) * 500) }
    XCTAssertTrue(m.orders[0].isLive, "被挤出窗口不是撤单")
    XCTAssertNil(m.orders[0].vanishedNotional)
    // 1100 撤了：1000 回到窗口，看得见。
    push(&m, bids: [level(1_100, 0), level(1_000, 6_500)], nowMs: 4_000)
    _ = m.evaluate(nowMs: 4_000)
    XCTAssertEqual(m.orders[0].notional, 6.5 * million, accuracy: 1)
    // 窗口内真撤掉：第 5 档（990）补进来。
    push(&m, bids: [level(1_000, 0), level(990, 1)], nowMs: 4_200)
    _ = m.evaluate(nowMs: 4_500)
    _ = m.evaluate(nowMs: 5_000)
    XCTAssertEqual(m.orders.count, 1)
    XCTAssertEqual(m.orders[0].status, .cancelled)
    XCTAssertEqual(m.orders[0].endMs, 4_500)
  }
}
