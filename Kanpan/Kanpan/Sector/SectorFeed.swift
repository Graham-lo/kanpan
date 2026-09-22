import Foundation
import KanpanCore
import KanpanNetwork

/// 板块页的取数。
///
/// 这一页要的东西和别的页不一样：它一次要**全市场**的 24h 涨跌幅和成交额，
/// 五百多个品种，少一个板块的中位数就偏一点。逐个 `ticker/24hr` 取五百次不现实，
/// 所以走 `/fapi/v1/ticker/24hr` 的全量那一版——一趟 285 KB 左右，权重 40。
///
/// 只取 `VenueRegistry.sectorVenue` 那一家：板块分类表是按它的品种表做的，
/// 别家的品种不进板块。全量 ticker 在网关上怎么走由那一家的提供者自己决定
/// （网关只代理带 symbol 的单品种请求，全量那条提供者会自己回退成直连）。
///
/// 节奏：进页立刻取一趟，之后**页面可见且 app 在前台**时每 10 秒一趟。板块的聚合值
/// 是几十个成员的中位数，不需要秒级刷新；页面一离开就停，不在后台烧流量。
/// 取数失败就退避重试（2→4→8…最多 30 秒），**界面上不显示任何取数状态**
/// （`kanpan-no-engineering-status-fields`）。
///
/// 手里那份行情**有寿命**（审查 A-04）。原来它只增不减：换线路之后仍旧拿上一家
/// 报的数算板块；连着取不到时整页就那么定在一分钟前、十分钟前、一小时前的数字上，
/// 而球、药丸、统计行看上去和实时的一模一样。现在两种情形都会把它清空：
/// * 换线路 / 换镜像（`configure`）——那是换了一家交易所，一条都不能留；
/// * 连着 `failuresBeforeDropping` 趟取不到、且手里这份已经超过 `dropAfterSeconds`
///   （`noteFailure`）。
/// 清空之后页面是空的，`SectorPage` 那层给一句「暂无行情」和「点此重试」，
/// 没有第二句话、也不说是为什么。
@MainActor @Observable final class SectorFeed {
  /// 大写 base → 行情。板块聚合只认 base（分类表里记的就是代号）。
  private(set) var quotes: [String: SectorQuote] = [:]
  /// 最近一次成功取回的时刻。只给内部判新旧用，**不要画到界面上**。
  private(set) var lastUpdate: Date?

  /// 这条线路上**问过**一趟了吗（成功或失败都算）。
  ///
  /// 只给空态判「还没取回来」用（复核项 2）：从前空态的判据只有「手里没行情」，
  /// 于是首屏那一两百毫秒里「暂无行情 / 点此重试」会先闪一下再被球场顶掉。
  /// 换线路会把它清回 false——换了一家交易所，之前问过什么都不作数。
  private(set) var attempted = false

  private var resolver = RouteResolver(policy: .direct, endpoints: .default)
  private var rest: any MarketProvider = RouteResolver(policy: .direct, endpoints: .default)
    .provider(venue: VenueRegistry.sectorVenue.id)
  private var catalog: [SymbolInfo] = []

  private var visible = false
  private var foreground = true
  private var job: Task<Void, Never>?

  /// 两趟之间隔多久。板块是聚合值，10 秒足够；权重 40 的请求一分钟六趟，
  /// 离交易所的配额差着两个数量级（`kanpan-user-scale-is-tiny`）。
  private static let refreshSeconds: Double = 10
  /// 失败之后的退避上限。
  private static let maxBackoffSeconds: Double = 30
  /// 连着几趟取不到才考虑丢掉手里那份行情。一趟超时就清屏太急——退避是 2→4→8 秒，
  /// 三趟之后基本可以断定不是一次抖动。
  static let failuresBeforeDropping = 3
  /// 手里那份行情最多能顶多久。板块是 10 秒一趟的聚合值，超过一分钟没换过
  /// 就不该再摆出实时的样子了。
  static let dropAfterSeconds: Double = 60

