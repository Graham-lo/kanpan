/* Hkline Web · 主力订单流 · 侧栏小部件（设计稿 2.5）
 *
 * 「自选」视图里和自选列表、详情堆在一起，整条侧栏一屏放下、不出滚动条（高度分配见 sidebar.ts）：
 * 盘口（交易所 × 产品表 + 分档，档数按高度）、成交（10 行起）、大单（6 行起）、提醒（余下）。
 * 每块都能收起、能拖着换顺序（顺序存 st.slots.widgets，随账号同步；收起是网页本机偏好）。
 * 盘口与大单跟着订单流的帧（半秒一帧）打补丁；成交是一张画布，逐笔来了在下一帧（rAF）里重画，
 * 每秒几十笔也只画一次。
 */
import { st, save, type WidgetId } from '../app/store'
import { I, esc } from '../ui/dom'
import { patchAttr, patchClass, patchShell, patchStyle, patchText, rowPool } from '../ui/patch'
import { toast } from '../ui/overlay'
import { hexA } from '../util/format'
import { pressure, steppedBook, exName, venueName, PRODUCT_SHORT, EXCHANGE_CH, type FineBook } from './aggregate'
import { orderId, type BigOrder, type Product } from './types'
import { tapeBase, bpsText, tapeRowH, tapeRowAlpha, TAPE_ROW_SMALL, type TapeRow } from './tape'
import { parseAmount } from './settings'
import { OF, feedIdleText, savePrefs, amt, hms, durShort, decFor, px, canvasFont, bandColor, productColor } from './state'
import { planSidebar, dragSidebar, sideCanDrag, toggleCollapsed, partsFor, BOOK_ROW, WALL_ROW, PARTS } from './sidebar'
import { sizes, saveSizes } from '../app/sizes'
import { StatChart, statHead, tpsLine, TPS_SHELL, type StatKind } from './statsView'
import { splitter, type Splitter } from '../ui/splitter'
export { toggleCollapsed }

export const OF_WIDGETS: WidgetId[] = ['book', 'tape', 'walls', 'liq', 'vol', 'alerts']
const TITLE: Record<string, string> = { book: '盘口', tape: '成交', walls: '大单', alerts: '提醒', liq: '24 小时流动性', vol: '24 小时成交', watch: '自选', detail: '详情' }
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
    case 'walls': return shell('walls', `<div class="of-walls" id="ofWalls"></div>`, `<span class="faint num" id="ofWallsN"></span>`)
    case 'alerts': return shell('alerts', `<div class="scroll no-bar of-alerts" id="ofAlerts"></div>`, `<button class="ibtn xs" data-of="alert-new" aria-label="新建提醒" data-tip="新建提醒">${I('plus', 'icon-16')}</button>`)
    case 'liq': return shell('liq', `<div class="of-stat-host"><canvas id="ofLiq" aria-label="24 小时流动性"></canvas></div>`, `<span class="of-stat-head" id="ofLiqHead"></span>`)
    case 'vol': return shell('vol', `<div class="of-stat-host"><canvas id="ofVol" aria-label="24 小时成交"></canvas></div>`, `<span class="of-stat-head" id="ofVolHead"></span>`)
    default: return ''
  }
}

// ------------------------------------------------------------------ 24 小时流动性 / 成交

let stats: StatChart[] = []
function mountStats(el: HTMLElement): void {
  stats = (['liq', 'vol'] as StatKind[]).flatMap(k => {
    const cv = el.querySelector<HTMLCanvasElement>(k === 'liq' ? '#ofLiq' : '#ofVol')
    return cv ? [new StatChart(k, cv)] : []
  })
}
/**
 * 详情小部件末尾的「每秒成交」一行。详情是图表页自己画的（renderDetail 整块重写 innerHTML），
 * 这里用 MutationObserver 在它重写之后立刻补回这一行（微任务里，赶在绘制之前，不闪）。
 */
