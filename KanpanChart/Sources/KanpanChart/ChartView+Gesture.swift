import CoreGraphics
import Foundation
import KanpanCore
import QuartzCore
import UIKit

// MARK: - 手势状态

/// Shared gesture state for every visual skin.
@MainActor
final class GestureState {
  enum Mode {
    /// 图上单指：拖图。
    case pan
    case crosshair
    /// 双指缩放。
    case pinch
    /// 右侧价格轴：竖拖缩放价格。
    case axisPrice
    case subAxis
    /// 手动纵轴平移；自动纵轴的纵向拖动交由父容器。
    case verticalPan
    case parentScroll
    /// 主图底边那个「A」徽章：抬手就把价格轴交还给自动贴合。
    case autoFit
  }

  var mode: Mode?
  /// 按住的手指，按落下顺序。UIKit 不给 pointerId，靠对象身份认人。
  var touches: [UITouch] = []

  /// 按下那一刻的全部快照。整场手势只读这一份，不逐帧累加——累加会把浮点误差
  /// 攒进视野里，先捏开再捏拢就回不到原位（G3 要求误差 < 0.01）。
  var startPoint: CGPoint = .zero
  var startView = ViewWindow(from: 0, to: 1)
  var startTransform = PriceTransform()
  var startRange: PriceRange?
  var trace = ""
  var pinchD0: Double = 0
  var pinchMid0: Double = 0
  var pinchActive = false
  var directionChosen = false
  var axisStarted = false
  var lastAxisTap: Double?
  /// 这次手势总共动了多远（取最大值，不是最后的位移）。判轻点、判长按取消都看它。
  var moved: Double = 0
  var velocity = VelocityTracker()
  /// 最后一次 move 的时刻，用来算「手指停下来之后才松手」那种不该甩的情况。
  var longPressActivated = false
  var longPress: DispatchWorkItem?
  /// 上一帧磁吸吸住的那根，换根才震一下。
  var lastMagnetIndex: Int = -1
  /// 已经喊过补历史了；序列长出来之前不重复喊。
  var askedHistory = false
  /// 上一次缩放有没有顶到边界，用来只在「刚撞上」那一下震。
  var wasAtZoomLimit = false

  func reset() {
    mode = nil
    longPressActivated = false
    moved = 0
    pinchActive = false
    directionChosen = false
    axisStarted = false
    velocity.reset()
    cancelLongPress()
  }

  func cancelLongPress() {
    longPress?.cancel()
    longPress = nil
  }
}

// MARK: - 触摸

extension ChartView {
  /// 图上有没有可操作的内容。空数据时手势整个让开，别在白板上滑出十字线。
  private var gestureReady: Bool {
    state != nil && !(state?.series.isEmpty ?? true) && chartLayout != nil
  }

  private static func ms(_ event: UIEvent?) -> Double {
    (event?.timestamp ?? CACurrentMediaTime()) * 1000
  }

  public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard gestureReady, let L = chartLayout else {
      super.touchesBegan(touches, with: event)
      return
    }
    // 手指一落下动画就停：正在滑行的图被按住应该立刻钉住，不能继续飘。
    animation = nil
    for t in touches where !gesture.touches.contains(t) { gesture.touches.append(t) }
    let now = Self.ms(event)

    if gesture.touches.count >= 2 {
      beginPinch(L: L)
      return
    }

    let q = gesture.touches[0].location(in: self)
    gesture.reset()
    gesture.startPoint = q
    gesture.startView = state?.view ?? gesture.startView
    gesture.startTransform = state?.price ?? PriceTransform()
    gesture.startRange = chartPriceRange
    gesture.velocity.add(x: Double(q.x), t: now)
    // 主图底边那个「A」（回到自动贴合）先截胡：它压在价格轴的可拖区域上，
    // 不先判就永远只会被当成竖拖。手动定标时它才存在。
    if state?.price.isManual == true, L.hitsAutoFit(x: Double(q.x), y: Double(q.y)) {
      gesture.mode = .autoFit
      return
    }

