// 移植自 KanpanChart/Sources/KanpanChart/ChartRenderer.swift（外加 ChartRenderer+Layers.swift、
// ChartRenderer+Depth.swift 与 HeikinSlice）
//
// CoreGraphics → Canvas 2D。坐标一律是「点」（CSS px），画布事先 setTransform(dpr)；
// 需要落在物理像素上的（影线、实体、网格）照 Swift 用 snap / hairline 按 scale（= dpr）对齐。
//
// 缓存分三层，各按各的输入失效（审查 23.4，照 Swift recalc）：
// - 输入层（指标掩码、叠加线、图例内缩、轴字宽）：state.input 变了、或 K 线戳变了、或订单流有 ↔ 无。
// - 视野层（布局、价格区间）：再加上 state.viewport。
// - 叠加层（画线、十字线、订单流、盘口、倒计时）不失效任何东西。
// Swift 的 state 是值类型、按 == 比；这里 state 每层是不可变对象，按引用比；
// BarSeries 原地改，另记它的 revision / prefixRevision / count 指纹。

import { IndicatorEngine } from '../indicator/engine'
import type { IndicatorID } from '../indicator/ids'
import { defaultParams, IndicatorResult, lineNames, paletteOffset } from '../indicator/ids'
import type { BarSeries } from './series'
import { heikinAshiSlice, isIrregular } from './series'
import type { PriceRange, PriceTransform, ViewWindow, Pane } from './geometry'
import {
  AICoinBehavior, CandleDataBox, ChartContentLayout, Layout, PriceMapping, candleMetrics, forward,
  hairline, isMainPane, pOf as corePOf, priceRange as corePriceRange, rendering, snap, timeTicks,
  visibleRange, yOf as coreYOf,
} from './geometry'
import { advancing, fmtCountdown, fmtFull, fmtNum, fmtTick, fmtVol, toFixed } from './format'
import type { ChartColors, ChartFontSpec, Hex } from './paint'
import { ChartFont, css, drawCentered, drawLeft, fillRoundRect, hairLine, hairLineV, textHeight, textWidth } from './paint'
import type { ChartState } from './state'
import { comparePercentLabel, effectiveGrid, effectivePriceMode, effectiveShape, indicatorInputs } from './state'
import type { Drawing } from './drawing'
import { DrawAxes, paintDrawing } from './drawing'
import { drawOrderFlow, drawOrderFlowHover, drawOrderFlowLabels, hasOrderFlow, orderFlowHoversBand } from './renderer.orderflow'
import { drawLegend, drawLegends, drawSub, subAxisLabels, subCrosshairY, subValueText } from './renderer.sub'
import { compareLegendInset, compareRange, drawCompare, mainPriceTicks } from './renderer.compare'

export type PriceFlash = 'up' | 'down'

/** HeikinSlice：只算可见段（外加热身）的平均 K 线。 */
export class HeikinSlice {
  constructor(
    readonly lo: number,
    readonly open: number[], readonly high: number[], readonly low: number[], readonly close: number[],
    readonly extremes: number[],
  ) {}

  static make(state: ChartState): HeikinSlice | null {
    const s = state.input.series
    if (state.input.options.kind !== 'heikin' || s.count <= 0) return null
    const { lo, hi } = visibleRange(state.viewport.view, s)
    const v = heikinAshiSlice(s, lo, hi)
    if (!v.close.length) return null
    let mx = -Infinity, mn = Infinity
    for (const x of v.high) if (x > mx) mx = x
    for (const x of v.low) if (x < mn) mn = x
    return new HeikinSlice(lo, v.open, v.high, v.low, v.close, [mn, mx])
  }

  bar(i: number): { o: number; h: number; l: number; c: number } | null {
    const k = i - this.lo
    if (k < 0 || k >= this.open.length) return null
    return { o: this.open[k], h: this.high[k], l: this.low[k], c: this.close[k] }
  }
}

interface InputCache {
  legendInset: { plotW: number; value: number } | null
  overlayLines: number[][] | null
  displayed: Map<IndicatorID, IndicatorResult | null>
  blank: number[] | null
  axisTextWidths: Map<string, number>
}
interface ViewportCache {
  layout: { W: number; H: number; value: Layout } | null
  ranges: { W: number; H: number; view: ViewWindow; transform: PriceTransform; value: PriceRange }[]
}
const newInputCache = (): InputCache => ({ legendInset: null, overlayLines: null, displayed: new Map(), blank: null, axisTextWidths: new Map() })
const newViewportCache = (): ViewportCache => ({ layout: null, ranges: [] })

/** K 线的指纹：原地改的 BarSeries 靠它判断「没变 / 末根变了 / 追加一根 / 整条换了」。 */
interface SeriesPrint { ref: BarSeries; revision: number; prefixRevision: number; count: number; t0: number; symbol: string; interval: string; lastTime: number }
const printOf = (s: BarSeries): SeriesPrint => ({
  ref: s, revision: s.revision, prefixRevision: s.prefixRevision, count: s.count, t0: s.t0, symbol: s.symbol, interval: s.interval,
  lastTime: s.count > 0 ? s.time(s.count - 1) : NaN,
})

const sameTransform = (a: PriceTransform, b: PriceTransform): boolean =>
  a.mode === b.mode && a.inverted === b.inverted && a.zoom === b.zoom && a.centerFraction === b.centerFraction
const sameIds = (a: readonly string[], b: readonly string[]): boolean => a.length === b.length && a.every((x, i) => x === b[i])

export type Rect = { x: number; y: number; w: number; h: number }

export class ChartRenderer {
  guestDrawings: Drawing[] = []
  ownDimmed = false
  priceFlash: PriceFlash | null = null
  pinnedPriceRange: PriceRange | null = null
  engine = new IndicatorEngine()
  heikin: HeikinSlice | null = null
  /** 订单流子模块自己的缓存；输入 / 视野 / 订单流快照任何一样变了就整只换新。 */
  orderFlowCache: Map<string, unknown> = new Map()

  private _state: ChartState
  private print: SeriesPrint
  private inputCache = newInputCache()
  private viewportCache = newViewportCache()

  constructor(state: ChartState) {
    this._state = state
    this.print = printOf(state.input.series)
    this.recalc(null, null)
  }

