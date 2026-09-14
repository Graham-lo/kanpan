import Foundation
import KanpanCore

/// 画一帧需要的全部输入。
///
/// 纯值类型：给它同样的 state，任何时候画出来都是同一张图——快照测试（A3.11）
/// 靠的就是这条。滚动、缩放这些只改 `view`，不碰别的。
public struct ChartState: Sendable {
  public var series: BarSeries
  public var oi: OISeries?
  public var symbol: SymbolInfo
  public var view: ViewWindow
  public var style: CandleStyle
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
  public var drawings: [Drawing]
  /// 十字线摆在哪根上；`nil` 就不画。
  public var crosshair: Crosshair?
  /// 十字线磁吸（原型 `chart.magnet`，默认开）。开着竖线吸到根中心、横线吸到最近的
  /// 开高低收；关掉就停在手指上。
  public var magnet: Bool
  /// 价格小数位。原型是快照里的 `meta.p`（BTCUSDT 是 2），等于 `exchangeInfo`
  /// 的 `pricePrecision`——不是按 `tickSize` 推的 `priceDecimals`。
  public var decimals: Int

  public init(
    series: BarSeries,
    symbol: SymbolInfo,
    view: ViewWindow,
    style: CandleStyle = .default,
    dark: Bool = false,
    redUp: Bool = false,
    price: PriceTransform = .init(),
    overlays: [IndicatorID] = [.ma],
    subs: [IndicatorID] = [.macd, .rsi],
    params: [IndicatorID: [Int]] = [:],
    timezone: TZChoice = .local,
    oi: OISeries? = nil,
    drawings: [Drawing] = [],
    crosshair: Crosshair? = nil,
    magnet: Bool = true,
    decimals: Int? = nil
  ) {
    self.series = series; self.symbol = symbol; self.view = view
    self.style = style; self.dark = dark; self.redUp = redUp; self.price = price
    self.overlays = overlays; self.subs = subs; self.params = params
    self.timezone = timezone; self.oi = oi; self.drawings = drawings
    self.crosshair = crosshair
    self.magnet = magnet
    self.decimals = decimals ?? symbol.pricePrecision
  }

  public var colors: ChartColors { Palette.chart(dark: dark, redUp: redUp) }
}

/// 十字线落在哪儿。
///
/// 存的是**时间和价格**，不是像素：转屏、改副图高度、补历史都会换一套坐标，存像素的话
/// 线会自己跳走。`index` 是磁吸模式下吸到的那根，读数（图例、时间胶囊）一律读它。
public struct Crosshair: Sendable, Equatable {
  public var index: Int
  /// 关掉磁吸时竖线停在这个时间上；`nil` 用第 `index` 根的中心。
  public var t: Double?
  /// 横线的价格；`nil` 表示用这根的收盘。
  ///
  /// 注意存的是价格不是 y：`y` 这个名字留着是因为 M3 的基线用它摆位置，语义没变过——
  /// 当时给的就是「这一层画到哪个高度」，现在统一成价格由渲染器换算。
  public var price: Double?
  public init(index: Int, t: Double? = nil, price: Double? = nil) {
    self.index = index; self.t = t; self.price = price
  }
}
