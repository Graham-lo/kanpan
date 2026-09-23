import XCTest
@testable import KanpanCore

// 主力订单流 · Core 四件的单测。
// 簿的 13 条逐条翻自 send-tradfi `crates/bit-orderbook-book/src/lib.rs` 的 tests 模块，
// 门槛的几条翻自 `crates/bit-orderbook-signal-policy/src/candidate.rs` 的 tests 模块。

private func level(_ price: Double, _ quantity: Double) -> BookLevel { BookLevel(price: price, quantity: quantity) }

private func snapshot(_ last: Int64, connection: Int = 0) -> BookSnapshot {
  BookSnapshot(lastUpdateID: last, requestedLevels: 1_000,
               bids: [level(99, 10), level(98, 5)], asks: [level(101, 12), level(102, 4)],
               connection: connection)
}

private func delta(_ first: Int64, _ final: Int64, _ previous: Int64?, connection: Int = 0) -> BookDelta {
  BookDelta(firstUpdateID: first, finalUpdateID: final, previousFinalUpdateID: previous,
            bids: [level(99, 11)], asks: [], eventTimeMs: 1, connection: connection)
}

final class OrderFlowBookTests: XCTestCase {
  func testBookEpochIsDeterministicForTheSameReconstructionSequence() {
    var first = LocalBook(sequenceModel: .rangeOverlap, connection: 7)
    var second = LocalBook(sequenceModel: .rangeOverlap, connection: 7)
    let initial = first.epoch
    XCTAssertEqual(initial, second.epoch)
    first.beginResync(connection: 7)
    second.beginResync(connection: 7)
    XCTAssertEqual(first.epoch, second.epoch)
    XCTAssertNotEqual(first.epoch, initial)
    first.beginResync(connection: 8)
    XCTAssertNotEqual(first.epoch, second.epoch)
  }

  func testSpotBootstrapRequiresLPlusOneOverlap() throws {
    var book = LocalBook(sequenceModel: .rangeOverlap)
    let outcome = try book.bootstrap(snapshot(100), buffered: [delta(99, 101, nil)])
    XCTAssertEqual(outcome, .ready(appliedEvents: 1))
    XCTAssertEqual(book.quality, .ready)
    XCTAssertEqual(book.lastUpdateID, 101)
  }

  func testStaleSpotSnapshotNeverBecomesReady() {
    var book = LocalBook(sequenceModel: .rangeOverlap)
    XCTAssertThrowsError(try book.bootstrap(snapshot(100), buffered: [delta(102, 103, nil)])) { error in
      guard case BookError.snapshotDoesNotOverlap = error else { return XCTFail("\(error)") }
    }
    XCTAssertEqual(book.quality, .gapped)
    XCTAssertNil(book.lastUpdateID)
  }

  func testDuplicateSpotEventIsIdempotent() throws {
    var book = LocalBook(sequenceModel: .rangeOverlap)
    let first = delta(100, 101, nil)
    try book.bootstrap(snapshot(100), buffered: [first])
    let before = book
    XCTAssertEqual(try book.apply(first), .duplicateIgnored)
    XCTAssertTrue(before.sameState(as: book))
  }

  func testSpotGapClearsBookAndChangesBookEpoch() throws {
    var book = LocalBook(sequenceModel: .rangeOverlap)
    try book.bootstrap(snapshot(100), buffered: [delta(100, 101, nil)])
    let old = book.epoch
    XCTAssertThrowsError(try book.apply(delta(103, 104, nil))) { error in
      guard case BookError.sequenceGap = error else { return XCTFail("\(error)") }
    }
    XCTAssertEqual(book.quality, .gapped)
    XCTAssertNotEqual(book.epoch, old)
    XCTAssertTrue(book.view(levels: 10).bids.isEmpty)
  }

