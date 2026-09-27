import Foundation

/// 条件提醒的条件本体（`Alert.rule`）。
///
/// 线上形状按 `docs/条件提醒-协议-2026-09-27.md` 第 2 节一字不差：比例与金额是**十进制字符串**
/// （只有 `.`、可带前导 `-`、不用科学计数法、不带千分位），比例是比值不是百分数（`"0.0005"` = 0.05%），
/// 只有均线的 `length` 是 JSON 整数。服务端 `conditions.rs` 的 `Rule::parse` 按同一张表卡。
///
/// 认不得的 `type`（将来的新条件）、以及已知 `type` 但字段不合规的，一律原样留在 `.unknown` 里：
/// 编码时整份写回去，不丢字段——`rule` 在 `PersonalSyncCodec.ownedKeys` 里，丢了就是替那条提醒
/// 把条件删了，服务端再按「condition 没有 rule」整条拒收，这台手机的同步队列就堵住了。
public enum AlertRule: Sendable, Equatable, Codable {
  public enum Side: String, Sendable, Codable, CaseIterable { case above, below }

  /// 结算前 15 分钟的预测费率 ≥（above）/ ≤（below）`rate`（比值）。
  case funding(side: Side, rate: String)
  /// 1 小时持仓量（币数量）变化幅度的绝对值 ≥ `threshold`（比值）。
  case openInterestChange(threshold: String)
  /// `interval` 周期收盘站上 / 跌破 MA`length`（边沿触发）。
  case maCross(interval: String, length: Int, side: Side)
  /// 出现一面名义 ≥ `threshold` 美元的新大单墙。
  case orderflowWall(threshold: String)
  /// 这一版认不得的条件：收下、存着、原样写回，不判。
  case unknown(RuleJSON)

  /// 均线能选的周期：客户端周期代号去掉 `1y`（币安没有年线）。
  public static let maIntervals = ["1m", "3m", "5m", "15m", "30m", "1h", "2h", "4h", "6h", "12h", "1d", "1w", "1M"]
  public static let maxLength = 1000
  /// 协议里各字段的取值范围。
  public static let fundingLimit = Decimal(string: "0.1")!
  public static let oiRange = Decimal(string: "0.001")!...Decimal(10)
  public static let wallRange = Decimal(10_000)...Decimal(10_000_000_000)

  /// 协议里的 `type`。
  public var type: String {
    switch self {
    case .funding: "funding"
    case .openInterestChange: "openInterestChange"
    case .maCross: "maCross"
    case .orderflowWall: "orderflowWall"
    case .unknown(let raw): raw.object?["type"]?.string ?? ""
    }
  }

  /// 这一版认不认得（认得的才判、才能在表单里改）。
  public var isKnown: Bool { if case .unknown = self { false } else { true } }

  // ---------------------------------------------------------------- 线协议

  public init(from decoder: any Decoder) throws {
    let raw = try RuleJSON(from: decoder)
    self = AlertRule.parse(raw) ?? .unknown(raw)
  }

  public func encode(to encoder: any Encoder) throws { try json.encode(to: encoder) }

  /// 整份 JSON。
  public var json: RuleJSON {
    switch self {
    case .funding(let side, let rate):
      .object(["type": .string("funding"), "side": .string(side.rawValue), "rate": .string(rate)])
    case .openInterestChange(let threshold):
      .object(["type": .string("openInterestChange"), "threshold": .string(threshold)])
    case .maCross(let interval, let length, let side):
      .object(["type": .string("maCross"), "interval": .string(interval), "length": .int(length), "side": .string(side.rawValue)])
    case .orderflowWall(let threshold):
      .object(["type": .string("orderflowWall"), "threshold": .string(threshold)])
    case .unknown(let raw): raw
    }
  }

  /// 按协议再卡一遍：合规就是它自己，不合规（范围外、字符串不规范）nil。表单交之前用。
  public var checked: AlertRule? { isKnown ? AlertRule.parse(json) : nil }

  /// 表单里写的百分数（`0.05`、`-0.01`、`.5`、`3%`）→ 比值的规范字符串（`"0.0005"`）。写不成数 nil。
  public static func ratio(percent text: String) -> String? {
    var s = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
    if s.hasSuffix("%") { s.removeLast() }
    s = s.trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("+") { s.removeFirst() }
    if s.hasPrefix(".") { s = "0" + s } else if s.hasPrefix("-.") { s = "-0" + s.dropFirst() }
    if s.hasSuffix(".") { s.removeLast() }
    guard let d = decimal(s) else { return nil }
    return AlertRule.text(d / 100)
  }

