/* Hkline Web · 通用分隔条
 *
 * 竖着的一条（dir 'x'）左右拖改宽，横着的一条（dir 'y'）上下拖改高。
 * 热区 6 px，正中 1 px 可见线：平时不显色（区域之间本来就有一道间隙），悬停与拖动时变强调色。
 * 拖动中实时重排：指针事件只记最新位移，每帧（rAF）交给 onMove 一次，图表的重画由它们自己的
 * ResizeObserver 接着在同一帧里做，不会一帧排好几次版。
 * 松手调 onEnd（落盘），双击调 onReset（回默认）。不做键盘操作。
 */
export type SplitDir = 'x' | 'y'

export interface SplitterOptions {
  dir: SplitDir
  /** 放到哪个容器里（需要是定位容器） */
  parent: HTMLElement
  /** 按下：记下起点的尺寸 */
  onStart?: () => void
  /** 拖动：d = 从按下到现在的位移（px，右 / 下为正），一帧最多一次 */
  onMove: (d: number) => void
  /** 松手（拖动过才调） */
  onEnd?: () => void
  /** 双击 */
  onReset?: () => void
  /** 给回归脚本与样式用的名字 */
  name?: string
  tip?: string
}

export interface Splitter {
  el: HTMLElement
  /** 放在容器里的位置（相对容器左上角）：dir 'x' 给竖线的中心 x 与上下；'y' 给横线的中心 y 与左右 */
  place(center: number, from: number, to: number): void
  show(on: boolean): void
  destroy(): void
}

/** 热区宽度 */
export const SPLIT_HIT = 6

let dragging = 0

/** 有分隔条正在拖（拖动时别的悬停效果让路） */
export function splitDragging(): boolean { return dragging > 0 }

export function splitter(o: SplitterOptions): Splitter {
  const el = document.createElement('div')
  el.className = `splitter split-${o.dir}`
  if (o.name) el.dataset.split = o.name
  el.setAttribute('role', 'separator')
  el.setAttribute('aria-orientation', o.dir === 'x' ? 'vertical' : 'horizontal')
  if (o.tip) el.title = o.tip
  o.parent.appendChild(el)

  let start = 0, last = 0, raf = 0, id = -1, moved = false
  const flush = (): void => { raf = 0; o.onMove(last) }
  const pos = (e: PointerEvent): number => o.dir === 'x' ? e.clientX : e.clientY

  el.addEventListener('pointerdown', e => {
    if (e.button !== 0) return
    e.preventDefault(); e.stopPropagation()
    id = e.pointerId; start = pos(e); last = 0; moved = false
    try { el.setPointerCapture(id) } catch { /* 合成事件没有真指针 */ }
    el.classList.add('dragging'); dragging++
    document.body.classList.add('resizing', `resizing-${o.dir}`)
    o.onStart?.()
  })
  el.addEventListener('pointermove', e => {
    if (e.pointerId !== id) return
    last = pos(e) - start
    if (last) moved = true
    if (!raf) raf = requestAnimationFrame(flush)
  })
  const end = (e: PointerEvent): void => {
    if (e.pointerId !== id) return
    id = -1
    if (raf) { cancelAnimationFrame(raf); raf = 0; o.onMove(last) }
    el.classList.remove('dragging'); dragging = Math.max(0, dragging - 1)
    document.body.classList.remove('resizing', 'resizing-x', 'resizing-y')
    if (moved) o.onEnd?.()
  }
  el.addEventListener('pointerup', end)
  el.addEventListener('pointercancel', end)
  el.addEventListener('dblclick', e => { e.preventDefault(); e.stopPropagation(); o.onReset?.() })

  return {
    el,
    place(center, from, to) {
      const s = el.style, half = SPLIT_HIT / 2
      if (o.dir === 'x') { s.left = `${Math.round(center - half)}px`; s.top = `${Math.round(from)}px`; s.height = `${Math.max(0, Math.round(to - from))}px`; s.width = `${SPLIT_HIT}px` }
      else { s.top = `${Math.round(center - half)}px`; s.left = `${Math.round(from)}px`; s.width = `${Math.max(0, Math.round(to - from))}px`; s.height = `${SPLIT_HIT}px` }
    },
    show(on) { el.hidden = !on },
    destroy() { if (raf) cancelAnimationFrame(raf); el.remove() },
  }
}
