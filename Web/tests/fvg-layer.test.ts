// 电脑网页主图「公允价值缺口」层：收线根数、缓存、开关、画法（桩画布，只数调用）
import { describe, it, expect } from 'vitest'
import { fvgZones } from '../src/analysis/fvg'
import { createFVGLayer, closedCountOf, isDarkColor, FVG_COLORS, type FVGChartLike } from '../src/chart/fvgLayer'
import type { Bar } from '../src/chart/calc'
import type { ChartGeometry } from '../src/chart/chart'

const IV = 60_000
const T0 = 1_700_000_000_000

/** 平稳的 34 根（高低 ±1），第 20–22 根造一个向上缺口 [101, 104]，第 25–27 根造一个向下缺口 [107, 108]，之后都不回补 */
function makeBars(): Bar[] {
  const bars: Bar[] = []
  let p = 100
  for (let i = 0; i < 34; i++) {
    let o = p, c = p, h = p + 1, l = p - 1
    if (i === 21) { o = p; c = p + 8; h = p + 8.5; l = p - 0.5 } // 中间那根长阳
    if (i === 22) { o = p + 8; c = p + 9; h = p + 9.5; l = p + 4 }  // 第三根低点 > 第一根高点（p + 1）
    if (i === 26) { o = p; c = p - 3; h = p + 0.5; l = p - 3.5 }   // 中间那根阴线
    if (i === 27) { o = p - 3; c = p - 3.5; h = p - 2; l = p - 4 }  // 第三根高点 < 第一根低点（p - 1）；低点仍在向上缺口之上
    bars.push({ t: T0 + i * IV, o, h, l, c, v: 1 } as Bar)
    if (i === 22) p = p + 9
    if (i === 27) p = p - 3.5
  }
  return bars
}

function geo(bars: Bar[], bg = '#F8F9FA'): ChartGeometry {
  const plotW = 800, spacing = 20, pane = { id: 'main', y: 0, h: 400 } as ChartGeometry['pane']
  const n = bars.length
  const indexToX = (i: number) => plotW - (n - 1 - i) * spacing - spacing / 2
  const idx = (t: number) => (t - bars[0].t) / IV
  return {
    pane, range: { min: 80, max: 120 }, plotW, from: 0, to: n - 1, spacing, iv: IV, log: false,
    priceToY: v => (120 - v) / 40 * 400, yToPrice: y => 120 - y / 400 * 40,
    timeToX: t => indexToX(idx(t)), xToTime: x => bars[0].t + ((x - indexToX(0)) / spacing) * IV,
    timeOf: i => bars[0].t + i * IV, indexToX, colors: { bg } as ChartGeometry['colors'], dec: 2, last: bars[n - 1].c,
    bar: i => bars[i] ?? null, xToIndex: x => (x - indexToX(0)) / spacing,
  }
}

function stubCtx(): { ctx: CanvasRenderingContext2D; calls: [string, unknown[]][] } {
  const calls: [string, unknown[]][] = []
  const ctx = new Proxy({} as Record<string, unknown>, {
    get: (t, k: string) => k in t ? t[k] : (...a: unknown[]) => { calls.push([k, a]) },
    set: (t, k: string, v) => { t[k] = v; calls.push(['set:' + k, [v]]); return true },
  }) as unknown as CanvasRenderingContext2D
  return { ctx, calls }
}

