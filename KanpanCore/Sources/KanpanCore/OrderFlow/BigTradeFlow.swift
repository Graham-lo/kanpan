import Foundation

// 大单与爆仓 · 大额成交的分钟桶（2026-10-08，手机「图上大单签」与「大单与爆仓」弹层共用的一份）。
//
// 口径照网页版 chart/tradeFlow.ts + orderflow/bigTags.ts（三端一致，那边验过）：
//   · 主力订单流打开一只品种时连着币安、OKX、Coinbase 全部簿的逐笔成交；一笔 ≥ 大单线（门槛 ÷ 50，服务端给过
//     `bigUsd` 就用服务端的，两边同口径）就按成交时刻落进「分钟」桶，记主动买 / 卖的美元额与笔数；逐笔的价位另留 2 小时
//     （弹层「价位」梯用）。分钟桶留 3 天。
//   · 数据层每拍一次心跳（连接都开着才算），相邻两拍隔不到 10 秒就连成一段「覆盖区间」：整分钟落在覆盖区间里的，
//     本机记的就是全部；否则服务端有这一分钟的行用服务端的（只有金额、没有笔数）；服务端在跟这只、这一分钟落在
//     它的历史里却没有行 = 这一分钟没有大单；再不然用本机攒到的那一部分。
//   · 服务端历史 GET /v1/market/orderflow/flow（近 3 天、每分钟一行）。没在跟的品种只有本机从打开起记的。
// 只聚合、门槛过滤、展示，不做判定。值类型：数据层在自己的执行器上改，一帧一帧整份交给界面（写时复制）。

/// 一分钟的大单：主动买 / 卖的美元额与笔数。
public struct BigTradeCell: Sendable, Equatable {
  public var buyUsd: Double = 0
  public var sellUsd: Double = 0
  public var buyCount = 0
  public var sellCount = 0
  public init(buyUsd: Double = 0, sellUsd: Double = 0, buyCount: Int = 0, sellCount: Int = 0) {
    self.buyUsd = buyUsd; self.sellUsd = sellUsd; self.buyCount = buyCount; self.sellCount = sellCount
  }
}

/// 一笔大单成交的价位（按时间升序，只留 2 小时）。价是图上的价（和挂单墙同一单位）。
public struct BigTradePrint: Sendable, Equatable {
  public var timeMs: Int64
  public var price: Double
  public var usd: Double
  public var buy: Bool
  public init(timeMs: Int64, price: Double, usd: Double, buy: Bool) {
    self.timeMs = timeMs; self.price = price; self.usd = usd; self.buy = buy
  }
}

/// 服务端 /flow 的一页。
public struct BigTradeFlowPage: Sendable, Equatable {
  public struct Row: Sendable, Equatable {
    public var minuteMs: Int64
    public var buyUsd: Double
    public var sellUsd: Double
    public init(minuteMs: Int64, buyUsd: Double, sellUsd: Double) {
      self.minuteMs = minuteMs; self.buyUsd = buyUsd; self.sellUsd = sellUsd
    }
  }
  public var tracked: Bool
  public var bigUsd: Double?
  public var rows: [Row]
  public init(tracked: Bool, bigUsd: Double?, rows: [Row]) {
    self.tracked = tracked; self.bigUsd = bigUsd; self.rows = rows
  }
}

/// 一段 [a, b) 的大单合计。笔数只有整段的大单金额都来自本机时才有（服务端的行没有笔数）。
public struct BigTradeSum: Sendable, Equatable {
  public var buyUsd: Double = 0
  public var sellUsd: Double = 0
  public var buyCount: Int?
  public var sellCount: Int?
  /// 这段有数据（本机记过、或服务端覆盖到）。false = 什么都不知道。
  public var has = false
  public init(buyUsd: Double = 0, sellUsd: Double = 0, buyCount: Int? = 0, sellCount: Int? = 0, has: Bool = false) {
    self.buyUsd = buyUsd; self.sellUsd = sellUsd; self.buyCount = buyCount; self.sellCount = sellCount; self.has = has
  }
  public var net: Double { buyUsd - sellUsd }
  public var total: Double { buyUsd + sellUsd }
}

public struct BigTradeFlow: Sendable {
  public static let minuteMs: Int64 = 60_000
  /// 两拍心跳隔这么久就算断了（覆盖区间另起一段）。
  public static let gapMs: Int64 = 10_000
  /// 分钟桶、服务端行、覆盖区间留多久。
  public static let keepMs: Int64 = 3 * 86_400_000
  /// 逐笔价位留多久、最多几笔。
  public static let printKeepMs: Int64 = 2 * 3_600_000
  public static let printCap = 20_000
  /// 服务端历史多久增量拉一次；失败了多久再试。
  public static let pollMs: Int64 = 60_000
  public static let retryMs: Int64 = 30_000

