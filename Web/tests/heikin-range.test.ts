// 平均 K 线 / 等幅 K 线（2026-10-07）：换算、增量缓存、幅度取整、合成与实时推进、往左翻页拼接、画线藏不删、性能
import { beforeEach, describe, expect, it } from 'vitest'
import type { Bar } from '../src/chart/calc'
import type { TVChart } from '../src/chart/chart'
import { HACache, haStep, heikinAshi } from '../src/chart/heikinAshi'
import { RangeBuilder, baseBars, bindRangeBars, rangeBarsOn, rangeStep, rangeTicks, resetRangeBars, setRangeBars, stepText } from '../src/chart/rangeBars'

const M = 60_000, T0 = 1_700_000_040_000 // 整分钟
/** 可复现的随机游走 1 分钟线 */
function walk1m(n: number, seed = 7, p0 = 100): Bar[] {
  let x = seed, p = p0
  const r = () => { x = (x * 1103515245 + 12345) % 2147483648; return x / 2147483648 }
  const out: Bar[] = []
  for (let i = 0; i < n; i++) {
    const o = p, c = +(o + (r() - 0.5) * 0.8).toFixed(2)
    const h = +(Math.max(o, c) + r() * 0.3).toFixed(2), l = +(Math.min(o, c) - r() * 0.3).toFixed(2)
    out.push({ t: T0 + i * M, o, h, l, c, v: 1000 + Math.round(r() * 500), tb: 500, bv: 10 })
    p = c
  }
  return out
}
const sum = (a: Bar[], k: 'v' | 'tb' | 'bv') => a.reduce((s, b) => s + (b[k] ?? 0), 0)
/** 合成结果的硬约束：走满的根 高−低 = 幅度、下一根从上一根收盘开、时间严格递增 */
function checkRange(out: Bar[], step: number): void {
  for (let i = 0; i < out.length; i++) {
    const b = out[i]
    expect(b.h - b.l).toBeLessThanOrEqual(step + 1e-9)
    if (i < out.length - 1) {
      expect(b.h - b.l).toBeCloseTo(step, 9)
      expect(out[i + 1].o).toBeCloseTo(b.c, 9)
      expect(out[i + 1].t).toBeGreaterThan(b.t)
      expect([b.h, b.l].some(x => Math.abs(x - b.c) < 1e-9)).toBe(true) // 收在走满的那一头
    }
  }
}

describe('平均 K 线', () => {
  it('换算：收 = 四价均值；开 = 上一根平均开收的中点（第一根取开收中点）；高低把平均开收包进去', () => {
    const bars: Bar[] = [{ t: 0, o: 10, h: 12, l: 9, c: 11, v: 1 }, { t: 1, o: 11, h: 11.5, l: 8, c: 8.5, v: 1 }]
    const ha = heikinAshi(bars)
    expect(ha[0]).toEqual({ o: 10.5, h: 12, l: 9, c: 10.5 })
    expect(ha[1].c).toBeCloseTo((11 + 11.5 + 8 + 8.5) / 4)
    expect(ha[1].o).toBeCloseTo(10.5)
    expect(ha[1].h).toBe(11.5); expect(ha[1].l).toBe(8)
    expect(haStep(bars[1], ha[0])).toEqual(ha[1])
  })
  it('增量缓存：最后一根原地改、往后加根、整份换都和整段重算一致', () => {
    const bars = walk1m(300), cache = new HACache()
    expect(cache.get(bars)).toEqual(heikinAshi(bars))
    Object.assign(bars[299], { h: bars[299].h + 1, c: bars[299].c + 0.7 })
    expect(cache.get(bars)).toEqual(heikinAshi(bars))
    bars.push({ ...bars[299], t: bars[299].t + M, o: bars[299].c })
    expect(cache.get(bars)).toEqual(heikinAshi(bars))
    const more = walk1m(20, 3).map(b => ({ ...b, t: b.t - 100 * M })).concat(bars)
    expect(cache.get(more)).toEqual(heikinAshi(more))
  })
})

