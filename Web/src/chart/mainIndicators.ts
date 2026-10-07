/* Hkline Web · 第三批主图叠加（网页版大屏专有，照 TradingView 内置指标补齐）
 *
 * 均线类：加权、赫尔、双重 / 三重指数、平滑、量加权、最小二乘、阿诺·勒古、麦金利动态线
 * 通道类：肯特纳通道、唐奇安通道、包络线
 * 趋势类：抛物线 SAR、波动止损、鳄鱼线、威廉分形、之字转向、枢轴点
 * 算法逐条照 TradingView 内置脚本（Pine 源码）移植；画法见 overlaysMore.ts。
 *
 * 这批 id 只存本机（IndState.mains），不进同步白名单（codec 的 OVERLAY_MAP / PARAM_IDS）：
 * 服务端不认识的名字会让整份设置被拒。
 * 只从 calc.ts 拿类型，运行时不反向依赖它（calc.ts 把这里的表并进 Calc / CATALOG）。
 */
import type { Bar, Series, IndParams, CatalogEntry, CalcEnv } from './calc'

export type MoreMainId =
  | 'wma' | 'hma' | 'dema' | 'tema' | 'smma' | 'vwma' | 'lsma' | 'alma' | 'mcg'
  | 'kc' | 'dc' | 'env'
  | 'sar' | 'vstop' | 'alligator' | 'fractals' | 'zigzag' | 'pivots'
export const MORE_MAIN_IDS: MoreMainId[] = [
  'wma', 'hma', 'dema', 'tema', 'smma', 'vwma', 'lsma', 'alma', 'mcg',
  'kc', 'dc', 'env',
  'sar', 'vstop', 'alligator', 'fractals', 'zigzag', 'pivots',
]
const MORE_SET = new Set<string>(MORE_MAIN_IDS)
export const isMoreMain = (id: string): id is MoreMainId => MORE_SET.has(id)

/** 主图叠加开没开：老的几个用布尔字段（会同步），这批在 mains 列表里（只存本机） */
export function mainOn(ind: { mains?: readonly string[] }, id: string): boolean {
  return isMoreMain(id) ? !!ind.mains?.includes(id) : (ind as Record<string, unknown>)[id] === true
}

type Fn = (bars: Bar[], p: IndParams, env?: CalcEnv) => Series[]
const DAY = 864e5
const int = (v: number | undefined, d: number): number => Math.max(1, Math.round(v && v > 0 ? v : d))
const num = (v: number | undefined, d: number): number => v && v > 0 ? v : d

// ------------------------------------------------------------ 均线小工具（都容得下开头的空值）
export function smaS(src: Series, n: number): Series {
  const out: Series = new Array(src.length).fill(null)
  let s = 0, run = 0
  for (let i = 0; i < src.length; i++) {
    const v = src[i]
    if (v == null) { s = 0; run = 0; continue }
    s += v; run++
    if (run > n) s -= src[i - n] as number
    if (run >= n) out[i] = s / n
  }
  return out
}
/** 指数均线：头 n 个有效值取简单平均当种子（与 calc.ts 的 ema 同一口径），中途的空值跳过、不断档 */
export function emaS(src: Series, n: number, alpha = 2 / (n + 1)): Series {
  const out: Series = new Array(src.length).fill(null)
  let e: number | null = null, s = 0, cnt = 0
  for (let i = 0; i < src.length; i++) {
    const x = src[i]
    if (x == null) { if (e == null) { s = 0; cnt = 0 } continue }
    if (e == null) { s += x; cnt++; if (cnt === n) { e = s / n; out[i] = e } continue }
    e = alpha * x + (1 - alpha) * e; out[i] = e
  }
  return out
}
/** 平滑均线（RMA / SMMA）：α = 1/n */
export const rmaS = (src: Series, n: number): Series => emaS(src, n, 1 / n)
/** 加权均线：越新的权重越大（1…n） */
export function wmaS(src: Series, n: number): Series {
  const out: Series = new Array(src.length).fill(null), ws = n * (n + 1) / 2
  for (let i = n - 1; i < src.length; i++) {
    let s = 0, ok = true
    for (let j = 0; j < n; j++) { const v = src[i - n + 1 + j]; if (v == null) { ok = false; break } s += v * (j + 1) }
    if (ok) out[i] = s / ws
  }
  return out
}
/** 最小二乘均线：过去 n 根做线性回归，取最新那一根上的回归值 */
export function linreg(src: Series, n: number): Series {
  const out: Series = new Array(src.length).fill(null)
  const sx = n * (n - 1) / 2, sxx = (n - 1) * n * (2 * n - 1) / 6, den = n * sxx - sx * sx
  for (let i = n - 1; i < src.length; i++) {
    let sy = 0, sxy = 0, ok = true
    for (let k = 0; k < n; k++) { const v = src[i - n + 1 + k]; if (v == null) { ok = false; break } sy += v; sxy += k * v }
    if (!ok) continue
    if (n === 1 || den === 0) { out[i] = sy / n; continue }
    const b = (n * sxy - sx * sy) / den, a = (sy - b * sx) / n
    out[i] = a + b * (n - 1)
  }
  return out
}
const sub = (a: Series, b: Series, ka = 1, kb = 1): Series => a.map((v, i) => { const w = b[i]; return v != null && w != null ? ka * v - kb * w : null })

