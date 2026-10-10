import Foundation

// 「盘口要点」半页与首页「异动 · 榜单」的接口模型（kanpan-api 要点引擎，PROJECT.md §79）。
//
// 接口只发稳定的枚举键（`w`、`t`、`wallState`、`combo`、`refs`、`cat`、`kind`），中文一律由
// `HighlightTerm`（terms.json 的 `highlights` 组）拼；价格是「每一枚币」的价，1000PEPE 这类要乘缩放。
// 单个元素解不出来只丢它自己（`Lossy`），不让一条新事件类型把整页打空。

/// `/v1/market/orderflow/highlights?base=` 的一份答复。
public struct HighlightsPage: Sendable, Equatable, Decodable {
  public var base: String
  public var generatedAtMs: Int64
  public var tracked: Bool
  /// 数据停了多久（毫秒）；`nil` 表示是新鲜的。
  public var staleMs: Int64?
  public var flow: Flow?
  public var range: HighlightRange?
  public var levels: [HighlightLevel]
  public var position: HighlightPosition?
  public var events: [HighlightEvent]

  public struct Flow: Sendable, Equatable, Decodable {
    public var rows: [FlowRow]
    public init(rows: [FlowRow]) { self.rows = rows }
    public init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      rows = (try? c.decode(Lossy<FlowRow>.self, forKey: .rows))?.items ?? []
    }
    enum CodingKeys: String, CodingKey { case rows }
  }

  public init(base: String, generatedAtMs: Int64, tracked: Bool, staleMs: Int64? = nil, flow: Flow? = nil,
              range: HighlightRange? = nil, levels: [HighlightLevel] = [], position: HighlightPosition? = nil,
              events: [HighlightEvent] = []) {
    self.base = base; self.generatedAtMs = generatedAtMs; self.tracked = tracked; self.staleMs = staleMs
    self.flow = flow; self.range = range; self.levels = levels; self.position = position; self.events = events
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    base = try c.decode(String.self, forKey: .base)
    generatedAtMs = try c.decode(Int64.self, forKey: .generatedAtMs)
    tracked = (try? c.decode(Bool.self, forKey: .tracked)) ?? false
    staleMs = try? c.decodeIfPresent(Int64.self, forKey: .staleMs)
    flow = try? c.decodeIfPresent(Flow.self, forKey: .flow)
    range = try? c.decodeIfPresent(HighlightRange.self, forKey: .range)
    levels = (try? c.decode(Lossy<HighlightLevel>.self, forKey: .levels))?.items ?? []
    position = try? c.decodeIfPresent(HighlightPosition.self, forKey: .position)
    events = (try? c.decode(Lossy<HighlightEvent>.self, forKey: .events))?.items ?? []
  }

  enum CodingKeys: String, CodingKey {
    case base, generatedAtMs, tracked, staleMs, flow, range, levels, position, events
  }

  /// 现价上方的价位（距离从近到远），最多 `limit` 条。
  public func above(limit: Int = 2) -> [HighlightLevel] {
    Array(levels.filter { $0.side == .ask }.sorted { abs($0.distPct) < abs($1.distPct) }.prefix(limit))
  }

  /// 现价下方的价位（距离从近到远），最多 `limit` 条。
  public func below(limit: Int = 2) -> [HighlightLevel] {
    Array(levels.filter { $0.side == .bid }.sorted { abs($0.distPct) < abs($1.distPct) }.prefix(limit))
  }

  /// 离现价最近的那一条（入口条写它）。
  public var nearestLevel: HighlightLevel? {
    levels.min { abs($0.distPct) < abs($1.distPct) }
  }

  /// 有没有可写的东西（价位、区间、事件、三格任一）。只有流向的算「平静」。
  public var hasPoints: Bool {
    !levels.isEmpty || range != nil || !events.isEmpty || (position?.show ?? false)
  }
}

/// 流向表的一行。
public struct FlowRow: Sendable, Equatable, Decodable, Identifiable {
  public enum Window: String, Sendable, Equatable, Decodable { case m15 = "15m", h1 = "1h", h4 = "4h", range, h24 = "24h" }
  public var w: Window
  /// 净主动（合约 + 现货主动买 − 主动卖，美元）；没连续盖住整窗时为 `nil`。
  public var netUsd: Double?
  public var pxPct: Double?
  public var oiPct: Double?
  public var diverge: Bool
  /// 只有 `range` 行有：区间从哪一刻起算。
  public var sinceMs: Int64?
  public var id: String { w.rawValue }

