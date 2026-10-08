/* Hkline Web · 多交易所 · Hyperliquid 永续（行情 + 主力订单流，一家一个模块）
 *
 * 行情（2026-10-08，报文按 Hyperliquid 官方文档与 scratchpad 速查表写，容器连不上录不了真帧）：
 *   - REST 全是 POST /info（JSON body）：直连 api.hyperliquid.xyz（带 CORS），网关 POST /v1/market/raw/info?source=hyperliquid；
 *     限流器 5 次 / 秒（按 IP 1200 权重 / 分钟，info 一次 2–60）。
 *   - 品种表与整表行情是同一次 metaAndAssetCtxs（universe 与 ctxs 同序）：一个请求拿全价 / 额 / 标记价 / 持仓量 / 费率。
 *     计价 USDC；价格最多 5 位有效数字、小数位 ≤ 6 − szDecimals；isDelisted 的不收。
 *   - 网页键 hyperliquid/usd_m/<coin 大写>（kPEPE → KPEPE，和服务端 identity 一致）；发请求要用原名 kPEPE，
 *     由品种表在这里留一张「大写键 → 原名」的表译回（Sym.raw 也是原名）。kPEPE 这类 k 前缀一单位是 1000 个币。
 *   - 最新价用 midPx（没有就 markPx），涨跌幅相对 prevDayPx；资金费每小时一期，下次结算 = 下一个整点。
 *   - K 线 candleSnapshot（一次最多 5000 根，按起止时刻要）；成交量 v 是币，额 ≈ v × 收盘。没有 6 时，由 2 时并。
 *   - 推送 wss://api.hyperliquid.xyz/ws（网关 /v1/market/ws/hyperliquid）：candle / trades / activeAssetCtx，
 *     每 30 秒 {"method":"ping"}，回 {"channel":"pong"}。
 *
 * 订单流（snapshotOnly：没有序号，每帧整本替换；每侧 20 档滑动窗口）：
 *   恒走网关中继 /v1/market/ws/hyperliquid（服务端整个进程只开一条上游、按引用计数订退，浏览器不直连），
 *   一条最多 8 本（16 个订阅，中继上限）。只订 nSigFigs:4 那一档：4 位有效数字的网格永远 ≤ 步长且整除步长，
 *   直接落进现成的桶。心跳每 30 秒 {"method":"ping"}（回 {"channel":"pong"}）；订阅回执 subscriptionResponse 不理；
 *   60 秒没有任何帧断开重连；连上到第一帧之间簿算 bootstrapping。
 *   成交 side：B = 主动买 → hit ask，A = 主动卖 → hit bid。kPEPE 这类 k 前缀的一单位是 1000 个币（品种表给 priceScale 1000）。
 */
import type { BookLevel } from '../orderflow/types'
import type { Bar } from '../chart/calc'
import { registerGate } from '../market/limit'
import { apiOrigin } from '../market/origin'
import { keyOf, parseKey } from '../market/identity'
import { badgeColor, cnOf, type Sym } from '../market/symbols'
import { chunk, compact, n, num, parseJSON, quantityFactor, trade, type DepthBook, type Out, type Push, type Quote, type VenueAdapter, type VenueMarket } from './common'
import { shared, vpost } from './http'
import { sortBars } from './bars'
import { IV_MS } from '../util/format'

// ------------------------------------------------------------ 地址表（这一家唯一的一份）
export const HL = {
  id: 'hyperliquid',
  info: 'https://api.hyperliquid.xyz/info',
  ws: 'wss://api.hyperliquid.xyz/ws',
  relay: '/v1/market/ws/hyperliquid',
} as const
/** 这一家唯一的限流器（直连 / 网关各一道）。官方（Rate limits and user limits）：按 IP、**按权重**，1200 / 分钟；
 *  info 默认一次 20（meta、metaAndAssetCtxs、candleSnapshot、fundingHistory），candleSnapshot 另加「每返回 60 根 +1」，
 *  allMids、l2Book 一次 2。不能按次数算（每秒 5 次 = 每分钟 6000 权重，是上限的五倍）。
 *  这里取一半 600 权重 / 分钟（另一半留给同一出口的手机 app 与别的页）；candleSnapshot 按要的起止与周期估根数 */
export function hlWeight(_url: string, body?: unknown): number {
  const b = body as { type?: string; req?: { interval?: string; startTime?: number; endTime?: number } } | undefined
  if (b?.type === 'allMids' || b?.type === 'l2Book') return 2
  if (b?.type === 'candleSnapshot') {
    const r = b.req ?? {}, ms = IV_MS[Object.keys(HL_INTERVALS).find(k => HL_INTERVALS[k] === r.interval) ?? ''] ?? 0
    const n = ms > 0 && r.startTime != null ? Math.ceil(((r.endTime ?? Date.now()) - r.startTime) / ms) : 0
    return 20 + Math.ceil(Math.min(5000, Math.max(0, n)) / 60)
  }
  return 20
}
export const HL_GATE = registerGate(HL.id, {
  hosts: ['api.hyperliquid.xyz'], rules: [{ windowMs: 60_000, cap: 600 }], weight: hlWeight,
  gateway: url => url === HL.info ? `${apiOrigin()}/v1/market/raw/info?source=${HL.id}` : null,
})

