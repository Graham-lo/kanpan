import Foundation

/// AICoin column offsets expressed as a time window. The final column includes half a cell.
public func clampView(_ v: ViewWindow, series: BarSeries, plotW: Double,
                      anchor: ViewAnchor = .right) -> ViewWindow {
  guard !series.isEmpty, plotW > 0 else { return v }
  let step = Double(series.step)
  let span = max(plotW / AICoinBehavior.maximumSpacing * step,
                 min(plotW / AICoinBehavior.minimumSpacing * step, v.span))
  let spacing = plotW / span * step
  let first = Double(series.firstTime) - step / 2
  let maximumOffset = ViewMath.maximumOffset(count: series.count, spacing: spacing, plotW: plotW, anchor: anchor)
  let offset = (v.to - span - first) / step * spacing
  let clampedOffset = max(0, min(maximumOffset, offset))
  return ViewWindow(to: first + clampedOffset / spacing * step + span, span: span)
}

public enum ViewMath {
  /// 单指在任一数据边界越界可拉出空白，松手回对应边界；历史中途不吸附。
  /// 阻力曲线是本项目实现参数，未宣称为原版iOS精确拟合。
  public static func dragging(_ proposed: ViewWindow, series: BarSeries, plotW: Double,
                              anchor: ViewAnchor = .right) -> ViewWindow {
    let settled = clampView(proposed, series: series, plotW: plotW, anchor: anchor)
    guard !series.isEmpty, plotW > 0, settled.span > 0 else { return settled }
    let beyond = (proposed.to - settled.to) / settled.span * plotW
    guard beyond != 0, beyond.isFinite else { return settled }
    let extent = min(32, plotW * 0.1)
    let pull = extent * (1 - 1 / (1 + 0.55 * abs(beyond) / extent))
    return ViewWindow(to: settled.to + (beyond > 0 ? pull : -pull) / plotW * settled.span, span: settled.span)
  }

  public static func maximumOffset(count: Int, spacing: Double, plotW: Double, anchor: ViewAnchor) -> Double {
    let total = max(0, Double(count + 400) * spacing - plotW)
    let reserved = min(400 * spacing - rightInset(anchor, plotW: plotW), total)
    return max(0, total - reserved)
  }

  public static func rightInset(_ anchor: ViewAnchor, plotW: Double) -> Double {
    switch anchor {
    case .right: AICoinBehavior.rightInset
    case .center: floor(plotW / 2)
    case .left: 2 * floor(plotW / 3)
    }
  }

  public static func reset(series: BarSeries, plotW: Double, spacing: Double,
                           anchor: ViewAnchor = .right) -> ViewWindow {
    guard !series.isEmpty else { return ViewWindow(from: 0, to: 1) }
    let w = min(AICoinBehavior.maximumSpacing, max(AICoinBehavior.minimumSpacing, spacing))
    let step = Double(series.step)
    let view = ViewWindow(to: Double(series.lastTime) + step / 2
                           + rightInset(anchor, plotW: plotW) / w * step,
                          span: plotW / w * step)
    return clampView(view, series: series, plotW: plotW, anchor: anchor)
  }

  /// Layout resizing preserves cell width and historical right time.
  public static func resized(_ v: ViewWindow, series: BarSeries, plotW: Double,
                             spacing: Double, anchor: ViewAnchor = .right) -> ViewWindow {
    guard !series.isEmpty else { return v }
    return clampView(ViewWindow(to: v.to, span: plotW / spacing * Double(series.step)),
                     series: series, plotW: plotW, anchor: anchor)
  }

  /// 换周期：根宽（一根占多少像素）照旧，看见的时间跨度跟着新周期走。
  ///
  /// `anchorRight` 是「切之前视野的右缘时刻」，只有在**看历史**的时候才该传：
  /// 人正翻着三个月前的那一段，切个周期就被送回最新，等于把刚找到的位置弄丢了（A-05）。
  /// 反过来，**跟着最新**的时候必须传 nil——那时右缘本来就该重新贴到新序列的末根上，
  /// 拿旧右缘去夹会在右边留下一截空白（新周期的末根时间往往比旧的更靠后）。
  /// 「在看历史还是跟着最新」由调用方判断（它才知道切之前那张图的状态）。
  public static func switchInterval(to series: BarSeries, plotW: Double, spacing: Double,
                                    anchorRight: Double?) -> ViewWindow {
    let latest = reset(series: series, plotW: plotW, spacing: spacing)
    guard let anchorRight, !series.isEmpty else { return latest }
    return clampView(ViewWindow(to: min(anchorRight, latest.to), span: latest.span),
                     series: series, plotW: plotW)
  }

  /// One accepted scale event. Boundary state, not the user's inset setting, chooses the anchor.
  public static func scaled(_ v: ViewWindow, series: BarSeries, plotW: Double,
                            factor: Double, focus: Double, anchor: ViewAnchor = .right) -> ViewWindow {
    guard factor > 0, factor.isFinite, !series.isEmpty else { return v }
    let oldW = v.barSpacing(step: series.step, plotW: plotW)
    let newW = min(AICoinBehavior.maximumSpacing, max(AICoinBehavior.minimumSpacing, oldW * factor))
    let oldRight = reset(series: series, plotW: plotW, spacing: oldW, anchor: anchor)
    let offset = (v.from - Double(series.firstTime)) / Double(series.step) * oldW + oldW / 2
    if abs(v.to - oldRight.to) / v.span * plotW < 0.5 {
      return reset(series: series, plotW: plotW, spacing: newW, anchor: anchor)
    }
    let pin = offset <= 0.5 ? 0 : focus
    let span = plotW / newW * Double(series.step)
    let time = v.t(atX: pin, plotW: plotW)
    return clampView(ViewWindow(from: time - pin / plotW * span,
                               to: time + (1 - pin / plotW) * span),
                     series: series, plotW: plotW, anchor: anchor)
  }

  public static func needsMoreHistory(_ v: ViewWindow, series: BarSeries) -> Bool {
    !series.isEmpty && v.from <= Double(series.firstTime) + Chart.loadMoreBars * Double(series.step)
  }
}
