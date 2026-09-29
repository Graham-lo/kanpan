// 移植自 KanpanChart/Sources/KanpanChart/ChartRenderer+OrderFlow.swift（逐函数对照，常量、画法、先后与 Swift 一致）
//
// 主力订单流 · 图表这一层（照 CoinAnk「主力大额挂单」的横向价格带，手机布局）。只画、不判定：
// 拿到的是 state.overlay.orderFlow（feed 算好的逐单集合），这里只管换算成横向价格带、图例「主力」一行、
// 带上的金额签，以及轻点 / 十字线选中的那一条（描边 + 交给页面出详情卡）。设计理由见 Swift 原文件头，要点：
//   1. 一堵墙一条：桶 × 侧 × 类（现货 / 合约）× 时间段切段，去掉活不过一根 K 线的已结束段，相邻桶并墙（orderflowGroup.ts）。
//   2. 按屏内排名分主次：前 6 名主、第 7–18 名次、其余底噪；还挂着的底噪升成次。
//   3. 细线 + 签，垫在 K 线下面（用户：「大单不许盖住 K 线，K 线是主体」）：主 2（挂着的 2.5）、次 1 / 70%、底噪 1 / 35%；
//      跨桶的主墙只画代表价一条芯线，范围用段右端一枚「]」括号表达，范围数字写在详情卡上。
//   4. 纵向去挤：和已落下的线纵向重叠（含 1 间隙）的压成 1 细线、不写金额。
//   5. 金额签：只给没被压细的主，一屏最多 6 枚；躲图例、躲盘口梯、躲 K 线；签底 85%，字色取对比度高的近黑 / 白。
//   5b. 颜色：合约买蓝、卖品红，现货买黄、卖紫（r.colors.orderFlow，读 tokens.css 的 --of-*）；
//      被吃过是本色，一口没成交往图区底色混（最多 45%，混完对底仍 ≥ 3:1）。
//   6. 显示开关逐单过滤后再合并；图例「主力 买 X · 卖 Y」按逐单求和。
// 线、底噪、括号只画在图例区（mainLegendInset）以下；签裁在整块主图里。
//
// 与 Swift 的差别（只是运行环境不同，画出来的一样）：
//   · Swift 的 OrderFlowWallCache 是后台串行队列 + 「先拿同一条道上的旧份顶着」；网页里同步算（放在主线程上，
//     单子数组同一块直接命中、换了一块先逐单比内容，内容没变照样命中），最多留三份。
//   · 画布坐标是 CSS px（= pt），画布事先 setTransform(dpr)；填矩形时把边对齐到物理像素（snap），线不糊。
//   · 签的字体：Swift 是 monospacedSystemFont(11, .medium)；这里是 11px / 500 的系统字、数字等宽（ChartFont 的做法）。

import type { BigOrder, BookSide } from '../../orderflow/types'
import type { ChartRenderer, Rect } from './renderer'
import type { Layout, Pane, PriceRange } from './geometry'
import { PriceMapping, snap, swiftRound, yOf as coreYOf } from './geometry'
import { toFixed } from './format'
import type { ChartFontSpec, Hex } from './paint'
import { ChartFont, bytes, contrast, css, drawCentered, drawLeft, orderFlowUnfilled, rgba, roundRectPath, textHeight, textWidth } from './paint'
import { effectivePriceMode } from './state'
import type { OrderFlowCardCandle, OrderFlowCardPlacement, OrderFlowDisplay, OrderFlowGroupKey, OrderFlowSnapshot } from './orderflowGroup'
import { OrderFlowCardBudget, OrderFlowGroup, OrderFlowKey, canonicalSymbol, displayShows, orderFlowDisplayEqual, wallGroup } from './orderflowGroup'

// ------------------------------------------------------------------ 常量（Swift 的 static let，数值照抄）

export const OrderFlowStyle = {
  /** 浅色档（一口没成交）往图区底色混的比例上限（对底不足 3:1 时少混）。 */
  lightMix: 0.45,
  /** 线粗：主 2、还挂着的主 2.5（最粗）、次与底噪 1、被挤的细线 1。 */
  mainLine: 2,
  mainLiveLine: 2.5,
  secondaryLine: 1,
  noiseLine: 1,
  thinLine: 1,
  /** 不透明度：主 1、次 0.7、底噪 0.35。 */
  secondaryAlpha: 0.7,
  noiseAlpha: 0.35,
  /** 底噪一屏最多画几条（并行之后），超出的丢名义最小的。 */
  noiseDrawMax: 200,
  /** 同一行上两段横向隔得不超过这么多就算相邻、并成一条。 */
  noiseJoin: 0.5,
  /** 跨桶主墙的范围括号「]」：宽 3（竖笔与钩都是 1.5）、段色 70%，和金额签之间留 1。 */
  bracketWidth: 3,
  bracketStroke: 1.5,
  bracketAlpha: 0.7,
  bracketGap: 1,
  /** 一屏几名「主」、主加次一共几名。 */
  mainCount: 6,
  rankedCount: 18,
  /** 判「纵向重叠」时两条线之间至少要留的空。 */
  gap: 1,
  /** 金额签：高 16、左右 4、离主图右缘 / 结束点 4、圆角 4、签间 2、离线 2、离蜡烛 2、签底 85%、一屏 6 枚、让位最多 32。 */
  labelHeight: 16,
  labelPadX: 4,
  labelInset: 4,
  labelRadius: 4,
  labelGap: 2,
  labelLineGap: 2,
  labelCandleGap: 2,
  labelAlpha: 0.85,
  labelMax: 6,
  labelMaxShift: 32,
  /** 命中区按至少这么高的带子算。 */
  hitHeight: 8,
  /** 十字线的竖向容差、横向两头各放多少。 */
  hitSlop: 8,
  hitSlopX: 4,
  /** 手指轻点的命中区至少 44 × 44（HIG），只放宽给主档。 */
  touchTarget: 44,
  /** 点蜡烛的纵向容差。 */
  candleHitSlop: 6,
} as const

/** 金额签字体：11 / medium / 整串等宽 SF Mono（Swift monospacedSystemFont(ofSize: 11, weight: .medium)）。 */
export const ORDER_FLOW_LABEL_FONT: ChartFontSpec = { size: 11, weight: 500, tabular: true, mono: true }

const S = OrderFlowStyle

// ------------------------------------------------------------------ 类型

/** 屏内排名的主次：前 6 名主、第 7–18 名次、其余底噪（还挂着的底噪升成次）。 */
export type OrderFlowRole = 'main' | 'secondary' | 'noise'

/** 一条要画的合并带。 */
export interface OrderFlowBand {
  group: OrderFlowGroup
  frame: Rect
  color: Hex
  /** 深色（被吃过）还是浅色（一口没成交）。 */
  dark: boolean
  /** 被排名更前的线挤成了细线（不写金额）。 */
  thin: boolean
  role: OrderFlowRole
  /** 不透明度（主 1、次 0.7、底噪 0.35）。 */
  alpha: number
  /** 跨桶主墙的价位范围括号；单桶、次、底噪、被压细的、范围比芯线还窄的没有。 */
  bracket: Rect | null
}

/** 带右端的金额小签。 */
export interface OrderFlowLabel { key: OrderFlowGroupKey; text: string; frame: Rect; fill: Hex; ink: Hex }

/** 底噪的画法：同一像素行、同色的并成一条。rank 是并进来的几条里名次最前的那条。 */
export interface OrderFlowStroke { frame: Rect; color: Hex; rank: number }

export interface OrderFlowFrame {
  /** 画的先后排好的线：底噪在前，整条的其次，细线在后。 */
  bands: OrderFlowBand[]
  /** 底噪实际画的那几条：并过行、封过顶，按名次排。 */
  noiseStrokes: OrderFlowStroke[]
  labels: OrderFlowLabel[]
  /** 可视区里还挂着（且开着显示）的大单各侧合计（逐单求和）。 */
  bidTotal: number
  askTotal: number
}

const emptyFrame = (): OrderFlowFrame => ({ bands: [], noiseStrokes: [], labels: [], bidTotal: 0, askTotal: 0 })