let detailMo: MutationObserver | null = null
function mountTps(el: HTMLElement): void {
  detailMo?.disconnect(); detailMo = null
  const d = el.querySelector<HTMLElement>('#detail')
  if (!d) return
  detailMo = new MutationObserver(() => ensureTps(d))
  detailMo.observe(d, { childList: true })
  ensureTps(d)
}
function ensureTps(d: HTMLElement): void {
  if (!d.isConnected || !d.firstElementChild) return
  let t = d.querySelector<HTMLElement>(':scope > .of-tps-row')
  if (!t) { t = document.createElement('div'); t.className = 'of-tps-row'; d.appendChild(t) }
  const line = tpsLine()
  if (!line) { patchShell(t, '', ''); return }
  patchShell(t, '#tps', TPS_SHELL)
  patchText(t.querySelector('b'), line.txt)
  patchAttr(t.querySelector('path'), 'd', line.d)
}

function updateStats(force = false): void {
  for (const s of stats) {
    const sec = s.cv.closest<HTMLElement>('.of-w')
    if (!sec || sec.classList.contains('collapsed')) continue
    s.draw(force)
    const head = sec.querySelector<HTMLElement>('.of-stat-head')
    const html = statHead(s.kind)
    if (head && head.dataset.html !== html) { head.innerHTML = html; head.dataset.html = html }
  }
}

let root: HTMLElement | null = null
let tapeCv: HTMLCanvasElement | null = null
let ro: ResizeObserver | null = null
let fitRo: ResizeObserver | null = null

/** 按侧栏高度给每块定高（sidebar.ts 的分配）；侧栏换了视图就不管了 */
export function fitStack(el: HTMLElement): void {
  const blocks = [...el.children].filter((x): x is HTMLElement => x instanceof HTMLElement && !!x.dataset.w)
  if (!blocks.length) { el.classList.remove('stack'); return }
  el.classList.add('stack')
  const avail = el.clientHeight
  if (!avail) return
  const ids = blocks.map(p => p.dataset.w as WidgetId)
  const collapsed = new Set(OF.prefs.collapsed)
  // 窄侧栏：详情十二格改两列（app.css .detail.two），高度跟着换
  const parts = partsFor(el.clientWidth)
  el.querySelector('#detail')?.classList.toggle('two', parts !== PARTS)
  const hs = planSidebar(avail, ids, collapsed, parts, sizes.side)
  blocks.forEach((p, i) => { const v = `${hs[i]}px`; if (p.style.height !== v) p.style.height = v })
  placeSideSplits(el, blocks, ids, hs, collapsed)
  // 行数跟着高度走的几块：重排一次
  updateBook(); updateWalls(); updateStats(true); tapeDirty = true; scheduleTape()
}

/**
 * 侧栏块与块之间的分隔条（横线，上下拖）：只在线上下最近的两块能长的块之间挪高度，
 * 定高的详情跟着走；总高不变。松手把展开各块的高度记进本机尺寸（sizes.side），双击回默认分配。
 * 分隔条挂在侧栏容器里（panelWatch 每次重写 innerHTML 会把它们一起清掉，这里按需重建）。
 */
let sideSplits: Splitter[] = []
let sideDrag: { hs: number[]; ids: WidgetId[] } | null = null
function placeSideSplits(el: HTMLElement, parts: HTMLElement[], ids: WidgetId[], hs: number[], collapsed: ReadonlySet<string>): void {
  sideSplits = sideSplits.filter(s => s.el.parentElement === el)
  while (sideSplits.length < parts.length - 1) {
    const k = sideSplits.length
    sideSplits.push(splitter({
      dir: 'y', parent: el, name: `side-${k}`, tip: '拖动调整高度，双击恢复默认',
      onStart: () => {
        const ps = [...el.children].filter((x): x is HTMLElement => x instanceof HTMLElement && !!x.dataset.w)
        sideDrag = { hs: ps.map(p => p.getBoundingClientRect().height), ids: ps.map(p => p.dataset.w as WidgetId) }
      },
      onMove: d => {
        if (!sideDrag) return
        const next = dragSidebar(sideDrag.hs, sideDrag.ids, new Set(OF.prefs.collapsed), k, d)
        const side: Record<string, number> = { ...(sizes.side || {}) }
        sideDrag.ids.forEach((id, i) => { if (!OF.prefs.collapsed.includes(id) && !PARTS[id]?.fixed) side[id] = next[i] })
        sizes.side = side
        fitStack(el)
      },
      onEnd: () => { sideDrag = null; saveSizes() },
      onReset: () => { delete sizes.side; saveSizes(); fitStack(el) },
    }))
  }
  while (sideSplits.length > parts.length - 1) sideSplits.pop()!.destroy()
  let y = 0
  sideSplits.forEach((s, k) => {
    y += hs[k]
    const on = sideCanDrag(ids, collapsed, k)
    s.show(on)
    if (on) s.place(y, 0, el.clientWidth)
  })
}

