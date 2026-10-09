/* Hkline Web · 主力订单流 · 图上大单带的取舍（纯逻辑，不碰画布）
 *
 * 图上几百道带叠在一起时蜡烛就读不出来了，所以图上只画「值得看的」：
 *   可见价格范围里按峰值名义排，挂着的最多 MAX_LIVE_BANDS 道、已结束的最多 MAX_ENDED_BANDS 道；
 *   其余的只在梯子、侧栏「大单」和抽屉里出现。
 * 挂着的带浓淡 0.14–0.20（最大的最深）；结束的只画一道细线 + 小记号，底色 ≤ 0.08；
 * □ / ▲ 记号只给峰值前 MAX_MARKS 的结束带，而且不许压在蜡烛上；右端标签最多 MAX_LABELS 个、互不重叠。
 * 这些上限是模块常量，不做成用户设置。
 *
 * 2026-10-08 起 PC 也按合并带画（和 iOS、手机网页同一套 OrderFlowGroup：桶 × 侧 × 类 × 时间段切段，
 * 相邻桶并墙）：一道带 = 一堵墙，读数卡一本簿一行（「Bybit 永续 1.2M」）。
 */
import type { BigOrder } from './types'
import { orderId } from './types'
import { OrderFlowGroup, OrderFlowKey, type OrderFlowBook } from './group'

export const MAX_LIVE_BANDS = 8
export const MAX_ENDED_BANDS = 4
export const MAX_LABELS = 8
export const MAX_MARKS = 3

/** 挂着的带：最大的一道 hi，最小的 lo（浅色皮肤 / 深色皮肤各一套）。
 *  带按涨跌方向着色（规范 §2 订单流：浅色 0.10、深色 0.16 上下），涨跌色比原来的品类色饱和，浅色压得更淡 */
export const LIVE_ALPHA = { light: { lo: 0.08, hi: 0.12 }, dark: { lo: 0.13, hi: 0.19 } } as const
/** 结束的带不铺底色（上限 0.08 的要求取 0），只画一道 1 px 细线 */
export const ENDED_LINE = { light: 0.55, dark: 0.5 } as const
/** 被点中的那道 */
export const HIGHLIGHT_ALPHA = { light: 0.22, dark: 0.30 } as const

export interface BandCand { id: string; live: boolean; pk: number }

export interface BandPick<T> {
  /** 挂着的，按峰值从大到小 */
  live: T[]
  /** 结束的，按峰值从大到小 */
  ended: T[]
}

/**
 * 从可见的候选里挑出要画的带。
 * 被点中（高亮）的那道不占名额、总是画；同峰值按 id 排，保证每帧挑出来的一样（不闪）。
 */
export function pickBands<T extends BandCand>(cands: readonly T[], highlight: string | null = null): BandPick<T> {
  const byPk = (a: T, b: T): number => b.pk - a.pk || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0)
  const live = cands.filter(c => c.live).sort(byPk)
  const ended = cands.filter(c => !c.live).sort(byPk)
  const out: BandPick<T> = { live: live.slice(0, MAX_LIVE_BANDS), ended: ended.slice(0, MAX_ENDED_BANDS) }
  if (highlight) {
    const h = cands.find(c => c.id === highlight)
    if (h) {
      const list = h.live ? out.live : out.ended
      if (!list.includes(h)) list.push(h)
    }
  }
  return out
}

/** 挂着的第 rank 道（0 = 峰值最大）的底色浓度：线性从 hi 退到 lo */
export function liveAlpha(rank: number, n: number, dark = false): number {
  const { lo, hi } = dark ? LIVE_ALPHA.dark : LIVE_ALPHA.light
  if (n <= 1) return hi
  const r = Math.min(1, Math.max(0, rank / (n - 1)))
  return +(hi - (hi - lo) * r).toFixed(4)
}

export interface Rect { x: number; y: number; w: number; h: number }
export const overlaps = (a: Rect, b: Rect, pad = 0): boolean =>
  a.x - pad < b.x + b.w && a.x + a.w + pad > b.x && a.y - pad < b.y + b.h && a.y + a.h + pad > b.y

export interface LabelReq {
  /** 标签右沿想贴的 x（带的右端） */
  right: number
  /** 带的左端：往左让位时不越过它 */
  left: number
  /** 标签竖直中心 */
  y: number
  w: number
  h: number
  /** 越大越先摆 */
  prio: number
}

/**
 * 摆右端标签：大的先摆；右沿不越过 maxRight（价格轴以内）；和已摆的、以及 blocked（蜡烛）撞了就往左让，
 * 一次让半个标签宽，让到带的左端还不行就不标。最多 max 个。返回每个请求摆到的矩形（没摆上是 null）。
 */
