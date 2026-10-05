import Foundation
import os
import KanpanCore
import KanpanData
import KanpanNetwork

// MARK: - 落盘格式

/// Current chart preferences only. Old prototype archives are not migrated.
enum PrefsCodec {
  /// 当前存档版本。
  ///
  /// **改了默认值要把它 +1，同时在 `migrate` 里补一条——版本号自己什么都不做了。**
  ///
  /// 这儿原来写的是「改任何一个默认值都要把它 +1」，而 `Prefs.init(from:)` 撞上对不上的
  /// 版本号就直接 `return`：整份存档连一个字段都不读，全退出厂值。也就是说下一个改
  /// 默认值的人只要照着这句注释把版本号 +1，就会把**所有人的全部偏好清空一次**。
  /// `UserDefaults` 那一侧还看不太出来（键名带版本号，换版本等于换键，旧档躺在旧键上
  /// 谁也没删），账号档案那一侧跑不掉——`PersonalFileStorage` 读的是固定的 prefs.json，
  /// 版本一变，四十多个字段当场归零。
  ///
  /// 2026-09-19 改成：版本对不上也照读每一个字段（每个字段本来就是一项一项容错解码的），
  /// 这一版真正改了默认值的那几项交给 `migrate` 点名修。
  ///
  /// 3（2026-09-26）：「认出上一版出厂的常用行就换成新默认」从 `init(from:)` 挪进
  /// `migrate`。原来那段每次解码都跑——而同步合并、撤销、账号切换一路都是先编码再解码，
  /// 于是用户**亲手**钉成 5m/30m/1h/4h/1d 的常用行，下一次随便哪条路一过就被改回出厂。
  /// 只有写着 2 的老档才该被这样认；3 起写下的档，那串就是用户自己的选择。
  ///
  /// 4（2026-10-03）：用户「现在一律默认绿涨红跌」。出厂从红涨改成绿涨，而且是「一律」——
  /// 老档不论存的是什么都迁成绿涨一次；4 起写下的档里若是红涨，那就是用户自己切回去的，不再动。
  static let version = 4
  /// 认得的最老存档。比它还老的是原型期那份键名完全不同的档（`styleID` / `recordButtonX`
  /// 那一代），读进来只会是一堆认不出的字段，不如直接退出厂值。
  static let oldestSupported = 2
  static let keyPrefix = "kanpan.prefs.v"
  /// `UserDefaults` 键名里那个数字。**钉死在 2，不跟 `version` 走**：档内的 `v` 已经
  /// 足够让 `migrate` 知道该修什么；键名要是跟着 +1，未登录那份设置会当场躺在一个再也
  /// 没人读的旧键上（上面那段注释说的就是这件事）。
  static let storageVersion = 2

  /// 写进 `UserDefaults` 的那个键。
  static var key: String { key(version: storageVersion) }
  static func key(version: Int) -> String { "\(keyPrefix)\(version)" }

  private static let log = Logger(subsystem: "com.kanpan.app", category: "prefs")

