import XCTest
@testable import KanpanCore

// 主力订单流 · Core 的单测。
// 簿的 13 条逐条翻自 send-tradfi `crates/bit-orderbook-book/src/lib.rs` 的 tests 模块；
// 逐单模型（照 CoinAnk「主力大额挂单」）的几条是新写的：出现 / 消失确认、成交归因、已成交 / 已撤销、
// 断簿过期、保留上限、改门槛 / 步长、落盘读回。

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

final class OrderFlowSchemeTests: XCTestCase {
  func testFixedDollarStepFloorsPriceIntoBuckets() {
    let btc = BucketScheme(step: 100)!
    XCTAssertEqual(btc.index(of: 78_450), 784)
    XCTAssertEqual(btc.index(of: 78_400), 784)
    XCTAssertEqual(btc.index(of: 78_399.9), 783)
    XCTAssertEqual(btc.low(of: 784), 78_400)
    XCTAssertEqual(btc.width, 100)
  }

  /// sol_uses_tenth_dollar_price_buckets：0.1 美元一桶，150.3 / 0.1 在浮点里是 1502.999…，要吸回 1503。
  func testTenthDollarStepSnapsFloatingNoise() {
    let sol = BucketScheme(step: 0.1)!
    XCTAssertEqual(sol.index(of: 150.3), 1_503)
    XCTAssertEqual(sol.index(of: 150.39), 1_503)
    XCTAssertEqual(sol.index(of: 150.4), 1_504)
    XCTAssertEqual(sol.low(of: 1_503), 150.3, accuracy: 1e-9)
  }

  func testRejectsNonPositiveStep() {
    XCTAssertNil(BucketScheme(step: 0))
    XCTAssertNil(BucketScheme(step: -.infinity))
  }

  /// 表里没有的品种：收盘 × 0.1% 最接近的 1 / 2 / 5 × 10ⁿ，不小于最小价格步长。
  func testDerivedStepPicksNearestOneTwoFive() {
    XCTAssertEqual(BucketScheme.derivedStep(referenceClose: 78_000, tick: 0.1)!, 100, accuracy: 1e-9)
    XCTAssertEqual(BucketScheme.derivedStep(referenceClose: 4_000, tick: 0.01)!, 5, accuracy: 1e-9)
    XCTAssertEqual(BucketScheme.derivedStep(referenceClose: 250, tick: 0.01)!, 0.2, accuracy: 1e-9)
    XCTAssertEqual(BucketScheme.derivedStep(referenceClose: 1.2, tick: 0.0001)!, 0.001, accuracy: 1e-12)
    XCTAssertEqual(BucketScheme.derivedStep(referenceClose: 0.05, tick: 0.0001)!, 0.0001, accuracy: 1e-12, "不小于 tick")
    XCTAssertNil(BucketScheme.derivedStep(referenceClose: 0, tick: 1))
  }

  func testReferenceDayIsPreviousUtcMidnight() {
    let day: Int64 = 86_400_000
    XCTAssertEqual(BucketScheme.referenceDay(nowMs: 20_000 * day + 5), 19_999 * day)
  }
}

// MARK: - 默认表、覆盖、开关

final class OrderFlowDefaultsTests: XCTestCase {
  func testMajorsUseTheFixedTable() {
    let btc = OrderFlowDefaults.thresholds(base: "BTC", asset: .crypto, turnover24h: 1)
    XCTAssertEqual(btc, OrderFlowThresholds(spot: 1_000_000, usdtPerp: 5_000_000, coinPerp: 5_000_000,
                                            delivery: 5_000_000, step: 100))
    let eth = OrderFlowDefaults.thresholds(base: "eth", asset: .crypto, turnover24h: nil)
    XCTAssertEqual(eth.step, 1)
    XCTAssertEqual(eth.spot, 1_000_000)
    let sol = OrderFlowDefaults.thresholds(base: "SOL", asset: .crypto, turnover24h: nil)
    XCTAssertEqual(sol, OrderFlowThresholds(spot: 750_000, usdtPerp: 2_500_000, coinPerp: 2_500_000,
                                            delivery: 2_500_000, step: 0.1))
  }

  /// 美股、金银只订 U 本位永续，200 万；有表的步长照表，没表的等前一日收盘。
  func testNonCryptoOnlySubscribesTheUsdtPerpetual() {
    let mu = OrderFlowDefaults.thresholds(base: "MU", asset: .equity, turnover24h: 9e12)
    XCTAssertEqual(mu, OrderFlowThresholds(usdtPerp: 2_000_000, step: 1))
    XCTAssertEqual(mu.products, [.usdtPerp])
    XCTAssertEqual(OrderFlowDefaults.thresholds(base: "SKHY", asset: .equity, turnover24h: nil).step, 0.1)
    XCTAssertEqual(OrderFlowDefaults.thresholds(base: "XAU", asset: .preciousMetal, turnover24h: nil).step, 1)
    XCTAssertEqual(OrderFlowDefaults.thresholds(base: "XAG", asset: .preciousMetal, turnover24h: nil).step, 0.1)
    let other = OrderFlowDefaults.thresholds(base: "AAPL", asset: .equity, turnover24h: nil)
    XCTAssertEqual(other, OrderFlowThresholds(usdtPerp: 2_000_000, step: nil))
  }