/** panelWatch 写完 innerHTML 之后调：绑事件、画第一帧。 */
export function mountWidgets(el: HTMLElement): void {
  root = el
  // 自选与详情也参与拖动排序、也能收起
  el.querySelector<HTMLElement>('.widget-watch')?.setAttribute('data-w', 'watch')
  el.querySelector<HTMLElement>('#detail')?.setAttribute('data-w', 'detail')
  fitStack(el)
  if (!fitRo) {
    fitRo = new ResizeObserver(() => { if (root && root.isConnected && st.panel === 'watch') fitStack(root) })
    fitRo.observe(el)
  }
  if (!el.dataset.ofBound) {
    el.dataset.ofBound = '1'
    el.addEventListener('click', onClick)
    el.addEventListener('change', onChange)
    el.addEventListener('keydown', e => { if (e.key === 'Enter' && (e.target as HTMLElement).id === 'ofTapeMin') (e.target as HTMLInputElement).blur() })
    bindSort(el)
  }
  mountStats(el)
  mountTps(el)
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
      toggleCollapsed(OF.prefs.collapsed, w)
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
  updateBook(); updateWalls(); updateAlerts(); updateStats(); syncTapeMin()
  const d = root?.querySelector<HTMLElement>('#detail'); if (d) ensureTps(d)
}

