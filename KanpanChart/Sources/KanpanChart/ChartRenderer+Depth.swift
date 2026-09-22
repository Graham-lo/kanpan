import CoreGraphics
import Foundation
import KanpanCore

extension ChartRenderer {
  struct DepthRow {
    let frame: CGRect
    let color: Hex
  }

  /// 买卖各五档固定行高，分界贴最新价；整架平移进主图，不参与定标。
  func depthRows(pane: Pane, range: PriceRange, L: Layout) -> [DepthRow] {
    guard let book = state.depth, book.symbol == state.symbol.symbol,
          let price = state.series.close.last else { return [] }
    let largest = (book.bids + book.asks).map(\.quantity).max() ?? 0
    let rowHeight = 6.0, gap = 1.0, height = 69.0
    guard largest > 0, pane.h >= height, L.plotW > 0 else { return [] }
    let priceY = KanpanCore.yOf(price, pane: pane, range: range, mode: state.price.mode)
    guard priceY.isFinite else { return [] }
    let top = max(pane.y, min(pane.y + pane.h - height, priceY - height / 2))
    let maxWidth = min(64.0, L.plotW)
    // 卖一、买一紧邻中间的空隙；缺档保持空行，不拿另一侧补足。
    let asks = book.asks.enumerated().map { (4 - $0.offset, $0.element, state.colors.down) }
    let bids = book.bids.enumerated().map { (5 + $0.offset, $0.element, state.colors.up) }
    return (asks + bids).sorted { $0.0 < $1.0 }.map { slot, level, color in
      let width = maxWidth * level.quantity / largest
      return DepthRow(frame: CGRect(x: L.plotW - width, y: top + Double(slot) * (rowHeight + gap),
                                    width: width, height: rowHeight), color: color)
    }
  }

  /// 返回实际填充的行数，模拟器探针核对绘制而非仅核对已收到的深度数据。
  @discardableResult
  func drawDepth(_ ctx: CGContext, pane: Pane, range: PriceRange, L: Layout) -> Int {
    let rows = depthRows(pane: pane, range: range, L: L)
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: pane.y, width: L.plotW, height: pane.h))
    ctx.setAlpha(0.55)
    for row in rows {
      ctx.setFillColor(Paint.cg(row.color))
      ctx.fill(row.frame)
    }
    ctx.restoreGState()
    return rows.count
  }
}
