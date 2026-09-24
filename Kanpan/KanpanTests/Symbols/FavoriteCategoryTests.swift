import Foundation
import Testing
import KanpanCore
@testable import Kanpan

@Suite("收藏自动分类")
struct FavoriteCategoryTests {
  @Test func metadataAndFallback() {
    func name(_ base: String, _ type: String?) -> String {
      FavoriteCategory.name(symbol: base + "USDT", info: SymbolInfo(symbol: base + "USDT", base: base, pricePrecision: 2, tickSize: 0.01, underlyingType: type))
    }
    // 交易所没说 `underlyingType` 就是**不知道**（审查 B-04）：不再按代号白名单
    // 把 BTC 猜成「加密」——猜错的代价不对称，一个新上的股票代号只要没进白名单
    // 就会被塞进加密分类里。`knows` 说不知道时，调用方不拿这个名字（见下一条用例）。
    #expect(FavoriteCategory.knows(symbol: "binance/usd_m/BTCUSDT", info: nil) == false)
    #expect(name("BTC", nil) == "其他")
    #expect(name("NEWCOIN", "COIN") == "加密")
    #expect(FavoriteCategory.knows(symbol: "binance/usd_m/BTCUSDT",
                                   info: SymbolInfo(symbol: "binance/usd_m/BTCUSDT", base: "BTC",
                                                    pricePrecision: 2, tickSize: 0.01,
                                                    underlyingType: "COIN")))
    // 例外只有 ISO 资产代码认出来的贵金属，那不是猜代号。
    #expect(FavoriteCategory.knows(symbol: "binance/usd_m/XAUUSDT", info: nil))
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
    model.addFavorite("binance/usd_m/BTCUSDT", info: coin("binance/usd_m/BTCUSDT"))
    model.addFavorite("binance/usd_m/ETHUSDT", info: coin("binance/usd_m/ETHUSDT"))
    #expect(model.prefs.groups.map(\.name) == ["加密"])
    let customID = model.createGroup("长期")
    let custom = try #require(customID)
    model.assign("binance/usd_m/BTCUSDT", to: custom); selected = custom
    model.addFavorite("binance/usd_m/BTCUSDT", info: coin("binance/usd_m/BTCUSDT")) // 重复收藏不覆盖用户选择、不复制品种。
    // 目录里没有这一行、也没人告诉我们它是什么：不编分类（审查 B-04），
    // 就留在他此刻看的那一类里——不新建「其他」，也不让它落进看不见的那一格。
    model.addFavorite("binance/usd_m/MYSTERYUSDT")
    #expect(model.prefs.groups.map(\.name) == ["加密", "长期"])
    #expect(model.prefs.groupForSymbol["binance/usd_m/MYSTERYUSDT"] == custom)
    let reloaded = SymbolPickerModel(store: store)
    #expect(reloaded.prefs.groupForSymbol["binance/usd_m/BTCUSDT"] == custom)
    #expect(reloaded.prefs.favorites == ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT", "binance/usd_m/MYSTERYUSDT"])
  }

  /// 别家交易所的品种固定进它自己那一类，排在「美股」之后；不跟着他此刻站着的那一类走，
  /// 默认交易所的品种照旧（交接 §2 拍板）。
  @Test @MainActor func venueFavoritesGoToTheirOwnCategoryAfterUSEquities() throws {
    let store = SymbolPrefsStore(storage: MemoryPrefsStorage())
    let venue: @Sendable (String) -> String? = { $0.hasPrefix("coinbase/") ? "Coinbase" : nil }
    let model = SymbolPickerModel(store: store, venueCategory: venue)
    var selected: String? = nil
    model.selectedGroupSource = { selected }
    func info(_ symbol: String, _ base: String, _ type: String) -> SymbolInfo {
      SymbolInfo(symbol: symbol, base: base, pricePrecision: 2, tickSize: 0.01, underlyingType: type)
    }
    model.addFavorite("binance/usd_m/BTCUSDT", info: info("binance/usd_m/BTCUSDT", "BTC", "COIN"))
    selected = try #require(model.createGroup("美股"))
    let mine = try #require(model.createGroup("长期"))
    selected = mine
    model.addFavorite("coinbase/spot/BTC-USD", info: info("coinbase/spot/BTC-USD", "BTC", "COIN"))
    #expect(model.prefs.groups.map(\.name) == ["加密", "美股", "Coinbase", "长期"])
    let own = try #require(model.prefs.groups.first { $0.name == "Coinbase" }?.id)
    #expect(model.prefs.groupForSymbol["coinbase/spot/BTC-USD"] == own)
    // 第二只进同一类，不再开新的。
    model.addFavorite("coinbase/spot/ETH-USD", info: info("coinbase/spot/ETH-USD", "ETH", "COIN"))
    #expect(model.prefs.groups.count == 4)
    #expect(model.prefs.groupForSymbol["coinbase/spot/ETH-USD"] == own)
    // 默认交易所的品种仍然留在他此刻那一类。
    model.addFavorite("binance/usd_m/ETHUSDT", info: info("binance/usd_m/ETHUSDT", "ETH", "COIN"))
    #expect(model.prefs.groupForSymbol["binance/usd_m/ETHUSDT"] == mine)
    // 同步拉回来一只还没分类的别家品种：重开时补进它自己那一类。
    var prefs = model.prefs
    prefs.addFavorite("coinbase/spot/SOL-USD")
    prefs.groupForSymbol["coinbase/spot/SOL-USD"] = nil
    store.save(prefs)
    let reopened = SymbolPickerModel(store: store, venueCategory: venue)
    #expect(reopened.prefs.groupForSymbol["coinbase/spot/SOL-USD"] == own)
  }

  @Test func newCategoryWithoutAnchorGoesLast() {
    var prefs = SymbolPrefs()
    _ = prefs.createGroup("加密")
    _ = prefs.createGroup("Coinbase", after: "美股")
    #expect(prefs.groups.map(\.name) == ["加密", "Coinbase"])
  }
}
