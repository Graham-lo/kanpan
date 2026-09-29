/* Hkline Web · 板块页的今日行情（照手机端 SectorFeed）
 *
 * - 品种表：进板块页才取一次 exchangeInfo（会话内只取一次），留下全部在交易的永续
 *   （各计价币都要，挑合约与兜底桶要用 underlyingType / underlyingSubType）。
 * - 行情：页面开着时每 10 秒拉一次全量 ticker/24hr，照手机的挑合约规则落成「base → 行情」；
 *   第一帧先拿启动时已有的 USDT 全市场表垫着，不白等。
 * - 正在看的那个板块的成员另外订 ticker 推送（页里经 hooks.extraStreams），推送到了只改那几格。
 */
import { REST, S, j } from '../market'
import { fallbackBuckets, ingest, tradableSplit } from './aggregate'
import type { CatalogEntry, Quotes, SectorBucket, SectorMarket, Ticker } from './aggregate'

interface ExRow { symbol: string; baseAsset: string; quoteAsset: string; contractType: string; status: string; underlyingType?: string; underlyingSubType?: string[] }
interface Ticker24 { symbol: string; lastPrice: string; priceChangePercent: string; quoteVolume: string }

export const POLL_MS = 10_000
const num = (v: unknown): number => typeof v === 'string' && v.trim() !== '' ? Number(v) : typeof v === 'number' ? v : NaN

export const feed = {
  quotes: new Map() as Quotes,
  entries: [] as CatalogEntry[],
  index: new Map<string, CatalogEntry>(),
  buckets: { crypto: [], us: [] } as Record<SectorMarket, SectorBucket[]>,
  /** 最近一次全量行情拉到没有（null = 还没拉过） */
  ok: null as boolean | null,
}

let catalogP: Promise<void> | null = null
let catalogFailedAt = 0
function loadCatalog(): Promise<void> {
  if (feed.entries.length) return Promise.resolve()
  if (catalogP) return catalogP
  if (Date.now() - catalogFailedAt < 60_000) return Promise.resolve()
  catalogP = j<{ symbols: ExRow[] }>(`${REST}/fapi/v1/exchangeInfo`, 15_000).then(ex => {
    const entries: CatalogEntry[] = []
    for (const e of ex.symbols) {
      if (e.status !== 'TRADING') continue
      if (e.contractType !== 'PERPETUAL' && e.contractType !== 'TRADIFI_PERPETUAL') continue
      entries.push({ symbol: e.symbol, baseAsset: e.baseAsset, quoteAsset: e.quoteAsset, underlyingType: e.underlyingType, underlyingSubType: e.underlyingSubType })
    }
    if (!entries.length) throw new Error('empty exchangeInfo')
    feed.entries = entries
    feed.index = new Map(entries.map(e => [e.symbol, e]))
    feed.buckets = { crypto: fallbackBuckets(entries, 'crypto'), us: fallbackBuckets(entries, 'us') }
  }).catch(() => { catalogFailedAt = Date.now() }).finally(() => { catalogP = null })
  return catalogP
}

/** 第一帧：启动时已经有的 USDT 全市场表（base 按合约名拆，保留 1000 前缀，和目录一致） */
export function seedFromUniverse(): boolean {
  if (feed.quotes.size || !S.symbols.size) return false
  const list: Ticker[] = []
  for (const s of S.symbols.values()) list.push({ symbol: s.symbol, pct: s.pct ?? NaN, quoteVolume: s.vol, price: s.price ?? NaN })
  feed.quotes = ingest(list, feed.index.size ? feed.index : undefined)
  return feed.quotes.size > 0
}

async function pollOnce(): Promise<void> {
  await loadCatalog()
  try {
    const rows = await j<Ticker24[]>(`${REST}/fapi/v1/ticker/24hr`, 10_000)
    const list: Ticker[] = rows.map(t => ({ symbol: t.symbol, pct: num(t.priceChangePercent), quoteVolume: num(t.quoteVolume), price: num(t.lastPrice) }))
    const next = ingest(list, feed.index.size ? feed.index : undefined)
    if (next.size) { feed.quotes = next; feed.ok = true } else feed.ok = feed.quotes.size > 0
  } catch {
    feed.ok = feed.quotes.size > 0 ? true : false
    throw new Error('ticker')
  }
}

let timer: ReturnType<typeof setTimeout> | undefined
let running = false
let failures = 0
/** 开始轮询；每拉到一次就回调一次。页面离开时 stopFeed() */
export function startFeed(onChange: () => void): void {
  if (running) return
  running = true
  const tick = (): void => {
    if (!running) return
    if (document.hidden) { timer = setTimeout(tick, POLL_MS); return }
    pollOnce().then(() => { failures = 0 }, () => { failures++ }).finally(() => {
      if (!running) return
      onChange()
      timer = setTimeout(tick, failures ? Math.min(POLL_MS * 2 ** Math.min(failures, 2), 30_000) : POLL_MS)
    })
  }
  tick()
}
export function stopFeed(): void { running = false; clearTimeout(timer) }

/** 推送来的 ticker：只认这个 base 挑中的那张合约，其余不动 */
export function applyLive(symbols: Iterable<string>): void {
  for (const k of symbols) {
    const s = S.symbols.get(k); if (!s || s.price == null || s.pct == null) continue
    const base = (feed.index.get(k)?.baseAsset ?? tradableSplit(k).base).toUpperCase()
    const q = feed.quotes.get(base); if (!q || q.symbol !== k) continue
    q.price = s.price; q.pct = s.pct
    if (Number.isFinite(s.vol) && s.vol > 0) q.quoteVolume = s.vol
  }
}
