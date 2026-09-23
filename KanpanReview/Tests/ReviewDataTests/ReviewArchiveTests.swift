import XCTest
import ReviewDomain
import ReviewData

// ============================================================ 存档这一层的四条底线
//
// 对应报告 B.5 客户端那张表里的 ReviewData 那一行：200 条已确认 + 待发的边界、
// 12 MiB 装满、501 个回放位置、以及「一份文件集同一个事务」。
//
// 这一层的判据只有一句：**云端只是同步通道，本地永远有完整缓存。** 所以
// 「还没推上去的」永远不许被裁掉，裁掉的只能是服务器上另有一份的那些。

final class ReviewArchiveTests: XCTestCase {

  private func makeDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  private func makeDraft(text: String = "") -> ReviewDraft {
    var value = ReviewDraft(range: ReviewRange(symbol: "BTCUSDT", interval: "1m", start: 0, end: 180_000, bars: 3),
                            reference: 100, high: 110, low: 90, now: 240_000)
    value.text = text
    return value
  }

  private func confirmed(text: String = "") -> ReviewRecord {
    var record = ReviewRecord(draft: makeDraft(text: text))
    record.serverId = record.id          // 服务器上另有一份，本地这份才可以裁。
    return record
  }

  // MARK: - 501 个回放位置：按「最久没看」淘汰，不是按 id 大小

  /// 从前是 `next.keys.sorted().first`——按 UUID 字符串挑第一个丢。那是「谁的 id 以 0
  /// 开头」，和这个人最近在看哪条毫无关系：他天天重温的那条只要 id 恰好小，就每次都
  /// 第一个被丢掉，而三个月没碰过的那条稳稳留着（审查 B-08）。
  ///
  /// 这条测试特意把**最新看过的那条摆成最小的 id**：按老写法它必死，按 LRU 它必活。
  @MainActor func testReplayPositionsAreEvictedByLeastRecentlyUsedNotById() throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReviewStore(directory: directory)
    let ids = (0..<501).map { _ in UUID() }.sorted { $0.uuidString < $1.uuidString }

    // 前 500 条：id 越小看得越新。
    for (index, id) in ids.prefix(500).enumerated() {
      try store.saveReplay(id, position: ReviewReplayPosition(cursor: Int64(index), speed: 1,
                                                              usedAt: Int64(1_000 + 500 - index)))
    }
    XCTAssertEqual(store.allReplay.count, 500)

    // 第 501 条：id 最大、刚刚看过。
    try store.saveReplay(ids[500], position: ReviewReplayPosition(cursor: 500, speed: 1, usedAt: 9_000))

    XCTAssertEqual(store.allReplay.count, 500, "上限就是 500 条，多一条就得丢一条")
    XCTAssertNotNil(store.savedReplay(ids[0]), "id 最小但刚看过的那条必须留着——老写法第一个丢的就是它")
    XCTAssertNotNil(store.savedReplay(ids[500]), "刚存进来的这条更不能被自己挤掉")
    XCTAssertNil(store.allReplay[ids[499].uuidString], "最久没看的那条（id 最大的那批里最旧的）才是该丢的")

