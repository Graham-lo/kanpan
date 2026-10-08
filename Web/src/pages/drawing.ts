/* Hkline Web · 画线的页面这一层（图表页接线用；几何与绘制在 chart/drawTools.ts）
 *
 *   · 左侧工具栏按组：一组一个按钮，显示这一组上次用的那把；单击 = 用它，双击 = 连续画（按钮上一个小点），
 *     右键工具栏 / 右键图 / Esc 退出；组按钮右边的小箭头展开同组的工具
 *   · 选中画线：格子上沿居中出一条临时快捷条（当前色 + 最近两种色、调色板、粗细、线型、提醒、锁、删），
 *     拖动画线时淡出；改过的样式记到同族工具上，下一条同族的画线照这个来
 *   · ⌘C / ⌘V：复制选中的画线、贴回同一只品种（每贴一次往右下错开一点）
 *   · 方向键微移选中的画线：1 px，⇧ 10 px；松键才记一步撤销
 *   · 每只品种最多 500 条 / 2 MB，到了不再新建并提示
 */
import { st, save } from '../app/store'
import type { Drawing, DrawingType, TVChart } from '../chart/chart'
import { QUOTA, TOOL_GROUPS, cleanDrawColor, cleanDrawWidth, familyOf, groupOf, quotaOK, toolName, usesFill, usesLevels, usesText, type Dash } from '../chart/drawTools'
import { drawingAlertOf, drawingCanAlert, toggleDrawingAlert } from '../alerts/model'
import { askNotify } from '../alerts/panel'
import { $$, I, esc, tgt } from '../ui/dom'
import { toast, menu, closeMenu, type MenuItem } from '../ui/overlay'
import { ago } from '../util/clock'
import { applyPreset } from '../chart/drawPreset'

export interface DrawCell { chart: TVChart; el: HTMLElement }
export interface DrawHost {
  cells(): readonly DrawCell[]
  active(): DrawCell | undefined
  symbolOf(c: DrawCell): string
  drawings(symbol: string): Drawing[]
  /** 画线改了：记一步撤销、落盘、同步、刷新撤销按钮 */
  changed(c: DrawCell): void
  /** 工具栏垃圾桶：批量删除菜单（碰撤销栈与指标，在图表页做） */
  clearMenu(btn: HTMLElement): void
  toggleHide(): void
  /** 工具栏「锁定全部画线」：每只品种的画线一起锁 / 解锁，并把锁后的样子记成撤销的基准 */
  lockAll(on: boolean): void
}
let host: DrawHost
export function installDrawing(h: DrawHost): void { host = h }

const uid = (): string => 'd' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6)

// ------------------------------------------------------------ 工具与连续画
let tool: DrawingType | null = null
let sticky = false
export const drawTool = (): DrawingType | null => tool
export const drawSticky = (): boolean => sticky

/** 选工具（null = 回到光标）；连续画只由双击打开，换工具、回光标都关掉 */
export function selectTool(t: DrawingType | 'cursor' | null, keepSticky = false): void {
  tool = t === 'cursor' ? null : t
  if (!tool || !keepSticky) sticky = false
  if (tool) { const g = groupOf(tool); if (g && st.toolLast[g.id] !== tool) { st.toolLast[g.id] = tool; save() } }
  host.cells().forEach(c => c.chart.setTool(tool))
  renderDrawbar()
}
/** 画完一条（图上回调）：连续画时工具留着、不选中新画的那条；否则回光标 */
export function toolDone(c: DrawCell, d: Drawing): void {
  if (sticky && d.type !== 'measure') { c.chart.selected = null; return }
  selectTool(null)
}

const current = (gid: string): DrawingType => {
  const g = TOOL_GROUPS.find(x => x.id === gid)!
  const last = st.toolLast[gid] as DrawingType | undefined
  return last && g.tools.some(x => x[0] === last) ? last : g.tools[0][0]
}

/** 展开箭头：4 × 7 的小三角（细，不抢图标） */
const CHEV = '<svg class="chev" viewBox="0 0 4 7" aria-hidden="true"><path d="M.6.6 3.2 3.5.6 6.4" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/></svg>'

