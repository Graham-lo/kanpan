import Foundation
import KanpanCore

// 交易复盘（`kind:"trade"`）在客户端这一侧的形状。线上契约见 `docs/交易复盘-协议-2026-09-27.md` §3–4：
// 一条记录 = 一个回合（`TradeRound`，手机拼的）+ 服务端算好回写的结果（`TradeResult`）+ 人写的一句备注。
//
// 数字一律十进制：线上是字符串，这里是 `Decimal`（`TradeDecimal.parse`），和回合本身同一口径。

/// 「当时怎么想」那一句。
public struct TradeNote: Codable, Sendable, Hashable {
  public var text: String
  public var updatedAt: Int64
  public init(text: String, updatedAt: Int64) { self.text = text; self.updatedAt = updatedAt }
}

/// 持仓期间的最大浮盈 / 最大浮亏（协议 §4.1）。
public struct TradeExcursion: Codable, Sendable, Hashable {
  public var maxFavorable: Decimal
  public var maxFavorablePct: Decimal
  public var maxFavorableAt: Int64?
  public var maxAdverse: Decimal
  public var maxAdversePct: Decimal
  public var maxAdverseAt: Int64?
  /// 净盈亏 ÷ |最大浮亏|；最大浮亏是 0 时为 nil。
  public var rewardRisk: Decimal?

  public init(maxFavorable: Decimal, maxFavorablePct: Decimal, maxFavorableAt: Int64?,
              maxAdverse: Decimal, maxAdversePct: Decimal, maxAdverseAt: Int64?, rewardRisk: Decimal?) {
    self.maxFavorable = maxFavorable; self.maxFavorablePct = maxFavorablePct; self.maxFavorableAt = maxFavorableAt
    self.maxAdverse = maxAdverse; self.maxAdversePct = maxAdversePct; self.maxAdverseAt = maxAdverseAt
    self.rewardRisk = rewardRisk
  }

  private enum CodingKeys: String, CodingKey {
    case maxFavorable, maxFavorablePct, maxFavorableAt, maxAdverse, maxAdversePct, maxAdverseAt, rewardRisk
  }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    maxFavorable = try TradeWire.decimal(c, .maxFavorable)
    maxFavorablePct = try TradeWire.decimal(c, .maxFavorablePct)
    maxFavorableAt = try c.decodeIfPresent(Int64.self, forKey: .maxFavorableAt)
    maxAdverse = try TradeWire.decimal(c, .maxAdverse)
    maxAdversePct = try TradeWire.decimal(c, .maxAdversePct)
    maxAdverseAt = try c.decodeIfPresent(Int64.self, forKey: .maxAdverseAt)
    rewardRisk = try TradeWire.optionalDecimal(c, .rewardRisk)
  }
  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(TradeDecimal.format(maxFavorable), forKey: .maxFavorable)
    try c.encode(TradeDecimal.format(maxFavorablePct), forKey: .maxFavorablePct)
    try c.encode(maxFavorableAt, forKey: .maxFavorableAt)
    try c.encode(TradeDecimal.format(maxAdverse), forKey: .maxAdverse)
    try c.encode(TradeDecimal.format(maxAdversePct), forKey: .maxAdversePct)
    try c.encode(maxAdverseAt, forKey: .maxAdverseAt)
    try c.encode(rewardRisk.map(TradeDecimal.format), forKey: .rewardRisk)
  }
}

/// 平仓后某个时刻的价（协议 §4.2）。
public struct TradeAfterPoint: Codable, Sendable, Hashable {
  public var at: Int64
  public var price: Decimal
  /// 比值（`0.021` = 2.1%），只看价格、不按方向翻号。
  public var changePct: Decimal

  public init(at: Int64, price: Decimal, changePct: Decimal) { self.at = at; self.price = price; self.changePct = changePct }

  private enum CodingKeys: String, CodingKey { case at, price, changePct }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    at = try c.decode(Int64.self, forKey: .at)
    price = try TradeWire.decimal(c, .price)
    changePct = try TradeWire.decimal(c, .changePct)
  }
  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(at, forKey: .at)
    try c.encode(TradeDecimal.format(price), forKey: .price)
    try c.encode(TradeDecimal.format(changePct), forKey: .changePct)
  }
}

/// 自动截图的周期与窗口（协议 §4.3）。
public struct TradeChartSpec: Codable, Sendable, Hashable {
  public var interval: String
  public var start: Int64
  public var end: Int64
  public init(interval: String, start: Int64, end: Int64) { self.interval = interval; self.start = start; self.end = end }
}

/// 一格结果现在是什么状态：有数、还没到点、拿不到。
public enum TradeCell<Value: Sendable & Hashable>: Sendable, Hashable {
  case value(Value)
  /// 还没到点（或服务端还没算到这一格）。界面写「—」。
  case pending
  /// 服务端说拿不到（`klines_missing` / `market_region_blocked`）。
  case unavailable(String)

