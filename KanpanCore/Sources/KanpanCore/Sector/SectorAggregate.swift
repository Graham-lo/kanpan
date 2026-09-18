import Foundation

/// 一个品种在板块聚合里用到的那点行情。归类是静态的，这一半是实时的。
public struct SectorQuote: Sendable, Equatable {
  /// base 代号，大写。
  public let base: String
  /// 24h 涨跌幅，百分数（-3.42 就是跌 3.42%），不是小数。
  public let pct: Double
  /// 24h 成交额（计价币）。
  public let quoteVolume: Double
  public let price: Double
  public init(base: String, pct: Double, quoteVolume: Double, price: Double) {
    self.base = base
    self.pct = pct
    self.quoteVolume = quoteVolume
    self.price = price
  }
}

/// 一个板块此刻的统计。`pct` 是成员涨跌幅的中位数——板块只有这一个口径。
///
/// 除了主数字，这儿还带着「这个数是怎么来的」：`breadth` 说整体跑赢池基准的比例，
/// `frontier` 点名领跑的那几只，`jackknife` 说删掉任意一个成员后中位数会摆到哪儿。
/// 五个成员 `−2, −1, 0, +1, +300` 的板块，`pct` 是 0、`frontier` 只有那只 +300、
/// `jackknife` 窄成一条线——「整体没动、一只在爆」直接读得出来。
public struct SectorStat: Sendable, Equatable, Identifiable {
  public let id: String
  public let name: String
  public let market: SectorMarket
  /// 成员涨跌幅的中位数，百分数。
  public let pct: Double
  /// 有行情的成员数（没行情的成员不参与，也不计数）。
  public let memberCount: Int
  /// 分类表里登记的成员数（按 base 去重后）。`memberCount` 少于它就是有成员没行情。
  public let staticCount: Int
  /// 成员成交额之和。
  public let quoteVolume: Double
  /// 兜底桶。兜底桶在气泡场的排序与归一之前就被摘掉，只活在「全部板块」里。
  public let isFallback: Bool
  /// 相对广度：跑赢池基准（`e_i > 0`）的成员占 `memberCount` 的比例。平盘不算跑赢。
  public let breadth: Double
  /// 绝对上涨家数（`pct > 0`）。和 `breadth` 不是一回事：全场普涨的日子里
  /// 一个板块可以人人翻红却没一个跑赢大盘。
  public let upCount: Int
  /// 前沿成员：跑赢基准、且相对收益排在全池 90 分位以上的那几只，按相对收益降序。
  public let frontier: [String]
  /// 删一区间：逐个删掉一个成员再取中位数，落在这个范围里。成员 ≤ 2 时没有意义，缺省。
  public let jackknife: ClosedRange<Double>?
  /// 进不进气泡场。有行情成员 < 3 的板块（以及兜底桶）不上场——一只币的涨跌不是板块强弱。
  public let eligible: Bool

  /// 跑赢池基准的家数。`breadth` 就是它除以 `memberCount`，这儿还原回整数给界面用。
  public var outperformCount: Int {
    guard memberCount > 0, breadth.isFinite else { return 0 }
    return Int((breadth * Double(memberCount)).rounded())
  }

  /// `staticCount` 不传就等于 `memberCount`；`eligible` 不传按上得了场算
  /// ——手搓统计（测试、预览）默认不该被过滤掉。
  public init(id: String, name: String, market: SectorMarket,
              pct: Double, memberCount: Int, staticCount: Int? = nil,
              quoteVolume: Double, isFallback: Bool,
              breadth: Double = 0, upCount: Int = 0, frontier: [String] = [],
              jackknife: ClosedRange<Double>? = nil, eligible: Bool = true) {
    self.id = id
    self.name = name
    self.market = market
    self.pct = pct
    self.memberCount = memberCount
    self.staticCount = staticCount ?? memberCount
    self.quoteVolume = quoteVolume
    self.isFallback = isFallback
    self.breadth = breadth
    self.upCount = upCount
    self.frontier = frontier
    self.jackknife = jackknife
    self.eligible = eligible
  }
}

/// 没被任何板块收录的品种，按交易所自带 tag 兜底聚出来的桶。
///
/// 静态表管不着它们（TSV 里那 48 个 `NONE` 就是这一拨）：tag 是交易所给的，
/// 会随合约上下架变，所以由调用方在运行时组好了传进来。
public struct SectorFallbackBucket: Sendable, Equatable {
  /// 约定形如 `"fb-<tag>"`，跟静态板块 id 天然不撞。
  public let id: String
  public let name: String
  public let members: [String]
  public init(id: String, name: String, members: [String]) {
    self.id = id
    self.name = name
    self.members = members
  }
}

