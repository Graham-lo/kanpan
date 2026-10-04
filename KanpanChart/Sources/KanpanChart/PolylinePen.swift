import CoreGraphics

/// 描指标线、收盘线、对比线这类「一根 K 线一个点」的长折线。
///
/// CoreGraphics 把一次 `strokePath` 里的整条折线当成一个多边形去做抗锯齿扫描，
/// 代价随段数超线性涨：同一条 214 点的线，一笔描完 270 µs（圆角连接 320 µs），
/// 拆成每笔 32 段、相邻两笔共用一段的若干笔只要 155–175 µs。缩到最小间距时
/// 一帧要描十来条这样的线（均线、成交量均线、MACD、RSI……），这一项就占了图层
/// 七成时间（2026-10-04 深度审查 F 线实测）。
///
/// 拆笔不改画面：每一笔从上一笔的倒数第二个点起笔，衔接处那一段画两遍，
/// 两边的连接都还在笔中间、照常画出圆角或尖角；差别只在那一段抗锯齿边缘的
/// 半透明像素被叠了两次。所以**只对不透明的颜色拆**——半透明的线叠两次会在
/// 衔接处看出一截更深的颜色，那种线照旧一笔描完。
///
/// 用法和 `move/addLine/strokePath` 一样：逐点 `add`，遇到 `NaN` 断线 `lift`，
/// 最后 `finish`。颜色、线宽、连接方式由调用方在建笔之前设好。
struct PolylinePen {
  /// 每笔最多描多少段。8–32 段的耗时差不到 10%，取 32 让重叠的那一段最少。
  static let segmentsPerStroke = 32

  private let ctx: CGContext
  private let split: Bool
  private var run: [CGPoint] = []
  private var on = false
  /// 这支笔一共调了几次 `strokePath`（测试用）。
  private(set) var strokes = 0

  init(_ ctx: CGContext, color: CGColor, capacity: Int = 0) {
    self.ctx = ctx
    split = color.alpha >= 1
    ctx.setStrokeColor(color)
    ctx.beginPath()
    if split { run.reserveCapacity(capacity) }
  }

  mutating func add(_ p: CGPoint) {
    if split { run.append(p); return }
    if on { ctx.addLine(to: p) } else { ctx.move(to: p); on = true }
  }

  /// 断线：下一个点重新起笔，不和前面连。
  mutating func lift() {
    if split { flush() }
    on = false
  }

  mutating func finish() {
    if split {
      flush()
    } else {
      ctx.strokePath()
      strokes += 1
    }
    on = false
  }

  private mutating func flush() {
    defer { run.removeAll(keepingCapacity: true) }
    guard run.count > 1 else { return }
    for r in Self.strokeRanges(pointCount: run.count) {
      ctx.beginPath()
      ctx.move(to: run[r.lowerBound])
      for k in (r.lowerBound + 1)..<r.upperBound { ctx.addLine(to: run[k]) }
      ctx.strokePath()
      strokes += 1
    }
  }

  /// 一段 `pointCount` 个点的连续折线拆成哪几笔：每笔是一段点下标区间，
  /// 第一笔最多 `per + 1` 个点、之后每笔最多 `per + 2` 个点；后一笔从前一笔的倒数第二个点起，所以每一段都至少
  /// 在某一笔里完整出现，每个连接点都落在某一笔的中间。
  static func strokeRanges(pointCount: Int, per: Int = segmentsPerStroke) -> [Range<Int>] {
    guard pointCount > 1, per > 0 else { return [] }
    var out: [Range<Int>] = []
    var k = 0
    while k < pointCount - 1 {
      let e = min(pointCount, k + per + 1)
      out.append(max(0, k - 1)..<e)
      k = e - 1
    }
    return out
  }
}