  func testFuturesLiveEventRequiresPreviousFinalUpdateID() throws {
    var book = LocalBook(sequenceModel: .previousFinalOverlap)
    try book.bootstrap(snapshot(100), buffered: [delta(99, 101, 98)])
    XCTAssertThrowsError(try book.apply(delta(102, 103, 100))) { error in
      guard case BookError.sequenceGap = error else { return XCTFail("\(error)") }
    }
    XCTAssertEqual(book.quality, .gapped)
  }

  func testLatePacketFromOldConnectionCannotMutateNewEpoch() {
    var book = LocalBook(sequenceModel: .rangeOverlap, connection: 1)
    book.beginResync(connection: 2)
    let before = book
    XCTAssertThrowsError(try book.apply(delta(100, 101, nil, connection: 1))) { error in
      guard case BookError.notReady = error else { return XCTFail("\(error)") }
    }
    XCTAssertTrue(before.sameState(as: book))
  }

  func testDistanceViewIsNotSilentlyTruncatedToTopTwoHundredLevels() throws {
    var deep = snapshot(100)
    deep.bids = (0..<300).map { level((99_990 - Double($0)) / 100, 1) }
    deep.asks = (0..<300).map { level((100_010 + Double($0)) / 100, 1) }
    var book = LocalBook(sequenceModel: .rangeOverlap)
    try book.bootstrap(deep, buffered: [delta(100, 101, nil)])
    let view = try book.viewWithinDistance(100)
    XCTAssertGreaterThan(view.bids.count, 200)
    XCTAssertGreaterThan(view.asks.count, 200)
    XCTAssertEqual(book.coverage.state, .fullSnapshot)
  }

  func testSnapshotAtTheRequestedLimitIsExplicitlyPartial() throws {
    var limited = snapshot(100)
    limited.requestedLevels = 2
    var book = LocalBook(sequenceModel: .previousFinalOverlap)
    try book.bootstrap(limited, buffered: [delta(99, 101, 99)])
    XCTAssertEqual(book.coverage.state, .snapshotLimited)
    XCTAssertEqual(book.coverage.bidFloor, 98)
    XCTAssertEqual(book.coverage.askCeiling, 102)
  }

  func testOKXPreviousSequenceMustEqualSnapshotAndThenLocalSequence() throws {
    var book = LocalBook(sequenceModel: .previousFinalExact)
    try book.bootstrap(snapshot(100), buffered: [delta(101, 101, 100)])
    XCTAssertEqual(try book.apply(delta(102, 102, 101)), .applied)
    XCTAssertThrowsError(try book.apply(delta(104, 104, 103))) { error in
      guard case BookError.sequenceGap = error else { return XCTFail("\(error)") }
    }
  }

  func testCoinbaseSequenceIsStrictlyIncrementing() throws {
    var book = LocalBook(sequenceModel: .strictIncrementing)
    try book.bootstrap(snapshot(10), buffered: [delta(11, 11, nil)])
    XCTAssertEqual(try book.apply(delta(12, 12, nil)), .applied)
    XCTAssertThrowsError(try book.apply(delta(14, 14, nil))) { error in
      guard case BookError.sequenceGap = error else { return XCTFail("\(error)") }
    }
  }

  func testAuthoritativeStreamSnapshotRotatesBookEpochAndReplacesAllLevels() throws {
    var book = LocalBook(sequenceModel: .strictIncrementing)
    try book.bootstrap(snapshot(10), buffered: [delta(11, 11, nil)])
    let old = book.epoch
    var replacement = snapshot(12)
    replacement.bids = [level(97, 20)]
    replacement.asks = [level(103, 30)]
    try book.replaceFromStreamSnapshot(replacement)
    XCTAssertEqual(book.quality, .ready)
    XCTAssertEqual(book.connection, 0)
    XCTAssertNotEqual(book.epoch, old)
    XCTAssertEqual(book.lastUpdateID, 12)
    XCTAssertEqual(book.quantity(at: 99, side: .bid), 0)
    XCTAssertEqual(book.quantity(at: 97, side: .bid), 20)
    XCTAssertEqual(book.quantity(at: 103, side: .ask), 30)
  }

