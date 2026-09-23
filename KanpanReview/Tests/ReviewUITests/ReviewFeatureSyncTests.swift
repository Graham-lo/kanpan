import XCTest
import Foundation
import ReviewDomain
import ReviewData
import KanpanAccount
@testable import ReviewUI

// ============================================================ 复盘本这一层的四条
//
// 对应报告 B.5 客户端那张表里 ReviewUI 模型的四行：
//
// 1. 拉过一次服务端列表之后断网再记一条 → 存档 / 队列 / 复盘本都要有它，翻页还不能重复；
// 2. 人停在「战绩」这一档时，普通的 `loadHistory` / `synchronize` 不许把他拨回「待办」；
// 3. 一条旧版本冲突 + 随后一条不相干的记录 → 不许全队列阻塞、不许丢人写的那段话、
//    更不许把 409 当成功；
// 4. 战绩首次就失败 / 已有战绩再失败 / 切账号 → 不许伪造一个 0%，也不许把上一个账号
//    的数字留在屏幕上。
//
// 网络一律走注进来的 `ScorebookClient.Transport`：不碰真网络，也不必起本地服务。

/// 一台按真实协议应答的假服务器。
///
/// 应答的形状照 `Backend/kanpan-api/src/native/review.rs`：外层 `{"data": …}`，
/// 详情 / 创建 / 更新是 `{record, groupPending, assessmentRevision, reflectionAssessmentRevision}`，
/// 列表是 `{records, next}`，战绩是 `{groups, proof:{compatible_groups:{…}}}`。
@MainActor final class FakeReviewServer {
  /// 服务器上现有的记录（按 `draft.id` 索引）。
  var records: [UUID: ReviewRecord] = [:]
  /// 第一页 / 第二页分别返回哪几条。
  var page0: [UUID] = []
  var page1: [UUID] = []
  var cursor: String?
  /// 还要拒几次复盘更新（409）。
  var reflectionRejections = 0
  /// 拒的时候抛什么。出厂是旧的 `ScorebookError`；生产上 transport 走账号通道，抛的是
  /// `AccountError.http`，那条用例把它换掉。
  var reflectionRejection: any Error = ScorebookError.http(409, "record_revision_changed")
  /// 创建接口要不要报错（模拟断网 / 服务端忙）。
  var createFailure: (any Error)?
  /// 战绩接口要不要报错。
  var statsFailure: (any Error)?
  /// 战绩响应整份（`groups` + `proof`）。
  var stats: [String: Any] = ["groups": [], "proof": [:]]
  /// 每次复盘更新用的幂等键，用来证明重发换了新键。
  private(set) var reflectionKeys: [UUID] = []
  /// 每次新建用的幂等键，用来证明「原样重发」真的没换键。
  private(set) var createKeys: [UUID] = []
  /// 最近一次复盘更新带上来的 `expectedRevision`。
  private(set) var reflectionExpected: Int?
  private(set) var paths: [String] = []
  /// 收到的那几张图（记录 id → 字节）。
  private(set) var shots: [UUID: Data] = [:]

  /// 为真时，拉列表的请求停在门口，直到测试放行（用来卡住「队列已清空、正在拉列表」那一段）。
  var holdList = false
  /// 有一次拉列表正停在门口。
  private(set) var listWaiting = false

  var transport: ScorebookClient.Transport {
    { [self] path, method, body, key in try await self.gated(path, method, body, key) }
  }

  func gated(_ path: String, _ method: String, _ body: Data?, _ key: UUID?) async throws -> Data {
    if method == "GET", path.split(separator: "?")[0] == "v1/native-review/records" {
      while holdList { listWaiting = true; try await Task.sleep(for: .milliseconds(5)) }
      listWaiting = false
    }
    return try respond(path, method, body, key)
  }

