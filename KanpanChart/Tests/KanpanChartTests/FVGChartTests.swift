import CoreGraphics
import Foundation
import KanpanCore
import Testing
import UIKit
@testable import KanpanChart

/// 公允价值缺口接进渲染器（`ChartRenderer+FVG`）：开关、对比态、缓存、盒子几何、确实画到了底图上。
@MainActor
@Suite("公允价值缺口 · 图表")
struct FVGChartTests {
  static let size = CGSize(width: 402, height: 520)

  /// 手造 70 根 15 分钟线：第 30–32 根留一个空头缺口 [97, 99.5]，第 60–62 根留一个多头缺口 [93.5, 94.5]，
  /// 中间与之后的 K 线都不碰它们，也不再生出别的缺口。末根（第 69 根）当作还在走。
  static func gapSeries() -> BarSeries {
    var rows: [(o: Double, h: Double, l: Double, c: Double)] = []
    for _ in 0...30 { rows.append((100, 100.5, 99.5, 100)) }
    rows.append((100, 100, 95, 95.5))      // 31：大跌
    rows.append((95.5, 97, 95, 96))        // 32：空头缺口 [97, 99.5]
    rows.append((96, 96, 94, 94.5))        // 33–35：慢慢走低，不留缺口
    rows.append((94.5, 95, 93, 93.5))
    rows.append((93.5, 94, 92.5, 93))
    for _ in 36...60 { rows.append((93, 93.5, 92.5, 93)) }
    rows.append((93, 95.2, 92.8, 95))      // 61：大涨
    rows.append((95, 95.8, 94.5, 95.5))    // 62：多头缺口 [93.5, 94.5]
    for _ in 63...69 { rows.append((95.3, 95.8, 94.8, 95.3)) }
    let t0: Int64 = 1_760_000_400_000
    let step = Interval.m15.stepMs
    let bars = rows.enumerated().map { i, r in
      Bar(openTime: t0 + Int64(i) * step, open: r.o, high: r.h, low: r.l, close: r.c, volume: 1)
    }
    return BarSeries(symbol: "BTCUSDT", interval: .m15, bars: bars)
  }

  static func renderer(on: Bool = true) -> ChartRenderer {
    let b = gapSeries()
    let L = Layout(width: size.width, height: size.height, subs: [.vol])
    var st = ChartState(
      series: b, symbol: benchSymbol("BTCUSDT"),
      view: ViewMath.reset(series: b, plotW: L.plotW, spacing: 5),
      price: .init(mode: .linear), overlays: [], subs: [.vol], timezone: .utc)
    if on { st.autoLayers = [.fvg] }
    return ChartRenderer(state: st)
  }

  static func draw(_ r: ChartRenderer) -> Int {
    let L = r.layout(size: size)
    let range = r.priceRange(size: size)
    let fmt = UIGraphicsImageRendererFormat()
    fmt.scale = 2
    var drawn = 0
    _ = UIGraphicsImageRenderer(size: size, format: fmt).image { c in
      drawn = r.drawFVG(c.cgContext, pane: L.main, range: range, L: L)
    }
    return drawn
  }

  @Test("开着：缓存里的缺口就是 fvgZones（末根在走不参与生成），一多一空都画出来")
  func zonesMatchCore() throws {
    let r = Self.renderer()
    let s = r.state.series
    #expect(r.state.closedBarCount == s.count - 1)
    let want = KanpanCore.fvgZones(series: s, closedCount: s.count - 1)
    #expect(want.map(\.side) == [.bear, .bull])
    #expect(Self.draw(r) == 2)
    #expect(r.fvgCache.zones == want)
    let bear = try #require(want.first), bull = try #require(want.last)
    #expect(bear.startMs == s.time(at: 31) && bear.top == 99.5 && bear.bottom == 97)
    #expect(bull.startMs == s.time(at: 61) && bull.top == 94.5 && bull.bottom == 93.5)
    // 末根算收线：整段参与生成，结果仍和核心同一个口径。
    var closed = r
    closed.state.lastBarLive = false
    #expect(closed.state.closedBarCount == s.count)
    #expect(closed.fvgCurrentZones() == KanpanCore.fvgZones(series: s, closedCount: s.count))
  }