describe('等幅 K 线 · 幅度', () => {
  const flat = (tr: number, n = 40): Bar[] => Array.from({ length: n }, (_, i) => ({ t: i * M, o: 100, h: 100 + tr / 2, l: 100 - tr / 2, c: 100, v: 1 }))
  it('ATR(14) × 0.5 取最近的 1/2/5×10ⁿ', () => {
    expect(rangeStep(flat(30), 2)).toBe(20)   // 15 → 20（按比例更近）
    expect(rangeStep(flat(8), 2)).toBe(5)     // 4 → 5
    expect(rangeStep(flat(0.6), 2)).toBe(0.2) // 0.3 → 0.2
    expect(rangeStep(flat(0.0021), 4)).toBe(0.001)
  })
  it('至少一个最小价位；Wilder 平滑跟着最近的波动走', () => {
    expect(rangeStep(flat(0.0001), 2)).toBe(0.01)
    const calmThenWild = flat(1, 200).concat(flat(40, 60).map((b, i) => ({ ...b, t: (200 + i) * M })))
    expect(rangeStep(calmThenWild, 2)).toBe(20)
  })
  it('幅度的写法是普通数字、去尾零', () => {
    expect(stepText(20)).toBe('20'); expect(stepText(0.5)).toBe('0.5'); expect(stepText(0.002)).toBe('0.002'); expect(stepText(1e-7)).toBe('0.0000001')
  })
})

describe('等幅 K 线 · 合成', () => {
  it('从 1 分钟线合成：每根走满幅度、首尾相接、时间严格递增且落在来源那一分钟里、成交量一分不差', () => {
    const base = walk1m(2000), step = rangeStep(base, 2), out = new RangeBuilder(step).build(base).out
    expect(out.length).toBeGreaterThan(50)
    checkRange(out, step)
    expect(out[0].o).toBe(base[0].o); expect(out.at(-1)!.c).toBeCloseTo(base.at(-1)!.c, 9)
    for (const b of out) expect(b.t).toBeGreaterThanOrEqual(T0)
    expect(out.at(-1)!.t).toBeLessThan(base.at(-1)!.t + M)
    expect(sum(out, 'v')).toBeCloseTo(sum(base, 'v'), 6)
    expect(sum(out, 'tb')).toBeCloseTo(sum(base, 'tb'), 6)
  })
  it('一分钟里走了好几个幅度：拆成好几根，阳线按 开→低→高→收 走；时间按走过的路程落在这一分钟里', () => {
    const out = new RangeBuilder(1).build([{ t: T0, o: 10, h: 13, l: 9.5, c: 12.5, v: 90 }]).out
    expect(out.map(b => [b.o, b.h, b.l, b.c])).toEqual([[10, 10.5, 9.5, 10.5], [10.5, 11.5, 10.5, 11.5], [11.5, 12.5, 11.5, 12.5], [12.5, 13, 12.5, 12.5]])
    expect(out.map(b => b.t - T0)).toEqual([0, 20000, 33333, 46666])  // 路程 4.5：走到 1.5、2.5、3.5 处各开一根
    expect(out.map(b => +b.v.toFixed(6))).toEqual([30, 20, 20, 20])  // 第一根走了 1.5 的路程，其余各 1
  })
  it('实时：同一分钟反复推送只接着走新多出来的那段，和整根当历史合成走到同样的价位；成交量按增量分', () => {
    const base = walk1m(500), step = rangeStep(base, 2)
    const b = new RangeBuilder(step).build(base.slice(0, -1)), last = base.at(-1)!
    const n0 = b.out.length
    // 逐笔：先到开盘，再一路到收盘（中间创的新高新低先到）
    const ticks = [
      { ...last, h: last.o, l: last.o, c: last.o, v: 10 },
      { ...last, h: last.o, l: last.l, c: last.l, v: 400 },
      { ...last, l: last.l, c: last.h, v: 900 },
      { ...last },
    ]
    let fed: Bar[] = []
    for (const [k, tk] of ticks.entries()) fed = b.update(tk, last.t + 10_000 * (k + 1))
    checkRange(b.out, step)
    expect(b.out.at(-1)!.c).toBeCloseTo(last.c, 9)
    expect(sum(b.out, 'v')).toBeCloseTo(sum(base, 'v'), 6)
    expect(fed[0]).toBe(b.out[Math.max(n0 - 1, b.out.length - fed.length)])  // 交给图表的是改过的最后一根 + 新加的
    for (const x of b.out.slice(n0)) { expect(x.t).toBeGreaterThan(last.t); expect(x.t).toBeLessThan(last.t + M) }
    // 新的一分钟：从上一分钟收盘接着走
    const nb = { t: last.t + M, o: last.c, h: last.c + step * 2.5, l: last.c, c: last.c + step * 2.5, v: 50 }
    b.update(nb, nb.t + 5000)
    checkRange(b.out, step)
    expect(b.out.at(-1)!.c).toBeCloseTo(nb.c, 9)
    // 晚到的老推送不动
    expect(b.update({ ...last, c: 1 }, nb.t)).toEqual([])
  })
  it('性能：1 万根 1 分钟线合成 < 20 ms', () => {
    const base = walk1m(10_000, 11), step = rangeStep(base, 2)
    new RangeBuilder(step).build(base) // 热身
    const t = performance.now()
    const out = new RangeBuilder(step).build(base).out
    const ms = performance.now() - t
    console.log(`等幅合成 10000 根 1 分钟线 → ${out.length} 根：${ms.toFixed(2)} ms`)
    expect(ms).toBeLessThan(20)
  })
  it('时间刻度：按跨过整几分钟挑，标的是那根开始的时间', () => {
    const times = [0, 20, 50, 70, 130, 170, 185].map(s => T0 + s * 1000)
    const ticks = rangeTicks(i => times[Math.max(0, Math.min(6, i))], 0, 6, i => i * 200, times.length)
    expect(ticks.map(t => t.i)).toEqual([3, 4, 6]) // 01:10、02:10、03:05 各跨进新的一分钟
  })
})

