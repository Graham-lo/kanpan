// 手机网页 · 图上大单与爆仓气泡：纯函数（与 iOS KanpanChart/Tests/KanpanChartTests/BigTradeSignsTests.swift 同一份规格，
// docs/design/大单爆仓气泡-三端规格-2026-10-08.md；摆放与电脑网页同一个 planBubbles，细的几何在 orderflow-bigtags.test.ts）
// + 图层（ChartView.addLayer 上真排一屏：命中只认泡、读屏只列泡、画线文字零相交）+ 数据源（爆仓按根并进 U / D）。
// 场地：node 里假的 DOM 元素与假画布（只记调用），帧循环不跑。
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { SIGN, planSigns, hitSign, hitBox, signLabel, type SignBar, type SignEnv } from '../src/m/chart/bigTradeSigns'
import { BigTradeLayer, bigTradeSource, type BigTradeSource } from '../src/m/chart/bigTradeLayer'
import { BUBBLE, type Levels, type Rect } from '../src/orderflow/bigTags'
import type { LiqRow } from '../src/orderflow/liquidation'
import { ViewWindow } from '../src/m/chart/geometry'
import { BarSeries, INTERVAL_STEP } from '../src/m/chart/series'
import { makeState, withOverlay } from '../src/m/chart/state'
import type { ChartState } from '../src/m/chart/state'
import { ChartView } from '../src/m/chart/view'
import { decodeDrawing } from '../src/m/chart/draw/drawing'
import { drawingLabelBoxes, orderFlowAmount } from '../src/m/chart/renderer.orderflow'

const K: Levels = { dot: 100_000, bubble: 300_000 }

function env(o: Partial<SignEnv> = {}): SignEnv {
  return {
    levels: K, spacing: 8, top: 24, bottom: 400, plotW: 800, avoid: [],
    measure: t => t.length * 6, fmt: v => `${Math.round(v / 1000)}K`, ...o,
  }
}
function bar(o: { i?: number; x?: number; hi?: number; lo?: number; up: number; down: number }): SignBar {
  const i = o.i ?? 0
  return { i, t: i * 60_000, x: o.x ?? 100, yHigh: o.hi ?? 100, yLow: o.lo ?? 200, up: o.up, down: o.down }
}
const circleHits = (x: number, y: number, r: number, a: Rect): boolean => {
  const cx = Math.max(a.x, Math.min(x, a.x + a.w)), cy = Math.max(a.y, Math.min(y, a.y + a.h))
  return Math.hypot(x - cx, y - cy) < r
}