  public var value: Value? { if case .value(let v) = self { v } else { nil } }
}

/// 服务端算、回写到 `record.result` 的那一份（协议 §4）。只有平仓的回合才有。
public struct TradeResult: Codable, Sendable, Hashable {
  public var version: Int
  public var computedAt: Int64
  public var excursion: TradeExcursion?
  /// `h1` / `h4` / `h24` → 那一格；还没到点的不在字典里。
  public var after: [String: TradeAfterPoint]
  public var chart: TradeChartSpec?
  /// 拿不到的那几部分 → 原因码。
  public var unavailable: [String: String]

  public static let afterKeys = ["h1", "h4", "h24"]

  public init(version: Int = 1, computedAt: Int64, excursion: TradeExcursion?, after: [String: TradeAfterPoint],
              chart: TradeChartSpec?, unavailable: [String: String] = [:]) {
    self.version = version; self.computedAt = computedAt; self.excursion = excursion; self.after = after
    self.chart = chart; self.unavailable = unavailable
  }

  private enum CodingKeys: String, CodingKey { case version, computedAt, excursion, after, chart, unavailable }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
    computedAt = try c.decodeIfPresent(Int64.self, forKey: .computedAt) ?? 0
    excursion = try c.decodeIfPresent(TradeExcursion.self, forKey: .excursion)
    // 线上是 `{"h1": {…}, "h4": null, "h24": null}`：null 的格子不进字典。
    let cells = try c.decodeIfPresent([String: TradeAfterPoint?].self, forKey: .after) ?? [:]
    after = cells.compactMapValues { $0 }
    chart = try c.decodeIfPresent(TradeChartSpec.self, forKey: .chart)
    unavailable = try c.decodeIfPresent([String: String].self, forKey: .unavailable) ?? [:]
  }
  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(version, forKey: .version)
    try c.encode(computedAt, forKey: .computedAt)
    try c.encode(excursion, forKey: .excursion)
    var cells: [String: TradeAfterPoint?] = [:]
    for key in Self.afterKeys { cells[key] = .some(after[key]) }
    try c.encode(cells, forKey: .after)
    try c.encode(chart, forKey: .chart)
    try c.encode(unavailable, forKey: .unavailable)
  }

  /// 持仓期间那一块。
  public var excursionCell: TradeCell<TradeExcursion> {
    if let excursion { return .value(excursion) }
    if let code = unavailable["excursion"] { return .unavailable(code) }
    return .pending
  }

  /// 离开后某一格（`h1` / `h4` / `h24`）。
  public func afterCell(_ key: String) -> TradeCell<TradeAfterPoint> {
    if let point = after[key] { return .value(point) }
    if let code = unavailable[key] { return .unavailable(code) }
    return .pending
  }
}

/// 一条交易复盘记录（`kind:"trade"`），服务端回来的原样。
public struct TradeRecord: Codable, Sendable, Hashable, Identifiable {
  public var kind = "trade"
  public var id: String
  public var revision: Int
  public var submitted: Int64
  public var updated: Int64
  public var voided: Bool
  public var round: TradeRound
  public var result: TradeResult?
  public var note: TradeNote?

  public init(id: String, revision: Int, submitted: Int64, updated: Int64, voided: Bool = false,
              round: TradeRound, result: TradeResult? = nil, note: TradeNote? = nil) {
    self.id = id; self.revision = revision; self.submitted = submitted; self.updated = updated
    self.voided = voided; self.round = round; self.result = result; self.note = note
  }

  private enum CodingKeys: String, CodingKey { case kind, id, revision, submitted, updated, voided, round, result, note }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "trade"
    id = try c.decode(String.self, forKey: .id).lowercased()
    revision = try c.decode(Int.self, forKey: .revision)
    submitted = try c.decodeIfPresent(Int64.self, forKey: .submitted) ?? 0
    updated = try c.decodeIfPresent(Int64.self, forKey: .updated) ?? 0
    voided = try c.decodeIfPresent(Bool.self, forKey: .voided) ?? false
    round = try c.decode(TradeRound.self, forKey: .round)
    result = try c.decodeIfPresent(TradeResult.self, forKey: .result)
    note = try c.decodeIfPresent(TradeNote.self, forKey: .note)
  }
  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(kind, forKey: .kind); try c.encode(id, forKey: .id); try c.encode(revision, forKey: .revision)
    try c.encode(submitted, forKey: .submitted); try c.encode(updated, forKey: .updated)
    try c.encode(voided, forKey: .voided); try c.encode(round, forKey: .round)
    try c.encode(result, forKey: .result); try c.encode(note, forKey: .note)
  }
}

