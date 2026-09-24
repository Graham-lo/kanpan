import Foundation
import Testing
import KanpanCore
@testable import Kanpan

@Suite("自选分类")
struct FavoriteGroupTests {
  @Test("旧收藏迁入默认分类，分类和成员落盘后恢复")
  @MainActor func migrationAndPersistence() throws {
    let memory = MemoryPrefsStorage([SymbolPrefsStore.defaultsKey: Data(#"{"favorites":["sndkusdt","binance/usd_m/MUUSDT"],"recents":["binance/usd_m/BTCUSDT"]}"#.utf8)])
    let store = SymbolPrefsStore(storage: memory)
    var prefs = store.load()
    #expect(prefs.favorites(in: nil) == ["binance/usd_m/SNDKUSDT", "binance/usd_m/MUUSDT"])
    let created = prefs.createGroup("半导体")
    let group = try #require(created)
    prefs.assign("sndkusdt", to: group)
    store.save(prefs)
    #expect(store.load() == prefs)
    #expect(store.load().favorites(in: group) == ["binance/usd_m/SNDKUSDT"])
  }

  @Test("取消收藏清分类关系，删除分类保留品种，重名空名不增加分类")
  func lifecycle() throws {
    var prefs = SymbolPrefs(favorites: ["binance/usd_m/SNDKUSDT", "binance/usd_m/MUUSDT"])
    let created = prefs.createGroup("芯片")
    let group = try #require(created)
    let duplicate = prefs.createGroup(" 芯片 ")
    #expect(duplicate == group)
    let empty = prefs.createGroup("  ")
    #expect(empty == nil)
    prefs.assign("binance/usd_m/SNDKUSDT", to: group); prefs.assign("binance/usd_m/MUUSDT", to: group)
    prefs.toggleFavorite("binance/usd_m/SNDKUSDT")
    #expect(prefs.groupForSymbol["binance/usd_m/SNDKUSDT"] == nil)
    prefs.deleteGroup(group)
    #expect(prefs.favorites == ["binance/usd_m/MUUSDT"] && prefs.favorites(in: nil) == ["binance/usd_m/MUUSDT"])
  }

  @Test("分类内部排序不改变其他分类的顺序")
  func scopedOrder() throws {
    var prefs = SymbolPrefs(favorites: ["A", "BTC", "B", "ETH", "C"])
    let created = prefs.createGroup("股票")
    let group = try #require(created)
    for symbol in ["A", "B", "C"] { prefs.assign(symbol, to: group) }
    prefs.moveVisible(prefs.favorites(in: group), from: IndexSet(integer: 0), to: 3)
    #expect(prefs.favorites(in: group) == ["B", "C", "A"].map(SymbolPrefs.key))
    #expect(prefs.favorites(in: nil) == ["BTC", "ETH"].map(SymbolPrefs.key))
  }
  @Test("行情排序后拖动使用可见顺序，未显示的其他分类仍保留")
  func displayedOrder() {
    var prefs = SymbolPrefs(favorites: ["A", "BTC", "B", "ETH", "C"])
    prefs.moveVisible(["C", "B", "A"], from: IndexSet(integer: 0), to: 3)
    #expect(prefs.favorites == ["B", "BTC", "A", "ETH", "C"].map(SymbolPrefs.key))
  }

  @Test("实际分类选择与成员移动持久化，不重复收藏")
  @MainActor func realFoldersPersist() throws {
    let memory = MemoryPrefsStorage(), store = SymbolPrefsStore(storage: memory)
    var prefs = SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT", "binance/usd_m/MUUSDT"])
    let cryptoID = prefs.createGroup("加密"), stocksID = prefs.createGroup("美股")
    let crypto = try #require(cryptoID), stocks = try #require(stocksID)
    prefs.classifyUnassigned()
    prefs.assign("binance/usd_m/MUUSDT", to: stocks)
    // 「他停在哪一类」2026-09-19 搬去了 `Prefs.favoritesGroup`（跟着账号走），
    // 这份档案不再存它，由调用方灌进来——这儿就拿一个局部变量当那一份。
    let selected = stocks
    prefs.addFavorite("binance/usd_m/SOXLUSDT", in: selected)
    store.save(prefs)
    #expect(store.load().favorites(in: stocks) == ["binance/usd_m/MUUSDT", "binance/usd_m/SOXLUSDT"])
    #expect(store.load().favorites(in: crypto) == ["binance/usd_m/BTCUSDT"])
    prefs.assign("binance/usd_m/MUUSDT", to: crypto)
    #expect(prefs.favorites == ["binance/usd_m/BTCUSDT", "binance/usd_m/MUUSDT", "binance/usd_m/SOXLUSDT"])
    prefs.deleteGroup(stocks, selected: selected)
    #expect(prefs.favorites(in: crypto).count == 3)
    // 停在那一类被删了：读的时候自己退回第一类（见 `SymbolFieldPlanTests`）。
    #expect(prefs.group(selected) == crypto)
  }


  @Test("移到分类：还没开的预设分类当场开出来，已有的分类照用，名单不重复")
  @MainActor func moveToPresetCategory() throws {
    let memory = MemoryPrefsStorage(), store = SymbolPrefsStore(storage: memory)
    let model = SymbolPickerModel(store: store)
    func coin(_ symbol: String) -> SymbolInfo {
      SymbolInfo(symbol: symbol, base: String(symbol.dropLast(4)),
                 pricePrecision: 2, tickSize: 0.01, underlyingType: "COIN")
    }
    // 新用户：第一支开出「加密」，之后站在「加密」里加的美股也落在「加密」（09-20 的规矩）。
    model.addFavorite("binance/usd_m/BTCUSDT", info: coin("binance/usd_m/BTCUSDT"))
    model.addFavorite("binance/usd_m/AAPLUSDT")
    #expect(model.prefs.groups.map(\.name) == ["加密"])
    // 没有「新建分类」之后，第二类只能从「移到分类」的预设里来。
    #expect(model.moveTargets == ["加密", "美股", "贵金属"])
    let stocks = try #require(model.assign(["binance/usd_m/AAPLUSDT"], toCategory: "美股"))
    #expect(model.prefs.groups.map(\.name) == ["加密", "美股"])
    #expect(model.prefs.favorites(in: stocks) == ["binance/usd_m/AAPLUSDT"])
    #expect(model.moveTargets == ["加密", "美股", "贵金属"])
    // 已经开着的那一类照用，不再开第二个同名的。
    #expect(model.assign(["binance/usd_m/BTCUSDT"], toCategory: "美股") == stocks)
    #expect(model.prefs.groups.count == 2)
    // 落了盘：换一个模型读回来还在。
    #expect(SymbolPickerModel(store: store).prefs.groupForSymbol["binance/usd_m/AAPLUSDT"] == stocks)
  }

}
