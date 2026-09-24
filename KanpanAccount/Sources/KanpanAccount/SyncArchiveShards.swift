import Foundation

/// 同步存档在盘上**分片**存（深度审查第 22 项：`ArchiveWriter` 每次整份编码）。
///
/// ## 为什么分
///
/// 存档里 `objects`（云端镜像）和 `local`（本机影子）各装着一份每条画线的完整几何、每份设置的全文，
/// 从前每一次事务都把**整份**编码成一个 `sync-v1.json` 原子写掉：改一条线，写的是几百 KB。
/// 这份活儿在写盘队列上，但 `flushNow()` 的地方（换档案、装云端那批、进后台）是主线程在等它。
///
/// ## 盘上长什么样
///
///     sync/
///       head.json      提交点：发件箱、游标、各开关（就是去掉 objects / local 的那份存档）+ 分片清单
///       <uuid>.json    一片：objects 与 local 里属于它的那几项（`ArchiveShard`）
///
/// 分片的键：画线按品种（`drawings` 的 id 是 `<venue>/<market>/<symbol>/<drawingId>`，取最后一个 `/` 之前），
/// 其余按表名（`settings`、`favorites`、`alerts` …）。一次抬手通常只动一个品种那一片 + head。
///
/// ## 怎么保证盘上永远是某一次事务的完整快照
///
/// 照的是 LSM / 追加写存储里「清单即提交点」的做法（LevelDB 的 MANIFEST、git 的 ref）：
/// 分片文件**只新建、不改写**，文件名每次都是新的 uuid；先把这次变了的分片写成新文件，
/// 最后原子地写 `head.json`——它一落下去，这次事务就算提交了。之前任何一步断电，
/// 盘上的 head 仍然指向上一版那一整套旧文件（都还在），读出来就是上一版。
/// 被取代的旧文件在 head 落盘**之后**才删；删之前进程没了只会剩几个没人引用的孤儿，
/// 下一次（本进程第一次提交时）扫掉。
///
/// ## 哪一片变了
///
/// 拿这次的切片和「这个目录上次真正提交到盘上的那一套」（`ArchiveDisk.committed`）逐片比。
/// 比较在写盘队列上做，不在主线程上；没动过的对象和上一版共享存储，`==` 基本是比指针。
/// 「上次提交的那一套」按**目录**记在进程级的表里、只在写盘队列上读写：同一个目录前后两个
/// `SyncStore`（换号再换回来）看到的是同一份真相，谁都不会删掉对方的 head 还引用着的文件。
///
/// ## 老档
///
/// 盘上还有 `sync-v1.json` 就读它，并立刻排一次整份提交把它迁成分片，提交成功后删掉老文件。
/// 老文件的存在本身就说明「还没迁完」或者「更老的版本在这之后又写过它」，两种情况都该以它为准。
/// **降级的代价**：回到只认 `sync-v1.json` 的旧版本时，它看不见分片，会当作空存档从云端整份重拉；
/// 这时还没推上去的发件箱（离线攒下的改动）在旧版本里看不见——正式文件（draws.json 等）不受影响。
struct ArchiveShard: Codable, Equatable, Sendable {
  var objects: [String: SyncObject] = [:]
  var local: [String: SyncObject] = [:]
}

struct ArchiveHead: Codable, Sendable {
  static let format = 2
  var format: Int
  /// `objects` / `local` 为空的那份存档。
  var archive: SyncArchive
  /// 分片键 → 文件名。
  var shards: [String: String]
}

/// 某个目录上次真正提交到盘上的那一套。
struct CommittedArchive: Sendable {
  var files: [String: String] = [:]
  var shards: [String: ArchiveShard] = [:]
  /// 这个进程里是否已经对这个目录扫过一次孤儿文件。
  var swept = false
}

enum ArchiveDisk {
  static let legacyName = "sync-v1.json"
  static let directoryName = "sync"
  static let headName = "head.json"

  /// 进程级：目录 → 上次提交的那一套。**只准在 `ArchiveWriter.queue` 上读写。**
  nonisolated(unsafe) static var committed: [String: CommittedArchive] = [:]

