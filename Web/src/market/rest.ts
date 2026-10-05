/* Hkline Web · 币安 U 本位合约 REST
 *
 * 直连线路：浏览器直接取 fapi.binance.com（它对 /fapi/* 与 /futures/data/* 都回 Access-Control-Allow-Origin: *）。
 * 一律不发 Referer：币安 CloudFront 对来源页是 sslip.io 的请求回 403 且不带跨域头。
 * 网关线路：同样的地址改走新加坡那台的 /v1/market/raw/<path>?source=binance（viaRoute）——国内不开代理
 * 根本连不上 fapi.binance.com，2026-10-02 之前「网关」只管 WebSocket，手机 4G 上 K 线、品种表全是空的。
 * 限流闸（limit.ts）按币安的原地址认族与权重，但两条线路各记一道：直连花的是这台电脑出口 IP 的额度，
 * 网关花的是服务端那份共用额度，一边被限流不连累另一边（切到网关正是直连被封时的出路）。
 * 取不到就是取不到——不造演示数据，界面显示空态。
 */
import type { Bar } from '../chart/calc'
import { S, emit } from './state'
import { admit, coolingFor, isRateLimit, noteStatus, setGatewayProbe } from './limit'
import { baseOf, badgeColor, cnOf, decOfTick, kindOfUnderlying, type Sym } from './symbols'
import { supplyOf } from './meta'

export const REST = 'https://fapi.binance.com'