export function renderDrawbar(): void {
  const bar = $$('#drawbar')[0]; if (!bar) return
  bindFlyHover(bar)
  const btn = (t: DrawingType, all: string, name: string, kbd: string) => {
    const on = tool === t
    return `<button class="ibtn" data-tool="${t}" data-tools="${all}" aria-label="${esc(name)}" data-tip="${esc(name)}${on && sticky ? '（连续画中，右键或 Esc 退出）' : '（双击连续画）'}" data-kbd="${kbd}" data-tip-side="right" aria-pressed="${on}">${I('draw:' + t)}${on && sticky ? '<span class="sticky-dot" aria-hidden="true"></span>' : ''}</button>`
  }
  const scroll = bar.scrollTop
  bar.innerHTML = `<button class="ibtn" data-tool="cursor" aria-label="十字光标" data-tip="十字光标" data-kbd="Esc" data-tip-side="right" aria-pressed="${!tool}">${I('cursor')}</button><div class="grp-sep"></div>` +
    TOOL_GROUPS.map(g => {
      const t = current(g.id), meta = g.tools.find(x => x[0] === t)!
      const all = g.tools.map(x => x[0]).join(' ')
      const open = flyGid === g.id && flyEl?.isConnected
      return `<div class="tool-grp${g.tools.some(x => x[0] === tool) ? ' has-tool' : ''}${open ? ' fly-open' : ''}" data-grp="${g.id}">${btn(t, all, meta[1], meta[2])}${g.tools.length > 1 ? `<button class="fly-chev" data-fly="${g.id}" aria-label="${g.name}：全部工具" aria-haspopup="menu" aria-expanded="${!!open}">${CHEV}</button>` : ''}</div>`
    }).join('') +
    `<div class="grp-sep"></div>
    ${btn('measure', 'measure', toolName('measure'), '⇧ 拖')}
    <button class="ibtn" data-dact="magnet" aria-label="磁吸" data-tip="磁吸：贴到最近的开高低收（按住 ⌘ 临时反过来）" data-tip-side="right" aria-pressed="${st.magnet}">${I('magnet')}</button>
    <button class="ibtn" data-dact="lock" aria-label="锁定画线" data-tip="锁定全部画线" data-tip-side="right" aria-pressed="${st.drawLocked}">${I('lock')}</button>
    <button class="ibtn" data-dact="hide" aria-label="隐藏画线" data-tip="隐藏全部画线" data-kbd="⌘ ⌥ H" data-tip-side="right" aria-pressed="${st.drawHidden}">${I(st.drawHidden ? 'eyeOff' : 'eye')}</button>
    <div class="spacer"></div>
    <button class="ibtn" data-dact="clear" aria-label="删除" data-tip="删除画线 / 指标" data-tip-side="right" aria-haspopup="menu">${I('trash')}</button>`
  bar.scrollTop = scroll
}

// 展开整组：点右沿的箭头条，或鼠标停在箭头条上（120 ms）就展开；菜单紧贴工具栏右沿、和这一组的按钮顶对齐
let flyGid: string | null = null
let flyEl: HTMLElement | null = null
let hoverTimer = 0
function bindFlyHover(bar: HTMLElement): void {
  if (bar.dataset.flyHover) return
  bar.dataset.flyHover = '1'
  bar.addEventListener('mouseover', e => {
    const b = tgt(e).closest<HTMLElement>('.fly-chev')
    clearTimeout(hoverTimer)
    if (!b?.dataset.fly || (flyGid === b.dataset.fly && flyEl?.isConnected)) return
    const gid = b.dataset.fly
    hoverTimer = window.setTimeout(() => { if (b.isConnected && b.matches(':hover')) flyout(b, gid) }, 120)
  })
  bar.addEventListener('mouseleave', () => clearTimeout(hoverTimer))
  // 列太矮在滚动时，展开着的菜单不再对得上那一组：收起
  bar.addEventListener('scroll', () => { if (flyEl?.isConnected) closeMenu() }, { passive: true })
}
function markFly(gid: string | null): void {
  $$<HTMLElement>('#drawbar .tool-grp').forEach(g => {
    const on = g.dataset.grp === gid
    g.classList.toggle('fly-open', on)
    g.querySelector('.fly-chev')?.setAttribute('aria-expanded', String(on))
  })
}

