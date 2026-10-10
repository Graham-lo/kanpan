import Testing
import Foundation
import KanpanCore
@testable import Kanpan

/// **值规则只写一处（`PrefsFieldPlan.rules`），iOS 的宽容解码必须守它。**
///
/// 服务端按契约里的规则收值（`Backend/kanpan-api/src/settings_rules.rs`），手机网页按同一份规则清洗
/// （`Web/src/sync/settingsRules.ts`）；`PrefsCodec` 的解码仍是一个字段一个字段手写的，这一组就是它的对账：
///
/// - 出厂值必须满足规则——不然新装第一次同步就被服务端当坏值丢掉；
/// - 契约里每一条「服务端拒收」的样例塞进存档，读回来再编出去必须**满足规则**（回落到出厂、夹到边上、
///   滤掉认不出的）——不然手改的档、更高版本写下的值会被原样推上去、被拒，那个字段从此悄悄不同步；
/// - 每一条「服务端收下」的样例，iOS 认得的那些读回来必须原样不变——不然另一台设备写的合法值到这台就丢了。
///
/// 红的时候：改 `PrefsCodec` 的解码（或者规则本身真的写错了，改 `PrefsFieldPlan.rules` 再 `make sync-contract`），不要改测试。
@Suite("跟人走字段的值规则")
struct PrefsFieldRulesTests {

