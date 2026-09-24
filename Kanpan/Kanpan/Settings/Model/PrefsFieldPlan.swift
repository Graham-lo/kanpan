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
/// - **直连 / 网关那两档**（`routePolicy`）——是
///   **这台手机所处网络**的属性，不是他摆出来的样子：跟着人走只会把
///   A 手机的网络环境带到 B 手机上。`deviceOnly`。
/// - 「最近打开过哪些品种」「哪些品种看得勤」这类**每开一张图就变的统计**——不是他摆出来的
///   样子，而且每变一次就得生成一条同步操作，代价远大于收益。`derivedLocal`。
///
/// ## 「线路」这一摊整个留在本机（2026-09-19 改的）
///
/// `routePolicy` 是 `deviceOnly`，判据是同一条：它说的是**这台手机挂在哪张网上、
/// 这张网连得通哪一头**。（原来并排的 `apiHost` / `streamHost` 两个自定义域名字段
/// 2026-09-24 整条删了：设置里早没有入口，主机一律由 `RouteResolver` 按线路给。）
///
/// `routePolicy` 曾经是 `.synced`（理由是「直连 / 网关是他用手点的两档」），2026-09-19 按
/// GPT Pro 第二轮审查 B7 改了过来。改的原因不是判据变了，是那条路上有一个真实的坏结果：
///
/// > A 在自己的网络里选了网关并同步上去。B 本来是直连，而且这个字段还干净，
/// > B 同步一轮之后存档里就成了网关——B 从头到尾没碰过线路那两档，行情却换了一头。
///
/// 「用手点的」和「跟着人走」在这一项上分了家：他点的是**这台手机怎么连得上行情**，
/// 不是他想让所有设备都长成什么样。同一个账号的两台手机完全可能一台直连通、一台非走网关不可。
///
/// **产品规则一个字没变**（`AGENTS.md` 的稳定约定）：行情线路两档由用户自己选、
/// 出厂默认直连、**没有任何自动切换**。变的只有一件事——这个选择不再跨设备覆盖。
/// `PrefsFieldPlanTests.routePolicyStaysOnThisDevice` 与
/// `RoutePolicyStaysHomeTests` 把这件事钉住了。
///
/// 服务端那一侧**仍然认 `routePolicy`**（见下面的 `wireOnlyKeys`）：库里存着的老 body
/// 还带着它，直接从白名单删掉，那条设置对象下一次合并就会因为这个键没有值规则整条 400。
/// 要下线得走服务端 `RETIRED_SETTINGS_FIELDS` 两端退役。新客户端既不发也不收。
/// （老客户端多发一个服务端不认的键，服务端现在只是丢掉它、在 `droppedFields` 里报回，
/// 不再整条拒绝——早先这里写的「堵死同步队列」说的是那之前的服务端。）
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
    "compareSymbols": .synced,
    "interval": .synced, "quickIntervals": .synced,
    "theme": .synced, "skin": .synced, "ambientTheme": .synced, "redUp": .synced,
    "priceMode": .synced, "magnet": .synced, "countdown": .synced, "depth": .synced, "orderFlow": .synced, "candleKind": .synced,
    "gridChoice": .synced, "bodyChoice": .synced, "lastLine": .synced,
    "sinceChange": .synced, "viewAnchor": .synced, "priceBias": .synced,
    "dataDisplay": .synced, "crossPrice": .synced,
    "allowMainInversion": .synced, "allowSubInversion": .synced,
    "barSpacing": .synced, "mainInverted": .synced, "subInverted": .synced,
    "adaptiveIndicators": .synced, "portraitHeight": .synced,
    "indicatorColors": .synced, "hiddenOutputs": .synced,
    "keepAwake": .synced, "timeZone": .synced, "changeBasis": .synced,
    "overlays": .synced, "subs": .synced, "params": .synced,
    "subHeightOverrides": .synced,
    // 他在各页上摆出来的样子（见 `Prefs` 末尾那一节）。
    "favoritesSort": .synced, "favoritesAscending": .synced, "favoritesAmount": .synced,
    "favoritesSparkline": .synced, "favoritesGroup": .synced,
    "sectorMarket": .synced, "sectorWindow": .synced, "sectorSort": .synced,
    "lastDrawTool": .synced,
    "replaySpeed": .synced, "reviewSearchScope": .synced,
    "alertSound": .synced,
    "watchMoveAlert": .synced, "watchMoveThreshold": .synced,

    // ------------------------------------------------- 跟着人走，但线上并成一个键
    "rsiUpper": .syncedMerged, "rsiLower": .syncedMerged,

    // ---------------------------------------------------------------- 留在这台机器上
    // 走直连还是走 VPS 网关，是这台手机所处网络的属性，不是他的习惯。`routePolicy`
    // 2026-09-19 从 `.synced` 搬到这儿，理由见上面那一节（A 选网关，B 从没碰过线路却跟着换了头）。
    "routePolicy": .deviceOnly,
    // `apiHost` / `streamHost`（自定义行情域名）2026-09-24 删了：设置里早没有入口，
    // 主机一律由 `RouteResolver` 按线路给。两个都是 deviceOnly，从来没发上过服务端，
    // 老客户端也不会发，契约里删掉不影响任何一台的同步队列。旧存档里的键解码时忽略。
    // `smartMarketRoute`（「智能行情线路」自动探测开关）2026-09-24 整条删了：它把网关主机表
    // 挂在一个没有界面入口的布尔上，和「两档、没有任何自动切换」相悖。旧存档里的这个键
    // 解码时直接忽略；服务端从来不认它（它一直是 deviceOnly），两端没有要对账的。
    // `launchSnapshot`（启动快照开关）2026-09-24 删了（审查 U13）：设置页上早撤了，
    // 启动快照一律开着。它一直是 deviceOnly，服务端从来不认，两端没有要对账的。
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

  /// 服务端 `SETTINGS_FIELDS` 里有、而客户端这张表里没有的那几个键 → 它为什么只在线上存在。
  ///
  /// 理由写在值里，跟着键一起被导进契约文件（`Backend/kanpan-api/contract/settings-fields.json`），
  /// 所以加一个键就必须当场写清楚为什么，下一个人不用去翻 git log。
  ///
  /// 留着它们的理由是**存量**，不是「老客户端还在发」：服务端对不认识的字段现在是丢掉并在
  /// `droppedFields` 里报回（不再整条拒绝），但库里存着的老 body 里的键如果突然没了值规则，
  /// 那条对象之后的每次合并都会 400。所以删它们要走服务端 `RETIRED_SETTINGS_FIELDS`。
  /// 四个退下来的键共用的那半句理由（见上）。
  private static let keptForStoredBodies = "服务端仍然认这个键：库里存着的老 body 还带着它，直接从 SETTINGS_FIELDS 删掉，下一次合并到那条对象上会因为这个键没有值规则整条 400；真要下线它，走 sync.rs 的 RETIRED_SETTINGS_FIELDS 两端退役（strip_retired 会顺手把存量 body 洗掉）。老客户端单纯多发一个服务端不认的键，如今只会被丢掉并在 droppedFields 里报回，不再堵队列。"

  static let wireOnlyKeys: [String: String] = [
    "rsiRange": "客户端的 rsiUpper / rsiLower 合成的一个键（PrefsFieldClass.syncedMerged）；"
      + "那两个字段自己的名字从不上线，所以服务端只认合成后的 rsiRange。",
    "styleID": "十二款蜡烛造型那一阵子的选择，客户端早就不发了。"
      + Self.keptForStoredBodies,
    "drawToolGroup": "「绘图」面板上次停在哪个分类。2026-09-22 工具砍到十二把、"
      + "分类标签整条去掉之后，客户端既不发也不收了（见 Drawing.Kind.palette）。"
      + Self.keptForStoredBodies,
    "compactValues": "「简化指标数值」开关。2026-09-23 起数额（量、均量、持仓量、成交量差）一律 K / M / B / T、"
      + "价格与振荡类读数一律原样不缩写，这件事不再交给用户选，开关连同 Prefs 字段一起收掉，客户端既不发也不收。"
      + Self.keptForStoredBodies,
    "routePolicy": "直连 / 网关那两档。2026-09-19 起是本机字段（PrefsFieldClass.deviceOnly）："
      + "它说的是这台手机这张网连得通哪一头，不跟着人走，新客户端既不发也不收。"
      + Self.keptForStoredBodies,
  ]
}
