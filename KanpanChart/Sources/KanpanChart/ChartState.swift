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
    decimals: Int? = nil
  ) {
    self.series = series; self.symbol = symbol; self.view = view
    self.style = style; self.dark = dark; self.redUp = redUp; self.price = price
    self.overlays = overlays; self.subs = subs; self.params = params
    self.timezone = timezone; self.oi = oi; self.drawings = drawings
    self.crosshair = crosshair
    self.decimals = decimals ?? symbol.pricePrecision
  }

  public var colors: ChartColors { Palette.chart(dark: dark, redUp: redUp) }
}

/// 十字线落在哪儿。静态摆放时（M3）只需要根的下标；跟手那套是 M4 的事。
public struct Crosshair: Sendable, Equatable {
  public var index: Int
  /// 竖线用根中心，横线用这个 y；`nil` 表示用这根的收盘。
  public var y: Double?
  public init(index: Int, y: Double? = nil) { self.index = index; self.y = y }
}