  // MARK: 外部接线

  /// 换线路/换镜像。口径和 `QuoteBook.configure` 一致，由 `MainScreen` 一起调。
  func configure(endpoints: MarketEndpoints, policy: MarketRoutePolicy) {
    guard endpoints != resolver.endpoints || policy != resolver.policy else { return }
    resolver = RouteResolver(policy: policy, endpoints: endpoints)
    rest = resolver.provider(venue: VenueRegistry.sectorVenue.id)
    // 手里这份是上一条线路报的，换了就一条都不留（审查 A-04）。两家的 24h 口径
    // 和品种集合都不一样，混着算出来的中位数不属于任何一个市场。
    drop()
    // 新线路还一趟都没问过：这会儿是在加载，不是「暂无行情」。
    attempted = false
    failures = 0
    restart()
  }

  /// 空态上那一下「点此重试」。不等退避，立刻重开一轮。
  ///
  /// 重开之前先把**线路冷却**清掉（审查复核项 2）。上一轮失败会给这条线路记一段
  /// 冷却时间，不清掉的话「点此重试」只是让循环立刻再问一次、然后被冷却挡回来，
  /// 用户按了等于没按。清的只是冷却，不动封禁——真被交易所封的线路照旧不走。
  func retry() {
    let rest = self.rest
    let reset = self.resetCooldowns
    // 清冷却和重开必须在**同一条**任务里按顺序来（复核项 1）。分成两个 Task
    // 的话「先清再取」只是概率成立：轮询那一趟可能抢在 reset 之前发出去，
    // 照样被冷却挡回来，用户按了还是等于没按。
    restart(preflight: { await reset(rest) })
  }

  /// 清线路冷却走哪条路。默认就是当前线路的提供者；用例把它换掉，
  /// 好证明它确实排在第一趟取数前面（和 `fetchTickers` 同一种接法）。
  @ObservationIgnored var resetCooldowns: @Sendable (any MarketProvider) async -> Void
    = { await $0.resetRouteCooldowns() }

  /// 把手里那份行情丢掉。清完页面就是空的，`SectorPage` 会显示空态。
  private func drop() {
    guard !quotes.isEmpty || lastUpdate != nil else { return }
    quotes = [:]
    lastUpdate = nil
  }

  // MARK: 失败记账
  //
  // 循环里那几行判定本身没法在用例里守（要等真实的退避时间），所以规则做成纯函数 +
  // 两个可以直接叫的记账方法。

  @ObservationIgnored private var failures = 0

  /// 连着失败到这个程度、手里那份又已经这么旧了，就该丢掉。
  ///
  /// 从来没成功过（`age == nil`）时不必等寿命：本来也没有什么可丢的，
  /// 这一条只是让「第一次进页就取不到」也走同一条路。
  static func shouldDrop(failures: Int, age: TimeInterval?) -> Bool {
    guard failures >= failuresBeforeDropping else { return false }
    guard let age else { return true }
    return age >= dropAfterSeconds
  }

  /// 屏幕中间那句「暂无行情 / 点此重试」现在该不该出现。
  ///
  /// 「还没问回来」和「问过了但没有」是两件事，只有后者才是空态。首屏那一趟
  /// 还在路上时整块留白——不写「加载中」，那是工程状态
  /// （`kanpan-no-engineering-status-fields`）。
  static func showsEmptyState(hasQuotes: Bool, attempted: Bool) -> Bool {
    !hasQuotes && attempted
  }

  /// 同一条规则，页面直接问这一个。
  var showsEmptyState: Bool {
    Self.showsEmptyState(hasQuotes: !quotes.isEmpty, attempted: attempted)
  }

  /// 取到了。
  func noteSuccess() {
    failures = 0
    attempted = true
  }

  /// 取不到。够旧够久就把屏上那份清掉。
  func noteFailure(now: Date = Date()) {
    failures += 1
    attempted = true
    let age = lastUpdate.map { now.timeIntervalSince($0) }
    if Self.shouldDrop(failures: failures, age: age) { drop() }
  }

