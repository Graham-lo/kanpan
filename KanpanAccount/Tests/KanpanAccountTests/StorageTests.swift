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
  @Test func uncertainOperationsKeepIdentityAndPayload() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root); let device = UUID()
    var object = SyncObject(collection: "drawings", id: "BTCUSDT/a"); object.body["color"] = .string("red")
    try store.capture(object, device: device)
    let first = try #require(store.archive.operations.first); try store.markSent(first.id)
    object.body["color"] = .string("blue"); try store.capture(object, device: device)
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
  @Test func offlineDeleteThenUndoRetainsExplicitRestoreAfterRestart() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root); let device = UUID()
    var line = SyncObject(collection: "drawings", id: "BTCUSDT/line")
    line.body["color"] = .string("amber"); line.revision = 4
    try store.receive(SyncPage(objects: [line], next: nil, cursor: 4, serverTime: 0))
    line.deleted = true; try store.capture(line, device: device)
    let deletion = try #require(store.archive.operations.first)
    line.deleted = false; try store.capture(line, device: device)
    let restored = try SyncStore(directory: root)
    #expect(restored.archive.operations.map(\.action) == ["delete", "restore"])
    line.deleted = true; line.revision = 5
    try restored.acknowledge(SyncPushResponse(results: [SyncResult(operationId: deletion.id, object: line, cursor: 5)], serverTime: 0))
    let undo = try #require(restored.archive.operations.first)
    #expect(undo.action == "restore"); #expect(undo.baseRevision == 5)
    #expect(restored.archive.local[line.key]?.deleted == false)
  }

}
