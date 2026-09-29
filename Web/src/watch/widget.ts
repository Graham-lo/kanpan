/* Hkline Web · 侧栏「自选」小部件
 *
 * 图表页只留挂接点（installWatch / widgetWatch / mountWatch / watchClick / patchWatchRow / takeWatchUndo），
 * 列表的渲染、键盘、右键、拖动排序、宽列数据都在这里。
 *
 * 列固定：品种 · 最新价 · 涨跌幅 · 成交额；侧栏宽 ≥ 400 时再加 资金费 · 持仓额（不给列设置）。
 * 键盘（焦点在列表里时，带 ⌘ / Ctrl / Alt 的一律放给全局）：
 *   ↑ ↓ Home End  移动并在活动格打开（和全局 ↑ ↓ 一样「看到哪只图就是哪只」）
 *   ↵             在活动格打开光标这只
 *   Delete / ⌫    移出自选，光标落到下一行，⌘Z 撤销
 *   空格          收藏 / 取消（等于点星）；取消后这一行淡着留在原位，再按空格收回原位置，焦点离开列表才真正消失
 *   Esc           退出列表
 * 多图时头部下写「在第 N 格打开」，跟着活动格走；行的右键菜单同样写第几格。
 */
import { st, save } from '../app/store'
import { S, REST, j, TABS, type Kind } from '../market'
import { $, $$, I, esc, tgt } from '../ui/dom'
import { toast, menu, menuFrom } from '../ui/overlay'
import { sym, pctText, cls, priceText, badge } from '../ui/common'
import { fmtCompact } from '../util/format'

export interface WatchDeps {
  openSymbol(k: string): void
  renderPanel(): void
  refreshStreams(): void
  openSearch(): void
  /** 活动格当前的品种 */
  current(): string
  /** 活动格是第几格（0 起） */
  activeIndex(): number
  /** 当前布局有几格 */
  cellCount(): number
  collapsed(): boolean
  collapseBtn(c: boolean): string
}
let D: WatchDeps

/** 宽列出现的侧栏宽度 */
export const WIDE_AT = 400
const OI_TTL = 60e3

const kb = { on: false, cursor: '' }
let ghost: { k: string; i: number; tab: Kind } | null = null
let wide = false
let undo: (() => void) | null = null

/** 全局 ⌘Z 先问这里要不要撤销自选的改动 */
export function takeWatchUndo(): (() => void) | null { const u = undo; undo = null; return u }

const panelEl = (): HTMLElement | null => document.getElementById('sidePanel')
const panelWide = (): boolean => (panelEl()?.getBoundingClientRect().width || 0) >= WIDE_AT
const tabName = (k: Kind): string => TABS.find(x => x[0] === k)?.[1] || ''
const codeOf = (k: string): string => sym(k)?.code || k
const targetLabel = (): string => D.cellCount() > 1 ? `在第 ${D.activeIndex() + 1} 格打开` : '在图上打开'

/** 列表里要画的行：自选 + 空格取消后淡着留下的那一行 */
function rows(): string[] {
  const list = [...st.watch[st.watchTab]]
  if (ghost && ghost.tab === st.watchTab && !list.includes(ghost.k)) list.splice(Math.min(ghost.i, list.length), 0, ghost.k)
  return list
}

export function installWatch(d: WatchDeps): void {
  D = d
  // 侧栏拖宽 / 拖窄跨过 400 时重画，加减那两列
  const el = panelEl()
  if (el) new ResizeObserver(() => {
    const w = panelWide()
    if (w !== wide && st.panel === 'watch') { wide = w; D.renderPanel() }
  }).observe(el)
  // 宽列的慢数：资金费一分钟刷一次全表，持仓额按需取、一分钟过期
  setInterval(() => {
    if (!wide || st.panel !== 'watch' || st.page !== 'chart' || document.visibilityState === 'hidden') return
    void refreshFunding(); void refreshOI(st.watch[st.watchTab])
  }, 61e3)
}

