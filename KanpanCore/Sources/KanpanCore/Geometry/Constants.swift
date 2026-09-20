import Foundation

/// Shared input constants; Android-only values await current-iPhone calibration.
public enum Chart {
  public static let minBarSpacing: Double = AICoinBehavior.minimumSpacing    // 再挤就只剩一根竖线
  public static let maxBarSpacing: Double = 40     // 再拉开就没有「盘」的样子了
  public static let priceLabelPx: Double = 46
  public static let timeLabelPx: Double = 74
  public static let longPressMs: Double = 400
  public static let longPressSlopPt: Double = 6
  public static let panSlopPt: Double = 4
  /// 两指再近也不会真的重合；低于这个间距的样本只当噪声丢掉，免得 d/d0 炸掉。
  /// 单位是 pt（物理尺寸），不能再按 displayScale 换算——那会让 2x 的 iPad 比 3x 的手机多出一截死区。
  public static let minPinchSpanPt: Double = 10
  /// 未选中的那些线，手柄与线体的命中半径（pt）。
  ///
  /// 保持 9.5pt 不动（第五轮审查 A.4 的裁决）：pt 是**物理尺寸**，3x 屏上就是 28.5 个物理像素、
  /// 直径约 19pt ≈ 3 毫米，并不会「因为屏幕更密就变小」；再往大调，图上多几条线之后相邻两条的靶
  /// 就开始互相吃——点谁都不确定，比偶尔点偏一次更难用。真正缺靶的是**正在编辑**的那条，
  /// 所以放大只发生在选中项的手柄上，见 `selectedHandlePt`。
  public static let hitHandlePt: Double = 9.5
  public static let hitLinePt: Double = 9.5
  /// 选中那条线的手柄靶半径（pt）。
  ///
  /// 手指的接触面直径本来就有 40pt 上下，正在拖的端点必须给足。但这个放大**只给手柄**：
  /// 从前它被当成整条线的命中半径传进 `DrawGeometry.hit`，于是线体和整块填充跟着一起放大，
  /// 一个选中的矩形能把压在它里面的趋势线整条吞掉（A-02）。
  public static let selectedHandlePt: Double = 22
  /// 画线标签一行占多高（pt）。排版与命中共用同一个值，见 `placeDrawingLabels`。
  public static let drawLabelLineH: Double = 13
  public static let loadMoreBars: Double = 200
}
