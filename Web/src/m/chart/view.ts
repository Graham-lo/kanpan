// 移植自 KanpanChart/Sources/KanpanChart/ChartView.swift
//
// 视图自己一笔都不画：三块画布（plot / live / cross）各自转手给 ChartRenderer 的
// drawPlot / drawLive / drawCross；最上面第四块是画线覆盖层（选中柄、预览线、铃铛），由画线模块画。
// 换 state 时跟旧值比出脏位（changed），脏位攒到下一帧 requestAnimationFrame 一起刷；
// 没有脏位、没有动画就不跑帧（Swift 的 CADisplayLink 暂停，A3.12：静止时不耗 CPU）。
//
// 与 Swift 的差异：
// - BarSeries 在网页里原地改（tick 只动末根），旧 state 与新 state 可能指向同一个序列对象，
//   所以「末根变没变」「只追加了一根」靠视图自己记的一份指纹（revision / prefixRevision / 末根 OHLCV）判，
//   不能像 Swift 那样拿两份值类型直接比。
// - 手机浏览器没有震动，也没有 120 Hz 档位开关（浏览器自己按屏幕刷新率跑 rAF）。

import type { ChartState, Crosshair } from './state'
import { ChartRenderer } from './renderer'
import type { PriceRange, ViewWindow, Layout } from './geometry'
import { visibleRange } from './geometry'
import { sameRender, orderFlowDisplayEqual, sameOrderFlowKey } from '../../orderflow/group'
import type { OrderFlowSnapshot, OrderFlowGroupKey } from '../../orderflow/group'
import type { BarSeries } from './series'
import type { Drawing } from './drawing'
import { ChartGestures, GestureState, reduceMotion } from './gesture'
import * as OrderFlowHits from './renderer.orderflow'
import { Parts } from './view.parts'
import type { PartsMask } from './view.parts'

export { Parts }

/** 十字线 / 轻点选中的那一单（详情卡定位用）。结构由订单流渲染给出，这里只当不透明值转手。 */
export type ChartOrderFlowFocus = { group: { key: OrderFlowGroupKey } } & Record<string, unknown>
const OF = OrderFlowHits as unknown as {
  orderFlowFocus?: (r: ChartRenderer, W: number, H: number) => ChartOrderFlowFocus | null
}

/** 拖动期间钉住的那套坐标（FrozenAxes）。 */
export interface FrozenAxes {
  view: ViewWindow
  range: PriceRange
  followingLatest: boolean
}

/** 画线层接管触摸的入口（ChartView+Drawing 的 drawingTouchesBegan / Moved / Ended）。 */
export interface DrawingInput {
  began(ids: number[], now: number): void
  moved(ids: number[], now: number): void
  ended(ids: number[], now: number, cancelled: boolean): void
}

/** 附加图层的画法（见 ChartView.addLayer）。 */
export type LayerPaint = (ctx: CanvasRenderingContext2D, W: number, H: number, scale: number, r: ChartRenderer) => void
interface ChartLayer { canvas: HTMLCanvasElement; paint: LayerPaint; dirty: boolean }
export interface ChartLayerHandle { readonly canvas: HTMLCanvasElement; redraw(): void; remove(): void }

/** 视图记的一份序列指纹：原地改的 BarSeries 只能这么比。 */
interface SeriesMark {
  ref: BarSeries
  revision: number
  prefixRevision: number
  count: number
  symbol: string
  interval: string
  last: [number, number, number, number, number] | null
}
function markOf(s: BarSeries): SeriesMark {
  const i = s.count - 1
  return {
    ref: s, revision: s.revision, prefixRevision: s.prefixRevision, count: s.count, symbol: s.symbol, interval: s.interval,
    last: i >= 0 ? [s.open[i], s.high[i], s.low[i], s.close[i], s.volume[i]] : null,
  }
}
const sameLastValues = (a: SeriesMark['last'], b: SeriesMark['last']): boolean =>
  a == null || b == null ? a == null && b == null : a.every((x, k) => Object.is(x, b[k]))

const INPUT_KEYS_EXCEPT_SERIES = [
  'compare', 'percentAxis', 'oi', 'external', 'symbol', 'colors', 'overlays', 'subs', 'params', 'tzOffset',
  'indicatorColors', 'decimals', 'options', 'hiddenOutputs', 'subInverted', 'rsiUpper', 'rsiLower', 'oiSupported', 'externalSupported',
] as const

