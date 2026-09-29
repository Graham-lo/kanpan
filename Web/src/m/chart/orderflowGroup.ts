// 移植自 KanpanChart/Sources/KanpanChart/OrderFlowGroup.swift
// （外加 KanpanCore 里渲染要用的：OrderFlowSettings.swift 的 OrderFlowDisplay、BigOrder+Display.swift 的
// thicknessQuarters / thicknessTier、OrderFlowSnapshot、InstrumentID.canonical）
//
// 主力订单流 · 手机布局的「一段一条带」：按「价位桶 × 买卖侧 × 类（现货 / 合约）× 时间段」切段，
// 去掉活不过一根 K 线的已结束段，再把同侧同类、桶号相邻、时间上连着的段并成一堵墙（最多 5 个桶、成块）。
// 只是画法合并——feed 交出来的逐单不动，图例「主力 买 X · 卖 Y」仍按逐单求和。算法、常量与 Swift 逐条一致，
// 设计理由见 Swift 原文件头。
//
// 数据类型直接用 PC 与手机共用的 src/orderflow/types.ts（BigOrder 字段与服务端、iOS 同名）。

import type { BigOrder, BookSide, Product, Thresholds } from '../../orderflow/types'
import { isContract, orderId } from '../../orderflow/types'

// ------------------------------------------------------------------ KanpanCore 渲染用的小件

/** OrderFlowDisplay（OrderFlowSettings.swift）：现货 / 合约 / 已成交 / 已撤销四个开关，出厂全开。
 *  注意与 src/orderflow/settings.ts 里 PC 的六开关 Display 不是一回事。 */
export interface OrderFlowDisplay {
  spot: boolean
  contract: boolean
  filled: boolean
  cancelled: boolean
}

export const defaultOrderFlowDisplay = (): OrderFlowDisplay => ({ spot: true, contract: true, filled: true, cancelled: true })

export const orderFlowDisplayEqual = (a: OrderFlowDisplay, b: OrderFlowDisplay): boolean =>
  a.spot === b.spot && a.contract === b.contract && a.filled === b.filled && a.cancelled === b.cancelled

/** 这一单画不画。还挂着的、失联结束的只看产品开关。 */
export function displayShows(d: OrderFlowDisplay, o: BigOrder): boolean {
  if (!(isContract(o.product) ? d.contract : d.spot)) return false
  switch (o.status) {
    case 'live': case 'lost': return true
    case 'filled': return d.filled
    case 'cancelled': return d.cancelled
  }
  return true
}

/** OrderFlowSnapshot：一只品种此刻的逐单集合（还挂着的 + 已结束的）。 */
export interface OrderFlowSnapshot {
  symbol: string
  phase: 'loading' | 'ready'
  orders: BigOrder[]
  asOfMs: number
  thresholds: Thresholds
  /** 可选：叠用户改过的项之前的默认门槛与步长。 */
  defaults?: Thresholds
  /** 可选：各本簿的就绪状态（详情、诊断用；渲染不看）。 */
  venues?: { id: string; label: string; exchange: string; product: Product; instrument: string; ready: boolean }[]
}

/** InstrumentID.canonical：「venue/market/SYMBOL」；只写代号的按币安 U 本位。 */
export function canonicalSymbol(raw: string): string {
  const t = raw.trim()
  if (!t) return ''
  const parts = t.split('/')
  if (parts.length === 3) return `${parts[0].toLowerCase()}/${parts[1].toLowerCase()}/${parts[2].toUpperCase()}`
  return 'binance/usd_m/' + t.toUpperCase()
}

const sameThresholds = (a: Thresholds | undefined, b: Thresholds | undefined): boolean =>
  a === b || (!!a && !!b && a.spot === b.spot && a.usdtPerp === b.usdtPerp && a.coinPerp === b.coinPerp
    && a.delivery === b.delivery && a.step === b.step)

