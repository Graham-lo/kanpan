/* 手机网页版 · 搜品种（照 iOS SymbolQuery.swift / SymbolSections.build 搜索态 / SearchHistory.swift / SymbolAliases.swift）
 *
 * 名次：最匹配（打全了）→ 中文名前缀 / 全拼前缀 → 中文名包含 / 首字母前缀 → 代号前缀 → 合约名前缀 → 代号包含 → 合约名包含；
 * 同档之间停牌的沉底，再按 24h 成交额降序，再按交易所原序。
 * 拼音（bitebi / btb / tsl）浏览器里没有字典，用 scripts/gen-pinyin.swift 在 Mac 上照 iOS 同一套
 * CFStringTransform 把别名表算成 pinyin.json 提交进来；别名表改了要重跑它。
 */
import { normalize, matchOne, type Hit } from '../../market/searchText'
import { parseKey } from '../../market/identity'
import { MARKET_VENUES, venueName } from '../../venues'

// 命中规则（归一、别名、拼音、分档）挪到 market/searchText，PC 搜索与这里共用一份
export { Tier, normalize, aliasKey, CRYPTO_NAMES, aliasNames, pinyinOf, matchOne, type Hit } from '../../market/searchText'

export const HISTORY_KEY = 'hkline-m-search-history-v1'
export const HISTORY_LIMIT = 10
export const HISTORY_MAX = 24
/** 结果先列几行，其余进「查看全部」 */
export const SEARCH_PREVIEW = 6
export const HOT_LIMIT = 10

export interface Searchable { symbol: string; vol: number; price: number | null }
export interface Ranked<T> { item: T; hit: Hit }

/** 过滤 + 排名（先档、同档停牌沉底、再成交额降序、再原序） */
/** wireOf：拿来比的合约名（别家完整键 okx/usd_m/BTCUSDT 要比的是 BTCUSDT 那一段，高亮也落在它上面） */
export function rank<T extends Searchable>(list: T[], raw: string, baseOf: (s: T) => string = s => s.symbol.replace(/USDT$|USDC$/, ''),
  wireOf: (s: T) => string = s => s.symbol): Ranked<T>[] {
  const q = normalize(raw)
  const out: { r: Ranked<T>; i: number }[] = []
  list.forEach((item, i) => { const hit = matchOne(wireOf(item), baseOf(item), q); if (hit) out.push({ r: { item, hit }, i }) })
  out.sort((a, b) => {
    if (a.r.hit.tier !== b.r.hit.tier) return a.r.hit.tier - b.r.hit.tier
    const sa = a.r.item.price == null, sb = b.r.item.price == null
    if (sa !== sb) return sa ? 1 : -1
    const va = a.r.item.vol || 0, vb = b.r.item.vol || 0
    if (va !== vb) return vb - va
    return a.i - b.i
  })
  return out.map(x => x.r)
}

// ------------------------------------------------------------ 按交易所分组（2026-10-08，照 iOS SymbolSections.searchGroups / previewQuota）

/** 组序：行情交易所的注册表顺序（币安 · OKX · Bybit · Hyperliquid · Coinbase，MARKET_VENUES，和 iOS VenueRegistry.all、
 *  电脑版 pages/searchGroups SEARCH_ORDER 同一份），美元指数排最后 */
export const SEARCH_ORDER: readonly string[] = [...MARKET_VENUES.map(v => v.key), 'macro']
/** 组头：交易所全名；美元指数那一组写「指数」 */
export const groupTitle = (venue: string): string => venue === 'macro' ? '指数' : venueName(venue)

export interface RankedGroup<T> { venue: string; title: string; hits: Ranked<T>[] }
/**
 * 排好序的命中按交易所拆组（组内保持 rank 给的顺序）：一家一组；
 * 组序先按组内最好的那一档（每组第一行就是它最好的那档），同档按 SEARCH_ORDER；认不出的交易所排在最后。
 */
