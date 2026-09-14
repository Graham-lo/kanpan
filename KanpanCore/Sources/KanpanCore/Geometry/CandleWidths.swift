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

/// 影线半个设备像素；实体不到 2 像素就退成一根竖线。
public func candleWidths(spacing: Double, scale: Double, bodyR: Double) -> CandleWidth {
  let ratio = (scale.isFinite && scale > 0) ? scale : 1
  let sp = (spacing.isFinite && spacing > 0) ? spacing : 0
  let rb = (bodyR.isFinite && bodyR > 0) ? bodyR : 0.55
  let wick = max(1, Int((ratio / 2).jsRounded()))
  let raw = sp * rb * ratio
  if raw < 2 { return CandleWidth(body: wick, wick: wick) }
  return CandleWidth(body: evenUp(raw: raw, body: max(1, Int(raw.jsRounded())), wick: wick), wick: wick)
}

/// 一根蜡烛画出来的实际尺寸，单位**点**（pt）。风格表里的 `wick`/`minBody`/`radius`
/// 都是按设备像素写的，所以一律除以 scale 换回点，和原型 `drawCandles` 开头一致。
public struct CandleMetrics: Sendable, Equatable {
  /// 实体宽。
  public var bodyW: Double
  /// 影线粗细。
  public var wickW: Double
  /// 十字星时实体的保底高度。
  public var minBody: Double
  /// 实体圆角（不超过半个实体宽）。
  public var radius: Double
  /// 描边实体的线宽。
  public var outline: Double
  /// 太挤了：只画影线，实体不画。
  public var thin: Bool
}

/// 由根间距 + 风格 + 屏幕倍率推出一根蜡烛的全部尺寸。
public func candleMetrics(spacing: Double, style: CandleStyle, scale: Double) -> CandleMetrics {
  let w = candleWidths(spacing: spacing, scale: scale, bodyR: style.bodyR)
  let bodyW = Double(w.body) / scale
  let wickW = wickLineWidth(style: style, scale: scale)
  return CandleMetrics(
    bodyW: bodyW,
    wickW: wickW,
    minBody: max(wickW, style.minBody / scale),
    radius: min(style.radius, bodyW / 2),
    outline: max(1, (scale * 0.9).rounded()) / scale,
    thin: spacing < 1.3 || bodyW <= wickW * 1.2)
}

/// 影线粗细：风格表的值兜底半个像素，再换回点（原型 `wickW`）。
public func wickLineWidth(style: CandleStyle, scale: Double) -> Double {
  max(0.5, style.wick) / scale
}

/// 所有 x 都先乘 scale 取整再除回，保证落在设备像素边界（§5.6 末句）。
public func snap(_ x: Double, scale: Double) -> Double { (x * scale).rounded() / scale }
/// 1 像素细线的中心：取整再加半像素。
public func hairline(_ y: Double, scale: Double) -> Double { ((y * scale).rounded() + 0.5) / scale }
