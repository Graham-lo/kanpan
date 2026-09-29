// 移植自 KanpanCore/Tests/KanpanCoreTests/IndicatorIncrementalTests.swift（含 OIAlignedTailTests、
// IndicatorEnsureInvalidationTests）+ IndicatorPerformanceTests.swift
//
// 增量重算必须和全量重算**逐位**一样（容差 0，NaN 位置一致），不是「差不多」。
import { describe, expect, it } from 'vitest'
import { BarSeries, ExternalSeries, bar } from '../src/m/chart/series'
import type { Bar, Interval } from '../src/m/chart/series'
import { defaultParams, normalizedParams, tailBars } from '../src/m/indicator/ids'
import type { IndicatorID, IndicatorResult } from '../src/m/indicator/ids'
import { IndicatorEngine } from '../src/m/indicator/engine'
import type { IndicatorParams } from '../src/m/indicator/engine'

// ------------------------------------------------------------------ 辅助（同 m-indicator.test.ts）

function expectSame(got: readonly number[], want: readonly number[], label: string, tol = 1e-9): void {
  expect(got.length, `${label} 长度`).toBe(want.length)
  let bad = 0, first = ''
  for (let i = 0; i < got.length; i++) {
    const ok = Number.isNaN(want[i]) ? Number.isNaN(got[i]) : Number.isFinite(got[i]) && Math.abs(got[i] - want[i]) <= tol
    if (!ok) { bad++; if (!first) first = `[${i}] want ${want[i]} got ${got[i]}` }
  }
  expect(bad, `${label}：${bad} 点不符，首个 ${first}`).toBe(0)
}

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

const B = (openTime: number, open: number, high: number, low: number, close: number, volume: number, takerBuy = NaN): Bar =>
  bar(openTime, open, high, low, close, volume, takerBuy)

// ================================================================== 指标增量重算

/** 只吃 K 线的那几把全在这儿——外部数据那四把另有专门的用例。 */
const ALL: IndicatorID[] = ['MA', 'EMA', 'BOLL', 'VWAP', 'ST', 'SAR', 'VOL', 'MACD', 'RSI', 'KDJ', 'SRSI', 'ATR', 'DMI', 'CVD']

const taker = (volume: number, r: Rng, skip: boolean): number => (skip ? NaN : volume * r.d(0.2, 0.8))

function full(s: BarSeries): ReadonlyMap<IndicatorID, IndicatorResult> {
  const e = new IndicatorEngine()
  e.ensure({ series: s, wanted: ALL, dataKey: 'full' })
  return e.values
}

function compare(got: ReadonlyMap<IndicatorID, IndicatorResult>, want: ReadonlyMap<IndicatorID, IndicatorResult>, label: string, ids = ALL): void {
  for (const id of ids) {
    const g = got.get(id)!, w = want.get(id)!
    expect(g.lines.length, `${label} ${id} 线数`).toBe(w.lines.length)
    g.lines.forEach((line, i) => expectSame(line, w.lines[i], `${label} ${id}[${i}]`, 0))
    if (w.histogram) expectSame(g.histogram ?? [], w.histogram, `${label} ${id} hist`, 0)
    // 方向那一列也要逐位对上：超级趋势 / 抛物线转向的颜色与点位。
    if (w.dir) expectSame(g.dir ?? [], w.dir, `${label} ${id} dir`, 0)
  }
}

