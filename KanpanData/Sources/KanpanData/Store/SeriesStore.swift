import Foundation
import KanpanCore

/// 多品种启动快照（§4.3 的扩写）。
///
/// 原来磁盘上只有一份 `last.kbar`，只有「上次看的那对」能秒开；一换品种或
/// 换周期就回到空图等网络。这里按 (品种, 周期) 一对一个文件，最近用过的留下来，
/// 来回切最近看过的东西第一帧就有图。
///
/// 代价是磁盘，不是流量：每份 ≤ 1500 根 ≈ 72 KB，条数和总字节都封顶。
/// 目录在 `Caches/` 下，系统缺空间随时可以清掉，app 不依赖它存在。
public enum SeriesStore {
  /// 最多留几对。
  ///
  /// 币安 U 本位永续约 500 个品种 × 14 个周期 ≈ 7000 对，没人会全翻一遍；
  /// 2000 对的意思就是「你翻过的，全都留着」，淘汰逻辑基本不会被触发。
  /// 原来是 12，只够「常看的那几个来回切」，换个品种照样白板。
  public static let maxEntries = 2000
  /// 整个目录的字节上限。先按条数淘汰，再按字节兜底。
  ///
  /// 512 MB 对着「256 G 的机器、还空着 160 G」这个现实定的——占用户不到千分之四，
  /// 而且放在 `Caches/` 下，系统真缺空间可以随时清掉。2000 对最深的快照
  /// 加起来也才 ~450 MB，所以这个上限实际上是个兜底，不是日常会撞到的墙。
  public static let maxBytes = 512 * 1024 * 1024

  /// 文件名里的周期片段。
  ///
  /// **不能用 `Interval.rawValue`**：`1m`（分钟）和 `1M`（月）只差大小写，而 iOS
  /// 的文件系统默认大小写不敏感，两者会撞成同一个文件，互相覆盖。这里用枚举
  /// 的 case 名，彼此在忽略大小写时也是唯一的。
  static func slug(_ interval: Interval) -> String {
    switch interval {
    case .m1: "m1"
    case .m3: "m3"
    case .m5: "m5"
    case .m15: "m15"
    case .m30: "m30"
    case .h1: "h1"
    case .h2: "h2"
    case .h4: "h4"
    case .h6: "h6"
    case .h12: "h12"
    case .d1: "d1"
    case .w1: "w1"
    case .mo1: "mo1"
    case .y1: "y1"
    }
  }

  /// 品种名只留字母和数字。交易所给的本来就是这个范围，这一步是防脏数据把
  /// 路径写到目录外面去。
  static func safe(_ symbol: String) -> String? {
    let cleaned = symbol.uppercased().filter { $0.isLetter || $0.isNumber }
    guard !cleaned.isEmpty, cleaned.count <= 32, cleaned == symbol.uppercased() else { return nil }
    return cleaned
  }

  public static func url(symbol: String, interval: Interval, in dir: URL) -> URL? {
    let id = InstrumentID(symbol)
    guard id.isValid else { return nil }
    return dir.appendingPathComponent(id.venue, isDirectory: true)
      .appendingPathComponent(id.market, isDirectory: true)
      .appendingPathComponent("\(id.symbol)@\(slug(interval)).kbar")
  }

  // ------------------------------------------------------------------ 读写

  /// 读一对。文件里存着品种和周期，对不上就当没有——大小写撞名之类的意外
  /// 只会变成一次未命中，不会把别人的 K 线画到这张图上。
  public static func read(symbol: String, interval: Interval, in dir: URL) -> BarSeries? {
    read(symbol: symbol, interval: interval, in: dir, touch: true)
  }

