// 移植自 KanpanCore/Geometry/*.swift（Constants、ViewWindow、Clamp、CandleWidths、Fling、ViewTransition、
// Layout、PriceScale、Ticks）与 Chart/AICoinBehavior.swift、Chart/ChartOptions.swift
//
// 纯函数，不碰 DOM。坐标一律是 CSS 像素（对应 iOS 的 pt），scale = devicePixelRatio。

import { BarSeries, jsRound } from './series'

/** Swift 的 `.rounded()`（四舍五入、.5 远离零），和 JS 的 Math.round 在负数 .5 上不一样。 */
export const swiftRound = (x: number): number => (x < 0 ? -Math.round(-x) : Math.round(x))

// ------------------------------------------------------------------ AICoinBehavior

export const AICoinBehavior = {
  initialSpacing: 4.0,
  minimumSpacing: 1.6,
  maximumSpacing: 40.0,
  axisWidth: 50.0,
  axisLabelPadding: 4.0,
  axisMinWidth: 24.0,
  axisChipInset: 2.0,
  axisChipPadding: 2.0,
  timeHeight: 17.0,
  rightInset: 0.0,
  mainTopInset: 24.0,
  mainBottomInset: 8.0,
  subpanels: ['vol', 'oi', 'macd'] as string[],
} as const

export type NarrowRendering = 'closeLine' | 'highLow' | 'candle'
export function rendering(spacing: number, scale: number): NarrowRendering {
  const px = spacing * scale
  return px < 5 ? 'closeLine' : px < 7 ? 'highLow' : 'candle'
}

export function axisZoom(start: number, dy: number, height: number): number {
  const value = Math.min(16, Math.max(0.03, start * Math.pow(2, -dy / Math.max(height / 4, 1))))
  return Math.abs(value - 1) <= 0.02 ? 1 : value
}

// ------------------------------------------------------------------ Chart 常量

export const Chart = {
  minBarSpacing: AICoinBehavior.minimumSpacing,
  maxBarSpacing: 40,
  priceLabelPx: 46,
  timeLabelPx: 74,
  hitHandlePt: 9.5,
  hitLinePt: 9.5,
  drawLabelLineH: 13,
  loadMoreBars: 200,
} as const

// ------------------------------------------------------------------ ChartOptions

export type CandleKind = 'candle' | 'heikin' | 'line'
export type GridChoice = 'style' | 'on' | 'off'
export type BodyChoice = 'solid' | 'hollowUp'
export type PriceBias = 'up' | 'center' | 'down'
export type ViewAnchor = 'left' | 'center' | 'right'
export type CandleDataDisplay = 'inside' | 'top' | 'follow'
export type CrossPriceMode = 'selected' | 'close'

export interface ChartOptions {
  kind: CandleKind
  grid: GridChoice
  body: BodyChoice
  lastLine: boolean
  drawings: boolean
  countdown: boolean
  sinceChange: boolean
  bias: PriceBias
  anchor: ViewAnchor
  dataDisplay: CandleDataDisplay
  crossPrice: CrossPriceMode
  allowMainInversion: boolean
  allowSubInversion: boolean
  adaptiveIndicators: boolean
  portraitHeight: number
}

export const defaultChartOptions = (): ChartOptions => ({
  kind: 'candle', grid: 'off', body: 'solid', lastLine: true, drawings: true, countdown: false,
  sinceChange: false, bias: 'center', anchor: 'right', dataDisplay: 'inside', crossPrice: 'selected',
  allowMainInversion: false, allowSubInversion: false, adaptiveIndicators: false, portraitHeight: 0.5,
})

// ------------------------------------------------------------------ ViewWindow

