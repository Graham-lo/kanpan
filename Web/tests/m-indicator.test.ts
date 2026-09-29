// 移植自 KanpanCore/Tests/KanpanCoreTests/IndicatorGoldenTests.swift + IndicatorEdgeTests.swift
// + LayoutTests.swift（IndicatorMetaTests）+ OINoticeTests.swift + ExternalSeriesTests.swift（cache）
//
// 黄金值直接读 iOS 那边的夹具（KanpanCore/Tests/KanpanCoreTests/Fixtures/indicators.json），不复制。
import { describe, expect, it } from 'vitest'
// @ts-expect-error Web 的 tsconfig 不带 @types/node，这里只在 vitest（node 环境）里用
import { readFileSync } from 'node:fs'
import { BarSeries, ExternalSeries, bar } from '../src/m/chart/series'
import type { Interval } from '../src/m/chart/series'
import { atr, boll, kdj, macd, rsi } from '../src/m/indicator/indicators'
import { ema, rma, sma, smaSkip, swiftMax, swiftMin } from '../src/m/indicator/math'
import {
  ALL_INDICATOR_IDS, IndicatorResult, OINotice, defaultOverlays, defaultParams, defaultSubs, fixedScale, guides,
  indicatorFromRaw, indicatorName, isRetired, lineNames, mainPalette, normalizedParams, oiNoticeForEmptyPane,
  palette, paramLabels, placement, retired, subPalette, tailBars,
} from '../src/m/indicator/ids'
import type { IndicatorID } from '../src/m/indicator/ids'
import { IndicatorEngine, startsAnchorPeriod, utcMonthIndex } from '../src/m/indicator/engine'

// ------------------------------------------------------------------ 夹具

type Raw = Record<string, unknown>
const FIXTURE = new URL('../../KanpanCore/Tests/KanpanCoreTests/Fixtures/indicators.json', import.meta.url)
const fx = JSON.parse(readFileSync(FIXTURE, 'utf8')) as { params: Record<string, number[]>; cases: Raw[] }

/** JSON 里 NaN 写成 null，读回来还原成 NaN。 */
const nums = (a: unknown): number[] => (Array.isArray(a) ? a.map(x => (typeof x === 'number' ? x : NaN)) : [])
const rows = (a: unknown): number[][] => (Array.isArray(a) ? a.map(nums) : [])

class GoldenCase {
  constructor(readonly c: Raw) {}
  get name(): string { return `${this.c.symbol}|${this.c.interval}` }
  get close(): number[] { return nums(this.c.close) }
  get high(): number[] { return nums(this.c.high) }
  get low(): number[] { return nums(this.c.low) }
  get volume(): number[] { return nums(this.c.volume) }
  get atr(): number[] { return nums(this.c.atr) }
  line(key: string, i: number): number[] { return rows(this.c[key])[i] ?? [] }
  part(key: string, sub: string): number[] { return nums((this.c[key] as Raw | undefined)?.[sub]) }
  get series(): BarSeries {
    return new BarSeries({
      symbol: String(this.c.symbol), interval: String(this.c.interval) as Interval,
      t0: this.c.t0 as number, step: this.c.step as number,
      open: nums(this.c.open), high: this.high, low: this.low, close: this.close, volume: this.volume,
    })
  }
}
const cases = fx.cases.map(c => new GoldenCase(c))
const P = fx.params

/** 逐点比：NaN 的位置必须一样，数字的绝对误差 ≤ tol。 */
function expectSame(got: readonly number[], want: readonly number[], label: string, tol = 1e-9): void {
  expect(got.length, `${label} 长度`).toBe(want.length)
  let bad = 0, first = ''
  for (let i = 0; i < got.length; i++) {
    const ok = Number.isNaN(want[i]) ? Number.isNaN(got[i]) : Number.isFinite(got[i]) && Math.abs(got[i] - want[i]) <= tol
    if (!ok) { bad++; if (!first) first = `[${i}] want ${want[i]} got ${got[i]}` }
  }
  expect(bad, `${label}：${bad} 点不符，首个 ${first}`).toBe(0)
}

// ------------------------------------------------------------------ 合成行情（Fixtures.swift 的 Rng / synthSeries）

