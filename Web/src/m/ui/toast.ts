/* Hkline 手机网页版 · 底部提示条（照 iOS Main/ToastCenter.swift）
 *
 * 胶囊形、raised 底、1px line 描边、footnote 字；离底栏上沿 92（安全区以上）。
 * 带动作（「撤销」）的停 5 秒，否则 1.6 秒；新的一条直接顶掉旧的。动作字用 accent，中间隔一个「·」。
 */
import { el, esc, layer } from './dom'

export interface ToastAction { title: string; run: () => void }

let cur: HTMLElement | null = null
let timer = 0

/** 弹一条提示；再弹就顶掉上一条 */
export function toast(text: string, action?: ToastAction): void {
  dismissToast(true)
  const t = el('div', 'm-toast', `<span class="m-toast-text">${esc(text)}</span>`)
  t.setAttribute('role', 'status')
  if (action) {
    t.insertAdjacentHTML('beforeend', '<span class="m-toast-dot">·</span>')
    const b = el('button', 'm-toast-act', esc(action.title))
    b.type = 'button'
    b.onclick = e => { e.stopPropagation(); dismissToast(); action.run() }
    t.appendChild(b)
  }
  layer().appendChild(t)
  cur = t
  requestAnimationFrame(() => t.classList.add('in'))
  timer = window.setTimeout(() => dismissToast(), action ? 5000 : 1600)
}

/** 收掉当前那条；now = 不做淡出 */
export function dismissToast(now = false): void {
  clearTimeout(timer)
  const t = cur; cur = null
  if (!t) return
  if (now) { t.remove(); return }
  t.classList.remove('in')
  setTimeout(() => t.remove(), 200)
}
