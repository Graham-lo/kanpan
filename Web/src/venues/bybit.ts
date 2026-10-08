/* Hkline Web · 多交易所 · Bybit v5（行情 + 主力订单流，一家一个模块）
 *
 * 行情（2026-10-08，报文按 Bybit v5 官方文档与 scratchpad 速查表写，容器连不上 Bybit 录不了真帧）：
 *   - 只收 USDT 线性永续（category=linear、contractType LinearPerpetual、quoteCoin USDT、status Trading）；
 *     网页键 bybit/usd_m/BTCUSDT（Bybit 原生就是这形状，1000PEPEUSDT 原样）。
 *   - REST 直连 api.bybit.com（带 CORS），网关 /v1/market/raw/v5/…?source=bybit；限流器 20 次 / 秒（公共 REST 按 IP 很宽）。
 *   - tickers 一条就有价、额（turnover24h，计价）、标记价、指数价、持仓量（币）、费率与下次结算：整表一次拿全。
 *   - K 线新的在前，倒过来；成交额 turnover、量 volume（币）。没有 8 时，由 4 时并。
 *   - 推送 wss://stream.bybit.com/v5/public/linear（网关 /v1/market/ws/bybit?category=linear）：tickers.<SYM>（行情与标记价共用）、
 *     kline.<interval>.<SYM>、publicTrade.<SYM>；一条订阅消息 ≤ 10 个 args；每 20 秒 {"op":"ping"}。
 *     tickers 先来 snapshot、之后 delta 只带变了的字段：解码器按连接给每只留一份快照，合并后再出行情。
 *
 * 订单流（strictIncrementing，快照在流里，1000 档滑动窗口）：
 *   一个 category（spot / linear / inverse）一组连接，一条最多 12 本（簿 + 成交 = 24 个 topic，中继上限）；
 *   直连 stream.bybit.com，连不上退到网关中继 /v1/market/ws/bybit?category=…；网关线路恒中继。
 *   订 orderbook.1000.<sym> + publicTrade.<sym>，一条订阅消息 ≤ 10 个 args（spot 的硬限，统一按 10）。
 *   2026-10-08 录帧：三个 category 的 u 都严格 +1 → strictIncrementing；断档只退订重订那一本的 orderbook topic
 *   （Bybit 重订会重发 snapshot），同连接其它簿不动。u == 1 的 snapshot 是对方服务重启，整本覆盖（restart）。
 *   心跳每 20 秒 {"op":"ping"}，回 {"success":true,"ret_msg":"pong","op":"ping"} 或 {"op":"pong"}，订阅回执 {"op":"subscribe"}，都静默吞掉。
 *   成交 S 是主动方：Buy 吃卖盘 → hit ask；L / BT / RPI / seq 这几个字段不用。
 */
import type { Venue } from '../orderflow/types'
import type { Bar } from '../chart/calc'
import { registerGate } from '../market/limit'
import { apiOrigin } from '../market/origin'
import { keyOf, parseKey } from '../market/identity'
import { badgeColor, baseOf, cnOf, decOfTick, type Sym } from '../market/symbols'
import { chunk, cleanQuote, levels, n, nonneg, num, parseJSON, pos, stamp, trade, tradeOk, type DepthBook, type Out, type Push, type Quote, type VenueAdapter, type VenueMarket } from './common'
import { rawRewrite, shared, vget } from './http'
import { cleanBar, sortBars } from './bars'

// ------------------------------------------------------------ 地址表（这一家唯一的一份）
export const BYBIT = {
  id: 'bybit',
  rest: 'https://api.bybit.com',
  ws: (cat: string) => `wss://stream.bybit.com/v5/public/${cat}`,
  relay: (cat: string) => `/v1/market/ws/bybit?category=${cat}`,
} as const
/** 这一家唯一的限流器（直连 / 网关各一道）。官方（Rate Limit Rules）：按 IP、**所有接口共用一个窗口**，
 *  任意 5 秒 ≤ 600 次（api.bybit.com 与 api.bytick.com 合算），超了 403 封约 10 分钟；WS 不计入。
 *  这里取一半 300 / 5 秒（另一半留给同一出口的手机 app 与别的页）；403 也按冷却记 */
