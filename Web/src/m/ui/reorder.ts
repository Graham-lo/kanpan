/* Hkline 手机网页版 · 长按拖动排序（iOS List.onMove 的手感）
 *
 * 用法：
 *   const r = reorderable(listEl, { item: '.fav-row', onMove: (from, to) => { moveIndex(arr, from, to); save(); render() } })
 *   // 重绘后 DOM 换了也不用重挂：按选择器实时找行。换整张表容器时 r.destroy()。
 *
 * - 长按（默认 350ms，手指没挪过 8 点）起拖；给了 handle 选择器时按在把手上立刻起拖。
 * - 起拖时那一行抬起（放大一点、带阴影），其余行让位滑动；靠近滚动容器上下沿自动滚。
 * - 松手回调 onMove(from, to, rows)：from 是原下标，to 是移完之后它的新下标（和 moveIndex 的口径一致）。
 *   下标按「起拖那一刻」list 里匹配 item 选择器的那组元素算，rows 就是那组快照——拖的途中表被同步 / 行情重画过，
 *   调用方必须按 rows 上的键（data-sym 等）去挪，不能拿下标套到重画后的新表上（会挪走别人）。
 * - 拖的途中别重画这张表（handle.dragging 为真时记一笔，onEnd 里补画）：重画会把抬起的那行换掉，手里拖的行凭空消失。
 * - 拖的时候吞掉纵向滚动（非被动的 touchmove preventDefault），松手后那一下点击不算。
 */
import { scrollParent } from './dom'

export interface ReorderOptions {
  /** 可拖的行（在 list 里用 querySelectorAll 找） */
  item: string
  /** 把手；给了就只能从把手起拖，而且不用等长按 */
  handle?: string
  /** 长按多久起拖，默认 350ms */
  longPress?: number
  /** 现在能不能拖（编辑模式才开的表用），默认总是能 */
  enabled?: () => boolean
  onMove(from: number, to: number, rows: readonly HTMLElement[]): void
  /** 一次拖动结束（松手或取消，onMove 之后）：拖的途中推迟的重画在这里补 */
  onEnd?(): void
}

export interface ReorderHandle {
  destroy(): void
  /** 正在拖：这时重画表会把手里那行换掉，调用方先记下、等 onEnd 再画 */
  readonly dragging: boolean
}

/** 把 arr[from] 挪到 to（to 为移完后的下标），原地改并返回 arr */
export function moveIndex<T>(arr: T[], from: number, to: number): T[] {
  if (from === to || from < 0 || from >= arr.length) return arr
  const [x] = arr.splice(from, 1)
  arr.splice(Math.max(0, Math.min(arr.length, to)), 0, x)
  return arr
}

