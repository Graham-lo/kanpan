import XCTest
import Foundation
import ReviewDomain
import ReviewData
import KanpanAccount
@testable import ReviewUI

// ============================================================ 同步队列的特征测试（第 25 项）
//
// 把「上传队列 + 拉取」这一段**现在的行为**钉下来，再把它从 `ReviewFeature` 里搬到
// `ReviewData` 的同步引擎里。每一条都走录回放：假 transport 按剧本一问一答，
// 同时把每一次请求（方法、路径、幂等键、body）原样录下来，断言的是「线上看得见的
// 那一串请求」和「本机存档最后长什么样」，不断言实现细节——搬家前后这组必须一字不改地过。
//
// 五种剧本：正常、409、422、网络断、拉取分页。

/// 录回放 transport。剧本是一串「路径前缀 → 应答」，按顺序消费；剧本外的请求直接判失败。
@MainActor final class ReviewReplayTransport {
  struct Request: Equatable {
    var method: String
    var path: String
    var key: UUID?
    var body: Data?
    /// body 里的一个字段（没有就 nil）。
    func field(_ name: String) -> Any? {
      guard let body, let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
      return object[name]
    }
  }
  enum Reply {
    case json(Any)
    case failure(any Error)
    /// 按请求现造应答（新建要把 body 里的草稿原样回过去）。
    case make((Request) throws -> Any)
  }
  struct Step { var method: String; var prefix: String; var reply: Reply }

  private(set) var log: [Request] = []
  var script: [Step] = []

  func expect(_ method: String, _ prefix: String, _ reply: Reply) {
    script.append(Step(method: method, prefix: prefix, reply: reply))
  }
  var transport: ScorebookClient.Transport {
    { [self] path, method, body, key in try await self.answer(path, method, body, key) }
  }
  private func answer(_ path: String, _ method: String, _ body: Data?, _ key: UUID?) async throws -> Data {
    let request = Request(method: method, path: path, key: key, body: body)
    log.append(request)
    guard !script.isEmpty else {
      XCTFail("剧本外的请求：\(method) \(path)")
      throw ScorebookError.http(599, "unscripted")
    }
    let step = script.removeFirst()
    XCTAssertEqual(step.method, method, "第 \(log.count) 次请求的方法不对：\(path)")
    XCTAssertTrue(path.hasPrefix(step.prefix), "第 \(log.count) 次请求应该是 \(step.prefix)，实际是 \(path)")
    switch step.reply {
    case .json(let value): return try JSONSerialization.data(withJSONObject: ["data": value])
    case .failure(let error): throw error
    case .make(let build): return try JSONSerialization.data(withJSONObject: ["data": try build(request)])
    }
  }
  var paths: [String] { log.map { $0.method + " " + $0.path } }
}

final class ReviewSyncCharacterizationTests: XCTestCase {
  private static let records = "v1/native-review/records"