  get state(): ChartState { return this._state }
  set state(next: ChartState) {
    const previous = this._state, prevPrint = this.print
    this._state = next
    this.print = printOf(next.input.series)
    this.recalc(previous, prevPrint)
  }

  get colors(): ChartColors { return this._state.input.colors }

  private seriesChanged(prev: SeriesPrint): boolean {
    const p = this.print
    return prev.ref !== p.ref || prev.revision !== p.revision
  }

  private recalc(previous: ChartState | null, prev: SeriesPrint | null): void {
    const state = this._state
    if (!previous || !prev) {
      this.inputCache = newInputCache(); this.viewportCache = newViewportCache(); this.orderFlowCache = new Map()
      this.rebuildIndicators(null, null)
      return
    }
    const inputChanged = previous.input !== state.input || this.seriesChanged(prev)
      || (previous.overlay.orderFlow == null) !== (state.overlay.orderFlow == null)
    const viewportChanged = previous.viewport !== state.viewport && !(
      previous.viewport.view.equals(state.viewport.view) && sameTransform(previous.viewport.price, state.viewport.price)
      && previous.viewport.axisScaleAnchor === state.viewport.axisScaleAnchor && previous.viewport.subScale === state.viewport.subScale)
    if (inputChanged) this.inputCache = newInputCache()
    if (inputChanged || viewportChanged) this.viewportCache = newViewportCache()
    if (inputChanged || viewportChanged || previous.overlay.orderFlow !== state.overlay.orderFlow
      || previous.overlay.orderFlowDisplay !== state.overlay.orderFlowDisplay) {
      this.orderFlowCache = new Map()
    }
    if (inputChanged || !previous.viewport.view.equals(state.viewport.view)) this.rebuildIndicators(previous, prev)
  }

  private rebuildIndicators(previous: ChartState | null, prev: SeriesPrint | null): void {
    const state = this._state, inp = state.input
    const dataKey = inp.symbol.symbol
    const seriesChanged = !previous || !prev || this.seriesChanged(prev)
    const oiChanged = previous != null && (previous.input.oi !== inp.oi || previous.input.external !== inp.external)
    const paramsSame = previous != null && previous.input.params === inp.params
    const setsSame = previous != null && sameIds(previous.input.overlays, inp.overlays) && sameIds(previous.input.subs, inp.subs)
    const inputsChanged = seriesChanged || oiChanged || !paramsSame || !setsSame
    let tailed = false
    if (previous && prev && (seriesChanged || oiChanged)) {
      const p = this.print
      // samePrefix：同一份（原地改）、同形状、前缀戳没动 → 只有末根变了（replaceLast 原样留着前缀戳）。
      const samePrefix = prev.ref === p.ref && prev.count === p.count && prev.t0 === p.t0 && p.count > 0
        && prev.prefixRevision === p.prefixRevision && prev.lastTime === p.lastTime
      // isOneBarAfter：新周期开盘，老的整条成了新的前缀。
      const oneBarAfter = prev.ref === p.ref && p.count === prev.count + 1 && prev.count > 0 && p.prefixRevision === prev.revision
      if ((samePrefix || oneBarAfter) && !oiChanged) {
        this.engine.updateTail({ series: inp.series, external: indicatorInputs(state), dataKey })
        tailed = true
      } else {
        this.engine = new IndicatorEngine()
      }
    }
    const onlyTicked = tailed && paramsSame && setsSame
    if (inputsChanged && !onlyTicked) {
      this.engine.ensure({
        series: inp.series, wanted: [...inp.overlays, ...inp.subs],
        params: inp.params, external: indicatorInputs(state), dataKey,
      })
    }
    if (seriesChanged || !previous || !previous.viewport.view.equals(state.viewport.view) || previous.input.options.kind !== inp.options.kind) {
      this.heikin = HeikinSlice.make(state)
    }
  }

  // ---------------------------------------------------------------- 指标取值

  displayed(id: IndicatorID): IndicatorResult | null {
    const c = this.inputCache.displayed
    if (c.has(id)) return c.get(id) ?? null
    const value = this.computeDisplayed(id)
    c.set(id, value)
    return value
  }

  private computeDisplayed(id: IndicatorID): IndicatorResult | null {
    const result = this.engine.get(id)
    if (!result) return null
    const hidden = this._state.input.hiddenOutputs[id] ?? []
    if (!hidden.length) return result
    const lines = result.lines.map((l, k) => (hidden.includes(k) ? this.blankLine(l.length) : l))
    const histogram = hidden.includes(result.lines.length) && result.histogram ? this.blankLine(result.histogram.length) : result.histogram
    return new IndicatorResult(lines, histogram, result.dir)
  }

  private blankLine(n: number): number[] {
    const hit = this.inputCache.blank
    if (hit && hit.length === n) return hit
    const value = new Array<number>(n).fill(NaN)
    this.inputCache.blank = value
    return value
  }

  indicatorColor(id: IndicatorID, index: number): Hex {
    const palette = this.colors.palette
    return this._state.input.indicatorColors[id]?.[index] ?? palette[(index + paletteOffset(id)) % palette.length]
  }

  outputVisible(id: IndicatorID, index: number): boolean {
    return !(this._state.input.hiddenOutputs[id]?.includes(index) ?? false)
  }

  indicatorNumber(value: number, decimals = 2): string {
    return Number.isFinite(value) ? fmtNum(value, decimals) : '--'
  }

  amountNumber(value: number): string {
    return Number.isFinite(value) ? fmtVol(value) : '--'
  }

  params(id: IndicatorID): number[] {
    return (this._state.input.params[id] as number[] | undefined) ?? defaultParams(id)
  }

  /** 自适应只多留图例行，从不改面板分配。 */
  mainLegendInset(plotW: number): number {
    const hit = this.inputCache.legendInset
    if (hit && hit.plotW === plotW) return hit.value
    const value = this.computeMainLegendInset(plotW)
    this.inputCache.legendInset = { plotW, value }
    return value
  }

