/* Hkline 手机网页版 · 弹层（照 iOS DesignSystem/PanelChrome.swift 的 PanelSheet 与 Panels/PanelPresentation.swift）
 *
 * 四种，都挂在最上层 #m-layer，带遮罩：
 *   openSheet    底部半屏面板：顶上一根拖拽条；标题行左「‹」（amber，关或回上一层）+ 标题 + 灰副标题 + 右端一个字按钮；
 *                正文可滚。档位 medium（半屏）/ large（留出状态栏）/ auto（按内容高，封顶 large），
 *                拖标题行或在正文顶上往下拉可以换档或关掉。底色 raised。
 *                形状照 iOS 26 的系统 sheet：没撑满时四边各留 8、四角大圆角浮在屏幕上（与屏幕圆角同心），
 *                撑到 large 才贴住左右下三边、只留上圆角。键盘起来时整张面板坐到键盘上沿（visualViewport）。
 *   openPopover  盖在内容上的弹层：从 anchor 下沿展开（周期条「更多」这类），下方整片遮罩，点遮罩关。
 *   openMenu     锚在按钮上的下拉菜单（「…」），iOS 26 Menu 的样子：大圆角卡片、图标在字前。
 *   confirmDialog 居中确认框（删除 / 退出登录这类不可逆动作），返回 Promise<boolean>。
 *
 * 切页时壳会 closeAllSheets()；Esc 与系统返回（鸿蒙 / 安卓侧边返回、Safari 左沿右划，见 ./backStack）退最上面一层。
 */
import { el, esc, layer, reducedMotion, safeArea } from './dom'
import { icon, type IconName } from './icons'
import { onBack } from './backStack'

// ───────── 共用：一层一层叠 ─────────

/** 一层：close 关掉；back 是系统返回 / Esc 时做的事（面板推进去几层时先回上一层），没有就是 close */
interface Layer { close(): void; back?(): void; unback?: () => void }
const stack: Layer[] = []
function push(l: Layer): void {
  stack.push(l); wireKeys()
  l.unback = onBack(() => (l.back ?? l.close)())
}
function drop(l: Layer): void {
  const i = stack.indexOf(l)
  if (i >= 0) stack.splice(i, 1)
  l.unback?.(); l.unback = undefined
}

/** 不归这里画、但要排进这一摞的层（解释卡这类）：切页时一起收、Esc / 系统返回关最上面的。返回「已关掉」时调的注销函数 */
export function pushLayer(close: () => void): () => void {
  const l: Layer = { close }
  push(l)
  return () => drop(l)
}

let keysWired = false
function wireKeys(): void {
  if (keysWired) return
  keysWired = true
  addEventListener('keydown', e => { if (e.key === 'Escape' && stack.length) { e.preventDefault(); const t = stack[stack.length - 1]; (t.back ?? t.close)() } })
}

/** 关掉所有弹层（切页、切后台回来时用） */
export function closeAllSheets(): void { [...stack].reverse().forEach(l => l.close()) }
/** 现在有没有弹层开着 */
export const sheetOpen = (): boolean => stack.length > 0

// ───────── 底部面板 ─────────

export type Detent = 'medium' | 'large' | 'auto'

export interface SheetOptions {
  title?: string
  subtitle?: string
  /** 标题行右端那一个字按钮（如「新建」）；一页最多一个 */
  action?: { title: string; run: () => void }
  /** 起始档位，默认 medium */
  detent?: Detent
  /** 能不能被拖到 large，默认 true（detent 为 auto 时无效） */
  expandable?: boolean
  /** 模态（默认 true）：遮罩盖住背后、点遮罩关。false = 背后还能点（iOS backgroundInteraction），也不画遮罩 */
  modal?: boolean
  /** 什么时候压暗背后：always（默认，系统 sheet）/ large（照 PanelHost 的 backgroundInteraction upThrough medium：
   *  半屏时背后不暗、图照常看得见，点背后只收面板；撑满才压暗） */
  dim?: 'always' | 'large'
  /** 不画左上的「‹」（整页式的面板） */
  noBack?: boolean
  /** 关掉之后 */
  onClose?: () => void
  /** 加在面板根上的类名 */
  className?: string
  /** 测试 / 无障碍标识 */
  id?: string
}

