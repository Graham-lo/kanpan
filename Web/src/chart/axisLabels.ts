/* Hkline Web · 价格轴标签让位（照 TradingView 的价格轴：标签排成不重叠的一列）
 *
 * 价格轴上同一窗格里的几枚标签（最新价、提醒价、对比线、主图均线 / 副图 MACD、RSI 当前值、最高最低价……）
 * 竖向上撞在一起时，按优先级从高到低一枚一枚摆：先摆的占住自己的真实位置，后摆的找「离自己真实位置最近」
 * 且不和已摆的重叠的空位（推开距离 = 刚好不重叠 + 1 px）。推开超过自身高度 1.5 倍仍放不下的，这一枚不画。
 * 被推开的标签仍是原价位的读数——只挪位置，不画引线。
 * 最新价给最高优先级：它第一个摆，永远完整、不挪（只按窗格上下沿夹住，和原来一样）。
 */

export interface AxisLabel {
  /** 标签想放的中心 y（就是它代表的那个价位在画布上的 y） */
  y: number
  /** 标签高 */
  h: number
  /** 优先级：大的先摆、挤不下时最后被丢；同优先级按传入顺序 */
  priority: number
}

/** 两枚标签之间至少留的空隙（px） */
export const AXIS_LABEL_GAP = 1
/** 最多推开自身高度的几倍；再远就不画 */
export const AXIS_LABEL_MAX_PUSH = 1.5

/**
 * 把一列标签排成不重叠的一列。返回每枚标签实际的中心 y（与传入顺序一一对应），放不下的是 null。
 * top / bottom = 这一列能用的竖向范围（窗格上下沿），标签整枚不出这个范围。
 */
export function layoutAxisLabels(labels: readonly AxisLabel[], top: number, bottom: number): (number | null)[] {
  const out: (number | null)[] = labels.map(() => null)
  const order = labels.map((_, i) => i).sort((a, b) => labels[b].priority - labels[a].priority || a - b)
  const placed: { a: number; b: number }[] = [] // 已摆的标签占的 [上沿, 下沿]
  const EPS = 1e-6
  const free = (t: number, h: number): boolean => placed.every(q => t + h + AXIS_LABEL_GAP <= q.a + EPS || t >= q.b + AXIS_LABEL_GAP - EPS)
  for (const i of order) {
    const { y, h } = labels[i]
    if (!Number.isFinite(y) || !(h > 0)) continue
    const lo = top, hi = bottom - h
    if (hi < lo - EPS) continue // 窗格比标签还矮
    const want = Math.min(Math.max(y - h / 2, lo), hi)
    // 候选：自己的位置；挪的话只会挪到紧贴某枚已摆标签的上方或下方
    const cands = free(want, h) ? [want] : placed.flatMap(q => [q.a - AXIS_LABEL_GAP - h, q.b + AXIS_LABEL_GAP])
    let best = NaN, bd = Infinity
    for (const t of cands) {
      if (t < lo - EPS || t > hi + EPS || !free(t, h)) continue
      const d = Math.abs(t - want)
      if (d < bd - EPS) { bd = d; best = t }
    }
    if (!Number.isFinite(best) || bd > AXIS_LABEL_MAX_PUSH * h + EPS) continue
    placed.push({ a: best, b: best + h })
    out[i] = best + h / 2
  }
  return out
}
