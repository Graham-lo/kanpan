import CoreGraphics
import Foundation
import KanpanCore
import UIKit
import XCTest

import KanpanChart

// MARK: - 可重复的性能基准（绘制层）
//
// 这个文件**只用 public API**，不 `@testable`：同一份文件要能原样复制到改动后的
// 代码上再跑一次，所以只碰最高层入口（`ChartState` / `ChartRenderer` 的三层绘制）。
// 数据是固定种子的随机游走，跑多少次都一样；每条基准循环 ≥20 次取中位数与 p90，
// 用 `BENCH <name> median_ms=<x> p90_ms=<y> n=<bars>` 打到 stdout 方便 grep。

// ---------------------------------------------------------------- 合成数据

/// xorshift64；固定种子 → 固定序列，和机器、时间、并发顺序都无关。
struct BenchRNG {
  private var s: UInt64
  init(seed: UInt64) { s = seed &* 6_364_136_223_846_793_005 &+ 1442695040888963407 }
  mutating func next() -> UInt64 {
    s ^= s << 13; s ^= s >> 7; s ^= s << 17
    return s
  }
  /// [0, 1)
  mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
  mutating func range(_ a: Double, _ b: Double) -> Double { a + unit() * (b - a) }
}

/// 确定性随机游走 K 线。
func benchSeries(count: Int, interval: Interval = .h1, seed: UInt64 = 20260917,
                 symbol: String = "BENCHUSDT", t0: Int64 = 1_600_000_000_000) -> BarSeries {
  var r = BenchRNG(seed: seed)
  var o = [Double](), h = [Double](), l = [Double](), c = [Double](), v = [Double]()
  o.reserveCapacity(count); h.reserveCapacity(count); l.reserveCapacity(count)
  c.reserveCapacity(count); v.reserveCapacity(count)
  var px = 30_000.0
  for _ in 0..<count {
    let op = px
    px = max(1, px * (1 + r.range(-0.012, 0.012)))
    o.append(op); c.append(px)
    h.append(max(op, px) * (1 + r.range(0, 0.006)))
    l.append(min(op, px) * (1 - r.range(0, 0.006)))
    v.append(r.range(10, 5000))
  }
  return BarSeries(symbol: symbol, interval: interval, t0: t0,
                   open: o, high: h, low: l, close: c, volume: v)
}

func benchSymbol(_ symbol: String = "BENCHUSDT") -> SymbolInfo {
  SymbolInfo(symbol: symbol, base: "BENCH", quote: "USDT", pricePrecision: 2, tickSize: 0.01)
}

// ---------------------------------------------------------------- 计时

func benchMs(_ d: Duration) -> Double {
  Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
}

