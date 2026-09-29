/* Hkline Web · 主力订单流 · 共用类型
 *
 * 逐项对照 KanpanCore/Sources/KanpanCore/OrderFlow/（OrderFlowVenue.swift、LocalBook.swift、OrderFlowModel.swift）。
 * 规则一律照手机端，不在网页版另起一套；网页版只换展示。
 */

export type BookSide = 'bid' | 'ask'
export type Product = 'spot' | 'usdtPerp' | 'coinPerp' | 'delivery'
export const PRODUCTS: Product[] = ['spot', 'usdtPerp', 'coinPerp', 'delivery']
export const isContract = (p: Product): boolean => p !== 'spot'

/** 一档挂单的数量怎么换成美元名义（USDT / USDC / USD 都按 1 美元算）。 */
export type Notional =
  | { kind: 'linear'; multiplier: number }
  | { kind: 'inverse'; contractUsd: number }

export function usdOf(n: Notional, price: number, quantity: number): number {
  const v = n.kind === 'linear' ? price * quantity * n.multiplier : quantity * n.contractUsd
  return Number.isFinite(v) && v > 0 ? v : 0
}

export type SequenceModel = 'rangeOverlap' | 'previousFinalOverlap' | 'previousFinalExact' | 'strictIncrementing'

/** 一本簿：交易所 × 产品 × 合约。 */
export interface Venue {
  /** binance / okx / coinbase */
  exchange: string
  /** 「币安」「OKX」「Coinbase」 */
  label: string
  product: Product
  instrument: string
  notional: Notional
  sequenceModel: SequenceModel
  /** 快照在流里（OKX、Coinbase）；false 要另拉 REST 快照（币安） */
  snapshotInBand: boolean
}
export const venueId = (v: Pick<Venue, 'exchange' | 'product' | 'instrument'>): string => `${v.exchange}:${v.product}:${v.instrument}`

export interface BookLevel { price: number; quantity: number }

export interface BookSnapshot {
  lastUpdateID: number
  requestedLevels: number
  bids: BookLevel[]
  asks: BookLevel[]
  eventTimeMs?: number
  connection: number
  slidingWindow: boolean
}

export interface BookDelta {
  firstUpdateID: number
  finalUpdateID: number
  previousFinalUpdateID: number | null
  bids: BookLevel[]
  asks: BookLevel[]
  eventTimeMs: number
  connection: number
}

export interface Trade { price: number; quantity: number; hitSide: BookSide; timeMs: number }

export type DepthMessage =
  | { type: 'snapshot'; snapshot: BookSnapshot }
  | { type: 'delta'; delta: BookDelta }
  | { type: 'trade'; trade: Trade }
  | { type: 'reset' }

export type Action = 'none' | 'fetchSnapshot' | 'resubscribe'

export type Status = 'live' | 'filled' | 'cancelled' | 'lost'

/** 一条大单（字段与服务端 /v1/market/orderflow/history 的行同名）。 */
export interface BigOrder {
  venueID: string
  exchange: string
  product: Product
  side: BookSide
  bucket: number
  price: number
  firstSeenMs: number
  endMs: number | null
  status: Status
  initialNotional: number
  notional: number
  filledNotional: number
  threshold: number
  vanishedNotional: number | null
}

export const orderId = (o: Pick<BigOrder, 'venueID' | 'side' | 'bucket' | 'firstSeenMs'>): string =>
  `${o.venueID}|${o.side}|${o.bucket}|${o.firstSeenMs}`

export function fillRatio(o: BigOrder): number {
  const base = o.status === 'live' ? o.notional : (o.vanishedNotional ?? o.notional)
  return base > 0 ? Math.min(1, Math.max(0, o.filledNotional / base)) : 0
}

/** 一只 base 此刻生效的门槛与步长；某产品为 undefined = 不订这种产品。 */
export interface Thresholds {
  spot?: number
  usdtPerp?: number
  coinPerp?: number
  delivery?: number
  step?: number
}
