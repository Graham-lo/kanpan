// 移植自 KanpanChart/Sources/KanpanChart/ChartView+Gesture.swift（外加 ChartGesture.swift）
//
// UIKit 的 touchesBegan / Moved / Ended / Cancelled → 手写 Pointer Events：每根手指一个 pointerId，
// 位置按宿主元素的 getBoundingClientRect 换成「点」。判定、阈值、状态机逐行照 Swift：
// 长按 400 ms 出十字线（移动超过 6 点取消）、单指平移过 4 点才起、竖向 1.5 倍判给价格轴平移或页面、
// 双指先平移、张合超过 8 点才开始缩放、抬手按 100 ms 窗口的速度起惯性、双击回到最新并复位价格轴。
// 浏览器没有震动（已接受的差异），ChartHaptics 只剩 reduceMotion。

import type { PriceRange, PriceTransform, Layout } from './geometry'
import {
  AICoinBehavior, Chart, ViewMath, ViewTransition, ViewWindow, FlingRun, VelocityTracker, axisZoom, clampView,
  anchoredCenter, clampedCenter, isManualTransform, pOf, priceTransform,
} from './geometry'
import type { ChartState, Crosshair } from './state'
import type { IndicatorID } from '../indicator/ids'
import { effectivePriceMode, withInput, withOverlay, withViewport } from './state'
import { subCrosshairValue } from './renderer.sub'
import * as OrderFlowHits from './renderer.orderflow'
import type { OrderFlowGroupKey } from './orderflowGroup'
import { sameOrderFlowKey } from './orderflowGroup'
import type { ChartView } from './view'
import { Parts } from './view.parts'

import { ChartGesture } from './gesture.constants'
export { ChartGesture }

export type GestureMode = 'pan' | 'crosshair' | 'pinch' | 'axisPrice' | 'subAxis' | 'verticalPan' | 'parentScroll' | 'autoFit'
export interface Point { x: number; y: number }

/** 两指的一帧：横 / 纵张开量（平均偏离 ×2）、中点、斜线距离。 */
interface TwoFinger { d: number; mid: number; my: number; sx: number; sy: number }

export class GestureState {
  mode: GestureMode | null = null
  /** 按落下顺序的 pointerId */
  touches: number[] = []
  startPoint: Point = { x: 0, y: 0 }
  startView: ViewWindow = ViewWindow.fromTo(0, 1)
  startTransform: PriceTransform = priceTransform()
  startRange: PriceRange | null = null
  trace = ''
  pinchD0 = 0
  pinchMid0 = 0
  pinchActive = false
  /** 捏合基准：两指横 / 纵张开量与中点纵坐标（死区按轴分开量，iOS a8012401）。 */
  pinchSx0 = 0
  pinchSy0 = 0
  pinchMidY0 = 0
  /** 这一捏缩哪根轴：越过死区那一帧定下，一捏之内不换。 */
  pinchAxis: 'undecided' | 'time' | 'price' = 'undecided'
  /**
   * 死区里这一轮已经报过新位置的手指。浏览器一根手指发一条 pointermove（iOS 一帧里两指一起到），
   * 只挪了一根时的「半帧」张开量会虚涨：两指一起平移 10pt，中间那一刻横向张开量就差了 10pt，
   * 3pt 的死区会把平移误判成捏合。所以死区里要等这一轮每根手指都报过（或者同一根报了第二次——
   * 另一根这一帧没动）再判；没判之前照常按中点平移。
   */
  pinchFresh = new Set<number>()
  /** 价格轴捏合：起捏时的倍数、纵向张开量、中点底下的价位。 */
  pinchStartZoom = 1
  pinchSyStart = 0
  pinchPrice = 0
  /** 时间轴：手指「要的」根宽（可越过 [1.6, 40]，画出来的是 ViewMath.softSpacing(它)）。越过死区那一帧从画面根宽倒推。 */
  pinchRawSpacing = 0
  cameFromPinch = false
  /**
   * 捏合越过软边时抬掉一根：图正走着回弹（settleView），剩下那根手指先不接管——
   * 一边弹、一边跟着画面重设起手点，弹完那一帧接着拖（iOS aedc26df）。
   */
  reboundHandoff = false
  directionChosen = false
  axisStarted = false
  lastAxisTap: { ms: number; y: number } | null = null
  lastPlotTap: { ms: number; x: number; y: number } | null = null
  moved = 0
  velocity = new VelocityTracker()
  longPressActivated = false
  longPress: ReturnType<typeof setTimeout> | null = null
  askedHistory = false
  wasAtZoomLimit = false
  /** 拎着十字线走时，交叉点相对手指的那段距离：按下时量一次，之后一路保持——十字线跟着手指的位移走，
   *  不往手指底下跳，也不被指头挡住。长按新出的十字线就在手指底下，距离是 0。 */
  grab: Point = { x: 0, y: 0 }
  /** 十字线归哪根手指（pointerId）：进 crosshair 那一刻按着的那根。十字线只跟它走；它抬起来这一轮
   *  十字线就算放下——不能让后落下的另一根手指接班，否则十字线会瞬间跳到那根手指底下（审查 B·P3-2）。 */
  owner: number | null = null

  reset(): void {
    this.mode = null
    this.grab = { x: 0, y: 0 }
    this.owner = null
    this.longPressActivated = false
    this.moved = 0
    this.pinchActive = false
    this.pinchAxis = 'undecided'
    this.pinchFresh.clear()
    this.cameFromPinch = false
    this.reboundHandoff = false
    this.directionChosen = false
    this.axisStarted = false
    this.velocity.reset()
    this.cancelLongPress()
  }
  endAxisTapCandidate(): void {
    this.lastAxisTap = null
    this.lastPlotTap = null
  }
  cancelLongPress(): void {
    if (this.longPress != null) clearTimeout(this.longPress)
    this.longPress = null
  }
}

