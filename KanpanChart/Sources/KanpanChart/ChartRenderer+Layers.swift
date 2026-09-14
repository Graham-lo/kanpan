import CoreGraphics
import Foundation
import KanpanCore
import UIKit

/// 三层绘制的三个入口（§5.7）。
///
/// 一帧的内容按「多久变一次」切成三份：底图几百根 K 线，视野 / 数据 / 风格 / 尺寸
/// 不动就不用重画；最新价每来一个 ticker 就得挪；十字线跟着手指走。三者各占一层
/// `CALayer`，脏了谁画谁。
///
/// 画法本身全在 `ChartRenderer.draw` / `drawLastPrice` / `drawOverlay` 里，这里
/// 只是把它们按层分派——绝不另起一套绘制。
extension ChartRenderer {
  /// `plotLayer`：背景、网格、K 线、叠加、画线、副图、时间轴、图例。不含最新价。
  public func drawPlot(in ctx: CGContext, size: CGSize, scale: CGFloat) {
    draw(in: ctx, size: size, scale: scale, live: false)
  }

  /// `liveLayer`：最新价线 + 右轴胶囊。
  ///
  /// 层是透明的，每次先清干净——上一帧的价格线不能留在底下。
  public func drawLive(in ctx: CGContext, size: CGSize, scale: CGFloat) {
    ctx.clear(CGRect(origin: .zero, size: size))
    guard !state.series.isEmpty else { return }
    let L = layout(size: size)
    let r = priceRange(size: size)
    UIGraphicsPushContext(ctx)
    defer { UIGraphicsPopContext() }
    drawLastPrice(ctx, pane: L.main, r: r, L: L, scale: Double(scale))
  }

  /// `crossLayer`：十字线 + 三处读数。`state.crosshair == nil` 时只把层清空。
  public func drawCross(in ctx: CGContext, size: CGSize, scale: CGFloat) {
    ctx.clear(CGRect(origin: .zero, size: size))
    drawOverlay(in: ctx, size: size, scale: scale)
  }
}
