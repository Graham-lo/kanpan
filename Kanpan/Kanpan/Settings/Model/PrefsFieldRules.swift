import Foundation
import KanpanCore

// MARK: - 跟人走字段的值规则

/// 一个 `.synced` 字段在线上**服务端收什么值**。和 `PrefsFieldPlan.table` 同一等级的母表，只写这一处。
///
/// ## 为什么要有它（2026-10-10「同步字段解耦」）
///
/// 字段名早就只写一次了（`table` → 契约 `wireKeys` → 服务端 `SETTINGS_FIELDS` 对账），可**值规则**——
/// 类型、枚举、范围、数组长度、白名单、去重——还在 Swift 解码、Rust `sync_validation::field`、
/// 两个网页的清洗里各手写一遍。三边一不一致就是「客户端发的值服务端不认」：设置里那一项被丢掉、
/// 回执 `invalidFields` 点名，那个字段从此悄悄不同步（审查 2026-10-10 查出多起）。
///
/// 现在规则也只写这一处：`make sync-contract` 把它连同按规则造出来的正反样例写进契约的 `rules`，
/// - 服务端：通用规则直接按契约校验（`settings_rules.rs`），只有 `.custom` 的才走手写函数；
/// - 手机网页：通用规则的清洗读同一份契约（`Web/src/sync/settingsRules.ts`）；
/// - iOS：`PrefsCodec` 的宽容解码仍是手写的，但 `PrefsFieldRulesTests` 拿契约规则去打出厂值与编解码边界，
///   出厂值不满足规则、非法值读回来不回落，都当场红。
///
/// ## 规则的意思（三边同一套读法）
///
/// 这里描述的是**服务端收下的边界**，不是本机界面的上限。本机可以更严（`quickIntervals` 服务端收 10 档、
/// 手机只钉 6 档），但不能更宽——更宽就是推上去被拒。客户端读到不合规则的值一律回落：
/// 数值夹到边上、数组滤掉认不出的、其余退回出厂值。
enum PrefsFieldRule: Equatable, Sendable {
  /// `true` / `false`。
  case bool
  /// 只收这几个字符串。
  case enumeration([String])
  /// 任意字符串，UTF-8 不超过 `maxBytes` 字节（服务端数字节，不数字符）。
  ///
  /// `known` 不为空时：服务端照样只看长度（更新的客户端可能写下新的取值，老服务端不挡），
  /// 客户端只认 `known` 里的那几个，别的退回出厂值。深浅、价格轴、K 线画法是这一档。
  case string(maxBytes: Int, known: [String]? = nil)
  /// 有限的数，闭区间。
  case number(min: Double, max: Double)
  /// 整数，闭区间。
  case int(min: Int, max: Int)
  /// 一个周期：契约 `instruments.json` 的 `intervals`，服务端另收 `legacyIntervals`（老存档里的 8h / 3d）。
  case interval
  /// 周期数组，最多 `maxCount` 个，每个同 `.interval`。
  case intervals(maxCount: Int)
  /// 字符串数组：每个都在 `values` 里、最多 `maxCount` 个；`unique` 时不许重复。
  case stringArray(values: [String], maxCount: Int, unique: Bool)
  /// 计次表：键在 `keys` 里、最多 `maxKeys` 个键，值是 0…`max` 的整数。
  case countMap(keys: [String], maxKeys: Int, max: Int)
  /// 通用描述装不下，服务端有一个同名的手写函数（`sync_validation.rs` 的 `custom_setting`）。
  /// 名字进契约，服务端测试保证每个名字都有函数、每个函数都有人用。
  case custom(String)
}

