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
  public static let hitHandlePt: Double = 9.5
  public static let hitLinePt: Double = 9.5
  public static let loadMoreBars: Double = 200
}