describe('公允价值缺口层（电脑网页）', () => {
  it('收线根数：最后一根没走完就不算', () => {
    const bars = makeBars(), last = bars[bars.length - 1].t
    expect(closedCountOf(bars, IV, last + IV - 1)).toBe(bars.length - 1)
    expect(closedCountOf(bars, IV, last + IV)).toBe(bars.length)
    expect(closedCountOf([], IV, last)).toBe(0)
  })

  it('算出来的缺口和 fvgZones(bars, closedCount) 一模一样（含正在走的那根的规则）', () => {
    const bars = makeBars(), last = bars[bars.length - 1].t
    for (const now of [last + 1, last + IV + 5]) {
      const chart: FVGChartLike = { bars, iv: IV, compareOn: () => false }
      const layer = createFVGLayer({ chart, on: () => true, now: () => now })
      expect(layer.zones()).toEqual(fvgZones(bars, closedCountOf(bars, IV, now)))
    }
    const sides = createFVGLayer({ chart: { bars, iv: IV, compareOn: () => false }, on: () => true, now: () => last + 1 }).zones().map(z => z.side)
    expect(sides).toEqual(['bull', 'bear'])
  })

  it('K 线没变就不重算；推送改了最后一根、新开一根、换数组、到点收线才重算', () => {
    const bars = makeBars(), last = bars[bars.length - 1].t
    let now = last + 1
    const chart: FVGChartLike = { bars, iv: IV, compareOn: () => false }
    const layer = createFVGLayer({ chart, on: () => true, now: () => now })
    const { ctx } = stubCtx(), g = geo(bars)
    for (let k = 0; k < 5; k++) layer.beforeCandles!(ctx, g)
    layer.zones()
    expect(layer.scans).toBe(1)
    bars[bars.length - 1].c += 0.1 // 推送原地改同一根
    layer.zones(); expect(layer.scans).toBe(2)
    layer.zones(); expect(layer.scans).toBe(2)
    now = last + IV // 到点收线
    layer.zones(); expect(layer.scans).toBe(3)
    bars.push({ ...bars[bars.length - 1], t: last + IV }) // 新开一根
    layer.zones(); expect(layer.scans).toBe(4)
    chart.bars = bars.slice() // setData 换了一份
    layer.zones(); expect(layer.scans).toBe(5)
    layer.zones(); expect(layer.scans).toBe(5)
  })

  it('关着、对比模式、等幅 K 线：一笔都不画', () => {
    const bars = makeBars(), last = bars[bars.length - 1].t, g = geo(bars)
    const cases: [boolean, boolean, boolean][] = [[false, false, false], [true, true, false], [true, false, true]]
    for (const [on, cmp, hidden] of cases) {
      const { ctx, calls } = stubCtx()
      const layer = createFVGLayer({ chart: { bars, iv: IV, compareOn: () => cmp }, on: () => on, hidden: () => hidden, now: () => last + 1 })
      layer.beforeCandles!(ctx, g)
      expect(calls.filter(([k]) => k === 'fillRect' || k === 'stroke')).toHaveLength(0)
    }
  })

  it('一多一空：两块填充都画到图的右缘，中线是虚线；不挂悬停 / 点击，走蜡烛前那一格', () => {
    const bars = makeBars(), last = bars[bars.length - 1].t, g = geo(bars)
    const layer = createFVGLayer({ chart: { bars, iv: IV, compareOn: () => false }, on: () => true, now: () => last + 1 })
    expect(layer.hover).toBeUndefined(); expect(layer.click).toBeUndefined(); expect(layer.under).toBeUndefined()
    const { ctx, calls } = stubCtx()
    layer.beforeCandles!(ctx, g)
    const fills = calls.filter(([k]) => k === 'fillRect').map(([, a]) => a as number[])
    expect(fills).toHaveLength(2)
    const zs = layer.zones()
    zs.forEach((z, k) => {
      const [x, , w] = fills[k]
      expect(x).toBeCloseTo(g.timeToX(z.startMs) - g.spacing / 2)
      expect(x + w).toBe(g.plotW)
    })
    const fillStyles = calls.filter(([k]) => k === 'set:fillStyle').map(([, a]) => a[0])
    expect(fillStyles[0]).toBe('rgba(41,98,255,0.12)') // 多头：布林蓝
    expect(fillStyles[1]).toBe('rgba(217,119,6,0.12)')  // 空头：琥珀
    const strokes = calls.filter(([k]) => k === 'stroke').length
    expect(strokes).toBe(zs.filter(z => z.midVisible).length)
    expect(strokes).toBeGreaterThan(0)
    expect(calls.some(([k, a]) => k === 'setLineDash' && (a[0] as number[]).length === 2)).toBe(true)
    expect(calls.filter(([k]) => k === 'set:lineWidth').map(([, a]) => a[0])).toContain(0.5)
  })

  it('深色底换深色那一套颜色', () => {
    expect(isDarkColor('#14171D')).toBe(true)
    expect(isDarkColor('#F8F9FA')).toBe(false)
    expect(isDarkColor('rgb(20, 23, 29)')).toBe(true)
    const bars = makeBars(), last = bars[bars.length - 1].t
    const layer = createFVGLayer({ chart: { bars, iv: IV, compareOn: () => false }, on: () => true, now: () => last + 1 })
    const { ctx, calls } = stubCtx()
    layer.beforeCandles!(ctx, geo(bars, '#14171D'))
    const n = parseInt(FVG_COLORS.dark.bull.slice(1), 16)
    expect(calls.find(([k]) => k === 'set:fillStyle')?.[1][0]).toBe(`rgba(${n >> 16 & 255},${n >> 8 & 255},${n & 255},0.12)`)
  })
})
