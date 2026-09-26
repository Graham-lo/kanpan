import CoreGraphics
import Foundation
import KanpanCore
import UIKit
import XCTest

@testable import KanpanChart

// MARK: - 整机压测 · 图表极限数据（2026-09-26）
//
// 一屏里同时堆满用户能堆出来的东西：6000 根（币安补缺上限）+ 主图 MA 四条 + 三个副图
// （VOL / MACD / RSI）+ 画线 + 主力订单流几十单。画线分两档：
//
// - `full`：每品种上限 `DrawArchive.perSymbolLimit` 条，混着全部 41 种工具，三把计算型
//   （锚定 VWAP、固定 / 锚定成交量分布）锚在最早那根——要把整段 6000 根扫一遍。
// - `hostile`：300 条（上限之外的东西只能从同步 / 分享收件箱进来，量的是渲染本身扛不扛得住）。
//
// 只打 `BENCH` 行，不做墙钟断言（计时在模拟器上抖得厉害）；结构性的判据另有单测。
@MainActor
final class StressExtremeBenchTests: XCTestCase {
  static let size = CGSize(width: 393, height: 620)
  static let scale: CGFloat = 3
  static let bars = 6000

  static func drawings(count: Int, series: BarSeries, seed: UInt64 = 7) -> [Drawing] {
    var r = BenchRNG(seed: seed)
    let kinds = Drawing.Kind.allCases
    let t0 = Double(series.firstTime), t1 = Double(series.time(at: series.count - 1))
    let lo = series.low.min()!, hi = series.high.max()!
    var out: [Drawing] = []
    for i in 0..<count {
      let kind = kinds[i % kinds.count]
      var pts: [DrawPoint] = []
      for k in 0..<max(1, kind.pointCount) {
        // 计算型锚在最早那根：最坏情况，每帧都要把整段扫一遍。
        let t = kind.isComputed && k == 0 ? t0 : r.range(t0 + (t1 - t0) * 0.6, t1)
        pts.append(DrawPoint(t: t, p: r.range(lo, hi)))
      }
      var d = Drawing(id: "stress-\(i)", kind: kind, points: pts)
      if kind.usesText { d.text = "压测 \(i)" }
      out.append(d)
    }
    return out
  }

  static func orders(series: BarSeries, count: Int = 60) -> [BigOrder] {
    var r = BenchRNG(seed: 11)
    let price = series.close.last!
    let products: [OrderFlowProduct] = [.spot, .usdtPerp, .coinPerp, .delivery]
    let statuses: [BigOrder.Status] = [.live, .live, .live, .filled, .cancelled]
    return (0..<count).map { i in
      let side: BookSide = i % 2 == 0 ? .bid : .ask
      let off = price * r.range(0.0005, 0.03)
      let seen = series.time(at: series.count - 1 - Int(r.range(5, 400))) + 1
      let status = statuses[i % statuses.count]
      let end: Int64? = status == .live ? nil : seen + 60_000 * Int64(r.range(2, 60))
      let n = r.range(1_000_000, 40_000_000)
      return BigOrder(venueID: "binance:\(products[i % 4].rawValue):\(i)", exchange: "币安",
                      product: products[i % 4], side: side, bucket: Int64(i),
                      price: side == .bid ? price - off : price + off, firstSeenMs: seen, endMs: end,
                      status: status, initialNotional: n, notional: n,
                      filledNotional: status == .filled ? n : 0, threshold: 1_000_000)
    }
  }

  static func state(drawings count: Int, dark: Bool = false, hidden: Bool = false,
                    only kinds: [Drawing.Kind]? = nil) -> ChartState {
    let series = benchSeries(count: bars, interval: .m1)
    let subs: [IndicatorID] = [.vol, .macd, .rsi]
    let layout = Layout(width: Double(size.width), height: Double(size.height), subs: subs)
    let view = ViewMath.reset(series: series, plotW: layout.plotW, spacing: AICoinBehavior.initialSpacing)
    var s = ChartState(series: series, symbol: benchSymbol(), view: view, dark: dark,
                       overlays: [.ma], subs: subs, params: IndicatorID.factoryParams)
    var ds = drawings(count: count, series: series)
    if let kinds {
      ds = ds.enumerated().map { i, d in
        var e = Drawing(id: d.id, kind: kinds[i % kinds.count],
                        points: [DrawPoint(t: Double(series.firstTime), p: d.a.p),
                                 DrawPoint(t: Double(series.time(at: series.count - 1)), p: d.a.p)])
        e.hidden = d.hidden
        return e
      }
    }
    if hidden { for i in ds.indices { ds[i].hidden = true } }
    s.drawings = ds
    s.orderFlow = OrderFlowSnapshot(symbol: s.symbol.symbol, phase: .ready, orders: orders(series: series),
                                    asOfMs: series.time(at: series.count - 1) + 30_000)
    return s
  }

