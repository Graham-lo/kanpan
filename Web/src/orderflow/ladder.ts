/* Hkline Web · 主力订单流 · 深度梯子（设计稿 2.2；2026-09-29 吸收 OpenMarket 的 P1-3 / P1-5）
 *
 * 价格轴与侧栏之间 240 px 的一列（用户可拖 160–480），和活动格子的主图共用一根价格轴：每次主图画完一帧就跟着重画。
 *   · 行铺满整列高度（顶上 28 的模式条、底下 32 的脚注之间），不再只画主图那一段：
 *     一个细桶在图上 ≤ 32 px 时按图的价格轴对齐（行不到 14 px 就 2 / 5 / 10 倍地并），
 *     细桶比 32 px 还高（图放得很大、步长又粗）就不硬对齐——每行 20 px、中间价钉在图上中间价的高度，价格范围往外放宽。
 *   · 左右两半：中列往左是买（涨色）、往右是卖（跌色）；淡色是累计、实色是这一行本身；有大单的行左边 3 px 竖条 + 胶囊。
 *   · 中列 56 px：从打开这只品种起、这一行的主动买 − 主动卖净额（各家逐笔合流），两侧各一条 0.2 透明度的买 / 卖细条。
 *   · 右上「深度 / 变化」：变化 = 这一行现在的挂单 − 窗口开始时的挂单（买卖分开），窗口只有「1 小时 / 1 天」；
 *     点一行在卡片里画这一价位在窗口里的小折线。不做真假判定。
 * 滚轮缩放价格轴（图也跟着缩）；深度模式点一行 = 建提醒；拖到图上 = 画水平线；双击 = 图回到中间价。
 */
import type { ChartGeometry, TVChart } from '../chart/chart'
import { st, save } from '../app/store'
import { I, esc } from '../ui/dom'
import { hexA } from '../util/format'
import { bucketIndex, mergeFactor } from './bucket'
import { ladderRows, rowOf, type LadderRow, venueName, exName } from './aggregate'
import { OF, savePrefs, bandColor, showCard, hideCard, amt, hm, durShort, decFor, px, canvasFont } from './state'
import { deltaPct, fromMidPct, signedPct, type TradeRow } from './tradeLadder'
import { snapFine, deltaRows, rowSeries, sparkSVG, niceCeil, WIN_MS, type DeltaRow, type DeltaWin } from './depthDelta'
import type { SplitCol } from './heatFetch'

/** 宽度跟着槽位走（用户可拖，160–480），每帧按槽位宽重算 */
let W = 240
/** 中列宽；L = 买半边的右沿，R = 卖半边的左沿 */
const MID_W = 56
let L = (W - MID_W) / 2
let R = L + MID_W
const PAD = 6
/** 顶上模式条、底下脚注 */
const TOP = 28, FOOT = 32
/** 对齐模式里一行至少多高；细桶比 ALIGN_MAX 还高就改成定高行 */
const MIN_ROW = 14, ALIGN_MAX = 32, FIXED_ROW = 20
const WIN_TEXT: Record<DeltaWin, string> = { '1h': '1 小时', '1d': '1 天' }

interface Hit { y0: number; y1: number; row: LadderRow }

let slot: HTMLElement | null = null
let cv: HTMLCanvasElement | null = null
let foot: HTMLElement | null = null
let hits: Hit[] = []
let off = 0
let lastGeo: { chart: TVChart; g: ChartGeometry } | null = null
let cache: { key: string; rows: Map<number, LadderRow> } | null = null
let tradeCache: { key: string; rows: Map<number, TradeRow> } | null = null
let deltaCache: { key: string; rows: Map<number, DeltaRow> } | null = null
let nowCol: { at: number; col: SplitCol | null } | null = null
let drag: { row: LadderRow | null; x: number; y: number; moved: boolean; ghost: HTMLElement | null } | null = null
/** 这一帧的行（悬停卡片按行号取成交、变化） */
let frame: { k: number; rs: number; trades: Map<number, TradeRow>; delta: Map<number, DeltaRow> | null; start: number | null; startFrom: 'server' | 'live' | null; aligned: boolean; midY: number | null; centerY: number } | null = null
/** 变化模式点过的一行（卡片里画小折线） */
let pinned: number | null = null
let clickTimer = 0
let lastUpAt = 0

