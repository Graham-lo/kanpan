/* Hkline Web · 多交易所 · Coinbase 现货（行情 + 主力订单流，一家一个模块）
 *
 * 行情（2026-10-08，Advanced Trade 公开行情，报文按官方文档写）：
 *   - 只收 USD 计价、在线、可交易的现货（product_type SPOT）；网页键 coinbase/spot/BTC-USD（原生 product_id）。
 *   - REST 直连 api.coinbase.com/api/v3/brokerage/market/*（带 CORS），网关 /v1/market/raw/<path>?source=coinbase；
 *     限流器 8 次 / 秒（公开端点按 IP 10 次 / 秒，留余量；和服务端那一家的节拍同一个数）。
 *   - 品种表与整表行情是同一次 products（价、24h 涨跌幅、24h 量）：额 = 量 × 价（近似）；没有 24h 高低。
 *   - K 线 products/{id}/candles（一次最多 350 根，按起止秒要），新的在前；原生 1 / 5 / 15 / 30 分、1 / 2 / 4 / 6 时、日；
 *     3 分由 1 分、8 时由 4 时、12 时由 6 时、周 / 月由日线并（月线一次最多拿得到约 11 个月）。
 *   - 推送 wss://advanced-trade-ws.coinbase.com（网关 /v1/market/stream?source=coinbase，服务端共用 hub，协议同原生）：
 *     ticker（价、24h 量与涨跌）、market_trades（逐笔）；没有任意周期的 K 线推送——行情层拿逐笔并当前这根
 *     （klineFromTrades）。连上先订 heartbeats，空闲连接不被对面收掉。
 *
 * 订单流（strictIncrementing：整条连接一个序号，一本簿一条连接；快照在流里）：
 *   恒直连 advanced-trade-ws；断档整条重连（没有单本重订）。30 分钟 K 线走 kanpan-api 的原样转发。
 */
import type { Bar } from '../chart/calc'
import type { BookLevel, DepthMessage } from '../orderflow/types'
import { registerGate } from '../market/limit'
import { apiOrigin } from '../market/origin'
import { keyOf, parseKey } from '../market/identity'
import { badgeColor, cnOf, decOfTick, type Sym } from '../market/symbols'
import { cleanQuote, levelOk, n, nonneg, num, parseJSON, pos, quantityFactor, stamp, trade, tradeOk, type DepthBook, type Kline, type Out, type Push, type Quote, type VenueAdapter, type VenueMarket } from './common'
import { rawRewrite, shared, vget } from './http'
import { sortBars } from './bars'
import { IV_MS } from '../util/format'

// ------------------------------------------------------------ 地址表（这一家唯一的一份）
export const CB = {
  id: 'coinbase',
  rest: 'https://api.coinbase.com/api/v3/brokerage/market',
  ws: 'wss://advanced-trade-ws.coinbase.com',
  /** 网关：服务端共用 hub，协议和原生一样 */
  hub: '/v1/market/stream?source=coinbase',
  /** 网关的 REST 透传前缀（订单流的 30 分钟 K 线一直走它） */
  raw: '/v1/market/raw',
} as const
/** 这一家唯一的限流器（直连 / 网关各一道）。官方（Advanced Trade › Rate Limits）：公开接口按 IP 10 次 / 秒。
 *  这里取一半 5 次 / 秒（另一半留给同一出口的手机 app 与别的页） */
export const CB_GATE = registerGate(CB.id, { hosts: ['api.coinbase.com'], rules: [{ windowMs: 1000, cap: 5 }], gateway: rawRewrite(CB.rest + '/', CB.id, apiOrigin) })

/** 服务端 coinbase_symbol：BASE-USD，BASE 只有 ASCII 大写与数字 */
export const cbSymbolOk = (s: string): boolean => s.length <= 40 && /^[A-Z0-9]+-USD$/.test(s)
const keyFor = (id: string): string => keyOf(CB.id, 'spot', id)

export const CB_GRANULARITY: Record<string, string> = { '1m': 'ONE_MINUTE', '5m': 'FIVE_MINUTE', '15m': 'FIFTEEN_MINUTE', '30m': 'THIRTY_MINUTE', '1h': 'ONE_HOUR', '2h': 'TWO_HOUR', '4h': 'FOUR_HOUR', '6h': 'SIX_HOUR', '1d': 'ONE_DAY' }