/** 服务端 hyperliquid::symbol_ok：大写字母数字 1–16 */
export const hlSymbolOk = (s: string): boolean => /^[A-Z0-9]{1,16}$/.test(s)
/** HL 的 coin 原名 → 网页键（kPEPE → hyperliquid/usd_m/KPEPE） */
export const hlKeyOf = (coin: string): string => keyOf(HL.id, 'usd_m', coin.toUpperCase())
/** 大写键代号 → 原名（品种表到了才全；没到时按大写原样，BTC / ETH 这些本来就是大写） */
const names = new Map<string, string>()
export function hlCoin(key: string): string { const s = parseKey(key).symbol; return names.get(s) ?? s }

export const HL_INTERVALS: Record<string, string> = { '1m': '1m', '3m': '3m', '5m': '5m', '15m': '15m', '30m': '30m', '1h': '1h', '2h': '2h', '4h': '4h', '8h': '8h', '12h': '12h', '1d': '1d', '1w': '1w', '1M': '1M' }

// ------------------------------------------------------------ 报文解码
interface Universe { name: string; szDecimals?: number; isDelisted?: boolean }
type Ctx = Record<string, unknown>

/** k 前缀的千枚币（kPEPE）：搜索与徽标按 PEPE，图表头写原名 */
function baseOfCoin(name: string): string { return /^k[A-Z0-9]/.test(name) ? name.slice(1) : name.toUpperCase() }

/** metaAndAssetCtxs → 品种表（顺手记下大写键 → 原名） */
export function decodeHlUniverse(body: unknown): Sym[] {
  const meta = Array.isArray(body) ? body[0] as { universe?: Universe[] } : body as { universe?: Universe[] }
  const out: Sym[] = []
  for (const u of meta?.universe ?? []) {
    if (!u || typeof u.name !== 'string' || u.isDelisted || !/^[A-Za-z0-9]{1,16}$/.test(u.name)) continue
    names.set(u.name.toUpperCase(), u.name)
    const base = baseOfCoin(u.name)
    out.push({
      symbol: hlKeyOf(u.name), venue: HL.id, quote: 'USDC', raw: u.name, title: u.name, base, code: base, kind: 'crypto', cn: cnOf(base, 'crypto'),
      dec: Math.max(0, Math.min(8, 6 - (u.szDecimals ?? 0))), color: badgeColor(base),
      price: null, chg: 0, pct: null, vol: 0, fr: null, nextFunding: null,
    })
  }
  return out
}

/** 下一个整点（资金费每小时一期） */
export const nextHour = (now: number): number => Math.floor(now / 36e5) * 36e5 + 36e5

/** 一只的上下文（metaAndAssetCtxs 的一项、推送 activeAssetCtx 的 ctx）→ 行情 */
export function decodeHlCtx(coin: string, c: Ctx, at: number): Quote | null {
  const mark = num(c.markPx), mid = num(c.midPx), prev = num(c.prevDayPx)
  const price = mid ?? mark
  if (price == null) return null
  return compact<Quote>({
    key: hlKeyOf(coin), price, open: prev, pct: prev ? (price / prev - 1) * 100 : undefined, chg: prev != null ? price - prev : undefined,
    vol: num(c.dayNtlVlm), mark, index: num(c.oraclePx), fr: num(c.funding) ?? null, nextFunding: nextHour(at), oi: num(c.openInterest), at,
  })
}
export function decodeHlCtxs(body: unknown, now = Date.now()): Quote[] {
  if (!Array.isArray(body)) return []
  const uni = (body[0] as { universe?: Universe[] })?.universe ?? [], ctxs = Array.isArray(body[1]) ? body[1] as Ctx[] : []
  const out: Quote[] = []
  uni.forEach((u, i) => { if (u && !u.isDelisted && ctxs[i]) { const q = decodeHlCtx(u.name, ctxs[i], now); if (q) out.push(q) } })
  return out
}

/** K 线 [{t, T, s, i, o, h, l, c, v(币), n}] → 升序；额 ≈ 量 × 收盘 */
export function decodeHlCandle(k: Record<string, unknown>): Bar | null {
  const t = num(k.t), c = num(k.c)
  if (t == null || c == null) return null
  const v = num(k.v) ?? 0
  return { t, o: num(k.o) ?? c, h: num(k.h) ?? c, l: num(k.l) ?? c, c, v: v * c, bv: v }
}
export function decodeHlCandles(body: unknown): Bar[] {
  return sortBars((Array.isArray(body) ? body as Record<string, unknown>[] : []).map(decodeHlCandle).filter((b): b is Bar => !!b))
}

