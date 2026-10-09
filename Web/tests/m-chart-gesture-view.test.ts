// ChartView 触摸状态机（Pointer Events 驱动），移植自 KanpanChart/Tests/KanpanChartTests/ChartGestureTests.swift
// 里与审查 B 线修复相关的几条。场地：node 里假的 DOM 元素、帧循环不跑，只看状态与模型。
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { ViewMath, ViewWindow, pOf } from '../src/m/chart/geometry'
import { BarSeries, INTERVAL_STEP } from '../src/m/chart/series'
import { effectivePriceMode, makeState, withOverlay, withViewport } from '../src/m/chart/state'
import type { ChartState } from '../src/m/chart/state'
import { ChartView } from '../src/m/chart/view'
import { ChartGesture } from '../src/m/chart/gesture'
import { decodeDrawing } from '../src/m/chart/draw/drawing'
import { ScaleReport } from '../src/m/chart/scaleReport'
import { orderFlowBands } from '../src/m/chart/renderer.orderflow'

type Listener = (e: unknown) => void
function fakeEl(): Record<string, unknown> {
  const listeners = new Map<string, Set<Listener>>()
  const el: Record<string, unknown> = {
    style: Object.assign(Object.create(null) as Record<string, unknown>, { setProperty() { /* 无 */ } }),
    dataset: {}, className: '', children: [] as unknown[], width: 0, height: 0,
    setAttribute() { /* 无 */ },
    appendChild(c: unknown) { (el.children as unknown[]).push(c); return c },
    remove() { /* 无 */ },
    addEventListener(type: string, fn: Listener) { if (!listeners.has(type)) listeners.set(type, new Set()); listeners.get(type)!.add(fn) },
    removeEventListener(type: string, fn: Listener) { listeners.get(type)?.delete(fn) },
    dispatch(type: string, e: unknown) { for (const fn of [...(listeners.get(type) ?? [])]) fn(e) },
    setPointerCapture() { /* 无 */ }, releasePointerCapture() { /* 无 */ },
    getBoundingClientRect: () => ({ left: 0, top: 0, width: 390, height: 700, right: 390, bottom: 700, x: 0, y: 0 }),
    getContext: () => null,
  }
  return el
}

beforeAll(() => {
  const g = globalThis as Record<string, unknown>
  if (!g.document) g.document = { createElement: () => fakeEl() }
  if (!g.window) g.window = { devicePixelRatio: 2 }
  if (!g.ResizeObserver) g.ResizeObserver = class { observe() { /* 无 */ } unobserve() { /* 无 */ } disconnect() { /* 无 */ } }
  if (!g.requestAnimationFrame) g.requestAnimationFrame = () => 1
  if (!g.cancelAnimationFrame) g.cancelAnimationFrame = () => { /* 无 */ }
})
afterEach(() => { vi.useRealTimers() })

function state(count = 400): ChartState {
  const o: number[] = [], h: number[] = [], l: number[] = [], c: number[] = [], v: number[] = []
  for (let k = 0; k < count; k++) {
    const p = 100 + 10 * Math.sin(k / 9)
    o.push(p); c.push(p + Math.cos(k / 5)); h.push(p + 2); l.push(p - 2); v.push(100 + k)
  }
  const series = new BarSeries({ symbol: 'BTCUSDT', interval: '1h', t0: 1_700_000_000_000, step: INTERVAL_STEP['1h'], open: o, high: h, low: l, close: c, volume: v })
  const span = series.step * 100
  return makeState({ series, symbol: { symbol: 'BTCUSDT', base: 'BTC', priceDecimals: 2 }, view: new ViewWindow(series.lastTime + span * 0.05, span), overlays: [], subs: ['MACD'] })
}

