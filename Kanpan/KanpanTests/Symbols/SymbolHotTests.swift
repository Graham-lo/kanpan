import Foundation
import Testing
import KanpanCore

@testable import Kanpan

/// 搜索页「热门」：第一次打开没历史、没最近时列的那一组（审查 U7）。
@Suite("搜索页热门")
struct SymbolHotTests {
  private var tickers: [String: Ticker] {
    Dictionary(SymbolFixtures.tickers.map { ($0.symbol, $0) }, uniquingKeysWith: { a, _ in a })
  }

  @Test("按 24h 成交额降序取前 10，口径同「全部合约」")
  func topTenByVolume() {
    let hot = SymbolSections.hot(catalog: SymbolFixtures.catalog, tickers: tickers)
    let expected = SymbolSections.build(catalog: SymbolFixtures.catalog, tickers: tickers,
                                        prefs: SymbolPrefs(), query: "")
      .first { $0.kind == .all }?.rows
      .filter { $0.quoteVolume > 0 }
      .prefix(SymbolSections.hotLimit)
      .map(\.id) ?? []
    #expect(hot.count == min(SymbolSections.hotLimit, expected.count))
    #expect(hot == expected)
    let volumes = hot.compactMap { tickers[$0]?.quoteVolume }
    #expect(volumes == volumes.sorted(by: >))
  }

  @Test("停牌 / 未开盘 / 下架的不列，成交额拿不到的不凑数")
  func onlyLiveWithVolume() {
    let top = SymbolSections.hot(catalog: SymbolFixtures.catalog, tickers: tickers)
    guard top.count >= 3 else { Issue.record("夹具不够三只"); return }
    let catalog = SymbolFixtures.catalog.map { info -> SymbolInfo in
      var next = info
      if info.symbol == top[0] { next.status = .delisted }
      if info.symbol == top[1] { next.status = .pending }
      return next
    }
    var t = tickers
    t[top[2]]?.quoteVolume = .nan
    let hot = SymbolSections.hot(catalog: catalog, tickers: t)
    #expect(!hot.contains(top[0]))
    #expect(!hot.contains(top[1]))
    #expect(!hot.contains(top[2]))
    #expect(SymbolSections.hot(catalog: SymbolFixtures.catalog, tickers: [:]).isEmpty, "没行情时不按原序凑一组「热门」")
  }
}
