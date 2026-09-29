/* Hkline Web · 主力订单流 · 聚合（梯子、盘口小部件、热力共用）
 *
 * 每本簿各自维护、各自分桶（VenueBook.buckets），这里把十几本簿按同一个步长加总成「细桶」，
 * 梯子再按「周期倍数 × 合并倍数」把细桶并成一行。只做加总与展示用的排序，不做任何判定。
 * 所有价格都已是图上的单位（1000PEPE 一格 = 1000 个币）。
 */
import type { BigOrder, BookSide, Product } from './types'
import { isContract, usdOf } from './types'
import type { OrderFlowModel } from './model'
import { bucketIndex } from './bucket'

export interface VenueMeta { id: string; exchange: string; label: string; product: Product; instrument: string }

/** 三家交易所在热力里的通道号（stride 3）。 */
export const EXCHANGE_CH: Record<string, number> = { binance: 0, okx: 1, coinbase: 2 }
export const EXCHANGE_NAMES = ['币安', 'OKX', 'Coinbase']

export const PRODUCT_SHORT: Record<Product, string> = { spot: '现货', usdtPerp: '永续', coinPerp: '币本位', delivery: '交割' }
export const exName = (e: string): string => EXCHANGE_NAMES[EXCHANGE_CH[e] ?? -1] ?? e
export const venueName = (label: string, p: Product): string => `${label}${PRODUCT_SHORT[p]}`

/** 一个细桶：各本簿在这一侧的美元名义（下标对齐 FineBook.venues）。 */
export interface FineCell { total: number; byVenue: Float64Array }

export interface FineBook {
  step: number
  asOfMs: number
  venues: VenueMeta[]
  bid: Map<number, FineCell>
  ask: Map<number, FineCell>
  /** 参考中间价：图上这只合约自己那本簿（币安 U 本位）；没有就取各本现货 / 永续中间价的中位数 */
  mid: number | null
  bestBid: number | null
  bestAsk: number | null
  ready: number
}

export function emptyFine(step: number, venues: VenueMeta[] = []): FineBook {
  return { step, asOfMs: 0, venues, bid: new Map(), ask: new Map(), mid: null, bestBid: null, bestAsk: null, ready: 0 }
}

/** 把模型里每本簿按 step 分桶再加总（radiusBps：各簿自己中间价两侧多远以内）。 */
export function buildFine(model: OrderFlowModel, radiusBps: number, nowMs: number, refInstrument?: string): FineBook | null {
  const scheme = model.scheme
  if (!scheme) return null
  const venues: VenueMeta[] = []
  const ids = model.venueIds
  for (const id of ids) {
    const v = model.books.get(id)!.venue
    venues.push({ id, exchange: v.exchange, label: v.label, product: v.product, instrument: v.instrument })
  }
  const out = emptyFine(scheme.step, venues)
  out.asOfMs = nowMs
  const n = venues.length
  const mids: number[] = []
  ids.forEach((id, vi) => {
    const b = model.books.get(id)!
    const map = b.buckets(scheme, radiusBps)
    if (!map) return
    out.ready++
    const m = b.mid()
    if (m != null) {
      const ref = refInstrument ? b.venue.instrument === refInstrument && b.venue.exchange === 'binance' : b.venue.product === 'usdtPerp' && b.venue.exchange === 'binance'
      if (ref) {
        out.mid = m
        out.bestBid = b.book.bids.bestPrice()
        out.bestAsk = b.book.asks.bestPrice()
      }
      if (b.venue.product !== 'delivery') mids.push(m)
    }
    for (const [k, v] of map) {
      const side = k[0] === 'b' ? out.bid : out.ask
      const idx = +k.slice(1)
      let c = side.get(idx)
      if (!c) { c = { total: 0, byVenue: new Float64Array(n) }; side.set(idx, c) }
      c.total += v.notional
      c.byVenue[vi] += v.notional
    }
  })
  if (out.mid == null && mids.length) {
    mids.sort((a, b) => a - b)
    out.mid = mids[mids.length >> 1]
  }
  return out
}

// ------------------------------------------------------------------ 梯子的一行

