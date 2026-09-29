/* Hkline Web · 主力订单流 · 合并成交
 *
 * 三家所有簿的逐笔合成一条带：同一家、同一方向、同一价位 1 秒以内的并成一行；
 * 过滤看并完的金额（默认门槛 ÷ 50），门槛 ÷ 5 以上加粗并在图上打点（点留 2 小时）。
 */
import type { Product } from './types'

export interface TapeRow {
  t: number
  /** 最后一笔的时刻（1 秒合并窗口从这里算） */
  last: number
  exchange: string
  label: string
  product: Product
  /** buy = 主动买（吃卖单）；sell = 主动卖 */
  side: 'buy' | 'sell'
  price: number
  usd: number
  qty: number
  n: number
}

export interface TradeDot { t: number; price: number; usd: number; side: 'buy' | 'sell'; exchange: string; label: string; product: Product }

export const TAPE_CAP = 3000
export const DOT_KEEP_MS = 2 * 3_600_000
export const DOT_CAP = 4000
export const MERGE_MS = 1000

/** 用哪个门槛当「门槛」：U 本位永续，没有就现货，再没有就最小的那个。 */
export function tapeBase(t: { spot?: number; usdtPerp?: number; coinPerp?: number; delivery?: number }): number | null {
  const v = t.usdtPerp ?? t.spot ?? Math.min(...[t.coinPerp, t.delivery].filter((x): x is number => x != null))
  return Number.isFinite(v) && v > 0 ? v : null
}

export class Tape {
  rows: TapeRow[] = []
  dots: TradeDot[] = []
  version = 0
  private open = new Map<string, TapeRow>()

  /** 进一笔；返回是否新开了一行。 */
  push(e: { t: number; exchange: string; label: string; product: Product; side: 'buy' | 'sell'; price: number; usd: number; qty: number }): TapeRow {
    const key = `${e.exchange}|${e.product}|${e.side}|${e.price}`
    const r = this.open.get(key)
    if (r && e.t - r.last <= MERGE_MS && e.t >= r.last - MERGE_MS) {
      r.usd += e.usd; r.qty += e.qty; r.n++; r.last = Math.max(r.last, e.t)
      this.version++
      return r
    }
    const row: TapeRow = { t: e.t, last: e.t, exchange: e.exchange, label: e.label, product: e.product, side: e.side, price: e.price, usd: e.usd, qty: e.qty, n: 1 }
    this.rows.push(row)
    this.open.set(key, row)
    if (this.rows.length > TAPE_CAP * 1.2) {
      const drop = this.rows.splice(0, this.rows.length - TAPE_CAP)
      for (const d of drop) {
        const k = `${d.exchange}|${d.product}|${d.side}|${d.price}`
        if (this.open.get(k) === d) this.open.delete(k)
      }
    }
    if (this.open.size > 2000) for (const [k, v] of this.open) if (e.t - v.last > MERGE_MS) this.open.delete(k)
    this.version++
    return row
  }

  /** 行并完之后够大就在图上打点（同一行只打一个，金额跟着长）。 */
  dotFor(row: TapeRow, big: number): void {
    if (!(row.usd >= big)) return
    for (let i = this.dots.length - 1; i >= Math.max(0, this.dots.length - 64); i--) {
      const d = this.dots[i]
      if (d.t === row.t && d.price === row.price && d.exchange === row.exchange && d.side === row.side && d.product === row.product) { d.usd = row.usd; return }
    }
    this.dots.push({ t: row.t, price: row.price, usd: row.usd, side: row.side, exchange: row.exchange, label: row.label, product: row.product })
  }

  prune(now: number): void {
    const cut = now - DOT_KEEP_MS
    let i = 0
    while (i < this.dots.length && this.dots[i].t < cut) i++
    if (i) this.dots.splice(0, i)
    if (this.dots.length > DOT_CAP) this.dots.splice(0, this.dots.length - DOT_CAP)
  }

  /** 最新在前、金额 ≥ min 的行（最多 limit 行）。 */
  visible(min: number, limit: number): TapeRow[] {
    const out: TapeRow[] = []
    for (let i = this.rows.length - 1; i >= 0 && out.length < limit; i--) if (this.rows[i].usd >= min) out.push(this.rows[i])
    return out
  }

  clear(): void { this.rows = []; this.dots = []; this.open.clear(); this.version++ }
}
