/* Hkline Web · 多交易所 · 各家适配器共用的件
 *
 * 这一层只认「交易所自己的报文与地址」；订单流（src/orderflow/**）只认这里导出的通用描述：
 * 一本簿（DepthBook）、一条连接的规格（ConnSpec）、REST 快照与 30 分钟 K 线的请求。
 * 价与量在解码时就乘上 priceFactor / quantityFactor 换成图上的单位（1000PEPE / kPEPE 一格是 1000 个币）。
 */
import type { BookLevel, BookSide, DepthMessage, Product, SequenceModel, Venue } from '../orderflow/types'

export type Route = 'direct' | 'gateway'

export interface DepthBook {
  id: string
  venue: Venue
  /** 本家价格 × priceFactor = 图上的价格 */
  priceFactor: number
  expiryMs: number | null
  tick: number | null
}
export const quantityFactor = (b: DepthBook): number => (b.venue.notional.kind === 'linear' ? 1 / b.priceFactor : 1)

/** 解出来的一条：[簿 id, 消息] */
export type Out = [string, DepthMessage]

export const n = (v: unknown): number => (typeof v === 'number' ? v : typeof v === 'string' ? parseFloat(v) : NaN)

/** [[价, 量], …] → 图上单位的档位 */
export function levels(raw: unknown, b: DepthBook): BookLevel[] {
  if (!Array.isArray(raw)) return []
  const pf = b.priceFactor, qf = quantityFactor(b)
  const out: BookLevel[] = []
  for (const r of raw as unknown[][]) {
    const p = n(r?.[0]), q = n(r?.[1])
    if (Number.isFinite(p) && Number.isFinite(q)) out.push({ price: p * pf, quantity: q * qf })
  }
  return out
}

export const trade = (b: DepthBook, price: number, qty: number, hit: BookSide, t: number): DepthMessage =>
  ({ type: 'trade', trade: { price: price * b.priceFactor, quantity: qty * quantityFactor(b), hitSide: hit, timeMs: t } })

export const chunk = <T>(a: T[], size: number): T[][] => { const o: T[][] = []; for (let i = 0; i < a.length; i += size) o.push(a.slice(i, i + size)); return o }

export const parseJSON = (text: string): Record<string, unknown> | null => {
  try { const v = JSON.parse(text) as unknown; return v && typeof v === 'object' ? v as Record<string, unknown> : null } catch { return null }
}

/** 一条连接：依次尝试 urls（还没打开就断了换下一个）；开了发 subscribe()，每帧过 decode。 */
export interface ConnSpec {
  key: string
  urls: string[]
  /** 这条连接负责的簿（开 / 断时通知它们）；只收成交的连接是空 */
  books: DepthBook[]
  subscribe: () => string[]
  decode: (text: string) => Out[]
  ping?: { text: string; everyMs: number }
  /** 多久没有任何帧当它死了重连（默认 30 秒） */
  silenceMs?: number
  /** 一本簿断档时只退订重订它（同连接其它簿不动）；没有就整条重连 */
  resubscribe?: (b: DepthBook) => string[]
}

export interface ConnContext {
  route: Route
  /** 网关的 WebSocket 根：wss://主机 */
  gw: string
}

/** 30 分钟 K 线一根（价已是图上单位；quote 是美元计价额，buy 是主动买计价额，K 线不带就是 null） */
export interface Kline { t: number; h: number; l: number; c: number; quote: number; buy: number | null }
export interface KlineReq { url: string; parse: (body: unknown) => Kline[] }

export interface SnapshotReq { url: string; parse: (json: unknown, b: DepthBook) => DepthMessage | null }

/** 保底簿（服务端品种表查不到时）：priceScale 是这本簿一单位是几个币（和品种表同一口径，priceFactor = 图的倍数 ÷ 它） */
export interface FallbackBook { product: Product; instrument: string; priceScale: number }

/** 一家交易所在注册表里登记的全部东西 */
export interface VenueAdapter {
  /** 稳定键（簿 id、品种表 exchange 字段） */
  key: string
  /** 显示名（读数分项、历史行的 exchange） */
  label: string
  /** 读数配色（CSS 变量） */
  color: string
  sequenceModel: (product: Product) => SequenceModel
  /** 快照在流里（不用另拉 REST） */
  snapshotInBand: boolean
  /** 一条连接最多装几本簿 */
  maxBooksPerConn: number
  /** 这家的簿该怎么分连接 */
  connections: (books: DepthBook[], ctx: ConnContext) => ConnSpec[]
  /** REST 快照（不在流里的才有） */
  snapshot?: (b: DepthBook, route: Route) => SnapshotReq
  /** 30 分钟 K 线（侧栏「24 小时成交」）；只给现货与 U 本位永续 */
  klines30m?: (b: DepthBook, now: number, slots: number) => KlineReq | null
  /** K 线带主动买额，能拆买卖 */
  takerSplit?: boolean
  /** 参考簿所在的家：图上那只合约自己（推步长的前一日收盘、中间价都以它为准） */
  primary?: { referenceCloseUrl: (symbol: string, day: number) => string; parseReferenceClose: (body: unknown, day: number) => number }
  /** 品种表查不到时的保底簿 */
  fallback?: (symbol: string, base: string, chartScale: number) => FallbackBook[]
}
