import CoreGraphics
import Foundation
import KanpanCore
import UIKit

/// 成交量柱的颜色：和主图蜡烛同色，不压透明。
///
/// 原型 `app.js` 里是 `theme.volUp = up + '66'`（40% 透明），照抄过来之后量柱在白底上
/// 最深也只到 `#AEDAB3` / `#D38188`，整条副图发灰。2026-09-15 在同一个镜像窗口、同品种
/// 同周期（BTCUSDT·1h）下量过手机 AICoin 的量柱：最纯的一格红是 `#E64553`——正好是
/// 我们的 `down` 原值，绿是 `#3DB45C`，都没有掺底色；整条量柱带离白底的平均距离
/// AICoin 是 240.1，压了透明的我们只有 154.0。所以这里跟手机 AICoin 走，撤掉透明。
/// 柱与柱之间恒留缝靠的是 `candlePixels` 的宽度上限（见 `subVol`），不是靠透明度。
extension ChartColors {
  var volUp: Hex { up }
  var volDn: Hex { down }
}

/// 一帧的画法，1:1 移植自 `prototype/src/chart.js` 的 `paint()`。
///
/// 底图和十字线分两层，跟原型的 `bctx` / `octx` 对应：底图重画一次要遍历几百根 K 线，
/// 十字线跟手要 60fps，两者不能挤在一张画布上。
///
/// 算法一律走 `KanpanCore`（`priceRange` / `priceTicks` / `timeTicks` / `candleWidths`
/// / `IndicatorEngine`），这里只负责把数落到像素上。
public struct ChartRenderer {
  /// 临时客线不属于存档与个人布局。
  public var guestDrawings: [Drawing] = []
  public var ownDimmed = false
  public var state: ChartState { didSet { recalc(previous: oldValue) } }
  public private(set) var engine = IndicatorEngine()
  /// 平均 K 线的可见段。`kind == .candle` 时恒为 `nil`——默认路径一个数都不多算。
  public private(set) var heikin: HeikinSlice?

  /// 同一份 `state` 下算出来的几何。见 `GeometryCache`。
  private var geometry = GeometryCache()

  public init(state: ChartState) {
    self.state = state
    recalc()
  }

  private mutating func recalc(previous: ChartState? = nil) {
    // 换了 state 就换一只新盒子：旧的那只留给还拿着旧值的副本，谁也串不到谁。
    //
    // 唯一的例外是**几何输入一个没动**的那种变化（十字线跟手、倒计时走一格）：
    // 那只盒子里存的每一项对新旧两份 state 都同样正确（见 `sameGeometryInputs`），
    // 留着不清，手指跟手时才不会每帧把布局、价格区间、隐藏掩码原样重算一遍。
    //
    // 隔离仍然成立：一只盒子只会被「几何输入与它里面的结果一致」的 state 写入——
    // 每次写都发生在当前 state 下，而只有与前一份几何等价时才继承这只盒子，
    // 递推下去，同一只盒子的所有写入方几何输入全等，谁也串不到谁。
    if let old = previous, old.sameGeometryInputs(as: state) {
      // 几何照旧：指标、平均 K 线的那几步也一定不会走（下面的判据全是它的子集）。
      return
    }
    geometry = GeometryCache()
    ChartWorkCounter.bump(.geometryCache)
    let dataKey = state.symbol.symbol
    let seriesChanged = previous == nil || previous!.series != state.series
    let oiChanged = previous?.oi != state.oi || previous?.external != state.external
    let inputsChanged = seriesChanged || oiChanged || previous?.params != state.params
      || previous?.overlays != state.overlays || previous?.subs != state.subs
    // Same count does not imply same candles: REST can replace a stale snapshot,
    // and every live tick changes the last MA/MACD value.
    if let old = previous, seriesChanged || oiChanged {
      // 从前这儿是「符号 / 周期 / t0 / 根数 / openTime 全等 + 四列 `dropLast` 逐个比」，
      // 每个 tick 都是四趟 O(n)。`samePrefix` 先看前缀戳（`replaceLast` 会原样留着它），
      // 对不上才退回同一套逐列比，所以判定只会更严不会更松——它比老条件多比了
      // `open` 的前缀和 `step`，也就是「只有 open 的历史根被改了」这种情况
      // 从前会错误地走增量，现在会老老实实重建。
      // `isOneBarAfter`：新周期开盘（老的整条成了新的前缀）也走增量。从前这里只认
      // 「根数相同」，所以每根新 K 线一落地就把十几条指标从头算一遍——而引擎的
      // `updateTail` 本来就会处理追加（既有的 1000 轮随机逐位一致测试正是这么测的）。
      if old.series.samePrefix(as: state.series) || state.series.isOneBarAfter(old.series),
        old.oi == state.oi && old.external == state.external {
        engine.updateTail(series: state.series, external: state.indicatorInputs, dataKey: dataKey)
      } else {
        engine = IndicatorEngine()
      }
    }
    if inputsChanged { engine.ensure(
      series: state.series, wanted: state.overlays + state.subs,
      params: state.params, external: state.indicatorInputs, dataKey: dataKey) }
    if seriesChanged || previous?.view != state.view || previous?.options.kind != state.options.kind {
      heikin = HeikinSlice.make(state: state)
    }
  }

  /// Mask outputs without changing their slots, periods, colors or computational dependencies.
  ///
  /// 一帧里图例、叠加、副图、价格区间会各问一遍同一个指标，所以结果存一份；
  /// 被藏起来的那条线原本每次现开一条 n 长的 NaN 数组，现在整帧共用同一条。
  func displayed(_ id: IndicatorID) -> IndicatorResult? {
    if let hit = geometry.displayed[id] { return hit }
    let value = computeDisplayed(id)
    geometry.displayed[id] = value
    return value
  }

  private func computeDisplayed(_ id: IndicatorID) -> IndicatorResult? {
    guard var result = engine[id] else { return nil }
    let hidden = state.hiddenOutputs[id] ?? []
    guard !hidden.isEmpty else { return result }
    for k in result.lines.indices where hidden.contains(k) {
      result.lines[k] = blankLine(result.lines[k].count)
    }
    if hidden.contains(result.lines.count), let histogram = result.histogram {
      result.histogram = blankLine(histogram.count)
    }
    return result
  }

  /// 整帧共用的一条 NaN 线。数组是 COW，返回的是同一块内存，谁也不会去写它。
  private func blankLine(_ n: Int) -> [Double] {
    if let hit = geometry.blank, hit.count == n { return hit }
    ChartWorkCounter.bump(.hiddenMask)
    let value = [Double](repeating: .nan, count: n)
    geometry.blank = value
    return value
  }

