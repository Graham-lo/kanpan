import XCTest
import ReviewDomain
import ReviewData

// ============================================================ 本地存储压测（几千条的量级）
//
// 全在进程里：临时目录 + `FakeReviewTransport`，不连任何服务器。断言只看结构——主档整份
// 写了几次、请求发了几条、重开之后盘上那份和内存逐条一致；耗时只打印，不断言。

final class ReviewStoreStressTests: XCTestCase {
  private func makeDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("review-stress-" + UUID().uuidString)
  }
  /// 一条像样的草稿：真机上每条都带着图表设置与画线快照，主档按条数线性长。
  private func draft(_ i: Int) -> ReviewDraft {
    var value = FakeReviewTransport.draft(UUID())
    value.created = Int64(1_000_000 + i)
    value.chartSettings = Data(repeating: UInt8(i % 251), count: 2048)
    value.drawingSnapshot = Data(repeating: UInt8(i % 13), count: 1024)
    return value
  }
  private func create(_ value: ReviewDraft) throws -> ReviewOperation {
    ReviewOperation(recordId: value.id, kind: "create", body: try JSONEncoder().encode(value))
  }
  private func edit(_ record: ReviewRecord, kind: String) throws -> ReviewOperation {
    ReviewOperation(recordId: record.id, kind: kind, body: try JSONSerialization.data(withJSONObject: ["expectedRevision": 0, "note": "x"]))
  }
  private func cloud(_ i: Int) -> ReviewRecord {
    var value = ReviewRecord(draft: draft(i)); value.serverId = value.id; value.revision = 1; return value
  }
  /// 盘上那份：另开一个 `ReviewStore` 读，不借内存里的任何东西。
  @MainActor private func onDisk(_ directory: URL) throws -> ReviewArchive { try ReviewStore(directory: directory).archive }
  @MainActor private func assertDiskMatchesMemory(_ store: ReviewStore, _ directory: URL, file: StaticString = #filePath, line: UInt = #line) throws {
    let disk = try onDisk(directory)
    XCTAssertEqual(disk.records, store.archive.records, "记录逐条一致", file: file, line: line)
    XCTAssertEqual(disk.queue.map(\.id), store.archive.queue.map(\.id), "队列一致", file: file, line: line)
    XCTAssertEqual(disk.queue.map(\.body), store.archive.queue.map(\.body), file: file, line: line)
    XCTAssertEqual(disk.queue.map(\.attempted), store.archive.queue.map(\.attempted), file: file, line: line)
    XCTAssertFalse(store.staged, "一轮收尾之后内存不许比盘新", file: file, line: line)
  }

  /// 离线攒了几百条再联网：一轮跑空队列，主档整份写的次数跟「要改写 body 的更新」走，
  /// 不再是每条两次（原来 300 条新建 + 5 条更新 = 611 次整份写，N² 级）。
  @MainActor func testDrainingABacklogWritesTheArchiveOncePerRebaseNotTwicePerOperation() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReviewStore(directory: directory)
    store.cloudCache = true
    store.stageInterval = 1e9   // 只数「必须落」的那几次
    let backlog = (0..<300).map(draft)
    let edited = (0..<5).map { cloud(10_000 + $0) }
    let ops = try backlog.map(create) + edited.map { try edit($0, kind: "reflection") }
    try store.transaction { $0.records = backlog.map(ReviewRecord.init(draft:)) + edited; $0.queue = ops }
    let server = FakeReviewTransport()
    let engine = ReviewSyncEngine(store: store, transport: server)
    let before = store.writes
    let started = Date()
    let completed = await engine.run()
    let elapsed = Date().timeIntervalSince(started)

    XCTAssertTrue(completed)
    let keys = await server.keys
    XCTAssertEqual(keys, ops.map(\.id), "按序、一条一发、键就是操作 id")
    XCTAssertTrue(store.archive.queue.isEmpty)
    XCTAssertEqual(store.writes - before, edited.count + 1, "5 次更新类发前落盘 + 收尾并第一页 1 次")
    try assertDiskMatchesMemory(store, directory)
    print("[review-stress] 跑空 \(ops.count) 条：主档整份写 \(store.writes - before) 次（原来 \(2 * ops.count + 1) 次），\(String(format: "%.2f", elapsed)) s")
  }

  /// 间隔调成 0：`stage` 每一笔都当场落，退化成原来的每条两次整份写——内容照样一致。
  @MainActor func testZeroIntervalDegradesToWritingEveryStep() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReviewStore(directory: directory)
    store.stageInterval = 0
    let backlog = (0..<20).map(draft)
    try store.transaction { $0.records = backlog.map(ReviewRecord.init(draft:)); $0.queue = try backlog.map(create) }
    let before = store.writes
    let completed = await ReviewSyncEngine(store: store, transport: FakeReviewTransport()).run()
    XCTAssertTrue(completed)
    XCTAssertEqual(store.writes - before, 2 * 20 + 1, "每条发前标记一次、摘队列一次，收尾并第一页一次")
    try assertDiskMatchesMemory(store, directory)
  }

  /// 半路断网：停下来的那一刻，已经发成功的那几条在盘上也摘掉了，最后一笔不丢。
  @MainActor func testTransientFailureMidQueueLeavesDiskEqualToMemory() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReviewStore(directory: directory)
    store.stageInterval = 1e9
    let backlog = (0..<60).map(draft)
    let ops = try backlog.map(create)
    try store.transaction { $0.records = backlog.map(ReviewRecord.init(draft:)); $0.queue = ops }
    let server = FakeReviewTransport()
    await server.fail(backlog[40].id, with: URLError(.notConnectedToInternet))
    let completed = await ReviewSyncEngine(store: store, transport: server).run()
    XCTAssertFalse(completed)
    XCTAssertEqual(store.archive.queue.map(\.id), Array(ops[40...]).map(\.id))
    XCTAssertEqual(store.archive.queue.first?.attempted, true)
    try assertDiskMatchesMemory(store, directory)
  }

  /// 撤销窗口里的作废把一轮挡住：挡住之前发成功的那些照样落盘。
  @MainActor func testHeldVoidStopStillFlushesWhatWasSent() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReviewStore(directory: directory)
    store.stageInterval = 1e9
    let backlog = (0..<30).map(draft)
    let voided = cloud(99)
    try store.transaction {
      $0.records = backlog.map(ReviewRecord.init(draft:)) + [voided]
      $0.queue = try backlog.map(create) + [try edit(voided, kind: "void")]
    }
    let engine = ReviewSyncEngine(store: store, transport: FakeReviewTransport())
    engine.isHeld = { $0.kind == "void" }
    let completed = await engine.run()
    XCTAssertFalse(completed)
    XCTAssertEqual(store.archive.queue.map(\.kind), ["void"])
    try assertDiskMatchesMemory(store, directory)
  }

  /// 一轮半路不算数了（换了账号）：不 flush——同一个目录可能已经被新开的档案接手。
  /// 没落下去的那几条下次开档还在队列里，原样重发：同一个幂等键、同一份 body。
  @MainActor func testStaleRunDoesNotFlushAndTheNextRunResendsTheSameKeys() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReviewStore(directory: directory)
    store.stageInterval = 1e9
    let backlog = (0..<30).map(draft)
    let ops = try backlog.map(create)
    try store.transaction { $0.records = backlog.map(ReviewRecord.init(draft:)); $0.queue = ops }
    let server = FakeReviewTransport()
    let engine = ReviewSyncEngine(store: store, transport: server)
    var changes = 0, stale = false
    engine.onChange = { changes += 1; if changes == 20 { stale = true } }
    engine.stillCurrent = { !stale }
    let completed = await engine.run()
    XCTAssertFalse(completed)
    let firstKeys = await server.keys
    XCTAssertFalse(firstKeys.isEmpty)
    XCTAssertTrue(store.staged, "这一轮的进度只在内存里")

    let disk = try onDisk(directory)
    XCTAssertEqual(disk.queue.map(\.id), ops.map(\.id), "盘上一条没摘")
    XCTAssertEqual(disk.queue.map(\.body), ops.map(\.body), "body 和入队时逐字节一样")

    let reopened = try ReviewStore(directory: directory)
    let again = ReviewSyncEngine(store: reopened, transport: server)
    let secondCompleted = await again.run()
    XCTAssertTrue(secondCompleted)
    let allKeys = await server.keys
    XCTAssertEqual(Array(allKeys.dropFirst(firstKeys.count)), ops.map(\.id), "重发的就是同一批键")
    XCTAssertTrue(reopened.archive.queue.isEmpty)
    try assertDiskMatchesMemory(reopened, directory)
  }
}
