import Foundation
import Testing
import KanpanCore
import KanpanNetwork

@testable import Kanpan

/// 方案第 3 节第四件：默认自选（2026-10-07 用户定的名单，访客与账号一样）。
@Suite("默认自选")
struct DefaultFavoritesTests {
  private static func perp(_ base: String) -> String { "binance/usd_m/\(base)USDT" }
  private static func spot(_ base: String) -> String { "coinbase/spot/\(base)-USD" }

  /// (base, underlyingType, 24h 成交额)。
  private static let extraRaw: [(String, String?, Double)] = [
    ("ZEC", "COIN", 3.0e8),
    ("XAU", "COMMODITY", 8.8e10),
    ("XAG", "COMMODITY", 2.0e9),
    ("NVDA", "EQUITY", 5.0e8), ("QQQ", "EQUITY", 4.0e8), ("SOXL", "EQUITY", 1.0e8),
    ("SKHY", "EQUITY", 9.0e7), ("SKHYNIX", "KR_EQUITY", 8.0e7), ("MU", "EQUITY", 7.0e7),
    ("SNDK", "EQUITY", 6.0e7), ("MRVL", "EQUITY", 5.0e7), ("ARM", "EQUITY", 4.0e7),
    ("SPCX", "EQUITY", 3.0e7), ("INTC", "EQUITY", 2.0e7), ("AVGO", "EQUITY", 1.0e7),
    // 成交额榜上常年排在前面的非币：只能靠点名进来，不能靠成交额挤进「加密」。
    ("TSLA", "EQUITY", 9.9e10),
    ("CL", "COMMODITY", 9.0e10),
    // 字段缺了的：分类那一层不猜，所以它也不算币。
    ("MYSTERY", nil, 7.7e10),
  ]

  static let catalog: [SymbolInfo] = SymbolFixtures.catalog + extraRaw.map {
    SymbolInfo(symbol: perp($0.0), base: $0.0, pricePrecision: 2, tickSize: 0.01, underlyingType: $0.1)
  }

  static let tickers: [Ticker] = SymbolFixtures.tickers + extraRaw.map {
    Ticker(symbol: perp($0.0), last: 1, changePercent: 0, high: 1, low: 1, quoteVolume: $0.2)
  }

  static let usOrder = ["NVDA", "QQQ", "SOXL", "SKHY", "SKHYNIX", "MU", "SNDK", "MRVL", "ARM", "SPCX", "INTC", "AVGO"]

  private func crypto(_ plan: [DefaultFavorites.Entry]) -> [String] {
    plan.filter { $0.group == DefaultFavorites.cryptoGroup }.map(\.symbol)
  }
  private func us(_ plan: [DefaultFavorites.Entry]) -> [String] {
    plan.filter { $0.group == DefaultFavorites.usGroup }.map(\.symbol)
  }

  @Test("「加密」：金银在最上面，六个币各是 Coinbase 现货在前、永续紧跟，再跟成交额前五")
  func cryptoOrder() {
    let plan = DefaultFavorites.pick(catalog: Self.catalog, tickers: Self.tickers)
    let pairs = ["BTC", "ETH", "SOL", "XRP", "DOGE", "ZEC"].flatMap { [Self.spot($0), Self.perp($0)] }
    // 剩下的币按成交额：BNB 6.4e8 > 1000PEPE 2.88e8 > AVAX 1.02e8 > BCH 9.3e7 > LTC 8.8e7（ETHFI、ETHW 落榜）
    let hot = ["binance/usd_m/BNBUSDT", "binance/usd_m/1000PEPEUSDT", "binance/usd_m/AVAXUSDT",
               "binance/usd_m/BCHUSDT", "binance/usd_m/LTCUSDT"]
    #expect(crypto(plan) == [Self.perp("XAU"), Self.perp("XAG")] + pairs + hot)
    // 整份计划里「加密」在前、「美股」在后（新档案上两类按这个先后开出来）。
    #expect(plan.prefix(crypto(plan).count).allSatisfy { $0.group == DefaultFavorites.cryptoGroup })
  }

  @Test("「美股」按点名顺序，韩股 SKHYNIX 也在")
  func usOrder() {
    let plan = DefaultFavorites.pick(catalog: Self.catalog, tickers: Self.tickers)
    #expect(us(plan) == Self.usOrder.map(Self.perp))
  }