  func indicatorColor(_ id: IndicatorID, _ index: Int) -> Hex {
    let palette = state.colors.palette
    return state.indicatorColors[id]?[index] ?? palette[(index + id.paletteOffset) % palette.count]
  }

  func outputVisible(_ id: IndicatorID, _ index: Int) -> Bool {
    !(state.hiddenOutputs[id]?.contains(index) ?? false)
  }

  func indicatorNumber(_ value: Double, decimals: Int = 2) -> String {
    guard value.isFinite else { return "--" }
    return state.options.compactValues ? fmtVol(value) : fmtNum(value, decimals)
  }

  // Adaptive mode reserves legend rows, never changes pane allocation.
  func mainLegendInset(plotW: Double) -> Double {
    if let hit = geometry.legendInset, hit.plotW == plotW { return hit.value }
    let value = computeMainLegendInset(plotW: plotW)
    geometry.legendInset = (plotW, value)
    return value
  }

  private func computeMainLegendInset(plotW: Double) -> Double {
    guard state.options.adaptiveIndicators else { return AICoinBehavior.mainTopInset }
    var x = 8.0, rows = 1.0
    for id in state.overlays {
      let names = id.lineNames(params: state.params[id] ?? id.defaultParams)
      for (k, name) in names.enumerated() where outputVisible(id, k) {
        let width = Double((name + " " + indicatorNumber(state.series.close.last ?? 0, decimals: state.decimals)).width(ChartFont.axis)) + 8
        if x + width > plotW - 4 { rows += 1; x = 8 }
        x += width
      }
    }
    return max(AICoinBehavior.mainTopInset, rows * 12 + 12)
  }

  // ---------------------------------------------------------------- 入口

  /// 一帧里被反复问到的那几样几何。
  ///
  /// `layout` / `priceRange` / `mainLegendInset` / `overlayLines` 在**同一份 state** 下
  /// 都是纯函数：同样的入参必然是同样的出参。可从前一帧要走一趟
  /// `drawPlot` → `drawLive` → `drawCross`，三层各自算一遍，加上 `priceRange`
  /// 内部还要回头再问两次 `layout`，一帧下来 core 的价格扫描跑 ≥8 次、`layout` ≥10 次——
  /// 算的全是同一个数。
  ///
  /// 所以挂一只引用型备忘录：`ChartRenderer` 仍是值类型，但每次 `recalc`（也就是
  /// 每次 `state` 变）都换一只新盒子，旧盒子跟着旧副本走，不会把上一份 state 的
  /// 结果串到新的上面来。**这里存的是计算结果本身，不是近似或简化，像素一个不差。**
  private final class GeometryCache {
    var layout: (size: CGSize, value: Layout)?
    var legendInset: (plotW: Double, value: Double)?
    var overlayLines: [[Double]]?
    var displayed: [IndicatorID: IndicatorResult?] = [:]
    /// 被藏起来的输出统一指向的那条 NaN 线。
    var blank: [Double]?
    /// 手势探针会拿别的 `view` / `transform` 来问（`panPrice` 的自动区间、回弹预演），
    /// 所以这里按入参存几条。条数极少（常见 1～2 条），线性找比哈希还快。
    var ranges: [(size: CGSize, view: ViewWindow, transform: PriceTransform, value: PriceRange)] = []
  }

  public func layout(size: CGSize) -> Layout {
    if let hit = geometry.layout, hit.size == size { return hit.value }
    let value = computeLayout(size: size)
    geometry.layout = (size, value)
    return value
  }

  private func computeLayout(size: CGSize) -> Layout {
    ChartWorkCounter.bump(.layout)
    let mainWeight = ChartContentLayout.mainWeight(height: Double(size.height), control: state.options.portraitHeight, count: state.subs.count)
    let initial = Layout(width: Double(size.width), height: Double(size.height), subs: state.subs, subScale: state.subScale, mainWeight: mainWeight)
    // Height changes must not alter plot width/time mapping through padded-range label sizes.
    let range = KanpanCore.priceRange(view: state.view, series: state.series, overlayValues: overlayLines(), transform: state.price, paneHeight: 300)
    var labels = [range.lo, range.hi].map { axisLabel($0, range: range) }
    for pane in initial.panes.dropFirst() {
      if let id = pane.indicator { labels += subAxisLabels(id) }
    }
    // 轴宽 = 这一屏最宽的那条刻度 + 两侧各 `axisLabelPadding`。从前是「50pt 起跳、
    // 不够再按 8pt 一档往上加」，于是三位数的价位两边各空一大截，用户看到的就是
    // 「右边这条太宽了」。位数多的品种自然宽、少的自然窄，不给「以后可能更长」留地方。
    var measured = labels.map { Double(axisWidthTemplate($0).width(ChartFont.axis)) }.max() ?? 0
    // 倒计时也是这一格里的内容：它挂在最新价胶囊底下，`23:59:59` 比五位数的价还长。
    // 开着就一并量进来（按周期能出现的最长写法，不读当前时刻——时刻一变轴就得重排，
    // 那才是真的抖），关着（出厂默认）一个像素都不占。
    if let stamp = countdownTemplate() {
      measured = max(measured, Double(axisWidthTemplate(stamp).width(ChartFont.tiny))
        + 2 * (AICoinBehavior.axisChipInset + AICoinBehavior.axisChipPadding)
        - 2 * AICoinBehavior.axisLabelPadding)
    }
    let width = max(AICoinBehavior.axisMinWidth,
                    measured.rounded(.up) + 2 * AICoinBehavior.axisLabelPadding)
    return Layout(width: Double(size.width), height: Double(size.height), subs: state.subs, subScale: state.subScale, mainWeight: mainWeight,
                  axisWidth: min(max(AICoinBehavior.axisMinWidth, Double(size.width) / 3), width))
  }

  /// 量轴宽时先把数字一律换成 `0`。
  ///
  /// 右轴用的是**等宽数字**字体（`ChartFont.axis`），`1` 和 `8` 本来就一样宽，
  /// 这一步是把「轴宽只跟字串的形状（几位数、有没有小数点 / 负号 / K M B）有关」
  /// 这件事写死：最新价每跳一下都不会让整条轴挪一个像素，只有位数真的多一位
  /// （9999 → 10000）才走一个字符的台阶。
  ///
  /// 为什么不用「同品种同周期内只增不减」那种记忆式防抖：`ChartRenderer` 是纯值类型，
  /// 同一份 state 必须画出同一张图（A3.11 的逐像素基线全靠这条），跨帧的闩锁会把
  /// 「这一帧画在哪个轴宽上」变成看不见的历史。台阶式量化没有这个副作用。
  func axisWidthTemplate(_ s: String) -> String {
    String(s.map { $0.isASCII && $0.isNumber ? "0" : $0 })
  }

