import { describe, expect, it } from 'vitest'
import { Calc, CATALOG, MAIN_IDS, type Bar } from '../src/chart/calc'
import {
  MORE_MAIN_IDS, isMoreMain, mainOn, wmaS, dema, tema, rmaS, vwma, hma, alma, linreg, donchian, envelope, keltner,
  parabolicSar, zigzag, fractals, alligator, pivotLevels, pivotPeriodStart, pivots,
} from '../src/chart/mainIndicators'

const H = 36e5, D = 864e5
const bar = (i: number, c: number, o = c, h = Math.max(o, c), l = Math.min(o, c), v = 1, t = i * H): Bar => ({ t, o, h, l, c, v })
const flat = (n: number, x = 50) => Array.from({ length: n }, () => x)
const line = (n: number, a = 10, b = 2) => Array.from({ length: n }, (_, i) => a + b * i)
const close = (s: (number | null)[], i: number, v: number, d = 9) => expect(s[i]).toBeCloseTo(v, d)

describe('第二批主图叠加 · 均线类', () => {
  it('常数序列：wma / dema / tema / smma / vwma / hma / alma / lsma 有值的地方都等于那个常数，前面不够窗口的是 null', () => {
    const c = flat(80, 37.5)
    for (const [name, s, first] of [
      ['wma', wmaS(c, 20), 19], ['dema', dema(c, 10), 18], ['tema', tema(c, 10), 27], ['smma', rmaS(c, 7), 6],
      ['hma', hma(c, 16), 18], ['alma', alma(c, 9), 8], ['lsma', linreg(c, 25), 24],
    ] as const) {
      expect(s.findIndex(v => v != null), name).toBe(first)
      for (let i = first; i < c.length; i++) close(s, i, 37.5)
    }
    const bars = c.map((x, i) => bar(i, x, x, x, x, 1 + (i % 5)))
    const v = vwma(bars, 20)
    expect(v.findIndex(x => x != null)).toBe(19)
    for (let i = 19; i < 80; i++) close(v, i, 37.5)
  })

  it('线性序列：wma 滞后 (n−1)/3、dema / tema 的稳态滞后比单 EMA 小、lsma 正好落在线上、等量的 vwma 就是简单均线', () => {
    const n = 20, c = line(400, 10, 2)
    const w = wmaS(c, n)
    // 线性 a + b·i 的 WMA = a + b·(i − (n−1)/3)
    close(w, 100, 10 + 2 * (100 - (n - 1) / 3))
    const e = rmaS(c, n)
    // 远离种子的稳态：EMA 滞后 (1−α)/α 根；DEMA 把一阶滞后抵消掉、TEMA 同样，两者都应收敛到真值
    expect(Math.abs((dema(c, n)[399] as number) - c[399])).toBeLessThan(1e-6)
    expect(Math.abs((tema(c, n)[399] as number) - c[399])).toBeLessThan(1e-6)
    expect(c[399] - (e[399] as number)).toBeCloseTo(2 * (n - 1), 6) // smma α=1/n：滞后 (n−1) 根 × 斜率 2
    close(linreg(c, n), 200, c[200])
    const bars = c.map((x, i) => bar(i, x))
    close(vwma(bars, n), 150, c.slice(131, 151).reduce((a, b) => a + b, 0) / n)
  })

  it('vwma 照量加权：量大的那根拉得多；整段零量回落到简单均线', () => {
    const bars = [bar(0, 10, 10, 10, 10, 1), bar(1, 20, 20, 20, 20, 3)]
    close(vwma(bars, 2), 1, (10 + 60) / 4)
    const zero = [bar(0, 10, 10, 10, 10, 0), bar(1, 20, 20, 20, 20, 0)]
    close(vwma(zero, 2), 1, 15)
  })
})

describe('第二批主图叠加 · 通道类', () => {
  const bars = Array.from({ length: 40 }, (_, i) => bar(i, 100 + Math.sin(i) * 5, 100, 100 + Math.sin(i) * 5 + 3, 100 + Math.sin(i) * 5 - 4))
  it('唐奇安：上轨 = n 根最高、下轨 = n 根最低、中轨是两者中点', () => {
    const [mid, up, dn] = donchian(bars, 10)
    expect(up[8]).toBeNull()
    for (const i of [9, 20, 39]) {
      const win = bars.slice(i - 9, i + 1)
      close(up, i, Math.max(...win.map(b => b.h)))
      close(dn, i, Math.min(...win.map(b => b.l)))
      close(mid, i, ((up[i] as number) + (dn[i] as number)) / 2)
    }
  })
  it('包络线：简单均线上下各偏 k%', () => {
    const c = line(30, 100, 1), [mid, up, dn] = envelope(c, 5, 10)
    close(mid, 10, (106 + 107 + 108 + 109 + 110) / 5)
    close(up, 10, (mid[10] as number) * 1.1)
    close(dn, 10, (mid[10] as number) * 0.9)
    expect(mid[3]).toBeNull()
  })
  it('肯特纳：上下轨关于中轨对称，波幅为零时三线重合', () => {
    const [mid, up, dn] = keltner(bars, 20, 2)
    const i = 39
    close(up, i, 2 * (mid[i] as number) - (dn[i] as number))
    expect((up[i] as number) > (mid[i] as number)).toBe(true)
    const still = flat(40, 7).map((x, k) => bar(k, x))
    const [m2, u2, d2] = keltner(still, 20, 2)
    close(u2, 39, m2[39] as number); close(d2, 39, 7)
  })
})

