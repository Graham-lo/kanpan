import KanpanChart
import KanpanCore
import SwiftUI
import UIKit

/// 换了数据之后视野该怎么办。
///
/// 冷启动、切周期和布局改变通过同一底座调整视野，
/// 差别在于「保住什么」：换品种什么都不保，换周期保根宽，风格变化保留整个视野。
enum ViewIntent: Equatable {
  case keep
  /// 换品种、第一次拿到数据：回到最新，按共用默认根间距。
  case reset
  /// 换周期：根宽不变，看见的时间跨度跟着周期走。带的是切之前量出来的实际根间距。
  case switchInterval(spacing: Double)
  /// 布局改尺寸：保留实际根间距和历史右缘。
  case resize(spacing: Double)
}

/// 装着 `ChartView` 的盒子，外加一件事：等布局出来再兑现视野。
///
/// 视野要算就得先知道图区有多宽（`plotW`），而 `UIViewRepresentable` 造视图那一刻
/// 帧还是零，`chartLayout` 是 `nil`，算不出来。所以把意图记下来，`layoutSubviews`
/// 里再兑现。`ChartView` 是 `final`（快照测试要它的行为完全定死），所以这里用「包一层」
/// 而不是继承。
final class ChartBox: UIView, UIGestureRecognizerDelegate {
  let chart = ChartView(frame: .zero)
  private let scroll = ChartPageScrollView()
  private let panelDismiss = UIControl()
  var onOverlayUpdate: () -> Void = {}
  var onPanelDismiss: () -> Void = {}
  var panelOpen = false { didSet { panelDismiss.isHidden = !panelOpen; if panelOpen { bringSubviewToFront(panelDismiss) } } }
  private var grips: [IndicatorID: ResizeGrip] = [:]
  private var resizeStart: (id: IndicatorID, height: Double, scale: Double, content: Double, other: Double)?
  private var resizeOriginY: CGFloat?
  var isResizing: Bool { resizeStart != nil }
  var onSubResize: (IndicatorID, Double) -> Void = { _, _ in }
  private var reorderCandidate: IndicatorID?
  private var reorderStart: [IndicatorID]?
  private var reorderFrames: [Pane] = []
  var isReordering: Bool { reorderStart != nil }
  var onSubReorder: ([IndicatorID]) -> Void = { _ in }
  var portrait = true
  var pending: ViewIntent = .reset

