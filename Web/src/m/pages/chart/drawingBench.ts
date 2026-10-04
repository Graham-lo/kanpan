/* 手机网页版 · 横屏画线工作台（照 iOS Main/LandscapeChrome.swift、MainScreen.landscapeBody、
 * Drawing/DrawingBar.swift 的 DrawingDock / DrawingSelectionBar / DrawingMoreButton / 样式表 / 画线列表、
 * Drawing/DrawingToolPicker.swift、Alerts/LineAlert.swift 的画线提醒胶囊）
 *
 * 横屏的整页：左边一列周期栏（52 宽）｜ 中间一列 [品种胶囊行、选中栏、图、画线条] ｜ 不在画线时右边一列「画线 / 竖屏」。
 * 画线条（46 高、raised 底、顶上一根发丝线）：工具 · 面板上的十二把（横滚）· 撤销（能重做才出重做）· 更多 · 完成。
 * 选中一条线：图上方多一行选中栏——能设提醒的线左边一颗「跌到 X 叫我」胶囊（点了挂 / 摘画线提醒），右边样式、复制、删除。
 *
 * 线从全 app 共享的那本（m/app/drawings.ts 的 drawingBook）来；增删改、撤销由本自己落盘记账。
 * 工具偏好（磁吸、连续画、各工具的样式与画法）改了写回 drawingBook.preferences 并 saveDrawingPreferences()；
 * 同步换进来的偏好由行情页调 pullPreferences() 拷回控制器。
 */
import { st, save } from '../../app/store'
import { INTERVALS, type IntervalId } from '../../app/prefs'
import { drawingBook, saveDrawingPreferences } from '../../app/drawings'
import { alertLinesOf } from '../../app/lineAlerts'
import { batchRoom } from '../../model/sharePreview'
import type { ChartHandle } from '../../chart'
import type { DrawingController } from '../../chart/view.drawing'
import { DrawKind, DRAWING_TEXT_LIMIT, isDrawingKind, type Drawing, type DrawingKind } from '../../chart/draw/drawing'
import { styleOf, styleEquals } from '../../chart/draw/archive'
import { AlertGeometry, alertLinePrice } from '../../chart/draw/alert'
import { graphemeCount } from '../../chart/draw/fmt'
import { INTERVAL_SHORT } from '../../chart/series'
import { S } from '../../../market'
import { baseOf, drawingIdOf, MARKET, newAlertId, type Alert } from '../../../alerts/shape'
import { activeAlerts, alertsReplaced, deleteAlert, onAlertsChange } from '../../model/alerts'
import { grouped, fmtPrice } from '../../model/rowText'
import { openSheet, confirmDialog, type Sheet } from '../../ui/sheet'
import { swipeRow, deleteAction } from '../../ui/swipeDelete'
import { toast } from '../../ui/toast'
import { el, esc } from '../../ui/dom'
import { icon } from '../../ui/icons'
import { railIntervals, deleteDrawingById, safeHexColor, mergeStyleEdits } from './logic'
import { splitPair } from './header'
import { openSymbolPicker, colorControlHTML, syncColorControl } from './panels'

// ───────────────────────────── 工具记号（照 DrawingGlyph.swift，24 格取景）

const G = (inner: string, size: number): string =>
  `<svg class="cp-kg" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${inner}</svg>`
const L = (x1: number, y1: number, x2: number, y2: number, dash = ''): string => `<path d="M${x1} ${y1}L${x2} ${y2}"${dash ? ` stroke-dasharray="${dash}"` : ''}/>`
const D = (x: number, y: number, r = 1.8): string => `<circle cx="${x}" cy="${y}" r="${r}" fill="currentColor" stroke="none"/>`
const B = (x1: number, y1: number, x2: number, y2: number, fill = 0): string =>
  `<rect x="${Math.min(x1, x2)}" y="${Math.min(y1, y2)}" width="${Math.abs(x2 - x1)}" height="${Math.abs(y2 - y1)}"${fill ? ` fill="currentColor" fill-opacity="${fill}"` : ''}/>`
const A = (x: number, y: number, dx: number, dy: number): string => {
  const len = Math.max(Math.hypot(dx, dy), 0.001), ux = dx / len, uy = dy / len, w = 2.4, back = 3.4
  const p = (a: number, b: number): string => `${+a.toFixed(2)} ${+b.toFixed(2)}`
  return `<path d="M${p(x, y)}L${p(x - ux * back - uy * w / 2, y - uy * back + ux * w / 2)}L${p(x - ux * back + uy * w / 2, y - uy * back - ux * w / 2)}Z" fill="currentColor" stroke="none"/>`
}
const Q = (x1: number, y1: number, cx: number, cy: number, x2: number, y2: number): string => `<path d="M${x1} ${y1}Q${cx} ${cy} ${x2} ${y2}"/>`

