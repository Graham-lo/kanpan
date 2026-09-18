import Testing
import Foundation
@testable import KanpanSymbols

/// **自选档案这一半的同一条红线**，配套的说明见 `SymbolFieldPlanTests` 的兄弟
/// `PrefsFieldPlanTests`（设置包里）和 `SymbolFieldPlan` 的注释。
///
/// 这边最要命的一处是 `AppAccountBridge.applyPending()`：云端只存自选和分类，
/// 每来一次同步就要拿云端那几张表重建一份完整的 `SymbolPrefs`。少带回一个本机字段，
/// 症状是「每同步一次，『常看』被清空一次」——不报错、不崩、用户只觉得这功能时灵时不灵。
@Suite("自选档案的归类表")
struct SymbolFieldPlanTests {

  /// 每一个存储字段都得在表里。用 `Mirror`：可选字段（`legacySelectedGroup`）是 nil 时
  /// 编码根本不写那个键，只看 JSON 会把它漏过去。
  @Test("每个存储字段都归了类")
  func everyStoredFieldIsClassified() {
    let stored = Set(Mirror(reflecting: SymbolPrefs()).children.compactMap(\.label)
      .map(SymbolFieldPlan.codingKey(forProperty:)))
    let classified = Set(SymbolFieldPlan.table.keys)
    let missing = stored.subtracting(classified).sorted()
    let extra = classified.subtracting(stored).sorted()
    #expect(missing.isEmpty, """
      \(missing) 是 `SymbolPrefs` 上新加的存储字段，还没归类。
      去 Kanpan/Kanpan/Symbols/SymbolFieldPlan.swift 的 `table` 里加一行，判据只有一条：
      用手改出来的习惯 → `.synced`（跟着人走，云端那几张表要能把它重建出来）；
      自动累积的统计 / 这台机器的属性 → `.localOnly`（`applyPending` 会按这张表把它抄回来）。
      归 `.synced` 的还要想清楚它在服务端 `favorites` / `groups` 两张表里怎么存
      （`PersonalSyncCodec.symbols`），不然它同步不上去。
      """)
    #expect(extra.isEmpty, """
      \(extra) 在 `SymbolFieldPlan.table` 里，但 `SymbolPrefs` 上没有这个键。
      改了属性名就顺手改表；属性名和 JSON 键名不一样时，错位要记进
      `SymbolFieldPlan.codingKey(forProperty:)`（今天只有 `legacySelectedGroup` 一处）。
      """)
  }

  /// 表里的键必须就是存档里的键——`SymbolPrefs.keeping` 是在 JSON 键上做覆盖的。
  @Test("表里的键就是存档里的键")
  func tableKeysMatchTheArchiveKeys() throws {
    // 每个字段都给一个非默认值，逼着可选字段也被写出来。
    var prefs = SymbolPrefs(favorites: ["BTCUSDT"], recents: ["BTCUSDT"],
                            groups: [.init(id: "g", name: "加密")],
                            groupForSymbol: ["BTCUSDT": "g"], pinned: ["BTCUSDT"],
                            legacySelectedGroup: "g", viewScores: ["BTCUSDT": 1], scoredAt: 1)
    prefs.scoredAt = 1
    let data = try JSONEncoder().encode(prefs)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let encoded = Set(json.keys)
    let classified = Set(SymbolFieldPlan.table.keys)
    #expect(encoded.subtracting(classified).sorted().isEmpty,
            "\(encoded.subtracting(classified).sorted()) 会被写进存档，但 `SymbolFieldPlan.table` 里没有它。")
    #expect(classified.subtracting(encoded).sorted().isEmpty,
            "\(classified.subtracting(encoded).sorted()) 在表里，却没被写进存档——键名拼错了，或者 `CodingKeys` 漏了一行。")
  }

  /// 云端重建 + 按表抄回本机字段，和「手写一份完整构造」的结果必须逐字一样。
  /// 这一条钉的是 `AppAccountBridge.applyPending()` 的那次改写。
  @Test("同步重建不会把本机那几样冲掉")
  func rebuildKeepsLocalOnlyFields() {
    let local = SymbolPrefs(favorites: ["BTCUSDT", "ETHUSDT"], recents: ["ETHUSDT", "BTCUSDT"],
                            groups: [.init(id: "g", name: "加密")],
                            groupForSymbol: ["BTCUSDT": "g", "ETHUSDT": "g"], pinned: ["BTCUSDT"],
                            legacySelectedGroup: "g",
                            viewScores: ["BTCUSDT": 7], scoredAt: 1_700_000_000)
    // 云端那几张表重建出来的：只有自选、分类、归属、钉住。
    let cloud = SymbolPrefs(favorites: ["ETHUSDT"], groups: [.init(id: "g", name: "加密")],
                            groupForSymbol: ["ETHUSDT": "g"], pinned: [])
    let merged = SymbolPrefs.keeping(SymbolPrefs.localOnlyFieldNames, of: local, over: cloud)
    #expect(merged.favorites == ["ETHUSDT"])          // 云端那半跟云端。
    #expect(merged.pinned.isEmpty)
    #expect(merged.recents == ["ETHUSDT", "BTCUSDT"]) // 本机那半原样留着。
    #expect(merged.viewScores == ["BTCUSDT": 7])
    #expect(merged.scoredAt == 1_700_000_000)
    #expect(merged.legacySelectedGroup == "g")
    #expect(SymbolFieldPlan.names(.localOnly) == ["recents", "viewScores", "scoredAt", "selectedGroupID"])
  }

  /// 「他停在哪一类」搬去 `Prefs.favoritesGroup` 之后，老存档里的那个键还得读得出来——
  /// 读不出来，升级那一刻用户停在哪一类就丢了。
  @Test("老存档里的选中分类还读得出来")
  func theOldKeyStillDecodes() throws {
    let json = Data("""
      {"favorites":["BTCUSDT"],"groups":[{"id":"g","name":"加密"}],"selectedGroupID":"g"}
      """.utf8)
    let prefs = try JSONDecoder().decode(SymbolPrefs.self, from: json)
    #expect(prefs.legacySelectedGroup == "g")
    // 指向一个早就删掉的分类时不要搬——搬过去就是一个指向空气的 id。
    let stale = try JSONDecoder().decode(SymbolPrefs.self, from: Data("""
      {"favorites":["BTCUSDT"],"groups":[{"id":"g","name":"加密"}],"selectedGroupID":"没了"}
      """.utf8))
    #expect(stale.legacySelectedGroup == nil)
  }

  /// **选中的分类被删掉之后要退回第一类。**
  ///
  /// 搬家之前这条兜底写在两处：`init` 里洗掉认不出的 id、`deleteGroup` 里清空选中项。
  /// 现在选中项存在 `Prefs` 那边，自选档案管不着它，所以兜底挪到了**读的时候**
  /// （`SymbolPrefs.group(_:)`）。这条测试钉的就是「换了个地方兜，行为一个字没变」。
  @Test("选中的分类没了就退回第一类")
  func deletedGroupFallsBack() throws {
    var prefs = SymbolPrefs(favorites: ["BTCUSDT", "MUUSDT"])
    let cryptoID = prefs.createGroup("加密"), stocksID = prefs.createGroup("美股")
    let crypto = try #require(cryptoID), stocks = try #require(stocksID)
    prefs.classifyUnassigned(into: crypto)
    prefs.assign("MUUSDT", to: stocks)
    #expect(prefs.group(stocks) == stocks)
    prefs.deleteGroup(stocks, selected: stocks)
    #expect(prefs.group(stocks) == crypto)            // 停在那一类没了 → 第一类。
    #expect(prefs.favorites(in: crypto).count == 2)   // 落单的成员也进第一类。
    #expect(prefs.group(nil) == crypto)               // 还没挑过 → 第一类。
    #expect(prefs.group("") == crypto)                // 空串就是「还没挑过」。
    var empty = SymbolPrefs(favorites: ["BTCUSDT"])
    #expect(empty.group(nil) == nil)                  // 一个分类都没有 → 没有。
    empty.addFavorite("ETHUSDT", in: "没了")           // 认不出的那一类不该凭空冒出来。
    #expect(empty.groupForSymbol.isEmpty)
  }
}
