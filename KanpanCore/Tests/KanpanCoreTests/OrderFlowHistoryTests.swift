import XCTest
@testable import KanpanCore

/// 服务端历史并进本机模型（`OrderFlowModel.mergeHistory`）与服务端 JSON 的解析。
final class OrderFlowHistoryTests: XCTestCase {
  /// 步长 1 美元，永续门槛 500 万、现货 100 万。
  private let thresholds = OrderFlowThresholds(spot: 1_000_000, usdtPerp: 5_000_000, coinPerp: 5_000_000,
                                               delivery: 5_000_000, step: 1)
  private let okx = OrderFlowVenue(exchange: "okx", label: "OKX", product: .usdtPerp, instrument: "ETH-USDT-SWAP",
                                   notional: .linear(multiplier: 1), sequenceModel: .previousFinalExact,
                                   snapshotInBand: true)
  private let spotID = "binance:spot:ETHUSDT"

  private func level(_ price: Double, _ quantity: Double) -> BookLevel { BookLevel(price: price, quantity: quantity) }

  /// 买侧 1600 往下每 1 美元一档 150 个币；1590 那一档挂 12 000 个币（1908 万美元）。
  private func ready(restored: OrderFlowJournal? = nil, thresholds: OrderFlowThresholds? = nil) -> OrderFlowModel {
    var model = OrderFlowModel(symbol: "ETHUSDT", thresholds: thresholds ?? self.thresholds, restored: restored)
    model.addVenue(okx)
    _ = model.connectionOpened(okx.id)
    var bids = (1...40).map { level(1_600 - Double($0), 150) }
    bids[9] = level(1_590, 12_000)
    let asks = (1...40).map { level(1_600 + Double($0), 150) }
    _ = model.ingest(okx.id, .snapshot(BookSnapshot(lastUpdateID: 1, requestedLevels: 1_000, bids: bids, asks: asks)),
                     nowMs: 0)
    return model
  }

  private func shrinkWall(_ model: inout OrderFlowModel) {
    _ = model.ingest(okx.id, .delta(BookDelta(firstUpdateID: 2, finalUpdateID: 2, previousFinalUpdateID: 1,
                                              bids: [level(1_590, 150)], asks: [], eventTimeMs: 0)), nowMs: 0)
  }

  private func remote(_ venue: String? = nil, product: OrderFlowProduct = .usdtPerp, side: BookSide = .bid,
                      price: Double = 1_590, first: Int64, end: Int64? = nil,
                      status: BigOrder.Status = .live, initial: Double = 6_000_000, filled: Double = 0) -> BigOrder {
    // 服务端的桶号按它自己的步长算，并进来时会重新分桶，这里故意给个不相干的数。
    BigOrder(venueID: venue ?? okx.id, exchange: "OKX", product: product, side: side, bucket: -1, price: price,
             firstSeenMs: first, endMs: end, status: status, initialNotional: initial, notional: initial,
             filledNotional: filled, threshold: 5_000_000, vanishedNotional: end == nil ? nil : initial)
  }

  private func page(_ orders: [BigOrder], step: Double? = 1) -> OrderFlowHistoryPage {
    OrderFlowHistoryPage(base: "ETH", thresholds: OrderFlowThresholds(spot: 1_000_000, usdtPerp: 5_000_000, step: step),
                         trackedSinceMs: -86_400_000, fromMs: -86_400_000, toMs: 0, orders: orders)
  }

  // MARK: - 解析

