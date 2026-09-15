import Foundation
import KanpanCore

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
  /// 周期条第一行的常用档（原型 `QUICK`）。§10.6：长按可增删，最多 8 个。
  var quickIntervals: [Interval] = Interval.quick

  // ---------------------------------------------------------------- 外观
  /// 跟随系统 / 浅 / 深（A6.3）。
  var theme: ThemeChoice = .system
  // Keep the manual choice intact; automatic brightness selection is runtime-only.
  var ambientTheme = false
  /// 涨跌对调（A6.7）。`false` = 绿涨红跌（原型默认）。
  var redUp: Bool = false

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

  init() {}

  /// 全新安装就是这一份（A6.4「首次安装即如此」）。
  static let defaults = Prefs()

  /// 最多同时打开七个副图，屏下内容通过页面纵向滚动可达。
  static let maxSubs = 7
  /// 常用行最多几档（§10.6）。
  static let maxQuick = 8

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
  /// 三档和拖拽只在用户**真的调过**的时候才算数；没调过的走各自的出厂倍率：
  /// 成交量维持满格，其余副图开出来只有 `otherSubScale` 那一档。为什么区别对待——
  /// 成交量是靠柱子之间的**高度差**读的，压扁了就剩一排看不出长短的小墩子；
  /// MACD / OI / KDJ 这类读的是线的方向和零轴上下，矮一截照样读得出来。
  /// 省下来的高度全给主图：一屏里真正要看的是 K 线，副图是陪看的。
  func scale(for id: IndicatorID) -> Double {
    if let manual = subHeightOverrides[id] { return manual }
    if let picked = subHeights[id] { return picked.scale }
    return id == .vol ? 1 : Prefs.otherSubScale
  }

  /// 成交量以外的副图的出厂高度倍率。
  static let otherSubScale: Double = 0.62

  /// 这个副图的高度档。用户没选过就是「中」——注意这只是档位的缺省，
  /// 实际高度看 `scale(for:)`（那儿对成交量以外的副图另有出厂倍率）。
  func height(for id: IndicatorID) -> SubPaneHeight { subHeights[id] ?? .medium }

  /// 某个指标是不是开着的。
  func isOn(_ id: IndicatorID) -> Bool {
    id.placement == .main ? overlays.contains(id) : subs.contains(id)
  }

  /// 当前深浅下的图表用色，涨跌已按 `redUp` 对调（A6.7 靠这一个入口，不会漏）。
  func chartColors(dark: Bool) -> ChartColors { Palette.chart(theme.seed(systemDark: dark), redUp: redUp) }

  /// 涨色 / 跌色。胶囊、VOL 柱、MACD 柱都从这儿取，免得各处自己判 `redUp`。
  func upColor(dark: Bool) -> Hex { chartColors(dark: dark).up }
  func downColor(dark: Bool) -> Hex { chartColors(dark: dark).down }

  // ---------------------------------------------------------------- 改

  /// 开 / 关一个指标。副图满三个时不动，返回一句提示（原型的 toast）。
  @discardableResult
  mutating func toggle(_ id: IndicatorID) -> String? {
    switch id.placement {
    case .main:
      if let at = overlays.firstIndex(of: id) { overlays.remove(at: at) } else { overlays.append(id) }
      return nil
    case .sub:
      if let at = subs.firstIndex(of: id) { subs.remove(at: at); return nil }
      guard subs.count < Prefs.maxSubs else { return "副图最多同时开七个" }
      subs.append(id)
      return nil
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

  /// 长按常用行 / 更多面板里的增删（§10.6），最多 8 个，至少留 1 个。
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