const M64 = (1n << 64n) - 1n
class Rng {
  private s: bigint
  constructor(seed: number | bigint) { this.s = (BigInt(seed) * 6364136223846793005n + 1n) & M64 }
  next(): bigint {
    let s = this.s
    s ^= (s << 13n) & M64; s ^= s >> 7n; s ^= (s << 17n) & M64
    this.s = s
    return s
  }
  d(a = 0, b = 1): number { return a + (Number(this.next() >> 11n) / 2 ** 53) * (b - a) }
  i(a: number, b: number): number { return a + Number(this.next() % BigInt(b - a + 1)) }
}

function synthSeries(count: number, seed = 7, interval: Interval = '1h', t0 = 1_700_000_000_000): BarSeries {
  const r = new Rng(seed)
  const o: number[] = [], h: number[] = [], l: number[] = [], c: number[] = [], v: number[] = [], tb: number[] = []
  let px = 100
  for (let k = 0; k < count; k++) {
    const op = px
    px = Math.max(1, px * (1 + r.d(-0.02, 0.02)))
    o.push(op); c.push(px)
    h.push(Math.max(op, px) * (1 + r.d(0, 0.01)))
    l.push(Math.min(op, px) * (1 - r.d(0, 0.01)))
    const vol = r.d(10, 5000)
    v.push(vol)
    tb.push(tb.length % 17 === 5 ? NaN : vol * r.d(0.2, 0.8))
  }
  return new BarSeries({ symbol: 'SYN', interval, t0, open: o, high: h, low: l, close: c, volume: v, takerBuy: tb })
}

// ================================================================== 黄金值

