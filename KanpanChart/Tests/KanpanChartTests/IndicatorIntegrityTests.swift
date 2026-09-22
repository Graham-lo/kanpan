import Foundation
import KanpanCore
import Testing
@testable import KanpanChart

@MainActor @Suite("Indicators follow the accepted candle snapshot")
struct IndicatorIntegrityTests {
  func verify(_ renderer: ChartRenderer, _ state: ChartState) {
    let reference = ChartRenderer(state: state)
    for id in state.overlays + state.subs {
      let a = renderer.engine[id]!, b = reference.engine[id]!
      for (x, y) in zip(a.lines + [a.histogram ?? [], a.dir ?? []],
                        b.lines + [b.histogram ?? [], b.dir ?? []]) {
        #expect(x.count == y.count)
        #expect(zip(x,y).allSatisfy { ($0.isNaN && $1.isNaN) || abs($0 - $1) < 1e-8 })
      }
    }
  }
  @Test func switchesHistoryCorrectionsParametersAndOI() {
    var state = ChartOptionsRenderTests.state()
    state.overlays = [.ma, .ema, .vwap, .supertrend, .sar]
    state.subs = [.vol, .oi, .macd, .kdj, .rsi, .dmi]
    var renderer = ChartRenderer(state: state)
    let i = state.series.count - 1
    state.series.close[i] += 3
    state.series.high[i] = max(state.series.high[i], state.series.close[i])
    state.series.volume[i] += 10
    renderer.state = state
    verify(renderer, state)
    // Same count and symbol; a historical correction must rebuild recursive seeds.
    state.series.close[20] += 70
    renderer.state = state
    verify(renderer, state)
    state.params[.ema] = [3, 8, 13]
    state.params[.macd] = [5, 13, 4]
    renderer.state = state
    verify(renderer, state)
    state.oi = OISeries(t0: state.series.t0, step: state.series.step,
                        values: Array(repeating: 33, count: state.series.count))
    renderer.state = state
    verify(renderer, state)
    state.oi = nil
    state.series = BarSeries(symbol: "ETHUSDT", interval: .h4, t0: state.series.t0,
      open: state.series.open, high: state.series.high, low: state.series.low,
      close: state.series.close.map { $0 / 10 }, volume: state.series.volume)
    renderer.state = state
    verify(renderer, state)
    let missingOI = renderer.engine[.oi]!.lines[0].allSatisfy { $0.isNaN }
    #expect(missingOI)
  }
  @Test func presentationChangesRetainExactCalculations() {
    var state = ChartOptionsRenderTests.state()
    state.overlays = [.ma, .ema, .vwap, .supertrend, .sar]
    state.subs = [.macd, .kdj, .rsi, .vol, .dmi]
    var renderer = ChartRenderer(state: state)
    for i in 0..<300 {
      state.crosshair = Crosshair(index: i % state.series.count)
      state.nowMs = Double(i * 1000)
      state.paletteSeed = i.isMultiple(of: 2) ? Palette.terraSeed : Palette.terraNightSeed
      renderer.state = state
    }
    verify(renderer, state)
  }
}