  private computeMainLegendInset(plotW: number): number {
    const s = this._state, inp = s.input
    if (inp.percentAxis) return compareLegendInset(this, plotW)
    const orderFlowRow = hasOrderFlow(this) ? 12 : 0 // 主力订单流的图例另占一行
    if (!inp.options.adaptiveIndicators) return AICoinBehavior.mainTopInset + orderFlowRow
    let x = 8, rows = 1
    const last = inp.series.close[inp.series.count - 1] ?? 0
    for (const id of inp.overlays) {
      const names = lineNames(id, this.params(id))
      names.forEach((name, k) => {
        if (!this.outputVisible(id, k)) return
        const width = textWidth(name + ' ' + this.indicatorNumber(last, inp.decimals), ChartFont.axis) + 8
        if (x + width > plotW - 4) { rows += 1; x = 8 }
        x += width
      })
    }
    return Math.max(AICoinBehavior.mainTopInset, rows * 12 + 12) + orderFlowRow
  }

  // ---------------------------------------------------------------- 布局与区间

  layout(W: number, H: number): Layout {
    const hit = this.viewportCache.layout
    if (hit && hit.W === W && hit.H === H) return hit.value
    const value = this.computeLayout(W, H)
    this.viewportCache.layout = { W, H, value }
    return value
  }

  private computeLayout(W: number, H: number): Layout {
    const s = this._state, inp = s.input, vp = s.viewport
    const subScale = vp.subScale as Record<string, number>
    const mainWeight = ChartContentLayout.mainWeight(H, inp.options.portraitHeight, inp.subs.length)
    const initial = new Layout(W, H, inp.subs, subScale, mainWeight)
    // 高度变化不许经由「留白后的区间 → 刻度字宽」改到绘图宽度与时间映射。
    const range = inp.percentAxis
      ? compareRange(this, vp.view, vp.price, 300, AICoinBehavior.mainTopInset)
      : corePriceRange(vp.view, inp.series, { overlayValues: this.overlayLines(), transform: vp.price, paneHeight: 300 })
    let labels = [range.lo, range.hi].map(p => this.axisLabel(p, range))
    for (const pane of initial.panes.slice(1)) {
      if (pane.indicator) labels = labels.concat(subAxisLabels(this, pane.indicator as IndicatorID))
    }
    // 轴宽 = 这一屏最宽的那条刻度 + 两侧各 axisLabelPadding。
    let measured = 0
    for (const l of labels) measured = Math.max(measured, this.axisTextWidth(this.axisWidthTemplate(l)))
    // 倒计时也挂在这一格里：开着就按周期能出现的最长写法一并量进来。
    const stamp = this.countdownTemplate()
    if (stamp != null) {
      measured = Math.max(measured, textWidth(this.axisWidthTemplate(stamp), ChartFont.tiny)
        + 2 * (AICoinBehavior.axisChipInset + AICoinBehavior.axisChipPadding) - 2 * AICoinBehavior.axisLabelPadding)
    }
    const width = Math.max(AICoinBehavior.axisMinWidth, Math.ceil(measured) + 2 * AICoinBehavior.axisLabelPadding)
    return new Layout(W, H, inp.subs, subScale, mainWeight, Math.min(Math.max(AICoinBehavior.axisMinWidth, W / 3), width))
  }

  private axisTextWidth(template: string): number {
    const c = this.inputCache.axisTextWidths
    const hit = c.get(template)
    if (hit !== undefined) return hit
    const value = textWidth(template, ChartFont.axis)
    c.set(template, value)
    return value
  }

  axisWidthTemplate(s: string): string {
    return s.replace(/[0-9]/g, '0')
  }

  axisChip(L: Layout, text: string, font: ChartFontSpec = ChartFont.axis, minWidth = 0): { x: number; w: number } {
    const inset = AICoinBehavior.axisChipInset
    const room = Math.max(4, L.axisW - 2 * inset)
    const wanted = Math.ceil(textWidth(text, font)) + 2 * AICoinBehavior.axisChipPadding
    return { x: L.plotW + inset, w: Math.min(room, Math.max(minWidth, wanted)) }
  }

  /** 钉住的时候一律给钉住的那份：画线、十字线读数、蜡烛定标走的都是这一个入口。 */
  priceRange(W: number, H: number, view?: ViewWindow, transform?: PriceTransform): PriceRange {
    if (!view && !transform && this.pinnedPriceRange) return this.pinnedPriceRange
    const s = this._state, inp = s.input
    const v = view ?? s.viewport.view, tr = transform ?? s.viewport.price
    for (const hit of this.viewportCache.ranges) {
      if (hit.W === W && hit.H === H && hit.view.equals(v) && sameTransform(hit.transform, tr)) return hit.value
    }
    const L = this.layout(W, H)
    const value = inp.percentAxis
      ? compareRange(this, v, tr, L.main.h, this.mainLegendInset(L.plotW))
      : corePriceRange(v, inp.series, {
        overlayValues: this.overlayLines(),
        // 画线关掉了就别再让它撑价格区间。
        drawingPrices: [],
        transform: tr,
        extraPrices: this.heikin?.extremes ?? [], bias: inp.options.bias,
        paneHeight: L.main.h, topInset: this.mainLegendInset(L.plotW),
        anchorPrice: tr.zoom !== 1 ? s.viewport.axisScaleAnchor : null,
        closeOnly: inp.options.kind === 'line',
      })
    if (this.viewportCache.ranges.length >= 8) this.viewportCache.ranges.shift()
    this.viewportCache.ranges.push({ W, H, view: v, transform: tr, value })
    return value
  }

  // ---------------------------------------------------------------- 坐标

  x(t: number, plotW: number): number { return this._state.viewport.view.x(t, plotW) }
  yOf(p: number, pane: Pane, r: PriceRange): number { return coreYOf(p, pane, r, effectivePriceMode(this._state)) }
  pOf(y: number, pane: Pane, r: PriceRange): number { return corePOf(y, pane, r, effectivePriceMode(this._state)) }
  visible(): { lo: number; hi: number } { return visibleRange(this._state.viewport.view, this._state.input.series) }
  spacing(plotW: number): number { return this._state.viewport.view.barSpacing(this._state.input.series.step, plotW) }

  get legendIndex(): number {
    const c = this._state.overlay.crosshair, n = this._state.input.series.count
    if (c) return Math.min(Math.max(0, c.index), n - 1)
    return n - 1
  }

  /** 十字线读数：有十字线读那一根，没有读最后一个有限值。 */
  reading(values: number[]): number {
    const cross = this._state.overlay.crosshair
    if (cross) return cross.index >= 0 && cross.index < values.length ? values[cross.index] : NaN
    for (let i = values.length - 1; i >= 0; i--) if (Number.isFinite(values[i])) return values[i]
    return NaN
  }

