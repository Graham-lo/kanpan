/* Hkline Web · 主力订单流 · 底部抽屉：大单列表（设计稿 2.6）
 *
 * 图表区下方 280 px。列：首见 / 结束 / 存活 / 方向 / 交易所 / 产品 / 价位 / 峰值名义 / 累计成交 / 结局，
 * 点表头排序；上面一排筛选胶囊就是那六个显示开关（和图上的大单带同一套）。
 * 数据 = 本机模型里的大单（服务端历史已经并进模型并去重）。行是虚拟滚动（28 px 一行），几万行也不卡。
 * 点一行：图挪到那条大单带的中间并高亮；图上点一条带：抽屉滚到那一行。
 */
import { st, save } from '../app/store'
import { I, esc } from '../ui/dom'
import { shows, type Display } from './settings'
import { exName, outcomeText, PRODUCT_SHORT } from './aggregate'
import { orderId, type BigOrder } from './types'
import { OF, savePrefs, amt, mdhm, hms, durShort, decFor, px, peak, bandColor, type DrawerKey } from './state'

const ROW = 28
const COLS: [DrawerKey, string, string][] = [
  ['first', '首见', 'l'], ['end', '结束', 'l'], ['age', '存活', 'r'], ['side', '方向', 'c'], ['exchange', '交易所', 'l'], ['product', '产品', 'l'],
  ['price', '价位', 'r'], ['peak', '峰值名义', 'r'], ['filled', '累计成交', 'r'], ['outcome', '结局', 'l'],
]
const CHIPS: [keyof Display, string][] = [
  ['spot', '现货'], ['contract', '合约'], ['filledBid', '买单成交'], ['filledAsk', '卖单成交'], ['cancelledBid', '买单撤销'], ['cancelledAsk', '卖单撤销'],
]

let slot: HTMLElement | null = null
let body: HTMLElement | null = null
let list: BigOrder[] = []
let seenVersion = -1
let lastSig = ''

export function mountDrawer(el: HTMLElement): void {
  slot = el
  el.innerHTML = `<div class="of-dr-head">
      <b>大单</b><span class="faint num" id="ofDrN"></span>
      <div class="of-dr-chips" role="group" aria-label="显示哪些大单">${CHIPS.map(([k, l]) => `<button class="chip" data-chip="${k}" aria-pressed="${OF.prefs.display[k]}">${l}</button>`).join('')}</div>
      <span class="faint of-dr-note" id="ofDrNote"></span>
      <button class="ibtn xs" id="ofDrClose" aria-label="收起抽屉" data-tip="收起">${I('close', 'icon-16')}</button>
    </div>
    <div class="of-dr-th" role="row">${COLS.map(([k, l, a]) => `<span class="${a} sortable" data-sort="${k}" role="columnheader">${l}<i class="arrow"></i></span>`).join('')}</div>
    <div class="scroll of-dr-body" id="ofDrBody" role="grid" aria-label="大单列表"><div class="of-dr-space"></div><div class="of-dr-rows"></div></div>`
  body = el.querySelector('#ofDrBody')
  el.querySelector<HTMLElement>('#ofDrClose')!.onclick = () => { st.slots.drawer = false; save(); OF.api?.layoutSlots() }
  el.addEventListener('click', onClick)
  body!.addEventListener('scroll', () => { paint(); nearBottom() }, { passive: true })
  // 列表不满一屏或已经在底：滚轮往下时 scroll 事件不来，也要能要下一页。
  body!.addEventListener('wheel', e => { if (e.deltaY > 0) nearBottom() }, { passive: true })
  seenVersion = -1; lastSig = ''
  updateDrawer(true)
}

/** 滚到离底不到四行：服务端还有更早的就往前取一页（6 小时、最多 5000 条已结束的），并进模型后列表自己长出来。 */
function nearBottom(): void {
  if (!body || !OF.feed?.hasOlder) return
  if (body.scrollTop + body.clientHeight >= body.scrollHeight - ROW * 4) OF.feed.loadOlder()
}