const BANDS = [1, 2, 5]
/** 分档盘口的档数：按这块的高度能放几行（至少 4、最多 30） */
function bookLevels(bEl: HTMLElement): number {
  const h = bEl.clientHeight
  return h ? Math.max(4, Math.min(30, Math.floor((h - 20 - 4 + 1) / BOOK_ROW))) : 8
}


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
    const w = `<div class="of-wait faint">${feed ? '正在连各家交易所的盘口…' : '打开指标「主力订单流」或深度梯子后开始接盘口'}</div>`
    patchShell(pEl, w, w); patchShell(vEl, '', ''); patchShell(bEl, '', '')
    return
  }
  const mid = fine.mid
  const pr = pressure(feed.model, BANDS)
  const band = OF.prefs.band
  const bi = Math.max(0, BANDS.indexOf(band))
  const t = pr.total[bi]
  const sum = t.bid + t.ask
  const share = sum > 0 ? t.bid / sum : 0.5
  // 外壳（档位钮、条）只建一次；每帧只改字、条宽、钮的按下态与条的悬停说明——整块重写会把指针下的档位钮换掉（点不上、悬停说明跑到左上角）
  patchShell(pEl, 'press', `<div class="of-press-top">
      <div class="of-bands" role="group" aria-label="距中间价">${BANDS.map(b => `<button class="chip" data-of="band" data-v="${b}" aria-pressed="false">±${b}%</button>`).join('')}</div>
      <span class="num up"></span><span class="num down"></span></div>
    <div class="of-press-bar"><i class="b"></i><i class="a"></i>
      <span class="l num"></span><span class="r num"></span></div>`)
  const pTop = pEl.firstElementChild!, pBar = pEl.lastElementChild!
  pTop.querySelectorAll('[data-of="band"]').forEach(c => patchAttr(c, 'aria-pressed', String(Number((c as HTMLElement).dataset.v) === band)))
  patchText(pTop.children[1], `买 ${unitAmt(t.bid, mid)}`); patchText(pTop.children[2], `卖 ${unitAmt(t.ask, mid)}`)
  patchAttr(pBar, 'data-tip', `中间价 ±${band}% 以内各家所有簿的买卖挂单名义`)
  patchStyle(pBar.children[0], 'width', `${(share * 100).toFixed(1)}%`)
  patchText(pBar.children[2], `${(share * 100).toFixed(0)}%`); patchText(pBar.children[3], `${((1 - share) * 100).toFixed(0)}%`)
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
  exs.sort((a, b) => (EXCHANGE_CH[a] ?? 99) - (EXCHANGE_CH[b] ?? 99))
  let maxSide = 0
  for (const c of cells.values()) maxSide = Math.max(maxSide, c.bid, c.ask)
  maxSide ||= 1
  patchStyle(vEl, 'grid-template-columns', `56px repeat(${exs.length}, minmax(0,1fr))`)
  // 各家格子：哪几家 × 哪几种产品（结构）变了才重建，每帧只改条宽、金额与悬停说明
  const vKey = exs.join(',') + '|' + prods.map(p => p + ':' + exs.map(e => cells.has(e + '|' + p) ? 1 : 0).join('')).join(',')
  patchShell(vEl, vKey, `<span></span>${exs.map(e => `<span class="of-vh">${exName(e)}</span>`).join('')}` + prods.map(p =>
    `<span class="of-vp">${PRODUCT_SHORT[p]}</span>` + exs.map(e => cells.has(e + '|' + p)
      ? `<span class="of-vc" data-vc="${e}|${p}"><i class="b"></i><i class="a"></i><em class="num"></em></span>`
      : '<span class="of-vc none faint">—</span>').join('')).join(''))
  vEl.querySelectorAll<HTMLElement>('[data-vc]').forEach(span => {
    const c = cells.get(span.dataset.vc || ''); if (!c) return
    const [e, p] = (span.dataset.vc || '').split('|') as [string, Product]
    patchAttr(span, 'data-tip', `${venueName(exName(e), p)}：买 ${amt(c.bid)} · 卖 ${amt(c.ask)}`)
    patchStyle(span.children[0], 'width', `${(c.bid / maxSide * 50).toFixed(1)}%`)
    patchStyle(span.children[1], 'width', `${(c.ask / maxSide * 50).toFixed(1)}%`)
    patchText(span.children[2], amt(c.bid + c.ask))
  })
  // 分档盘口：买左卖右，各 8 档
  const step = fine.step
  const k = bookK(fine)
  const sb = steppedBook(fine, k, bookLevels(bEl))
  const d = decFor(step * k, OF.api?.dec(OF.feed!.symbol) ?? 2)
  const maxOne = Math.max(1, ...sb.bids.map(r => r.usd), ...sb.asks.map(r => r.usd))
  const maxCum = Math.max(1, sb.bids[sb.bids.length - 1]?.cum ?? 0, sb.asks[sb.asks.length - 1]?.cum ?? 0)
  const coin = OF.prefs.bookUnit === 'coin'
  const row = (r: { price: number; usd: number; cum: number; qty: number }, side: 'b' | 'a'): string =>
    `<div class="of-br ${side}"><i class="c" style="width:${(r.cum / maxCum * 100).toFixed(1)}%"></i><i class="o" style="width:${(r.usd / maxOne * 100).toFixed(1)}%"></i>
      <span class="p num">${px(r.price, d)}</span><span class="v num">${r.usd > 0 ? (coin ? amt(r.qty) : amt(r.usd)) : ''}</span><span class="s num faint">${coin ? amt(r.cum / Math.max(r.price, 1e-12)) : amt(r.cum)}</span></div>`
  // 分档盘口的行没有可点、可悬停的东西（不挂悬停说明），整块写不碍事；写之前清掉外壳记号，等待态回来时能重建
  patchShell(bEl, '#book', '')
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
  patchText(n, live.length ? `${live.length} 单` : '')
  const wait = (msg: string): void => { const h = `<div class="of-wait faint">${msg}</div>`; patchShell(box, h, h) }
  if (!OF.feed) { wait(feedIdleText()); return }
  if (!live.length) { wait(OF.snap?.phase === 'ready' || OF.snap?.phase == null ? '现在没有达到门槛的挂单' : '正在接盘口…'); return }
  const dec = decFor(OF.feed.model.scheme?.step ?? 0, OF.api?.dec(OF.feed.symbol) ?? 2)
  const now = Date.now()
  const max = live[0].notional
  // 只放得下的几行，不出滚动条（全部在抽屉里）
  const fit = Math.max(1, Math.floor(((box.clientHeight || 6 * WALL_ROW + 4) - 4) / WALL_ROW)) // 扣掉底边 4
  // 行按位置复用、每帧只改字与条宽（「挂了多久」每帧都变，整块重写会把指针下 / 键盘焦点所在的那一行换掉，点不上）
  const shown = live.slice(0, fit)
  rowPool(box, shown.length, `<div class="of-wall" tabindex="0" role="button"><i class="bar"></i><span class="sd"></span><span class="vn"><i class="sw"></i><b></b></span><span class="p num"></span><span class="v num"></span><span class="t num faint"></span></div>`)
    .forEach((row, k) => {
      const o = shown[k], id = orderId(o), bid = o.side === 'bid'
      patchClass(row, `of-wall${OF.highlight === id ? ' sel' : ''}`)
      patchAttr(row, 'data-wall', id)
      patchAttr(row, 'aria-label', `${bid ? '买' : '卖'} ${px(o.price, dec)} ${amt(o.notional)}`)
      const [bar, sd, vn, p, v, t] = Array.from(row.children)
      patchStyle(bar, 'width', `${(o.notional / max * 100).toFixed(1)}%`); patchStyle(bar, 'background', bandColor(o.product, o.side, 0.14))
      patchClass(sd, `sd ${bid ? 'up' : 'down'}`); patchText(sd, bid ? '买' : '卖')
      patchStyle(vn.firstElementChild, 'background', productColor(o.product, document.documentElement.dataset.theme === 'dark')); patchText(vn.lastElementChild, venueName(exName(o.exchange), o.product))
      patchText(p, px(o.price, dec)); patchText(v, amt(o.notional)); patchText(t, durShort(now - o.firstSeenMs))
    })
}

