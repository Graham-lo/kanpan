import Foundation
import Testing
@testable import KanpanAccount

// MARK: - 录回放的假传输层

/// 把 `FakeSyncServer`（`sync.rs` 的 `merge()` / `push()` 复刻）接成一条 `SyncTransport`。
///
/// 真服务端在 HTTP 这一层还有几件 `merge()` 管不到的事，这里一并模拟：
/// 请求体超过 `DefaultBodyLimit` 回 413、按 collection / prefix / after 分页的 bootstrap、
/// 以及任意一次请求上「插一个错误」（410 `cursor_expired`、断网……）。
/// 每次请求都记进 `log`，用例拿它断言「发了什么、按什么顺序」。
@MainActor final class ServerTransport: SyncTransport {
  enum Call: Equatable, CustomStringConvertible {
    case push(Int, bytes: Int, status: Int)
    case bootstrap(SyncScope, after: String?)
    var description: String {
      switch self {
      case .push(let n, let bytes, let status): "push \(n) ops \(bytes)B → \(status)"
      case .bootstrap(let scope, let after): "bootstrap \(scope)" + (after.map { " after \($0)" } ?? "")
      }
    }
  }
  let server: FakeSyncServer
  /// 服务端能收的最大请求体（真服务端是 512 KiB）。`nil` 表示不限。
  var bodyLimit: Int?
  /// bootstrap 每页最多几个对象。
  var pageSize = 500
  /// 按顺序消费的插入错误：`push` 一队、`bootstrap` 一队。
  var pushFailures: [any Error] = []
  var bootstrapFailures: [any Error] = []
  /// 这些线上字段服务端认了这条操作、却没收下（`droppedFields`）。
  var dropFields: Set<String> = []
  /// 每次 push 回来之前调一下（用来模拟「请求在路上时账号换了」）。
  var beforeReply: (@MainActor () -> Void)?
  private(set) var log: [Call] = []

  init(_ server: FakeSyncServer) { self.server = server }

  var pushes: [Call] { log.filter { if case .push = $0 { true } else { false } } }
  var bootstraps: [SyncScope] { log.compactMap { if case .bootstrap(let s, nil) = $0 { s } else { nil } } }

  /// 推送体的解码镜像：`WireOperation` 只有 `Encodable`，服务端那一侧的解码在这儿补上，
  /// 键集合和 `sync.rs` 的 `Operation` 一致（多一个键就解不出来，和 `deny_unknown_fields` 同性质）。
  private struct Body: Decodable { var operations: [Op] }
  private struct Op: Decodable {
    var id: UUID, collection: String, objectId: String, deviceId: UUID, baseRevision: Int64, generation: Int64
    var timestamp: Int64, logical: UInt64, action: String, fields: [String: JSONValue], importBatch: UUID?
    var wire: WireOperation {
      WireOperation(SyncOperation(id: id, collection: collection, objectId: objectId, deviceId: deviceId,
                                  baseRevision: baseRevision, generation: generation, timestamp: timestamp,
                                  logical: logical, action: action, fields: fields, importBatch: importBatch))
    }
  }

  func push(_ body: Data, key: UUID) async throws -> SyncPushResponse {
    let operations = try JSONDecoder().decode(Body.self, from: body).operations.map(\.wire)
    #expect(operations.first?.id == key)          // 幂等键就是这一批第一条的 id
    func record(_ status: Int) { log.append(.push(operations.count, bytes: body.count, status: status)) }
    if !pushFailures.isEmpty {
      let error = pushFailures.removeFirst()
      if case AccountError.http(let code, _) = error { record(code) } else { record(0) }
      throw error
    }
    if let limit = bodyLimit, body.count > limit { record(413); throw AccountError.http(413, "payload_too_large") }
    do {
      var response = try server.push(operations)
      record(200)
      if !dropFields.isEmpty {
        response.results = response.results.map { r in
          var r = r; r.droppedFields = operations.first { $0.id == r.operationId }
            .map { Array($0.fields.keys.filter(dropFields.contains)).sorted() }; return r
        }
      }
      beforeReply?()
      return response
    } catch FakeSyncServer.Failure.conflict(let reason) {
      record(409); throw AccountError.http(409, reason)
    } catch FakeSyncServer.Failure.bad(let reason) {
      record(400); throw AccountError.http(400, reason)
    }
  }

