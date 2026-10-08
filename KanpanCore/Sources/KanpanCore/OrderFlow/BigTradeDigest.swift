import Foundation

// 大单与爆仓 · 弹层的摘要算法（纯函数，弹层的 BigTradeSummary 拿结果画）。口径照网页版 orderflow/summary.ts 与
// orderflow/liquidation.ts，只是手机上的「价位」是现价上下五档的竖梯（近 2 小时），不是买卖各取前三。

public enum BigTradeDigest {
  public static let hourMs: Int64 = 3_600_000
  public static let dayMs: Int64 = 86_400_000
  private static let tz8Ms: Int64 = 8 * 3_600_000

  /// 北京时间当天 0 点（毫秒）。
  public static func dayStart8(_ now: Int64) -> Int64 {
    let shifted = now + tz8Ms
    let q = shifted / dayMs
    return (shifted < 0 && shifted % dayMs != 0 ? q - 1 : q) * dayMs - tz8Ms
  }

  public struct Windows: Sendable, Equatable {
    public var bar: BigTradeSum
    public var hour: BigTradeSum
    public var today: BigTradeSum
  }

  /// 三个窗口：本根（`barT0`..`barT1`）、近 1 小时（滚动）、今日（北京时间 0 点起）。
  public static func windows(_ flow: BigTradeFlow, barT0: Int64, barT1: Int64, nowMs now: Int64) -> Windows {
    Windows(bar: flow.sum(barT0, barT1, nowMs: now),
            hour: flow.sum(now - hourMs, now + 1, nowMs: now),
            today: flow.sum(dayStart8(now), now + 1, nowMs: now))
  }

  /// 价位梯的一行：这一档（步长桶的下沿）近 2 小时的大买 / 大卖。
  public struct Level: Sendable, Equatable {
    public var price: Double
    public var buyUsd: Double
    public var sellUsd: Double
    public init(price: Double, buyUsd: Double, sellUsd: Double) {
      self.price = price; self.buyUsd = buyUsd; self.sellUsd = sellUsd
    }
  }

  /// 价位梯窗口（近 2 小时，和逐笔价位留的一样长）。
  public static let ladderWindowMs: Int64 = 2 * 3_600_000

  /// 现价上下 `levels` 档（共 2 × levels + 1 行，价从高到低）。每分钟取哪份同 `BigTradeFlow.sum`：
  /// 本机整分钟都在记的用逐笔成交的真实价；否则服务端有这分钟的行，就把它的大买 / 大卖整份记在那分钟
  /// 1 分钟 K 线的典型价 (高 + 低 + 收) / 3 上（`typical` 给；取不到就不算）；服务端在跟却没有行 = 没成交；
  /// 再不然用本机攒到的那一部分。`step` 是订单流的步长。
  public static func ladder(_ flow: BigTradeFlow, step: Double, price: Double, levels: Int = 5,
                            nowMs now: Int64, typical: ((Int64) -> Double?)? = nil) -> [Level] {
    guard step > 0, step.isFinite, price > 0, price.isFinite, levels >= 0 else { return [] }
    let center = (price / step + 1e-9).rounded(.down)
    var rows: [Double: (buy: Double, sell: Double)] = [:]
    for k in -levels...levels { rows[center + Double(k)] = (0, 0) }
    func add(_ p: Double, _ usd: Double, _ buy: Bool) {
      guard usd > 0, p > 0 else { return }
      let idx = (p / step + 1e-9).rounded(.down)
      guard var r = rows[idx] else { return }
      if buy { r.buy += usd } else { r.sell += usd }
      rows[idx] = r
    }
    let m = BigTradeFlow.minuteMs
    let cur = BigTradeFlow.floorMinute(now), from = cur - ladderWindowMs + m
    var byMinute: [Int64: [BigTradePrint]] = [:]
    for p in flow.prints.reversed() {
      if p.timeMs < from { break }
      byMinute[BigTradeFlow.floorMinute(p.timeMs), default: []].append(p)
    }
    let firstCover = flow.cover.first?.lowerBound
    var t = from
    while t <= cur {
      let live = byMinute[t]
      if let firstCover, t >= firstCover, flow.covered(t, t + m, nowMs: now) {
        live?.forEach { add($0.price, $0.usd, $0.buy) }
      } else if let row = flow.serverRows[t] {
        if let tp = typical?(t), tp > 0 { add(tp, row.buy, true); add(tp, row.sell, false) }
      } else if flow.tracked == true, let range = flow.serverRange, range.contains(t) {
        // 服务端在跟、这分钟没有行：没有大单。
      } else {
        live?.forEach { add($0.price, $0.usd, $0.buy) }
      }
      t += m
    }
    return (-levels...levels).reversed().map { k in
      let idx = center + Double(k)
      let r = rows[idx] ?? (0, 0)
      return Level(price: idx * step, buyUsd: r.buy, sellUsd: r.sell)
    }
  }

  /// 最近的挂单墙：现价上方最近的卖墙、下方最近的买墙（只看还挂着的；同一价位桶几家合计）。
  public struct Wall: Sendable, Equatable {
    public var price: Double
    public var usd: Double
    public var bucket: Int64
  }

