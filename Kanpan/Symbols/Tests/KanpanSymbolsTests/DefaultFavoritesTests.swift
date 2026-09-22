import Foundation
import Testing
import KanpanCore

@testable import KanpanSymbols

/// 方案第 3 节第四件：第一次启动给的那几条自选。
@Suite("默认自选")
struct DefaultFavoritesTests {
  /// 目录里掺上几个**不是币**的合约：美股、黄金、指数。它们在真实的成交额榜上
  /// 常年排在前面，正是这条规则要挡掉的（记忆 kanpan-not-every-contract-is-a-coin）。
  private static let mixedCatalog: [SymbolInfo] = SymbolFixtures.catalog + [
    SymbolInfo(symbol: "binance/usd_m/TSLAUSDT", base: "TSLA", pricePrecision: 2, tickSize: 0.01,
               underlyingType: "STOCK"),
    SymbolInfo(symbol: "binance/usd_m/XAUUSDT", base: "XAU", pricePrecision: 2, tickSize: 0.01,
               underlyingType: "COMMODITY"),
    // 字段缺了的：分类那一层不猜，所以它也不算币。
    SymbolInfo(symbol: "binance/usd_m/MYSTERYUSDT", base: "MYSTERY", pricePrecision: 2, tickSize: 0.01),
  ]

  private static let mixedTickers: [Ticker] = SymbolFixtures.tickers + [
    Ticker(symbol: "binance/usd_m/TSLAUSDT", last: 410, changePercent: 2, high: 420, low: 400, quoteVolume: 9.9e10),
    Ticker(symbol: "binance/usd_m/XAUUSDT", last: 3300, changePercent: 0.2, high: 3310, low: 3290, quoteVolume: 8.8e10),
    Ticker(symbol: "binance/usd_m/MYSTERYUSDT", last: 1, changePercent: 0, high: 1, low: 1, quoteVolume: 7.7e10),
  ]

  @Test("三个锚在前，后面跟成交额前五")
  func anchorsThenHot() {
    let picked = DefaultFavorites.pick(catalog: SymbolFixtures.catalog, tickers: SymbolFixtures.tickers)
    #expect(picked.prefix(3) == ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT", "binance/usd_m/SOLUSDT"])
    #expect(picked.count == 8)
    // 锚之外按成交额降序：BNB 6.4e8 > XRP 5.92e8 > DOGE 4.03e8 > 1000PEPE 2.88e8 > AVAX 1.02e8
    #expect(Array(picked.dropFirst(3)) == ["binance/usd_m/BNBUSDT", "binance/usd_m/XRPUSDT", "binance/usd_m/DOGEUSDT", "binance/usd_m/1000PEPEUSDT", "binance/usd_m/AVAXUSDT"])
  }

  @Test("美股、黄金、以及没标品种类型的合约都不算币")
  func noneCoinContractsAreExcluded() {
    let picked = DefaultFavorites.pick(catalog: Self.mixedCatalog, tickers: Self.mixedTickers)
    #expect(!picked.contains("binance/usd_m/TSLAUSDT"))
    #expect(!picked.contains("binance/usd_m/XAUUSDT"))
    #expect(!picked.contains("binance/usd_m/MYSTERYUSDT"))
    #expect(picked.count == 8)
  }

  @Test("同一个币的多条合约只占一行，倍数前缀也算同一个币")
  func dedupesByCoin() {
    let catalog = SymbolFixtures.catalog + [
      SymbolInfo(symbol: "binance/usd_m/BTCUSDC", base: "BTC", quote: "USDC", pricePrecision: 2, tickSize: 0.1,
                 underlyingType: "COIN"),
      SymbolInfo(symbol: "binance/usd_m/PEPEUSDT", base: "PEPE", pricePrecision: 7, tickSize: 0.0000001,
                 underlyingType: "COIN"),
    ]
    let tickers = SymbolFixtures.tickers + [
      Ticker(symbol: "binance/usd_m/BTCUSDC", last: 76_800, changePercent: 1, high: 1, low: 1, quoteVolume: 1.0e8),
      Ticker(symbol: "binance/usd_m/PEPEUSDT", last: 0.0000074, changePercent: -1, high: 1, low: 1, quoteVolume: 3.0e8),
    ]
    let picked = DefaultFavorites.pick(catalog: catalog, tickers: tickers)
    #expect(picked.filter { InstrumentID($0).symbol.hasPrefix("BTC") } == ["binance/usd_m/BTCUSDT"])   // 成交额大的那条留下
    // PEPE 与 1000PEPE 是同一个币：只留成交额大的 PEPEUSDT（3.0e8 > 2.88e8）
    #expect(picked.filter { $0.contains("PEPE") } == ["binance/usd_m/PEPEUSDT"])
    #expect(Set(picked).count == picked.count)
  }

  @Test("行情取不到时至少还有三个锚")
  func anchorsSurviveWithoutTickers() {
    #expect(DefaultFavorites.pick(catalog: SymbolFixtures.catalog, tickers: []) ==
            ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT", "binance/usd_m/SOLUSDT"])
  }

  @Test("已下架的合约不进默认自选")
  func skipsDelisted() {
    let catalog = SymbolFixtures.catalog.map { info -> SymbolInfo in
      guard info.base == "BNB" else { return info }
      var copy = info
      copy.status = .delisted
      return copy
    }
    let picked = DefaultFavorites.pick(catalog: catalog, tickers: SymbolFixtures.tickers)
    #expect(!picked.contains("binance/usd_m/BNBUSDT"))
    #expect(picked.count == 8)   // 少一条就往下顺一条
  }

  @Test("目录还没加载出来时什么都不给")
  func emptyCatalogGivesNothing() {
    #expect(DefaultFavorites.pick(catalog: [], tickers: SymbolFixtures.tickers).isEmpty)
  }
}