export class ViewWindow {
  constructor(public to: number, public span: number) {}
  static fromTo(from: number, to: number): ViewWindow { return new ViewWindow(to, to - from) }
  get from(): number { return this.to - this.span }
  x(t: number, plotW: number): number { return (t - this.from) / this.span * plotW }
  t(x: number, plotW: number): number { return this.from + x / plotW * this.span }
  barSpacing(step: number, plotW: number): number { return plotW / (this.span / step) }
  shifted(dx: number, plotW: number): ViewWindow { return new ViewWindow(this.to + dx / plotW * this.span, this.span) }
  dragged(fingerDx: number, plotW: number): ViewWindow { return this.shifted(-fingerDx, plotW) }
  equals(o: ViewWindow | null | undefined): boolean { return !!o && o.to === this.to && o.span === this.span }
}

// ------------------------------------------------------------------ Clamp / ViewMath

export function clampView(v: ViewWindow, series: BarSeries, plotW: number, anchor: ViewAnchor = 'right'): ViewWindow {
  if (series.isEmpty || !(plotW > 0)) return v
  const step = series.step
  const span = Math.max(plotW / AICoinBehavior.maximumSpacing * step, Math.min(plotW / AICoinBehavior.minimumSpacing * step, v.span))
  const spacing = plotW / span * step
  const first = series.firstTime - step / 2
  const maximumOffset = ViewMath.maximumOffset(series.count, spacing, plotW, anchor)
  const offset = (v.to - span - first) / step * spacing
  const clampedOffset = Math.max(0, Math.min(maximumOffset, offset))
  return new ViewWindow(first + clampedOffset / spacing * step + span, span)
}

export const ViewMath = {
  /** 拖过头时的橡皮筋：越拉越重，最多 min(32, plotW·0.1)。 */
  dragging(proposed: ViewWindow, series: BarSeries, plotW: number, anchor: ViewAnchor = 'right'): ViewWindow {
    const settled = clampView(proposed, series, plotW, anchor)
    if (series.isEmpty || !(plotW > 0) || !(settled.span > 0)) return settled
    const beyond = (proposed.to - settled.to) / settled.span * plotW
    if (beyond === 0 || !Number.isFinite(beyond)) return settled
    const extent = Math.min(32, plotW * 0.1)
    const pull = extent * (1 - 1 / (1 + 0.55 * Math.abs(beyond) / extent))
    return new ViewWindow(settled.to + (beyond > 0 ? pull : -pull) / plotW * settled.span, settled.span)
  },

  maximumOffset(count: number, spacing: number, plotW: number, anchor: ViewAnchor): number {
    const total = Math.max(0, (count + 400) * spacing - plotW)
    const reserved = Math.min(400 * spacing - ViewMath.rightInset(anchor, plotW), total)
    return Math.max(0, total - reserved)
  },

  rightInset(anchor: ViewAnchor, plotW: number): number {
    switch (anchor) {
      case 'right': return AICoinBehavior.rightInset
      case 'center': return Math.floor(plotW / 2)
      case 'left': return 2 * Math.floor(plotW / 3)
    }
  },

  reset(series: BarSeries, plotW: number, spacing: number, anchor: ViewAnchor = 'right'): ViewWindow {
    if (series.isEmpty) return ViewWindow.fromTo(0, 1)
    const w = Math.min(AICoinBehavior.maximumSpacing, Math.max(AICoinBehavior.minimumSpacing, spacing))
    const step = series.step
    const view = new ViewWindow(series.lastTime + step / 2 + ViewMath.rightInset(anchor, plotW) / w * step, plotW / w * step)
    return clampView(view, series, plotW, anchor)
  },

  resized(v: ViewWindow, series: BarSeries, plotW: number, spacing: number, anchor: ViewAnchor = 'right'): ViewWindow {
    if (series.isEmpty) return v
    return clampView(new ViewWindow(v.to, plotW / spacing * series.step), series, plotW, anchor)
  },

  switchInterval(series: BarSeries, plotW: number, spacing: number, anchorRight: number | null): ViewWindow {
    const latest = ViewMath.reset(series, plotW, spacing)
    if (anchorRight == null || series.isEmpty) return latest
    return clampView(new ViewWindow(Math.min(anchorRight, latest.to), latest.span), series, plotW)
  },

  scaled(v: ViewWindow, series: BarSeries, plotW: number, factor: number, focus: number, anchor: ViewAnchor = 'right'): ViewWindow {
    if (!(factor > 0) || !Number.isFinite(factor) || series.isEmpty) return v
    const oldW = v.barSpacing(series.step, plotW)
    const newW = Math.min(AICoinBehavior.maximumSpacing, Math.max(AICoinBehavior.minimumSpacing, oldW * factor))
    const oldRight = ViewMath.reset(series, plotW, oldW, anchor)
    const offset = (v.from - series.firstTime) / series.step * oldW + oldW / 2
    if (Math.abs(v.to - oldRight.to) / v.span * plotW < 0.5) return ViewMath.reset(series, plotW, newW, anchor)
    const pin = offset <= 0.5 ? 0 : focus
    const span = plotW / newW * series.step
    const time = v.t(pin, plotW)
    return clampView(ViewWindow.fromTo(time - pin / plotW * span, time + (1 - pin / plotW) * span), series, plotW, anchor)
  },

  needsMoreHistory(v: ViewWindow, series: BarSeries): boolean {
    return !series.isEmpty && v.from <= series.firstTime + Chart.loadMoreBars * series.step
  },
}