  @Test("目录里没有、或者已下架的美股就跳过")
  func usSkipsMissingAndDelisted() {
    let catalog = Self.catalog.compactMap { info -> SymbolInfo? in
      if info.base == "SPCX" { return nil }
      guard info.base == "ARM" else { return info }
      var copy = info
      copy.status = .delisted
      return copy
    }
    let plan = DefaultFavorites.pick(catalog: catalog, tickers: Self.tickers)
    #expect(us(plan) == Self.usOrder.filter { $0 != "SPCX" && $0 != "ARM" }.map(Self.perp))
  }

  @Test("成交额榜只认币：美股、原油、没标类型的都挤不进「加密」")
  func hotListIsCoinsOnly() {
    let plan = DefaultFavorites.pick(catalog: Self.catalog, tickers: Self.tickers)
    let symbols = plan.map(\.symbol)
    #expect(!symbols.contains(Self.perp("TSLA")))
    #expect(!symbols.contains(Self.perp("CL")))
    #expect(!symbols.contains(Self.perp("MYSTERY")))
    // 「加密」里除了点名的金银，其余都是币或 Coinbase 现货。
    for symbol in crypto(plan) where !symbol.hasPrefix("coinbase/") {
      guard let info = Self.catalog.first(where: { $0.symbol == symbol }) else { Issue.record("\(symbol) 不在目录里"); continue }
      let asset = SymbolClassifier.classify(info).asset
      #expect(asset == .crypto || ["XAU", "XAG"].contains(info.base), "\(symbol) 不是币")
    }
  }

  @Test("同一个币的多条合约只占一行，倍数前缀也算同一个币；点名的币不再从榜上重复进")
  func dedupesByCoin() {
    let catalog = Self.catalog + [
      SymbolInfo(symbol: "binance/usd_m/BTCUSDC", base: "BTC", quote: "USDC", pricePrecision: 2, tickSize: 0.1,
                 underlyingType: "COIN"),
      SymbolInfo(symbol: "binance/usd_m/PEPEUSDT", base: "PEPE", pricePrecision: 7, tickSize: 0.0000001,
                 underlyingType: "COIN"),
    ]
    let tickers = Self.tickers + [
      // BTCUSDC 成交额再大也只是同一个币的另一条合约：不进榜、不顶掉 BTCUSDT。
      Ticker(symbol: "binance/usd_m/BTCUSDC", last: 76_800, changePercent: 1, high: 1, low: 1, quoteVolume: 1.0e8),
      Ticker(symbol: "binance/usd_m/PEPEUSDT", last: 0.0000074, changePercent: -1, high: 1, low: 1, quoteVolume: 3.0e8),
    ]
    let symbols = DefaultFavorites.pick(catalog: catalog, tickers: tickers).map(\.symbol)
    #expect(symbols.filter { $0.hasPrefix("binance/usd_m/BTC") } == ["binance/usd_m/BTCUSDT"])
    // PEPE 与 1000PEPE 是同一个币：只留成交额大的 PEPEUSDT（3.0e8 > 2.88e8）
    #expect(symbols.filter { $0.contains("PEPE") } == ["binance/usd_m/PEPEUSDT"])
    #expect(Set(symbols).count == symbols.count)
  }

  @Test("整份计划没有重复")
  func noDuplicates() {
    let symbols = DefaultFavorites.pick(catalog: Self.catalog, tickers: Self.tickers).map(\.symbol)
    #expect(Set(symbols).count == symbols.count)
    #expect(symbols.count == 2 + 12 + 5 + 12)
  }

  @Test("行情取不到时点名的那几条照给，只少了成交额前五")
  func namedSurviveWithoutTickers() {
    let plan = DefaultFavorites.pick(catalog: Self.catalog, tickers: [])
    let pairs = ["BTC", "ETH", "SOL", "XRP", "DOGE", "ZEC"].flatMap { [Self.spot($0), Self.perp($0)] }
    #expect(crypto(plan) == [Self.perp("XAU"), Self.perp("XAG")] + pairs)
    #expect(us(plan) == Self.usOrder.map(Self.perp))
  }

  @Test("币安没有那个币的永续时，Coinbase 现货照给")
  func spotWithoutPerp() {
    let catalog = Self.catalog.filter { $0.base != "ZEC" }
    let plan = DefaultFavorites.pick(catalog: catalog, tickers: Self.tickers)
    let symbols = crypto(plan)
    #expect(!symbols.contains(Self.perp("ZEC")))
    #expect(symbols.contains(Self.spot("ZEC")))
    // ZEC 那一格空出来不让给成交额榜：榜上仍是五条。
    #expect(symbols.count == 2 + 11 + 5)
  }