describe('指标增量重算', () => {
  it.each([0, 1, 2, 3])('随机改末根 / 追加新根 250 次 × 4 条链路（第 %i 条）', lane => {
    const r = new Rng(20260914 + lane)
    const s = synthSeries(320, 101 + lane)
    const e = new IndicatorEngine()
    e.ensure({ series: s, wanted: ALL, dataKey: 'inc' })
    compare(e.values, full(s), `lane${lane} 初始`)

    for (let step = 0; step < 250; step++) {
      const last = s.bar(s.count - 1)
      if (r.d() < 0.5) {
        const c = Math.max(1, last.close * (1 + r.d(-0.01, 0.01)))
        const high = Math.max(Math.max(last.open, c), last.high * (1 + r.d(0, 0.004)))
        const low = Math.min(Math.min(last.open, c), last.low * (1 - r.d(0, 0.004)))
        const volume = last.volume + r.d(0, 40)
        s.replaceLast(B(last.openTime, last.open, high, low, c, volume, taker(last.volume, r, step % 7 === 3)))
      } else {
        const o = last.close
        const c = Math.max(1, o * (1 + r.d(-0.02, 0.02)))
        const high = Math.max(o, c) * (1 + r.d(0, 0.008)), low = Math.min(o, c) * (1 - r.d(0, 0.008))
        const volume = r.d(10, 5000)
        s.append(B(last.openTime + s.step, o, high, low, c, volume, taker(last.volume, r, step % 7 === 5)))
      }
      e.updateTail({ series: s, dataKey: 'inc' })
      if (step % 25 === 0 || step === 249) compare(e.values, full(s), `lane${lane} 第 ${step} 步`)
    }
    compare(e.values, full(s), `lane${lane} 收尾`)
  })

  it('连续追加 500 根不漂移', () => {
    const r = new Rng(4242)
    const s = synthSeries(200, 9)
    const e = new IndicatorEngine()
    e.ensure({ series: s, wanted: ALL, dataKey: 'drift' })
    for (let k = 0; k < 500; k++) {
      const last = s.bar(s.count - 1)
      const o = last.close
      const c = Math.max(1, o * (1 + r.d(-0.03, 0.03)))
      const volume = r.d(1, 999)
      const tb = r.d(0, 1) < 0.1 ? NaN : r.d(0, 999)
      s.append(B(last.openTime + s.step, o, Math.max(o, c) * 1.001, Math.min(o, c) * 0.999, c, volume, tb))
      e.updateTail({ series: s, dataKey: 'drift' })
    }
    compare(e.values, full(s), '追 500 根')
  })

  it.each([1, 2, 5, 13, 27])('短序列 n=%i：改末根后一路追到所有线都出过值', n => {
    const r = new Rng(6000 + n)
    const s = synthSeries(n, n)
    const e = new IndicatorEngine()
    e.ensure({ series: s, wanted: ALL, dataKey: 'short' })
    compare(e.values, full(s), `n=${n} 初始`)
    const last = s.bar(s.count - 1)
    s.replaceLast(B(last.openTime, last.open, last.high * 1.01, last.low * 0.99, last.close * 1.005, last.volume + 1))
    e.updateTail({ series: s, dataKey: 'short' })
    compare(e.values, full(s), `n=${n} 改末根`)
    for (let step = 0; step < 64 - n; step++) {
      const prev = s.bar(s.count - 1)
      const o = prev.close
      const c = Math.max(1, o * (1 + r.d(-0.02, 0.02)))
      const high = Math.max(o, c) * (1 + r.d(0, 0.006)), low = Math.min(o, c) * (1 - r.d(0, 0.006))
      s.append(B(prev.openTime + s.step, o, high, low, c, r.d(10, 5000)))
      e.updateTail({ series: s, dataKey: 'short' })
      compare(e.values, full(s), `n=${n} 追到第 ${s.count} 根（第 ${step} 步）`)
    }
  })

  // ------------------------------------------------------------ A4：可变的第 0 根

  const flatBar = (t: number, close: number): Bar => B(t, close, close, close, close, 100)

  it('唯一一根改掉之后再长：MA(1) 立刻跟上，MA(5) 首次出值仍等于全量', () => {
    const s = BarSeries.fromBars('A4', '1h', [flatBar(0, 100)])
    const params: IndicatorParams = { MA: [1, 5] }
    const e = new IndicatorEngine()
    e.ensure({ series: s, wanted: ['MA'], params, dataKey: 'a4' })
    s.replaceLast(flatBar(0, 110))
    e.updateTail({ series: s, dataKey: 'a4' })
    expect(e.values.get('MA')!.lines[0][0]).toBe(110)
    for (let i = 1; i <= 4; i++) {
      s.append(flatBar(i * s.step, 100))
      e.updateTail({ series: s, dataKey: 'a4' })
    }
    expect(e.values.get('MA')!.lines[1][4]).toBe(102) // (110 + 100 × 4) / 5
    const fresh = new IndicatorEngine()
    fresh.ensure({ series: s, wanted: ['MA'], params, dataKey: 'a4-full' })
    e.values.get('MA')!.lines.forEach((l, i) => expectSame(l, fresh.values.get('MA')!.lines[i], `MA[${i}]`, 0))
  })

  it('唯一一根的振幅改掉之后，ATR 首次出值仍等于全量', () => {
    const s = BarSeries.fromBars('A4ATR', '1h', [B(0, 100, 110, 90, 100, 1)])
    const params: IndicatorParams = { ATR: [2] }
    const e = new IndicatorEngine()
    e.ensure({ series: s, wanted: ['ATR'], params, dataKey: 'a4atr' })
    s.replaceLast(B(0, 100, 130, 90, 100, 1)) // tr[0] 20 → 40
    e.updateTail({ series: s, dataKey: 'a4atr' })
    s.append(B(s.step, 100, 105, 95, 100, 1)) // tr[1] = 10
    e.updateTail({ series: s, dataKey: 'a4atr' })
    expect(e.values.get('ATR')!.lines[0][1]).toBe(25)
    const fresh = new IndicatorEngine()
    fresh.ensure({ series: s, wanted: ['ATR'], params, dataKey: 'a4atr-full' })
    expectSame(e.values.get('ATR')!.lines[0], fresh.values.get('ATR')!.lines[0], 'ATR', 0)
  })

  it('参数是 0 / 负数时，起点 0 也不能越界', () => {
    const s = BarSeries.fromBars('A4BAD', '1h', [flatBar(0, 100)])
    const params: IndicatorParams = {
      MA: [0], EMA: [0], VOL: [-1], RSI: [0], ATR: [0], BOLL: [0, 2], MACD: [0, 0, 0], KDJ: [0, 0, 0], SRSI: [0, 0, 0, 0],
    }
    const e = new IndicatorEngine()
    e.ensure({ series: s, wanted: ALL, params, dataKey: 'bad' })
    s.replaceLast(flatBar(0, 110))
    e.updateTail({ series: s, dataKey: 'bad' })
    for (let i = 1; i <= 3; i++) {
      s.append(flatBar(i * s.step, 100))
      e.updateTail({ series: s, dataKey: 'bad' })
    }
    const fresh = new IndicatorEngine()
    fresh.ensure({ series: s, wanted: ALL, params, dataKey: 'bad-full' })
    for (const id of ALL) e.values.get(id)!.lines.forEach((l, i) => expectSame(l, fresh.values.get(id)!.lines[i], `脏参数 ${id}[${i}]`, 0))
  })

  it('参数长度不够时按默认值补齐，不越界', () => {
    const s = synthSeries(120, 4242)
    const fixed: IndicatorID[] = ['BOLL', 'MACD', 'KDJ', 'SRSI', 'ATR', 'ST', 'DMI']
    const short = new IndicatorEngine()
    short.ensure({ series: s, wanted: fixed, params: Object.fromEntries(fixed.map(id => [id, []])), dataKey: 'short' })
    const partial = new IndicatorEngine()
    partial.ensure({ series: s, wanted: ['SRSI', 'MACD'], params: { SRSI: [10], MACD: [8, 21] }, dataKey: 'partial' })
    const whole = new IndicatorEngine()
    whole.ensure({ series: s, wanted: fixed, dataKey: 'full' })
    for (const id of fixed) short.values.get(id)!.lines.forEach((l, i) => expectSame(l, whole.values.get(id)!.lines[i], `空参数 ${id}[${i}]`, 0))
    expect(normalizedParams('SRSI', [10])).toEqual([10, 14, 3, 3])
    expect(partial.values.get('SRSI')!.lines.length).toBeGreaterThan(0)
    expect(partial.values.get('MACD')!.lines.length).toBeGreaterThan(0)
  })

  it.each([0, 1])('从一根长到一百多根，每一步都等于全量（第 %i 条）', lane => {
    const r = new Rng(20260919 + lane)
    const s = synthSeries(1, 301 + lane)
    const e = new IndicatorEngine()
    e.ensure({ series: s, wanted: ALL, dataKey: 'grow' })
    const first = s.bar(0)
    s.replaceLast(B(first.openTime, first.open, first.high * 1.08, first.low * 0.92, first.close * 1.1, first.volume + 7))
    e.updateTail({ series: s, dataKey: 'grow' })
    compare(e.values, full(s), `lane${lane} n=1 改末根`)
    for (let step = 0; step < 130; step++) {
      const last = s.bar(s.count - 1)
      const o = last.close
      const c = Math.max(1, o * (1 + r.d(-0.02, 0.02)))
      const high = Math.max(o, c) * (1 + r.d(0, 0.008)), low = Math.min(o, c) * (1 - r.d(0, 0.008))
      s.append(B(last.openTime + s.step, o, high, low, c, r.d(10, 5000)))
      e.updateTail({ series: s, dataKey: 'grow' })
      if (r.d() < 0.5) {
        const cur = s.bar(s.count - 1)
        const c2 = Math.max(1, cur.close * (1 + r.d(-0.01, 0.01)))
        const volume = cur.volume + r.d(0, 30)
        s.replaceLast(B(cur.openTime, cur.open, Math.max(Math.max(cur.open, c2), cur.high), Math.min(Math.min(cur.open, c2), cur.low), c2, volume))
        e.updateTail({ series: s, dataKey: 'grow' })
      }
      compare(e.values, full(s), `lane${lane} 第 ${step} 步（${s.count} 根）`)
    }
  })

  it('日线跨月：VWAP / CVD 按自然月归零，增量与全量一致', () => {
    const r = new Rng(9)
    const s = synthSeries(40, 5, '1d', Date.UTC(2024, 0, 1))
    const e = new IndicatorEngine()
    e.ensure({ series: s, wanted: ALL, dataKey: 'day' })
    for (let k = 0; k < 90; k++) {
      const last = s.bar(s.count - 1)
      const o = last.close, c = Math.max(1, o * (1 + r.d(-0.03, 0.03)))
      s.append(B(last.openTime + s.step, o, Math.max(o, c) * 1.01, Math.min(o, c) * 0.99, c, r.d(10, 999), r.d(0, 1) < 0.2 ? NaN : r.d(0, 999)))
      e.updateTail({ series: s, dataKey: 'day' })
    }
    compare(e.values, full(s), '日线 130 根')
    // 2 月 1 日那根重新从典型价起算。
    const feb = (Date.UTC(2024, 1, 1) - Date.UTC(2024, 0, 1)) / 86_400_000
    const b = s.bar(feb)
    expect(e.get('VWAP')!.lines[0][feb]).toBeCloseTo((b.high + b.low + b.close) / 3, 9)
  })
})

