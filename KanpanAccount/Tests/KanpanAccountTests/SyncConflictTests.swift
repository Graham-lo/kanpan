import Foundation
import Testing
@testable import KanpanAccount

// MARK: - 按服务端真实规则写的假服务端

/// `Backend/kanpan-api/src/sync.rs` 的 `merge()` / `push()` 在本机的复刻。
///
/// 条件一条都没简化：版本与代次的门槛、`restore` 的精确相等、`delete` 之后
/// `patch` 被默默吞掉、字段级时间戳比大小，以及**一整批在同一个事务里**——
/// 中间任何一条抛出来，整批回滚、一条都不落库。简化任何一条，这几个用例就都
/// 变成在考自己写的模型，而不是在考客户端顶不顶得住真服务器。
@MainActor final class FakeSyncServer {
  enum Failure: Error, Equatable { case conflict(String), bad(String) }

  struct Stamp {
    var revision: Int64, timestamp: Int64, logical: UInt64, deviceId: String, operationId: String
    var json: JSONValue {
      .object(["revision": .number(Double(revision)), "timestamp": .number(Double(timestamp)),
               "logical": .number(Double(logical)), "deviceId": .string(deviceId), "operationId": .string(operationId)])
    }
    init(revision: Int64, timestamp: Int64, logical: UInt64, deviceId: String, operationId: String) {
      self.revision = revision; self.timestamp = timestamp; self.logical = logical
      self.deviceId = deviceId; self.operationId = operationId
    }
    init?(_ value: JSONValue?) {
      guard case .object(let o)? = value,
        case .number(let r)? = o["revision"], case .number(let t)? = o["timestamp"],
        case .number(let l)? = o["logical"], case .string(let d)? = o["deviceId"],
        case .string(let i)? = o["operationId"] else { return nil }
      revision = Int64(r); timestamp = Int64(t); logical = UInt64(l); deviceId = d; operationId = i
    }
    var order: (Int64, UInt64, String, String) { (timestamp, logical, deviceId, operationId) }
  }

  var objects: [String: SyncObject] = [:]
  var cursor: Int64 = 0
  var now = Int64(Date().timeIntervalSince1970 * 1000)
  /// 幂等表：同 id 同 digest 原样回放，同 id 不同 digest 是 `idempotency_mismatch`。
  private var applied: [UUID: (digest: Data, result: SyncResult)] = [:]
  /// 这台服务器按语义顶回来的那些操作（`sync_validation` 那一层）。返回 reason。
  var refuse: (@MainActor (WireOperation) -> String?)?

  func seed(_ object: SyncObject) { objects[object.key] = object }
  func page(_ collections: Set<String>) -> SyncPage {
    SyncPage(objects: objects.values.filter { collections.contains($0.collection) }.sorted { $0.id < $1.id },
             next: nil, cursor: cursor, serverTime: now)
  }

  func push(_ operations: [WireOperation]) throws -> SyncPushResponse {
    guard !operations.isEmpty, operations.count <= 100 else { throw Failure.bad("invalid_batch") }
    // 事务：先在副本上全跑通，最后才提交。任何一条抛出来，外面这两份原样不动。
    var staged = objects
    var stagedApplied = applied
    var stagedCursor = cursor
    var results: [SyncResult] = []
    for op in operations {
      if let reason = refuse?(op) { throw Failure.bad(reason) }
      let digest = try JSONEncoder.sorted.encode(op)
      if let previous = stagedApplied[op.id] {
        guard previous.digest == digest else { throw Failure.conflict("idempotency_mismatch") }
        results.append(previous.result); continue
      }
      let key = op.collection + ":" + op.objectId
      let old = staged[key] ?? SyncObject(collection: op.collection, id: op.objectId)
      let next = try merge(old, op)
      staged[key] = next
      stagedCursor += 1
      let result = SyncResult(operationId: op.id, object: next, cursor: stagedCursor, droppedFields: [])
      stagedApplied[op.id] = (digest, result)
      results.append(result)
    }
    objects = staged; applied = stagedApplied; cursor = stagedCursor
    return SyncPushResponse(results: results, serverTime: now)
  }

