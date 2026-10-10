/* Hkline Web · 板块口径（纯函数）
 *
 * 逐条照手机端 KanpanCore `SectorAggregate.swift` / `SectorCatalog.swift` 与 app 层的
 * `SectorRows.swift`、`SectorWindowChoice.swift`、`SectorHistoryFeed.swift` 写，
 * 用例在 tests/sectors.test.ts，数字从 Swift 同名用例逐条搬过来。
 *
 * 口径：
 *   - 板块涨跌幅 = 有行情成员「这段窗口收益」的中位数（原始百分数，不是对数）。
 *   - 跑赢大盘 = 相对「全场等权池」的超额收益 > 0 的成员占比；池 = 该市场全部目录成员
 *     加兜底桶成员（按 base 去重），收益取对数后等权平均当基准。
 *   - 领涨 = 跑赢且超额收益进全场前 10%（≥ 池超额的 90 分位）。
 *   - 同一个币挂着多张合约时，计价币档次 USDT > USDC > FDUSD > BUSD > USD1 > TUSD，
 *     同档才比成交额，平手不换。
 *   - 5 日 / 20 日 = 现价 / 服务端给的日线收盘 − 1；这段数据覆盖不到有行情成员的八成就不算数。
 */
import SECTORS from '../data/sectors.json'

export type SectorMarket = 'crypto' | 'us'
export type SectorWindow = 'today' | 'd5' | 'd20'

/** symbol：挑中的那张合约（网页版点进图表用），口径计算不看它 */
export interface SectorQuote { base: string; pct: number; quoteVolume: number; price: number; symbol?: string }
export interface SectorCloses { c5?: number; c20?: number }
export interface SectorHistory { asof: string; closes: Map<string, SectorCloses> }
export interface SectorDef { id: string; name: string; market: SectorMarket; members: string[] }
export interface SectorBucket { id: string; name: string; members: string[] }
export interface SectorStat {
  id: string
  name: string
  market: SectorMarket
  pct: number
  memberCount: number
  staticCount: number
  quoteVolume: number
  isFallback: boolean
  breadth: number
  upCount: number
  frontier: string[]
  jackknife: [number, number] | null
}
export type Quotes = Map<string, SectorQuote>

export const MIN_ELIGIBLE_MEMBERS = 3
/** 有行情的成员不到三家：不算广度（跑赢大盘）、整档沉底（手机 SectorBoardOrder / SectorSubtitle 同一条） */
export const isThin = (s: Pick<SectorStat, 'memberCount'>): boolean => s.memberCount < MIN_ELIGIBLE_MEMBERS
export const MIN_WINDOW_COVERAGE = 0.8
export const EMPTY_HISTORY: SectorHistory = Object.freeze({ asof: '', closes: new Map() }) as SectorHistory

// ------------------------------------------------------------ 目录

interface SectorJSON { crypto: [string, string][]; us: [string, string, string[]][]; usNames: Record<string, string>; members: Record<string, string[]> }
const RAW = SECTORS as unknown as SectorJSON

function buildCatalog(): { crypto: SectorDef[]; us: SectorDef[] } {
  const byId = new Map<string, string[]>()
  for (const [base, ids] of Object.entries(RAW.members)) for (const id of ids) {
    const list = byId.get(id) || []
    list.push(base.toUpperCase())
    byId.set(id, list)
  }
  const crypto = RAW.crypto.filter(([id]) => id !== '---').map(([id, name]): SectorDef =>
    ({ id, name, market: 'crypto', members: [...new Set(byId.get(id) || [])].sort(cmpStr) }))
  const us = RAW.us.map(([id, name, codes]): SectorDef => ({ id, name, market: 'us', members: [...new Set(codes.map(c => c.toUpperCase()))] }))
  return { crypto, us }
}
const CATALOG = buildCatalog()
const BY_ID = new Map([...CATALOG.crypto, ...CATALOG.us].map(d => [d.id, d]))