export function mountLadder(el: HTMLElement): void {
  slot = el
  OF.delta.onUpdate = () => { if (OF.prefs.ladderMode === 'delta') redrawLadder() }
  el.innerHTML = `<canvas class="of-lad-cv" aria-label="深度梯子：点一行建提醒，拖到图上画水平线，双击回到中间价"></canvas>
    <div class="of-lad-top">
      <div class="seg of-unit" id="ofLadWin" role="group" aria-label="变化窗口">${(['1h', '1d'] as DeltaWin[]).map(w => `<button data-lad-win="${w}">${WIN_TEXT[w]}</button>`).join('')}</div>
      <div class="seg of-unit" role="group" aria-label="梯子模式"><button data-lad-mode="depth">深度</button><button data-lad-mode="delta">变化</button></div>
    </div>
    <div class="of-lad-foot"><span class="faint num" id="ofLadInfo"></span>
      <button class="ibtn xs" id="ofLadClose" aria-label="收起深度梯子" data-tip="收起">${I('close', 'icon-16')}</button></div>
    <div class="of-lad-empty faint" id="ofLadEmpty" hidden></div>`
  cv = el.querySelector('canvas')
  foot = el.querySelector('.of-lad-foot')
  el.querySelector<HTMLElement>('#ofLadClose')!.onclick = () => { st.slots.ladder = false; save(); OF.api?.layoutSlots() }
  el.querySelector<HTMLElement>('.of-lad-top')!.onclick = onTopClick
  syncTop()
  cv!.addEventListener('wheel', onWheel, { passive: false })
  cv!.addEventListener('pointerdown', onDown)
  cv!.addEventListener('pointermove', onMove)
  cv!.addEventListener('pointerleave', () => { if (!drag) leaveRow() })
  window.addEventListener('pointerup', onUp)
  lastGeo = null
}

export function ladderVisible(): boolean { return !!slot && st.slots.ladder && !slot.hidden && slot.isConnected }

