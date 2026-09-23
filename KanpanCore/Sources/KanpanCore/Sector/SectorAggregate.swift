import Foundation

/// 一个品种在板块聚合里用到的那点行情。归类是静态的，这一半是实时的。
public struct SectorQuote: Sendable, Equatable {
  /// base 代号，大写。
  public let base: String
  /// 24h 涨跌幅，百分数（-3.42 就是跌 3.42%），不是小数。
  public let pct: Double
  /// 24h 成交额（计价币）。**拿不到就是 NaN**，不是 0——0 是「真的零成交」，
  /// 而缺数不许冒充它（审查复核项 1）。加总、排序、挑合约都各自把非有限值排除。
  public let quoteVolume: Double
  public let price: Double
  public init(base: String, pct: Double, quoteVolume: Double, price: Double) {
    self.base = base
    self.pct = pct
    self.quoteVolume = quoteVolume
    self.price = price
  }
}

/// 看哪一段时间。
///
/// 页面上只给用户两颗：「今日」和「5 日」（`kanpan-sector-page-no-basis-picker`：
/// 一页上的模式最多两个）。`d20` 不是一个模式，它只在品种列表头部补一句
/// 「20 日 +12.1%」——同一个算法，换一段窗口，不另开一颗药丸。
///
/// 三个窗口共用一套口径：给每个成员**一个收益值**，然后照样算中位数、广度、
/// 领涨、删一。差别只在这个收益值怎么来。
public enum SectorWindow: String, Sendable, CaseIterable, Equatable {
  /// 24h 涨跌幅。交易所在 ticker 里直接给，永远有。
  case today
  /// 5 个交易日：现价 ÷ 5 个交易日前的收盘。
  case d5
  /// 20 个交易日。
  case d20

  /// 要不要日线收盘。`today` 不要——所以取历史失败时今日这一档一点都不受影响。
  public var needsHistory: Bool { self != .today }
}

/// 一个品种的日线收盘。缺一档就是**没有**，不是 0——0 会让 `last/c − 1` 变成 +∞。
public struct SectorCloses: Sendable, Equatable {
  /// 5 个交易日前那根日线的收盘价。
  public let c5: Double?
  /// 20 个交易日前那根日线的收盘价。
  public let c20: Double?
  public init(c5: Double? = nil, c20: Double? = nil) {
    self.c5 = c5
    self.c20 = c20
  }

  /// 某个窗口要的那一档收盘。`today` 不看收盘。
  public func close(_ window: SectorWindow) -> Double? {
    switch window {
    case .today: return nil
    case .d5: return c5
    case .d20: return c20
    }
  }
}

/// 服务端那份日线收盘的一次快照。
///
/// `asof` 是它算到哪一天（`YYYY-MM-DD`），**只用来判这份数据有没有换过、够不够新**，
/// 界面上一个字都不出现（`kanpan-no-engineering-status-fields`：更新时间、数据截至、
/// 数据来源、覆盖率都不是给用户看的东西）。
public struct SectorHistory: Sendable, Equatable {
  public let asof: String
  /// 大写 base → 收盘。取数那一侧已经把 `BTCUSDT` 折成 `BTC` 了，板块这一路只认 base。
  public let closes: [String: SectorCloses]

  public init(asof: String, closes: [String: SectorCloses]) {
    self.asof = asof
    self.closes = closes
  }

  /// 没有历史。取数没回来、失败、或这个市场服务端根本还没采——都是这一份。
  public static let empty = SectorHistory(asof: "", closes: [:])

  public var isEmpty: Bool { closes.isEmpty }