/// 中位数。
func benchMedian(_ xs: [Double]) -> Double {
  let s = xs.sorted()
  guard !s.isEmpty else { return .nan }
  return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

/// p90（向上取整的名次法）。
func benchP90(_ xs: [Double]) -> Double {
  let s = xs.sorted()
  guard !s.isEmpty else { return .nan }
  let k = max(1, Int((0.9 * Double(s.count)).rounded(.up)))
  return s[min(s.count - 1, k - 1)]
}

func benchPrint(_ name: String, n: Int, _ samples: [Double]) {
  print(String(format: "BENCH %@ median_ms=%.4f p90_ms=%.4f n=%d",
               name, benchMedian(samples), benchP90(samples), n))
}

/// 跑 `warmup` 次热身 + `rounds` 次计时，返回每次的毫秒数。
/// 结果落地口。Release 下算完没人用的话整段会被优化掉——指标基准把结果喂给
/// 这个 `@inline(never)` 的口子，量到的才是真算了一遍。绘制基准不需要，
/// 它们本来就往位图里写。
final class BenchSink: @unchecked Sendable {
  static let shared = BenchSink()
  var value = 0.0
}

@inline(never)
func benchKeep(_ r: IndicatorResult?) {
  guard let r else { return }
  var s = 0.0
  for line in r.lines { s += line.last ?? 0 }
  s += r.histogram?.last ?? 0
  BenchSink.shared.value += s
}

func benchRun(rounds: Int = 25, warmup: Int = 3, _ body: (Int) -> Void) -> [Double] {
  for i in 0..<warmup { body(-i - 1) }
  var out: [Double] = []
  out.reserveCapacity(rounds)
  for i in 0..<rounds {
    let t = ContinuousClock.now
    body(i)
    out.append(benchMs(t.duration(to: .now)))
  }
  return out
}

// ---------------------------------------------------------------- 画布

/// 一张和 `UIGraphicsImageRenderer` 同口径的离屏画布：坐标是 pt、原点左上、y 向下。
/// 建一次反复用——量的是绘制本身，不是每帧重新分配位图。
func benchContext(size: CGSize, scale: CGFloat) -> CGContext {
  let w = Int(size.width * scale), h = Int(size.height * scale)
  let ctx = CGContext(
    data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.translateBy(x: 0, y: CGFloat(h))
  ctx.scaleBy(x: scale, y: -scale)
  return ctx
}

@MainActor
final class PerfBenchmarkTests: XCTestCase {

  /// 取证机型之外单独定一档：393×700 @3x，和交接说明里的一致。
  static let frameSize = CGSize(width: 393, height: 700)
  static let frameScale: CGFloat = 3
  static let counts = [3000, 15000]

  /// 默认指标配置：主图 MA(10,30,120,256)，副图 VOL + MACD + RSI，对数轴。
  static let overlays: [IndicatorID] = [.ma]
  static let subs: [IndicatorID] = [.vol, .macd, .rsi]
  static let params: [IndicatorID: [Int]] = [
    .ma: IndicatorID.ma.defaultParams,
    .vol: IndicatorID.vol.defaultParams,
    .macd: IndicatorID.macd.defaultParams,
    .rsi: IndicatorID.rsi.defaultParams,
  ]

  static func state(count: Int) -> ChartState {
    let series = benchSeries(count: count)
    let layout = Layout(width: Double(frameSize.width), height: Double(frameSize.height), subs: subs)
    let view = ViewMath.reset(series: series, plotW: layout.plotW,
                             spacing: AICoinBehavior.initialSpacing)
    return ChartState(
      series: series, symbol: benchSymbol(), view: view,
      price: PriceTransform(mode: .log),
      overlays: overlays, subs: subs, params: params, timezone: .utc)
  }

  private func drawAllLayers(_ renderer: ChartRenderer, _ ctx: CGContext) {
    let size = Self.frameSize, scale = Self.frameScale
    ctx.saveGState(); renderer.drawPlot(in: ctx, size: size, scale: scale); ctx.restoreGState()
    ctx.saveGState(); renderer.drawLive(in: ctx, size: size, scale: scale); ctx.restoreGState()
    ctx.saveGState(); renderer.drawCross(in: ctx, size: size, scale: scale); ctx.restoreGState()
  }

  // -------------------------------------------------------------- 1. 整帧三层绘制

  func testFrameThreeLayers() {
    for n in Self.counts {
      let renderer = ChartRenderer(state: Self.state(count: n))
      let ctx = benchContext(size: Self.frameSize, scale: Self.frameScale)
      let samples = benchRun { _ in drawAllLayers(renderer, ctx) }
      benchPrint("chart.frame.three_layers", n: n, samples)
    }
  }

  // -------------------------------------------------------------- 2. 一次 tick 的完整成本

  /// 末根 close 改一下 → 赋回 `state` → 触发 recalc + 三层重画，量一次的耗时。
  func testTickFullCost() {
    for n in Self.counts {
      let state = Self.state(count: n)
      var renderer = ChartRenderer(state: state)
      let ctx = benchContext(size: Self.frameSize, scale: Self.frameScale)
      drawAllLayers(renderer, ctx)  // 先把缓存热起来

      var r = BenchRNG(seed: 99)
      // 每一轮要喂的新末根都先算好，计时区间里只剩 recalc + 重画。
      let base = state.series.bar(at: state.series.count - 1)
      var pending: [Bar] = []
      for _ in 0..<64 {
        let c = max(1, base.close * (1 + r.range(-0.004, 0.004)))
        pending.append(Bar(openTime: base.openTime, open: base.open,
                           high: max(base.high, c), low: min(base.low, c),
                           close: c, volume: base.volume + r.range(0, 30)))
      }
      var next = state
      let samples = benchRun(rounds: 30) { i in
        var series = state.series
        _ = series.upsert(pending[(i &+ 64) % pending.count])
        next.series = series
        renderer.state = next
        drawAllLayers(renderer, ctx)
      }
      benchPrint("chart.tick.recalc_redraw", n: n, samples)
    }
  }

  // -------------------------------------------------------------- 3. 一次拖动帧

  /// 改 transform（平移一根）→ recalc + 重画。
  func testDragFrame() {
    for n in Self.counts {
      let state = Self.state(count: n)
      var renderer = ChartRenderer(state: state)
      let ctx = benchContext(size: Self.frameSize, scale: Self.frameScale)
      drawAllLayers(renderer, ctx)

      let step = Double(state.series.step)
      var next = state
      let samples = benchRun(rounds: 30) { i in
        // 往历史方向一次挪一根；负的 i（热身）也是合法位移。
        next.view = ViewWindow(to: state.view.to - step * Double(i + 40), span: state.view.span)
        renderer.state = next
        drawAllLayers(renderer, ctx)
      }
      benchPrint("chart.drag.frame", n: n, samples)
    }
  }

  // -------------------------------------------------------------- 4. 指标全量重建

  /// 新建 `IndicatorEngine` 对 n 根算全部默认指标（主图 MA + 副图 VOL/MACD/RSI）。
  func testIndicatorFullRebuild() {
    for n in Self.counts {
      let series = benchSeries(count: n)
      let wanted = Self.overlays + Self.subs
      let samples = benchRun { _ in
        var engine = IndicatorEngine()
        engine.ensure(series: series, wanted: wanted, params: Self.params, dataKey: "bench")
        for id in wanted { benchKeep(engine[id]) }
      }
      benchPrint("chart.indicators.full_rebuild", n: n, samples)
    }
  }
}
