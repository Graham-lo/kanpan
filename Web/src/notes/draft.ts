/* Hkline Web · 记一笔：把「图上看得见的那一段 + 这时候的判断」拼成服务端的观点记录草稿
 *
 * 纯函数，不碰 DOM，单元测试直接测。形状照 kanpan-api 的 NativeDraft（deny_unknown_fields，
 * 多一个键整条拒收），取值照手机端取景卡（KanpanReview ReviewCaptureCard / ReviewChartBridge）：
 *   · 区间 = 视野里已收盘的 K 线，从最左一根的开盘到最右一根的收盘；3–1500 根
 *   · 默认「只记录」、收盘确认；参考价 = 最新收盘，目标 / 失效默认取区间最高 / 最低（看空时对调）
 *   · 到期按周期给：分钟线一天、小时线一周、日线一个月、周线三个月、月线一年
 *   · 「把握」2026-09-28 手机端已收掉，新记的一律 null
 *   · chartSettings / drawingSnapshot 不传：前者要过服务端的同步字段白名单（网页的指标键和手机不是一套，
 *     带一个手机不认的键整条就被拒），后者是手机的画线编码，网页的画线格式塞进去手机解不开
 *
 * 网页独有的周期（秒级、自定义分钟）服务端不认，按「能整除它的原生周期」记：秒级记成 1 分，
 * 7 分记成 1 分、90 分记成 30 分。区间覆盖的时间段不变，只是根数按原生周期数。
 */
import { IV_MS } from '../util/format'

/** 服务端认的周期（币安官方写法） */
export const SERVER_IVS = ['1m', '3m', '5m', '15m', '30m', '1h', '2h', '4h', '6h', '8h', '12h', '1d', '3d', '1w', '1M'] as const
const MINUTE_BASES = ['12h', '8h', '6h', '4h', '2h', '1h', '30m', '15m', '5m', '3m', '1m']
export const MIN_BARS = 3
export const MAX_BARS = 1500
const DAY = 864e5

export type Direction = 'observe' | 'long' | 'short'
export type Confirmation = 'bar_close' | 'trade_touch'
export type Origin = 'chart_first' | 'thought_first' | 'interwoven' | 'unknown'

export const DIRECTION_LABEL: Record<Direction, string> = { observe: '只记录', long: '看多', short: '看空' }
export const CONFIRMATION_LABEL: Record<Confirmation, string> = { bar_close: '收盘确认', trade_touch: '触价确认' }
export const ORIGIN_LABEL: Record<Origin, string> = { chart_first: '图在先', thought_first: '想法在先', interwoven: '两者交织', unknown: '不确定' }

export interface NoteRange { venue: 'binance'; market: 'usd_m'; symbol: string; interval: string; start: number; end: number; bars: number }
export interface NoteRule {
  version: 'criteria-v2'; direction: Direction; confirmation: Confirmation
  reference: number; target: number; invalidation: number; expires: number
  targetEdited: boolean; invalidationEdited: boolean; expiryEdited: boolean
}
/** 发给 POST /v1/native-review/records 的整条（键一个不多一个不少） */
export interface NoteDraft {
  id: string; range: NoteRange; rule: NoteRule; text: string
  confidence: null; origin: Origin; created: number
}

/** 图上的一根 K 线（只要开盘时间与高低收） */
export interface BarLike { t: number; h: number; l: number; c: number }

/** 周期的毫秒数：自定义分钟 / 秒级没挂进周期表时按名字算 */
function ivMs(iv: string): number {
  return IV_MS[iv] ?? (/^\d+m$/.test(iv) ? +iv.slice(0, -1) * 60e3 : /^\d+s$/.test(iv) ? +iv.slice(0, -1) * 1e3 : NaN)
}

/** 这个周期在服务端按哪个原生周期记 */
export function recordInterval(iv: string): string {
  if ((SERVER_IVS as readonly string[]).includes(iv)) return iv
  if (/^\d+s$/.test(iv)) return '1m'
  const ms = ivMs(iv)
  if (!(ms > 0)) return '1m'
  return MINUTE_BASES.find(b => ms % IV_MS[b] === 0) || '1m'
}

/** 下一个月一号 0 点（UTC）：月线的收盘时刻 */
function nextMonth(t: number): number { const d = new Date(t); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1) }
function addMonths(t: number, n: number): number { const d = new Date(t); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + n, 1) }

/** [start, end) 里有几根完整 K 线：和服务端 bars_between 逐位一致（固定周期按秒整除，月线按日历） */
export function barsBetween(iv: string, start: number, end: number): number {
  if (iv === '1M') {
    const a = new Date(start), b = new Date(end)
    let n = (b.getUTCFullYear() - a.getUTCFullYear()) * 12 + b.getUTCMonth() - a.getUTCMonth()
    while (n > 0 && addMonths(start, n) > end) n--
    while (addMonths(start, n + 1) <= end) n++
    return n
  }
  const step = (IV_MS[iv] ?? (iv === '3d' ? 3 * DAY : 60e3)) / 1000
  return Math.floor(Math.floor((end - start) / 1000) / step)
}

