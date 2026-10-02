/* 手机网页版 · 朋友与收件箱的纯逻辑（照 iOS Share/ShareInbox.swift、ShareItem.swift、ShareClient.swift）
 *
 * 收件箱独立于个人同步：按账号一份本机缓存（信、朋友名单、游标、待发回执、「留下」时预分的新线 id）。
 * - 拉一页（GET /v1/shares/inbox?after=游标）并进缓存：有待发回执的信，本机的「已读 / 留下」不被服务端旧值盖掉；
 *   90 天前的信（没留下的）丢掉（服务端清理没有墓碑，本地守同一条留存规则）；按创建时间新的在前。
 * - 回执（opened / kept）先记在 pending 里，下次拉之前先发；服务端永远不会收的（404 信没了、400 号不认……）丢掉，
 *   只有连不上、5xx、401 / 403 / 408 / 429 留着重试。
 * - 「留下」先给每条线分好新 id 记进缓存，再落画线：重试、刷新页面都不会把同一封信复制两遍。
 */

import { baseOf } from '../../alerts/shape'

export interface ShareView { from: number; to: number }
export interface ShareItem {
  id: string
  from: string
  symbol: string
  /** 「venue/market」，如 binance/usd_m */
  market: string
  interval: string
  view: ShareView
  /** 线的 JSON（和画线同步同一种编码），进门时裁到每品种上限 */
  drawings: unknown[]
  alerted: string[]
  /** 服务端 RFC3339 原串（也是排序依据，保留微秒） */
  createdAt: string
  openedAt?: string | null
  keptAt?: string | null
  replyTo?: string | null
}
export interface InboxCache {
  items: ShareItem[]
  friends: string[]
  cursor?: string | null
  pending: Record<string, boolean>
  copies: Record<string, string[]>
}

export const RETENTION_MS = 90 * 86_400_000
/** 每品种画线上限（DrawArchive.perSymbolLimit） */
export const PER_SYMBOL_LIMIT = 50

export const emptyCache = (): InboxCache => ({ items: [], friends: [], cursor: null, pending: {}, copies: {} })

const str = (v: unknown): string | null => (typeof v === 'string' ? v : null)

/** 服务端 / 本机缓存里的一封信 → ShareItem；形状不对返回 null。进门就把线裁到每品种上限（丢最老的，即数组头上的） */
export function readItem(raw: unknown): ShareItem | null {
  if (!raw || typeof raw !== 'object') return null
  const r = raw as Record<string, unknown>
  const id = str(r.id), from = str(r.from), symbol = str(r.symbol), interval = str(r.interval), createdAt = str(r.createdAt)
  const v = r.view as Record<string, unknown> | undefined
  if (!id || from == null || !symbol || !interval || !createdAt || !v || typeof v.from !== 'number' || typeof v.to !== 'number') return null
  const drawings = Array.isArray(r.drawings) ? r.drawings : []
  return {
    id, from, symbol, market: str(r.market) ?? 'binance/usd_m', interval, view: { from: v.from, to: v.to },
    drawings: drawings.length > PER_SYMBOL_LIMIT ? drawings.slice(drawings.length - PER_SYMBOL_LIMIT) : drawings,
    alerted: Array.isArray(r.alerted) ? r.alerted.filter((x): x is string => typeof x === 'string') : [],
    createdAt, openedAt: str(r.openedAt), keptAt: str(r.keptAt), replyTo: str(r.replyTo),
  }
}

export function readCache(raw: unknown): InboxCache {
  if (!raw || typeof raw !== 'object') return emptyCache()
  const r = raw as Record<string, unknown>
  const items = Array.isArray(r.items) ? r.items.map(readItem).filter((x): x is ShareItem => !!x) : []
  const friends = Array.isArray(r.friends) ? r.friends.filter((x): x is string => typeof x === 'string') : []
  const pending: Record<string, boolean> = {}
  if (r.pending && typeof r.pending === 'object') for (const [k, v] of Object.entries(r.pending)) if (typeof v === 'boolean') pending[k] = v
  const copies: Record<string, string[]> = {}
  if (r.copies && typeof r.copies === 'object') {
    for (const [k, v] of Object.entries(r.copies)) if (Array.isArray(v) && v.every(x => typeof x === 'string')) copies[k] = v
  }
  return { items, friends, cursor: str(r.cursor), pending, copies }
}

/** RFC3339 → 毫秒；解不开 NaN */
export const createdMs = (raw: string): number => Date.parse(raw)

