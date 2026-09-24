import Foundation
import KanpanCore

/// 画线的落盘（A7.7：按品种持久化，杀 app 重开仍在）。
///
/// 存档本身（`DrawArchive`：分桶、上限、逐条容错解码）是 KanpanCore 里的纯模型；
/// 这里只管它在磁盘上的那一份。从前整个文件放在 Core——当年 `KanpanData/` 有别人在改、
/// 不能碰，于是暂放 Core；审查 24 把文件 IO 请出 Core，挪到用它的 app 画线模块旁边
/// （唯一的调用方是 `DrawingController` 与账号桥），测试在 `KanpanTests/Main/DrawStoreTests.swift`。
///
/// 画线是用户的东西，必须永久留着，所以走 Application Support（会进 iCloud 备份、
/// 系统不会自己清），不是 K 线快照那个 `Caches/`。

/// 一份 JSON 文件，整存整取。
///
/// 不做增量：画线全部加起来也就几 KB，一次写完最省事，也不会写到一半断电留下半份。
struct DrawStore: Sendable {
  var url: URL

  init(url: URL) { self.url = url }

  /// 默认位置：`Application Support/kanpan/draws.json`。
  ///
  /// UI 用例要的是「这一轮跑的画线别落到用户自己那份档案里」，于是有一道
  /// `KANPAN_TEST_PROFILE=1` + `KANPAN_PERSISTENCE_PROFILE=<UUID>` 的岔路。
  /// 那道岔路**只在 DEBUG 构建里存在**（审查 C-02）：UI 测试跑的就是 Debug 包，
  /// 行为一点没变；而 Release 包里连那个分支都编不出来，不存在「设对了环境变量
  /// 就能把正式档案挪走」这回事。
  static func applicationSupport() -> DrawStore {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    return DrawStore(url: folder(under: base).appendingPathComponent("draws.json"))
  }

  /// 画线档案所在的目录。Release 下只有 `kanpan/` 这一个答案，没有第二条岔路。
  private static func folder(under base: URL) -> URL {
    let normal = base.appendingPathComponent("kanpan", isDirectory: true)
    #if DEBUG
    guard ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] == "1" else { return normal }
    let profile = ProcessInfo.processInfo.environment["KANPAN_PERSISTENCE_PROFILE"].flatMap { UUID(uuidString: $0)?.uuidString } ?? "default"
    return base.appendingPathComponent("kanpan-drawing-tests", isDirectory: true)
      .appendingPathComponent(profile, isDirectory: true)
    #else
    return normal
    #endif
  }

  /// 读。读不出来一律当空档，**不抛**：画线丢了是可惜，因为它开不了图是不可接受的。
  enum StoreError: Error { case newerVersion, invalidArchive }
  func read() throws -> DrawArchive {
    guard FileManager.default.fileExists(atPath: url.path) else { return DrawArchive() }
    let data = try Data(contentsOf: url)
    // Read the envelope before decoding tools unknown to this version.
    if let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
       let version = raw["v"] as? Int, version > DrawArchive.currentVersion { throw StoreError.newerVersion }
    var archive = try JSONDecoder().decode(DrawArchive.self, from: data)
    archive.version = DrawArchive.currentVersion
    return archive
  }
  func load() -> DrawArchive { (try? read()) ?? DrawArchive() }

  /// 写。先写临时文件再原子替换，中途被杀不会留下半份坏 JSON。
  func save(_ archive: DrawArchive) throws {
    // Never replace an unreadable/newer file with an empty in-memory fallback.
    if FileManager.default.fileExists(atPath: url.path) { _ = try read() }
    guard archive.bySymbol.values.allSatisfy({ $0.allSatisfy(\.isValid) }) else { throw StoreError.invalidArchive }
    if FileManager.default.fileExists(atPath: url.path) {
      let backup = url.appendingPathExtension("backup")
      if !FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.copyItem(at: url, to: backup) }
    }
    var a = archive
    a.version = DrawArchive.currentVersion
    let data = try JSONEncoder().encode(a)
    let dir = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
  }
}
