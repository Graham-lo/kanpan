/* Hkline Web · 浮层：悬停提示、术语解释、轻提示、菜单、对话框 */
import { $, $$, I, esc, tgt } from './dom'

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
  主力订单流: '币安、OKX、Coinbase 现货三家挂单簿合在一起，只画超过门槛的大单。',
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
  t.classList.add('show')
  const tw = t.offsetWidth, th = t.offsetHeight
  let x = r.left + r.width / 2 - tw / 2, y = r.bottom + 8
  const side = target.dataset.tipSide
  if (side === 'right') { x = r.right + 8; y = r.top + r.height / 2 - th / 2 }
  else if (side === 'left') { x = r.left - tw - 8; y = r.top + r.height / 2 - th / 2 }
  else if (y + th > innerHeight - 8) y = r.top - th - 8
  t.style.left = Math.max(8, Math.min(innerWidth - tw - 8, x)) + 'px'
  t.style.top = Math.max(8, y) + 'px'
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
  document.addEventListener('mousedown', e => { if (openMenuEl && !openMenuEl.contains(e.target as Node)) closeMenu() }, true)
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
}
export interface MenuOpts { width?: number; focus?: boolean; returnFocus?: HTMLElement }

let openMenuEl: HTMLElement | null = null
export function menuOpen(): boolean { return !!openMenuEl }
export function closeMenu(): void { openMenuEl?.remove(); openMenuEl = null }

export function menu(items: MenuItem[], x: number, y: number, opts: MenuOpts = {}): HTMLElement {
  closeMenu()
  const m = document.createElement('div')
  m.className = 'menu'; m.setAttribute('role', 'menu')
  if (opts.width) m.style.minWidth = opts.width + 'px'
  m.innerHTML = items.map((it, k) => {
    if (it === '-') return '<div class="sep" role="separator"></div>'
    if (it.header) return `<div class="mh">${esc(it.header)}</div>`
    const lead = it.icon ? I(it.icon) : it.check !== undefined ? I('check', 'icon check') : ''
    return `<button class="mi ${it.checked ? 'checked' : ''}" role="menuitem" data-k="${k}" ${it.disabled ? 'disabled style="opacity:.45;cursor:default"' : ''}>${lead}<span class="label">${it.html || esc(it.label)}</span>${it.sc ? `<span class="sc">${esc(it.sc)}</span>` : ''}</button>`
  }).join('')
  document.body.appendChild(m)
  const w = m.offsetWidth, h = m.offsetHeight
  m.style.left = Math.max(8, Math.min(x, innerWidth - w - 8)) + 'px'
  m.style.top = (y + h > innerHeight - 8 ? Math.max(8, y - h) : y) + 'px'
  m.addEventListener('click', e => {
    const b = tgt(e).closest<HTMLButtonElement>('.mi'); if (!b || b.disabled) return
    const it = items[+(b.dataset.k || 0)]; closeMenu()
    if (it !== '-') it.run?.()
  })
  m.addEventListener('keydown', e => {
    const list = $$<HTMLButtonElement>('.mi:not([disabled])', m), i = list.indexOf(document.activeElement as HTMLButtonElement)
    if (!list.length) return
    if (e.key === 'ArrowDown') { e.preventDefault(); list[(i + 1) % list.length].focus() }
    if (e.key === 'ArrowUp') { e.preventDefault(); list[(i - 1 + list.length) % list.length].focus() }
    if (e.key === 'Escape') { e.stopPropagation(); closeMenu(); opts.returnFocus?.focus() }
  })
  openMenuEl = m
  if (opts.focus) $('.mi', m)?.focus()
  return m
}
export function menuFrom(btn: HTMLElement, items: MenuItem[], opts: MenuOpts = {}): HTMLElement {
  const r = btn.getBoundingClientRect()
  return menu(items, r.left, r.bottom + 4, { ...opts, returnFocus: btn })
}

// ------------------------------------------------------------ 对话框
export interface Dialog { scrim: HTMLElement; dlg: HTMLElement; close: () => void }
export const dialogs: Dialog[] = []
// 对话框里点了会整块重画的东西（指标勾选、分类）之后，焦点掉回 body，对话框自己的 keydown 收不到 Esc；
// 这里兜一层：焦点不在任何对话框里时，Esc 关最上面那个
let escBound = false
function bindEsc(): void {
  if (escBound || typeof document === 'undefined') return
  escBound = true
  document.addEventListener('keydown', e => {
    if (e.key !== 'Escape' || !dialogs.length || menuOpen()) return
    const t = e.target as Node | null
    if (t && dialogs.some(d => d.dlg.contains(t))) return
    e.stopPropagation(); e.preventDefault()
    dialogs[dialogs.length - 1].close()
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
