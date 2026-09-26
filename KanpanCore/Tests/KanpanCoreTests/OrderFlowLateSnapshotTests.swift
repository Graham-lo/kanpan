import XCTest
@testable import KanpanCore

// 压测 · 迟到的 REST 快照：簿已就绪后再到的快照（同一本重复拉的第二份、旧连接那一份）一律不理，
// 不能把就绪的簿整本盖回旧快照、打回「拉快照中」。

final class OrderFlowLateSnapshotTests: XCTestCase {
  private let binance = OrderFlowVenue(exchange: "binance", label: "币安", product: .usdtPerp, instrument: "ETHUSDT",
                                       notional: .linear(multiplier: 1), sequenceModel: .previousFinalOverlap,
                                       snapshotInBand: false)

  private func level(_ price: Double, _ quantity: Double) -> BookLevel { BookLevel(price: price, quantity: quantity) }

  private func snapshot(last: Int64, bidQuantity: Double = 150) -> BookSnapshot {
    BookSnapshot(lastUpdateID: last, requestedLevels: 1_000,
                 bids: (1...40).map { level(1_600 - Double($0), bidQuantity) },
                 asks: (1...40).map { level(1_600 + Double($0), 150) })
  }

  private func delta(_ first: Int64, _ final: Int64, previous: Int64, bids: [BookLevel] = []) -> DepthMessage {
    .delta(BookDelta(firstUpdateID: first, finalUpdateID: final, previousFinalUpdateID: previous, bids: bids, asks: []))
  }

  func testSnapshotArrivingAfterReadyIsIgnored() {
    var book = VenueBook(venue: binance)
    XCTAssertEqual(book.connectionOpened(), .fetchSnapshot)
    XCTAssertEqual(book.ingest(delta(95, 101, previous: 94), nowMs: 0), .none)
    XCTAssertEqual(book.applySnapshot(snapshot(last: 100), nowMs: 10), .none)
    XCTAssertTrue(book.isReady)
    XCTAssertEqual(book.ingest(delta(102, 110, previous: 101, bids: [level(1_590, 9_000)]), nowMs: 20), .none)
    let before = book.book

    // 同一本的第二份快照（更旧的、或内容不同的）到了：簿不动、仍就绪、不要求再拉。
    XCTAssertEqual(book.applySnapshot(snapshot(last: 90, bidQuantity: 1), nowMs: 30), .none)
    XCTAssertTrue(book.isReady, "就绪的簿不能被迟到的快照打回「拉快照中」")
    XCTAssertEqual(book.book.quantity(at: 1_590, side: .bid), 9_000, "增量改过的那一档还在，没被旧快照盖掉")
    XCTAssertEqual(book.book.quantity(at: 1_599, side: .bid), 150)
    XCTAssertEqual(book.book.lastUpdateID, before.lastUpdateID)
    XCTAssertEqual(book.book.levelCount, before.levelCount)

    // 接下来的增量照常接上。
    XCTAssertEqual(book.ingest(delta(111, 115, previous: 110, bids: [level(1_599, 1)]), nowMs: 40), .none)
    XCTAssertTrue(book.isReady)
    XCTAssertEqual(book.book.quantity(at: 1_599, side: .bid), 1)
  }

  /// 没就绪时快照照常用：断了序号要重拉，新快照到了照样接上（不能被这道闸挡住）。
  func testSnapshotStillBootstrapsAfterAGap() {
    var book = VenueBook(venue: binance)
    _ = book.connectionOpened()
    _ = book.ingest(delta(95, 101, previous: 94), nowMs: 0)
    _ = book.applySnapshot(snapshot(last: 100), nowMs: 0)
    XCTAssertEqual(book.ingest(delta(105, 106, previous: 104), nowMs: 1), .fetchSnapshot)
    XCTAssertFalse(book.isReady)
    XCTAssertEqual(book.applySnapshot(snapshot(last: 105), nowMs: 3), .none)
    XCTAssertTrue(book.isReady)
  }
}

// 压测 · 快照比增量流新（流落后 REST 几秒）：等增量追上来的这段时间不逐条整本重建。

final class OrderFlowWaitingForOverlapTests: XCTestCase {
  private let binance = OrderFlowVenue(exchange: "binance", label: "币安", product: .usdtPerp, instrument: "ETHUSDT",
                                       notional: .linear(multiplier: 1), sequenceModel: .previousFinalOverlap,
                                       snapshotInBand: false)

  private func level(_ price: Double, _ quantity: Double) -> BookLevel { BookLevel(price: price, quantity: quantity) }

  /// 币安 REST 那种 1000 档快照，最后序号 1000。
  private func bigSnapshot() -> BookSnapshot {
    BookSnapshot(lastUpdateID: 1_000, requestedLevels: 1_000,
                 bids: (1...1_000).map { level(1_600 - Double($0) / 100, 1) },
                 asks: (1...1_000).map { level(1_600 + Double($0) / 100, 1) })
  }

  func testLaggingDeltasDoNotRebuildTheBookEach() {
    var book = VenueBook(venue: binance)
    _ = book.connectionOpened()
    XCTAssertEqual(book.applySnapshot(bigSnapshot(), nowMs: 0), .none)
    XCTAssertFalse(book.isReady)
    XCTAssertEqual(book.bootstrapAttempts, 1)
    // 流落后：999 条增量都在快照之前。
    for id in Int64(1)...999 {
      XCTAssertEqual(book.ingest(.delta(BookDelta(firstUpdateID: id, finalUpdateID: id, previousFinalUpdateID: id - 1,
                                                  bids: [level(1_599, Double(id))], asks: [])), nowMs: id), .none)
    }
    XCTAssertFalse(book.isReady)
    XCTAssertEqual(book.bootstrapAttempts, 1, "够不着快照的增量不触发整本重建")
    // 追上来：这一条覆盖快照的最后序号，接上。
    XCTAssertEqual(book.ingest(.delta(BookDelta(firstUpdateID: 1_000, finalUpdateID: 1_001, previousFinalUpdateID: 999,
                                                bids: [level(1_599.5, 7)], asks: [])), nowMs: 1_000), .none)
    XCTAssertTrue(book.isReady)
    XCTAssertEqual(book.bootstrapAttempts, 2)
    XCTAssertEqual(book.book.quantity(at: 1_599.5, side: .bid), 7)
    XCTAssertEqual(book.book.quantity(at: 1_599, side: .bid), 1, "快照之前的增量不落进簿里")
    XCTAssertEqual(book.book.lastUpdateID, 1_001)
  }
}