  public static func nearestWalls(_ orders: [BigOrder], mid: Double) -> (ask: Wall?, bid: Wall?) {
    var ask: [Int64: Wall] = [:], bid: [Int64: Wall] = [:]
    for o in orders where o.status == .live {
      let isAsk = o.side == .ask
      if isAsk ? o.price < mid : o.price > mid { continue }
      if isAsk {
        if var w = ask[o.bucket] { w.usd += o.notional; w.price = min(w.price, o.price); ask[o.bucket] = w }
        else { ask[o.bucket] = Wall(price: o.price, usd: o.notional, bucket: o.bucket) }
      } else {
        if var w = bid[o.bucket] { w.usd += o.notional; w.price = max(w.price, o.price); bid[o.bucket] = w }
        else { bid[o.bucket] = Wall(price: o.price, usd: o.notional, bucket: o.bucket) }
      }
    }
    return (ask.values.min { $0.price < $1.price }, bid.values.max { $0.price < $1.price })
  }
}

// MARK: - 爆仓

/// 服务端 /liq 的一行：一分钟里各家（有强平推送的那几家）的强平合计。多单被平用跌色、空单被平用涨色。
public struct LiquidationRow: Sendable, Equatable {
  /// 服务端「哪家」列的编号（0 / 1 / 2）。显示名不在 Core：拿 `key` 去 KanpanNetwork 的交易所注册表查。
  public enum Exchange: Int, Sendable, CaseIterable {
    case binance = 0, okx = 1, bybit = 2
    /// 交易所代号（与 `OrderFlowVenue.exchange` 同一套）。
    public var key: String {
      switch self {
      case .binance: "binance"
      case .okx: "okx"
      case .bybit: "bybit"
      }
    }
  }
  public var minuteMs: Int64
  /// 多头被平 / 空头被平（美元）。
  public var longUsd: Double
  public var shortUsd: Double
  public var count: Int
  /// 这一分钟最大的一笔。
  public var maxUsd: Double
  public var maxPrice: Double
  /// 最大一笔是多头被平。
  public var maxIsLong: Bool
  public var maxExchange: Exchange
  public init(minuteMs: Int64, longUsd: Double, shortUsd: Double, count: Int, maxUsd: Double = 0,
              maxPrice: Double = 0, maxIsLong: Bool = true, maxExchange: Exchange = .binance) {
    self.minuteMs = minuteMs; self.longUsd = longUsd; self.shortUsd = shortUsd; self.count = count
    self.maxUsd = maxUsd; self.maxPrice = maxPrice; self.maxIsLong = maxIsLong; self.maxExchange = maxExchange
  }
}

/// 服务端 /liq 的一页。
public struct LiquidationPage: Sendable, Equatable {
  public var tracked: Bool
  public var rows: [LiquidationRow]
  public init(tracked: Bool, rows: [LiquidationRow]) { self.tracked = tracked; self.rows = rows }
}

/// 一段的爆仓合计与这段里最大的一笔。
public struct LiquidationSum: Sendable, Equatable {
  public var longUsd: Double = 0
  public var shortUsd: Double = 0
  public var count = 0
  public var max: LiquidationRow?
  public init() {}
  public var total: Double { longUsd + shortUsd }
}

/// 一只品种在本机留的爆仓分钟行（3 天）。值类型，`LiquidationFeed` 每 30 秒并一页进来。
public struct LiquidationBook: Sendable, Equatable {
  public static let keepMs: Int64 = 3 * 86_400_000
  public static let pollMs: Int64 = 30_000
  /// 增量从已有的最后一行往前退多少接着取（分钟会补齐）。
  public static let overlapMs: Int64 = 120_000

  public let base: String
  public private(set) var rows: [Int64: LiquidationRow] = [:]
  /// nil = 还没取到过。
  public private(set) var tracked: Bool?
  public private(set) var version = 0

  public init(base: String) { self.base = base }

  /// 下一次从哪儿取：第一次取 3 天，之后从最后一行往前 2 分钟起。
  public func fetchFrom(nowMs now: Int64) -> Int64 {
    guard let last = rows.keys.max() else { return now - Self.keepMs }
    return max(now - Self.keepMs, last - Self.overlapMs)
  }

  public mutating func merge(_ page: LiquidationPage, nowMs now: Int64) {
    tracked = page.tracked
    for row in page.rows { rows[row.minuteMs] = row }
    let cutoff = now - Self.keepMs
    if rows.keys.contains(where: { $0 < cutoff }) { rows = rows.filter { $0.key >= cutoff } }
    version &+= 1
  }

  /// [a, b) 的合计（整分钟落在区间里的都算），最大一笔跟着最大的那行。
  public func sum(_ a: Int64, _ b: Int64) -> LiquidationSum {
    var s = LiquidationSum()
    for r in rows.values where r.minuteMs >= a && r.minuteMs < b {
      s.longUsd += r.longUsd; s.shortUsd += r.shortUsd; s.count += r.count
      if r.maxUsd > 0, r.maxUsd > (s.max?.maxUsd ?? 0) || (r.maxUsd == s.max?.maxUsd && r.minuteMs > s.max!.minuteMs) {
        s.max = r
      }
    }
    return s
  }

  /// 24 小时时间轴：`cells` 格、每格 `cellMs`（默认 96 × 15 分钟），最后一格含 `now`。
  public func timeline(nowMs now: Int64, cells: Int = 96, cellMs: Int64 = 15 * 60_000) -> [LiquidationSum] {
    guard cells > 0, cellMs > 0 else { return [] }
    let lastStart = (now / cellMs) * cellMs
    let first = lastStart - Int64(cells - 1) * cellMs
    var out = [LiquidationSum](repeating: LiquidationSum(), count: cells)
    for r in rows.values where r.minuteMs >= first && r.minuteMs < lastStart + cellMs {
      let i = Int((r.minuteMs - first) / cellMs)
      out[i].longUsd += r.longUsd; out[i].shortUsd += r.shortUsd; out[i].count += r.count
      if r.maxUsd > (out[i].max?.maxUsd ?? 0) { out[i].max = r }
    }
    return out
  }
}