let nextPointer = 1
interface Finger { id: number; x: number; y: number }
const finger = (x: number, y: number): Finger => ({ id: nextPointer++, x, y })
const ev = (f: Finger, ms: number) => ({ pointerType: 'touch', button: 0, pointerId: f.id, clientX: f.x, clientY: f.y, timeStamp: ms, preventDefault() { /* 无 */ } })
const fire = (v: ChartView, type: string, f: Finger, ms: number) => (v.el as unknown as { dispatch(t: string, e: unknown): void }).dispatch(type, ev(f, ms))
const down = (v: ChartView, f: Finger, ms: number) => fire(v, 'pointerdown', f, ms)
const move = (v: ChartView, f: Finger, x: number, y: number, ms: number) => { f.x = x; f.y = y; fire(v, 'pointermove', f, ms) }
const up = (v: ChartView, f: Finger, ms: number) => fire(v, 'pointerup', f, ms)

function rig(): ChartView {
  const v = new ChartView(fakeEl() as unknown as HTMLElement)
  v.state = state()
  return v
}

describe('订单流点击互斥', () => {
  it('金额签优先于气泡放宽热区，点签选墙再点收起', () => {
    const v = rig(), s = v.state!, b = s.input.series
    v.state = withOverlay(s, { orderFlow: { symbol: b.symbol, phase: 'ready', asOfMs: b.lastTime, thresholds: {}, orders: [{
      venueID: 'binance:usdtPerp:X', exchange: '币安', product: 'usdtPerp', side: 'bid', bucket: 1,
      price: 100, firstSeenMs: b.time(b.count - 20), endMs: null, status: 'live',
      initialNotional: 10_000_000, notional: 10_000_000, filledNotional: 0, threshold: 1_000_000, vanishedNotional: null,
    }] } })
    const r = v.renderer!, L = r.layout(v.width, v.height)
    const label = orderFlowBands(r, L.main, r.priceRange(v.width, v.height), L).labels[0]
    expect(label).toBeDefined()
    const bubble = vi.fn(() => true)
    v.bigTradeTap = bubble
    const f = finger(label.frame.x + label.frame.w / 2, label.frame.y + label.frame.h / 2)
    down(v, f, 10_000); up(v, f, 10_010)
    expect(v.state!.overlay.orderFlowSelected).toEqual(label.key)
    expect(bubble).not.toHaveBeenCalled()
    down(v, f, 11_000); up(v, f, 11_010)
    expect(v.state!.overlay.orderFlowSelected).toBeNull()
  })
  it('大单定位清旧挂单卡；同位置恢复手动来源必须刷新，手动拖动恢复检查', () => {
    const v = rig(), i = v.state!.input.series.count - 30
    v.crosshairTo(i)
    const c = v.state!.overlay.crosshair!
    v.state = withOverlay(v.state!, { orderFlowSelected: { bucket: 1, side: 'bid', contract: true, start: 1 } })
    const changed = vi.fn()
    v.onCrosshairChanged = changed
    v.crosshairTo(i, 'bigTrade')
    expect(changed).toHaveBeenCalledTimes(1)
    expect(v.state!.overlay.crosshair?.source).toBe('bigTrade')
    expect(v.state!.overlay.orderFlowSelected).toBeNull()
    v.state = withOverlay(v.state!, { crosshair: c })
    expect(changed).toHaveBeenCalledTimes(2)
    v.crosshairTo(i, 'bigTrade')
    v.gestures.moveCrosshair({ x: 150, y: 160 }, v.chartLayout!)
    expect(v.state!.overlay.crosshair?.source ?? 'chart').toBe('chart')
  })
})