  static func shardKey(_ object: SyncObject) -> String {
    guard object.collection == "drawings", let slash = object.id.lastIndex(of: "/") else { return object.collection }
    return "drawings/" + object.id[..<slash]
  }
  static func split(_ archive: SyncArchive) -> (head: SyncArchive, shards: [String: ArchiveShard]) {
    var head = archive; head.objects = [:]; head.local = [:]
    var shards: [String: ArchiveShard] = [:]
    for (key, object) in archive.objects { shards[shardKey(object), default: ArchiveShard()].objects[key] = object }
    for (key, object) in archive.local { shards[shardKey(object), default: ArchiveShard()].local[key] = object }
    return (head, shards)
  }
  static func join(_ head: SyncArchive, _ shards: some Sequence<ArchiveShard>) -> SyncArchive {
    var archive = head
    for shard in shards {
      archive.objects.merge(shard.objects) { _, new in new }
      archive.local.merge(shard.local) { _, new in new }
    }
    return archive
  }

  struct Loaded: Sendable {
    var archive: SyncArchive; var committed: CommittedArchive; var migrating: Bool
    /// 盘上有没有存档（老的或分片的）。
    var found = true
  }

  /// 读盘上那份。没有就是空存档。
  ///
  /// 读 head 和读分片之间，同一个目录上另一个 `SyncStore` 的提交可能恰好删掉了被取代的旧分片
  /// （正常路径上调用方会先 `flushNow()`，碰不到）。碰上了就整份重读一次，最多三次。
  static func load(directory: URL) throws -> Loaded {
    let legacy = directory.appendingPathComponent(legacyName)
    if FileManager.default.fileExists(atPath: legacy.path) {
      let old = try JSONDecoder().decode(SyncArchive.self, from: Data(contentsOf: legacy))
      return Loaded(archive: old, committed: CommittedArchive(), migrating: true)
    }
    let folder = directory.appendingPathComponent(directoryName)
    let head = folder.appendingPathComponent(headName)
    var attempt = 0
    while true {
      do {
        guard FileManager.default.fileExists(atPath: head.path) else {
          return Loaded(archive: SyncArchive(), committed: CommittedArchive(), migrating: false, found: false)
        }
        let value = try JSONDecoder().decode(ArchiveHead.self, from: Data(contentsOf: head))
        guard value.format == ArchiveHead.format else { throw AccountError.storage }
        var shards: [String: ArchiveShard] = [:]
        for (key, file) in value.shards {
          shards[key] = try JSONDecoder().decode(ArchiveShard.self, from: Data(contentsOf: folder.appendingPathComponent(file)))
        }
        return Loaded(archive: join(value.archive, shards.values),
                      committed: CommittedArchive(files: value.shards, shards: shards), migrating: false)
      } catch AccountError.storage {
        throw AccountError.storage
      } catch {
        attempt += 1
        if attempt >= 3 { throw error }
      }
    }
  }

  /// 把一版存档提交到盘上：只写变了的分片，最后写 head。**只准在 `ArchiveWriter.queue` 上调。**
  /// 返回这次写了多少字节（观测用）。
  static func commit(_ value: SyncArchive, directory: URL, seed: CommittedArchive, removingLegacy: Bool) throws -> Int {
    let key = directory.standardizedFileURL.path
    let previous = committed[key] ?? seed
    let folder = directory.appendingPathComponent(directoryName)
    let (head, shards) = split(value)
    let encoder = JSONEncoder()
    var files: [String: String] = [:], fresh: [String] = [], bytes = 0
    do {
      for (name, shard) in shards {
        if let file = previous.files[name], previous.shards[name] == shard { files[name] = file; continue }
        let file = UUID().uuidString.lowercased() + ".json"
        let data = try encoder.encode(shard)
        try AccountFiles.writeData(data, to: folder.appendingPathComponent(file))
        files[name] = file; fresh.append(file); bytes += data.count
      }
      let data = try encoder.encode(ArchiveHead(format: ArchiveHead.format, archive: head, shards: files))
      try AccountFiles.writeData(data, to: folder.appendingPathComponent(headName))
      bytes += data.count
    } catch {
      // 这次没提交：新写的那几片没人引用，当场删掉；盘上仍是上一版。
      for file in fresh { try? FileManager.default.removeItem(at: folder.appendingPathComponent(file)) }
      throw error
    }
    committed[key] = CommittedArchive(files: files, shards: shards, swept: true)
    // 提交之后才删被取代的旧文件。
    let referenced = Set(files.values)
    for file in Set(previous.files.values).subtracting(referenced) {
      try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
    }
    if !previous.swept, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) {
      for name in names where name != headName && !referenced.contains(name) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
      }
    }
    if removingLegacy { try? FileManager.default.removeItem(at: directory.appendingPathComponent(legacyName)) }
    return bytes
  }
}
