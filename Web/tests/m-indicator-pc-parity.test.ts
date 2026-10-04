// 同一只品种、同一组参数，PC 网页（src/chart/calc.ts）与手机网页引擎（src/m/indicator，已与 iOS KanpanCore 逐位对账，
// 见 m-indicator-xcheck）算出的指标必须一样——三端以 iOS 为准。曾经 PC 的 MACD 柱只有手机的一半（少了 ×2）、
// KDJ 从第 n 根才起步递推，开头几十根 K/D/J 对不上
import { describe, expect, it } from 'vitest'
import { BarSeries } from '../src/m/chart/series'
import { IndicatorEngine } from '../src/m/indicator/engine'
import { Calc, type Bar } from '../src/chart/calc'

function gen(n: number, flatFrom = -1) {
  let s = 12345
  const r = () => { s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648 }
  const o: number[] = [], h: number[] = [], l: number[] = [], c: number[] = [], v: number[] = [], tb: number[] = []
  let px = 100
  for (let k = 0; k < n; k++) {
    const op = px
    const fl = flatFrom >= 0 && k >= flatFrom
    px = fl ? px : px * (1 + (r() - 0.5) * 0.04)
    o.push(op); c.push(px)
    h.push(fl ? px : Math.max(op, px) * (1 + r() * 0.01)); l.push(fl ? px : Math.min(op, px) * (1 - r() * 0.01))
    const vv = 1000 * (0.1 + r()); v.push(vv); tb.push(vv * r())
  }
  return { o, h, l, c, v, tb }
}

/** 两条序列逐根比：空值位置必须一致，有值处相对误差 ≤ 1e-9 */
function diff(a: (number | null)[], b: ArrayLike<number>): string | null {
  if (a.length !== b.length) return `长度 ${a.length} ≠ ${b.length}`
  for (let i = 0; i < a.length; i++) {
    const x = a[i], y = b[i]
    const xn = x == null || !Number.isFinite(x), yn = !Number.isFinite(y)
    if (xn !== yn) return `第 ${i} 根 一边有值一边空：PC=${x} 手机=${y}`
    if (xn) continue
    if (Math.abs((x as number) - y) > 1e-9 * Math.max(1, Math.abs(y))) return `第 ${i} 根 PC=${x} 手机=${y}`
  }
  return null
}

describe('PC 与手机网页（= iOS）指标同口径', () => {
  for (const [tag, d] of [['随机走势', gen(400)], ['后半段一字横盘', gen(400, 200)]] as const) {
    it(tag, () => {
      const t0 = 1_700_000_000_000 - 1_700_000_000_000 % 3_600_000
      const s = new BarSeries({ symbol: 'X', interval: '1h', t0, open: d.o, high: d.h, low: d.l, close: d.c, volume: d.v, takerBuy: d.tb })
      const bars: Bar[] = d.c.map((_, i) => ({ t: t0 + i * 3_600_000, o: d.o[i], h: d.h[i], l: d.l[i], c: d.c[i], v: d.v[i] * d.c[i], bv: d.v[i], tb: d.tb[i] * d.c[i] }))
      const e = new IndicatorEngine()
      const params = { MA: [10, 30], EMA: [12, 26], BOLL: [20, 2], MACD: [12, 26, 9], RSI: [14], KDJ: [9, 3, 3], ST: [10, 3], ATR: [14] }
      e.ensure({ series: s, wanted: ['MA', 'EMA', 'BOLL', 'MACD', 'RSI', 'KDJ', 'ST', 'ATR'], params, dataKey: 'x' })
      const m = (id: string) => { const r = e.get(id as never)!; return [...r.lines, ...(r.histogram ? [r.histogram] : [])] }
      const st = Calc.st(bars, { n: 10, k: 3 })
      const pairs: [string, (number | null)[], ArrayLike<number>][] = [
        ...Calc.ma(bars, { periods: [10, 30] }).map((x, i) => [`MA${i}`, x, m('MA')[i]] as [string, (number | null)[], ArrayLike<number>]),
        ...Calc.ema(bars, { periods: [12, 26] }).map((x, i) => [`EMA${i}`, x, m('EMA')[i]] as [string, (number | null)[], ArrayLike<number>]),
        ...Calc.boll(bars, { n: 20, k: 2 }).map((x, i) => [`BOLL${i}`, x, m('BOLL')[i]] as [string, (number | null)[], ArrayLike<number>]),
        ...Calc.macd(bars, { fast: 12, slow: 26, signal: 9 }).map((x, i) => [['DIF', 'DEA', '柱'][i], x, m('MACD')[i]] as [string, (number | null)[], ArrayLike<number>]),
        ['RSI', Calc.rsi(bars, { n: 14 })[0], m('RSI')[0]],
        ...Calc.kdj(bars, { n: 9, m1: 3, m2: 3 }).map((x, i) => [['K', 'D', 'J'][i], x, m('KDJ')[i]] as [string, (number | null)[], ArrayLike<number>]),
        ['超级趋势', st[0].map((x, i) => x ?? st[1][i]), m('ST')[0]],
        ['ATR', Calc.atr(bars, { n: 14 })[0], m('ATR')[0]],
      ]
      const bad = pairs.map(([name, a, b]) => { const r = diff(a, b); return r && `${name}: ${r}` }).filter(Boolean)
      expect(bad).toEqual([])
    })
  }
})