export const catalog = {
  all: (): SectorDef[] => [...CATALOG.crypto, ...CATALOG.us],
  sectors: (m: SectorMarket): SectorDef[] => CATALOG[m],
  sector: (id: string): SectorDef | undefined => BY_ID.get(id),
  sectorsFor(base: string, m: SectorMarket): SectorDef[] {
    const k = base.toUpperCase()
    return CATALOG[m].filter(d => d.members.includes(k))
  },
  chineseName: (base: string): string | undefined => RAW.usNames[base.toUpperCase()],
}

// ------------------------------------------------------------ 小工具

/** Swift 的 String `<`（ASCII 与常用汉字下和 UTF-16 码元序一致） */
export function cmpStr(a: string, b: string): number { return a < b ? -1 : a > b ? 1 : 0 }
const fin = (v: number | undefined | null): v is number => typeof v === 'number' && Number.isFinite(v)

export function median(values: number[]): number {
  if (!values.length) throw new Error('median of empty')
  const s = values.slice().sort((a, b) => a - b)
  const n = s.length
  if (n % 2 === 1) return s[n >> 1]
  return (s[n / 2 - 1] + s[n / 2]) / 2
}

/** 线性插值分位数；p 夹在 [0, 1]；sorted 须已升序 */
export function quantile(sorted: number[], p: number): number {
  if (!sorted.length) throw new Error('quantile of empty')
  const n = sorted.length
  if (n === 1) return sorted[0]
  const pos = (n - 1) * Math.min(Math.max(p, 0), 1)
  const lo = Math.floor(pos)
  const hi = Math.min(lo + 1, n - 1)
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo)
}

export function logReturn(pct: number): number { return Math.log1p(Math.max(pct, -99.99) / 100) }

/** 删一中位数的区间；成员不到 3 个没有 */
export function jackknife(values: number[]): [number, number] | null {
  if (values.length < MIN_ELIGIBLE_MEMBERS) return null
  const s = values.slice().sort((a, b) => a - b)
  const n = s.length, m = n - 1
  const el = (i: number, j: number): number => i < j ? s[i] : s[i + 1]
  let lo = Infinity, hi = -Infinity
  for (let j = 0; j < n; j++) {
    const med = m % 2 === 1 ? el(m >> 1, j) : (el(m / 2 - 1, j) + el(m / 2, j)) / 2
    lo = Math.min(lo, med); hi = Math.max(hi, med)
  }
  return [lo, hi]
}

export function outperformCount(s: Pick<SectorStat, 'memberCount' | 'breadth'>): number {
  if (s.memberCount <= 0 || !Number.isFinite(s.breadth)) return 0
  return Math.round(s.breadth * s.memberCount)
}

// ------------------------------------------------------------ 计价币档次

export const TRADABLE_QUOTES = ['USDT', 'USDC', 'FDUSD', 'BUSD', 'USD1', 'TUSD']
export function quoteRank(quote: string): number {
  const i = TRADABLE_QUOTES.indexOf(quote.toUpperCase())
  return i < 0 ? TRADABLE_QUOTES.length : i
}
/** `BTCUSDT` → BTC + 档次；认不出计价币就整串当 base、档次垫底 */
export function tradableSplit(symbol: string): { base: string; rank: number } {
  for (let i = 0; i < TRADABLE_QUOTES.length; i++) {
    const q = TRADABLE_QUOTES[i]
    if (symbol.endsWith(q) && symbol.length > q.length) return { base: symbol.slice(0, -q.length), rank: i }
  }
  return { base: symbol, rank: TRADABLE_QUOTES.length }
}
/** 先比档次，同档才比成交额（非有限值当 −∞），平手不换 */
export function prefers(rank: number, volume: number, other: { rank: number; volume: number }): boolean {
  if (rank !== other.rank) return rank < other.rank
  const mine = Number.isFinite(volume) ? volume : -Infinity
  const theirs = Number.isFinite(other.volume) ? other.volume : -Infinity
  return mine > theirs
}

// ------------------------------------------------------------ 窗口收益