    try store.flushReplay()
    let reopened = try ReviewStore(directory: directory)
    XCTAssertEqual(reopened.allReplay.count, 500)
    XCTAssertNotNil(reopened.savedReplay(ids[0]))
  }

  /// 「刚打开看过一眼」也算用过：`savedReplay` 会顺手记一笔时间，下一次淘汰就轮不到它。
  ///
  /// 打开一条旧记录重温、但一根都没往前推的时候，只会走到 `savedReplay`——
  /// 不在那儿记一笔，这个人最常回头看的那条反而是最先被丢的。
  @MainActor func testReadingAPositionCountsAsUsingIt() throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReviewStore(directory: directory)
    let ids = (0..<501).map { _ in UUID() }.sorted { $0.uuidString < $1.uuidString }
    for (index, id) in ids.prefix(500).enumerated() {
      try store.saveReplay(id, position: ReviewReplayPosition(cursor: Int64(index), speed: 1,
                                                              usedAt: Int64(1_000 + 500 - index)))
    }
    // 本来最该被丢的那条（最久没看），现在被打开看了一眼。
    XCTAssertNotNil(store.savedReplay(ids[499]))

    try store.saveReplay(ids[500], position: ReviewReplayPosition(cursor: 500, speed: 1, usedAt: 9_000))
    XCTAssertNotNil(store.allReplay[ids[499].uuidString], "刚看过的那条不该再被当成最久没看的")
    XCTAssertNil(store.allReplay[ids[498].uuidString], "轮到它了")
    XCTAssertEqual(store.allReplay.count, 500)
  }

  /// 老存档里的条目没有 `usedAt`，当成「上古」先丢——它们本来就是最久没动的那批。
  @MainActor func testLegacyPositionsWithoutATimestampGoFirst() throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReviewStore(directory: directory)
    let legacy = UUID()
    try store.saveReplay(legacy, position: ReviewReplayPosition(cursor: 1, speed: 1, usedAt: nil))
    // 写进去时补的时间戳是「现在」，为了摆出老存档的样子，直接把它抹掉重写一遍。
    var table = store.allReplay
    table[legacy.uuidString]?.usedAt = nil
    let replayURL = directory.appendingPathComponent("replay-positions.json")
    try JSONEncoder().encode(table).write(to: replayURL)

    let reopened = try ReviewStore(directory: directory)
    let restored = try XCTUnwrap(reopened.allReplay[legacy.uuidString], "老存档里没有 `usedAt` 这个键，不该被合成 `Decodable` 整条拒掉")
    XCTAssertNil(restored.usedAt)
    for index in 0..<500 {
      try reopened.saveReplay(UUID(), position: ReviewReplayPosition(cursor: Int64(index), speed: 1, usedAt: 9_000))
    }
    XCTAssertEqual(reopened.allReplay.count, 500)
    XCTAssertNil(reopened.allReplay[legacy.uuidString], "没有时间戳的那条最先走")
  }

  // MARK: - 200 条 / 12 MiB：裁的只能是服务器上另有一份的

  @MainActor func testTwoHundredConfirmedRecordsIsTheBoundary() throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReviewStore(directory: directory)
    store.cloudCache = true
    try store.transaction { $0.records = (0..<200).map { _ in confirmed() } }
    XCTAssertEqual(store.archive.records.count, 200, "正好 200 条，一条都不该丢")

    try store.transaction { $0.records.append(confirmed()) }
    XCTAssertEqual(store.archive.records.count, 200, "第 201 条把最旧的那条挤出缓存")
  }

  /// 待发的、还没推上去的，一条都不许裁——裁了就是「本地记录凭空消失」。
  @MainActor func testPendingAndOfflineRecordsSurviveTheCap() throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReviewStore(directory: directory)
    store.cloudCache = true
    let queued = confirmed(), offline = ReviewRecord(draft: makeDraft(text: "还没登录时记的"))
    try store.transaction { archive in
      archive.records = [queued, offline] + (0..<400).map { _ in confirmed() }
      archive.queue = [ReviewOperation(recordId: queued.id, kind: "reflection", body: Data())]
    }
    XCTAssertEqual(store.archive.records.count, 202, "200 条缓存 + 队列里那条 + 压根没上过云的那条")
    XCTAssertTrue(store.archive.records.contains { $0.id == queued.id })
    XCTAssertTrue(store.archive.records.contains { $0.id == offline.id })
  }

  /// 12 MiB 的预算先于 200 条触顶时，按字节数收手。
  @MainActor func testTwelveMebibyteBudgetStopsBeforeTheCount() throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReviewStore(directory: directory)
    store.cloudCache = true
    let fat = String(repeating: "看", count: 180_000)          // 一条半兆多。
    let size = try JSONEncoder().encode(confirmed(text: fat)).count
    let budget = 12 * 1024 * 1024
    let expected = budget / size
    XCTAssertLessThan(expected, 200, "这条测试要的是字节数先触顶，不是条数先触顶")

    let offline = ReviewRecord(draft: makeDraft(text: "没上过云"))
    try store.transaction { archive in
      archive.records = (0..<(expected + 20)).map { _ in confirmed(text: fat) } + [offline]
    }
    XCTAssertEqual(store.archive.records.count, expected + 1, "装得下几条就是几条，外加永远不裁的那条离线记录")
    XCTAssertTrue(store.archive.records.contains { $0.id == offline.id })
    let written = try Data(contentsOf: directory.appendingPathComponent("review-v1.json")).count
    XCTAssertLessThan(written, budget + size, "写下去的主档不该冲破预算（离线那条是额外留的，所以放一条的余量）")
  }

  // MARK: - 一份文件集，一个事务

  /// 记录和它那条待发操作要么一起在，要么一起不在——中间态意味着「本地有记录但永远
  /// 传不上去」或者「传上去了本地没有」。顺带把攒着的重温书签一起结掉。
  @MainActor func testTheRecordItsUploadAndTheBookmarkLandTogether() throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReviewStore(directory: directory)
    let draft = makeDraft(text: "圈完就断网了")
    let record = ReviewRecord(draft: draft)

    // 第一笔进度立刻落盘，第二笔走 2 秒节流、还挂在内存里。
    try store.saveReplay(record.id, position: ReviewReplayPosition(cursor: 60_000, speed: 1))
    try store.saveReplay(record.id, position: ReviewReplayPosition(cursor: 120_000, speed: 4))

    try store.transaction { archive in
      archive.records.append(record)
      archive.queue.append(ReviewOperation(recordId: record.id, kind: "create",
                                           body: try JSONEncoder().encode(draft)))
      archive.draft = nil
    }

    let reopened = try ReviewStore(directory: directory)
    XCTAssertEqual(reopened.archive.records.count, 1)
    XCTAssertEqual(reopened.archive.queue.count, 1, "记录在、它那条上传却不在，等于这条永远传不上去")
    XCTAssertEqual(reopened.archive.queue.first?.recordId, record.id)
    XCTAssertEqual(reopened.savedReplay(record.id)?.cursor, 120_000, "攒着的书签被这次落盘顺手带走了")
    XCTAssertEqual(reopened.savedReplay(record.id)?.speed, 4)
  }

  /// 事务中途抛了：盘上和内存里都不许留下半份。
  @MainActor func testAFailedTransactionLeavesNothingBehind() throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReviewStore(directory: directory)
    let record = ReviewRecord(draft: makeDraft())
    try store.transaction { $0.records = [record] }

    struct Boom: Error {}
    XCTAssertThrowsError(try store.transaction { archive in
      archive.records.append(ReviewRecord(draft: self.makeDraft(text: "半条")))
      throw Boom()
    })
    XCTAssertEqual(store.archive.records.count, 1, "内存里那份不能被改了一半的副本盖掉")
    let reopened = try ReviewStore(directory: directory)
    XCTAssertEqual(reopened.archive.records.count, 1)
    XCTAssertEqual(reopened.archive.records.first?.id, record.id)
  }

  // MARK: - 没人认领的图（审查 D4）

  /// 记录还在（含被裁前的、待发队列提到的、手上那条草稿）的图留着，别的 UUID.png 删掉；
  /// 不是「UUID.png」的文件一概不碰。
  @MainActor func testPruneShotsKeepsOnlyLiveEntries() throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReviewStore(directory: directory)
    let kept = ReviewRecord(draft: makeDraft(text: "留"))
    let queued = UUID()
    let draft = makeDraft(text: "草稿")
    try store.transaction { archive in
      archive.records = [kept]
      archive.queue = [ReviewOperation(recordId: queued, kind: "shot", body: Data())]
    }
    try store.saveDraft(draft)
    let orphan = UUID()
    for id in [kept.id, queued, draft.id, orphan] { try store.saveShot(Data([1, 2, 3]), for: id) }
    let shots = directory.appendingPathComponent("shots")
    let stray = shots.appendingPathComponent("not-a-shot.tmp")
    try Data([9]).write(to: stray)

    XCTAssertEqual(store.pruneShots(), 1, "只该删那一张没人认领的")
    XCTAssertTrue(store.hasShot(kept.id))
    XCTAssertTrue(store.hasShot(queued), "待发队列里还提着它，不能删")
    XCTAssertTrue(store.hasShot(draft.id), "手上那条草稿的图不能删")
    XCTAssertFalse(store.hasShot(orphan))
    XCTAssertTrue(FileManager.default.fileExists(atPath: stray.path), "不是 UUID.png 的文件不碰")
    XCTAssertEqual(store.pruneShots(), 0, "再扫一次没东西可删")
  }

  /// 记录被删掉（或被云端缓存裁掉）之后，它的图下一次扫就跟着走。
  @MainActor func testPruneShotsDropsTheShotOfARemovedRecord() throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReviewStore(directory: directory)
    let record = ReviewRecord(draft: makeDraft())
    try store.transaction { $0.records = [record] }
    try store.saveShot(Data([1]), for: record.id)
    XCTAssertEqual(store.pruneShots(), 0)
    try store.transaction { $0.records = [] }
    XCTAssertEqual(store.pruneShots(), 1)
    XCTAssertFalse(store.hasShot(record.id))
  }
}
