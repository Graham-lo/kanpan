// ChartView 触摸状态机（Pointer Events 驱动），移植自 KanpanChart/Tests/KanpanChartTests/ChartGestureTests.swift
// 里与审查 B 线修复相关的几条。场地：node 里假的 DOM 元素、帧循环不跑，只看状态与模型。
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { ViewWindow } from '../src/m/chart/geometry'
import { BarSeries, INTERVAL_STEP } from '../src/m/chart/series'
import { makeState, withOverlay } from '../src/m/chart/state'
import type { ChartState } from '../src/m/chart/state'
import { ChartView } from '../src/m/chart/view'
import { ChartGesture } from '../src/m/chart/gesture'

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