export function reorderable(list: HTMLElement, o: ReorderOptions): ReorderHandle {
  const hold = o.longPress ?? 350
  let timer = 0, pid = -1, x0 = 0, y0 = 0
  let drag: null | {
    row: HTMLElement; rows: HTMLElement[]; from: number; to: number
    tops: number[]; h: number; startY: number; y: number; scroller: HTMLElement; scroll0: number; raf: number
  } = null
  let swallowClick = false

  const items = (): HTMLElement[] => [...list.querySelectorAll<HTMLElement>(o.item)]

  const start = (row: HTMLElement, y: number): void => {
    const rows = items()
    const from = rows.indexOf(row)
    if (from < 0) return
    const scroller = scrollParent(list)
    drag = { row, rows, from, to: from, tops: rows.map(r => r.getBoundingClientRect().top), h: row.getBoundingClientRect().height, startY: y, y, scroller, scroll0: scroller.scrollTop, raf: 0 }
    list.classList.add('m-reordering')
    row.classList.add('m-lifted')
    rows.forEach(r => { if (r !== row) r.style.transition = 'transform 200ms cubic-bezier(0.2, 0.8, 0.3, 1)' })
    tick()
  }
  const layout = (): void => {
    if (!drag) return
    const d = drag
    const dScroll = d.scroller.scrollTop - d.scroll0
    const dy = d.y - d.startY + dScroll
    d.row.style.transform = `translate3d(0,${dy}px,0) scale(1.02)`
    // 被拖那行的中线落在哪一行的位置上
    const mid = d.tops[d.from] + dy + d.h / 2
    let to = d.from
    for (let i = 0; i < d.rows.length; i++) {
      if (i === d.from) continue
      const c = d.tops[i] + d.rows[i].offsetHeight / 2
      if (i < d.from && mid < c) { to = Math.min(to, i) }
      if (i > d.from && mid > c) { to = Math.max(to, i) }
    }
    d.to = to
    d.rows.forEach((r, i) => {
      if (i === d.from) return
      let shift = 0
      if (d.from < to && i > d.from && i <= to) shift = -d.h
      if (d.from > to && i >= to && i < d.from) shift = d.h
      r.style.transform = shift ? `translate3d(0,${shift}px,0)` : ''
    })
  }
  // 靠近滚动容器上下沿时自动滚
  const tick = (): void => {
    if (!drag) return
    const d = drag
    const box = d.scroller === document.scrollingElement ? { top: 0, bottom: innerHeight } : d.scroller.getBoundingClientRect()
    const edge = 56
    let v = 0
    if (d.y < box.top + edge) v = -Math.ceil((box.top + edge - d.y) / 6)
    else if (d.y > box.bottom - edge) v = Math.ceil((d.y - (box.bottom - edge)) / 6)
    if (v) d.scroller.scrollTop += v
    layout()
    d.raf = requestAnimationFrame(tick)
  }
  const finish = (commit: boolean): void => {
    clearTimeout(timer); timer = 0
    if (!drag) return
    const d = drag; drag = null
    cancelAnimationFrame(d.raf)
    list.classList.remove('m-reordering')
    d.row.classList.remove('m-lifted')
    d.rows.forEach(r => { r.style.transition = ''; r.style.transform = '' })
    swallowClick = true
    setTimeout(() => { swallowClick = false }, 0)
    if (commit && d.to !== d.from) o.onMove(d.from, d.to, d.rows)
    o.onEnd?.()
  }

  const onDown = (e: PointerEvent): void => {
    if (e.button !== 0 || drag || (o.enabled && !o.enabled())) return
    const t = e.target as Element
    const row = t.closest<HTMLElement>(o.item)
    if (!row || !list.contains(row)) return
    pid = e.pointerId; x0 = e.clientX; y0 = e.clientY
    if (o.handle) {
      if (!t.closest(o.handle)) return
      e.preventDefault()
      start(row, e.clientY)
      return
    }
    timer = window.setTimeout(() => { timer = 0; start(row, y0) }, hold)
  }
  const onMove = (e: PointerEvent): void => {
    if (e.pointerId !== pid) return
    if (timer && Math.hypot(e.clientX - x0, e.clientY - y0) > 8) { clearTimeout(timer); timer = 0 }
    if (drag) { drag.y = e.clientY; e.preventDefault() }
  }
  const onUp = (e: PointerEvent): void => { if (e.pointerId === pid) { pid = -1; finish(true) } }
  const onCancel = (e: PointerEvent): void => { if (e.pointerId === pid) { pid = -1; finish(false) } }
  // 触摸时 pointermove 在浏览器开始滚动后就收不到了：拖的时候把 touchmove 吞掉并自己喂坐标
  const onTouchMove = (e: TouchEvent): void => {
    if (!drag) return
    e.preventDefault()
    drag.y = e.touches[0].clientY
  }
  const onTouchEnd = (): void => { if (drag) { pid = -1; finish(true) } }
  const onClick = (e: MouseEvent): void => { if (swallowClick) { e.stopPropagation(); e.preventDefault() } }
  const onCtx = (e: Event): void => { if (timer || drag) e.preventDefault() }

  list.addEventListener('pointerdown', onDown)
  addEventListener('pointermove', onMove, { passive: false })
  addEventListener('pointerup', onUp)
  addEventListener('pointercancel', onCancel)
  list.addEventListener('touchmove', onTouchMove, { passive: false })
  list.addEventListener('touchend', onTouchEnd)
  list.addEventListener('click', onClick, true)
  list.addEventListener('contextmenu', onCtx)
  return {
    get dragging() { return drag !== null },
    destroy() {
      finish(false)
      list.removeEventListener('pointerdown', onDown)
      removeEventListener('pointermove', onMove)
      removeEventListener('pointerup', onUp)
      removeEventListener('pointercancel', onCancel)
      list.removeEventListener('touchmove', onTouchMove)
      list.removeEventListener('touchend', onTouchEnd)
      list.removeEventListener('click', onClick, true)
      list.removeEventListener('contextmenu', onCtx)
    },
  }
}

/** 长按（不起拖，只回调一次）：手指没挪过 8 点且按满 ms。返回解绑函数；触发后那一下点击不算 */
export function longPress(target: HTMLElement, run: (e: PointerEvent) => void, ms = 450): () => void {
  let t = 0, x = 0, y = 0, fired = false
  const down = (e: PointerEvent): void => {
    if (e.button !== 0) return
    x = e.clientX; y = e.clientY; fired = false
    t = window.setTimeout(() => { t = 0; fired = true; run(e) }, ms)
  }
  const move = (e: PointerEvent): void => { if (t && Math.hypot(e.clientX - x, e.clientY - y) > 8) { clearTimeout(t); t = 0 } }
  const up = (): void => { clearTimeout(t); t = 0 }
  const click = (e: MouseEvent): void => { if (fired) { fired = false; e.stopPropagation(); e.preventDefault() } }
  const ctx = (e: Event): void => e.preventDefault()
  target.addEventListener('pointerdown', down)
  target.addEventListener('pointermove', move)
  target.addEventListener('pointerup', up)
  target.addEventListener('pointercancel', up)
  target.addEventListener('click', click, true)
  target.addEventListener('contextmenu', ctx)
  return () => {
    clearTimeout(t)
    target.removeEventListener('pointerdown', down)
    target.removeEventListener('pointermove', move)
    target.removeEventListener('pointerup', up)
    target.removeEventListener('pointercancel', up)
    target.removeEventListener('click', click, true)
    target.removeEventListener('contextmenu', ctx)
  }
}