export function kindGlyph(k: DrawingKind, size = 22): string {
  let s = ''
  switch (k) {
    case 'hline': s = L(3, 12, 21, 12); break
    case 'vline': s = L(12, 3, 12, 21); break
    case 'trend': s = L(3, 19, 21, 5) + D(3, 19) + D(21, 5); break
    case 'ray': s = L(4, 19, 21, 5) + D(4, 19); break
    case 'hray': s = L(5, 12, 21, 12) + D(5, 12); break
    case 'extended': s = L(2, 20, 22, 6, '3 2.5') + L(7, 16.5, 17, 9.5) + D(7, 16.5) + D(17, 9.5); break
    case 'arrowLine': s = L(3, 19, 18, 7) + A(21, 4.6, 3, -2.4) + D(3, 19); break
    case 'crossLine': s = L(3, 12, 21, 12) + L(12, 3, 12, 21) + D(12, 12); break
    case 'rectangle': s = B(4, 6, 20, 18, 0.16); break
    case 'channel': s = L(3, 17, 21, 6) + L(3, 21, 21, 10); break
    case 'fibonacci': s = [4, 9, 14, 20].map(y => L(3, y, 21, y)).join('') + D(4.5, 20) + D(19.5, 4); break
    case 'fibExtension': s = L(3, 19, 8, 8) + L(8, 8, 12, 15) + L(12, 4, 21, 4, '3 2.5') + L(12, 10, 21, 10) + L(12, 18, 21, 18, '3 2.5'); break
    case 'measure': s = B(4, 5, 20, 19, 0.16) + L(12, 18, 12, 8) + A(12, 6.4, 0, -1); break
    case 'position': s = B(5, 5, 19, 12, 0.22) + B(5, 12, 19, 19, 0.1) + L(3, 12, 21, 12); break
    case 'note': s = L(6, 6, 18, 6) + L(12, 6, 12, 18) + L(9.5, 18, 14.5, 18); break
    case 'anchoredVWAP': s = D(4, 18.5) + Q(4, 18.5, 11, 10.5, 17, 9) + L(18.6, 9, 21.5, 9); break
    case 'fixedVolumeProfile': s = L(4, 3.5, 4, 20.5, '2 2') + L(20, 3.5, 20, 20.5, '2 2') + L(5, 7, 11, 7) + L(5, 10.5, 16, 10.5) + L(5, 14, 9, 14) + L(5, 17.5, 13, 17.5); break
    case 'anchoredVolumeProfile': s = L(5, 3.5, 5, 19.5) + D(5, 20.4) + L(6.5, 7, 12.5, 7) + L(6.5, 10.5, 17.5, 10.5) + L(6.5, 14, 10.5, 14) + L(6.5, 17.5, 14.5, 17.5); break
    default: s = L(3, 19, 21, 5)
  }
  return G(s, size)
}

const UNDO = `<svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M7.5 4.5 4 8l3.5 3.5"/><path d="M4.5 8H12a4 4 0 0 1 0 8H9"/></svg>`
const REDO = `<svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12.5 4.5 16 8l-3.5 3.5"/><path d="M15.5 8H8a4 4 0 0 0 0 8h3"/></svg>`
const COPY = `<svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" aria-hidden="true"><rect x="6.5" y="6.5" width="10" height="10" rx="2"/><path d="M13.5 6.5V5a1.5 1.5 0 0 0-1.5-1.5H5A1.5 1.5 0 0 0 3.5 5v7A1.5 1.5 0 0 0 5 13.5h1.5"/></svg>`

// ───────────────────────────── 提示语（照 DrawingFeedback.swift DrawingHints）

export function drawHint(tool: DrawingKind, placed: number): string {
  const t = DrawKind.title(tool)
  if (DrawKind.pointCount(tool) === 1) return '按住放置' + t
  const at = <T,>(list: T[]): T => list[Math.min(placed, list.length - 1)]
  switch (tool) {
    case 'position': return at(['按住放置入场价', '选择目标价', '选择止损价'])
    case 'fibExtension': return at(['按住拖动画起点 A', '选择回调点 B', '选择起算点 C'])
    case 'channel': return placed === 2 ? '选择通道宽度' : placed === 0 ? '按住拖动画' + t : '选择终点'
    case 'regression': return placed === 0 ? '圈住要拟合的那一段' : '选择这一段的终点'
    case 'xabcd': return at(['按住放置 X 点', '选择 A 点', '选择 B 点', '选择 C 点', '选择 D 点'])
    case 'abcd': return at(['按住放置 A 点', '选择 B 点', '选择 C 点', '选择 D 点'])
    case 'headShoulders': return at(['按住放置起点', '选择左肩', '选择左颈线点', '选择头部', '选择右颈线点', '选择右肩', '选择终点'])
    case 'elliottImpulse': return placed === 0 ? '按住放置 0 点' : `选择 ${placed} 浪终点`
    case 'elliottCorrection': return at(['按住放置 0 点', '选择 A 浪终点', '选择 B 浪终点', '选择 C 浪终点'])
    case 'pitchfork': return at(['按住放置柄部 A', '选择枢轴 B', '选择枢轴 C'])
    case 'fibChannel': return at(['按住拖动画基线起点', '选择基线终点', '选择通道宽度'])
    case 'triangle': return at(['按住放置第一个角', '选择第二个角', '选择第三个角'])
    case 'curve': return at(['按住放置起点', '选择终点', '拉出弯曲方向'])
    case 'callout': return placed === 0 ? '按住指向要标注的位置' : '选择气泡落点'
    default: return placed === 0 ? '按住拖动画' + t : '选择终点'
  }
}