/**
 * 新末根到货时视野跟不跟（AICoinBehavior.reconcile 的判据，网页放宽了一档）：
 * - 贴着最新（右缘离「最新」不到一根）——照 iOS 跟；
 * - 或者末根还在视野里（`to ≥ 旧末根`，和「回到最新」按钮不出现是同一个口径）——也跟。
 *   用户眼里「按钮没出来」就是在看最新；原来只认前一条，右缘因为补缺口、换宽度漂开过一根就再也不跟，
 *   静止看盘到新的一根开出来，新蜡烛落在右缘外、只剩现价线。
 * 跟的时候右缘不超过「最新」：漂到最新右边的（补缺口时 REST 末页比推送旧一根）顺手收回去。
 */
function followed(view: ViewWindow, old: BarSeries, nextLastTime: number, plotW: number, anchor: ViewAnchor): ViewWindow {
  if (old.isEmpty || !(nextLastTime > old.lastTime) || !(plotW > 0)) return view
  const spacing = view.barSpacing(old.step, plotW)
  const latest = ViewMath.reset(old, plotW, spacing, anchor)
  const near = Math.abs(view.to - latest.to) / view.span * plotW < spacing
  if (!near && !(view.to >= old.lastTime)) return view
  return new ViewWindow(Math.min(view.to, latest.to) + (nextLastTime - old.lastTime), view.span)
}

/** AICoinBehavior.reconcile：只有视图停在最新一根时，新来的尾巴才把视图往前推。 */
export function reconcile(view: ViewWindow, old: BarSeries, next: BarSeries, plotW: number, anchor: ViewAnchor = 'right'): ViewWindow {
  if (old.isEmpty || next.isEmpty || old.symbol !== next.symbol || old.interval !== next.interval) return view
  return followed(view, old, next.lastTime, plotW, anchor)
}

/**
 * reconcile 的「原地改」版：BarSeries 在网页里是原地改的，改完就拿不到旧的那一份了，
 * 所以在 upsert 之前、拿旧 series 与新末根的时间调用（判据与 reconcile 相同）。
 */
export function reconcileBeforeUpsert(view: ViewWindow, old: BarSeries, nextLastTime: number, plotW: number, anchor: ViewAnchor = 'right'): ViewWindow {
  return followed(view, old, nextLastTime, plotW, anchor)
}

// ------------------------------------------------------------------ CandleWidths

export interface CandleWidth { body: number; wick: number }
export interface CandleMetrics { bodyW: number; wickW: number; minBody: number; outline: number; thin: boolean }

export function evenUp(raw: number, body: number, wick: number): number {
  let b = body
  if (((b % 2) + 2) % 2 !== ((wick % 2) + 2) % 2) {
    const up = b + 1, down = b - 1
    b = (down >= wick && Math.abs(raw - down) <= Math.abs(raw - up)) ? down : up
  }
  return Math.max(b, wick)
}

export const wickPixels = (scale: number): number => Math.max(1, swiftRound(Math.max(1, scale) * 2 / 3))

