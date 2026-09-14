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
  }

  var tool: DrawingStore.Tool?
  var selected: String?
  /// 趋势线落了第一点、还差第二点。
  var pending: DrawPoint?
  /// 第二点此刻指到哪儿：`pending` 在的时候手指移动，预览线实时跟到这里（§10.8）。
  var aim: DrawPoint?
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
private let drawTapMs: Double = 200

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
    s.drawings = DrawArchive.capped(items)
    state = s
    let d = drawing
    d.selected = nil
    d.pending = nil
    d.aim = nil
    d.drag = nil
    d.history.clear()
    drawingChanged()
  }

  /// 图区顶部那一行提示（§10.8）。没选工具时是 `nil`，外面就把提示条收起来。
  public var drawHint: String? {
    switch drawing.tool {
    case .trend: return drawing.pending == nil ? "点两下画一条趋势线" : "再点一下"
    // 任务书只给了趋势线那两句，水平线一点即成，照同样的口气补一句。
    case .hline: return "点一下画一条水平线"
    case nil: return nil
    }
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
    drawingChanged()
  }

  public var canUndoDrawing: Bool { drawing.history.canUndo }
  public var canRedoDrawing: Bool { drawing.history.canRedo }

  public func undoDrawing() {
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
      t: axes.t(atX: px), p: axes.p(atY: Double(q.y)), series: s.series, magnet: s.magnet)
  }

  fileprivate func drawHitTest(_ q: CGPoint, axes: DrawAxes) -> DrawHit? {
    hitDraw(
      drawings, px: Double(q.x), py: Double(q.y),
      xOf: { axes.x($0) }, yOf: { axes.y($0) })
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
    if d.claimed != nil { return }
    // 已经交给图表的手势：第二根手指要给它做捏合，继续转。
    if !gesture.touches.isEmpty {
      touchesBegan(touches, with: event)
      return
    }
    guard touches.count == 1, let t = touches.first, let axes = drawAxes else {
      touchesBegan(touches, with: event)
      return
    }
    let q = t.location(in: self)
    // 右侧价格轴、底部时间轴归图表，画线不掺和。
    guard Double(q.x) <= axes.layout.plotW, Double(q.y) <= axes.layout.timeY else {
      touchesBegan(touches, with: event)
      return
    }
    d.startPoint = q
    d.beganMs = Self.drawMs(event)
    d.moved = 0

    // 半截的趋势线：这根手指是用来瞄第二点的，预览线跟着走，抬手落点。
    if d.pending != nil {
      d.claimed = t
      d.lastMagnetIndex = -1
      aimPending(at: q, axes: axes)
      return
    }

    // 命中已有的线。原型的规矩：手柄随时可拖，线身只有已经选中的那条才拖得动，
    // 否则从线上划过去就再也拖不动图了。
    if let hit = drawHitTest(q, axes: axes), d.selected == hit.id || hit.part != .body,
      let from = drawings.first(where: { $0.id == hit.id }), var s = state
    {
      d.claimed = t
      d.selected = hit.id
      d.drag = DrawingSession.Drag(id: hit.id, part: hit.part, from: from, start: q)
      d.history.commit(before: s.drawings)
      s.crosshair = nil          // 拖线的时候十字线碍事
      state = s
      drawingChanged()
      return
    }

    touchesBegan(touches, with: event)
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

    if d.drag != nil {
      d.drag = nil
      drawingChanged(items: drawings)
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
      !cancelled && gesture.mode == .pan && gesture.moved < Chart.panSlopPt
      && now - d.beganMs < drawTapMs
    // 十字线在的时候这一下是用来收十字线的，不落笔也不改选中。
    let busy = state?.crosshair != nil

    if isTap, !busy, let axes = drawAxes {
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
      let isDoubleTap = now - gesture.lastTapMs < Chart.doubleTapMs
      // 取消选中要给双击复位让路——原型里双击那一支也排在选中之前。
      if (hit != nil || d.selected != nil) && !isDoubleTap {
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
  }

  /// 把这一下轻点从图表手势里摘掉：`mode` 一清，`finishTouches` 的轻点、甩、双击
  /// 三个分支全都不成立，只剩一次无害的回弹判定。
  private func consumeTap() {
    gesture.mode = nil
    gesture.lastTapMs = 0
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
      d.tool = nil
      d.pending = nil
      d.aim = nil
      if s.magnet { Haptics.magnetTick() }
      drawingChanged(items: s.drawings)
    }

    switch tool {
    case .hline:
      commit(Drawing(kind: .hline, a: pt))
    case .trend:
      if let first = d.pending {
        commit(Drawing(kind: .trend, a: first, b: pt))
      } else {
        d.pending = pt
        d.aim = nil
        d.lastMagnetIndex = snap.index
        if s.magnet { Haptics.magnetTick() }
        drawingChanged()
      }
    }
  }

  // MARK: - 拖

  private func applyDrag(to q: CGPoint, axes: DrawAxes) {
    guard var s = state, let drag = drawing.drag,
      let i = s.drawings.firstIndex(where: { $0.id == drag.id })
    else { return }
    let dxPx = Double(q.x - drag.start.x)
    let dyPx = Double(q.y - drag.start.y)
    let dt = dxPx / axes.layout.plotW * s.view.span
    // 价格按**像素**平移：对数 / 百分比模式下等价差不等于等像素（A7.5）。
    s.drawings[i] = movedDrawing(
      drag.from, part: drag.part, dt: dt,
      priceShift: { axes.p(atY: axes.y($0) + dyPx) })
    state = s
    refreshDrawingOverlay()
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
    ctx.saveGState()
    defer { ctx.restoreGState() }
    // 画布只有图区那一块，别糊到轴上。
    ctx.clip(to: CGRect(x: 0, y: 0, width: axes.layout.plotW, height: axes.layout.timeY))

    if let sel = d.selected, let item = s.drawings.first(where: { $0.id == sel }) {
      strokeSelected(item, ctx: ctx, axes: axes, colors: t, decimals: s.decimals)
    }
    if let first = d.pending {
      let x1 = axes.x(first.t), y1 = axes.y(first.p)
      if let aim = d.aim {
        // 预览用虚线：还没落的东西不能和画好的线长一个样。
        ctx.setStrokeColor(Paint.cg(t.amber))
        ctx.setLineWidth(1.3)
        ctx.setLineDash(phase: 0, lengths: [4, 3])
        ctx.beginPath()
        ctx.move(to: CGPoint(x: x1, y: y1))
        ctx.addLine(to: CGPoint(x: axes.x(aim.t), y: axes.y(aim.p)))
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        readout(ctx, at: CGPoint(x: axes.x(aim.t), y: axes.y(aim.p)), point: aim, host: host, axes: axes)
      }
      ctx.setFillColor(Paint.cg(t.amber))
      ctx.fillEllipse(in: CGRect(x: x1 - 4, y: y1 - 4, width: 8, height: 8))
    }
    if let drag = d.drag, let item = s.drawings.first(where: { $0.id == drag.id }),
      drag.part != .body
    {
      // §10.8：拖手柄时给出该点的 时间 · 价格。
      let pt = drag.part == .a ? item.a : (item.b ?? item.a)
      readout(ctx, at: CGPoint(x: axes.x(pt.t), y: axes.y(pt.p)), point: pt, host: host, axes: axes)
    }
  }

  private func strokeSelected(
    _ d: Drawing, ctx: CGContext, axes: DrawAxes, colors t: ChartColors, decimals: Int
  ) {
    ctx.setStrokeColor(Paint.cg(t.amber))
    ctx.setLineWidth(1.8)
    ctx.setLineDash(phase: 0, lengths: [])
    if d.kind == .hline {
      let y = axes.y(d.a.p)
      ctx.beginPath()
      ctx.move(to: CGPoint(x: 0, y: y))
      ctx.addLine(to: CGPoint(x: axes.layout.plotW, y: y))
      ctx.strokePath()
      fmtNum(d.a.p, decimals).drawRightBottom(
        at: CGPoint(x: axes.layout.plotW - 4, y: y - 3), font: ChartFont.axis, color: t.amber)
      handle(ctx: ctx, x: axes.layout.plotW / 2, y: y, colors: t)
    } else if let b = d.b {
      let x1 = axes.x(d.a.t), y1 = axes.y(d.a.p)
      let x2 = axes.x(b.t), y2 = axes.y(b.p)
      ctx.beginPath()
      ctx.move(to: CGPoint(x: x1, y: y1))
      ctx.addLine(to: CGPoint(x: x2, y: y2))
      ctx.strokePath()
      handle(ctx: ctx, x: x1, y: y1, colors: t)
      handle(ctx: ctx, x: x2, y: y2, colors: t)
    }
  }

  /// 原型的 `handle()`：r=5 的圆，`panel` 填、amber 描 1.4。
  /// 看着是 10pt，但命中半径是 12pt（`Chart.hitHandlePt`），实际可按范围 24pt，
  /// 满足 §10.8 的「直径 22pt 好按」。
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
