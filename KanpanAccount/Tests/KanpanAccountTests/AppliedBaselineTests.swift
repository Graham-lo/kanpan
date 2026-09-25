import Foundation
import Testing
@testable import KanpanAccount

/// 差分基线是「本机装进去的那一版」，不是「云端收到 / 下发的那一版」（`SyncArchive.shelved`）；
/// 以及同一批修整里的两件事：多批推送断在半路时 `onPushed` 照样报一次，补推拒绝记录的收尾。
@MainActor @Suite("同步：本机已装的那一版做基线") struct AppliedBaselineTests {
  private let device = UUID()
  private let chartKey = "settings:chart"
  private func temp() throws -> URL {
    let p = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true); return p
  }
  private func stamped(_ server: FakeSyncServer, _ collection: String, _ id: String,
                       _ body: [String: JSONValue], revision: Int64, age: Int64 = 600_000) -> SyncObject {
    var object = SyncObject(collection: collection, id: id)
    object.body = body; object.revision = revision
    for key in body.keys {
      object.fields[key] = FakeSyncServer.Stamp(revision: revision, timestamp: server.now - age, logical: 1,
                                                deviceId: "00000000-0000-0000-0000-000000000000",
                                                operationId: "00000000-0000-0000-0000-000000000000").json
    }
    return object
  }
  private func chart(_ skin: String, _ spacing: Double) -> SyncObject {
    var value = SyncObject(collection: "settings", id: "chart")
    value.body = ["skin": .string(skin), "barSpacing": .number(spacing)]
    return value
  }
  /// 云端 `settings:chart` 是 moss/6，本机拉下来、装好了。
  private func appliedStore(_ root: URL, _ server: FakeSyncServer) throws -> SyncStore {
    let store = try SyncStore(directory: root)
    server.seed(stamped(server, "settings", "chart", ["skin": .string("moss"), "barSpacing": .number(6)], revision: 1))
    try store.receive(server.page(["settings"]))
    try store.markApplied(at: 1)
    #expect(store.archive.shelved.isEmpty)
    return store
  }

  // MARK: - A

  /// (a) 别的设备把皮肤改成 terra，本机拉下来还没装；用户这时改了柱宽。
  /// 只许推柱宽那一项，云端的 terra 不许被「moss」回滚掉。
  @Test func anUnappliedCloudChangeIsNotRolledBackByAnotherFieldsEdit() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let server = FakeSyncServer()
    let store = try appliedStore(root, server)
    server.seed(stamped(server, "settings", "chart", ["skin": .string("terra"), "barSpacing": .number(6)], revision: 2))
    try store.receive(server.page(["settings"]))
    #expect(store.archive.unapplied == ["settings"])
    #expect(store.archive.shelved[chartKey]?.object?.body["skin"] == .string("moss"))
    #expect(store.archive.appliedLocal[chartKey]?.body["skin"] == .string("moss"))

    // 整表记账时没碰过的对象：用户眼前那一版原样交上来，一条操作都不记。
    try store.capture(chart("moss", 6), device: device)
    #expect(store.archive.operations.isEmpty)

    try store.capture(chart("moss", 8), device: device)
    let op = try #require(store.archive.operations.first)
    #expect(store.archive.operations.count == 1)
    #expect(op.action == "patch")
    #expect(op.fields == ["barSpacing": .number(8)])
    // 记账是云端那份叠上用户动过的字段；用户眼前那一版挪成新底稿。
    #expect(store.archive.local[chartKey]?.body == ["skin": .string("terra"), "barSpacing": .number(8)])
    #expect(store.archive.shelved[chartKey]?.object?.body == ["skin": .string("moss"), "barSpacing": .number(8)])

    try await engine(over: server, store, device: device).run(.push)
    #expect(server.objects[chartKey]?.body == ["skin": .string("terra"), "barSpacing": .number(8)])
    #expect(store.archive.local[chartKey]?.body == ["skin": .string("terra"), "barSpacing": .number(8)])
    // 回执不会把底稿冲掉：本机还没装 terra。
    #expect(store.archive.appliedLocal[chartKey]?.body["skin"] == .string("moss"))
  }

  /// (b) 云端新带来一个对象，本机还没装：拿 `appliedLocal` 判删除时它不在里面，
  /// 整表记账不会把它当成「用户删了」推一条删除。
  @Test func aReceivedButUnappliedObjectIsNotTakenForADeletion() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let server = FakeSyncServer()
    let store = try SyncStore(directory: root)
    let old = stamped(server, "drawings", "binance/usd_m/BTCUSDT/a", ["symbol": .string("BTCUSDT")], revision: 1)
    server.seed(old)
    try store.receive(server.page(["drawings"]))
    try store.markApplied(at: 1)
    let fresh = stamped(server, "drawings", "binance/usd_m/BTCUSDT/b", ["symbol": .string("BTCUSDT")], revision: 1)
    server.seed(fresh)
    try store.receive(server.page(["drawings"]))

    #expect(store.archive.local[fresh.key] != nil)
    #expect(store.archive.appliedLocal[fresh.key] == nil, "本机装的那一版里没有它")
    #expect(store.archive.appliedLocal[old.key] != nil)
    #expect(store.archive.shelved[fresh.key] == ShelvedObject(collection: "drawings", id: fresh.id, object: nil))

    // 本机档案里只有 a（b 还没装进来）。桥上 `withDeletions` 的同一段推法：
    let onDisk = [old]
    func deletions(against local: some Sequence<SyncObject>) -> [SyncObject] {
      let keys = Set(onDisk.map(\.key))
      return local.filter { $0.collection == "drawings" && !$0.deleted && !keys.contains($0.key) }
        .map { var value = $0; value.deleted = true; return value }
    }
    #expect(deletions(against: store.archive.local.values).map(\.key) == [fresh.key], "拿 local 比就会误删")
    let batch = onDisk + deletions(against: store.archive.appliedLocal.values)
    try store.capture(batch, device: device)
    #expect(store.archive.operations.isEmpty, "\(store.archive.operations.map { ($0.objectId, $0.action) })")
    #expect(store.archive.local[fresh.key]?.deleted == false)

    // 用户在装之前真的删了它（本机眼前没有它、又明说要删）：没有底稿可比，照旧发删除。
    var gone = fresh; gone.deleted = true
    try store.capture(gone, device: device)
    #expect(store.archive.operations.map(\.action) == ["delete"])
    #expect(store.archive.shelved[fresh.key] == nil)
  }

  /// (c) 装完（`markApplied`）底稿就作废，之后照常拿 `local` 差分。
  @Test func applyingClearsTheShelf() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let server = FakeSyncServer()
    let store = try appliedStore(root, server)
    server.seed(stamped(server, "settings", "chart", ["skin": .string("terra"), "barSpacing": .number(6)], revision: 2))
    let line = stamped(server, "drawings", "binance/usd_m/BTCUSDT/a", ["symbol": .string("BTCUSDT")], revision: 1)
    server.seed(line)
    try store.receive(server.page(["settings", "drawings"]))
    #expect(store.archive.shelved.count == 2)

    // 只装了画线那一张：设置的底稿还得留着。
    try store.markApplied(at: 2, covering: ["drawings"])
    #expect(store.archive.shelved.keys.sorted() == [chartKey])
    try store.markApplied(at: 3, covering: ["settings"])
    #expect(store.archive.shelved.isEmpty)
    #expect(store.archive.appliedLocal == store.archive.local)

    // 装完之后用户眼前就是 terra：改柱宽只推柱宽，改皮肤就推皮肤。
    try store.capture(chart("terra", 9), device: device)
    try store.capture(chart("moss", 9), device: device)
    #expect(store.archive.operations.map(\.fields) == [["barSpacing": .number(9)], ["skin": .string("moss")]])

    // 不带范围的 `markApplied` 全清。
    server.seed(stamped(server, "drawings", "binance/usd_m/BTCUSDT/c", ["symbol": .string("BTCUSDT")], revision: 1))
    try store.receive(server.page(["drawings"]))
    #expect(!store.archive.shelved.isEmpty)
    try store.markApplied(at: 4)
    #expect(store.archive.shelved.isEmpty)
  }

  /// (d) 没有 `shelved` 这个键的老存档（整份的 `sync-v1.json`、分片的 shard）都打得开；
  /// 底稿本身能活过重启。
  @Test func oldArchivesOpenAndTheShelfSurvivesARestart() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let legacy = """
    {"version":1,"operations":[],"sent":[],"objects":{},"local":{"settings:chart":{"collection":"settings",\
    "id":"chart","body":{"skin":"moss"},"fields":{},"revision":1,"deleted":false,"generation":0}},\
    "autoSync":true,"logical":1,"offset":0}
    """
    try Data(legacy.utf8).write(to: root.appendingPathComponent("sync-v1.json"))
    let store = try SyncStore(directory: root)
    #expect(store.archive.shelved.isEmpty)
    #expect(store.archive.local[chartKey]?.body["skin"] == .string("moss"))

    let shard = try JSONDecoder().decode(ArchiveShard.self, from: Data(#"{"objects":{},"local":{}}"#.utf8))
    #expect(shard.shelved.isEmpty)
    let head = try JSONDecoder().decode(SyncArchive.self, from: Data(#"{"version":1}"#.utf8))
    #expect(head.shelved.isEmpty)

    let server = FakeSyncServer()
    var terra = SyncObject(collection: "settings", id: "chart"); terra.body = ["skin": .string("terra")]; terra.revision = 2
    server.seed(terra)
    try store.receive(server.page(["settings"]))
    #expect(store.archive.shelved[chartKey]?.object?.body["skin"] == .string("moss"))
    await store.flush()
    let reopened = try SyncStore(directory: root)
    #expect(reopened.archive.shelved == store.archive.shelved)
    #expect(reopened.archive.local[chartKey]?.body["skin"] == .string("terra"))
  }

  // MARK: - B

  /// 两批：第一批推上去了、第二批断网。第一批那几个字段确实在云端了，`onPushed` 必须报它们一次。
  @Test func aPushThatDiesHalfwayStillReportsTheFirstBatch() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let server = FakeSyncServer()
    let store = try appliedStore(root, server)
    try store.capture(chart("terra", 6), device: device)
    try store.capture(chart("terra", 8), device: device)
    #expect(store.archive.operations.count == 2)

    let transport = ServerTransport(server)
    transport.beforeReply = { [transport] in transport.pushFailures = [URLError(.networkConnectionLost)] }
    let engine = SyncEngine(store: store, transport: transport, device: device)
    engine.batchLimit = 1
    var reports: [(Set<String>, Set<String>)] = []
    engine.onPushed = { reports.append(($0, $1)) }
    await #expect(throws: URLError.self) { try await engine.run(.push) }

    #expect(reports.count == 1)
    #expect(reports.first?.0 == ["skin"])
    #expect(reports.first?.1 == ["barSpacing"])
    #expect(server.objects[chartKey]?.body["skin"] == .string("terra"))
    #expect(store.archive.operations.map(\.fields) == [["barSpacing": .number(8)]])
  }

  /// 同样断在半路，但这一轮已经不算数了（换了账号）：一个字都不报。
  @Test func aStaleRoundReportsNothing() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let server = FakeSyncServer()
    let store = try appliedStore(root, server)
    try store.capture(chart("terra", 6), device: device)
    try store.capture(chart("terra", 8), device: device)

    var current = true
    let transport = ServerTransport(server)
    transport.beforeReply = { current = false }
    let engine = SyncEngine(store: store, transport: transport, device: device)
    engine.batchLimit = 1
    engine.stillCurrent = { current }
    var reports = 0
    engine.onPushed = { _, _ in reports += 1 }
    await #expect(throws: CancellationError.self) { try await engine.run(.push) }
    #expect(reports == 0)
  }

  // MARK: - C

  private func reject(_ store: SyncStore, local: SyncObject, timestamp: Int64, logical: UInt64) throws {
    let op = SyncOperation(collection: local.collection, objectId: local.id, deviceId: device, baseRevision: 1,
                           generation: 0, timestamp: timestamp, logical: logical, action: "patch",
                           fields: ["text": .null])
    try store.transaction { a in
      a.local[local.key] = local
      a.rejected = [RejectedOperation(operation: op, reason: "invalid_operation", at: 1, intent: local)]
    }
  }

  /// 本地和云端只差一个外来键：带回外来键之后没有东西可补，记录要了结并落盘，
  /// 不能每轮全量都原地留着。
  @Test func aRecordThatOnlyDiffersByAForeignKeyIsResolved() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let server = FakeSyncServer()
    let store = try SyncStore(directory: root)
    let remote = stamped(server, "drawings", "binance/usd_m/BTCUSDT/note",
                         ["symbol": .string("BTCUSDT"), "created": .number(1)], revision: 1)
    server.seed(remote)
    try store.receive(server.page(["drawings"]))
    var local = remote; local.body["created"] = nil
    try reject(store, local: local, timestamp: 100, logical: 3)

    try store.retryRejected(device: device, owning: ["drawings": ["symbol", "text"]])
    #expect(store.archive.rejected.isEmpty)
    #expect(store.archive.operations.isEmpty)
    #expect(store.archive.local[remote.key]?.body == remote.body)
  }

  /// 补推沿用被拒那条的时间戳与逻辑钟，id 另起一个。
  @Test func theRetryKeepsTheOriginalStamp() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let server = FakeSyncServer()
    let store = try SyncStore(directory: root)
    let remote = stamped(server, "drawings", "binance/usd_m/BTCUSDT/note",
                         ["symbol": .string("BTCUSDT"), "text": .string("顶背离")], revision: 1)
    server.seed(remote)
    try store.receive(server.page(["drawings"]))
    var local = remote; local.body["text"] = nil
    try reject(store, local: local, timestamp: 123_456, logical: 7)
    let logical = store.archive.logical

    try store.retryRejected(device: device)
    let op = try #require(store.archive.operations.first)
    #expect(op.fields == ["text": .null])
    #expect(op.timestamp == 123_456)
    #expect(op.logical == 7)
    #expect(op.id != store.archive.rejected.first?.operation.id)
    #expect(store.archive.logical == logical, "沿用旧逻辑钟时不许把本机时钟往前拨")
    #expect(store.archive.rejected.count == 1, "推上去之前记录还留着")
  }
}
