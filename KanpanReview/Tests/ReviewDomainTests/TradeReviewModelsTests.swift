import XCTest
import KanpanCore
import ReviewDomain

/// 交易复盘的客户端形状：服务端回写的结果怎么读、观点 ↔ 交易怎么配、上传怎么切批。
final class TradeReviewModelsTests: XCTestCase {
  static func round(_ n: Int, symbol: String = "BTCUSDT", opened: Int64, closed: Int64?, updated: Int64 = 1) -> TradeRound {
    TradeRound(id: String(format: "00000000-0000-8000-8000-%012d", n), venue: "binance", market: "usd_m",
               symbol: symbol, accountTag: "primary", positionSide: .both, direction: .long,
               status: closed == nil ? .open : .closed, quoteAsset: "USDT", openedAt: opened, closedAt: closed,
               holdingMs: closed.map { $0 - opened }, openAvgPrice: 100, closeAvgPrice: closed == nil ? nil : 110,
               openedQty: 1, closedQty: closed == nil ? 0 : 1, maxQty: 1, peakNotional: 100, leverage: 10,
               realizedPnl: 10, commission: 1, commissionByAsset: ["USDT": 1], commissionUnpriced: false,
               funding: 0, netPnl: 9, fills: [], updatedAt: updated)
  }

  // MARK: 结果回写

  func testResultParsesStringsAndTellsPendingFromUnavailable() throws {
    let json = """
    {"version":1,"computedAt":1790000000000,
     "excursion":{"maxFavorable":"40","maxFavorablePct":"0.190476","maxFavorableAt":1790000120000,
                  "maxAdverse":"-5","maxAdversePct":"-0.05","maxAdverseAt":null,"rewardRisk":"1.8"},
     "after":{"h1":{"at":1790003600000,"price":"101.5","changePct":"0.012"},"h4":null,"h24":null},
     "chart":{"interval":"5m","start":1789996400000,"end":1790007200000},
     "unavailable":{"h24":"klines_missing"}}
    """
    let result = try JSONDecoder().decode(TradeResult.self, from: Data(json.utf8))
    let excursion = try XCTUnwrap(result.excursionCell.value)
    XCTAssertEqual(excursion.maxFavorable, 40)
    XCTAssertEqual(excursion.maxAdverse, -5)
    XCTAssertEqual(excursion.maxFavorablePct, Decimal(string: "0.190476"))
    XCTAssertNil(excursion.maxAdverseAt)
    XCTAssertEqual(excursion.rewardRisk, Decimal(string: "1.8"))
    XCTAssertEqual(result.afterCell("h1").value?.price, Decimal(string: "101.5"))
    XCTAssertEqual(result.afterCell("h1").value?.changePct, Decimal(string: "0.012"))
    // null 且不在 unavailable 里 = 还没到点；在 unavailable 里 = 拿不到。
    XCTAssertEqual(result.afterCell("h4"), .pending)
    XCTAssertEqual(result.afterCell("h24"), .unavailable("klines_missing"))
    XCTAssertEqual(result.chart, TradeChartSpec(interval: "5m", start: 1_789_996_400_000, end: 1_790_007_200_000))
    // 本地缓存来回一趟不丢东西。
    let again = try JSONDecoder().decode(TradeResult.self, from: JSONEncoder().encode(result))
    XCTAssertEqual(again, result)
  }

  func testRecordDecodesServerShapeWithoutResult() throws {
    let round = Self.round(1, opened: 1_000, closed: nil)
    let body: [String: Any] = [
      "kind": "trade", "id": round.id.uppercased(), "revision": 1, "submitted": 5, "updated": 5, "voided": false,
      "round": try JSONSerialization.jsonObject(with: JSONEncoder().encode(round)),
      "result": NSNull(), "note": NSNull(), "groupPending": false,
    ]
    let record = try JSONDecoder().decode(TradeRecord.self, from: JSONSerialization.data(withJSONObject: body))
    XCTAssertEqual(record.id, round.id, "id 一律小写，和回合 id 同一个键")
    XCTAssertNil(record.result)
    XCTAssertNil(record.note)
    XCTAssertTrue(record.round.isOpen)
  }