/** BigOrder.renderKey 相等：id、状态、结束、桶、价、门槛、四分之一格、深浅（「画出来一样」）。 */
export function sameRenderKey(a: BigOrder, b: BigOrder): boolean {
  return orderId(a) === orderId(b) && a.status === b.status && a.endMs === b.endMs && a.bucket === b.bucket
    && a.price === b.price && a.threshold === b.threshold
    && thicknessQuarters(a.notional, a.threshold) === thicknessQuarters(b.notional, b.threshold)
    && hasFill(a) === hasFill(b)
}

/** OrderFlowSnapshot.sameRender + ChartView.samePixels：两份快照画在底图上是不是一样（两边都没有也算一样）。 */
export function sameRender(a: OrderFlowSnapshot | null | undefined, b: OrderFlowSnapshot | null | undefined): boolean {
  if (a == null || b == null) return a == null && b == null
  if (a === b) return true
  if (a.symbol !== b.symbol || a.phase !== b.phase || !sameThresholds(a.thresholds, b.thresholds)
    || !sameThresholds(a.defaults, b.defaults) || a.orders.length !== b.orders.length) return false
  const va = a.venues ?? [], vb = b.venues ?? []
  if (va.length !== vb.length) return false
  for (let i = 0; i < va.length; i++) {
    const x = va[i], y = vb[i]
    if (x.id !== y.id || x.label !== y.label || x.exchange !== y.exchange || x.product !== y.product
      || x.instrument !== y.instrument || x.ready !== y.ready) return false
  }
  for (let i = 0; i < a.orders.length; i++) if (!sameRenderKey(a.orders[i], b.orders[i])) return false
  return true
}

export const MAX_THICKNESS_QUARTERS = 64
export const THICKNESS_TIERS = 5

/** 这一单占门槛的几个四分之一（向下取整，封顶 64 = 16 倍）。 */
export function thicknessQuarters(notional: number, threshold: number): number {
  if (!(threshold > 0) || !Number.isFinite(notional) || !(notional > 0)) return 0
  const q = Math.floor(4 * notional / threshold)
  return Number.isFinite(q) ? Math.min(MAX_THICKNESS_QUARTERS, Math.max(0, q)) : 0
}

/** 粗细档：⌊log₂(四分之一格 ÷ 4)⌋ 夹到 0…4；不到 2 倍 0 档。 */
export function thicknessTier(quarters: number): number {
  if (quarters < 8) return 0
  return Math.min(THICKNESS_TIERS - 1, Math.max(0, Math.floor(Math.log2(quarters / 4))))
}

const orderQuarters = (o: BigOrder): number => thicknessQuarters(o.notional, o.threshold)
const isLive = (o: BigOrder): boolean => o.status === 'live'
const hasFill = (o: BigOrder): boolean => o.filledNotional > 0

// ------------------------------------------------------------------ 键

/** 一条合并带（一堵墙）的身份：墙里最早起的那一段是哪一桶、哪一侧、哪一类、从哪一刻起。 */
export interface OrderFlowGroupKey {
  bucket: number
  side: BookSide
  /** true = 合约（U 本位永续、币本位永续、交割），false = 现货。 */
  contract: boolean
  /** 这一段的起点：段里最早的首见（ms）。 */
  start: number
}

export const OrderFlowKey = {
  /** 以这一单为起点的那一段。 */
  of(o: BigOrder): OrderFlowGroupKey {
    return { bucket: o.bucket, side: o.side, contract: isContract(o.product), start: o.firstSeenMs }
  },
  equal(a: OrderFlowGroupKey, b: OrderFlowGroupKey): boolean {
    return a.bucket === b.bucket && a.side === b.side && a.contract === b.contract && a.start === b.start
  },
  /** 同一桶、同一侧、同一类（不管哪一段）。 */
  sameLane(a: OrderFlowGroupKey, b: OrderFlowGroupKey): boolean {
    return a.bucket === b.bucket && a.side === b.side && a.contract === b.contract
  },
  /** 同一侧、同一类：能并成同一堵墙的前提。 */
  sameKind(a: OrderFlowGroupKey, b: OrderFlowGroupKey): boolean {
    return a.side === b.side && a.contract === b.contract
  },
  /** 「contract|ask|836|1790000000000」 */
  id(k: OrderFlowGroupKey): string {
    return (k.contract ? 'contract' : 'spot') + '|' + k.side + '|' + String(k.bucket) + '|' + String(k.start)
  },
}

