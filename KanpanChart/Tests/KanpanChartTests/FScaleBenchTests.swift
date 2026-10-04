import CoreGraphics
import Foundation
import KanpanCore
import UIKit
import XCTest

@testable import KanpanChart

/// 深度审查 F 线（2026-10-04）的图层拆账基准：总根数 1500 → 6000、订单流 60 → 2400 单（挤在最近 400 根
/// 或铺满全史）、两条对比、30 条画线，各自在不同视野、缩到最小间距时一帧图层要多久，以及一条 214 点
/// 折线一笔描完与拆笔描的对照。只出数不断言（断言在 `PolylinePenTests`）；默认跳过，
/// 要复测时 `SIMCTL_CHILD_KANPAN_FSCALE_BENCH=1 xcrun simctl spawn <设备> …/xctest -XCTest FScaleBenchTests/<用例> …`，
/// 一律 Release 包，Debug 量出来的数不作数。报告见 docs/acceptance/深度审查-2026-10-04/F-性能压测/报告.md。
@MainActor
final class FScaleBenchTests: XCTestCase {
  static let size = CGSize(width: 393, height: 620)

  override func setUpWithError() throws {
    // 环境门（`ReleaseTestRosterTests.skipGates` 名册上有它）：不许写成 `XCTSkipUnless`。
    guard ProcessInfo.processInfo.environment["KANPAN_FSCALE_BENCH"] == "1" else {
      throw XCTSkip("F 线拆账基准只出数不断言，设 KANPAN_FSCALE_BENCH=1 才跑（未执行，不等于通过）")
    }
  }

  func state(bars: Int, orders: Int, compare: Bool) -> ChartState {
    let series = benchSeries(count: bars, interval: .m1)
    let subs: [IndicatorID] = [.vol, .macd, .rsi]
    let layout = Layout(width: Double(Self.size.width), height: Double(Self.size.height), subs: subs)
    let view = ViewMath.reset(series: series, plotW: layout.plotW, spacing: AICoinBehavior.initialSpacing)
    var s = ChartState(series: series, symbol: benchSymbol(), view: view, dark: false,
                       overlays: [.ma], subs: subs, params: IndicatorID.factoryParams)
    // 画线只落在最近 300 根里（和 UI 热路径用例一样），计算型锚在 300 根前。
    var ds = StressExtremeBenchTests.drawings(count: 30, series: series)
    let t0 = Double(series.time(at: series.count - 300))
    for i in ds.indices where ds[i].kind.isComputed { ds[i].points[0].t = t0 }
    s.drawings = ds
    s.orderFlow = OrderFlowSnapshot(symbol: s.symbol.symbol, phase: .ready,
                                    orders: StressExtremeBenchTests.orders(series: series, count: orders),
                                    asOfMs: series.time(at: series.count - 1) + 30_000)
    if compare {
      s.compare = ["ETH", "SOL"].enumerated().map { k, name in
        CompareSeries(key: name, name: name, color: Hex(k == 0 ? "#3366FF" : "#FF8800"),
                      open: series.open.map { $0 * (1 + 0.01 * Double(k + 1)) },
                      close: series.close.map { $0 * (1 + 0.01 * Double(k + 1)) })
      }
    }
    return s
  }

  func testScaling() {
    for (bars, orders, compare) in [(1500, 60, false), (6000, 60, false), (1500, 2400, false), (6000, 2400, false),
                                    (1500, 2400, true), (6000, 2400, true)] {
      let base = state(bars: bars, orders: orders, compare: compare)
      var renderer = ChartRenderer(state: base)
      let ctx = benchContext(size: Self.size, scale: 3)
      var next = base
      let step = Double(base.series.step)
      let samples = benchRun(rounds: 30) { i in
        next.view = ViewWindow(to: base.view.to - step * Double(i + 40), span: base.view.span)
        renderer.state = next
        ctx.saveGState(); renderer.drawPlot(in: ctx, size: Self.size, scale: 3); ctx.restoreGState()
        ctx.saveGState(); renderer.drawLive(in: ctx, size: Self.size, scale: 3); ctx.restoreGState()
        ctx.saveGState(); renderer.drawCross(in: ctx, size: Self.size, scale: 3); ctx.restoreGState()
      }
      benchPrint("fscale.drag.bars\(bars).orders\(orders)\(compare ? ".cmp2" : "")", n: bars, samples)
    }
  }