export function candlePixels(spacing: number, scale: number): CandleWidth {
  const ratio = Number.isFinite(scale) && scale > 0 ? scale : 1
  const sp = Number.isFinite(spacing) && spacing > 0 ? spacing : 0
  const raw = sp * (2 / 3) * ratio
  const cell = Math.floor(sp * ratio)
  const wick = Math.min(wickPixels(ratio), Math.max(1, cell - 1))
  const cap = Math.max(wick, cell - 1)
  let body = raw < 2 ? wick : Math.max(1, jsRound(raw))
  body = Math.min(body, cap)
  body = evenUp(raw, body, wick)
  if (body > cap) body = Math.max(wick, body - 2)
  return { body, wick }
}

export function candleMetrics(spacing: number, scale: number): CandleMetrics {
  const w = candlePixels(spacing, scale)
  const cell = Math.floor(spacing * scale)
  return {
    bodyW: w.body / scale, wickW: w.wick / scale, minBody: 1 / scale, outline: 1 / scale,
    thin: cell - 1 <= w.wick || w.body <= w.wick,
  }
}

export const wickLineWidth = (scale: number): number => wickPixels(scale) / scale
export const snap = (x: number, scale: number): number => swiftRound(x * scale) / scale
export const hairline = (y: number, scale: number): number => (swiftRound(y * scale) + 0.5) / scale

// ------------------------------------------------------------------ Fling（Android OverScroller 样条）

const FLING_POSITION: number[] = (() => {
  const out: number[] = []
  for (let i = 0; i <= 100; i++) {
    if (i === 100) { out.push(1); break }
    const time = i / 100
    let lo = 0, hi = 1, x = 0
    for (let k = 0; k < 32; k++) {
      x = (lo + hi) / 2
      const tx = 3 * x * (1 - x) * ((1 - x) * 0.175 + x * 0.35) + x * x * x
      if (tx < time) lo = x; else hi = x
    }
    out.push(3 * x * (1 - x) * ((1 - x) * 0.5 + x) + x * x * x)
  }
  return out
})()

export class FlingCurve {
  readonly durationMs: number
  readonly distance: number
  constructor(speedPointsPerSecond: number) {
    const v = speedPointsPerSecond
    const rate = Math.log(0.78) / Math.log(0.9)
    const physical = 9.80665 * 39.37 * 160 * 0.84
    const friction = 0.015
    const speed = Math.min(8000, Math.abs(v))
    if (!(speed > 0) || !Number.isFinite(speed)) { this.durationMs = 0; this.distance = 0; return }
    const l = Math.log(0.35 * speed / (friction * physical))
    this.durationMs = Math.floor(1000 * Math.exp(l / (rate - 1)))
    this.distance = (v < 0 ? -1 : 1) * Math.floor(friction * physical * Math.exp(rate * l / (rate - 1)))
  }
  sample(elapsedMs: number): { pastPx: number; done: boolean } {
    if (!(this.durationMs > 0) || !(elapsedMs < this.durationMs)) return { pastPx: this.distance, done: true }
    if (elapsedMs <= 0) return { pastPx: 0, done: false }
    const t = elapsedMs / this.durationMs * 100
    const i = Math.min(99, Math.floor(t)), f = t - i
    const p = FLING_POSITION[i] + (FLING_POSITION[i + 1] - FLING_POSITION[i]) * f
    return { pastPx: swiftRound(this.distance * p), done: false }
  }
}

export class FlingRun {
  readonly curve: FlingCurve
  private constructor(v: number, readonly start: ViewWindow, readonly plotW: number) {
    this.curve = new FlingCurve(v * 1000)
  }
  /** v：px/ms。太慢（< 50 px/s）不起惯性，返回 null。 */
  static make(v: number, start: ViewWindow, plotW: number): FlingRun | null {
    if (!Number.isFinite(v) || !(Math.abs(v * 1000) > 50) || !(plotW > 0)) return null
    return new FlingRun(v, start, plotW)
  }
  frame(elapsedMs: number): { view: ViewWindow; done: boolean } {
    const s = this.curve.sample(elapsedMs)
    return { view: this.start.dragged(s.pastPx, this.plotW), done: s.done }
  }
}

