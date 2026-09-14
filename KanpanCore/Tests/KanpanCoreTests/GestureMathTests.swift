import Foundation
import Testing

@testable import KanpanCore

/// M4 手势背后的纯算术：回弹、惯性、捏合往返、轴拖锚点。
///
/// 这些是 §13 G1 / G2 / G3 / G5 / G6 / G7 能不能过的前提——录屏只能证明「看起来对」，
/// 数字得在这儿钉死。
@Suite("手势算术")
struct GestureMathTests {
  private let plotW = 360.0

  private func fixture() -> BarSeries { synthSeries(count: 1500, interval: .h1, seed: 7) }
  private func startView(_ s: BarSeries) -> ViewWindow {
    ViewMath.reset(series: s, plotW: plotW, spacing: 8)
  }

  // ---------------------------------------------------------------- G1 拖

  @Test("G1：手指走 100pt，图正好走 100pt")
  func dragIsOneToOne() {
    let s = fixture()
    let v0 = startView(s)
    for dx in [-240.0, -100, -3, 3, 100, 240] {
      let v = v0.dragged(byFingerPx: dx, plotW: plotW)
      // 拖之前在 x 处的那个时间，拖之后应该正好在 x + dx 处。
      let t = v0.t(atX: 120, plotW: plotW)
      #expect(abs(v.x(t, plotW: plotW) - (120 + dx)) < 1e-9, "dx=\(dx) 没跟住手")
      #expect(abs(v.span - v0.span) < 1e-9, "拖动不该改窗宽")
    }
  }

  // ---------------------------------------------------------------- G2 甩

  @Test("G2：慢放手不滑行、停一下再松手不滑行、快甩封顶 3px/ms")
  func flingGates() {
    let s = fixture()
    let v0 = startView(s)
    // 比 0.2px/ms 慢：不甩。
    #expect(FlingRun(speedPxPerMs: 0.19, gapMs: 8, start: v0, plotW: plotW) == nil)
    // 够快但手指已经停了 120ms：不甩。
    #expect(FlingRun(speedPxPerMs: 2, gapMs: 120, start: v0, plotW: plotW) == nil)
    let run = FlingRun(speedPxPerMs: 9, gapMs: 8, start: v0, plotW: plotW)
    #expect(run?.speedPxPerMs == 3, "速度该封顶到 3px/ms")
  }

  @Test("G2：滑行 1.4s 内必停，方向跟手，总位移等于 v·τ")
  func flingRunsOut() {
    let s = fixture()
    let v0 = startView(s)
    for v in [-3.0, -0.6, 0.35, 1.7] {
      guard let run = FlingRun(speedPxPerMs: v, gapMs: 8, start: v0, plotW: plotW) else {
        Issue.record("v=\(v) 该甩却没甩起来")
        continue
      }
      #expect(run.frame(elapsedMs: Chart.flingMaxMs).done, "v=\(v) 到 1.4s 还没停")
      let end = run.frame(elapsedMs: 5000).view
      // 手指往右甩（v > 0）视野该往回走，看到更早的 K 线。
      #expect((end.to - v0.to).sign == (v > 0 ? .minus : .plus), "v=\(v) 方向反了")
      let want = -(v * Chart.flingTauMs / plotW) * v0.span
      #expect(abs((end.to - v0.to) - want) < abs(want) * 1e-6 + 1e-9, "v=\(v) 总位移不对")
      // 中途某一帧必须落在起点和终点之间，不能越冲。
      let mid = run.frame(elapsedMs: 200).view.to - v0.to
      #expect(abs(mid) < abs(want) && abs(mid) > 0)
    }
  }

  // ---------------------------------------------------------------- G3 捏

  @Test("G3：两指中点那根全程不动")
  func pinchKeepsMidpointFixed() {
    let s = fixture()
    let v0 = startView(s)
    let mid = 150.0
    let t0 = v0.t(atX: mid, plotW: plotW)
    for d in [40.0, 80, 120, 240, 20] {
      let v = ViewMath.pinch(
        from0: v0.from, span0: v0.span, d0: 80, d: d, mid0Px: mid, plotW: plotW)
      #expect(abs(v.x(t0, plotW: plotW) - mid) < 1e-9, "d=\(d) 中点那根跑了")
    }
  }

  @Test("G3：捏开再捏拢回到原处，误差远小于 0.01 根间距")
  func pinchRoundTrip() {
    let s = fixture()
    let v0 = startView(s)
    let sp0 = v0.barSpacing(step: s.step, plotW: plotW)
    var v = v0
    // 一次手势里的每一帧都从同一份快照算，所以往返只看首尾。
    for d in [80.0, 140, 220, 300, 220, 140, 80] {
      v = ViewMath.pinch(
        from0: v0.from, span0: v0.span, d0: 80, d: d, mid0Px: 150, plotW: plotW)
    }
    let sp = v.barSpacing(step: s.step, plotW: plotW)
    #expect(abs(sp - sp0) < 1e-9, "往返之后根间距变了：\(sp0) → \(sp)")
    #expect(abs(v.to - v0.to) < 1e-9, "往返之后右边缘变了")
  }