// ------------------------------------------------------------ 挂到图表上（用一个只有 setData / prependData / updateBar 与坐标换算的假图表）
class FakeChart {
  bars: Bar[] = []; iv = 36e5; meta = { symbol: '', title: '', sub: '', dec: 2 }; rightBar = 0; spacing = 8
  dirty = false; legendDirty = false
  legendExtra: ((i: number) => string) | null = null
  drawingShown: ((d: { pts: { t: number; p: number }[] }) => boolean) | null = null
  resets = 0
  setData(bars: Bar[], meta: { iv: number; symbol?: string; dec?: number }): void {
    const same = this.meta.symbol === meta.symbol && this.iv === meta.iv && this.bars.length > 0
    this.bars = bars; this.iv = meta.iv; this.meta = Object.assign({}, this.meta, meta)
    if (!same) { this.rightBar = bars.length - 1 + 6; this.resets++ }
  }
  prependData(more: Bar[]): void { const f = this.bars[0]?.t ?? Infinity; more = more.filter(b => b.t < f); this.bars = more.concat(this.bars); this.rightBar += more.length }
  updateBar(b: Bar): void {
    const n = this.bars.length, last = this.bars[n - 1]
    if (!n) return
    if (b.t === last.t) Object.assign(last, b); else if (b.t > last.t) { const e = this.rightBar >= n - 1; this.bars.push(b); if (e) this.rightBar++ }
  }
  timeAt(i: number): number { return this.bars[Math.max(0, Math.min(this.bars.length - 1, Math.round(i)))]?.t ?? 0 }
  timeOfIndex(i: number): number { return this.timeAt(i) }
  indexAt(t: number): number { let k = 0; while (k < this.bars.length - 1 && this.bars[k + 1].t <= t) k++; return k }
  xToIndex(x: number): number { return this.rightBar - (800 - x) / this.spacing }
  indexToX(i: number): number { return 800 - (this.rightBar - i) * this.spacing }
}
const meta1m = { symbol: 'BTCUSDT', iv: M, dec: 2 }