// ------------------------------------------------------------ 报文解码
interface Product {
  product_id?: string; price?: string; price_percentage_change_24h?: string; volume_24h?: string; quote_increment?: string
  quote_currency_id?: string; base_currency_id?: string; base_display_symbol?: string; status?: string; trading_disabled?: boolean; is_disabled?: boolean
  product_type?: string; new_at?: string
}
const listed = (p: Product): boolean => !!p && typeof p === 'object' && typeof p.product_id === 'string' && cbSymbolOk(p.product_id) && (p.product_type ?? 'SPOT') === 'SPOT'
  && p.status === 'online' && !p.trading_disabled && !p.is_disabled

export function decodeCbProducts(body: unknown): Sym[] {
  const out: Sym[] = []
  for (const p of productsOf(body)) {
    if (!listed(p)) continue
    const base = p.product_id!.slice(0, -4)
    out.push({
      symbol: keyFor(p.product_id!), venue: CB.id, quote: 'USD', raw: p.product_id!, base, code: base, kind: 'crypto', cn: cnOf(base, 'crypto'),
      dec: pos(p.quote_increment) ? decOfTick(p.quote_increment!) : 2, color: badgeColor(base), price: null, chg: 0, pct: null, vol: 0, fr: null, nextFunding: null,
      onboard: p.new_at ? Date.parse(p.new_at) || undefined : undefined,
    })
  }
  return out
}
const productsOf = (body: unknown): Product[] => { const p = (body as { products?: unknown })?.products; return Array.isArray(p) ? p as Product[] : [] }
/** 24h 涨跌（%）倒推开盘价：跌了 100% 或更多（写坏的）倒推不出来，不给（原来 −100% 推出无穷大的开盘价） */
const openOf = (price: number, pct: number | undefined): number | undefined => (pct != null && pct > -100 ? price / (1 + pct / 100) : undefined)
export function decodeCbQuotes(body: unknown, now = Date.now()): Quote[] {
  const out: Quote[] = []
  for (const p of productsOf(body)) {
    if (!listed(p)) continue
    const price = pos(p.price), pct = num(p.price_percentage_change_24h), vol = nonneg(p.volume_24h)
    if (price == null) continue
    const open = openOf(price, pct)
    const q = cleanQuote({ key: keyFor(p.product_id!), price, pct, open, chg: open != null ? price - open : undefined, vol: vol != null ? vol * price : undefined, fr: null, at: now })
    if (q) out.push(q)
  }
  return out
}

/** K 线 {candles:[{start(秒), low, high, open, close, volume(币)}]}，新的在前 → 升序；额 = 量 × 收盘 */
export function decodeCbCandles(body: unknown): Bar[] {
  const d = (body as { candles?: unknown })?.candles
  if (!Array.isArray(d)) return []
  const out: Bar[] = []
  for (const r of d as Record<string, unknown>[]) {
    if (!r || typeof r !== 'object') continue
    const t = (num(r.start) ?? NaN) * 1000, c = num(r.close), v = nonneg(r.volume)
    if (!Number.isFinite(t) || c == null) continue
    out.push({ t, o: num(r.open) ?? c, h: num(r.high) ?? c, l: num(r.low) ?? c, c, v: (v ?? 0) * c, ...(v != null ? { bv: v } : {}) })
  }
  return sortBars(out)
}

