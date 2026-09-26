import Testing
import KanpanCore
@testable import Kanpan

@MainActor @Suite("Exchange sectors are independent of favorites")
struct MarketSectorTests {
  @Test func combinedFiltersNeverMoveFolders() async {
    let info = [
      SymbolInfo(symbol: "binance/usd_m/BTCUSDT", base: "BTC", pricePrecision: 2, tickSize: 0.1, underlyingType: "COIN", underlyingSubTypes: ["Crypto", "PoW"]),
      SymbolInfo(symbol: "binance/usd_m/ETHUSDT", base: "ETH", pricePrecision: 2, tickSize: 0.01, underlyingType: "COIN", underlyingSubTypes: ["Crypto", "Layer-1"]),
      SymbolInfo(symbol: "binance/usd_m/SNDKUSDT", base: "SNDK", pricePrecision: 2, tickSize: 0.01, underlyingType: "EQUITY", underlyingSubTypes: ["TradFi"]),
      SymbolInfo(symbol: "binance/usd_m/NEWUSDT", base: "NEW", pricePrecision: 2, tickSize: 0.01, underlyingType: "NEW_TYPE", underlyingSubTypes: ["NewSector"])]
    let store = SymbolPrefsStore(storage: MemoryPrefsStorage(), key: "sector")
    store.save(SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT", "binance/usd_m/SNDKUSDT"]))
    let model = SymbolPickerModel(catalog: info, store: store)
    let prefs = model.prefs
    #expect(model.markets == ["crypto", "us", "other"])
    model.marketFilter = "crypto"
    #expect(model.sectors == ["layer-1", "pow"])
    model.sectorFilter = "pow"
    #expect(model.sections.flatMap(\.rows).map(\.id) == ["binance/usd_m/BTCUSDT"])
    model.query = "eth"
    await model.settleSearch()
    #expect(model.isEmpty)
    model.marketFilter = "us"
    #expect(model.sectorFilter == nil)
    model.query = ""
    #expect(model.sections.flatMap(\.rows).map(\.id) == ["binance/usd_m/SNDKUSDT"])
    #expect(model.prefs == prefs)
    #expect(MarketSector.tags(info[3]) == ["newsector"])
  }
}
