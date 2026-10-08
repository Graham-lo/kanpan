import CoreGraphics
import Foundation
import KanpanCore
import Testing
import UIKit
@testable import KanpanChart

/// 图上大单与爆仓气泡接进渲染器（`ChartRenderer+BigTrades`）：大单 + 爆仓并成每根向上 / 向下、两级门槛、
/// 一屏 6 枚泡、躲画线字、命中只认泡、缓存、脏层、1m × 500 根的性能。
@MainActor
@Suite("大单与爆仓气泡 · 图表")
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

  /// 一本爆仓账：`rows` = [(第几根, 多单爆仓, 空单爆仓)]，落在那根开盘那一分钟。
  static func book(_ b: BarSeries, _ rows: [(Int, Double, Double)]) -> LiquidationBook {
    var book = LiquidationBook(base: "SOL")
    book.merge(LiquidationPage(tracked: true, rows: rows.map {
      LiquidationRow(minuteMs: b.time(at: $0.0), longUsd: $0.1, shortUsd: $0.2, count: 1)
    }), nowMs: b.lastTime + 60_000)
    return book
  }

  func bubbles(_ r: ChartRenderer) -> [BigTradeBubble] { r.bigTradeBubbles(size: Self.size) }

  @Test("分钟账并成每根：巨买成泡挂最高价之上、巨卖挂最低价之下；一屏至多 6 枚泡，一根上下各至多一枚")
  func bubblesFollowTape() throws {
    let r = Self.renderer()
    let all = bubbles(r)
    #expect(!all.isEmpty)
    let L = r.layout(size: Self.size), range = r.priceRange(size: Self.size), b = r.state.series
    let mode = r.state.effectivePriceMode
    let pops = all.filter(\.isBubble)
    #expect(!pops.isEmpty && pops.count <= BigTradeBubbles.maxBubbles)
    #expect(all.contains { !$0.isBubble }, "过点线没过泡线的画成点")
    let top = try #require(all.max { $0.usd < $1.usd })
    #expect(top.isBubble && top.up && top.usd == 3_300_000 && top.text == "3.3")
    #expect(Set(all.map { "\($0.index)\($0.up)" }).count == all.count, "一根上下各至多一枚")
    for s in all {
      let hy = KanpanCore.yOf(b.high[s.index], pane: L.main, range: range, mode: mode)
      let ly = KanpanCore.yOf(b.low[s.index], pane: L.main, range: range, mode: mode)
      if s.up { #expect(Double(s.bounds.maxY) <= hy + 0.01) } else { #expect(Double(s.bounds.minY) >= ly - 0.01) }
      #expect(Double(s.bounds.minY) >= L.main.y + ChartRenderer.bigTradeLegendBand - 0.01, "不进图例那一带")
      #expect(Double(s.bounds.maxY) <= L.main.y + L.main.h + 0.01)
      if s.isBubble { #expect(s.bounds.minX >= -0.01 && Double(s.bounds.maxX) <= L.plotW + 0.01, "泡整圆在主图里") }
    }
  }

  @Test("爆仓并进同一枚：空单爆仓算向上、多单爆仓算向下；不带爆仓时向上 / 向下就是大买 / 大卖")
  func liquidationsMergeIntoSides() throws {
    var r = Self.renderer()
    let b = r.state.series
    let plain = try #require(r.bigTradeBars())
    // 挑最近 60 根里上方 / 下方空间最大的两根（最高价最低、最低价最高），泡不会因为顶到窗格边退成点。
    let recent = Array((b.count - 60)..<b.count)
    let i = recent.min { b.high[$0] < b.high[$1] }!
    let j = recent.filter { $0 != i }.max { b.low[$0] < b.low[$1] }!
    #expect(plain.up[i] == r.state.bigTrades!.buy[i])
    #expect(plain.down[j] == r.state.bigTrades!.sell[j])
    var t = r.state.bigTrades!
    t.setLiquidations(Self.book(b, [(i, 0, 7_000_000), (j, 6_000_000, 0)]))
    r.state.bigTrades = t
    let merged = try #require(r.bigTradeBars())
    #expect(merged.up[i] == plain.up[i] + 7_000_000)
    #expect(merged.down[i] == plain.down[i])
    #expect(merged.down[j] == plain.down[j] + 6_000_000)
    #expect(merged.up[j] == plain.up[j])
    let all = bubbles(r)
    let up = try #require(all.first { $0.index == i && $0.up })
    #expect(up.isBubble && up.usd == plain.up[i] + 7_000_000)
    #expect(all.contains { $0.index == j && !$0.up && $0.isBubble })
  }

  @Test("只有爆仓、没有大单也出（永续刚打开、大单账还空着时）")
  func liquidationOnly() {
    var r = Self.renderer()
    let b = r.state.series
    var t = BigTradeTape(symbol: b.symbol, minutes: [], buy: [], sell: [], floor: 50_000, lastBigMs: nil, lastBigBuy: true)
    t.setLiquidations(Self.book(b, (0..<40).map { (b.count - 1 - $0 * 3, Double(490_000 - $0 * 10_000), 0) }))
    r.state.bigTrades = t
    let all = bubbles(r)
    #expect(!all.isEmpty)
    #expect(all.allSatisfy { !$0.up }, "多单爆仓只在下侧")
  }

  @Test("秒线、比价、没有分钟账都不出")
  func inactiveCases() {
    var r = Self.renderer()
    r.state.bigTrades = nil
    #expect(bubbles(r).isEmpty)
    var p = Self.renderer()
    p.state.percentAxis = true
    #expect(bubbles(p).isEmpty)
    let b = benchSeries(count: 200, interval: .m1, symbol: "SOLUSDT")
    let sec = BarSeries(symbol: b.symbol, interval: .m1, t0: b.t0, step: 1_000, open: b.open, high: b.high,
                        low: b.low, close: b.close, volume: b.volume)
    var q = Self.renderer()
    q.state.series = sec
    q.state.bigTrades = Self.tape(sec)
    #expect(bubbles(q).isEmpty)
    var e = Self.renderer()
    e.state.bigTrades = BigTradeTape(symbol: "SOLUSDT", minutes: [], buy: [], sell: [], floor: 1, lastBigMs: nil,
                                     lastBigBuy: true)
    #expect(bubbles(e).isEmpty)
  }

  @Test("画线交叉：水平线 / 趋势线 / 斐波那契的字横扫整块主图，点与泡和画线文字零相交")
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
      if !boxes.isEmpty { withBoxes += 1 }
      for s in bubbles(r) {
        total += 1
        for box in boxes where s.bounds.intersects(box) { hits += 1 }
      }
    }
    #expect(withBoxes >= 20)
    #expect(total > 0)
    #expect(hits == 0, "点 / 泡与画线文字相交 \(hits) 次")
  }

  @Test("命中：泡中心点得中；小圆点与空白处不中；读屏「时间 向上 金额」")
  func hitTest() throws {
    let r = Self.renderer()
    let all = bubbles(r)
    let s = try #require(all.first { $0.isBubble && $0.usd == 3_300_000 })
    let hit = try #require(r.bigTradeHit(at: s.center, size: Self.size))
    #expect(hit.index == s.index && hit.up == s.up)
    let pops = all.filter(\.isBubble)
    // 离所有泡都远于热区的小圆点点了不中。
    if let dot = all.first(where: { d in !d.isBubble && pops.allSatisfy { abs($0.center.x - d.center.x) > 30 || abs($0.center.y - d.center.y) > 30 } }) {
      #expect(r.bigTradeHit(at: dot.center, size: Self.size) == nil)
    }
    #expect(r.bigTradeHit(at: CGPoint(x: 2, y: 30), size: Self.size) == nil)
    #expect(r.bigTradeAccessibilityLabel(s).hasSuffix(" 向上 3.3M"))
  }

  @Test("缓存：拖图不重并根；分钟账换了才重算；十字线动不换摆好的点与泡")
  func caching() {
    var r = Self.renderer()
    _ = bubbles(r)
    let n = r.bigTradeBarsCache.computed
    r.state.view = r.state.view.shifted(byPx: -30, plotW: r.layout(size: Self.size).plotW)
    _ = bubbles(r)
    #expect(r.bigTradeBarsCache.computed == n)
    let box = r.bigTradeBubbleCache
    r.state.crosshair = Crosshair(index: 10)
    #expect(r.bigTradeBubbleCache === box)
    var t = r.state.bigTrades!
    t.buy[t.buy.count - 1] = 9_000_000
    r.state.bigTrades = t
    #expect(r.bigTradeBubbleCache !== box)
    _ = bubbles(r)
    #expect(r.bigTradeBarsCache.computed == n + 1)
    // 换一本爆仓账也重算。
    t.setLiquidations(Self.book(r.state.series, [(r.state.series.count - 2, 0, 5_000_000)]))
    r.state.bigTrades = t
    _ = bubbles(r)
    #expect(r.bigTradeBarsCache.computed == n + 2)
  }

  @Test("底图画出来的枚数就是摆好的枚数")
  func drawCountsMatch() {
    let r = Self.renderer()
    let L = r.layout(size: Self.size)
    let range = r.priceRange(size: Self.size)
    let fmt = UIGraphicsImageRendererFormat()
    fmt.scale = 2
    var drawn = 0
    _ = UIGraphicsImageRenderer(size: Self.size, format: fmt).image { c in
      drawn = r.drawBigTrades(c.cgContext, pane: L.main, range: range, L: L)
    }
    #expect(drawn == bubbles(r).count)
    #expect(drawn > 0)
  }

  @Test("分钟账换了只脏底图")
  func dirtyParts() {
    let r = Self.renderer()
    var next = r.state
    next.bigTrades?.buy[0] = 1
    #expect(ChartView.changed(from: r.state, to: next) == .plot)
    var liq = r.state
    liq.bigTrades?.setLiquidations(Self.book(r.state.series, [(3, 1, 1)]))
    #expect(ChartView.changed(from: r.state, to: liq) == .plot)
  }

  @Test("门槛按最近 300 根：老根的巨额不把新根的泡线抬上去")
  func tiersUseRecentBars() throws {
    var r = Self.renderer(count: 800)
    var t = r.state.bigTrades!
    t.buy[0] = 900_000_000
    r.state.bigTrades = t
    let k = try #require(r.bigTradeBars()?.tiers)
    #expect(k.bubble < 10_000_000)
    #expect(k.dot <= k.bubble)
  }
}

