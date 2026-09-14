import Foundation
import Testing
import KanpanCore

@testable import KanpanSymbols

/// §9.3 的四个分区、每行的展示字段、以及 A5.7 的「全部列表按 24h 额降序」。
@Suite("品种页分区")
struct SymbolSectionsTests {
  private let catalog = SymbolFixtures.catalog
  private var tickers: [String: Ticker] {
    Dictionary(SymbolFixtures.tickers.map { ($0.symbol, $0) }, uniquingKeysWith: { a, _ in a })
  }

  private func build(_ prefs: SymbolPrefs = SymbolPrefs(), query: String = "",
                     tickers t: [String: Ticker]? = nil) -> [SymbolSection] {
    SymbolSections.build(catalog: catalog, tickers: t ?? tickers, prefs: prefs, query: query)
  }

  @Test("无查询：自选 → 最近 → 全部，顺序固定")
  func threeSections() {
    let prefs = SymbolPrefs(favorites: ["ETHUSDT"], recents: ["DOGEUSDT"])
    let s = build(prefs)
    #expect(s.map(\.kind) == [.favorites, .recents, .all])
    #expect(s.map(\.title) == ["自选", "最近", "全部合约"])
  }

  @Test("空分区不出现")
  func emptySectionsHidden() {
    #expect(build().map(\.kind) == [.all])
    #expect(build(SymbolPrefs(favorites: ["BTCUSDT"])).map(\.kind) == [.favorites, .all])
    #expect(build(SymbolPrefs(recents: ["BTCUSDT"])).map(\.kind) == [.recents, .all])
  }

  @Test("自选按用户自己的顺序出，不按成交额")
  func favoritesKeepUserOrder() {
    let prefs = SymbolPrefs(favorites: ["DOGEUSDT", "BTCUSDT", "ETHUSDT"])
    let fav = build(prefs).first { $0.kind == .favorites }
    #expect(fav?.rows.map(\.id) == ["DOGEUSDT", "BTCUSDT", "ETHUSDT"])
  }

  @Test("已在自选里的不再出现在最近，两处都露过的不再进全部")
  func noDuplicatesAcrossSections() {
    let prefs = SymbolPrefs(favorites: ["BTCUSDT"], recents: ["BTCUSDT", "ETHUSDT"])
    let s = build(prefs)
    #expect(s.first { $0.kind == .favorites }?.rows.map(\.id) == ["BTCUSDT"])
    #expect(s.first { $0.kind == .recents }?.rows.map(\.id) == ["ETHUSDT"])
    let all = s.first { $0.kind == .all }?.rows.map(\.id) ?? []
    #expect(!all.contains("BTCUSDT"))
    #expect(!all.contains("ETHUSDT"))
    #expect(all.count == catalog.count - 2)
  }

  @Test("实时报价先到但统计缺失时仍保持有效排序，不伪造统计值")
  func missingStatisticsHaveStableSortKeys() {
    var values = tickers
    values["BTCUSDT"]?.quoteVolume = .nan
    values["ETHUSDT"]?.quoteVolume = .infinity
    values["SOLUSDT"]?.quoteVolume = -1
    let input = catalog.filter { ["BTCUSDT", "ETHUSDT", "SOLUSDT", "DOGEUSDT"].contains($0.symbol) }
    let rows = SymbolSections.build(catalog: input, tickers: values, prefs: SymbolPrefs(), query: "").flatMap(\.rows)
    #expect(rows.first?.id == "DOGEUSDT")
    #expect(Array(rows.dropFirst().map(\.id)) == input.filter { $0.symbol != "DOGEUSDT" }.map(\.symbol))
    #expect(rows.first { $0.id == "BTCUSDT" }?.ticker?.quoteVolume.isNaN == true)
  }

  @Test("全部按 24h 成交额降序（A5.7）")
  func allSortedByQuoteVolume() {
    let rows = build().first { $0.kind == .all }?.rows ?? []
    let vols = rows.map(\.quoteVolume)
    #expect(vols == vols.sorted(by: >))
    #expect(rows.first?.id == "BTCUSDT")      // 9.82e9 最大
    #expect(rows.map(\.id).prefix(3) == ["BTCUSDT", "ETHUSDT", "SOLUSDT"])
    // AVAX 在品种表里排最后，成交额却比 BCH / LTC / ETHFI 高，排序确实动过
    #expect(rows.last?.id == "ETHWUSDT")
    #expect(rows.firstIndex { $0.id == "AVAXUSDT" }! < rows.firstIndex { $0.id == "BCHUSDT" }!)
  }

  @Test("没有行情的品种成交额算 0，落到末尾且保持原序")
  func missingTickersFallBackToCatalogOrder() {
    let only = ["SOLUSDT": tickers["SOLUSDT"]!]
    let rows = build(tickers: only).first { $0.kind == .all }?.rows ?? []
    #expect(rows.first?.id == "SOLUSDT")
    // 其余全是 0，按品种表原序
    #expect(rows.dropFirst().map(\.id) == catalog.map(\.symbol).filter { $0 != "SOLUSDT" })
    #expect(rows.dropFirst().allSatisfy { $0.priceText == "—" })
  }