describe('指标黄金值（15 个快照，≤ 1e-9，NaN 位置一致）', () => {
  it('夹具读得到', () => {
    expect(cases.length).toBe(15)
    expect(P.MA).toEqual([7, 25, 99])
  })

  it.each(cases.map((c, i) => [c.name, i] as const))('%s', (_n, ci) => {
    const c = cases[ci]
    P.MA.forEach((n, k) => expectSame(sma(c.close, n), c.line('ma', k), `${c.name} MA${n}`))
    P.EMA.forEach((n, k) => expectSame(ema(c.close, n), c.line('ema', k), `${c.name} EMA${n}`))
    const b = boll(c.close, P.BOLL[0], P.BOLL[1])
    expectSame(b.mid, c.part('boll', 'mid'), `${c.name} BOLL mid`)
    expectSame(b.up, c.part('boll', 'up'), `${c.name} BOLL up`)
    expectSame(b.dn, c.part('boll', 'dn'), `${c.name} BOLL dn`)
    P.VOL.forEach((n, k) => expectSame(sma(c.volume, n), c.line('vol', k), `${c.name} VOL${n}`))
    const m = macd(c.close, P.MACD[0], P.MACD[1], P.MACD[2])
    expectSame(m.dif, c.part('macd', 'dif'), `${c.name} MACD dif`)
    expectSame(m.dea, c.part('macd', 'dea'), `${c.name} MACD dea`)
    expectSame(m.hist, c.part('macd', 'hist'), `${c.name} MACD hist`)
    P.RSI.forEach((n, k) => expectSame(rsi(c.close, n), c.line('rsi', k), `${c.name} RSI${n}`))
    const kd = kdj(c.high, c.low, c.close, P.KDJ[0], P.KDJ[1], P.KDJ[2])
    expectSame(kd.k, c.part('kdj', 'k'), `${c.name} KDJ K`)
    expectSame(kd.d, c.part('kdj', 'd'), `${c.name} KDJ D`)
    expectSame(kd.j, c.part('kdj', 'j'), `${c.name} KDJ J`)
    expectSame(atr(c.high, c.low, c.close, P.ATR[0]), c.atr, `${c.name} ATR`)

    // StochRSI 只有引擎这一条路。
    const e = new IndicatorEngine()
    e.ensure({ series: c.series, wanted: ['SRSI'], params: { SRSI: P.SRSI }, dataKey: 'golden-srsi' })
    expectSame(e.get('SRSI')!.lines[0], c.part('srsi', 'k'), `${c.name} SRSI K`)
    expectSame(e.get('SRSI')!.lines[1], c.part('srsi', 'd'), `${c.name} SRSI D`)

    // 引擎算出来的要和裸函数一模一样——缓存层不许悄悄改数。
    const params: Partial<Record<IndicatorID, number[]>> = {}
    for (const [k, v] of Object.entries(P)) { const id = indicatorFromRaw(k); if (id) params[id] = v }
    const g = new IndicatorEngine()
    g.ensure({ series: c.series, wanted: ['MA', 'EMA', 'BOLL', 'VOL', 'MACD', 'RSI', 'KDJ', 'SRSI', 'ATR'], params, dataKey: 'golden' })
    expectSame(g.get('MA')!.lines[0], c.line('ma', 0), `引擎 ${c.name} MA`)
    expectSame(g.get('EMA')!.lines[1], c.line('ema', 1), `引擎 ${c.name} EMA`)
    expectSame(g.get('BOLL')!.lines[2], c.part('boll', 'dn'), `引擎 ${c.name} BOLL dn`)
    expectSame(g.get('VOL')!.lines[0], c.line('vol', 0), `引擎 ${c.name} VOL`)
    expectSame(g.get('MACD')!.histogram!, c.part('macd', 'hist'), `引擎 ${c.name} MACD hist`)
    expectSame(g.get('RSI')!.lines[2], c.line('rsi', 2), `引擎 ${c.name} RSI`)
    expectSame(g.get('KDJ')!.lines[2], c.part('kdj', 'j'), `引擎 ${c.name} KDJ J`)
    expectSame(g.get('SRSI')!.lines[1], c.part('srsi', 'd'), `引擎 ${c.name} SRSI D`)
    expectSame(g.get('ATR')!.lines[0], c.atr, `引擎 ${c.name} ATR`)
  })

  it('缓存键：键一样就不重算；参数、集合、根数一变就重算', () => {
    const e = new IndicatorEngine()
    const s = cases[0].series
    expect(e.ensure({ series: s, wanted: ['MA'], dataKey: 'k' })).toBe(true)
    expect(e.ensure({ series: s, wanted: ['MA'], dataKey: 'k' })).toBe(false)
    expect(e.ensure({ series: s, wanted: ['MA'], params: { MA: [5] }, dataKey: 'k' })).toBe(true)
    expect(e.ensure({ series: s, wanted: ['MA', 'RSI'], params: { MA: [5] }, dataKey: 'k' })).toBe(true)
    const t = s.clone()
    t.close.pop(); t.open.pop(); t.high.pop(); t.low.pop(); t.volume.pop(); t.takerBuy.pop()
    t.stampAll()
    expect(e.ensure({ series: t, wanted: ['MA', 'RSI'], params: { MA: [5] }, dataKey: 'k' })).toBe(true)
    // 数据键、指标顺序：顺序不算，数据键算。
    expect(e.ensure({ series: t, wanted: ['RSI', 'MA'], params: { MA: [5] }, dataKey: 'k' })).toBe(false)
    expect(e.ensure({ series: t, wanted: ['RSI', 'MA'], params: { MA: [5] }, dataKey: 'k2' })).toBe(true)
  })

  it('空序列：全部指标都在，每条线都空', () => {
    const s = BarSeries.empty('X', '1h')
    const e = new IndicatorEngine()
    e.ensure({ series: s, wanted: ALL_INDICATOR_IDS, dataKey: 'empty' })
    for (const id of ALL_INDICATOR_IDS) for (const line of e.get(id)!.lines) expect(line.length, id).toBe(0)
  })
})

// ================================================================== 边界

