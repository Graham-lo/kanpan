import Foundation
import KanpanCore

// 板块页那张品种列表的**值与文案**。视图（`SectorSymbolList.swift`）只管摆，
// 这一份不 import SwiftUI——它要能在 `Kanpan/Sector` 那个测试壳包里单独编、单独跑
// （审查 B-07 / B.5：小数位和排序这两条规则以前只能靠肉眼在真机上看）。

/// 品种列表的排序。原型 `.lsort` 那两颗。
enum SectorSymbolSort: String, CaseIterable, Sendable {
  case change, volume

  var title: String {
    switch self {
    case .change: "涨跌幅"
    case .volume: "成交额"
    }
  }
}

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
    symbol.hasPrefix(base) ? String(symbol.dropFirst(base.count)) : ""
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
  /// 药丸里只写数，符号由前面那个小三角表达（和自选页一致）。
  var changeText: String { pct.isFinite ? toFixed(abs(pct), 2) + "%" : "—" }
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
                    sort: SectorSymbolSort,
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
    // 两档都要先把非数压到最低档再比（审查 B.5）：NaN 参与 `>` 时任何比较都是假，
    // 排序谓词就不再是严格弱序——同一份数据两次刷新能排出两个顺序，行会自己换位。
    switch sort {
    case .change:
      return rows.sorted { a, b in
        let x = a.pct.isFinite ? a.pct : -.infinity
        let y = b.pct.isFinite ? b.pct : -.infinity
        return x == y ? a.base < b.base : x > y
      }
    case .volume:
      return rows.sorted { a, b in
        let x = a.quoteVolume.isFinite ? a.quoteVolume : -.infinity
        let y = b.quoteVolume.isFinite ? b.quoteVolume : -.infinity
        return x == y ? a.base < b.base : x > y
      }
    }
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

/// 成交额在**副文案**里的那一段：`· 成交额 1.2B`。
///
/// 拿不到就整段不写，不印「· 成交额 —」——一整列的「—」是废话，它既不是一格空位，
/// 也没告诉用户任何事（OKX 那条线路上全市场都没有以 USDT 结算的成交额，就会是这样）。
/// 和同一句里「20 日」那一段缺数时的处理一致：少一段，不解释。
/// 成交额的写法只有这两个出口，别再各处自己拼。
func sectorVolumeClause(_ value: Double) -> String {
  value.isFinite ? " · 成交额 " + sectorVolumeText(value) : ""
}

/// `+1.23%` / `-0.45%`，两位小数带符号。
func sectorPctText(_ value: Double) -> String {
  guard value.isFinite else { return "—" }
  return (value >= 0 ? "+" : "") + toFixed(value, 2) + "%"
}
