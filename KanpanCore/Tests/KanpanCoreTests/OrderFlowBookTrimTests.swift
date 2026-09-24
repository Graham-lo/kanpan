import XCTest
@testable import KanpanCore

// 主力订单流 · 本地簿有上限（审查第 36 项）：只留中间价两侧 `retainBps` 以内的价位。

final class OrderFlowBookTrimTests: XCTestCase {
  private func level(_ price: Double, _ quantity: Double) -> BookLevel { BookLevel(price: price, quantity: quantity) }

  /// 买 1…99、卖 101…1000，每 0.5 一档：像 Coinbase level2 首帧那样的整本簿，中间价 100。
  private func wholeBook(_ last: Int64) -> BookSnapshot {
    let bids = stride(from: 99.0, through: 1, by: -0.5).map { level($0, 1) }
    let asks = stride(from: 101.0, through: 1_000, by: 0.5).map { level($0, 1) }
    return BookSnapshot(lastUpdateID: last, requestedLevels: 10_000, bids: bids, asks: asks)
  }

  private func book(retain: Double?) throws -> LocalBook {
    var book = LocalBook(sequenceModel: .strictIncrementing)
    book.retainBps = retain
    try book.replaceFromStreamSnapshot(wholeBook(1))
    return book
  }

  private func scan(_ book: inout LocalBook) -> [String] {
    var out: [String] = []
    book.forEachLevel(withinBps: OrderFlowDefaults.scanRadiusBps) { out.append("\($0.rawValue)|\($1)|\($2)") }
    return out.sorted()
  }

  func testWholeSnapshotIsTrimmedToRetainBand() throws {
    var trimmed = try book(retain: 2_000)
    // 保留 ±20%：买 80…99、卖 101…120，各 39 档。
    XCTAssertEqual(trimmed.levelCount, 78)
    XCTAssertEqual(trimmed.quantity(at: 50, side: .bid), 0)
    XCTAssertEqual(trimmed.quantity(at: 80, side: .bid), 1)
    XCTAssertEqual(trimmed.bestBid(), 99)
    XCTAssertEqual(trimmed.bestAsk(), 101)
    var whole = try book(retain: nil)
    XCTAssertEqual(whole.levelCount, 197 + 1_799)
    XCTAssertEqual(scan(&trimmed), scan(&whole), "扫描窗（±10%）里的价位一档不少")
  }

  func testFarNewLevelsAreNotTakenButDeletesStillApply() throws {
    var book = try book(retain: 2_000)
    _ = book.forEachLevel(withinBps: OrderFlowDefaults.scanRadiusBps) { _, _, _ in }
    try book.apply(BookDelta(firstUpdateID: 2, finalUpdateID: 2, previousFinalUpdateID: nil,
                             bids: [level(10, 5), level(85, 0)], asks: [level(500, 5), level(110, 7)]))
    XCTAssertEqual(book.quantity(at: 10, side: .bid), 0, "保留区间外的新买价不收")
    XCTAssertEqual(book.quantity(at: 500, side: .ask), 0, "保留区间外的新卖价不收")
    XCTAssertEqual(book.quantity(at: 85, side: .bid), 0, "区间内的删单照删")
    XCTAssertEqual(book.quantity(at: 110, side: .ask), 7)
  }

  /// 长跑：五万条增量在 1…1000 里到处加档、偶尔删档，每 250 条评估一次。表的大小始终不超过保留区间里的
  /// 档数；和不裁的那本逐拍比，扫描窗里看到的完全一样。
  func testLevelCountStaysBoundedAfterLongRun() throws {
    var trimmed = try book(retain: 2_000)
    var whole = try book(retain: nil)
    var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
    func next() -> UInt64 { seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407; return seed >> 33 }
    var maxCount = 0
    for id in Int64(2)...50_001 {
      // 买只落在 98 以下、卖只落在 102 以上：两侧最优价（99 / 101）不动，中间价一直是 100。
      let isBid = next() % 2 == 0
      let price = isBid ? Double(2 + next() % 193) / 2 : Double(204 + next() % 1_797) / 2
      let quantity = next() % 5 == 0 ? 0 : Double(1 + next() % 9)
      let delta = BookDelta(firstUpdateID: id, finalUpdateID: id, previousFinalUpdateID: nil,
                            bids: isBid ? [level(price, quantity)] : [], asks: isBid ? [] : [level(price, quantity)])
      try trimmed.apply(delta)
      try whole.apply(delta)
      if id % 250 == 0 {
        XCTAssertEqual(scan(&trimmed), scan(&whole))
        maxCount = max(maxCount, trimmed.levelCount)
      }
    }
    XCTAssertLessThanOrEqual(maxCount, 78, "价位数有上限：保留区间里至多 78 档")
    XCTAssertGreaterThan(whole.levelCount, 1_000, "不裁的那本一直在长（对照）")
    XCTAssertEqual(trimmed.bestBid(), 99)
    XCTAssertEqual(trimmed.bestAsk(), 101)
  }

  func testVenueBooksRetainTwiceTheScanRadius() {
    let venue = OrderFlowVenue(exchange: "coinbase", label: "Coinbase", product: .spot, instrument: "ETH-USD",
                               notional: .linear(multiplier: 1), sequenceModel: .strictIncrementing, snapshotInBand: true)
    XCTAssertEqual(VenueBook(venue: venue).book.retainBps, 2 * OrderFlowDefaults.scanRadiusBps)
  }
}
