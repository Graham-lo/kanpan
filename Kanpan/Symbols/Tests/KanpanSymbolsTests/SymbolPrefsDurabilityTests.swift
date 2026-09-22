import Testing
import Foundation
@testable import KanpanSymbols

// ============================================================ 自选存档的耐久性
//
// B-01：`symbols.json` 是一份合法 JSON 对象，但里头某一处形状不对（分类缺 `name`、
// `scoredAt` 写成字符串……），整份 `SymbolPrefs` 解码失败 → `load()` 把失败当空档
// 返回 → `AppAccountBridge.prepare` 拿这份空档回写磁盘 → 用户的自选永久没了。
//
// 这一组按「丢用户的东西」的口径守两层：
// 1. **局部坏只丢局部**：一个坏分组、一个类型不对的字段，不许带走整份自选。
// 2. **真的读不动就抛**，不许静默当空档——`prepare` 那一侧靠这个 `throw` 拒绝覆盖。

@Suite("自选存档：局部损坏只丢局部，读不动就抛")
struct SymbolPrefsDurabilityTests {

  private func data(_ json: String) -> Data { Data(json.utf8) }

  // ---------------------------------------------------------------- 解码容错

  @Test("顶层缺 key 照常解（老存档只有 favorites / recents）")
  func missingTopLevelKeys() throws {
    let raw = data(#"{"favorites":["binance/usd_m/BTCUSDT","binance/usd_m/ETHUSDT"],"recents":["binance/usd_m/SOLUSDT"]}"#)
    let prefs = try JSONDecoder().decode(SymbolPrefs.self, from: raw)
    #expect(prefs.favorites == ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"])
    #expect(prefs.recents == ["binance/usd_m/SOLUSDT"])
    #expect(prefs.groups.isEmpty)
  }

  @Test("分组里一项缺 name：只丢那一项的名字，自选一条都不能少")
  func groupMissingNameKeepsFavorites() throws {
    let raw = data(#"""
    {"favorites":["binance/usd_m/BTCUSDT","binance/usd_m/ETHUSDT"],
     "groups":[{"id":"g1","name":"加密"},{"id":"g2"}],
     "groupForSymbol":{"binance/usd_m/BTCUSDT":"g1","binance/usd_m/ETHUSDT":"g2"}}
    """#)
    let prefs = try JSONDecoder().decode(SymbolPrefs.self, from: raw)
    #expect(prefs.favorites == ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"])
    #expect(prefs.groups.map(\.id) == ["g1", "g2"])
    #expect(prefs.groupForSymbol["binance/usd_m/ETHUSDT"] == "g2")
  }

  @Test("分组数组里混进一个不是对象的元素：跳过它，别的分组照常在")
  func groupGarbageElementIsSkipped() throws {
    let raw = data(#"""
    {"favorites":["binance/usd_m/BTCUSDT"],"groups":["这不是分组",{"id":"g1","name":"加密"}]}
    """#)
    let prefs = try JSONDecoder().decode(SymbolPrefs.self, from: raw)
    #expect(prefs.favorites == ["binance/usd_m/BTCUSDT"])
    #expect(prefs.groups.map(\.id) == ["g1"])
  }

  @Test("scoredAt 写成字符串：只有它回默认，自选 / 分组 / 置顶全留着")
  func typeMismatchFallsBackToDefaultOnly() throws {
    let raw = data(#"""
    {"favorites":["binance/usd_m/BTCUSDT","binance/usd_m/ETHUSDT"],"pinned":["binance/usd_m/BTCUSDT"],
     "groups":[{"id":"g1","name":"加密"}],"groupForSymbol":{"binance/usd_m/BTCUSDT":"g1"},
     "viewScores":{"binance/usd_m/BTCUSDT":3.5},"scoredAt":"2026-09-19"}
    """#)
    let prefs = try JSONDecoder().decode(SymbolPrefs.self, from: raw)
    #expect(prefs.favorites == ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"])
    #expect(prefs.pinned == ["binance/usd_m/BTCUSDT"])
    #expect(prefs.groups.map(\.id) == ["g1"])
    #expect(prefs.viewScores["binance/usd_m/BTCUSDT"] == 3.5)
    #expect(prefs.scoredAt == 0)
  }

  @Test("自选数组里混进一个数字：跳过它，剩下的代号全在")
  func garbageFavoriteElementIsSkipped() throws {
    let raw = data(#"{"favorites":["binance/usd_m/BTCUSDT",7,"binance/usd_m/ETHUSDT"]}"#)
    let prefs = try JSONDecoder().decode(SymbolPrefs.self, from: raw)
    #expect(prefs.favorites == ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"])
  }

  // ---------------------------------------------------------------- 读盘的两种「读不出来」

  @Test("柜子里没有这份档案 = 合法空档，不抛")
  @MainActor
  func absentArchiveIsALegalEmptyOne() throws {
    let store = SymbolPrefsStore(storage: MemoryPrefsStorage(), key: "k")
    #expect(try store.read() == SymbolPrefs())
  }

  @Test("档案在、但解不动：抛，不许静默当空档")
  @MainActor
  func unreadableArchiveThrows() {
    let storage = MemoryPrefsStorage(["k": Data("这不是 JSON".utf8)])
    let store = SymbolPrefsStore(storage: storage, key: "k")
    #expect(throws: SymbolPrefsStore.StoreError.unreadable) { try store.read() }
  }

  @Test("零字节的档案也算解不动（写到一半断电），不当空档")
  @MainActor
  func truncatedArchiveThrows() {
    let store = SymbolPrefsStore(storage: MemoryPrefsStorage(["k": Data()]), key: "k")
    #expect(throws: SymbolPrefsStore.StoreError.unreadable) { try store.read() }
  }

  // ---------------------------------------------------------------- prepare 的姿态

  /// `AppAccountBridge.prepare` 的那一段：读档 → 编码 → 和盘上的字节不同就回写。
  /// 读不动就整段中断（和画线的 `try drawStore.read()` 同一个姿态），一个字节都不许写。
  @MainActor
  private func prepareLikeBridge(_ store: SymbolPrefsStore, storage: MemoryPrefsStorage, key: String) throws {
    var next = try store.read()
    next.legacySelectedGroup = nil
    let encoded = try JSONEncoder().encode(next)
    if encoded != storage.symbolPrefsData(forKey: key) { storage.setSymbolPrefsData(encoded, forKey: key) }
  }

  @Test("prepare 的姿态：档案解不动就中断，磁盘上那份原封不动")
  @MainActor
  func prepareRefusesToOverwriteAnUnreadableArchive() {
    let bytes = Data("这不是 JSON".utf8)
    let storage = MemoryPrefsStorage(["kanpan.symbols.v1": bytes])
    let store = SymbolPrefsStore(storage: storage)
    #expect(throws: SymbolPrefsStore.StoreError.unreadable) {
      try prepareLikeBridge(store, storage: storage, key: SymbolPrefsStore.defaultsKey)
    }
    #expect(storage.raw["kanpan.symbols.v1"] == bytes)
  }

  @Test("prepare 的姿态：一个坏分组不能让盘上的自选被空档盖掉")
  @MainActor
  func prepareKeepsFavoritesWhenOneGroupIsBroken() throws {
    let raw = data(#"""
    {"favorites":["binance/usd_m/BTCUSDT","binance/usd_m/ETHUSDT"],"groups":[{"id":"g1","name":"加密"},{"id":"g2"}],
     "scoredAt":"坏了"}
    """#)
    let storage = MemoryPrefsStorage(["kanpan.symbols.v1": raw])
    let store = SymbolPrefsStore(storage: storage)
    try prepareLikeBridge(store, storage: storage, key: SymbolPrefsStore.defaultsKey)
    let after = SymbolPrefsStore(storage: storage)
    #expect(try after.read().favorites == ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"])
    #expect(try after.read().groups.map(\.id) == ["g1", "g2"])
  }
}