  overlayLines(): number[][] {
    if (this.inputCache.overlayLines) return this.inputCache.overlayLines
    const value = this.computeOverlayLines()
    this.inputCache.overlayLines = value
    return value
  }

  private computeOverlayLines(): number[][] {
    const inp = this._state.input
    if (inp.percentAxis) return []
    let out: number[][] = []
    for (const id of inp.overlays) {
      const v = this.displayed(id)
      if (!v) continue
      switch (id) {
        // 超级趋势与抛物线转向都贴着价格走，偶尔会甩到可见蜡烛之外；它们要进自适应。
        case 'MA': case 'EMA': case 'VWAP': case 'ST': case 'SAR': out = out.concat(v.lines); break
        case 'BOLL': if (v.lines.length >= 3) out = out.concat([v.lines[1], v.lines[2]]); break
        default: break
      }
    }
    return out
  }

  axisLabel(price: number, range: PriceRange): string {
    const s = this._state
    if (s.input.percentAxis) return comparePercentLabel((price / range.base - 1) * 100)
    return effectivePriceMode(s) === 'percent' ? toFixed((price / range.base - 1) * 100, 2) + '%' : fmtNum(price, s.input.decimals)
  }

  // ---------------------------------------------------------------- 整帧

  draw(ctx: CanvasRenderingContext2D, W: number, H: number, scale: number, live = true, legend = true): void {
    const s = this._state
    if (s.input.series.isEmpty) return
    const L = this.layout(W, H)
    const r = this.priceRange(W, H)
    const t = this.colors
    ctx.clearRect(0, 0, W, H)
    ctx.fillStyle = css(t.bg)
    ctx.fillRect(0, 0, W, H)

    const main = L.main
    this.drawPriceGrid(ctx, main, r, L, scale)
    this.drawTimeGrid(ctx, L, scale)
    // 主力订单流垫在 K 线下面：先画线与淡底，再画蜡烛、均线、副图（「K 线是主体」）。
    if (!s.input.percentAxis) drawOrderFlow(this, ctx, main, r, L, scale)
    this.drawCandles(ctx, main, r, L, scale)
    this.drawExtrema(ctx, r, L, scale)
    if (s.input.percentAxis) drawCompare(this, ctx, main, r, L)
    else {
      this.drawOverlays(ctx, main, r, L, scale)
      this.drawDrawings(ctx, main, r, L, scale)
      if (live) this.drawDepth(ctx, main, r, L)
    }
    if (live) this.drawLastPrice(ctx, main, r, L, scale)
    for (let k = 1; k < L.panes.length; k++) drawSub(this, ctx, L.panes[k], L, scale, legend)
    this.drawTimeAxis(ctx, L, scale)
    if (legend) drawLegend(this, ctx, main, L)
  }

  /** 底图层：不含最新价、盘口、图例（+Layers）。 */
  drawPlot(ctx: CanvasRenderingContext2D, W: number, H: number, scale: number): void {
    this.draw(ctx, W, H, scale, false, false)
  }

  /** 实时层：盘口 + 最新价线与胶囊（+ 倒计时）。返回盘口画了几行。 */
  drawLive(ctx: CanvasRenderingContext2D, W: number, H: number, scale: number): number {
    ctx.clearRect(0, 0, W, H)
    const s = this._state
    if (s.input.series.isEmpty) return 0
    const L = this.layout(W, H)
    const r = this.priceRange(W, H)
    const depthRows = s.input.percentAxis ? 0 : this.drawDepth(ctx, L.main, r, L)
    if (s.input.options.lastLine) this.drawLastPrice(ctx, L.main, r, L, scale)
    return depthRows
  }

  /** 十字线层：订单流点亮块与金额签、图例、十字线。 */
  drawCross(ctx: CanvasRenderingContext2D, W: number, H: number, scale: number): void {
    ctx.clearRect(0, 0, W, H)
    const s = this._state
    if (s.input.series.isEmpty) return
    const L = this.layout(W, H)
    if (!s.input.percentAxis) {
      const range = this.priceRange(W, H)
      drawOrderFlowHover(this, ctx, L.main, range, L, scale)
      drawOrderFlowLabels(this, ctx, L.main, range, L, scale)
    }
    drawLegends(this, ctx, L)
    this.drawOverlay(ctx, W, H, scale)
  }

  crosshairCenter(W: number, H: number): { x: number; y: number } | null {
    const s = this._state, cross = s.overlay.crosshair, b = s.input.series
    if (b.isEmpty || !cross) return null
    const L = this.layout(W, H), r = this.priceRange(W, H)
    const i = Math.min(Math.max(0, cross.index), b.count - 1)
    const pane = (cross.pane != null ? L.panes.find(p => p.indicator === cross.pane) : null) ?? L.main
    const rawY = cross.pane != null ? subCrosshairY(this, cross.price ?? 0, pane) : this.yOf(cross.price ?? b.close[i], pane, r)
    return { x: this.x(b.time(i), L.plotW), y: Math.min(pane.y + pane.h - 7, Math.max(pane.y + 7, rawY)) }
  }

