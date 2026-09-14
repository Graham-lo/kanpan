import Foundation

/// 手感常数。全部从定版原型 `chart.js` 量出来，Swift 侧照搬，不重新发明。
public enum Chart {
  public static let minBarSpacing: Double = 0.4    // 再挤就只剩一根竖线
  public static let maxBarSpacing: Double = 40     // 再拉开就没有「盘」的样子了
  public static let flingTauMs: Double = 325       // 惯性衰减时间常数
  public static let flingMaxMs: Double = 1400
  public static let flingMinPxPerMs: Double = 0.2  // 比这慢就不算甩
  public static let flingMaxPxPerMs: Double = 3
  public static let flingEpsPx: Double = 0.5       // 剩下不到半像素就停
  public static let pinchMinPx: Double = 8         // 两指距离小于这个不算数

  /// 视野右边缘默认留出的空白：`span * 0.06`（原型 `resetView`）。
  public static let rightGap: Double = 0.06
  /// 手指按着时允许多越界的比例，松手回弹（§5.2）。
  public static let softGive: Double = 0.12
  /// 价格轴一格目标高度（原型 `drawPriceGrid`：`floor(pane.h / 46)`）。
  public static let priceLabelPx: Double = 46
  /// 时间轴一个标签的最小占位（原型 `timeTicks`：`timeStep(span, plotW, 74)`）。
  public static let timeLabelPx: Double = 74
  /// 长按出十字线的判定。原型 `pointerdown` 里挂的是 320ms、位移上限 6px
  /// （任务书 §7 的表写的是 450ms——以原型为准，见 `docs/acceptance/M1.md`）。
  public static let longPressMs: Double = 320
  public static let longPressSlopPt: Double = 6
  public static let panSlopPt: Double = 4
  public static let tapMaxMs: Double = 200
  /// 双击判定：两次轻点间隔（原型 `now - lastTap < 280`）。
  public static let doubleTapMs: Double = 280
  /// 命中判定（原型 `hitDraw`）。
  public static let hitHandlePt: Double = 12
  public static let hitLinePt: Double = 9
  /// 补历史触发：视野左缘推进到头部 200 根以内（§7）。
  public static let loadMoreBars: Double = 200
}