/** 此刻被选中的那一条合并带，交给页面出详情卡。坐标都是图表坐标（CSS px）。 */
export class ChartOrderFlowFocus {
  constructor(
    /** 最新快照里的这一段（金额、状态随快照更新）。 */
    readonly group: OrderFlowGroup,
    /** true = 轻点选中；false = 十字线停在上面。 */
    readonly selected: boolean,
    /** 卡片躲开的横坐标：十字线的 x，或选中那条带可见段的中点。 */
    readonly anchorX: number,
    /** 这条带的中线 y 与半高（卡片不能盖住它）。 */
    readonly bandY: number,
    readonly bandHalf: number,
    readonly plotW: number,
    /** 主图里能摆卡片的那一段：上沿是图例下沿 + 4，下沿是主图下沿。 */
    readonly mainTop: number,
    readonly mainBottom: number,
    /** 主图整块的高（卡高上限按它的 55% 算）。 */
    readonly mainHeight: number,
    /** 快照时刻（还挂着的单算持续时长用）。 */
    readonly asOfMs: number,
    /** 十字线那根 K 线；轻点选中时没有十字线，是 null。卡片不盖住它。 */
    readonly candle: OrderFlowCardCandle | null = null,
  ) {}

  /** 卡片摆在哪、最宽最高多少、三行还是两行。 */
  get cardPlacement(): OrderFlowCardPlacement {
    return OrderFlowCardBudget.placement({
      bandY: this.bandY, bandHalf: this.bandHalf, top: this.mainTop, bottom: this.mainBottom,
      mainHeight: this.mainHeight, plotW: this.plotW, anchorX: this.anchorX, candle: this.candle,
    })
  }
  /** 卡片最宽多少（躲 K 线时会收窄）。 */
  get cardMaxWidth(): number { return this.cardPlacement.maxWidth }
}

// ------------------------------------------------------------------ 小工具

const minX = (r: Rect) => r.x
const maxX = (r: Rect) => r.x + r.w
const minY = (r: Rect) => r.y
const maxY = (r: Rect) => r.y + r.h
const midX = (r: Rect) => r.x + r.w / 2
const midY = (r: Rect) => r.y + r.h / 2
const rect = (x: number, y: number, w: number, h: number): Rect => ({ x, y, w, h })
const intersects = (a: Rect, b: Rect) => minX(a) < maxX(b) && maxX(a) > minX(b) && minY(a) < maxY(b) && maxY(a) > minY(b)
const sameRect = (a: Rect | null, b: Rect | null) =>
  a == null || b == null ? a == null && b == null : a.x === b.x && a.y === b.y && a.w === b.w && a.h === b.h
const EPS = 1e-9

/** KanpanCore.mixHex：整数通道按比例混，输出小写（a·(1−k) + b·k）。 */
export function mixHex(a: Hex, b: Hex, k: number): Hex {
  const pa = bytes(a), pb = bytes(b)
  const m = (x: number, y: number) => {
    const v = swiftRound(x * (1 - k) + y * k)
    return Math.max(0, Math.min(255, v)).toString(16).padStart(2, '0')
  }
  return '#' + m(pa.r, pb.r) + m(pa.g, pb.g) + m(pa.b, pb.b)
}

/** 名义金额：K / M / B / T 一位小数。 */
export function orderFlowAmount(value: number): string {
  const a = Math.abs(value)
  if (a >= 1e12) return toFixed(value / 1e12, 1) + 'T'
  if (a >= 1e9) return toFixed(value / 1e9, 1) + 'B'
  if (a >= 1e6) return toFixed(value / 1e6, 1) + 'M'
  if (a >= 1e3) return toFixed(value / 1e3, 1) + 'K'
  return toFixed(value, 0)
}

/** 图区底色是不是浅色（按亮度）。 */
export function isLightBackground(bg: Hex): boolean {
  const v = rgba(bg)
  return 0.2126 * v.r + 0.7152 * v.g + 0.0722 * v.b > 0.5
}

/** 小签上的字色：近黑与白里对 fill 对比度高的那个；两个都不到 4.5:1 就用纯黑。 */
export function orderFlowLabelInk(fill: Hex): Hex {
  const dark = contrast('#141414', fill), light = contrast('#FFFFFF', fill)
  if (Math.max(dark, light) < 4.5) return '#000000'
  return dark >= light ? '#141414' : '#FFFFFF'
}

/** 金额签的横向落点：挂着的贴主图右缘，已结束的在结束点右侧、放不下收回主图右缘以内。 */
export function orderFlowLabelX(live: boolean, lineRight: number, w: number, plotW: number): number {
  const edge = plotW - S.labelInset - w
  return live ? edge : Math.min(lineRight + S.labelInset, edge)
}

/** 金额签的宽：字宽 + 左右各 4。 */
export function orderFlowLabelWidth(text: string): number {
  return textWidth(text, ORDER_FLOW_LABEL_FONT) + 2 * S.labelPadX
}

/** 签（含 2 间隙）和盘口梯那一块交叠就挪到梯子左边，纵向不动。 */
export function orderFlowDodgeLadder(r: Rect, ladder: Rect | null): Rect {
  if (!ladder) return r
  const g = S.labelGap
  if (!(minX(r) < maxX(ladder) && maxX(r) > minX(ladder) - g && minY(r) < maxY(ladder) + g && maxY(r) > minY(ladder) - g)) return r
  return rect(minX(ladder) - g - r.w, r.y, r.w, r.h)
}

/** 跨桶主墙的范围括号：右缘紧贴金额签的横向落点左侧 1，纵向是整个价位范围。开着盘口时签躲梯子，括号跟着签走。 */
export function orderFlowBracket(o: {
  live: boolean; lineRight: number; labelWidth: number; plotW: number; top: number; bottom: number; mid?: number; ladder?: Rect | null
}): Rect {
  const x = orderFlowLabelX(o.live, o.lineRight, o.labelWidth, o.plotW)
  const nominal = orderFlowDodgeLadder(rect(x, (o.mid ?? 0) - S.labelHeight / 2, o.labelWidth, S.labelHeight), o.ladder ?? null)
  const right = minX(nominal) - S.bracketGap
  return rect(right - S.bracketWidth, o.top, S.bracketWidth, o.bottom - o.top)
}

/** 签躲 K 线横向挪了，范围括号跟着签走；挪过去和排名更前、已立的括号纵向重叠的就不立。 */
export function orderFlowBracketsFollowLabels(bands: OrderFlowBand[], labels: OrderFlowLabel[]): OrderFlowBand[] {
  if (!bands.some(b => b.bracket != null) || !labels.length) return bands
  const kept: Rect[] = []
  return bands.map(band => {
    if (!band.bracket) return band
    let k = band.bracket
    let moved = false
    const label = labels.find(l => OrderFlowKey.equal(l.key, band.group.key))
    if (label) {
      const right = minX(label.frame) - S.bracketGap
      if (Math.abs(maxX(k) - right) > EPS) {
        k = rect(right - k.w, k.y, k.w, k.h)
        moved = true
      }
    }
    if (kept.some(q => intersects(q, k))) return { ...band, bracket: null }
    kept.push(k)
    return moved ? { ...band, bracket: k } : band
  })
}

/** 底噪按像素行并：同一行、同色、横向重叠或相隔 ≤ 0.5 的并成一条；超过 max 条按名次留前 max 条。noise 须按名次排好。 */
export function orderFlowMergeNoise(noise: OrderFlowBand[], colorIndex: number[], max: number): OrderFlowStroke[] {
  if (!noise.length) return []
  const h = S.noiseLine
  type Item = { color: number; row: number; left: number; right: number; rank: number }
  const items: Item[] = noise.map((band, rank) => ({
    color: colorIndex[rank], row: swiftRound(midY(band.frame) - h / 2), left: minX(band.frame), right: maxX(band.frame), rank,
  }))
  items.sort((a, b) => (a.color !== b.color ? a.color - b.color : a.row !== b.row ? a.row - b.row : a.left - b.left))
  const out: OrderFlowStroke[] = []
  let cur = { ...items[0] }
  const flush = (c: Item) => out.push({ frame: rect(c.left, c.row, c.right - c.left, h), color: noise[c.rank].color, rank: c.rank })
  for (let i = 1; i < items.length; i++) {
    const item = items[i]
    if (item.color === cur.color && item.row === cur.row && item.left <= cur.right + S.noiseJoin) {
      cur.right = Math.max(cur.right, item.right)
      if (item.rank < cur.rank) cur.rank = item.rank
    } else {
      flush(cur)
      cur = { ...item }
    }
  }
  flush(cur)
  out.sort((a, b) => a.rank - b.rank)
  if (out.length > max) out.length = max
  return out
}

