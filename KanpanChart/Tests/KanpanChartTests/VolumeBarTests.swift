import Foundation
import KanpanCore
import Testing
import UIKit
@testable import KanpanChart

/// 副图量柱的坏量（审查 B·待核实 2 / P3-4）。
///
/// 交易所补的洞、聚合出来的空桶会给出 NaN 量；上游解析器已经挡掉了，但图表这一层
/// 自己也不能拿它去画：NaN 量算出 NaN 矩形，+inf 量算出一根从零线一直顶出视图的柱子。
@MainActor struct VolumeBarTests {
  static let size = CGSize(width: 400, height: 300)
  static let k = 50

  static func state(volumeAtK v: Double) -> ChartState {
    let n = 60
    var volume = [Double](repeating: 100, count: n)
    volume[k] = v
    let open = (0 ..< n).map { 100 + Double($0 % 3) }
    let close = open.enumerated().map { $0.offset % 2 == 0 ? $0.element + 2 : $0.element - 2 }
    let series = BarSeries(symbol: "BTCUSDT", interval: .h1, t0: 0, open: open,
                           high: open.map { $0 + 4 }, low: open.map { $0 - 4 }, close: close, volume: volume)
    return ChartState(series: series, symbol: SymbolInfo(symbol: "BTCUSDT", base: "BTC", pricePrecision: 2, tickSize: 0.1),
                      view: ViewWindow(to: Double(series.lastTime), span: 40 * Double(series.step)),
                      overlays: [], subs: [.vol])
  }

  static func pixels(_ renderer: ChartRenderer) -> [UInt8] {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
    let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer.draw(in: $0.cgContext, size: size, scale: 1) }
    var out = [UInt8](repeating: 0, count: 400 * 300 * 4)
    out.withUnsafeMutableBytes { raw in
      let ctx = CGContext(data: raw.baseAddress, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 400 * 4,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      ctx.draw(image.cgImage!, in: CGRect(origin: .zero, size: size))
    }
    return out
  }

  /// 第 k 根那一列、量副图下部 30%（离均量线远，只有柱子会落在这里）的像素。
  static func column(_ px: [UInt8], _ renderer: ChartRenderer) -> [UInt8] {
    let layout = renderer.layout(size: size)
    let pane = layout.panes.first { $0.indicator == .vol }!
    let x = Int(renderer.state.view.x(Double(renderer.state.series.time(at: k)), plotW: layout.plotW).rounded())
    var out: [UInt8] = []
    for row in Int(pane.y + pane.h * 0.7) ..< Int(pane.y + pane.h) - 2 {
      for c in 0 ..< 3 { out.append(px[(row * 400 + x) * 4 + c]) }
    }
    return out
  }

  @Test("坏量（NaN / ±inf）那根不画柱子：和量为 0 的那根一模一样，邻居照画")
  func nonFiniteVolumeDrawsNoBar() {
    let zero = ChartRenderer(state: Self.state(volumeAtK: 0))
    let full = ChartRenderer(state: Self.state(volumeAtK: 100))
    let zeroCol = Self.column(Self.pixels(zero), zero)
    // 探针确实落在柱子上：量正常时这一列和量为 0 时不一样。
    #expect(Self.column(Self.pixels(full), full) != zeroCol)
    for bad in [Double.nan, .infinity, -.infinity] {
      let r = ChartRenderer(state: Self.state(volumeAtK: bad))
      let px = Self.pixels(r)
      #expect(Self.column(px, r) == zeroCol, "量 = \(bad)")
      // 整张图的其它地方也不该被一根顶出视图的柱子刷过：主图顶上那一行同一列与量为 0 时一致。
      let layout = r.layout(size: Self.size)
      let x = Int(r.state.view.x(Double(r.state.series.time(at: Self.k)), plotW: layout.plotW).rounded())
      let zp = Self.pixels(zero)
      let row = Int(layout.main.y + 2)
      #expect((0 ..< 3).allSatisfy { px[(row * 400 + x) * 4 + $0] == zp[(row * 400 + x) * 4 + $0] }, "量 = \(bad)")
    }
  }
}
