/* Hkline Web · 侧栏「自选」小部件
 *
 * 图表页只留挂接点（installWatch / widgetWatch / mountWatch / watchClick / patchWatchRow / takeWatchUndo），
 * 列表的渲染、键盘、右键、拖动排序都在这里。
 *
 * 2026-10-10 用户定版（docs/prototypes/web-layout-2026-10-10.html §3，审查 A1 / C1）：
 *   · 按分类分节连续列出（watch/sections.ts）：组头可折叠、带数量、吸顶；分类胶囊只做跳转（点了滚到那一节），
 *     滚动时胶囊跟着亮到当前那一节。折叠只记本机（localStorage 一个键），不是设置项。
 *   · 当前品种那一行强调软底；行尾悬停出「铃 · 星」两个快捷块（涨跌幅让位）：铃 = 创建提醒，星 = 加 / 移自选。
 *     快捷块整张表只有一份，指针移到哪一行就挪进哪一行（三百行的表不多三百对按钮）。
 *   · 右键：在图上打开 · 创建提醒 · 记一笔 · 加入对比 · 移到分类 · 移出自选。
 * 列固定三列：品种（「DOGEUSDT」，2026-10-09 用户要求不带交易所与永续）· 最新价 · 涨跌幅，不给列设置；
 * 排版照 TradingView 自选：字 14、行高 34、数字列定宽各成一竖条。
 * 键盘（焦点在列表里时，带 ⌘ / Ctrl / Alt 的一律放给全局）：
 *   ↑ ↓ Home End  移动并在活动格打开（跨节连续走，收起的节跳过）
 *   ↵             在活动格打开光标这只
 *   Delete / ⌫    移出自选，光标落到下一行，⌘Z 撤销
 *   空格          收藏 / 取消（等于点星）；取消后这一行淡着留在原位，再按空格收回原位置，焦点离开列表才真正消失
 *   Esc           退出列表
 * 多图时头部下写「在第 N 格打开」，跟着活动格走；行的右键菜单同样写第几格。
 */
import { st, save } from '../app/store'
import { S, TABS, baseOf, headName, kindOfUnderlying, type Kind } from '../market'
import { $, $$, I, tgt, esc } from '../ui/dom'
import { toast, menu, menuFrom, type MenuItem } from '../ui/overlay'
import { sym, pctText, cls, priceText, badge } from '../ui/common'
import { marketOf } from '../venues'
import { HL } from '../terms'
import { undoClear, flashClass, FLASH_CLASSES, RowGate } from './logic'
import { watchSections, navRows, sectionAt, dropAcross, moveToTab, loadFold, saveFold, type WatchSection } from './sections'
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
  /** 创建提醒（提醒模块现成的弹窗） */
  createAlert(k: string): void
  /** 记一笔（不是当前品种先在图上打开它，K 线到了再弹） */
  note(k: string): void
  /** 加入 / 移出对比（满了由宿主提示） */
  toggleCompare(k: string): void
  inCompare(k: string): boolean
  /** 加 / 移自选（星） */
  toggleWatch(k: string): void
}
let D: WatchDeps

const kb = { on: false, cursor: '' }
let ghost: { k: string; i: number; tab: Kind } | null = null
let undo: (() => void) | null = null
let fold: Set<Kind> | null = null
const folds = (): Set<Kind> => (fold ??= loadFold())

/** 全局 ⌘Z 先问这里要不要撤销自选的改动 */
export function takeWatchUndo(): (() => void) | null { const u = undo; undo = null; return u }

const panelEl = (): HTMLElement | null => document.getElementById('sidePanel')
const tabName = (k: Kind): string => TABS.find(x => x[0] === k)?.[1] || ''
const codeOf = (k: string): string => sym(k)?.code || headName({ symbol: k })
const targetLabel = (): string => D.cellCount() > 1 ? `在第 ${D.activeIndex() + 1} 格打开` : '在图上打开'
const isWatched = (k: string): boolean => Object.values(st.watch).some(l => l.includes(k))

/** 各节（含空格取消后淡着留下的那一行） */
function sections(): WatchSection[] { return watchSections(st.watch, TABS, ghost, folds()) }
/** 这一只在哪一节（淡行算它原来那一节） */
function tabOf(k: string): Kind | null {
  if (ghost?.k === k) return ghost.tab
  return TABS.find(([t]) => st.watch[t].includes(k))?.[0] ?? null
}

/** 自选栏里看得见的那些（收起的节不算）：只给它们订行情 */
export function watchVisible(): string[] { return navRows(sections()) }

export function installWatch(d: WatchDeps): void {
  D = d
  // 换了账号：上一个账号的 ⌘Z 撤销和淡行都不再作数（不然 ⌘Z 会把上个账号移出的品种塞进这个账号）
  onSession(() => { undo = null; ghost = null })
}