  /// 其他币按 24h 成交额分六档；币本位、交割取永续那个数；不知道成交额走第三档。
  func testCoinsAreTieredBy24hTurnover() {
    func t(_ turnover: Double?) -> OrderFlowThresholds {
      OrderFlowDefaults.thresholds(base: "DOGE", asset: .crypto, turnover24h: turnover)
    }
    XCTAssertEqual(t(12_000_000_000).usdtPerp, 5_000_000)
    XCTAssertEqual(t(10_000_000_000).spot, 1_000_000)
    XCTAssertEqual(t(9_999_999_999).usdtPerp, 2_500_000)
    XCTAssertEqual(t(2_000_000_000).spot, 750_000)
    XCTAssertEqual(t(600_000_000).usdtPerp, 1_000_000)
    XCTAssertEqual(t(600_000_000).spot, 300_000)
    XCTAssertEqual(t(100_000_000).usdtPerp, 500_000)
    XCTAssertEqual(t(100_000_000).spot, 150_000)
    XCTAssertEqual(t(20_000_000).usdtPerp, 200_000)
    XCTAssertEqual(t(20_000_000).spot, 60_000)
    XCTAssertEqual(t(19_999_999).usdtPerp, 100_000)
    XCTAssertEqual(t(0).spot, 30_000)
    XCTAssertEqual(t(nil), t(600_000_000), "不知道成交额走第三档")
    XCTAssertEqual(t(.nan), t(nil))
    XCTAssertEqual(t(12_000_000_000).coinPerp, 5_000_000)
    XCTAssertEqual(t(12_000_000_000).delivery, 5_000_000)
    XCTAssertNil(t(12_000_000_000).step, "没表的步长等前一日收盘")
  }

  func testOverrideReplacesOnlyWhatTheUserChanged() {
    let btc = OrderFlowDefaults.thresholds(base: "BTC", asset: .crypto, turnover24h: nil)
    let mine = btc.applying(OrderFlowOverride(spot: 2_000_000, step: 50))
    XCTAssertEqual(mine, OrderFlowThresholds(spot: 2_000_000, usdtPerp: 5_000_000, coinPerp: 5_000_000,
                                             delivery: 5_000_000, step: 50))
    XCTAssertEqual(btc.applying(nil), btc)
    // 非币不能凭空多出一种产品。
    let mu = OrderFlowDefaults.thresholds(base: "MU", asset: .equity, turnover24h: nil)
    XCTAssertEqual(mu.applying(OrderFlowOverride(spot: 1_000_000, usdtPerp: 3_000_000)),
                   OrderFlowThresholds(usdtPerp: 3_000_000, step: 1))
    // 越界、非数的项当没改。
    XCTAssertEqual(btc.applying(OrderFlowOverride(spot: 10, usdtPerp: .nan, step: -1)), btc)
    XCTAssertTrue(OrderFlowOverride(spot: 5).isEmpty)
    XCTAssertFalse(OrderFlowOverride(delivery: 8_000_000).isEmpty)
  }

  func testOverrideAndDisplayRoundTripAsJSON() throws {
    let override = OrderFlowOverride(spot: 1_500_000, coinPerp: 4_000_000, step: 25)
    let data = try JSONEncoder().encode(override)
    XCTAssertEqual(try JSONDecoder().decode(OrderFlowOverride.self, from: data), override)
    let display = OrderFlowDisplay(spot: false, cancelled: false)
    XCTAssertEqual(try JSONDecoder().decode(OrderFlowDisplay.self, from: JSONEncoder().encode(display)), display)
  }

  func testDisplayTogglesFilterByProductAndStatus() {
    func order(_ product: OrderFlowProduct, _ side: BookSide, _ status: BigOrder.Status) -> BigOrder {
      BigOrder(venueID: "v", exchange: "币安", product: product, side: side, bucket: 1, price: 1, firstSeenMs: 0,
               status: status, initialNotional: 1, notional: 1, threshold: 1)
    }
    let all = OrderFlowDisplay.all
    XCTAssertTrue(all.shows(order(.spot, .bid, .cancelled)))
    let noSpot = OrderFlowDisplay(spot: false)
    XCTAssertFalse(noSpot.shows(order(.spot, .ask, .live)))
    XCTAssertTrue(noSpot.shows(order(.coinPerp, .ask, .live)))
    let noContract = OrderFlowDisplay(contract: false)
    XCTAssertFalse(noContract.shows(order(.delivery, .bid, .live)))
    XCTAssertTrue(noContract.shows(order(.spot, .bid, .live)))
    let noFilled = OrderFlowDisplay(filled: false)
    XCTAssertFalse(noFilled.shows(order(.usdtPerp, .bid, .filled)))
    XCTAssertFalse(noFilled.shows(order(.spot, .ask, .filled)), "买卖两侧一起藏")
    XCTAssertTrue(noFilled.shows(order(.usdtPerp, .bid, .cancelled)))
    XCTAssertTrue(noFilled.shows(order(.usdtPerp, .bid, .live)), "挂着的单只看产品开关")
    let noCancelled = OrderFlowDisplay(cancelled: false)
    XCTAssertFalse(noCancelled.shows(order(.usdtPerp, .ask, .cancelled)))
    XCTAssertFalse(noCancelled.shows(order(.usdtPerp, .bid, .cancelled)))
    XCTAssertTrue(noCancelled.shows(order(.usdtPerp, .bid, .filled)))
    XCTAssertTrue(noCancelled.shows(order(.usdtPerp, .bid, .lost)), "失联结束不归撤销开关管")
  }

