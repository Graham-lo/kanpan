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
  @Test("贴着最新：右缘离末根一格以内都算，一格开外不算；不满一屏的序列夹完就算")
  func pinnedToLatest() {
    let s = synthSeries(count: 800), w = 390.0, step = Double(s.step)
    for spacing in [1.6, 6, 40] {
      let latest = ViewMath.reset(series: s, plotW: w, spacing: spacing)
      #expect(ViewMath.isPinnedToLatest(latest, series: s, plotW: w))
      // 往历史挪 0.9 格还算贴着，挪 1.1 格就不算。
      #expect(ViewMath.isPinnedToLatest(latest.dragged(byFingerPx: 0.9 * spacing, plotW: w), series: s, plotW: w))
      #expect(!ViewMath.isPinnedToLatest(latest.dragged(byFingerPx: 1.1 * spacing, plotW: w), series: s, plotW: w))
    }
    let short = synthSeries(count: 20)
    let v = clampView(ViewWindow(to: Double(short.lastTime) + step * 100, span: w / 8 * step), series: short, plotW: w)
    #expect(ViewMath.isPinnedToLatest(v, series: short, plotW: w))
  }
  @Test("捏合一帧：贴着最新钉末根，否则绕中点；根宽不夹（软越界由调用方给）")
  func pinchedFrame() {
    let s = synthSeries(count: 800), w = 390.0
    let latest = ViewMath.reset(series: s, plotW: w, spacing: 8)
    let a = ViewMath.pinched(latest, series: s, plotW: w, spacing: 16, focus: 100, pinned: true)
    #expect(abs(a.x(Double(s.lastTime), plotW: w) + 8 - w) < 1e-6)
    #expect(abs(a.barSpacing(step: s.step, plotW: w) - 16) < 1e-9)
    let history = latest.dragged(byFingerPx: 900, plotW: w)
    let t = history.t(atX: 120, plotW: w)
    let b = ViewMath.pinched(history, series: s, plotW: w, spacing: 16, focus: 120, pinned: false)
    #expect(abs(b.x(t, plotW: w) - 120) < 1e-6)
    // 越过 40：根宽照给，左右照样不出界。
    let c = ViewMath.pinched(latest, series: s, plotW: w, spacing: 44, focus: 100, pinned: true)
    #expect(abs(c.barSpacing(step: s.step, plotW: w) - 44) < 1e-9)
    #expect(c == ViewMath.clampedOffset(c, series: s, plotW: w))
  }
  @Test("滚轮 / 一步缩放：贴着最新的判据和捏合同一条——差半格也钉末根")
  func scaledUsesSamePinnedRule() {
    let s = synthSeries(count: 800), w = 390.0
    let near = ViewMath.reset(series: s, plotW: w, spacing: 8).dragged(byFingerPx: 4, plotW: w)
    let z = ViewMath.scaled(near, series: s, plotW: w, factor: 2, focus: 100)
    #expect(abs(z.x(Double(s.lastTime), plotW: w) + 8 - w) < 1e-6)
  }
  @Test("软边界：界内原样、越界连续且斜率 1、永远够不着 0.85 / 1.15；反函数对得上")
  func softSpacing() {
    let lo = AICoinBehavior.minimumSpacing, hi = AICoinBehavior.maximumSpacing
    for r in [lo, 3, 10, hi] { #expect(ViewMath.softSpacing(r) == r) }
    var prev = 0.0
    for k in 0..<400 {
      let r = lo * 0.3 + Double(k) * (hi * 3 - lo * 0.3) / 400
      let v = ViewMath.softSpacing(r)
      #expect(v >= prev - 1e-12)
      #expect(v > lo * (1 - ViewMath.zoomOvershoot) && v < hi * (1 + ViewMath.zoomOvershoot))
      prev = v
      #expect(abs(ViewMath.rawSpacing(forSoft: v) - ViewMath.boundedRawSpacing(r)) / r < 1e-6 || r > hi * 1.52 || r < lo * 0.62)
    }
    // 越界那一点斜率 1：刚越过去 1% 时画出来的也差不多越过 1%。
    #expect(abs(ViewMath.softSpacing(hi * 1.01) / hi - 1.01) < 0.001)
    #expect(abs(ViewMath.softSpacing(lo / 1.01) * 1.01 / lo - 1) < 0.001)
    // 攒的量有上限：再往外捏也只攒到三倍阻尼宽度。
    #expect(ViewMath.boundedRawSpacing(1e9) == hi * pow(1.15, 3))
    #expect(ViewMath.boundedRawSpacing(1e-9) == lo * pow(0.85, 3))
  }
  @Test("空数据不产生无效窗口")
  func empty() {
    let s = BarSeries(symbol: "X", interval: .h1, bars: [])
    let v = ViewWindow(from: 10, to: 20)
    #expect(clampView(v, series: s, plotW: 300) == v)
  }
}
