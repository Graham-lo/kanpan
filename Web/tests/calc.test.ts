import { describe, expect, it } from 'vitest'
import { CATALOG, Calc, MAX_SUBS, ema, paramText, rma, sma } from '../src/chart/calc'
import type { Bar } from '../src/chart/calc'

const closeBars = (cs: number[]): Bar[] => cs.map((c, i) => ({ t: i * 36e5, o: c, h: c, l: c, c, v: 1 }))
const near = (a: number | null, b: number) => { expect(a).not.toBeNull(); expect(a as number).toBeCloseTo(b, 9) }

describe('sma / ema / rma', () => {
  it('sma：前 n-1 根为 null，之后是滑动均值', () => {
    expect(sma([1, 2, 3, 4, 5], 3)).toEqual([null, null, 2, 3, 4])
  })
  it('ema：前 n 根的 SMA 做种子，之后 k = 2/(n+1)', () => {
    const e = ema([2, 4, 6, 8, 20], 3) // k = 0.5
    expect(e.slice(0, 2)).toEqual([null, null])
    near(e[2], 4)          // (2+4+6)/3
    near(e[3], 8 * 0.5 + 4 * 0.5)
    near(e[4], 20 * 0.5 + 6 * 0.5)
  })
  it('ema：跳过开头的 null，从第一个满 n 根的非空值起算', () => {
    // k = 2/3。原型规则：第一次遇到非空值且 i ≥ n-1，就用 [i-n+1, i] 的和 / n 做种子；
    // 窗口里混进的 null 按 0 计（原型行为，照搬不改）
    const e = ema([null, null, 3, 5, 7, 9], 2)
    near(e[2], (0 + 3) / 2)
    near(e[3], 5 * 2 / 3 + 1.5 / 3)
  })
  it('rma：前 n 个的均值做种子，之后 (r(n-1)+x)/n', () => {
    const r = rma([1, 2, 3, 4, 5], 3)
    expect(r.slice(0, 2)).toEqual([null, null])
    near(r[2], 2)
    near(r[3], 8 / 3)
    near(r[4], 31 / 9)
  })
})

