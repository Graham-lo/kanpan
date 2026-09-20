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
    // 这里从前还存过一份**按下那一刻的坐标换算**（`axes`），`applyDrag` 拿它遮蔽实时的
    // `axes` 参数。于是拖动过程中行情推动自动纵轴、价格区间一变，落地的价格还是按旧轴算的，
    // 手指在这儿、线落在那儿（A-08）。基准只需要 `from` + `start` 这两样就够了：
    // 前者保证不逐帧累加，后者给出位移；换算一律用**当前这一帧**的。
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

/// 「轻点」的时长上限：按下到抬起 < 500ms 且位移 < 4pt 才算落笔。
///
/// §10.8 的原文写的是 200ms，那是照着鼠标的 click 抄来的数。手指不是鼠标——落笔要先
/// 瞄准，指腹压上去、看一眼落点再抬起，200ms 根本来不及，实测一大半「点」会被判成
/// 没动够距离的拖动而整个丢掉。所以**这里以 500ms 为准，不改回 200ms**（第五轮审查
/// A.4 的裁决）；真正把「点」和「拖」分开的是位移那一半，它复用 `Chart.panSlopPt`，
/// 和图表手势是同一个 4pt。长按（`Chart.longPressMs` = 400ms）走的是另一条路，
/// 手指一旦停住到 400ms 就被十字线接走，不会跟这 500ms 抢。
private let drawTapMs: Double = 500

