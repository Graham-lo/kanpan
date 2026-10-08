/* Hkline Web · 多交易所 · Coinbase 现货（strictIncrementing：整条连接一个序号，一本簿一条连接；快照在流里）
 *
 * 恒直连 advanced-trade-ws；断档整条重连（没有单本重订）。K 线走 kanpan-api 的原样转发（浏览器跨域不让直取）。
 */
import { n, parseJSON, quantityFactor, trade, type DepthBook, type Kline, type Out, type VenueAdapter } from './common'
import type { BookLevel, DepthMessage } from '../orderflow/types'

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

/** Coinbase K 线 {candles:[{start(秒), low, high, open, close, volume(币)}]} → 计价额 = 量 × 收盘；没有主动买 */
export function parseCoinbaseCandles(body: unknown, priceFactor = 1): Kline[] {
  const d = (body as { candles?: unknown })?.candles
  if (!Array.isArray(d)) return []
  const out: Kline[] = []
  for (const r of d) {
    const o = r as Record<string, unknown>
    const t = +(o.start as string) * 1000, c = +(o.close as string), v = +(o.volume as string)
    if (!Number.isFinite(t) || !(c > 0) || !(v >= 0)) continue
    out.push({ t, h: +(o.high as string) * priceFactor, l: +(o.low as string) * priceFactor, c: c * priceFactor, quote: v * c, buy: null })
  }
  return out.sort((a, b) => a.t - b.t)
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
    key: `coinbase-${b.venue.instrument}`, books: [b], urls: ['wss://advanced-trade-ws.coinbase.com'],
    subscribe: () => coinbaseSubscribe(b), decode: t => decodeCoinbase(t, b),
  })),
  klines30m(b, now, slots) {
    if (b.venue.product !== 'spot') return null
    const end = Math.ceil(now / 1000), start = Math.floor((Math.floor(now / SLOT_MS) * SLOT_MS - (slots - 1) * SLOT_MS) / 1000)
    const f = b.priceFactor
    return { url: `/v1/market/raw/products/${encodeURIComponent(b.venue.instrument)}/candles?source=coinbase&granularity=THIRTY_MINUTE&start=${start}&end=${end}`, parse: x => parseCoinbaseCandles(x, f) }
  },
  fallback: (_symbol, base) => [{ product: 'spot', instrument: base + '-USD', priceScale: 1 }],
}
