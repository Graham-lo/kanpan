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
    // 交易所没说 `underlyingType` 就是**不知道**（审查 B-04）：不再按代号白名单
    // 把 BTC 猜成「加密」——猜错的代价不对称，一个新上的股票代号只要没进白名单
    // 就会被塞进加密分类里。`knows` 说不知道时，调用方不拿这个名字（见下一条用例）。
    #expect(FavoriteCategory.knows(symbol: "BTCUSDT", info: nil) == false)
    #expect(name("BTC", nil) == "其他")
    #expect(name("NEWCOIN", "COIN") == "加密")
    #expect(FavoriteCategory.knows(symbol: "BTCUSDT",
                                   info: SymbolInfo(symbol: "BTCUSDT", base: "BTC",
                                                    pricePrecision: 2, tickSize: 0.01,
                                                    underlyingType: "COIN")))
    // 例外只有 ISO 资产代码认出来的贵金属，那不是猜代号。
    #expect(FavoriteCategory.knows(symbol: "XAUUSDT", info: nil))
    #expect(name("XAU", nil) == "贵金属")
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
    // 真实路径上星星按在品种行上，那一行的事实是跟着 `info:` 一起递进来的。
    func coin(_ symbol: String) -> SymbolInfo {
      SymbolInfo(symbol: symbol, base: String(symbol.dropLast(4)),
                 pricePrecision: 2, tickSize: 0.01, underlyingType: "COIN")
    }
    model.addFavorite("BTCUSDT", info: coin("BTCUSDT"))
    model.addFavorite("ETHUSDT", info: coin("ETHUSDT"))
    #expect(model.prefs.groups.map(\.name) == ["加密"])
    let customID = model.createGroup("长期")
    let custom = try #require(customID)
    model.assign("BTCUSDT", to: custom); selected = custom
    model.addFavorite("BTCUSDT", info: coin("BTCUSDT")) // 重复收藏不覆盖用户选择、不复制品种。
    // 目录里没有这一行、也没人告诉我们它是什么：不编分类（审查 B-04），
    // 就留在他此刻看的那一类里——不新建「其他」，也不让它落进看不见的那一格。
    model.addFavorite("MYSTERYUSDT")
    #expect(model.prefs.groups.map(\.name) == ["加密", "长期"])
    #expect(model.prefs.groupForSymbol["MYSTERYUSDT"] == custom)
    let reloaded = SymbolPickerModel(store: store)
    #expect(reloaded.prefs.groupForSymbol["BTCUSDT"] == custom)
    #expect(reloaded.prefs.favorites == ["BTCUSDT", "ETHUSDT", "MYSTERYUSDT"])
  }
}
