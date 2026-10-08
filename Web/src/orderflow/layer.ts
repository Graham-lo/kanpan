/* Hkline Web · 主力订单流 · 画在 K 线图上的三层（设计稿 2.3 / 2.4 / 2.5）
 *
 * 最底下（成交量柱之下）：深度热力（开了才画）。
 * 蜡烛下面：大单带——只画值得看的几道（取舍见 bands.ts），挂着的铺底、结束的一道细线。
 * 蜡烛上面：结束记号与右端标签（躲开蜡烛）、每根 K 线的大单签（bigTags.ts）、梯子悬停那一行的淡色横带。
 * 大单签不跟着数据层走：多图里每一格都画（非活动格子只有服务端历史），刷新后从服务端历史重画。
 * 行高和梯子是同一套「k 个细桶一行」，所以热力的格子、大单带的厚度和梯子的行一一对齐。
 * 时间 t 在图上的 x：timeToX(t) − 半根 K 线宽（一根 K 线的时间段正好铺满它的宽度）。
 */
import type { ChartGeometry, ChartLayer, TVChart } from '../chart/chart'
import { st } from '../app/store'
import type { BigOrder } from './types'
import { orderId } from './types'
import { shows } from './settings'
import { bucketIndex } from './bucket'
import { rowOf, exName, venueName, outcomeText, EXCHANGE_NAMES } from './aggregate'
import { HeatCache, percentile, heatAlpha, edgeFade, type HeatCol } from './heat'
import { pickBands, liveAlpha, placeLabels, placeMark, MAX_MARKS, ENDED_LINE, HIGHLIGHT_ALPHA, type Rect } from './bands'
import { OF, rowsPerLine, bandColor, bandInk, isDarkBg, rgbOf, showCard, hideCard, amt, hms, mdhm, durShort, PRODUCT_FULL, decFor, px, peak, canvasFont } from './state'
import { esc } from '../ui/dom'
import { hexA } from '../util/format'
import { flowOf, ensureHistory } from '../chart/tradeFlow'
import { BigBarCache, TierCache, planTags, unitFor, type Tag, type TagIn, type Rect as TagRect, type BarBig } from './bigTags'
import { hoverCardHtml, ivShort } from './drawerView'
import { drawerChartDrawn } from './drawer'

interface BandHit { x0: number; x1: number; y0: number; y1: number; o: BigOrder; id: string }
interface HeatDraw { cols: HeatCol[]; xs: number[]; ws: number[]; rowLo: number; rowHi: number; k: number; step: number; top: number; bottom: number }

function rrect(c: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
  c.beginPath()
  if (typeof c.roundRect === 'function') c.roundRect(x, y, w, h, r); else c.rect(x, y, w, h)
}

const xOf = (g: ChartGeometry, t: number): number => g.timeToX(t) - g.spacing / 2
/** 成交量垫在主图底部的比例（同 chart.ts 的 VOL_H）：大单签不落进这一截 */
const VOL_H = 0.16
/** 签离图例文字至少留这么多 */
const LEGEND_PAD = 4

/** 每张图此刻画出来的签（压测 / 截图脚本按它找悬停位置；界面不读） */
export const tagsOf = new WeakMap<TVChart, () => readonly Tag[]>()