export class VelocityTracker {
  private samples: { t: number; x: number }[] = []
  constructor(readonly windowMs = 100) {}
  add(x: number, t: number): void {
    this.samples.push({ t, x })
    while (this.samples.length && t - this.samples[0].t > this.windowMs) this.samples.shift()
  }
  reset(): void { this.samples.length = 0 }
  get velocity(): number {
    const a = this.samples[0], b = this.samples[this.samples.length - 1]
    if (!a || !b || !(b.t > a.t)) return 0
    return (b.x - a.x) / (b.t - a.t)
  }
}

// ------------------------------------------------------------------ ViewTransition

export const ViewTransition = {
  rebound(a: ViewWindow, b: ViewWindow, elapsedMs: number): { view: ViewWindow; done: boolean } {
    const t = Math.max(0, Math.min(1, elapsedMs / 320))
    if (!(t < 1)) return { view: b, done: true }
    const remaining = (1 + 9 * t) * Math.exp(-9 * t)
    return { view: new ViewWindow(b.to + (a.to - b.to) * remaining, b.span), done: false }
  },
  frame(a: ViewWindow, b: ViewWindow, elapsedMs: number): { view: ViewWindow; done: boolean } {
    const t = Math.max(0, Math.min(1, elapsedMs / 200))
    const e = t * t * (3 - 2 * t)
    return { view: ViewWindow.fromTo(a.from + (b.from - a.from) * e, a.to + (b.to - a.to) * e), done: t >= 1 }
  },
}

// ------------------------------------------------------------------ Layout

export interface Pane {
  /** null = 主图。 */
  indicator: string | null
  y: number
  h: number
}
export const isMainPane = (p: Pane): boolean => p.indicator == null

export class Layout {
  readonly W: number
  readonly H: number
  readonly plotW: number
  readonly mainH: number
  readonly subH: number
  readonly timeY: number
  readonly panes: Pane[]

  constructor(W: number, H: number, subs: string[], subScale: Record<string, number> = {}, mainWeight = 3, axisWidth: number = AICoinBehavior.axisWidth) {
    this.W = W
    this.H = H
    this.plotW = Math.max(40, W - axisWidth)
    const content = Math.max(1, H - AICoinBehavior.timeHeight)
    const weights = subs.map(id => {
      const raw = subScale[id] ?? 1
      return Number.isFinite(raw) ? Math.min(2, Math.max(0.5, raw)) : 0.5
    })
    const sum = weights.reduce((a, b) => a + b, 0)
    const unit = content / (Math.max(0.5, mainWeight) + sum)
    this.mainH = content - sum * unit
    this.timeY = this.mainH
    this.subH = weights.length ? weights[0] * unit : unit
    const list: Pane[] = [{ indicator: null, y: 0, h: this.mainH }]
    let y = this.mainH + AICoinBehavior.timeHeight
    subs.forEach((id, i) => {
      const height = weights[i] * unit
      list.push({ indicator: id, y, h: height })
      y += height
    })
    this.panes = list
  }

  get main(): Pane { return this.panes[0] }
  get axisW(): number { return this.W - this.plotW }

  get autoFitButton(): { x: number; y: number; w: number; h: number } {
    return { x: this.plotW + Math.max(2, (this.axisW - 16) / 2), y: Math.max(0, this.mainH - 42), w: 16, h: 17 }
  }

  hitsAutoFit(x: number, y: number): boolean {
    const b = this.autoFitButton
    const pad = Math.max(0, (44 - b.w) / 2)
    return x >= b.x - pad && x <= b.x + b.w + pad && y >= b.y - pad && y <= b.y + b.h + pad
  }
}