export interface Sheet {
  root: HTMLElement
  /** 正文容器（可滚）；push 进去的下一层会换掉它的内容 */
  body: HTMLElement
  close(): void
  setTitle(title: string, subtitle?: string): void
  setDetent(d: Detent): void
  /** 推进下一层（「图表设置 › 更多设置」）：左上「‹」回上一层，不关面板 */
  push(title: string, build: (body: HTMLElement) => void, subtitle?: string): void
  /** 回上一层；已在最底层就关掉 */
  back(): void
  readonly closed: boolean
}

const vh = (): number => window.visualViewport?.height ?? innerHeight
/** 没撑满时四边留的空（iOS 26 浮起来的 sheet） */
export const SHEET_FLOAT = 8

/** 键盘（或别的系统条）从底下盖住了多少：布局视口底边到可视视口底边的距离；小于 40 当作没有（地址栏伸缩这类） */
export function keyboardInset(innerH: number, vvTop: number, vvH: number): number {
  const kb = Math.round(innerH - vvTop - vvH)
  return kb >= 40 ? kb : 0
}

/** 面板该多高。view = 可视视口高；kb > 0（键盘起来）时 medium 也按 large 给，免得正在填的框被压成一条缝 */
export function sheetHeight(d: Detent, o: { view: number; safeTop: number; content: number; kb?: number }): number {
  const large = Math.round(o.view - Math.max(o.safeTop, 20) - 10)
  if (d === 'auto') return Math.min(large - SHEET_FLOAT, Math.round(o.content))
  if (d === 'large' || (o.kb ?? 0) > 0) return large
  return Math.round(o.view * 0.52)
}

function detentPx(d: Detent, content: number, kb = 0): number {
  return sheetHeight(d, { view: vh(), safeTop: safeArea().top, content, kb })
}

function kbNow(): number {
  const v = window.visualViewport
  return v ? keyboardInset(innerHeight, v.offsetTop, v.height) : 0
}