describe('第二批主图叠加 · 趋势类', () => {
  it('SAR：一路上涨时第一段在 K 线下方、逐根抬高；一路下跌时在上方', () => {
    const upBars = line(30, 100, 1).map((c, i) => bar(i, c, c - 0.5, c + 0.3, c - 0.8))
    const s = parabolicSar(upBars)
    expect(s[0]).toBeNull()
    for (let i = 1; i < 30; i++) expect(s[i] as number).toBeLessThanOrEqual(upBars[i].l)
    // 照 Pine：SAR 不能高过前两根的最低，所以开头两根会被夹住持平，之后逐根抬高
    for (let i = 2; i < 30; i++) expect(s[i] as number).toBeGreaterThanOrEqual(s[i - 1] as number)
    expect(s[29] as number).toBeGreaterThan(s[5] as number)
    const dnBars = line(30, 200, -1).map((c, i) => bar(i, c, c + 0.5, c + 0.8, c - 0.3))
    const t = parabolicSar(dnBars)
    for (let i = 1; i < 30; i++) expect(t[i] as number).toBeGreaterThanOrEqual(dnBars[i].h)
  })
  it('SAR：第一段起点照 Pine——第二根收涨就从前一根最低起算，加速因子 0.02', () => {
    const b = [bar(0, 10, 10, 11, 9), bar(1, 12, 10, 13, 10), bar(2, 13, 12, 14, 12)]
    const s = parabolicSar(b)
    // i=1：result = 9 + 0.02·(13 − 9) = 9.08，再夹到前一根最低 9 以下 → 9
    close(s, 1, 9)
  })
  it('SAR：涨着涨着跌穿 SAR 就翻到上方', () => {
    const b = [...line(15, 100, 1).map((c, i) => bar(i, c, c - 0.5, c + 0.3, c - 0.8)), ...line(10, 105, -3).map((c, i) => bar(15 + i, c, c + 1, c + 1.2, c - 0.3))]
    const s = parabolicSar(b)
    const flip = s.findIndex((v, i) => i > 1 && v != null && v > b[i].h)
    expect(flip).toBeGreaterThan(14)
    expect(s[flip - 1] as number).toBeLessThan(b[flip - 1].l + 1e-9)
  })
  it('之字转向：只在转折处有值，高低交替，相邻转折偏离 ≥ dev%', () => {
    // 三角波：第 0–20 根涨到 120，第 21–40 根跌到 81，第 41 根 80 起再涨到 130（还没走完，最后不算转折）
    const path = [...line(21, 100, 1), ...line(20, 119, -2), ...line(26, 80, 2)]
    const bars = path.map((c, i) => bar(i, c, c, c + 0.1, c - 0.1))
    const z = zigzag(bars, 6, 5)
    const pts = z.map((v, i) => [i, v] as const).filter(([, v]) => v != null)
    expect(pts.map(([i]) => i)).toEqual([20, 41])
    close(z, 20, 120.1); close(z, 41, 80 - 0.1)
    // 偏离不够大的抖动不算转折
    const tiny = line(40, 100, 0).map((c, i) => bar(i, c + (i % 8 < 4 ? 0.3 : -0.3)))
    const zt = zigzag(tiny, 4, 5)
    expect(zt.filter(v => v != null).length).toBeLessThanOrEqual(1)
  })
  it('分形：比左右各 n 根都高（低）的那根标出来，最后 n 根还没确认的不标', () => {
    const hs = [1, 2, 5, 2, 1, 1, 0, 3, 0.5, 2, 9]
    const bars = hs.map((h, i) => bar(i, h, h, h, h - 1))
    const [up, dn] = fractals(bars, 2)
    expect(up[2]).toBe(5)
    expect(up[10]).toBeNull()
    expect(dn[6]).toBe(-1)
    expect(up.filter(v => v != null).length).toBe(2) // 2 与 7
  })
  it('鳄鱼线：三条平滑均线各往右推 8 / 5 / 3 根，序列比 K 线长', () => {
    const bars = flat(40, 10).map((x, i) => bar(i, x, x, 12, 8))
    const [jaw, teeth, lips] = alligator(bars)
    expect(jaw.length).toBe(48); expect(teeth.length).toBe(45); expect(lips.length).toBe(43)
    expect(jaw.findIndex(v => v != null)).toBe(12 + 8)
    close(lips, 42, 10)
  })
})