  func testRegressedStreamSnapshotFailsClosed() throws {
    var book = LocalBook(sequenceModel: .strictIncrementing)
    try book.bootstrap(snapshot(10), buffered: [delta(11, 11, nil)])
    XCTAssertThrowsError(try book.replaceFromStreamSnapshot(snapshot(9))) { error in
      guard case BookError.regressedStreamSnapshot = error else { return XCTFail("\(error)") }
    }
    XCTAssertEqual(book.quality, .gapped)
    XCTAssertTrue(book.view(levels: 10).bids.isEmpty)
  }

  // 看盘补的：数量 0 删价位、最优价随删除重算、交叉按失败处理。

  func testZeroQuantityRemovesLevelAndBestPriceIsRecomputed() throws {
    var book = LocalBook(sequenceModel: .strictIncrementing)
    try book.replaceFromStreamSnapshot(snapshot(10))
    XCTAssertEqual(book.bestBid(), 99)
    try book.apply(BookDelta(firstUpdateID: 11, finalUpdateID: 11, previousFinalUpdateID: nil, bids: [level(99, 0)]))
    XCTAssertEqual(book.bestBid(), 98)
    XCTAssertEqual(book.quantity(at: 99, side: .bid), 0)
  }

  func testCrossedBookFailsSequence() throws {
    var book = LocalBook(sequenceModel: .strictIncrementing)
    try book.replaceFromStreamSnapshot(snapshot(10))
    XCTAssertThrowsError(try book.apply(BookDelta(firstUpdateID: 11, finalUpdateID: 11, previousFinalUpdateID: nil,
                                                  bids: [level(101.5, 1)]))) { error in
      guard case BookError.crossed = error else { return XCTFail("\(error)") }
    }
    XCTAssertEqual(book.quality, .gapped)
  }
}

final class OrderFlowFilterTests: XCTestCase {
  private func bucket(_ price: Double, _ notional: Double, side: BookSide = .bid) -> BucketNotional {
    BucketNotional(side: side, index: Int64(price), low: price, width: 1, notional: notional)
  }

  private func neighbourhood(_ subject: BucketNotional, each: Double = 200_000) -> [BucketNotional] {
    [subject] + (1...12).map { bucket(1_600 - Double($0), each) }
  }

  func testAWallThatClearsEveryRelativeTestIsAdmitted() {
    let subject = bucket(1_600, 9_500_000)
    let verdict = BigOrderFilter.evaluate(subject, sameSide: neighbourhood(subject), reference: 1_600, floor: 2_000_000)
    guard case .admitted(let evidence) = verdict else { return XCTFail("\(verdict)") }
    XCTAssertEqual(evidence.localMedian, 200_000)
    XCTAssertGreaterThan(evidence.localMultiple, 5)
    XCTAssertEqual(evidence.neighbours, 12)
  }

  func testBelowTheAbsoluteFloorIsRejectedFirst() {
    // 原测试 a_single_venue_wall_needs_the_stricter_local_multiple：1.3M 先撞下限。
    let subject = bucket(1_600, 1_300_000)
    XCTAssertEqual(BigOrderFilter.evaluate(subject, sameSide: neighbourhood(subject), reference: 1_600, floor: 2_000_000),
                   .rejected(.belowFloor))
  }

