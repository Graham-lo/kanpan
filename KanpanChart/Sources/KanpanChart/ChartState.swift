import Foundation
import KanpanCore

/// 画一帧需要的全部输入，分三层（审查 23）。
///
/// 纯值类型：给它同样的 state，任何时候画出来都是同一张图——快照测试（A3.11）
/// 靠的就是这条。
///
/// ```
/// input     K 线、指标、皮肤、品种、样式开关      来一笔 tick / 换品种 / 改设置
/// viewport  视野、价格轴、分隔线                 拖、捏、甩、拉价格轴、拖分隔线
/// overlay   画线、十字线、订单流、盘口、倒计时    手指跟手、每秒一格
/// ```
///
/// 分层是为了让「谁变了」能按层回答：宿主和 `ChartView` 只看变了的那一层，
/// 拖图（只动 `viewport`）不会让叠加层、指标缓存、无障碍把手跟着重来一遍；
/// 从前这件事靠 `sameFrame` / `sameGeometryInputs` 两张手写的逐字段清单，
/// 新增字段漏写一处就是画错。现在每层是一个 `Equatable`，编译器替我们把字段列全。
///
/// 旧的平铺字段名（`state.view`、`state.drawings`……）全部保留成转发属性，
/// 调用方一行都不用改；`_modify` 让 `state.series.append(...)` 这类原地改仍是原地改。
///
/// `compare`（比价序列）和 `percentAxis` 放在 `input`：比价模式下它们决定价格区间，
/// 属于数据，不是叠加。
public struct ChartState: Sendable, Equatable {
  /// 数据与样式：画什么、用什么颜色画。
  public struct Input: Sendable, Equatable {
    public var series: BarSeries
    public var compare: [CompareSeries] = []
    public var percentAxis: Bool = false
    public var oi: OISeries? = nil
    public var external: [IndicatorID: ExternalSeries] = [:]
    public var symbol: SymbolInfo
    public var paletteSeed: PaletteSeed? = nil
    public var dark: Bool
    public var redUp: Bool
    /// 主图叠加：MA / EMA / BOLL。
    public var overlays: [IndicatorID]
    /// 副图，从上到下。
    public var subs: [IndicatorID]
    /// 指标参数覆盖；没给的走 `IndicatorID.defaultParams`。
    public var params: [IndicatorID: [Int]]
    public var timezone: TZChoice
    public var indicatorColors: [IndicatorID: [Int: Hex]] = [:]
    /// 价格小数位来自 `SymbolInfo.priceDecimals`，按最小报价步长展示。
    public var decimals: Int
    /// K 线设置的那组开关（网格 / 实体 / 平均 K 线 / 实时价格线 / 画线 / 倒计时 / 至今涨幅 /
    /// 留白偏置 / 拖动位置）。全默认 = 现状。
    public var options: ChartOptions
    public var hiddenOutputs: [IndicatorID: Set<Int>] = [:]
    public var subInverted: Set<IndicatorID> = []
    public var rsiUpper: Double = 70.0
    public var rsiLower: Double = 30.0
    /// 当前行情线路给不给得出持仓量。`OISource` 只认币安；走 OKX 兜底线路时这条数据
    /// 根本不会来，副图要是还挂着「持仓量加载中」，等多久都等不到，用户只会以为卡住了。
    public var oiSupported: Bool = true
    /// 当前行情线路给不给得出多空比、主动买卖、基差这几样衍生统计。和持仓量分开：
    /// 网关线路上的替身有持仓量历史，这几样没有。
    public var externalSupported: Bool = true
  }

  /// 看哪一段、多大：手势只改这一层。
  public struct Viewport: Sendable, Equatable {
    /// 时间轴视野：拖动、捏合、甩出去的惯性只改它。
    public var view: ViewWindow
    /// 价格轴：对数 / 线性 / 百分比，以及价格轴上拉出来的倍率与翻转。
    public var price: PriceTransform
    /// 手动拉价格轴时钉住的那个价位（`nil` = 自动）。
    public var axisScaleAnchor: Double? = nil
    /// 每个副图各自的高度倍率（A6.4 小/中/大）。空字典 = 全 1.0 = 现状。拖分隔线只改它。
    public var subScale: [IndicatorID: Double]
  }