  /// 表单里写的金额（`5M`、`800K`）→ 规范字符串（`"5000000"`）。写不成数 nil。
  public static func amount(_ text: String) -> String? {
    parseAmount(text).map { AlertRule.text($0) }
  }

  /// 按协议第 2 节严格解；形状不对返回 nil（调用方收进 `.unknown`）。
  static func parse(_ raw: RuleJSON) -> AlertRule? {
    guard let o = raw.object, let type = o["type"]?.string else { return nil }
    func side() -> Side? { o["side"]?.string.flatMap(Side.init(rawValue:)) }
    func decimal(_ key: String, in range: ClosedRange<Decimal>) -> String? {
      guard let text = o[key]?.string, let d = AlertRule.decimal(text), range.contains(d) else { return nil }
      return text
    }
    switch type {
    case "funding":
      guard let side = side(), let rate = decimal("rate", in: -fundingLimit...fundingLimit) else { return nil }
      return .funding(side: side, rate: rate)
    case "openInterestChange":
      return decimal("threshold", in: oiRange).map { .openInterestChange(threshold: $0) }
    case "maCross":
      guard let interval = o["interval"]?.string, maIntervals.contains(interval),
            let length = o["length"]?.int, (1...maxLength).contains(length), let side = side() else { return nil }
      return .maCross(interval: interval, length: length, side: side)
    case "orderflowWall":
      return decimal("threshold", in: wallRange).map { .orderflowWall(threshold: $0) }
    default:
      return nil
    }
  }

  /// 规范的十进制字符串 → Decimal；不规范（科学计数法、千分位、`+`、空的小数部分…）返回 nil。
  /// 和服务端 `sync_validation::decimal` 同一条：整数部分 1–12 位、小数部分 1–18 位。
  public static func decimal(_ text: String) -> Decimal? {
    let body = text.hasPrefix("-") ? String(text.dropFirst()) : text
    let parts = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    let whole = parts[0]
    guard !whole.isEmpty, whole.count <= 12, whole.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
    if parts.count > 1 {
      let fraction = parts[1]
      guard !fraction.isEmpty, fraction.count <= 18, fraction.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
    }
    return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
  }

  /// Decimal → 规范的十进制字符串（不带科学计数法、去掉尾巴上的 0）。
  public static func text(_ value: Decimal) -> String {
    var v = value
    var out = Decimal()
    NSDecimalRound(&out, &v, 18, .plain)
    let s = NSDecimalNumber(decimal: out).stringValue
    return s == "-0" ? "0" : s
  }

  // ---------------------------------------------------------------- 文案

  /// 服务端 `Rule::phrase`：`{条件}`，也是默认标题去掉品种名那一段。
  /// 「资金费率高于 0.05%」「1 小时持仓量变化超过 5%」「4h 收盘站上 MA20」「出现 5M 以上的大单墙」。
  public var phrase: String {
    switch self {
    case .funding(let side, let rate):
      "资金费率\(side == .above ? "高于" : "低于") \(AlertRule.percent(rate, dp: 6))%"
    case .openInterestChange(let threshold):
      "1 小时持仓量变化超过 \(AlertRule.percent(threshold, dp: 4))%"
    case .maCross(let interval, let length, let side):
      "\(interval) 收盘\(side == .above ? "站上" : "跌破") MA\(length)"
    case .orderflowWall(let threshold):
      "出现 \(AlertRule.units(AlertRule.decimal(threshold).map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0)) 以上的大单墙"
    case .unknown:
      "条件提醒"
    }
  }

  /// 提醒列表那一行的短句：「费率高于 0.05%」「1 小时持仓量变化超过 3%」「1h 收盘站上 MA 20」「出现超过 5M 的挂单墙」。
  public var rowText: String {
    switch self {
    case .funding(let side, let rate):
      "费率\(side == .above ? "高于" : "低于") \(AlertRule.percent(rate, dp: 6))%"
    case .openInterestChange(let threshold):
      "1 小时持仓量变化超过 \(AlertRule.percent(threshold, dp: 4))%"
    case .maCross(let interval, let length, let side):
      "\(interval) 收盘\(side == .above ? "站上" : "跌破") MA \(length)"
    case .orderflowWall(let threshold):
      "出现超过 \(AlertRule.units(AlertRule.decimal(threshold).map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0)) 的挂单墙"
    case .unknown:
      "条件提醒"
    }
  }

