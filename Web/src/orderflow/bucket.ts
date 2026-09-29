/* Hkline Web · 主力订单流 · 分桶（照 BucketScheme.swift）
 *
 * 桶是固定美元步长，价位落桶 = floor(价 / 步长)，离整数 1e-9 以内先吸到整数。
 * 网页版的梯子、热力在此之上再乘「周期倍数」和「合并倍数」，只影响展示，不影响大单判定。
 */

export class BucketScheme {
  static readonly derivedFraction = 0.001
  readonly step: number
  private constructor(step: number) { this.step = step }

  static make(step: number | undefined | null): BucketScheme | null {
    return step != null && Number.isFinite(step) && step > 0 ? new BucketScheme(step) : null
  }

  index(price: number): number { return bucketIndex(price, this.step) }
  low(index: number): number { return index * this.step }

  /** 收盘 × 0.1% 最接近的 0.5 / 1 / 2 / 5 / 10 × 10ⁿ，且不小于最小价格步长。 */
  static derivedStep(referenceClose: number, tick?: number | null): number | null {
    if (!Number.isFinite(referenceClose) || referenceClose <= 0) return null
    const target = referenceClose * BucketScheme.derivedFraction
    const decade = Math.pow(10, Math.floor(Math.log10(target)))
    let best = [0.5, 1, 2, 5, 10].map(x => x * decade).reduce((a, b) => (Math.abs(b - target) < Math.abs(a - target) ? b : a))
    if (tick != null && Number.isFinite(tick) && tick > 0 && best < tick) best = tick
    return Number.isFinite(best) && best > 0 ? best : null
  }

  /** 前一个 UTC 日的零点（毫秒）。 */
  static referenceDay(nowMs: number): number {
    const day = 86_400_000
    return Math.floor(nowMs / day) * day - day
  }
}

export function bucketIndex(price: number, step: number): number {
  const x = price / step
  const r = Math.round(x)
  const q = Math.abs(x - r) <= 1e-9 * Math.max(1, Math.abs(r)) ? r : Math.floor(x)
  return Number.isFinite(q) ? q : 0
}

/** 梯子 / 热力的「周期倍数」：1 分钟图一桶一行，1 小时 15 倍，日线 50 倍（设计稿 2.2）。 */
export function intervalMultiplier(iv: string): number {
  const m: Record<string, number> = {
    '1m': 1, '3m': 1, '5m': 2, '15m': 5, '30m': 10, '1h': 15, '2h': 20, '4h': 25, '6h': 30, '8h': 40, '12h': 50,
    '1d': 50, '1w': 100, '1M': 200,
  }
  return m[iv] ?? 1
}

/** 行高不到 6 px 时把桶按 2 / 5 / 10 倍合并（10 倍还不够就继续 20 / 50 / 100……）直到 ≥ 6 px。 */
export function mergeFactor(pxPerBucket: number, minPx = 6): number {
  if (!(pxPerBucket > 0) || !Number.isFinite(pxPerBucket)) return 1
  if (pxPerBucket >= minPx) return 1
  for (let decade = 1; decade < 1e9; decade *= 10) {
    for (const f of [2, 5, 10]) if (pxPerBucket * f * decade >= minPx) return f * decade
  }
  return 1
}