export function trueRangeS(bars: Bar[]): number[] {
  return bars.map((b, i) => i === 0 ? b.h - b.l : Math.max(b.h - b.l, Math.abs(b.h - bars[i - 1].c), Math.abs(b.l - bars[i - 1].c)))
}

// ------------------------------------------------------------ 均线类
export function hma(c: Series, n: number): Series {
  const half = Math.max(1, Math.floor(n / 2)), sq = Math.max(1, Math.floor(Math.sqrt(n)))
  return wmaS(sub(wmaS(c, half), wmaS(c, n), 2, 1), sq)
}
export function dema(c: Series, n: number): Series { const e1 = emaS(c, n), e2 = emaS(e1, n); return sub(e1, e2, 2, 1) }
export function tema(c: Series, n: number): Series {
  const e1 = emaS(c, n), e2 = emaS(e1, n), e3 = emaS(e2, n)
  return e1.map((v, i) => { const b = e2[i], d = e3[i]; return v != null && b != null && d != null ? 3 * v - 3 * b + d : null })
}
/** 量加权均线：Σ(收 × 量) / Σ量，量用基础币成交量（没有就用成交额）；这段全是零量时回落到简单均线 */
export function vwma(bars: Bar[], n: number): Series {
  const out: Series = new Array(bars.length).fill(null)
  let pv = 0, vv = 0, cs = 0
  const vol = (b: Bar) => { const v = b.bv ?? b.v; return Number.isFinite(v) && v > 0 ? v : 0 }
  for (let i = 0; i < bars.length; i++) {
    const b = bars[i], v = vol(b); pv += b.c * v; vv += v; cs += b.c
    if (i >= n) { const o = bars[i - n], w = vol(o); pv -= o.c * w; vv -= w; cs -= o.c }
    if (i >= n - 1) out[i] = vv > 1e-12 ? pv / vv : cs / n
  }
  return out
}
/** 阿诺·勒古均线（ALMA）：高斯权重，offset 0.85 偏向新的一侧，sigma 6 */
export function alma(c: Series, n: number, offset = 0.85, sigma = 6): Series {
  const m = offset * (n - 1), s = n / sigma, w: number[] = []
  let norm = 0
  for (let k = 0; k < n; k++) { const x = Math.exp(-((k - m) ** 2) / (2 * s * s)); w.push(x); norm += x }
  const out: Series = new Array(c.length).fill(null)
  for (let i = n - 1; i < c.length; i++) {
    let sum = 0, ok = true
    for (let k = 0; k < n; k++) { const v = c[i - n + 1 + k]; if (v == null) { ok = false; break } sum += v * w[k] }
    if (ok) out[i] = sum / norm
  }
  return out
}
/** 麦金利动态线：mg + (价 − mg) / (n · (价 / mg)^4)，第一个值取 EMA */
export function mcginley(c: number[], n: number): Series {
  const e = emaS(c, n), out: Series = new Array(c.length).fill(null)
  let mg: number | null = null
  for (let i = 0; i < c.length; i++) {
    if (mg == null) { mg = e[i]; out[i] = mg; continue }
    const r: number = c[i] / mg
    mg = mg !== 0 && Number.isFinite(r) && r > 0 ? mg + (c[i] - mg) / (n * r ** 4) : c[i]
    out[i] = mg
  }
  return out
}

