// 移植自 KanpanChart/Tests/KanpanChartTests/OrderFlowChartTests.swift（数值部分）
// + KanpanCore/Tests/KanpanCoreTests/OrderFlow*Tests.swift 里分组 / 厚度 / 墙合并的部分。
//
// 夹具直接读 iOS 那边的定版快照（KanpanChart/Tests/KanpanChartTests/Fixtures/snapshot.json），与 Swift 的
// AxisWidthTests.renderer() 同一份：BTCUSDT 1h、402 × 520、副图成交量 + MACD、线性价格轴、nowMs = 末根 + 30 分钟。
//
// 跳过的 Swift 用例（依赖 UIKit / ChartView / 后台队列，网页这边没有对应物或另有测法）：
//   · 位图类：linesStayOutOfLegend、pixels，rankRoles / labels / hoverFocus 里 UIGraphicsImageRenderer 画图取像素那一截；
//   · ChartView 层：selectAndDeselect、crosshairSweepCounts、invalidationAndInset 里 ChartView.changed 那一截；
//   · 后台墙缓存：background*、rendererServesStale（网页的墙缓存同步算，没有「先拿旧份顶着」）；
//   · bench（性能基准）；derivedMatchesNaive 里「改 books 后派生量跟着更新」那一截（网页的组建好后不可变，没有可写的 books）。
// 另：测试环境没有 canvas，textWidth 走近似宽度，签宽与 Swift 的像素值不逐位相同，涉及签宽的断言都按规则算、不写死像素。
import { describe, expect, it } from 'vitest'
// @ts-expect-error Web 的 tsconfig 不带 @types/node，这里只在 vitest（node 环境）里用
import { readFileSync } from 'node:fs'
import { BarSeries } from '../src/m/chart/series'
import type { Interval } from '../src/m/chart/series'
import { AICoinBehavior, Layout, ViewMath, ViewWindow, candleMetrics, pOf, priceTransform, yOf } from '../src/m/chart/geometry'
import { effectivePriceMode, makeOrderBook, makeState, withInput, withOverlay, withViewport } from '../src/m/chart/state'
import type { Crosshair } from '../src/m/chart/state'
import { ChartRenderer } from '../src/m/chart/renderer'
import { decodeDrawing } from '../src/m/chart/draw/drawing'
import type { Rect } from '../src/m/chart/renderer'
import { FALLBACK_COLORS, contrast, orderFlowFor, orderFlowOnDark, orderFlowOnLight, orderFlowUnfilled, rgba } from '../src/m/chart/paint'
import type { BigOrder, BookSide, Product, Status } from '../src/orderflow/types'
import { isContract, orderId } from '../src/orderflow/types'
import {
  OrderFlowCardBudget, OrderFlowGroup, OrderFlowKey, THICKNESS_TIERS, defaultOrderFlowDisplay, thicknessQuarters, thicknessTier,
} from '../src/m/chart/orderflowGroup'
import type { OrderFlowDisplay, OrderFlowGroupKey, OrderFlowSegment, OrderFlowSnapshot } from '../src/m/chart/orderflowGroup'
import {
  OrderFlowStyle as S, OrderFlowWallCache, candleHit, drawOrderFlow, drawOrderFlowBracket, drawOrderFlowHover, drawOrderFlowLabels, hasOrderFlow,
  mixHex, orderFlowAmount, orderFlowBands, orderFlowBaseColor, orderFlowColor, orderFlowEntry, orderFlowFocus,
  drawingLabelBoxes, orderFlowFrameUnfiltered, orderFlowHit, orderFlowHitBands, orderFlowHoversBand, orderFlowIsSelected, orderFlowLabelInk,
  orderFlowLabelWidth, orderFlowMergeGapMs, orderFlowMergeNoise, orderFlowMinLifeMs,
} from '../src/m/chart/renderer.orderflow'
import type { OrderFlowBand, OrderFlowFrame, OrderFlowLabel } from '../src/m/chart/renderer.orderflow'

// ------------------------------------------------------------------ 夹具

const FIXTURE = new URL('../../KanpanChart/Tests/KanpanChartTests/Fixtures/snapshot.json', import.meta.url)
const fx = JSON.parse(readFileSync(FIXTURE, 'utf8')) as {
  symbol: string; interval: string; t0: number; step: number; p: number
  open: number[]; high: number[]; low: number[]; close: number[]; volume: number[]
}
const W = 402, H = 520

function fixtureSeries(): BarSeries {
  return new BarSeries({
    symbol: fx.symbol, interval: fx.interval as Interval, t0: fx.t0, step: fx.step,
    open: fx.open.slice(), high: fx.high.slice(), low: fx.low.slice(), close: fx.close.slice(), volume: fx.volume.slice(),
  })
}

/** 可复现的洗牌（Swift 用 shuffled()，结论与顺序无关）。 */
function shuffled<T>(xs: T[], seed = 7): T[] {
  const a = xs.slice()
  let s = seed
  for (let i = a.length - 1; i > 0; i--) {
    s = (s * 1103515245 + 12345) & 0x7fffffff
    const j = s % (i + 1);
    [a[i], a[j]] = [a[j], a[i]]
  }
  return a
}

const minX = (r: Rect) => r.x, maxX = (r: Rect) => r.x + r.w, minY = (r: Rect) => r.y, maxY = (r: Rect) => r.y + r.h
const midX = (r: Rect) => r.x + r.w / 2, midY = (r: Rect) => r.y + r.h / 2
const intersects = (a: Rect, b: Rect) => minX(a) < maxX(b) && maxX(a) > minX(b) && minY(a) < maxY(b) && maxY(a) > minY(b)
const keyOf = (o: BigOrder): OrderFlowGroupKey => OrderFlowKey.of(o)
const eqKey = (a: OrderFlowGroupKey | null | undefined, b: OrderFlowGroupKey | null | undefined) =>
  a != null && b != null && OrderFlowKey.equal(a, b)
const bandKey = (b: OrderFlowBand) => b.group.key
const ids = (f: OrderFlowFrame) => f.bands.map(b => OrderFlowKey.id(b.group.key)).join(', ')

function order(product: Product, side: BookSide, price: number, firstSeen: number, o: {
  end?: number | null; status?: Status; notional?: number; initial?: number; filled?: number; threshold?: number; bucket?: number
} = {}): BigOrder {
  return {
    venueID: `binance:${product}:X`, exchange: '币安', product, side, bucket: o.bucket ?? 0, price, firstSeenMs: firstSeen,
    endMs: o.end ?? null, status: o.status ?? 'live', initialNotional: o.initial ?? 10_000_000,
    notional: o.notional ?? 10_000_000, filledNotional: o.filled ?? 0, threshold: o.threshold ?? 5_000_000, vanishedNotional: null,
  }
}

/** 一只可改的图表：Swift 里 `var r` 的 `r.state.xxx = …` 在这里换成新的不可变 state。 */
class Rig {
  r: ChartRenderer
  constructor(r: ChartRenderer) { this.r = r }
  get b(): BarSeries { return this.r.state.input.series }
  get L(): Layout { return this.r.layout(W, H) }
  get range() { return this.r.priceRange(W, H) }
  get flow(): OrderFlowSnapshot { return this.r.state.overlay.orderFlow! }
  /** 快照换一份新的（逐单拷贝：真实 feed 也是每帧交新的）。 */
  setFlow(p: Partial<OrderFlowSnapshot>): void {
    const cur = this.r.state.overlay.orderFlow
    const next = { ...(cur as OrderFlowSnapshot), ...p }
    next.orders = (p.orders ?? cur?.orders ?? []).map(o => ({ ...o }))
    next.thresholds = { ...(p.thresholds ?? cur?.thresholds ?? {}) }
    this.r.state = withOverlay(this.r.state, { orderFlow: next })
  }
  get orders(): BigOrder[] { return this.flow.orders.map(o => ({ ...o })) }
  set orders(os: BigOrder[]) { this.setFlow({ orders: os }) }
  editOrder(i: number, patch: Partial<BigOrder>): void {
    const os = this.orders
    Object.assign(os[i], patch)
    this.orders = os
  }
  set step(step: number) { this.setFlow({ thresholds: { ...this.flow.thresholds, step } }) }
  select(key: OrderFlowGroupKey | null): void { this.r.state = withOverlay(this.r.state, { orderFlowSelected: key }) }
  cross(c: Crosshair | null): void { this.r.state = withOverlay(this.r.state, { crosshair: c }) }
  display(d: OrderFlowDisplay): void { this.r.state = withOverlay(this.r.state, { orderFlowDisplay: d }) }
  frame(): OrderFlowFrame { const L = this.L; return orderFlowBands(this.r, L.main, this.range, L) }
  focus() { return orderFlowFocus(this.r, W, H) }
  hit(x: number, y: number) { return orderFlowHit(this.r, x, y, W, H) }
  y(price: number): number { return yOf(price, this.L.main, this.range, effectivePriceMode(this.r.state)) }
  price(y: number): number { return pOf(y, this.L.main, this.range, effectivePriceMode(this.r.state)) }
  get spacing(): number { return this.r.spacing(this.L.plotW) }
  x(i: number): number { return this.r.state.viewport.view.x(this.b.time(i), this.L.plotW) }
  barLeft(i: number): number { return this.x(i) - this.spacing / 2 }
  barRight(i: number): number { return this.x(i) + this.spacing / 2 }
  /** 视野往右多留 px 的空白（最新那根离主图右缘 px）。 */
  clearRight(px = 140): void {
    const v = this.r.state.viewport.view
    this.r.state = withViewport(this.r.state, { view: new ViewWindow(v.to + px / this.L.plotW * v.span, v.span) })
  }
  /** 画出来的蜡烛（含影线，3 倍屏尺寸）里和 rect 相交的那些根的下标。 */
  candlesUnder(rc: Rect): number[] {
    const L = this.L, b = this.b, range = this.range, mode = effectivePriceMode(this.r.state)
    const m = candleMetrics(this.spacing, 3)
    const halfW = Math.max(m.bodyW, m.wickW) / 2
    const out: number[] = []
    for (let i = 0; i < b.count; i++) {
      const cx = this.x(i)
      const hiY = yOf(b.high[i], L.main, range, mode), loY = yOf(b.low[i], L.main, range, mode)
      if (cx + halfW > minX(rc) && cx - halfW < maxX(rc) && hiY < maxY(rc) && loY > minY(rc)) out.push(i)
    }
    return out
  }
}

/** AxisWidthTests.renderer()：定版快照、线性价格轴。 */
function baseRig(): Rig {
  const b = fixtureSeries()
  const L = new Layout(W, H, ['VOL', 'MACD'])
  const st = makeState({
    series: b, symbol: { symbol: b.symbol, base: b.symbol, priceDecimals: 2 },
    view: ViewMath.reset(b, L.plotW, AICoinBehavior.initialSpacing), price: priceTransform('linear'),
    subs: ['VOL', 'MACD'], decimals: 2, nowMs: b.lastTime + 1_800_000,
  })
  return new Rig(new ChartRenderer(st))
}

/** 最新价上下摆几单：U 本位买（挂着）、现货买卖、币本位卖、一条已成交买、一条已撤销卖。 */
function fixtureRig(): { g: Rig; orders: BigOrder[] } {
  const g = baseRig()
  const b = g.b
  const price = b.close[b.count - 1]
  const d = price * 0.002
  const seen = b.time(b.count - 10) + 1
  const ended = b.time(b.count - 4) + 1
  const orders = [
    order('usdtPerp', 'bid', price - d, seen, { bucket: 1 }),
    order('spot', 'bid', price - 2 * d, seen, { notional: 1_500_000, initial: 1_500_000, threshold: 1_000_000, bucket: 2 }),
    order('spot', 'ask', price + 2 * d, seen, { notional: 1_500_000, initial: 1_500_000, threshold: 1_000_000, bucket: 3 }),
    order('coinPerp', 'ask', price + d, b.firstTime - 60_000, { notional: 5_300_000, initial: 8_000_000, filled: 2_014_000, bucket: 4 }),
    order('usdtPerp', 'bid', price - 3 * d, seen, { end: ended, status: 'filled', filled: 9_000_000, bucket: 5 }),
    order('delivery', 'ask', price + 3 * d, seen, { end: ended, status: 'cancelled', bucket: 6 }),
  ]
  g.r.state = withOverlay(g.r.state, {
    orderFlow: { symbol: b.symbol, phase: 'ready', orders, asOfMs: seen + 12 * 60_000, thresholds: {} },
  })
  return { g, orders }
}

/** 同一桶（合约买 1 桶）上的一单。 */
function laneOrder(venue: string, firstSeen: number, price: number, o: { end?: number; notional?: number; filled?: number } = {}): BigOrder {
  const notional = o.notional ?? 10_000_000, filled = o.filled ?? 0
  const x = order('usdtPerp', 'bid', price, firstSeen, {
    end: o.end, status: o.end == null ? 'live' : filled > 0 ? 'filled' : 'cancelled',
    notional, initial: notional, filled, bucket: 1,
  })
  x.venueID = venue
  return x
}

/** 按步长摆一单：桶号 bucket、价在桶中间；默认合约卖、10M。 */
function wallOrder(g: Rig, step: number, bucket: number, o: {
  side?: BookSide; product?: Product; venue?: string; from: number; to?: number; notional?: number
}): BigOrder {
  const b = g.b, product = o.product ?? 'usdtPerp', notional = o.notional ?? 10_000_000
  const x = order(product, o.side ?? 'ask', (bucket + 0.5) * step, b.time(b.count - o.from) + 1, {
    end: o.to == null ? null : b.time(b.count - o.to) + 1, status: o.to == null ? 'live' : 'cancelled',
    notional, initial: notional, threshold: product === 'spot' ? 1_000_000 : 5_000_000, bucket,
  })
  x.venueID = o.venue ?? 'binance:usdtPerp:X'
  return x
}

/** 步长取最新价的万分之一。 */
function wallRig(): { g: Rig; step: number; b0: number } {
  const { g } = fixtureRig()
  const p = g.b.close[g.b.count - 1]
  const step = p * 0.0001
  g.step = step
  return { g, step, b0: Math.floor(p / step) }
}

const seg = (bucket: number, start: number, end: number | null): OrderFlowSegment =>
  ({ key: { bucket, side: 'ask', contract: true, start }, members: [], endMs: end })

/** 已结束的签落在规则允许的几处之一。 */
function endedLabelAtAllowedSpot(label: OrderFlowLabel, band: OrderFlowBand, plotW: number): boolean {
  const inset = S.labelInset, lift = S.labelLineGap
  const f = label.frame, l = band.frame
  const xR = Math.min(maxX(l) + inset, plotW - inset - f.w), xL = maxX(l) - inset - f.w
  const centered = Math.abs(midY(f) - midY(l)) < 1e-9
  const offLine = Math.abs(maxY(f) - (minY(l) - lift)) < 1e-9 || Math.abs(minY(f) - (maxY(l) + lift)) < 1e-9
  if (Math.abs(minX(f) - xR) < 1e-9) return centered || offLine
  if (minX(f) <= xL + 1e-9 && minX(f) >= Math.max(0, minX(l)) - 1e-9) return offLine
  return minX(f) > xR && centered
}

const bandAt = (f: OrderFlowFrame, bucket: number): OrderFlowBand | undefined => f.bands.find(x => x.group.key.bucket === bucket)

/** 测试环境没有 canvas：一只什么都接、什么都不画的 2D 上下文（measureText 给 10 宽）。 */
function mockCtx(): CanvasRenderingContext2D {
  const t: Record<string | symbol, unknown> = {}
  return new Proxy(t, {
    get: (o, k) => (k in o ? o[k] : () => ({ width: 10 })),
    set: (o, k, v) => { o[k] = v; return true },
  }) as unknown as CanvasRenderingContext2D
}

