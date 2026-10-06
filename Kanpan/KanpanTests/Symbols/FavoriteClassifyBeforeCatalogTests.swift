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

  /// 2026-10-06 17 Pro Max 全量 UI 里抓到的：目录还没到时报价簿先收到一次「交易所不认这个代号」，
  /// 品种页的 `markDelisted` 拿「空目录 + 一行占位」当了目录灌进去——目录不再是空的，
  /// 「等目录」那道闸就开了：只有黄金认得出（ISO 代码），先开「贵金属」，其余七只全被归进
  /// 「他此刻看的那一类」，自选页上只剩一格「贵金属，8 个品种」，真目录到了也改不回来。
  @Test("目录没到时有一只被拒：不拿占位行当目录，真目录到了照常按资产类型分")
  func rejectionBeforeCatalogDoesNotFakeACatalog() throws {
    let store = SymbolPrefsStore(storage: MemoryPrefsStorage(), key: "t")
    store.save(SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT", "binance/usd_m/NVDAUSDT", "binance/usd_m/XAUUSDT"]))
    let m = SymbolPickerModel(store: store)   // 目录还没到
    m.markDelisted("binance/usd_m/GONEUSDT")
    #expect(m.catalog.isEmpty)
    #expect(m.prefs.groups.isEmpty)
    m.setCatalog(Self.catalog)
    #expect(m.prefs.groups.map(\.name) == ["加密", "美股", "贵金属"])
    let crypto = try #require(m.prefs.groups.first { $0.name == "加密" }?.id)
    #expect(m.prefs.groupForSymbol["binance/usd_m/BTCUSDT"] == crypto)
  }
}
