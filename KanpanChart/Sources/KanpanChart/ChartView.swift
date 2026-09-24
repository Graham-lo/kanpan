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
  #if DEBUG
  private var renderedDepthRows = 0
  #endif
  private let crossLayer = CanvasLayer(part: .cross)
  private var canvases: [CanvasLayer] { [plotLayer, liveLayer, crossLayer] }

  /// 客线是临时覆盖，不属于 ChartState / 存档，也不参与画线命中。
  public var guestDrawings: [Drawing] = [] {
    didSet { renderer?.guestDrawings = guestDrawings; setNeedsRedraw(.plot); refreshDrawingOverlay() }
  }
  public var ownDimmed = false {
    didSet { renderer?.ownDimmed = ownDimmed; setNeedsRedraw(.plot); refreshDrawingOverlay() }
  }

  // ---------------------------------------------------------------- 输入

  /// 画一帧要的全部东西。换一份就按需重画。
  ///
  /// `nil` 表示还没数据（冷启动、切品种的空档）：三层清空，什么都不画。
  ///
  /// 写进来的那份先按规矩摆正（`normalized`）再存——从前是在 `didSet` 里发现不对就
  /// 回头再赋一遍 `state`，靠的是「属性观察器里给自己赋值不会再触发观察器」这条
  /// 语言细节才没递归，读起来像递归，改的人一不小心就真递归了（审查 23.5）。
  public var state: ChartState? {
    get { storedState }
    set {
      let old = storedState
      var next = newValue
      if var incoming = next {
        if let old { incoming = normalized(incoming, after: old) }
        // 线不归调用方给：一律从画线真值（`DrawingBook`）按品种投影进来（审查 23.2）。
        next = projectDrawings(into: incoming)
      }
      let keyBefore = drawingKey
      storedState = next
      if next != nil { drawingKey = drawingKeyCache.key }
      adopt(old: old)
      // 换了品种：半截的画线交互（工具、选中、待落点）属于上一张图，放在 `adopt` 之后收，
      // 收的时候外面回调读到的已经是新品种的那份 state。
      if next != nil, keyBefore != drawingKey { drawingKeyDidChange(from: keyBefore) }
    }
  }
  private var storedState: ChartState?

  // ---------------------------------------------------------------- 画线真值

  /// 这张图的画线会话（选中、待落点、拖动快照……交互中间量）。第一次用到时才建
  /// （见 `ChartView.drawing`）。从前挂在 objc 关联对象上，因为扩展里加不了存储属性；
  /// 现在就是一个普通的存储属性（审查 23.2）。
  var drawingSessionStorage: DrawingSession?
  /// 画线真值。宿主用 `bindDrawings(to:)` 绑上它自己那一本；没绑的图（单测、复盘回放）
  /// 用一本自己私有的，第一次用到时才建。
  var drawingBookStorage: DrawingBook?
  /// 绑的是宿主给的那一本（`true`），还是图私有的那一本（`false`）。
  var drawingsBound = false
  /// 这张图此刻投影的是哪一桶（规范写法的品种键）。`state` 为 `nil` 的空档里保留上一只，
  /// 不然冷启动或换品种的空档一过，同一只品种回来也会被当成「换品种」把工具收掉。
  var drawingKey: String?
  /// 上一次算规范键用的原始代号。每一帧都要投影，`InstrumentID.canonical` 只在代号变了时算一次。
  var drawingKeyCache: (raw: String, key: String) = ("", "")

  /// 新来的一份 state 相对上一份要先摆正的几件事。纯粹改值，不碰任何副作用以外的状态
  /// （手势候选、补历史的门、冻结这三样「换了张图就作废」的账在这里一并销掉）。
  private func normalized(_ incoming: ChartState, after old: ChartState) -> ChartState {
    var next = incoming
    if old.options.dataDisplay != next.options.dataDisplay || old.options.crossPrice != next.options.crossPrice
      || old.series.symbol != next.series.symbol || old.series.interval != next.series.interval
      || next.crosshair?.pane.map({ !next.subs.contains($0) }) == true {
      next.crosshair = nil
    }
    // 换品种 / 换周期 = 换了一张图，上一张图上那次轴轻点跟现在没关系了（A-09）。
    // 补历史的门同理：那次「已经喊过了」记的是上一张图的账（A.5 用例 13）。
    // 冻结也一样：手指底下那张图已经不在了，钉着上一张图的视野只会更乱。
    if old.series.symbol != next.series.symbol || old.series.interval != next.series.interval
      || old.percentAxis != next.percentAxis {
      gesture.endAxisTapCandidate()
      gesture.askedHistory = false
      cancelAxisFreeze()
    }
    // 手指按着一个目标的这段时间里视野钉死（见 `beginAxisFreeze`）：外面灌进来的
    // 那份视野一律让位——新 K 线到货时 `AICoinBehavior.reconcile` 会把视野右移一格，
    // 而用户手指没动，线不能跟着跑。
    if let frozen = frozenAxes, next.view != frozen.view {
      next.view = frozen.view
    }
    return next
  }

  // ---------------------------------------------------------------- 拖动期间的坐标

  /// 拖动期间钉住的那套坐标。整场只在 `beginAxisFreeze` / `endAxisFreeze` 里换，
  /// 别处只读（写它就等于绕过抬手那一刻的追平）。
  struct FrozenAxes {
    /// 冻结那一刻的时间轴视野。
    var view: ViewWindow
    /// 冻结那一刻的主图价格区间。
    var range: PriceRange
    /// 冻结那一刻视野还贴着末根吗——抬手要不要追平看它。
    var followingLatest: Bool
  }

  var frozenAxes: FrozenAxes?

  /// 此刻手指正按着某个目标、坐标是钉住的吗。宿主据此跳过 `reconcile`（见 `ChartHost`）。
  public var axesFrozen: Bool { frozenAxes != nil }

  /// 渲染器缓存着指标结果（`IndicatorEngine`），所以留着不重建——
  /// 换 `state` 走它的 setter，末根变了只重算末尾那几根。
  private(set) var renderer: ChartRenderer?

  /// 当前布局。手势层（M4）和取证脚本要按它换算坐标。
  public var chartLayout: Layout? {
    guard let renderer, bounds.width > 0, bounds.height > 0 else { return nil }
    return renderer.layout(size: bounds.size)
  }

  /// 钉住 / 松开主图价格区间（见 `beginAxisFreeze`）。
  ///
  /// `renderer` 是 `private(set)`，而它是个 struct——写它的字段就等于写 `renderer` 本身，
  /// 所以这个口子只能开在本文件里。外面一律走 `beginAxisFreeze` / `cancelAxisFreeze`。
  func pinPriceRange(_ range: PriceRange?) {
    guard renderer != nil else { return }
    renderer?.pinnedPriceRange = range
  }

  /// 当前主图价格区间。
  public var chartPriceRange: PriceRange? {
    guard let renderer, bounds.width > 0, bounds.height > 0 else { return nil }
    return renderer.priceRange(size: bounds.size)
  }

  public override var accessibilityValue: String? {
    get {
      guard let s = state, let layout = chartLayout else { return "行情加载中" }
      // 这一整块诊断 JSON **只在 DEBUG 构建里存在**（审查 C-02）：正式包的读屏不该
      // 因为一个启动环境变量就把整张图的内部状态念出来。写成 `#if DEBUG` 包住整块，
      // 让「所有读启动环境的地方都在 DEBUG 里」这句话能被机械扫描直接证明。
      #if DEBUG
      if ProcessInfo.processInfo.environment["KANPAN_CHART_DIAGNOSTICS"] == "1" {
        let metrics = candleMetrics(spacing: s.view.barSpacing(step: s.series.step, plotW: layout.plotW),
                                    scale: Double(renderScale))
        let compareIndex = min(max(s.crosshair?.index ?? (s.series.count - 1), 0), max(s.series.count - 1, 0))
        let compareRange = renderer?.priceRange(size: bounds.size)
        let crossPoint = renderer?.crosshairCenter(size: bounds.size)
        let crossLabel: String
        if let compareRange, let crossPoint, let renderer {
          crossLabel = renderer.axisLabel(pOf(crossPoint.y, pane: layout.main, range: compareRange, mode: s.effectivePriceMode), range: compareRange)
        } else { crossLabel = "" }
        let orderFlow = renderer?.orderFlowDiagnostics(size: bounds.size)
        let info: [String: Any] = [
          "compareMainClose": s.series.close.indices.contains(compareIndex) ? s.series.close[compareIndex] : 0,
          "crossAxisLabel": crossLabel,
          "compareTicks": compareRange.map { renderer?.mainPriceTicks(range: $0, paneHeight: layout.main.h) ?? [] } ?? [],
          "background": s.colors.bg.value, "bars": s.series.count, "symbol": s.series.symbol,
          "latestRightGap": layout.plotW - s.view.x(Double(s.series.lastTime), plotW: layout.plotW)
            - s.view.barSpacing(step: s.series.step, plotW: layout.plotW) / 2,
          "priceDecimals": s.decimals,
          "lastClose": s.series.close.last ?? 0, "lastVolume": s.series.volume.last ?? 0,
          "from": s.view.from, "to": s.view.to, "span": s.view.span,
          "plotW": layout.plotW, "mainH": layout.mainH, "timeY": layout.timeY,
          "bodyW": metrics.bodyW, "spacing": s.view.barSpacing(step: s.series.step, plotW: layout.plotW),
          "percentAxis": s.percentAxis,
          "compareKeys": s.compare.map(\.key),
          "compareColors": s.compare.map { $0.color.value },
          "compareReady": s.compare.filter { $0.percent(at: s.series.count - 1, baseIndex: s.compareBaseIndex()) != nil }.count,
          "compareBaseIndex": s.compareBaseIndex(), "compareBaseOpen": s.compareBase(),
          "compareBaseTime": s.series.time(at: s.compareBaseIndex()),
          "compareLegend": renderer?.compareLegend.map { ["name": $0.name, "label": ChartState.comparePercentLabel($0.value)] } ?? [],
          "drawingsVisible": s.options.drawings,
          "mode": s.effectivePriceMode.rawValue, "inverted": s.price.inverted,
          "zoomY": s.price.zoom, "centerY": s.price.centerFraction,
          "axisW": layout.axisW, "height": layout.H,
          "dataDisplay": s.options.dataDisplay.rawValue, "portraitHeight": s.options.portraitHeight,
          "candleKind": s.options.kind.rawValue,
          "drawingCount": s.drawings.count,
          "guestIDs": guestDrawings.map(\.id),
          "ownDimmed": ownDimmed,
          "drawingKinds": s.drawings.map { $0.kind.rawValue },
          "drawingIDs": s.drawings.map { $0.id },
          "drawingAnchors": s.drawings.map { $0.points.map { ["t": $0.t, "p": $0.p] } },
          "drawingColors": s.drawings.map { $0.color?.value ?? "default" },
          "drawingLocked": s.drawings.map { $0.locked },
          "drawingHidden": s.drawings.map { $0.hidden },
          // 哪几条线右端挂着铃铛（提醒）。图自己只认 id，用例也只问这一件事。
          "drawingAlerted": s.drawings.filter { drawing.alerted.contains($0.id) }.map { $0.id },
          "maColor0": renderer?.indicatorColor(.ma, 0).value ?? "",
          "emaColor0": renderer?.indicatorColor(.ema, 0).value ?? "",
          "drawingCommits": drawing.commits,
          "drawingCommitWired": drawing.onCommitted != nil,
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
          // 主力订单流：快照阶段、大单条数、此刻画出来的色带（视图坐标）与十字线点亮与否。
          "orderFlowPhase": s.orderFlow.map { $0.phase == .ready ? "ready" : "loading" } ?? "",
          "orderFlowOrders": s.orderFlow?.orders.count ?? 0,
          // 此刻生效的门槛（按产品，美元）与步长：用例改完门槛靠它确认新数真的到了簿那一层。
          "orderFlowThresholds": s.orderFlow.map { f in
            var out: [String: Double] = [:]
            for product in OrderFlowProduct.allCases { if let v = f.thresholds[product] { out[product.rawValue] = v } }
            if let step = f.thresholds.step { out["step"] = step }
            return out
          } ?? [:],
          "orderFlowBands": (orderFlow?.bands ?? []).map {
            ["side": $0.order.side == .bid ? "bid" : "ask", "x": $0.frame.minX, "y": $0.frame.midY,
             "w": $0.frame.width, "h": $0.frame.height, "alpha": $0.alpha, "color": $0.color.value,
             "product": $0.order.product.rawValue, "status": $0.order.status.rawValue,
             "dashed": $0.dashed] as [String: Any]
          },
          "orderFlowHovered": orderFlow?.hovered ?? false,
          "orderFlowAdoptions": orderFlowAdoptions,
          "renderCounts": renderCounts,
          "panes": layout.panes.dropFirst().map { ["id": $0.indicator?.rawValue ?? "", "y": $0.y, "h": $0.h] as [String: Any] }, "subs": s.subs.map(\.rawValue),
          // 画线横屏要的是一张没有任何指标参与定标的原始 K 线，用例得能看见主图叠加层。
          "overlays": s.overlays.map(\.rawValue),
          "ma": s.params[.ma] ?? [], "macd": s.params[.macd] ?? [],
          "externalReady": s.external.keys.map(\.rawValue).sorted(),
          "externalSupported": s.externalSupported, "oiSupported": s.oiSupported, "depthSymbol": s.depth?.symbol ?? "", "depthLevels": (s.depth?.bids.count ?? 0) + (s.depth?.asks.count ?? 0),
          "renderedDepthRows": renderedDepthRows,
          "oiReady": s.oi != nil, "interval": s.series.interval.rawValue,
          "oiPeriod": s.oi?.bucketInterval?.rawValue ?? "",
          "oiTimes": s.oi?.timestamps ?? [],
          // 正式包读屏念的那一句（P2.12），用例断言它非空、跟着十字线变。
          "voiceValue": voiceOverValue ?? ""]
        guard let data = try? JSONSerialization.data(withJSONObject: info, options: .sortedKeys)
        else { return nil }
        return String(data: data, encoding: .utf8)
      }
      #endif
      return voiceOverValue ?? "\(InstrumentID(s.symbol.symbol).symbol)，\(s.series.interval.display)，暂无K线"
    }
    set { super.accessibilityValue = newValue }
  }

  // ---------------------------------------------------------------- 手势

  /// 一次手势从按下到抬手之间攒的东西。逻辑全在 `ChartView+Gesture.swift`，
  /// 这里只放这一个存储属性——扩展加不了存储属性。
  let gesture = GestureState()

  /// 视野变了。**谁造成的都叫**：手势、回弹、「回到最新」、外面灌进来的重排都算。
  /// 补历史、周期条行尾那颗「最新」这类「跟着视野走」的事读它。
  public var onViewChanged: ((ViewWindow) -> Void)?
  /// 视野被**用户手上的动作**改了（拖、甩、捏、轴拖、回弹的每一帧）。
  ///
  /// 和上面那个的分工是这次 bug 的要害：「用户想要多宽」**只能**从这儿读。
  /// 程序自己造成的视野变化（换品种的 `.reset`、换周期的 `.switchInterval`、
  /// 转屏/换页的 `.resize`、档案到货的 `.adopt`、「回到最新」）一律不走这个口子——
  /// 走了的话，图会把自己开张时那份出厂宽度当成用户意图报回去，把档案里真正的那份
  /// 覆盖写掉（见 `ChartViewport` 的「杀法甲」）。
  public var onUserViewChanged: ((ViewWindow) -> Void)?
  /// 十字线出现 / 移动 / 消失。`nil` 表示消失。
  public var onCrosshairChanged: ((Crosshair?) -> Void)?
  /// 视野左缘推进到头部 200 根以内，该补历史了（§13 G9）。序列长出来之前只叫一次。
  public var onNeedsHistory: (() -> Void)?
  /// 图上轻点了一下（没有十字线、不是双击）。画线选中交给 M7 接。
  public var onTapped: (() -> Void)?
  /// 图自己做了件用户可能没预料到的事，需要外面报一行短提示（比如价格轴双击翻转）。
  /// 只给这种「不说一声就找不回来」的动作用，别拿它做常规反馈。
  public var onNotice: ((String) -> Void)?
  /// state 换了。第二个参数是这次变的是哪几层（`nil` state 报 `.all`）；
  /// 宿主据此只更新变了的那部分——拖图只报 `.viewport`，十字线跟手只报 `.overlay`。
  /// 一层都没变（同一份 state 又灌了一遍）不报。
  public var onStateChanged: ((ChartState?, ChartState.Layers) -> Void)?
  /// **这次交互结束了：手指全部离开了画布。**
  ///
  /// 每次抬手都响一次（拖、甩、点、捏都算），而且 `.ended` 和 `.cancelled` 都响——
  /// 系统把手势掐掉（来电、上滑回桌面）时手指同样已经离开了屏幕，那一下更该存。
  /// 捏合中途抬掉一根手指、还剩指头按着时**不**响。
  ///
  /// 存在的理由只有一个：用户的原话是「用户手离开的瞬间就应该做同步做持久保存啊」。
  /// 落盘与同步的时机钉在这儿，不是钉在定时器上，也不是钉在切后台上。
  public var onInteractionEnded: (() -> Void)?
  /// **这次交互开始了：第一根手指落到画布上。** 和 `onInteractionEnded` 成对：
  /// 捏合时第二根手指落下不再响。宿主在 DEBUG 包里拿它给帧探针打点（P2.2）。
  public var onInteractionBegan: (() -> Void)?

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
    // 上下轻扫挪十字线，念出那一根的开高低收（P2.12）。
    accessibilityTraits = .adjustable
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
      gesture.touches.removeAll(); gesture.reset(); gesture.endAxisTapCandidate()
      // 手指是跟着视图一起离开的，钉住的坐标也就没人来解（抬手那一刻已经不会再来了）。
      cancelAxisFreeze()
      state?.axisScaleAnchor = nil
      // 不在窗口上就没有帧可跑；脏位留着，回来再刷。
      link?.invalidate()
      link = nil
      // 画线那条 link 也得在这儿收。它原来只在「下一帧发现触点、动画都空了」时
      // 自灭——而离屏之后根本没有下一帧，于是它连同 `CADisplayLink` 注册在主
      // runloop 上的那份强引用一起活到进程结束（转屏、来电、切页都能撞上）。
      // 触点和 claimed 一起收掉：手指是随着视图一起离开的，留着那半截状态，
      // 回来第一下会被当成上一次拖动的续拍。
      teardownDrawingLink()
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
      gesture.touches.removeAll(); gesture.reset(); gesture.endAxisTapCandidate()
      cancelAxisFreeze()
      fireCrosshairChanged(nil)
      onStateChanged?(nil, .all)
      renderer = nil
      setNeedsRedraw(.all)
      return
    }
    let layers = s.changedLayers(from: old)
    // 视野变了才需要知道「布局动没动」（轴宽跟着这一屏的刻度走）；旧布局此刻多半
    // 就在缓存里，取一下不花钱。
    let layoutBefore = layers.contains(.viewport) ? chartLayout : nil
    if renderer == nil { renderer = ChartRenderer(state: s) } else { renderer?.state = s }
    renderer?.guestDrawings = guestDrawings; renderer?.ownDimmed = ownDimmed
    var parts = Self.changed(from: old, to: s)
    if let layoutBefore, !parts.contains(.cross), chartLayout != layoutBefore { parts.insert(.cross) }
    setNeedsRedraw(parts)
    #if DEBUG
    onAdoptedForProbe?(!parts.isEmpty)
    if old?.orderFlow != s.orderFlow { orderFlowAdoptions += 1 }
    #endif
    flashIfTicked(from: old, to: s)
    if !layers.isEmpty { onStateChanged?(s, layers) }
    if old?.crosshair != s.crosshair { fireCrosshairChanged(s.crosshair) }
  }

  // ---------------------------------------------------------------- 最新价闪一下

  private var flashEnd: Task<Void, Never>?
  /// 闪多久（P2.8）。
  static let priceFlashDuration: Duration = .milliseconds(150)

  /// 同一只、同一周期的末根收盘价动了一口（改末根或者刚开新根），右轴那颗最新价胶囊
  /// 按这一口的方向闪 150ms。换品种、换周期、整段历史换掉都不算「一口」，不闪；
  /// 系统「减少动效」打开时一律不闪。只脏 live 层，蜡烛那层不跟着重画。
  private func flashIfTicked(from old: ChartState?, to new: ChartState) {
    guard let o = old, let before = o.series.close.last, let now = new.series.close.last, before != now,
      o.series.symbol == new.series.symbol, o.series.interval == new.series.interval,
      new.series.count == o.series.count ? new.series.samePrefix(as: o.series) : new.series.count == o.series.count + 1,
      new.options.lastLine, !UIAccessibility.isReduceMotionEnabled
    else { return }
    renderer?.priceFlash = now > before ? .up : .down
    setNeedsRedraw(.live)
    flashEnd?.cancel()
    flashEnd = Task { @MainActor [weak self] in
      try? await Task.sleep(for: Self.priceFlashDuration)
      guard !Task.isCancelled, let self else { return }
      self.renderer?.priceFlash = nil
      self.setNeedsRedraw(.live)
    }
  }

  /// 十字线回调的唯一出口：计数挂在这儿，别绕过去直接叫 `onCrosshairChanged`。
  func fireCrosshairChanged(_ crosshair: Crosshair?) {
    ChartWorkCounter.bump(.crosshairCallback)
    onCrosshairChanged?(crosshair)
  }

  /// 新旧两帧的差异落在哪几层。按 `ChartState` 的三层来问（审查 23.1）：
  ///
  /// - **输入层**除末根外动了（风格、指标、主题、整段数据）：几何全变，三层全重画；
  ///   只有末根动（ticker 推进来一笔），蜡烛和最新价要跟着变，十字线不用。
  /// - **视野层**动了（拖、捏、甩、拉价格轴、拖分隔线）：底图与最新价重画；十字线层
  ///   只在它的内容真读视野时才跟着画——十字线开着、比价（图例读视野左缘的基准）、
  ///   订单流开着（图例按这一屏的区间合计），以及布局变了（由 `adopt` 比布局补上）。
  /// - **叠加层**：画线只脏底图，十字线只脏十字线层，盘口 / 倒计时只脏最新价层。
  static func changed(from old: ChartState?, to new: ChartState) -> Parts {
    guard let o = old else { return .all }
    guard o.input.sameExceptLastBar(as: new.input),
          (o.orderFlow == nil) == (new.orderFlow == nil)  // 开着主力就多一行图例，影响 mainLegendInset
    else { return .all }
    var p: Parts = []
    if o.viewport != new.viewport {
      p.insert([.plot, .live])
      if o.crosshair != nil || new.crosshair != nil || new.percentAxis || new.orderFlow != nil { p.insert(.cross) }
    }
    if o.drawings != new.drawings || o.drawingPreviewID != new.drawingPreviewID { p.insert(.plot) }
    // 末根变了：蜡烛（plot）、最新价（live）都要重画；没有十字线时图例读的就是末根，
    // 图例在 `crossLayer` 上，所以 cross 也得跟着脏。
    if !sameLastBar(o.series, new.series) {
      p.insert([.plot, .live])
      if o.crosshair == nil || new.crosshair == nil { p.insert(.cross) }
    }
    if o.depth != new.depth { p.insert(.live) }
    // 主力订单流：色块在 plot、图例在 cross；十字线进出色带要把那条提亮到 0.9，也得重画 plot。
    // 画出来一样（只是金额在同一格、同一档里抖）只脏 cross：图例合计与读数在那一层，底图不动（审查第 31 项）。
    if o.orderFlowDisplay != new.orderFlowDisplay || !samePixels(o.orderFlow, new.orderFlow) { p.insert([.plot, .cross]) }
    else if o.orderFlow != new.orderFlow { p.insert(.cross) }
    else if o.crosshair != new.crosshair, new.orderFlow?.orders.isEmpty == false,
            o.crosshair.map({ $0.pane == nil }) == true || new.crosshair.map({ $0.pane == nil }) == true { p.insert(.plot) }
    if o.crosshair != new.crosshair { p.insert(.cross) }
    // 倒计时每秒走一格，但它只画在 `liveLayer` 上——只脏 live，别把整张图拖下水
    // （A3.12 要求静止时 CPU < 1%，重画 plot 层就破功了）。倒计时没开就当没变过。
    if o.nowMs != new.nowMs, new.options.countdown, new.options.lastLine { p.insert(.live) }
    return p
  }

  /// 两份主力快照画在底图上是不是一样（`OrderFlowSnapshot.sameContent`：量化到像素）。
  private static func samePixels(_ a: OrderFlowSnapshot?, _ b: OrderFlowSnapshot?) -> Bool {
    switch (a, b) {
    case (nil, nil): true
    case let (a?, b?): a.sameContent(as: b)
    default: false
    }
  }

  private static func sameLastBar(_ a: BarSeries, _ b: BarSeries) -> Bool {
    guard let i = a.close.indices.last, let j = b.close.indices.last else {
      return a.isEmpty && b.isEmpty
    }
    return a.open[i] == b.open[j] && a.high[i] == b.high[j] && a.low[i] == b.low[j]
      && a.close[i] == b.close[j] && a.volume[i] == b.volume[j]
  }

  // ---------------------------------------------------------------- DisplayLink

  /// 主图那条帧循环。读权限放到模块内是给生命周期用例看的（出窗之后它必须是 nil）。
  private(set) var link: CADisplayLink?
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
    // 不在窗口上就不许建帧循环。以前 `animation` 的 didSet 是无条件 resume 的，
    // 于是一次「离屏时挂上的惯性」会在没人看的地方建起一条 `CADisplayLink`，
    // 而出窗清理已经跑过了，没人再来收它。
    guard window != nil else { return }
    if link == nil {
      let l = CADisplayLink(target: LinkProxy(self), selector: #selector(LinkProxy.tick(_:)))
      l.add(to: .main, forMode: .common)
      link = l
      linkWantsHighRate = nil
    }
    applyFrameRateRange()
    link?.isPaused = false
  }

  /// 低电量模式下一律不进 120 Hz 档：跟手照样每帧刷，只是封顶 60（P2.10）。
  /// 每次换脏位都会重新读一次系统开关，所以用户中途开关低电量，下一帧就跟上。
  static func usesHighFrameRate(wantsHigh: Bool, lowPower: Bool) -> Bool {
    wantsHigh && !lowPower
  }

  private func applyFrameRateRange() {
    guard let link else { return }
    let high = Self.usesHighFrameRate(
      wantsHigh: wantsHighFrameRate, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
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
    // 挂动画才需要帧；离屏时直接丢掉——没有窗口就没有帧，留着它只会让下一次
    // 入窗从半截惯性开始，而这半截是用户早就看不见的那一程。
    didSet {
      guard animation != nil else { return }
      if window == nil { animation = nil } else { resumeLink() }
    }
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
    #if DEBUG
    let probeStart = CACurrentMediaTime()
    defer {
      if let hook = onRenderPartForProbe {
        hook(part == .plot ? "plot" : part == .live ? "live" : "cross",
             (CACurrentMediaTime() - probeStart) * 1000)
      }
    }
    #endif
    guard let renderer, size.width > 0, size.height > 0 else {
      ctx.clear(CGRect(origin: .zero, size: size))
      #if DEBUG
      if part == .live { renderedDepthRows = 0 }
      #endif
      return
    }
    switch part {
    case .plot: renderer.drawPlot(in: ctx, size: size, scale: scale)
    case .live:
      let count = renderer.drawLive(in: ctx, size: size, scale: scale)
      #if DEBUG
      renderedDepthRows = count
      #endif
    case .cross: renderer.drawCross(in: ctx, size: size, scale: scale)
    }
    #if DEBUG
    if part != .cross { onRenderedForProbe?() }
    renderCounts[part == .plot ? "plot" : part == .live ? "live" : "cross", default: 0] += 1
    #endif
  }

  #if DEBUG
  /// 诊断口子（M5 A5.2「收到行情事件 → 画进图层」计时），正式包里没有。
  /// `onAdoptedForProbe`：新状态进来了，参数是这一次有没有置上脏位（没有就不会重画）。
  /// `onRenderedForProbe`：蜡烛层或最新价层刚画完一次。
  public var onAdoptedForProbe: ((Bool) -> Void)?
  public var onRenderedForProbe: (() -> Void)?
  /// 分层计时：哪一层、画了多少毫秒。只给采帧诊断用。
  public var onRenderPartForProbe: ((String, Double) -> Void)?
  /// 三层各真画了几次（审查 31 / 32 的秤）：静置时、十字线移动时底图有没有被白画，
  /// 取证用例前后各读一次相减。只在 DEBUG 里有，诊断 JSON 的 `renderCounts`。
  private(set) var renderCounts: [String: Int] = [:]
  /// 主力订单流快照换了几次（新快照和上一份不相等才算），诊断 JSON 的 `orderFlowAdoptions`。
  private(set) var orderFlowAdoptions = 0
  #endif
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
///
/// 「空转一次就没了」原来是句空话：宿主释放之后没人再叫 `invalidate()`，link 仍然
/// 挂在主 runloop 上，每帧醒来一次、一直醒到进程结束。所以回调要把 link 自己收进来
/// （`CADisplayLink` 调 selector 时把自己当参数传过来），发现宿主没了就地作废。
@MainActor
private final class LinkProxy: NSObject {
  private weak var view: ChartView?
  init(_ view: ChartView) {
    self.view = view
    super.init()
  }

  @objc func tick(_ link: CADisplayLink) {
    guard let view else { link.invalidate(); return }
    view.onFrame()
  }
}