/** 两个选中键是否同一个（给 view 层比 orderFlowSelected 用）。 */
export const sameOrderFlowKey = (a: OrderFlowGroupKey | null | undefined, b: OrderFlowGroupKey | null | undefined): boolean =>
  a == null || b == null ? a == null && b == null : OrderFlowKey.equal(a, b)

// ------------------------------------------------------------------ 组

/** 一本簿在这堵墙的某一桶里的那一行。 */
export interface OrderFlowBook {
  venueID: string
  exchange: string
  product: Product
  bucket: number
  /** 这本簿在这一桶最近的那一单（首见最晚的）。 */
  latest: BigOrder
  orders: number
  filledNotional: number
  fillBase: number
  hasFill: boolean
}
export const bookNotional = (b: OrderFlowBook): number => b.latest.notional
export const bookPrice = (b: OrderFlowBook): number => b.latest.price
export const bookFillRatio = (b: OrderFlowBook): number => b.fillBase > 0 ? Math.min(1, Math.max(0, b.filledNotional / b.fillBase)) : 0

/** 墙里的一段占的那一格：哪一桶、从哪到哪（挂着的 end 是 null）。 */
export interface OrderFlowSpan { bucket: number; start: number; end: number | null }
export const spanContains = (s: OrderFlowSpan, ms: number): boolean => s.start <= ms && ms <= (s.end ?? Infinity)

/** 一段：键、按首见排好的成员、段的结束（有一单还挂着就是 null）。 */
export interface OrderFlowSegment { key: OrderFlowGroupKey; members: BigOrder[]; endMs: number | null }
export const segmentSpan = (s: OrderFlowSegment): OrderFlowSpan => ({ bucket: s.key.bucket, start: s.key.start, end: s.endMs })

/** 一堵墙：并在一起的几段（还没建组）。 */
export interface OrderFlowWall { key: OrderFlowGroupKey; segments: OrderFlowSegment[]; startMs: number; endMs: number | null }
export const wallMembers = (w: OrderFlowWall): BigOrder[] => w.segments.flatMap(s => s.members)
export const wallSpans = (w: OrderFlowWall): OrderFlowSpan[] => w.segments.map(segmentSpan)
export const wallGroup = (w: OrderFlowWall, step: number | null | undefined): OrderFlowGroup | null =>
  OrderFlowGroup.make(w.key, wallMembers(w), wallSpans(w), step)

const laneKey = (bucket: number, side: BookSide, contract: boolean): string => `${bucket}|${side}|${contract ? 1 : 0}`

/** 一条合并带（一堵墙）：同侧、同类、相邻桶、时间上连着的几段。建好后不可变，派生量建组时算一次。 */
export class OrderFlowGroup {
  readonly key: OrderFlowGroupKey
  /** 按首见先后排的全部单。 */
  readonly members: BigOrder[]
  /** 一本簿一桶一行，按此刻名义从大到小（名义一样按簿名、再按桶）。 */
  readonly books: OrderFlowBook[]
  /** 墙里的各段，按起点排。 */
  readonly spans: OrderFlowSpan[]
  /** 步长（thresholds.step）：算价位范围用；不知道时按各行的价。 */
  readonly step: number | null

  readonly notional: number
  readonly filledNotional: number
  private readonly fillBase: number
  readonly drawNotional: number
  readonly price: number
  readonly hasFill: boolean
  readonly isLive: boolean
  readonly quarters: number
  readonly firstSeenMs: number
  readonly endMs: number | null
  readonly bucketLow: number
  readonly bucketHigh: number
  readonly bucketCount: number