const sameCrosshair = (a: Crosshair | null, b: Crosshair | null): boolean =>
  a === b || (a != null && b != null && a.index === b.index && a.pane === b.pane && a.t === b.t && a.price === b.price
    && (a.source ?? 'chart') === (b.source ?? 'chart'))

const sameFocus = (a: Set<string> | null, b: Set<string> | null): boolean =>
  a == null || b == null ? a == null && b == null : a.size === b.size && [...a].every(k => b.has(k))

function hasLadder(s: ChartState): boolean {
  const book = s.overlay.depth
  if (!book || book.symbol !== s.input.symbol.symbol) return false
  return book.bids.some(l => l.quantity > 0) || book.asks.some(l => l.quantity > 0)
}
const samePixels = (a: OrderFlowSnapshot | null, b: OrderFlowSnapshot | null): boolean =>
  a == null || b == null ? a == null && b == null : sameRender(a, b)

/** 价格闪一下的时长（P2.8）。 */
const PRICE_FLASH_MS = 150

export class ChartView {
  readonly el: HTMLDivElement
  private readonly canvases: { part: number; canvas: HTMLCanvasElement }[]
  /** 画线覆盖层（DrawingOverlayView）：最上面一块，画选中态、预览线、铃铛。 */
  readonly overlayCanvas: HTMLCanvasElement

  readonly gesture = new GestureState()
  readonly gestures: ChartGestures
  frozenAxes: FrozenAxes | null = null
  renderer: ChartRenderer | null = null

  /** 点尺寸与渲染倍率（min(4, devicePixelRatio)）。上限原来是 3（iPhone 正好 3），华为 nova 16 这类鸿蒙机是 3.5 倍屏，
   *  封在 3 会让画布按 3 倍画再被拉伸 1.17 倍，字和细线发虚——所以放到 4，按设备真实倍率画。 */
  width = 0
  height = 0
  scale = 2
  attached = false

  // ------------------------------------------------------------ 回调（与 Swift 同名）
  onViewChanged: ((v: ViewWindow) => void) | null = null
  onUserViewChanged: ((v: ViewWindow) => void) | null = null
  onCrosshairChanged: ((c: Crosshair | null) => void) | null = null
  onOrderFlowFocusChanged: ((f: ChartOrderFlowFocus | null) => void) | null = null
  onNeedsHistory: (() => void) | null = null
  onTapped: (() => void) | null = null
  onNotice: ((text: string) => void) | null = null
  onStateChanged: ((s: ChartState | null, layers: { input: boolean; viewport: boolean; overlay: boolean }) => void) | null = null
  onInteractionEnded: (() => void) | null = null
  onInteractionBegan: (() => void) | null = null
  /** 竖向拖到了页面那一侧（UIScrollView 接手）：dy 是页面该滚的量（点）。 */
  onParentScroll: ((dy: number) => void) | null = null
  /** 尺寸变了（宿主据此按 `.resize` 重排视野）。 */
  onResize: ((W: number, H: number) => void) | null = null

  // ------------------------------------------------------------ 画线层的挂点（view.drawing.ts 赋值）
  drawingInput: DrawingInput | null = null
  drawingOverlayPaint: ((ctx: CanvasRenderingContext2D, W: number, H: number, scale: number) => void) | null = null
  /** 线不归调用方给：挂了画线控制器时，每份 state 先按品种投影一遍线（projectDrawings）。 */
  drawingProject: ((incoming: ChartState) => ChartState) | null = null
  /**
   * 换了品种（投影键变了）：收掉上一张图的半截画线交互。
   * 换投影函数（装上 / 摘下控制器）时一并忘掉记着的旧键：否则同一张图重装控制器后投影出同一个键，
   * 视图就不会再喊 onDrawingKeyChanged，新控制器永远接不上键。
   */
  get drawingKeyOf(): ((s: ChartState) => string) | null { return this._drawingKeyOf }
  set drawingKeyOf(fn: ((s: ChartState) => string) | null) {
    if (fn !== this._drawingKeyOf) this.drawingKey = null
    this._drawingKeyOf = fn
  }
  onDrawingKeyChanged: ((from: string | null) => void) | null = null
  /** 图销毁时通知画线控制器摘下（退订全局本、停长按计时器）。attachDrawing 赋值。 */
  drawingTeardown: (() => void) | null = null
  /** 一下轻点先问画线层：落在提醒线（AlertSignal）上就归它、返回真，图不再当轻点处理 */
  signalTap: ((x: number, y: number) => boolean) | null = null
  /** 一下轻点接着问图上气泡（bigTradeLayer 赋值）：点中一枚就归它、返回真 */
  bigTradeTap: ((x: number, y: number) => boolean) | null = null
  private _drawingKeyOf: ((s: ChartState) => string) | null = null
  private drawingKey: string | null = null