// ================================================================== 持仓量（外部序列）增量对齐

/** kind：0 稠密、1 稀疏不限桶、2 稀疏限桶（1h）、3 稀疏限桶（1m，5 分钟窗）。 */
function makeOI(kind: number, t0: number, step: number, n: number, seed: number): ExternalSeries {
  const r = new Rng(seed)
  if (kind === 0) {
    const values = Array.from({ length: n }, () => r.d(1000, 9000))
    return new ExternalSeries({ t0, step, columns: [values] })
  }
  const pts: { time: number; values: number[] }[] = []
  let t = t0 - step
  for (let k = 0; k < n; k++) {
    t += step * r.i(1, 3)
    pts.push({ time: t, values: [r.d(1000, 9000)] })
  }
  const bucket: Interval | null = kind === 2 ? '1h' : kind === 3 ? '1m' : null
  return ExternalSeries.fromPoints(pts, step, bucket)
}

describe('持仓量增量对齐', () => {
  it.each([0, 1, 2, 3])('随机 300 轮：尾部对齐 == 整列对齐（kind %i）', kind => {
    const r = new Rng(20260917 + kind)
    const s = synthSeries(260, 31 + kind)
    const oi = makeOI(kind, s.t0, s.step, 300, 77 + kind)
    let prev = oi.aligned(s)
    for (let round = 0; round < 300; round++) {
      const last = s.bar(s.count - 1)
      if (r.d() < 0.5) {
        const c = Math.max(1, last.close * (1 + r.d(-0.01, 0.01)))
        s.replaceLast(B(last.openTime, last.open, Math.max(last.high, c), Math.min(last.low, c), c, last.volume + r.d(0, 40)))
      } else {
        const o = last.close, c = Math.max(1, o * (1 + r.d(-0.02, 0.02)))
        s.append(B(last.openTime + s.step, o, Math.max(o, c), Math.min(o, c), c, r.d(10, 5000)))
      }
      const start = Math.max(0, s.count - tailBars('OI', defaultParams('OI')))
      prev = oi.alignedFrom(s, start, prev)
      if (round % 10 === 0 || round === 299) expectSame(prev[0], oi.aligned(s)[0], `kind${kind} 第 ${round} 轮`, 0)
    }
  })

  it.each([1, 2, 3])('任意起点的尾部对齐都等于整列（kind %i）', kind => {
    const r = new Rng(4096 + kind)
    const s = synthSeries(180, 5 + kind)
    const oi = makeOI(kind, s.t0, s.step, 200, 11 + kind)
    const want = oi.aligned(s)
    for (let k = 0; k < 60; k++) {
      const start = r.i(0, s.count)
      const seeded = want.map(c => c.slice())
      for (let i = start; i < s.count; i++) seeded[0][i] = -12345
      expectSame(oi.alignedFrom(s, start, seeded)[0], want[0], `kind${kind} start=${start}`, 0)
    }
  })

  it('引擎里的 OI 增量与全量一致', () => {
    const r = new Rng(20260101)
    const s = synthSeries(240, 3)
    const oi = makeOI(1, s.t0, s.step, 280, 19)
    const ids: IndicatorID[] = ['OI', 'MA', 'RSI', 'ATR']
    const e = new IndicatorEngine()
    e.ensure({ series: s, wanted: ids, oi, dataKey: 'oi' })
    for (let round = 0; round < 200; round++) {
      const last = s.bar(s.count - 1)
      if (r.d() < 0.5) {
        const c = Math.max(1, last.close * (1 + r.d(-0.01, 0.01)))
        s.replaceLast(B(last.openTime, last.open, Math.max(last.high, c), Math.min(last.low, c), c, last.volume + 1))
      } else {
        const o = last.close, c = Math.max(1, o * (1 + r.d(-0.02, 0.02)))
        s.append(B(last.openTime + s.step, o, Math.max(o, c), Math.min(o, c), c, r.d(10, 5000)))
      }
      e.updateTail({ series: s, oi, dataKey: 'oi' })
      if (round % 20 === 0 || round === 199) {
        const fresh = new IndicatorEngine()
        fresh.ensure({ series: s, wanted: ids, oi, dataKey: 'oi' })
        for (const id of ids) e.values.get(id)!.lines.forEach((l, i) => expectSame(l, fresh.values.get(id)!.lines[i], `第 ${round} 轮 ${id}[${i}]`, 0))
      }
    }
  })

  it('换一份持仓量就得重算', () => {
    const s = synthSeries(120, 8)
    const a = makeOI(0, s.t0, s.step, 140, 21)
    const b = makeOI(0, s.t0, s.step, 140, 22)
    const e = new IndicatorEngine()
    e.ensure({ series: s, wanted: ['OI'], oi: a, dataKey: 'swap' })
    const first = e.values.get('OI')!.lines[0].slice()
    e.updateTail({ series: s, oi: b, dataKey: 'swap' })
    expectSame(e.values.get('OI')!.lines[0], b.aligned(s)[0], '换了之后', 0)
    expect(first).not.toEqual(e.values.get('OI')!.lines[0])
    // 缓存键里有外部序列的戳：换一份再 ensure 也会重算（而不是短路）。
    expect(e.ensure({ series: s, wanted: ['OI'], oi: a, dataKey: 'swap' })).toBe(true)
    expectSame(e.values.get('OI')!.lines[0], a.aligned(s)[0], '换回来', 0)
    // 撤掉外部数据：整列 NaN。
    e.updateTail({ series: s, oi: null, dataKey: 'swap' })
    expect(e.values.get('OI')!.lines[0].every(Number.isNaN)).toBe(true)
  })
})

