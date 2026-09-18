import Foundation
import Testing
@testable import KanpanSymbols

@Suite("自选分类")
struct FavoriteGroupTests {
  @Test("旧收藏迁入默认分类，分类和成员落盘后恢复")
  @MainActor func migrationAndPersistence() throws {
    let memory = MemoryPrefsStorage([SymbolPrefsStore.defaultsKey: Data(#"{"favorites":["sndkusdt","MUUSDT"],"recents":["BTCUSDT"]}"#.utf8)])
    let store = SymbolPrefsStore(storage: memory)
    var prefs = store.load()
    #expect(prefs.favorites(in: nil) == ["SNDKUSDT", "MUUSDT"])
    let created = prefs.createGroup("半导体")
    let group = try #require(created)
    prefs.assign("sndkusdt", to: group)
    prefs.setPinned("sndkusdt", true)
    store.save(prefs)
    #expect(store.load() == prefs)
    #expect(store.load().favorites(in: group) == ["SNDKUSDT"])
  }

  @Test("取消收藏清分类关系，删除分类保留品种，重名空名不增加分类")
  func lifecycle() throws {
    var prefs = SymbolPrefs(favorites: ["SNDKUSDT", "MUUSDT"])
    let created = prefs.createGroup("芯片")
    let group = try #require(created)
    let duplicate = prefs.createGroup(" 芯片 ")
    #expect(duplicate == group)
    let empty = prefs.createGroup("  ")
    #expect(empty == nil)
    prefs.assign("SNDKUSDT", to: group); prefs.assign("MUUSDT", to: group)
    prefs.setPinned("SNDKUSDT", true)
    prefs.toggleFavorite("SNDKUSDT")
    #expect(prefs.pinned.isEmpty)
    #expect(prefs.groupForSymbol["SNDKUSDT"] == nil)
    prefs.renameGroup(group, name: "半导体")
    #expect(prefs.groups.first?.name == "半导体")
    prefs.deleteGroup(group)
    #expect(prefs.favorites == ["MUUSDT"] && prefs.favorites(in: nil) == ["MUUSDT"])
  }

  @Test("分类内部排序不改变其他分类的顺序")
  func scopedOrder() throws {
    var prefs = SymbolPrefs(favorites: ["A", "BTC", "B", "ETH", "C"])
    let created = prefs.createGroup("股票")
    let group = try #require(created)
    for symbol in ["A", "B", "C"] { prefs.assign(symbol, to: group) }
    prefs.moveInGroup(group, from: IndexSet(integer: 0), to: 3)
    #expect(prefs.favorites(in: group) == ["B", "C", "A"])
    #expect(prefs.favorites(in: nil) == ["BTC", "ETH"])
  }
  @Test("行情排序后拖动使用可见顺序，未显示的其他分类仍保留")
  func displayedOrder() {
    var prefs = SymbolPrefs(favorites: ["A", "BTC", "B", "ETH", "C"])
    prefs.moveVisible(["C", "B", "A"], from: IndexSet(integer: 0), to: 3)
    #expect(prefs.favorites == ["B", "BTC", "A", "ETH", "C"])
  }

  @Test("实际分类选择与成员移动持久化，不重复收藏")
  @MainActor func realFoldersPersist() throws {
    let memory = MemoryPrefsStorage(), store = SymbolPrefsStore(storage: memory)
    var prefs = SymbolPrefs(favorites: ["BTCUSDT", "MUUSDT"])
    let cryptoID = prefs.createGroup("加密"), stocksID = prefs.createGroup("美股")
    let crypto = try #require(cryptoID), stocks = try #require(stocksID)
    prefs.classifyUnassigned()
    prefs.assign("MUUSDT", to: stocks)
    // 「他停在哪一类」2026-09-19 搬去了 `Prefs.favoritesGroup`（跟着账号走），
    // 这份档案不再存它，由调用方灌进来——这儿就拿一个局部变量当那一份。
    let selected = stocks
    prefs.addFavorite("SOXLUSDT", in: selected)
    store.save(prefs)
    #expect(store.load().favorites(in: stocks) == ["MUUSDT", "SOXLUSDT"])
    #expect(store.load().favorites(in: crypto) == ["BTCUSDT"])
    prefs.assign("MUUSDT", to: crypto)
    #expect(prefs.favorites == ["BTCUSDT", "MUUSDT", "SOXLUSDT"])
    prefs.deleteGroup(stocks, selected: selected)
    #expect(prefs.favorites(in: crypto).count == 3)
    // 停在那一类被删了：读的时候自己退回第一类（见 `SymbolFieldPlanTests`）。
    #expect(prefs.group(selected) == crypto)
  }

}