    // Only the main price axis accepts Y scaling.
    if Double(q.x) > L.plotW && Double(q.y) < L.mainH {
      gesture.mode = .axisPrice
      return
    }
    if Double(q.x) > L.plotW {
      gesture.mode = .subAxis
      return
    }
    if Double(q.y) >= L.mainH && Double(q.y) < L.mainH + AICoinBehavior.timeHeight {
      gesture.mode = .parentScroll
      return
    }
    gesture.mode = hitsCrosshairCenter(q) ? .crosshair : .pan
    if state?.crosshair == nil { scheduleLongPress(at: q) }
  }

  public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard gestureReady, let L = chartLayout, let mode = gesture.mode else {
      super.touchesMoved(touches, with: event)
      return
    }
    let now = Self.ms(event)

    if mode == .pinch, gesture.touches.count >= 2 {
      updatePinch(L: L)
      return
    }

    let q = gesture.touches.first?.location(in: self) ?? gesture.startPoint
    let dx = Double(q.x - gesture.startPoint.x)
    let dy = Double(q.y - gesture.startPoint.y)
    gesture.moved = max(gesture.moved, (dx * dx + dy * dy).squareRoot())
    if gesture.moved > Chart.longPressSlopPt { gesture.cancelLongPress() }

    switch mode {
    case .pinch, .autoFit, .subAxis: break
    case .axisPrice: dragPriceAxis(dy: dy, L: L)
    case .verticalPan: panPrice(dy: dy, L: L)
    case .parentScroll: break
    case .crosshair: moveCrosshair(to: q, L: L)
    case .pan:
      do {
        guard gesture.moved >= Chart.panSlopPt else { break }
        if !gesture.directionChosen {
          gesture.directionChosen = true
          if abs(dy) > 1.5 * abs(dx) {
            gesture.mode = gesture.startTransform.isManual && gesture.startPoint.y < L.mainH
              ? .verticalPan : .parentScroll
            if gesture.mode == .verticalPan { panPrice(dy: dy, L: L) }
            break
          }
        }
        clearCrosshair()
        gesture.velocity.add(x: Double(q.x), t: now)
        panPlot(dx: dx, dy: dy, L: L)
      }
    }
  }

  public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    finishTouches(touches, event: event, cancelled: false)
  }

  public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    finishTouches(touches, event: event, cancelled: true)
  }

  private func finishTouches(_ touches: Set<UITouch>, event: UIEvent?, cancelled: Bool) {
    processTouchEnd(touches, event: event, cancelled: cancelled)
    // 手指全离开画布的那一刻 = 这次交互结束（见 `onInteractionEnded`）。
    // `gesture.reset()` 有意不清 `gesture.touches`，所以这一句是可靠的「还有指头按着吗」。
    // 放在正文之后：正文里那几条 early return（捏合中途抬掉一根、还剩指头）本来就不该响。
    if gesture.touches.isEmpty { onInteractionEnded?() }
  }

  private func processTouchEnd(_ touches: Set<UITouch>, event: UIEvent?, cancelled: Bool) {
    let now = Self.ms(event)
    let wasPinch = gesture.mode == .pinch
    let endPoint = touches.first?.location(in: self) ?? gesture.startPoint
    if cancelled {
      gesture.touches.removeAll(); gesture.reset(); animation = nil
      state?.axisScaleAnchor = nil
      settleView()
      return
    }
    let liftedAll = gesture.touches.allSatisfy { touches.contains($0) }
    gesture.touches.removeAll { touches.contains($0) }
    gesture.cancelLongPress()

    if wasPinch {
      if gesture.touches.count >= 2 {
        if let layout = chartLayout { beginPinch(L: layout) }
        return                                   // 三指抬掉一根，剩下的两指接着捏
      }
      if let t = gesture.touches.first, let L = chartLayout {
        // G10：捏合中途抬一根手指要无缝变拖动——以剩下那根的**当前**位置重新起手，
        // 不是拿按下时的位置，否则图会瞬间跳一段。
        let q = t.location(in: self)
        gesture.reset()
        gesture.mode = .pan
        gesture.startPoint = q
        gesture.startView = state?.view ?? gesture.startView
        gesture.startTransform = state?.price ?? PriceTransform()
        gesture.velocity.add(x: Double(q.x), t: now)
        // 框先缓着还给自动贴合，同时剩下那根手指已经能拖了，两件事互不打扰。
        _ = L
        return
      }
      gesture.reset()
      settleView()
      return
    }

    guard liftedAll || gesture.touches.isEmpty else { return }
    let mode = gesture.mode
    state?.axisScaleAnchor = nil
    let wasLongPress = gesture.longPressActivated
    let moved = gesture.moved
    // 抬手位置要在 `gesture.reset()` 之前拿——「A」徽章判「手指有没有跑出去」要用。
    gesture.velocity.add(x: Double(endPoint.x), t: now)
    let v = gesture.velocity.velocity
    gesture.reset()

    if cancelled {
      settleView()
      return
    }

    if wasLongPress { finishCrosshairSelection(); return }
    if (mode == .pan || mode == .crosshair), moved < Chart.panSlopPt * 2 {
      handleTap(at: now)
      return
    }
    if mode == .autoFit {
      // 手指没跑出钮才算数，跟系统按钮一个规矩。
      if moved < Chart.panSlopPt * 2, let L = chartLayout,
        L.hitsAutoFit(x: Double(endPoint.x), y: Double(endPoint.y))
      {
        resetPriceScale()
      }
      return
    }
    if mode == .subAxis, moved < Chart.panSlopPt * 2 {
      if let layout = chartLayout, var s = state, s.options.allowSubInversion,
         let id = layout.panes.first(where: { $0.indicator != nil && endPoint.y >= $0.y && endPoint.y <= $0.y + $0.h })?.indicator {
        if s.subInverted.contains(id) { s.subInverted.remove(id) } else { s.subInverted.insert(id) }
        state = s
      }
      return
    }
    if mode == .axisPrice, moved < Chart.panSlopPt * 2 {
      handleAxisTap(at: now)
      return
    }
    if mode == .pan, state?.crosshair == nil {
      startFling(speed: v)
      return
    }
    finishCrosshairSelection()
    settleView()
  }

  // MARK: - 拖

  /// 两端允许单指弹性留白；历史中途仍沿共享时间映射。
  private func panPlot(dx: Double, dy: Double, L: Layout) {
    guard var s = state else { return }
    s.view = ViewMath.dragging(gesture.startView.dragged(byFingerPx: dx, plotW: L.plotW),
                               series: s.series, plotW: L.plotW, anchor: s.options.anchor)
    state = s
    viewDidChange(s.view)
  }

  private func panPrice(dy: Double, L: Layout) {
    guard var s = state, gesture.startTransform.isManual else { return }
    guard let range = gesture.startRange, let renderer else { return }
    var auto = gesture.startTransform; auto.reset()
    let automatic = renderer.priceRange(size: bounds.size, transform: auto)
    let start = Double(gesture.startPoint.y)
    let delta = pOf(start, pane: L.main, range: range, mode: s.price.mode)
      - pOf(start + dy, pane: L.main, range: range, mode: s.price.mode)
    let center = gesture.startTransform.centerFraction + delta / max(1e-12, automatic.hi - automatic.lo)
    s.price.centerFraction = PriceTransform.clampedCenter(center, zoom: s.price.zoom)
    state = s
  }

  private func dragPriceAxis(dy: Double, L: Layout) {
    guard var s = state, gesture.moved >= Chart.panSlopPt else { return }
    if !gesture.axisStarted {
      gesture.axisStarted = true
      gesture.startPoint.y += dy
      if let range = chartPriceRange { s.axisScaleAnchor = (range.lo + range.hi) / 2 }
      state = s
      return
    }
    s.price.zoom = AICoinBehavior.axisZoom(from: gesture.startTransform.zoom,
                                          dy: dy, height: L.mainH)
    s.price.centerFraction = PriceTransform.clampedCenter(
      gesture.startTransform.centerFraction, zoom: s.price.zoom)
    state = s
  }

  private func beginPinch(L: Layout) {
    guard gesture.touches.count >= 2, gesture.mode != .crosshair else { return }
    clearCrosshair()
    let (d, m) = twoFinger()
    gesture.cancelLongPress()
    state?.axisScaleAnchor = nil
    gesture.mode = .pinch
    gesture.trace = "begin d=\(d)"
    gesture.pinchD0 = d
    gesture.pinchMid0 = m
    gesture.pinchActive = false
    gesture.moved = .greatestFiniteMagnitude
  }

  private func updatePinch(L: Layout) {
    guard var s = state else { return }
    let (d, m) = twoFinger()
    gesture.trace = "move d=\(d) previous=\(gesture.pinchD0) active=\(gesture.pinchActive)"
    guard gesture.pinchD0 > 0 else { gesture.pinchD0 = d; return }
    // 两指太近的那几帧只当噪声，但基准要跟着它走：不跟的话，等间距一跨过门槛，
    // d/d0 会把这一路攒下来的比例一次性甩出去，图会「嘭」地跳一下。
    guard d >= Chart.minPinchSpanPt else {
      gesture.pinchD0 = d; gesture.pinchMid0 = m; gesture.pinchActive = false
      return
    }
    if !gesture.pinchActive {
      guard abs(d - gesture.pinchD0) > 2 * Chart.panSlopPt else { return }
      gesture.pinchActive = true
    }
    let spacing = s.view.barSpacing(step: s.series.step, plotW: L.plotW)
    // Android mode4 aligns the latest column without reserved blank, not any RIGHT boundary.
    let aligned = Double(s.series.lastTime) + Double(s.series.step) / 2
    let mode4 = abs(s.view.to - aligned) / s.view.span * L.plotW < spacing
    let moved = mode4 ? s.view : clamp(s.view.dragged(byFingerPx: m - gesture.pinchMid0, plotW: L.plotW), plotW: L.plotW)
    s.view = ViewMath.scaled(moved, series: s.series, plotW: L.plotW,
                            factor: d / gesture.pinchD0, focus: m, anchor: s.options.anchor)
    gesture.pinchD0 = d
    gesture.pinchMid0 = m
    state = s
    viewDidChange(s.view)
    reportZoomLimit(s.view, L: L)
  }

  private func twoFinger() -> (d: Double, mid: Double) {
    let points = gesture.touches.map { $0.location(in: self) }
    let count = Double(points.count)
    let mx = points.reduce(0) { $0 + Double($1.x) } / count
    let my = points.reduce(0) { $0 + Double($1.y) } / count
    let sx = 2 * points.reduce(0) { $0 + abs(Double($1.x) - mx) } / count
    let sy = 2 * points.reduce(0) { $0 + abs(Double($1.y) - my) } / count
    return (hypot(sx, sy), mx)
  }

  /// 缩放顶到 1.6 / 40 那一下震一次，松开再撞才震第二次（G11 的 rigid）。
  private func reportZoomLimit(_ v: ViewWindow, L: Layout) {
    guard let s = state, s.series.count > 0 else { return }
    let sp = v.barSpacing(step: s.series.step, plotW: L.plotW)
    let atLimit = sp <= Chart.minBarSpacing * 1.001 || sp >= Chart.maxBarSpacing * 0.999
    if atLimit && !gesture.wasAtZoomLimit { Haptics.boundary() }
    gesture.wasAtZoomLimit = atLimit
  }

  // MARK: - 十字线

  /// A native 44 pt touch target around the rendered intersection, not either full line.
  public func hitsCrosshairCenter(_ point: CGPoint) -> Bool {
    guard let center = renderer?.crosshairCenter(size: bounds.size) else { return false }
    return abs(point.x - center.x) <= 22 && abs(point.y - center.y) <= 22
  }

  private func scheduleLongPress(at q: CGPoint) {
    let work = DispatchWorkItem { [weak self] in
      guard let self, let L = self.chartLayout else { return }
      self.gesture.longPress = nil
      guard self.gesture.moved <= Chart.longPressSlopPt else { return }
      self.gesture.longPressActivated = true
      self.gesture.mode = .crosshair
      self.gesture.lastMagnetIndex = -1
      self.moveCrosshair(to: q, L: L)
      Haptics.crosshair()
    }
    gesture.longPress = work
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Chart.longPressMs / 1000, execute: work)
  }

  /// 把十字线摆到手指底下。存的是时间与价格，不是像素（见 `Crosshair`）。
  private func moveCrosshair(to q: CGPoint, L: Layout) {
    guard var s = state, s.series.count > 0 else { return }
    let px = max(0, min(L.plotW, Double(q.x)))
    let t = s.view.t(atX: px, plotW: L.plotW)
    let i = s.series.index(atTime: t)
    var c = Crosshair(index: i, t: nil, price: price(atY: Double(q.y)))
    if let pane = L.panes.dropFirst().first(where: { Double(q.y) >= $0.y && Double(q.y) <= $0.y + $0.h }) {
      c.pane = pane.indicator
      c.price = renderer?.subCrosshairValue(y: Double(q.y), pane: pane)
    } else if s.magnet { c.price = s.series.close[i] }
    let changed = s.crosshair?.index != i
    s.crosshair = c
    // 回调由 `state` 的 setter 统一发（`adopt` 里那一句）。这儿不再补一发：同一份
    // 十字线连送两次，外面每收一次就重算一遍读数——跟手时那是白白翻倍的一摊活。
    state = s
    if changed && s.magnet && gesture.lastMagnetIndex >= 0 { Haptics.magnetTick() }
    gesture.lastMagnetIndex = i
  }

  /// Android M.g/q12: close mode snaps only after release, not during selection movement.
  private func finishCrosshairSelection() {
    guard var s = state, s.options.crossPrice == .close, var cross = s.crosshair,
          cross.pane == nil, s.series.close.indices.contains(cross.index) else { return }
    cross.price = nil
    s.crosshair = cross
    state = s
  }

  /// 清掉十字线。品种 / 周期切换、面板弹出时外面也会叫。
  public func clearCrosshair() {
    guard var s = state, s.crosshair != nil else { return }
    s.crosshair = nil
    // 同上：`state` 的 setter 会把这一下清空回调出去，这儿不必再发一遍。
    state = s
    gesture.lastMagnetIndex = -1
  }

  // MARK: - 轻点与双击

  private func handleTap(at now: Double) {
    if state?.crosshair != nil {
      clearCrosshair()
    } else if let L = chartLayout {
      moveCrosshair(to: gesture.startPoint, L: L)
      finishCrosshairSelection()
      onTapped?()
    }
  }

  /// Restore automatic Y only; historical X and inversion remain unchanged.
  public func resetPriceScale() {
    guard var s = state else { return }
    s.price.reset()
    s.axisScaleAnchor = nil
    state = s
  }

  /// 价格轴上轻点 / 双击。
  ///
  /// 单击 = 恢复自动纵向缩放。安全、可逆、点错了没代价，正好配「轴上拖动改缩放」这个手势。
  ///
  /// 双击 = 主图上下翻转（前提是设置里开了「主轴允许翻转」，默认没开）。翻转会让整张图的
  /// 形态全反过来、副图还不跟着翻，实测一次误触就足以让人以为行情崩了；所以它必须是个
  /// 「我确实要这么干」的手势，而且翻完要说一句——不然用户只知道图不对，不知道怎么翻回去。
  private func handleAxisTap(at now: Double) {
    guard let L = chartLayout, gesture.startPoint.y < L.mainH else { return }
    let isDouble = gesture.lastAxisTap.map { now - $0 < 300 } ?? false
    guard isDouble else {
      gesture.lastAxisTap = now
      resetPriceScale()
      return
    }
    gesture.lastAxisTap = nil
    guard var s = state, s.options.allowMainInversion else { return }
    s.price.inverted.toggle()
    s.price.reset()
    state = s
    onNotice?(s.price.inverted ? "主图已上下翻转，再双击价格轴翻回来" : "主图已翻回正常方向")
  }

  /// 把视野重置回出厂根宽。**程序动作，不算用户意图**——它硬写着
  /// `AICoinBehavior.initialSpacing`，报成用户意图就等于替用户把他的宽度改成出厂值。
  ///
  /// 顺带一句：全仓（`Kanpan/Kanpan` 与 `KanpanChart/Sources`）目前**一个调用方都没有**。
  /// 留着是因为它是 `public` API，删不删是另一轮的事。
  public func resetView() {
    guard var s = state, let L = chartLayout, s.series.count > 0 else { return }
    s.view = ViewMath.reset(
      series: s.series, plotW: L.plotW, spacing: AICoinBehavior.initialSpacing, anchor: s.options.anchor)
    s.price.reset()
    s.crosshair = nil
    state = s
    viewDidChange(s.view, source: .program)
    fireCrosshairChanged(nil)
  }

  /// 「回到最新」（G14）：滑回右边缘。
  public func scrollToLatest(animated: Bool = true) {
    guard var s = state, let L = chartLayout, s.series.count > 0 else { return }
    let target = ViewMath.reset(
      series: s.series, plotW: L.plotW,
      spacing: s.view.barSpacing(step: s.series.step, plotW: L.plotW),
      anchor: s.options.anchor)
    guard animated, !Haptics.reduceMotion else {
      s.view = target
      state = s
      // 「回到最新」只动位置、不动根宽，而且是按钮点出来的程序动作，不是用户在图上捏。
      viewDidChange(target, source: .program)
      return
    }
    animate(from: s.view, to: target, source: .program)
  }

  /// 末根还在视野里吗——「回到最新」按钮的显隐看它（G14）。
  public var isAtLatest: Bool {
    guard let s = state, s.series.count > 0 else { return true }
    return s.view.to >= Double(s.series.lastTime)
  }

  // MARK: - 惯性与回弹

  private func startFling(speed: Double) {
    guard let s = state, let L = chartLayout else { return }
    let settled = clamp(s.view, plotW: L.plotW)
    if abs(s.view.to - settled.to) / s.view.span * L.plotW > 0.01 { settleView(); return }
    // G12：系统开了「减少动效」就不滑行，抬手即停，其余功能不变。
    guard !Haptics.reduceMotion,
      let run = FlingRun(
        speedPxPerMs: speed, start: s.view, plotW: L.plotW)
    else {
      settleView()
      return
    }
    let t0 = CACurrentMediaTime()
    animation = { [weak self] now in
      guard let self, var cur = self.state else { return true }
      let (v, done) = run.frame(elapsedMs: (now - t0) * 1000)
      cur.view = self.clamp(v, plotW: L.plotW)
      let hit = abs(cur.view.to - v.to) / v.span * L.plotW > 0.01
      self.state = cur
      self.viewDidChange(cur.view)
      return done || hit
    }
  }

  /// 两端单指拉出的空白松手回对应边界，历史窗口不被拉回最新。
  private func settleView() {
    guard var s = state, let L = chartLayout else { return }
    let target = clamp(s.view, plotW: L.plotW)
    if !Haptics.reduceMotion, abs(s.view.to - target.to) / s.view.span * L.plotW > 0.01 {
      animate(from: s.view, to: target, rebound: true)
    } else {
      s.view = target; state = s; viewDidChange(s.view)
    }
  }

  private func animate(from a: ViewWindow, to b: ViewWindow, rebound: Bool = false,
                       source: ViewChangeSource = .gesture) {
    let t0 = CACurrentMediaTime()
    animation = { [weak self] now in
      guard let self, var cur = self.state else { return true }
      let elapsed = (now - t0) * 1000
      let (v, done) = rebound ? ViewTransition.rebound(from: a, to: b, elapsedMs: elapsed)
                              : ViewTransition.frame(from: a, to: b, elapsedMs: elapsed)
      cur.view = v
      self.state = cur
      self.viewDidChange(v, source: source)
      return done
    }
  }

  // MARK: - 杂项

  private func clamp(_ v: ViewWindow, plotW: Double) -> ViewWindow {
    guard let s = state else { return v }
    return clampView(v, series: s.series, plotW: plotW, anchor: s.options.anchor)
  }

  /// 这一下视野是谁造成的。见 `ChartView.onUserViewChanged`。
  enum ViewChangeSource { case gesture, program }

  /// 视野变了之后统一走这里：通知外面 + 判断该不该补历史。
  ///
  /// 默认算**用户手上的动作**——这个文件里除了「回到最新」和 `resetView()`，
  /// 其余每一条路（拖、捏、甩、回弹、轴拖）都是手指直接或间接造成的。
  private func viewDidChange(_ v: ViewWindow, source: ViewChangeSource = .gesture) {
    onViewChanged?(v)
    if source == .gesture { onUserViewChanged?(v) }
    guard let s = state else { return }
    if ViewMath.needsMoreHistory(v, series: s.series) {
      if !gesture.askedHistory {
        gesture.askedHistory = true
        onNeedsHistory?()
      }
    } else {
      gesture.askedHistory = false
    }
  }

  /// 主图里某个 y 对应的价格。
  /// 屏幕 y 对应的主图价格。手势和测试都要用（`internal` 是为了后者）。
  func price(atY y: Double) -> Double {
    guard let s = state, let L = chartLayout, let r = chartPriceRange else { return 0 }
    return pOf(y, pane: L.main, range: r, mode: s.price.mode)
  }
}

// MARK: - 触觉

/// 三种触觉各管一件事（G11）：出十字线 light、磁吸换根 selection、缩放到边界 rigid。
///
/// 生成器留着不重建：`prepare()` 之后系统会把 Taptic Engine 预热，每次现 new 一个
/// 第一下会晚几十毫秒，磁吸换根那种连续反馈就会糊成一片。
@MainActor
enum Haptics {
  private static let light = UIImpactFeedbackGenerator(style: .light)
  private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
  private static let selection = UISelectionFeedbackGenerator()

  /// 系统「减少动效」。甩和回弹看它，触觉不看——那是两个开关。
  static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

  static func crosshair() {
    light.prepare()
    light.impactOccurred()
    selection.prepare()          // 接下来多半是磁吸连击，先热起来
  }

  static func magnetTick() { selection.selectionChanged() }

  static func boundary() {
    rigid.prepare()
    rigid.impactOccurred(intensity: 0.7)
  }
}
