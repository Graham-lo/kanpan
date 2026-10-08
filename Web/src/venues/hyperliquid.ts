/* Hkline Web · 多交易所 · Hyperliquid 永续（snapshotOnly：没有序号，每帧整本替换；每侧 20 档滑动窗口）
 *
 * 恒走网关中继 /v1/market/ws/hyperliquid（服务端整个进程只开一条上游、按引用计数订退，浏览器不直连），
 * 一条最多 8 本（16 个订阅，中继上限）。只订 nSigFigs:4 那一档：4 位有效数字的网格永远 ≤ 步长且整除步长，
 * 直接落进现成的桶。心跳每 30 秒 {"method":"ping"}（回 {"channel":"pong"}）；订阅回执 subscriptionResponse 不理；
 * 60 秒没有任何帧断开重连；连上到第一帧之间簿算 bootstrapping。
 * 成交 side：B = 主动买 → hit ask，A = 主动卖 → hit bid。kPEPE 这类 k 前缀的一单位是 1000 个币（品种表给 priceScale 1000）。
 */
import type { BookLevel } from '../orderflow/types'
import { chunk, n, parseJSON, quantityFactor, trade, type DepthBook, type Out, type VenueAdapter } from './common'

export const HL_WINDOW = 20
export const HL_MAX_BOOKS = 8
export const HL_SIG_FIGS = 4
export const HL_SILENCE_MS = 60_000

const sub = (b: DepthBook, kind: 'l2Book' | 'trades'): Record<string, unknown> =>
  kind === 'l2Book' ? { type: 'l2Book', coin: b.venue.instrument, nSigFigs: HL_SIG_FIGS } : { type: 'trades', coin: b.venue.instrument }
export const hlSubscribe = (books: DepthBook[]): string[] =>
  books.flatMap(b => (['l2Book', 'trades'] as const).map(k => JSON.stringify({ method: 'subscribe', subscription: sub(b, k) })))
export const hlResubscribe = (b: DepthBook): string[] =>
  ['unsubscribe', 'subscribe'].map(method => JSON.stringify({ method, subscription: sub(b, 'l2Book') }))

function hlLevels(raw: unknown, b: DepthBook): BookLevel[] {
  if (!Array.isArray(raw)) return []
  const pf = b.priceFactor, qf = quantityFactor(b)
  const out: BookLevel[] = []
  for (const l of raw as Record<string, unknown>[]) {
    const p = n(l?.px), q = n(l?.sz)
    if (Number.isFinite(p) && Number.isFinite(q)) out.push({ price: p * pf, quantity: q * qf })
  }
  return out
}

/** byCoin：HL 的 coin 名（BTC、kPEPE，大小写照原样）→ 簿 */
export function decodeHyperliquid(text: string, byCoin: Map<string, DepthBook>): Out[] {
  const r = parseJSON(text)
  if (!r) return []
  if (r.channel === 'l2Book') {
    const d = r.data as Record<string, unknown> | undefined
    const b = typeof d?.coin === 'string' ? byCoin.get(d.coin) : undefined
    const lv = d?.levels
    if (!b || !Array.isArray(lv)) return []
    const t = n(d!.time)
    const time = Number.isFinite(t) ? t : Date.now()
    return [[b.id, { type: 'snapshot', snapshot: {
      lastUpdateID: time, requestedLevels: HL_WINDOW, bids: hlLevels(lv[0], b), asks: hlLevels(lv[1], b),
      eventTimeMs: time, connection: 0, slidingWindow: true,
    } }]]
  }
  if (r.channel === 'trades') {
    const out: Out[] = []
    for (const x of (Array.isArray(r.data) ? r.data : []) as Record<string, unknown>[]) {
      const b = typeof x.coin === 'string' ? byCoin.get(x.coin) : undefined
      const p = n(x.px), q = n(x.sz), t = n(x.time)
      if (!b || !Number.isFinite(p) || !Number.isFinite(q)) continue
      out.push([b.id, trade(b, p, q, x.side === 'B' ? 'ask' : 'bid', Number.isFinite(t) ? t : Date.now())])
    }
    return out
  }
  return [] // pong、subscriptionResponse、error
}

export const hyperliquid: VenueAdapter = {
  key: 'hyperliquid',
  label: 'Hyperliquid',
  color: 'var(--of-hl)',
  sequenceModel: () => 'snapshotOnly',
  snapshotInBand: true,
  maxBooksPerConn: HL_MAX_BOOKS,
  connections: (books, ctx) => chunk(books, HL_MAX_BOOKS).map((c, i) => {
    const map = new Map(c.map(b => [b.venue.instrument, b]))
    return {
      key: `hyperliquid${i}`, books: c, urls: [`${ctx.gw}/v1/market/ws/hyperliquid`],
      subscribe: () => hlSubscribe(c), decode: (t: string) => decodeHyperliquid(t, map),
      ping: { text: JSON.stringify({ method: 'ping' }), everyMs: 30_000 }, silenceMs: HL_SILENCE_MS, resubscribe: hlResubscribe,
    }
  }),
  // k 前缀 = 1000 个币一单位
  fallback: (_symbol, base, chartScale) => [chartScale >= 1000 ? { product: 'usdtPerp', instrument: 'k' + base, priceScale: 1000 } : { product: 'usdtPerp', instrument: base, priceScale: 1 }],
}
