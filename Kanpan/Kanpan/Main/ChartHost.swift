import KanpanChart
import KanpanCore
import SwiftUI
import UIKit

/// 换了数据之后视野该怎么办。
///
/// 冷启动、切周期和布局改变通过同一底座调整视野，
/// 差别在于「保住什么」：**换品种保根宽、不保位置**，换周期保根宽，风格变化保留整个视野。
///
/// 换品种为什么位置和根宽分开处理：
/// - **位置不保**。位置是「我在看 3 月 14 号那一段」。换到另一个品种，同一段时间上
///   什么都没有——那儿的行情和我刚才在看的事没有关系。所以位置一律回到最新。
/// - **根宽要保**。根宽是「我要一屏看多少根」，这是人的看盘习惯，和看的是哪个品种无关。
///   以前这里连根宽一起清掉，用户捏小了图去自选点下一个品种，K 线又变回一屏五十根，
///   每换一个品种就得重捏一次。现在根宽住在 `Prefs.barSpacing`，所有品种、所有周期
///   共用一份，跨 app 重启也在（见 `ChartBox.resetSpacing`）。
enum ViewIntent: Equatable {
  case keep
  /// 换品种、第一次拿到数据：回到最新，根宽按用户存下来的那一份（`ChartBox.resetSpacing`）。
  case reset
  /// 换周期：根宽不变，看见的时间跨度跟着周期走。带的是切之前量出来的实际根间距。
  ///
  /// `anchorRight` 是切之前视野的右缘时刻，只在**正看着历史**时带上：人翻到三个月前那一段，
  /// 切一下周期就被送回最新，刚找到的位置就没了（A-05）。跟着最新时它是 nil，
  /// 右缘照常贴到新序列的末根上。
  case switchInterval(spacing: Double, anchorRight: Double?)
  /// 布局改尺寸：保留实际根间距和历史右缘。
  case resize(spacing: Double)
  /// **档案到货，按新根宽重量一次。** 位置（历史右缘）保住，只换宽度。
  ///
  /// 为什么非有这一档不可：登录的人冷启动时档案要等 `account.restore()` 那条异步链才到，
  /// 图早就按出厂宽度开完张了。到货之后只改内存里那份是不够的——`resetSpacing` 只有
  /// `.reset` 那一支会消费，`.switchInterval` / `.resize` 都是从**图自己身上**取宽度，
  /// 没有任何一条会回头去读新到货的值。于是图会一直画在错的宽度上，直到某次视野变化
  /// 把它当成用户意图报回去、反过来把档案里对的那份覆盖掉（`ChartViewport` 的「杀法甲」）。
  case adopt(spacing: Double)
  /// **把视野铺到一个指定的时间窗上。** 「看细节」（§10.1）专用：十字线选中一根大 K 线，
  /// 换到更细的一档之后，视野要刚好是那一根覆盖的那一段，而不是新周期的最新一屏。
  ///
  /// 和 `.switchInterval` 的区别是位置由外面说了算：那一档保的是根宽，这一档保的是**时间**，
  /// 根宽由窗宽和图区宽度反推（`clampView` 会把它夹在 1.6～40pt 之间）。
  case window(ViewWindow)
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
  /// `.reset` 时用哪个根间距。外面每次接线都灌一遍（`ChartHost.wire`），值来自
  /// `Prefs.barSpacing`——用户上次捏到的那个宽度。没存过就是出厂的 `initialSpacing`。
  var resetSpacing = AICoinBehavior.initialSpacing
  /// 上一次兑现过的「档案到货」序号。见 `ChartHost.adoptToken`。
  var lastAdoptToken = 0
  /// 上一次报出去的翻转状态。图每改一次状态都会回调一次，先在这儿比一下，
  /// 没变就不劳烦 `PrefsStore` 去比整份设置。
  var lastInversion: (main: Bool, subs: Set<IndicatorID>)?
  /// 视野兑现完还欠一下「回到最新」。见 `ChartProxy.scrollToLatest(animated:)`：
  /// 那一下经常提在图还没量出宽度的时候，只能记账、等 `layoutSubviews` 兑现。
  var pendingLatest = false

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
      ChartContentLayout.height(viewport: Double(bounds.height), subs: state.subs, portrait: portrait)
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
    // 顺序不能反：`applyPending()` 先把根间距/视野落到位（换页回来走的是
    // `.resize`，保住用户缩放过的根宽），然后这一下只把视野推到右缘。
    if pendingLatest, chart.chartLayout != nil, (chart.state?.series.count ?? 0) > 0 {
      pendingLatest = false
      chart.scrollToLatest(animated: false)
    }
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
          spacing: resetSpacing, anchor: s.options.anchor)
      case .switchInterval(let spacing, let anchorRight):
        s.view = ViewMath.switchInterval(to: s.series, plotW: plotW, spacing: spacing,
                                         anchorRight: anchorRight)
      case .resize(let spacing), .adopt(let spacing):
        s.view = ViewMath.resized(s.view, series: s.series, plotW: plotW, spacing: spacing, anchor: s.options.anchor)
      case .window(let want):
        s.view = clampView(want, series: s.series, plotW: plotW, anchor: s.options.anchor)
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
  /// 上一次兑现过的「档案到货」序号（`ChartHost.adoptToken`）。
  ///
  /// **记在这儿而不是盒子上，因为盒子活不过一次换页。** 用户 2026-09-19 报的现象：
  /// 登录状态冷启动 → 落在自选页 → 点 BTC → 图还是出厂宽度，之前捏出来的那份没了；
  /// 而盘上、云端两处的 `barSpacing` 取证下来都是对的。病根就在这个序号的存放位置：
  ///
  /// 1. 冷启动 `MainScreen` 的 `tab` 出厂是 `.chart`，图先按 4pt 开张，`savedState`
  ///    记下一份 4pt 的视野；
  /// 2. `account.restore()` 把档案读回来，`ChartViewport.adopt` 把序号 +1，**同一轮**里
  ///    `honorProfile` 又把 `tab` 翻到 `.favorites`——图被拆掉，这次到货没有任何一个
  ///    盒子来兑现；
  /// 3. 用户点进同一个品种，`makeUIView` 拿 `savedState` 把 4pt 的视野原样装回去，
  ///    并把序号记成「已兑现」——那次到货就此蒸发。之后随便一次拖动，图把 4pt
  ///    当成用户意图报回去，反手把盘上和云端那份真值也写掉。
  ///
  /// 序号跟着 `MainScreen` 的 `@State` 活着，重建盒子时就能看出「我不在的时候档案
  /// 到过货」，改按 `resetSpacing` 重量一次（`.adopt`），位置照旧留着。
  var lastAdoptToken = 0
  /// 还欠一下「回到最新」。
  ///
  /// 竖屏的三张整页是 `switch tab` 拆出来的：换到自选再换回行情，`chartPage` 整棵树
  /// 重建一遍，`box` 这根弱引用在那一瞬是空的。而两处「回到最新」——底栏点「图表」格
  /// （`switchTo(tab:)`）和自选里点回**同一个**品种（`picker.onPick`）——恰恰都在
  /// `tab = .chart` 的同一轮里发出，那时候图还没建出来，这一下全打在空气上。
  /// 表现出来就是：拖到历史区，去自选转一圈再点回来，图还停在历史那一段。
  /// 所以这里记一笔，等图建好、量出图区宽度（`chartLayout`）之后再兑现。
  fileprivate var wantsLatest = false
  /// 还欠一下「把视野铺到这一段时间上」（「看细节」，§10.1）。
  ///
  /// 和 `wantsLatest` 同一个毛病、同一个治法：提这一下的时候（人刚点了「看细节」）新那档
  /// 的数据还在路上，图上还是旧周期，当场铺等于铺在错的序列上。所以记一笔，等对得上的
  /// 序列到了再兑现。`tries` 是这笔账的有效期——细档的历史可能一时补不到那么早
  /// （`clampView` 会先把视野顶在现有数据的左边缘上，图自己会去要更多历史，
  /// 下一批到了再铺一次），但不能无限期地等着，否则它会在很久以后冷不丁跳出来。
  fileprivate var wantsWindow: (symbol: String, interval: Interval, view: ViewWindow, tries: Int)?

  /// 一笔账最多跨多少轮渲染。约等于数据来回两三趟的量。
  private static let windowAttempts = 30

  /// 「看细节」：等这个品种的这一档数据到了，把视野铺成 `window`。
  func show(window: ViewWindow, symbol: String, interval: Interval) {
    wantsWindow = (symbol.uppercased(), interval, window, 0)
    box?.setNeedsLayout()
  }

  /// 人自己动了手（换档、换品种、在图上拖），这笔账就作废——别在他后来做的事上面盖一层。
  func cancelWindow() { wantsWindow = nil }

  /// 这一轮该不该把视野铺过去。对不上的序列先记一笔次数，等下一轮。
  fileprivate func window(for series: BarSeries) -> ViewWindow? {
    guard let want = wantsWindow else { return nil }
    guard want.tries < Self.windowAttempts else { wantsWindow = nil; return nil }
    wantsWindow?.tries = want.tries + 1
    guard series.count > 0, want.interval == series.interval,
          want.symbol == series.symbol.uppercased() else { return nil }
    // 历史已经补到那一段的左边了：这笔账兑现完就销。还没补到就先铺一次（视野会被夹在
    // 现有数据的左缘，图当场去要历史），账留着，下一批数据到了再铺准。
    if Double(series.firstTime) <= want.view.from { wantsWindow = nil }
    // 铺完再补报一次视野。这一下是在 SwiftUI 的更新里发生的（`updateUIView` →
    // `applyPending`），那一轮里 `onViewChanged` 报出去的位置到不了 `@State`：
    // 实测「看细节」钻进历史之后，周期条行尾那颗「最新」不露面，人就没路回来了。
    // 隔一个 runloop 用同一个口子再报一次（`onViewChanged` 本来就是「谁造成的都来」），
    // 位置类的事就都对上了。
    renotify()
    return want.view
  }

  /// 下一个 runloop 把当前视野按原样再报一次。不改任何状态，只是让程序摆的这一下
  /// 也能走到 `onViewChanged` 的订阅者那儿去。
  private func renotify() {
    DispatchQueue.main.async { [weak self] in
      guard let box = self?.box, let view = box.chart.state?.view else { return }
      box.chart.onViewChanged?(view)
    }
  }

  func scrollToLatest(animated: Bool = true) {
    // 没有图、还没量出布局、或者数据还没到——`ChartView.scrollToLatest` 这三种情况
    // 都会直接 return，等于这一下丢了。记账，别丢。
    guard let box, box.chart.chartLayout != nil, (box.chart.state?.series.count ?? 0) > 0 else {
      wantsLatest = true
      return
    }
    box.chart.scrollToLatest(animated: animated)
  }

  /// 把欠的那一下交给图；交完就销账。
  fileprivate func handOverLatest(to box: ChartBox) {
    guard wantsLatest else { return }
    wantsLatest = false
    box.pendingLatest = true
    // 盒子可能已经躺在那儿不动了（比如只是 `renderingActive` 翻了个面，帧没变），
    // 那样 `layoutSubviews` 不会自己来。这里点它一下，欠的账才有人兑现。
    box.setNeedsLayout()
  }
  /// 十字线往左 / 往右挪一根（§P3-7）。图还没建出来就当没这回事——
  /// 那三颗药丸只有十字线活着时才在屏幕上，图不在十字线也不在。
  func moveCrosshair(by step: Int) { box?.chart.moveCrosshair(by: step) }

  /// 按十字线此刻这口价画一条水平线（§P3-7）。走的是画线自己那条落笔路。
  @discardableResult
  func addHorizontalLine(at price: Double) -> Bool {
    box?.chart.addHorizontalLine(at: price) ?? false
  }

  var isAtLatest: Bool { box?.chart.isAtLatest ?? true }
  /// 此刻图上真正在看的那段时间。视野归图自己管，外面要读就从这儿读
  /// （换品种时想停在同一段时间上、「看细节」钻下去前要记一笔，都要它）。
  var currentView: ViewWindow? { box?.chart.state?.view ?? savedState?.view }
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
  /// `.reset`（换品种 / 第一次拿到数据）时回到多宽的根间距。见 `ViewIntent`。
  /// 传下来的是 `PrefsStore.liveBarSpacing`——内存里那一份，不是节流之后才落盘的那一份：
  /// 用户捏完下一秒就换品种，新图得按刚刚那个宽度开。
  var resetSpacing = AICoinBehavior.initialSpacing
  /// **用户**在图上捏出来的根间距。一次捏合就是一串，接的人内存里立刻认、
  /// 手一松就落盘（`ChartViewport`）。
  ///
  /// 只有手势来源的视野变化才走这儿：程序自己造成的（`.reset` / `.switchInterval` /
  /// `.resize` / `.adopt` / 「回到最新」）**一律不报**，否则图会把自己开张时那份
  /// 出厂宽度当成用户意图，反过来把档案里真正的那份覆盖掉。见 `ChartView.onUserViewChanged`。
  var onBarSpacing: (Double) -> Void = { _ in }
  /// **用户自己**动了视野（拖、捏、甩）。和 `onBarSpacing` 同一个源头，
  /// 但报的是「他动手了」这件事本身，不是宽度——「返回刚才」那条后路靠它作废（§P3-2）。
  var onUserView: () -> Void = {}
  /// 手指全部离开画布了。落盘与同步的时机钉在这儿，见 `ChartView.onInteractionEnded`。
  var onInteractionEnded: () -> Void = {}
  /// 「档案到货」的序号。变一次，图就按 `resetSpacing` 重量一次（`ViewIntent.adopt`）。
  /// 由 `ChartViewport.adoptToken` 提供——它是个事件计数器，不是值，理由写在那儿。
  var adoptToken = 0
  /// 主图 / 副图的上下翻转变了。只在真变了的那一下报。
  var onInversion: (Bool, Set<IndicatorID>) -> Void = { _, _ in }
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
  /// **用户刚亲手画完一条线**（改、拖、同步下来的都不算）。带上当时那个品种，
  /// 接的人不必再去猜图上是谁。提醒模块拿它弹确认卡（方案 2.3），
  /// 这儿**只转交，不判断**——提醒的规矩一个字都别写进图表宿主里。
  var onDrawingCommitted: (Drawing, String) -> Void = { _, _ in }
  /// 哪几条线上挂着提醒。图照它在线的右端点一枚小铃铛。
  var alertedDrawingIDs: Set<String> = []

  func makeUIView(context: Context) -> ChartBox {
    let box = ChartBox(frame: .zero)
    proxy?.box = box
    box.chart.isHidden = !renderingActive
    guard renderingActive else { return box }
    box.portrait = portrait
    wire(box)
    proxy?.handOverLatest(to: box)
    var incoming = state
    if var next = incoming, let saved = proxy?.savedState, let width = proxy?.savedPlotWidth,
       next.series.symbol == saved.series.symbol, next.series.interval == saved.series.interval {
      next.view = saved.view
      if next.price.mode == saved.price.mode { next.price = saved.price }
      next.subInverted = saved.subInverted
      next.crosshair = next.options.dataDisplay == saved.options.dataDisplay && next.options.crossPrice == saved.options.crossPrice ? saved.crosshair : nil
      incoming = next
      // 图不在的那段时间档案到过货（见 `ChartProxy.lastAdoptToken`）：存下来的那份
      // 视野宽度是旧的，位置留着、宽度按档案重量。没到过货就原样装回去。
      box.pending = adoptToken != consumedAdoptToken(box)
        ? .adopt(spacing: resetSpacing)
        : .resize(spacing: saved.view.barSpacing(step: saved.series.step, plotW: width))
    }
    box.chart.state = incoming
    // 走到这儿要么按 `resetSpacing` 走 `.reset`，要么上面已经补了 `.adopt`——
    // 这次到货算兑现过了。
    consumeAdoptToken(box)
    return box
  }

  /// 上一次兑现过的到货序号。有把手就以把手上那份为准（它活得过换页），
  /// 没把手（横屏工作台之类只活一阵的图）就退回盒子自己记的那份。
  private func consumedAdoptToken(_ box: ChartBox) -> Int { proxy?.lastAdoptToken ?? box.lastAdoptToken }
  private func consumeAdoptToken(_ box: ChartBox) { proxy?.lastAdoptToken = adoptToken; box.lastAdoptToken = adoptToken }

  func updateUIView(_ box: ChartBox, context: Context) {
    proxy?.box = box
    box.chart.isHidden = !renderingActive
    guard renderingActive else { return }
    box.portrait = portrait
    wire(box)
    proxy?.handOverLatest(to: box)
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
        // 「跟着最新」和「在看历史」是两件事，换周期时的右缘也就该落在两个地方（A-05）：
        // 前者贴到新序列的末根上（传 nil），后者把切之前那个时刻原样带过去，由
        // `ViewMath.switchInterval` 夹进新序列。判据和「回到最新」按钮的显隐同一条
        // （`ChartView.isAtLatest`）：右缘越过末根就算跟着最新。
        let followingLatest = old.series.count > 0 && old.view.to >= Double(old.series.lastTime)
        box.pending = .switchInterval(
          spacing: old.view.barSpacing(step: old.series.step, plotW: plotW),
          anchorRight: followingLatest ? nil : old.view.to)
        // 换周期要把竖着拉出来的倍率留住。
        //
        // 这两行以前只写在下面那个 `else` 里，而那条分支的前提是「品种没换**且**周期
        // 没换」——于是一换周期，`s.price` 就用 SwiftUI 快照里的出厂值（zoom = 1、
        // 居中 0.5），人刚在价格轴上拉出来的倍率当场没了。根宽（`switchInterval` 那句）
        // 早就是保住的，纵向没跟上，同一次换周期里横着的习惯留着、竖着的丢了。
        //
        // **换品种仍然要丢**，所以这两行不能提到上面去：不同品种的价格区间不一样，
        // 把上一个品种拉出来的倍率搬过去没有意义。
        if old.price.mode == s.price.mode { s.price = old.price }
        else { s.price.inverted = old.price.inverted }
      } else {
        // 手指正按着十字线或某个画线锚点时，坐标是钉死的（`ChartView.axesFrozen`）：
        // 新 K 线照常进序列，但视野一格都不许挪——`reconcile` 把右缘往右推一格，
        // 手指底下那根 K 线就跟着跑了，线看上去像自己在动。抬手那一刻
        // `endAxisFreeze` 会一次追平，不留台阶。
        if !box.chart.axesFrozen, let layout = box.chart.chartLayout {
          s.view = AICoinBehavior.reconcile(old.view, from: old.series, to: s.series, plotW: layout.plotW, anchor: s.options.anchor)
        }
        // Price transforms belong to the chart, not the SwiftUI settings snapshot.
        if old.price.mode == s.price.mode { s.price = old.price }
        else { s.price.inverted = old.price.inverted }
      }
    } else {
      box.pending = .reset
    }
    // 档案到货：图得按新到货的根宽重新起点。放在所有 `pending` 赋值之后——
    // `.reset`（换品种 / 第一次拿到数据）本来就用 `resetSpacing` 开张，不用再重量一次。
    if adoptToken != consumedAdoptToken(box) {
      consumeAdoptToken(box)
      if box.pending != .reset { box.pending = .adopt(spacing: resetSpacing) }
    }
    // 「看细节」欠的那一下：放在所有 `pending` 赋值之后——这一下是人刚按下去的意图，
    // 优先于换周期那条默认的「保根宽、贴最新」。数据还没到就什么都不做，账留着。
    if let want = proxy?.window(for: s.series) { box.pending = .window(want) }
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
    box.resetSpacing = resetSpacing
    drawing?.attach(box.chart)
    // 视野一变就顺手把根间距量出来报上去。量它要图区宽度，那是 UIKit 这一侧才知道的事，
    // 所以在这儿落笔而不是让 SwiftUI 那边自己去翻 `proxy.box`。
    // 两个口子分工严格，别合回一个：
    // - `onViewChanged`：**谁造成的都来**。位置类的事（补 OI、周期条行尾那颗「最新」）读它。
    // - `onUserViewChanged`：**只有用户手上的动作**。「用户想要多宽」只能从这儿量。
    //   合回一个的后果就是这次的 bug：`applyPending()` 末尾那句 `chart.onViewChanged?(s.view)`
    //   会把程序刚摆好的宽度当成用户意图报出去。
    let onView = self.onView, onBarSpacing = self.onBarSpacing
    box.chart.onViewChanged = { view in onView(view) }
    let onUserView = self.onUserView
    box.chart.onUserViewChanged = { [weak box] view in
      onUserView()
      guard let box, let layout = box.chart.chartLayout,
            let series = box.chart.state?.series, series.count > 0 else { return }
      onBarSpacing(view.barSpacing(step: series.step, plotW: layout.plotW))
    }
    box.chart.onInteractionEnded = onInteractionEnded
    box.onSubResize = onSubResize
    box.onSubReorder = onSubReorder
    box.chart.onCrosshairChanged = onCrosshair
    box.chart.onNeedsHistory = onNeedsHistory
    box.chart.onTapped = onTapped
    box.chart.onNotice = onNotice
    box.chart.alertedDrawingIDs = alertedDrawingIDs
    let onDrawingCommitted = self.onDrawingCommitted
    box.chart.onDrawingCommitted = { [weak box] item in
      guard let symbol = box?.chart.state?.series.symbol, !symbol.isEmpty else { return }
      onDrawingCommitted(item, symbol)
    }
    let onInversion = self.onInversion
    box.chart.onStateChanged = { [weak proxy, weak box] state in
      box?.updateControls()
      guard let state, let box, let layout = box.chart.chartLayout else { return }
      proxy?.savedState = state
      proxy?.savedPlotWidth = layout.plotW
      // 翻转是双击翻一下的离散动作，但这个回调每改一次状态都来一趟，先自己比一下。
      let now = (main: state.price.inverted, subs: state.subInverted)
      if let last = box.lastInversion, last == now { return }
      box.lastInversion = now
      onInversion(now.main, now.subs)
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
