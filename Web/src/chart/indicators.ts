/* Hkline Web · 第二批指标（网页版大屏专有）
 *
 * 主图：VWAP（±1σ / ±2σ）、超级趋势、一目均衡表、成交量分布（VPVR，按可见区间现算，见 overlays.ts）、
 *       关键价位（昨高低、上周高低、今开、昨日控制点与价值区，见 keyLevels.ts）
 * 副图：CVD（主动买卖累计差；实时段各家、拆现货合约，见 tradeFlow.ts）、ATR、OBV、随机 RSI、CCI、威廉指标、
 *       大单与散户累计量差（见 tradeFlow.ts）
 *
 * 只从 calc.ts 拿类型，运行时不反向依赖它（calc.ts 把这里的表并进 Calc / CATALOG），
 * 所以 sma / ema / rma 在这里各留一份小实现。
 */
import type { Bar, Series, IndParams, CatalogEntry, CalcEnv } from './calc'
import { calcCvd, calcWhale } from './tradeFlow'
import * as Osc from './oscillators'
import { shared } from './sharedIndicators'

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
const DAY = 864e5
/** UTC 月序号（年 × 12 + 月），整数算术不走 Date（同手机网页 utcMonthIndex 的口径；结果只用来比相等） */
function monthIndex(t: number): number {
  const z = Math.floor(t / DAY) + 719468, era = Math.floor(z / 146097), doe = z - era * 146097
  const yoe = Math.floor((doe - Math.floor(doe / 1460) + Math.floor(doe / 36524) - Math.floor(doe / 146096)) / 365)
  const doy = doe - (365 * yoe + Math.floor(yoe / 4) - Math.floor(yoe / 100)), mp = Math.floor((5 * doy + 2) / 153)
  const m = mp < 10 ? mp + 3 : mp - 9
  return (yoe + era * 400 + (m <= 2 ? 1 : 0)) * 12 + m
}
/** VWAP 的锚（累计从哪儿归零），三端同一张表（iOS startsAnchorPeriod、手机网页 m/indicator/engine.ts）：
 *  一天以下的周期按 UTC 日（上海 8:00 换日，和日线一致）、一周以下（日线、三日线）按自然月、
 *  一年以下（周线、月线）按自然年、再往上不归零。同一套指标参数跟人走、各端同步，同一根 K 线上的数就得一样。
 *  返回值只拿来比相等：同一段的根返回同一个数。纯算术——每次重算每根都要调一次 */
export function vwapAnchor(t: number, iv: number): number {
  if (iv < DAY) return Math.floor(t / DAY) * DAY
  if (iv < 7 * DAY) return monthIndex(t)
  if (iv < 365 * DAY) return Math.floor((monthIndex(t) - 1) / 12)
  return 0
}

/** 一根 K 线在成交均价里的权重（币数）：有基础币成交量用它，没有（或解析坏了）就拿成交额 / 收盘价折。
 *  坏量（NaN、Infinity、负数）、坏价返回 NaN：这一根留白、累计原样往下传——进了累计的话这一段往后整段都是 NaN
 *  （手机网页 / iOS 同口径，见 m/indicator/engine.ts VWAPState） */
export function vwapWeight(b: Bar): number {
  const w = b.bv != null && Number.isFinite(b.bv) ? b.bv : b.c > 0 ? b.v / b.c : NaN
  return Number.isFinite(w) && w >= 0 && Number.isFinite(b.h + b.l + b.c) ? w : NaN
}

/** VWAP 与 ±1σ、±2σ：典型价 (高+低+收)/3，按成交量（币）加权；锚点一到就从头累计。
 *  这一段到目前为止全是零成交时退回典型价（不出空、不除零），和 iOS 一致。
 *  第一段不完整就不画（PC 自己的显示规则）：加载进来的第一根如果不是它那一段的开头（前一根还属于同一段），
 *  这一段的累计缺了开头，输出 null，直到下一个锚点——这样往左加载更多历史时，已经画出来的值一个都不变。
 *  不归零的周期（一年以上）一次载齐全部历史，第一段就是完整的。 */