  /// 同上，但可以不 touch。
  ///
  /// `touch: true` 要往文件上写一次 mtime（`setAttributes` 是一次同步 syscall），
  /// 为的是让淘汰按「最近看过」排而不是按「最近写过」排。冷启动主线程那一读
  /// 是要抢第一帧的，那次 touch 既拖慢首屏、又没有信息量（马上就会有一次写盘
  /// 把 mtime 顶上去），传 `touch: false` 跳过它。
  ///
  /// 即使 `touch: true`，现在也不在调用线程上写 mtime 了——落到后台任务里做，
  /// 顺手更新进程内索引（见 `SeriesIndex`）。
  public static func read(symbol: String, interval: Interval, in dir: URL, touch: Bool) -> BarSeries? {
    guard let url = url(symbol: symbol, interval: interval, in: dir) else { return nil }
    let id = InstrumentID(symbol)
    let legacy = dir.appendingPathComponent("\(id.symbol)@\(slug(interval)).kbar")
    // Read the old file in place. Atomic writes use the new path; never delete the migration source.
    let current = Snapshot.read(url)
    guard let series = current ?? (id.isDefaultMarket ? Snapshot.read(legacy) : nil),
          InstrumentID(series.symbol) == id, series.interval == interval, series.count > 0 else { return nil }
    if touch { self.touch(current == nil ? legacy : url, in: dir) }
    return series
  }

  @discardableResult
  public static func write(_ series: BarSeries, in dir: URL) throws -> Int {
    guard series.count > 0, let url = url(symbol: series.symbol, interval: series.interval, in: dir) else { return 0 }
    let n = try Snapshot.write(series, to: url)
    // 时间戳在这里取，不在 actor 里取：后台任务的执行顺序不保证，真在 actor 里
    // 现取 `Date()`，先写的那份反而可能记成更新的，LRU 就倒过来了。
    let at = Date()
    let index = SeriesIndex.shared
    Task.detached(priority: .utility) { await index.wrote(url, in: dir, bytes: n, at: at) }
    return n
  }

  public static func remove(symbol: String, interval: Interval, in dir: URL) {
    guard let url = url(symbol: symbol, interval: interval, in: dir) else { return }
    try? FileManager.default.removeItem(at: url)
    let id = InstrumentID(symbol)
    if id.isDefaultMarket {
      try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id.symbol)@\(slug(interval)).kbar"))
    }
    let index = SeriesIndex.shared
    Task.detached(priority: .utility) { await index.dropped(url, in: dir) }
  }

  public static func clear(in dir: URL) {
    try? FileManager.default.removeItem(at: dir)
    let index = SeriesIndex.shared
    Task.detached(priority: .utility) { await index.forget(dir) }
  }

  /// 启动时把目录扫一遍建索引。不扫也能用（索引第一次被碰到时会自己扫），
  /// 这个入口只是让那一次扫发生在空闲时刻，而不是第一次写盘的时候。
  public static func warm(_ dir: URL) {
    let index = SeriesIndex.shared
    Task.detached(priority: .background) { await index.warm(dir) }
  }

  // ------------------------------------------------------------------ 淘汰

  static func files(in dir: URL, keys: [URLResourceKey]) -> [URL] {
    (FileManager.default.enumerator(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])?.allObjects as? [URL]) ?? []
  }

  private static func touch(_ url: URL, in dir: URL) {
    let now = Date()
    let index = SeriesIndex.shared
    Task.detached(priority: .utility) {
      try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
      await index.touched(url, in: dir, at: now)
    }
  }
}

