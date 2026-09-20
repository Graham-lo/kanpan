import XCTest
import Foundation
import ReviewDomain
import ReviewData
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

  var transport: ScorebookClient.Transport {
    { [self] path, method, body, key in try await self.respond(path, method, body, key) }
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
        throw ScorebookError.http(409, "record_revision_changed")
      }
      var record = try XCTUnwrap(records[id])
      guard record.revision == edit.expectedRevision else { throw ScorebookError.http(409, "record_revision_changed") }
      record.reflection = edit.reflection
      record.revision += 1
      records[id] = record
      return try wrap(["record": try object(record), "assessmentRevision": 2, "reflectionAssessmentRevision": 2])
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

  /// 翻到第二页时不补本地那几条：那一页的口径在服务端，补进去就是串行。
  @MainActor func testLaterPagesAreNotMixedWithLocalOnlyRecords() async throws {
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

    await feature.loadHistory(page: 1)
    XCTAssertEqual(feature.bookRecords.map(\.id), [older.id], "第二页只听服务端的")
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

    feature.tab = "history"
    await feature.loadHistory()
    feature.synchronize(manual: true)
    await settle(feature)
    XCTAssertEqual(feature.tab, "history", "拉一次列表、同步一轮，不该把人从他正看的那一档上拨走")
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
}