  /// `asof` 解成那一天的 UTC 零点。严格 `YYYY-MM-DD`：四位年、两位月、两位日，
  /// 全是 ASCII 数字，而且日历上真有这一天（`2026-02-30` 不算）。解不出来一律 nil
  /// ——服务端给的是 `NaiveDate` 的原样字符串，别的形状只可能是坏包。
  public static func day(_ asof: String) -> Date? {
    let pieces = asof.split(separator: "-", omittingEmptySubsequences: false)
    guard pieces.count == 3, pieces[0].count == 4, pieces[1].count == 2, pieces[2].count == 2,
          pieces.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
          let y = Int(pieces[0]), let m = Int(pieces[1]), let d = Int(pieces[2])
    else { return nil }
    var parts = DateComponents()
    parts.year = y; parts.month = m; parts.day = d
    guard let date = utcCalendar.date(from: parts) else { return nil }
    // `date(from:)` 会把 2 月 30 号顺延到 3 月 2 号。折回来对一遍才知道是不是真有这天。
    let back = utcCalendar.dateComponents([.year, .month, .day], from: date)
    guard back.year == y, back.month == m, back.day == d else { return nil }
    return date
  }

  private static let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
  }()

  /// 这一份是哪一天的。解不出来就是 nil——那就不是一份能用的快照。
  public var day: Date? { Self.day(asof) }

  /// 一份快照最多认几天。
  ///
  /// `c5` 是 `asof − 5 天`那根日线的收盘：快照旧一天，「5 日」那一档就多算一天。
  /// 旧到一周前，挂在「5 日」上的其实是十二天的收益——宁可留空（那颗药丸整行不出现）
  /// 也不能给错的数。
  public static let maxAgeDays = 7

  /// 这一份（不管来自网络还是磁盘）还认不认。
  public func isFresh(now: Date = Date()) -> Bool { Self.isFresh(asof, now: now) }

  public static func isFresh(_ asof: String, now: Date = Date()) -> Bool {
    guard let date = day(asof) else { return false }
    let days = now.timeIntervalSince(date) / 86_400
    // 未来那头留两天：服务端按 UTC 跨日，手机的钟还可能偏。
    return days >= -2 && days <= Double(maxAgeDays)
  }

  /// 新取回来的这份要不要顶掉手上那份。
  ///
  /// 日线一天才换一次，同一个 `asof` 基本就是同一份数据。手上已经有同一天的还照样
  /// 赋值，整页会为一份一模一样的收盘重算一遍聚合、重排一遍列表——用户看得见的是
  /// 无缘无故抖一下。
  ///
  /// 三条，都按**日期**判，不按字符串判：
  /// - `asof` 解不成一天（空、`banana`、`2026-02-30`）的一律不认。字符串比的时候
  ///   这些全都「不等于」手上那份，于是全都会被收下。
  /// - 更老的那一天不认：服务端算不出今天那份时会拿上一份垫着（`sector_history.rs`
  ///   的 `stale()`），老基线配现价算出来的不是「5 日」。
  /// - 同一天只在**覆盖面更大**时才认：采集是增量的，当天晚些时候会补齐几个合约；
  ///   一样多或更少就是同一份，不值得整页重算。
  public func supersedes(_ old: SectorHistory) -> Bool {
    guard !isEmpty, let mine = Self.day(asof) else { return false }
    guard !old.isEmpty, let theirs = Self.day(old.asof) else { return true }
    if mine != theirs { return mine > theirs }
    return closes.count > old.closes.count
  }

  /// 一份新到的快照要不要装进界面。网络和磁盘两条路共用这一道闸。
  ///
  /// 先问新鲜度再问新旧：过期的那份既不能顶掉手上这份，也不能在手上还空着的时候
  /// 顶上来——它配现价算出来的收益挂着「5 日」的名字却不是 5 日。被挡住时
  /// `history` 保持原样（冷启动就是 `.empty`），页面照现有的样子办：`hasEligible`
  /// 问不出东西，「5 日」那颗药丸整行不出现，停在 5 日的人就地退回今日。
  public func accepts(_ next: SectorHistory, now: Date = Date()) -> Bool {
    next.isFresh(now: now) && next.supersedes(self)
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
  /// 成员在**当前窗口**上的收益中位数，百分数。今日是 24h 涨跌幅，5 日是
  /// `100·(现价/5 日前收盘 − 1)`——板块只有中位数这一个口径，换的只是窗口。
  public let pct: Double
  /// 这段窗口上算得出收益的成员数（没行情、这段没收盘的都不参与，也不计数）。
  public let memberCount: Int
  /// 分类表里登记的成员数（按 base 去重后）。`memberCount` 少于它就是有成员没行情。
  public let staticCount: Int
  /// 成员成交额之和。
  public let quoteVolume: Double
  /// 兜底桶（分类表没收录、按交易所标签凑的那几桶）。在板块列表里和普通板块同样对待。
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

  /// 跑赢池基准的家数。`breadth` 就是它除以 `memberCount`，这儿还原回整数给界面用。
  public var outperformCount: Int {
    guard memberCount > 0, breadth.isFinite else { return 0 }
    return Int((breadth * Double(memberCount)).rounded())
  }

  /// `staticCount` 不传就等于 `memberCount`。
  public init(id: String, name: String, market: SectorMarket,
              pct: Double, memberCount: Int, staticCount: Int? = nil,
              quoteVolume: Double, isFallback: Bool,
              breadth: Double = 0, upCount: Int = 0, frontier: [String] = [],
              jackknife: ClosedRange<Double>? = nil) {
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
/// 来回反超就让板块的中位数跟着跳、列表跟着抖。所以先按计价币的固定档次挑，
/// 同一档才比成交额。
public enum SectorQuotePreference {
  /// 计价币优先级，越靠前越优先，表里没有的一律垫底。表本身只有 `QuoteAssets.tradable` 那一份。
  public static func rank(_ quote: String) -> Int { QuoteAssets.rank(quote) }

  /// 新来的这张是不是比手上那张更该留下。
  public static func prefers(rank: Int, volume: Double,
                             over other: (rank: Int, volume: Double)) -> Bool {
    guard rank == other.rank else { return rank < other.rank }
    // 缺失的成交额一律算最低档。NaN 参与 `>` 时两边都是假，于是先到的那张
    // 「没有成交额」的合约永远顶不掉、也永远不被真有成交额的那张顶掉——
    // 挑哪张合约就成了「谁先到」（审查复核项 1）。
    let mine = volume.isFinite ? volume : -.infinity
    let theirs = other.volume.isFinite ? other.volume : -.infinity
    return mine > theirs
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
///
/// 三个窗口共用这一套：外面给定 `window`，里面给每个成员算出**一个收益值**
/// （今日是 24h 涨跌幅，5 日 / 20 日是 `100·(现价/收盘 − 1)`），之后中位数、广度、
/// 领涨、删一全都照着这一个向量算，一行分支都不多。
public enum SectorAggregator {
  /// 有行情成员少于这个数的板块不算一个板块的强弱：列表里照样列出来，但副文案不写
  /// 「x/N 跑赢大盘」，也不拿它判「5 日」那一档有没有东西可看。
  public static let minEligibleMembers = 3

  /// 5 日 / 20 日窗口另加的一条门槛：这一段有收盘的成员，得占到有行情成员的这个比例。
  ///
  /// 服务端的日线是逐个合约采的，新上市的币根本没有 5 根日线。一个 20 个成员的板块
  /// 只剩 4 个算得出 5 日收益时，那 4 个的中位数不是这个板块的 5 日强弱。
  /// 覆盖不够的板块不算数——`hasEligible` 靠它判「5 日」那颗药丸出不出现。
  public static let minWindowCoverage = 0.8

  /// - Parameters:
  ///   - quotes: 以**大写 base** 为键。
  ///   - fallbackBuckets: 兜底桶，聚出来的 `isFallback = true`。
  ///   - window: 看哪一段。缺省是今日，于是老调用方一个字都不用改。
  ///   - history: 日线收盘。`today` 窗口用不着它，取历史失败也只是这一项为空，
  ///     今日那一档照常。
  /// - Returns: 顺序 = 目录顺序在前、兜底桶按传入顺序在后。
  ///            **这一段里一个成员都算不出收益的板块直接不出现**（不是给个 0）。
  public static func stats(market: SectorMarket,
                           quotes: [String: SectorQuote],
                           fallbackBuckets: [SectorFallbackBucket],
                           window: SectorWindow = .today,
                           history: SectorHistory = .empty) -> [SectorStat] {
    // 池基准只算一次：它是整个市场的事，不是某个板块的事。每个窗口各算各的——
    // 5 日的超额收益不能拿 24h 的基准去减。
    let pool = pool(market: market, quotes: quotes, fallbackBuckets: fallbackBuckets,
                    window: window, history: history)
    var out: [SectorStat] = []
    out.reserveCapacity(SectorCatalog.sectors(market).count + fallbackBuckets.count)
    for def in SectorCatalog.sectors(market) {
      if let s = stat(id: def.id, name: def.name, market: market,
                      members: def.members, quotes: quotes, pool: pool, isFallback: false,
                      window: window, history: history) {
        out.append(s)
      }
    }
    for b in fallbackBuckets {
      if let s = stat(id: b.id, name: b.name, market: market,
                      members: b.members, quotes: quotes, pool: pool, isFallback: true,
                      window: window, history: history) {
        out.append(s)
      }
    }
    return out
  }

  /// 这个市场在这段窗口上还有没有板块算得出像样的强弱（成员够、覆盖够）。
  ///
  /// 「5 日」那颗药丸只在有东西可看时才出现：某个市场服务端还没采日线（美股就是），
  /// 或者整段历史断了，那一行药丸就整行不在，页面读起来和只有今日时一模一样。
  /// 这一问不需要池基准、也不需要领涨，所以不走完整的 `stats`。
  public static func hasEligible(market: SectorMarket,
                                 quotes: [String: SectorQuote],
                                 window: SectorWindow,
                                 history: SectorHistory) -> Bool {
    if window.needsHistory && history.isEmpty { return false }
    for def in SectorCatalog.sectors(market) {
      let set = memberSet(members: def.members, quotes: quotes, window: window, history: history)
      if set.returns.count >= minEligibleMembers && covered(set, window: window) { return true }
    }
    return false
  }

  // MARK: - 一个成员、一段窗口、一个收益

  /// 这个成员在这段窗口上的收益，百分数。算不出来就是**没有**，不是 0。
  ///
  /// 5 日 / 20 日拿的是**现价**除以那一天的收盘，所以这两档跟着 ticker 一起动，
  /// 不是一天只变一次的死数。收盘 ≤ 0 或者现价没回来都当没有——`last/0` 是 +∞，
  /// 一个 +∞ 就能把整段中位数和池基准全带走。
  public static func windowReturn(_ quote: SectorQuote, window: SectorWindow,
                                  closes: SectorCloses?) -> Double? {
    switch window {
    case .today:
      return quote.pct.isFinite ? quote.pct : nil
    case .d5, .d20:
      guard let close = closes?.close(window), close.isFinite, close > 0,
            quote.price.isFinite, quote.price > 0 else { return nil }
      return (quote.price / close - 1) * 100
    }
  }

  /// 某个板块在某段窗口上的中位数。覆盖不够（或一个都算不出来）时返回 nil。
  ///
  /// 品种列表头部那句「20 日 +12.1%」要的就是它：20 日不是一个模式，用不着为它
  /// 把整个市场再聚合一遍。
  public static func windowMedian(members: [String], quotes: [String: SectorQuote],
                                  history: SectorHistory, window: SectorWindow) -> Double? {
    let set = memberSet(members: members, quotes: quotes, window: window, history: history)
    guard !set.returns.isEmpty, covered(set, window: window) else { return nil }
    return median(set.returns)
  }

  // MARK: - 市场池

  /// 池 `G` = 该市场所有在这段窗口上算得出收益、按 base 去重的品种
  /// （分类表收录的 + 兜底桶里的）。
  ///
  /// 基准 `b` 取等权均值而不是中位数：中位数会把「全场普涨」这件事本身吃掉一半。
  static func pool(market: SectorMarket,
                   quotes: [String: SectorQuote],
                   fallbackBuckets: [SectorFallbackBucket],
                   window: SectorWindow = .today,
                   history: SectorHistory = .empty) -> SectorPool {
    var seen = Set<String>()
    var returns: [String: Double] = [:]
    func collect(_ members: [String]) {
      for raw in members {
        let base = raw.uppercased()
        guard seen.insert(base).inserted, let q = quotes[base],
              let r = windowReturn(q, window: window, closes: history.closes[base])
        else { continue }
        returns[base] = logReturn(r)
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

  /// 一个板块在一段窗口上的成员集 `S_s^W = 目录成员 ∩ 有行情 ∩ 这段有收盘`。
  struct MemberSet {
    var bases: [String] = []
    /// 和 `bases` 一一对应的窗口收益，百分数。
    var returns: [Double] = []
    /// 有成交额的那几个成员加总起来是多少。一个都没有时是 nil。
    ///
    /// 这儿只留和、不留数组（复核项 5）：缺成交额的成员根本不进来，所以它跟
    /// `bases` / `returns` 既不同序也不等长，留成数组迟早会有人按下标去对齐。
    var volumeSum: Double?
    /// 分类表里登记的成员数（按 base 去重后）。
    var staticCount = 0
    /// 有行情的成员数 `n_s`。5 日 / 20 日的覆盖率就是拿它当分母。
    var quotedCount = 0
  }

  static func memberSet(members: [String], quotes: [String: SectorQuote],
                        window: SectorWindow, history: SectorHistory) -> MemberSet {
    var set = MemberSet()
    var seen = Set<String>()
    set.bases.reserveCapacity(members.count)
    set.returns.reserveCapacity(members.count)
    for raw in members {
      let base = raw.uppercased()
      guard seen.insert(base).inserted else { continue }
      set.staticCount += 1
      guard let q = quotes[base], q.pct.isFinite else { continue }
      set.quotedCount += 1
      guard let r = windowReturn(q, window: window, closes: history.closes[base]) else { continue }
      set.bases.append(base)
      set.returns.append(r)
      // 成交额缺失就不进这个数组：编成 0 等于替交易所宣布「这个成员零成交」，
      // 板块成交额的加总会被它稀释成一个偏小的真数（审查复核项 1）。
      // 一个成员都没有成交额时 `quoteVolume` 是 NaN，界面照缺数显示。
      if q.quoteVolume.isFinite, q.quoteVolume >= 0 {
        set.volumeSum = (set.volumeSum ?? 0) + q.quoteVolume
      }
    }
    return set
  }

  /// 这段窗口上，有收盘的成员够不够多。今日窗口不设这条（成员集就是有行情的那些）。
  static func covered(_ set: MemberSet, window: SectorWindow) -> Bool {
    guard window.needsHistory else { return true }
    return Double(set.returns.count) >= minWindowCoverage * Double(set.quotedCount)
  }

  /// 单个桶的聚合。成员按 base 去重，这段窗口算不出收益的跳过（但仍计进 `staticCount`）。
  private static func stat(id: String, name: String, market: SectorMarket,
                           members: [String], quotes: [String: SectorQuote],
                           pool: SectorPool, isFallback: Bool,
                           window: SectorWindow, history: SectorHistory) -> SectorStat? {
    let set = memberSet(members: members, quotes: quotes, window: window, history: history)
    let rets = set.returns
    guard !rets.isEmpty else { return nil }

    var outperform = 0
    var up = 0
    var frontier: [(base: String, excess: Double)] = []
    for (index, base) in set.bases.enumerated() {
      if rets[index] > 0 { up += 1 }
      guard let e = pool.excess[base], e > 0 else { continue }
      outperform += 1
      if e >= pool.frontierCut { frontier.append((base, e)) }
    }
    // 并列按代号排，免得两次刷新之间换位。
    frontier.sort { $0.excess == $1.excess ? $0.base < $1.base : $0.excess > $1.excess }

    return SectorStat(id: id, name: name, market: market,
                      pct: median(rets),
                      memberCount: rets.count, staticCount: set.staticCount,
                      quoteVolume: set.volumeSum ?? .nan,
                      isFallback: isFallback,
                      breadth: Double(outperform) / Double(rets.count),
                      upCount: up, frontier: frontier.map(\.base),
                      jackknife: jackknife(rets))
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
