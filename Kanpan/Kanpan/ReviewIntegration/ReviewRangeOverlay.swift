import SwiftUI
import UIKit
import KanpanCore
import KanpanChart
import ReviewDomain
import ReviewUI

struct ReviewRangeOverlay: UIViewRepresentable {
  var feature: ReviewFeature
  var bridge: ReviewChartBridge
  var liveProxy: ChartProxy
  /// 横屏画线时置真：这一层什么都不画（§2E5）。记录一条没少，只是这一帧不上图。
  var suppressed = false
  /// 刚记下的那一条（§2F2）：进来一个新 id 就闪一下，告诉用户「记号落在这儿了」。
  var flash: UUID?
  /// 非圈选时点图上已画的那条记录（落图标签那一小块）打开它的详情（P3.7）。
  /// 画线、横屏、回放时不接手指——那时候图上的手势都是别人的。
  var tappable = false
  var onOpenRecord: (UUID) -> Void = { _ in }
  /// 这一层是 UIKit 手绘的，取不到 SwiftUI 那套 `foregroundStyle`，所以配色得自己端进去。
  ///
  /// 原来它把橙色（`UIColor.systemOrange`）钉死在自己那边：SwiftUI 那几页早就跟着
  /// 皮肤走了，只有画在图上的这一层没跟上——青苔是墨绿强调、陶土是赤陶强调，
  /// 满屏就这块橙谁都不像。和 `ReviewThemeBridge` 是同一件事的 UIKit 版。
  @Environment(\.panelTheme) private var theme
  func makeUIView(context: Context) -> RangeOverlayView { RangeOverlayView() }
  func updateUIView(_ view: RangeOverlayView, context: Context) {
    view.accent = UIColor(theme.amber)
    view.canvas = UIColor(theme.chartBG)
    view.subdued = UIColor(theme.ink3)
    view.feature = feature; view.bridge = bridge
    view.proxy = bridge.active ? bridge.proxy : liveProxy
    view.draft = (bridge.mode == .capture && !suppressed) ? feature.draft : nil
    view.records = suppressed ? [] : feature.records
    view.suppressed = suppressed
    view.flash(suppressed ? nil : flash)
    view.tappable = tappable && bridge.mode == .live && !suppressed
    view.onOpenRecord = onOpenRecord
    view.isUserInteractionEnabled = bridge.mode == .capture || view.tappable
    view.attach()
    view.setNeedsDisplay()
  }
}
final class RangeOverlayView: UIView {
  weak var feature: ReviewFeature?
  weak var bridge: ReviewChartBridge?
  weak var proxy: ChartProxy?
  var draft: ReviewDraft?
  var records: [ReviewRecord] = []
  /// 见 `ReviewRangeOverlay.suppressed`。回放态那一支不吃 `records`，所以得单独挡一道。
  var suppressed = false
  /// 选区带、目标 / 失效横线、手柄、落图记号统一用的强调色（见 `ReviewRangeOverlay.theme`）。
  ///
  /// 这三支的默认值都从出厂那套种子（青苔浅）直接取，**不取系统色**：`updateUIView`
  /// 在第一次 `draw(_:)` 之前一定跑过一遍，默认值原则上看不见；但只要它是
  /// `.systemOrange` / `.systemBackground` 这类系统色，下一个人读这段就会以为
  /// 「这一层还允许系统色」。这一层一支系统色都不留。
  var accent: UIColor = UIColor(Color(hex: Palette.lightSeed.accent))
  /// 画布自己的底（`PanelTheme.chartBG`）。手柄的描边走它，才能在任何皮肤下都把
  /// 那颗圆点从背后的蜡烛里剜出来；原来写死 `UIColor.white`，落在
  /// `#F3F7F4` / `#FBF6F0` / `#FFFFFF` 这几张浅画布上等于没画。
  var canvas: UIColor = UIColor(Color(hex: Palette.lightSeed.chart))
  /// 次一级的记号色（`PanelTheme.ink3`）：有效期那条虚线用它。
  ///
  /// 那条线原来是 `UIColor.secondaryLabel`——它只跟系统的浅 / 深走，不跟皮肤走，
  /// 于是青苔、陶土、经典三套皮肤的图上都横着同一支蓝灰。而且它在浅色画布上
  /// 只有 3.3:1（`#3C3C43` 60% 压在 `#F3F7F4` 上算出来是 `#85878A`），`ink3` 是
  /// 4.9:1（青苔浅）到 5.4:1（青苔深），六套皮肤全部过 4.5:1。
  ///
  /// 取 `ink3` 而不是 `ink2`：有效期是这张图上**最次**的一条线——目标价、失效价
  /// 走强调色，选区边框走强调色 0.8，它只是「到这天为止」。`ink2` 在深色皮肤上
  /// 有 8.7–9.1:1，比旁边那两条 0.3 透明度的强调线还抢眼，读起来像主角。
  var subdued: UIColor = UIColor(Color(hex: Palette.lightSeed.ink3))
  /// 闪一下的实现（§2F2）：只记「闪的是哪一条」和「这一帧是亮还是暗」，
  /// 剩下的交给一个短定时器。不用 CoreAnimation 是因为这一层是手绘的 `draw(_:)`，
  /// 没有可以动画的 layer 属性；三次明暗切换共 0.9 秒，够看见，不至于闪得人眼晕。
  private var flashID: UUID?
  private var flashOn = false
  private var flashTimer: Timer?
  private var dragPart = ""
  /// 见 `ReviewRangeOverlay.tappable`。
  var tappable = false
  var onOpenRecord: (UUID) -> Void = { _ in }
  /// 这一帧每条落图记录的可点区域（落图标签那一块），`draw(_:)` 里顺手记下。
  private var hotspots: [(CGRect, UUID)] = []
  private var tapTarget: UUID?
  private var tapOrigin = CGPoint.zero
  /// 贴边自动滚动（P3.7）：拖选区的左右手柄或整段圈选时，手指进了离边 24pt 以内，
  /// 图就按手指压进去的深度往那一头滚，边滚边把选区跟到手指下面那根。
  private static let edgeZone: CGFloat = 24
  private var edgeLink: CADisplayLink?
  private var lastTouch = CGPoint.zero
  private var startIndex = 0
  private var before: ReviewDraft?
  override init(frame: CGRect) { super.init(frame: frame); isOpaque = false; backgroundColor = .clear; isMultipleTouchEnabled = false }
  required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
  private var chart: ChartView? { proxy?.box?.chart }
  func flash(_ id: UUID?) {
    guard id != flashID else { return }
    flashID = id; flashTimer?.invalidate(); flashOn = false
    guard id != nil else { setNeedsDisplay(); return }
    var left = 6   // 亮灭各三次
    // `Timer` 的 block 在严格并发下是 `@Sendable` 的非隔离上下文，而这一层是 `UIView`
    // 子类、整个在主 actor 上，所以里面每一次碰 `self` 都会挨一条「不能从非隔离上下文
    // 调用」。定时器是在主 actor 的 `flash(_:)` 里挂到当前 runloop 上的，回调只会在
    // 主线程上来，这里就把这件既成事实如实声明一次。不改成 `Task { @MainActor in }`
    // 是因为那样每一次亮灭都要多等一次调度，0.15 秒的节奏会漂。
    // `timer` 本身留在隔离区外：它是任务隔离的，塞进主 actor 闭包会被判「sending
    // 'timer' risks causing data races」。所以里面只答一句「还闪不闪」，invalidate
    // 在外面做——view 已经没了也照样收得掉，不会在 runloop 上留一个空转的定时器。
    flashTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] timer in
      let keepGoing = MainActor.assumeIsolated { () -> Bool in
        guard let self else { return false }
        self.flashOn.toggle(); left -= 1
        if left <= 0 { self.flashOn = false; self.flashTimer = nil }
        self.setNeedsDisplay()
        return left > 0
      }
      if !keepGoing { timer.invalidate() }
    }
    setNeedsDisplay()
  }
  /// 只给 UI 用例看的一个数：这一帧到底把几条记号画到了当前这张图上。
  ///
  /// 记号是在 `draw(_:)` 里手绘的，XCUITest 看不见画布上的像素，于是「切了周期记号
  /// 还在不在」这类事没法端到端验。和顶栏、主屏那两处诊断口径一样，用
  /// `KANPAN_CHART_DIAGNOSTICS=1` 单独开一道门：平时这一层压根不是无障碍元素，
  /// 不会多出一个读屏焦点，也不会挡住底下那张 `chart.canvas`。
  ///
  /// 报的不只是那个数：后面还跟着这一帧**是在哪张图上**画的（本机一共几条记录、
  /// 品种、周期、行情源）。用例红了的时候，「记号没出来」和「这一帧根本还是上一档
  /// 周期的图」是两件完全不同的事，只报一个数分不出来。
  ///
  /// 这道门**只在 DEBUG 构建里存在**（审查 C-02）：正式包里它恒为 `false`，
  /// 这一层永远不是无障碍元素，不会因为启动环境里多了个变量就把记号数念出来。
  private static let diagnostics: Bool = {
    #if DEBUG
    return ProcessInfo.processInfo.environment["KANPAN_CHART_DIAGNOSTICS"] == "1"
    #else
    return false
    #endif
  }()
  private func report(marks: Int, state: ChartState) {
    guard Self.diagnostics else { return }
    // 末尾带上最后一条可点记号的中心（相对这一层），用例靠它去点「图上那条记录」。
    let spot = hotspots.last.map { " @\(Int($0.0.midX)),\(Int($0.0.midY))" } ?? ""
    let value = "\(marks)/\(records.count) \(state.series.symbol) \(state.series.interval.rawValue) \(bridge?.liveVenue ?? "-")" + spot
    if probe.accessibilityValue != value { probe.accessibilityValue = value }
  }

  /// 诊断口挂在一块 1×1 的探针上，不把这一层自己变成无障碍元素。
  ///
  /// 上面那段说「平时这一层压根不是无障碍元素……不会挡住底下那张 `chart.canvas`」——
  /// 原来的写法（`db97365`）却恰好把这句话作废了：`KANPAN_CHART_DIAGNOSTICS=1` 一开，
  /// `report` 就把**铺满整个图区**的这一层翻成无障碍元素。无障碍命中测试和手指的
  /// 命中测试是两回事，它不看 `isUserInteractionEnabled`（读屏本来就要能念到不可点的
  /// 静态内容），所以这一层即使在非取景态（`allowsHitTesting(false)`）也照样把图上
  /// 所有东西挡住：XCUITest 问 `chart.canvas`、问副图分隔线把手 `chart.resize.*`
  /// 能不能点，命中测试先撞上它，一律答「点不着」——`testThreeSubpanelsFitWithoutPageScroll`
  /// 就是这么红的。真人的手指从头到尾没被挡过，所以只有用例看得见这个病。
  ///
  /// 现在这一层自己永远不是无障碍元素，值挂在左上角一块 1×1 的子视图上（和
  /// `market.source` 那个诊断口一个做法）。命中测试落在图上任何地方都穿得过去，
  /// `ReviewFlowUITests` 要的那个记号数照样读得到。
  private lazy var probe: UIView = {
    let view = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    view.isUserInteractionEnabled = false
    view.isAccessibilityElement = true
    view.accessibilityIdentifier = "review.range"
    addSubview(view)
    return view
  }()

  // MARK: - 这一层自己盯着图有没有换内容

  /// 记号画在图**上面**的一层独立 `UIView` 里，它自己并不知道图什么时候换了内容。
  /// 原来只有两条路会叫它重画，而这两条路都会断：
  ///
  /// - **SwiftUI 那条**（`updateUIView`）：这一层的入参全是引用类型（feature / bridge /
  ///   proxy）加两个小值，换周期、换品种时它们一个都没变，SwiftUI 比下来「没变化」就
  ///   不再下发这一层；
  /// - **盒子那条**（`ChartBox.onOverlayUpdate`）：`ChartProxy.box` 是弱引用，盒子活不过
  ///   一次换页/重建，盒子一换，挂在旧盒子上的那个回调就跟着没了——而重新挂钩恰恰只发生在
  ///   上面那条已经断掉的路里。
  ///
  /// 用例 A 抓到的就是这个：1h 上记一笔 → 切到 1m（记号正确地不画）→ 切回 1h，图已经是
  /// 1h 了，这一层还停在 1m 那一帧上，用户的记号就这么没了。所以这一层自己盯着：在窗口里
  /// 的时候每 0.25 秒看一眼「我贴着的还是那只盒子吗、图上那段行情还是刚才那段吗」，变了
  /// 才重画。一次「看一眼」只是十来个字段的比较，不碰画布，静止时的开销可以忽略。
  private struct Frame: Equatable {
    var chart: ObjectIdentifier?
    var symbol = ""
    var interval = ""
    var bars = 0
    var lastTime: Int64 = 0
    var to = 0.0
    var span = 0.0
    var mode = ""
  }
  private var lastFrame = Frame()
  private weak var hooked: ChartBox?
  private var watchdog: Timer?

  /// 把「图重画了叫我一声」挂到**当前**这只盒子上；换了盒子就重挂一次。
  func attach() {
    guard let box = proxy?.box, box !== hooked else { return }
    hooked = box
    box.onOverlayUpdate = { [weak self] in self?.setNeedsDisplay() }
    setNeedsDisplay()
  }

  private func currentFrame() -> Frame {
    guard let chart, let state = chart.state else { return Frame(mode: bridge?.mode.rawValue ?? "") }
    return Frame(chart: ObjectIdentifier(chart), symbol: state.series.symbol,
                 interval: state.series.interval.rawValue, bars: state.series.count,
                 lastTime: state.series.lastTime, to: state.view.to, span: state.view.span,
                 mode: bridge?.mode.rawValue ?? "")
  }

  private func resync() {
    attach()
    let now = currentFrame()
    guard now != lastFrame else { return }
    lastFrame = now
    setNeedsDisplay()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    watchdog?.invalidate(); watchdog = nil
    guard window != nil else { stopEdgeScroll(); return }
    // 同 `flash(_:)` 里那段：定时器挂在主 runloop 上，回调只会在主线程来，这里把这件
    // 既成事实如实声明一次；视图没了就让定时器自己收摊——`deinit` 是非隔离的，碰不了
    // 主 actor 上的这几个存储属性。
    let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] timer in
      let alive = MainActor.assumeIsolated { () -> Bool in
        guard let self else { return false }
        self.resync()
        return true
      }
      if !alive { timer.invalidate() }
    }
    // `.common`：捏合、拖动、列表滚动时 runloop 在 tracking 模式，默认模式的定时器
    // 会整段哑掉——那正是记号最该跟着动的时候。
    RunLoop.main.add(timer, forMode: .common)
    watchdog = timer
    resync()
  }
  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    guard let layout = chart?.chartLayout else { return false }
    let inPlot = point.x >= 0 && point.x <= layout.plotW && point.y >= 0 && point.y < layout.mainH
    if bridge?.mode == .capture { return inPlot }
    return inPlot && tappable && hotspots.contains { $0.0.contains(point) }
  }
  override func draw(_ rect: CGRect) {
    guard let chart, let state = chart.state, let layout = chart.chartLayout, let ctx = UIGraphicsGetCurrentContext() else { return }
    ctx.saveGState(); ctx.clip(to: CGRect(x: 0, y: 0, width: layout.plotW, height: layout.mainH))
    report(marks: 0, state: state)   // 先归零：下面只有实时那一支会往上画记号。
    hotspots = []
    if let draft { paint(draft, state: state, layout: layout, ctx: ctx, editing: true, outcome: nil) }
    else if suppressed { ctx.restoreGState(); return }
    else if bridge?.mode == .live {
      // 落图的条件统一在 `ReviewRecord.paints(venue:symbol:interval:)` 里（§2F3），
      // 那儿有单测盯着「BTC 的记号不许画到 ETH 上、1h 的不许画到 1m 上、
      // 另一家交易所记的不许画到这家的图上」。venue 这一条是这轮补的（审查 B.4）：
      // 记录一直带着捕获时的行情源，落图时却没人看它。
      let mine = records.filter {
        $0.paints(venue: bridge?.liveVenue ?? "binance", symbol: state.series.symbol,
                  interval: state.series.interval.rawValue)
      }.prefix(50)
      for record in mine {
        paint(record.draft, state: state, layout: layout, ctx: ctx, editing: false,
              outcome: record.outcome, emphasis: record.id == flashID && flashOn)
        // 可点的只有落图标签那一小块（44pt 见方起），其余图面照旧归图表的手势。
        let a = state.view.x(Double(record.draft.range.start), plotW: layout.plotW)
        let b = state.view.x(Double(record.draft.range.end), plotW: layout.plotW)
        let x = max(0, a), w = max(44, min(96, b - x))
        let spot = CGRect(x: x - 6, y: layout.mainH - 44, width: w + 12, height: 44)
          .intersection(CGRect(x: 0, y: 0, width: layout.plotW, height: layout.mainH))
        if !spot.isNull, spot.width > 8 { hotspots.append((spot, record.id)) }
      }
      report(marks: mine.count, state: state)
    } else if let record = bridge?.replayRecord, state.series.lastTime >= record.draft.range.start {
      // Outcomes and target annotations stay hidden until the judgment is known.
      if ReviewChartBridge.closeTime(state.series.lastTime, interval: state.series.interval) >= record.draft.created {
        paint(record.draft, state: state, layout: layout, ctx: ctx, editing: false, outcome: nil)
      }
    }
    ctx.restoreGState()
  }
  private func paint(_ draft: ReviewDraft, state: ChartState, layout: KanpanCore.Layout, ctx: CGContext, editing: Bool, outcome: ReviewOutcome?, emphasis: Bool = false) {
    let a = state.view.x(Double(draft.range.start), plotW: layout.plotW)
    let b = state.view.x(Double(draft.range.end), plotW: layout.plotW)
    let color = accent
    ctx.setFillColor(color.withAlphaComponent(editing ? 0.1 : (emphasis ? 0.14 : 0.035)).cgColor)
    ctx.fill(CGRect(x: a, y: 0, width: b - a, height: layout.mainH))
    ctx.setStrokeColor(color.withAlphaComponent(editing ? 0.8 : (emphasis ? 0.9 : 0.35)).cgColor)
    ctx.setLineWidth(emphasis && !editing ? 1.5 : 1)
    for x in [a, b] { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: layout.mainH)); ctx.strokePath() }
    if editing {
      for x in [a, b] { handle(CGPoint(x: x, y: layout.mainH * 0.52), ctx: ctx) }
      // 时间跟着**图表自己的时区档**走，和时间轴、十字线读数同一口径（审查 B-08）。
      // 原来这儿现造一个 `DateFormatter`，它认的是设备时区：图表切到「交易所（UTC+8）」
      // 或者 UTC 之后，同一根 K 线在轴上和在这条选区标签上写着两个时刻。
      // 文案本体在 `ReviewLabels.range` 里——那是复盘本、找相似列表、这条选区标签
      // 共用的同一个纯函数，用例直接驱动它（B-T18），测的就是屏上这一行。
      let label = ReviewLabels.range(bars: draft.range.bars, start: draft.range.start,
                                     end: draft.range.end,
                                     offsetMinutes: state.timezone.offsetMinutes)
      label.draw(at: CGPoint(x: 8, y: layout.mainH - 24), withAttributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: color])
    }
    if draft.rule.direction != .observe, let priceRange = chart?.chartPriceRange {
      for (value, title) in [(draft.rule.target, "目标"), (draft.rule.invalidation, "失效")] {
        let y = yOf(value, pane: layout.main, range: priceRange, mode: state.price.mode)
        ctx.setStrokeColor(color.withAlphaComponent(editing ? 0.75 : 0.3).cgColor)
        ctx.move(to: CGPoint(x: max(0, a), y: y)); ctx.addLine(to: CGPoint(x: layout.plotW, y: y)); ctx.strokePath()
        if editing {
          handle(CGPoint(x: layout.plotW - 18, y: max(18, min(layout.mainH - 42, y))), ctx: ctx)
          // 目标价 / 失效价的小数位由品种自己说（`ChartState.decimals`，也就是
          // `SymbolInfo.priceDecimals`），和顶栏、K 线价格轴一致（审查 B-07）。
          // 原来是「最多 6 位、能省就省」，于是 76800 写成 `76800`、0.0000004 写成
          // `0.0000004`，同一张图上两条线的写法能差出四位。
          ReviewLabels.price(title, value: value, decimals: state.decimals).draw(at: CGPoint(x: max(8, layout.plotW - 125), y: max(2, min(layout.mainH - 52, y - 17))), withAttributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: color])
        }
      }
      let expiry = min(layout.plotW - 18, max(18, state.view.x(Double(draft.rule.expires), plotW: layout.plotW)))
      // 有效期那条竖虚线走皮肤的 `ink3`（见 `subdued`），不是系统的 secondaryLabel。
      ctx.setLineDash(phase: 0, lengths: [3, 4]); ctx.setStrokeColor(subdued.cgColor)
      ctx.move(to: CGPoint(x: expiry, y: 0)); ctx.addLine(to: CGPoint(x: expiry, y: layout.mainH)); ctx.strokePath(); ctx.setLineDash(phase: 0, lengths: [])
      if editing { handle(CGPoint(x: expiry, y: 34), ctx: ctx) }
    }
    if !editing {
      let judgment = state.view.x(Double(draft.created), plotW: layout.plotW)
      ctx.setStrokeColor(color.withAlphaComponent(0.5).cgColor); ctx.move(to: CGPoint(x: judgment, y: 0)); ctx.addLine(to: CGPoint(x: judgment, y: layout.mainH)); ctx.strokePath()
      if let outcome { outcome.title.draw(at: CGPoint(x: max(3, a), y: layout.mainH - 20), withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: color]) }
    }
  }
  private func handle(_ point: CGPoint, ctx: CGContext) {
    ctx.setFillColor(accent.cgColor); ctx.fillEllipse(in: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
    ctx.setStrokeColor(canvas.cgColor); ctx.setLineWidth(1.5); ctx.strokeEllipse(in: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
  }
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    if bridge?.mode != .capture, let q = touches.first?.location(in: self) {
      // 后画的在上面：从后往前找，点到重叠的两条时开最上面那条。
      tapTarget = hotspots.last { $0.0.contains(q) }?.1; tapOrigin = q; return
    }
    guard let q = touches.first?.location(in: self), let draft, let state = chart?.state, let layout = chart?.chartLayout else { return }
    before = draft
    let a = state.view.x(Double(draft.range.start), plotW: layout.plotW), b = state.view.x(Double(draft.range.end), plotW: layout.plotW)
    let candidates: [(String, CGPoint)] = [("left", CGPoint(x: a, y: layout.mainH * 0.52)), ("right", CGPoint(x: b, y: layout.mainH * 0.52))]
    var handles = candidates
    if draft.rule.direction != .observe, let range = chart?.chartPriceRange {
      handles += [("target", CGPoint(x: layout.plotW - 18, y: max(18, min(layout.mainH - 42, yOf(draft.rule.target, pane: layout.main, range: range, mode: state.price.mode))))),
        ("invalid", CGPoint(x: layout.plotW - 18, y: max(18, min(layout.mainH - 42, yOf(draft.rule.invalidation, pane: layout.main, range: range, mode: state.price.mode))))),
        ("expiry", CGPoint(x: min(layout.plotW - 18, max(18, state.view.x(Double(draft.rule.expires), plotW: layout.plotW))), y: 34))]
    }
    dragPart = handles.filter { hypot($0.1.x - q.x, $0.1.y - q.y) <= 22 }.min { hypot($0.1.x - q.x, $0.1.y - q.y) < hypot($1.1.x - q.x, $1.1.y - q.y) }?.0 ?? "range"
    startIndex = state.series.index(atTime: state.view.t(atX: q.x, plotW: layout.plotW))
  }
  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let q = touches.first?.location(in: self) else { return }
    if bridge?.mode != .capture {
      if hypot(q.x - tapOrigin.x, q.y - tapOrigin.y) > 10 { tapTarget = nil }
      return
    }
    lastTouch = q
    drag(to: q)
    updateEdgeScroll()
  }
  /// 把正在拖的那一部分跟到手指 `q` 下面。手指移动和贴边滚动的每一帧都走这里。
  private func drag(to q: CGPoint) {
    guard var draft, let state = chart?.state, let layout = chart?.chartLayout else { return }
    let s = state.series, t = state.view.t(atX: max(0, min(layout.plotW, q.x)), plotW: layout.plotW)
    let index = s.index(atTime: t)
    if ["target", "invalid"].contains(dragPart), let range = chart?.chartPriceRange {
      let value = pOf(q.y, pane: layout.main, range: range, mode: state.price.mode)
      if dragPart == "target" { draft.rule.target = value; draft.rule.targetEdited = true }
      else { draft.rule.invalidation = value; draft.rule.invalidationEdited = true }
    } else if dragPart == "expiry" {
      draft.rule.expires = max(ReviewClock.now + 60_000, Int64(t)); draft.rule.expiryEdited = true
    } else {
      var left = s.index(atTime: Double(draft.range.start)), right = (0..<s.count).last(where: { s.time(at: $0) < draft.range.end }) ?? s.count - 1
      if dragPart == "left" { left = min(index, max(0, right - 2)) }
      else if dragPart == "right" { right = max(index, min(s.count - 1, left + 2)) }
      else { left = min(startIndex, index); right = max(startIndex, index); if right - left < 2 { right = min(s.count - 1, left + 2); left = max(0, right - 2) } }
      ReviewChartBridge.snap(&draft, left: left, right: right, series: s)
    }
    self.draft = draft; feature?.draft = draft; setNeedsDisplay()
  }
  /// 手指在离边 24pt 以内、拖的是选区（左手柄 / 右手柄 / 整段圈选）时开一条 displayLink；
  /// 出了那一圈、换成拖价格线或到期、或者松手，就停。
  private func updateEdgeScroll() {
    guard let layout = chart?.chartLayout, ["left", "right", "range"].contains(dragPart),
          lastTouch.x < Self.edgeZone || lastTouch.x > layout.plotW - Self.edgeZone else { stopEdgeScroll(); return }
    guard edgeLink == nil else { return }
    let link = CADisplayLink(target: self, selector: #selector(edgeTick(_:)))
    link.add(to: .main, forMode: .common)
    edgeLink = link
  }
  private func stopEdgeScroll() { edgeLink?.invalidate(); edgeLink = nil }
  /// 一帧挪多少：压得越深越快。刚进那一圈时每秒约 120pt（慢到能停在想要的那根上），
  /// 压到边上（或出了图）每秒约 900pt。按帧时长算，不按帧数算——120Hz 屏不会快一倍。
  @objc private func edgeTick(_ link: CADisplayLink) {
    guard let chart, let layout = chart.chartLayout, ["left", "right", "range"].contains(dragPart) else { stopEdgeScroll(); return }
    let zone = Self.edgeZone
    let depth: CGFloat
    if lastTouch.x < zone { depth = -min(1, (zone - lastTouch.x) / zone) }
    else if lastTouch.x > layout.plotW - zone { depth = min(1, (lastTouch.x - (layout.plotW - zone)) / zone) }
    else { stopEdgeScroll(); return }
    let dt = max(1.0 / 240, min(1.0 / 30, link.targetTimestamp - link.timestamp))
    let speed = 120 + 780 * abs(depth) * abs(depth)
    chart.nudge(byPx: Double(depth < 0 ? -speed : speed) * dt)
    drag(to: lastTouch)
  }
  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    if bridge?.mode != .capture {
      if let id = tapTarget { onOpenRecord(id) }
      tapTarget = nil; return
    }
    stopEdgeScroll(); feature?.saveDraft(); before = nil; dragPart = ""
  }
  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    tapTarget = nil; stopEdgeScroll()
    if let before { draft = before; feature?.draft = before }; self.before = nil; dragPart = ""; setNeedsDisplay()
  }
}