/** 底部半屏面板 */
export function openSheet(build: (body: HTMLElement, sheet: Sheet) => void, opts: SheetOptions = {}): Sheet {
  const modal = opts.modal !== false
  const wrap = el('div', 'm-sheet-wrap' + (modal ? ' modal' : '') + (opts.dim === 'large' ? ' dim-large' : ''))
  const scrim = el('div', 'm-sheet-scrim')
  const root = el('div', 'm-sheet' + (opts.className ? ' ' + opts.className : ''))
  root.setAttribute('role', 'dialog')
  if (modal) root.setAttribute('aria-modal', 'true')
  if (opts.id) root.dataset.id = opts.id
  root.innerHTML = `<div class="m-sheet-grab" aria-hidden="true"><i></i></div>
    <div class="m-sheet-head">
      ${opts.noBack ? '<span class="m-sheet-lead"></span>' : `<button type="button" class="m-sheet-back" aria-label="返回">${icon('chevronLeft', 20)}</button>`}
      <div class="m-sheet-titles"><span class="m-sheet-title"></span><span class="m-sheet-sub"></span></div>
      ${opts.action ? `<button type="button" class="m-sheet-action">${esc(opts.action.title)}</button>` : ''}
    </div>
    <div class="m-sheet-body"></div>`
  wrap.append(scrim, root)
  const body = root.querySelector<HTMLElement>('.m-sheet-body')!
  const head = root.querySelector<HTMLElement>('.m-sheet-head')!
  const titleEl = root.querySelector<HTMLElement>('.m-sheet-title')!
  const subEl = root.querySelector<HTMLElement>('.m-sheet-sub')!
  const levels: { title: string; sub?: string; nodes: Node[]; scroll: number }[] = []
  let detent: Detent = opts.detent ?? 'medium'
  let closed = false

  const setTitle = (t: string, s?: string): void => {
    titleEl.textContent = t; subEl.textContent = s ?? ''; subEl.hidden = !s
    root.setAttribute('aria-label', t)
  }
  const layout = (): void => {
    const kb = kbNow()
    const content = root.querySelector<HTMLElement>('.m-sheet-grab')!.offsetHeight + head.offsetHeight + body.scrollHeight + 2
    root.style.height = detentPx(detent, content, kb) + 'px'
    // 键盘起来：整张面板坐到键盘上沿，贴边（与 large 同形）
    wrap.style.setProperty('--kb', kb + 'px')
    wrap.classList.toggle('kb', kb > 0)
    wrap.classList.toggle('large', detent === 'large' || kb > 0)
  }
  const sheet: Sheet = {
    root, body,
    get closed() { return closed },
    setTitle,
    setDetent(d) { detent = d; layout() },
    push(t, b, s) {
      levels.push({ title: titleEl.textContent || '', sub: subEl.textContent || undefined, nodes: [...body.childNodes], scroll: body.scrollTop })
      body.replaceChildren(); setTitle(t, s); b(body); body.scrollTop = 0
      root.classList.add('pushed')
    },
    back() {
      const l = levels.pop()
      if (!l) { sheet.close(); return }
      body.replaceChildren(...l.nodes); setTitle(l.title, l.sub); body.scrollTop = l.scroll
      root.classList.toggle('pushed', levels.length > 0)
    },
    close() {
      if (closed) return
      closed = true; drop(me)
      // 关掉就摘掉窗口上的 resize：它的闭包攥着整张面板的 DOM，留着就开一次漏一张（压测 200 次开关 +2 万节点）
      removeEventListener('resize', onResize)
      visualViewport?.removeEventListener('resize', onResize)
      visualViewport?.removeEventListener('scroll', onResize)
      wrap.classList.remove('in')
      root.style.transform = ''
      setTimeout(() => wrap.remove(), reducedMotion() ? 0 : 300)
      opts.onClose?.()
    },
  }
  const me: Layer = { close: () => sheet.close(), back: () => sheet.back() }

  setTitle(opts.title ?? '', opts.subtitle)
  root.querySelector<HTMLElement>('.m-sheet-back')?.addEventListener('click', () => sheet.back())
  if (opts.action) root.querySelector<HTMLElement>('.m-sheet-action')!.onclick = () => opts.action!.run()
  if (modal) scrim.addEventListener('click', () => sheet.close())
  build(body, sheet)
  layer().appendChild(wrap)
  push(me)
  layout()
  requestAnimationFrame(() => requestAnimationFrame(() => wrap.classList.add('in')))
  const onResize = (): void => { if (!closed && !dragging) layout() }
  addEventListener('resize', onResize)
  // 软键盘只改可视视口（iOS Safari、Chromium 默认的 resizes-visual），window 不发 resize
  visualViewport?.addEventListener('resize', onResize)
  visualViewport?.addEventListener('scroll', onResize)

  // —— 拖：标题行 / 拖拽条随便拖；正文只在滚到顶时往下拉才接手 ——
  const expandable = opts.expandable !== false && detent !== 'auto'
  let startY = 0, startH = 0, dy = 0, dragging = false, lastY = 0, lastT = 0, vel = 0
  const begin = (y: number): void => {
    startY = lastY = y; lastT = performance.now(); dy = 0; vel = 0; dragging = true
    startH = root.offsetHeight; root.classList.add('dragging')
  }
  const move = (y: number): void => {
    const now = performance.now()
    vel = (y - lastY) / Math.max(1, now - lastT); lastY = y; lastT = now
    dy = y - startY
    if (dy >= 0) root.style.transform = `translateY(${dy}px)`
    else if (expandable) { root.style.transform = ''; root.style.height = Math.min(detentPx('large', 0, kbNow()), startH - dy) + 'px' }
    else root.style.transform = `translateY(${dy / 6}px)` // 往上拉不动，给一点阻尼
  }
  const end = (): void => {
    if (!dragging) return
    dragging = false; root.classList.remove('dragging'); root.style.transform = ''
    const h = root.offsetHeight
    if (dy > 0 && (dy > h * 0.3 || vel > 0.6)) {
      if (detent === 'large' && expandable && dy < h * 0.5 && vel < 1.2) { detent = 'medium'; layout(); return }
      sheet.close(); return
    }
    if (dy < 0 && expandable && (-dy > 40 || vel < -0.5)) detent = 'large'
    layout()
  }
  const grabZone = [root.querySelector<HTMLElement>('.m-sheet-grab')!, head]
  grabZone.forEach(z => {
    z.addEventListener('pointerdown', e => {
      if ((e.target as Element).closest('button')) return
      z.setPointerCapture(e.pointerId); begin(e.clientY)
    })
    z.addEventListener('pointermove', e => { if (dragging) move(e.clientY) })
    z.addEventListener('pointerup', end)
    z.addEventListener('pointercancel', end)
  })
  let bodyY = 0, bodyArmed = false
  body.addEventListener('touchstart', e => { bodyY = e.touches[0].clientY; bodyArmed = body.scrollTop <= 0 }, { passive: true })
  body.addEventListener('touchmove', e => {
    const y = e.touches[0].clientY
    if (!dragging && bodyArmed && y - bodyY > 6 && body.scrollTop <= 0) begin(bodyY)
    if (dragging) { e.preventDefault(); move(y) }
    else if (y < bodyY) bodyArmed = false
  }, { passive: false })
  body.addEventListener('touchend', end)
  body.addEventListener('touchcancel', end)

  return sheet
}