export const ChartContentLayout = {
  height(viewport: number, subs: number, portrait: boolean): number {
    return Math.max(viewport, (portrait ? 120 : 72) + subs * (portrait ? 40 : 28) + AICoinBehavior.timeHeight)
  },
  mainWeight(height: number, control: number, count: number): number {
    if (count <= 0) return 3
    const setting = Number.isFinite(control) ? Math.min(1, Math.max(0, control)) : 0.5
    const content = Math.max(1, height - AICoinBehavior.timeHeight)
    const minimumSub = Math.min(40, content / (count + 3))
    const preferred = 3 * (0.5 + setting)
    return Math.min(preferred, Math.max(0.5, content / minimumSub - count))
  },
}

export const CandleDataBox = {
  rect(plotWidth: number, mainHeight: number, selectedX: number, desiredWidth: number, desiredHeight: number,
    top: number = AICoinBehavior.mainTopInset + 4): { x: number; y: number; width: number; height: number } {
    const width = Math.max(1, Math.min(desiredWidth, plotWidth - 8))
    const height = Math.max(1, Math.min(desiredHeight, mainHeight - 8))
    const x = selectedX < plotWidth / 2 ? plotWidth - width - 4 : 4
    const y = Math.max(4, Math.min(top, mainHeight - height - 4))
    return { x: Math.max(0, x), y, width, height }
  },
}

export const ChartGestureRoute = {
  reorderPane(x: number, y: number, plotWidth: number, panes: Pane[]): string | null {
    if (!(x >= 0 && x < plotWidth)) return null
    return panes.find(p => p.indicator != null && y >= p.y && y < p.y + p.h)?.indicator ?? null
  },
  pageScroll(x: number, y: number, dx: number, dy: number, touches: number, plotWidth: number, mainHeight: number, manualY: boolean, selecting: boolean): boolean {
    if (touches !== 1 || selecting || !(Math.abs(dy) > 1.5 * Math.abs(dx))) return false
    if (y < mainHeight && (x > plotWidth || manualY)) return false
    return true
  },
}

export const SubPaneResize = {
  scale(initialHeight: number, translation: number, contentHeight: number, otherWeight: number): number {
    if (!(contentHeight > 0) || !Number.isFinite(translation) || !(otherWeight > 0)) return 1
    const desired = Math.min(contentHeight - 1, Math.max(1, initialHeight + translation))
    return Math.min(2, Math.max(0.5, desired * otherWeight / (contentHeight - desired)))
  },
}

// ------------------------------------------------------------------ PriceScale

export type PriceMode = 'linear' | 'log' | 'percent'

export function forward(mode: PriceMode, p: number, base: number): number {
  switch (mode) {
    case 'linear': return p
    case 'log': return Math.log(Math.max(1e-12, p))
    case 'percent': return (p / base - 1) * 100
  }
}
export function inverse(mode: PriceMode, f: number, base: number): number {
  switch (mode) {
    case 'linear': return f
    case 'log': return Math.exp(f)
    case 'percent': return (f / 100 + 1) * base
  }
}

export interface PriceRange { lo: number; hi: number; base: number; inverted: boolean }

export interface PriceTransform { mode: PriceMode; inverted: boolean; zoom: number; centerFraction: number }
export const priceTransform = (mode: PriceMode = 'linear', zoom = 1, centerFraction = 0.5): PriceTransform =>
  ({ mode, inverted: false, zoom, centerFraction })
export const isManualTransform = (t: PriceTransform): boolean => t.zoom !== 1

export function clampedCenter(c: number, zoom: number): number {
  if (!Number.isFinite(zoom) || !(zoom > 0) || !(Math.abs(zoom - 1) > 0.02)) return 0.5
  const h = 1 / (2 * zoom), margin = zoom <= 1 ? 3.0 : 0.75
  const a = h - margin, b = 1 - h + margin
  return Math.max(Math.min(a, b), Math.min(Math.max(a, b), c))
}

export function visibleRange(view: ViewWindow, series: BarSeries): { lo: number; hi: number } {
  if (series.count <= 0) return { lo: 0, hi: 0 }
  if (!series.openTime.length) {
    const step = series.step, t0 = series.t0
    const lo = Math.min(series.count - 1, Math.max(0, Math.floor((view.from - t0) / step) - 1))
    const hi = Math.min(series.count - 1, Math.ceil((view.to - t0) / step) + 1)
    return { lo, hi: Math.max(lo, hi) }
  }
  const lo = Math.max(0, series.index(view.from) - 1)
  const hi = Math.min(series.count - 1, series.index(view.to) + 1)
  return { lo, hi: Math.max(lo, hi) }
}

