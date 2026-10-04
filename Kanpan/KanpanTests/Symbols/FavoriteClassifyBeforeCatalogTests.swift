import Foundation
import Testing
import KanpanCore
@testable import Kanpan

/// 深度审查 G 线走查：没分类的自选里夹着一只黄金，冷启动（目录还没到）那一趟初始化
/// 只认得出黄金（ISO 资产代码），先开了「贵金属」，排在最前、自选页一进来就停在只有
/// 一只 XAU 的那一格；排在黄金后面、还认不出来的币则被塞进「贵金属」（「他此刻看的那一类」）。
/// 目录没到之前除了别家交易所那一类，什么都不动，全留给 `setCatalog`。
@Suite("目录没到之前不给自选编分类")
@MainActor
struct FavoriteClassifyBeforeCatalogTests {
  private static func info(_ symbol: String, _ base: String, _ type: String) -> SymbolInfo {
    SymbolInfo(symbol: symbol, base: base, pricePrecision: 2, tickSize: 0.01, underlyingType: type)
  }
  private static let catalog = [
    info("binance/usd_m/BTCUSDT", "BTC", "COIN"),
    info("binance/usd_m/NVDAUSDT", "NVDA", "EQUITY"),
    info("binance/usd_m/XAUUSDT", "XAU", "COMMODITY"),
  ]

  @Test("币在前、黄金在后：分类按自选顺序开，加密排第一")
  func cryptoFirstWhenItLeadsTheList() {
    let store = SymbolPrefsStore(storage: MemoryPrefsStorage(), key: "t")
    store.save(SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT", "binance/usd_m/NVDAUSDT", "binance/usd_m/XAUUSDT"]))
    let m = SymbolPickerModel(store: store)   // 目录还没到
    #expect(m.prefs.groups.isEmpty)
    m.setCatalog(Self.catalog)
    #expect(m.prefs.groups.map(\.name) == ["加密", "美股", "贵金属"])
  }

  @Test("黄金在前、币在后：币不会被塞进「贵金属」")
  func coinIsNotDumpedIntoTheMetalsGroup() throws {
    let store = SymbolPrefsStore(storage: MemoryPrefsStorage(), key: "t")
    store.save(SymbolPrefs(favorites: ["binance/usd_m/XAUUSDT", "binance/usd_m/BTCUSDT"]))
    let m = SymbolPickerModel(store: store)
    #expect(m.prefs.groupForSymbol["binance/usd_m/BTCUSDT"] == nil)
    m.setCatalog(Self.catalog)
    let crypto = try #require(m.prefs.groups.first { $0.name == "加密" }?.id)
    #expect(m.prefs.groupForSymbol["binance/usd_m/BTCUSDT"] == crypto)
  }
}
