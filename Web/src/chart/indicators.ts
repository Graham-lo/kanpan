/* Hkline Web · 第二批指标（网页版大屏专有）
 *
 * 主图：VWAP（±1σ / ±2σ）、超级趋势、一目均衡表、成交量分布（VPVR，按可见区间现算，见 overlays.ts）、
 *       关键价位（昨高低、上周高低、今开、昨日控制点与价值区，见 keyLevels.ts）
 * 副图：CVD（主动买卖累计差；实时段三家、拆现货合约，见 tradeFlow.ts）、ATR、OBV、随机 RSI、CCI、威廉指标、
 *       大单与散户累计量差（见 tradeFlow.ts）
 *
 * 只从 calc.ts 拿类型，运行时不反向依赖它（calc.ts 把这里的表并进 Calc / CATALOG），
 * 所以 sma / ema / rma 在这里各留一份小实现。
 */
import type { Bar, Series, IndParams, CatalogEntry, CalcEnv } from './calc'
import { calcCvd, calcWhale } from './tradeFlow'

export type ExtraMainId = 'vwap' | 'st' | 'ichi' | 'vpvr' | 'keys'
export type ExtraSubId = 'cvd' | 'atr' | 'obv' | 'stochrsi' | 'cci' | 'wr' | 'whale'
type Fn = (bars: Bar[], p: IndParams, env?: CalcEnv) => Series[]

// ------------------------------------------------------------ 小工具
function smaN(src: number[], n: number): Series {
  const out: Series = new Array(src.length).fill(null); let s = 0
  for (let i = 0; i < src.length; i++) { s += src[i]; if (i >= n) s -= src[i - n]; if (i >= n - 1) out[i] = s / n }
  return out
}
function smaS(src: Series, n: number): Series {
  const out: Series = new Array(src.length).fill(null)
  for (let i = 0; i < src.length; i++) {
    if (i < n - 1) continue
    let s = 0, ok = true
    for (let j = i - n + 1; j <= i; j++) { const v = src[j]; if (v == null) { ok = false; break } s += v }
    if (ok) out[i] = s / n
  }
  return out
}
function rmaN(src: number[], n: number): Series {
  const out: Series = new Array(src.length).fill(null); let r = 0, s = 0
  for (let i = 0; i < src.length; i++) {
    if (i < n) { s += src[i]; if (i === n - 1) { r = s / n; out[i] = r } continue }
    r = (r * (n - 1) + src[i]) / n; out[i] = r
  }
  return out
}
function hiLo(bars: Bar[], i: number, n: number): [number, number] {
  let hi = -Infinity, lo = Infinity
  for (let j = Math.max(0, i - n + 1); j <= i; j++) { hi = Math.max(hi, bars[j].h); lo = Math.min(lo, bars[j].l) }
  return [hi, lo]
}
const int = (v: number | undefined, d: number): number => Math.max(1, Math.round(v && v > 0 ? v : d))

/** 真实波幅 */
export function trueRange(bars: Bar[]): number[] {
  return bars.map((b, i) => i === 0 ? b.h - b.l : Math.max(b.h - b.l, Math.abs(b.h - bars[i - 1].c), Math.abs(b.l - bars[i - 1].c)))
}

/** 相邻两根的间隔（ms）：取前几段里最小的正间隔，断档不影响 */
export function barInterval(bars: Bar[]): number {
  let m = Infinity
  for (let i = 1; i < Math.min(bars.length, 12); i++) { const d = bars[i].t - bars[i - 1].t; if (d > 0 && d < m) m = d }
  return isFinite(m) ? m : 36e5
}

/** 一根 K 线的主动买卖差（报价币计）：多交易所聚合时把各家加起来，只有币安时 = 2 × 主动买入 − 总成交额 */
export function barDelta(b: Bar): number {
  if (b.venueDelta) { let s = 0; for (const v of Object.values(b.venueDelta)) s += v || 0; return s }
  if (b.tb == null || !isFinite(b.tb)) return 0
  return 2 * b.tb - b.v
}