describe('十字线归哪根手指（ChartGestureTests · 审查 B·P3-2）', () => {
  it('拎着十字线时落下第二根手指、先抬起主人那根：十字线就此放下，不跳到第二根手指底下', () => {
    const v = rig()
    const s0 = v.state!
    v.state = withOverlay(s0, { crosshair: { index: s0.input.series.count - 40, pane: null, t: null, price: 100 } })
    const c = v.renderer!.crosshairCenter(v.width, v.height)!
    const owner = finger(c.x, c.y)
    down(v, owner, 1000)
    expect(v.gesture.mode).toBe('crosshair')
    move(v, owner, c.x + 20, c.y, 1016)
    const held = v.state!.overlay.crosshair!.index
    const other = finger(40, 120)
    down(v, other, 1030)
    up(v, owner, 1050)
    // 第二根手指挪动：十字线不跟它
    move(v, other, 60, 140, 1066)
    move(v, other, 80, 160, 1082)
    const after = v.state!.overlay.crosshair
    expect(after == null || after.index === held, `十字线跳到了第二根手指底下：${after?.index} ≠ ${held}`).toBe(true)
    expect(v.gesture.mode).not.toBe('crosshair')
    up(v, other, 1100)
    expect(v.gesture.touches.length).toBe(0)
  })

  it('长按出的十字线也一样：主人抬起、留下的手指不接班', () => {
    vi.useFakeTimers()
    const v = rig()
    const owner = finger(200, 200)
    down(v, owner, 1000)
    vi.advanceTimersByTime(ChartGesture.longPressMs + 10)
    expect(v.gesture.mode).toBe('crosshair')
    expect(v.gesture.owner).toBe(owner.id)
    const held = v.state!.overlay.crosshair!.index
    const other = finger(30, 100)
    down(v, other, 1600)
    up(v, owner, 1650)
    move(v, other, 50, 110, 1670)
    move(v, other, 70, 120, 1690)
    const after = v.state!.overlay.crosshair
    expect(after == null || after.index === held).toBe(true)
    up(v, other, 1700)
  })

  it('主人一直按着：第二根手指落下又抬起，十字线照旧跟主人走', () => {
    const v = rig()
    const s0 = v.state!
    v.state = withOverlay(s0, { crosshair: { index: s0.input.series.count - 40, pane: null, t: null, price: 100 } })
    const c = v.renderer!.crosshairCenter(v.width, v.height)!
    const owner = finger(c.x, c.y)
    down(v, owner, 1000)
    const other = finger(40, 120)
    down(v, other, 1010)
    move(v, other, 300, 300, 1020)
    move(v, owner, c.x - 60, c.y, 1030)
    expect(v.state!.overlay.crosshair!.index).toBeLessThan(s0.input.series.count - 40)
    up(v, other, 1040)
    expect(v.gesture.mode).toBe('crosshair')
    up(v, owner, 1060)
  })
})

// ------------------------------------------------------------------ 哪几层脏（ChartViewDirtyTests · 审查 B·P3-1 / 待核实 4）

type Dirty = { dirty: number }
const CROSS = 4  // Parts.cross
function tick(v: ChartView): number {
  const s = v.state!
  const b = s.input.series, i = b.count - 1
  ;(v as unknown as Dirty).dirty = 0
  b.replaceLast({ ...b.bar(i), close: b.close[i] * 1.001, high: Math.max(b.high[i], b.close[i] * 1.001) })
  v.state = s
  return (v as unknown as Dirty).dirty
}

describe('十字线读不读末根（ChartViewDirtyTests.lastBarTickRefreshesCrosshair）', () => {
  it('十字线停在末根 / 末根在屏里 / 开着「至今涨幅」：末根一跳十字线层跟着重画', () => {
    for (const when of ['onLast', 'visible', 'sinceChange'] as const) {
      const v = rig()
      let s = v.state!
      const n = s.input.series.count
      if (when === 'sinceChange') {
        s = { ...s, input: { ...s.input, options: { ...s.input.options, sinceChange: true } } }
        s = { ...s, viewport: { ...s.viewport, view: new ViewWindow(s.input.series.time(100), s.viewport.view.span) } }
      }
      const index = when === 'onLast' ? n - 1 : when === 'visible' ? n - 20 : 10
      v.state = withOverlay(s, { crosshair: { index, pane: null, t: null, price: 100 } })
      expect(tick(v) & CROSS, when).toBe(CROSS)
    }
  })

  it('往回翻到末根不在屏里、没开「至今涨幅」：末根一跳不必重画十字线层', () => {
    const v = rig()
    const s = v.state!
    v.state = withOverlay({ ...s, viewport: { ...s.viewport, view: new ViewWindow(s.input.series.time(100), s.viewport.view.span) } },
      { crosshair: { index: 10, pane: null, t: null, price: 100 } })
    expect(tick(v) & CROSS).toBe(0)
  })
})