  public let symbol: String
  /// 本机记的分钟桶（键 = 分钟开盘毫秒）。
  public private(set) var minutes: [Int64: BigTradeCell] = [:]
  /// 覆盖区间 [起, 止]（本机时间），按时间排。
  public private(set) var cover: [ClosedRange<Int64>] = []
  public private(set) var prints: [BigTradePrint] = []
  /// 服务端的分钟行（买, 卖）。
  public private(set) var serverRows: [Int64: (buy: Double, sell: Double)] = [:]
  /// 服务端历史覆盖的分钟（含两端）；没有数据时 nil。
  public private(set) var serverRange: ClosedRange<Int64>?
  /// 服务端在不在跟这只：nil = 还没问到。
  public private(set) var tracked: Bool?
  public private(set) var serverBigUsd: Double?
  /// 本机当下用的大单线（门槛 ÷ 50）。
  public private(set) var localCut: Double?
  /// 最近一笔成交（不论大小）的时刻：「数据停在 hh:mm」用。
  public private(set) var lastTradeMs: Int64?
  /// 最近一笔大单（时刻, 买方）：图上正在走那根签的光环用。
  public private(set) var lastBig: (timeMs: Int64, buy: Bool)?
  /// 内容版本：进了一笔大单、并进服务端行、覆盖区间另起一段时加一。界面按它判断要不要重算。
  public private(set) var version = 0
  private var prunedAtMs: Int64 = .min / 2

  public init(symbol: String) { self.symbol = symbol }

  /// 生效的大单线：服务端给过就用服务端的。
  public var cut: Double? { serverBigUsd ?? localCut }

  /// 门槛 → 大单线（÷ 50）。
  public static func cut(threshold: Double) -> Double { threshold / 50 }

  /// 这只品种按哪档门槛定大单线：U 本位永续 → 现货 → 币本位 / 交割里低的那个（和网页版、服务端同口径）。
  public static func threshold(_ t: OrderFlowThresholds) -> Double? {
    if let v = t[.usdtPerp] { return v }
    if let v = t[.spot] { return v }
    switch (t[.coinPerp], t[.delivery]) {
    case let (a?, b?): return min(a, b)
    case let (a?, nil): return a
    case let (nil, b?): return b
    default: return nil
    }
  }

  // MARK: - 记录

  /// 进一笔成交（`usd` 已按这本簿的计价算成美元）。`cut` 是本机此刻的大单线。返回这笔算不算大单。
  @discardableResult
  public mutating func record(timeMs: Int64, price: Double, usd: Double, buy: Bool, cut: Double?) -> Bool {
    if let cut, cut > 0, cut.isFinite { localCut = cut }
    guard usd > 0, usd.isFinite else { return false }
    lastTradeMs = max(lastTradeMs ?? timeMs, timeMs)
    guard let big = self.cut, usd >= big else { return false }
    let minute = Self.floorMinute(timeMs)
    var c = minutes[minute] ?? BigTradeCell()
    if buy { c.buyUsd += usd; c.buyCount += 1 } else { c.sellUsd += usd; c.sellCount += 1 }
    minutes[minute] = c
    if price > 0, price.isFinite {
      let p = BigTradePrint(timeMs: timeMs, price: price, usd: usd, buy: buy)
      if let last = prints.last, last.timeMs > timeMs {
        let i = prints.firstIndex { $0.timeMs > timeMs } ?? prints.count
        prints.insert(p, at: i)
      } else {
        prints.append(p)
      }
    }
    if lastBig.map({ timeMs >= $0.timeMs }) ?? true { lastBig = (timeMs, buy) }
    version &+= 1
    return true
  }

  /// 数据层每拍一次：连接都开着（`ok`）就把覆盖区间往后接（断了 10 秒以上另起一段）；顺手清掉过期的。
  public mutating func beat(nowMs now: Int64, ok: Bool) {
    if ok {
      if let last = cover.last, now - last.upperBound <= Self.gapMs, now >= last.lowerBound {
        cover[cover.count - 1] = last.lowerBound...max(last.upperBound, now)
      } else {
        cover.append(now...now)
        version &+= 1
      }
    }
    prune(nowMs: now)
  }

