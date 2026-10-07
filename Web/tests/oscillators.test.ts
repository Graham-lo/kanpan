import { describe, expect, it } from 'vitest'
import type { Bar, IndParams, Series } from '../src/chart/calc'
import { OSC_BAND, OSC_CALC, OSC_CATALOG, OSC_FIXED, OSC_LEVELS, OSC_STYLE, type OscId } from '../src/chart/oscillators'

const IDS = Object.keys(OSC_CATALOG) as OscId[]
const ALLOWED = new Set(['n', 'k', 'fast', 'slow', 'signal', 'm1', 'm2', 'stoch', 'tenkan', 'kijun', 'senkou'])
const EXISTING = ['obv', 'cvd', 'atr', 'stochrsi', 'cci', 'wr', 'whale', 'oi', 'macd', 'rsi', 'kdj']

const closeBars = (cs: number[]): Bar[] => cs.map((c, i) => ({ t: i * 36e5, o: c, h: c, l: c, c, v: 1 }))
const near = (a: number | null | undefined, b: number, d = 9) => { expect(a).not.toBeNull(); expect(a as number).toBeCloseTo(b, d) }
const run = (id: OscId, bars: Bar[], p?: IndParams): Series[] => OSC_CALC[id](bars, p ?? OSC_CATALOG[id].params ?? {})

/** 带固定种子的随机游走 K 线：高 > 低，带主动买入与基础币量 */
function randomBars(n: number, seed = 7, start = 60000): Bar[] {
  let s = seed
  const rnd = () => { s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648 }
  const out: Bar[] = []; let c = start
  for (let i = 0; i < n; i++) {
    const o = c; c = Math.max(1, o * (1 + (rnd() - 0.5) * 0.02))
    const h = Math.max(o, c) * (1 + rnd() * 0.005) + 1e-9, l = Math.min(o, c) * (1 - rnd() * 0.005)
    const bv = 10 + rnd() * 1000, v = bv * c
    out.push({ t: i * 36e5, o, h, l, c, v, bv, tb: v * rnd() })
  }
  return out
}
const RB = randomBars(500)

// ---- 测试侧的暴力参考实现（逐窗重算，不走滑窗）
const bruteStd = (xs: number[]) => { const m = xs.reduce((a, b) => a + b, 0) / xs.length; return Math.sqrt(xs.reduce((a, b) => a + (b - m) ** 2, 0) / xs.length) }
const bruteWma = (xs: number[]) => xs.reduce((a, x, j) => a + (j + 1) * x, 0) / (xs.length * (xs.length + 1) / 2)
function pineRsi(src: number[], n: number): (number | null)[] {
  const out: (number | null)[] = src.map(() => null); let u = 0, d = 0
  for (let i = 1; i < src.length; i++) {
    const ch = src[i] - src[i - 1], up = Math.max(ch, 0), dn = Math.max(-ch, 0)
    if (i < n) { u += up; d += dn; continue }
    if (i === n) { u = (u + up) / n; d = (d + dn) / n } else { u = (u * (n - 1) + up) / n; d = (d * (n - 1) + dn) / n }
    out[i] = d === 0 ? 100 : u === 0 ? 0 : 100 - 100 / (1 + u / d)
  }
  return out
}

