import Foundation
import KanpanCore
import Testing
import UIKit
@testable import KanpanChart

@MainActor struct ShareRenderingTests {
  @Test func ownInkIsCompositedAt35PercentAndGuestIsFullStrength() throws {
    let series = BarSeries(symbol: "BTCUSDT", interval: .h1, t0: 0,
                          open: Array(repeating: 100, count: 60), high: Array(repeating: 105, count: 60),
                          low: Array(repeating: 95, count: 60), close: Array(repeating: 101, count: 60), volume: Array(repeating: 1, count: 60))
    let size = CGSize(width: 400, height: 300)
    let empty = ChartState(series: series, symbol: SymbolInfo(symbol: "BTCUSDT", base: "BTC", pricePrecision: 2, tickSize: 0.1),
                           view: ViewWindow(to: Double(series.lastTime), span: 40 * Double(series.step)), overlays: [], subs: [])
    var own = Drawing(kind: .hline, points: [DrawPoint(t: Double(series.lastTime), p: 102)])
    own.lineWidth = 3
    var guest = own; guest.id = Drawing.newID(); guest.points[0].p = 104
    var normal = ChartRenderer(state: empty); normal.state.drawings = [own]
    var dim = normal; dim.ownDimmed = true
    var mixed = dim; mixed.guestDrawings = [guest]
    var guestOnly = ChartRenderer(state: empty); guestOnly.guestDrawings = [guest]
    let base = pixels(ChartRenderer(state: empty), size), full = pixels(normal, size), faint = pixels(dim, size)
    let range = normal.priceRange(size: size), layout = normal.layout(size: size)
    let y = Int(yOf(102, pane: layout.main, range: range, mode: empty.price.mode).rounded())
    let x = Int(layout.plotW * 0.4)
    var index = (y*400+x)*4
    var best = -1
    for row in (y-2)...(y+2) {
      let candidate = (row*400+x)*4
      var distance = 0
      for channel in 0..<3 { distance += abs(Int(full[candidate+channel])-Int(base[candidate+channel])) }
      if distance > best { best = distance; index = candidate }
    }
    #expect((0..<3).contains { full[index+$0] != base[index+$0] }, "probe must hit the own line")
    for channel in 0..<3 {
      let expected = Double(base[index+channel]) + (Double(full[index+channel])-Double(base[index+channel])) * 0.35
      #expect(abs(Double(faint[index+channel])-expected) <= 2)
    }
    let composed = pixels(mixed, size), guestPixels = pixels(guestOnly, size)
    let gy = Int(yOf(104, pane: layout.main, range: range, mode: empty.price.mode).rounded())
    for row in (gy-1)...(gy+1) { for c in 0..<3 { #expect(composed[(row*400+x)*4+c] == guestPixels[(row*400+x)*4+c]) } }
    let view = ChartView(frame: CGRect(origin: .zero, size: size)); view.state = empty
    view.guestDrawings = [guest]; view.ownDimmed = true; view.setDrawings([own])
    #expect(view.guestDrawings == [guest]); #expect(view.drawings == [own])
  }
  private func pixels(_ renderer: ChartRenderer, _ size: CGSize) -> [UInt8] {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
    let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer.draw(in: $0.cgContext, size: size, scale: 1) }
    let cg = image.cgImage!
    var result = [UInt8](repeating: 0, count: 400*300*4)
    result.withUnsafeMutableBytes { raw in
      let context = CGContext(data: raw.baseAddress, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 400*4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      context.draw(cg, in: CGRect(origin: .zero, size: size))
    }
    return result
  }
}
