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
/// - 面板停在哪一栏（复盘本「观点 / 交易」那一面、筛选停在哪一档、板块停在哪个市场）也是他用手点出来的
///   习惯，跨重启、跨设备都该还在。`synced`。**自动替他翻过去的那一下不算**：比如复盘本「观点」空着
///   时自动翻到「交易」，只改这一次显示、不回写（`TradeReviewFeature.chosenSegment`）。
///
/// **例外：统计结果直接决定界面怎么摆的，跟着人走。** `drawToolUsage`（画线条露哪几把）、
/// `analysisUsage`（「分析」面板四节的顺序）、`learnedDefaults`（「按我的习惯自动调整」学到的结论）
/// 都是自动累积的，照字面该是 `derivedLocal`；但它们定的是界面长什么样——同一个人换台手机，条上还该
/// 是那几把、节序还该一样——所以是 `synced`。量都很小且有上限，别照字面把它们挪回本机。
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
/// 两档手动选、**没有任何自动切换**（出厂 2026-10-08 起是网关）。变的只有一件事——这个选择不再跨设备覆盖。
/// `PrefsFieldPlanTests.routePolicyStaysOnThisDevice` 与
/// `RoutePolicyStaysHomeTests` 把这件事钉住了。
///
/// 服务端 2026-10-10 起**不再认 `routePolicy`**：它进了 `sync.rs` 的 `RETIRED_SETTINGS_FIELDS`，
/// 老客户端发上来被丢掉并在 `droppedFields` 里报回，库里老 body 带着的由 `strip_retired` 在下一次
/// 合并时洗掉。新客户端既不发也不收，本机照旧存它（`.deviceOnly`）。
///
/// 来回搬过的字段各留了一条记录，免得下一个人再翻一次：`interval` / `keepAwake` 曾经被当成
/// 本机设置，结果是「换台设备登同一个账号，周期回到出厂 1h」，2026-09-19 改回 `synced`；
/// `favoritesGroup`（自选页停在哪个分类）曾经是 `SymbolPrefs` 里的纯本机字段，
/// 2026-09-19 搬进 `Prefs` 跟着人走。
enum PrefsFieldClass: String, Sendable, CaseIterable {
  /// 随账号同步，线上就用它自己的字段名。
  case synced
  // 原来还有一档 `syncedMerged`（随账号同步、线上并成别的键——只有 `rsiLower` / `rsiUpper` 合成
  // `rsiRange`）。RSI 上下限 2026-09-28 收设置项 C 组收掉，这一档没了成员，一起撤掉。
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
    "theme": .synced, "skin": .synced, "redUp": .synced,
    "priceMode": .synced, "depth": .synced, "orderFlow": .synced, "orderFlowHistory": .synced, "candleKind": .synced,
    "barSpacing": .synced, "mainInverted": .synced, "subInverted": .synced,
    // 横屏自己记的根间距（2026-10-05）：横竖图宽差两倍多，共用一份转屏就乱，见 `Prefs.landscapeBarSpacing`。
    "landscapeBarSpacing": .synced,
    "indicatorColors": .synced,
    "overlays": .synced, "subs": .synced, "params": .synced,
    "subHeightOverrides": .synced,
    // 他在各页上摆出来的样子（见 `Prefs` 末尾那一节）。
    "favoritesGroup": .synced,
    "sectorMarket": .synced, "sectorWindow": .synced,
    "lastDrawTool": .synced,
    // 画线条上露哪几把：每把工具用了几次（整张表一个键，见 `Prefs.drawToolUsage`）。
    // 它是自动统计出来的，按上面的判据本该只在本机；但它定的是条上摆什么——同一个人
    // 换台手机条上还该是那几把，所以跟账号走。量很小（最多十二个键、总数过 256 就减半）。
    "drawToolUsage": .synced,
    // 「分析」面板四节怎么排：每节用了几次（整张表一个键，见 `Prefs.analysisUsage`，2026-10-08）。
    // 和 `drawToolUsage` 同一个理由：自动统计出来的，但它定的是面板摆什么——同一个人换台手机
    // 节的顺序还该一样，所以跟账号走。量很小（最多四个键、总数过 256 就减半）。
    "analysisUsage": .synced,
    "drawingOverlaysShown": .synced,
    // 2026-10-06「隐藏画线」：个人的看图偏好，换台手机还该是藏着的，跟账号走。
    "drawingsHidden": .synced,
    // 2026-10-08「自选走势线」：个人的看表偏好，换台手机还该是那样，跟账号走。
    "favoritesTrend": .synced,
    "reviewSearchScope": .synced,
    // 2026-10-10 复盘本「观点 / 交易」停在哪一面、筛选停在「全部 / 待判定 / 已判定」哪一档：
    // 面板停在哪一栏也是用手点出来的习惯，跨重启、跨设备。自动翻面不回写（见 `Prefs.reviewSegment`）。
    "reviewSegment": .synced, "reviewBookFilter": .synced,
    "alertSound": .synced,
    "watchMoveAlert": .synced,
    // 条件提醒协议第 6 节：设置 › 通知「品种上新与停牌下架」。
    "notifyListingChanges": .synced,
    // 主力订单流：改过的门槛 / 步长（整张表一个键，见 `Prefs.orderFlowOverrides`）。
    // 六合四之前的 `orderFlowFilledBid/Ask`、`orderFlowCancelledBid/Ask` 在服务端 RETIRED_SETTINGS_FIELDS 里退役。
    "orderFlowOverrides": .synced,
    // 2026-10-08 图上大单与爆仓气泡：个人的看图偏好，换台手机还该是那样，跟账号走。
    "bigTradeSigns": .synced,
    // 2026-10-10 自动分析层（公允价值缺口）：个人的看图偏好，换台手机还该是开着的，跟账号走。
    "autoLayers": .synced,
    // 「按我的习惯自动调整」：开关 + 学到的结论（整份一个对象，≤ 16 KB）。行为日志只在本机。
    "habitLearning": .synced, "learnedDefaults": .synced,
    // ↑ new-sync-field:plan 在这一行上面插新字段（Tools/new-sync-field.py 认这一行，别删）