// ------------------------------------------------------------ 通道类
/** 肯特纳通道：中轨 EMA(n)，上下轨 ± ATR(10) × k（TradingView 默认「平均真实波幅」带宽） */
export function keltner(bars: Bar[], n: number, k: number): Series[] {
  const mid = emaS(bars.map(b => b.c), n), atr = rmaS(trueRangeS(bars), 10)
  const up = mid.map((m, i) => { const a = atr[i]; return m != null && a != null ? m + a * k : null })
  const dn = mid.map((m, i) => { const a = atr[i]; return m != null && a != null ? m - a * k : null })
  return [mid, up, dn]
}
/** 唐奇安通道：n 根最高、最低与两者中点 */
export function donchian(bars: Bar[], n: number): Series[] {
  const mid: Series = [], up: Series = [], dn: Series = []
  for (let i = 0; i < bars.length; i++) {
    if (i < n - 1) { mid.push(null); up.push(null); dn.push(null); continue }
    let hi = -Infinity, lo = Infinity
    for (let j = i - n + 1; j <= i; j++) { if (bars[j].h > hi) hi = bars[j].h; if (bars[j].l < lo) lo = bars[j].l }
    up.push(hi); dn.push(lo); mid.push((hi + lo) / 2)
  }
  return [mid, up, dn]
}
/** 包络线：简单均线上下各偏 k%（TradingView 默认 10%） */
export function envelope(c: number[], n: number, k: number): Series[] {
  const mid = smaS(c, n)
  return [mid, mid.map(m => m == null ? null : m * (1 + k / 100)), mid.map(m => m == null ? null : m * (1 - k / 100))]
}

