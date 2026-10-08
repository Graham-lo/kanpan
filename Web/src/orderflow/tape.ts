/* Hkline Web · 主力订单流 · 合并成交
 *
 * 各家所有簿的逐笔合成一条带：同一家、同一方向、同一价位 1 秒以内的并成一行；
 * 过滤看并完的金额（默认门槛 ÷ 50），门槛 ÷ 5 以上加粗。
 * 2026-10-08 起图上不再按逐笔打点：点只活在内存里，空闲停流 / 换品种 / 刷新一清就没（「下一根就没了」），
 * 改成每根 K 线上下各至多一枚大单与爆仓气泡，数据走 tradeFlow 的分钟桶 + 服务端历史（见 bigTags.ts）。
 * 每行带一个 bps：这一笔相对同一家同一产品上一笔的价格变化（OpenMarket 通读 P1-6），|bps| < 0.5 不显示。
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
  /** 相对同一家同一产品上一笔的价格变化（万分之一）；这一家的第一笔为 null */
  bps: number | null
}

export const TAPE_CAP = 3000
export const MERGE_MS = 1000

/** 用哪个门槛当「门槛」：U 本位永续，没有就现货，再没有就最小的那个。 */
export function tapeBase(t: { spot?: number; usdtPerp?: number; coinPerp?: number; delivery?: number }): number | null {
  const v = t.usdtPerp ?? t.spot ?? Math.min(...[t.coinPerp, t.delivery].filter((x): x is number => x != null))
  return Number.isFinite(v) && v > 0 ? v : null
}

export class Tape {
  rows: TapeRow[] = []
  version = 0
  private open = new Map<string, TapeRow>()
  /** 每本簿（交易所 × 产品 × 合约）上一笔的价格（算 bps 用；交割几期各算各的） */
  private lastPx = new Map<string, number>()

  /** 进一笔；返回是否新开了一行。 */
  push(e: { t: number; exchange: string; label: string; product: Product; side: 'buy' | 'sell'; price: number; usd: number; qty: number; instrument?: string }): TapeRow {
    const key = `${e.exchange}|${e.product}|${e.side}|${e.price}`
    const vk = `${e.exchange}|${e.product}|${e.instrument ?? ''}`
    const prev = this.lastPx.get(vk)
    this.lastPx.set(vk, e.price)
    const r = this.open.get(key)
    if (r && e.t - r.last <= MERGE_MS && e.t >= r.last - MERGE_MS) {
      r.usd += e.usd; r.qty += e.qty; r.n++; r.last = Math.max(r.last, e.t)
      this.version++
      return r
    }
    const row: TapeRow = { t: e.t, last: e.t, exchange: e.exchange, label: e.label, product: e.product, side: e.side, price: e.price, usd: e.usd, qty: e.qty, n: 1, bps: bpsOf(e.price, prev) }
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

  /** 最新在前、金额 ≥ min 的行（最多 limit 行）。 */
  visible(min: number, limit: number): TapeRow[] {
    const out: TapeRow[] = []
    for (let i = this.rows.length - 1; i >= 0 && out.length < limit; i--) if (this.rows[i].usd >= min) out.push(this.rows[i])
    return out
  }

  clear(): void { this.rows = []; this.open.clear(); this.lastPx.clear(); this.version++ }
}

/** 价格变化（万分之一）：上一笔没有给 null */
export function bpsOf(price: number, prev: number | undefined): number | null {
  return prev != null && prev > 0 && price > 0 ? (price - prev) / prev * 1e4 : null
}
/** bps 小标的字：|bps| < 0.5 不显示（null）；一位小数、带符号 */
export function bpsText(bps: number | null): string | null {
  if (bps == null || !Number.isFinite(bps) || Math.abs(bps) < 0.5) return null
  const a = Math.abs(bps)
  return (bps > 0 ? '+' : '−') + (a >= 100 ? a.toFixed(0) : a.toFixed(1))
}

export const TAPE_ROW_SMALL = 20
export const TAPE_ROW_BIG = 28
/** 行高：金额 ≥ 门槛 ÷ 5（大额成交）的长高到 28 */
export const tapeRowH = (usd: number, big: number): number => (big > 0 && usd >= big ? TAPE_ROW_BIG : TAPE_ROW_SMALL)
/** 行底色浓度 = clamp(金额 ÷ 门槛, 0.04, 0.35) */
export const tapeRowAlpha = (usd: number, base: number): number => (base > 0 ? Math.min(0.35, Math.max(0.04, usd / base)) : 0.04)
