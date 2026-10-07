/* Hkline Web · 技术指标提醒（均线交叉 · RSI · 突破）
 *
 * 三种条件，线格式和服务端约定死（字段名不改，见 PROJECT.md §46 / §47）：
 *   {"kind":"ma_cross","interval":"15m","fast":{"ma":"ema","period":9},"slow":{"ma":"sma","period":21},"direction":"up"}
 *   {"kind":"rsi_level","interval":"1h","period":14,"level":70,"direction":"up"}
 *   {"kind":"bar_breakout","interval":"4h","bars":20,"direction":"up"}
 * 整个对象放在提醒记录的 `rule` 里（提醒本身是 kind:"condition"，和资金费率 / 持仓量条件并列）。
 * 只在这个周期的 K 线收盘时判、只响一次。口径照 TradingView：
 *   上穿 = 这一根 a > b 且上一根 a <= b；下穿 = 这一根 a < b 且上一根 a >= b（恰好相等不算穿越）；
 *   突破 = 收盘 > 前 N 根（不含这一根）最高价的最大值；跌破 = 收盘 < 前 N 根最低价的最小值。
 *   均线 / RSI 的算法用图上那份（chart/calc.ts：SMA、SMA 起种的 EMA、Wilder RSI），图上看到的穿越和这里判的是同一个。
 *
 * 全是纯函数（校验、文案、判定、预填），单测直接调；页面开着时的收盘判定循环在 panel.ts。
 * 登录着服务端也判（谁先判到谁响，响了就删，不会响两次）；没登录 / 服务端还不认时只靠本页。
 */
import { CATALOG, Calc, ema, sma, type Bar, type IndParams, type Series } from '../chart/calc'

export const IND_INTERVALS = ['1m', '5m', '15m', '30m', '1h', '4h', '1d'] as const
export type IndInterval = typeof IND_INTERVALS[number]
export type MaType = 'sma' | 'ema'
export type Direction = 'up' | 'down'
export interface MaLine { ma: MaType; period: number }
/** `type?: undefined`：和老条件（`{type:'funding',…}`）同在一个联合里时还能直接读 `.type` */
export interface MaCrossRule { kind: 'ma_cross'; interval: IndInterval; fast: MaLine; slow: MaLine; direction: Direction; type?: undefined }
export interface RsiLevelRule { kind: 'rsi_level'; interval: IndInterval; period: number; level: number; direction: Direction; type?: undefined }
export interface BarBreakoutRule { kind: 'bar_breakout'; interval: IndInterval; bars: number; direction: Direction; type?: undefined }
export type IndicatorRule = MaCrossRule | RsiLevelRule | BarBreakoutRule
export type IndicatorKind = IndicatorRule['kind']
export const INDICATOR_KINDS: readonly IndicatorKind[] = ['ma_cross', 'rsi_level', 'bar_breakout']

export const IV_MS_IND: Record<IndInterval, number> = { '1m': 60e3, '5m': 300e3, '15m': 900e3, '30m': 1800e3, '1h': 36e5, '4h': 144e5, '1d': 864e5 }
export const PERIOD_MIN = 2, PERIOD_MAX = 500, LEVEL_MIN = 1, LEVEL_MAX = 99

/** 默认值：EMA9 / SMA21 金叉、RSI 14 上穿 70、20 根上破 */
export const DEFAULT_FAST: MaLine = { ma: 'ema', period: 9 }
export const DEFAULT_SLOW: MaLine = { ma: 'sma', period: 21 }
export const DEFAULT_RSI = 14
export const DEFAULT_LEVEL = 70
export const DEFAULT_BARS = 20

// ------------------------------------------------------------ 形状与校验
const isObj = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v)
export const isIndicatorRule = (r: unknown): r is IndicatorRule =>
  isObj(r) && typeof r.kind === 'string' && (INDICATOR_KINDS as readonly string[]).includes(r.kind)
const intIn = (v: unknown, lo: number, hi: number): v is number => typeof v === 'number' && Number.isInteger(v) && v >= lo && v <= hi
const okIv = (v: unknown): v is IndInterval => typeof v === 'string' && (IND_INTERVALS as readonly string[]).includes(v)
const okDir = (v: unknown): v is Direction => v === 'up' || v === 'down'
const okMa = (v: unknown): v is MaType => v === 'sma' || v === 'ema'

