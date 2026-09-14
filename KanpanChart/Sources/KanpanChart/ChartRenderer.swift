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

  public init(state: ChartState) {
    self.state = state
    recalc()
  }

  private mutating func recalc() {
    engine.ensure(
      series: state.series, wanted: state.overlays + state.subs,
      params: state.params, oi: state.oi, dataKey: state.symbol.symbol)
  }

  // ---------------------------------------------------------------- 入口

  public func layout(size: CGSize) -> Layout {
    Layout(width: Double(size.width), height: Double(size.height), style: state.style, subs: state.subs)
  }

  /// 主图价格区间。手势层要用同一份，所以露出来。
  public func priceRange(size: CGSize) -> PriceRange {
    KanpanCore.priceRange(
      view: state.view, series: state.series, style: state.style,
      overlayValues: overlayLines(), drawingPrices: state.drawings.flatMap(\.prices),
      transform: state.price)
  }

  /// 底图：背景、网格、K 线、叠加、画线、最新价、副图、时间轴、图例。
  ///
  /// `live == false` 时跳过最新价——`ChartView` 把最新价放在单独一层（§5.7），
  /// 由 `drawPlot` / `drawLive` 分别调进来。
  public func draw(in ctx: CGContext, size: CGSize, scale: CGFloat, live: Bool = true) {
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
    for k in 1..<L.panes.count { drawSub(ctx, pane: L.panes[k], L: L, scale: s) }
    drawTimeAxis(ctx, L: L, scale: s)
    drawLegend(ctx, pane: main, L: L)
  }

  /// 十字线层（原型 `paintOver`）。M3 只按 `state.crosshair` 静态摆放。
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
    ctx.clear(CGRect(origin: .zero, size: size))

    let xc = x(b.time(at: i), L)
    let y = min(L.timeY, max(0, cross.y ?? yOf(b.close[i], pane, r)))

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
    let gm = state.style.grid
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
  }

  // ---------------------------------------------------------------- 时间轴

  private func ticks(_ L: Layout) -> [(t: Double, step: Int64)] {
    timeTicks(view: state.view, plotW: L.plotW, offsetMinutes: state.timezone.offsetMinutes)
  }

  private func drawTimeGrid(_ ctx: CGContext, L: Layout, scale s: Double) {
    guard state.style.grid == .both else { return }
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

  private func drawCandles(_ ctx: CGContext, pane: Pane, r: PriceRange, L: Layout, scale s: Double) {
    let b = state.series, t = state.colors, S = state.style
    let (lo, hi) = visible
    let spacing = state.view.barSpacing(step: b.step, plotW: L.plotW)
    let m = candleMetrics(spacing: spacing, style: S, scale: s)
    let lw = m.outline
    let hollowShape = S.shape == .outline || S.shape == .hollowUp

    ctx.saveGState()
    ctx.beginPath()
    ctx.addRect(CGRect(x: 0, y: pane.y, width: L.plotW, height: pane.h))
    ctx.clip()
    ctx.setLineCap(S.wickCap == .round ? .round : .butt)

    for i in lo...hi {
      let xc = x(b.time(at: i), L)
      if xc < -4 || xc > L.plotW + 4 { continue }
      let up = b.close[i] >= b.open[i]
      let col = up ? t.up : t.down
      let wick = S.wickTint < 1 ? Paint.mix(t.bg, col, S.wickTint) : col
      let yh = yOf(b.high[i], pane, r), yl = yOf(b.low[i], pane, r)

      // 影线：可以比实体淡，端头可以是圆的
      if S.wickCap == .round && !m.thin {
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

      let yo = yOf(b.open[i], pane, r), yc = yOf(b.close[i], pane, r)
      let top = min(yo, yc)
      let h = max(m.minBody, abs(yc - yo))
      let xb = snap(xc - m.bodyW / 2, scale: s)
      let drawHollow = S.shape == .outline || (S.shape == .hollowUp && up)
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
  }
}