  func testParsesTheServerShapeAndDropsBadRows() throws {
    let json = """
    {"base":"BTC","thresholds":{"coinPerp":5e6,"delivery":5e6,"spot":1e6,"step":100,"usdtPerp":5e6},
     "trackedSinceMs":1790256061037,
     "orders":[
      {"bucket":837,"endMs":1790256177970,"exchange":"OKX","filledNotional":57340.0,"firstSeenMs":1790256064113,
       "initialNotional":8859900.0,"notional":3825810.0,"price":83700.5,"product":"coinPerp","side":"bid",
       "status":"cancelled","threshold":5000000.0,"vanishedNotional":1435610.0,"venueID":"okx:coinPerp:BTC-USD-SWAP"},
      {"bucket":840,"endMs":null,"exchange":"币安","filledNotional":0,"firstSeenMs":1790256070000,
       "initialNotional":1200000.0,"notional":1300000.0,"price":84000,"product":"spot","side":"ask",
       "status":"live","threshold":1000000.0,"vanishedNotional":null,"venueID":"binance:spot:BTCUSDT"},
      {"bucket":1,"exchange":"X","firstSeenMs":1,"initialNotional":1,"price":1,"product":"option","side":"bid",
       "status":"live","threshold":1,"venueID":"x:option:X"},
      {"bucket":1,"exchange":"X","firstSeenMs":1,"initialNotional":1,"price":1,"product":"spot","side":"bid",
       "status":"filled","threshold":1,"venueID":"x:spot:X"}
     ]}
    """
    let parsed = try XCTUnwrap(OrderFlowHistoryPage.parse(Data(json.utf8), fromMs: 10, toMs: 20))
    XCTAssertEqual(parsed.base, "BTC")
    XCTAssertEqual(parsed.thresholds, OrderFlowThresholds(spot: 1e6, usdtPerp: 5e6, coinPerp: 5e6, delivery: 5e6, step: 100))
    XCTAssertEqual(parsed.trackedSinceMs, 1_790_256_061_037)
    XCTAssertEqual(parsed.orders.count, 2, "未知产品、结束了却没有结束时刻的两条丢掉")
    XCTAssertEqual(parsed.orders[0], BigOrder(
      venueID: "okx:coinPerp:BTC-USD-SWAP", exchange: "OKX", product: .coinPerp, side: .bid, bucket: 837,
      price: 83_700.5, firstSeenMs: 1_790_256_064_113, endMs: 1_790_256_177_970, status: .cancelled,
      initialNotional: 8_859_900, notional: 3_825_810, filledNotional: 57_340, threshold: 5_000_000,
      vanishedNotional: 1_435_610))
    XCTAssertTrue(parsed.orders[1].isLive)
    XCTAssertNil(parsed.orders[1].endMs)
    XCTAssertEqual(parsed.latestMs, 1_790_256_177_970)
    XCTAssertNil(OrderFlowHistoryPage.parse(Data("{\"error\":\"x\"}".utf8), fromMs: 0, toMs: 1))
  }

  // MARK: - 合并

  /// 同簿同侧同桶、时间重叠：以服务端为准；只有本机有的留着。
  func testOverlapTakesTheServerAndLocalOnlyStays() {
    let local = [
      BigOrder(venueID: okx.id, exchange: "OKX", product: .usdtPerp, side: .ask, bucket: 1_700, price: 1_700.2,
               firstSeenMs: -50_000, endMs: -20_000, status: .cancelled, initialNotional: 6_000_000,
               notional: 6_000_000, threshold: 5_000_000, vanishedNotional: 6_000_000),
      BigOrder(venueID: okx.id, exchange: "OKX", product: .usdtPerp, side: .ask, bucket: 1_800, price: 1_800,
               firstSeenMs: -40_000, endMs: -30_000, status: .cancelled, initialNotional: 7_000_000,
               notional: 7_000_000, threshold: 5_000_000, vanishedNotional: 7_000_000),
    ]
    var model = ready(restored: OrderFlowJournal(symbol: "ETHUSDT", step: 1, savedAtMs: 0, orders: local))
    let server = remote(side: .ask, price: 1_700.9, first: -60_000, end: -25_000, status: .filled, filled: 5_900_000)
    XCTAssertEqual(model.mergeHistory(page([server]), chartScale: 1, nowMs: 0), .merged)
    let at1700 = model.orders.filter { $0.bucket == 1_700 }
    XCTAssertEqual(at1700.count, 1)
    XCTAssertEqual(at1700.first?.status, .filled)
    XCTAssertEqual(at1700.first?.firstSeenMs, -60_000)
    XCTAssertEqual(at1700.first?.endMs, -25_000)
    XCTAssertEqual(model.orders.filter { $0.bucket == 1_800 }.count, 1, "只有本机有的留着")
    XCTAssertTrue(model.journalDirty)
  }

  /// 首次名义不到本机门槛的丢掉（用户把门槛调高了）；本机没门槛的产品整类丢掉。
  func testBelowTheLocalThresholdIsDropped() {
    var raised = thresholds
    raised.usdtPerp = 8_000_000
    raised.coinPerp = nil
    var model = ready(thresholds: raised)
    let orders = [
      remote(price: 1_500, first: -9_000, end: -1_000, status: .cancelled, initial: 6_000_000),
      remote(price: 1_501, first: -9_000, end: -1_000, status: .cancelled, initial: 9_000_000),
      remote("okx:coinPerp:ETH-USD-SWAP", product: .coinPerp, price: 1_502, first: -9_000, end: -1_000,
             status: .cancelled, initial: 9_000_000),
      remote(spotID, product: .spot, price: 1_503, first: -9_000, end: -1_000, status: .cancelled, initial: 1_200_000),
    ]
    model.mergeHistory(page(orders), chartScale: 1, nowMs: 0)
    XCTAssertEqual(model.orders.map(\.bucket).sorted(), [1_501, 1_503])
    XCTAssertEqual(model.orders.first { $0.bucket == 1_501 }?.threshold, 8_000_000, "门槛换成本机此刻的")
  }

