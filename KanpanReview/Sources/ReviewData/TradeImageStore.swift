import CryptoKit
import Foundation

/// 复盘本缩略图的盘上那份（体感优化 2026-10-07）：滚复盘本不再一格一格现画。
///
/// * 位置：宿主给的根（`Library/Caches/kanpan/trade-images`）下按档案再分一层（档案目录路径的
///   摘要），不同账号的单子不串；
/// * 名字：`TradeImagePolicy.diskKey` 的 SHA-256，一张一个文件；
/// * 封顶：整棵根目录 `maxBytes`（默认 16 MB，缩略图一张几 KB，够几千张），超了按最近使用
///   （读写都刷新）从最久没用的删起，删到 3/4。
/// 放在 Caches 下、不进备份：没了重新画就有，「清缓存」一并清。
public actor TradeImageStore {
  public static let defaultMaxBytes = 16 * 1024 * 1024

  public nonisolated let root: URL
  public nonisolated let directory: URL
  public nonisolated let maxBytes: Int
  private var index: [String: Entry]?
  private struct Entry { var url: URL; var bytes: Int; var used: Date }

  /// - Parameter profile: 这份档案的标识（复盘档案目录的路径就行），只取摘要做目录名。
  public init(root: URL, profile: String, maxBytes: Int = TradeImageStore.defaultMaxBytes) {
    self.root = root
    self.directory = root.appendingPathComponent(String(Self.digest(profile).prefix(16)), isDirectory: true)
    self.maxBytes = maxBytes
  }

  public func read(_ key: String) -> Data? {
    let url = file(key)
    guard let data = try? Data(contentsOf: url) else { return nil }
    touch(url)
    return data
  }

  /// 一次读一批（复盘本打开时把手上这些单子的缩略图一起翻出来，界面只刷一次）。
  public func read(_ keys: [String]) -> [String: Data] {
    var out: [String: Data] = [:]
    for key in keys { if let data = read(key) { out[key] = data } }
    return out
  }

  public func write(_ key: String, data: Data) {
    let url = file(key)
    // 「清缓存」刚把整棵删了：索引跟着重扫，别对着不存在的文件算用量。
    if !FileManager.default.fileExists(atPath: directory.path) { index = nil }
    buildIndex()
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
      var values = URLResourceValues(); values.isExcludedFromBackup = true
      var mutable = url; try? mutable.setResourceValues(values)
    } catch { return }
    index?[Self.key(url)] = Entry(url: url, bytes: data.count, used: Date())
    evict(keeping: url)
  }

  public func totalBytes() -> Int { buildIndex().values.reduce(0) { $0 + $1.bytes } }

  // MARK: -

  private func file(_ key: String) -> URL {
    directory.appendingPathComponent(Self.digest(key) + ".img")
  }

  private static func digest(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private static func key(_ url: URL) -> String { url.resolvingSymlinksInPath().path }

  private func touch(_ url: URL) {
    let now = Date()
    try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
    if var entry = index?[Self.key(url)] { entry.used = now; index?[Self.key(url)] = entry }
  }

  @discardableResult
  private func buildIndex() -> [String: Entry] {
    if let index { return index }
    var built: [String: Entry] = [:]
    let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
    if let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) {
      for case let file as URL in walker where file.pathExtension == "img" {
        let v = try? file.resourceValues(forKeys: Set(keys))
        guard v?.isRegularFile == true else { continue }
        built[Self.key(file)] = Entry(url: file, bytes: v?.fileSize ?? 0, used: v?.contentModificationDate ?? .distantPast)
      }
    }
    index = built
    return built
  }

  private func evict(keeping keep: URL) {
    guard var idx = index else { return }
    var total = idx.values.reduce(0) { $0 + $1.bytes }
    guard total > maxBytes else { return }
    let target = maxBytes * 3 / 4
    let kept = Self.key(keep)
    for (k, entry) in idx.sorted(by: { $0.value.used < $1.value.used }) where total > target && k != kept {
      try? FileManager.default.removeItem(at: entry.url)
      idx[k] = nil
      total -= entry.bytes
    }
    index = idx
  }
}