export function closeOf(c: SectorCloses | undefined, w: SectorWindow): number | undefined {
  return w === 'd5' ? c?.c5 : w === 'd20' ? c?.c20 : undefined
}
export function windowReturn(q: SectorQuote, w: SectorWindow, closes: SectorCloses | undefined): number | null {
  if (w === 'today') return fin(q.pct) ? q.pct : null
  const close = closeOf(closes, w)
  if (!fin(close) || close <= 0 || !fin(q.price) || q.price <= 0) return null
  return (q.price / close - 1) * 100
}

export interface MemberSet { bases: string[]; returns: number[]; volumeSum: number | null; staticCount: number; quotedCount: number }

export function memberSet(members: string[], quotes: Quotes, w: SectorWindow, history: SectorHistory): MemberSet {
  const set: MemberSet = { bases: [], returns: [], volumeSum: null, staticCount: 0, quotedCount: 0 }
  const seen = new Set<string>()
  for (const raw of members) {
    const base = raw.toUpperCase()
    if (seen.has(base)) continue
    seen.add(base)
    set.staticCount++
    const q = quotes.get(base)
    if (!q || !fin(q.pct)) continue
    set.quotedCount++
    const r = windowReturn(q, w, history.closes.get(base))
    if (r == null) continue
    set.bases.push(base); set.returns.push(r)
    if (fin(q.quoteVolume) && q.quoteVolume >= 0) set.volumeSum = (set.volumeSum ?? 0) + q.quoteVolume
  }
  return set
}

export function covered(set: MemberSet, w: SectorWindow): boolean {
  if (w === 'today') return true
  return set.returns.length >= MIN_WINDOW_COVERAGE * set.quotedCount
}

/** bench：全场等权池的对数收益均值（池空时 NaN）——跑赢大盘的那条基准线 */
export interface SectorPool { excess: Map<string, number>; frontierCut: number; bench: number }

export function pool(market: SectorMarket, quotes: Quotes, buckets: SectorBucket[], w: SectorWindow = 'today', history: SectorHistory = EMPTY_HISTORY): SectorPool {
  const seen = new Set<string>()
  const returns = new Map<string, number>()
  const collect = (members: string[]): void => {
    for (const raw of members) {
      const base = raw.toUpperCase()
      if (seen.has(base)) continue
      seen.add(base)
      const q = quotes.get(base); if (!q) continue
      const r = windowReturn(q, w, history.closes.get(base)); if (r == null) continue
      returns.set(base, logReturn(r))
    }
  }
  for (const d of catalog.sectors(market)) collect(d.members)
  for (const b of buckets) collect(b.members)
  if (!returns.size) return { excess: new Map(), frontierCut: Infinity, bench: NaN }
  let sum = 0
  for (const v of returns.values()) sum += v
  const b = sum / returns.size
  const excess = new Map<string, number>()
  for (const [k, v] of returns) excess.set(k, v - b)
  return { excess, frontierCut: quantile([...excess.values()].sort((x, y) => x - y), 0.9), bench: b }
}

/** 「大盘」这段窗口的涨跌幅（%）：全场等权池对数收益均值换回百分数，就是跑赢大盘比的那条线；池空给 null */
export function marketReturn(market: SectorMarket, quotes: Quotes, buckets: SectorBucket[], w: SectorWindow = 'today', history: SectorHistory = EMPTY_HISTORY): number | null {
  const b = pool(market, quotes, buckets, w, history).bench
  return Number.isFinite(b) ? Math.expm1(b) * 100 : null
}

function stat(id: string, name: string, market: SectorMarket, members: string[], quotes: Quotes, p: SectorPool, isFallback: boolean, w: SectorWindow, history: SectorHistory): SectorStat | null {
  const set = memberSet(members, quotes, w, history)
  const rets = set.returns
  if (!rets.length) return null
  let outperform = 0, up = 0
  const frontier: { base: string; e: number }[] = []
  set.bases.forEach((base, i) => {
    if (rets[i] > 0) up++
    const e = p.excess.get(base)
    if (e == null || !(e > 0)) return
    outperform++
    if (e >= p.frontierCut) frontier.push({ base, e })
  })
  frontier.sort((a, b) => a.e === b.e ? cmpStr(a.base, b.base) : b.e - a.e)
  return {
    id, name, market, pct: median(rets), memberCount: rets.length, staticCount: set.staticCount,
    quoteVolume: set.volumeSum ?? NaN, isFallback, breadth: outperform / rets.length, upCount: up,
    frontier: frontier.map(f => f.base), jackknife: jackknife(rets),
  }
}

