import Foundation
import KanpanCore
import KanpanNetwork

/// 板块页的取数。
///
/// 这一页要的东西和别的页不一样：它一次要**全市场**的 24h 涨跌幅和成交额，
/// 五百多个品种，少一个板块的中位数就偏一点。逐个 `ticker/24hr` 取五百次不现实，
/// 所以走 `/fapi/v1/ticker/24hr` 的全量那一版——一趟 285 KB 左右，权重 40。
///
/// 全量 ticker **只有直连这条路**：网关只代理带 symbol 的单品种请求
/// （`MarketSource.gatewayPlan` 里那句「全市场 ticker 没有 symbol，网关只代理单品种」），
/// 所以 `BinanceREST.upstream` 拿到这条请求时会自动回退成直连。走网关那档的用户
/// 在这一页上仍旧是直连取数，这是现状，不在这一轮的范围里。
///
/// 节奏：进页立刻取一趟，之后**页面可见且 app 在前台**时每 10 秒一趟。板块的聚合值
/// 是几十个成员的中位数，不需要秒级刷新；页面一离开就停，不在后台烧流量。
/// 取数失败就退避重试（2→4→8…最多 30 秒），**界面上不显示任何取数状态**
/// （`kanpan-no-engineering-status-fields`）。
@MainActor @Observable final class SectorFeed {
  /// 大写 base → 行情。板块聚合只认 base（分类表里记的就是代号）。
  private(set) var quotes: [String: SectorQuote] = [:]
  /// 最近一次成功取回的时刻。只给内部判新旧用，**不要画到界面上**。
  private(set) var lastUpdate: Date?

  private var rest = BinanceREST.upstream(.binance, hosts: .default)
  private var hosts: BinanceHosts = .default
  private var source: MarketSource = .binance
  private var catalog: [SymbolInfo] = []

  private var visible = false
  private var foreground = true
  private var job: Task<Void, Never>?

  /// 两趟之间隔多久。板块是聚合值，10 秒足够；权重 40 的请求一分钟六趟，
  /// 离交易所的配额差着两个数量级（`kanpan-user-scale-is-tiny`）。
  private static let refreshSeconds: Double = 10
  /// 失败之后的退避上限。
  private static let maxBackoffSeconds: Double = 30

  // MARK: 外部接线

  /// 换线路/换镜像。口径和 `QuoteBook.configure` 一致，由 `MainScreen` 一起调。
  func configure(hosts: BinanceHosts, source: MarketSource) {
    guard hosts != self.hosts || source != self.source else { return }
    self.hosts = hosts
    self.source = source
    rest = BinanceREST.upstream(source, hosts: hosts)
    restart()
  }

  /// 品种表。用来把 `BTCUSDT` 还原成 `BTC`，以及给没被任何板块收录的币凑兜底桶。
  func setCatalog(_ catalog: [SymbolInfo]) {
    guard catalog.count != self.catalog.count else { return }
    self.catalog = catalog
  }

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

  private func restart() {
    job?.cancel()
    job = nil
    guard running else { return }
    job = Task { [weak self] in await self?.loop() }
  }

  private func loop() async {
    var backoff = 2.0
    while !Task.isCancelled {
      let ok = await pull()
      if ok {
        backoff = 2
        try? await Task.sleep(for: .seconds(Self.refreshSeconds))
      } else {
        try? await Task.sleep(for: .seconds(backoff))
        backoff = min(Self.maxBackoffSeconds, backoff * 2)
      }
    }
  }

  private func pull() async -> Bool {
    let rest = self.rest
    guard let tickers = try? await rest.tickers24h(timeout: 8), !tickers.isEmpty else { return false }
    ingest(tickers)
    return true
  }

  private func ingest(_ tickers: [Ticker]) {
    var next: [String: SectorQuote] = [:]
    next.reserveCapacity(tickers.count)
    for ticker in tickers {
      guard ticker.changePercent.isFinite, ticker.last.isFinite else { continue }
      let base = base(of: ticker.symbol)
      guard !base.isEmpty else { continue }
      // 同一个 base 可能有多个计价对（USDT / USDC）。留成交额大的那一个，
      // 别让一条清淡的 USDC 盘把整个板块的中位数带偏。
      let volume = ticker.quoteVolume.isFinite ? ticker.quoteVolume : 0
      if let old = next[base], old.quoteVolume >= volume { continue }
      next[base] = SectorQuote(base: base, pct: ticker.changePercent, quoteVolume: volume, price: ticker.last)
    }
    quotes = next
    lastUpdate = Date()
  }

  /// `BTCUSDT` → `BTC`。品种表里有就照表，没有就削掉计价币的后缀
  /// （交易所偶尔会在品种表回来之前先给出行情）。
  private func base(of symbol: String) -> String {
    let upper = symbol.uppercased()
    if let info = catalogIndex[upper] { return info.base.uppercased() }
    for quote in Self.quoteAssets where upper.hasSuffix(quote) && upper.count > quote.count {
      return String(upper.dropLast(quote.count))
    }
    return upper
  }

  private static let quoteAssets = ["USDT", "USDC", "FDUSD", "BUSD", "USD1", "TUSD"]

  private var catalogIndex: [String: SymbolInfo] {
    if cachedIndexCount == catalog.count { return cachedIndex }
    var index: [String: SymbolInfo] = [:]
    index.reserveCapacity(catalog.count)
    for info in catalog { index[info.symbol.uppercased()] = info }
    cachedIndex = index
    cachedIndexCount = catalog.count
    return index
  }
  @ObservationIgnored private var cachedIndex: [String: SymbolInfo] = [:]
  @ObservationIgnored private var cachedIndexCount = -1

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
    if cachedBaseCount == catalog.count { return cachedBase }
    var rank: [String: Int] = [:]
    var index: [String: String] = [:]
    for info in catalog {
      let base = info.base.uppercased()
      let quote = info.quote.uppercased()
      let score = Self.quoteAssets.firstIndex(of: quote) ?? Self.quoteAssets.count
      if let old = rank[base], old <= score { continue }
      rank[base] = score
      index[base] = info.symbol.uppercased()
    }
    cachedBase = index
    cachedBaseCount = catalog.count
    return index
  }
  @ObservationIgnored private var cachedBase: [String: String] = [:]
  @ObservationIgnored private var cachedBaseCount = -1

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