  private _guestDrawings: Drawing[] = []
  private _ownDimmed = false
  private storedState: ChartState | null = null
  private mark: SeriesMark | null = null
  private orderFlowFocus: ChartOrderFlowFocus | null = null
  private dirty: PartsMask = 0
  /** 附加图层（图上大单与爆仓气泡等）：各自一块画布，插在画线覆盖层下面 */
  private readonly layers: ChartLayer[] = []
  private overlayDirty = false
  private raf = 0
  private _animation: ((nowMs: number) => boolean) | null = null
  private flashTimer: ReturnType<typeof setTimeout> | null = null
  private resizeObserver: ResizeObserver | null = null
  private dprQuery: MediaQueryList | null = null
  private readonly onDprChange = () => { this.measure(); this.watchDpr() }

  constructor(host: HTMLElement) {
    const el = document.createElement('div')
    el.className = 'm-chart'
    Object.assign(el.style, {
      position: 'relative', width: '100%', height: '100%', overflow: 'hidden',
      touchAction: 'none', userSelect: 'none', webkitUserSelect: 'none',
    } as Partial<CSSStyleDeclaration>)
    el.style.setProperty('-webkit-touch-callout', 'none')
    el.style.setProperty('-webkit-tap-highlight-color', 'transparent')
    el.setAttribute('role', 'img')
    el.setAttribute('aria-label', '行情图表')
    this.el = el
    const make = (part: number): HTMLCanvasElement => {
      const c = document.createElement('canvas')
      c.dataset.part = String(part)
      Object.assign(c.style, { position: 'absolute', left: '0', top: '0', width: '100%', height: '100%', pointerEvents: 'none' })
      el.appendChild(c)
      return c
    }
    this.canvases = [Parts.plot, Parts.live, Parts.cross].map(part => ({ part, canvas: make(part) }))
    this.overlayCanvas = make(8)
    host.appendChild(el)
    this.gestures = new ChartGestures(this)
    this.gestures.attach(el)
    this.attached = true
    this.resizeObserver = new ResizeObserver(() => this.measure())
    this.resizeObserver.observe(el)
    this.watchDpr()
    this.measure()
  }

  destroy(): void {
    // 先摘画线控制器：它挂在全局 DrawingBook 的观察者表里（强引用），不摘整张图都放不掉
    const drawingTeardown = this.drawingTeardown
    this.drawingTeardown = null
    drawingTeardown?.()
    this.gestures.teardown()
    this.gestures.detach()
    this.resizeObserver?.disconnect()
    this.resizeObserver = null
    this.dprQuery?.removeEventListener('change', this.onDprChange)
    this.dprQuery = null
    if (this.raf) cancelAnimationFrame(this.raf)
    this.raf = 0
    if (this.flashTimer) clearTimeout(this.flashTimer)
    this.attached = false
    this._animation = null
    this.el.remove()
  }

  // ------------------------------------------------------------ 客线 / 自己的线变暗

  get guestDrawings(): Drawing[] { return this._guestDrawings }
  set guestDrawings(v: Drawing[]) {
    this._guestDrawings = v
    if (this.renderer) this.renderer.guestDrawings = v
    // 金额签躲客线上的字，签在 cross 层（见 renderer.orderflow drawingLabelBoxes）。
    this.setNeedsRedraw(this.storedState?.overlay.orderFlow == null ? Parts.plot : Parts.plot | Parts.cross)
    this.refreshDrawingOverlay()
  }
  get ownDimmed(): boolean { return this._ownDimmed }
  set ownDimmed(v: boolean) {
    this._ownDimmed = v
    if (this.renderer) this.renderer.ownDimmed = v
    this.setNeedsRedraw(Parts.plot)
    this.refreshDrawingOverlay()
  }

  // ------------------------------------------------------------ 输入

