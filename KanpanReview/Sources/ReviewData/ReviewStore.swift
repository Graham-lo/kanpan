import Foundation
import ReviewDomain

public struct ReviewOperation: Codable, Sendable, Identifiable {
  public var id = UUID()
  public var recordId: UUID
  public var kind: String
  public var body: Data
  public var attempted: Bool?
  public init(recordId: UUID, kind: String, body: Data) { self.recordId = recordId; self.kind = kind; self.body = body }
}
public struct ReviewArchive: Codable, Sendable {
  public var version = 1
  public var draft: ReviewDraft?
  public var records: [ReviewRecord] = []
  public var queue: [ReviewOperation] = []
  public var replay: [String: ReviewReplayPosition] = [:]
  public var lastTab = "todo"
  public init() {}
}
public enum ReviewStorageError: LocalizedError {
  case unreadable
  public var errorDescription: String? { "复盘存档暂时无法读取，已保留原文件" }
}
/// A complete atomic archive is one transaction: a record and its upload cannot diverge.
@MainActor public final class ReviewStore {
  public private(set) var archive: ReviewArchive
  private let url: URL
  private let replayURL: URL
  private let draftURL: URL
  private struct DraftFile: Codable { var draft: ReviewDraft? }
  private var positions: [String: ReviewReplayPosition]
  public var cloudCache = false
  private var readable = true
  public init(directory: URL) throws {
    url = directory.appendingPathComponent("review-v1.json")
    replayURL = directory.appendingPathComponent("replay-positions.json")
    draftURL = directory.appendingPathComponent("draft-v1.json")
    if FileManager.default.fileExists(atPath: replayURL.path) { positions = try JSONDecoder().decode([String: ReviewReplayPosition].self, from: Data(contentsOf: replayURL)) } else { positions = [:] }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: url.path) {
      let value = try JSONDecoder().decode(ReviewArchive.self, from: Data(contentsOf: url))
      guard value.version == 1 else { throw ReviewStorageError.unreadable }
      archive = value
    } else { archive = ReviewArchive() }
    if FileManager.default.fileExists(atPath: draftURL.path) {
      let saved = try JSONDecoder().decode(DraftFile.self, from: Data(contentsOf: draftURL)).draft
      archive.draft = saved.flatMap { value in archive.records.contains(where: { $0.id == value.id }) ? nil : value }
    }
  }
  public func saveDraft(_ value: ReviewDraft?) throws {
    try JSONEncoder().encode(DraftFile(draft: value)).write(to: draftURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    archive.draft = value
  }
  public func transaction(_ edit: (inout ReviewArchive) throws -> Void) throws {
    guard readable else { throw ReviewStorageError.unreadable }
    // Recheck before writing: never overwrite a future version or externally corrupted file.
    if FileManager.default.fileExists(atPath: url.path) {
      guard let current = try? JSONDecoder().decode(ReviewArchive.self, from: Data(contentsOf: url)), current.version == 1 else {
        readable = false; throw ReviewStorageError.unreadable
      }
    }
    var next = archive; try edit(&next)
    if cloudCache {
      let protected = Set(next.queue.map(\.recordId))
      var bytes = 0, count = 0
      next.records = try next.records.filter { record in
        if record.serverId == nil || protected.contains(record.id) { return true }
        let size = try JSONEncoder().encode(record).count
        if count >= 200 || bytes + size > 12 * 1024 * 1024 { return false }
        count += 1; bytes += size; return true
      }
    }
    let data = try JSONEncoder().encode(next)
    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    archive = next
  }
  public func saveReplay(_ id: UUID, position: ReviewReplayPosition) throws {
    var next = positions; next[id.uuidString] = position
    if next.count > 500, let key = next.keys.sorted().first(where: { $0 != id.uuidString }) { next.removeValue(forKey: key) }
    try JSONEncoder().encode(next).write(to: replayURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    positions = next
  }
  public func savedReplay(_ id: UUID) -> ReviewReplayPosition? { positions[id.uuidString] ?? archive.replay[id.uuidString] }

}