  /// 右轴上那一格胶囊的横向几何（最新价、十字线读数、倒计时共用）。
  ///
  /// 左右各留 `axisChipInset`，文字两侧各留 `axisChipPadding`，最宽不超过轴宽减掉
  /// 两边的留白——轴宽本身就是按最宽的刻度量出来的，所以最长的那条读数正好填满一格，
  /// 既不会被裁掉，也不会探出右缘。
  func axisChip(_ L: Layout, text: String, font: UIFont = ChartFont.axis,
                minWidth: Double = 0) -> (x: Double, w: Double) {
    let inset = AICoinBehavior.axisChipInset
    let room = max(4, L.axisW - 2 * inset)
    let wanted = Double(text.width(font)).rounded(.up) + 2 * AICoinBehavior.axisChipPadding
    return (L.plotW + inset, min(room, max(minWidth, wanted)))
  }

  /// 拖动期间钉住的主图价格区间（`ChartView.beginAxisFreeze`）。
  ///
  /// 为什么不放进 `ChartState`：它是**交互中间量**，和选中态、预览线是一类东西——
  /// `ChartState` 是渲染的纯输入，A3.11 的 176 张逐像素基线钉死了「同一份 state →
  /// 同一张图」，把一个只在手指按着的那两秒里存在的值塞进去就等于改渲染路径。
  /// 它只盖住「这一帧画在哪个价格区间上」这一件事，谁都不必知道它存在。
  var pinnedPriceRange: PriceRange?

  /// 主图价格区间。手势层要用同一份，所以露出来。
  public func priceRange(size: CGSize) -> PriceRange {
    // 钉住的时候一律给钉住的那份：画线、十字线读数、蜡烛定标走的都是这一个入口，
    // 少一处就会出现「图没动、线动了」。
    if let pinnedPriceRange { return pinnedPriceRange }
    return priceRange(size: size, transform: state.price)
  }

  /// Probe a normalized Y state without invalidating indicator caches.
  public func priceRange(size: CGSize, transform: PriceTransform) -> PriceRange {
    priceRange(size: size, view: state.view, transform: transform)
  }

  /// Probe another visible range using the same geometry and indicators.
  public func priceRange(size: CGSize, view: ViewWindow, transform: PriceTransform) -> PriceRange {
    for hit in geometry.ranges where hit.size == size && hit.view == view && hit.transform == transform {
      return hit.value
    }
    // 从前这儿是 `paneHeight: layout(size:).main.h, topInset: ...layout(size:).plotW`，
    // 一次调用把 `layout` 算两遍。算一次，两处都用它。
    ChartWorkCounter.bump(.priceRange)
    let L = layout(size: size)
    let value = KanpanCore.priceRange(
      view: view, series: state.series, overlayValues: overlayLines(),
      // 画线关掉了就别再让它撑价格区间：一条看不见的线把蜡烛压扁，用户只会觉得图坏了。
      drawingPrices: [],
      transform: transform,
      extraPrices: heikin?.extremes ?? [], bias: state.options.bias,
      paneHeight: L.main.h, topInset: mainLegendInset(plotW: L.plotW), anchorPrice: transform.isManual ? state.axisScaleAnchor : nil)
    if geometry.ranges.count >= 8 { geometry.ranges.removeFirst() }
    geometry.ranges.append((size, view, transform, value))
    return value
  }

  /// 底图：背景、网格、K 线、叠加、画线、最新价、副图、时间轴、图例。
  ///
  /// `live == false` 时跳过最新价——`ChartView` 把最新价放在单独一层（§5.7），
  /// 由 `drawPlot` / `drawLive` 分别调进来。
  /// `legend == false` 时跳过主图图例与副图图例——`ChartView` 把图例放在 `crossLayer`
  /// （§5.7 的「读数」），因为图例读的是 `legendIndex`，十字线一动它就得跟着变。
  public func draw(
    in ctx: CGContext, size: CGSize, scale: CGFloat, live: Bool = true, legend: Bool = true
  ) {
    guard !state.series.isEmpty else { return }
    let L = layout(size: size)
    let r = priceRange(size: size)
    let t = state.colors
    let s = Double(scale)

    UIGraphicsPushContext(ctx)
    defer { UIGraphicsPopContext() }

    ctx.clear(CGRect(origin: .zero, size: size))
    ctx.setFillColor(Paint.cg(t.bg))
    ctx.fill(CGRect(origin: .zero, size: size))

    let main = L.main
    drawPriceGrid(ctx, pane: main, r: r, L: L, scale: s)
    drawTimeGrid(ctx, L: L, scale: s)
    drawCandles(ctx, pane: main, r: r, L: L, scale: s)
    drawExtrema(ctx, r: r, L: L, scale: s)
    drawOverlays(ctx, pane: main, r: r, L: L, scale: s)
    drawDrawings(ctx, pane: main, r: r, L: L, scale: s)
    if live { drawDepth(ctx, pane: main, range: r, L: L) }
    if live { drawLastPrice(ctx, pane: main, r: r, L: L, scale: s) }
    for k in 1..<L.panes.count {
      drawSub(ctx, pane: L.panes[k], L: L, scale: s, legend: legend)
    }
    drawTimeAxis(ctx, L: L, scale: s)
    if legend { drawLegend(ctx, pane: main, L: L) }
  }

  /// 十字线层（原型 `paintOver`）。M3 只按 `state.crosshair` 静态摆放。
  /// 十字线与三处读数。**不负责清屏**——它画在 `crossLayer` 上，由调用方先把那层清空
  /// （图例也画在同一层，先画图例再画十字线，和原型的 `base`/`over` 叠放顺序一致）。
  /// One geometry source for drawing and the crosshair's touch target.
  public func crosshairCenter(size: CGSize) -> CGPoint? {
    guard !state.series.isEmpty, let cross = state.crosshair else { return nil }
    let L = layout(size: size), r = priceRange(size: size), b = state.series
    let i = min(max(0, cross.index), b.count - 1)
    let pane = cross.pane.flatMap { id in L.panes.first { $0.indicator == id } } ?? L.main
    let rawY = cross.pane != nil ? subCrosshairY(value: cross.price ?? 0, pane: pane)
      : yOf(cross.price ?? b.close[i], pane, r)
    return CGPoint(x: x(b.time(at: i), L), y: min(pane.y + pane.h - 7, max(pane.y + 7, rawY)))
  }