function syncTop(): void {
  if (!slot) return
  const m = OF.prefs.ladderMode, w = OF.prefs.deltaWin
  slot.querySelectorAll<HTMLElement>('[data-lad-mode]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.ladMode === m)))
  slot.querySelectorAll<HTMLElement>('[data-lad-win]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.ladWin === w)))
  const win = slot.querySelector<HTMLElement>('#ofLadWin')
  if (win) win.hidden = m !== 'delta'
}

function onTopClick(e: MouseEvent): void {
  const b = (e.target as HTMLElement).closest<HTMLElement>('button')
  if (!b) return
  if (b.dataset.ladMode) OF.prefs.ladderMode = b.dataset.ladMode === 'delta' ? 'delta' : 'depth'
  else if (b.dataset.ladWin) OF.prefs.deltaWin = b.dataset.ladWin === '1d' ? '1d' : '1h'
  else return
  savePrefs(); syncTop(); pinned = null; deltaCache = null
  hideCard(); redrawLadder()
}

/** 行的纵向映射：对齐（跟图的价格轴）或定高（每行 20 px、中间价钉住） */
interface Scale { k: number; rs: number; aligned: boolean; yOf: (p: number) => number; pOf: (y: number) => number }

function scaleFor(g: ChartGeometry, step: number, H: number, mid: number | null): Scale {
  const ref = mid ?? g.last ?? (g.range.min + g.range.max) / 2
  const h1 = Math.abs(g.priceToY(ref) - g.priceToY(ref + step))
  let k: number, aligned: boolean
  if (h1 <= ALIGN_MAX) { k = mergeFactor(h1, MIN_ROW); aligned = true }
  else {
    const n = Math.max(4, Math.floor((H - TOP - FOOT) / FIXED_ROW))
    const span = Math.min(ref * 0.1, Math.max(ref * 0.004, g.range.max - g.range.min))
    k = niceCeil(span / n / step); aligned = false
  }
  // 变化模式：行不能比服务端快照的步长细（而且要是它的整数倍，免得一格被切两半）
  if (OF.prefs.ladderMode === 'delta' && OF.delta.srvStep > step) {
    const kS = Math.max(1, Math.round(OF.delta.srvStep / step))
    if (k % kS) k = kS * Math.ceil(k / kS)
    if (aligned && Math.abs(g.priceToY(ref) - g.priceToY(ref + step * k)) > ALIGN_MAX * 2) aligned = false
  }
  const rs = step * k
  if (aligned) return { k, rs, aligned, yOf: p => g.priceToY(p) + off, pOf: y => g.yToPrice(y - off) }
  const yA = Math.min(H - FOOT - 60, Math.max(TOP + 60, g.priceToY(ref) + off))
  return { k, rs, aligned, yOf: p => yA - (p - ref) / rs * FIXED_ROW, pOf: y => ref - (y - yA) / FIXED_ROW * rs }
}

/** 活动格子的主图画完一帧：按它的价格轴重画梯子。 */
export function drawLadder(chart: TVChart, g: ChartGeometry): void {
  lastGeo = { chart, g }
  if (!ladderVisible() || !cv || !slot) return
  const sr = slot.getBoundingClientRect(), cr = chart.canvas.getBoundingClientRect()
  const H = Math.max(0, Math.round(sr.height))
  W = Math.max(120, Math.round(sr.width)); L = Math.floor((W - MID_W) / 2); R = L + MID_W
  const dpr = window.devicePixelRatio || 1
  if (cv.width !== Math.round(W * dpr) || cv.height !== Math.round(H * dpr)) {
    cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr)
    cv.style.width = W + 'px'; cv.style.height = H + 'px'
  }
  off = cr.top - sr.top
  const c = cv.getContext('2d')!
  c.setTransform(dpr, 0, 0, dpr, 0, 0)
  c.clearRect(0, 0, W, H)
  hits = []; frame = null
  const empty = slot.querySelector<HTMLElement>('#ofLadEmpty')!
  const info = slot.querySelector<HTMLElement>('#ofLadInfo')!
  const yTop = TOP, yBot = H - FOOT
  if (foot) foot.style.top = `${H - FOOT}px`
  const fine = OF.fine, feed = OF.feed
  const step = feed?.model.scheme?.step
  const delta = OF.prefs.ladderMode === 'delta'
  if (!feed || !fine || !step || fine.step !== step || !fine.ready) {
    empty.hidden = false
    empty.style.top = `${(yTop + yBot) / 2 - 12}px`
    empty.textContent = !feed ? (OF.pending ? '正在连各家交易所的盘口…' : '') : feed.isCalibrating ? '正在按盘口深度定门槛…' : !step ? '正在取步长…' : '正在连各家交易所的盘口…'
    info.textContent = ''
    return
  }
  const sc = scaleFor(g, step, H, fine.mid)
  const { k, rs } = sc
  const pHi = sc.pOf(yTop), pLo = sc.pOf(yBot)
  const rowLo = rowOf(bucketIndex(Math.min(pLo, pHi), step), k), rowHi = rowOf(bucketIndex(Math.max(pLo, pHi), step), k)
  if (!(rowHi >= rowLo) || rowHi - rowLo > 4000) return
  const key = `${fine.asOfMs}|${k}|${rowLo}|${rowHi}|${OF.version}`
  if (!cache || cache.key !== key) cache = { key, rows: ladderRows(fine, k, rowLo, rowHi, OF.snap?.orders ?? []) }
  const rows = cache.rows
  const tKey = `${OF.trades.version}|${k}|${rowLo}|${rowHi}`
  if (!tradeCache || tradeCache.key !== tKey) tradeCache = { key: tKey, rows: OF.trades.rows(k, rowLo, rowHi) }
  const trades = tradeCache.rows
  const now = Date.now()
  // 变化：窗口开始那一列对现在这一列
  let dRows: Map<number, DeltaRow> | null = null
  let start: ReturnType<typeof OF.delta.start> = null
  if (delta) {
    const win = OF.prefs.deltaWin
    if (fine.mid != null) OF.delta.ensure(win, feed.base, feed.chartScale, step, Math.min(pLo, pHi), Math.max(pLo, pHi), fine.mid, now)
    start = OF.delta.start(win, now)
    if (!nowCol || nowCol.at !== fine.asOfMs) nowCol = { at: fine.asOfMs, col: OF.snap ? snapFine(fine, OF.snap.thresholds, now, 0) : null }
    if (start && nowCol.col) {
      const dKey = `${start.col.t}|${start.col.step}|${start.from}|${nowCol.at}|${rs}|${rowLo}|${rowHi}|${OF.delta.version}`
      if (!deltaCache || deltaCache.key !== dKey) deltaCache = { key: dKey, rows: deltaRows(start.col, start.range, nowCol.col, rs, rowLo, rowHi) }
      dRows = deltaCache.rows
    }
  }
  frame = { k, rs, trades, delta: dRows, start: start?.col.t ?? null, startFrom: start?.from ?? null, aligned: sc.aligned,
    midY: fine.mid != null ? g.priceToY(fine.mid) + off : null, centerY: (g.priceToY(g.range.max) + g.priceToY(g.range.min)) / 2 + off }
  empty.hidden = true
  if (delta && !dRows) {
    empty.hidden = false
    empty.style.top = `${(yTop + yBot) / 2 - 12}px`
    empty.textContent = OF.delta.status === 'loading' ? `正在取${WIN_TEXT[OF.prefs.deltaWin]}前的深度…` : '正在记第一列深度…'
  }
  // 脚注：每行多少 · 成交 / 变化从什么时候算起
  const since = OF.trades.since
  const winStart = start ? Math.max(start.col.t, now - WIN_MS[OF.prefs.deltaWin]) : null
  info.textContent = `每行 ${px(rs, decFor(rs, 0))}` + (delta
    ? (winStart != null ? ` · 变化自 ${hm(winStart)} 起` : '')
    : (since != null ? ` · 成交自 ${hm(since)} 起` : ''))
  info.dataset.tip = [
    since != null ? `中列是 ${hm(since)} 打开这只品种以来各家的主动买 − 主动卖` : '',
    delta && start ? `变化的起点来自${start.from === 'server' ? '服务端深度快照' : '本页实时记录（服务端没跟这只或还没取到）'}` : '',
    sc.aligned ? '' : '图放得很大，梯子每行定高、价格范围放宽了',
  ].filter(Boolean).join(' · ')
  const C = g.colors
  let maxOne = 0, maxCum = 0, maxT = 0, maxD = 0
  for (const r of rows.values()) {
    maxOne = Math.max(maxOne, r.bid, r.ask)
    maxCum = Math.max(maxCum, r.cumBid, r.cumAsk)
  }
  for (const t of trades.values()) maxT = Math.max(maxT, t.buy, t.sell)
  if (dRows) for (const d of dRows.values()) maxD = Math.max(maxD, Math.abs(d.dBid), Math.abs(d.dAsk))
  maxOne ||= 1; maxCum ||= 1; maxT ||= 1; maxD ||= 1
  c.save()
  c.beginPath(); c.rect(0, yTop, W, yBot - yTop); c.clip()
  // 中列的底：一道很淡的竖带，把「成交」和两侧的挂单分开
  c.fillStyle = hexA(C.text, 0.03); c.fillRect(L, yTop, MID_W, yBot - yTop)
  // 最新成交所在的行：淡底
  if (g.last != null) {
    const r = Math.floor(g.last / rs)
    const a = sc.yOf((r + 1) * rs), b = sc.yOf(r * rs)
    c.fillStyle = hexA(C.text, 0.06); c.fillRect(0, a, W, b - a)
  }
  c.textBaseline = 'middle'
  const LW = L, RW = W - R
  for (let r = rowLo; r <= rowHi; r++) {
    const x = rows.get(r), t = trades.get(r), d = dRows?.get(r)
    const yT = sc.yOf((r + 1) * rs), yB = sc.yOf(r * rs)
    const h = yB - yT
    if (h <= 0 || yB < yTop || yT > yBot) continue
    if (!x && !t && !d) continue
    const gap = h >= 8 ? 1 : 0
    const y0 = yT + gap / 2, hh = h - gap, cy = (yT + yB) / 2
    hits.push({ y0: yT, y1: yB, row: x ?? blankRow(r, k, step) })
    const big = !!x && x.orders.length > 0
    if (!delta && x) {
      // 累计（淡）
      if (x.cumBid > 0) { const w = LW * x.cumBid / maxCum; c.fillStyle = hexA(C.up, 0.25); c.fillRect(L - w, y0, w, hh) }
      if (x.cumAsk > 0) { const w = RW * x.cumAsk / maxCum; c.fillStyle = hexA(C.down, 0.25); c.fillRect(R, y0, w, hh) }
      // 这一行本身（实）
      if (x.bid > 0) { const w = Math.max(1, LW * x.bid / maxOne); c.fillStyle = hexA(C.up, big && x.orders.some(o => o.side === 'bid') ? 0.95 : 0.6); c.fillRect(L - w, y0, w, hh) }
      if (x.ask > 0) { const w = Math.max(1, RW * x.ask / maxOne); c.fillStyle = hexA(C.down, big && x.orders.some(o => o.side === 'ask') ? 0.95 : 0.6); c.fillRect(R, y0, w, hh) }
      if (h >= 12) {
        c.font = canvasFont(11); c.textAlign = 'right'; c.fillStyle = C.text
        if (x.bid > 0) c.fillText(amt(x.bid), L - PAD, cy)
        if (x.ask > 0) c.fillText(amt(x.ask), W - PAD, cy)
      }
    }
    if (delta && d) {
      // 变化：增加实色、减少淡底加描边；数字带符号
      const bar = (v: number, col: string, left: boolean): void => {
        if (!v) return
        const w = Math.max(1, (left ? LW : RW) * Math.abs(v) / maxD), x0 = left ? L - w : R
        if (v > 0) { c.fillStyle = hexA(col, 0.6); c.fillRect(x0, y0, w, hh) }
        else { c.fillStyle = hexA(col, 0.14); c.fillRect(x0, y0, w, hh); c.strokeStyle = hexA(col, 0.7); c.lineWidth = 1; c.strokeRect(x0 + .5, y0 + .5, Math.max(0, w - 1), Math.max(0, hh - 1)) }
      }
      bar(d.dBid, C.up, true); bar(d.dAsk, C.down, false)
      if (h >= 12) {
        c.font = canvasFont(11); c.textAlign = 'right'; c.fillStyle = C.text
        if (d.dBid) c.fillText(signedAmt(d.dBid), L - PAD, cy)
        if (d.dAsk) c.fillText(signedAmt(d.dAsk), W - PAD, cy)
      }
      if (pinned === r) { c.strokeStyle = hexA(C.text, 0.6); c.lineWidth = 1; c.strokeRect(.5, yT + .5, W - 1, Math.max(0, h - 1)) }
    }
    // 中列：主动买 / 主动卖两条淡色细条（买从左沿、卖从右沿），中间写净额
    if (t) {
      const half = MID_W / 2
      if (t.buy > 0) { c.fillStyle = hexA(C.up, 0.2); c.fillRect(L, y0, Math.max(1, half * t.buy / maxT), hh) }
      if (t.sell > 0) { const w = Math.max(1, half * t.sell / maxT); c.fillStyle = hexA(C.down, 0.2); c.fillRect(R - w, y0, w, hh) }
      const net = t.buy - t.sell
      if (h >= 12 && net) {
        c.font = canvasFont(11, 500); c.textAlign = 'center'; c.fillStyle = net > 0 ? C.up : C.down
        c.fillText(signedAmt(net), L + half, cy)
      }
    }
    if (big) {
      const o = x!.orders[0]
      c.fillStyle = bandColor(o.product, o.side, 1)
      c.fillRect(0, yT, 3, h)
      if (!delta && h >= 10) pill(c, x!, cy, o.side === 'bid')
    }
  }
  // 中间价与价差
  if (fine.mid != null) {
    const y = Math.round(sc.yOf(fine.mid)) + .5
    c.strokeStyle = hexA(C.text, 0.55); c.lineWidth = 1
    c.beginPath(); c.moveTo(0, y); c.lineTo(W, y); c.stroke()
    const bps = fine.bestBid != null && fine.bestAsk != null && fine.mid > 0 ? (fine.bestAsk - fine.bestBid) / fine.mid * 1e4 : null
    const t = `${px(fine.mid, Math.max(g.dec, decFor(step, 0)))}${bps != null ? ` · 价差 ${bps < 10 ? bps.toFixed(2) : bps.toFixed(1)} bps` : ''}`
    c.font = canvasFont(11, 500)
    const tw = c.measureText(t).width
    const cx = W / 2
    c.fillStyle = C.bg; c.fillRect(cx - tw / 2 - 6, y - 8, tw + 12, 16)
    c.strokeStyle = hexA(C.text, 0.3); c.strokeRect(cx - tw / 2 - 5.5, y - 7.5, tw + 11, 15)
    c.fillStyle = C.text; c.textAlign = 'center'; c.fillText(t, cx, y)
  }
  c.restore()
}

const signedAmt = (v: number): string => (v > 0 ? '+' : v < 0 ? '−' : '') + amt(Math.abs(v))

/** 只有成交或变化、没有挂单的行：给悬停与拖动一个空壳 */
function blankRow(r: number, k: number, step: number): LadderRow {
  const n = OF.fine?.venues.length ?? 0
  return { row: r, low: r * k * step, high: (r + 1) * k * step, bid: 0, ask: 0, cumBid: 0, cumAsk: 0, bidBy: new Float64Array(n), askBy: new Float64Array(n), orders: [] }
}

/** 大单胶囊：画在这一行空着的那半边（买单行在卖半边、卖单行在买半边）。 */
function pill(c: CanvasRenderingContext2D, x: LadderRow, y: number, bidRow: boolean): void {
  const o = x.orders[0]
  const room = L - 8
  c.font = canvasFont(11, 600)
  // 胶囊只有半边宽：放不下「交易所产品 金额」就只留金额，存活时长与其余细节在悬停卡片里
  const full = `${venueName(exName(o.exchange), o.product)} ${amt(o.notional)}`
  const t = c.measureText(full).width + 12 + (x.orders.length > 1 ? 23 : 0) <= room ? full : amt(o.notional)
  // 同一行还有别家 / 别的产品的大单：胶囊后面跟几个小点（最多三个），悬停卡片里全列
  const seen = new Set([o.venueID + o.side])
  const others: typeof x.orders = []
  for (const q of x.orders) if (!seen.has(q.venueID + q.side)) { seen.add(q.venueID + q.side); others.push(q) }
  const dots = others.slice(0, 3)
  const dw = dots.length ? dots.length * 7 + 2 : 0
  const w = Math.min(room, c.measureText(t).width + 12 + dw), h = 16
  const x0 = bidRow ? R + 4 : L - 4 - w
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
  lastGeo.chart.zoomPrice(Math.exp(e.deltaY * 0.002), frame?.aligned === false ? undefined : y - off)
}

function leaveRow(): void {
  hideCard()
  if (cv) cv.style.cursor = ''
  if (OF.hoverRow) { OF.hoverRow = null; if (lastGeo) lastGeo.chart.dirty = true }
}

function onMove(e: PointerEvent): void {
  const { x, y } = local(e)
  if (drag) {
    if (drag.row && !drag.moved && Math.hypot(x - drag.x, y - drag.y) > 4) {
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
}

function onDown(e: PointerEvent): void {
  if (e.button !== 0) return
  const { x, y } = local(e)
  drag = { row: rowAt(y)?.row ?? null, x, y, moved: false, ghost: null }
  cv!.setPointerCapture?.(e.pointerId)
}

function onUp(e: PointerEvent): void {
  if (!drag) return
  const d = drag; drag = null
  d.ghost?.remove()
  if (d.moved && d.row) {
    // 落点在活动图的画布范围里就算（画布上面还叠着十字线层等，不能靠 elementFromPoint 认）
    const act = OF.api?.activeChart()
    const r = act?.chart.canvas.getBoundingClientRect()
    if (r && e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom) OF.api?.addHline(center(d.row))
    return
  }
  // 单击等 250 ms 看是不是双击：双击 = 图回到中间价（不管点在哪一行）
  const t = performance.now()
  if (clickTimer && t - lastUpAt < 320) { clearTimeout(clickTimer); clickTimer = 0; recenter(); return }
  lastUpAt = t
  const row = d.row, cx = e.clientX, cy = e.clientY
  clickTimer = window.setTimeout(() => { clickTimer = 0; if (row) single(row, cx, cy) }, 250)
}

function single(row: LadderRow, cx: number, cy: number): void {
  if (OF.prefs.ladderMode === 'delta') {
    pinned = pinned === row.row ? null : row.row
    redrawLadder()
    showCard(rowCard(row), cx, cy)
    return
  }
  hideCard(); OF.api?.openAlert(center(row))
}

/** 双击：活动图的价格轴挪到中间价（不改缩放） */
function recenter(): void {
  const mid = OF.fine?.mid ?? lastGeo?.g.last
  if (mid == null || !lastGeo) return
  hideCard()
  lastGeo.chart.centerOn(null, mid)
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
  const delta = OF.prefs.ladderMode === 'delta'
  const lines: string[] = []
  if (fine && !delta) {
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
  const orders = r.orders.map(o => `<div class="of-card-r"><span><i class="sw" style="background:${bandColor(o.product, o.side, 1)}"></i>${esc(venueName(exName(o.exchange), o.product))} 大单</span><b class="num">${amt(o.notional)} · ${durShort(Date.now() - o.firstSeenMs)}</b></div>`).join('')
  // 成交（中列）与距中间价
  const t = frame?.trades.get(r.row)
  const since = OF.trades.since
  const tr = t && (t.buy > 0 || t.sell > 0)
    ? `<div class="of-card-r"><span>主动买 · 主动卖</span><b class="num"><span class="up">${amt(t.buy)}</span> · <span class="down">${amt(t.sell)}</span></b></div>
       <div class="of-card-r"><span>净差</span><b class="num ${t.buy >= t.sell ? 'up' : 'down'}">${signedAmt(t.buy - t.sell)} · ${signedPct(deltaPct(t), 0)}</b></div>`
    : since != null ? `<div class="of-card-r"><span>成交</span><b class="num faint">${hm(since)} 以来没有</b></div>` : ''
  const dist = `<div class="of-card-r"><span>距中间价</span><b class="num">${signedPct(fromMidPct(center(r), fine?.mid ?? null))}</b></div>`
  let body: string
  if (delta) {
    const x = frame?.delta?.get(r.row)
    const win = OF.prefs.deltaWin
    const startT = frame?.start != null ? Math.max(frame.start, Date.now() - WIN_MS[win]) : null
    const ago = startT != null ? `${hm(startT)} 起` : WIN_TEXT[win]
    body = x
      ? `<div class="of-card-r"><span>买 · ${ago}</span><b class="num up">${signedAmt(x.dBid)}</b></div>
         <div class="of-card-r"><span></span><b class="num faint">${amt(x.bid0)} → ${amt(x.bid)}</b></div>
         <div class="of-card-r"><span>卖 · ${ago}</span><b class="num down">${signedAmt(x.dAsk)}</b></div>
         <div class="of-card-r"><span></span><b class="num faint">${amt(x.ask0)} → ${amt(x.ask)}</b></div>`
      : `<div class="of-card-r"><span>变化</span><b class="faint">窗口开始时没记到这一行</b></div>`
    if (pinned === r.row && frame) {
      const pts = rowSeries(OF.delta.series(win, Date.now()), r.row, frame.rs)
      const css = cv ? getComputedStyle(cv) : null
      const svg = sparkSVG(pts, 200, 44, css?.getPropertyValue('--up').trim() || '#089981', css?.getPropertyValue('--down').trim() || '#F23645')
      body += `<div class="of-card-sep"></div>${svg || '<div class="of-card-r faint"><span>这一段还没有足够的记录</span></div>'}`
    }
  } else {
    body = `<div class="of-card-r"><span>买 · 累计</span><b class="num up">${amt(r.bid)} · ${amt(r.cumBid)}</b></div>
      <div class="of-card-r"><span>卖 · 累计</span><b class="num down">${amt(r.ask)} · ${amt(r.cumAsk)}</b></div>`
  }
  return `<div class="of-card-h">${px(r.low, d)} – ${px(r.high, d)}</div>
    ${body}${tr}${dist}
    ${orders}${lines.length ? `<div class="of-card-sep"></div>${lines.join('')}` : ''}
    <div class="of-card-foot">${delta ? '点一下看这一价位的走势' : '点一下建提醒 · 拖到图上画水平线'} · 双击回到中间价</div>`
}

/** 诊断（回归脚本用）：这一帧梯子的行、覆盖的高度、中列与变化各有几行 */
export function ladderDebug(): unknown {
  if (!frame || !cv) return null
  const H = cv.clientHeight
  const top = hits.length ? Math.min(...hits.map(h => h.y0)) : null, bot = hits.length ? Math.max(...hits.map(h => h.y1)) : null
  return {
    mode: OF.prefs.ladderMode, win: OF.prefs.deltaWin, k: frame.k, rs: frame.rs, aligned: frame.aligned, H, rows: hits.length,
    top, bottom: bot, rowH: hits.length ? Math.round((hits[0].y1 - hits[0].y0) * 10) / 10 : null,
    trades: [...frame.trades.values()].filter(t => t.buy > 0 || t.sell > 0).length,
    delta: frame.delta ? [...frame.delta.values()].filter(d => d.dBid || d.dAsk).length : null, deltaFrom: frame.startFrom,
    pinned, info: slot?.querySelector('#ofLadInfo')?.textContent ?? '',
    midY: frame.midY != null ? Math.round(frame.midY) : null, centerY: Math.round(frame.centerY),
    // 回归脚本悬停 / 点用：第一行有成交的、第一行有变化的（行中点，梯子画布坐标）
    tradeY: yOfFirst(h => { const t = frame!.trades.get(h.row.row); return !!t && t.buy > 0 && t.sell > 0 }),
    deltaY: yOfFirst(h => { const d = frame!.delta?.get(h.row.row); return !!d && (d.dBid !== 0 || d.dAsk !== 0) && h.y1 - h.y0 >= 6 }),
  }
}

function yOfFirst(f: (h: Hit) => boolean): number | null {
  const H = cv?.clientHeight ?? 0
  const h = hits.find(x => x.y0 >= TOP && x.y1 <= H - FOOT && f(x))
  return h ? Math.round((h.y0 + h.y1) / 2) : null
}

/** 数据变了但图没动：用上次的坐标重画。 */
export function redrawLadder(): void { if (lastGeo) drawLadder(lastGeo.chart, lastGeo.g) }

/** 换品种：点过的行、缓存都不要了 */
export function resetLadder(): void { pinned = null; cache = null; tradeCache = null; deltaCache = null; nowCol = null }