describe('Calc', () => {
  it('ma / ema 按 periods 各出一条', () => {
    const bars = closeBars([1, 2, 3, 4, 5])
    const ma = Calc.ma(bars, { periods: [2, 3] })
    expect(ma).toHaveLength(2)
    expect(ma[0]).toEqual([null, 1.5, 2.5, 3.5, 4.5])
    expect(ma[1]).toEqual([null, null, 2, 3, 4])
    expect(Calc.ema(bars, { periods: [3] })[0]).toEqual([null, null, 2, 3, 4])
  })

  it('boll：中轨 = sma，上下轨 = 中轨 ± k·总体标准差', () => {
    const bars = closeBars([1, 2, 3, 4, 5])
    const [mid, up, dn] = Calc.boll(bars, { n: 3, k: 2 })
    expect(mid).toEqual(sma([1, 2, 3, 4, 5], 3))
    expect(up.slice(0, 2)).toEqual([null, null])
    expect(dn.slice(0, 2)).toEqual([null, null])
    const sd = Math.sqrt(2 / 3)
    near(up[2], 2 + 2 * sd); near(dn[2], 2 - 2 * sd)
    near(up[4], 4 + 2 * sd); near(dn[4], 4 - 2 * sd)
  })

  it('macd：DIF = EMA快 − EMA慢；DEA 从 DIF 第一个有效值起算 EMA；柱 = (DIF − DEA) × 2（与手机 / iOS 同口径）', () => {
    const bars = closeBars([1, 2, 4, 8, 16, 32])
    const [dif, dea, hist] = Calc.macd(bars, { fast: 2, slow: 3, signal: 2 })
    expect(dif.slice(0, 2)).toEqual([null, null])
    near(dif[2], 5 / 6)   // EMA2 = 19/6，EMA3 = 7/3
    near(dif[3], 11 / 9)  // EMA2 = 115/18，EMA3 = 31/6
    // DEA：DIF 从下标 2 开始有效，signal = 2 → 下标 3 才有第一个值（两根 DIF 的均值）
    expect(dea.slice(0, 3)).toEqual([null, null, null])
    near(dea[3], 37 / 36)
    near(dea[4], (dif[4] as number) * 2 / 3 + (37 / 36) / 3)
    expect(hist.slice(0, 3)).toEqual([null, null, null])
    for (let i = 3; i < 6; i++) near(hist[i], ((dif[i] as number) - (dea[i] as number)) * 2)
  })

  it('macd 默认参数：前 slow-1 根 DIF 为 null，DEA 再晚 signal-1 根', () => {
    const cs = Array.from({ length: 60 }, (_, i) => 100 + Math.sin(i / 3) * 5 + i * 0.2)
    const [dif, dea] = Calc.macd(closeBars(cs), { fast: 12, slow: 26, signal: 9 })
    expect(dif.findIndex(v => v != null)).toBe(25)
    expect(dea.findIndex(v => v != null)).toBe(25 + 8)
  })

  it('rsi：全涨 = 100，全跌 = 0，前 n-1 根为 null', () => {
    const upR = Calc.rsi(closeBars([1, 2, 3, 4, 5, 6]), { n: 3 })[0]
    expect(upR.slice(0, 2)).toEqual([null, null])
    expect(upR.slice(2)).toEqual([100, 100, 100, 100])
    const dnR = Calc.rsi(closeBars([6, 5, 4, 3, 2, 1]), { n: 3 })[0]
    expect(dnR.slice(0, 2)).toEqual([null, null])
    expect(dnR.slice(2)).toEqual([0, 0, 0, 0])
  })

  it('rsi：已知序列的值（Wilder 平滑）', () => {
    // up = [0,1,0,2,0]，dn = [0,0,1,0,1]，n = 2
    const r = Calc.rsi(closeBars([10, 11, 10, 12, 11]), { n: 2 })[0]
    expect(r[0]).toBeNull()
    expect(r[1]).toBe(100)            // ru 0.5，rd 0
    near(r[2], 100 - 100 / (1 + 0.25 / 0.5))
    near(r[3], 100 - 100 / (1 + 1.125 / 0.25))
    near(r[4], 100 - 100 / (1 + 0.5625 / 0.625))
  })

  it('kdj：K、D 从 50 起步、从第一根就递推（窗口不满按已有的算），前 n-1 根为 null（与手机 / iOS 同口径）', () => {
    const bars: Bar[] = [
      { t: 0, o: 9, h: 10, l: 8, c: 9, v: 1 },
      { t: 1, o: 10, h: 11, l: 9, c: 10, v: 1 },
      { t: 2, o: 11, h: 12, l: 10, c: 12, v: 1 },
    ]
    const [K, D, J] = Calc.kdj(bars, { n: 3, m1: 3, m2: 3 })
    expect(K.slice(0, 2)).toEqual([null, null]); expect(D.slice(0, 2)).toEqual([null, null]); expect(J.slice(0, 2)).toEqual([null, null])
    // 第 0 根 RSV = (9-8)/(10-8)·100 = 50；第 1 根 (10-8)/(11-8)·100；第 2 根 (12-8)/(12-8)·100 = 100
    let k = (50 * 2 + 50) / 3, d = (50 * 2 + k) / 3
    k = (k * 2 + 200 / 3) / 3; d = (d * 2 + k) / 3
    k = (k * 2 + 100) / 3; d = (d * 2 + k) / 3
    near(K[2], k); near(D[2], d); near(J[2], 3 * k - 2 * d)
  })

  it('kdj：高低相同时 RSV 取 50，K=D=J=50', () => {
    const [K, D, J] = Calc.kdj(closeBars([5, 5, 5, 5]), { n: 2, m1: 3, m2: 3 })
    expect(K).toEqual([null, 50, 50, 50]); expect(D).toEqual([null, 50, 50, 50]); expect(J).toEqual([null, 50, 50, 50])
  })

  it('oi：原样取 bar.oi，没有就是 null', () => {
    const bars: Bar[] = [{ t: 0, o: 1, h: 1, l: 1, c: 1, v: 1, oi: 12 }, { t: 1, o: 1, h: 1, l: 1, c: 1, v: 1 }, { t: 2, o: 1, h: 1, l: 1, c: 1, v: 1, oi: null }]
    expect(Calc.oi(bars, {})).toEqual([[12, null, null]])
  })
})

describe('CATALOG / paramText', () => {
  it('目录与原型一致', () => {
    expect(Object.keys(CATALOG).slice(0, 8)).toEqual(['ma', 'ema', 'boll', 'vol', 'macd', 'rsi', 'kdj', 'oi'])
    expect(Object.keys(CATALOG).slice(8)).toEqual(['vwap', 'st', 'ichi', 'vpvr', 'keys', 'cvd', 'atr', 'obv', 'stochrsi', 'cci', 'wr', 'whale'])
    expect(CATALOG.ma).toEqual({ name: 'MA', cn: '均线', place: 'main', params: { periods: [10, 30, 120, 256] }, colors: ['#F7A600', '#2962FF', '#AB47BC', '#0EA5B7'] })
    expect(CATALOG.boll.params).toEqual({ n: 20, k: 2 })
    expect(CATALOG.vol).toEqual({ name: '成交量', cn: '成交量', place: 'overlay' })
    expect(CATALOG.macd.params).toEqual({ fast: 12, slow: 26, signal: 9 })
    expect(CATALOG.rsi.colors).toEqual(['#7E57C2'])
    expect(CATALOG.kdj.params).toEqual({ n: 9, m1: 3, m2: 3 })
    expect(CATALOG.oi.place).toBe('sub')
    expect(MAX_SUBS).toBe(3) // 和手机端 Prefs.maxSubs 一致
  })
  it('paramText', () => {
    expect(paramText('ma', CATALOG.ma.params)).toBe('10 30 120 256')
    expect(paramText('macd', CATALOG.macd.params)).toBe('12 26 9')
    expect(paramText('oi', {})).toBe('')
    expect(paramText('vol', undefined)).toBe('')
  })
})