function flyout(b: HTMLElement, gid: string): void {
  const g = TOOL_GROUPS.find(x => x.id === gid); if (!g) return
  clearTimeout(hoverTimer)
  const r = (b.closest('.tool-grp') as HTMLElement).getBoundingClientRect()
  const bar = (b.closest('#drawbar') as HTMLElement | null)?.getBoundingClientRect() ?? r
  const items: MenuItem[] = [{ header: g.name }, ...g.tools.map(([t, name, kbd]): MenuItem => ({ icon: 'draw:' + t, label: name, sc: kbd, checked: tool === t, run: () => selectTool(t) }))]
  const m = menu(items, bar.right + 2, r.top - 4, { width: 285, returnFocus: b })
  m.classList.add('tool-fly')
  // 靠下的组：菜单往上挪到刚好放得下，不整块翻到按钮上面去
  m.style.top = Math.max(8, Math.min(r.top - 4, innerHeight - m.offsetHeight - 8)) + 'px'
  flyGid = gid; flyEl = m; markFly(gid)
  // 菜单怎么关的都行（点外面、Esc、选了一把）：关了就把这一组的展开态收掉
  new MutationObserver((_, ob) => { if (!m.isConnected) { ob.disconnect(); if (flyEl === m) { flyEl = null; flyGid = null; markFly(null) } } })
    .observe(document.body, { childList: true })
  // 双击菜单里的一项 = 连续画
  m.addEventListener('dblclick', e => {
    const mi = tgt(e).closest<HTMLElement>('.mi'); if (!mi) return
    const it = items[+(mi.dataset.k || 0)]
    if (it !== '-' && it.icon) { sticky = true; selectTool(it.icon.replace(/^draw:/, '') as DrawingType, true) }
  })
}

export function onDrawbarClick(e: MouseEvent): void {
  const b = tgt(e).closest<HTMLElement>('button'); if (!b) return
  if (b.dataset.fly) return flyout(b, b.dataset.fly)
  const t = b.dataset.tool as DrawingType | 'cursor' | undefined
  if (t) {
    if (t === 'cursor') return selectTool(null)
    if (e.detail >= 2) { sticky = true; selectTool(t, true); return } // 双击：连续画
    if (tool === t) return selectTool(null) // 再点一下 = 放下
    return selectTool(t)
  }
  const a = b.dataset.dact
  if (a === 'magnet') { st.magnet = !st.magnet; host.cells().forEach(c => c.chart.setMagnet(st.magnet)) }
  if (a === 'lock') { st.drawLocked = !st.drawLocked; host.lockAll(st.drawLocked); refreshQuick() }
  if (a === 'hide') return host.toggleHide()
  if (a === 'clear') return host.clearMenu(b)
  save(); renderDrawbar()
}
/** 右键工具栏：退出连续画 / 放下工具 */
export function onDrawbarContext(e: MouseEvent): void {
  e.preventDefault()
  if (tool) selectTool(null)
}

// ------------------------------------------------------------ 同族样式、上限
export const PALETTE = ['#2962FF', '#00BCD4', '#089981', '#4CAF50', '#FFEB3B', '#F59E0B', '#FF9800', '#F23645', '#E91E63', '#9C27B0', '#673AB7', '#787B86', '#131722', '#FFFFFF']
type NewStyle = Partial<Pick<Drawing, 'color' | 'width' | 'dash' | 'filled' | 'levels' | 'style'>>
/** 新画一条的样式：这把工具「存为默认」过就照默认（主字段 + 扩展样式，优先于同族记忆与出厂值），
 *  没有才用同族记住的颜色、粗细、线型 */