  func testHot() {
    let orders = Int(ProcessInfo.processInfo.environment["F_ORDERS"] ?? "2400") ?? 2400
    let base = state(bars: 6000, orders: orders, compare: false)
    var renderer = ChartRenderer(state: base)
    let ctx = benchContext(size: Self.size, scale: 3)
    var next = base
    let step = Double(base.series.step)
    let samples = benchRun(rounds: 600) { i in
      next.view = ViewWindow(to: base.view.to - step * Double(i % 30 + 40), span: base.view.span)
      renderer.state = next
      ctx.saveGState(); renderer.drawPlot(in: ctx, size: Self.size, scale: 3); ctx.restoreGState()
      ctx.saveGState(); renderer.drawLive(in: ctx, size: Self.size, scale: 3); ctx.restoreGState()
      ctx.saveGState(); renderer.drawCross(in: ctx, size: Self.size, scale: 3); ctx.restoreGState()
    }
    benchPrint("fscale.hot.orders\(orders)", n: 6000, samples)
  }
  /// 订单铺满整段历史（像服务端几天的历史）：首见在任意一根、价在那根收盘价 ±3%、已结束的活 2–600 分钟。
  static func spreadOrders(series: BarSeries, count: Int) -> [BigOrder] {
    var r = BenchRNG(seed: 7)
    let products: [OrderFlowProduct] = [.spot, .usdtPerp, .coinPerp, .delivery]
    let statuses: [BigOrder.Status] = [.live, .filled, .cancelled, .cancelled, .cancelled]
    return (0..<count).map { i in
      let side: BookSide = i % 2 == 0 ? .bid : .ask
      let idx = series.count - 1 - Int(r.range(2, Double(series.count - 2)))
      let price = series.close[idx]
      let off = price * r.range(0.0005, 0.03)
      let seen = series.time(at: idx) + 1
      let status = statuses[i % statuses.count]
      let end: Int64? = status == .live ? nil : seen + 60_000 * Int64(r.range(2, 600))
      let n = r.range(1_000_000, 40_000_000)
      return BigOrder(venueID: "binance:\(products[i % 4].rawValue):\(i)", exchange: "币安",
                      product: products[i % 4], side: side, bucket: Int64(i),
                      price: side == .bid ? price - off : price + off, firstSeenMs: seen, endMs: end,
                      status: status, initialNotional: n, notional: n,
                      filledNotional: status == .filled ? n : 0, threshold: 1_000_000)
    }
  }

