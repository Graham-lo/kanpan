/* Hkline Web · 主力订单流 · 出帧节奏（照 iOS OrderFlowFeed：amountRefreshMs / heartbeatMs / samePixels）
 *
 * feed 每 500 ms 评估一轮，模型原地改每一单的 notional / filledNotional。原来每一轮都原样交给图表，色块上的金额签、
 * 图例「主力 买 12.3M」、抽屉里的列表每半秒就换一个数——簿上的挂单量本来就一拍一个样，看着像出错的数据
 * （用户 2026-10-07：「数字变化的非常快，有点像出错的数据」）。这里把金额按住：
 * - 画面没变（同一批单子、状态 / 价格 / 成交格都一样）、金额也没变 → 不出帧；
 * - 画面没变、只是金额在抖 → 金额（连带色块厚度、墙的均价）按上一次交出去的那份，每 5 秒才换一次。厚度不进「画面变了」的判定：
 *   BTC 一帧三百来条活单，哪怕按门槛 1/4 一档比，每拍总有几条跨档，等于每拍都发、金额照样跳（10-07 Chromium 实测
 *   20 秒 40 拍发了 39 拍）；厚度本来就是金额画出来的样子，和金额一起 5 秒换一次才稳。墙的均价（同一桶里按量加权）
 *   也一样：桶才是身份，均价随挂单量每拍动几块钱，图上色块的中线、抽屉里的价签跟着抖，所以和金额一起按住；
 * - 画面变了（有单出现 / 消失 / 换状态 / 成交格变）→ 立刻出帧，但其余画面没变的活单金额仍按住，到 5 秒一起刷；
 * - 十字线停在色块上要精确读数时（precise）逐拍发，不按住；
 * - 内容完全没变也至少 30 秒出一次（图上「12 分」这类随时间走的要跟上）。
 */
import type { BigOrder } from './types'
import { fillRatio, orderId } from './types'
import type { Snapshot } from './model'
import { ago } from '../util/clock'

/** 画出来一样、只是金额变了的帧最快隔这么久发一次 */
export const AMOUNT_REFRESH_MS = 5_000
/** 内容没变时至少隔这么久也发一次 */
export const HEARTBEAT_MS = 30_000
/** 成交格（20 格）：活单按 a 那份的挂单量算底，b 只看吃掉了多少——挂单量一拍一个样，拿各自的底算的话
 *  成交没动、格也会跳（10-07 实测剩下每拍 1–7 条就是这个） */
const fillStep = (a: BigOrder, b: BigOrder): number => {
  if (a.status !== 'live') return Math.round(fillRatio(b) * 20)
  const base = a.notional
  return base > 0 ? Math.round(Math.min(1, Math.max(0, b.filledNotional / base)) * 20) : 0
}

/** 画出来是不是一样（身份、状态、门槛、成交格；不比金额、桶内均价，也不比金额画出来的厚度） */
export function samePixels(a: BigOrder, b: BigOrder): boolean {
  return a.firstSeenMs === b.firstSeenMs && a.bucket === b.bucket && a.side === b.side && a.venueID === b.venueID
    && a.status === b.status && a.endMs === b.endMs && a.threshold === b.threshold
    && fillStep(a, a) === fillStep(a, b)
}

const sameOrder = (a: BigOrder, b: BigOrder): boolean =>
  samePixels(a, b) && a.notional === b.notional && a.filledNotional === b.filledNotional && a.price === b.price
  && a.initialNotional === b.initialNotional && a.vanishedNotional === b.vanishedNotional
  && a.exchange === b.exchange && a.product === b.product

/** 除时间戳外逐字相同 */
export function sameExactContent(a: Snapshot, b: Snapshot): boolean {
  if (a.phase !== b.phase || a.orders.length !== b.orders.length || a.venues.length !== b.venues.length) return false
  const t = a.thresholds, u = b.thresholds
  if (t.spot !== u.spot || t.usdtPerp !== u.usdtPerp || t.coinPerp !== u.coinPerp || t.delivery !== u.delivery || t.step !== u.step) return false
  for (let i = 0; i < a.venues.length; i++) {
    const v = a.venues[i], w = b.venues[i]
    if (v.id !== w.id || v.ready !== w.ready || v.label !== w.label || v.instrument !== w.instrument) return false
  }
  for (let i = 0; i < a.orders.length; i++) if (!sameOrder(a.orders[i], b.orders[i])) return false
  return true
}

/** 拷一份（模型原地改单子，交出去的必须是不再变的） */
export function copySnapshot(s: Snapshot): Snapshot {
  return { phase: s.phase, orders: s.orders.map(o => ({ ...o })), asOfMs: s.asOfMs, thresholds: { ...s.thresholds }, venues: s.venues.map(v => ({ ...v })) }
}

/** 拷一份，活着、画面没变的单金额（与桶内均价）按上一次交出去的那份 */
export function holdAmounts(frame: Snapshot, last: Snapshot): Snapshot {
  const held = new Map<string, BigOrder>()
  for (const o of last.orders) if (o.status === 'live') held.set(orderId(o), o)
  const orders = frame.orders.map(o => {
    const h = o.status === 'live' ? held.get(orderId(o)) : undefined
    return h && samePixels(h, o) ? { ...o, notional: h.notional, filledNotional: h.filledNotional, price: h.price } : { ...o }
  })
  return { phase: frame.phase, orders, asOfMs: frame.asOfMs, thresholds: { ...frame.thresholds }, venues: frame.venues.map(v => ({ ...v })) }
}

export class FramePacer {
  private last: Snapshot | null = null
  private lastAt = -Infinity
  private amountsAt = -Infinity

  constructor(private readonly precise: () => boolean = () => false) {}

  /** 这一拍该交出去的帧；null = 这一拍不发 */
  next(frame: Snapshot, now: number): Snapshot | null {
    const last = this.last
    const refresh = !last || this.precise() || ago(this.amountsAt, now) >= AMOUNT_REFRESH_MS
    const out = !last || refresh ? copySnapshot(frame) : holdAmounts(frame, last)
    if (refresh) this.amountsAt = now
    if (last && ago(this.lastAt, now) < HEARTBEAT_MS && sameExactContent(out, last)) return null
    this.last = out
    this.lastAt = now
    return out
  }

  /** 门槛改了、历史并进来了：下一拍一定发（金额也取新的） */
  reset(): void { this.last = null }
}
