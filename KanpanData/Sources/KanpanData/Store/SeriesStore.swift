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
    guard let name = safe(symbol) else { return nil }
    return dir.appendingPathComponent("\(name)@\(slug(interval)).kbar")
  }

  // ------------------------------------------------------------------ 读写

  /// 读一对。文件里存着品种和周期，对不上就当没有——大小写撞名之类的意外
  /// 只会变成一次未命中，不会把别人的 K 线画到这张图上。
  public static func read(symbol: String, interval: Interval, in dir: URL) -> BarSeries? {
    guard let url = url(symbol: symbol, interval: interval, in: dir),
          let series = Snapshot.read(url),
          series.symbol.uppercased() == symbol.uppercased(), series.interval == interval,
          series.count > 0 else { return nil }
    touch(url)
    return series
  }

  @discardableResult
  public static func write(_ series: BarSeries, in dir: URL) throws -> Int {
    guard series.count > 0, let url = url(symbol: series.symbol, interval: series.interval, in: dir) else { return 0 }
    let n = try Snapshot.write(series, to: url)
    prune(in: dir)
    return n
  }

  public static func remove(symbol: String, interval: Interval, in dir: URL) {
    guard let url = url(symbol: symbol, interval: interval, in: dir) else { return }
    try? FileManager.default.removeItem(at: url)
  }

  public static func clear(in dir: URL) {
    try? FileManager.default.removeItem(at: dir)
  }

  // ------------------------------------------------------------------ 淘汰

  /// 两次淘汰之间至少隔这么久。
  ///
  /// 淘汰要把整个目录连同每份文件的大小扫一遍；目录能放到 2000 份之后，这一扫就不再
  /// 便宜了，而预热是一口气写十几二十份的。上限是「最终有界」，不需要每次写盘都扫，
  /// 隔一分钟扫一次足够——期间最多也就多占几份快照的地方。
  static let pruneEverySeconds: TimeInterval = 60
  private static let pruneClock = PruneClock()

  /// 按最近使用时间倒序留下，超出条数或字节上限的删掉。读的时候会 `touch`，
  /// 所以「最近看过的」是真的按看过的时间排，不是只按写入时间。
  ///
  /// `force` 只给测试用：正常路径上这里是按 `pruneEverySeconds` 节流的。
  static func prune(in dir: URL, force: Bool = false) {
    guard force || pruneClock.due(every: pruneEverySeconds) else { return }
    let fm = FileManager.default
    let keys: [URLResourceKey] = [.contentModificationDateKey, .totalFileAllocatedSizeKey, .fileSizeKey]
    guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys,
                                                  options: [.skipsHiddenFiles]) else { return }
    let entries = files
      .filter { $0.pathExtension == "kbar" }
      .map { url -> (url: URL, at: Date, bytes: Int) in
        let v = try? url.resourceValues(forKeys: Set(keys))
        return (url, v?.contentModificationDate ?? .distantPast,
                v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
      }
      .sorted { $0.at > $1.at }

    var kept = 0
    var bytes = 0
    for entry in entries {
      kept += 1
      bytes += entry.bytes
      if kept > maxEntries || bytes > maxBytes {
        try? fm.removeItem(at: entry.url)
      }
    }
  }

  private static func touch(_ url: URL) {
    try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
  }
}

/// 记上次淘汰的时间。写盘可能发生在任意线程，所以上把锁。
private final class PruneClock: @unchecked Sendable {
  private let lock = NSLock()
  private var last = Date.distantPast
  func due(every seconds: TimeInterval) -> Bool {
    lock.lock(); defer { lock.unlock() }
    let now = Date()
    guard now.timeIntervalSince(last) >= seconds else { return false }
    last = now
    return true
  }
}
