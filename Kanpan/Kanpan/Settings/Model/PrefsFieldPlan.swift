import Foundation

// MARK: - 体验类状态归到哪一类

/// 一个存储字段跟着谁走。
///
/// ## 判据（只有这一条，别再发明第二条）
///
/// **用手改出来的习惯 → 跟着人走；自动累积的统计 / 这台机器的属性 → 留在本机。**
///
/// - 皮肤、周期、副图高度、自选表按什么排、板块停在哪个市场、上次拿的哪把画线工具——
///   都是他用手点出来的，换台设备登同一个账号就该还是那样。`synced`。
/// - 行情域名、线路开关、本机启动快照——是**这台手机所处网络 / 这台手机自己**的属性，
///   跟着人走只会把 A 手机的网络环境带到 B 手机上。`deviceOnly`。
/// - 「最近打开过哪些品种」「哪些品种看得勤」这类**每开一张图就变的统计**——不是他摆出来的
///   样子，而且每变一次就得生成一条同步操作，代价远大于收益。`derivedLocal`。
///
/// 来回搬过的字段各留了一条记录，免得下一个人再翻一次：`interval` / `keepAwake` 曾经被当成
/// 本机设置，结果是「换台设备登同一个账号，周期回到出厂 1h」，2026-09-19 改回 `synced`；
/// `favoritesGroup`（自选页停在哪个分类）曾经是 `SymbolPrefs` 里的纯本机字段，
/// 2026-09-19 搬进 `Prefs` 跟着人走。
enum PrefsFieldClass: String, Sendable, CaseIterable {
  /// 随账号同步，线上就用它自己的字段名。
  case synced
  /// 随账号同步，但**线上不是它自己的键**——由 `SettingsWire` 合成另一个键发出去
  /// （今天只有 `rsiLower` / `rsiUpper` 合成 `rsiRange`）。
  ///
  /// 单独一档是因为 `PersonalSyncCodec.settings` 用 `synced` 那张表在**拍平后的 JSON 顶层键**
  /// 上做过滤：把这两个放进 `synced`，发上去就会多两个服务端从没听说过的顶层键，
  /// 被 `droppedFields` 顶回来；不放进来又没法打脏标识。所以它们进 `stampedFieldNames`、
  /// 不进 `syncedFieldNames`。
  case syncedMerged
  /// 留在本机：这是**这台机器自己的属性**，换档案（登录 / 退登 / 切账号）时不被新档案覆盖。
  case deviceOnly
  /// 留在本机：**自动生成的统计**，不跟人、也不同步。
  ///
  /// `Prefs` 今天一个都没有——这一类活在 `SymbolPrefs`（`recents` / `viewScores` / `scoredAt`，
  /// 见 `SymbolFieldPlan`）。档位留在这儿是因为判据是同一条，下一个往 `Prefs` 里加统计的人
  /// 该看见它，而不是随手塞进 `synced`。
  case derivedLocal
}

/// **`Prefs` 的每一个存储字段归哪一类，只在这儿写一次。**
///
/// 这一份存在的理由：2026-09-19 之前，同一件事散在四张手抄的清单里——
/// `Prefs.syncedFieldNames`、`PersonalSyncCodec.keepDeviceFields` 里的四行赋值、
/// `AppAccountBridge.applyPending` 里手抄的四个本机字段、以及服务端的 `SETTINGS_FIELDS`。
/// 四张表分别看都「没错」，放一起才看得出对不齐，而它两天里咬了两次：
///
/// - 提交 `a161bb0`：客户端白名单比服务端多十九个字段，整条操作被拒，那个账号从此同步不上任何东西。
/// - 提交 `0f09f7e`：嵌套字段拍平后的路径映不回顶层字段名，脏标识永远清不掉。
///
/// 所以现在只有这一张表，上面那几处全部从它派生，再配一条穷举守卫
/// （`PrefsFieldPlanTests`）：**新加一个存储字段却没在这儿归类，测试立刻红。**
enum PrefsFieldPlan {
  /// 字段名 → 归类。键和 `PrefsCodec` 的编码键名、以及 `Prefs` 的存储属性名**三者逐字相同**，
  /// 所以拿它去 JSON 上按键比对是成立的（`Prefs.keeping` / `PersonalSyncCodec.settings` 都这么用）。
  static let table: [String: PrefsFieldClass] = [
    // ---------------------------------------------------------------- 跟着人走
    "interval": .synced, "quickIntervals": .synced,
    "theme": .synced, "skin": .synced, "ambientTheme": .synced, "redUp": .synced,
    "priceMode": .synced, "magnet": .synced, "countdown": .synced, "candleKind": .synced,
    "gridChoice": .synced, "bodyChoice": .synced, "lastLine": .synced, "showDrawings": .synced,
    "sinceChange": .synced, "viewAnchor": .synced, "priceBias": .synced,
    "dataDisplay": .synced, "crossPrice": .synced,
    "allowMainInversion": .synced, "allowSubInversion": .synced,
    "barSpacing": .synced, "mainInverted": .synced, "subInverted": .synced,
    "adaptiveIndicators": .synced, "compactValues": .synced, "portraitHeight": .synced,
    "indicatorColors": .synced, "hiddenOutputs": .synced,
    "keepAwake": .synced, "timeZone": .synced, "changeBasis": .synced,
    "overlays": .synced, "subs": .synced, "params": .synced,
    "subHeights": .synced, "subHeightOverrides": .synced,
    "routePolicy": .synced,
    // 他在各页上摆出来的样子（见 `Prefs` 末尾那一节）。
    "favoritesSort": .synced, "favoritesAscending": .synced, "favoritesAmount": .synced,
    "favoritesSparkline": .synced, "favoritesExpanded": .synced, "favoritesGroup": .synced,
    "sectorMarket": .synced, "sectorWindow": .synced, "sectorSort": .synced,
    "drawToolGroup": .synced, "lastDrawTool": .synced,
    "replaySpeed": .synced, "reviewSearchScope": .synced,

    // ------------------------------------------------- 跟着人走，但线上并成一个键
    "rsiUpper": .syncedMerged, "rsiLower": .syncedMerged,

    // ---------------------------------------------------------------- 留在这台机器上
    // 行情域名与线路是这台手机所处网络的属性。
    "apiHost": .deviceOnly, "streamHost": .deviceOnly, "smartMarketRoute": .deviceOnly,
    // 本机缓存的开关，只对这台机器有意义。
    "launchSnapshot": .deviceOnly,
  ]

  /// 这一类的全部字段名。
  static func names(_ kind: PrefsFieldClass) -> Set<String> {
    Set(table.compactMap { $0.value == kind ? $0.key : nil })
  }

  /// 归到某几类的全部字段名。
  static func names(_ kinds: Set<PrefsFieldClass>) -> Set<String> {
    Set(table.compactMap { kinds.contains($0.value) ? $0.key : nil })
  }

  /// `PrefsCodec` 编码出来但不是字段的键：存档版本号。穷举守卫要把它排掉。
  static let nonFieldKeys: Set<String> = ["v"]

  /// 服务端 `SETTINGS_FIELDS` 里有、而客户端这张表里没有的那几个键。
  ///
  /// - `rsiRange`：`rsiUpper` / `rsiLower` 合成的那一个（`syncedMerged`）。
  /// - `styleID`：只有老存档还带着它（十二款蜡烛造型那一阵子的选择），客户端早就不发了，
  ///   服务端留着是为了不把老客户端的操作整条拒掉。
  static let wireOnlyKeys: Set<String> = ["rsiRange", "styleID"]
}