  func testNotionalConvertsLinearAndInverseToUsd() {
    XCTAssertEqual(OrderFlowNotional.linear(multiplier: 1).usd(price: 80_000, quantity: 2), 160_000)
    XCTAssertEqual(OrderFlowNotional.linear(multiplier: 0.01).usd(price: 80_000, quantity: 100), 80_000,
                   "OKX U 本位：张数 × ctVal 个币")
    XCTAssertEqual(OrderFlowNotional.inverse(contractUsd: 100).usd(price: 80_000, quantity: 50_000), 5_000_000,
                   "币本位：张数 × 面值，与价格无关")
    XCTAssertEqual(OrderFlowNotional.inverse(contractUsd: 10).usd(price: 3_000, quantity: 7), 70)
    XCTAssertEqual(OrderFlowNotional.linear(multiplier: 1).usd(price: .nan, quantity: 1), 0)
  }
}

// MARK: - 逐单模型

final class OrderFlowModelTests: XCTestCase {
  /// 步长 1 美元，永续门槛 500 万、现货 100 万。
  private let thresholds = OrderFlowThresholds(spot: 1_000_000, usdtPerp: 5_000_000, coinPerp: 5_000_000,
                                               delivery: 5_000_000, step: 1)

  private let binance = OrderFlowVenue(exchange: "binance", label: "币安", product: .usdtPerp, instrument: "ETHUSDT",
                                       notional: .linear(multiplier: 1), sequenceModel: .previousFinalOverlap,
                                       snapshotInBand: false)
  private let okx = OrderFlowVenue(exchange: "okx", label: "OKX", product: .usdtPerp, instrument: "ETH-USDT-SWAP",
                                   notional: .linear(multiplier: 1), sequenceModel: .previousFinalExact,
                                   snapshotInBand: true)
  private let coinbase = OrderFlowVenue(exchange: "coinbase", label: "Coinbase", product: .spot, instrument: "ETH-USD",
                                        notional: .linear(multiplier: 1), sequenceModel: .strictIncrementing,
                                        snapshotInBand: true)
  private let coinM = OrderFlowVenue(exchange: "binance", label: "币安", product: .coinPerp, instrument: "ETHUSD_PERP",
                                     notional: .inverse(contractUsd: 10), sequenceModel: .previousFinalOverlap,
                                     snapshotInBand: false)

  /// 买侧：1600 往下每 1 美元一档 150 个币（24 万）；1590 那一档另挂 `wall` 个币。卖侧对称但没有墙。
  private func deepSnapshot(last: Int64, requested: Int = 1_000, wall: Double = 12_000) -> BookSnapshot {
    var bids = (1...40).map { level(1_600 - Double($0), 150) }
    bids[9] = level(1_590, wall)
    let asks = (1...40).map { level(1_600 + Double($0), 150) }
    return BookSnapshot(lastUpdateID: last, requestedLevels: requested, bids: bids, asks: asks)
  }

  /// 流内快照即就绪的一本簿（OKX / Coinbase 那种）。
  private func inBand(_ venue: OrderFlowVenue, wall: Double = 12_000,
                      restored: OrderFlowJournal? = nil) -> OrderFlowModel {
    var model = OrderFlowModel(symbol: "ETHUSDT", thresholds: thresholds, restored: restored)
    model.addVenue(venue)
    _ = model.connectionOpened(venue.id)
    _ = model.ingest(venue.id, .snapshot(deepSnapshot(last: 1, wall: wall)), nowMs: 0)
    return model
  }

  /// OKX 那种：prevSeqId 链上改一档。
  private func set(_ model: inout OrderFlowModel, _ venue: OrderFlowVenue, seq: Int64, bid: BookLevel) {
    XCTAssertEqual(model.ingest(venue.id, .delta(BookDelta(firstUpdateID: seq, finalUpdateID: seq,
                                                           previousFinalUpdateID: seq - 1, bids: [bid], asks: [],
                                                           eventTimeMs: 0)), nowMs: 0), .none)
  }

  func testRestSnapshotBootstrapsAgainstBufferedDeltas() {
    var model = OrderFlowModel(symbol: "ETHUSDT", thresholds: thresholds)
    model.addVenue(binance)
    XCTAssertEqual(model.connectionOpened(binance.id), .fetchSnapshot)
    XCTAssertEqual(model.ingest(binance.id, .delta(BookDelta(firstUpdateID: 95, finalUpdateID: 101,
                                                             previousFinalUpdateID: 94)), nowMs: 0), .none)
    XCTAssertEqual(model.evaluate(nowMs: 0).phase, .loading)
    XCTAssertEqual(model.applySnapshot(binance.id, deepSnapshot(last: 100), nowMs: 10), .none)
    XCTAssertTrue(model.isReady(binance.id))
    XCTAssertEqual(model.evaluate(nowMs: 20).phase, .ready)
  }

  func testGapOnTheRestPathAsksForANewSnapshotAndInBandGapResubscribes() {
    var model = OrderFlowModel(symbol: "ETHUSDT", thresholds: thresholds)
    model.addVenue(binance)
    model.addVenue(coinbase)
    _ = model.connectionOpened(binance.id)
    _ = model.ingest(binance.id, .delta(BookDelta(firstUpdateID: 95, finalUpdateID: 101, previousFinalUpdateID: 94)), nowMs: 0)
    _ = model.applySnapshot(binance.id, deepSnapshot(last: 100), nowMs: 0)
    XCTAssertEqual(model.ingest(binance.id, .delta(BookDelta(firstUpdateID: 105, finalUpdateID: 106,
                                                             previousFinalUpdateID: 104)), nowMs: 1), .fetchSnapshot)
    XCTAssertFalse(model.isReady(binance.id))
    XCTAssertEqual(model.applySnapshot(binance.id, deepSnapshot(last: 105), nowMs: 3), .none)
    XCTAssertTrue(model.isReady(binance.id))

    XCTAssertEqual(model.connectionOpened(coinbase.id), .none)
    XCTAssertEqual(model.ingest(coinbase.id, .snapshot(deepSnapshot(last: 2)), nowMs: 0), .none)
    XCTAssertTrue(model.isReady(coinbase.id))
    XCTAssertEqual(model.ingest(coinbase.id, .delta(BookDelta(firstUpdateID: 3, finalUpdateID: 3, previousFinalUpdateID: nil)), nowMs: 1), .none)
    XCTAssertEqual(model.ingest(coinbase.id, .delta(BookDelta(firstUpdateID: 5, finalUpdateID: 5, previousFinalUpdateID: nil)), nowMs: 2), .resubscribe)
    XCTAssertEqual(model.ingest(coinbase.id, .reset, nowMs: 3), .resubscribe)
  }