// ------------------------------------------------------------ VWAP
/** VWAP 的锚：一小时以下按天（上海 8:00 = UTC 0 点换日，和日线一致）、一天以下按周、日线按月、再往上按年 */
export function vwapAnchor(t: number, iv: number): number {
  const d = new Date(t)
  if (iv < 36e5) return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate())
  if (iv < 864e5) { const day = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()); return day - ((d.getUTCDay() + 6) % 7) * 864e5 }
  if (iv < 2 * 864e5) return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1)
  return Date.UTC(d.getUTCFullYear(), 0, 1)
}

/** VWAP 与 ±1σ、±2σ：典型价 (高+低+收)/3，按成交量（币）加权；锚点一到就从头累计。
 *  第一段不完整就不画：加载进来的第一根如果不是它那一段的开头（前一根还属于同一段），这一段的累计缺了开头，
 *  输出 null，直到下一个锚点——这样往左加载更多历史时，已经画出来的值一个都不变。 */
export function vwap(bars: Bar[], iv = barInterval(bars)): Series[] {
  const n = bars.length
  const mid: Series = new Array(n).fill(null), u1: Series = new Array(n).fill(null), d1: Series = new Array(n).fill(null), u2: Series = new Array(n).fill(null), d2: Series = new Array(n).fill(null)
  let anchor = NaN, sw = 0, swp = 0, swp2 = 0
  // 第一根正好是一段的开头（它的前一根落在上一段里）时，第一段也是完整的
  let whole = n > 0 && vwapAnchor(bars[0].t - iv, iv) !== vwapAnchor(bars[0].t, iv)
  for (let i = 0; i < n; i++) {
    const b = bars[i], a = vwapAnchor(b.t, iv)
    if (a !== anchor) { if (i > 0) whole = true; anchor = a; sw = 0; swp = 0; swp2 = 0 }
    if (!whole) continue
    const tp = (b.h + b.l + b.c) / 3
    const w = b.bv != null && isFinite(b.bv) ? b.bv : b.c > 0 ? b.v / b.c : 0
    sw += w; swp += w * tp; swp2 += w * tp * tp
    if (sw <= 0) continue
    const m = swp / sw, sd = Math.sqrt(Math.max(0, swp2 / sw - m * m))
    mid[i] = m; u1[i] = m + sd; d1[i] = m - sd; u2[i] = m + 2 * sd; d2[i] = m - 2 * sd
  }
  return [mid, u1, d1, u2, d2]
}

// ------------------------------------------------------------ 超级趋势
/** 超级趋势：[多头时的线, 空头时的线]，同一根只有一条有值 */
export function supertrend(bars: Bar[], n: number, k: number): Series[] {
  const len = bars.length, atr = rmaN(trueRange(bars), n)
  const up: Series = new Array(len).fill(null), dn: Series = new Array(len).fill(null)
  let fu = 0, fl = 0, dir = 1
  for (let i = 0; i < len; i++) {
    const a = atr[i]; if (a == null) continue
    const b = bars[i], hl2 = (b.h + b.l) / 2
    let bu = hl2 + k * a, bl = hl2 - k * a
    if (up[i - 1] != null || dn[i - 1] != null) {
      const pc = bars[i - 1].c
      bu = bu < fu || pc > fu ? bu : fu
      bl = bl > fl || pc < fl ? bl : fl
      if (dir === 1 && b.c < bl) dir = -1
      else if (dir === -1 && b.c > bu) dir = 1
    } else dir = b.c >= hl2 ? 1 : -1
    fu = bu; fl = bl
    if (dir === 1) up[i] = bl; else dn[i] = bu
  }
  return [up, dn]
}