/** 订单流那一半的命中函数由订单流移植提供；没提供时当作没命中。 */
interface OrderFlowHitHooks {
  orderFlowHit?: (r: unknown, x: number, y: number, W: number, H: number) => { key: OrderFlowGroupKey } | null
  candleHit?: (r: unknown, x: number, y: number, W: number, H: number) => boolean
  orderFlowIsSelected?: (r: unknown, g: unknown) => boolean
}
const OF = OrderFlowHits as unknown as OrderFlowHitHooks

export const reduceMotion = (): boolean =>
  typeof matchMedia !== 'undefined' && matchMedia('(prefers-reduced-motion: reduce)').matches

export type ViewChangeSource = 'gesture' | 'program'

/**
 * ChartView 的手势扩展。Swift 用 extension 挂在 ChartView 上；这里是一个持有 view 的控制器，
 * 状态（GestureState、frozenAxes）仍放在 view 上，和 Swift 的归属一致。
 */
export class ChartGestures {
  /** pointerId → 当前位置（点，相对画布左上角） */
  private points = new Map<number, Point>()
  private bound: { el: HTMLElement; off: () => void; cancel: (id: number, t: number) => void } | null = null

  constructor(private readonly v: ChartView) {}

  private get gesture(): GestureState { return this.v.gesture }
  private get state(): ChartState | null { return this.v.state }
  private set state(s: ChartState | null) { this.v.state = s }

  // ---------------------------------------------------------------- Pointer Events 接线

  attach(el: HTMLElement): void {
    this.detach()
    const local = (e: PointerEvent): Point => {
      const r = el.getBoundingClientRect()
      return { x: e.clientX - r.left, y: e.clientY - r.top }
    }
    const down = (e: PointerEvent) => {
      if (e.pointerType === 'mouse' && e.button !== 0) return
      if (!this.gestureReady) return
      try { el.setPointerCapture(e.pointerId) } catch { /* 已经抬起 */ }
      this.points.set(e.pointerId, local(e))
      e.preventDefault()
      const d = this.v.drawingInput
      if (d) d.began([e.pointerId], e.timeStamp)
      else this.touchesBegan([e.pointerId], e.timeStamp)
    }
    const move = (e: PointerEvent) => {
      if (!this.points.has(e.pointerId)) return
      this.points.set(e.pointerId, local(e))
      e.preventDefault()
      const d = this.v.drawingInput
      if (d) d.moved([e.pointerId], e.timeStamp)
      else this.touchesMoved(e.timeStamp, [e.pointerId])
    }
    const up = (e: PointerEvent) => {
      if (!this.points.has(e.pointerId)) return
      this.points.set(e.pointerId, local(e))
      const d = this.v.drawingInput
      if (d) d.ended([e.pointerId], e.timeStamp, false)
      else this.finishTouches([e.pointerId], e.timeStamp, false)
      this.points.delete(e.pointerId)
    }
    const cancelID = (id: number, t: number) => {
      if (!this.points.has(id)) return
      const d = this.v.drawingInput
      if (d) d.ended([id], t, true)
      else this.finishTouches([id], t, true)
      this.points.delete(id)
    }
    const cancel = (e: PointerEvent) => cancelID(e.pointerId, e.timeStamp)
    const menu = (e: Event) => e.preventDefault()
    el.addEventListener('pointerdown', down)
    el.addEventListener('pointermove', move)
    el.addEventListener('pointerup', up)
    el.addEventListener('pointercancel', cancel)
    el.addEventListener('lostpointercapture', cancel)
    el.addEventListener('contextmenu', menu)
    this.bound = {
      el,
      cancel: cancelID,
      off: () => {
        el.removeEventListener('pointerdown', down)
        el.removeEventListener('pointermove', move)
        el.removeEventListener('pointerup', up)
        el.removeEventListener('pointercancel', cancel)
        el.removeEventListener('lostpointercapture', cancel)
        el.removeEventListener('contextmenu', menu)
      },
    }
  }

  /**
   * 宿主上层的手势（副图分隔线拖高、长按换副图顺序）认领了这根手指：
   * 照 UIKit 的 cancelsTouchesInView，把图这边已经开始的那一段按「取消」收掉。
   */
  cancelPointer(id: number, now: number = performance.now()): void {
    this.bound?.cancel(id, now)
  }

  /**
   * 手指还按着页面就进了后台（锁屏、上滑回桌面、切到别的页）：浏览器不一定补 pointercancel，
   * 按着时冻住的视野（十字线 / 画线拖动）就一直不跟最新。这里把还按着的全部按「取消」收掉。
   */
  cancelAllPointers(now: number = performance.now()): void {
    for (const id of [...this.points.keys()]) this.bound?.cancel(id, now)
    if (!this.points.size) this.cancelAxisFreeze()
  }

  detach(): void {
    this.bound?.off()
    this.bound = null
    this.points.clear()
  }

  /** didMoveToWindow(nil)：手势、动画、价格轴锚点全部清掉。 */
  teardown(): void {
    this.v.animation = null
    this.gesture.touches = []
    this.gesture.reset()
    this.gesture.endAxisTapCandidate()
    this.cancelAxisFreeze()
    this.points.clear()
  }

  /** 某根手指此刻的位置（点，相对画布左上角）；画线层也用它。 */
  location(id: number | undefined): Point {
    return (id != null ? this.points.get(id) : undefined) ?? this.gesture.startPoint
  }

  private get gestureReady(): boolean {
    const s = this.state
    return s != null && !s.input.series.isEmpty && this.v.chartLayout != null
  }

  // ---------------------------------------------------------------- touchesBegan