  private constructor(key: OrderFlowGroupKey, members: BigOrder[], books: OrderFlowBook[], spans: OrderFlowSpan[], step: number | null) {
    this.key = key; this.members = members; this.books = books; this.spans = spans; this.step = step
    // derive()：求和顺序按 books 的顺序，浮点结果与 Swift 逐位一致。
    let notional = 0, filled = 0, fillBase = 0, draw = 0, fill = false, quarters = 0
    let top: BigOrder | null = null
    for (const b of books) {
      notional += bookNotional(b)
      filled += b.filledNotional
      fillBase += b.fillBase
      fill = fill || b.hasFill
      const q = orderQuarters(b.latest)
      quarters += q
      draw += q * b.latest.threshold / 4
      if (top) {
        const tq = orderQuarters(top)
        if (q !== tq ? tq < q : orderId(top) > orderId(b.latest)) top = b.latest
      } else top = b.latest
    }
    this.notional = notional; this.filledNotional = filled; this.fillBase = fillBase; this.drawNotional = draw
    this.hasFill = fill; this.quarters = quarters
    this.price = top?.price ?? 0
    let first = Infinity, end: number | null = null, live = false
    for (const m of members) {
      first = Math.min(first, m.firstSeenMs)
      if (isLive(m)) live = true
      if (m.endMs != null) end = Math.max(end ?? m.endMs, m.endMs)
    }
    this.firstSeenMs = members.length ? first : 0
    this.isLive = live
    this.endMs = live ? null : end
    let lo = Infinity, hi = -Infinity
    const set = new Set<number>()
    for (const s of spans) { lo = Math.min(lo, s.bucket); hi = Math.max(hi, s.bucket); set.add(s.bucket) }
    this.bucketLow = spans.length ? lo : key.bucket
    this.bucketHigh = spans.length ? hi : key.bucket
    this.bucketCount = set.size
  }

  /** 把几单合成一条带；空的给 null。spans 不给就按成员一桶一格（每桶最早首见到最晚结束）。 */
  static make(key: OrderFlowGroupKey, members: BigOrder[], spans?: OrderFlowSpan[] | null, step?: number | null): OrderFlowGroup | null {
    if (!members.length) return null
    const st = step != null && Number.isFinite(step) && step > 0 ? step : null
    const sorted = members.slice().sort((a, b) => {
      if (a.firstSeenMs !== b.firstSeenMs) return a.firstSeenMs - b.firstSeenMs
      const ia = orderId(a), ib = orderId(b)
      return ia < ib ? -1 : ia > ib ? 1 : 0
    })
    const rows = new Map<string, OrderFlowBook>()
    const perBucket = new Map<number, OrderFlowSpan>()
    for (const o of sorted) {
      const base = o.status === 'live' ? o.notional : (o.vanishedNotional ?? o.notional)
      const rk = o.venueID + '\u0000' + String(o.bucket)
      const b = rows.get(rk)
      if (b) {
        if (o.firstSeenMs >= b.latest.firstSeenMs) b.latest = o
        b.orders += 1
        b.filledNotional += o.filledNotional
        b.fillBase += base
        b.hasFill = b.hasFill || hasFill(o)
      } else {
        rows.set(rk, { venueID: o.venueID, exchange: o.exchange, product: o.product, bucket: o.bucket, latest: o,
          orders: 1, filledNotional: o.filledNotional, fillBase: base, hasFill: hasFill(o) })
      }
      if (spans == null) {
        const end = isLive(o) ? null : Math.max(o.firstSeenMs, o.endMs ?? o.firstSeenMs)
        const span = perBucket.get(o.bucket)
        if (span) {
          span.start = Math.min(span.start, o.firstSeenMs)
          span.end = span.end == null || end == null ? null : Math.max(span.end, end)
        } else perBucket.set(o.bucket, { bucket: o.bucket, start: o.firstSeenMs, end })
      }
    }
    const books = [...rows.values()].sort((a, b) => {
      const na = bookNotional(a), nb = bookNotional(b)
      if (na !== nb) return na > nb ? -1 : 1
      if (a.venueID !== b.venueID) return a.venueID < b.venueID ? -1 : 1
      return a.bucket - b.bucket
    })
    const sp = (spans ? spans.slice() : [...perBucket.values()]).sort((a, b) => a.start !== b.start ? a.start - b.start : a.bucket - b.bucket)
    return new OrderFlowGroup(key, sorted, books, sp, st)
  }