// ------------------------------------------------------------ 渲染
export function widgetWatch(): string {
  wide = panelWide()
  const cur = D.current()
  const list = rows()
  const empty = !S.symbols.size
    ? `<div class="empty">${I('wifiOff', 'icon-24')}<div>${S.live === false ? (S.limited ? '币安限流了，冷却后自动重试' : '连不上币安合约接口') : '正在取行情…'}</div></div>`
    : `<div class="empty">${I('star', 'icon-24')}<div>这一类还没有自选</div><button class="btn secondary sm" style="margin-top:12px" id="wAdd2">搜索品种</button></div>`
  const c = D.collapsed()
  if (!list.includes(kb.cursor)) kb.cursor = list.includes(cur) ? cur : list[0] || ''
  const multi = D.cellCount() > 1
  if (wide && list.length) { void refreshOI(list); void refreshFunding() }
  // 标题、分类、添加、更多、收起并在一行（36 px），省下的高度给列表
  return `<div class="widget widget-watch ${c ? 'collapsed' : ''} ${wide ? 'wv-wide' : ''}"><div class="sp-head wv-head"><h3>自选</h3>
      <div class="wv-tabs" role="tablist">${TABS.map(([k, l]) => `<button class="chip" role="tab" data-tab="${k}" aria-pressed="${st.watchTab === k}">${l} ${st.watch[k].length}</button>`).join('')}</div>
      <button class="ibtn xs" id="wAdd" aria-label="添加品种" data-tip="添加品种" data-kbd="⌘ K">${I('plus', 'icon-16')}</button>
      <button class="ibtn xs" id="wMore" aria-label="更多" data-tip="更多">${I('more', 'icon-16')}</button>
      ${D.collapseBtn(c)}</div>
    ${multi ? `<div class="wv-target" id="wTarget">${I('layout4', 'icon-16')}<span>${targetLabel()}</span><span class="sc">↵</span></div>` : ''}
    <div class="scroll no-bar wv-body">
      ${list.length && S.symbols.size ? `<table class="tbl" id="wTbl" role="grid" aria-label="自选"><thead><tr><th>品种</th><th>最新价</th><th>涨跌幅</th><th>成交额</th>${wide ? '<th>资金费</th><th>持仓额</th>' : ''}</tr></thead>
      <tbody>${list.map(k => watchRow(k, cur)).join('')}</tbody></table>` : empty}
    </div></div>`
}

const NO_PERP = '该品种没有永续'
function frCell(k: string): string {
  const s = sym(k)
  return s?.fr == null ? `<td class="num faint" data-f="fr" data-tip="${NO_PERP}">—</td>` : `<td class="num ${cls(s.fr)}" data-f="fr">${frText(s.fr)}</td>`
}
function oiCell(k: string): string {
  const v = oiCache.get(k)?.v
  return v == null ? `<td class="num faint" data-f="oi"${oiCache.has(k) ? ` data-tip="${NO_PERP}"` : ''}>—</td>` : `<td class="num muted" data-f="oi">${fmtCompact(v)}</td>`
}
const frText = (fr: number): string => (fr * 100).toFixed(4) + '%'

function watchRow(k: string, cur: string): string {
  const s = sym(k), g = ghost?.k === k
  return `<tr data-sym="${k}" draggable="${!g}" tabindex="${k === kb.cursor ? 0 : -1}" class="${k === cur ? 'sel' : ''} ${g ? 'wv-ghost' : ''}" aria-selected="${k === cur}">
    <td><div class="sym">${badge(s)}<b>${esc(s?.code || k)}</b><span class="cn">${esc(s?.cn || '')}</span>${g ? `<span class="wv-off" data-tip="已移出自选，按空格收回">${I('starOff', 'icon-16')}</span>` : ''}</div></td>
    <td class="num price-live" data-f="price">${priceText(s)}</td>
    <td class="num ${cls(s?.pct)} price-live" data-f="pct">${pctText(s?.pct)}</td>
    <td class="num muted" data-f="vol">${fmtCompact(s?.vol)}</td>${wide ? frCell(k) + oiCell(k) : ''}</tr>`
}