  /// 盖在几何上面的东西：它们一个都不改布局、价格区间与指标。
  public struct Overlay: Sendable, Equatable {
    /// 这只品种的画线。**不是真值**：真值在 `DrawingBook`，这里是图从它投影过来的一份。
    public var drawings: [Drawing]
    public var drawingPreviewID: String? = nil
    /// 十字线摆在哪根上；`nil` 就不画。
    public var crosshair: Crosshair? = nil
    /// 十字线磁吸（原型 `chart.magnet`，默认开）。开着竖线吸到根中心、横线吸到最近的
    /// 开高低收；关掉就停在手指上。
    public var magnet: Bool
    /// 主力订单流的当前大单集合（ChartRenderer+OrderFlow）。`nil` = 开关关着或横屏画线台；永不落盘。
    public var orderFlow: OrderFlowSnapshot? = nil
    /// 主力订单流的显示开关（现货 / 合约 / 已成交买卖 / 已撤销买卖）。只管画不画，跟人走。
    public var orderFlowDisplay: OrderFlowDisplay = .all
    /// 轻点选中的那一条合并带（详情卡、描边）：存「桶 × 侧 × 类」，画和出卡时到最新快照里现合一份
    /// （金额、状态会变）；快照里这一桶没单了就等于没选中。换品种、换周期清掉；永不落盘。
    public var orderFlowSelected: OrderFlowGroupKey? = nil
    public var depth: OrderBook? = nil
    /// 「本根还有多久收」用的当前时刻（毫秒）。`nil` 就不画倒计时。
    ///
    /// 为什么不在渲染器里读系统时钟：`ChartState` 必须保持纯值——同一份 state 任何时候
    /// 画出来都得是同一张图，取证渲染（`make evidence`）和渲染单测全靠这条。时间是外部输入，得喂进来。
    public var nowMs: Double? = nil
  }

  public var input: Input
  public var viewport: Viewport
  public var overlay: Overlay

  // ---------------------------------------------------------------- 平铺字段名（转发）

  public var series: BarSeries {
    get { input.series }
    _modify { yield &input.series }
  }
  public var compare: [CompareSeries] {
    get { input.compare }
    _modify { yield &input.compare }
  }
  public var percentAxis: Bool {
    get { input.percentAxis }
    _modify { yield &input.percentAxis }
  }
  public var oi: OISeries? {
    get { input.oi }
    _modify { yield &input.oi }
  }
  public var external: [IndicatorID: ExternalSeries] {
    get { input.external }
    _modify { yield &input.external }
  }
  public var symbol: SymbolInfo {
    get { input.symbol }
    _modify { yield &input.symbol }
  }
  public var paletteSeed: PaletteSeed? {
    get { input.paletteSeed }
    _modify { yield &input.paletteSeed }
  }
  public var dark: Bool {
    get { input.dark }
    _modify { yield &input.dark }
  }
  public var redUp: Bool {
    get { input.redUp }
    _modify { yield &input.redUp }
  }
  public var overlays: [IndicatorID] {
    get { input.overlays }
    _modify { yield &input.overlays }
  }
  public var subs: [IndicatorID] {
    get { input.subs }
    _modify { yield &input.subs }
  }
  public var params: [IndicatorID: [Int]] {
    get { input.params }
    _modify { yield &input.params }
  }
  public var timezone: TZChoice {
    get { input.timezone }
    _modify { yield &input.timezone }
  }
  public var indicatorColors: [IndicatorID: [Int: Hex]] {
    get { input.indicatorColors }
    _modify { yield &input.indicatorColors }
  }
  public var decimals: Int {
    get { input.decimals }
    _modify { yield &input.decimals }
  }
  public var options: ChartOptions {
    get { input.options }
    _modify { yield &input.options }
  }
  public var hiddenOutputs: [IndicatorID: Set<Int>] {
    get { input.hiddenOutputs }
    _modify { yield &input.hiddenOutputs }
  }
  public var subInverted: Set<IndicatorID> {
    get { input.subInverted }
    _modify { yield &input.subInverted }
  }
  public var rsiUpper: Double {
    get { input.rsiUpper }
    _modify { yield &input.rsiUpper }
  }
  public var rsiLower: Double {
    get { input.rsiLower }
    _modify { yield &input.rsiLower }
  }
  public var oiSupported: Bool {
    get { input.oiSupported }
    _modify { yield &input.oiSupported }
  }
  public var externalSupported: Bool {
    get { input.externalSupported }
    _modify { yield &input.externalSupported }
  }
  public var view: ViewWindow {
    get { viewport.view }
    _modify { yield &viewport.view }
  }
  public var price: PriceTransform {
    get { viewport.price }
    _modify { yield &viewport.price }
  }
  public var axisScaleAnchor: Double? {
    get { viewport.axisScaleAnchor }
    _modify { yield &viewport.axisScaleAnchor }
  }
  public var subScale: [IndicatorID: Double] {
    get { viewport.subScale }
    _modify { yield &viewport.subScale }
  }
  public var drawings: [Drawing] {
    get { overlay.drawings }
    _modify { yield &overlay.drawings }
  }
  public var drawingPreviewID: String? {
    get { overlay.drawingPreviewID }
    _modify { yield &overlay.drawingPreviewID }
  }
  public var crosshair: Crosshair? {
    get { overlay.crosshair }
    _modify { yield &overlay.crosshair }
  }
  public var magnet: Bool {
    get { overlay.magnet }
    _modify { yield &overlay.magnet }
  }
  public var orderFlow: OrderFlowSnapshot? {
    get { overlay.orderFlow }
    _modify { yield &overlay.orderFlow }
  }
  public var orderFlowDisplay: OrderFlowDisplay {
    get { overlay.orderFlowDisplay }
    _modify { yield &overlay.orderFlowDisplay }
  }
  public var orderFlowSelected: OrderFlowGroupKey? {
    get { overlay.orderFlowSelected }
    _modify { yield &overlay.orderFlowSelected }
  }
  public var depth: OrderBook? {
    get { overlay.depth }
    _modify { yield &overlay.depth }
  }
  public var nowMs: Double? {
    get { overlay.nowMs }
    _modify { yield &overlay.nowMs }
  }

