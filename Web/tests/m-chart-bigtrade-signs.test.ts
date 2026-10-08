// 手机网页 · 图上大单签：纯函数（移植自 KanpanChart/Tests/KanpanChartTests/BigTradeSignsTests.swift，两端同一份规则）
// + 图层（ChartView.addLayer 上真排一屏：命中、读屏、画线文字零相交）。
// 场地：node 里假的 DOM 元素与假画布（只记调用），帧循环不跑。
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { SIGN, planSigns, hitSign, signLabel, type SignBar, type SignEnv } from '../src/m/chart/bigTradeSigns'
import { BigTradeLayer, spanOf, type BigTradeSource } from '../src/m/chart/bigTradeLayer'
import type { Rect, Tiers } from '../src/orderflow/bigTags'
import { ViewWindow } from '../src/m/chart/geometry'
import { BarSeries, INTERVAL_STEP } from '../src/m/chart/series'
import { makeState, withOverlay } from '../src/m/chart/state'
import type { ChartState } from '../src/m/chart/state'
import { ChartView } from '../src/m/chart/view'
import { decodeDrawing } from '../src/m/chart/draw/drawing'
import { drawingLabelBoxes } from '../src/m/chart/renderer.orderflow'

const K: Tiers = { t1: 100_000, t2: 300_000, t3: 1_000_000 }

function env(o: Partial<SignEnv> = {}): SignEnv {
  return {
    tiers: K, spacing: 8, top: 24, bottom: 400, plotW: 800, avoid: [],
    measure: t => t.length * 6, fmt: v => `${Math.round(v / 1000)}K`, ...o,
  }
}
function bar(o: { i?: number; x?: number; hi?: number; lo?: number; buy: number; sell: number }): SignBar {
  const i = o.i ?? 0
  return { i, t: i * 60_000, x: o.x ?? 100, yHigh: o.hi ?? 100, yLow: o.lo ?? 200, bb: o.buy, bs: o.sell }
}
const maxY = (r: Rect) => r.y + r.h, maxX = (r: Rect) => r.x + r.w
const inter = (a: Rect, b: Rect) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h

describe('大单签 · 一根一枚', () => {
  it('大的那一侧：二档买 = 最高价上方 4 的实心三角，三档卖 = 最低价下方 4 + 离尖 2 的胶囊', () => {
    const [s, ...rest] = planSigns([bar({ buy: 500_000, sell: 150_000 })], env())
    expect(rest).toEqual([])
    expect(s.side).toBe('buy'); expect(s.tier).toBe(2); expect(s.shape).toBe('tri'); expect(s.cap).toBeNull(); expect(s.above).toBe(true)
    expect(maxY(s.mark)).toBe(96); expect(s.mark.w).toBe(8); expect(s.mark.h).toBe(7)
    const [t] = planSigns([bar({ buy: 120_000, sell: 2_000_000 })], env())
    expect(t.side).toBe('sell'); expect(t.tier).toBe(3); expect(t.above).toBe(false)
    expect(t.mark.y).toBe(204)
    expect(t.cap!.y).toBe(maxY(t.mark) + 2); expect(t.cap!.h).toBe(16)
    expect(t.cap!.w).toBe('2000K'.length * 6 + 10)
    expect(t.text).toBe('2000K')
  })

  it('一档是直径 5 的圆点、离高点 3；没过线不画', () => {
    const [s] = planSigns([bar({ buy: 150_000, sell: 0 })], env())
    expect(s.shape).toBe('dot'); expect(s.tier).toBe(1); expect(s.cap).toBeNull()
    expect([s.mark.w, s.mark.h]).toEqual([5, 5]); expect(maxY(s.mark)).toBe(97)
    expect(planSigns([bar({ buy: 99_000, sell: 90_000 })], env())).toEqual([])
    expect(planSigns([bar({ buy: 5e6, sell: 0 })], env({ tiers: null }))).toEqual([])
  })

  it('密的周期（一根 < 3）三档也不出胶囊；稀的周期（一根 ≥ 9）二档也出胶囊', () => {
    expect(planSigns([bar({ buy: 2e6, sell: 0 })], env({ spacing: 2 }))[0]).toMatchObject({ shape: 'tri', cap: null })
    expect(planSigns([bar({ buy: 5e5, sell: 0 })], env({ spacing: 10 }))[0].cap).not.toBeNull()
    expect(planSigns([bar({ buy: 5e5, sell: 0 })], env({ spacing: 6 }))[0].cap).toBeNull()
  })
})

