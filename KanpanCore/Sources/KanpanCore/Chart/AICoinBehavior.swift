import Foundation

/// All skins share this chart contract. Android constants are initial references;
/// current iPhone settings and remaining calibration are recorded in docs/AICoin-K线复刻规格.md.
public enum AICoinBehavior {
  public static let initialSpacing = 4.0
  public static let minimumSpacing = 1.6
  public static let maximumSpacing = 40.0
  public static let axisWidth = 50.0
  public static let timeHeight = 17.0
  /// iPhone原版进入行情末列贴绘图区右缘；2026-09-15镜像实测。
  public static let rightInset = 0.0
  public static let mainTopInset = 40.0
  public static let mainBottomInset = 8.0
  public static let maPeriods = [10, 30, 120, 256]
  public static let volumePeriods = [5, 10, 30, 60, 120]
  public static let macdPeriods = [10, 30, 9]
  public static let subpanels: [IndicatorID] = [.vol, .oi, .macd]

  public enum NarrowRendering { case closeLine, highLow, candle }
  /// Thresholds from Android physical pixels; scale=3 is the current reference phone.
  public static func rendering(spacing: Double, scale: Double) -> NarrowRendering {
    let px = spacing * scale
    return px < 5 ? .closeLine : px < 7 ? .highLow : .candle
  }

  public static func axisZoom(from start: Double, dy: Double, height: Double) -> Double {
    let value = min(16, max(0.03, start * pow(2, -dy / max(height / 4, 1))))
    return abs(value - 1) <= 0.02 ? 1 : value
  }

  /// A changing data tail follows only while the viewer is still looking at the tail.
  /// A stale launch snapshot may end days before the REST response.
  public static func reconcile(_ view: ViewWindow, from old: BarSeries,
                               to new: BarSeries, plotW: Double, anchor: ViewAnchor = .right) -> ViewWindow {
    guard !old.isEmpty, !new.isEmpty, old.symbol == new.symbol,
          old.interval == new.interval else { return view }
    let spacing = view.barSpacing(step: old.step, plotW: plotW)
    let latest = ViewMath.reset(series: old, plotW: plotW, spacing: spacing, anchor: anchor)
    guard abs(view.to - latest.to) / view.span * plotW < spacing,
          new.lastTime > old.lastTime else { return view }
    return ViewWindow(to: view.to + Double(new.lastTime - old.lastTime), span: view.span)
  }
}