export interface PriceRangeOptions {
  overlayValues?: number[][]
  drawingPrices?: number[]
  transform?: PriceTransform
  extraPrices?: number[]
  bias?: PriceBias
  paneHeight?: number
  topInset?: number
  anchorPrice?: number | null
  closeOnly?: boolean
}

export function priceRange(view: ViewWindow, series: BarSeries, o: PriceRangeOptions = {}): PriceRange {
  const overlayValues = o.overlayValues ?? [], drawingPrices = o.drawingPrices ?? [], extraPrices = o.extraPrices ?? []
  const transform = o.transform ?? priceTransform()
  const bias = o.bias ?? 'center', height = o.paneHeight ?? 300, topInset = o.topInset ?? AICoinBehavior.mainTopInset
  const { lo, hi } = visibleRange(view, series)
  const baseIndex = series.count > 0 ? series.index(view.from) : 0
  const candidateBase = series.count > 0 ? series.close[baseIndex] : 1
  const base = Number.isFinite(candidateBase) && candidateBase !== 0 ? candidateBase : 1
  let minV = Infinity, maxV = -Infinity
  if (series.count > 0) {
    if (o.closeOnly) {
      for (let i = lo; i <= hi; i++) {
        const c = series.close[i]
        if (!Number.isFinite(c)) continue
        if (c > maxV) maxV = c
        if (c < minV) minV = c
      }
    } else {
      for (let i = lo; i <= hi; i++) {
        if (series.high[i] > maxV) maxV = series.high[i]
        if (series.low[i] < minV) minV = series.low[i]
      }
    }
    for (const arr of overlayValues) {
      if (!(arr.length > lo)) continue
      const end = Math.min(hi, arr.length - 1)
      for (let i = lo; i <= end; i++) {
        const v = arr[i]
        if (!Number.isFinite(v)) continue
        if (v > maxV) maxV = v
        if (v < minV) minV = v
      }
    }
  }
  for (const p of drawingPrices) { if (p > maxV) maxV = p; if (p < minV) minV = p }
  for (const p of extraPrices) { if (!Number.isFinite(p)) continue; if (p > maxV) maxV = p; if (p < minV) minV = p }
  if (!Number.isFinite(minV) || !Number.isFinite(maxV)) { minV = 0; maxV = 1 }
  if (maxV === minV) { maxV = minV * 1.001 + 1; minV = minV * 0.999 - 1 }
  const mode = transform.mode
  if (mode === 'log') { minV = Math.max(minV, 1e-12); maxV = Math.max(maxV, minV * 1.001) }
  const low = forward(mode, minV, base), high = forward(mode, maxV, base)
  const top = Math.min(topInset, height * 0.4)
  const bottom = Math.min(AICoinBehavior.mainBottomInset, height * 0.1)
  const content = Math.max(1, height - top - bottom)
  const perPoint = (high - low) / content
  const totalInset = top + bottom
  const shiftInset = bias === 'up' ? totalInset * 0.25 : bias === 'down' ? -totalInset * 0.25 : 0
  const a = low - perPoint * (bottom + shiftInset)
  const z = high + perPoint * (top - shiftInset)
  const zoom = Math.min(16, Math.max(0.03, transform.zoom))
  const center = clampedCenter(transform.centerFraction, zoom)
  const autoLow = inverse(mode, a, base), autoHigh = inverse(mode, z, base)
  const mid = zoom === 1 ? (autoLow + autoHigh) / 2 : (o.anchorPrice ?? (autoLow + (autoHigh - autoLow) * center))
  const half = (autoHigh - autoLow) / (2 * zoom)
  const resultLow = mode === 'log' ? Math.max(autoLow * 0.001, mid - half) : mid - half
  return {
    lo: resultLow,
    hi: Math.max(resultLow + Math.max(Math.abs(resultLow) * 1e-9, 1e-9), mid + half),
    base, inverted: transform.inverted,
  }
}

