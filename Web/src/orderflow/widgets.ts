/* Hkline Web · 主力订单流 · 侧栏小部件（设计稿 2.5）
 *
 * 「自选」视图里和自选列表、详情堆在一起：盘口（360）、成交（占剩余高度）、大单（240）、提醒（160）。
 * 每块都能收起、能拖着换顺序（顺序存 st.slots.widgets，随账号同步；收起是网页本机偏好）。
 * 盘口与大单跟着订单流的帧（半秒一帧）打补丁；成交是一张画布，逐笔来了在下一帧（rAF）里重画，
 * 每秒几十笔也只画一次。
 */
import { st, save, type WidgetId } from '../app/store'
import { I, esc } from '../ui/dom'
import { toast } from '../ui/overlay'
import { hexA } from '../util/format'
import { pressure, steppedBook, exName, venueName, PRODUCT_SHORT, type FineBook } from './aggregate'
import { orderId, type BigOrder, type Product } from './types'
import { tapeBase, type TapeRow } from './tape'
import { parseAmount } from './settings'
import { OF, savePrefs, amt, hms, durShort, decFor, px, canvasFont, bandColor } from './state'

export const OF_WIDGETS: WidgetId[] = ['book', 'tape', 'walls', 'alerts']
const TITLE: Record<string, string> = { book: '盘口', tape: '成交', walls: '大单', alerts: '提醒', watch: '自选', detail: '详情' }
export const isOfWidget = (w: WidgetId): boolean => OF_WIDGETS.includes(w)

// ------------------------------------------------------------------ 外壳

function shell(w: WidgetId, body: string, extra = ''): string {
  const c = OF.prefs.collapsed.includes(w)
  return `<section class="widget of-w of-w-${w} ${c ? 'collapsed' : ''}" data-w="${w}" aria-label="${TITLE[w]}">
    <div class="of-w-head" draggable="true">
      <span class="of-grip" aria-hidden="true">${I('drag', 'icon-16')}</span>
      <h3>${TITLE[w]}</h3>${extra}
      <button class="ibtn xs" data-of="collapse" aria-label="${c ? '展开' : '收起'}" aria-expanded="${!c}" data-tip="${c ? '展开' : '收起'}">${I('chevronDown', 'icon-16 of-chev')}</button>
      <button class="ibtn xs" data-of="remove" aria-label="从侧栏移除" data-tip="移除">${I('close', 'icon-16')}</button>
    </div>
    <div class="of-w-body">${body}</div></section>`
}

/** 侧栏「自选」视图里某个订单流小部件的 HTML（图表页 panelWatch 调）。 */
export function widgetHTML(w: WidgetId): string {
  switch (w) {
    case 'book': return shell('book', `
      <div class="of-press" id="ofPress"></div>
      <div class="of-venues" id="ofVenues"></div>
      <div class="of-book" id="ofBook"></div>`, `<div class="seg of-unit" role="group" aria-label="单位">
        <button data-of="unit" data-v="usd" aria-pressed="${OF.prefs.bookUnit === 'usd'}">美元</button>
        <button data-of="unit" data-v="coin" aria-pressed="${OF.prefs.bookUnit === 'coin'}">币</button></div>`)
    case 'tape': return shell('tape', `<div class="of-tape-host"><canvas id="ofTape" aria-label="合并成交"></canvas></div>`,
      `<label class="of-min" data-tip="只看不小于这个金额的成交（并过之后）"><span>≥</span><input id="ofTapeMin" class="input num" inputmode="decimal" spellcheck="false"></label>
       <button class="ibtn xs" data-of="pause" id="ofTapePause" aria-label="暂停" data-tip="暂停">${I('pause', 'icon-16')}</button>`)
    case 'walls': return shell('walls', `<div class="scroll of-walls" id="ofWalls"></div>`, `<span class="faint num" id="ofWallsN"></span>`)
    case 'alerts': return shell('alerts', `<div class="scroll of-alerts" id="ofAlerts"></div>`, `<button class="ibtn xs" data-of="alert-new" aria-label="新建提醒" data-tip="新建提醒">${I('plus', 'icon-16')}</button>`)
    default: return ''
  }
}

let root: HTMLElement | null = null
let tapeCv: HTMLCanvasElement | null = null
let ro: ResizeObserver | null = null