  func testLayers() {
    for (bars, orders, spread) in [(6000, 60, false), (6000, 2400, false), (6000, 2400, true)] {
      var base = state(bars: bars, orders: orders, compare: false)
      if spread {
        base.orderFlow = OrderFlowSnapshot(symbol: base.symbol.symbol, phase: .ready,
                                           orders: Self.spreadOrders(series: base.series, count: orders),
                                           asOfMs: base.series.time(at: base.series.count - 1) + 30_000)
      }
      for back in [40, 1500, 4500] {
        var renderer = ChartRenderer(state: base)
        let ctx = benchContext(size: Self.size, scale: 3)
        var next = base
        let step = Double(base.series.step)
        var tp: [Double] = [], tl: [Double] = [], tc: [Double] = []
        for i in 0..<33 {
          next.view = ViewWindow(to: base.view.to - step * Double(i + back), span: base.view.span)
          renderer.state = next
          let a = ContinuousClock.now
          ctx.saveGState(); renderer.drawPlot(in: ctx, size: Self.size, scale: 3); ctx.restoreGState()
          let b = ContinuousClock.now
          ctx.saveGState(); renderer.drawLive(in: ctx, size: Self.size, scale: 3); ctx.restoreGState()
          let c = ContinuousClock.now
          ctx.saveGState(); renderer.drawCross(in: ctx, size: Self.size, scale: 3); ctx.restoreGState()
          let d = ContinuousClock.now
          if i >= 3 { tp.append(benchMs(a.duration(to: b))); tl.append(benchMs(b.duration(to: c))); tc.append(benchMs(c.duration(to: d))) }
        }
        let L = renderer.layout(size: Self.size)
        let f = renderer.orderFlowFrame(pane: L.main, range: renderer.priceRange(size: Self.size), L: L)
        let roles = Dictionary(grouping: f.bands, by: { "\($0.role)" }).mapValues(\.count)
        let area = f.bands.filter { $0.role != .noise }.reduce(0.0) { $0 + Double($1.frame.width * $1.frame.height) }
          + f.noiseStrokes.reduce(0.0) { $0 + Double($1.frame.width * $1.frame.height) }
        print(String(format: "LAYERS bars=%d orders=%d spread=%d back=%d plot=%.2f live=%.2f cross=%.2f bands=%d strokes=%d labels=%d area=%.0f %@",
                     bars, orders, spread ? 1 : 0, back, benchMedian(tp), benchMedian(tl), benchMedian(tc),
                     f.bands.count, f.noiseStrokes.count, f.labels.count, area, roles.description))
      }
    }
  }
  func testSweep() {
    for drawings in [true, false] {
      var base = state(bars: 6000, orders: 0, compare: false)
      base.orderFlow = nil
      if !drawings { base.drawings = [] }
      for back in [40, 300, 600, 1000, 1500, 2000, 3000, 4500] {
        var renderer = ChartRenderer(state: base)
        let ctx = benchContext(size: Self.size, scale: 3)
        var next = base
        let step = Double(base.series.step)
        let tp = benchRun(rounds: 30) { i in
          next.view = ViewWindow(to: base.view.to - step * Double(abs(i) + back), span: base.view.span)
          renderer.state = next
          ctx.saveGState(); renderer.drawPlot(in: ctx, size: Self.size, scale: 3); ctx.restoreGState()
        }
        let r = renderer.priceRange(size: Self.size)
        print(String(format: "SWEEP drawings=%d back=%d plot=%.2f range=%@", drawings ? 1 : 0, back, benchMedian(tp), "\(r)"))
      }
    }
  }
  func testPerDrawing() {
    let full = state(bars: 6000, orders: 0, compare: false)
    let step = Double(full.series.step)
    let back = Int(ProcessInfo.processInfo.environment["F_BACK"] ?? "600") ?? 600
    func cost(_ ds: [Drawing]) -> Double {
      var base = full
      base.orderFlow = nil
      base.drawings = ds
      var renderer = ChartRenderer(state: base)
      let ctx = benchContext(size: Self.size, scale: 3)
      var next = base
      return benchMedian(benchRun(rounds: 15) { i in
        next.view = ViewWindow(to: base.view.to - step * Double(abs(i) + back), span: base.view.span)
        renderer.state = next
        ctx.saveGState(); renderer.drawPlot(in: ctx, size: Self.size, scale: 3); ctx.restoreGState()
      })
    }
    let zero = cost([])
    print(String(format: "PERDRAW back=%d none=%.2f all=%.2f", back, zero, cost(full.drawings)))
    var rows: [(Double, String)] = []
    for d in full.drawings {
      let c = cost([d]) - zero
      rows.append((c, "\(d.kind) pts=\(d.points.map { String(format: "(%.0f,%.0f)", ($0.t - Double(full.series.firstTime)) / step, $0.p) })"))
    }
    for (c, name) in rows.sorted(by: { $0.0 > $1.0 }).prefix(12) { print(String(format: "PERDRAW %.2f %@", c, name)) }
  }
  func testZoomedOutParts() {
    let mode = ProcessInfo.processInfo.environment["F_ZOOM_LOOP"]
    for (name, drawings, orders, compare) in [("bare", false, 0, false), ("cmp2", false, 0, true), ("of2400", false, 2400, false),
                                              ("draw30", true, 0, false), ("all", true, 2400, true)] {
      if let mode, mode != name { continue }
      var base = state(bars: 6000, orders: max(orders, 1), compare: compare)
      if orders == 0 { base.orderFlow = nil }
      if !drawings { base.drawings = [] }
      let plotW = Layout(width: Double(Self.size.width), height: Double(Self.size.height), subs: base.subs).plotW
      base.view = ViewMath.reset(series: base.series, plotW: plotW, spacing: AICoinBehavior.minimumSpacing)
      var renderer = ChartRenderer(state: base)
      let ctx = benchContext(size: Self.size, scale: 3)
      var next = base
      let step = Double(base.series.step)
      var tp: [Double] = [], tl: [Double] = [], tc: [Double] = []
      let rounds = mode == nil ? 33 : 1500
      for i in 0..<rounds {
        next.view = ViewWindow(to: base.view.to - step * Double(i % 30), span: base.view.span)
        renderer.state = next
        let a = ContinuousClock.now
        ctx.saveGState(); renderer.drawPlot(in: ctx, size: Self.size, scale: 3); ctx.restoreGState()
        let b = ContinuousClock.now
        ctx.saveGState(); renderer.drawLive(in: ctx, size: Self.size, scale: 3); ctx.restoreGState()
        let c = ContinuousClock.now
        ctx.saveGState(); renderer.drawCross(in: ctx, size: Self.size, scale: 3); ctx.restoreGState()
        let d = ContinuousClock.now
        if i >= 3 { tp.append(benchMs(a.duration(to: b))); tl.append(benchMs(b.duration(to: c))); tc.append(benchMs(c.duration(to: d))) }
      }
      print(String(format: "ZOOMOUT %@ visibleBars=%.0f plot=%.2f live=%.2f cross=%.2f", name, base.view.span / step,
                   benchMedian(tp), benchMedian(tl), benchMedian(tc)))
    }
  }
  func testLineStroke() {
    var r = BenchRNG(seed: 3)
    let size = CGSize(width: 340, height: 90), s: CGFloat = 3
    var v = 50.0
    let pts: [CGPoint] = (0..<214).map { k in
      v = min(88, max(2, v + r.range(-12, 12)))
      return CGPoint(x: 2 + Double(k) * 1.57, y: v)
    }
    func ctx() -> CGContext { benchContext(size: size, scale: s) }
    let color = UIColor(red: 0.9, green: 0.6, blue: 0.1, alpha: 1).cgColor
    func chunked(_ n: Int, join: CGLineJoin) -> (CGContext) -> Void {
      { c in
        c.setStrokeColor(color); c.setLineWidth(2 / s); c.setLineJoin(join)
        var k = 0
        while k < pts.count - 1 {
          let e = min(pts.count, k + n + 1)
          c.beginPath(); c.addLines(between: Array(pts[max(0, k - 1)..<e])); c.strokePath()
          k = e - 1
        }
      }
    }
    func onePath(_ n: Int, join: CGLineJoin) -> (CGContext) -> Void {
      { c in
        c.setStrokeColor(color); c.setLineWidth(2 / s); c.setLineJoin(join)
        c.beginPath()
        var k = 0
        while k < pts.count - 1 {
          let e = min(pts.count, k + n + 1)
          c.addLines(between: Array(pts[max(0, k - 1)..<e]))
          k = e - 1
        }
        c.strokePath()
      }
    }
    func whole(_ join: CGLineJoin) -> (CGContext) -> Void {
      { c in c.setStrokeColor(color); c.setLineWidth(2 / s); c.setLineJoin(join); c.beginPath(); c.addLines(between: pts); c.strokePath() }
    }
    let joinName = ProcessInfo.processInfo.environment["F_JOIN"] ?? "miter"
    let join: CGLineJoin = joinName == "round" ? .round : .miter
    let variants: [(String, (CGContext) -> Void)] = [
      ("whole.\(joinName)", whole(join)),
      ("overlap4", chunked(4, join: join)), ("overlap8", chunked(8, join: join)),
      ("overlap16", chunked(16, join: join)), ("overlap32", chunked(32, join: join)),
      ("onePath32", onePath(32, join: join)),
      ("PolylinePen", { c in
        c.setLineWidth(2 / s); c.setLineJoin(join)
        var pen = PolylinePen(c, color: color, capacity: pts.count)
        for p in pts { pen.add(p) }
        pen.finish()
      }),
    ]
    var ref: [UInt8] = []
    for (name, draw) in variants {
      let c = ctx()
      let t = benchRun(rounds: 300, warmup: 20) { _ in draw(c) }
      let fresh = ctx(); draw(fresh)
      let w = fresh.width, h = fresh.height, bpr = fresh.bytesPerRow
      let p = fresh.data!.assumingMemoryBound(to: UInt8.self)
      let px = Array(UnsafeBufferPointer(start: p, count: bpr * h))
      if ref.isEmpty { ref = px }
      var diff = 0, maxd = 0
      for k in 0..<(bpr * h) { let d = abs(Int(px[k]) - Int(ref[k])); if d > 0 { diff += 1 }; maxd = max(maxd, d) }
      print(String(format: "LINE %@ median_us=%.1f p90_us=%.1f diffBytes=%d maxDiff=%d of %d", name, benchMedian(t) * 1000, benchP90(t) * 1000, diff, maxd, w * h * 4))
    }
  }
}
