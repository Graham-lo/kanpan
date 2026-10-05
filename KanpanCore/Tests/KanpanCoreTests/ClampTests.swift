import Foundation
import Testing
@testable import KanpanCore
@Suite("AICoin 硬边界") struct ClampTests {
  @Test("十万随机视窗在左右列边界内", arguments: Array(0..<10))
  func bounds(_ lane: Int) {
    var rng = Rng(UInt64(999 + lane))
    let series = [1, 37, 500, 1500].map { synthSeries(count: $0) }
    var bad = 0
    for _ in 0..<10000 {
      let s = series[rng.i(0, 3)], width = rng.d(80, 1400), step = Double(s.step)
      let raw = ViewWindow(to: Double(s.lastTime) + rng.d(-1e10, 1e10), span: step * pow(10, rng.d(-3, 5)))
      let v = clampView(raw, series: s, plotW: width)
      let spacing = v.barSpacing(step: s.step, plotW: width)
      let firstX = v.x(Double(s.firstTime), plotW: width)
      let lastX = v.x(Double(s.lastTime), plotW: width)
      let expectedMinimumLastX = min(Double(s.count) * spacing - spacing / 2, width - spacing / 2)
      if spacing < 1.6 - 1e-6 || spacing > 40 + 1e-6 || firstX > spacing / 2 + 1e-6
          || lastX < expectedMinimumLastX - 1e-6 { bad += 1 }
      let again = clampView(v, series: s, plotW: width)
      if abs(v.to - again.to) > 0.001 || abs(v.span - again.span) > 0.001 { bad += 1 }
    }
    #expect(bad == 0)
  }
  @Test("最新柱列尾贴右缘，半根偏移一致")
  func latest() {
    let s = synthSeries(count: 800)
    for spacing in [1.6, 4, 8, 40] {
      let v = ViewMath.reset(series: s, plotW: 390, spacing: spacing)
      #expect(abs(v.x(Double(s.lastTime), plotW: 390) + spacing / 2 - 390) < 1e-6)
    }
  }
  @Test("休市缺根的序列（美元指数周末）：打开就贴到真实末根，最新一截能拖到")
  func gappyLatest() {
    // 1h，前 300 根连续，中间停 48 小时（周末），后 200 根连续。
    let step: Int64 = 3_600_000
    var times: [Int64] = []
    for i in 0..<300 { times.append(Int64(i) * step) }
    for i in 0..<200 { times.append(Int64(300 + 48 + i) * step) }
    let n = times.count
    let ones = [Double](repeating: 1, count: n)
    let s = BarSeries(symbol: "DXY", interval: .h1, t0: 0, step: step,
                      open: ones, high: ones, low: ones, close: ones, volume: ones,
                      openTime: times)
    #expect(s.lastTime == times[n - 1])
    for spacing in [1.6, 4, 8, 40] {
      let v = ViewMath.reset(series: s, plotW: 390, spacing: spacing)
      // 末根列尾贴右缘留出右侧空白，和连续序列一样，不被夹回历史中段。
      let c = synthSeries(count: n)
      let vc = ViewMath.reset(series: c, plotW: 390, spacing: spacing)
      #expect(abs(v.x(Double(s.lastTime), plotW: 390) - vc.x(Double(c.lastTime), plotW: 390)) < 1e-6)
      // 再往右拖也夹回同一处，往左拖到首根为止。
      let pushed = clampView(ViewWindow(to: v.to + 1e9, span: v.span), series: s, plotW: 390)
      #expect(abs(pushed.to - v.to) < 1e-3)
    }
  }
  @Test("空数据不产生无效窗口")
  func empty() {
    let s = BarSeries(symbol: "X", interval: .h1, bars: [])
    let v = ViewWindow(from: 10, to: 20)
    #expect(clampView(v, series: s, plotW: 300) == v)
  }
}