  /// 服务端说还挂着、本机也挂着：接着本机跟——出现时刻、首次名义取服务端的，成交取两边大的，
  /// 此刻名义还是本机簿上的；成交照常记进这条，不多冒一条。价格按缩放换算后重新分桶。
  func testServerLiveContinuesLocalTracking() {
    var model = ready()
    _ = model.evaluate(nowMs: 0)
    _ = model.evaluate(nowMs: 500)
    XCTAssertEqual(model.orders.count, 1)
    // 服务端的价是每个币的价、步长 0.001：1000 倍缩放的品种换算过来正好落在 1590 那一桶。
    let server = remote(price: 1.5905, first: -600_000, initial: 6_000_000, filled: 3_000_000)
    XCTAssertEqual(model.mergeHistory(page([server], step: 0.001), chartScale: 1_000, nowMs: 1_000), .merged)
    XCTAssertEqual(model.orders.count, 1)
    let merged = model.orders[0]
    XCTAssertTrue(merged.isLive)
    XCTAssertEqual(merged.firstSeenMs, -600_000)
    XCTAssertEqual(merged.initialNotional, 6_000_000)
    XCTAssertEqual(merged.filledNotional, 3_000_000)
    XCTAssertEqual(merged.notional, 19_080_000, accuracy: 1)
    _ = model.ingest(okx.id, .trade(OrderFlowTrade(price: 1_590, quantity: 100, hitSide: .bid, timeMs: 1_100)), nowMs: 1_100)
    let frame = model.evaluate(nowMs: 1_500)
    XCTAssertEqual(frame.orders.count, 1, "不因为出现时刻换了又冒出一条")
    XCTAssertEqual(frame.orders[0].filledNotional, 3_159_000, accuracy: 1)
    // 本机簿上那一桶撤了：本机照常判结束。
    shrinkWall(&model)
    _ = model.evaluate(nowMs: 2_000)
    let ended = model.evaluate(nowMs: 2_500).orders[0]
    XCTAssertEqual(ended.status, .cancelled)
    XCTAssertEqual(ended.endMs, 2_000)
    XCTAssertEqual(ended.firstSeenMs, -600_000)
  }

  /// 本机已经亲眼看到结束（已撤销）的，服务端还挂着（还没刷到库）：留本机的结束，只补出现时刻与成交；
  /// 服务端之后说结束了，再以它为准。
  func testLocallyEndedWinsOverAStaleServerLiveUntilTheServerEndsIt() {
    var model = ready()
    _ = model.evaluate(nowMs: 0)
    _ = model.evaluate(nowMs: 500)
    shrinkWall(&model)
    _ = model.evaluate(nowMs: 1_000)
    _ = model.evaluate(nowMs: 1_500)
    XCTAssertEqual(model.orders.first?.status, .cancelled)
    model.mergeHistory(page([remote(first: -600_000, filled: 1_000_000)]), chartScale: 1, nowMs: 2_000)
    XCTAssertEqual(model.orders.count, 1)
    XCTAssertEqual(model.orders[0].status, .cancelled, "不回到挂着")
    XCTAssertEqual(model.orders[0].endMs, 1_000)
    XCTAssertEqual(model.orders[0].firstSeenMs, -600_000)
    XCTAssertEqual(model.orders[0].filledNotional, 1_000_000)
    _ = model.evaluate(nowMs: 2_500)
    XCTAssertEqual(model.orders.count, 1, "那一桶没过门槛，不冒新单")
    model.mergeHistory(page([remote(first: -600_000, end: 1_200, status: .filled, filled: 5_900_000)]),
                       chartScale: 1, nowMs: 3_000)
    XCTAssertEqual(model.orders.count, 1)
    XCTAssertEqual(model.orders[0].status, .filled)
    XCTAssertEqual(model.orders[0].endMs, 1_200)
  }

