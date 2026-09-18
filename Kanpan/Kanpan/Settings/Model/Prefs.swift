import Foundation
import KanpanCore
import KanpanData

/// 一份完整的设置（任务书 §3.2 的 `AppState` 里可持久化的那一半）。
///
/// 纯值类型、`Sendable`，读的人拿到的是快照，不会被别的线程改到。
/// 默认 AICoin 风格、1h、MA 与 VOL/OI/MACD，具体参数见 AICoinBehavior。
/// 已存设置通过容错解码保留，不在启动时强行重置。
///
/// 品种、自选、最近**不在这里**——那三样归 `SymbolPrefs`（`kanpan.symbols.v1`），
/// 画线归 `DrawStore`。这里只管「设置」四个面板能改的东西。
struct Prefs: Sendable, Equatable {

  // ---------------------------------------------------------------- 周期
  /// 当前周期。原型 `S.interval` 恒从 `'1h'` 起步。
  var interval: Interval = .h1
  /// 周期条第一行的常用档（原型 `QUICK`）。§10.6：长按可增删，最多 10 个。
  var quickIntervals: [Interval] = Interval.quick

  // ---------------------------------------------------------------- 外观
  /// 跟随系统 / 浅 / 深（A6.3）。
  var theme: ThemeChoice = .system
  /// 配色：青苔（冷）/ 陶土（暖）。出厂青苔。
  var skin: ThemeSkin = .sage
  // Keep the manual choice intact; automatic brightness selection is runtime-only.
  var ambientTheme = false
  /// 涨跌对调（A6.7）。国内看盘习惯是红涨绿跌，出厂就给红涨；
  /// 老用户存档里存过什么就还是什么，这儿只改「从没设过」的那一档默认值。
  var redUp: Bool = true

  // ---------------------------------------------------------------- 图
  /// 价格轴 常规 / 对数 / 百分比（A6.8）。
  var priceMode: PriceMode = .log
  /// 十字线磁吸（§7 长按那一行）。原型 `chart.magnet = true`。
  var magnet: Bool = false
  /// 本根倒计时，默认关；前台时钟独立更新。
  var countdown: Bool = false
  /// 蜡烛 / 平均K线（Heikin-Ashi）。默认蜡烛。
  var candleKind: CandleKind = .candle
  /// 共用网格，默认关闭；旧存档的跟随风格枚举按共用默认解析。
  var gridChoice: GridChoice = .off
  /// 阳线实体：实心 / 空心。默认实心，也就是 AICoin 的画法。
  var bodyChoice: BodyChoice = .solid
  /// 最新价横线 + 右轴胶囊。默认开。
  var lastLine: Bool = true
  /// 用户画的线显不显示（数据不删）。默认显示。
  var showDrawings: Bool = true
  /// 十字线打开时，多报一段「选中那根到最新价」的涨跌幅。默认关。
  var sinceChange: Bool = false
  /// 复位到最新时，最新一根落在横向哪儿。默认靠右（现状）。
  var viewAnchor: ViewAnchor = .right
  /// 蜡烛在主图区里整体偏上 / 居中 / 偏下。总留白量不变，只改上下分配，
  /// 所以蜡烛大小不变，只是位置挪。默认居中（现状）。
  var priceBias: PriceBias = .center
  var dataDisplay: CandleDataDisplay = .inside
  var crossPrice: CrossPriceMode = .selected
  /// 默认关，理由见 `ChartOptions.allowMainInversion`。
  var allowMainInversion = false
  var allowSubInversion = false
  /// 用户缩放到的根间距（pt）。
  ///
  /// 「我要一屏看多少根」是**人的习惯**，不是某个品种的属性：以前它只活在图自己身上，
  /// 换品种一律回到出厂的 4pt，用户捏小了去自选点下一个品种，K 线又变回一屏五十根。
  /// 所以把它挪到设置里，跟皮肤、副图高度同一等级——所有品种、所有周期共用一份，
  /// 跨 app 重启也在。没存过就是出厂的 `initialSpacing`。
  ///
  /// 唯一不读它的是显式的「重置视野」：重置的语义就是回出厂值（见
  /// `ChartView.resetView()`），跟着偏好走就没有「回到出厂」这个动作了。
  ///
  /// ⚠️ **这一份是「盘上那一份」，写入是节流的**（`PrefsStore.noteBarSpacing`），
  /// 它只管下次冷启动。本程内要「用户此刻捏到多宽」请读 `PrefsStore.liveBarSpacing`，
  /// 那一份手一动就变——用户捏完立刻换周期换品种，靠的是它。
  var barSpacing: Double = AICoinBehavior.initialSpacing
  /// 主图上下翻转（双击价格轴）。和根间距同理：是「我习惯怎么看」，不是这个品种的属性。
  /// 要 `allowMainInversion` 开着才生效——开关关掉时不认这一份，免得翻过去再也翻不回来。
  var mainInverted = false
  /// 哪几个副图被上下翻转（双击副图那一侧）。同上，要 `allowSubInversion` 开着才生效。
  var subInverted: Set<IndicatorID> = []
  var adaptiveIndicators = false
  var compactValues = false
  var portraitHeight = 0.5
  var indicatorColors: [IndicatorID: [Int: Hex]] = [:]
  var hiddenOutputs: [IndicatorID: Set<Int>] = [:]
  var rsiUpper = 70.0
  var rsiLower = 30.0
  /// 盯盘时不锁屏（§10.4，默认开）。
  var keepAwake: Bool = true
  /// 启动快照（§4.3「设置里『启动快照』开关，默认开」）。
  var launchSnapshot: Bool = true
  /// 时区（A6.9）。Core 的 `TZChoice` 已经是原型的口径：本地 / UTC / 交易所。
  var timeZone: TZChoice = .local
  var changeBasis: ChangeBasis = .rolling24h

