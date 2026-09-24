import Foundation

/// 视野与命中的几何尺寸。手势手感（长按、拖动门槛、捏合、选中手柄靶）在 KanpanChart 的 `ChartGesture`。
public enum Chart {
  public static let minBarSpacing: Double = AICoinBehavior.minimumSpacing    // 再挤就只剩一根竖线
  public static let maxBarSpacing: Double = 40     // 再拉开就没有「盘」的样子了
  public static let priceLabelPx: Double = 46
  public static let timeLabelPx: Double = 74
  /// 未选中的那些线，手柄与线体的命中半径（pt）。
  ///
  /// 保持 9.5pt 不动（第五轮审查 A.4 的裁决）：pt 是**物理尺寸**，3x 屏上就是 28.5 个物理像素、
  /// 直径约 19pt ≈ 3 毫米，并不会「因为屏幕更密就变小」；再往大调，图上多几条线之后相邻两条的靶
  /// 就开始互相吃——点谁都不确定，比偶尔点偏一次更难用。真正缺靶的是**正在编辑**的那条，
  /// 所以放大只发生在选中项的手柄上，见 KanpanChart 的 `ChartGesture.selectedHandlePt`。
  public static let hitHandlePt: Double = 9.5
  public static let hitLinePt: Double = 9.5
  /// 画线标签一行占多高（pt）。排版与命中共用同一个值，见 `placeDrawingLabels`。
  public static let drawLabelLineH: Double = 13
  public static let loadMoreBars: Double = 200
}