/** 推送一帧 → 统一事件（candle / trades / activeAssetCtx）；pong、subscriptionResponse、error 回空 */
export function decodeHlPush(text: string): Push[] {
  const r = parseJSON(text)
  if (!r) return []
  if (r.channel === 'candle') {
    const d = r.data as Record<string, unknown> | undefined
    const b = d ? decodeHlCandle(d) : null
    if (!b || typeof d!.s !== 'string' || typeof d!.i !== 'string' || !HL_INTERVALS[d!.i as string]) return []
    return [{ type: 'kline', key: hlKeyOf(d!.s as string), iv: d!.i as string, bar: b }]
  }
  if (r.channel === 'trades') {
    const out: Push[] = []
    for (const x of (Array.isArray(r.data) ? r.data : []) as Record<string, unknown>[]) {
      const p = num(x.px), q = num(x.sz)
      if (typeof x.coin !== 'string' || p == null || q == null) continue
      out.push({ type: 'trade', key: hlKeyOf(x.coin), price: p, qty: q, t: num(x.time) ?? Date.now(), sell: x.side === 'A' })
    }
    return out
  }
  if (r.channel === 'activeAssetCtx') {
    const d = r.data as { coin?: unknown; ctx?: Ctx } | undefined
    if (typeof d?.coin !== 'string' || !d.ctx) return []
    const q = decodeHlCtx(d.coin, d.ctx, Date.now())
    return q ? [{ type: 'quote', quote: q }] : []
  }
  return []
}

// ------------------------------------------------------------ 行情面
const ctxs = (route?: 'direct' | 'gateway') => shared(`hl:ctx:${route ?? ''}`, () => vpost<unknown>(HL.info, { type: 'metaAndAssetCtxs' }, { ms: 12_000, route }))
/** 发请求前要原名：表没到过就先取一次（和品种表共用在途的那一次） */
async function coinOf(key: string): Promise<string> {
  if (!names.size) { try { decodeHlUniverse(await ctxs()) } catch { /* 取不到就按大写原样 */ } }
  return hlCoin(key)
}

export const hlMarket: VenueMarket = {
  shortName: 'HL', displayName: 'Hyperliquid', market: 'usd_m', quote: 'USDC',
  symbolOk: hlSymbolOk,
  instruments: async route => decodeHlUniverse(await ctxs(route)),
  tickers: async route => decodeHlCtxs(await ctxs(route)),
  maxKlines: 5000,
  async klines(key, iv, q, opts) {
    const interval = HL_INTERVALS[iv]
    if (!interval) return []
    const ms = IV_MS[iv], limit = Math.min(5000, q.limit)
    const now = Date.now()
    let start: number, end: number
    if (q.start != null) { start = q.start; end = Math.min(now, q.start + limit * ms) }
    else { end = q.end != null ? q.end - 1 : now; start = end - limit * ms }
    const bars = decodeHlCandles(await vpost(HL.info, { type: 'candleSnapshot', req: { coin: await coinOf(key), interval, startTime: Math.max(0, Math.floor(start)), endTime: Math.floor(end) } }, opts))
    return q.end != null ? bars.filter(b => b.t < q.end!) : bars
  },
  intervals: { native: HL_INTERVALS, derived: { '6h': '2h' } },
  stream: {
    endpoint: sub => sub.kind === 'kline' && !HL_INTERVALS[sub.iv ?? ''] ? null : 'main',
    url: (_ep, route, gw) => route === 'gateway' ? `${gw}${HL.relay}` : HL.ws,
    topics(sub) {
      const c = hlCoin(sub.key)
      if (sub.kind === 'kline') return [`candle|${c}|${HL_INTERVALS[sub.iv ?? '']}`]
      if (sub.kind === 'trade') return [`trades|${c}`]
      return [`activeAssetCtx|${c}`]   // 行情与标记价共用
    },
    frames: (_ep, topics, on) => topics.map(t => {
      const [type, coin, interval] = t.split('|')
      return JSON.stringify({ method: on ? 'subscribe' : 'unsubscribe', subscription: interval ? { type, coin, interval } : { type, coin } })
    }),
    decoder: () => decodeHlPush,
    ping: { text: JSON.stringify({ method: 'ping' }), everyMs: 30_000 },
    silenceMs: 60_000,
    maxTopics: 32,
    // 官方：每 IP ≤ 10 条连接（这里一条）、每分钟 ≤ 2000 条上行（这里每 250 ms 一条 = 240 条 / 分钟）
    controlGapMs: 250,
  },
}

// ------------------------------------------------------------ 订单流
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
      key: `hyperliquid${i}`, books: c, urls: [`${ctx.gw}${HL.relay}`],
      subscribe: () => hlSubscribe(c), decode: (t: string) => decodeHyperliquid(t, map),
      ping: { text: JSON.stringify({ method: 'ping' }), everyMs: 30_000 }, silenceMs: HL_SILENCE_MS, resubscribe: hlResubscribe,
    }
  }),
  // k 前缀 = 1000 个币一单位
  fallback: (_symbol, base, chartScale) => [chartScale >= 1000 ? { product: 'usdtPerp', instrument: 'k' + base, priceScale: 1000 } : { product: 'usdtPerp', instrument: base, priceScale: 1 }],
  market: hlMarket,
}