/** 视野右缘不动、跨度缩到 1/k（放大 k 倍）。 */
function zoomIn(g: Rig, k: number): void {
  const v = g.r.state.viewport.view
  g.r.state = withViewport(g.r.state, { view: new ViewWindow(v.to, v.span / k) })
}

/** 视野右缘挪到 to、跨度不变。 */
function setView(g: Rig, to: number): void {
  const v = g.r.state.viewport.view
  g.r.state = withViewport(g.r.state, { view: new ViewWindow(to, v.span) })
}

/** Palette.hue：HSV 色相（度）。 */
function hue(h: string): number {
  const { r, g, b } = rgba(h)
  const hi = Math.max(r, g, b), lo = Math.min(r, g, b), d = hi - lo
  if (d === 0) return 0
  const x = hi === r ? (g - b) / d : hi === g ? 2 + (b - r) / d : 4 + (r - g) / d
  return ((x * 60) % 360 + 360) % 360
}
/** Palette.hueDistance：色相环上的最短角距。 */
function hueDistance(a: string, b: string): number {
  const d = Math.abs(hue(a) - hue(b)) % 360
  return Math.min(d, 360 - d)
}
/** 两色在 RGB 里的欧氏距离（0…√3）。 */
function rgbDistance(a: string, b: string): number {
  const x = rgba(a), y = rgba(b)
  return Math.hypot(x.r - y.r, x.g - y.g, x.b - y.b)
}

// ================================================================== 图表层（OrderFlowChartTests.swift）