function updateAlerts(): void {
  const el = root?.querySelector<HTMLElement>('.of-w-alerts')
  if (!el || el.classList.contains('collapsed')) return
  const a = OF.api?.activeChart()
  const box = el.querySelector<HTMLElement>('#ofAlerts')!
  if (!a || !OF.api) { box.innerHTML = ''; return }
  const list = OF.api.alertsFor(a.symbol)
  const html = list.length ? list.map(x => `<div class="of-al"><span class="num">${esc(OF.api!.alertDesc(x))}</span><button class="ibtn xs" data-of-del="${esc(x.id)}" aria-label="删除提醒" data-tip="删除">${I('trash', 'icon-16')}</button></div>`).join('')
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
/** 每行的顶（多一个 = 最后一行的底） */
let tapeYs: number[] = []

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
  const rows0 = tapePaused ?? OF.tape.visible(tapeMin(), Math.max(1, Math.ceil(H / TAPE_ROW_SMALL)))
  if (!OF.feed) { tapeShown = []; tapeYs = []; hint(c, W, H, text3, feedIdleText('打开指标「主力订单流」后显示各家合并成交')); return }
  if (!rows0.length) { tapeShown = []; tapeYs = []; hint(c, W, H, text3, `还没有 ≥ ${amt(tapeMin())} 的成交`); return }
  const big = OF.bigTrade || Infinity
  const base = OF.bigTrade > 0 ? OF.bigTrade * 5 : 0
  // 行高不等：大额成交（≥ 门槛 ÷ 5）28、其余 20；放得下几行就画几行
  const rows: TapeRow[] = [], ys: number[] = []
  let yy = 0
  for (const r of rows0) { const h = tapeRowH(r.usd, big); if (yy + h > H) break; rows.push(r); ys.push(yy); yy += h }
  ys.push(yy)
  tapeShown = rows; tapeYs = ys
  const dec = OF.feed ? decFor(OF.feed.model.scheme?.step ?? 0, OF.api?.dec(OF.feed.symbol) ?? 2) : 2
  const coin = OF.prefs.bookUnit === 'coin'
  // 列：时间 12 · 交易所 70 · 方向块 150（宽 ≥ 394 才有）· 价格右对齐 W−132 · bps 小标右对齐 W−80 · 金额右对齐 W−12
  const showSide = W >= 394
  const pxR = W - 132, bpsR = W - 80
  c.textBaseline = 'middle'
  for (let i = 0; i < rows.length; i++) {
    const r = rows[i], y = ys[i], h = ys[i + 1] - y, cy = y + h / 2
    const isBig = r.usd >= big
    const col = r.side === 'buy' ? up : down
    // 底色浓淡 = 金额 ÷ 门槛（0.04–0.35），一眼看出哪几笔是大的
    c.fillStyle = hexA(col, tapeRowAlpha(r.usd, base)); c.fillRect(0, y, W, h - 1)
    if (i === tapeHover) { c.fillStyle = hexA(text1, 0.06); c.fillRect(0, y, W, h - 1) }
    c.font = canvasFont(12, 400)
    c.fillStyle = text3; c.textAlign = 'left'; c.fillText(hms(r.t), 12, cy)
    c.fillStyle = text1; c.fillText(venueName(exName(r.exchange), r.product), 70, cy)
    if (showSide) {
      c.fillStyle = col
      c.beginPath(); c.roundRect?.(150, cy - 8, 28, 16, 4); if (!c.roundRect) c.rect(150, cy - 8, 28, 16); c.fill()
      c.fillStyle = '#fff'; c.textAlign = 'center'; c.font = canvasFont(11, 600); c.fillText(r.side === 'buy' ? '买' : '卖', 164, cy)
    }
    c.font = canvasFont(isBig ? 13 : 12, isBig ? 650 : 400)
    c.textAlign = 'right'; c.fillStyle = r.side === 'buy' ? upT : downT; c.fillText(px(r.price, dec), pxR, cy)
    const bt = bpsText(r.bps)
    if (bt) {
      c.font = canvasFont(11, 500)
      const tw = c.measureText(bt).width + 8, bc = r.bps! > 0 ? up : down
      c.fillStyle = hexA(bc, 0.14)
      c.beginPath(); c.roundRect?.(bpsR - tw, cy - 8, tw, 16, 4); if (!c.roundRect) c.rect(bpsR - tw, cy - 8, tw, 16); c.fill()
      c.fillStyle = r.bps! > 0 ? upT : downT; c.textAlign = 'center'; c.fillText(bt, bpsR - tw / 2, cy)
    }
    c.font = canvasFont(isBig ? 13 : 12, isBig ? 650 : 400)
    c.textAlign = 'right'; c.fillStyle = text1
    c.fillText((coin ? amt(r.qty) : amt(r.usd)) + (r.n > 1 ? ` ×${r.n}` : ''), W - 12, cy)
  }
  void hover
}

