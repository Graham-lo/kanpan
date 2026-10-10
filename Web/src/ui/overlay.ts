/* Hkline Web · 浮层：悬停提示、术语解释、轻提示、菜单、对话框 */
import { $, $$, I, esc, tgt } from './dom'
import { isTipSide, placeTip } from './tipPlace'

// ------------------------------------------------------------ 术语
export const GLOSSARY: Record<string, string> = {
  资金费率: '多空双方每 8 小时互付一次的费用。为正时多头付给空头，说明合约价高于现货、做多的人多。',
  持仓量: '所有还没平掉的合约加起来值多少美元。价格涨、持仓量也涨，多半是新资金进场。',
  多空人数比: '币安上做多的账户数 ÷ 做空的账户数（5 分钟一档）。大于 1 是多头人多。',
  大户持仓比: '持仓最大的前 20% 账户里，多头仓位 ÷ 空头仓位。大于 1 是大户偏多。',
  主动买卖比: '最近 5 分钟主动买入量 ÷ 主动卖出量。大于 1 是买盘更急。',
  标记价: '用来算强平与盈亏的价格，取指数价加上资金费率的均值，比最新价平滑。',
  指数价: '几家现货交易所的成交价加权平均，是合约价格的锚。',
  基差: '标记价相对指数价高出多少。为正说明合约比现货贵、市场偏多。',
  下次结算: '距离下一次收付资金费还有多久。',
  市值: '总供应量 × 现价。',
  跑赢大盘: '这段时间里，板块成员跑赢全市场等权平均的有几只（分母是有行情的成员数）。',
  中位涨跌: '板块里所有品种涨跌幅排在正中间的那个数，不会被一两只暴涨暴跌的带偏。',
  主力订单流: '币安、OKX、Coinbase、Bybit、Hyperliquid 各家挂单簿合在一起，只画超过门槛的大单。',
}
export function term(k: string, label = k): string { return `<span class="term" data-term="${k}" tabindex="0">${label}</span>` }

// ------------------------------------------------------------ 悬停提示
const tip: { timer: ReturnType<typeof setTimeout> | undefined; target: HTMLElement | null } = { timer: undefined, target: null }
function showTip(target: HTMLElement): void {
  const t = $('#tooltip'); if (!t) return
  let html: string
  if (target.dataset.term) html = `<b>${esc(target.dataset.term)}</b>${esc(GLOSSARY[target.dataset.term] || '')}`
  else html = esc(target.dataset.tip) + (target.dataset.kbd ? target.dataset.kbd.split(' ').map(k => `<kbd>${esc(k)}</kbd>`).join('') : '')
  t.innerHTML = html
  t.style.maxWidth = target.dataset.term ? '280px' : '360px'
  const r = target.getBoundingClientRect()
  // 先挪回左上角再量：停在右缘的上一次位置会让宽度按剩余空间收窄、多折一行，量出来的尺寸就不对了
  t.style.left = '0px'; t.style.top = '0px'
  t.classList.add('show')
  // 摆位规则见 ui/tipPlace.ts：不盖目标、首选边放不下就翻面、夹进视口
  const side = target.dataset.tipSide
  const p = placeTip(r, t.offsetWidth, t.offsetHeight, isTipSide(side) ? side : undefined, innerWidth, innerHeight)
  t.dataset.side = p.side
  t.style.left = p.x + 'px'
  t.style.top = p.y + 'px'
}
export function hideTip(): void { clearTimeout(tip.timer); tip.target = null; $('#tooltip')?.classList.remove('show') }

export function installTooltips(): void {
  document.addEventListener('mouseover', e => {
    const t = tgt(e).closest?.<HTMLElement>('[data-tip],[data-term]') ?? null
    if (t === tip.target) return
    hideTip()
    if (!t) return
    tip.target = t
    tip.timer = setTimeout(() => showTip(t), t.dataset.term ? 250 : 450)
  })
  document.addEventListener('focusin', e => { const t = tgt(e).closest?.<HTMLElement>('[data-tip]'); if (t && t.matches(':focus-visible')) { tip.target = t; showTip(t) } })
  document.addEventListener('focusout', hideTip)
  document.addEventListener('mousedown', hideTip)
  document.addEventListener('mousedown', e => {
    const n = e.target as Node
    // 点在弹层的触发按钮上不在这里关：交给按钮自己的点击做「再点一下收起」（不然先关后开，永远收不起来）
    if (openMenuEl && !openMenuEl.contains(n) && !openMenuKeep?.contains(n)) closeMenu()
  }, true)
  bindEsc()
}

