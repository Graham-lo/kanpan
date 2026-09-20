import Foundation
import Testing
import KanpanCore

@testable import KanpanSymbols

/// 方案第 3 节第三件：长按桌面图标那几格。
///
/// 模拟器上没法用脚本去长按桌面图标，所以「摆哪几格」这件事由这几条用例定死。
@Suite("桌面快捷入口")
@MainActor
struct HomeShortcutsTests {
  @Test("最近看过的三个 + 搜索，搜索在最后")
  func threeRecentsThenSearch() {
    let items = HomeShortcuts.build(recents: ["BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT"])
    #expect(items.count == 4)
    #expect(items.map(\.title) == ["BTC", "ETH", "SOL", "搜索"])
    #expect(items.map(\.symbol) == ["BTCUSDT", "ETHUSDT", "SOLUSDT", nil])
    #expect(items.last?.type == HomeShortcuts.searchType)
    #expect(items.dropLast().allSatisfy { $0.type == HomeShortcuts.symbolType })
  }

  @Test("没看过任何品种时只有搜索那一格")
  func searchOnly() {
    let items = HomeShortcuts.build(recents: [])
    #expect(items.map(\.title) == ["搜索"])
  }

  @Test("重复的品种只占一格，大小写不算两个")
  func dedupes() {
    let items = HomeShortcuts.build(recents: ["btcusdt", "BTCUSDT", "ethusdt", " ", "SOLUSDT"])
    #expect(items.map(\.title) == ["BTC", "ETH", "SOL", "搜索"])
  }

  @Test("每一格都有 SF Symbol，没有副标题那一档")
  func iconsOnly() {
    let items = HomeShortcuts.build(recents: ["BTCUSDT"])
    #expect(items.allSatisfy { !$0.icon.isEmpty })
  }

  @Test("最近看过变了才重摆，没变不再写一遍")
  func refreshOnlyWhenChanged() {
    HomeShortcuts.reset()
    var rounds: [[HomeShortcut]] = []
    HomeShortcuts.apply = { rounds.append($0) }
    defer { HomeShortcuts.apply = nil; HomeShortcuts.reset() }

    HomeShortcuts.refresh(recents: ["BTCUSDT"])
    HomeShortcuts.refresh(recents: ["BTCUSDT"])          // 一模一样，不该再写
    #expect(rounds.count == 1)
    HomeShortcuts.refresh(recents: ["ETHUSDT", "BTCUSDT"])
    #expect(rounds.count == 2)
    #expect(rounds.last?.map(\.title) == ["ETH", "BTC", "搜索"])
  }

  @Test("看过一个品种就把桌面那几格重排了")
  func favoriteRefreshesShortcuts() {
    HomeShortcuts.reset()
    var rounds: [[HomeShortcut]] = []
    HomeShortcuts.apply = { rounds.append($0) }
    defer { HomeShortcuts.apply = nil; HomeShortcuts.reset() }

    let model = SymbolPickerModel(catalog: SymbolFixtures.catalog,
                                  store: SymbolPrefsStore(storage: MemoryPrefsStorage(), key: "t"))
    model.visit("ETHUSDT")
    #expect(rounds.last?.map(\.symbol) == ["ETHUSDT", nil])
  }
}
