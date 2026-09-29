/* Hkline 手机网页版 · 左划删除（照 iOS DesignSystem/SwipeToDelete.swift）
 *
 * 用法：
 *   const s = swipeRow(rowEl, { trailing: [deleteAction(() => remove(sym))] })
 *   // 重绘整张表前：s.destroy()（或直接丢掉 DOM，没有全局监听要解）
 *
 * 行为逐条照 iOS：
 * - 两边都能挂：trailing 是左划（从右沿拉出来）露的那几颗，leading 是右划露的。先写的那颗贴着屏幕边，
 *   一边多颗时平分露出的宽度。
 * - 砖：flush（方砖、贴边，每颗 76）/ pill（圆角 14 的药丸、四周留 8，每颗 92）。
 * - 起手先判方向：手指挪过 8 点时 |dy| ≥ |dx| 就当场让给纵向滚动，这一趟不再管。
 * - 松手：越过 36 就吸附打开；滑到底（max(140, 行宽 × 60%)）直接触发那一边的第一颗；否则弹回。easeOut 0.16。
 * - 同一时刻只许一行开着：另一行一划开，这一行自己收回去；开着的时候点行里任何地方先收回，不当成点击。
 * - 没划开时砖整组不建出来（不是画成透明）。
 * - 破坏性动作：行先归位再调 run（删行的收拢交给调用方重绘）；非破坏性：滑回去再 run。
 */
import { el, esc } from './dom'

export interface SwipeAction {
  /** 标识（data-swipe="<id>"，测试用）；删除那颗叫 delete */
  id: string
  title: string
  /** 砖的底色（CSS 颜色，默认 var(--danger)） */
  fill?: string
  destructive?: boolean
  run: () => void
}

/** 标准的「删除」砖 */
export const deleteAction = (run: () => void, title = '删除'): SwipeAction =>
  ({ id: 'delete', title, fill: 'var(--danger)', destructive: true, run })

export interface SwipeOptions {
  trailing?: SwipeAction[]
  leading?: SwipeAction[]
  brick?: 'flush' | 'pill'
  /** 滑到底直接触发第一颗，默认 true */
  fullSwipe?: boolean
}

export interface SwipeHandle {
  close(animated?: boolean): void
  readonly isOpen: boolean
  destroy(): void
}

let openRow: SwipeHandle | null = null
/** 收回当前划开的那一行（滚动、切页时调用） */
export function closeOpenSwipe(): void { openRow?.close() }

/**
 * 把一行变成可划的：行里原有的子节点挪进 .m-sw-content（它带行底色、跟着手指走），
 * 砖画在后面的 .m-sw-bricks 里。行本身加 .m-sw-row（overflow hidden、touch-action pan-y）。
 * 行底色默认 var(--app)，调用方可以在行上设 --sw-bg 改。
 */
