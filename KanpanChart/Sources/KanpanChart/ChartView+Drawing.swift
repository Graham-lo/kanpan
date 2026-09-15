import CoreGraphics
import Foundation
import KanpanCore
import ObjectiveC
import QuartzCore
import UIKit

// MARK: - 一次画线会话

/// 画线态从「选了工具」到「完成」之间要记住的东西（§10.8、§13 A7）。
///
/// 为什么不塞进 `ChartState`：`ChartState` 是渲染的纯输入，M3 的 176 张逐像素基线
/// （A3.11）钉死了「同一份 state → 同一张图」。选中态、待落点、预览线都是**交互**
/// 中间量，进了 state 就等于改渲染路径。所以它们留在这里，由一层不接触渲染器的
/// 覆盖视图画（`DrawingOverlayView`）——基线一张都不用动。
///
/// 扩展加不了存储属性，所以这个会话挂在视图的关联对象上（见 `ChartView.drawing`）。
@MainActor
final class DrawingSession {
  /// 一次拖动的快照。
  struct Drag {
    var id: String
    var part: Drawing.Part
    /// **按下那一刻**的那条线。整场拖动都拿它当基准，不逐帧累加——理由和 M4 手势的
    /// `startView` 一样：累加会把手指抖动的浮点误差一路攒进端点里。
    var from: Drawing
    var start: CGPoint
    var axes: DrawAxes
  }

  var tool: DrawingStore.Tool?
  var selected: String?
  /// 趋势线落了第一点、还差第二点。
  var anchors: [DrawPoint] = []
  var pending: DrawPoint? {
    get { anchors.first }
    set { anchors = newValue.map { [$0] } ?? [] }
  }
  var styles: [String: DrawingStyle] = [:]
  var continuous = false
  var magnet = true
  var navigating = false
  /// 第二点此刻指到哪儿：`pending` 在的时候手指移动，预览线实时跟到这里（§10.8）。
  var aim: DrawPoint?
  var preview: Drawing?
  var loupe: UIImage?
  var drag: Drag?
  var history = DrawHistory()

  /// 这一次触摸归画线管，不转给图表手势。
  var claimed: UITouch?
  var startPoint: CGPoint = .zero
  var beganMs: Double = 0
  var moved: Double = 0
  /// 上一次吸住的那根，换根才震（和十字线磁吸同一个手法）。
  var lastMagnetIndex: Int = -1

  weak var overlay: DrawingOverlayView?
  var link: CADisplayLink?

  var onChanged: (([Drawing]) -> Void)?
  var onState: (() -> Void)?
  var onFull: (() -> Void)?
}

/// 关联对象的键。全局 `let` 只初始化一次，地址唯一，正好当键用。
private nonisolated(unsafe) let drawingSessionKey =
  UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

/// 「轻点」的时长上限（§10.8：按下到抬起 < 200ms 且位移 < 4pt 才算落笔）。
/// 位移那一半复用 `Chart.panSlopPt`，两处是同一个 4pt。
private let drawTapMs: Double = 500

extension ChartView {
  /// 这张图的画线会话。第一次问的时候建。
  var drawing: DrawingSession {
    if let s = objc_getAssociatedObject(self, drawingSessionKey) as? DrawingSession { return s }
    let s = DrawingSession()
    objc_setAssociatedObject(self, drawingSessionKey, s, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    return s
  }
}

// MARK: - 对外

extension ChartView {
  /// 打开画线交互。
  ///
  /// 打开时往图上盖一层透明视图：它既画选中态 / 预览线，也是画线手势的入口——
  /// 不归画线管的触摸原封不动转回 `ChartView` 自己的 `touchesBegan/...`，
  /// 所以拖图、捏合、长按十字线全都照常（A7.8）。
  ///
  /// 不打开的时候图上一个多余的视图都没有，M4 的手势测试与 M3 的基线都碰不到这条路径。
  public var drawingInteractive: Bool {
    get { drawing.overlay != nil }
    set {
      if newValue {
        guard drawing.overlay == nil else { return }
        let v = DrawingOverlayView(host: self)
        v.frame = bounds
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(v)
        drawing.overlay = v
      } else {
        drawing.overlay?.removeFromSuperview()
        drawing.overlay = nil
      }
    }
  }

