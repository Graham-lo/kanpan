import CoreGraphics
import Foundation
import KanpanCore
import Testing
import UIKit
@testable import KanpanChart

/// 图上大单签接进渲染器（`ChartRenderer+BigTrades`）：并根、档位、躲画线字、命中、缓存、脏层、1m × 500 根的性能。
@MainActor
@Suite("大单签 · 图表")
struct BigTradeChartTests {
  static let size = CGSize(width: 402, height: 520)

  /// 1m × `count` 根；每根一分钟都有点小大单（撑分布），每 37 根来一笔巨买、每 53 根来一笔巨卖。
  static func renderer(count: Int = 500, interval: Interval = .m1, spacing: Double = AICoinBehavior.initialSpacing)
    -> ChartRenderer {
    let b = benchSeries(count: count, interval: interval, symbol: "SOLUSDT")
    let L = Layout(width: size.width, height: size.height, subs: [.vol])
    let st = ChartState(
      series: b, symbol: benchSymbol("SOLUSDT"),
      view: ViewMath.reset(series: b, plotW: L.plotW, spacing: spacing),
      price: .init(mode: .linear), subs: [.vol], timezone: .utc)
    var r = ChartRenderer(state: st)
    r.state.bigTrades = tape(b)
    return r
  }

  static func tape(_ b: BarSeries, floor: Double = 50_000) -> BigTradeTape {
    var m: [Int64] = [], buy: [Double] = [], sell: [Double] = []
    for i in 0..<b.count {
      m.append(b.time(at: i))
      var bb = 60_000 + Double(i % 7) * 20_000, ss = 50_000 + Double(i % 5) * 25_000
      if i % 37 == 0 { bb = 3_300_000 }
      if i % 53 == 0 { ss = 2_400_000 }
      buy.append(bb); sell.append(ss)
    }
    return BigTradeTape(symbol: b.symbol, minutes: m, buy: buy, sell: sell, floor: floor,
                        lastBigMs: b.lastTime + 5_000, lastBigBuy: true)
  }

  func signs(_ r: ChartRenderer) -> [BigTradeSign] { r.bigTradeSigns(size: Self.size) }