export const BYBIT_GATE = registerGate(BYBIT.id, { hosts: ['api.bybit.com', 'api.bytick.com'], rules: [{ windowMs: 5000, cap: 300 }], gateway: rawRewrite(BYBIT.rest + '/', BYBIT.id, apiOrigin) })

/** 服务端 bybit::symbol_ok：大写字母数字 5–40、以 USDT 结尾 */
export const bybitSymbolOk = (s: string): boolean => /^[A-Z0-9]{5,40}$/.test(s) && s.endsWith('USDT') && s.length > 4
const keyFor = (sym: string): string => keyOf(BYBIT.id, 'usd_m', sym)

export const BYBIT_INTERVALS: Record<string, string> = { '1m': '1', '3m': '3', '5m': '5', '15m': '15', '30m': '30', '1h': '60', '2h': '120', '4h': '240', '6h': '360', '12h': '720', '1d': 'D', '1w': 'W', '1M': 'M' }
const IV_OF: Record<string, string> = Object.fromEntries(Object.entries(BYBIT_INTERVALS).map(([k, v]) => [v, k]))

// ------------------------------------------------------------ 报文解码
type Body = { retCode?: number; retMsg?: string; result?: { list?: unknown[]; nextPageCursor?: string }; time?: number }
function listOf(body: unknown): unknown[] {
  const b = body as Body
  if (b && b.retCode != null && b.retCode !== 0) throw new Error(`Bybit ${b.retCode} ${b.retMsg ?? ''}`.trim())
  return Array.isArray(b?.result?.list) ? b.result!.list! : []
}

export function decodeBybitInstruments(body: unknown): Sym[] {
  const out: Sym[] = []
  for (const r of listOf(body) as Record<string, any>[]) {
    if (!r || typeof r !== 'object' || typeof r.symbol !== 'string') continue
    if (r.quoteCoin !== 'USDT' || r.contractType !== 'LinearPerpetual' || r.status !== 'Trading' || !bybitSymbolOk(r.symbol)) continue
    const base = baseOf(r.symbol)
    out.push({
      symbol: keyFor(r.symbol), venue: BYBIT.id, quote: 'USDT', raw: r.symbol, base, code: base, kind: 'crypto', cn: cnOf(base, 'crypto'),
      dec: pos(r.priceFilter?.tickSize) ? decOfTick(r.priceFilter.tickSize) : 4, color: badgeColor(base),
      price: null, chg: 0, pct: null, vol: 0, fr: null, nextFunding: null, onboard: pos(r.launchTime),
    })
  }
  return out
}

/** 一行行情（REST tickers 与推送 tickers 合并后的快照同形）。price24hPcnt 是小数（0.0123 = 1.23%） */
export function decodeBybitTicker(r: Record<string, unknown>, at: number): Quote | null {
  if (typeof r.symbol !== 'string' || !bybitSymbolOk(r.symbol)) return null
  const last = pos(r.lastPrice), prev = pos(r.prevPrice24h), p = num(r.price24hPcnt), fr = num(r.fundingRate), nf = pos(r.nextFundingTime)
  return cleanQuote({
    key: keyFor(r.symbol), price: last, open: prev, hi: pos(r.highPrice24h), lo: pos(r.lowPrice24h),
    pct: p != null ? p * 100 : undefined, chg: last != null && prev != null ? last - prev : undefined,
    vol: nonneg(r.turnover24h), mark: pos(r.markPrice), index: pos(r.indexPrice),
    fr: r.fundingRate === '' ? null : fr, nextFunding: nf, oi: nonneg(r.openInterest), at,
  })
}
export function decodeBybitTickers(body: unknown): Quote[] {
  const at = stamp((body as Body)?.time)
  return (listOf(body) as Record<string, unknown>[]).map(r => (r && typeof r === 'object' ? decodeBybitTicker(r, at) : null)).filter((q): q is Quote => !!q)
}