// ───────────────────────────── 画线提醒（照 LineAlertModel / LineAlertPhrase）

export interface LinePhrase { target: string; distance: string | null }
/** 胶囊上那句话：线在现价上面「涨到」、下面「跌到」，两边都有就都说 */
export function linePhrase(targets: number[], current: number | null, dec: number): LinePhrase {
  const text = (p: number): string => grouped(fmtPrice(p, dec))
  if (!targets.length) return { target: '价格达到这条线', distance: null }
  if (current == null) return { target: targets.length === 1 ? `到 ${text(targets[0])}` : '价格达到这条线', distance: null }
  const above = targets.filter(x => x >= current).reduce<number | null>((m, x) => (m == null || x < m ? x : m), null)
  const below = targets.filter(x => x < current).reduce<number | null>((m, x) => (m == null || x > m ? x : m), null)
  const target = above != null && below != null ? `涨到 ${text(above)} 或跌到 ${text(below)}`
    : above != null ? `涨到 ${text(above)}` : below != null ? `跌到 ${text(below)}` : '价格达到这条线'
  const near = above != null && below == null ? above : below != null && above == null ? below : null
  const distance = near != null && current > 0 ? `还差 ${(Math.abs(near - current) / current * 100).toFixed(2)}%` : null
  return { target, distance }
}

const lineAlertOf = (sym: string, id: string): Alert | undefined =>
  activeAlerts(sym).find(a => a.kind === 'drawing' && a.drawingID === drawingIdOf(sym, id))

function toggleLineAlert(sym: string, d: Drawing): boolean {
  const had = lineAlertOf(sym, d.id)
  if (had) { deleteAlert(had.id); return false }
  const lines = alertLinesOf(d)
  if (!lines) return false
  const now = Date.now()
  const a: Alert = {
    id: newAlertId(), kind: 'drawing', market: MARKET, symbol: sym, lines, condition: 'touch', status: 'active', once: true,
    armedAt: now, firedAt: null, firedPrice: null, title: `${baseOf(sym)} 触到你画的${DrawKind.title(d.kind)}`, note: null,
    webhook: null, webhookText: null, drawingID: drawingIdOf(sym, d.id), reviewID: null, dueAt: null, rule: null, created: now,
  }
  st.alerts = [...st.alerts, a]
  save()
  alertsReplaced()
  return true
}

/**
 * 一组线一次挂上提醒（收下朋友的线时「加入提醒」，照 MainScreen.wireAlerts 的 onAcceptBatch）：
 * 已经挂着的不重复，挂不了提醒的几何跳过，提醒总数到上限就停。返回挂上了几条、是不是撞了上限。
 */
export function addLineAlerts(sym: string, list: readonly Drawing[]): { added: number; full: boolean } {
  const have = alertedLineIds(sym)
  const now = Date.now()
  const want = list.filter(d => !have.has(d.id) && alertLinesOf(d) != null)
  const room = batchRoom(st.alerts.filter(a => a.status === 'active').length, want.length)
  const made: Alert[] = want.slice(0, room).map(d => ({
    id: newAlertId(), kind: 'drawing', market: MARKET, symbol: sym, lines: alertLinesOf(d)!, condition: 'touch', status: 'active', once: true,
    armedAt: now, firedAt: null, firedPrice: null, title: `${baseOf(sym)} 触到你画的${DrawKind.title(d.kind)}`, note: null,
    webhook: null, webhookText: null, drawingID: drawingIdOf(sym, d.id), reviewID: null, dueAt: null, rule: null, created: now,
  }))
  if (made.length) {
    st.alerts = [...st.alerts, ...made]
    save()
    alertsReplaced()
  }
  return { added: made.length, full: room < want.length }
}

/** 这只品种上挂着没响的提醒的那几条线（画线自己的 id） */
export function alertedLineIds(sym: string): Set<string> {
  const pre = drawingIdOf(sym, '')
  return new Set(activeAlerts(sym).filter(a => a.kind === 'drawing' && a.drawingID?.startsWith(pre)).map(a => a.drawingID!.slice(pre.length)))
}

