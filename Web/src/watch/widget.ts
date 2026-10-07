/* Hkline Web · 侧栏「自选」小部件
 *
 * 图表页只留挂接点（installWatch / widgetWatch / mountWatch / watchClick / patchWatchRow / takeWatchUndo），
 * 列表的渲染、键盘、右键、拖动排序都在这里。
 *
 * 列固定三列：品种（只写代号）· 最新价 · 涨跌幅，不给列设置；2026-10-07 用户说中文名、成交额都没必要，
 * 侧栏拉宽时的资金费 · 持仓额两列一并去掉。
 * 键盘（焦点在列表里时，带 ⌘ / Ctrl / Alt 的一律放给全局）：
 *   ↑ ↓ Home End  移动并在活动格打开（和全局 ↑ ↓ 一样「看到哪只图就是哪只」）
 *   ↵             在活动格打开光标这只
 *   Delete / ⌫    移出自选，光标落到下一行，⌘Z 撤销
 *   空格          收藏 / 取消（等于点星）；取消后这一行淡着留在原位，再按空格收回原位置，焦点离开列表才真正消失
 *   Esc           退出列表
 * 多图时头部下写「在第 N 格打开」，跟着活动格走；行的右键菜单同样写第几格。
 */
import { st, save } from '../app/store'
import { S, TABS, baseOf, kindOfUnderlying, type Kind } from '../market'
import { $, $$, I, esc, tgt } from '../ui/dom'
import { toast, menu, menuFrom } from '../ui/overlay'
import { sym, pctText, cls, priceText, badge } from '../ui/common'
import { reorderWatch, undoClear, flashClass, FLASH_CLASSES, RowGate } from './logic'
import { onSession } from '../account/session'

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

const kb = { on: false, cursor: '' }
let ghost: { k: string; i: number; tab: Kind } | null = null
let undo: (() => void) | null = null

/** 全局 ⌘Z 先问这里要不要撤销自选的改动 */
export function takeWatchUndo(): (() => void) | null { const u = undo; undo = null; return u }

const panelEl = (): HTMLElement | null => document.getElementById('sidePanel')
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
  // 换了账号：上一个账号的 ⌘Z 撤销和淡行都不再作数（不然 ⌘Z 会把上个账号移出的品种塞进这个账号）
  onSession(() => { undo = null; ghost = null })
}

// ------------------------------------------------------------ 渲染
export function widgetWatch(): string {
  const cur = D.current()
  const list = rows()
  const empty = !S.symbols.size
    ? `<div class="empty">${I('wifiOff', 'icon-24')}<div>${S.live === false ? (S.limited ? '币安限流了，冷却后自动重试' : '连不上币安合约接口') : '正在取行情…'}</div></div>`
    : `<div class="empty">${I('star', 'icon-24')}<div>这一类还没有自选</div><button class="btn secondary sm" style="margin-top:12px" id="wAdd2">搜索品种</button></div>`
  const c = D.collapsed()
  if (!list.includes(kb.cursor)) kb.cursor = list.includes(cur) ? cur : list[0] || ''
  const multi = D.cellCount() > 1
  // 标题、分类、添加、更多、收起并在一行（36 px），省下的高度给列表
  return `<div class="widget widget-watch ${c ? 'collapsed' : ''}"><div class="sp-head wv-head"><h3>自选</h3>
      <div class="wv-tabs" role="tablist">${TABS.filter(([k]) => k !== 'idx' || st.watch.idx.length || st.watchTab === 'idx').map(([k, l]) => `<button class="chip" role="tab" data-tab="${k}" aria-pressed="${st.watchTab === k}">${l} ${st.watch[k].length}</button>`).join('')}</div>
      <button class="ibtn xs" id="wAdd" aria-label="添加品种" data-tip="添加品种" data-kbd="⌘ K">${I('plus', 'icon-16')}</button>
      <button class="ibtn xs" id="wMore" aria-label="更多" data-tip="更多">${I('more', 'icon-16')}</button>
      ${D.collapseBtn(c)}</div>
    ${multi ? `<div class="wv-target" id="wTarget">${I('layout4', 'icon-16')}<span>${targetLabel()}</span><span class="sc">↵</span></div>` : ''}
    <div class="scroll no-bar wv-body">
      ${list.length ? `<table class="tbl" id="wTbl" role="grid" aria-label="自选"><thead><tr><th>品种</th><th>最新价</th><th>涨跌幅</th></tr></thead>
      <tbody>${list.map(k => watchRow(k, cur)).join('')}</tbody></table>` : empty}
    </div></div>`
}

/** 品种表还没到（冷启动、本机也没留）：行先按本机自选的代号摆出来，徽标按代号猜、价格写「—」，表到了整张重画 */
function watchRow(k: string, cur: string): string {
  const s = sym(k), g = ghost?.k === k, base = baseOf(k)
  return `<tr data-sym="${k}" draggable="${!g}" tabindex="${k === kb.cursor ? 0 : -1}" class="${k === cur ? 'sel' : ''} ${g ? 'wv-ghost' : ''}" aria-selected="${k === cur}">
    <td><div class="sym">${badge(s ?? { base, kind: kindOfUnderlying(undefined, base) })}<b>${esc(s?.code || base)}</b>${g ? `<span class="wv-off" data-tip="已移出自选，按空格收回">${I('starOff', 'icon-16')}</span>` : ''}</div></td>
    <td class="num price-live" data-f="price">${priceText(s)}</td>
    <td class="num ${cls(s?.pct)} price-live" data-f="pct">${pctText(s?.pct)}</td></tr>`
}

