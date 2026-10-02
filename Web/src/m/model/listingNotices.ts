/* 手机网页版 · 品种上新与停牌下架通知的取舍（照 iOS Alerts/ListingNotices.swift 的 plan，纯函数）
 *
 * 服务端每 10 分钟对一次品种表，事件记在每个人名下；网页没有推送，回前台、每一轮同步跑完、在前台时定时
 * 拉一次 GET /v1/alerts/listing-notices。每条只出一次：本机按账号记一个「看到哪条了」的游标（最大 id）。
 * 第一次拉（这台设备上这个账号还没有游标）只出最近 1 小时内的，之后出游标以后、24 小时以内的；
 * 太旧的只挪游标不打扰。一次最多出 5 条（新的在前）。
 */

export interface ListingNotice { id: number; venue: string; market: string; symbol: string; event: string; at: number; title: string; body: string }

export const LN = { firstWindowMs: 3_600_000, windowMs: 24 * 3_600_000, maxPerPull: 5, minIntervalMs: 20_000 } as const

export const cursorKey = (owner: string): string => 'listingNotices.cursor.' + owner.toLowerCase()

export function readNotices(raw: unknown): ListingNotice[] {
  const list = raw && typeof raw === 'object' ? (raw as { notices?: unknown }).notices : null
  if (!Array.isArray(list)) return []
  return list.flatMap(x => {
    if (!x || typeof x !== 'object') return []
    const r = x as Record<string, unknown>
    const s = (k: string): string => (typeof r[k] === 'string' ? r[k] as string : '')
    if (typeof r.id !== 'number' || typeof r.at !== 'number' || !s('title')) return []
    return [{ id: r.id, venue: s('venue'), market: s('market'), symbol: s('symbol'), event: s('event'), at: r.at, title: s('title'), body: s('body') }]
  })
}

/** 这一批该出哪几条、游标挪到哪儿 */
export function planNotices(notices: readonly ListingNotice[], cursor: number | null, now: number): { show: ListingNotice[]; cursor: number | null } {
  const newest = notices.length ? Math.max(...notices.map(n => n.id)) : null
  const next = cursor == null ? newest : newest == null ? cursor : Math.max(cursor, newest)
  const window = cursor == null ? LN.firstWindowMs : LN.windowMs
  const fresh = notices.filter(n => n.id > (cursor ?? -Infinity) && n.at >= now - window).sort((a, b) => b.id - a.id)
  return { show: fresh.slice(0, LN.maxPerPull), cursor: next }
}

/** 通知点开去哪只：币安 U 本位永续给裸代号，别的网页版开不了返回 null */
export function noticeSymbol(n: Pick<ListingNotice, 'venue' | 'market' | 'symbol'>): string | null {
  return n.venue.toLowerCase() === 'binance' && n.market.toLowerCase() === 'usd_m' && n.symbol ? n.symbol.toUpperCase() : null
}