  func respond(_ path: String, _ method: String, _ body: Data?, _ key: UUID?) throws -> Data {
    paths.append(method + " " + path)
    if path.hasPrefix("v1/native-review/statistics") {
      if let statsFailure { throw statsFailure }
      return try wrap(stats)
    }
    if method == "POST", path == "v1/native-review/records" {
      createKeys.append(try XCTUnwrap(key))
      if let createFailure { throw createFailure }
      let draft = try JSONDecoder().decode(ReviewDraft.self, from: body ?? Data())
      var record = ReviewRecord(draft: draft)
      record.serverId = draft.id
      record.revision = 1
      record.submitted = draft.created
      records[draft.id] = record
      page0.append(draft.id)
      return try wrap(["record": try object(record), "assessmentRevision": 0])
    }
    if method == "POST", path.hasSuffix("/reflection") {
      let id = try identifier(path)
      struct Edit: Decodable { var expectedRevision: Int; var reflection: ReviewReflection; var publish: Bool }
      let edit = try JSONDecoder().decode(Edit.self, from: body ?? Data())
      reflectionKeys.append(try XCTUnwrap(key))
      reflectionExpected = edit.expectedRevision
      if reflectionRejections > 0 {
        reflectionRejections -= 1
        throw reflectionRejection
      }
      var record = try XCTUnwrap(records[id])
      guard record.revision == edit.expectedRevision else { throw ScorebookError.http(409, "record_revision_changed") }
      record.reflection = edit.reflection
      record.revision += 1
      records[id] = record
      return try wrap(["record": try object(record), "assessmentRevision": 2, "reflectionAssessmentRevision": 2])
    }
    if path.hasSuffix("/shot") {
      let id = try identifier(path)
      if method == "POST" {
        struct Shot: Decodable { var image: String }
        shots[id] = Data(base64Encoded: try JSONDecoder().decode(Shot.self, from: body ?? Data()).image)
        return try wrap(["ok": true])
      }
      guard let data = shots[id] else { throw ScorebookError.http(404, "not_found") }
      return try wrap(["image": data.base64EncodedString(), "mime": "image/png"])
    }
    if method == "GET", path.hasPrefix("v1/native-review/records") {
      if let id = try? identifier(path) {
        let record = try XCTUnwrap(records[id])
        return try wrap(["record": try object(record), "assessmentRevision": 2, "reflectionAssessmentRevision": 1])
      }
      let ids = path.contains("after=") ? page1 : page0
      let listed = try ids.map { try object(try XCTUnwrap(records[$0])) }
      return try wrap(["records": listed, "next": path.contains("after=") ? NSNull() : (cursor.map { $0 as Any } ?? NSNull())])
    }
    throw ScorebookError.http(404, "not_found")
  }

  private func identifier(_ path: String) throws -> UUID {
    let parts = path.split(separator: "?")[0].split(separator: "/")
    for part in parts.reversed() { if let id = UUID(uuidString: String(part)) { return id } }
    throw ScorebookError.http(404, "not_found")
  }
  private func object(_ record: ReviewRecord) throws -> Any {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(record))
  }
  private func wrap(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["data": value])
  }
}

final class ReviewFeatureSyncTests: XCTestCase {

  private func makeDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  /// 一条服务端一定收得下的草稿（`ReviewContract` 那一套全过）。
  private func validDraft(symbol: String = "BTCUSDT") -> ReviewDraft {
    let step: Int64 = 3_600_000
    let end = (ReviewClock.now / step) * step
    let range = ReviewRange(symbol: symbol, interval: "1h", start: end - step * 48, end: end, bars: 48)
    return ReviewDraft(range: range, reference: 100, high: 110, low: 90, now: ReviewClock.now)
  }

  @MainActor private func client(_ server: FakeReviewServer) -> ScorebookClient {
    ScorebookClient(connection: ReviewConnection(baseURL: URL(string: "https://example.invalid")!, account: "r5"),
                    transport: server.transport)
  }

  /// 等这一轮同步跑完。
  @MainActor private func settle(_ feature: ReviewFeature) async {
    for _ in 0..<600 {
      await Task.yield()
      if !feature.syncing { return }
      try? await Task.sleep(for: .milliseconds(5))
    }
    XCTFail("同步一直没结束")
  }

  // MARK: - B-03：服务端列表拉过一次之后，本地新记的那条不许从复盘本上消失

  @MainActor func testLocallyCreatedRecordStaysInTheBookAfterTheServerListLoads() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = FakeReviewServer()
    let feature = ReviewFeature(directory: directory)
    let store = try ReviewStore(directory: directory.appendingPathComponent("account"))
    feature.activate(store: store, client: client(server))

    // 登录后成功拉过一次列表（空的），`historyLoaded` 从此再也不会放回去。
    await feature.loadHistory()
    XCTAssertTrue(feature.bookRecords.isEmpty)