  /// 比值 → 百分数的数字部分（`"0.0005"` → `"0.05"`），最多 `dp` 位小数、四舍五入（中点远离 0）、去掉尾巴上的 0。
  /// 服务端 `conditions::percent`。
  public static func percent(_ ratio: String, dp: Int) -> String {
    guard let d = decimal(ratio) else { return ratio }
    return percent(d, dp: dp)
  }

  public static func percent(_ ratio: Decimal, dp: Int) -> String {
    var scaled = ratio * 100
    var out = Decimal()
    NSDecimalRound(&out, &scaled, dp, .plain)
    let s = NSDecimalNumber(decimal: out).stringValue
    return s == "-0" ? "0" : s
  }

  /// 带符号的百分数（`+6.21%` / `-3.5%` / `0%`）。服务端 `signed_percent`。
  public static func signedPercent(_ ratio: Decimal, dp: Int) -> String {
    let text = percent(ratio, dp: dp)
    return ratio > 0 && !text.hasPrefix("-") ? "+\(text)%" : "\(text)%"
  }

  /// 金额的 K / M / B / T（`12400000` → `12.4M`，`5000000` → `5M`）。服务端 `conditions::units`。
  public static func units(_ v: Double) -> String {
    let a = abs(v)
    let (n, u): (Double, String) = a >= 1e12 ? (v / 1e12, "T") : a >= 1e9 ? (v / 1e9, "B")
      : a >= 1e6 ? (v / 1e6, "M") : a >= 1e3 ? (v / 1e3, "K") : (v, "")
    var text = String(format: "%.1f", n)
    if text.hasSuffix(".0") { text.removeLast(2) }
    return text + u
  }

  /// 用户在表单里写的金额（`5M`、`1.5m`、`800K`、`2000000`、`1,000,000`）→ 美元数。写不成数返回 nil。
  public static func parseAmount(_ text: String) -> Decimal? {
    var s = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "").uppercased()
    guard !s.isEmpty else { return nil }
    var scale = Decimal(1)
    if let last = s.last, let mult = ["K": Decimal(1_000), "M": Decimal(1_000_000), "B": Decimal(1_000_000_000), "T": Decimal(1_000_000_000_000)][String(last)] {
      scale = mult; s.removeLast()
    }
    guard let d = decimal(s), d > 0 else { return nil }
    return d * scale
  }

  /// 通知正文里的价（服务端 `alerts::money`）：≥ 1000 取整、≥ 1 两位、≥ 0.01 四位、更小八位，千分位。
  public static func money(_ v: Double) -> String {
    let m = abs(v)
    let dp = m >= 1000 ? 0 : m >= 1 ? 2 : m >= 0.01 ? 4 : 8
    let text = String(format: "%.\(dp)f", v)
    let neg = text.hasPrefix("-")
    let body = neg ? String(text.dropFirst()) : text
    let parts = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    let whole = Array(parts[0])
    var grouped = ""
    for (i, c) in whole.enumerated() {
      if i > 0, (whole.count - i) % 3 == 0 { grouped.append(",") }
      grouped.append(c)
    }
    return (neg ? "-" : "") + grouped + (parts.count > 1 ? "." + parts[1] : "")
  }
}

/// `rule` 的原样 JSON（认不得的条件整份留着写回去）。
public indirect enum RuleJSON: Sendable, Equatable, Codable {
  case null
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case array([RuleJSON])
  case object([String: RuleJSON])

  public var object: [String: RuleJSON]? { if case .object(let o) = self { o } else { nil } }
  public var string: String? { if case .string(let s) = self { s } else { nil } }
  public var int: Int? {
    switch self {
    case .int(let i): i
    case .double(let d) where d.rounded() == d && abs(d) < 1e15: Int(d)
    default: nil
    }
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() { self = .null }
    else if let b = try? c.decode(Bool.self) { self = .bool(b) }
    else if let i = try? c.decode(Int.self) { self = .int(i) }
    else if let d = try? c.decode(Double.self) { self = .double(d) }
    else if let s = try? c.decode(String.self) { self = .string(s) }
    else if let a = try? c.decode([RuleJSON].self) { self = .array(a) }
    else { self = .object(try c.decode([String: RuleJSON].self)) }
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .null: try c.encodeNil()
    case .bool(let b): try c.encode(b)
    case .int(let i): try c.encode(i)
    case .double(let d): try c.encode(d)
    case .string(let s): try c.encode(s)
    case .array(let a): try c.encode(a)
    case .object(let o): try c.encode(o)
    }
  }
}