  private func frame(_ r: ChartRenderer, _ ctx: CGContext) {
    ctx.saveGState(); r.drawPlot(in: ctx, size: Self.size, scale: Self.scale); ctx.restoreGState()
    ctx.saveGState(); r.drawLive(in: ctx, size: Self.size, scale: Self.scale); ctx.restoreGState()
    ctx.saveGState(); r.drawCross(in: ctx, size: Self.size, scale: Self.scale); ctx.restoreGState()
  }

  /// 一帧底图（plot 层）的成本：tick 与拖动每一帧都要重画它。
  func testPlotLayerExtreme() {
    let computed: [Drawing.Kind] = [.anchoredVWAP, .fixedVolumeProfile, .anchoredVolumeProfile]
    let plain = Drawing.Kind.allCases.filter { !$0.isComputed }
    let cases: [(String, Int, Bool, [Drawing.Kind]?)] = [
      ("none", 0, false, nil), ("full", DrawArchive.perSymbolLimit, false, nil),
      ("full_hidden", DrawArchive.perSymbolLimit, true, nil), ("own_plus_guest", 100, false, nil),
      ("hostile", 300, false, nil), ("plain_100", 100, false, plain),
      ("computed_6", 6, false, computed), ("computed_6_hidden", 6, true, computed),
      ("computed_30", 30, false, computed),
    ]
    for (name, count, hidden, kinds) in cases {
      let r = ChartRenderer(state: Self.state(drawings: count, hidden: hidden, only: kinds))
      let ctx = benchContext(size: Self.size, scale: Self.scale)
      let samples = benchRun(rounds: 20) { _ in
        ctx.saveGState(); r.drawPlot(in: ctx, size: Self.size, scale: Self.scale); ctx.restoreGState()
      }
      benchPrint("stress.plot.\(name)", n: Self.bars, samples)
    }
  }

  /// 末根每跳一口：recalc + 三层重画。
  func testTickExtreme() {
    for (name, count) in [("full", DrawArchive.perSymbolLimit), ("hostile", 300)] {
      let base = Self.state(drawings: count)
      var renderer = ChartRenderer(state: base)
      let ctx = benchContext(size: Self.size, scale: Self.scale)
      frame(renderer, ctx)
      let last = base.series.bar(at: base.series.count - 1)
      var next = base
      let samples = benchRun(rounds: 20) { i in
        var series = base.series
        let c = last.close * (1 + 0.0001 * Double(i % 7 - 3))
        _ = series.upsert(Bar(openTime: last.openTime, open: last.open, high: max(last.high, c),
                              low: min(last.low, c), close: c, volume: last.volume + Double(i + 5)))
        next.series = series
        renderer.state = next
        frame(renderer, ctx)
      }
      benchPrint("stress.tick.\(name)", n: Self.bars, samples)
    }
  }

  /// 拖动一帧：视野挪一根。
  func testDragExtreme() {
    for (name, count) in [("full", DrawArchive.perSymbolLimit), ("hostile", 300)] {
      let base = Self.state(drawings: count)
      var renderer = ChartRenderer(state: base)
      let ctx = benchContext(size: Self.size, scale: Self.scale)
      frame(renderer, ctx)
      var next = base
      let step = Double(base.series.step)
      let samples = benchRun(rounds: 20) { i in
        next.view = ViewWindow(to: base.view.to - step * Double(i + 40), span: base.view.span)
        renderer.state = next
        frame(renderer, ctx)
      }
      benchPrint("stress.drag.\(name)", n: Self.bars, samples)
    }
  }

  /// 捏到最远（`AICoinBehavior.minimumSpacing`，用户手指能到的极限）。
  func testZoomedOutExtreme() {
    var s = Self.state(drawings: DrawArchive.perSymbolLimit)
    let plotW = Layout(width: Double(Self.size.width), height: Double(Self.size.height), subs: s.subs).plotW
    s.view = ViewMath.reset(series: s.series, plotW: plotW, spacing: AICoinBehavior.minimumSpacing)
    let r = ChartRenderer(state: s)
    let ctx = benchContext(size: Self.size, scale: Self.scale)
    let samples = benchRun(rounds: 20) { _ in frame(r, ctx) }
    benchPrint("stress.zoomed_out.full", n: Self.bars, samples)
  }
}