function hint(c: CanvasRenderingContext2D, W: number, H: number, color: string, t: string): void {
  c.font = canvasFont(12); c.fillStyle = color; c.textAlign = 'center'; c.textBaseline = 'middle'
  c.fillText(t, W / 2, Math.min(H / 2, 48))
}

/** 行高不等：按累计的行顶找第几行 */
function tapeRowAt(y: number): number {
  for (let i = 0; i < tapeShown.length; i++) if (y >= tapeYs[i] && y < tapeYs[i + 1]) return i
  return -1
}
function onTapeHover(e: MouseEvent): void {
  const i = tapeRowAt(e.offsetY)
  const r = i >= 0 ? tapeShown[i] : undefined
  if (i !== tapeHover) { tapeHover = r ? i : -1; tapeDirty = true; scheduleTape() }
  if (tapeCv) {
    tapeCv.style.cursor = r ? 'pointer' : ''
    tapeCv.dataset.tip = r ? `${venueName(exName(r.exchange), r.product)} ${r.side === 'buy' ? '主动买' : '主动卖'} ${amt(r.usd)}${r.n > 1 ? `（1 秒内同价 ${r.n} 笔并成一行）` : ''}${bpsText(r.bps) ? ` · 比这家上一笔 ${bpsText(r.bps)} bps` : ''} · 点一下在图上定位` : ''
  }
}
function onTapeClick(e: MouseEvent): void {
  const r = tapeShown[tapeRowAt(e.offsetY)]
  if (!r) return
  const a = OF.api?.activeChart()
  a?.chart.centerOn(r.t, r.price)
}

/** 换品种：成交带清空、暂停取消。 */
/** 诊断（回归脚本用）：成交流当前画出来的每一行的高、bps 小标、底色浓度 */
export function tapeDebug(): { h: number; bps: string | null; alpha: number; usd: number }[] {
  const base = OF.bigTrade > 0 ? OF.bigTrade * 5 : 0
  return tapeShown.map((r, i) => ({ h: tapeYs[i + 1] - tapeYs[i], bps: bpsText(r.bps), alpha: +tapeRowAlpha(r.usd, base).toFixed(3), usd: Math.round(r.usd) }))
}

export function resetTape(): void { tapePaused = null; tapeHover = -1; tapeDirty = true; scheduleTape() }

/** 大单对象在侧栏大单列表里高亮（抽屉 / 图上点过来时）。 */
export function markWall(_o: BigOrder | null): void { updateWalls() }
