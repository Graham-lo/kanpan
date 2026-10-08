/* Hkline Web · 美元指数（macro 交易所）的身份与取数改写
 *
 * 照 iOS KanpanNetwork/Macro/ 与 docs/美元指数-协议-2026-10-05.md：
 *   - 网页版的品种身份一直是「裸代号 = binance/usd_m/<代号>」，美元指数也用裸代号 DXY 存在自选 / 画线 / 提醒里，
 *     只在和服务端同步时换成 macro/index/DXY（币安的合约都以 USDT/USDC 结尾，不会和 DXY 撞名）。
 *   - 它唯一的来源是 kanpan-api：REST 与推送不管用户选直连还是网关都走自家服务器。
 *     币安形状的 /fapi/v1/klines、/fapi/v1/ticker/24hr 在 rest.ts j() 里被改写成 /v1/market/raw/*?source=macro；
 *     其余币安接口（持仓量、多空比、盘口、逐笔……）对它一律本地拒掉，不往币安发。
 *   - 没有计价币、没有资金费率 / 持仓 / 结算 / 估值 / 主力订单流 / 条件提醒；成交量恒为 0。
 */
import type { Sym } from './symbols'

export const MACRO_SYMBOL = 'DXY'
export const MACRO_VENUE = 'macro'
export const MACRO_MARKET = 'index'
/** 同步键 venue/market/symbol */
export const MACRO_KEY = 'macro/index/DXY'
/** 提醒正文里的 market（照 iOS AlertSyncCodec：venue/market） */
export const MACRO_ALERT_MARKET = 'macro/index'
export const MACRO_CN = '美元指数'

/** 这只是不是美元指数（裸代号或同步键都认） */
export function isMacro(sym: string | null | undefined): boolean {
  return sym === MACRO_SYMBOL || sym === MACRO_KEY
}

// 同步用的三段身份：2026-10-08 起所有交易所都走 identity.ts（这里保留导出，老代码照旧从这里拿）
export { syncKeyOf, venueMarketOf } from './identity'

/** 服务端不通时的内置一行（离线照样搜得到、加得了自选）；价格等第一帧来了再填 */
export function macroFallback(): Sym {
  return {
    symbol: MACRO_SYMBOL, base: MACRO_SYMBOL, code: MACRO_SYMBOL, kind: 'idx', cn: MACRO_CN, dec: 3,
    color: '#2F8F5F', venue: MACRO_VENUE, quote: '', price: null, chg: 0, pct: null, vol: 0, fr: null, nextFunding: null, ut: 'INDEX', macro: true,
  }
}

/** 币安形状的地址里带的是不是 symbol=DXY */
function symbolParam(url: string): string | null {
  const m = /[?&]symbol=([^&#]*)/.exec(url)
  return m ? decodeURIComponent(m[1]) : null
}

/** 美元指数没有的数据：在本地就拒掉，不往币安发（币安会回 400，还白占限流额度） */
export class MacroUnsupported extends Error {
  constructor(url: string) { super(`美元指数没有这项数据：${url}`); this.name = 'MacroUnsupported' }
}

/**
 * 币安合约 REST 地址 → 美元指数的取数地址：
 *   /fapi/v1/klines?symbol=DXY&…     → <origin>/v1/market/raw/klines?…&source=macro
 *   /fapi/v1/ticker/24hr?symbol=DXY  → <origin>/v1/market/raw/ticker/24hr?symbol=DXY&source=macro
 * 不是 DXY 的返回 null（照原样走）；是 DXY 但服务端没有这项的抛 MacroUnsupported。
 */
export function macroRewrite(url: string, origin: string): string | null {
  const m = /^https:\/\/(?:fapi|dapi)\.binance\.com\/(?:fapi|dapi|futures)\/[^?#]*/.exec(url)
  if (!m) return null
  const sym = symbolParam(url)
  if (!sym || !isMacro(sym.toUpperCase())) return null
  const k = /^https:\/\/fapi\.binance\.com\/fapi\/v1\/(klines|ticker\/24hr)\?([^#]*)$/.exec(url)
  if (!k) throw new MacroUnsupported(url)
  // continuousKlines / markPriceKlines 之类的已经被上面挡掉；这里统一把代号写成大写的 DXY
  const q = k[2].replace(/(^|&)symbol=[^&]*/, `$1symbol=${MACRO_SYMBOL}`)
  return `${origin}/v1/market/raw/${k[1]}?${q}&source=macro`
}

/** 服务端 24h 行情（REST 对象或推送 24hrTicker 帧）落进那一行；涨跌照服务端原样用（相对上一交易日收盘） */
export interface MacroTicker {
  lastPrice?: string; priceChange?: string; priceChangePercent?: string; openPrice?: string; highPrice?: string; lowPrice?: string
  closeTime?: number; marketState?: string
}
export function applyMacroTicker(s: Sym, t: MacroTicker, at: number): boolean {
  const px = Number(t.lastPrice)
  if (!Number.isFinite(px) || px <= 0) return false
  if (at < (s.pxAt ?? 0)) { if (t.marketState) s.closed = t.marketState === 'closed'; return false }
  Object.assign(s, {
    price: px, chg: Number(t.priceChange) || 0, pct: Number.isFinite(Number(t.priceChangePercent)) ? Number(t.priceChangePercent) : null,
    open: Number(t.openPrice) || undefined, hi: Number(t.highPrice) || undefined, lo: Number(t.lowPrice) || undefined, pxAt: at, vol: 0,
  })
  if (t.marketState) s.closed = t.marketState === 'closed'
  return true
}