  touchesBegan(ids: number[], now: number): void {
    const L = this.v.chartLayout
    if (!this.gestureReady || !L) return
    const g = this.gesture
    this.v.animation = null
    const firstFinger = g.touches.length === 0
    for (const t of ids) if (!g.touches.includes(t)) g.touches.push(t)
    if (firstFinger) this.v.onInteractionBegan?.()
    if (g.touches.length >= 2) {
      this.beginPinch()
      return
    }
    const q = this.location(g.touches[0])
    g.reset()
    g.askedHistory = false
    g.startPoint = { ...q }
    g.startView = this.state?.viewport.view ?? g.startView
    g.startTransform = this.state?.viewport.price ?? priceTransform()
    g.startRange = this.v.chartPriceRange
    g.velocity.add(q.x, now)
    const s = this.state
    if (s && isManualTransform(s.viewport.price) && L.hitsAutoFit(q.x, q.y)) {
      g.mode = 'autoFit'
      return
    }
    if (q.x > L.plotW && q.y < L.mainH) { g.mode = 'axisPrice'; return }
    if (q.x > L.plotW) { g.mode = 'subAxis'; return }
    if (q.y >= L.mainH && q.y < L.mainH + AICoinBehavior.timeHeight) { g.mode = 'parentScroll'; return }
    g.mode = this.hitsCrosshairCenter(q) ? 'crosshair' : 'pan'
    if (g.mode === 'crosshair') { g.owner = g.touches[0]; this.grabCrosshair(q) }
    if (this.state?.overlay.crosshair == null) this.scheduleLongPress(q)
  }

  // ---------------------------------------------------------------- touchesMoved

  private lastParentY: number | null = null

  touchesMoved(now: number, ids?: readonly number[]): void {
    const L = this.v.chartLayout
    const g = this.gesture
    const mode = g.mode
    if (!this.gestureReady || !L || !mode) return
    if (mode === 'pinch' && g.touches.length >= 2) {
      this.updatePinch(L, ids)
      return
    }
    // 十字线只认它的主人那根手指；其余模式这时只会有一根手指（两根就进捏合了）。
    const q = this.location(mode === 'crosshair' ? (g.owner ?? g.touches[0]) : g.touches[0])
    if (mode === 'pan' && g.reboundHandoff) {
      // 捏合越界抬掉一根、回弹还没走完：这根手指不抢画面，起手点跟着回弹重设，弹完那一帧接着拖——不跳、不和回弹打架
      g.startPoint = { ...q }
      g.startView = this.state?.viewport.view ?? g.startView
      if (this.v.animation == null) g.reboundHandoff = false
      return
    }
    const dx = q.x - g.startPoint.x
    const dy = q.y - g.startPoint.y
    g.moved = Math.max(g.moved, Math.sqrt(dx * dx + dy * dy))
    if (g.moved > ChartGesture.longPressSlopPt) g.cancelLongPress()
    switch (mode) {
      case 'pinch': case 'autoFit': case 'subAxis': break
      case 'axisPrice': this.dragPriceAxis(dy, L); break
      case 'verticalPan': this.panPrice(dy, L); break
      case 'parentScroll': this.parentScroll(q.y); break
      case 'crosshair': this.moveCrosshair({ x: q.x + g.grab.x, y: q.y + g.grab.y }, L); break
      case 'pan': {
        if (g.moved < ChartGesture.panSlopPt) break
        if (!g.directionChosen) {
          g.directionChosen = true
          if (Math.abs(dy) > 1.5 * Math.abs(dx)) {
            // 按在十字线的横线（价格线）上竖着拖：就是要把价格线挪上挪下
            if (this.hitsCrosshairLine(g.startPoint)) {
              g.mode = 'crosshair'
              g.owner = g.touches[0]
              this.grabCrosshair(g.startPoint)
              this.moveCrosshair({ x: q.x + g.grab.x, y: q.y + g.grab.y }, L)
              break
            }
            g.mode = isManualTransform(g.startTransform) && g.startPoint.y < L.mainH ? 'verticalPan' : 'parentScroll'
            if (g.mode === 'verticalPan') this.panPrice(dy, L)
            else { this.lastParentY = g.startPoint.y; this.parentScroll(q.y) }
            break
          }
        }
        this.clearCrosshair()
        g.velocity.add(q.x, now)
        this.panPlot(dx, L)
        break
      }
    }
  }

  /** UIScrollView 接手的那一段：网页里交给宿主（图表内容比可视区高时滚宿主）。 */
  private parentScroll(y: number): void {
    const prev = this.lastParentY ?? this.gesture.startPoint.y
    this.lastParentY = y
    const d = y - prev
    if (d !== 0) this.v.onParentScroll?.(-d)
  }

  // ---------------------------------------------------------------- touchesEnded / Cancelled

  finishTouches(ids: number[], now: number, cancelled: boolean): void {
    this.processTouchEnd(ids, now, cancelled)
    if (this.gesture.touches.length === 0) {
      this.lastParentY = null
      this.endAxisFreeze()
      this.v.onInteractionEnded?.()
    }
  }