export function swipeRow(row: HTMLElement, o: SwipeOptions): SwipeHandle {
  const trailing = o.trailing ?? [], leading = o.leading ?? []
  const pill = o.brick === 'pill'
  const unit = pill ? 92 : 76
  const full = o.fullSwipe !== false
  const tReveal = unit * trailing.length, lReveal = unit * leading.length

  row.classList.add('m-sw-row')
  if (pill) row.classList.add('pill')
  const content = el('div', 'm-sw-content')
  content.append(...row.childNodes)
  const bricksT = el('div', 'm-sw-bricks trailing')
  const bricksL = el('div', 'm-sw-bricks leading')
  row.append(bricksL, bricksT, content)

  let offset = 0, side: 'leading' | 'trailing' = 'trailing', isOpen = false
  const width = (): number => Math.max(row.offsetWidth, 1)

  const one = (a: SwipeAction): HTMLElement => {
    const b = el('button', 'm-sw-brick', `<span class="m-sw-fill" style="background:${a.fill ?? 'var(--danger)'}"></span><span class="m-sw-text">${esc(a.title)}</span>`)
    b.type = 'button'; b.dataset.swipe = a.id; b.setAttribute('aria-label', a.title)
    b.addEventListener('click', e => { e.stopPropagation(); fire(a) })
    return b
  }
  const paint = (animate: boolean): void => {
    content.style.transition = animate ? 'transform 160ms cubic-bezier(0.2, 0.8, 0.3, 1)' : 'none'
    content.style.transform = offset ? `translate3d(${offset}px,0,0)` : ''
    // 没划开的那一边整组不建
    const wt = Math.max(0, -offset), wl = Math.max(0, offset)
    if (wt > 1 && trailing.length) {
      if (!bricksT.childElementCount) bricksT.append(...[...trailing].reverse().map(one))
      bricksT.style.transition = content.style.transition.replace('transform', 'width')
      bricksT.style.width = wt + 'px'
    } else if (!animate) { bricksT.replaceChildren(); bricksT.style.width = '0' }
    if (wl > 1 && leading.length) {
      if (!bricksL.childElementCount) bricksL.append(...leading.map(one))
      bricksL.style.transition = content.style.transition.replace('transform', 'width')
      bricksL.style.width = wl + 'px'
    } else if (!animate) { bricksL.replaceChildren(); bricksL.style.width = '0' }
    if (animate && offset === 0) {
      bricksT.style.width = '0'; bricksL.style.width = '0'
      setTimeout(() => { if (offset === 0) { bricksT.replaceChildren(); bricksL.replaceChildren() } }, 170)
    }
  }
  const setOpen = (v: boolean): void => {
    isOpen = v
    row.classList.toggle('m-sw-open', v)
    if (v) { if (openRow && openRow !== handle) openRow.close(); openRow = handle }
    else if (openRow === handle) openRow = null
  }
  const fire = (a: SwipeAction): void => {
    setOpen(false)
    offset = 0
    if (a.destructive) { paint(false); a.run() } else { paint(true); a.run() }
  }
  const anchor = (): number => !isOpen ? 0 : side === 'leading' ? lReveal : -tReveal

  // —— 手势：Pointer Events；行上 touch-action: pan-y，纵向让浏览器滚 ——
  let id = -1, x0 = 0, y0 = 0, decided: 'h' | 'v' | null = null, moved = false
  const onDown = (e: PointerEvent): void => {
    if (e.button !== 0 || (!trailing.length && !leading.length)) return
    id = e.pointerId; x0 = e.clientX; y0 = e.clientY; decided = null; moved = false
  }
  const onMove = (e: PointerEvent): void => {
    if (e.pointerId !== id) return
    const dx = e.clientX - x0, dy = e.clientY - y0
    if (!decided) {
      if (Math.hypot(dx, dy) < 8) return
      decided = Math.abs(dy) >= Math.abs(dx) ? 'v' : 'h'
      if (decided === 'h') { row.setPointerCapture(e.pointerId); if (openRow && openRow !== handle) openRow.close() }
    }
    if (decided !== 'h') return
    moved = true
    e.preventDefault()
    const far = width()
    const low = trailing.length ? -(full ? far : tReveal) : 0
    const high = leading.length ? (full ? far : lReveal) : 0
    offset = Math.min(high, Math.max(low, anchor() + dx))
    paint(false)
  }
  const onUp = (e: PointerEvent): void => {
    if (e.pointerId !== id) return
    id = -1
    if (decided !== 'h') return
    let end = offset
    if (!trailing.length) end = Math.max(end, 0)
    if (!leading.length) end = Math.min(end, 0)
    const threshold = Math.max(140, width() * 0.6)
    if (full && end < -threshold && trailing[0]) { fire(trailing[0]); return }
    if (full && end > threshold && leading[0]) { fire(leading[0]); return }
    if (end < -36 && trailing.length) { offset = -tReveal; side = 'trailing'; setOpen(true) }
    else if (end > 36 && leading.length) { offset = lReveal; side = 'leading'; setOpen(true) }
    else { offset = 0; setOpen(false) }
    paint(true)
  }
  const onCancel = (e: PointerEvent): void => { if (e.pointerId === id) { id = -1; if (decided === 'h') { offset = anchor(); paint(true) } } }
  // 划过或开着时的点击：先收回，不当成点击
  const onClickCapture = (e: MouseEvent): void => {
    if (moved) { moved = false; e.stopPropagation(); e.preventDefault(); return }
    if (isOpen && content.contains(e.target as Node)) { e.stopPropagation(); e.preventDefault(); handle.close() }
  }
  row.addEventListener('pointerdown', onDown)
  row.addEventListener('pointermove', onMove)
  row.addEventListener('pointerup', onUp)
  row.addEventListener('pointercancel', onCancel)
  row.addEventListener('click', onClickCapture, true)

  const handle: SwipeHandle = {
    get isOpen() { return isOpen },
    close(animated = true) { if (!offset && !isOpen) return; offset = 0; setOpen(false); paint(animated) },
    destroy() {
      if (openRow === handle) openRow = null
      row.removeEventListener('pointerdown', onDown)
      row.removeEventListener('pointermove', onMove)
      row.removeEventListener('pointerup', onUp)
      row.removeEventListener('pointercancel', onCancel)
      row.removeEventListener('click', onClickCapture, true)
    },
  }
  return handle
}