  // ---------------------------------------------------------------- 指标
  /// 主图叠加，按打开先后排。默认 `[.ma]`。
  var overlays: [IndicatorID] = IndicatorID.defaultOverlays
  /// 副图从上往下的顺序，默认 VOL/OI/MACD。
  var subs: [IndicatorID] = AICoinBehavior.subpanels
  /// 每个指标的参数。没记的取 `IndicatorID.defaultParams`。
  var params: [IndicatorID: [Int]] = [.ma: AICoinBehavior.maPeriods, .ema: [12, 144, 169, 200], .vol: AICoinBehavior.volumePeriods, .macd: AICoinBehavior.macdPeriods]
  /// 每个副图的高度档（A6.4）。没记的是「中」。
  var subHeights: [IndicatorID: SubPaneHeight] = [:]
  /// Direct divider drags override the three preset heights, keyed by panel identity.
  var subHeightOverrides: [IndicatorID: Double] = [:]

  // ---------------------------------------------------------------- 网络
  /// 自定义 API 域名（A6.10）。
  var apiHost: String = APIHost.default
  /// 自定义行情推送域名（WebSocket）。和 `apiHost` 分开，理由见 `APIHost.defaultStream`。
  var streamHost: String = APIHost.defaultStream
  var smartMarketRoute = true
  /// 行情线路：直连（默认）/ 网关。选了哪条就走哪条，代码不做自动切换。
  /// 存在这里而不是单独一个键，是为了跟着设置一起走：登录了随账号同步，
  /// 没登录就落在本机的访客档案里；`PrefsStore` 再把它镜像给 `MarketRoutePolicyStore`。
  var routePolicy: MarketRoutePolicy = .direct

  // ------------------------------------------------ 他在各页上摆出来的样子
  //
  // 这一节全是「用户用手改出来的习惯」，不属于四个设置面板，但和皮肤、副图高度
  // 完全是同一等级的东西。以前它们要么是纯 `@State`（切一次页签就没了），要么是
  // 裸 `@AppStorage`（跟着这台机器走：换个账号还在，换台设备又不在）。
  //
  // 判据只有一条：**这是他改出来的习惯，还是这个对象自己的属性。** 自选表按什么
  // 排、板块看今日还是 5 日、上次拿的哪把画线工具、回放几倍速，全是前者，所以
  // 一律搬进这里跟着人走——每一项都同时进了 `PersonalSyncCodec.fields`，
  // 一个都不在 `keepDeviceFields` 里（它们都不是「这台手机的属性」）。