  /// 当前工具。设成非 `nil` 会顺手把交互打开——底栏点「趋势线」就能画，不用外面
  /// 再记得开一次开关。
  public var drawTool: DrawingStore.Tool? {
    get { drawing.tool }
    set {
      let d = drawing
      guard d.tool != newValue else { return }
      d.tool = newValue
      d.pending = nil
      d.aim = nil
      d.selected = nil
      if var s = state { s.crosshair = nil; state = s }
      if newValue != nil { drawingInteractive = true }
      drawingChanged()
    }
  }

  /// 选中的那条线的 id；`nil` 表示没选中。
  public var selectedDrawingID: String? {
    get { drawing.selected }
    set {
      guard drawing.selected != newValue else { return }
      drawing.selected = newValue
      drawingChanged()
    }
  }

  /// 图上现有的线。
  public var drawings: [Drawing] { state?.drawings ?? [] }

  /// 整批换线（切品种、从磁盘读回来）。撤销栈一并清掉：两个品种的线互不相干。
  public func setDrawings(_ items: [Drawing]) {
    guard var s = state else { return }
    s.drawingPreviewID = nil
    drawing.preview = nil
    s.drawings = DrawArchive.capped(items)
    state = s
    let d = drawing
    d.selected = nil
    d.pending = nil
    d.aim = nil
    d.drag = nil
    d.history.clear()
    d.tool = nil
    d.claimed = nil
    d.navigating = false
    drawingChanged()
  }

  /// 图区顶部那一行提示（§10.8）。没选工具时是 `nil`，外面就把提示条收起来。
  public var drawHint: String? {
    guard let tool = drawing.tool else { return nil }
    if tool == .trend { return drawing.pending == nil ? "点两下画一条趋势线" : "再点一下" }
    if tool.pointCount == 1 { return "轻点放置" + tool.title }
    if drawing.anchors.isEmpty { return "选择起点" }
    return tool == .channel && drawing.anchors.count == 2 ? "选择通道宽度" : "选择终点"
  }

  public var drawingStyles: [String: DrawingStyle] {
    get { drawing.styles }
    set { drawing.styles = newValue }
  }
  public var continuousDrawing: Bool {
    get { drawing.continuous }
    set { drawing.continuous = newValue; drawingChanged() }
  }
  public var drawingMagnet: Bool {
    get { drawing.magnet }
    set { drawing.magnet = newValue; drawingChanged() }
  }
  public func updateDrawing(_ item: Drawing) {
    guard item.isValid, var s = state, let i = s.drawings.firstIndex(where: { $0.id == item.id }), s.drawings[i] != item else { return }
    drawing.history.commit(before: s.drawings)
    s.drawings[i] = item; state = s; drawingChanged(items: s.drawings)
  }
  public func duplicateSelectedDrawing() {
    guard var s = state, let item = s.drawings.first(where: { $0.id == drawing.selected }), let axes = drawAxes else { return }
    guard s.drawings.count < DrawArchive.perSymbolLimit else { drawing.onFull?(); return }
    var copy = item; copy.locked = false; copy.hidden = false
    copy = movedDrawing(copy, part: .body, dt: axes.view.span * 20 / axes.layout.plotW,
                        priceShift: { axes.p(atY: axes.y($0) + 20) })
    copy.id = Drawing.newID()
    drawing.history.commit(before: s.drawings); s.drawings.append(copy); state = s
    drawing.selected = copy.id; drawingChanged(items: s.drawings)
  }
  public func clearDrawings() {
    guard var s = state, !s.drawings.isEmpty else { return }
    drawing.history.commit(before: s.drawings); s.drawings = []; state = s
    drawing.selected = nil; drawing.pending = nil; drawing.aim = nil; drawingChanged(items: [])
  }
  public func setAllDrawingsHidden(_ hidden: Bool) {
    guard var s = state, s.drawings.contains(where: { $0.hidden != hidden }) else { return }
    drawing.history.commit(before: s.drawings)
    for i in s.drawings.indices { s.drawings[i].hidden = hidden }
    state = s; drawing.selected = nil; drawingChanged(items: s.drawings)
  }

  /// 删掉选中的那条（A7.6）。一次 rigid 触觉，没有确认弹窗——画错了重画就是了（§10.8）。
  public func deleteSelectedDrawing() {
    guard var s = state, let sel = drawing.selected,
      s.drawings.contains(where: { $0.id == sel })
    else { return }
    drawing.history.commit(before: s.drawings)
    s.drawings.removeAll { $0.id == sel }
    state = s
    drawing.selected = nil
    Haptics.boundary()
    drawingChanged(items: s.drawings)
  }

