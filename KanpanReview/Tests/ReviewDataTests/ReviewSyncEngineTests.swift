import XCTest
import ReviewDomain
import ReviewData

// ============================================================ 同步引擎本身（第 25 项）
//
// 引擎搬进 `ReviewData` 之后，不再需要起一个 `ReviewFeature` 才能测它：真引擎对着一台
// 假服务器（`ReviewTransport` 的实现）跑，断言线上看得见的请求和存档最后的样子。
// 和 `KanpanAccount` 的 `SyncEngine` + `SyncTransport` 同一个测法。

/// 一台假服务器：按剧本一问一答，并把每次请求录下来。
actor FakeReviewTransport: ReviewTransport {
  enum Call: Equatable { case create(UUID), update(String, UUID, Int?), shot(UUID, Int), list(String?), detail(UUID) }
  private(set) var calls: [Call] = []
  private(set) var keys: [UUID] = []
  /// 按记录 id 排好的应答；没排的更新就按「版本 +1」回。
  var failures: [UUID: [any Error]] = [:]
  var page: [ReviewRecord] = []
  var revisions: [UUID: Int] = [:]

  func fail(_ id: UUID, with error: any Error) { failures[id, default: []].append(error) }
  func setPage(_ records: [ReviewRecord]) { page = records }

  private func pop(_ id: UUID) throws {
    if var list = failures[id], !list.isEmpty {
      let error = list.removeFirst(); failures[id] = list; throw error
    }
  }
  func create(_ operation: ReviewOperation) async throws -> ReviewRecord {
    calls.append(.create(operation.recordId)); keys.append(operation.id)
    try pop(operation.recordId)
    var value = ReviewRecord(draft: try JSONDecoder().decode(ReviewDraft.self, from: operation.body))
    value.serverId = value.id; value.revision = 1
    revisions[value.id] = 1
    return value
  }
  func update(_ operation: ReviewOperation) async throws -> ReviewRecord {
    let body = try JSONSerialization.jsonObject(with: operation.body) as? [String: Any]
    calls.append(.update(operation.kind, operation.recordId, body?["expectedRevision"] as? Int)); keys.append(operation.id)
    try pop(operation.recordId)
    var value = ReviewRecord(draft: Self.draft(operation.recordId))
    value.serverId = operation.recordId
    value.revision = ((body?["expectedRevision"] as? Int) ?? 0) + 1
    return value
  }
  func uploadShot(record: UUID, image: Data, key: UUID) async throws {
    calls.append(.shot(record, image.count)); keys.append(key)
    try pop(record)
  }
  func list(after: String?, query: String, todo: Bool, decided: Bool) async throws -> NativeListResponse {
    calls.append(.list(after))
    return NativeListResponse(records: page, next: nil)
  }
  func detail(_ id: UUID) async throws -> NativeRecordResponse {
    calls.append(.detail(id))
    return NativeRecordResponse(record: ReviewRecord(draft: Self.draft(id)))
  }
  static func draft(_ id: UUID) -> ReviewDraft {
    var value = ReviewDraft(range: ReviewRange(symbol: "BTCUSDT", interval: "1m", start: 0, end: 180_000, bars: 3),
                            reference: 100, high: 110, low: 90, now: 240_000)
    value.id = id
    return value
  }
}

final class ReviewSyncEngineTests: XCTestCase {
  private func makeStore() throws -> (ReviewStore, URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("review-engine-" + UUID().uuidString)
    return (try MainActor.assumeIsolated { try ReviewStore(directory: directory) }, directory)
  }
  private func draft(_ created: Int64 = 240_000) -> ReviewDraft {
    var value = FakeReviewTransport.draft(UUID()); value.created = created; return value
  }
  private func cloud(revision: Int) -> ReviewRecord {
    var value = ReviewRecord(draft: draft()); value.serverId = value.id; value.revision = revision; return value
  }
  private func edit(_ record: ReviewRecord, kind: String, expected: Int) throws -> ReviewOperation {
    ReviewOperation(recordId: record.id, kind: kind, body: try JSONSerialization.data(withJSONObject: ["expectedRevision": expected, "note": "x"]))
  }
  private func create(_ value: ReviewDraft) throws -> ReviewOperation {
    ReviewOperation(recordId: value.id, kind: "create", body: try JSONEncoder().encode(value))
  }