/** K 线 result.list [[start, o, h, l, c, volume(币), turnover(计价)]]，新的在前 → 升序 */
export function decodeBybitKlines(body: unknown): Bar[] {
  const out: Bar[] = []
  for (const r of listOf(body)) {
    if (!Array.isArray(r)) continue
    const t = n(r[0]), c = n(r[4]), v = n(r[5]), q = n(r[6])
    if (!Number.isFinite(t) || !Number.isFinite(c)) continue
    out.push({ t, o: n(r[1]), h: n(r[2]), l: n(r[3]), c, v: Number.isFinite(q) ? q : (v || 0) * c, ...(Number.isFinite(v) ? { bv: v } : {}) })
  }
  return sortBars(out)
}

/** 推送解码器（一条连接一个）：tickers 的 delta 只带变了的字段，按品种留一份快照合并后再出行情。
 *  比上一帧旧的（ts 倒退：重订、中继补发时的旧帧）不并进快照——并进去之后，后面一条只带成交额的 delta
 *  会把那个旧价当成新的带出去（2026-10-08 解码模糊） */
export function bybitDecoder(): (text: string) => Push[] {
  const snaps = new Map<string, Record<string, unknown>>()
  const seen = new Map<string, number>()
  return text => {
    const r = parseJSON(text)
    if (!r || typeof r.topic !== 'string') return []   // pong、订阅回执
    const topic = r.topic
    const sym = topic.slice(topic.lastIndexOf('.') + 1)
    const at = stamp(r.ts)
    if (topic.startsWith('tickers.')) {
      const d = r.data as Record<string, unknown> | undefined
      if (!d || typeof d !== 'object' || Array.isArray(d) || !bybitSymbolOk(sym)) return []
      const last = seen.get(sym)
      if (last != null && at < last) return []
      const prev = r.type === 'snapshot' ? undefined : snaps.get(sym)
      // delta 先于 snapshot 到（重订的空档）：没有底就不出，等 snapshot
      if (r.type === 'delta' && !prev) return []
      const merged = { ...(prev ?? {}), ...d, symbol: sym }
      snaps.set(sym, merged)
      seen.set(sym, at)
      const q = decodeBybitTicker(merged, at)
      return q ? [{ type: 'quote', quote: q }] : []
    }
    if (topic.startsWith('kline.')) {
      const iv = IV_OF[topic.split('.')[1]]
      if (!iv || !bybitSymbolOk(sym)) return []
      const out: Push[] = []
      for (const k of (Array.isArray(r.data) ? r.data : []) as Record<string, unknown>[]) {
        if (!k || typeof k !== 'object') continue
        const t = num(k.start), c = num(k.close)
        if (t == null || c == null) continue
        const v = nonneg(k.volume), q = nonneg(k.turnover)
        const bar = cleanBar({ t, o: num(k.open) ?? c, h: num(k.high) ?? c, l: num(k.low) ?? c, c, v: q ?? (v ?? 0) * c, ...(v != null ? { bv: v } : {}) })
        if (bar) out.push({ type: 'kline', key: keyFor(sym), iv, bar })
      }
      return out
    }
    if (topic.startsWith('publicTrade.')) {
      if (!bybitSymbolOk(sym)) return []
      const out: Push[] = []
      for (const t of (Array.isArray(r.data) ? r.data : []) as Record<string, unknown>[]) {
        const p = n(t?.p), q = n(t?.v)
        if (!tradeOk(p, q)) continue
        out.push({ type: 'trade', key: keyFor(sym), price: p, qty: q, t: stamp(t.T, at), sell: t.S === 'Sell' })
      }
      return out
    }
    return []
  }
}

// ------------------------------------------------------------ 行情面
const KLINE_PAGE = 1000

