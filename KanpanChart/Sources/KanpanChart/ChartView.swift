import CoreGraphics
import Foundation
import KanpanCore
import QuartzCore
import UIKit

/// 图表视图：三层 `CALayer` + 一条 `CADisplayLink`（§5.7）。
///
/// ```
/// crossLayer   十字线 + 三处读数        手指移动
/// liveLayer    最新价线 + 右轴胶囊      每次 ticker
/// plotLayer    网格、蜡烛、指标、画线、副图、轴、图例   视野 / 数据 / 风格 / 尺寸变了
/// ```
///
/// 视图自己**一笔都不画**：三层的 `draw(in:)` 各自转手给 `ChartRenderer` 的
/// `drawPlot` / `drawLive` / `drawCross`。算法在 `KanpanCore`，画法在 `ChartRenderer`，
/// 这里只管「谁脏了、什么时候画」。
///
/// `state` 一变就跟旧值比一次，只有真受影响的层才置脏位；`CADisplayLink` 每帧把脏位
/// 刷成 `setNeedsDisplay`，没有脏位就把自己暂停（A3.12：静止时 CPU < 1%）。
///
/// 手势在 `ChartView+Gesture.swift`：触摸直接改 `state`，改完走同一条脏位通道，
/// 所以跟手、惯性、回弹和外部换数据是一条路，没有第二套绘制入口。
@MainActor
public final class ChartView: UIView {
  // ---------------------------------------------------------------- 层