describe('主力订单流 · 图表', () => {
  it('一桶一单时一单一条：首见那根左缘起，挂着的画到主图右缘、结束的画到结束那根右缘', () => {
    const { g, orders } = fixtureRig()
    const L = g.L, f = g.frame(), b = g.b
    expect(f.bands.length).toBe(orders.length)
    expect(f.bands.every(x => !x.thin)).toBe(true)
    const left = g.barLeft(b.count - 10), endRight = g.barRight(b.count - 4)
    for (const band of f.bands) {
      if (band.group.firstSeenMs < b.firstTime) expect(minX(band.frame)).toBe(0)
      else expect(Math.abs(minX(band.frame) - Math.max(0, left))).toBeLessThan(0.001)
      if (band.group.isLive) expect(Math.abs(maxX(band.frame) - L.plotW)).toBeLessThan(0.001)
      else expect(Math.abs(maxX(band.frame) - endRight)).toBeLessThan(0.001)
    }
  })

  it('细线：主 2（挂着 2.5）、次 1 / 70%、底噪 1 / ≤ 35%、被压 1；括号宽 3、70%；线粗不看名义', () => {
    expect(S.mainLine).toBe(2); expect(S.mainLiveLine).toBe(2.5)
    expect(S.secondaryLine).toBe(1); expect(S.noiseLine).toBe(1); expect(S.thinLine).toBe(1)
    expect(S.secondaryAlpha).toBe(0.7); expect(S.noiseAlpha).toBeLessThanOrEqual(0.35)
    expect(S.bracketWidth).toBe(3); expect(S.bracketAlpha).toBe(0.7)
    expect(S.labelAlpha).toBe(0.85); expect(S.labelMax).toBe(6)
    expect(THICKNESS_TIERS).toBe(5)
    const { g } = fixtureRig()
    const f = g.frame()
    expect(f.bands.every(x => x.frame.h >= 1 && x.frame.h <= 2.5)).toBe(true)
    for (const band of f.bands) {
      if (band.role !== 'main' || band.thin) continue
      expect(band.frame.h).toBe(band.group.isLive ? 2.5 : 2)
      expect(band.alpha).toBe(1)
    }
    expect(f.bands.find(x => x.group.key.bucket === 1)?.frame.h).toBe(2.5)
    expect(f.bands.find(x => x.group.key.bucket === 5)?.frame.h).toBe(2)
  })

  it('合并：同桶同侧同类、时间上连着的合成一条，不同类、不同侧不合；粗细按合计', () => {
    const { g, orders } = fixtureRig()
    const p = orders[0].price, seen = orders[0].firstSeenMs, b = g.b
    const early = b.time(b.count - 14) + 1
    const ended = b.time(b.count - 6) + 1
    const contract = (product: Product, venue: string, o: { exchange?: string; notional?: number; firstSeen?: number; end?: number; status?: Status; filled?: number } = {}) => {
      const notional = o.notional ?? 5_000_000
      const x = order(product, 'bid', p, o.firstSeen ?? seen, { end: o.end, status: o.status, notional, initial: notional, filled: o.filled, bucket: 1 })
      x.venueID = venue; x.exchange = o.exchange ?? '币安'
      return x
    }
    const spot = (side: BookSide, venue: string, exchange: string) => {
      const x = order('spot', side, p, seen, { notional: 1_000_000, initial: 1_000_000, threshold: 1_000_000, bucket: 1 })
      x.venueID = venue; x.exchange = exchange
      return x
    }
    g.orders = [
      contract('usdtPerp', 'binance:usdtPerp:X', { firstSeen: early, end: ended, status: 'cancelled' }),
      contract('coinPerp', 'binance:coinPerp:X', { filled: 100_000 }),
      contract('delivery', 'binance:delivery:X'),
      contract('usdtPerp', 'okx:usdtPerp:X', { exchange: 'OKX' }),
      spot('bid', 'binance:spot:X', '币安'), spot('bid', 'okx:spot:X', 'OKX'), spot('bid', 'coinbase:spot:X', 'Coinbase'),
      spot('ask', 'binance:spot:X', '币安'),
    ]
    const f = g.frame()
    expect(f.bands.length, '合约买一条、现货买一条、现货卖一条').toBe(3)
    const c = f.bands.find(x => eqKey(bandKey(x), { bucket: 1, side: 'bid', contract: true, start: early }))!
    expect(c).toBeTruthy()
    expect(c.group.books.length).toBe(4); expect(c.group.members.length).toBe(4)
    expect(c.group.notional).toBe(20_000_000)
    expect(c.group.tier).toBe(2)
    expect(c.dark, '任何一单被吃过就是深色').toBe(true)
    expect(c.color).toBe(orderFlowBaseColor(g.r, 'bid', true))
    expect(c.color).not.toBe(g.r.colors.up)
    const L = g.L
    expect(Math.abs(minX(c.frame) - g.barLeft(b.count - 14))).toBeLessThan(0.001)
    expect(Math.abs(maxX(c.frame) - L.plotW)).toBeLessThan(0.001)
    const sb = f.bands.find(x => eqKey(bandKey(x), { bucket: 1, side: 'bid', contract: false, start: seen }))!
    expect(sb.group.books.length).toBe(3); expect(sb.group.notional).toBe(3_000_000)
    expect(sb.dark).toBe(false)
    expect(sb.color).toBe(orderFlowUnfilled(orderFlowBaseColor(g.r, 'bid', false), g.r.colors.bg))
    expect(f.bands.some(x => eqKey(bandKey(x), { bucket: 1, side: 'ask', contract: false, start: seen }))).toBe(true)
    expect(f.bidTotal).toBe(15_000_000 + 3_000_000)
    expect(f.askTotal).toBe(1_000_000)

    // 全结束了：终点取最晚的结束。
    g.orders = [
      contract('usdtPerp', 'binance:usdtPerp:X', { end: ended, status: 'cancelled' }),
      contract('coinPerp', 'binance:coinPerp:X', { end: b.time(b.count - 3) + 1, status: 'filled', filled: 5_000_000 }),
    ]
    const one = g.frame().bands[0]
    expect(one.group.endMs).toBe(b.time(b.count - 3) + 1)
    expect(Math.abs(maxX(one.frame) - g.barRight(b.count - 3))).toBeLessThan(0.001)

    // 同一本簿撤了又挂回来：名义取最近那一单、不累加；成交累加。
    const reposted = [
      contract('usdtPerp', 'binance:usdtPerp:X', { notional: 10_000_000, firstSeen: early, end: ended, status: 'cancelled', filled: 1_000_000 }),
      contract('usdtPerp', 'binance:usdtPerp:X', { notional: 6_000_000, filled: 500_000 }),
    ]
    const groups = OrderFlowGroup.groups(reposted)
    expect(groups.length).toBe(1)
    expect(groups[0].books.length).toBe(1); expect(groups[0].books[0].orders).toBe(2)
    expect(groups[0].notional).toBe(6_000_000)
    expect(groups[0].filledNotional).toBe(1_500_000)
    expect(groups[0].isLive).toBe(true); expect(groups[0].endMs).toBeNull()
  })

  it('切段：同桶两单空档远大于容差时画两条，起止、名义、深浅只在段内算', () => {
    const { g, orders } = fixtureRig()
    g.clearRight()
    const b = g.b, p = orders[0].price, L = g.L
    const early = laneOrder('binance:usdtPerp:X', b.time(b.count - 30) + 1, p, { end: b.time(b.count - 29) + 1, notional: 20_000_000, filled: 1_000 })
    const late = laneOrder('okx:usdtPerp:X', b.time(b.count - 12) + 1, p, { notional: 6_000_000 })
    expect(late.firstSeenMs - early.endMs!).toBeGreaterThan(OrderFlowGroup.mergeGapMs(b.step))
    g.orders = [late, early]
    const f = g.frame()
    expect(f.bands.length, ids(f)).toBe(2)
    const a = f.bands.find(x => eqKey(bandKey(x), keyOf(early)))!
    const c = f.bands.find(x => eqKey(bandKey(x), keyOf(late)))!
    expect(a.group.members.map(m => m.venueID)).toEqual([early.venueID])
    expect(c.group.members.map(m => m.venueID)).toEqual([late.venueID])
    expect(Math.abs(minX(a.frame) - g.barLeft(b.count - 30))).toBeLessThan(0.001)
    expect(Math.abs(maxX(a.frame) - g.barRight(b.count - 29))).toBeLessThan(0.001)
    expect(Math.abs(minX(c.frame) - g.barLeft(b.count - 12))).toBeLessThan(0.001)
    expect(Math.abs(maxX(c.frame) - L.plotW)).toBeLessThan(0.001)
    expect(a.group.notional).toBe(20_000_000); expect(c.group.notional).toBe(6_000_000)
    expect(a.dark).toBe(true); expect(c.dark).toBe(false)
    expect(a.group.isLive).toBe(false); expect(a.group.endMs).toBe(early.endMs)
    expect(OrderFlowKey.id(a.group.key)).not.toBe(OrderFlowKey.id(c.group.key))
    expect(OrderFlowKey.id(a.group.key).endsWith(`|${early.firstSeenMs}`)).toBe(true)
    expect(f.bidTotal).toBe(6_000_000)
    expect(eqKey(orderFlowHitBands(f.bands, midX(a.frame), midY(a.frame))?.group.key, a.group.key)).toBe(true)
    g.select(a.group.key)
    expect(g.focus()?.group.members.map(m => m.firstSeenMs)).toEqual([early.firstSeenMs])

    const plotW = L.plotW
    const lc = f.labels.find(l => eqKey(l.key, c.group.key))
    if (lc) {
      expect(lc.text).toBe('6.0M')
      expect(Math.abs(maxX(lc.frame) - (plotW - S.labelInset))).toBeLessThan(1e-9)
    }
    const la = f.labels.find(l => eqKey(l.key, a.group.key))
    if (la) {
      expect(la.text).toBe('20.0M')
      expect(endedLabelAtAllowedSpot(la, a, plotW)).toBe(true)
    }

    // 边界：空档恰好等于容差还并，多 1 ms 就断。
    const gap = OrderFlowGroup.mergeGapMs(b.step)
    const x = laneOrder('binance:usdtPerp:X', 1_000, p, { end: 2_000 })
    const y1 = laneOrder('okx:usdtPerp:X', 2_000 + gap, p, { end: 2_000 + gap + 10 })
    const y2 = laneOrder('okx:usdtPerp:X', 2_000 + gap + 1, p, { end: 2_000 + gap + 10 })
    expect(OrderFlowGroup.segments([x, y1], gap).length).toBe(1)
    expect(OrderFlowGroup.segments([x, y2], gap).length).toBe(2)
    expect(OrderFlowGroup.mergeGapMs(1_000)).toBe(60_000)
    expect(OrderFlowGroup.mergeGapMs(3_600_000)).toBe(3_600_000)
  })

  it('切段：空档小于容差并成一条；区间重叠照旧并', () => {
    const { g, orders } = fixtureRig()
    const b = g.b, p = orders[0].price
    const gap = OrderFlowGroup.mergeGapMs(b.step)
    const first = laneOrder('binance:usdtPerp:X', b.time(b.count - 20) + 1, p, { end: b.time(b.count - 16) + 1, notional: 10_000_000 })
    const again = laneOrder('binance:usdtPerp:X', first.endMs! + gap / 2, p, { end: first.endMs! + gap / 2 + 3 * b.step, notional: 7_000_000 })
    const other = laneOrder('okx:usdtPerp:X', again.firstSeenMs + b.step, p, { notional: 5_000_000 })
    g.orders = [other, again, first]
    const f = g.frame()
    expect(f.bands.length, ids(f)).toBe(1)
    const band = f.bands[0]
    expect(eqKey(bandKey(band), keyOf(first))).toBe(true)
    expect(band.group.members.length).toBe(3); expect(band.group.books.length).toBe(2)
    expect(band.group.notional).toBe(12_000_000)
    expect(band.group.isLive).toBe(true)
    expect(Math.abs(maxX(band.frame) - g.L.plotW)).toBeLessThan(0.001)
  })

  it('切段：挂着续长、新单并进来、回填把段起点前移，选中的那条都不跳走不丢', () => {
    const { g, orders } = fixtureRig()
    const b = g.b, p = orders[0].price
    const gap = OrderFlowGroup.mergeGapMs(b.step)
    const wall = laneOrder('binance:usdtPerp:X', b.time(b.count - 12) + 1, p)
    const old = laneOrder('binance:usdtPerp:X', b.time(b.count - 40) + 1, p, { end: b.time(b.count - 39) + 1 })
    g.orders = [old, wall]
    const key = g.frame().bands.find(x => x.group.isLive)!.group.key
    expect(eqKey(key, keyOf(wall))).toBe(true)
    g.select(key)
    expect(eqKey(g.focus()?.group.key, key)).toBe(true)

    // 1. 续长。
    g.setFlow({ asOfMs: g.flow.asOfMs + 30 * 60_000 })
    g.editOrder(1, { notional: 14_000_000 })
    let focus = g.focus()!
    expect(eqKey(focus.group.key, key)).toBe(true); expect(focus.selected).toBe(true); expect(focus.group.notional).toBe(14_000_000)
    expect(g.frame().bands.some(x => eqKey(bandKey(x), key))).toBe(true)

    // 2. 别家新挂一单并进这一段。
    const joined = laneOrder('okx:usdtPerp:X', b.time(b.count - 3) + 1, p, { notional: 5_000_000 })
    g.orders = [...g.orders, joined]
    focus = g.focus()!
    expect(eqKey(focus.group.key, key)).toBe(true); expect(focus.group.books.length).toBe(2)

    // 3. 原先那单撤了、容差内又挂回来。
    g.editOrder(1, { status: 'cancelled', endMs: b.time(b.count - 2) + 1 })
    g.orders = [...g.orders, laneOrder('binance:usdtPerp:X', b.time(b.count - 2) + 1 + gap / 2, p)]
    focus = g.focus()!
    expect(eqKey(focus.group.key, key)).toBe(true); expect(focus.group.members.length).toBe(3)

    // 4. 回填一单把早先那段和这一段接上：段起点前移，旧键仍认得回来。
    const bridge = laneOrder('binance:delivery:X', old.endMs! + 1, p, { end: wall.firstSeenMs + 1 })
    const os = g.orders; os.splice(1, 0, bridge); g.orders = os
    const lane = g.frame().bands.filter(x => OrderFlowKey.sameLane(bandKey(x), key))
    expect(lane.length).toBe(1)
    const merged = lane[0]
    expect(eqKey(bandKey(merged), keyOf(old))).toBe(true)
    focus = g.focus()!
    expect(eqKey(focus.group.key, merged.group.key)).toBe(true); expect(focus.selected).toBe(true)
    expect(orderFlowIsSelected(g.r, merged.group)).toBe(true)
    const lone = OrderFlowGroup.groups([old], gap)[0]
    expect(lone.covers(key)).toBe(false)
  })

  it('并墙：同侧同类、桶号相邻、时间连着的段并成一堵；隔一桶、不同类、不同侧、时间断开的不并', () => {
    const { g, step, b0 } = wallRig()
    const a = wallOrder(g, step, b0 + 5, { from: 20 })
    const bMid = wallOrder(g, step, b0 + 6, { venue: 'okx:usdtPerp:X', from: 15, to: 5 })
    const c = wallOrder(g, step, b0 + 7, { from: 10 })
    const skip = wallOrder(g, step, b0 + 9, { from: 40, to: 35 })
    const spot = wallOrder(g, step, b0 + 8, { product: 'spot', venue: 'binance:spot:X', from: 10, notional: 2_000_000 })
    const bid = wallOrder(g, step, b0 + 8, { side: 'bid', from: 10 })
    const old = wallOrder(g, step, b0 + 4, { from: 60, to: 50 })
    g.orders = [c, skip, spot, a, bid, old, bMid]
    const f = g.frame()
    expect(f.bands.length, ids(f)).toBe(5)
    const wall = f.bands.find(x => eqKey(bandKey(x), keyOf(a)))!
    const gr = wall.group
    expect(gr.bucketCount).toBe(3); expect(gr.bucketLow).toBe(b0 + 5); expect(gr.bucketHigh).toBe(b0 + 7); expect(gr.isRange).toBe(true)
    expect(Math.abs(gr.priceLow - (b0 + 5) * step)).toBeLessThan(1e-9)
    expect(Math.abs(gr.priceHigh - (b0 + 8) * step)).toBeLessThan(1e-9)
    expect(gr.notional).toBe(30_000_000); expect(gr.drawNotional).toBe(30_000_000)
    expect(gr.tier).toBe(2)
    expect(gr.books.length).toBe(3)
    expect(new Set(gr.books.map(x => x.bucket))).toEqual(new Set([b0 + 5, b0 + 6, b0 + 7]))
    expect(gr.books.every(x => Math.abs(x.latest.price - (x.bucket + 0.5) * step) < 1e-9)).toBe(true)
    expect(gr.isLive).toBe(true); expect(gr.endMs).toBeNull()
    expect(wall.role).toBe('main'); expect(wall.thin).toBe(false)
    expect(Math.abs(wall.frame.h - 2.5)).toBeLessThan(1e-9)
    expect(Math.abs(midY(wall.frame) - g.y(gr.price))).toBeLessThan(1e-6)
    const rangeHeight = Math.abs(g.y(gr.priceLow) - g.y(gr.priceHigh))
    const L = g.L
    if (wall.bracket) {
      expect(Math.abs(minY(wall.bracket) - g.y(gr.priceHigh))).toBeLessThan(1e-6)
      expect(Math.abs(maxY(wall.bracket) - g.y(gr.priceLow))).toBeLessThan(1e-6)
      expect(Math.abs(wall.bracket.w - 3)).toBeLessThan(1e-9)
      const label = f.labels.find(l => eqKey(l.key, gr.key))!
      expect(Math.abs(maxX(wall.bracket) - (minX(label.frame) - S.bracketGap))).toBeLessThan(1e-6)
    } else {
      const pane = L.main
      expect(rangeHeight <= wall.frame.h + 1e-9 || g.y(gr.priceHigh) < pane.y || g.y(gr.priceLow) > pane.y + pane.h).toBe(true)
    }
    const b = g.b
    expect(Math.abs(minX(wall.frame) - g.barLeft(b.count - 20))).toBeLessThan(0.001)
    expect(Math.abs(maxX(wall.frame) - L.plotW)).toBeLessThan(0.001)
    expect(f.labels.some(l => eqKey(l.key, gr.key) && l.text === '30.0M')).toBe(true)
    for (const o of [skip, spot, bid, old]) {
      expect(f.bands.some(x => eqKey(bandKey(x), keyOf(o)) && x.group.bucketCount === 1), OrderFlowKey.id(keyOf(o))).toBe(true)
    }
    expect(eqKey(orderFlowHitBands(f.bands, midX(wall.frame), midY(wall.frame))?.group.key, gr.key)).toBe(true)
    const clearOf = (yy: number) => f.bands.every(x => Math.max(0, Math.abs(yy - midY(x.frame)) - Math.max(x.frame.h, S.hitHeight) / 2) > 8.5)
    if (wall.bracket) {
      let yFar: number | null = null
      for (let yy = minY(wall.bracket); yy <= maxY(wall.bracket); yy += 0.5) if (clearOf(yy)) { yFar = yy; break }
      if (yFar != null) {
        expect(eqKey(orderFlowHitBands(f.bands, midX(wall.bracket), yFar)?.group.key, gr.key)).toBe(true)
        expect(eqKey(orderFlowHitBands(f.bands, midX(wall.bracket), yFar, true)?.group.key, gr.key)).toBe(true)
        expect(orderFlowHitBands(f.bands, minX(wall.bracket) - 40, yFar)).toBeNull()
      }
    }
    g.select(gr.key)
    expect(g.focus()?.group.members.length).toBe(3)

    // 连成串与边界。
    const gap = OrderFlowGroup.mergeGapMs(b.step)
    expect(OrderFlowGroup.walls([seg(1, 0, 100), seg(2, 100 + gap, 200 + gap)], gap).length).toBe(1)
    expect(OrderFlowGroup.walls([seg(1, 0, 100), seg(2, 101 + gap, 200 + gap)], gap).length).toBe(2)
    expect(OrderFlowGroup.walls([seg(1, 0, 100), seg(2, 50, 400), seg(3, 300, null)], gap).length).toBe(1)
    expect(OrderFlowGroup.walls([seg(1, 0, 100), seg(3, 0, 100)], gap).length).toBe(2)
    expect(OrderFlowGroup.walls([seg(1, 100_000_000, null), seg(2, 500_000_000, 500_000_001)], gap).length).toBe(1)
    expect(OrderFlowGroup.walls([seg(1, 100_000_000, null), seg(2, 0, 10)], gap).length).toBe(2)
    const key = OrderFlowGroup.walls([seg(2, 50, 400), seg(1, 50, 100), seg(3, 300, null)], gap)[0].key
    expect(key.bucket).toBe(1); expect(key.start).toBe(50)
  })

  it('范围括号：整段范围出了主图（哪怕一端）整枚不画；芯线、金额签、详情卡的区间照旧', () => {
    const { g } = fixtureRig()
    const p = g.b.close[g.b.count - 1]
    const step = p * 0.001
    g.step = step
    const pane = g.L.main
    expect(Math.abs(g.y(p) - g.y(p + step))).toBeGreaterThan(3)
    const top = Math.floor(g.price(pane.y) / step)
    const lo = top - 2
    g.orders = [lo, lo + 1, lo + 2, lo + 3].map(bk => wallOrder(g, step, bk, { from: 20, notional: bk === lo ? 14_000_000 : 10_000_000 }))
    const f = g.frame()
    const wall = f.bands.find(x => x.group.bucketCount === 4)!
    expect(wall, ids(f)).toBeTruthy()
    expect(g.y(wall.group.priceHigh)).toBeLessThan(pane.y)
    expect(midY(wall.frame)).toBeGreaterThanOrEqual(pane.y)
    expect(wall.role).toBe('main'); expect(wall.thin).toBe(false); expect(wall.group.isRange).toBe(true)
    expect(wall.bracket).toBeNull()
    const legendBottom = pane.y + g.r.mainLegendInset(g.L.plotW)
    const shift = legendBottom + S.labelHeight / 2 - midY(wall.frame)
    expect(f.labels.some(l => eqKey(l.key, wall.group.key))).toBe(shift <= S.labelMaxShift)
    g.select(wall.group.key)
    const focus = g.focus()!
    expect(focus.group.isRange).toBe(true); expect(focus.group.bucketCount).toBe(4)

    const mid = Math.floor(p / step) - 2
    g.orders = [mid, mid + 1, mid + 2, mid + 3].map(bk => wallOrder(g, step, bk, { from: 20, notional: bk === mid ? 14_000_000 : 10_000_000 }))
    const inside = g.frame().bands.find(x => x.group.bucketCount === 4)!
    const bracket = inside.bracket!
    expect(bracket).toBeTruthy()
    expect(minY(bracket)).toBeGreaterThanOrEqual(pane.y)
    expect(maxY(bracket)).toBeLessThanOrEqual(pane.y + pane.h)
  })

  it('代表价出了主图的墙不占排名：不能把看得见的墙挤出「主」那 6 位', () => {
    const { g } = fixtureRig()
    const p = g.b.close[g.b.count - 1]
    const step = p * 0.001
    g.step = step
    const pane = g.L.main
    expect(Math.abs(g.y(p) - g.y(p + step))).toBeGreaterThan(3)
    const top = Math.floor(g.price(pane.y) / step)
    const wall = [top - 2, top - 1, top, top + 1].map(bk => wallOrder(g, step, bk, { from: 20, notional: bk === top + 1 ? 40_000_000 : 10_000_000 }))
    const small = [0, 1, 2, 3, 4, 5].map(i => {
      const bk = Math.floor(g.price(pane.y + pane.h * (0.3 + 0.08 * i)) / step)
      return wallOrder(g, step, bk, { side: 'bid', from: 20 + i, notional: 6_000_000 })
    })
    expect(new Set(small.map(o => o.bucket)).size).toBe(6)
    g.orders = [...wall, ...small]
    const f = g.frame()
    expect(g.y((top + 1 + 0.5) * step)).toBeLessThan(pane.y)
    expect(f.bands.some(x => x.group.bucketCount === 4), ids(f)).toBe(false)
    expect(f.bands.length).toBe(6)
    expect(f.bands.every(x => x.role === 'main')).toBe(true)
    expect(f.bands.every(x => midY(x.frame) >= pane.y && midY(x.frame) <= pane.y + pane.h)).toBe(true)
  })

  it('金额：K / M / B / T 一位小数', () => {
    expect(orderFlowAmount(950)).toBe('950')
    expect(orderFlowAmount(5_300_000)).toBe('5.3M')
    expect(orderFlowAmount(1e9)).toBe('1.0B')
    expect(orderFlowAmount(999e9)).toBe('999.0B')
    expect(orderFlowAmount(1.2e12)).toBe('1.2T')
    // 进位到一千就升一档（同 iOS cccf6fff）：原来 999,960 印成「1000.0K」。
    expect(orderFlowAmount(999_960)).toBe('1.0M')
    expect(orderFlowAmount(999_940)).toBe('999.9K')
    expect(orderFlowAmount(999.6)).toBe('1.0K')
    expect(orderFlowAmount(999_960_000_000)).toBe('1.0T')
  })

  it('开着盘口：挂着的签挪到梯子左边、纵向不动；括号跟着签走；没开盘口照旧贴右缘', () => {
    const { g, step, b0 } = wallRig()
    g.clearRight()
    const L = g.L
    const px = g.b.close[g.b.count - 1]
    const wall = [b0, b0 + 1, b0 + 2].map(bk => wallOrder(g, step, bk, { from: 20, notional: 30_000_000 }))
    const farY = L.main.y + L.main.h * 0.85
    const far = wallOrder(g, step, Math.floor(g.price(farY) / step), { side: 'bid', from: 20 })
    g.r.state = withOverlay(g.r.state, {
      depth: makeOrderBook(g.b.symbol, g.b.lastTime,
        [1, 2, 3, 4, 5].map(i => ({ price: px - i * step, quantity: 1 })),
        [1, 2, 3, 4, 5].map(i => ({ price: px + i * step, quantity: 1 }))),
    })
    g.orders = [...wall, far]
    const ladder = g.r.depthEnvelope(L.main, g.range, L)!
    expect(ladder).toBeTruthy()
    expect(Math.abs(ladder.w - 64)).toBeLessThan(1e-9)
    expect(Math.abs(maxX(ladder) - L.plotW)).toBeLessThan(1e-9)
    const f = g.frame()
    const w = f.bands.find(x => x.group.bucketCount === 3)!
    const label = f.labels.find(l => eqKey(l.key, w.group.key))!
    expect(intersects(label.frame, ladder)).toBe(false)
    expect(Math.abs(maxX(label.frame) - (minX(ladder) - S.labelGap))).toBeLessThan(1e-6)
    if (w.bracket) expect(Math.abs(maxX(w.bracket) - (minX(label.frame) - S.bracketGap))).toBeLessThan(1e-6)
    const farLabel = f.labels.find(l => eqKey(l.key, keyOf(far)))!
    expect(Math.abs(maxX(farLabel.frame) - (L.plotW - S.labelInset))).toBeLessThan(1e-6)
    g.r.state = withOverlay(g.r.state, { depth: null })
    const back = g.frame().labels.find(l => eqKey(l.key, w.group.key))!
    expect(Math.abs(maxX(back.frame) - (L.plotW - S.labelInset))).toBeLessThan(1e-6)
  })

  it('范围括号：同一 x 上两枚纵向重叠只留名义大的那枚，不错开 x', () => {
    const { g } = fixtureRig()
    g.clearRight()
    const p = g.b.close[g.b.count - 1]
    const step = p * 0.001
    g.step = step
    expect(Math.abs(g.y(p) - g.y(p + step))).toBeGreaterThan(3)
    const b0 = Math.floor(p / step) - 4
    const ask = [0, 1, 2, 3, 4].map(i => wallOrder(g, step, b0 + i, { side: 'ask', from: 20, notional: i === 1 ? 14_000_000 : 10_000_000 }))
    const bid = [3, 4, 5, 6, 7].map(i => wallOrder(g, step, b0 + i, { side: 'bid', from: 20, notional: i === 6 ? 12_000_000 : 6_000_000 }))
    g.orders = [...ask, ...bid]
    const f = g.frame()
    const big = f.bands.find(x => x.group.side === 'ask' && x.group.bucketCount === 5)!
    const small = f.bands.find(x => x.group.side === 'bid' && x.group.bucketCount === 5)!
    expect(big, ids(f)).toBeTruthy(); expect(small).toBeTruthy()
    expect(big.group.notional).toBeGreaterThan(small.group.notional)
    expect(big.role).toBe('main'); expect(small.role).toBe('main'); expect(big.thin).toBe(false); expect(small.thin).toBe(false)
    const kept = big.bracket!
    expect(kept).toBeTruthy()
    expect(small.bracket).toBeNull()
    const bigLabel = f.labels.find(l => eqKey(l.key, big.group.key))!
    const smallLabel = f.labels.find(l => eqKey(l.key, small.group.key))!
    expect(Math.abs(maxX(kept) - (minX(bigLabel.frame) - S.bracketGap))).toBeLessThan(1e-6)
    expect(Math.abs(minX(bigLabel.frame) - minX(smallLabel.frame))).toBeLessThan(1e-6)
    g.orders = bid
    expect(g.frame().bands.find(x => x.group.bucketCount === 5)?.bracket).not.toBeNull()
  })

  it('并墙要成块：接力的段不链成一片，一堵最多 maxWallBuckets 个桶；与输入顺序无关', () => {
    const gap = 60_000, hour = 3_600_000
    const drift = Array.from({ length: 30 }, (_, i) => seg(i, i * hour, i * hour + hour * 3 / 2))
    const driftWalls = OrderFlowGroup.walls(drift, gap)
    expect(driftWalls.every(w => w.segments.length <= 2)).toBe(true)
    expect(driftWalls.length).toBe(15)
    for (const w of driftWalls) {
      const latest = Math.max(...w.segments.map(s => s.key.start))
      const ends = w.segments.map(s => s.endMs).filter((e): e is number => e != null)
      const earliestEnd = ends.length ? Math.min(...ends) + gap : Infinity
      expect(latest).toBeLessThanOrEqual(earliestEnd)
    }
    const row = Array.from({ length: 12 }, (_, i) => seg(100 + i, 1_000 + i, null))
    const rowWalls = OrderFlowGroup.walls(row, gap)
    expect(rowWalls.map(w => w.segments.length).sort((a, b) => a - b)).toEqual([2, 5, 5])
    for (const w of rowWalls) {
      const bs = w.segments.map(s => s.key.bucket)
      expect(Math.max(...bs) - Math.min(...bs) + 1).toBeLessThanOrEqual(OrderFlowGroup.maxWallBuckets)
    }
    const keys = (ws: { key: OrderFlowGroupKey }[]) => new Set(ws.map(w => OrderFlowKey.id(w.key)))
    expect(keys(OrderFlowGroup.walls(row.slice().reverse(), gap))).toEqual(keys(rowWalls))
    expect(keys(OrderFlowGroup.walls(drift.slice().reverse(), gap))).toEqual(keys(driftWalls))
  })

  it('并墙：键跨帧稳定；回填更早的段键前移，旧键按 covers 认回来', () => {
    const { g, step, b0 } = wallRig()
    const a = wallOrder(g, step, b0 + 5, { from: 20 })
    const c = wallOrder(g, step, b0 + 6, { from: 12 })
    g.orders = [a, c]
    const key = keyOf(a)
    expect(g.frame().bands.map(x => OrderFlowKey.id(x.group.key))).toEqual([OrderFlowKey.id(key)])
    g.select(key)
    g.setFlow({ asOfMs: g.flow.asOfMs + 30 * 60_000 })
    g.editOrder(0, { notional: 14_000_000 })
    let focus = g.focus()!
    expect(eqKey(focus.group.key, key)).toBe(true); expect(focus.group.notional).toBe(24_000_000)
    const later = wallOrder(g, step, b0 + 7, { venue: 'okx:usdtPerp:X', from: 3 })
    g.orders = [...g.orders, later]
    focus = g.focus()!
    expect(eqKey(focus.group.key, key)).toBe(true); expect(focus.group.bucketCount).toBe(3)
    const early = wallOrder(g, step, b0 + 4, { venue: 'binance:coinPerp:X', from: 30, to: 2 })
    g.orders = [early, ...g.orders]
    const bands = g.frame().bands
    expect(bands.length).toBe(1)
    const merged = bands[0]
    expect(eqKey(bandKey(merged), keyOf(early))).toBe(true); expect(merged.group.covers(key)).toBe(true)
    focus = g.focus()!
    expect(eqKey(focus.group.key, merged.group.key)).toBe(true); expect(focus.selected).toBe(true)
    expect(orderFlowIsSelected(g.r, merged.group)).toBe(true)
    const other = OrderFlowGroup.groups([wallOrder(g, step, b0 + 5, { from: 60, to: 50 })], undefined, 0, step)[0]
    expect(other.covers(key)).toBe(false); expect(other.looselyCovers(key)).toBe(false)
  })

  it('去碎屑：已结束、活不过一根 K 线的段不画（挂着的留，恰好一根的留）；碎屑不当桥', () => {
    const { g, step, b0 } = wallRig()
    const b = g.b
    const flash = wallOrder(g, step, b0 + 5, { from: 10, to: 10 }); flash.endMs = flash.firstSeenMs + b.step - 1
    const oneBar = wallOrder(g, step, b0 + 9, { from: 10, to: 9 }); oneBar.endMs = oneBar.firstSeenMs + b.step
    const fresh = wallOrder(g, step, b0 + 13, { side: 'bid', from: 1 })
    g.orders = [flash, oneBar, fresh]
    const f = g.frame()
    expect(f.bands.some(x => eqKey(bandKey(x), keyOf(flash)))).toBe(false)
    expect(f.bands.some(x => eqKey(bandKey(x), keyOf(oneBar)))).toBe(true)
    expect(f.bands.some(x => eqKey(bandKey(x), keyOf(fresh)))).toBe(true)
    expect(f.bidTotal).toBe(10_000_000)
    const lo = wallOrder(g, step, b0 + 20, { from: 30, to: 20 })
    const bridge = wallOrder(g, step, b0 + 21, { from: 20, to: 20 }); bridge.endMs = bridge.firstSeenMs + 1
    const hi = wallOrder(g, step, b0 + 22, { from: 20, to: 10 })
    g.orders = [lo, bridge, hi]
    expect(g.frame().bands.length).toBe(2)
    expect(OrderFlowGroup.groups([lo, bridge, hi], undefined, 0, step).length).toBe(1)
    expect(OrderFlowGroup.groups([lo, bridge, hi], undefined, b.step, step).length).toBe(2)
  })

  it('轻点只认主档与次档：底噪点不中（十字线照旧认），44 放宽只给主档，次档按 8 / 4', () => {
    const { g, step, b0 } = wallRig()
    const pane = g.L.main
    const count = 25
    const pitch = (pane.h - 40) / count
    const orders: BigOrder[] = []
    for (let i = 0; i < count; i++) {
      const p = g.price(pane.y + 20 + pitch * i)
      const o = wallOrder(g, step, b0 + 3 * i, { from: 30, to: 5, notional: (40 - i) * 1_250_000 })
      o.price = p
      o.threshold = 5_000_000
      orders.push(o)
    }
    g.orders = orders
    const f = g.frame()
    const noise = f.bands.find(x => eqKey(bandKey(x), keyOf(orders[21])))!
    expect(noise).toBeTruthy()
    expect(noise.role).toBe('noise')
    const secondary = f.bands.find(x => x.role === 'secondary')!
    const main = f.bands.find(x => x.role === 'main')!
    expect(orderFlowHitBands(f.bands, midX(noise.frame), midY(noise.frame), true)?.role).not.toBe('noise')
    expect(orderFlowHitBands([noise], midX(noise.frame), midY(noise.frame), true)).toBeNull()
    expect(eqKey(orderFlowHitBands([noise], midX(noise.frame), midY(noise.frame))?.group.key, noise.group.key)).toBe(true)
    expect(eqKey(g.hit(midX(noise.frame), midY(noise.frame))?.key, noise.group.key)).toBe(false)
    const sh = Math.max(secondary.frame.h, S.hitHeight) / 2
    const sx = midX(secondary.frame), sy = midY(secondary.frame)
    expect(eqKey(orderFlowHitBands([secondary], sx, sy, true)?.group.key, secondary.group.key)).toBe(true)
    expect(eqKey(orderFlowHitBands([secondary], sx, sy + sh + 7.9, true)?.group.key, secondary.group.key)).toBe(true)
    expect(orderFlowHitBands([secondary], sx, sy + sh + 8.1, true)).toBeNull()
    const mh = Math.max(main.frame.h, S.hitHeight) / 2
    const reach = (S.touchTarget - 2 * mh) / 2
    expect(eqKey(orderFlowHitBands([main], midX(main.frame), midY(main.frame) + mh + reach - 0.1, true)?.group.key, main.group.key)).toBe(true)
    let misses = 0, total = 0
    for (let yy = midY(noise.frame) - pitch / 2; yy < midY(noise.frame) + pitch / 2; yy += 2) {
      total += 1
      if (g.hit(midX(noise.frame), yy) == null) misses += 1
    }
    expect(misses * 2, `底噪那一行 ${misses}/${total} 点不中`).toBeGreaterThan(total)
  })

  it('屏内排名：前 6 名主、7–18 名次、其余底噪；挂着的底噪升成次；每帧现排结果确定', () => {
    const { g, step, b0 } = wallRig()
    const pane = g.L.main
    const count = 25
    const pitch = (pane.h - 40) / count
    expect(pitch, `主图够高才摆得开：${pane.h}`).toBeGreaterThanOrEqual(9)
    const orders: BigOrder[] = []
    for (let i = 0; i < count; i++) {
      const p = g.price(pane.y + 20 + pitch * i)
      const o = wallOrder(g, step, b0 + 3 * i, { from: 30, to: i === count - 1 ? undefined : 5, notional: (40 - i) * 1_250_000 })
      o.price = p
      o.threshold = 5_000_000
      orders.push(o)
    }
    g.orders = shuffled(orders)
    const f = g.frame()
    expect(f.bands.length).toBe(count)
    const byKey = new Map(f.bands.map(x => [OrderFlowKey.id(x.group.key), x]))
    orders.forEach((o, i) => {
      const band = byKey.get(OrderFlowKey.id(keyOf(o)))!
      expect(band, `第 ${i + 1} 名`).toBeTruthy()
      const want = i < 6 ? 'main' : i < 18 ? 'secondary' : i === count - 1 ? 'secondary' : 'noise'
      expect(band.role, `第 ${i + 1} 名`).toBe(want)
      if (want === 'main') {
        expect(band.thin).toBe(false); expect(band.frame.h).toBe(o.endMs == null ? 2.5 : 2); expect(band.alpha).toBe(1)
      } else if (want === 'secondary') {
        expect(band.frame.h).toBe(1); expect(band.alpha).toBe(0.7)
      } else {
        expect(band.frame.h).toBe(1); expect(band.alpha).toBe(0.35); expect(band.thin).toBe(false)
      }
      expect(Math.abs(midY(band.frame) - g.y(o.price)), '不挪位').toBeLessThan(1e-9)
    })
    expect(f.labels.every(l => byKey.get(OrderFlowKey.id(l.key))?.role === 'main'), '只有主写金额').toBe(true)
    expect(f.labels.length).toBeGreaterThan(0)
    const firstNonNoise = f.bands.findIndex(x => x.role !== 'noise')
    expect(firstNonNoise).toBeGreaterThanOrEqual(0)
    expect(f.bands.slice(0, firstNonNoise).every(x => x.role === 'noise')).toBe(true)
    expect(f.bands.slice(firstNonNoise).every(x => x.role !== 'noise')).toBe(true)
    // 名义一样的先起的在前。
    const tieEarly = { ...orders[0], firstSeenMs: orders[0].firstSeenMs - 60_000 }
    const e = OrderFlowGroup.make(keyOf(tieEarly), [tieEarly])!
    const l = OrderFlowGroup.make(keyOf(orders[0]), [orders[0]])!
    expect(OrderFlowGroup.drawOrder(e, l)).toBe(true)
    expect(OrderFlowGroup.drawOrder(l, e)).toBe(false)
    // 换个顺序给同一批单，排出来一样。
    const again = g.frame()
    g.orders = orders.slice().reverse()
    const rev = g.frame()
    expect(rev.bands.map(x => [OrderFlowKey.id(x.group.key), x.role, x.frame, x.color, x.alpha, x.thin]))
      .toEqual(again.bands.map(x => [OrderFlowKey.id(x.group.key), x.role, x.frame, x.color, x.alpha, x.thin]))
    expect(rev.labels).toEqual(again.labels)
    const L = g.L
    expect(drawOrderFlow(g.r, mockCtx(), L.main, g.range, L, 3)).toBe(count)
  })

  it('纵向去挤：和已落下的纵向重叠（含 1 间隙）的压成 1 细线、不写金额、不挪位；同价叠着点出大的', () => {
    const { g, orders } = fixtureRig()
    const p = orders[0].price, seen = orders[0].firstSeenMs
    const cy = g.y(p)
    const big = order('usdtPerp', 'bid', p, seen, { notional: 40_000_000, initial: 40_000_000, bucket: 1 })
    const small = order('spot', 'bid', p, seen, { notional: 1_500_000, initial: 1_500_000, filled: 10, threshold: 1_000_000, bucket: 1 })
    const nearPrice = g.price(cy - 3)
    const near = order('coinPerp', 'ask', nearPrice, seen, { bucket: 2 })
    const far = order('delivery', 'ask', g.price(cy - 20), seen, { bucket: 5 })
    g.orders = [small, near, big, far]
    const f = g.frame()
    const find = (o: BigOrder) => f.bands.find(x => eqKey(bandKey(x), keyOf(o)))!
    const bigBand = find(big), smallBand = find(small), nearBand = find(near), farBand = find(far)
    expect(bigBand.thin).toBe(false); expect(bigBand.frame.h).toBe(2.5)
    expect(smallBand.thin).toBe(true); expect(smallBand.frame.h).toBe(1)
    expect(Math.abs(midY(smallBand.frame) - cy), '不挪位').toBeLessThan(1e-9)
    expect(smallBand.dark).toBe(true)
    expect(smallBand.color, '细线仍是本色深浅').toBe(orderFlowBaseColor(g.r, 'bid', false))
    expect(nearBand.thin).toBe(true)
    expect(Math.abs(midY(nearBand.frame) - g.y(nearPrice))).toBeLessThan(1e-9)
    expect(farBand.thin).toBe(false); expect(farBand.frame.h).toBe(2.5)
    expect(f.labels.some(l => eqKey(l.key, smallBand.group.key) || eqKey(l.key, nearBand.group.key)), '细线不写金额').toBe(false)
    const firstThin = f.bands.findIndex(x => x.thin)
    expect(firstThin).toBeGreaterThanOrEqual(0)
    expect(f.bands.slice(firstThin).every(x => x.thin) && f.bands.slice(0, firstThin).every(x => !x.thin)).toBe(true)
    expect(eqKey(orderFlowHitBands(f.bands, midX(nearBand.frame), midY(nearBand.frame))?.group.key, nearBand.group.key)).toBe(true)
    expect(eqKey(orderFlowHitBands(f.bands, midX(smallBand.frame), midY(smallBand.frame))?.group.key, bigBand.group.key)).toBe(true)
    expect(eqKey(orderFlowHitBands(f.bands, midX(bigBand.frame), maxY(bigBand.frame) + 1)?.group.key, bigBand.group.key)).toBe(true)
    expect(eqKey(g.hit(midX(nearBand.frame), midY(nearBand.frame))?.key, nearBand.group.key)).toBe(true)

    // 横向不交叠就不挤。
    const b = g.b
    const before = order('spot', 'bid', p, b.time(b.count - 30) + 1, {
      end: b.time(b.count - 20) + 1, status: 'cancelled', notional: 1_500_000, initial: 1_500_000, threshold: 1_000_000, bucket: 1,
    })
    g.orders = [big, before]
    expect(g.frame().bands.every(x => !x.thin)).toBe(true)

    // 纵向隔 1 以上也不挤；不足 1 算重叠。
    const apart = order('spot', 'bid', g.price(cy + 1.25 + 1 + 1.25 + 0.2), seen, { notional: 1_500_000, initial: 1_500_000, threshold: 1_000_000, bucket: 7 })
    const touching = order('spot', 'ask', g.price(cy - 1.25 - 1 - 1.25 + 0.2), seen, { notional: 1_500_000, initial: 1_500_000, threshold: 1_000_000, bucket: 8 })
    g.orders = [big, apart, touching]
    const h = g.frame()
    expect(h.bands.find(x => eqKey(bandKey(x), keyOf(apart)))?.thin).toBe(false)
    expect(h.bands.find(x => eqKey(bandKey(x), keyOf(touching)))?.thin, '间隙不足 1 算重叠').toBe(true)
  })

  it('金额签：只给主档整条；挂着的贴主图右缘、结束的在结束点旁；纵向撞了名义小的让位（挪 ≤ 32，挪不开就不放）', () => {
    const { g, orders } = fixtureRig()
    g.clearRight()
    const L = g.L
    const inset = S.labelInset, gap = S.labelGap
    const f = g.frame()
    expect(f.labels.length).toBeGreaterThan(0)
    for (const label of f.labels) {
      const band = f.bands.find(x => eqKey(bandKey(x), label.key))!
      expect(band.thin).toBe(false); expect(band.role).toBe('main')
      expect(label.text).toBe(orderFlowAmount(band.group.notional))
      expect(label.fill).toBe(band.color)
      expect(label.ink).toBe(orderFlowLabelInk(mixHex(band.color, g.r.colors.bg, 1 - S.labelAlpha)))
      expect(Math.abs(label.frame.h - S.labelHeight)).toBeLessThan(1e-6)
      expect(Math.abs(midY(label.frame) - midY(band.frame))).toBeLessThanOrEqual(S.labelMaxShift + 1e-9)
      expect(maxX(label.frame), '不进价格刻度列').toBeLessThanOrEqual(L.plotW - inset + 1e-9)
      if (band.group.isLive) {
        expect(Math.abs(maxX(label.frame) - (L.plotW - inset)), '挂着的贴主图右缘').toBeLessThan(1e-9)
      } else {
        const want = Math.min(maxX(band.frame) + inset, L.plotW - inset - label.frame.w)
        const ok = (Math.abs(minX(label.frame) - want) < 1e-9 && Math.abs(midY(label.frame) - midY(band.frame)) < 1e-9)
          || endedLabelAtAllowedSpot(label, band, L.plotW)
        expect(ok, `结束的在结束点旁：${JSON.stringify(label.frame)}，本该 ${want}`).toBe(true)
      }
    }
    f.labels.forEach((a, i) => {
      for (const c of f.labels.slice(i + 1)) {
        expect(maxX(a.frame) <= minX(c.frame) || maxX(c.frame) <= minX(a.frame)
          || maxY(a.frame) + gap <= minY(c.frame) + 1e-9 || maxY(c.frame) + gap <= minY(a.frame) + 1e-9).toBe(true)
      }
    })
    // 5.3M 那条单拿出来照旧写（夹在两条 10M 之间时让位不放）。
    g.orders = [orders[3]]
    expect(g.frame().labels.map(l => l.text)).toEqual(['5.3M'])
    expect(orderFlowLabelInk('#E1D610')).toBe('#141414')
    expect(orderFlowLabelInk('#8A149F')).toBe('#FFFFFF')
    expect(orderFlowLabelInk('#CF09E7')).toBe('#000000')
    expect(orderFlowLabelInk('#5A7DFF')).toBe('#141414')
    expect(f.labels.length).toBeLessThanOrEqual(S.labelMax)

    // 窄段也写：签在结束点右侧那几处。
    const b = g.b
    const p = orders[0].price, cy = g.y(p)
    const narrow = order('usdtPerp', 'bid', p, b.time(b.count - 8) + 1, { end: b.time(b.count - 7) + 2, status: 'cancelled', bucket: 1 })
    g.orders = [narrow]
    const n = g.frame()
    expect(n.bands.length).toBe(1); expect(n.labels.length).toBe(1)
    const nl = n.labels[0]
    const nlWant = Math.min(maxX(n.bands[0].frame) + inset, L.plotW - inset - nl.frame.w)
    expect(minX(nl.frame)).toBeGreaterThanOrEqual(nlWant - 1e-9)
    expect(endedLabelAtAllowedSpot(nl, n.bands[0], L.plotW), JSON.stringify(nl.frame)).toBe(true)

    // 上下隔 6：名义大的签坐在线上方 2，小的挪到它上方。
    const seen = b.time(b.count - 30) + 1
    const big = order('usdtPerp', 'bid', p, seen, { notional: 20_000_000, initial: 20_000_000, bucket: 1 })
    const small = order('coinPerp', 'ask', g.price(cy - 6), seen, { bucket: 2 })
    g.orders = [small, big]
    const c = g.frame()
    expect(c.bands.every(x => !x.thin)).toBe(true)
    expect(c.labels.length).toBe(2)
    const bl = c.labels.find(l => eqKey(l.key, keyOf(big)))!
    const sl = c.labels.find(l => eqKey(l.key, keyOf(small)))!
    const bigLine = c.bands.find(x => eqKey(bandKey(x), keyOf(big)))!
    expect(Math.abs(maxY(bl.frame) - (minY(bigLine.frame) - S.labelLineGap)), '名义大的不挪').toBeLessThan(1e-9)
    expect(maxY(sl.frame), '小的让到上方').toBeLessThanOrEqual(minY(bl.frame) - gap + 1e-9)
    expect(Math.abs(midY(sl.frame) - (cy - 6))).toBeLessThanOrEqual(S.labelMaxShift)

    // 六条主线挤在 20 里。
    const crowd: BigOrder[] = []
    for (let i = 0; i < 6; i++) {
      const even = i % 2 === 0
      const amount = (30 - i) * 1_000_000
      crowd.push(order(even ? 'usdtPerp' : 'coinPerp', even ? 'bid' : 'ask', g.price(cy + 4 * i), seen,
        { notional: amount, initial: amount, bucket: 10 + 3 * i }))
    }
    g.orders = crowd
    const k = g.frame()
    expect(k.bands.every(x => !x.thin) && k.bands.length === 6).toBe(true)
    expect(k.labels.length).toBeLessThan(6)
    expect(k.labels.some(l => eqKey(l.key, keyOf(crowd[0])))).toBe(true)
    k.labels.forEach((a, i) => {
      const line = k.bands.find(x => eqKey(bandKey(x), a.key))!
      expect(Math.abs(midY(a.frame) - midY(line.frame))).toBeLessThanOrEqual(S.labelMaxShift + 1e-9)
      for (const o of k.labels.slice(i + 1)) {
        expect(maxY(a.frame) + gap <= minY(o.frame) + 1e-9 || maxY(o.frame) + gap <= minY(a.frame) + 1e-9).toBe(true)
      }
    })
    // 挤成细线的不写。
    const thin = order('spot', 'bid', p, seen, { notional: 1_500_000, initial: 1_500_000, threshold: 1_000_000, bucket: 1 })
    g.orders = [big, thin]
    expect(g.frame().labels.map(l => OrderFlowKey.id(l.key))).toEqual([OrderFlowKey.id(keyOf(big))])
    expect(drawOrderFlowLabels(g.r, mockCtx(), L.main, g.range, L, 3)).toBe(1)
  })

  it('挂着的签坐在线上方 2、贴右缘，不压线；已结束的在结束点旁；上方会进图例就翻到线下方 2', () => {
    const { g } = fixtureRig()
    const L = g.L
    const legend = g.r.mainLegendInset(L.plotW)
    const lift = S.labelLineGap, inset = S.labelInset
    const b = g.b
    const seen = b.time(b.count - 30) + 1
    const my = L.main.y + L.main.h * 0.5
    const live = order('usdtPerp', 'bid', g.price(my), seen, { bucket: 1 })
    const ended = order('usdtPerp', 'ask', g.price(my + 60), seen, { end: b.time(b.count - 10) + 1, status: 'cancelled', bucket: 2 })
    g.orders = [live, ended]
    const f = g.frame()
    const line = f.bands.find(x => eqKey(bandKey(x), keyOf(live)))!
    const label = f.labels.find(l => eqKey(l.key, line.group.key))!
    expect(Math.abs(maxY(label.frame) - (minY(line.frame) - lift))).toBeLessThan(1e-9)
    expect(intersects(label.frame, line.frame), '不压线').toBe(false)
    expect(Math.abs(maxX(label.frame) - (L.plotW - inset))).toBeLessThan(1e-9)
    const endLine = f.bands.find(x => eqKey(bandKey(x), keyOf(ended)))!
    const endLabel = f.labels.find(l => eqKey(l.key, endLine.group.key))!
    expect(endedLabelAtAllowedSpot(endLabel, endLine, L.plotW)).toBe(true)

    const high = order('usdtPerp', 'bid', g.price(L.main.y + legend + 8), seen, { bucket: 3 })
    g.orders = [high]
    const h = g.frame()
    const hl = h.bands[0], hLabel = h.labels[0]
    expect(hl).toBeTruthy(); expect(hLabel).toBeTruthy()
    expect(Math.abs(minY(hLabel.frame) - (maxY(hl.frame) + lift)), '翻到线下方 2').toBeLessThan(1e-9)
    expect(minY(hLabel.frame)).toBeGreaterThanOrEqual(L.main.y + legend - 1e-9)
    const roomy = order('usdtPerp', 'bid', g.price(L.main.y + legend + 24), seen, { bucket: 4 })
    g.orders = [roomy]
    const k = g.frame()
    const kl = k.bands[0], kLabel = k.labels[0]
    expect(Math.abs(maxY(kLabel.frame) - (minY(kl.frame) - lift))).toBeLessThan(1e-9)
    expect(minY(kLabel.frame)).toBeGreaterThanOrEqual(L.main.y + legend - 1e-9)
  })

  it('金额签不进顶上图例：线在图例带里，签夹到图例下沿；夹下来离线超过 32 就不放', () => {
    const { g } = fixtureRig()
    const L = g.L
    const legend = g.r.mainLegendInset(L.plotW)
    expect(legend, '开着主力，图例至少两行').toBeGreaterThan(S.labelHeight)
    const b = g.b
    const seen = b.time(b.count - 30) + 1
    g.orders = [order('usdtPerp', 'ask', g.price(L.main.y + legend - 4), seen, { bucket: 1 })]
    const f = g.frame()
    expect(f.bands.length).toBe(1)
    const l = f.labels[0]
    expect(l, '离下沿不远的仍写金额').toBeTruthy()
    expect(minY(l.frame)).toBeGreaterThanOrEqual(L.main.y + legend - 1e-9)
    expect(Math.abs(midY(l.frame) - midY(f.bands[0].frame))).toBeLessThanOrEqual(S.labelMaxShift + 1e-9)
    g.orders = [order('usdtPerp', 'ask', g.price(L.main.y + 2), seen, { bucket: 2 })]
    const t = g.frame()
    expect(t.bands.length, '线照画').toBe(1)
    const shift = L.main.y + legend + S.labelHeight / 2 - (L.main.y + 2)
    if (shift > S.labelMaxShift) expect(t.labels.length).toBe(0)
    else expect(t.labels.every(x => minY(x.frame) >= L.main.y + legend - 1e-9)).toBe(true)
  })

  it('挂着的签贴右缘压到最新几根 K 线：往左让到压着的最右一根左侧 2、不压任何一根、仍在线上方；墙离 K 线远照旧贴右缘', () => {
    const { g } = fixtureRig()
    const L = g.L
    const b = g.b
    const seen = b.time(b.count - 30) + 1
    const inset = S.labelInset, lift = S.labelLineGap
    const m = candleMetrics(g.spacing, 3)
    const halfW = Math.max(m.bodyW, m.wickW) / 2
    const cx = (i: number) => g.x(i)
    const hiY = (i: number) => g.y(b.high[i]), loY = (i: number) => g.y(b.low[i])
    const covers = (rc: Rect, i: number) => cx(i) + halfW > minX(rc) && cx(i) - halfW < maxX(rc) && hiY(i) < maxY(rc) && loY(i) > minY(rc)
    const all = Array.from({ length: b.count }, (_, i) => i)
    const w = orderFlowLabelWidth(orderFlowAmount(10_000_000))
    const right = L.plotW - inset
    const under = all.filter(i => cx(i) + halfW > right - w && cx(i) - halfW < right)
    expect(under.length, '最新那几根落在贴右缘的签底下').toBeGreaterThan(0)
    const tall = under.reduce((a, c) => (loY(c) - hiY(c) > loY(a) - hiY(a) ? c : a))
    expect(loY(tall) - hiY(tall)).toBeGreaterThan(8)
    g.orders = [order('usdtPerp', 'bid', (b.high[tall] + b.low[tall]) / 2, seen, { bucket: 1 })]
    const f = g.frame()
    const line = f.bands[0]
    const naive: Rect = { x: right - w, y: minY(line.frame) - lift - S.labelHeight, w, h: S.labelHeight }
    const hitting = under.filter(i => covers(naive, i))
    expect(hitting.length, '贴右缘的签压着最新那几根').toBeGreaterThan(0)
    const hit = Math.max(...hitting)
    const label = f.labels[0]
    expect(label, '躲开 K 线后仍写金额').toBeTruthy()
    expect(maxX(label.frame)).toBeLessThan(cx(hit) - halfW)
    expect(Math.abs(maxY(label.frame) - (minY(line.frame) - lift))).toBeLessThan(1e-9)
    expect(all.filter(i => covers(label.frame, i)), '挪完不再压任何一根').toEqual([])
    const gaps = all.filter(i => hiY(i) < maxY(label.frame) && loY(i) > minY(label.frame))
      .map(i => cx(i) - halfW - maxX(label.frame)).filter(x => x > 0)
    const gapToBlocker = gaps.length ? Math.min(...gaps) : null
    expect(gapToBlocker != null && gapToBlocker >= S.labelCandleGap && gapToBlocker <= S.labelCandleGap + 1, `签右缘离压着的那根 ${gapToBlocker}`).toBe(true)

    // 墙挪到签够不着蜡烛的地方：照旧贴右缘。
    const ceil = Math.min(...under.map(hiY)), floor = Math.max(...under.map(loY))
    const legendBottom = L.main.y + g.r.mainLegendInset(L.plotW)
    const aboveY = ceil - 4, belowY = floor + 22
    const farY = aboveY - 20 >= legendBottom ? aboveY : belowY + 4 <= L.main.y + L.main.h ? belowY : null
    expect(farY, '夹具主图里放得下一条不压蜡烛的线').not.toBeNull()
    g.orders = [order('usdtPerp', 'bid', g.price(farY!), seen, { bucket: 2 })]
    const h = g.frame()
    const farLine = h.bands[0], farLabel = h.labels[0]
    expect(Math.abs(maxX(farLabel.frame) - right), '不压蜡烛就贴右缘').toBeLessThan(1e-9)
    expect(Math.abs(maxY(farLabel.frame) - (minY(farLine.frame) - lift))).toBeLessThan(1e-9)

    // 跨桶的墙：括号跟着让开的签走。
    const mid = (b.high[tall] + b.low[tall]) / 2, step = mid * 0.001
    g.step = step
    const b0 = Math.floor(mid / step) - 1
    g.orders = [b0, b0 + 1, b0 + 2].map(bk => wallOrder(g, step, bk, { from: 20 }))
    const wf = g.frame()
    const wall = wf.bands.find(x => x.group.bucketCount === 3)!
    expect(wall, ids(wf)).toBeTruthy()
    const wallLabel = wf.labels.find(l => eqKey(l.key, wall.group.key))!
    const bracket = wall.bracket!
    expect(bracket, '三桶的主墙立括号').toBeTruthy()
    expect(maxX(wallLabel.frame), '夹具：签让开了 K 线').toBeLessThan(right - 1)
    expect(all.every(i => !covers(wallLabel.frame, i))).toBe(true)
    expect(Math.abs(maxX(bracket) - (minX(wallLabel.frame) - S.bracketGap))).toBeLessThan(1e-6)
  })

  it('已结束的签在结束点右侧压到蜡烛：先试线上方 / 下方，都压着就往右让到那根右侧 2、居中在线上；括号跟着签走；哪儿都压着取盖得最少的', () => {
    const { g } = fixtureRig()
    zoomIn(g, 3)
    const L = g.L
    const b = g.b
    const inset = S.labelInset, gap = S.labelCandleGap, h = S.labelHeight, lift = S.labelLineGap
    const spacing = g.spacing
    const cx = (i: number) => g.x(i)
    const hiY = (i: number) => g.y(b.high[i]), loY = (i: number) => g.y(b.low[i])
    const half = Math.max(1, spacing / 3 + 0.5)
    const w = orderFlowLabelWidth(orderFlowAmount(10_000_000))
    let tall = -1
    for (let i = b.count - 40; i < b.count - 12; i++) {
      const landing: Rect = { x: cx(i) + half + gap, y: hiY(i) - 1, w, h }
      if (loY(i) - hiY(i) > 10 && cx(i - 3) - spacing / 2 >= 0 && g.candlesUnder(landing).length === 0 && maxX(landing) <= L.plotW - inset) {
        tall = i; break
      }
    }
    expect(tall, '夹具里要有这么一根').toBeGreaterThanOrEqual(0)
    const level = g.price(hiY(tall) + h / 2 - 1)
    const seen = b.time(tall - 3) + 1, end = b.time(tall - 1) + 1
    g.orders = [order('usdtPerp', 'ask', level, seen, { end, status: 'cancelled', bucket: 3 })]
    const f = g.frame()
    const line = f.bands[0], label = f.labels[0]
    expect(label, '让开后仍写金额').toBeTruthy()
    expect(Math.abs(maxX(line.frame) - (cx(tall) - spacing / 2))).toBeLessThan(1)
    expect(minX(label.frame), '签往右让开了').toBeGreaterThan(maxX(line.frame) + inset)
    expect(Math.abs(midY(label.frame) - midY(line.frame)), '居中在线上').toBeLessThan(1e-9)
    expect(g.candlesUnder(label.frame), '不压任何一根').toEqual([])
    expect(maxX(label.frame)).toBeLessThanOrEqual(L.plotW - inset + 1e-9)
    expect(Math.abs(minX(label.frame) - (cx(tall) + half + gap)), '签左缘 = 那根右缘 + 2').toBeLessThan(1e-6)

    // 那根之上还有一小截空：线上方放得下就不横向挪。
    const low = g.price(hiY(tall) + h + lift + 1 + 4)
    g.orders = [order('usdtPerp', 'ask', low, seen, { end, status: 'cancelled', bucket: 3 })]
    const s = g.frame()
    const sLine = s.bands[0], sLabel = s.labels[0]
    const aboveRect: Rect = { x: maxX(sLine.frame) + inset, y: minY(sLine.frame) - lift - h, w, h }
    if (g.candlesUnder(aboveRect).length === 0) {
      expect(Math.abs(minX(sLabel.frame) - (maxX(sLine.frame) + inset)) < 1e-9
        && Math.abs(maxY(sLabel.frame) - (minY(sLine.frame) - lift)) < 1e-9, '上方放得下就不横向挪').toBe(true)
    }
    expect(endedLabelAtAllowedSpot(sLabel, sLine, L.plotW)).toBe(true)

    // 哪儿都压着：签照样有，落在允许的几处之一。
    const dense = new Rig(new ChartRenderer(g.r.state))
    setView(dense, b.time(tall) + b.step / 2)
    dense.orders = [order('usdtPerp', 'ask', level, seen, { end, status: 'cancelled', bucket: 3 })]
    const df = dense.frame()
    const dLine = df.bands[0], dLabel = df.labels[0]
    expect(dLabel, '让不开也要有签').toBeTruthy()
    expect(endedLabelAtAllowedSpot(dLabel, dLine, dense.L.plotW)).toBe(true)

    // 跨桶的已结束墙：括号跟着让开的签走。
    const step = level * 0.001
    g.step = step
    const b0 = Math.floor(level / step) - 1
    g.orders = [b0, b0 + 1, b0 + 2].map(bk => wallOrder(g, step, bk, { from: b.count - tall + 3, to: b.count - tall + 1 }))
    const wf = g.frame()
    const wall = wf.bands.find(x => x.group.bucketCount === 3)!
    expect(wall, ids(wf)).toBeTruthy()
    const wallLabel = wf.labels.find(l => eqKey(l.key, wall.group.key))!
    const bracket = wall.bracket!
    expect(bracket, '三桶的主墙立括号').toBeTruthy()
    expect(wall.group.isLive).toBe(false)
    expect(endedLabelAtAllowedSpot(wallLabel, wall, L.plotW)).toBe(true)
    expect(Math.abs(maxX(bracket) - (minX(wallLabel.frame) - S.bracketGap))).toBeLessThan(1e-6)
  })

  it('已结束的长线结束在一片高蜡烛里、右边让不开：签沿线往左滑到线身上不压蜡烛的地方，不落回压着蜡烛的那处', () => {
    const { g } = fixtureRig()
    zoomIn(g, 3)
    const b = g.b
    const inset = S.labelInset, h = S.labelHeight, lift = S.labelLineGap
    const w = orderFlowLabelWidth(orderFlowAmount(10_000_000))
    const spacing = g.spacing
    let pick: { tall: number; level: number; clearX: number } | null = null
    for (let i = b.count - 40; i < b.count - 12 && !pick; i++) {
      if (i < 31 || !(g.y(b.low[i]) - g.y(b.high[i]) > 10)) continue
      const d = new Rig(new ChartRenderer(g.r.state))
      setView(d, b.time(i) + b.step / 2)
      const level = d.price(d.y(b.high[i]) + h / 2 - 1)
      const lineY = d.y(level)
      const lineMinX = d.x(i - 30) - spacing / 2, lineMaxX = d.x(i) - spacing / 2
      const xL = lineMaxX - inset - w
      if (xL < lineMinX) continue
      const above = (x: number): Rect => ({ x, y: lineY - 1 - lift - h, w, h })
      const below = (x: number): Rect => ({ x, y: lineY + 1 + lift, w, h })
      const centered: Rect = { x: lineMaxX + inset, y: lineY - h / 2, w, h }
      const anchored = [centered, above(lineMaxX + inset), below(lineMaxX + inset), above(xL), below(xL)]
      if (!anchored.every(rc => d.candlesUnder(rc).length > 0)) continue
      for (let x = xL - 1; x >= lineMinX; x -= 1) {
        if (d.candlesUnder(above(x)).length === 0 || d.candlesUnder(below(x)).length === 0) { pick = { tall: i, level, clearX: x }; break }
      }
    }
    expect(pick, '夹具里要有这么一根').not.toBeNull()
    const { tall, level, clearX } = pick!
    setView(g, b.time(tall) + b.step / 2)
    g.orders = [order('usdtPerp', 'ask', level, b.time(tall - 30) + 1, { end: b.time(tall - 1) + 1, status: 'cancelled', bucket: 3 })]
    const f = g.frame()
    const line = f.bands[0], label = f.labels[0]
    expect(label, '滑过去仍写金额').toBeTruthy()
    const plotW = g.L.plotW
    expect(endedLabelAtAllowedSpot(label, line, plotW), `${JSON.stringify(label.frame)} 线 ${JSON.stringify(line.frame)}`).toBe(true)
    expect(maxX(label.frame)).toBeLessThan(maxX(line.frame) - inset - 1e-9)
    expect(minX(label.frame), '签左缘不出线头').toBeGreaterThanOrEqual(minX(line.frame) - 1e-9)
    expect(minX(label.frame), '滑到最近的空档就停').toBeGreaterThanOrEqual(clearX - w - spacing)
    const offLine = Math.abs(maxY(label.frame) - (minY(line.frame) - lift)) < 1e-9 || Math.abs(minY(label.frame) - (maxY(line.frame) + lift)) < 1e-9
    expect(offLine, '沿线滑的是线上方 / 下方那两处').toBe(true)
    expect(g.candlesUnder(label.frame), '不压任何一根').toEqual([])
  })

  it('详情卡上限：宽 ≤ 85% 绘图区、高 ≤ 55% 主图且不越过线的命中带（至少 8 高）', () => {
    const B = OrderFlowCardBudget
    expect(B.maxWidth(400)).toBe(340)
    const place = (bandY: number, top: number, bottom: number, main: number) =>
      B.placement({ bandY, bandHalf: 3, top, bottom, mainHeight: main, plotW: 400, anchorX: 100, candle: null })
    const top = place(60, 20, 420, 400)
    expect(top.below).toBe(true)
    expect(top.maxHeight).toBeCloseTo(220, 9)
    expect(top.top).toBeCloseTo(200, 9)
    expect(top.leading).toBe(false); expect(top.maxWidth).toBe(340); expect(top.compact).toBe(false); expect(top.coversCandle).toBe(false)
    const low = place(380, 20, 420, 400)
    expect(low.below).toBe(false); expect(low.maxHeight).toBeCloseTo(220, 9); expect(low.top).toBe(20)
    const mid = B.placement({ bandY: 150, bandHalf: 4, top: 20, bottom: 300, mainHeight: 280, plotW: 400, anchorX: 300, candle: null })
    expect(mid.below).toBe(true); expect(mid.maxHeight).toBe(140); expect(mid.top).toBe(160); expect(mid.leading).toBe(true)
    const { g, orders } = fixtureRig()
    g.select(keyOf(orders[0]))
    const focus = g.focus()!
    expect(focus).toBeTruthy()
    const L = g.L
    expect(focus.candle).toBeNull()
    expect(focus.cardMaxWidth).toBe(L.plotW * 0.85)
    expect(focus.mainHeight).toBe(L.main.h)
    expect(focus.bandHalf).toBe(S.hitHeight / 2)
    const p = focus.cardPlacement
    expect(p.maxHeight).toBeLessThanOrEqual(L.main.h * 0.55)
    if (p.below) {
      expect(focus.bandY + focus.bandHalf + 6).toBeLessThanOrEqual(p.top + 1e-9)
      expect(Math.abs(p.top + p.maxHeight - focus.mainBottom), '贴主图下沿').toBeLessThan(1e-9)
    } else {
      expect(p.top + p.maxHeight).toBeLessThanOrEqual(focus.bandY - focus.bandHalf - 6 + 1e-9)
      expect(p.top, '贴图例下的上沿').toBe(focus.mainTop)
    }
  })

  it('D4 详情卡在带的对面那一半、贴远端，不盖住十字线那根 K 线', () => {
    const B = OrderFlowCardBudget
    const C = (left: number, right: number, top: number, bottom: number) => ({ left, right, top, bottom })
    const place = (anchorX: number, candle: ReturnType<typeof C> | null, bandY = 100, top = 20, bottom = 420) =>
      B.placement({ bandY, bandHalf: 4, top, bottom, mainHeight: bottom - top, plotW: 360, anchorX, candle })
    const clear = place(60, C(56, 64, 60, 150))
    expect([clear.below, clear.leading, clear.maxWidth, clear.coversCandle]).toEqual([true, false, 306, false])
    const narrow = place(60, C(56, 64, 300, 400))
    expect(narrow.below).toBe(true); expect(narrow.leading).toBe(false); expect(narrow.coversCandle).toBe(false)
    expect(narrow.maxWidth).toBeCloseTo(284, 9)
    expect(360 - B.sideInset - narrow.maxWidth, '卡的左缘在 K 线右边以外').toBeGreaterThanOrEqual(64 + B.candleGap - 1e-9)
    const center = place(180, C(176, 184, 300, 400))
    expect([center.below, center.top, center.compact, center.coversCandle]).toEqual([false, 20, true, false])
    const stuck = place(180, C(176, 184, 300, 400), 80)
    expect([stuck.below, stuck.coversCandle, stuck.maxWidth]).toEqual([true, true, 306])
    const flipped = place(180, C(176, 184, 300, 400), 180)
    expect([flipped.below, flipped.top, flipped.coversCandle, flipped.maxWidth]).toEqual([false, 20, false, 306])
    const gap = place(180, C(176, 184, 250, 330))
    expect([gap.below, gap.maxWidth, gap.coversCandle]).toEqual([true, 306, false])
  })

  it('D4 十字线停在线上：卡的高度段与那根 K 线不重叠，或横向躲开', () => {
    const { g } = fixtureRig()
    const L = g.L, B = OrderFlowCardBudget
    const f = g.frame()
    let checked = 0
    for (const band of f.bands) {
      const x = minX(band.frame) + band.frame.w * 0.3
      const i = g.b.index(g.r.state.viewport.view.t(x, L.plotW))
      g.cross({ index: i, pane: null, t: null, price: g.price(midY(band.frame)) })
      const focus = g.focus()
      const c = focus?.candle
      if (!focus || !c) continue
      checked += 1
      expect(c.top).toBeLessThanOrEqual(c.bottom); expect(c.left).toBeLessThan(c.right)
      const p = focus.cardPlacement
      const h = Math.min(p.maxHeight, p.compact ? B.compactHeight : B.fullHeight)
      const lo = p.below ? p.top + p.maxHeight - h : p.top, hi = lo + h
      const x0 = p.leading ? B.sideInset : L.plotW - B.sideInset - p.maxWidth, x1 = x0 + p.maxWidth
      const overlap = c.top < hi && c.bottom > lo && c.left < x1 && c.right > x0
      expect(!overlap || p.coversCandle, `卡 ${x0}…${x1} × ${lo}…${hi} 盖住了 K 线 ${JSON.stringify(c)}`).toBe(true)
      if (p.below) expect(p.top).toBeGreaterThanOrEqual(focus.bandY + focus.bandHalf + B.bandGap - 1e-9)
      else expect(p.top + p.maxHeight).toBeLessThanOrEqual(focus.bandY - focus.bandHalf - B.bandGap + 1e-9)
    }
    expect(checked).toBeGreaterThan(0)
  })

  it('深浅：被吃过（成交名义 > 0）是本色，一口没成交往底色混 45%；撤单 / 失联不再另画', () => {
    const { g } = fixtureRig()
    const bg = g.r.colors.bg
    const bid = orderFlowBaseColor(g.r, 'bid', true), ask = orderFlowBaseColor(g.r, 'ask', true)
    const f = g.frame()
    const fresh = bandAt(f, 1)!, coin = bandAt(f, 4)!, filled = bandAt(f, 5)!, cancelled = bandAt(f, 6)!
    expect(fresh.dark).toBe(false); expect(fresh.color).toBe(orderFlowUnfilled(bid, bg))
    expect(coin.dark, '部分成交也是深色').toBe(true); expect(coin.color).toBe(ask)
    expect(filled.dark).toBe(true); expect(filled.color).toBe(bid)
    expect(cancelled.dark).toBe(false); expect(cancelled.color).toBe(orderFlowUnfilled(ask, bg))
    expect(orderFlowColor(g.r, 'bid', true, true), '被吃一口就转深').toBe(bid)
  })

  it('颜色：合约买蓝卖品红、现货买黄绿卖浅紫，一律不用蜡烛涨跌色、不随红涨绿跌翻；按图区底色明暗两套', () => {
    const base = (g: Rig, o: BigOrder) => orderFlowBaseColor(g.r, o.side, isContract(o.product))
    for (const redUp of [false, true]) {
      const { g, orders } = fixtureRig()
      const c0 = FALLBACK_COLORS
      if (redUp) g.r.state = withInput(g.r.state, { colors: { ...c0, up: c0.down, down: c0.up } })
      const t = g.r.colors
      const p = orderFlowFor(t.bg)
      expect(p, '默认夹具是浅色底').toBe(orderFlowOnLight)
      expect(base(g, orders[0])).toBe(p.contractBid)
      expect(base(g, orders[3]), '币本位永续和 U 本位同一套').toBe(p.contractAsk)
      expect(base(g, orders[5]), '交割同一套').toBe(p.contractAsk)
      expect(base(g, orders[1])).toBe(p.spotBid)
      expect(base(g, orders[2])).toBe(p.spotAsk)
      for (const o of orders) {
        const c = base(g, o)
        expect(c !== t.up && c !== t.down).toBe(true)
        expect(Math.min(hueDistance(c, t.up), hueDistance(c, t.down)), `${o.product} ${o.side} 和蜡烛撞色`).toBeGreaterThanOrEqual(60)
      }
    }
    // 六套皮肤按底色分两套（tokens.css 的 --k-bg）；浅色档和底色、和深色档都拉得开。
    const skins: [string, string, boolean][] = [
      ['sage', '#F3F7F4', false], ['sage', '#0B120F', true], ['terra', '#FBF6F0', false], ['terra', '#16100C', true],
      ['classic', '#FFFFFF', false], ['classic', '#0D111C', true],
    ]
    for (const [skin, bg, dark] of skins) {
      const { g, orders } = fixtureRig()
      g.r.state = withInput(g.r.state, { colors: { ...FALLBACK_COLORS, bg, orderFlow: orderFlowFor(bg) } })
      const want = dark ? orderFlowOnDark : orderFlowOnLight
      expect(base(g, orders[0]), `${skin} ${dark}`).toBe(want.contractBid)
      expect(base(g, orders[1]), `${skin} ${dark}`).toBe(want.spotBid)
      expect(base(g, orders[2]), `${skin} ${dark}`).toBe(want.spotAsk)
      expect(base(g, orders[3]), `${skin} ${dark}`).toBe(want.contractAsk)
      for (const o of orders) {
        const lc = orderFlowColor(g.r, o.side, isContract(o.product), false)
        const dc = orderFlowColor(g.r, o.side, isContract(o.product), true)
        expect(rgbDistance(lc, bg), `${skin} ${dark} ${o.product} 浅色档要和底色拉开：${lc} vs ${bg}`).toBeGreaterThan(0.12)
        expect(rgbDistance(lc, dc), `${skin} ${dark} ${o.product} 深浅两档要分得开`).toBeGreaterThan(0.10)
        for (const c of [lc, dc]) {
          const shown = mixHex(c, bg, 1 - S.labelAlpha)
          const ink = orderFlowLabelInk(shown)
          expect(contrast(ink, shown), `${skin} ${dark} ${c} 签字 ${ink} 对签底 ${shown}`).toBeGreaterThanOrEqual(4.5)
        }
      }
    }
  })

  it('显示开关：关现货 / 合约 / 已成交 / 已撤销各自只藏那一类（逐单过滤后再合并）；合计只算还挂着的', () => {
    const { g, orders } = fixtureRig()
    const live = orders.filter(o => o.status === 'live')
    const sum = (side: BookSide) => live.filter(o => o.side === side).reduce((s, o) => s + o.notional, 0)
    expect(g.frame().bidTotal).toBe(sum('bid'))
    expect(g.frame().askTotal).toBe(sum('ask'))
    g.display({ ...defaultOrderFlowDisplay(), spot: false })
    expect(g.frame().bands.every(x => x.group.contract)).toBe(true)
    expect(g.frame().bands.length).toBe(4)
    g.display({ ...defaultOrderFlowDisplay(), contract: false })
    expect(g.frame().bands.every(x => !x.group.contract)).toBe(true)
    g.display({ ...defaultOrderFlowDisplay(), filled: false })
    expect(g.frame().bands.some(x => x.group.members.some(m => m.status === 'filled'))).toBe(false)
    g.display({ ...defaultOrderFlowDisplay(), filled: false, cancelled: false })
    expect(g.frame().bands.some(x => x.group.members.some(m => m.status === 'cancelled'))).toBe(false)
    expect(g.frame().bands.length).toBe(4)
  })

  it('点中判定：线按至少 8 高的带子算，横向两头放 4、竖向再放 8；同价叠着点出名义大的，错开的细线点得中', () => {
    const { g } = fixtureRig()
    const f = g.frame()
    const band = bandAt(f, 1)!
    const x = midX(band.frame), mid = midY(band.frame)
    const half = Math.max(band.frame.h, S.hitHeight) / 2
    const hitKey = (bands: OrderFlowBand[], px: number, py: number, touch = false) => orderFlowHitBands(bands, px, py, touch)?.group.key ?? null
    expect(half, '2.5 的线按 8 的带子算').toBe(4)
    expect(eqKey(hitKey(f.bands, x, mid), band.group.key)).toBe(true)
    expect(eqKey(hitKey([band], x, mid + half + 7.9), band.group.key)).toBe(true)
    expect(eqKey(hitKey([band], x, mid - half - 7.9), band.group.key)).toBe(true)
    expect(hitKey([band], x, mid + half + 8.1)).toBeNull()
    expect(eqKey(hitKey([band], minX(band.frame) - 3.9, mid), band.group.key)).toBe(true)
    expect(hitKey([band], minX(band.frame) - 4.1, mid)).toBeNull()
    // 一条名义小的细线：和它同价叠着时点下去给大的；错开 3 时点在细线上给细线、点在大线上给大线。
    const small: BigOrder = { ...band.group.members[0], venueID: 'binance:spot:X', product: 'spot', notional: 1_500_000, initialNotional: 1_500_000 }
    const smallGroup = OrderFlowGroup.make(keyOf(small), [small])!
    expect(smallGroup).toBeTruthy()
    const thinBand = (y: number): OrderFlowBand => ({
      group: smallGroup, frame: { x: minX(band.frame), y, w: band.frame.w, h: 1 }, color: band.color, dark: false, thin: true,
      role: 'main', alpha: 1, bracket: null,
    })
    const stacked = thinBand(mid - 0.5)
    expect(eqKey(hitKey([band, stacked], x, mid), band.group.key)).toBe(true)
    const offset = thinBand(mid - 3.5)
    expect(eqKey(hitKey([band, offset], x, mid - 3), offset.group.key)).toBe(true)
    expect(eqKey(hitKey([band, offset], x, mid + 0.5), band.group.key)).toBe(true)
    // 都没点在带里：离带边最近的；一样近取名义大的。
    expect(eqKey(hitKey([offset, band], x, mid + half + 3), band.group.key)).toBe(true)
    // 轻点：命中区至少 44 高、44 宽（HIG）；十字线仍按 8 / 4。
    const reachY = (S.touchTarget - 2 * half) / 2
    expect(reachY).toBe(18)
    expect(eqKey(hitKey([band], x, mid + half + reachY - 0.1, true), band.group.key)).toBe(true)
    expect(eqKey(hitKey([band], x, mid - half - reachY + 0.1, true), band.group.key)).toBe(true)
    expect(hitKey([band], x, mid + half + reachY + 0.1, true)).toBeNull()
    const narrow: OrderFlowBand = { ...band, frame: { x: minX(band.frame), y: minY(band.frame), w: 4, h: band.frame.h }, dark: false, thin: false }
    expect(eqKey(hitKey([narrow], midX(narrow.frame) + 21.9, mid, true), band.group.key)).toBe(true)
    expect(hitKey([narrow], midX(narrow.frame) + 22.1, mid, true)).toBeNull()
    expect(hitKey([narrow], midX(narrow.frame) + 6.1, mid), '十字线不放宽').toBeNull()
    // 视图坐标版只认主图绘图区。
    expect(eqKey(g.hit(x, mid)?.key, band.group.key)).toBe(true)
    expect(g.hit(g.L.plotW + 5, mid)).toBeNull()
  })

  it('十字线停在带上：出选中（非点选）；离开就没有', () => {
    const { g, orders } = fixtureRig()
    const coin = orders[3]
    g.cross({ index: g.b.count - 1, pane: null, t: null, price: coin.price })
    const focus = g.focus()!
    expect(focus).toBeTruthy()
    expect(eqKey(focus.group.key, keyOf(coin))).toBe(true)
    expect(focus.selected).toBe(false)
    expect(focus.group.members).toEqual([coin])
    const L = g.L, range = g.range
    expect(orderFlowHoversBand(g.r, L, range)).toBe(true)
    expect(drawOrderFlowHover(g.r, mockCtx(), L.main, range, L, 3)).toBe(true)
    g.cross({ index: 0, pane: null, t: null, price: coin.price * 2 })
    expect(g.focus()).toBeNull()
    expect(orderFlowHoversBand(g.r, L, range)).toBe(false)
    expect(drawOrderFlowHover(g.r, mockCtx(), L.main, range, L, 3)).toBe(false)
  })

  it('失联结束：和撤单一样按深浅画，也不归已成交 / 已撤销开关管', () => {
    const { g } = fixtureRig()
    g.editOrder(5, { status: 'lost' })
    expect(bandAt(g.frame(), 6)!.dark).toBe(false)
    g.display({ ...defaultOrderFlowDisplay(), cancelled: false, filled: false })
    expect(bandAt(g.frame(), 6)).toBeTruthy()
  })

  it('开着主力图例多留一行；拉快照中、别的品种不画', () => {
    const { g } = fixtureRig()
    const plain = new ChartRenderer(withOverlay(g.r.state, { orderFlow: null }))
    expect(g.r.mainLegendInset(300)).toBe(plain.mainLegendInset(300) + 12)
    const loading = new Rig(new ChartRenderer(g.r.state))
    loading.setFlow({ phase: 'loading', orders: [] })
    expect(loading.frame().bands).toEqual([])
    const other = new Rig(new ChartRenderer(g.r.state))
    other.setFlow({ symbol: 'ETHUSDT' })
    expect(other.frame().bands).toEqual([])
  })

  it('整帧绘制：每单一条都画了，比价模式不画', () => {
    const { g, orders } = fixtureRig()
    const L = g.L
    expect(drawOrderFlow(g.r, mockCtx(), L.main, g.range, L, 3)).toBe(orders.length)
    const compare = new ChartRenderer(withInput(g.r.state, { percentAxis: true }))
    expect(hasOrderFlow(compare)).toBe(false)
  })

  it('色块几何两层共用一份：十字线动不重算，快照一变才重算', () => {
    const { g, orders } = fixtureRig()
    g.frame(); g.frame()
    const computed = () => g.r.orderFlowCache.get('computed')
    expect(computed()).toBe(1)
    g.cross({ index: g.b.count - 1, pane: null, t: null, price: orders[3].price })
    expect(eqKey(g.focus()?.group.key, keyOf(orders[3]))).toBe(true)
    g.cross(null)
    g.select(keyOf(orders[0]))
    expect(eqKey(g.focus()?.group.key, keyOf(orders[0]))).toBe(true)
    expect(computed(), '十字线动、选中换都不重算几何').toBe(1)
    g.orders = orders.slice(0, -1)
    g.frame()
    expect(computed(), '快照变了换了新盒子，新盒子里算了一次').toBe(1)
    expect(g.frame().bands.length).toBe(orders.length - 1)
  })

  it('轻点：点在蜡烛高低范围内是 K 线的，哪怕底下垫着一条大单带子；点在蜡烛外的带子上才出详情卡', () => {
    const { g } = fixtureRig()
    const L = g.L, b = g.b
    let overlap: { x: number; y: number } | null = null
    let clear: { x: number; y: number } | null = null
    for (const band of g.frame().bands) {
      const by = midY(band.frame)
      for (let i = 0; i < b.count; i++) {
        const cx = g.x(i)
        if (!(cx > minX(band.frame) + 1 && cx < maxX(band.frame) - 1 && cx > 0 && cx < L.plotW)) continue
        const yHi = g.y(b.high[i]), yLo = g.y(b.low[i])
        if (by > yHi + 1 && by < yLo - 1 && !overlap) overlap = { x: cx, y: by }
        if ((by < yHi - S.candleHitSlop - 2 || by > yLo + S.candleHitSlop + 2) && !clear) clear = { x: cx, y: by }
      }
    }
    expect(overlap).not.toBeNull(); expect(clear).not.toBeNull()
    const on = overlap!, off = clear!
    expect(g.hit(on.x, on.y)).not.toBeNull()
    expect(candleHit(g.r, on.x, on.y, W, H)).toBe(true)
    expect(candleHit(g.r, off.x, off.y, W, H)).toBe(false)
    expect(g.hit(off.x, off.y)).not.toBeNull()
    expect(candleHit(g.r, L.plotW + 5, on.y, W, H)).toBe(false)
  })

  it('粗细格：占门槛几个四分之一（封顶 64），档位 ⌊log₂(格 ÷ 4)⌋ 夹到 0…4', () => {
    expect(thicknessQuarters(5_000_000, 5_000_000)).toBe(4)
    expect(thicknessQuarters(11_000_000, 5_000_000)).toBe(8)
    expect(thicknessQuarters(1e12, 5_000_000)).toBe(64)
    expect(thicknessQuarters(1, 0)).toBe(0)
    expect(thicknessQuarters(Number.NaN, 5)).toBe(0)
    expect([4, 7, 8, 15, 16, 32, 64].map(thicknessTier)).toEqual([0, 0, 1, 1, 2, 3, 4])
  })
})