describe('等幅 K 线 · 挂到图表', () => {
  let c: FakeChart, chart: TVChart
  beforeEach(() => { resetRangeBars(); c = new FakeChart(); chart = c as unknown as TVChart; bindRangeBars(chart, 0) })

  it('开着时 1 分钟数据进来图上是合成的根；原始 1 分钟留着（补尾巴对齐用）；图例多一行「幅度」', () => {
    setRangeBars(0, true)
    const base = walk1m(1500)
    chart.setData(base, meta1m)
    expect(c.bars).not.toBe(base)
    expect(c.bars.every(b => b.h - b.l <= rangeStep(base, 2) + 1e-9)).toBe(true)
    expect(baseBars(chart)).toBe(base)
    checkRange(c.bars, rangeStep(base, 2))
    expect(c.legendExtra!(0)).toContain(`幅度 ${stepText(rangeStep(base, 2))}`)
  })
  it('实时推送推进最后一根、走满了往后加根；同一只品种重取时幅度不变', () => {
    setRangeBars(0, true)
    const base = walk1m(1500), step = rangeStep(base, 2)
    chart.setData(base.slice(), meta1m)
    const n = c.bars.length, last = base.at(-1)!
    chart.updateBar({ t: last.t + M, o: last.c, h: last.c + step * 3.2, l: last.c, c: last.c + step * 3.2, v: 9 })
    expect(c.bars.length).toBe(n + 3)
    expect(c.bars.at(-1)!.c).toBeCloseTo(last.c + step * 3.2, 9)
    checkRange(c.bars, step)
    expect(baseBars(chart).at(-1)!.t).toBe(last.t + M)
    chart.setData(walk1m(1500, 99, 100).map(b => ({ ...b, h: b.h + 5, l: b.l - 5 })), meta1m) // 波动大很多的一份
    expect(c.legendExtra!(0)).toContain(`幅度 ${stepText(step)}`)
  })
  it('往左翻页：更早的一段单独合成接在前面，已经画着的根一根不动', () => {
    setRangeBars(0, true)
    const all = walk1m(3000), step = rangeStep(all.slice(1500), 2)
    chart.setData(all.slice(1500), meta1m)
    const before = c.bars.slice(), rb = c.rightBar
    chart.prependData(all.slice(0, 1501)) // 交易所会把截止那一根也回来：要去重
    expect(c.bars.slice(-before.length)).toEqual(before)
    expect(c.bars.slice(-before.length)[0]).toBe(before[0])
    expect(c.rightBar - rb).toBe(c.bars.length - before.length)
    expect(baseBars(chart).length).toBe(3000)
    checkRange(c.bars.slice(0, c.bars.length - before.length), step)
  })
  it('画线：比最早一根还早的在等幅下藏起来（不删），退出等幅就回来；退出后停在最右边', () => {
    setRangeBars(0, true)
    const base = walk1m(1500)
    chart.setData(base, meta1m)
    const early = { pts: [{ t: T0 - 3 * M, p: 100 }, { t: T0 + 10 * M, p: 101 }] }, inside = { pts: [{ t: c.bars[5].t, p: 100 }] }
    expect(c.drawingShown!(early)).toBe(false)
    expect(c.drawingShown!(inside)).toBe(true)
    setRangeBars(0, false)
    expect(c.drawingShown).toBeNull()
    expect(c.bars).toBe(base)
    expect(c.rightBar).toBe(base.length - 1 + 6)
    expect(c.legendExtra!(0)).toBe('')
  })
  it('等幅开着换到别的周期：当成退出等幅；十六图里各格独立', () => {
    setRangeBars(0, true)
    const other = new FakeChart(); bindRangeBars(other as unknown as TVChart, 1)
    chart.setData(walk1m(100), meta1m)
    ;(other as unknown as TVChart).setData(walk1m(100), meta1m)
    expect(other.bars.length).toBe(100)              // 第 2 格没开：原样 1 分钟
    chart.setData(walk1m(100), { ...meta1m, iv: 36e5 })
    expect(rangeBarsOn(0)).toBe(false)
    expect(c.bars.length).toBe(100)
  })
})