// ------------------------------------------------------------ 趋势类
/** 抛物线 SAR：逐行照 TradingView 的 ta.sar（Pine 源码）移植 */
export function parabolicSar(bars: Bar[], start = 0.02, inc = 0.02, max = 0.2): Series {
  const out: Series = new Array(bars.length).fill(null)
  if (bars.length < 2) return out
  let result = 0, maxMin = 0, acc = start, below = false
  for (let i = 1; i < bars.length; i++) {
    const b = bars[i], p1 = bars[i - 1]
    let first = false
    if (i === 1) {
      if (b.c > p1.c) { below = true; maxMin = b.h; result = p1.l } else { below = false; maxMin = b.l; result = p1.h }
      first = true; acc = start
    }
    result = result + acc * (maxMin - result)
    if (below) {
      if (result > b.l) { first = true; below = false; result = Math.max(b.h, maxMin); maxMin = b.l; acc = start }
    } else if (result < b.h) { first = true; below = true; result = Math.min(b.l, maxMin); maxMin = b.h; acc = start }
    if (!first) {
      if (below) { if (b.h > maxMin) { maxMin = b.h; acc = Math.min(acc + inc, max) } }
      else if (b.l < maxMin) { maxMin = b.l; acc = Math.min(acc + inc, max) }
    }
    if (below) { result = Math.min(result, p1.l); if (i > 1) result = Math.min(result, bars[i - 2].l) }
    else { result = Math.max(result, p1.h); if (i > 1) result = Math.max(result, bars[i - 2].h) }
    out[i] = result
  }
  return out
}
/** 波动止损（TradingView「Volatility Stop」）：收盘 ∓ ATR(n) × k 的棘轮，收盘穿过就翻向。返回 [多头止损, 空头止损] */
export function volStop(bars: Bar[], n: number, k: number): Series[] {
  const len = bars.length, long: Series = new Array(len).fill(null), short: Series = new Array(len).fill(null)
  if (!len) return [long, short]
  const tr = trueRangeS(bars), atr = rmaS(tr, n)
  let hi = bars[0].c, lo = bars[0].c, up = true, stop: number | null = null
  for (let i = 0; i < len; i++) {
    const src = bars[i].c, a = atr[i], m = a != null ? a * k : tr[i]
    hi = Math.max(hi, src); lo = Math.min(lo, src)
    stop = stop == null ? src : up ? Math.max(stop, hi - m) : Math.min(stop, lo + m)
    const nu: boolean = src - stop >= 0
    if (nu !== up) { hi = src; lo = src; stop = nu ? hi - m : lo + m }
    up = nu
    if (up) long[i] = stop; else short[i] = stop
  }
  return [long, short]
}
/** 鳄鱼线：中价（高低平均）的平滑均线 13 / 8 / 5，各往右推 8 / 5 / 3 根（画到最新一根之后） */
export const ALLIGATOR: [number, number][] = [[13, 8], [8, 5], [5, 3]]
export function alligator(bars: Bar[]): Series[] {
  const hl2 = bars.map(b => (b.h + b.l) / 2)
  return ALLIGATOR.map(([n, shift]) => {
    const s = rmaS(hl2, n), out: Series = new Array(bars.length + shift).fill(null)
    for (let i = 0; i < s.length; i++) out[i + shift] = s[i]
    return out
  })
}
/** 威廉分形：中间那根的高（低）比左右各 n 根都高（低）。返回 [上分形的最高价, 下分形的最低价]，只在分形那根有值 */
export function fractals(bars: Bar[], n: number): Series[] {
  const up: Series = new Array(bars.length).fill(null), dn: Series = new Array(bars.length).fill(null)
  for (let i = n; i < bars.length - n; i++) {
    let isUp = true, isDn = true
    for (let k = 1; k <= n && (isUp || isDn); k++) {
      if (!(bars[i].h > bars[i - k].h && bars[i].h > bars[i + k].h)) isUp = false
      if (!(bars[i].l < bars[i - k].l && bars[i].l < bars[i + k].l)) isDn = false
    }
    if (isUp) up[i] = bars[i].h
    if (isDn) dn[i] = bars[i].l
  }
  return [up, dn]
}
/** 之字转向：深度 depth 的窗口里找高低点；同向的取更极端的，换向要偏离上一个转折 ≥ dev%。
 *  只在转折那根有值（画的时候把它们连起来，最后一段虚线连到最新收盘） */
export function zigzag(bars: Bar[], depth: number, dev: number): Series {
  const out: Series = new Array(bars.length).fill(null)
  const half = Math.max(1, Math.floor(depth / 2))
  const pts: { i: number; v: number; hi: boolean }[] = []
  const add = (i: number, v: number, hi: boolean) => {
    const last = pts[pts.length - 1]
    if (!last) { pts.push({ i, v, hi }); return }
    if (last.hi === hi) { if (hi ? v > last.v : v < last.v) pts[pts.length - 1] = { i, v, hi } ; return }
    if (Math.abs(v - last.v) / Math.abs(last.v || 1) * 100 >= dev) pts.push({ i, v, hi })
  }
  for (let i = half; i < bars.length - half; i++) {
    let isHi = true, isLo = true
    for (let j = i - half; j <= i + half && (isHi || isLo); j++) {
      if (j === i) continue
      if (bars[j].h > bars[i].h || (j > i && bars[j].h === bars[i].h)) isHi = false
      if (bars[j].l < bars[i].l || (j > i && bars[j].l === bars[i].l)) isLo = false
    }
    // 同一根既是高点又是低点（大阴大阳）：先接与上一个转折相反的那个
    const lastHi = pts[pts.length - 1]?.hi
    if (isHi && isLo) { if (lastHi) { add(i, bars[i].l, false); add(i, bars[i].h, true) } else { add(i, bars[i].h, true); add(i, bars[i].l, false) } }
    else if (isHi) add(i, bars[i].h, true)
    else if (isLo) add(i, bars[i].l, false)
  }
  for (const p of pts) out[p.i] = p.v
  return out
}