/** 渲染后挂事件、把键盘焦点放回光标那一行 */
export function mountWatch(el: HTMLElement): void {
  const tbl = $('#wTbl', el)
  if (!tbl) return
  bindDrag(tbl)
  tbl.addEventListener('keydown', onKey)
  tbl.addEventListener('focusin', e => {
    const tr = tgt(e).closest<HTMLElement>('tr[data-sym]'); if (!tr) return
    kb.on = true; setCursor(tr.dataset.sym || '', false)
  })
  tbl.addEventListener('focusout', () => setTimeout(() => {
    if ($('#wTbl')?.contains(document.activeElement)) return
    kb.on = false
    if (ghost) { ghost = null; if (st.panel === 'watch') D.renderPanel() }
  }))
  tbl.addEventListener('contextmenu', onContext)
  const a = document.activeElement
  if (kb.on && (!a || a === document.body || panelEl()?.contains(a))) {
    const tr = $<HTMLElement>(`tr[data-sym="${kb.cursor}"]`, tbl)
    if (tr) { tr.focus({ preventScroll: true }); tr.scrollIntoView({ block: 'nearest' }) }
  }
}

function setCursor(k: string, focus: boolean): void {
  kb.cursor = k
  const tbl = $('#wTbl'); if (!tbl) return
  $$<HTMLElement>('tbody tr[data-sym]', tbl).forEach(r => { r.tabIndex = r.dataset.sym === k ? 0 : -1 })
  if (focus) { const tr = $<HTMLElement>(`tr[data-sym="${k}"]`, tbl); if (tr) { tr.focus({ preventScroll: true }); tr.scrollIntoView({ block: 'nearest' }) } }
}

// ------------------------------------------------------------ 键盘
function onKey(e: KeyboardEvent): void {
  if (e.metaKey || e.ctrlKey || e.altKey) return
  const tbl = e.currentTarget as HTMLElement
  const tr = tgt(e).closest<HTMLElement>('tr[data-sym]'); if (!tr) return
  const list = $$<HTMLElement>('tbody tr[data-sym]', tbl).map(r => r.dataset.sym || '')
  const k = tr.dataset.sym || '', i = list.indexOf(k)
  const go = (n: number) => { const to = list[Math.max(0, Math.min(list.length - 1, n))]; if (!to) return; setCursor(to, true); D.openSymbol(to) }
  switch (e.key) {
    case 'ArrowDown': go(i + 1); break
    case 'ArrowUp': go(i - 1); break
    case 'Home': go(0); break
    case 'End': go(list.length - 1); break
    case 'Enter': D.openSymbol(k); break
    case 'Delete': case 'Backspace': removeRow(k, list); break
    case ' ': toggleRow(k); break
    case 'Escape': kb.on = false; tr.blur(); break
    default: return
  }
  e.preventDefault(); e.stopPropagation()
}

/** 移出自选（⌘Z 撤销）；光标落到下一行，不自动打开它 */
function removeRow(k: string, list: string[]): void {
  if (ghost?.k === k) { const i = list.indexOf(k); ghost = null; kb.cursor = list[i + 1] || list[i - 1] || ''; D.renderPanel(); return }
  const tab = st.watchTab, wl = st.watch[tab], idx = wl.indexOf(k); if (idx < 0) return
  const i = list.indexOf(k)
  kb.cursor = list[i + 1] || list[i - 1] || ''
  wl.splice(idx, 1); save(); D.renderPanel(); D.refreshStreams()
  undo = () => {
    const l = st.watch[tab]; if (!l.includes(k)) l.splice(Math.min(idx, l.length), 0, k)
    kb.cursor = k; save(); D.renderPanel(); D.refreshStreams()
  }
  toast(`已移出自选 ${codeOf(k)}`, '⌘Z 撤销', 'starOff', 2400)
}

