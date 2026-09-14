import Foundation
import KanpanCore

/// 归档站的每日 metrics（§4.5）。
///
/// 一天一个 zip（≈ 12 KB），解开是 CSV，5 分钟粒度、288 行。**行不是按时间排的**
/// （真实文件里 00:00 后面跟着 00:15、00:35），所以解完必须排序。
public enum OIArchive {
  /// 列序：create_time, symbol, sum_open_interest, sum_open_interest_value,
  /// count_toptrader_long_short_ratio, sum_toptrader_long_short_ratio,
  /// count_long_short_ratio, sum_taker_long_short_vol_ratio
  public static func parseCSV(_ data: Data) -> [OIPoint] {
    var out: [OIPoint] = []
    out.reserveCapacity(300)
    let text = String(decoding: data, as: UTF8.self)
    var first = true
    text.enumerateLines { line, _ in
      if first { first = false; if line.hasPrefix("create_time") { return } }
      guard !line.isEmpty else { return }
      let f = line.split(separator: ",", omittingEmptySubsequences: false)
      guard f.count >= 3, let t = parseTime(f[0]), let v = Double(f[2]) else { return }
      out.append(OIPoint(
        time: t, value: v,
        topTraderAccountRatio: f.count > 4 ? Double(f[4]) : nil,
        topTraderPositionRatio: f.count > 5 ? Double(f[5]) : nil,
        accountRatio: f.count > 6 ? Double(f[6]) : nil,
        takerVolumeRatio: f.count > 7 ? Double(f[7]) : nil))
    }
    out.sort { $0.time < $1.time }
    return out
  }

  /// `2026-09-01 00:05:00` → UTC 毫秒。归档站的时间就是 UTC。
  public static func parseTime(_ s: Substring) -> Int64? {
    let b = Array(s.utf8)
    guard b.count >= 19 else { return nil }
    func n(_ i: Int, _ len: Int) -> Int? {
      var v = 0
      for k in i..<(i + len) {
        let c = Int(b[k]) - 48
        guard c >= 0, c <= 9 else { return nil }
        v = v * 10 + c
      }
      return v
    }
    guard let y = n(0, 4), let mo = n(5, 2), let d = n(8, 2),
          let h = n(11, 2), let mi = n(14, 2), let se = n(17, 2) else { return nil }
    let day = Aggregator.utcMs(year: y, month: mo, day: d)
    return day + Int64(h) * 3_600_000 + Int64(mi) * 60_000 + Int64(se) * 1000
  }

  public static func parseZip(_ data: Data) throws -> [OIPoint] {
    parseCSV(try Zip.unzipFirst(data))
  }

  // ------------------------------------------------------------------ 日切片

  /// `.oi` 精简二进制：只留 create_time + sum_open_interest，一天 ≈ 3.4 KB。
  /// 时间存「距当天 00:00 的秒数」，四字节够（一天 86400 秒）。
  static let sliceMagic: UInt32 = 0x494F_4B31   // 'KOI1' 小端读出来

  public static func encodeSlice(_ points: [OIPoint], dayStartMs: Int64) -> Data {
    var d = Data()
    d.reserveCapacity(16 + points.count * 12)
    append(&d, sliceMagic)
    append(&d, UInt64(bitPattern: dayStartMs))
    append(&d, UInt32(points.count))
    for p in points {
      append(&d, UInt32(max(0, min(Int64(UInt32.max), (p.time - dayStartMs) / 1000))))
      append(&d, p.value.bitPattern)
    }
    return d
  }

  public static func decodeSlice(_ data: Data) -> [OIPoint]? {
    let b = [UInt8](data)
    guard b.count >= 16, Zip.u32(b, 0) == sliceMagic else { return nil }
    var day: Int64 = 0
    for i in 0..<8 { day |= Int64(b[4 + i]) << (8 * Int64(i)) }
    let n = Int(Zip.u32(b, 12))
    guard b.count >= 16 + n * 12 else { return nil }
    var out: [OIPoint] = []
    out.reserveCapacity(n)
    for i in 0..<n {
      let o = 16 + i * 12
      let secs = Int64(Zip.u32(b, o))
      var bits: UInt64 = 0
      for k in 0..<8 { bits |= UInt64(b[o + 4 + k]) << (8 * UInt64(k)) }
      out.append(OIPoint(time: day + secs * 1000, value: Double(bitPattern: bits)))
    }
    return out
  }

  private static func append(_ d: inout Data, _ v: UInt32) {
    for i in 0..<4 { d.append(UInt8(truncatingIfNeeded: v >> (8 * UInt32(i)))) }
  }
  private static func append(_ d: inout Data, _ v: UInt64) {
    for i in 0..<8 { d.append(UInt8(truncatingIfNeeded: v >> (8 * UInt64(i)))) }
  }

  // ------------------------------------------------------------------ 日期

  /// `2026-09-01`。归档站的文件名就长这样。
  public static func dayString(_ ms: Int64) -> String {
    let p = DateParts(ms: Double(ms), offsetMinutes: 0)
    return String(format: "%04d-%02d-%02d", p.year, p.month, p.day)
  }

  public static func dayStart(_ ms: Int64) -> Int64 {
    let p = DateParts(ms: Double(ms), offsetMinutes: 0)
    return Aggregator.utcMs(year: p.year, month: p.month, day: p.day)
  }

  /// `[from, to]` 覆盖到的每一天（UTC），从早到晚。
  public static func days(from: Int64, to: Int64) -> [Int64] {
    guard to >= from else { return [] }
    var out: [Int64] = []
    var d = dayStart(from)
    let end = dayStart(to)
    while d <= end {
      out.append(d)
      d += 86_400_000
    }
    return out
  }

  /// 下载顺序：先视野中间，再往两边扩（§4.5 第 3 条）。用户最先看到的先有。
  public static func centerOut<T>(_ items: [T]) -> [T] {
    guard !items.isEmpty else { return [] }
    var out: [T] = []
    out.reserveCapacity(items.count)
    let mid = items.count / 2
    out.append(items[mid])
    var l = mid - 1, r = mid + 1
    while l >= 0 || r < items.count {
      if r < items.count { out.append(items[r]); r += 1 }
      if l >= 0 { out.append(items[l]); l -= 1 }
    }
    return out
  }
}