/// 同一个 base 挂着好几张合约（USDT 本位 + USDC 本位 + FDUSD…）时留哪一张。
///
/// 从前是「留成交额大的那张」，可 USDT 和 USDC 两张的 24h 涨幅并不相同，成交额
/// 来回反超就让板块的中位数跟着跳、球跟着抖。所以先按计价币的固定档次挑，
/// 同一档才比成交额。
public enum SectorQuotePreference {
  /// 计价币优先级，越靠前越优先。表里没有的一律垫底。
  public static let quoteAssets = ["USDT", "USDC", "FDUSD", "BUSD", "USD1", "TUSD"]

  public static func rank(_ quote: String) -> Int {
    quoteAssets.firstIndex(of: quote.uppercased()) ?? quoteAssets.count
  }

  /// 新来的这张是不是比手上那张更该留下。
  public static func prefers(rank: Int, volume: Double,
                             over other: (rank: Int, volume: Double)) -> Bool {
    rank != other.rank ? rank < other.rank : volume > other.volume
  }
}

/// 市场池：一个市场里所有有行情的品种，以及它们相对池基准的超额收益。
///
/// 「涨了 3%」这句话单独没有意义——全场平均涨 5% 的时候它其实是在拖后腿。
/// 所以广度和前沿都不看绝对涨跌，只看 `e_i = r_i − b`。
struct SectorPool: Sendable {
  /// 大写 base → 相对收益 `e_i`（对数口径）。
  let excess: [String: Double]
  /// 前沿门槛：池内 `e_i` 的 90 分位。池空时是 `+∞`，谁都进不了前沿。
  let frontierCut: Double

  static let empty = SectorPool(excess: [:], frontierCut: .infinity)
}

/// 把静态归类 × 实时行情聚成板块统计。
public enum SectorAggregator {
  /// 有行情成员少于这个数的板块不进气泡场。
  public static let minEligibleMembers = 3

  /// - Parameters:
  ///   - quotes: 以**大写 base** 为键。
  ///   - fallbackBuckets: 兜底桶，聚出来的 `isFallback = true`。
  /// - Returns: 顺序 = 目录顺序在前、兜底桶按传入顺序在后。
  ///            **一个成员都没行情的板块直接不出现**（不是给个 0）。
  public static func stats(market: SectorMarket,
                           quotes: [String: SectorQuote],
                           fallbackBuckets: [SectorFallbackBucket]) -> [SectorStat] {
    // 池基准只算一次：它是整个市场的事，不是某个板块的事。
    let pool = pool(market: market, quotes: quotes, fallbackBuckets: fallbackBuckets)
    var out: [SectorStat] = []
    out.reserveCapacity(SectorCatalog.sectors(market).count + fallbackBuckets.count)
    for def in SectorCatalog.sectors(market) {
      if let s = stat(id: def.id, name: def.name, market: market,
                      members: def.members, quotes: quotes, pool: pool, isFallback: false) {
        out.append(s)
      }
    }
    for b in fallbackBuckets {
      if let s = stat(id: b.id, name: b.name, market: market,
                      members: b.members, quotes: quotes, pool: pool, isFallback: true) {
        out.append(s)
      }
    }
    return out
  }

  // MARK: - 市场池

  /// 池 `G` = 该市场所有有行情、按 base 去重的品种（分类表收录的 + 兜底桶里的）。
  ///
  /// 基准 `b` 取等权均值而不是中位数：中位数会把「全场普涨」这件事本身吃掉一半。
  static func pool(market: SectorMarket,
                   quotes: [String: SectorQuote],
                   fallbackBuckets: [SectorFallbackBucket]) -> SectorPool {
    var seen = Set<String>()
    var returns: [String: Double] = [:]
    func collect(_ members: [String]) {
      for raw in members {
        let base = raw.uppercased()
        guard seen.insert(base).inserted, let q = quotes[base], q.pct.isFinite else { continue }
        returns[base] = logReturn(q.pct)
      }
    }
    for def in SectorCatalog.sectors(market) { collect(def.members) }
    for bucket in fallbackBuckets { collect(bucket.members) }
    guard !returns.isEmpty else { return .empty }

    let base = returns.values.reduce(0, +) / Double(returns.count)
    let excess = returns.mapValues { $0 - base }
    return SectorPool(excess: excess, frontierCut: quantile(excess.values.sorted(), 0.9))
  }

