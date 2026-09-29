/* Hkline Web · 主力订单流 · 画在 K 线图上的三层（设计稿 2.3 / 2.4 / 2.5）
 *
 * 蜡烛下面：深度热力（开了才画）→ 大单带（首见 → 结束，挂着的拉到右边）。
 * 蜡烛上面：大额成交的点、梯子悬停那一行的淡色横带。
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
import { HeatCache, percentile, type HeatCol } from './heat'
import { OF, rowsPerLine, bandColor, rgbOf, showCard, hideCard, amt, hms, mdhm, durShort, PRODUCT_FULL, decFor, px, peak, canvasFont } from './state'
import { esc } from '../ui/dom'
import { hexA } from '../util/format'

interface BandHit { x0: number; x1: number; y0: number; y1: number; o: BigOrder; id: string }
interface DotHit { x: number; y: number; r: number; i: number }
interface HeatDraw { cols: HeatCol[]; xs: number[]; ws: number[]; rowLo: number; rowHi: number; k: number; step: number; top: number; bottom: number }

const xOf = (g: ChartGeometry, t: number): number => g.timeToX(t) - g.spacing / 2

export function createLayer(chart: TVChart, cellOf: () => { symbol: string; iv: string }): ChartLayer {
  let bands: BandHit[] = []
  let dots: DotHit[] = []
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
    for (let ci = 0; ci < W; ci++) {
      const col = cols[ci]
      for (let i = 0; i < col.n; i++) {
        const r = col.lo + i
        if (r < rowLo || r > rowHi) continue
        const v = col.vals[i]
        if (!(v > 0)) continue
        const a = Math.pow(Math.min(1, v / p95), 0.8) * 0.78
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

  function drawBands(c: CanvasRenderingContext2D, g: ChartGeometry, k: number, step: number): void {
    bands = []
    const snap = OF.snap
    if (!snap || !st.orderFlow) return
    const rs = step * k
    const tFrom = g.timeOf(g.from - 1), tTo = g.timeOf(g.to + 2)
    const top = g.pane.y, bottom = g.pane.y + g.pane.h
    // 先挑出画面里的带，再按峰值定浓淡：最大的几道 0.35，小的淡到 0.06（短命的撤单不画末端记号）——几百道叠在一起时 K 线仍读得出来
    const vis: { o: BigOrder; id: string; x0: number; w: number; y0: number; h: number; mid: number; pk: number }[] = []
    let maxPk = 0
    for (const o of snap.orders) {
      if (!shows(OF.prefs.display, o)) continue
      const end = o.endMs
      if (end != null && end < tFrom) continue
      if (o.firstSeenMs > tTo) continue
      const r = rowOf(o.bucket, k)
      const yT = g.priceToY((r + 1) * rs), yB = g.priceToY(r * rs)
      const mid = (yT + yB) / 2
      const h = Math.max(3, Math.min(24, yB - yT))
      const y0 = mid - h / 2
      if (y0 > bottom || y0 + h < top) continue
      const x0 = Math.max(-2, xOf(g, o.firstSeenMs))
      const x1 = end == null ? g.plotW : Math.min(g.plotW, xOf(g, end))
      if (x1 < 0 || x0 > g.plotW) continue
      const id = orderId(o)
      const pk = peak(o, id)
      if (pk > maxPk) maxPk = pk
      vis.push({ o, id, x0, w: Math.max(2, x1 - x0), y0, h, mid, pk })
    }
    vis.sort((a, b) => a.pk - b.pk)
    c.font = canvasFont(11, 500)
    c.textBaseline = 'middle'
    const labels: [string, number, number, string, number][] = []
    for (const { o, id, x0, w, y0, h, mid, pk } of vis) {
      const hl = OF.highlight === id
      const rel = Math.sqrt(pk / (maxPk || 1))
      const a = hl ? 0.6 : 0.06 + 0.29 * rel
      c.fillStyle = bandColor(o.product, o.side, a)
      c.fillRect(x0, y0, w, h)
      // 左端一道实色，读得出「从这里开始」
      c.fillStyle = bandColor(o.product, o.side, Math.min(0.9, a * 2.4))
      c.fillRect(x0, y0, Math.min(2, w), h)
      if (hl) { c.strokeStyle = g.colors.accent; c.lineWidth = 1.5; c.strokeRect(x0 + .5, y0 + .5, w - 1, h - 1) }
      // 撤掉的单最多，□ 只给够宽又够大的；成交（▲）更有信息量，门槛放低
      if (o.endMs != null && (hl || (o.status === 'filled' || o.filledNotional > 0 ? w >= 16 || rel >= 0.5 : w >= 40 && rel >= 0.35))) endMark(c, o, x0 + w, mid, Math.min(10, Math.max(6, h)))
      bands.push({ x0, x1: x0 + w, y0, y1: y0 + h, o, id })
      // 右端的小标签：峰值名义 + 交易所（带宽 ≥ 80 px 才标，否则靠悬停）
      if (w >= 80) labels.push([`${amt(pk)} ${venueName(exName(o.exchange), o.product)}`, x0 + w - (o.endMs != null ? 12 : 6), h >= 13 ? mid : y0 - 7, bandColor(o.product, o.side, 1), pk])
    }
    // 标签最后画，免得被带盖住；大的优先，互相压着的只留先到的，最多 12 个
    c.textAlign = 'left'
    labels.sort((a, b) => b[4] - a[4])
    const placed: [number, number, number, number][] = []
    for (const [t, xr, y, col] of labels) {
      if (placed.length >= 12) break
      if (y < top + 6 || y > bottom - 6) continue
      const w = c.measureText(t).width
      const x = Math.max(4, Math.min(xr, g.plotW - 4) - w)
      if (placed.some(([a, b, cc, d]) => x - 3 < cc && x + w + 3 > a && y - 7 < d && y + 7 > b)) continue
      placed.push([x - 3, y - 7, x + w + 3, y + 7])
      c.fillStyle = hexA(g.colors.bg, 0.78)
      c.fillRect(x - 3, y - 7, w + 6, 14)
      c.fillStyle = col
      c.fillText(t, x, y)
    }
  }

  function endMark(c: CanvasRenderingContext2D, o: BigOrder, x: number, y: number, s: number): void {
    const col = bandColor(o.product, o.side, 1)
    c.fillStyle = col; c.strokeStyle = col; c.lineWidth = 1.5
    if (o.status === 'filled') {
      c.beginPath(); c.moveTo(x, y - s / 2); c.lineTo(x + s / 2, y + s / 2); c.lineTo(x - s / 2, y + s / 2); c.closePath(); c.fill()
    } else if (o.status === 'cancelled') {
      const h = s - 2
      c.strokeRect(x - h / 2 + .5, y - h / 2 + .5, h - 1, h - 1)
      if (o.filledNotional > 0) c.fillRect(x - h / 2 + .5, y, h - 1, h / 2 - .5)
    }
  }

  function drawDots(c: CanvasRenderingContext2D, g: ChartGeometry): void {
    dots = []
    if (!st.orderFlow) return
    const list = OF.tape.dots
    if (!list.length) return
    const tFrom = g.timeOf(g.from - 1)
    const top = g.pane.y, bottom = g.pane.y + g.pane.h
    const big = OF.bigTrade || 1
    for (let i = list.length - 1; i >= 0; i--) {
      const d = list[i]
      if (d.t < tFrom) break
      const x = xOf(g, d.t), y = g.priceToY(d.price)
      if (x < 0 || x > g.plotW || y < top || y > bottom) continue
      const r = Math.max(3, Math.min(9, 3 * Math.sqrt(d.usd / big)))
      c.beginPath(); c.arc(x, y, r, 0, Math.PI * 2)
      c.fillStyle = hexA(d.side === 'buy' ? g.colors.up : g.colors.down, 0.85); c.fill()
      c.lineWidth = 1; c.strokeStyle = hexA(g.colors.bg, 0.9); c.stroke()
      dots.push({ x, y, r, i })
    }
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

  function dotCard(d: DotHit, dec: number): string {
    const t = OF.tape.dots[d.i]
    if (!t) return ''
    return `<div class="of-card-h"><i style="background:${t.side === 'buy' ? 'var(--up)' : 'var(--down)'}"></i>大额成交 · ${esc(t.label)}${PRODUCT_FULL[t.product]}</div>
      <div class="of-card-r"><span>时间</span><b class="num">${hms(t.t)}</b></div>
      <div class="of-card-r"><span>方向</span><b class="${t.side === 'buy' ? 'up' : 'down'}">${t.side === 'buy' ? '主动买' : '主动卖'}</b></div>
      <div class="of-card-r"><span>价格</span><b class="num">${px(t.price, dec)}</b></div>
      <div class="of-card-r"><span>金额</span><b class="num">${amt(t.usd)}</b></div>`
  }

  return {
    under(c, g) {
      geo = g
      if (!mine()) { bands = []; heat = null; return }
      const step = OF.feed?.model.scheme?.step
      if (!step) { bands = []; heat = null; return }
      const k = rowsPerLine(g, step, cellOf().iv)
      if (OF.prefs.heat) drawHeat(c, g, k, step); else heat = null
      drawBands(c, g, k, step)
    },
    over(c, g) {
      if (!mine()) { dots = []; return }
      drawDots(c, g)
      drawHoverRow(c, g)
    },
    after(g) { if (mine()) OF.onChartDrawn?.(chart, g) },
    hover(x, y, cx, cy) {
      if (!mine() || !geo) return false
      const dec = geo.dec
      for (const d of dots) if ((x - d.x) ** 2 + (y - d.y) ** 2 <= (d.r + 2) ** 2) { showCard(dotCard(d, dec), cx, cy); return true }
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
    leave() { hideCard() },
    click(x, y) {
      if (!mine()) return false
      for (let i = bands.length - 1; i >= 0; i--) {
        const b = bands[i]
        if (x >= b.x0 && x <= b.x1 + 4 && y >= b.y0 - 1 && y <= b.y1 + 1) { OF.highlight = b.id; chart.dirty = true; OF.reveal?.(b.id); return true }
      }
      return false
    },
  }
}
