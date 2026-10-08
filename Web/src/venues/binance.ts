/* Hkline Web · 多交易所 · 币安（行情 + 主力订单流）
 *
 * 行情：网页的默认交易所（裸代号）。REST / 推送的代码是复刻早期的那套，留在原文件——
 *   market/rest.ts（fapi REST、全市场表、K 线、持仓量、详情、按权重记账的限流器 market/limit.ts Limiter）
 *   market/stream.ts（组合流连接池：直连 dstream.binance.me、网关 /market/stream stream_hub）。
 * 上层只经注册表的 binance.market 取 K 线（klines 分发）；推送由 stream.ts 自己的连接池管（这里不给 stream）。
 *
 * 订单流（现货 rangeOverlap、合约 previousFinalOverlap，快照另拉 REST）：
 *
 * 直连：U 本位深度、成交两条连接都拨 iOS 出厂同一台 dstream.binance.me（国内不开代理能直连；
 * fstream.binance.com 国内解析被污染、握手就重置）；币本位同一台一条；现货 data-stream.binance.vision。
 * 网关：合约走 /v1/market/ws/binance 中继（一条 4 本 = 8 路流）、快照走 /v1/market/depth；现货仍直连 vision。
 * 一律不用 *.binancefuture.com（那是合约测试网）。
 */
import type { DepthMessage, Venue } from '../orderflow/types'
import { chunk, levels, n, parseJSON, trade, type ConnSpec, type DepthBook, type Kline, type Out, type VenueAdapter, type VenueMarket } from './common'
import { REST, binanceKlines, fetchExchangeInfo, fetchTicker24, symOfExchange } from '../market/rest'
import { INTERVALS } from '../market/symbols'

/** 服务端 sync_validation binance_symbol：按字符数（不按 UTF-16 长度）最长 40；ASCII 大写、数字，
 *  或非 ASCII 的 Unicode 字母数字（币安上架过「币安人生USDT」这种中文底名的合约）；以计价资产结尾，且前面还有底名 */
const QUOTE_ASSETS = ['USDT', 'USDC', 'FDUSD', 'BUSD', 'USD1', 'TUSD'] // instruments.rs QUOTE_ASSETS
const symbolChar = (c: string): boolean => /^[A-Z0-9]$/.test(c) || (c.codePointAt(0)! > 0x7f && /^[\p{Alphabetic}\p{N}]$/u.test(c))
export function binanceSymbolOk(s: string): boolean {
  if (!s) return false
  const chars = [...s]
  if (chars.length > 40 || !chars.every(symbolChar)) return false
  return QUOTE_ASSETS.some(q => s.length > q.length && s.endsWith(q))
}

/** 币安的行情面：薄薄一层，实际的取数在 market/rest.ts */
export const BINANCE_MARKET: VenueMarket = {
  shortName: '币安', displayName: '币安', market: 'usd_m', quote: 'USDT',
  symbolOk: binanceSymbolOk,
  instruments: async () => (await fetchExchangeInfo()).symbols.map(symOfExchange).filter((s): s is NonNullable<typeof s> => !!s),
  tickers: async () => (await fetchTicker24()).map(t => ({
    key: t.symbol, price: +t.lastPrice, chg: +t.priceChange, pct: +t.priceChangePercent, open: +t.openPrice, hi: +t.highPrice, lo: +t.lowPrice,
    vol: +t.quoteVolume, count: +t.count, at: +t.closeTime || Date.now(),
  })),
  klines: (key, iv, q, opts) => binanceKlines(key, iv, q, opts),
  maxKlines: 1500,
  intervals: { native: Object.fromEntries(INTERVALS.map(iv => [iv, iv])), derived: {} },
}

export type BinanceMarket = 'um' | 'cm' | 'spot'
export function binanceMarket(v: Venue): BinanceMarket {
  if (v.product === 'spot') return 'spot'
  if (v.product === 'usdtPerp') return 'um'
  if (v.product === 'coinPerp') return 'cm'
  return v.notional.kind === 'inverse' ? 'cm' : 'um'
}
export const BINANCE_SNAPSHOT_LEVELS: Record<BinanceMarket, number> = { spot: 5000, um: 1000, cm: 1000 }
/** 网关中继一条最多几本（每本深度 + 成交两路流，中继上限 8 路） */
export const BINANCE_GW_BOOKS = 4
export const binanceStreams = (b: DepthBook): string[] => { const s = b.venue.instrument.toLowerCase(); return [`${s}@depth@100ms`, `${s}@aggTrade`] }

const DIRECT_FUTURES = 'wss://dstream.binance.me/stream?streams='
const DIRECT_SPOT = 'wss://data-stream.binance.vision/stream?streams='

export function decodeBinance(text: string, bySymbol: Map<string, DepthBook>): Out[] {
  const outer = parseJSON(text)
  if (!outer) return []
  const body = (outer.data ?? outer) as Record<string, unknown>
  const s = typeof body.s === 'string' ? body.s.toUpperCase() : ''
  const b = bySymbol.get(s)
  if (!b) return []
  if (body.e === 'aggTrade') {
    const p = n(body.p), q = n(body.q), t = n(body.T)
    if (!Number.isFinite(p) || !Number.isFinite(q)) return []
    return [[b.id, trade(b, p, q, body.m === true ? 'bid' : 'ask', Number.isFinite(t) ? t : Date.now())]]
  }
  if (body.e === 'depthUpdate') {
    const U = n(body.U), u = n(body.u)
    if (!Number.isFinite(U) || !Number.isFinite(u)) return []
    const pu = body.pu == null ? null : n(body.pu)
    return [[b.id, { type: 'delta', delta: {
      firstUpdateID: U, finalUpdateID: u, previousFinalUpdateID: pu != null && Number.isFinite(pu) ? pu : null,
      bids: levels(body.b, b), asks: levels(body.a, b), eventTimeMs: n(body.E) || Date.now(), connection: 0,
    } }]]
  }
  return []
}

