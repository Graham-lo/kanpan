import CoreGraphics
import Foundation
import KanpanCore
import UIKit

/// 成交量柱的颜色：涨跌色压 40% 透明（原型 `app.js` 的 `theme.volUp = up + '66'`）。
extension ChartColors {
  var volUp: Hex { up.alpha("66") }
  var volDn: Hex { down.alpha("66") }
}

/// 一帧的画法，1:1 移植自 `prototype/src/chart.js` 的 `paint()`。
///
/// 底图和十字线分两层，跟原型的 `bctx` / `octx` 对应：底图重画一次要遍历几百根 K 线，
/// 十字线跟手要 60fps，两者不能挤在一张画布上。
///
/// 算法一律走 `KanpanCore`（`priceRange` / `priceTicks` / `timeTicks` / `candleWidths`
/// / `IndicatorEngine`），这里只负责把数落到像素上。
public struct ChartRenderer {
  public var state: ChartState { didSet { recalc() } }
  public private(set) var engine = IndicatorEngine()
  /// 平均 K 线的可见段。`kind == .candle` 时恒为 `nil`——默认路径一个数都不多算。
  public private(set) var heikin: HeikinSlice?

  public init(state: ChartState) {
    self.state = state
    recalc()
  }

  private mutating func recalc() {
    engine.ensure(
      series: state.series, wanted: state.overlays + state.subs,
      params: state.params, oi: state.oi, dataKey: state.symbol.symbol)
    heikin = HeikinSlice.make(state: state)
  }

  // ---------------------------------------------------------------- 入口

  public func layout(size: CGSize) -> Layout {
    Layout(
      width: Double(size.width), height: Double(size.height), style: state.style,
      subs: state.subs, subScale: state.subScale)
  }

  /// 主图价格区间。手势层要用同一份，所以露出来。
  public func priceRange(size: CGSize) -> PriceRange {
    priceRange(size: size, transform: state.price)
  }

  /// 换一套 `zoom`/`shift` 重算区间，别的输入不动。
  ///
  /// 拖价格轴要为「按下点不动」解 `shift`（`PriceAnchor`），一次二分要问几十遍区间；
  /// 走这条不用改 `state`，叠加指标的缓存也不会被反复推翻。
  public func priceRange(size: CGSize, transform: PriceTransform) -> PriceRange {
    priceRange(size: size, view: state.view, transform: transform)
  }

  /// 再换一套视野。捏合期间要为「框钉住不动」解 `zoom`/`shift`，而解之前必须先知道
  /// **新视野**下不带变换的区间长什么样——这时 `state.view` 还是旧的，不能用。
  ///
  /// 叠加指标（`overlayLines()`）和平均 K 线的极值算的都是整条序列，与视野无关，
  /// 缓存照旧能用，所以这条只是把 `view` 换掉，不额外花钱。
  public func priceRange(size: CGSize, view: ViewWindow, transform: PriceTransform) -> PriceRange {
    KanpanCore.priceRange(
      view: view, series: state.series, style: state.style,
      overlayValues: overlayLines(),
      // 画线关掉了就别再让它撑价格区间：一条看不见的线把蜡烛压扁，用户只会觉得图坏了。
      drawingPrices: state.options.drawings ? state.drawings.flatMap(\.prices) : [],
      transform: transform,
      extraPrices: heikin?.extremes ?? [], bias: state.options.bias)
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
    drawOverlays(ctx, pane: main, r: r, L: L, scale: s)
    drawDrawings(ctx, pane: main, r: r, L: L, scale: s)
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
  public func drawOverlay(in ctx: CGContext, size: CGSize, scale: CGFloat) {
    guard !state.series.isEmpty, let cross = state.crosshair else { return }
    let L = layout(size: size)
    let r = priceRange(size: size)
    let t = state.colors
    let s = Double(scale)
    let b = state.series
    let i = min(max(0, cross.index), b.count - 1)
    let pane = L.main

    UIGraphicsPushContext(ctx)
    defer { UIGraphicsPopContext() }

    // 磁吸开着就画在根中心；关掉才用手指停住的那个时间。两个字段都空（M3 的静态摆放、
    // A3.11 的基线）走的还是根中心 + 收盘价这条老路。
    let freeT = state.magnet ? nil : cross.t
    let xc = freeT.map { state.view.x($0, plotW: L.plotW) } ?? x(b.time(at: i), L)
    let y = min(L.timeY, max(0, yOf(cross.price ?? b.close[i], pane, r)))

    ctx.saveGState()
    ctx.setLineDash(phase: 0, lengths: [3 / s, 3 / s])
    ctx.setStrokeColor(Paint.cg(t.cross))
    ctx.setLineWidth(1 / s)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: hairline(xc, scale: s), y: 0))
    ctx.addLine(to: CGPoint(x: hairline(xc, scale: s), y: L.timeY))
    ctx.strokePath()
    ctx.beginPath()
    ctx.move(to: CGPoint(x: 0, y: hairline(y, scale: s)))
    ctx.addLine(to: CGPoint(x: L.plotW, y: hairline(y, scale: s)))
    ctx.strokePath()
    ctx.restoreGState()