  /// 「完成」：退出画线态。线全部留着（A7.6），只是不再有工具、选中和半截的线。
  public func endDrawing() {
    let d = drawing
    d.tool = nil
    d.pending = nil
    d.aim = nil
    d.selected = nil
    d.drag = nil
    d.claimed = nil
    d.preview = nil
    if var s = state { s.drawingPreviewID = nil; state = s }
    drawingChanged()
  }

  public var canUndoDrawing: Bool { !drawing.anchors.isEmpty || drawing.history.canUndo }
  public var canRedoDrawing: Bool { drawing.history.canRedo }

  public func undoDrawing() {
    if !drawing.anchors.isEmpty { drawing.anchors.removeLast(); drawing.aim = nil; drawingChanged(); return }
    guard var s = state, let prev = drawing.history.undo(current: s.drawings) else { return }
    s.drawings = prev
    state = s
    afterHistoryJump(prev)
  }

  public func redoDrawing() {
    guard var s = state, let next = drawing.history.redo(current: s.drawings) else { return }
    s.drawings = next
    state = s
    afterHistoryJump(next)
  }

  private func afterHistoryJump(_ items: [Drawing]) {
    let d = drawing
    d.pending = nil
    d.aim = nil
    d.drag = nil
    if let sel = d.selected, !items.contains(where: { $0.id == sel }) { d.selected = nil }
    drawingChanged(items: items)
  }

  /// 线增删改了。`items` 只在真的动了线的时候给。
  public var onDrawingsChanged: (([Drawing]) -> Void)? {
    get { drawing.onChanged }
    set { drawing.onChanged = newValue }
  }

  /// 工具 / 选中 / 待落点变了——底栏和提示条照着重画一次就行。
  public var onDrawingStateChanged: (() -> Void)? {
    get { drawing.onState }
    set { drawing.onState = newValue }
  }

  /// 这个品种画满 50 条了（A7.7）。要不要提示由外面定，这里只负责不再往里塞。
  public var onDrawingLimitReached: (() -> Void)? {
    get { drawing.onFull }
    set { drawing.onFull = newValue }
  }

  /// 让覆盖层重画一次。外面改了 `state` 又想让手柄跟上时用。
  public func refreshDrawingOverlay() { drawing.overlay?.setNeedsDisplay() }

  fileprivate func drawingChanged(items: [Drawing]? = nil) {
    refreshDrawingOverlay()
    if let items { drawing.onChanged?(items) }
    drawing.onState?()
  }
}

// MARK: - 坐标

/// 这一帧的四个换算：时间↔x、价格↔y。
///
/// 每次触摸都现取：视野、价格区间、副图高度随时在变，缓存下来就会拖着上一帧的坐标走。
struct DrawAxes {
  var layout: Layout
  var pane: Pane
  var range: PriceRange
  var mode: PriceMode
  var view: ViewWindow
  var bounds: DrawBounds { DrawBounds(left: 0, top: pane.y, right: layout.plotW, bottom: pane.y + pane.h) }

  func x(_ t: Double) -> Double { view.x(t, plotW: layout.plotW) }
  func y(_ p: Double) -> Double { yOf(p, pane: pane, range: range, mode: mode) }
  func t(atX x: Double) -> Double { view.t(atX: x, plotW: layout.plotW) }
  func p(atY y: Double) -> Double { pOf(y, pane: pane, range: range, mode: mode) }
}

extension ChartView {
  var drawAxes: DrawAxes? {
    guard let s = state, !s.series.isEmpty, let L = chartLayout, let r = chartPriceRange
    else { return nil }
    return DrawAxes(layout: L, pane: L.main, range: r, mode: s.price.mode, view: s.view)
  }

  /// 屏幕坐标 → 画线端点。磁吸开着就吸到最近那根的 OHLC（A7.2、§10.8）。
  fileprivate func drawPoint(at q: CGPoint, axes: DrawAxes) -> DrawSnap {
    guard let s = state else { return DrawSnap(point: DrawPoint(t: 0, p: 0), index: -1) }
    let px = max(0, min(axes.layout.plotW, Double(q.x)))
    return snapDrawPoint(
      t: axes.t(atX: px), p: axes.p(atY: max(axes.pane.y, min(axes.pane.y + axes.pane.h, Double(q.y)))),
      series: s.series, magnet: drawing.magnet, xOf: axes.x, yOf: axes.y)
  }