/** color 以 alpha 叠在 bg 上读出来的颜色（不透明）。 */
const premixMemo = new Map<string, Hex>()
export function orderFlowPremixed(color: Hex, alpha: number, bg: Hex): Hex {
  if (!(alpha < 1)) return color
  const key = color + '|' + alpha + '|' + bg
  const hit = premixMemo.get(key)
  if (hit !== undefined) return hit
  const value = mixHex(color, bg, 1 - alpha)
  if (premixMemo.size >= 256) premixMemo.clear()
  premixMemo.set(key, value)
  return value
}

// ------------------------------------------------------------------ 命中（纯函数，测试直接用）

/**
 * 一个点落在哪条带上。命中按「以线为中线、至少 8 高的带子」算；横向落在带里（两头各放 4）为前提：
 *   1. 点在某条带的范围里（上下各放 0.5）：离线最近的；一样近取名义大的，再一样取画在上面的；
 *   2. 否则离带边不超过 8（轻点时主档放到 44 的命中区）的里面取最近的；一样近取名义大的、再取 id 小的；
 *   3. 都不沾：落在某堵跨桶主墙的范围括号上就认那堵墙，几堵叠着取名义大的。
 * 轻点只认看得清的：底噪点不中。
 */
export function orderFlowHitBands(all: OrderFlowBand[], x: number, y: number, touch = false): OrderFlowBand | null {
  const bands = touch ? all.filter(b => b.role !== 'noise') : all
  const half = (b: OrderFlowBand) => Math.max(b.frame.h, S.hitHeight) / 2
  const slopX = (b: OrderFlowBand) =>
    touch && b.role === 'main' ? Math.max(S.hitSlopX, (S.touchTarget - b.frame.w) / 2) : S.hitSlopX
  const slopY = (b: OrderFlowBand) =>
    touch && b.role === 'main' ? Math.max(S.hitSlop, (S.touchTarget - 2 * half(b)) / 2) : S.hitSlop
  const inX = (b: OrderFlowBand) => x >= minX(b.frame) - slopX(b) && x <= maxX(b.frame) + slopX(b)
  const off = (b: OrderFlowBand) => Math.abs(y - midY(b.frame))
  let exact: { b: OrderFlowBand; i: number } | null = null
  bands.forEach((b, i) => {
    if (!(inX(b) && off(b) <= half(b) + 0.5)) return
    if (!exact) { exact = { b, i }; return }
    const a: { b: OrderFlowBand; i: number } = exact
    const oa = off(b), ob = off(a.b)
    const better = oa !== ob ? oa < ob
      : b.group.drawNotional !== a.b.group.drawNotional ? b.group.drawNotional > a.b.group.drawNotional : i > a.i
    if (better) exact = { b, i }
  })
  if (exact) return (exact as { b: OrderFlowBand }).b
  const gap = (b: OrderFlowBand) => Math.max(0, off(b) - half(b))
  const rankBefore = (a: OrderFlowBand, b: OrderFlowBand): boolean => {
    if (a.group.drawNotional !== b.group.drawNotional) return a.group.drawNotional > b.group.drawNotional
    return OrderFlowKey.id(a.group.key) < OrderFlowKey.id(b.group.key)
  }
  let near: OrderFlowBand | null = null
  for (const b of bands) {
    if (!(inX(b) && gap(b) <= slopY(b))) continue
    if (!near) { near = b; continue }
    const ga = gap(b), gb = gap(near)
    if (ga !== gb ? ga < gb : rankBefore(b, near)) near = b
  }
  if (near) return near
  let onBracket: OrderFlowBand | null = null
  for (const b of bands) {
    const r = b.bracket
    if (!r) continue
    const sx = touch ? Math.max(S.hitSlopX, (S.touchTarget - r.w) / 2) : S.hitSlopX
    if (!(x >= minX(r) - sx && x <= maxX(r) + sx && y >= minY(r) - 0.5 && y <= maxY(r) + 0.5)) continue
    if (!onBracket || rankBefore(b, onBracket)) onBracket = b
  }
  return onBracket
}

// ------------------------------------------------------------------ 与视野无关的那一半：墙（Swift OrderFlowWallCache）

export interface OrderFlowWallItem { group: OrderFlowGroup; startMs: number; endMs: number | null }
export interface OrderFlowWallEntry { walls: OrderFlowWallItem[]; live: BigOrder[] }
export interface OrderFlowWallKey {
  symbol: string
  orders: BigOrder[]
  display: OrderFlowDisplay
  step: number | null
  gapMs: number
  minLifeMs: number
}

const sameOrder = (a: BigOrder, b: BigOrder): boolean => a === b || (
  a.venueID === b.venueID && a.exchange === b.exchange && a.product === b.product && a.side === b.side
  && a.bucket === b.bucket && a.price === b.price && a.firstSeenMs === b.firstSeenMs && a.endMs === b.endMs
  && a.status === b.status && a.initialNotional === b.initialNotional && a.notional === b.notional
  && a.filledNotional === b.filledNotional && a.threshold === b.threshold && a.vanishedNotional === b.vanishedNotional)

const sameLane = (a: OrderFlowWallKey, b: OrderFlowWallKey): boolean =>
  a.symbol === b.symbol && orderFlowDisplayEqual(a.display, b.display) && a.step === b.step
  && a.gapMs === b.gapMs && a.minLifeMs === b.minLifeMs

function sameContent(a: OrderFlowWallKey, b: OrderFlowWallKey): boolean {
  if (!sameLane(a, b) || a.orders.length !== b.orders.length) return false
  if (a.orders === b.orders) return true
  for (let i = 0; i < a.orders.length; i++) if (!sameOrder(a.orders[i], b.orders[i])) return false
  return true
}

/**
 * 进程内的小缓存：按内容认（单子数组先比是不是同一块，同一份快照 O(1)；换了一块再逐单比），最多留三份。
 * Swift 在后台队列上算、没算好先拿旧份顶着；网页同步算（见文件头）。
 */
export const OrderFlowWallCache = {
  capacity: 3,
  /** 真算了几次（测试核对缓存有没有生效）。 */
  computed: 0,
  entries: [] as { key: OrderFlowWallKey; entry: OrderFlowWallEntry; generation: number }[],
  generation: 0,

  entry(key: OrderFlowWallKey): OrderFlowWallEntry {
    const C = OrderFlowWallCache
    let i = C.entries.findIndex(e => sameLane(e.key, key) && e.key.orders === key.orders)
    if (i < 0) {
      const order = C.entries.map((_, k) => k).sort((a, b) => C.entries[b].generation - C.entries[a].generation)
      const found = order.find(k => sameContent(C.entries[k].key, key))
      if (found !== undefined) { C.entries[found].key = key; i = found }
    }
    if (i >= 0) return C.entries[i].entry
    C.generation += 1
    const g = C.generation
    const entry = OrderFlowWallCache.compute(key)
    C.computed += 1
    if (C.entries.length >= C.capacity) {
      let oldest = 0
      for (let k = 1; k < C.entries.length; k++) if (C.entries[k].generation < C.entries[oldest].generation) oldest = k
      C.entries.splice(oldest, 1)
    }
    C.entries.push({ key, entry, generation: g })
    return entry
  },

  /** 过显示开关 → 切段 → 去碎屑 → 并墙 → 建组 → 按 drawOrder 排好；记下过了开关、还挂着的单。 */
  compute(key: OrderFlowWallKey): OrderFlowWallEntry {
    const shown = key.orders.filter(o => displayShows(key.display, o))
    const parts = OrderFlowGroup.dropShortLived(OrderFlowGroup.segments(shown, key.gapMs), key.minLifeMs)
    const walls: OrderFlowWallItem[] = []
    for (const wall of OrderFlowGroup.walls(parts, key.gapMs)) {
      const group = wallGroup(wall, key.step)
      if (group) walls.push({ group, startMs: wall.startMs, endMs: wall.endMs })
    }
    walls.sort((a, b) => OrderFlowGroup.compareDrawOrder(a.group, b.group))
    return { walls, live: shown.filter(o => o.status === 'live') }
  },

  clear(): void {
    OrderFlowWallCache.entries = []
    OrderFlowWallCache.computed = 0
  },
}