const KEYS: Record<IndicatorKind, string[]> = {
  ma_cross: ['kind', 'interval', 'fast', 'slow', 'direction'],
  rsi_level: ['kind', 'interval', 'period', 'level', 'direction'],
  bar_breakout: ['kind', 'interval', 'bars', 'direction'],
}
/** 这条条件哪里不对（中文，给人看）；对就 null。多给的字段也算不对：线上只认约定的那几个键 */
export function indicatorRuleError(r: unknown): string | null {
  if (!isIndicatorRule(r)) return '认不出这种条件'
  const o = r as unknown as Record<string, unknown>
  if (Object.keys(o).some(k => !KEYS[r.kind].includes(k))) return '条件里有多余的字段'
  if (!okIv(o.interval)) return `周期只能选 ${IND_INTERVALS.join(' ')}`
  if (!okDir(o.direction)) return '方向只能是上或下'
  if (r.kind === 'ma_cross') {
    for (const [name, l] of [['快线', o.fast], ['慢线', o.slow]] as const) {
      if (!isObj(l) || Object.keys(l).some(k => k !== 'ma' && k !== 'period') || !okMa(l.ma)) return `${name}只能是简单均线或指数均线`
      if (!intIn(l.period, PERIOD_MIN, PERIOD_MAX)) return `${name}长度填 ${PERIOD_MIN} 到 ${PERIOD_MAX} 的整数`
    }
    const f = o.fast as MaLine, s = o.slow as MaLine
    if (f.ma === s.ma && f.period === s.period) return '快线和慢线不能一样'
    return null
  }
  if (r.kind === 'rsi_level') {
    if (!intIn(o.period, PERIOD_MIN, PERIOD_MAX)) return `RSI 长度填 ${PERIOD_MIN} 到 ${PERIOD_MAX} 的整数`
    if (!intIn(o.level, LEVEL_MIN, LEVEL_MAX)) return `水平填 ${LEVEL_MIN} 到 ${LEVEL_MAX} 的整数`
    return null
  }
  if (!intIn(o.bars, PERIOD_MIN, PERIOD_MAX)) return `根数填 ${PERIOD_MIN} 到 ${PERIOD_MAX} 的整数`
  return null
}
export const indicatorRuleOk = (r: unknown): r is IndicatorRule => indicatorRuleError(r) == null

/** 构造：键序固定、只放约定的字段（线上一字不差） */
export function maCrossRule(interval: IndInterval, fast: MaLine, slow: MaLine, direction: Direction): MaCrossRule {
  return { kind: 'ma_cross', interval, fast: { ma: fast.ma, period: fast.period }, slow: { ma: slow.ma, period: slow.period }, direction }
}
export const rsiLevelRule = (interval: IndInterval, period: number, level: number, direction: Direction): RsiLevelRule =>
  ({ kind: 'rsi_level', interval, period, level, direction })
export const barBreakoutRule = (interval: IndInterval, bars: number, direction: Direction): BarBreakoutRule =>
  ({ kind: 'bar_breakout', interval, bars, direction })

// ------------------------------------------------------------ 文案
export const maName = (l: MaLine): string => `${l.ma === 'ema' ? 'EMA' : 'SMA'}${l.period}`
/** 「15m EMA9 上穿 SMA21」「1h RSI(14) 上穿 70」「4h 收盘突破前 20 根最高」 */
export function indicatorPhrase(r: IndicatorRule): string {
  const cross = r.direction === 'up' ? '上穿' : '下穿'
  if (r.kind === 'ma_cross') return `${r.interval} ${maName(r.fast)} ${cross} ${maName(r.slow)}`
  if (r.kind === 'rsi_level') return `${r.interval} RSI(${r.period}) ${cross} ${r.level}`
  return r.direction === 'up' ? `${r.interval} 收盘突破前 ${r.bars} 根最高` : `${r.interval} 收盘跌破前 ${r.bars} 根最低`
}
/** 输入框里的整数：去空白、全角数字转半角；不是纯数字就 null */
export function parseIntField(text: string): number | null {
  const s = text.replace(/\s/g, '').replace(/[０-９]/g, c => String.fromCharCode(c.charCodeAt(0) - 0xfee0))
  return /^\d{1,6}$/.test(s) ? +s : null
}

// ------------------------------------------------------------ 判定（纯函数）
const maSeries = (closes: number[], l: MaLine): Series => l.ma === 'ema' ? ema(closes, l.period) : sma(closes, l.period)
export function rsiSeries(bars: readonly Bar[], period: number): Series { return Calc.rsi(bars as Bar[], { n: period })[0] }

/** 上穿 / 下穿（TradingView ta.crossover / crossunder）：这一根 a1 严格越过 b1、上一根 a0 还没越过 b0 */
export function crossed(a0: number | null | undefined, b0: number | null | undefined, a1: number | null | undefined, b1: number | null | undefined, dir: Direction): boolean {
  if (a0 == null || b0 == null || a1 == null || b1 == null) return false
  return dir === 'up' ? a1 > b1 && a0 <= b0 : a1 < b1 && a0 >= b0
}