  private processTouchEnd(ids: number[], now: number, cancelled: boolean): void {
    const g = this.gesture
    const wasPinch = g.mode === 'pinch'
    const endPoint = this.location(ids[0])
    const axisTapCandidate = g.lastAxisTap
    g.lastAxisTap = null
    const plotTapCandidate = g.lastPlotTap
    g.lastPlotTap = null
    try {
      if (cancelled) {
        g.touches = []
        g.reset()
        this.v.animation = null
        this.clearAxisScaleAnchor()
        this.settleView()
        return
      }
      const liftedAll = g.touches.every(t => ids.includes(t))
      // 拎十字线那根手指抬起来了、别的手指还按着：这一轮十字线照样就此放下，剩下的手指不接班。
      const ownerLifted = g.mode === 'crosshair' && g.owner != null && ids.includes(g.owner)
      g.touches = g.touches.filter(t => !ids.includes(t))
      g.cancelLongPress()
      if (wasPinch) {
        if (g.touches.length >= 2) {
          this.beginPinch()
          return   // 三指抬掉一根，剩下的两指接着捏
        }
        if (g.touches.length === 1 && this.v.chartLayout) {
          const q = this.location(g.touches[0])
          // 捏合越过软边时抬掉一根：剩下那根接着拖，拖动走的是硬夹（ViewMath.dragging），根宽得先回到边界里。
          // 和两指都松开同一条路（settleView）：绕捏的那一点弹回去，「减少动效」下直接到位；弹的这一程剩下那根不接管。
          const s0 = this.state, L0 = this.v.chartLayout
          const target = s0 ? this.pinchSettleTarget(s0.viewport.view, L0) : null
          const overshoot = !!target && !!s0 && !(target.to === s0.viewport.view.to && target.span === s0.viewport.view.span)
          if (overshoot) this.settleView()
          g.reset()
          g.reboundHandoff = overshoot && this.v.animation != null
          g.mode = 'pan'
          g.cameFromPinch = true
          g.startPoint = { ...q }
          g.startView = this.state?.viewport.view ?? g.startView
          g.startTransform = this.state?.viewport.price ?? priceTransform()
          g.velocity.add(q.x, now)
          return
        }
        g.reset()
        this.settleView()
        return
      }
      if (!(liftedAll || g.touches.length === 0 || ownerLifted)) return
      // 捏合越界降下来的那根手指在回弹途中抬起：回弹照走完，不判轻点、不起惯性（惯性会把没弹回的根宽连动画一起换掉）
      if (g.reboundHandoff && this.v.animation != null) { g.reset(); return }
      const mode = g.mode
      this.clearAxisScaleAnchor()
      const wasLongPress = g.longPressActivated
      const moved = g.moved
      const cameFromPinch = g.cameFromPinch
      g.velocity.add(endPoint.x, now)
      const v = g.velocity.velocity
      g.reset()
      if (wasLongPress) { this.finishCrosshairSelection(); return }
      // 拎着十字线微调几个点也是在挪它，门槛比拖图那边的轻点低一半，不然往上挪 5 点一松手十字线就被收掉了
      if ((mode === 'pan' && moved < ChartGesture.panSlopPt * 2 || mode === 'crosshair' && moved < ChartGesture.panSlopPt) && !cameFromPinch) {
        this.handleTap(now, plotTapCandidate)
        return
      }
      if (mode === 'autoFit') {
        const L = this.v.chartLayout
        if (moved < ChartGesture.panSlopPt * 2 && L && L.hitsAutoFit(endPoint.x, endPoint.y)) this.resetPriceScale()
        return
      }
      if (mode === 'subAxis' && moved < ChartGesture.panSlopPt * 2) {
        const L = this.v.chartLayout, s = this.state
        if (L && s && s.input.options.allowSubInversion) {
          const id = L.panes.find(p => p.indicator != null && endPoint.y >= p.y && endPoint.y <= p.y + p.h)?.indicator as IndicatorID | null | undefined
          if (id) {
            const inv = s.input.subInverted.includes(id)
              ? s.input.subInverted.filter(x => x !== id) : [...s.input.subInverted, id]
            this.state = withInput(s, { subInverted: inv })
          }
        }
        return
      }
      if (mode === 'axisPrice' && moved < ChartGesture.panSlopPt * 2) {
        this.handleAxisTap(now, endPoint, axisTapCandidate)
        return
      }
      if (mode === 'pan' && this.state?.overlay.crosshair == null) {
        this.startFling(v)
        return
      }
      this.finishCrosshairSelection()
      this.settleView()
    } finally {
      if (g.touches.length === 0 && this.v.animation == null) this.settleGeometry()
    }
  }

  private clearAxisScaleAnchor(): void {
    const s = this.state
    if (s && s.viewport.axisScaleAnchor != null) this.state = withViewport(s, { axisScaleAnchor: null })
  }

  // ---------------------------------------------------------------- 平移、价格轴

  private panPlot(dx: number, L: Layout): void {
    const s = this.state
    if (!s) return
    const view = ViewMath.dragging(this.gesture.startView.dragged(dx, L.plotW), s.input.series, L.plotW, s.input.options.anchor)
    this.state = withViewport(s, { view })
    this.viewDidChange(view)
  }

  private panPrice(dy: number, L: Layout): void {
    const s = this.state, g = this.gesture, r = this.v.renderer
    if (!s || !isManualTransform(g.startTransform) || !g.startRange || !r) return
    const auto: PriceTransform = { ...g.startTransform, zoom: 1, centerFraction: 0.5 }
    const automatic = r.priceRange(this.v.width, this.v.height, undefined, auto)
    const start = g.startPoint.y
    const mode = effectivePriceMode(s)
    const delta = pOf(start, L.main, g.startRange, mode) - pOf(start + dy, L.main, g.startRange, mode)
    const center = g.startTransform.centerFraction + delta / Math.max(1e-12, automatic.hi - automatic.lo)
    this.state = withViewport(s, { price: { ...s.viewport.price, centerFraction: clampedCenter(center, s.viewport.price.zoom) } })
  }

  private dragPriceAxis(dy: number, L: Layout): void {
    const s = this.state, g = this.gesture
    if (!s || g.moved < ChartGesture.panSlopPt) return
    if (!g.axisStarted) {
      g.axisStarted = true
      g.startPoint = { x: g.startPoint.x, y: g.startPoint.y + dy }
      const range = this.v.chartPriceRange
      if (range) this.state = withViewport(s, { axisScaleAnchor: (range.lo + range.hi) / 2 })
      return
    }
    const zoom = axisZoom(g.startTransform.zoom, dy, L.mainH)
    this.state = withViewport(s, {
      price: { ...s.viewport.price, zoom, centerFraction: clampedCenter(g.startTransform.centerFraction, zoom) },
    })
  }

  // ---------------------------------------------------------------- 双指

  private beginPinch(): void {
    const g = this.gesture
    if (g.touches.length < 2 || g.mode === 'crosshair') return
    this.cancelAxisFreeze()
    this.clearCrosshair()
    const f = this.twoFinger()
    g.cancelLongPress()
    this.clearAxisScaleAnchor()
    g.mode = 'pinch'
    g.trace = `begin d=${f.d}`
    g.pinchD0 = f.d
    this.rebasePinch(f)
    g.pinchActive = false
    g.pinchAxis = 'undecided'
    g.pinchFresh.clear()
    g.moved = Number.MAX_VALUE
  }

  /** 死区里这一轮每根手指都报过新位置了吗（见 GestureState.pinchFresh）。不知道是哪根手指动的就当报齐。 */
  private pinchFrameComplete(ids?: readonly number[]): boolean {
    const g = this.gesture
    if (!ids || ids.length === 0) { g.pinchFresh.clear(); return true }
    const repeat = ids.some(id => g.pinchFresh.has(id))
    for (const id of ids) g.pinchFresh.add(id)
    const all = g.touches.slice(0, 2).every(t => g.pinchFresh.has(t))
    if (!(repeat || all)) return false
    g.pinchFresh.clear()
    return true
  }