/// 1m × 500 根：开着气泡比关着，底图一帧 p95 多出不超过 1 ms（每帧都挪一点视野，点与泡每帧重摆）。
@MainActor
@Suite("大单与爆仓气泡 · 性能", .serialized)
struct BigTradePerfTests {
  @Test("1m × 500 根 p95 ≤ +1ms")
  func plotFrameBudget() {
    let size = BigTradeChartTests.size
    var base = BigTradeChartTests.renderer(count: 500, spacing: 3)
    var t = base.state.bigTrades!
    let b = base.state.series
    t.setLiquidations(BigTradeChartTests.book(b, (0..<120).map { (b.count - 1 - $0 * 4, Double($0 % 3) * 200_000, Double($0 % 4) * 150_000) }))
    base.state.bigTrades = t
    var on = base, off = base
    off.state.bigTrades = nil
    let fmt = UIGraphicsImageRendererFormat()
    fmt.scale = 3
    let canvas = UIGraphicsImageRenderer(size: size, format: fmt)
    let plotW = base.layout(size: size).plotW
    var a: [Double] = [], c: [Double] = []
    let clock = ContinuousClock()
    for i in 0..<80 {
      let dx = Double(i % 2 == 0 ? 1 : -1)
      on.state.view = on.state.view.shifted(byPx: dx, plotW: plotW)
      off.state.view = off.state.view.shifted(byPx: dx, plotW: plotW)
      _ = canvas.image { ctx in
        let t0 = clock.now
        off.drawPlot(in: ctx.cgContext, size: size, scale: 3)
        let t1 = clock.now
        on.drawPlot(in: ctx.cgContext, size: size, scale: 3)
        let t2 = clock.now
        if i >= 10 { c.append(benchMs(t1 - t0)); a.append(benchMs(t2 - t1)) }
      }
    }
    func p95(_ xs: [Double]) -> Double { let s = xs.sorted(); return s[min(s.count - 1, Int(Double(s.count) * 0.95))] }
    benchPrint("bigTradeBubbles.on", n: 500, a)
    benchPrint("bigTradeBubbles.off", n: 500, c)
    print(String(format: "BENCH bigTradeBubbles p95 on=%.3f off=%.3f", p95(a), p95(c)))
    #expect(!on.bigTradeBubbles(size: size).isEmpty)
    #expect(p95(a) - p95(c) <= 1.0, "p95 多了 \(p95(a) - p95(c)) ms")
  }
}