export function drawerVisible(): boolean { return !!slot && st.slots.drawer && !slot.hidden && slot.isConnected }

function onClick(e: MouseEvent): void {
  const t = e.target as HTMLElement
  const chip = t.closest<HTMLElement>('[data-chip]')
  if (chip) {
    const k = chip.dataset.chip as keyof Display
    OF.prefs.display[k] = !OF.prefs.display[k]
    chip.setAttribute('aria-pressed', String(OF.prefs.display[k]))
    savePrefs(); OF.version++
    OF.api?.charts().forEach(c => { c.chart.dirty = true })
    updateDrawer(true); return
  }
  const th = t.closest<HTMLElement>('[data-sort]')
  if (th) {
    const k = th.dataset.sort as DrawerKey
    const s = OF.prefs.sort
    OF.prefs.sort = s.key === k ? { key: k, dir: s.dir === 1 ? -1 : 1 } : { key: k, dir: k === 'first' || k === 'end' || k === 'peak' || k === 'filled' || k === 'age' ? -1 : 1 }
    savePrefs(); updateDrawer(true); return
  }
  const row = t.closest<HTMLElement>('[data-id]')
  if (row) {
    const o = list.find(x => orderId(x) === row.dataset.id)
    if (o) OF.focus?.(o)
  }
}

const endOf = (o: BigOrder, now: number): number => o.endMs ?? now
function key(o: BigOrder, k: DrawerKey, now: number): number | string {
  switch (k) {
    case 'first': return o.firstSeenMs
    case 'end': return o.endMs ?? Infinity
    case 'age': return endOf(o, now) - o.firstSeenMs
    case 'side': return o.side
    case 'exchange': return o.exchange
    case 'product': return o.product
    case 'price': return o.price
    case 'peak': return peak(o, orderId(o))
    case 'filled': return o.filledNotional
    case 'outcome': return o.status
  }
}

/** 订单流出了一帧（或筛选、排序变了）：重排并重画可见的那几行。 */
export function updateDrawer(force = false): void {
  if (!drawerVisible() || !body) return
  const snap = OF.snap
  const n = slot!.querySelector<HTMLElement>('#ofDrN')!
  const note = slot!.querySelector<HTMLElement>('#ofDrNote')!
  if (!OF.feed || !snap) {
    list = []
    n.textContent = ''
    note.textContent = OF.feed ? '正在接盘口…' : '打开指标「主力订单流」后显示'
    paint(); return
  }
  if (!force && seenVersion === OF.version) return
  seenVersion = OF.version
  const now = Date.now()
  const d = OF.prefs.display
  const rows = snap.orders.filter(o => shows(d, o))
  const { key: k, dir } = OF.prefs.sort
  rows.sort((a, b) => {
    const x = key(a, k, now), y = key(b, k, now)
    const c = typeof x === 'number' && typeof y === 'number' ? x - y : String(x).localeCompare(String(y))
    return c !== 0 ? c * dir : b.firstSeenMs - a.firstSeenMs
  })
  list = rows
  const live = rows.filter(o => o.status === 'live').length
  n.textContent = `${rows.length} 单 · 挂着 ${live}`
  note.textContent = OF.feed.historyState === 'down' ? '服务端历史暂时取不到，只显示这次打开以来的' : ''
  slot!.querySelectorAll<HTMLElement>('[data-sort]').forEach(th => {
    const on = th.dataset.sort === k
    th.setAttribute('aria-sort', on ? (dir === 1 ? 'ascending' : 'descending') : 'none')
    th.querySelector('.arrow')!.textContent = on ? (dir === 1 ? '↑' : '↓') : ''
  })
  paint()
}

