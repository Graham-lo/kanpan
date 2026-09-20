import Foundation

/// All skins share this chart contract. Android constants are initial references;
/// current iPhone settings and remaining calibration are recorded in docs/AICoin-K线复刻规格.md.
public enum AICoinBehavior {
  public static let initialSpacing = 4.0
  public static let minimumSpacing = 1.6
  public static let maximumSpacing = 40.0
  /// 右轴兜底宽度。**只在没人量过字的时候用**：`Layout` 的默认参数、Core 侧不涉及
  /// 排版的几何测试。真正上屏的那一份由 `ChartRenderer.computeLayout` 按当前刻度
  /// 文字量出来（`axisLabelPadding`），所以这个数不是「右轴有多宽」的答案。
  public static let axisWidth = 50.0
  /// 右轴刻度文字左右各留这么多——轴宽 = 最宽的那条刻度 + 两倍这个数。
  ///
  /// 2026-09-20 之前是「50pt 起跳、不够再按 8pt 一档往上加」，于是 `398.40` 这种
  /// 三位数价位两边各空出一大截白。宽度按内容算之后，位数多的品种自然宽、
  /// 少的自然窄，不为「以后可能更长」预留。
  public static let axisLabelPadding = 4.0
  /// 右轴最窄多少。只在刻度短到不成样子（或者一条刻度都没有）时兜底。
  public static let axisMinWidth = 24.0
  /// 右轴上那些胶囊（最新价、十字线读数、倒计时）离轴两侧各留这么多。
  public static let axisChipInset = 2.0
  /// 胶囊里文字左右各留这么多。两个数加起来正好等于 `axisLabelPadding`，于是最长的
  /// 那条读数在胶囊里的位置和刻度文字**完全对齐**（都从轴左缘往里 4pt 起排），
  /// 胶囊右边还留得下 2pt，不会贴到屏幕边上。
  public static let axisChipPadding = 2.0
  public static let timeHeight = 17.0
  /// iPhone原版进入行情末列贴绘图区右缘；2026-09-15镜像实测。
  public static let rightInset = 0.0
  public static let mainTopInset = 24.0
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
