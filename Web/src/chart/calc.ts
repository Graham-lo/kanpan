/* Hkline Web · 指标计算与指标目录
 *
 * 从原型 chart.js 逐字搬过来：算法、目录（名字、默认参数、线色、分类）都不改。
 */

/** 一根 K 线；v 是成交额（报价币计），oi 是持仓量（没有就 null）；
 *  tb 是主动买入成交额（报价币计，CVD 与成交量分布的买卖拆分用），bv 是成交量（基础币计，VWAP 加权用）；
 *  venueDelta 是多交易所聚合时各家的主动买卖差（报价币计），只有币安时不填 */
export type Bar = { t: number; o: number; h: number; l: number; c: number; v: number; oi?: number | null; tb?: number; bv?: number; venueDelta?: Partial<Record<'binance' | 'okx' | 'coinbase', number>> }
export type Series = (number | null)[]
import { EXTRA_CALC, EXTRA_CATALOG, type ExtraMainId, type ExtraSubId } from './indicators'

export type IndicatorId = 'ma' | 'ema' | 'boll' | 'vol' | 'macd' | 'rsi' | 'kdj' | 'oi' | ExtraMainId | ExtraSubId
export type MainId = 'ma' | 'ema' | 'boll' | ExtraMainId
export type SubId = 'macd' | 'rsi' | 'kdj' | 'oi' | ExtraSubId
export type CalcId = MainId | SubId

/** 指标参数：各指标只用到其中几项（MA/EMA 用 periods，BOLL 用 n/k，MACD 用 fast/slow/signal，RSI 用 n，KDJ 用 n/m1/m2） */
export interface IndParams {
  periods?: number[]
  n?: number
  k?: number
  fast?: number
  slow?: number
  signal?: number
  m1?: number
  m2?: number
  /** 随机 RSI 的取值窗口 */
  stoch?: number
  /** 一目均衡表：转换线、基准线、先行 B */
  tenkan?: number
  kijun?: number
  senkou?: number
}

export interface CatalogEntry {
  name: string
  cn: string
  place: 'main' | 'overlay' | 'sub'
  params?: IndParams
  colors?: string[]
}

/** 主图叠加指标（按这个顺序算、按 boll → ema → ma 的顺序画） */
export const MAIN_IDS: MainId[] = ['ma', 'ema', 'boll', 'vwap', 'st', 'ichi', 'vpvr']
/** 副图最多四个（网页版副图矮、屏幕高） */
export const MAX_SUBS = 4

// ------------------------------------------------------------ 指标计算
export function sma(src: number[], n: number): Series {
  const out: Series = new Array(src.length).fill(null); let s = 0
  for (let i = 0; i < src.length; i++) { s += src[i]; if (i >= n) s -= src[i - n]; if (i >= n - 1) out[i] = s / n }
  return out
}
export function ema(src: Series, n: number): Series {
  const out: Series = new Array(src.length).fill(null); const k = 2 / (n + 1); let e: number | null = null
  for (let i = 0; i < src.length; i++) {
    const x = src[i]
    if (x == null) continue
    if (e == null) { if (i >= n - 1) { let s = 0; for (let j = i - n + 1; j <= i; j++) s += src[j] as number; e = s / n; out[i] = e } continue }
    e = x * k + e * (1 - k); out[i] = e
  }
  return out
}
export function rma(src: number[], n: number): Series {
  const out: Series = new Array(src.length).fill(null); let r = 0, s = 0
  for (let i = 0; i < src.length; i++) {
    if (i < n) { s += src[i]; if (i === n - 1) { r = s / n; out[i] = r } continue }
    r = (r * (n - 1) + src[i]) / n; out[i] = r
  }
  return out
}

type CalcFn = (bars: Bar[], p: IndParams) => Series[]