  /// 后端网关名单，顺序就是 `MarketStatsClient` 问供应量 / 持仓量时试的那个顺序。
  ///
  /// 「5 日」那一档的日线收盘（`SectorHistoryFeed`）问的是同样这几台。板块页手里
  /// 已经有这个 feed，不必为一条只读接口再从 `MainScreen` 另牵一根线下来。
  var backendHosts: [String] { resolver.endpoints.gateways }

  /// 品种表。用来把 `BTCUSDT` 还原成 `BTC`，以及给没被任何板块收录的币凑兜底桶。
  ///
  /// 比的是 symbol 集合的内容，不是条数：一张合约下架、另一张同时上架时条数一模一样，
  /// 只比数量会让整页一直拿着旧表算兜底桶。
  func setCatalog(_ catalog: [SymbolInfo]) {
    let ids = Set(catalog.map { InstrumentID.canonical($0.symbol) })
    guard ids != catalogIDs else { return }
    catalogIDs = ids
    self.catalog = catalog
    // 两张派生表按代次作废——条数相同、内容不同的那一版正是它们会看走眼的地方。
    catalogGeneration &+= 1
  }

  /// 品种表换了几版。派生缓存拿它当钥匙。
  @ObservationIgnored private var catalogGeneration: UInt64 = 0
  @ObservationIgnored private var catalogIDs: Set<String> = []

  /// 板块页在不在屏幕上。
  func setVisible(_ on: Bool) {
    guard on != visible else { return }
    visible = on
    restart()
  }

  /// app 在不在前台。
  func setForeground(_ on: Bool) {
    guard on != foreground else { return }
    foreground = on
    restart()
  }

  // MARK: 轮询

  private var running: Bool { visible && foreground }

  /// - Parameter preflight: 轮询开始之前先做完的事（「点此重试」要先清线路冷却）。
  ///   和循环在同一条任务里，顺序是确定的。
  private func restart(preflight: (@Sendable () async -> Void)? = nil) {
    job?.cancel()
    job = nil
    guard running else { return }
    job = Task { [weak self] in
      await preflight?()
      guard !Task.isCancelled else { return }
      await self?.loop()
    }
  }

  private func loop() async {
    var backoff = 2.0
    while !Task.isCancelled {
      let ok = await pull()
      if ok {
        noteSuccess()
        backoff = 2
        try? await Task.sleep(for: .seconds(Self.refreshSeconds))
      } else {
        noteFailure()
        try? await Task.sleep(for: .seconds(backoff))
        backoff = min(Self.maxBackoffSeconds, backoff * 2)
      }
    }
  }

  /// 全市场 24h 行情从哪儿来。默认走当前线路的提供者；用例把它换成离线的
  /// 假数据——这一路要守的规则全是「取不到时屏上留什么」，不换掉就只能靠真网络。
  @ObservationIgnored var fetchTickers: @Sendable (any MarketProvider) async throws -> [Ticker]
    = { try await $0.tickers24h(timeout: 8) }

  private func pull() async -> Bool {
    let rest = self.rest
    guard let tickers = try? await fetchTickers(rest), !tickers.isEmpty else { return false }
    ingest(tickers)
    return true
  }

