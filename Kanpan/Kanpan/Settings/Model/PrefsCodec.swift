import Foundation
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
  static let version = 2
  /// 认得的最老存档。比它还老的是原型期那份键名完全不同的档（`styleID` / `recordButtonX`
  /// 那一代），读进来只会是一堆认不出的字段，不如直接退出厂值。
  static let oldestSupported = 2
  static let keyPrefix = "kanpan.prefs.v"

  /// 写进 `UserDefaults` 的那个键。
  static var key: String { key(version: version) }
  static func key(version: Int) -> String { "\(keyPrefix)\(version)" }

  static func encode(_ prefs: Prefs) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    // Prefs 的 encode 不会抛（全是标准类型），真抛了就当没存档。
    return (try? encoder.encode(prefs)) ?? Data()
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
  /// 现在是空的：版本 2 就是目前这一版，还没有需要往上修的老档。
  static func migrate(_ prefs: inout Prefs, from: Int) {
    guard from < version else { return }
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
    case indicatorColors
    case ambientTheme
    case depth, orderFlow, priceMode, magnet, countdown, keepAwake, launchSnapshot, timeZone, changeBasis
    case candleKind, gridChoice, bodyChoice, lastLine, sinceChange
    case viewAnchor, priceBias
    case dataDisplay, crossPrice, allowMainInversion, allowSubInversion
    case barSpacing, mainInverted, subInverted
    case adaptiveIndicators, portraitHeight, hiddenOutputs, rsiUpper, rsiLower
    case overlays, subs, params, subHeightOverrides
    // `apiHost` / `streamHost`（自定义行情域名）2026-09-24 删了：设置里早就没有入口，
    // 线路只剩直连 / 网关两档，主机一律由 `RouteResolver` 定。旧存档里的这两个键解码时忽略。
    case routePolicy
    // 他在各页上摆出来的样子。全是加法加进来的新键，老存档里没有就退默认值。
    case favoritesSort, favoritesAscending, favoritesAmount, favoritesSparkline
    case favoritesGroup
    case sectorMarket, sectorWindow, sectorSort
    case lastDrawTool
    case replaySpeed, reviewSearchScope
    case alertSound
    case watchMoveAlert, watchMoveThreshold
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(PrefsCodec.version, forKey: .v)
    try c.encode(compareSymbols, forKey: .compareSymbols)
    try c.encode(interval.rawValue, forKey: .interval)
    try c.encode(quickIntervals.map(\.rawValue), forKey: .quickIntervals)
    try c.encode(theme.rawValue, forKey: .theme)
    try c.encode(skin.rawValue, forKey: .skin)
    try c.encode(ambientTheme, forKey: .ambientTheme)
    try c.encode(redUp, forKey: .redUp)
    try c.encode(priceMode.rawValue, forKey: .priceMode)
    try c.encode(magnet, forKey: .magnet)
    try c.encode(depth, forKey: .depth)
    try c.encode(orderFlow, forKey: .orderFlow)
    try c.encode(countdown, forKey: .countdown)
    try c.encode(keepAwake, forKey: .keepAwake)
    try c.encode(launchSnapshot, forKey: .launchSnapshot)
    try c.encode(timeZone.rawValue, forKey: .timeZone)
    try c.encode(changeBasis.rawValue, forKey: .changeBasis)
    try c.encode(candleKind.rawValue, forKey: .candleKind)
    try c.encode(gridChoice.rawValue, forKey: .gridChoice)
    try c.encode(bodyChoice.rawValue, forKey: .bodyChoice)
    try c.encode(lastLine, forKey: .lastLine)
    try c.encode(sinceChange, forKey: .sinceChange)
    try c.encode(viewAnchor.rawValue, forKey: .viewAnchor)
    try c.encode(priceBias.rawValue, forKey: .priceBias)
    try c.encode(dataDisplay, forKey: .dataDisplay)
    try c.encode(crossPrice, forKey: .crossPrice)
    try c.encode(allowMainInversion, forKey: .allowMainInversion)
    try c.encode(allowSubInversion, forKey: .allowSubInversion)
    try c.encode(barSpacing, forKey: .barSpacing)
    try c.encode(mainInverted, forKey: .mainInverted)
    try c.encode(subInverted.map(\.rawValue).sorted(), forKey: .subInverted)
    try c.encode(adaptiveIndicators, forKey: .adaptiveIndicators)
    try c.encode(portraitHeight, forKey: .portraitHeight)
    try c.encode(Dictionary(uniqueKeysWithValues: hiddenOutputs.map { ($0.key.rawValue, $0.value.sorted()) }), forKey: .hiddenOutputs)
    try c.encode(Dictionary(uniqueKeysWithValues: indicatorColors.map { ($0.key.rawValue, $0.value) }), forKey: .indicatorColors)
    try c.encode(rsiUpper, forKey: .rsiUpper)
    try c.encode(rsiLower, forKey: .rsiLower)
    try c.encode(overlays.map(\.rawValue), forKey: .overlays)
    try c.encode(subs.map(\.rawValue), forKey: .subs)
    // 字典键是 enum，直接 encode 会变成交错数组；摊成 [String: …] 才是人能看懂的 JSON。
    try c.encode(Dictionary(uniqueKeysWithValues: params.map { ($0.key.rawValue, $0.value) }),
                 forKey: .params)
    try c.encode(Dictionary(uniqueKeysWithValues: subHeightOverrides.map { ($0.key.rawValue, $0.value) }), forKey: .subHeightOverrides)
    try c.encode(routePolicy.rawValue, forKey: .routePolicy)
    try c.encode(favoritesSort, forKey: .favoritesSort)
    try c.encode(favoritesAscending, forKey: .favoritesAscending)
    try c.encode(favoritesAmount, forKey: .favoritesAmount)
    try c.encode(favoritesSparkline, forKey: .favoritesSparkline)
    try c.encode(favoritesGroup, forKey: .favoritesGroup)
    try c.encode(sectorMarket.rawValue, forKey: .sectorMarket)
    try c.encode(sectorWindow.rawValue, forKey: .sectorWindow)
    try c.encode(sectorSort, forKey: .sectorSort)
    try c.encode(lastDrawTool, forKey: .lastDrawTool)
    try c.encode(replaySpeed, forKey: .replaySpeed)
    try c.encode(reviewSearchScope, forKey: .reviewSearchScope)
    try c.encode(alertSound.rawValue, forKey: .alertSound)
    try c.encode(watchMoveAlert, forKey: .watchMoveAlert)
    try c.encode(watchMoveThreshold, forKey: .watchMoveThreshold)
  }

  /// 历次出厂的常用行。存档里一字不差地躺着其中一串，就说明用户从没动过常用行。
  ///
  /// 常用行是每次装完就写进存档的，所以「没存过」这条路只对全新安装有效；老用户要吃到
  /// 新默认，只能靠认出「这串就是上一版出厂的样子」。反过来只要有一处不一样，那就是
  /// 用户自己钉的，一个字都不动。
  fileprivate static let factoryQuicks: [[Interval]] = [
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

    if let raw = strs(.quickIntervals) {
      var seen: [Interval] = []
      for r in raw {
        guard let iv = Interval(rawValue: r), !seen.contains(iv) else { continue }
        seen.append(iv)
      }
      // 存档里原样躺着上一版出厂的那串就当没动过，直接给新默认；只要有一处不一样
      // 就是用户自己钉过的，一个字都不改。
      if Self.factoryQuicks.contains(seen) { seen = Interval.quick }
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
    if let v = bool(.ambientTheme) { ambientTheme = v }
    if let v = bool(.redUp) { redUp = v }

    if let raw = str(.priceMode), let v = PriceMode(rawValue: raw) { priceMode = v }
    if let v = bool(.magnet) { magnet = v }
    if let v = bool(.depth) { depth = v }
    if let v = bool(.orderFlow) { orderFlow = v }
    if let v = bool(.countdown) { countdown = v }
    if let v = bool(.keepAwake) { keepAwake = v }
    if let v = bool(.launchSnapshot) { launchSnapshot = v }
    if let raw = str(.changeBasis), let v = ChangeBasis(rawValue: raw) { changeBasis = v }
    if let raw = str(.timeZone), let v = TZChoice(rawValue: raw) { timeZone = v }

    // 「图表」面板那几项。认不出的字面量一律退回默认（多半是降级回旧版本，
    // 或者手改存档手抖），不能因为一个字符串就让整档作废。
    if let raw = str(.candleKind), let v = CandleKind(rawValue: raw) { candleKind = v }
    if let raw = str(.gridChoice), let v = GridChoice(rawValue: raw) { gridChoice = v }
    // 旧存档里的 `"style"`（「跟随风格」那一档）读成实心：风格表只剩一套，两者等价。
    if let raw = str(.bodyChoice) { bodyChoice = raw == "style" ? .solid : BodyChoice(rawValue: raw) ?? bodyChoice }
    if let v = bool(.lastLine) { lastLine = v }
    if let v = bool(.sinceChange) { sinceChange = v }
    if let raw = str(.viewAnchor), let v = ViewAnchor(rawValue: raw) { viewAnchor = v }
    if let raw = str(.priceBias), let v = PriceBias(rawValue: raw) { priceBias = v }

    if let raw = str(.dataDisplay), let v = CandleDataDisplay(rawValue: raw) { dataDisplay = v }
    if let raw = str(.crossPrice), let v = CrossPriceMode(rawValue: raw) { crossPrice = v }
    if let v = bool(.allowMainInversion) { allowMainInversion = v }
    if let v = bool(.allowSubInversion) { allowSubInversion = v }
    // 存档里的根间距同样夹一道：手改过存档、或者以后动了上下限，都不能让图开在
    // 一个画不出来的宽度上。
    if let v = try? c.decode(Double.self, forKey: .barSpacing) { barSpacing = Prefs.clampSpacing(v) }
    if let v = bool(.mainInverted) { mainInverted = v }
    if let raw = strs(.subInverted) { subInverted = Set(Prefs.ids(raw, placement: .sub)) }
    if let v = bool(.adaptiveIndicators) { adaptiveIndicators = v }
    if let v = try? c.decode(Double.self, forKey: .portraitHeight), v.isFinite { portraitHeight = min(1, max(0, v)) }
    if let v = try? c.decode(Double.self, forKey: .rsiUpper), v.isFinite { rsiUpper = min(100, max(1, v)) }
    if let v = try? c.decode(Double.self, forKey: .rsiLower), v.isFinite { rsiLower = min(rsiUpper - 1, max(0, v)) }
    if let raw = try? c.decode([String: [Int]].self, forKey: .hiddenOutputs) {
      for (key, values) in raw {
        if let id = IndicatorID(rawValue: key) { hiddenOutputs[id] = Set(values.filter { (0..<21).contains($0) }) }
      }
    }

    if let raw = try? c.decode([String: [Int: Hex]].self, forKey: .indicatorColors) {
      for (key, values) in raw {
        guard let id = IndicatorID(rawValue: key) else { continue }
        indicatorColors[id] = values.filter { (0..<21).contains($0.key) && $0.value.value.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil }
      }
    }
    if let raw = strs(.overlays) {
      overlays = Prefs.ids(raw, placement: .main)
    }
    if let raw = strs(.subs) {
      subs = Array(Prefs.ids(raw, placement: .sub).prefix(Prefs.maxSubs))
    }

    if let raw = (try? c.decodeIfPresent([String: [Int]].self, forKey: .params)) ?? nil {
      var out: [IndicatorID: [Int]] = [:]
      for (k, v) in raw {
        guard let id = IndicatorID(rawValue: k) else { continue }   // 认不出的指标直接丢
        out[id] = IndicatorParamRule.sanitize(v, for: id)           // 越界的夹回来
      }
      params = out
    }

    if let raw = try? c.decode([String: Double].self, forKey: .subHeightOverrides) {
      for (key, scale) in raw {
        if let id = IndicatorID(rawValue: key), id.placement == .sub, scale.isFinite {
          subHeightOverrides[id] = min(2, max(0.5, scale))
        }
      }
    }

    // 认不出的值（比如旧版本的「自动」）退回直连。
    if let raw = str(.routePolicy), let v = MarketRoutePolicy(rawValue: raw) { routePolicy = v }

    // 他在各页上摆出来的样子。全走 `decodeIfPresent`：老存档里一个都没有，
    // 缺了就留在上面那份 `.defaults` 给的出厂值上。
    if let raw = str(.favoritesSort), Prefs.favoriteSorts.contains(raw) { favoritesSort = raw }
    if let v = bool(.favoritesAscending) { favoritesAscending = v }
    if let v = bool(.favoritesAmount) { favoritesAmount = v }
    if let v = bool(.favoritesSparkline) { favoritesSparkline = v }
    // 分类 id 是本机生成的 UUID 串，认不认得出交给 `SymbolPrefs.group(_:)`；
    // 这儿只拦长度，128 这个数和服务端 `sync_validation.rs` 给它的上限逐字相同。
    if let raw = str(.favoritesGroup), raw.count <= 128 { favoritesGroup = raw }
    if let raw = str(.sectorMarket), let v = SectorMarket(rawValue: raw) { sectorMarket = v }
    if let raw = str(.sectorWindow), let v = SectorWindow(rawValue: raw) { sectorWindow = v }
    // 排序口径那个枚举在 app target 里，这一层认不出来，只做长度这一道；
    // 认不认得出交给读的那一边（`SectorSymbolSort(rawValue:) ?? .change`）。
    if let raw = str(.sectorSort), !raw.isEmpty, raw.count <= 32 { sectorSort = raw }
    if let raw = str(.lastDrawTool), raw.count <= 32 { lastDrawTool = raw }
    if let v = (try? c.decodeIfPresent(Int.self, forKey: .replaySpeed)) ?? nil { replaySpeed = Prefs.clampSpeed(v) }
    if let raw = str(.reviewSearchScope), Prefs.searchScopes.contains(raw) { reviewSearchScope = raw }
    if let raw = str(.alertSound), let sound = AlertSound(rawValue: raw) { alertSound = sound }
    if let v = bool(.watchMoveAlert) { watchMoveAlert = v }
    if let v = (try? c.decodeIfPresent(Double.self, forKey: .watchMoveThreshold)) ?? nil {
      watchMoveThreshold = WatchMove.clampThreshold(v)
    }

    if let raw = strs(.compareSymbols) { compareSymbols = Prefs.cleanCompareSymbols(raw) }
    PrefsCodec.migrate(&self, from: archived)
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