export interface LadderRow {
  /** 行号 = floor(细桶号 / k) */
  row: number
  low: number
  high: number
  bid: number
  ask: number
  /** 累计：买从最高买往下累、卖从最低卖往上累 */
  cumBid: number
  cumAsk: number
  /** 每本簿在这一行的买 / 卖（悬停卡片按交易所 × 产品拆） */
  bidBy: Float64Array
  askBy: Float64Array
  /** 这一行里还挂着的大单 */
  orders: BigOrder[]
}

/** 细桶号 → 行号（k 个细桶一行）。 */
export const rowOf = (idx: number, k: number): number => Math.floor(idx / k)

/** 把细桶按 k 并成行，只要 [lowRow, highRow] 以内的；累计量从盘口往外累，范围以外的也算进累计。 */
export function ladderRows(fine: FineBook, k: number, lowRow: number, highRow: number, live: BigOrder[]): Map<number, LadderRow> {
  const n = fine.venues.length
  const rows = new Map<number, LadderRow>()
  const get = (r: number): LadderRow => {
    let x = rows.get(r)
    if (!x) {
      x = { row: r, low: r * k * fine.step, high: (r + 1) * k * fine.step, bid: 0, ask: 0, cumBid: 0, cumAsk: 0, bidBy: new Float64Array(n), askBy: new Float64Array(n), orders: [] }
      rows.set(r, x)
    }
    return x
  }
  // 累计先在所有行上算（含范围外），再只留范围内的
  const bidRows = new Map<number, number>(), askRows = new Map<number, number>()
  for (const [idx, c] of fine.bid) { const r = rowOf(idx, k); bidRows.set(r, (bidRows.get(r) ?? 0) + c.total) }
  for (const [idx, c] of fine.ask) { const r = rowOf(idx, k); askRows.set(r, (askRows.get(r) ?? 0) + c.total) }
  const cumB = new Map<number, number>(), cumA = new Map<number, number>()
  let acc = 0
  for (const r of [...bidRows.keys()].sort((a, b) => b - a)) { acc += bidRows.get(r)!; cumB.set(r, acc) }
  acc = 0
  for (const r of [...askRows.keys()].sort((a, b) => a - b)) { acc += askRows.get(r)!; cumA.set(r, acc) }
  for (const [idx, c] of fine.bid) {
    const r = rowOf(idx, k); if (r < lowRow || r > highRow) continue
    const x = get(r); x.bid += c.total
    for (let i = 0; i < n; i++) x.bidBy[i] += c.byVenue[i]
  }
  for (const [idx, c] of fine.ask) {
    const r = rowOf(idx, k); if (r < lowRow || r > highRow) continue
    const x = get(r); x.ask += c.total
    for (let i = 0; i < n; i++) x.askBy[i] += c.byVenue[i]
  }
  // 累计量要连续：范围内没有挂单的行也要带上它外侧的累计
  const fill = (cum: Map<number, number>, down: boolean, set: (x: LadderRow, v: number) => void): void => {
    const keys = [...cum.keys()].sort((a, b) => (down ? b - a : a - b))
    if (!keys.length) return
    let j = 0, cur = 0
    const start = keys[0]
    if (down) {
      for (let r = Math.min(start, highRow); r >= lowRow; r--) {
        while (j < keys.length && keys[j] >= r) { cur = cum.get(keys[j])!; j++ }
        if (r <= start) set(get(r), cur)
      }
    } else {
      for (let r = Math.max(start, lowRow); r <= highRow; r++) {
        while (j < keys.length && keys[j] <= r) { cur = cum.get(keys[j])!; j++ }
        if (r >= start) set(get(r), cur)
      }
    }
  }
  fill(cumB, true, (x, v) => { x.cumBid = v })
  fill(cumA, false, (x, v) => { x.cumAsk = v })
  for (const o of live) {
    if (o.status !== 'live') continue
    const r = rowOf(o.bucket, k)
    if (r < lowRow || r > highRow) continue
    get(r).orders.push(o)
  }
  for (const x of rows.values()) x.orders.sort((a, b) => b.notional - a.notional)
  return rows
}

// ------------------------------------------------------------------ 盘口小部件