export function binanceSnapshot(json: unknown, b: DepthBook): DepthMessage | null {
  const r = json as Record<string, unknown>
  const L = n(r?.lastUpdateId)
  if (!Number.isFinite(L)) return null
  return { type: 'snapshot', snapshot: {
    lastUpdateID: L, requestedLevels: BINANCE_SNAPSHOT_LEVELS[binanceMarket(b.venue)],
    bids: levels(r.bids, b), asks: levels(r.asks, b), eventTimeMs: n(r.E) || undefined, connection: 0, slidingWindow: false,
  } }
}

/** 币安 K 线 [开盘时间, 开, 高, 低, 收, 量, 收盘时间, 计价额, 笔数, 主动买量, 主动买计价额, _] */
export function parseBinanceKlines(body: unknown, priceFactor = 1): Kline[] {
  if (!Array.isArray(body)) return []
  const out: Kline[] = []
  for (const r of body) {
    if (!Array.isArray(r)) continue
    const t = +r[0], h = +r[2], l = +r[3], c = +r[4], q = +r[7], b = +r[10]
    if (!Number.isFinite(t) || !(q >= 0)) continue
    out.push({ t, h: h * priceFactor, l: l * priceFactor, c: c * priceFactor, quote: q, buy: Number.isFinite(b) ? b : null })
  }
  return out
}

function spec(key: string, books: DepthBook[], url: string): ConnSpec {
  const map = new Map(books.map(b => [b.venue.instrument.toUpperCase(), b]))
  return { key, books, urls: [url], subscribe: () => [], decode: t => decodeBinance(t, map) }
}

export const binance: VenueAdapter = {
  key: 'binance',
  label: '币安',
  color: 'var(--of-bn)',
  sequenceModel: p => (p === 'spot' ? 'rangeOverlap' : 'previousFinalOverlap'),
  snapshotInBand: false,
  maxBooksPerConn: BINANCE_GW_BOOKS,
  takerSplit: true,
  connections(books, ctx) {
    const by: Record<BinanceMarket, DepthBook[]> = { um: [], cm: [], spot: [] }
    for (const b of books) by[binanceMarket(b.venue)].push(b)
    const out: ConnSpec[] = []
    for (const m of ['um', 'cm', 'spot'] as BinanceMarket[]) {
      const list = by[m]
      if (!list.length) continue
      if (m === 'spot') out.push(spec('binance-spot', list, DIRECT_SPOT + list.flatMap(binanceStreams).join('/')))
      else if (ctx.route === 'gateway') {
        chunk(list, BINANCE_GW_BOOKS).forEach((c, i) => out.push(spec(`binance-${m}-gw${i}`, c, `${ctx.gw}/v1/market/ws/binance?streams=${c.flatMap(binanceStreams).join('/')}`)))
      } else if (m === 'um') {
        // 深度、成交分两条；成交那条不负责簿（books 为空时不触发 connectionOpened）
        const depth = spec('binance-um-depth', list, DIRECT_FUTURES + list.map(b => binanceStreams(b)[0]).join('/'))
        out.push(depth, { ...depth, key: 'binance-um-trade', books: [], urls: [DIRECT_FUTURES + list.map(b => binanceStreams(b)[1]).join('/')] })
      } else out.push(spec('binance-cm', list, DIRECT_FUTURES + list.flatMap(binanceStreams).join('/')))
    }
    return out
  },
  snapshot(b, route) {
    const m = binanceMarket(b.venue)
    const sym = encodeURIComponent(b.venue.instrument)
    const limit = BINANCE_SNAPSHOT_LEVELS[m]
    const url = m === 'spot' ? `https://data-api.binance.vision/api/v3/depth?symbol=${sym}&limit=${limit}`
      : route === 'gateway' ? `/v1/market/depth?symbol=${sym}&limit=1000&market=${m}`
      : m === 'um' ? `${REST}/fapi/v1/depth?symbol=${sym}&limit=${limit}`
      : `https://dapi.binance.com/dapi/v1/depth?symbol=${sym}&limit=${limit}`
    return { url, parse: binanceSnapshot }
  },
  klines30m(b, _now, slots) {
    const v = b.venue
    if (v.product !== 'spot' && v.product !== 'usdtPerp') return null
    const ins = encodeURIComponent(v.instrument), f = b.priceFactor
    return {
      url: v.product === 'spot' ? `https://data-api.binance.vision/api/v3/klines?symbol=${ins}&interval=30m&limit=${slots}`
        : `${REST}/fapi/v1/klines?symbol=${ins}&interval=30m&limit=${slots}`,
      parse: x => parseBinanceKlines(x, f),
    }
  },
  primary: {
    referenceCloseUrl: (symbol, day) => `${REST}/fapi/v1/klines?symbol=${encodeURIComponent(symbol)}&interval=1d&startTime=${day}&limit=2`,
    parseReferenceClose(body, day) {
      const rows = Array.isArray(body) ? (body as unknown[][]) : []
      const exact = rows.find(r => Number(r[0]) === day) ?? rows.filter(r => Number(r[0]) < day + 86_400_000).pop()
      return exact ? parseFloat(String(exact[4])) : NaN
    },
  },
  fallback: (symbol, base, chartScale) => [
    { product: 'usdtPerp', instrument: symbol, priceScale: chartScale },
    { product: 'spot', instrument: base + 'USDT', priceScale: 1 },
  ],
  market: BINANCE_MARKET,
}
