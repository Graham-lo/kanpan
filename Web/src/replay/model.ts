/* Hkline Web · K 线回放：纯计算（不碰 DOM、不发请求，单测直接跑）
 *
 * 用一只「回放钟」描述回放走到哪：clock = 最后一根可见 K 线的收线时刻（即下一根的开盘时刻）。
 *   · 可见 = 收线时刻 ≤ clock 的那些 K 线，所以图上永远只有走完的整根，没有「半根未来」
 *   · 定起点：点中的那一根算可见，startClock = 它的收线时刻
 *   · 切周期：clock 与 startClock 原样留着，在新周期上按同一条规则重新数可见的那几根（= 重新定位）
 *   · 进一根：clock 推到下一根的收线时刻
 */
import type { Bar } from '../chart/calc'
import { IV_MS } from '../util/format'

/** 播放速度：1× = 每秒一根 */
export const REPLAY_SPEEDS = [1, 2, 4, 8, 16] as const
/** 起点左边至少留这么多根：均线、指标按当时的样子算出来 */
export const HISTORY_BARS = 300
/** 起点之后先取这么多根「未来」 */
export const FUTURE_BARS = 600
/** 没播的剩不到这么多根就去补下一页 */
export const REFILL_AT = 200
/** 币安一页最多 1500 根 */
export const PAGE = 1500

const WEEK = 6048e5
/** 币安周线从周一 00:00 UTC 开始；1970-01-01 是周四，往后四天是周一 */
const WEEK_OFF = 4 * 864e5
const TZ = 8 * 36e5

/** 时刻 t 落在哪一根 K 线里：那一根的开盘时刻（周线按周一对齐，月线按 UTC 自然月） */
export function barOpen(t: number, iv: string): number {
  if (iv === '1M') { const d = new Date(t); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1) }
  if (iv === '1w') return Math.floor((t - WEEK_OFF) / WEEK) * WEEK + WEEK_OFF
  const ms = IV_MS[iv] || 60e3
  return Math.floor(t / ms) * ms
}
/** 开盘时刻为 open 的那一根的收线时刻（= 下一根的开盘） */
export function barClose(open: number, iv: string): number {
  if (iv === '1M') { const d = new Date(open); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1) }
  return open + (iv === '1w' ? WEEK : IV_MS[iv] || 60e3)
}
/** 在时刻 t 定起点：t 所在的那一根算可见 */
export function clockAtStart(t: number, iv: string): number { return barClose(barOpen(t, iv), iv) }
/** 在周期 iv 上，clock 这一刻最后一根走完的 K 线的收线时刻（clock 落在一根中间就退回到那一根的开盘） */
export function relocate(clock: number, iv: string): number { return barOpen(clock, iv) }
/** 现在这一刻最后一根走完的 K 线的收线时刻：回放最远走到这里 */
export function liveEnd(now: number, iv: string): number { return barOpen(now, iv) }

/** bars（按时间升序）的前 len 根里有几根在 clock 时已经收线 */
export function visibleCount(bars: readonly Bar[], clock: number, iv: string, len = bars.length): number {
  // 收线时刻 ≤ clock ⟺ 开盘 < relocate(clock)（同一周期的 K 线首尾相接）
  const edge = relocate(clock, iv)
  let lo = 0, hi = Math.min(len, bars.length)
  while (lo < hi) { const m = (lo + hi) >> 1; if (bars[m].t < edge) lo = m + 1; else hi = m }
  return lo
}

/** 定起点时手里已有的 K 线够不够用：起点左边至少 HISTORY_BARS 根、且起点没越过手里最后一根才直接拿来切；
 *  够就切成「可见 / 未来」两份（拷贝，不动实时那份；正在走的那根不进未来），不够返回 null 去取 */
export function splitAt(bars: readonly Bar[], clock: number, iv: string, now: number): { hist: Bar[]; future: Bar[] } | null {
  const n = visibleCount(bars, clock, iv)
  if (n < HISTORY_BARS || n >= bars.length) return null
  const end = liveEnd(now, iv)
  const hist = bars.slice(0, n).map(b => ({ ...b }))
  const future: Bar[] = []
  for (let i = n; i < bars.length; i++) { const b = bars[i]; if (barClose(b.t, iv) <= end) future.push({ ...b }) }
  return { hist, future }
}

