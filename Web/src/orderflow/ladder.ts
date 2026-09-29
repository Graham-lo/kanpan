/* Hkline Web · 主力订单流 · 深度梯子（设计稿 2.2）
 *
 * 价格轴与侧栏之间 240 px 的一列，和活动格子的主图共用一根价格轴：每次主图画完一帧就跟着重画，
 * 所以缩放、拖动时一行一行和 K 线对齐。一行 = 步长 × 周期倍数，行高不到 6 px 就 2 / 5 / 10 倍地并。
 * 中线往左是买（涨色）、往右是卖（跌色）；淡色是累计、实色是这一行本身；有大单的行加饱和色、
 * 左边 3 px 竖条和一颗胶囊，几家同在一行时胶囊后面跟几个小点（悬停卡片里全列出来）。
 * 滚轮缩放价格轴（图也跟着缩）；点一行 = 在这一行建提醒；把一行拖到图上 = 画一条水平线。
 */
import type { ChartGeometry, TVChart } from '../chart/chart'
import { st, save } from '../app/store'
import { I } from '../ui/dom'
import { hexA } from '../util/format'
import { bucketIndex } from './bucket'
import { ladderRows, rowOf, type LadderRow, venueName, exName } from './aggregate'
import { OF, rowsPerLine, bandColor, showCard, hideCard, amt, durShort, decFor, px, canvasFont } from './state'

/** 宽度跟着槽位走（用户可拖，160–480），每帧按槽位宽重算 */
let W = 240
let HALF = W / 2
const PAD = 6

interface Hit { y0: number; y1: number; row: LadderRow }

let slot: HTMLElement | null = null
let cv: HTMLCanvasElement | null = null
let foot: HTMLElement | null = null
let hits: Hit[] = []
let off = 0
let lastGeo: { chart: TVChart; g: ChartGeometry } | null = null
let cache: { key: string; rows: Map<number, LadderRow> } | null = null
let drag: { row: LadderRow; x: number; y: number; moved: boolean; ghost: HTMLElement | null } | null = null

export function mountLadder(el: HTMLElement): void {
  slot = el
  el.innerHTML = `<canvas class="of-lad-cv" aria-label="深度梯子：点一行建提醒，拖到图上画水平线"></canvas>
    <div class="of-lad-foot"><b>深度梯子</b><span class="faint num" id="ofLadInfo"></span>
      <button class="ibtn xs" id="ofLadClose" aria-label="收起深度梯子" data-tip="收起">${I('close', 'icon-16')}</button></div>
    <div class="of-lad-empty faint" id="ofLadEmpty" hidden></div>`
  cv = el.querySelector('canvas')
  foot = el.querySelector('.of-lad-foot')
  el.querySelector<HTMLElement>('#ofLadClose')!.onclick = () => { st.slots.ladder = false; save(); OF.api?.layoutSlots() }
  cv!.addEventListener('wheel', onWheel, { passive: false })
  cv!.addEventListener('pointerdown', onDown)
  cv!.addEventListener('pointermove', onMove)
  cv!.addEventListener('pointerleave', () => { if (!drag) leaveRow() })
  window.addEventListener('pointerup', onUp)
  lastGeo = null
}

export function ladderVisible(): boolean { return !!slot && st.slots.ladder && !slot.hidden && slot.isConnected }