// ------------------------------------------------------------------ 取数

/** 这一帧要不要画主力订单流：快照属于当前品种、不在比价模式。 */
export function orderFlowSnapshot(r: ChartRenderer): OrderFlowSnapshot | null {
  const st = r.state, flow = st.overlay.orderFlow
  if (!flow || st.input.percentAxis) return null
  if (canonicalSymbol(flow.symbol) !== canonicalSymbol(st.input.symbol.symbol)) return null
  return flow
}

export function hasOrderFlow(r: ChartRenderer): boolean { return orderFlowSnapshot(r) != null }

/** 这一周期的切段容差：max(60 秒, 一根 K 线)。并墙的时间容差也用它。 */
export const orderFlowMergeGapMs = (r: ChartRenderer): number => OrderFlowGroup.mergeGapMs(r.state.input.series.step)
/** 已结束的段活不过这么久就不画：一根 K 线。 */
export const orderFlowMinLifeMs = (r: ChartRenderer): number => Math.max(0, r.state.input.series.step)

export function orderFlowWallKey(r: ChartRenderer, flow: OrderFlowSnapshot): OrderFlowWallKey {
  return {
    symbol: canonicalSymbol(flow.symbol), orders: flow.orders, display: r.state.overlay.orderFlowDisplay,
    step: flow.thresholds.step ?? null, gapMs: orderFlowMergeGapMs(r), minLifeMs: orderFlowMinLifeMs(r),
  }
}

/** 这份快照在当前显示开关、周期下的那一份；同一只盒子（r.orderFlowCache，随 state 换新）里只取一次。 */
export function orderFlowEntry(r: ChartRenderer, flow: OrderFlowSnapshot): OrderFlowWallEntry {
  const memo = r.orderFlowCache.get('entry') as OrderFlowWallEntry | undefined
  if (memo) return memo
  const entry = OrderFlowWallCache.entry(orderFlowWallKey(r, flow))
  r.orderFlowCache.set('entry', entry)
  return entry
}

// ------------------------------------------------------------------ 颜色

/** 本色：合约买蓝、卖品红，现货买黄、卖紫（跟 r.colors.orderFlow，不跟皮肤涨跌色）。 */
export function orderFlowBaseColor(r: ChartRenderer, side: BookSide, contract: boolean): Hex {
  const p = r.colors.orderFlow
  return contract ? (side === 'bid' ? p.contractBid : p.contractAsk) : (side === 'bid' ? p.spotBid : p.spotAsk)
}

/** 画出来的颜色：被吃过是本色，一口没成交往图区底色混（最多 45%，混完对底仍 ≥ 3:1）。 */
export function orderFlowColor(r: ChartRenderer, side: BookSide, contract: boolean, hasFill: boolean): Hex {
  const base = orderFlowBaseColor(r, side, contract)
  return hasFill ? base : orderFlowUnfilled(base, r.colors.bg, S.lightMix)
}

const paletteMemo = new Map<string, Hex[]>()
/** 八种画法色，下标 (合约 ? 4 : 0) + (卖 ? 2 : 0) + (被吃过 ? 1 : 0)，按底色与四色记下来。 */
export function orderFlowPalette(r: ChartRenderer): Hex[] {
  const c = r.colors, p = c.orderFlow
  const key = [c.bg, p.contractBid, p.contractAsk, p.spotBid, p.spotAsk].join('|')
  const hit = paletteMemo.get(key)
  if (hit) return hit
  const out: Hex[] = []
  for (const contract of [false, true]) {
    for (const side of ['bid', 'ask'] as BookSide[]) {
      for (const fill of [false, true]) out.push(orderFlowColor(r, side, contract, fill))
    }
  }
  if (paletteMemo.size >= 16) paletteMemo.clear()
  paletteMemo.set(key, out)
  return out
}

const colorIndexOf = (g: OrderFlowGroup): number => (g.contract ? 4 : 0) + (g.side === 'bid' ? 0 : 2) + (g.hasFill ? 1 : 0)

// ------------------------------------------------------------------ 横向：时刻 → K 线格子

/** 这一屏在时间上的粗筛界：起点 ≥ hi 的、结束 < lo 的一定看不见（找不到给 +∞）。 */
function orderFlowVisibleTimes(r: ChartRenderer, spacing: number, plotW: number): { lo: number; hi: number } {
  const b = r.state.input.series, view = r.state.viewport.view
  const n = b.count
  if (n <= 0) return { lo: Infinity, hi: -Infinity }
  const cx = (i: number) => view.x(b.time(i), plotW)
  const first = (pred: (i: number) => boolean): number => {
    let lo = 0, hi = n
    while (lo < hi) {
      const mid = (lo + hi) >> 1
      if (pred(mid)) hi = mid; else lo = mid + 1
    }
    return lo
  }
  const iL = first(i => cx(i) + spacing / 2 > -1)
  const iR = first(i => cx(i) - spacing / 2 >= plotW)
  return { lo: iL < n ? b.time(iL) : Infinity, hi: iR < n ? b.time(iR) : Infinity }
}

/** 某一时刻落在哪根 K 线上，那根的左右缘（蜡烛中心落在 openTime 上）。早于序列的给 −∞。 */
function orderFlowBarX(r: ChartRenderer, ms: number, spacing: number, plotW: number): { left: number; right: number } {
  const b = r.state.input.series
  if (ms < b.firstTime) return { left: -Infinity, right: -Infinity }
  let i = b.index(ms)
  if (b.time(i) > ms && i > 0) i -= 1
  const cx = r.state.viewport.view.x(b.time(i), plotW)
  return { left: cx - spacing / 2, right: cx + spacing / 2 }
}

/** 一堵墙在这一屏的横向范围（至少 1）；横向不落在主图里、或代表价不在主图里的给 null。 */
function orderFlowWallSpan(r: ChartRenderer, wall: OrderFlowWallItem, pane: Pane, spacing: number, plotW: number,
  y: (p: number) => number): { left: number; right: number } | null {
  const x0 = orderFlowBarX(r, wall.startMs, spacing, plotW).left
  const x1 = wall.endMs != null ? orderFlowBarX(r, wall.endMs, spacing, plotW).right : plotW
  const left = Math.max(0, x0), right = Math.min(plotW, Math.max(x1, x0 + 1))
  if (!(right > left && left < plotW)) return null
  const cy = y(wall.group.price)
  if (!(Number.isFinite(cy) && cy >= pane.y && cy <= pane.y + pane.h)) return null
  return { left, right }
}

/** 不做时间粗筛、逐墙算出这一屏落进来几堵（只给测试核对粗筛没丢墙）。 */
export function orderFlowFrameUnfiltered(r: ChartRenderer, W: number, H: number): number {
  const flow = orderFlowSnapshot(r)
  if (!flow || flow.phase !== 'ready' || r.state.input.series.isEmpty) return 0
  const L = r.layout(W, H), range = r.priceRange(W, H), mode = effectivePriceMode(r.state)
  const spacing = r.spacing(L.plotW)
  const y = (p: number) => coreYOf(p, L.main, range, mode)
  return orderFlowEntry(r, flow).walls.filter(w => orderFlowWallSpan(r, w, L.main, spacing, L.plotW, y) != null).length
}

// ------------------------------------------------------------------ 签躲 K 线

export interface OrderFlowCandleProbe {
  dodge: (r: Rect, toRight: boolean, floor: number) => Rect | null
  overlap: (r: Rect) => number
}

/**
 * 金额签躲 K 线：签横向范围里有蜡烛（含影线）和它纵向重叠，就横向挪开，纵向不动；挪过去又压到下一根接着让。
 * toRight 为假往左让（签左缘越过 floor 给 null），为真往右让（出了主图右缘 −4 给 null）。
 * 蜡烛横向按「中心 ± 格宽 / 3 + 0.5」算。overlap 算一枚签盖住的蜡烛面积。
 */
