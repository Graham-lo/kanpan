/* Hkline Web · 主力订单流 · 梯子上的成交（OpenMarket 通读 P1-3，纯逻辑）
 *
 * 三家逐笔合流按细桶累加「主动买 / 主动卖」的美元额，从打开这只品种起算、换品种（或步长变了）清零。
 * 梯子按它当前的行（k 个细桶一行）再并一次：中列画净额（买 − 卖），两侧深度柱外沿各一条淡色细条画买 / 卖。
 * 只累加，不判定。
 */
import { bucketIndex } from './bucket'
import { rowOf } from './aggregate'

export interface TradeRow { buy: number; sell: number }

export class TradeLadder {
  /** 细桶号 → 主动买 / 主动卖（美元） */
  private buy = new Map<number, number>()
  private sell = new Map<number, number>()
  /** 从什么时候起算（第一笔进来的时刻；清零后重新起算） */
  since: number | null = null
  step = 0
  version = 0

  /** 进一笔（价格是图上的单位）；步长变了就清零重来。 */
  add(price: number, usd: number, side: 'buy' | 'sell', step: number, t: number): void {
    if (!(step > 0) || !(price > 0) || !(usd > 0)) return
    if (step !== this.step) { this.clear(); this.step = step }
    if (this.since == null) this.since = t
    const i = bucketIndex(price, step)
    const m = side === 'buy' ? this.buy : this.sell
    m.set(i, (m.get(i) ?? 0) + usd)
    this.version++
  }

  /** 把细桶并成梯子的行（只要 [lowRow, highRow] 里的）。 */
  rows(k: number, lowRow: number, highRow: number): Map<number, TradeRow> {
    const out = new Map<number, TradeRow>()
    const put = (m: Map<number, number>, buy: boolean): void => {
      for (const [i, v] of m) {
        const r = rowOf(i, k)
        if (r < lowRow || r > highRow) continue
        let x = out.get(r)
        if (!x) { x = { buy: 0, sell: 0 }; out.set(r, x) }
        if (buy) x.buy += v; else x.sell += v
      }
    }
    put(this.buy, true); put(this.sell, false)
    return out
  }

  get size(): number { return this.buy.size + this.sell.size }

  clear(): void { this.buy.clear(); this.sell.clear(); this.since = null; this.version++ }
}

/** 净差占比：(买 − 卖) ÷ (买 + 卖) × 100；都为 0 给 null。 */
export function deltaPct(r: TradeRow): number | null {
  const s = r.buy + r.sell
  return s > 0 ? (r.buy - r.sell) / s * 100 : null
}

/** 距中间价的百分比（带符号）。 */
export function fromMidPct(price: number, mid: number | null): number | null {
  return mid != null && mid > 0 ? (price - mid) / mid * 100 : null
}

/** 带符号的百分比文字：+0.42% / −1.3%（两位有效的小数，|x| ≥ 10 一位） */
export function signedPct(x: number | null, dec?: number): string {
  if (x == null || !Number.isFinite(x)) return '—'
  const d = dec ?? (Math.abs(x) >= 10 ? 1 : 2)
  const s = Math.abs(x).toFixed(d)
  return (x > 0 && +s > 0 ? '+' : x < 0 && +s > 0 ? '−' : '') + s + '%'
}