  get state(): ChartState | null { return this.storedState }
  set state(incoming: ChartState | null) {
    const old = this.storedState
    const oldMark = this.mark
    let next = incoming
    if (next) {
      if (old && oldMark) next = this.normalized(next, old, oldMark)
      if (this.drawingProject) next = this.drawingProject(next)
    }
    const keyBefore = this.drawingKey
    this.storedState = next
    if (next && this.drawingKeyOf) this.drawingKey = this.drawingKeyOf(next)
    this.adopt(old, oldMark)
    if (next && keyBefore !== this.drawingKey) this.onDrawingKeyChanged?.(keyBefore)
  }

  /** 此刻手指正按着某个目标、坐标是钉住的吗。宿主据此跳过 reconcile。 */
  get axesFrozen(): boolean { return this.frozenAxes != null }

  get chartLayout(): Layout | null {
    if (!this.renderer || !(this.width > 0) || !(this.height > 0)) return null
    return this.renderer.layout(this.width, this.height)
  }
  get chartPriceRange(): PriceRange | null {
    if (!this.renderer || !(this.width > 0) || !(this.height > 0)) return null
    return this.renderer.priceRange(this.width, this.height)
  }
  pinPriceRange(range: PriceRange | null): void {
    if (this.renderer) this.renderer.pinnedPriceRange = range
  }

  private normalized(incoming: ChartState, old: ChartState, oldMark: SeriesMark): ChartState {
    let next = incoming
    const ni = next.input, oi = old.input
    const nextSeries = ni.series
    const changedChart = oldMark.symbol !== nextSeries.symbol || oldMark.interval !== nextSeries.interval
    const cross = next.overlay.crosshair
    if (oi.options.dataDisplay !== ni.options.dataDisplay || oi.options.crossPrice !== ni.options.crossPrice || changedChart
      || (cross?.pane != null && !ni.subs.includes(cross.pane))) {
      if (cross) next = { ...next, overlay: { ...next.overlay, crosshair: null } }
    }
    if (changedChart || oi.percentAxis !== ni.percentAxis) {
      this.gesture.endAxisTapCandidate()
      this.gesture.askedHistory = false
      this.gestures.cancelAxisFreeze()
    }
    if (changedChart) {
      this.animation = null
      this.gesture.reset()
    }
    const frozen = this.frozenAxes
    if (frozen && !next.viewport.view.equals(frozen.view)) {
      next = { ...next, viewport: { ...next.viewport, view: frozen.view } }
    }
    return next
  }

  // ------------------------------------------------------------ 尺寸

  private watchDpr(): void {
    this.dprQuery?.removeEventListener('change', this.onDprChange)
    if (typeof matchMedia === 'undefined') return
    this.dprQuery = matchMedia(`(resolution: ${window.devicePixelRatio || 1}dppx)`)
    this.dprQuery.addEventListener('change', this.onDprChange)
  }

  /** layoutSubviews：尺寸或倍率变了才重设画布、全部置脏。 */
  measure(): void {
    const r = this.el.getBoundingClientRect()
    const W = r.width, H = r.height
    const scale = Math.min(4, window.devicePixelRatio || 2)
    if (W === this.width && H === this.height && scale === this.scale) return
    this.width = W
    this.height = H
    this.scale = scale
    const pw = Math.max(1, Math.round(W * scale)), ph = Math.max(1, Math.round(H * scale))
    for (const { canvas } of this.canvases) { canvas.width = pw; canvas.height = ph }
    this.overlayCanvas.width = pw
    this.overlayCanvas.height = ph
    for (const l of this.layers) { l.canvas.width = pw; l.canvas.height = ph; l.dirty = true }
    this.onResize?.(W, H)
    this.setNeedsRedraw(Parts.all)
    this.refreshDrawingOverlay()
  }

  // ------------------------------------------------------------ 脏位与帧

  get animation(): ((nowMs: number) => boolean) | null { return this._animation }
  set animation(a: ((nowMs: number) => boolean) | null) {
    this._animation = a
    if (a) this.resume()
  }

  setNeedsRedraw(parts: PartsMask = Parts.all): void {
    if (!parts) return
    this.dirty |= parts
    this.resume()
  }

  refreshDrawingOverlay(): void {
    this.overlayDirty = true
    this.resume()
  }