/** 空格：收藏 / 取消，等于点星；取消后留一行淡的在原位，焦点不离开就还能收回 */
function toggleRow(k: string): void {
  if (ghost?.k === k) {
    const l = st.watch[ghost.tab]; if (!l.includes(k)) l.splice(Math.min(ghost.i, l.length), 0, k)
    ghost = null; save(); D.renderPanel(); D.refreshStreams()
    toast(`已加回自选 ${codeOf(k)}`, '', 'star', 1800)
    return
  }
  const tab = st.watchTab, l = st.watch[tab], idx = l.indexOf(k); if (idx < 0) return
  l.splice(idx, 1); ghost = { k, i: idx, tab }
  save(); D.renderPanel(); D.refreshStreams()
  toast(`已从自选移除 ${codeOf(k)}`, '再按空格收回', 'starOff', 1800)
}

// ------------------------------------------------------------ 右键
function onContext(e: MouseEvent): void {
  const tr = tgt(e).closest<HTMLElement>('tr[data-sym]'); if (!tr) return
  e.preventDefault()
  const k = tr.dataset.sym || '', g = ghost?.k === k
  const list = rows()
  setCursor(k, false)
  menu([
    { header: codeOf(k) },
    { icon: D.cellCount() > 1 ? 'layout4' : 'candles', label: targetLabel(), sc: '↵', run: () => D.openSymbol(k) },
    g ? { icon: 'star', label: '加回自选', sc: '空格', run: () => toggleRow(k) }
      : { icon: 'starOff', label: '移出自选', sc: 'Delete', run: () => removeRow(k, list) },
  ], e.clientX, e.clientY, { width: 200 })
}

// ------------------------------------------------------------ 点击（图表页的面板点击先问这里）
export function watchClick(e: MouseEvent): boolean {
  const t = tgt(e)
  const tab = t.closest<HTMLElement>('.widget-watch [data-tab]')
  if (tab) { st.watchTab = tab.dataset.tab as Kind; ghost = null; save(); D.renderPanel(); D.refreshStreams(); return true }
  if (t.closest('#wAdd,#wAdd2')) { D.openSearch(); return true }
  const more = t.closest<HTMLElement>('#wMore')
  if (more) {
    menuFrom(more, [
      { icon: 'drag', label: '拖动行可以排序', disabled: true },
      { icon: 'list', label: '键盘：↑ ↓ 切换 · 空格 收藏 · Delete 移出', disabled: true },
      {
        icon: 'trash', label: `清空「${tabName(st.watchTab)}」自选`, disabled: !st.watch[st.watchTab].length, run: () => {
          const k = st.watchTab, bak = st.watch[k]; st.watch[k] = []; ghost = null; save(); D.renderPanel(); D.refreshStreams()
          undo = () => { st.watch[k] = bak; save(); D.renderPanel(); D.refreshStreams() }
          toast('已清空', '⌘Z 撤销', 'trash')
        },
      },
    ])
    return true
  }
  const tr = t.closest<HTMLElement>('#wTbl tr[data-sym]')
  if (tr) { kb.cursor = tr.dataset.sym || ''; D.openSymbol(kb.cursor); return true }
  return false
}

// ------------------------------------------------------------ 拖动排序
function bindDrag(tbl: HTMLElement): void {
  let from: HTMLElement | null = null
  const clear = () => $$('tr', tbl).forEach(r => r.classList.remove('drop-above', 'drop-below'))
  tbl.addEventListener('dragstart', e => { from = tgt(e).closest('tr'); from?.classList.add('dragging'); if (e.dataTransfer) e.dataTransfer.effectAllowed = 'move' })
  tbl.addEventListener('dragend', () => { from?.classList.remove('dragging'); clear() })
  tbl.addEventListener('dragover', e => {
    const tr = tgt(e).closest<HTMLElement>('tbody tr'); if (!tr || !from) return
    e.preventDefault(); clear()
    const r = tr.getBoundingClientRect(); tr.classList.add(e.clientY < r.top + r.height / 2 ? 'drop-above' : 'drop-below')
  })
  tbl.addEventListener('drop', e => {
    const tr = tgt(e).closest<HTMLElement>('tbody tr'); if (!tr || !from || tr === from) return
    e.preventDefault()
    const list = st.watch[st.watchTab], a = from.dataset.sym || ''
    if (!list.includes(a)) return
    list.splice(list.indexOf(a), 1)
    let i = list.indexOf(tr.dataset.sym || ''); if (i < 0) i = list.length; else if (tr.classList.contains('drop-below')) i++
    list.splice(i, 0, a); save(); D.renderPanel()
  })
}