/** panelWatch 写完 innerHTML 之后调：绑事件、画第一帧。 */
export function mountWidgets(el: HTMLElement): void {
  root = el
  // 自选与详情也参与拖动排序
  el.querySelector<HTMLElement>('.widget-watch')?.setAttribute('data-w', 'watch')
  el.querySelector<HTMLElement>('#detail')?.setAttribute('data-w', 'detail')
  if (!el.dataset.ofBound) {
    el.dataset.ofBound = '1'
    el.addEventListener('click', onClick)
    el.addEventListener('change', onChange)
    el.addEventListener('keydown', e => { if (e.key === 'Enter' && (e.target as HTMLElement).id === 'ofTapeMin') (e.target as HTMLInputElement).blur() })
    bindSort(el)
  }
  tapeCv = el.querySelector<HTMLCanvasElement>('#ofTape')
  ro?.disconnect()
  if (tapeCv) {
    ro = new ResizeObserver(() => { tapeDirty = true; scheduleTape() })
    ro.observe(tapeCv.parentElement!)
    tapeCv.onmousemove = onTapeHover
    tapeCv.onmouseleave = () => { tapeHover = -1; tapeDirty = true; scheduleTape() }
    tapeCv.onclick = onTapeClick
  }
  syncTapeMin()
  updateWidgets()
  tapeDirty = true; scheduleTape()
}

function mounted(): boolean { return !!root && root.isConnected && st.panel === 'watch' }

// ------------------------------------------------------------------ 事件

function onClick(e: MouseEvent): void {
  const b = (e.target as HTMLElement).closest<HTMLElement>('[data-of]')
  if (!b) {
    const wall = (e.target as HTMLElement).closest<HTMLElement>('[data-wall]')
    if (wall) { const o = OF.snap?.orders.find(x => orderId(x) === wall.dataset.wall); if (o) OF.focus?.(o) }
    const del = (e.target as HTMLElement).closest<HTMLElement>('[data-of-del]')
    if (del) { OF.api?.deleteAlert(del.dataset.ofDel || ''); updateAlerts() }
    return
  }
  e.stopPropagation()
  const w = b.closest<HTMLElement>('[data-w]')?.dataset.w as WidgetId | undefined
  switch (b.dataset.of) {
    case 'collapse': {
      if (!w) return
      const c = OF.prefs.collapsed
      if (c.includes(w)) c.splice(c.indexOf(w), 1); else c.push(w)
      savePrefs(); OF.api?.renderPanel(); return
    }
    case 'remove': {
      if (!w) return
      st.slots.widgets = st.slots.widgets.filter(x => x !== w)
      save(); OF.api?.renderPanel()
      toast(`已从侧栏移除「${TITLE[w]}」`, '在「主力订单流」面板里可以加回来', 'check', 2400)
      return
    }
    case 'unit': {
      OF.prefs.bookUnit = b.dataset.v === 'coin' ? 'coin' : 'usd'; savePrefs()
      b.parentElement?.querySelectorAll('button').forEach(x => x.setAttribute('aria-pressed', String(x === b)))
      updateBook(); return
    }
    case 'band': { OF.prefs.band = +(b.dataset.v || 1); savePrefs(); updateBook(); return }
    case 'pause': {
      tapePaused = tapePaused ? null : OF.tape.visible(tapeMin(), 200)
      b.innerHTML = I(tapePaused ? 'play' : 'pause', 'icon-16')
      b.setAttribute('aria-label', tapePaused ? '继续' : '暂停'); b.dataset.tip = tapePaused ? '继续' : '暂停'
      b.classList.toggle('on', !!tapePaused)
      tapeDirty = true; scheduleTape(); return
    }
    case 'alert-new': OF.api?.openAlert(); return
  }
}

function onChange(e: Event): void {
  const t = e.target as HTMLInputElement
  if (t.id !== 'ofTapeMin') return
  const base = OF.feed?.base
  if (!base) return
  const v = parseAmount(t.value)
  if (v == null) delete OF.prefs.tapeMin[base]
  else OF.prefs.tapeMin[base] = v
  savePrefs(); syncTapeMin()
  tapePaused = null; tapeDirty = true; scheduleTape()
}


function syncTapeMin(): void {
  const inp = root?.querySelector<HTMLInputElement>('#ofTapeMin')
  if (!inp || document.activeElement === inp) return
  const base = OF.feed?.base
  const own = base ? OF.prefs.tapeMin[base] : undefined
  inp.value = own ? amt(own) : ''
  inp.placeholder = amt(defaultTapeMin())
}

