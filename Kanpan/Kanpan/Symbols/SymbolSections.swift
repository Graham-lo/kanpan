import Foundation
import KanpanCore

// ============================================================ 分区与行
//
// §9.3 品种整页：搜索框 → 自选 → 最近 → 全部（按 24h 成交额降序）。
// 每行：名 · 最新价 · 涨跌幅。
//
// 常数、文案、分组规矩全部照原型 `app.js/renderSymbols()`：
//   · 无查询时三组；有查询时只剩一组「搜到 N 个」，不再分组。
//   · 「全部」里剔掉已经在上面两组露过脸的品种（原型是 `!have.has(sym)`）。
//   · 全部 120 条封顶、搜索 160 条封顶，超出的用一行小字交代。

/// 一行要显示的东西。纯值，好断言。
struct SymbolRow: Sendable, Equatable, Identifiable {
  var match: SymbolMatch
  var ticker: Ticker?
  /// 这个代号在品种目录里是什么情况（审查复核项 4）。
  ///
  /// `nil` 是常态：这一行本来就是从目录里挑出来的，那就按它自己那一档状态算。
  /// 只有「目录里查不到这个代号」时上层才会给一个明确的 `.unknown` / `.unloaded`——
  /// 那种行是拿 `SymbolInfo.placeholder` 凑出来的，`info.status` 说明不了任何事。
  var listing: SymbolListing?

  var id: String { match.info.symbol }
  var info: SymbolInfo { match.info }
  /// 这一行的目录状态，`listing` 没给就按目录里那一档算。
  var catalogListing: SymbolListing { listing ?? .listed(info.status) }

  /// 行首大字：`BTC`。
  var name: String { info.base }
  /// 大字后面那半截灰的：` / USDT`。
  var quoteSuffix: String { " / " + info.quote }
  /// 第二行小字。原型这行放的是「内嵌了哪些周期」，属于原型特有；
  /// 真 app 里放合约全称，和顶栏「BTCUSDT 永续 ▾」对上。
  var meta: String { info.id.symbol + " " + info.id.productLabel }

  /// 最新价。没有行情时原型给一个破折号 `—`。
  ///
  /// 小数位按 `SymbolInfo.priceDecimals`（最小报价步长），与头部、图表一致。
  var priceText: String {
    guard let t = ticker, t.last.isFinite else { return "—" }
    // `fmtPrice` 而不是 `fmtNum`：0.0000004 这种合法极小价按通常位数
    // 四舍五入会变成 `0.00`，那是在说「这个东西不值钱」（审查 B-07）。
    // 占位行没有精度可言（目录里查不到），`displayDecimals` 会按这口价自己猜。
    // 千分位（UI 审查 2026-09-24 §2.6：搜索页与品种整页的价格原来没有，自选页有）。
    return grouped(fmtPrice(t.last, decimals: info.displayDecimals(for: t.last)))
  }

  /// 这一行还有没有实时价可言。没有的时候界面按「旧值」渲染（灰掉），
  /// 而**由它算出来的**那些字段一律留空——涨跌幅就是第一个（审查 B-06）。
  ///
  /// 判据只有一个：`SymbolListing`——目录里有它就是那一档 `SymbolInfo.status`，
  /// 目录里没有它就是「未知」（同样没有实时价，但不划掉、不删、也不算下架）。
  /// 自选、搜索、图表三处都问这一个，所以同一个品种在三处的说法必然一致。
  var isStale: Bool { !catalogListing.hasLivePrice }

  /// 涨跌幅：`+1.23%` / `−1.23%`，两位小数，全 app 唯一那把 `changePercentText`（审查 U9）。
  /// 没有报价或日开盘基准时留空，不把缺失值写成0%或nan%。
  var changeText: String {
    guard !isStale, let p = ticker?.changePercent, p.isFinite else { return "—" }
    return changePercentText(p)
  }

  /// 原型 `pct >= 0 ? 'up' : 'down'`——平盘算涨。
  var isUp: Bool { (ticker?.changePercent ?? 0) >= 0 }

  /// 24h 成交额，「全部」分区的排序键。
  var quoteVolume: Double {
    // A real trade may arrive before 24h statistics. Unknown volume must sort
    // with missing values; NaN would violate the comparator's ordering contract.
    guard let value = ticker?.quoteVolume, value.isFinite, value >= 0 else { return 0 }
    return value
  }
}

/// 一个分区。
struct SymbolSection: Sendable, Equatable, Identifiable {
  enum Kind: String, Sendable { case search, favorites, recents, all }

