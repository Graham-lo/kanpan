import CoreGraphics
import Foundation
import KanpanCore

extension ChartRenderer {
  /// 十根价位锚定的量柱；只占现有图区，盘口既不改价格范围，也不改轴宽。
  func drawDepth(_ ctx: CGContext, pane: Pane, range: PriceRange, L: Layout) {
    guard let book = state.depth, book.symbol == state.symbol.symbol else { return }
    let largest = (book.bids + book.asks).map(\.quantity).max() ?? 0
    guard largest > 0 else { return }
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: pane.y, width: L.plotW, height: pane.h))
    let maxWidth = min(72.0, L.plotW * 0.24)
    for (levels, color) in [(book.bids, state.colors.up), (book.asks, state.colors.down)] {
      ctx.setFillColor(Paint.cg(color)); ctx.setAlpha(0.4)
      for level in levels {
        let width = maxWidth * level.quantity / largest
        let y = KanpanCore.yOf(level.price, pane: pane, range: range, mode: state.price.mode)
        guard y.isFinite else { continue }
        ctx.fill(CGRect(x: L.plotW - width, y: y - 0.5, width: width, height: 1))
      }
    }
    ctx.restoreGState()
  }
}