/** 活动格子的主图画完一帧：按它的价格轴重画梯子。 */
export function drawLadder(chart: TVChart, g: ChartGeometry): void {
  lastGeo = { chart, g }
  if (!ladderVisible() || !cv || !slot) return
  const sr = slot.getBoundingClientRect(), cr = chart.canvas.getBoundingClientRect()
  const H = Math.max(0, Math.round(sr.height))
  W = Math.max(120, Math.round(sr.width)); HALF = W / 2
  const dpr = window.devicePixelRatio || 1
  if (cv.width !== Math.round(W * dpr) || cv.height !== Math.round(H * dpr)) {
    cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr)
    cv.style.width = W + 'px'; cv.style.height = H + 'px'
  }
  off = cr.top - sr.top
  const c = cv.getContext('2d')!
  c.setTransform(dpr, 0, 0, dpr, 0, 0)
  c.clearRect(0, 0, W, H)
  hits = []
  const empty = slot.querySelector<HTMLElement>('#ofLadEmpty')!
  const info = slot.querySelector<HTMLElement>('#ofLadInfo')!
  const paneTop = g.pane.y + off, paneBot = g.pane.y + g.pane.h + off
  if (foot) foot.style.top = `${Math.min(H - 36, paneBot + 4)}px`
  const fine = OF.fine, feed = OF.feed
  const step = feed?.model.scheme?.step
  if (!feed || !fine || !step || fine.step !== step || !fine.ready) {
    empty.hidden = false
    empty.style.top = `${(paneTop + paneBot) / 2 - 12}px`
    empty.textContent = !feed ? '' : feed.isCalibrating ? '正在按盘口深度定门槛…' : !step ? '正在取步长…' : '正在连三家交易所的盘口…'
    info.textContent = ''
    return
  }
  empty.hidden = true
  const k = rowsPerLine(g, step, OF.iv)
  const rs = step * k
  const rowLo = rowOf(bucketIndex(g.range.min, step), k), rowHi = rowOf(bucketIndex(g.range.max, step), k)
  if (rowHi - rowLo > 4000) return
  const key = `${fine.asOfMs}|${k}|${rowLo}|${rowHi}|${OF.version}`
  if (!cache || cache.key !== key) cache = { key, rows: ladderRows(fine, k, rowLo, rowHi, OF.snap?.orders ?? []) }
  const rows = cache.rows
  info.textContent = `每行 ${px(rs, decFor(rs, 0))} · ${fine.ready}/${fine.venues.length} 本`
  const C = g.colors
  let maxOne = 0, maxCum = 0
  for (const r of rows.values()) {
    maxOne = Math.max(maxOne, r.bid, r.ask)
    maxCum = Math.max(maxCum, r.cumBid, r.cumAsk)
  }
  maxOne ||= 1; maxCum ||= 1
  c.save()
  c.beginPath(); c.rect(0, paneTop, W, paneBot - paneTop); c.clip()
  // 最新成交所在的行：淡底
  if (g.last != null) {
    const r = rowOf(bucketIndex(g.last, step), k)
    const yT = g.priceToY((r + 1) * rs) + off, yB = g.priceToY(r * rs) + off
    c.fillStyle = hexA(C.text, 0.06); c.fillRect(0, yT, W, yB - yT)
  }
  c.font = canvasFont(11)
  c.textBaseline = 'middle'
  const now = Date.now()
  for (let r = rowLo; r <= rowHi; r++) {
    const x = rows.get(r)
    const yT = g.priceToY((r + 1) * rs) + off, yB = g.priceToY(r * rs) + off
    const h = yB - yT
    if (h <= 0 || yB < paneTop || yT > paneBot) continue
    const gap = h >= 8 ? 1 : 0
    const y0 = yT + gap / 2, hh = h - gap
    if (!x) continue
    hits.push({ y0: yT, y1: yB, row: x })
    const big = x.orders.length > 0
    // 累计（淡）
    if (x.cumBid > 0) { const w = HALF * x.cumBid / maxCum; c.fillStyle = hexA(C.up, 0.25); c.fillRect(HALF - w, y0, w, hh) }
    if (x.cumAsk > 0) { const w = HALF * x.cumAsk / maxCum; c.fillStyle = hexA(C.down, 0.25); c.fillRect(HALF, y0, w, hh) }
    // 这一行本身（实）
    if (x.bid > 0) { const w = Math.max(1, HALF * x.bid / maxOne); c.fillStyle = hexA(C.up, big && x.orders.some(o => o.side === 'bid') ? 0.95 : 0.6); c.fillRect(HALF - w, y0, w, hh) }
    if (x.ask > 0) { const w = Math.max(1, HALF * x.ask / maxOne); c.fillStyle = hexA(C.down, big && x.orders.some(o => o.side === 'ask') ? 0.95 : 0.6); c.fillRect(HALF, y0, w, hh) }
    // 金额（右对齐），行高够才写
    if (h >= 12) {
      c.textAlign = 'right'
      if (x.bid > 0) { c.fillStyle = C.text; c.fillText(amt(x.bid), HALF - PAD, (yT + yB) / 2) }
      if (x.ask > 0) { c.fillStyle = C.text; c.fillText(amt(x.ask), W - PAD, (yT + yB) / 2) }
    }
    if (big) {
      const o = x.orders[0]
      c.fillStyle = bandColor(o.product, o.side, 1)
      c.fillRect(0, yT, 3, h)
      if (h >= 10) pill(c, x, (yT + yB) / 2, now, o.side === 'bid')
    }
  }
  // 中间价与价差
  if (fine.mid != null) {
    const y = Math.round(g.priceToY(fine.mid) + off) + .5
    c.strokeStyle = hexA(C.text, 0.55); c.lineWidth = 1
    c.beginPath(); c.moveTo(0, y); c.lineTo(W, y); c.stroke()
    const bps = fine.bestBid != null && fine.bestAsk != null && fine.mid > 0 ? (fine.bestAsk - fine.bestBid) / fine.mid * 1e4 : null
    const t = `${px(fine.mid, Math.max(g.dec, decFor(step, 0)))}${bps != null ? ` · 价差 ${bps < 10 ? bps.toFixed(2) : bps.toFixed(1)} bps` : ''}`
    c.font = canvasFont(11, 500)
    const tw = c.measureText(t).width
    c.fillStyle = C.bg; c.fillRect(HALF - tw / 2 - 6, y - 8, tw + 12, 16)
    c.strokeStyle = hexA(C.text, 0.3); c.strokeRect(HALF - tw / 2 - 5.5, y - 7.5, tw + 11, 15)
    c.fillStyle = C.text; c.textAlign = 'center'; c.fillText(t, HALF, y)
  }
  c.restore()
}