// ------------------------------------------------------------ 推送来的数：只改那几格的字
/** dir：这一跳是涨（1）还是跌（-1）；价格文字闪一次涨跌色（150 ms） */
export function patchWatchRow(k: string, dir: number): void {
  const tr = $(`#wTbl tr[data-sym="${k}"]`), s = sym(k)
  if (!tr || !s) return
  const p = $('[data-f="price"]', tr), pc = $('[data-f="pct"]', tr), v = $('[data-f="vol"]', tr)
  if (p) {
    p.textContent = priceText(s)
    if (dir) { p.classList.remove('wv-flash-up', 'wv-flash-down'); void p.offsetWidth; p.classList.add(dir > 0 ? 'wv-flash-up' : 'wv-flash-down') }
  }
  if (pc) { pc.textContent = pctText(s.pct); pc.className = `num ${cls(s.pct)} price-live` }
  if (v) v.textContent = fmtCompact(s.vol)
}
function patchWide(): void {
  const tbl = $('#wTbl'); if (!tbl || !wide) return
  for (const tr of $$<HTMLElement>('tbody tr[data-sym]', tbl)) {
    const k = tr.dataset.sym || ''
    const f = $('[data-f="fr"]', tr), o = $('[data-f="oi"]', tr)
    if (f) f.outerHTML = frCell(k)
    if (o) o.outerHTML = oiCell(k)
  }
}

// ------------------------------------------------------------ 宽列数据
interface Premium { symbol: string; lastFundingRate: string; nextFundingTime: number }
let fundingAt = 0
/** 资金费：启动时 premiumIndex 取过一次，此后只有订了标记价流的那只在动；宽列出来时一分钟整表刷一次 */
async function refreshFunding(): Promise<void> {
  if (Date.now() - fundingAt < 60e3) return
  fundingAt = Date.now()
  try {
    const pi = await j<Premium[]>(`${REST}/fapi/v1/premiumIndex`)
    for (const p of pi) { const s = S.symbols.get(p.symbol); if (s) { s.fr = p.lastFundingRate === '' ? null : +p.lastFundingRate; if (p.nextFundingTime) s.nextFunding = p.nextFundingTime } }
    patchWide()
  } catch { fundingAt = 0 }
}

const oiCache = new Map<string, { v: number | null; t: number }>()
const oiInflight = new Set<string>()
/** 持仓额 = 未平仓合约数 × 最新价（和详情一致）；币安没有批量接口，逐只取，并发 4，一分钟过期 */
async function refreshOI(list: string[]): Promise<void> {
  const now = Date.now()
  const todo = list.filter(k => !oiInflight.has(k) && now - (oiCache.get(k)?.t || 0) >= OI_TTL)
  if (!todo.length) return
  todo.forEach(k => oiInflight.add(k))
  let next = 0
  const worker = async () => {
    while (next < todo.length) {
      const k = todo[next++]
      try {
        const r = await j<{ openInterest: string }>(`${REST}/fapi/v1/openInterest?symbol=${k}`)
        const px = S.symbols.get(k)?.price
        oiCache.set(k, { v: px && +r.openInterest > 0 ? +r.openInterest * px : null, t: Date.now() })
      } catch { oiCache.set(k, { v: null, t: Date.now() - OI_TTL + 10e3 }) }
      finally { oiInflight.delete(k) }
    }
  }
  await Promise.all([worker(), worker(), worker(), worker()])
  patchWide()
}
