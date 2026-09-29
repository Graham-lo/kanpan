// 手机网页版审查（指标）：参数的脏值。
//
// Swift 那边参数是 [Int]，非整数 / NaN 根本进不来；TS 这边是 number[]，偏好清洗
// （prefs.cleanParams / 面板 clampParam）之外还有同步解码、深链、旧存档几条路能把
// 2.5、NaN 送进引擎。引擎自己得守住 Swift 的语义：按 Int 截断，非有限值按「缺位」处理。
import { describe, expect, it } from 'vitest'
import { BarSeries, bar } from '../src/m/chart/series'
import { IndicatorResult, normalizedParams } from '../src/m/indicator/ids'
import type { IndicatorID } from '../src/m/indicator/ids'
import { IndicatorEngine } from '../src/m/indicator/engine'

function series(count: number): BarSeries {
  const o: number[] = [], h: number[] = [], l: number[] = [], c: number[] = [], v: number[] = []
  let px = 100
  for (let k = 0; k < count; k++) {
    const op = px
    px = Math.max(1, px * (1 + Math.sin(k * 1.7) * 0.02))
    o.push(op); c.push(px)
    h.push(Math.max(op, px) * 1.004); l.push(Math.min(op, px) * 0.996)
    v.push(100 + (k * 37) % 900)
  }
  return new BarSeries({ symbol: 'SYN', interval: '1h', t0: 1_700_000_000_000, open: o, high: h, low: l, close: c, volume: v })
}

function run(id: IndicatorID, params: number[], s: BarSeries): IndicatorResult {
  const e = new IndicatorEngine()
  e.ensure({ series: s, wanted: [id], params: { [id]: params }, dataKey: 'k' })
  return e.get(id)!
}

function same(a: IndicatorResult, b: IndicatorResult, label: string): void {
  expect(a.lines.length, `${label} 线数`).toBe(b.lines.length)
  a.lines.forEach((line, i) => {
    expect(line.length, `${label}[${i}] 长度`).toBe(b.lines[i].length)
    // 只许有数组下标：非整数周期曾经往结果上写出 "1.5" 这种属性。
    expect(Object.keys(line).filter(k => !/^\d+$/.test(k)), `${label}[${i}] 非下标属性`).toEqual([])
    for (let j = 0; j < line.length; j++) expect(Object.is(line[j], b.lines[i][j]), `${label}[${i}][${j}] ${line[j]} vs ${b.lines[i][j]}`).toBe(true)
  })
}

describe('参数脏值：按 Swift Int 截断', () => {
  it('normalizedParams 截断小数、非有限值按缺位', () => {
    expect(normalizedParams('MA', [2.9, -3.5, 7])).toEqual([2, -3, 7])
    expect(normalizedParams('EMA', [NaN, Infinity, 5])).toEqual([0, 0, 5])
    expect(normalizedParams('BOLL', [20.7, NaN])).toEqual([20, 2])
    expect(normalizedParams('MACD', [Infinity, 30.2, 9])).toEqual([10, 30, 9])
  })

  it.each<[IndicatorID, number[], number[]]>([
    ['MA', [2.5, 7.9], [2, 7]],
    ['EMA', [2.5, 12.4], [2, 12]],
    ['VOL', [3.3], [3]],
    ['RSI', [6.6, 12.1], [6, 12]],
    ['BOLL', [20.5, 2.5], [20, 2]],
    ['MACD', [10.5, 30.5, 9.5], [10, 30, 9]],
    ['KDJ', [9.9, 3.1, 3.1], [9, 3, 3]],
    ['ATR', [14.5], [14]],
    ['DMI', [14.5], [14]],
    ['ST', [10.5, 3.5], [10, 3]],
  ])('%s %j 与 %j 逐位相同', (id, dirty, clean) => {
    const s = series(300)
    same(run(id, dirty, s), run(id, clean, s), id)
  })

  it('RSI 带 NaN 参数时尾部增量与全量逐位相同', () => {
    const s = series(200)
    const e = new IndicatorEngine()
    const params = { RSI: [NaN, 6] }
    e.ensure({ series: s, wanted: ['RSI'], params, dataKey: 'k' })
    for (let k = 0; k < 20; k++) {
      const last = s.bar(s.count - 1)
      const c = last.close * (k % 2 ? 1.03 : 0.97)
      s.append(bar(last.openTime + s.step, last.close, Math.max(last.close, c) * 1.001, Math.min(last.close, c) * 0.999, c, 500))
      e.updateTail({ series: s, dataKey: 'k' })
    }
    same(e.get('RSI')!, run('RSI', [NaN, 6], s), 'RSI 增量')
    same(e.get('RSI')!, run('RSI', [0, 6], s), 'RSI NaN≡0')
  })

  it('参数带 NaN 时同一份数据再 ensure 命中缓存', () => {
    const s = series(100)
    const e = new IndicatorEngine()
    const o = { series: s, wanted: ['MA', 'BOLL'] as IndicatorID[], params: { MA: [NaN, 5], BOLL: [NaN, 2] }, dataKey: 'k' }
    expect(e.ensure(o)).toBe(true)
    expect(e.ensure(o)).toBe(false)
  })

  it('IndicatorResult.values 非整数下标给 NaN', () => {
    const r = new IndicatorResult([[1, 2, 3]])
    expect(r.values(1.5)).toEqual([NaN])
    expect(r.values(1)).toEqual([2])
  })
})