  /// 编码。**编不出来就是 nil**——调用方拿到 nil 必须什么都不写、留着上一份。
  ///
  /// 原来这儿编不出来就交一个空 `Data()` 出去，`PrefsStore` 照单写盘：空档读回来是
  /// `.defaults`，于是一次编码失败 = 全部偏好清零。JSONEncoder 真会抛的只有一种情况：
  /// 某个 `Double` 是 NaN / ±∞（它不肯写非数），所以编码之前先 `sanitized` 一遍，
  /// 把每一个浮点字段夹回合法区间；夹完还抛就记一条日志，交 nil。
  static func encoded(_ prefs: Prefs) -> Data? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    do {
      return try encoder.encode(sanitized(prefs))
    } catch {
      log.error("prefs encode failed, keeping previous archive: \(String(describing: error), privacy: .public)")
      return nil
    }
  }

  /// 兼容老调用方（账号那一侧还按「一定有 Data」在用）。`sanitized` 之后 `encoded`
  /// 实际上不会失败；真失败了这里仍交空 `Data()`，**写盘的路一律改走 `encoded`**。
  static func encode(_ prefs: Prefs) -> Data { encoded(prefs) ?? Data() }

  /// 编码前把每一个浮点字段夹回合法区间：非数退回出厂值，越界夹到边上。
  /// 和 `init(from:)` 里读的那一道是同一组规则——写进去的和读得回来的一样。
  static func sanitized(_ prefs: Prefs) -> Prefs {
    var p = prefs
    p.barSpacing = Prefs.clampSpacing(p.barSpacing)
    p.portraitHeight = Prefs.clampPortraitHeight(p.portraitHeight)
    p.subHeightOverrides = p.subHeightOverrides.compactMapValues { $0.isFinite ? min(2, max(0.5, $0)) : nil }
    p.orderFlowOverrides = p.orderFlowOverrides.compactMapValues { $0.normalized }
    p.learnedDefaults = p.learnedDefaults.sanitized()
    return p
  }

  /// 永远给得出一份能用的设置：坏档、半截档、未来版本的档，都退回默认再往上并。
  static func decode(_ data: Data?) -> Prefs {
    guard let data, !data.isEmpty else { return .defaults }
    return (try? JSONDecoder().decode(Prefs.self, from: data)) ?? .defaults
  }

  /// 老存档读完之后的逐版修补。
  ///
  /// 每次 `version` +1 就在这儿补一段 `if from < N { ... }`，**只动这一版真的改了默认值的
  /// 那几个字段**，别的一个字都不碰。`from` 是存档里写着的版本；比当前还新（用户从更高
  /// 版本降级回来）时什么都不做，那一版新加的字段解码时已经当认不出忽略掉了。
  ///
  ///
  /// `archivedQuicks`：存档里原样写着的常用行（只去重、没排序、没按上限截）。出厂的七档
  /// 那一版截到六档之后就认不出来了，所以比对要拿截之前的那串。
  static func migrate(_ prefs: inout Prefs, from: Int, archivedQuicks: [Interval]? = nil) {
    guard from < version else { return }
    // 3：存档里原样躺着某一版出厂的常用行，就说明用户从没动过——换成新默认。
    if from < 3, let quicks = archivedQuicks, Prefs.factoryQuicks.contains(quicks) { prefs.quickIntervals = Interval.quick }
    // 4：一律绿涨红跌（云端那份由服务端迁移 0041 同时翻，免得同步再盖回红涨）。
    if from < 4 { prefs.redUp = false }
    // 样板（真要用时照这个写）：版本 3 把出厂皮肤从青苔改成陶土，没手动挑过皮肤的
    // 老用户该跟着换，挑过的一个字不动——
    // if from < 3, prefs.skin == .moss { prefs.skin = .clay }
  }
}

// MARK: - 容错解码