/** 一页并进缓存（返回新的 items，不改入参） */
export function mergePage(cache: InboxCache, page: readonly ShareItem[], now: number): ShareItem[] {
  const merged = new Map(cache.items.map(i => [i.id, i]))
  for (const item of page) {
    const next = { ...item }
    if (cache.pending[item.id] != null) {
      const local = merged.get(item.id)
      next.openedAt = next.openedAt ?? local?.openedAt ?? null
      next.keptAt = next.keptAt ?? local?.keptAt ?? null
    }
    merged.set(item.id, next)
  }
  const cutoff = now - RETENTION_MS
  return [...merged.values()]
    .filter(i => !!i.keptAt || !(createdMs(i.createdAt) < cutoff))
    .sort((a, b) => a.createdAt === b.createdAt ? (a.id < b.id ? 1 : a.id > b.id ? -1 : 0) : (a.createdAt < b.createdAt ? 1 : -1))
}

/** 这条回执服务端永远不会收：4xx 里除了 401 / 403 / 408 / 429 */
export const receiptIsDead = (status: number): boolean => status >= 400 && status < 500 && ![401, 403, 408, 429].includes(status)

/** 本机记一次「已读」或「留下」（留下也算读过）；返回新缓存 */
export function markLocal(cache: InboxCache, id: string, keep: boolean, stamp: string): InboxCache {
  const i = cache.items.findIndex(x => x.id === id)
  if (i < 0) return cache
  const items = cache.items.slice()
  const it = { ...items[i] }
  it.openedAt = it.openedAt ?? stamp
  if (keep) it.keptAt = it.keptAt ?? stamp
  items[i] = it
  return { ...cache, items, pending: { ...cache.pending, [id]: (cache.pending[id] ?? false) || keep } }
}

export const unseen = (items: readonly ShareItem[]): ShareItem[] => items.filter(i => !i.openedAt)

/** 信落在哪只品种（规范键）：symbol 带「/」就是完整键，否则拼上 market */
export function itemKey(item: Pick<ShareItem, 'symbol' | 'market'>): string {
  const full = item.symbol.includes('/') ? item.symbol : item.market + '/' + item.symbol
  const parts = full.split('/')
  return parts.length === 3 ? `${parts[0].toLowerCase()}/${parts[1].toLowerCase()}/${parts[2].toUpperCase()}` : full
}
/** 图表页认的代号：币安 U 本位永续就是裸代号（BTCUSDT）；别的交易所 / 市场网页版开不了，返回 null */
export function openableSymbol(item: Pick<ShareItem, 'symbol' | 'market'>): string | null {
  const [venue, market, sym] = itemKey(item).split('/')
  return venue === 'binance' && market === 'usd_m' && sym ? sym : null
}

/** 「留下」要用的新 id：已经分过就用分过的（重试不重复复制） */
export function plannedCopies(cache: InboxCache, item: ShareItem, newId: () => string): { cache: InboxCache; ids: string[] } {
  const have = cache.copies[item.id]
  if (have && have.length >= item.drawings.length) return { cache, ids: have }
  const ids = item.drawings.map((_, i) => have?.[i] ?? newId())
  return { cache: { ...cache, copies: { ...cache.copies, [item.id]: ids } }, ids }
}

/** 加朋友成功后的名单：去重、按名字排 */
export const withFriend = (friends: readonly string[], name: string): string[] => [...new Set([...friends, name])].sort()

/** 收件箱一行第二行的时间：「10月3日 14:05」（本机时区，和 iOS .dateTime.month().day().hour().minute() 一个意思） */
export function letterTime(raw: string): string {
  const ms = createdMs(raw)
  if (!Number.isFinite(ms)) return ''
  const d = new Date(ms)
  const p = (n: number): string => (n < 10 ? '0' + n : String(n))
  return `${d.getMonth() + 1}月${d.getDate()}日 ${p(d.getHours())}:${p(d.getMinutes())}`
}

/** 信上的品种短名（照 iOS ShareItem.shortSymbol：基础币） */
export const shortSymbol = (item: Pick<ShareItem, 'symbol' | 'market'>): string => {
  const sym = itemKey(item).split('/')[2] ?? item.symbol
  return sym.includes('-') ? sym.split('-')[0] : baseOf(sym)
}
/** 收件箱一行第一行：「amy · BTC · 3 条线」 */
export const letterTitle = (item: Pick<ShareItem, 'symbol' | 'market' | 'from' | 'drawings'>): string =>
  `${item.from} · ${shortSymbol(item)} · ${item.drawings.length} 条线`