// ================================================================== 按需失效

describe('指标按需失效', () => {
  const IDS: IndicatorID[] = ['MA', 'EMA', 'BOLL', 'MACD', 'RSI', 'KDJ', 'SRSI', 'ATR', 'VOL']

  const fullOf = (s: BarSeries, ids: IndicatorID[], p: IndicatorParams) => {
    const e = new IndicatorEngine()
    e.ensure({ series: s, wanted: ids, params: p, dataKey: 'k' })
    return e.values
  }

  function same(got: ReadonlyMap<IndicatorID, IndicatorResult>, want: ReadonlyMap<IndicatorID, IndicatorResult>, label: string): void {
    for (const [id, w] of want) {
      const g = got.get(id)
      expect(g, `${label} 少了 ${id}`).toBeDefined()
      if (!g) continue
      expect(g.lines.length).toBe(w.lines.length)
      w.lines.forEach((l, i) => expectSame(g.lines[i], l, `${label} ${id}[${i}]`, 0))
      if (w.histogram) expectSame(g.histogram ?? [], w.histogram, `${label} ${id} hist`, 0)
    }
    expect(new Set(got.keys())).toEqual(new Set(want.keys()))
  }

  it.each([0, 1])('随机改参数与增删指标 200 轮（第 %i 条）', lane => {
    const r = new Rng(777 + lane)
    const s = synthSeries(300, 41 + lane)
    const p: Partial<Record<IndicatorID, number[]>> = {}
    const wanted = IDS.slice()
    const e = new IndicatorEngine()
    e.ensure({ series: s, wanted, params: p, dataKey: 'k' })
    same(e.values, fullOf(s, wanted, p), `lane${lane} 初始`)
    for (let round = 0; round < 200; round++) {
      switch (r.i(0, 2)) {
        case 0: {
          const id = IDS[r.i(0, IDS.length - 1)]
          const q = (p[id] ?? defaultParams(id)).slice()
          if (q.length) { const at = r.i(0, q.length - 1); q[at] = r.i(2, 40) }
          p[id] = q
          break
        }
        case 1:
          if (wanted.length > 1) wanted.splice(r.i(0, wanted.length - 1), 1)
          break
        default: {
          const id = IDS[r.i(0, IDS.length - 1)]
          if (!wanted.includes(id)) wanted.push(id)
        }
      }
      e.ensure({ series: s, wanted, params: { ...p }, dataKey: 'k' })
      same(e.values, fullOf(s, wanted, p), `lane${lane} 第 ${round} 轮`)
    }
  })

  it('数据变了就不许留用老状态', () => {
    const s = synthSeries(200, 12)
    const e = new IndicatorEngine()
    e.ensure({ series: s, wanted: ['MA', 'RSI'], dataKey: 'd' })
    s.close[100] *= 1.5
    s.high[100] *= 1.5
    s.stampAll() // Swift 的列有 didSet 自动换戳；TS 直接改列后要手动换
    e.ensure({ series: s, wanted: ['MA', 'RSI'], params: { MA: [5, 10, 20] }, dataKey: 'd' })
    same(e.values, fullOf(s, ['MA', 'RSI'], { MA: [5, 10, 20] }), '戳过之后')
  })

  it('没换参数的指标原样留用（同一个结果对象），换了参数的重建', () => {
    const s = synthSeries(200, 13)
    const e = new IndicatorEngine()
    e.ensure({ series: s, wanted: ['MA', 'MACD'], dataKey: 'keep' })
    const macd = e.get('MACD'), ma = e.get('MA')
    e.ensure({ series: s, wanted: ['MA', 'MACD'], params: { MA: [5] }, dataKey: 'keep' })
    expect(e.get('MACD')).toBe(macd)
    expect(e.get('MA')).not.toBe(ma)
  })
})