/** 目录顺序在前、兜底桶在后；一个有行情成员都没有的板块不出现 */
export function stats(market: SectorMarket, quotes: Quotes, buckets: SectorBucket[], w: SectorWindow = 'today', history: SectorHistory = EMPTY_HISTORY): SectorStat[] {
  const p = pool(market, quotes, buckets, w, history)
  const out: SectorStat[] = []
  for (const d of catalog.sectors(market)) { const s = stat(d.id, d.name, market, d.members, quotes, p, false, w, history); if (s) out.push(s) }
  for (const b of buckets) { const s = stat(b.id, b.name, market, b.members, quotes, p, true, w, history); if (s) out.push(s) }
  return out
}

/** 这个市场在这段窗口上有没有一个目录板块凑得满三家且覆盖够（兜底桶不算） */
export function hasEligible(market: SectorMarket, quotes: Quotes, w: SectorWindow, history: SectorHistory): boolean {
  if (w !== 'today' && history.closes.size === 0) return false
  for (const d of catalog.sectors(market)) {
    const set = memberSet(d.members, quotes, w, history)
    if (set.returns.length >= MIN_ELIGIBLE_MEMBERS && covered(set, w)) return true
  }
  return false
}

export function windowMedian(members: string[], quotes: Quotes, history: SectorHistory, w: SectorWindow): number | null {
  const set = memberSet(members, quotes, w, history)
  if (!set.returns.length || !covered(set, w)) return null
  return median(set.returns)
}

// ------------------------------------------------------------ 展示层的几条规则（手机 app 层）

/** 板块列表：成员不到三家的整档沉底；其余按涨跌幅降序，非数当 −∞，并列按 id */
export function boardOrder(list: SectorStat[]): SectorStat[] {
  return list.slice().sort((a, b) => {
    const thinA = isThin(a), thinB = isThin(b)
    if (thinA !== thinB) return thinA ? 1 : -1
    const x = Number.isFinite(a.pct) ? a.pct : -Infinity
    const y = Number.isFinite(b.pct) ? b.pct : -Infinity
    return x === y ? cmpStr(a.id, b.id) : y > x ? 1 : -1
  })
}

/** 「x/N 跑赢大盘」；成员不到三家给空串（调用处整行不画） */
export function subtitle(s: Pick<SectorStat, 'memberCount' | 'breadth'>): string {
  if (isThin(s)) return ''
  return `${outperformCount(s)}/${s.memberCount} 跑赢大盘`
}

export const WINDOW_TITLE = { today: '今日', d5: '5 日' } as const
export function windowTitle(w: SectorWindow): string { return w === 'd5' ? WINDOW_TITLE.d5 : WINDOW_TITLE.today }
/** 用户停在哪一档 × 5 日算不算得出 → 实际显示哪一档、那排切换在不在、叫什么 */
export function resolveWindow(preferred: SectorWindow, hasD5: boolean): { window: SectorWindow; showsBar: boolean; title: string } {
  const window: SectorWindow = preferred === 'd5' && hasD5 ? 'd5' : 'today'
  return { window, showsBar: hasD5, title: windowTitle(window) }
}

/** 覆盖不到八成的板块不进 5 日榜（网页版的规矩；手机上那一行仍留着） */
export function rankable(market: SectorMarket, s: SectorStat, quotes: Quotes, w: SectorWindow, history: SectorHistory, buckets: SectorBucket[]): boolean {
  if (w === 'today') return true
  const members = catalog.sector(s.id)?.market === market ? catalog.sector(s.id)!.members : buckets.find(b => b.id === s.id)?.members
  if (!members) return false
  return covered(memberSet(members, quotes, w, history), w)
}

