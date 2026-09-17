import Foundation

/// 文案与数字格式（§A1.11，原型 `fmtNum / fmtVol / fmtTick / fmtFull`）。
///
/// 成交量 / 成交额走千进制金融单位 K / M / B / T（2026-09-18 用户决定，取代原型的万/亿）。

/// 时区口径（§9.4）：跟系统 / UTC / 交易所（固定 UTC+8）。
public enum TZChoice: String, Sendable, Codable, CaseIterable {
  case local, utc, exchange

  public var display: String {
    switch self {
    case .local: "本地"
    case .utc: "UTC"
    case .exchange: "交易所"
    }
  }

  /// 相对 UTC 的分钟偏移。`local` 取当下的系统偏移（夏令时会变，所以每次现问）。
  public var offsetMinutes: Int {
    switch self {
    case .utc: 0
    case .exchange: 480
    case .local: TimeZone.current.secondsFromGMT() / 60
    }
  }
}

/// 拆好的年月日时分（偏移已经加进去了，等价于原型的 `parts`）。
public struct DateParts: Sendable, Equatable {
  public var year: Int, month: Int, day: Int, hour: Int, minute: Int

  /// 毫秒时间戳 + 分钟偏移 → 各字段。用 civil-from-days 直接算，不走 Calendar。
  public init(ms: Double, offsetMinutes: Int) {
    let shifted = ms + Double(offsetMinutes) * 60_000
    let secs = Int(floor(shifted / 1000))
    var days = secs / 86_400
    var rem = secs % 86_400
    if rem < 0 { rem += 86_400; days -= 1 }
    hour = rem / 3600
    minute = (rem % 3600) / 60

    // Howard Hinnant 的 civil_from_days。
    var z = days + 719_468
    let era = (z >= 0 ? z : z - 146_096) / 146_097
    z -= era * 146_097
    let doe = z
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
    let y = yoe + era * 400
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    day = doy - (153 * mp + 2) / 5 + 1
    month = mp < 10 ? mp + 3 : mp - 9
    year = month <= 2 ? y + 1 : y
  }
}

@inlinable
func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

/// 时间轴刻度文案：≥180 天给年-月，≥1 天给月-日，跨零点给月-日，其余给时:分。
public func fmtTick(ms: Double, step: Double, offsetMinutes: Int) -> String {
  let p = DateParts(ms: ms, offsetMinutes: offsetMinutes)
  let day = 86_400_000.0
  if step >= 180 * day { return "\(p.year)-\(pad2(p.month))" }
  if step >= day { return "\(pad2(p.month))-\(pad2(p.day))" }
  if p.hour == 0 && p.minute == 0 { return "\(pad2(p.month))-\(pad2(p.day))" }
  return "\(pad2(p.hour)):\(pad2(p.minute))"
}

/// 十字线和详情里的完整时间。
public func fmtFull(ms: Double, offsetMinutes: Int) -> String {
  let p = DateParts(ms: ms, offsetMinutes: offsetMinutes)
  return "\(p.year)-\(pad2(p.month))-\(pad2(p.day)) \(pad2(p.hour)):\(pad2(p.minute))"
}

/// 本根倒计时的文案（K 线设置·本根倒计时）。
///
/// 三档，按「这一眼要看的是什么」分：
/// - 不到一小时：`mm:ss`。分钟不进位，59 分以内本来就只有两位。
/// - 一小时以上：`h:mm:ss`。小时不补零——`3:05:12` 比 `03:05:12` 窄，右轴那一格很挤。
/// - 一天以上（1d / 1w / 1M 这几档）：`Nd hh:mm`。到了这个量级秒没有意义，
///   每秒重画一次右轴纯属浪费帧。
///
/// 剩余时间 <= 0 或非数一律给 `nil`：收盘时刻已经过了就不该画这一格
/// （数据还没推进来的空档，画一个 `00:00` 反而像卡住了）。
public func fmtCountdown(msRemaining ms: Double) -> String? {
  guard ms.isFinite, ms > 0 else { return nil }
  let total = Int((ms / 1000).rounded(.down))
  let d = total / 86_400
  let h = (total % 86_400) / 3600
  let m = (total % 3600) / 60
  let s = total % 60
  if d > 0 { return "\(d)d \(pad2(h)):\(pad2(m))" }
  if total >= 3600 { return "\(h):\(pad2(m)):\(pad2(s))" }
  return "\(pad2(m)):\(pad2(s))"
}

