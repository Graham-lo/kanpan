/* Hkline Web · 多交易所 · OKX（previousFinalExact，快照在流里，400 档滑动窗口）
 *
 * 直连 ws.okx.com，连不上退到网关中继 /v1/market/ws/okx；网关线路恒中继。一条最多 12 本。
 * 断档只退订重订那一本的 books，同连接其它簿不动。
 */
import { chunk, levels, n, parseJSON, trade, type DepthBook, type Kline, type Out, type VenueAdapter } from './common'

export const OKX_MAX_BOOKS = 12
export const OKX_WINDOW = 400
export function okxSubscribe(books: DepthBook[]): string[] {
  const args = books.flatMap(b => [{ channel: 'books', instId: b.venue.instrument }, { channel: 'trades', instId: b.venue.instrument }])
  return chunk(args, 12).map(a => JSON.stringify({ op: 'subscribe', args: a }))
}
export const okxResubscribe = (b: DepthBook): string[] =>
  ['unsubscribe', 'subscribe'].map(op => JSON.stringify({ op, args: [{ channel: 'books', instId: b.venue.instrument }] }))

export function decodeOKX(text: string, byInst: Map<string, DepthBook>): Out[] {
  if (text === 'pong') return []
  const r = parseJSON(text)
  if (!r || r.event != null) return []
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

/** OKX K 线 {data:[[ts, o, h, l, c, vol, volCcy, volCcyQuote, confirm]]}，新的在前；没有主动买 */
export function parseOkxCandles(body: unknown, priceFactor = 1): Kline[] {
  const d = (body as { data?: unknown })?.data
  if (!Array.isArray(d)) return []
  const out: Kline[] = []
  for (const r of d) {
    if (!Array.isArray(r)) continue
    const t = +r[0], q = +r[7]
    if (!Number.isFinite(t) || !(q >= 0)) continue
    out.push({ t, h: +r[2] * priceFactor, l: +r[3] * priceFactor, c: +r[4] * priceFactor, quote: q, buy: null })
  }
  return out.sort((a, b) => a.t - b.t)
}

export const okx: VenueAdapter = {
  key: 'okx',
  label: 'OKX',
  color: 'var(--of-okx)',
  sequenceModel: () => 'previousFinalExact',
  snapshotInBand: true,
  maxBooksPerConn: OKX_MAX_BOOKS,
  connections(books, ctx) {
    const relay = `${ctx.gw}/v1/market/ws/okx`
    return chunk(books, OKX_MAX_BOOKS).map((c, i) => {
      const map = new Map(c.map(b => [b.venue.instrument, b]))
      return {
        key: `okx${i}`, books: c, urls: ctx.route === 'gateway' ? [relay] : ['wss://ws.okx.com:8443/ws/v5/public', relay],
        subscribe: () => okxSubscribe(c), decode: t => decodeOKX(t, map), ping: { text: 'ping', everyMs: 20_000 }, resubscribe: okxResubscribe,
      }
    })
  },
  klines30m(b, _now, slots) {
    const v = b.venue
    if (v.product !== 'spot' && v.product !== 'usdtPerp') return null
    const f = b.priceFactor
    return { url: `https://www.okx.com/api/v5/market/candles?instId=${encodeURIComponent(v.instrument)}&bar=30m&limit=${slots}`, parse: x => parseOkxCandles(x, f) }
  },
}