  get side(): BookSide { return this.key.side }
  get contract(): boolean { return this.key.contract }
  /** 跨了不止一个桶（详情卡标题写价位范围、每行带价）。 */
  get isRange(): boolean { return this.bucketCount > 1 }
  /** 价位范围：最低桶的桶价 … 最高桶的桶价 + 步长。不知道步长时按各行的价。 */
  get priceLow(): number {
    if (this.step != null) return this.bucketLow * this.step
    return this.books.length ? Math.min(...this.books.map(bookPrice)) : this.price
  }
  get priceHigh(): number {
    if (this.step != null) return (this.bucketHigh + 1) * this.step
    return this.books.length ? Math.max(...this.books.map(bookPrice)) : this.price
  }
  /** 成交比例：成交之和 ÷ 各单分母之和（封顶 1）。 */
  get fillRatio(): number {
    const base = this.fillBase
    return base > 0 ? Math.min(1, Math.max(0, this.filledNotional / base)) : 0
  }
  /** 粗细档（0…4）。 */
  get tier(): number { return thicknessTier(this.quarters) }

  /** 选中存的那个键还认不认这堵墙。 */
  covers(other: OrderFlowGroupKey): boolean {
    if (OrderFlowKey.equal(other, this.key)) return true
    if (!OrderFlowKey.sameKind(this.key, other)) return false
    return this.spans.some(s => s.bucket === other.bucket && spanContains(s, other.start))
  }

  /** 宽松地认：键那一段被当碎屑去掉了，但键的桶在墙的桶范围里、起点在墙的时间跨度里。 */
  looselyCovers(other: OrderFlowGroupKey): boolean {
    if (!OrderFlowKey.sameKind(this.key, other) || other.bucket < this.bucketLow || other.bucket > this.bucketHigh) return false
    return this.firstSeenMs <= other.start && other.start <= (this.endMs ?? Infinity)
  }

  // ---------------------------------------------------------------- 静态：切段、去碎屑、并墙、排序

  /** 两段之间的空档不超过这么久就并成一段的下限。 */
  static readonly minMergeGapMs = 60_000
  /** 切段容差：max(60 秒, 一根 K 线的时长)。并墙的时间容差用同一个数。 */
  static mergeGapMs(barMs: number): number { return Math.max(OrderFlowGroup.minMergeGapMs, barMs) }
  /** 一堵墙最多跨几个桶。 */
  static readonly maxWallBuckets = 5

  /** 按「桶 × 侧 × 类 × 时间段」切段。 */
  static segments(orders: BigOrder[], gapMs: number): OrderFlowSegment[] {
    const lanes = new Map<string, { bucket: number; side: BookSide; contract: boolean; list: BigOrder[] }>()
    for (const o of orders) {
      const c = isContract(o.product), k = laneKey(o.bucket, o.side, c)
      let lane = lanes.get(k)
      if (!lane) { lane = { bucket: o.bucket, side: o.side, contract: c, list: [] }; lanes.set(k, lane) }
      lane.list.push(o)
    }
    const out: OrderFlowSegment[] = []
    for (const lane of lanes.values()) {
      const sorted = lane.list.slice().sort((a, b) => a.firstSeenMs - b.firstSeenMs)
      let members: BigOrder[] = []
      let runEnd = -Infinity
      const flush = () => {
        if (!members.length) return
        const key: OrderFlowGroupKey = { bucket: lane.bucket, side: lane.side, contract: lane.contract, start: members[0].firstSeenMs }
        out.push({ key, members, endMs: runEnd === Infinity ? null : runEnd })
      }
      for (const o of sorted) {
        const end = isLive(o) ? Infinity : Math.max(o.firstSeenMs, o.endMs ?? o.firstSeenMs)
        if (members.length && (runEnd === Infinity || o.firstSeenMs - runEnd <= gapMs)) {
          members.push(o)
          runEnd = Math.max(runEnd, end)
        } else {
          flush()
          members = [o]
          runEnd = end
        }
      }
      flush()
    }
    return out
  }