/// 十进制字符串的读法：协议写的是字符串，老数据或测试夹具偶尔是数字，两样都认。
enum TradeWire {
  static func decimal<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) throws -> Decimal {
    guard let value = try optionalDecimal(c, key) else {
      throw DecodingError.valueNotFound(Decimal.self, .init(codingPath: c.codingPath + [key], debugDescription: "缺数"))
    }
    return value
  }
  static func optionalDecimal<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) throws -> Decimal? {
    guard c.contains(key), try !c.decodeNil(forKey: key) else { return nil }
    if let text = try? c.decode(String.self, forKey: key) {
      guard let value = TradeDecimal.parse(text) else {
        throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "不是十进制数：\(text)")
      }
      return value
    }
    // 数字形态直接按 `Decimal` 解：JSONDecoder 对 `Decimal` 是照数字原文逐位解析的，
    // 先过一道 `Double` 再转会把 `0.1` 读成 `0.1000000000000000512`（审查 R18）。
    return try c.decode(Decimal.self, forKey: key)
  }
}

// MARK: - 上传怎么分批

/// 回合上传的纯算术：哪些要传、怎么切批（协议 §3.1：一批最多 100 个）。
public enum TradeUploadPlan {
  public static let batchSize = 100

  /// 要传的：本地这一版比服务端手上那一版**新**（`updatedAt` 更大）、也没被服务端拒过这一版
  /// （或更新的一版）的。
  ///
  /// 只认「更新」不认「不同」（审查 R11）：`uploaded` 会被拉列表 / 并档抬到服务端那份的
  /// `updatedAt`，另一台设备传上去的版本比本机的新时，按「不同」判本机这份旧回合就永远是
  /// 待传，每次进复盘都重传一遍、服务端又给回那份新的、再判不同……回合的 `updatedAt`
  /// 是它所有成交 / 资金费事件时间的最大值，本地更小就是本地更旧，传上去没有意义。
  /// 按开仓时间排，老的先传——列表按平仓时间倒序，先传老的不会让界面上跳来跳去。
  public static func pending(_ rounds: [TradeRound], uploaded: [String: Int64],
                             rejected: [String: Int64] = [:]) -> [TradeRound] {
    rounds.filter { round in
      (uploaded[round.id].map { round.updatedAt > $0 } ?? true)
        && (rejected[round.id].map { round.updatedAt > $0 } ?? true)
    }
      .sorted { ($0.openedAt, $0.id) < ($1.openedAt, $1.id) }
  }

  public static func batches(_ rounds: [TradeRound], size: Int = batchSize) -> [[TradeRound]] {
    stride(from: 0, to: rounds.count, by: max(1, size)).map { Array(rounds[$0..<min(rounds.count, $0 + max(1, size))]) }
  }

  /// 一批的指纹：同一批（同样的回合、同样的版本）重发要带同一个幂等键。
  public static func fingerprint(_ batch: [TradeRound]) -> String {
    batch.map { "\($0.id)@\($0.updatedAt)" }.joined(separator: ",")
  }
}

// MARK: - 观点 ↔ 交易

/// 「对应的观点」「对应的交易」：同一只品种、时间段有交叠。
///
/// 观点的时间段是「记下那一刻 → 到期」（它在那段时间里对这只品种有一个看法）；
/// 交易的时间段是「开仓 → 平仓」（持仓中的到现在）。品种只比代号（`BTCUSDT`）：
/// 在现货图上记的看法和在合约上下的单说的是同一只。作废的观点不算。
public enum TradeViewMatch {
  public static func viewSpan(_ record: ReviewRecord) -> ClosedRange<Int64> {
    let start = record.draft.created
    return start...max(start, record.draft.rule.expires)
  }

  public static func tradeSpan(_ round: TradeRound, now: Int64) -> ClosedRange<Int64> {
    let end = round.closedAt ?? now
    return round.openedAt...max(round.openedAt, end)
  }

  public static func sameSymbol(_ round: TradeRound, _ record: ReviewRecord) -> Bool {
    round.symbol.uppercased() == record.draft.range.symbol.uppercased()
  }

  public static func views(for round: TradeRound, in records: [ReviewRecord], now: Int64) -> [ReviewRecord] {
    let span = tradeSpan(round, now: now)
    var seen = Set<UUID>()
    return records.filter { record in
      !record.voided && sameSymbol(round, record) && viewSpan(record).overlaps(span) && seen.insert(record.id).inserted
    }
    .sorted { $0.draft.created < $1.draft.created }
  }

  public static func rounds(for record: ReviewRecord, in rounds: [TradeRound], now: Int64) -> [TradeRound] {
    guard !record.voided else { return [] }
    let span = viewSpan(record)
    return rounds.filter { sameSymbol($0, record) && tradeSpan($0, now: now).overlaps(span) }
      .sorted { $0.openedAt < $1.openedAt }
  }
}