  var kind: Kind
  var title: String
  var rows: [SymbolRow]
  /// 没列出来的还剩几个（> 0 时行尾补一行小字）。
  var more: Int = 0

  var id: String { kind.rawValue }

  /// 原型：`'还有 ' + more + ' 个，搜名字更快。'`
  var moreNote: String? { more > 0 ? "还有 \(more) 个，搜名字更快。" : nil }
}

enum SymbolSections {
  /// 「全部」最多列几条（原型 `rows.slice(0, 120)`）。
  static let allLimit = 120
  /// 搜索结果最多列几条（原型 `rows.slice(0, 160)`）。
  static let searchLimit = 160

  /// 分区标题，逐字照原型。
  static let favoritesTitle = "自选"
  static let recentsTitle = "最近"
  static let allTitle = "全部合约"
  /// 空结果那一行（§10.5「空结果一行『没有这个品种』，不放插画」）。
  static let emptyText = "没有这个品种"

  /// 页头右边那行小字：原型 `D.catalog.length + ' 个永续合约'`。
  ///
  /// 数的是**还在交易的**那些。停牌和还没开盘的行现在也留在表里（审查 B-06），
  /// 把它们一起数进去，这行小字就会比「全部合约」里真能点的条数多出一百多个。
  static func countText(_ catalog: [SymbolInfo]) -> String {
    let live = catalog.filter { $0.status.hasLivePrice }
    let spot = live.count { $0.id.market == "spot" }
    let perps = "\(live.count - spot) 个永续合约"
    return spot == 0 ? perps : perps + " · \(spot) 个现货"
  }