export function createLayer(chart: TVChart, cellOf: () => { symbol: string; iv: string }): ChartLayer {
  let bands: BandHit[] = []
  let tags: Tag[] = []
  /** 鼠标停在哪枚签上（那根的开盘时间）：图上给那根铺一道淡竖带，不然签比根宽、十字线又停在旁边那根，看不出卡上的数是哪根的 */
  let hoverT: number | null = null
  tagsOf.set(chart, () => tags)
  let tagData = new Map<number, BarBig>()
  const bigCache = new BigBarCache()
  const tierCache = new TierCache()
  let flowSym = ''
  const onHistory = (): void => { chart.dirty = true }
  // 图例是 DOM（左上角），尺寸变了 ResizeObserver 推过来，画签时不去读布局
  let legend: TagRect | null = null
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

  interface Vis { o: BigOrder; id: string; live: boolean; x0: number; x1: number; y0: number; h: number; mid: number; pk: number }
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

  /** 蜡烛下面：挂着的带铺底（0.14–0.20，最大的最深），结束的只画一道细线；不描边 */
  function drawBands(c: CanvasRenderingContext2D, g: ChartGeometry, k: number, step: number): void {
    bands = []
    plan = null
    const snap = OF.snap
    if (!snap || !st.orderFlow) return
    const rs = step * k
    const tFrom = g.timeOf(g.from - 1), tTo = g.timeOf(g.to + 2)
    const top = g.pane.y, bottom = g.pane.y + g.pane.h
    const cands: Vis[] = []
    for (const o of snap.orders) {
      if (!shows(OF.prefs.display, o)) continue
      const end = o.endMs
      if (end != null && end < tFrom) continue
      if (o.firstSeenMs > tTo) continue
      const r = rowOf(o.bucket, k)
      const yT = g.priceToY((r + 1) * rs), yB = g.priceToY(r * rs)
      const mid = (yT + yB) / 2
      if (mid > bottom || mid < top) continue
      const h = Math.max(3, Math.min(24, yB - yT))
      const x0 = Math.max(-2, xOf(g, o.firstSeenMs))
      const x1 = end == null ? g.plotW : Math.min(g.plotW, xOf(g, end))
      if (x1 < 0 || x0 > g.plotW) continue
      const id = orderId(o)
      cands.push({ o, id, live: end == null, x0, x1: Math.max(x0 + 2, x1), y0: mid - h / 2, h, mid, pk: peak(o, id) })
    }
    const dark = isDarkBg(g.colors.bg)
    const pick = pickBands(cands, OF.highlight)
    plan = { ...pick, dark }
    // 结束的：1 px 细线（在蜡烛下面）
    for (const v of pick.ended) {
      const hl = OF.highlight === v.id
      c.fillStyle = bandColor(v.o.product, v.o.side, hl ? 0.9 : ENDED_LINE[dark ? 'dark' : 'light'], dark)
      c.fillRect(v.x0, Math.round(v.mid) - (hl ? 1 : 0), v.x1 - v.x0, hl ? 2 : 1)
      bands.push({ x0: v.x0, x1: v.x1, y0: v.mid - 4, y1: v.mid + 4, o: v.o, id: v.id })
    }
    // 挂着的：小的先画、大的后画
    const n = pick.live.length
    for (let rank = n - 1; rank >= 0; rank--) {
      const v = pick.live[rank]
      const hl = OF.highlight === v.id
      c.fillStyle = bandColor(v.o.product, v.o.side, hl ? HIGHLIGHT_ALPHA : liveAlpha(rank, n, dark), dark)
      c.fillRect(v.x0, v.y0, v.x1 - v.x0, v.h)
      if (hl) { c.strokeStyle = g.colors.accent; c.lineWidth = 1; c.strokeRect(v.x0 + .5, v.y0 + .5, v.x1 - v.x0 - 1, v.h - 1) }
      bands.push({ x0: v.x0, x1: v.x1, y0: v.y0, y1: v.y0 + v.h, o: v.o, id: v.id })
    }
  }

  /** 蜡烛上面：结束记号（峰值前几道，躲开蜡烛）与右端标签（最多 8 个、互不重叠、不压价格轴、不压蜡烛） */
  function drawBandMarks(c: CanvasRenderingContext2D, g: ChartGeometry): void {
    const p = plan
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
      marked.add(v.id)
    }
    c.font = canvasFont(11, 600)
    c.textBaseline = 'middle'
    c.textAlign = 'left'
    const all = [...p.live, ...p.ended]
    const texts = all.map(v => `${amt(v.pk)} ${venueName(exName(v.o.exchange), v.o.product)}`)
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
      c.fillStyle = hexA(g.colors.bg, p.dark ? 0.55 : 0.6)
      rrect(c, r.x, r.y, r.w, r.h, 3); c.fill()
      c.fillStyle = bandColor(v.o.product, v.o.side, p.dark ? 0.24 : 0.16, p.dark)
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

  function drawTags(c: CanvasRenderingContext2D, g: ChartGeometry): void {
    tags = []
    if (!st.orderFlow) return
    const sym = cellOf().symbol.toUpperCase()
    if (!sym || sym === 'DXY') return
    const f = flowOf(sym)
    if (sym !== flowSym) { if (flowSym) flowOf(flowSym).listeners.delete(onHistory); flowSym = sym }
    const now = Date.now()
    if (!(g.iv < 60_000)) ensureHistory(f, onHistory, now)
    bigCache.begin(f, `${sym}|${g.iv}`, now)
    const tiers = tierCache.get(bigCache, f, chart, now, unitFor(f, mine() ? OF.bigTrade : 0))
    if (!tiers) return
    const list: TagIn[] = []
    tagData = new Map()
    const lo = Math.max(0, Math.floor(g.from) - 1), hi = Math.ceil(g.to) + 1
    for (let i = lo; i <= hi; i++) {
      const t0 = g.timeOf(i)
      if (t0 > now) break
      const d = bigCache.get(f, t0, g.timeOf(i + 1), now)
      if (!d || Math.max(d.bb, d.bs) < tiers.t1) continue
      const x = g.indexToX(i)
      if (x < -40 || x > g.plotW + 40) continue
      list.push({ i, t: t0, x, data: d }); tagData.set(t0, d)
    }
    if (!list.length) return
    const avoid: TagRect[] = chart.textRects.slice()
    if (legend) avoid.push(legend)
    const fontS = canvasFont(11, 600), fontB = canvasFont(13, 700)
    const yHi = (b: { h: number }) => g.priceToY(b.h), yLo = (b: { l: number }) => g.priceToY(b.l)
    const volOn = chart.ind.vol && chart.deg.vol && !chart.hidden.has('vol')
    tags = planTags(list, {
      tiers, spacing: g.spacing, top: g.pane.y + 2, bottom: g.pane.y + g.pane.h * (volOn ? 1 - VOL_H : 1) - 2, plotW: g.plotW - 2, avoid,
      span: (x0, x1) => {
        const i0 = Math.max(0, Math.round(g.xToIndex(x0))), i1 = Math.round(g.xToIndex(x1))
        let hiY = Infinity, loY = -Infinity
        for (let i = i0; i <= i1; i++) { const b = g.bar(i); if (!b) continue; hiY = Math.min(hiY, yHi(b)); loY = Math.max(loY, yLo(b)) }
        return isFinite(hiY) ? { hiY, loY } : null
      },
      measure: (t, big) => { c.font = big ? fontB : fontS; return c.measureText(t).width },
      text: amt,
    })
    const hiOn = OF.barHi && OF.barHi.symbol === sym && OF.barHi.until > now ? OF.barHi.t : null
    c.textAlign = 'center'; c.textBaseline = 'middle'; c.lineWidth = 1
    for (const t of tags) {
      const col = t.side === 'buy' ? g.colors.up : g.colors.down
      if (hiOn === t.t) { c.fillStyle = hexA(col, 0.22); rrect(c, t.x - 4, t.y - 4, t.w + 8, t.h + 8, 6); c.fill() }
      if (t.kind === 'tri') {
        const up = t.side === 'buy'
        c.beginPath()
        if (up) { c.moveTo(t.cx, t.y); c.lineTo(t.x + t.w, t.y + t.h); c.lineTo(t.x, t.y + t.h) }
        else { c.moveTo(t.cx, t.y + t.h); c.lineTo(t.x + t.w, t.y); c.lineTo(t.x, t.y) }
        c.closePath()
        if (t.filled) { c.fillStyle = col; c.fill() } else { c.strokeStyle = col; c.stroke() }
        continue
      }
      const big = t.kind === 'big'
      rrect(c, t.x + .5, t.y + .5, t.w - 1, t.h - 1, big ? 4 : 3)
      if (t.filled) { c.fillStyle = col; c.fill() } else { c.fillStyle = hexA(g.colors.bg, 0.85); c.fill(); c.strokeStyle = col; c.stroke() }
      c.font = big ? fontB : fontS
      c.fillStyle = t.filled ? '#fff' : col
      c.fillText(t.text, t.cx, t.y + t.h / 2 + .5)
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

  function bandCard(b: BandHit, dec: number, step: number): string {
    const o = b.o
    const d = decFor(step, dec)
    const lo = o.bucket * step, hi = lo + step
    const now = Date.now()
    const pk = peak(o, b.id)
    const rows: [string, string][] = [
      ['价位', `${px(lo, d)} – ${px(hi, d)}`],
      ['首见', mdhm(o.firstSeenMs)],
      ['结束', o.endMs == null ? `挂着 · 已 ${durShort(now - o.firstSeenMs)}` : `${mdhm(o.endMs)} · 挂了 ${durShort(o.endMs - o.firstSeenMs)}`],
      ['峰值', amt(pk)],
      ['剩余', o.status === 'live' ? amt(o.notional) : '—'],
      ['累计成交', o.filledNotional > 0 ? amt(o.filledNotional) : '—'],
      ['结局', outcomeText(o)],
    ]
    const ex = exName(o.exchange)
    return `<div class="of-card-h"><i style="background:${bandColor(o.product, o.side, 1)}"></i>${esc(ex)} · ${PRODUCT_FULL[o.product]} · <b class="${o.side === 'bid' ? 'up' : 'down'}">${o.side === 'bid' ? '买单' : '卖单'}</b></div>` +
      rows.map(([k, v]) => `<div class="of-card-r"><span>${k}</span><b class="num">${v}</b></div>`).join('')
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
    const parts = [col.parts[i * 3], col.parts[i * 3 + 1], col.parts[i * 3 + 2]]
    const split = col.split
      ? EXCHANGE_NAMES.map((n, q) => `<div class="of-card-r"><span>${n}</span><b class="num">${parts[q] > 0 ? amt(parts[q]) : '—'}</b></div>`).join('')
      : `<div class="of-card-r"><span>三家合计</span><b class="num faint">历史回填不分交易所</b></div>`
    const t = col.t1 - col.t0 <= 60_000 ? `${mdhm(col.t0).slice(0, 5)} ${hms(col.t0)}` : `${mdhm(col.t0)} – ${hms(col.t1).slice(0, 5)}`
    return `<div class="of-card-h"><i style="background:${g.colors.accent}"></i>深度热力 · ${t}</div>
      <div class="of-card-r"><span>价位</span><b class="num">${px(r * rs, d)} – ${px((r + 1) * rs, d)}</b></div>
      <div class="of-card-r"><span>挂单名义</span><b class="num">${amt(col.vals[i])}</b></div>${split}`
  }

  // 悬停卡与抽屉「每根」同一套样子（drawerView.hoverCardHtml）
  function tagCard(t: Tag): string {
    const d = tagData.get(t.t)
    return d ? hoverCardHtml(d, mdhm(d.t), ivShort(d.t1 - d.t)) : ''
  }

  /** 一根上的强调色竖带（画在蜡烛下面）：抽屉里点选的那根带底边粗线；鼠标停在签上的那根只有淡带 */
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
    if (hoverT != null && hoverT !== s?.t) drawBar(c, g, hoverT, false)
  }

  /** 签悬停换了根（或离开）就重画一帧 */
  function setHover(t: number | null): void {
    if (hoverT === t) return
    hoverT = t; chart.dirty = true
  }

  const tagAt = (x: number, y: number): Tag | null => {
    for (const t of tags) if (x >= t.x - 2 && x <= t.x + t.w + 2 && y >= t.y - 2 && y <= t.y + t.h + 2) return t
    return null
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
      drawTags(c, g)
      if (mine()) drawHoverRow(c, g)
    },
    after(g) {
      if (mine()) OF.onChartDrawn?.(chart, g)
      drawerChartDrawn(chart)
    },
    hover(x, y, cx, cy) {
      if (!geo) return false
      const tg = tagAt(x, y)
      setHover(tg?.t ?? null)
      if (tg) { showCard(tagCard(tg), cx, cy); return true }
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
      const tg = tagAt(x, y)
      if (tg) {
        const sym = cellOf().symbol.toUpperCase()
        OF.barHi = { symbol: sym, t: tg.t, until: Date.now() + 1500 }
        OF.selBar = { symbol: sym, iv: chart.iv, t: tg.t }
        chart.dirty = true
        OF.revealBar?.(sym, tg.t)
        return true
      }
      if (!mine()) return false
      for (let i = bands.length - 1; i >= 0; i--) {
        const b = bands[i]
        if (x >= b.x0 && x <= b.x1 + 4 && y >= b.y0 - 1 && y <= b.y1 + 1) { OF.highlight = b.id; chart.dirty = true; OF.reveal?.(b.id); return true }
      }
      return false
    },
  }
}
