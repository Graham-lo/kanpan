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
  /// 这一轮手势是从**捏合**降下来的（捏合中途抬掉一根，剩下那根接着拖）。
  ///
  /// 降下来之后 `reset()` 把 `moved` 清了零、模式换成 `.pan`，于是「原地抬起剩下那根」
  /// 完全长得像一次轻点——图上凭空多出一条十字线，`onTapped` 也白响一次（A-03）。
  /// 剩下那根手指照常能拖（语义不变），但这一轮**不许再被判成轻点**。
  var cameFromPinch = false
  var directionChosen = false
  var axisStarted = false
  /// 上一次价格轴轻点：什么时候、点在哪儿。两样都要，见 `handleAxisTap`（A-09）。
  var lastAxisTap: (ms: Double, y: Double)?
  /// 上一次画布（非轴）轻点：什么时候、点在哪儿。凑成双击就回到最新并自动贴合（P2.11）。
  var lastPlotTap: (ms: Double, x: Double, y: Double)?
  /// 这次手势总共动了多远（取最大值，不是最后的位移）。判轻点、判长按取消都看它。
  var moved: Double = 0
  var velocity = VelocityTracker()
  /// 最后一次 move 的时刻，用来算「手指停下来之后才松手」那种不该甩的情况。
  var longPressActivated = false
  var longPress: DispatchWorkItem?
  /// 已经喊过补历史了；序列长出来之前不重复喊。
  var askedHistory = false
  /// 上一次缩放有没有顶到边界，用来只在「刚撞上」那一下震。
  var wasAtZoomLimit = false

  func reset() {
    mode = nil
    longPressActivated = false
    moved = 0
    pinchActive = false
    cameFromPinch = false
    directionChosen = false
    axisStarted = false
    velocity.reset()
    cancelLongPress()
  }

  /// 价格轴双击的候选到此为止。
  ///
  /// `reset()` 有意不清 `lastAxisTap`——双击本来就横跨两次触摸序列，清了就永远凑不成对。
  /// 但换品种、换周期、视图离屏、状态清空这些事一发生，上一次点的那下就跟现在这张图
  /// 没关系了，必须在这儿断掉（A-09）。
  func endAxisTapCandidate() {
    lastAxisTap = nil
    lastPlotTap = nil
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
    // 补历史的门是「一轮手势只喊一次」，不是「这辈子只喊一次」：上一轮喊出去的那次
    // 要是失败了（断网、接口报错），序列没长、`needsMoreHistory` 还成立，门却一直关着——
    // 用户在左缘再怎么拖都不会再请求一次，除非他先滑走再滑回来。手指重新落下就是
    // 一次新的意图，门在这儿重新打开；一轮之内仍然只喊一次，不会每帧重复请求（A.5 用例 13）。
    gesture.askedHistory = false
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
    // 拎着已经在图上的十字线走，和长按新出一条十字线是同一件事，一样要钉住坐标。
    if gesture.mode == .crosshair { beginAxisFreeze() }
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
    if gesture.touches.isEmpty {
      // 解钉要排在「这次交互结束」之前：外面收到结束回调就会去落盘视野，
      // 得让它拿到追平之后的那一份。
      endAxisFreeze()
      onInteractionEnded?()
    }
  }

  private func processTouchEnd(_ touches: Set<UITouch>, event: UIEvent?, cancelled: Bool) {
    let now = Self.ms(event)
    let wasPinch = gesture.mode == .pinch
    let endPoint = touches.first?.location(in: self) ?? gesture.startPoint
    // A-09：双击候选只在「连着来的两次轴上轻点」之间传递。先摘下来再清掉——
    // 这一轮但凡不是轴上轻点（捏合、拖图、长按十字线、被系统打断……），它就作废了，
    // 否则「点一下轴 → 拖半天图 → 再点一下轴」会被拼成双击，主图莫名其妙上下翻转。
    let axisTapCandidate = gesture.lastAxisTap
    gesture.lastAxisTap = nil
    // 画布双击同理（P2.11）：候选只在连着的两次画布轻点之间传递。
    let plotTapCandidate = gesture.lastPlotTap
    gesture.lastPlotTap = nil
    // A-04：不管下面走哪条 early return，最后一根手指离开画布时**几何上的收尾必须做完**。
    // `touchesBegan` 一按下就把 `animation` 掐了；这一下要是正好落在回弹中途，视野就停在
    // 硬夹之外的半途，而轻点 / 长按 / 轴双击 /「A」徽章这几条分支各自 return，没人管它——
    // 那片弹性空白就永久留在图上了。业务可以不做，几何不能不收。
    // `animation != nil` 说明这条分支自己已经起了动画（甩出去、回弹），别去打断它。
    defer { if gesture.touches.isEmpty, animation == nil { settleGeometry() } }
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
        // 但这一轮的身世要留着：原地抬起剩下那根手指不是轻点（A-03）。
        gesture.cameFromPinch = true
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
    let cameFromPinch = gesture.cameFromPinch
    // 抬手位置要在 `gesture.reset()` 之前拿——「A」徽章判「手指有没有跑出去」要用。
    gesture.velocity.add(x: Double(endPoint.x), t: now)
    let v = gesture.velocity.velocity
    gesture.reset()

    if cancelled {
      settleView()
      return
    }

    if wasLongPress { finishCrosshairSelection(); return }
    // 捏合降下来的那一轮不判轻点：`reset()` 刚把 `moved` 清零，原地抬手看上去和轻点
    // 一模一样，但用户的意思是「结束这次缩放」，不是「点一下图」（A-03）。
    if (mode == .pan || mode == .crosshair), moved < Chart.panSlopPt * 2, !cameFromPinch {
      handleTap(at: now, previous: plotTapCandidate)
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
      handleAxisTap(at: now, point: endPoint, previous: axisTapCandidate)
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
    // 捏合就是冲着视野来的，这时候还钉着等于把缩放整个吞掉。
    cancelAxisFreeze()
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
    // 缩放要越过死区才认：两指之间那点抖动不该被读成缩放。但**平移不看这个门槛**——
    // 两指保持距离一起往旁边挪，那就是明明白白的平移，从前它被这条 `return` 整个吃掉，
    // 于是「两指按住图挪」纹丝不动，非得先捏一下改了倍数才肯跟着走（A-06）。
    // 死区期间 `pinchD0` 不跟着每一帧走：跟了就永远越不过门槛（慢慢撑开等于没撑）。
    if !gesture.pinchActive {
      guard abs(d - gesture.pinchD0) > 2 * Chart.panSlopPt else {
        panPinch(mid: m, L: L)
        return
      }
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

  /// 两指整体位移：中点挪了多少，图就跟着挪多少（A-06）。
  ///
  /// 和捏合里那段平移的差别只有一处：这里不做 `mode4`（视野右缘贴着末根时按住不动）。
  /// 那条规矩是给**缩放**用的——在最新位置捏合时把末根钉住，中点的漂移不算数；
  /// 可若把它套到纯平移上，就成了「停在最新时两指怎么拖都不动」，正是要修的那个毛病。
  /// 纵向一点不碰：两指平移只改时间窗，价格轴归价格轴的手势管。
  private func panPinch(mid m: Double, L: Layout) {
    defer { gesture.pinchMid0 = m }
    let dx = m - gesture.pinchMid0
    guard var s = state, abs(dx) > 0 else { return }
    s.view = clamp(s.view.dragged(byFingerPx: dx, plotW: L.plotW), plotW: L.plotW)
    state = s
    viewDidChange(s.view)
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
      // 十字线一出来就把坐标钉住：接下来这段跟手的移动里，新 K 线到货也好、
      // 新高新低也好，都不许把手指底下那根 K 线挪走（见 `beginAxisFreeze`）。
      self.beginAxisFreeze()
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
    s.crosshair = c
    // 回调由 `state` 的 setter 统一发（`adopt` 里那一句）。这儿不再补一发：同一份
    // 十字线连送两次，外面每收一次就重算一遍读数——跟手时那是白白翻倍的一摊活。
    state = s
    // 这儿从前每跨一根 K 线就 `Haptics.magnetTick()` 一次，没有任何节流：手指横着
    // 一扫过去几十根，那串 selection 触感连成一片嗡嗡响，像电动牙刷。触感只留给
    // **离散事件**——十字线出现（`scheduleLongPress`）、缩放顶到边界（`reportZoomLimit`）、
    // 画线落点（`ChartView+Drawing`）。「跟着手指连续变化」的过程一律不震。
  }

  /// Android M.g/q12: close mode snaps only after release, not during selection movement.
  private func finishCrosshairSelection() {
    guard var s = state, s.options.crossPrice == .close, var cross = s.crosshair,
          cross.pane == nil, s.series.close.indices.contains(cross.index) else { return }
    cross.price = nil
    s.crosshair = cross
    state = s
  }

  /// 把十字线挪到隔壁那一根（`-1` = 上一根，`+1` = 下一根）。
  ///
  /// 给图**外面**那两颗「‹ 上一根 / 下一根 ›」用（§P3-7）。画布上不许浮控件，所以
  /// 这两颗长在读数行右端；它们要做的事手指做不到——在一根 K 线只有几个点宽的时候
  /// 精确地挪一根。
  ///
  /// 价格那一维照十字线自己的规矩走：贴着收盘价（磁吸开着、或者本来就贴着收盘）就
  /// 继续贴着新的那一根，人手动摆在某个价位上的就保持那个价位不动——挪的是「哪一根」，
  /// 不是「哪个价」。到头了就停在头上，不循环。副图上的十字线同理只换根。
  ///
  /// 视野不跟着走：真挪到屏幕外面去了才把视野推一根，让那根留在眼前。
  public func moveCrosshair(by step: Int) {
    guard step != 0, var s = state, s.series.count > 0, var c = s.crosshair else { return }
    let next = c.index + step
    guard s.series.close.indices.contains(next) else { return }
    let wasOnClose = c.pane == nil && c.price != nil
      && s.series.close.indices.contains(c.index)
      && abs((c.price ?? 0) - s.series.close[c.index]) < .ulpOfOne
    c.index = next
    // 关掉磁吸时竖线本来停在某个时刻上（`t`），挪根之后那个时刻属于上一根，
    // 留着它线就还站在原地。清掉 = 用新那根的中心，这正是「挪了一根」该有的样子。
    c.t = nil
    if c.pane == nil, s.magnet || wasOnClose { c.price = s.series.close[next] }
    s.crosshair = c
    // 挪出屏幕就把视野跟着推：人按的是「下一根」，结果那一根画在屏幕外面，
    // 等于什么都没看到。推到那条边的里侧一点点，不重新居中——视野大幅跳动比不跳更晕。
    if let L = chartLayout, L.plotW > 0 {
      let x = s.view.x(Double(s.series.time(at: next)), plotW: L.plotW)
      let inset = min(40, L.plotW * 0.1)
      if x < inset || x > L.plotW - inset {
        let dx = x < inset ? x - inset : x - (L.plotW - inset)
        s.view = clampView(s.view.shifted(byPx: dx, plotW: L.plotW),
                           series: s.series, plotW: L.plotW, anchor: s.options.anchor)
      }
    }
    state = s
    Haptics.magnetTick()
  }

  /// 清掉十字线。品种 / 周期切换、面板弹出时外面也会叫。
  public func clearCrosshair() {
    guard var s = state, s.crosshair != nil else { return }
    s.crosshair = nil
    // 同上：`state` 的 setter 会把这一下清空回调出去，这儿不必再发一遍。
    state = s
  }

  // MARK: - 轻点与双击

  /// 画布轻点 / 双击（P2.11）。
  ///
  /// 单击照旧**立刻**开关十字线——不等「看看是不是双击」，所以单击手感一点不慢。
  /// 双击 = 回到最新并恢复自动纵向贴合：第一下已经开了十字线也没关系，第二下一并收掉。
  /// 「连着的两下」和价格轴双击同一个尺度：300ms 以内、相距不超过 44pt。
  private func handleTap(at now: Double, previous: (ms: Double, x: Double, y: Double)?) {
    let p = gesture.startPoint
    let isDouble = previous.map {
      now - $0.ms < 300 && hypot(Double(p.x) - $0.x, Double(p.y) - $0.y) < 44
    } ?? false
    guard !isDouble else {
      gesture.lastPlotTap = nil
      if state?.crosshair != nil { clearCrosshair() }
      resetPriceScale()
      scrollToLatest()
      return
    }
    gesture.lastPlotTap = (ms: now, x: Double(p.x), y: Double(p.y))
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
  private func handleAxisTap(at now: Double, point: CGPoint, previous: (ms: Double, y: Double)?) {
    guard let L = chartLayout, gesture.startPoint.y < L.mainH else { return }
    // 「连着来的两下」要同时满足两件事：时间上 300ms 以内，位置上不超过一个手指的宽度
    // （44pt，和系统的最小触控目标同一个尺度）。只看时间不行——轴很长，从轴顶点一下、
    // 半秒后在轴底又点一下，那是两次「恢复自动纵向缩放」，不是一次翻转（A-09）。
    // 中间插进任何别的手势时，候选在 `processTouchEnd` 里就已经作废了。
    let isDouble = previous.map { now - $0.ms < 300 && abs(Double(point.y) - $0.y) < 44 } ?? false
    guard isDouble else {
      gesture.lastAxisTap = (ms: now, y: Double(point.y))
      resetPriceScale()
      return
    }
    gesture.lastAxisTap = nil
    guard var s = state, s.options.allowMainInversion else { return }
    s.price.inverted.toggle()
    s.price.reset()
    state = s
    // 翻过去要说一句：上下颠倒的 K 线太反直觉，不告诉他怎么翻回来他会以为图坏了。
    // 翻回来什么都不说——那一句「主图已翻回正常方向」是纯报喜：他刚做完这个动作，
    // 图当场就正过来了，再念一遍只是挡住一行 K 线（§P3-8）。
    if s.price.inverted { onNotice?("主图已上下翻转，再双击价格轴翻回来") }
  }

  /// 把视野重置回出厂根宽。**程序动作，不算用户意图**——它硬写着
  /// `AICoinBehavior.initialSpacing`，报成用户意图就等于替用户把他的宽度改成出厂值。
  ///
  /// 顺带一句：全仓（`Kanpan/Kanpan` 与 `KanpanChart/Sources`）目前**一个调用方都没有**。
  /// 留着是因为它是 `public` API，删不删是另一轮的事。
  public func resetView() {
    cancelAxisFreeze()
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
    cancelAxisFreeze()
    guard var s = state, let L = chartLayout, s.series.count > 0 else { return }
    let target = ViewMath.reset(
      series: s.series, plotW: L.plotW,
      spacing: s.view.barSpacing(step: s.series.step, plotW: L.plotW),
      anchor: s.options.anchor)
    // 不在窗口上挂动画会被 `animation` 的 didSet 直接丢掉，那就一步到位。
    guard animated, window != nil, !Haptics.reduceMotion else {
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

  /// 几何收尾：视野已经落在硬夹之内就什么都不做，在外面就把它送回去（A-04）。
  ///
  /// 和 `settleView()` 的分工：那个是「该回弹就回弹」的动作，这个是「手指都走了，
  /// 保证图不停在半途」的兜底。没超界就一句不响，免得每次轻点都白发一轮视野变更通知。
  private func settleGeometry() {
    guard let s = state, let L = chartLayout, s.view.span > 0 else { return }
    let target = clamp(s.view, plotW: L.plotW)
    let offPx = abs(target.to - s.view.to) / s.view.span * L.plotW
    guard offPx > 0.01 || abs(target.span - s.view.span) / s.view.span > 1e-9 else { return }
    settleView()
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

  // MARK: - 拖动期间的坐标冻结

  /// 手指按住一个**目标**的这段时间里，把两根轴都钉死。
  ///
  /// 「目标」指十字线和画线的锚点——它们都是「手指指着图上某一个点」。这类交互里
  /// 用户的参照系是屏幕上那一处，而图底下的两根轴却在各自动：1 分钟图上一根新 K 线
  /// 到货，`AICoinBehavior.reconcile` 把视野右移一格；行情走出新高新低，自动纵轴重算
  /// 价格区间。两者都会让手指底下那根 K 线（那条线）自己挪走，看着就像线在跑。
  ///
  /// 钉住的只有**视野**和**主图价格区间**这两样：新 K 线照常进 `series`，指标照常算，
  /// 实时价照常跳。抬手那一刻 `endAxisFreeze` 一次追平，不留台阶。
  func beginAxisFreeze() {
    guard frozenAxes == nil, let s = state, !s.series.isEmpty,
          let L = chartLayout, L.plotW > 0, s.view.span > 0,
          let range = chartPriceRange else { return }
    let spacing = s.view.barSpacing(step: s.series.step, plotW: L.plotW)
    let latest = ViewMath.reset(series: s.series, plotW: L.plotW, spacing: spacing,
                                anchor: s.options.anchor)
    // 判据和 `reconcile` 自己那条一模一样：贴着末根才叫「跟着最新」，抬手才要追。
    // 在看历史的图本来就不会被新 K 线推着走，追平反而会把人踢回右边。
    let following = abs(s.view.to - latest.to) / s.view.span * L.plotW < spacing
    frozenAxes = FrozenAxes(view: s.view, range: range, followingLatest: following)
    pinPriceRange(range)
  }

  /// 抬手：解钉，并把冻结期间欠下的那点位移一次补上。
  ///
  /// 必须显式追平，光解钉是回不去的：`reconcile` 只在视野「还贴着末根」时才右移，
  /// 而钉了一整根 K 线之后视野已经差了一格，那条判据从此不成立——不追的话这张图
  /// 就永远停在落后一根的位置上，直到用户自己滑一下。
  func endAxisFreeze() {
    guard let frozen = frozenAxes else { return }
    cancelAxisFreeze()
    guard frozen.followingLatest, var s = state, !s.series.isEmpty,
          let L = chartLayout, L.plotW > 0, s.view.span > 0 else { return }
    let spacing = s.view.barSpacing(step: s.series.step, plotW: L.plotW)
    let latest = ViewMath.reset(series: s.series, plotW: L.plotW, spacing: spacing,
                                anchor: s.options.anchor)
    guard abs(latest.to - s.view.to) / s.view.span * L.plotW > 0.01 else { return }
    s.view = latest
    state = s
    // 这一下不是用户在图上捏出来的，是程序替他补的——别污染「用户想要的根宽」那条道。
    viewDidChange(latest, source: .program)
  }

  /// 不追平地解钉。换品种 / 换周期、视图离窗、二指转捏合这些「这张图已经不是刚才那张」
  /// 的场合用它：追平一个早就作废的视野只会更乱。
  func cancelAxisFreeze() {
    guard frozenAxes != nil else { return }
    frozenAxes = nil
    pinPriceRange(nil)
    // 钉子不在 `ChartState` 里，摘掉它不会触发任何脏位，得自己喊一声重画。
    setNeedsRedraw(.all)
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
