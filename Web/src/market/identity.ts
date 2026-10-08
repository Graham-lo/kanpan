/* Hkline Web · 品种身份（venue/market/SYMBOL）
 *
 * 和 iOS InstrumentID、服务端 sync_validation::identity 同一套三段身份。网页这边的约定（2026-10-08 起，三端一致）：
 *   - 币安 U 本位合约在网页里继续用**裸代号**（BTCUSDT = binance/usd_m/BTCUSDT）：本机存档、画线、提醒、自选、
 *     地址栏 ?s= 都是裸代号，不迁移；
 *   - 美元指数用裸 DXY（= macro/index/DXY，见 macro.ts）；
 *   - 别家一律用完整键：okx/usd_m/BTCUSDT、bybit/usd_m/BTCUSDT、hyperliquid/usd_m/BTC（HL 的 coin 名大写，
 *     kPEPE → KPEPE，原名由品种表 Sym.raw 留着）、coinbase/spot/BTC-USD。
 * 同一个币在不同交易所是不同品种（像 TradingView / AICoin），键里不混源、没有替身。
 *
 * 这个文件是纯函数（不认识注册表，也不碰网络），网页各处（含手机网页 src/m/**）判身份都走它：
 *   parseKey(k)      任何写法 → { venue, market, symbol }（symbol 是交易所那一家的键代号，进同步正文的那一段）
 *   keyOf(v, m, s)   三段 → 网页里存的那个键（币安 / 美元指数回裸代号，别家回完整键）
 *   displayKey(k)    任何写法 → 网页里存的规范键（binance/usd_m/BTCUSDT → BTCUSDT，macro/index/DXY → DXY）
 *   syncKeyOf(k)     任何写法 → 完整的三段键（同步对象 id 前缀、对比偏好、提醒 id 都用它）
 *   venueOf(k) / isDefaultVenue(k) / venueMarketOf(k) / wireSymbol(k)
 */
import { MACRO_MARKET, MACRO_SYMBOL, MACRO_VENUE } from './macro'

/** 网页的默认交易所：裸代号就是它 */
export const DEFAULT_VENUE = 'binance'
export const DEFAULT_MARKET = 'usd_m'

export interface InstrumentKey { venue: string; market: string; symbol: string }

/** 完整键的形状：小写的 venue / market，代号段是交易所那一家的形状（大写字母数字，Coinbase 带「-」，币安有中文底名） */
const FULL = /^([a-z][a-z0-9_]{1,19})\/([a-z][a-z0-9_]{1,9})\/([\p{L}\p{N}._-]{1,40})$/u

/** 任何写法 → 三段。裸代号 = 币安 U 本位；DXY = 美元指数；完整键原样（venue / market 认小写，代号段照原样） */
export function parseKey(sym: string): InstrumentKey {
  const m = FULL.exec(sym)
  if (m) return { venue: m[1], market: m[2], symbol: m[3] }
  if (sym === MACRO_SYMBOL) return { venue: MACRO_VENUE, market: MACRO_MARKET, symbol: MACRO_SYMBOL }
  return { venue: DEFAULT_VENUE, market: DEFAULT_MARKET, symbol: sym }
}

/** 三段 → 网页里存的键：币安 U 本位回裸代号、美元指数回 DXY，其余 `venue/market/SYMBOL` */
export function keyOf(venue: string, market: string, symbol: string): string {
  if (venue === DEFAULT_VENUE && market === DEFAULT_MARKET) return symbol
  if (venue === MACRO_VENUE && market === MACRO_MARKET && symbol === MACRO_SYMBOL) return MACRO_SYMBOL
  return `${venue}/${market}/${symbol}`
}

/** 任何写法 → 网页里存的规范键（写进 st / S.symbols 的那个） */
export function displayKey(sym: string): string { const k = parseKey(sym); return keyOf(k.venue, k.market, k.symbol) }

/** 这只是哪一家的（binance / okx / bybit / hyperliquid / coinbase / macro） */
export const venueOf = (sym: string): string => parseKey(sym).venue
/** 是不是默认交易所（币安 U 本位，裸代号） */
export const isDefaultVenue = (sym: string): boolean => { const k = parseKey(sym); return k.venue === DEFAULT_VENUE && k.market === DEFAULT_MARKET }
/** 同步正文里的 symbol 段（交易所那一家的键代号） */
export const wireSymbol = (sym: string): string => parseKey(sym).symbol

/** 同步用的 venue / market（照 iOS PersonalSyncCodec：三段身份） */
export function venueMarketOf(sym: string): { venue: string; market: string } {
  const k = parseKey(sym)
  return { venue: k.venue, market: k.market }
}
/** 完整三段键：binance/usd_m/BTCUSDT、macro/index/DXY、okx/usd_m/BTCUSDT…… */
export function syncKeyOf(sym: string): string {
  const k = parseKey(sym)
  return `${k.venue}/${k.market}/${k.symbol}`
}
/** 提醒正文里的 market（`venue/market`） */
export function alertMarketOf(sym: string): string {
  const k = parseKey(sym)
  return `${k.venue}/${k.market}`
}