// ───────── 盖在内容上的弹层 ─────────

export interface PopoverOptions {
  onClose?: () => void
  className?: string
  /** 遮罩从 anchor 下沿开始（默认）还是盖满全屏 */
  cover?: 'below' | 'full'
}
export interface Popover { root: HTMLElement; close(): void; readonly closed: boolean }

/** 从 anchor 下沿展开、盖在内容上的弹层（照 iOS IntervalGridPopover：带遮罩，点遮罩关） */
export function openPopover(anchor: HTMLElement, build: (root: HTMLElement, pop: Popover) => void, opts: PopoverOptions = {}): Popover {
  const r = anchor.getBoundingClientRect()
  const wrap = el('div', 'm-pop-wrap')
  const top = opts.cover === 'full' ? 0 : Math.round(r.bottom)
  wrap.style.setProperty('--pop-top', top + 'px')
  wrap.style.setProperty('--pop-anchor', Math.round(r.bottom) + 'px')
  const scrim = el('div', 'm-pop-scrim')
  const root = el('div', 'm-pop' + (opts.className ? ' ' + opts.className : ''))
  wrap.append(scrim, root)
  let closed = false
  const pop: Popover = {
    root,
    get closed() { return closed },
    close() {
      if (closed) return
      closed = true; drop(me)
      wrap.classList.remove('in')
      setTimeout(() => wrap.remove(), reducedMotion() ? 0 : 220)
      opts.onClose?.()
    },
  }
  const me: Layer = { close: () => pop.close() }
  scrim.addEventListener('click', () => pop.close())
  build(root, pop)
  layer().appendChild(wrap)
  push(me)
  requestAnimationFrame(() => requestAnimationFrame(() => wrap.classList.add('in')))
  return pop
}

// ───────── 下拉菜单 ─────────

export interface MenuItem {
  title: string
  icon?: IconName
  destructive?: boolean
  checked?: boolean
  disabled?: boolean
  /** 写到这一项按钮的 data-act 上（测试与脚本按它点） */
  act?: string
  run: () => void
}