  public func drawOverlay(in ctx: CGContext, size: CGSize, scale: CGFloat) {
    guard !state.series.isEmpty, let cross = state.crosshair else { return }
    let L = layout(size: size)
    let r = priceRange(size: size)
    let t = state.colors
    let s = Double(scale)
    let b = state.series
    let i = min(max(0, cross.index), b.count - 1)
    let pane = cross.pane.flatMap { id in L.panes.first { $0.indicator == id } } ?? L.main

    UIGraphicsPushContext(ctx)
    defer { UIGraphicsPopContext() }

    guard let center = crosshairCenter(size: size) else { return }
    let xc = Double(center.x), y = Double(center.y)

    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: 0, width: L.plotW, height: L.H))
    ctx.setLineDash(phase: 0, lengths: [3 / s, 3 / s])
    ctx.setStrokeColor(Paint.cg(t.cross))
    ctx.setLineWidth(1 / s)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: hairline(xc, scale: s), y: 0))
    ctx.addLine(to: CGPoint(x: hairline(xc, scale: s), y: L.H))
    ctx.strokePath()
    ctx.beginPath()
    ctx.move(to: CGPoint(x: 0, y: hairline(y, scale: s)))
    ctx.addLine(to: CGPoint(x: L.plotW, y: hairline(y, scale: s)))
    ctx.strokePath()
    ctx.restoreGState()

    // 右轴价格
    if y <= pane.y + pane.h {
      let p = cross.pane == nil ? pOf(y, pane, r) : cross.price ?? 0
      let label: String
      if let key = cross.pane { label = subValueText(p, indicator: key) }
      else if state.price.mode == .percent { label = toFixed((p / r.base - 1) * 100, 2) + "%" }
      else { label = fmtNum(p, state.decimals) }
      let chip = axisChip(L, text: label)
      ctx.setFillColor(Paint.cg(t.crossBg))
      ctx.addRoundRect(CGRect(x: chip.x, y: y - 7.5, width: chip.w, height: 15), radius: 3)
      ctx.fillPath()
      label.drawCentered(at: CGPoint(x: chip.x + chip.w / 2, y: y), font: ChartFont.axis, color: t.crossInk)
    }

    drawCandleData(ctx, L: L, index: i, selectedX: xc)

    // 下轴时间
    let tl = fmtFull(ms: Double(b.time(at: i)), offsetMinutes: state.timezone.offsetMinutes)
    let tw = Double(tl.width(ChartFont.axis)) + 12
    let tx = max(2, min(L.plotW - tw - 2, xc - tw / 2))
    ctx.setFillColor(Paint.cg(t.crossBg))
    ctx.addRoundRect(
      CGRect(x: tx, y: L.timeY + 3, width: tw, height: AICoinBehavior.timeHeight - 6), radius: 3)
    ctx.fillPath()
    tl.drawCentered(
      at: CGPoint(x: tx + tw / 2, y: L.timeY + AICoinBehavior.timeHeight / 2),
      font: ChartFont.axis, color: t.crossInk)
  }

  // ---------------------------------------------------------------- 坐标

  private func x(_ t: Int64, plotW: Double) -> Double { state.view.x(Double(t), plotW: plotW) }
  private func x(_ t: Int64, _ L: Layout) -> Double { x(t, plotW: L.plotW) }
  private func yOf(_ p: Double, _ pane: Pane, _ r: PriceRange) -> Double {
    KanpanCore.yOf(p, pane: pane, range: r, mode: state.price.mode)
  }
  private func pOf(_ y: Double, _ pane: Pane, _ r: PriceRange) -> Double {
    KanpanCore.pOf(y, pane: pane, range: r, mode: state.price.mode)
  }
  private var visible: (lo: Int, hi: Int) { visibleRange(view: state.view, series: state.series) }

  /// 进价格区间的那几条叠加线：MA / EMA 全部，BOLL 只要上下轨（原型 `priceRange`）。
  ///
  /// 只跟 `state.overlays` / `hiddenOutputs` 与 `engine` 有关，同一份 state 下恒定；
  /// `layout` 与每次 `priceRange` 都要，所以存一份（数组是 COW，存的是引用不是拷贝）。
  private func overlayLines() -> [[Double]] {
    if let hit = geometry.overlayLines { return hit }
    let value = computeOverlayLines()
    geometry.overlayLines = value
    return value
  }

  private func computeOverlayLines() -> [[Double]] {
    var out: [[Double]] = []
    for id in state.overlays {
      guard let v = displayed(id) else { continue }
      switch id {
      // 超级趋势与抛物线转向都贴着价格走，偶尔会甩到可见蜡烛之外；它们要进自适应，
      // 不然翻向那一段直接画到画布外面去了。
      case .ma, .ema, .vwap, .supertrend, .sar: out += v.lines
      case .boll: if v.lines.count >= 3 { out += [v.lines[1], v.lines[2]] }
      default: break
      }
    }
    return out
  }

  // ---------------------------------------------------------------- 价格网格

  private func drawPriceGrid(_ ctx: CGContext, pane: Pane, r: PriceRange, L: Layout, scale s: Double) {
    let t = state.colors
    let mode = state.price.mode
    let a = mode.forward(r.lo, base: r.base), z = mode.forward(r.hi, base: r.base)
    ctx.setLineWidth(1 / s)
    let gm = state.effectiveGrid
    for f in priceTicks(range: r, mode: mode, paneH: pane.h) {
      let fraction = (f - a) / (z - a)
      let y = pane.y + (r.inverted ? fraction : 1 - fraction) * pane.h
      if y < pane.y + 6 || y > pane.y + pane.h - 2 { continue }
      if gm != .none {
        let x0 = gm == .tick ? L.plotW - 22 : 0
        ctx.hairLine(from: x0, to: L.plotW, y: y, scale: CGFloat(s), color: Paint.cg(t.grid))
      }
      let label: String
      switch mode {
      case .percent: label = (f >= 0 ? "+" : "") + toFixed(f, 1) + "%"
      case .log: label = fmtNum(exp(f), state.decimals)
      case .linear: label = fmtNum(f, state.decimals)
      }
      label.drawCentered(at: CGPoint(x: L.plotW + L.axisW / 2, y: y), font: ChartFont.axis, color: t.dim)
    }
    ctx.hairLineV(x: L.plotW, from: 0, to: L.H, scale: CGFloat(s), color: Paint.cg(t.axis))
    drawAutoFitButton(ctx, L: L, scale: s)
  }

  /// The A badge resets only Y auto scaling; the iPhone's separate round control opens a side panel.
  private func drawAutoFitButton(_ ctx: CGContext, L: Layout, scale s: Double) {
    guard state.price.isManual else { return }
    let b = L.autoFitButton
    let rect = CGRect(x: b.x, y: b.y, width: b.w, height: b.h)
    ctx.setFillColor(Paint.cg(state.colors.axis))
    ctx.addRoundRect(rect, radius: 2)
    ctx.fillPath()
    "A".drawCentered(at: CGPoint(x: rect.midX, y: rect.midY),
                     font: ChartFont.axis, color: state.colors.text)
  }

  // ---------------------------------------------------------------- 时间轴

  private func ticks(_ L: Layout) -> [(t: Double, step: Int64)] {
    timeTicks(view: state.view, plotW: L.plotW, offsetMinutes: state.timezone.offsetMinutes)
  }

  private func drawTimeGrid(_ ctx: CGContext, L: Layout, scale s: Double) {
    guard state.effectiveGrid == .both else { return }
    let color = Paint.cg(state.colors.grid)
    for k in ticks(L) {
      let xx = state.view.x(k.t, plotW: L.plotW)
      if xx < 0 || xx > L.plotW { continue }
      ctx.hairLineV(x: xx, from: 0, to: L.timeY, scale: CGFloat(s), color: color)
    }
  }

  private func drawTimeAxis(_ ctx: CGContext, L: Layout, scale s: Double) {
    let t = state.colors
    ctx.hairLine(from: 0, to: L.W, y: L.timeY, scale: CGFloat(s), color: Paint.cg(t.axis))
    let off = state.timezone.offsetMinutes
    for k in ticks(L) {
      let xx = state.view.x(k.t, plotW: L.plotW)
      if xx < 18 || xx > L.plotW - 18 { continue }
      fmtTick(ms: k.t, step: Double(k.step), offsetMinutes: off)
        .drawCentered(
          at: CGPoint(x: xx, y: L.timeY + AICoinBehavior.timeHeight / 2),
          font: ChartFont.axis, color: t.dim)
    }
  }

  private func drawExtrema(_ ctx: CGContext, r: PriceRange, L: Layout, scale: Double) {
    let b = state.series
    let bounds = visibleRange(view: state.view, series: b)
    let visible = (bounds.lo...bounds.hi).filter {
      let px = x(b.time(at: $0), L); return px >= 0 && px <= L.plotW
    }
    guard let high = visible.max(by: { b.high[$0] < b.high[$1] }),
          let low = visible.min(by: { b.low[$0] < b.low[$1] }) else { return }
    // 主图顶上那几行是图例的地盘（`mainLegendInset`，副图的图例也照这个数收边）。
    // 上界原来写死 8，于是最高价那颗标注直接压在「MA256 78125.45」那行字上——
    // 两层小字叠在一起谁也读不出来。标注以 `ty` 为纵向**中心**，所以下界是
    // 「图例占掉的高度 + 半行字」，图例行本身一个像素都不挪。
    let legendBand = mainLegendInset(plotW: L.plotW)
    let floor = legendBand + Double(ChartFont.measure("0", ChartFont.axis).height) / 2 + 2
    for (index, price, isHigh) in [(high, b.high[high], true), (low, b.low[low], false)] {
      let px = x(b.time(at: index), L), py = yOf(price, L.main, r)
      let label = fmtNum(price, state.decimals), width = Double(label.width(ChartFont.axis))
      let left = px + 16 + width > L.plotW - 4
      let tx = max(4, min(L.plotW - width - 4, left ? px - width - 12 : px + 12))
      let above = isHigh != r.inverted
      let ty = max(floor, min(L.mainH - 8, py + (above ? -10 : 10)))
      // 引线同理：起点落在图例那几行里时只画跨出图例之后的那一截，
      // 不让一根斜线横穿读数。
      let ax = left ? tx + width + 3 : tx - 3
      var from = CGPoint(x: px, y: py)
      if py < legendBand, ty > py {
        let k = (legendBand - py) / (ty - py)
        from = CGPoint(x: px + (ax - px) * k, y: legendBand)
      }
      ctx.setStrokeColor(Paint.cg(state.colors.text)); ctx.setLineWidth(1 / scale)
      ctx.beginPath(); ctx.move(to: from)
      ctx.addLine(to: CGPoint(x: ax, y: ty)); ctx.strokePath()
      label.drawLeft(at: CGPoint(x: tx, y: ty), font: ChartFont.axis, color: state.colors.text)
    }
  }

  // ---------------------------------------------------------------- K 线

  /// 蜡烛。
  ///
  /// **和原型的分歧：x 和 y 两个方向都对齐到设备像素**（原型只对齐 x）。影线长、实体高的
  /// 时候只有首尾两行发虚看不出来；捏小之后一根影线只剩 3~5 个像素高、实体 1~3 个像素，
  /// 发虚的那两行占了大半——用户实机看到的「模糊不清、挤在一起」就是这个。
  ///
  /// 上下边**各自** `snap`，不要 snap 一个再加高度：后者会让另一条边又掉回像素中间。
  private func drawCandles(_ ctx: CGContext, pane: Pane, r: PriceRange, L: Layout, scale s: Double) {
    let b = state.series, t = state.colors, S = state.style
    let shape = state.effectiveShape
    let ha = heikin
    let (lo, hi) = visible
    let spacing = state.view.barSpacing(step: b.step, plotW: L.plotW)
    let m = candleMetrics(spacing: spacing, style: S, scale: s)
    let lw = m.outline
    let hollowShape = shape == .outline || shape == .hollowUp
    // 影线兑淡（`wickTint`）是给「大实体配粗影线」准备的：墩 0.7 / 砖 0.45 / 辉 0.6，
    // 让影线往背景退半步，实体才压得住。可蜡烛一捏小，这份退让就只剩「影线看不见」——
    // 用户实机反馈的「颜色都好像变淡了，像模糊不清，特别是影线」就是这一段。
    //
    // AiCoin 的做法是**根本不兑**：1920×975 原生截图实测，影线与实体完全同色
    // （#CF3E3E / #26A380，491 个影线样本无一偏离，见 docs/acceptance/M8/aicoin-对比.md §2.3）。
    // 风格表是定版规格不动，改的是兑淡的**生效区间**：实体粗到 8 个设备像素以上照旧按
    // 风格兑，从 8 掉到 2 的过程里线性收回满饱和，2 以下完全不兑。
    //
    // 从前这儿是 `bodyW*s <= 2 ? 1 : wickTint` 一个硬台阶——门槛太低（一屏一百多根时
    // 实体还有 3~6 个像素，照兑不误），而且跨过去的那一帧颜色会跳一下。
    let tintFade = min(1, max(0, (m.bodyW * s - 2) / 6))
    let tint = S.wickTint + (1 - S.wickTint) * (1 - tintFade)
    // 圆头帽在 ≤2 个设备像素时只贡献两坨抗锯齿，不贡献造型，那就别用。
    let roundCap = S.wickCap == .round && m.wickW * s >= 3
    let minBodyH = max(m.wickW, snap(m.minBody, scale: s))

    ctx.saveGState()
    ctx.beginPath()
    ctx.addRect(CGRect(x: 0, y: pane.y, width: L.plotW, height: pane.h))
    ctx.clip()
    ctx.setLineCap(roundCap ? .round : .butt)
    // 整帧不变的四种颜色：涨/跌的实体色、以及按 `tint` 兑淡后的影线色。
    // 从前 `Paint.mix` 和 `Paint.cg` 都写在逐根循环里——一屏两百根就是两百次
    // `String(format:)` 拼十六进制加两百次加锁查表，算出来的还都是同两个值。
    // 这里提到循环外算一次，混色公式、入参、位数一个没动，像素完全一致。
    let map = PriceMapping(range: r, mode: state.price.mode)
    let cgBg = Paint.cg(t.bg)
    let cgUp = Paint.cg(t.up), cgDown = Paint.cg(t.down)
    let cgWickUp = tint < 1 ? Paint.cg(Paint.mix(t.bg, t.up, tint)) : cgUp
    let cgWickDown = tint < 1 ? Paint.cg(Paint.mix(t.bg, t.down, tint)) : cgDown
    let rendering = AICoinBehavior.rendering(spacing: spacing, scale: s)
    if rendering == .closeLine {
      line(ctx, pane: pane, r: r, plotW: L.plotW, arr: b.close,
           color: t.up, lo: lo, hi: hi, width: 2 / s)
      ctx.restoreGState()
      return
    }

    for i in lo...hi {
      let xc = x(b.time(at: i), L)
      if xc < -4 || xc > L.plotW + 4 { continue }
      // 平均 K 线只换这四个数，别处（最新价、指标、读数）一律还是真实价。
      let bar = ha?.bar(i) ?? (o: b.open[i], h: b.high[i], l: b.low[i], c: b.close[i])
      let up = bar.c >= bar.o
      let col = up ? cgUp : cgDown
      let wick = up ? cgWickUp : cgWickDown
      let highY = map.y(bar.h, pane: pane), lowY = map.y(bar.l, pane: pane)
      let yh = snap(min(highY, lowY), scale: s), yl = snap(max(highY, lowY), scale: s)

      // 影线：可以比实体淡，端头可以是圆的
      if roundCap && !m.thin {
        ctx.setStrokeColor(wick)
        ctx.setLineWidth(m.wickW)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: hairline(xc, scale: s), y: yh + m.wickW / 2))
        ctx.addLine(to: CGPoint(x: hairline(xc, scale: s), y: yl - m.wickW / 2))
        ctx.strokePath()
      } else {
        ctx.setFillColor(wick)
        let xw = snap(xc - m.wickW / 2, scale: s)
        ctx.fill(CGRect(x: xw, y: yh, width: m.wickW, height: max(m.wickW, yl - yh)))
      }
      if rendering == .highLow { continue }

      let yo = map.y(bar.o, pane: pane), yc = map.y(bar.c, pane: pane)
      let top = snap(min(yo, yc), scale: s)
      let h = max(minBodyH, snap(max(yo, yc), scale: s) - top)
      let xb = snap(xc - m.bodyW / 2, scale: s)
      let drawHollow = shape == .outline || (shape == .hollowUp && up)
      let rect = CGRect(x: xb, y: top, width: m.bodyW, height: h)

      if hollowShape && drawHollow && h > lw * 2.2 && m.bodyW > lw * 2.2 {
        // 描边实体：先用底色挖空，K 线之间才不会互相糊住
        ctx.setLineWidth(lw)
        if m.radius > 0 {
          ctx.addRoundRect(rect, radius: m.radius)
          ctx.setFillColor(cgBg)
          ctx.setStrokeColor(col)
          ctx.drawPath(using: .fillStroke)
        } else {
          ctx.setFillColor(cgBg)
          ctx.fill(rect)
          ctx.setStrokeColor(col)
          ctx.stroke(rect.insetBy(dx: lw / 2, dy: lw / 2), width: lw)
        }
      } else if m.radius > 0 && h > m.radius * 2 {
        ctx.setFillColor(col)
        ctx.addRoundRect(rect, radius: m.radius)
        ctx.fillPath()
      } else {
        ctx.setFillColor(col)
        ctx.fill(rect)
      }
    }
    ctx.setLineCap(.butt)
    ctx.restoreGState()
  }

  // ---------------------------------------------------------------- 叠加

  /// 把一条指标线画进 pane；`NaN` 断线不连（原型 `line()`）。
  private func line(
    _ ctx: CGContext, pane: Pane, r: PriceRange, plotW: Double, arr: [Double], color: Hex,
    lo: Int, hi: Int, width: Double = 1
  ) {
    let b = state.series
    ctx.setStrokeColor(Paint.cg(color))
    ctx.setLineWidth(width)
    ctx.setLineJoin(.round)
    ctx.beginPath()
    // 区间固定，`a`/`z` 只算一次；逐点还是原来那套算式（见 `PriceMapping`）。
    let map = PriceMapping(range: r, mode: state.price.mode)
    var on = false
    for i in lo...hi where i < arr.count {
      let v = arr[i]
      if !v.isFinite { on = false; continue }
      let px = x(b.time(at: i), plotW: plotW)
      let py = map.y(v, pane: pane)
      if on { ctx.addLine(to: CGPoint(x: px, y: py)) } else { ctx.move(to: CGPoint(x: px, y: py)); on = true }
    }
    ctx.strokePath()
  }

  /// 按多空分段上色的一条线（超级趋势）。
  ///
  /// 不能一笔 `strokePath` 拉完：翻向那一根的前后两点分属两种颜色，连起来会在图上
  /// 拖出一条横跨蜡烛的斜线，而超级趋势在翻向处本来就是**跳**过去的，中间没有值。
  /// 所以逐段走，方向一变就收笔，留下的那道缺口正是翻向点。
  private func directedLine(
    _ ctx: CGContext, pane: Pane, r: PriceRange, plotW: Double, arr: [Double], dir: [Double],
    lo: Int, hi: Int, width: Double = 1.5
  ) {
    let b = state.series, t = state.colors
    let map = PriceMapping(range: r, mode: state.price.mode)
    ctx.setLineWidth(width)
    ctx.setLineJoin(.round)
    var i = lo
    while i <= hi {
      guard i < arr.count, i < dir.count, arr[i].isFinite, dir[i].isFinite, dir[i] != 0 else {
        i += 1
        continue
      }
      let rising = dir[i] > 0
      ctx.setStrokeColor(Paint.cg(rising ? t.up : t.down))
      ctx.beginPath()
      var on = false
      while i <= hi, i < arr.count {
        let v = arr[i]
        let d = i < dir.count ? dir[i] : .nan
        if !v.isFinite || !d.isFinite || d == 0 || (d > 0) != rising { break }
        let px = x(b.time(at: i), plotW: plotW)
        let py = map.y(v, pane: pane)
        if on {
          ctx.addLine(to: CGPoint(x: px, y: py))
        } else {
          ctx.move(to: CGPoint(x: px, y: py))
          on = true
        }
        i += 1
      }
      ctx.strokePath()
    }
  }

  /// 一根一个点（抛物线转向）。相邻两点之间没有「中间值」，连成线是错的。
  private func dots(
    _ ctx: CGContext, pane: Pane, r: PriceRange, L: Layout, arr: [Double], dir: [Double],
    lo: Int, hi: Int, scale s: Double
  ) {
    let b = state.series, t = state.colors
    let map = PriceMapping(range: r, mode: state.price.mode)
    let spacing = state.view.barSpacing(step: b.step, plotW: L.plotW)
    // 点子跟着蜡烛疏密走，但不许小到看不见，也不许大到连成一条带。
    let size = max(1.5, min(3.5, spacing * 0.3))
    var rising: [CGRect] = [], falling: [CGRect] = []
    for i in lo...hi where i < arr.count {
      guard arr[i].isFinite, i < dir.count, dir[i].isFinite, dir[i] != 0 else { continue }
      let rect = CGRect(
        x: x(b.time(at: i), plotW: L.plotW) - size / 2,
        y: map.y(arr[i], pane: pane) - size / 2, width: size, height: size)
      if dir[i] > 0 { rising.append(rect) } else { falling.append(rect) }
    }
    // 两批一次性填完，而不是每根点一次 `setFillColor`：一屏几百根就是几百次状态切换。
    for (rects, color) in [(rising, t.up), (falling, t.down)] where !rects.isEmpty {
      ctx.setFillColor(Paint.cg(color))
      ctx.beginPath()
      for rect in rects { ctx.addEllipse(in: rect) }
      ctx.fillPath()
    }
  }

  private func drawOverlays(_ ctx: CGContext, pane: Pane, r: PriceRange, L: Layout, scale s: Double) {
    let t = state.colors
    let (lo, hi) = visible
    ctx.saveGState()
    ctx.beginPath()
    ctx.addRect(CGRect(x: 0, y: pane.y, width: L.plotW, height: pane.h))
    ctx.clip()
    for id in state.overlays {
      guard let v = displayed(id) else { continue }
      switch id {
      case .ma:
        for (k, a) in v.lines.enumerated() {
          line(ctx, pane: pane, r: r, plotW: L.plotW, arr: a, color: indicatorColor(id, k), lo: lo, hi: hi)
        }
      case .ema:
        for (k, a) in v.lines.enumerated() {
          line(ctx, pane: pane, r: r, plotW: L.plotW, arr: a, color: indicatorColor(id, k), lo: lo, hi: hi)
        }
      case .boll:
        guard v.lines.count >= 3 else { break }
        line(ctx, pane: pane, r: r, plotW: L.plotW, arr: v.lines[1], color: t.band, lo: lo, hi: hi)
        line(ctx, pane: pane, r: r, plotW: L.plotW, arr: v.lines[0], color: t.amber, lo: lo, hi: hi)
        line(ctx, pane: pane, r: r, plotW: L.plotW, arr: v.lines[2], color: t.band, lo: lo, hi: hi)
      case .vwap:
        guard let a = v.lines.first else { break }
        line(ctx, pane: pane, r: r, plotW: L.plotW, arr: a, color: indicatorColor(id, 0), lo: lo, hi: hi)
      case .supertrend:
        guard let a = v.lines.first else { break }
        directedLine(
          ctx, pane: pane, r: r, plotW: L.plotW, arr: a, dir: v.dir ?? [], lo: lo, hi: hi)
      case .sar:
        guard let a = v.lines.first else { break }
        dots(ctx, pane: pane, r: r, L: L, arr: a, dir: v.dir ?? [], lo: lo, hi: hi, scale: s)
      default: break
      }
    }
    ctx.restoreGState()
  }

  // ---------------------------------------------------------------- 最新价

  func drawLastPrice(_ ctx: CGContext, pane: Pane, r: PriceRange, L: Layout, scale s: Double) {
    // 关掉实时价格线：那条横线和右轴胶囊一起没有，挂在胶囊底下的倒计时自然也没有。
    guard state.options.lastLine else { return }
    let b = state.series, t = state.colors
    let i = b.count - 1
    let p = b.close[i]
    let y = max(pane.y + 8, min(pane.y + pane.h - 8, yOf(p, pane, r)))
    let up = b.close[i] >= b.open[i]
    let col = up ? t.up : t.down

    ctx.saveGState()
    ctx.setLineDash(phase: 0, lengths: [3, 2])
    ctx.setStrokeColor(Paint.cg(col)); ctx.setLineWidth(2 / s)
    ctx.beginPath(); ctx.move(to: CGPoint(x: 0, y: snap(y, scale: s)))
    ctx.addLine(to: CGPoint(x: L.plotW, y: snap(y, scale: s))); ctx.strokePath()
    ctx.restoreGState()

    let label = axisLabel(p, range: r)
    let chip = axisChip(L, text: label)
    let h = 15.0
    ctx.setFillColor(Paint.cg(col))
    ctx.addRoundRect(CGRect(x: chip.x, y: y - h / 2, width: chip.w, height: h), radius: 3)
    ctx.fillPath()
    label.drawCentered(at: CGPoint(x: chip.x + chip.w / 2, y: y), font: ChartFont.axis, color: t.chip)
    drawCountdown(ctx, L: L, belowY: y + h / 2, width: chip.w)
  }

  /// 本根倒计时：紧贴价格胶囊底下，同一个左沿、同一个宽度，中间留 2pt。
  ///
  /// 底色借十字线读数那一对（`crossBg` / `crossInk`）而不是涨跌色：它报的是「还有多久」，
  /// 是个读数不是行情，跟着涨跌变色只会误导。也因此不需要新增任何颜色常数。
  ///
  /// - Parameter width: 价格胶囊的宽度。轴窄下来之后 `12d 03:05` 这种长文案未必放得下，
  ///   所以允许往右长到轴宽为止——「同宽」是常态而不是死规矩，宁可略宽一点也别把字截掉。
  private func drawCountdown(_ ctx: CGContext, L: Layout, belowY: Double, width: Double) {
    guard state.options.countdown, let now = state.nowMs, let text = countdownText(now: now)
    else { return }
    let t = state.colors
    let h = 13.0
    let y = belowY + 2 + h <= L.timeY ? belowY + 2 : max(0, belowY - 15 - 2 - h)
    guard y + h <= L.timeY else { return }   // 顶到时间轴上就不画了
    let chip = axisChip(L, text: text, font: ChartFont.tiny, minWidth: width)
    ctx.setFillColor(Paint.cg(t.crossBg))
    ctx.addRoundRect(CGRect(x: chip.x, y: y, width: chip.w, height: h), radius: 3)
    ctx.fillPath()
    text.drawCentered(
      at: CGPoint(x: chip.x + chip.w / 2, y: y + h / 2), font: ChartFont.tiny, color: t.crossInk)
  }

  /// 倒计时文案。最后一根的收盘时刻 = 它的 openTime + 周期，收盘已过给 `nil`。
  ///
  /// 用 `series.time(at:)` 拿 openTime 而不是 `t0 + i * step`：1M 这种不等距周期
  /// 只有查表才是对的。
  func countdownText(now: Double) -> String? {
    let b = state.series
    guard b.count > 0 else { return nil }
    let close = Double(b.time(at: b.count - 1)) + Double(b.step)
    return fmtCountdown(msRemaining: close - now)
  }

  /// 这一档周期里，倒计时能写出来的**最长**那个写法（量轴宽用）。
  ///
  /// 只看周期不看当前时刻：`nowMs` 不是几何输入（`sameGeometryInputs` 特意把它摘出去），
  /// 拿它算宽度就等于每秒重排一次右轴。剩余时间落在 `(0, step]` 里，写法在 1 小时和
  /// 1 天两个坎上各变一次，所以把坎两侧各探一下，取最宽的那个。
  func countdownTemplate() -> String? {
    guard state.options.countdown, state.series.count > 0 else { return nil }
    let step = Double(state.series.step)
    let probes = [step, 86_400_000, 86_399_000, 3_600_000, 3_599_000].filter { $0 > 0 && $0 <= step }
    let texts = probes.compactMap { fmtCountdown(msRemaining: $0) }
    return texts.max { Double($0.width(ChartFont.tiny)) < Double($1.width(ChartFont.tiny)) }
  }
}