// ================================================================== 长序列（IndicatorPerformanceTests，轻量版）

describe('长序列尾部更新', () => {
  it('12000 根：尾部更新与全量一致（≤ 1e-7），且明显比全量快', () => {
    const bars = Array.from({ length: 12_000 }, (_, i) => {
      const close = 100 + Math.sin(i / 19) * 10 + i / 100
      return B(i * 60_000, close - 0.2, close + 1, close - 1, close, 100 + (i % 50))
    })
    const s = BarSeries.fromBars('BTCUSDT', '1m', bars)
    const ids: IndicatorID[] = ['MA', 'EMA', 'VOL', 'OI', 'MACD', 'KDJ', 'RSI']
    const tail = new IndicatorEngine()
    tail.ensure({ series: s, wanted: ids })
    let tailMs = 0, fullMs = 0
    for (let i = 0; i < 20; i++) {
      const last = s.count - 1
      s.close[last] = bars[last].close + (i % 10) / 100
      s.volume[last] += 1
      s.stampAll()
      let t = performance.now()
      tail.updateTail({ series: s })
      tailMs += performance.now() - t
      t = performance.now()
      const f = new IndicatorEngine()
      f.ensure({ series: s, wanted: ids })
      fullMs += performance.now() - t
      if (i % 5 === 0 || i === 19) {
        for (const id of ids) {
          const a = tail.get(id)!, b = f.get(id)!
          ;[...a.lines, a.histogram ?? []].forEach((x, k) => expectSame(x, [...b.lines, b.histogram ?? []][k], `${id}[${k}]`, 1e-7))
        }
      }
    }
    expect(tailMs).toBeLessThan(fullMs)
  })
})