  @Test("分钟账并成每根、按档出签：巨买挂最高价上方尖朝上，巨卖挂最低价下方，三档带胶囊")
  func signsFollowTape() throws {
    let r = Self.renderer()
    let all = signs(r)
    #expect(!all.isEmpty)
    let L = r.layout(size: Self.size), range = r.priceRange(size: Self.size), b = r.state.series
    let top = try #require(all.max { $0.usd < $1.usd })
    #expect(top.tier == 3)
    #expect(top.usd == 3_300_000)
    #expect(top.buy)
    for s in all {
      #expect(Set(all.map(\.index)).count == all.count, "一根只一枚")
      let hy = KanpanCore.yOf(b.high[s.index], pane: L.main, range: range, mode: r.state.effectivePriceMode)
      let ly = KanpanCore.yOf(b.low[s.index], pane: L.main, range: range, mode: r.state.effectivePriceMode)
      if s.markAbove { #expect(Double(s.markRect.maxY) <= hy + 0.01) } else { #expect(Double(s.markRect.minY) >= ly - 0.01) }
      #expect(Double(s.bounds.minY) >= L.main.y + ChartRenderer.bigTradeLegendBand - 0.01, "签不进图例那一带")
      #expect(Double(s.bounds.maxY) <= L.main.y + L.main.h + 0.01)
      #expect(s.bounds.minX >= -0.01 && Double(s.bounds.maxX) <= L.plotW + 0.01 || s.capsule == nil)
    }
    #expect(all.contains { $0.capsule != nil && $0.text == "3.3M" })
  }

  @Test("秒线、比价、没有分钟账都不出签")
  func inactiveCases() {
    var r = Self.renderer()
    r.state.bigTrades = nil
    #expect(signs(r).isEmpty)
    var p = Self.renderer()
    p.state.percentAxis = true
    #expect(signs(p).isEmpty)
    let b = benchSeries(count: 200, interval: .m1, symbol: "SOLUSDT")
    let sec = BarSeries(symbol: b.symbol, interval: .m1, t0: b.t0, step: 1_000, open: b.open, high: b.high,
                        low: b.low, close: b.close, volume: b.volume)
    var q = Self.renderer()
    q.state.series = sec
    q.state.bigTrades = Self.tape(sec)
    #expect(signs(q).isEmpty)
  }

  @Test("画线交叉：水平线 / 趋势线 / 斐波那契的字横扫整块主图，签与画线文字零相交")
  func zeroIntersectionsWithDrawingText() throws {
    var r = Self.renderer()
    let L = r.layout(size: Self.size)
    let b = r.state.series
    let lo = b.low.suffix(200).min()!, hi = b.high.suffix(200).max()!
    var total = 0, hits = 0, withBoxes = 0
    for k in 0..<24 {
      let p = lo + (hi - lo) * Double(k) / 23
      let t = Double(b.time(at: b.count - 1 - (k * 7) % 120))
      r.state.drawings = [
        Drawing(id: "h\(k)", kind: .hline, a: DrawPoint(t: t, p: p)),
        Drawing(id: "t\(k)", kind: .trend, a: DrawPoint(t: Double(b.time(at: b.count - 80)), p: p),
                b: DrawPoint(t: Double(b.time(at: b.count - 10)), p: hi - (p - lo))),
        Drawing(id: "f\(k)", kind: .fibonacci, a: DrawPoint(t: Double(b.time(at: b.count - 60)), p: lo),
                b: DrawPoint(t: Double(b.time(at: b.count - 20)), p: p)),
      ]
      let boxes = r.drawingLabelBoxes(pane: L.main, range: r.priceRange(size: Self.size), L: L)
      // 斐波那契两端同价（k = 0）等退化情形本来就不出字；只要大多数位置有字可躲。
      if !boxes.isEmpty { withBoxes += 1 }
      for s in signs(r) {
        total += 1
        // 画出来的只有记号与胶囊两块（胶囊为让开邻根可以离三角远一点，中间是空的），逐块查。
        let drawn = [s.markRect] + (s.capsule.map { [$0] } ?? [])
        for box in boxes where drawn.contains(where: { $0.intersects(box) }) { hits += 1 }
      }
    }
    #expect(withBoxes >= 20)
    #expect(total > 0)
    #expect(hits == 0, "签与画线文字相交 \(hits) 次")
  }

  @Test("命中：签中心点得中、取最近；空白处不中")
  func hitTest() throws {
    let r = Self.renderer()
    let s = try #require(signs(r).first { $0.tier == 3 })
    #expect(r.bigTradeHit(at: s.markCenter, size: Self.size)?.index == s.index)
    #expect(r.bigTradeHit(at: CGPoint(x: 2, y: 30), size: Self.size) == nil)
    #expect(r.bigTradeAccessibilityLabel(s).hasPrefix("买方大单 3.3M，"))
    #expect(r.bigTradeAccessibilityLabel(s).hasSuffix("这根"))
  }

  @Test("缓存：拖图不重并根；分钟账换了才重算；十字线动不换摆好的签")
  func caching() {
    var r = Self.renderer()
    _ = signs(r)
    let n = r.bigTradeBarsCache.computed
    r.state.view = r.state.view.shifted(byPx: -30, plotW: r.layout(size: Self.size).plotW)
    _ = signs(r)
    #expect(r.bigTradeBarsCache.computed == n)
    let box = r.bigTradeSignCache
    r.state.crosshair = Crosshair(index: 10)
    #expect(r.bigTradeSignCache === box)
    var t = r.state.bigTrades!
    t.buy[t.buy.count - 1] = 9_000_000
    r.state.bigTrades = t
    #expect(r.bigTradeSignCache !== box)
    _ = signs(r)
    #expect(r.bigTradeBarsCache.computed == n + 1)
  }

  @Test("分钟账换了只脏底图")
  func dirtyParts() {
    let r = Self.renderer()
    var next = r.state
    next.bigTrades?.buy[0] = 1
    let parts = ChartView.changed(from: r.state, to: next)
    #expect(parts == .plot)
  }

  @Test("档位按最近 300 根：老根的巨额不把新根的档位抬上去")
  func tiersUseRecentBars() throws {
    var r = Self.renderer(count: 800)
    var t = r.state.bigTrades!
    t.buy[0] = 900_000_000
    r.state.bigTrades = t
    let k = try #require(r.bigTradeBars()?.tiers)
    #expect(k.t3 < 10_000_000)
  }
}

/// 1m × 500 根：开着签比关着签，底图一帧 p95 多出不超过 1 ms（每帧都挪一点视野，签每帧重摆）。
@MainActor
@Suite("大单签 · 性能", .serialized)
struct BigTradePerfTests {
  @Test("1m × 500 根 p95 ≤ +1ms")
  func plotFrameBudget() {
    let size = BigTradeChartTests.size
    let base = BigTradeChartTests.renderer(count: 500, spacing: 3)
    var on = base, off = base
    off.state.bigTrades = nil
    let fmt = UIGraphicsImageRendererFormat()
    fmt.scale = 3
    let canvas = UIGraphicsImageRenderer(size: size, format: fmt)
    let plotW = base.layout(size: size).plotW
    var a: [Double] = [], b: [Double] = []
    let clock = ContinuousClock()
    for i in 0..<80 {
      let dx = Double(i % 2 == 0 ? 1 : -1)
      on.state.view = on.state.view.shifted(byPx: dx, plotW: plotW)
      off.state.view = off.state.view.shifted(byPx: dx, plotW: plotW)
      _ = canvas.image { c in
        let t0 = clock.now
        off.drawPlot(in: c.cgContext, size: size, scale: 3)
        let t1 = clock.now
        on.drawPlot(in: c.cgContext, size: size, scale: 3)
        let t2 = clock.now
        if i >= 10 { b.append(benchMs(t1 - t0)); a.append(benchMs(t2 - t1)) }
      }
    }
    func p95(_ xs: [Double]) -> Double { let s = xs.sorted(); return s[min(s.count - 1, Int(Double(s.count) * 0.95))] }
    benchPrint("bigTradeSigns.on", n: 500, a)
    benchPrint("bigTradeSigns.off", n: 500, b)
    print(String(format: "BENCH bigTradeSigns p95 on=%.3f off=%.3f", p95(a), p95(b)))
    #expect(!on.bigTradeSigns(size: size).isEmpty)
    #expect(p95(a) - p95(b) <= 1.0, "p95 多了 \(p95(a) - p95(b)) ms")
  }
}