export const bybitMarket: VenueMarket = {
  shortName: 'Bybit', displayName: 'Bybit', market: 'usd_m', quote: 'USDT',
  symbolOk: bybitSymbolOk,
  instruments: route => shared(`bybit:ins:${route ?? ''}`, async () => {
    const out: Sym[] = []
    let cursor = ''
    for (let page = 0; page < 5; page++) {
      const body = await vget<Body>(`${BYBIT.rest}/v5/market/instruments-info?category=linear&limit=1000${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`, { ms: 12_000, route })
      out.push(...decodeBybitInstruments(body))
      cursor = body?.result?.nextPageCursor ?? ''
      if (!cursor) break
    }
    return out
  }),
  tickers: route => shared(`bybit:tk:${route ?? ''}`, async () => decodeBybitTickers(await vget(`${BYBIT.rest}/v5/market/tickers?category=linear`, { route }))),
  async ticker(key, opts) {
    return decodeBybitTickers(await vget(`${BYBIT.rest}/v5/market/tickers?category=linear&symbol=${parseKey(key).symbol}`, opts))[0] ?? null
  },
  maxKlines: KLINE_PAGE,
  async klines(key, iv, q, opts) {
    const interval = BYBIT_INTERVALS[iv]
    if (!interval) return []
    const range = q.end != null ? `&end=${q.end - 1}` : q.start != null ? `&start=${q.start}` : ''
    return decodeBybitKlines(await vget(`${BYBIT.rest}/v5/market/kline?category=linear&symbol=${parseKey(key).symbol}&interval=${interval}&limit=${Math.min(KLINE_PAGE, q.limit)}${range}`, opts))
  },
  /** 持仓量在单只行情里（币） */
  async openInterest(key, opts) { return (await bybitMarket.ticker!(key, opts))?.oi ?? null },
  intervals: { native: BYBIT_INTERVALS, derived: { '8h': '4h' } },
  stream: {
    endpoint: sub => sub.kind === 'kline' && !BYBIT_INTERVALS[sub.iv ?? ''] ? null : 'linear',
    url: (_ep, route, gw) => route === 'gateway' ? `${gw}${BYBIT.relay('linear')}` : BYBIT.ws('linear'),
    topics(sub) {
      const s = parseKey(sub.key).symbol
      if (sub.kind === 'kline') return [`kline.${BYBIT_INTERVALS[sub.iv ?? '']}.${s}`]
      if (sub.kind === 'trade') return [`publicTrade.${s}`]
      return [`tickers.${s}`]   // 行情与标记价共用
    },
    frames: (_ep, topics, on) => chunk(topics, BYBIT_ARGS_PER_MESSAGE).map(args => JSON.stringify({ op: on ? 'subscribe' : 'unsubscribe', args })),
    decoder: () => bybitDecoder(),
    ping: { text: JSON.stringify({ op: 'ping' }), everyMs: 20_000 },
    maxTopics: 48,
  },
}

// ------------------------------------------------------------ 订单流
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
      const p = n(t?.p), q = n(t?.v), T = n(t?.T)
      if (!tradeOk(p, q)) continue
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
      const relay = `${ctx.gw}${BYBIT.relay(cat)}`
      return {
        key: `bybit-${cat}${i}`, books: c,
        urls: ctx.route === 'gateway' ? [relay] : [BYBIT.ws(cat), relay],
        subscribe: () => bybitSubscribe(c), decode: (t: string) => decodeBybit(t, map),
        ping: { text: JSON.stringify({ op: 'ping' }), everyMs: 20_000 }, resubscribe: bybitResubscribe,
      }
    }))
  },
  // 和币安同名（1000PEPEUSDT 这类前缀一致）：按图上的单位
  fallback: (symbol, _base, chartScale) => [{ product: 'usdtPerp', instrument: parseKey(symbol).symbol, priceScale: chartScale }],
  market: bybitMarket,
}