  fileprivate func drawHitTest(_ q: CGPoint, axes: DrawAxes) -> DrawHit? {
    guard state?.options.drawings == true, axes.bounds.contains(DrawPixel(Double(q.x), Double(q.y))) else { return nil }
    // The selected object's handles get a finger-sized target and priority over
    // crossing lines. Unselected drawings keep their narrower selection hit area.
    if let item = drawings.first(where: { $0.id == drawing.selected && !$0.hidden }) {
      let g = drawingGeometry(item, bounds: axes.bounds, xOf: axes.x, yOf: axes.y)
      if let part = g.hit(x: Double(q.x), y: Double(q.y), handleRadius: 22) { return DrawHit(id: item.id, part: part) }
    }
    for item in drawings.reversed() where !item.hidden {
      let g = drawingGeometry(item, bounds: axes.bounds, xOf: axes.x, yOf: axes.y)
      if let part = g.hit(x: Double(q.x), y: Double(q.y)) { return DrawHit(id: item.id, part: part) }
    }
    return nil
  }

}

// MARK: - 触摸

/// 覆盖层把四个触摸回调原样转进来。
///
/// 判断顺序照原型 `_bind` 的 `pointerdown`：先看是不是在拖已有的线，再看是不是在
/// 落笔，都不是就把这次触摸整个还给图表手势。**和原型不同的是画线态下不禁用拖图**
/// ——原型 `if (this.drawMode) { mode = 'draw'; return }` 直接把平移关掉了，
/// 任务书 A7.8 / §10.8 要求照常能拖能捏，以任务书为准（见 `docs/acceptance/M7.md`）。
extension ChartView {
  private static func drawMs(_ event: UIEvent?) -> Double {
    (event?.timestamp ?? CACurrentMediaTime()) * 1000
  }

  func drawingTouchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    startDrawingLink()
    let d = drawing
    // 已经在拖线 / 在瞄第二点：多落下来的手指一概不理，别把正在画的东西打断。
    if let claimed = d.claimed {
      guard !touches.contains(claimed) else { return }
      // Transition the original touch and the new touch to a pinch. Keep completed anchors.
      if let drag = d.drag, var s = state, let i = s.drawings.firstIndex(where: { $0.id == drag.id }) {
        s.drawings[i] = drag.from; s.drawingPreviewID = nil; state = s
      }
      d.preview = nil; d.drag = nil; d.claimed = nil; d.aim = nil; d.navigating = true
      touchesBegan(Set([claimed]).union(touches), with: event)
      drawingChanged(); return
    }
    // 已经交给图表的手势：第二根手指要给它做捏合，继续转。
    if !gesture.touches.isEmpty {
      d.navigating = true
      touchesBegan(touches, with: event)
      return
    }
    guard touches.count == 1, let t = touches.first, let axes = drawAxes else {
      touchesBegan(touches, with: event)
      return
    }
    let q = t.location(in: self)
    // 右侧价格轴、底部时间轴归图表，画线不掺和。
    guard axes.bounds.contains(DrawPixel(Double(q.x), Double(q.y))) else {
      touchesBegan(touches, with: event)
      return
    }
    d.startPoint = q
    d.beganMs = Self.drawMs(event)
    d.moved = 0

    // 半截的趋势线：这根手指是用来瞄第二点的，预览线跟着走，抬手落点。
    if d.pending != nil {
      d.claimed = t
      captureDrawingLoupe()
      d.lastMagnetIndex = -1
      aimPending(at: q, axes: axes)
      return
    }

    // On a phone, first tap to select, then drag. Passing a finger over an
    // unselected endpoint must not accidentally edit a drawing instead of panning.
    if d.tool == nil, let hit = drawHitTest(q, axes: axes), d.selected == hit.id,
      let from = drawings.first(where: { $0.id == hit.id }), !from.locked, var s = state
    {
      d.claimed = t
      d.selected = hit.id
      captureDrawingLoupe()
      d.preview = from
      s.drawingPreviewID = from.id
      d.drag = DrawingSession.Drag(id: hit.id, part: hit.part, from: from, start: q, axes: axes)
      s.crosshair = nil          // 拖线的时候十字线碍事
      state = s
      drawingChanged()
      return
    }