  private func ingest(_ tickers: [Ticker]) {
    var next: [String: SectorQuote] = [:]
    // base → 已选中那张的（计价币档次，成交额）。
    var picked: [String: (rank: Int, volume: Double)] = [:]
    next.reserveCapacity(tickers.count)
    picked.reserveCapacity(tickers.count)
    for ticker in tickers {
      guard ticker.changePercent.isFinite, ticker.last.isFinite else { continue }
      let base = base(of: ticker.symbol)
      guard !base.isEmpty else { continue }
      // 同一个 base 可能有多张合约（USDT / USDC / FDUSD）。先按计价币的固定优先级挑，
      // 同一档才比成交额——USDT 和 USDC 两张的 24h 涨幅并不相同，按成交额挑会在
      // 两张之间来回切，球就一直在抖。
      // 成交额拿不到就是**没有**，不是 0（审查复核项 1）：编成 0 之后这个成员会
      // 带着一个假的「零成交」进板块成交额的加总、也会在「成交额」那档排序里
      // 冒充一个真实的最小值，而列表上那条「—」分支永远走不到。NaN 原样留着，
      // 用到它的地方各自把它当缺数处理（挑合约、加总、排序都已经过滤非有限值）。
      let volume = ticker.quoteVolume
      let rank = quoteRank(of: ticker.symbol)
      if let old = picked[base],
         !SectorQuotePreference.prefers(rank: rank, volume: volume, over: old) { continue }
      picked[base] = (rank, volume)
      next[base] = SectorQuote(base: base, pct: ticker.changePercent, quoteVolume: volume, price: ticker.last)
    }
    quotes = next
    lastUpdate = Date()
  }

  /// `BTCUSDT` → `BTC`。品种表里有就照表，没有就削掉计价币的后缀
  /// （交易所偶尔会在品种表回来之前先给出行情）。
  private func base(of symbol: String) -> String {
    let upper = InstrumentID.canonical(symbol)
    if let info = catalogIndex[upper] { return info.base.uppercased() }
    return SymbolInfo.placeholder(symbol: symbol).base
  }

  /// 计价币的档次，越小越优先：`USDT > USDC > FDUSD > 其它`。品种表里有就照表，
  /// 没有就按后缀猜（交易所偶尔会在品种表回来之前先给出行情）。
  private func quoteRank(of symbol: String) -> Int {
    let upper = InstrumentID.canonical(symbol)
    if let info = catalogIndex[upper] { return SectorQuotePreference.rank(info.quote) }
    for (index, quote) in Self.quoteAssets.enumerated()
    where upper.hasSuffix(quote) && upper.count > quote.count {
      return index
    }
    return Self.quoteAssets.count
  }

  private static let quoteAssets = SectorQuotePreference.quoteAssets

  /// 这个 base 对应品种的价格小数位。品种表里没有就 `nil`——列表那一层会退回
  /// 按大小猜，但绝不在这儿编一个位数出来（审查 B-07）。
  func priceDecimals(forBase base: String) -> Int? {
    catalogIndex[symbol(forBase: base)]?.priceDecimals
  }

  private var catalogIndex: [String: SymbolInfo] {
    if cachedIndexCount == catalogGeneration { return cachedIndex }
    var index: [String: SymbolInfo] = [:]
    index.reserveCapacity(catalog.count)
    for info in catalog { index[InstrumentID.canonical(info.symbol)] = info }
    cachedIndex = index
    cachedIndexCount = catalogGeneration
    return index
  }
  @ObservationIgnored private var cachedIndex: [String: SymbolInfo] = [:]
  @ObservationIgnored private var cachedIndexCount: UInt64? = nil

  /// 大写 base → 完整合约代号（`BTC` → `BTCUSDT`）。
  ///
  /// 板块这一路从头到尾只认 base——分类表里记的就是代号，聚合、选取、画球都不需要
  /// 知道它是拿什么计价的。但点进品种列表再点一行是要开行情页的，那儿要的是全名。
  /// 直接拼 `base + "USDT"` 在绝大多数上成立，可币安有一小撮只有 USDC 本位的合约
  /// （分类表里也收了），拼出来的代号在品种表里根本不存在，点下去就是一张空图。
  /// 所以照表查：同一个 base 有多条时按 `quoteAssets` 的顺序取偏好最高的那条。
  func symbol(forBase base: String) -> String {
    let upper = base.uppercased()
    if let hit = baseIndex[upper] { return hit }
    return upper + "USDT"
  }