/** 到期默认值（照手机端 ReviewInterval.defaultHorizonMillis） */
export function horizonMs(iv: string): number {
  if (/^\d+m$/.test(iv)) return DAY
  if (/^\d+h$/.test(iv)) return 7 * DAY
  if (iv === '1d') return 30 * DAY
  if (iv === '3d' || iv === '1w') return 90 * DAY
  if (iv === '1M') return 365 * DAY
  return DAY
}

export interface Capture {
  range: NoteRange
  /** 参考价：区间里最后一根的收盘 */
  reference: number
  high: number
  low: number
}

/**
 * 取景：图表周期 iv 的 K 线 bars，视野是下标 [from, to]；now 以前收盘的才算。
 * 原生周期直接用这几根的开盘时间（交易所给的，已经对齐）；网页独有的周期换成原生周期、按时间段对齐。
 * 根数不到 3 根往左补、超过 1500 根从左边砍（保留最近的）。取不出一段合法区间时返回 null。
 */
export function captureRange(symbol: string, iv: string, bars: readonly BarLike[], from: number, to: number, now: number): Capture | null {
  if (!/USDT$/.test(symbol) || !bars.length) return null
  const ms = ivMs(iv)
  const closeOf = (i: number): number => i + 1 < bars.length ? bars[i + 1].t : iv === '1M' ? nextMonth(bars[i].t) : bars[i].t + ms
  let b = Math.min(to, bars.length - 1)
  while (b >= 0 && closeOf(b) > now) b--
  if (b < 0) return null
  let a = Math.max(0, Math.min(from, b))
  const rec = recordInterval(iv)
  let start: number, end: number, n: number
  if (rec === iv) {
    if (b - a + 1 < MIN_BARS) a = Math.max(0, b - MIN_BARS + 1)
    if (b - a + 1 > MAX_BARS) a = b - MAX_BARS + 1
    start = bars[a].t; end = closeOf(b)
    n = barsBetween(rec, start, end)
    // 交易所的 K 线偶尔有缺口，按时间算的根数会比数出来的多：超了就按时间从左边砍
    if (n > MAX_BARS && rec !== '1M') { start = end - MAX_BARS * ms; n = MAX_BARS }
    if (n < MIN_BARS || n > MAX_BARS) return null
  } else {
    const step = IV_MS[rec]
    end = Math.floor(Math.min(closeOf(b), now) / step) * step
    start = Math.floor(bars[a].t / step) * step
    n = barsBetween(rec, start, end)
    if (n < MIN_BARS) { start = end - MIN_BARS * step; n = MIN_BARS }
    if (n > MAX_BARS) { start = end - MAX_BARS * step; n = MAX_BARS }
  }
  let hi = -Infinity, lo = Infinity
  for (let i = a; i <= b; i++) { if (bars[i].h > hi) hi = bars[i].h; if (bars[i].l < lo) lo = bars[i].l }
  return { range: { venue: 'binance', market: 'usd_m', symbol, interval: rec, start, end, bars: n }, reference: bars[b].c, high: hi, low: lo }
}

/** 按方向把目标 / 失效摆到参考价两侧：人改过的那一个不动（照手机端方向切换时的做法） */
export function sideLevels(dir: Direction, reference: number, high: number, low: number): { target: number; invalidation: number } {
  const up = Math.max(high, reference * 1.01), dn = Math.min(low, reference * 0.99)
  return dir === 'short' ? { target: dn, invalidation: up } : { target: up, invalidation: dn }
}

export interface DraftInput {
  id: string
  capture: Capture
  direction: Direction
  confirmation: Confirmation
  target: number
  invalidation: number
  targetEdited: boolean
  invalidationEdited: boolean
  text: string
  origin: Origin
  created: number
}

export function buildDraft(x: DraftInput): NoteDraft {
  const c = x.capture
  const observe = x.direction === 'observe'
  return {
    id: x.id,
    range: { ...c.range },
    rule: {
      version: 'criteria-v2', direction: x.direction, confirmation: observe ? 'bar_close' : x.confirmation,
      reference: c.reference,
      // 只记录时目标 / 失效不参与判定，但服务端要求三个价都是正数：照手机端给区间最高 / 最低
      target: observe ? c.high : x.target,
      invalidation: observe ? c.low : x.invalidation,
      expires: x.created + horizonMs(c.range.interval),
      targetEdited: !observe && x.targetEdited, invalidationEdited: !observe && x.invalidationEdited, expiryEdited: false,
    },
    text: x.text.trim(),
    confidence: null,
    origin: x.origin,
    created: x.created,
  }
}

/** 本地先查一遍服务端会拒的情形，返回给人看的一句话；没问题返回 null */
export function checkDraft(d: NoteDraft): string | null {
  const r = d.rule
  if (![r.reference, r.target, r.invalidation].every(v => Number.isFinite(v) && v > 0)) return '目标和失效都要填一个正数价格'
  if (r.direction === 'long' && !(r.target > r.reference && r.invalidation < r.reference)) return '看多：目标要高于参考价，失效要低于参考价'
  if (r.direction === 'short' && !(r.target < r.reference && r.invalidation > r.reference)) return '看空：目标要低于参考价，失效要高于参考价'
  if (d.range.bars < MIN_BARS || d.range.bars > MAX_BARS) return '这段图表区间不完整'
  if (new TextEncoder().encode(d.text).length > 64000) return '这段话太长了'
  return null
}