// ------------------------------------------------------------------ 拖动排序

function bindSort(el: HTMLElement): void {
  let from: string | null = null
  const clear = (): void => el.querySelectorAll('.drop-above,.drop-below').forEach(x => x.classList.remove('drop-above', 'drop-below'))
  el.addEventListener('dragstart', e => {
    const h = (e.target as HTMLElement).closest?.('.of-w-head')
    if (!h) return
    from = h.closest<HTMLElement>('[data-w]')?.dataset.w ?? null
    if (e.dataTransfer) { e.dataTransfer.effectAllowed = 'move'; e.dataTransfer.setData('text/plain', from || '') }
    h.closest('[data-w]')?.classList.add('dragging')
  })
  el.addEventListener('dragend', () => { from = null; clear(); el.querySelectorAll('.dragging').forEach(x => x.classList.remove('dragging')) })
  el.addEventListener('dragover', e => {
    if (!from) return
    const w = (e.target as HTMLElement).closest<HTMLElement>('[data-w]')
    if (!w || w.dataset.w === from) return
    e.preventDefault(); clear()
    const r = w.getBoundingClientRect()
    w.classList.add(e.clientY < r.top + r.height / 2 ? 'drop-above' : 'drop-below')
  })
  el.addEventListener('drop', e => {
    const w = (e.target as HTMLElement).closest<HTMLElement>('[data-w]')
    if (!from || !w || w.dataset.w === from) return
    e.preventDefault()
    const list = st.slots.widgets.filter(x => x !== from)
    let i = list.indexOf(w.dataset.w as WidgetId)
    if (i < 0) return
    if (w.classList.contains('drop-below')) i++
    list.splice(i, 0, from as WidgetId)
    st.slots.widgets = list; from = null
    save(); OF.api?.renderPanel()
  })
}

// ------------------------------------------------------------------ 帧更新

/** 订单流出了一帧：盘口、大单、提醒打补丁。 */
export function updateWidgets(): void {
  if (!mounted()) return
  updateBook(); updateWalls(); updateAlerts(); syncTapeMin()
}

const BANDS = [1, 2, 5]
const BOOK_LEVELS = 8

function unitAmt(usd: number, price: number | null): string {
  if (OF.prefs.bookUnit === 'coin' && price && price > 0) return amt(usd / price)
  return amt(usd)
}