export function styleFor(t: DrawingType): NewStyle {
  const p = st.drawDefaults[t]
  if (p) {
    const d: Drawing = { id: '', type: t, pts: [] }
    applyPreset(d, p)
    const out: NewStyle = { color: d.color, width: d.width }
    if (d.dash) out.dash = d.dash
    if (d.filled === false) out.filled = false
    if (d.levels) out.levels = d.levels
    if (d.style) out.style = d.style
    return out
  }
  const s = st.drawStyles[familyOf(t)]
  return s ? { color: s.color, width: s.width, dash: s.dash } : {}
}
/** 用默认 / 同族样式新建一条（右键画水平线、订单流「在这里画线」） */
export function newDrawing(type: DrawingType, pts: Drawing['pts']): Drawing {
  const s = styleFor(type)
  const d: Drawing = { id: uid(), type, pts, color: s.color || st.drawColor, width: s.width || 2 }
  if (s.dash) d.dash = s.dash
  if (s.filled === false) d.filled = false
  if (s.levels) d.levels = s.levels
  if (s.style) d.style = s.style
  return d
}
let lastQuotaToast = 0
/** 这只品种还能不能再加 add；不能就提示（2 秒内只提示一次） */
export function canAdd(symbol: string, add: Drawing[]): boolean {
  if (quotaOK(host.drawings(symbol), add)) return true
  if (ago(lastQuotaToast) > 2000) {
    lastQuotaToast = Date.now()
    toast(`${symbol} 的画线到上限了`, `每只品种最多 ${QUOTA.count} 条（${QUOTA.bytes / 1024 / 1024} MB），先删掉一些再画`, 'info', 4000)
  }
  return false
}
function remember(d: Drawing, patch: { color?: string; width?: number; dash?: Drawing['dash'] }): void {
  const fam = familyOf(d.type)
  const cur = { ...(st.drawStyles[fam] ?? {}) }
  if (patch.color) {
    cur.color = patch.color
    st.recentColors = [patch.color, ...st.recentColors.filter(c => c.toUpperCase() !== patch.color!.toUpperCase())].slice(0, 3)
  }
  if (patch.width) cur.width = patch.width
  if ('dash' in patch) { if (patch.dash) cur.dash = patch.dash; else delete cur.dash }
  st.drawStyles[fam] = cur
}

// ------------------------------------------------------------ 选中快捷条
let quick: { d: Drawing; c: DrawCell; el: HTMLElement } | null = null
export const quickTarget = (): { d: Drawing; c: DrawCell } | null => quick

const DASH_SVG: Record<'solid' | Dash, string> = {
  solid: '<path d="M2 8h12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',
  dashed: '<path d="M2 8h12" stroke="currentColor" stroke-width="2" stroke-dasharray="3.5 2.5"/>',
  dotted: '<path d="M2.5 8h11.5" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-dasharray="0.1 3.6"/>',
}
const DASH_NAME: Record<'solid' | Dash, string> = { solid: '实线', dashed: '虚线', dotted: '点线' }
// 颜色 / 粗细都来自存档（会被老版本、手改写坏），拼进 HTML 之前一律先过白名单（cleanDrawColor / cleanDrawWidth）再转义
const widthSvg = (raw: unknown) => { const w = cleanDrawWidth(raw); return `<svg class="icon-16" viewBox="0 0 16 16"><rect x="2" y="${8 - w / 2}" width="12" height="${w}" rx="${w / 2}" fill="currentColor"/></svg>` }
const swatchBtn = (raw: unknown, pressed: boolean, tip: string) => { const c = esc(cleanDrawColor(raw)); return `<button class="swatch-btn" data-color="${c}" aria-label="${esc(tip)} ${c}" data-tip="${esc(tip)}" aria-pressed="${pressed}"><span class="swatch" style="background:${c}"></span></button>` }
const sameColor = (a: unknown, b: unknown): boolean => cleanDrawColor(a).toUpperCase() === cleanDrawColor(b).toUpperCase()

/** 这条画线能调哪些样式（多空持仓固定红绿；两把成交量分布只有框色；标注类没有线宽线型；刻度一族没有线型） */
function knobs(t: DrawingType): { color: boolean; width: boolean; dash: boolean; fill: boolean; text: boolean } {
  const fill = usesFill(t) && t !== 'position', text = usesText(t)
  if (t === 'position') return { color: false, width: false, dash: false, fill: false, text: false }
  if (t === 'fvp' || t === 'anchoredVolumeProfile') return { color: true, width: false, dash: false, fill: false, text: false }
  if (t === 'note' || t === 'callout' || t === 'flag' || t === 'priceLabel' || t === 'markerUp' || t === 'markerDown') return { color: true, width: false, dash: false, fill, text }
  return { color: true, width: true, dash: t !== 'fib' && !usesLevels(t), fill, text }
}
const FILL_SVG = (on: boolean) => `<svg class="icon-16" viewBox="0 0 16 16"><rect x="2.5" y="3.5" width="11" height="9" rx="2" fill="${on ? 'currentColor' : 'none'}" fill-opacity=".35" stroke="currentColor" stroke-width="1.5"/></svg>`

