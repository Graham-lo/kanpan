import Foundation
import KanpanCore
import XCTest

import KanpanData

// MARK: - 可重复的性能基准（数据层）
//
// 只用 public API，不 `@testable`：同一份文件要能原样复制到改动后的代码上再跑。
// 快照编解码、补缺合并、启动快照的落盘与读回，各自量一次。

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

  // -------------------------------------------------------------- 快照编解码

  /// `Snapshot.maxBars` 就是 3000，正好是一份满快照。
  func testSnapshotEncodeDecode() {
    let n = 3000
    let series = benchSeries(count: n)
    let encodeSamples = benchRun { _ in
      let d = Snapshot.encode(series)
      XCTAssertGreaterThan(d.count, 0)
    }
    benchPrint("data.snapshot.encode", n: n, encodeSamples)

    let blob = Snapshot.encode(series)
    let decodeSamples = benchRun { _ in
      let back = Snapshot.decode(blob)
      XCTAssertEqual(back?.count, n)
    }
    benchPrint("data.snapshot.decode", n: n, decodeSamples)
  }

  // -------------------------------------------------------------- 补缺合并

  /// `FeedComposer.merge`：把 1500 根（与末尾重叠）合进 15000 根。
  func testFeedComposerMerge() {
    let n = 15000
    let series = benchSeries(count: n)
    // 与末尾 1500 根同 openTime 的一段「权威值」，收盘抖一下，走的是去重合并那条路。
    var r = BenchRNG(seed: 31337)
    var incoming: [Bar] = []
    incoming.reserveCapacity(1500)
    for i in (n - 1500)..<n {
      var b = series.bar(at: i)
      let c = max(1, b.close * (1 + r.range(-0.002, 0.002)))
      b.high = max(b.high, c); b.low = min(b.low, c); b.close = c
      incoming.append(b)
    }
    let samples = benchRun(rounds: 20) { _ in
      var composer = FeedComposer(series: series)
      composer.merge(incoming)
      XCTAssertEqual(composer.series.count, n)
    }
    benchPrint("data.feedcomposer.merge_1500_into_15000", n: n, samples)
  }

  // -------------------------------------------------------------- 启动快照落盘

  func testSeriesStoreWriteRead() throws {
    let n = 3000
    let series = benchSeries(count: n, symbol: "BENCHUSDT")
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("kanpan-bench-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let writeSamples = benchRun { _ in
      let bytes = (try? SeriesStore.write(series, in: dir)) ?? 0
      XCTAssertGreaterThan(bytes, 0)
    }
    benchPrint("data.seriesstore.write", n: n, writeSamples)

    let readSamples = benchRun { _ in
      let back = SeriesStore.read(symbol: "BENCHUSDT", interval: .h1, in: dir)
      XCTAssertEqual(back?.count, n)
    }
    benchPrint("data.seriesstore.read", n: n, readSamples)
  }
}
