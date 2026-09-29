/* Hkline Web · 主力订单流 · 三家交易所的报文解码（照 KanpanNetwork/OrderFlow 的三个适配器）
 *
 * 只管「一帧文本 → 哪本簿的哪条 DepthMessage」，连接与重连在 feed.ts。
 * 价与量在这里就乘上 priceFactor / quantityFactor 换成图上的单位（1000PEPE 一格是 1000 个币）。
 */
import type { BookLevel, BookSide, DepthMessage, Venue } from './types'

export interface DepthBook {
  id: string
  venue: Venue
  /** 本家价格 × priceFactor = 图上的价格 */
  priceFactor: number
  expiryMs: number | null
  tick: number | null
}
export const quantityFactor = (b: DepthBook): number => (b.venue.notional.kind === 'linear' ? 1 / b.priceFactor : 1)

export type Out = [string, DepthMessage]

const n = (v: unknown): number => (typeof v === 'number' ? v : typeof v === 'string' ? parseFloat(v) : NaN)

function levels(raw: unknown, b: DepthBook): BookLevel[] {
  if (!Array.isArray(raw)) return []
  const pf = b.priceFactor, qf = quantityFactor(b)
  const out: BookLevel[] = []
  for (const r of raw as unknown[][]) {
    const p = n(r?.[0]), q = n(r?.[1])
    if (Number.isFinite(p) && Number.isFinite(q)) out.push({ price: p * pf, quantity: q * qf })
  }
  return out
}
const trade = (b: DepthBook, price: number, qty: number, hit: BookSide, t: number): DepthMessage =>
  ({ type: 'trade', trade: { price: price * b.priceFactor, quantity: qty * quantityFactor(b), hitSide: hit, timeMs: t } })

// ------------------------------------------------------------------ 币安

export type BinanceMarket = 'um' | 'cm' | 'spot'
export function binanceMarket(v: Venue): BinanceMarket {
  if (v.product === 'spot') return 'spot'
  if (v.product === 'usdtPerp') return 'um'
  if (v.product === 'coinPerp') return 'cm'
  return v.notional.kind === 'inverse' ? 'cm' : 'um'
}
export const BINANCE_SNAPSHOT_LEVELS: Record<BinanceMarket, number> = { spot: 5000, um: 1000, cm: 1000 }
export const binanceStreams = (b: DepthBook): string[] => { const s = b.venue.instrument.toLowerCase(); return [`${s}@depth@100ms`, `${s}@aggTrade`] }

export function decodeBinance(text: string, bySymbol: Map<string, DepthBook>): Out[] {
  let outer: Record<string, unknown>
  try { outer = JSON.parse(text) } catch { return [] }
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

// ------------------------------------------------------------------ OKX

export const OKX_MAX_BOOKS = 12
export const OKX_WINDOW = 400
export function okxSubscribe(books: DepthBook[]): string[] {
  const args = books.flatMap(b => [{ channel: 'books', instId: b.venue.instrument }, { channel: 'trades', instId: b.venue.instrument }])
  const out: string[] = []
  for (let i = 0; i < args.length; i += 12) out.push(JSON.stringify({ op: 'subscribe', args: args.slice(i, i + 12) }))
  return out
}
export const okxResubscribe = (b: DepthBook): string[] =>
  ['unsubscribe', 'subscribe'].map(op => JSON.stringify({ op, args: [{ channel: 'books', instId: b.venue.instrument }] }))

export function decodeOKX(text: string, byInst: Map<string, DepthBook>): Out[] {
  if (text === 'pong') return []
  let r: Record<string, unknown>
  try { r = JSON.parse(text) } catch { return [] }
  if (r.event != null) return []
  const arg = r.arg as { channel?: string; instId?: string } | undefined
  const b = arg?.instId ? byInst.get(arg.instId) : undefined
  if (!b || !Array.isArray(r.data)) return []
  const out: Out[] = []
  if (arg!.channel === 'trades') {
    for (const t of r.data as Record<string, unknown>[]) {
      const p = n(t.px), q = n(t.sz), ts = n(t.ts)
      if (!Number.isFinite(p) || !Number.isFinite(q)) continue
      out.push([b.id, trade(b, p, q, t.side === 'buy' ? 'ask' : 'bid', Number.isFinite(ts) ? ts : Date.now())])
    }
    return out
  }
  if (arg!.channel !== 'books') return []
  for (const d of r.data as Record<string, unknown>[]) {
    const seq = n(d.seqId), prev = n(d.prevSeqId), ts = n(d.ts)
    if (!Number.isFinite(seq)) continue
    if (r.action === 'snapshot') {
      out.push([b.id, { type: 'snapshot', snapshot: {
        lastUpdateID: seq, requestedLevels: OKX_WINDOW, bids: levels(d.bids, b), asks: levels(d.asks, b),
        eventTimeMs: Number.isFinite(ts) ? ts : undefined, connection: 0, slidingWindow: true,
      } }])
    } else {
      if (Number.isFinite(prev) && seq < prev) { out.push([b.id, { type: 'reset' }]); continue }
      out.push([b.id, { type: 'delta', delta: {
        firstUpdateID: seq, finalUpdateID: seq, previousFinalUpdateID: Number.isFinite(prev) ? prev : null,
        bids: levels(d.bids, b), asks: levels(d.asks, b), eventTimeMs: Number.isFinite(ts) ? ts : Date.now(), connection: 0,
      } }])
    }
  }
  return out
}

// ------------------------------------------------------------------ Coinbase（整条连接一个序号，一本簿一条连接）

export const coinbaseSubscribe = (b: DepthBook): string[] =>
  ([['level2', [b.venue.instrument]], ['market_trades', [b.venue.instrument]], ['heartbeats', []]] as [string, string[]][])
    .map(([channel, ids]) => JSON.stringify(ids.length ? { type: 'subscribe', channel, product_ids: ids } : { type: 'subscribe', channel }))

export function decodeCoinbase(text: string, b: DepthBook): Out[] {
  let r: Record<string, unknown>
  try { r = JSON.parse(text) } catch { return [] }
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
        const p = n(u.price_level), q = n(u.new_quantity)
        if (!Number.isFinite(p) || !Number.isFinite(q)) continue
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
        const p = n(t.price), q = n(t.size), ts = Date.parse(String(t.time ?? ''))
        if (!Number.isFinite(p) || !Number.isFinite(q)) continue
        out.push([b.id, trade(b, p, q, t.side === 'BUY' ? 'ask' : 'bid', Number.isFinite(ts) ? ts : Date.now())])
      }
    }
    return out
  }
  return [[b.id, advance]]
}
