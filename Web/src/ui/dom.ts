/* Hkline Web · DOM 小工具 */
import { icon } from './icons'

/** 取一个元素；找不到时运行期是 null（调用处用 ?. 兜） */
export function $<T extends HTMLElement = HTMLElement>(sel: string, root: ParentNode = document): T {
  return root.querySelector(sel) as T
}
export function $$<T extends HTMLElement = HTMLElement>(sel: string, root: ParentNode = document): T[] {
  return [...root.querySelectorAll(sel)] as T[]
}
export const I = (name: string, cls?: string): string => icon(name, cls)

const ESC: Record<string, string> = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }
export function esc(s: unknown): string { return String(s ?? '').replace(/[&<>"]/g, c => ESC[c]) }

/** 事件目标当作元素用 */
export function tgt(e: Event): HTMLElement { return e.target as HTMLElement }

export function hydrateIcons(root: ParentNode = document): void {
  $$('[data-icon]', root).forEach(e => {
    const [n, c] = (e.dataset.icon || '').split(':')
    e.outerHTML = I(n, c || 'icon')
  })
}