/// 定点小数，非数给 `--`。
public func fmtNum(_ x: Double, _ p: Int) -> String {
  guard x.isFinite else { return "--" }
  return toFixed(x, p)
}

/// 成交量 / 持仓量 / 市值：K / M / B / T，两位小数；不满一千给原数。
public func fmtVol(_ x: Double) -> String {
  guard x.isFinite else { return "--" }
  return fmtVol(x, unit: volUnit(x))
}

/// 成交额用哪个单位。
///
/// 拆出来是为了「按品种固定单位」（§2B / 审查 §3.10 #53）：换一条行情线路，
/// 同一个品种回来的成交额口径可能差一截，数字一跨过进位的坎，单位就从 `M`
/// 翻成 `B`，顶栏那一格看上去像换了个品种。所以选单位这件事交给外面记住，
/// 不再每帧按当前数字现算。
public enum VolUnit: Int, Sendable, Equatable { case plain, k, m, b, t }

public func volUnit(_ x: Double) -> VolUnit {
  let a = abs(x)
  if a >= 1e12 { return .t }
  if a >= 1e9 { return .b }
  if a >= 1e6 { return .m }
  if a >= 1e3 { return .k }
  return .plain
}

public func fmtVol(_ x: Double, unit: VolUnit) -> String {
  guard x.isFinite else { return "--" }
  switch unit {
  case .t: return toFixed(x / 1e12, 2) + "T"
  case .b: return toFixed(x / 1e9, 2) + "B"
  case .m: return toFixed(x / 1e6, 2) + "M"
  case .k: return toFixed(x / 1e3, 2) + "K"
  case .plain: return abs(x) >= 100 ? toFixed(x, 0) : toFixed(x, 2)
  }
}

/// JS `Number.prototype.toFixed` 的语义：对**二进制精确值**四舍五入，逢五进一（远离零）。
///
/// `String(format:)` 用的是「逢五取偶」，`0.125` 会给 `0.12` 而 JS 给 `0.13`。
/// 先把精确十进制展开取足位数，再自己在第 p 位上进位，两边就一致了。
public func toFixed(_ x: Double, _ p: Int) -> String {
  guard x.isFinite else { return "\(x)" }
  guard p >= 0, p <= 100 else { return String(format: "%.\(max(0, p))f", x) }
  let neg = x < 0
  // 多要 25 位：精确展开若在第 p+1 位就终止（正好是 5），这些位才会全是 0。
  var s = String(format: "%.\(p + 25)f", abs(x))
  guard let dot = s.firstIndex(of: ".") else { return s }
  var digits = Array(s.replacingOccurrences(of: ".", with: "").utf8).map { Int($0) - 48 }
  let intLen = s.distance(from: s.startIndex, to: dot)
  let keep = intLen + p
  let roundUp = digits[keep] >= 5
  digits.removeSubrange(keep...)
  if roundUp {
    var i = digits.count - 1
    while i >= 0 {
      digits[i] += 1
      if digits[i] < 10 { break }
      digits[i] = 0
      i -= 1
    }
    if i < 0 { digits.insert(1, at: 0) }
  }
  let extra = digits.count - keep          // 进位可能多出一位整数
  let ip = digits.prefix(intLen + extra).map(String.init).joined()
  let fp = digits.suffix(p).map(String.init).joined()
  s = p > 0 ? "\(ip).\(fp)" : ip
  if s.count > 1, s.hasPrefix("0"), !s.hasPrefix("0.") { s.removeFirst() }
  return neg && digits.contains(where: { $0 != 0 }) ? "-" + s : s
}

/// 两个十六进制颜色按比例混，原型 `mixHex`。
public func mixHex(_ a: Hex, _ b: Hex, _ k: Double) -> Hex {
  // 原型在整数通道上混，输出 `toString(16)` 的小写；这里照办，别走浮点通道。
  let pa = a.bytes, pb = b.bytes
  let m = { (x: Int, y: Int) -> Int in Int((Double(x) * (1 - k) + Double(y) * k).rounded()) }
  return Hex(String(format: "#%02x%02x%02x", m(pa.r, pb.r), m(pa.g, pb.g), m(pa.b, pb.b)))
}