// ------------------------------------------------------------ 一目均衡表
/** [转换线, 基准线, 先行 A, 先行 B, 迟行]；先行带往右挪 kijun 根（序列比 K 线多出 kijun 格），迟行往左挪 kijun 根 */
export function ichimoku(bars: Bar[], tenkan: number, kijun: number, senkou: number): Series[] {
  const n = bars.length
  const mid = (i: number, len: number): number | null => { if (i < len - 1) return null; const [h, l] = hiLo(bars, i, len); return (h + l) / 2 }
  const conv: Series = [], base: Series = []
  for (let i = 0; i < n; i++) { conv.push(mid(i, tenkan)); base.push(mid(i, kijun)) }
  const a: Series = new Array(n + kijun).fill(null), b: Series = new Array(n + kijun).fill(null)
  for (let i = 0; i < n; i++) {
    const c = conv[i], k = base[i]
    if (c != null && k != null) a[i + kijun] = (c + k) / 2
    b[i + kijun] = mid(i, senkou)
  }
  const lag: Series = new Array(n).fill(null)
  for (let i = kijun; i < n; i++) lag[i - kijun] = bars[i].c
  return [conv, base, a, b, lag]
}

// ------------------------------------------------------------ 副图
/** CVD（只看 K 线自带的主动买入）：从第一根加载进来的 K 线起，逐根累加主动买卖差。图上用的是 tradeFlow.calcCvd（实时段加三家） */
export function cvd(bars: Bar[]): Series[] {
  let s = 0
  return [bars.map(b => (s += barDelta(b)))]
}
export function atr(bars: Bar[], n: number): Series[] { return [rmaN(trueRange(bars), n)] }
export function obv(bars: Bar[]): Series[] {
  let s = 0
  return [bars.map((b, i) => { if (i > 0) s += b.c > bars[i - 1].c ? b.v : b.c < bars[i - 1].c ? -b.v : 0; return s })]
}
function rsiOf(c: number[], n: number): Series {
  const up = [0], dn = [0]
  for (let i = 1; i < c.length; i++) { const d = c[i] - c[i - 1]; up.push(Math.max(d, 0)); dn.push(Math.max(-d, 0)) }
  const ru = rmaN(up, n), rd = rmaN(dn, n)
  return c.map((_, i) => { const u = ru[i], d = rd[i]; return u == null || d == null ? null : d === 0 ? 100 : 100 - 100 / (1 + u / d) })
}
/** 随机 RSI：RSI 在 stoch 根里的位置（0–100），K 取 m1 根均值、D 再取 m2 根均值 */
export function stochRsi(bars: Bar[], n: number, stoch: number, m1: number, m2: number): Series[] {
  const r = rsiOf(bars.map(b => b.c), n)
  const raw: Series = r.map((v, i) => {
    if (v == null || i < stoch - 1) return null
    let hi = -Infinity, lo = Infinity
    for (let j = i - stoch + 1; j <= i; j++) { const x = r[j]; if (x == null) return null; hi = Math.max(hi, x); lo = Math.min(lo, x) }
    return hi === lo ? 0 : (v - lo) / (hi - lo) * 100
  })
  const k = smaS(raw, m1)
  return [k, smaS(k, m2)]
}
/** CCI：(典型价 − 均值) / (0.015 × 平均绝对偏差) */
export function cci(bars: Bar[], n: number): Series[] {
  const tp = bars.map(b => (b.h + b.l + b.c) / 3), m = smaN(tp, n)
  return [tp.map((v, i) => {
    const mm = m[i]; if (mm == null) return null
    let md = 0; for (let j = i - n + 1; j <= i; j++) md += Math.abs(tp[j] - mm)
    md /= n
    return md === 0 ? 0 : (v - mm) / (0.015 * md)
  })]
}
/** 威廉指标：−100 × (最高 − 收) / (最高 − 最低)，范围 −100 到 0 */
export function williams(bars: Bar[], n: number): Series[] {
  return [bars.map((b, i) => {
    if (i < n - 1) return null
    const [h, l] = hiLo(bars, i, n)
    return h === l ? -50 : -100 * (h - b.c) / (h - l)
  })]
}