  drawOverlay(ctx: CanvasRenderingContext2D, W: number, H: number, scale: number): void {
    const s = this._state, cross = s.overlay.crosshair, b = s.input.series
    if (b.isEmpty || !cross) return
    const L = this.layout(W, H)
    const r = this.priceRange(W, H)
    const t = this.colors
    const i = Math.min(Math.max(0, cross.index), b.count - 1)
    const pane = (cross.pane != null ? L.panes.find(p => p.indicator === cross.pane) : null) ?? L.main
    const center = this.crosshairCenter(W, H)
    if (!center) return
    const xc = center.x, y = center.y

    ctx.save()
    ctx.beginPath(); ctx.rect(0, 0, L.plotW, L.H); ctx.clip()
    ctx.setLineDash([3 / scale, 3 / scale])
    ctx.strokeStyle = css(t.cross)
    ctx.lineWidth = 1 / scale
    ctx.beginPath()
    ctx.moveTo(hairline(xc, scale), 0); ctx.lineTo(hairline(xc, scale), L.H)
    ctx.stroke()
    ctx.beginPath()
    ctx.moveTo(0, hairline(y, scale)); ctx.lineTo(L.plotW, hairline(y, scale))
    ctx.stroke()
    ctx.restore()

    // 右轴价格
    if (y <= pane.y + pane.h) {
      const p = cross.pane == null ? this.pOf(y, pane, r) : (cross.price ?? 0)
      let label: string
      if (cross.pane != null) label = subValueText(this, p, cross.pane)
      else if (s.input.percentAxis) label = comparePercentLabel((p / r.base - 1) * 100)
      else if (effectivePriceMode(s) === 'percent') label = toFixed((p / r.base - 1) * 100, 2) + '%'
      else label = fmtNum(p, s.input.decimals)
      const chip = this.axisChip(L, label)
      fillRoundRect(ctx, chip.x, y - 7.5, chip.w, 15, 3, t.crossBg)
      drawCentered(ctx, label, chip.x + chip.w / 2, y, ChartFont.axis, t.crossInk)
    }

    // 十字线停在一条主力色带上时，那一单的详情卡（页面画）顶替开高低收框，两块不叠。
    if (cross.pane != null || !orderFlowHoversBand(this, L, r)) this.drawCandleData(ctx, L, i, xc)

    // 下轴时间
    const tl = fmtFull(b.time(i), s.input.tzOffset)
    const tw = textWidth(tl, ChartFont.axis) + 12
    const tx = Math.max(2, Math.min(L.plotW - tw - 2, xc - tw / 2))
    fillRoundRect(ctx, tx, L.timeY + 3, tw, AICoinBehavior.timeHeight - 6, 3, t.crossBg)
    drawCentered(ctx, tl, tx + tw / 2, L.timeY + AICoinBehavior.timeHeight / 2, ChartFont.axis, t.crossInk)
  }

  // ---------------------------------------------------------------- 价格网格

  private drawPriceGrid(ctx: CanvasRenderingContext2D, pane: Pane, r: PriceRange, L: Layout, s: number): void {
    const st = this._state, t = this.colors
    const mode = effectivePriceMode(st)
    const a = forward(mode, r.lo, r.base), z = forward(mode, r.hi, r.base)
    const gm = effectiveGrid(st)
    // 手动拖过价格轴之后那颗「A」画在价格轴里；和它同一高度的刻度字让位，网格线照画。
    const manual = st.viewport.price.zoom !== 1
    const fb = manual && isMainPane(pane) ? L.autoFitButton : null
    const fitBadge = fb ? { lo: fb.y - 6, hi: fb.y + fb.h + 6 } : null
    for (const f of mainPriceTicks(this, r, pane.h)) {
      const fraction = (f - a) / (z - a)
      const y = pane.y + (r.inverted ? fraction : 1 - fraction) * pane.h
      if (y < pane.y + 6 || y > pane.y + pane.h - 2) continue
      if (gm !== 'none') hairLine(ctx, 0, L.plotW, y, s, t.grid)
      if (fitBadge && y > fitBadge.lo && y < fitBadge.hi) continue
      let label: string
      switch (mode) {
        case 'percent': label = st.input.percentAxis ? comparePercentLabel(f) : (f >= 0 ? '+' : '') + toFixed(f, 1) + '%'; break
        case 'log': label = fmtNum(Math.exp(f), st.input.decimals); break
        default: label = fmtNum(f, st.input.decimals)
      }
      drawCentered(ctx, label, L.plotW + L.axisW / 2, y, ChartFont.axis, t.dim)
    }
    hairLineV(ctx, L.plotW, 0, L.H, s, t.axis)
    this.drawAutoFitButton(ctx, L)
  }

  private drawAutoFitButton(ctx: CanvasRenderingContext2D, L: Layout): void {
    if (this._state.viewport.price.zoom === 1) return
    const b = L.autoFitButton
    fillRoundRect(ctx, b.x, b.y, b.w, b.h, 2, this.colors.axis)
    drawCentered(ctx, 'A', b.x + b.w / 2, b.y + b.h / 2, ChartFont.axis, this.colors.text)
  }

  // ---------------------------------------------------------------- 时间轴

  private ticks(L: Layout): { t: number; step: number }[] {
    return timeTicks(this._state.viewport.view, L.plotW, this._state.input.tzOffset)
  }

  private drawTimeGrid(ctx: CanvasRenderingContext2D, L: Layout, s: number): void {
    if (effectiveGrid(this._state) !== 'both') return
    const color = this.colors.grid
    for (const k of this.ticks(L)) {
      const xx = this.x(k.t, L.plotW)
      if (xx < 0 || xx > L.plotW) continue
      hairLineV(ctx, xx, 0, L.timeY, s, color)
    }
  }

  private drawTimeAxis(ctx: CanvasRenderingContext2D, L: Layout, s: number): void {
    const t = this.colors
    hairLine(ctx, 0, L.W, L.timeY, s, t.axis)
    const off = this._state.input.tzOffset
    for (const k of this.ticks(L)) {
      const xx = this.x(k.t, L.plotW)
      if (xx < 18 || xx > L.plotW - 18) continue
      drawCentered(ctx, fmtTick(k.t, k.step, off), xx, L.timeY + AICoinBehavior.timeHeight / 2, ChartFont.axis, t.dim)
    }
  }

  // ---------------------------------------------------------------- 最高 / 最低标注

