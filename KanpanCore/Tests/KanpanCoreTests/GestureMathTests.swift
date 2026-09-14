import Foundation
import Testing
@testable import KanpanCore

@Suite("AICoin 统一手势算术") struct GestureMathTests {
  @Test("历史区焦点缩放，右端缩放保持最新列尾贴右")
  func anchors() {
    let s = synthSeries(count: 1500)
    let w = 360.0
    let latest = ViewMath.reset(series: s, plotW: w, spacing: 4)
    let end = ViewMath.scaled(latest, series: s, plotW: w, factor: 2, focus: 100)
    #expect(abs(end.x(Double(s.lastTime), plotW: w) - 356) < 1e-6)
    let history = latest.dragged(byFingerPx: 500, plotW: w)
    let t = history.t(atX: 120, plotW: w)
    let zoom = ViewMath.scaled(history, series: s, plotW: w, factor: 2, focus: 120)
    #expect(abs(zoom.x(t, plotW: w) - 120) < 1e-6)
    let back = ViewMath.scaled(zoom, series: s, plotW: w, factor: 0.5, focus: 120)
    #expect(abs(back.to - history.to) < 0.001)
    #expect(abs(back.span - history.span) < 0.001)
  }
  @Test("两端越界有限空白并回各自边界，历史中途不吸回", arguments: [240.0, 360.0, 900.0])
  func latestEdgePull(width: Double) {
    let series = synthSeries(count: 1500)
    let latest = ViewMath.reset(series: series, plotW: width, spacing: 4)
    let history = latest.dragged(byFingerPx: 400, plotW: width)
    for finger in [-80.0, 80.0] {
      let proposed = history.dragged(byFingerPx: finger, plotW: width)
      let actual = ViewMath.dragging(proposed, series: series, plotW: width)
      #expect(abs(actual.to - proposed.to) < 0.001)
      #expect(actual.to < latest.to)
    }
    let oldest = clampView(latest.dragged(byFingerPx: 100000, plotW: width), series: series, plotW: width)
    let olderPull = ViewMath.dragging(oldest.dragged(byFingerPx: 100, plotW: width), series: series, plotW: width)
    #expect(olderPull.to < oldest.to)
    #expect((oldest.to - olderPull.to) / oldest.span * width < min(32, width * 0.1))
    #expect(abs(clampView(olderPull, series: series, plotW: width).to - oldest.to) < 0.001)
    var previous = 0.0
    for finger in [-10.0, -100, -10000] {
      let pulled = ViewMath.dragging(latest.dragged(byFingerPx: finger, plotW: width), series: series, plotW: width)
      let distance = (pulled.to - latest.to) / pulled.span * width
      #expect(distance > previous && distance < min(32, width * 0.1))
      #expect(pulled.span == latest.span)
      let settled = clampView(pulled, series: series, plotW: width)
      #expect(abs(settled.to - latest.to) < 0.001)
      previous = distance
    }
  }

  @Test("回弹有限时长单调回原边界，不改根宽或越过历史目标")
  func latestEdgeRebound() {
    let end = ViewWindow(to: 1000, span: 500)
    let start = ViewWindow(to: 1200, span: 500)
    var previous = start.to
    for ms in stride(from: 0.0, through: 320.0, by: 16) {
      let (view, done) = ViewTransition.rebound(from: start, to: end, elapsedMs: ms)
      #expect(view.to <= previous && view.to >= end.to && view.span == end.span)
      #expect(done == (ms >= 320))
      previous = view.to
    }
    #expect(ViewTransition.rebound(from: start, to: end, elapsedMs: 1000).view == end)
  }

  @Test("到达极限后反向捏合立即响应")
  func reverseAtLimit() {
    let s = synthSeries(count: 1500)
    let v = ViewMath.reset(series: s, plotW: 360, spacing: 4)
    let maxed = ViewMath.scaled(v, series: s, plotW: 360, factor: 100, focus: 100)
    let back = ViewMath.scaled(maxed, series: s, plotW: 360, factor: 0.9, focus: 100)
    #expect(abs(back.barSpacing(step: s.step, plotW: 360) - 36) < 1e-6)
  }
  @Test("Y倍率与高度归一化，中心夹取，自动复位仅改Y")
  func yState() {
    #expect(AICoinBehavior.axisZoom(from: 1, dy: 100, height: 400) == 0.5)
    #expect(AICoinBehavior.axisZoom(from: 1, dy: -10000, height: 400) == 16)
    #expect(AICoinBehavior.axisZoom(from: 1, dy: 10000, height: 400) == 0.03)
    #expect(PriceTransform.clampedCenter(50, zoom: 2) == 1.5)
    #expect(PriceTransform.clampedCenter(-50, zoom: 2) == -0.5)
    var p = PriceTransform(mode: .log, zoom: 2, centerFraction: 0.7)
    p.inverted = true; p.reset()
    #expect(!p.isManual && p.centerFraction == 0.5 && p.inverted && p.mode == .log)
  }
  @Test("手动Y随新自动区间重算，不永久钉死旧价格")
  func manualRange() {
    let s = synthSeries(count: 1500)
    let start = ViewMath.reset(series: s, plotW: 360, spacing: 4)
    let t = PriceTransform(mode: .linear, zoom: 2, centerFraction: 0.7)
    for v in [start, start.dragged(byFingerPx: 300, plotW: 360)] {
      let raw = priceRange(view: v, series: s)
      let actual = priceRange(view: v, series: s, transform: t)
      let d = raw.hi - raw.lo
      #expect(abs((actual.hi - actual.lo) / d - 0.5) < 1e-9)
      #expect(abs(((actual.hi + actual.lo) / 2 - raw.lo) / d - 0.7) < 1e-9)
    }
  }
}
