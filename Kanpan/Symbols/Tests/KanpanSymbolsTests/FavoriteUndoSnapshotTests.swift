import Foundation
import Testing

@testable import KanpanSymbols

/// 「已移除 · 撤销」那条路（§P3-4）。
///
/// 撤销要还原的不只是「它还在自选里」：**位置、分类、置顶位**三样一起回来，
/// 否则删错一只之后还得自己去把它拖回原处、摆回原来那一类、重新置顶——
/// 那就不叫撤销了。这一组用纯数据守住这三样，界面那一半由
/// `KanpanUITests/FavoritesUndoUITests` 守。
@Suite("自选删除可撤销")
struct FavoriteUndoSnapshotTests {

  private func prefsWithGroup() throws -> (SymbolPrefs, String) {
    var prefs = SymbolPrefs(favorites: ["BTCUSDT", "ETHUSDT", "SOLUSDT", "SNDKUSDT"])
    let created = prefs.createGroup("半导体")
    let group = try #require(created)
    prefs.assign("SNDKUSDT", to: group)
    prefs.assign("ETHUSDT", to: group)
    prefs.setPinned("SOLUSDT", true)
    prefs.setPinned("ETHUSDT", true)
    return (prefs, group)
  }

  @Test("撤销把它放回原来那一行、原来那一类、原来那个置顶位")
  func restorePutsEverythingBack() throws {
    let (original, _) = try prefsWithGroup()
    var prefs = original
    let snapshot = try #require(prefs.snapshot(of: "ETHUSDT"))
    #expect(snapshot.index == 1)
    #expect(snapshot.group != nil)
    #expect(snapshot.pinIndex == 1)

    prefs.toggleFavorite("ETHUSDT")
    #expect(prefs.favorites == ["BTCUSDT", "SOLUSDT", "SNDKUSDT"])
    #expect(prefs.groupForSymbol["ETHUSDT"] == nil)
    #expect(!prefs.pinned.contains("ETHUSDT"))

    prefs.restore([snapshot])
    #expect(prefs == original)
  }

  @Test("一次删好几个，一起撤销，各回各的下标")
  func restoreManyKeepsTheirOwnIndexes() throws {
    let (original, _) = try prefsWithGroup()
    var prefs = original
    let doomed = ["BTCUSDT", "SNDKUSDT"]
    let snapshots = doomed.compactMap { prefs.snapshot(of: $0) }
    #expect(snapshots.map(\.index) == [0, 3])
    doomed.forEach { prefs.toggleFavorite($0) }
    #expect(prefs.favorites == ["ETHUSDT", "SOLUSDT"])

    prefs.restore(snapshots)
    #expect(prefs == original)
  }

  @Test("这五秒里分类被删了，就回到未分类，而不是指向一个不存在的分类")
  func restoreFallsBackToNoGroupWhenTheGroupIsGone() throws {
    var (prefs, group) = try prefsWithGroup()
    let snapshot = try #require(prefs.snapshot(of: "SNDKUSDT"))
    prefs.toggleFavorite("SNDKUSDT")
    prefs.deleteGroup(group)

    prefs.restore([snapshot])
    #expect(prefs.favorites.contains("SNDKUSDT"))
    #expect(prefs.groupForSymbol["SNDKUSDT"] == nil)
  }

  @Test("撤销晚了一步（它已经被重新加回来）不会插出第二条")
  func restoreIsANoOpWhenItIsBackAlready() throws {
    let (original, _) = try prefsWithGroup()
    var prefs = original
    let snapshot = try #require(prefs.snapshot(of: "SOLUSDT"))
    prefs.toggleFavorite("SOLUSDT")
    prefs.toggleFavorite("SOLUSDT")
    let before = prefs
    prefs.restore([snapshot])
    #expect(prefs == before)
    #expect(prefs.favorites.filter { $0 == "SOLUSDT" }.count == 1)
  }

  @Test("没在自选里的品种拍不出快照")
  func noSnapshotForStrangers() {
    let prefs = SymbolPrefs(favorites: ["BTCUSDT"])
    #expect(prefs.snapshot(of: "ETHUSDT") == nil)
    #expect(prefs.snapshot(of: "btcusdt")?.index == 0)
  }
}