  private func makeDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("review-char-" + UUID().uuidString)
  }
  private func validDraft(symbol: String = "BTCUSDT", ageBars: Int64 = 0) -> ReviewDraft {
    let step: Int64 = 3_600_000
    let end = (ReviewClock.now / step) * step - ageBars * step
    let range = ReviewRange(symbol: symbol, interval: "1h", start: end - step * 48, end: end, bars: 48)
    return ReviewDraft(range: range, reference: 100, high: 110, low: 90, now: ReviewClock.now)
  }
  /// 一份已经在云端的记录。
  private func cloud(_ symbol: String, revision: Int, ageBars: Int64 = 0) -> ReviewRecord {
    var draft = validDraft(symbol: symbol, ageBars: ageBars)
    // 记下的时刻按「多久以前」错开，倒序排才有确定的先后。
    draft.created -= ageBars * 1000
    var value = ReviewRecord(draft: draft)
    value.serverId = value.id; value.revision = revision; value.submitted = value.draft.created
    return value
  }
  private func object(_ record: ReviewRecord) -> Any {
    (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(record))) ?? [:]
  }
  /// 新建的应答：把 body 里的草稿当成服务端存下的第 1 版。
  private func created(_ request: ReviewReplayTransport.Request) throws -> Any {
    let draft = try JSONDecoder().decode(ReviewDraft.self, from: request.body ?? Data())
    var value = ReviewRecord(draft: draft)
    value.serverId = draft.id; value.revision = 1; value.submitted = draft.created
    return ["record": object(value), "assessmentRevision": 0]
  }
  private func updated(_ record: ReviewRecord, revision: Int, note: String? = nil) -> Any {
    var value = record; value.revision = revision
    if let note { value.reflection.note = note }
    return ["record": object(value), "assessmentRevision": 1]
  }
  private func page(_ records: [ReviewRecord], next: String? = nil) -> Any {
    ["records": records.map(object), "next": next.map { $0 as Any } ?? NSNull()]
  }

  /// 起一个接好录回放 transport 的模型。
  @MainActor private func makeFeature(_ directory: URL, _ replay: ReviewReplayTransport,
                                      seed: [ReviewRecord] = []) throws -> (ReviewFeature, ReviewStore) {
    let store = try ReviewStore(directory: directory.appendingPathComponent("account"))
    if !seed.isEmpty { try store.transaction { $0.records = seed } }
    let feature = ReviewFeature(directory: directory)
    let client = ScorebookClient(connection: ReviewConnection(baseURL: URL(string: "https://example.invalid")!),
                                 transport: replay.transport)
    feature.activate(store: store, client: client)
    feature.autoSync = false
    return (feature, store)
  }
  @MainActor private func settle(_ feature: ReviewFeature) async {
    for _ in 0..<600 {
      await Task.yield()
      if !feature.syncing { return }
      try? await Task.sleep(for: .milliseconds(5))
    }
    XCTFail("同步一直没结束")
  }
  @MainActor private func run(_ feature: ReviewFeature) async {
    feature.autoSync = true
    feature.synchronize(manual: true)
    await settle(feature)
    feature.autoSync = false
  }

  // MARK: - 正常

  /// 一条新建 + 同一条旧记录上连着两次复盘：按入队顺序逐条发，幂等键就是操作 id，
  /// 更新类的 `expectedRevision` 发之前改写成本机那一刻的版本（第二条接着第一条回来的版本），
  /// 发完队列清空，最后拉**一次**第一页并入本机。
  @MainActor func testNormalRunSendsInOrderWithStableKeysAndRebasedRevisions() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let replay = ReviewReplayTransport()
    let mine = cloud("ETHUSDT", revision: 3, ageBars: 2)
    let (feature, store) = try makeFeature(directory, replay, seed: [mine])
    var completions = 0
    feature.onSyncComplete = { completions += 1 }

    let draft = validDraft()
    feature.begin(draft)
    XCTAssertTrue(feature.saveRecord())
    feature.saveReflection(mine.id, note: "第一版", nextTime: "", publish: false)
    feature.saveReflection(mine.id, note: "第二版", nextTime: "", publish: false)
    let queued = store.archive.queue
    XCTAssertEqual(queued.map(\.kind), ["create", "reflection", "reflection"])

    replay.expect("POST", Self.records, .make(created))
    replay.expect("POST", "\(Self.records)/\(mine.id.uuidString)/reflection", .json(updated(mine, revision: 4, note: "第一版")))
    replay.expect("POST", "\(Self.records)/\(mine.id.uuidString)/reflection", .json(updated(mine, revision: 5, note: "第二版")))
    var listed = mine; listed.revision = 5; listed.reflection.note = "第二版"
    let other = cloud("SOLUSDT", revision: 1, ageBars: 5)
    var createdRecord = ReviewRecord(draft: draft); createdRecord.serverId = draft.id; createdRecord.revision = 1
    replay.expect("GET", Self.records, .json(page([createdRecord, listed, other], next: "c1")))
    await run(feature)

    XCTAssertTrue(replay.script.isEmpty, "剧本没走完：\(replay.paths)")
    XCTAssertEqual(replay.paths, [
      "POST \(Self.records)",
      "POST \(Self.records)/\(mine.id.uuidString)/reflection",
      "POST \(Self.records)/\(mine.id.uuidString)/reflection",
      "GET \(Self.records)",
    ], "同步那一轮只拉第一页，不带 after")
    XCTAssertEqual(replay.log.prefix(3).map(\.key), queued.map { Optional($0.id) }, "幂等键就是队列里那条操作的 id")
    XCTAssertEqual(replay.log[1].field("expectedRevision") as? Int, 3)
    XCTAssertEqual(replay.log[2].field("expectedRevision") as? Int, 4, "第二条接着第一条回来的版本发")
    XCTAssertNil(replay.log[0].field("expectedRevision"), "新建没有版本可锁")
    XCTAssertEqual(store.archive.queue.count, 0)
    XCTAssertEqual(feature.pendingUploads, 0)
    XCTAssertEqual(completions, 1)
    XCTAssertNil(feature.notice)
    XCTAssertEqual(Set(store.archive.records.map(\.id)), [draft.id, mine.id, other.id], "第一页里本机没有的那条也并进来")
    XCTAssertEqual(feature.record(mine.id)?.revision, 5)
    XCTAssertEqual(feature.record(mine.id)?.reflection.note, "第二版")
    XCTAssertEqual(feature.record(draft.id)?.serverId, draft.id)
    XCTAssertEqual(store.archive.records.map(\.draft.created), store.archive.records.map(\.draft.created).sorted(by: >), "按记下的时刻倒序")
  }

  // MARK: - 409

  /// 409：这一条摘下来存成可重试的冲突（内容一个字不丢），队列接着往下跑，照常拉列表收尾。
  @MainActor func testConflictIsQuarantinedAsRetryableAndTheQueueMovesOn() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let replay = ReviewReplayTransport()
    let mine = cloud("ETHUSDT", revision: 3, ageBars: 2)
    let (feature, store) = try makeFeature(directory, replay, seed: [mine])
    var completions = 0
    feature.onSyncComplete = { completions += 1 }

    feature.saveReflection(mine.id, note: "等回踩", nextTime: "下次等确认", publish: true)
    let draft = validDraft()
    feature.begin(draft)
    XCTAssertTrue(feature.saveRecord())

    replay.expect("POST", "\(Self.records)/\(mine.id.uuidString)/reflection", .failure(AccountError.http(409, "record_revision_changed")))
    replay.expect("POST", Self.records, .make(created))
    var theirs = mine; theirs.revision = 7
    replay.expect("GET", Self.records, .json(page([theirs])))
    await run(feature)

    XCTAssertTrue(replay.script.isEmpty, "剧本没走完：\(replay.paths)")
    XCTAssertEqual(store.archive.queue.count, 0)
    let stuck = try XCTUnwrap(feature.record(mine.id))
    XCTAssertEqual(stuck.conflict?.kind, "reflection")
    XCTAssertEqual(stuck.conflict?.code, "record_revision_changed")
    XCTAssertEqual(stuck.conflict?.retryable, true)
    XCTAssertEqual(stuck.reflection.note, "等回踩", "拉回来的云端那份不许盖掉人写的这段话")
    XCTAssertEqual(stuck.revision, 7, "版本号跟云端走，等人裁决时拿它做基准")
    XCTAssertNil(stuck.syncError)
    XCTAssertEqual(feature.notice, "这条记录在别的设备上改过了")
    XCTAssertNotNil(feature.record(draft.id)?.serverId)
    XCTAssertEqual(completions, 1)
  }

  // MARK: - 422

  /// 422（新建被拒）：摘下来存成**不可重试**的冲突，不重发；后面的操作照常发。
  @MainActor func testRejectedCreateIsQuarantinedAsFinalAndNotRetried() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let replay = ReviewReplayTransport()
    let mine = cloud("ETHUSDT", revision: 3, ageBars: 2)
    let (feature, store) = try makeFeature(directory, replay, seed: [mine])

    let draft = validDraft()
    feature.begin(draft)
    XCTAssertTrue(feature.saveRecord())
    feature.resolveGroup(mine.id, sameEpisode: true)

    replay.expect("POST", Self.records, .failure(AccountError.http(422, "invalid_review_evidence")))
    replay.expect("POST", "\(Self.records)/\(mine.id.uuidString)/group", .json(updated(mine, revision: 4)))
    replay.expect("GET", Self.records, .json(page([])))
    await run(feature)

    XCTAssertTrue(replay.script.isEmpty, "剧本没走完：\(replay.paths)")
    XCTAssertEqual(store.archive.queue.count, 0)
    let rejected = try XCTUnwrap(feature.record(draft.id))
    XCTAssertEqual(rejected.conflict?.kind, "create")
    XCTAssertEqual(rejected.conflict?.retryable, false)
    XCTAssertNil(rejected.serverId)
    XCTAssertEqual(feature.notice, "这段行情服务端不收，换一段再记")
    XCTAssertEqual(feature.record(mine.id)?.revision, 4)

    // 第二轮：没有什么可发的，只拉列表。被拒那条不会被悄悄重发。
    replay.expect("GET", Self.records, .json(page([])))
    await run(feature)
    XCTAssertEqual(replay.paths.filter { $0 == "POST \(Self.records)" }.count, 1)
    XCTAssertNotNil(feature.record(draft.id)?.conflict, "只活在本机的冲突拉一次列表也不许抹掉")
  }

  // MARK: - 网络断

  /// 断网：这一条原样留在队首（标记为发过、幂等键和 body 都不变），记录上挂一句错误，
  /// 不拉列表、不报完成；网回来之后一模一样地重发。
  @MainActor func testNetworkFailureKeepsTheOperationAndRetriesWithTheSameKey() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let replay = ReviewReplayTransport()
    let (feature, store) = try makeFeature(directory, replay)
    var completions = 0
    feature.onSyncComplete = { completions += 1 }

    let draft = validDraft()
    feature.begin(draft)
    XCTAssertTrue(feature.saveRecord())
    let later = validDraft(symbol: "ETHUSDT")
    feature.begin(later)
    XCTAssertTrue(feature.saveRecord())

    replay.expect("POST", Self.records, .failure(URLError(.notConnectedToInternet)))
    await run(feature)

    XCTAssertTrue(replay.script.isEmpty)
    XCTAssertEqual(replay.paths, ["POST \(Self.records)"], "第一条没发出去就停，不越过它发第二条，也不拉列表")
    XCTAssertEqual(store.archive.queue.count, 2)
    XCTAssertEqual(store.archive.queue.first?.attempted, true)
    XCTAssertEqual(completions, 0)
    XCTAssertNotNil(feature.notice)
    let first = try XCTUnwrap(feature.record(draft.id))
    XCTAssertNotNil(first.syncError)
    XCTAssertNil(first.conflict, "断网不是冲突")
    let firstKey = replay.log[0].key
    let firstBody = replay.log[0].body

    replay.expect("POST", Self.records, .make(created))
    replay.expect("POST", Self.records, .make(created))
    replay.expect("GET", Self.records, .json(page([])))
    await run(feature)

    XCTAssertTrue(replay.script.isEmpty, "剧本没走完：\(replay.paths)")
    XCTAssertEqual(replay.log[1].key, firstKey, "重发必须同一个幂等键")
    XCTAssertEqual(replay.log[1].body, firstBody, "同一个键必须配同一份 body")
    XCTAssertNotEqual(replay.log[2].key, firstKey)
    XCTAssertEqual(store.archive.queue.count, 0)
    XCTAssertEqual(completions, 1)
    XCTAssertNotNil(feature.record(draft.id)?.serverId)
    XCTAssertNil(feature.record(draft.id)?.syncError, "传上去之后那句错误要跟着消失")
  }

  /// 被顶下线这类「问不出状态码」的错误一律当成暂时的：留着，不摘成冲突。
  @MainActor func testSessionErrorsAreTransient() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let replay = ReviewReplayTransport()
    let (feature, store) = try makeFeature(directory, replay)
    let draft = validDraft()
    feature.begin(draft)
    XCTAssertTrue(feature.saveRecord())
    replay.expect("POST", Self.records, .failure(AccountError.sessionReplaced(.phone)))
    await run(feature)
    XCTAssertEqual(store.archive.queue.count, 1)
    XCTAssertNil(feature.record(draft.id)?.conflict)
  }

  // MARK: - 拉取分页

  /// 同步那一轮只拉第一页；复盘本往下翻才带着游标接后面的页，接到 `next == nil` 为止。
  /// 同步拉回来的并入本机存档，最多留最近 200 条云端记录（还在队列里的不算）。
  @MainActor func testPullPaginationAndTheCloudCacheCap() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let replay = ReviewReplayTransport()
    // 本机已经缓存了 205 条云端记录。
    let seed = (0..<205).map { cloud("C\($0)USDT", revision: 1, ageBars: Int64($0)) }
    let (feature, store) = try makeFeature(directory, replay, seed: seed)

    let first = Array(seed.prefix(2)), second = Array(seed[2..<4])
    replay.expect("GET", Self.records, .json(page(first)))
    await run(feature)
    XCTAssertTrue(replay.script.isEmpty)
    XCTAssertEqual(store.archive.records.count, 200, "云端记录本机最多缓存 200 条")
    XCTAssertTrue(Set(store.archive.records.map(\.id)) == Set(seed.prefix(200).map(\.id)), "留下的是最近的那 200 条")

    replay.expect("GET", "\(Self.records)?todo=true", .json(page(first, next: "cursor-1")))
    await feature.loadHistory()
    XCTAssertEqual(feature.nextPage, "cursor-1")
    replay.expect("GET", "\(Self.records)?after=cursor-1&todo=true", .json(page(second + [first[0]], next: nil)))
    await feature.loadMoreHistory()
    XCTAssertTrue(replay.script.isEmpty, "剧本没走完：\(replay.paths)")
    XCTAssertEqual(feature.bookRecords.map(\.id), (first + second).map(\.id), "第二页接在后面，重复的那条只算一次")
    XCTAssertNil(feature.nextPage)
    await feature.loadMoreHistory()
    XCTAssertEqual(replay.log.count, 3, "没有下一页时滑到底不再请求")
  }
}