  /** 去掉活不过一根 K 线的已结束段：（结束 − 首见）< minLifeMs。挂着的一律留。 */
  static dropShortLived(segments: OrderFlowSegment[], minLifeMs: number): OrderFlowSegment[] {
    if (!(minLifeMs > 0)) return segments
    return segments.filter(s => s.endMs == null || s.endMs - s.key.start >= minLifeMs)
  }

  /** 把段并成墙（成块：有共同在场时刻、最多 maxWallBuckets 个桶）。 */
  static walls(segments: OrderFlowSegment[], gapMs: number): OrderFlowWall[] {
    if (!segments.length) return []
    const order = segments.map((_, i) => i).sort((i, j) => {
      const a = segments[i].key, b = segments[j].key
      if (a.start !== b.start) return a.start - b.start
      if (a.bucket !== b.bucket) return a.bucket - b.bucket
      if (a.side !== b.side) return a.side === 'bid' ? -1 : 1
      if (a.contract !== b.contract) return !a.contract ? -1 : 1
      return 0
    })
    const reach = (i: number): number => {
      const end = segments[i].endMs
      return end == null ? Infinity : end + gapMs
    }
    interface Building { parts: number[]; low: number; high: number; minReach: number }
    const building: Building[] = []
    const laneWall = new Map<string, number>()
    for (const i of order) {
      const s = segments[i]
      const b = s.key.bucket
      let best: number | null = null
      for (const nb of [b - 1, b + 1]) {
        const w = laneWall.get(laneKey(nb, s.key.side, s.key.contract))
        if (w == null) continue
        const wall = building[w]
        if (!(wall.minReach >= s.key.start
          && Math.max(wall.high, b) - Math.min(wall.low, b) + 1 <= OrderFlowGroup.maxWallBuckets
          && laneWall.get(laneKey(b, s.key.side, s.key.contract)) !== w)) continue
        if (best != null) {
          const ck = segments[building[best].parts[0]].key, wk = segments[wall.parts[0]].key
          if (wk.start < ck.start || (wk.start === ck.start && wk.bucket < ck.bucket)) best = w
        } else best = w
      }
      const lane = laneKey(b, s.key.side, s.key.contract)
      if (best != null) {
        const w = building[best]
        w.parts.push(i)
        w.low = Math.min(w.low, b)
        w.high = Math.max(w.high, b)
        w.minReach = Math.min(w.minReach, reach(i))
        laneWall.set(lane, best)
      } else {
        building.push({ parts: [i], low: b, high: b, minReach: reach(i) })
        laneWall.set(lane, building.length - 1)
      }
    }
    return building.map(w => {
      const parts = w.parts.map(i => segments[i])
      let end: number | null = null
      if (!parts.some(p => p.endMs == null)) {
        for (const p of parts) if (p.endMs != null) end = end == null ? p.endMs : Math.max(end, p.endMs)
      }
      return { key: parts[0].key, segments: parts, startMs: parts[0].key.start, endMs: end }
    })
  }

  /** 画的先后：drawNotional 从大到小，一样的先起的在前，再按 key.id。返回 a 是否排在 b 前面。 */
  static drawOrder(a: OrderFlowGroup, b: OrderFlowGroup): boolean {
    if (a.drawNotional !== b.drawNotional) return a.drawNotional > b.drawNotional
    if (a.firstSeenMs !== b.firstSeenMs) return a.firstSeenMs < b.firstSeenMs
    return OrderFlowKey.id(a.key) < OrderFlowKey.id(b.key)
  }

  /** drawOrder 的 Array.sort 比较器。 */
  static compareDrawOrder(a: OrderFlowGroup, b: OrderFlowGroup): number {
    return OrderFlowGroup.drawOrder(a, b) ? -1 : OrderFlowGroup.drawOrder(b, a) ? 1 : 0
  }

  /** 把一批单切段、去碎屑、并墙，按 drawOrder 排好。 */
  static groups(orders: BigOrder[], gapMs: number = OrderFlowGroup.minMergeGapMs, minLifeMs = 0, step: number | null = null): OrderFlowGroup[] {
    const parts = OrderFlowGroup.dropShortLived(OrderFlowGroup.segments(orders, gapMs), minLifeMs)
    const out: OrderFlowGroup[] = []
    for (const w of OrderFlowGroup.walls(parts, gapMs)) {
      const g = wallGroup(w, step)
      if (g) out.push(g)
    }
    return out.sort(OrderFlowGroup.compareDrawOrder)
  }
}