extension Prefs: Codable {
  enum CodingKeys: String, CodingKey {
    case v
    case compareSymbols
    case interval, quickIntervals
    case theme, skin, redUp
    // 这儿原来还有 `styleID`：十二款蜡烛造型里挑一款的那阵子存的选择。现在只剩 AICoin
    // 一套，老存档里的那个键读的时候认不出来，直接忽略。
    // 这儿原来还有 `recordButtonX/Y`：「记」还浮在图上、能拖着摆的那阵子存的位置。
    // 现在「记」住在周期条上，没有位置可存了。老存档里那两个键读的时候认不出来，
    // 直接忽略（这份编解码是一个键一个键 `try?` 取的，多出来的键不会让整份存档解不开）。
    // `showDrawings`（全局画线开关）和 `subHeights`（副图三档高度）同理：2026-09-24 两端删掉，
    // 老存档、云端老 body 里还带着也无妨。`favoritesExpanded`（自选页展开着详情的那几行）
    // 也是同一天删的：审查 U9 把行内展开收掉了，品种详情只剩长按那张预览卡。
    // `launchSnapshot`（启动快照开关）同一天删：界面上早没有入口，启动快照一律开着。
    // 它一直是 deviceOnly，从没上过服务端，老存档里的键读的时候忽略。
    case indicatorColors
    // `ambientTheme`（按屏幕亮度切深浅）、`keepAwake`（盯盘不锁屏）、`timeZone`（时区三档）、
    // `changeBasis`（涨跌幅起点）2026-09-28 收掉（收设置项 A 组）：老存档、云端老 body 里还带着
    // 这几个键，读的时候认不出来直接忽略，服务端在 RETIRED_SETTINGS_FIELDS 里退役。
    // `magnet`（十字线吸附）、`countdown`、`gridChoice`、`bodyChoice`、`lastLine`、`sinceChange`、
    // `viewAnchor`、`priceBias`、`dataDisplay`、`crossPrice`、`allowMainInversion`、`allowSubInversion`、
    // `adaptiveIndicators` 2026-09-28 收掉（收设置项 B 组）：图一律按 `Prefs.chartOptions` 的定值画，
    // 老存档、云端老 body 里的这些键读时忽略，服务端退役。
    case depth, orderFlow, priceMode
    // 主力订单流的门槛 / 步长改动（2026-09-24 逐单模型那一轮加的）。四个显示开关（`orderFlowSpot`、
    // `orderFlowContract`、`orderFlowShowFilled`、`orderFlowShowCancelled`）以及更早按买卖拆开的
    // `orderFlowFilledBid/Ask`、`orderFlowCancelledBid/Ask` 2026-09-28 收掉（收设置项 D 组），老档读时忽略。
    case orderFlowOverrides
    case candleKind
    case barSpacing, mainInverted, subInverted
    // `hiddenOutputs`、`rsiUpper`、`rsiLower` 2026-09-28 收掉（收设置项 C 组），老档里的这几个键读时忽略；
    // `indicatorLayouts/<组>` 里嵌着的 `hiddenOutputs` 同样忽略。
    case portraitHeight
    case overlays, subs, params, subHeightOverrides
    // 指标按周期分组记忆（2026-09-27 到 10-02）留下的键：10-03 起布局一人一份，上面那六个键就是
    // 那一份；这个键只读老档（取当前周期那组），写出去永远是空表，见 `IndicatorLayouts.swift`。
    case indicatorLayouts
    // `apiHost` / `streamHost`（自定义行情域名）2026-09-24 删了：设置里早就没有入口，
    // 线路只剩直连 / 网关两档，主机一律由 `RouteResolver` 定。旧存档里的这两个键解码时忽略。
    case routePolicy
    // 他在各页上摆出来的样子。全是加法加进来的新键，老存档里没有就退默认值。
    // `favoritesSort` / `favoritesAscending` / `favoritesAmount` / `favoritesSparkline` / `sectorSort`
    // 2026-09-28 收掉（收设置项 G）：老存档里的键读时忽略，服务端退役。
    case favoritesGroup
    case sectorMarket, sectorWindow
    case lastDrawTool
    case drawingOverlaysShown
    // `replaySpeed`（回放倍速）2026-09-28 收掉（收设置项）：老存档里的键读时忽略，服务端退役。
    case reviewSearchScope
    case alertSound
    // `watchMoveThreshold` 2026-09-28 收掉（收设置项 E 组），老档读时忽略。
    case watchMoveAlert
    case notifyListingChanges
    // 「按我的习惯自动调整」（2026-09-28）：开关 + 学到的结论（整份一个对象）。
    case habitLearning, learnedDefaults
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(PrefsCodec.version, forKey: .v)
    try c.encode(compareSymbols, forKey: .compareSymbols)
    try c.encode(interval.rawValue, forKey: .interval)
    try c.encode(quickIntervals.map(\.rawValue), forKey: .quickIntervals)
    try c.encode(theme.rawValue, forKey: .theme)
    try c.encode(skin.rawValue, forKey: .skin)
    try c.encode(redUp, forKey: .redUp)
    try c.encode(depth, forKey: .depth)
    try c.encode(orderFlow, forKey: .orderFlow)
    try c.encode(orderFlowOverrides, forKey: .orderFlowOverrides)
    try c.encode(barSpacing, forKey: .barSpacing)
    try c.encode(mainInverted, forKey: .mainInverted)
    try c.encode(subInverted.map(\.rawValue).sorted(), forKey: .subInverted)
    try c.encode(portraitHeight, forKey: .portraitHeight)
    try c.encode(Dictionary(uniqueKeysWithValues: indicatorColors.map { ($0.key.rawValue, $0.value) }), forKey: .indicatorColors)
    // 指标布局：老键写这个人的那一份；`indicatorLayouts` 永远是空表（键留着，老客户端读得懂、云端残留的分叉被清掉）。
    let book = layoutBook
    try Prefs.encode(book.shared, into: &c)
    var groups = c.nestedContainer(keyedBy: IntervalGroup.self, forKey: .indicatorLayouts)
    for group in IntervalGroup.allCases {
      guard let fork = book.forks[group] else { continue }
      var one = groups.nestedContainer(keyedBy: CodingKeys.self, forKey: group)
      try Prefs.encode(fork, into: &one)
    }
    try c.encode(routePolicy.rawValue, forKey: .routePolicy)
    try c.encode(favoritesGroup, forKey: .favoritesGroup)
    try c.encode(sectorMarket.rawValue, forKey: .sectorMarket)
    try c.encode(sectorWindow.rawValue, forKey: .sectorWindow)
    try c.encode(lastDrawTool, forKey: .lastDrawTool)
    try c.encode(drawingOverlaysShown, forKey: .drawingOverlaysShown)
    try c.encode(reviewSearchScope, forKey: .reviewSearchScope)
    try c.encode(alertSound.rawValue, forKey: .alertSound)
    try c.encode(watchMoveAlert, forKey: .watchMoveAlert)
    try c.encode(notifyListingChanges, forKey: .notifyListingChanges)
    try c.encode(habitLearning, forKey: .habitLearning)
    try c.encode(learnedDefaults, forKey: .learnedDefaults)
  }