  func testEachRejectionNamesExactlyOneCauseInEvaluationOrder() {
    let thin = bucket(1_600, 1_000)
    XCTAssertEqual(BigOrderFilter.evaluate(thin, sameSide: neighbourhood(thin), reference: 1_600, floor: 2_000_000),
                   .rejected(.belowFloor))
    let lonely = bucket(1_600, 9_500_000)
    XCTAssertEqual(BigOrderFilter.evaluate(lonely, sameSide: [lonely], reference: 1_600, floor: 2_000_000),
                   .rejected(.insufficientNeighbourhood))
    let flatSubject = bucket(1_600, 9_500_000)
    XCTAssertEqual(BigOrderFilter.evaluate(flatSubject, sameSide: neighbourhood(flatSubject, each: 9_000_000),
                                           reference: 1_600, floor: 2_000_000),
                   .rejected(.belowLocalMultiple))
    XCTAssertEqual(BigOrderFilter.evaluate(thin, sameSide: neighbourhood(thin), reference: 1_600, floor: nil),
                   .rejected(.noFloor))
  }

  func testDepthShareBelowTwentyPercentIsRejected() {
    // 局部中位数 200k、倍数 5.5×，但 100 bps 内有一大块别的挂单把占比压到 20% 以下。
    let subject = bucket(1_600, 1_100_000)
    var side = neighbourhood(subject)
    side.append(bucket(1_590.5, 8_000_000))
    let verdict = BigOrderFilter.evaluate(subject, sameSide: side, reference: 1_600, floor: 500_000)
    XCTAssertEqual(verdict, .rejected(.belowDepthShare))
  }

  func testNeighboursAreCountedAroundTheReferenceNotTheBucket() {
    // 邻居半径以参考价为圆心：离参考价 200 bps 外的桶不算邻居。
    let subject = bucket(1_600, 9_500_000)
    let far = [subject] + (1...12).map { bucket(1_600 + 40 + Double($0), 200_000) }
    XCTAssertEqual(BigOrderFilter.evaluate(subject, sameSide: far, reference: 1_600, floor: 1),
                   .rejected(.insufficientNeighbourhood))
  }

  func testTheLocalMedianIsATabulatedSampleNotAnAverage() {
    XCTAssertEqual(BigOrderFilter.median([1, 2, 3, 100]), 2)
    XCTAssertEqual(BigOrderFilter.median([]), 0)
  }

  func testHysteresisEntersAtFiveHoldsAtThreePointFiveAndDropsBelow() {
    var filter = BigOrderFilter()
    func frame(_ notional: Double, at t: Int64) -> [BigOrder] {
      let subject = bucket(1_600, notional)
      return filter.update(buckets: neighbourhood(subject), reference: 1_600, bidFloor: 1, askFloor: 1, nowMs: t)
    }
    XCTAssertTrue(frame(800_000, at: 1).isEmpty, "4× 还没进")
    XCTAssertEqual(frame(1_200_000, at: 2).map(\.firstSeenMs), [2], "6× 进")
    XCTAssertEqual(frame(800_000, at: 3).map(\.firstSeenMs), [2], "4× 维持，首次出现时间不变")
    XCTAssertTrue(frame(600_000, at: 4).isEmpty, "3× 掉出去就立刻消失")
    XCTAssertTrue(frame(800_000, at: 5).isEmpty, "掉出去之后要重新过 5× 才回来")
  }

  func testTradesHittingATrackedWallAccumulateFilledNotional() throws {
    var filter = BigOrderFilter()
    let scheme = try XCTUnwrap(BucketScheme(referenceClose: 1_250, tick: 1, bps: 8))  // 1 tick
    let subject = bucket(1_600, 1_200_000)
    _ = filter.update(buckets: neighbourhood(subject), reference: 1_600, bidFloor: 1, askFloor: 1, nowMs: 1)
    filter.recordTrade(OrderFlowTrade(price: 1_600.4, quantity: 150, hitSide: .bid, timeMs: 2), scheme: scheme)
    filter.recordTrade(OrderFlowTrade(price: 1_600.4, quantity: 999, hitSide: .ask, timeMs: 2), scheme: scheme)
    let orders = filter.update(buckets: neighbourhood(subject), reference: 1_600, bidFloor: 1, askFloor: 1, nowMs: 3)
    XCTAssertEqual(orders.first?.filledNotional ?? 0, 1_600.4 * 150, accuracy: 1e-6)
    XCTAssertEqual(orders.first?.fillRatio ?? 0, 1_600.4 * 150 / 1_200_000, accuracy: 1e-9)
  }
}