// ------------------------------------------------------------ 轻提示
export function toast(title: string, sub = '', ic = 'check', ms = 3600): void {
  const e = document.createElement('div')
  e.className = 'toast'
  e.innerHTML = `${I(ic)}<div class="tx"><b>${esc(title)}</b>${sub ? `<span>${esc(sub)}</span>` : ''}</div>`
  $('#toasts')?.appendChild(e)
  setTimeout(() => e.remove(), ms)
}

// ------------------------------------------------------------ 菜单
export type MenuItem = '-' | {
  header?: string; icon?: string; label?: string; html?: string; sc?: string
  checked?: boolean; check?: boolean; disabled?: boolean; run?: () => void
  /** 行尾的小按钮（如周期的收藏星）：点它只跑 trailRun、菜单不关；trailRun 拿到按钮自己好就地改样子 */
  trail?: string; trailTip?: string; trailRun?: (el: HTMLElement) => void
}
export interface MenuOpts { width?: number; focus?: boolean; returnFocus?: HTMLElement }

let openMenuEl: HTMLElement | null = null
/** 弹层的触发按钮：在它上面按下不算「点在外面」 */
let openMenuKeep: HTMLElement | null = null
let onMenuClose: (() => void) | null = null
/** Esc 关掉菜单 / 弹层之后焦点回哪（触发按钮，没有就是开之前的焦点） */
let openMenuReturn: HTMLElement | null = null
export function menuOpen(): boolean { return !!openMenuEl }
export function closeMenu(): void {
  const cb = onMenuClose
  openMenuEl?.remove(); openMenuEl = null; openMenuKeep = null; onMenuClose = null; openMenuReturn = null
  cb?.()
}
/** Esc 收起最上面那层（菜单 / 弹层），焦点回触发处 */
function escMenu(): void {
  const r = openMenuReturn
  closeMenu(); if (r?.isConnected) r.focus({ preventScroll: true })
}

export function menu(items: MenuItem[], x: number, y: number, opts: MenuOpts = {}): HTMLElement {
  closeMenu(); bindEsc()
  const prev = document.activeElement as HTMLElement | null
  const m = document.createElement('div')
  m.className = 'menu'; m.setAttribute('role', 'menu'); m.tabIndex = -1
  if (opts.width) m.style.minWidth = opts.width + 'px'
  m.innerHTML = items.map((it, k) => {
    if (it === '-') return '<div class="sep" role="separator"></div>'
    if (it.header) return `<div class="mh">${esc(it.header)}</div>`
    const lead = it.icon ? I(it.icon) : it.check !== undefined ? I('check', 'icon check') : ''
    return `<button class="mi ${it.checked ? 'checked' : ''}" role="menuitem" data-k="${k}" ${it.disabled ? 'disabled style="opacity:.45;cursor:default"' : ''}>${lead}<span class="label">${it.html || esc(it.label)}</span>${it.sc ? `<span class="sc">${esc(it.sc)}</span>` : ''}${it.trail ? `<span class="mi-trail" data-trail${it.trailTip ? ` data-tip="${esc(it.trailTip)}"` : ''}>${it.trail}</span>` : ''}</button>`
  }).join('')
  document.body.appendChild(m)
  const w = m.offsetWidth, h = m.offsetHeight
  m.style.left = Math.max(8, Math.min(x, innerWidth - w - 8)) + 'px'
  m.style.top = (y + h > innerHeight - 8 ? Math.max(8, y - h) : y) + 'px'
  m.addEventListener('click', e => {
    const b = tgt(e).closest<HTMLButtonElement>('.mi'); if (!b || b.disabled) return
    const it = items[+(b.dataset.k || 0)]
    const tr = tgt(e).closest<HTMLElement>('[data-trail]')
    if (tr && it !== '-' && it.trailRun) { e.stopPropagation(); it.trailRun(tr); return }
    closeMenu()
    if (it !== '-') it.run?.()
  })
  m.addEventListener('keydown', e => {
    const list = $$<HTMLButtonElement>('.mi:not([disabled])', m), i = list.indexOf(document.activeElement as HTMLButtonElement)
    if (!list.length) return
    if (e.key === 'ArrowDown') { e.preventDefault(); list[(i + 1) % list.length].focus() }
    if (e.key === 'ArrowUp') { e.preventDefault(); list[(i < 0 ? list.length : i) - 1].focus() }
  })
  m.addEventListener('keydown', escInside)
  openMenuEl = m; openMenuReturn = opts.returnFocus ?? (prev && prev !== document.body ? prev : null)
  // 焦点放进菜单：右键 / 点按钮弹出后直接 Esc、上下键都接得住（键盘打开的落在第一项）
  if (opts.focus) $('.mi', m)?.focus(); else m.focus({ preventScroll: true })
  return m
}
// ------------------------------------------------------------ 弹层（右侧栏图标点出的面板：主力订单流 / 提醒 / 笔记 / 成交）
/** 和菜单同一套：同一时刻只开一个（开菜单、对话框会先关它），点外面、Esc 收起。
 *  摆在触发按钮左边、上沿对齐按钮，放不下就往上挪、夹进视口（四边留 8）；内容由调用方往返回的元素里画。 */