  /// 指标布局的六个键。顶层和老档 `indicatorLayouts/<组>` 里写法一样。
  private static func encode(_ layout: IndicatorLayout, into c: inout KeyedEncodingContainer<CodingKeys>) throws {
    let l = layout.sanitized
    try c.encode(l.priceMode.rawValue, forKey: .priceMode)
    try c.encode(l.candleKind.rawValue, forKey: .candleKind)
    try c.encode(l.overlays.map(\.rawValue), forKey: .overlays)
    try c.encode(l.subs.map(\.rawValue), forKey: .subs)
    // 字典键是 enum，直接 encode 会变成交错数组；摊成 [String: …] 才是人能看懂的 JSON。
    try c.encode(Dictionary(uniqueKeysWithValues: l.params.map { ($0.key.rawValue, $0.value) }), forKey: .params)
    try c.encode(Dictionary(uniqueKeysWithValues: l.subHeightOverrides.map { ($0.key.rawValue, $0.value) }), forKey: .subHeightOverrides)
  }

  /// 反过来：档里有哪一键就整项换掉哪一项，没有的留着 `layout` 原来的值
  /// （顶层从出厂起步；分叉那份从共用的那份起步——半截的分叉档缺的项就跟共用的走）。
  /// 认不出的字面量、放错位置的指标、越界的数，规则和原来顶层那几段一模一样。
  private static func decode(_ c: KeyedDecodingContainer<CodingKeys>, into layout: inout IndicatorLayout) {
    func str(_ k: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil }
    func strs(_ k: CodingKeys) -> [String]? { (try? c.decodeIfPresent([String].self, forKey: k)) ?? nil }
    if let raw = str(.priceMode), let v = PriceMode(rawValue: raw) { layout.priceMode = v }
    if let raw = str(.candleKind), let v = CandleKind(rawValue: raw) { layout.candleKind = v }
    if let raw = strs(.overlays) { layout.overlays = Prefs.ids(raw, placement: .main) }
    // 成交量不占名额：网页推上来的是「成交量 + 最多三个」，四项都要留住（`Prefs.cappedSubs`）。
    if let raw = strs(.subs) { layout.subs = Prefs.cappedSubs(Prefs.ids(raw, placement: .sub)) }
    if let raw = (try? c.decodeIfPresent([String: [Int]].self, forKey: .params)) ?? nil {
      var out: [IndicatorID: [Int]] = [:]
      for (k, v) in raw {
        guard let id = IndicatorID(rawValue: k) else { continue }   // 认不出的指标直接丢
        out[id] = IndicatorParamRule.sanitize(v, for: id)           // 越界的夹回来
      }
      layout.params = out
    }
    if let raw = try? c.decode([String: Double].self, forKey: .subHeightOverrides) {
      var out: [IndicatorID: Double] = [:]
      for (key, scale) in raw {
        if let id = IndicatorID(rawValue: key), id.placement == .sub, scale.isFinite { out[id] = min(2, max(0.5, scale)) }
      }
      layout.subHeightOverrides = out
    }
  }

  /// 历次出厂的常用行。存档里一字不差地躺着其中一串，就说明用户从没动过常用行。
  ///
  /// 常用行是每次装完就写进存档的，所以「没存过」这条路只对全新安装有效；老用户要吃到
  /// 新默认，只能靠认出「这串就是上一版出厂的样子」。反过来只要有一处不一样，那就是
  /// 用户自己钉的，一个字都不动。
  static let factoryQuicks: [[Interval]] = [
    [.m1, .m5, .m15, .h1, .h4, .d1],        // 更早的六档
    [.m1, .m5, .m15, .m30, .h1, .h4, .d1],  // 收成五档之前的七档
    [.m5, .m30, .h1, .h4, .d1],             // 2026-09-21 放满六格之前的五档
  ]

