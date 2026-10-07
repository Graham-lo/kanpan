import Foundation
import Testing
import KanpanCore
import KanpanNetwork

@testable import Kanpan

/// 加自选时同一个品种的几条挨着放、现货在前（用户 2026-10-07 定的，方便对比）。
@Suite("自选：同品种挨着放")
@MainActor
struct FavoriteSiblingsTests {
  private static let perpBTC = "binance/usd_m/BTCUSDT"
  private static let spotBTC = "coinbase/spot/BTC-USD"
  private static let perpETH = "binance/usd_m/ETHUSDT"
  private static let spotETH = "coinbase/spot/ETH-USD"
  private static let perpSOL = "binance/usd_m/SOLUSDT"
  private static let perpPEPE = "binance/usd_m/1000PEPEUSDT"

  private static let catalog: [SymbolInfo] = [
    SymbolInfo(symbol: perpBTC, base: "BTC", pricePrecision: 1, tickSize: 0.1, underlyingType: "COIN"),
    SymbolInfo(symbol: perpETH, base: "ETH", pricePrecision: 2, tickSize: 0.01, underlyingType: "COIN"),
    SymbolInfo(symbol: perpSOL, base: "SOL", pricePrecision: 2, tickSize: 0.01, underlyingType: "COIN"),
    SymbolInfo(symbol: perpPEPE, base: "1000PEPE", pricePrecision: 7, tickSize: 0.0000001, underlyingType: "COIN"),
    SymbolInfo(symbol: spotBTC, base: "BTC", quote: "USD", pricePrecision: 2, tickSize: 0.01),
    SymbolInfo(symbol: spotETH, base: "ETH", quote: "USD", pricePrecision: 2, tickSize: 0.01),
  ]

  private func make(_ prefs: SymbolPrefs, catalog: [SymbolInfo] = FavoriteSiblingsTests.catalog)
    -> (SymbolPickerModel, MemoryPrefsStorage) {
    let storage = MemoryPrefsStorage()
    let store = SymbolPrefsStore(storage: storage, key: "t")
    store.save(prefs)
    let model = SymbolPickerModel(catalog: catalog, tickers: [], store: store,
                                  venueCategory: { VenueRegistry.descriptor(forSymbol: $0).favoriteCategory })
    return (model, storage)
  }

  // ------------------------------------------------------------ 纯逻辑

  @Test("底层名：目录里按目录，没有就按代号拆；倍数前缀算同一个币")
  func base() {
    #expect(FavoriteSiblings.base(of: Self.spotBTC, info: nil) == "BTC")
    #expect(FavoriteSiblings.base(of: Self.perpBTC, info: nil) == "BTC")
    #expect(FavoriteSiblings.base(of: Self.perpPEPE, info: nil) == "PEPE")
    #expect(FavoriteSiblings.base(of: "macro/index/DXY", info: nil) == "DXY")
    let info = SymbolInfo(symbol: "binance/usd_m/XYZUSDT", base: "ABC", pricePrecision: 1, tickSize: 0.1)
    #expect(FavoriteSiblings.base(of: "binance/usd_m/XYZUSDT", info: info) == "ABC")
  }

  @Test("插位：现货插在第一条同品种前面，永续插在最后一条后面，没有同品种就不管")
  func insertion() {
    let favs = [Self.perpSOL, Self.perpBTC, "binance/usd_m/BTCUSDC", Self.perpETH]
    let baseOf: (String) -> String = { FavoriteSiblings.base(of: $0, info: nil) }
    let spot = FavoriteSiblings.insertion(of: Self.spotBTC, base: "BTC", in: favs, baseOf: baseOf)
    #expect(spot?.index == 1 && spot?.neighbor == Self.perpBTC)
    let perp = FavoriteSiblings.insertion(of: "binance/coin_m/BTCUSD_PERP", base: "BTC", in: favs, baseOf: baseOf)
    #expect(perp?.index == 3 && perp?.neighbor == "binance/usd_m/BTCUSDC")
    #expect(FavoriteSiblings.insertion(of: Self.spotETH, base: "ETH", in: favs, baseOf: baseOf)?.index == 3)
    #expect(FavoriteSiblings.insertion(of: "coinbase/spot/DOGE-USD", base: "DOGE", in: favs, baseOf: baseOf) == nil)
    // 自己已经在表里不算同品种。
    #expect(FavoriteSiblings.insertion(of: Self.perpSOL, base: "SOL", in: favs, baseOf: baseOf) == nil)
  }