export interface PopOpts {
  width: number; cls?: string; label?: string; onClose?: () => void
  /** 在它上面按下不算点外面（默认 = 触发按钮；右侧栏整条传进来，栏重画换了按钮节点也认） */
  keep?: HTMLElement
  /** 内容后补（门槛、列表异步到）使高度变了时怎么重摆；不给就按触发按钮摆 */
  place?: () => void
}
export function popover(anchor: HTMLElement, opts: PopOpts): HTMLElement {
  closeMenu(); bindEsc()
  const m = document.createElement('div')
  m.className = 'menu pop' + (opts.cls ? ' ' + opts.cls : '')
  m.setAttribute('role', 'dialog')
  if (opts.label) m.setAttribute('aria-label', opts.label)
  m.style.width = opts.width + 'px'
  document.body.appendChild(m)
  const place = opts.place ?? (() => { if (anchor.isConnected) placePop(m, anchor) })
  // 内容后补（门槛、列表异步到）：下一帧按新的自然高重摆（放不下先上移、再限高滚动），一帧最多一次
  let raf = 0
  const mo = typeof MutationObserver === 'undefined' ? null : new MutationObserver(() => {
    if (!raf) raf = requestAnimationFrame(() => { raf = 0; if (m.isConnected) place() })
  })
  mo?.observe(m, { childList: true, subtree: true })
  m.addEventListener('keydown', escInside)
  openMenuEl = m; openMenuKeep = opts.keep ?? anchor; openMenuReturn = anchor
  onMenuClose = () => { mo?.disconnect(); if (raf) cancelAnimationFrame(raf); opts.onClose?.() }
  placePop(m, anchor)
  return m
}
/** 内容变了（高度变了）之后再摆一次 */
export function placePop(m: HTMLElement, anchor: HTMLElement): void {
  const r = anchor.getBoundingClientRect()
  m.style.maxHeight = ''   // 按内容的自然高量（上一次限的高不算），放不下再上移 / 限高
  const p = popPlace(r, m.offsetWidth, m.offsetHeight, innerWidth, innerHeight)
  m.style.left = p.x + 'px'; m.style.top = p.y + 'px'; m.style.maxHeight = p.maxH + 'px'
}
/** 弹层左上角：贴在按钮左侧 8，上沿对齐按钮；下面放不下就整体上移；比视口还高就顶到上沿、限高（纯函数，tests/rail-side.test.ts） */
export function popPlace(r: { left: number; top: number; right: number }, w: number, h: number, vw: number, vh: number): { x: number; y: number; maxH: number } {
  const E = 8
  const x = Math.max(E, Math.min(r.left - 8 - w, vw - w - E))
  const y = Math.max(E, Math.min(r.top, vh - E - Math.min(h, vh - 2 * E)))
  return { x: Math.round(x), y: Math.round(y), maxH: Math.round(vh - E - y) }
}
/** 现在开着的弹层（不是菜单）；没有返回 null */
export function openPop(): HTMLElement | null { return openMenuEl?.classList.contains('pop') ? openMenuEl : null }