  public init(w: Window, netUsd: Double?, pxPct: Double?, oiPct: Double?, diverge: Bool = false, sinceMs: Int64? = nil) {
    self.w = w; self.netUsd = netUsd; self.pxPct = pxPct; self.oiPct = oiPct; self.diverge = diverge; self.sinceMs = sinceMs
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    w = try c.decode(Window.self, forKey: .w)
    netUsd = try? c.decodeIfPresent(Double.self, forKey: .netUsd)
    pxPct = try? c.decodeIfPresent(Double.self, forKey: .pxPct)
    oiPct = try? c.decodeIfPresent(Double.self, forKey: .oiPct)
    diverge = (try? c.decode(Bool.self, forKey: .diverge)) ?? false
    sinceMs = try? c.decodeIfPresent(Int64.self, forKey: .sinceMs)
  }

  enum CodingKeys: String, CodingKey { case w, netUsd, pxPct, oiPct, diverge, sinceMs }
}

/// 成立的区间（箱体）。
public struct HighlightRange: Sendable, Equatable, Decodable {
  public var low: Double
  public var high: Double
  public var sinceMs: Int64
  public var lowFillUsd: Double
  public var lowTests: Int
  public var highFillUsd: Double
  public var highTests: Int

  public init(low: Double, high: Double, sinceMs: Int64, lowFillUsd: Double, lowTests: Int, highFillUsd: Double, highTests: Int) {
    self.low = low; self.high = high; self.sinceMs = sinceMs
    self.lowFillUsd = lowFillUsd; self.lowTests = lowTests; self.highFillUsd = highFillUsd; self.highTests = highTests
  }
}

public enum HighlightSide: String, Sendable, Equatable, Decodable { case bid, ask }

/// 关键价位（账本格）。
public struct HighlightLevel: Sendable, Equatable, Decodable, Identifiable {
  public enum WallState: String, Sendable, Equatable, Decodable { case live, reducing, broken }
  public var id: String
  public var low: Double
  public var high: Double
  public var side: HighlightSide
  /// 距现价（%）：上方为正、下方为负。
  public var distPct: Double
  public var wallUsd: Double
  public var wallHeldMs: Int64
  public var wallState: WallState?
  public var fillBuyUsd: Double
  public var fillSellUsd: Double
  public var liqUsd: Double
  public var tests: Int
  /// 首次 / 最近一次触及。
  public var touchMs: [Int64?]
  public var refs: [String]

  public var fillUsd: Double { fillBuyUsd + fillSellUsd }

  public init(id: String, low: Double, high: Double, side: HighlightSide, distPct: Double, wallUsd: Double = 0,
              wallHeldMs: Int64 = 0, wallState: WallState? = nil, fillBuyUsd: Double = 0, fillSellUsd: Double = 0,
              liqUsd: Double = 0, tests: Int = 0, touchMs: [Int64?] = [nil, nil], refs: [String] = []) {
    self.id = id; self.low = low; self.high = high; self.side = side; self.distPct = distPct
    self.wallUsd = wallUsd; self.wallHeldMs = wallHeldMs; self.wallState = wallState
    self.fillBuyUsd = fillBuyUsd; self.fillSellUsd = fillSellUsd; self.liqUsd = liqUsd
    self.tests = tests; self.touchMs = touchMs; self.refs = refs
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    low = try c.decode(Double.self, forKey: .low)
    high = try c.decode(Double.self, forKey: .high)
    side = try c.decode(HighlightSide.self, forKey: .side)
    distPct = (try? c.decode(Double.self, forKey: .distPct)) ?? 0
    wallUsd = (try? c.decode(Double.self, forKey: .wallUsd)) ?? 0
    wallHeldMs = (try? c.decode(Int64.self, forKey: .wallHeldMs)) ?? 0
    wallState = try? c.decodeIfPresent(WallState.self, forKey: .wallState)
    fillBuyUsd = (try? c.decode(Double.self, forKey: .fillBuyUsd)) ?? 0
    fillSellUsd = (try? c.decode(Double.self, forKey: .fillSellUsd)) ?? 0
    liqUsd = (try? c.decode(Double.self, forKey: .liqUsd)) ?? 0
    tests = (try? c.decode(Int.self, forKey: .tests)) ?? 0
    touchMs = (try? c.decode([Int64?].self, forKey: .touchMs)) ?? []
    refs = (try? c.decode([String].self, forKey: .refs)) ?? []
  }

  enum CodingKeys: String, CodingKey {
    case id, low, high, side, distPct, wallUsd, wallHeldMs, wallState, fillBuyUsd, fillSellUsd, liqUsd, tests, touchMs, refs
  }
}

