/* Hkline Web · 搜索结果按交易所分区（电脑版搜索弹层、对比弹层共用；2026-10-08）
 *
 * 像 TradingView / AICoin：同一个币在不同交易所是不同品种。一家一组，组头是交易所全名；组内按现有排序
 * （匹配档 → 空查询时自选在前 → 24h 成交额）；组序先按组内最好的匹配档、同档按注册表顺序（币安 · OKX · Bybit ·
 * Hyperliquid · Coinbase，同 iOS），美元指数这一组（自家服务器的指数）排在最后。每组各自封顶。
 * 别家的品种表懒拉：弹层打开时拉全部（market/rest.ts loadAllVenues），还在路上 / 取不到的在列表底下一行说明。
 */
import { S, groupSearch, headName, type SearchGroup, type Sym } from '../market'
import { normalize } from '../market/searchText'
import { DEFAULT_VENUE } from '../market/identity'
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