final class OrderFlowSchemeTests: XCTestCase {
  func testWidthIsCeilOfEightBpsInTicks() throws {
    let s = try XCTUnwrap(BucketScheme(referenceClose: 84_000, tick: 0.1))
    XCTAssertEqual(s.widthTicks, 672)
    XCTAssertEqual(s.width, 67.2, accuracy: 1e-9)
  }

  func testExactMultipleDoesNotRoundUpAnExtraTick() throws {
    XCTAssertEqual(try XCTUnwrap(BucketScheme(referenceClose: 100_000, tick: 0.1)).widthTicks, 800)
    XCTAssertEqual(try XCTUnwrap(BucketScheme(referenceClose: 1, tick: 0.0001)).widthTicks, 8)
  }

  func testAtLeastOneTickAndInvalidInputsAreRejected() {
    XCTAssertEqual(BucketScheme(referenceClose: 0.002, tick: 0.0001)?.widthTicks, 1)
    XCTAssertNil(BucketScheme(referenceClose: 0, tick: 0.1))
    XCTAssertNil(BucketScheme(referenceClose: 100, tick: 0))
    XCTAssertNil(BucketScheme(referenceClose: .nan, tick: 0.1))
  }

  func testPricesFloorIntoBuckets() throws {
    let s = try XCTUnwrap(BucketScheme(referenceClose: 84_000, tick: 0.1))
    let i = s.index(of: 84_261.3)
    XCTAssertEqual(i, 1_253)
    XCTAssertEqual(s.low(of: i), 84_201.6, accuracy: 1e-6)
    XCTAssertEqual(s.index(of: 84_201.6), i)
    XCTAssertEqual(s.index(of: 84_201.5), i - 1)
  }

  func testReferenceDayIsThePreviousUTCMidnight() {
    let t: Int64 = 1_790_000_000_000
    let day: Int64 = 86_400_000
    XCTAssertEqual(BucketScheme.referenceDay(nowMs: t), t / day * day - day)
  }
}

final class OrderFlowCalibrationTests: XCTestCase {
  func testNearestRankQuantile() {
    XCTAssertEqual(FloorCalibration.value(atQuantile: 0.9, of: (1...10).map(Double.init)), 9)
    XCTAssertEqual(FloorCalibration.value(atQuantile: 0.9, of: [5]), 5)
    XCTAssertNil(FloorCalibration.value(atQuantile: 0.9, of: []))
    XCTAssertEqual(FloorCalibration.frameFloor([0, -1, 3, 1, 2]), 3)
  }

  func testFloorNeedsTwoThousandSamplesInsideSevenDays() {
    var c = FloorCalibration()
    for i in 0..<1_999 { c.record(Double(i + 1), side: .bid, atMs: Int64(i) * 1_000) }
    XCTAssertNil(c.floor(.bid, nowMs: 2_000_000))
    c.record(2_000, side: .bid, atMs: 1_999_000)
    XCTAssertEqual(c.floor(.bid, nowMs: 2_000_000), 1_800)
    XCTAssertNil(c.floor(.ask, nowMs: 2_000_000))
    XCTAssertNil(c.floor(.bid, nowMs: 1_999_000 + FloorCalibration.windowMs + 2_000), "7 天前的样本不算")
  }

  func testCapacityKeepsTheNewestTwoThousand() {
    var c = FloorCalibration()
    for i in 0..<2_500 { c.record(Double(i + 1), side: .ask, atMs: Int64(i) * 1_000) }
    XCTAssertEqual(c.asks.count, 2_000)
    XCTAssertEqual(c.asks.first?.value, 501)
  }