  /// 搭出整页的分区。
  ///
  /// - Parameters:
  ///   - catalog: 品种表（`exchangeInfo` 过滤后的 USDT 永续），顺序即交易所给的顺序。
  ///   - tickers: symbol → 24h 行情，缺的行就显示 `—`。
  ///   - prefs: 自选与最近。
  ///   - query: 搜索框里的原文，空串表示没搜。
  ///   - catalogKeys: **没被市场/板块药丸筛过**的那份目录里有哪些代号（大写）。
  ///     `nil` 表示就按 `catalog` 算。这一份只用来回答一件事：一个自选
  ///     「是被药丸筛掉了」还是「目录里根本没有它」（审查复核项 4）——
  ///     前者照旧不列，后者要按「未知」列出来。
  static func build(catalog: [SymbolInfo],
                    tickers: [String: Ticker],
                    prefs: SymbolPrefs,
                    query: String,
                    catalogKeys: Set<String>? = nil) -> [SymbolSection] {
    let bySymbol = Dictionary(catalog.map { (InstrumentID.canonical($0.symbol), $0) }, uniquingKeysWith: { a, _ in a })
    func row(_ m: SymbolMatch) -> SymbolRow { SymbolRow(match: m, ticker: tickers[InstrumentID.canonical(m.info.symbol)]) }

    // ---- 搜索态：只有一组，不分自选 / 最近 / 全部（同原型）
    let q = SymbolQuery.normalize(query)
    if !q.isEmpty {
      // 先最匹配，再按 24h 成交额降序（用户 2026-09-18 定的）。`SymbolQuery.match`
      // 已经按档排好、同档里保着交易所原序，这儿只在同档内改用成交额，
      // 成交额也一样（含都没有行情的）时回落到那个原序，排序仍然稳定。
      let hits = SymbolQuery.match(catalog, query: q).map(row)
        .enumerated()
        .sorted { a, b in
          if a.element.match.tier != b.element.match.tier { return a.element.match.tier < b.element.match.tier }
          // 已停牌 / 还没开盘的排在同档的后面，但**照旧列出来**：用户要能搜到自己
          // 那个已下架的自选，不然「找不到」和「不存在」又成了同一件事（审查 B-06）。
          if a.element.isStale != b.element.isStale { return b.element.isStale }
          if a.element.quoteVolume != b.element.quoteVolume { return a.element.quoteVolume > b.element.quoteVolume }
          return a.offset < b.offset
        }
        .map(\.element)
      let shown = Array(hits.prefix(searchLimit))
      return [SymbolSection(kind: .search,
                            title: "搜到 \(hits.count) 个",
                            rows: shown,
                            more: max(0, hits.count - searchLimit))]
    }

    // ---- 常态：自选 → 最近 → 全部
    var out: [SymbolSection] = []
    var shownAlready = Set<String>()

    // 目录里查不到的自选 / 最近**照旧摆出来**（审查复核项 4）。原来这儿是
    // `compactMap { bySymbol[$0] }`：目录里没有这个代号，那一行就凭空消失了——
    // 用户只会以为是自己手滑删的。现在按代号凑一行占位，标成「未知」：
    // 价还是最后看到的那口（灰的），由实时价算出来的全留空，一个字的解释都不加。
    // 目录还没到的时候不算「未知」（`.unloaded`），那会把整页自选一起打灰。
    let known = catalogKeys ?? Set(bySymbol.keys)
    let loaded = !known.isEmpty
    /// `nil` = 这一行不该出现在这一页（被药丸筛掉了）。
    func rowForKey(_ key: String) -> SymbolRow? {
      let id = InstrumentID.canonical(key)
      if let info = bySymbol[id] { return row(SymbolMatch(info: info)) }
      // 目录里有它、只是不属于当前这颗药丸：照旧不列，药丸就是这么用的。
      if known.contains(id) { return nil }
      return SymbolRow(match: SymbolMatch(info: .placeholder(symbol: id)),
                       ticker: tickers[id],
                       listing: loaded ? .unknown : .unloaded)
    }

    let favorites = prefs.favorites.map { InstrumentID.canonical($0) }.compactMap(rowForKey)
    if !favorites.isEmpty {
      shownAlready.formUnion(favorites.map { InstrumentID.canonical($0.info.symbol) })
      out.append(SymbolSection(kind: .favorites, title: favoritesTitle, rows: favorites))
    }

    // 原型：中间那组剔掉已经在自选里的（`filter(s => !S.watch.includes(s))`）。
    let recents = prefs.recents.map { InstrumentID.canonical($0) }
      .filter { !shownAlready.contains($0) }
      .compactMap(rowForKey)
    if !recents.isEmpty {
      shownAlready.formUnion(recents.map { InstrumentID.canonical($0.info.symbol) })
      out.append(SymbolSection(kind: .recents, title: recentsTitle, rows: recents))
    }

    // 「全部」：剔掉上面露过脸的，按 24h 成交额降序（A5.7）。
    // 没有行情的品种成交额算 0，落在末尾，同额时保持交易所给的原序。
    // 「全部合约」列的是**还能交易的**合约：停牌、已交割、还没开盘的行留在品种表里
    // 是为了自选和搜索认得它（审查 B-06），但它不属于这张「有哪些合约可以看」的清单。
    let pool = catalog
      .filter { !shownAlready.contains(InstrumentID.canonical($0.symbol)) && $0.status.hasLivePrice }
      .map { row(SymbolMatch(info: $0)) }
      .enumerated()
      .sorted { a, b in
        a.element.quoteVolume == b.element.quoteVolume
          ? a.offset < b.offset
          : a.element.quoteVolume > b.element.quoteVolume
      }
      .map(\.element)
    if !pool.isEmpty {
      out.append(SymbolSection(kind: .all,
                               title: allTitle,
                               rows: Array(pool.prefix(allLimit)),
                               more: max(0, pool.count - allLimit)))
    }
    return out
  }

  /// 搜索页的「热门」：没有历史搜索、也没有最近看过时（第一次打开）列的那一组（审查 U7）。
  ///
  /// 口径和「全部合约」、搜索结果同一套：只列还能交易的，按 24h 成交额降序，
  /// 同额保交易所原序。成交额拿不到（还没有行情、NaN、负数）的**不列**——
  /// 「热门」是一句关于成交额的话，没有成交额就不该凭交易所原序凑数。
  static func hot(catalog: [SymbolInfo], tickers: [String: Ticker], limit: Int = hotLimit) -> [String] {
    var seen = Set<String>()
    return catalog
      .filter { $0.status.hasLivePrice }
      .compactMap { info -> (key: String, volume: Double)? in
        let key = InstrumentID.canonical(info.symbol)
        guard seen.insert(key).inserted, let v = tickers[key]?.quoteVolume, v.isFinite, v > 0 else { return nil }
        return (key, v)
      }
      .enumerated()
      .sorted { a, b in
        a.element.volume == b.element.volume ? a.offset < b.offset : a.element.volume > b.element.volume
      }
      .prefix(limit)
      .map(\.element.key)
  }

  /// 「热门」列几个。
  static let hotLimit = 10
}

extension InstrumentID {
  /// 品种名后面那枚小签：现货市场写「现货」，其余（币安 U 本位）写「永续」。
  /// 按市场分、不按交易所分，这一层不认识任何一家交易所。
  var productLabel: String { market == "spot" ? "现货" : "永续" }
}
