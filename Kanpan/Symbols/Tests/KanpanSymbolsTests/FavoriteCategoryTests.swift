import Foundation
import Testing
import KanpanCore
@testable import KanpanSymbols

@Suite("收藏自动分类")
struct FavoriteCategoryTests {
  @Test func metadataAndFallback() {
    func name(_ base: String, _ type: String?) -> String {
      FavoriteCategory.name(symbol: base + "USDT", info: SymbolInfo(symbol: base + "USDT", base: base, pricePrecision: 2, tickSize: 0.01, underlyingType: type))
    }
    #expect(name("BTC", nil) == "加密")
    #expect(name("NEWCOIN", "COIN") == "加密")
    #expect(name("MRVL", "EQUITY") == "美股")
    #expect(name("SKHYNIX", "KR_EQUITY") == "美股")
    #expect(name("XAG", "COMMODITY") == "贵金属")
    #expect(name("CL", "COMMODITY") == "其他")
    #expect(name("UNKNOWN", nil) == "其他")
    #expect(name("HKSTOCK", "HK_EQUITY") == "其他")
  }
  @Test @MainActor func autoCreateReuseManualMoveAndReload() throws {
    let memory = MemoryPrefsStorage(), store = SymbolPrefsStore(storage: memory)
    let model = SymbolPickerModel(store: store)
    // 「他停在哪一类」2026-09-19 搬去了 `Prefs.favoritesGroup`，这个包看不见设置包，
    // 所以是宿主灌一个读法进来（真接线在 `AppAccountBridge.init`）。
    var selected: String? = nil
    model.selectedGroupSource = { selected }
    model.addFavorite("BTCUSDT"); model.addFavorite("ETHUSDT")
    #expect(model.prefs.groups.map(\.name) == ["加密"])
    let customID = model.createGroup("长期")
    let custom = try #require(customID)
    model.assign("BTCUSDT", to: custom); selected = custom
    model.addFavorite("BTCUSDT") // 重复收藏不覆盖用户选择、不复制品种。
    model.addFavorite("MYSTERYUSDT")
    #expect(model.prefs.groups.map(\.name) == ["加密", "长期", "其他"])
    let reloaded = SymbolPickerModel(store: store)
    #expect(reloaded.prefs.groupForSymbol["BTCUSDT"] == custom)
    #expect(reloaded.prefs.favorites == ["BTCUSDT", "ETHUSDT", "MYSTERYUSDT"])
  }
}
