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

const lastHTML = new WeakMap<Element, string>()
/** 只有内容真变了才重写 innerHTML（轮询回来数没变时不重建一整张表）；返回是否重写了。
 *  别处就地改过这块里面的字（行情推送 patch）之后要 forgetHTML，免得下次拿旧串比成「没变」 */
export function setHTML(node: Element, html: string): boolean {
  if (lastHTML.get(node) === html) return false
  node.innerHTML = html
  lastHTML.set(node, html)
  return true
}
export function forgetHTML(node: Element): void { lastHTML.delete(node) }

/** 手指按在 root 里时把整块重画往后放：轮询回来就地 innerHTML 会把按着的那一行换成新节点，
 *  松手时点击落不到行上、长按计时随旧节点一起作废。返回的 gate(fn)：没按着立刻跑；按着就记下最后一次，
 *  松手（这一下的 click 派发完）后跑。按住超过 STUCK_MS 当作丢了松手事件，不再挡。 */
export function pressGate(root: HTMLElement): (fn: () => void) => void {
  const STUCK_MS = 5000
  const down = new Set<number>()
  let since = 0
  let queued: (() => void) | null = null
  const busy = (): boolean => down.size > 0 && Date.now() - since < STUCK_MS
  const flush = (): void => {
    if (busy() || !queued) return
    const fn = queued; queued = null
    setTimeout(() => { if (busy()) { queued ??= fn; return } fn() }, 0)
  }
  root.addEventListener('pointerdown', e => { if (!down.size) since = Date.now(); down.add(e.pointerId) })
  const up = (e: PointerEvent): void => { down.delete(e.pointerId); flush() }
  document.addEventListener('pointerup', up, true)
  document.addEventListener('pointercancel', up, true)
  document.addEventListener('visibilitychange', () => { down.clear(); flush() })
  return fn => { if (busy()) queued = fn; else { queued = null; fn() } }
}