  private mutating func prune(nowMs now: Int64) {
    // 逐笔价位每拍都看头上几笔（按时间排，删头部很便宜）；分钟桶与服务端行一分钟清一次。
    let pc = now - Self.printKeepMs
    var drop = 0
    while drop < prints.count, prints[drop].timeMs < pc { drop += 1 }
    if prints.count - drop > Self.printCap { drop = prints.count - Self.printCap }
    if drop > 0 { prints.removeFirst(drop) }
    guard now - prunedAtMs >= Self.minuteMs else { return }
    prunedAtMs = now
    let cutoff = now - Self.keepMs
    if minutes.keys.contains(where: { $0 < cutoff }) { minutes = minutes.filter { $0.key >= cutoff } }
    while let first = cover.first, first.upperBound < cutoff { cover.removeFirst() }
    if serverRows.keys.contains(where: { $0 < cutoff }) {
      serverRows = serverRows.filter { $0.key >= cutoff }
      if let range = serverRange {
        serverRange = serverRows.keys.min().map { $0...range.upperBound }
      }
    }
  }

  // MARK: - 服务端历史

  /// 下一次该从哪儿取：取到过就从最晚那一分钟接着取，否则取满 3 天。
  public func serverFetchFrom(nowMs now: Int64) -> Int64 {
    if let hi = serverRange?.upperBound, hi > 0 { return hi }
    return now - Self.keepMs
  }

  /// 并进一页服务端历史。服务端在跟这只时，它历史范围（最早到最晚一行）里没有行的分钟 = 没有大单。
  public mutating func merge(_ page: BigTradeFlowPage, nowMs now: Int64) {
    tracked = page.tracked
    if let big = page.bigUsd, big > 0, big.isFinite { serverBigUsd = big }
    let cutoff = now - Self.keepMs
    var lo = serverRange?.lowerBound, hi = serverRange?.upperBound
    for row in page.rows where row.minuteMs >= cutoff {
      serverRows[row.minuteMs] = (max(0, row.buyUsd), max(0, row.sellUsd))
      lo = min(lo ?? row.minuteMs, row.minuteMs)
      hi = max(hi ?? row.minuteMs, row.minuteMs)
    }
    if let lo, let hi { serverRange = lo...hi }
    version &+= 1
  }

  // MARK: - 取数

  /// 这一段 [a, b) 是不是整个落在一个覆盖区间里；b 在未来（正在走的那根）时要求覆盖还没断。
  public func covered(_ a: Int64, _ b: Int64, nowMs now: Int64) -> Bool {
    for range in cover.reversed() {
      if range.lowerBound > a { continue }
      if b <= range.upperBound { return true }
      return b > now && now - range.upperBound <= Self.gapMs
    }
    return false
  }

  /// 一分钟取哪份（见文件头）。返回 (单元, 是不是本机的整份, 有没有数据)。
  @inline(__always)
  private func minute(_ m: Int64, firstCover: Int64?, nowMs now: Int64) -> (cell: BigTradeCell, exact: Bool, has: Bool) {
    let local = minutes[m]
    if let firstCover, m >= firstCover, covered(m, m + Self.minuteMs, nowMs: now) {
      return (local ?? BigTradeCell(), true, local != nil)
    }
    if let row = serverRows[m] {
      return (BigTradeCell(buyUsd: row.buy, sellUsd: row.sell), row.buy <= 0 && row.sell <= 0, true)
    }
    if tracked == true, let range = serverRange, range.contains(m) { return (BigTradeCell(), true, true) }
    return (local ?? BigTradeCell(), true, local != nil)
  }

  /// 最早有数据的那一分钟（本机最早的桶，或服务端在跟时它历史的起点）。
  private var start: Int64? {
    var s = minutes.keys.min()
    if tracked == true, let lo = serverRange?.lowerBound { s = min(s ?? lo, lo) }
    return s
  }

  /// [a, b) 的大单合计。
  public func sum(_ a: Int64, _ b: Int64, nowMs now: Int64) -> BigTradeSum {
    var out = BigTradeSum()
    guard let start, b > a else { return out }
    let firstCover = cover.first?.lowerBound
    var exact = true
    var buyN = 0, sellN = 0
    var m = max(Self.floorMinute(a), Self.floorMinute(start))
    while m < b && m <= now {
      let x = minute(m, firstCover: firstCover, nowMs: now)
      if x.has {
        out.has = true
        out.buyUsd += x.cell.buyUsd; out.sellUsd += x.cell.sellUsd
        buyN += x.cell.buyCount; sellN += x.cell.sellCount
        if !x.exact { exact = false }
      }
      m += Self.minuteMs
    }
    out.buyCount = exact ? buyN : nil
    out.sellCount = exact ? sellN : nil
    return out
  }

