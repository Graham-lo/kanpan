// 手机网页 · 公允价值缺口这一层（src/m/chart/renderer.fvg.ts）：已收线根数、缓存、开关 / 对比 / 百分比轴不算、画法与先后。
import { describe, expect, it } from 'vitest'
import { BarSeries } from '../src/m/chart/series'
import { ViewWindow, priceTransform } from '../src/m/chart/geometry'
import { makeState, withInput, withOverlay, withViewport } from '../src/m/chart/state'
import { ChartRenderer } from '../src/m/chart/renderer'
import { FALLBACK_COLORS } from '../src/m/chart/paint'
import { closedBarCount, drawFVG, fvgComputeCount, fvgShown, fvgZonesFor } from '../src/m/chart/renderer.fvg'
import { fvgZonesOfSeries } from '../src/analysis/fvg'
import rendererSource from '../src/m/chart/renderer.ts?raw'

const STEP = 15 * 60_000
const T0 = Date.UTC(2026, 9, 1)
const W = 402, H = 520

/** 0–20 平盘（高 101 低 99）；21–22 拉出一块多头缺口 [101, 103]；23–28 横在 106–108；29–30 砸出一块空头缺口 [105, 106]；
 *  31 是正在走的那根（没碰到两块缺口）。 */
function gapSeries(): BarSeries {
  const rows: [number, number, number, number][] = []
  for (let i = 0; i <= 20; i++) rows.push([100, 101, 99, 100])
  rows.push([100, 106, 100, 105], [105, 108, 103, 107], [107, 108, 105.5, 107])
  for (let i = 24; i <= 28; i++) rows.push([107, 108, 106, 107])
  rows.push([106, 106.5, 104.5, 105], [105, 105, 104, 104.5], [104.5, 105, 104, 104.5])
  return new BarSeries({
    symbol: 'BTCUSDT', interval: '15m', t0: T0,
    open: rows.map(r => r[0]), high: rows.map(r => r[1]), low: rows.map(r => r[2]), close: rows.map(r => r[3]),
    volume: rows.map(() => 1),
  })
}

/** 末根开盘后半个周期：末根还在走 */
const liveNow = (s: BarSeries): number => s.lastTime + STEP / 2

function rig(fvg = true): { r: ChartRenderer; s: BarSeries } {
  const s = gapSeries()
  const st = makeState({
    series: s, symbol: { symbol: 'BTCUSDT', base: 'BTC', priceDecimals: 2 },
    view: new ViewWindow(s.lastTime + STEP, STEP * 40), colors: FALLBACK_COLORS, price: priceTransform('linear'),
    overlays: [], subs: [], fvg,
  })
  return { r: new ChartRenderer(st), s }
}

/** 记下每次 fillRect 时的 fillStyle / globalAlpha、每次 stroke 时的 strokeStyle / 线宽 / 虚线 */
function recCtx() {
  const fills: { style: string; alpha: number; x: number; y: number; w: number; h: number }[] = []
  const strokes: { style: string; alpha: number; width: number; dash: number[] }[] = []
  const o: Record<string, unknown> = { globalAlpha: 1, fillStyle: '', strokeStyle: '', lineWidth: 1 }
  let dash: number[] = []
  const ctx = new Proxy(o, {
    get: (t, k) => {
      if (k === 'fillRect') return (x: number, y: number, w: number, h: number) => fills.push({ style: String(t.fillStyle), alpha: Number(t.globalAlpha), x, y, w, h })
      if (k === 'stroke') return () => strokes.push({ style: String(t.strokeStyle), alpha: Number(t.globalAlpha), width: Number(t.lineWidth), dash })
      if (k === 'setLineDash') return (d: number[]) => { dash = d }
      if (k in t) return t[k as string]
      return () => ({ width: 10 })
    },
    set: (t, k, v) => { t[k as string] = v; return true },
  }) as unknown as CanvasRenderingContext2D
  return { ctx, fills, strokes }
}

describe('已收线根数', () => {
  it('末根还没走完不算它；到点就算', () => {
    const s = gapSeries()
    expect(closedBarCount(s, liveNow(s))).toBe(s.count - 1)
    expect(closedBarCount(s, s.lastTime + STEP)).toBe(s.count)
    expect(closedBarCount(BarSeries.empty('BTCUSDT', '15m'), 0)).toBe(0)
  })
})