  /**
   * 挂一块附加图层：插在画线覆盖层下面、不接触摸。几何变了（plot 层重画：视野、价格区间、末根、画线）时跟着重画，
   * 自己的数据变了调 redraw()。画的时候坐标系已按倍率缩放好，W / H 是点尺寸。
   */
  addLayer(paint: LayerPaint): ChartLayerHandle {
    const c = document.createElement('canvas')
    Object.assign(c.style, { position: 'absolute', left: '0', top: '0', width: '100%', height: '100%', pointerEvents: 'none' })
    c.width = Math.max(1, Math.round(this.width * this.scale)); c.height = Math.max(1, Math.round(this.height * this.scale))
    this.el.insertBefore(c, this.overlayCanvas)
    const layer: ChartLayer = { canvas: c, paint, dirty: true }
    this.layers.push(layer)
    this.resume()
    return {
      canvas: c,
      redraw: () => { layer.dirty = true; this.resume() },
      remove: () => {
        const i = this.layers.indexOf(layer)
        if (i >= 0) this.layers.splice(i, 1)
        c.remove()
      },
    }
  }

  /** 立刻把脏层画完，不等下一帧（验收截图用）。 */
  redrawNow(): void { this.flush() }

  private resume(): void {
    if (!this.attached || this.raf) return
    this.raf = requestAnimationFrame(t => this.onFrame(t))
  }

  private onFrame(now: number): void {
    this.raf = 0
    const a = this._animation
    if (a) {
      // 动画每帧写 state（走 setter → 置脏），返回 true 表示演完了
      const done = a(now)
      if (done && this._animation === a) this._animation = null
    }
    this.flush()
    if (this._animation) this.resume()
  }

  private flush(): void {
    const parts = this.dirty
    this.dirty = 0
    const W = this.width, H = this.height, scale = this.scale
    if (parts && W > 0 && H > 0) {
      const r = this.renderer
      for (const { part, canvas } of this.canvases) {
        if (!(parts & part)) continue
        const ctx = canvas.getContext('2d')
        if (!ctx) continue
        ctx.setTransform(scale, 0, 0, scale, 0, 0)
        if (!r || !this.storedState) { ctx.clearRect(0, 0, W, H); continue }
        if (part === Parts.plot) r.drawPlot(ctx, W, H, scale)
        else if (part === Parts.live) r.drawLive(ctx, W, H, scale)
        else r.drawCross(ctx, W, H, scale)
      }
    }
    if (this.overlayDirty && W > 0 && H > 0) {
      this.overlayDirty = false
      const ctx = this.overlayCanvas.getContext('2d')
      if (ctx) {
        ctx.setTransform(scale, 0, 0, scale, 0, 0)
        ctx.clearRect(0, 0, W, H)
        if (this.storedState && this.renderer) this.drawingOverlayPaint?.(ctx, W, H, scale)
      }
    }
    if (W > 0 && H > 0) {
      for (const l of this.layers) {
        if (!l.dirty && !(parts & Parts.plot)) continue
        l.dirty = false
        const ctx = l.canvas.getContext('2d')
        if (!ctx) continue
        ctx.setTransform(scale, 0, 0, scale, 0, 0)
        ctx.clearRect(0, 0, W, H)
        if (this.storedState && this.renderer) l.paint(ctx, W, H, scale, this.renderer)
      }
    }
  }

  // ------------------------------------------------------------ 换 state

  private adopt(old: ChartState | null, oldMark: SeriesMark | null): void {
    const s = this.storedState
    if (!s) {
      this.animation = null
      this.gesture.touches = []
      this.gesture.reset()
      this.gesture.endAxisTapCandidate()
      this.gestures.cancelAxisFreeze()
      if (old?.overlay.crosshair) this.onCrosshairChanged?.(null)
      this.fireOrderFlowFocus(null)
      this.onStateChanged?.(null, { input: true, viewport: true, overlay: true })
      this.renderer = null
      this.mark = null
      this.setNeedsRedraw(Parts.all)
      this.refreshDrawingOverlay()
      return
    }
    const nextMark = markOf(s.input.series)
    const layers = {
      input: !old || old.input !== s.input || !oldMark || oldMark.ref !== nextMark.ref || oldMark.revision !== nextMark.revision,
      viewport: !old || old.viewport !== s.viewport,
      overlay: !old || old.overlay !== s.overlay,
    }
    const layoutBefore = layers.viewport ? this.chartLayout : null
    // 叠加线超过六条时焦点跟十字线走（overlayFocus）：焦点换了，蜡烛那层也得重画。
    const focusBefore = this.renderer ? this.renderer.overlayFocus() : null
    if (!this.renderer) this.renderer = new ChartRenderer(s)
    else this.renderer.state = s
    this.renderer.guestDrawings = this._guestDrawings
    this.renderer.ownDimmed = this._ownDimmed
    let parts = this.changed(old, oldMark, s, nextMark)
    if (old && !(parts & Parts.plot) && !sameFocus(focusBefore, this.renderer.overlayFocus())) parts |= Parts.plot
    if (layoutBefore && !(parts & Parts.cross)) {
      const L = this.chartLayout
      if (L && !sameLayout(L, layoutBefore)) parts |= Parts.cross
    }
    this.mark = nextMark
    this.setNeedsRedraw(parts)
    if (parts & Parts.plot) this.refreshDrawingOverlay()
    this.flashIfTicked(old, oldMark, s, nextMark)
    if (layers.input || layers.viewport || layers.overlay) this.onStateChanged?.(s, layers)
    if (!sameCrosshair(old?.overlay.crosshair ?? null, s.overlay.crosshair)) this.onCrosshairChanged?.(s.overlay.crosshair)
    if (s.overlay.crosshair != null || s.overlay.orderFlowSelected != null || this.orderFlowFocus != null) {
      this.fireOrderFlowFocus(OF.orderFlowFocus && this.renderer ? OF.orderFlowFocus(this.renderer, this.width, this.height) : null)
    }
  }