describe('第二批主图叠加 · 枢轴点（经典）', () => {
  it('公式：P、R1/S1、R2/S2、R3/S3', () => {
    const [p, r1, s1, r2, s2, r3, s3] = pivotLevels(110, 90, 105)
    const P = 305 / 3
    expect(p).toBeCloseTo(P, 12)
    expect(r1).toBeCloseTo(2 * P - 90, 12); expect(s1).toBeCloseTo(2 * P - 110, 12)
    expect(r2).toBeCloseTo(P + 20, 12); expect(s2).toBeCloseTo(P - 20, 12)
    expect(r3).toBeCloseTo(110 + 2 * (P - 90), 12); expect(s3).toBeCloseTo(90 - 2 * (110 - P), 12)
  })
  it('日内周期取前一天的高低收；第一天之内没有值；第一段没加载全不作数', () => {
    const day0 = Date.UTC(2026, 9, 5)
    const bars: Bar[] = []
    for (let i = 0; i < 48; i++) { const c = i < 24 ? 100 + i : 50 + i; bars.push(bar(i, c, c, c + 1, c - 1, 1, day0 + i * H)) }
    const out = pivots(bars, H)
    expect(out[0][23]).toBeNull()
    const [P] = pivotLevels(124, 99, 123)
    close(out[0], 24, P); close(out[0], 47, P)
    // 从当天中午才开始有 K 线：那一天不完整，第二天也不画
    const half = bars.slice(12).map(b => ({ ...b }))
    expect(pivots(half, H)[0].every(v => v == null)).toBe(true)
  })
  it('周期切分：日线按周一起的周，周线按月，月线按年', () => {
    const wed = Date.UTC(2026, 9, 7, 13) // 2026-10-07 周三
    expect(new Date(pivotPeriodStart(wed, D)).toISOString().slice(0, 10)).toBe('2026-10-05')
    expect(new Date(pivotPeriodStart(wed, 7 * D)).toISOString().slice(0, 10)).toBe('2026-10-01')
    expect(new Date(pivotPeriodStart(wed, 30 * D)).toISOString().slice(0, 10)).toBe('2026-01-01')
    expect(pivotPeriodStart(wed, H)).toBe(Date.UTC(2026, 9, 7))
  })
})

describe('第二批主图叠加 · 目录与开关', () => {
  it('全部并进 Calc / CATALOG / MAIN_IDS，叠在主图上，算出来的条数与颜色条数一致', () => {
    const bars = line(300, 100, 0.5).map((c, i) => bar(i, c + Math.sin(i / 3) * 4, c, c + 6, c - 6, 10))
    expect(MORE_MAIN_IDS.length).toBe(18)
    for (const id of MORE_MAIN_IDS) {
      expect(MAIN_IDS).toContain(id)
      expect(CATALOG[id].place).toBe('main')
      expect(CATALOG[id].cn).toBe('')
      const out = Calc[id](bars, CATALOG[id].params || {}, { symbol: 'BTCUSDT', iv: H, invalidate: () => {} })
      expect(out.length, id).toBe(CATALOG[id].colors?.length)
      for (const v of CATALOG[id].params ? Object.values(CATALOG[id].params!) : []) {
        if (typeof v === 'number') { expect(v).toBeGreaterThan(0); expect(v).toBeLessThanOrEqual(2000) }
      }
    }
  })
  it('mainOn：老的主图看布尔字段，第二批看 mains 列表', () => {
    expect(isMoreMain('kc')).toBe(true); expect(isMoreMain('ma')).toBe(false); expect(isMoreMain('nope')).toBe(false)
    const ind = { ma: true, ema: false, mains: ['kc', 'sar'] }
    expect(mainOn(ind, 'ma')).toBe(true); expect(mainOn(ind, 'ema')).toBe(false)
    expect(mainOn(ind, 'kc')).toBe(true); expect(mainOn(ind, 'dc')).toBe(false)
    expect(mainOn({}, 'kc')).toBe(false)
  })
})

describe('指标对话框清单', async () => {
  const { indicatorRows, matchRow, IND_GROUPS } = await import('../src/pages/indicatorPicker')
  it('目录里每个指标正好出现一次；按类分组，类里主图在前', () => {
    const rows = indicatorRows()
    expect(rows.map(r => r.id).sort()).toEqual(Object.keys(CATALOG).sort())
    let gi = 0, seenSub = false
    for (const r of rows) {
      const g = IND_GROUPS.indexOf(r.group)
      if (g !== gi) { expect(g).toBeGreaterThan(gi); gi = g; seenSub = false }
      if (r.place === 'sub') seenSub = true
      else expect(seenSub, r.id).toBe(false)
    }
    expect(rows[0].id).toBe('ma')
  })
  it('搜索：中文名、id、目录短名都能搜到，忽略大小写与空格', () => {
    const rows = indicatorRows(), find = (q: string) => rows.filter(r => matchRow(r, q)).map(r => r.id)
    expect(find('均线')).toEqual(expect.arrayContaining(['ma', 'ema', 'wma', 'hma']))
    expect(find('SAR')).toContain('sar')
    expect(find(' k c ')).toContain('kc')
    expect(find('随机')).toEqual(expect.arrayContaining(['kdj', 'stoch']))
    expect(find('')).toHaveLength(rows.length)
  })
})