  /// 百分数 → 对数收益。比例口径下 `ln(1+x)` 才可加，也才让「价格统一乘常数」这类
  /// 变换在相减之后干净地抵消掉。跌停到 −100% 以下是脏数据，夹住免得出 −∞。
  static func logReturn(_ pct: Double) -> Double {
    log1p(max(pct, -99.99) / 100)
  }

  /// 线性插值分位：取位置 `(n−1)p`，落在两个样本之间就按比例取。`sorted` 升序、非空。
  static func quantile(_ sorted: [Double], _ p: Double) -> Double {
    precondition(!sorted.isEmpty)
    let n = sorted.count
    if n == 1 { return sorted[0] }
    let pos = Double(n - 1) * min(max(p, 0), 1)
    let lo = Int(pos.rounded(.down))
    let hi = min(lo + 1, n - 1)
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - Double(lo))
  }

  // MARK: - 单个桶

  /// 单个桶的聚合。成员按 base 去重，没行情的跳过（但仍计进 `staticCount`）。
  private static func stat(id: String, name: String, market: SectorMarket,
                           members: [String], quotes: [String: SectorQuote],
                           pool: SectorPool, isFallback: Bool) -> SectorStat? {
    var bases: [String] = []
    var pcts: [Double] = []
    var vols: [Double] = []
    var seen = Set<String>()
    var staticCount = 0
    bases.reserveCapacity(members.count)
    pcts.reserveCapacity(members.count)
    vols.reserveCapacity(members.count)
    for raw in members {
      let base = raw.uppercased()
      guard seen.insert(base).inserted else { continue }
      staticCount += 1
      guard let q = quotes[base], q.pct.isFinite else { continue }
      bases.append(base)
      pcts.append(q.pct)
      vols.append(q.quoteVolume.isFinite ? q.quoteVolume : 0)
    }
    guard !pcts.isEmpty else { return nil }

    var outperform = 0
    var up = 0
    var frontier: [(base: String, excess: Double)] = []
    for (index, base) in bases.enumerated() {
      if pcts[index] > 0 { up += 1 }
      guard let e = pool.excess[base], e > 0 else { continue }
      outperform += 1
      if e >= pool.frontierCut { frontier.append((base, e)) }
    }
    // 并列按代号排，免得两次刷新之间换位。
    frontier.sort { $0.excess == $1.excess ? $0.base < $1.base : $0.excess > $1.excess }

    return SectorStat(id: id, name: name, market: market,
                      pct: median(pcts),
                      memberCount: pcts.count, staticCount: staticCount,
                      quoteVolume: vols.reduce(0, +), isFallback: isFallback,
                      breadth: Double(outperform) / Double(pcts.count),
                      upCount: up, frontier: frontier.map(\.base),
                      jackknife: jackknife(pcts),
                      eligible: pcts.count >= minEligibleMembers && !isFallback)
  }

  /// 偶数个取中间两个的平均——跟分类表 README 的口径一致。
  static func median(_ values: [Double]) -> Double {
    precondition(!values.isEmpty)
    let s = values.sorted()
    let n = s.count
    if n % 2 == 1 { return s[n / 2] }
    return (s[n / 2 - 1] + s[n / 2]) / 2
  }

  /// 删一（jackknife）区间：逐个删掉一个成员，中位数会落在哪个范围里。
  ///
  /// 排完序之后「删掉第 j 个」不用真的重建数组——第 i 个位置上的元素不是 `s[i]`
  /// 就是 `s[i+1]`，所以整趟是 O(n)。成员 ≤ 2 时删一之后不剩东西可谈，返回 nil。
  static func jackknife(_ values: [Double]) -> ClosedRange<Double>? {
    guard values.count >= minEligibleMembers else { return nil }
    let s = values.sorted()
    let n = s.count
    let m = n - 1
    func element(_ i: Int, dropping j: Int) -> Double { i < j ? s[i] : s[i + 1] }
    var lo = Double.infinity
    var hi = -Double.infinity
    for j in 0..<n {
      let med = m % 2 == 1
        ? element(m / 2, dropping: j)
        : (element(m / 2 - 1, dropping: j) + element(m / 2, dropping: j)) / 2
      lo = Swift.min(lo, med)
      hi = Swift.max(hi, med)
    }
    return lo...hi
  }
}