  override init(frame: CGRect) {
    super.init(frame: frame)
    scroll.chart = chart
    scroll.delaysContentTouches = false
    scroll.bounces = false
    scroll.showsVerticalScrollIndicator = true
    addSubview(scroll)
    scroll.addSubview(chart)
    let reorder = UILongPressGestureRecognizer(target: self, action: #selector(reorderPane))
    reorder.minimumPressDuration = 0.35; reorder.delegate = self
    chart.addGestureRecognizer(reorder)
    scroll.panGestureRecognizer.require(toFail: reorder)
    panelDismiss.isHidden = true
    panelDismiss.accessibilityIdentifier = "chart.dismissPanel"
    panelDismiss.accessibilityLabel = "收起面板"
    panelDismiss.addTarget(self, action: #selector(closePanel), for: .touchUpInside)
    addSubview(panelDismiss)
  }

  required init?(coder: NSCoder) { fatalError("不从 xib 来") }

  override func layoutSubviews() {
    super.layoutSubviews()
    let oldWidth = chart.chartLayout?.plotW
    let oldSpacing = chart.state.flatMap { state in
      oldWidth.map { state.view.barSpacing(step: state.series.step, plotW: $0) }
    }
    panelDismiss.frame = bounds
    scroll.frame = bounds
    let contentHeight = chart.state.map { state in
      ChartContentLayout.height(viewport: Double(bounds.height), control: state.options.portraitHeight,
        subs: state.subs, subScale: state.subScale, portrait: portrait)
    } ?? Double(bounds.height)
    scroll.contentSize = CGSize(width: bounds.width, height: contentHeight)
    scroll.contentOffset.y = min(scroll.contentOffset.y, max(0, contentHeight - bounds.height))
    chart.frame = CGRect(x: 0, y: 0, width: bounds.width, height: contentHeight)
    chart.layoutIfNeeded()
    if pending == .keep, let oldWidth, let oldSpacing,
       let newWidth = chart.chartLayout?.plotW, oldWidth != newWidth {
      pending = .resize(spacing: oldSpacing)
    }
    applyPending()
    updateControls()
  }

  @objc private func closePanel() { onPanelDismiss() }

  /// 图上的把手 / 覆盖层跟着新布局走一遍。
  ///
  /// 这儿原来还摆着一颗 44×44 的「回到最新」圆钮，浮在主图右下角。用户定过规矩：
  /// 画布上不允许浮任何控件——它会压着 K 线，改副图高度时还得跟着主图的下沿挪。
  /// 那颗按钮已经搬到周期条行尾（见 `IntervalBar` 的「最新」），id 仍叫 `chart.latest`。
  func updateControls() {
    onOverlayUpdate()
    guard let state = chart.state, let layout = chart.chartLayout else { return }
    for id in Array(grips.keys) where !state.subs.contains(id) { grips.removeValue(forKey: id)?.removeFromSuperview() }
    for pane in layout.panes.dropFirst() {
      guard let id = pane.indicator else { continue }
      let grip = grips[id] ?? ResizeGrip(id: id)
      if grips[id] == nil {
        grip.isAccessibilityElement = true
        grip.accessibilityIdentifier = "chart.resize.\(id.rawValue)"
        grip.accessibilityLabel = "调整\(id.name)区域高度"
        let pan = UIPanGestureRecognizer(target: self, action: #selector(resizePane))
        pan.maximumNumberOfTouches = 1; pan.delegate = self
        grip.addGestureRecognizer(pan)
        scroll.panGestureRecognizer.require(toFail: pan)
        scroll.addSubview(grip); grips[id] = grip
      }
      // 分隔线本身就是把手：这条 16pt 高的带子骑在两格的交界上，只提供热区，不画任何东西。
      grip.frame = CGRect(x: 0, y: min(layout.H - 16, pane.y + pane.h - 8), width: layout.W, height: 16)
      grip.accessibilityValue = String(format: "%.0f", pane.h)
    }
    if panelOpen { bringSubviewToFront(panelDismiss) }
  }

  override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
    guard let pan = recognizer as? UIPanGestureRecognizer, pan.view is ResizeGrip else { return true }
    let d = pan.translation(in: self)
    return abs(d.y) > abs(d.x)
  }
  func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    if recognizer.view is ResizeGrip { resizeOriginY = touch.location(in: self).y }
    if recognizer is UILongPressGestureRecognizer {
      let p = touch.location(in: chart)
      if let layout = chart.chartLayout {
        reorderCandidate = ChartGestureRoute.reorderPane(x: p.x, y: p.y,
          plotWidth: layout.plotW, panes: layout.panes)
      } else { reorderCandidate = nil }
      return reorderCandidate != nil
    }
    return true
  }
  /// Hold anywhere in a subplot to reorder; moving before the hold keeps chart pan/pinch.
  @objc private func reorderPane(_ press: UILongPressGestureRecognizer) {
    guard var state = chart.state, let id = reorderCandidate else { return }
    if press.state == .began {
      reorderStart = state.subs
      reorderFrames = Array(chart.chartLayout?.panes.dropFirst() ?? [])
      chart.clearCrosshair(); state.crosshair = nil
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    guard let original = reorderStart else { return }
    if press.state == .cancelled || press.state == .failed {
      state.subs = original
    } else {
      let y = press.location(in: chart).y
      let target = reorderFrames.firstIndex(where: { y < $0.y + $0.h }) ?? max(0, original.count - 1)
      if let source = state.subs.firstIndex(of: id), source != target {
        state.subs.remove(at: source); state.subs.insert(id, at: target)
        UISelectionFeedbackGenerator().selectionChanged()
      }
    }
    chart.state = state
    setNeedsLayout(); layoutIfNeeded()
    if press.state == .ended || press.state == .cancelled || press.state == .failed {
      reorderStart = nil; reorderCandidate = nil; reorderFrames = []
      if press.state == .ended { onSubReorder(state.subs) }
    }
  }

  @objc private func resizePane(_ pan: UIPanGestureRecognizer) {
    guard var state = chart.state, let layout = chart.chartLayout else { return }
    let delta = pan.location(in: self).y - (resizeOriginY ?? pan.location(in: self).y)
    if pan.state == .began {
      guard let grip = pan.view as? ResizeGrip,
            let pane = layout.panes.first(where: { $0.indicator == grip.id }) else { return }
      let id = grip.id
      state.crosshair = nil
      let scale = state.subScale[id] ?? 1
      let content = layout.H - AICoinBehavior.timeHeight
      resizeStart = (id, pane.h, scale, content, scale * (content - pane.h) / pane.h)
    }
    guard let start = resizeStart else { return }
    let scale = pan.state == .cancelled ? start.scale : SubPaneResize.scale(initialHeight: start.height,
      translation: delta, contentHeight: start.content, otherWeight: start.other)
    state.subScale[start.id] = scale
    chart.state = state
    setNeedsLayout(); layoutIfNeeded()
    if pan.state == .ended || pan.state == .cancelled || pan.state == .failed {
      resizeStart = nil; resizeOriginY = nil
      if pan.state == .ended { onSubResize(start.id, scale) }
    }
  }

  func applyPending() {
    guard pending != .keep, var s = chart.state, s.series.count > 0, let L = chart.chartLayout
    else { return }
    let transition = pending
    pending = .keep
    var plotW = L.plotW
    // The new visible range can change formatted axis label width. Resolve the
    // viewport against that final width, keeping the requested candle spacing.
    for _ in 0..<4 {
      switch transition {
      case .keep: return
      case .reset:
        s.view = ViewMath.reset(series: s.series, plotW: plotW,
          spacing: AICoinBehavior.initialSpacing, anchor: s.options.anchor)
      case .switchInterval(let spacing):
        s.view = ViewMath.switchInterval(to: s.series, plotW: plotW, spacing: spacing, anchorRight: nil)
      case .resize(let spacing):
        s.view = ViewMath.resized(s.view, series: s.series, plotW: plotW, spacing: spacing, anchor: s.options.anchor)
      }
      chart.state = s
      let resolved = chart.chartLayout?.plotW ?? plotW
      if abs(resolved - plotW) < 0.001 { break }
      plotW = resolved
    }
    chart.onViewChanged?(s.view)
  }
}

private final class ResizeGrip: UIView {
  let id: IndicatorID
  init(id: IndicatorID) { self.id = id; super.init(frame: .zero) }
  required init?(coder: NSCoder) { fatalError("programmatic only") }
}

/// 给 SwiftUI 递过去的一个把手。
///
/// 「回到最新」要叫的是 `ChartView.scrollToLatest()`，那是 UIKit 那一侧的方法；
/// SwiftUI 这边拿不到视图实例，所以建视图时把它挂进来。弱引用——视图归 SwiftUI 管，
/// 这里只是借来用一下。
@MainActor
final class ChartProxy {
  weak var box: ChartBox?
  var savedState: ChartState?
  var savedPlotWidth: Double?

  func scrollToLatest(animated: Bool = true) { box?.chart.scrollToLatest(animated: animated) }
  var isAtLatest: Bool { box?.chart.isAtLatest ?? true }
}

/// 把 `ChartView`（UIKit + CoreGraphics 手绘）嵌进 SwiftUI。
///
/// 这里刻意只做两件事：把 `state` 灌进去、把手势回调接出来。**不要**在这儿摆任何
/// SwiftUI 控件——图上的一切（十字线、读数、最新价胶囊）都归 `ChartRenderer` 画，
/// 混着摆就会出现两套坐标系，转屏和改副图高度时必然对不齐。
struct ChartHost: UIViewRepresentable {
  var portrait = true
  var renderingActive: Bool = true
  var panelOpen = false
  var state: ChartState?
  var proxy: ChartProxy?
  /// 手势改了视野。视野是**图自己**的状态，不走 SwiftUI 的 `@State` 回环——
  /// 每帧 60/120 次穿过 SwiftUI 的 diff 太贵，所以图自己改自己，改完通知外面记一笔。
  var onView: (ViewWindow) -> Void = { _ in }
  var onSubResize: (IndicatorID, Double) -> Void = { _, _ in }
  var onSubReorder: ([IndicatorID]) -> Void = { _ in }
  var onCrosshair: (Crosshair?) -> Void = { _ in }
  var onNeedsHistory: () -> Void = {}
  var onTapped: () -> Void = {}
  /// 图里那些「做了个大动作」的提示，接到外面的 toast 上。
  var onNotice: (String) -> Void = { _ in }
  /// 画线壳（M7）。线本身住在 `ChartState.drawings` 里、手势归图，这个只负责
  /// 亮哪一颗按钮和按品种落盘。
  var drawing: DrawingController?

  func makeUIView(context: Context) -> ChartBox {
    let box = ChartBox(frame: .zero)
    proxy?.box = box
    box.chart.isHidden = !renderingActive
    guard renderingActive else { return box }
    box.portrait = portrait
    wire(box)
    var incoming = state
    if var next = incoming, let saved = proxy?.savedState, let width = proxy?.savedPlotWidth,
       next.series.symbol == saved.series.symbol, next.series.interval == saved.series.interval {
      next.view = saved.view
      if next.price.mode == saved.price.mode { next.price = saved.price }
      next.subInverted = saved.subInverted
      next.crosshair = next.options.dataDisplay == saved.options.dataDisplay && next.options.crossPrice == saved.options.crossPrice ? saved.crosshair : nil
      incoming = next
      box.pending = .resize(spacing: saved.view.barSpacing(step: saved.series.step, plotW: width))
    }
    box.chart.state = incoming
    return box
  }

  func updateUIView(_ box: ChartBox, context: Context) {
    proxy?.box = box
    box.chart.isHidden = !renderingActive
    guard renderingActive else { return }
    box.portrait = portrait
    wire(box)
    guard var s = state else {
      box.chart.state = nil
      box.pending = .reset
      return
    }
    if let old = box.chart.state ?? proxy?.savedState, old.series.count > 0 {
      // 视野归图自己管：外面传下来的那份是「上一次图告诉我的」，原样塞回去会把
      // 手势正在做的位移覆盖掉。只在品种/周期/风格真换了的时候才重算。
      s.view = old.view
      s.crosshair = old.crosshair
      s.subInverted = old.subInverted
      if box.isResizing { s.subScale = old.subScale }
      if box.isReordering { s.subs = old.subs }
      if old.options.dataDisplay != s.options.dataDisplay || old.options.crossPrice != s.options.crossPrice {
        s.crosshair = nil
      }
      if let pane = s.crosshair?.pane, !s.subs.contains(pane) { s.crosshair = nil }
      if var cross = s.crosshair, old.series.count > cross.index, cross.index >= 0 {
        cross.index = s.series.index(atTime: Double(old.series.time(at: cross.index)))
        s.crosshair = cross
      }
      // 线和视野一个道理：画的时候每帧都在动，外面那份必然是旧的。
      if old.series.symbol == s.series.symbol { s.drawings = old.drawings; s.drawingPreviewID = old.drawingPreviewID }
      if old.series.symbol != s.series.symbol {
        s.crosshair = nil
        box.pending = .reset
      } else if old.series.interval != s.series.interval {
        s.crosshair = nil
        let plotW = box.chart.chartLayout?.plotW ?? proxy?.savedPlotWidth ?? Double(box.bounds.width)
        box.pending = .switchInterval(
          spacing: old.view.barSpacing(step: old.series.step, plotW: plotW))
      } else {
        if let layout = box.chart.chartLayout {
          s.view = AICoinBehavior.reconcile(old.view, from: old.series, to: s.series, plotW: layout.plotW, anchor: s.options.anchor)
        }
        // Price transforms belong to the chart, not the SwiftUI settings snapshot.
        if old.price.mode == s.price.mode { s.price = old.price }
        else { s.price.inverted = old.price.inverted }
      }
    } else {
      box.pending = .reset
    }
    let previousWidth = box.chart.chartLayout?.plotW
    let previousSpacing = box.chart.state.flatMap { old in previousWidth.map { old.view.barSpacing(step: old.series.step, plotW: $0) } }
    box.chart.state = s
    if box.pending == .keep, let previousWidth, let previousSpacing,
       let width = box.chart.chartLayout?.plotW, width != previousWidth {
      box.pending = .resize(spacing: previousSpacing)
    }
    box.setNeedsLayout()
    box.applyPending()
    // 放在灌完 state 之后：`focus` 会往图里塞这个品种的线，早一步会被上面那行盖掉。
    drawing?.focus(s.series.symbol)
  }

  private func wire(_ box: ChartBox) {
    box.panelOpen = panelOpen
    box.onPanelDismiss = onTapped
    drawing?.attach(box.chart)
    box.chart.onViewChanged = onView
    box.onSubResize = onSubResize
    box.onSubReorder = onSubReorder
    box.chart.onCrosshairChanged = onCrosshair
    box.chart.onNeedsHistory = onNeedsHistory
    box.chart.onTapped = onTapped
    box.chart.onNotice = onNotice
    box.chart.onStateChanged = { [weak proxy, weak box] state in
      box?.updateControls()
      guard let state, let layout = box?.chart.chartLayout else { return }
      proxy?.savedState = state
      proxy?.savedPlotWidth = layout.plotW
    }
  }
}

/// Scroll view takes only page-directed vertical drags. Horizontal/pinch/manual-Y
/// stay in ChartView's existing state machine; a long-press selection also keeps capture.
private final class ChartPageScrollView: UIScrollView {
  weak var chart: ChartView?
  override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
    guard recognizer === panGestureRecognizer, let chart, let state = chart.state,
          let layout = chart.chartLayout else { return super.gestureRecognizerShouldBegin(recognizer) }
    let point = panGestureRecognizer.location(in: chart)
    let velocity = panGestureRecognizer.velocity(in: chart)
    return ChartGestureRoute.pageScroll(x: point.x, y: point.y, dx: velocity.x, dy: velocity.y,
      touches: panGestureRecognizer.numberOfTouches, plotWidth: layout.plotW, mainHeight: layout.mainH,
      manualY: state.price.isManual, selecting: chart.hitsCrosshairCenter(point))
  }
}