/** 大单胶囊：画在这一行空着的那半边（买单行在右半、卖单行在左半）。 */
function pill(c: CanvasRenderingContext2D, x: LadderRow, y: number, now: number, bidRow: boolean): void {
  const o = x.orders[0]
  c.font = canvasFont(11, 600)
  // 胶囊只有半行宽：放不下「交易所产品 金额」就只留金额，存活时长与其余细节在悬停卡片里
  const full = `${venueName(exName(o.exchange), o.product)} ${amt(o.notional)}`
  const t = c.measureText(full).width + 12 + (x.orders.length > 1 ? 23 : 0) <= HALF - 8 ? full : amt(o.notional)
  void now
  // 同一行还有别家 / 别的产品的大单：胶囊后面跟几个小点（最多三个），悬停卡片里全列
  const seen = new Set([o.venueID + o.side])
  const others: typeof x.orders = []
  for (const q of x.orders) if (!seen.has(q.venueID + q.side)) { seen.add(q.venueID + q.side); others.push(q) }
  const dots = others.slice(0, 3)
  const dw = dots.length ? dots.length * 7 + 2 : 0
  const w = Math.min(HALF - 8, c.measureText(t).width + 12 + dw), h = 16
  const x0 = bidRow ? HALF + 4 : HALF - 4 - w
  c.fillStyle = bandColor(o.product, o.side, 1)
  roundRect(c, x0, y - h / 2, w, h, 8); c.fill()
  c.fillStyle = '#fff'; c.textAlign = 'left'
  c.save(); c.beginPath(); c.rect(x0 + 6, y - h / 2, w - 12 - dw, h); c.clip()
  c.fillText(t, x0 + 6, y); c.restore()
  dots.forEach((q, i) => {
    const cx = x0 + w - 8 - i * 7
    c.beginPath(); c.arc(cx, y, 3, 0, Math.PI * 2); c.fillStyle = '#fff'; c.fill()
    c.beginPath(); c.arc(cx, y, 2, 0, Math.PI * 2); c.fillStyle = bandColor(q.product, q.side, 1); c.fill()
  })
}

function roundRect(c: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
  c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath()
}

// ------------------------------------------------------------------ 交互

function rowAt(y: number): Hit | null {
  for (const h of hits) if (y >= h.y0 && y < h.y1) return h
  return null
}
function local(e: PointerEvent | WheelEvent): { x: number; y: number } {
  const r = cv!.getBoundingClientRect()
  return { x: e.clientX - r.left, y: e.clientY - r.top }
}

function onWheel(e: WheelEvent): void {
  if (!lastGeo) return
  e.preventDefault()
  const { y } = local(e)
  lastGeo.chart.zoomPrice(Math.exp(e.deltaY * 0.002), y - off)
}

function leaveRow(): void {
  hideCard()
  if (OF.hoverRow) { OF.hoverRow = null; if (lastGeo) lastGeo.chart.dirty = true }
}