  @Test("已下架的合约不进默认自选，榜上往下顺一条")
  func skipsDelisted() {
    let catalog = Self.catalog.map { info -> SymbolInfo in
      guard info.base == "BNB" else { return info }
      var copy = info
      copy.status = .delisted
      return copy
    }
    let symbols = crypto(DefaultFavorites.pick(catalog: catalog, tickers: Self.tickers))
    #expect(!symbols.contains("binance/usd_m/BNBUSDT"))
    #expect(symbols.suffix(5).contains("binance/usd_m/ETHFIUSDT"))
  }

  @Test("Coinbase 现货的键用交易所自己的口径，服务端认")
  func coinbaseKey() {
    #expect(DefaultFavorites.usdSpot("btc") == "coinbase/spot/BTC-USD")
    #expect(InstrumentID.isSyncKey(DefaultFavorites.usdSpot("ZEC") ?? ""))
    #expect(VenueRegistry.descriptor(forSymbol: DefaultFavorites.usdSpot("BTC") ?? "").id == CoinbaseProvider.venue)
    #expect(DefaultFavorites.usdSpotVenue?.id == CoinbaseProvider.venue)
    #expect(FavoriteSiblings.spotMarket == CoinbaseProvider.market)
  }

  @Test("目录还没加载出来时什么都不给")
  func emptyCatalogGivesNothing() {
    #expect(DefaultFavorites.pick(catalog: [], tickers: Self.tickers).isEmpty)
  }
}

/// `SymbolPickerModel.seedFavorites`：默认名单并进已有的档案。
@Suite("默认自选并进档案")
@MainActor
struct DefaultFavoritesSeedTests {
  private typealias Entry = DefaultFavorites.Entry
  private static let crypto = DefaultFavorites.cryptoGroup
  private static let us = DefaultFavorites.usGroup

  private func make(_ prefs: SymbolPrefs = SymbolPrefs()) -> (SymbolPickerModel, MemoryPrefsStorage) {
    let storage = MemoryPrefsStorage()
    let store = SymbolPrefsStore(storage: storage, key: "t")
    store.save(prefs)
    let model = SymbolPickerModel(catalog: DefaultFavoritesTests.catalog, tickers: DefaultFavoritesTests.tickers,
                                  store: store,
                                  venueCategory: { VenueRegistry.descriptor(forSymbol: $0).favoriteCategory })
    return (model, storage)
  }

  private func groupID(_ model: SymbolPickerModel, _ name: String) -> String? {
    model.prefs.groups.first { $0.name == name }?.id
  }

  @Test("空档案：先开「加密」再开「美股」，成员和顺序都照名单")
  func emptyProfile() throws {
    let (model, storage) = make()
    let plan = DefaultFavorites.pick(catalog: DefaultFavoritesTests.catalog, tickers: DefaultFavoritesTests.tickers)
    let added = model.seedFavorites(plan)
    #expect(added == plan.map(\.symbol))
    #expect(model.prefs.favorites == plan.map(\.symbol))
    #expect(model.prefs.groups.map(\.name) == [Self.crypto, Self.us])
    let cryptoID = try #require(groupID(model, Self.crypto))
    let usID = try #require(groupID(model, Self.us))
    #expect(model.prefs.favorites(in: cryptoID) == plan.filter { $0.group == Self.crypto }.map(\.symbol))
    #expect(model.prefs.favorites(in: usID) == plan.filter { $0.group == Self.us }.map(\.symbol))
    #expect(model.prefs.favorites.first == "binance/usd_m/XAUUSDT")
    // 落了盘。
    #expect(SymbolPrefsStore(storage: storage, key: "t").load() == model.prefs)
    // Coinbase 现货明着归进了「加密」：补分类那一趟不会再把它挪去交易所自己那一类。
    #expect(model.classifyArrivals() == false)
    #expect(model.prefs.groupForSymbol["coinbase/spot/BTC-USD"] == cryptoID)
    #expect(model.prefs.groups.count == 2)
  }