// ------------------------------------------------------------ 渲染
export function widgetWatch(): string {
  const cur = D.current()
  const secs = sections()
  const nav = navRows(secs)
  const empty = !S.symbols.size
    ? `<div class="empty">${I('wifiOff', 'icon-24')}<div>${S.live === false ? (S.limited ? '币安限流了，冷却后自动重试' : '连不上币安合约接口') : '正在取行情…'}</div></div>`
    : `<div class="empty">${I('star', 'icon-24')}<div>还没有自选</div><button class="btn secondary sm" style="margin-top:12px" id="wAdd2">搜索品种</button></div>`
  const c = D.collapsed()
  if (!nav.includes(kb.cursor)) kb.cursor = nav.includes(cur) ? cur : nav[0] || ''
  if (secs.length && !secs.some(s => s.tab === st.watchTab)) st.watchTab = secs[0].tab
  const multi = D.cellCount() > 1
  // 标题、分类胶囊（跳转；数量写在各节组头上，胶囊只写分类名，窄侧栏也放得下）、添加、更多、收起并在一行，省下的高度给列表
  return `<div class="widget widget-watch ${c ? 'collapsed' : ''}"><div class="sp-head wv-head"><h3>自选</h3>
      <div class="wv-tabs" role="tablist">${secs.map(s => `<button class="chip" role="tab" data-tab="${s.tab}" aria-pressed="${st.watchTab === s.tab}" aria-label="${s.label} ${s.count}">${s.label}</button>`).join('')}</div>
      <button class="ibtn xs" id="wAdd" aria-label="添加品种" data-tip="添加品种" data-kbd="⌘ K">${I('plus', 'icon-16')}</button>
      <button class="ibtn xs" id="wMore" aria-label="更多" data-tip="更多">${I('more', 'icon-16')}</button>
      ${D.collapseBtn(c)}</div>
    ${multi ? `<div class="wv-target" id="wTarget">${I('layout4', 'icon-16')}<span>${targetLabel()}</span><span class="sc">↵</span></div>` : ''}
    <div class="scroll no-bar wv-body">
      ${secs.length ? `<table class="tbl" id="wTbl" role="grid" aria-label="自选">${secs.map(s => sectionHTML(s, cur)).join('')}</table>` : empty}
    </div></div>`
}

function sectionHTML(s: WatchSection, cur: string): string {
  const lab = s.folded ? HL.sideExpand : HL.collapse
  return `<tbody data-grp="${s.tab}"><tr class="wv-grp" data-fold="${s.tab}"><th colspan="3"><button class="wv-gh" aria-expanded="${!s.folded}" aria-label="${s.label} ${s.count} · ${lab}">
      <span class="wv-gl">${s.label}</span><span class="wv-gn num">${s.count}</span>${I('chevronDown', 'icon-16 wv-chev')}</button></th></tr>
    ${s.folded ? '' : s.rows.map(k => watchRow(k, cur, s.tab)).join('')}</tbody>`
}

/** 品种表还没到（冷启动、本机也没留）：行先按本机自选的代号摆出来，徽标按代号猜、价格写「—」，表到了整张重画 */
function watchRow(k: string, cur: string, tab: Kind): string {
  const s = sym(k), g = ghost?.k === k, base = baseOf(k)
  const code = s?.code || base, quote = s?.quote ?? marketOf(k)?.quote ?? ''
  return `<tr data-sym="${k}" data-tab="${tab}" draggable="${!g}" tabindex="${k === kb.cursor ? 0 : -1}" class="${k === cur ? 'sel' : ''} ${g ? 'wv-ghost' : ''}" aria-selected="${k === cur}">
    <td><div class="sym">${badge(s ?? { base, kind: kindOfUnderlying(undefined, base) })}<span class="wv-name"><b><span>${esc(code)}</span>${quote ? `<span>${esc(quote)}</span>` : ''}</b></span>${g ? `<span class="wv-off" data-tip="已移出自选，按空格收回">${I('starOff', 'icon-16')}</span>` : ''}</div></td>
    <td class="num price-live wc-px" data-f="price">${priceText(s)}</td>
    <td class="wc-pct"><span class="num ${cls(s?.pct)} price-live" data-f="pct">${pctText(s?.pct)}</span></td></tr>`
}