  /// 出现要连续两拍、首尾隔 ≥ 300 ms；出现时刻记第一拍。
  func testAppearNeedsTwoSamplesThreeHundredMsApart() {
    var model = inBand(okx)
    XCTAssertEqual(model.evaluate(nowMs: 1_000).orders, [])
    XCTAssertEqual(model.evaluate(nowMs: 1_200).orders, [], "两拍了但只隔 200 ms")
    let frame = model.evaluate(nowMs: 1_300)
    XCTAssertEqual(frame.orders.count, 1)
    let order = frame.orders[0]
    XCTAssertEqual(order.side, .bid)
    XCTAssertEqual(order.price, 1_590)
    XCTAssertEqual(order.bucket, 1_590)
    XCTAssertEqual(order.firstSeenMs, 1_000)
    XCTAssertEqual(order.initialNotional, 1_590 * 12_000)
    XCTAssertEqual(order.status, .live)
    XCTAssertEqual(order.exchange, "OKX")
    XCTAssertEqual(order.product, .usdtPerp)
    XCTAssertEqual(order.threshold, 5_000_000)
    XCTAssertTrue(model.journalDirty)
  }

  /// 只过了一拍就掉下去的不算（连续两拍）。
  func testASingleSpikeNeverAppears() {
    var model = inBand(okx)
    _ = model.evaluate(nowMs: 0)
    set(&model, okx, seq: 2, bid: level(1_590, 150))
    XCTAssertEqual(model.evaluate(nowMs: 500).orders, [])
    set(&model, okx, seq: 3, bid: level(1_590, 12_000))
    XCTAssertEqual(model.evaluate(nowMs: 1_000).orders, [])
    XCTAssertEqual(model.evaluate(nowMs: 1_500).orders.first?.firstSeenMs, 1_000, "重新从第一拍算起")
  }

  /// 被吃掉八成以上再跌破门槛 = 已成交；结束时刻记第一次跌破那一拍，名义留着结束前那一拍的。
  func testEndingWithEnoughFillsIsFilled() {
    var model = inBand(okx)
    _ = model.evaluate(nowMs: 0)
    _ = model.evaluate(nowMs: 500)
    let initial = 1_590.0 * 12_000
    // 主动卖打到 1590.4（同一个桶），合计 85%。
    _ = model.ingest(okx.id, .trade(OrderFlowTrade(price: 1_590.4, quantity: 12_000 * 0.85, hitSide: .bid, timeMs: 0)), nowMs: 600)
    // 打到卖侧、别的桶的不算。
    _ = model.ingest(okx.id, .trade(OrderFlowTrade(price: 1_590, quantity: 99_999, hitSide: .ask, timeMs: 0)), nowMs: 600)
    _ = model.ingest(okx.id, .trade(OrderFlowTrade(price: 1_591, quantity: 99_999, hitSide: .bid, timeMs: 0)), nowMs: 600)
    set(&model, okx, seq: 2, bid: level(1_590, 1_000))
    XCTAssertEqual(model.evaluate(nowMs: 1_000).orders.first?.status, .live, "跌破的第一拍还挂着")
    let order = model.evaluate(nowMs: 1_300).orders[0]
    XCTAssertEqual(order.status, .filled)
    XCTAssertEqual(order.endMs, 1_000)
    XCTAssertEqual(order.filledNotional, 1_590.4 * 12_000 * 0.85, accuracy: 1e-6)
    XCTAssertEqual(order.notional, initial, "名义留着结束前最后一次过门槛的")
    // 成交比例的分母是消失掉的那部分：1590 × (12 000 − 1 000)，和判定同一个口径。
    XCTAssertEqual(order.vanishedNotional ?? 0, 1_590 * 11_000, accuracy: 1e-6)
    XCTAssertEqual(order.fillRatio, 1_590.4 * 12_000 * 0.85 / (1_590 * 11_000), accuracy: 1e-9)
  }

  func testEndingWithFewFillsIsCancelled() {
    var model = inBand(okx)
    _ = model.evaluate(nowMs: 0)
    _ = model.evaluate(nowMs: 500)
    _ = model.ingest(okx.id, .trade(OrderFlowTrade(price: 1_590, quantity: 12_000 * 0.3, hitSide: .bid, timeMs: 0)), nowMs: 600)
    set(&model, okx, seq: 2, bid: level(1_590, 0))
    _ = model.evaluate(nowMs: 1_000)
    let order = model.evaluate(nowMs: 1_400).orders[0]
    XCTAssertEqual(order.status, .cancelled)
    XCTAssertEqual(order.endMs, 1_000)
  }