export function orderFlowCandleDodge(r: ChartRenderer, pane: Pane, range: PriceRange, plotW: number, spacing: number): OrderFlowCandleProbe {
  const st = r.state, b = st.input.series, view = st.viewport.view
  const n = b.count
  const map = new PriceMapping(range, effectivePriceMode(st))
  const ha = r.heikin
  const closeOnly = st.input.options.kind === 'line'
  const half = Math.max(1, spacing / 3 + 0.5)
  const gap = S.labelCandleGap
  const cx = (i: number) => view.x(b.time(i), plotW)
  const extent = (i: number): { top: number; bottom: number } => {
    let hi: number, lo: number
    const bar = !closeOnly && ha ? ha.bar(i) : null
    if (closeOnly) {
      const c = b.close[i]
      const prev = i > 0 ? (b.close[i - 1] + c) / 2 : c, next = i + 1 < n ? (b.close[i + 1] + c) / 2 : c
      hi = Math.max(c, prev, next); lo = Math.min(c, prev, next)
    } else if (bar) {
      hi = bar.h; lo = bar.l
    } else {
      hi = b.high[i]; lo = b.low[i]
    }
    const y1 = map.y(hi, pane), y2 = map.y(lo, pane)
    return { top: Math.min(y1, y2), bottom: Math.max(y1, y2) }
  }
  const limit = plotW - S.labelInset
  const hits = (i: number, q: Rect): boolean => {
    const e = extent(i)
    return Number.isFinite(e.top) && Number.isFinite(e.bottom) && e.top < maxY(q) && e.bottom > minY(q)
  }
  const firstRightOf = (x: number): number => {
    let lo = 0, hi = n
    while (lo < hi) {
      const mid = (lo + hi) >> 1
      if (cx(mid) + half > x) hi = mid; else lo = mid + 1
    }
    return lo
  }
  const overlap = (q: Rect): number => {
    if (n <= 0) return 0
    let total = 0
    for (let i = firstRightOf(minX(q)); i < n; i++) {
      const c = cx(i)
      if (c - half >= maxX(q)) break
      const e = extent(i)
      if (Number.isFinite(e.top) && Number.isFinite(e.bottom)) {
        const dy = Math.min(e.bottom, maxY(q)) - Math.max(e.top, minY(q))
        const dx = Math.min(c + half, maxX(q)) - Math.max(c - half, minX(q))
        if (dy > 0 && dx > 0) total += dx * dy
      }
    }
    return total
  }
  const dodge = (start: Rect, toRight: boolean, floor: number): Rect | null => {
    if (n <= 0) return start
    let q = { ...start }
    if (toRight) {
      for (let i = firstRightOf(minX(q)); i < n; i++) {
        const c = cx(i)
        const right = c + half
        if (c - half >= maxX(q)) break
        if (right > minX(q) && hits(i, q)) {
          q = rect(right + gap, q.y, q.w, q.h)
          if (maxX(q) > limit) return null
        }
      }
      return q
    }
    let lo = 0, hi = n
    while (lo < hi) {
      const mid = (lo + hi) >> 1
      if (cx(mid) - half >= maxX(q)) hi = mid; else lo = mid + 1
    }
    for (let i = lo - 1; i >= 0; i--) {
      const c = cx(i)
      const left = c - half
      if (c + half <= minX(q)) break
      if (left < maxX(q) && hits(i, q)) {
        q = rect(left - gap - q.w, q.y, q.w, q.h)
        if (minX(q) < floor) return null
      }
    }
    return q
  }
  return { dodge, overlap }
}

// ------------------------------------------------------------------ 金额签

/**
 * 金额签（只给「主」里没被压细的，按排名）：挂着的贴主图右缘、签底坐在线上方 2（上方进图例就翻到线下方）；
 * 已结束的先试五处（结束点右侧居中 / 右侧线上方 / 右侧线下方 / 结束点左侧线上方 / 线下方），哪个不用横向挪就用哪个；
 * 都压着蜡烛就横向让（左侧两处沿线往左滑、右侧居中往右让，取挪得少的），都让不出去就取盖住蜡烛最少的那处。
 * 和已放下的签撞了（留 2）：挪到撞上那枚的上方或下方，离线不超过 32；都不行就不放。一屏最多 6 枚。
 */
function orderFlowLabels(r: ChartRenderer, mains: OrderFlowBand[], pane: Pane, range: PriceRange, L: Layout, spacing: number,
  ladder: Rect | null): OrderFlowLabel[] {
  const h = S.labelHeight, gap = S.labelGap
  const candleDodge = mains.length ? orderFlowCandleDodge(r, pane, range, L.plotW, spacing) : null
  const bg = r.colors.bg
  const ceiling = pane.y + Math.min(r.mainLegendInset(L.plotW), Math.max(0, pane.h - h))
  const labels: OrderFlowLabel[] = []
  const hitsLabel = (l: OrderFlowLabel, q: Rect) =>
    minX(l.frame) < maxX(q) && maxX(l.frame) > minX(q) && minY(q) < maxY(l.frame) + gap && maxY(q) > minY(l.frame) - gap
  const collides = (q: Rect) => labels.some(l => hitsLabel(l, q))
  type Want = { x: number; top: number; left: boolean }
  for (const band of mains) {
    if (labels.length >= S.labelMax) break
    const text = orderFlowAmount(band.group.notional)
    const w = orderFlowLabelWidth(text)
    const x = orderFlowLabelX(band.group.isLive, maxX(band.frame), w, L.plotW)
    if (!(x >= 0)) continue
    const mid = midY(band.frame)
    const clamp = (top: number) => Math.min(Math.max(top, ceiling), pane.y + pane.h - h)
    const live = band.group.isLive
    const halfH = band.frame.h / 2, lift = S.labelLineGap
    const above = mid - halfH - lift - h, below = mid + halfH + lift
    const xL = maxX(band.frame) - S.labelInset - w
    let wants: Want[]
    if (live) {
      wants = (above >= ceiling ? [above, below] : [below]).map(top => ({ x, top, left: false }))
    } else {
      wants = above >= ceiling
        ? [{ x, top: mid - h / 2, left: false }, { x, top: above, left: false }, { x, top: below, left: false }]
        : [{ x, top: mid - h / 2, left: false }, { x, top: below, left: false }]
      if (xL >= Math.max(0, minX(band.frame))) {
        if (above >= ceiling) wants.push({ x: xL, top: above, left: true })
        wants.push({ x: xL, top: below, left: true })
      }
    }
    const preferred = wants[0].top + h / 2
    const shift = (want: Rect): Rect | null => {
      const q = orderFlowDodgeLadder(want, ladder)
      if (!candleDodge) return q
      return candleDodge.dodge(q, !live, 0)
    }
    const place = (want: Want): Rect | null => {
      const q = shift(rect(want.x, clamp(want.top), w, h))
      if (!q || !(minX(q) >= 0) || !(Math.abs(midY(q) - mid) <= S.labelMaxShift)) return null
      if (want.left && Math.abs(minX(q) - want.x) > EPS) return null
      return q
    }
    let first: Rect | null = null
    if (live) {
      for (const want of wants) { const q = place(want); if (q) { first = q; break } }
    } else {
      const placed: { rect: Rect; moved: boolean }[] = []
      for (const want of wants) {
        const q = place(want)
        if (q) placed.push({ rect: q, moved: Math.abs(minX(q) - want.x) > EPS })
      }
      const nominal: Rect[] = []
      for (const want of wants) {
        const q = orderFlowDodgeLadder(rect(want.x, clamp(want.top), w, h), ladder)
        if (minX(q) >= 0 && Math.abs(midY(q) - mid) <= S.labelMaxShift) nominal.push(q)
      }
      const floor = Math.max(0, minX(band.frame))
      const candidates: { rect: Rect; moved: number }[] = []
      for (const want of wants) {
        if (!want.left) continue
        const r0 = orderFlowDodgeLadder(rect(want.x, clamp(want.top), w, h), ladder)
        if (!(Math.abs(midY(r0) - mid) <= S.labelMaxShift)) continue
        const q = candleDodge ? candleDodge.dodge(r0, false, floor) : null
        if (q) candidates.push({ rect: q, moved: Math.abs(minX(q) - want.x) })
      }
      if (placed.length) candidates.push({ rect: placed[0].rect, moved: Math.abs(minX(placed[0].rect) - x) })
      const still = placed.find(p => !p.moved)
      if (still) first = still.rect
      else if (candidates.length) {
        let best = candidates[0]
        for (const c of candidates) if (c.moved < best.moved) best = c
        first = best.rect
      } else if (nominal.length) {
        const cover = (q: Rect) => candleDodge?.overlap(q) ?? 0
        let best = nominal[0]
        for (const q of nominal) if (cover(q) < cover(best)) best = q
        first = best
      }
    }
    if (!first) continue
    let placedRect: Rect = first
    if (collides(placedRect)) {
      for (const want of wants.slice(1)) {
        const q = place(want)
        if (q && !collides(q)) { placedRect = q; break }
      }
    }
    if (collides(placedRect)) {
      const hitsNow = labels.filter(l => hitsLabel(l, placedRect))
      const tops = hitsNow.flatMap(l => [minY(l.frame) - gap - h, maxY(l.frame) + gap])
      let fit: Rect | null = null
      for (const top of tops) {
        if (!(top >= ceiling && top + h <= pane.y + pane.h && Math.abs(top + h / 2 - mid) <= S.labelMaxShift)) continue
        const q = shift(rect(x, top, w, h))
        if (!q || !(minX(q) >= 0) || collides(q)) continue
        if (!fit || Math.abs(midY(q) - preferred) < Math.abs(midY(fit) - preferred)) fit = q
      }
      if (!fit) continue
      placedRect = fit
    }
    const shown = mixHex(band.color, bg, 1 - S.labelAlpha)
    labels.push({ key: band.group.key, text, frame: placedRect, fill: band.color, ink: orderFlowLabelInk(shown) })
  }
  return labels
}

