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
  /// 这份档案的全部文件位置（`ReviewPaths`）。
  public let paths: ReviewPaths
  private var url: URL { paths.archive }
  private var replayURL: URL { paths.replay }
  private var draftURL: URL { paths.draft }
  /// 「记一笔」自动存下来的那张图放哪儿（§4.3）。一条记录一张，文件名就是记录 id，
  /// 所以不需要索引，也不进主档——几百 KB 的 PNG 塞进那份每次改动都整份重写的
  /// JSON 里，等于每记一笔就把所有图重编码一遍。
  private var shotsURL: URL { paths.shots }
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
  /// 上一次写进度的时刻（单调钟，纳秒）；nil 是这份档案还没写过。原来用墙上时间：
  /// 手机时间往回拨一小时，`saveReplay` 算出来的「还得等」就是一小时，那一小时里的
  /// 进度全挂在一个睡着的 Task 上，中途被杀就丢了。
  private var replayWrittenAt: UInt64?
  private var replayDirty = false

  /// 三个文件，**只有主档坏了才拒绝开门**。
  ///
  /// 以前三份里任何一份解不动，`init` 就整个抛；而 `init` 抛就等于
  /// `AppAccountBridge.prepare` 抛，整份账号档案（设置、自选、画线、复盘）都换不进来。
  /// 拿一个书签（重温进度）或者一条写了一半的草稿去换「整个复盘打不开」，
  /// 代价对不上：
  ///
  /// - `replay-positions.json`（进度）坏了 → 丢这个书签，别的照常。
  /// - `draft-v1.json`（草稿）坏了 → 丢这条草稿，记录与待发队列一条不少。
  /// - `review-v1.json`（主档）坏了 → **照旧抛**。那里面是用户全部的记录和还没推上去的
  ///   队列，拿一份空档接着跑等于把它们一起丢掉，还会被下一次写盘盖死。
  ///
  /// 坏掉的那份不静默抹掉：先留一份 `.backup`（和 `DrawStore.save`、
  /// `PersonalFileStorage.write` 同一个做法），再按缺省值往下走。
  public convenience init(directory: URL) throws { try self.init(paths: ReviewPaths(directory: directory)) }
  public init(paths: ReviewPaths) throws {
    self.paths = paths
    let directory = paths.directory
    positions = Self.recover([String: ReviewReplayPosition].self, at: paths.replay) ?? [:]
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: paths.archive.path) {
      let value = try JSONDecoder().decode(ReviewArchive.self, from: Data(contentsOf: paths.archive))
      guard value.version == 1 else { throw ReviewStorageError.unreadable }
      archive = value
      stamp = Self.fingerprint(paths.archive)
    } else { archive = ReviewArchive() }
    if FileManager.default.fileExists(atPath: paths.draft.path) {
      // 解不动时 `recover` 给 nil，这儿要和「文件里明写着没有草稿」区分开：
      // 前者保留主档里那一份（登录时从访客档案并过来的草稿就住在那儿），
      // 后者照旧清空（草稿提交完 `saveDraft(nil)` 留下的就是它）。
      if let saved = Self.recover(DraftFile.self, at: paths.draft) {
        archive.draft = saved.draft.flatMap { value in archive.records.contains(where: { $0.id == value.id }) ? nil : value }
      }
    }
    migrateShotBodies()
  }

  /// 老队列里的「发图」那条把整张图（base64）塞在 body 里（第 25 项之前）。
  ///
  /// 那样每一次 `transaction` 都要把几百 KB 到 2 MB 的图跟着整份主档重编码、重写一遍，
  /// 记一笔、改一句复盘、归一次组都是。现在队列只记「哪条记录的图要传」，图本身就住在
  /// `shots/<id>.png`，引擎发的那一刻现读。这里把老 body 落成文件（那边已经有就不盖），
  /// 再把 body 清空；落不下来的那条原样留着，引擎还认得老格式。
  private func migrateShotBodies() {
    struct Legacy: Decodable { var image: String }
    var stripped = Set<UUID>()
    for operation in archive.queue where operation.kind == "shot" && !operation.body.isEmpty {
      guard let legacy = try? JSONDecoder().decode(Legacy.self, from: operation.body),
            let image = Data(base64Encoded: legacy.image) else { continue }
      if !hasShot(operation.recordId) { guard (try? saveShot(image, for: operation.recordId, trim: false)) != nil else { continue } }
      stripped.insert(operation.id)
    }
    guard !stripped.isEmpty else { return }
    try? transaction { archive in
      for index in archive.queue.indices where stripped.contains(archive.queue[index].id) { archive.queue[index].body = Data() }
    }
  }

  /// 读一份**侧文件**：解不动就留一份 `.backup` 再返回 nil，不抛。
  private static func recover<T: Decodable>(_ type: T.Type, at url: URL) -> T? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    if let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(type, from: data) { return value }
    let backup = url.appendingPathExtension("backup")
    if !FileManager.default.fileExists(atPath: backup.path) { try? FileManager.default.copyItem(at: url, to: backup) }
    return nil
  }

  /// 把另一份档案的两份**侧文件**并过来：草稿与重温进度。
  ///
  /// 记录与待发队列由调用方自己在 `transaction` 里挑（要按 `serverId` 去重、要
  /// 重编 `create` 的 body），侧文件这两样没得挑，规则只有一条：**这边没有的才收**。
  ///
  /// 草稿**必须落回 `draft-v1.json`**，不能只塞进主档的 `archive.draft`：`init` 末尾
  /// 是拿这份侧文件去盖 `archive.draft` 的，只写主档的话，账号目录里那份写着
  /// 「现在没有草稿」的 `draft-v1.json`（上一条草稿提交时 `saveDraft(nil)` 留下的）
  /// 会在下一次冷启动把刚并过来的草稿当场抹掉——游客转正式账号丢草稿就是这么丢的。
  /// 进度则是压根没人并过。
  public func adoptSideFiles(from other: ReviewStore, sanitizingDraft: (ReviewDraft) -> ReviewDraft = { $0 }) throws {
    if archive.draft == nil, let draft = other.archive.draft { try saveDraft(sanitizingDraft(draft)) }
    try adoptReplay(from: other)
    adoptShots(from: other)
  }

  /// 访客那边记过的图跟着记录一起搬过来。规则同样只有一条：这边没有的才收。
  /// 搬不动的那张就算了——图丢了记录还在，不值得为它中断整次登录。
  public func adoptShots(from other: ReviewStore) {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: other.shotsURL.path)) ?? []
    guard !names.isEmpty, (try? FileManager.default.createDirectory(at: shotsURL, withIntermediateDirectories: true)) != nil else { return }
    for name in names {
      let to = shotsURL.appendingPathComponent(name)
      guard !FileManager.default.fileExists(atPath: to.path) else { continue }
      try? FileManager.default.copyItem(at: other.shotsURL.appendingPathComponent(name), to: to)
    }
  }

  // MARK: - 那张图

  private func shotURL(_ id: UUID) -> URL { paths.shot(id) }
  /// 这条记录的图。没有就是 nil，不抛——它只是一张图。
  ///
  /// 读到了就把文件的修改时间拨到现在：`trimShots` 按它做 LRU，刚看过的最后才轮到。
  public func shot(_ id: UUID) -> Data? {
    guard let data = try? Data(contentsOf: shotURL(id)) else { return nil }
    try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: shotURL(id).path)
    return data
  }
  public func hasShot(_ id: UUID) -> Bool { FileManager.default.fileExists(atPath: shotURL(id).path) }
  public func saveShot(_ data: Data, for id: UUID) throws { try saveShot(data, for: id, trim: true) }
  private func saveShot(_ data: Data, for id: UUID, trim: Bool) throws {
    try FileManager.default.createDirectory(at: shotsURL, withIntermediateDirectories: true)
    try data.write(to: shotURL(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    if trim { trimShots() }
  }

  /// `shots/` 的总量上限。一张图压到 2 MB 以内（`ReviewFeature.shotMaxBytes`），
  /// 实际多在 150–400 KB，64 MB 大约是最近两三百条记录的图——和云端缓存留的 200 条
  /// 记录对得上；整台设备的预算是存储加内存约 2 GB，复盘的图占它 3%。
  public static let shotBudget = 64 * 1024 * 1024

  /// 超过 `budget` 就按「最久没看」删图，删到回到预算以内。
  ///
  /// 只删**能再要回来**的：队列里没有它的任何一条（图那条还没传上去的更不能删）、
  /// 不是手上那条草稿、也不是主档里只活在本机的记录（没有 `serverId`）。删掉的那张
  /// 哪天再翻到，`loadShot` 会从服务端再要一次。本机独有的图一张都不删——宁可超预算。
  ///
  /// 主档里已经没有记录认领的那张（记录被云端缓存那趟裁掉、或者从服务端翻页时现要回来的）
  /// 同样能删：和 `pruneShots` 一个口径。原来这儿只认「主档里有、而且带 `serverId`」的，
  /// 孤儿一张都不删——离线攒几百条再联网跑空队列，云端缓存把旧记录裁到只剩 200 条，
  /// 旧记录的图全成了孤儿；这时超预算，删掉的反而是那 200 条还看得见的记录的图，
  /// 几百张孤儿原样留着，照样超预算，要等下一次换档案 `pruneShots` 才清。
  @discardableResult public func trimShots(budget: Int = ReviewStore.shotBudget) -> Int {
    guard readable else { return 0 }
    let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
    let files = (try? FileManager.default.contentsOfDirectory(at: shotsURL, includingPropertiesForKeys: keys)) ?? []
    var entries: [(id: UUID, url: URL, size: Int, used: Date)] = []
    for url in files where url.pathExtension == "png" {
      guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
            let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
      entries.append((id, url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast))
    }
    var total = entries.reduce(0) { $0 + $1.size }
    guard total > budget else { return 0 }
    var kept = Set(archive.queue.map(\.recordId)).union(archive.draft.map { [$0.id] } ?? [])
    kept.formUnion(archive.records.lazy.filter { $0.serverId == nil }.map(\.id))
    var removed = 0
    for entry in entries.sorted(by: { $0.used < $1.used }) where total > budget {
      guard !kept.contains(entry.id) else { continue }
      if (try? FileManager.default.removeItem(at: entry.url)) != nil { total -= entry.size; removed += 1 }
    }
    return removed
  }
  public func removeShot(_ id: UUID) { try? FileManager.default.removeItem(at: shotURL(id)) }

  /// 删掉已经没有记录认领的图（审查 D4）。
  ///
  /// `shots/` 只进不出：记录被云端缓存那趟裁掉（`cloudCache` 只留最近 200 条 / 12 MB）、
  /// 登录时从访客那边整目录搬过来的图（`adoptShots` 不看记录在不在）都会留成孤儿，
  /// 一张几百 KB，攒着没人删。
  ///
  /// 认领的口径：主档里的记录、待发队列里提到的记录、以及手上那条草稿。被裁掉的记录
  /// 本来就在服务端，图也传上去过，哪天再翻到它 `loadShot` 会再要一次。
  /// 只动文件名是「UUID.png」的那些，别的（写了一半的临时文件等）一概不碰；
  /// 主档读不动时不删——那时候不知道谁还活着。
  @discardableResult public func pruneShots() -> Int {
    guard readable else { return 0 }
    var live = Set(archive.records.map(\.id))
    live.formUnion(archive.queue.map(\.recordId))
    if let draft = archive.draft { live.insert(draft.id) }
    let names = (try? FileManager.default.contentsOfDirectory(atPath: shotsURL.path)) ?? []
    var removed = 0
    for name in names where name.hasSuffix(".png") {
      guard let id = UUID(uuidString: String(name.dropLast(4))), !live.contains(id) else { continue }
      if (try? FileManager.default.removeItem(at: shotsURL.appendingPathComponent(name))) != nil { removed += 1 }
    }
    // 孤儿删完再看总量（换档案时扫一次，不挂定时器）。
    trimShots()
    return removed
  }

  /// 重温进度：这边没有的才收（这边有的那一条是这个人自己更晚看到的位置）。
  public func adoptReplay(from other: ReviewStore) throws {
    var next = positions
    for (key, value) in other.allReplay where next[key] == nil { next[key] = value }
    Self.evict(&next, keeping: nil)
    guard next.keys != positions.keys else { return }
    positions = next
    replayDirty = true
    try flushReplay()
  }

  /// 这份档案知道的全部重温进度：侧文件那份为主，老存档里并进主档的那份兜底。
  public var allReplay: [String: ReviewReplayPosition] { archive.replay.merging(positions) { _, live in live } }
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
  public func transaction(_ edit: (inout ReviewArchive) throws -> Void) throws { try commit(edit, write: true) }

  /// 改动立刻进内存（`archive` 当场就是新的），落盘最多晚 `stageInterval`。
  ///
  /// 只给同步引擎用，而且只用在「丢了也能靠幂等重发补回来」的那几笔上：发成功之后把
  /// 这条摘下队列、把服务端回的那份并进记录。一轮要是没来得及落盘就被杀，下次开档
  /// 那几条还在队列里，原样重发（同一个幂等键、同一份 body），服务端认成同一次。
  /// 发之前要改写 body 的那一笔（更新类的 `expectedRevision`）不走这里，照旧
  /// `transaction`——那一份必须先在盘上，重发才一模一样。
  ///
  /// 原来这几笔全是 `transaction`：离线攒 N 条再联网，一轮要把整份主档（N 条记录 +
  /// 还剩的队列，每条都带着图表设置与画线快照）编码、原子写 2N 遍，写盘量是 N² 级的。
  /// 2000 条（约 40 MB 的主档）跑空队列要 4001 次整份写、Debug 下 6 分钟，全压在主线程上。
  ///
  /// 攒着的这一笔由下一次任何落盘（`transaction` / 过了 `stageInterval` 的 `stage` /
  /// `flush`）一起带走；引擎每一轮收尾都 `flush`。
  public func stage(_ edit: (inout ReviewArchive) throws -> Void) throws {
    try commit(edit, write: Double(Self.uptime() &- writtenAt) / 1_000_000_000 >= stageInterval)
  }
  /// 把 `stage` 攒着的改动写下去。没攒着就是空操作，不碰盘。
  public func flush() throws {
    guard staged else { return }
    try commit({ _ in }, write: true)
  }
  /// `stage` 最多攒多久就得落一次盘。测试里调大，好数「这一轮到底写了几次」。
  public var stageInterval: TimeInterval = 2
  /// 内存比盘上新（有 `stage` 过、还没写下去的改动）。
  public private(set) var staged = false
  /// 主档整份写了几次（测试据此判断一轮同步是不是 N² 级的写盘）。
  public private(set) var writes = 0
  /// 上一次整份写主档的时刻（单调钟，纳秒）。
  private var writtenAt: UInt64 = 0
  /// 「过了多久」读单调钟：墙上时间被拨回去，节流就会一等几个小时。
  static func uptime() -> UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) }

  private func commit(_ edit: (inout ReviewArchive) throws -> Void, write: Bool) throws {
    guard readable else { throw ReviewStorageError.unreadable }
    // Recheck before writing: never overwrite a future version or externally corrupted file.
    //
    // 原来是**每次写之前**把整份存档从盘上重读一遍再解码一遍——几百条记录的 JSON，
    // 只为了确认「还是 version 1」。这条保护针对的是「文件被别人换过」，而不是
    // 「文件本来就是我们写的」：所以先 stat 一下，指纹和上次我们自己写下去的那份
    // 对得上就直接写，对不上（或者压根没记过）才真去读一遍。
    if write, FileManager.default.fileExists(atPath: url.path) {
      let now = Self.fingerprint(url)
      if stamp == nil || now == nil || now != stamp {
        guard let current = try? JSONDecoder().decode(ReviewArchive.self, from: Data(contentsOf: url)), current.version == 1 else {
          readable = false; throw ReviewStorageError.unreadable
        }
        stamp = now
      }
    }
    var next = archive; try edit(&next)
    // 云端缓存的裁剪只在真落盘时做：它每次要把整张记录表过一遍（量字节、比对上次量过的那份），
    // 放在每一笔 `stage` 上，一轮几千笔就又是 N² 级。晚两秒再裁不改变结果——裁掉的只会是
    // 服务端另有一份、又挤出了最近 200 条的那些，而这个集合只会越来越大。
    if cloudCache && write {
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
    guard write else { archive = next; staged = true; return }
    let data = try JSONEncoder().encode(next)
    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    stamp = Self.fingerprint(url)
    writes += 1; writtenAt = Self.uptime(); staged = false
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
    var stamped = position
    if stamped.usedAt == nil { stamped.usedAt = ReviewClock.now }
    var next = positions; next[id.uuidString] = stamped
    Self.evict(&next, keeping: id.uuidString)
    positions = next
    replayDirty = true
    let elapsed = replayWrittenAt.map { Double(Self.uptime() &- $0) / 1_000_000_000 } ?? .infinity
    let wait = Self.replayThrottle - elapsed
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
  ///
  /// 写成功了才摘掉「有没写的」标记。原来是先摘再写：这一次写失败（磁盘满、文件保护下
  /// 锁屏后台写不进），标记已经没了，之后的 `transaction` / `saveDraft` 顺手带的那一下
  /// 全是空操作，这一段进度只剩内存里一份，进程一退就丢。
  /// 时刻照样先记：写失败也按节流来，别每走一根 K 线就再撞一次墙。
  public func flushReplay() throws {
    replayPending?.cancel(); replayPending = nil
    guard replayDirty else { return }
    replayWrittenAt = Self.uptime()
    try JSONEncoder().encode(positions).write(to: replayURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    replayDirty = false
  }
  /// 读一条进度，顺手记一笔「刚看过」。
  ///
  /// 淘汰要按「最久没看的」来（见 `evict`），而「看」这个动作在这儿——打开一条旧记录
  /// 重温、但一根都没往前推的时候，只会走到这里。不立刻写盘：`replayDirty` 挂上，
  /// 下一次任何一笔落盘顺手带走它。
  public func savedReplay(_ id: UUID) -> ReviewReplayPosition? {
    let key = id.uuidString
    guard var value = positions[key] ?? archive.replay[key] else { return nil }
    value.usedAt = ReviewClock.now
    positions[key] = value
    replayDirty = true
    return value
  }

  /// 超过 500 条时按 **LRU** 淘汰：丢最久没看的那几条，`keeping` 那一条永远留着。
  ///
  /// 原来写的是 `next.keys.sorted().first`——按 UUID 字符串排序取第一个。那是
  /// 「谁的 id 以 0 开头」，和这个人最近在看哪条记录毫无关系：他天天重温的那条
  /// 只要 id 恰好小，就每次都被第一个丢掉，而三个月没碰过的那条稳稳留着（审查 B-08）。
  ///
  /// 老存档里的条目没有 `usedAt`，当成「上古」先丢——它们本来也就是最久没动的那批。
  private static func evict(_ table: inout [String: ReviewReplayPosition], keeping: String?) {
    guard table.count > limit else { return }
    let order = table
      .filter { $0.key != keeping }
      .sorted { ($0.value.usedAt ?? 0, $0.key) < ($1.value.usedAt ?? 0, $1.key) }
    for entry in order {
      guard table.count > limit else { break }
      table.removeValue(forKey: entry.key)
    }
  }
  /// 最多记多少条重温进度。
  private static let limit = 500
}
