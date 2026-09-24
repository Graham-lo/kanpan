import Foundation

/// 文案与数字格式（§A1.11，原型 `fmtNum / fmtVol / fmtTick / fmtFull`）。
///
/// 成交量 / 成交额走千进制金融单位 K / M / B / T（2026-09-18 用户决定，取代原型的万/亿）。

/// 时区口径（§9.4）：跟系统 / UTC / 交易所（固定 UTC+8）。
///
/// case 名 `exchange` 不动——它是存档与同步里的原值。界面上写什么在 KanpanPresentation
/// 的 `TZChoice.display`。
public enum TZChoice: String, Sendable, Codable, CaseIterable {
  case local, utc, exchange

  /// 相对 UTC 的偏移**口径**——注意它不是一个数，而是一条「怎么算偏移」的规则（审查 B-08）。
  ///
  /// 原来这里直接给 `TimeZone.current.secondsFromGMT() / 60`，也就是**此刻**的偏移，
  /// 然后拿它去格式化历史上的每一根 K 线。于是夏天打开 app 看纽约的冬季行情，
  /// 整段历史会整体平移一小时：`2026-01-05 09:30` 的开盘被写成 `10:30`。
  /// 正确的口径是「被格式化的那个时刻当时的偏移」，所以这里交出去的是 `TZOffset`，
  /// 由 `fmtTick` / `fmtFull` / `DateParts` 在知道 ms 之后再问一次。
  ///
  /// 名字保留 `offsetMinutes` 不改，是为了让图表层那些
  /// `fmtFull(ms:, offsetMinutes: state.timezone.offsetMinutes)` 的调用点一个字都不用动。
  public var offsetMinutes: TZOffset {
    switch self {
    case .utc: .fixed(0)
    case .exchange: .fixed(480)      // 交易所口径固定 UTC+8，不随任何地方的夏令时动
    case .local: .zone(.autoupdatingCurrent)
    }
  }
}

/// 「怎么把 UTC 毫秒换成挂在墙上的那个时间」——固定偏移，或者某个真实时区在那一刻的偏移。
///
/// 两条分支的区别只在夏令时：`fixed` 永远是同一个数（UTC、交易所 +8 都是这种），
/// `zone` 要拿被格式化的那个时刻去问时区数据库（纽约冬天 −5、夏天 −4）。
public struct TZOffset: Sendable, Equatable {
  public enum Basis: Sendable, Equatable {
    case fixed(Int)                  // 分钟
    case zone(TimeZone)
  }
  public var basis: Basis
  public init(_ basis: Basis) { self.basis = basis }

  public static func fixed(_ minutes: Int) -> TZOffset { .init(.fixed(minutes)) }
  public static func zone(_ zone: TimeZone) -> TZOffset { .init(.zone(zone)) }
  /// 跟着系统走，且系统在运行中改了时区也跟得上。
  public static var system: TZOffset { .zone(.autoupdatingCurrent) }

  /// 交给系统控件（`DatePicker`、SwiftUI 的 `\.timeZone` 环境值）用的那份时区。
  ///
  /// 显示一律走 `minutes(at:)`，这里只服务「让用户在原生控件里挑一个时刻」的场合：
  /// 挑的时候和挑完写出来的必须是同一个时区，否则设了 20:00 到期、列表里写 12:00。
  public var timeZone: TimeZone {
    switch basis {
    case .fixed(let m): return TimeZone(secondsFromGMT: m * 60) ?? .gmt
    case .zone(let z): return z
    }
  }