  /// 正常一轮：按序发、键就是操作 id、更新类发前改写版本、跑空后拉第一页并入。
  @MainActor func testRunSendsInOrderRebasesAndMergesTheFirstPage() async throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = FakeReviewTransport()
    let mine = cloud(revision: 3)
    let fresh = draft(300_000)
    let ops = [try create(fresh), try edit(mine, kind: "reflection", expected: 0), try edit(mine, kind: "void", expected: 0)]
    try store.transaction { $0.records = [ReviewRecord(draft: fresh), mine]; $0.queue = ops }
    let listed = cloud(revision: 1)
    await server.setPage([listed])

    let engine = ReviewSyncEngine(store: store, transport: server)
    var changes = 0
    engine.onChange = { changes += 1 }
    let completed = await engine.run()

    XCTAssertTrue(completed)
    let calls = await server.calls
    XCTAssertEqual(calls, [.create(fresh.id), .update("reflection", mine.id, 3), .update("void", mine.id, 4), .list(nil)])
    let keys = await server.keys
    XCTAssertEqual(keys, ops.map(\.id))
    XCTAssertTrue(store.archive.queue.isEmpty)
    XCTAssertEqual(Set(store.archive.records.map(\.id)), [fresh.id, mine.id, listed.id])
    XCTAssertEqual(store.archive.records.first { $0.id == mine.id }?.revision, 5)
    XCTAssertGreaterThan(changes, 0)
  }

  /// 409 摘成可重试冲突、422 摘成终局冲突，都不挡后面的；暂时失败停在队首、同键重发。
  @MainActor func testFailuresAreSortedIntoTheirThreeOutcomes() async throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = FakeReviewTransport()
    let conflicted = cloud(revision: 3), rejected = draft(), blocked = draft(200_000)
    try store.transaction {
      $0.records = [conflicted, ReviewRecord(draft: rejected), ReviewRecord(draft: blocked)]
      $0.queue = [try edit(conflicted, kind: "reflection", expected: 3), try create(rejected), try create(blocked)]
    }
    await server.fail(conflicted.id, with: ScorebookError.http(409, "record_revision_changed"))
    await server.fail(rejected.id, with: ScorebookError.http(422, "invalid_review_evidence"))
    await server.fail(blocked.id, with: URLError(.notConnectedToInternet))
    let engine = ReviewSyncEngine(store: store, transport: server)
    var notices: [String] = []
    engine.onNotice = { notices.append($0) }

    let completed = await engine.run()
    XCTAssertFalse(completed, "暂时失败的那一轮不算完成")
    let record = { (id: UUID) in store.archive.records.first { $0.id == id } }
    XCTAssertEqual(record(conflicted.id)?.conflict?.retryable, true)
    XCTAssertEqual(record(rejected.id)?.conflict?.retryable, false)
    XCTAssertNil(record(blocked.id)?.conflict)
    XCTAssertNotNil(record(blocked.id)?.syncError)
    XCTAssertEqual(store.archive.queue.map(\.recordId), [blocked.id])
    XCTAssertEqual(store.archive.queue.first?.attempted, true)
    XCTAssertEqual(notices.count, 3)
    let firstKey = await server.keys.last

    let again = await engine.run()
    XCTAssertTrue(again, "网回来了，同一条接着发")
    let keys = await server.keys
    XCTAssertEqual(keys.last, firstKey, "重发同一个幂等键")
    XCTAssertTrue(store.archive.queue.isEmpty)
  }

  /// 撤销窗口里的作废先不发；这一轮不算数了（换了账号）就一个字都不写。
  @MainActor func testHeldAndStaleRunsStopWithoutWriting() async throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = FakeReviewTransport()
    let mine = cloud(revision: 3)
    try store.transaction { $0.records = [mine]; $0.queue = [try edit(mine, kind: "void", expected: 3)] }

    let held = ReviewSyncEngine(store: store, transport: server)
    held.isHeld = { $0.kind == "void" }
    let heldRan = await held.run()
    XCTAssertFalse(heldRan)
    let heldCalls = await server.calls
    XCTAssertEqual(heldCalls, [])
    XCTAssertNotEqual(store.archive.queue.first?.attempted, true, "没发就不许标成发过——撤销还得摘得掉")

    let stale = ReviewSyncEngine(store: store, transport: server)
    stale.stillCurrent = { false }   // 这一轮起跑前账号就换了
    stale.isHeld = { _ in false }
    let staleRan = await stale.run()
    XCTAssertFalse(staleRan)
    let staleCalls = await server.calls
    XCTAssertEqual(staleCalls, [], "不算数的一轮不许再往外发")
    XCTAssertEqual(store.archive.queue.count, 1)
  }

  /// 发图那一条：字节在发的那一刻现读；读不到就摘掉，不重发、也不挡后面的。
  @MainActor func testShotBytesAreReadAtSendTime() async throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = FakeReviewTransport()
    let with = cloud(revision: 1), without = cloud(revision: 1)
    let bytes = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
    try store.saveShot(bytes, for: with.id)
    try store.transaction {
      $0.records = [with, without]
      $0.queue = [ReviewOperation(recordId: with.id, kind: "shot", body: Data()),
                  ReviewOperation(recordId: without.id, kind: "shot", body: Data())]
    }
    let engine = ReviewSyncEngine(store: store, transport: server)
    let completed = await engine.run()
    XCTAssertTrue(completed)
    let calls = await server.calls
    XCTAssertEqual(calls, [.shot(with.id, bytes.count), .list(nil)])
    XCTAssertTrue(store.archive.queue.isEmpty)
  }

  /// 拉回来的一页并进存档：还在队列里的不盖、只活在本机的冲突不抹、云端缓存最多 200 条。
  @MainActor func testMergeKeepsLocalOnlyStateAndCapsTheCloudCache() throws {
    var archive = ReviewArchive()
    var conflicted = cloud(revision: 2)
    conflicted.conflict = ReviewConflict(kind: "reflection", code: "", reason: "", at: 0, body: Data(), retryable: true)
    conflicted.reflection.note = "我写的"
    var queued = cloud(revision: 2)
    queued.draft.created = -1   // 比 250 条都旧：只靠「在队列里」才留得下
    archive.records = [conflicted, queued]
    archive.queue = [try edit(queued, kind: "group", expected: 2)]
    var remoteConflicted = conflicted; remoteConflicted.conflict = nil; remoteConflicted.reflection.note = ""; remoteConflicted.revision = 5
    var remoteQueued = queued; remoteQueued.revision = 9
    let crowd = (0..<250).map { i -> ReviewRecord in var r = cloud(revision: 1); r.draft.created = Int64(i); return r }
    ReviewSyncEngine.merge([remoteConflicted, remoteQueued] + crowd, into: &archive)

    let byID = Dictionary(uniqueKeysWithValues: archive.records.map { ($0.id, $0) })
    XCTAssertEqual(byID[conflicted.id]?.revision, 5)
    XCTAssertEqual(byID[conflicted.id]?.reflection.note, "我写的")
    XCTAssertNotNil(byID[conflicted.id]?.conflict)
    XCTAssertEqual(byID[queued.id]?.revision, 2, "还在队列里的不拿云端那份去盖")
    XCTAssertEqual(archive.records.count, ReviewSyncEngine.cloudCacheLimit + 1, "200 条最近的 + 1 条被队列护着的")
  }
}