describe('画线一变，开着订单流时十字线层跟着重画（金额签在那一层、要躲画线字）', () => {
  const hline = (s: ChartState) => decodeDrawing({ id: 'h', kind: 'hline', points: [{ t: s.input.series.lastTime, p: 100 }] })
  it('开订单流：画线一变 cross 脏；客线一换 cross 也脏', () => {
    const v = rig()
    const s0 = v.state!
    v.state = withOverlay(s0, { orderFlow: { symbol: 'BTCUSDT', phase: 'ready', orders: [], asOfMs: s0.input.series.lastTime, thresholds: {} } })
    ;(v as unknown as Dirty).dirty = 0
    v.state = withOverlay(v.state!, { drawings: [hline(s0)] })
    expect((v as unknown as Dirty).dirty & CROSS).toBe(CROSS)
    ;(v as unknown as Dirty).dirty = 0
    v.guestDrawings = [hline(s0)]
    expect((v as unknown as Dirty).dirty & CROSS).toBe(CROSS)
  })
  it('没开订单流：画线一变只脏底图', () => {
    const v = rig()
    ;(v as unknown as Dirty).dirty = 0
    v.state = withOverlay(v.state!, { drawings: [hline(v.state!)] })
    const d = (v as unknown as Dirty).dirty
    expect(d & 1).toBe(1)
    expect(d & CROSS).toBe(0)
  })
})

describe('捏合缩放的宽度只在抬手那一刻报给页面落盘（iOS ChartViewport.interactionEnded）', () => {
  // 页面一收到 'scale' 就 save()：整份偏好写 localStorage + 同步记脏 + syncChart 重算。
  // 原来 index.ts 在 onUserViewChanged 里每帧都 emit，一次捏合几十帧就整份落盘几十遍。
  const wire = (v: ChartView) => {
    const reports: number[] = []
    const r = new ScaleReport(() => v.gesture.touches.length > 0, w => reports.push(w))
    let frames = 0
    v.onUserViewChanged = nv => {
      const L = v.chartLayout!, s = v.state!
      frames++
      r.note(nv.barSpacing(s.input.series.step, L.plotW))
    }
    v.onInteractionEnded = () => r.lift()
    return { reports, frames: () => frames, r }
  }

  it('双指捏开二十帧：按着时一次不报，抬起最后一根手指报一次、报的就是最终宽度', () => {
    const v = rig()
    const w = wire(v)
    const a = finger(150, 200), b = finger(250, 200)
    down(v, a, 1000); down(v, b, 1001)
    expect(v.gesture.mode).toBe('pinch')
    for (let k = 1; k <= 20; k++) {
      move(v, a, 150 - k * 3, 200, 1000 + k * 16)
      move(v, b, 250 + k * 3, 200, 1000 + k * 16 + 1)
    }
    expect(w.frames()).toBeGreaterThan(10)
    expect(w.reports).toHaveLength(0)
    const s = v.state!
    const final = s.viewport.view.barSpacing(s.input.series.step, v.chartLayout!.plotW)
    up(v, a, 1400)
    expect(w.reports).toHaveLength(0) // 还剩一根手指按着
    up(v, b, 1410)
    expect(w.reports).toHaveLength(1)
    expect(w.reports[0]).toBeCloseTo(final, 9)
    expect(w.r.owed).toBe(false)
  })

  it('捏到一半被系统取消（来电、切后台）：照样把欠着的那一下报出去', () => {
    const v = rig()
    const w = wire(v)
    const a = finger(150, 200), b = finger(250, 200)
    down(v, a, 1000); down(v, b, 1001)
    for (let k = 1; k <= 6; k++) { move(v, a, 150 - k * 4, 200, 1000 + k * 16); move(v, b, 250 + k * 4, 200, 1000 + k * 16 + 1) }
    expect(w.reports).toHaveLength(0)
    const s = v.state!
    const final = s.viewport.view.barSpacing(s.input.series.step, v.chartLayout!.plotW)
    fire(v, 'pointercancel', a, 1200)
    fire(v, 'pointercancel', b, 1201)
    // 取消路径收尾时 settleView 在手指已清空后再报一帧同样的宽度；页面对没变的宽度不写盘
    expect(w.reports.length).toBeGreaterThanOrEqual(1)
    for (const x of w.reports) expect(x).toBeCloseTo(final, 9)
    expect(w.r.owed).toBe(false)
  })

  it('手指已经离开时来的帧（惯性、回弹）照常即时报', () => {
    const reports: number[] = []
    let down = true
    const r = new ScaleReport(() => down, x => reports.push(x))
    r.note(5); r.note(6)
    expect(reports).toEqual([])
    down = false
    r.lift()
    expect(reports).toEqual([6])
    r.note(6.5)
    expect(reports).toEqual([6, 6.5])
    r.lift()
    expect(reports).toEqual([6, 6.5])
  })
})

