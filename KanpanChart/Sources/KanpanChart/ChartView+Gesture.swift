import CoreGraphics
import Foundation
import KanpanCore
import QuartzCore
import UIKit

// MARK: - 手势状态

/// 一次手势从按下到抬手之间要记住的东西（§7、§13 G1–G15）。
///
/// 不用 `UIGestureRecognizer`：那套有自己的 slop、长按时长和互斥策略，和原型的
/// `pointerdown/move/up` 对不上，G10 要求的「捏合中途抬一根手指变拖动不跳」在
/// recognizer 之间转交时也很难做到无缝。直接接 `touches*`，一条路照着原型抄。
@MainActor
final class GestureState {
  enum Mode {
    /// 图上单指：拖图；十字线在的时候是移线。
    case pan
    /// 双指缩放。
    case pinch
    /// 右侧价格轴：竖拖缩放价格。
    case axisPrice
    /// 底部时间轴：横拖缩放时间。
    case axisTime
  }

  var mode: Mode?
  /// 按住的手指，按落下顺序。UIKit 不给 pointerId，靠对象身份认人。
  var touches: [UITouch] = []

  /// 按下那一刻的全部快照。整场手势只读这一份，不逐帧累加——累加会把浮点误差
  /// 攒进视野里，先捏开再捏拢就回不到原位（G3 要求误差 < 0.01）。
  var startPoint: CGPoint = .zero
  var startView = ViewWindow(from: 0, to: 1)
  var startTransform = PriceTransform()
  var startAtMs: Double = 0
  /// 按下点上的价格，价格轴拖要把它钉住。
  var anchorPrice: Double = 0

  /// 双指快照：初始间距与中点。
  var pinchD0: Double = 0
  var pinchMid0: Double = 0

  /// 这次手势总共动了多远（取最大值，不是最后的位移）。判轻点、判长按取消都看它。
  var moved: Double = 0
  var velocity = VelocityTracker()
  /// 最后一次 move 的时刻，用来算「手指停下来之后才松手」那种不该甩的情况。
  var lastMoveMs: Double = 0
  var longPress: DispatchWorkItem?
  var lastTapMs: Double = 0
  /// 上一帧磁吸吸住的那根，换根才震一下。
  var lastMagnetIndex: Int = -1
  /// 已经喊过补历史了；序列长出来之前不重复喊。
  var askedHistory = false
  /// 上一次缩放有没有顶到边界，用来只在「刚撞上」那一下震。
  var wasAtZoomLimit = false

