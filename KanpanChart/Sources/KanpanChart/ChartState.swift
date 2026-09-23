import Foundation
import KanpanCore

/// 画一帧需要的全部输入。
///
/// 纯值类型：给它同样的 state，任何时候画出来都是同一张图——快照测试（A3.11）
/// 靠的就是这条。滚动、缩放这些只改 `view`，不碰别的。
public struct ChartState: Sendable {
  public var series: BarSeries
  public var compare: [CompareSeries] = []
  public var percentAxis = false
  public var oi: OISeries?
  public var external: [IndicatorID: ExternalSeries] = [:]
  public var depth: OrderBook?
  public var indicatorInputs: [IndicatorID: ExternalSeries] {
    var inputs = external
    if let oi { inputs[.oi] = ExternalSeries(oi: oi) }
    return inputs
  }
  public var symbol: SymbolInfo
  public var view: ViewWindow
  public var style: CandleStyle
  public var paletteSeed: PaletteSeed?
  public var dark: Bool
  public var redUp: Bool
  public var price: PriceTransform
  /// 主图叠加：MA / EMA / BOLL。
  public var overlays: [IndicatorID]
  /// 副图，从上到下。
  public var subs: [IndicatorID]
  /// 指标参数覆盖；没给的走 `IndicatorID.defaultParams`。
  public var params: [IndicatorID: [Int]]
  public var timezone: TZChoice
  public var indicatorColors: [IndicatorID: [Int: Hex]] = [:]
  public var drawingPreviewID: String? = nil
  public var drawings: [Drawing]
  /// 十字线摆在哪根上；`nil` 就不画。
  public var crosshair: Crosshair?
  /// 十字线磁吸（原型 `chart.magnet`，默认开）。开着竖线吸到根中心、横线吸到最近的
  /// 开高低收；关掉就停在手指上。
  public var magnet: Bool
  /// 价格小数位来自 `SymbolInfo.priceDecimals`，按最小报价步长展示。
  public var decimals: Int
  /// K 线设置的那组开关（网格 / 实体 / 平均 K 线 / 实时价格线 / 画线 / 倒计时 / 至今涨幅 /
  /// 留白偏置 / 拖动位置）。全默认 = 现状。
  public var options: ChartOptions
  /// 「本根还有多久收」用的当前时刻（毫秒）。`nil` 就不画倒计时。
  ///
  /// 为什么不在渲染器里读系统时钟：`ChartState` 必须保持纯值——同一份 state 任何时候
  /// 画出来都得是同一张图，取证渲染（`make evidence`）和渲染单测全靠这条。时间是外部输入，得喂进来。
  public var nowMs: Double?
  /// 每个副图各自的高度倍率（A6.4 小/中/大）。空字典 = 全 1.0 = 现状。
  ///
  /// 放这儿而不是塞进 `options`：它是「指标面板」那边的设置，不是「K 线设置」里的项，
  /// 而且它和 `subs` 是一对（同一批指标的两个侧面），挨着放读起来才顺。
  public var axisScaleAnchor: Double?
  public var hiddenOutputs: [IndicatorID: Set<Int>] = [:]
  public var subInverted: Set<IndicatorID> = []
  public var rsiUpper = 70.0
  public var rsiLower = 30.0
  public var subScale: [IndicatorID: Double]
  /// 当前行情线路给不给得出持仓量。`OISource` 只认币安；走 OKX 兜底线路时这条数据
  /// 根本不会来，副图要是还挂着「持仓量加载中」，等多久都等不到，用户只会以为卡住了。
  public var oiSupported = true
  /// 当前行情线路给不给得出多空比、主动买卖、基差这几样衍生统计。和持仓量分开：
  /// 网关线路上的替身有持仓量历史，这几样没有。
  public var externalSupported = true

  public init(
    series: BarSeries,
    symbol: SymbolInfo,
    view: ViewWindow,
    style: CandleStyle = .default,
    dark: Bool = false,
    redUp: Bool = false,
    price: PriceTransform = .init(mode: .log),
    overlays: [IndicatorID] = [.ma],
    subs: [IndicatorID] = AICoinBehavior.subpanels,
    params: [IndicatorID: [Int]] = [.ma: AICoinBehavior.maPeriods, .vol: AICoinBehavior.volumePeriods, .macd: AICoinBehavior.macdPeriods],
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
    self.series = series; self.symbol = symbol; self.view = view
    self.style = style; self.dark = dark; self.redUp = redUp; self.price = price
    self.overlays = overlays; self.subs = subs; self.params = params
    self.timezone = timezone; self.oi = oi; self.drawings = drawings
    self.crosshair = crosshair
    self.magnet = magnet
    self.decimals = decimals ?? symbol.priceDecimals
    self.options = options
    self.nowMs = nowMs
    self.subScale = subScale
  }

  public var colors: ChartColors { Palette.chart(paletteSeed ?? (dark ? Palette.darkSeed : Palette.lightSeed), redUp: redUp) }

  /// 真正生效的网格档位。渲染器和探针一律读这个，别再读 `style.grid`——
  /// 覆盖只在读的时候叠，风格表本身一个数都不许改（原型即规格）。
  public var effectiveGrid: CandleStyle.Grid {
    switch options.grid {
    case .style: .none
    case .on: .both
    case .off: .none
    }
  }

  /// 真正生效的实体画法。风格表只剩 AICoin 一套之后，这里就是「图表」面板上那两档的直译；
  /// 渲染器一律读这个，别去读 `style.shape`。
  public var effectiveShape: CandleStyle.Shape {
    switch options.body {
    case .solid: .solid
    case .hollowUp: .hollowUp
    }
  }
}

extension ChartState {
  /// 两份 state 算出来的**几何**是不是同一套。
  ///
  /// 这里列的是 `ChartRenderer` 的 `GeometryCache` 真正依赖的那些输入：布局、价格区间、
  /// 图例内缩、叠加线、隐藏输出掩码，没有一个读得到 `crosshair` 或 `nowMs`——
  /// 十字线摆在哪根上、倒计时走到哪一秒，都不会让轴宽变一个像素。所以这两项单独摘出去，
  /// 它们一变就作废整只缓存是纯亏：手指跟手时每一帧都得把布局和价格区间重算一遍。
  ///
  /// 反过来，凡是**会**改几何的东西一律留在下面逐项比——漏一项就会拿上一份 state 的
  /// 几何去画新 state，那是画错，不是慢。所以这里不用「白名单式的近似」，
  /// 而是把 `ChartState` 的字段一个不落地列全（新增字段时也必须加进来）。
  func sameGeometryInputs(as other: ChartState) -> Bool {
    series == other.series && oi == other.oi && external == other.external && symbol == other.symbol && view == other.view
      && style == other.style && paletteSeed == other.paletteSeed && dark == other.dark
      && redUp == other.redUp && price == other.price && overlays == other.overlays
      && subs == other.subs && params == other.params && timezone == other.timezone
      && indicatorColors == other.indicatorColors && drawingPreviewID == other.drawingPreviewID
      && drawings == other.drawings && magnet == other.magnet && decimals == other.decimals
      && options == other.options && axisScaleAnchor == other.axisScaleAnchor
      && hiddenOutputs == other.hiddenOutputs && subInverted == other.subInverted
      && rsiUpper == other.rsiUpper && rsiLower == other.rsiLower && subScale == other.subScale
      && oiSupported == other.oiSupported && externalSupported == other.externalSupported && compare == other.compare && percentAxis == other.percentAxis
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