  init(from decoder: Decoder) throws {
    // 从新默认起步：存档只往上盖它真有的那几项（A6.13）。
    self = .defaults
    guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
    // 存档里写着的版本。没写的当成当前版本（`encode` 一直都写，读到没有多半是手写的档）。
    // 只有比 `oldestSupported` 还老的原型档才整份不读；其余版本一律**照读每一个字段**，
    // 该按版本修的那几项走末尾的 `PrefsCodec.migrate`。详见 `PrefsCodec.version` 的注释。
    let archived = (try? c.decode(Int.self, forKey: .v)) ?? PrefsCodec.version
    guard archived >= PrefsCodec.oldestSupported else { return }

    func str(_ k: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil }
    func bool(_ k: CodingKeys) -> Bool? { (try? c.decodeIfPresent(Bool.self, forKey: k)) ?? nil }
    func strs(_ k: CodingKeys) -> [String]? { (try? c.decodeIfPresent([String].self, forKey: k)) ?? nil }

    if let raw = str(.interval), let v = Interval(rawValue: raw) { interval = v }

    var archivedQuicks: [Interval]?
    if let raw = strs(.quickIntervals) {
      var seen: [Interval] = []
      for r in raw {
        guard let iv = Interval(rawValue: r), !seen.contains(iv) else { continue }
        seen.append(iv)
      }
      // 「认出上一版出厂的那串就换新默认」只对写着 2 的老档做，在末尾的 `PrefsCodec.migrate`
      // 里（版本 3 起）。原来放在这儿每次解码都跑，用户亲手钉成同一串也会被改回去。
      archivedQuicks = seen
      // 上限 2026-09-21 从 10 收到 6，存档里躺着七八档的不在少数。砍之前先按周期从短到长
      // 排一遍再取前六个：直接 `prefix` 砍的是「存档里写在前面的那几个」，那个顺序是
      // 历史包袱（手改的档、更早版本的写法），砍出来的六档可能是 1d 1w 1M 这种全长周期。
      let order = Interval.allCases
      seen.sort { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
      if !seen.isEmpty { quickIntervals = Array(seen.prefix(Prefs.maxQuick)) }
    }

    // 老存档里可能还写着「护眼 / 夜读」那两档（`paper` / `night`）：那时候配色和深浅
    // 焊在一起，现在拆成了两根轴，认不出来的字面量一律退回出厂的「跟随系统 + 青苔」。
    if let raw = str(.theme), let v = ThemeChoice(rawValue: raw) { theme = v }
    if let raw = str(.skin), let v = ThemeSkin(rawValue: raw) { skin = v }
    if let v = bool(.redUp) { redUp = v }

    if let v = bool(.depth) { depth = v }
    if let v = bool(.orderFlow) { orderFlow = v }
    // 改过的门槛 / 步长：认不出的 base、越界的数一项一项丢，不让一只坏档拖垮整张表。
    if let raw = try? c.decode([String: OrderFlowOverride].self, forKey: .orderFlowOverrides) {
      for base in raw.keys.sorted() where orderFlowOverrides.count < Prefs.maxOrderFlowOverrides {
        if OrderFlowBase.isValid(base), let value = raw[base]?.normalized { orderFlowOverrides[base] = value }
      }
    }
    // 存档里的根间距同样夹一道：手改过存档、或者以后动了上下限，都不能让图开在
    // 一个画不出来的宽度上。
    if let v = try? c.decode(Double.self, forKey: .barSpacing) { barSpacing = Prefs.clampSpacing(v) }
    if let v = bool(.mainInverted) { mainInverted = v }
    if let raw = strs(.subInverted) { subInverted = Set(Prefs.ids(raw, placement: .sub)) }
    if let v = try? c.decode(Double.self, forKey: .portraitHeight), v.isFinite { portraitHeight = Prefs.clampPortraitHeight(v) }

    if let raw = try? c.decode([String: [Int: Hex]].self, forKey: .indicatorColors) {
      for (key, values) in raw {
        guard let id = IndicatorID(rawValue: key) else { continue }
        indicatorColors[id] = values.filter { (0..<21).contains($0.key) && $0.value.value.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil }
      }
    }
    // 指标布局一人一份、不分周期（2026-10-03）。老键就是那一份；老档（与老客户端写在云端的）
    // `indicatorLayouts` 里还有按周期分的叉时，取当前周期所在组那一份当作唯一那份，其余丢掉。
    var shared = indicatorLayout
    Prefs.decode(c, into: &shared)
    var book = IndicatorLayoutBook(shared: shared)
    if let groups = try? c.nestedContainer(keyedBy: IntervalGroup.self, forKey: .indicatorLayouts) {
      for group in IntervalGroup.allCases {
        guard let one = try? groups.nestedContainer(keyedBy: CodingKeys.self, forKey: group) else { continue }
        var fork = shared
        Prefs.decode(one, into: &fork)
        book.forks[group] = fork
      }
    }
    adopt(book)
    collapseIndicatorLayouts()

    // 认不出的值（比如旧版本的「自动」）退回直连。
    if let raw = str(.routePolicy), let v = MarketRoutePolicy(rawValue: raw) { routePolicy = v }

    // 他在各页上摆出来的样子。全走 `decodeIfPresent`：老存档里一个都没有，
    // 缺了就留在上面那份 `.defaults` 给的出厂值上。
    // 分类 id 是本机生成的 UUID 串，认不认得出交给 `SymbolPrefs.group(_:)`；
    // 这儿只拦长度，128 这个数和服务端 `sync_validation.rs` 给它的上限逐字相同——
    // 服务端 `string(v, 128)` 数的是 **UTF-8 字节**，所以这儿也数字节，不数字符：
    // 原来 `raw.count` 数的是字形簇，128 个汉字（384 字节）本地收下、推上去整条被拒。
    if let raw = str(.favoritesGroup), raw.utf8.count <= 128 { favoritesGroup = raw }
    if let raw = str(.sectorMarket), let v = SectorMarket(rawValue: raw) { sectorMarket = v }
    if let raw = str(.sectorWindow), let v = SectorWindow(rawValue: raw) { sectorWindow = v }
    // 和服务端 `sync_validation.rs` 的值规则逐字对齐：画线工具只认 `Drawing.Kind` 里有的
    // （或空串 = 没用过）。认不出的退回出厂值，不让一个手改 / 更高版本写下的字面量躺进档里、
    // 再被推上去整条拒收。
    if let raw = str(.lastDrawTool) { lastDrawTool = raw.isEmpty || Drawing.Kind(rawValue: raw) != nil ? raw : "" }
    if let v = bool(.drawingOverlaysShown) { drawingOverlaysShown = v }
    if let raw = str(.reviewSearchScope), Prefs.searchScopes.contains(raw) { reviewSearchScope = raw }
    if let raw = str(.alertSound), let sound = AlertSound(rawValue: raw) { alertSound = sound }
    if let v = bool(.watchMoveAlert) { watchMoveAlert = v }
    if let v = bool(.notifyListingChanges) { notifyListingChanges = v }
    if let v = bool(.habitLearning) { habitLearning = v }
    // 结论表自己宽容解码（坏的那一条丢掉、别的留着），整份读不出就当没学到。
    if let v = (try? c.decodeIfPresent(LearnedDefaults.self, forKey: .learnedDefaults)) ?? nil { learnedDefaults = v }

    if let raw = strs(.compareSymbols) { compareSymbols = Prefs.cleanCompareSymbols(raw) }
    PrefsCodec.migrate(&self, from: archived, archivedQuicks: archivedQuicks)
  }

  /// 一串 rawValue → 去重、去掉认不出的、去掉放错位置的指标。
  /// 退役的那几把（`IndicatorID.retired`）在这里滤掉：枚举里还留着它们的 case，
  /// 所以老存档照样解得出来，只是解出来之后不再挂到图上——面板上已经没有这一行了，
  /// 留着它用户就只能看着它却关不掉。
  private static func ids(_ raw: [String], placement: IndicatorID.Where) -> [IndicatorID] {
    var out: [IndicatorID] = []
    for r in raw {
      guard let id = IndicatorID(rawValue: r), id.placement == placement, !id.isRetired,
        !out.contains(id)
      else { continue }
      out.append(id)
    }
    return out
  }
}