  @Test("搜索态只剩一组，标题带命中数")
  func searchCollapsesToOneSection() {
    let s = build(SymbolPrefs(favorites: ["BTCUSDT"]), query: "eth")
    #expect(s.count == 1)
    #expect(s[0].kind == .search)
    #expect(s[0].title == "搜到 3 个")
    #expect(s[0].rows.map(\.id) == ["ETHUSDT", "ETHFIUSDT", "ETHWUSDT"])
  }

  @Test("搜不到给空分区，页面自己去显示「没有这个品种」")
  func searchMiss() {
    let s = build(query: "zzzz")
    #expect(s.count == 1)
    #expect(s[0].rows.isEmpty)
    #expect(s[0].title == "搜到 0 个")
    #expect(SymbolSections.emptyText == "没有这个品种")
  }

  @Test("封顶与「还有 N 个」小字，常数照原型：全部 120、搜索 160")
  func limitsFollowPrototype() {
    #expect(SymbolSections.allLimit == 120)
    #expect(SymbolSections.searchLimit == 160)

    let big = (1 ... 300).map {
      SymbolInfo(symbol: "S\($0)USDT", base: "S\($0)", pricePrecision: 2, tickSize: 0.01)
    }
    let all = SymbolSections.build(catalog: big, tickers: [:], prefs: SymbolPrefs(), query: "")[0]
    #expect(all.rows.count == 120)
    #expect(all.more == 180)
    #expect(all.moreNote == "还有 180 个，搜名字更快。")

    let hit = SymbolSections.build(catalog: big, tickers: [:], prefs: SymbolPrefs(), query: "S")[0]
    #expect(hit.rows.count == 160)
    #expect(hit.more == 140)

    // 没超出就没有那行小字
    #expect(SymbolSections.build(catalog: SymbolFixtures.catalog, tickers: [:],
                                 prefs: SymbolPrefs(), query: "")[0].moreNote == nil)
  }

  @Test("页头小字：N 个永续合约")
  func countText() {
    #expect(SymbolSections.countText(catalog) == "\(catalog.count) 个永续合约")
    #expect(SymbolSections.countText([]) == "0 个永续合约")
  }

  // ---------------------------------------------------------------- 行

  @Test("行的展示字段照原型：名 · 最新价 · 涨跌幅")
  func rowFields() {
    let rows = build().first { $0.kind == .all }?.rows ?? []
    let btc = rows.first { $0.id == "BTCUSDT" }!
    #expect(btc.name == "BTC")
    #expect(btc.quoteSuffix == " / USDT")
    #expect(btc.meta == "BTCUSDT 永续")
    #expect(btc.priceText == "76800.00")     // pricePrecision 2（tickSize 0.10 只推得出 1 位）
    #expect(btc.changeText == "+1.24%")
    #expect(btc.isUp)

    let xrp = rows.first { $0.id == "XRPUSDT" }!
    #expect(xrp.priceText == "2.1843")       // pricePrecision 4
    #expect(xrp.changeText == "-2.15%")
    #expect(!xrp.isUp)
  }

  /// 原型 symRow 用的是 catalog 里的 `p`（= pricePrecision），不是 tickSize 推的位数。
  @Test("价格小数位跟 pricePrecision 走")
  func priceDecimalsFollowPricePrecision() {
    let rows = build().first { $0.kind == .all }?.rows ?? []
    #expect(rows.first { $0.id == "SOLUSDT" }?.priceText == "141.226")          // 3
    #expect(rows.first { $0.id == "DOGEUSDT" }?.priceText == "0.16204")         // 5
    #expect(rows.first { $0.id == "1000PEPEUSDT" }?.priceText == "0.0074812")   // 7
    // BTCUSDT 两者不一致：pricePrecision 2 vs tickSize 0.10 推出的 1 位
    let btc = SymbolFixtures.info("BTCUSDT")
    #expect(btc.pricePrecision == 2)
    #expect(btc.priceDecimals == 1)
    #expect(rows.first { $0.id == "BTCUSDT" }?.priceText == "76800.00")
  }

  @Test("平盘按涨算，没有行情时价显示破折号")
  func flatAndMissing() {
    let rows = build().first { $0.kind == .all }?.rows ?? []
    let bnb = rows.first { $0.id == "BNBUSDT" }!
    #expect(bnb.changeText == "+0.00%")
    #expect(bnb.isUp)

    let naked = SymbolRow(match: SymbolMatch(info: SymbolFixtures.info("BTCUSDT")), ticker: nil)
    #expect(naked.priceText == "—")
    #expect(naked.changeText == "—")
    #expect(naked.isUp)
  }
}
