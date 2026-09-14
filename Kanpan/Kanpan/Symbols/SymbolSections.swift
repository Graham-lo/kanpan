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

  var id: String { match.info.symbol }
  var info: SymbolInfo { match.info }

  /// 行首大字：`BTC`。
  var name: String { info.base }
  /// 大字后面那半截灰的：` / USDT`。
  var quoteSuffix: String { " / " + info.quote }
  /// 第二行小字。原型这行放的是「内嵌了哪些周期」，属于原型特有；
  /// 真 app 里放合约全称，和顶栏「BTCUSDT 永续 ▾」对上。
  var meta: String { info.symbol + " 永续" }

  /// 最新价。没有行情时原型给一个破折号 `—`。
  ///
  /// 小数位用 `pricePrecision`，不是 `SymbolInfo.priceDecimals`（那个由 `tickSize` 推）。
  /// 原型 `symRow()` 取的是 catalog 行里的 `p`，也就是 `pricePrecision`：
  /// BTCUSDT 的 tickSize 是 0.10（推出来 1 位），但币安和原型都显示两位 `76800.00`。
  /// 差异记在 docs/acceptance/M5/品种页.md。
  var priceText: String {
    guard let t = ticker, t.last.isFinite else { return "—" }
    return fmtNum(t.last, info.pricePrecision)
  }

  /// 涨跌幅：`+1.23%` / `-1.23%`，两位小数，照原型 `pct.toFixed(2)`。
  /// 没有行情时原型仍按 0 走（显示 `+0.00%`），这里也一样。
  var changeText: String {
    let p = ticker?.changePercent ?? 0
    return (p >= 0 ? "+" : "") + toFixed(p, 2) + "%"
  }

  /// 原型 `pct >= 0 ? 'up' : 'down'`——平盘算涨。
  var isUp: Bool { (ticker?.changePercent ?? 0) >= 0 }

  /// 24h 成交额，「全部」分区的排序键。
  var quoteVolume: Double { ticker?.quoteVolume ?? 0 }
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
  static func countText(_ catalog: [SymbolInfo]) -> String { "\(catalog.count) 个永续合约" }

  /// 搭出整页的分区。
  ///
  /// - Parameters:
  ///   - catalog: 品种表（`exchangeInfo` 过滤后的 USDT 永续），顺序即交易所给的顺序。
  ///   - tickers: symbol → 24h 行情，缺的行就显示 `—`。
  ///   - prefs: 自选与最近。
  ///   - query: 搜索框里的原文，空串表示没搜。
  static func build(catalog: [SymbolInfo],
                    tickers: [String: Ticker],
                    prefs: SymbolPrefs,
                    query: String) -> [SymbolSection] {
    let bySymbol = Dictionary(catalog.map { ($0.symbol.uppercased(), $0) }, uniquingKeysWith: { a, _ in a })
    func row(_ m: SymbolMatch) -> SymbolRow { SymbolRow(match: m, ticker: tickers[m.info.symbol.uppercased()]) }

    // ---- 搜索态：只有一组，不分自选 / 最近 / 全部（同原型）
    let q = SymbolQuery.normalize(query)
    if !q.isEmpty {
      let hits = SymbolQuery.match(catalog, query: q)
      let shown = Array(hits.prefix(searchLimit)).map(row)
      return [SymbolSection(kind: .search,
                            title: "搜到 \(hits.count) 个",
                            rows: shown,
                            more: max(0, hits.count - searchLimit))]
    }

    // ---- 常态：自选 → 最近 → 全部
    var out: [SymbolSection] = []
    var shownAlready = Set<String>()

    let favorites = prefs.favorites.compactMap { bySymbol[$0] }
    if !favorites.isEmpty {
      shownAlready.formUnion(favorites.map { $0.symbol.uppercased() })
      out.append(SymbolSection(kind: .favorites,
                               title: favoritesTitle,
                               rows: favorites.map { row(SymbolMatch(info: $0)) }))
    }

    // 原型：中间那组剔掉已经在自选里的（`filter(s => !S.watch.includes(s))`）。
    let recents = prefs.recents.compactMap { bySymbol[$0] }.filter { !shownAlready.contains($0.symbol.uppercased()) }
    if !recents.isEmpty {
      shownAlready.formUnion(recents.map { $0.symbol.uppercased() })
      out.append(SymbolSection(kind: .recents,
                               title: recentsTitle,
                               rows: recents.map { row(SymbolMatch(info: $0)) }))
    }

    // 「全部」：剔掉上面露过脸的，按 24h 成交额降序（A5.7）。
    // 没有行情的品种成交额算 0，落在末尾，同额时保持交易所给的原序。
    let pool = catalog
      .filter { !shownAlready.contains($0.symbol.uppercased()) }
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
}