function updateBook(): void {
  const el = root?.querySelector<HTMLElement>('.of-w-book')
  if (!el || el.classList.contains('collapsed')) return
  const feed = OF.feed, fine = OF.fine
  const pEl = el.querySelector<HTMLElement>('#ofPress')!, vEl = el.querySelector<HTMLElement>('#ofVenues')!, bEl = el.querySelector<HTMLElement>('#ofBook')!
  if (!feed || !fine || !fine.ready) {
    pEl.innerHTML = `<div class="of-wait faint">${feed ? '正在连三家交易所的盘口…' : '打开指标「主力订单流」或深度梯子后开始接盘口'}</div>`
    vEl.innerHTML = ''; bEl.innerHTML = ''
    return
  }
  const mid = fine.mid
  const pr = pressure(feed.model, BANDS)
  const band = OF.prefs.band
  const bi = Math.max(0, BANDS.indexOf(band))
  const t = pr.total[bi]
  const sum = t.bid + t.ask
  const share = sum > 0 ? t.bid / sum : 0.5
  pEl.innerHTML = `<div class="of-press-top">
      <div class="of-bands" role="group" aria-label="距中间价">${BANDS.map(b => `<button class="chip" data-of="band" data-v="${b}" aria-pressed="${b === band}">±${b}%</button>`).join('')}</div>
      <span class="num up">买 ${unitAmt(t.bid, mid)}</span><span class="num down">卖 ${unitAmt(t.ask, mid)}</span></div>
    <div class="of-press-bar" data-tip="中间价 ±${band}% 以内三家所有簿的买卖挂单名义"><i class="b" style="width:${(share * 100).toFixed(1)}%"></i><i class="a"></i>
      <span class="l num">${(share * 100).toFixed(0)}%</span><span class="r num">${((1 - share) * 100).toFixed(0)}%</span></div>`
  // 各家：交易所 × 产品，同一格里几本（比如两个交割）加总
  const cells = new Map<string, { bid: number; ask: number }>()
  const exs: string[] = [], prods: Product[] = []
  for (const v of pr.byVenue) {
    const k = v.meta.exchange + '|' + v.meta.product
    const c = cells.get(k) ?? { bid: 0, ask: 0 }
    c.bid += v.bands[bi].bid; c.ask += v.bands[bi].ask
    cells.set(k, c)
    if (!exs.includes(v.meta.exchange)) exs.push(v.meta.exchange)
    if (!prods.includes(v.meta.product)) prods.push(v.meta.product)
  }
  const order: Product[] = ['usdtPerp', 'spot', 'coinPerp', 'delivery']
  prods.sort((a, b) => order.indexOf(a) - order.indexOf(b))
  const exOrder = ['binance', 'okx', 'coinbase']
  exs.sort((a, b) => exOrder.indexOf(a) - exOrder.indexOf(b))
  let maxSide = 0
  for (const c of cells.values()) maxSide = Math.max(maxSide, c.bid, c.ask)
  maxSide ||= 1
  vEl.style.gridTemplateColumns = `56px repeat(${exs.length}, minmax(0,1fr))`
  vEl.innerHTML = `<span></span>${exs.map(e => `<span class="of-vh">${exName(e)}</span>`).join('')}` + prods.map(p =>
    `<span class="of-vp">${PRODUCT_SHORT[p]}</span>` + exs.map(e => {
      const c = cells.get(e + '|' + p)
      if (!c) return '<span class="of-vc none faint">—</span>'
      return `<span class="of-vc" data-tip="${venueName(exName(e), p)}：买 ${amt(c.bid)} · 卖 ${amt(c.ask)}"><i class="b" style="width:${(c.bid / maxSide * 50).toFixed(1)}%"></i><i class="a" style="width:${(c.ask / maxSide * 50).toFixed(1)}%"></i><em class="num">${amt(c.bid + c.ask)}</em></span>`
    }).join('')).join('')
  // 分档盘口：买左卖右，各 8 档
  const step = fine.step
  const k = bookK(fine)
  const sb = steppedBook(fine, k, BOOK_LEVELS)
  const d = decFor(step * k, OF.api?.dec(OF.feed!.symbol) ?? 2)
  const maxOne = Math.max(1, ...sb.bids.map(r => r.usd), ...sb.asks.map(r => r.usd))
  const maxCum = Math.max(1, sb.bids[sb.bids.length - 1]?.cum ?? 0, sb.asks[sb.asks.length - 1]?.cum ?? 0)
  const coin = OF.prefs.bookUnit === 'coin'
  const row = (r: { price: number; usd: number; cum: number; qty: number }, side: 'b' | 'a'): string =>
    `<div class="of-br ${side}"><i class="c" style="width:${(r.cum / maxCum * 100).toFixed(1)}%"></i><i class="o" style="width:${(r.usd / maxOne * 100).toFixed(1)}%"></i>
      <span class="p num">${px(r.price, d)}</span><span class="v num">${r.usd > 0 ? (coin ? amt(r.qty) : amt(r.usd)) : ''}</span><span class="s num faint">${coin ? amt(r.cum / Math.max(r.price, 1e-12)) : amt(r.cum)}</span></div>`
  bEl.innerHTML = `<div class="of-bh"><span>买 · 每档 ${px(step * k, decFor(step * k, 0))}</span><span class="num">${mid != null ? px(mid, d) : '—'}</span><span>卖</span></div>
    <div class="of-bcols"><div class="of-bcol">${sb.bids.map(r => row(r, 'b')).join('')}</div><div class="of-bcol">${sb.asks.map(r => row(r, 'a')).join('')}</div></div>`
}

/** 盘口分档的行倍数：一档至少覆盖中间价 0.02%，免得 8 档挤在一两个 tick 里。 */
function bookK(fine: FineBook): number {
  const mid = fine.mid ?? 0
  if (!(mid > 0)) return 1
  const want = mid * 0.0002
  for (const f of [1, 2, 5, 10, 20, 50, 100]) if (fine.step * f >= want) return f
  return 100
}