  /// 退出滞回：缩到门槛以下、退出线（门槛 × 0.5）以上仍然挂着，名义跟着更新；跌破退出线才结束。
  func testShrinkingAboveExitLineStaysLive() {
    var model = inBand(okx)
    _ = model.evaluate(nowMs: 0)
    _ = model.evaluate(nowMs: 500)
    // 1590 × 2 000 = 318 万：低于门槛 500 万、高于退出线 250 万。
    set(&model, okx, seq: 2, bid: level(1_590, 2_000))
    _ = model.evaluate(nowMs: 1_000)
    let shrunk = model.evaluate(nowMs: 1_500).orders[0]
    XCTAssertEqual(shrunk.status, .live)
    XCTAssertEqual(shrunk.notional, 1_590 * 2_000, "名义跟着缩")
    XCTAssertEqual(shrunk.initialNotional, 1_590 * 12_000)
    // 1590 × 1 500 = 238 万：跌破退出线，两拍后结束。
    set(&model, okx, seq: 3, bid: level(1_590, 1_500))
    XCTAssertEqual(model.evaluate(nowMs: 2_000).orders[0].status, .live)
    let ended = model.evaluate(nowMs: 2_400).orders[0]
    XCTAssertEqual(ended.status, .cancelled)
    XCTAssertEqual(ended.endMs, 2_000)
    XCTAssertEqual(ended.notional, 1_590 * 2_000, "名义留着结束前最后一次在退出线上的")
  }

  /// 成交比的是消失掉的那部分：结束时桶里还剩的既没成交也没撤。
  func testFilledRatioIsAgainstTheVanishedPart() {
    var model = inBand(okx)
    _ = model.evaluate(nowMs: 0)
    _ = model.evaluate(nowMs: 500)
    // 首次 12 000 个币；主动卖吃掉 9 000 个（75%，按首次名义算不到八成）。
    _ = model.ingest(okx.id, .trade(OrderFlowTrade(price: 1_590, quantity: 9_000, hitSide: .bid, timeMs: 0)), nowMs: 600)
    // 剩 1 500 个（238 万，跌破退出线）：消失了 10 500 个，成交 9 000 ≥ 10 500 × 0.8 = 8 400 → 已成交。
    set(&model, okx, seq: 2, bid: level(1_590, 1_500))
    _ = model.evaluate(nowMs: 1_000)
    XCTAssertEqual(model.evaluate(nowMs: 1_400).orders[0].status, .filled)
  }

  /// 加码后撤：挂出 1908 万、加到 6360 万后整张撤掉，其间被吃了 1590 万。按首次名义算够八成（会判已成交），
  /// 按跌破前最后一拍的 6360 万算只成交了四分之一——是撤的。
  func testAddedThenPulledIsCancelled() {
    var model = inBand(okx)
    _ = model.evaluate(nowMs: 0)
    _ = model.evaluate(nowMs: 500)
    set(&model, okx, seq: 2, bid: level(1_590, 40_000))
    XCTAssertEqual(model.evaluate(nowMs: 1_000).orders[0].notional, 1_590 * 40_000)
    _ = model.ingest(okx.id, .trade(OrderFlowTrade(price: 1_590, quantity: 10_000, hitSide: .bid, timeMs: 0)), nowMs: 1_100)
    XCTAssertEqual(model.evaluate(nowMs: 1_200).orders[0].fillRatio, 0.25, accuracy: 1e-9, "挂着的按此刻名义算")
    set(&model, okx, seq: 3, bid: level(1_590, 0))
    _ = model.evaluate(nowMs: 1_500)
    let order = model.evaluate(nowMs: 2_000).orders[0]
    XCTAssertEqual(order.status, .cancelled)
    XCTAssertEqual(order.vanishedNotional ?? 0, 1_590 * 40_000, accuracy: 1e-6)
    XCTAssertEqual(order.fillRatio, 0.25, accuracy: 1e-9)
  }

  /// 减仓后被吃：挂出 1908 万，先撤到 636 万（还在退出线 250 万以上），再被吃掉 556.5 万跌破退出线。
  /// 按首次名义算只成交三成（会判撤单），按跌破前最后一拍的 636 万算消失的部分全是被吃的——已成交。
  func testShrunkThenEatenIsFilled() {
    var model = inBand(okx)
    _ = model.evaluate(nowMs: 0)
    _ = model.evaluate(nowMs: 500)
    set(&model, okx, seq: 2, bid: level(1_590, 4_000))
    XCTAssertEqual(model.evaluate(nowMs: 1_000).orders[0].status, .live)
    _ = model.ingest(okx.id, .trade(OrderFlowTrade(price: 1_590, quantity: 3_500, hitSide: .bid, timeMs: 0)), nowMs: 1_100)
    set(&model, okx, seq: 3, bid: level(1_590, 500))
    _ = model.evaluate(nowMs: 1_500)
    let order = model.evaluate(nowMs: 2_000).orders[0]
    XCTAssertEqual(order.status, .filled)
    XCTAssertEqual(order.vanishedNotional ?? 0, 1_590 * 3_500, accuracy: 1e-6)
    XCTAssertEqual(order.fillRatio, 1, accuracy: 1e-9)
  }

  /// 旧版日志没有「消失掉的名义」：读回来按名义算，不崩、不改判定。
  func testOldJournalWithoutVanishedDecodes() throws {
    let json = #"{"version":1,"symbol":"ETHUSDT","step":1,"savedAtMs":0,"orders":[{"v":"okx","x":"OKX","p":"usdtPerp","s":"bid","b":1590,"px":1590,"f":0,"e":10,"st":"filled","n0":8000000,"n":6000000,"fl":3000000,"t":5000000}]}"#
    let journal = try XCTUnwrap(OrderFlowJournal.decode(Data(json.utf8)))
    XCTAssertNil(journal.orders[0].vanishedNotional)
    XCTAssertEqual(journal.orders[0].fillRatio, 0.5, accuracy: 1e-9)
  }