export interface SymbolRow { base: string; pct: number; price: number; quoteVolume: number; isFrontier: boolean }
/** 板块下钻的品种列表：有行情的成员；涨跌幅跟窗口，价格永远是现价；按涨跌幅降序，缺数沉底，并列按代号 */
export function symbolRows(members: string[], quotes: Quotes, frontier: string[] = [], w: SectorWindow = 'today', history: SectorHistory = EMPTY_HISTORY): SymbolRow[] {
  const f = new Set(frontier)
  const rows: SymbolRow[] = []
  for (const base of members) {
    const q = quotes.get(base); if (!q) continue
    rows.push({ base, pct: windowReturn(q, w, history.closes.get(base)) ?? NaN, price: q.price, quoteVolume: q.quoteVolume, isFrontier: f.has(base) })
  }
  return rows.sort((a, b) => {
    const x = Number.isFinite(a.pct) ? a.pct : -Infinity
    const y = Number.isFinite(b.pct) ? b.pct : -Infinity
    return x === y ? cmpStr(a.base, b.base) : y > x ? 1 : -1
  })
}

// ------------------------------------------------------------ 5 日 / 20 日收盘

const DAY_MS = 86_400_000
/** 严格的 `YYYY-MM-DD`，而且得是日历上真有的一天；返回那天 UTC 零点的毫秒 */
export function parseDay(asof: string): number | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(asof)
  if (!m) return null
  const y = +m[1], mo = +m[2], d = +m[3]
  const t = Date.UTC(y, mo - 1, d)
  const back = new Date(t)
  if (back.getUTCFullYear() !== y || back.getUTCMonth() !== mo - 1 || back.getUTCDate() !== d) return null
  return t
}
export const MAX_AGE_DAYS = 7
/** 服务端按 UTC 跨日：过去 7 天内、未来 2 天内都算新鲜 */
export function isFresh(asof: string, now = Date.now()): boolean {
  const t = parseDay(asof)
  if (t == null) return false
  const days = (now - t) / DAY_MS
  return days >= -2 && days <= MAX_AGE_DAYS
}
/** next 能不能顶掉手上这份：日期更新的认；同一天只认覆盖面更大的 */
export function supersedes(next: SectorHistory, held: SectorHistory): boolean {
  const mine = parseDay(next.asof)
  if (next.closes.size === 0 || mine == null) return false
  const theirs = parseDay(held.asof)
  if (held.closes.size === 0 || theirs == null) return true
  if (mine !== theirs) return mine > theirs
  return next.closes.size > held.closes.size
}
export function accepts(held: SectorHistory, next: SectorHistory, now = Date.now()): boolean {
  return isFresh(next.asof, now) && supersedes(next, held)
}

function num(v: unknown): number | undefined {
  const n = typeof v === 'number' ? v : typeof v === 'string' && v.trim() !== '' ? Number(v) : NaN
  return Number.isFinite(n) && n > 0 ? n : undefined
}
/** `{"data":{"asof":…,"symbols":{"BTCUSDT":{"c5":…,"c20":…}}}}` → 以大写 base 为键；同 base 按计价币档次留一张 */
export function decodeHistory(body: unknown): SectorHistory | null {
  const data = (body as { data?: unknown } | null)?.data as { asof?: unknown; symbols?: unknown } | undefined
  if (!data || typeof data.asof !== 'string' || parseDay(data.asof) == null) return null
  const symbols = data.symbols
  if (!symbols || typeof symbols !== 'object' || Array.isArray(symbols)) return null
  const closes = new Map<string, SectorCloses>()
  const rank = new Map<string, number>()
  for (const [raw, row] of Object.entries(symbols as Record<string, unknown>)) {
    if (!row || typeof row !== 'object') continue
    const sp = tradableSplit(raw.toUpperCase())
    const old = rank.get(sp.base)
    if (old != null && old <= sp.rank) continue
    const r = row as Record<string, unknown>
    const c5 = num(r.c5), c20 = num(r.c20)
    if (c5 == null && c20 == null) continue
    rank.set(sp.base, sp.rank)
    const c: SectorCloses = {}
    if (c5 != null) c.c5 = c5
    if (c20 != null) c.c20 = c20
    closes.set(sp.base, c)
  }
  if (!closes.size) return null
  return { asof: data.asof, closes }
}