/** 枢轴点（经典）：P = (高 + 低 + 收) / 3，R1 = 2P − 低，S1 = 2P − 高，R2 = P + (高 − 低)，S2 = P − (高 − 低)，
 *  R3 = 高 + 2(P − 低)，S3 = 低 − 2(高 − P)。日内周期取前一天，日线取前一周，周线取前一月，再大取前一年（UTC 切分）。
 *  返回 [P, R1, S1, R2, S2, R3, S3]，每根上是它所在那段的价位 */
export const PIVOT_LABELS = ['P', 'R1', 'S1', 'R2', 'S2', 'R3', 'S3']
export function pivotLevels(h: number, l: number, c: number): number[] {
  const p = (h + l + c) / 3
  return [p, 2 * p - l, 2 * p - h, p + (h - l), p - (h - l), h + 2 * (p - l), l - 2 * (h - p)]
}
/** 这根 K 线所在那一段（天 / 周 / 月 / 年）的起点（ms） */
export function pivotPeriodStart(t: number, iv: number): number {
  if (iv < DAY) return Math.floor(t / DAY) * DAY
  if (iv < 7 * DAY) { const d = Math.floor(t / DAY); return (d - ((d + 3) % 7 + 7) % 7) * DAY } // 周一起
  const dt = new Date(t)
  if (iv < 28 * DAY) return Date.UTC(dt.getUTCFullYear(), dt.getUTCMonth(), 1)
  return Date.UTC(dt.getUTCFullYear(), 0, 1)
}
export function pivots(bars: Bar[], iv: number): Series[] {
  const out: Series[] = PIVOT_LABELS.map(() => new Array(bars.length).fill(null))
  if (!bars.length) return out
  let start = pivotPeriodStart(bars[0].t, iv)
  // 第一段要是只加载到一半（这段更早的 K 线没拿到），它的高低收不作数
  let complete = bars[0].t - start < iv
  let h = -Infinity, l = Infinity, c = 0, lv: number[] | null = null
  for (let i = 0; i < bars.length; i++) {
    const b = bars[i], s = pivotPeriodStart(b.t, iv)
    if (s !== start) {
      lv = complete && isFinite(h) ? pivotLevels(h, l, c) : null
      start = s; complete = true; h = -Infinity; l = Infinity
    }
    if (b.h > h) h = b.h
    if (b.l < l) l = b.l
    c = b.c
    if (lv) for (let k = 0; k < 7; k++) out[k][i] = lv[k]
  }
  return out
}
/** 估一个周期：相邻两根最小的正间隔 */
function guessIv(bars: Bar[]): number {
  let m = Infinity
  for (let i = 1; i < Math.min(bars.length, 12); i++) { const d = bars[i].t - bars[i - 1].t; if (d > 0 && d < m) m = d }
  return isFinite(m) ? m : 36e5
}

// ------------------------------------------------------------ 并进 Calc / CATALOG 的表
const closes = (bars: Bar[]) => bars.map(b => b.c)
export const MORE_MAIN_CALC: Record<MoreMainId, Fn> = {
  wma: (b, p) => [wmaS(closes(b), int(p.n, 20))],
  hma: (b, p) => [hma(closes(b), int(p.n, 20))],
  dema: (b, p) => [dema(closes(b), int(p.n, 20))],
  tema: (b, p) => [tema(closes(b), int(p.n, 20))],
  smma: (b, p) => [rmaS(closes(b), int(p.n, 7))],
  vwma: (b, p) => [vwma(b, int(p.n, 20))],
  lsma: (b, p) => [linreg(closes(b), int(p.n, 25))],
  alma: (b, p) => [alma(closes(b), int(p.n, 9))],
  mcg: (b, p) => [mcginley(closes(b), int(p.n, 14))],
  kc: (b, p) => keltner(b, int(p.n, 20), num(p.k, 2)),
  dc: (b, p) => donchian(b, int(p.n, 20)),
  env: (b, p) => envelope(closes(b), int(p.n, 20), num(p.k, 10)),
  sar: b => [parabolicSar(b)],
  vstop: (b, p) => volStop(b, int(p.n, 20), num(p.k, 2)),
  alligator: b => alligator(b),
  fractals: (b, p) => fractals(b, int(p.n, 2)),
  zigzag: (b, p) => [zigzag(b, int(p.n, 10), num(p.k, 5))],
  pivots: (b, _p, env) => pivots(b, env?.iv || guessIv(b)),
}