  private rebasePinch(f: TwoFinger): void {
    const g = this.gesture
    g.pinchD0 = f.d
    g.pinchSx0 = f.sx
    g.pinchSy0 = f.sy
    g.pinchMid0 = f.mid
    g.pinchMidY0 = f.my
  }

  /**
   * 双指的一帧（移植 iOS a8012401「横屏捏合手感」，竖屏同样生效）：
   * - 死区：横向或纵向张开量变过 3pt（ChartGesture.pinchSlopPt）才认缩放；死区里两指一起挪是平移。
   *   越过门槛那一帧只重设基准、定下缩哪根轴，不缩放——门槛小也不会「嘭」地跳。
   * - 轴锁：竖着摆、竖着捏（纵向张开量 > 横向 1.5 倍）、中点在主图里 → 这一捏只缩价格轴；其余缩时间轴。
   * - 焦点：时间轴缩放钉住两指中点那一根；视野贴着最新一根时按最新一根锚住。
   * - 软边：根宽越过 [1.6, 40] 按对数阻尼还能再走一点（最多 ×0.85 / ×1.15，ViewMath.softSpacing），
   *   松手或双指变单指时 settleView 绕捏的那一点弹回；prefers-reduced-motion 下不越界、硬停在边界（iOS aedc26df）。
   */
  private updatePinch(L: Layout, ids?: readonly number[]): void {
    const s = this.state, g = this.gesture
    if (!s) return
    const f = this.twoFinger()
    g.trace = `move sx=${f.sx} sy=${f.sy} axis=${g.pinchAxis} active=${g.pinchActive}`
    // 两指太近的那几帧只当噪声，但基准要跟着走：不跟的话，等间距一跨过门槛，比例会一次性甩出去。
    if (f.d < ChartGesture.minPinchSpanPt) {
      this.rebasePinch(f); g.pinchActive = false; g.pinchAxis = 'undecided'
      return
    }
    if (!g.pinchActive) {
      // 死区期间基准不跟着每一帧走（跟了就永远越不过门槛），但平移不看门槛（A-06）。
      if (!this.pinchFrameComplete(ids)) { this.panPinch(f.mid, L); return }
      const dsx = Math.abs(f.sx - g.pinchSx0), dsy = Math.abs(f.sy - g.pinchSy0)
      if (!(Math.max(dsx, dsy) > ChartGesture.pinchSlopPt)) {
        this.panPinch(f.mid, L)
        return
      }
      g.pinchActive = true
      const inMain = f.my >= L.main.y && f.my <= L.main.y + L.main.h && f.mid <= L.plotW
      const vertical = f.sy > 1.5 * f.sx && dsy > ChartGesture.pinchSlopPt && inMain && this.v.chartPriceRange != null
      g.pinchAxis = vertical ? 'price' : 'time'
      this.rebasePinch(f)
      if (vertical) {
        g.pinchStartZoom = s.viewport.price.zoom
        g.pinchSyStart = f.sy
        g.pinchPrice = this.price(f.my)
      } else if (!s.input.series.isEmpty) {
        // 回弹半途又捏上去：画面根宽可能在边界外，从它倒推手指那一侧，第一帧不跳
        g.pinchRawSpacing = ViewMath.rawSpacingForSoft(s.viewport.view.barSpacing(s.input.series.step, L.plotW))
      }
      return
    }
    if (g.pinchAxis === 'price') this.pinchPrice(f, L)
    else this.pinchTime(f, L)
  }

  /** 时间轴捏合的一帧：倍数只看横向张开量；贴着最新 → 末根钉住、中点漂移不算；不贴 → 先跟中点平移再绕中点缩放。 */
  private pinchTime(f: TwoFinger, L: Layout): void {
    const s = this.state, g = this.gesture
    if (!s) return
    if (!(f.sx >= ChartGesture.minPinchSpanPt) || !(g.pinchSx0 >= ChartGesture.minPinchSpanPt)) {
      // 两指几乎竖成一条线：横向张开量太小，比值全是噪声。只换基准。
      this.rebasePinch(f)
      return
    }
    const b = s.input.series, v0 = s.viewport.view, anchor = s.input.options.anchor
    if (b.isEmpty) { this.rebasePinch(f); return }
    const lo = AICoinBehavior.minimumSpacing, hi = AICoinBehavior.maximumSpacing
    if (!(g.pinchRawSpacing > 0)) g.pinchRawSpacing = ViewMath.rawSpacingForSoft(v0.barSpacing(b.step, L.plotW))
    const reduce = reduceMotion()
    let raw = g.pinchRawSpacing * f.sx / g.pinchSx0
    raw = reduce ? Math.min(hi, Math.max(lo, raw)) : ViewMath.boundedRawSpacing(raw)
    g.pinchRawSpacing = raw
    const spacing = reduce ? raw : ViewMath.softSpacing(raw)
    const pinned = ViewMath.isPinnedToLatest(v0, b, L.plotW, anchor)
    const base = pinned ? v0 : ViewMath.clampedOffset(v0.dragged(f.mid - g.pinchMid0, L.plotW), b, L.plotW, anchor)
    // 只夹左右、不夹根宽（夹根宽就没有软边了）
    const view = ViewMath.pinched(base, b, L.plotW, spacing, f.mid, pinned, anchor)
    this.rebasePinch(f)
    this.state = withViewport(s, { view })
    this.viewDidChange(view)
    this.reportZoomLimit(view, L)
  }