describe('缓存', () => {
  it('结果就是共用算法对（序列, 已收线根数）的输出：一块多头、一块空头', () => {
    const { r, s } = rig()
    const now = liveNow(s)
    const zones = fvgZonesFor(r, now)
    expect(zones).toEqual(fvgZonesOfSeries(s, s.count - 1))
    expect(zones.map(z => z.side)).toEqual(['bull', 'bear'])
    expect(zones[0]).toMatchObject({ top: 103, bottom: 101, startMs: s.time(21) })
    expect(zones[1]).toMatchObject({ top: 106, bottom: 105, startMs: s.time(29) })
  })

  it('序列没动就原样返回、不重算；十字线 / 视野变化也不重算', () => {
    const { r, s } = rig()
    const now = liveNow(s)
    const a = fvgZonesFor(r, now)
    const n = fvgComputeCount()
    expect(fvgZonesFor(r, now)).toBe(a)
    r.state = withOverlay(r.state, { crosshair: { index: 10, pane: null, t: s.time(10), price: 100 } })
    r.state = withViewport(r.state, { view: new ViewWindow(s.lastTime, STEP * 20) })
    expect(fvgZonesFor(r, now)).toBe(a)
    expect(fvgComputeCount()).toBe(n)
  })

  it('末根变了（revision）或末根收线（已收线根数）才重算', () => {
    const { r, s } = rig()
    const now = liveNow(s)
    const a = fvgZonesFor(r, now)
    const n = fvgComputeCount()
    // 末根收线：同一份序列，已收线根数 +1
    const b = fvgZonesFor(r, s.lastTime + STEP)
    expect(fvgComputeCount()).toBe(n + 1)
    expect(b).not.toBe(a)
    expect(b).toEqual(fvgZonesOfSeries(s, s.count))
    // 末根跳了一口，砸穿空头缺口上沿：重算，空头那块被补掉
    s.high[s.count - 1] = 106.5
    s.stampAll()
    const c = fvgZonesFor(r, now)
    expect(fvgComputeCount()).toBe(n + 2)
    expect(c.map(z => z.side)).toEqual(['bull'])
  })
})

describe('不画就不算', () => {
  it('开关关着：不画、不算', () => {
    const { r, s } = rig(false)
    const n = fvgComputeCount()
    const L = r.layout(W, H), range = r.priceRange(W, H)
    expect(fvgShown(r)).toBe(false)
    expect(drawFVG(r, recCtx().ctx, L.main, range, L, liveNow(s))).toBe(0)
    expect(fvgComputeCount()).toBe(n)
  })

  it('对比模式（百分比轴）与百分比价格轴：不画、不算', () => {
    const { r, s } = rig()
    const n = fvgComputeCount()
    const cmp = withInput(r.state, { percentAxis: true })
    const rc = new ChartRenderer(cmp)
    const L = rc.layout(W, H)
    expect(drawFVG(rc, recCtx().ctx, L.main, rc.priceRange(W, H), L, liveNow(s))).toBe(0)
    const pct = new ChartRenderer(withViewport(r.state, { price: priceTransform('percent') }))
    expect(drawFVG(pct, recCtx().ctx, L.main, pct.priceRange(W, H), L, liveNow(s))).toBe(0)
    expect(fvgComputeCount()).toBe(n)
  })
})

describe('画法', () => {
  it('多头 t.band、空头 t.amber，填充 12%，盒子铺到图右缘；中线 0.5 虚线 35%', () => {
    const { r, s } = rig()
    const L = r.layout(W, H), range = r.priceRange(W, H)
    const { ctx, fills, strokes } = recCtx()
    expect(drawFVG(r, ctx, L.main, range, L, liveNow(s))).toBe(2)
    expect(fills.map(f => f.style)).toEqual([FALLBACK_COLORS.band, FALLBACK_COLORS.amber])
    for (const f of fills) {
      expect(f.alpha).toBeCloseTo(0.12)
      expect(f.x).toBeGreaterThanOrEqual(0)
      expect(f.x + f.w).toBeCloseTo(L.plotW)
    }
    expect(strokes.length).toBe(2)
    for (const k of strokes) {
      expect(k.alpha).toBeCloseTo(0.35)
      expect(k.width).toBe(0.5)
      expect(k.dash.length).toBeGreaterThan(0)
    }
  })

  it('整帧里排在主力订单流之后、蜡烛之前', () => {
    const body = rendererSource.slice(rendererSource.indexOf('  draw(ctx: CanvasRenderingContext2D'))
    const of = body.indexOf('drawOrderFlow(this'), fvg = body.indexOf('drawFVG(this'), candles = body.indexOf('this.drawCandles(')
    expect(of).toBeGreaterThan(0)
    expect(fvg).toBeGreaterThan(of)
    expect(candles).toBeGreaterThan(fvg)
  })

  it('不撑价格轴：开关开不开，价格区间一样', () => {
    const on = rig(true).r, off = rig(false).r
    expect(on.priceRange(W, H)).toEqual(off.priceRange(W, H))
  })
})
