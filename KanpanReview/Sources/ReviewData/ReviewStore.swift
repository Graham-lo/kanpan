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
  /// 上一次「我们自己」写下去的那份存档的指纹（改动时间 + 字节数）。见 `transaction`。
  private var stamp: FileStamp?
  /// 每条记录编码后有多大。`cloudCache` 那趟裁剪要按字节数算，但记录本身
  /// 大多数时候一个字段都没动，没必要每次整条重编一遍。
  private var sizes: [UUID: (record: ReviewRecord, size: Int)] = [:]
  private struct FileStamp: Equatable { var date: Date; var size: Int }
  /// 重温进度的节流（见 `saveReplay`）。
  private static let replayThrottle: TimeInterval = 2
  private var replayPending: Task<Void, Never>?
  private var replayWrittenAt = Date.distantPast
  private var replayDirty = false

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
      stamp = Self.fingerprint(url)
    } else { archive = ReviewArchive() }
    if FileManager.default.fileExists(atPath: draftURL.path) {
      let saved = try JSONDecoder().decode(DraftFile.self, from: Data(contentsOf: draftURL)).draft
      archive.draft = saved.flatMap { value in archive.records.contains(where: { $0.id == value.id }) ? nil : value }
    }
  }
  public func saveDraft(_ value: ReviewDraft?) throws {
    try JSONEncoder().encode(DraftFile(draft: value)).write(to: draftURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    archive.draft = value
    // 这一步多半意味着「从重温里出来了」，顺手把攒着的进度结掉。
    try? flushReplay()
  }

  /// 文件的指纹。只 stat，不读内容。
  private static func fingerprint(_ url: URL) -> FileStamp? {
    guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
          let date = values.contentModificationDate, let size = values.fileSize else { return nil }
    return FileStamp(date: date, size: size)
  }
  public func transaction(_ edit: (inout ReviewArchive) throws -> Void) throws {
    guard readable else { throw ReviewStorageError.unreadable }
    // Recheck before writing: never overwrite a future version or externally corrupted file.
    //
    // 原来是**每次写之前**把整份存档从盘上重读一遍再解码一遍——几百条记录的 JSON，
    // 只为了确认「还是 version 1」。这条保护针对的是「文件被别人换过」，而不是
    // 「文件本来就是我们写的」：所以先 stat 一下，指纹和上次我们自己写下去的那份
    // 对得上就直接写，对不上（或者压根没记过）才真去读一遍。
    if FileManager.default.fileExists(atPath: url.path) {
      let now = Self.fingerprint(url)
      if stamp == nil || now == nil || now != stamp {
        guard let current = try? JSONDecoder().decode(ReviewArchive.self, from: Data(contentsOf: url)), current.version == 1 else {
          readable = false; throw ReviewStorageError.unreadable
        }
        stamp = now
      }
    }
    var next = archive; try edit(&next)
    if cloudCache {
      let protected = Set(next.queue.map(\.recordId))
      var bytes = 0, count = 0
      var measured: [UUID: (record: ReviewRecord, size: Int)] = [:]
      next.records = try next.records.filter { record in
        if record.serverId == nil || protected.contains(record.id) { return true }
        // 这一条和上次量过的那份一模一样就沿用上次的字节数。
        let size: Int
        if let hit = sizes[record.id], hit.record == record { size = hit.size }
        else { size = try JSONEncoder().encode(record).count }
        measured[record.id] = (record, size)
        if count >= 200 || bytes + size > 12 * 1024 * 1024 { return false }
        count += 1; bytes += size; return true
      }
      sizes = measured
    }
    let data = try JSONEncoder().encode(next)
    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    stamp = Self.fingerprint(url)
    archive = next
    try? flushReplay()
  }

  /// 记下重温进度。
  ///
  /// 重温每走一根 K 线都会回报一次，而原来每回报一次就把整份进度表（最多 500 条）
  /// 编码一遍、原子写一次盘——4 倍速播一分钟就是几百次整表写，全压在主线程上。
  ///
  /// 现在是「第一笔立刻写，之后 2 秒最多一次」：进度只是个书签，差两秒的书签和
  /// 差一根 K 线的书签，用户看不出区别；而停下来、离开重温、或者任何一次别的落盘
  /// （`saveDraft` / `transaction`）都会顺手把攒着的那一笔结掉，所以「记到哪儿了」
  /// 不会丢。
  public func saveReplay(_ id: UUID, position: ReviewReplayPosition) throws {
    var next = positions; next[id.uuidString] = position
    if next.count > 500, let key = next.keys.sorted().first(where: { $0 != id.uuidString }) { next.removeValue(forKey: key) }
    positions = next
    replayDirty = true
    let wait = Self.replayThrottle - Date().timeIntervalSince(replayWrittenAt)
    guard wait > 0 else { try flushReplay(); return }
    guard replayPending == nil else { return }
    replayPending = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
      guard let self, !Task.isCancelled else { return }
      self.replayPending = nil
      try? self.flushReplay()
    }
  }

  /// 把攒着的重温进度立刻写下去。停止播放 / 离开重温时调，没攒着东西就是空操作。
  public func flushReplay() throws {
    replayPending?.cancel(); replayPending = nil
    guard replayDirty else { return }
    replayDirty = false
    replayWrittenAt = Date()
    try JSONEncoder().encode(positions).write(to: replayURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
  public func savedReplay(_ id: UUID) -> ReviewReplayPosition? { positions[id.uuidString] ?? archive.replay[id.uuidString] }

}