  public var indicatorInputs: [IndicatorID: ExternalSeries] {
    var inputs = external
    if let oi { inputs[.oi] = ExternalSeries(oi: oi) }
    return inputs
  }

  public init(
    series: BarSeries,
    symbol: SymbolInfo,
    view: ViewWindow,
    dark: Bool = false,
    redUp: Bool = false,
    price: PriceTransform = .init(mode: .log),
    overlays: [IndicatorID] = [.ma],
    subs: [IndicatorID] = AICoinBehavior.subpanels,
    params: [IndicatorID: [Int]] = IndicatorID.factoryParams,
    timezone: TZChoice = .local,
    oi: OISeries? = nil,
    drawings: [Drawing] = [],
    crosshair: Crosshair? = nil,
    magnet: Bool = false,
    decimals: Int? = nil,
    options: ChartOptions = .init(),
    nowMs: Double? = nil,
    subScale: [IndicatorID: Double] = [:]
  ) {
    input = Input(
      series: series, oi: oi, symbol: symbol, dark: dark, redUp: redUp,
      overlays: overlays, subs: subs, params: params, timezone: timezone,
      decimals: decimals ?? symbol.priceDecimals, options: options)
    viewport = Viewport(view: view, price: price, subScale: subScale)
    overlay = Overlay(drawings: drawings, crosshair: crosshair, magnet: magnet, nowMs: nowMs)
  }

  public var colors: ChartColors { Palette.chart(paletteSeed ?? (dark ? Palette.darkSeed : Palette.lightSeed), redUp: redUp) }

  /// 真正生效的网格档位。渲染器和探针一律读这个。
  public var effectiveGrid: CandleStyle.Grid {
    switch options.grid {
    case .style: .none
    case .on: .both
    case .off: .none
    }
  }

  /// 真正生效的实体画法：「图表」面板上那两档的直译。渲染器一律读这个。
  public var effectiveShape: CandleStyle.Shape {
    switch options.body {
    case .solid: .solid
    case .hollowUp: .hollowUp
    }
  }
}

extension ChartState {
  /// 三层里哪几层变了。
  public struct Layers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let input = Layers(rawValue: 1 << 0)
    public static let viewport = Layers(rawValue: 1 << 1)
    public static let overlay = Layers(rawValue: 1 << 2)
    public static let all: Layers = [.input, .viewport, .overlay]
  }

  /// 相对 `old` 变了哪几层；`old == nil` 算全变。
  public func changedLayers(from old: ChartState?) -> Layers {
    guard let old else { return .all }
    var out: Layers = []
    if old.input != input { out.insert(.input) }
    if old.viewport != viewport { out.insert(.viewport) }
    if old.overlay != overlay { out.insert(.overlay) }
    return out
  }
}

extension ChartState.Input {
  /// 除了末根，其余一样吗——也就是「这次只是来了一笔 tick」（改末根，或者新开一根）。
  ///
  /// 从前这是一张手写的逐字段清单（`ChartView.sameFrame`），新增字段漏写一处就会把
  /// 风格变化当成 tick、只重画一半。现在借 `Equatable`：把对方的 K 线换进来再整体比，
  /// K 线本身另按 `samePrefix` 比前缀。数组是写时复制，换进来只是多一次引用计数。
  public func sameExceptLastBar(as other: ChartState.Input) -> Bool {
    var probe = self
    probe.series = other.series
    return probe == other && series.samePrefix(as: other.series)
  }
}

/// 十字线落在哪儿。
///
/// 存的是**时间和价格**，不是像素：转屏、改副图高度、补历史都会换一套坐标，存像素的话
/// 线会自己跳走。`index` 是磁吸模式下吸到的那根，读数（图例、时间胶囊）一律读它。
public struct Crosshair: Sendable, Equatable {
  public var index: Int
  public var pane: IndicatorID?
  /// 关掉磁吸时竖线停在这个时间上；`nil` 用第 `index` 根的中心。
  public var t: Double?
  /// 横线的价格；`nil` 表示用这根的收盘。
  ///
  /// 注意存的是价格不是 y：`y` 这个名字留着是因为 M3 的基线用它摆位置，语义没变过——
  /// 当时给的就是「这一层画到哪个高度」，现在统一成价格由渲染器换算。
  public var price: Double?
  public init(index: Int, t: Double? = nil, price: Double? = nil, pane: IndicatorID? = nil) {
    self.index = index; self.t = t; self.price = price; self.pane = pane
  }
}
