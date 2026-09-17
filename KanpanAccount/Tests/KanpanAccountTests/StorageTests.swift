import Foundation
import Testing
@testable import KanpanAccount

@MainActor @Suite("Account durability and isolation") struct StorageTests {
  private func temp() throws -> URL { let p = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true); return p }
  @Test func guestClaimSurvivesRestartAndCannotMoveToB() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let a = UUID(), b = UUID(); var files = try AccountFiles(root: root)
    let original = try files.directory(user: nil); try Data("guest-record".utf8).write(to: original.appendingPathComponent("review.json"))
    let first = try #require(try files.claimGuest(user: a)); files = try AccountFiles(root: root)
    #expect(try files.claimGuest(user: a)?.id == first.id)
    #expect(try files.claimGuest(user: b) == nil)
    #expect(try files.directory(user: nil) != original)
    #expect(throws: AccountError.self) { try files.completeGuestClaim(user: b, batch: first.id) }
    try files.completeGuestClaim(user: a, batch: first.id)
    files = try AccountFiles(root: root)
    #expect(try files.pendingGuest(user: a) == nil)
    #expect(FileManager.default.fileExists(atPath: original.appendingPathComponent("review.json").path))
  }
  @Test func unreadableRegistryIsNotOverwritten() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("registry.json"); let bad = Data("broken".utf8); try bad.write(to: url)
    #expect(throws: (any Error).self) { try AccountFiles(root: root) }
    #expect(try Data(contentsOf: url) == bad)
  }
  @Test func uncertainOperationsKeepIdentityAndPayload() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root); let device = UUID()
    var object = SyncObject(collection: "drawings", id: "BTCUSDT/a"); object.body["color"] = .string("red")
    try store.capture(object, device: device)
    let first = try #require(store.archive.operations.first); try store.markSent(first.id)
    object.body["color"] = .string("blue"); try store.capture(object, device: device)
    // 落盘挪到后台队列了，"重开一遍存档"之前得等它写完。
    await store.flush()
    let reopened = try SyncStore(directory: root)
    #expect(reopened.archive.operations.count == 2)
    #expect(try JSONEncoder().encode(reopened.archive.operations[0]).count == JSONEncoder().encode(first).count)
    #expect(reopened.archive.operations[0].fields["color"] == .string("red"))
    object.revision = 1; object.body["color"] = .string("red")
    let response = SyncPushResponse(results: [SyncResult(operationId: first.id, object: object, cursor: 3)], serverTime: Int64(Date().timeIntervalSince1970 * 1000))
    try reopened.acknowledge(response)
    #expect(reopened.archive.operations.count == 1)
    #expect(reopened.archive.operations[0].baseRevision == 1)
    #expect(reopened.archive.local[object.key]?.body["color"] == .string("blue"))
  }
  @Test func offlineDeleteThenUndoRetainsExplicitRestoreAfterRestart() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root); let device = UUID()
    var line = SyncObject(collection: "drawings", id: "BTCUSDT/line")
    line.body["color"] = .string("amber"); line.revision = 4
    try store.receive(SyncPage(objects: [line], next: nil, cursor: 4, serverTime: 0))
    line.deleted = true; try store.capture(line, device: device)
    let deletion = try #require(store.archive.operations.first)
    line.deleted = false; try store.capture(line, device: device)
    await store.flush()
    let restored = try SyncStore(directory: root)
    #expect(restored.archive.operations.map(\.action) == ["delete", "restore"])
    line.deleted = true; line.revision = 5
    try restored.acknowledge(SyncPushResponse(results: [SyncResult(operationId: deletion.id, object: line, cursor: 5)], serverTime: 0))
    let undo = try #require(restored.archive.operations.first)
    #expect(undo.action == "restore"); #expect(undo.baseRevision == 5)
    #expect(restored.archive.local[line.key]?.deleted == false)
  }


  @Test func batchedCaptureWritesOnce() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root); let device = UUID()
    var batch: [SyncObject] = []
    for index in 0..<20 {
      var value = SyncObject(collection: "favorites", id: "s\(index)")
      value.body["symbol"] = .string("S\(index)"); value.body["order"] = .number(Double(index))
      batch.append(value)
    }
    try store.capture(batch, device: device)
    await store.flush()
    #expect(store.archive.operations.count == 20)
    #expect(store.writeCount == 1)
    // 逐条走的话是 20 次整档重写。
    var again = batch
    for index in again.indices { again[index].body["order"] = .number(Double(index + 100)) }
    try store.capture(again, device: device)
    await store.flush()
    #expect(store.archive.operations.count == 40)
    #expect(store.writeCount == 2)
    let reopened = try SyncStore(directory: root)
    #expect(reopened.archive.operations.count == 40)
    #expect(reopened.archive.local["favorites:s0"]?.body["order"] == .number(100))
  }
  @Test func capturesWithoutChangesDoNotWrite() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root); let device = UUID()
    var value = SyncObject(collection: "settings", id: "chart"); value.body["theme"] = .string("moss")
    try store.capture(value, device: device)
    await store.flush()
    #expect(store.writeCount == 1)
    try store.capture(value, device: device)
    try store.capture([value, value], device: device)
    await store.flush()
    #expect(store.writeCount == 1)
    #expect(store.archive.operations.count == 1)
  }
  @Test func orderedWritesLandInOrderAndLastOneIsReadable() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root); let device = UUID()
    // 连续 50 次事务全部排到后台串行队列，盘上必须是最后一次的完整快照。
    for index in 1...50 {
      var value = SyncObject(collection: "settings", id: "chart")
      value.body["tick"] = .number(Double(index))
      try store.capture(value, device: device)
    }
    #expect(store.archive.operations.count == 50)
    await store.flush()
    #expect(store.writeCount == 50)
    let reopened = try SyncStore(directory: root)
    #expect(reopened.archive.operations.count == 50)
    #expect(reopened.archive.operations.map(\.logical) == Array(1...50).map(UInt64.init))
    #expect(reopened.archive.local["settings:chart"]?.body["tick"] == .number(50))
  }
  @Test func lastWriteBeforeATeardownIsReadable() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let device = UUID()
    do {
      let store = try SyncStore(directory: root)
      var value = SyncObject(collection: "favorites", id: "btc")
      value.body["symbol"] = .string("BTCUSDT")
      try store.capture(value, device: device)
      try store.transaction { $0.lastSync = 1234 }
      // 模拟"进程要没了"：同步排空，不靠 await。
      store.flushNow()
    }
    let reopened = try SyncStore(directory: root)
    #expect(reopened.archive.lastSync == 1234)
    #expect(reopened.archive.local["favorites:btc"]?.body["symbol"] == .string("BTCUSDT"))
    #expect(reopened.archive.operations.count == 1)
  }
}
