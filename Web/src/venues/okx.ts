/* Hkline Web · 多交易所 · OKX（行情 + 主力订单流，一家一个模块）
 *
 * 地址表、唯一的限流器、一套报文解码都在这里；行情（VenueAdapter.market：品种表、整表行情、K 线、费率、
 * 持仓量、推送）与主力订单流（books / trades 簿）是它的两个使用面。
 *
 * 行情（2026-10-08，报文按 OKX v5 官方文档与 scratchpad 速查表写，容器连不上 OKX 录不了真帧）：
 *   - 只收 USDT 本位线性永续（instId BASE-USDT-SWAP，settleCcy USDT、ctType linear）；网页键 okx/usd_m/BASEUSDT
 *     （币安形状，同一个币 OKX 与币安只差 venue），instId 在这里互译。
 *   - REST 直连 www.okx.com（带 CORS），网关 /v1/market/raw/api/v5/…?source=okx；限流器 8 次 / 秒
 *     （公共端点按 IP 20 次 / 2 秒，K 线 40 次 / 2 秒，留余量）。
 *   - 24h 行情没有计价成交额：额 = volCcy24h（币）× last（近似，和 Coinbase 同一条已拍板的口径）；
 *     涨跌幅 = last / open24h − 1。
 *   - K 线新的在前，倒过来；成交额用 volCcyQuote，量用 volCcy（币）。6 时以上用 UTC 对齐的 6Hutc / 12Hutc / 1Dutc / 1Wutc / 1Mutc
 *     （默认 1D 是 UTC+8 对齐，和币安对不上）；没有 8 时，由 4 时并。
 *   - 推送：public 端点 tickers / trades / mark-price / funding-rate，K 线在 business 端点（另一条连接）；
 *     网关档连中继 /v1/market/ws/okx（K 线 ?endpoint=business）。每 25 秒发文本 ping，回文本 pong。
 *
 * 订单流（previousFinalExact，快照在流里，400 档滑动窗口）：
 *   直连 ws.okx.com，连不上退到网关中继 /v1/market/ws/okx；网关线路恒中继。一条最多 12 本。
 *   断档只退订重订那一本的 books，同连接其它簿不动。
 */
import type { Bar } from '../chart/calc'
import { pathOf, registerGate } from '../market/limit'
import { apiOrigin } from '../market/origin'
import { keyOf, parseKey } from '../market/identity'
import { badgeColor, baseOf, cnOf, decOfTick, type Sym } from '../market/symbols'
import { chunk, compact, levels, n, num, parseJSON, trade, type DepthBook, type Kline, type Out, type Push, type Quote, type VenueAdapter, type VenueMarket } from './common'
import { rawRewrite, shared, vget } from './http'
import { sortBars } from './bars'
import { IV_MS } from '../util/format'

// ------------------------------------------------------------ 地址表（这一家唯一的一份）
export const OKX = {
  id: 'okx',
  rest: 'https://www.okx.com',
  wsPublic: 'wss://ws.okx.com:8443/ws/v5/public',
  wsBusiness: 'wss://ws.okx.com:8443/ws/v5/business',
  /** 网关中继（K 线加 ?endpoint=business） */
  relay: '/v1/market/ws/okx',
} as const
/** 这一家唯一的限流器：行情 REST、订单流的 30 分钟 K 线都经它（直连 / 网关各一道）。
 *  官方（Rate limits）：按 IP、**每个接口各算各的**，2 秒窗口——market/candles 40 次、public/mark-price 10 次，
 *  history-candles / instruments / tickers / ticker / funding-rate / open-interest 等 20 次。
 *  这里各取一半（另一半留给同一出口的手机 app 与别的页，和币安那把同一条规矩）：candles 20、mark-price 5、其余每个接口 10。 */
const CANDLES = '/api/v5/market/candles', MARK = '/api/v5/public/mark-price'
export const OKX_GATE = registerGate(OKX.id, {
  hosts: ['www.okx.com'],
  rules: [
    { windowMs: 2000, cap: 20, key: u => pathOf(u) === CANDLES ? CANDLES : null },
    { windowMs: 2000, cap: 5, key: u => pathOf(u) === MARK ? MARK : null },
    { windowMs: 2000, cap: 10, key: u => { const p = pathOf(u); return p === CANDLES || p === MARK ? null : p } },
  ],
  gateway: rawRewrite(OKX.rest + '/', OKX.id, apiOrigin),
})

