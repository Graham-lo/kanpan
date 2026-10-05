import Foundation
import Testing
import KanpanCore
import KanpanNetwork

@testable import Kanpan

/// 美元指数（`macro/index/DXY`）作为一只普通品种：能搜、能加自选、进「指数」那一类。
@Suite("美元指数：搜索与自选")
struct DollarIndexSearchTests {
  private static let dxy = MacroProvider.builtinInstruments[0]
  private static let catalog: [SymbolInfo] = SymbolFixtures.catalog + [
    SymbolInfo(symbol: "binance/usd_m/USDCUSDT", base: "USDC", pricePrecision: 4, tickSize: 0.0001,
               underlyingType: "COIN"),
    SymbolInfo(symbol: "coinbase/spot/BTC-USD", base: "BTC", quote: "USD", pricePrecision: 2,
               tickSize: 0.01, underlyingType: "COIN"),
    dxy,
  ]

  @Test("美元 / 美指 / DXY / dxy / USD / 美元指数 都把美元指数排第一")
  func allQueriesPutDXYFirst() {
    for q in ["美元", "美指", "DXY", "dxy", "USD", "usd", "美元指数", " 美元指数 ", "$DXY"] {
      let hits = SymbolQuery.match(Self.catalog, query: q)
      #expect(hits.first?.id == "macro/index/DXY", "\(q)")
      #expect(hits.first?.tier == .exact, "\(q)")
    }
  }

  @Test("整词 USD：美元指数在最匹配那一档，USDC、xxxUSDT、BTC-USD 都在它后面")
  func usdRanksAheadOfStablecoinsAndUSDT() {
    let tickers = Dictionary(SymbolFixtures.tickers.map { ($0.symbol, $0) }, uniquingKeysWith: { a, _ in a })
    let sections = SymbolSections.build(catalog: Self.catalog, tickers: tickers, prefs: SymbolPrefs(), query: "USD")
    let ids = sections.first?.rows.map(\.id) ?? []
    #expect(ids.first == "macro/index/DXY")
    #expect(ids.contains("binance/usd_m/USDCUSDT") && ids.contains("binance/usd_m/BTCUSDT"))
    // 打「US」不算整词，不把美元指数顶上来（它也不含 US）。
    #expect(SymbolQuery.match(Self.dxy, query: "US") == nil)
  }

  @Test("拼音也认：meiyuan、my")
  func pinyin() {
    #expect(SymbolQuery.match(Self.dxy, query: "MEIYUAN")?.tier == .pinyinFull)
    #expect(SymbolQuery.match(Self.dxy, query: "MYZS")?.tier == .pinyinInitials)
  }

  @Test("行与小签：没有计价币就不写斜杠，小签写「指数」，中文名是「美元指数」")
  func rowDisplay() {
    let row = SymbolRow(match: SymbolMatch(info: Self.dxy))
    #expect(row.quoteSuffix == "")
    #expect(row.meta == "DXY 指数")
    #expect(Self.dxy.display == "DXY")
    #expect(SymbolAliases.names(base: "DXY").first == "美元指数")
    #expect(InstrumentID("macro/index/DXY").productLabel == "指数")
    #expect(SymbolInfo.placeholder(symbol: "macro/index/DXY").quote == "")
  }

  @Test("不在默认自选里；同步键服务端认")
  func notDefaultAndSyncable() {
    // 默认自选只从币里挑（`SymbolClassifier` 判成加密的）；美元指数是指数，挑不上。
    let picked = DefaultFavorites.pick(catalog: Self.catalog, tickers: SymbolFixtures.tickers)
    #expect(!picked.isEmpty && !picked.contains("macro/index/DXY"))
    #expect(InstrumentID.isSyncKey("macro/index/DXY"))
    #expect(VenueRegistry.descriptor(forSymbol: "macro/index/DXY").favoriteCategory == "指数")
  }

  @Test("加星进「指数」那一类，排在「美股」之后")
  @MainActor func favoriteGoesToIndexCategory() throws {
    let store = SymbolPrefsStore(storage: MemoryPrefsStorage())
    let model = SymbolPickerModel(store: store,
                                  venueCategory: { VenueRegistry.descriptor(forSymbol: $0).favoriteCategory })
    var selected: String? = nil
    model.selectedGroupSource = { selected }
    model.addFavorite("binance/usd_m/BTCUSDT", info: SymbolFixtures.info("binance/usd_m/BTCUSDT"))
    selected = try #require(model.createGroup("美股"))
    model.addFavorite("macro/index/DXY", info: Self.dxy)
    #expect(model.prefs.groups.map(\.name) == ["加密", "美股", "指数"])
    let own = try #require(model.prefs.groups.first { $0.name == "指数" }?.id)
    #expect(model.prefs.groupForSymbol["macro/index/DXY"] == own)
    #expect(model.prefs.favorites.contains("macro/index/DXY"))
  }

  @Test("自选里还没分类的币与美元指数：冷启动等目录到了再一起编，「指数」排在「加密」后面")
  @MainActor func unassignedSeedKeepsIndexAfterCrypto() {
    let store = SymbolPrefsStore(storage: MemoryPrefsStorage())
    store.save(SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT", "macro/index/DXY", "binance/usd_m/ETHUSDT"]))
    let model = SymbolPickerModel(store: store,
                                  venueCategory: { VenueRegistry.descriptor(forSymbol: $0).favoriteCategory })
    // 目录还没到：币认不出来，美元指数也不抢先开「指数」。
    #expect(model.prefs.groups.isEmpty)
    model.setCatalog(Self.catalog)
    #expect(model.prefs.groups.map(\.name) == ["加密", "指数"])
    let index = model.prefs.groups.first { $0.name == "指数" }?.id
    #expect(index != nil && model.prefs.groupForSymbol["macro/index/DXY"] == index)
  }
}