/** 锚在按钮上的菜单（iOS Menu）：贴着 anchor 下沿、右对齐；null 画一条分隔 */
export function openMenu(anchor: HTMLElement, items: (MenuItem | null)[], onClose?: () => void): Popover {
  const r = anchor.getBoundingClientRect()
  const wrap = el('div', 'm-menu-wrap')
  const scrim = el('div', 'm-menu-scrim')
  const root = el('div', 'm-menu')
  root.setAttribute('role', 'menu')
  const right = Math.max(8, innerWidth - r.right)
  root.style.right = right + 'px'
  root.style.top = Math.round(r.bottom + 6) + 'px'
  root.style.transformOrigin = `calc(100% - ${Math.round(r.width / 2)}px) top`
  const leadCol = items.some(it => it && (it.icon || it.checked !== undefined))
  items.forEach(it => {
    if (!it) { root.appendChild(el('div', 'm-menu-sep')); return }
    // iOS 26：图标在字前；勾选项的勾占图标那一格（菜单里有任何一项带图标或勾，各行都留这一格对齐）
    const lead = it.checked ? icon('check', 15) : it.icon ? icon(it.icon, 18) : ''
    const b = el('button', 'm-menu-item' + (it.destructive ? ' danger' : '') + (it.checked ? ' checked' : ''),
      `${leadCol ? `<span class="m-menu-lead">${lead}</span>` : ''}<span class="m-menu-title">${esc(it.title)}</span>`)
    b.type = 'button'; b.setAttribute('role', 'menuitem'); b.disabled = !!it.disabled
    if (it.act) b.dataset.act = it.act
    b.onclick = () => { pop.close(); it.run() }
    root.appendChild(b)
  })
  wrap.append(scrim, root)
  let closed = false
  const pop: Popover = {
    root,
    get closed() { return closed },
    close() {
      if (closed) return
      closed = true; drop(me)
      wrap.classList.remove('in')
      setTimeout(() => wrap.remove(), reducedMotion() ? 0 : 180)
      onClose?.()
    },
  }
  const me: Layer = { close: () => pop.close() }
  scrim.addEventListener('click', () => pop.close())
  layer().appendChild(wrap)
  // 底下放不下就翻到上面
  const h = root.offsetHeight
  if (r.bottom + 6 + h > vh() - 12) { root.style.top = Math.max(12, r.top - 6 - h) + 'px'; root.style.transformOrigin = root.style.transformOrigin.replace('top', 'bottom') }
  push(me)
  requestAnimationFrame(() => wrap.classList.add('in'))
  return pop
}

// ───────── 居中确认框 ─────────

export interface ConfirmOptions {
  title: string
  message?: string
  /** 确认按钮文字，默认「确定」 */
  confirm?: string
  /** 取消按钮文字，默认「取消」 */
  cancel?: string
  /** 确认是破坏性动作（红字） */
  destructive?: boolean
}

/** 居中确认框（iOS alert 的样子）；点确认 resolve(true)，取消 / 遮罩 resolve(false) */
export function confirmDialog(o: ConfirmOptions): Promise<boolean> {
  return new Promise(resolve => {
    const scrim = el('div', 'm-alert-scrim')
    scrim.innerHTML = `<div class="m-alert" role="alertdialog" aria-modal="true" aria-label="${esc(o.title)}">
      <div class="m-alert-main"><div class="m-alert-title">${esc(o.title)}</div>${o.message ? `<div class="m-alert-msg">${esc(o.message)}</div>` : ''}</div>
      <div class="m-alert-btns"><button type="button" class="m-alert-cancel">${esc(o.cancel ?? '取消')}</button><button type="button" class="m-alert-ok${o.destructive ? ' danger' : ''}">${esc(o.confirm ?? '确定')}</button></div></div>`
    let done = false
    const finish = (v: boolean): void => {
      if (done) return
      done = true; drop(me)
      scrim.classList.remove('in')
      setTimeout(() => scrim.remove(), 200)
      resolve(v)
    }
    const me: Layer = { close: () => finish(false) }
    scrim.addEventListener('click', e => { if (e.target === scrim) finish(false) })
    scrim.querySelector<HTMLElement>('.m-alert-cancel')!.onclick = () => finish(false)
    scrim.querySelector<HTMLElement>('.m-alert-ok')!.onclick = () => finish(true)
    layer().appendChild(scrim)
    push(me)
    requestAnimationFrame(() => scrim.classList.add('in'))
  })
}
