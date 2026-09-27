import Foundation
import KanpanCore

/// 「按我的习惯自动调整」学到的结论。随账号同步的只有这一份（`Prefs.learnedDefaults`，
/// 整份一个字段），推它的行为日志（`HabitLog`）只留在本机。
///
/// 四张表，一张一件事：
///
/// - `intervals`：品种规范键 → 打开这只时用的周期（`Interval.rawValue`）。
/// - `priceAxis`：类别（`HabitCategory`）→ `linear` / `log`。
/// - `sectorWindow`：板块市场（`SectorMarket.rawValue`）→ `today` / `d5`。
/// - `watchMove`：品种规范键 → 自选波动提醒幅度的倍数（0.5…2）。
///
/// 每一条都带「依据几次」（`n`，给「已学到的」那页看）和「最近一次依据的时刻」（`at`，
/// Unix 秒，两台设备各学各的时候谁新用谁、30 天没新依据就过期）。
///
/// 这份形状和服务端 `sync_validation.rs` 的 `learned_defaults` 一一对应，改一边另一边要跟。
struct LearnedDefaults: Codable, Equatable, Sendable {
  struct Choice: Codable, Equatable, Sendable {
    var v: String
    var n: Int
    var at: Double
  }

  struct Factor: Codable, Equatable, Sendable {
    var v: Double
    var n: Int
    var at: Double
  }

  var intervals: [String: Choice] = [:]
  var priceAxis: [String: Choice] = [:]
  var sectorWindow: [String: Choice] = [:]
  var watchMove: [String: Factor] = [:]

  static let empty = LearnedDefaults()

  var isEmpty: Bool { intervals.isEmpty && priceAxis.isEmpty && sectorWindow.isEmpty && watchMove.isEmpty }

  /// 按品种记的两张表各自最多留几只（按 `at` 留新的）。
  static let maxSymbols = 80
  /// 整份编码后的上限。服务端卡同一个数（`LEARNED_MAX_BYTES`）。
  static let maxBytes = 16_384
  /// 倍数的范围。服务端卡同一个区间。
  static let factorRange: ClosedRange<Double> = 0.5...2.0
  static let axisValues: Set<String> = [PriceMode.linear.rawValue, PriceMode.log.rawValue]
  static let sectorValues: Set<String> = [SectorWindow.today.rawValue, SectorWindow.d5.rawValue]

  init() {}

  private enum CodingKeys: String, CodingKey { case intervals, priceAxis, sectorWindow, watchMove }