/** 推送一帧（ticker / market_trades）→ 统一事件；heartbeats、subscriptions 回空 */
export function decodeCbPush(text: string): Push[] {
  const r = parseJSON(text)
  if (!r || !Array.isArray(r.events)) return []
  const out: Push[] = []
  const at = stamp(Date.parse(String(r.timestamp ?? '')))
  const events = (r.events as unknown[]).filter((e): e is Record<string, unknown> => !!e && typeof e === 'object')
  if (r.channel === 'ticker' || r.channel === 'ticker_batch') {
    for (const e of events) for (const t of (Array.isArray(e.tickers) ? e.tickers : []) as Record<string, unknown>[]) {
      const id = t?.product_id, price = pos(t?.price)
      if (typeof id !== 'string' || !cbSymbolOk(id) || price == null) continue
      const pct = num(t.price_percent_chg_24_h), vol = nonneg(t.volume_24_h)
      const open = openOf(price, pct)
      const quote = cleanQuote({ key: keyFor(id), price, pct, open, chg: open != null ? price - open : undefined, hi: pos(t.high_24_h), lo: pos(t.low_24_h), vol: vol != null ? vol * price : undefined, at })
      if (quote) out.push({ type: 'quote', quote })
    }
  } else if (r.channel === 'market_trades') {
    for (const e of events) for (const t of (Array.isArray(e.trades) ? e.trades : []) as Record<string, unknown>[]) {
      const id = t?.product_id, p = n(t?.price), q = n(t?.size)
      if (typeof id !== 'string' || !cbSymbolOk(id) || !tradeOk(p, q)) continue
      out.push({ type: 'trade', key: keyFor(id), price: p, qty: q, t: stamp(Date.parse(String(t.time ?? '')), at), sell: t.side !== 'BUY' })
    }
  }
  return out
}

// ------------------------------------------------------------ 行情面
const PAGE = 350
const products = (route?: 'direct' | 'gateway') => shared(`cb:products:${route ?? ''}`, () => vget<unknown>(`${CB.rest}/products?product_type=SPOT`, { ms: 15_000, route }))

export const cbMarket: VenueMarket = {
  shortName: 'CB', displayName: 'Coinbase', market: 'spot', quote: 'USD',
  symbolOk: cbSymbolOk,
  instruments: async route => decodeCbProducts(await products(route)),
  tickers: async route => decodeCbQuotes(await products(route)),
  maxKlines: PAGE,
  async klines(key, iv, q, opts) {
    const g = CB_GRANULARITY[iv]
    if (!g) return []
    const ms = IV_MS[iv], limit = Math.min(PAGE, q.limit), now = Date.now()
    let start: number, end: number
    if (q.start != null) { start = q.start; end = Math.min(now, q.start + (limit - 1) * ms) }
    else { end = q.end != null ? q.end - 1 : now; start = end - (limit - 1) * ms }
    const id = parseKey(key).symbol
    const bars = decodeCbCandles(await vget(`${CB.rest}/products/${encodeURIComponent(id)}/candles?granularity=${g}&start=${Math.floor(start / 1000)}&end=${Math.floor(end / 1000)}`, opts))
    return q.end != null ? bars.filter(b => b.t < q.end!) : bars
  },
  intervals: { native: CB_GRANULARITY, derived: { '3m': '1m', '8h': '4h', '12h': '6h', '1w': '1d', '1M': '1d' } },
  stream: {
    endpoint: () => 'main',
    url: (_ep, route, gw) => route === 'gateway' ? `${gw}${CB.hub}` : CB.ws,
    topics(sub) {
      const id = parseKey(sub.key).symbol
      return sub.kind === 'ticker' || sub.kind === 'mark' ? [`ticker|${id}`] : [`market_trades|${id}`]
    },
    frames(_ep, topics, on) {
      const by = new Map<string, string[]>()
      for (const t of topics) { const [ch, id] = t.split('|'); by.set(ch, [...(by.get(ch) ?? []), id]) }
      return [...by].map(([channel, product_ids]) => JSON.stringify({ type: on ? 'subscribe' : 'unsubscribe', channel, product_ids }))
    },
    decoder: () => decodeCbPush,
    hello: [JSON.stringify({ type: 'subscribe', channel: 'heartbeats' })],
    maxTopics: 48,
    // 官方：未鉴权连接每 IP 上行 ≤ 8 条 / 秒（订阅、退订帧都算）；这里 4 条 / 秒
    controlGapMs: 250,
    klineFromTrades: true,
  },
}

// ------------------------------------------------------------ 订单流
export const coinbaseSubscribe = (b: DepthBook): string[] =>
  ([['level2', [b.venue.instrument]], ['market_trades', [b.venue.instrument]], ['heartbeats', []]] as [string, string[]][])
    .map(([channel, ids]) => JSON.stringify(ids.length ? { type: 'subscribe', channel, product_ids: ids } : { type: 'subscribe', channel }))