// 只改看得见的行（RowGate）：观察器挂在列表的滚动区上，上下各多留 160 px，滚动时新露出的行已经是新价
const gate = new RowGate()
let rowIO: IntersectionObserver | null = null
/** 代号 → 这一行（每次画表时重建）：推送一来就按代号直接取，不再拿属性选择器扫整页——
 *  全市场每秒几百只在跳，不在自选里的那些原来每只都要白扫一遍文档 */
const rowEl = new Map<string, HTMLElement>()
/** 诊断用：看不见的行、欠着推送的行 */
export const watchGateStats = (): { hidden: number; owed: number } => gate.stats()
function observeRows(tbl: HTMLElement, root: HTMLElement | null): void {
  rowIO?.disconnect(); rowIO = null
  gate.reset(); rowEl.clear()
  for (const tr of $$<HTMLElement>('tbody tr[data-sym]', tbl)) rowEl.set(tr.dataset.sym || '', tr)
  if (typeof IntersectionObserver === 'undefined') return
  rowIO = new IntersectionObserver(es => {
    for (const e of es) {
      const k = (e.target as HTMLElement).dataset.sym || ''
      if (gate.seen(k, e.isIntersecting)) writeRow(e.target as HTMLElement, k, 0)
    }
  }, { root, rootMargin: '160px 0px' })
  for (const tr of rowEl.values()) rowIO.observe(tr)
}

/** 渲染后挂事件、把键盘焦点放回光标那一行 */
export function mountWatch(el: HTMLElement): void {
  const tbl = $('#wTbl', el)
  if (!tbl) { rowIO?.disconnect(); rowIO = null; gate.reset(); rowEl.clear(); return }
  observeRows(tbl, tbl.closest<HTMLElement>('.wv-body'))
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
          undo = () => { st.watch[k] = undoClear(bak, st.watch[k]); save(); D.renderPanel(); D.refreshStreams() }
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
/** 被拖的品种放在拖动数据里，不记 DOM 节点：拖动途中同步改了自选、列表重画，松手照样落得对 */
const DRAG_TYPE = 'application/x-hkline-watch'
function bindDrag(tbl: HTMLElement): void {
  const clear = () => $$('tr', tbl).forEach(r => r.classList.remove('drop-above', 'drop-below'))
  const ours = (e: DragEvent): boolean => !!e.dataTransfer?.types.includes(DRAG_TYPE)
  tbl.addEventListener('dragstart', e => {
    const tr = tgt(e).closest<HTMLElement>('tr[data-sym]'); if (!tr || !e.dataTransfer) return
    tr.classList.add('dragging'); e.dataTransfer.setData(DRAG_TYPE, tr.dataset.sym || ''); e.dataTransfer.effectAllowed = 'move'
  })
  tbl.addEventListener('dragend', e => { tgt(e).closest('tr')?.classList.remove('dragging'); clear() })
  tbl.addEventListener('dragover', e => {
    const tr = tgt(e).closest<HTMLElement>('tbody tr[data-sym]'); if (!tr || !ours(e)) return
    e.preventDefault(); clear()
    const r = tr.getBoundingClientRect(); tr.classList.add(e.clientY < r.top + r.height / 2 ? 'drop-above' : 'drop-below')
  })
  tbl.addEventListener('drop', e => {
    const tr = tgt(e).closest<HTMLElement>('tbody tr[data-sym]'); if (!tr || !ours(e)) return
    e.preventDefault()
    const below = tr.classList.contains('drop-below'); clear()
    const rendered = $$<HTMLElement>('tbody tr[data-sym]', tbl).map(r => r.dataset.sym || '')
    const list = st.watch[st.watchTab]
    const next = reorderWatch(list, rendered, e.dataTransfer?.getData(DRAG_TYPE) || '', tr.dataset.sym || '', below)
    if (!next) return
    list.splice(0, list.length, ...next); save(); D.renderPanel()
  })
}

// ------------------------------------------------------------ 推送来的数：只改那几格的字
/** dir：这一跳是涨（1）还是跌（-1）；价格文字闪一次涨跌色（150 ms） */
export function patchWatchRow(k: string, dir: number): void {
  // 滚出去的行：不碰 DOM，滚进来时补（见 RowGate）
  const tr = rowEl.get(k)
  if (!tr || !tr.isConnected || !gate.offer(k)) return
  writeRow(tr, k, dir)
}
function writeRow(tr: HTMLElement, k: string, dir: number): void {
  const s = sym(k)
  if (!s) return
  const p = $('[data-f="price"]', tr), pc = $('[data-f="pct"]', tr)
  // 字没变就不写（同一价位来回推、涨跌幅两位小数没跳）：写一次 textContent 就是一次排版
  if (p) {
    const pt = priceText(s)
    if (p.textContent !== pt) p.textContent = pt
    // 重播闪色不读 offsetWidth：原来每只跳价的行都 remove → 读宽度 → add，一帧几十行就是几十次强制样式重算；
    // 改成两套同样的关键帧轮换（换了动画名就从头播），一帧内只写不读
    if (dir) { const c = flashClass(p.className, dir); p.classList.remove(...FLASH_CLASSES); p.classList.add(c) }
  }
  if (pc) {
    const ct = pctText(s.pct), cn = `num ${cls(s.pct)} price-live`
    if (pc.textContent !== ct) pc.textContent = ct
    if (pc.className !== cn) pc.className = cn
  }
}