  func reset() {
    mode = nil
    moved = 0
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
    gesture.startAtMs = now
    gesture.lastMoveMs = now
    gesture.velocity.add(x: Double(q.x), t: now)

    // 轴的判定顺序照原型：先看右侧价格轴，右下角那块重叠区归价格轴。
    if Double(q.x) > L.plotW {
      gesture.mode = .axisPrice
      gesture.anchorPrice = price(atY: Double(q.y))
      return
    }
    if Double(q.y) > L.timeY {
      gesture.mode = .axisTime
      return
    }

    gesture.mode = .pan
    scheduleLongPress(at: q)
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
    gesture.lastMoveMs = now

    switch mode {
    case .pinch: break
    case .axisPrice: dragPriceAxis(dy: dy, L: L)
    case .axisTime: dragTimeAxis(dx: dx, L: L)
    case .pan:
      if state?.crosshair != nil {
        moveCrosshair(to: q, L: L)
      } else {
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
    let now = Self.ms(event)
    let wasPinch = gesture.mode == .pinch
    let liftedAll = gesture.touches.allSatisfy { touches.contains($0) }
    gesture.touches.removeAll { touches.contains($0) }
    gesture.cancelLongPress()

    if wasPinch {
      if gesture.touches.count >= 2 {
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
        gesture.startAtMs = now
        gesture.lastMoveMs = now
        gesture.velocity.add(x: Double(q.x), t: now)
        _ = L
        return
      }
      gesture.reset()
      settleView()
      return
    }

    guard liftedAll || gesture.touches.isEmpty else { return }
    let mode = gesture.mode
    let moved = gesture.moved
    let v = gesture.velocity.velocity
    let gap = now - gesture.lastMoveMs
    gesture.reset()

    if cancelled {
      settleView()
      return
    }

    if mode == .pan, moved < Chart.panSlopPt * 2 {
      handleTap(at: now)
      return
    }
    if mode == .axisPrice, moved < Chart.panSlopPt * 2 {
      handleAxisTap(at: now)
      return
    }
    if mode == .pan, state?.crosshair == nil {
      startFling(speed: v, gapMs: gap)
      return
    }
    settleView()
  }

  // MARK: - 拖

  /// 单指拖图（G1）。横向平移视野，纵向超过 14pt 才顺带平移价格——原型这个阈值
  /// 是为了「想横拖的时候手指难免带点竖向抖动」，别一抖价格就跑。
  private func panPlot(dx: Double, dy: Double, L: Layout) {
    guard var s = state else { return }
    let shifted = gesture.startView.dragged(byFingerPx: dx, plotW: L.plotW)
    s.view = clamp(shifted, plotW: L.plotW, soft: true)
    if abs(dy) > 14 {
      s.price.shift = gesture.startTransform.shift - dy / (L.main.h * 2)
    }
    state = s
    viewDidChange(s.view)
  }

  /// 价格轴竖拖（G6）：缩放 + 解出让按下点价格不动的 `shift`。
  private func dragPriceAxis(dy: Double, L: Layout) {
    guard var s = state, let r = renderer else { return }
    var t = gesture.startTransform
    t.zoom = PriceAnchor.zoom(from: gesture.startTransform.zoom, dy: dy)
    let size = bounds.size
    t.shift = PriceAnchor.shift(
      keeping: gesture.anchorPrice, at: Double(gesture.startPoint.y), pane: L.main,
      mode: t.mode, zoom: t.zoom,
      rangeFor: { sh in
        var probe = t
        probe.shift = sh
        return r.priceRange(size: size, transform: probe)
      })
    s.price = t
    state = s
  }

  /// 时间轴横拖（G7）：以按下点为锚缩放窗宽。原型没有这条，见 `PriceAnchor.spanFactor`。
  private func dragTimeAxis(dx: Double, L: Layout) {
    guard var s = state else { return }
    let zoomed = ViewMath.zoom(
      gesture.startView, factor: PriceAnchor.spanFactor(dx: dx),
      anchorPx: Double(gesture.startPoint.x), plotW: L.plotW)
    s.view = clamp(zoomed, plotW: L.plotW, soft: true)
    state = s
    viewDidChange(s.view)
    reportZoomLimit(s.view, L: L)
  }

  // MARK: - 捏

  private func beginPinch(L: Layout) {
    guard gesture.touches.count >= 2 else { return }
    let (d, m) = twoFinger()
    gesture.cancelLongPress()
    gesture.mode = .pinch
    gesture.startView = state?.view ?? gesture.startView
    gesture.pinchD0 = max(Chart.pinchMinPx, d)
    gesture.pinchMid0 = m
    gesture.moved = .greatestFiniteMagnitude   // 捏过就不可能是轻点
    _ = L
  }

  private func updatePinch(L: Layout) {
    guard var s = state else { return }
    let (d, m) = twoFinger()
    let v = ViewMath.pinch(
      from0: gesture.startView.from, span0: gesture.startView.span,
      d0: gesture.pinchD0, d: max(Chart.pinchMinPx, d),
      mid0Px: gesture.pinchMid0, plotW: L.plotW)
    // 中点自己也会漂（两指整体平移），按当前中点把视野拖回去，两指中间那根就真不动了。
    let follow = v.dragged(byFingerPx: m - gesture.pinchMid0, plotW: L.plotW)
    s.view = clamp(follow, plotW: L.plotW, soft: true)
    state = s
    viewDidChange(s.view)
    reportZoomLimit(s.view, L: L)
  }

  private func twoFinger() -> (d: Double, mid: Double) {
    let a = gesture.touches[0].location(in: self)
    let b = gesture.touches[1].location(in: self)
    let dx = Double(a.x - b.x), dy = Double(a.y - b.y)
    return ((dx * dx + dy * dy).squareRoot(), Double(a.x + b.x) / 2)
  }

  /// 缩放顶到 0.4 / 40 那一下震一次，松开再撞才震第二次（G11 的 rigid）。
  private func reportZoomLimit(_ v: ViewWindow, L: Layout) {
    guard let s = state, s.series.count > 0 else { return }
    let sp = v.barSpacing(step: s.series.step, plotW: L.plotW)
    let atLimit = sp <= Chart.minBarSpacing * 1.001 || sp >= Chart.maxBarSpacing * 0.999
    if atLimit && !gesture.wasAtZoomLimit { Haptics.boundary() }
    gesture.wasAtZoomLimit = atLimit
  }

  // MARK: - 十字线

  private func scheduleLongPress(at q: CGPoint) {
    let work = DispatchWorkItem { [weak self] in
      guard let self, let L = self.chartLayout else { return }
      self.gesture.longPress = nil
      guard self.gesture.moved <= Chart.longPressSlopPt else { return }
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
    var c = Crosshair(index: i, t: t, price: price(atY: Double(q.y)))
    if s.magnet, let p = c.price {
      // 竖线吸根中心由渲染器按 `index` 画；横线在这儿吸到最近的开高低收。
      c.price = nearestOHLC(p, at: i, in: s.series)
    }
    let changed = s.crosshair?.index != i
    s.crosshair = c
    state = s
    if changed && s.magnet && gesture.lastMagnetIndex >= 0 { Haptics.magnetTick() }
    gesture.lastMagnetIndex = i
    onCrosshairChanged?(c)
  }

  private func nearestOHLC(_ p: Double, at i: Int, in b: BarSeries) -> Double {
    let cands = [b.open[i], b.high[i], b.low[i], b.close[i]]
    return cands.min(by: { abs($0 - p) < abs($1 - p) }) ?? p
  }

  /// 清掉十字线。品种 / 周期切换、面板弹出时外面也会叫。
  public func clearCrosshair() {
    guard var s = state, s.crosshair != nil else { return }
    s.crosshair = nil
    state = s
    gesture.lastMagnetIndex = -1
    onCrosshairChanged?(nil)
  }

  // MARK: - 轻点与双击

  private func handleTap(at now: Double) {
    if now - gesture.lastTapMs < Chart.doubleTapMs {
      gesture.lastTapMs = 0
      resetView()
      return
    }
    gesture.lastTapMs = now
    if state?.crosshair != nil {
      clearCrosshair()
    } else {
      onTapped?()
    }
  }

  /// 价格轴双击复位到自动范围（G6）。
  private func handleAxisTap(at now: Double) {
    if now - gesture.lastTapMs < Chart.doubleTapMs {
      gesture.lastTapMs = 0
      guard var s = state else { return }
      s.price.reset()
      state = s
      return
    }
    gesture.lastTapMs = now
  }

  /// 双击图面：回到默认视野，价格轴也一并复位（原型 `resetView`）。
  public func resetView() {
    guard var s = state, let L = chartLayout, s.series.count > 0 else { return }
    s.view = ViewMath.reset(series: s.series, plotW: L.plotW, spacing: s.style.spacing)
    s.price.reset()
    s.crosshair = nil
    state = s
    viewDidChange(s.view)
    onCrosshairChanged?(nil)
  }

  /// 「回到最新」（G14）：滑回右边缘。
  public func scrollToLatest(animated: Bool = true) {
    guard var s = state, let L = chartLayout, s.series.count > 0 else { return }
    let target = ViewMath.reset(
      series: s.series, plotW: L.plotW,
      spacing: s.view.barSpacing(step: s.series.step, plotW: L.plotW))
    guard animated, !Haptics.reduceMotion else {
      s.view = target
      state = s
      viewDidChange(target)
      return
    }
    animate(from: s.view, to: target)
  }

  /// 末根还在视野里吗——「回到最新」按钮的显隐看它（G14）。
  public var isAtLatest: Bool {
    guard let s = state, s.series.count > 0 else { return true }
    return s.view.to >= Double(s.series.lastTime)
  }

  // MARK: - 惯性与回弹

  private func startFling(speed: Double, gapMs: Double) {
    guard let s = state, let L = chartLayout else { return }
    // G12：系统开了「减少动效」就不滑行，抬手即停，其余功能不变。
    guard !Haptics.reduceMotion,
      let run = FlingRun(
        speedPxPerMs: speed, gapMs: gapMs, start: s.view, plotW: L.plotW)
    else {
      settleView()
      return
    }
    let t0 = CACurrentMediaTime()
    animation = { [weak self] now in
      guard let self, var cur = self.state else { return true }
      let (v, done) = run.frame(elapsedMs: (now - t0) * 1000)
      cur.view = self.clamp(v, plotW: L.plotW, soft: false)
      self.state = cur
      self.viewDidChange(cur.view)
      if done { self.settleView() }
      return done
    }
  }

  /// 松手回弹（G5）。已经在界内就什么都不做。
  private func settleView() {
    guard let s = state, let L = chartLayout, s.series.count > 0 else { return }
    guard let target = Settle.target(s.view, series: s.series, plotW: L.plotW) else {
      onViewChanged?(s.view)
      return
    }
    guard !Haptics.reduceMotion else {
      var cur = s
      cur.view = target
      state = cur
      viewDidChange(target)
      return
    }
    animate(from: s.view, to: target)
  }

  private func animate(from a: ViewWindow, to b: ViewWindow) {
    let t0 = CACurrentMediaTime()
    animation = { [weak self] now in
      guard let self, var cur = self.state else { return true }
      let (v, done) = Settle.frame(from: a, to: b, elapsedMs: (now - t0) * 1000)
      cur.view = v
      self.state = cur
      self.viewDidChange(v)
      return done
    }
  }

  // MARK: - 杂项

  private func clamp(_ v: ViewWindow, plotW: Double, soft: Bool) -> ViewWindow {
    guard let s = state else { return v }
    return clampView(v, series: s.series, plotW: plotW, soft: soft)
  }

  /// 视野变了之后统一走这里：通知外面 + 判断该不该补历史。
  private func viewDidChange(_ v: ViewWindow) {
    onViewChanged?(v)
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
  private func price(atY y: Double) -> Double {
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
