import Testing

@testable import KanpanCore

/// A1.2：增量重算必须和全量重算**逐位**一样，不是「差不多」。
/// 随机做 1000 次「改末根 / 追加新根」，每次都拿一台全新的引擎当裁判。
@Suite("指标增量重算")
struct IndicatorIncrementalTests {
  static let all: [IndicatorID] = [.ma, .ema, .boll, .vol, .macd, .rsi, .kdj, .srsi, .atr]

  /// 全量：新引擎从零算。
  static func full(_ s: BarSeries) -> [IndicatorID: IndicatorResult] {
    var e = IndicatorEngine()
    e.ensure(series: s, wanted: all, dataKey: "full")
    return e.values
  }

  static func compare(
    _ got: [IndicatorID: IndicatorResult], _ want: [IndicatorID: IndicatorResult], _ label: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    for id in all {
      let g = got[id]!, w = want[id]!
      #expect(g.lines.count == w.lines.count, "\(label) \(id.rawValue) 线数", sourceLocation: sourceLocation)
      for (i, line) in g.lines.enumerated() {
        expectSame(line, w.lines[i], "\(label) \(id.rawValue)[\(i)]", tol: 0, sourceLocation: sourceLocation)
      }
      if let h = w.histogram {
        expectSame(g.histogram ?? [], h, "\(label) \(id.rawValue) hist", tol: 0, sourceLocation: sourceLocation)
      }
    }
  }

  /// 1000 次随机操作，四条链路并行跑（每条 250 次），全程与全量对照。
  @Test("随机改末根 / 追加新根 1000 次", arguments: [0, 1, 2, 3])
  func incrementalMatchesFull(_ lane: Int) {
    var r = Rng(UInt64(20260914 + lane))
    var s = synthSeries(count: 320, seed: UInt64(101 + lane))
    var e = IndicatorEngine()
    e.ensure(series: s, wanted: Self.all, dataKey: "inc")
    Self.compare(e.values, Self.full(s), "lane\(lane) 初始")

    for step in 0..<250 {
      let last = s.bar(at: s.count - 1)
      if r.d() < 0.5 {
        // 改末根：价格抖一下，量重报一次。
        let c = max(1, last.close * (1 + r.d(-0.01, 0.01)))
        s.replaceLast(with: Bar(
          openTime: last.openTime, open: last.open,
          high: max(max(last.open, c), last.high * (1 + r.d(0, 0.004))),
          low: min(min(last.open, c), last.low * (1 - r.d(0, 0.004))),
          close: c, volume: last.volume + r.d(0, 40)))
      } else {
        // 收一根、开一根。
        let o = last.close
        let c = max(1, o * (1 + r.d(-0.02, 0.02)))
        s.append(Bar(
          openTime: last.openTime + s.step, open: o,
          high: max(o, c) * (1 + r.d(0, 0.008)), low: min(o, c) * (1 - r.d(0, 0.008)),
          close: c, volume: r.d(10, 5000)))
      }
      e.updateTail(series: s, dataKey: "inc")
      if step % 25 == 0 || step == 249 {
        Self.compare(e.values, Self.full(s), "lane\(lane) 第 \(step) 步")
      }
    }
    Self.compare(e.values, Self.full(s), "lane\(lane) 收尾")
  }

  /// 连追 500 根不回头对一次，最后仍要和全量一致——递推状态不许漂。
  @Test("连续追加 500 根不漂移")
  func longRunNoDrift() {
    var r = Rng(4242)
    var s = synthSeries(count: 200, seed: 9)
    var e = IndicatorEngine()
    e.ensure(series: s, wanted: Self.all, dataKey: "drift")
    for _ in 0..<500 {
      let last = s.bar(at: s.count - 1)
      let o = last.close
      let c = max(1, o * (1 + r.d(-0.03, 0.03)))
      s.append(Bar(openTime: last.openTime + s.step, open: o,
                   high: max(o, c) * 1.001, low: min(o, c) * 0.999, close: c, volume: r.d(1, 999)))
      e.updateTail(series: s, dataKey: "drift")
    }
    Self.compare(e.values, Self.full(s), "追 500 根")
  }

  /// 根数少于指标周期时（前导全 NaN）增量也不能出岔子。
  @Test("短序列", arguments: [1, 2, 5, 13, 27])
  func shortSeries(_ n: Int) {
    var s = synthSeries(count: n, seed: UInt64(n))
    var e = IndicatorEngine()
    e.ensure(series: s, wanted: Self.all, dataKey: "short")
    Self.compare(e.values, Self.full(s), "n=\(n) 初始")
    let last = s.bar(at: s.count - 1)
    s.replaceLast(with: Bar(openTime: last.openTime, open: last.open, high: last.high * 1.01,
                            low: last.low * 0.99, close: last.close * 1.005, volume: last.volume + 1))
    e.updateTail(series: s, dataKey: "short")
    Self.compare(e.values, Self.full(s), "n=\(n) 改末根")
  }
}