// ------------------------------------------------------------ 代号互译
/** 网页键 → instId（okx/usd_m/BTCUSDT → BTC-USDT-SWAP） */
export function okxInstId(key: string): string {
  const s = parseKey(key).symbol
  return `${s.endsWith('USDT') ? s.slice(0, -4) : s}-USDT-SWAP`
}
/** instId → 网页键；不是 USDT 线性永续的回 null */
export function okxKeyOf(inst: string): string | null {
  const m = /^([A-Z0-9]+)-USDT-SWAP$/.exec(inst)
  return m ? keyOf(OKX.id, 'usd_m', m[1] + 'USDT') : null
}
/** 服务端 okx::symbol_ok：大写字母数字 5–40、以 USDT 结尾、前面还有底名 */
export const okxSymbolOk = (s: string): boolean => /^[A-Z0-9]{5,40}$/.test(s) && s.endsWith('USDT') && s.length > 4

/** 网页周期 → OKX bar；6 时以上用 UTC 对齐那一族 */
export const OKX_BARS: Record<string, string> = { '1m': '1m', '3m': '3m', '5m': '5m', '15m': '15m', '30m': '30m', '1h': '1H', '2h': '2H', '4h': '4H', '6h': '6Hutc', '12h': '12Hutc', '1d': '1Dutc', '1w': '1Wutc', '1M': '1Mutc' }
const IV_OF_BAR: Record<string, string> = Object.fromEntries(Object.entries(OKX_BARS).map(([k, v]) => [v, k]))

// ------------------------------------------------------------ 报文解码（行情与订单流共用这一份）
type Body = { code?: string; msg?: string; data?: unknown }
function dataOf(body: unknown): unknown[] {
  const b = body as Body
  if (b && b.code != null && b.code !== '0') throw new Error(`OKX ${b.code} ${b.msg ?? ''}`.trim())
  return Array.isArray(b?.data) ? b.data : []
}

/** 品种表 public/instruments?instType=SWAP → 网页品种（只收 USDT 线性永续、在交易的） */
export function decodeOkxInstruments(body: unknown): Sym[] {
  const out: Sym[] = []
  for (const r of dataOf(body) as Record<string, string>[]) {
    if (r.settleCcy !== 'USDT' || r.ctType !== 'linear' || r.state !== 'live') continue
    const key = okxKeyOf(r.instId)
    if (!key) continue
    const sym = parseKey(key).symbol, base = baseOf(sym)
    out.push({
      symbol: key, venue: OKX.id, quote: 'USDT', raw: r.instId, base, code: base, kind: 'crypto', cn: cnOf(base, 'crypto'),
      dec: r.tickSz ? decOfTick(r.tickSz) : 4, color: badgeColor(base), price: null, chg: 0, pct: null, vol: 0, fr: null, nextFunding: null,
      onboard: +r.listTime || undefined,
    })
  }
  return out
}

/** 一行 ticker（REST market/ticker(s) 与推送 tickers 同形） */
export function decodeOkxTicker(r: Record<string, unknown>): Quote | null {
  const key = typeof r.instId === 'string' ? okxKeyOf(r.instId) : null
  const last = num(r.last)
  if (!key || last == null) return null
  const open = num(r.open24h), coins = num(r.volCcy24h)
  return compact<Quote>({
    key, price: last, open, hi: num(r.high24h), lo: num(r.low24h),
    pct: open ? (last / open - 1) * 100 : undefined, chg: open != null ? last - open : undefined,
    // 没有计价成交额：币数 × 最新价（近似）
    vol: coins != null ? coins * last : undefined,
    at: num(r.ts) ?? Date.now(),
  })
}
export function decodeOkxTickers(body: unknown): Quote[] {
  return (dataOf(body) as Record<string, unknown>[]).map(decodeOkxTicker).filter((q): q is Quote => !!q)
}

