import XCTest
import ReviewDomain
import ReviewData

final class ReviewStorageTests: XCTestCase {
  @MainActor func testSavedDraftAndReplayDoNotRewriteRecordQueue() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReviewStore(directory: directory)
    let draft = makeDraft()
    try store.transaction { archive in
      archive.records = [ReviewRecord(draft: draft)]
      archive.queue = [ReviewOperation(recordId: draft.id, kind: "create", body: try JSONEncoder().encode(draft))]
    }
    let main = directory.appendingPathComponent("review-v1.json")
    let before = try Data(contentsOf: main)
    var another = makeDraft(); another.text = "等收盘再看"
    try store.saveDraft(another)
    try store.saveReplay(draft.id, position: ReviewReplayPosition(cursor: 180_000, speed: 4))
    XCTAssertEqual(try Data(contentsOf: main), before)
    let reopened = try ReviewStore(directory: directory)
    XCTAssertEqual(reopened.archive.draft, another)
    XCTAssertEqual(reopened.archive.queue.count, 1)
    XCTAssertEqual(reopened.savedReplay(draft.id)?.cursor, 180_000)
    XCTAssertEqual(reopened.savedReplay(draft.id)?.speed, 4)
  }

  @MainActor func testCrashAfterRecordCommitDoesNotResurrectItsDraft() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReviewStore(directory: directory), draft = makeDraft()
    try store.saveDraft(draft)
    try store.transaction { archive in
      archive.records.append(ReviewRecord(draft: draft)); archive.draft = nil
      archive.queue.append(ReviewOperation(recordId: draft.id, kind: "create", body: try JSONEncoder().encode(draft)))
    }
    // Simulate termination before draft-v1.json was cleared.
    let reopened = try ReviewStore(directory: directory)
    XCTAssertNil(reopened.archive.draft)
    XCTAssertEqual(reopened.archive.records.count, 1)
    XCTAssertEqual(reopened.archive.queue.first?.recordId, draft.id)
  }

  @MainActor func testCloudCacheNeverEvictsUnsentRecords() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReviewStore(directory: directory); store.cloudCache = true
    let pending = makeDraft(), offline = makeDraft()
    try store.transaction { archive in
      archive.records = (0..<205).map { _ in
        var value = ReviewRecord(draft: makeDraft()); value.serverId = value.id; return value
      }
      var protected = ReviewRecord(draft: pending); protected.serverId = protected.id
      archive.records += [protected, ReviewRecord(draft: offline)]
      archive.queue.append(ReviewOperation(recordId: pending.id, kind: "reflection", body: Data()))
    }
    let reopened = try ReviewStore(directory: directory)
    XCTAssertEqual(reopened.archive.records.count, 202)
    XCTAssertTrue(reopened.archive.records.contains { $0.id == pending.id })
    XCTAssertTrue(reopened.archive.records.contains { $0.id == offline.id })
    XCTAssertEqual(reopened.archive.queue.count, 1)
  }

  @MainActor func testCorruptArchiveIsPreservedOnWrite() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReviewStore(directory: directory)
    let main = directory.appendingPathComponent("review-v1.json"), damaged = Data("incomplete".utf8)
    try damaged.write(to: main)
    XCTAssertThrowsError(try store.transaction { $0.lastTab = "records" })
    XCTAssertEqual(try Data(contentsOf: main), damaged)
  }

  private func makeDraft() -> ReviewDraft {
    ReviewDraft(range: ReviewRange(symbol: "BTCUSDT", interval: "1m", start: 0, end: 180_000, bars: 3),
                reference: 100, high: 110, low: 90, now: 240_000)
  }
}