describe('捏合手感（移植 iOS a8012401：死区 3pt、按轴分开量、焦点钉住、竖捏价格轴）', () => {
  const spacingOf = (v: ChartView) => {
    const s = v.state!
    return s.viewport.view.barSpacing(s.input.series.step, v.chartLayout!.plotW)
  }
  /** 视野停在历史中段（不贴最新）。 */
  const midHistory = (v: ChartView) => {
    const s = v.state!, b = s.input.series
    v.state = withViewport(s, { view: new ViewWindow(b.lastTime - b.step * 150, b.step * 80) })
  }

  it('死区：横向张开量只变 2pt 不缩放；越过 3pt 那一帧只重设基准不缩放；下一帧按横向比例缩、没有跳', () => {
    const v = rig()
    midHistory(v)
    const w0 = spacingOf(v)
    const a = finger(150, 200), b = finger(250, 200)
    down(v, a, 1000); down(v, b, 1001)
    move(v, a, 149, 200, 1016); move(v, b, 251, 200, 1017)       // sx 100 → 102
    expect(v.gesture.pinchActive).toBe(false)
    expect(spacingOf(v)).toBeCloseTo(w0, 9)
    move(v, a, 148, 200, 1032); move(v, b, 252, 200, 1033)       // sx 104：越过 3pt
    expect(v.gesture.pinchActive).toBe(true)
    expect(v.gesture.pinchAxis).toBe('time')
    expect(spacingOf(v)).toBeCloseTo(w0, 9)                         // 越门槛那一帧不缩
    move(v, a, 138, 200, 1048)                                      // sx 104 → 114（只动一根）
    expect(spacingOf(v)).toBeCloseTo(w0 * 114 / 104, 6)
    up(v, a, 1100); up(v, b, 1101)
  })

  it('死区里两指一起挪是平移，不改根宽', () => {
    const v = rig()
    midHistory(v)
    const w0 = spacingOf(v), to0 = v.state!.viewport.view.to
    const a = finger(150, 200), b = finger(250, 200)
    down(v, a, 1000); down(v, b, 1001)
    move(v, a, 170, 200, 1016); move(v, b, 270, 200, 1017)
    expect(v.gesture.pinchActive).toBe(false)
    expect(spacingOf(v)).toBeCloseTo(w0, 9)
    expect(v.state!.viewport.view.to).toBeLessThan(to0)              // 手指往右 = 看更早
  })

  it('不贴最新：绕两指中点缩放，中点底下那一刻的时间不动', () => {
    const v = rig()
    midHistory(v)
    const a = finger(150, 200), b = finger(250, 200)
    down(v, a, 1000); down(v, b, 1001)
    move(v, a, 146, 200, 1016); move(v, b, 254, 200, 1017)       // 越门槛
    const L = v.chartLayout!
    const tAtMid = v.state!.viewport.view.t(200, L.plotW)
    for (let k = 1; k <= 5; k++) { move(v, a, 146 - k * 6, 200, 1016 + k * 16); move(v, b, 254 + k * 6, 200, 1017 + k * 16) }
    const view = v.state!.viewport.view
    expect(Math.abs(view.x(tAtMid, L.plotW) - 200)).toBeLessThan(0.01)
    expect(spacingOf(v)).toBeGreaterThan(0)
  })

  it('贴着最新：末根钉住，捏开捏合之后仍贴着最新', () => {
    const v = rig()
    const s = v.state!, b = s.input.series, L = v.chartLayout!
    v.state = withViewport(s, { view: ViewMath.reset(b, L.plotW, 8) })
    expect(ViewMath.isPinnedToLatest(v.state!.viewport.view, b, L.plotW)).toBe(true)
    const w0 = spacingOf(v)
    const f1 = finger(100, 200), f2 = finger(200, 200)
    down(v, f1, 1000); down(v, f2, 1001)
    move(v, f1, 96, 200, 1016); move(v, f2, 204, 200, 1017)
    // 一边捏一边手指往左偏：中点漂移不算数
    for (let k = 1; k <= 5; k++) { move(v, f1, 96 - k * 10, 200, 1016 + k * 16); move(v, f2, 204 + k * 2, 200, 1017 + k * 16) }
    const view = v.state!.viewport.view
    expect(spacingOf(v)).toBeGreaterThan(w0)
    expect(ViewMath.isPinnedToLatest(view, b, L.plotW)).toBe(true)
    expect(view.to).toBeCloseTo(ViewMath.reset(b, L.plotW, spacingOf(v)).to, 3)
  })

  it('竖着捏（两指在主图里）只缩价格轴：时间窗不动，中点底下的价位还在中点高度', () => {
    const v = rig()
    midHistory(v)
    const view0 = v.state!.viewport.view
    const a = finger(200, 150), b = finger(204, 250)
    down(v, a, 1000); down(v, b, 1001)
    move(v, a, 200, 140, 1016); move(v, b, 204, 260, 1017)        // sy 100 → 120：越门槛、定价格轴
    expect(v.gesture.pinchAxis).toBe('price')
    const L = v.chartLayout!
    const anchor = v.gesture.pinchPrice
    move(v, a, 200, 120, 1032); move(v, b, 204, 280, 1033)
    const s = v.state!
    expect(s.viewport.price.zoom).toBeGreaterThan(1)
    expect(s.viewport.view.equals(view0)).toBe(true)
    const r = v.chartPriceRange!
    expect(Math.abs(pOf(200, L.main, r, effectivePriceMode(s)) - anchor) / anchor).toBeLessThan(1e-6)
  })
})