describe('气泡 · 一根上下各至多一枚', () => {
  it('U 过泡线 = 最高价之上的带字泡（涨色侧），D 过点线 = 最低价之下的小圆点', () => {
    const [u, d, ...rest] = planSigns([bar({ up: 500_000, down: 150_000 })], env())
    expect(rest).toEqual([])
    expect(u).toMatchObject({ side: 'up', bubble: true, text: '500K', anchor: 100 })
    expect(u.cy + u.r).toBe(96)
    expect(d).toMatchObject({ side: 'down', bubble: false, text: '', anchor: 200 })
    expect(d.cy - d.r).toBeCloseTo(202)
  })
  it('没过点线不画；没有金额线不画', () => {
    expect(planSigns([bar({ up: 99_000, down: 90_000 })], env())).toEqual([])
    expect(planSigns([bar({ up: 5e6, down: 0 })], env({ levels: null }))).toEqual([])
  })
  it('一根宽不到 4：全部只画点', () => {
    const out = planSigns([bar({ up: 2e6, down: 2e6 })], env({ spacing: 3 }))
    expect(out).toHaveLength(2); expect(out.every(s => !s.bubble)).toBe(true)
  })
  it('一屏带字的泡最多 6 枚，大的先占位，其余退成点；输出按根序', () => {
    const bars = Array.from({ length: 9 }, (_, i) => bar({ i, x: 40 + i * 80, up: 1e6 + i * 1000, down: 0 }))
    const out = planSigns(bars, env())
    expect(out.map(s => s.i)).toEqual([0, 1, 2, 3, 4, 5, 6, 7, 8])
    expect(out.filter(s => s.bubble).map(s => s.i)).toEqual([3, 4, 5, 6, 7, 8])
  })
  it('同侧挨上了往外推一层（大的先占位）；推出图例带（顶上 24 + 4）就退成点', () => {
    const out = planSigns([bar({ i: 0, x: 100, hi: 200, up: 1e6, down: 0 }), bar({ i: 1, x: 106, hi: 200, up: 2e6, down: 0 })], env())
    const [a, b] = out
    expect(a.bubble && b.bubble).toBe(true)
    expect(b.cy + b.r).toBe(196)
    expect(Math.hypot(a.x - b.x, a.cy - b.cy)).toBeGreaterThanOrEqual(a.r + b.r + 2 - 1e-9)
    const [c] = planSigns([bar({ i: 0, x: 100, up: 1e6, down: 0 }), bar({ i: 1, x: 106, up: 2e6, down: 0 })], env())
    expect(c.bubble).toBe(false)
    const [t] = planSigns([bar({ hi: 50, up: 2e6, down: 0 })], env())
    expect(t.bubble).toBe(false); expect(t.cy - t.r).toBeGreaterThanOrEqual(24)
  })
  it('和画线文字零相交、不进图例带、不出主图、每屏至多 6 枚泡（随机 200 屏）', () => {
    let seed = 42
    const rnd = (lo: number, hi: number) => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return lo + (hi - lo) * (seed / 0x7fffffff) }
    let total = 0
    for (let k = 0; k < 200; k++) {
      const avoid: Rect[] = Array.from({ length: 4 }, () => ({ x: rnd(0, 700), y: rnd(24, 380), w: rnd(20, 120), h: rnd(12, 20) }))
      const bars = Array.from({ length: 80 }, (_, i) => { const hi = rnd(30, 300); return bar({ i, x: 4 + i * 9.5, hi, lo: hi + rnd(2, 80), up: rnd(0, 3e6), down: rnd(0, 3e6) }) })
      const signs = planSigns(bars, env({ spacing: 9.5, avoid }))
      total += signs.length
      expect(signs.filter(s => s.bubble).length).toBeLessThanOrEqual(6)
      for (const s of signs) {
        for (const a of avoid) expect(circleHits(s.x, s.cy, s.r, a)).toBe(false)
        expect(s.cy - s.r).toBeGreaterThanOrEqual(24 - 1e-9); expect(s.cy + s.r).toBeLessThanOrEqual(400 + 1e-9)
      }
    }
    expect(total).toBeGreaterThan(1000)
  })
})

describe('气泡 · 命中与读屏', () => {
  it('44 × 44 命中、几枚都中取圆心最近的；小圆点不响应', () => {
    const signs = planSigns([bar({ i: 0, x: 100, up: 5e5, down: 0 }), bar({ i: 1, x: 140, up: 6e5, down: 0 })], env())
    const [a, b] = signs
    expect(a.bubble && b.bubble).toBe(true)
    expect(hitSign(signs, a.x - 20, a.cy + 20)?.i).toBe(0)
    expect(hitSign(signs, 121, a.cy)?.i).toBe(1)
    expect(hitSign(signs, 119, a.cy)?.i).toBe(0)
    expect(hitSign(signs, a.x, a.cy - 30)).toBeNull()
    expect(hitSign(signs, 300, 300)).toBeNull()
    const [dot] = planSigns([bar({ up: 150_000, down: 0 })], env())
    expect(dot.bubble).toBe(false)
    expect(hitSign([dot], dot.x, dot.cy)).toBeNull()
  })
  it('命中框以圆心为心，泡大于 44 时按泡', () => {
    expect(hitBox({ x: 100, cy: 50, r: 12 })).toEqual({ x: 78, y: 28, w: 44, h: 44 })
    expect(hitBox({ x: 100, cy: 50, r: 30 })).toEqual({ x: 70, y: 20, w: 60, h: 60 })
  })
  it('读屏文案「12:30 向上 1.2M」/「10月8日 向下 300.0K」', () => {
    const [s] = planSigns([bar({ up: 1.2e6, down: 0 })], env())
    expect(signLabel(s, orderFlowAmount, '12:30')).toBe('12:30 向上 1.2M')
    expect(signLabel({ side: 'down', usd: 3e5 }, orderFlowAmount, '10月8日')).toBe(`10月8日 向下 ${orderFlowAmount(3e5)}`)
  })
  it('尺寸与 iOS 同值', () => {
    expect(SIGN).toMatchObject({ legendBand: 24, hit: 44, pop: 1.3, popMs: 120, ring: 8, ringMs: 600, flashMs: 150 })
    expect(BUBBLE).toMatchObject({ cap: 6, minBw: 4, font: 11, r0: 11, rGrow: 6, stem: 4, dotStem: 2, fill: 0.16, fillDark: 0.22, stroke: 1.4, dotAlpha: 0.85 })
  })
})

