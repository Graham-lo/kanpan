/* Hkline 手机网页版 · DOM 小工具（不依赖 PC 的 ui/dom） */

/** HTML 转义 */
export function esc(s: unknown): string {
  return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!))
}

/** 建一个元素：el('div', 'row', '<b>x</b>') */
export function el<K extends keyof HTMLElementTagNameMap>(tag: K, cls = '', html = ''): HTMLElementTagNameMap[K] {
  const e = document.createElement(tag)
  if (cls) e.className = cls
  if (html) e.innerHTML = html
  return e
}

/** 最近的可滚动祖先（找不到就是页面滚动容器） */
export function scrollParent(node: HTMLElement | null): HTMLElement {
  for (let n = node?.parentElement; n; n = n.parentElement) {
    const o = getComputedStyle(n).overflowY
    if ((o === 'auto' || o === 'scroll') && n.scrollHeight > n.clientHeight) return n
  }
  return (document.scrollingElement as HTMLElement) || document.documentElement
}

/** 下一帧（等布局落定再量 / 再起过渡） */
export const nextFrame = (): Promise<void> => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => r())))

/** 用户开了「减弱动态效果」 */
export const reducedMotion = (): boolean => matchMedia('(prefers-reduced-motion: reduce)').matches

/** 最上层的浮层容器（弹层、解释卡、toast 都挂这儿，不受页面 overflow / transform 影响） */
export function layer(): HTMLElement {
  let l = document.getElementById('m-layer')
  if (!l) { l = el('div'); l.id = 'm-layer'; document.body.appendChild(l) }
  return l
}

let probe: HTMLElement | null = null
/** 当前安全区（px）：CSS 变量里的 env() 读不出数值，用一个隐藏探针量 */
export function safeArea(): { top: number; bottom: number; left: number; right: number } {
  if (!probe) {
    probe = el('div')
    probe.style.cssText = 'position:fixed;visibility:hidden;pointer-events:none;inset:0 auto auto 0;width:0;height:0;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)'
    document.body.appendChild(probe)
  }
  const s = getComputedStyle(probe)
  return { top: parseFloat(s.paddingTop) || 0, bottom: parseFloat(s.paddingBottom) || 0, left: parseFloat(s.paddingLeft) || 0, right: parseFloat(s.paddingRight) || 0 }
}