// ------------------------------------------------------------------ 2 万单压测数据（Swift OrderFlowPerfBenchTests 的结构性用例）
// 不做墙钟断言、不打 ORDERFLOW-PERF；随机数用 mulberry32（与 Swift BenchRNG 不逐位相同，统计形状一样）。

function rng(seed: number): { unit(): number; range(a: number, b: number): number } {
  let s = seed >>> 0
  const unit = () => {
    s = (s + 0x6D2B79F5) >>> 0
    let t = s
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
  return { unit, range: (a, b) => a + (b - a) * unit() }
}

function benchSeries(count: number, interval: Interval, seed = 20260917): BarSeries {
  const r = rng(seed)
  const open: number[] = [], high: number[] = [], low: number[] = [], close: number[] = [], volume: number[] = []
  let px = 30_000
  for (let i = 0; i < count; i++) {
    const op = px
    px = Math.max(1, px * (1 + r.range(-0.012, 0.012)))
    open.push(op); close.push(px)
    high.push(Math.max(op, px) * (1 + r.range(0, 0.006)))
    low.push(Math.min(op, px) * (1 - r.range(0, 0.006)))
    volume.push(r.range(10, 5000))
  }
  return new BarSeries({ symbol: 'BENCHUSDT', interval, t0: 1_600_000_000_000, open, high, low, close, volume })
}

/** 2 万单，全落在最近三天里，价位贴着当时那根的收盘。 */
function benchOrders(series: BarSeries, count = 20_000, seed = 20260928): { orders: BigOrder[]; step: number } {
  const r = rng(seed)
  const last = series.time(series.count - 1)
  const t0 = Math.max(series.firstTime, last - 3 * 86_400_000)
  const step = Math.round(series.close[series.count - 1] * 0.001)
  const products: Product[] = ['spot', 'usdtPerp', 'usdtPerp', 'coinPerp', 'delivery']
  const out: BigOrder[] = []
  for (let i = 0; i < count; i++) {
    const seen = t0 + Math.trunc(r.unit() * (last - t0))
    const idx = series.index(seen)
    const side: BookSide = r.unit() < 0.5 ? 'bid' : 'ask'
    const off = series.close[idx] * r.range(0.0005, 0.02)
    const bucket = Math.round((side === 'bid' ? series.close[idx] - off : series.close[idx] + off) / step)
    const roll = r.unit()
    const status: Status = roll < 0.1 ? 'live' : roll < 0.3 ? 'filled' : 'cancelled'
    const life = Math.trunc(Math.exp(r.range(Math.log(30_000), Math.log(4 * 3_600_000))))
    const end = status === 'live' ? null : Math.min(last + 30_000, seen + life)
    const n = Math.exp(r.range(Math.log(1_000_000), Math.log(80_000_000)))
    const filled = status === 'filled' ? n : (status === 'cancelled' && r.unit() < 0.3 ? n * r.range(0.05, 0.9) : 0)
    const product = products[i % products.length]
    out.push({
      venueID: `binance:${product}:${i}`, exchange: '币安', product, side, bucket, price: bucket * step, firstSeenMs: seen,
      endMs: end, status, initialNotional: n, notional: n, filledNotional: filled, threshold: 1_000_000, vanishedNotional: null,
    })
  }
  out.sort((a, b) => a.firstSeenMs - b.firstSeenMs)
  return { orders: out, step }
}

const BW = 402, BH = 620
const benchMemo = new Map<string, { orders: BigOrder[]; step: number }>()

function benchState(interval: Interval, visible: number) {
  const series = benchSeries(interval === '1d' ? 1000 : 6000, interval)
  const subs = ['VOL', 'MACD'] as const
  const L = new Layout(BW, BH, [...subs])
  const view = ViewMath.reset(series, L.plotW, L.plotW / visible)
  let s = makeState({ series, symbol: { symbol: 'BENCHUSDT', base: 'BENCH', priceDecimals: 2 }, view, overlays: ['MA'], subs: [...subs] })
  // 同一周期的那 2 万单只生成一次（与 Swift 一样确定性，重复生成只是白花时间）。
  let gen = benchMemo.get(interval)
  if (!gen) { gen = benchOrders(series); benchMemo.set(interval, gen) }
  const px = series.close[series.count - 1]
  s = withOverlay(s, {
    orderFlow: {
      symbol: 'BENCHUSDT', phase: 'ready', orders: gen.orders, asOfMs: series.time(series.count - 1) + 30_000,
      thresholds: { spot: 1_000_000, usdtPerp: 1_000_000, coinPerp: 1_000_000, delivery: 1_000_000, step: gen.step },
    },
    depth: makeOrderBook('BENCHUSDT', series.lastTime,
      [1, 2, 3, 4, 5].map(i => ({ price: px - i * 0.1, quantity: (6 - i) * 3 })),
      [1, 2, 3, 4, 5].map(i => ({ price: px + i * 0.1, quantity: i * 2 }))),
  })
  return s
}

function bandsCold(r: ChartRenderer): OrderFlowFrame {
  const L = r.layout(BW, BH)
  return orderFlowBands(r, L.main, r.priceRange(BW, BH), L)
}

const sameGroups = (a: OrderFlowGroup[], b: OrderFlowGroup[]): boolean =>
  a.length === b.length && a.every((g, i) =>
    OrderFlowKey.equal(g.key, b[i].key) && g.members.length === b[i].members.length
    && g.members.every((m, k) => m === b[i].members[k]) && JSON.stringify(g.spans) === JSON.stringify(b[i].spans))

describe('主力订单流 · 2 万单压测数据', () => {
  it('拖图、捏合不重算并墙：视野一动只重排这一屏，切段 / 并墙 / 建组那一半走缓存', () => {
    const base = benchState('1m', 300)
    const r = new ChartRenderer(base)
    bandsCold(r)
    const before = OrderFlowWallCache.computed
    let next = base
    for (let i = 1; i <= 20; i++) {
      const v = base.viewport.view
      next = withViewport(base, { view: new ViewWindow(v.to - base.input.series.step * i, v.span * (1 + 0.01 * i)) })
      r.state = next
      bandsCold(r)
    }
    expect(OrderFlowWallCache.computed).toBe(before)
    const flow = next.overlay.orderFlow!
    r.state = withOverlay(next, { orderFlow: { ...flow, orders: flow.orders.slice(0, -1) } })
    bandsCold(r)
    expect(OrderFlowWallCache.computed).toBe(before + 1)
  })

  it('缓存的墙与直接 groups() 逐堵相同；按侧、类挑出来的与只拿那一类单现算的逐堵相同、先后相同', () => {
    const base = benchState('1m', 300)
    const r = new ChartRenderer(base)
    const flow = base.overlay.orderFlow!
    const cached = orderFlowEntry(r, flow).walls.map(w => w.group)
    const gap = orderFlowMergeGapMs(r), life = orderFlowMinLifeMs(r), step = flow.thresholds.step ?? null
    expect(sameGroups(cached, OrderFlowGroup.groups(flow.orders, gap, life, step))).toBe(true)
    for (const side of ['bid', 'ask'] as BookSide[]) {
      for (const contract of [false, true]) {
        const probe = cached.find(g => g.side === side && g.contract === contract)!
        expect(probe).toBeTruthy()
        const kind = flow.orders.filter(o => OrderFlowKey.sameKind(keyOf(o), probe.key))
        expect(sameGroups(cached.filter(g => OrderFlowKey.sameKind(g.key, probe.key)),
          OrderFlowGroup.groups(kind, gap, life, step))).toBe(true)
      }
    }
  })

  it('派生量建组时算一次：与逐行 / 逐单现算的结果逐位相同', () => {
    const base = benchState('1m', 300)
    const r = new ChartRenderer(base)
    const groups = orderFlowEntry(r, base.overlay.orderFlow!).walls.map(w => w.group)
    const q = (o: BigOrder) => thicknessQuarters(o.notional, o.threshold)
    for (const g of groups.slice(0, 400)) {
      expect(g.notional).toBe(g.books.reduce((s, b) => s + b.latest.notional, 0))
      expect(g.drawNotional).toBe(g.books.reduce((s, b) => s + q(b.latest) * b.latest.threshold / 4, 0))
      expect(g.quarters).toBe(g.books.reduce((s, b) => s + q(b.latest), 0))
      expect(g.firstSeenMs).toBe(Math.min(...g.members.map(m => m.firstSeenMs)))
      expect(g.isLive).toBe(g.members.some(m => m.status === 'live'))
      const ends = g.members.map(m => m.endMs).filter((x): x is number => x != null)
      expect(g.endMs).toBe(g.isLive ? null : Math.max(...ends))
      expect(g.hasFill).toBe(g.books.some(b => b.hasFill))
      expect(g.bucketCount).toBe(new Set(g.spans.map(s => s.bucket)).size)
      let top: BigOrder | null = null
      for (const b of g.books) {
        const o = b.latest
        if (!top || (q(o) !== q(top) ? q(top) < q(o) : orderId(top) > orderId(o))) top = o
      }
      expect(g.price).toBe(top?.price)
    }
  })

  it('D1 底噪按像素行并：同行同色相邻的并成一条，不同色 / 不同行 / 隔开的不并，封顶时留名次最前的', () => {
    const r = new ChartRenderer(benchState('1m', 300))
    const g = bandsCold(r).bands[0].group
    const band = (x0: number, x1: number, y: number, color: string): OrderFlowBand => ({
      group: g, frame: { x: x0, y: y - 0.5, w: x1 - x0, h: 1 }, color, dark: false, thin: false, role: 'noise', alpha: S.noiseAlpha, bracket: null,
    })
    const a = '#112233', b = '#445566'
    const noise = [band(10, 40, 100.2, a), band(30, 60, 100.4, a), band(60.4, 70, 100.1, a), band(10, 40, 100.2, b),
      band(10, 40, 101.6, a), band(73, 80, 100.2, a)]
    const out = orderFlowMergeNoise(noise, [0, 0, 0, 1, 0, 0], 200)
    expect(out.length).toBe(4)
    expect(out[0].rank).toBe(0)
    expect(out[0].frame.x).toBeCloseTo(10, 9); expect(out[0].frame.y).toBe(100)
    expect(out[0].frame.w).toBeCloseTo(60, 9); expect(out[0].frame.h).toBe(1)
    expect(out.map(s => s.rank)).toEqual([0, 3, 4, 5])
    expect(out.every(s => s.frame.h === 1 && s.frame.y === Math.round(s.frame.y))).toBe(true)
    expect(orderFlowMergeNoise(noise, [0, 0, 0, 1, 0, 0], 2).map(s => s.rank)).toEqual([0, 3])
  })

  it('D1 1 分钟 2 万单：底噪画的条数封在 200 以内且比逐条少，名义最大的那条在画，丢的只有名次靠后的；最小的那条仍选得中', () => {
    for (const visible of [300, 1500]) {
      const r = new ChartRenderer(benchState('1m', visible))
      const frame = bandsCold(r)
      const noise = frame.bands.filter(x => x.role === 'noise')
      const strokes = frame.noiseStrokes
      expect(noise.length).toBeGreaterThan(S.noiseDrawMax)
      expect(strokes.length).toBeLessThanOrEqual(S.noiseDrawMax)
      expect(strokes.length).toBeLessThan(noise.length)
      const covered = (x: OrderFlowBand) => strokes.some(s =>
        s.color === x.color && Math.abs(midY(s.frame) - midY(x.frame)) <= 0.5 && minX(s.frame) <= minX(x.frame) && maxX(s.frame) >= maxX(x.frame))
      expect(covered(noise[0])).toBe(true)
      noise.forEach((x, rank) => {
        if (covered(x)) return
        expect(strokes.length).toBe(S.noiseDrawMax)
        expect(strokes[strokes.length - 1].rank).toBeLessThan(rank)
      })
      const smallest = noise[noise.length - 1]
      r.state = withOverlay(r.state, { orderFlowSelected: smallest.group.key })
      const focus = orderFlowFocus(r, BW, BH)
      expect(focus).toBeTruthy()
      expect(eqKey(focus!.group.key, smallest.group.key)).toBe(true)
    }
  })

  it('D1 按时间粗筛不改结果：拖到最左、最右、中间，筛过的与整份逐条算的一样', () => {
    for (const interval of ['1m', '1d'] as Interval[]) {
      const base = benchState(interval, 300)
      const step = base.input.series.step
      for (const shift of [0, -150, -2990, -5990, 40]) {
        const v = base.viewport.view
        const r = new ChartRenderer(withViewport(base, { view: new ViewWindow(v.to + step * shift, v.span) }))
        const frame = bandsCold(r)
        const plotW = r.layout(BW, BH).plotW
        expect(frame.bands.every(x => maxX(x.frame) > 0 && minX(x.frame) < plotW)).toBe(true)
        expect(frame.bands.length, `${interval} ${shift}`).toBe(orderFlowFrameUnfiltered(r, BW, BH))
      }
    }
  })
})

// ------------------------------------------------------------------ 审查补充：括号三笔按物理像素切

describe('范围括号三笔对齐到物理像素后不交叠', () => {
  type R = { x: number; y: number; w: number; h: number }
  const record = () => {
    const rects: R[] = []
    const ctx = { fillStyle: '', fillRect: (x: number, y: number, w: number, h: number) => { rects.push({ x, y, w, h }) } }
    return { ctx: ctx as unknown as CanvasRenderingContext2D, rects }
  }
  const px = (v: number, s: number) => Math.round(v * s * 1e6) / 1e6
  const overlapArea = (a: R, b: R) =>
    Math.max(0, Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x)) * Math.max(0, Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y))

  for (const scale of [1, 2, 3]) {
    it(`@${scale}x：框左缘落在像素任何位置，竖笔与钩只贴边、整枚仍是 3 宽`, () => {
      for (let k = 0; k < 12; k++) {
        const x = 40 + k / 12, y = 100 + k / 7
        const { ctx, rects } = record()
        drawOrderFlowBracket(ctx, { x, y, w: S.bracketWidth, h: 30 }, '#5A7DFF', scale)
        expect(rects.length).toBe(3)
        for (let i = 0; i < rects.length; i++) {
          for (let j = i + 1; j < rects.length; j++) expect(overlapArea(rects[i], rects[j])).toBeLessThan(1e-9)
        }
        for (const q of rects) {
          for (const v of [q.x, q.y, q.x + q.w, q.y + q.h]) expect(Math.abs(px(v, scale) - Math.round(px(v, scale)))).toBeLessThan(1e-6)
        }
        const [stroke, top] = rects
        expect(top.x + top.w).toBeCloseTo(stroke.x, 9)
      }
    })
  }

  it('矮括号（不足两笔高）上下两钩不叠在一起', () => {
    const { ctx, rects } = record()
    drawOrderFlowBracket(ctx, { x: 10, y: 10, w: S.bracketWidth, h: 2.2 }, '#5A7DFF', 3)
    for (let i = 0; i < rects.length; i++) {
      for (let j = i + 1; j < rects.length; j++) expect(overlapArea(rects[i], rects[j])).toBeLessThan(1e-9)
    }
  })
})