  /// 给图表的分钟序列（只有有大单的分钟，按时间升序）：每一分钟取哪份照 `sum` 的规矩。
  public func tape(nowMs now: Int64, floor: Double) -> BigTradeTape {
    var times: [Int64] = [], buy: [Double] = [], sell: [Double] = []
    if let start {
      let firstCover = cover.first?.lowerBound
      var keys = Set(minutes.keys)
      for k in serverRows.keys { keys.insert(k) }
      for m in keys.sorted() where m >= Self.floorMinute(start) && m <= now {
        let x = minute(m, firstCover: firstCover, nowMs: now)
        guard x.cell.buyUsd > 0 || x.cell.sellUsd > 0 else { continue }
        times.append(m); buy.append(x.cell.buyUsd); sell.append(x.cell.sellUsd)
      }
    }
    return BigTradeTape(symbol: symbol, minutes: times, buy: buy, sell: sell, floor: floor,
                        lastBigMs: lastBig?.timeMs, lastBigBuy: lastBig?.buy ?? true)
  }

  public static func floorMinute(_ t: Int64) -> Int64 {
    let q = t / minuteMs
    return (t < 0 && t % minuteMs != 0 ? q - 1 : q) * minuteMs
  }
}

extension BigTradeFlow: Equatable {
  /// 按内容版本比：分钟桶与逐笔每秒都在长，逐项比没必要（审查第 31 项同一个道理）。
  /// 最近一笔成交按 5 秒取整也算进来：界面的「数据停在 hh:mm」要靠它。
  public static func == (a: BigTradeFlow, b: BigTradeFlow) -> Bool {
    a.symbol == b.symbol && a.version == b.version && a.localCut == b.localCut && a.tracked == b.tracked
      && a.lastTradeMs.map { $0 / 5000 } == b.lastTradeMs.map { $0 / 5000 }
  }
}

/// 图上大单签吃的那一份：有大单的分钟（升序）与各自的买 / 卖额，图表按自己的 K 线开盘时间并成根。
public struct BigTradeTape: Sendable, Equatable {
  public var symbol: String
  public var minutes: [Int64]
  public var buy: [Double]
  public var sell: [Double]
  /// 档位的绝对下限（门槛 ÷ 5）。
  public var floor: Double
  /// 最近一笔大单的时刻与方向（正在走那根的签外圈光环）。
  public var lastBigMs: Int64?
  public var lastBigBuy: Bool

  public init(symbol: String, minutes: [Int64], buy: [Double], sell: [Double], floor: Double,
              lastBigMs: Int64? = nil, lastBigBuy: Bool = true) {
    self.symbol = symbol; self.minutes = minutes; self.buy = buy; self.sell = sell; self.floor = floor
    self.lastBigMs = lastBigMs; self.lastBigBuy = lastBigBuy
  }

  /// [a, b) 里的买 / 卖合计。
  public func sum(_ a: Int64, _ b: Int64) -> (buy: Double, sell: Double) {
    var i = lowerBound(a)
    var bb = 0.0, bs = 0.0
    while i < minutes.count, minutes[i] < b { bb += buy[i]; bs += sell[i]; i += 1 }
    return (bb, bs)
  }

  /// 第一个 ≥ t 的下标。
  public func lowerBound(_ t: Int64) -> Int {
    var lo = 0, hi = minutes.count
    while lo < hi {
      let mid = (lo + hi) / 2
      if minutes[mid] < t { lo = mid + 1 } else { hi = mid }
    }
    return lo
  }

  /// 按一串 K 线开盘时间（升序）并成每根的买 / 卖：第 i 根是 [opens[i], opens[i+1])，最后一根到 `lastEnd`。
  /// 一趟扫完（O(根数 + 分钟数)），图表缓存它。
  public func bars(opens: [Int64], lastEnd: Int64) -> (buy: [Double], sell: [Double]) {
    var bb = [Double](repeating: 0, count: opens.count), bs = bb
    guard !opens.isEmpty, !minutes.isEmpty else { return (bb, bs) }
    var j = lowerBound(opens[0])
    for i in opens.indices {
      let end = i + 1 < opens.count ? opens[i + 1] : lastEnd
      while j < minutes.count, minutes[j] < end {
        if minutes[j] >= opens[i] { bb[i] += buy[j]; bs[i] += sell[j] }
        j += 1
      }
    }
    return (bb, bs)
  }
}