  /// 宽容读：缺哪张表就当空的；某一条读不懂只丢那一条（`sanitized`），不连累别的。
  init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    func table<V: Decodable>(_ key: CodingKeys, _: V.Type) -> [String: V] {
      ((try? c.decodeIfPresent([String: Lossy<V>].self, forKey: key)) ?? nil)?.compactMapValues(\.value) ?? [:]
    }
    intervals = table(.intervals, Choice.self)
    priceAxis = table(.priceAxis, Choice.self)
    sectorWindow = table(.sectorWindow, Choice.self)
    watchMove = table(.watchMove, Factor.self)
    self = sanitized()
  }

  /// 空表不写出去，整份更小。
  func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    if !intervals.isEmpty { try c.encode(intervals, forKey: .intervals) }
    if !priceAxis.isEmpty { try c.encode(priceAxis, forKey: .priceAxis) }
    if !sectorWindow.isEmpty { try c.encode(sectorWindow, forKey: .sectorWindow) }
    if !watchMove.isEmpty { try c.encode(watchMove, forKey: .watchMove) }
  }

  // ---------------------------------------------------------------- 读

  func interval(for symbol: String) -> Interval? {
    intervals[InstrumentID.canonical(symbol)].flatMap { Interval(rawValue: $0.v) }
  }

  func priceMode(for category: HabitCategory) -> PriceMode? {
    priceAxis[category.rawValue].flatMap { PriceMode(rawValue: $0.v) }
  }

  func window(for market: SectorMarket) -> SectorWindow? {
    sectorWindow[market.rawValue].flatMap { SectorWindow(rawValue: $0.v) }
  }

  /// 没学到就是 1。
  func watchMoveFactor(for symbol: String) -> Double {
    watchMove[InstrumentID.canonical(symbol)]?.v ?? 1
  }

  // ---------------------------------------------------------------- 整理

  /// 值不合法的条目丢掉（周期认不得、轴不是线性 / 对数、倍数越界、数不是有限的）。
  func sanitized() -> LearnedDefaults {
    func ok(_ n: Int, _ at: Double) -> Bool { n >= 0 && at.isFinite && at >= 0 }
    func key(_ k: String) -> Bool { !k.isEmpty && k.utf8.count <= 128 }
    var out = LearnedDefaults()
    out.intervals = intervals.filter { key($0.key) && Interval(rawValue: $0.value.v) != nil && ok($0.value.n, $0.value.at) }
    out.priceAxis = priceAxis.filter {
      HabitCategory(rawValue: $0.key) != nil && Self.axisValues.contains($0.value.v) && ok($0.value.n, $0.value.at)
    }
    out.sectorWindow = sectorWindow.filter {
      SectorMarket(rawValue: $0.key) != nil && Self.sectorValues.contains($0.value.v) && ok($0.value.n, $0.value.at)
    }
    out.watchMove = watchMove.filter {
      key($0.key) && $0.value.v.isFinite && Self.factorRange.contains($0.value.v) && ok($0.value.n, $0.value.at)
    }
    return out
  }

  /// 30 天没有新依据的丢掉；按品种的两张表只留最新的 `maxSymbols` 只；
  /// 编码后还超 `maxBytes` 就从最旧的品种条目开始丢，直到放得下。
  func pruned(now: Double) -> LearnedDefaults {
    let cutoff = now - HabitLog.retention
    var out = sanitized()
    out.intervals = Self.newest(out.intervals.filter { $0.value.at >= cutoff }, keep: Self.maxSymbols, at: \.at)
    out.priceAxis = out.priceAxis.filter { $0.value.at >= cutoff }
    out.sectorWindow = out.sectorWindow.filter { $0.value.at >= cutoff }
    out.watchMove = Self.newest(out.watchMove.filter { $0.value.at >= cutoff }, keep: Self.maxSymbols, at: \.at)
    while out.encodedSize > Self.maxBytes {
      let oldestInterval = out.intervals.min { $0.value.at < $1.value.at }
      let oldestMove = out.watchMove.min { $0.value.at < $1.value.at }
      switch (oldestInterval, oldestMove) {
      case let (i?, m?): if i.value.at <= m.value.at { out.intervals[i.key] = nil } else { out.watchMove[m.key] = nil }
      case let (i?, nil): out.intervals[i.key] = nil
      case let (nil, m?): out.watchMove[m.key] = nil
      case (nil, nil): return out
      }
    }
    return out
  }

  var encodedSize: Int { (try? JSONEncoder().encode(self).count) ?? 0 }

  /// 本机推出来的（`local`，只含本机有依据的键）并到账号上同步来的那份（`synced`）上：
  /// 同一个键谁的 `at` 新用谁（一样新用本机的）；只在一边有的照留；最后整理一遍。
  static func merged(synced: LearnedDefaults, local: LearnedDefaults, now: Double) -> LearnedDefaults {
    func pick<V>(_ a: [String: V], _ b: [String: V], at: (V) -> Double) -> [String: V] {
      a.merging(b) { old, new in at(new) >= at(old) ? new : old }
    }
    var out = LearnedDefaults()
    out.intervals = pick(synced.intervals, local.intervals, at: \.at)
    out.priceAxis = pick(synced.priceAxis, local.priceAxis, at: \.at)
    out.sectorWindow = pick(synced.sectorWindow, local.sectorWindow, at: \.at)
    out.watchMove = pick(synced.watchMove, local.watchMove, at: \.at)
    return out.pruned(now: now)
  }

  private static func newest<V>(_ table: [String: V], keep: Int, at: (V) -> Double) -> [String: V] {
    guard table.count > keep else { return table }
    let kept = table.sorted { at($0.value) != at($1.value) ? at($0.value) > at($1.value) : $0.key < $1.key }.prefix(keep)
    return Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
  }
}

/// 读一条，读不懂就是 nil（不连累同一张表里的别的条目）。
private struct Lossy<V: Decodable>: Decodable {
  var value: V?
  init(from decoder: any Decoder) throws { value = try? V(from: decoder) }
}

/// 价格轴按哪一类记。类别来自品种事实分类（`SymbolClassifier`），合成用户看得懂的五类：
/// 大宗、盘前这类量少的并进「其它」。
enum HabitCategory: String, CaseIterable, Sendable {
  case crypto, equity, metal, index, other

  init(_ asset: SymbolClassification.Asset) {
    switch asset {
    case .crypto: self = .crypto
    case .equity: self = .equity
    case .preciousMetal: self = .metal
    case .index: self = .index
    case .commodity, .preMarket, .other: self = .other
    }
  }

  init(_ info: SymbolInfo) { self.init(SymbolClassifier.classify(info).asset) }

  var title: String {
    switch self {
    case .crypto: "加密"
    case .equity: "美股"
    case .metal: "贵金属"
    case .index: "指数"
    case .other: "其它"
    }
  }
}