  private fireOrderFlowFocus(f: ChartOrderFlowFocus | null): void {
    const a = this.orderFlowFocus
    if (a === f) return
    if (a && f && sameOrderFlowKey(a.group.key, f.group.key) && JSON.stringify(a) === JSON.stringify(f)) return
    this.orderFlowFocus = f
    this.onOrderFlowFocusChanged?.(f)
  }

  /** 订单流并墙完成后外部通知（Swift 的 orderFlowWallsReady）。 */
  orderFlowWallsReady(plotStale: boolean): void {
    this.setNeedsRedraw(plotStale ? Parts.plot | Parts.cross : Parts.cross)
    const s = this.storedState
    if (s && (s.overlay.crosshair != null || s.overlay.orderFlowSelected != null || this.orderFlowFocus != null)) {
      this.fireOrderFlowFocus(OF.orderFlowFocus && this.renderer ? OF.orderFlowFocus(this.renderer, this.width, this.height) : null)
    }
  }

  /** 新旧两帧的差异落在哪几层（ChartView.changed）。 */
  private changed(o: ChartState | null, om: SeriesMark | null, n: ChartState, nm: SeriesMark): PartsMask {
    if (!o || !om) return Parts.all
    // 输入层除末根外动了：几何全变
    if (o.input !== n.input) {
      for (const k of INPUT_KEYS_EXCEPT_SERIES) if (o.input[k] !== n.input[k]) return Parts.all
    }
    const seriesSame = om.ref === nm.ref && om.revision === nm.revision
    const onlyTail = om.ref === nm.ref && om.symbol === nm.symbol && om.interval === nm.interval
      && ((nm.count === om.count && nm.prefixRevision === om.prefixRevision)
        || (nm.count === om.count + 1 && nm.prefixRevision === om.revision))
    if (!seriesSame && !onlyTail) return Parts.all
    if ((o.overlay.orderFlow == null) !== (n.overlay.orderFlow == null)) return Parts.all
    let p = 0
    if (o.viewport !== n.viewport) {
      p |= Parts.plot | Parts.live
      if (o.overlay.crosshair != null || n.overlay.crosshair != null || n.input.percentAxis || n.overlay.orderFlow != null) p |= Parts.cross
    }
    if (o.overlay.drawings !== n.overlay.drawings || o.overlay.drawingPreviewID !== n.overlay.drawingPreviewID) {
      p |= Parts.plot
      // 金额签在 cross 层、要躲画线上的字（drawingLabelBoxes）：线一变签得跟着重排。
      if (n.overlay.orderFlow != null) p |= Parts.cross
    }
    // 末根变了：蜡烛（plot）、最新价（live）都要重画；没有十字线时图例读的就是末根，图例在 cross 层，
    // 所以 cross 也得跟着脏。十字线开着时看它读不读末根（见 crossReadsLastBar）。
    if (!(seriesSame || (nm.count === om.count && sameLastValues(om.last, nm.last)))) {
      p |= Parts.plot | Parts.live
      if (o.overlay.crosshair == null || n.overlay.crosshair == null
        || crossReadsLastBar(o, om.count) || crossReadsLastBar(n, nm.count)) p |= Parts.cross
    }
    if (o.overlay.depth !== n.overlay.depth) {
      p |= Parts.live
      if (n.overlay.orderFlow != null && hasLadder(o) !== hasLadder(n)) p |= Parts.cross
    }
    if (!orderFlowDisplayEqual(o.overlay.orderFlowDisplay, n.overlay.orderFlowDisplay) || !samePixels(o.overlay.orderFlow, n.overlay.orderFlow)) {
      p |= Parts.plot | Parts.cross
    } else if (o.overlay.orderFlow !== n.overlay.orderFlow) p |= Parts.cross
    if (!sameCrosshair(o.overlay.crosshair, n.overlay.crosshair) || !sameOrderFlowKey(o.overlay.orderFlowSelected, n.overlay.orderFlowSelected)) {
      p |= Parts.cross
    }
    if (o.overlay.nowMs !== n.overlay.nowMs && n.input.options.countdown && n.input.options.lastLine) p |= Parts.live
    return p
  }

