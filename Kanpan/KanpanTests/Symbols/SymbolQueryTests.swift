import Foundation
import Testing
import KanpanCore

@testable import Kanpan

/// A5.7 前半：搜「btc」实时过滤、base 前缀优先。
@Suite("品种搜索")
struct SymbolQueryTests {
  private let catalog = SymbolFixtures.catalog

  @Test("小写照样搜得到，命中集合与原型一致")
  func caseInsensitive() {
    let hit = SymbolQuery.match(catalog, query: "btc")
    #expect(hit.map(\.id) == ["binance/usd_m/BTCUSDT"])
    #expect(SymbolQuery.match(catalog, query: "BTC").map(\.id) == hit.map(\.id))
    #expect(SymbolQuery.match(catalog, query: "  btc  ").map(\.id) == hit.map(\.id))
  }

  @Test("空查询不过滤，原序全出")
  func emptyQuery() {
    #expect(SymbolQuery.match(catalog, query: "").map(\.id) == catalog.map(\.symbol))
    #expect(SymbolQuery.match(catalog, query: "   ").count == catalog.count)
  }

  /// §10.5 的原话：搜 eth 先出 ETHUSDT 再出 ETHFIUSDT。
  @Test("base 前缀排在含子串的前面")
  func basePrefixWins() {
    let ids = SymbolQuery.match(catalog, query: "eth").map(\.id)
    #expect(ids.prefix(3) == ["binance/usd_m/ETHUSDT", "binance/usd_m/ETHFIUSDT", "binance/usd_m/ETHWUSDT"])
    // ETH 三个是 base 前缀，排在只是 symbol 里含 ETH 的后面那些之前
    #expect(ids.firstIndex(of: "binance/usd_m/ETHUSDT")! < ids.firstIndex(of: "binance/usd_m/ETHFIUSDT")!)
  }

  /// 用户 2026-09-18：「首先选最匹配的」。打全了的那个要压过同前缀的兄弟，
  /// 哪怕兄弟在品种表里排得更靠前。
  @Test("打全了的排第一档")
  func exactWins() {
    #expect(SymbolQuery.match(SymbolFixtures.info("binance/usd_m/ETHUSDT"), query: "ETH")?.tier == .exact)
    #expect(SymbolQuery.match(SymbolFixtures.info("binance/usd_m/ETHUSDT"), query: "ETHUSDT")?.tier == .exact)
    #expect(SymbolQuery.match(SymbolFixtures.info("binance/usd_m/ETHFIUSDT"), query: "ETH")?.tier == .basePrefix)
    #expect(SymbolQuery.match(catalog, query: "eth").first?.id == "binance/usd_m/ETHUSDT")
  }

  @Test("同档保持品种表原序（稳定排序）")
  func stableWithinTier() {
    // U 在这批里只会命中 quote 段（USDT），全是同一档
    let ids = SymbolQuery.match(catalog, query: "USDT").map(\.id)
    #expect(ids == catalog.map(\.symbol))
  }

  @Test("五档名次各就各位")
  func tiers() {
    #expect(SymbolQuery.match(SymbolFixtures.info("binance/usd_m/ETHUSDT"), query: "ETH")?.tier == .exact)
    #expect(SymbolQuery.match(SymbolFixtures.info("binance/usd_m/ETHFIUSDT"), query: "ETH")?.tier == .basePrefix)
    #expect(SymbolQuery.match(SymbolFixtures.info("binance/usd_m/ETHUSDT"), query: "ETHU")?.tier == .symbolPrefix)
    #expect(SymbolQuery.match(SymbolFixtures.info("binance/usd_m/ETHFIUSDT"), query: "THF")?.tier == .baseContains)
    #expect(SymbolQuery.match(SymbolFixtures.info("binance/usd_m/BTCUSDT"), query: "SDT")?.tier == .symbolContains)
    #expect(SymbolQuery.match(SymbolFixtures.info("binance/usd_m/BTCUSDT"), query: "ZZZ") == nil)
  }

  @Test("数字前缀的品种也能搜")
  func numericBase() {
    #expect(SymbolQuery.match(catalog, query: "1000").map(\.id) == ["binance/usd_m/1000PEPEUSDT"])
    #expect(SymbolQuery.match(catalog, query: "pepe").map(\.id) == ["binance/usd_m/1000PEPEUSDT"])
    #expect(SymbolQuery.match(SymbolFixtures.info("binance/usd_m/1000PEPEUSDT"), query: "PEPE")?.tier == .baseContains)
  }

  @Test("高亮片段落在 symbol 的正确位置")
  func highlightRange() {
    #expect(SymbolQuery.match(SymbolFixtures.info("binance/usd_m/ETHFIUSDT"), query: "ETH")?.highlight == 0 ..< 3)
    #expect(SymbolQuery.match(SymbolFixtures.info("binance/usd_m/ETHFIUSDT"), query: "FI")?.highlight == 3 ..< 5)
    // 落在 quote 段：ETHFI 5 个字符，USDT 从 5 起
    #expect(SymbolQuery.match(SymbolFixtures.info("binance/usd_m/ETHFIUSDT"), query: "USD")?.highlight == 5 ..< 8)
    #expect(SymbolQuery.match(catalog, query: "").first?.highlight == nil)
  }

  @Test("高亮切段：命中段单独拆出来")
  func split() {
    let base = SymbolQuery.split("ETHFI", highlight: 0 ..< 3, offset: 0)
    #expect(base.map(\.text) == ["ETH", "FI"])
    #expect(base.map(\.hit) == [true, false])

    let mid = SymbolQuery.split("ETHFI", highlight: 3 ..< 5, offset: 0)
    #expect(mid.map(\.text) == ["ETH", "FI"])
    #expect(mid.map(\.hit) == [false, true])

    // quote 段：高亮 5..<8 落在 offset 5 的 "USDT" 上
    let quote = SymbolQuery.split("USDT", highlight: 5 ..< 8, offset: 5)
    #expect(quote.map(\.text) == ["USD", "T"])
    #expect(quote.map(\.hit) == [true, false])

    // 区间完全不搭界 → 整段不高亮
    #expect(SymbolQuery.split("USDT", highlight: 0 ..< 3, offset: 5).map(\.hit) == [false])
    #expect(SymbolQuery.split("USDT", highlight: nil, offset: 0).map(\.hit) == [false])
  }

  @Test("带横杠的代号：BTC-USD / BTC/USD / btcusd 都搜得到，且算完全命中")
  func dashedSymbols() {
    let spot = SymbolInfo(symbol: "coinbase/spot/BTC-USD", base: "BTC", quote: "USD",
                          pricePrecision: 2, tickSize: 0.01, underlyingType: "COIN")
    for q in ["BTC-USD", "BTC/USD", "btcusd"] {
      #expect(SymbolQuery.match(spot, query: SymbolQuery.normalize(q))?.tier == .exact)
    }
    // 计价那一段的高亮落在去掉横杠之后的位置（BTC 3 位，USD 从 3 起）。
    #expect(SymbolQuery.match(spot, query: "USD")?.highlight == 3 ..< 6)
  }
}

