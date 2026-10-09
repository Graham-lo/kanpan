import XCTest
@testable import KanpanCore

final class OrderFlowInsightDigestTests: XCTestCase {
  private let start: Int64 = 1_791_424_800_000
  private func bar(_ minute: Int, close: Double = 100.1) -> Bar {
    Bar(openTime: start + Int64(minute) * 60_000, open: 100, high: max(100.2, close), low: min(99.9, close), close: close, volume: 10)
  }
  private func order(_ venue: String, _ price: Double, _ side: BookSide, status: BigOrder.Status = .live) -> BigOrder {
    BigOrder(venueID: venue, exchange: venue, product: .usdtPerp, side: side, bucket: Int64(price), price: price,
             firstSeenMs: start, endMs: status == .live ? nil : start + 60_000, status: status,
             initialNotional: 1000, notional: 800, filledNotional: 200, threshold: 500)
  }
  func testPrimaryIdentityDoesNotSubstituteAnotherExchangeProductOrQuote() {
    let instrument = InstrumentID("okx/usd_m/BTCUSDT")
    XCTAssertTrue(OrderFlowInsightDigest.isPrimary(venueID: "okx:usdtPerp:BTC-USDT-SWAP", product: .usdtPerp, instrument: instrument))
    XCTAssertFalse(OrderFlowInsightDigest.isPrimary(venueID: "bybit:usdtPerp:BTCUSDT", product: .usdtPerp, instrument: instrument))
    XCTAssertFalse(OrderFlowInsightDigest.isPrimary(venueID: "okx:usdtPerp:BTC-USDC-SWAP", product: .usdtPerp, instrument: instrument))
    XCTAssertFalse(OrderFlowInsightDigest.isPrimary(venueID: "okx:spot:BTC-USDT", product: .spot, instrument: instrument))
    XCTAssertFalse(OrderFlowInsightDigest.isPrimary(venueID: "okx:spot:BTC-USDT", product: .usdtPerp, instrument: instrument))
  }
  func testNearestWallsOnlyUseLiveExactInstrument() {
    let orders = [order("binance:usdtPerp:BTCUSDT", 99, .bid), order("okx:usdtPerp:BTC-USDT-SWAP", 99.5, .bid),
                  order("binance:usdtPerp:BTCUSDT", 101, .ask), order("binance:usdtPerp:BTCUSDT", 100.5, .ask, status: .lost)]
    let walls = OrderFlowInsightDigest.nearestWalls(orders, instrument: InstrumentID("BTCUSDT"), price: 100, nowMs: start + 60_000)
    XCTAssertEqual(walls.bid?.order.price, 99)
    XCTAssertEqual(walls.ask?.order.price, 101)
    XCTAssertEqual(walls.ask?.durationMs, 60_000)
    XCTAssertEqual(walls.ask?.distancePercent ?? 0, 1, accuracy: 1e-8)
  }
  func testDisconnectedBookWithLiveOrderCannotClaimCurrentLiquidity() {
    var o = order("binance:usdtPerp:BTCUSDT", 101, .ask)
    o.exchange = "币安"
    var snapshot = OrderFlowSnapshot(symbol: "BTCUSDT", phase: .ready, orders: [o], asOfMs: start,
      venues: [.init(label: "币安", product: .usdtPerp, instrument: "BTCUSDT", ready: false)])
    XCTAssertTrue(OrderFlowInsightDigest.currentOrders(snapshot, symbol: "BTCUSDT", nowMs: start).isEmpty)
    snapshot.venues[0].ready = true
    XCTAssertEqual(OrderFlowInsightDigest.currentOrders(snapshot, symbol: "BTCUSDT", nowMs: start).count, 1)
    XCTAssertTrue(OrderFlowInsightDigest.currentOrders(snapshot, symbol: "BTCUSDT", nowMs: start + 30_001).isEmpty)
    XCTAssertTrue(OrderFlowInsightDigest.currentOrders(snapshot, symbol: "ETHUSDT", nowMs: start).isEmpty)
  }
  func testMinuteReactionRequiresContinuousCompletedExactWindow() {
    let bars = (0..<5).map { bar($0) }
    let reaction = OrderFlowInsightDigest.reaction(bars: bars, fromMs: start, toMs: start + 5 * 60_000)
    XCTAssertEqual(reaction?.percent ?? 0, 0.1, accuracy: 1e-8)
    XCTAssertNil(OrderFlowInsightDigest.reaction(bars: [bars[0], bars[2], bars[3], bars[4]], fromMs: start, toMs: start + 5 * 60_000))
    XCTAssertNil(OrderFlowInsightDigest.reaction(bars: bars, fromMs: start, toMs: start + 6 * 60_000))
    XCTAssertNil(OrderFlowInsightDigest.reaction(bars: [bar(0)], fromMs: start, toMs: start + 60_000))
  }
  func testEvidenceThresholdsAndMissingCoverageDoNotPredictAbsorption() {
    let advancing = OrderFlowInsightDigest.reaction(bars: (0..<5).map { bar($0) }, fromMs: start, toMs: start + 5 * 60_000)
    XCTAssertEqual(OrderFlowInsightDigest.observation(buy: 600, sell: 400, reaction: advancing, covered: true), .buyAdvance)
    XCTAssertEqual(OrderFlowInsightDigest.observation(buy: 599, sell: 401, reaction: advancing, covered: true), .balanced)
    XCTAssertEqual(OrderFlowInsightDigest.observation(buy: 600, sell: 400, reaction: advancing, covered: false), .insufficient)
    XCTAssertEqual(OrderFlowInsightDigest.observation(buy: 0, sell: 0, reaction: advancing, covered: true), .insufficient)
    let stationary = OrderFlowInsightDigest.reaction(bars: (0..<5).map { bar($0, close: 100.01) }, fromMs: start, toMs: start + 5 * 60_000)
    XCTAssertEqual(OrderFlowInsightDigest.observation(buy: 400, sell: 600, reaction: stationary, covered: true), .sellNoAdvance)
  }
  func testLostLifecycleRemainsUnknownAndRecentEventsHaveBoundedTime() {
    let lost = order("binance:usdtPerp:BTCUSDT", 100, .ask, status: .lost)
    XCTAssertEqual(OrderFlowInsightDigest.recentEvents([lost], nowMs: start + 120_000).first?.status, .lost)
    XCTAssertTrue(OrderFlowInsightDigest.recentEvents([lost], nowMs: start + 4_000_000).isEmpty)
    XCTAssertTrue(OrderFlowInsightDigest.recentEvents([lost], nowMs: start + 16 * 60_000 + 1).isEmpty)
    XCTAssertTrue(OrderFlowInsightDigest.recentEvents([order("binance:usdtPerp:BTCUSDT", 100, .ask)], nowMs: start + 120_000).isEmpty)
    var many = (0..<7).map { _ in lost }
    for i in many.indices { many[i].endMs = start + Int64(i + 1) * 60_000 }
    XCTAssertEqual(OrderFlowInsightDigest.recentEvents(many, nowMs: start + 8 * 60_000).count, 4)
  }
  func testTruePriceZonesScaleAndPreserveSeparateVenues() throws {
    let json = """
    {"base":"PEPE","generatedAtMs":1791424800000,"dayStartMs":1791388800000,"tracked":true,"coverageSinceMs":1791388800000,"lastTradeMs":1791424740000,"bigUsd":1000,"windows":[],"zones":[
    {"venueID":"binance:usdtPerp:1000PEPEUSDT","exchange":"币安","product":"usdtPerp","low":0.00001,"high":0.00002,"buyUsd":10000,"sellUsd":5000,"recentBuyUsd":1000,"recentSellUsd":0,"firstMs":1791420000000,"lastMs":1791424740000},
    {"venueID":"okx:usdtPerp:PEPE-USDT-SWAP","exchange":"OKX","product":"usdtPerp","low":0.00001,"high":0.00002,"buyUsd":7000,"sellUsd":3000,"recentBuyUsd":0,"recentSellUsd":0,"firstMs":1791420000000,"lastMs":1791424740000}]}
    """
    let page = try JSONDecoder().decode(OrderFlowInsightsPage.self, from: Data(json.utf8))
    XCTAssertTrue(page.isValid)
    let ranked = OrderFlowInsightDigest.rankedZones(page, chartScale: 1000)
    XCTAssertEqual(ranked.count, 2)
    XCTAssertEqual(ranked[0].low, 0.01, accuracy: 1e-10)
    XCTAssertEqual(ranked[0].total, 15000)
    XCTAssertNotEqual(ranked[0].venueID, ranked[1].venueID)
  }
}