/** 取数计划：历史一页取到 clock 为止（含起点左边 300 根与一屏），未来从下一根起先取 FUTURE_BARS 根 */
export interface FetchPlan {
  /** 历史这页的 endTime（取开盘严格早于它的） */
  histEnd: number
  histLimit: number
  /** 未来这页的 startTime（取开盘不早于它的） */
  futureFrom: number
  futureLimit: number
  /** 回放最远走到的收线时刻 */
  stop: number
}
export function fetchPlan(clock: number, iv: string, now: number): FetchPlan {
  const histEnd = relocate(clock, iv)
  return { histEnd, histLimit: PAGE, futureFrom: histEnd, futureLimit: FUTURE_BARS, stop: liveEnd(now, iv) }
}
/** 没播的还剩 left 根、手里最后一根开盘在 lastOpen：要不要补下一页（已经取到最新就不补） */
export function needRefill(left: number, lastOpen: number | null, iv: string, now: number): boolean {
  if (left >= REFILL_AT) return false
  return lastOpen == null || barClose(lastOpen, iv) < liveEnd(now, iv)
}
/** 补下一页从哪一根取起 */
export function refillFrom(lastOpen: number, iv: string): number { return barClose(lastOpen, iv) }
/** 取回来的一页里只留走完的整根（别把正在走的那根当未来播出去） */
export function completed(bars: readonly Bar[], iv: string, now: number): Bar[] {
  const end = liveEnd(now, iv)
  return bars.filter(b => barClose(b.t, iv) <= end)
}

/** 速度 → 两根之间隔多少毫秒 */
export function speedDelay(speed: number): number { return 1000 / Math.max(1, speed) }

/** 进度线：起点在 0，最新在 1 */
export function trackPos(clock: number, start: number, stop: number): number {
  if (!(stop > start)) return 1
  return Math.max(0, Math.min(1, (clock - start) / (stop - start)))
}
/** 进度线上的位置 → 回放钟（落到整根的收线上，不早于起点、不晚于最新） */
export function clockAtPos(pos: number, start: number, stop: number, iv: string): number {
  const p = Math.max(0, Math.min(1, isFinite(pos) ? pos : 0))
  if (!(stop > start)) return start
  if (p >= 1) return stop
  return Math.max(start, Math.min(stop, barOpen(start + p * (stop - start), iv)))
}

/** 头部报价：当前那根的收盘，涨跌对比 24 小时前那一刻（大周期就是上一根）的收盘 */
export interface ReplayQuote { price: number; chg: number; pct: number; t: number }
export function quoteAt(bars: readonly Bar[], n: number, iv: string): ReplayQuote | null {
  if (n <= 0 || n > bars.length) return null
  const last = bars[n - 1], clock = barClose(last.t, iv)
  const k = visibleCount(bars, clock - 864e5, iv, n - 1)
  const ref = k > 0 ? bars[k - 1].c : bars[0].o
  const chg = last.c - ref
  return { price: last.c, chg, pct: ref ? chg / ref * 100 : 0, t: last.t }
}

/** 秒级周期没有交易所 K 线历史，不能回放 */
export function canReplay(iv: string): boolean { return !/^\d+s$/.test(iv) }

const p2 = (n: number): string => String(n).padStart(2, '0')
/** 上海时间 'YYYY-MM-DD HH:mm'（回放条上的起点输入框与当前时刻） */
export function fmtShTime(t: number): string {
  const d = new Date(t + TZ)
  return `${d.getUTCFullYear()}-${p2(d.getUTCMonth() + 1)}-${p2(d.getUTCDate())} ${p2(d.getUTCHours())}:${p2(d.getUTCMinutes())}`
}
/** 解析用户打的上海时间：2026-10-04 21:30 / 2026/10/4 21:30 / 2026-10-04T21:30 / 2026-10-04（当天 0 点）/ 10-04 21:30（今年） */
export function parseShTime(s: string, now = Date.now()): number | null {
  const m = s.trim().match(/^(?:(\d{4})[-/.年])?(\d{1,2})[-/.月](\d{1,2})日?(?:[ T]+(\d{1,2})[:：时](\d{1,2})分?)?$/)
  if (!m) return null
  const y = m[1] ? +m[1] : new Date(now + TZ).getUTCFullYear()
  const mo = +m[2], d = +m[3], h = m[4] ? +m[4] : 0, mi = m[5] ? +m[5] : 0
  if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59) return null
  const t = Date.UTC(y, mo - 1, d, h, mi) - TZ
  // 2 月 30 日这种会被 Date 滚到下个月：滚了就不算
  if (new Date(t + TZ).getUTCDate() !== d) return null
  return t
}