  @Test("现货在前：只重排挨在一起的同品种，拆开摆的不碰，同档相对顺序不变")
  func spotFirst() {
    let baseOf: (String) -> String = { FavoriteSiblings.base(of: $0, info: nil) }
    let favs = [Self.perpBTC, "binance/usd_m/BTCUSDC", Self.spotBTC, Self.perpSOL, Self.perpETH, Self.spotETH,
                "binance/usd_m/DOGEUSDT", Self.perpPEPE, "coinbase/spot/DOGE-USD"]
    #expect(FavoriteSiblings.spotFirst(favs, baseOf: baseOf) == [
      Self.spotBTC, Self.perpBTC, "binance/usd_m/BTCUSDC", Self.perpSOL, Self.spotETH, Self.perpETH,
      "binance/usd_m/DOGEUSDT", Self.perpPEPE, "coinbase/spot/DOGE-USD",
    ])
    let already = [Self.spotBTC, Self.perpBTC, Self.perpSOL]
    #expect(FavoriteSiblings.spotFirst(already, baseOf: baseOf) == already)
    #expect(FavoriteSiblings.spotFirst([], baseOf: baseOf) == [])
  }

  // ------------------------------------------------------------ 接进加自选

  @Test("自选里有币安 BTC 永续，再加 Coinbase 现货：插在它前面、归它那一类，不进 Coinbase 那一类")
  func spotJoinsPerp() throws {
    let mine = FavoriteGroup(id: "g-mine", name: "短线")
    let (model, storage) = make(SymbolPrefs(favorites: [Self.perpSOL, Self.perpBTC, Self.perpETH], groups: [mine],
                                            groupForSymbol: [Self.perpSOL: mine.id, Self.perpBTC: mine.id,
                                                             Self.perpETH: mine.id]))
    model.addFavorite(Self.spotBTC, info: model.info(for: Self.spotBTC))
    #expect(model.prefs.favorites == [Self.perpSOL, Self.spotBTC, Self.perpBTC, Self.perpETH])
    #expect(model.prefs.groupForSymbol[Self.spotBTC] == mine.id)
    #expect(model.prefs.groups == [mine], "不该为它开交易所自己那一类")
    #expect(SymbolPrefsStore(storage: storage, key: "t").load() == model.prefs)
    // 补分类那一趟也不会再把它挪走。
    #expect(model.classifyArrivals() == false)
    #expect(model.prefs.groupForSymbol[Self.spotBTC] == mine.id)
  }

  @Test("自选里有 Coinbase ETH 现货，再加币安永续：紧跟在它后面、同一类")
  func perpJoinsSpot() {
    let crypto = FavoriteGroup(id: "g-c", name: "加密")
    let (model, _) = make(SymbolPrefs(favorites: [Self.spotETH, Self.perpSOL], groups: [crypto],
                                      groupForSymbol: [Self.spotETH: crypto.id, Self.perpSOL: crypto.id]))
    model.addFavorite(Self.perpETH)
    #expect(model.prefs.favorites == [Self.spotETH, Self.perpETH, Self.perpSOL])
    #expect(model.prefs.groupForSymbol[Self.perpETH] == crypto.id)
  }

  @Test("星星一点也走同一条路；目录里没有那条时按代号拆也认得出同品种")
  func starWithoutCatalog() {
    let crypto = FavoriteGroup(id: "g-c", name: "加密")
    let (model, _) = make(SymbolPrefs(favorites: [Self.perpBTC, Self.perpSOL], groups: [crypto],
                                      groupForSymbol: [Self.perpBTC: crypto.id, Self.perpSOL: crypto.id]),
                          catalog: [])
    #expect(model.toggleFavorite(Self.spotBTC))
    #expect(model.prefs.favorites == [Self.spotBTC, Self.perpBTC, Self.perpSOL])
    #expect(model.prefs.groupForSymbol[Self.spotBTC] == crypto.id)
    // 再点一次移除，回到原样。
    #expect(!model.toggleFavorite(Self.spotBTC))
    #expect(model.prefs.favorites == [Self.perpBTC, Self.perpSOL])
  }

  @Test("没有同品种的照旧追加到最末、归此刻站着的那一类")
  func unrelatedAppends() {
    let crypto = FavoriteGroup(id: "g-c", name: "加密")
    let (model, _) = make(SymbolPrefs(favorites: [Self.spotBTC, Self.perpBTC], groups: [crypto],
                                      groupForSymbol: [Self.spotBTC: crypto.id, Self.perpBTC: crypto.id]))
    model.selectedGroupSource = { crypto.id }
    model.addFavorite(Self.perpSOL)
    #expect(model.prefs.favorites == [Self.spotBTC, Self.perpBTC, Self.perpSOL])
    #expect(model.prefs.groupForSymbol[Self.perpSOL] == crypto.id)
  }

  @Test("同品种被用户拆开摆着：现货还是插到第一条前面，永续插到最后一条后面")
  func splitSiblings() {
    let (model, _) = make(SymbolPrefs(favorites: [Self.perpBTC, Self.perpSOL, "binance/usd_m/BTCUSDC"]))
    model.addFavorite(Self.spotBTC)
    #expect(model.prefs.favorites == [Self.spotBTC, Self.perpBTC, Self.perpSOL, "binance/usd_m/BTCUSDC"])
  }

  @Test("默认名单并进来时把挨着的同品种站成现货在前，只有顺序变了也落盘")
  func seedReordersAdjacentSiblings() {
    let crypto = FavoriteGroup(id: "g-c", name: "加密")
    let (model, storage) = make(SymbolPrefs(favorites: [Self.perpBTC, Self.spotBTC, Self.perpSOL], groups: [crypto],
                                            groupForSymbol: [Self.perpBTC: crypto.id, Self.spotBTC: crypto.id,
                                                             Self.perpSOL: crypto.id]))
    let plan = [DefaultFavorites.Entry(symbol: Self.perpBTC, group: "加密"),
                DefaultFavorites.Entry(symbol: Self.spotBTC, group: "加密")]
    #expect(model.seedFavorites(plan).isEmpty)
    #expect(model.prefs.favorites == [Self.spotBTC, Self.perpBTC, Self.perpSOL])
    #expect(SymbolPrefsStore(storage: storage, key: "t").load().favorites == model.prefs.favorites)
  }
}