export const Calc: Record<CalcId, CalcFn> = {
  ma(bars, p) { const c = bars.map(b => b.c); return (p.periods ?? []).map(n => sma(c, n)) },
  ema(bars, p) { const c = bars.map(b => b.c); return (p.periods ?? []).map(n => ema(c, n)) },
  boll(bars, p) {
    const c = bars.map(b => b.c), n = p.n as number, k = p.k as number, mid = sma(c, n), up: Series = [], dn: Series = []
    for (let i = 0; i < c.length; i++) {
      const m = mid[i]
      if (m == null) { up.push(null); dn.push(null); continue }
      let v = 0; for (let j = i - n + 1; j <= i; j++) v += (c[j] - m) ** 2
      const sd = Math.sqrt(v / n); up.push(m + k * sd); dn.push(m - k * sd)
    }
    return [mid, up, dn]
  },
  macd(bars, p) {
    const c = bars.map(b => b.c), f = ema(c, p.fast as number), s = ema(c, p.slow as number)
    const dif: Series = c.map((_, i) => { const a = f[i], b = s[i]; return a != null && b != null ? a - b : null })
    const firstIdx = dif.findIndex(v => v != null)
    const dea: Series = new Array(c.length).fill(null)
    if (firstIdx >= 0) { const d2 = ema(dif.slice(firstIdx), p.signal as number); for (let i = 0; i < d2.length; i++) dea[firstIdx + i] = d2[i] }
    const hist: Series = dif.map((v, i) => { const d = dea[i]; return v != null && d != null ? v - d : null })
    return [dif, dea, hist]
  },
  rsi(bars, p) {
    const c = bars.map(b => b.c), up = [0], dn = [0]
    for (let i = 1; i < c.length; i++) { const d = c[i] - c[i - 1]; up.push(Math.max(d, 0)); dn.push(Math.max(-d, 0)) }
    const n = p.n as number, ru = rma(up, n), rd = rma(dn, n)
    return [c.map((_, i) => { const u = ru[i], d = rd[i]; return u == null || d == null ? null : d === 0 ? 100 : 100 - 100 / (1 + u / d) })]
  },
  kdj(bars, p) {
    const n = p.n as number, m1 = p.m1 as number, m2 = p.m2 as number
    const K: Series = [], D: Series = [], J: Series = []; let k = 50, d = 50
    for (let i = 0; i < bars.length; i++) {
      if (i < n - 1) { K.push(null); D.push(null); J.push(null); continue }
      let hi = -Infinity, lo = Infinity
      for (let j = i - n + 1; j <= i; j++) { hi = Math.max(hi, bars[j].h); lo = Math.min(lo, bars[j].l) }
      const rsv = hi === lo ? 50 : (bars[i].c - lo) / (hi - lo) * 100
      k = (k * (m1 - 1) + rsv) / m1; d = (d * (m2 - 1) + k) / m2
      K.push(k); D.push(d); J.push(3 * k - 2 * d)
    }
    return [K, D, J]
  },
  oi(bars) { return [bars.map(b => b.oi ?? null)] },
  ...EXTRA_CALC,
}

// 指标目录：名字、默认参数、线色。副图最多四个（网页版副图矮、屏幕高）。
export const CATALOG: Record<IndicatorId, CatalogEntry> = {
  ma: { name: 'MA', cn: '均线', place: 'main', params: { periods: [10, 30, 120, 256] }, colors: ['#F7A600', '#2962FF', '#AB47BC', '#0EA5B7'] },
  ema: { name: 'EMA', cn: '指数均线', place: 'main', params: { periods: [12, 26] }, colors: ['#FF6D00', '#00897B'] },
  boll: { name: 'BOLL', cn: '布林带', place: 'main', params: { n: 20, k: 2 }, colors: ['#FF6D00', '#2962FF', '#2962FF'] },
  vol: { name: '成交量', cn: '成交量', place: 'overlay' },
  macd: { name: 'MACD', cn: '平滑异同', place: 'sub', params: { fast: 12, slow: 26, signal: 9 }, colors: ['#2962FF', '#FF6D00'] },
  rsi: { name: 'RSI', cn: '相对强弱', place: 'sub', params: { n: 14 }, colors: ['#7E57C2'] },
  kdj: { name: 'KDJ', cn: '随机指标', place: 'sub', params: { n: 9, m1: 3, m2: 3 }, colors: ['#2962FF', '#FF6D00', '#AB47BC'] },
  oi: { name: '持仓量', cn: '持仓量', place: 'sub', params: {}, colors: ['#2962FF'] },
  ...EXTRA_CATALOG,
}

export function paramText(_id: string, p: IndParams | null | undefined): string {
  if (!p) return ''
  if (p.periods) return p.periods.join(' ')
  return Object.values(p).join(' ')
}