export function groupRanked<T extends Searchable>(hits: Ranked<T>[], venueOf: (s: T) => string = s => parseKey(s.symbol).venue): RankedGroup<T>[] {
  const by = new Map<string, Ranked<T>[]>()
  for (const h of hits) { const v = venueOf(h.item); let g = by.get(v); if (!g) by.set(v, g = []); g.push(h) }
  const rank = (v: string): number => { const i = SEARCH_ORDER.indexOf(v); return i < 0 ? SEARCH_ORDER.length : i }
  return [...by].map(([venue, hs]) => ({ venue, title: groupTitle(venue), hits: hs }))
    .sort((a, b) => (a.hits[0].hit.tier - b.hits[0].hit.tier) || (rank(a.venue) - rank(b.venue)))
}

/**
 * 搜索页每组先露几行（和 counts 一一对应）：按组序轮流每组取一行，直到总数到 budget；
 * 组数比 budget 多时每组照样一行（每家至少露出它最匹配的那一只）；取完的组跳过、名额留给后面的组。
 * 例：budget 6，[12, 3] → [3, 3]；[12, 1] → [5, 1]；五组都有 → [2, 1, 1, 1, 1]；只有一组 → [6]。
 */
export function previewQuota(counts: readonly number[], budget: number): number[] {
  const quota = counts.map(() => 0)
  const cap = Math.max(budget, counts.filter(n => n > 0).length)
  let used = 0, progressed = true
  while (used < cap && progressed) {
    progressed = false
    for (let i = 0; i < counts.length && used < cap; i++) if (quota[i] < counts[i]) { quota[i]++; used++; progressed = true }
  }
  return quota
}

/** 空搜索框时的「热门」：24h 成交额前十 */
export function hot<T extends Searchable>(list: T[], limit = HOT_LIMIT): T[] {
  return list.filter(s => s.price != null).sort((a, b) => (b.vol || 0) - (a.vol || 0)).slice(0, limit)
}

/** 把合约名按高亮切段 */
export function splitHighlight(text: string, hl: [number, number] | null, offset = 0): { text: string; hit: boolean }[] {
  if (!hl) return [{ text, hit: false }]
  const a = Math.max(0, hl[0] - offset), b = Math.min(text.length, hl[1] - offset)
  if (b <= 0 || a >= text.length || a >= b) return [{ text, hit: false }]
  return [{ text: text.slice(0, a), hit: false }, { text: text.slice(a, b), hit: true }, { text: text.slice(b), hit: false }].filter(p => p.text)
}

// ------------------------------------------------------------ 搜索历史（只记本机）

type KV = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>
const mem = new Map<string, string>()
const memKV: KV = { getItem: k => mem.get(k) ?? null, setItem: (k, v) => { mem.set(k, v) }, removeItem: k => { mem.delete(k) } }
function kv(): KV { try { return globalThis.localStorage ?? memKV } catch { return memKV } }

export const normalizeTerm = (raw: string): string => [...raw.trim()].slice(0, HISTORY_MAX).join('')
export function clean(raw: unknown): string[] {
  if (!Array.isArray(raw)) return []
  const seen = new Set<string>(), out: string[] = []
  for (const r of raw) {
    if (typeof r !== 'string') continue
    const t = normalizeTerm(r), k = t.toUpperCase()
    if (!t || seen.has(k)) continue
    seen.add(k); out.push(t)
    if (out.length >= HISTORY_LIMIT) break
  }
  return out
}
export function readHistory(store: KV = kv()): string[] {
  try { return clean(JSON.parse(store.getItem(HISTORY_KEY) || '[]')) } catch { return [] }
}
function writeHistory(list: string[], store: KV): void {
  try { if (list.length) store.setItem(HISTORY_KEY, JSON.stringify(list)); else store.removeItem(HISTORY_KEY) } catch { /* 存不下就算了 */ }
}
export function remember(raw: string, store: KV = kv()): string[] {
  const t = normalizeTerm(raw)
  if (!t) return readHistory(store)
  const next = [t, ...readHistory(store).filter(x => x.toUpperCase() !== t.toUpperCase())].slice(0, HISTORY_LIMIT)
  writeHistory(next, store)
  return next
}
export function forget(term: string, store: KV = kv()): string[] {
  const next = readHistory(store).filter(x => x.toUpperCase() !== term.toUpperCase())
  writeHistory(next, store)
  return next
}
export function clearHistory(store: KV = kv()): void { writeHistory([], store) }