  func testEncodingRoundTripsAndIsEightBytesPerSample() throws {
    var c = FloorCalibration()
    for i in 0..<2_000 { c.record(Double(i) * 1_000 + 0.5, side: .bid, atMs: 1_790_000_000_000 + Int64(i) * 1_000) }
    c.record(12_345, side: .ask, atMs: 1_790_000_500_000)
    let data = c.encoded()
    XCTAssertEqual(data.count, 20 + 2_001 * 8)
    let back = try XCTUnwrap(FloorCalibration(encoded: data))
    XCTAssertEqual(back.bids.count, 2_000)
    XCTAssertEqual(back.bids.last?.value ?? 0, 1_999_000.5, accuracy: 0.5)
    XCTAssertEqual(back.asks.first?.value, 12_345)
    XCTAssertEqual(back.asks.first?.timeMs, 1_790_000_500_000)
    XCTAssertNil(FloorCalibration(encoded: Data([1, 2, 3])))
  }
}

final class OrderFlowModelTests: XCTestCase {
  /// 买侧：1600 往下每 1 美元一档 1 个币；1590 那一档另挂一堵 12 000 个币的墙。卖侧对称但没有墙。
  private func deepSnapshot(last: Int64, requested: Int = 1_000) -> BookSnapshot {
    var bids = (1...40).map { level(1_600 - Double($0), 150) }
    bids[9] = level(1_590, 12_000)
    let asks = (1...40).map { level(1_600 + Double($0), 150) }
    return BookSnapshot(lastUpdateID: last, requestedLevels: requested, bids: bids, asks: asks)
  }

  private var scheme: BucketScheme { BucketScheme(referenceClose: 1_250, tick: 1)! }  // 1 美元一桶

  func testRestSnapshotBootstrapsAgainstBufferedDeltasAndFindsTheWall() {
    var model = OrderFlowModel(symbol: "ETHUSDT", sequenceModel: .previousFinalOverlap, snapshotInBand: false, scheme: scheme)
    XCTAssertEqual(model.connectionOpened(), .fetchSnapshot)
    XCTAssertEqual(model.ingest(.delta(BookDelta(firstUpdateID: 95, finalUpdateID: 101, previousFinalUpdateID: 94)), nowMs: 0), .none)
    XCTAssertEqual(model.evaluate(nowMs: 0).phase, .loading)
    XCTAssertEqual(model.applySnapshot(deepSnapshot(last: 100), nowMs: 10), .none)
    XCTAssertTrue(model.isReady)
    let frame = model.evaluate(nowMs: 20)
    XCTAssertEqual(frame.phase, .ready)
    XCTAssertEqual(frame.orders.map(\.low), [1_590])
    XCTAssertEqual(frame.orders.first?.side, .bid)
    XCTAssertEqual(frame.orders.first?.firstSeenMs, 20)
  }

  func testGapOnTheRestPathAsksForANewSnapshot() {
    var model = OrderFlowModel(symbol: "ETHUSDT", sequenceModel: .previousFinalOverlap, snapshotInBand: false, scheme: scheme)
    _ = model.connectionOpened()
    _ = model.ingest(.delta(BookDelta(firstUpdateID: 95, finalUpdateID: 101, previousFinalUpdateID: 94)), nowMs: 0)
    _ = model.applySnapshot(deepSnapshot(last: 100), nowMs: 0)
    XCTAssertEqual(model.ingest(.delta(BookDelta(firstUpdateID: 105, finalUpdateID: 106, previousFinalUpdateID: 104)), nowMs: 1),
                   .fetchSnapshot)
    XCTAssertEqual(model.evaluate(nowMs: 2).phase, .loading)
    // 新快照接上缓冲里那条 105–106。
    XCTAssertEqual(model.applySnapshot(deepSnapshot(last: 105), nowMs: 3), .none)
    XCTAssertTrue(model.isReady)
  }