  /// `sync.rs:84–110` 的逐行复刻。
  func merge(_ input: SyncObject, _ op: WireOperation) throws -> SyncObject {
    var object = input
    guard op.timestamp >= 0, op.baseRevision >= 0, op.generation >= 0,
      ["patch", "delete", "restore"].contains(op.action) else { throw Failure.bad("invalid_operation") }
    if op.baseRevision > object.revision || op.generation != object.generation { throw Failure.conflict("resync_required") }
    if op.action == "restore" {
      guard object.deleted, op.baseRevision == object.revision else { throw Failure.conflict("resync_required") }
      object.deleted = false; object.generation += 1
    } else if op.action == "delete" {
      object.deleted = true
    } else if object.deleted {
      return object                                   // patch 打在墓碑上：默默吞掉，revision 都不动
    }
    let next = object.revision + 1
    if !object.deleted {
      for (path, value) in op.fields {
        let previous = Stamp(object.fields[path])
        let stamp = Stamp(revision: next, timestamp: min(op.timestamp, now + 300_000), logical: op.logical,
                          deviceId: op.deviceId.uuidString.lowercased(), operationId: op.id.uuidString.lowercased())
        let accept = previous.map { op.baseRevision >= $0.revision || stamp.order > $0.order } ?? true
        if accept {
          if value == .null { object.body.removeValue(forKey: path) } else { object.body[path] = value }
          object.fields[path] = stamp.json
        }
      }
    }
    object.revision = next
    return object
  }
}

extension JSONEncoder {
  static var sorted: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e }
}

// MARK: - 用例