/// 平均 K 线的可见段（含热身），外加它的极值。
///
/// 单独一个类型是为了让 `ChartRenderer` 只在 `recalc()` 里算一次：一帧里画蜡烛、算价格
/// 区间、取证探针三处都要用，重算三遍纯属浪费。
public struct HeikinSlice: Sendable, Equatable {
  public var lo: Int
  public var open: [Double], high: [Double], low: [Double], close: [Double]
  /// 给 `priceRange(extraPrices:)` 用：`hh`/`hl` 必然跑到真实 high/low 之外
  /// （`ho` 是上一根的均值），不并进去蜡烛会被裁掉一截。
  public var extremes: [Double]

  static func make(state: ChartState) -> HeikinSlice? {
    guard state.options.kind == .heikin, state.series.count > 0 else { return nil }
    let (lo, hi) = visibleRange(view: state.view, series: state.series)
    let v = HeikinAshi.slice(state.series, lo: lo, hi: hi)
    guard !v.close.isEmpty else { return nil }
    let mx = v.high.max() ?? 0, mn = v.low.min() ?? 0
    return HeikinSlice(
      lo: lo, open: v.open, high: v.high, low: v.low, close: v.close, extremes: [mn, mx])
  }

  /// 第 `i` 根（原序列下标）的平均 K 线；不在这一段里给 `nil`。
  public func bar(_ i: Int) -> (o: Double, h: Double, l: Double, c: Double)? {
    let k = i - lo
    guard k >= 0, k < open.count else { return nil }
    return (open[k], high[k], low[k], close[k])
  }
}