    // 然后断网，再记一条。
    feature.autoSync = false
    let draft = validDraft()
    feature.begin(draft)
    XCTAssertTrue(feature.saveRecord())

    XCTAssertEqual(feature.pendingUploads, 1, "它得在待发队列里")
    XCTAssertTrue(store.archive.records.contains { $0.id == draft.id }, "它得在存档里")
    XCTAssertEqual(feature.bookRecords.map(\.id), [draft.id], """
      刚记下的这条不在复盘本上（审查 B-03）。人明明看着它保存成功了，回头翻本子却找不到——
      在他眼里这就是「记录没了」。服务端这一页里没有它，是因为它还没传上去。
      """)
    XCTAssertNotNil(feature.record(draft.id), "点进去也得打得开")
  }

  /// 传上去之后服务端这一页里有了它，复盘本上也只能有一条——不能一条记录出现两行。
  @MainActor func testTheLocalCopyDoesNotDuplicateTheServerRow() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = FakeReviewServer()
    let feature = ReviewFeature(directory: directory)
    let store = try ReviewStore(directory: directory.appendingPathComponent("account"))
    feature.activate(store: store, client: client(server))
    await feature.loadHistory()

    let draft = validDraft()
    feature.begin(draft)
    XCTAssertTrue(feature.saveRecord())
    await settle(feature)

    await feature.loadHistory()
    XCTAssertEqual(feature.bookRecords.map(\.id), [draft.id], "服务端和本地是同一条，只能出现一次")
    XCTAssertEqual(feature.pendingUploads, 0)
  }

  // MARK: - §4.3：记一笔自带的那张图

  /// 记录一保存就把图存到账号目录里，并且跟着队列传上去；换台设备（本地没有）能再拉回来。
  @MainActor func testTheChartShotIsSavedLocallyAndUploaded() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = FakeReviewServer()
    let feature = ReviewFeature(directory: directory)
    let store = try ReviewStore(directory: directory.appendingPathComponent("account"))
    feature.activate(store: store, client: client(server))
    let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
    feature.captureShot = { bytes }

    let draft = validDraft()
    feature.begin(draft)
    XCTAssertTrue(feature.saveRecord())
    XCTAssertEqual(store.shot(draft.id), bytes, "图得先落在这个账号自己的目录里")
    XCTAssertEqual(feature.shot(draft.id), bytes)
    await settle(feature)

    XCTAssertEqual(server.shots[draft.id], bytes, "图得跟着队列传上去")
    XCTAssertEqual(feature.pendingUploads, 0, "传完队列要空，图那条不许把后面的堵住")

    // 换一台设备：本机没有这张图，详情页去服务端拉。
    let second = ReviewFeature(directory: makeDirectory())
    let secondStore = try ReviewStore(directory: directory.appendingPathComponent("other"))
    second.activate(store: secondStore, client: client(server))
    await second.loadHistory()
    XCTAssertNil(second.shot(draft.id))
    await second.loadShot(draft.id)
    XCTAssertEqual(second.shot(draft.id), bytes)
  }

  /// 没接渲染器（没截成图）时照样记得下这一笔，也不会凭空多一条上传。
  @MainActor func testARecordWithoutAShotStillSaves() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = FakeReviewServer()
    let feature = ReviewFeature(directory: directory)
    let store = try ReviewStore(directory: directory.appendingPathComponent("account"))
    feature.activate(store: store, client: client(server))
    feature.autoSync = false

    let draft = validDraft()
    feature.begin(draft)
    XCTAssertTrue(feature.saveRecord())
    XCTAssertNil(feature.shot(draft.id))
    XCTAssertEqual(feature.pendingUploads, 1, "只有新建那一条")
  }

  /// 无限滚动（P3.7）：滑到底接下一页，接在已有那几条后面，本地那条只补一次、不重复。
  @MainActor func testLoadingMoreAppendsTheNextPageOnce() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = FakeReviewServer()
    let old = ReviewRecord(draft: validDraft(symbol: "ETHUSDT"))
    var older = ReviewRecord(draft: validDraft(symbol: "SOLUSDT"))
    older.serverId = older.id
    var first = old; first.serverId = first.id
    server.records = [first.id: first, older.id: older]
    server.page0 = [first.id]; server.page1 = [older.id]; server.cursor = "p1"

    let feature = ReviewFeature(directory: directory)
    let store = try ReviewStore(directory: directory.appendingPathComponent("account"))
    feature.activate(store: store, client: client(server))
    feature.autoSync = false
    await feature.loadHistory()

    let draft = validDraft()
    feature.begin(draft)
    XCTAssertTrue(feature.saveRecord())
    XCTAssertEqual(Set(feature.bookRecords.map(\.id)), [first.id, draft.id], "第一页要把本地那条补进来")

    await feature.loadMoreHistory()
    let ids = feature.bookRecords.map(\.id)
    XCTAssertEqual(Set(ids), [first.id, draft.id, older.id], "第二页接在后面，第一页和本地那条都还在")
    XCTAssertEqual(ids.count, 3, "同一条不许出现两次")
    XCTAssertNil(feature.nextPage, "到底了")
    await feature.loadMoreHistory()
    XCTAssertEqual(feature.bookRecords.count, 3, "没有下一页时再滑到底什么都不做")
  }

  // MARK: - 人停在哪一档就停在哪一档

  @MainActor func testLoadingAndSyncingDoNotSendTheUserBackToTheTodoTab() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = FakeReviewServer()
    let feature = ReviewFeature(directory: directory)
    let store = try ReviewStore(directory: directory.appendingPathComponent("account"))
    feature.activate(store: store, client: client(server))
    XCTAssertEqual(feature.tab, "todo", "复盘本每次**打开**都落在待办（§2G2）")

    feature.tab = "all"
    await feature.loadHistory()
    feature.synchronize(manual: true)
    await settle(feature)
    XCTAssertEqual(feature.tab, "all", "拉一次列表、同步一轮，不该把人从他正看的那一档上拨走")
  }

  // MARK: - B-02：一条永远成功不了的上传，不许把整条队列锁死

  @MainActor func testOnePermanentConflictDoesNotBlockTheRestOfTheQueue() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = FakeReviewServer()

    // 这条记录别的设备上已经改到第 7 版了，本机还停在第 3 版。
    var mine = ReviewRecord(draft: validDraft(symbol: "ETHUSDT"))
    mine.serverId = mine.id; mine.revision = 3
    var theirs = mine; theirs.revision = 7
    server.records = [mine.id: theirs]; server.page0 = [mine.id]
    server.reflectionRejections = 1

    let feature = ReviewFeature(directory: directory)
    let store = try ReviewStore(directory: directory.appendingPathComponent("account"))
    try store.transaction { $0.records = [mine] }
    feature.activate(store: store, client: client(server))
    feature.autoSync = false

    feature.saveReflection(mine.id, note: "追高那一笔，等回踩再进", nextTime: "下次等确认", publish: true)
    let later = validDraft()
    feature.begin(later)
    XCTAssertTrue(feature.saveRecord())
    XCTAssertEqual(feature.pendingUploads, 2)

    feature.autoSync = true
    feature.synchronize(manual: true)
    await settle(feature)

    XCTAssertEqual(feature.pendingUploads, 0, """
      队列没跑空。一条永远成功不了的上传坐在队首，后面每一条新记录都跟着上不去——
      这就是审查 B-02 的现场：人以为记下了，其实一条都没传上去。
      """)
    let stuck = try XCTUnwrap(feature.record(mine.id))
    XCTAssertEqual(stuck.conflict?.kind, "reflection", "那条冲突要被摘下来，等人裁决")
    XCTAssertEqual(stuck.reflection.note, "追高那一笔，等回踩再进", "人写的那段话一个字都不能丢")
    XCTAssertTrue(stuck.needsAction, "复盘本上要看得见它需要处理")
    XCTAssertEqual(server.records[mine.id]?.reflection.note, "",
                   "服务端压根没收下这段话——本地就不许摆出一副「已经同步好了」的样子")

    let uploaded = try XCTUnwrap(feature.record(later.id))
    XCTAssertNotNil(uploaded.serverId, "后面那条不相干的记录必须传上去")
    XCTAssertTrue(server.paths.contains { $0 == "POST v1/native-review/records" })
  }

  /// 生产上的 transport 走账号通道，抛的是 `AccountError.http` 而不是 `ScorebookError`。
  /// 以前 `AccountError` 不遵循 `ReviewFailureStatus`，问不出状态码 → 一律 `.transient`，
  /// 一条 409 / 422 就原样坐在队首无限重发，后面的记录永远上不去（审查 2026-09-24 §0.2 #2）。
  @MainActor func testAccountErrorRejectionsDoNotBlockTheQueue() async throws {
    XCTAssertEqual(ReviewFailure.verdict(for: AccountError.http(409, "record_revision_changed")), .conflict)
    XCTAssertEqual(ReviewFailure.verdict(for: AccountError.http(422, "invalid_reflection")), .rejected)
    XCTAssertEqual(ReviewFailure.verdict(for: AccountError.http(503, "request_failed")), .transient)
    XCTAssertEqual(ReviewFailure.verdict(for: AccountError.sessionReplaced(.phone)), .transient, "被顶下线是等人重新登录，不是内容被拒")
    XCTAssertEqual(ReviewFailure.code(for: AccountError.http(422, "invalid_reflection")), "invalid_reflection")

    for (status, code) in [(409, "record_revision_changed"), (422, "invalid_reflection")] {
      let directory = makeDirectory()
      defer { try? FileManager.default.removeItem(at: directory) }
      let server = FakeReviewServer()
      var mine = ReviewRecord(draft: validDraft(symbol: "ETHUSDT"))
      mine.serverId = mine.id; mine.revision = 3
      server.records = [mine.id: mine]; server.page0 = [mine.id]
      server.reflectionRejections = 1
      server.reflectionRejection = AccountError.http(status, code)

      let feature = ReviewFeature(directory: directory)
      let store = try ReviewStore(directory: directory.appendingPathComponent("account"))
      try store.transaction { $0.records = [mine] }
      feature.activate(store: store, client: client(server))
      feature.autoSync = false
      feature.saveReflection(mine.id, note: "追高那一笔", nextTime: "", publish: true)
      let later = validDraft()
      feature.begin(later)
      XCTAssertTrue(feature.saveRecord())
      XCTAssertEqual(feature.pendingUploads, 2)

      feature.autoSync = true
      feature.synchronize(manual: true)
      await settle(feature)

      XCTAssertEqual(feature.pendingUploads, 0, "AccountError.http(\(status)) 让队列卡在了队首")
      XCTAssertEqual(server.reflectionKeys.count, 1, "\(status) 不该被当成网络抖动重发")
      let stuck = try XCTUnwrap(feature.record(mine.id))
      XCTAssertEqual(stuck.conflict?.kind, "reflection")
      XCTAssertEqual(stuck.conflict?.code, code)
      XCTAssertEqual(stuck.conflict?.retryable, status == 409, "409 可以重新基准再发，422 只能留在本机")
      XCTAssertEqual(stuck.reflection.note, "追高那一笔")
      XCTAssertNotNil(feature.record(later.id)?.serverId, "后面那条不相干的记录必须传上去")
    }
  }

  /// 人裁决「用我这份」：拿服务端最新版本做基准重发，而且必须是**一条新操作、新幂等键**。
  ///
  /// 同一个幂等键下改 body 是幂等重试的大忌——服务端记着那个键第一次的请求，
  /// 改了就是 `idempotency_mismatch`，这条从此彻底发不出去。
  @MainActor func testResolvingAConflictRebasesAndUsesAFreshIdempotencyKey() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = FakeReviewServer()
    var mine = ReviewRecord(draft: validDraft(symbol: "ETHUSDT"))
    mine.serverId = mine.id; mine.revision = 3
    var theirs = mine; theirs.revision = 7
    server.records = [mine.id: theirs]; server.page0 = [mine.id]
    server.reflectionRejections = 1

    let feature = ReviewFeature(directory: directory)
    let store = try ReviewStore(directory: directory.appendingPathComponent("account"))
    try store.transaction { $0.records = [mine] }
    feature.activate(store: store, client: client(server))
    feature.saveReflection(mine.id, note: "这一笔是追高", nextTime: "", publish: true)
    await settle(feature)
    XCTAssertEqual(server.reflectionExpected, 3)
    XCTAssertNotNil(feature.record(mine.id)?.conflict)

    await feature.resolveConflict(mine.id, keepLocal: true)
    await settle(feature)

    XCTAssertEqual(server.reflectionKeys.count, 2)
    XCTAssertNotEqual(server.reflectionKeys[0], server.reflectionKeys[1], """
      重发用的还是上一次那个幂等键。服务端记着那个键第一次的请求体，
      换了内容就是 `idempotency_mismatch`——这条从此再也发不出去。
      """)
    XCTAssertEqual(server.reflectionExpected, 7, "重发要以服务端最新那一版为基准")
    let settled = try XCTUnwrap(feature.record(mine.id))
    XCTAssertNil(settled.conflict, "裁决完这条冲突就该消失")
    XCTAssertEqual(settled.reflection.note, "这一笔是追高")
    XCTAssertEqual(feature.pendingUploads, 0)
  }

  /// 「用云端那份」：本地这条不再往上传，冲突清掉，权威版本拉回来。
  @MainActor func testKeepingTheRemoteVersionDropsTheLocalUpload() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = FakeReviewServer()
    var mine = ReviewRecord(draft: validDraft(symbol: "ETHUSDT"))
    mine.serverId = mine.id; mine.revision = 3
    var theirs = mine; theirs.revision = 7; theirs.reflection.note = "别人写的那一份"
    server.records = [mine.id: theirs]; server.page0 = [mine.id]
    server.reflectionRejections = 1

    let feature = ReviewFeature(directory: directory)
    let store = try ReviewStore(directory: directory.appendingPathComponent("account"))
    try store.transaction { $0.records = [mine] }
    feature.activate(store: store, client: client(server))
    feature.saveReflection(mine.id, note: "我这份", nextTime: "", publish: true)
    await settle(feature)

    await feature.resolveConflict(mine.id, keepLocal: false)
    let settled = try XCTUnwrap(feature.record(mine.id))
    XCTAssertNil(settled.conflict)
    XCTAssertEqual(settled.reflection.note, "别人写的那一份", "认了云端那份，就该显示云端那份")
    XCTAssertEqual(feature.pendingUploads, 0, "不再往上传")
    XCTAssertEqual(server.reflectionKeys.count, 1, "认云端就不该再发一次")
  }

  /// 网络不好是**另一回事**：这条要原样留在队首，连幂等键一起留着，下次一模一样地重发。
  @MainActor func testATransientFailureKeepsTheOperationAndItsKey() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = FakeReviewServer()
    server.createFailure = URLError(.notConnectedToInternet)

    let feature = ReviewFeature(directory: directory)
    let store = try ReviewStore(directory: directory.appendingPathComponent("account"))
    feature.activate(store: store, client: client(server))
    let draft = validDraft()
    feature.begin(draft)
    XCTAssertTrue(feature.saveRecord())
    await settle(feature)

    XCTAssertEqual(feature.pendingUploads, 1, "断网不是拒绝，这条要留着")
    XCTAssertNil(feature.record(draft.id)?.conflict, "断网不该被当成冲突摆给人裁决")
    XCTAssertNotNil(feature.record(draft.id)?.syncError)

    server.createFailure = nil
    feature.synchronize(manual: true)
    await settle(feature)
    XCTAssertEqual(feature.pendingUploads, 0, "网络回来就该自己传上去")
    XCTAssertNotNil(feature.record(draft.id)?.serverId)
    XCTAssertEqual(server.createKeys.count, 2)
    XCTAssertEqual(server.createKeys[0], server.createKeys[1], """
      重发换了幂等键。这条要是第一次其实已经到了服务端、只是回程断了，换键重发就会
      在云端多出一条一模一样的记录——幂等重试的前提是同一个键配同一份 body。
      """)
  }

  // MARK: - 战绩：不伪造、不越账号

  @MainActor func testStatisticsNeverFabricateAZeroPercent() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = FakeReviewServer()
    // 一笔一组：服务端在 `proof` 里标着「样本不足」，界面就不能拿 0/1 算出个 0% 摆上去。
    server.stats = [
      "groups": [["id": "sig-1", "title": "看多 · 收盘确认", "total": 1, "correct": 0]],
      "proof": ["compatible_groups": ["sig-1": ["numerator": 0, "denominator": 1,
                                                "verdict_status": "insufficient", "recheck": false]]],
    ]
    let feature = ReviewFeature(directory: directory)
    let store = try ReviewStore(directory: directory.appendingPathComponent("account"))
    feature.activate(store: store, client: client(server))

    await feature.loadStatistics()
    let group = try XCTUnwrap(feature.statistics.first)
    XCTAssertEqual(group.verdict, "insufficient")
    XCTAssertEqual(group.rateText, "样本不足", "一笔一组的 0% 不是战绩，是噪声")
  }

  @MainActor func testTheFirstStatisticsFailureShowsAnErrorNotAnEmptyScoreboard() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = FakeReviewServer()
    server.statsFailure = ScorebookError.http(503, "temporarily_unavailable")
    let feature = ReviewFeature(directory: directory)
    let store = try ReviewStore(directory: directory.appendingPathComponent("account"))
    feature.activate(store: store, client: client(server))

    await feature.loadStatistics()
    XCTAssertTrue(feature.statistics.isEmpty, "第一次就失败，不许拿空表算出一屏 0%")
    XCTAssertNotNil(feature.statisticsError)
  }

  @MainActor func testAFailedRefreshKeepsTheNumbersAlreadyOnScreen() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = FakeReviewServer()
    server.stats = [
      "groups": [["id": "sig-1", "title": "看多 · 收盘确认", "total": 40, "correct": 26]],
      "proof": ["compatible_groups": ["sig-1": ["numerator": 26, "denominator": 40,
                                                "verdict_status": "verdict_due", "recheck": true]]],
    ]
    let feature = ReviewFeature(directory: directory)
    let store = try ReviewStore(directory: directory.appendingPathComponent("account"))
    feature.activate(store: store, client: client(server))
    await feature.loadStatistics()
    XCTAssertEqual(feature.statistics.first?.rateText, "65%")

    server.statsFailure = ScorebookError.http(503, "temporarily_unavailable")
    await feature.loadStatistics()
    XCTAssertEqual(feature.statistics.first?.rateText, "65%", "刷新失败不该把刚才那屏数字清空")
    XCTAssertNotNil(feature.statisticsError)
  }

  /// 换个账号进来，上一个人的战绩、记录、搜索结果一律清空——数字不许越账号。
  @MainActor func testSwitchingAccountsClearsTheOtherPersonsNumbers() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = FakeReviewServer()
    server.stats = [
      "groups": [["id": "sig-1", "title": "看多 · 收盘确认", "total": 40, "correct": 26]],
      "proof": ["compatible_groups": ["sig-1": ["numerator": 26, "denominator": 40,
                                                "verdict_status": "verdict_due"]]],
    ]
    let feature = ReviewFeature(directory: directory)
    let first = try ReviewStore(directory: directory.appendingPathComponent("first"))
    feature.activate(store: first, client: client(server))
    await feature.loadStatistics()
    await feature.loadHistory()
    XCTAssertFalse(feature.statistics.isEmpty)

    let second = try ReviewStore(directory: directory.appendingPathComponent("second"))
    feature.activate(store: second, client: client(FakeReviewServer()))
    XCTAssertTrue(feature.statistics.isEmpty, "上一个账号的战绩不许留在屏幕上")
    XCTAssertTrue(feature.records.isEmpty)
    XCTAssertTrue(feature.bookRecords.isEmpty)
    XCTAssertNil(feature.statisticsError)
  }

  // MARK: - P2.7：作废一条记录，五秒内能撤销

  /// 作废之后先说一句带「撤销」的话；窗口里点撤销，记录回来、那条作废根本没发到服务端。
  /// P2.9：判定落下（完成复盘、同一次 / 独立判断）报 `.done`，作废报 `.removed`；
  /// 只存草稿、判定失败都不报——宿主按这个出触觉，报错了就是替没发生的事震一下。
  @MainActor func testOnlyVerdictsAndVoidsReportFeedback() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = FakeReviewServer()
    let feature = ReviewFeature(directory: directory)
    let store = try ReviewStore(directory: directory.appendingPathComponent("account"))
    feature.activate(store: store, client: client(server))
    var heard: [ReviewFeedback] = []
    feature.onFeedback = { heard.append($0) }

    let draft = validDraft()
    feature.begin(draft)
    XCTAssertTrue(feature.saveRecord())
    await settle(feature)
    XCTAssertEqual(heard, [], "记下一笔由宿主那边震，这个包不该再报一次")

    feature.saveReflection(draft.id, note: "", nextTime: "", publish: true)
    XCTAssertEqual(heard, [], "没写复盘就点完成，被拦下了还震")
    feature.saveReflection(draft.id, note: "草稿", nextTime: "", publish: false)
    XCTAssertEqual(heard, [], "存草稿不是判定")
    feature.saveReflection(draft.id, note: "追高了", nextTime: "等回踩", publish: true)
    XCTAssertEqual(heard, [.done])
    await settle(feature)
    feature.resolveGroup(draft.id, sameEpisode: true)
    XCTAssertEqual(heard, [.done, .done])
    await settle(feature)
    feature.voidRecord(draft.id)
    XCTAssertEqual(heard, [.done, .done, .removed])
    feature.resolveGroup(UUID(), sameEpisode: false)
    XCTAssertEqual(heard, [.done, .done, .removed], "没有这条记录，判定没发生")
  }

  @MainActor func testVoidingARecordCanBeUndoneBeforeItIsSent() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = FakeReviewServer()
    let feature = ReviewFeature(directory: directory)
    let store = try ReviewStore(directory: directory.appendingPathComponent("account"))
    feature.activate(store: store, client: client(server))
    var said: [String] = []
    var undo: (@MainActor () -> Void)?
    feature.onUndoable = { text, action in said.append(text); undo = action }

    let draft = validDraft()
    feature.begin(draft)
    XCTAssertTrue(feature.saveRecord())
    await settle(feature)
    XCTAssertEqual(feature.pendingUploads, 0)

    feature.voidRecord(draft.id)
    await settle(feature)
    XCTAssertEqual(said, ["已作废"], "作废之后没给「撤销」")
    XCTAssertEqual(feature.record(draft.id)?.voided, true, "本地得立刻显示已作废")
    XCTAssertEqual(feature.pendingUploads, 1, "作废要排在队列里（app 被杀也不丢）")
    XCTAssertFalse(server.paths.contains { $0.contains("/void") }, "撤销窗口还没过，作废就发出去了")

    try XCTUnwrap(undo)()
    XCTAssertEqual(feature.record(draft.id)?.voided, false, "撤销之后记录没回来")
    XCTAssertEqual(feature.pendingUploads, 0, "撤销之后那条作废还挂在队列里")
    try? await Task.sleep(for: .milliseconds(80))
    await settle(feature)
    XCTAssertFalse(server.paths.contains { $0.contains("/void") }, "撤销过的作废还是发出去了")
  }

  /// 不撤销：窗口一过，作废照常发出去。
  @MainActor func testAVoidIsSentOnceTheUndoWindowPasses() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = FakeReviewServer()
    let feature = ReviewFeature(directory: directory)
    feature.undoWindow = .milliseconds(50)
    let store = try ReviewStore(directory: directory.appendingPathComponent("account"))
    feature.activate(store: store, client: client(server))

    let draft = validDraft()
    feature.begin(draft)
    XCTAssertTrue(feature.saveRecord())
    await settle(feature)

    feature.voidRecord(draft.id)
    for _ in 0..<200 where !server.paths.contains(where: { $0.contains("/void") }) {
      try? await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertTrue(server.paths.contains { $0.contains("/void") }, "窗口过了作废还没发出去")
  }

  // MARK: - P3.7：同步正在拉列表时点了「完成复盘」，这一轮收尾要再跑一轮把它发出去

  @MainActor func testReflectionSavedWhileListingIsSentByAFollowUpRun() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = FakeReviewServer()
    var mine = ReviewRecord(draft: validDraft())
    mine.serverId = mine.id; mine.revision = 1
    server.records = [mine.id: mine]; server.page0 = [mine.id]

    let feature = ReviewFeature(directory: directory)
    let store = try ReviewStore(directory: directory.appendingPathComponent("account"))
    try store.transaction { $0.records = [mine] }
    feature.activate(store: store, client: client(server))

    server.holdList = true
    feature.synchronize(manual: true)
    for _ in 0..<400 where !server.listWaiting { try? await Task.sleep(for: .milliseconds(5)) }
    XCTAssertTrue(server.listWaiting, "这一轮得停在拉列表那一段")

    feature.saveReflection(mine.id, note: "突破没站稳", nextTime: "", publish: true)
    XCTAssertEqual(feature.pendingUploads, 1)
    server.holdList = false
    await settle(feature)

    XCTAssertEqual(feature.pendingUploads, 0, "刚写的复盘还躺在本机队列里——这一轮没回头看队列，也没人补跑")
    XCTAssertEqual(server.records[mine.id]?.reflection.note, "突破没站稳")
  }
}