describe('捏合软边（移植 iOS aedc26df：越过 1.6 / 40 带对数阻尼、松手绕捏的那一点弹回、减少动效直接到位）', () => {
  const lo = 1.6, hi = 40
  const spacingOf = (v: ChartView) => {
    const s = v.state!
    return s.viewport.view.barSpacing(s.input.series.step, v.chartLayout!.plotW)
  }
  /** 视野停在历史中段、根宽 `w`。 */
  const at = (v: ChartView, w: number) => {
    const s = v.state!, b = s.input.series, L = v.chartLayout!
    const span = L.plotW / w * b.step
    v.state = withViewport(s, { view: new ViewWindow(b.lastTime - b.step * 120, span) })
  }
  /** 帧循环在 node 里不跑：手动把动画推进到 `ms` 毫秒之后（演完就照 view.ts 摘掉）。 */
  const runAnim = (v: ChartView, ms: number) => {
    const a = v.animation
    if (!a) return
    if (a(performance.now() + ms) && v.animation === a) v.animation = null
  }
  /** 两指从 (cx ± 50) 横着张到 (cx ± half)，先越死区再分 8 帧走完。 */
  const spread = (v: ChartView, a: Finger, b: Finger, cx: number, half: number, t0: number) => {
    move(v, a, cx - 54, 200, t0); move(v, b, cx + 54, 200, t0 + 1)
    for (let k = 1; k <= 8; k++) {
      const h = 54 + (half - 54) * k / 8
      move(v, a, cx - h, 200, t0 + k * 16); move(v, b, cx + h, 200, t0 + k * 16 + 1)
    }
  }
  const mq = (matches: boolean) => ({ matches, addEventListener() { /* 无 */ }, removeEventListener() { /* 无 */ } })
  const noReduce = () => vi.stubGlobal('matchMedia', () => mq(false))
  afterEach(() => { vi.unstubAllGlobals() })

  it('softSpacing：界内原样、越界那一点斜率 1、渐近 ×1.15 / ×0.85 够不着；rawSpacingForSoft 是它的反函数；攒的上限三倍', () => {
    expect(ViewMath.softSpacing(20)).toBe(20)
    expect(ViewMath.softSpacing(hi)).toBe(hi)
    expect((ViewMath.softSpacing(hi * 1.0001) - hi) / (hi * 0.0001)).toBeCloseTo(1, 2)
    expect((lo - ViewMath.softSpacing(lo * 0.9999)) / (lo * 0.0001)).toBeCloseTo(1, 2)
    let prev = hi
    for (const r of [45, 60, 100, 1e3, 1e6]) {
      const x = ViewMath.softSpacing(r)
      expect(x).toBeGreaterThan(prev); expect(x).toBeLessThan(hi * 1.15); prev = x
    }
    expect(ViewMath.softSpacing(0.5)).toBeGreaterThan(lo * 0.85)
    expect(ViewMath.softSpacing(0.5)).toBeLessThan(lo)
    for (const r of [1.0, 1.2, 1.6, 5, 40, 44, 52]) expect(ViewMath.rawSpacingForSoft(ViewMath.softSpacing(r))).toBeCloseTo(r, 6)
    expect(ViewMath.boundedRawSpacing(1e9)).toBeCloseTo(hi * 1.15 ** 3, 9)
    expect(ViewMath.boundedRawSpacing(0)).toBeCloseTo(lo * 0.85 ** 3, 9)
  })

  it('捏开越过 40：画出来的根宽在 40 外面但不到 46；松手绕捏的那一点弹回 40，那一刻的时间站在原地', () => {
    noReduce()
    const v = rig()
    at(v, 20)
    const a = finger(150, 200), b = finger(250, 200)
    down(v, a, 1000); down(v, b, 1001)
    spread(v, a, b, 200, 160, 1016)
    const w = spacingOf(v)
    expect(w).toBeGreaterThan(hi)
    expect(w).toBeLessThan(hi * 1.15)
    const L = v.chartLayout!
    const tAtMid = v.state!.viewport.view.t(200, L.plotW)
    up(v, a, 1300); up(v, b, 1301)
    expect(v.animation).not.toBeNull()                    // 弹回是动画，不是一下吸到边界
    runAnim(v, 120)
    const mid = spacingOf(v)
    expect(mid).toBeGreaterThan(hi); expect(mid).toBeLessThan(w)
    runAnim(v, 400)
    expect(v.animation).toBeNull()
    expect(spacingOf(v)).toBeCloseTo(hi, 6)
    expect(Math.abs(v.state!.viewport.view.x(tAtMid, L.plotW) - 200)).toBeLessThan(0.5)
  })

  it('捏合越过 1.6 同样带阻尼并弹回 1.6', () => {
    noReduce()
    const v = rig()
    at(v, 2.4)
    const a = finger(100, 200), b = finger(300, 200)
    down(v, a, 1000); down(v, b, 1001)
    move(v, a, 104, 200, 1016); move(v, b, 296, 200, 1017)
    for (let k = 1; k <= 8; k++) { move(v, a, 104 + k * 11, 200, 1016 + k * 16); move(v, b, 296 - k * 11, 200, 1017 + k * 16) }
    const w = spacingOf(v)
    expect(w).toBeLessThan(lo); expect(w).toBeGreaterThan(lo * 0.85)
    up(v, a, 1300); up(v, b, 1301)
    runAnim(v, 400)
    expect(spacingOf(v)).toBeCloseTo(lo, 6)
  })

  it('越界时抬掉一根：剩下那根在回弹途中不抢画面，弹完接着拖、不跳', () => {
    noReduce()
    const v = rig()
    at(v, 20)
    const a = finger(150, 200), b = finger(250, 200)
    down(v, a, 1000); down(v, b, 1001)
    spread(v, a, b, 200, 160, 1016)
    expect(spacingOf(v)).toBeGreaterThan(hi)
    up(v, a, 1300)
    expect(v.gesture.mode).toBe('pan')
    expect(v.gesture.reboundHandoff).toBe(true)
    expect(v.animation).not.toBeNull()
    runAnim(v, 100)
    const during = v.state!.viewport.view
    move(v, b, 300, 200, 1320)                            // 回弹途中手指挪了：画面不跟
    expect(v.state!.viewport.view.equals(during)).toBe(true)
    runAnim(v, 400)
    expect(spacingOf(v)).toBeCloseTo(hi, 6)
    const settled = v.state!.viewport.view
    move(v, b, 300, 200, 1400)                            // 弹完第一帧：只交接起手点
    expect(v.gesture.reboundHandoff).toBe(false)
    expect(v.state!.viewport.view.equals(settled)).toBe(true)
    move(v, b, 280, 200, 1416)                            // 往左拖 20pt = 看更新的
    const L = v.chartLayout!
    const after = v.state!.viewport.view
    expect(spacingOf(v)).toBeCloseTo(hi, 6)
    expect((after.to - settled.to) / settled.span * L.plotW).toBeCloseTo(20, 3)
    up(v, b, 1500)
  })

  it('越界抬掉一根、回弹途中剩下那根也抬了：回弹照走完，不判轻点、不起惯性', () => {
    noReduce()
    const v = rig()
    at(v, 20)
    let taps = 0
    v.onTapped = () => { taps++ }
    const a = finger(150, 200), b = finger(250, 200)
    down(v, a, 1000); down(v, b, 1001)
    spread(v, a, b, 200, 160, 1016)
    up(v, a, 1300)
    const anim = v.animation
    up(v, b, 1310)
    expect(taps).toBe(0)
    expect(v.animation).toBe(anim)                        // 还是那段回弹，没被惯性换掉
    runAnim(v, 400)
    expect(spacingOf(v)).toBeCloseTo(hi, 6)
  })

  it('prefers-reduced-motion：不越界、硬停在 40，松手没有动画', () => {
    vi.stubGlobal('matchMedia', (q: string) => mq(q.includes('reduce')))
    const v = rig()
    at(v, 20)
    const a = finger(150, 200), b = finger(250, 200)
    down(v, a, 1000); down(v, b, 1001)
    spread(v, a, b, 200, 160, 1016)
    expect(spacingOf(v)).toBeCloseTo(hi, 9)
    up(v, a, 1300); up(v, b, 1301)
    expect(v.animation).toBeNull()
    expect(spacingOf(v)).toBeCloseTo(hi, 9)
  })
})