  @Test("G3：捏到 0.4 / 40 就停住")
  func pinchStopsAtLimits() {
    let s = fixture()
    let v0 = startView(s)
    for d in [1.0, 4, 10_000] {
      let raw = ViewMath.pinch(
        from0: v0.from, span0: v0.span, d0: 80, d: max(Chart.pinchMinPx, d),
        mid0Px: 150, plotW: plotW)
      let v = clampView(raw, series: s, plotW: plotW, soft: true)
      let sp = v.barSpacing(step: s.step, plotW: plotW)
      #expect(sp >= Chart.minBarSpacing - 1e-9 && sp <= Chart.maxBarSpacing + 1e-9,
        "d=\(d) 根间距跑到 \(sp)")
    }
  }

  // ---------------------------------------------------------------- G5 回弹

  @Test("G5：软边界内松手会弹回硬边界，240ms 走完")
  func settleReturnsToHardBound() {
    let s = fixture()
    let v0 = startView(s)
    // 往左推手指，把最后一根一路推到左边 30% 处再往外顶——这是右边界那一侧。
    let over = clampView(
      v0.dragged(byFingerPx: -4 * plotW, plotW: plotW), series: s, plotW: plotW, soft: true)
    let hard = clampView(over, series: s, plotW: plotW)
    #expect(over.to > hard.to, "软夹取没给出越界空间，后面的回弹就没意义了")
    guard let target = Settle.target(over, series: s, plotW: plotW) else {
      Issue.record("越界了却说不用回弹")
      return
    }
    #expect(abs(target.to - hard.to) < 1e-9)
    #expect(Settle.frame(from: over, to: target, elapsedMs: 0).view.to == over.to)
    let done = Settle.frame(from: over, to: target, elapsedMs: Settle.durationMs)
    #expect(done.done)
    #expect(abs(done.view.to - target.to) < 1e-9)
    // 缓出：一半时间该走完一大半路程。
    let half = Settle.frame(from: over, to: target, elapsedMs: Settle.durationMs / 2).view
    let k = (half.to - over.to) / (target.to - over.to)
    #expect(k > 0.8 && k < 0.9, "缓出曲线不对：半程走了 \(k)")
  }

  @Test("G5：本来就在界内就不起动画")
  func settleSkipsWhenInside() {
    let s = fixture()
    #expect(Settle.target(startView(s), series: s, plotW: plotW) == nil)
  }

  // ---------------------------------------------------------------- G6 价格轴

  @Test("G6：竖拖缩放后按下点的价格还在原来那个 y 上", arguments: PriceMode.allCases)
  func priceAxisKeepsAnchor(_ mode: PriceMode) {
    let s = fixture()
    let v = startView(s)
    let pane = Pane(indicator: nil, y: 0, h: 420)
    let style = CandleStyle.default
    func range(_ t: PriceTransform) -> PriceRange {
      priceRange(view: v, series: s, style: style, transform: t)
    }
    var t0 = PriceTransform(mode: mode)
    let y = 130.0
    let anchor = pOf(y, pane: pane, range: range(t0), mode: mode)
    for dy in [-260.0, -80, -10, 10, 80, 260] {
      var t = t0
      t.zoom = PriceAnchor.zoom(from: t0.zoom, dy: dy)
      t.shift = PriceAnchor.shift(
        keeping: anchor, at: y, pane: pane, mode: mode, zoom: t.zoom,
        rangeFor: { sh in
          var probe = t
          probe.shift = sh
          return range(probe)
        })
      let got = yOf(anchor, pane: pane, range: range(t), mode: mode)
      #expect(abs(got - y) < 1e-6, "\(mode) dy=\(dy)：按下点从 \(y) 跑到 \(got)")
    }
    t0.zoom = 1
  }

  @Test("G6：缩放倍数卡在 0.25…6")
  func priceZoomClamped() {
    #expect(PriceAnchor.zoom(from: 1, dy: -5000) == 6)
    #expect(PriceAnchor.zoom(from: 1, dy: 5000) == 0.25)
    #expect(abs(PriceAnchor.zoom(from: 1, dy: 0) - 1) < 1e-12)
  }

  // ---------------------------------------------------------------- G7 时间轴

  @Test("G7：横拖时间轴，按下点的时间不动")
  func timeAxisKeepsAnchor() {
    let s = fixture()
    let v0 = startView(s)
    let anchorPx = 220.0
    let t0 = v0.t(atX: anchorPx, plotW: plotW)
    for dx in [-300.0, -60, 60, 300] {
      let v = ViewMath.zoom(
        v0, factor: PriceAnchor.spanFactor(dx: dx), anchorPx: anchorPx, plotW: plotW)
      #expect(abs(v.x(t0, plotW: plotW) - anchorPx) < 1e-9, "dx=\(dx) 锚点跑了")
      // 往左拖看得更长，往右拖看得更细。
      #expect((v.span > v0.span) == (dx < 0), "dx=\(dx) 缩放方向反了")
    }
  }

  // ---------------------------------------------------------------- G9 补历史

  @Test("G9：左缘进到头部 200 根以内才喊补历史")
  func historyTrigger() {
    let s = fixture()
    let step = Double(s.step)
    let first = Double(s.firstTime)
    // 阈值看的是**左缘**：`from = to - span`，所以 to 要算上 span 才落进 200 根以内。
    let inside = ViewWindow(to: first + 200 * step, span: 60 * step)
    let outside = ViewWindow(to: first + 900 * step, span: 60 * step)
    #expect(ViewMath.needsMoreHistory(inside, series: s))
    #expect(!ViewMath.needsMoreHistory(outside, series: s))
  }
}