/** 自家服务器的根：线上与页面同源；本机开发（localhost）直接打线上那台。 */
export function apiOrigin(): string {
  if (typeof location !== 'undefined' && /^https:$/.test(location.protocol) && !/^localhost$|^127\./.test(location.hostname)) return location.origin
  return 'https://kanpan.43-160-232-253.sslip.io'
}
/** 网关线路下，币安合约的 REST 地址改成经新加坡透传的地址；别的地址与直连线路原样返回。 */
export function viaRoute(url: string): string {
  if (S.route !== 'gateway') return url
  const m = /^https:\/\/(?:fapi|dapi)\.binance\.com\/([^?#]+)(\?[^#]*)?$/.exec(url)
  if (!m) return url
  return `${apiOrigin()}/v1/market/raw/${m[1]}${m[2] ? `${m[2]}&` : '?'}source=binance`
}

// 走网关的合约 REST 只用网关那份共用额度里属于这个浏览器的一截（见 limit.ts GATEWAY_SHARE）
setGatewayProbe(url => viaRoute(url) !== url)

/** priority：给浏览器的取数优先级（同一条 HTTP/2 连接上谁先拿带宽）；冷启动并行预取的 K 线用 'low'，让品种表先到 */
export async function j<T = unknown>(url: string, ms = 8000, background = false, alive?: () => boolean, priority?: RequestPriority): Promise<T> {
  // 主机在限流冷却里就不发（抛 RateLimited）：429 之后接着打会被升级成 418 封 IP；
  // 一分钟权重快满了就先排队（见 limit.ts）；排队期间 alive() 说不要了就不发（抛 Superseded）
  const gw = await admit(url, background, alive)
  const ctl = new AbortController()
  const t = setTimeout(() => ctl.abort(), ms)
  try {
    const r = await fetch(viaRoute(url), { signal: ctl.signal, referrerPolicy: 'no-referrer', cache: 'no-store', ...(priority ? { priority } : {}) })
    noteStatus(url, r.status, r.headers.get('Retry-After'), Date.now(), gw)
    if (!r.ok) throw new Error(`${r.status} ${url}`)
    return await r.json() as T
  } finally { clearTimeout(t) }
}

interface ExSymbol {
  symbol: string; baseAsset: string; quoteAsset: string; contractType: string; status: string
  underlyingType?: string; underlyingSubType?: string[]; onboardDate?: number
  filters: { filterType: string; tickSize?: string }[]; pricePrecision: number
}
interface Ticker24 { symbol: string; lastPrice: string; priceChange: string; priceChangePercent: string; quoteVolume: string; openPrice: string; highPrice: string; lowPrice: string; count: number; closeTime: number }
interface Premium { symbol: string; lastFundingRate: string; nextFundingTime: number; markPrice: string; indexPrice: string; time?: number }

function blank(e: ExSymbol): Sym {
  const base = baseOf(e.symbol, e.baseAsset)
  const kind = kindOfUnderlying(e.underlyingType, base)
  const tick = e.filters.find(f => f.filterType === 'PRICE_FILTER')?.tickSize
  return {
    symbol: e.symbol, base, code: base, kind, cn: cnOf(base, kind),
    dec: tick ? decOfTick(tick) : Math.min(8, e.pricePrecision),
    color: badgeColor(base), price: null, chg: 0, pct: null, vol: 0, fr: null, nextFunding: null,
    ut: e.underlyingType, onboard: e.onboardDate || undefined,
    tags: e.underlyingSubType?.length ? [...new Set(e.underlyingSubType.map(t => t.toLowerCase()))].sort() : undefined,
  }
}

/** 全市场：exchangeInfo（品种与分类）+ ticker/24hr（价与量）+ premiumIndex（费率、标记价、指数价） */
export async function loadUniverse(): Promise<Map<string, Sym>> {
  try {
    const [ex, tk, pi] = await Promise.all([
      j<{ symbols: ExSymbol[] }>(`${REST}/fapi/v1/exchangeInfo`, 12000),
      j<Ticker24[]>(`${REST}/fapi/v1/ticker/24hr`),
      j<Premium[]>(`${REST}/fapi/v1/premiumIndex`),
    ])
    const next = new Map<string, Sym>()
    for (const e of ex.symbols) {
      if (e.quoteAsset !== 'USDT' || e.status !== 'TRADING') continue
      if (e.contractType !== 'PERPETUAL' && e.contractType !== 'TRADIFI_PERPETUAL') continue
      let s = S.symbols.get(e.symbol)
      if (!s) { s = blank(e); const sup = supplyOf(e.symbol); if (sup != null) s.supply = sup }   // 元数据先于全市场表到了
      next.set(e.symbol, s)
    }
    // 三个请求要几百毫秒到几秒才回来，这期间推送已经把手里的价格、标记价刷新过了：
    // 交易所时间比手里旧的那一组不覆盖（否则价格回跳一下、涨跌幅闪回旧值，直到下一帧推送再改回来）
    for (const t of tk) {
      const s = next.get(t.symbol); if (!s) continue
      const at = +t.closeTime || 0
      if (!(at < (s.pxAt ?? 0))) Object.assign(s, { price: +t.lastPrice, chg: +t.priceChange, pct: +t.priceChangePercent, open: +t.openPrice, hi: +t.highPrice, lo: +t.lowPrice, pxAt: at })
      if (!(at < (s.statAt ?? 0))) Object.assign(s, { vol: +t.quoteVolume, count: +t.count, statAt: at })
    }
    for (const p of pi) {
      const s = next.get(p.symbol); if (!s) continue
      const at = +(p.time ?? 0) || 0
      if (at < (s.markAt ?? 0)) continue
      Object.assign(s, { fr: p.lastFundingRate === '' ? null : +p.lastFundingRate, nextFunding: p.nextFundingTime || null, mark: +p.markPrice, index: +p.indexPrice, markAt: at })
    }
    S.symbols = next
    S.universeAt = Date.now()
    S.live = true
    S.limited = false
    S.error = ''
  } catch (e) {
    console.warn('[hkline] 币安合约接口不可达', e)
    S.live = false
    S.limited = isRateLimit(e)
    S.error = S.limited ? `请求太密，${Math.ceil(Math.max(coolingFor(REST), 1000) / 1000)} 秒后自动重试` : String((e as Error)?.message || e)
  }
  emit({ type: 'universe' })
  return S.symbols
}

type Row = [number, string, string, string, string, string, number, string, ...unknown[]]
function parse(rows: Row[]): Bar[] {
  // 成交量用成交额（USDT），和手机端一致；r[10] 主动买入成交额、r[5] 成交量（币）给 CVD / VWAP / 成交量分布用
  return rows.map(r => ({ t: r[0], o: +r[1], h: +r[2], l: +r[3], c: +r[4], v: +r[7], tb: +(r[10] as string), bv: +r[5] }))
}

export interface KlineResult { bars: Bar[]; ok: boolean; error?: string }

/** 一页 K 线（最多 1500 根）；带 endTime 时是向左翻页，取严格早于它的那一页 */
/** background：后台一大批取的（板块迷你走势），只用限流预算的一截，见 limit.ts */
export async function klines(symbol: string, iv: string, endTime?: number, limit = 1500, withOI = true, background = false, alive?: () => boolean, priority?: RequestPriority): Promise<KlineResult> {
  try {
    const u = `${REST}/fapi/v1/klines?symbol=${symbol}&interval=${iv}&limit=${limit}${endTime ? `&endTime=${endTime - 1}` : ''}`
    const bars = parse(await j<Row[]>(u, 10000, background, alive, priority))
    if (withOI) void attachOI(symbol, iv, bars)
    return { bars, ok: true }
  } catch (e) {
    return { bars: [], ok: false, error: String((e as Error)?.message || e) }
  }
}

/** 持仓量副图：币安只给最近 30 天、5 分钟以上周期的历史，对不齐的根留空 */
const OI_PERIOD = new Set(['5m', '15m', '30m', '1h', '2h', '4h', '6h', '12h', '1d'])
export async function attachOI(symbol: string, iv: string, bars: Bar[]): Promise<void> {
  if (!OI_PERIOD.has(iv) || !bars.length) return
  try {
    const endTime = bars[bars.length - 1].t + 1
    const rows = await j<{ timestamp: number; sumOpenInterestValue: string }[]>(`${REST}/futures/data/openInterestHist?symbol=${symbol}&period=${iv}&limit=500&endTime=${endTime}`)
    if (!rows.length) return
    const m = new Map(rows.map(r => [r.timestamp, +r.sumOpenInterestValue]))
    let hit = 0
    for (const b of bars) { const v = m.get(b.t); if (v != null) { b.oi = v; hit++ } }
    if (hit) emit({ type: 'oi', symbol, iv })
  } catch { /* 取不到持仓量就留空 */ }
}

// ------------------------------------------------------------ 详情块里不在推送里的数
export interface Detail {
  t: number
  oiValue?: number      // 持仓量（美元）
  oiChg?: number        // 持仓量 24h 变化（%）
  ls?: number           // 多空人数比
  top?: number          // 大户持仓比
  taker?: number        // 主动买卖比
}
const detailCache = new Map<string, Detail>()
export function detailOf(symbol: string): Detail | undefined { return detailCache.get(symbol) }

/** 一分钟最多取一次 */
export async function fetchDetail(symbol: string): Promise<void> {
  const prev = detailCache.get(symbol)
  if (prev && Date.now() - prev.t < 60e3) return
  const d: Detail = { ...(prev || {}), t: Date.now() }
  detailCache.set(symbol, d)
  const get = <T,>(path: string, q: string) => j<T>(`${REST}${path}?symbol=${symbol}${q ? '&' + q : ''}`).catch(() => null)
  const [oi, hist, ls, top, taker] = await Promise.all([
    get<{ openInterest: string }>('/fapi/v1/openInterest', ''),
    get<{ sumOpenInterestValue: string }[]>('/futures/data/openInterestHist', 'period=1h&limit=25'),
    get<{ longShortRatio: string }[]>('/futures/data/globalLongShortAccountRatio', 'period=5m&limit=1'),
    get<{ longShortRatio: string }[]>('/futures/data/topLongShortPositionRatio', 'period=5m&limit=1'),
    get<{ buySellRatio: string }[]>('/futures/data/takerlongshortRatio', 'period=5m&limit=1'),
  ])
  const px = S.symbols.get(symbol)?.price
  if (oi && px) d.oiValue = +oi.openInterest * px
  if (hist && hist.length > 1) d.oiChg = (+hist[hist.length - 1].sumOpenInterestValue / +hist[0].sumOpenInterestValue - 1) * 100
  if (ls?.[0]) d.ls = +ls[0].longShortRatio
  if (top?.[0]) d.top = +top[0].longShortRatio
  if (taker?.[0]) d.taker = +taker[0].buySellRatio
  emit({ type: 'detail', symbol })
}