  /// 自选表的排序口径：`custom`（自选顺序）/ `name` / `price` / `change` / `volume`。
  var favoritesSort: String = "custom"
  /// 排序方向。`custom` 那一档用不上它，但仍然记着——换回某个口径时接着上次的方向。
  var favoritesAscending: Bool = false
  /// 涨跌那一列看涨跌额还是涨跌幅。
  var favoritesAmount: Bool = false
  /// 行尾那条迷你走势线。默认不画，想看的人在「…」里自己打开。
  var favoritesSparkline: Bool = false
  /// 展开着行详情的那几个品种。
  var favoritesExpanded: Set<String> = []

  /// 板块页停在哪个市场（加密 / 美股）。
  var sectorMarket: SectorMarket = .crypto
  /// 板块页上**他点的那一档**窗口：今日 / 5 日。
  ///
  /// ⚠️ 只存他点的那一档。真正画出来的那一档是派生值——5 日数据没齐时页面就地退回
  /// 今日，而那一刻「今日 / 5 日」的切换条整条都不画。把那个降级结果回写到这儿，
  /// 等于在一个当时根本没有入口的页面上永久改掉了他的选择，数据齐了也回不来。
  var sectorWindow: SectorWindow = .today
  /// 板块里那张品种列表的排序口径（`SectorSymbolSort` 的 rawValue）。
  /// 存字符串不存枚举：那个枚举住在 app target 里，这一层（`KanpanSettings`）看不见它。
  var sectorSort: String = "change"

  /// 「绘图」面板上次停在哪个分类。空串 = 还没挑过，按出厂第一个分类开。
  /// 存回来的分类可能已经不在了（收藏清空「收藏」那一格就没了），
  /// 由 `DrawingToolPicker` 里既有的那条兜底接住。
  var drawToolGroup: String = ""
  /// 最近用过的那把画线工具（`Drawing.Kind` 的 rawValue），用来在工具面板上预选高亮。
  ///
  /// 它**不是**「此刻正举着笔」：换品种要把待画状态清掉（`ChartView+Drawing.setDrawings`
  /// 里那行 `d.tool = nil` 保持不动），冷启动更不许一进来就处于待画状态。
  /// 这儿记的只是「上次用的是哪把」这个习惯。
  var lastDrawTool: String = ""

  /// 回放倍速。**是人的习惯，不是这条记录的属性**——调到 4× 退出去，再进另一条记录
  /// 也该还是 4×。游标位置按记录存（`ReviewReplayPosition.cursor`），那个不跟着人走。
  var replaySpeed: Int = 1
  /// 「找相似」的搜索范围：`history`（市场历史）/ `private`（我的记录）。
  var reviewSearchScope: String = "history"

  init() {}

  /// 全新安装就是这一份（A6.4「首次安装即如此」）。
  static let defaults = Prefs()

  /// 最多同时开三个副图。再多主图就被挤没了——「主图和副图要同时落在一屏里」是
  /// 这张图的底线，所以这里卡死在三个，第四个进来就把最早开的那个换下去。
  static let maxSubs = 3
  /// 常用行最多几档（§10.6）。周期条右端从四颗药丸减到两颗之后腾出了位置，
  /// 上限跟着从 8 抬到 10——排不下的那几档会在右边淡出去，滑一下就到。
  static let maxQuick = 10

  /// 自选表认得的排序口径。存档里写着别的（降级回旧版本、手改存档）就退回 `custom`。
  static let favoriteSorts: Set<String> = ["custom", "name", "price", "change", "volume"]

  /// 「找相似」认得的两档范围。
  static let searchScopes: Set<String> = ["history", "private"]

  /// 展开着的自选行最多记多少个。这份名单跟着自选条数走，正常情况下远小于它；
  /// 上限只是别让手改过的存档把一份无限长的名单带进来。
  static let maxExpanded = 500

  /// 回放倍速只有 1 / 2 / 4 三档（`ReviewReplayControls` 上那颗按钮就是这么转的）。
  static func clampSpeed(_ value: Int) -> Int { [1, 2, 4].contains(value) ? value : 1 }