export function decodeCoinbase(text: string, b: DepthBook): Out[] {
  const r = parseJSON(text)
  if (!r) return []
  const seq = n(r.sequence_num)
  if (!Number.isFinite(seq)) return []
  const delta = (bids: BookLevel[] = [], asks: BookLevel[] = []): DepthMessage =>
    ({ type: 'delta', delta: { firstUpdateID: seq, finalUpdateID: seq, previousFinalUpdateID: null, bids, asks, eventTimeMs: Date.now(), connection: 0 } })
  const advance = delta()
  const events = Array.isArray(r.events) ? (r.events as Record<string, unknown>[]) : []
  const ch = r.channel
  if (ch === 'l2_data' || ch === 'level2') {
    const mine = events.filter(e => e.product_id == null || e.product_id === b.venue.instrument)
    const snap = mine.find(e => e.type === 'snapshot')
    const pf = b.priceFactor, qf = quantityFactor(b)
    const split = (list: Record<string, unknown>[]): { bids: BookLevel[]; asks: BookLevel[] } => {
      const bids: BookLevel[] = [], asks: BookLevel[] = []
      for (const e of list) for (const u of (Array.isArray(e.updates) ? e.updates : []) as Record<string, unknown>[]) {
        const p = n(u?.price_level), q = n(u?.new_quantity)
        if (!levelOk(p, q)) continue
        const lvl = { price: p * pf, quantity: q * qf }
        if (u.side === 'bid') bids.push(lvl); else if (u.side === 'offer' || u.side === 'ask') asks.push(lvl)
      }
      return { bids, asks }
    }
    if (snap) {
      const { bids, asks } = split([snap])
      return [[b.id, { type: 'snapshot', snapshot: {
        lastUpdateID: seq, requestedLevels: Math.max(bids.length, asks.length) + 1, bids, asks, connection: 0, slidingWindow: false,
      } }]]
    }
    const { bids, asks } = split(mine)
    return [[b.id, delta(bids, asks)]]
  }
  if (ch === 'market_trades') {
    const out: Out[] = [[b.id, advance]]
    for (const e of events) {
      if (e.type !== 'update') continue
      for (const t of (Array.isArray(e.trades) ? e.trades : []) as Record<string, unknown>[]) {
        if (t.product_id != null && t.product_id !== b.venue.instrument) continue
        const p = n(t?.price), q = n(t?.size), ts = Date.parse(String(t?.time ?? ''))
        if (!tradeOk(p, q)) continue
        out.push([b.id, trade(b, p, q, t.side === 'BUY' ? 'ask' : 'bid', Number.isFinite(ts) ? ts : Date.now())])
      }
    }
    return out
  }
  return [[b.id, advance]]
}

/** 订单流的 30 分钟 K 线：和行情同一份解码，换成订单流的 Kline（计价额 = 量 × 收盘；没有主动买） */
export function parseCoinbaseCandles(body: unknown, priceFactor = 1): Kline[] {
  return decodeCbCandles(body).filter(b => b.c > 0 && b.v >= 0)
    .map(b => ({ t: b.t, h: b.h * priceFactor, l: b.l * priceFactor, c: b.c * priceFactor, quote: b.v, buy: null }))
}

const SLOT_MS = 1_800_000

export const coinbase: VenueAdapter = {
  key: 'coinbase',
  label: 'Coinbase',
  color: 'var(--of-cb)',
  sequenceModel: () => 'strictIncrementing',
  snapshotInBand: true,
  maxBooksPerConn: 1,
  connections: books => books.map(b => ({
    key: `coinbase-${b.venue.instrument}`, books: [b], urls: [CB.ws],
    subscribe: () => coinbaseSubscribe(b), decode: t => decodeCoinbase(t, b),
  })),
  klines30m(b, now, slots) {
    if (b.venue.product !== 'spot') return null
    const end = Math.ceil(now / 1000), start = Math.floor((Math.floor(now / SLOT_MS) * SLOT_MS - (slots - 1) * SLOT_MS) / 1000)
    const f = b.priceFactor
    return { url: `${CB.raw}/products/${encodeURIComponent(b.venue.instrument)}/candles?source=${CB.id}&granularity=THIRTY_MINUTE&start=${start}&end=${end}`, parse: x => parseCoinbaseCandles(x, f) }
  },
  fallback: (_symbol, base) => [{ product: 'spot', instrument: base + '-USD', priceScale: 1 }],
  market: cbMarket,
}
