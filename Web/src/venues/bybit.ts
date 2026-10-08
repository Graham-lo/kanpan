/* Hkline Web · 多交易所 · Bybit v5 public（strictIncrementing，快照在流里，1000 档滑动窗口）
 *
 * 一个 category（spot / linear / inverse）一组连接，一条最多 12 本（簿 + 成交 = 24 个 topic，中继上限）；
 * 直连 stream.bybit.com，连不上退到网关中继 /v1/market/ws/bybit?category=…；网关线路恒中继。
 * 订 orderbook.1000.<sym> + publicTrade.<sym>，一条订阅消息 ≤ 10 个 args（spot 的硬限，统一按 10）。
 * 2026-10-08 录帧：三个 category 的 u 都严格 +1 → strictIncrementing；断档只退订重订那一本的 orderbook topic
 * （Bybit 重订会重发 snapshot），同连接其它簿不动。u == 1 的 snapshot 是对方服务重启，整本覆盖（restart）。
 * 心跳每 20 秒 {"op":"ping"}，回 {"success":true,"ret_msg":"pong","op":"ping"} 或 {"op":"pong"}，订阅回执 {"op":"subscribe"}，都静默吞掉。
 * 成交 S 是主动方：Buy 吃卖盘 → hit ask；L / BT / RPI / seq 这几个字段不用。
 */
import type { Venue } from '../orderflow/types'
import { chunk, levels, n, parseJSON, trade, type DepthBook, type Out, type VenueAdapter } from './common'

export type BybitCategory = 'spot' | 'linear' | 'inverse'
export function bybitCategory(v: Venue): BybitCategory {
  if (v.product === 'spot') return 'spot'
  return v.notional.kind === 'inverse' ? 'inverse' : 'linear'
}
export const BYBIT_DEPTH = 1000
export const BYBIT_MAX_BOOKS = 12
export const BYBIT_ARGS_PER_MESSAGE = 10
const bookTopic = (b: DepthBook): string => `orderbook.${BYBIT_DEPTH}.${b.venue.instrument}`
const tradeTopic = (b: DepthBook): string => `publicTrade.${b.venue.instrument}`

export const bybitSubscribe = (books: DepthBook[]): string[] =>
  chunk(books.flatMap(b => [bookTopic(b), tradeTopic(b)]), BYBIT_ARGS_PER_MESSAGE).map(args => JSON.stringify({ op: 'subscribe', args }))
export const bybitResubscribe = (b: DepthBook): string[] =>
  ['unsubscribe', 'subscribe'].map(op => JSON.stringify({ op, args: [bookTopic(b)] }))

/** bySymbol：Bybit 自己的 symbol（大写）→ 簿 */
export function decodeBybit(text: string, bySymbol: Map<string, DepthBook>): Out[] {
  const r = parseJSON(text)
  if (!r || typeof r.topic !== 'string') return [] // pong、订阅回执、错误回执
  const topic = r.topic
  const dot = topic.lastIndexOf('.')
  const b = bySymbol.get(topic.slice(dot + 1))
  if (!b) return []
  if (topic.startsWith('orderbook.')) {
    const d = r.data as Record<string, unknown> | undefined
    const u = n(d?.u), ts = n(r.ts)
    if (!d || !Number.isFinite(u)) return []
    if (r.type === 'snapshot') {
      return [[b.id, { type: 'snapshot', snapshot: {
        lastUpdateID: u, requestedLevels: BYBIT_DEPTH, bids: levels(d.b, b), asks: levels(d.a, b),
        eventTimeMs: Number.isFinite(ts) ? ts : undefined, connection: 0, slidingWindow: true, restart: u === 1,
      } }]]
    }
    if (r.type !== 'delta') return []
    return [[b.id, { type: 'delta', delta: {
      firstUpdateID: u, finalUpdateID: u, previousFinalUpdateID: null,
      bids: levels(d.b, b), asks: levels(d.a, b), eventTimeMs: Number.isFinite(ts) ? ts : Date.now(), connection: 0,
    } }]]
  }
  if (topic.startsWith('publicTrade.')) {
    const out: Out[] = []
    for (const t of (Array.isArray(r.data) ? r.data : []) as Record<string, unknown>[]) {
      const p = n(t.p), q = n(t.v), T = n(t.T)
      if (!Number.isFinite(p) || !Number.isFinite(q)) continue
      out.push([b.id, trade(b, p, q, t.S === 'Buy' ? 'ask' : 'bid', Number.isFinite(T) ? T : Date.now())])
    }
    return out
  }
  return []
}

export const bybit: VenueAdapter = {
  key: 'bybit',
  label: 'Bybit',
  color: 'var(--of-bybit)',
  sequenceModel: () => 'strictIncrementing',
  snapshotInBand: true,
  maxBooksPerConn: BYBIT_MAX_BOOKS,
  connections(books, ctx) {
    const by: Record<BybitCategory, DepthBook[]> = { spot: [], linear: [], inverse: [] }
    for (const b of books) by[bybitCategory(b.venue)].push(b)
    return (Object.keys(by) as BybitCategory[]).flatMap(cat => chunk(by[cat], BYBIT_MAX_BOOKS).map((c, i) => {
      const map = new Map(c.map(b => [b.venue.instrument, b]))
      const relay = `${ctx.gw}/v1/market/ws/bybit?category=${cat}`
      return {
        key: `bybit-${cat}${i}`, books: c,
        urls: ctx.route === 'gateway' ? [relay] : [`wss://stream.bybit.com/v5/public/${cat}`, relay],
        subscribe: () => bybitSubscribe(c), decode: (t: string) => decodeBybit(t, map),
        ping: { text: JSON.stringify({ op: 'ping' }), everyMs: 20_000 }, resubscribe: bybitResubscribe,
      }
    }))
  },
  // 和币安同名（1000PEPEUSDT 这类前缀一致）：按图上的单位
  fallback: (symbol, _base, chartScale) => [{ product: 'usdtPerp', instrument: symbol, priceScale: chartScale }],
}