@MainActor @Suite("本地与云端的冲突编排") struct SyncConflictTests {
  private func temp() throws -> URL {
    let p = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true); return p
  }
  private func stamped(_ server: FakeSyncServer, collection: String, id: String,
                       _ body: [String: JSONValue], revision: Int64) -> SyncObject {
    var object = SyncObject(collection: collection, id: id)
    object.body = body
    object.revision = revision
    for key in body.keys {
      object.fields[key] = FakeSyncServer.Stamp(revision: revision, timestamp: server.now - 600_000, logical: 1,
                                                deviceId: "00000000-0000-0000-0000-000000000000",
                                                operationId: "00000000-0000-0000-0000-000000000000").json
    }
    return object
  }

  /// B1 的正面：离线删掉一条线又立刻撤销，这两条是**必定组不成一批**的。
  /// 从前它们被一起发出去、整批回滚，客户端又永远先推后拉，于是这个账号的队列
  /// 从此再也前进不了。
  @Test func offlineDeleteThenUndoRecoversInOneRun() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), server = FakeSyncServer(), device = UUID()
    let line = stamped(server, collection: "drawings", id: "binance/usd_m/BTCUSDT/a",
                       ["symbol": .string("BTCUSDT"), "color": .string("amber")], revision: 4)
    server.seed(line)
    try store.receive(server.page(["drawings"]))

    var deleted = line; deleted.deleted = true
    try store.capture(deleted, device: device)
    try store.capture(line, device: device)
    #expect(store.archive.operations.map(\.action) == ["delete", "restore"])
    // 删除和恢复之间有一条依赖边，批次必须在那儿截断。
    #expect(store.nextBatch(limit: 100, maxBytes: SyncEngine.batchBytes).map(\.action) == ["delete"])

    let loop = try await engine(over: server, store, device: device).run(.push)
    #expect(store.archive.operations.isEmpty)
    let final = try #require(server.objects[line.key])
    #expect(final.deleted == false)
    #expect(final.generation == 1)
    #expect(final.body["color"] == .string("amber"))
    #expect(store.archive.local[line.key]?.deleted == false)
  }

  /// 同一串操作走从前那条「队首直接切一百条、409 只置个标记」的路：整批回滚，
  /// 推不上去，而且重跑多少次都是同一个 409。
  @Test func theOldBatchingCannotGetPastTheSameConflict() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), server = FakeSyncServer(), device = UUID()
    let line = stamped(server, collection: "drawings", id: "binance/usd_m/BTCUSDT/a",
                       ["symbol": .string("BTCUSDT")], revision: 4)
    server.seed(line)
    try store.receive(server.page(["drawings"]))
    var deleted = line; deleted.deleted = true
    try store.capture(deleted, device: device)
    try store.capture(line, device: device)

    // 从前的走法：队首直接切一百条整批发，409 之后只置个标记、下一轮原样再发。
    for _ in 0..<3 {
      #expect(throws: FakeSyncServer.Failure.conflict("resync_required")) {
        try server.push(store.archive.operations.prefix(100).map(WireOperation.init))
      }
    }
    #expect(store.archive.operations.count == 2)          // 一条都没前进
    #expect(server.objects[line.key]?.revision == 4)      // 服务端整批回滚了
  }

  /// 删除 → 恢复 → 接着编辑：三条都要落地，语义顺序也要对。
  @Test func deleteRestoreThenEditAllLand() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), server = FakeSyncServer(), device = UUID()
    let line = stamped(server, collection: "drawings", id: "binance/usd_m/BTCUSDT/a",
                       ["symbol": .string("BTCUSDT"), "color": .string("amber")], revision: 4)
    server.seed(line)
    try store.receive(server.page(["drawings"]))

    var deleted = line; deleted.deleted = true
    try store.capture(deleted, device: device)
    try store.capture(line, device: device)
    var edited = line; edited.body["color"] = .string("blue")
    try store.capture(edited, device: device)
    #expect(store.archive.operations.map(\.action) == ["delete", "restore", "patch"])

    let loop = try await engine(over: server, store, device: device).run(.push)
    #expect(store.archive.operations.isEmpty)
    let final = try #require(server.objects[line.key])
    #expect(final.deleted == false)
    #expect(final.generation == 1)
    #expect(final.body["color"] == .string("blue"))
    #expect(loop.batches == [1, 1, 1])
  }

  /// 设备 B 删了又恢复把代次推到 1，A 带着代次 0 的旧操作重连：走恢复路径，
  /// A 的改动不能丢。
  @Test func aReconnectsAcrossDeviceBsGenerationBump() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), server = FakeSyncServer()
    let a = UUID(), b = UUID()
    let line = stamped(server, collection: "drawings", id: "binance/usd_m/BTCUSDT/a",
                       ["symbol": .string("BTCUSDT"), "color": .string("amber")], revision: 4)
    server.seed(line)
    try store.receive(server.page(["drawings"]))

    // A 离线改了颜色。
    var mine = line; mine.body["color"] = .string("teal")
    try store.capture(mine, device: a)

    // 与此同时 B 把这条线删了又恢复：代次 0 → 1。
    func wire(_ action: String, base: Int64, generation: Int64) -> WireOperation {
      WireOperation(SyncOperation(collection: "drawings", objectId: line.id, deviceId: b, baseRevision: base,
                                  generation: generation, timestamp: server.now - 1_000, logical: 1,
                                  action: action, fields: [:], importBatch: nil))
    }
    _ = try server.push([wire("delete", base: 4, generation: 0)])
    _ = try server.push([wire("restore", base: 5, generation: 0)])
    #expect(server.objects[line.key]?.generation == 1)

    let loop = try await engine(over: server, store, device: a).run(.push)
    #expect(store.archive.operations.isEmpty)
    let final = try #require(server.objects[line.key])
    #expect(final.generation == 1)
    #expect(final.deleted == false)
    #expect(final.body["color"] == .string("teal"))    // A 的意图没丢
    #expect(store.archive.local[line.key]?.body["color"] == .string("teal"))
  }

  /// B5 的核心验收：同一串离线操作，分成 1 / 99 / 100 / 101 条推上去，
  /// 最终状态必须一模一样。B 的并发修改就放在里头。
  @Test(arguments: [1, 99, 100, 101]) func theBatchBoundaryDoesNotPickTheWinner(_ count: Int) async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), server = FakeSyncServer()
    let a = UUID(), b = UUID()
    let chart = stamped(server, collection: "settings", id: "chart",
                        ["barSpacing": .number(4), "skin": .string("moss")], revision: 1)
    server.seed(chart)
    try store.receive(server.page(["settings"]))

    // A 离线连着捏了 count 次。时间戳都比 B 那一下早。
    var mine = chart
    for step in 1...count {
      mine.body["barSpacing"] = .number(Double(4 + step))
      try store.capture(mine, device: a)
    }
    #expect(store.archive.operations.count == count)
    #expect(store.archive.operations.allSatisfy { $0.baseRevision == 1 })

    // B 后到（时间戳更晚），把这个字段改成自己的值。
    _ = try server.push([WireOperation(SyncOperation(
      collection: "settings", objectId: "chart", deviceId: b, baseRevision: 1, generation: 0,
      timestamp: server.now + 200_000, logical: 1, action: "patch",
      fields: ["barSpacing": .number(999)], importBatch: nil))])
    #expect(server.objects["settings:chart"]?.body["barSpacing"] == .number(999))

    let loop = try await engine(over: server, store, device: a).run(.push)
    #expect(store.archive.operations.isEmpty)
    // 不论 A 积压了一条还是一百零一条，赢家都得是时间戳最晚的 B。
    #expect(server.objects["settings:chart"]?.body["barSpacing"] == .number(999))
    #expect(store.archive.local["settings:chart"]?.body["barSpacing"] == .number(999))
    // 互不依赖的 patch 仍然是整批走的，没退化成一条一个请求。
    #expect(loop.batches.count == (count + 99) / 100)
  }

  /// B3：被服务端顶回来之后，用户的值不许回退，记录要留在盘上，`pending` 不许算它，
  /// 服务端修好之后自己用**新 id** 补推。
  @Test func aRejectedOperationKeepsTheUsersValueAndRepushesItself() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    var store = try SyncStore(directory: root)
    let server = FakeSyncServer(), device = UUID()
    let line = stamped(server, collection: "drawings", id: "binance/usd_m/BTCUSDT/note",
                       ["symbol": .string("BTCUSDT"), "text": .string("顶背离")], revision: 4)
    server.seed(line)
    try store.receive(server.page(["drawings"]))
    // 这台服务器的 null 白名单里没有 `drawings/text`，清空文字被整条顶回来。
    server.refuse = { op in op.fields["text"] == .null ? "invalid_operation" : nil }

    var cleared = line; cleared.body["text"] = nil
    try store.capture(cleared, device: device)
    #expect(store.archive.operations.first?.fields["text"] == .null)
    let original = try #require(store.archive.operations.first?.id)

    let loop = try await engine(over: server, store, device: device).run(.push)
    // 1. 队列空了（不堵别人），`pending` 不含它。
    #expect(store.archive.operations.isEmpty)
    // 2. 用户的值没回退。
    #expect(store.archive.local[line.key]?.body["text"] == nil)
    #expect(store.archive.rejected.count == 1)
    #expect(store.archive.rejected.first?.reason == "invalid_operation")
    #expect(store.archive.rejected.first?.intent.body["text"] == nil)
    // 3. 云端那份（还带着旧文字）不许写回本地。
    try store.receive(server.page(["drawings"]))
    #expect(store.archive.local[line.key]?.body["text"] == nil)

    // 4. 重启之后记录还在，护栏也还在。
    await store.flush()
    store = try SyncStore(directory: root)
    #expect(store.archive.rejected.count == 1)
    #expect(store.archive.local[line.key]?.body["text"] == nil)
    try store.receive(server.page(["drawings"]))
    #expect(store.archive.local[line.key]?.body["text"] == nil)

    // 5. 服务端修好了：下一次全量自己用新 id 补推，不用用户再删一次。
    server.refuse = nil
    let next = try await engine(over: server, store, device: device).fullThenLeftovers("binance/usd_m/BTCUSDT/")
    #expect(server.objects[line.key]?.body["text"] == nil)
    #expect(store.archive.operations.isEmpty)
    #expect(store.archive.rejected.isEmpty)
    // 载荷重建走的是新 id：已经发出去过的那条 id 绝不能改载荷再发。
    #expect(next.batches == [1])
    #expect(store.archive.objects[line.key]?.body["text"] == nil)
    #expect(original != store.archive.rejected.first?.id)
  }

  /// 服务端一直不认时也不能无限加速：全量之间只补推一次，再被拒就再记一次。
  @Test func aStillBrokenServerJustGetsOneMoreTryPerFullSync() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), server = FakeSyncServer(), device = UUID()
    let line = stamped(server, collection: "drawings", id: "binance/usd_m/BTCUSDT/note",
                       ["symbol": .string("BTCUSDT"), "text": .string("顶背离")], revision: 4)
    server.seed(line)
    try store.receive(server.page(["drawings"]))
    server.refuse = { op in op.fields["text"] == .null ? "invalid_operation" : nil }
    var cleared = line; cleared.body["text"] = nil
    try store.capture(cleared, device: device)

    let loop = try await engine(over: server, store, device: device).run(.push)
    #expect(store.archive.rejected.count == 1)
    let again = try await engine(over: server, store, device: device).fullThenLeftovers("binance/usd_m/BTCUSDT/")
    #expect(again.batches == [1])                 // 一次全量只补推一条
    #expect(store.archive.rejected.count == 1)        // 又被拒，又记了一次，没堆起来
    #expect(store.archive.operations.isEmpty)
    #expect(store.archive.local[line.key]?.body["text"] == nil)
  }

  /// `dependsOn` 是本机字段。服务端的 `Operation` 是 `deny_unknown_fields`，
  /// 多一个键**整批 100 条**一起 400。
  @Test func theLocalDependencyLinkNeverReachesTheServer() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), device = UUID()
    var value = SyncObject(collection: "settings", id: "chart")
    value.body["skin"] = .string("moss")
    try store.capture(value, device: device)
    value.body["skin"] = .string("terra")
    try store.capture(value, device: device)
    // 本机这条链是有的。
    #expect(store.archive.operations[1].dependsOn == store.archive.operations[0].id)

    let data = try JSONEncoder.sorted.encode(SyncPushRequest(store.archive.operations))
    let text = try #require(String(data: data, encoding: .utf8))
    #expect(!text.contains("dependsOn"))
    // 而且键集合正好是服务端 `Operation` 认的那些。
    struct Body: Decodable { var operations: [[String: JSONValue]] }
    let keys = Set(try JSONDecoder().decode(Body.self, from: data).operations.flatMap(\.keys))
    #expect(keys == ["id", "collection", "objectId", "deviceId", "baseRevision", "generation",
                     "timestamp", "logical", "action", "fields"])
  }

  /// 这条链要活过重启，不然恢复路径在冷启动之后就瞎了。
  @Test func theDependencyLinkSurvivesARestart() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), device = UUID()
    var value = SyncObject(collection: "settings", id: "chart")
    value.body["skin"] = .string("moss"); try store.capture(value, device: device)
    value.body["skin"] = .string("terra"); try store.capture(value, device: device)
    await store.flush()
    let reopened = try SyncStore(directory: root)
    #expect(reopened.archive.operations[1].dependsOn == reopened.archive.operations[0].id)
  }

  /// 往存档里加字段不能把老用户的档案变成打不开的。
  @Test func anArchiveWrittenBeforeTheseFieldsStillOpens() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let legacy = """
    {"version":1,"operations":[{"id":"\(UUID().uuidString)","collection":"settings","objectId":"chart",\
    "deviceId":"\(UUID().uuidString)","baseRevision":0,"generation":0,"timestamp":1,"logical":1,\
    "action":"patch","fields":{"skin":"moss"}}],"sent":[],"objects":{},"local":{},"autoSync":true,\
    "logical":1,"offset":0}
    """
    try Data(legacy.utf8).write(to: root.appendingPathComponent("sync-v1.json"))
    let store = try SyncStore(directory: root)
    #expect(store.archive.operations.count == 1)
    #expect(store.archive.operations[0].dependsOn == nil)
    #expect(store.archive.rejected.isEmpty)
    #expect(store.archive.autoSync)
  }
}