  /// 根间距存进档案之前夹一道。
  ///
  /// `ViewMath.reset` 里本来就夹了一次，但那是「画的时候不许越界」；这一道管的是
  /// 「不许把离谱的数写进存档」——真写进去了，下次冷启动第一帧就得靠画图那一道兜，
  /// 而存档里躺着一个永远兑现不了的数，看日志的人只会更糊涂。
  static func clampSpacing(_ value: Double) -> Double {
    guard value.isFinite else { return AICoinBehavior.initialSpacing }
    return min(AICoinBehavior.maximumSpacing, max(AICoinBehavior.minimumSpacing, value))
  }

  // ---------------------------------------------------------------- 取用

  /// 造型只剩 AICoin 一套（见 `CandleStyle`），所以这儿不再存 id，也没有 `styleID` 这个字段了。
  /// 旧存档里的 `styleID` 解码时直接忽略。
  var style: CandleStyle { .aicoin }

  /// 喂给图表的那一包开关。**主界面只调这一句**：各处自己拼容易漏项，
  /// 漏了的那一项会静悄悄退回引擎默认值，而不是报错，很难发现。
  var chartOptions: ChartOptions {
    var o = ChartOptions()
    o.kind = candleKind
    o.grid = gridChoice
    o.body = bodyChoice
    o.lastLine = lastLine
    o.drawings = showDrawings
    o.countdown = countdown          // 「本根倒计时」早就有了，这里接的是同一个字段
    o.sinceChange = sinceChange
    o.anchor = viewAnchor
    o.bias = priceBias
    o.dataDisplay = dataDisplay
    o.crossPrice = crossPrice
    o.allowMainInversion = allowMainInversion
    o.allowSubInversion = allowSubInversion
    o.adaptiveIndicators = adaptiveIndicators
    o.compactValues = compactValues
    o.portraitHeight = portraitHeight
    // 副图高度（`subHeights`）**不**走这里：它改的是分区怎么切，归 `Layout`，
    // 由主界面另行接线。放进来会变成两条路各说各话。
    return o
  }

  /// 这个指标现在用的参数。
  func params(for id: IndicatorID) -> [Int] {
    IndicatorParamRule.sanitize(params[id] ?? id.defaultParams, for: id)
  }

  /// 这个副图实际要多高（倍率，1.0 = 风格表原值）。
  ///
  /// 三档和拖拽只在用户**真的调过**的时候才算数；没调过的一律走同一个出厂倍率
  /// `defaultSubScale`，也就是三个副图**等高**。
  ///
  /// 以前这里给成交量满格、其余只给 0.62，理由是「成交量靠柱子的高度差读，压扁了
  /// 就剩一排小墩子」。真机量下来这条理由撑不住：4h 一屏里成交量拿到 105.7pt，
  /// OI 和 MACD 各只有 65.5pt——成交量比它们高出 61%，一排副图看着像没对齐的三段楼梯，
  /// 而矮下去的那两格恰恰是 MACD 这种要看线离零轴多远的图。AICoin 同屏是 89 / 90pt
  /// 的等高两格，读起来齐整得多。
  ///
  /// 等高不是把主图砍掉换来的：三格各 0.75 倍时主图仍是 316.6pt（原来 317.2pt），
  /// 副图各 79.1pt，主图只让出半个点。省高度要省在别处，不是让成交量一家独大。
  func scale(for id: IndicatorID) -> Double {
    if let manual = subHeightOverrides[id] { return manual }
    if let picked = subHeights[id] { return picked.scale }
    return Prefs.defaultSubScale
  }

  /// 副图的出厂高度倍率，三个副图共用一个数（等高）。
  ///
  /// 0.75 是照「主图不动」反推的：主图权重 3、三个副图各 w，
  /// 想让每格 ≈79pt 而主图留在 ≈317pt，解出来正好 w = 0.75。
  static let defaultSubScale: Double = 0.75

  /// 这个副图的高度档。用户没选过就是「中」——注意这只是档位的缺省，
  /// 实际高度看 `scale(for:)`（没选过的走 `defaultSubScale`，不是「中」的 1.0）。
  func height(for id: IndicatorID) -> SubPaneHeight { subHeights[id] ?? .medium }

  /// 某个指标是不是开着的。
  func isOn(_ id: IndicatorID) -> Bool {
    id.placement == .main ? overlays.contains(id) : subs.contains(id)
  }

