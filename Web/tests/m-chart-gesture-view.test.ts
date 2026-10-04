// ChartView 触摸状态机（Pointer Events 驱动），移植自 KanpanChart/Tests/KanpanChartTests/ChartGestureTests.swift
// 里与审查 B 线修复相关的几条。场地：node 里假的 DOM 元素、帧循环不跑，只看状态与模型。
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { ViewWindow } from '../src/m/chart/geometry'
import { BarSeries, INTERVAL_STEP } from '../src/m/chart/series'
import { makeState, withOverlay } from '../src/m/chart/state'
import type { ChartState } from '../src/m/chart/state'
import { ChartView } from '../src/m/chart/view'
import { ChartGesture } from '../src/m/chart/gesture'
import { decodeDrawing } from '../src/m/chart/draw/drawing'
import { ScaleReport } from '../src/m/chart/scaleReport'

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
