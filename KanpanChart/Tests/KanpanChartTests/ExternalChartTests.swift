import CoreGraphics
import KanpanCore
import Testing
import UIKit
@testable import KanpanChart

@MainActor
@Suite("外部指标和盘口绘制")
struct ExternalChartTests {
  @Test("只更新外部指标会更新曲线与基差百分比")
  func inputRefresh() {
    var renderer = AxisWidthTests.renderer(subs: [.lsr, .taker, .basis])
    let bars = renderer.state.series
    let a = ExternalSeries(t0: bars.t0, step: bars.step, columns: [Array(repeating: -0.03, count: bars.count)])
    renderer.state.external = [.basis: a]
    #expect(renderer.displayed(.basis)?.lines.first?.last == -0.03)
    #expect(renderer.subValueText(-0.03, indicator: .basis) == "-0.030%")
    var b = a; b.columns = [Array(repeating: 0.02, count: bars.count)]
    renderer.state.external = [.basis: b]
    #expect(renderer.displayed(.basis)?.lines.first?.last == 0.02)
  }

  @Test("盘口只刷新实时层，不改变布局、轴宽和价格范围")
  func depthGeometry() {
    var renderer = AxisWidthTests.renderer()
    let old = renderer.state
    let size = AxisWidthTests.size
    let layout = renderer.layout(size: size), range = renderer.priceRange(size: size)
    let price = old.series.close.last!
    renderer.state.depth = OrderBook(symbol: old.symbol.symbol, time: old.series.lastTime,
      bids: [.init(price: price - 0.1, quantity: 10)], asks: [.init(price: price + 0.1, quantity: 20)])
    #expect(renderer.layout(size: size) == layout)
    #expect(renderer.priceRange(size: size) == range)
    #expect(ChartView.changed(from: old, to: renderer.state) == .live)
    renderer.state.options.lastLine = false
    let image = UIGraphicsImageRenderer(size: size).image { context in
      renderer.drawLive(in: context.cgContext, size: size, scale: 2)
    }
    #expect(image.cgImage != nil)
  }
}