export function menuFrom(btn: HTMLElement, items: MenuItem[], opts: MenuOpts = {}): HTMLElement {
  const r = btn.getBoundingClientRect()
  return menu(items, r.left, r.bottom + 4, { ...opts, returnFocus: btn })
}

// ------------------------------------------------------------ 对话框
export interface Dialog { scrim: HTMLElement; dlg: HTMLElement; close: () => void }
export const dialogs: Dialog[] = []
/** Esc 归谁：谁在最上层谁吃掉。菜单 / 弹层压在对话框上面，开着就先关它，对话框这一下收不到；
 *  焦点就在那一层里时交给那一层自己的 keydown（输入框可先接走，如布局改名的 Esc = 退回菜单）。
 *  对话框里点了会整块重画的东西（指标勾选、分类）之后焦点掉回 body，对话框自己的 keydown 收不到，这里兜住关最上面那个。
 *  纯函数，tests/overlay-esc.test.ts */
export type EscOwner = 'menu' | 'dialog' | null
export function escOwner(s: { menu: boolean; inMenu: boolean; dialogs: number; inDialog: boolean }): EscOwner {
  if (s.menu) return s.inMenu ? null : 'menu'
  if (s.dialogs && !s.inDialog) return 'dialog'
  return null
}
/** 焦点在菜单 / 弹层里：冒泡到它自己身上时关（里面的输入框没 stopPropagation 的话） */
function escInside(e: KeyboardEvent): void {
  if (e.key !== 'Escape') return
  e.stopPropagation(); e.preventDefault(); escMenu()
}
let escBound = false
function bindEsc(): void {
  if (escBound || typeof document === 'undefined') return
  escBound = true
  document.addEventListener('keydown', e => {
    if (e.key !== 'Escape') return
    const t = e.target as Node | null
    const who = escOwner({
      menu: !!openMenuEl, inMenu: !!t && !!openMenuEl?.contains(t),
      dialogs: dialogs.length, inDialog: !!t && dialogs.some(d => d.dlg.contains(t)),
    })
    if (!who) return
    // 捕获阶段在 document 上就截住：对话框、图表页全局键盘都收不到这一下
    e.stopImmediatePropagation(); e.preventDefault()
    if (who === 'menu') escMenu(); else dialogs[dialogs.length - 1].close()
  }, { capture: true })
}

export function dialog(html: string, cls: string, { center = false, onClose, label = '' }: { center?: boolean; onClose?: () => void; label?: string } = {}): Dialog {
  closeMenu()
  const scrim = document.createElement('div')
  scrim.className = 'scrim' + (center ? ' center' : '')
  scrim.innerHTML = `<div class="dialog ${cls}" role="dialog" aria-modal="true" aria-label="${esc(label)}">${html}</div>`
  const prevFocus = document.activeElement as HTMLElement | null
  document.body.appendChild(scrim)
  const dlg = scrim.firstElementChild as HTMLElement
  let closed = false
  const api: Dialog = {
    scrim, dlg,
    close: () => {
      if (closed) return
      closed = true
      scrim.remove(); dialogs.splice(dialogs.indexOf(api), 1); onClose?.(); prevFocus?.focus?.()
    },
  }
  dialogs.push(api); bindEsc()
  scrim.addEventListener('mousedown', e => { if (e.target === scrim) api.close() })
  $$('[data-close]', dlg).forEach(b => b.addEventListener('click', api.close))
  dlg.addEventListener('keydown', e => {
    if (e.key === 'Escape') { e.stopPropagation(); api.close() }
    if (e.key === 'Tab') { // 焦点留在对话框里
      const f = $$('button:not([disabled]),input,textarea,[tabindex="0"]', dlg).filter(x => x.offsetParent)
      if (!f.length) return
      if (e.shiftKey && document.activeElement === f[0]) { e.preventDefault(); f[f.length - 1].focus() }
      else if (!e.shiftKey && document.activeElement === f[f.length - 1]) { e.preventDefault(); f[0].focus() }
    }
  })
  return api
}
export function head(title: string, extra = ''): string {
  return `<div class="dialog-head"><h2>${title}</h2>${extra}<button class="ibtn" data-close aria-label="关闭" data-tip="关闭" data-kbd="Esc">${I('close')}</button></div>`
}