export function showQuick(d: Drawing | null, c?: DrawCell): void {
  if (!d || !c || d.type === 'measure' || !c.chart.editable()) { hideQuick(); return }
  let el = quick?.el
  if (!el) {
    el = document.createElement('div')
    el.className = 'draw-quick'; el.setAttribute('role', 'toolbar'); el.setAttribute('aria-label', '画线快捷条')
    el.addEventListener('click', quickClick)
    el.addEventListener('mousedown', e => e.stopPropagation())
  }
  if (el.parentElement !== c.el) c.el.appendChild(el)
  quick = { d, c, el }
  renderQuick()
}
export function hideQuick(): void {
  if (!quick) return
  quick.el.remove(); quick = null
}
/** 拖画线时快捷条淡出，松手回来并跟着换位置 */
export function quickFade(on: boolean): void {
  if (!quick) return
  quick.el.classList.toggle('fading', on)
  if (!on) placeQuick()
}
/** 画线列表换过（撤销、换品种、别处删掉）：选中的不在了就收起，还在就重画 */
export function refreshQuick(): void {
  if (!quick) return
  const { d, c } = quick
  if (!c.el.isConnected || c.chart.selected !== d || !c.chart.drawings.includes(d)) { hideQuick(); return }
  renderQuick()
}
function placeQuick(): void {
  if (!quick) return
  const top = quick.c.chart.selectedTop()
  // 画线贴着格子上沿时让到下面，别挡住它
  quick.el.classList.toggle('at-bottom', top != null && top < 64)
}
function renderQuick(): void {
  if (!quick) return
  const { d, c, el } = quick
  const k = knobs(d.type), locked = !!d.locked
  const cur = cleanDrawColor(d.color), w = cleanDrawWidth(d.width)
  const recent = st.recentColors.filter(x => !sameColor(x, cur)).slice(0, 2)
  const sym = host.symbolOf(c)
  const canAlert = drawingCanAlert(d.type), hasAlert = canAlert && !!drawingAlertOf(sym, d.id)
  const dash: 'solid' | Dash = d.dash === 'dashed' || d.dash === 'dotted' ? d.dash : 'solid'
  el.innerHTML = `<span class="dq-kind" data-tip="${esc(toolName(d.type))}">${I('draw:' + d.type, 'icon-16')}</span>` +
    (k.color ? `<span class="tb-sep"></span><button class="dq-color" data-q="palette" aria-label="颜色" data-tip="颜色" ${locked ? 'disabled' : ''} aria-haspopup="menu"><span class="swatch" style="background:${esc(cur)}"></span>${I('chevronDown', 'icon-12')}</button>
      ${recent.map(x => swatchBtn(x, false, '最近用过的颜色')).join('')}` : '') +
    (k.width ? `<span class="tb-sep"></span><button class="ibtn xs" data-q="width" aria-label="粗细 ${w} px" data-tip="粗细" ${locked ? 'disabled' : ''} aria-haspopup="menu">${widthSvg(w)}</button>` : '') +
    (k.dash ? `<button class="ibtn xs" data-q="dash" aria-label="线型：${DASH_NAME[dash]}" data-tip="线型" ${locked ? 'disabled' : ''} aria-haspopup="menu"><svg class="icon-16" viewBox="0 0 16 16">${DASH_SVG[dash]}</svg></button>` : '') +
    (k.fill ? `<button class="ibtn xs" data-q="fill" aria-pressed="${d.filled !== false}" aria-label="底色" data-tip="底色" ${locked ? 'disabled' : ''}>${FILL_SVG(d.filled !== false)}</button>` : '') +
    (k.text ? `<button class="ibtn xs" data-q="text" aria-label="改文字" data-tip="改文字" data-kbd="双击" ${locked ? 'disabled' : ''}>${I('pencil', 'icon-16')}</button>` : '') +
    `<span class="tb-sep"></span>
    ${canAlert ? `<button class="ibtn xs" data-q="alert" aria-pressed="${hasAlert}" aria-label="画线提醒" data-tip="价格碰到这条线时提醒我">${I('bellPlus', 'icon-16')}</button>` : ''}
    <button class="ibtn xs" data-q="lock" aria-pressed="${locked}" aria-label="${locked ? '解锁' : '锁定'}" data-tip="${locked ? '解锁这条' : '锁定这条（不能拖、不能改）'}">${I('lock', 'icon-16')}</button>
    <button class="ibtn xs" data-q="del" aria-label="删除" data-tip="删除" data-kbd="Delete">${I('trash', 'icon-16')}</button>`
  placeQuick()
}
function applyStyle(patch: { color?: string; width?: number; dash?: Drawing['dash'] }): void {
  if (!quick) return
  const { d, c } = quick
  if (d.locked) return
  if (patch.color) d.color = patch.color
  if (patch.width) d.width = patch.width
  if ('dash' in patch) { if (patch.dash) d.dash = patch.dash; else delete d.dash }
  remember(d, patch)
  c.chart.dirty = true
  host.changed(c)
  renderQuick()
}
function quickClick(e: MouseEvent): void {
  const b = tgt(e).closest<HTMLElement>('button'); if (!b || !quick || (b as HTMLButtonElement).disabled) return
  const { d, c } = quick
  if (b.dataset.color) return applyStyle({ color: b.dataset.color })
  const q = b.dataset.q
  const r = b.getBoundingClientRect(), below = r.bottom + 6
  if (q === 'palette') {
    const m = menu([{ header: '颜色' }], r.left, below, { width: 200, returnFocus: b })
    const grid = document.createElement('div'); grid.className = 'dq-palette'
    grid.innerHTML = PALETTE.map(x => swatchBtn(x, sameColor(x, d.color), '颜色')).join('')
    grid.addEventListener('click', ev => { const s = tgt(ev).closest<HTMLElement>('[data-color]'); if (!s) return; closeMenu(); applyStyle({ color: s.dataset.color }) })
    m.appendChild(grid)
    return
  }
  if (q === 'width') {
    menu([{ header: '粗细' }, ...[1, 2, 3, 4].map((w): MenuItem => ({ html: `<span class="dq-sample">${widthSvg(w)}</span>${w} px`, check: true, checked: cleanDrawWidth(d.width) === w, run: () => applyStyle({ width: w }) }))], r.left, below, { width: 160, returnFocus: b })
    return
  }
  if (q === 'dash') {
    menu([{ header: '线型' }, ...(['solid', 'dashed', 'dotted'] as const).map((k): MenuItem => ({ html: `<span class="dq-sample"><svg class="icon-16" viewBox="0 0 16 16">${DASH_SVG[k]}</svg></span>${DASH_NAME[k]}`, check: true, checked: (d.dash === 'dashed' || d.dash === 'dotted' ? d.dash : 'solid') === k, run: () => applyStyle({ dash: k === 'solid' ? undefined : k }) }))], r.left, below, { width: 160, returnFocus: b })
    return
  }
  if (q === 'fill') { d.filled = d.filled === false; if (d.filled) delete d.filled; c.chart.dirty = true; host.changed(c); renderQuick(); return }
  if (q === 'text') { const at = c.chart.textRectOf(d); if (at) editText(c, d, at); return }
  if (q === 'alert') { if (toggleDrawingAlert(host.symbolOf(c), d)) { toast('画线提醒已开', '价格碰到这条线时通知你', 'bell'); askNotify() } host.changed(c); renderQuick(); return }
  if (q === 'lock') { d.locked = !d.locked; host.changed(c); renderQuick(); return }
  if (q === 'del') { c.chart.selected = d; c.chart.deleteSelected() }
}