describe('指标边界', () => {
  const flat = new Array<number>(60).fill(100)
  const ramp = Array.from({ length: 60 }, (_, i) => i + 1)
  const finite = (a: number[]) => a.filter(Number.isFinite)

  it('数据不够时整列 NaN', () => {
    for (const n of [5, 20, 99]) {
      const short = ramp.slice(0, n - 1)
      expect(finite(sma(short, n))).toEqual([])
      expect(finite(ema(short, n))).toEqual([])
      expect(finite(rma(short, n))).toEqual([])
    }
    expect(sma([], 5)).toEqual([]); expect(ema([], 5)).toEqual([])
  })

  it('前导 NaN 的位置', () => {
    const n = 7
    const s = sma(ramp, n), e = ema(ramp, n)
    expect(s.slice(0, n - 1).filter(Number.isNaN).length).toBe(n - 1)
    expect(Number.isFinite(s[n - 1])).toBe(true)
    expect(e.slice(0, n - 1).filter(Number.isNaN).length).toBe(n - 1)
    expect(e[n - 1]).toBe(ramp.slice(0, n).reduce((a, b) => a + b, 0) / n)
    expect(s.slice(n - 1).filter(Number.isNaN)).toEqual([])
    expect(e.slice(n - 1).filter(Number.isNaN)).toEqual([])
  })

  it('参数非法就整列 NaN，不要崩', () => {
    for (const n of [0, -1, -100]) {
      expect(finite(sma(ramp, n))).toEqual([])
      expect(finite(ema(ramp, n))).toEqual([])
      expect(finite(rma(ramp, n))).toEqual([])
      expect(rsi(ramp, n).length).toBe(ramp.length)
    }
    expect(sma(ramp, 1)).toEqual(ramp)
    expect(ema(ramp, 1)).toEqual(ramp)
  })

  it('横盘时不出 NaN / inf', () => {
    const tail = rsi(flat, 14).slice(20)
    expect(tail.filter(x => !Number.isFinite(x))).toEqual([])
    expect(tail.every(x => x >= 0 && x <= 100)).toBe(true)
    const k = kdj(flat, flat, flat, 9, 3, 3)
    expect(k.k.slice(12).filter(x => !Number.isFinite(x))).toEqual([])
    const b = boll(flat, 20, 2)
    expect(b.up[30]).toBe(b.mid[30]); expect(b.dn[30]).toBe(b.mid[30]); expect(b.mid[30]).toBe(100)
    expect(atr(flat, flat, flat, 14)[30]).toBe(0)
  })

  it('单边行情的 RSI 极值', () => {
    const up = rsi(ramp, 14)
    expect(Math.abs(up[40] - 100)).toBeLessThan(1e-9)
    const down = rsi(ramp.slice().reverse(), 14)
    expect(Math.abs(down[40])).toBeLessThan(1e-9)
    for (const v of up.slice(14)) expect(v >= 0 && v <= 100).toBe(true)
  })

  it('StochRSI 分母为零', () => {
    const s = new BarSeries({ symbol: 'X', interval: '1h', t0: 0, open: flat, high: flat, low: flat, close: flat, volume: new Array(60).fill(1) })
    const e = new IndicatorEngine()
    e.ensure({ series: s, wanted: ['SRSI'], params: { SRSI: [14, 14, 3, 3] }, dataKey: 'flat' })
    const tail = e.get('SRSI')!.lines[0].slice(35)
    expect(tail.length).toBeGreaterThan(0)
    expect(tail.filter(x => !Number.isFinite(x))).toEqual([])
    expect(tail.every(x => x >= 0 && x <= 100)).toBe(true)
  })

  it('J 线允许越界', () => {
    const c = ramp.slice(); c[30] = 1000
    const k = kdj(c.map(x => x + 5), c.map(x => x - 5), c, 9, 3, 3)
    const j = finite(k.j.slice(12))
    expect(j.length).toBeGreaterThan(0)
    expect(j.some(x => x > 100) || j.some(x => x < 0)).toBe(true)
    for (const v of k.k.slice(12)) if (Number.isFinite(v)) expect(v >= -1e-9 && v <= 100 + 1e-9).toBe(true)
  })

  it('smaSkip 跳过前导 NaN', () => {
    const src = [...new Array(5).fill(NaN), ...Array.from({ length: 10 }, (_, i) => i + 1)]
    const out = smaSkip(src, 3)
    expect(out.length).toBe(src.length)
    expect(finite(out.slice(0, 7))).toEqual([])
    expect(Math.abs(out[7] - 2)).toBeLessThan(1e-12)
    expect(finite(smaSkip(new Array(10).fill(NaN), 3))).toEqual([])
  })

  it('MACD 柱是差值的两倍', () => {
    const m = macd(ramp, 12, 26, 9)
    expect(m.dea.length).toBe(ramp.length); expect(m.hist.length).toBe(ramp.length)
    for (let i = 0; i < m.hist.length; i++) if (Number.isFinite(m.hist[i])) {
      expect(Math.abs(m.hist[i] - (m.dif[i] - m.dea[i]) * 2)).toBeLessThan(1e-9)
    }
  })

  it('ATR 算上跳空', () => {
    const h = new Array(40).fill(101), l = new Array(40).fill(99), c = new Array(40).fill(100)
    for (let i = 20; i < 40; i++) { h[i] += 50; l[i] += 50; c[i] += 50 }
    const a = atr(h, l, c, 14)
    expect(a[19]).toBe(2)
    expect(a[20]).toBeGreaterThan(2)
  })

  it('引擎在空数据和换参时不乱', () => {
    const empty = BarSeries.fromBars('X', '1h', [])
    const e = new IndicatorEngine()
    expect(e.ensure({ series: empty, wanted: ALL_INDICATOR_IDS, dataKey: 'k' })).toBe(true)
    expect(e.values.size).toBe(ALL_INDICATOR_IDS.length)
    for (const [id, r] of e.values) {
      expect(r.lines.length, id).toBe(lineNames(id, defaultParams(id)).length)
      expect(r.lines.filter(l => l.length > 0), id).toEqual([])
    }
    e.updateTail({ series: empty, dataKey: 'k' })

    const s = synthSeries(100, 3)
    const e2 = new IndicatorEngine()
    e2.ensure({ series: s, wanted: ['MA'], dataKey: 'k' })
    const a = e2.values.get('MA')!.lines[0].slice()
    expect(e2.ensure({ series: s, wanted: ['MA'], params: { MA: [3, 4, 5] }, dataKey: 'k' })).toBe(true)
    expect(e2.values.get('MA')!.lines[0]).not.toEqual(a)
    expect(e2.values.get('MA')!.lines.length).toBe(3)
  })

  it('Swift 的 min / max 在 NaN 上的语义（SAR、ATR 依赖）', () => {
    expect(swiftMin(1, NaN)).toBe(1)            // NaN < 1 为假 → 取 x
    expect(Number.isNaN(swiftMin(NaN, 1))).toBe(true)
    expect(swiftMax(1, NaN)).toBe(1)
    expect(Number.isNaN(swiftMax(NaN, 1))).toBe(true)
    expect(swiftMin(3, 2, 1)).toBe(1); expect(swiftMax(1, 2, 3)).toBe(3)
  })
})