  @Test("已有自选：只插缺的，插在名单里前一条的后面；已有的位置和分类都不动；再来一次什么都不变")
  func mergesIntoExisting() throws {
    let mine = FavoriteGroup(id: "g-mine", name: "短线")
    let prefs = SymbolPrefs(favorites: ["binance/usd_m/BNBUSDT", "binance/usd_m/ETHUSDT", "binance/usd_m/NVDAUSDT"],
                            groups: [mine],
                            groupForSymbol: ["binance/usd_m/BNBUSDT": mine.id, "binance/usd_m/ETHUSDT": mine.id,
                                             "binance/usd_m/NVDAUSDT": mine.id])
    let (model, _) = make(prefs)
    let plan = [
      Entry(symbol: "binance/usd_m/XAUUSDT", group: Self.crypto),
      Entry(symbol: "coinbase/spot/BTC-USD", group: Self.crypto),
      Entry(symbol: "binance/usd_m/BTCUSDT", group: Self.crypto),
      Entry(symbol: "binance/usd_m/ETHUSDT", group: Self.crypto),
      Entry(symbol: "coinbase/spot/ETH-USD", group: Self.crypto),
      Entry(symbol: "binance/usd_m/BNBUSDT", group: Self.crypto),
      Entry(symbol: "binance/usd_m/NVDAUSDT", group: Self.us),
      Entry(symbol: "binance/usd_m/QQQUSDT", group: Self.us),
    ]
    let added = model.seedFavorites(plan)
    #expect(added == ["binance/usd_m/XAUUSDT", "coinbase/spot/BTC-USD", "binance/usd_m/BTCUSDT",
                      "coinbase/spot/ETH-USD", "binance/usd_m/QQQUSDT"])
    // ETH 现货插在他那条 ETH 永续后面，再按「现货在前」站成现货、永续（两条挨着，类别不变）。
    #expect(model.prefs.favorites == [
      "binance/usd_m/XAUUSDT", "coinbase/spot/BTC-USD", "binance/usd_m/BTCUSDT",
      "binance/usd_m/BNBUSDT", "coinbase/spot/ETH-USD", "binance/usd_m/ETHUSDT",
      "binance/usd_m/NVDAUSDT", "binance/usd_m/QQQUSDT",
    ])
    // 他自己的那一类排第一不动，新开的两类跟在后面。
    #expect(model.prefs.groups.map(\.name) == ["短线", Self.crypto, Self.us])
    let cryptoID = try #require(groupID(model, Self.crypto))
    let usID = try #require(groupID(model, Self.us))
    for symbol in ["binance/usd_m/BNBUSDT", "binance/usd_m/ETHUSDT", "binance/usd_m/NVDAUSDT"] {
      #expect(model.prefs.groupForSymbol[symbol] == mine.id, "\(symbol) 被挪出了他自己的分类")
    }
    #expect(model.prefs.favorites(in: cryptoID) == ["binance/usd_m/XAUUSDT", "coinbase/spot/BTC-USD",
                                                    "binance/usd_m/BTCUSDT", "coinbase/spot/ETH-USD"])
    #expect(model.prefs.favorites(in: usID) == ["binance/usd_m/QQQUSDT"])

    let before = model.prefs
    #expect(model.seedFavorites(plan).isEmpty)
    #expect(model.prefs == before)
  }

  @Test("已经有「加密」「美股」就用那两格，不再开同名的")
  func reusesSameNamedGroups() throws {
    let crypto = FavoriteGroup(id: "g-c", name: Self.crypto)
    let us = FavoriteGroup(id: "g-u", name: Self.us)
    let prefs = SymbolPrefs(favorites: ["binance/usd_m/SOLUSDT"], groups: [us, crypto],
                            groupForSymbol: ["binance/usd_m/SOLUSDT": crypto.id])
    let (model, _) = make(prefs)
    let plan = DefaultFavorites.pick(catalog: DefaultFavoritesTests.catalog, tickers: DefaultFavoritesTests.tickers)
    let added = model.seedFavorites(plan)
    #expect(added.count == plan.count - 1)
    #expect(model.prefs.groups == [us, crypto])
    #expect(model.prefs.favorites == plan.map(\.symbol))
    #expect(model.prefs.favorites(in: crypto.id) == plan.filter { $0.group == Self.crypto }.map(\.symbol))
    #expect(model.prefs.favorites(in: us.id) == plan.filter { $0.group == Self.us }.map(\.symbol))
  }

  @Test("空名单什么都不做")
  func emptyPlan() {
    let (model, _) = make(SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT"]))
    let before = model.prefs
    #expect(model.seedFavorites([]).isEmpty)
    #expect(model.prefs == before)
  }
}