/** 取失败后第 n 次重试等多久：5、15、45 秒…封顶 10 分钟；没失败就 10 分钟一拍 */
export const HISTORY_TICK_S = 600
export function historyRetryDelay(failures: number): number {
  if (failures <= 0) return HISTORY_TICK_S
  return Math.min(5 * Math.pow(3, Math.min(failures - 1, 16)), HISTORY_TICK_S)
}

// ------------------------------------------------------------ 兜底桶

export interface CatalogEntry { symbol: string; baseAsset: string; quoteAsset: string; underlyingType?: string; underlyingSubType?: string[] }
const PRECIOUS = new Set(['XAU', 'XAG', 'XPT', 'XPD'])
/** 交易所元数据上这张合约属于哪个市场（只认加密与美国股票，其余一律不进这两页） */
export function marketOf(e: Pick<CatalogEntry, 'baseAsset' | 'underlyingType'>): SectorMarket | null {
  if (PRECIOUS.has(e.baseAsset.toUpperCase())) return null
  const u = e.underlyingType?.toUpperCase()
  return u === 'COIN' ? 'crypto' : u === 'EQUITY' ? 'us' : null
}
const TAG_ORDER = ['infrastructure', 'alpha', 'defi']
const BUCKET_ORDER = ['tag-infrastructure', 'tag-alpha', 'tag-defi', 'misc']
const BUCKET_NAMES: Record<string, string> = { 'tag-infrastructure': '基础设施', 'tag-alpha': '币安 Alpha', 'tag-defi': 'DeFi 其他', misc: '其他' }

/** 不在目录里的币按交易所自带的标签兜底成几个桶；同一个 base 只认第一张合约 */
export function fallbackBuckets(entries: CatalogEntry[], market: SectorMarket): SectorBucket[] {
  const known = new Set(catalog.sectors(market).flatMap(d => d.members))
  const buckets = new Map<string, string[]>()
  const seen = new Set<string>()
  for (const e of entries) {
    if (marketOf(e) !== market) continue
    const base = e.baseAsset.toUpperCase()
    if (known.has(base) || seen.has(base)) continue
    seen.add(base)
    const tags = new Set((e.underlyingSubType || []).map(t => t.toLowerCase()).filter(t => t !== 'crypto' && t !== 'tradfi'))
    const hit = TAG_ORDER.find(t => tags.has(t))
    const key = hit ? 'tag-' + hit : 'misc'
    const list = buckets.get(key) || []
    list.push(base)
    buckets.set(key, list)
  }
  return BUCKET_ORDER.filter(k => buckets.get(k)?.length).map(k => ({ id: k, name: BUCKET_NAMES[k], members: buckets.get(k)!.slice().sort(cmpStr) }))
}

export interface Ticker { symbol: string; pct: number; quoteVolume: number; price: number }
/** 全量 24h 行情 → 以 base 为键；base 与计价币照品种表，没有就按后缀拆 */
export function ingest(tickers: Ticker[], index?: Map<string, CatalogEntry>): Quotes {
  const next: Quotes = new Map()
  const picked = new Map<string, { rank: number; volume: number }>()
  for (const t of tickers) {
    if (!Number.isFinite(t.pct) || !Number.isFinite(t.price)) continue
    const sym = t.symbol.toUpperCase()
    const info = index?.get(sym)
    if (index && index.size && !info) continue // 品种表里没有（已下架、交割）就不认
    const base = info ? info.baseAsset.toUpperCase() : tradableSplit(sym).base
    if (!base) continue
    const rank = info ? quoteRank(info.quoteAsset) : tradableSplit(sym).rank
    const old = picked.get(base)
    if (old && !prefers(rank, t.quoteVolume, old)) continue
    picked.set(base, { rank, volume: t.quoteVolume })
    next.set(base, { base, pct: t.pct, quoteVolume: t.quoteVolume, price: t.price, symbol: sym })
  }
  return next
}
