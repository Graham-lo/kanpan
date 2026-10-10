/* Hkline Web · 搜索结果按交易所分区（电脑版搜索弹层、对比弹层共用；2026-10-08）
 *
 * 像 TradingView / AICoin：同一个币在不同交易所是不同品种。一家一组，组头是交易所全名；组内按现有排序
 * （匹配档 → 空查询时自选在前 → 24h 成交额）；组序先按组内最好的匹配档、同档按注册表顺序（币安 · OKX · Bybit ·
 * Hyperliquid · Coinbase，同 iOS），美元指数这一组（自家服务器的指数）排在最后。每组各自封顶。
 * 别家的品种表懒拉：弹层打开时拉全部（market/rest.ts loadAllVenues），还在路上 / 取不到的在列表底下一行说明。
 */
import { S, groupSearch, headName, matchScore, type SearchGroup, type Sym } from '../market'
import { normalize } from '../market/searchText'
import { DEFAULT_VENUE, parseKey } from '../market/identity'
import { MARKET_VENUES, venueName } from '../venues'
import { esc } from '../ui/dom'

/** 组序：行情交易所的注册表顺序（MARKET_VENUES：币安 · OKX · Bybit · Hyperliquid · Coinbase，和 iOS VenueRegistry.all 一致），
 *  美元指数（macro）排最后。原来用的是订单流的合并顺序 VENUE_LIST（Coinbase 排在 Bybit 前面），同档时组序和 iOS 对不上 */
export const SEARCH_ORDER: readonly string[] = [...MARKET_VENUES.map(v => v.key), 'macro']
/** 组头：交易所全名；美元指数那一组写「指数」 */
export const groupTitle = (venue: string): string => venue === 'macro' ? '指数' : venueName(venue)

/** 分好组的结果，以及按显示顺序摊平的一列（键盘上下、回车用的下标就是它的下标） */
export function searchGroups(pool: Sym[], q: string, watched: (k: string) => boolean): { groups: SearchGroup<Sym>[]; flat: Sym[] } {
  const groups = groupSearch(pool, q, SEARCH_ORDER, watched, normalize(q) ? 40 : 12)
  return { groups, flat: groups.flatMap(g => g.items) }
}

/** 一行的名字：基础币 + 计价（「BTCUSDT」），交易所由组头说明，打到的那一截高亮 */
export function resultName(s: Sym, qq: string): string {
  const head = headName(s) + s.quote
  const hl = qq && head.toUpperCase().startsWith(qq) ? `<mark>${esc(head.slice(0, qq.length))}</mark>${esc(head.slice(qq.length))}` : esc(head)
  return hl
}

/** 组头 */
export const groupHead = (g: SearchGroup<Sym>): string => `<div class="sr-group" role="presentation">${esc(groupTitle(g.venue))}<span class="faint num">${g.items.length}</span></div>`

/** 别家的表还在路上 / 取不到：列表底下一行小字（不挡结果） */
export function venueStatusHTML(): string {
  const loading: string[] = [], failed: string[] = []
  for (const v of MARKET_VENUES) {
    if (v.key === DEFAULT_VENUE) continue
    const st = S.venues[v.key]
    if (!st || st.live == null) loading.push(v.market.displayName)
    else if (st.live === false) failed.push(v.market.displayName)
  }
  const parts = [loading.length ? `正在取 ${loading.join('、')} 的品种表…` : '', failed.length ? `${failed.join('、')} 的品种表取不到` : ''].filter(Boolean)
  return parts.length ? `<div class="sr-group faint" role="presentation">${esc(parts.join('；'))}</div>` : ''
}