  /// 当前这一套配色 + 深浅下的原始令牌。全 app 只有这一处把两根轴合起来。
  func seed(systemDark: Bool) -> PaletteSeed { theme.seed(skin: skin, systemDark: systemDark) }

  /// 当前深浅下的图表用色，涨跌已按 `redUp` 对调（A6.7 靠这一个入口，不会漏）。
  func chartColors(dark: Bool) -> ChartColors { Palette.chart(seed(systemDark: dark), redUp: redUp) }

  /// 涨色 / 跌色。胶囊、VOL 柱、MACD 柱都从这儿取，免得各处自己判 `redUp`。
  func upColor(dark: Bool) -> Hex { chartColors(dark: dark).up }
  func downColor(dark: Bool) -> Hex { chartColors(dark: dark).down }

  // ---------------------------------------------------------------- 改

  /// 开 / 关一个指标。
  ///
  /// 副图满三个时**不再拒绝**：拒绝等于让用户自己回去找一个关掉，白跑一趟。
  /// 改成把最早打开的那个换下去（`subs` 本来就是按打开先后排的，队首即最早），
  /// 再返回一句「换下了谁」——调用方拿它弹一条带「撤销」的 toast，后悔一下就能还原。
  @discardableResult
  mutating func toggle(_ id: IndicatorID) -> String? {
    switch id.placement {
    case .main:
      if let at = overlays.firstIndex(of: id) { overlays.remove(at: at) } else { overlays.append(id) }
      return nil
    case .sub:
      if let at = subs.firstIndex(of: id) { subs.remove(at: at); return nil }
      var evicted: IndicatorID?
      while subs.count >= Prefs.maxSubs, !subs.isEmpty { evicted = subs.removeFirst() }
      subs.append(id)
      guard let evicted else { return nil }
      return "副图最多三个 · 已换下 \(evicted.rawValue)"
    }
  }

  /// 改一个参数。非法值按 `IndicatorParamRule` 夹回来，不会写进存档。
  mutating func setParam(_ id: IndicatorID, at index: Int, to value: Int) {
    var v = params(for: id)
    guard v.indices.contains(index) else { return }
    v[index] = IndicatorParamRule.clamp(value)
    params[id] = v
  }

  /// 步进器的加减（原型 `bump`）。
  mutating func bumpParam(_ id: IndicatorID, at index: Int, by delta: Int) {
    let v = params(for: id)
    guard v.indices.contains(index) else { return }
    setParam(id, at: index, to: v[index] + delta)
  }

  /// 副图上下排序（§10.6 的拖柄）。
  mutating func moveSub(from source: Int, to destination: Int) {
    guard subs.indices.contains(source) else { return }
    let clamped = min(max(0, destination), subs.count - 1)
    guard clamped != source else { return }
    let id = subs.remove(at: source)
    subs.insert(id, at: clamped)
  }

  /// 长按常用行 / 更多面板里的增删（§10.6），最多 10 个，至少留 1 个。
  @discardableResult
  mutating func toggleQuick(_ iv: Interval) -> String? {
    if let at = quickIntervals.firstIndex(of: iv) {
      guard quickIntervals.count > 1 else { return "常用行至少留一档" }
      quickIntervals.remove(at: at)
      return nil
    }
    guard quickIntervals.count < Prefs.maxQuick else { return "常用行最多 \(Prefs.maxQuick) 档" }
    quickIntervals.append(iv)
    quickIntervals.sort { a, b in
      (Interval.allCases.firstIndex(of: a) ?? 0) < (Interval.allCases.firstIndex(of: b) ?? 0)
    }
    return nil
  }

  /// 改 API 域名。形状不对就不写，返回那句提示。
  @discardableResult
  mutating func setAPIHost(_ raw: String) -> String? {
    let host = APIHost.normalize(raw)
    if let why = APIHost.reject(host) { return why }
    apiHost = host
    return nil
  }

  /// 改行情推送域名。规则和 `setAPIHost` 一样。
  @discardableResult
  mutating func setStreamHost(_ raw: String) -> String? {
    let host = APIHost.normalize(raw)
    if let why = APIHost.reject(host) { return why }
    streamHost = host
    return nil
  }
}