  private var baseIndex: [String: String] {
    if cachedBaseCount == catalogGeneration { return cachedBase }
    var rank: [String: Int] = [:]
    var index: [String: String] = [:]
    for info in catalog {
      let base = info.base.uppercased()
      let quote = info.quote.uppercased()
      let score = SectorQuotePreference.rank(quote)
      if let old = rank[base], old <= score { continue }
      rank[base] = score
      index[base] = InstrumentID.canonical(info.symbol)
    }
    cachedBase = index
    cachedBaseCount = catalogGeneration
    return index
  }
  @ObservationIgnored private var cachedBase: [String: String] = [:]
  @ObservationIgnored private var cachedBaseCount: UInt64? = nil

  // MARK: 兜底桶

  /// 没被分类表收录的品种，按交易所自带的标签凑成的几个桶。
  ///
  /// 加密那份分类表里有 48 个币标的是 `NONE`——不是漏了，是它们确实不属于任何一个
  /// 我们定义的板块。这些币走交易所自己的 `underlyingSubTypes` 兜底，只出现在
  /// 「全部板块」那张整页列表里，**不参与气泡场的排名和归一**，而且在那张列表里
  /// 画得和普通板块一模一样（不去饱和、不加标记、不另起一组）。
  ///
  /// 桶的 id 和数量不是随手定的，得和记号表对上：`SectorIcons` 里除了 34 个真板块，
  /// 另有 `tag-infrastructure` / `tag-alpha` / `tag-defi` / `misc` 四枚，就是给这儿用的
  /// （原型定稿那一版也正好是这四个桶、49 个成员）。所以这儿**不能**按标签有几种就分几个桶
  /// ——那样会冒出一串 id 对不上、没有记号的小桶，在「全部板块」里就是一片空洞。
  ///
  /// 分桶是**划分**不是打标签：一个币只落一个桶，按 `tagOrder` 的先后认领，
  /// 一个都不认的落 `misc`。美股那一路分类表本来就只收「AI 产业链」那几十只
  /// （`kanpan-us-equity-data-is-binance-only`），剩下的一律进 `misc`，
  /// 免得它们从「全部板块」里凭空消失。
  func fallbackBuckets(for market: SectorMarket) -> [SectorFallbackBucket] {
    let covered = Set(SectorCatalog.sectors(market).flatMap(\.members))
    var buckets: [String: [String]] = [:]
    // 同一个 base 可能挂着好几张合约（USDT 本位 + USDC 本位），标签还未必一样。
    // 认第一张，免得同一个币同时出现在两个桶里。
    var seen = Set<String>()
    for info in catalog {
      guard MarketSector.market(info) == market.rawValue else { continue }
      let base = info.base.uppercased()
      guard !covered.contains(base), seen.insert(base).inserted else { continue }
      let tags = Set(MarketSector.tags(info))
      let key = Self.tagOrder.first { tags.contains($0) }.map { "tag-" + $0 } ?? "misc"
      buckets[key, default: []].append(base)
    }
    return Self.bucketOrder.compactMap { key in
      guard let members = buckets[key], !members.isEmpty else { return nil }
      return SectorFallbackBucket(id: key, name: Self.bucketNames[key] ?? key,
                                  members: members.sorted())
    }
  }

  /// 认领顺序。和 `bucketOrder` 一致，只是少了兜底的 `misc`。
  private static let tagOrder = ["infrastructure", "alpha", "defi"]
  /// 出现在「全部板块」里的先后，和 `SectorIcons` 里那四枚记号的顺序一致。
  private static let bucketOrder = ["tag-infrastructure", "tag-alpha", "tag-defi", "misc"]
  /// 桶名照原型定稿。`MarketSector.title` 给的是「基础设施 / Alpha / DeFi」，
  /// 但这一页要说清楚它们是**兜底**，所以 Alpha 带上「币安」、DeFi 带上「其他」。
  private static let bucketNames = ["tag-infrastructure": "基础设施", "tag-alpha": "币安 Alpha",
                                    "tag-defi": "DeFi 其他", "misc": "其他"]
}
