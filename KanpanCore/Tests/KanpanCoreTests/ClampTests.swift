import Foundation
import Testing

@testable import KanpanCore

/// A1.4：10 万次随机视野过一遍 `clampView`，结果必须落在 §5.2 的边界里。
@Suite("视野夹取")
struct ClampTests {
  /// 十条链路各 1 万次。
  @Test("10 万次随机视野无越界", arguments: Array(0..<10))
  func randomViewsStayInBounds(_ lane: Int) {
    var r = Rng(UInt64(999 + lane))
    let series = [
      synthSeries(count: 1, interval: .h1, seed: 1),
      synthSeries(count: 37, interval: .m1, seed: 2),
      synthSeries(count: 500, interval: .h4, seed: 3),
      synthSeries(count: 1500, interval: .d1, seed: 4),
    ]
    var bad = 0
    var first = ""
    for _ in 0..<10_000 {
      let s = series[r.i(0, series.count - 1)]
      let plotW = r.d(80, 1400)
      let soft = r.d() < 0.5
      let step = Double(s.step)
      // 故意撒野：窗宽从荒唐地小到荒唐地大，位置也随便放。
      let span = step * pow(10, r.d(-3, 5))
      let to = Double(s.lastTime) + r.d(-Double(s.count) * step * 2, Double(s.count) * step * 2)
      let v = clampView(ViewWindow(to: to, span: span), series: s, plotW: plotW, soft: soft)

      let minSpan = (plotW / Chart.maxBarSpacing) * step
      let maxSpan = min((plotW / Chart.minBarSpacing) * step, Double(s.count) * step * 3)
      let give = soft ? v.span * Chart.softGive : 0
      let eps = max(1e-6, abs(v.to) * 1e-12)
      let maxTo: Double = Double(s.lastTime) + v.span * 0.7 + give
      let minTo: Double = Double(s.firstTime) + v.span * 0.3 - give
      // 整段还没一屏宽时 minSpan 会大过 maxSpan，原型的写法是 minSpan 说了算。
      var ok: Bool = v.span >= minSpan - eps && v.span <= max(minSpan, maxSpan) + eps
      // 窗比整段还宽时左右两个边界会打架，原型的顺序是左边界说了算。
      ok = ok && (v.to <= maxTo + eps || abs(v.to - minTo) <= eps)
      ok = ok && v.to >= minTo - eps
      ok = ok && v.from < v.to && v.span.isFinite
      if !ok {
        bad += 1
        if first.isEmpty {
          first = "span=\(span) to=\(to) plotW=\(plotW) soft=\(soft) → \(v)"
        }
      }
    }
    #expect(bad == 0, "lane\(lane)：\(bad) 次越界，首个 \(first)")
  }

  /// 夹过一次就是稳的：再夹不动了。
  @Test("幂等")
  func idempotent() {
    var r = Rng(31337)
    let s = synthSeries(count: 600, interval: .h1, seed: 5)
    for _ in 0..<5000 {
      let plotW = r.d(100, 1200)
      let v = clampView(
        ViewWindow(to: Double(s.lastTime) + r.d(-1e9, 1e9), span: Double(s.step) * pow(10, r.d(-2, 4))),
        series: s, plotW: plotW)
      let again = clampView(v, series: s, plotW: plotW)
      #expect(abs(again.from - v.from) < 1e-6 && abs(again.to - v.to) < 1e-6, "夹了两次不一样 \(v) → \(again)")
    }
  }

  /// 空序列不夹，直接原样返回——别在没有数据的时候算出 NaN。
  @Test("空序列原样返回")
  func emptyPassthrough() {
    let s = BarSeries(symbol: "X", interval: .h1, t0: 0, open: [], high: [], low: [], close: [], volume: [])
    let v = ViewWindow(from: 10, to: 20)
    #expect(clampView(v, series: s, plotW: 300) == v)
    #expect(ViewMath.reset(series: s, plotW: 300, spacing: 9.2) == ViewWindow(from: 0, to: 1))
  }

  /// `reset` 右边留 6% 空白；最后一根一定看得见。
  @Test("初始视野右侧留白 6%")
  func resetRightGap() {
    for iv in Interval.allCases {
      let s = synthSeries(count: 800, interval: iv, seed: 6)
      let v = ViewMath.reset(series: s, plotW: 390, spacing: CandleStyle.default.spacing)
      let last = Double(s.lastTime)
      #expect(v.to > last, "\(iv.rawValue) 最后一根被挤出去了")
      #expect(v.from < last, "\(iv.rawValue) 看不见最后一根")
      #expect(abs((v.to - last) / v.span - Chart.rightGap) < 1e-9 || v.to == last + v.span * 0.7,
              "\(iv.rawValue) 留白 \((v.to - last) / v.span)")
    }
  }

  /// 换风格：右边缘不动，只有窗宽跟着新的默认根间距走。
  @Test("换风格右缘不动")
  func applySpacingKeepsRightEdge() {
    let s = synthSeries(count: 700, seed: 7)
    let plotW = 390.0
    var v = ViewMath.reset(series: s, plotW: plotW, spacing: CandleStyle.default.spacing)
    for st in CandleStyle.all {
      let n = ViewMath.applySpacing(v, series: s, plotW: plotW, spacing: st.spacing)
      #expect(abs(n.to - v.to) < 1e-6, "\(st.id) 右缘动了 \(v.to) → \(n.to)")
      #expect(abs(n.barSpacing(step: s.step, plotW: plotW) - st.spacing) < 1e-9, "\(st.id) 根间距不对")
      v = n
    }
  }

  /// 视野左缘进到头部 200 根以内才叫「该补历史了」。
  @Test("补历史阈值")
  func needsMore() {
    let s = synthSeries(count: 1000, seed: 8)
    let step = Double(s.step), t0 = Double(s.firstTime)
    #expect(ViewMath.needsMoreHistory(ViewWindow(from: t0 + 199 * step, to: t0 + 400 * step), series: s))
    #expect(!ViewMath.needsMoreHistory(ViewWindow(from: t0 + 201 * step, to: t0 + 400 * step), series: s))
  }

  /// 双指缩放：先捏开再捏拢，回到原处；中点那一刻对应的时间钉住不动。
  @Test("双指缩放锚点不动")
  func pinchAnchor() {
    var r = Rng(24680)
    let plotW = 390.0
    for _ in 0..<2000 {
      let from0 = r.d(1e12, 1.7e12), span0 = r.d(1e6, 1e10)
      let d0 = r.d(20, 400), d = r.d(20, 400), mid = r.d(0, plotW)
      let v = ViewMath.pinch(from0: from0, span0: span0, d0: d0, d: d, mid0Px: mid, plotW: plotW)
      let anchor = from0 + mid / plotW * span0
      let got = v.t(atX: mid, plotW: plotW)
      #expect(abs(got - anchor) <= max(1e-6, abs(anchor) * 1e-12), "锚点漂了 \(anchor) → \(got)")
      // 同一次手势里回到原距离，就该回到原视野。
      let back = ViewMath.pinch(from0: from0, span0: span0, d0: d0, d: d0, mid0Px: mid, plotW: plotW)
      // 时间戳上万亿，一个 ulp 就有 2e-4，容差得跟着绝对量级走。
      let slack = max(1e-6, (abs(from0) + span0) * 1e-12)
      #expect(abs(back.from - from0) <= slack && abs(back.span - span0) <= slack)
    }
  }
}