  private drawExtrema(ctx: CanvasRenderingContext2D, r: PriceRange, L: Layout, scale: number): void {
    const st = this._state, b = st.input.series
    const bounds = this.visible()
    // 收盘价画法没画影线：标注落在折线的最高 / 最低收盘上。
    const closeOnly = st.input.options.kind === 'line'
    const highs = closeOnly ? b.close : b.high, lows = closeOnly ? b.close : b.low
    let high = -1, low = -1
    for (let i = bounds.lo; i <= bounds.hi; i++) {
      const px = this.x(b.time(i), L.plotW)
      if (!(px >= 0 && px <= L.plotW)) continue
      // Swift max(by:) 取第一个最大、min(by:) 取第一个最小
      if (high < 0 || highs[i] > highs[high]) high = i
      if (low < 0 || lows[i] < lows[low]) low = i
    }
    if (high < 0 || low < 0) return
    // 主图顶上那几行是图例的地盘；标注以 ty 为纵向中心，下界是「图例占掉的高度 + 半行字」。
    const legendBand = this.mainLegendInset(L.plotW)
    const floor = legendBand + textHeight(ChartFont.axis) / 2 + 2
    const text = this.colors.text
    for (const [index, price, isHigh] of [[high, highs[high], true], [low, lows[low], false]] as [number, number, boolean][]) {
      const px = this.x(b.time(index), L.plotW), py = this.yOf(price, L.main, r)
      const label = st.input.percentAxis ? this.axisLabel(price, r) : fmtNum(price, st.input.decimals)
      const width = textWidth(label, ChartFont.axis)
      const left = px + 16 + width > L.plotW - 4
      const tx = Math.max(4, Math.min(L.plotW - width - 4, left ? px - width - 12 : px + 12))
      const above = isHigh !== r.inverted
      const ty = Math.max(floor, Math.min(L.mainH - 8, py + (above ? -10 : 10)))
      // 引线起点落在图例那几行里时只画跨出图例之后的那一截。
      const ax = left ? tx + width + 3 : tx - 3
      let fx = px, fy = py
      if (py < legendBand && ty > py) {
        const k = (legendBand - py) / (ty - py)
        fx = px + (ax - px) * k; fy = legendBand
      }
      ctx.strokeStyle = css(text); ctx.lineWidth = 1 / scale
      ctx.beginPath(); ctx.moveTo(fx, fy); ctx.lineTo(ax, ty); ctx.stroke()
      drawLeft(ctx, label, tx, ty, ChartFont.axis, text)
    }
  }

  // ---------------------------------------------------------------- K 线

  private drawCandles(ctx: CanvasRenderingContext2D, pane: Pane, r: PriceRange, L: Layout, s: number): void {
    const st = this._state, b = st.input.series, t = this.colors
    const shape = effectiveShape(st)
    const ha = this.heikin
    const { lo, hi } = this.visible()
    const spacing = this.spacing(L.plotW)
    const m = candleMetrics(spacing, s)
    const lw = m.outline
    // 影线与实体同色、平头：AICoin 的做法。
    const minBodyH = Math.max(m.wickW, snap(m.minBody, s))

    ctx.save()
    ctx.beginPath(); ctx.rect(0, pane.y, L.plotW, pane.h); ctx.clip()
    const map = new PriceMapping(r, effectivePriceMode(st))
    const cgBg = css(t.bg), cgUp = css(t.up), cgDown = css(t.down)
    const mode = rendering(spacing, s)
    // 「收盘价」画法和捏到极窄时退成的收盘折线是同一笔：同色（up）、同宽（2 个物理像素）。
    if (st.input.options.kind === 'line' || mode === 'closeLine') {
      this.line(ctx, pane, r, L.plotW, b.close, t.up, lo, hi, 2 / s)
      ctx.restore()
      return
    }
    for (let i = lo; i <= hi; i++) {
      const xc = this.x(b.time(i), L.plotW)
      if (xc < -4 || xc > L.plotW + 4) continue
      // 平均 K 线只换这四个数，别处（最新价、指标、读数）一律还是真实价。
      const bar = ha?.bar(i) ?? { o: b.open[i], h: b.high[i], l: b.low[i], c: b.close[i] }
      const up = bar.c >= bar.o
      const col = up ? cgUp : cgDown
      const highY = map.y(bar.h, pane), lowY = map.y(bar.l, pane)
      const yh = snap(Math.min(highY, lowY), s), yl = snap(Math.max(highY, lowY), s)
      // 影线：和实体同色的整像素矩形
      ctx.fillStyle = col
      const xw = snap(xc - m.wickW / 2, s)
      ctx.fillRect(xw, yh, m.wickW, Math.max(m.wickW, yl - yh))
      if (mode === 'highLow') continue

      const yo = map.y(bar.o, pane), yc = map.y(bar.c, pane)
      const top = snap(Math.min(yo, yc), s)
      const h = Math.max(minBodyH, snap(Math.max(yo, yc), s) - top)
      const xb = snap(xc - m.bodyW / 2, s)
      if (shape === 'hollowUp' && up && h > lw * 2.2 && m.bodyW > lw * 2.2) {
        // 描边实体：先用底色挖空，K 线之间才不会互相糊住
        ctx.fillStyle = cgBg
        ctx.fillRect(xb, top, m.bodyW, h)
        ctx.strokeStyle = col
        ctx.lineWidth = lw
        ctx.strokeRect(xb + lw / 2, top + lw / 2, m.bodyW - lw, h - lw)
      } else {
        ctx.fillStyle = col
        ctx.fillRect(xb, top, m.bodyW, h)
      }
    }
    ctx.restore()
  }

  // ---------------------------------------------------------------- 叠加

  line(ctx: CanvasRenderingContext2D, pane: Pane, r: PriceRange, plotW: number, arr: number[], color: Hex, lo: number, hi: number, width = 1): void {
    const b = this._state.input.series
    ctx.strokeStyle = css(color)
    ctx.lineWidth = width
    ctx.lineJoin = 'round'
    ctx.beginPath()
    const map = new PriceMapping(r, effectivePriceMode(this._state))
    let on = false
    for (let i = lo; i <= hi && i < arr.length; i++) {
      const v = arr[i]
      if (!Number.isFinite(v)) { on = false; continue }
      const px = this.x(b.time(i), plotW), py = map.y(v, pane)
      if (on) ctx.lineTo(px, py); else { ctx.moveTo(px, py); on = true }
    }
    ctx.stroke()
  }

  private directedLine(ctx: CanvasRenderingContext2D, pane: Pane, r: PriceRange, plotW: number, arr: number[], dir: number[], lo: number, hi: number, width = 1.5): void {
    const b = this._state.input.series, t = this.colors
    const map = new PriceMapping(r, this._state.viewport.price.mode)
    ctx.lineWidth = width
    ctx.lineJoin = 'round'
    let i = lo
    while (i <= hi) {
      if (!(i < arr.length && i < dir.length && Number.isFinite(arr[i]) && Number.isFinite(dir[i]) && dir[i] !== 0)) { i += 1; continue }
      const rising = dir[i] > 0
      ctx.strokeStyle = css(rising ? t.up : t.down)
      ctx.beginPath()
      let on = false
      while (i <= hi && i < arr.length) {
        const v = arr[i]
        const d = i < dir.length ? dir[i] : NaN
        if (!Number.isFinite(v) || !Number.isFinite(d) || d === 0 || (d > 0) !== rising) break
        const px = this.x(b.time(i), plotW), py = map.y(v, pane)
        if (on) ctx.lineTo(px, py); else { ctx.moveTo(px, py); on = true }
        i += 1
      }
      ctx.stroke()
    }
  }