  func testInBandSnapshotIsReadyImmediatelyAndGapAsksToResubscribe() {
    var model = OrderFlowModel(symbol: "BTC-USD", sequenceModel: .strictIncrementing, snapshotInBand: true, scheme: scheme)
    XCTAssertEqual(model.connectionOpened(), .none)
    XCTAssertEqual(model.ingest(.delta(BookDelta(firstUpdateID: 1, finalUpdateID: 1, previousFinalUpdateID: nil)), nowMs: 0), .none)
    XCTAssertEqual(model.ingest(.snapshot(deepSnapshot(last: 2)), nowMs: 0), .none)
    XCTAssertTrue(model.isReady)
    XCTAssertEqual(model.ingest(.delta(BookDelta(firstUpdateID: 3, finalUpdateID: 3, previousFinalUpdateID: nil)), nowMs: 1), .none)
    XCTAssertEqual(model.ingest(.delta(BookDelta(firstUpdateID: 5, finalUpdateID: 5, previousFinalUpdateID: nil)), nowMs: 2), .resubscribe)
    XCTAssertEqual(model.ingest(.reset, nowMs: 3), .resubscribe)
  }

  func testLimitedSnapshotOnlyShowsCoveredBucketsDuringWarmUp() {
    var model = OrderFlowModel(symbol: "BTCUSDT", sequenceModel: .strictIncrementing, snapshotInBand: true, scheme: scheme)
    _ = model.connectionOpened()
    var snap = deepSnapshot(last: 1, requested: 40)
    snap.bids = Array(snap.bids.prefix(20))  // 快照只覆盖到 1580
    _ = model.ingest(.snapshot(snap), nowMs: 0)
    // 增量补进来 1575 一堵墙（在快照覆盖以外），以及更深处的普通价位。
    let deeper = (21...40).map { level(1_600 - Double($0), $0 == 25 ? 12_000 : 150) }
    _ = model.ingest(.delta(BookDelta(firstUpdateID: 2, finalUpdateID: 2, previousFinalUpdateID: nil, bids: deeper)), nowMs: 1)
    XCTAssertEqual(model.evaluate(nowMs: 1_000).orders.map(\.low), [1_590], "热身期只看快照覆盖以内")
    XCTAssertEqual(model.evaluate(nowMs: OrderFlowModel.warmUpMs + 1).orders.map(\.low).sorted(), [1_575, 1_590])
  }

  func testCalibrationSamplesOncePerSecondOnlyAfterWarmUp() {
    var model = OrderFlowModel(symbol: "BTC-USD", sequenceModel: .strictIncrementing, snapshotInBand: true, scheme: scheme)
    _ = model.connectionOpened()
    _ = model.ingest(.snapshot(deepSnapshot(last: 1)), nowMs: 0)  // 全量快照：不用热身
    _ = model.evaluate(nowMs: 0)
    _ = model.evaluate(nowMs: 500)
    _ = model.evaluate(nowMs: 1_000)
    XCTAssertEqual(model.calibration.bids.count, 2)
    XCTAssertTrue(model.calibrationDirty)
    model.markCalibrationSaved()
    XCTAssertFalse(model.calibrationDirty)
  }

  func testSchemeChangeClearsTracking() {
    var model = OrderFlowModel(symbol: "BTC-USD", sequenceModel: .strictIncrementing, snapshotInBand: true, scheme: scheme)
    _ = model.connectionOpened()
    _ = model.ingest(.snapshot(deepSnapshot(last: 1)), nowMs: 0)
    XCTAssertEqual(model.evaluate(nowMs: 0).orders.first?.firstSeenMs, 0)
    model.setScheme(scheme)
    XCTAssertEqual(model.evaluate(nowMs: 5).orders.first?.firstSeenMs, 0, "桶宽没变不清")
    model.setScheme(BucketScheme(referenceClose: 2_500, tick: 1))
    XCTAssertEqual(model.evaluate(nowMs: 9).orders.first?.firstSeenMs, 9)
  }
}