/// 持仓 · 费率 · 现货溢价三格。
public struct HighlightPosition: Sendable, Equatable, Decodable {
  public enum Combo: String, Sendable, Equatable, Decodable { case oiUpPxUp, oiDownPxUp, oiUpPxDown, oiDownPxDown }
  public struct OI: Sendable, Equatable, Decodable {
    public var pct1h: Double?
    public var combo: Combo?
    public var pctile: Int?
    public init(pct1h: Double?, combo: Combo?, pctile: Int?) { self.pct1h = pct1h; self.combo = combo; self.pctile = pctile }
    public init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      pct1h = try? c.decodeIfPresent(Double.self, forKey: .pct1h)
      combo = try? c.decodeIfPresent(Combo.self, forKey: .combo)
      pctile = try? c.decodeIfPresent(Int.self, forKey: .pctile)
    }
    enum CodingKeys: String, CodingKey { case pct1h, combo, pctile }
  }
  public struct Funding: Sendable, Equatable, Decodable {
    /// 小数（0.0001 = 0.01%）。
    public var rate: Double?
    public var pctile: Int?
    public init(rate: Double?, pctile: Int?) { self.rate = rate; self.pctile = pctile }
    public init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      rate = try? c.decodeIfPresent(Double.self, forKey: .rate)
      pctile = try? c.decodeIfPresent(Int.self, forKey: .pctile)
    }
    enum CodingKeys: String, CodingKey { case rate, pctile }
  }
  public struct Premium: Sendable, Equatable, Decodable {
    /// 百分数（0.08 = 0.08%）。
    public var pct: Double?
    public var pctile: Int?
    public init(pct: Double?, pctile: Int?) { self.pct = pct; self.pctile = pctile }
    public init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      pct = try? c.decodeIfPresent(Double.self, forKey: .pct)
      pctile = try? c.decodeIfPresent(Int.self, forKey: .pctile)
    }
    enum CodingKeys: String, CodingKey { case pct, pctile }
  }
  public var show: Bool
  public var oi: OI?
  public var funding: Funding?
  public var spotPremium: Premium?

  public init(show: Bool, oi: OI?, funding: Funding?, spotPremium: Premium?) {
    self.show = show; self.oi = oi; self.funding = funding; self.spotPremium = spotPremium
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    show = (try? c.decode(Bool.self, forKey: .show)) ?? false
    oi = try? c.decodeIfPresent(OI.self, forKey: .oi)
    funding = try? c.decodeIfPresent(Funding.self, forKey: .funding)
    spotPremium = try? c.decodeIfPresent(Premium.self, forKey: .spotPremium)
  }
  enum CodingKeys: String, CodingKey { case show, oi, funding, spotPremium }
}

/// 近 4 小时的一条事件。
public struct HighlightEvent: Sendable, Equatable, Decodable, Identifiable {
  public enum Kind: String, Sendable, Equatable, Decodable {
    case wallEaten, wallCancel, flowBurst, liqWave, oiJump, levelBroken
  }
  public var id: String
  public var t: Kind
  public var atMs: Int64?
  public var fromMs: Int64?
  public var toMs: Int64?
  public var price: Double?
  public var low: Double?
  public var high: Double?
  public var usd: Double?
  public var netUsd: Double?
  /// buy / sell（墙）、long / short（爆仓）、bid / ask（已破）。
  public var side: String?
  public var distPct: Double?
  public var pxPct: Double?
  public var pct: Double?

  /// 这条事件落在哪一刻（时段取起点）。
  public var startMs: Int64? { atMs ?? fromMs }

  public init(id: String, t: Kind, atMs: Int64? = nil, fromMs: Int64? = nil, toMs: Int64? = nil, price: Double? = nil,
              low: Double? = nil, high: Double? = nil, usd: Double? = nil, netUsd: Double? = nil, side: String? = nil,
              distPct: Double? = nil, pxPct: Double? = nil, pct: Double? = nil) {
    self.id = id; self.t = t; self.atMs = atMs; self.fromMs = fromMs; self.toMs = toMs; self.price = price
    self.low = low; self.high = high; self.usd = usd; self.netUsd = netUsd; self.side = side
    self.distPct = distPct; self.pxPct = pxPct; self.pct = pct
  }
}

// MARK: - 首页

/// `/v1/market/orderflow/highlights/board?bases=` 的一份答复：异动一列。
public struct HighlightsBoard: Sendable, Equatable, Decodable {
  public var generatedAtMs: Int64
  public var rows: [Row]

  public enum Category: String, Sendable, Equatable, Decodable { case book, oi, funding }