type Cache = { a?: Series; b?: Series }
/** 第 i 根（已收盘）上条件成立吗（要用到第 i-1 根；突破要前 N 根） */
export function indicatorHitAt(r: IndicatorRule, bars: readonly Bar[], i: number, cache: Cache = {}): boolean {
  if (i < 1 || i >= bars.length) return false
  if (r.kind === 'bar_breakout') {
    if (i < r.bars) return false
    const c = bars[i].c
    if (r.direction === 'up') { let hi = -Infinity; for (let k = i - r.bars; k < i; k++) hi = Math.max(hi, bars[k].h); return c > hi }
    let lo = Infinity; for (let k = i - r.bars; k < i; k++) lo = Math.min(lo, bars[k].l); return c < lo
  }
  if (r.kind === 'rsi_level') {
    const s = cache.a ??= rsiSeries(bars, r.period)
    return crossed(s[i - 1], r.level, s[i], r.level, r.direction)
  }
  const closes = bars.map(b => b.c)
  const f = cache.a ??= maSeries(closes, r.fast), s = cache.b ??= maSeries(closes, r.slow)
  return crossed(f[i - 1], s[i - 1], f[i], s[i], r.direction)
}

/** 判要拉多少根（EMA 与 Wilder RSI 是递推的，多给暖机根数让数值和图上一致）；币安一页最多 1500 */
export function barsNeeded(r: IndicatorRule): number {
  const n = r.kind === 'ma_cross'
    ? Math.max(r.fast.ma === 'ema' ? r.fast.period * 4 : r.fast.period, r.slow.ma === 'ema' ? r.slow.period * 4 : r.slow.period) + 3
    : r.kind === 'rsi_level' ? r.period * 10 + 3 : r.bars + 3
  return Math.min(1500, Math.max(n, 50))
}

/** 这一串 K 线（时间升序，末尾可以带一根还没收的）里，「收盘时刻晚于 armedAt、晚于 after、而且已经收了」的那几根，
 *  按先后找第一根命中的；返回下标，没有就 -1。after：上次判到哪一根的收盘时刻（判过的不再判） */
export function judgeClosedBars(r: IndicatorRule, bars: readonly Bar[], armedAt: number, now: number, after = 0): number {
  const ms = IV_MS_IND[r.interval]
  const cache: Cache = {}
  for (let i = 1; i < bars.length; i++) {
    const close = bars[i].t + ms
    if (close > now) break            // 这一根还没收
    if (close <= armedAt || close <= after) continue
    if (indicatorHitAt(r, bars, i, cache)) return i
  }
  return -1
}
/** 这个周期最近一次收盘的时刻（币安按 UTC 对齐，1d 在 UTC 0 点收） */
export const lastCloseAt = (iv: IndInterval, now: number): number => Math.floor(now / IV_MS_IND[iv]) * IV_MS_IND[iv]

// ------------------------------------------------------------ 预填（当前格子图上挂着的指标）
/** 图上那份指标状态：哪几个开着、各自的参数 */
export interface ChartIndView {
  iv: string
  ma: boolean; ema: boolean; rsi: boolean
  params: (id: 'ma' | 'ema' | 'rsi') => IndParams | undefined
}
export interface IndicatorDraft {
  interval: IndInterval
  fast: MaLine; slow: MaLine; maDir: Direction
  rsiPeriod: number; level: number; rsiDir: Direction
  bars: number; brDir: Direction
}
const IV_ORDER_MS: Record<string, number> = { '1s': 1e3, '5s': 5e3, '15s': 15e3, '3m': 180e3, '2h': 72e5, '6h': 216e5, '8h': 288e5, '12h': 432e5, '1w': 6048e5, '1M': 2592e6, ...IV_MS_IND }
/** 格子的周期不在七档里（3m、2h、自定义 7 分钟…）就取最近的一档（按倍数算远近，一样远取短的） */
export function nearestInterval(iv: string): IndInterval {
  if (okIv(iv)) return iv
  const ms = IV_ORDER_MS[iv] ?? (/^\d+$/.test(iv) ? +iv * 60e3 : 36e5)
  let best: IndInterval = '1h', d = Infinity
  for (const k of IND_INTERVALS) { const x = Math.abs(Math.log(IV_MS_IND[k] / ms)); if (x < d - 1e-9) { d = x; best = k } }
  return best
}
const okPeriod = (n: unknown): n is number => intIn(n, PERIOD_MIN, PERIOD_MAX)
const periodsOf = (v: ChartIndView, id: 'ma' | 'ema'): number[] =>
  (v.params(id)?.periods ?? CATALOG[id].params?.periods ?? []).filter(okPeriod)
