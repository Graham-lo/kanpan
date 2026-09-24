import Foundation

/// 手指在图上怎么算「按住」「拖动」「捏合」「点中手柄」——这些门槛只有图表视图的手势层用，
/// 所以住在 KanpanChart，不在 KanpanCore（审查 24：Core 只放纯模型与几何，不放交互手感）。
/// 视野本身的尺寸上下限（`Chart.minBarSpacing` 等）是几何，仍在 Core。
enum ChartGesture {
  static let longPressMs: Double = 400
  static let longPressSlopPt: Double = 6
  static let panSlopPt: Double = 4
  /// 两指再近也不会真的重合；低于这个间距的样本只当噪声丢掉，免得 d/d0 炸掉。
  /// 单位是 pt（物理尺寸），不能再按 displayScale 换算——那会让 2x 的 iPad 比 3x 的手机多出一截死区。
  static let minPinchSpanPt: Double = 10
  /// 选中那条线的手柄靶半径（pt）。
  ///
  /// 手指的接触面直径本来就有 40pt 上下，正在拖的端点必须给足。但这个放大**只给手柄**：
  /// 从前它被当成整条线的命中半径传进 `DrawGeometry.hit`，于是线体和整块填充跟着一起放大，
  /// 一个选中的矩形能把压在它里面的趋势线整条吞掉（A-02）。未选中的线仍用 `Chart.hitHandlePt`。
  static let selectedHandlePt: Double = 22
}