export function vwap(bars: Bar[], iv = barInterval(bars)): Series[] {
  const n = bars.length
  const mid: Series = new Array(n).fill(null), u1: Series = new Array(n).fill(null), d1: Series = new Array(n).fill(null), u2: Series = new Array(n).fill(null), d2: Series = new Array(n).fill(null)
  let anchor = NaN, sw = 0, swp = 0, swp2 = 0
  // 第一根正好是一段的开头（它的前一根落在上一段里）时，第一段也是完整的
  let whole = n > 0 && (iv >= 365 * DAY || vwapAnchor(bars[0].t - iv, iv) !== vwapAnchor(bars[0].t, iv))
  for (let i = 0; i < n; i++) {
    const b = bars[i], a = vwapAnchor(b.t, iv)
    if (a !== anchor) { if (i > 0) whole = true; anchor = a; sw = 0; swp = 0; swp2 = 0 }
    if (!whole) continue
    const tp = (b.h + b.l + b.c) / 3, w = vwapWeight(b)
    if (Number.isNaN(w)) continue
    sw += w; swp += w * tp; swp2 += w * tp * tp
    const m = sw > 0 ? swp / sw : tp, sd = sw > 0 ? Math.sqrt(Math.max(0, swp2 / sw - m * m)) : 0
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
/** CVD（只看 K 线自带的主动买入）：从第一根加载进来的 K 线起，逐根累加主动买卖差。图上用的是 tradeFlow.calcCvd（实时段加各家） */
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
  vwap: { ...shared('vwap'), cn: '', place: 'main', colors: ['#2962FF', '#4CAF50', '#4CAF50', '#808000', '#808000'] },
  st: { ...shared('st'), cn: '', place: 'main', colors: ['#4CAF50', '#F23645'] },
  ichi: { name: '一目均衡表', cn: '', place: 'main', params: { tenkan: 9, kijun: 26, senkou: 52 }, colors: ['#2962FF', '#B71C1C', '#A5D6A7', '#EF9A9A', '#43A047'] },
  vpvr: { name: '成交量分布', cn: '', place: 'main', params: {}, colors: [] },
  keys: { name: '关键价位', cn: '', place: 'main', params: {}, colors: [] },
  cvd: { ...shared('cvd'), cn: '', place: 'sub', colors: ['#2962FF', '#06B6D4', '#8B5CF6'], labels: ['', '现货', '合约'] },
  atr: { ...shared('atr'), cn: '', place: 'sub', colors: ['#B71C1C'] },
  obv: { name: '能量潮', cn: '', place: 'sub', params: {}, colors: ['#2962FF'] },
  stochrsi: { ...shared('stochrsi'), cn: '', place: 'sub', colors: ['#2962FF', '#FF6D00'] },
  cci: { name: '顺势指标', cn: '', place: 'sub', params: { n: 20 }, colors: ['#2962FF'] },
  wr: { name: '威廉指标', cn: '', place: 'sub', params: { n: 14 }, colors: ['#7E57C2'] },
  whale: { name: '大单与散户累计量差', cn: '', place: 'sub', params: {}, colors: ['#F7A600', '#26A69A'], labels: ['大单', '散户'] },
}

/** 固定刻度的副图（不随可见数据伸缩） */
export const SUB_FIXED: Partial<Record<ExtraSubId, { min: number; max: number }>> = {
  stochrsi: { min: 0, max: 100 },
  wr: { min: -100, max: 0 },
}
/** 副图上的参考线 */
export const SUB_LEVELS: Partial<Record<ExtraSubId, number[]>> = {
  stochrsi: [80, 50, 20],
  wr: [-20, -50, -80],
  cci: [100, 0, -100],
}
/** 两条参考线之间铺一层底色（照 TradingView：随机 RSI、CCI、威廉指标的上下轨之间 10% 填充，色在 subBandFills 里查） */
export const SUB_BAND: Partial<Record<ExtraSubId, [number, number]>> = {
  stochrsi: [80, 20],
  wr: [-20, -80],
  cci: [100, -100],
}

// ------------------------------------------------------------ 副图画法查表：第二批（这里）与第三批（oscillators.ts）合在一起查
/** 副图每条序列的画法：line 折线 · hist 零轴柱（正涨色负跌色）· hist4 MACD 式四色柱 · histTrend 比上一根高绿低红的柱 ·
 *  area 零轴填充加线 · dots 小圆点 */
export type SubStyle = 'line' | 'hist' | 'hist4' | 'histTrend' | 'area' | 'dots'
type Lookup<T> = Partial<Record<string, T>>
// OSC_BAND 是 oscillators.ts 后加的表：没有它时当空表（另一路还在写那个文件）
export const subFixed = (id: string): { min: number; max: number } | undefined => (SUB_FIXED as Lookup<{ min: number; max: number }>)[id] ?? (Osc.OSC_FIXED as Lookup<{ min: number; max: number }>)[id]
/** 第二、三批副图的参考线数值（样式由 subLevelLines 定） */
export const oscLevels = (id: string): number[] | undefined => (Osc.OSC_LEVELS as Lookup<number[]>)[id]
export const subLevels = (id: string): number[] | undefined => (SUB_LEVELS as Lookup<number[]>)[id] ?? oscLevels(id)
export const subBand = (id: string): [number, number] | undefined => (SUB_BAND as Lookup<[number, number]>)[id] ?? (Osc.OSC_BAND as Lookup<[number, number]>)[id]
export const subStyles = (id: string): readonly SubStyle[] | undefined => (Osc.OSC_STYLE as Lookup<readonly SubStyle[]>)[id]

// ------------------------------------------------------------ 副图参考线与底色的样式：照 TradingView 内置指标（pine-facade STD;*）的默认 hline / fill
/** TV hline 的默认色；中线（50 / 0）多是它的 50% 透明 */
export const TV_HLINE = '#787B86'
const MID = { color: 'rgba(120,123,134,0.5)' }
export interface LevelLine { v: number; color: string; dash: 'dashed' | 'dotted' }
/** 核心副图（calc.ts 的 RSI / MACD）的参考线，和第二、三批的表放在一起查 */
const CORE_LEVELS: Lookup<number[]> = { rsi: [70, 50, 30], macd: [0] }
const CORE_BAND: Lookup<[number, number]> = { rsi: [70, 30] }
/** 个别 hline 的样式例外（其余一律 #787B86、hline.style_dashed 1 px） */
const LEVEL_STYLE: Lookup<Record<string, Partial<Omit<LevelLine, 'v'>>>> = {
  rsi: { 50: MID }, macd: { 0: MID }, stoch: { 50: MID }, stochrsi: { 50: MID }, cci: { 0: MID }, mfi: { 50: MID },
  chop: { 50: MID }, rvi: { 50: MID }, crsi: { 50: MID }, smi: { 0: MID }, ppo: { 0: MID },
  wr: { [-50]: { dash: 'dotted' } },
  fisher: { 1.5: { color: '#E91E63' }, 0: { color: '#E91E63' }, [-1.5]: { color: '#E91E63' } },
  bbpct: { 1: { color: 'rgba(242,54,69,0.5)' }, 0.5: { color: 'rgba(41,98,255,0.5)' }, 0: { color: 'rgba(8,153,129,0.5)' } },
}
/** 一个副图要画的参考线（值、色、虚实） */
export const subLevelLines = (id: string): LevelLine[] =>
  (CORE_LEVELS[id] ?? subLevels(id) ?? []).map(v => ({ v, color: TV_HLINE, dash: 'dashed' as const, ...LEVEL_STYLE[id]?.[String(v)] }))
/** TV 的两种带底色：#2196F3 10%（随机、随机 RSI、CCI、波动指数、康纳 RSI）与 #7E57C2 10%（RSI、资金流量、相对波动、威廉） */
const BLUE_BAND = 'rgba(33,150,243,0.1)', PURPLE_BAND = 'rgba(126,87,194,0.1)'
const BAND_COLOR: Lookup<string> = { rsi: PURPLE_BAND, mfi: PURPLE_BAND, rvi: PURPLE_BAND, wr: PURPLE_BAND, smi: 'rgba(41,98,255,0.1)', bbpct: 'rgba(41,98,255,0.1)' }
export interface BandFill { a: number; b: number; color: string }
/** 一个副图要铺的底色带：[a, b] 两个值之间。布林 %B 照 TV 三段：1 以上红、0–1 蓝、0 以下绿（TV 用藏起来的 ±100 hline 当外沿） */
export function subBandFills(id: string): BandFill[] {
  const band = CORE_BAND[id] ?? subBand(id)
  if (!band) return []
  const out: BandFill[] = [{ a: band[0], b: band[1], color: BAND_COLOR[id] ?? BLUE_BAND }]
  if (id === 'bbpct') out.push({ a: 100, b: band[0], color: 'rgba(242,54,69,0.1)' }, { a: band[1], b: -100, color: 'rgba(8,153,129,0.1)' })
  return out
}