extension PrefsFieldPlan {
  /// **每个 `.synced` 字段的值规则。** 键必须和 `table` 里 `.synced` 的那些逐字相同
  /// （`PrefsFieldRulesTests` 穷举守着：漏一个、多一个都红）。
  ///
  /// 能从枚举派生的一律派生（`allCases.map(\.rawValue)`），不抄字面量——枚举加一个 case，
  /// 规则跟着变，`make sync-contract` 之后服务端与网页自动认它。
  static let rules: [String: PrefsFieldRule] = {
    let kinds = Drawing.Kind.allCases.map(\.rawValue)
    let overlays = IndicatorID.allCases.filter { $0.placement == .main }.map(\.rawValue)
    let subs = IndicatorID.allCases.filter { $0.placement == .sub }.map(\.rawValue)
    let spacing = PrefsFieldRule.number(min: AICoinBehavior.minimumSpacing, max: AICoinBehavior.maximumSpacing)
    return [
      // ---------------------------------------------------------------- 开关
      "redUp": .bool, "depth": .bool, "orderFlow": .bool, "orderFlowHistory": .bool,
      "mainInverted": .bool, "watchMoveAlert": .bool, "notifyListingChanges": .bool,
      "habitLearning": .bool, "drawingOverlaysShown": .bool, "drawingsHidden": .bool,
      "favoritesTrend": .bool, "bigTradeSigns": .bool,

      // ---------------------------------------------------------------- 几选一
      "skin": .enumeration(ThemeSkin.allCases.map(\.rawValue)),
      "sectorMarket": .enumeration(SectorMarket.allCases.map(\.rawValue)),
      "sectorWindow": .enumeration(SectorWindow.allCases.map(\.rawValue)),
      "alertSound": .enumeration(AlertSound.allCases.map(\.rawValue)),
      "reviewSearchScope": .enumeration(Prefs.searchScopes.sorted()),
      "reviewSegment": .enumeration(Prefs.reviewSegments.sorted()),
      "reviewBookFilter": .enumeration(Prefs.reviewBookFilters.sorted()),
      // 空串 = 还没用过画线工具。
      "lastDrawTool": .enumeration([""] + kinds),
      // 服务端只按长度收（`string(v,64)`）：这三个最早上线时值域还在变，老服务端不挡新取值。
      "theme": .string(maxBytes: 64, known: ThemeChoice.allCases.map(\.rawValue)),
      "priceMode": .string(maxBytes: 64, known: PriceMode.allCases.map(\.rawValue)),
      "candleKind": .string(maxBytes: 64, known: CandleKind.allCases.map(\.rawValue)),
      // 本机生成的分类 UUID；客户端找不到那个分类会退回第一类，服务端能老实卡的只有长度。
      "favoritesGroup": .string(maxBytes: 128),

      // ---------------------------------------------------------------- 数
      "barSpacing": spacing, "landscapeBarSpacing": spacing,

      // ---------------------------------------------------------------- 周期
      "interval": .interval,
      // 服务端收到 10 档：上限 2026-09-21 才从 10 收到 6（`Prefs.maxQuick`），老存档里七八档的不在少数，
      // 收紧服务端就是让那些老 body 在下一次合并时被洗掉。本机读进来再按 6 档截。
      "quickIntervals": .intervals(maxCount: 10),

      // ---------------------------------------------------------------- 列表
      // 主图 / 副图 / 副图翻转：只认各自那一档的指标，条数上限就是那一档的长度。服务端历来不查重。
      "overlays": .stringArray(values: overlays, maxCount: overlays.count, unique: false),
      "subs": .stringArray(values: subs, maxCount: subs.count, unique: false),
      "subInverted": .stringArray(values: subs, maxCount: subs.count, unique: false),
      // 自动分析层：每个最多一次（条数上限 = 词表长度，重复的放不下）。
      "autoLayers": .stringArray(values: AutoLayer.allCases.map(\.rawValue), maxCount: AutoLayer.allCases.count, unique: true),

      // ---------------------------------------------------------------- 计次表
      "drawToolUsage": .countMap(keys: kinds, maxKeys: Prefs.maxDrawToolUsageKeys, max: Prefs.maxDrawToolUsageCount),
      "analysisUsage": .countMap(
        keys: AnalysisSection.allCases.map(\.rawValue), maxKeys: Prefs.maxAnalysisUsageKeys, max: Prefs.maxDrawToolUsageCount),

      // ↑ new-sync-field:rule 在这一行上面插新字段（Tools/new-sync-field.py 认这一行，别删）
      // 脚手架插的条目落在这里；值得归类的话挪到上面对应的段。

      // ---------------------------------------------------------------- 手写规则（服务端 `custom_setting`）
      // 对比品种：完整身份键，代号段按交易所分流到注册表那一家的规则，最多三只、不重复。
      "compareSymbols": .custom("compare_symbols"),
      // 主力订单流门槛 / 步长：base → {spot?, usdtPerp?, coinPerp?, delivery?, step?}，数在契约 `orderFlow` 一段。
      "orderFlowOverrides": .custom("order_flow_overrides"),
      // 学到的结论：四张表各有键与值的规则，整份 ≤ 16 KB。
      "learnedDefaults": .custom("learned_defaults"),
      // 下面三个线上是拍平的路径（`params/<指标>`、`indicatorColors/<指标>/<序号>`、`subHeightOverrides/<指标>`）。
      "params": .custom("indicator_params"),
      "indicatorColors": .custom("indicator_colors"),
      "subHeightOverrides": .custom("sub_height_overrides"),
    ]
  }()
}
