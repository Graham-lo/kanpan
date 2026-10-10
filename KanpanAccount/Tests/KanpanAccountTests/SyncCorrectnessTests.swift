import Foundation
import Testing
@testable import KanpanAccount

/// 审查 2026-10-10 的同步正确性几项，逐条钉住：
/// 1. 记在别的设备号名下的操作（冷启动恢复会话之前记的、退出后离线改的再登回来）照样推得上去；
/// 2. 补推被拒操作只补被拒的那几项，别的设备之后的改动不许被冻住的旧值盖回去；
/// 3. 设置里值不对的那一项只丢那一项，客户端认云端那份、不无限重发；不认识的字段不打转；
/// 5. 单条的毛病只隔离那一条（新服务端的单条拒绝格），设备号不对的改记重发、绝不隔离。
@MainActor @Suite("同步正确性（审查 2026-10-10）") struct SyncCorrectnessTests {
  private let chartKey = "settings:chart"
  private func temp() throws -> URL {
    let p = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true); return p
  }
  private func stamped(_ server: FakeSyncServer, _ collection: String, _ id: String,
                       _ body: [String: JSONValue], revision: Int64) -> SyncObject {
    var object = SyncObject(collection: collection, id: id)
    object.body = body; object.revision = revision
    for key in body.keys {
      object.fields[key] = FakeSyncServer.Stamp(revision: revision, timestamp: server.now - 600_000, logical: 1,
                                                deviceId: "00000000-0000-0000-0000-000000000000",
                                                operationId: "00000000-0000-0000-0000-000000000000").json
    }
    return object
  }
  private func chart(_ body: [String: JSONValue]) -> SyncObject {
    var value = SyncObject(collection: "settings", id: "chart"); value.body = body; return value
  }
  private func line(_ server: FakeSyncServer, _ n: Int) -> SyncObject {
    stamped(server, "drawings", "binance/usd_m/BTCUSDT/n\(n)", ["symbol": .string("BTCUSDT"), "text": .string("旧")], revision: 2)
  }
  private func seeded(_ root: URL, _ server: FakeSyncServer, _ objects: [SyncObject]) throws -> SyncStore {
    let store = try SyncStore(directory: root)
    objects.forEach(server.seed)
    try store.receive(server.page(Set(objects.map(\.collection))))
    return store
  }

  // MARK: - 1 设备号

  /// 冷启动：会话还没恢复出来，用户先改了一笔，记在一个旧设备号名下；恢复之后推送要照样过，
  /// 不许被当成坏操作隔离（从前每次启动设备号都是新的，这一笔永远 `invalid_device`）。
  @Test(arguments: [false, true]) func anEditRecordedBeforeTheSessionCameBackStillLands(_ inline: Bool) async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let server = FakeSyncServer(), session = UUID(), stale = UUID()
    server.device = session; server.inline = inline
    let store = try seeded(root, server, [stamped(server, "settings", "chart", ["barSpacing": .number(6)], revision: 1)])
    try store.capture(chart(["barSpacing": .number(9)]), device: stale)
    #expect(store.archive.operations.first?.deviceId == stale)

    let loop = try await engine(over: server, store, device: session).run(.push)
    #expect(loop.batches == [1])
    #expect(store.archive.operations.isEmpty)
    #expect(store.archive.rejected.isEmpty, "设备号对不上被当成坏操作隔离了")
    #expect(server.objects[chartKey]?.body["barSpacing"] == .number(9))
    #expect(loop.acked == ["barSpacing"])
  }

  /// 退出登录之前发出去、没等到回话的那一条（`sent`），离线又改了一笔，重启后登回同一个号：
  /// 已发的那条不在开头改设备号（它可能已经落库），服务端说「设备不对、没落库」之后再改记重发。
  /// 老服务端整批 400，新服务端只拒那一格——两条路都要推空、一条都不隔离。
  @Test(arguments: [false, true]) func aSentOperationUnderTheOldDeviceIsReassignedNotQuarantined(_ inline: Bool) async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let server = FakeSyncServer(), session = UUID(), stale = UUID()
    server.device = session; server.inline = inline
    let lines = [line(server, 0), line(server, 1)]
    let store = try seeded(root, server, lines)
    var first = lines[0]; first.body["text"] = .string("退出前")
    try store.capture(first, device: stale)
    let sentID = try #require(store.archive.operations.first?.id)
    try store.markSent(sentID)                                      // 发出去了、回话没到
    var second = lines[1]; second.body["text"] = .string("离线改的")
    try store.capture(second, device: stale)

    let loop = try await engine(over: server, store, device: session).run(.push)
    // 老服务端：整批顶回 → 改记 → 整批再发；新服务端：只拒已发那条 → 它改记后单独再发。
    #expect(loop.batches == (inline ? [2, 1] : [2, 2]))
    #expect(store.archive.operations.isEmpty)
    #expect(store.archive.sent.isEmpty)
    #expect(store.archive.rejected.isEmpty)
    #expect(server.objects[lines[0].key]?.body["text"] == .string("退出前"))
    #expect(server.objects[lines[1].key]?.body["text"] == .string("离线改的"))
  }

  /// 会话那台设备本身和引擎手上的不一样（改不动任何一条）：那不是操作的错，队列原样留着，不隔离。
  @Test(arguments: [false, true]) func aSessionOnAnotherDeviceLeavesTheQueueAlone(_ inline: Bool) async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let server = FakeSyncServer(), mine = UUID()
    server.device = UUID(); server.inline = inline
    let store = try seeded(root, server, [line(server, 0)])
    var edited = line(server, 0); edited.body["text"] = .string("新")
    try store.capture(edited, device: mine)

    let engine = engine(over: server, store, device: mine)
    if inline {
      let loop = try await engine.run(.push)
      #expect(loop.batches == [1])
    } else {
      await #expect(throws: AccountError.http(400, "invalid_device")) { try await engine.run(.push) }
    }
    #expect(store.archive.operations.count == 1)
    #expect(store.archive.sent.isEmpty)
    #expect(store.archive.rejected.isEmpty)
  }

  /// `adoptDevice`：未发的全改，已发的一条不动。
  @Test func adoptDeviceOnlyTouchesUnsentOperations() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let server = FakeSyncServer(), stale = UUID(), session = UUID()
    let store = try seeded(root, server, [line(server, 0), line(server, 1)])
    for n in 0..<2 { var edited = line(server, n); edited.body["text"] = .string("新"); try store.capture(edited, device: stale) }
    let sent = try #require(store.archive.operations.first?.id)
    try store.markSent(sent)
    #expect(try store.adoptDevice(session) == 1)
    #expect(store.archive.operations.map(\.deviceId) == [stale, session])
    #expect(try store.adoptDevice(session) == 0)
  }

  // MARK: - 2 补推只补被拒的那几项

  /// A 改了皮肤与颜色，被拒；B 之后改了皮肤（同一项）和柱宽（另一项）；A 补推时 B 的两项都得留着，
  /// A 只补颜色，沿用被拒那一刻的时间戳。
  @Test func aRetryKeepsWhatAnotherDeviceChangedMeanwhile() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let server = FakeSyncServer(), a = UUID(), b = UUID()
    let store = try seeded(root, server, [stamped(server, "settings", "chart",
      ["skin": .string("moss"), "barSpacing": .number(6), "color": .string("a")], revision: 1)])
    server.refuse = { op in op.fields["skin"] == .string("terra") ? "invalid_operation" : nil }
    try store.capture(chart(["skin": .string("terra"), "barSpacing": .number(6), "color": .string("b")]), device: a)
    let original = try #require(store.archive.operations.first)
    #expect(Set(original.fields.keys) == ["skin", "color"])
    _ = try await engine(over: server, store, device: a).run(.push)
    #expect(store.archive.rejected.count == 1)

    // B（另一台设备）在 A 被拒之后改了皮肤与柱宽。
    let byB = SyncOperation(collection: "settings", objectId: "chart", deviceId: b, baseRevision: 1, generation: 0,
                            timestamp: original.timestamp + 1_000, logical: 1, action: "patch",
                            fields: ["skin": .string("ink"), "barSpacing": .number(9)])
    _ = try server.push([WireOperation(byB)])
    server.refuse = nil

    let engine = engine(over: server, store, device: a)
    var settled: [Set<String>] = []
    engine.onPushed = { acked, _ in settled.append(acked) }
    _ = try await engine.run(.full(drawingsPrefix: nil))
    let retry = try #require(store.archive.operations.first)
    #expect(retry.fields == ["color": .string("b")], "补推带上了被拒之后别人改过的项：\(retry.fields)")
    #expect(retry.timestamp == original.timestamp)
    #expect(retry.logical == original.logical)
    #expect(retry.id != original.id)
    #expect(settled.contains { $0.contains("skin") }, "按云端了结的那一项要交给脏标记那一层放手")
    // 记账里那一项已经换成云端的（装进本机时跟上），柱宽这段时间被挡在外面也要放进来。
    #expect(store.archive.local[chartKey]?.body["skin"] == .string("ink"))

    _ = try await engine.run(.push)
    let cloud = try #require(server.objects[chartKey])
    #expect(cloud.body["skin"] == .string("ink"))
    #expect(cloud.body["barSpacing"] == .number(9))
    #expect(cloud.body["color"] == .string("b"))
    #expect(store.archive.rejected.isEmpty)
    #expect(store.archive.operations.isEmpty)
    #expect(store.archive.local[chartKey]?.body == cloud.body)
  }

  /// B 改的恰好就是被拒的那几项：什么都不补，记录了结，本机跟上云端。
  @Test func aRetryWhoseFieldsAllMovedOnIsDropped() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let server = FakeSyncServer(), a = UUID(), b = UUID()
    let store = try seeded(root, server, [stamped(server, "settings", "chart",
      ["skin": .string("moss"), "barSpacing": .number(6)], revision: 1)])
    server.refuse = { op in op.fields["skin"] == .string("terra") ? "invalid_operation" : nil }
    try store.capture(chart(["skin": .string("terra"), "barSpacing": .number(6)]), device: a)
    let original = try #require(store.archive.operations.first)
    _ = try await engine(over: server, store, device: a).run(.push)
    _ = try server.push([WireOperation(SyncOperation(collection: "settings", objectId: "chart", deviceId: b,
      baseRevision: 1, generation: 0, timestamp: original.timestamp + 1_000, logical: 1, action: "patch",
      fields: ["skin": .string("ink"), "barSpacing": .number(9)]))])
    server.refuse = nil

    let outcome = try await engine(over: server, store, device: a).run(.full(drawingsPrefix: nil))
    #expect(!outcome.leftovers)
    #expect(store.archive.operations.isEmpty)
    #expect(store.archive.rejected.isEmpty)
    #expect(store.archive.local[chartKey]?.body == server.objects[chartKey]?.body)
    #expect(store.archive.unapplied?.contains("settings") == true)
  }

  // MARK: - 3 值不对 / 不认识的字段

  /// 值不对的那一项：服务端丢掉它、照收其余；客户端把它当了结（清脏标记），记账认云端那份，
  /// 再记一遍手上的云端值不生出新操作——不会每半秒重发一次。
  @Test func anInvalidSettingsValueSettlesOnTheCloudValue() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let server = FakeSyncServer(), device = UUID()
    server.invalidValue = { path, value in path == "skin" && value == .string("neon") }
    let store = try seeded(root, server, [stamped(server, "settings", "chart",
      ["skin": .string("moss"), "barSpacing": .number(6)], revision: 1)])
    try store.markApplied(at: 1)
    try store.capture(chart(["skin": .string("neon"), "barSpacing": .number(8)]), device: device)

    let loop = try await engine(over: server, store, device: device).run(.push)
    #expect(loop.acked == ["skin", "barSpacing"])
    #expect(loop.dropped.isEmpty)
    #expect(server.objects[chartKey]?.body["skin"] == .string("moss"))
    #expect(server.objects[chartKey]?.body["barSpacing"] == .number(8))
    #expect(store.archive.local[chartKey]?.body["skin"] == .string("moss"))
    #expect(store.archive.unapplied?.contains("settings") == true, "本机要装上云端那份，两边才对得上")
    #expect(store.archive.rejected.isEmpty)
    // 桥上 `applyPending` 装上云端那份（`markApplied`）之后再记账：没有东西可推。
    try store.markApplied(at: 2)
    try store.capture(chart(["skin": .string("moss"), "barSpacing": .number(8)]), device: device)
    #expect(store.archive.operations.isEmpty)
  }

  /// 不认识的那一项：脏标记照旧留着（dropped），记账叠回本机的值，同一份再记一遍不生出新操作。
  @Test func anUnknownFieldDoesNotLoop() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let server = FakeSyncServer(), device = UUID()
    server.unknownFields = ["glow"]
    let store = try seeded(root, server, [stamped(server, "settings", "chart", ["barSpacing": .number(6)], revision: 1)])
    let mine = chart(["barSpacing": .number(6), "glow": .bool(true)])
    try store.capture(mine, device: device)

    let loop = try await engine(over: server, store, device: device).run(.push)
    #expect(loop.dropped == ["glow"])
    #expect(!loop.acked.contains("glow"))
    #expect(server.objects[chartKey]?.body["glow"] == nil)
    #expect(store.archive.local[chartKey]?.body["glow"] == .bool(true))
    try store.capture(mine, device: device)
    #expect(store.archive.operations.isEmpty, "不认识的字段每记一次账就生出一条新操作：死循环")
  }

  // MARK: - 5 单条拒绝

  /// 新服务端：一批里一条有毛病只拒那一条，其余一次落地，不再对半切。
  @Test func anInlineRejectionQuarantinesOnlyThatOperation() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let server = FakeSyncServer(), device = UUID()
    server.inline = true
    let lines = (0..<3).map { line(server, $0) }
    let store = try seeded(root, server, lines)
    server.refuse = { op in op.fields["text"] == .string("坏") ? "symbol" : nil }
    for (n, value) in ["好", "坏", "也好"].enumerated() {
      var edited = lines[n]; edited.body["text"] = .string(value); try store.capture(edited, device: device)
    }
    let bad = store.archive.operations[1].id

    let loop = try await engine(over: server, store, device: device).run(.push)
    #expect(loop.batches == [3])
    #expect(store.archive.operations.isEmpty)
    #expect(store.archive.sent.isEmpty)
    #expect(store.archive.rejected.map(\.id) == [bad])
    #expect(store.archive.rejected.first?.reason == "symbol")
    #expect(server.objects[lines[0].key]?.body["text"] == .string("好"))
    #expect(server.objects[lines[2].key]?.body["text"] == .string("也好"))
  }

  /// 回话解码：一格回执、一格拒绝混在 `results` 里；`invalidFields` 老服务端不给也能解。
  @Test func thePushResponseSplitsReceiptsFromRejections() throws {
    let ok = UUID(), bad = UUID()
    let json = """
    {"results":[
      {"operationId":"\(ok.uuidString)","object":{"collection":"settings","id":"chart","body":{},"fields":{},
       "revision":2,"deleted":false,"generation":0},"cursor":7,"droppedFields":["skin","glow"],"invalidFields":["skin"]},
      {"operationId":"\(bad.uuidString)","status":"rejected","code":"invalid_device","message":"设备不对"}
    ],"serverTime":5}
    """
    let response = try JSONDecoder().decode(SyncPushResponse.self, from: Data(json.utf8))
    #expect(response.results.map(\.operationId) == [ok])
    #expect(response.results.first?.invalidFields == ["skin"])
    #expect(response.rejections == [SyncRejection(operationId: bad, code: "invalid_device", message: "设备不对")])
    let old = #"{"results":[],"serverTime":1}"#
    #expect(try JSONDecoder().decode(SyncPushResponse.self, from: Data(old.utf8)).rejections.isEmpty)
  }

  @Test func thePushGoesOutWithInlineRejections() {
    #expect(HTTPSyncTransport.pushPath == "v1/sync/operations?rejections=inline")
  }
}