describe('挂着的金额签不压用户画线上的字（OrderFlowChartTests.labelsDodgeDrawingLabels · 审查 B·待核实 4）', () => {
  it('大单价位上画一条水平线，签让开它的价格胶囊；藏线 / 删线签回原位；客线一样要让', () => {
    const { g } = fixtureRig()
    g.clearRight()
    const L = g.L
    const before = g.frame()
    const band = bandAt(before, 1)!
    expect(band).toBeTruthy()
    const label = before.labels.find(l => eqKey(l.key, band.group.key))!
    expect(label).toBeTruthy()
    const wall = g.price(midY(band.frame))
    const line = (id: string, hidden = false) => ({ ...decodeDrawing({ id, kind: 'hline', points: [{ t: g.b.lastTime, p: wall }] }), hidden })
    g.r.state = withOverlay(g.r.state, { drawings: [line('h')] })
    const boxes = drawingLabelBoxes(g.r, L.main, g.range, L)
    expect(boxes.length).toBe(1)
    expect(boxes.some(b => intersects(b, label.frame)), `夹具得真撞上：签 ${JSON.stringify(label.frame)}，胶囊 ${JSON.stringify(boxes)}`).toBe(true)
    const moved = g.frame().labels.find(l => eqKey(l.key, band.group.key))!
    expect(moved, '签不能因为让画线就没了').toBeTruthy()
    for (const b of boxes) expect(intersects(moved.frame, b), `签仍压着画线字`).toBe(false)
    expect(Math.abs(midY(moved.frame) - midY(band.frame))).toBeLessThanOrEqual(S.labelMaxShift)
    // 藏起来的线不画字，签也不必让。
    g.r.state = withOverlay(g.r.state, { drawings: [line('h', true)] })
    expect(drawingLabelBoxes(g.r, L.main, g.range, L)).toEqual([])
    expect(g.frame().labels.find(l => eqKey(l.key, band.group.key))!.frame).toEqual(label.frame)
    // 拖动中的那条（预览 ID）照屏幕取舍：屏上画的是预览，不是存档里那条。
    g.r.state = withOverlay(g.r.state, { drawings: [line('h')], drawingPreviewID: 'h' })
    expect(drawingLabelBoxes(g.r, L.main, g.range, L)).toEqual([])
    // 删掉线：盒子随画线换新，签回到原位。
    g.r.state = withOverlay(g.r.state, { drawings: [], drawingPreviewID: null })
    expect(g.frame().labels.find(l => eqKey(l.key, band.group.key))!.frame).toEqual(label.frame)
    // 对方分享来的线一样要让。
    g.r.guestDrawings = [line('g')]
    const guest = g.frame().labels.find(l => eqKey(l.key, band.group.key))!
    expect(guest.frame).not.toEqual(label.frame)
    for (const b of drawingLabelBoxes(g.r, L.main, g.range, L)) expect(intersects(guest.frame, b)).toBe(false)
    g.r.guestDrawings = []
    expect(g.frame().labels.find(l => eqKey(l.key, band.group.key))!.frame).toEqual(label.frame)
  })
})