describe('大单签 · 翻面 / 退化', () => {
  it('胶囊撞字：只把胶囊翻到另一侧，三角不动', () => {
    const [s] = planSigns([bar({ buy: 2e6, sell: 0 })], env({ avoid: [{ x: 0, y: 70, w: 300, h: 16 }] }))
    expect(s.side).toBe('buy'); expect(s.above).toBe(true); expect(maxY(s.mark)).toBe(96)
    expect(s.capAbove).toBe(false); expect(s.cap!.y).toBe(213) // 最低价 200 + 4 + 7 + 2
  })

  it('三角也撞：整枚翻过去，颜色与朝向不变（side 仍是买）', () => {
    const [s] = planSigns([bar({ buy: 2e6, sell: 0 })], env({ avoid: [{ x: 0, y: 70, w: 300, h: 30 }] }))
    expect(s.side).toBe('buy'); expect(s.above).toBe(false); expect(s.flipped).toBe(true); expect(s.mark.y).toBe(204)
    expect(s.cap!.y).toBe(213)
  })

  it('两侧胶囊都撞：退成本侧三角；三角也放不下就不画', () => {
    const avoid = [{ x: 0, y: 70, w: 300, h: 16 }, { x: 0, y: 212, w: 300, h: 30 }]
    const [s] = planSigns([bar({ buy: 2e6, sell: 0 })], env({ avoid }))
    expect(s).toMatchObject({ shape: 'tri', cap: null, above: true }); expect(maxY(s.mark)).toBe(96)
    const all = [{ x: 0, y: 70, w: 300, h: 30 }, { x: 0, y: 200, w: 300, h: 30 }]
    expect(planSigns([bar({ buy: 2e6, sell: 0 })], env({ avoid: all }))).toEqual([])
  })

  it('胶囊进图例带（顶上 24）就翻面；三角也进就整枚到最低价下方', () => {
    const [s] = planSigns([bar({ hi: 50, buy: 2e6, sell: 0 })], env())
    expect(s.above).toBe(true); expect(s.mark.y).toBeGreaterThanOrEqual(24); expect(s.cap!.y).toBe(213)
    const [t] = planSigns([bar({ hi: 30, buy: 2e6, sell: 0 })], env())
    expect(t.above).toBe(false); expect(t.mark.y).toBe(204)
  })

  it('掉出主图下沿就翻到上方；两侧都放不下不画', () => {
    const [s] = planSigns([bar({ hi: 100, lo: 330, buy: 0, sell: 2e6 })], env({ bottom: 336 }))
    expect(s.side).toBe('sell'); expect(s.above).toBe(true); expect(maxY(s.mark)).toBe(96)
    expect(planSigns([bar({ hi: 30, lo: 330, buy: 0, sell: 2e6 })], env({ bottom: 336 }))).toEqual([])
  })

  it('胶囊横向夹在主图里（左右各留 2）', () => {
    const [s] = planSigns([bar({ x: 796, buy: 2e6, sell: 0 })], env())
    expect(maxX(s.cap!)).toBeLessThanOrEqual(798); expect(s.cap!.x).toBeGreaterThanOrEqual(2)
    const [l] = planSigns([bar({ x: 3, buy: 2e6, sell: 0 })], env())
    expect(l.cap!.x).toBeGreaterThanOrEqual(2)
  })

  it('胶囊让开横跨的那几根（邻根更高）', () => {
    const [s] = planSigns([bar({ buy: 2e6, sell: 0 })], env({ span: () => ({ hiY: 80, loY: 200 }) }))
    expect(maxY(s.cap!)).toBeLessThanOrEqual(78)
  })

  it('spanOf：只取横跨范围内那几根的最高 / 最低', () => {
    const bars = [0, 1, 2, 3].map(i => bar({ i, x: 10 + i * 10, hi: 100 - i * 10, lo: 200 + i, buy: 0, sell: 0 }))
    expect(spanOf(bars)(15, 32)).toEqual({ hiY: 80, loY: 202 })
    expect(spanOf(bars)(100, 120)).toBeNull()
  })

  it('胶囊与胶囊不叠，大的先占位，输出按根序', () => {
    const bars = Array.from({ length: 6 }, (_, i) => bar({ i, x: 100 + i * 8, buy: 1e6 + i * 1000, sell: 0 }))
    const signs = planSigns(bars, env())
    expect(signs.length).toBe(6)
    const caps = signs.flatMap(s => (s.cap ? [s.cap] : []))
    expect(caps.length).toBeGreaterThan(0)
    for (let a = 0; a < caps.length; a++) for (let b = a + 1; b < caps.length; b++) expect(inter(caps[a], caps[b])).toBe(false)
    expect(signs[signs.length - 1].cap).not.toBeNull()
    expect(signs.map(s => s.i)).toEqual([0, 1, 2, 3, 4, 5])
  })

  it('和画线文字零相交、不进图例带、不出主图（随机 200 屏）', () => {
    let seed = 42
    const rnd = (lo: number, hi: number) => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return lo + (hi - lo) * (seed / 0x7fffffff) }
    let total = 0
    for (let k = 0; k < 200; k++) {
      const avoid: Rect[] = Array.from({ length: 4 }, () => ({ x: rnd(0, 700), y: rnd(24, 380), w: rnd(20, 120), h: rnd(12, 20) }))
      const bars = Array.from({ length: 80 }, (_, i) => { const hi = rnd(30, 300); return bar({ i, x: 4 + i * 9.5, hi, lo: hi + rnd(2, 80), buy: rnd(0, 3e6), sell: rnd(0, 3e6) }) })
      const signs = planSigns(bars, env({ spacing: 9.5, avoid }))
      total += signs.length
      for (const s of signs) {
        for (const a of avoid) { expect(inter(a, s.mark)).toBe(false); if (s.cap) expect(inter(a, s.cap)).toBe(false) }
        expect(s.bounds.y).toBeGreaterThanOrEqual(24); expect(maxY(s.bounds)).toBeLessThanOrEqual(400)
      }
    }
    expect(total).toBeGreaterThan(1000)
  })
})

