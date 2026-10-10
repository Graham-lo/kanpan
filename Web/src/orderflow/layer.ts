/* Hkline Web · 主力订单流 · 画在 K 线图上的三层（设计稿 2.3 / 2.4 / 2.5）
 *
 * 最底下（成交量柱之下）：深度热力（开了才画）。
 * 蜡烛下面：大单带——只画值得看的几道（取舍见 bands.ts），挂着的铺底、结束的一道细线。
 * 蜡烛上面：结束记号与右端标签（躲开蜡烛）、每根 K 线的大单与爆仓气泡（几何见 bigTags.ts）、梯子悬停那一行的淡色横带。
 * 气泡：每根上下各至多一枚——向上 U = 大买 + 空爆挂最高价之上（涨色），向下 D = 大卖 + 多爆挂最低价之下（跌色）；
 *   柄先画，再画小圆点（85% 实心），最后画泡（方向色 16% 填充、深色皮肤 22%，1.4 描边，方向色 11 号字）。
 *   悬停泡：填充升到 32%、放大 1.1、那根铺淡竖带、弹读数卡（顶上向上 / 向下两行拆出大单与爆仓）；点泡：选中那根、抽屉滚到它。
 *   小圆点不响应悬停与点击。爆仓用抽屉那份 LiqStore（drawerLiq）按本图 K 线并分钟；现货与 DXY 不拉。
 * 气泡不跟着数据层走：多图里每一格都画（非活动格子只有服务端历史），刷新后从服务端历史重画。
 * 行高和梯子是同一套「k 个细桶一行」，所以热力的格子、大单带的厚度和梯子的行一一对齐。
 * 时间 t 在图上的 x：timeToX(t) − 半根 K 线宽（一根 K 线的时间段正好铺满它的宽度）。
 */
import type { ChartGeometry, ChartLayer, TVChart } from '../chart/chart'
import { BT } from '../terms'
import { st } from '../app/store'
import type { BigOrder } from './types'
import { orderId } from './types'
import { shows, baseOfSymbol } from './settings'
import { bucketIndex } from './bucket'
import { rowOf, exName, venueName, outcomeText, EXCHANGE_NAMES } from './aggregate'
import { HeatCache, percentile, heatAlpha, edgeFade, type HeatCol } from './heat'
import { pickBands, liveAlpha, placeLabels, placeMark, mergedWalls, wallOf, wallId, bookRows, wallPeak, MAX_MARKS, ENDED_LINE, HIGHLIGHT_ALPHA, type Rect, type BookRow } from './bands'
import { OrderFlowGroup } from './group'
import { OF, rowsPerLine, bandColor, bandInk, productColor, isDarkBg, rgbOf, showCard, hideCard, amt, hms, mdhm, durShort, decFor, px, peak, canvasFont } from './state'
import { esc } from '../ui/dom'
import { hexA } from '../util/format'
import { flowOf, ensureHistory } from '../chart/tradeFlow'
import { BigBarCache, LevelCache, planBubbles, unitFor, udOf, BUBBLE, type Bubble, type BubbleIn, type Rect as BubbleRect, type BarBig, type BarLiq, type LiqBars } from './bigTags'
import { LiqBarCache, noLiq } from './liquidation'
import { hoverCardHtml, ivShort } from './drawerView'
import { drawerChartDrawn, drawerLiq } from './drawer'

/** 读数卡分簿那行小字最多点几家（只写各家金额，不写「+N 本」这类计数）。用户 2026-10-08：他关心的是品种和数据，哪家交易所权重不大 */
export const CARD_BOOKS = 3
interface BandHit { x0: number; x1: number; y0: number; y1: number; v: Vis }
/** 一道要画的带：一堵墙（w）+ 它的代表单（o：最大那本簿的最新一单，定颜色和记号）+ 读数卡的分簿行 */
interface Vis { o: BigOrder; w: OrderFlowGroup; rows: BookRow[]; id: string; live: boolean; x0: number; x1: number; y0: number; h: number; mid: number; pk: number }
interface HeatDraw { cols: HeatCol[]; xs: number[]; ws: number[]; rowLo: number; rowHi: number; k: number; step: number; top: number; bottom: number }

function rrect(c: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
  c.beginPath()
  if (typeof c.roundRect === 'function') c.roundRect(x, y, w, h, r); else c.rect(x, y, w, h)
}