function onMove(e: PointerEvent): void {
  const { x, y } = local(e)
  if (drag) {
    if (!drag.moved && Math.hypot(x - drag.x, y - drag.y) > 4) {
      drag.moved = true
      hideCard()
      drag.ghost = document.createElement('div')
      drag.ghost.className = 'of-drag-ghost num'
      drag.ghost.textContent = `水平线 ${priceText(center(drag.row))}`
      document.body.appendChild(drag.ghost)
    }
    if (drag.ghost) drag.ghost.style.transform = `translate(${e.clientX + 12}px,${e.clientY - 12}px)`
    return
  }
  const h = rowAt(y)
  if (!h) { leaveRow(); return }
  const r = h.row
  if (!OF.hoverRow || OF.hoverRow.low !== r.low) { OF.hoverRow = { low: r.low, high: r.high }; if (lastGeo) lastGeo.chart.dirty = true }
  showCard(rowCard(r), e.clientX, e.clientY)
  cv!.style.cursor = 'pointer'
  void x
}

function onDown(e: PointerEvent): void {
  if (e.button !== 0) return
  const { x, y } = local(e)
  const h = rowAt(y)
  if (!h) return
  drag = { row: h.row, x, y, moved: false, ghost: null }
  cv!.setPointerCapture?.(e.pointerId)
}

function onUp(e: PointerEvent): void {
  if (!drag) return
  const d = drag; drag = null
  d.ghost?.remove()
  const p = center(d.row)
  if (!d.moved) { hideCard(); OF.api?.openAlert(p); return }
  // 落点在活动图的画布范围里就算（画布上面还叠着十字线层等，不能靠 elementFromPoint 认）
  const act = OF.api?.activeChart()
  const r = act?.chart.canvas.getBoundingClientRect()
  if (r && e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom) OF.api?.addHline(p)
}

const center = (r: LadderRow): number => (r.low + r.high) / 2
function priceText(p: number): string {
  const g = lastGeo?.g
  const step = OF.feed?.model.scheme?.step ?? 0
  return px(p, decFor(step, g?.dec ?? 2))
}

function rowCard(r: LadderRow): string {
  const g = lastGeo?.g
  const fine = OF.fine
  const d = decFor(r.high - r.low, g?.dec ?? 2)
  const lines: string[] = []
  if (fine) {
    // 同一家同一类产品的几本簿（比如币安的几个交割月份）并成一行
    const by = new Map<string, [string, number, 'bid' | 'ask']>()
    const add = (n: string, v: number, s: 'bid' | 'ask') => { const e = by.get(n + s); if (e) e[1] += v; else by.set(n + s, [n, v, s]) }
    fine.venues.forEach((v, i) => {
      if (r.bidBy[i] > 0) add(venueName(v.label, v.product), r.bidBy[i], 'bid')
      if (r.askBy[i] > 0) add(venueName(v.label, v.product), r.askBy[i], 'ask')
    })
    const items = [...by.values()]
    items.sort((a, b) => b[1] - a[1])
    for (const [n, v, s] of items.slice(0, 12)) lines.push(`<div class="of-card-r"><span>${n}<em class="${s === 'bid' ? 'up' : 'down'}">${s === 'bid' ? '买' : '卖'}</em></span><b class="num">${amt(v)}</b></div>`)
    if (items.length > 12) lines.push(`<div class="of-card-r faint"><span>另有 ${items.length - 12} 处</span></div>`)
  }
  const orders = r.orders.map(o => `<div class="of-card-r"><span><i class="sw" style="background:${bandColor(o.product, o.side, 1)}"></i>${venueName(exName(o.exchange), o.product)} 大单</span><b class="num">${amt(o.notional)} · ${durShort(Date.now() - o.firstSeenMs)}</b></div>`).join('')
  return `<div class="of-card-h">${px(r.low, d)} – ${px(r.high, d)}</div>
    <div class="of-card-r"><span>买 · 累计</span><b class="num up">${amt(r.bid)} · ${amt(r.cumBid)}</b></div>
    <div class="of-card-r"><span>卖 · 累计</span><b class="num down">${amt(r.ask)} · ${amt(r.cumAsk)}</b></div>
    ${orders}${lines.length ? `<div class="of-card-sep"></div>${lines.join('')}` : ''}
    <div class="of-card-foot">点一下建提醒 · 拖到图上画水平线</div>`
}

/** 数据变了但图没动：用上次的坐标重画。 */
export function redrawLadder(): void { if (lastGeo) drawLadder(lastGeo.chart, lastGeo.g) }
