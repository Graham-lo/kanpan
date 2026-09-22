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

  @Test("密集价位仍画出六点高的十行盘口梯，数量决定宽度")
  func fixedDepthLadder() throws {
    var renderer = AxisWidthTests.renderer()
    let price = renderer.state.series.close.last!
    renderer.state.depth = OrderBook(symbol: renderer.state.symbol.symbol, time: renderer.state.series.lastTime,
      bids: (1...5).map { .init(price: price - Double($0) * 0.1, quantity: Double($0)) },
      asks: (1...5).map { .init(price: price + Double($0) * 0.1, quantity: Double($0 + 5)) })
    let layout = renderer.layout(size: AxisWidthTests.size)
    let range = PriceRange(lo: price - 1_000, hi: price + 1_000, base: price)
    let rows = renderer.depthRows(pane: layout.main, range: range, L: layout)
    #expect(rows.count == 10)
    #expect(rows.prefix(5).allSatisfy { $0.color == renderer.state.colors.down })
    #expect(rows.suffix(5).allSatisfy { $0.color == renderer.state.colors.up })
    #expect(rows.allSatisfy { $0.frame.height == 6 && $0.frame.maxX == layout.plotW })
    #expect(rows.map(\.frame.width).max() == 64)
    #expect(abs(rows[5].frame.width - 6.4) < 0.001)
    for index in 1..<rows.count {
      #expect(rows[index].frame.minY - rows[index - 1].frame.maxY == 1)
    }
    #expect(abs((rows[4].frame.maxY + rows[5].frame.minY) / 2 - layout.main.h / 2) < 0.001)

    // 直接读实际绘制像素：旧的按价位1pt细线达不到这个面积与透明度。
    var bytes = [UInt8](repeating: 0, count: 402 * 520 * 4)
    try bytes.withUnsafeMutableBytes { buffer in
      let ctx = try #require(CGContext(data: buffer.baseAddress, width: 402, height: 520,
        bitsPerComponent: 8, bytesPerRow: 402 * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      #expect(renderer.drawDepth(ctx, pane: layout.main, range: range, L: layout) == 10)
    }
    #expect(stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] >= 130 }.count > 1_500)

    for edge in [price - 20_000, price + 20_000] {
      let outside = PriceRange(lo: edge, hi: edge + 1_000, base: price)
      let clamped = renderer.depthRows(pane: layout.main, range: outside, L: layout)
      #expect(clamped.count == 10)
      #expect(clamped.allSatisfy { $0.frame.minY >= layout.main.y && $0.frame.maxY <= layout.main.y + layout.main.h })
    }
    renderer.state.depth = nil
    #expect(renderer.depthRows(pane: layout.main, range: range, L: layout).isEmpty)
  }

}
