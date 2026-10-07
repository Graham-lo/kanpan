import Foundation
import KanpanCore

// 板块页那张品种列表的**值与文案**。视图（`SectorSymbolList.swift`）只管摆，
// 这一份不 import SwiftUI——值与文案和视图分开，KanpanTests 的 Sector 组直接测它
// （审查 B-07 / B.5：小数位和排序这两条规则以前只能靠肉眼在真机上看）。

// 品种列表的排序原来有「涨跌幅 / 成交额」两档（`SectorSymbolSort`，原型 `.lsort` 那两颗），
// 2026-09-28 收掉（收设置项 G）：一律按当前窗口的涨跌幅降序。

/// 板块品种列表里的一行。
///
/// 纯值、好断言，写法照 `SymbolSections.swift`：视图只管摆，文案在这儿算完。
struct SectorSymbolRow: Sendable, Equatable, Identifiable {
  /// 大写代号，如 `BTC`。
  let base: String
  /// 完整合约代号，如 `BTCUSDT`。开行情页要的是它。
  let symbol: String
  let price: Double
  let pct: Double
  let quoteVolume: Double
  /// 前沿成员：跑赢池基准、且相对收益排在全池 90 分位以上。
  let isFrontier: Bool
  /// 这个品种自己的价格小数位（`SymbolInfo.priceDecimals`）。品种表还没到就是 `nil`。
  let decimals: Int?

  var id: String { symbol }

  /// 代号后面那截计价币。`BTCUSDT` → `USDT`。
  var quoteText: String {
    SymbolInfo.placeholder(symbol: symbol).quote
  }

  /// 价格小数位由**品种自己**说（`SymbolInfo.priceDecimals`），和顶栏、图表、
  /// 复盘浮层同一个口径（审查 B-07）。原来这儿按数值大小现猜 2/4/5/7 位，
  /// 于是同一个价在这张列表里和在行情页头部能写成两种样子。
  ///
  /// 品种表还没到（`decimals == nil`）才退回按大小猜，并且照 `fmtPrice` 的规矩
  /// 兜住极小的正价——真实存在的价绝不显示成 `0.00`。
  var priceText: String {
    guard price.isFinite else { return "—" }
    return sectorGrouped(fmtPrice(price, decimals: decimals ?? Self.guessedDecimals(price)))
  }

  /// 品种表缺位时的临时小数位。只在这一种情形下用，梯子在 `KanpanCore`——
  /// 自选页那条空档路走的是同一把（审查 B-07）。
  static func guessedDecimals(_ price: Double) -> Int { priceDecimalsFallback(price) }

  var volumeText: String { sectorVolumeText(quoteVolume) }
  var isUp: Bool { pct >= 0 }
  var signedText: String { sectorPctText(pct) }

  /// 把成员名单和行情拼成行。没有行情的成员直接不出现——聚合那边也没算它。
  ///
  /// `pct` 跟着当前窗口走：今日是 24h 涨跌幅，5 日是 `100·(现价/5 日前收盘 − 1)`。
  /// **价格那一列永远是实时价**，不跟窗口变——看 5 日的人也要知道现在多少钱。
  /// 这一段没有收盘的成员仍旧列在表里（它有行情、有价格），只是涨跌那一格写「—」，
  /// 排序时沉到最后；把它整行藏掉才是骗人。
  static func build(members: [String], quotes: [String: SectorQuote],
                    symbolForBase: (String) -> String,
                    decimalsForBase: (String) -> Int? = { _ in nil },
                    frontier: Set<String> = [],
                    window: SectorWindow = .today,
                    history: SectorHistory = .empty) -> [SectorSymbolRow] {
    let rows = members.compactMap { base -> SectorSymbolRow? in
      guard let quote = quotes[base] else { return nil }
      let pct = SectorAggregator.windowReturn(quote, window: window,
                                              closes: history.closes[base]) ?? .nan
      return SectorSymbolRow(base: base, symbol: symbolForBase(base), price: quote.price,
                             pct: pct, quoteVolume: quote.quoteVolume,
                             isFrontier: frontier.contains(base),
                             decimals: decimalsForBase(base))
    }
    // 并列（以及一整排「—」）按代号排，免得两次刷新之间互换位置。
    //
    // 先把非数压到最低档再比（审查 B.5）：NaN 参与 `>` 时任何比较都是假，
    // 排序谓词就不再是严格弱序——同一份数据两次刷新能排出两个顺序，行会自己换位。
    return rows.sorted { a, b in
      let x = a.pct.isFinite ? a.pct : -.infinity
      let y = b.pct.isFinite ? b.pct : -.infinity
      return x == y ? a.base < b.base : x > y
    }
  }
}

/// 板块页那张整页列表的顺序：按当前窗口的涨跌幅降序，兜底桶和普通板块一视同仁。
///
/// 有行情成员不到 `minEligibleMembers` 个的板块整档排在后面（`desci` 就一只 BIO）：
/// 它的「中位数」就是那一两只币自己的涨跌，拿来和几十只成员的板块比强弱，
/// 一只币拉一根就能顶到第一。这一档自己之间仍按涨跌幅排，板块照样列着、点得进去。
///
/// 5 日那一档覆盖不够的板块（`SectorAggregator.covered`）也在后面那一档：它的 `pct` 是 NaN，
/// 成员再多也不算强弱（深度审查 D 线 2026-10-04）。
///
/// 算不出数的（NaN / ±∞）压到最后，并列按 id 排——NaN 参与 `>` 时比较恒假，排序谓词
/// 就不再是严格弱序，同一份数据两次刷新能排出两个顺序，行会自己换位（和品种列表那条
/// 规矩一样，审查 B.5）。
enum SectorBoardOrder {
  static func sorted(_ stats: [SectorStat]) -> [SectorStat] {
    stats.sorted { a, b in
      // 分档只看成员数：覆盖不够、算不出数的板块（`pct` 是 NaN）仍在真板块这一档、沉到档底，
      // 一两只币的板块整档排在它后面（`SectorRowTests.thinBoardsSinkBelowRealSectors`）。
      let thinA = a.memberCount < SectorAggregator.minEligibleMembers
      let thinB = b.memberCount < SectorAggregator.minEligibleMembers
      if thinA != thinB { return thinB }
      let x = a.pct.isFinite ? a.pct : -.infinity
      let y = b.pct.isFinite ? b.pct : -.infinity
      return x == y ? a.id < b.id : x > y
    }
  }
}

