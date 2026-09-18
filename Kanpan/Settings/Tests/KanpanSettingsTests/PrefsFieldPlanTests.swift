import Testing
import Foundation
@testable import KanpanSettings

/// **把「加了字段忘了归类」变成一条红线。**
///
/// 这一套守卫存在的理由写在 `PrefsFieldPlan` 的注释里，一句话版本：同一件事
/// （哪个字段跟着人走 / 留在本机）以前散在四张手抄的清单里，两天里咬了两次——
/// 提交 `a161bb0`（客户端白名单比服务端多十九个字段，整条同步操作被拒，那个账号
/// 从此同步不上任何东西）和提交 `0f09f7e`（脏标识永远清不掉）。
///
/// 现在清单只有一张（`PrefsFieldPlan.table`），下面这几条负责保证它**不漏不多**。
/// 红的时候不要改测试，改表。
@Suite("体验类状态的归类表")
struct PrefsFieldPlanTests {

  /// `Prefs` 的每一个存储字段都得在表里，表里也不许有 `Prefs` 上没有的字段。
  ///
  /// 用 `Mirror` 而不是 JSON 键：可选字段是 nil 时 `encodeIfPresent` 根本不写那个键，
  /// 只看 JSON 会把它当成「不存在」放过去。`Mirror` 数的是存储属性，一个都躲不掉。
  @Test("每个存储字段都归了类")
  func everyStoredFieldIsClassified() {
    let stored = Set(Mirror(reflecting: Prefs.defaults).children.compactMap(\.label))
    let classified = Set(PrefsFieldPlan.table.keys)
    let missing = stored.subtracting(classified).sorted()
    let extra = classified.subtracting(stored).sorted()
    #expect(missing.isEmpty, """
      \(missing) 是 `Prefs` 上新加的存储字段，还没归类。
      去 Kanpan/Kanpan/Settings/Model/PrefsFieldPlan.swift 的 `table` 里加一行，判据只有一条：
      用手改出来的习惯 → `.synced`（跟着人走）；这台机器的属性 → `.deviceOnly`；
      自动累积的统计 → `.derivedLocal`（不跟人也不同步）。
      归 `.synced` 的还要同时改服务端 `Backend/kanpan-api/src/sync.rs` 的 `SETTINGS_FIELDS`
      和 `src/sync_validation.rs` 的值规则——只进白名单不补值规则，这个字段会变成毒丸，
      整条同步操作 400。两边对不齐上一次的代价见提交 a161bb0。
      """)
    #expect(extra.isEmpty, """
      \(extra) 在 `PrefsFieldPlan.table` 里，但 `Prefs` 上没有这个存储字段。
      字段被删了或者改了名字就把表里这一行一起改掉；名字对不上的话，
      `Prefs.syncedFieldNames` 会把一个谁也不认识的键发给服务端。
      """)
  }

  /// 表里的键必须和 `PrefsCodec` 编码出来的键逐字相同——整条同步链路
  /// （`PersonalSyncCodec.settings` 过滤、`Prefs.keeping` 按键覆盖）都是在 JSON 键上做的。
  @Test("表里的键就是存档里的键")
  func tableKeysMatchTheArchiveKeys() throws {
    let data = PrefsCodec.encode(.defaults)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let encoded = Set(json.keys).subtracting(PrefsFieldPlan.nonFieldKeys)
    let classified = Set(PrefsFieldPlan.table.keys)
    let missing = encoded.subtracting(classified).sorted()
    let extra = classified.subtracting(encoded).sorted()
    #expect(missing.isEmpty, """
      \(missing) 会被写进存档、也会被发上云，但 `PrefsFieldPlan.table` 里没有它。
      """)
    #expect(extra.isEmpty, """
      \(extra) 在 `PrefsFieldPlan.table` 里，却没被 `PrefsCodec.encode` 写出来。
      要么是 `CodingKeys` / `encode(to:)` 漏了一行（那这个字段根本存不下来，杀掉 app 就没了），
      要么是表里的键名拼错了。
      """)
  }

  /// 三张派生表就是那张母表，不许再出现第二份字面量。
  @Test("派生出来的几张表对得上母表")
  func derivedSetsComeFromTheTable() {
    #expect(Prefs.syncedFieldNames == PrefsFieldPlan.names(.synced))
    #expect(Prefs.deviceOnlyFieldNames == PrefsFieldPlan.names(.deviceOnly))
    #expect(Prefs.stampedFieldNames == Prefs.syncedFieldNames.union(SettingsWire.rsiFields))
    // `.syncedMerged` 的定义就是「打脏标识认它，但不以自己的名字上云」。
    #expect(PrefsFieldPlan.names(.syncedMerged) == SettingsWire.rsiFields)
    #expect(Prefs.syncedFieldNames.isDisjoint(with: Prefs.deviceOnlyFieldNames))
  }

  /// **客户端会发的字段 ≡ 服务端认的字段。**
  ///
  /// 下面这一份是 `Backend/kanpan-api/src/sync.rs` 的 `SETTINGS_FIELDS` 抄过来的。
  /// **改服务端就得同步改这里，两边对不齐上一次的代价见提交 a161bb0**
  /// （服务端认的字段比客户端会发的少十九个，服务端对含未知字段的操作是整条拒绝，
  /// 于是那个账号的同步队列被一条永远推不上去的操作堵死）。
  ///
  /// 这儿不跑 cargo：Swift 测试读不到 Rust 常量，两份清单只能各写一遍，靠这条测试对账——
  /// 和服务端那边 `the_allowlist_is_what_ios_sends` 把同一份期望写两遍是同一个手法。
  @Test("客户端会发的字段和服务端认的字段一个不差")
  func theServerKnowsEveryFieldWeSend() {
    let server: Set<String> = [
      "overlays", "subs", "subHeights", "subHeightOverrides", "params", "indicatorColors",
      "hiddenOutputs", "rsiRange", "portraitHeight", "quickIntervals", "theme", "skin",
      "ambientTheme", "styleID", "redUp", "priceMode", "timeZone", "magnet", "countdown",
      "lastLine", "sinceChange", "showDrawings", "candleKind", "gridChoice", "bodyChoice",
      "viewAnchor", "priceBias", "dataDisplay", "crossPrice", "allowMainInversion",
      "allowSubInversion", "adaptiveIndicators", "compactValues", "changeBasis", "barSpacing",
      "mainInverted", "subInverted", "interval", "keepAwake", "routePolicy",
      "favoritesSort", "favoritesAscending", "favoritesAmount", "favoritesSparkline",
      "favoritesExpanded", "favoritesGroup", "sectorMarket", "sectorWindow", "sectorSort",
      "drawToolGroup", "lastDrawTool", "replaySpeed", "reviewSearchScope",
    ]
    let sent = Prefs.syncedFieldNames.union(PrefsFieldPlan.wireOnlyKeys)
    let refused = sent.subtracting(server).sorted()
    let unused = server.subtracting(sent).sorted()
    #expect(refused.isEmpty, """
      \(refused) 客户端会发，服务端不认。服务端对含未知字段的操作是**整条拒绝**，
      于是这条操作永远推不上去，还会把同步队列堵死——上一次就是这么坏的（提交 a161bb0）。
      去 Backend/kanpan-api/src/sync.rs 的 `SETTINGS_FIELDS` 加名字（数组长度也要改），
      去 src/sync_validation.rs 的 `field` 加值规则（漏了值规则更糟：`_=>false` 会让整条操作 400），
      服务端 `the_allowlist_is_what_ios_sends` 里那份期望也要加，最后回到这个数组里加一行。
      """)
    #expect(unused.isEmpty, """
      \(unused) 服务端认，客户端不发。删字段时服务端那份要留着（老客户端还在发），
      就把它记进 `PrefsFieldPlan.wireOnlyKeys` 并写清楚为什么；否则说明这个数组抄漏了。
      """)
  }

  /// 搬家不能把人停在哪一类弄丢：`favoritesGroup` 得真的存得下来、也真的跟着人走。
  @Test("自选页停在哪一类跟着账号走")
  func favoritesGroupIsSynced() {
    #expect(PrefsFieldPlan.table["favoritesGroup"] == .synced)
    #expect(Prefs.syncedFieldNames.contains("favoritesGroup"))
    var prefs = Prefs.defaults
    #expect(prefs.favoritesGroup.isEmpty)   // 还没挑过。
    prefs.favoritesGroup = "F1E0A6C2-0000-4000-8000-000000000001"
    #expect(PrefsCodec.decode(PrefsCodec.encode(prefs)).favoritesGroup == prefs.favoritesGroup)
    // 长度和服务端那条规则同一个上限，超了就当没存过。
    prefs.favoritesGroup = String(repeating: "x", count: 129)
    #expect(PrefsCodec.decode(PrefsCodec.encode(prefs)).favoritesGroup.isEmpty)
  }
}