// ------------------------------------------------------------------ 这一屏的几何

function computeOrderFlowBands(r: ChartRenderer, pane: Pane, range: PriceRange, L: Layout, ladder: Rect | null): OrderFlowFrame {
  const flow = orderFlowSnapshot(r), st = r.state
  if (!flow || flow.phase !== 'ready' || !flow.orders.length || st.input.series.isEmpty || !(L.plotW > 0)) return emptyFrame()
  const mode = effectivePriceMode(st)
  const y = (p: number) => coreYOf(p, pane, range, mode)
  const spacing = r.spacing(L.plotW)

  // 1. 图例合计：过了显示开关、还挂着、落在主图里、横向落在这一屏的单（逐单求和）。
  const frame = emptyFrame()
  const entry = orderFlowEntry(r, flow)
  const { lo: tLo, hi: tHi } = orderFlowVisibleTimes(r, spacing, L.plotW)
  for (const order of entry.live) {
    if (!(order.firstSeenMs < tHi)) continue
    const cy = y(order.price)
    if (!(Number.isFinite(cy) && cy >= pane.y && cy <= pane.y + pane.h)) continue
    if (order.side === 'bid') frame.bidTotal += order.notional; else frame.askTotal += order.notional
  }

  // 2. 横向落在这一屏、代表价落在主图里的墙（缓存里已按 drawOrder 排好，就是屏内排名）。
  const visible: { group: OrderFlowGroup; left: number; right: number }[] = []
  for (const wall of entry.walls) {
    if (!(wall.startMs < tHi && (wall.endMs ?? Infinity) >= tLo)) continue
    const span = orderFlowWallSpan(r, wall, pane, spacing, L.plotW, y)
    if (span) visible.push({ group: wall.group, left: span.left, right: span.right })
  }
  if (!visible.length) return frame

  // 3. 按排名定主次与线粗；主、次和已落下的线纵向重叠就压成细线；跨桶主墙立范围括号（同一 x 上纵向重叠的只留大的）。
  const noise: OrderFlowBand[] = [], full: OrderFlowBand[] = [], thin: OrderFlowBand[] = []
  const noiseColor: number[] = []
  const occupied: Rect[] = [], brackets: Rect[] = []
  const palette = orderFlowPalette(r)
  visible.forEach(({ group, left, right }, rank) => {
    let role: OrderFlowRole = rank < S.mainCount ? 'main' : rank < S.rankedCount ? 'secondary' : 'noise'
    if (role === 'noise' && group.isLive) role = 'secondary'
    const cy = y(group.price)
    const color = palette[colorIndexOf(group)]
    const line = (h: number) => rect(left, cy - h / 2, right - left, h)
    if (role === 'noise') {
      noise.push({ group, frame: line(S.noiseLine), color, dark: group.hasFill, thin: false, role: 'noise', alpha: S.noiseAlpha, bracket: null })
      noiseColor.push(colorIndexOf(group))
      return
    }
    let whole: Rect
    let bracket: Rect | null = null
    const alpha = role === 'main' ? 1 : S.secondaryAlpha
    if (role === 'main') {
      whole = line(group.isLive ? S.mainLiveLine : S.mainLine)
      if (group.isRange) {
        const a = y(group.priceLow), b = y(group.priceHigh)
        const top = Math.min(a, b), bottom = Math.max(a, b)
        if (bottom - top > whole.h && top >= pane.y && bottom <= pane.y + pane.h) {
          bracket = orderFlowBracket({
            live: group.isLive, lineRight: right, labelWidth: orderFlowLabelWidth(orderFlowAmount(group.notional)),
            plotW: L.plotW, top, bottom, mid: cy, ladder,
          })
        }
      }
    } else {
      whole = line(S.secondaryLine)
    }
    const clash = occupied.some(q =>
      minX(q) < maxX(whole) && maxX(q) > minX(whole) && minY(whole) < maxY(q) + S.gap && maxY(whole) > minY(q) - S.gap)
    const frameRect = clash ? line(S.thinLine) : whole
    occupied.push(frameRect)
    const kept = clash || !bracket ? null : brackets.some(q => intersects(q, bracket as Rect)) ? null : bracket
    if (kept) brackets.push(kept)
    const band: OrderFlowBand = { group, frame: frameRect, color, dark: group.hasFill, thin: clash, role, alpha, bracket: kept }
    if (clash) thin.push(band); else full.push(band)
  })
  frame.labels = orderFlowLabels(r, full.filter(b => b.role === 'main'), pane, range, L, spacing, ladder)
  const followed = orderFlowBracketsFollowLabels(full, frame.labels)
  frame.bands = [...noise, ...followed, ...thin]
  frame.noiseStrokes = orderFlowMergeNoise(noise, noiseColor, S.noiseDrawMax)
  return frame
}

type FrameMemo = { pane: Pane; range: PriceRange; plotW: number; ladder: Rect | null; frame: OrderFlowFrame }

/** 色带几何，按 pane / range / plotW / 盘口梯走缓存（r.orderFlowCache 随输入、视野、快照、显示开关换新）。 */
export function orderFlowBands(r: ChartRenderer, pane: Pane, range: PriceRange, L: Layout): OrderFlowFrame {
  const cache = r.orderFlowCache
  let entries = cache.get('frames') as FrameMemo[] | undefined
  if (!entries) { entries = []; cache.set('frames', entries) }
  const ladder = r.state.overlay.orderFlow == null ? null : r.depthEnvelope(pane, range, L)
  const hit = entries.find(e =>
    e.pane.y === pane.y && e.pane.h === pane.h && e.pane.indicator === pane.indicator
    && e.range.lo === range.lo && e.range.hi === range.hi && e.range.base === range.base && e.range.inverted === range.inverted
    && e.plotW === L.plotW && sameRect(e.ladder, ladder))
  if (hit) return hit.frame
  const value = computeOrderFlowBands(r, pane, range, L, ladder)
  cache.set('computed', ((cache.get('computed') as number | undefined) ?? 0) + 1)
  if (entries.length >= 4) entries.shift()
  entries.push({ pane: { ...pane }, range: { ...range }, plotW: L.plotW, ladder, frame: value })
  return value
}

/** 同 orderFlowBands（Swift 的 orderFlowFrame）。 */
export const orderFlowFrame = orderFlowBands

// ------------------------------------------------------------------ 命中与选中（gesture.ts / view.ts 的钩子）