/** K 线 [[ts, o, h, l, c, vol(张), volCcy(币), volCcyQuote(计价), confirm]]，新的在前 → 升序 */
export function decodeOkxCandles(body: unknown): Bar[] {
  const out: Bar[] = []
  for (const r of dataOf(body)) {
    if (!Array.isArray(r)) continue
    const t = +r[0], o = +r[1], h = +r[2], l = +r[3], c = +r[4], coins = +r[6], q = +r[7]
    if (!Number.isFinite(t) || !Number.isFinite(c)) continue
    const b: Bar = { t, o, h, l, c, v: Number.isFinite(q) ? q : Number.isFinite(coins) ? coins * c : 0 }
    if (Number.isFinite(coins)) b.bv = coins
    out.push(b)
  }
  return sortBars(out)
}

/** 推送一帧 → 统一事件（tickers / candle* / trades / mark-price / funding-rate）；pong、回执、错误回空 */
export function decodeOkxPush(text: string): Push[] {
  if (text === 'pong') return []
  const r = parseJSON(text)
  if (!r || r.event != null || !Array.isArray(r.data)) return []
  const arg = r.arg as { channel?: string; instId?: string } | undefined
  const ch = arg?.channel ?? '', key = arg?.instId ? okxKeyOf(arg.instId) : null
  if (!key) return []
  const out: Push[] = []
  if (ch === 'tickers') {
    for (const d of r.data as Record<string, unknown>[]) { const q = decodeOkxTicker(d); if (q) out.push({ type: 'quote', quote: q }) }
  } else if (ch.startsWith('candle')) {
    const iv = IV_OF_BAR[ch.slice(6)]
    if (iv) for (const b of decodeOkxCandles({ data: r.data })) out.push({ type: 'kline', key, iv, bar: b })
  } else if (ch === 'trades') {
    for (const t of r.data as Record<string, unknown>[]) {
      const p = num(t.px), q = num(t.sz)
      if (p == null || q == null) continue
      out.push({ type: 'trade', key, price: p, qty: q, t: num(t.ts) ?? Date.now(), sell: t.side === 'sell' })
    }
  } else if (ch === 'mark-price') {
    for (const d of r.data as Record<string, unknown>[]) { const m = num(d.markPx); if (m != null) out.push({ type: 'quote', quote: { key, mark: m, at: num(d.ts) ?? Date.now() } }) }
  } else if (ch === 'funding-rate') {
    for (const d of r.data as Record<string, unknown>[]) {
      const fr = num(d.fundingRate)
      if (fr != null) out.push({ type: 'quote', quote: { key, fr, nextFunding: num(d.fundingTime) ?? null, at: num(d.ts) ?? Date.now() } })
    }
  }
  return out
}

// ------------------------------------------------------------ 行情面
const HISTORY_PAGE = 100
const RECENT_PAGE = 300

