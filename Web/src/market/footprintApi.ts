/* Hkline Web · 足迹图的服务端历史
 *
 *   GET /v1/market/orderflow/footprint?symbol=&from=&to=
 *   →  {"symbol","step","minutes":[{"t":<分钟起点 ms>,"rows":[[price,buyUsd,sellUsd],...]},...]}
 *   price 是价位桶的下沿，rows 按价升序；单次最多 24 小时窗；没跟踪的品种回空 minutes。
 *   数据是服务端用币安、OKX、Coinbase 三家逐笔按（分钟 × 价位桶）攒的主动买 / 主动卖美元额，留 3 天。
 * 接口没上线（404）或空回包都当「没有历史」（见 rest.ts serverHistory）。
 */
import { serverHistory } from './rest'

/** 一分钟里的价位：[桶下沿, 主动买额, 主动卖额]，按价升序 */
export type FootRow = [number, number, number]
export interface FootMinute { t: number; rows: FootRow[] }
export interface FootHistory { step: number | null; minutes: FootMinute[] }

/** 单次最多要 24 小时 */
export const FOOT_WINDOW_MS = 24 * 3_600_000
/** 服务端留 3 天 */
export const FOOT_KEEP_MS = 3 * 86_400_000

/** 解答复；不是这个形状回 null。坏行丢掉，分钟按时间升序、行按价升序（同价位并起来） */
export function parseFootprint(body: unknown): FootHistory | null {
  if (!body || typeof body !== 'object') return null
  const b = body as { step?: unknown; minutes?: unknown }
  if (!Array.isArray(b.minutes)) return null
  const step = typeof b.step === 'number' && Number.isFinite(b.step) && b.step > 0 ? b.step : null
  const minutes: FootMinute[] = []
  for (const m of b.minutes) {
    if (!m || typeof m !== 'object') continue
    const { t, rows } = m as { t?: unknown; rows?: unknown }
    if (typeof t !== 'number' || !Number.isFinite(t) || !Array.isArray(rows)) continue
    const byPx = new Map<number, FootRow>()
    for (const r of rows) {
      if (!Array.isArray(r) || r.length < 3) continue
      const [p, buy, sell] = r as number[]
      if (![p, buy, sell].every(x => typeof x === 'number' && Number.isFinite(x)) || !(p > 0) || buy < 0 || sell < 0) continue
      const o = byPx.get(p)
      if (o) { o[1] += buy; o[2] += sell } else byPx.set(p, [p, buy, sell])
    }
    minutes.push({ t: Math.floor(t / 60_000) * 60_000, rows: [...byPx.values()].sort((x, y) => x[0] - y[0]) })
  }
  minutes.sort((x, y) => x.t - y.t)
  return { step, minutes }
}

/** 要 [from, to) 这一段（调用方保证不超过 24 小时）；ok 为假是失败（断网、5xx），没有历史是 ok 且空 */
export async function fetchFootprint(symbol: string, from: number, to: number, base = ''): Promise<{ ok: boolean; data: FootHistory }> {
  const r = await serverHistory(`/v1/market/orderflow/footprint?symbol=${encodeURIComponent(symbol)}&from=${Math.floor(from)}&to=${Math.floor(to)}`, 12_000, base)
  if (!r.ok) return { ok: false, data: { step: null, minutes: [] } }
  const p = r.body == null ? null : parseFootprint(r.body)
  return { ok: true, data: p ? { step: p.step, minutes: p.minutes.filter(m => m.t >= from && m.t < to) } : { step: null, minutes: [] } }
}