    touchesBegan(touches, with: event)
    if d.tool != nil { gesture.cancelLongPress() }
  }

  func drawingTouchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    let d = drawing
    guard let t = d.claimed, touches.contains(t), let axes = drawAxes else {
      touchesMoved(touches, with: event)
      return
    }
    let q = t.location(in: self)
    let dx = Double(q.x - d.startPoint.x), dy = Double(q.y - d.startPoint.y)
    d.moved = max(d.moved, (dx * dx + dy * dy).squareRoot())
    if d.drag != nil {
      applyDrag(to: q, axes: axes)
    } else if d.pending != nil {
      aimPending(at: q, axes: axes)
    }
  }

  func drawingTouchesEnded(_ touches: Set<UITouch>, with event: UIEvent?, cancelled: Bool) {
    let d = drawing
    guard let t = d.claimed, touches.contains(t) else {
      finishUnclaimed(touches, with: event, cancelled: cancelled)
      return
    }
    d.claimed = nil
    let axes = drawAxes

    if let drag = d.drag, var s = state, let i = s.drawings.firstIndex(where: { $0.id == drag.id }) {
      let preview = d.preview
      d.drag = nil; d.preview = nil; s.drawingPreviewID = nil
      if cancelled { s.drawings[i] = drag.from; state = s; drawingChanged(); return }
      if let preview { s.drawings[i] = preview }
      state = s
      if s.drawings[i] != drag.from {
        var before = s.drawings; before[i] = drag.from
        d.history.commit(before: before); drawingChanged(items: s.drawings)
      } else { drawingChanged() }
      return
    }
    // 瞄着第二点的那根手指抬起来了：落点。
    if let axes, d.pending != nil {
      if cancelled {
        d.aim = nil
        drawingChanged()
      } else {
        placeDrawPoint(at: t.location(in: self), axes: axes)
      }
    }
  }

  /// 这次触摸是图表手势在管的。抬手之前先看看该不该把这一下「轻点」收走。
  private func finishUnclaimed(_ touches: Set<UITouch>, with event: UIEvent?, cancelled: Bool) {
    let d = drawing
    let now = Self.drawMs(event)
    let isTap =
      !d.navigating && !cancelled && gesture.mode == .pan && gesture.moved < Chart.panSlopPt
      && now - d.beganMs < drawTapMs
    // 十字线在的时候这一下是用来收十字线的，不落笔也不改选中。
    let busy = state?.crosshair != nil

    if isTap, !busy, let axes = drawAxes, axes.bounds.contains(DrawPixel(Double(gesture.startPoint.x), Double(gesture.startPoint.y))) {
      let q = gesture.startPoint
      if d.tool != nil {
        // 原型 `pointerup` 里画线分支排在平移分支**前面**：画线态下这一下不会被
        // 当成双击复位。
        consumeTap()
        touchesEnded(touches, with: event)
        placeDrawPoint(at: q, axes: axes)
        return
      }
      let hit = drawHitTest(q, axes: axes)
      // 取消选中要给双击复位让路——原型里双击那一支也排在选中之前。
      if hit != nil || d.selected != nil {
        consumeTap()
        touchesEnded(touches, with: event)
        d.selected = hit?.id
        drawingChanged()
        return
      }
    }
    if cancelled {
      touchesCancelled(touches, with: event)
    } else {
      touchesEnded(touches, with: event)
    }
    if gesture.touches.isEmpty { d.navigating = false }
  }

  /// 把这一下轻点从图表手势里摘掉：`mode` 一清，`finishTouches` 的轻点、甩、双击
  /// 三个分支全都不成立，只剩一次无害的回弹判定。
  private func consumeTap() {
    gesture.mode = nil
  }

  // MARK: - 落笔

  private func aimPending(at q: CGPoint, axes: DrawAxes) {
    let d = drawing
    let snap = drawPoint(at: q, axes: axes)
    d.aim = snap.point
    if snap.index >= 0, snap.index != d.lastMagnetIndex {
      if d.lastMagnetIndex >= 0 { Haptics.magnetTick() }
      d.lastMagnetIndex = snap.index
    }
    refreshDrawingOverlay()
  }

  private func placeDrawPoint(at q: CGPoint, axes: DrawAxes) {
    guard var s = state, let tool = drawing.tool else { return }
    let d = drawing
    let snap = drawPoint(at: q, axes: axes)
    let pt = snap.point

    func commit(_ item: Drawing) {
      guard s.drawings.count < DrawArchive.perSymbolLimit else {
        // 满了就不画，也不偷偷挤掉最早那条——用户多半根本没看见它被挤掉。
        Haptics.boundary()
        d.pending = nil
        d.aim = nil
        d.onFull?()
        drawingChanged()
        return
      }
      d.history.commit(before: s.drawings)
      s.drawings.append(item)
      state = s
      d.tool = d.continuous ? tool : nil
      d.selected = item.id
      d.pending = nil
      d.aim = nil
      if snap.index >= 0 { Haptics.magnetTick() }
      drawingChanged(items: s.drawings)
    }

    if let last = d.anchors.last, hypot(axes.x(last.t) - axes.x(pt.t), axes.y(last.p) - axes.y(pt.p)) < 3 { return }
    let points = d.anchors + [pt]
    if points.count == tool.pointCount {
      var item = Drawing(kind: tool, points: points)
      if let style = d.styles[tool.rawValue] {
        item.color = style.color; item.lineWidth = style.lineWidth; item.dash = style.dash
        item.filled = style.filled; item.levels = style.levels
      }
      commit(item)
    } else {
      d.anchors.append(pt); d.aim = nil; d.lastMagnetIndex = snap.index
      if snap.index >= 0 { Haptics.magnetTick() }
      drawingChanged()
    }
  }

  // MARK: - 拖

  private func applyDrag(to q: CGPoint, axes: DrawAxes) {
    guard let drag = drawing.drag else { return }
    let axes = drag.axes
    let dx = Double(q.x - drag.start.x), dy = Double(q.y - drag.start.y)
    var item = movedDrawing(drag.from, part: drag.part, dt: dx / axes.layout.plotW * axes.view.span,
                            priceShift: { axes.p(atY: axes.y($0) + dy) })
    if drag.part != .body {
      let index = drag.part == .a ? 0 : (drag.part == .b ? 1 : 2)
      if item.points.indices.contains(index) { item.points[index] = drawPoint(at: q, axes: axes).point }
    }
    drawing.preview = item
    refreshDrawingOverlay()
  }

  private func captureDrawingLoupe() {
    guard let renderer else { return }
    drawing.loupe = UIGraphicsImageRenderer(size: bounds.size).image { context in
      renderer.drawPlot(in: context.cgContext, size: bounds.size, scale: Double(contentScaleFactor))
    }
  }

  // MARK: - 覆盖层的帧

  /// 覆盖层画的是手柄和预览线，它们跟着视野走：拖图、捏合、甩出去的每一帧都得重画。
  /// 图表自己的脏位通道进不来（那是 `ChartState` 的事），所以在有触摸或有动画的时候
  /// 挂一条自己的 `CADisplayLink`，两样都没了立刻摘掉——A3.12 的「静止不跑帧」不破。
  fileprivate func startDrawingLink() {
    guard drawing.overlay != nil else { return }
    if let l = drawing.link {
      l.isPaused = false
      return
    }
    let l = CADisplayLink(target: DrawingLinkProxy(self), selector: #selector(DrawingLinkProxy.tick))
    l.add(to: .main, forMode: .common)
    drawing.link = l
  }

  fileprivate func drawingTick() {
    refreshDrawingOverlay()
    guard drawing.claimed == nil, gesture.touches.isEmpty, animation == nil else { return }
    drawing.link?.invalidate()
    drawing.link = nil
  }
}