function paint(): void {
  if (!body) return
  const space = body.querySelector<HTMLElement>('.of-dr-space')!, box = body.querySelector<HTMLElement>('.of-dr-rows')!
  space.style.height = `${list.length * ROW}px`
  if (!list.length) {
    const msg = OF.feed && OF.snap ? '没有符合筛选的大单' : ''
    const html = msg ? `<div class="of-wait faint">${msg}</div>` : ''
    if (box.dataset.sig !== html) { box.innerHTML = html; box.dataset.sig = html }
    box.style.transform = ''
    return
  }
  const top = body.scrollTop, h = body.clientHeight
  const i0 = Math.max(0, Math.floor(top / ROW) - 4), i1 = Math.min(list.length, Math.ceil((top + h) / ROW) + 4)
  const now = Date.now()
  const dec = decFor(OF.feed?.model.scheme?.step ?? 0, OF.feed ? OF.api?.dec(OF.feed.symbol) ?? 2 : 2)
  const today = mdhm(now).slice(0, 5)
  const t = (ms: number): string => { const s = mdhm(ms); return s.slice(0, 5) === today ? hms(ms) : s }
  let html = ''
  for (let i = i0; i < i1; i++) {
    const o = list[i], id = orderId(o)
    const live = o.status === 'live'
    html += `<div class="of-dr-row ${OF.highlight === id ? 'sel' : ''} ${live ? 'live' : ''}" data-id="${esc(id)}" role="row" tabindex="-1">
      <span class="l num">${t(o.firstSeenMs)}</span>
      <span class="l num ${live ? 'faint' : ''}">${live ? '挂着' : t(o.endMs ?? now)}</span>
      <span class="r num">${durShort(endOf(o, now) - o.firstSeenMs)}</span>
      <span class="c"><em class="of-side ${o.side === 'bid' ? 'up' : 'down'}">${o.side === 'bid' ? '买' : '卖'}</em></span>
      <span class="l">${exName(o.exchange)}</span>
      <span class="l"><i class="sw" style="background:${bandColor(o.product, o.side, 1)}"></i>${PRODUCT_SHORT[o.product]}</span>
      <span class="r num">${px(o.price, dec)}</span>
      <span class="r num">${amt(peak(o, id))}</span>
      <span class="r num">${o.filledNotional > 0 ? amt(o.filledNotional) : '—'}</span>
      <span class="l">${outcomeText(o)}</span></div>`
  }
  const sig = `${i0}|${i1}|${html.length}|${OF.version}|${OF.highlight}`
  box.style.transform = `translateY(${i0 * ROW}px)`
  if (box.dataset.sig !== sig) { box.innerHTML = html; box.dataset.sig = sig }
  lastSig = sig
}

/** 图上点了一条带：打开抽屉、滚到那一行。 */
export function revealInDrawer(id: string): void {
  if (!st.slots.drawer) { st.slots.drawer = true; save(); OF.api?.layoutSlots() }
  updateDrawer(true)
  let i = list.findIndex(o => orderId(o) === id)
  if (i < 0) {
    // 被筛选藏起来了：把它所属的那个开关打开
    const o = OF.snap?.orders.find(x => orderId(x) === id)
    if (!o) return
    const d = OF.prefs.display
    if (o.product === 'spot') d.spot = true; else d.contract = true
    if (o.status === 'filled') d[o.side === 'bid' ? 'filledBid' : 'filledAsk'] = true
    if (o.status === 'cancelled') d[o.side === 'bid' ? 'cancelledBid' : 'cancelledAsk'] = true
    savePrefs()
    slot?.querySelectorAll<HTMLElement>('[data-chip]').forEach(c => c.setAttribute('aria-pressed', String(d[c.dataset.chip as keyof Display])))
    updateDrawer(true)
    i = list.findIndex(x => orderId(x) === id)
    if (i < 0) return
  }
  if (!body) return
  const top = i * ROW, h = body.clientHeight
  if (top < body.scrollTop || top + ROW > body.scrollTop + h) body.scrollTop = Math.max(0, top - h / 2 + ROW / 2)
  paint()
}

export const drawerSig = (): string => lastSig