// ================================================================== 元数据（LayoutTests.IndicatorMetaTests）

describe('指标元数据', () => {
  it.each(ALL_INDICATOR_IDS.map(id => [id]))('%s：主图副图之分和面板清单对得上；参数与线名', id => {
    expect(placement(id) === 'main').toBe(mainPalette.includes(id))
    if (subPalette.includes(id)) expect(placement(id)).toBe('sub')
    expect(indicatorName(id).length).toBeGreaterThan(0)
    const p = defaultParams(id)
    expect(p.length).toBe(paramLabels(id).length)
    expect(p.filter(x => x > 0).length).toBe(p.length)
    const names = lineNames(id, p)
    expect(names.length).toBeGreaterThan(0)
    expect(new Set(names).size).toBe(names.length)
    const tail = tailBars(id, p)
    expect(tail).toBeGreaterThanOrEqual(1)
    if (p.length) expect(tail).toBeGreaterThan(Math.max(...p))
  })

  it('面板清单不重不漏，退役的不在上面', () => {
    expect(new Set(palette).size).toBe(palette.length)
    for (const id of retired) { expect(palette.includes(id)).toBe(false); expect(isRetired(id)).toBe(true) }
    expect(new Set([...palette, ...retired])).toEqual(new Set(ALL_INDICATOR_IDS))
  })

  it('默认参数与原型一致', () => {
    expect(defaultParams('MA')).toEqual([10, 30, 120, 256])
    expect(defaultParams('EMA')).toEqual([12, 144, 169, 200])
    expect(defaultParams('BOLL')).toEqual([20, 2])
    expect(defaultParams('VOL')).toEqual([5, 10, 30, 60, 120])
    expect(defaultParams('MACD')).toEqual([10, 30, 9])
    expect(defaultParams('RSI')).toEqual([6, 12, 24])
    expect(defaultParams('KDJ')).toEqual([9, 3, 3])
    expect(defaultParams('SRSI')).toEqual([14, 14, 3, 3])
    expect(defaultParams('ATR')).toEqual([14])
    expect(defaultOverlays).toEqual(['MA'])
    expect(defaultSubs).toEqual(['MACD', 'RSI'])
  })

  it('0–100 的副图锁刻度与参考线', () => {
    for (const id of ['RSI', 'SRSI'] as const) expect(fixedScale(id)).toEqual({ lo: 0, hi: 100 })
    for (const id of ['KDJ', 'MACD', 'ATR', 'VOL', 'OI'] as const) expect(fixedScale(id)).toBeNull()
    expect(guides('RSI')).toEqual([30, 70])
    expect(guides('KDJ')).toEqual([20, 80])
    expect(guides('SRSI')).toEqual([20, 80])
    for (const id of ['MACD', 'ATR', 'VOL', 'OI', 'MA', 'EMA', 'BOLL'] as const) expect(guides(id)).toEqual([])
  })

  it('回算根数够深', () => {
    expect(tailBars('MACD', [12, 26, 9])).toBeGreaterThanOrEqual(52)
    expect(tailBars('SRSI', [14, 14, 3, 3])).toBeGreaterThanOrEqual(42)
  })

  it('线名跟着参数走', () => {
    expect(lineNames('MA', [5, 10])).toEqual(['均线5', '均线10'])
    expect(lineNames('EMA', [8])).toEqual(['指数均线8'])
    expect(lineNames('VOL', [5, 10])).toEqual(['均量5', '均量10'])
    expect(lineNames('BOLL', [20, 2])).toEqual(['中轨', '上轨', '下轨'])
    expect(lineNames('KDJ', [9, 3, 3])).toEqual(['快线', '慢线', '敏感线'])
  })

  it('参数理一遍：长度不够按默认补齐、多了截掉', () => {
    expect(normalizedParams('SRSI', [10])).toEqual([10, 14, 3, 3])
    expect(normalizedParams('MACD', [8, 21])).toEqual([8, 21, 9])
    expect(normalizedParams('BOLL', [20, 2, 7])).toEqual([20, 2])
    expect(normalizedParams('MA', [5])).toEqual([5])
    expect(normalizedParams('KDJ', null)).toEqual([9, 3, 3])
  })

  it('结果取值越界给 NaN', () => {
    const r = new IndicatorResult([[1, 2, 3], [4, 5, 6]])
    expect(r.values(1)).toEqual([2, 5])
    expect(r.values(99).filter(Number.isNaN).length).toBe(2)
    expect(r.values(-1).filter(Number.isNaN).length).toBe(2)
  })
})