  func bootstrap(collection: String, prefix: String?, after: String?) async throws -> SyncPage {
    log.append(.bootstrap(SyncScope(collection, prefix: prefix), after: after))
    if !bootstrapFailures.isEmpty { throw bootstrapFailures.removeFirst() }
    let all = server.objects.values
      .filter { o in o.collection == collection && (prefix.map { o.id.hasPrefix($0) } ?? true) && (after.map { o.id > $0 } ?? true) }
      .sorted { $0.id < $1.id }
    let slice = Array(all.prefix(pageSize))
    return SyncPage(objects: slice, next: all.count > slice.count ? slice.last?.id : nil,
                    cursor: server.cursor, serverTime: server.now)
  }
}

// MARK: - 特征测试

/// `SyncEngine` 的特征测试：搬家之前 `AppAccountBridge.run` 怎么推、怎么拉、谁赢，
/// 搬完之后一个字都不能变。每条都走真的 `SyncStore` + 按 `sync.rs` 复刻的服务端，
/// 中间只隔一条会录请求的假传输层。
@MainActor @Suite("同步引擎：推 / 拉 / 谁赢") struct SyncEngineTests {
  private func temp() throws -> URL {
    let p = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true); return p
  }
  private func stamped(_ server: FakeSyncServer, _ collection: String, _ id: String,
                       _ body: [String: JSONValue], revision: Int64 = 1) -> SyncObject {
    var object = SyncObject(collection: collection, id: id)
    object.body = body; object.revision = revision
    for key in body.keys {
      object.fields[key] = FakeSyncServer.Stamp(revision: revision, timestamp: server.now - 600_000, logical: 1,
                                                deviceId: "00000000-0000-0000-0000-000000000000",
                                                operationId: "00000000-0000-0000-0000-000000000000").json
    }
    return object
  }
  private struct Rig {
    let root: URL, store: SyncStore, server: FakeSyncServer, transport: ServerTransport, engine: SyncEngine, device: UUID
  }
  private func rig() throws -> Rig {
    let root = try temp()
    let store = try SyncStore(directory: root), server = FakeSyncServer(), device = UUID()
    let transport = ServerTransport(server)
    return Rig(root: root, store: store, server: server, transport: transport,
               engine: SyncEngine(store: store, transport: transport, device: device), device: device)
  }
  private func line(_ n: Int, text: String = "") -> SyncObject {
    var o = SyncObject(collection: "drawings", id: "binance/usd_m/BTCUSDT/\(n)")
    o.body = ["symbol": .string("BTCUSDT"), "text": .string(text)]; return o
  }

  // MARK: 正常推

  @Test func aPushRoundSendsOneBatchAndPullsNothing() async throws {
    let r = try rig(); defer { try? FileManager.default.removeItem(at: r.root) }
    var chart = SyncObject(collection: "settings", id: "chart")
    chart.body = ["skin": .string("moss"), "barSpacing": .number(6)]
    try r.store.capture(chart, device: r.device)
    for n in 0..<3 { try r.store.capture(line(n), device: r.device) }
    var pushed: (Set<String>, Set<String>)?
    r.engine.onPushed = { pushed = ($0, $1) }

    let outcome = try await r.engine.run(.push)
    #expect(r.store.archive.operations.isEmpty)
    #expect(r.store.archive.sent.isEmpty)
    #expect(outcome.batches == [4])
    #expect(outcome.pulled.isEmpty)
    #expect(r.transport.bootstraps.isEmpty)
    #expect(outcome.acked == ["skin", "barSpacing"])
    #expect(outcome.dropped.isEmpty)
    #expect(pushed?.0 == outcome.acked)
    #expect(r.server.objects["settings:chart"]?.body["skin"] == .string("moss"))
    // 回执里的对象就是服务端合并之后那份：本机记账跟上了 revision。
    #expect(r.store.archive.objects["settings:chart"]?.revision == 1)
  }

  // MARK: 413 / 字节预算

  @Test func a413HalvesTheBudgetAndStillDeliversEverything() async throws {
    let r = try rig(); defer { try? FileManager.default.removeItem(at: r.root) }
    let text = String(repeating: "注", count: 300)               // 每条约 1 KiB
    for n in 0..<40 { try r.store.capture(line(n, text: text), device: r.device) }
    r.transport.bodyLimit = 20 * 1024

    let outcome = try await r.engine.run(.push)
    #expect(r.store.archive.operations.isEmpty)
    #expect(r.store.archive.rejected.isEmpty)
    #expect(r.server.objects.count == 40)
    guard case .push(40, _, 413)? = r.transport.pushes.first else {
      Issue.record("第一批应当整批发出去并吃一个 413：\(r.transport.log)"); return
    }
    // 413 那批一条都没落库，也就没被当成「已发」卡住。
    let delivered = r.transport.pushes.compactMap { if case .push(let n, let b, 200) = $0 { (n, b) } else { nil } }
    #expect(delivered.map(\.0).reduce(0, +) == 40)
    #expect(delivered.allSatisfy { $0.1 <= 20 * 1024 })
    #expect(outcome.batches.count == r.transport.pushes.count)
  }

  @Test func theByteBudgetSplitsBatchesBeforeTheServerHasToSayNo() async throws {
    let r = try rig(); defer { try? FileManager.default.removeItem(at: r.root) }
    let text = String(repeating: "注", count: 300)
    for n in 0..<30 { try r.store.capture(line(n, text: text), device: r.device) }
    r.engine.batchBytes = 8 * 1024

    let outcome = try await r.engine.run(.push)
    #expect(r.store.archive.operations.isEmpty)
    #expect(outcome.batches.count > 1)
    #expect(outcome.batches.reduce(0, +) == 30)
    #expect(r.transport.pushes.allSatisfy { if case .push(_, let b, 200) = $0 { b <= 8 * 1024 } else { false } })
  }

  @Test func aSingleOperationOverTheBudgetIsQuarantinedWithoutBeingSent() async throws {
    let r = try rig(); defer { try? FileManager.default.removeItem(at: r.root) }
    var chart = SyncObject(collection: "settings", id: "chart")
    chart.body = ["note": .string(String(repeating: "x", count: 4096))]
    try r.store.capture(chart, device: r.device)
    try r.store.capture(line(1), device: r.device)
    r.engine.batchBytes = 2 * 1024

    let outcome = try await r.engine.run(.push)
    #expect(r.store.archive.operations.isEmpty)
    #expect(r.store.archive.rejected.map(\.reason) == ["payload_too_large"])
    #expect(outcome.dropped == ["note"])
    #expect(outcome.batches == [1])                              // 大的那条根本没上路
    #expect(r.server.objects["settings:chart"] == nil)
    #expect(r.server.objects["drawings:binance/usd_m/BTCUSDT/1"] != nil)
    // 本地值不回退。
    #expect(r.store.archive.local["settings:chart"]?.body["note"] == chart.body["note"])
  }

  // MARK: 410 / 重新 bootstrap

  @Test func cursorExpiredAsksForABootstrapAndTheNextFullRoundRecovers() async throws {
    let r = try rig(); defer { try? FileManager.default.removeItem(at: r.root) }
    r.server.seed(stamped(r.server, "favorites", "binance/usd_m/ETHUSDT", ["order": .number(1)]))
    var chart = SyncObject(collection: "settings", id: "chart"); chart.body = ["skin": .string("terra")]
    try r.store.capture(chart, device: r.device)
    r.transport.bootstrapFailures = [AccountError.http(410, "cursor_expired")]
    var pushedBeforePull = false
    r.engine.onPushed = { acked, _ in pushedBeforePull = acked == ["skin"] && r.transport.bootstraps.isEmpty }

    await #expect(throws: AccountError.http(410, "cursor_expired")) { try await r.engine.run(.full(drawingsPrefix: nil)) }
    #expect(SyncEngine.demandsBootstrap(AccountError.http(410, "cursor_expired")))
    // 推上去的那一半不因为拉取失败而作废：脏标记在拉之前就交出去了。
    #expect(pushedBeforePull)
    #expect(r.store.archive.operations.isEmpty)
    #expect(r.store.archive.objects["favorites:binance/usd_m/ETHUSDT"] == nil)

    let outcome = try await r.engine.run(.full(drawingsPrefix: nil))
    #expect(outcome.pulled == SyncEngine.scopes(for: .full(drawingsPrefix: nil)))
    #expect(r.store.archive.local["favorites:binance/usd_m/ETHUSDT"]?.body["order"] == .number(1))
  }

  @Test func whichErrorsAskForABootstrap() {
    #expect(SyncEngine.demandsBootstrap(AccountError.http(409, "resync_required")))
    #expect(SyncEngine.demandsBootstrap(AccountError.http(400, "invalid_operation")))
    #expect(!SyncEngine.demandsBootstrap(AccountError.http(401, "unauthorized")))
    #expect(!SyncEngine.demandsBootstrap(AccountError.http(429, "rate_limited")))
    #expect(!SyncEngine.demandsBootstrap(AccountError.http(503, "unavailable")))
    #expect(!SyncEngine.demandsBootstrap(URLError(.notConnectedToInternet)))
    #expect(!SyncEngine.isPermanent(.http(409, "resync_required")))
    #expect(SyncEngine.isPermanent(.http(409, "idempotency_mismatch")))
    #expect(SyncEngine.isPermanent(.http(422, "x")))
    #expect(!SyncEngine.isPermanent(.http(410, "cursor_expired")))
  }

  @Test func aNetworkErrorLeavesTheBatchSentAndItGoesOutAgainUnderTheSameID() async throws {
    let r = try rig(); defer { try? FileManager.default.removeItem(at: r.root) }
    var chart = SyncObject(collection: "settings", id: "chart"); chart.body = ["skin": .string("terra")]
    try r.store.capture(chart, device: r.device)
    let id = try #require(r.store.archive.operations.first?.id)
    r.transport.pushFailures = [URLError(.networkConnectionLost)]

    await #expect(throws: URLError.self) { try await r.engine.run(.push) }
    #expect(r.store.archive.sent == [id])                        // 结果不明：原 id 原载荷重发
    try await r.engine.run(.push)
    #expect(r.store.archive.operations.isEmpty)
    #expect(r.server.objects["settings:chart"]?.body["skin"] == .string("terra"))
  }

  // MARK: 409 / 重拉重整

  @Test func aGenerationBumpIsRefetchedByInstrumentPrefixAndRealigned() async throws {
    let r = try rig(); defer { try? FileManager.default.removeItem(at: r.root) }
    let seeded = stamped(r.server, "drawings", "binance/usd_m/BTCUSDT/a",
                         ["symbol": .string("BTCUSDT"), "color": .string("amber")], revision: 4)
    r.server.seed(seeded)
    r.server.seed(stamped(r.server, "drawings", "binance/usd_m/ETHUSDT/b", ["symbol": .string("ETHUSDT")]))
    try r.store.receive(r.server.page(["drawings"]))
    var mine = seeded; mine.body["color"] = .string("teal")
    try r.store.capture(mine, device: r.device)
    // 另一台设备删了又恢复：代次 0 → 1。
    let b = UUID()
    func wire(_ action: String, base: Int64) -> WireOperation {
      WireOperation(SyncOperation(collection: "drawings", objectId: seeded.id, deviceId: b, baseRevision: base,
                                  generation: 0, timestamp: r.server.now - 1_000, logical: 1, action: action,
                                  fields: [:], importBatch: nil))
    }
    _ = try r.server.push([wire("delete", base: 4)]); _ = try r.server.push([wire("restore", base: 5)])

    try await r.engine.run(.push)
    #expect(r.store.archive.operations.isEmpty)
    #expect(r.transport.bootstraps == [SyncScope("drawings", prefix: "binance/usd_m/BTCUSDT/")])
    #expect(r.server.objects[seeded.key]?.body["color"] == .string("teal"))
    #expect(r.server.objects[seeded.key]?.generation == 1)
    #expect(r.store.archive.local[seeded.key]?.body["color"] == .string("teal"))
  }

  @Test func refetchScopesGroupByCollectionAndInstrument() {
    func op(_ c: String, _ id: String) -> SyncOperation {
      SyncOperation(collection: c, objectId: id, deviceId: UUID(), baseRevision: 0, generation: 0, timestamp: 0,
                    logical: 0, action: "patch", fields: [:], importBatch: nil)
    }
    let scopes = SyncEngine.refetchScopes([op("drawings", "binance/usd_m/BTCUSDT/a"), op("drawings", "binance/usd_m/BTCUSDT/b"),
                                           op("drawings", "okx/spot/ETH-USDT/c"), op("favorites", "x"), op("favorites", "y"),
                                           op("drawings", "loose")])
    #expect(scopes == [SyncScope("drawings"), SyncScope("drawings", prefix: "binance/usd_m/BTCUSDT/"),
                       SyncScope("drawings", prefix: "okx/spot/ETH-USDT/"), SyncScope("favorites")])
  }

  // MARK: 谁赢

  @Test func aCleanFieldTakesTheCloudValue() async throws {
    let r = try rig(); defer { try? FileManager.default.removeItem(at: r.root) }
    r.server.seed(stamped(r.server, "settings", "chart", ["skin": .string("moss")]))
    try await r.engine.run(.full(drawingsPrefix: nil))
    #expect(r.store.archive.local["settings:chart"]?.body["skin"] == .string("moss"))
    // 另一台设备改了，本机没碰过：云端那份照收。
    var b = r.server.objects["settings:chart"]!; b.body["skin"] = .string("terra"); r.server.seed(b)
    try await r.engine.run(.full(drawingsPrefix: nil))
    #expect(r.store.archive.local["settings:chart"]?.body["skin"] == .string("terra"))
  }

  @Test func aPendingLocalValueIsNotOverwrittenByAPull() async throws {
    let r = try rig(); defer { try? FileManager.default.removeItem(at: r.root) }
    r.server.seed(stamped(r.server, "settings", "chart", ["skin": .string("moss")]))
    try await r.engine.run(.full(drawingsPrefix: nil))
    var mine = r.store.archive.local["settings:chart"]!; mine.body["skin"] = .string("classic")
    try r.store.capture(mine, device: r.device)
    var b = r.server.objects["settings:chart"]!; b.body["skin"] = .string("terra"); r.server.seed(b)
    // 推不上去（断网），拉却拉到了：待发操作还在，本地说了算。
    r.transport.pushFailures = [URLError(.timedOut)]
    await #expect(throws: URLError.self) { try await r.engine.run(.full(drawingsPrefix: nil)) }
    try r.store.receive(r.server.page(["settings"]))
    #expect(r.store.archive.local["settings:chart"]?.body["skin"] == .string("classic"))
    #expect(r.store.archive.objects["settings:chart"]?.body["skin"] == .string("terra"))
  }

  /// 同一个字段两边都改了：服务端按时间戳判，客户端不替它猜，而且分批边界不改变赢家（B5）。
  @Test(arguments: [1, 100, 101]) func theLaterWriterWinsRegardlessOfBatching(_ count: Int) async throws {
    let r = try rig(); defer { try? FileManager.default.removeItem(at: r.root) }
    r.server.seed(stamped(r.server, "settings", "chart", ["barSpacing": .number(4)]))
    try r.store.receive(r.server.page(["settings"]))
    var mine = r.store.archive.local["settings:chart"]!
    for step in 1...count { mine.body["barSpacing"] = .number(Double(4 + step)); try r.store.capture(mine, device: r.device) }
    _ = try r.server.push([WireOperation(SyncOperation(
      collection: "settings", objectId: "chart", deviceId: UUID(), baseRevision: 1, generation: 0,
      timestamp: r.server.now + 200_000, logical: 1, action: "patch", fields: ["barSpacing": .number(999)], importBatch: nil))])

    let outcome = try await r.engine.run(.push)
    #expect(r.store.archive.operations.isEmpty)
    #expect(outcome.batches.count == (count + 99) / 100)
    #expect(r.server.objects["settings:chart"]?.body["barSpacing"] == .number(999))
    #expect(r.store.archive.local["settings:chart"]?.body["barSpacing"] == .number(999))
  }

  // MARK: 语义错误

  @Test func aPermanentErrorIsIsolatedOneByOne() async throws {
    let r = try rig(); defer { try? FileManager.default.removeItem(at: r.root) }
    for n in 0..<3 { try r.store.capture(line(n, text: n == 1 ? "坏" : "好"), device: r.device) }
    r.server.refuse = { $0.fields["text"] == .string("坏") ? "invalid_operation" : nil }

    let outcome = try await r.engine.run(.push)
    #expect(outcome.batches == [3, 1, 1, 1])
    #expect(r.store.archive.operations.isEmpty)
    #expect(r.store.archive.rejected.map(\.objectId) == ["binance/usd_m/BTCUSDT/1"])
    #expect(r.server.objects.count == 2)
    #expect(r.store.archive.local["drawings:binance/usd_m/BTCUSDT/1"]?.body["text"] == .string("坏"))
  }

  @Test func droppedFieldsAreReportedAsNotLanded() async throws {
    let r = try rig(); defer { try? FileManager.default.removeItem(at: r.root) }
    var chart = SyncObject(collection: "settings", id: "chart")
    chart.body = ["skin": .string("moss"), "barSpacing": .number(7)]
    try r.store.capture(chart, device: r.device)
    r.transport.dropFields = ["barSpacing"]
    let outcome = try await r.engine.run(.push)
    #expect(outcome.acked == ["skin"])
    #expect(outcome.dropped == ["barSpacing"])
  }

  // MARK: 档位

  @Test func eachPlanPullsExactlyItsScopes() async throws {
    let r = try rig(); defer { try? FileManager.default.removeItem(at: r.root) }
    r.server.seed(stamped(r.server, "drawings", "binance/usd_m/BTCUSDT/a", ["symbol": .string("BTCUSDT")]))
    r.server.seed(stamped(r.server, "drawings", "binance/usd_m/ETHUSDT/b", ["symbol": .string("ETHUSDT")]))
    r.transport.pageSize = 1

    try await r.engine.run(.drawings(prefix: "binance/usd_m/BTCUSDT/"))
    #expect(r.transport.bootstraps == [SyncScope("drawings", prefix: "binance/usd_m/BTCUSDT/")])
    #expect(r.store.archive.local["drawings:binance/usd_m/BTCUSDT/a"] != nil)
    #expect(r.store.archive.local["drawings:binance/usd_m/ETHUSDT/b"] == nil)

    let full = try await r.engine.run(.full(drawingsPrefix: "binance/usd_m/ETHUSDT/"))
    #expect(full.pulled.map(\.collection) == ["settings", "drawingPreferences", "favorites", "groups", "alerts", "drawings"])
    #expect(r.store.archive.local["drawings:binance/usd_m/ETHUSDT/b"] != nil)
    #expect(SyncEngine.scopes(for: .push).isEmpty)
  }

  @Test func paginationFollowsNextUntilTheEnd() async throws {
    let r = try rig(); defer { try? FileManager.default.removeItem(at: r.root) }
    for n in 0..<5 { r.server.seed(stamped(r.server, "favorites", "binance/usd_m/S\(n)", ["order": .number(Double(n))])) }
    r.transport.pageSize = 2
    try await r.engine.run(.full(drawingsPrefix: nil))
    #expect(r.store.archive.local.keys.filter { $0.hasPrefix("favorites:") }.count == 5)
    #expect(r.transport.log.filter { if case .bootstrap(SyncScope("favorites"), _) = $0 { true } else { false } }.count == 3)
  }

  @Test func onlyTheFullPlanRetriesRejectedOperations() async throws {
    let r = try rig(); defer { try? FileManager.default.removeItem(at: r.root) }
    try r.store.capture(line(1, text: "坏"), device: r.device)
    r.server.refuse = { _ in "invalid_operation" }
    try await r.engine.run(.push)
    #expect(r.store.archive.rejected.count == 1)
    r.server.refuse = nil

    let push = try await r.engine.run(.drawings(prefix: "binance/usd_m/BTCUSDT/"))
    #expect(!push.leftovers)
    #expect(r.store.archive.operations.isEmpty && r.store.archive.rejected.count == 1)

    let full = try await r.engine.run(.full(drawingsPrefix: nil))
    // 全量拉完之后用新 id 重新记了一条，但不在这一轮里推：留给调用方再排一轮推送。
    #expect(full.leftovers)
    #expect(r.store.archive.operations.count == 1)
    try await r.engine.run(.push)
    #expect(r.server.objects["drawings:binance/usd_m/BTCUSDT/1"]?.body["text"] == .string("坏"))
    #expect(r.store.archive.rejected.isEmpty)
  }

  // MARK: 这一轮不算数了

  @Test func aRoundThatStoppedCountingAcknowledgesNothing() async throws {
    let r = try rig(); defer { try? FileManager.default.removeItem(at: r.root) }
    var chart = SyncObject(collection: "settings", id: "chart"); chart.body = ["skin": .string("terra")]
    try r.store.capture(chart, device: r.device)
    var current = true
    r.engine.stillCurrent = { current }
    r.transport.beforeReply = { current = false }       // 请求在路上的时候退登 / 换了账号
    var pushedCalled = false
    r.engine.onPushed = { _, _ in pushedCalled = true }

    await #expect(throws: CancellationError.self) { try await r.engine.run(.full(drawingsPrefix: nil)) }
    #expect(r.store.archive.operations.count == 1)       // 回执没进存档
    #expect(r.store.archive.objects["settings:chart"] == nil)
    #expect(!pushedCalled)
    #expect(r.transport.bootstraps.isEmpty)
  }
}

// MARK: - 给别的用例用的接线

/// 一台按 `sync.rs` 复刻的假服务端上的真引擎。
@MainActor func engine(over server: FakeSyncServer, _ store: SyncStore, device: UUID,
                       owning: [String: Set<String>] = [:]) -> SyncEngine {
  SyncEngine(store: store, transport: ServerTransport(server), device: device, owning: owning)
}
@MainActor extension SyncEngine {
  /// 全量一档，再加上桥上那句「补推留下的，跑完接着推」（`AppAccountBridge.run` 的 `queuedPush`）。
  func fullThenLeftovers(_ drawingsPrefix: String?) async throws -> Outcome {
    var outcome = try await run(.full(drawingsPrefix: drawingsPrefix))
    guard outcome.leftovers else { return outcome }
    outcome.batches += try await run(.push).batches
    return outcome
  }
}
