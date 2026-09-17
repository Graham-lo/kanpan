import Foundation
import XCTest

import KanpanCore

// MARK: - 可重复的性能基准（算法层）
//
// 只用 public API，不 `@testable`：同一份文件要能原样复制到改动后的代码上再跑。
// `IndicatorEngine` 全量（新引擎 `ensure`）对比追加一根后的增量（`updateTail`），
// RSI / ATR / BOLL / KDJ / MACD 各一档，n = 3000 与 15000。

struct BenchRNG {
  private var s: UInt64
  init(seed: UInt64) { s = seed &* 6_364_136_223_846_793_005 &+ 1442695040888963407 }
  mutating func next() -> UInt64 {
    s ^= s << 13; s ^= s >> 7; s ^= s << 17
    return s
  }
  mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
  mutating func range(_ a: Double, _ b: Double) -> Double { a + unit() * (b - a) }
}

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

func benchMs(_ d: Duration) -> Double {
  Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
}

func benchMedian(_ xs: [Double]) -> Double {
  let s = xs.sorted()
  guard !s.isEmpty else { return .nan }
  return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

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

/// 结果落地口。Release 下如果算完没人用，整段计算会被优化掉——所有基准都把
/// 结果喂给这个 `@inline(never)` 的口子，量到的才是真的算了一遍。
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

final class PerfBenchmarkTests: XCTestCase {
  static let counts = [3000, 15000]
  static let ids: [IndicatorID] = [.rsi, .atr, .boll, .kdj, .macd]

  /// 全量：每轮新建一台引擎，从零把整段算出来。
  func testIndicatorFullRebuild() {
    for id in Self.ids {
      for n in Self.counts {
        let series = benchSeries(count: n)
        let params = [id: id.defaultParams]
        let samples = benchRun { _ in
          var engine = IndicatorEngine()
          engine.ensure(series: series, wanted: [id], params: params, dataKey: "bench")
          benchKeep(engine[id])
        }
        benchPrint("core.indicator.\(id.rawValue.lowercased()).full", n: n, samples)
      }
    }
  }

  /// 增量：引擎已经算好，再追一根只重算尾巴（`updateTail`）。
  ///
  /// 追根本身（数组增长、COW）在计时区间之外——量的是引擎的增量成本，
  /// 不是 `BarSeries.append`。`n` 记的是起始根数。
  func testIndicatorTailUpdate() {
    for id in Self.ids {
      for n in Self.counts {
        var series = benchSeries(count: n)
        let params = [id: id.defaultParams]
        var engine = IndicatorEngine()
        engine.ensure(series: series, wanted: [id], params: params, dataKey: "bench")

        var r = BenchRNG(seed: 4242)
        var samples: [Double] = []
        let rounds = 40, warmup = 3
        for i in 0..<(rounds + warmup) {
          let last = series.bar(at: series.count - 1)
          let o = last.close
          let c = max(1, o * (1 + r.range(-0.012, 0.012)))
          series.append(Bar(
            openTime: last.openTime + series.step, open: o,
            high: max(o, c) * (1 + r.range(0, 0.006)),
            low: min(o, c) * (1 - r.range(0, 0.006)),
            close: c, volume: r.range(10, 5000)))
          let t = ContinuousClock.now
          engine.updateTail(series: series, dataKey: "bench")
          benchKeep(engine[id])
          let dt = benchMs(t.duration(to: .now))
          if i >= warmup { samples.append(dt) }
        }
        benchPrint("core.indicator.\(id.rawValue.lowercased()).tail", n: n, samples)
      }
    }
  }
}