  /// 跌破一拍又回来：不结束，重新算。
  func testDipAndRecoverStaysLive() {
    var model = inBand(okx)
    _ = model.evaluate(nowMs: 0)
    _ = model.evaluate(nowMs: 500)
    set(&model, okx, seq: 2, bid: level(1_590, 150))
    _ = model.evaluate(nowMs: 1_000)
    set(&model, okx, seq: 3, bid: level(1_590, 14_000))
    let order = model.evaluate(nowMs: 1_500).orders[0]
    XCTAssertEqual(order.status, .live)
    XCTAssertEqual(order.notional, 1_590 * 14_000)
    XCTAssertEqual(order.initialNotional, 1_590 * 12_000, "首次名义不跟着涨")
  }

  /// 成交只记同一本簿自己的：别家打到同一侧同一桶的成交不记；一本簿一本簿各自出单。
  func testTradesOnlyCountOnTheirOwnVenueAndVenuesAreTrackedSeparately() {
    var model = OrderFlowModel(symbol: "ETHUSDT", thresholds: thresholds)
    for venue in [okx, coinbase] {
      model.addVenue(venue)
      _ = model.connectionOpened(venue.id)
    }
    _ = model.ingest(okx.id, .snapshot(deepSnapshot(last: 1)), nowMs: 0)
    // Coinbase 现货：1590 挂 1000 个币（159 万 ≥ 现货门槛 100 万）。
    _ = model.ingest(coinbase.id, .snapshot(deepSnapshot(last: 1, wall: 1_000)), nowMs: 0)
    _ = model.evaluate(nowMs: 0)
    let frame = model.evaluate(nowMs: 500)
    XCTAssertEqual(Set(frame.orders.map(\.exchange)), ["OKX", "Coinbase"])
    XCTAssertEqual(Set(frame.orders.map(\.product)), [.usdtPerp, .spot])
    _ = model.ingest(coinbase.id, .trade(OrderFlowTrade(price: 1_590, quantity: 100, hitSide: .bid, timeMs: 0)), nowMs: 600)
    _ = model.ingest(okx.id, .trade(OrderFlowTrade(price: 1_590, quantity: 10, hitSide: .bid, timeMs: 0)), nowMs: 600)
    let after = model.evaluate(nowMs: 700).orders
    XCTAssertEqual(after.first { $0.exchange == "Coinbase" }?.filledNotional, 159_000)
    XCTAssertEqual(after.first { $0.exchange == "OKX" }?.filledNotional, 15_900, "Coinbase 的成交不记进 OKX 那一单")
  }

  /// 正在确认中的候选也只收自己这本簿的成交。
  func testCandidateOnlyCollectsItsOwnVenuesTrades() {
    var model = OrderFlowModel(symbol: "ETHUSDT", thresholds: thresholds)
    for venue in [okx, coinbase] {
      model.addVenue(venue)
      _ = model.connectionOpened(venue.id)
    }
    _ = model.ingest(okx.id, .snapshot(deepSnapshot(last: 1)), nowMs: 0)
    _ = model.ingest(coinbase.id, .snapshot(deepSnapshot(last: 1, wall: 0)), nowMs: 0)
    _ = model.evaluate(nowMs: 0)  // OKX 1590 成了候选
    _ = model.ingest(coinbase.id, .trade(OrderFlowTrade(price: 1_590, quantity: 100, hitSide: .bid, timeMs: 0)), nowMs: 100)
    _ = model.ingest(okx.id, .trade(OrderFlowTrade(price: 1_590, quantity: 20, hitSide: .bid, timeMs: 0)), nowMs: 100)
    let order = model.evaluate(nowMs: 500).orders.first { $0.exchange == "OKX" }
    XCTAssertEqual(order?.filledNotional, 31_800)
  }

  /// 币本位：张数 × 面值换成美元再比门槛。
  func testInverseVenueComparesUsdNotional() {
    var model = OrderFlowModel(symbol: "ETHUSDT", thresholds: thresholds)
    model.addVenue(coinM)
    _ = model.connectionOpened(coinM.id)
    _ = model.ingest(coinM.id, .delta(BookDelta(firstUpdateID: 95, finalUpdateID: 101, previousFinalUpdateID: 94)), nowMs: 0)
    // 1590 挂 600 000 张 × 10 美元 = 600 万；其余 150 张 = 1500 美元。
    _ = model.applySnapshot(coinM.id, deepSnapshot(last: 100, wall: 600_000), nowMs: 0)
    _ = model.evaluate(nowMs: 0)
    let order = model.evaluate(nowMs: 400).orders[0]
    XCTAssertEqual(order.initialNotional, 6_000_000)
    XCTAssertEqual(order.product, .coinPerp)
    _ = model.ingest(coinM.id, .trade(OrderFlowTrade(price: 1_590, quantity: 1_000, hitSide: .bid, timeMs: 0)), nowMs: 500)
    XCTAssertEqual(model.evaluate(nowMs: 600).orders[0].filledNotional, 10_000)
  }

  /// 这只没有的产品（门槛为 nil）不出单。
  func testProductWithoutThresholdIsIgnored() {
    var model = OrderFlowModel(symbol: "MUUSDT", thresholds: OrderFlowThresholds(usdtPerp: 2_000_000, step: 1))
    model.addVenue(coinbase)
    _ = model.connectionOpened(coinbase.id)
    _ = model.ingest(coinbase.id, .snapshot(deepSnapshot(last: 1, wall: 100_000)), nowMs: 0)
    _ = model.evaluate(nowMs: 0)
    XCTAssertEqual(model.evaluate(nowMs: 500).orders, [])
  }