  /**
   * 价格轴捏合的一帧：两指竖着张开 = 价格放大、捏拢 = 缩小，绕起捏时中点底下那个价位；
   * 倍数走价格轴竖拖同一条曲线（axisZoom），进的也是同一个手动态（「A」徽章、双击价格轴照常回自动）。时间轴整轮不动。
   */
  private pinchPrice(f: TwoFinger, L: Layout): void {
    const s = this.state, g = this.gesture, r = this.v.renderer
    if (!s || !r || !(g.pinchSyStart > 0) || !(f.sy >= ChartGesture.minPinchSpanPt)) return
    const unit = Math.max(L.mainH / 4, 1)
    const zoom = axisZoom(g.pinchStartZoom, -unit * Math.log2(f.sy / g.pinchSyStart), L.mainH)
    const auto: PriceTransform = { ...s.viewport.price, zoom: 1, centerFraction: 0.5 }
    const automatic = r.priceRange(this.v.width, this.v.height, undefined, auto)
    const frac = Math.min(1, Math.max(0, (f.my - L.main.y) / Math.max(1, L.main.h)))
    const inverted = this.v.chartPriceRange?.inverted ?? s.viewport.price.inverted
    const gy = inverted ? frac : 1 - frac
    const mode = effectivePriceMode(s) === 'log' ? 'log' : 'linear'
    const centerFraction = anchoredCenter(g.pinchPrice, gy, zoom, automatic.lo, automatic.hi, mode)
    g.pinchMid0 = f.mid
    this.state = withViewport(s, { price: { ...s.viewport.price, zoom, centerFraction }, axisScaleAnchor: null })
  }

  private panPinch(m: number, L: Layout): void {
    const g = this.gesture
    const dx = m - g.pinchMid0
    g.pinchMid0 = m
    const s = this.state
    if (!s || Math.abs(dx) === 0) return
    const view = this.clamp(s.viewport.view.dragged(dx, L.plotW), L.plotW)
    this.state = withViewport(s, { view })
    this.viewDidChange(view)
  }

  private twoFinger(): TwoFinger {
    const pts = this.gesture.touches.map(t => this.location(t))
    const n = pts.length || 1
    const mx = pts.reduce((a, p) => a + p.x, 0) / n
    const my = pts.reduce((a, p) => a + p.y, 0) / n
    const sx = 2 * pts.reduce((a, p) => a + Math.abs(p.x - mx), 0) / n
    const sy = 2 * pts.reduce((a, p) => a + Math.abs(p.y - my), 0) / n
    return { d: Math.hypot(sx, sy), mid: mx, my, sx, sy }
  }

  private reportZoomLimit(v: ViewWindow, L: Layout): void {
    const s = this.state
    if (!s || s.input.series.count === 0) return
    const sp = v.barSpacing(s.input.series.step, L.plotW)
    const atLimit = sp <= Chart.minBarSpacing * 1.001 || sp >= Chart.maxBarSpacing * 0.999
    // 手机网页没有震动（ChartHaptics.boundary），只记状态
    this.gesture.wasAtZoomLimit = atLimit
  }

  // ---------------------------------------------------------------- 十字线

  hitsCrosshairCenter(p: Point): boolean {
    const c = this.v.renderer?.crosshairCenter(this.v.width, this.v.height)
    if (!c) return false
    return Math.abs(p.x - c.x) <= 22 && Math.abs(p.y - c.y) <= 22
  }

  /** 横线（价格线）上下 22 点、图区宽度以内都算按在线上；竖着拖就挪价格线，横着拖照旧拖图。 */
  hitsCrosshairLine(p: Point): boolean {
    const c = this.v.renderer?.crosshairCenter(this.v.width, this.v.height)
    const L = this.v.chartLayout
    if (!c || !L) return false
    return p.x >= 0 && p.x <= L.plotW && Math.abs(p.y - c.y) <= 22
  }

  /** 从 p 拎起已经在图上的十字线：记下交叉点相对手指的距离，钉住坐标。 */
  private grabCrosshair(p: Point): void {
    const c = this.v.renderer?.crosshairCenter(this.v.width, this.v.height)
    this.gesture.grab = c ? { x: c.x - p.x, y: c.y - p.y } : { x: 0, y: 0 }
    this.beginAxisFreeze()
  }

  private scheduleLongPress(q: Point): void {
    const g = this.gesture
    g.cancelLongPress()
    g.longPress = setTimeout(() => {
      g.longPress = null
      const L = this.v.chartLayout
      if (!L || g.moved > ChartGesture.longPressSlopPt || g.touches.length !== 1) return
      g.longPressActivated = true
      g.mode = 'crosshair'
      g.owner = g.touches[0]
      this.beginAxisFreeze()
      this.moveCrosshair(q, L)
    }, ChartGesture.longPressMs)
  }

  moveCrosshair(q: Point, L: Layout): void {
    const s = this.state
    if (!s || s.input.series.count === 0) return
    const b = s.input.series
    const px = Math.max(0, Math.min(L.plotW, q.x))
    const t = s.viewport.view.t(px, L.plotW)
    const i = b.index(t)
    const c: Crosshair = { index: i, pane: null, t: null, price: this.price(q.y) }
    const pane = L.panes.slice(1).find(p => q.y >= p.y && q.y <= p.y + p.h)
    if (pane && this.v.renderer) {
      c.pane = pane.indicator as IndicatorID | null
      c.price = subCrosshairValue(this.v.renderer, q.y, pane)
    } else if (s.overlay.magnet) c.price = b.close[i]
    this.state = withOverlay(s, { crosshair: c, orderFlowSelected: null })
  }

  private finishCrosshairSelection(): void {
    const s = this.state
    const cross = s?.overlay.crosshair
    if (!s || s.input.options.crossPrice !== 'close' || !cross || cross.pane != null
      || cross.index < 0 || cross.index >= s.input.series.count) return
    this.state = withOverlay(s, { crosshair: { ...cross, price: null } })
  }

  /** 十字线按根步进（外部按钮 / 键盘用）。 */
  moveCrosshairBy(step: number): void {
    const s = this.state
    const c = s?.overlay.crosshair
    if (step === 0 || !s || s.input.series.count === 0 || !c) return
    const b = s.input.series
    const next = c.index + step
    if (next < 0 || next >= b.count) return
    const wasOnClose = c.pane == null && c.price != null && c.index >= 0 && c.index < b.count
      && Math.abs((c.price ?? 0) - b.close[c.index]) < Number.EPSILON
    const moved: Crosshair = { ...c, index: next, t: null }
    if (c.pane == null && (s.overlay.magnet || wasOnClose)) moved.price = b.close[next]
    let out = withOverlay(s, { crosshair: moved })
    const L = this.v.chartLayout
    if (L && L.plotW > 0) {
      const x = s.viewport.view.x(b.time(next), L.plotW)
      const inset = Math.min(40, L.plotW * 0.1)
      if (x < inset || x > L.plotW - inset) {
        const dx = x < inset ? x - inset : x - (L.plotW - inset)
        out = withViewport(out, { view: clampView(s.viewport.view.shifted(dx, L.plotW), b, L.plotW, s.input.options.anchor) })
      }
    }
    this.state = out
  }

