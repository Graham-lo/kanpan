import Foundation
import Testing
@testable import KanpanCore

@Suite("Indicator workload benchmark")
struct IndicatorPerformanceTests {
  @Test func liveTailVersusFullRebuild() {
    let bars = (0..<12_000).map { i -> Bar in
      let close = 100 + sin(Double(i) / 19) * 10 + Double(i) / 100
      return Bar(openTime: Int64(i) * 60_000, open: close - 0.2, high: close + 1, low: close - 1, close: close, volume: 100 + Double(i % 50))
    }
    var series = BarSeries(symbol: "BTCUSDT", interval: .m1, bars: bars)
    let ids: [IndicatorID] = [.ma, .ema, .vol, .oi, .macd, .kdj, .rsi]
    var tail = IndicatorEngine()
    tail.ensure(series: series, wanted: ids)
    var incrementalMs: [Double] = [], fullMs: [Double] = []
    for i in 0..<100 {
      let last = series.count - 1
      series.close[last] = bars[last].close + Double(i % 10) / 100
      series.volume[last] += 1
      let start = ContinuousClock.now
      tail.updateTail(series: series)
      incrementalMs.append(milliseconds(start.duration(to: .now)))
      let beginFull = ContinuousClock.now
      var full = IndicatorEngine()
      full.ensure(series: series, wanted: ids)
      fullMs.append(milliseconds(beginFull.duration(to: .now)))
      for id in ids {
        let a = tail[id]!, b = full[id]!
        for (x, y) in zip(a.lines + [a.histogram ?? []], b.lines + [b.histogram ?? []]) {
          #expect(x.count == y.count)
          #expect(zip(x,y).allSatisfy { ($0.isNaN && $1.isNaN) || abs($0 - $1) < 1e-7 })
        }
      }
    }
    func p95(_ values: [Double]) -> Double { values.sorted()[94] }
    print("INDICATOR_BENCHMARK bars=12000 updates=100 tailP95Ms=\(p95(incrementalMs)) fullP95Ms=\(p95(fullMs))")
  }
  func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
  }
}