export interface Pressure { bps: number; bid: number; ask: number }

/** 各本簿在自己中间价 ±x 以内的买卖美元名义（交割有溢价，所以按各自的中间价）。 */
export function pressure(model: OrderFlowModel, bandsPct: number[]): { total: Pressure[]; byVenue: { meta: VenueMeta; bands: Pressure[] }[] } {
  const total = bandsPct.map(p => ({ bps: p * 100, bid: 0, ask: 0 }))
  const byVenue: { meta: VenueMeta; bands: Pressure[] }[] = []
  const maxF = Math.max(...bandsPct) / 100
  for (const id of model.venueIds) {
    const b = model.books.get(id)!
    const mid = b.mid()
    if (mid == null) continue
    const bands = bandsPct.map(p => ({ bps: p * 100, bid: 0, ask: 0 }))
    const nv = b.venue.notional
    b.book.scan(mid * (1 - maxF), mid * (1 + maxF), (side, p, q) => {
      const usd = usdOf(nv, p, q)
      if (!(usd > 0)) return
      const d = Math.abs(p - mid) / mid
      for (let i = 0; i < bandsPct.length; i++) {
        if (d > bandsPct[i] / 100) continue
        if (side === 'bid') { bands[i].bid += usd; total[i].bid += usd } else { bands[i].ask += usd; total[i].ask += usd }
      }
    })
    byVenue.push({ meta: { id, exchange: b.venue.exchange, label: b.venue.label, product: b.venue.product, instrument: b.venue.instrument }, bands })
  }
  return { total, byVenue }
}

export interface BookRow { price: number; usd: number; cum: number; qty: number }

/** 分档盘口：从参考中间价往外各 n 档（每档 step × k），只算现货与 U 本位 / 币本位永续（交割有溢价，会把盘口拉歪）。 */
export function steppedBook(fine: FineBook, k: number, n: number): { bids: BookRow[]; asks: BookRow[] } {
  const include = fine.venues.map(v => v.product !== 'delivery')
  const sum = (side: Map<number, FineCell>): Map<number, number> => {
    const m = new Map<number, number>()
    for (const [idx, c] of side) {
      let v = 0
      for (let i = 0; i < include.length; i++) if (include[i]) v += c.byVenue[i]
      if (v > 0) { const r = rowOf(idx, k); m.set(r, (m.get(r) ?? 0) + v) }
    }
    return m
  }
  const b = sum(fine.bid), a = sum(fine.ask)
  const rs = fine.step * k
  const mid = fine.mid ?? 0
  const top = (fine.bestBid ?? mid) || 0, bot = (fine.bestAsk ?? mid) || 0
  const bids: BookRow[] = [], asks: BookRow[] = []
  let cum = 0
  const b0 = bucketIndex(top, rs)
  for (let r = b0; r > b0 - n; r--) { const usd = b.get(r) ?? 0; cum += usd; const price = r * rs; bids.push({ price, usd, cum, qty: price > 0 ? usd / (price + rs / 2) : 0 }) }
  cum = 0
  const a0 = bucketIndex(bot, rs)
  for (let r = a0; r < a0 + n; r++) { const usd = a.get(r) ?? 0; cum += usd; const price = r * rs; asks.push({ price, usd, cum, qty: price > 0 ? usd / (price + rs / 2) : 0 }) }
  return { bids, asks }
}

// ------------------------------------------------------------------ 大单的展示字段

export function peakOf(o: BigOrder, peaks: Map<string, number>, id: string): number {
  const p = Math.max(o.initialNotional, o.notional, peaks.get(id) ?? 0)
  peaks.set(id, p)
  return p
}

export function outcomeText(o: BigOrder): string {
  switch (o.status) {
    case 'live': return '挂着'
    case 'filled': return '已成交'
    case 'cancelled': return o.filledNotional > 0 ? '部分成交后撤' : '已撤销'
    case 'lost': return '失联'
  }
}

export const sideText = (s: BookSide): string => (s === 'bid' ? '买' : '卖')
export const productText = (p: Product): string => PRODUCT_SHORT[p]
export const contractOf = isContract