  /// 三层的脏位。
  public struct Parts: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    /// 底图：网格、蜡烛、指标、画线、副图、轴、图例。
    public static let plot = Parts(rawValue: 1 << 0)
    /// 最新价线 + 右轴胶囊。
    public static let live = Parts(rawValue: 1 << 1)
    /// 十字线 + 读数。
    public static let cross = Parts(rawValue: 1 << 2)
    public static let all: Parts = [.plot, .live, .cross]
  }

  private let plotLayer = CanvasLayer(part: .plot)
  private let liveLayer = CanvasLayer(part: .live)
  private let crossLayer = CanvasLayer(part: .cross)
  private var canvases: [CanvasLayer] { [plotLayer, liveLayer, crossLayer] }

  // ---------------------------------------------------------------- 输入

  /// 画一帧要的全部东西。换一份就按需重画。
  ///
  /// `nil` 表示还没数据（冷启动、切品种的空档）：三层清空，什么都不画。
  public var state: ChartState? {
    didSet {
      if let old = oldValue, var next = state {
        if old.options.dataDisplay != next.options.dataDisplay || old.options.crossPrice != next.options.crossPrice
          || old.series.symbol != next.series.symbol || old.series.interval != next.series.interval
          || next.crosshair?.pane.map({ !next.subs.contains($0) }) == true {
          next.crosshair = nil
          state = next
        }
      }
      adopt(old: oldValue)
    }
  }

  /// 渲染器缓存着指标结果（`IndicatorEngine`），所以留着不重建——
  /// 换 `state` 走它的 setter，末根变了只重算末尾那几根。
  private(set) var renderer: ChartRenderer?

  /// 当前布局。手势层（M4）和取证脚本要按它换算坐标。
  public var chartLayout: Layout? {
    guard let renderer, bounds.width > 0, bounds.height > 0 else { return nil }
    return renderer.layout(size: bounds.size)
  }

  /// 当前主图价格区间。
  public var chartPriceRange: PriceRange? {
    guard let renderer, bounds.width > 0, bounds.height > 0 else { return nil }
    return renderer.priceRange(size: bounds.size)
  }

  public override var accessibilityValue: String? {
    get {
      guard let s = state, let layout = chartLayout else { return "行情加载中" }
      if ProcessInfo.processInfo.environment["KANPAN_CHART_DIAGNOSTICS"] == "1" {
        let metrics = candleMetrics(spacing: s.view.barSpacing(step: s.series.step, plotW: layout.plotW),
                                    style: s.style, scale: Double(renderScale))
        let info: [String: Any] = ["style": s.style.id, "background": s.colors.bg.value, "bars": s.series.count, "symbol": s.series.symbol,
          "latestRightGap": layout.plotW - s.view.x(Double(s.series.lastTime), plotW: layout.plotW)
            - s.view.barSpacing(step: s.series.step, plotW: layout.plotW) / 2,
          "lastClose": s.series.close.last ?? 0, "lastVolume": s.series.volume.last ?? 0,
          "from": s.view.from, "to": s.view.to, "span": s.view.span,
          "plotW": layout.plotW, "mainH": layout.mainH, "timeY": layout.timeY,
          "bodyW": metrics.bodyW, "spacing": s.view.barSpacing(step: s.series.step, plotW: layout.plotW),
          "mode": s.price.mode.rawValue, "inverted": s.price.inverted,
          "zoomY": s.price.zoom, "centerY": s.price.centerFraction,
          "axisW": layout.axisW, "height": layout.H,
          "dataDisplay": s.options.dataDisplay.rawValue, "portraitHeight": s.options.portraitHeight,
          "drawingCount": s.drawings.count,
          "drawingKinds": s.drawings.map { $0.kind.rawValue },
          "drawingIDs": s.drawings.map { $0.id },
          "drawingAnchors": s.drawings.map { $0.points.map { ["t": $0.t, "p": $0.p] } },
          "drawingColors": s.drawings.map { $0.color?.value ?? "default" },
          "drawingLocked": s.drawings.map { $0.locked },
          "drawingHidden": s.drawings.map { $0.hidden },
          "maColor0": renderer?.indicatorColor(.ma, 0).value ?? "",
          "emaColor0": renderer?.indicatorColor(.ema, 0).value ?? "",
          "drawingMagnet": drawing.magnet,
          "drawingContinuous": drawing.continuous,
          "hiddenMA": (s.hiddenOutputs[.ma] ?? []).sorted(),
          "scrollY": (superview as? UIScrollView)?.contentOffset.y ?? 0,
          "viewportH": (superview as? UIScrollView)?.bounds.height ?? bounds.height,
          "gestureTrace": gesture.trace,
          "crossPane": s.crosshair?.pane?.rawValue ?? "MAIN",
          "crosshair": s.crosshair != nil,
          "crossIndex": s.crosshair?.index ?? -1,
          "crossX": renderer?.crosshairCenter(size: bounds.size)?.x ?? -1,
          "crossY": renderer?.crosshairCenter(size: bounds.size)?.y ?? -1,
          "panes": layout.panes.dropFirst().map { ["id": $0.indicator?.rawValue ?? "", "y": $0.y, "h": $0.h] as [String: Any] }, "subs": s.subs.map(\.rawValue),
          // 画线横屏要的是一张没有任何指标参与定标的原始 K 线，用例得能看见主图叠加层。
          "overlays": s.overlays.map(\.rawValue),
          "ma": s.params[.ma] ?? [], "macd": s.params[.macd] ?? [],
          "oiReady": s.oi != nil, "interval": s.series.interval.rawValue,
          "oiPeriod": s.oi?.bucketInterval?.rawValue ?? "",
          "oiTimes": s.oi?.timestamps ?? []]
        guard let data = try? JSONSerialization.data(withJSONObject: info, options: .sortedKeys)
        else { return nil }
        return String(data: data, encoding: .utf8)
      }
      return "\(s.symbol.symbol)，\(s.series.interval.display)，\(s.series.count)根K线"
    }
    set { super.accessibilityValue = newValue }
  }

  // ---------------------------------------------------------------- 手势

  /// 一次手势从按下到抬手之间攒的东西。逻辑全在 `ChartView+Gesture.swift`，
  /// 这里只放这一个存储属性——扩展加不了存储属性。
  let gesture = GestureState()

  /// 视野被手势改了（拖、甩、捏、轴拖、回弹的每一帧都会叫）。
  public var onViewChanged: ((ViewWindow) -> Void)?
  /// 十字线出现 / 移动 / 消失。`nil` 表示消失。
  public var onCrosshairChanged: ((Crosshair?) -> Void)?
  /// 视野左缘推进到头部 200 根以内，该补历史了（§13 G9）。序列长出来之前只叫一次。
  public var onNeedsHistory: (() -> Void)?
  /// 图上轻点了一下（没有十字线、不是双击）。画线选中交给 M7 接。
  public var onTapped: (() -> Void)?
  /// 图自己做了件用户可能没预料到的事，需要外面报一行短提示（比如价格轴双击翻转）。
  /// 只给这种「不说一声就找不回来」的动作用，别拿它做常规反馈。
  public var onNotice: ((String) -> Void)?
  public var onStateChanged: ((ChartState?) -> Void)?

  // ---------------------------------------------------------------- 生命周期

  public override init(frame: CGRect) {
    super.init(frame: frame)
    setup()
  }

  public convenience init(state: ChartState?) {
    self.init(frame: .zero)
    self.state = state
    // 初始化里赋值不走 `didSet`，这一下得自己补，否则渲染器建不起来、三层全是空的。
    adopt(old: nil)
  }

  public required init?(coder: NSCoder) {
    super.init(coder: coder)
    setup()
  }

  private func setup() {
    isMultipleTouchEnabled = true
    isAccessibilityElement = true
    accessibilityIdentifier = "chart.canvas"
    accessibilityLabel = "行情图表"
    backgroundColor = .clear
    isOpaque = false
    contentMode = .redraw
    layer.masksToBounds = true
    for c in canvases {
      c.host = self
      c.isOpaque = false
      c.contentsScale = renderScale
      c.needsDisplayOnBoundsChange = false
      // 改 bounds / 换 contents 一律不要隐式动画：滚动时图会拖影。
      c.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
      layer.addSublayer(c)
    }
  }

  // ---------------------------------------------------------------- 尺寸与屏幕

  /// 设备像素密度。原型 `resize()` 里封顶 3，这里照抄。
  private var renderScale: CGFloat {
    let s = traitCollection.displayScale
    return s > 0 ? min(3, s) : 2
  }

  private var lastSize: CGSize = .zero
  private var lastScale: CGFloat = 0

  public override func layoutSubviews() {
    super.layoutSubviews()
    let size = bounds.size
    let scale = renderScale
    guard size != lastSize || scale != lastScale else { return }
    lastSize = size
    lastScale = scale
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for c in canvases {
      c.frame = bounds
      c.contentsScale = scale
    }
    CATransaction.commit()
    setNeedsRedraw(.all)
  }

  public override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      animation = nil
      gesture.touches.removeAll(); gesture.reset()
      state?.axisScaleAnchor = nil
      // 不在窗口上就没有帧可跑；脏位留着，回来再刷。
      link?.invalidate()
      link = nil
    } else {
      if renderScale != lastScale { setNeedsLayout() }
      if !dirty.isEmpty { resumeLink() }
    }
  }

  // ---------------------------------------------------------------- 脏位

  private var dirty: Parts = []

  /// 手动置脏。数据没变但想重画（换屏、取证截图）时用。
  public func setNeedsRedraw(_ parts: Parts = .all) {
    guard !parts.isEmpty else { return }
    dirty.formUnion(parts)
    // 挂在窗口上就交给 DisplayLink 按帧刷；离屏（快照测试、后台渲染）
    // 没有帧，直接置 `setNeedsDisplay`，不然永远画不出来。
    if window != nil { resumeLink() } else { flush() }
  }

  /// 立刻把脏层画完，不等下一帧。快照取证（A3.1 / A3.11）用。
  public func redrawNow() {
    flush()
    for c in canvases { c.displayIfNeeded() }
  }

  private func flush() {
    guard !dirty.isEmpty else { return }
    if dirty.contains(.plot) { plotLayer.setNeedsDisplay() }
    if dirty.contains(.live) { liveLayer.setNeedsDisplay() }
    if dirty.contains(.cross) { crossLayer.setNeedsDisplay() }
    dirty = []
  }

  /// 换 `state`：先喂给渲染器，再跟旧值比出该重画哪几层。
  private func adopt(old: ChartState?) {
    guard let s = state else {
      animation = nil
      gesture.touches.removeAll(); gesture.reset()
      onCrosshairChanged?(nil)
      onStateChanged?(nil)
      renderer = nil
      setNeedsRedraw(.all)
      return
    }
    if renderer == nil { renderer = ChartRenderer(state: s) } else { renderer?.state = s }
    setNeedsRedraw(Self.changed(from: old, to: s))
    onStateChanged?(s)
    if old?.crosshair != s.crosshair { onCrosshairChanged?(s.crosshair) }
  }

  /// 新旧两帧的差异落在哪几层。
  ///
  /// 末根之外的东西一动（视野、风格、指标、主题、整段数据），几何就变了，三层全重画；
  /// 只有末根动（ticker 推进来一笔），蜡烛和最新价要跟着变，十字线不用；
  /// 只有十字线动，就只画十字线那层。
  static func changed(from old: ChartState?, to new: ChartState) -> Parts {
    guard let o = old else { return .all }
    if !sameFrame(o, new) { return .all }
    var p: Parts = []
    // 末根变了：蜡烛（plot）、最新价（live）都要重画；没有十字线时图例读的就是末根，
    // 图例在 `crossLayer` 上，所以 cross 也得跟着脏。
    if !sameLastBar(o.series, new.series) {
      p.insert([.plot, .live])
      if o.crosshair == nil || new.crosshair == nil { p.insert(.cross) }
    }
    if o.crosshair != new.crosshair { p.insert(.cross) }
    // 倒计时每秒走一格，但它只画在 `liveLayer` 上——只脏 live，别把整张图拖下水
    // （A3.12 要求静止时 CPU < 1%，重画 plot 层就破功了）。倒计时没开就当没变过。
    if o.nowMs != new.nowMs, new.options.countdown, new.options.lastLine { p.insert(.live) }
    return p
  }

  /// 末根之外的一切是否一样。
  private static func sameFrame(_ a: ChartState, _ b: ChartState) -> Bool {
    a.symbol == b.symbol && a.view == b.view && a.style == b.style && a.dark == b.dark && a.paletteSeed == b.paletteSeed
      && a.redUp == b.redUp && a.price == b.price && a.overlays == b.overlays
      && a.subs == b.subs && a.params == b.params && a.timezone == b.timezone
      && a.drawingPreviewID == b.drawingPreviewID && a.drawings == b.drawings && a.decimals == b.decimals && a.oi == b.oi && a.oiSupported == b.oiSupported
      && a.magnet == b.magnet && a.options == b.options && a.subScale == b.subScale
      && a.indicatorColors == b.indicatorColors && a.hiddenOutputs == b.hiddenOutputs && a.subInverted == b.subInverted
      && a.rsiUpper == b.rsiUpper && a.rsiLower == b.rsiLower && a.axisScaleAnchor == b.axisScaleAnchor
      && sameSeriesExceptLast(a.series, b.series)
  }

  /// 搬到了 `BarSeries.samePrefix(as:)`：判定条件和从前逐字相同，只是在逐列比之前
  /// 先看一眼前缀戳。留着这层壳是因为它是 `sameFrame` 的一部分，名字在这儿读着顺。
  private static func sameSeriesExceptLast(_ a: BarSeries, _ b: BarSeries) -> Bool {
    a.samePrefix(as: b)
  }

  private static func sameLastBar(_ a: BarSeries, _ b: BarSeries) -> Bool {
    guard let i = a.close.indices.last, let j = b.close.indices.last else {
      return a.isEmpty && b.isEmpty
    }
    return a.open[i] == b.open[j] && a.high[i] == b.high[j] && a.low[i] == b.low[j]
      && a.close[i] == b.close[j] && a.volume[i] == b.volume[j]
  }

  // ---------------------------------------------------------------- DisplayLink

  private var link: CADisplayLink?
  /// 上一次给 `link` 设的是不是高刷区间。只在真的换档时才写 `preferredFrameRateRange`。
  private var linkWantsHighRate: Bool?

  /// 跟手的那几种脏位来源：拖图、捏合、拖价格轴、拖副图轴、纵向平移、十字线跟手，
  /// 外加惯性 / 回弹（`FlingRun` 走的是 `animation`）。
  ///
  /// tick、倒计时、外部换 state 这类「一帧刷一次」的不算——给它们 120 Hz 只是白烧电。
  private var wantsHighFrameRate: Bool {
    if animation != nil { return true }
    guard !gesture.touches.isEmpty, let mode = gesture.mode else { return false }
    switch mode {
    case .pan, .pinch, .axisPrice, .subAxis, .verticalPan, .crosshair: return true
    case .parentScroll, .autoFit: return false
    }
  }

  /// `CADisplayLink` 每帧只干一件事：把脏位刷成 `setNeedsDisplay`；没脏位就把自己停掉。
  /// 静止时不跑帧，这是 A3.12 的全部内容。
  ///
  /// 帧率区间按脏位来源分两档：手势 / 动画要 120 Hz（`Info.plist` 里的
  /// `CADisableMinimumFrameDurationOnPhone` 把 iPhone 的 60 Hz 钳制解开了），
  /// 其余单帧刷新压回 60 Hz。
  private func resumeLink() {
    if link == nil {
      let l = CADisplayLink(target: LinkProxy(self), selector: #selector(LinkProxy.tick))
      l.add(to: .main, forMode: .common)
      link = l
      linkWantsHighRate = nil
    }
    applyFrameRateRange()
    link?.isPaused = false
  }

  private func applyFrameRateRange() {
    guard let link else { return }
    let high = wantsHighFrameRate
    guard linkWantsHighRate != high else { return }
    linkWantsHighRate = high
    link.preferredFrameRateRange = high
      ? CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
      : CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
  }

  /// 每帧跑一次的动画：惯性、回弹、十字线淡出这类自己会走完的东西。
  ///
  /// 返回 `true` 表示演完了，视图会把它摘掉。只要挂着动画 `CADisplayLink` 就不停——
  /// 但动画自己走完那一帧之后立刻回到「没脏位就暂停」的老规矩（A3.12）。
  var animation: ((CFTimeInterval) -> Bool)? {
    didSet { if animation != nil { resumeLink() } }
  }

  fileprivate func onFrame() {
    if let step = animation {
      // 用 `link.targetTimestamp` 而不是 `CACurrentMediaTime()`：动画该按这一帧
      // **将要显示**的时刻算位置，否则 120Hz 下每帧都慢半拍，甩起来有拖影。
      let now = link?.targetTimestamp ?? CACurrentMediaTime()
      // 动画演完就把帧率区间落回 60：`animation` 的 didSet 只在挂上时抬档。
      if step(now) { animation = nil; applyFrameRateRange() }
    }
    if dirty.isEmpty {
      if animation == nil { link?.isPaused = true }
      return
    }
    flush()
  }

  // ---------------------------------------------------------------- 画

  /// 层回调进来的唯一入口。视图不画，只负责分派。
  fileprivate func render(_ part: CanvasLayer.Part, in ctx: CGContext, size: CGSize, scale: CGFloat)
  {
    guard let renderer, size.width > 0, size.height > 0 else {
      ctx.clear(CGRect(origin: .zero, size: size))
      return
    }
    switch part {
    case .plot: renderer.drawPlot(in: ctx, size: size, scale: scale)
    case .live: renderer.drawLive(in: ctx, size: size, scale: scale)
    case .cross: renderer.drawCross(in: ctx, size: size, scale: scale)
    }
  }
}