describe('大单签 · 命中与读屏', () => {
  it('44 热区，几枚都中取最近的那枚', () => {
    const signs = planSigns([bar({ i: 0, x: 100, buy: 5e5, sell: 0 }), bar({ i: 1, x: 112, buy: 6e5, sell: 0 })], env())
    expect(signs.length).toBe(2)
    const a = signs[0]
    expect(hitSign(signs, a.cx - 20, a.cy + 20)?.i).toBe(0)
    expect(hitSign(signs, 107, a.cy)?.i).toBe(1)
    expect(hitSign(signs, 104, a.cy)?.i).toBe(0)
    expect(hitSign(signs, a.cx, a.cy - 30)).toBeNull()
    expect(hitSign(signs, 300, 300)).toBeNull()
  })

  it('点胶囊整块也算点中（胶囊翻到了另一侧也一样）', () => {
    const [s] = planSigns([bar({ buy: 2e6, sell: 0 })], env({ avoid: [{ x: 0, y: 70, w: 300, h: 16 }] }))
    expect(hitSign([s], s.cap!.x + s.cap!.w / 2, s.cap!.y + s.cap!.h / 2)?.i).toBe(0)
  })

  it('读屏文案「买方大单 1200K，12:30 这根」', () => {
    const [s] = planSigns([bar({ buy: 1.2e6, sell: 0 })], env())
    expect(signLabel(s, env().fmt, '12:30')).toBe('买方大单 1200K，12:30 这根')
    expect(signLabel({ side: 'sell', usd: 3e5 }, env().fmt, '10月8日')).toBe('卖方大单 300K，10月8日 这根')
  })

  it('尺寸与 iOS 同值', () => {
    expect(SIGN).toMatchObject({ dot: 5, dotGap: 3, triW: 8, triH: 7, triGap: 4, capH: 16, capPadX: 5, capGap: 2, capFont: 11, legendBand: 24, hit: 44 })
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

/** 每 3 根一枚，金额从 0.2M 往上走，最后几根够顶档 */
function source(): BigTradeSource {
  return {
    prepare: series => ({
      tiers: K, live: 0,
      bar: i => (i % 3 === 0 ? { bb: i % 2 ? 0 : 2e5 + (i / series.count) * 3e6, bs: i % 2 ? 2e5 + (i / series.count) * 3e6 : 0 } : null),
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

describe('大单签 · 图层', () => {
  it('一屏排出签：只在主图里、不进图例带、一根至多一枚', () => {
    const { v, layer } = rig()
    const L = v.renderer!.layout(v.width, v.height)
    const signs = layer.current
    expect(signs.length).toBeGreaterThan(5)
    expect(new Set(signs.map(s => s.i)).size).toBe(signs.length)
    for (const s of signs) {
      expect(s.bounds.y).toBeGreaterThanOrEqual(L.main.y + SIGN.legendBand - 0.001)
      expect(maxY(s.bounds)).toBeLessThanOrEqual(L.main.y + L.main.h + 0.001)
      expect(s.bounds.x).toBeGreaterThanOrEqual(-0.001); expect(maxX(s.bounds)).toBeLessThanOrEqual(L.plotW + 0.001)
    }
    expect(signs.some(s => s.shape === 'cap')).toBe(true)
  })

  it('轻点落在签上：交给宿主（返回真 = 手势不再当轻点）；宿主不接（横屏）就照常', () => {
    const taps: number[] = []
    let accept = true
    const { v, layer } = rig(s => { taps.push(s.i); return accept })
    const s = layer.current[layer.current.length - 1]
    expect(v.bigTradeTap!(s.cx, s.cy)).toBe(true)
    expect(taps).toEqual([s.i])
    accept = false
    expect(v.bigTradeTap!(s.cx, s.cy)).toBe(false)
    expect(v.bigTradeTap!(-500, -500)).toBe(false)
    layer.setEnabled(false)
    v.redrawNow()
    expect(layer.current).toEqual([])
    expect(v.bigTradeTap!(s.cx, s.cy)).toBe(false)
    layer.destroy()
    expect(v.bigTradeTap).toBeNull()
  })

  it('读屏：一枚一个隐形按钮，文案「买方 / 卖方大单 金额，时间 这根」，点它等于点签', () => {
    vi.useFakeTimers()
    const taps: number[] = []
    const { layer } = rig(s => { taps.push(s.i); return true })
    vi.advanceTimersByTime(400)
    const aria = (layer as unknown as { aria: { children: Record<string, unknown>[] } }).aria
    expect(aria.children.length).toBe(layer.current.length)
    const b = aria.children[0] as { getAttribute(k: string): string; click(): void }
    expect(b.getAttribute('aria-label')).toMatch(/^(买方|卖方)大单 [\d.]+[KMB]?，\d\d:\d\d 这根$/)
    b.click()
    expect(taps).toEqual([layer.current[0].i])
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
    for (const s of layer.current) for (const b of boxes) { n++; expect(inter(s.mark, b)).toBe(false); if (s.cap) expect(inter(s.cap, b)).toBe(false) }
    expect(n).toBeGreaterThan(0)
    expect(before).toBeGreaterThan(0)
  })
})

// ------------------------------------------------------------------ 压测：1m × 500 根，真数据源

describe('大单签 · 压测', () => {
  it('1m × 500 根满屏：签这层每帧 p95 ≤ 1 ms（这一层是加在原帧上的全部开销）', async () => {
    const { recordTrade, beat, resetFlows } = await import('../src/chart/tradeFlow')
    const { bigTradeSource } = await import('../src/m/chart/bigTradeLayer')
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
    console.log(`[大单签压测] 1m × 500：每帧 p50 ${times[200].toFixed(3)} ms，p95 ${p95.toFixed(3)} ms，签 ${layer.current.length} 枚`)
    layer.destroy(); resetFlows()
  })
})