function updateWalls(): void {
  const el = root?.querySelector<HTMLElement>('.of-w-walls')
  if (!el || el.classList.contains('collapsed')) return
  const box = el.querySelector<HTMLElement>('#ofWalls')!, n = el.querySelector<HTMLElement>('#ofWallsN')!
  const live = (OF.snap?.orders ?? []).filter(o => o.status === 'live').sort((a, b) => b.notional - a.notional)
  n.textContent = live.length ? `${live.length} 单` : ''
  if (!OF.feed) { box.innerHTML = `<div class="of-wait faint">打开指标「主力订单流」后显示</div>`; return }
  if (!live.length) { box.innerHTML = `<div class="of-wait faint">${OF.snap?.phase === 'ready' || OF.snap?.phase == null ? '现在没有达到门槛的挂单' : '正在接盘口…'}</div>`; return }
  const dec = decFor(OF.feed.model.scheme?.step ?? 0, OF.api?.dec(OF.feed.symbol) ?? 2)
  const now = Date.now()
  const max = live[0].notional
  box.innerHTML = live.slice(0, 60).map(o => {
    const id = orderId(o)
    return `<div class="of-wall ${OF.highlight === id ? 'sel' : ''}" data-wall="${esc(id)}" tabindex="0" role="button" aria-label="${o.side === 'bid' ? '买' : '卖'} ${px(o.price, dec)} ${amt(o.notional)}">
      <i class="bar" style="width:${(o.notional / max * 100).toFixed(1)}%;background:${bandColor(o.product, o.side, 0.16)}"></i>
      <span class="sd ${o.side === 'bid' ? 'up' : 'down'}">${o.side === 'bid' ? '买' : '卖'}</span>
      <span class="vn"><i class="sw" style="background:${bandColor(o.product, o.side, 1)}"></i>${venueName(exName(o.exchange), o.product)}</span>
      <span class="p num">${px(o.price, dec)}</span><span class="v num">${amt(o.notional)}</span><span class="t num faint">${durShort(now - o.firstSeenMs)}</span></div>`
  }).join('')
}

function updateAlerts(): void {
  const el = root?.querySelector<HTMLElement>('.of-w-alerts')
  if (!el || el.classList.contains('collapsed')) return
  const a = OF.api?.activeChart()
  const box = el.querySelector<HTMLElement>('#ofAlerts')!
  if (!a || !OF.api) { box.innerHTML = ''; return }
  const list = OF.api.alertsFor(a.symbol)
  const html = list.length ? list.map(x => `<div class="of-al"><span class="num">${esc(OF.api!.alertDesc(x))}</span><button class="ibtn xs" data-of-del="${x.id}" aria-label="删除提醒" data-tip="删除">${I('trash', 'icon-16')}</button></div>`).join('')
    : `<div class="of-wait faint">这只品种没有还在等的提醒 · 点梯子上的一行就能建</div>`
  if (box.dataset.html !== html) { box.innerHTML = html; box.dataset.html = html }
}

// ------------------------------------------------------------------ 成交带（画布）

let tapeDirty = false
let tapeRaf = 0
let tapeSeen = -1
let tapePaused: TapeRow[] | null = null
let tapeHover = -1
let tapeShown: TapeRow[] = []
const ROW_H = 22

export function defaultTapeMin(): number {
  const t = OF.snap?.thresholds
  const base = t ? tapeBase(t) : null
  return base ? base / 50 : 10_000
}
function tapeMin(): number {
  const base = OF.feed?.base
  return (base && OF.prefs.tapeMin[base]) || defaultTapeMin()
}

/** 逐笔来了：下一帧重画（同一帧里来多少笔都只画一次）。 */
export function scheduleTape(): void {
  if (tapeRaf || !tapeCv) return
  if (document.visibilityState === 'hidden') return
  tapeRaf = requestAnimationFrame(drawTape)
}

