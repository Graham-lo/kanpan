/* Hkline Web · 秒级周期补历史
 *
 * 秒级 K 线原来只有「打开页面以后」逐笔攒的那段（intervals.ts，内存里留 6 小时）。服务端对常驻跟踪的品种也在攒 1 秒线
 * （只币安 U 本位，和图表主数据源一致），留 3 天：
 *   GET /v1/market/klines/seconds?symbol=&from=&to=  →  {"symbol","bars":[[ts,o,h,l,c,vol,buyVol],...]}
 *   ts 是这一秒的起点（ms）；单次最多 6 小时窗；没成交的秒不出行（这里补成平的空 K 线）；没跟踪的品种回空。
 *   vol / buyVol 按币安 K 线的口径当基础币数量（成交量、主动买入量），这里乘以这一秒的典型价折成报价币额，
 *   和逐笔攒的 1 秒线（v 是报价币额、bv 是基础币量、tb 是主动买入额）同一口径。
 *
 * 打开秒级周期：先要最近 6 小时，和内存里逐笔攒的拼起来——重叠的那几秒以逐笔攒的为准；5 秒、15 秒照旧从 1 秒并。
 * 往左翻：一次 6 小时一页，翻到服务端的 3 天上限或回空为止。接口没上线（404）或空回包都当「没有历史」，照旧只有逐笔那段。
 * 要失败了（断网、5xx）30 秒内不再去要，免得往左拖一次打一次。
 */
import type { Bar } from './calc'
import { IV_MS } from '../util/format'
import { serverHistory } from '../market/rest'
import { aggregate, secondBars } from './intervals'
import { ago } from '../util/clock'

/** 单次最多要 6 小时 */
export const SEC_WINDOW_MS = 6 * 3_600_000
/** 服务端留 3 天 */
export const SEC_KEEP_MS = 3 * 86_400_000
const RETRY_MS = 30_000
const failedAt = new Map<string, number>()

/** 解 /v1/market/klines/seconds 的答复成按时间升序的 1 秒线（坏行丢掉、同一秒留后一行）；不是这个形状回 null */
export function parseSeconds(body: unknown): Bar[] | null {
  if (!body || typeof body !== 'object') return null
  const rows = (body as { bars?: unknown }).bars
  if (!Array.isArray(rows)) return null
  const m = new Map<number, Bar>()
  for (const r of rows) {
    if (!Array.isArray(r) || r.length < 6) continue
    const [ts, o, h, l, c, vol] = r as number[], buy = r.length > 6 ? (r[6] as number) : null
    if (![ts, o, h, l, c, vol].every(x => typeof x === 'number' && Number.isFinite(x))) continue
    if (!(o > 0 && h > 0 && l > 0 && c > 0) || vol < 0) continue
    const t = Math.floor(ts / 1e3) * 1e3, px = (h + l + c) / 3
    const b: Bar = { t, o, h: Math.max(h, o, c, l), l: Math.min(l, o, c, h), c, v: vol * px, bv: vol }
    if (typeof buy === 'number' && Number.isFinite(buy) && buy >= 0) b.tb = Math.min(buy, vol) * px
    m.set(t, b)
  }
  return [...m.values()].sort((a, b) => a.t - b.t)
}

/** 没成交的秒补成平的空 K 线（开高低收都是上一秒的收）；until 给了就一直补到 until 前一秒 */
export function fillGaps(bars: Bar[], until?: number): Bar[] {
  if (!bars.length) return bars
  const out: Bar[] = []
  for (const b of bars) {
    const prev = out[out.length - 1]
    if (prev) for (let t = prev.t + 1e3; t < b.t; t += 1e3) out.push(flat(t, prev.c))
    out.push(b)
  }
  if (until != null) { const last = out[out.length - 1]; for (let t = last.t + 1e3; t < until; t += 1e3) out.push(flat(t, last.c)) }
  return out
}
const flat = (t: number, c: number): Bar => ({ t, o: c, h: c, l: c, c, v: 0, bv: 0, tb: 0 })

/** 服务端的历史与逐笔攒的拼起来：同一秒以逐笔攒的为准，按时间升序 */
export function spliceSeconds(hist: Bar[], live: Bar[]): Bar[] {
  if (!hist.length) return live
  if (!live.length) return hist
  const m = new Map<number, Bar>()
  for (const b of hist) m.set(b.t, b)
  for (const b of live) m.set(b.t, b)
  return [...m.values()].sort((a, b) => a.t - b.t)
}

/** 要 [from, to) 这一段 1 秒线；ok 为假是失败（断网、5xx），没有历史是 ok 且空 */
export async function fetchSeconds(symbol: string, from: number, to: number, base = ''): Promise<{ ok: boolean; bars: Bar[] }> {
  const r = await serverHistory(`/v1/market/klines/seconds?symbol=${encodeURIComponent(symbol)}&from=${Math.floor(from)}&to=${Math.floor(to)}`, 12_000, base)
  if (!r.ok) return { ok: false, bars: [] }
  const bars = r.body == null ? [] : parseSeconds(r.body) ?? []
  return { ok: true, bars: bars.filter(b => b.t >= from && b.t < to) }
}

/**
 * 秒级周期取 K 线（pages/chart.ts 的 barsFor 调）。
 * 不带 endTime：最近 6 小时的历史 + 内存里逐笔攒的；带 endTime：往左翻一页（endTime 之前 6 小时，不早于 3 天前）。
 */
export async function secondsKlines(symbol: string, iv: string, endTime?: number, alive?: () => boolean, base = '', now = Date.now()): Promise<{ bars: Bar[]; ok: boolean; error?: string }> {
  const ms = IV_MS[iv] || 1e3
  const floor = Math.floor((now - SEC_KEEP_MS) / ms) * ms
  if (endTime != null) {
    if (endTime <= floor) return { bars: [], ok: true }
    if (ago(failedAt.get(symbol) ?? 0, now) < RETRY_MS) return { bars: [], ok: false, error: '秒线历史稍后再取' }
    const from = Math.max(floor, Math.floor((endTime - SEC_WINDOW_MS) / ms) * ms)
    const r = await fetchSeconds(symbol, from, endTime, base)
    if (alive && !alive()) return { bars: [], ok: false }
    if (!r.ok) { failedAt.set(symbol, Date.now()); return { bars: [], ok: false, error: '取不到秒线历史' } }
    if (!r.bars.length) return { bars: [], ok: true }
    const one = fillGaps(r.bars, endTime)
    return { bars: ms === 1e3 ? one : aggregate(one, ms).filter(b => b.t < endTime), ok: true }
  }
  const from = Math.floor((now - SEC_WINDOW_MS) / ms) * ms
  const r = ago(failedAt.get(symbol) ?? 0, now) < RETRY_MS ? { ok: false, bars: [] } : await fetchSeconds(symbol, from, now + 1e3, base)
  if (!r.ok) failedAt.set(symbol, Date.now())
  const live = secondBars(symbol, '1s')
  // 没有历史：照旧只有逐笔攒的那段（没成交时页面写「等第一笔成交」）
  if (!r.bars.length) return { bars: ms === 1e3 ? live : aggregate(live, ms), ok: true }
  const one = fillGaps(spliceSeconds(r.bars, live))
  return { bars: ms === 1e3 ? one : aggregate(one, ms), ok: true }
}

/** 测试用 */
export function resetSecondsHistory(): void { failedAt.clear() }