/** 轻点这一下落在哪条带上（图表坐标）。只认主图的绘图区。 */
export function orderFlowHit(r: ChartRenderer, x: number, y: number, W: number, H: number): OrderFlowGroup | null {
  if (!orderFlowSnapshot(r) || r.state.input.series.isEmpty) return null
  const L = r.layout(W, H)
  if (!(x >= 0 && x <= L.plotW && y >= L.main.y && y <= L.main.y + L.main.h)) return null
  const frame = orderFlowBands(r, L.main, r.priceRange(W, H), L)
  return orderFlowHitBands(frame.bands, x, y, true)?.group ?? null
}

/** 轻点是不是点在一根 K 线上：横向落在那一根的格子里（不足 8 按 8），纵向在高低 ± 6 以内（收盘价画法只认收盘）。 */
export function candleHit(r: ChartRenderer, x: number, y: number, W: number, H: number): boolean {
  const st = r.state, s = st.input.series
  if (s.isEmpty) return false
  const L = r.layout(W, H)
  if (!(x >= 0 && x <= L.plotW && y >= L.main.y && y <= L.main.y + L.main.h)) return false
  const view = st.viewport.view
  const i = s.index(view.t(x, L.plotW))
  if (!(i >= 0 && i < s.count)) return false
  const spacing = r.spacing(L.plotW)
  const cx = view.x(s.time(i), L.plotW)
  if (!(Math.abs(x - cx) <= Math.max(spacing / 2, 4))) return false
  const closeOnly = st.input.options.kind === 'line'
  let hi = closeOnly ? s.close[i] : s.high[i], lo = closeOnly ? s.close[i] : s.low[i]
  if (st.input.options.kind === 'heikin') {
    const ha = r.heikin?.bar(i)
    if (ha) { hi = Math.max(hi, ha.h); lo = Math.min(lo, ha.l) }
  }
  const range = r.priceRange(W, H), mode = effectivePriceMode(st)
  const y1 = coreYOf(hi, L.main, range, mode), y2 = coreYOf(lo, L.main, range, mode)
  return y >= Math.min(y1, y2) - S.candleHitSlop && y <= Math.max(y1, y2) + S.candleHitSlop
}

/** 十字线停在哪条带上：只看主图。 */
function orderFlowHovered(r: ChartRenderer, bands: OrderFlowBand[], pane: Pane, range: PriceRange, L: Layout): OrderFlowBand | null {
  const st = r.state, cross = st.overlay.crosshair, s = st.input.series
  if (!cross || cross.pane != null || !bands.length || s.isEmpty) return null
  const i = Math.min(Math.max(0, cross.index), s.count - 1)
  const cy = coreYOf(cross.price ?? s.close[i], pane, range, effectivePriceMode(st))
  const cx = st.viewport.view.x(s.time(i), L.plotW)
  return orderFlowHitBands(bands, cx, cy)
}

/**
 * 此刻被选中的那一条（十字线在主图上就看十字线，否则看轻点选中的那一堵）。选中的墙滚出这一屏时 band 为 null，
 * 从整份快照的墙里挑同侧同类的认回来。认的顺序：键一样 → covers → looselyCovers。
 */
export function orderFlowFocusBand(r: ChartRenderer, pane: Pane, range: PriceRange, L: Layout):
  { group: OrderFlowGroup; band: OrderFlowBand | null; hovered: boolean } | null {
  const flow = orderFlowSnapshot(r)
  if (!flow || flow.phase !== 'ready') return null
  const frame = orderFlowBands(r, pane, range, L)
  const cross = r.state.overlay.crosshair
  if (cross) {
    if (cross.pane != null) return null
    const band = orderFlowHovered(r, frame.bands, pane, range, L)
    return band ? { group: band.group, band, hovered: true } : null
  }
  const key = r.state.overlay.orderFlowSelected
  if (!key) return null
  const band = frame.bands.find(b => OrderFlowKey.equal(b.group.key, key))
    ?? frame.bands.find(b => b.group.covers(key)) ?? frame.bands.find(b => b.group.looselyCovers(key))
  if (band) return { group: band.group, band, hovered: false }
  const walls = orderFlowEntry(r, flow).walls.map(w => w.group).filter(g => OrderFlowKey.sameKind(g.key, key))
  const group = walls.find(g => OrderFlowKey.equal(g.key, key)) ?? walls.find(g => g.covers(key)) ?? walls.find(g => g.looselyCovers(key))
  return group ? { group, band: null, hovered: false } : null
}

/** 这一条是不是此刻选中的那一条（轻点同一条收起用）。 */
export function orderFlowIsSelected(r: ChartRenderer, g: OrderFlowGroup): boolean {
  const key = r.state.overlay.orderFlowSelected
  return key ? g.covers(key) || g.looselyCovers(key) : false
}

/** 交给页面的选中带（出详情卡用）。没选中返回 null。 */
export function orderFlowFocus(r: ChartRenderer, W: number, H: number): ChartOrderFlowFocus | null {
  const st = r.state, b = st.input.series
  const flow = orderFlowSnapshot(r)
  if (b.isEmpty || !flow) return null
  const L = r.layout(W, H), range = r.priceRange(W, H)
  const hit = orderFlowFocusBand(r, L.main, range, L)
  if (!hit) return null
  let anchorX: number
  let candle: OrderFlowCardCandle | null = null
  const cross = st.overlay.crosshair
  if (hit.hovered && cross) {
    const i = Math.min(Math.max(0, cross.index), b.count - 1)
    anchorX = st.viewport.view.x(b.time(i), L.plotW)
    const bar = r.heikin?.bar(i) ?? { o: b.open[i], h: b.high[i], l: b.low[i], c: b.close[i] }
    const map = new PriceMapping(range, effectivePriceMode(st))
    const hy = map.y(bar.h, L.main), ly = map.y(bar.l, L.main)
    const half = Math.max(2, r.spacing(L.plotW) / 2)
    if (Number.isFinite(hy) && Number.isFinite(ly)) {
      candle = {
        left: anchorX - half, right: anchorX + half,
        top: Math.max(L.main.y, Math.min(hy, ly)), bottom: Math.min(L.main.y + L.main.h, Math.max(hy, ly)),
      }
    }
  } else if (hit.band) {
    anchorX = midX(hit.band.frame)
  } else {
    anchorX = L.plotW / 2
  }
  const bandY = hit.band ? midY(hit.band.frame) : coreYOf(hit.group.price, L.main, range, effectivePriceMode(st))
  const bandHalf = Math.max(hit.band ? hit.band.frame.h : S.mainLine, S.hitHeight) / 2
  return new ChartOrderFlowFocus(hit.group, !hit.hovered, anchorX, bandY, bandHalf, L.plotW,
    L.main.y + r.mainLegendInset(L.plotW) + 4, L.main.y + L.main.h, L.main.h, flow.asOfMs, candle)
}

/** 十字线正停在一条带上（这时详情卡顶替图里的开高低收框）。 */
export function orderFlowHoversBand(r: ChartRenderer, L: Layout, range: PriceRange): boolean {
  return orderFlowFocusBand(r, L.main, range, L)?.hovered === true
}

/** 此刻主图上画着的色带与小签、十字线有没有停在一条上。只给诊断与测试用。 */
export function orderFlowDiagnostics(r: ChartRenderer, W: number, H: number):
  { bands: OrderFlowBand[]; labels: OrderFlowLabel[]; hovered: boolean; focus: ChartOrderFlowFocus | null } {
  if (r.state.input.series.isEmpty) return { bands: [], labels: [], hovered: false, focus: null }
  const L = r.layout(W, H)
  const focus = orderFlowFocus(r, W, H)
  const frame = orderFlowBands(r, L.main, r.priceRange(W, H), L)
  return { bands: frame.bands, labels: frame.labels, hovered: focus ? !focus.selected : false, focus }
}

// ------------------------------------------------------------------ 画

/** 线、底噪、括号能画到的范围：主图里图例区以下。 */
export function orderFlowPlotClip(r: ChartRenderer, pane: Pane, plotW: number): Rect {
  const top = Math.min(Math.max(0, r.mainLegendInset(plotW)), pane.h)
  return rect(0, pane.y + top, plotW, pane.h - top)
}