// ---------------------------------------------------------------- 一层画布

/// 三层里的一层。自己不认识图表，只知道自己是哪一层，画的时候回头问宿主。
///
/// 不拿 `ChartView` 当别的层的 `delegate`：UIView 只该是自己那层的 delegate，
/// 当别人的会在 `layoutSublayers` 上打架。
final class CanvasLayer: CALayer {
  enum Part: Sendable { case plot, live, cross }

  private(set) var part: Part = .plot
  weak var host: ChartView?

  init(part: Part) {
    self.part = part
    super.init()
  }

  /// CoreAnimation 复制层（presentation layer）时走这条，自定义字段要跟着带过去。
  override init(layer: Any) {
    super.init(layer: layer)
    if let l = layer as? CanvasLayer {
      part = l.part
      host = l.host
    }
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  override func draw(in ctx: CGContext) {
    // 层的 display 一律在主线程的 CA 提交里跑（没开 `drawsAsynchronously`），
    // 所以这里可以 `assumeIsolated`。`CALayer` 本身没有隔离标注，`CGContext` 也不
    // `Sendable`，跨进闭包得显式免检——运行时的线程保证由 CoreAnimation 给。
    let part = self.part
    let size = bounds.size
    let scale = contentsScale
    let host = self.host
    nonisolated(unsafe) let ctx = ctx
    MainActor.assumeIsolated {
      host?.render(part, in: ctx, size: size, scale: scale)
    }
  }
}

// ---------------------------------------------------------------- DisplayLink 的壳

/// `CADisplayLink` 会**强引用** target，直接指向视图就成环了。这层壳弱引用视图，
/// 视图被释放后帧回调空转一次就没了。
@MainActor
private final class LinkProxy: NSObject {
  private weak var view: ChartView?
  init(_ view: ChartView) {
    self.view = view
    super.init()
  }

  @objc func tick() { view?.onFrame() }
}
