import Foundation

public struct SyncObject: Codable, Sendable, Equatable {
  public var collection: String
  public var id: String
  public var body: [String: JSONValue]
  public var fields: [String: JSONValue]
  public var revision: Int64
  public var deleted: Bool
  public var generation: Int64
  public var key: String { collection + ":" + id }
  public init(collection: String, id: String) {
    self.collection = collection; self.id = id; body = [:]; fields = [:]; revision = 0; deleted = false; generation = 0
  }
}
public struct SyncOperation: Codable, Sendable, Identifiable {
  public var id = UUID()
  public var collection: String
  public var objectId: String
  public var deviceId: UUID
  public var baseRevision: Int64
  public var generation: Int64
  public var timestamp: Int64
  public var logical: UInt64
  public var action: String
  public var fields: [String: JSONValue]
  public var importBatch: UUID?
}
public struct SyncResult: Codable, Sendable { public var operationId: UUID; public var object: SyncObject; public var cursor: Int64 }
public struct SyncPushResponse: Codable, Sendable { public var results: [SyncResult]; public var serverTime: Int64 }
public struct SyncPage: Codable, Sendable { public var objects: [SyncObject]; public var next: String?; public var cursor: Int64; public var serverTime: Int64 }
public struct SyncArchive: Codable, Sendable {
  public var version = 1
  public var operations: [SyncOperation] = []
  public var sent: Set<UUID> = []
  public var objects: [String: SyncObject] = [:]
  public var local: [String: SyncObject] = [:]
  public var autoSync = true
  public var lastSync: Int64?
  public var logical: UInt64 = 0
  public var offset: Int64 = 0
}
@MainActor public final class SyncStore {
  public private(set) var archive: SyncArchive
  private let url: URL
  public init(directory: URL) throws {
    url = directory.appendingPathComponent("sync-v1.json")
    archive = try AccountFiles.read(SyncArchive.self, at: url) ?? SyncArchive()
    guard archive.version == 1 else { throw AccountError.storage }
  }
  public func transaction(_ edit: (inout SyncArchive) throws -> Void) throws {
    if let disk = try AccountFiles.read(SyncArchive.self, at: url), disk.version != 1 { throw AccountError.storage }
    var next = archive; try edit(&next); try AccountFiles.write(next, to: url); archive = next
  }
  /// Record only actual field changes. Uncertain requests are immutable; retry them with their original ID.
  public func capture(_ value: SyncObject, device: UUID, importing batch: UUID? = nil) throws {
    let previous = archive.local[value.key]
    guard previous?.body != value.body || previous?.deleted != value.deleted else { return }
    let base = archive.objects[value.key] ?? SyncObject(collection: value.collection, id: value.id)
    if batch != nil && base.deleted { return }
    var changed = value.body.filter { previous?.body[$0.key] != $0.value }
    for key in previous?.body.keys ?? Dictionary<String, JSONValue>().keys where value.body[key] == nil { changed[key] = .null }
    let action = value.deleted ? "delete" : (previous?.deleted == true || base.deleted) ? "restore" : "patch"
    let op = SyncOperation(collection: value.collection, objectId: value.id, deviceId: device,
      baseRevision: base.revision, generation: base.generation, timestamp: Int64(Date().timeIntervalSince1970 * 1000) + archive.offset,
      logical: archive.logical + 1, action: action, fields: changed, importBatch: batch)
    try transaction { $0.logical += 1; $0.operations.append(op); $0.local[value.key] = value }
  }
  public func markSent(_ id: UUID) throws { try transaction { $0.sent.insert(id) } }
  public func acknowledge(_ response: SyncPushResponse) throws {
    try transaction { a in
      a.offset = response.serverTime - Int64(Date().timeIntervalSince1970 * 1000)
      for result in response.results {
        a.objects[result.object.key] = result.object
        a.operations.removeAll { $0.id == result.operationId }; a.sent.remove(result.operationId)
        // Operations behind this ACK have not been sent; advance causal base without changing uncertain requests.
        for index in a.operations.indices where !a.sent.contains(a.operations[index].id) && a.operations[index].collection == result.object.collection && a.operations[index].objectId == result.object.id {
          a.operations[index].baseRevision = result.object.revision
          a.operations[index].generation = result.object.generation
        }
        if !a.operations.contains(where: { $0.collection == result.object.collection && $0.objectId == result.object.id }) { a.local[result.object.key] = result.object }
      }
    }
  }
  public func receive(_ page: SyncPage) throws {
    try transaction { a in
      a.offset = page.serverTime - Int64(Date().timeIntervalSince1970 * 1000)
      for object in page.objects {
        a.objects[object.key] = object
        if !a.operations.contains(where: { $0.collection == object.collection && $0.objectId == object.id }) { a.local[object.key] = object }
      }
    }
  }
}