extension ChartView {
  /// 这张图的画线会话。第一次问的时候建。
  var drawing: DrawingSession {
    if let s = drawingSessionIfLoaded { return s }
    let s = DrawingSession()
    objc_setAssociatedObject(self, drawingSessionKey, s, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    return s
  }

  /// 已经建过的那份会话，没建过就是 `nil`。
  ///
  /// 出窗清理要用它：那条路上问 `drawing` 会把会话**建出来**——一张从没开过画线的图
  /// 只是转了个屏，就凭空多挂一个关联对象。只有真开过画线的图才有东西要收。
  var drawingSessionIfLoaded: DrawingSession? {
    objc_getAssociatedObject(self, drawingSessionKey) as? DrawingSession
  }

  /// 视图离开窗口：把画线那条帧循环和半截交互态一起收掉。
  ///
  /// 它原来只有一条自灭路径（`drawingTick` 里发现触点、动画都空了才 invalidate），
  /// 而离屏之后根本不会再有下一帧——于是 link 连同 `CADisplayLink` 注册在主 runloop
  /// 上的那份强引用一直活到进程结束。手指是跟着视图一起离开的，`claimed` 和拖动快照
  /// 留着，回来第一下会被当成上一次拖动的续拍；预览线留着，下次入窗先闪一根上一程的线。
  /// 待落点（`anchors`）不收：那是用户明确点下的第一点，转个屏不该让它消失。
  func teardownDrawingLink() {
    guard let session = drawingSessionIfLoaded else { return }
    session.link?.invalidate()
    session.link = nil
    session.claimed = nil
    session.drag = nil
    session.preview = nil
    session.aim = nil
    session.loupe = nil
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
  /// **整批外部替换**：换品种、换存储、云端推下来的那一桶真的变了，才走这儿。
  ///
  /// 它和「本地交互编辑」是两套撤销策略：本地每一笔编辑都进 `drawing.history`，撤销
  /// 一步步往回走；而外部替换是「这张图上的线换了一整套」，上一套的撤销步骤全部失效
  /// （撤回去会撤成别人那份数据的中间态），所以这里把撤销栈连同选中项、半截交互态一起清掉。
  ///
  /// 正因为代价是整条撤销历史，调用方有责任先确认**当前这一桶**真的变了——
  /// 别的品种的云端变化不该清掉本图的撤销历史（A-07，见 `DrawingController.publishSynced`）。
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
    if tool.pointCount == 1 { return "按住放置" + tool.title }
    let placed = drawing.anchors.count
    switch tool {
    // 三点工具各有各的说法，统一说「选择终点」等于什么都没说。
    case .position: return ["按住放置入场价", "选择目标价", "选择止损价"][min(placed, 2)]
    case .fibExtension: return ["按住拖动画起点 A", "选择回调点 B", "选择起算点 C"][min(placed, 2)]
    case .channel: return placed == 2 ? "选择通道宽度" : (placed == 0 ? "按住拖动画" + tool.title : "选择终点")
    case .regression: return placed == 0 ? "圈住要拟合的那一段" : "选择这一段的终点"
    // 形态类点数多，一路数下去比「选择终点」有用：用户照着字母摆点就行。
    case .xabcd: return ["按住放置 X 点", "选择 A 点", "选择 B 点", "选择 C 点", "选择 D 点"][min(placed, 4)]
    case .abcd: return ["按住放置 A 点", "选择 B 点", "选择 C 点", "选择 D 点"][min(placed, 3)]
    case .headShoulders:
      return ["按住放置起点", "选择左肩", "选择左颈线点", "选择头部", "选择右颈线点", "选择右肩", "选择终点"][min(placed, 6)]
    case .elliottImpulse: return placed == 0 ? "按住放置 0 点" : "选择 \(placed) 浪终点"
    case .elliottCorrection: return ["按住放置 0 点", "选择 A 浪终点", "选择 B 浪终点", "选择 C 浪终点"][min(placed, 3)]
    case .pitchfork: return ["按住放置柄部 A", "选择枢轴 B", "选择枢轴 C"][min(placed, 2)]
    case .fibChannel: return ["按住拖动画基线起点", "选择基线终点", "选择通道宽度"][min(placed, 2)]
    case .triangle: return ["按住放置第一个角", "选择第二个角", "选择第三个角"][min(placed, 2)]
    case .curve: return ["按住放置起点", "选择终点", "拉出弯曲方向"][min(placed, 2)]
    case .callout: return placed == 0 ? "按住指向要标注的位置" : "选择气泡落点"
    default: return placed == 0 ? "按住拖动画" + tool.title : "选择终点"
    }
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

/// 量一行画线标签有多宽多高。
///
/// 命中测试与渲染共用这一个入口：两边各量各的，排出来的位置就会差那么几个像素，
/// 「看得见的字」和「点得中的字」也就对不上了（A-01）。
func measureDrawLabel(_ text: String) -> DrawTextSize {
  let size = ChartFont.measure(text, ChartFont.axis)
  return DrawTextSize(width: Double(size.width), height: Double(size.height))
}

/// 拖锚点时浮在手指上的那只圆镜头摆在哪儿（A.5 用例 18）。
///
/// 单拎出来是因为这三件事必须能被单测，而画它的 `readout` 要 `CGContext` 才跑得起来：
///
/// - **同源**：镜子里放大的就是这一帧的图（`captureDrawingLoupe` 抓的那张），圆心对准
///   锚点 `q`，所以「看见的」和「落下的」永远是同一处；`source` 就是被放大的那块原图区域。
/// - **不挡落点**：默认浮在手指上方 95pt。锚点贴着主图顶边时上面摆不下——原来的写法
///   是把镜头夹到 `pane.y + 42`，于是镜头自己压住了落点，放大镜就白装了；现在上面
///   放不下就翻到手指**下方**，上下都放不下才横着让开一格。
/// - **不越界**：整只镜头留在主图区里，不压到价格轴和副图上。
struct DrawLoupeFrame {
  /// 镜心（屏幕坐标）。
  var center: CGPoint
  /// 镜头的外接方框，圆就内切在里面。
  var box: CGRect
  /// 放大倍数。
  var scale: Double
  /// 镜子里那块被放大的原图区域（屏幕坐标）。圆心正是锚点。
  var source: CGRect

  init(at q: CGPoint, plotW: Double, pane: Pane, scale: Double = 1.8) {
    let halfW = 43.0, halfH = 33.0, lift = 95.0
    let top = pane.y, bottom = pane.y + pane.h
    var cx = max(halfW + 5, min(plotW - halfW - 5, Double(q.x)))
    var cy = Double(q.y) - lift
    if cy - halfH < top {
      cy = Double(q.y) + lift                      // 上面摆不下：翻到手指下方
      if cy + halfH > bottom {                     // 上下都摆不下：贴住能放的位置，横着让开
        cy = max(top + halfH, min(bottom - halfH, Double(q.y)))
        let side = Double(q.x) > plotW / 2 ? -(halfW + 20) : (halfW + 20)
        cx = max(halfW + 5, min(plotW - halfW - 5, Double(q.x) + side))
      }
    }
    self.center = CGPoint(x: cx, y: cy)
    self.box = CGRect(x: cx - halfW, y: cy - halfH, width: halfW * 2, height: halfH * 2)
    self.scale = scale
    self.source = CGRect(x: Double(q.x) - halfW / scale, y: Double(q.y) - halfH / scale,
                         width: halfW * 2 / scale, height: halfH * 2 / scale)
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
  /// 价格轴当前的小数位。画线标签照它写，别在同一屏上出现两种价格写法（§2E6）。
  var decimals: Int = 2
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
    return DrawAxes(layout: L, pane: L.main, range: r, mode: s.price.mode, view: s.view,
                    decimals: s.decimals)
  }

  /// 屏幕坐标 → 画线端点。磁吸开着就吸到最近那根的 OHLC（A7.2、§10.8）。
  fileprivate func drawPoint(at q: CGPoint, axes: DrawAxes) -> DrawSnap {
    guard let s = state else { return DrawSnap(point: DrawPoint(t: 0, p: 0), index: -1) }
    let px = max(0, min(axes.layout.plotW, Double(q.x)))
    return snapDrawPoint(
      t: axes.t(atX: px), p: axes.p(atY: max(axes.pane.y, min(axes.pane.y + axes.pane.h, Double(q.y)))),
      series: s.series, magnet: drawing.magnet, xOf: axes.x, yOf: axes.y)
  }

  /// 一条线这一帧的几何，外加它那些字**排好版之后**真正盖住的矩形。
  ///
  /// 排版走的是和画图同一个入口（`layoutLabels` → `placeDrawingLabels`），量字用的也是
  /// 同一支字体、同一份小数位，所以屏幕上看得见多大一块，手指就能点中多大一块（A-01）。
  func drawGeometry(_ item: Drawing, axes: DrawAxes) -> DrawGeometry {
    var g = drawingGeometry(item, bounds: axes.bounds, xOf: axes.x, yOf: axes.y,
                            decimals: axes.decimals)
    g.layoutLabels(plotW: axes.layout.plotW, paneY: axes.pane.y, paneH: axes.pane.h,
                   measure: measureDrawLabel)
    return g
  }

  /// 点在哪条线的哪个部位上。
  ///
  /// 三遍，一遍比一遍松，**整层比完才往下一层**：
  ///
  /// ① **手柄**。选中那条给 `Chart.selectedHandlePt`（22pt）的手指靶，别的按
  ///    `Chart.hitHandlePt`（9.5pt）。同一遍里比的是真实距离，所以两条线的端点凑在一起时
  ///    谁近点中谁；选中项在同样够得着的时候优先——那是用户正在编辑的那组端点。
  /// ② **看得见的墨**：线体与文字。比的还是真实距离，一样近就让上面那条赢。
  /// ③ **填充区**。整片都算，所以它必须垫底。
  ///
  /// 从前是「选中那条先整只判一遍，`handleRadius: 22`」——那个 22pt 顺手把线体和整块填充
  /// 也放大了，而且一命中就提前返回：选中一个矩形之后，压在它里面的趋势线、它自己的
  /// 手柄以外的一切，全被这块填充吞掉（A-02）。
  fileprivate func drawHitTest(_ q: CGPoint, axes: DrawAxes) -> DrawHit? {
    guard state?.options.drawings == true, axes.bounds.contains(DrawPixel(Double(q.x), Double(q.y))) else { return nil }
    let x = Double(q.x), y = Double(q.y)
    // 后画的在上面，所以从后往前遍历：同样近的时候先到的那条就是上面那条。
    let visible = drawings.reversed().filter { !$0.hidden }
    let shapes = visible.map { (item: $0, geometry: drawGeometry($0, axes: axes)) }

    var handle: (hit: DrawHit, distance: Double, selected: Bool)?
    for shape in shapes {
      let selected = shape.item.id == drawing.selected
      let radius = selected ? Chart.selectedHandlePt : Chart.hitHandlePt
      guard let near = shape.geometry.nearestHandle(x: x, y: y, radius: radius) else { continue }
      let better = handle.map { old in
        old.selected == selected ? near.distance < old.distance : selected
      } ?? true
      if better {
        handle = (DrawHit(id: shape.item.id, part: .anchor(near.index)), near.distance, selected)
      }
    }
    if let handle { return handle.hit }

    var ink: (hit: DrawHit, distance: Double)?
    for shape in shapes {
      guard let d = shape.geometry.inkDistance(x: x, y: y) else { continue }
      if ink == nil || d < ink!.distance { ink = (DrawHit(id: shape.item.id, part: .body), d) }
    }
    if let ink { return ink.hit }

    for shape in shapes where shape.geometry.hitsFill(x: x, y: y) {
      return DrawHit(id: shape.item.id, part: .body)
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
      // 放大镜也要跟着这一程一起结束：它扣着一张整屏位图（`DrawLoupe.image`），
      // 这一指既然转交给捏合了，镜子既没人看也没人再更新，留着就是一张压在内存里
      // 的死图，还会跟着后面的缩放一起被画出来（A.5 用例 18「二指介入 → 释放无残留」）。
      d.loupe = nil
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

    // 手上拿着工具：按下就是第一点，拖到哪儿画到哪儿，抬手成线（第二批 7）。
    //
    // 原来只认「轻点两下」：按下—拖—抬手会被当成平移，什么都不留下，而这恰恰是
    // 所有人第一次画线的下意识动作。现在这根手指整场归画线，单指平移在握着工具时
    // 让位——两指照常平移捏合（`claimed` 分支会把它整场转交），画完一条工具自动
    // 松手（连续画线默认关），平移立刻回来。位移不够就退回轻点，「点两下」那条路
    // 一点没丢。
    if d.tool != nil, d.anchors.isEmpty {
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
      d.drag = DrawingSession.Drag(id: hit.id, part: hit.part, from: from, start: q)
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
    } else if d.tool != nil {
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
    // 放大镜的底图是一整张屏幕大的位图，只在这一程拖动里有用。原来只有
    // `teardownDrawingLink`（离窗）才收，于是一次拖动之后它一直压在会话里，
    // 下一次按下再抓一张新的——「释放无残留」这条得在抬手这一刻就成立（A.5 用例 18）。
    d.loupe = nil
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
    // 瞄着落点的那根手指抬起来了。
    guard let axes, let tool = d.tool else { return }
    if cancelled {
      d.aim = nil
      drawingChanged()
      return
    }
    let q = t.location(in: self)
    guard d.anchors.isEmpty else {
      placeDrawPoint(at: q, axes: axes)
      return
    }
    d.aim = nil
    // 单点的线（水平线、竖线）按下去只是先放着，抬手那一刻才算数——中间可以一直挪，
    // 放大镜就在手指上面，挪到哪儿看到哪儿。
    if tool.pointCount == 1 {
      placeDrawPoint(at: q, axes: axes)
      return
    }
    // 拖过了：这一笔是完整的一条线，起点在按下处，终点在抬手处。
    // 没拖动：只是轻点，落第一点，接着按老规矩点第二下。
    let dragged = d.moved >= Chart.panSlopPt * 2
    placeDrawPoint(at: d.startPoint, axes: axes)
    if dragged { placeDrawPoint(at: q, axes: axes) }
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
      // 连续模式下别顺手选中：手里还攥着同一把工具要接着画，底下却弹出一条
      // 「样式／锁定／复制／删除」的选中条，画一条弹一次，挡着图还得先点空白取消。
      // 一次性模式才选中——那一刻用户多半正想调它的颜色粗细。
      d.selected = d.continuous ? nil : item.id
      d.pending = nil
      d.aim = nil
      if snap.index >= 0 { Haptics.magnetTick() }
      drawingChanged(items: s.drawings)
    }

    if let last = d.anchors.last, hypot(axes.x(last.t) - axes.x(pt.t), axes.y(last.p) - axes.y(pt.p)) < 3 { return }
    var points = d.anchors + [pt]
    // 收口看的是 `placeCount`（手指要点几下），存下来的是 `pointCount`（这条线由几个点描述）。
    // 只有回归通道两者不同：用户圈起止两点，第三点由最小二乘拟合出来补上。
    if points.count == tool.placeCount {
      if tool == .regression {
        // 拟合不出来（圈住的 K 线不到 3 根）就当这一点没落，提示条还停在「选择终点」上，
        // 用户往右再点远一些就成了——比画出一条没有数据支持的通道诚实。
        guard let fitted = Drawing.fittedRegression(from: points, series: s.series) else {
          Haptics.boundary()
          return
        }
        points = fitted
      }
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

  /// 把这一帧的手指位置落成预览线。
  ///
  /// `axes` 是**当前这一帧**的换算，不是按下那一刻的：拖动期间行情照样在推，自动纵轴
  /// 会随着新高新低重算，价格区间一变，同一个价格对应的 y 就换了地方。按旧轴算出来的
  /// 价格落回新轴上就是偏的——手指在这儿，线在那儿（A-08）。不逐帧累加这件事由
  /// `drag.from` + `drag.start` 保证，和坐标用哪一帧是两回事。
  private func applyDrag(to q: CGPoint, axes: DrawAxes) {
    guard let drag = drawing.drag else { return }
    let dx = Double(q.x - drag.start.x), dy = Double(q.y - drag.start.y)
    var item = movedDrawing(drag.from, part: drag.part, dt: dx / axes.layout.plotW * axes.view.span,
                            priceShift: { axes.p(atY: axes.y($0) + dy) })
    if drag.part != .body {
      let index = drag.part.index ?? 0
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
    // 和主图那条一样：不在窗口上就不建帧循环——没有下一帧，也就没人来收它。
    guard drawing.overlay != nil, window != nil else { return }
    if let l = drawing.link {
      l.isPaused = false
      return
    }
    let l = CADisplayLink(target: DrawingLinkProxy(self), selector: #selector(DrawingLinkProxy.tick(_:)))
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
/// 弱引用之外还得管一件事：宿主一旦释放就没人再来 `invalidate()` 这条 link，它会挂在
/// 主 runloop 上每帧醒一次、一直醒到进程结束。所以把 link 自己收进回调里
/// （selector 带一个参数时 `CADisplayLink` 会把自己传过来），宿主空了就地作废。
@MainActor
private final class DrawingLinkProxy: NSObject {
  private weak var view: ChartView?
  init(_ view: ChartView) {
    self.view = view
    super.init()
  }
  @objc func tick(_ link: CADisplayLink) {
    guard let view else { link.invalidate(); return }
    view.drawingTick()
  }
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
      // 正在拖的那条底层跳过了（`drawingPreviewID`），得由覆盖层整只画；
      // 没在拖的那条底层已经画好，这里只补手柄——再整只画一遍就是两层字叠在一起。
      let live = s.drawingPreviewID == sel
      let shown = d.preview ?? item
      paintDrawing(shown, ctx: ctx, axes: axes, colors: t,
                   selected: true, handles: !shown.locked, shape: live)
    }
    if let tool = d.tool, !d.anchors.isEmpty || d.aim != nil {
      var points = d.anchors
      if let aim = d.aim { points.append(aim) }
      // 回归通道的预览也得先拟合，不然两个点喂给 `.regression` 的几何是画不出东西的。
      // 拟合失败（圈住的 K 线太少）就退到下面那条「只画手柄和一条连线」的路上。
      if points.count == tool.placeCount, tool == .regression {
        points = Drawing.fittedRegression(from: points, series: s.series) ?? points
      }
      if points.count == tool.pointCount {
        var preview = Drawing(kind: tool, points: points); preview.dash = .dashed
        paintDrawing(preview, ctx: ctx, axes: axes, colors: t, selected: true, handles: true)
      } else {
        for pt in points { handle(ctx: ctx, x: axes.x(pt.t), y: axes.y(pt.p), colors: t) }
        // 还没点够的时候把**已经落下的点全连起来**，不是只连前两个。
        // XABCD 要点五下、头肩要点七下，从前点到第四下屏幕上还是当初那一小段，
        // 用户看不出自己画到哪儿了。
        for i in 1 ..< max(points.count, 1) {
          var link = Drawing(kind: .trend, points: Array(points[(i - 1)...i]))
          link.dash = .dashed
          paintDrawing(link, ctx: ctx, axes: axes, colors: t, selected: true, handles: false)
        }
      }
      if let aim = d.aim { readout(ctx, at: CGPoint(x: axes.x(aim.t), y: axes.y(aim.p)), point: aim, host: host, axes: axes) }
    }
    if let drag = d.drag, let item = d.preview ?? s.drawings.first(where: { $0.id == drag.id }), drag.part != .body {
      let index = drag.part.index ?? 0
      if item.points.indices.contains(index) {
        let pt = item.points[index]
        readout(ctx, at: CGPoint(x: axes.x(pt.t), y: axes.y(pt.p)), point: pt, host: host, axes: axes)
      }
    }
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
      let lens = DrawLoupeFrame(at: q, plotW: axes.layout.plotW, pane: axes.pane)
      let center = lens.center, box = lens.box
      ctx.saveGState(); ctx.addEllipse(in: box); ctx.clip()
      ctx.translateBy(x: center.x, y: center.y); ctx.scaleBy(x: lens.scale, y: lens.scale)
      // 底图整张平移到「锚点落在镜心」，所以镜子里放大的就是 `q` 周围那一块，
      // 和手指真正会落下的地方同源——这是用例 18 的第一条断言。
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

/// 把一条画线画出来。
///
/// `shape` 关掉时只画手柄：**同一条线不能被画两遍**。底层（`ChartRenderer.drawDrawings`）
/// 已经把除了正在拖的那条以外的全画过了，覆盖层要是再整只画一遍，两遍字叠在一个锚点上——
/// 只要两遍的小数位不一样（底层从前漏传 `decimals`，默认 2；覆盖层传的是品种真实位数），
/// 屏幕上就是「+0.00」压着「+0.0000147」的一团墨。选中态要加的只有手柄。
/// 一条线上的那些字。
///
/// 两件从前没人管的事在这儿一起做了：
///
/// **底板。** 9pt 的小字直接压在 K 线上是读不出来的——一根绿柱穿过小数点，
/// 「+1600.96」就成了「+1600 96」。读数给实心胶囊配反白字（和价格轴上的现价标签
/// 同一套语言），刻度只垫一层图表底色把线挡掉（见 `DrawPlate`）。
///
/// **避让。** 斐波那契一口气铺七八档，缩放到某个倍数上相邻两档只差三四个像素，
/// 几串数字糊在一起谁也认不出。先按纵向排一遍，横向真的有交叠就把后来的那条
/// 往下让一行；让到图外就干脆不画——图上少一档刻度，好过多一团墨。
///
/// 排版本身（夹进图区、往下让行、让到图外就不画）已经搬去 Core 的 `placeDrawingLabels`，
/// 因为命中测试要的就是这批矩形——画多大一块、点中多大一块，得是同一份算式（A-01）。
/// 这里只剩「照着排好的位置把底板和字画出来」。
private func paintDrawingLabels(_ placed: [PlacedDrawLabel], ctx: CGContext,
                                colors t: ChartColors, ink: (DrawTint) -> Hex) {
  for item in placed {
    let label = item.label
    let rect = CGRect(x: item.box.left, y: item.box.top,
                      width: item.box.right - item.box.left, height: item.box.bottom - item.box.top)
    let tint = ink(label.tint)
    switch label.plate {
    case .none: break
    case .wash:
      ctx.saveGState(); ctx.setAlpha(0.85)
      ctx.setFillColor(Paint.cg(t.bg)); ctx.addRoundRect(rect, radius: 3); ctx.fillPath()
      ctx.restoreGState()
    case .chip:
      ctx.setFillColor(Paint.cg(tint)); ctx.addRoundRect(rect, radius: 3); ctx.fillPath()
    }
    label.text.drawCentered(at: CGPoint(x: item.center.x, y: item.center.y), font: ChartFont.axis,
                            color: label.plate == .chip ? t.bg : tint)
  }
}

func paintDrawing(_ d: Drawing, ctx: CGContext, axes: DrawAxes, colors t: ChartColors,
                  selected: Bool = false, handles: Bool = false, shape: Bool = true) {
  var g = drawingGeometry(d, bounds: axes.bounds, xOf: axes.x, yOf: axes.y, decimals: axes.decimals)
  let placedLabels = g.layoutLabels(plotW: axes.layout.plotW, paneY: axes.pane.y, paneH: axes.pane.h,
                                    measure: measureDrawLabel)
  guard !d.hidden else { return }
  let color = d.color ?? t.band
  ctx.saveGState(); defer { ctx.restoreGState() }
  ctx.clip(to: CGRect(x: axes.bounds.left, y: axes.bounds.top, width: axes.layout.plotW, height: axes.pane.h))
  // 「多空持仓框」的两半要跟着图表的涨跌色走，别的画线一律用用户自己挑的那个颜色
  // （见 `DrawTint`）。涨跌色也得照用户的红绿口径来，所以问的是这张图的 `t.up/t.down`。
  func paint(_ tint: DrawTint) -> Hex {
    switch tint { case .line: color; case .up: t.up; case .down: t.down }
  }
  ctx.setStrokeColor(Paint.cg(color)); ctx.setLineWidth(d.lineWidth)
  ctx.setLineDash(phase: 0, lengths: d.dash == .solid ? [] : (d.dash == .dashed ? [6, 4] : [1, 3]))
  // 填充不看选中态：从前「选中就不画底」，于是一拖动矩形／量尺／持仓框，
  // 整块颜色就没了，手一松又回来——闪一下的是这条线自己的身份。
  if d.filled, shape {
    for fill in g.fills {
      guard let first = fill.points.first else { continue }
      ctx.saveGState(); ctx.setAlpha(0.12); ctx.setFillColor(Paint.cg(paint(fill.tint)))
      ctx.beginPath(); ctx.move(to: CGPoint(x: first.x, y: first.y))
      for p in fill.points.dropFirst() { ctx.addLine(to: CGPoint(x: p.x, y: p.y)) }
      ctx.closePath(); ctx.fillPath(); ctx.restoreGState()
    }
  }
  if shape {
    for line in g.segments {
      ctx.setStrokeColor(Paint.cg(paint(line.tint)))
      ctx.beginPath(); ctx.move(to: CGPoint(x: line.a.x, y: line.a.y)); ctx.addLine(to: CGPoint(x: line.b.x, y: line.b.y)); ctx.strokePath()
    }
  }
  if shape { paintDrawingLabels(placedLabels, ctx: ctx, colors: t, ink: paint) }
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
