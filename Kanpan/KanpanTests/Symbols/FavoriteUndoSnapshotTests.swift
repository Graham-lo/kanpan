import Foundation
import Testing

@testable import Kanpan

/// 「已移除 · 撤销」那条路（§P3-4）。
///
/// 撤销要还原的不只是「它还在自选里」：**位置、分类**两样一起回来，
/// 否则删错一只之后还得自己去把它拖回原处、摆回原来那一类——
/// 那就不叫撤销了。这一组用纯数据守住这两样，界面那一半由
/// `KanpanUITests/FavoritesUndoUITests` 守。
@Suite("自选删除可撤销")
struct FavoriteUndoSnapshotTests {

  private func prefsWithGroup() throws -> (SymbolPrefs, String) {
    var prefs = SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT", "binance/usd_m/SOLUSDT", "binance/usd_m/SNDKUSDT"])
    let created = prefs.createGroup("半导体")
    let group = try #require(created)
    prefs.assign("binance/usd_m/SNDKUSDT", to: group)
    prefs.assign("binance/usd_m/ETHUSDT", to: group)
    return (prefs, group)
  }

  @Test("撤销把它放回原来那一行、原来那一类")
  func restorePutsEverythingBack() throws {
    let (original, _) = try prefsWithGroup()
    var prefs = original
    let snapshot = try #require(prefs.snapshot(of: "binance/usd_m/ETHUSDT"))
    #expect(snapshot.index == 1)
    #expect(snapshot.group != nil)

    prefs.toggleFavorite("binance/usd_m/ETHUSDT")
    #expect(prefs.favorites == ["binance/usd_m/BTCUSDT", "binance/usd_m/SOLUSDT", "binance/usd_m/SNDKUSDT"])
    #expect(prefs.groupForSymbol["binance/usd_m/ETHUSDT"] == nil)

    prefs.restore([snapshot])
    #expect(prefs == original)
  }

  @Test("一次删好几个，一起撤销，各回各的下标")
  func restoreManyKeepsTheirOwnIndexes() throws {
    let (original, _) = try prefsWithGroup()
    var prefs = original
    let doomed = ["binance/usd_m/BTCUSDT", "binance/usd_m/SNDKUSDT"]
    let snapshots = doomed.compactMap { prefs.snapshot(of: $0) }
    #expect(snapshots.map(\.index) == [0, 3])
    doomed.forEach { prefs.toggleFavorite($0) }
    #expect(prefs.favorites == ["binance/usd_m/ETHUSDT", "binance/usd_m/SOLUSDT"])

    prefs.restore(snapshots)
    #expect(prefs == original)
  }

  @Test("这五秒里分类被删了，就回到未分类，而不是指向一个不存在的分类")
  func restoreFallsBackToNoGroupWhenTheGroupIsGone() throws {
    var (prefs, group) = try prefsWithGroup()
    let snapshot = try #require(prefs.snapshot(of: "binance/usd_m/SNDKUSDT"))
    prefs.toggleFavorite("binance/usd_m/SNDKUSDT")
    prefs.deleteGroup(group)

    prefs.restore([snapshot])
    #expect(prefs.favorites.contains("binance/usd_m/SNDKUSDT"))
    #expect(prefs.groupForSymbol["binance/usd_m/SNDKUSDT"] == nil)
  }

  @Test("撤销晚了一步（它已经被重新加回来）不会插出第二条")
  func restoreIsANoOpWhenItIsBackAlready() throws {
    let (original, _) = try prefsWithGroup()
    var prefs = original
    let snapshot = try #require(prefs.snapshot(of: "binance/usd_m/SOLUSDT"))
    prefs.toggleFavorite("binance/usd_m/SOLUSDT")
    prefs.toggleFavorite("binance/usd_m/SOLUSDT")
    let before = prefs
    prefs.restore([snapshot])
    #expect(prefs == before)
    #expect(prefs.favorites.filter { $0 == "binance/usd_m/SOLUSDT" }.count == 1)
  }

  @Test("没在自选里的品种拍不出快照")
  func noSnapshotForStrangers() {
    let prefs = SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT"])
    #expect(prefs.snapshot(of: "binance/usd_m/ETHUSDT") == nil)
    #expect(prefs.snapshot(of: "btcusdt")?.index == 0)
  }
}
