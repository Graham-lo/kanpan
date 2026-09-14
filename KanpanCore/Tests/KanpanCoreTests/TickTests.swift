import Foundation
import Testing

@testable import KanpanCore

/// A1.6：`niceStep` / `timeStep` 与原型导出的 200 组输入输出全等。
@Suite("刻度")
struct TickTests {
  @Test("niceStep 与原型全等")
  func niceStepMatches() {
    var bad = 0
    var first = ""
    for row in Fx.nice {
      let got = niceStep(span: row[0], want: row[1])
      if abs(got - row[2]) > 1e-12 * max(1, abs(row[2])) {
        bad += 1
        if first.isEmpty { first = "span=\(row[0]) want=\(row[1]) 期望 \(row[2]) 得到 \(got)" }
      }
    }
    #expect(bad == 0, "\(Fx.nice.count) 组里 \(bad) 组不符，首个 \(first)")
    #expect(Fx.nice.count >= 200, "fixture 只有 \(Fx.nice.count) 组")
  }

  @Test("timeStep 与原型全等")
  func timeStepMatches() {
    var bad = 0
    var first = ""
    for row in Fx.time {
      let got = timeStep(spanMs: row[0], plotW: row[1], perLabelPx: row[2])
      if Double(got) != row[3] {
        bad += 1
        if first.isEmpty { first = "span=\(row[0]) plotW=\(row[1]) 期望 \(row[3]) 得到 \(got)" }
      }
    }
    #expect(bad == 0, "\(Fx.time.count) 组里 \(bad) 组不符，首个 \(first)")
    #expect(Fx.time.count >= 200, "fixture 只有 \(Fx.time.count) 组")
  }

  @Test("阶梯表与原型一致")
  func stepsTable() {
    #expect(timeSteps.map(Double.init) == Fx.timeStepsJS)
  }

  /// `niceStep` 只允许 1 / 2 / 2.5 / 5 / 10 这五种尾数。
  @Test("niceStep 尾数只有五种")
  func niceStepMantissa() {
    var r = Rng(515)
    for _ in 0..<20000 {
      let span = pow(10, r.d(-6, 9))
      let want = Double(r.i(2, 16))
      let s = niceStep(span: span, want: want)
      #expect(s > 0 && s.isFinite, "span=\(span) 得到 \(s)")
      let m = s / pow(10, floor(log10(s)))
      let ok = [1.0, 2.0, 2.5, 5.0, 10.0].contains { abs($0 - m) < 1e-9 }
      #expect(ok, "span=\(span) want=\(want) 尾数 \(m)")
    }
    #expect(niceStep(span: 0, want: 5) == 1, "span=0 要有兜底")
    #expect(niceStep(span: -3, want: 5) == 1)
  }

  /// 标签数不能失控：`span/step` 落在 want 附近。
  @Test("刻度密度合理")
  func density() {
    var r = Rng(717)
    for _ in 0..<5000 {
      let span = pow(10, r.d(-4, 6))
      let want = Double(r.i(2, 14))
      let n = span / niceStep(span: span, want: want)
      #expect(n <= want * 2 + 1e-9, "span=\(span) want=\(want) 出了 \(n) 格")
      #expect(n >= want / 4 - 1e-9, "span=\(span) want=\(want) 只出了 \(n) 格")
    }
  }

  /// 时间刻度对齐到步长整数倍（按时区平移后）。
  @Test("时间刻度按时区对齐", arguments: TZChoice.allCases)
  func timeTicksAligned(_ tz: TZChoice) {
    let off = Double(tz.offsetMinutes) * 60_000
    var r = Rng(919)
    for _ in 0..<400 {
      let from = r.d(1.6e12, 1.8e12)
      let span = pow(10, r.d(5, 10.5))
      let plotW = r.d(120, 900)
      let v = ViewWindow(from: from, to: from + span)
      let ticks = timeTicks(view: v, plotW: plotW, offsetMinutes: tz.offsetMinutes)
      for (t, step) in ticks {
        #expect(t >= v.from - 1 && t <= v.to + 1, "刻度跑到视野外 \(t)")
        let m = (t + off).truncatingRemainder(dividingBy: Double(step))
        #expect(abs(m) < 1e-6 || abs(abs(m) - Double(step)) < 1e-6, "\(tz.rawValue) 没对齐：\(t) % \(step) = \(m)")
      }
      let expected = floor(v.span / Double(ticks.first?.step ?? 1))
      #expect(Double(ticks.count) <= expected + 2, "刻度多了")
    }
  }

  /// 价格刻度在变换后的空间里等距，且都落在区间内。
  @Test("价格刻度等距", arguments: PriceMode.allCases)
  func priceTicksEven(_ mode: PriceMode) {
    var r = Rng(1213)
    for _ in 0..<600 {
      let lo = r.d(0.01, 90000)
      let range = PriceRange(lo: lo, hi: lo * r.d(1.001, 3), base: lo)
      let h = r.d(60, 700)
      let ts = priceTicks(range: range, mode: mode, paneH: h)
      guard ts.count >= 2 else { continue }
      let d0 = ts[1] - ts[0]
      for i in 1..<ts.count {
        #expect(abs((ts[i] - ts[i - 1]) - d0) <= 1e-9 * max(1, abs(d0)), "\(mode.rawValue) 第 \(i) 格不等距")
      }
      let a = mode.forward(range.lo, base: range.base), z = mode.forward(range.hi, base: range.base)
      #expect(ts.first! >= a - 1e-9 && ts.last! <= z + 1e-9, "\(mode.rawValue) 刻度出界")
      #expect(Double(ts.count) <= max(2, floor(h / Chart.priceLabelPx)) * 2 + 2, "\(mode.rawValue) 刻度太密")
    }
  }
}