describe('目录', () => {
  it('39 个 id，CALC 与 CATALOG 一一对应，不和已有指标重名', () => {
    expect(IDS).toHaveLength(39)
    expect(Object.keys(OSC_CALC).sort()).toEqual([...IDS].sort())
    for (const id of EXISTING) expect(IDS).not.toContain(id)
  })
  it('每项：副图、cn 为空、参数键都在 IndParams 里且在 (0, 2000]', () => {
    for (const id of IDS) {
      const c = OSC_CATALOG[id]
      expect(c.place, id).toBe('sub')
      expect(c.cn, id).toBe('')
      expect(c.name.length, id).toBeGreaterThan(0)
      for (const [k, v] of Object.entries(c.params ?? {})) {
        expect(ALLOWED.has(k), `${id}.${k}`).toBe(true)
        expect(typeof v === 'number' && v > 0 && v <= 2000, `${id}.${k}=${v}`).toBe(true)
      }
      for (const col of c.colors ?? []) expect(col, id).toMatch(/^#[0-9A-F]{6}$/i)
    }
  })
  it('输出条数 = 线色条数 = 图例前缀条数；画法条数与输出一致', () => {
    for (const id of IDS) {
      const out = run(id, RB), c = OSC_CATALOG[id]
      expect(c.colors?.length, id).toBe(out.length)
      expect(c.labels?.length, id).toBe(out.length)
      const st = OSC_STYLE[id]; if (st) expect(st.length, id).toBe(out.length)
    }
  })
  it('参考线落在固定刻度里；超买超卖带的两条边都是参考线', () => {
    for (const id of IDS) {
      const f = OSC_FIXED[id], lv = OSC_LEVELS[id] ?? []
      if (f) for (const v of lv) { expect(v, id).toBeGreaterThanOrEqual(f.min); expect(v, id).toBeLessThanOrEqual(f.max) }
      const b = OSC_BAND[id]
      if (b) { expect(b[0], id).toBeGreaterThan(b[1]); expect(lv, id).toContain(b[0]); expect(lv, id).toContain(b[1]) }
    }
  })
  it('默认参数照 TradingView', () => {
    expect(OSC_CATALOG.stoch.params).toEqual({ n: 14, m1: 1, m2: 3 })
    expect(OSC_CATALOG.kst.params).toEqual({ signal: 9 })
    expect(OSC_CATALOG.tsi.params).toEqual({ slow: 25, fast: 13, signal: 13 })
    expect(OSC_CATALOG.crsi.params).toEqual({ n: 3, m1: 2, m2: 100 })
    expect(OSC_CATALOG.ppo.params).toEqual({ fast: 12, slow: 26, signal: 9 })
    expect(OSC_CATALOG.pvt.params).toEqual({})
  })
})

describe('500 根随机 K 线：全部指标', () => {
  for (const id of IDS) {
    it(`${id}：不抛错、长度等于输入、前段 null 后段有限数`, () => {
      const out = run(id, RB)
      for (const s of out) {
        expect(s).toHaveLength(RB.length)
        const first = s.findIndex(v => v != null)
        expect(first, id).toBeGreaterThanOrEqual(0)
        expect(first, id).toBeLessThan(200)
        for (let i = first; i < s.length; i++) expect(Number.isFinite(s[i]), `${id}[${i}]=${s[i]}`).toBe(true)
      }
      const f = OSC_FIXED[id]
      if (f) for (const s of out) for (const v of s) if (v != null) { expect(v).toBeGreaterThanOrEqual(f.min - 1e-9); expect(v).toBeLessThanOrEqual(f.max + 1e-9) }
    })
  }
  it('没有成交、只有一根、空数组都不抛错', () => {
    for (const id of IDS) {
      expect(run(id, []).every(s => s.length === 0)).toBe(true)
      expect(run(id, RB.slice(0, 1)).every(s => s.length === 1)).toBe(true)
      run(id, RB.map(b => ({ ...b, v: 0, bv: 0, tb: 0 })))
    }
  })
  it('前 n−1 根是 null（窗口类）', () => {
    expect(run('stdev', RB)[0].findIndex(v => v != null)).toBe(19)
    expect(run('mom', RB)[0].findIndex(v => v != null)).toBe(10)
    expect(run('aroon', RB)[0].findIndex(v => v != null)).toBe(14)
    expect(run('ao', RB)[0].findIndex(v => v != null)).toBe(33)
    expect(run('cmo', RB)[0].findIndex(v => v != null)).toBe(9)       // 涨跌从第 1 根起，再满 9 根
    expect(run('dmi', RB)[0].findIndex(v => v != null)).toBe(14)
    expect(run('dmi', RB)[2].findIndex(v => v != null)).toBe(14 + 13)
    expect(run('crsi', RB)[0].findIndex(v => v != null)).toBe(101)    // 涨跌幅从第 1 根起，百分位要前 100 根
  })
})

describe('解析值', () => {
  it('动量 / 变动率', () => {
    expect(run('mom', closeBars([1, 2, 4, 7, 11]), { n: 2 })[0]).toEqual([null, null, 3, 5, 7])
    const r = run('roc', closeBars([100, 110, 99]), { n: 1 })[0]
    expect(r[0]).toBeNull(); near(r[1], 10); near(r[2], -10)
  })
  it('标准差：总体标准差，和逐窗重算一致（大价位也不丢精度）', () => {
    const s = run('stdev', closeBars([1, 2, 3, 4, 5]), { n: 3 })[0]
    expect(s.slice(0, 2)).toEqual([null, null])
    for (let i = 2; i < 5; i++) near(s[i], Math.sqrt(2 / 3))
    const cs = RB.map(b => b.c), out = run('stdev', RB, { n: 20 })[0]
    for (let i = 19; i < cs.length; i++) near(out[i], bruteStd(cs.slice(i - 19, i + 1)), 6)
  })
  it('阿隆：n + 1 根窗口里距最高 / 最低的根数', () => {
    const hs = [1, 5, 2, 3, 4], ls = [2, 4, 1, 0.5, 3]
    const bars: Bar[] = hs.map((h, i) => ({ t: i, o: h, h, l: ls[i], c: h, v: 1 }))
    const [up, dn] = run('aroon', bars, { n: 3 })
    expect(up.slice(0, 3)).toEqual([null, null, null])
    near(up[3], 100 / 3); near(up[4], 0)
    near(dn[3], 100); near(dn[4], 100 * 2 / 3) // i=3 最低就是本根（并列取最近）；i=4 窗口 1..4 最低在第 3 根
  })
  it('随机指标：%K 与 %D 照定义，和逐窗暴力算一致', () => {
    const bars: Bar[] = [
      { t: 0, o: 0, h: 10, l: 8, c: 9, v: 1 },
      { t: 1, o: 0, h: 11, l: 9, c: 10, v: 1 },
      { t: 2, o: 0, h: 12, l: 10, c: 12, v: 1 },
      { t: 3, o: 0, h: 12, l: 7, c: 8, v: 1 },
    ]
    const [k, d] = run('stoch', bars, { n: 3, m1: 1, m2: 2 })
    expect(k.slice(0, 2)).toEqual([null, null])
    near(k[2], 100); near(k[3], 100 * (8 - 7) / (12 - 7))
    expect(d[2]).toBeNull(); near(d[3], (100 + 20) / 2)
    const [k2] = run('stoch', RB, { n: 14, m1: 1, m2: 3 })
    for (let i = 13; i < RB.length; i++) {
      const w = RB.slice(i - 13, i + 1), h = Math.max(...w.map(b => b.h)), l = Math.min(...w.map(b => b.l))
      near(k2[i], 100 * (RB[i].c - l) / (h - l), 7)
    }
  })
  it('钱德动量', () => {
    const c = run('cmo', closeBars([1, 2, 1, 3]), { n: 2 })[0]
    expect(c.slice(0, 2)).toEqual([null, null]); near(c[2], 0); near(c[3], 100 / 3)
  })
  it('资金流量：全涨 100；动向指标：一路上涨 −DI = 0、ADX → 100', () => {
    const up: Bar[] = Array.from({ length: 40 }, (_, i) => ({ t: i, o: 10 + i, h: 11 + i, l: 9 + i, c: 10.5 + i, v: 100, bv: 10 }))
    expect(run('mfi', up, { n: 5 })[0].slice(5).every(v => v === 100)).toBe(true)
    const [p, m, adx] = run('dmi', up, { n: 5, m1: 5 })
    near(p[39], 100 * 1 / 2); near(m[39], 0); near(adx[39], 100)
  })
  it('PPO：柱 = PPO − 信号；PPO = 100 × (EMA快 − EMA慢) / EMA慢', () => {
    const [p, s, h] = run('ppo', RB)
    for (let i = 0; i < RB.length; i++) {
      if (p[i] == null || s[i] == null) { expect(h[i]).toBeNull(); continue }
      near(h[i], (p[i] as number) - (s[i] as number))
    }
    expect(p.findIndex(v => v != null)).toBe(25)
    expect(s.findIndex(v => v != null)).toBe(25 + 8)
  })
  it('科波克：WMA(ROC 长 + ROC 短)，和暴力算一致', () => {
    const cs = RB.map(b => b.c), out = run('coppock', RB, { m1: 11, m2: 14, n: 10 })[0]
    const sumRoc = cs.map((c, i) => i >= 14 ? 100 * (c - cs[i - 14]) / cs[i - 14] + 100 * (c - cs[i - 11]) / cs[i - 11] : NaN)
    expect(out.findIndex(v => v != null)).toBe(14 + 9)
    for (let i = 23; i < cs.length; i++) near(out[i], bruteWma(sumRoc.slice(i - 9, i + 1)), 7)
  })
  it('康纳 RSI：(RSI 3 + 连涨连跌 RSI 2 + 一根涨跌幅的百分位 100) / 3，和暴力算一致', () => {
    const cs = RB.map(b => b.c), out = run('crsi', RB)[0]
    const ud: number[] = []
    for (let i = 0; i < cs.length; i++) {
      const p = i > 0 ? ud[i - 1] : 0
      ud.push(i > 0 && cs[i] === cs[i - 1] ? 0 : i > 0 && cs[i] > cs[i - 1] ? (p <= 0 ? 1 : p + 1) : (p >= 0 ? -1 : p - 1))
    }
    const r1 = pineRsi(cs, 3), r2 = pineRsi(ud, 2), rc = cs.map((c, i) => i > 0 ? 100 * (c - cs[i - 1]) / cs[i - 1] : NaN)
    for (let i = 101; i < cs.length; i++) {
      let cnt = 0; for (let j = i - 100; j < i; j++) if (rc[j] <= rc[i]) cnt++
      near(out[i], ((r1[i] as number) + (r2[i] as number) + cnt) / 3, 7)
    }
  })
  it('均势指标：n = 1 不平滑，(收 − 开) / (高 − 低)', () => {
    const b: Bar[] = [{ t: 0, o: 10, h: 12, l: 8, c: 11, v: 1 }, { t: 1, o: 11, h: 11, l: 11, c: 11, v: 1 }]
    expect(run('bop', b, { n: 1 })[0]).toEqual([0.25, 0])
  })
  it('费舍尔：触发线 = 上一根的值', () => {
    const [f, t] = run('fisher', RB)
    for (let i = 1; i < RB.length; i++) expect(t[i]).toBe(f[i - 1])
  })
  it('布林 %B 与带宽：和逐窗暴力算一致', () => {
    const cs = RB.map(b => b.c), [pb] = run('bbpct', RB), [bw] = run('bbw', RB)
    for (let i = 19; i < cs.length; i++) {
      const w = cs.slice(i - 19, i + 1), m = w.reduce((a, b) => a + b, 0) / 20, sd = bruteStd(w)
      near(pb[i], (cs[i] - (m - 2 * sd)) / (4 * sd), 6)
      near(bw[i], 400 * sd / m, 6)
    }
  })
  it('净成交量：2 × 主动买入 − 成交额；没有主动买入出空；多家聚合时加各家量差', () => {
    const b: Bar[] = [
      { t: 0, o: 1, h: 1, l: 1, c: 1, v: 100, tb: 70 },
      { t: 1, o: 1, h: 1, l: 1, c: 1, v: 100 },
      { t: 2, o: 1, h: 1, l: 1, c: 1, v: 100, tb: 10, venueDelta: { binance: -80, okx: 5 } },
    ]
    expect(run('nv', b)[0]).toEqual([40, null, -75])
  })
  it('历史波动率：每根同样的对数收益 → 0；日线以下按 √365 年化', () => {
    const g = closeBars(Array.from({ length: 30 }, (_, i) => 100 * 1.01 ** i))
    for (const v of run('hv', g)[0].slice(10)) near(v, 0, 6)
    const alt = closeBars(Array.from({ length: 12 }, (_, i) => (i % 2 ? 110 : 100)))
    const sd = Math.log(1.1) // 对数收益 ±ln1.1 交替，总体标准差 = ln1.1
    near(run('hv', alt, { n: 10 })[0][11], 100 * sd * Math.sqrt(365), 6)
  })
})

describe('常量序列', () => {
  const flat = closeBars(new Array(300).fill(123.456))
  const zeroIds: OscId[] = ['mom', 'roc', 'trix', 'efi', 'dpo', 'ao', 'ac', 'cmo', 'tsi', 'kst', 'coppock', 'stdev', 'hv', 'bbw', 'bbp', 'pvt', 'ad', 'cmf', 'chosc', 'eom', 'volosc', 'klinger', 'ppo', 'smi', 'rvgi', 'bop']
  for (const id of zeroIds) {
    it(`${id} 为 0`, () => {
      for (const s of run(id, flat)) {
        const vals = s.filter((v): v is number => v != null)
        expect(vals.length, id).toBeGreaterThan(0)
        for (const v of vals) expect(Math.abs(v), id).toBeLessThan(1e-9)
      }
    })
  }
  it('有中性值的取中性值、没有的出空', () => {
    expect(run('stoch', flat)[0].slice(13).every(v => v === 50)).toBe(true)
    expect(run('mfi', flat)[0].slice(14).every(v => v === 50)).toBe(true)
    expect(run('rvi', flat)[0].slice(22).every(v => v === 50)).toBe(true)
    expect(run('bbpct', flat)[0].slice(19).every(v => v === 0.5)).toBe(true)
    expect(run('mass', flat)[0].slice(40).every(v => v === 25)).toBe(true)
    expect(run('chop', flat)[0].every(v => v == null)).toBe(true)
    expect(run('vortex', flat)[0].every(v => v == null)).toBe(true)
  })
})

describe('简易波动：量级不随价位与周期变', () => {
  it('同样的相对涨跌、同样的成交额，价格放大一万倍读数不变', () => {
    const a = run('eom', RB)[0], scaled = RB.map(b => ({ ...b, o: b.o * 1e-4, h: b.h * 1e-4, l: b.l * 1e-4, c: b.c * 1e-4, bv: (b.bv as number) * 1e4 }))
    const b = run('eom', scaled)[0]
    for (let i = 14; i < RB.length; i++) near(b[i], a[i] as number, 6)
  })
})