/** 填一个矩形，边对齐到物理像素、至少 1 个物理像素（1 / 1.5 / 2 / 2.5 的线不糊）。 */
function fillSnapped(ctx: CanvasRenderingContext2D, q: Rect, scale: number): void {
  const px = 1 / scale
  const x0 = snap(q.x, scale), y0 = snap(q.y, scale)
  const w = Math.max(px, snap(q.w, scale)), h = Math.max(px, snap(q.h, scale))
  ctx.fillRect(x0, y0, w, h)
}

function clipTo(ctx: CanvasRenderingContext2D, q: Rect): void {
  ctx.beginPath()
  ctx.rect(q.x, q.y, q.w, q.h)
  ctx.clip()
}

/**
 * 范围括号「]」：右侧一道竖笔、上下两个朝左的钩，笔画 1.5，整个框宽 3。不透明度由调用方设（0.7）。
 * 先把整枚括号的四条边对齐到物理像素，三笔在对齐后的格子里切：竖笔与钩、上下两钩彼此只贴边不交叠——
 * 三笔各自取整时，框左缘落在像素后半格（一半的位置）钩的右端会多出一个像素压进竖笔，70% 叠两遍成了两个深点；
 * 矮括号（不足两笔高）上下两钩也会叠在一起。Swift 那边 Core Graphics 按原坐标填、三笔正好首尾相接。
 */
export function drawOrderFlowBracket(ctx: CanvasRenderingContext2D, q: Rect, color: Hex, scale: number): void {
  const px = 1 / scale
  const x0 = snap(q.x, scale), x1 = Math.max(x0 + 2 * px, snap(maxX(q), scale))
  const y0 = snap(q.y, scale), y1 = Math.max(y0 + px, snap(maxY(q), scale))
  const t = Math.min(x1 - x0 - px, Math.max(px, snap(S.bracketStroke, scale)))
  const hook = x1 - t - x0
  const th = Math.min(Math.max(px, snap(S.bracketStroke, scale)), y1 - y0)
  ctx.fillStyle = css(color)
  ctx.fillRect(x1 - t, y0, t, y1 - y0)
  ctx.fillRect(x0, y0, hook, th)
  const lowTop = Math.max(y0 + th, y1 - th)
  if (y1 - lowTop > EPS) ctx.fillRect(x0, lowTop, hook, y1 - lowTop)
}

/**
 * 在底图上画线（在蜡烛之前调，垫在 K 线下面）：底噪、整条、细线依次，最后是跨桶主墙的范围括号。
 * 半透明的线先和图区底色混好、再不透明地填（与叠上去读起来一样，快得多）。返回画了几条。
 */
export function drawOrderFlow(r: ChartRenderer, ctx: CanvasRenderingContext2D, pane: Pane, range: PriceRange, L: Layout, scale: number): number {
  const frame = orderFlowBands(r, pane, range, L)
  if (!frame.bands.length) return 0
  ctx.save()
  clipTo(ctx, orderFlowPlotClip(r, pane, L.plotW))
  const bg = r.colors.bg
  let batches: { color: Hex; alpha: number; rects: Rect[] }[] = []
  const flush = () => {
    for (const batch of batches) {
      ctx.fillStyle = css(orderFlowPremixed(batch.color, batch.alpha, bg))
      for (const q of batch.rects) fillSnapped(ctx, q, scale)
    }
    batches = []
  }
  const add = (q: Rect, color: Hex, alpha: number) => {
    const b = batches.find(x => x.alpha === alpha && x.color === color)
    if (b) b.rects.push(q); else batches.push({ color, alpha, rects: [q] })
  }
  for (const stroke of frame.noiseStrokes) add(stroke.frame, stroke.color, S.noiseAlpha)
  flush()
  for (const band of frame.bands) if (band.role !== 'noise' && !band.thin) add(band.frame, band.color, band.alpha)
  flush()
  for (const band of frame.bands) if (band.thin) add(band.frame, band.color, band.alpha)
  flush()
  ctx.globalAlpha = S.bracketAlpha
  for (const band of frame.bands) {
    if (band.role === 'main' && band.bracket) drawOrderFlowBracket(ctx, band.bracket, band.color, scale)
  }
  ctx.globalAlpha = 1
  ctx.restore()
  return frame.bands.length
}

/** 在十字线层上画金额签（签底 85% 不透明）。返回画了几枚。 */
export function drawOrderFlowLabels(r: ChartRenderer, ctx: CanvasRenderingContext2D, pane: Pane, range: PriceRange, L: Layout, scale: number): number {
  const frame = orderFlowBands(r, pane, range, L)
  if (!frame.labels.length) return 0
  ctx.save()
  clipTo(ctx, rect(0, pane.y, L.plotW, pane.h))
  for (const label of frame.labels) {
    const f = label.frame
    const x0 = snap(f.x, scale), y0 = snap(f.y, scale)
    ctx.globalAlpha = S.labelAlpha
    ctx.fillStyle = css(label.fill)
    roundRectPath(ctx, x0, y0, f.w, f.h, S.labelRadius)
    ctx.fill()
    ctx.globalAlpha = 1
    drawCentered(ctx, label.text, x0 + f.w / 2, y0 + f.h / 2, ORDER_FLOW_LABEL_FONT, label.ink)
  }
  ctx.restore()
  return frame.labels.length
}

/** 在十字线层上把选中的那一条再画一遍（盖过蜡烛）并描 1 正文色边；跨桶的括号也用本色再画一遍。返回画了没有。 */
export function drawOrderFlowHover(r: ChartRenderer, ctx: CanvasRenderingContext2D, pane: Pane, range: PriceRange, L: Layout, scale: number): boolean {
  const band = orderFlowFocusBand(r, pane, range, L)?.band
  if (!band) return false
  ctx.save()
  clipTo(ctx, orderFlowPlotClip(r, pane, L.plotW))
  if (band.bracket) drawOrderFlowBracket(ctx, band.bracket, band.color, scale)
  const f = band.frame
  ctx.fillStyle = css(r.colors.text)
  fillSnapped(ctx, rect(f.x - 1, f.y - 1, f.w + 2, f.h + 2), scale)
  ctx.fillStyle = css(band.color)
  fillSnapped(ctx, f, scale)
  ctx.restore()
  return true
}

/**
 * 图例「主力」那一行：跟在叠加指标的图例后面另起一行（x、y 是前面那几段画完停在哪儿）。
 * 始终是「主力 ▬▬ 买 X · ▬▬ 卖 Y」（逐单求和）：买、卖前面各两枚色样（合约、现货，关掉的那类不画）。
 */
export function drawOrderFlowLegend(r: ChartRenderer, ctx: CanvasRenderingContext2D, pane: Pane, L: Layout, x0: number, y0: number): void {
  const flow = orderFlowSnapshot(r)
  if (!flow) return
  const y = x0 > 8 ? y0 + 12 : y0
  if (!(y < pane.y + Math.min(pane.h - 6, r.mainLegendInset(L.plotW) - 4))) return
  const t = r.colors
  const font = ChartFont.axis
  let x = 8
  const put = (text: string, color: Hex) => {
    drawLeft(ctx, text, x, y, font, color)
    x += textWidth(text, font) + 4
  }
  if (flow.phase !== 'ready') { put('主力 …', t.text); return }
  const frame = orderFlowBands(r, pane, r.priceRange(L.W, L.H), L)
  if (!(frame.bidTotal > 0 || frame.askTotal > 0)) { put('主力 暂无', t.text); return }
  const display = r.state.overlay.orderFlowDisplay
  const swatches = (side: BookSide) => {
    const lineY = y + textHeight(font) / 2 - 1
    for (const contract of [true, false]) {
      if (!(contract ? display.contract : display.spot)) continue
      ctx.fillStyle = css(orderFlowBaseColor(r, side, contract))
      ctx.fillRect(x, lineY, 8, 2)
      x += 10
    }
    x += 2
  }
  put('主力', t.text)
  if (frame.bidTotal > 0) { swatches('bid'); put('买 ' + orderFlowAmount(frame.bidTotal), t.text) }
  if (frame.bidTotal > 0 && frame.askTotal > 0) put('·', t.text)
  if (frame.askTotal > 0) { swatches('ask'); put('卖 ' + orderFlowAmount(frame.askTotal), t.text) }
}
