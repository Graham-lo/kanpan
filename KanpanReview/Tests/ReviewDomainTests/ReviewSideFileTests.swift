import XCTest
import ReviewDomain
import ReviewData

// ============================================================ 复盘的两份侧文件
//
// 复盘落三个文件：主档 `review-v1.json`、草稿 `draft-v1.json`、重温进度
// `replay-positions.json`。后两份是**侧文件**，以前只有主档被当回事：
//
// 1. 一次性迁移（`AppAccountBridge.migrateLegacy`）只搬主档，草稿和进度留在老目录里；
// 2. 游客转正式账号时草稿只被并进**主档**，而下次 `init` 又拿 `draft-v1.json` 去盖
//    `archive.draft`，那份草稿就没了；进度压根没并；
// 3. 三份里任何一份解不动，`init` 整个抛——进度是个书签、草稿是一条记录，
//    坏了不该让整个复盘打不开；只有主档坏了才该拒绝。
//
// 这一组守的就是这三条。

final class ReviewSideFileTests: XCTestCase {
  private func makeDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  private func makeDraft(_ text: String = "") -> ReviewDraft {
    var value = ReviewDraft(range: ReviewRange(symbol: "BTCUSDT", interval: "1m", start: 0, end: 180_000, bars: 3),
                            reference: 100, high: 110, low: 90, now: 240_000)
    value.text = text
    return value
  }

  // ---------------------------------------------------------------- 转正式账号

  /// 游客写了一半的那条草稿，登录之后还在。
  ///
  /// 以前是把它塞进主档的 `archive.draft` 就算完，而 `ReviewStore.init` 末尾会拿
  /// `draft-v1.json` 的内容**覆盖** `archive.draft`——账号目录里那份侧文件写着
  /// 「现在没有草稿」（上一条草稿提交时 `saveDraft(nil)` 留下的），于是下次冷启动
  /// 刚并过来的草稿当场被抹掉。
  @MainActor func testGuestDraftSurvivesAccountClaimAndRelaunch() throws {
    let account = makeDirectory(), guest = makeDirectory()
    defer { try? FileManager.default.removeItem(at: account); try? FileManager.default.removeItem(at: guest) }
    // 账号这边：记过一条，草稿提交完清空过（draft-v1.json 里写着 null）。
    let existing = try ReviewStore(directory: account)
    let committed = makeDraft("已经记完的")
    try existing.saveDraft(committed)
    try existing.transaction { $0.records.append(ReviewRecord(draft: committed)); $0.draft = nil }
    try existing.saveDraft(nil)
    // 游客这边：写了一半。
    let guestStore = try ReviewStore(directory: guest)
    let unfinished = makeDraft("还没写完")
    try guestStore.saveDraft(unfinished)

    // `AppAccountBridge.prepare` 的那一段。
    let next = try ReviewStore(directory: account)
    let source = try ReviewStore(directory: guest)
    try next.transaction { archive in
      for record in source.archive.records where !archive.records.contains(where: { $0.id == record.id }) {
        archive.records.append(record)
      }
    }
    try next.adoptSideFiles(from: source)

    let relaunched = try ReviewStore(directory: account)
    XCTAssertEqual(relaunched.archive.draft?.id, unfinished.id)
    XCTAssertEqual(relaunched.archive.draft?.text, "还没写完")
  }

  /// 游客看到哪一根了，转正式账号之后还停在那一根。以前这份进度压根没并过去。
  @MainActor func testGuestReplayProgressIsAdopted() throws {
    let account = makeDirectory(), guest = makeDirectory()
    defer { try? FileManager.default.removeItem(at: account); try? FileManager.default.removeItem(at: guest) }
    let mine = UUID(), theirs = UUID()
    let existing = try ReviewStore(directory: account)
    try existing.saveReplay(mine, position: ReviewReplayPosition(cursor: 900_000, speed: 2))
    try existing.flushReplay()
    let guestStore = try ReviewStore(directory: guest)
    try guestStore.saveReplay(theirs, position: ReviewReplayPosition(cursor: 180_000, speed: 4))
    try guestStore.flushReplay()

    let next = try ReviewStore(directory: account)
    try next.adoptSideFiles(from: try ReviewStore(directory: guest))

    let relaunched = try ReviewStore(directory: account)
    XCTAssertEqual(relaunched.savedReplay(theirs)?.cursor, 180_000)
    XCTAssertEqual(relaunched.savedReplay(theirs)?.speed, 4)
    // 自己那一条更晚，不许被访客那份盖掉。
    XCTAssertEqual(relaunched.savedReplay(mine)?.cursor, 900_000)
  }

  // ---------------------------------------------------------------- 三份文件各自坏掉

  /// 进度是个书签。它坏了只该丢这个书签，不该让整个复盘打不开——
  /// `ReviewStore.init` 抛就意味着 `AppAccountBridge.prepare` 抛，整份档案都换不进来。
  @MainActor func testCorruptReplayFileDoesNotBlockTheArchive() throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReviewStore(directory: directory)
    let draft = makeDraft("记录还在")
    try store.transaction { $0.records.append(ReviewRecord(draft: draft)) }
    try Data("这不是进度".utf8).write(to: directory.appendingPathComponent("replay-positions.json"))

    let reopened = try ReviewStore(directory: directory)
    XCTAssertEqual(reopened.archive.records.count, 1)
    XCTAssertNil(reopened.savedReplay(draft.id))
    // 坏掉的原件留着，不静默抹掉。
    XCTAssertTrue(FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("replay-positions.json.backup").path))
  }

  /// 草稿坏了同理：丢的是那一条草稿，不是整个复盘。记录与待发队列一条都不能少。
  @MainActor func testCorruptDraftFileDoesNotBlockTheArchive() throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReviewStore(directory: directory)
    let draft = makeDraft("记录还在")
    try store.transaction {
      $0.records.append(ReviewRecord(draft: draft))
      $0.queue.append(ReviewOperation(recordId: draft.id, kind: "create", body: Data()))
    }
    try Data("这不是草稿".utf8).write(to: directory.appendingPathComponent("draft-v1.json"))

    let reopened = try ReviewStore(directory: directory)
    XCTAssertEqual(reopened.archive.records.count, 1)
    XCTAssertEqual(reopened.archive.queue.count, 1)
    XCTAssertTrue(FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("draft-v1.json.backup").path))
  }

  /// 主档坏了才该拒绝：那里面是用户全部的记录和还没推上去的队列，
  /// 拿一份空档接着跑等于把它们一起丢掉。
  @MainActor func testCorruptMainArchiveStillRefusesToOpen() throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReviewStore(directory: directory)
    try store.transaction { $0.records.append(ReviewRecord(draft: makeDraft())) }
    let main = directory.appendingPathComponent("review-v1.json"), damaged = Data("incomplete".utf8)
    try damaged.write(to: main)
    XCTAssertThrowsError(try ReviewStore(directory: directory))
    XCTAssertEqual(try Data(contentsOf: main), damaged)
  }
}
