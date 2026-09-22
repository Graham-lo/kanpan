import CoreGraphics
import Foundation
import KanpanCore
import UIKit

/// 三层绘制的三个入口（§5.7）。
///
/// 叠放顺序照原型的 `base` / `over` 两块画布拆出来：原型 `render()` 的次序是
/// 网格 → 蜡烛 → 叠加 → 画线 → **最新价** → 副图 → 时间轴 → **图例**，十字线另画在
/// `over` 上盖在最上面。所以这里：
///
/// - `plotLayer`：最新价与图例**之外**的全部内容
/// - `liveLayer`：最新价线 + 右轴胶囊（在图例之下、蜡烛之上）
/// - `crossLayer`：图例 → 十字线 + 三处读数
///
/// 图例放在最上层不只是为了对齐叠放顺序：图例读的是 `legendIndex`，十字线一动它就得
/// 跟着换一根，留在 `plotLayer` 的话十字线跟手时图例数值会一直停在旧值上。
extension ChartRenderer {
  /// `plotLayer`：背景、网格、K 线、叠加、画线、副图、时间轴。不含最新价与图例。
  public func drawPlot(in ctx: CGContext, size: CGSize, scale: CGFloat) {
    draw(in: ctx, size: size, scale: scale, live: false, legend: false)
  }

  /// `liveLayer`：最新价线 + 右轴胶囊。
  public func drawLive(in ctx: CGContext, size: CGSize, scale: CGFloat) {
    ctx.clear(CGRect(origin: .zero, size: size))
    // 关掉实时价格线时这一层永远是空的：清完就走，连价格区间都不用算。
    guard !state.series.isEmpty else { return }
    let L = layout(size: size)
    let r = priceRange(size: size)
    UIGraphicsPushContext(ctx)
    defer { UIGraphicsPopContext() }
    drawDepth(ctx, pane: L.main, range: r, L: L)
    if state.options.lastLine { drawLastPrice(ctx, pane: L.main, r: r, L: L, scale: Double(scale)) }
  }

  /// `crossLayer`：图例 + 十字线 + 三处读数。`state.crosshair == nil` 时只画图例。
  public func drawCross(in ctx: CGContext, size: CGSize, scale: CGFloat) {
    ctx.clear(CGRect(origin: .zero, size: size))
    guard !state.series.isEmpty else { return }
    let L = layout(size: size)
    UIGraphicsPushContext(ctx)
    drawLegends(ctx, L: L)
    UIGraphicsPopContext()
    drawOverlay(in: ctx, size: size, scale: scale)
  }
}
