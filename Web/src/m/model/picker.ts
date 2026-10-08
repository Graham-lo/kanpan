/* 手机网页版 · 品种整页的纯逻辑（照 iOS KanpanCore/Model/MarketSector.swift 与 Symbols/SymbolSections.swift）
 *
 * 搜索页「查看全部 N 个品种」进来的那一页：页头「品种 · N 个永续合约」，两颗筛选小块（市场 / 板块），
 * 下面分组列表——没打字时 自选 → 最近 → 全部合约（按 24h 成交额降序，120 条封顶）；
 * 打了字按交易所分组（2026-10-08，照 iOS SymbolSections.searchGroups）：一家一组，组头交易所全名 + 命中数，
 * 组序先按组内最好的匹配档、同档按注册表；组内先最匹配、同档停牌沉底再按成交额，每组各自 160 条封顶；一条都没命中时一组空的「搜到 0 个」。
 */
import { groupRanked, normalize, rank, type Hit } from './search'
import { parseKey, wireSymbol } from '../../market/identity'

/** 市场：贵金属按代号认（XAU/XAG/XPT/XPD 本身就是 ISO 资产代码），其余只看交易所给的 underlyingType，缺了不猜 */
const METALS = new Set(['XAU', 'XAG', 'XPT', 'XPD'])
const BY_UT: Record<string, string> = {
  COIN: 'crypto', EQUITY: 'us', HK_EQUITY: 'hk', KR_EQUITY: 'kr', CN_EQUITY: 'cn',
  COMMODITY: 'commodities', INDEX: 'index', PREMARKET: 'premarket',
}
export interface PickerSym { symbol: string; base: string; ut?: string; tags?: string[]; vol: number; price: number | null; venue?: string }

/** 别家（OKX / Bybit / Hyperliquid / Coinbase）的品种表不给 underlyingType：它们只挂加密币，归「加密」 */
export function marketOf(s: Pick<PickerSym, 'base' | 'ut' | 'venue'>): string {
  if (METALS.has(s.base.toUpperCase())) return 'metals'
  if (!s.ut && s.venue && s.venue !== 'binance' && s.venue !== 'macro') return 'crypto'
  return s.ut ? BY_UT[s.ut.toUpperCase()] ?? 'other' : 'other'
}
export const MARKET_ORDER = ['crypto', 'us', 'hk', 'kr', 'cn', 'equity', 'metals', 'commodities', 'index', 'premarket', 'other'] as const

const TITLES: Record<string, string> = {
  all: '全部市场', crypto: '加密', us: '美股', hk: '港股', kr: '韩股', cn: 'A股',
  equity: '股票', metals: '贵金属', commodities: '大宗商品', index: '指数', premarket: '盘前', other: '其他',
  'layer-1': 'Layer 1', 'layer-2': 'Layer 2', defi: 'DeFi', ai: 'AI', meme: 'Meme', nft: 'NFT',
  gaming: '游戏', infrastructure: '基础设施', storage: '存储', payment: '支付', metaverse: '元宇宙',
  pow: 'PoW', rwa: 'RWA', etf: 'ETF', alpha: 'Alpha', chinese: '中国概念',
}
/** 市场与板块的中文名；没收录的板块原样显示交易所给的那个词 */
export const marketTitle = (key: string): string => TITLES[key] ?? key

/** 一只品种的板块（交易所 underlyingSubType 小写去重，剔掉 crypto / tradfi 这两个大类词） */
export const tagsOf = (s: Pick<PickerSym, 'tags'>): string[] =>
  [...new Set((s.tags ?? []).map(t => t.toLowerCase()))].filter(t => t !== 'crypto' && t !== 'tradfi').sort()

export interface Filtered<T> { markets: string[]; sectors: string[]; list: T[] }
/** 照 rebuildFilter：在场的市场按固定次序；板块从按市场筛过的那份里收；再按板块筛 */
export function applyFilter<T extends PickerSym>(catalog: readonly T[], market: string, sector: string | null): Filtered<T> {
  const present = new Set(catalog.map(marketOf))
  const markets = MARKET_ORDER.filter(m => present.has(m))
  const base = catalog.filter(s => market === 'all' || marketOf(s) === market)
  const sectors = [...new Set(base.flatMap(tagsOf))].sort()
  const list = sector == null ? base : base.filter(s => tagsOf(s).includes(sector))
  return { markets, sectors, list }
}

