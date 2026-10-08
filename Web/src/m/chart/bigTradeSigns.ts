/* Hkline 手机网页 · 图上大单与爆仓气泡：纯几何与命中（2026-10-08 二稿，规格 docs/design/大单爆仓气泡-三端规格-2026-10-08.md）
 *
 * 只管「一根 → 画不画、画成点还是泡、画在哪」，不碰画布、不碰数据源：数据（每根向上 U = 大买 + 空爆、向下 D = 大卖 + 多爆，
 * 两级金额线）由 bigTradeLayer.ts 的 bigTradeSource() 给（底下是 orderflow/bigTags.ts 的 BigBarCache / LevelCache 与
 * orderflow/liquidation.ts 的 LiqBarCache），画法在 bigTradeLayer.ts。
 *
 * 摆放与电脑网页同一个函数（orderflow/bigTags.ts 的 planBubbles，原型 one()），iOS KanpanChart/BigTradeSigns.swift 照同一份规格：
 *   · 一根上下各至多一枚：U 挂最高价之上（涨色）、D 挂最低价之下（跌色）；点线 P90 到泡线 P97 之间画小圆点，过泡线画带字的泡；
 *   · 一屏带字的泡最多 6 枚（金额大的先占位），一根宽不到 4 一律只画点；同侧挨上了往外推一层，推出窗格就退成点；
 *   · 能落的竖直范围从图例带（主图顶上 24，或图例实际占的更高）以下到主图底；泡躲开画线上的字。
 *   · 命中：只有泡，44 × 44（以圆心为心，泡大于 44 时按泡）；几枚都中取圆心离手指最近的。小圆点不响应、不进读屏按钮。
 */
import { planBubbles, type Bubble, type BubbleIn, type Levels, type Rect } from '../../orderflow/bigTags'
import { BT, fill } from '../../terms'

/** 尺寸（pt），与 iOS 同值 */
export const SIGN = {
  /** 主图顶上留给图例的一带 */
  legendBand: 24,
  /** 命中区边长 */
  hit: 44,
  /** 点中放大倍数与时长 */
  pop: 1.3,
  popMs: 120,
  /** 新大单光环外扩多少、多久；减少动效时改成闪一下 */
  ring: 8,
  ringMs: 600,
  flashMs: 150,
} as const

/** 一根的输入（与电脑网页同一个形状）：x = 根中心，yHigh / yLow = 高 / 低点的纵坐标，up / down = U / D */
export type SignBar = BubbleIn
/** 一枚气泡（或小圆点）：bubble = true 才是带字的泡 */
export type Sign = Bubble

export interface SignEnv {
  levels: Levels | null
  /** 一根 K 线宽 */
  spacing: number
  /** 能落的竖直范围（图例带以下到主图底）与主图宽 */
  top: number
  bottom: number
  plotW: number
  /** 不许压的：画线上的字 */
  avoid: readonly Rect[]
  /** 量泡里的字宽（11 / 600、等宽数字） */
  measure: (text: string) => number
  /** 金额短写（1.2M / 860K），泡里再去掉末尾的 M */
  fmt: (usd: number) => string
}

/** 排一屏：返回按根序（同根上侧在前） */
export function planSigns(bars: readonly SignBar[], env: SignEnv): Sign[] {
  return planBubbles(bars, {
    levels: env.levels, bw: env.spacing, top: env.top, bottom: env.bottom, plotW: env.plotW,
    avoid: env.avoid, measure: env.measure, text: env.fmt,
  })
}

/** 命中框：以圆心为心 44 × 44，泡比 44 大时按泡的外接方 */
export function hitBox(s: Pick<Sign, 'x' | 'cy' | 'r'>): Rect {
  const w = Math.max(SIGN.hit, s.r * 2)
  return { x: s.x - w / 2, y: s.cy - w / 2, w, h: w }
}

/** 手指落在 (x, y)：命中框里的泡取圆心最近的那枚；小圆点不算 */
export function hitSign(signs: readonly Sign[], x: number, y: number): Sign | null {
  let best: Sign | null = null, bd = Infinity
  for (const s of signs) {
    if (!s.bubble) continue
    const b = hitBox(s)
    if (x < b.x || x > b.x + b.w || y < b.y || y > b.y + b.h) continue
    const d = Math.hypot(x - s.x, y - s.cy)
    if (d < bd) { best = s; bd = d }
  }
  return best
}

/** 读屏：「12:30 向上 1.2M」（用词在 terms.json：signA11y / up / down） */
export function signLabel(s: Pick<Sign, 'side' | 'usd'>, fmt: (usd: number) => string, when: string): string {
  return fill(BT.signA11y, { t: when, side: s.side === 'up' ? BT.up : BT.down, v: fmt(s.usd) })
}
