// 移植自 KanpanCore/Geometry/*.swift（Constants、ViewWindow、Clamp、CandleWidths、Fling、ViewTransition、
// Layout、PriceScale、Ticks）与 Chart/AICoinBehavior.swift、Chart/ChartOptions.swift
//
// 纯函数，不碰 DOM。坐标一律是 CSS 像素（对应 iOS 的 pt），scale = devicePixelRatio。

import { dateParts } from './format'
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
  /**
   * 主图叠加线（均线、布林带……）进不进价格轴的上下界（iOS `ChartState.overlaysAffectPriceRange`）。
   * 横屏画线台关掉：线照画（裁在主图里），轴只按 K 线定——MA256 一挂上量程被拉宽、K 线被压扁，
   * 画的线就和真正的价格结构对不上。
   */
  overlaysAffectPriceRange: boolean
}

export const defaultChartOptions = (): ChartOptions => ({
  kind: 'candle', grid: 'off', body: 'solid', lastLine: true, drawings: true, countdown: false,
  sinceChange: false, bias: 'center', anchor: 'right', dataDisplay: 'inside', crossPrice: 'selected',
  allowMainInversion: false, allowSubInversion: false, adaptiveIndicators: false, portraitHeight: 0.5,
  overlaysAffectPriceRange: true,
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
  // 能拖到的最右按「从第一根到最后一根占了多少格」算，不按根数：美元指数这类有休市空档的序列
  // （每天停一小时、周末停两天）根数远少于格数，按根数夹会把视野夹回一个多月前（照 iOS Clamp.swift 的 cells）
  const cells = Math.max(series.count, (series.lastTime - series.firstTime) / step + 1)
  const maximumOffset = ViewMath.maximumOffset(cells, spacing, plotW, anchor)
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

  maximumOffset(cells: number, spacing: number, plotW: number, anchor: ViewAnchor): number {
    const total = Math.max(0, (cells + 400) * spacing - plotW)
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

  /**
   * 只夹左右（视野在时间轴上的偏移），根宽原样不动（iOS ViewMath.clampedOffset）。
   * `clampView` = 先把根宽夹进 [1.6, 40]，再走这一步。
   */
  clampedOffset(v: ViewWindow, series: BarSeries, plotW: number, anchor: ViewAnchor = 'right'): ViewWindow {
    if (series.isEmpty || !(plotW > 0) || !(v.span > 0)) return v
    const step = series.step
    const span = v.span
    const spacing = plotW / span * step
    const first = series.firstTime - step / 2
    const cells = Math.max(series.count, (series.lastTime - series.firstTime) / step + 1)
    const maximumOffset = ViewMath.maximumOffset(cells, spacing, plotW, anchor)
    const offset = (v.to - span - first) / step * spacing
    const clamped = Math.max(0, Math.min(maximumOffset, offset))
    return new ViewWindow(first + clamped / spacing * step + span, span)
  },

  /** 按 `spacing` 摆到最新（末根 + 右留白），只夹左右、不夹根宽。 */
  latestView(series: BarSeries, plotW: number, spacing: number, anchor: ViewAnchor = 'right'): ViewWindow {
    const step = series.step
    return ViewMath.clampedOffset(
      new ViewWindow(series.lastTime + step / 2 + ViewMath.rightInset(anchor, plotW) / spacing * step, plotW / spacing * step),
      series, plotW, anchor)
  },

  /**
   * 视野是不是「贴着最新」：右缘离「末根 + 右留白」不到一格（iOS ViewMath.isPinnedToLatest，a8012401）。
   * 捏合只认这一条判据：贴着 → 末根钉住、两指中点的漂移不算数；不贴 → 绕两指中点缩放。
   */
  isPinnedToLatest(v: ViewWindow, series: BarSeries, plotW: number, anchor: ViewAnchor = 'right'): boolean {
    if (series.isEmpty || !(plotW > 0) || !(v.span > 0) || !Number.isFinite(v.span)) return false
    const spacing = plotW / v.span * series.step
    const latest = ViewMath.latestView(series, plotW, spacing, anchor)
    return Math.abs(v.to - latest.to) / v.span * plotW < spacing
  },

  /**
   * 捏合的一帧：根宽换成 `spacing`，左右照常夹（iOS ViewMath.pinched）。
   * - `pinned`：末根连同右留白钉在原处；
   * - 否则以 `focus`（两指中点，图区内的 x）为不动点；视野左缘已经顶着首根时以左缘为不动点。
   */
  pinched(v: ViewWindow, series: BarSeries, plotW: number, spacing: number, focus: number, pinned: boolean, anchor: ViewAnchor = 'right'): ViewWindow {
    if (series.isEmpty || !(plotW > 0) || !(v.span > 0) || !(spacing > 0) || !Number.isFinite(spacing)) return v
    if (pinned) return ViewMath.latestView(series, plotW, spacing, anchor)
    const step = series.step
    const oldW = plotW / v.span * step
    const offset = (v.from - series.firstTime) / step * oldW + oldW / 2
    const pin = offset <= 0.5 ? 0 : Math.max(0, Math.min(plotW, focus))
    const span = plotW / spacing * step
    const time = v.t(pin, plotW)
    return ViewMath.clampedOffset(ViewWindow.fromTo(time - pin / plotW * span, time + (1 - pin / plotW) * span), series, plotW, anchor)
  },

  /** 捏合软边越过去最多多少：根宽最多捏到 1.6 × 0.85、40 × 1.15，松手弹回 [1.6, 40]（iOS ViewMath.zoomOvershoot）。 */
  zoomOvershoot: 0.15,

  /**
   * 捏合软边：把「手指要的根宽」`raw` 换成「这一帧画出来的根宽」（iOS ViewMath.softSpacing，aedc26df）。
   * [1.6, 40] 之内原样；越过去带阻尼——越界那一点斜率是 1（不打顿），越往外越紧，渐近到 zoomOvershoot 那条线却够不着。
   * 对数空间里算，放大缩小两头手感对称。
   */
  softSpacing(raw: number): number {
    const lo = AICoinBehavior.minimumSpacing, hi = AICoinBehavior.maximumSpacing
    if (!Number.isFinite(raw) || !(raw > 0)) return lo
    if (raw > hi) {
      const room = Math.log(1 + ViewMath.zoomOvershoot), e = Math.log(raw / hi)
      return hi * Math.exp(room * (1 - 1 / (1 + e / room)))
    }
    if (raw < lo) {
      const room = -Math.log(1 - ViewMath.zoomOvershoot), e = Math.log(lo / raw)
      return lo / Math.exp(room * (1 - 1 / (1 + e / room)))
    }
    return raw
  },

  /** softSpacing 的反函数：画面上是 `soft` 这么宽时手指「要的」根宽（回弹半途又捏上去，从画面根宽倒推，不跳）。 */
  rawSpacingForSoft(soft: number): number {
    const lo = AICoinBehavior.minimumSpacing, hi = AICoinBehavior.maximumSpacing
    if (!Number.isFinite(soft) || !(soft > 0)) return lo
    if (soft > hi) {
      const room = Math.log(1 + ViewMath.zoomOvershoot), u = Math.log(soft / hi) / room
      if (!(u < 1)) return ViewMath.boundedRawSpacing(Infinity)
      return ViewMath.boundedRawSpacing(hi * Math.exp(room * u / (1 - u)))
    }
    if (soft < lo) {
      const room = -Math.log(1 - ViewMath.zoomOvershoot), u = Math.log(lo / soft) / room
      if (!(u < 1)) return ViewMath.boundedRawSpacing(0)
      return ViewMath.boundedRawSpacing(lo / Math.exp(room * u / (1 - u)))
    }
    return soft
  },

  /** 手指要的根宽最多攒到越界三倍阻尼宽度：再往外画面几乎不动，攒多了回捏要先白捏一大段。 */
  boundedRawSpacing(raw: number): number {
    const lo = AICoinBehavior.minimumSpacing, hi = AICoinBehavior.maximumSpacing
    if (Number.isNaN(raw)) return hi
    const up = hi * Math.pow(1 + ViewMath.zoomOvershoot, 3), down = lo * Math.pow(1 - ViewMath.zoomOvershoot, 3)
    return Math.min(up, Math.max(down, raw))
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
    // 根宽也一起回（捏合软边松手弹回 [1.6, 40]）：左右两缘同一个权重插值，捏的那一点整段回弹里站在原地
    return { view: new ViewWindow(b.to + (a.to - b.to) * remaining, b.span + (a.span - b.span) * remaining), done: false }
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
      const raw = subScale[id] ?? DEFAULT_SUB_SCALE
      return Number.isFinite(raw) ? Math.min(SubPaneResize.maximumScale, Math.max(SubPaneResize.minimumScale, raw)) : 0.5
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

/** 没拖过的副图的高度权重（主图权重 3）。手机网页版在浏览器里还要让出地址栏与工具栏，可视高度比 app 矮，
 *  照 iOS 的 1 会让三个副图吃掉一半图区；用户 2026-10-03 要「指标区域尽量小一点，k 线区域多一点」。
 *  拖过的副图存的是绝对权重，跨 iOS / 网页一致 */
export const DEFAULT_SUB_SCALE = 0.7

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

/**
 * KanpanCore `SubPaneResize`：往小拖的底线是点数（一格最矮 40pt），不是倍率 0.5；
 * 倍率下界 0.25、上界 2（2026-10-10，原因见 Swift 那份注释）。
 */
export const SubPaneResize = {
  minimumScale: 0.25,
  maximumScale: 2,
  minimumHeight: 40,
  scale(initialHeight: number, translation: number, contentHeight: number, otherWeight: number, minimumHeight = 40): number {
    if (!(contentHeight > 0) || !Number.isFinite(translation) || !(otherWeight > 0)) return 1
    const floor = Math.min(minimumHeight, initialHeight)
    const desired = Math.min(contentHeight - 1, Math.max(1, floor, initialHeight + translation))
    return Math.min(SubPaneResize.maximumScale, Math.max(SubPaneResize.minimumScale, desired * otherWeight / (contentHeight - desired)))
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

/**
 * 价格轴绕一个价位缩放：倍数换成 `zoom` 之后，`price` 仍落在主图同一个高度上，返回该用的
 * `centerFraction`（已夹过）。双指竖着捏价格轴用它（iOS PriceTransform.anchoredCenter，a8012401）。
 * - `g`：那个高度在主图里的位置，按前向空间从下往上量（0 = 下沿，1 = 上沿；反转的轴由调用方先翻）；
 * - `autoLow` / `autoHigh`：同一视野下 zoom = 1 时的价格区间。
 * 手动区间在价格空间里按 mid ± half 摆（见 priceRange）：线性、百分比是闭式解，对数轴二分。
 */
export function anchoredCenter(price: number, g: number, zoom: number, autoLow: number, autoHigh: number, mode: PriceMode): number {
  const autoH = autoHigh - autoLow
  if (!(autoH > 0) || !Number.isFinite(autoH) || !Number.isFinite(price) || !Number.isFinite(g) || !Number.isFinite(zoom) || !(zoom > 0)) return 0.5
  const z = Math.min(16, Math.max(0.03, zoom))
  const half = autoH / (2 * z)
  let mid: number
  if (mode === 'log' && price > 0 && g > 0 && g < 1) {
    const target = Math.log(price)
    const frac = (m: number): number => {
      const lo = Math.log(Math.max(1e-300, m - half)), hi = Math.log(m + half)
      return (target - lo) / (hi - lo)
    }
    let a = half * (1 + 1e-12), b = price + half
    for (let k = 0; k < 80; k++) {
      const m = (a + b) / 2
      if (frac(m) > g) a = m; else b = m
    }
    mid = (a + b) / 2
  } else {
    mid = price + half * (1 - 2 * g)
  }
  return clampedCenter((mid - autoLow) / autoH, z)
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
      // 坏数（NaN / ±Infinity）一根都不许进区间：一个 Infinity 会把整屏顶成兜底的 0...1。
      for (let i = lo; i <= hi; i++) {
        const h = series.high[i], l = series.low[i]
        if (Number.isFinite(h) && h > maxV) maxV = h
        if (Number.isFinite(l) && l < minV) minV = l
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
  for (const p of drawingPrices) { if (!Number.isFinite(p)) continue; if (p > maxV) maxV = p; if (p < minV) minV = p }
  for (const p of extraPrices) { if (!Number.isFinite(p)) continue; if (p > maxV) maxV = p; if (p < minV) minV = p }
  if (!Number.isFinite(minV) || !Number.isFinite(maxV)) { minV = 0; maxV = 1 }
  if (maxV === minV) {
    // 十字星 / 停牌：上下各留价格的千分之一。从前的 ±(0.1% + 1) 里那个「+1」是绝对值，
    // 对 0.00001234 的小币会把区间撑到 -1...+1、蜡烛压成正中一条线、下沿掉进负价；
    // 留白必须跟价格同量级，只有价格本身是 0 时才退回 ±1（同 iOS PriceScale）。
    const pad = minV !== 0 ? Math.abs(minV) * 0.001 : 1
    maxV = minV + pad
    minV = minV - pad
  }
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
/**
 * 时间轴允许的步长阶梯（末尾补了 2 / 5 / 10 年，同 iOS Ticks.swift · 审查 B·P3-3）。
 * 原型封顶一年：月线缩到最密时九年历史塞进三百来点宽，一年一格只有三十几点，标签挤成一团。
 * 一周及以上的步长只是「标称长度」，用来挑档；真正的刻度按日历摆（见 timeTicks）。
 */
export const timeSteps: number[] = [
  TMIN, 5 * TMIN, 15 * TMIN, 30 * TMIN, THOUR, 2 * THOUR, 4 * THOUR, 6 * THOUR, 12 * THOUR,
  TDAY, 2 * TDAY, 7 * TDAY, 14 * TDAY, 30 * TDAY, 90 * TDAY, 180 * TDAY, 365 * TDAY,
  730 * TDAY, 1825 * TDAY, 3650 * TDAY,
]

/** 按日历月推进的档：一档跨几个月。月 / 季 / 半年 / 年 / 2 年 / 5 年 / 10 年。 */
export function calendarMonths(step: number): number | null {
  switch (step) {
    case 30 * TDAY: return 1
    case 90 * TDAY: return 3
    case 180 * TDAY: return 6
    case 365 * TDAY: return 12
    case 730 * TDAY: return 24
    case 1825 * TDAY: return 60
    case 3650 * TDAY: return 120
    default: return null
  }
}

/** 公历某年某月某日（本地零点）距 1970-01-01 的天数（Howard Hinnant 的 days_from_civil，同 iOS）。 */
export function daysFromCivil(year: number, month: number, day: number): number {
  const y = month <= 2 ? year - 1 : year
  const era = Math.trunc((y >= 0 ? y : y - 399) / 400)
  const yoe = y - era * 400
  const mp = (month + 9) % 12
  const doy = Math.trunc((153 * mp + 2) / 5) + day - 1
  const doe = yoe * 365 + Math.trunc(yoe / 4) - Math.trunc(yoe / 100) + doy
  return era * 146_097 + doe - 719_468
}

/** 1970-01-05 是周一，比 epoch（周四）晚 4 天：周 / 两周的刻度以它为锚。 */
const MONDAY_ANCHOR = 4 * TDAY

export function timeStep(spanMs: number, plotW: number, perLabelPx: number = Chart.timeLabelPx): number {
  const want = Math.max(2, Math.floor(plotW / perLabelPx))
  const rough = spanMs / want
  for (const s of timeSteps) if (s >= rough) return s
  return timeSteps[timeSteps.length - 1]
}

/** 上海时区：+480 分钟，没有夏令时（kanpan-timezone-shanghai）。 */
export const SHANGHAI_OFFSET_MIN = 480

/**
 * 时间轴上要画的刻度：按时区对齐（同 iOS Ticks.swift · 审查 B·P3-3）。
 * - 一天以内：对齐到整点 / 整日（步长整倍数）。
 * - 周 / 两周：对齐到周一零点。从前按 epoch 整倍数对齐，1970-01-01 是周四，周线刻度全落在周四。
 * - 月及以上：对齐到某月 1 号零点、按日历月推进（季 1/4/7/10、年 1 月 1 号）。从前拿 30 / 90 / 365 天
 *   的毫秒数整除，标出「03-17」这种逐年漂移的日子。
 */
export function timeTicks(view: ViewWindow, plotW: number, offsetMinutes: number = SHANGHAI_OFFSET_MIN, perLabelPx: number = Chart.timeLabelPx): { t: number; step: number }[] {
  if (!Number.isFinite(view.from) || !Number.isFinite(view.to) || !(view.to > view.from)) return []
  const step = timeStep(view.span, plotW, perLabelPx)
  const shift = offsetMinutes * 60_000
  const out: { t: number; step: number }[] = []
  const months = calendarMonths(step)
  if (months != null) {
    const start = dateParts(view.from, offsetMinutes)
    let index = start.year * 12 + (start.month - 1)
    const r = ((index % months) + months) % months
    if (r !== 0) index += months - r
    // 视野再宽也就几十格；上限只防坏输入把循环拖死。
    for (let k = 0; k < 4096; k++) {
      const year = Math.floor(index / 12)
      const month = index - year * 12 + 1
      const t = daysFromCivil(year, month, 1) * TDAY - shift
      if (t > view.to) break
      if (t >= view.from) out.push({ t, step })
      index += months
    }
    return out
  }
  const anchor = step % (7 * TDAY) === 0 ? MONDAY_ANCHOR : 0
  let t = Math.ceil((view.from + shift - anchor) / step) * step + anchor - shift
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
