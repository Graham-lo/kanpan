import Foundation

/// 一根蜡烛的实体宽和影线宽，单位**设备像素**（§5.5，原型 `candleWidths` 的手机分支）。
public struct CandleWidth: Sendable, Equatable {
  public var body: Int
  public var wick: Int
  public init(body: Int, wick: Int) { self.body = body; self.wick = wick }
}

/// 实体和影线奇偶对齐，边缘才不起毛。
func evenUp(raw: Double, body: Int, wick: Int) -> Int {
  var body = body
  if body % 2 != wick % 2 {
    let up = body + 1, down = body - 1
    body = (down >= wick && abs(raw - Double(down)) <= abs(raw - Double(up))) ? down : up
  }
  return max(body, wick)
}

/// Shared candle geometry in points.
public struct CandleMetrics: Sendable, Equatable {
  /// 实体宽。
  public var bodyW: Double
  /// 影线粗细。
  public var wickW: Double
  /// 十字星时实体的保底高度。
  public var minBody: Double
  /// 描边实体的线宽。
  public var outline: Double
  /// 太挤了：只画影线，实体不画。
  public var thin: Bool
}

/// Shared wick width, snapped to whole device pixels.
public func wickPixels(scale: Double) -> Int {
  max(1, Int((max(1, scale) * 2 / 3).rounded()))
}

/// All skins use the same 2/3 body and a visible gap between adjacent candles.
public func candlePixels(spacing: Double, scale: Double) -> CandleWidth {
  let ratio = (scale.isFinite && scale > 0) ? scale : 1
  let sp = (spacing.isFinite && spacing > 0) ? spacing : 0
  let rb = 2.0 / 3
  let raw = sp * rb * ratio
  // 一根占几个像素：`snap` 之后相邻两根的左沿最少差这么多，减 1 就是能给实体的上限。
  let cell = Int((sp * ratio).rounded(.down))
  // 影线也得让出这条缝。从前只有实体受 `cell - 1` 约束、影线直接用风格量化值，
  // 于是捏小之后影线自己就把一格占满了：墩在 3x 上影线 3 像素，一格只剩 3 像素时
  // 缝是 **0**，一排影线糊成一堵墙——正是实机反馈的「影线挤在一起」。
  let wick = min(wickPixels(scale: ratio), max(1, cell - 1))
  let cap = max(wick, cell - 1)
  var body = raw < 2 ? wick : max(1, Int(raw.jsRounded()))
  body = min(body, cap)
  body = evenUp(raw: raw, body: body, wick: wick)
  // `evenUp` 为了配奇偶可能把实体顶上去 1，那就再退 2（奇偶不变），别把缝吃掉。
  if body > cap { body = max(wick, body - 2) }
  return CandleWidth(body: body, wick: wick)
}

/// 由根间距 + 屏幕倍率推出一根蜡烛的全部尺寸。
public func candleMetrics(spacing: Double, scale: Double) -> CandleMetrics {
  let w = candlePixels(spacing: spacing, scale: scale)
  let bodyW = Double(w.body) / scale
  let wickW = Double(w.wick) / scale
  let cell = Int((spacing * scale).rounded(.down))
  return CandleMetrics(
    bodyW: bodyW,
    wickW: wickW,
    minBody: 1 / scale,
    outline: 1 / scale,
    // 判据改成物理条件：一格里放不下比影线更宽的实体了，画实体就是白画。
    // 原来写死的 `spacing < 1.3` 和屏幕倍率、风格都无关，2x 和 3x 该退化的点不一样。
    thin: cell - 1 <= w.wick || w.body <= w.wick)
}

/// 影线粗细，换回点。整数设备像素除以 scale，落笔正好压满整数个像素。
func wickLineWidth(scale: Double) -> Double {
  Double(wickPixels(scale: scale)) / scale
}

/// 所有 x 都先乘 scale 取整再除回，保证落在设备像素边界（§5.6 末句）。
public func snap(_ x: Double, scale: Double) -> Double { (x * scale).rounded() / scale }
/// 1 像素细线的中心：取整再加半像素。
public func hairline(_ y: Double, scale: Double) -> Double { ((y * scale).rounded() + 0.5) / scale }