/** 行尾悬停的两个快捷块：铃 = 创建提醒，星 = 加 / 移自选（星实心 = 在自选里） */
export function quickHTML(k: string, watched: boolean): string {
  const star = watched ? HL.sideWatchOff : HL.addFavorite
  return `<button class="wv-q" data-wq="alert" data-k="${esc(k)}" aria-label="${HL.sideAlert}" data-tip="${HL.sideAlert}" data-tip-side="top">${I('bellPlus')}</button>` +
    `<button class="wv-q${watched ? ' on' : ''}" data-wq="star" data-k="${esc(k)}" aria-pressed="${watched}" aria-label="${star}" data-tip="${star}" data-tip-side="top">${I(watched ? 'star' : 'starLine')}</button>`
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

/** 整张表一份的快捷块：指针进哪一行就挪进哪一行的涨跌幅格 */
let quick: HTMLElement | null = null
function hoverRow(tr: HTMLElement | null): void {
  if (!tr) { quick?.remove(); return }
  const k = tr.dataset.sym || ''
  const cell = $('.wc-pct', tr)
  if (!cell || (quick?.parentElement === cell && quick.dataset.k === k)) return
  if (!quick) { quick = document.createElement('span'); quick.className = 'wv-act' }
  quick.dataset.k = k
  quick.innerHTML = quickHTML(k, isWatched(k))
  cell.appendChild(quick)
}

/** 滚到哪一节，胶囊就亮哪一颗（只换 aria-pressed，不重画） */
function spy(body: HTMLElement): void {
  const top = body.getBoundingClientRect().top
  const heads = $$<HTMLElement>('tbody[data-grp]', body).map(b => ({ tab: b.dataset.grp as Kind, top: b.getBoundingClientRect().top - top + body.scrollTop }))
  const t = sectionAt(heads, body.scrollTop, { viewH: body.clientHeight, scrollH: body.scrollHeight, keep: st.watchTab })
  if (!t || t === st.watchTab) return
  st.watchTab = t
  $$<HTMLElement>('.wv-tabs [data-tab]', body.closest('.widget-watch') ?? document).forEach(b => b.setAttribute('aria-pressed', String(b.dataset.tab === t)))
}

/** 渲染后挂事件、把键盘焦点放回光标那一行 */
export function mountWatch(el: HTMLElement): void {
  const tbl = $('#wTbl', el)
  quick = null
  if (!tbl) { rowIO?.disconnect(); rowIO = null; gate.reset(); rowEl.clear(); return }
  const body = tbl.closest<HTMLElement>('.wv-body')
  observeRows(tbl, body)
  bindDrag(tbl)
  tbl.addEventListener('keydown', onKey)
  tbl.addEventListener('mouseover', e => hoverRow(tgt(e).closest<HTMLElement>('tr[data-sym]')))
  tbl.addEventListener('mouseleave', () => hoverRow(null))
  if (body) body.addEventListener('scroll', () => spy(body), { passive: true })
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
  const tab = tabOf(k); if (!tab) return
  const wl = st.watch[tab], idx = wl.indexOf(k); if (idx < 0) return
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
  const tab = tabOf(k); if (!tab) return
  const l = st.watch[tab], idx = l.indexOf(k); if (idx < 0) return
  l.splice(idx, 1); ghost = { k, i: idx, tab }
  save(); D.renderPanel(); D.refreshStreams()
  toast(`已从自选移除 ${codeOf(k)}`, '再按空格收回', 'starOff', 1800)
}

/** 移到别的分类：接到那一节末尾，并把那一节展开、滚过去 */
function moveRow(k: string, to: Kind): void {
  const from = tabOf(k); if (!from || ghost?.k === k) return
  const next = moveToTab(st.watch, k, from, to); if (!next) return
  Object.assign(st.watch, next)
  if (folds().delete(to)) saveFold(folds())
  st.watchTab = to
  save(); D.renderPanel(); D.refreshStreams()
  $(`#wTbl tr[data-sym="${k}"]`)?.scrollIntoView({ block: 'nearest' })
  toast(`${codeOf(k)} 已移到「${tabName(to)}」`, '', 'list', 1800)
}

// ------------------------------------------------------------ 右键
/** 一行的右键菜单（纯拼装，tests/watch-sections.test.ts） */
export function rowMenu(k: string, o: { ghost: boolean; tab: Kind | null; multi: boolean; target: string; current: string; compared: boolean; tabs: readonly (readonly [Kind, string])[] }, run: {
  open(): void; alert(): void; note(): void; compare(): void; toggle(): void; remove(): void; move(t: Kind): void
}): MenuItem[] {
  const items: MenuItem[] = [
    { header: codeOf(k) },
    { icon: o.multi ? 'layout4' : 'candles', label: o.target, sc: '↵', run: run.open },
    { icon: 'bellPlus', label: HL.sideAlert, run: run.alert },
    { icon: 'note', label: HL.sideNote, run: run.note },
    { icon: 'compare', label: o.compared ? HL.sideCompareOff : HL.sideCompare, disabled: k === o.current, run: run.compare },
  ]
  const others = o.ghost || !o.tab ? [] : o.tabs.filter(([t]) => t !== o.tab)
  if (others.length) items.push('-', { header: HL.sideMoveTo }, ...others.map(([t, l]): MenuItem => ({ icon: 'list', label: l, run: () => run.move(t) })))
  items.push('-', o.ghost ? { icon: 'star', label: '加回自选', sc: '空格', run: run.toggle } : { icon: 'starOff', label: HL.sideWatchOff, sc: 'Delete', run: run.remove })
  return items
}

function onContext(e: MouseEvent): void {
  const tr = tgt(e).closest<HTMLElement>('tr[data-sym]'); if (!tr) return
  e.preventDefault()
  const k = tr.dataset.sym || '', g = ghost?.k === k
  const list = $$<HTMLElement>('#wTbl tbody tr[data-sym]').map(r => r.dataset.sym || '')
  setCursor(k, false)
  // 指数一类只有美元指数这种算出来的品种：没自选进去时不给「移到指数」
  const tabs = TABS.filter(([t]) => t !== 'idx' || st.watch.idx.length)
  menu(rowMenu(k, { ghost: g, tab: tabOf(k), multi: D.cellCount() > 1, target: targetLabel(), current: D.current(), compared: D.inCompare(k), tabs }, {
    open: () => D.openSymbol(k),
    alert: () => D.createAlert(k),
    note: () => D.note(k),
    compare: () => D.toggleCompare(k),
    toggle: () => toggleRow(k),
    remove: () => removeRow(k, list),
    move: t => moveRow(k, t),
  }), e.clientX, e.clientY, { width: 220 })
}

// ------------------------------------------------------------ 点击（图表页的面板点击先问这里）
/** 点胶囊：滚到那一节（收起着就先展开） */
function jumpTo(t: Kind): void {
  st.watchTab = t
  if (folds().delete(t)) { saveFold(folds()); D.renderPanel() }
  const body = $<HTMLElement>('.widget-watch .wv-body'), sec = $<HTMLElement>(`#wTbl tbody[data-grp="${t}"]`)
  $$<HTMLElement>('.widget-watch .wv-tabs [data-tab]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.tab === t)))
  if (body && sec) body.scrollTop += sec.getBoundingClientRect().top - body.getBoundingClientRect().top
}
function toggleFold(t: Kind): void {
  const f = folds()
  if (f.has(t)) f.delete(t); else f.add(t)
  saveFold(f); D.renderPanel()
}

export function watchClick(e: MouseEvent): boolean {
  const t = tgt(e)
  const q = t.closest<HTMLElement>('.wv-act [data-wq]')
  if (q) {
    const k = q.dataset.k || ''
    if (q.dataset.wq === 'alert') D.createAlert(k)
    else { if (ghost?.k === k) toggleRow(k); else D.toggleWatch(k) }
    return true
  }
  // 只认胶囊条：行上也带 data-tab（所在分组），放宽了会把点行当成「跳到那一组」、品种打不开
  const tab = t.closest<HTMLElement>('.widget-watch .wv-tabs [data-tab]')
  if (tab) { jumpTo(tab.dataset.tab as Kind); return true }
  const g = t.closest<HTMLElement>('#wTbl [data-fold]')
  if (g) { toggleFold(g.dataset.fold as Kind); return true }
  if (t.closest('#wAdd,#wAdd2')) { D.openSearch(); return true }
  const more = t.closest<HTMLElement>('#wMore')
  if (more) {
    const cur = st.watchTab
    menuFrom(more, [
      { icon: 'drag', label: '拖动行可以排序，拖到别的分类即移过去', disabled: true },
      { icon: 'list', label: '键盘：↑ ↓ 切换 · 空格 收藏 · Delete 移出', disabled: true },
      {
        icon: 'trash', label: `清空「${tabName(cur)}」自选`, disabled: !st.watch[cur].length, run: () => {
          const k = cur, bak = st.watch[k]; st.watch[k] = []; ghost = null; save(); D.renderPanel(); D.refreshStreams()
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
    hoverRow(null)
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
    const moved = e.dataTransfer?.getData(DRAG_TYPE) || ''
    const to = tr.dataset.tab as Kind, from = TABS.find(([t]) => st.watch[t].includes(moved))?.[0]
    if (!from || !to) return
    const rendered = $$<HTMLElement>('tr[data-sym]', tr.parentElement ?? tbl).map(r => r.dataset.sym || '')
    const next = dropAcross(st.watch, from, to, rendered, moved, tr.dataset.sym || '', below)
    if (!next) return
    for (const [t, l] of Object.entries(next) as [Kind, string[]][]) st.watch[t].splice(0, st.watch[t].length, ...l)
    save(); D.renderPanel()
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