  clearCrosshair(): void {
    const s = this.state
    if (!s || s.overlay.crosshair == null) return
    this.state = withOverlay(s, { crosshair: null })
  }

  nudge(dx: number): void {
    const s = this.state, L = this.v.chartLayout
    if (!s || !L || !(L.plotW > 0) || dx === 0) return
    const v = clampView(s.viewport.view.shifted(dx, L.plotW), s.input.series, L.plotW, s.input.options.anchor)
    if (v.equals(s.viewport.view)) return
    this.state = withViewport(s, { view: v })
    this.viewDidChange(v)
  }

  reveal(from: number, to: number): void {
    const s = this.state, L = this.v.chartLayout
    if (!s || !L || !(L.plotW > 0) || !(to > from)) return
    const cur = s.viewport.view
    if (from >= cur.from && to <= cur.to) return
    let span = cur.span
    if ((to - from) * 1.16 > span) span = (to - from) * 1.25
    const center = (from + to) / 2
    const v = clampView(new ViewWindow(center + span / 2, span), s.input.series, L.plotW, s.input.options.anchor)
    this.state = withViewport(s, { view: v })
    this.viewDidChange(v)
  }

  // ---------------------------------------------------------------- 点按

  private handleTap(now: number, previous: { ms: number; x: number; y: number } | null): void {
    const g = this.gesture
    const p = g.startPoint
    const isDouble = previous != null && now - previous.ms < 300 && Math.hypot(p.x - previous.x, p.y - previous.y) < 44
    if (isDouble) {
      g.lastPlotTap = null
      if (this.state?.overlay.crosshair != null) this.clearCrosshair()
      this.selectOrderFlow(null)
      this.resetPriceScale()
      this.scrollToLatest()
      return
    }
    g.lastPlotTap = { ms: now, x: p.x, y: p.y }
    // 提醒线（画线删了 / 藏了还在生效的提醒）：十字线没开时点中它就开提醒，不出十字线
    if (this.state?.overlay.crosshair == null && this.v.signalTap?.(p.x, p.y)) return
    const r = this.v.renderer
    if (r && OF.orderFlowHit && OF.candleHit && !OF.candleHit(r, p.x, p.y, this.v.width, this.v.height)) {
      const hit = OF.orderFlowHit(r, p.x, p.y, this.v.width, this.v.height)
      if (hit) {
        this.selectOrderFlow(OF.orderFlowIsSelected?.(r, hit) ? null : hit.key)
        return
      }
    }
    if (this.state?.overlay.orderFlowSelected != null) {
      this.selectOrderFlow(null)
      return
    }
    if (this.state?.overlay.crosshair != null) {
      this.clearCrosshair()
    } else {
      const L = this.v.chartLayout
      if (L) {
        this.moveCrosshair(g.startPoint, L)
        this.finishCrosshairSelection()
        this.v.onTapped?.()
      }
    }
  }

  selectOrderFlow(key: OrderFlowGroupKey | null): void {
    const s = this.state
    if (!s) return
    const same = sameOrderFlowKey(s.overlay.orderFlowSelected, key)
    if (same && !(key != null && s.overlay.crosshair != null)) return
    this.state = withOverlay(s, key != null ? { orderFlowSelected: key, crosshair: null } : { orderFlowSelected: null })
  }

  resetPriceScale(): void {
    const s = this.state
    if (!s) return
    this.state = withViewport(s, { price: { ...s.viewport.price, zoom: 1, centerFraction: 0.5 }, axisScaleAnchor: null })
  }

  private handleAxisTap(now: number, point: Point, previous: { ms: number; y: number } | null): void {
    const L = this.v.chartLayout, g = this.gesture
    if (!L || !(g.startPoint.y < L.mainH)) return
    const isDouble = previous != null && now - previous.ms < 300 && Math.abs(point.y - previous.y) < 44
    if (!isDouble) {
      g.lastAxisTap = { ms: now, y: point.y }
      this.resetPriceScale()
      return
    }
    g.lastAxisTap = null
    const s = this.state
    if (!s || !s.input.options.allowMainInversion) return
    const inverted = !s.viewport.price.inverted
    this.state = withViewport(s, { price: { ...s.viewport.price, inverted, zoom: 1, centerFraction: 0.5 } })
    if (inverted) this.v.onNotice?.('主图已上下翻转，再双击价格轴翻回来')
  }

  scrollToLatest(animated = true): void {
    this.cancelAxisFreeze()
    const s = this.state, L = this.v.chartLayout
    if (!s || !L || s.input.series.count === 0) return
    const b = s.input.series
    const target = ViewMath.reset(b, L.plotW, s.viewport.view.barSpacing(b.step, L.plotW), s.input.options.anchor)
    if (!animated || !this.v.attached || reduceMotion()) {
      this.state = withViewport(s, { view: target })
      this.viewDidChange(target, 'program')
      return
    }
    this.animate(s.viewport.view, target, false, 'program')
  }

  get isAtLatest(): boolean {
    const s = this.state
    if (!s || s.input.series.count === 0) return true
    return s.viewport.view.to >= s.input.series.lastTime
  }

  // ---------------------------------------------------------------- 惯性、回弹