function drawTape(): void {
  tapeRaf = 0
  const cv = tapeCv
  if (!cv || !cv.isConnected || !mounted()) return
  if (!tapeDirty && tapeSeen === OF.tape.version) return
  tapeDirty = false; tapeSeen = OF.tape.version
  const host = cv.parentElement!
  const W = host.clientWidth, H = host.clientHeight
  if (!W || !H) return
  const dpr = window.devicePixelRatio || 1
  if (cv.width !== Math.round(W * dpr) || cv.height !== Math.round(H * dpr)) {
    cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr)
    cv.style.width = W + 'px'; cv.style.height = H + 'px'
  }
  const c = cv.getContext('2d')!
  c.setTransform(dpr, 0, 0, dpr, 0, 0)
  c.clearRect(0, 0, W, H)
  const css = getComputedStyle(cv)
  const text1 = css.getPropertyValue('--text-1').trim() || '#131722'
  const text3 = css.getPropertyValue('--text-3').trim() || '#767C8A'
  const up = css.getPropertyValue('--up').trim() || '#089981'
  const down = css.getPropertyValue('--down').trim() || '#F23645'
  const upT = css.getPropertyValue('--up-text').trim() || up
  const downT = css.getPropertyValue('--down-text').trim() || down
  const hover = css.getPropertyValue('--surface-2').trim() || '#F6F7F9'
  const n = Math.ceil(H / ROW_H)
  const rows = tapePaused ?? OF.tape.visible(tapeMin(), n)
  tapeShown = rows
  if (!OF.feed) { hint(c, W, H, text3, '打开指标「主力订单流」后显示三家合并成交'); return }
  if (!rows.length) { hint(c, W, H, text3, `还没有 ≥ ${amt(tapeMin())} 的成交`); return }
  const big = OF.bigTrade || Infinity
  const dec = OF.feed ? decFor(OF.feed.model.scheme?.step ?? 0, OF.api?.dec(OF.feed.symbol) ?? 2) : 2
  const coin = OF.prefs.bookUnit === 'coin'
  // 列：时间 16 · 交易所 76 · 方向块 196 · 价格右对齐 300 · 金额右对齐 W−16
  c.textBaseline = 'middle'
  for (let i = 0; i < rows.length && i < n; i++) {
    const r = rows[i], y = i * ROW_H, cy = y + ROW_H / 2
    const isBig = r.usd >= big
    const col = r.side === 'buy' ? up : down
    if (i === tapeHover) { c.fillStyle = hover; c.fillRect(0, y, W, ROW_H) }
    if (isBig) { c.fillStyle = hexA(col, 0.1); c.fillRect(0, y, W, ROW_H) }
    c.font = canvasFont(12, 400)
    c.fillStyle = text3; c.textAlign = 'left'; c.fillText(hms(r.t), 16, cy)
    c.fillStyle = text1; c.fillText(venueName(exName(r.exchange), r.product), 76, cy)
    c.fillStyle = col
    c.beginPath(); c.roundRect?.(186, cy - 8, 28, 16, 4); if (!c.roundRect) c.rect(186, cy - 8, 28, 16); c.fill()
    c.fillStyle = '#fff'; c.textAlign = 'center'; c.font = canvasFont(11, 600); c.fillText(r.side === 'buy' ? '买' : '卖', 200, cy)
    c.font = canvasFont(12, isBig ? 650 : 400)
    c.textAlign = 'right'; c.fillStyle = r.side === 'buy' ? upT : downT; c.fillText(px(r.price, dec), Math.min(W - 96, 312), cy)
    c.fillStyle = text1
    c.fillText((coin ? amt(r.qty) : amt(r.usd)) + (r.n > 1 ? ` ×${r.n}` : ''), W - 16, cy)
  }
}

function hint(c: CanvasRenderingContext2D, W: number, H: number, color: string, t: string): void {
  c.font = canvasFont(12); c.fillStyle = color; c.textAlign = 'center'; c.textBaseline = 'middle'
  c.fillText(t, W / 2, Math.min(H / 2, 48))
}

function onTapeHover(e: MouseEvent): void {
  const i = Math.floor(e.offsetY / ROW_H)
  const r = tapeShown[i]
  if (i !== tapeHover) { tapeHover = r ? i : -1; tapeDirty = true; scheduleTape() }
  if (tapeCv) {
    tapeCv.style.cursor = r ? 'pointer' : ''
    tapeCv.dataset.tip = r ? `${venueName(exName(r.exchange), r.product)} ${r.side === 'buy' ? '主动买' : '主动卖'} ${amt(r.usd)}${r.n > 1 ? `（1 秒内同价 ${r.n} 笔并成一行）` : ''} · 点一下在图上定位` : ''
  }
}
function onTapeClick(e: MouseEvent): void {
  const r = tapeShown[Math.floor(e.offsetY / ROW_H)]
  if (!r) return
  const a = OF.api?.activeChart()
  a?.chart.centerOn(r.t, r.price)
}

/** 换品种：成交带清空、暂停取消。 */
export function resetTape(): void { tapePaused = null; tapeHover = -1; tapeDirty = true; scheduleTape() }

/** 大单对象在侧栏大单列表里高亮（抽屉 / 图上点过来时）。 */
export function markWall(_o: BigOrder | null): void { updateWalls() }