/// 和 `LinkProxy` 同样的理由：`CADisplayLink` 强引用 target，直接指向视图会成环。
@MainActor
private final class DrawingLinkProxy: NSObject {
  private weak var view: ChartView?
  init(_ view: ChartView) {
    self.view = view
    super.init()
  }
  @objc func tick() { view?.drawingTick() }
}

// MARK: - 覆盖层

/// 盖在三层 `CALayer` 之上的一层：选中态、手柄、待落点、预览线，外加画线手势的入口。
///
/// 静态的线由 `ChartRenderer.drawDrawings` 画在底图上（M3 就有了），这里只补
/// **交互中间量**那一档：选中的那条用 amber 1.8pt 盖一遍（原型 `drawDrawings` 的
/// `sel` 分支），两端 r=5 的手柄，`pending` 的 amber 圆点，以及从第一点拉到手指的
/// 虚线预览。
///
/// 它比十字线那层还高，所以选中的线会压在十字线上面——两者同时出现的机会很少，
/// 换来的是渲染路径一行都不用改（A3.11 的 176 张基线全部原封不动）。
final class DrawingOverlayView: UIView {
  weak var host: ChartView?

  init(host: ChartView) {
    self.host = host
    super.init(frame: .zero)
    backgroundColor = .clear
    isOpaque = false
    contentMode = .redraw
    isMultipleTouchEnabled = true
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) 用不到") }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    host?.drawingTouchesBegan(touches, with: event)
  }
  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    host?.drawingTouchesMoved(touches, with: event)
  }
  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    host?.drawingTouchesEnded(touches, with: event, cancelled: false)
  }
  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    host?.drawingTouchesEnded(touches, with: event, cancelled: true)
  }

  override func draw(_ rect: CGRect) {
    guard let host, let ctx = UIGraphicsGetCurrentContext(), let s = host.state,
      let axes = host.drawAxes
    else { return }
    let d = host.drawing
    let t = s.colors
    guard s.options.drawings else { return }
    ctx.saveGState()
    defer { ctx.restoreGState() }
    // 画布只有图区那一块，别糊到轴上。
    ctx.clip(to: CGRect(x: 0, y: axes.pane.y, width: axes.layout.plotW, height: axes.pane.h))

    if let sel = d.selected, let item = s.drawings.first(where: { $0.id == sel }) {
      strokeSelected(d.preview ?? item, ctx: ctx, axes: axes, colors: t, decimals: s.decimals)
    }
    if let tool = d.tool, !d.anchors.isEmpty {
      var points = d.anchors
      if let aim = d.aim { points.append(aim) }
      if points.count == tool.pointCount {
        var preview = Drawing(kind: tool, points: points); preview.dash = .dashed
        paintDrawing(preview, ctx: ctx, axes: axes, colors: t, selected: true, handles: true)
      } else {
        for pt in points { handle(ctx: ctx, x: axes.x(pt.t), y: axes.y(pt.p), colors: t) }
        if points.count > 1 {
          paintDrawing(Drawing(kind: .trend, points: Array(points.prefix(2))), ctx: ctx, axes: axes, colors: t, selected: true, handles: false)
        }
      }
      if let aim = d.aim { readout(ctx, at: CGPoint(x: axes.x(aim.t), y: axes.y(aim.p)), point: aim, host: host, axes: axes) }
    }
    if let drag = d.drag, let item = d.preview ?? s.drawings.first(where: { $0.id == drag.id }), drag.part != .body {
      let index = drag.part == .a ? 0 : (drag.part == .b ? 1 : 2)
      if item.points.indices.contains(index) {
        let pt = item.points[index]
        readout(ctx, at: CGPoint(x: axes.x(pt.t), y: axes.y(pt.p)), point: pt, host: host, axes: axes)
      }
    }
  }

  private func strokeSelected(_ d: Drawing, ctx: CGContext, axes: DrawAxes, colors t: ChartColors, decimals: Int) {
    paintDrawing(d, ctx: ctx, axes: axes, colors: t, selected: true, handles: !d.locked)
  }

  /// Visual handle stays compact; the selected handle accepts a 44pt touch target.
  private func handle(ctx: CGContext, x: Double, y: Double, colors t: ChartColors) {
    let r = CGRect(x: x - 5, y: y - 5, width: 10, height: 10)
    ctx.setFillColor(Paint.cg(t.panel))
    ctx.fillEllipse(in: r)
    ctx.setStrokeColor(Paint.cg(t.amber))
    ctx.setLineWidth(1.4)
    ctx.strokeEllipse(in: r)
  }

  /// 手柄旁边的一颗读数胶囊：时间 · 价格。样式照十字线的读数（`crossBg` / `crossInk`）。
  private func readout(
    _ ctx: CGContext, at q: CGPoint, point: DrawPoint, host: ChartView, axes: DrawAxes
  ) {
    guard let s = host.state else { return }
    if let backdrop = host.drawing.loupe {
      let center = CGPoint(x: max(48, min(axes.layout.plotW - 48, Double(q.x))), y: max(axes.pane.y + 42, Double(q.y) - 95))
      let box = CGRect(x: center.x - 43, y: center.y - 33, width: 86, height: 66)
      ctx.saveGState(); ctx.addEllipse(in: box); ctx.clip()
      ctx.translateBy(x: center.x, y: center.y); ctx.scaleBy(x: 1.8, y: 1.8)
      backdrop.draw(at: CGPoint(x: -q.x, y: -q.y)); ctx.restoreGState()
      ctx.setStrokeColor(Paint.cg(s.colors.amber)); ctx.setLineWidth(1.5); ctx.strokeEllipse(in: box)
      ctx.beginPath(); ctx.move(to: CGPoint(x: center.x - 7, y: center.y)); ctx.addLine(to: CGPoint(x: center.x + 7, y: center.y))
      ctx.move(to: CGPoint(x: center.x, y: center.y - 7)); ctx.addLine(to: CGPoint(x: center.x, y: center.y + 7)); ctx.strokePath()
    }
    let text = fmtFull(ms: point.t, offsetMinutes: s.timezone.offsetMinutes) + " · "
      + fmtNum(point.p, s.decimals)
    let t = s.colors
    let w = Double(text.width(ChartFont.axis)) + 12
    let x = max(2, min(axes.layout.plotW - w - 2, Double(q.x) - w / 2))
    let y = max(2, Double(q.y) - 28)
    ctx.setFillColor(Paint.cg(t.crossBg))
    ctx.addRoundRect(CGRect(x: x, y: y, width: w, height: 17), radius: 3)
    ctx.fillPath()
    text.drawCentered(
      at: CGPoint(x: x + w / 2, y: y + 8.5), font: ChartFont.axis, color: t.crossInk)
  }
}