// ------------------------------------------------------------ 剪贴板
let clip: { symbol: string; d: Drawing; n: number } | null = null
/** ⌘C：选中了画线才接（没选中时让浏览器照常复制文字） */
export function copyDrawing(c: DrawCell): boolean {
  const d = c.chart.selected
  if (!d || d.type === 'measure') return false
  clip = { symbol: host.symbolOf(c), d: structuredClone(d), n: 0 }
  toast(`已复制${toolName(d.type)}`, '⌘V 贴到这只品种的图上', 'check', 1500)
  return true
}
export function pasteDrawing(c: DrawCell): boolean {
  if (!clip || !c.chart.editable()) return false
  const s = host.symbolOf(c)
  if (s !== clip.symbol) { toast('画线只能贴回同一只品种', `复制的是 ${clip.symbol}`, 'info', 2400); return true }
  const d: Drawing = { ...structuredClone(clip.d), id: uid(), locked: false }
  delete d.alert
  if (!canAdd(s, [d])) return true
  clip.n++
  d.pts = c.chart.shiftPts(d.pts, 12 * clip.n, 12 * clip.n) // 每贴一次往右下错开一点，不和原来那条叠在一起
  host.drawings(s).push(d)
  c.chart.selected = d; c.chart.dirty = true
  host.changed(c)
  showQuick(d, c)
  return true
}