  /// 簿没就绪：它的单不新增、不结束；断开超过两分钟才按最后一次看到时结束。
  func testDisconnectedVenueFreezesThenExpires() {
    var model = inBand(okx)
    _ = model.evaluate(nowMs: 0)
    _ = model.evaluate(nowMs: 500)
    model.disconnected(okx.id)
    XCTAssertEqual(model.evaluate(nowMs: 1_000).orders.first?.status, .live)
    XCTAssertEqual(model.evaluate(nowMs: 60_000).orders.first?.status, .live)
    let order = model.evaluate(nowMs: 500 + OrderFlowModel.staleMs).orders[0]
    XCTAssertEqual(order.status, .lost, "断线之后成交还是撤单不知道：失联结束，不判撤单")
    XCTAssertEqual(order.endMs, 500, "按最后一次看到时结束")
    XCTAssertNil(order.vanishedNotional)
    XCTAssertTrue(OrderFlowDisplay(filled: false, cancelled: false)
      .shows(order), "失联结束的不归成交 / 撤销开关管")
  }

  /// 24 小时以前结束的删掉；结束的超过 500 条删结束最早的；挂着的不删。
  func testRetentionKeepsTwentyFourHoursAndFiveHundredEndedOrders() {
    var journalOrders: [BigOrder] = []
    for k in 0..<530 {
      journalOrders.append(BigOrder(venueID: okx.id, exchange: "OKX", product: .usdtPerp, side: .ask,
                                    bucket: Int64(2_000 + k), price: Double(2_000 + k), firstSeenMs: Int64(k),
                                    endMs: Int64(1_000 + k), status: .cancelled, initialNotional: 6_000_000,
                                    notional: 6_000_000, threshold: 5_000_000))
    }
    let journal = OrderFlowJournal(symbol: "ETHUSDT", step: 1, savedAtMs: 2_000, orders: journalOrders)
    var model = inBand(okx, restored: journal)
    XCTAssertEqual(model.orders.count, 530)
    _ = model.evaluate(nowMs: 3_000)
    let frame = model.evaluate(nowMs: 3_500)
    XCTAssertEqual(frame.orders.filter { !$0.isLive }.count, OrderFlowDefaults.maxEndedOrders)
    XCTAssertEqual(frame.orders.filter(\.isLive).count, 1, "挂着的那条留着，不占结束单的额度")
    XCTAssertEqual(frame.orders.filter { !$0.isLive }.map(\.endMs).compactMap { $0 }.min(), 1_030, "删的是结束最早的 30 条")
    let later = model.evaluate(nowMs: 1_100 + OrderFlowDefaults.retentionMs)
    XCTAssertEqual(later.orders.filter { !$0.isLive }.count, 430, "结束超过 24 小时的删掉")
  }

  /// 改门槛：首次名义不到新门槛的删掉，其余换成新门槛；改步长整份清掉。
  func testThresholdAndStepChanges() {
    var model = inBand(okx)
    _ = model.evaluate(nowMs: 0)
    _ = model.evaluate(nowMs: 500)
    XCTAssertEqual(model.orders.count, 1)
    var higher = thresholds
    higher.usdtPerp = 15_000_000
    model.setThresholds(higher)
    XCTAssertEqual(model.orders.first?.threshold, 15_000_000)
    higher.usdtPerp = 20_000_000
    model.setThresholds(higher)
    XCTAssertEqual(model.orders, [], "1908 万不到 2000 万")
    model.setThresholds(thresholds)
    _ = model.evaluate(nowMs: 1_000)
    XCTAssertEqual(model.evaluate(nowMs: 1_500).orders.first?.firstSeenMs, 1_000, "门槛降回来，从这一刻重新确认出现")
    var coarse = thresholds
    coarse.step = 10
    model.setThresholds(coarse)
    XCTAssertEqual(model.orders, [])
    XCTAssertEqual(model.scheme?.step, 10)
  }

  /// 落盘读回：步长一致才认；步长还不知道时先放着，知道了再认；结束的上限 500 条（`d415d680` 从 200 调上来）也不到 128 KB。
  func testJournalRoundTripAndDeferredRestore() throws {
    var model = inBand(okx)
    _ = model.evaluate(nowMs: 0)
    _ = model.evaluate(nowMs: 500)
    let journal = try XCTUnwrap(model.journal(nowMs: 600))
    let decoded = try XCTUnwrap(OrderFlowJournal.decode(journal.encoded()))
    XCTAssertEqual(decoded, journal)

    var noStep = thresholds
    noStep.step = nil
    var deferred = OrderFlowModel(symbol: "ETHUSDT", thresholds: noStep, restored: decoded)
    XCTAssertEqual(deferred.orders, [])
    XCTAssertEqual(deferred.evaluate(nowMs: 700).phase, .loading)
    deferred.setThresholds(thresholds)
    XCTAssertEqual(deferred.orders, journal.orders)

    var other = thresholds
    other.step = 2
    XCTAssertEqual(OrderFlowModel(symbol: "ETHUSDT", thresholds: other, restored: decoded).orders, [],
                   "步长不一样，桶号对不上，整份作废")
    XCTAssertNil(OrderFlowJournal.decode(Data("{}".utf8)))

    let many = (0..<OrderFlowDefaults.maxEndedOrders).map { k in
      BigOrder(venueID: "binance:coinPerp:BTCUSD_PERP", exchange: "币安", product: .coinPerp, side: .bid,
               bucket: Int64(840 + k), price: 84_123.4, firstSeenMs: 1_790_000_000_000 + Int64(k),
               endMs: 1_790_000_600_000, status: .filled, initialNotional: 5_312_345.67, notional: 5_312_345.67,
               filledNotional: 4_400_000.12, threshold: 5_000_000, vanishedNotional: 5_312_345.67)
    }
    let size = OrderFlowJournal(symbol: "BTCUSDT", step: 100, savedAtMs: 0, orders: many).encoded().count
    // 500 条实测约 110 KB；日志 15 秒最多写一次，这个量级落盘不是负担（原来 200 条时的 64 KB 线跟着放宽）。
    XCTAssertLessThan(size, 128 * 1024, "\(size) 字节")
  }