  private dots(ctx: CanvasRenderingContext2D, pane: Pane, r: PriceRange, L: Layout, arr: number[], dir: number[], lo: number, hi: number): void {
    const b = this._state.input.series, t = this.colors
    const map = new PriceMapping(r, this._state.viewport.price.mode)
    // 点子跟着蜡烛疏密走，但不许小到看不见，也不许大到连成一条带。
    const size = Math.max(1.5, Math.min(3.5, this.spacing(L.plotW) * 0.3))
    const rising: [number, number][] = [], falling: [number, number][] = []
    for (let i = lo; i <= hi && i < arr.length; i++) {
      if (!(Number.isFinite(arr[i]) && i < dir.length && Number.isFinite(dir[i]) && dir[i] !== 0)) continue
      const c: [number, number] = [this.x(b.time(i), L.plotW), map.y(arr[i], pane)]
      if (dir[i] > 0) rising.push(c); else falling.push(c)
    }
    for (const [pts, color] of [[rising, t.up], [falling, t.down]] as [[number, number][], Hex][]) {
      if (!pts.length) continue
      ctx.fillStyle = css(color)
      ctx.beginPath()
      for (const [cx, cy] of pts) { ctx.moveTo(cx + size / 2, cy); ctx.arc(cx, cy, size / 2, 0, Math.PI * 2) }
      ctx.fill()
    }
  }

  private drawOverlays(ctx: CanvasRenderingContext2D, pane: Pane, r: PriceRange, L: Layout, _s: number): void {
    const t = this.colors
    const { lo, hi } = this.visible()
    ctx.save()
    ctx.beginPath(); ctx.rect(0, pane.y, L.plotW, pane.h); ctx.clip()
    for (const id of this._state.input.overlays) {
      const v = this.displayed(id)
      if (!v) continue
      switch (id) {
        case 'MA': case 'EMA':
          v.lines.forEach((a, k) => this.line(ctx, pane, r, L.plotW, a, this.indicatorColor(id, k), lo, hi))
          break
        case 'BOLL':
          if (v.lines.length < 3) break
          this.line(ctx, pane, r, L.plotW, v.lines[1], t.band, lo, hi)
          this.line(ctx, pane, r, L.plotW, v.lines[0], t.amber, lo, hi)
          this.line(ctx, pane, r, L.plotW, v.lines[2], t.band, lo, hi)
          break
        case 'VWAP':
          if (v.lines[0]) this.line(ctx, pane, r, L.plotW, v.lines[0], this.indicatorColor(id, 0), lo, hi)
          break
        case 'ST':
          if (v.lines[0]) this.directedLine(ctx, pane, r, L.plotW, v.lines[0], v.dir ?? [], lo, hi)
          break
        case 'SAR':
          if (v.lines[0]) this.dots(ctx, pane, r, L, v.lines[0], v.dir ?? [], lo, hi)
          break
        default: break
      }
    }
    ctx.restore()
  }

  // ---------------------------------------------------------------- 画线

  drawDrawings(ctx: CanvasRenderingContext2D, pane: Pane, r: PriceRange, L: Layout, s: number): void {
    const st = this._state
    if (!st.input.options.drawings && !this.guestDrawings.length) return
    ctx.save()
    ctx.beginPath(); ctx.rect(0, pane.y, L.plotW, pane.h); ctx.clip()
    const axes = new DrawAxes({ layout: L, pane, range: r, mode: st.viewport.price.mode, view: st.viewport.view, decimals: st.input.decimals })
    ctx.save()
    // Swift 用透明层整体压 0.35；Canvas 没有透明层，逐笔压同一个透明度（交叠处略深，肉眼看不出）。
    if (this.ownDimmed) ctx.globalAlpha = 0.35
    if (st.input.options.drawings) {
      for (const d of st.overlay.drawings) {
        if (d.id === st.overlay.drawingPreviewID) continue
        paintDrawing(d, ctx, axes, this.colors, st.input.series, s)
      }
    }
    ctx.restore()
    for (const d of this.guestDrawings) paintDrawing(d, ctx, axes, this.colors, st.input.series, s)
    ctx.restore()
  }

  // ---------------------------------------------------------------- 盘口（+Depth）

  depthEnvelope(pane: Pane, range: PriceRange, L: Layout): Rect | null {
    const st = this._state, book = st.overlay.depth, b = st.input.series
    if (!book || book.symbol !== st.input.symbol.symbol.toUpperCase() || b.isEmpty) return null
    const price = b.close[b.count - 1]
    let largest = 0
    for (const l of book.bids) largest = Math.max(largest, l.quantity)
    for (const l of book.asks) largest = Math.max(largest, l.quantity)
    const height = 69
    if (!(largest > 0) || pane.h < height || !(L.plotW > 0)) return null
    const priceY = coreYOf(price, pane, range, st.viewport.price.mode)
    if (!Number.isFinite(priceY)) return null
    const top = Math.max(pane.y, Math.min(pane.y + pane.h - height, priceY - height / 2))
    const maxWidth = Math.min(64, L.plotW)
    return { x: L.plotW - maxWidth, y: top, w: maxWidth, h: height }
  }

  depthRows(pane: Pane, range: PriceRange, L: Layout): { frame: Rect; color: Hex }[] {
    const envelope = this.depthEnvelope(pane, range, L), book = this._state.overlay.depth
    if (!envelope || !book) return []
    let largest = 0
    for (const l of [...book.bids, ...book.asks]) largest = Math.max(largest, l.quantity)
    const rowHeight = 6, gap = 1
    const top = envelope.y, maxWidth = envelope.w
    // 卖一、买一紧邻中间的空隙；缺档保持空行，不拿另一侧补足。
    const rows: [number, number, Hex][] = [
      ...book.asks.map((l, k) => [4 - k, l.quantity, this.colors.down] as [number, number, Hex]),
      ...book.bids.map((l, k) => [5 + k, l.quantity, this.colors.up] as [number, number, Hex]),
    ].sort((a, b) => a[0] - b[0])
    return rows.map(([slot, q, color]) => {
      const width = Math.min(maxWidth, Math.max(2, maxWidth * Math.sqrt(q / largest)))
      return { frame: { x: L.plotW - width, y: top + slot * (rowHeight + gap), w: width, h: rowHeight }, color }
    })
  }