const xOf = (g: ChartGeometry, t: number): number => g.timeToX(t) - g.spacing / 2
/** 成交量垫在主图底部的比例（同 chart.ts 的 VOL_H）：气泡不落进这一截 */
const VOL_H = 0.16
/** 气泡离图例文字至少留这么多 */
const LEGEND_PAD = 4
/** 悬停 / 点击命中：泡半径外再放宽这么多 */
const HIT_PAD = 2

/** 每张图此刻画出来的气泡（压测 / 截图脚本按它找悬停位置；界面不读） */
export const bubblesOf = new WeakMap<TVChart, () => readonly Bubble[]>()
/** 一根的数据（悬停卡用）：大单合计（没有大单 null）与爆仓（这只没有爆仓项时 undefined） */
interface BarCardData { t: number; t1: number; d: BarBig | null; l: BarLiq | null | undefined }

export function createLayer(chart: TVChart, cellOf: () => { symbol: string; iv: string }): ChartLayer {
  let bands: BandHit[] = []
  let bubbles: Bubble[] = []
  /** 鼠标停在哪枚泡上（那根的开盘时间 + 哪一侧）：泡放大加深，图上给那根铺一道淡竖带，不然泡比根宽、十字线又停在旁边那根，看不出卡上的数是哪根的 */
  let hoverB: { t: number; side: Bubble['side'] } | null = null
  bubblesOf.set(chart, () => bubbles)
  let barData = new Map<number, BarCardData>()
  const bigCache = new BigBarCache()
  const levelCache = new LevelCache()
  const liqCache = new LiqBarCache()
  let flowSym = ''
  const onHistory = (): void => { chart.dirty = true }
  // 爆仓有新数据：这张图重画（图拆了就自己摘掉）
  const onLiq = (): void => { if (chart.dead) drawerLiq.listeners.delete(onLiq); else chart.dirty = true }
  drawerLiq.listeners.add(onLiq)
  // 图例是 DOM（左上角），尺寸变了 ResizeObserver 推过来，画气泡时不去读布局
  let legend: BubbleRect | null = null
  if (typeof ResizeObserver !== 'undefined' && chart.legendEl) {
    new ResizeObserver(() => {
      const el = chart.legendEl
      const P = LEGEND_PAD
      legend = el.offsetWidth && el.offsetHeight ? { x: el.offsetLeft - P, y: el.offsetTop - P, w: el.offsetWidth + 2 * P, h: el.offsetHeight + 2 * P } : null
    }).observe(chart.legendEl)
  }
  let heat: HeatDraw | null = null
  let geo: ChartGeometry | null = null
  const cache = new HeatCache()
  let img: HTMLCanvasElement | null = null

  const mine = (): boolean => {
    const f = OF.feed
    return !!f && f.symbol === cellOf().symbol.toUpperCase()
  }

  function drawHeat(c: CanvasRenderingContext2D, g: ChartGeometry, k: number, step: number): void {
    const store = OF.heat
    heat = null
    if (!store || store.step !== step) return
    const now = Date.now()
    const ivMs = g.iv
    cache.reset(`${step}|${k}|${ivMs}`)
    const cols: HeatCol[] = [], xs: number[] = [], ws: number[] = []
    if (ivMs > 60_000) {
      for (let i = g.from - 1; i <= g.to + 1; i++) {
        const t0 = g.timeOf(i), t1 = g.timeOf(i + 1)
        if (t0 > now) break
        cols.push(cache.column(store, t0, t1, k, now)); xs.push(g.indexToX(i) - g.spacing / 2); ws.push(g.spacing)
      }
    } else {
      // 1 分钟及以下：按秒成列，一列至少 2 px（不够就几秒并一列）
      const pxPerMs = g.spacing / ivMs
      const need = Math.max(1, Math.ceil(2 / (pxPerMs * 1000)))
      const w = ([1, 2, 3, 5, 10, 15, 20, 30, 60].find(x => x >= need) ?? 60) * 1000
      const tA = g.timeOf(g.from - 1), tB = Math.min(g.timeOf(g.to + 1), now + w)
      cache.reset(`${step}|${k}|${ivMs}|${w}`)
      for (let t = Math.floor(tA / w) * w; t < tB; t += w) {
        cols.push(cache.column(store, t, t + w, k, now)); xs.push(xOf(g, t)); ws.push(pxPerMs * w)
      }
    }
    cache.sweep()
    if (!cols.length) return
    const rs = step * k
    const rowLo = rowOf(bucketIndex(g.range.min, step), k), rowHi = rowOf(bucketIndex(g.range.max, step), k)
    const rows = rowHi - rowLo + 1
    if (rows <= 0 || rows > 3000) return
    // 亮度：值 ÷ 画面里可见格子的第 95 百分位
    const vis: number[] = []
    for (const col of cols) for (let i = 0; i < col.n; i++) { const r = col.lo + i; if (r >= rowLo && r <= rowHi && col.vals[i] > 0) vis.push(col.vals[i]) }
    if (!vis.length) return
    const p95 = percentile(vis, 0.95) || 1
    const W = cols.length
    if (!img) img = document.createElement('canvas')
    if (img.width !== W || img.height !== rows) { img.width = W; img.height = rows }
    const ic = img.getContext('2d')!
    const data = ic.createImageData(W, rows)
    const [cr, cg, cb] = rgbOf(g.colors.accent)
    const d = data.data
    // 边沿淡入：最早有数据的那一列往右约 24 px、每列簿深度的上下沿约 10 px，免得数据起点切出硬边
    let first = -1
    for (let ci = 0; ci < W && first < 0; ci++) if (cols[ci].n) first = ci
    const colSpan = Math.round(24 / Math.max(0.5, ws[0] || 1))
    const rowSpan = Math.round(10 / Math.max(0.5, g.pane.h / rows))
    for (let ci = 0; ci < W; ci++) {
      const col = cols[ci]
      const fx = first < 0 ? 1 : edgeFade(ci, first, Infinity, colSpan)
      for (let i = 0; i < col.n; i++) {
        const r = col.lo + i
        if (r < rowLo || r > rowHi) continue
        const v = col.vals[i]
        if (!(v > 0)) continue
        const a = heatAlpha(v, p95) * fx * edgeFade(i, 0, col.n - 1, rowSpan)
        const o = ((rowHi - r) * W + ci) * 4
        d[o] = cr; d[o + 1] = cg; d[o + 2] = cb; d[o + 3] = Math.round(a * 255)
      }
    }
    ic.putImageData(data, 0, 0)
    c.imageSmoothingEnabled = false
    // 一行一条地贴（对数坐标下每行高度不同）；列宽是均匀的
    const x0 = xs[0], wAll = xs[W - 1] + ws[W - 1] - x0
    for (let r = rowLo; r <= rowHi; r++) {
      const yT = g.priceToY((r + 1) * rs), yB = g.priceToY(r * rs)
      const h = yB - yT
      if (h <= 0) continue
      c.drawImage(img, 0, rowHi - r, W, 1, x0, yT, wAll, h)
    }
    c.imageSmoothingEnabled = true
    heat = { cols, xs, ws, rowLo, rowHi, k, step, top: g.pane.y, bottom: g.pane.y + g.pane.h }
  }

  /** 这一帧要画的带（under 画底、over 画记号和标签共用） */
  let plan: { live: Vis[]; ended: Vis[]; dark: boolean } | null = null

  /** 一个矩形压没压到蜡烛（影线 + 实体，左右各留 1 px） */
  function hitsCandles(g: ChartGeometry, r: Rect): boolean {
    const i0 = Math.floor(g.xToIndex(r.x)) - 1, i1 = Math.ceil(g.xToIndex(r.x + r.w)) + 1
    const half = Math.max(1.5, g.spacing * 0.42) + 1
    for (let i = Math.max(i0, g.from - 1); i <= Math.min(i1, g.to + 1); i++) {
      const b = g.bar(i)
      if (!b) continue
      const cx = g.indexToX(i)
      if (cx + half < r.x || cx - half > r.x + r.w) continue
      const yT = g.priceToY(b.h), yB = g.priceToY(b.l)
      if (yB + 1 >= r.y && yT - 1 <= r.y + r.h) return true
    }
    return false
  }

  /** 蜡烛下面：一堵墙一道带（同侧同类、相邻桶、时间上连着的并成一道，和手机同一套 OrderFlowGroup）；
   *  挂着的铺底（0.14–0.20，最大的最深），结束的只画一道细线；不描边 */
  function drawBands(c: CanvasRenderingContext2D, g: ChartGeometry, k: number, step: number): void {
    bands = []
    plan = null
    const snap = OF.snap
    if (!snap || !st.orderFlow) return
    const rs = step * k
    const tFrom = g.timeOf(g.from - 1), tTo = g.timeOf(g.to + 2)
    const top = g.pane.y, bottom = g.pane.y + g.pane.h
    const disp = { ...OF.prefs.display, history: st.orderFlowHistory }
    const bar = Math.max(0, g.iv || 0)
    const opts = { gapMs: OrderFlowGroup.mergeGapMs(bar), minLifeMs: bar, step: snap.thresholds?.step ?? step }
    const walls = mergedWalls(snap.orders, o => shows(disp, o), JSON.stringify(disp), opts)
    const hlWall = wallOf(walls, OF.highlight, snap.orders, opts.step, o => shows(disp, o))
    const list = hlWall && !walls.includes(hlWall) ? [...walls, hlWall] : walls
    const cands: Vis[] = []
    for (const w of list) {
      const end = w.endMs
      if (end != null && end < tFrom) continue
      if (w.firstSeenMs > tTo) continue
      const rLo = rowOf(w.bucketLow, k), rHi = rowOf(w.bucketHigh, k)
      const yT = g.priceToY((rHi + 1) * rs), yB = g.priceToY(rLo * rs)
      const mid = (yT + yB) / 2
      if (mid > bottom || mid < top) continue
      const h = Math.max(3, Math.min(24 * (rHi - rLo + 1), yB - yT))
      const x0 = Math.max(-2, xOf(g, w.firstSeenMs))
      const x1 = end == null ? g.plotW : Math.min(g.plotW, xOf(g, end))
      if (x1 < 0 || x0 > g.plotW) continue
      const rows = bookRows(w, m => peak(m, orderId(m)))
      const top1 = rows[0]?.book.latest ?? w.members[0]
      cands.push({ o: top1, w, rows, id: wallId(w, OF.highlight), live: end == null, x0, x1: Math.max(x0 + 2, x1), y0: mid - h / 2, h, mid, pk: wallPeak(rows) })
    }
    const dark = isDarkBg(g.colors.bg)
    const pick = pickBands(cands, OF.highlight)
    plan = { ...pick, dark }
    // 结束的：1 px 细线（在蜡烛下面）
    for (const v of pick.ended) {
      const hl = OF.highlight === v.id
      c.fillStyle = bandColor(v.o.product, v.o.side, hl ? 0.9 : ENDED_LINE[dark ? 'dark' : 'light'], dark)
      c.fillRect(v.x0, Math.round(v.mid) - (hl ? 1 : 0), v.x1 - v.x0, hl ? 2 : 1)
      bands.push({ x0: v.x0, x1: v.x1, y0: v.mid - 4, y1: v.mid + 4, v })
    }
    // 挂着的：小的先画、大的后画
    const n = pick.live.length
    for (let rank = n - 1; rank >= 0; rank--) {
      const v = pick.live[rank]
      const hl = OF.highlight === v.id
      c.fillStyle = bandColor(v.o.product, v.o.side, hl ? HIGHLIGHT_ALPHA[dark ? 'dark' : 'light'] : liveAlpha(rank, n, dark), dark)
      c.fillRect(v.x0, v.y0, v.x1 - v.x0, v.h)
      // 左缘 2 px 品类细条：方向看底色，现货 / 永续看这一道
      if (v.x0 > -2) { c.fillStyle = productColor(v.o.product, dark); c.fillRect(v.x0, v.y0, 2, v.h) }
      if (hl) { c.strokeStyle = g.colors.accent; c.lineWidth = 1; c.strokeRect(v.x0 + .5, v.y0 + .5, v.x1 - v.x0 - 1, v.h - 1) }
      bands.push({ x0: v.x0, x1: v.x1, y0: v.y0, y1: v.y0 + v.h, v })
    }
  }

  /** 蜡烛上面：结束记号（峰值前几道，躲开蜡烛）与右端标签（最多 8 个、互不重叠、不压价格轴、不压蜡烛） */
  /** 这一帧挂单带的金额标签与结束记号占的格（气泡躲开它们；每帧 drawBandMarks 重算） */
  let markRects: BubbleRect[] = []
  function drawBandMarks(c: CanvasRenderingContext2D, g: ChartGeometry): void {
    const p = plan
    markRects = []
    if (!p) return
    const top = g.pane.y, bottom = g.pane.y + g.pane.h
    const blocked = (r: Rect): boolean => hitsCandles(g, r)
    const marked = new Set<string>()
    const byPk = [...p.ended].sort((a, b) => b.pk - a.pk)
    const S = 7
    for (let i = 0; i < byPk.length; i++) {
      const v = byPk[i]
      if (i >= MAX_MARKS && OF.highlight !== v.id) continue
      if (v.x1 > g.plotW - 2) continue
      const m = placeMark(v.x1, v.mid, S, v.x0, g.spacing, blocked, bottom)
      endMark(c, v.o, m.x, m.y, S, p.dark)
      markRects.push({ x: m.x - S / 2, y: m.y - S / 2, w: S, h: S })
      marked.add(v.id)
    }
    c.font = canvasFont(11, 600)
    c.textBaseline = 'middle'
    c.textAlign = 'left'
    const all = [...p.live, ...p.ended]
    const texts = all.map(v => bandLabel(v))
    const H = 16
    const reqs = all.map((v, i) => ({
      right: (v.live ? v.x1 - 6 : v.x1 - (marked.has(v.id) ? 12 : 4)), left: v.x0 + 2,
      y: v.mid, w: Math.ceil(c.measureText(texts[i]).width) + 10, h: H, prio: v.pk + (OF.highlight === v.id ? 1e18 : 0),
    }))
    const spots = placeLabels(reqs, { top: top + 2, bottom: bottom - 2, maxRight: g.plotW - 6 }, blocked)
    for (let i = 0; i < all.length; i++) {
      const r = spots[i]
      if (!r) continue
      const v = all[i]
      markRects.push(r)
      // 先垫一层 70% 的画布底，蜡烛不从字后面透出来（规范 §5b）
      c.fillStyle = hexA(g.colors.bg, 0.7)
      rrect(c, r.x, r.y, r.w, r.h, 3); c.fill()
      c.fillStyle = bandColor(v.o.product, v.o.side, p.dark ? 0.2 : 0.12, p.dark)
      rrect(c, r.x, r.y, r.w, r.h, 3); c.fill()
      c.fillStyle = bandInk(v.o.product, v.o.side, p.dark)
      c.fillText(texts[i], r.x + 5, r.y + r.h / 2 + 0.5)
    }
  }

  function endMark(c: CanvasRenderingContext2D, o: BigOrder, x: number, y: number, s: number, dark: boolean): void {
    const col = bandInk(o.product, o.side, dark)
    c.fillStyle = col; c.strokeStyle = col; c.lineWidth = 1.25
    if (o.status === 'filled') {
      c.beginPath(); c.moveTo(x, y - s / 2); c.lineTo(x + s / 2, y + s / 2); c.lineTo(x - s / 2, y + s / 2); c.closePath(); c.fill()
    } else if (o.status === 'cancelled') {
      const h = s - 2
      c.strokeRect(x - h / 2 + .5, y - h / 2 + .5, h - 1, h - 1)
      if (o.filledNotional > 0) c.fillRect(x - h / 2 + .5, y, h - 1, h / 2 - .5)
    }
  }

  function drawBubbles(c: CanvasRenderingContext2D, g: ChartGeometry): void {
    bubbles = []
    // 气泡跟「图上大单标记」走（共用字段 bigTradeSigns，同手机），不再跟订单流横带同一颗开关
    if (!st.bigTradeSigns) return
    const sym = cellOf().symbol.toUpperCase()
    if (!sym || sym === 'DXY') return
    const f = flowOf(sym)
    if (sym !== flowSym) { if (flowSym) flowOf(flowSym).listeners.delete(onHistory); flowSym = sym }
    const now = Date.now()
    if (!(g.iv < 60_000)) ensureHistory(f, onHistory, now)
    bigCache.begin(f, `${sym}|${g.iv}`, now)
    // 爆仓：合约品种才有；秒级周期不并（分钟粒度）
    let liq: LiqBars | null = null
    const hasLiq = !noLiq(sym) && g.iv >= 60_000
    if (hasLiq) {
      const base = baseOfSymbol(sym).base
      drawerLiq.ensure(base, now)
      liq = liqCache.of(drawerLiq.state(base), base, g.iv)
    }
    const levels = levelCache.get(bigCache, f, chart, now, unitFor(f, mine() ? OF.bigTrade : 0), liq)
    if (!levels) return
    const list: BubbleIn[] = []
    barData = new Map()
    const lo = Math.max(0, Math.floor(g.from) - 1), hi = Math.ceil(g.to) + 1
    for (let i = lo; i <= hi; i++) {
      const t0 = g.timeOf(i)
      if (t0 > now) break
      const t1 = g.timeOf(i + 1)
      const d = bigCache.get(f, t0, t1, now), l = liq ? liq.at(t0, t1) : null
      if (!d && !l) continue
      const u = udOf(d, l)
      if (Math.max(u.up, u.down) < levels.dot) continue
      const b = g.bar(i)
      if (!b) continue
      const x = g.indexToX(i)
      if (x < -40 || x > g.plotW + 40) continue
      list.push({ i, t: t0, x, yHigh: g.priceToY(b.h), yLow: g.priceToY(b.l), up: u.up, down: u.down })
      barData.set(t0, { t: t0, t1, d, l: hasLiq ? l : undefined })
    }
    if (!list.length) return
    const avoid: BubbleRect[] = chart.textRects.concat(markRects)
    if (legend) avoid.push(legend)
    const font = canvasFont(BUBBLE.font, 650)
    c.font = font
    const volOn = chart.ind.vol && chart.deg.vol && !chart.hidden.has('vol')
    bubbles = planBubbles(list, {
      levels, bw: g.spacing, top: g.pane.y + 2, bottom: g.pane.y + g.pane.h * (volOn ? 1 - VOL_H : 1) - 2, plotW: g.plotW - 2, avoid,
      measure: t => c.measureText(t).width,
      text: amt,
    })
    // 开发构建把这一帧的泡挂在画布上（截图脚本 scripts/pc-bigtrade.mjs 据此找泡去悬停 / 点）
    if (import.meta.env.DEV) (chart.canvas as HTMLCanvasElement & { __bubbles?: unknown }).__bubbles = bubbles.map(b => ({ t: b.t, side: b.side, x: b.x, y: b.cy, r: b.r, text: b.text, bubble: b.bubble }))
    const hiOn = OF.barHi && OF.barHi.symbol === sym && OF.barHi.until > now ? OF.barHi.t : null
    const hot = (b: Bubble): boolean => b.bubble && (hiOn === b.t || (hoverB != null && hoverB.t === b.t && hoverB.side === b.side))
    const colOf = (b: Bubble): string => b.side === 'up' ? g.colors.up : g.colors.down
    const fillA = isDarkBg(g.colors.bg) ? BUBBLE.fillDark : BUBBLE.fill
    // 柄全部先画（只有泡有柄），再画点，最后画泡
    c.lineWidth = BUBBLE.stemW
    for (const b of bubbles) {
      if (!b.bubble) continue
      const s = hot(b) ? BUBBLE.hoverScale : 1
      const end = b.side === 'up' ? b.cy + b.r * s : b.cy - b.r * s
      if (Math.abs(end - b.anchor) < 0.5) continue
      c.strokeStyle = hexA(colOf(b), BUBBLE.stemAlpha)
      c.beginPath(); c.moveTo(b.x, b.anchor); c.lineTo(b.x, end); c.stroke()
    }
    for (const b of bubbles) {
      if (b.bubble) continue
      c.fillStyle = hexA(colOf(b), BUBBLE.dotAlpha)
      c.beginPath(); c.arc(b.x, b.cy, b.r, 0, Math.PI * 2); c.fill()
    }
    c.textAlign = 'center'; c.textBaseline = 'middle'; c.lineWidth = BUBBLE.stroke; c.font = font
    for (const b of bubbles) {
      if (!b.bubble) continue
      const col = colOf(b), on = hot(b), r = b.r * (on ? BUBBLE.hoverScale : 1)
      c.beginPath(); c.arc(b.x, b.cy, r, 0, Math.PI * 2)
      c.fillStyle = hexA(col, on ? BUBBLE.fillHover : fillA); c.fill()
      c.strokeStyle = col; c.stroke()
      c.fillStyle = col
      c.fillText(b.text, b.x, b.cy + .5)
    }
    if (hiOn != null) setTimeout(() => { chart.dirty = true }, Math.max(0, OF.barHi!.until - now) + 20)
  }

  function drawHoverRow(c: CanvasRenderingContext2D, g: ChartGeometry): void {
    const h = OF.hoverRow
    if (!h) return
    const y0 = g.priceToY(h.high), y1 = g.priceToY(h.low)
    c.fillStyle = hexA(g.colors.accent, 0.12)
    c.fillRect(0, y0, g.plotW, Math.max(1, y1 - y0))
  }

  /** 右端标签：只写金额。不写交易所名、不写「·N本」——用户 2026-10-08：K 线图上只要数额，不要额外信息 */
  function bandLabel(v: Vis): string {
    return amt(v.pk)
  }

  /** 读数卡（§64 悬停卡的样子）：头一行类 · 侧 · 价位；大字合计；首见 / 已挂 / 累计成交这些主数据；
   *  最后才是一行小字点出前几本簿（「Bybit永续 1.2M · 币安永续 0.9M」）——交易所是次要信息，不再一本一行占满卡片 */
  function bandCard(b: BandHit, dec: number, step: number): string {
    const { w, rows } = b.v
    const st0 = w.step ?? step
    const d = decFor(st0, dec)
    const lo = st0 > 0 ? w.bucketLow * st0 : w.priceLow, hi = st0 > 0 ? (w.bucketHigh + 1) * st0 : w.priceHigh
    const now = Date.now()
    const buy = w.side === 'bid'
    const kind = w.contract ? '合约' : '现货'
    const head = `<div class="hc-h"><i class="sw" style="background:${productColor(b.v.o.product, plan?.dark ?? false)}"></i><b>${kind} · <span class="${buy ? 'up' : 'dn'}">${buy ? '买单' : '卖单'}</span></b>· <span class="num">${px(lo, d)} – ${px(hi, d)}</span></div>`
    const net = `<div class="hc-net"><span class="v num ${buy ? 'up' : 'dn'}">${amt(b.v.pk)}</span><span class="l">${w.isLive ? BT.statusLive : BT.statusEnded}</span></div>`
    const one = w.members.length === 1 ? w.members[0] : null
    const fill = w.filledNotional > 0 ? `${amt(w.filledNotional)}` : '—'
    const meta: [string, string, string][] = [
      ['首见', mdhm(w.firstSeenMs), ''],
      w.endMs == null ? [BT.held, durShort(now - w.firstSeenMs), ''] : ['结束', mdhm(w.endMs), durShort(w.endMs - w.firstSeenMs)],
      ['累计成交', fill, w.filledNotional > 0 ? `${Math.round(w.fillRatio * 100)}%` : ''],
    ]
    if (one && !w.isLive) meta.push(['结局', outcomeText(one), ''])
    const metaKv = meta.map(([k, v, em]) => `<span>${k}</span><b class="num">${v}</b><em class="num">${em}</em>`).join('')
    // 分簿只占一行小字：按金额从大到小点前 CARD_BOOKS 家的金额；不写「+N 本」这类计数（用户 2026-10-08：一律只要数额）
    const books = rows.slice(0, CARD_BOOKS).map(r => `${esc(venueName(exName(r.book.exchange), r.book.product))} <b class="num">${amt(r.usd)}</b>`).join(' · ')
    return `<div class="hc hc-band">${head}${net}<div class="hc-kv">${metaKv}</div><div class="hc-books">${books}</div></div>`
  }

  function heatCard(x: number, y: number, g: ChartGeometry): string | null {
    const h = heat
    if (!h || !OF.prefs.heat) return null
    let ci = -1
    for (let i = 0; i < h.cols.length; i++) if (x >= h.xs[i] && x < h.xs[i] + h.ws[i]) { ci = i; break }
    if (ci < 0) return null
    const price = g.yToPrice(y)
    const r = rowOf(bucketIndex(price, h.step), h.k)
    const col = h.cols[ci]
    const i = r - col.lo
    if (i < 0 || i >= col.n || !(col.vals[i] > 0)) return null
    const rs = h.step * h.k
    const d = decFor(rs, g.dec)
    const parts = EXCHANGE_NAMES.map((_, q) => col.parts[i * EXCHANGE_NAMES.length + q])
    const split = col.split
      ? EXCHANGE_NAMES.map((n, q) => `<div class="of-card-r"><span>${n}</span><b class="num">${parts[q] > 0 ? amt(parts[q]) : '—'}</b></div>`).join('')
      : ''
    const t = col.t1 - col.t0 <= 60_000 ? `${mdhm(col.t0).slice(0, 5)} ${hms(col.t0)}` : `${mdhm(col.t0)} – ${hms(col.t1).slice(0, 5)}`
    return `<div class="of-card-h"><i style="background:${g.colors.accent}"></i>深度热力 · ${t}</div>
      <div class="of-card-r"><span>价位</span><b class="num">${px(r * rs, d)} – ${px((r + 1) * rs, d)}</b></div>
      <div class="of-card-r"><span>挂单名义</span><b class="num">${amt(col.vals[i])}</b></div>${split}`
  }

  // 悬停卡与抽屉「每根」同一套样子（drawerView.hoverCardHtml），顶上加向上 / 向下两行
  function bubbleCard(b: Bubble): string {
    const e = barData.get(b.t)
    return e ? hoverCardHtml(e.d, mdhm(e.t), ivShort(e.t1 - e.t), e.l) : ''
  }

  /** 一根上的强调色竖带（画在蜡烛下面）：抽屉里点选的那根带底边粗线；鼠标停在泡上的那根只有淡带 */
  function drawBar(c: CanvasRenderingContext2D, g: ChartGeometry, t: number, strong: boolean): void {
    const x = xOf(g, t)
    if (x + g.spacing < 0 || x > g.plotW) return
    const [r, gg, b] = rgbOf(g.colors.accent)
    const w = Math.max(2, g.spacing)
    c.fillStyle = `rgba(${r},${gg},${b},${strong ? '.09' : '.13'})`
    c.fillRect(x, g.pane.y, w, g.pane.h)
    if (!strong) return
    c.fillStyle = `rgba(${r},${gg},${b},.85)`
    c.fillRect(x, g.pane.y + g.pane.h - 3, w, 3)
  }

  function drawSel(c: CanvasRenderingContext2D, g: ChartGeometry): void {
    const s = OF.selBar
    if (s && s.symbol === cellOf().symbol.toUpperCase() && s.iv === g.iv && OF.api?.activeChart()?.chart === chart) drawBar(c, g, s.t, true)
    if (hoverB != null && hoverB.t !== s?.t) drawBar(c, g, hoverB.t, false)
  }

  /** 悬停换了泡（或离开）就重画一帧 */
  function setHover(b: Bubble | null): void {
    if (hoverB?.t === b?.t && hoverB?.side === b?.side) return
    hoverB = b ? { t: b.t, side: b.side } : null; chart.dirty = true
  }

  /** 鼠标下的泡（小圆点不算）：落在半径（悬停放大后的）+ 2 以内，取圆心最近的 */
  const bubbleAt = (x: number, y: number): Bubble | null => {
    let best: Bubble | null = null, bd = Infinity
    for (const b of bubbles) {
      if (!b.bubble) continue
      const d = Math.hypot(x - b.x, y - b.cy)
      if (d <= b.r * BUBBLE.hoverScale + HIT_PAD && d < bd) { best = b; bd = d }
    }
    return best
  }

  const stepK = (g: ChartGeometry): [number, number] | null => {
    if (!mine()) return null
    const step = OF.feed?.model.scheme?.step
    return step ? [step, rowsPerLine(g, step, cellOf().iv)] : null
  }

  return {
    // 热力铺在成交量柱与蜡烛、均线之下；同一帧里所有列（回填 + 实时）用同一个 p95 归一
    back(c, g) {
      geo = g
      const sk = stepK(g)
      if (sk && OF.prefs.heat) drawHeat(c, g, sk[1], sk[0]); else heat = null
    },
    under(c, g) {
      geo = g
      drawSel(c, g)
      const sk = stepK(g)
      if (!sk) { bands = []; plan = null; return }
      drawBands(c, g, sk[1], sk[0])
    },
    over(c, g) {
      geo = g
      if (mine()) drawBandMarks(c, g)
      drawBubbles(c, g)
      if (mine()) drawHoverRow(c, g)
    },
    after(g) {
      if (mine()) OF.onChartDrawn?.(chart, g)
      drawerChartDrawn(chart)
    },
    hover(x, y, cx, cy) {
      if (!geo) return false
      const bb = bubbleAt(x, y)
      setHover(bb)
      if (bb) { showCard(bubbleCard(bb), cx, cy); return true }
      if (!mine()) { hideCard(); return false }
      const dec = geo.dec
      const step = OF.feed?.model.scheme?.step ?? 0
      for (let i = bands.length - 1; i >= 0; i--) {
        const b = bands[i]
        if (x >= b.x0 && x <= b.x1 + 4 && y >= b.y0 - 1 && y <= b.y1 + 1) { showCard(bandCard(b, dec, step), cx, cy); return true }
      }
      const h = heatCard(x, y, geo)
      if (h) { showCard(h, cx, cy); return 'soft' }
      hideCard()
      return false
    },
    leave() { setHover(null); hideCard() },
    click(x, y) {
      const bb = bubbleAt(x, y)
      if (bb) {
        const sym = cellOf().symbol.toUpperCase()
        OF.barHi = { symbol: sym, t: bb.t, until: Date.now() + 1500 }
        OF.selBar = { symbol: sym, iv: chart.iv, t: bb.t }
        chart.dirty = true
        OF.revealBar?.(sym, bb.t)
        return true
      }
      if (!mine()) return false
      for (let i = bands.length - 1; i >= 0; i--) {
        const b = bands[i]
        if (x >= b.x0 && x <= b.x1 + 4 && y >= b.y0 - 1 && y <= b.y1 + 1) { OF.highlight = b.v.id; chart.dirty = true; OF.reveal?.(b.v.id); return true }
      }
      return false
    },
  }
}