// ================================================================== 持仓量提示（OINoticeTests）

describe('持仓量提示：只说自己知道的，不替币安下断言', () => {
  const all = Object.values(OINotice)
  it('线路不报 / 还没到 / 真没有，三句各归各', () => {
    expect(oiNoticeForEmptyPane(false, false)).toBe(OINotice.routeMissing)
    expect(oiNoticeForEmptyPane(false, true)).toBe(OINotice.routeMissing)
    expect(oiNoticeForEmptyPane(true, false)).toBe(OINotice.loading)
    expect(oiNoticeForEmptyPane(true, true)).toBe(OINotice.empty)
  })
  it('哪个周期都不会被说成「不提供持仓量历史」', () => {
    for (const loaded of [true, false]) {
      const text = oiNoticeForEmptyPane(true, loaded)
      for (const bad of ['不提供', '币安', '这个周期', '30 天']) expect(text.includes(bad)).toBe(false)
    }
  })
  it('唯一一句「不提供」说的是线路', () => {
    expect(all.filter(t => t.includes('不提供'))).toEqual([OINotice.routeMissing])
    expect(OINotice.routeMissing).toBe('当前线路不提供持仓量')
  })
  it('三句都是中文，没有 OI 这类英文缩写；图例也是', () => {
    for (const t of all) { expect(t.includes('OI')).toBe(false); expect(t.includes('持仓量')).toBe(true) }
    expect(indicatorName('OI')).toBe('持仓量')
    expect(lineNames('OI', [])).toEqual(['持仓量'])
  })
})