// 线色：照 TradingView 各指标的默认色。均线族在 TV 里默认都是同一个蓝（#2962FF），
// 但几条同时开时分不出谁是谁，所以各取 TV 调色板里一个不同的颜色（避开 MA / EMA 已经用掉的几种）。
const BLUE = '#2962FF', ORANGE = '#FF6D00', TV_RED = '#F23645', TV_GREEN = '#089981'
const BAND3 = ['中', '上', '下']
export const MORE_MAIN_CATALOG: Record<MoreMainId, CatalogEntry> = {
  wma: { name: '加权均线', cn: '', place: 'main', params: { n: 20 }, colors: ['#00BCD4'] },
  hma: { name: '赫尔均线', cn: '', place: 'main', params: { n: 20 }, colors: ['#9C27B0'] },
  dema: { name: '双重指数均线', cn: '', place: 'main', params: { n: 20 }, colors: ['#4CAF50'] },
  tema: { name: '三重指数均线', cn: '', place: 'main', params: { n: 20 }, colors: ['#E91E63'] },
  smma: { name: '平滑均线', cn: '', place: 'main', params: { n: 7 }, colors: ['#673AB7'] },
  vwma: { name: '量加权均线', cn: '', place: 'main', params: { n: 20 }, colors: ['#FF9800'] },
  lsma: { name: '最小二乘均线', cn: '', place: 'main', params: { n: 25 }, colors: ['#795548'] },
  alma: { name: '阿诺·勒古均线', cn: '', place: 'main', params: { n: 9 }, colors: ['#26A69A'] },
  mcg: { name: '麦金利动态线', cn: '', place: 'main', params: { n: 14 }, colors: ['#F06292'] },
  kc: { name: '肯特纳通道', cn: '', place: 'main', params: { n: 20, k: 2 }, colors: [BLUE, BLUE, BLUE], labels: BAND3 },
  dc: { name: '唐奇安通道', cn: '', place: 'main', params: { n: 20 }, colors: [ORANGE, BLUE, BLUE], labels: BAND3 },
  env: { name: '包络线', cn: '', place: 'main', params: { n: 20, k: 10 }, colors: [BLUE, BLUE, BLUE], labels: BAND3 },
  sar: { name: '抛物线 SAR', cn: '', place: 'main', params: {}, colors: [BLUE] },
  vstop: { name: '波动止损', cn: '', place: 'main', params: { n: 20, k: 2 }, colors: [TV_GREEN, TV_RED], labels: ['多', '空'] },
  alligator: { name: '鳄鱼线', cn: '', place: 'main', params: {}, colors: [BLUE, '#E91E63', '#66BB6A'], labels: ['颚', '齿', '唇'] },
  fractals: { name: '威廉分形', cn: '', place: 'main', params: { n: 2 }, colors: [TV_RED, TV_GREEN], labels: ['上', '下'] },
  zigzag: { name: '之字转向', cn: '', place: 'main', params: { n: 10, k: 5 }, colors: [BLUE] },
  // P 线深色底白、浅色底黑：目录里留空，画与图例时按主题取
  pivots: { name: '枢轴点', cn: '', place: 'main', params: {}, colors: ['', TV_RED, TV_GREEN, TV_RED, TV_GREEN, TV_RED, TV_GREEN], labels: PIVOT_LABELS },
}
/** 参数框里各项的叫法（同一个键在不同指标里意思不一样时用这张表） */
export const MORE_PARAM_NAME: Partial<Record<MoreMainId, Partial<Record<keyof IndParams, string>>>> = {
  env: { k: '偏移 %' },
  zigzag: { n: '深度', k: '偏差 %' },
}