    // 右轴价格
    if y <= pane.y + pane.h {
      let p = pOf(y, pane, r)
      let label = state.price.mode == .percent
        ? toFixed((p / r.base - 1) * 100, 2) + "%"
        : fmtNum(p, state.decimals)
      let w = min(state.style.axisW - 2, Double(label.width(ChartFont.axis)) + 10)
      ctx.setFillColor(Paint.cg(t.crossBg))
      ctx.addRoundRect(CGRect(x: L.plotW + 2, y: y - 7.5, width: w, height: 15), radius: 3)
      ctx.fillPath()
      label.drawCentered(at: CGPoint(x: L.plotW + 2 + w / 2, y: y), font: ChartFont.axis, color: t.crossInk)
    }

    // 下轴时间
    let tl = fmtFull(ms: Double(b.time(at: i)), offsetMinutes: state.timezone.offsetMinutes)
    let tw = Double(tl.width(ChartFont.axis)) + 12
    let tx = max(2, min(L.plotW - tw - 2, xc - tw / 2))
    ctx.setFillColor(Paint.cg(t.crossBg))
    ctx.addRoundRect(
      CGRect(x: tx, y: L.timeY + 3, width: tw, height: state.style.timeH - 6), radius: 3)
    ctx.fillPath()
    tl.drawCentered(
      at: CGPoint(x: tx + tw / 2, y: L.timeY + state.style.timeH / 2),
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
  private func overlayLines() -> [[Double]] {
    var out: [[Double]] = []
    for id in state.overlays {
      guard let v = engine[id] else { continue }
      switch id {
      case .ma, .ema: out += v.lines
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
      let y = pane.y + pane.h - ((f - a) / (z - a)) * pane.h
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
      label.drawLeft(at: CGPoint(x: L.plotW + 5, y: y), font: ChartFont.axis, color: t.dim)
    }
    ctx.hairLineV(x: L.plotW, from: 0, to: L.H, scale: CGFloat(s), color: Paint.cg(t.axis))
    drawAutoFitButton(ctx, L: L, scale: s)
  }

  /// 价格轴底下那个圈着的「R」：手动定标时才出现，点一下把价格轴交还给自动贴合。
  ///
  /// 位置和造型照 AiCoin 手机版（桌面版同一个位置放的是「对数 / % / 自动」三个钮，
  /// 手机宽度不够，官方自己就收成了一个「R」）。手势那头在 `Layout.hitsAutoFit`。
  private func drawAutoFitButton(_ ctx: CGContext, L: Layout, scale s: Double) {
    guard state.price.isManual else { return }
    let t = state.colors
    let b = L.autoFitButton
    let rect = CGRect(x: b.x, y: b.y, width: b.w, height: b.h)
    ctx.setLineWidth(1 / s)
    ctx.setStrokeColor(Paint.cg(t.dim))
    ctx.strokeEllipse(in: rect.insetBy(dx: 0.5 / s, dy: 0.5 / s))
    "R".drawCentered(
      at: CGPoint(x: rect.midX, y: rect.midY), font: ChartFont.axis, color: t.dim)
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
          at: CGPoint(x: xx, y: L.timeY + state.style.timeH / 2),
          font: ChartFont.axis, color: t.dim)
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
    // 实体只剩 2 个设备像素以内时别再把影线往背景色里兑：兑淡是为了让粗影线给大实体
    // 让位（墩 0.7 / 砖 0.45 / 辉 0.6），整根只剩一两个像素宽的时候它只会让影线消失。
    let tint = m.bodyW * s <= 2 ? 1 : S.wickTint
    // 圆头帽在 ≤2 个设备像素时只贡献两坨抗锯齿，不贡献造型，那就别用。
    let roundCap = S.wickCap == .round && m.wickW * s >= 3
    let minBodyH = max(m.wickW, snap(m.minBody, scale: s))

    ctx.saveGState()
    ctx.beginPath()
    ctx.addRect(CGRect(x: 0, y: pane.y, width: L.plotW, height: pane.h))
    ctx.clip()
    ctx.setLineCap(roundCap ? .round : .butt)

    for i in lo...hi {
      let xc = x(b.time(at: i), L)
      if xc < -4 || xc > L.plotW + 4 { continue }
      // 平均 K 线只换这四个数，别处（最新价、指标、读数）一律还是真实价。
      let bar = ha?.bar(i) ?? (o: b.open[i], h: b.high[i], l: b.low[i], c: b.close[i])
      let up = bar.c >= bar.o
      let col = up ? t.up : t.down
      let wick = tint < 1 ? Paint.mix(t.bg, col, tint) : col
      let yh = snap(yOf(bar.h, pane, r), scale: s), yl = snap(yOf(bar.l, pane, r), scale: s)

      // 影线：可以比实体淡，端头可以是圆的
      if roundCap && !m.thin {
        ctx.setStrokeColor(Paint.cg(wick))
        ctx.setLineWidth(m.wickW)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: hairline(xc, scale: s), y: yh + m.wickW / 2))
        ctx.addLine(to: CGPoint(x: hairline(xc, scale: s), y: yl - m.wickW / 2))
        ctx.strokePath()
      } else {
        ctx.setFillColor(Paint.cg(wick))
        let xw = snap(xc - m.wickW / 2, scale: s)
        ctx.fill(CGRect(x: xw, y: yh, width: m.wickW, height: max(m.wickW, yl - yh)))
      }
      if m.thin { continue }

      let yo = yOf(bar.o, pane, r), yc = yOf(bar.c, pane, r)
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
          ctx.setFillColor(Paint.cg(t.bg))
          ctx.setStrokeColor(Paint.cg(col))
          ctx.drawPath(using: .fillStroke)
        } else {
          ctx.setFillColor(Paint.cg(t.bg))
          ctx.fill(rect)
          ctx.setStrokeColor(Paint.cg(col))
          ctx.stroke(rect.insetBy(dx: lw / 2, dy: lw / 2), width: lw)
        }
      } else if m.radius > 0 && h > m.radius * 2 {
        ctx.setFillColor(Paint.cg(col))
        ctx.addRoundRect(rect, radius: m.radius)
        ctx.fillPath()
      } else {
        ctx.setFillColor(Paint.cg(col))
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
    var on = false
    for i in lo...hi where i < arr.count {
      let v = arr[i]
      if !v.isFinite { on = false; continue }
      let px = x(b.time(at: i), plotW: plotW)
      let py = yOf(v, pane, r)
      if on { ctx.addLine(to: CGPoint(x: px, y: py)) } else { ctx.move(to: CGPoint(x: px, y: py)); on = true }
    }
    ctx.strokePath()
  }

  private func drawOverlays(_ ctx: CGContext, pane: Pane, r: PriceRange, L: Layout, scale s: Double) {
    let t = state.colors
    let (lo, hi) = visible
    let pal = t.palette
    ctx.saveGState()
    ctx.beginPath()
    ctx.addRect(CGRect(x: 0, y: pane.y, width: L.plotW, height: pane.h))
    ctx.clip()
    for id in state.overlays {
      guard let v = engine[id] else { continue }
      switch id {
      case .ma:
        for (k, a) in v.lines.enumerated() {
          line(ctx, pane: pane, r: r, plotW: L.plotW, arr: a, color: pal[k % pal.count], lo: lo, hi: hi)
        }
      case .ema:
        for (k, a) in v.lines.enumerated() {
          line(ctx, pane: pane, r: r, plotW: L.plotW, arr: a, color: pal[(k + 3) % pal.count], lo: lo, hi: hi)
        }
      case .boll:
        guard v.lines.count >= 3 else { break }
        line(ctx, pane: pane, r: r, plotW: L.plotW, arr: v.lines[1], color: t.band, lo: lo, hi: hi)
        line(ctx, pane: pane, r: r, plotW: L.plotW, arr: v.lines[0], color: t.amber, lo: lo, hi: hi)
        line(ctx, pane: pane, r: r, plotW: L.plotW, arr: v.lines[2], color: t.band, lo: lo, hi: hi)
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
    let y = yOf(p, pane, r)
    if y < pane.y || y > pane.y + pane.h { return }
    let up = b.close[i] >= b.open[i]
    let col = up ? t.up : t.down

    ctx.saveGState()
    if state.style.lastDash { ctx.setLineDash(phase: 0, lengths: [3 / s, 3 / s]) }
    ctx.hairLine(from: 0, to: L.plotW, y: y, scale: CGFloat(s), color: Paint.cg(col))
    ctx.restoreGState()

    let label = fmtNum(p, state.decimals)
    let w = min(state.style.axisW - 2, Double(label.width(ChartFont.axis)) + 10)
    let h = 15.0
    ctx.setFillColor(Paint.cg(col))
    ctx.addRoundRect(CGRect(x: L.plotW + 2, y: y - h / 2, width: w, height: h), radius: 3)
    ctx.fillPath()
    label.drawCentered(at: CGPoint(x: L.plotW + 2 + w / 2, y: y), font: ChartFont.axis, color: t.chip)
    drawCountdown(ctx, L: L, belowY: y + h / 2, width: w)
  }

  /// 本根倒计时：紧贴价格胶囊底下，同一个左沿、同一个宽度，中间留 2pt。
  ///
  /// 底色借十字线读数那一对（`crossBg` / `crossInk`）而不是涨跌色：它报的是「还有多久」，
  /// 是个读数不是行情，跟着涨跌变色只会误导。也因此不需要新增任何颜色常数。
  ///
  /// - Parameter width: 价格胶囊的宽度。窄轴风格（密 `axisW` 只有 40pt）放不下
  ///   `12d 03:05` 这种长文案，所以允许往右长到轴宽为止——「同宽」是常态而不是死规矩，
  ///   宁可略宽一点也别把字截掉。
  private func drawCountdown(_ ctx: CGContext, L: Layout, belowY: Double, width: Double) {
    guard state.options.countdown, let now = state.nowMs, let text = countdownText(now: now)
    else { return }
    let t = state.colors
    let h = 13.0
    let y = belowY + 2
    guard y + h <= L.timeY else { return }   // 顶到时间轴上就不画了
    let w = min(state.style.axisW - 2, max(width, Double(text.width(ChartFont.tiny)) + 8))
    ctx.setFillColor(Paint.cg(t.crossBg))
    ctx.addRoundRect(CGRect(x: L.plotW + 2, y: y, width: w, height: h), radius: 3)
    ctx.fillPath()
    text.drawCentered(
      at: CGPoint(x: L.plotW + 2 + w / 2, y: y + h / 2), font: ChartFont.tiny, color: t.crossInk)
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