extension ChartRenderer {
  func axisLabel(_ price: Double, range: PriceRange) -> String {
    state.price.mode == .percent ? toFixed((price / range.base - 1) * 100, 2) + "%" : fmtNum(price, state.decimals)
  }

  /// One derived container; top mode is rendered by the host, never cached here.
  func drawCandleData(_ ctx: CGContext, L: Layout, index: Int, selectedX: Double) {
    guard state.options.dataDisplay != .top else { return }
    let b = state.series
    let lines = [fmtFull(ms: Double(b.time(at: index)), offsetMinutes: state.timezone.offsetMinutes),
      "开 " + fmtNum(b.open[index], state.decimals), "高 " + fmtNum(b.high[index], state.decimals),
      "低 " + fmtNum(b.low[index], state.decimals), "收 " + fmtNum(b.close[index], state.decimals),
      "量 " + indicatorNumber(b.volume[index])]
    let wantedW = (lines.map { Double($0.width(ChartFont.axis)) }.max() ?? 100) + 16
    let box = CandleDataBox.rect(plotWidth: L.plotW, mainHeight: L.mainH,
      selectedX: selectedX, desiredWidth: wantedW, desiredHeight: Double(lines.count) * 14 + 12,
      follow: state.options.dataDisplay == .follow)
    let rect = CGRect(x: box.x, y: box.y, width: box.width, height: box.height)
    ctx.saveGState(); defer { ctx.restoreGState() }
    ctx.clip(to: rect)
    ctx.setFillColor(Paint.cg(state.colors.bg)); ctx.fill(rect)
    ctx.setStrokeColor(Paint.cg(state.colors.axis)); ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
    let rowHeight = min(14, (rect.height - 8) / Double(lines.count))
    for (row, text) in lines.enumerated() {
      text.drawLeft(at: CGPoint(x: rect.minX + 8, y: rect.minY + 5 + rowHeight * (Double(row) + 0.5)),
        font: ChartFont.axis, color: state.colors.text)
    }
  }
}
