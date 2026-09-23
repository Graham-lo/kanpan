import Foundation
import KanpanCore

/// OI 归档切片的磁盘缓存（§4.3 的唯一例外）。
///
/// 归档站的每日 metrics 是**不可变的历史事实**，重取一次就是一个往返；看两年 OI
/// 就是 700 多个请求。所以解压后按天存成精简二进制，总上限 20 MB、LRU 淘汰、
/// 放 `Caches/` 让系统缺空间时能自动收走。设置里关掉就退化成每次重新下。
public actor OIStore {
  public static let limitBytes = 20 * 1024 * 1024

  private let paths: Paths
  private let limit: Int
  /// 设置页「OI 归档缓存」开关。关掉：不读不写，并把已有的清掉。
  private var enabled: Bool

  public init(paths: Paths, limitBytes: Int = OIStore.limitBytes, enabled: Bool = true) {
    self.paths = paths
    self.limit = limitBytes
    self.enabled = enabled
  }

  public func setEnabled(_ on: Bool) {
    enabled = on
    if !on { clear() }
  }
  public var isEnabled: Bool { enabled }

  public func load(symbol: String, dayStart: Int64) -> [OIPoint]? {
    guard enabled else { return nil }
    let url = readable(paths.oiDay(symbol: symbol, day: OIArchive.dayString(dayStart)), symbol: symbol)
    guard let d = try? Data(contentsOf: url) else { return nil }
    // LRU 靠 mtime，读到就摸一下。
    try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    return OIArchive.decodeSlice(d)
  }

  public func save(symbol: String, dayStart: Int64, points: [OIPoint]) {
    guard enabled else { return }
    let url = paths.oiDay(symbol: symbol, day: OIArchive.dayString(dayStart))
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? OIArchive.encodeSlice(points, dayStartMs: dayStart).write(to: url, options: .atomic)
    evict()
  }

  /// 上次为这个「品种 + 周期」聚好的那一段，连同它覆盖的区间。
  ///
  /// 有它，重新打开同一张图就不必再等一个往返：先把旧的画上，再只补缺的那一头。
  public func loadSeries(symbol: String, interval: Interval) -> (points: [OIPoint], from: Int64, to: Int64)? {
    guard enabled else { return nil }
    let url = readable(paths.oiSeries(symbol: symbol, interval: interval.rawValue), symbol: symbol)
    guard let d = try? Data(contentsOf: url) else { return nil }
    try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    return OIArchive.decodeRange(d)
  }

  public func saveSeries(symbol: String, interval: Interval, points: [OIPoint], from: Int64, to: Int64) {
    guard enabled, to >= from else { return }
    let url = paths.oiSeries(symbol: symbol, interval: interval.rawValue)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? OIArchive.encodeRange(points, from: from, to: to).write(to: url, options: .atomic)
    evict()
  }

  /// 占用字节（设置页「清缓存」要显示）。
  public func usage() -> Int {
    files().reduce(0) { $0 + $1.size }
  }

  public func clear() {
    try? FileManager.default.removeItem(at: paths.oi)
  }

  // ------------------------------------------------------------------ 内部

  private struct Slice { var url: URL; var size: Int; var mtime: Date }

  private func readable(_ current: URL, symbol: String) -> URL {
    let id = InstrumentID(symbol)
    guard id.isDefaultMarket, !FileManager.default.fileExists(atPath: current.path) else { return current }
    return paths.oi.appendingPathComponent(id.symbol).appendingPathComponent(current.lastPathComponent)
  }

  private func files() -> [Slice] {
    let fm = FileManager.default
    guard let e = fm.enumerator(at: paths.oi, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]) else { return [] }
    var out: [Slice] = []
    for case let u as URL in e {
      guard let v = try? u.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]), v.isRegularFile == true,
            let size = v.fileSize else { continue }
      out.append(Slice(url: u, size: size, mtime: v.contentModificationDate ?? .distantPast))
    }
    return out
  }

  private func evict() {
    var all = files()
    var used = all.reduce(0) { $0 + $1.size }
    guard used > limit else { return }
    all.sort { $0.mtime < $1.mtime }
    for f in all {
      guard used > limit else { break }
      try? FileManager.default.removeItem(at: f.url)
      used -= f.size
    }
  }
}