  /// 每只取它此刻权重最高的那一条要点。
  public enum Top: Sendable, Equatable {
    case level(HighlightLevel)
    case event(HighlightEvent)
    case position(HighlightPosition)
  }

  public struct Row: Sendable, Equatable, Decodable, Identifiable {
    public var base: String
    public var favorite: Bool
    /// 这只此刻一共有几条要点（行尾写「+N」= count − 1）。
    public var count: Int
    public var cat: Category
    /// 强度 1…3。
    public var tier: Int
    public var top: Top
    public var price: Double?
    public var changePct: Double?
    public var atMs: Int64
    public var id: String { base }

    public init(base: String, favorite: Bool, count: Int, cat: Category, tier: Int, top: Top, price: Double?, changePct: Double?, atMs: Int64) {
      self.base = base; self.favorite = favorite; self.count = count; self.cat = cat; self.tier = tier
      self.top = top; self.price = price; self.changePct = changePct; self.atMs = atMs
    }

    public init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      base = try c.decode(String.self, forKey: .base)
      favorite = (try? c.decode(Bool.self, forKey: .favorite)) ?? false
      count = (try? c.decode(Int.self, forKey: .count)) ?? 1
      cat = try c.decode(Category.self, forKey: .cat)
      tier = min(3, max(1, (try? c.decode(Int.self, forKey: .tier)) ?? 1))
      price = try? c.decodeIfPresent(Double.self, forKey: .price)
      changePct = try? c.decodeIfPresent(Double.self, forKey: .changePct)
      atMs = (try? c.decode(Int64.self, forKey: .atMs)) ?? 0
      let kind = try c.nestedContainer(keyedBy: KindKey.self, forKey: .top).decode(String.self, forKey: .kind)
      switch kind {
      case "level": top = .level(try c.decode(HighlightLevel.self, forKey: .top))
      case "event": top = .event(try c.decode(HighlightEvent.self, forKey: .top))
      case "position": top = .position(try c.decode(HighlightPosition.self, forKey: .top))
      default: throw DecodingError.dataCorruptedError(forKey: .top, in: c, debugDescription: "unknown kind \(kind)")
      }
    }

    enum CodingKeys: String, CodingKey { case base, favorite, count, cat, tier, top, price, changePct, atMs }
    enum KindKey: String, CodingKey { case kind }
  }

  public init(generatedAtMs: Int64, rows: [Row]) { self.generatedAtMs = generatedAtMs; self.rows = rows }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    generatedAtMs = try c.decode(Int64.self, forKey: .generatedAtMs)
    rows = (try? c.decode(Lossy<Row>.self, forKey: .rows))?.items ?? []
  }
  enum CodingKeys: String, CodingKey { case generatedAtMs, rows }
}

/// `/v1/market/board?kind=&window=` 的一份答复：榜单一张卡。
public struct MarketBoard: Sendable, Equatable, Decodable {
  public enum Kind: String, Sendable, CaseIterable { case oi, gainers, losers }
  public enum Window: String, Sendable, CaseIterable { case h1 = "1h", h4 = "4h", h24 = "24h" }
  public struct Row: Sendable, Equatable, Decodable, Identifiable {
    public var base: String
    public var changePct: Double
    public var oiUsd: Double?
    public var price: Double?
    public var id: String { base }
    public init(base: String, changePct: Double, oiUsd: Double?, price: Double?) {
      self.base = base; self.changePct = changePct; self.oiUsd = oiUsd; self.price = price
    }
  }
  public var generatedAtMs: Int64
  public var rows: [Row]

  public init(generatedAtMs: Int64, rows: [Row]) { self.generatedAtMs = generatedAtMs; self.rows = rows }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    generatedAtMs = try c.decode(Int64.self, forKey: .generatedAtMs)
    rows = (try? c.decode(Lossy<Row>.self, forKey: .rows))?.items ?? []
  }
  enum CodingKeys: String, CodingKey { case generatedAtMs, rows }
}

/// 解不出来的元素丢掉、其余照收。
struct Lossy<T: Decodable>: Decodable {
  var items: [T]
  init(from decoder: Decoder) throws {
    var c = try decoder.unkeyedContainer()
    var out: [T] = []
    while !c.isAtEnd {
      if let v = try? c.decode(T.self) { out.append(v) } else if (try? c.decode(Skip.self)) == nil { break }
    }
    items = out
  }
  /// 什么都收（不碰解码器就算解成功，游标照样前进），防坏元素把循环卡死。
  private struct Skip: Decodable { init(from decoder: Decoder) throws {} }
}