  /// 指定时刻的偏移（分钟）。这是整条时区口径的唯一入口。
  public func minutes(at ms: Double) -> Int {
    switch basis {
    case .fixed(let m): return m
    case .zone(let z):
      guard ms.isFinite else { return z.secondsFromGMT() / 60 }
      return z.secondsFromGMT(for: Date(timeIntervalSince1970: ms / 1000)) / 60
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

/// 拆好的年月日时分，偏移按**这个时刻**的口径算（跨夏令时的历史才不会整段平移）。
extension DateParts {
  public init(ms: Double, offsetMinutes: TZOffset) {
    self.init(ms: ms, offsetMinutes: offsetMinutes.minutes(at: ms))
  }
}

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

/// 同上，但偏移按被格式化的那个时刻现问（审查 B-08）。
public func fmtTick(ms: Double, step: Double, offsetMinutes: TZOffset) -> String {
  fmtTick(ms: ms, step: step, offsetMinutes: offsetMinutes.minutes(at: ms))
}

public func fmtFull(ms: Double, offsetMinutes: TZOffset) -> String {
  fmtFull(ms: ms, offsetMinutes: offsetMinutes.minutes(at: ms))
}

/// 复盘选区那种「几月几日 时:分」的短时间。和十字线同一个口径（同一个 `TZOffset`），
/// 不再各自 `DateFormatter()` 拿设备时区、也不跟随地区习惯换分隔符（审查 B-07 / B-08）。
func fmtDayTime(ms: Double, offsetMinutes: TZOffset) -> String {
  let p = DateParts(ms: ms, offsetMinutes: offsetMinutes)
  return "\(p.month)/\(p.day) \(pad2(p.hour)):\(pad2(p.minute))"
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

/// 价格文案：小数位由品种自己说（`SymbolInfo.priceDecimals`），
/// 不再按数值大小现猜几位（审查 B-07：同一个价在头部、板块页、复盘浮层给出三种写法）。
///
/// 唯一的例外是**极小的正价**：如果按品种的位数四舍五入之后变成了 0，
/// 就自动多给几位直到第一个有效数字露出来。一个真实存在的价显示成 `0.00`
/// 比少两位小数严重得多——那等于告诉用户这东西不要钱。
public func fmtPrice(_ x: Double, decimals: Int) -> String {
  guard x.isFinite else { return "--" }
  let p = max(0, min(12, decimals))
  let s = toFixed(x, p)
  // 「舍完是不是 0」看字面有没有非零数字就够了，不必再把字符串解析回 `Double`。
  guard x != 0, !s.utf8.contains(where: { $0 >= 49 && $0 <= 57 }) else { return s }
  let need = min(12, Int(ceil(-log10(abs(x)))) + 1)
  return toFixed(x, max(p, need))
}

/// 品种表还没到时的临时小数位。**只在这一种情形下用。**
///
/// 正常路径上小数位一律由品种自己说（`SymbolInfo.priceDecimals`）；这把梯子是给
/// 「冷启动第一帧目录还没回来」「自选里那个代号不在这份目录里」这两种空档用的。
/// 单独放在这儿是为了全 app 只有一把：原来自选页写死 2 位、板块页另有一套
/// 2/4/5/7，于是同一个价在两页上写法不同（审查 B-07）。
///
/// 梯子按 2026-09-23 全目录普查（P4.8）重排：拿币安 776 个在报价合约的现价和真实步长对照，
/// 旧梯子（≥0.01 给 5 位、再往下 7 位）在 39 个合约上少一位（`COTI` 0.017 步长 6 位、
/// `1000SATS` 0.0000123 步长 8 位）；拆成 0.1 / 0.01 / 0.001 三档之后只剩 2 个（`USDC`、`BR`）。
/// 空档里宁可末尾多一个 0，也不能把一位有效数字吃掉。
public func priceDecimalsFallback(_ price: Double) -> Int {
  let magnitude = abs(price)
  return if !magnitude.isFinite { 2 }
    else if magnitude >= 100 { 2 } else if magnitude >= 1 { 4 }
    else if magnitude >= 0.1 { 5 } else if magnitude >= 0.01 { 6 }
    else if magnitude >= 0.001 { 7 } else { 8 }
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
///
/// 图上每一帧的刻度、图例、最新价都要过它（审查 24：每帧 `String(format:)`），所以分两条路：
/// 放大后装得进 2^52 的（价格、成交量、百分比几乎全是）走整数快路，不碰 `String(format:)`；
/// 装不下的退回下面 `toFixedReference` 那条「精确展开再进位」的老路。两条路逐位一致，
/// 由「定点小数快路与精确展开逐位一致」那条随机对拍测试守着。
public func toFixed(_ x: Double, _ p: Int) -> String {
  if let fast = toFixedFast(x, p) { return fast }
  return toFixedReference(x, p)
}

/// 10 的 0…15 次方，全都是精确的 `Double`。
private let pow10Table: [Double] = (0...15).map { p in (0..<p).reduce(1.0) { a, _ in a * 10 } }

/// 整数快路：`|x|·10^p` 的精确值拆成「乘出来的 `Double`」加「乘法舍掉的那点误差」，
/// 误差用 FMA 精确求出（`s` 是精确的 10 的幂，`x·s` 的舍入误差本身就是一个 `Double`）。
/// 然后在精确值上按「逢五进一」取整——判的是二进制精确值，不是乘完舍入过的那个，
/// 所以 `1.005`（精确值是 1.00499999…）照样给 `1.00`，和 JS 一样。
///
/// 返回 `nil` 表示这条路不管（位数太多、数太大、非数），交给精确展开。
func toFixedFast(_ x: Double, _ p: Int) -> String? {
  guard x.isFinite, p >= 0, p < pow10Table.count else { return nil }
  let s = pow10Table[p]
  let a = abs(x)
  let scaled = a * s
  // 2^52 以内：`scaled` 的小数部分精确可表示，取整后的整数也放得进 Int64。
  guard scaled < 4_503_599_627_370_496 else { return nil }
  let err = (-scaled).addingProduct(a, s)   // a·s − scaled，一次舍入的 FMA，精确
  let whole = scaled.rounded(.down)
  let frac = scaled - whole               // 精确（同一量级内相减）
  // 真值 = whole + frac + err，|err| ≤ scaled 的半个 ulp，而 frac 是 ulp 的整数倍：
  // frac ≠ 0.5 时 err 改变不了它在 0.5 哪一边；正好 0.5 时看 err 的符号（= 0 就是真的逢五，进）。
  let up = frac > 0.5 || (frac == 0.5 && err >= 0)
  let n = Int64(whole) + (up ? 1 : 0)
  var digits = String(n)
  if p > 0 {
    if digits.utf8.count <= p {
      digits = String(repeating: "0", count: p + 1 - digits.utf8.count) + digits
    }
    digits.insert(".", at: digits.index(digits.endIndex, offsetBy: -p))
  }
  // 和老路一致：舍入后全是 0 的负数不带负号（`-0.001` → `0.00`）。
  return x < 0 && n != 0 ? "-" + digits : digits
}

/// 精确展开再进位：先把二进制精确值展开取足位数，再自己在第 p 位上进位。
/// 快路装不下的数走这里；测试拿它当对拍的标准答案。
func toFixedReference(_ x: Double, _ p: Int) -> String {
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

/// 全 app 唯一的涨跌幅写法（审查 U9）。参数是百分数（2.74 就是 2.74%），两位小数，
/// 取整走 `toFixed`（和原型同一把逢五进位）。
///
/// * 带符号「+2.74%」「−2.74%」。负号用数学减号 U+2212，不用连字符——
///   它和「+」、和等宽数字一样宽，一列涨跌上下对得齐（顶栏涨跌额从来就是这么写的）。
/// * 四舍五入后是 0.00 的一律「+0.00%」，不会冒出「−0.00%」。
/// * 全 app 的涨跌只有「符号 + 颜色」一种说法，不再有 ▲▼ 小三角配绝对值那一路（UI 整改 P1c，
///   原来的 `arrow:` 参数随最后两处调用——分享截图药丸、板块行——一起删了）。
/// * 缺数（`nil`、NaN、无穷）写 `missing`，默认「—」。小组件和实时活动传「--」：那两处的价格
///   走 `fmtPrice` 一族，缺数本来就写「--」，同一行里两种占位更难看。
public func changePercentText(_ percent: Double?, missing: String = "—") -> String {
  guard let percent, percent.isFinite else { return missing }
  let magnitude = toFixed(abs(percent), 2)
  let zero = !magnitude.contains(where: { $0 != "0" && $0 != "." })
  return (percent < 0 && !zero ? "\u{2212}" : "+") + magnitude + "%"
}

/// 两个十六进制颜色按比例混，原型 `mixHex`。
public func mixHex(_ a: Hex, _ b: Hex, _ k: Double) -> Hex {
  // 原型在整数通道上混，输出 `toString(16)` 的小写；这里照办，别走浮点通道。
  let pa = a.bytes, pb = b.bytes
  let m = { (x: Int, y: Int) -> Int in Int((Double(x) * (1 - k) + Double(y) * k).rounded()) }
  return Hex(String(format: "#%02x%02x%02x", m(pa.r, pb.r), m(pa.g, pb.g), m(pa.b, pb.b)))
}