export const okxMarket: VenueMarket = {
  shortName: 'OKX', displayName: 'OKX', market: 'usd_m', quote: 'USDT',
  symbolOk: okxSymbolOk,
  instruments: route => shared(`okx:ins:${route ?? ''}`, async () => decodeOkxInstruments(await vget(`${OKX.rest}/api/v5/public/instruments?instType=SWAP`, { ms: 12_000, route }))),
  tickers: route => shared(`okx:tk:${route ?? ''}`, async () => decodeOkxTickers(await vget(`${OKX.rest}/api/v5/market/tickers?instType=SWAP`, { route }))),
  async ticker(key, opts) {
    const q = decodeOkxTickers(await vget(`${OKX.rest}/api/v5/market/ticker?instId=${okxInstId(key)}`, opts))
    return q[0] ?? null
  },
  maxKlines: RECENT_PAGE,
  /** 最新一页走 candles（≤ 300 根，首屏一发）；往前翻走 history-candles（一页 100，最多三页） */
  async klines(key, iv, q, opts) {
    const bar = OKX_BARS[iv]
    if (!bar) return []
    const inst = okxInstId(key)
    // 只给了起点（回放往后取）：换算成「截止到起点之后 limit 根」再往前翻
    let end = q.end ?? (q.start != null ? q.start + q.limit * IV_MS[iv] : undefined)
    if (end == null) return decodeOkxCandles(await vget(`${OKX.rest}/api/v5/market/candles?instId=${inst}&bar=${bar}&limit=${Math.min(RECENT_PAGE, q.limit)}`, opts))
    const out: Bar[] = []
    for (let page = 0; page < 3 && out.length < q.limit; page++) {
      const rows = decodeOkxCandles(await vget(`${OKX.rest}/api/v5/market/history-candles?instId=${inst}&bar=${bar}&limit=${HISTORY_PAGE}&after=${end}`, opts))
      if (!rows.length) break
      out.unshift(...rows)
      end = rows[0].t
      if (rows.length < HISTORY_PAGE) break
    }
    const bars = sortBars(out)
    return q.start != null ? bars.filter(b => b.t >= q.start!) : bars
  },
  async funding(key, opts) {
    const d = dataOf(await vget(`${OKX.rest}/api/v5/public/funding-rate?instId=${okxInstId(key)}`, opts))[0] as Record<string, unknown> | undefined
    if (!d) return null
    return { fr: num(d.fundingRate) ?? null, nextFunding: num(d.fundingTime) ?? null }
  },
  async openInterest(key, opts) {
    const d = dataOf(await vget(`${OKX.rest}/api/v5/public/open-interest?instType=SWAP&instId=${okxInstId(key)}`, opts))[0] as Record<string, unknown> | undefined
    return d ? num(d.oiCcy) ?? null : null
  },
  intervals: { native: OKX_BARS, derived: { '8h': '4h' } },
  stream: {
    endpoint: sub => sub.kind === 'kline' ? (OKX_BARS[sub.iv ?? ''] ? 'business' : null) : 'public',
    url: (ep, route, gw) => route === 'gateway' ? `${gw}${OKX.relay}${ep === 'business' ? '?endpoint=business' : ''}` : ep === 'business' ? OKX.wsBusiness : OKX.wsPublic,
    topics(sub) {
      const inst = okxInstId(sub.key)
      if (sub.kind === 'kline') return [`candle${OKX_BARS[sub.iv ?? '']}|${inst}`]
      if (sub.kind === 'ticker') return [`tickers|${inst}`]
      if (sub.kind === 'mark') return [`mark-price|${inst}`, `funding-rate|${inst}`]
      return [`trades|${inst}`]
    },
    frames: (_ep, topics, on) => chunk(topics.map(t => { const [channel, instId] = t.split('|'); return { channel, instId } }), 12)
      .map(args => JSON.stringify({ op: on ? 'subscribe' : 'unsubscribe', args })),
    decoder: () => decodeOkxPush,
    ping: { text: 'ping', everyMs: 25_000 },
    maxTopics: 48,
    // 官方 WS 限制：每条连接订 / 退合计 480 次 / 小时；新连接按 IP 3 次 / 秒；30 秒内要 ping
    controlPerHour: 480,
    openGapMs: 400,
  },
}

// ------------------------------------------------------------ 订单流
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

/** 订单流的 30 分钟 K 线：和行情同一份解码，换成订单流的 Kline（价乘 priceFactor；计价额；没有主动买） */
export function parseOkxCandles(body: unknown, priceFactor = 1): Kline[] {
  let bars: Bar[]
  try { bars = decodeOkxCandles(body) } catch { return [] }
  return bars.filter(b => b.v >= 0).map(b => ({ t: b.t, h: b.h * priceFactor, l: b.l * priceFactor, c: b.c * priceFactor, quote: b.v, buy: null }))
}

export const okx: VenueAdapter = {
  key: 'okx',
  label: 'OKX',
  color: 'var(--of-okx)',
  sequenceModel: () => 'previousFinalExact',
  snapshotInBand: true,
  maxBooksPerConn: OKX_MAX_BOOKS,
  connections(books, ctx) {
    const relay = `${ctx.gw}${OKX.relay}`
    return chunk(books, OKX_MAX_BOOKS).map((c, i) => {
      const map = new Map(c.map(b => [b.venue.instrument, b]))
      return {
        key: `okx${i}`, books: c, urls: ctx.route === 'gateway' ? [relay] : [OKX.wsPublic, relay],
        subscribe: () => okxSubscribe(c), decode: t => decodeOKX(t, map), ping: { text: 'ping', everyMs: 20_000 }, resubscribe: okxResubscribe,
      }
    })
  },
  klines30m(b, _now, slots) {
    const v = b.venue
    if (v.product !== 'spot' && v.product !== 'usdtPerp') return null
    const f = b.priceFactor
    return { url: `${OKX.rest}/api/v5/market/candles?instId=${encodeURIComponent(v.instrument)}&bar=30m&limit=${slots}`, parse: x => parseOkxCandles(x, f) }
  },
  market: okxMarket,
}