  /** 同一只、同一周期的末根收盘价动了一口：右轴最新价胶囊按方向闪 150 ms（减少动效时不闪）。 */
  private flashIfTicked(o: ChartState | null, om: SeriesMark | null, n: ChartState, nm: SeriesMark): void {
    if (!o || !om || !om.last || !nm.last) return
    const before = om.last[3], now = nm.last[3]
    if (before === now || om.symbol !== nm.symbol || om.interval !== nm.interval) return
    const tick = nm.count === om.count
      ? om.ref === nm.ref && nm.prefixRevision === om.prefixRevision
      : nm.count === om.count + 1 && om.ref === nm.ref && nm.prefixRevision === om.revision
    if (!tick || !n.input.options.lastLine || reduceMotion() || !this.renderer) return
    this.renderer.priceFlash = now > before ? 'up' : 'down'
    this.setNeedsRedraw(Parts.live)
    if (this.flashTimer) clearTimeout(this.flashTimer)
    this.flashTimer = setTimeout(() => {
      this.flashTimer = null
      if (this.renderer) this.renderer.priceFlash = null
      this.setNeedsRedraw(Parts.live)
    }, PRICE_FLASH_MS)
  }

  // ------------------------------------------------------------ 转手给手势层的公开动作

  scrollToLatest(animated = true): void { this.gestures.scrollToLatest(animated) }
  get isAtLatest(): boolean { return this.gestures.isAtLatest }
  clearCrosshair(): void { this.gestures.clearCrosshair() }
  moveCrosshair(by: number): void { this.gestures.moveCrosshairBy(by) }
  crosshairTo(index: number, source: Crosshair['source'] = 'chart', price?: number): void { this.gestures.crosshairTo(index, source, price) }
  resetPriceScale(): void { this.gestures.resetPriceScale() }
  nudge(dx: number): void { this.gestures.nudge(dx) }
  reveal(from: number, to: number): void { this.gestures.reveal(from, to) }
  selectOrderFlow(key: OrderFlowGroupKey | null): void { this.gestures.selectOrderFlow(key) }
}

function sameLayout(a: Layout, b: Layout): boolean {
  if (a.W !== b.W || a.H !== b.H || a.plotW !== b.plotW || a.panes.length !== b.panes.length) return false
  return a.panes.every((p, i) => p.y === b.panes[i].y && p.h === b.panes[i].h && p.indicator === b.panes[i].indicator)
}

/**
 * 十字线开着时，末根一跳它那一层会不会变（ChartView.crossReadsLastBar，审查 B·P3-1）。
 * 从前一律当「不会」：手指按着最后一根不动，开高低收框与图例停在按下那一刻的价上，底图的蜡烛却一笔一笔在长。
 * 会变的有三种：十字线就停在末根上；「至今涨幅」开着（从十字线那根到末根收盘）；末根在这一屏里（含右侧护栏根），
 * 它参与价格区间与副图值域，一跳区间就可能变，横线与右轴读数都得跟着挪。
 * count 按那一帧记下的根数给：序列是原地改的，旧帧的 series.count 已经是新的。
 */
function crossReadsLastBar(s: ChartState, count: number): boolean {
  const cross = s.overlay.crosshair
  if (!cross || count <= 0) return false
  const last = count - 1
  return cross.index >= last || s.input.options.sinceChange || visibleRange(s.viewport.view, s.input.series).hi >= last
}
