import Foundation

/// 视野夹取（§5.2，原型 `Chart.clamp`）。
///
/// 右侧能拖出大片空白是**正常行为**（最后一根最多推到 30% 处），不要收紧。
public func clampView(
  _ v: ViewWindow, series: BarSeries, plotW: Double, soft: Bool = false
) -> ViewWindow {
  guard series.count > 0 else { return v }
  let step = Double(series.step)
  let span0 = v.span
  let minSpan = (plotW / Chart.maxBarSpacing) * step
  let maxSpan = min((plotW / Chart.minBarSpacing) * step, Double(series.count) * step * 3)
  let span = max(minSpan, min(maxSpan, span0))
  var to = v.to + (span - span0) / 2       // 缩放越界时以中心为锚修正
  let firstT = Double(series.firstTime)
  let lastT = Double(series.lastTime)
  let give = soft ? span * Chart.softGive : 0
  let maxTo = lastT + span * 0.7 + give
  let minTo = firstT + span * 0.3 - give
  if to > maxTo { to = maxTo }
  if to < minTo { to = minTo }
  return ViewWindow(to: to, span: span)
}

extension ViewAnchor {
  /// 复位时最新一根右边要留多少空白，单位是「窗宽的几成」。
  ///
  /// `.right` 就是原来那个 6%（`Chart.rightGap`），一个字没动——默认档必须逐像素等于现状。
  /// `.center` 留半屏，最新一根正好落在图区正中。
  ///
  /// `.left` 名义上想留 75%（最新一根落在左侧 1/4 处），但实际只到 30%：`clampView` 的
  /// `maxTo = lastT + span * 0.7` 把它截住了。那条 0.7 同时管着手指拖动的边界和手感
  /// （§5.2 注释写明「右侧能拖出大片空白是正常行为，不要收紧」），为了一个复位档去放宽
  /// 它，代价是整套拖动边界跟着变，不划算。所以这里照写 0.75，让夹取去截，
  /// 实测落点是距左边缘 30%——比居中更靠左，方向对，只是没到 25%。
  var rightGapRatio: Double {
    switch self {
    case .right: Chart.rightGap
    case .center: 0.5
    case .left: 0.75
    }
  }
}

public enum ViewMath {
  /// 初始视野 / 换品种：右边缘留 6% 空白，窗宽按风格默认根间距（原型 `resetView`）。
  ///
  /// - Parameter anchor: 「回到最新」时最新一根停在横向哪儿（K 线设置·拖动位置）。
  ///   默认 `.right` = 原行为，老调用点一个字都不用改。
  public static func reset(
    series: BarSeries, plotW: Double, spacing: Double, anchor: ViewAnchor = .right
  ) -> ViewWindow {
    guard series.count > 0 else { return ViewWindow(from: 0, to: 1) }
    let span = (plotW / spacing) * Double(series.step)
    let to = Double(series.lastTime) + span * anchor.rightGapRatio
    return clampView(ViewWindow(to: to, span: span), series: series, plotW: plotW)
  }

  /// 换风格：右边缘不动，按新风格的默认根间距重算窗宽（原型 `applySpacing`）。
  public static func applySpacing(
    _ v: ViewWindow, series: BarSeries, plotW: Double, spacing: Double
  ) -> ViewWindow {
    guard series.count > 0 else { return v }
    let span = (plotW / spacing) * Double(series.step)
    return clampView(ViewWindow(to: v.to, span: span), series: series, plotW: plotW)
  }

  /// 切周期：**根宽不变**，看见的时间跨度跟着周期走（原型 `switchInterval`）。
  ///
  /// - Parameter spacing: 切之前量出来的实际根间距（`ViewWindow.barSpacing`）。
  public static func switchInterval(
    to series: BarSeries, plotW: Double, spacing: Double, anchorRight: Double?
  ) -> ViewWindow {
    guard series.count > 0 else { return ViewWindow(from: 0, to: 1) }
    let s = min(Chart.maxBarSpacing, max(Chart.minBarSpacing, spacing))
    let span = (plotW / s) * Double(series.step)
    let lastT = Double(series.lastTime)
    let to = anchorRight.map { min($0, lastT + span * Chart.rightGap) } ?? (lastT + span * Chart.rightGap)
    return clampView(ViewWindow(to: to, span: span), series: series, plotW: plotW)
  }

  /// 双指缩放的单次快照（§7）：按下时记 `(from0, span0, d0, m0)`，每帧只用这一份。
  /// 先捏开再捏拢和反过来速度一样。
  public static func pinch(
    from0: Double, span0: Double, d0: Double, d: Double, mid0Px: Double, plotW: Double
  ) -> ViewWindow {
    let ratio = d0 / max(d, 1e-6)
    let span = span0 * ratio
    let anchor = from0 + mid0Px / plotW * span0     // 两指中点对应的时间，固定不动
    let from = anchor - mid0Px / plotW * span
    return ViewWindow(to: from + span, span: span)
  }

  /// 轴拖缩放：以按下点为锚横向缩放（时间轴拖）。
  public static func zoom(
    _ v: ViewWindow, factor: Double, anchorPx: Double, plotW: Double
  ) -> ViewWindow {
    let anchor = v.t(atX: anchorPx, plotW: plotW)
    let span = v.span * factor
    let from = anchor - anchorPx / plotW * span
    return ViewWindow(to: from + span, span: span)
  }

  /// 该补历史了吗：视野左缘进到序列头部 200 根以内（§7）。
  public static func needsMoreHistory(_ v: ViewWindow, series: BarSeries) -> Bool {
    guard series.count > 0 else { return false }
    return v.from <= Double(series.firstTime) + Chart.loadMoreBars * Double(series.step)
  }
}
