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
///
/// **这是原型口径**（`prototype/src/chart.js` 的 `candleWidths`），A1.3 逐点对账用它。
/// 真正画蜡烛走 `candlePixels`：原型的影线宽只看 dpr 不看风格，也不保证相邻两根之间
/// 留得出缝，缩小之后会糊成一片（M6 实机反馈）。两条口径分开留着，对账的归对账。
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

/// 影线宽度，**整数设备像素**。
///
/// 风格表里的 0.5 / 0.8 / 0.9 / 1.8 这些小数是「想要多粗」的意图值，不是能直接画的宽度：
/// CoreGraphics 拿到 0.5 会画出一条 50% 覆盖率的灰线（靛/砖/骨/密四款全中，而密和骨
/// 恰恰是密度最高的两款），拿到 1.8 会让右边缘落在像素中间被抗锯齿吃掉一截。用户实机
/// 反馈的「颜色变淡、影线模糊」就是这个。一律四舍五入到整数像素，最小 1。
///
/// 结果：墩 1.8→2，针 2.0→2，芯/阔 1.0→1，纸 0.8→1，描 0.9→1，靛/砖/骨/密 0.5→1。
///
/// - Parameter scale: 目前用不上——风格表的 `wick` 本来就是按设备像素写的。留着这个参数
///   是为了万一以后要按屏幕倍率分档时不用改所有调用点。
public func wickPixels(style: CandleStyle, scale: Double) -> Int {
  _ = scale
  return max(1, Int(max(0.5, style.wick).jsRounded()))
}

/// 实际绘制用的一根蜡烛宽度，单位**设备像素**。和 `candleWidths` 的区别有两条：
///
/// 1. 影线按风格量化（`wickPixels`），不再是原型那个只看 dpr 的 `round(scale/2)`。
///    这样 `evenUp` 的奇偶对齐才真的生效——原来渲染器只取了 `w.body`，影线另走
///    `wickLineWidth`，奇偶从来没对上过，整个设计意图是死的。
/// 2. 实体上限 `cell - 1`（`cell` = 一根占的整数像素），保证相邻两根之间至少留得出
///    1 个设备像素的缝。原型没有这一条，捏小之后实体会连成一片（实测墩在 1.3pt 时
///    3 像素一格、实体 3 像素，缝为 0）。
///
/// 注意所有风格的**默认根间距都碰不到第 2 条**（墩 9.2pt@3x 算下来 `min(24, 26) = 24`），
/// 它只在用户捏小之后才生效。
public func candlePixels(spacing: Double, scale: Double, style: CandleStyle) -> CandleWidth {
  let ratio = (scale.isFinite && scale > 0) ? scale : 1
  let sp = (spacing.isFinite && spacing > 0) ? spacing : 0
  let rb = (style.bodyR.isFinite && style.bodyR > 0) ? style.bodyR : 0.55
  let wick = wickPixels(style: style, scale: ratio)
  let raw = sp * rb * ratio
  // 一根占几个像素：`snap` 之后相邻两根的左沿最少差这么多，减 1 就是能给实体的上限。
  let cell = Int((sp * ratio).rounded(.down))
  let cap = max(wick, cell - 1)
  var body = raw < 2 ? wick : max(1, Int(raw.jsRounded()))
  body = min(body, cap)
  body = evenUp(raw: raw, body: body, wick: wick)
  // `evenUp` 为了配奇偶可能把实体顶上去 1，那就再退 2（奇偶不变），别把缝吃掉。
  if body > cap { body = max(wick, body - 2) }
  return CandleWidth(body: body, wick: wick)
}

/// 由根间距 + 风格 + 屏幕倍率推出一根蜡烛的全部尺寸。
public func candleMetrics(spacing: Double, style: CandleStyle, scale: Double) -> CandleMetrics {
  let w = candlePixels(spacing: spacing, scale: scale, style: style)
  let bodyW = Double(w.body) / scale
  let wickW = Double(w.wick) / scale
  let cell = Int((spacing * scale).rounded(.down))
  return CandleMetrics(
    bodyW: bodyW,
    wickW: wickW,
    minBody: max(wickW, style.minBody / scale),
    radius: min(style.radius, bodyW / 2),
    outline: max(1, (scale * 0.9).rounded()) / scale,
    // 判据改成物理条件：一格里放不下比影线更宽的实体了，画实体就是白画。
    // 原来写死的 `spacing < 1.3` 和屏幕倍率、风格都无关，2x 和 3x 该退化的点不一样。
    thin: cell - 1 <= w.wick || w.body <= w.wick)
}

/// 影线粗细，换回点。整数设备像素除以 scale，落笔正好压满整数个像素。
public func wickLineWidth(style: CandleStyle, scale: Double) -> Double {
  Double(wickPixels(style: style, scale: scale)) / scale
}

/// 所有 x 都先乘 scale 取整再除回，保证落在设备像素边界（§5.6 末句）。
public func snap(_ x: Double, scale: Double) -> Double { (x * scale).rounded() / scale }
/// 1 像素细线的中心：取整再加半像素。
public func hairline(_ y: Double, scale: Double) -> Double { ((y * scale).rounded() + 0.5) / scale }