// ------------------------------------------------------------ 按品种聚合（2026-10-10 审查 C2）
/*
 * 搜索弹层默认一个品种一行：同一个基础币在几家交易所的合约并成一行，交易所做行尾小记号（pages/symbolSearch.ts）。
 * 原来一家一组，搜 ETH 出九行（币安 / OKX / Bybit 各三只），想要的那只被淹没。
 * 并行的键 = 分类 + 去掉倍数前缀的基础币（Sym.base：1000PEPE / kPEPE 都并进 PEPE）；美股 / 大宗 / 美元指数这类只一家有的照常一行。
 * 行序：最好的匹配档 → 空查询时有自选的在前 → 有价的在前 → 各家 24h 成交额之和。
 * 行内各家按注册表顺序（币安 · OKX · Bybit · Hyperliquid · Coinbase，同 SEARCH_ORDER），记号的位置每行一致。
 * 回车 / 点行打开的那一家（pick）：匹配档最高的 → 当前图所在的那一家 → 自选里有的 → 币安 → 注册表顺序。
 */
export interface SearchRow {
  /** 并行的键：分类 + 基础币 */
  id: string
  /** 这一行里的各家，按注册表顺序 */
  items: Sym[]
  /** 默认打开 items 里的第几只 */
  pick: number
  /** 这一行最好的匹配分（matchScore） */
  best: number
}

const orderOf = (v: string): number => { const i = SEARCH_ORDER.indexOf(v); return i < 0 ? SEARCH_ORDER.length : i }
const venueKey = (s: Sym): string => s.venue || parseKey(s.symbol).venue

/** 有字时最多几行、空查询时最多几行 */
export const ROW_LIMIT = 40, BLANK_ROW_LIMIT = 24

/** 搜索结果按品种聚合成行。current：当前图那只的键（回车默认开它所在的那一家） */
export function searchRows(pool: Sym[], q: string, watched: (k: string) => boolean, current = '', limit?: number): SearchRow[] {
  const blank = !normalize(q)
  const cur = current ? parseKey(current).venue : ''
  const by = new Map<string, { s: Sym; m: number }[]>()
  for (const s of pool) {
    const m = matchScore(s, q)
    if (m <= 0) continue
    const id = `${s.kind}|${s.base || s.code || s.symbol}`
    let g = by.get(id); if (!g) by.set(id, g = [])
    g.push({ s, m })
  }
  const rows: (SearchRow & { w: boolean; priced: boolean; vol: number })[] = []
  for (const [id, xs] of by) {
    xs.sort((a, b) => (orderOf(venueKey(a.s)) - orderOf(venueKey(b.s))) || ((b.s.vol || 0) - (a.s.vol || 0)))
    let pick = 0
    const rank = (x: { s: Sym; m: number }): number[] => [x.m, +(cur !== '' && venueKey(x.s) === cur), +watched(x.s.symbol), +(venueKey(x.s) === DEFAULT_VENUE)]
    xs.forEach((x, i) => { if (i === pick) return; const a = rank(x), b = rank(xs[pick]); for (let k = 0; k < a.length; k++) { if (a[k] !== b[k]) { if (a[k] > b[k]) pick = i; break } } })
    rows.push({ id, items: xs.map(x => x.s), pick, best: Math.max(...xs.map(x => x.m)),
      w: xs.some(x => watched(x.s.symbol)), priced: xs.some(x => x.s.price != null), vol: xs.reduce((a, x) => a + (x.s.vol || 0), 0) })
  }
  rows.sort((a, b) => (b.best - a.best) || (blank ? +b.w - +a.w : 0) || (+b.priced - +a.priced) || (b.vol - a.vol))
  return rows.slice(0, limit ?? (blank ? BLANK_ROW_LIMIT : ROW_LIMIT)).map(({ id, items, pick, best }) => ({ id, items, pick, best }))
}

/** 一行的名字：基础币（不带计价，计价随交易所变），打到的那一截高亮 */
export function rowName(s: Sym, qq: string): string {
  const head = s.macro ? headName(s) : (s.code || s.base || headName(s))
  return qq && head.toUpperCase().startsWith(qq) ? `<mark>${esc(head.slice(0, qq.length))}</mark>${esc(head.slice(qq.length))}` : esc(head)
}