const otherThan = (l: MaLine): MaLine => l.ma === DEFAULT_SLOW.ma && l.period === DEFAULT_SLOW.period ? DEFAULT_FAST : DEFAULT_SLOW

/** 图上开着的均线（EMA 与 MA 合起来）按长度从短到长：快线取最短的，慢线取第一条更长的；不够两条用默认 */
export function maFromChart(v: ChartIndView): { fast: MaLine; slow: MaLine } {
  const lines: MaLine[] = []
  if (v.ema) for (const p of periodsOf(v, 'ema')) lines.push({ ma: 'ema', period: p })
  if (v.ma) for (const p of periodsOf(v, 'ma')) lines.push({ ma: 'sma', period: p })
  lines.sort((a, b) => a.period - b.period || (a.ma === b.ma ? 0 : a.ma === 'ema' ? -1 : 1))
  const fast = lines[0]
  const slow = fast && lines.find(l => l.period > fast.period)
  if (fast && slow) return { fast, slow }
  if (fast) return { fast, slow: otherThan(fast) }
  return { fast: DEFAULT_FAST, slow: DEFAULT_SLOW }
}
/** 图例上点的那一组均线（MA 图例 → 头两条 SMA；EMA 图例 → 头两条 EMA），短的当快线 */
export function maFromLegend(v: ChartIndView, id: 'ma' | 'ema'): { fast: MaLine; slow: MaLine } {
  const ma: MaType = id === 'ema' ? 'ema' : 'sma'
  const two = [...new Set(periodsOf(v, id))].slice(0, 2).sort((a, b) => a - b)
  if (two.length >= 2) return { fast: { ma, period: two[0] }, slow: { ma, period: two[1] } }
  if (two.length === 1) { const fast: MaLine = { ma, period: two[0] }; return { fast, slow: otherThan(fast) } }
  return { fast: DEFAULT_FAST, slow: DEFAULT_SLOW }
}
/** RSI 长度：图上挂着 RSI（或从 RSI 副图点进来）就用图上的，否则 14 */
export function rsiFromChart(v: ChartIndView, force = false): number {
  const n = v.params('rsi')?.n ?? CATALOG.rsi.params?.n
  return (v.rsi || force) && okPeriod(n) ? n : DEFAULT_RSI
}

/** 建提醒页的起始草稿：周期取当前格子；图上挂着 EMA / SMA / RSI 就用图上的参数；from = 从哪个图例 / 副图点进来的 */
export function draftFromChart(v: ChartIndView, from?: 'ma' | 'ema' | 'rsi'): IndicatorDraft {
  const m = from === 'ma' || from === 'ema' ? maFromLegend(v, from) : maFromChart(v)
  return {
    interval: nearestInterval(v.iv), fast: m.fast, slow: m.slow, maDir: 'up',
    rsiPeriod: rsiFromChart(v, from === 'rsi'), level: DEFAULT_LEVEL, rsiDir: 'up', bars: DEFAULT_BARS, brDir: 'up',
  }
}
/** 草稿 → 某一种条件 */
export function ruleFromDraft(kind: IndicatorKind, d: IndicatorDraft): IndicatorRule {
  if (kind === 'ma_cross') return maCrossRule(d.interval, d.fast, d.slow, d.maDir)
  if (kind === 'rsi_level') return rsiLevelRule(d.interval, d.rsiPeriod, d.level, d.rsiDir)
  return barBreakoutRule(d.interval, d.bars, d.brDir)
}
/** RSI 换方向时水平跟着翻：70 上穿 ↔ 30 下穿（别的值不动） */
export function flipLevel(level: number, dir: Direction): number {
  if (dir === 'down' && level === 70) return 30
  if (dir === 'up' && level === 30) return 70
  return level
}

// ------------------------------------------------------------ 同步被拒时给人看的原因
/** 服务端给了中文原因就用它；没有就按错误码说 */
export function rejectReason(code: string, reason?: string | null): string {
  const r = (reason || '').trim()
  if (r && /[一-鿿]/.test(r)) return r
  if (code === 'invalid_sync_value' || code === 'invalid_operation' || code === 'invalid_rule') return '服务端暂不支持这种条件，本页开着时照常判'
  if (code === 'payload_too_large') return '内容太大，没存上云端'
  return `服务端没收（${code || '未知原因'}）`
}