// ------------------------------------------------------------------ 详情卡尺寸与摆位

export interface OrderFlowCardPlacement {
  /** true = 卡在下半边、贴主图下沿（带在上半边）；false = 卡在上半边、贴图例下的上沿。 */
  below: boolean
  /** true = 卡贴绘图区左边（焦点在右半边）。 */
  leading: boolean
  /** 卡能占的那一段：top 起、高 maxHeight；卡在这段里贴远端（below 贴底，否则贴顶）。 */
  top: number
  maxHeight: number
  /** 卡最宽多少（85% 绘图区，或为躲 K 线收窄后的宽）。 */
  maxWidth: number
  /** 两行卡。 */
  compact: boolean
  /** 卡的高度段和十字线那根 K 线躲不开。 */
  coversCandle: boolean
}

/** 十字线那根 K 线在图上占的范围（影线高低、实体左右）。 */
export interface OrderFlowCardCandle { left: number; right: number; top: number; bottom: number }

/** 详情卡的尺寸上限与摆位：卡放在焦点带所在半边的对面、贴主图的远端边缘，横向摆在焦点的另一侧，躲开十字线那根 K 线。 */
export const OrderFlowCardBudget = {
  widthFraction: 0.85,
  heightFraction: 0.55,
  bandGap: 6,
  sideInset: 8,
  candleGap: 4,
  fullHeight: 80,
  compactHeight: 60,
  compactBelow: 200,
  minWidth: 220,

  maxWidth(plotW: number): number { return Math.max(0, plotW * OrderFlowCardBudget.widthFraction) },

  placement(o: { bandY: number; bandHalf: number; top: number; bottom: number; mainHeight: number; plotW: number; anchorX: number; candle: OrderFlowCardCandle | null }): OrderFlowCardPlacement {
    const B = OrderFlowCardBudget
    const { bandY, bandHalf, top, bottom, mainHeight, plotW, anchorX, candle } = o
    const compactMain = bottom - top < B.compactBelow
    const leading = anchorX > plotW / 2
    const fullW = B.maxWidth(plotW)
    const cap = mainHeight * B.heightFraction
    const zone = (below: boolean) => {
      const room = below ? bottom - (bandY + bandHalf + B.bandGap) : (bandY - bandHalf - B.bandGap) - top
      const h = Math.max(0, Math.min(cap, room))
      return { top: below ? bottom - h : top, height: h }
    }
    const cardSpan = (below: boolean, height: number, compact: boolean) => {
      const h = Math.min(height, compact ? B.compactHeight : B.fullHeight)
      return below ? { lo: bottom - h, hi: bottom } : { lo: top, hi: top + h }
    }
    const make = (below: boolean): { p: OrderFlowCardPlacement; fits: boolean } => {
      const z = zone(below)
      const compact = compactMain || z.height < B.fullHeight
      const p: OrderFlowCardPlacement = { below, leading, top: z.top, maxHeight: z.height, maxWidth: fullW, compact, coversCandle: false }
      if (!candle) return { p, fits: true }
      const span = cardSpan(below, z.height, compact)
      const overlaps = candle.top < span.hi + B.candleGap && candle.bottom > span.lo - B.candleGap
      if (!overlaps) return { p, fits: true }
      const side = leading ? candle.left - B.candleGap - B.sideInset : plotW - B.sideInset - (candle.right + B.candleGap)
      if (side >= B.minWidth) {
        p.maxWidth = Math.min(fullW, side)
        return { p, fits: true }
      }
      p.coversCandle = true
      return { p, fits: false }
    }
    const below = bandY <= (top + bottom) / 2
    const first = make(below)
    if (first.fits) return first.p
    const other = make(!below)
    if (other.fits && other.p.maxHeight >= (other.p.compact ? B.compactHeight : B.fullHeight)) return other.p
    return first.p
  },
}
