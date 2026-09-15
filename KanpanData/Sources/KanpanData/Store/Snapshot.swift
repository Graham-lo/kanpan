import Foundation
import KanpanCore

/// 启动快照 `last.kbar`（§4.3）。
///
/// 列式小端，最后 3000 根，≤ 300 KB。编码格式没变，变的只是留多深。
/// 一对一个文件，按 (品种, 周期) 存在 `series/` 下，见 `SeriesStore`。
public enum Snapshot {
  /// `'K','B','A','R'`
  static let magic: UInt32 = 0x4B42_4152
  static let version: UInt16 = 1
  /// 存多少根。
  ///
  /// 必须**装得下 `MarketFeed.deepenTarget`（1800 根）**，否则后台辛苦加深出来的
  /// 那一段，一写盘就被截掉，下次冷启动还得重拉。3000 根留了足够余量，
  /// 一份也才 ~144 KB——磁盘是这台机器上最不值钱的东西。原来是 600 根。
  public static let maxBars = 3000
  /// 单个文件的字节上限（A2.4）。3000 根 × 48 B ≈ 144 KB，留一倍余量。
  public static let maxBytes = 300 * 1024

  // ------------------------------------------------------------------ 编码

  public static func encode(_ series: BarSeries) -> Data {
    let n = min(series.count, maxBars)
    let from = series.count - n
    var d = Data()
    d.reserveCapacity(64 + n * 48)
    put(&d, magic)
    put(&d, version)
    putStr(&d, series.symbol)
    putStr(&d, series.interval.rawValue)
    put(&d, UInt64(bitPattern: n > 0 ? series.time(at: from) : series.t0))
    put(&d, UInt64(bitPattern: series.step))
    put(&d, UInt32(n))
    // 有没有 openTime 表：不等距周期必有。
    let hasTimes = !series.openTime.isEmpty
    put(&d, UInt8(hasTimes ? 1 : 0))
    for col in [series.open, series.high, series.low, series.close, series.volume] {
      for i in from..<series.count { put(&d, col[i].bitPattern) }
    }
    if hasTimes {
      for i in from..<series.count { put(&d, UInt64(bitPattern: series.time(at: i))) }
    }
    return d
  }

  // ------------------------------------------------------------------ 解码

  public static func decode(_ data: Data) -> BarSeries? {
    var p = 0
    let b = [UInt8](data)
    func u8() -> UInt8? { guard p + 1 <= b.count else { return nil }; defer { p += 1 }; return b[p] }
    func u16() -> UInt16? {
      guard p + 2 <= b.count else { return nil }
      defer { p += 2 }
      return UInt16(b[p]) | UInt16(b[p + 1]) << 8
    }
    func u32() -> UInt32? {
      guard p + 4 <= b.count else { return nil }
      defer { p += 4 }
      var v: UInt32 = 0
      for i in 0..<4 { v |= UInt32(b[p + i]) << (8 * UInt32(i)) }
      return v
    }
    func u64() -> UInt64? {
      guard p + 8 <= b.count else { return nil }
      defer { p += 8 }
      var v: UInt64 = 0
      for i in 0..<8 { v |= UInt64(b[p + i]) << (8 * UInt64(i)) }
      return v
    }
    func str() -> String? {
      guard let n = u16(), p + Int(n) <= b.count else { return nil }
      defer { p += Int(n) }
      return String(decoding: b[p..<p + Int(n)], as: UTF8.self)
    }

    guard let m = u32(), m == magic, let v = u16(), v == version else { return nil }
    guard let symbol = str(), let ivRaw = str(), let iv = Interval(rawValue: ivRaw) else { return nil }
    guard let t0 = u64(), let step = u64(), let cnt = u32(), let flag = u8() else { return nil }
    let n = Int(cnt)
    guard n >= 0, n <= maxBars else { return nil }

    var cols: [[Double]] = []
    for _ in 0..<5 {
      var c = [Double](); c.reserveCapacity(n)
      for _ in 0..<n { guard let x = u64() else { return nil }; c.append(Double(bitPattern: x)) }
      cols.append(c)
    }
    var times: [Int64] = []
    if flag == 1 {
      times.reserveCapacity(n)
      for _ in 0..<n { guard let x = u64() else { return nil }; times.append(Int64(bitPattern: x)) }
    }
    return BarSeries(symbol: symbol, interval: iv, t0: Int64(bitPattern: t0), step: Int64(bitPattern: step),
                     open: cols[0], high: cols[1], low: cols[2], close: cols[3], volume: cols[4],
                     openTime: times)
  }

  // ------------------------------------------------------------------ 读写

  @discardableResult
  public static func write(_ series: BarSeries, to url: URL) throws -> Int {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let d = encode(series)
    try d.write(to: url, options: .atomic)
    return d.count
  }

  public static func read(_ url: URL) -> BarSeries? {
    guard let d = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
    return decode(d)
  }

  public static func remove(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
  }

  private static func put(_ d: inout Data, _ v: UInt8) { d.append(v) }
  private static func put(_ d: inout Data, _ v: UInt16) { for i in 0..<2 { d.append(UInt8(truncatingIfNeeded: v >> (8 * UInt16(i)))) } }
  private static func put(_ d: inout Data, _ v: UInt32) { for i in 0..<4 { d.append(UInt8(truncatingIfNeeded: v >> (8 * UInt32(i)))) } }
  private static func put(_ d: inout Data, _ v: UInt64) { for i in 0..<8 { d.append(UInt8(truncatingIfNeeded: v >> (8 * UInt64(i)))) } }
  private static func putStr(_ d: inout Data, _ s: String) {
    let u = Array(s.utf8)
    put(&d, UInt16(u.count))
    d.append(contentsOf: u)
  }
}
