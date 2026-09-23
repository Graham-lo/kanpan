import Foundation
import Testing
@testable import KanpanAccount

/// 「只推不拉」的那一轮收尾：本机界面上已经有的东西，不再合并、落盘一遍。
///
/// App 层 `AppAccountBridge.run(.push)` 从前每一轮都 `markFetched` → `applyPending()`，
/// 后者要在主线程上跑两次阻塞落盘。纯推送那一轮 `local` 里通常只是本机刚刚写进去的值，
/// 那一整套是白做的。但回执会把服务端并好的对象写回 `local`——别的设备改过的字段会
/// 跟着回来——所以不能一律跳过：只有「这一轮云端没往 `local` 里带进任何新内容」才跳。
@MainActor @Suite("Push-only round skips the merge") struct PushOnlyRoundTests {
  private func temp() throws -> URL {
    let p = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true); return p
  }
  private func stamped(_ server: FakeSyncServer, _ body: [String: JSONValue], revision: Int64) -> SyncObject {
    var object = SyncObject(collection: "settings", id: "prefs")
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
  private func settled(_ store: SyncStore, _ server: FakeSyncServer) throws {
    try store.receive(server.page(["settings"]))
    try store.markFetched(at: 1_000)
    try store.markApplied(at: 1_000)
    #expect(!store.needsApply)
  }

  @Test func pushWhoseAckBringsNothingNewSkipsTheMerge() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), server = FakeSyncServer(), device = UUID()
    server.seed(stamped(server, ["theme": .string("moss"), "zoom": .number(1)], revision: 4))
    try settled(store, server)

    let mark = store.remoteArrivals
    var mine = try #require(store.archive.local["settings:prefs"])
    mine.body["theme"] = .string("clay")
    try store.capture(mine, device: device)
    var loop = SyncLoop(store: store, server: server, device: device)
    try loop.push()
    #expect(store.archive.operations.isEmpty)
    // 回执把服务端那份写回了 local，但内容和本机的一模一样（只是版本号抬了）。
    #expect(store.archive.local["settings:prefs"]?.revision == 5)
    #expect(store.remoteArrivals == mark)

    #expect(try store.finishPushOnlyRound(since: mark, at: 2_000) == false)
    #expect(store.archive.lastSync == 2_000)
    #expect(store.archive.lastApplied == 2_000)
    #expect(!store.needsApply)
  }

  /// 回执里带着别的设备刚改的字段：`local` 变了，这一轮必须照常合并。
  @Test func ackCarryingAnotherDevicesFieldStillMerges() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), server = FakeSyncServer(), device = UUID()
    server.seed(stamped(server, ["theme": .string("moss")], revision: 4))
    try settled(store, server)
    // 另一台设备在这期间往云端加了一个字段，本机还没拉过。
    server.seed(stamped(server, ["theme": .string("moss"), "zoom": .number(2)], revision: 5))

    let mark = store.remoteArrivals
    var mine = try #require(store.archive.local["settings:prefs"])
    mine.body["theme"] = .string("clay")
    try store.capture(mine, device: device)
    var loop = SyncLoop(store: store, server: server, device: device)
    try loop.push()
    #expect(store.archive.local["settings:prefs"]?.body["zoom"] == .number(2))
    #expect(store.remoteArrivals == mark &+ 1)

    #expect(try store.finishPushOnlyRound(since: mark, at: 2_000) == true)
    // 什么都没记：调用方会自己 markFetched + 合并。
    #expect(store.archive.lastSync == 1_000)
    #expect(store.archive.lastApplied == 1_000)
  }

  /// 上一批拉下来的还没装进本机（比如当时界面不让装），这一轮哪怕什么都没到也得合并。
  @Test func unappliedEarlierPullIsNotSwallowed() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), server = FakeSyncServer()
    server.seed(stamped(server, ["theme": .string("moss")], revision: 4))
    try store.receive(server.page(["settings"]))
    try store.markFetched(at: 1_000)
    #expect(store.needsApply)

    let mark = store.remoteArrivals
    #expect(try store.finishPushOnlyRound(since: mark, at: 2_000) == true)
    #expect(store.archive.lastSync == 1_000)
    #expect(store.needsApply)
  }

  /// 拉取也按「内容变没变」计：同一页再拉一遍不算到达，改了才算。
  @Test func receiveCountsOnlyRealChanges() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), server = FakeSyncServer()
    server.seed(stamped(server, ["theme": .string("moss")], revision: 4))
    try store.receive(server.page(["settings"]))
    let first = store.remoteArrivals
    #expect(first == 1)
    try store.receive(server.page(["settings"]))
    #expect(store.remoteArrivals == first)
    server.seed(stamped(server, ["theme": .string("clay")], revision: 5))
    try store.receive(server.page(["settings"]))
    #expect(store.remoteArrivals == first &+ 1)
    var gone = stamped(server, ["theme": .string("clay")], revision: 6); gone.deleted = true
    server.seed(gone)
    try store.receive(server.page(["settings"]))
    #expect(store.remoteArrivals == first &+ 2)
  }
}