// ================================================================== 累计周期

describe('累计周期的锚', () => {
  it('utcMonthIndex 与 Date.UTC 逐月一致（含 1970 以前）', () => {
    for (let y = 1950; y <= 2100; y += 7) {
      for (let m = 0; m < 12; m++) {
        const want = y * 12 + m + 1
        for (const ms of [Date.UTC(y, m, 1), Date.UTC(y, m, 1) + 1, Date.UTC(y, m + 1, 1) - 1, Date.UTC(y, m, 15, 13)]) {
          expect(utcMonthIndex(ms), new Date(ms).toISOString()).toBe(want)
        }
      }
    }
  })

  it('日内按 UTC 零点、日线以上按自然月', () => {
    const t = Date.UTC(2025, 0, 31, 22)
    const h = BarSeries.fromBars('X', '1h', [0, 1, 2, 3].map(i => bar(t + i * 3_600_000, 1, 1, 1, 1, 1)))
    expect([0, 1, 2, 3].map(i => startsAnchorPeriod(h, i))).toEqual([true, false, true, false])
    const d0 = Date.UTC(2025, 0, 30)
    const d = BarSeries.fromBars('X', '1d', [0, 1, 2, 3].map(i => bar(d0 + i * 86_400_000, 1, 1, 1, 1, 1)))
    expect([0, 1, 2, 3].map(i => startsAnchorPeriod(d, i))).toEqual([true, false, true, false])
  })
})

// ================================================================== 外部序列刷新缓存（ExternalSeriesTests.cache）

describe('外部指标的缓存', () => {
  it('只改外部序列也刷新缓存；没有当前桶就留空', () => {
    const series = BarSeries.fromBars('TEST', '5m', [bar(300_000, 10, 11, 9, 10, 1), bar(600_000, 10, 11, 9, 10, 1)])
    const e = new IndicatorEngine()
    const input = new ExternalSeries({ t0: 300_000, step: 300_000, columns: [[1]], timestamps: [300_000], bucketInterval: '5m' })
    e.ensure({ series, wanted: ['LSR'], params: {}, external: { LSR: input } })
    expect(e.get('LSR')!.lines[0][0]).toBe(1)
    expect(Number.isNaN(e.get('LSR')!.lines[0][1])).toBe(true)
    // Swift 的 ExternalSeries 改 columns 会自动换戳；TS 这边要调用方自己换（见 engine.ts 头注）。
    input.columns = [[2]]
    input.revision = new ExternalSeries({ t0: 0, step: 1, columns: [] }).revision
    e.ensure({ series, wanted: ['LSR'], params: {}, external: { LSR: input } })
    expect(e.get('LSR')!.lines[0][0]).toBe(2)
  })

  it('没喂到外部数据的外部指标画一列 NaN，列数按 externalColumns', () => {
    const s = synthSeries(30)
    const e = new IndicatorEngine()
    e.ensure({ series: s, wanted: ['OI', 'LSR', 'TAKER', 'BASIS', 'ORDERFLOW'] })
    for (const id of ['OI', 'LSR', 'TAKER', 'BASIS', 'ORDERFLOW'] as const) {
      const r = e.get(id)!
      expect(r.lines.length, id).toBeGreaterThanOrEqual(1)
      for (const l of r.lines) { expect(l.length).toBe(30); expect(l.every(Number.isNaN)).toBe(true) }
    }
    // 追一根：没数据的那几列追长、仍是 NaN。
    s.append(bar(s.time(29) + s.step, 1, 1, 1, 1, 1))
    e.updateTail({ series: s })
    for (const id of ['OI', 'LSR', 'TAKER', 'BASIS', 'ORDERFLOW'] as const) {
      for (const l of e.get(id)!.lines) { expect(l.length).toBe(31); expect(l.every(Number.isNaN)).toBe(true) }
    }
  })
})
