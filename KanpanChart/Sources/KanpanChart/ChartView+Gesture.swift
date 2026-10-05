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
  /// 捏合这一轴的基准：两指**横向**张开量 sx、**纵向**张开量 sy（各自 = 2 × 到中点的平均距离）。
  ///
  /// 从前只记一个斜线距离 d = hypot(sx, sy)，两指竖着摆一捏，时间轴也跟着缩——
  /// 人竖着捏是想看价格的细节，不是想改一根 K 线多宽（2026-10-05 P2）。
  var pinchSx0: Double = 0
  var pinchSy0: Double = 0
  var pinchMid0: Double = 0
  var pinchMidY0: Double = 0
  var pinchActive = false
  /// 这一轮捏合缩的是哪根轴。越过死区那一帧定下来，整轮不再改（中途换轴，图会忽横忽竖地抽）。
  enum PinchAxis { case undecided, time, price }
  var pinchAxis: PinchAxis = .undecided
  /// 时间轴：手指「要的」根宽（可越过 [1.6, 40]，见 `ViewMath.softSpacing`）。
  var pinchRawSpacing: Double = 0
  /// 价格轴：越过死区那一刻的倍数、纵向张开量，和两指中点底下那个价位。
  var pinchStartZoom: Double = 1
  var pinchSyStart: Double = 0
  var pinchPrice: Double = 0
  /// 这一轮手势是从**捏合**降下来的（捏合中途抬掉一根，剩下那根接着拖）。
  ///
  /// 降下来之后 `reset()` 把 `moved` 清了零、模式换成 `.pan`，于是「原地抬起剩下那根」
  /// 完全长得像一次轻点——图上凭空多出一条十字线，`onTapped` 也白响一次（A-03）。
  /// 剩下那根手指照常能拖（语义不变），但这一轮**不许再被判成轻点**。
  var cameFromPinch = false
  /// 捏合越过软边界时抬掉一根：图正走着回弹（`settleView`），剩下那根手指先不接管——
  /// 一边弹、一边跟着画面重设起手点，弹完再按它拖（2026-10-05，不再直接吸到边界上）。
  var reboundHandoff = false
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
  /// 拎着十字线走时，交叉点相对手指的那段距离：按下时量一次，之后一路保持——十字线跟着
  /// 手指的位移走，不往手指底下跳，也不被指头挡住。长按新出的十字线就在手指底下，距离是 0。
  var grab: CGVector = .zero
  /// 十字线归哪根手指：进 `.crosshair` 那一刻按着的那根。十字线只跟它走；它抬起来这一轮
  /// 十字线就算放下了——不能让后落下的另一根手指接班，否则十字线会瞬间跳到那根手指底下（审查 B·P3-2）。
  var owner: UITouch?

  func reset() {
    mode = nil
    grab = .zero
    owner = nil
    longPressActivated = false
    moved = 0
    pinchActive = false
    pinchAxis = .undecided
    cameFromPinch = false
    reboundHandoff = false
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
    let firstFinger = gesture.touches.isEmpty
    for t in touches where !gesture.touches.contains(t) { gesture.touches.append(t) }
    if firstFinger { onInteractionBegan?() }
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
    if gesture.mode == .crosshair { gesture.owner = gesture.touches[0]; grabCrosshair(at: q) }
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

    // 十字线只认它的主人那根手指；其余模式这时只会有一根手指（两根就进捏合了）。
    let finger = mode == .crosshair ? (gesture.owner ?? gesture.touches.first) : gesture.touches.first
    let q = finger?.location(in: self) ?? gesture.startPoint
    if mode == .pan, gesture.reboundHandoff {
      // 捏合越界抬掉一根、回弹还没走完：这根手指不抢画面，起手点跟着回弹重设，
      // 弹完那一帧接着拖——不跳、也不和回弹打架。
      gesture.startPoint = q
      gesture.startView = state?.view ?? gesture.startView
      if animation == nil { gesture.reboundHandoff = false }
      return
    }
    let dx = Double(q.x - gesture.startPoint.x)
    let dy = Double(q.y - gesture.startPoint.y)
    gesture.moved = max(gesture.moved, (dx * dx + dy * dy).squareRoot())
    if gesture.moved > ChartGesture.longPressSlopPt { gesture.cancelLongPress() }

    switch mode {
    case .pinch, .autoFit, .subAxis: break
    case .axisPrice: dragPriceAxis(dy: dy, L: L)
    case .verticalPan: panPrice(dy: dy, L: L)
    case .parentScroll: break
    case .crosshair: moveCrosshair(to: grabbed(q), L: L)
    case .pan:
      do {
        guard gesture.moved >= ChartGesture.panSlopPt else { break }
        if !gesture.directionChosen {
          gesture.directionChosen = true
          if abs(dy) > 1.5 * abs(dx) {
            // 按在十字线的横线（价格线）上竖着拖：就是要把价格线挪上挪下
            if hitsCrosshairLine(gesture.startPoint) {
              gesture.mode = .crosshair
              gesture.owner = gesture.touches.first
              grabCrosshair(at: gesture.startPoint)
              moveCrosshair(to: grabbed(q), L: L)
              break
            }
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
    // 拎十字线那根手指抬起来了、别的手指还按着：这一轮十字线照样就此放下，
    // 剩下的手指不接班（接班就会把十字线拽到它底下去）。
    let ownerLifted = gesture.mode == .crosshair && gesture.owner.map { touches.contains($0) } == true
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
        // 捏合越过软边界时抬掉一根：剩下那根接着拖，拖动走的是硬夹（`ViewMath.dragging`），
        // 根宽得先回到边界里。和两指都松开同一条路（`settleView`）：绕捏的那一点弹回去，
        // 「减少动效」下直接到位。弹的这一程剩下那根手指不接管（`reboundHandoff`）。
        let overshoot = state.flatMap { s in pinchSettleTarget(s.view, L: L).map { $0 != s.view } } ?? false
        if overshoot { settleView() }
        gesture.reset()
        gesture.reboundHandoff = overshoot && animation != nil
        gesture.mode = .pan
        // 但这一轮的身世要留着：原地抬起剩下那根手指不是轻点（A-03）。
        gesture.cameFromPinch = true
        gesture.startPoint = q
        gesture.startView = state?.view ?? gesture.startView
        gesture.startTransform = state?.price ?? PriceTransform()
        gesture.velocity.add(x: Double(q.x), t: now)
        return
      }
      gesture.reset()
      settleView()
      return
    }

    guard liftedAll || gesture.touches.isEmpty || ownerLifted else { return }
    // 捏合越界降下来的那根手指在回弹途中抬起：回弹照走完，不判轻点、不起惯性
    // （惯性会把还没弹回的根宽连同动画一起换掉，停在边界外面）。
    if gesture.reboundHandoff, animation != nil { gesture.reset(); return }
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
    // 拎着十字线微调几个点也是在挪它，门槛比拖图那边的轻点低一半，不然往上挪 5 点一松手十字线就被收掉了
    if mode == .pan && moved < ChartGesture.panSlopPt * 2 || mode == .crosshair && moved < ChartGesture.panSlopPt,
       !cameFromPinch {
      handleTap(at: now, previous: plotTapCandidate)
      return
    }
    if mode == .autoFit {
      // 手指没跑出钮才算数，跟系统按钮一个规矩。
      if moved < ChartGesture.panSlopPt * 2, let L = chartLayout,
        L.hitsAutoFit(x: Double(endPoint.x), y: Double(endPoint.y))
      {
        resetPriceScale()
      }
      return
    }
    if mode == .subAxis, moved < ChartGesture.panSlopPt * 2 {
      if let layout = chartLayout, var s = state, s.options.allowSubInversion,
         let id = layout.panes.first(where: { $0.indicator != nil && endPoint.y >= $0.y && endPoint.y <= $0.y + $0.h })?.indicator {
        if s.subInverted.contains(id) { s.subInverted.remove(id) } else { s.subInverted.insert(id) }
        state = s
      }
      return
    }
    if mode == .axisPrice, moved < ChartGesture.panSlopPt * 2 {
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
    let delta = pOf(start, pane: L.main, range: range, mode: s.effectivePriceMode)
      - pOf(start + dy, pane: L.main, range: range, mode: s.effectivePriceMode)
    let center = gesture.startTransform.centerFraction + delta / max(1e-12, automatic.hi - automatic.lo)
    s.price.centerFraction = PriceTransform.clampedCenter(center, zoom: s.price.zoom)
    state = s
  }

  private func dragPriceAxis(dy: Double, L: Layout) {
    guard var s = state, gesture.moved >= ChartGesture.panSlopPt else { return }
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
    let f = twoFinger()
    gesture.cancelLongPress()
    state?.axisScaleAnchor = nil
    gesture.mode = .pinch
    gesture.trace = "begin sx=\(f.sx) sy=\(f.sy)"
    rebasePinch(f)
    gesture.pinchActive = false
    gesture.pinchAxis = .undecided
    gesture.moved = .greatestFiniteMagnitude
  }

  private func rebasePinch(_ f: TwoFinger) {
    gesture.pinchSx0 = f.sx
    gesture.pinchSy0 = f.sy
    gesture.pinchMid0 = f.mx
    gesture.pinchMidY0 = f.my
  }

  private func updatePinch(L: Layout) {
    guard let s = state else { return }
    let f = twoFinger()
    gesture.trace = "move sx=\(f.sx) sy=\(f.sy) axis=\(gesture.pinchAxis) active=\(gesture.pinchActive)"
    // 两指太近的那几帧只当噪声，但基准要跟着它走：不跟的话，等间距一跨过门槛，
    // 比例会把这一路攒下来的一次性甩出去，图会「嘭」地跳一下。
    guard hypot(f.sx, f.sy) >= ChartGesture.minPinchSpanPt else {
      rebasePinch(f); gesture.pinchActive = false; gesture.pinchAxis = .undecided
      return
    }
    // P1 死区：横向或纵向张开量变过 3pt 才认缩放。死区期间基准不跟着每一帧走
    // （跟了就永远越不过门槛，慢慢撑开等于没撑），但**平移不看这个门槛**——
    // 两指保持距离一起往旁边挪就是平移（A-06）。
    // 越过门槛那一帧只重设基准、定下这轮缩哪根轴，不缩放：从这一帧起按比例走，没有跳。
    if !gesture.pinchActive {
      let dsx = abs(f.sx - gesture.pinchSx0), dsy = abs(f.sy - gesture.pinchSy0)
      guard max(dsx, dsy) > ChartGesture.pinchSlopPt else {
        panPinch(mid: f.mx, L: L)
        return
      }
      gesture.pinchActive = true
      let inMain = f.my >= L.main.y && f.my <= L.main.y + L.main.h
      // P2：竖着摆、竖着捏、两指中点在主图里 → 缩价格轴；其余一律缩时间轴。
      let vertical = f.sy > 1.5 * f.sx && dsy > ChartGesture.pinchSlopPt && inMain
      gesture.pinchAxis = vertical ? .price : .time
      rebasePinch(f)
      if vertical {
        gesture.pinchStartZoom = s.price.zoom
        gesture.pinchSyStart = f.sy
        gesture.pinchPrice = price(atY: f.my)
      } else {
        gesture.pinchRawSpacing = ViewMath.rawSpacing(
          forSoft: s.view.barSpacing(step: s.series.step, plotW: L.plotW))
      }
      return
    }
    switch gesture.pinchAxis {
    case .price: pinchPrice(f, L: L)
    case .time, .undecided: pinchTime(f, L: L)
    }
  }

  /// 时间轴捏合的一帧（P1 / P3 / P5）。
  ///
  /// 倍数只看**横向**张开量：斜着捏时纵向那一半不再把根宽带着走。
  /// 贴着最新（`ViewMath.isPinnedToLatest`，捏合与滚轮同一条判据）→ 末根钉住、中点漂移不算；
  /// 不贴 → 视野先跟着中点平移，再绕中点缩放。
  /// 根宽越过 [1.6, 40] 时带阻尼往外走（最多 1.6 × 0.85、40 × 1.15），抬手 `settleView` 弹回；
  /// 系统「减少动效」开着就不越界，硬停在边界上。
  private func pinchTime(_ f: TwoFinger, L: Layout) {
    guard var s = state else { return }
    guard f.sx >= ChartGesture.minPinchSpanPt, gesture.pinchSx0 >= ChartGesture.minPinchSpanPt else {
      // 两指几乎竖成一条线：横向张开量太小，比值全是噪声。只换基准，等它张开再说。
      rebasePinch(f)
      return
    }
    let lo = AICoinBehavior.minimumSpacing, hi = AICoinBehavior.maximumSpacing
    var raw = gesture.pinchRawSpacing * f.sx / gesture.pinchSx0
    let reduce = ChartHaptics.reduceMotion
    raw = reduce ? min(hi, max(lo, raw)) : ViewMath.boundedRawSpacing(raw)
    gesture.pinchRawSpacing = raw
    let spacing = reduce ? raw : ViewMath.softSpacing(raw)
    let anchor = s.options.anchor
    let pinned = ViewMath.isPinnedToLatest(s.view, series: s.series, plotW: L.plotW, anchor: anchor)
    let base = pinned ? s.view
      : ViewMath.clampedOffset(s.view.dragged(byFingerPx: f.mx - gesture.pinchMid0, plotW: L.plotW),
                               series: s.series, plotW: L.plotW, anchor: anchor)
    s.view = ViewMath.pinched(base, series: s.series, plotW: L.plotW, spacing: spacing,
                              focus: f.mx, pinned: pinned, anchor: anchor)
    rebasePinch(f)
    state = s
    viewDidChange(s.view)
    reportZoomLimit(s.view, L: L)
  }

  /// 价格轴捏合的一帧（P2）：两指竖着张开 = 价格放大，捏拢 = 缩小，绕两指中点那个价位。
  ///
  /// 倍数走价格轴竖拖同一条曲线（`AICoinBehavior.axisZoom`，0.03…16、靠近 1 吸回自动），
  /// 进的也是同一个手动态（底边「A」徽章、双击价格轴都照常能回自动）。按下那一刻中点底下
  /// 的价位一直跟着中点：两指一起上下挪，价格跟着挪。时间轴整轮不动。
  private func pinchPrice(_ f: TwoFinger, L: Layout) {
    guard var s = state, let renderer, gesture.pinchSyStart > 0,
          f.sy >= ChartGesture.minPinchSpanPt else { return }
    let unit = max(L.mainH / 4, 1)
    let zoom = AICoinBehavior.axisZoom(from: gesture.pinchStartZoom,
                                       dy: -unit * log2(f.sy / gesture.pinchSyStart), height: L.mainH)
    var auto = s.price; auto.reset()
    let automatic = renderer.priceRange(size: bounds.size, transform: auto)
    let frac = min(1, max(0, (f.my - L.main.y) / max(1, L.main.h)))
    let g = (chartPriceRange?.inverted ?? s.price.inverted) ? frac : 1 - frac
    s.price.zoom = zoom
    s.price.centerFraction = PriceTransform.anchoredCenter(
      price: gesture.pinchPrice, fraction: g, zoom: zoom,
      autoLow: automatic.lo, autoHigh: automatic.hi,
      mode: s.effectivePriceMode == .log ? .log : .linear)
    s.axisScaleAnchor = nil
    gesture.pinchMid0 = f.mx
    state = s
  }

  /// 两指整体位移：中点挪了多少，图就跟着挪多少（A-06）。
  ///
  /// 和捏合的差别只有一处：这里不认「贴着最新」（`isPinnedToLatest`）。
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

  struct TwoFinger { var sx: Double; var sy: Double; var mx: Double; var my: Double }

  private func twoFinger() -> TwoFinger {
    let points = gesture.touches.map { $0.location(in: self) }
    let count = Double(points.count)
    let mx = points.reduce(0) { $0 + Double($1.x) } / count
    let my = points.reduce(0) { $0 + Double($1.y) } / count
    let sx = 2 * points.reduce(0) { $0 + abs(Double($1.x) - mx) } / count
    let sy = 2 * points.reduce(0) { $0 + abs(Double($1.y) - my) } / count
    return TwoFinger(sx: sx, sy: sy, mx: mx, my: my)
  }

  /// 捏合越过软边界之后该回到哪：根宽收回 [1.6, 40]，不动点和捏的时候同一个
  /// （贴着最新就钉末根，否则是最后那一帧的两指中点）。根宽没越界返回 nil。
  func pinchSettleTarget(_ v: ViewWindow, L: Layout) -> ViewWindow? {
    guard let s = state, !s.series.isEmpty, v.span > 0 else { return nil }
    let sp = v.barSpacing(step: s.series.step, plotW: L.plotW)
    let lo = AICoinBehavior.minimumSpacing, hi = AICoinBehavior.maximumSpacing
    guard sp < lo * (1 - 1e-9) || sp > hi * (1 + 1e-9) else { return nil }
    let anchor = s.options.anchor
    let pinned = ViewMath.isPinnedToLatest(v, series: s.series, plotW: L.plotW, anchor: anchor)
    return clamp(ViewMath.pinched(v, series: s.series, plotW: L.plotW, spacing: min(hi, max(lo, sp)),
                                  focus: gesture.pinchMid0, pinned: pinned, anchor: anchor),
                 plotW: L.plotW)
  }

  /// 缩放顶到 1.6 / 40 那一下震一次，松开再撞才震第二次（G11 的 rigid）。
  /// 软越界那几帧根宽在边界外面，照样算「顶着」，不重复震。
  private func reportZoomLimit(_ v: ViewWindow, L: Layout) {
    guard let s = state, s.series.count > 0 else { return }
    let sp = v.barSpacing(step: s.series.step, plotW: L.plotW)
    let atLimit = sp <= Chart.minBarSpacing * 1.001 || sp >= Chart.maxBarSpacing * 0.999
    if atLimit && !gesture.wasAtZoomLimit { ChartHaptics.boundary() }
    gesture.wasAtZoomLimit = atLimit
  }

  // MARK: - 十字线

  /// A native 44 pt touch target around the rendered intersection, not either full line.
  public func hitsCrosshairCenter(_ point: CGPoint) -> Bool {
    guard let center = renderer?.crosshairCenter(size: bounds.size) else { return false }
    return abs(point.x - center.x) <= 22 && abs(point.y - center.y) <= 22
  }

  /// 横线（价格线）上下 22 点、图区宽度以内都算按在线上：竖着拖就挪价格线，横着拖照旧拖图。
  /// `ChartPageScrollView` 也问它——按在线上竖拖不能被页面滚动抢走。
  public func hitsCrosshairLine(_ point: CGPoint) -> Bool {
    guard let center = renderer?.crosshairCenter(size: bounds.size), let L = chartLayout else { return false }
    return point.x >= 0 && Double(point.x) <= L.plotW && abs(point.y - center.y) <= 22
  }

  /// 从 p 拎起已经在图上的十字线：记下交叉点相对手指的距离，钉住坐标。
  private func grabCrosshair(at p: CGPoint) {
    if let c = renderer?.crosshairCenter(size: bounds.size) {
      gesture.grab = CGVector(dx: c.x - p.x, dy: c.y - p.y)
    }
    // 拎着已经在图上的十字线走，和长按新出一条十字线是同一件事，一样要钉住坐标。
    beginAxisFreeze()
  }

  private func grabbed(_ q: CGPoint) -> CGPoint {
    CGPoint(x: q.x + gesture.grab.dx, y: q.y + gesture.grab.dy)
  }

  private func scheduleLongPress(at q: CGPoint) {
    let work = DispatchWorkItem { [weak self] in
      guard let self, let L = self.chartLayout else { return }
      self.gesture.longPress = nil
      guard self.gesture.moved <= ChartGesture.longPressSlopPt else { return }
      self.gesture.longPressActivated = true
      self.gesture.mode = .crosshair
      self.gesture.owner = self.gesture.touches.first
      // 十字线一出来就把坐标钉住：接下来这段跟手的移动里，新 K 线到货也好、
      // 新高新低也好，都不许把手指底下那根 K 线挪走（见 `beginAxisFreeze`）。
      self.beginAxisFreeze()
      self.moveCrosshair(to: q, L: L)
      ChartHaptics.crosshair()
    }
    gesture.longPress = work
    DispatchQueue.main.asyncAfter(
      deadline: .now() + ChartGesture.longPressMs / 1000, execute: work)
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
    // 十字线一出来，轻点选中的那一单就让位：卡片改由十字线停在哪条带上决定。
    s.orderFlowSelected = nil
    // 回调由 `state` 的 setter 统一发（`adopt` 里那一句）。这儿不再补一发：同一份
    // 十字线连送两次，外面每收一次就重算一遍读数——跟手时那是白白翻倍的一摊活。
    state = s
    // 这儿从前每跨一根 K 线就 `ChartHaptics.magnetTick()` 一次，没有任何节流：手指横着
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
    ChartHaptics.magnetTick()
  }

  /// 清掉十字线。品种 / 周期切换、面板弹出时外面也会叫。
  public func clearCrosshair() {
    guard var s = state, s.crosshair != nil else { return }
    s.crosshair = nil
    // 同上：`state` 的 setter 会把这一下清空回调出去，这儿不必再发一遍。
    state = s
  }

  // MARK: - 外面叫的平移（复盘选区）

  /// 按像素挪视野（正数 = 往更新的那头走）。复盘圈选拖手柄贴到边上时，由那一层的
  /// displayLink 每帧叫一次（P3.7）。和手指拖图同一条夹紧、同一条「要更多历史」回调，
  /// 所以挪到头就停在头上，挪到最左边会照常去取更早的 K 线。
  public func nudge(byPx dx: Double) {
    guard var s = state, let L = chartLayout, L.plotW > 0, dx != 0 else { return }
    let v = clampView(s.view.shifted(byPx: dx, plotW: L.plotW),
                      series: s.series, plotW: L.plotW, anchor: s.options.anchor)
    guard v != s.view else { return }
    s.view = v
    state = s
    viewDidChange(v)
  }

  /// 让 `[from, to)` 这段时间落进可视区：已经在里面就不动；不在就平移过去，
  /// 宽过一屏才放宽视野。复盘卡片上改起止时刻时用（P3.7）。
  public func reveal(from: Double, to: Double) {
    guard var s = state, let L = chartLayout, L.plotW > 0, to > from else { return }
    if from >= s.view.from && to <= s.view.to { return }
    var span = s.view.span
    if (to - from) * 1.16 > span { span = (to - from) * 1.25 }
    let center = (from + to) / 2
    let v = clampView(ViewWindow(to: center + span / 2, span: span),
                      series: s.series, plotW: L.plotW, anchor: s.options.anchor)
    s.view = v
    state = s
    viewDidChange(v)
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
      selectOrderFlow(nil)
      resetPriceScale()
      scrollToLatest()
      return
    }
    gesture.lastPlotTap = (ms: now, x: Double(p.x), y: Double(p.y))
    // 主力订单流：点在一条色带（一桶一段合并的那条）上就选中它（出详情卡、描边），再点同一条收起，点别的换过去；
    // 选中时点空白处只收卡，不顺手开十字线。「同一条」按 `orderFlowIsSelected` 认（段起点前移过也算同一条）。
    // 点在蜡烛上（高低范围内）永远是 K 线的：出十字线，不被垫在底下的大单带子截走。
    if let renderer, !renderer.candleHit(at: p, size: bounds.size), let hit = renderer.orderFlowHit(at: p, size: bounds.size) {
      selectOrderFlow(renderer.orderFlowIsSelected(hit) ? nil : hit.key)
      return
    }
    if state?.orderFlowSelected != nil {
      selectOrderFlow(nil)
      return
    }
    if state?.crosshair != nil {
      clearCrosshair()
    } else if let L = chartLayout {
      moveCrosshair(to: gesture.startPoint, L: L)
      finishCrosshairSelection()
      onTapped?()
    }
  }

  /// 选中 / 取消选中主力订单流的一条合并带（一段，`nil` = 取消）。选中时十字线收掉，两块读数不同时出。
  public func selectOrderFlow(_ key: OrderFlowGroupKey?) {
    guard var s = state, s.orderFlowSelected != key || (key != nil && s.crosshair != nil) else { return }
    s.orderFlowSelected = key
    if key != nil { s.crosshair = nil }
    state = s
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

  /// 「回到最新」（G14）：滑回右边缘。
  public func scrollToLatest(animated: Bool = true) {
    cancelAxisFreeze()
    guard var s = state, let L = chartLayout, s.series.count > 0 else { return }
    let target = ViewMath.reset(
      series: s.series, plotW: L.plotW,
      spacing: s.view.barSpacing(step: s.series.step, plotW: L.plotW),
      anchor: s.options.anchor)
    // 不在窗口上挂动画会被 `animation` 的 didSet 直接丢掉，那就一步到位。
    guard animated, window != nil, !ChartHaptics.reduceMotion else {
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
    guard !ChartHaptics.reduceMotion,
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
    let target = pinchSettleTarget(s.view, L: L) ?? clamp(s.view, plotW: L.plotW)
    let offPx = abs(target.to - s.view.to) / s.view.span * L.plotW
    guard offPx > 0.01 || abs(target.span - s.view.span) / s.view.span > 1e-9 else { return }
    settleView()
  }

  /// 两端单指拉出的空白松手回对应边界，历史窗口不被拉回最新。
  ///
  /// 捏合越过软边界的（根宽在 [1.6, 40] 外面）绕捏的那个不动点弹回，不是绕右缘——
  /// 不然捏着中间放大到头一松手，画面整体往右一滑。
  private func settleView() {
    guard var s = state, let L = chartLayout, s.view.span > 0 else { return }
    let target = pinchSettleTarget(s.view, L: L) ?? clamp(s.view, plotW: L.plotW)
    let offPx = abs(s.view.to - target.to) / s.view.span * L.plotW
    let spanOff = abs(target.span - s.view.span) / s.view.span > 1e-9
    if !ChartHaptics.reduceMotion, offPx > 0.01 || spanOff {
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
  /// 默认算**用户手上的动作**——这个文件里除了「回到最新」，
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
    return pOf(y, pane: L.main, range: r, mode: s.effectivePriceMode)
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

/// 图上自己的那几下触觉（G11、P2.9）：出十字线 light、十字线磁吸换根 selection、缩放到边界 rigid。
/// 画线那几下（落点吸住、没落成、删线）不在这儿：图只报 `DrawingFeedback`，震不震由 app 的
/// `DrawingHaptics` 定（审查 23.2）。图外的触觉（点星、换档、提醒响了……）在 app 层的 `Haptics` 里，
/// 这个包不对外公开触觉。
///
/// 生成器留着不重建：`prepare()` 之后系统会把 Taptic Engine 预热，每次现 new 一个
/// 第一下会晚几十毫秒，磁吸换根那种连续反馈就会糊成一片。
@MainActor
enum ChartHaptics {
  private static let light = UIImpactFeedbackGenerator(style: .light)
  private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
  private static let selection = UISelectionFeedbackGenerator()

  /// 系统「减少动效」。甩、回弹、捏合软越界看它，触觉不看——那是两个开关。
  static var reduceMotion: Bool { reduceMotionOverride ?? UIAccessibility.isReduceMotionEnabled }
  /// 单测用：模拟器里拨不动系统开关。
  static var reduceMotionOverride: Bool?
  /// 单测用：边界震了几次。
  private(set) static var boundaryCount = 0

  static func crosshair() {
    light.prepare()
    light.impactOccurred()
    selection.prepare()          // 接下来多半是磁吸连击，先热起来
  }

  static func magnetTick() { selection.selectionChanged() }

  static func boundary() {
    boundaryCount += 1
    rigid.prepare()
    rigid.impactOccurred(intensity: 0.7)
  }
}
