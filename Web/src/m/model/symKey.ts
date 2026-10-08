/* 手机网页版 · 品种键与品种展示的小件（2026-10-08 多交易所，三端一致）
 *
 * 身份照共用层 market/identity.ts：币安 U 本位裸代号（BTCUSDT）、美元指数 DXY、别家完整键
 * okx/usd_m/BTCUSDT、bybit/usd_m/1000PEPEUSDT、hyperliquid/usd_m/KPEPE、coinbase/spot/BTC-USD。
 * 手机页各处原来拿 toUpperCase() 归一裸代号——完整键大写之后（OKX/USD_M/…）就认不出来了，一律改走 normKey。
 *
 * 展示（照 docs 框架设计第 7 节）：
 *   - 列表行：名字前一截灰小字缩写（币安 / OKX / Bybit / HL / CB，美元指数不带）+「DOGE / USDT」；
 *   - 行情页顶部：品种名只写基础币，旁边小字「币安 USDT 永续」「HL USDC 永续」「CB USD 现货」「指数」
 *     （和电脑版 ui/common.ts chartSub 同一口径，这里另写一份免得把电脑版的图标表打进手机包）。
 */
import { parseKey, wireSymbol } from '../../market/identity'
import { normKey } from '../chart/symbolKey'
import { marketOf, symbolOk, venueLabel, venueName } from '../../venues'
import type { Sym } from '../../market/symbols'

/** 任何写法 → 网页里存的规范键（实现在图表层 chart/symbolKey，这里转一手） */
export { normKey }

/** 是不是别家（不是币安 U 本位、也不是美元指数）的完整键 */
export const isVenueKey = (k: string): boolean => k.includes('/')

const QUOTES = ['USDT', 'USDC', 'FDUSD', 'BUSD', 'USD1', 'TUSD', 'USD']
/** 币安代号拆成 (base, quote)：BTCUSDT → BTC / USDT；1000PEPEUSDT → 1000PEPE / USDT */
export function splitSymbol(symbol: string): { base: string; quote: string } {
  for (const q of QUOTES) if (symbol.length > q.length && symbol.endsWith(q)) return { base: symbol.slice(0, -q.length), quote: q }
  return { base: symbol, quote: '' }
}

/** 列表行 / 顶栏的两截名字：基础币（带交易所自己的倍数前缀：1000PEPE、kPEPE）+ 计价币。
 *  币安与美元指数照旧按代号拆；别家按品种表（title / quote），表没到时按键与注册表猜 */
export function pairOf(k: string, s?: Partial<Pick<Sym, 'title' | 'quote' | 'macro'>> | null): { base: string; quote: string } {
  if (!isVenueKey(k)) {
    if (s?.macro || k === 'DXY') return { base: k, quote: '' }
    return splitSymbol(k)
  }
  const base = s?.title || wireSymbol(k).replace(/-USD[CT]?$|USDT$|USDC$/, '') || k
  return { base, quote: s?.quote ?? marketOf(k)?.quote ?? '' }
}

/** 名字前那一截灰小字（「币安」「OKX」「HL」「CB」）；美元指数与认不出的回空串 */
export function venueTagHTML(k: string): string {
  const v = venueLabel(k)
  return v ? `<span class="row-vtag">${escTag(v)}</span>` : ''
}
const escTag = (s: string): string => s.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!))

/** 顶部品种名旁的小字：「缩写 + 计价币 + 永续 / 现货」，美元指数只写「指数」（同电脑版 chartSub） */
export function chartSubOf(k: string, s?: Partial<Pick<Sym, 'quote' | 'macro'>> | null): string {
  const market = parseKey(k).market
  if (s?.macro || market === 'index') return '指数'
  return [venueLabel(k), s?.quote || marketOf(k)?.quote || '', market === 'spot' ? '现货' : '永续'].filter(Boolean).join(' ')
}

/** 搜索 / 品种整页行的第二行：「BTCUSDT 永续」「BTC-USDT-SWAP 永续」「BTC-USD 现货」「DXY 指数」 */
export function rowMeta(k: string, s?: Partial<Pick<Sym, 'raw' | 'macro'>> | null): string {
  const market = parseKey(k).market
  if (s?.macro || market === 'index') return `${k} 指数`
  return `${s?.raw || wireSymbol(k)} ${market === 'spot' ? '现货' : '永续'}`
}

/** 提醒卡 / 提醒表单那一行：「币安 · USDT 永续」「CB · USD 现货」「指数」 */
export function venueLine(k: string, s?: Partial<Pick<Sym, 'quote' | 'macro'>> | null): string {
  const market = parseKey(k).market
  if (s?.macro || market === 'index') return '指数'
  const v = venueLabel(k), q = s?.quote || marketOf(k)?.quote || ''
  const kind = market === 'spot' ? '现货' : '永续'
  return (v ? v + ' · ' : '') + (q ? q + ' ' + kind : kind)
}

/** 自选分类：别家的品种各自一类，类名是交易所全名（照 iOS VenueDescriptor.favoriteCategory）；
 *  币安按资产类型分（不单列），美元指数「指数」由调用方管。回 null = 不单列 */
export function venueCategory(k: string): string | null {
  if (!isVenueKey(k)) return null
  const v = parseKey(k).venue
  return marketOf(k) ? venueName(v) : null
}

/** 通知 / 朋友的画线点开去哪只：币安 U 本位给裸代号；注册表里有行情面的别家（代号形状对得上）给完整键；
 *  别的（认不出的交易所、写坏的代号）网页版开不了，回 null */
export function openableKey(venue: string, market: string, symbol: string): string | null {
  const v = venue.toLowerCase(), m = market.toLowerCase(), sym = symbol.toUpperCase()
  if (!sym) return null
  if (v === 'binance' && m === 'usd_m') return sym
  const k = `${v}/${m}/${sym}`
  return symbolOk(k) ? k : null
}