  /// 本机没这本簿（或簿没就绪）的挂单靠服务端续命：服务端每分钟说一次「还挂着」就一直挂着；
  /// 断了 3 分钟按最后一次听到的时刻失联结束；服务端再说还挂着，以服务端为准。
  func testRemoteOnlyLiveLivesOnServerConfirmation() {
    var model = ready()
    _ = model.evaluate(nowMs: 0)
    model.mergeHistory(page([remote(spotID, product: .spot, price: 1_500, first: -1_000, initial: 2_000_000)]),
                       chartScale: 1, nowMs: 0)
    XCTAssertEqual(model.evaluate(nowMs: 150_000).orders.first { $0.venueID == spotID }?.status, .live,
                   "本机没这本簿，超过 staleMs 也不结束——服务端刚说过还挂着")
    let lost = model.evaluate(nowMs: 200_000).orders.first { $0.venueID == spotID }
    XCTAssertEqual(lost?.status, .lost)
    XCTAssertEqual(lost?.endMs, 0)
    model.mergeHistory(page([remote(spotID, product: .spot, price: 1_500, first: -1_000, initial: 2_000_000)]),
                       chartScale: 1, nowMs: 210_000)
    let back = model.orders.filter { $0.venueID == spotID }
    XCTAssertEqual(back.count, 1)
    XCTAssertEqual(back.first?.status, .live, "失联结束的以服务端为准")
    XCTAssertEqual(model.evaluate(nowMs: 300_000).orders.first { $0.venueID == spotID }?.status, .live)
  }

  /// 冷启动：日志里挂着的单缺席很久（本来第一次评估就按存盘时刻失联结束），但服务端刚说它还挂着——不结束。
  func testRestoredLiveOrderConfirmedByTheServerSurvivesTheFirstEvaluation() throws {
    var first = ready()
    _ = first.evaluate(nowMs: 0)
    _ = first.evaluate(nowMs: 500)
    let journal = try XCTUnwrap(first.journal(nowMs: 800))
    var later = ready(restored: journal)
    later.mergeHistory(page([remote(first: -600_000)]), chartScale: 1, nowMs: 3_600_000)
    let frame = later.evaluate(nowMs: 3_600_000)
    XCTAssertEqual(frame.orders.count, 1)
    XCTAssertTrue(frame.orders[0].isLive)
    XCTAssertEqual(frame.orders[0].firstSeenMs, -600_000)
  }

  /// 服务端说结束了、本机还挂着：以服务端为准；本机簿上那一桶还过门槛，按正常确认重新出现一条。
  func testServerEndedReplacesALocalLive() {
    var model = ready()
    _ = model.evaluate(nowMs: 0)
    _ = model.evaluate(nowMs: 500)
    model.mergeHistory(page([remote(first: -600_000, end: 400, status: .cancelled)]), chartScale: 1, nowMs: 1_000)
    XCTAssertEqual(model.orders.map(\.status), [.cancelled])
    _ = model.evaluate(nowMs: 1_000)
    let frame = model.evaluate(nowMs: 1_500)
    XCTAssertEqual(frame.orders.map(\.status), [.cancelled, .live])
    XCTAssertEqual(frame.orders.last?.firstSeenMs, 1_000)
  }

  /// 步长对不上（用户改过步长）整页不用；自己的步长还不知道先不并。
  func testStepMismatchAndUnknownStep() {
    var model = ready()
    XCTAssertEqual(model.mergeHistory(page([remote(first: -1, end: 0, status: .cancelled)], step: 2), chartScale: 1,
                                      nowMs: 0), .incompatible)
    XCTAssertEqual(model.mergeHistory(page([remote(first: -1, end: 0, status: .cancelled)], step: nil), chartScale: 1,
                                      nowMs: 0), .incompatible)
    XCTAssertEqual(model.orders, [])
    var noStep = thresholds
    noStep.step = nil
    var pending = OrderFlowModel(symbol: "ETHUSDT", thresholds: noStep)
    XCTAssertEqual(pending.mergeHistory(page([remote(first: -1, end: 0, status: .cancelled)]), chartScale: 1,
                                        nowMs: 0), .pending)
  }

  /// 同一页取两次（增量往前退了 5 分钟、和上一页重叠）：不重复。
  func testRepeatedPagesDoNotDuplicate() {
    var model = ready()
    let orders = (0..<50).map { remote(price: Double(1_000 + $0), first: -9_000, end: -1_000, status: .cancelled) }
      + [remote(spotID, product: .spot, price: 1_200, first: -5_000, initial: 2_000_000)]
    model.mergeHistory(page(orders), chartScale: 1, nowMs: 0)
    model.mergeHistory(page(orders), chartScale: 1, nowMs: 60_000)
    XCTAssertEqual(model.orders.count, 51)
    XCTAssertEqual(model.orders.filter(\.isLive).count, 1)
  }
}