  private startFling(speed: number): void {
    const s = this.state, L = this.v.chartLayout
    if (!s || !L) return
    const settled = this.clamp(s.viewport.view, L.plotW)
    if (Math.abs(s.viewport.view.to - settled.to) / s.viewport.view.span * L.plotW > 0.01) { this.settleView(); return }
    const run = reduceMotion() ? null : FlingRun.make(speed, s.viewport.view, L.plotW)
    if (!run) { this.settleView(); return }
    const t0 = performance.now()
    this.v.animation = (now: number) => {
      const cur = this.state
      if (!cur) return true
      const { view: v, done } = run.frame(now - t0)
      const view = this.clamp(v, L.plotW)
      const hit = Math.abs(view.to - v.to) / v.span * L.plotW > 0.01
      this.state = withViewport(cur, { view })
      this.viewDidChange(view)
      return done || hit
    }
  }

  private settleGeometry(): void {
    const s = this.state, L = this.v.chartLayout
    if (!s || !L || !(s.viewport.view.span > 0)) return
    const v = s.viewport.view
    const target = this.pinchSettleTarget(v, L) ?? this.clamp(v, L.plotW)
    const offPx = Math.abs(target.to - v.to) / v.span * L.plotW
    if (!(offPx > 0.01 || Math.abs(target.span - v.span) / v.span > 1e-9)) return
    this.settleView()
  }

  /**
   * 根宽在 [1.6, 40] 外面（捏合软边）时该弹回到哪：绕最后那一捏的两指中点弹回，贴着最新的照旧钉最新——
   * 不是绕右缘，不然捏着中间放大到头一松手画面整体往右一滑（iOS pinchSettleTarget）。根宽在界内返回 null。
   */
  pinchSettleTarget(v: ViewWindow, L: Layout): ViewWindow | null {
    const s = this.state
    if (!s || s.input.series.isEmpty || !(v.span > 0)) return null
    const b = s.input.series, anchor = s.input.options.anchor
    const sp = v.barSpacing(b.step, L.plotW)
    const lo = AICoinBehavior.minimumSpacing, hi = AICoinBehavior.maximumSpacing
    if (!(sp < lo * (1 - 1e-9) || sp > hi * (1 + 1e-9))) return null
    const pinned = ViewMath.isPinnedToLatest(v, b, L.plotW, anchor)
    return this.clamp(ViewMath.pinched(v, b, L.plotW, Math.min(hi, Math.max(lo, sp)), this.gesture.pinchMid0, pinned, anchor), L.plotW)
  }

  /** 两端拉出的空白松手回边界、捏合越过软边的根宽弹回 [1.6, 40]；「减少动效」下直接到位。 */
  private settleView(): void {
    const s = this.state, L = this.v.chartLayout
    if (!s || !L || !(s.viewport.view.span > 0)) return
    const v = s.viewport.view
    const target = this.pinchSettleTarget(v, L) ?? this.clamp(v, L.plotW)
    const spanOff = Math.abs(target.span - v.span) / v.span > 1e-9
    if (!reduceMotion() && (Math.abs(v.to - target.to) / v.span * L.plotW > 0.01 || spanOff)) {
      this.animate(v, target, true)
    } else {
      this.state = withViewport(s, { view: target })
      this.viewDidChange(target)
    }
  }

  private animate(a: ViewWindow, b: ViewWindow, rebound = false, source: ViewChangeSource = 'gesture'): void {
    const t0 = performance.now()
    this.v.animation = (now: number) => {
      const cur = this.state
      if (!cur) return true
      const elapsed = now - t0
      const { view, done } = rebound ? ViewTransition.rebound(a, b, elapsed) : ViewTransition.frame(a, b, elapsed)
      this.state = withViewport(cur, { view })
      this.viewDidChange(view, source)
      return done
    }
  }

  private clamp(v: ViewWindow, plotW: number): ViewWindow {
    const s = this.state
    if (!s) return v
    return clampView(v, s.input.series, plotW, s.input.options.anchor)
  }

  viewDidChange(v: ViewWindow, source: ViewChangeSource = 'gesture'): void {
    this.v.onViewChanged?.(v)
    if (source === 'gesture') this.v.onUserViewChanged?.(v)
    const s = this.state
    if (!s) return
    if (ViewMath.needsMoreHistory(v, s.input.series)) {
      if (!this.gesture.askedHistory) {
        this.gesture.askedHistory = true
        this.v.onNeedsHistory?.()
      }
    } else {
      this.gesture.askedHistory = false
    }
  }

  price(y: number): number {
    const s = this.state, L = this.v.chartLayout, r = this.v.chartPriceRange
    if (!s || !L || !r) return 0
    return pOf(y, L.main, r, effectivePriceMode(s))
  }

  // ---------------------------------------------------------------- 坐标轴冻结（十字线拖动时视野不跟最新走）

  beginAxisFreeze(): void {
    const v = this.v, s = this.state, L = v.chartLayout, range = v.chartPriceRange
    if (v.frozenAxes || !s || s.input.series.isEmpty || !L || !(L.plotW > 0) || !(s.viewport.view.span > 0) || !range) return
    const b = s.input.series, view = s.viewport.view
    const spacing = view.barSpacing(b.step, L.plotW)
    const latest = ViewMath.reset(b, L.plotW, spacing, s.input.options.anchor)
    const following = Math.abs(view.to - latest.to) / view.span * L.plotW < spacing
    v.frozenAxes = { view, range, followingLatest: following }
    v.pinPriceRange(range)
  }

  endAxisFreeze(): void {
    const frozen = this.v.frozenAxes
    if (!frozen) return
    this.cancelAxisFreeze()
    const s = this.state, L = this.v.chartLayout
    if (!frozen.followingLatest || !s || s.input.series.isEmpty || !L || !(L.plotW > 0) || !(s.viewport.view.span > 0)) return
    const b = s.input.series, view = s.viewport.view
    const latest = ViewMath.reset(b, L.plotW, view.barSpacing(b.step, L.plotW), s.input.options.anchor)
    if (!(Math.abs(latest.to - view.to) / view.span * L.plotW > 0.01)) return
    this.state = withViewport(s, { view: latest })
    this.viewDidChange(latest, 'program')
  }

  cancelAxisFreeze(): void {
    if (!this.v.frozenAxes) return
    this.v.frozenAxes = null
    this.v.pinPriceRange(null)
    this.v.setNeedsRedraw(Parts.all)
  }
}
