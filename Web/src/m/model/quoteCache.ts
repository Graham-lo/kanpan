/* 手机网页版 · 上次看到的品种表与价（体感：开页先有数，不是一排「—」）
 *
 * 全市场表（market 的 S.symbols）要等 exchangeInfo + 24hr 两个整表回来才有；网慢时自选、头部价、搜索都要空等。
 * 这里把表里展示要用的那几列（代号、中文名、类别、小数位、价、涨跌、成交额、板块标签、上线时间）
 * 节流记进本机，开页时先拿它顶上：
 * - 自选行、行情页头部：实时价没到时摆上次的价（退灰），到了就换；
 * - 搜索、换品种：表没到时按上次的表搜。
 * 只读不写回 S.symbols——提醒、订单流这些会把它当实时价用。
 */
import { S, on } from '../../market'
import type { Sym } from '../../market/symbols'
import { venueOf } from '../../market/identity'

export const QUOTE_CACHE_KEY = 'hkline-m-quotes-v1'
/** 行情跳动时最多多久记一次 */
export const QUOTE_SAVE_MS = 10_000
/** 太久以前的表不拿来顶（下架、改名都可能变过） */
export const QUOTE_KEEP_MS = 14 * 86_400_000

/** 记下来的一行（键短，整表几百只也就几十 KB） */
export type CachedSym = Pick<Sym, 'symbol' | 'base' | 'code' | 'kind' | 'cn' | 'dec' | 'color' | 'price' | 'chg' | 'pct' | 'vol'>
  & Partial<Pick<Sym, 'ut' | 'tags' | 'onboard' | 'macro'>>

interface Stored { at: number; rows: CachedSym[] }

type KV = Pick<Storage, 'getItem' | 'setItem'>
const kv = (): KV | null => { try { return globalThis.localStorage ?? null } catch { return null } }

/** 表里一行 → 记下来的那一行 */
export function compact(s: Sym): CachedSym {
  const r: CachedSym = { symbol: s.symbol, base: s.base, code: s.code, kind: s.kind, cn: s.cn, dec: s.dec, color: s.color, price: s.price, chg: s.chg, pct: s.pct, vol: s.vol }
  if (s.ut) r.ut = s.ut
  if (s.tags?.length) r.tags = s.tags
  if (s.onboard) r.onboard = s.onboard
  if (s.macro) r.macro = true
  return r
}

/** 记下来的一行 → 搜索 / 列表能直接用的 Sym（缺的实时字段一律空） */
export function expand(r: CachedSym): Sym {
  return { ...r, venue: r.macro ? 'macro' : venueOf(r.symbol), quote: r.macro ? '' : 'USDT', fr: null, nextFunding: null }
}

export function readQuotes(store: KV | null = kv(), now = Date.now()): Stored | null {
  try {
    const raw = store?.getItem(QUOTE_CACHE_KEY)
    if (!raw) return null
    const v = JSON.parse(raw) as Stored
    if (!v || !Array.isArray(v.rows) || !(v.at > 0) || now - v.at > QUOTE_KEEP_MS) return null
    return v
  } catch { return null }
}

export function writeQuotes(rows: CachedSym[], store: KV | null = kv(), now = Date.now()): boolean {
  if (!store || !rows.length) return false
  try { store.setItem(QUOTE_CACHE_KEY, JSON.stringify({ at: now, rows } satisfies Stored)); return true } catch { return false }
}

// ---------------------------------------------------------------- 本页这一份

let table: Map<string, Sym> | null = null
let list: Sym[] | null = null
const load = (): Map<string, Sym> => {
  if (table) return table
  table = new Map()
  for (const r of readQuotes()?.rows ?? []) if (r && typeof r.symbol === 'string') table.set(r.symbol, expand(r))
  list = [...table.values()]
  return table
}

/** 上次记下的这一只（实时表里已有就别用它） */
export function cachedSym(symbol: string): Sym | null {
  install()
  return load().get(symbol.toUpperCase()) ?? null
}

/** 上次记下的整表（实时表没到时拿来搜） */
export function cachedTable(): Sym[] {
  install()
  load()
  return list ?? []
}

/** 展示用的品种表：实时表有就用实时表，没有就用上次的 */
export function symbolsForDisplay(): { list: Sym[]; cached: boolean } {
  if (S.symbols.size) return { list: [...S.symbols.values()], cached: false }
  const t = cachedTable()
  return { list: t, cached: t.length > 0 }
}

/** 一只品种的展示行：实时表有就是实时的，没有就退到上次记下的（cached = true，调用方退灰） */
export function symForDisplay(symbol: string): { s: Sym | null; cached: boolean } {
  const live = S.symbols.get(symbol)
  if (live) return { s: live, cached: false }
  // 实时表已经到了却没这只：下架了，不拿旧价顶
  if (S.live === true) return { s: null, cached: false }
  const c = cachedSym(symbol)
  return { s: c, cached: !!c }
}

// ---------------------------------------------------------------- 记

let installed = false
let lastSave = 0
let timer: ReturnType<typeof setTimeout> | null = null

/** 把实时表记一次（实时表没到时什么都不写，不拿空表盖掉上次的） */
export function saveNow(): void {
  if (timer) { clearTimeout(timer); timer = null }
  if (!S.symbols.size || S.live !== true) return
  const rows: CachedSym[] = []
  for (const s of S.symbols.values()) rows.push(compact(s))
  if (writeQuotes(rows)) lastSave = Date.now()
}

function schedule(delay: number): void {
  if (timer) return
  timer = setTimeout(() => { timer = null; saveNow() }, delay)
}

/** 跟着行情记（幂等）：表一到就记，行情跳动按 QUOTE_SAVE_MS 节流，切后台 / 关页补记一次 */
export function install(): void {
  if (installed || typeof window === 'undefined') return
  installed = true
  on(e => {
    if (e.type === 'universe') schedule(1000)
    else if (e.type === 'ticker') schedule(Math.max(0, lastSave + QUOTE_SAVE_MS - Date.now()))
  })
  addEventListener('pagehide', () => saveNow())
  document.addEventListener('visibilitychange', () => { if (document.hidden) saveNow() })
  if (S.symbols.size && S.live === true) schedule(1000)
}

/** 测试用：丢掉本页这一份 */
export function _resetQuoteCache(): void {
  table = null; list = null
  if (timer) clearTimeout(timer)
  timer = null; lastSave = 0
}
