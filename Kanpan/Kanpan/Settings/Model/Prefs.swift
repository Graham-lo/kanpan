import Foundation
import KanpanCore

/// 一份完整的设置（任务书 §3.2 的 `AppState` 里可持久化的那一半）。
///
/// 纯值类型、`Sendable`，读的人拿到的是快照，不会被别的线程改到。
/// **默认值一律以原型为准**：风格「墩」、周期 1h、主图 MA、副图 MACD + RSI、
/// 价格轴常规、磁吸开、时区本地、绿涨红跌、外观跟随系统（原型 `chart.js` 358–369 行
/// 与 `app.js` 的 `S` 初始化）。
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
  /// 十一款形态之一，存 `CandleStyle.id`。默认「墩」。
  var styleID: String = CandleStyle.default.id
  /// 涨跌对调（A6.7）。`false` = 绿涨红跌（原型默认）。
  var redUp: Bool = false

  // ---------------------------------------------------------------- 图
  /// 价格轴 常规 / 对数 / 百分比（A6.8）。
  var priceMode: PriceMode = .linear
  /// 十字线磁吸（§7 长按那一行）。原型 `chart.magnet = true`。
  var magnet: Bool = true
  /// 本根倒计时（§10.4，默认开）。
  var countdown: Bool = true
  /// 盯盘时不锁屏（§10.4，默认开）。
  var keepAwake: Bool = true
  /// 启动快照（§4.3「设置里『启动快照』开关，默认开」）。
  var launchSnapshot: Bool = true
  /// 时区（A6.9）。Core 的 `TZChoice` 已经是原型的口径：本地 / UTC / 交易所。
  var timeZone: TZChoice = .local

  // ---------------------------------------------------------------- 指标
  /// 主图叠加，按打开先后排。默认 `[.ma]`。
  var overlays: [IndicatorID] = IndicatorID.defaultOverlays
  /// 副图，从上往下就是这个顺序。默认 `[.macd, .rsi]`。
  var subs: [IndicatorID] = IndicatorID.defaultSubs
  /// 每个指标的参数。没记的取 `IndicatorID.defaultParams`。
  var params: [IndicatorID: [Int]] = [:]
  /// 每个副图的高度档（A6.4）。没记的是「中」。
  var subHeights: [IndicatorID: SubPaneHeight] = [:]

  // ---------------------------------------------------------------- 网络
  /// 自定义 API 域名（A6.10）。
  var apiHost: String = APIHost.default
  /// 自定义行情推送域名（WebSocket）。和 `apiHost` 分开，理由见 `APIHost.defaultStream`。
  var streamHost: String = APIHost.defaultStream

  init() {}

  /// 全新安装就是这一份（A6.4「首次安装即如此」）。
  static let defaults = Prefs()

  /// 副图最多同时开几个。原型 `renderIndicators`：第四个按不下去，弹「副图最多同时开三个」。
  static let maxSubs = 3
  /// 常用行最多几档（§10.6）。
  static let maxQuick = 8

  // ---------------------------------------------------------------- 取用

  var style: CandleStyle { CandleStyle.style(id: styleID) }

  /// 这个指标现在用的参数。
  func params(for id: IndicatorID) -> [Int] {
    IndicatorParamRule.sanitize(params[id] ?? id.defaultParams, for: id)
  }

  /// 这个副图的高度档。
  func height(for id: IndicatorID) -> SubPaneHeight { subHeights[id] ?? .medium }

  /// 某个指标是不是开着的。
  func isOn(_ id: IndicatorID) -> Bool {
    id.placement == .main ? overlays.contains(id) : subs.contains(id)
  }

  /// 当前深浅下的图表用色，涨跌已按 `redUp` 对调（A6.7 靠这一个入口，不会漏）。
  func chartColors(dark: Bool) -> ChartColors { Palette.chart(dark: dark, redUp: redUp) }

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
      guard subs.count < Prefs.maxSubs else { return "副图最多同时开三个" }
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