/// 快照目录的进程内索引：每份文件的 (mtime, bytes)。
///
/// 存在的理由是淘汰。老做法是每次写盘都把整个目录连同每份文件的属性扫一遍
/// （`contentsOfDirectory` + 每份一次 `resourceValues`），目录能放 2000 份，
/// 预热又是一口气写十几二十份，这一扫全压在写盘路径上。现在启动时扫一次建表，
/// 之后 `write` / `touch` / `remove` 增量维护，只有条数或字节真的超限了才排序删文件——
/// 正常情况下一次 stat 都不做。
///
/// 索引放在 actor 里：写盘可能发生在任意线程/任意 Task 上，字典不能裸着让人并发改。
actor SeriesIndex {
  static let shared = SeriesIndex()

  private struct Entry {
    var at: Date
    var bytes: Int
  }

  /// 一个进程里可能同时有好几个快照目录（正式的、测试临时目录），按目录分表；
  /// 表里按文件名索引。
  ///
  /// **键要先规整**：`NSTemporaryDirectory()` 给的是 `/var/folders/…`，而
  /// `contentsOfDirectory` 扫回来的是 `/private/var/folders/…`——同一个文件，
  /// 两个 `URL` 不相等。直接拿 `URL` 当键，扫出来的那份和写进来的那份会各记一条，
  /// 条数翻倍、字节翻倍，淘汰也就跟着算错。
  private var dirs: [URL: [String: Entry]] = [:]
  private var totals: [URL: Int] = [:]

  private func key(_ dir: URL) -> URL { dir.resolvingSymlinksInPath().standardizedFileURL }

  /// 显式预热。
  func warm(_ dir: URL) { ensureScanned(key(dir)) }

  /// 目录第一次被碰到时扫一遍，之后全靠增量。
  private func ensureScanned(_ dir: URL) {
    guard dirs[dir] == nil else { return }
    var table: [String: Entry] = [:]
    var total = 0
    let keys: [URLResourceKey] = [.contentModificationDateKey, .totalFileAllocatedSizeKey, .fileSizeKey]
    let files = SeriesStore.files(in: dir, keys: keys)
    for url in files where url.pathExtension == "kbar" {
      let v = try? url.resourceValues(forKeys: Set(keys))
      let entry = Entry(at: v?.contentModificationDate ?? .distantPast,
                        bytes: v?.fileSize ?? v?.totalFileAllocatedSize ?? 0)
      table[url.resolvingSymlinksInPath().standardizedFileURL.path.replacingOccurrences(of: key(dir).path + "/", with: "")] = entry
      total += entry.bytes
    }
    dirs[dir] = table
    totals[dir] = total
  }

  /// 写了一份。更新索引，顺便看要不要淘汰。
  func wrote(_ url: URL, in dir: URL, bytes: Int, at when: Date) {
    let d = key(dir)
    ensureScanned(d)
    let name = url.resolvingSymlinksInPath().standardizedFileURL.path.replacingOccurrences(of: key(dir).path + "/", with: "")
    var table = dirs[d] ?? [:]
    var total = totals[d] ?? 0
    if let old = table[name] { total -= old.bytes }
    table[name] = Entry(at: when, bytes: bytes)
    total += bytes
    dirs[d] = table
    totals[d] = total
    evictIfNeeded(d)
  }

  /// 读了一份。只挪它在 LRU 里的位置，大小没变，也不会触发淘汰。
  func touched(_ url: URL, in dir: URL, at when: Date) {
    let d = key(dir)
    ensureScanned(d)
    let name = url.resolvingSymlinksInPath().standardizedFileURL.path.replacingOccurrences(of: key(dir).path + "/", with: "")
    guard var table = dirs[d], var entry = table[name] else { return }
    entry.at = when
    table[name] = entry
    dirs[d] = table
  }

  func dropped(_ url: URL, in dir: URL) {
    let d = key(dir)
    ensureScanned(d)
    guard var table = dirs[d] else { return }
    if let old = table.removeValue(forKey: url.resolvingSymlinksInPath().standardizedFileURL.path.replacingOccurrences(of: key(dir).path + "/", with: "")) {
      totals[d] = (totals[d] ?? 0) - old.bytes
      dirs[d] = table
    }
  }

  /// 磁盘被别人动过（整目录删掉），索引作废。
  func forget(_ dir: URL) {
    let d = key(dir)
    dirs[d] = nil
    totals[d] = nil
  }

  /// 索引里记着几份、共多少字节（测试用）。
  func stats(_ dir: URL) -> (count: Int, bytes: Int) {
    let d = key(dir)
    ensureScanned(d)
    return (dirs[d]?.count ?? 0, totals[d] ?? 0)
  }

  /// 索引里记的这份的时刻（测试用）。
  func mark(_ url: URL, in dir: URL) -> Date? {
    let d = key(dir)
    ensureScanned(d)
    return dirs[d]?[url.resolvingSymlinksInPath().standardizedFileURL.path.replacingOccurrences(of: key(dir).path + "/", with: "")]?.at
  }

  /// 只有真的超限才排序、才删文件。没超就是几次字典操作。
  private func evictIfNeeded(_ dir: URL) {
    guard var table = dirs[dir] else { return }
    var total = totals[dir] ?? 0
    guard table.count > SeriesStore.maxEntries || total > SeriesStore.maxBytes else { return }
    let ordered = table.sorted { $0.value.at > $1.value.at }
    var kept = 0
    var bytes = 0
    for (name, entry) in ordered {
      kept += 1
      bytes += entry.bytes
      if kept > SeriesStore.maxEntries || bytes > SeriesStore.maxBytes {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        table[name] = nil
        total -= entry.bytes
      }
    }
    dirs[dir] = table
    totals[dir] = total
  }
}