    // 2026-09-28「收设置项」收掉的字段不在这张表里了，线上在服务端 `RETIRED_SETTINGS_FIELDS` 退役
    // （老客户端发上来丢掉并在 droppedFields 报回，库里老 body 下次合并时洗掉）。逐项清单与恢复办法见
    // `.project-memory/PROJECT.md`「收设置项」一节；恢复某一项从 tag settings-before-trim-2026-09-28 取代码。
    // A 组：ambientTheme、keepAwake、timeZone、changeBasis。
    // B 组：magnet、countdown、gridChoice、bodyChoice、lastLine、sinceChange、viewAnchor、priceBias、
    // dataDisplay、crossPrice、allowMainInversion、allowSubInversion、adaptiveIndicators。
    // 复盘：replaySpeed（回放倍速改为按根数自动挑，见 `ReplayPace`）。
    // C 组：hiddenOutputs（指标「输出」开关）、rsiUpper / rsiLower（线上合成的 rsiRange）。
    // D 组：orderFlowSpot、orderFlowContract、orderFlowShowFilled、orderFlowShowCancelled（主力订单流「显示」开关）。
    // E 组：watchMoveThreshold（自选波动提醒的幅度，改为按波动自动定，见 `WatchMove.autoThreshold`）。
    // G 组：favoritesSort、favoritesAscending、favoritesAmount、favoritesSparkline（自选页排序与迷你走势）、
    // sectorSort（板块品种列表排序，固定按涨跌幅）。
    //
    // 2026-10-10「同步字段整理」退役的，同样在服务端 `RETIRED_SETTINGS_FIELDS` 里（老客户端发上来丢掉并在
    // droppedFields 报回，库里老 body 由 strip_retired 洗掉）。退役前的代码在 tag
    // sync-fields-before-retire-2026-10-10，恢复某一项从那里取回字段、Codec 键与服务端值规则，再 make sync-contract：
    // - portraitHeight（竖屏主图占比）：三端只读不写、永远 0.5，读端改用 `ChartOptions` 的出厂值。
    // - indicatorLayouts（09-27~10-02 周期分组留下的键）：10-03 之前的老客户端已经没了，读老档的迁移一起删掉
    //   （老存档里的这个键解码时忽略，退回顶层那份布局）。
    // - 原来的四个 wireOnly 键：styleID、drawToolGroup、compactValues 客户端早就不发；routePolicy 在本机照旧
    //   （下面 `.deviceOnly` 那一行），只是服务端不再认。
    // - 画线偏好集合里的 favorites（收藏的画线工具，`DrawingPreferences` 那边，见服务端
    //   `RETIRED_DRAWING_PREFERENCE_FIELDS`）。

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
  /// 所以加一个键就必须当场写清楚为什么，下一个人不用去翻提交历史。
  ///
  /// 2026-10-10 起是空表：原来的四个（`styleID`、`drawToolGroup`、`compactValues`、`routePolicy`）
  /// 走服务端 `RETIRED_SETTINGS_FIELDS` 两端退役了——老客户端发上来丢掉并在 `droppedFields` 里报回，
  /// 库里存着的老 body 由 `strip_retired` 在下一次合并时洗掉，不会因为键没有值规则整条 400。
  /// 表和契约里那一栏留着，是为了以后真有「服务端先认、客户端不发」的键时有地方写理由。
  static let wireOnlyKeys: [String: String] = [:]
}