  @Test("每个跟人走的字段都写了值规则，规则表里也没有多余的")
  func everySyncedFieldHasARule() {
    let synced = PrefsFieldPlan.names(.synced)
    let ruled = Set(PrefsFieldPlan.rules.keys)
    #expect(synced.subtracting(ruled).isEmpty, """
      \(synced.subtracting(ruled).sorted()) 是 `.synced` 字段，但 `PrefsFieldPlan.rules` 里没有它的值规则。
      去 Kanpan/Kanpan/Settings/Model/PrefsFieldRules.swift 加一行（能用通用描述就用通用描述，
      装不下的写 `.custom("<函数名>")` 并在服务端 sync_validation.rs 的 `custom_setting` 里加同名函数），再 `make sync-contract`。
      """)
    #expect(ruled.subtracting(synced).isEmpty, """
      \(ruled.subtracting(synced).sorted()) 在 `PrefsFieldPlan.rules` 里，却不是 `.synced` 字段——删掉那一行，
      或者把它在 `table` 里归成 `.synced`。
      """)
  }

  @Test("契约里的规则就是母表生成出来的")
  func contractRulesAreTheTable() throws {
    let contract = try SettingsFieldContract.decode(try SettingsFieldContract.readFromDisk())
    let want = PrefsFieldPlan.rules.mapValues(SettingsFieldContract.RuleDoc.init)
    let differ = Set(want.keys).union(contract.rules.keys).filter { want[$0] != contract.rules[$0] }.sorted()
    #expect(differ.isEmpty, """
      契约 `rules` 和 `PrefsFieldPlan.rules` 对不上的字段：\(differ)。契约是生成物：在仓库根跑 `make sync-contract`。
      """)
  }

  @Test("样例和规则自己说的一致")
  func samplesAgreeWithTheirRule() {
    for (name, rule) in PrefsFieldPlan.rules {
      let doc = SettingsFieldContract.RuleDoc(rule)
      for v in doc.accept ?? [] { #expect(RuleCheck.accepts(rule, v), "\(name) 的正样例 \(v) 自己的规则不收") }
      for v in doc.reject ?? [] { #expect(!RuleCheck.accepts(rule, v), "\(name) 的反样例 \(v) 自己的规则却收了") }
    }
  }

  @Test("出厂值满足规则")
  func factoryValuesPassTheirRules() throws {
    let wire = try Self.wire(PrefsCodec.encode(.defaults))
    for (name, rule) in PrefsFieldPlan.rules {
      if case .custom = rule { continue }
      let value = try #require(wire[name], "出厂存档里没有 \(name)")
      #expect(RuleCheck.accepts(rule, value), """
        `\(name)` 的出厂值 \(value) 不满足它的值规则 \(rule)——新装第一次同步，服务端就把它当坏值丢掉。
        改出厂值，或者规则写错了改 `PrefsFieldPlan.rules`。
        """)
    }
  }

  @Test("服务端拒收的值读进来会回落，不会原样再推上去")
  func illegalValuesFallBack() throws {
    let factory = try Self.wire(PrefsCodec.encode(.defaults))
    for (name, rule) in PrefsFieldPlan.rules {
      if case .custom = rule { continue }
      for bad in SettingsFieldContract.RuleDoc(rule).reject ?? [] {
        let back = try Self.roundTrip(name, bad)
        #expect(RuleCheck.accepts(rule, back), """
          `\(name)` 存档里是服务端拒收的 \(bad)，`PrefsCodec` 读回来再编出去是 \(back)，仍然不满足规则 \(rule)：
          它会被原样推上去、被服务端丢掉。改 `PrefsCodec.init(from:)` 里这一项的解码，让它回落。
          """)
        // 标量的回落就是出厂值（数值例外：越界的夹到边上，那也满足规则，上面已经查过）。
        switch rule {
        case .bool, .enumeration, .string, .interval:
          #expect(back == factory[name], "`\(name)` 读到 \(bad) 应该退回出厂值 \(String(describing: factory[name]))，读出来是 \(back)")
        default: break
        }
      }
    }
  }

  @Test("服务端收下的值、iOS 认得的，读回来原样不变")
  func legalValuesSurvive() throws {
    for (name, rule) in PrefsFieldPlan.rules {
      if case .custom = rule { continue }
      for good in SettingsFieldContract.RuleDoc(rule).accept ?? [] {
        let back = try Self.roundTrip(name, good)
        #expect(RuleCheck.accepts(rule, back), "`\(name)` 读进合法值 \(good)，编出去 \(back) 反而不满足规则")
        // 数组与计次表本机可以更严（常用行只钉 6 档、副图最多三个、0 次不记），只要求读回来仍合法。
        switch rule {
        case .bool, .enumeration, .number, .int, .interval:
          #expect(back == good, "`\(name)` 读进合法值 \(good)，读回来变成了 \(back)：另一台设备写的值到这台就丢了")
        case .string(_, let known):
          if known == nil || known!.contains(good.stringValue ?? "\u{0}") {
            #expect(back == good, "`\(name)` 读进合法值 \(good)，读回来变成了 \(back)")
          }
        default: break
        }
      }
    }
  }

  // MARK: 存档往返

  /// 出厂存档里把 `name` 换成 `value`，经 `PrefsCodec` 读回来再编出去，取那一项。
  static func roundTrip(_ name: String, _ value: WireValue) throws -> WireValue {
    var archive = try wire(PrefsCodec.encode(.defaults))
    archive[name] = value
    let data = try JSONEncoder().encode(archive)
    let back = try wire(PrefsCodec.encode(PrefsCodec.decode(data)))
    return back[name] ?? .null
  }

  static func wire(_ data: Data) throws -> [String: WireValue] {
    try JSONDecoder().decode([String: WireValue].self, from: data)
  }
}

// MARK: - 规则的 Swift 读法（只给测试用：和服务端 settings_rules.rs、网页 settingsRules.ts 同一套语义）

enum RuleCheck {
  /// 服务端在同步里认的周期：现行的，加上老存档里还有的（`instruments.json` 的 `legacyIntervals`）。
  static let syncedIntervals = Set(Interval.allCases.map(\.rawValue)).union(["8h", "3d"])

  static func accepts(_ rule: PrefsFieldRule, _ v: WireValue) -> Bool {
    switch rule {
    case .bool:
      if case .bool = v { return true }
      return false
    case .enumeration(let values):
      return v.stringValue.map(values.contains) ?? false
    case .string(let maxBytes, _):
      return v.stringValue.map { $0.utf8.count <= maxBytes } ?? false
    case .number(let lo, let hi):
      guard case .number(let n) = v else { return false }
      return n.isFinite && n >= lo && n <= hi
    case .int(let lo, let hi):
      guard case .number(let n) = v else { return false }
      return n == n.rounded() && n >= Double(lo) && n <= Double(hi)
    case .interval:
      return v.stringValue.map(syncedIntervals.contains) ?? false
    case .intervals(let maxCount):
      guard case .array(let a) = v else { return false }
      return a.count <= maxCount && a.allSatisfy { $0.stringValue.map(syncedIntervals.contains) ?? false }
    case .stringArray(let values, let maxCount, let unique):
      guard case .array(let a) = v, a.count <= maxCount else { return false }
      let strings = a.compactMap(\.stringValue)
      guard strings.count == a.count, strings.allSatisfy(values.contains) else { return false }
      return !unique || Set(strings).count == strings.count
    case .countMap(let keys, let maxKeys, let max):
      guard case .object(let o) = v, o.count <= maxKeys else { return false }
      return o.allSatisfy { k, n in
        guard keys.contains(k), case .number(let x) = n else { return false }
        return x == x.rounded() && x >= 0 && x <= Double(max)
      }
    case .custom:
      return true
    }
  }
}

// MARK: - 契约里的规则长什么样

extension SettingsFieldContract {
  /// 一条规则在契约里的写法。键名就是网页 / 服务端读的那些，没有的项不写。
  struct RuleDoc: Codable, Equatable {
    var type: String
    var values: [String]?
    var known: [String]?
    var keys: [String]?
    var maxBytes: Int?
    var maxCount: Int?
    var maxKeys: Int?
    var unique: Bool?
    var min: Double?
    var max: Double?
    var name: String?
    /// 服务端必须收下的样例。
    var accept: [WireValue]?
    /// 服务端必须拒收的样例。
    var reject: [WireValue]?

    init(_ rule: PrefsFieldRule) {
      type = ""
      switch rule {
      case .bool:
        type = "bool"
        accept = [.bool(true), .bool(false)]
        reject = [.number(1), .string("true"), .null]
      case .enumeration(let values):
        type = "enum"; self.values = values
        accept = values.map(WireValue.string)
        reject = [.string("__unknown__"), .number(1), .null] + (values.contains("") ? [] : [.string("")])
      case .string(let maxBytes, let known):
        type = "string"; self.maxBytes = maxBytes; self.known = known
        // 「数字节不数字符」：maxBytes / 3 个汉字收得下，多一个就超了——字符数远没到上限。
        accept = [.string(""), .string(String(repeating: "a", count: maxBytes)), .string(String(repeating: "汉", count: maxBytes / 3))]
          + (known ?? []).map(WireValue.string)
        reject = [.string(String(repeating: "a", count: maxBytes + 1)), .string(String(repeating: "汉", count: maxBytes / 3 + 1)),
                  .number(1), .bool(true), .null]
      case .number(let lo, let hi):
        type = "number"; min = lo; max = hi
        let step = Swift.max(0.1, abs(lo) * 0.1)
        accept = [.number(lo), .number(hi), .number((lo + hi) / 2)]
        reject = [.number(lo - step), .number(hi + step), .string(String(lo)), .bool(true), .null]
      case .int(let lo, let hi):
        type = "int"; min = Double(lo); max = Double(hi)
        accept = [.number(Double(lo)), .number(Double(hi))]
        reject = [.number(Double(lo) - 1), .number(Double(hi) + 1), .string(String(lo)), .null]
          + (hi > lo ? [.number(Double(lo) + 0.5)] : [])
      case .interval:
        type = "interval"
        accept = Interval.allCases.map { .string($0.rawValue) }
        reject = [.string("7m"), .string(""), .number(1), .null]
      case .intervals(let maxCount):
        type = "intervals"; self.maxCount = maxCount
        let all = Interval.allCases.map { WireValue.string($0.rawValue) }
        accept = [.array([]), .array(Array(all.prefix(maxCount)))]
        reject = [.array([.string("7m")]), .string("1h"), .array([.number(1)]), .null]
          + (all.count > maxCount ? [.array(Array(all.prefix(maxCount + 1)))] : [])
      case .stringArray(let values, let maxCount, let unique):
        type = "stringArray"; self.values = values; self.maxCount = maxCount; self.unique = unique
        let first = WireValue.string(values[0])
        accept = [.array([]), .array([first]), .array(values.prefix(maxCount).map(WireValue.string))]
        reject = [.array([.string("__unknown__")]), first, .array([.number(1)]), .null,
                  .array(Array(repeating: first, count: maxCount + 1))]
        if maxCount >= 2 {
          if unique { reject!.append(.array([first, first])) } else { accept!.append(.array([first, first])) }
        }
      case .countMap(let keys, let maxKeys, let max):
        type = "countMap"; self.keys = keys; self.maxKeys = maxKeys; self.max = Double(max)
        let k = keys[0]
        accept = [.object([:]), .object([k: .number(0)]), .object([k: .number(Double(max))]),
                  .object(Dictionary(uniqueKeysWithValues: keys.prefix(maxKeys).map { ($0, WireValue.number(1)) }))]
        reject = [.object([k: .number(-1)]), .object([k: .number(Double(max) + 1)]), .object([k: .number(1.5)]),
                  .object([k: .string("3")]), .object(["__unknown__": .number(1)]), .array([.string(k)]), .string(k), .null]
          + (keys.count > maxKeys
            ? [.object(Dictionary(uniqueKeysWithValues: keys.prefix(maxKeys + 1).map { ($0, WireValue.number(1)) }))] : [])
      case .custom(let name):
        type = "custom"; self.name = name
      }
    }
  }
}

/// 任意 JSON 值（契约样例、存档里的一项）。数一律按 `Double` 存：整数编出来照样是 `100000`，不带小数点。
enum WireValue: Codable, Equatable, CustomStringConvertible {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([WireValue])
  case object([String: WireValue])

  var stringValue: String? { if case .string(let s) = self { return s }; return nil }

  init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() { self = .null }
    else if let b = try? c.decode(Bool.self) { self = .bool(b) }
    else if let n = try? c.decode(Double.self) { self = .number(n) }
    else if let s = try? c.decode(String.self) { self = .string(s) }
    else if let a = try? c.decode([WireValue].self) { self = .array(a) }
    else { self = .object(try c.decode([String: WireValue].self)) }
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .null: try c.encodeNil()
    case .bool(let b): try c.encode(b)
    case .number(let n): try c.encode(n)
    case .string(let s): try c.encode(s)
    case .array(let a): try c.encode(a)
    case .object(let o): try c.encode(o)
    }
  }

  var description: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return (try? String(decoding: encoder.encode(self), as: UTF8.self)) ?? "?"
  }
}
