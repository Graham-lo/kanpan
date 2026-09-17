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

  /// 列式小端。**字节格式一个比特都没动**，变的只是怎么把这些字节堆出来：
  /// 原来是逐字节 `Data.append(UInt8)`——3000 根 × 5 列 × 8 字节 = 12 万次
  /// append，每次都要过一遍 Data 的写时复制检查和边界检查。现在按列整块 memcpy。
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
    guard n > 0 else { return d }
    // 一块暂存反复用：换成小端排好，再整块拷进去。
    var scratch = [UInt64](repeating: 0, count: n)
    for col in [series.open, series.high, series.low, series.close, series.volume] {
      for i in 0..<n { scratch[i] = col[from + i].bitPattern.littleEndian }
      append(&d, scratch)
    }
    if hasTimes {
      for i in 0..<n { scratch[i] = UInt64(bitPattern: series.time(at: from + i)).littleEndian }
      append(&d, scratch)
    }
    return d
  }

  // ------------------------------------------------------------------ 解码

  /// 按偏移直接在 `Data` 上读。原来第一句是 `[UInt8](data)`——把整份快照
  /// （最大 300KB，冷启动时一个周期一份）先整体复制成数组，再逐字节移位拼回
  /// UInt64。现在零复制、整数按小端一次读出。**字节格式没变。**
  ///
  /// `Snapshot.read` 用的是 `mappedIfSafe`，少掉这次复制意味着冷启动那几份
  /// 快照可以直接从页缓存里读，根本不用落进进程的堆。
  public static func decode(_ data: Data) -> BarSeries? {
    data.withUnsafeBytes { raw -> BarSeries? in
      var p = 0
      let end = raw.count
      /// 占掉 `k` 个字节，返回起始偏移。
      func take(_ k: Int) -> Int? {
        guard k >= 0, p <= end - k else { return nil }
        defer { p += k }
        return p
      }
      func u8() -> UInt8? { take(1).map { raw.loadUnaligned(fromByteOffset: $0, as: UInt8.self) } }
      func u16() -> UInt16? {
        take(2).map { UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: $0, as: UInt16.self)) }
      }
      func u32() -> UInt32? {
        take(4).map { UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0, as: UInt32.self)) }
      }
      func u64() -> UInt64? {
        take(8).map { UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: $0, as: UInt64.self)) }
      }
      func str() -> String? {
        guard let len = u16(), let at = take(Int(len)) else { return nil }
        return String(decoding: UnsafeRawBufferPointer(rebasing: raw[at..<(at + Int(len))]), as: UTF8.self)
      }
      /// 一整列：先划出字节区间，再按 8 字节一格填进去。
      func column(_ count: Int) -> [UInt64]? {
        guard count > 0 else { return [] }
        guard let at = take(count * 8) else { return nil }
        return [UInt64](unsafeUninitializedCapacity: count) { buf, filled in
          for i in 0..<count {
            buf[i] = UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: at + i * 8, as: UInt64.self))
          }
          filled = count
        }
      }

      guard let m = u32(), m == magic, let v = u16(), v == version else { return nil }
      guard let symbol = str(), let ivRaw = str(), let iv = Interval(rawValue: ivRaw) else { return nil }
      guard let t0 = u64(), let step = u64(), let cnt = u32(), let flag = u8() else { return nil }
      let n = Int(cnt)
      guard n >= 0, n <= maxBars else { return nil }

      var cols: [[Double]] = []
      cols.reserveCapacity(5)
      for _ in 0..<5 {
        guard let words = column(n) else { return nil }
        cols.append(words.map(Double.init(bitPattern:)))
      }
      var times: [Int64] = []
      if flag == 1 {
        guard let words = column(n) else { return nil }
        times = words.map(Int64.init(bitPattern:))
      }
      return BarSeries(symbol: symbol, interval: iv, t0: Int64(bitPattern: t0), step: Int64(bitPattern: step),
                       open: cols[0], high: cols[1], low: cols[2], close: cols[3], volume: cols[4],
                       openTime: times)
    }
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
  private static func put(_ d: inout Data, _ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
  private static func put(_ d: inout Data, _ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
  private static func put(_ d: inout Data, _ v: UInt64) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
  private static func putStr(_ d: inout Data, _ s: String) {
    let u = Array(s.utf8)
    put(&d, UInt16(u.count))
    d.append(contentsOf: u)
  }

  /// 一整列小端字长，一次 memcpy。
  private static func append(_ d: inout Data, _ words: [UInt64]) {
    words.withUnsafeBytes { d.append($0.bindMemory(to: UInt8.self)) }
  }
}