// ------------------------------------------------------------ 并进 Calc / CATALOG 的表
export const EXTRA_CALC: Record<ExtraMainId | ExtraSubId, Fn> = {
  vwap: (bars, _p, env) => vwap(bars, env?.iv || barInterval(bars)),
  st: (bars, p) => supertrend(bars, int(p.n, 10), p.k && p.k > 0 ? p.k : 3),
  ichi: (bars, p) => ichimoku(bars, int(p.tenkan, 9), int(p.kijun, 26), int(p.senkou, 52)),
  vpvr: () => [],
  keys: () => [],
  cvd: (bars, _p, env) => calcCvd(bars, env),
  atr: (bars, p) => atr(bars, int(p.n, 14)),
  obv: bars => obv(bars),
  stochrsi: (bars, p) => stochRsi(bars, int(p.n, 14), int(p.stoch, 14), int(p.m1, 3), int(p.m2, 3)),
  cci: (bars, p) => cci(bars, int(p.n, 20)),
  wr: (bars, p) => williams(bars, int(p.n, 14)),
  whale: (bars, _p, env) => calcWhale(bars, env),
}

export const EXTRA_CATALOG: Record<ExtraMainId | ExtraSubId, CatalogEntry> = {
  vwap: { name: '成交均价', cn: '按成交量加权、每天零点重算，带一倍与两倍标准差', place: 'main', params: {}, colors: ['#2962FF', '#26A69A', '#26A69A', '#FF9800', '#FF9800'] },
  st: { name: '超级趋势', cn: '按真实波幅翻转的趋势线', place: 'main', params: { n: 10, k: 3 }, colors: ['#089981', '#F23645'] },
  ichi: { name: '一目均衡表', cn: '转换线、基准线、云带、迟行线', place: 'main', params: { tenkan: 9, kijun: 26, senkou: 52 }, colors: ['#2962FF', '#B71C1C', '#43A047', '#F44336', '#9C27B0'] },
  vpvr: { name: '成交量分布', cn: '看得见的这段里各价位成交多少，含控制点与七成价值区', place: 'main', params: { n: 48 }, colors: [] },
  keys: { name: '关键价位', cn: '昨高低、上周高低、今开，昨日控制点与七成价值区（未回踩的才延伸）', place: 'main', params: {}, colors: [] },
  cvd: { name: '累计量差', cn: '主动买入减主动卖出逐根累加；实时段加上 OKX、Coinbase，拆现货、合约', place: 'sub', params: {}, colors: ['#2962FF', '#06B6D4', '#8B5CF6'], labels: ['', '现货', '合约'] },
  atr: { name: '真实波幅', cn: '平均真实波幅', place: 'sub', params: { n: 14 }, colors: ['#B71C1C'] },
  obv: { name: '能量潮', cn: '涨加跌减的累计成交额', place: 'sub', params: {}, colors: ['#2962FF'] },
  stochrsi: { name: '随机强弱', cn: '相对强弱再取随机值', place: 'sub', params: { n: 14, stoch: 14, m1: 3, m2: 3 }, colors: ['#2962FF', '#FF6D00'] },
  cci: { name: '顺势指标', cn: '偏离均价的程度', place: 'sub', params: { n: 20 }, colors: ['#2962FF'] },
  wr: { name: '威廉指标', cn: '收盘在区间里的位置', place: 'sub', params: { n: 14 }, colors: ['#7E57C2'] },
  whale: { name: '大单与散户累计量差', cn: '三家成交里大单、散户各自的主动买减主动卖，逐根累加', place: 'sub', params: {}, colors: ['#F7A600', '#26A69A'], labels: ['大单', '散户'] },
}

/** 固定刻度的副图（不随可见数据伸缩） */
export const SUB_FIXED: Partial<Record<ExtraSubId, { min: number; max: number }>> = {
  stochrsi: { min: 0, max: 100 },
  wr: { min: -100, max: 0 },
}
/** 副图上的参考线 */
export const SUB_LEVELS: Partial<Record<ExtraSubId, number[]>> = {
  stochrsi: [80, 20],
  wr: [-20, -80],
  cci: [100, -100],
}