func paintDrawing(_ d: Drawing, ctx: CGContext, axes: DrawAxes, colors t: ChartColors,
                  selected: Bool = false, handles: Bool = false) {
  let g = drawingGeometry(d, bounds: axes.bounds, xOf: axes.x, yOf: axes.y)
  guard !d.hidden else { return }
  let color = d.color ?? t.band
  ctx.saveGState(); defer { ctx.restoreGState() }
  ctx.clip(to: CGRect(x: axes.bounds.left, y: axes.bounds.top, width: axes.layout.plotW, height: axes.pane.h))
  ctx.setStrokeColor(Paint.cg(color)); ctx.setLineWidth(d.lineWidth)
  ctx.setLineDash(phase: 0, lengths: d.dash == .solid ? [] : (d.dash == .dashed ? [6, 4] : [1, 3]))
  if d.filled, !selected, let first = g.polygon.first {
    ctx.saveGState(); ctx.setAlpha(0.12); ctx.setFillColor(Paint.cg(color))
    ctx.beginPath(); ctx.move(to: CGPoint(x: first.x, y: first.y))
    for p in g.polygon.dropFirst() { ctx.addLine(to: CGPoint(x: p.x, y: p.y)) }
    ctx.closePath(); ctx.fillPath(); ctx.restoreGState()
  }
  for line in g.segments {
    ctx.beginPath(); ctx.move(to: CGPoint(x: line.a.x, y: line.a.y)); ctx.addLine(to: CGPoint(x: line.b.x, y: line.b.y)); ctx.strokePath()
  }
  for label in g.labels where label.point.y >= axes.pane.y && label.point.y <= axes.pane.y + axes.pane.h {
    let width = Double(label.text.width(ChartFont.axis))
    label.text.drawRightBottom(at: CGPoint(x: max(width + 3, min(axes.layout.plotW - 3, label.point.x)), y: label.point.y), font: ChartFont.axis, color: color)
  }
  if selected, handles {
    ctx.setLineDash(phase: 0, lengths: [])
    let points = g.handles.isEmpty ? [DrawPixel(d.kind == .hline ? axes.layout.plotW / 2 : axes.x(d.a.t), d.kind == .vline ? axes.pane.y + axes.pane.h / 2 : axes.y(d.a.p))] : g.handles
    for p in points {
      let rect = CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)
      ctx.setFillColor(Paint.cg(t.panel)); ctx.fillEllipse(in: rect)
      ctx.setStrokeColor(Paint.cg(t.amber)); ctx.setLineWidth(1.5); ctx.strokeEllipse(in: rect)
    }
  }
}