export function placeLabels(
  reqs: readonly LabelReq[],
  bounds: { top: number; bottom: number; maxRight: number },
  blocked: (r: Rect) => boolean = () => false,
  max = MAX_LABELS,
): (Rect | null)[] {
  const order = reqs.map((_, i) => i).sort((a, b) => reqs[b].prio - reqs[a].prio)
  const out: (Rect | null)[] = reqs.map(() => null)
  const placed: Rect[] = []
  for (const i of order) {
    if (placed.length >= max) break
    const q = reqs[i]
    const y = q.y - q.h / 2
    if (y < bounds.top || y + q.h > bounds.bottom) continue
    const stepX = Math.max(8, q.w / 2)
    for (let right = Math.min(q.right, bounds.maxRight); right - q.w >= Math.max(q.left, 0) - 0.5; right -= stepX) {
      const r: Rect = { x: right - q.w, y, w: q.w, h: q.h }
      if (placed.some(p => overlaps(p, r, 2)) || blocked(r)) continue
      placed.push(r); out[i] = r
      break
    }
  }
  return out
}

/**
 * 结束记号的位置：先放在带的右端（结束那一刻）；压到蜡烛就沿着带往左一根一根让（最多 maxShift 根），
 * 还不行就落到时间轴上方那一条（axisY），x 不变——记号永远不盖在蜡烛上。
 */
export function placeMark(
  x: number, y: number, s: number, left: number, spacing: number,
  blocked: (r: Rect) => boolean, axisY: number, maxShift = 4,
): { x: number; y: number; onAxis: boolean } {
  const box = (cx: number, cy: number): Rect => ({ x: cx - s / 2 - 1, y: cy - s / 2 - 1, w: s + 2, h: s + 2 })
  const st = Math.max(s + 2, spacing)
  for (let k = 0; k <= maxShift; k++) {
    const cx = x - k * st
    if (k > 0 && cx - s / 2 < left) break
    if (!blocked(box(cx, y))) return { x: cx, y, onAxis: false }
  }
  return { x, y: axisY - s / 2 - 2, onAxis: true }
}

// ------------------------------------------------------------------ 合并带（PC 与手机同一套 OrderFlowGroup）

export interface WallOpts {
  /** 切段 / 并墙的时间容差（OrderFlowGroup.mergeGapMs(一根 K 线)） */
  gapMs: number
  /** 已结束的段活不过这么久就不画（一根 K 线） */
  minLifeMs: number
  step: number | null
}

/** 同一批单（快照数组）× 同一组参数只并一次：十六张图同一品种、每帧重画都走缓存 */
const wallCache = new WeakMap<readonly BigOrder[], Map<string, OrderFlowGroup[]>>()

/** 过滤后的单 → 合并带（按 drawOrder 排好）。orders 是快照里的原数组（缓存键），keep 是显示开关 */
export function mergedWalls(orders: readonly BigOrder[], keep: (o: BigOrder) => boolean, keepKey: string, o: WallOpts): OrderFlowGroup[] {
  const k = `${keepKey}|${o.gapMs}|${o.minLifeMs}|${o.step ?? ''}`
  let m = wallCache.get(orders)
  if (!m) { m = new Map(); wallCache.set(orders, m) }
  const hit = m.get(k)
  if (hit) return hit
  const out = OrderFlowGroup.groups(orders.filter(keep), o.gapMs, o.minLifeMs, o.step)
  m.set(k, out)
  return out
}

/** 被点中的那一单所在的墙；它那一段被当碎屑去掉了就单独给它建一道（点中的总要画出来） */
export function wallOf(walls: readonly OrderFlowGroup[], highlight: string | null, orders: readonly BigOrder[], step: number | null, keep: (o: BigOrder) => boolean = () => true): OrderFlowGroup | null {
  if (!highlight) return null
  for (const w of walls) if (w.members.some(m => orderId(m) === highlight)) return w
  const o = orders.find(x => orderId(x) === highlight && keep(x))
  return o ? OrderFlowGroup.make(OrderFlowKey.of(o), [o], null, step) : null
}

/** 一道带的身份：墙里包含被点中的那一单就用它（高亮、联动梯子都按单 id），否则用墙里最大那本簿的最新一单 */
export function wallId(w: OrderFlowGroup, highlight: string | null): string {
  if (highlight && w.members.some(m => orderId(m) === highlight)) return highlight
  return orderId(w.books[0]?.latest ?? w.members[0])
}

export interface BookRow { book: OrderFlowBook; usd: number }

/** 读数卡一本簿一行：挂着的写此刻名义，结束的写它的峰值；按金额从大到小（一样按簿 id） */
export function bookRows(w: OrderFlowGroup, peakOf: (o: BigOrder) => number): BookRow[] {
  return w.books.map(b => ({ book: b, usd: b.latest.status === 'live' ? b.latest.notional : peakOf(b.latest) }))
    .sort((a, b) => b.usd - a.usd || (a.book.venueID < b.book.venueID ? -1 : a.book.venueID > b.book.venueID ? 1 : a.book.bucket - b.book.bucket))
}

/** 一道带的峰值（排名、标签用）：各本簿金额之和 */
export const wallPeak = (rows: readonly BookRow[]): number => rows.reduce((a, r) => a + r.usd, 0)