// ------------------------------------------------------------ 方向键微移
let nudging: DrawCell | null = null
export function nudge(c: DrawCell, key: string, shift: boolean): boolean {
  const step = shift ? 10 : 1
  const dx = key === 'ArrowLeft' ? -step : key === 'ArrowRight' ? step : 0
  const dy = key === 'ArrowUp' ? -step : key === 'ArrowDown' ? step : 0
  if (!c.chart.nudgeSelected(dx, dy)) return false
  nudging = c
  if (quick) placeQuick()
  return true
}
/** 松开方向键：这一串微移记成一步撤销 */
export function nudgeEnd(): void {
  if (!nudging) return
  const c = nudging; nudging = null
  host.changed(c)
}

// ------------------------------------------------------------ 原地改字（文字注释 / 气泡标注 / 旗标）
// 刚放下、双击、快捷条「改文字」都走这里：字块上原地出一个输入框，↵ 确定、Esc 取消、点别处也算确定；最多 60 个字
let editing: { c: DrawCell; d: Drawing; el: HTMLInputElement; done: boolean } | null = null
const TEXT_LIMIT = 60
function clipText(v: string): string {
  const seg = typeof Intl !== 'undefined' && 'Segmenter' in Intl ? [...new Intl.Segmenter('zh', { granularity: 'grapheme' }).segment(v)].map(x => x.segment) : [...v]
  return seg.slice(0, TEXT_LIMIT).join('')
}
export const textEditing = (): boolean => !!editing
export function editText(c: DrawCell, d: Drawing, at: { x: number; y: number; w: number; h: number }): void {
  endEdit(true)
  if (!c.chart.editable() || d.locked) return
  const cv = c.chart.canvas.getBoundingClientRect(), box = c.el.getBoundingClientRect()
  const el = document.createElement('input')
  el.className = 'draw-text-edit'; el.type = 'text'; el.value = d.text ?? ''; el.placeholder = '文字'
  el.setAttribute('aria-label', toolName(d.type) + '文字'); el.spellcheck = false; el.autocomplete = 'off'
  const w = Math.max(140, Math.min(320, at.w + 40)), h = Math.max(24, at.h + 6)
  const left = Math.max(0, Math.min(cv.left - box.left + at.x - 3, box.width - w - 4))
  el.style.cssText = `left:${left}px;top:${cv.top - box.top + at.y + at.h / 2 - h / 2}px;width:${w}px;height:${h}px;--draw-col:${cleanDrawColor(d.color)}`
  editing = { c, d, el, done: false }
  el.addEventListener('keydown', e => {
    e.stopPropagation()
    if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); endEdit(true) }
    else if (e.key === 'Escape') { e.preventDefault(); endEdit(false) }
  })
  el.addEventListener('input', () => { const v = clipText(el.value); if (v !== el.value) el.value = v })
  el.addEventListener('mousedown', e => e.stopPropagation())
  c.el.appendChild(el)
  // 刚放下时还在画布的按下 / 松开里：等这次事件走完（画布按下的默认动作会把焦点挪走）再聚焦，之后失焦才算「点别处确定」
  setTimeout(() => {
    if (editing?.el !== el) return
    el.focus(); el.select()
    el.addEventListener('blur', () => endEdit(true))
  }, 0)
}
/** 收起输入框；commit = 把字写回去（变了才记一步撤销、同步） */
export function endEdit(commit: boolean): void {
  const e = editing; if (!e || e.done) return
  e.done = true; editing = null
  const v = clipText(e.el.value.trim())
  e.el.remove()
  if (!commit || v === (e.d.text ?? '') || !e.c.chart.drawings.includes(e.d)) return
  if (v) e.d.text = v; else delete e.d.text
  e.c.chart.dirty = true
  host.changed(e.c)
  refreshQuick()
}
