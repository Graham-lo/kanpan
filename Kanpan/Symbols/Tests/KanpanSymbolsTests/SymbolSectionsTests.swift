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
    let prefs = SymbolPrefs(favorites: ["binance/usd_m/ETHUSDT"], recents: ["binance/usd_m/DOGEUSDT"])
    let s = build(prefs)
    #expect(s.map(\.kind) == [.favorites, .recents, .all])
    #expect(s.map(\.title) == ["自选", "最近", "全部合约"])
  }

  @Test("空分区不出现")
  func emptySectionsHidden() {
    #expect(build().map(\.kind) == [.all])
    #expect(build(SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT"])).map(\.kind) == [.favorites, .all])
    #expect(build(SymbolPrefs(recents: ["binance/usd_m/BTCUSDT"])).map(\.kind) == [.recents, .all])
  }

  @Test("自选按用户自己的顺序出，不按成交额")
  func favoritesKeepUserOrder() {
    let prefs = SymbolPrefs(favorites: ["binance/usd_m/DOGEUSDT", "binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"])
    let fav = build(prefs).first { $0.kind == .favorites }
    #expect(fav?.rows.map(\.id) == ["binance/usd_m/DOGEUSDT", "binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"])
  }

  @Test("已在自选里的不再出现在最近，两处都露过的不再进全部")
  func noDuplicatesAcrossSections() {
    let prefs = SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT"], recents: ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"])
    let s = build(prefs)
    #expect(s.first { $0.kind == .favorites }?.rows.map(\.id) == ["binance/usd_m/BTCUSDT"])
    #expect(s.first { $0.kind == .recents }?.rows.map(\.id) == ["binance/usd_m/ETHUSDT"])
    let all = s.first { $0.kind == .all }?.rows.map(\.id) ?? []
    #expect(!all.contains("binance/usd_m/BTCUSDT"))
    #expect(!all.contains("binance/usd_m/ETHUSDT"))
    #expect(all.count == catalog.count - 2)
  }

  @Test("实时报价先到但统计缺失时仍保持有效排序，不伪造统计值")
  func missingStatisticsHaveStableSortKeys() {
    var values = tickers
    values["binance/usd_m/BTCUSDT"]?.quoteVolume = .nan
    values["binance/usd_m/ETHUSDT"]?.quoteVolume = .infinity
    values["binance/usd_m/SOLUSDT"]?.quoteVolume = -1
    let input = catalog.filter { ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT", "binance/usd_m/SOLUSDT", "binance/usd_m/DOGEUSDT"].contains($0.symbol) }
    let rows = SymbolSections.build(catalog: input, tickers: values, prefs: SymbolPrefs(), query: "").flatMap(\.rows)
    #expect(rows.first?.id == "binance/usd_m/DOGEUSDT")
    #expect(Array(rows.dropFirst().map(\.id)) == input.filter { $0.symbol != "binance/usd_m/DOGEUSDT" }.map(\.symbol))
    #expect(rows.first { $0.id == "binance/usd_m/BTCUSDT" }?.ticker?.quoteVolume.isNaN == true)
  }

  @Test("全部按 24h 成交额降序（A5.7）")
  func allSortedByQuoteVolume() {
    let rows = build().first { $0.kind == .all }?.rows ?? []
    let vols = rows.map(\.quoteVolume)
    #expect(vols == vols.sorted(by: >))
    #expect(rows.first?.id == "binance/usd_m/BTCUSDT")      // 9.82e9 最大
    #expect(rows.map(\.id).prefix(3) == ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT", "binance/usd_m/SOLUSDT"])
    // AVAX 在品种表里排最后，成交额却比 BCH / LTC / ETHFI 高，排序确实动过
    #expect(rows.last?.id == "binance/usd_m/ETHWUSDT")
    #expect(rows.firstIndex { $0.id == "binance/usd_m/AVAXUSDT" }! < rows.firstIndex { $0.id == "binance/usd_m/BCHUSDT" }!)
  }

  @Test("没有行情的品种成交额算 0，落到末尾且保持原序")
  func missingTickersFallBackToCatalogOrder() {
    let only = ["binance/usd_m/SOLUSDT": tickers["binance/usd_m/SOLUSDT"]!]
    let rows = build(tickers: only).first { $0.kind == .all }?.rows ?? []
    #expect(rows.first?.id == "binance/usd_m/SOLUSDT")
    // 其余全是 0，按品种表原序
    #expect(rows.dropFirst().map(\.id) == catalog.map(\.symbol).filter { $0 != "binance/usd_m/SOLUSDT" })
    #expect(rows.dropFirst().allSatisfy { $0.priceText == "—" })
  }

  @Test("搜索态只剩一组，标题带命中数")
  func searchCollapsesToOneSection() {
    let s = build(SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT"]), query: "eth")
    #expect(s.count == 1)
    #expect(s[0].kind == .search)
    #expect(s[0].title == "搜到 3 个")
    #expect(s[0].rows.map(\.id) == ["binance/usd_m/ETHUSDT", "binance/usd_m/ETHFIUSDT", "binance/usd_m/ETHWUSDT"])
  }

  /// 用户 2026-09-18：「首先选最匹配的，然后如果出现多个应该按照成交额来排序，
  /// 这样用户如果不是输入全匹配的品种就可以第一时间搜到最热门的品种」。
  @Test("搜索结果同档内按 24h 成交额降序")
  func searchOrdersByTurnover() {
    // 「USDT」只命中 quote 段，全是同一档；品种表原序不是成交额序，
    // 所以这一组的次序只能来自成交额。
    let rows = build(query: "USDT")[0].rows
    #expect(rows.map(\.id) == ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT", "binance/usd_m/SOLUSDT", "binance/usd_m/BNBUSDT", "binance/usd_m/XRPUSDT",
                               "binance/usd_m/DOGEUSDT", "binance/usd_m/1000PEPEUSDT", "binance/usd_m/AVAXUSDT", "binance/usd_m/BCHUSDT",
                               "binance/usd_m/LTCUSDT", "binance/usd_m/ETHFIUSDT", "binance/usd_m/ETHWUSDT"])
    #expect(rows.map(\.quoteVolume) == rows.map(\.quoteVolume).sorted(by: >))
  }

  @Test("打全了的压过成交额：搜 eth，ETHUSDT 在最前")
  func exactBeatsTurnover() {
    // ETHFI / ETHW 的成交额都不如 ETH，但就算它们更大也该排在 ETHUSDT 后面——
    // 这里把 ETHUSDT 的成交额压到最低来证明「最匹配」是第一顺位。
    var t = tickers
    t["binance/usd_m/ETHUSDT"] = Ticker(symbol: "binance/usd_m/ETHUSDT", last: 2_913.45, changePercent: -0.86,
                          high: 3_000, low: 2_800, quoteVolume: 1)
    let rows = SymbolSections.build(catalog: catalog, tickers: t,
                                    prefs: SymbolPrefs(), query: "eth")[0].rows
    #expect(rows.map(\.id) == ["binance/usd_m/ETHUSDT", "binance/usd_m/ETHFIUSDT", "binance/usd_m/ETHWUSDT"])
  }

  @Test("一条行情都没有时，搜索结果回落到品种表原序")
  func searchWithoutTickersKeepsCatalogOrder() {
    let rows = SymbolSections.build(catalog: catalog, tickers: [:],
                                    prefs: SymbolPrefs(), query: "USDT")[0].rows
    #expect(rows.map(\.id) == catalog.map(\.symbol))
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
    // 表里并进了现货（别家交易所）：分开数，不把现货算成永续。
    let spot = SymbolInfo(symbol: "coinbase/spot/BTC-USD", base: "BTC", quote: "USD",
                          pricePrecision: 2, tickSize: 0.01, underlyingType: "COIN")
    #expect(SymbolSections.countText(catalog + [spot]) == "\(catalog.count) 个永续合约 · 1 个现货")
  }

  @Test("现货行的小字写「现货」")
  func spotMeta() {
    let spot = SymbolInfo(symbol: "coinbase/spot/BTC-USD", base: "BTC", quote: "USD",
                          pricePrecision: 2, tickSize: 0.01, underlyingType: "COIN")
    let rows = SymbolSections.build(catalog: [spot], tickers: [:], prefs: SymbolPrefs(), query: "")
      .first { $0.kind == .all }?.rows ?? []
    #expect(rows.first?.meta == "BTC-USD 现货")
  }

  // ---------------------------------------------------------------- 行

  @Test("行的展示字段照原型：名 · 最新价 · 涨跌幅")
  func rowFields() {
    let rows = build().first { $0.kind == .all }?.rows ?? []
    let btc = rows.first { $0.id == "binance/usd_m/BTCUSDT" }!
    #expect(btc.name == "BTC")
    #expect(btc.quoteSuffix == " / USDT")
    #expect(btc.meta == "BTCUSDT 永续")
    #expect(btc.priceText == "76800.0")     // tickSize 0.1 → 1 位
    #expect(btc.changeText == "+1.24%")
    #expect(btc.isUp)

    let xrp = rows.first { $0.id == "binance/usd_m/XRPUSDT" }!
    #expect(xrp.priceText == "2.1843")       // tickSize 0.0001 → 4 位
    #expect(xrp.changeText == "-2.15%")
    #expect(!xrp.isUp)
  }

  /// 展示位数按最小报价步长，不能把下单字段的位数带到界面。
  @Test("价格小数位跟 tickSize 走")
  func priceDecimalsFollowTickSize() {
    let rows = build().first { $0.kind == .all }?.rows ?? []
    #expect(rows.first { $0.id == "binance/usd_m/SOLUSDT" }?.priceText == "141.226")          // 3
    #expect(rows.first { $0.id == "binance/usd_m/DOGEUSDT" }?.priceText == "0.16204")         // 5
    #expect(rows.first { $0.id == "binance/usd_m/1000PEPEUSDT" }?.priceText == "0.0074812")   // 7
    // BTCUSDT 两者不一致：pricePrecision 2 vs tickSize 0.10 推出的 1 位
    let btc = SymbolFixtures.info("binance/usd_m/BTCUSDT")
    #expect(btc.pricePrecision == 2)
    #expect(btc.priceDecimals == 1)
    #expect(rows.first { $0.id == "binance/usd_m/BTCUSDT" }?.priceText == "76800.0")
  }

  @Test("平盘按涨算，没有行情时价显示破折号")
  func flatAndMissing() {
    let rows = build().first { $0.kind == .all }?.rows ?? []
    let bnb = rows.first { $0.id == "binance/usd_m/BNBUSDT" }!
    #expect(bnb.changeText == "+0.00%")
    #expect(bnb.isUp)

    let naked = SymbolRow(match: SymbolMatch(info: SymbolFixtures.info("binance/usd_m/BTCUSDT")), ticker: nil)
    #expect(naked.priceText == "—")
    #expect(naked.changeText == "—")
    #expect(naked.isUp)
  }
}