export class PriceMapping {
  readonly base: number
  readonly a: number
  readonly z: number
  readonly inverted: boolean
  constructor(range: PriceRange, readonly mode: PriceMode) {
    this.base = range.base
    this.a = forward(mode, range.lo, range.base)
    this.z = forward(mode, range.hi, range.base)
    this.inverted = range.inverted
  }
  y(p: number, pane: Pane): number {
    const f = forward(this.mode, p, this.base)
    const fraction = (f - this.a) / (this.z - this.a)
    return pane.y + (this.inverted ? fraction : 1 - fraction) * pane.h
  }
}

export function yOf(p: number, pane: Pane, range: PriceRange, mode: PriceMode): number {
  const a = forward(mode, range.lo, range.base)
  const z = forward(mode, range.hi, range.base)
  const f = forward(mode, p, range.base)
  const fraction = (f - a) / (z - a)
  return pane.y + (range.inverted ? fraction : 1 - fraction) * pane.h
}

export function pOf(y: number, pane: Pane, range: PriceRange, mode: PriceMode): number {
  const a = forward(mode, range.lo, range.base)
  const z = forward(mode, range.hi, range.base)
  const fraction = (y - pane.y) / pane.h
  const f = a + (range.inverted ? fraction : 1 - fraction) * (z - a)
  return inverse(mode, f, range.base)
}

export function yOfValue(v: number, pane: Pane, lo: number, hi: number): number {
  if (!(hi > lo)) return pane.y + pane.h / 2
  return pane.y + pane.h - ((v - lo) / (hi - lo)) * pane.h
}

// ------------------------------------------------------------------ Ticks

export function niceStep(span: number, want: number): number {
  if (!(span > 0)) return 1
  const rough = span / Math.max(1, want)
  const mag = Math.pow(10, Math.floor(Math.log10(rough)))
  const n = rough / mag
  const step = n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10
  return step * mag
}

const TMIN = 60_000, THOUR = 3_600_000, TDAY = 86_400_000
export const timeSteps: number[] = [
  TMIN, 5 * TMIN, 15 * TMIN, 30 * TMIN, THOUR, 2 * THOUR, 4 * THOUR, 6 * THOUR, 12 * THOUR,
  TDAY, 2 * TDAY, 7 * TDAY, 14 * TDAY, 30 * TDAY, 90 * TDAY, 180 * TDAY, 365 * TDAY,
]

export function timeStep(spanMs: number, plotW: number, perLabelPx: number = Chart.timeLabelPx): number {
  const want = Math.max(2, Math.floor(plotW / perLabelPx))
  const rough = spanMs / want
  for (const s of timeSteps) if (s >= rough) return s
  return timeSteps[timeSteps.length - 1]
}

/** 上海时区：+480 分钟，没有夏令时（kanpan-timezone-shanghai）。 */
export const SHANGHAI_OFFSET_MIN = 480

export function timeTicks(view: ViewWindow, plotW: number, offsetMinutes: number = SHANGHAI_OFFSET_MIN, perLabelPx: number = Chart.timeLabelPx): { t: number; step: number }[] {
  const step = timeStep(view.span, plotW, perLabelPx)
  const shift = offsetMinutes * 60_000
  const out: { t: number; step: number }[] = []
  let t = Math.ceil((view.from + shift) / step) * step - shift
  while (t <= view.to) { out.push({ t, step }); t += step }
  return out
}

export function priceTicks(range: PriceRange, mode: PriceMode, paneH: number): number[] {
  const a = forward(mode, range.lo, range.base)
  const z = forward(mode, range.hi, range.base)
  if (!(z > a)) return []
  const step = niceStep(z - a, Math.max(2, Math.floor(paneH / Chart.priceLabelPx)))
  const out: number[] = []
  let f = Math.ceil(a / step) * step
  while (f <= z) { out.push(f); f += step }
  return out
}