  func testExcursionAcceptsNumbersAndNullRewardRisk() throws {
    let json = #"{"maxFavorable":12.5,"maxFavorablePct":"0.1","maxAdverse":"0","maxAdversePct":"0","rewardRisk":null}"#
    let value = try JSONDecoder().decode(TradeExcursion.self, from: Data(json.utf8))
    XCTAssertEqual(value.maxFavorable, Decimal(12.5))
    XCTAssertNil(value.rewardRisk)
  }

  // MARK: 上传切批

  func testPendingSkipsUploadedAndRejectedVersionsOldestFirst() {
    let a = Self.round(1, opened: 3_000, closed: 4_000, updated: 10)
    let b = Self.round(2, opened: 1_000, closed: 2_000, updated: 10)
    let c = Self.round(3, opened: 2_000, closed: nil, updated: 11)
    let d = Self.round(4, opened: 500, closed: 900, updated: 7)
    let todo = TradeUploadPlan.pending([a, b, c, d], uploaded: [a.id: 10, c.id: 9], rejected: [d.id: 7])
    XCTAssertEqual(todo.map(\.id), [b.id, c.id], "传过这一版的不传、拒过这一版的不传、版本变了的重传，老的先传")
  }

  func testBatchesNeverExceedAHundred() {
    let rounds = (0..<250).map { Self.round($0, opened: Int64($0), closed: Int64($0) + 1) }
    let batches = TradeUploadPlan.batches(rounds)
    XCTAssertEqual(batches.map(\.count), [100, 100, 50])
    XCTAssertEqual(batches.flatMap { $0 }.map(\.id), rounds.map(\.id))
    XCTAssertEqual(TradeUploadPlan.batches([]).count, 0)
  }

  func testFingerprintChangesWithVersion() {
    let a = Self.round(1, opened: 0, closed: 1, updated: 1)
    var b = a; b.updatedAt = 2
    XCTAssertEqual(TradeUploadPlan.fingerprint([a]), TradeUploadPlan.fingerprint([a]))
    XCTAssertNotEqual(TradeUploadPlan.fingerprint([a]), TradeUploadPlan.fingerprint([b]))
  }

  // MARK: 观点 ↔ 交易

  private func view(_ symbol: String, created: Int64, expires: Int64, voided: Bool = false) -> ReviewRecord {
    var draft = ReviewDraft(range: ReviewRange(symbol: symbol, interval: "1h", start: created - 3_600_000, end: created, bars: 1),
                            reference: 100, high: 110, low: 90, now: created)
    draft.rule.expires = expires
    var record = ReviewRecord(draft: draft)
    record.voided = voided
    return record
  }

  func testMatchesSameSymbolWithOverlappingTime() {
    let hour: Int64 = 3_600_000
    let trade = Self.round(1, symbol: "BTCUSDT", opened: 10 * hour, closed: 12 * hour)
    let before = view("BTCUSDT", created: 8 * hour, expires: 11 * hour)       // 到期落在持仓里
    let inside = view("btcusdt", created: 11 * hour, expires: 30 * hour)      // 持仓中记下的
    let after = view("BTCUSDT", created: 13 * hour, expires: 20 * hour)       // 平仓以后
    let other = view("ETHUSDT", created: 11 * hour, expires: 20 * hour)       // 别的品种
    let dead = view("BTCUSDT", created: 11 * hour, expires: 20 * hour, voided: true)
    let views = TradeViewMatch.views(for: trade, in: [inside, after, before, other, dead], now: 40 * hour)
    XCTAssertEqual(views.map(\.id), [before.id, inside.id])
    XCTAssertEqual(TradeViewMatch.rounds(for: inside, in: [trade], now: 40 * hour).map(\.id), [trade.id])
    XCTAssertTrue(TradeViewMatch.rounds(for: after, in: [trade], now: 40 * hour).isEmpty)
    XCTAssertTrue(TradeViewMatch.rounds(for: dead, in: [trade], now: 40 * hour).isEmpty)
  }

  func testOpenTradeRunsToNow() {
    let hour: Int64 = 3_600_000
    let open = Self.round(1, opened: 10 * hour, closed: nil)
    let later = view("BTCUSDT", created: 30 * hour, expires: 40 * hour)
    XCTAssertEqual(TradeViewMatch.views(for: open, in: [later], now: 35 * hour).count, 1)
    XCTAssertEqual(TradeViewMatch.views(for: open, in: [later], now: 20 * hour).count, 0)
  }
}