  /// 进程重启读回来的挂单，簿一就绪就照常续上；那本簿再没出现，两分钟后按存盘时刻结束。
  func testRestoredLiveOrdersContinueOrExpire() throws {
    var first = inBand(okx)
    _ = first.evaluate(nowMs: 0)
    _ = first.evaluate(nowMs: 500)
    let journal = try XCTUnwrap(first.journal(nowMs: 800))

    var resumed = inBand(okx, restored: journal)
    _ = resumed.evaluate(nowMs: 10_000)
    let order = resumed.evaluate(nowMs: 10_500).orders
    XCTAssertEqual(order.count, 1)
    XCTAssertEqual(order.first?.firstSeenMs, 0, "同一条单续上，不重新出现")

    var orphan = OrderFlowModel(symbol: "ETHUSDT", thresholds: thresholds, restored: journal)
    _ = orphan.evaluate(nowMs: 10_000)
    let ended = orphan.evaluate(nowMs: 10_000 + OrderFlowModel.staleMs).orders[0]
    XCTAssertEqual(ended.status, .lost)
    XCTAssertEqual(ended.endMs, 800)
  }

  /// 存盘之后缺席超过两分钟才再打开：读回的挂单第一次评估就按存盘时刻失联结束；
  /// 那个桶此刻还过门槛，就当一条新出现的单，从这一刻重新确认——不把缺席的那几小时画成一直挂着。
  func testRestoredAfterLongAbsenceEndsAtSaveTimeAndReappearsAsNew() throws {
    var first = inBand(okx)
    _ = first.evaluate(nowMs: 0)
    _ = first.evaluate(nowMs: 500)
    let journal = try XCTUnwrap(first.journal(nowMs: 800))

    var later = inBand(okx, restored: journal)
    let back: Int64 = 800 + 3_600_000
    let frame = later.evaluate(nowMs: back)
    XCTAssertEqual(frame.orders.count, 1)
    XCTAssertEqual(frame.orders[0].status, .lost)
    XCTAssertEqual(frame.orders[0].endMs, 800, "按存盘时刻结束，不是现在")
    let next = later.evaluate(nowMs: back + 500).orders
    XCTAssertEqual(next.count, 2)
    XCTAssertEqual(next.filter { $0.isLive }.map { $0.firstSeenMs }, [back], "桶还在：当一条新出现的单")
  }

  /// 成交按（簿、侧、桶）索引记账：读回来的挂单、改门槛之后留下的挂单都还能收到成交；已经结束的不再收。
  func testFillIndexSurvivesRestoreThresholdChangeAndEnding() throws {
    var first = inBand(okx)
    _ = first.evaluate(nowMs: 0)
    _ = first.evaluate(nowMs: 500)
    let journal = try XCTUnwrap(first.journal(nowMs: 600))
    var model = inBand(okx, restored: journal)
    _ = model.ingest(okx.id, .trade(OrderFlowTrade(price: 1_590, quantity: 10, hitSide: .bid, timeMs: 0)), nowMs: 700)
    XCTAssertEqual(model.orders.first?.filledNotional, 15_900, "读回来的挂单照样记成交")
    var higher = thresholds
    higher.usdtPerp = 6_000_000
    model.setThresholds(higher)
    _ = model.ingest(okx.id, .trade(OrderFlowTrade(price: 1_590, quantity: 10, hitSide: .bid, timeMs: 0)), nowMs: 800)
    XCTAssertEqual(model.orders.first?.filledNotional, 31_800, "改门槛之后留下的挂单照样记成交")
    set(&model, okx, seq: 2, bid: level(1_590, 0))
    _ = model.evaluate(nowMs: 1_000)
    _ = model.evaluate(nowMs: 1_400)
    XCTAssertEqual(model.orders.first?.isLive, false)
    _ = model.ingest(okx.id, .trade(OrderFlowTrade(price: 1_590, quantity: 10, hitSide: .bid, timeMs: 0)), nowMs: 1_500)
    XCTAssertEqual(model.orders.first?.filledNotional, 31_800, "结束了的不再收")
  }

  func testLiveOrdersSortByFirstSeen() {
    var model = inBand(okx)
    _ = model.evaluate(nowMs: 0)
    _ = model.evaluate(nowMs: 500)
    set(&model, okx, seq: 2, bid: level(1_580, 12_000))
    _ = model.evaluate(nowMs: 1_000)
    let frame = model.evaluate(nowMs: 1_500)
    XCTAssertEqual(frame.orders.map(\.firstSeenMs), [0, 1_000])
    XCTAssertEqual(frame.venues, [OrderFlowVenueStatus(label: "OKX", product: .usdtPerp, instrument: "ETH-USDT-SWAP", ready: true)])
  }
}
