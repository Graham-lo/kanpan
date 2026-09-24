import Foundation
import Testing
@testable import KanpanAccount

/// 「装进本机」只装云端真的改过的那几张表（`SyncArchive.unapplied`）。
///
/// App 层 `AppAccountBridge.run` 从前每一轮都 `applyPending()`——全量合并四摊、主线程上两次
/// 阻塞落盘、再惊动一次宿主。纯推送那一轮 `local` 里通常只是本机刚刚写进去的值，那一整套
/// 是白做的；换品种拉画线那一轮，设置、自选、提醒也跟着重装一遍。但回执会把服务端并好的
/// 对象写回 `local`——别的设备改过的字段会跟着回来——所以不能按「这一轮拉没拉」一刀切，
/// 要按「`local` 里哪张表的内容真的变了」记账，而且这笔账要和 `local` 同一个事务落盘。
@MainActor @Suite("只装云端改过的那几张表") struct PushOnlyRoundTests {
  private func temp() throws -> URL {
    let p = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true); return p
  }
  private func stamped(_ server: FakeSyncServer, _ body: [String: JSONValue], revision: Int64,
                       collection: String = "settings", id: String = "prefs") -> SyncObject {
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
  /// 上一轮已经拉过、也装进本机了。
  private func settled(_ store: SyncStore, _ server: FakeSyncServer, _ collections: Set<String> = ["settings"]) throws {
    try store.receive(server.page(collections))
    try store.markApplied(at: 1_000, covering: store.archive.unapplied)
    #expect(!store.needsApply)
  }
  /// `local` 里每个对象的内容（版本号不算）。
  private func contents(_ store: SyncStore) -> [String: String] {
    store.archive.local.mapValues { "\($0.deleted)|\($0.body.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" })" }
  }

  @Test func pushWhoseAckBringsNothingNewLeavesNothingToApply() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), server = FakeSyncServer(), device = UUID()
    server.seed(stamped(server, ["theme": .string("moss"), "zoom": .number(1)], revision: 4))
    try settled(store, server)

    var mine = try #require(store.archive.local["settings:prefs"])
    mine.body["theme"] = .string("clay")
    try store.capture(mine, device: device)
    try await engine(over: server, store, device: device).run(.push)
    #expect(store.archive.operations.isEmpty)
    // 回执把服务端那份写回了 local，但内容和本机的一模一样（只是版本号抬了）。
    #expect(store.archive.local["settings:prefs"]?.revision == 5)
    #expect(store.archive.unapplied == [])
    #expect(!store.needsApply)
  }

  /// 回执里带着别的设备刚改的字段：`local` 变了，这张表（只有这张）要装。
  @Test func ackCarryingAnotherDevicesFieldMarksOnlyThatCollection() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), server = FakeSyncServer(), device = UUID()
    server.seed(stamped(server, ["theme": .string("moss")], revision: 4))
    server.seed(stamped(server, ["symbol": .string("BTCUSDT")], revision: 1, collection: "drawings", id: "binance/usd_m/BTCUSDT/a"))
    try settled(store, server, ["settings", "drawings"])
    // 另一台设备在这期间往云端加了一个字段，本机还没拉过。
    server.seed(stamped(server, ["theme": .string("moss"), "zoom": .number(2)], revision: 5))

    var mine = try #require(store.archive.local["settings:prefs"])
    mine.body["theme"] = .string("clay")
    try store.capture(mine, device: device)
    try await engine(over: server, store, device: device).run(.push)
    #expect(store.archive.local["settings:prefs"]?.body["zoom"] == .number(2))
    #expect(store.archive.unapplied == ["settings"])
    #expect(store.needsApply)
  }

  /// 上一批拉下来的还没装进本机（比如当时界面不让装），这一轮哪怕什么都没到，欠账也还在。
  @Test func unappliedEarlierPullIsNotSwallowed() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), server = FakeSyncServer(), device = UUID()
    server.seed(stamped(server, ["theme": .string("moss")], revision: 4))
    try store.receive(server.page(["settings"]))
    #expect(store.archive.unapplied == ["settings"])

    try store.markFetched(at: 2_000)
    try await engine(over: server, store, device: device).run(.push)
    #expect(store.archive.unapplied == ["settings"])
    #expect(store.needsApply)
  }

  /// 拉取也按「内容变没变」计：同一页再拉一遍不算，改了、删了才算。
  @Test func receiveMarksOnlyRealChanges() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), server = FakeSyncServer()
    server.seed(stamped(server, ["theme": .string("moss")], revision: 4))
    try store.receive(server.page(["settings"]))
    #expect(store.archive.unapplied == ["settings"])
    try store.markApplied(at: 1_000, covering: ["settings"])
    try store.receive(server.page(["settings"]))
    #expect(store.archive.unapplied == [])
    server.seed(stamped(server, ["theme": .string("clay")], revision: 5))
    try store.receive(server.page(["settings"]))
    #expect(store.archive.unapplied == ["settings"])
    try store.markApplied(at: 2_000, covering: ["settings"])
    var gone = stamped(server, ["theme": .string("clay")], revision: 6); gone.deleted = true
    server.seed(gone)
    try store.receive(server.page(["settings"]))
    #expect(store.archive.unapplied == ["settings"])
  }

  /// 欠账和 `local` 同一个事务落盘：拉到一半进程没了，重开照样知道哪张表欠着。
  @Test func theDebtSurvivesARestart() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let server = FakeSyncServer()
    server.seed(stamped(server, ["symbol": .string("BTCUSDT")], revision: 1, collection: "drawings", id: "binance/usd_m/BTCUSDT/a"))
    do {
      let store = try SyncStore(directory: root)
      try store.receive(server.page(["drawings"]))
      store.flushNow()
    }
    let reopened = try SyncStore(directory: root)
    #expect(reopened.archive.unapplied == ["drawings"])
    #expect(reopened.needsApply)
  }

  /// 装的时候只减掉装了的那几张；装之前（或装的同时）欠着的别的表照样欠着。
  @Test func applyingSomeCollectionsLeavesTheOthersOwed() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), server = FakeSyncServer()
    server.seed(stamped(server, ["theme": .string("moss")], revision: 1))
    server.seed(stamped(server, ["symbol": .string("BTCUSDT")], revision: 1, collection: "drawings", id: "binance/usd_m/BTCUSDT/a"))
    try store.receive(server.page(["settings", "drawings"]))
    #expect(store.archive.unapplied == ["settings", "drawings"])
    try store.markApplied(at: 1_000, covering: ["drawings"])
    #expect(store.archive.unapplied == ["settings"])
    try store.markApplied(at: 1_000)
    #expect(store.archive.unapplied == [])
  }

  /// 全量同步要一次整份合并：`markUnapplied(nil)` 之后「说不清」，装完才清。
  @Test func aFullRoundCanAskForEverything() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root)
    try store.markUnapplied(nil)
    #expect(store.archive.unapplied == nil)
    #expect(store.needsApply)
    // 「全部」里再并进一张也还是全部；只装一部分也不算装完。
    try store.markUnapplied(["drawings"])
    try store.markApplied(at: 1_000, covering: ["drawings"])
    #expect(store.archive.unapplied == nil)
    try store.markApplied(at: 1_000, covering: nil)
    #expect(store.archive.unapplied == [])
  }

  // MARK: - 深度审查 §9：纯推送之后 `applyPending` 是否还承担「把 realign 出的本地值落盘」

  /// 不承担。409 → 按品种前缀重拉 → `realign` → 重推这一整条恢复路径上，`local` 的内容
  /// 一个对象都没变过（`realign` 只改操作的版本元信息；重拉回来的那份被待发操作挡在
  /// `local` 外面；回执回来的就是本机的值），所以没有任何东西要装进本机。
  @Test func aConflictRealignRoundLeavesLocalUntouched() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), server = FakeSyncServer(), device = UUID()
    let seeded = stamped(server, ["symbol": .string("BTCUSDT"), "color": .string("amber")], revision: 4,
                         collection: "drawings", id: "binance/usd_m/BTCUSDT/a")
    server.seed(seeded)
    try settled(store, server, ["drawings"])
    var mine = seeded; mine.body["color"] = .string("teal")
    try store.capture(mine, device: device)
    let before = contents(store)
    // 另一台设备删了又恢复：代次 0 → 1，本机那条 patch 会被 409 顶回来。
    let b = UUID()
    func wire(_ action: String, base: Int64) -> WireOperation {
      WireOperation(SyncOperation(collection: "drawings", objectId: seeded.id, deviceId: b, baseRevision: base,
                                  generation: 0, timestamp: server.now - 1_000, logical: 1, action: action,
                                  fields: [:], importBatch: nil))
    }
    _ = try server.push([wire("delete", base: 4)]); _ = try server.push([wire("restore", base: 5)])

    let transport = ServerTransport(server)
    try await SyncEngine(store: store, transport: transport, device: device).run(.push)
    #expect(transport.bootstraps == [SyncScope("drawings", prefix: "binance/usd_m/BTCUSDT/")])   // 真的走了恢复路径
    #expect(store.archive.operations.isEmpty)
    #expect(server.objects[seeded.key]?.generation == 1)
    #expect(contents(store) == before)
    #expect(store.archive.unapplied == [])
    #expect(!store.needsApply)
  }

  /// 被服务端永久顶回来（400）的那条被隔离：`local` 仍是用户的值，同样没有要装的。
  @Test func aQuarantinedOperationLeavesLocalUntouched() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), server = FakeSyncServer(), device = UUID()
    server.seed(stamped(server, ["theme": .string("moss")], revision: 4))
    try settled(store, server)
    var mine = try #require(store.archive.local["settings:prefs"])
    mine.body["theme"] = .string("clay")
    try store.capture(mine, device: device)
    let before = contents(store)
    let transport = ServerTransport(server)
    transport.pushFailures = [AccountError.http(400, "invalid_field")]
    try await SyncEngine(store: store, transport: transport, device: device).run(.push)
    #expect(store.archive.operations.isEmpty)
    #expect(store.archive.rejected.count == 1)
    #expect(contents(store) == before)
    #expect(!store.needsApply)
  }

  /// 老存档里没有 `unapplied` 这个键：说不清就全装一次，装完才算清。
  @Test func anArchiveWrittenBeforeTheScopeExistedAppliesEverythingOnce() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let old = #"{"version":1,"operations":[],"sent":[],"objects":{},"local":{},"autoSync":true,"logical":0,"offset":0,"lastSync":900,"lastApplied":900}"#
    try Data(old.utf8).write(to: root.appendingPathComponent("sync-v1.json"))
    let store = try SyncStore(directory: root)
    #expect(store.archive.unapplied == nil)
    #expect(store.needsApply)
    try store.markApplied(at: 1_000, covering: store.archive.unapplied)
    #expect(!store.needsApply)
  }
}