export const ALL_LIMIT = 120
export const SEARCH_LIMIT = 160
export const EMPTY_TEXT = '没有这个品种'
export const moreNote = (more: number): string | null => more > 0 ? `还有 ${more} 个，搜名字更快。` : null

export interface PickerRow { symbol: string; hl: Hit['hl'] }
/** count：搜索组的命中总数（含封顶没列出来的），组头上写着；别的组不给 */
export interface PickerSection { kind: 'search' | 'favorites' | 'recents' | 'all'; title: string; rows: PickerRow[]; more: number; count?: number; venue?: string }

/**
 * 分组（SymbolSections.build）。
 * list：筛过的品种表；known：整张品种表的代号（不随筛选变）。
 * 自选 / 最近里品种表认得、只是不属于当前筛选的不列；品种表压根不认得的照旧列一行占位（价格那一格写「—」），
 * 不然一个已下架的自选就凭空没了，用户只会以为是自己手滑删的。品种表还没到（known 空）时不当它是「不认得」，照常列。
 */
export function buildSections<T extends PickerSym>(list: readonly T[], o: { query: string; favorites: readonly string[]; recents: readonly string[]; known: ReadonlySet<string> }): PickerSection[] {
  const q = normalize(o.query)
  if (q) {
    // 别家完整键（okx/usd_m/BTCUSDT）比的是代号那一段；币安的 base 照旧是去掉 1000 前缀的底
    const hits = rank([...list], q, s => s.base, s => wireSymbol(s.symbol))
    if (!hits.length) return [{ kind: 'search', title: '搜到 0 个', rows: [], more: 0, count: 0 }]
    return groupRanked(hits, s => s.venue ?? parseKey(s.symbol).venue).map(g => ({
      kind: 'search', title: g.title, venue: g.venue, count: g.hits.length,
      rows: g.hits.slice(0, SEARCH_LIMIT).map(h => ({ symbol: h.item.symbol, hl: h.hit.hl })), more: Math.max(0, g.hits.length - SEARCH_LIMIT),
    }))
  }
  const inList = new Set(list.map(s => s.symbol))
  const keep = (sym: string): boolean => inList.has(sym) || !o.known.has(sym)
  const out: PickerSection[] = []
  const shown = new Set<string>()
  const favs = o.favorites.filter(keep)
  if (favs.length) { favs.forEach(s => shown.add(s)); out.push({ kind: 'favorites', title: '自选', rows: favs.map(symbol => ({ symbol, hl: null })), more: 0 }) }
  const recents = o.recents.filter(s => !shown.has(s) && keep(s))
  if (recents.length) { recents.forEach(s => shown.add(s)); out.push({ kind: 'recents', title: '最近', rows: recents.map(symbol => ({ symbol, hl: null })), more: 0 }) }
  // 「全部合约」：剔掉上面露过脸的，按 24h 成交额降序，同额保持交易所原序。
  // 品种表本来就只收在交易的（TRADING），停牌、已交割的不在里面；行情还没到的成交额算 0，落在末尾
  const pool = list.map((s, i) => ({ s, i })).filter(x => !shown.has(x.s.symbol))
    .sort((a, b) => (b.s.vol || 0) - (a.s.vol || 0) || a.i - b.i)
  if (pool.length) out.push({ kind: 'all', title: '全部合约', rows: pool.slice(0, ALL_LIMIT).map(x => ({ symbol: x.s.symbol, hl: null })), more: Math.max(0, pool.length - ALL_LIMIT) })
  return out
}

/** 页头右边那行小字：「571 个永续合约」；有现货（Coinbase）时后面接「· 300 个现货」（照 iOS SymbolSections.countText） */
export function countText(catalog: readonly { symbol?: string }[]): string {
  const spot = catalog.filter(s => typeof s.symbol === 'string' && parseKey(s.symbol).market === 'spot').length
  const perps = `${catalog.length - spot} 个永续合约`
  return spot ? `${perps} · ${spot} 个现货` : perps
}