  drawDepth(ctx: CanvasRenderingContext2D, pane: Pane, range: PriceRange, L: Layout): number {
    const rows = this.depthRows(pane, range, L)
    if (!rows.length) return 0
    ctx.save()
    ctx.beginPath(); ctx.rect(0, pane.y, L.plotW, pane.h); ctx.clip()
    ctx.globalAlpha = 0.55
    for (const row of rows) {
      ctx.fillStyle = css(row.color)
      ctx.fillRect(row.frame.x, row.frame.y, row.frame.w, row.frame.h)
    }
    ctx.restore()
    return rows.length
  }

  // ---------------------------------------------------------------- 最新价

  drawLastPrice(ctx: CanvasRenderingContext2D, pane: Pane, r: PriceRange, L: Layout, s: number): void {
    // 关掉实时价格线：那条横线和右轴胶囊一起没有，挂在胶囊底下的倒计时自然也没有。
    const st = this._state
    if (!st.input.options.lastLine) return
    const b = st.input.series, t = this.colors
    const i = b.count - 1
    const p = b.close[i]
    const y = Math.max(pane.y + 8, Math.min(pane.y + pane.h - 8, this.yOf(p, pane, r)))
    const up = b.close[i] >= b.open[i]
    const col = up ? t.up : t.down

    ctx.save()
    ctx.setLineDash([3, 2])
    ctx.strokeStyle = css(col); ctx.lineWidth = 2 / s
    ctx.beginPath(); ctx.moveTo(0, snap(y, s)); ctx.lineTo(L.plotW, snap(y, s)); ctx.stroke()
    ctx.restore()

    const label = this.axisLabel(p, r)
    const chip = this.axisChip(L, label)
    const h = 15
    // 闪的那 150ms：底色换成这一口的方向色，再提亮一层。平时照旧按这根 K 线的涨跌上色。
    fillRoundRect(ctx, chip.x, y - h / 2, chip.w, h, 3, this.priceFlash ? (this.priceFlash === 'up' ? t.up : t.down) : col)
    if (this.priceFlash) fillRoundRect(ctx, chip.x, y - h / 2, chip.w, h, 3, '#FFFFFF52')
    drawCentered(ctx, label, chip.x + chip.w / 2, y, ChartFont.axis, t.chip)
    this.drawCountdown(ctx, L, y + h / 2, chip.w)
  }

  private drawCountdown(ctx: CanvasRenderingContext2D, L: Layout, belowY: number, width: number): void {
    const st = this._state
    const now = st.overlay.nowMs
    if (!st.input.options.countdown || now == null) return
    const text = this.countdownText(now)
    if (text == null) return
    const t = this.colors
    const h = 13
    const y = belowY + 2 + h <= L.timeY ? belowY + 2 : Math.max(0, belowY - 15 - 2 - h)
    if (y + h > L.timeY) return // 顶到时间轴上就不画了
    const chip = this.axisChip(L, text, ChartFont.tiny, width)
    fillRoundRect(ctx, chip.x, y, chip.w, h, 3, t.crossBg)
    drawCentered(ctx, text, chip.x + chip.w / 2, y + h / 2, ChartFont.tiny, t.crossInk)
  }

  countdownText(now: number): string | null {
    const b = this._state.input.series
    if (b.count <= 0) return null
    const open = b.time(b.count - 1)
    const close = isIrregular(b.interval) ? advancing(b.interval, open, 1) : open + b.step
    return fmtCountdown(close - now)
  }

  countdownTemplate(): string | null {
    const st = this._state
    if (!st.input.options.countdown || st.input.series.count <= 0) return null
    // 不等距周期的剩余时间最长能到一整个日历月 / 年（31 天、366 天），名义步长探不到。
    const day = 86_400_000
    const iv = st.input.series.interval
    const step = iv === '1M' ? 31 * day : iv === '1y' ? 366 * day : st.input.series.step
    const probes = [step, 86_400_000, 86_399_000, 3_600_000, 3_599_000].filter(x => x > 0 && x <= step)
    let best: string | null = null, bestW = -Infinity
    for (const p of probes) {
      const text = fmtCountdown(p)
      if (text == null) continue
      const w = textWidth(text, ChartFont.tiny)
      // Swift max(by: <) 并列时取最后一个
      if (w >= bestW) { best = text; bestW = w }
    }
    return best
  }

  // ---------------------------------------------------------------- 开高低收框

  drawCandleData(ctx: CanvasRenderingContext2D, L: Layout, index: number, selectedX: number): void {
    const st = this._state
    if (st.input.options.dataDisplay === 'top') return
    const b = st.input.series, d = st.input.decimals
    const lines = [
      fmtFull(b.time(index), st.input.tzOffset),
      '开 ' + fmtNum(b.open[index], d), '高 ' + fmtNum(b.high[index], d),
      '低 ' + fmtNum(b.low[index], d), '收 ' + fmtNum(b.close[index], d),
      '量 ' + this.amountNumber(b.volume[index]),
    ]
    let wantedW = 0
    for (const l of lines) wantedW = Math.max(wantedW, textWidth(l, ChartFont.axis))
    wantedW += 16
    const box = CandleDataBox.rect(L.plotW, L.mainH, selectedX, wantedW, lines.length * 14 + 12, this.mainLegendInset(L.plotW) + 4)
    ctx.save()
    ctx.beginPath(); ctx.rect(box.x, box.y, box.width, box.height); ctx.clip()
    ctx.fillStyle = css(this.colors.bg); ctx.fillRect(box.x, box.y, box.width, box.height)
    ctx.strokeStyle = css(this.colors.axis); ctx.lineWidth = 1
    ctx.strokeRect(box.x + 0.5, box.y + 0.5, box.width - 1, box.height - 1)
    const rowHeight = Math.min(14, (box.height - 8) / lines.length)
    lines.forEach((text, row) => {
      drawLeft(ctx, text, box.x + 8, box.y + 5 + rowHeight * (row + 0.5), ChartFont.axis, this.colors.text)
    })
    ctx.restore()
  }
}