// 线挪了 / 删了时挂在上面的提醒跟着改 / 摘：对账与「见过的线」在壳层 m/app/lineAlerts.ts（不依赖行情页挂没挂）
export { reconcileLineAlerts, reconcileLineAlertsIn, resetSeenLines } from '../../app/lineAlerts'

// ───────────────────────────── 工作台

export interface BenchContext {
  chart: ChartHandle
  c: DrawingController
  symbol(): string
  interval(): IntervalId
  onPickInterval(iv: IntervalId): void
  onPickSymbol(sym: string): void
  /** 进 / 出画线（行情页据此切图的横屏模式） */
  onActive(on: boolean): void
}

/** 没设颜色的画线在样式页里显示的颜色（引擎默认金色） */
const DEFAULT_LINE_COLOR = '#D6A64F'
const WIDTHS = [1, 1.5, 2, 3]

export function createBench(ctx: BenchContext) {
  const { c } = ctx
  const rail = el('div', 'cp-rail')
  const line = el('div', 'cp-lline')
  const sel = el('div', 'cp-lsel')
  const dock = el('div', 'cp-dock')
  const tools = el('div', 'cp-trail')
  sel.hidden = true; dock.hidden = true
  let active = false
  let readout: string | null = null
  let sheet: Sheet | null = null

  // ---- 左：周期栏
  // 行情页每次刷新（换周期、行情推送）都叫它：周期和这一列没变就不重建——按钮在手指按下和抬起之间被换掉，
  // 那一下点击就没了。以前只有工作台整体重画（选中线、进出画线、转屏）才重画这一列，点了周期图换了、
  // 高亮还停在旧的那格，看着就是「点周期没反应」（2026-10-03 用户真机横屏画线）
  let railKey = ''
  const renderRail = (): void => {
    const cur = ctx.interval()
    const list = railIntervals(st.quickIntervals as IntervalId[], cur, INTERVALS as readonly IntervalId[])
    const key = `${cur}|${list.join(',')}`
    if (key === railKey) return
    railKey = key
    rail.innerHTML = `<div class="cp-rail-list">${list.map(iv =>
      `<button type="button" class="cp-rail-iv${iv === cur ? ' on' : ''}" data-iv="${iv}" aria-pressed="${iv === cur}">${esc(INTERVAL_SHORT[iv])}</button>`).join('')}</div>
      <button type="button" class="cp-rail-more" data-act="more" aria-label="更多周期">${icon('more', 18)}</button>`
  }
  rail.addEventListener('click', e => {
    const b = (e.target as Element).closest<HTMLElement>('button')
    if (!b) return
    if (b.dataset.iv) ctx.onPickInterval(b.dataset.iv as IntervalId)
    else if (b.dataset.act === 'more') openPeriods()
  })
  function openPeriods(): void {
    sheet?.close()
    sheet = openSheet(body => {
      const cur = ctx.interval()
      body.innerHTML = `<div class="cp-pgrid">${(INTERVALS as readonly IntervalId[]).map(iv =>
        `<button type="button" class="cp-pcell${iv === cur ? ' on' : ''}" data-iv="${iv}">${esc(INTERVAL_SHORT[iv])}</button>`).join('')}</div>`
      body.addEventListener('click', e => {
        const b = (e.target as Element).closest<HTMLElement>('[data-iv]')
        if (!b) return
        ctx.onPickInterval(b.dataset.iv as IntervalId)
        sheet?.close()
      })
    }, { title: '周期', detent: 'auto', className: 'cp-sheet', id: 'land-periods' })
  }

  // ---- 中上：品种胶囊 + 读数 / 提示
  line.innerHTML = `<button type="button" class="cp-lpill"></button><span class="cp-lread num"></span>`
  const pill = line.querySelector<HTMLButtonElement>('.cp-lpill')!
  const lread = line.querySelector<HTMLElement>('.cp-lread')!
  pill.addEventListener('click', () => {
    if (!active) return
    sheet?.close()
    sheet = openSymbolPicker({
      title: '换品种', id: 'land-symbol', current: ctx.symbol(),
      accept: sym => /USDT$|USDC$/.test(sym), onPick: sym => ctx.onPickSymbol(sym),
    })
  })
  let pillHTML = ''
  const renderQuote = (): void => {
    const sym = ctx.symbol()
    const s = S.symbols.get(sym)
    const { base, quote } = splitPair(sym)
    const up = (s?.pct ?? 0) >= 0
    const cls = s?.price != null ? (up ? 'up' : 'down') : ''
    // 每跳行情都会进来：拼出来一样就不重写
    const html = `<b>${esc(base)}</b><small>/${esc(quote)}</small>${active ? `<span class="cp-lchev">${icon('chevron', 12)}</span>` : ''}`
      + (s?.price != null ? `<b class="num ${cls}">${esc(grouped(fmtPrice(s.price, s.dec ?? 2)))}</b>` : '')
      + (s?.pct != null && Number.isFinite(s.pct) ? `<small class="num ${cls}">${s.pct >= 0 ? '+' : ''}${s.pct.toFixed(2)}%</small>` : '')
    if (html !== pillHTML) { pillHTML = html; pill.innerHTML = html }
    pill.disabled = !active
    pill.setAttribute('aria-label', active ? `换品种，当前 ${base}/${quote}` : `${base}/${quote}`)
    const hint = active && c.tool && readout == null ? drawHint(c.tool, c.placedAnchors) : null
    lread.textContent = readout ?? hint ?? ''
    lread.classList.toggle('hint', readout == null && hint != null)
  }

  // ---- 选中栏
  const selected = (): Drawing | null => (c.selected ? c.drawings.find(d => d.id === c.selected) ?? null : null)
  const renderSel = (): void => {
    const d = active ? selected() : null
    sel.hidden = !d
    if (!d) { sel.innerHTML = ''; return }
    const sym = ctx.symbol()
    let lead = `<span class="cp-lsel-name">${esc(DrawKind.title(d.kind) + (d.locked ? ' · 已锁定' : ''))}</span>`
    if (AlertGeometry.supports(d.kind)) {
      const lines = AlertGeometry.lines(d) ?? []
      const now = Date.now()
      const targets = lines.map(l => alertLinePrice(l, now)).filter((x): x is number => x != null && Number.isFinite(x))
      const s = S.symbols.get(sym)
      const on = !!lineAlertOf(sym, d.id)
      const ph = linePhrase(targets, s?.price ?? null, s?.dec ?? 2)
      lead = `<button type="button" class="cp-lchip${on ? ' on' : ''}" data-act="alert" aria-pressed="${on}">${icon('bell', 12)}<span>${esc(ph.target + (on ? ' 会叫你' : ' 叫我'))}</span>${on && ph.distance ? `<small class="num">· ${esc(ph.distance)}</small>` : ''}</button>`
    }
    sel.innerHTML = `${lead}<span class="cp-sp"></span>
      <button type="button" class="cp-sact" data-act="style">${icon('style', 20)}<span>样式</span></button>
      <button type="button" class="cp-sact" data-act="copy">${COPY}<span>复制</span></button>
      <button type="button" class="cp-sact cp-danger" data-act="delete">${icon('trash', 20)}<span>删除</span></button>`
  }
  sel.addEventListener('click', e => {
    const b = (e.target as Element).closest<HTMLElement>('[data-act]')
    const d = selected()
    if (!b || !d) return
    switch (b.dataset.act) {
      case 'alert': {
        const on = toggleLineAlert(ctx.symbol(), d)
        c.alerted = alertedIds()
        if (on) toast('线被碰到时会提醒你')
        renderSel()
        break
      }
      case 'style': openStyle(d); break
      case 'copy': c.duplicateSelected(); break
      case 'delete': c.deleteSelected(); break
    }
  })

  // ---- 画线条
  const renderDock = (): void => {
    const held = c.tool && !DrawKind.palette.includes(c.tool) ? DrawKind.title(c.tool) : null
    dock.innerHTML = `<button type="button" class="cp-dbtn cp-dtools${held ? ' on' : ''}" data-act="tools" aria-label="全部画线工具">${icon('draw', 20)}<span>${esc(held ?? '工具')}</span></button>
      <i class="cp-ddiv"></i>
      <div class="cp-dscroll">${DrawKind.palette.map(k => {
        const on = c.tool === k
        return `<button type="button" class="cp-dbtn${on ? ' on' : ''}" data-kind="${k}" aria-pressed="${on}">${kindGlyph(k, 22)}<span>${esc(DrawKind.title(k))}</span></button>`
      }).join('')}</div>
      <i class="cp-ddiv"></i>
      <button type="button" class="cp-dbtn cp-dicon" data-act="undo" aria-label="撤销"${c.canUndo ? '' : ' disabled'}>${UNDO}</button>
      ${c.canRedo ? `<button type="button" class="cp-dbtn cp-dicon" data-act="redo" aria-label="重做">${REDO}</button>` : ''}
      <button type="button" class="cp-dbtn" data-act="more" aria-label="更多画线设置">${icon('more', 20)}<span>更多</span></button>
      <i class="cp-ddiv"></i>
      <button type="button" class="cp-dfinish" data-act="finish">完成</button>`
  }
  let dockScroll = 0
  dock.addEventListener('scroll', e => { const t = e.target as HTMLElement; if (t.classList?.contains('cp-dscroll')) dockScroll = t.scrollLeft }, true)
  dock.addEventListener('click', e => {
    const b = (e.target as Element).closest<HTMLElement>('button')
    if (!b || b.hasAttribute('disabled')) return
    if (b.dataset.kind) { pick(b.dataset.kind as DrawingKind); return }
    switch (b.dataset.act) {
      case 'tools': openTools(); break
      case 'undo': c.undo(); break
      case 'redo': c.redo(); break
      case 'more': openMore(); break
      case 'finish': setActive(false); break
    }
  })
  function pick(k: DrawingKind): void {
    if (c.tool === k) { c.setTool(null); return }
    c.selected = null
    c.setTool(k)
    if (st.lastDrawTool !== k) { st.lastDrawTool = k; save() }
  }
  function openTools(): void {
    sheet?.close()
    sheet = openSheet(body => {
      const draw = (): void => {
        body.innerHTML = `<div class="cp-tgrid">${DrawKind.palette.map(k => {
          const on = c.tool === k || (c.tool == null && st.lastDrawTool === k)
          return `<button type="button" class="cp-tile${on ? ' on' : ''}" data-kind="${k}" aria-pressed="${on}">${kindGlyph(k, 30)}<span>${esc(DrawKind.title(k))}</span></button>`
        }).join('')}</div>`
      }
      draw()
      body.addEventListener('click', e => {
        const b = (e.target as Element).closest<HTMLElement>('[data-kind]')
        if (!b) return
        const k = b.dataset.kind as DrawingKind
        c.selected = null
        c.setTool(k)
        if (st.lastDrawTool !== k) { st.lastDrawTool = k; save() }
        sheet?.close()
      })
    }, { title: '画线', detent: 'large', className: 'cp-sheet', id: 'draw-tools' })
  }
  function openMore(): void {
    sheet?.close()
    sheet = openSheet(body => {
      const host = el('div', 'cp-panel')
      body.append(host)
      const draw = (): void => {
        const items = c.drawings
        const allHidden = items.length > 0 && items.every(d => d.hidden)
        const sw = (on: boolean, act: string, label: string): string =>
          `<button type="button" class="cp-switch${on ? ' on' : ''}" role="switch" aria-checked="${on}" aria-label="${label}" data-act="${act}"><i></i></button>`
        host.innerHTML = `<div class="cp-gt">画的时候</div><div class="cp-group">
            <div class="cp-row"><span class="cp-rn">吸附到 K 线</span>${sw(c.magnet, 'magnet', '吸附到 K 线')}</div>
            <div class="cp-row"><span class="cp-rn">连续画同一种线</span>${sw(c.continuous, 'continuous', '连续画同一种线')}</div></div>
          <div class="cp-gt">这个品种的所有画线</div><div class="cp-group">
            <div class="cp-row"><span class="cp-rn">全部隐藏</span>${sw(allHidden, 'hide', '全部隐藏')}</div>
            <button type="button" class="cp-row cp-tap" data-act="list"><span class="cp-rn">画线列表</span><span class="cp-meta num">${items.length} 条</span><span class="cp-chev">${icon('chevronRight', 12)}</span></button>
            <button type="button" class="cp-row cp-tap cp-dangerrow" data-act="clear"${items.length ? '' : ' disabled'}><span class="cp-rn">清空全部画线</span></button></div>`
      }
      draw()
      host.addEventListener('click', async e => {
        const b = (e.target as Element).closest<HTMLElement>('[data-act]')
        if (!b || b.hasAttribute('disabled')) return
        const p = drawingBook.preferences
        switch (b.dataset.act) {
          case 'magnet': c.magnet = !c.magnet; p.magnet = c.magnet; saveDrawingPreferences(); draw(); break
          case 'continuous': c.continuous = !c.continuous; p.continuous = c.continuous; saveDrawingPreferences(); draw(); break
          case 'hide': { const items = c.drawings; c.setAllHidden(!(items.length > 0 && items.every(d => d.hidden))); draw(); break }
          case 'list': sheet?.close(); openList(); break
          case 'clear': {
            const ok = await confirmDialog({ title: '清空这个品种的全部画线？', message: '清空后可以撤销。', confirm: '清空画线', destructive: true })
            if (ok) { c.clear(); sheet?.close() }
            break
          }
        }
      })
    }, { title: '更多', detent: 'auto', className: 'cp-sheet cp-list', id: 'draw-more' })
  }
  function openList(): void {
    const swipes: { destroy(): void }[] = []
    let off: (() => void) | null = null
    sheet = openSheet(body => {
      const host = el('div', 'cp-panel cp-dlist')
      body.append(host)
      const draw = (): void => {
        swipes.splice(0).forEach(s => s.destroy())
        const items = c.drawings
        host.innerHTML = items.length ? `<div class="cp-group">${items.map(d => `<div class="cp-dl-row" data-id="${esc(d.id)}"><div class="m-sw-content cp-row">
            <button type="button" class="cp-dl-main" data-act="select">${kindGlyph(d.kind, 20)}<span class="cp-rn">${esc(DrawKind.title(d.kind) + (d.locked ? ' · 已锁定' : ''))}</span></button>
            <button type="button" class="cp-textbtn" data-act="eye" aria-label="${d.hidden ? '显示画线' : '隐藏画线'}">${d.hidden ? '显示' : '隐藏'}</button></div></div>`).join('')}</div>`
          : '<div class="cp-empty">还没有画线</div>'
        host.querySelectorAll<HTMLElement>('.cp-dl-row').forEach(row => {
          swipes.push(swipeRow(row, { trailing: [deleteAction(() => deleteDrawingById(c, row.dataset.id!))], brick: 'flush' }))
        })
      }
      draw()
      const prev = c.onChanged
      off = () => { c.onChanged = prev }
      c.onChanged = items => { prev?.(items); if (!sheet?.closed) draw() }
      host.addEventListener('click', e => {
        const b = (e.target as Element).closest<HTMLElement>('[data-act]')
        const row = b?.closest<HTMLElement>('.cp-dl-row')
        if (!b || !row) return
        const d = c.drawings.find(x => x.id === row.dataset.id)
        if (!d) return
        if (b.dataset.act === 'eye') c.updateDrawing({ ...d, hidden: !d.hidden })
        else { c.setTool(null); c.selected = d.id; sheet?.close() }
      })
    // 照 iOS 画线列表：页面底色上一张白卡（系统 List），半屏起、可拉满，半屏时图还能看
    }, { title: '画线列表', detent: 'medium', expandable: true, dim: 'large', className: 'cp-sheet cp-form', id: 'draw-list', onClose: () => { off?.(); swipes.forEach(s => s.destroy()) } })
  }
  function openStyle(orig: Drawing): void {
    sheet?.close()
    const item: Drawing = { ...orig, points: orig.points.slice(), levels: orig.levels.slice() }
    const original = styleOf(orig)
    let levelText = item.levels.join(', ')
    const parsedLevels = (): number[] | null => {
      const parts = levelText.split(/[,，\s]+/).filter(Boolean)
      if (!parts.length) return null
      const nums = parts.map(Number)
      return nums.every(Number.isFinite) ? nums : null
    }
    let host: HTMLElement
    const draw = (): void => {
      const cur = safeHexColor(item.color, DEFAULT_LINE_COLOR)
      const width = WIDTHS.reduce((m, w) => (Math.abs(w - item.lineWidth) < Math.abs(m - item.lineWidth) ? w : m), WIDTHS[0])
      const swaps = DrawKind.swaps(item.kind)
      // 照 iOS DrawingStyleEditor：颜色（取色圈 + 一排色卡）、粗细（四档样张）、换画法（同族几个字按钮，选中的墨色描边）
      host.innerHTML = `<div class="cp-gt">样式</div><div class="cp-group">
          ${colorControlHTML('颜色', cur, 'color', '1')}
          <div class="cp-row"><span class="cp-rn">粗细</span><div class="cp-widths">${WIDTHS.map(w =>
            `<button type="button" class="cp-wcell${w === width ? ' on' : ''}" data-act="width" data-w="${w}" aria-label="粗细 ${w}"><i style="height:${w}px"></i></button>`).join('')}</div></div>
          ${swaps.map(s => `<div class="cp-row cp-swaprow"><span class="cp-rn">${esc(s.title)}</span><div class="cp-swaps">${s.options.map(o =>
            `<button type="button" class="cp-wcell cp-swap${o.kind === item.kind ? ' on' : ''}" data-act="swap" data-k="${o.kind}">${esc(o.label)}</button>`).join('')}</div></div>`).join('')}
        </div>
        ${DrawKind.usesText(item.kind) ? `<div class="cp-gt">文字</div><div class="cp-group cp-textbox"><textarea rows="2" data-text="1" placeholder="写点什么">${esc(item.text)}</textarea><div class="cp-foot">最多 ${DRAWING_TEXT_LIMIT} 个字</div></div>` : ''}
        ${DrawKind.usesLevels(item.kind) ? `<div class="cp-gt">${item.kind === 'fibExtension' ? '扩展比例' : '回撤比例'}</div><div class="cp-group cp-textbox"><input class="cp-levels num" type="text" inputmode="decimal" data-levels="1" placeholder="0, 0.382, 0.5, 0.618, 1" value="${esc(levelText)}"></div>` : ''}`
    }
    sheet = openSheet((body, sh) => {
      host = el('div', 'cp-panel cp-editor')
      body.append(host)
      draw()
      host.addEventListener('click', e => {
        const b = (e.target as Element).closest<HTMLElement>('[data-act]')
        if (!b) return
        if (b.dataset.act === 'color') item.color = b.dataset.c!
        else if (b.dataset.act === 'width') item.lineWidth = +b.dataset.w!
        else if (b.dataset.act === 'swap' && isDrawingKind(b.dataset.k)) item.kind = b.dataset.k
        draw()
      })
      host.addEventListener('input', e => {
        const t = e.target as HTMLInputElement | HTMLTextAreaElement
        if (t.dataset.pick) {
          // 拖色盘时 input 事件一秒几十次：只改色块与高亮，不整块重写（重写会把正开着的取色器那个 input 拆掉）
          item.color = safeHexColor(t.value, DEFAULT_LINE_COLOR)
          syncColorControl(t as HTMLInputElement, item.color.slice(0, 7).toUpperCase())
        }
        else if (t.dataset.text) {
          let v = t.value
          while (graphemeCount(v) > DRAWING_TEXT_LIMIT) v = [...v].slice(0, -1).join('')
          if (v !== t.value) t.value = v
          item.text = v
        } else if (t.dataset.levels) levelText = t.value
      })
      const lead = sh.root.querySelector('.m-sheet-lead')
      if (lead) {
        const cancel = el('button', 'cp-cancel', '取消')
        cancel.type = 'button'
        cancel.addEventListener('click', () => sheet?.close())
        lead.replaceWith(cancel)
      }
    }, {
      title: DrawKind.title(orig.kind), noBack: true, detent: 'large', className: 'cp-sheet cp-form', id: 'draw-style',
      action: {
        title: '保存', run: () => {
          if (DrawKind.usesLevels(item.kind)) {
            const lv = parsedLevels()
            if (!lv) { toast('比例要用逗号隔开的数字'); return }
            item.levels = lv
          }
          // 按 id 取现在那条，只盖这次改过的样式字段：面板开着时同步挪了点 / 上了锁不被打开时的快照回滚，线删了就不写
          const next = mergeStyleEdits(c.drawings.find(d => d.id === orig.id), orig, item)
          if (!next) { sheet?.close(); return }
          c.updateDrawing(next)
          const p = drawingBook.preferences
          let prefs = false
          // 记成这一类的默认样式按「这次在面板里调成的样子」算，不夹带同步过来的别处改动
          if (!styleEquals(styleOf(item), original)) { p.styles[item.kind] = styleOf(item); c.styles = { ...p.styles }; prefs = true }
          if (p.rememberSwap(orig.kind, item.kind)) { c.variants = { ...p.variants }; prefs = true }
          if (prefs) saveDrawingPreferences()
          sheet?.close()
        },
      },
    })
  }

  // ---- 右：不在画线时的「画线 / 竖屏」
  tools.innerHTML = `<button type="button" class="cp-tr" data-act="draw">${icon('draw', 22)}<span>画线</span></button>
    <button type="button" class="cp-tr" data-act="portrait">${icon('landscape', 22)}<span>竖屏</span></button>`
  tools.addEventListener('click', e => {
    const b = (e.target as Element).closest<HTMLElement>('[data-act]')
    if (!b) return
    if (b.dataset.act === 'draw') setActive(true)
    else toast('把手机转回竖屏就回到行情')
  })

  // ---- 状态
  const alertedIds = (): Set<string> => alertedLineIds(ctx.symbol())
  function render(): void {
    renderRail(); renderQuote(); renderSel()
    if (active) {
      renderDock()
      const sc = dock.querySelector<HTMLElement>('.cp-dscroll')
      if (sc) sc.scrollLeft = dockScroll
    }
    dock.hidden = !active
    tools.hidden = active
  }
  function setActive(on: boolean): void {
    if (active === on) return
    active = on
    if (!on) { sheet?.close(); c.endDrawing(); c.setTool(null); c.selected = null }
    c.editable = on
    c.interactive = on
    ctx.onActive(on)
    render()
  }
  /** 云端换进来的偏好（或绑定之后第一次）拷回控制器 */
  function pullPreferences(): void {
    const p = drawingBook.preferences
    c.magnet = p.magnet
    c.continuous = p.continuous
    c.styles = { ...p.styles }
    c.variants = { ...p.variants }
  }
  const offAlerts = onAlertsChange(() => { c.alerted = alertedIds(); if (active) renderSel() })
  c.alerted = alertedIds()
  pullPreferences()
  c.editable = false
  c.interactive = false
  render()

  return {
    rail, line, sel, dock, tools,
    get active() { return active },
    setActive,
    render,
    renderRail,
    renderQuote,
    pullPreferences,
    refreshAlerts(): void { c.alerted = alertedIds() },
    setReadout(text: string | null): void { readout = text; renderQuote() },
    closeSheets(): void { sheet?.close() },
    destroy(): void { offAlerts(); sheet?.close() },
  }
}
export type Bench = ReturnType<typeof createBench>
