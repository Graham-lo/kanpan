import XCTest
@testable import KanpanCore

// 压测 · 截断快照的本地簿：覆盖范围以外「知道的价位」有上限，被拒收的远价不算知道。
//
// 币安 REST 快照只给 1000 档、OKX 只给 400 档，这类簿整条连接都处在「快照被截断」的状态；
// 原来覆盖范围以外凡是增量推过的价（含推成正数、含保留区间外被拒收的）都记进 `touched`、只有重新同步才清，
// 一条连接跑几天它随「出现过的不同价位」只涨不落，被拒收的远价还被 `knows` 当成「知道」。

final class OrderFlowTouchedBoundTests: XCTestCase {
  private func level(_ price: Double, _ quantity: Double) -> BookLevel { BookLevel(price: price, quantity: quantity) }

  /// 买 99…89.5、卖 101…110.5，各 20 档、每 0.5 一档，要的正好 20 档：两侧都算被截断。中间价 100。
  private func limitedBook() throws -> LocalBook {
    var book = LocalBook(sequenceModel: .strictIncrementing)
    book.retainBps = 2 * OrderFlowDefaults.scanRadiusBps
    let bids = (0..<20).map { level(99 - Double($0) / 2, 1) }
    let asks = (0..<20).map { level(101 + Double($0) / 2, 1) }
    try book.replaceFromStreamSnapshot(BookSnapshot(lastUpdateID: 1, requestedLevels: 20, bids: bids, asks: asks))
    _ = book.forEachLevel(withinBps: OrderFlowDefaults.scanRadiusBps) { _, _, _ in }
    return book
  }

  private func delta(_ id: Int64, bids: [BookLevel] = [], asks: [BookLevel] = []) -> BookDelta {
    BookDelta(firstUpdateID: id, finalUpdateID: id, previousFinalUpdateID: nil, bids: bids, asks: asks)
  }

  /// 五万条增量在 1…1000 里到处加档、删档（两侧最优价不动），每 250 条评估一次。
  /// 覆盖范围以外记下来的价位不超过保留区间里、覆盖范围以外的价位格数：买 80…89、卖 111…120，各 19 格。
  func testTouchedStaysWithinRetainBandGrid() throws {
    var book = try limitedBook()
    var seed: UInt64 = 0x2545_F491_4F6C_DD1D
    func next() -> UInt64 { seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407; return seed >> 33 }
    var maxTouched = 0
    for id in Int64(2)...50_001 {
      let isBid = next() % 2 == 0
      // 买只落在 98 以下、卖只落在 102 以上：两侧最优价（99 / 101）不动。
      let price = isBid ? Double(2 + next() % 193) / 2 : Double(204 + next() % 1_797) / 2
      let quantity = next() % 3 == 0 ? 0 : Double(1 + next() % 9)
      try book.apply(delta(id, bids: isBid ? [level(price, quantity)] : [], asks: isBid ? [] : [level(price, quantity)]))
      if id % 250 == 0 { _ = book.forEachLevel(withinBps: OrderFlowDefaults.scanRadiusBps) { _, _, _ in } }
      maxTouched = max(maxTouched, book.bids.touched.count + book.asks.touched.count)
    }
    XCTAssertLessThanOrEqual(maxTouched, 38, "覆盖范围以外知道的价位不随跑的时间长：至多保留区间里那 38 格")
    XCTAssertEqual(book.bestBid(), 99)
    XCTAssertEqual(book.bestAsk(), 101)
  }

  func testRejectedFarPriceIsUnknownButInBandDeleteIsKnown() throws {
    var book = try limitedBook()
    try book.apply(delta(2, bids: [level(10, 5), level(85, 0), level(84, 3)], asks: [level(500, 5), level(115, 0)]))
    XCTAssertEqual(book.quantity(at: 10, side: .bid), 0, "保留区间外的新买价不收")
    XCTAssertFalse(book.knows(.bid, price: 10), "没收下的远价仍是不知道，不能当成「知道、是 0」")
    XCTAssertFalse(book.knows(.ask, price: 500))
    XCTAssertTrue(book.knows(.bid, price: 85), "区间内推成 0 的：知道是空的")
    XCTAssertTrue(book.knows(.ask, price: 115))
    XCTAssertTrue(book.knows(.bid, price: 84), "区间内收下的：表里有")
    XCTAssertEqual(book.quantity(at: 84, side: .bid), 3)
    XCTAssertFalse(book.knows(.bid, price: 83), "从没推过的覆盖外价位：不知道")
    // 收下的又被推成 0：仍然知道（是空的）。
    try book.apply(delta(3, bids: [level(84, 0)]))
    XCTAssertTrue(book.knows(.bid, price: 84))
    XCTAssertEqual(book.bids.touched, [84, 85])
  }

  /// 中间价往上走，保留区间跟着挪；挪出去的那些「知道是空的」价位一起裁掉，回到不知道。
  func testTouchedIsPrunedWhenBandMoves() throws {
    var book = try limitedBook()
    try book.apply(delta(2, bids: [level(81, 0)]))
    XCTAssertTrue(book.knows(.bid, price: 81))
    // 卖 101…104.5 撤光、买 104 挂上：中间价 104.5，保留区间下沿 83.6。
    try book.apply(delta(3, bids: [level(104, 1)], asks: (0..<8).map { level(101 + Double($0) / 2, 0) }))
    _ = book.forEachLevel(withinBps: OrderFlowDefaults.scanRadiusBps) { _, _, _ in }
    XCTAssertEqual(book.bestBid(), 104)
    XCTAssertEqual(book.bestAsk(), 105)
    XCTAssertFalse(book.bids.touched.contains(81), "挪出保留区间的价位不再记")
    XCTAssertFalse(book.knows(.bid, price: 81))
  }
}