/// 板块的副文案：只有一句 `15/21 跑赢大盘`。
///
/// 板块列表每一行和品种列表头部说的是同一句，所以句子只在这儿拼一次。
/// 2026-09-28 用户定：原来前面的「21 个品种」、后面的「· 成交额 4.86B」（下钻页看 5 日时是
/// 「· 20 日 +12.1%」）都去掉——分母已经说了有几只，成交额在每一行上各有一格，
/// 这一句只回答「整体在动还是一只在爆」。
///
/// 有行情成员不到 `minEligibleMembers` 个的板块（`desci` 就一只 BIO）没有「广度」可言
/// ——一只币的涨跌不是板块强弱。这种给空串，调用处整行不画，不解释为什么。
enum SectorSubtitle {
  static func text(_ stat: SectorStat) -> String {
    guard counts(stat) else { return "" }
    return "\(stat.outperformCount)/\(stat.memberCount) 跑赢大盘"
  }

  /// 这个板块的强弱算不算数：有行情成员够 `minEligibleMembers` 个，而且这段窗口上
  /// 真算出了中位数（覆盖不够的那种 `pct` 是 NaN，广度也没有，写「0/12 跑赢大盘」就是瞎说）。
  static func counts(_ stat: SectorStat) -> Bool {
    stat.memberCount >= SectorAggregator.minEligibleMembers && stat.pct.isFinite
  }

  /// 板块列表里的一行。和下钻页头部同一句。
  static func row(_ stat: SectorStat) -> String { text(stat) }

  /// 页头标题旁那行规模：`28 个板块 · 526 个品种`。品种数是去重后、这段窗口上
  /// 真算得出收益的那些，不是各板块成员数相加（一个品种可以同时属于好几个板块）。
  static func scale(sectors: Int, symbols: Int) -> String {
    "\(sectors) 个板块 · \(symbols) 个品种"
  }
}

/// 板块行涨跌幅左边那行小字「领涨 XXX」。
///
/// 只写一只：这段窗口上收益最高、而且真在涨的成员（`SectorStat.leader`）。板块强弱不算数
/// （`SectorSubtitle.counts` 不过）或没有领涨的就返回空串，界面上那格直接不画。
/// 港股 `HK0992`、`LGELECTRONICS` 这种读不出是谁的代号换成中文简称（有数字或超过 6 个字符、
/// 且分类表里有简称时）；其余照写代号，超过 8 个字符截到 8 位，免得把涨跌幅挤走。
enum SectorLeaderLabel {
  static let maxCodeLength = 8

  static func text(_ stat: SectorStat) -> String {
    guard SectorSubtitle.counts(stat), let base = stat.leader, !base.isEmpty else { return "" }
    return "领涨 " + display(base)
  }

  static func display(_ base: String) -> String {
    let opaque = base.count > 6 || base.contains(where: \.isNumber)
    if opaque, let name = SectorCatalog.chineseName(base: base) { return name }
    return String(base.prefix(maxCodeLength))
  }
}

/// 价格千分位。`fmtNum` 只管小数位，逗号在这儿补。和自选页同一份实现。
func sectorGrouped(_ text: String) -> String {
  let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
  var head = String(parts[0])
  let negative = head.hasPrefix("-")
  if negative { head.removeFirst() }
  guard head.count > 3 else { return text }
  var out = ""
  for (index, character) in head.reversed().enumerated() {
    if index > 0, index % 3 == 0 { out.append(",") }
    out.append(character)
  }
  let body = (negative ? "-" : "") + String(out.reversed())
  return parts.count > 1 ? body + "." + parts[1] : body
}

/// 成交额的**值格**写法：占着一格位置的那种（品种行的成交额列、自选详情里的
/// 「24小时额」）。拿不到就是「—」，和同一格的价格 / 涨跌幅缺数写成一个样
/// （复核项 3）；行情页头部那一格沿用它既有的 `--`。
func sectorVolumeText(_ value: Double) -> String {
  value.isFinite ? fmtVol(value) : "—"
}

// 原来这儿还有副文案里那一段「· 成交额 1.2B」的出口（`sectorVolumeClause`），
// 2026-09-28 副文案收成一句「跑赢大盘」后没有调用处了，一并删掉。成交额的写法只剩上面这一个出口。

/// `+1.23%` / `−0.45%`，两位小数带符号——全 app 唯一那把 `changePercentText`（审查 U9）。
func sectorPctText(_ value: Double) -> String { changePercentText(value) }

/// 涨跌幅该上哪种颜色。算不出来（`NaN`：下钻时行情还没到的那张空壳）就是**中性**，
/// 不能因为「不 ≥ 0」落进下跌色——原来空壳写着 `+0.00%` 涂着上涨色，像是真算出来了一个平盘。
enum SectorPctTone: Equatable {
  case up, down, neutral
  static func of(_ value: Double) -> SectorPctTone {
    guard value.isFinite else { return .neutral }
    return value >= 0 ? .up : .down
  }
}