// ------------------------------------------------------------------ 图层：ChartView 上真排一屏

type Listener = (e: unknown) => void
function fakeEl(): Record<string, unknown> {
  const listeners = new Map<string, Set<Listener>>()
  const el: Record<string, unknown> = {
    style: Object.assign(Object.create(null) as Record<string, unknown>, { setProperty() { /* 无 */ } }),
    dataset: {}, className: '', children: [] as unknown[], width: 0, height: 0,
    setAttribute(k: string, v: string) { (el as Record<string, unknown>)[`attr:${k}`] = v },
    getAttribute(k: string) { return (el as Record<string, unknown>)[`attr:${k}`] ?? null },
    appendChild(c: unknown) { (el.children as unknown[]).push(c); return c },
    insertBefore(c: unknown) { (el.children as unknown[]).push(c); return c },
    replaceChildren(...cs: unknown[]) { el.children = cs },
    remove() { /* 无 */ },
    addEventListener(type: string, fn: Listener) { if (!listeners.has(type)) listeners.set(type, new Set()); listeners.get(type)!.add(fn) },
    removeEventListener(type: string, fn: Listener) { listeners.get(type)?.delete(fn) },
    dispatch(type: string, e: unknown) { for (const fn of [...(listeners.get(type) ?? [])]) fn(e) },
    click() { (el as { dispatch(t: string, e: unknown): void }).dispatch('click', {}) },
    setPointerCapture() { /* 无 */ }, releasePointerCapture() { /* 无 */ },
    getBoundingClientRect: () => ({ left: 0, top: 0, width: 393, height: 560, right: 393, bottom: 560, x: 0, y: 0 }),
    getContext: () => null,
  }
  return el
}
/** 什么都接、什么都不画的 2d 上下文 */
function nullCtx(): CanvasRenderingContext2D {
  const box: Record<string | symbol, unknown> = { globalAlpha: 1 }
  return new Proxy(box, {
    get: (o, k) => (k in o ? o[k] : k === 'measureText' ? (t: string) => ({ width: t.length * 6 }) : () => undefined),
    set: (o, k, v) => { o[k] = v; return true },
  }) as unknown as CanvasRenderingContext2D
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

function state(count = 300): ChartState {
  const o: number[] = [], h: number[] = [], l: number[] = [], c: number[] = [], v: number[] = []
  for (let k = 0; k < count; k++) {
    const p = 100 + 10 * Math.sin(k / 9)
    o.push(p); c.push(p + Math.cos(k / 5)); h.push(p + 2); l.push(p - 2); v.push(100 + k)
  }
  const series = new BarSeries({ symbol: 'BTCUSDT', interval: '15m', t0: 1_700_000_000_000, step: INTERVAL_STEP['15m'], open: o, high: h, low: l, close: c, volume: v })
  const span = series.step * 60
  return makeState({ series, symbol: { symbol: 'BTCUSDT', base: 'BTC', priceDecimals: 2 }, view: new ViewWindow(series.lastTime + span * 0.05, span), overlays: [], subs: [] })
}

/** 每 3 根一枚，金额从 0.2M 往上走，后面的根过泡线 */
function source(): BigTradeSource {
  return {
    prepare: series => ({
      levels: K, live: 0,
      bar: i => {
        if (i % 3) return null
        const v = 2e5 + (i / series.count) * 3e6
        return i % 2 ? { up: 0, down: v, bb: 0, bs: v } : { up: v, down: 0, bb: v, bs: 0 }
      },
    }),
  }
}

function rig(onTap: (s: { i: number }) => boolean = () => true) {
  const v = new ChartView(fakeEl() as unknown as HTMLElement)
  v.state = state()
  const layer = new BigTradeLayer(v, { source: source(), onTap })
  ;(layer as unknown as { handle: { canvas: { getContext: () => unknown } } }).handle.canvas.getContext = () => nullCtx()
  v.redrawNow()
  return { v, layer }
}

describe('气泡 · 图层', () => {
  it('一屏排出：只在主图里、不进图例带、一根同侧至多一枚、带字的泡至多 6 枚', () => {
    const { v, layer } = rig()
    const L = v.renderer!.layout(v.width, v.height)
    const signs = layer.current
    expect(signs.length).toBeGreaterThan(5)
    expect(new Set(signs.map(s => `${s.i}${s.side}`)).size).toBe(signs.length)
    for (const s of signs) {
      expect(s.cy - s.r).toBeGreaterThanOrEqual(L.main.y + SIGN.legendBand - 0.001)
      expect(s.cy + s.r).toBeLessThanOrEqual(L.main.y + L.main.h + 0.001)
      expect(s.x).toBeGreaterThanOrEqual(-0.001); expect(s.x).toBeLessThanOrEqual(L.plotW + 0.001)
    }
    const nb = signs.filter(s => s.bubble).length
    expect(nb).toBeGreaterThan(0); expect(nb).toBeLessThanOrEqual(6)
    expect(signs.some(s => !s.bubble)).toBe(true)
  })

  it('轻点落在泡上：交给宿主（返回真 = 手势不再当轻点）；宿主不接（横屏）就照常；点在小圆点上不算', () => {
    const taps: number[] = []
    let accept = true
    const { v, layer } = rig(s => { taps.push(s.i); return accept })
    const s = layer.current.filter(x => x.bubble).pop()!
    expect(v.bigTradeTap!(s.x, s.cy)).toBe(true)
    expect(taps).toEqual([s.i])
    const dot = layer.current.find(x => !x.bubble && layer.current.filter(y => y.bubble).every(y => Math.abs(y.x - x.x) > 30 || Math.abs(y.cy - x.cy) > 30))
    if (dot) expect(v.bigTradeTap!(dot.x, dot.cy)).toBe(false)
    accept = false
    expect(v.bigTradeTap!(s.x, s.cy)).toBe(false)
    expect(v.bigTradeTap!(-500, -500)).toBe(false)
    layer.setEnabled(false)
    v.redrawNow()
    expect(layer.current).toEqual([])
    expect(v.bigTradeTap!(s.x, s.cy)).toBe(false)
    layer.destroy()
    expect(v.bigTradeTap).toBeNull()
  })

  it('读屏：只给泡一个隐形按钮（小圆点不进），文案「时间 向上 / 向下 金额」，点它等于点泡', () => {
    vi.useFakeTimers()
    const taps: number[] = []
    const { layer } = rig(s => { taps.push(s.i); return true })
    vi.advanceTimersByTime(400)
    const aria = (layer as unknown as { aria: { children: Record<string, unknown>[] } }).aria
    const bubbles = layer.current.filter(s => s.bubble).sort((a, b) => a.t - b.t)
    expect(aria.children.length).toBe(bubbles.length)
    expect(aria.children.length).toBeLessThan(layer.current.length)
    const b = aria.children[0] as { getAttribute(k: string): string; click(): void; className: string }
    expect(b.className).toBe('m-bigtrade-aria-sign')
    expect(b.getAttribute('aria-label')).toMatch(/^\d\d:\d\d 向(上|下) [\d.]+[KMB]?$/)
    b.click()
    expect(taps).toEqual([bubbles[0].i])
  })

  it('和画线文字零相交（真画线：几条水平线压在 K 线高点附近）', () => {
    const { v, layer } = rig()
    const before = layer.current.length
    const s0 = v.state!
    const ps = [111, 108, 104, 100, 96, 92, 89]
    const lines = ps.map((p, k) => decodeDrawing({ id: `h${k}`, kind: 'hline', points: [{ t: s0.input.series.lastTime, p }] }))
    v.state = withOverlay(s0, { drawings: lines })
    v.redrawNow()
    const r = v.renderer!, L = r.layout(v.width, v.height)
    const boxes = drawingLabelBoxes(r, L.main, r.priceRange(v.width, v.height), L)
    expect(boxes.length).toBe(ps.length)
    let n = 0
    for (const s of layer.current) for (const b of boxes) { n++; expect(circleHits(s.x, s.cy, s.r, b)).toBe(false) }
    expect(n).toBeGreaterThan(0)
    expect(before).toBeGreaterThan(0)
  })
})

describe('气泡 · 数据源并爆仓', () => {
  function series(): BarSeries {
    const n = 10, o = Array(n).fill(100), h = Array(n).fill(101), l = Array(n).fill(99)
    return new BarSeries({ symbol: 'LIQTUSDT', interval: '5m', t0: 1_760_000_100_000, step: 300_000, open: o, high: h, low: l, close: o, volume: Array(n).fill(1) })
  }
  it('空爆并进向上、多爆并进向下；只有爆仓的根也有数，金额线从合并后的数定', () => {
    const s = series(), T = s.time(0)
    const rows = new Map<number, LiqRow>()
    for (let k = 0; k < 10; k++) rows.set(T + k * 300_000 + 60_000, [T + k * 300_000 + 60_000, k === 9 ? 5e6 : 0, 100_000, 1, 0, 0, 0, 0])
    const seen: string[] = []
    const src = bigTradeSource(() => 0, sym => { seen.push(sym); return { state: { rows, tracked: true, ver: 1 }, base: 'LIQT' } })
    const d = src.prepare(s, T + 10 * 300_000)!
    expect(seen[0]).toBe('LIQTUSDT')
    expect(d.bar(0)).toEqual({ up: 100_000, down: 0, bb: 0, bs: 0 })
    expect(d.bar(9)).toEqual({ up: 100_000, down: 5e6, bb: 0, bs: 0 })
    expect(d.levels).not.toBeNull()
    expect(d.levels!.bubble).toBeGreaterThan(100_000)
  })
  it('不给爆仓（现货 / 宏观 / 没开）：只看大单，没有大单就没有金额线', () => {
    const s = series()
    const d = bigTradeSource(() => 0, () => null).prepare(s, s.time(9) + 300_000)!
    expect(d.bar(0)).toBeNull(); expect(d.levels).toBeNull()
    expect(bigTradeSource(() => 0).prepare(s, s.time(9) + 300_000)!.levels).toBeNull()
  })
})

// ------------------------------------------------------------------ 压测：1m × 500 根，真数据源

describe('气泡 · 压测', () => {
  it('1m × 500 根满屏：气泡这层每帧 p95 ≤ 1 ms（这一层是加在原帧上的全部开销）', async () => {
    const { recordTrade, beat, resetFlows } = await import('../src/chart/tradeFlow')
    const { withViewport } = await import('../src/m/chart/state')
    resetFlows()
    const N = 500, step = 60_000, t0 = Math.floor(Date.now() / step) * step - (N - 1) * step
    const now = t0 + (N - 1) * step + 30_000
    const o: number[] = [], h: number[] = [], l: number[] = [], c: number[] = [], v: number[] = []
    let seed = 9
    const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff }
    for (let k = 0; k < N; k++) {
      const p = 100 + 8 * Math.sin(k / 23) + rnd()
      o.push(p); c.push(p + rnd() - 0.5); h.push(p + 1 + rnd()); l.push(p - 1 - rnd()); v.push(100)
    }
    const venue = { exchange: 'binance', product: 'usdtPerp', instrument: 'PERFUSDT' }
    for (let tt = t0; tt <= now; tt += 5_000) {
      beat('PERFUSDT', tt, true)
      const usd = rnd() < 0.3 ? 5_000 + rnd() * 400_000 : 2_000
      recordTrade('PERFUSDT', { usd, trade: { timeMs: tt, hitSide: rnd() < 0.5 ? 'ask' : 'bid', price: 100 }, book: { venue } } as never, 1_000)
    }
    const series = new BarSeries({ symbol: 'PERFUSDT', interval: '1m', t0, step, open: o, high: h, low: l, close: c, volume: v })
    const view = new ChartView(fakeEl() as unknown as HTMLElement)
    const span = step * N
    view.state = makeState({ series, symbol: { symbol: 'PERFUSDT', base: 'PERF', priceDecimals: 2 }, view: new ViewWindow(series.lastTime + step, span), overlays: [], subs: [] })
    const layer = new BigTradeLayer(view, { source: bigTradeSource(() => 10_000), onTap: () => true, now: () => now })
    ;(layer as unknown as { handle: { canvas: { getContext: () => unknown } } }).handle.canvas.getContext = () => nullCtx()
    view.redrawNow()
    expect(layer.current.length).toBeGreaterThan(20)
    const times: number[] = []
    for (let k = 0; k < 400; k++) {
      // 每帧挪一点视野（拖图），图层随几何重排
      const s = view.state!
      view.state = withViewport(s, { view: new ViewWindow(series.lastTime + step - (k % 50) * step, span * (k % 2 ? 1 : 0.6)) })
      const a = performance.now()
      layer.invalidate(); view.redrawNow()
      times.push(performance.now() - a)
    }
    times.sort((x, y) => x - y)
    const p95 = times[Math.floor(times.length * 0.95)]
    expect(p95, `p95 ${p95.toFixed(3)} ms`).toBeLessThanOrEqual(1)
    console.log(`[气泡压测] 1m × 500：每帧 p50 ${times[200].toFixed(3)} ms，p95 ${p95.toFixed(3)} ms，气泡与点 ${layer.current.length} 枚`)
    layer.destroy(); resetFlows()
  })
})