  @Test("盒子从中间那根的左缘画到主图右缘；价位换算和 K 线同一套")
  func boxGeometry() throws {
    let r = Self.renderer()
    let L = r.layout(size: Self.size), range = r.priceRange(size: Self.size), s = r.state.series
    let items = r.fvgDiagnostics(size: Self.size)
    #expect(items.count == 2)
    let spacing = r.state.view.barSpacing(step: s.step, plotW: L.plotW)
    for item in items {
      let cx = r.state.view.x(Double(item.zone.startMs), plotW: L.plotW)
      #expect(abs(Double(item.box.minX) - max(0, cx - spacing / 2)) < 0.001)
      #expect(abs(Double(item.box.maxX) - L.plotW) < 0.001)
      let yTop = KanpanCore.yOf(item.zone.top, pane: L.main, range: range, mode: r.state.effectivePriceMode)
      let yBot = KanpanCore.yOf(item.zone.bottom, pane: L.main, range: range, mode: r.state.effectivePriceMode)
      #expect(abs(Double(item.box.minY) - min(yTop, yBot)) < 0.001)
      #expect(abs(Double(item.box.maxY) - max(yTop, yBot)) < 0.001)
    }
  }

  @Test("十字线、拖图不重算；来一笔 tick（戳换了）才重扫")
  func cacheKey() {
    var r = Self.renderer()
    _ = Self.draw(r)
    _ = Self.draw(r)
    #expect(r.fvgCache.computed == 1)
    r.state.crosshair = Crosshair(index: 40, price: 95)
    _ = Self.draw(r)
    r.state.view = ViewWindow(to: r.state.view.to - Double(r.state.series.step) * 3, span: r.state.view.span)
    _ = Self.draw(r)
    #expect(r.fvgCache.computed == 1)
    var s = r.state.series
    let last = s.bar(at: s.count - 1)
    s.replaceLast(with: Bar(openTime: last.openTime, open: last.open, high: last.high, low: last.low,
                            close: last.close + 0.1, volume: 2))
    r.state.series = s
    _ = Self.draw(r)
    #expect(r.fvgCache.computed == 2)
  }

  @Test("关着、对比态（百分比轴）一个都不算、不画")
  func offAndPercentAxis() {
    let off = Self.renderer(on: false)
    #expect(Self.draw(off) == 0)
    #expect(off.fvgCurrentZones().isEmpty)
    #expect(off.fvgCache.computed == 0 && off.fvgCache.key == nil)

    var percent = Self.renderer()
    percent.state.percentAxis = true
    #expect(Self.draw(percent) == 0)
    #expect(percent.fvgCurrentZones().isEmpty)
    #expect(percent.fvgCache.computed == 0)
  }

  @Test("不撑价格区间：开关前后主图区间一模一样")
  func priceRangeUnchanged() {
    let on = Self.renderer(), off = Self.renderer(on: false)
    #expect(on.priceRange(size: Self.size) == off.priceRange(size: Self.size))
  }

  @Test("整帧底图里确实画上了：盒子里右缘那一带的像素和关着时不一样")
  func paintedInFullFrame() throws {
    let on = Self.renderer(), off = Self.renderer(on: false)
    let box = try #require(on.fvgDiagnostics(size: Self.size).first { $0.zone.side == .bear }?.box)
    let probe = CGPoint(x: box.maxX - 3, y: box.midY)
    #expect(try Self.pixel(on, at: probe) != Self.pixel(off, at: probe))
  }

  static func pixel(_ r: ChartRenderer, at p: CGPoint) throws -> [UInt8] {
    let w = Int(size.width), h = Int(size.height)
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    try buf.withUnsafeMutableBytes { raw in
      let ctx = try #require(CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                       bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
      r.draw(in: ctx, size: size, scale: 1)
    }
    let i = (Int(p.y) * w + Int(p.x)) * 4
    return Array(buf[i..<(i + 4)])
  }
}
