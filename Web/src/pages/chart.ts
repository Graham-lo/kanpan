/* Hkline Web · 图表页
 *
 * 交互原则（和手机端刻意不同）：
 *   · 鼠标悬停就是查看：十字线、图例、术语解释都跟着指针走，不用先点
 *   · 右键是「在这里做事」：在这个价位建提醒 / 画水平线 / 记一笔
 *   · 键盘直达：打字就是搜品种，打数字就是换周期，Alt+字母选画线工具，⌘Z 撤销
 *   · 画线不是一个模式：左侧工具栏常驻，选了工具就在当前图上画，画完回到光标
 *   · 大屏同时看：一 / 二 / 四图布局，十字线跨图按时间同步
 *
 * 布局槽位（给订单簿 / 主力订单流大屏版留的位置，本阶段是空容器）：
 *   深度梯子列 —— 价格轴与侧栏之间，开 240 / 关 0
 *   底部抽屉   —— 图表区下方，开 280 / 关 0
 *   侧栏小部件 —— 「自选」视图里按 st.slots.widgets 的顺序堆叠
 */
import { st, save, type CellCfg, type PanelId, type Layout } from '../app/store'
import { activeAlerts, createAlertAt, moveAlert, onAlertsChange, drawingAlertOf, drawingCanAlert, toggleDrawingAlert, reconcileDrawingAlerts, migrateDrawingFlags, alertLevel } from '../alerts/model'
import { SECOND_IVS, isSecondIv, isCustomIv, registerCustomIv, minutesIv, streamIvOf, startSeconds, onSecondsTick, secondBars, secondLastBar, customKlines, customTick, customBase } from '../chart/intervals'
import { VPVR_MODES } from '../chart/overlays'
import { renderAlertsPanel, alertsPanelClick, openCreateAlert, installAlerts, alertStreams, askNotify } from '../alerts/panel'
import { hooks, go } from '../app/shell'
import { $, $$, I, esc, tgt } from '../ui/dom'
import { toast, menu, menuFrom, closeMenu, menuOpen, dialog, dialogs, head, term, type MenuItem } from '../ui/overlay'
import { sym, pctText, cls, priceText, badge, clamp01, countdown, shTime, ratioText, ratioCls } from '../ui/common'
import { TVChart, type Drawing, type DrawingType, type ContextMenuInfo, type AlertLine } from '../chart/chart'
import { CATALOG, MAX_SUBS, type Bar, type IndicatorId, type IndParams, type SubId } from '../chart/calc'
import { fmt, fmtCompact, pad, sh, IV_MS } from '../util/format'
import {
  S, on, klines, loadUniverse, fetchDetail, detailOf, setStreams, streamName, wantMeta, marketCap,
  IV_LABEL, IV_SHORT, INTERVALS, TABS, kindName, sectorsOf, rankSearch, type Kind, type Sym,
} from '../market'

// ------------------------------------------------------------ 图表格子
interface Cell {
  el: HTMLElement
  host: HTMLElement
  idx: number
  chart: TVChart
  loadToken: number
  more: boolean
  noMore: boolean
}
const cells: Cell[] = []
export const allCells = (): readonly Cell[] => cells

type RangeDays = number | 'ytd' | 'all'
const RANGES: [string, string, RangeDays][] = [['1天', '1m', 1], ['5天', '5m', 5], ['1月', '30m', 30], ['3月', '2h', 91], ['6月', '4h', 182], ['今年', '1d', 'ytd'], ['1年', '1d', 365], ['全部', '1w', 'all']]

function cfg(cell: Cell | undefined): CellCfg { return st.cells[cell ? cell.idx : st.active] || st.cells[0] }
export const active = (): Cell | undefined => cells[st.active]

function metaFor(c: CellCfg) {
  const s = sym(c.symbol)
  return { symbol: c.symbol, iv: IV_MS[c.iv], title: c.symbol, sub: `· ${IV_LABEL[c.iv]} · 币安${kindName(s)}`, dec: s?.dec ?? 2, badge: badge(s) }
}

/** 图上画的提醒线：这只品种还在等的价格提醒（画线提醒由画线本身表示） */
function priceAlerts(symbol: string): AlertLine[] {
  return activeAlerts(symbol).filter(a => a.kind === 'price').flatMap(a => { const p = alertLevel(a); return p == null ? [] : [{ price: p, id: a.id, symbol: a.symbol, kind: a.kind, created: a.created }] })
}
/** 在价位 p 直接建一条价格提醒（点 / 拖价格轴、右键菜单） */
function quickAlert(symbol: string, p: number): void {
  const a = createAlertAt(symbol, p); if (!a) return
  toast('提醒已创建', a.title, 'bell'); askNotify()
}

function buildCells(): void {
  const n = ({ '1': 1, '2': 2, '2v': 2, '4': 4, '6': 6, '8': 8 } as Record<Layout, number>)[st.layout]
  const fill = ['ETHUSDT', 'SOLUSDT', 'XAUUSDT', 'BNBUSDT', 'XRPUSDT', 'DOGEUSDT', 'NVDAUSDT']
  while (st.cells.length < n) st.cells.push({ symbol: fill[st.cells.length - 1] || 'BTCUSDT', iv: st.cells[0].iv })
  st.active = Math.min(st.active, n - 1)
  const area = $('#chartArea'); area.dataset.layout = st.layout
  while (cells.length > n) { const c = cells.pop(); c?.chart.destroy(); c?.el.remove() }
  for (let i = cells.length; i < n; i++) cells.push(makeCell(i))
  cells.forEach((c, i) => c.el.classList.toggle('active', i === st.active))
  save(); refreshStreams()
}

function makeCell(i: number): Cell {
  const el = document.createElement('div')
  el.className = 'card chart-cell'
  el.innerHTML = `<div class="canvas-host"></div>
    <div class="cell-empty" hidden></div>
    <div class="cell-foot">
      <button class="foot-ic" data-act="layout" aria-label="图表布局" data-tip="图表布局">${I(LAYOUT_ICON[st.layout], 'icon-16')}</button>
      <button class="foot-ic" data-act="save" aria-label="保存图表截图" data-tip="保存图表截图" data-kbd="⌥ S">${I('camera', 'icon-16')}</button>
      <span class="tb-sep"></span>
      ${RANGES.map(([l, iv], k) => `<button data-range="${k}" data-tip="${l}：切到 ${IV_LABEL[iv]}，显示最近${l === '全部' ? '全部历史' : l === '今年' ? '今年以来' : l}">${l}</button>`).join('')}
      <div class="foot-right">
        <span class="clock num" data-tip="时间统一按上海时间显示，日线在北京时间 8:00 换日"></span>
        <span class="conn-dot" data-conn="${connState()}" data-tip="${CONN_TIP[connState()]}"></span>
        <span class="tb-sep"></span>
        <button data-act="log" data-tip="对数坐标" aria-pressed="false">对数</button>
        <button data-act="auto" data-tip="价格轴自动缩放（双击价格轴也可以恢复）" aria-pressed="true">自动</button>
      </div>
    </div>`
  $('#chartArea').appendChild(el)
  const host = $('.canvas-host', el)
  const cell = { el, host, idx: i, loadToken: 0, more: false, noMore: false } as unknown as Cell
  cell.chart = new TVChart(host, {
    onActivate: () => setActive(cell.idx),
    onNeedMore: () => { void loadMore(cell) },
    onCrosshairMove: t => { if (st.linkCross) cells.forEach(o => { if (o !== cell) o.chart.syncCrosshair(t) }) },
    onContextMenu: info => chartContextMenu(cell, info),
    onLegendAction: (id, act, btn) => legendAction(id, act, btn),
    onToolDone: () => selectTool(null),
    onSelectDrawing: d => showDrawProps(d, cell),
    onDrawingsChanged: () => drawingsChanged(cell),
    onAlertCreate: p => quickAlert(cfg(cell).symbol, p),
    onAlertMove: (a, p) => { if (a.id) moveAlert(a.id, p) },
    drawColor: () => st.drawColor,
    onAutoChange: v => { $('[data-act="auto"]', el)?.setAttribute('aria-pressed', String(v)) },
  })
  cell.chart.setIndicators(structuredClone(st.ind))
  if (st.params) for (const [k, p] of Object.entries(st.params)) cell.chart.params[k as IndicatorId] = structuredClone(p)
  cell.chart.setMagnet(st.magnet)
  cell.chart.setVpvrMode(st.vpvrMode)
  cell.chart.drawingsHidden = st.drawHidden
  el.addEventListener('click', e => {
    const t = tgt(e)
    const r = t.closest<HTMLElement>('[data-range]'); if (r) return applyRange(cell, +(r.dataset.range || 0))
    if (t.closest('[data-retry]')) { void retryLoad(cell); return }
    const a = t.closest<HTMLElement>('[data-act]')?.dataset.act
    if (a === 'layout') { layoutMenu(t.closest<HTMLElement>('[data-act]') as HTMLElement); return }
    if (a === 'save') { setActive(cell.idx); screenshot(); return }
    if (a === 'log') { cell.chart.setLog(!cell.chart.log); t.closest('[data-act]')?.setAttribute('aria-pressed', String(cell.chart.log)) }
    if (a === 'auto') cell.chart.setAuto(!cell.chart.auto)
  })
  void loadCell(cell)
  return cell
}

function showCellEmpty(cell: Cell, msg: string | null, quiet = false): void {
  const e = $('.cell-empty', cell.el); if (!e) return
  e.hidden = !msg
  if (msg) e.innerHTML = quiet ? `<div class="empty">${I('trades', 'icon-24')}<div>${esc(msg)}</div></div>` : `<div class="empty">${I('wifiOff', 'icon-24')}<div>${esc(msg)}</div><button class="btn secondary sm" style="margin-top:12px" data-retry>重试</button></div>`
}
/** 取 K 线：秒级从逐笔攒的内存里拿，自定义分钟从原生周期并，其余走交易所 */
async function barsFor(symbol: string, iv: string, endTime?: number): Promise<{ bars: Bar[]; ok: boolean; error?: string }> {
  if (isSecondIv(iv)) return { bars: endTime ? [] : secondBars(symbol, iv), ok: true }
  if (isCustomIv(iv)) return customKlines(symbol, iv, endTime)
  return klines(symbol, iv, endTime)
}

async function retryLoad(cell: Cell): Promise<void> {
  if (!S.live) { await loadUniverse(); if (S.live) { afterUniverse(); return } }
  void loadCell(cell)
}

async function loadCell(cell: Cell, then?: () => void): Promise<void> {
  const c = cfg(cell), token = ++cell.loadToken
  cell.noMore = false
  cell.chart.setDrawings(drawingsFor(c.symbol))
  const { bars, ok, error } = await barsFor(c.symbol, c.iv)
  if (token !== cell.loadToken) return
  if (ok && !bars.length && isSecondIv(c.iv)) showCellEmpty(cell, '等第一笔成交', true)
  else if (!ok || !bars.length) {
    cell.chart.setData([], metaFor(c))
    showCellEmpty(cell, ok ? `${c.symbol} 在这个周期上还没有 K 线` : `取不到 ${c.symbol} 的 K 线${error ? `（${error.split(' ')[0]}）` : ''}`)
  } else showCellEmpty(cell, null)
  cell.chart.setData(bars, metaFor(c))
  // 测量框是临时的，不进存档
  const ds = drawingsFor(c.symbol)
  for (let k = ds.length - 1; k >= 0; k--) if (ds[k].type === 'measure') ds.splice(k, 1)
  cell.chart.setDrawings(ds)
  cell.chart.setAlerts(priceAlerts(c.symbol))
  cell.chart.setStale(st.stale)
  then?.()
  if (cell.idx === st.active) { renderToolbar(); renderPanel() }
}

async function loadMore(cell: Cell): Promise<void> {
  if (cell.more || cell.noMore || !cell.chart.bars.length) return
  cell.more = true; cell.chart.loadingMore = true
  const c = cfg(cell), token = cell.loadToken
  const { bars, ok } = await barsFor(c.symbol, c.iv, cell.chart.bars[0].t)
  cell.more = false; cell.chart.loadingMore = false
  if (token !== cell.loadToken) return
  if (!ok) return
  if (!bars.length) { cell.noMore = true; return }
  cell.chart.prependData(bars)
}

function applyRange(cell: Cell, k: number): void {
  const [, iv, days] = RANGES[k], c = cfg(cell)
  const now = Date.now()
  let t0: number
  if (days === 'ytd') { const d = sh(now); t0 = Date.UTC(d.getUTCFullYear(), 0, 1) - 8 * 36e5 }
  else if (days === 'all') t0 = 0
  else t0 = now - days * 864e5
  const fit = () => { const b = cell.chart.bars; if (b.length) cell.chart.setVisibleRange(Math.max(t0, b[0].t), b[b.length - 1].t) }
  if (c.iv !== iv) { c.iv = iv; save(); void loadCell(cell, fit); refreshStreams(); renderToolbar() } else fit()
}

function setActive(i: number): void {
  if (i === st.active || i < 0) return
  st.active = i
  cells.forEach((c, k) => c.el.classList.toggle('active', k === i))
  save(); renderToolbar(); renderPanel(); refreshStreams()
}

export function openSymbol(symbol: string, cell: Cell | undefined = active()): void {
  if (!cell) return
  const c = cfg(cell)
  if (c.symbol === symbol) return
  c.symbol = symbol; save()
  if (st.linkSymbol && cells.length > 1) return linkAll(symbol)
  void loadCell(cell); refreshStreams(); renderToolbar(); renderPanel()
}

function setIv(iv: string, cell: Cell | undefined = active()): void {
  if (!cell) return
  const c = cfg(cell); if (c.iv === iv) return
  c.iv = iv; save(); void loadCell(cell); refreshStreams(); renderToolbar()
}

// ------------------------------------------------------------ 画线
export function drawingsFor(s: string): Drawing[] { return (st.drawings[s] ||= []) }
interface Snap { s: string; json: string }
const undoStack: Snap[] = [], redoStack: Snap[] = []
const lastSnap: Record<string, string> = {}
const snapOf = (s: string): string => JSON.stringify(drawingsFor(s).filter(d => d.type !== 'measure'))

export function drawingsChanged(cell: Cell): void {
  const s = cfg(cell).symbol
  const now = snapOf(s)
  const prev = lastSnap[s] ?? '[]'
  if (now !== prev) { undoStack.push({ s, json: prev }); redoStack.length = 0 }
  lastSnap[s] = now
  cells.forEach(c => { if (cfg(c).symbol === s) c.chart.dirty = true })
  reconcileDrawingAlerts(s, drawingsFor(s))
  save(); renderToolbar()
}
function restoreDrawings(s: string, json: string, toStack: Snap[]): void {
  toStack.push({ s, json: snapOf(s) })
  st.drawings[s] = JSON.parse(json) as Drawing[]; lastSnap[s] = json
  cells.forEach(c => { if (cfg(c).symbol === s) c.chart.setDrawings(st.drawings[s]) })
  reconcileDrawingAlerts(s, st.drawings[s])
  showDrawProps(null); save(); renderToolbar()
}
function undo(): void { const u = undoStack.pop(); if (!u) return; restoreDrawings(u.s, u.json, redoStack); toast('已撤销', '⌘⇧Z 重做', 'undo', 1800) }
function redo(): void { const u = redoStack.pop(); if (!u) return; restoreDrawings(u.s, u.json, undoStack) }

type ToolId = DrawingType | 'cursor'
const TOOLS: ([ToolId, string, string] | null)[] = [
  ['cursor', '十字光标', 'Esc'], null,
  ['trend', '趋势线', 'Alt T'], ['ray', '射线', ''], ['hline', '水平线', 'Alt H'], ['vline', '垂直线', 'Alt V'], null,
  ['rect', '矩形', 'Alt ⇧ R'], ['fib', '斐波那契回撤', 'Alt F'], ['measure', '测量（也可以按住 ⇧ 拖）', ''],
]
let tool: DrawingType | null = null
function selectTool(t: ToolId | null): void {
  tool = t === 'cursor' ? null : t
  cells.forEach(c => c.chart.setTool(tool))
  $$('#drawbar [data-tool]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.tool === (tool || 'cursor'))))
}
function renderDrawbar(): void {
  $('#drawbar').innerHTML = TOOLS.map(t => t ? `<button class="ibtn" data-tool="${t[0]}" aria-label="${t[1]}" data-tip="${t[1]}" data-kbd="${t[2]}" data-tip-side="right" aria-pressed="${t[0] === (tool || 'cursor')}">${I(t[0])}</button>` : '<div class="grp-sep"></div>').join('') +
    `<div class="grp-sep"></div>
    <button class="ibtn" data-dact="magnet" aria-label="磁吸" data-tip="磁吸：贴到最近的开高低收" data-tip-side="right" aria-pressed="${st.magnet}">${I('magnet')}</button>
    <button class="ibtn" data-dact="lock" aria-label="锁定画线" data-tip="锁定全部画线" data-tip-side="right" aria-pressed="${st.drawLocked}">${I('lock')}</button>
    <button class="ibtn" data-dact="hide" aria-label="隐藏画线" data-tip="隐藏全部画线" data-tip-side="right" aria-pressed="${st.drawHidden}">${I(st.drawHidden ? 'eyeOff' : 'eye')}</button>
    <div class="spacer"></div>
    <button class="ibtn" data-dact="clear" aria-label="清除画线" data-tip="清除这只品种的全部画线" data-tip-side="right">${I('trash')}</button>`
}
function toggleHideDrawings(): void {
  st.drawHidden = !st.drawHidden
  cells.forEach(c => { c.chart.drawingsHidden = st.drawHidden; c.chart.dirty = true })
  save(); renderDrawbar()
}
function onDrawbarClick(e: MouseEvent): void {
  const b = tgt(e).closest<HTMLElement>('button'); if (!b) return
  if (b.dataset.tool) return selectTool(b.dataset.tool as ToolId)
  const a = b.dataset.dact
  if (a === 'magnet') { st.magnet = !st.magnet; cells.forEach(c => c.chart.setMagnet(st.magnet)) }
  if (a === 'lock') { st.drawLocked = !st.drawLocked; Object.values(st.drawings).flat().forEach(d => { d.locked = st.drawLocked }) }
  if (a === 'hide') return toggleHideDrawings()
  if (a === 'clear') {
    const s = cfg(active()).symbol, n = drawingsFor(s).length
    if (!n) { toast('这只品种还没有画线', '', 'info', 1800); return }
    undoStack.push({ s, json: snapOf(s) }); redoStack.length = 0; st.drawings[s] = []; lastSnap[s] = '[]'
    cells.forEach(c => { if (cfg(c).symbol === s) c.chart.setDrawings(st.drawings[s]) })
    showDrawProps(null)
    toast(`已清除 ${n} 条画线`, '⌘Z 撤销', 'trash')
  }
  save(); renderDrawbar(); selectTool(tool); renderToolbar()
}

const SWATCHES = ['#2962FF', '#F23645', '#089981', '#F59E0B', '#9C27B0', '#131722']
let propsTarget: { d: Drawing; cell: Cell } | null = null
function showDrawProps(d: Drawing | null, cell?: Cell): void {
  propsTarget = d && cell ? { d, cell } : null
  const el = $('#drawProps'); if (!el) return
  el.classList.toggle('show', !!propsTarget)
  if (!d) { el.innerHTML = ''; return }
  const canAlert = drawingCanAlert(d.type)
  const hasAlert = !!drawingAlertOf(cfg(cell).symbol, d.id)
  el.innerHTML = SWATCHES.map(c => `<button class="swatch-btn" data-color="${c}" aria-label="颜色 ${c}" aria-pressed="${d.color === c}"><span class="swatch" style="background:${c}"></span></button>`).join('') +
    `<span class="tb-sep"></span>
    ${[1, 2, 3].map(w => `<button class="ibtn xs" data-w="${w}" aria-pressed="${(d.width || 2) === w}" data-tip="${w} px 粗细" aria-label="${w} px"><svg class="icon-16" viewBox="0 0 16 16"><rect x="2" y="${8 - w / 2}" width="12" height="${w}" rx="${w / 2}" fill="currentColor"/></svg></button>`).join('')}
    <span class="tb-sep"></span>
    ${canAlert ? `<button class="ibtn xs" data-p="alert" aria-pressed="${hasAlert}" aria-label="画线提醒" data-tip="价格碰到这条线时提醒我">${I('bellPlus', 'icon-16')}</button>` : ''}
    <button class="ibtn xs" data-p="lock" aria-pressed="${!!d.locked}" aria-label="锁定" data-tip="锁定">${I('lock', 'icon-16')}</button>
    <button class="ibtn xs" data-p="del" aria-label="删除" data-tip="删除" data-kbd="Delete">${I('trash', 'icon-16')}</button>`
}
function drawPropsClick(e: MouseEvent): void {
  const b = tgt(e).closest<HTMLElement>('button'); if (!b || !propsTarget) return
  const { d, cell } = propsTarget
  if (b.dataset.color) { d.color = b.dataset.color; st.drawColor = b.dataset.color }
  if (b.dataset.w) d.width = +b.dataset.w
  if (b.dataset.p === 'lock') d.locked = !d.locked
  if (b.dataset.p === 'alert') { if (toggleDrawingAlert(cfg(cell).symbol, d)) { toast('画线提醒已开', '价格碰到这条线时通知你', 'bell'); askNotify() } }
  if (b.dataset.p === 'del') { cell.chart.selected = d; cell.chart.deleteSelected(); return }
  drawingsChanged(cell); showDrawProps(d, cell)
}

// ------------------------------------------------------------ 工具栏
const LAYOUT_ICON: Record<Layout, string> = { '1': 'layout1', '2': 'layout2', '2v': 'layout2v', '4': 'layout4', '6': 'layout6', '8': 'layout8' }
const LAYOUT_NAME: [Layout, string][] = [['1', '一图'], ['2', '左右两图'], ['2v', '上下两图'], ['4', '四图'], ['6', '六图（三列两行）'], ['8', '八图（四列两行）']]
function layoutMenu(b: HTMLElement): void {
  const items: MenuItem[] = [{ header: '布局' }, ...LAYOUT_NAME.map(([k, l]): MenuItem => ({ icon: LAYOUT_ICON[k], label: l, checked: st.layout === k, sc: k === st.layout ? '当前' : '', run: () => setLayout(k) })), '-',
    { header: '多图联动' },
    { label: '十字线跨图同步', check: true, checked: st.linkCross, run: () => { st.linkCross = !st.linkCross; if (!st.linkCross) cells.forEach(c => c.chart.syncCrosshair(null)); save() } },
    { label: '品种跨图同步', check: true, checked: st.linkSymbol, sc: st.linkSymbol ? '' : '换一格全跟着换', run: () => { st.linkSymbol = !st.linkSymbol; save(); if (st.linkSymbol) linkAll(cfg(active()).symbol) } }]
  menuFrom(b, items)
}
/** 品种跨图同步：一格换了品种，其余格一起换（周期各自保留） */
function linkAll(symbol: string): void {
  cells.forEach(c => { const cc = cfg(c); if (cc.symbol !== symbol) { cc.symbol = symbol; void loadCell(c) } })
  save(); refreshStreams(); renderToolbar(); renderPanel()
}
// ---- 连接状态点：绿 = 实时，黄 = 在连，红 = 断了或行情停住
type Conn = 'live' | 'connecting' | 'down'
const CONN_TIP: Record<Conn, string> = { live: '行情连着', connecting: '正在连行情', down: '行情断了，正在重连' }
function connState(): Conn { return st.stale || S.wsState === 'closed' || !S.live ? (S.wsState === 'connecting' ? 'connecting' : 'down') : S.wsState === 'open' ? 'live' : 'connecting' }
function paintConn(): void { const c = connState(); $$('.cell-foot .conn-dot').forEach(e => { e.dataset.conn = c; e.dataset.tip = CONN_TIP[c] }) }
/** 浏览器标签页标题：当前品种的最新价与涨跌；换品种时立刻换，不等下一笔成交 */
function syncTitle(): void {
  const s = sym(cfg(active())?.symbol || '')
  document.title = s?.price ? `${s.code} ${priceText(s)} ${pctText(s.pct)} · Hkline` : 'Hkline'
}

export function renderToolbar(): void {
  const cell = active(); if (!cell) return
  const c = cfg(cell), s = sym(c.symbol)
  syncTitle()
  const pinnedHas = st.pinned.includes(c.iv)
  $('#toolbar').innerHTML = `
    <button class="tb-btn symbol-btn" id="tbSymbol" data-tip="换品种" data-kbd="⌘ K">${badge(s)}<span>${esc(c.symbol)}</span><span class="kind">${kindName(s)}</span></button>
    <span class="tb-sep"></span>
    <div class="intervals" role="group" aria-label="周期">
      ${st.pinned.map((iv, k) => `<button data-iv="${iv}" aria-pressed="${iv === c.iv}" data-tip="${IV_LABEL[iv]}" data-kbd="${k < 9 ? k + 1 : ''}">${IV_SHORT[iv]}</button>`).join('')}
      ${pinnedHas ? '' : `<button data-iv="${c.iv}" aria-pressed="true">${IV_SHORT[c.iv]}</button>`}
      <button class="tb-btn" id="tbMoreIv" aria-label="更多周期" data-tip="全部周期">更多${I('chevronDown', 'icon-16')}</button>
    </div>
    <span class="tb-sep"></span>
    <button class="tb-btn" id="tbInd" data-tip="指标" data-kbd="/">${I('indicators')}指标</button>
    <button class="tb-btn" id="tbAlert" data-tip="在现价创建提醒" data-kbd="Alt A">${I('bellPlus')}提醒</button>
    <button class="tb-btn" id="tbNote" data-tip="把这一刻记下来">${I('note')}记一笔</button>
    <div class="draw-props" id="drawProps" role="toolbar" aria-label="画线属性"></div>
    <div class="tb-right">
      <button class="ibtn sm" id="tbUndo" aria-label="撤销" data-tip="撤销" data-kbd="⌘ Z" ${undoStack.length ? '' : 'disabled style="opacity:.4"'}>${I('undo')}</button>
      <button class="ibtn sm" id="tbRedo" aria-label="重做" data-tip="重做" data-kbd="⌘ ⇧ Z" ${redoStack.length ? '' : 'disabled style="opacity:.4"'}>${I('redo')}</button>
      <span class="tb-sep"></span>
      <button class="ibtn sm" id="tbLayout" aria-label="布局" data-tip="图表布局">${I(LAYOUT_ICON[st.layout])}</button>
      <button class="ibtn sm" id="tbShot" aria-label="截图" data-tip="保存图表截图" data-kbd="⌥ S">${I('camera')}</button>
      <button class="ibtn sm" id="tbShare" aria-label="分享" data-tip="分享">${I('share')}</button>
      <button class="ibtn sm" id="tbFull" aria-label="全屏" data-tip="全屏" data-kbd="⇧ F">${I('fullscreen')}</button>
    </div>`
  $('#drawProps').addEventListener('click', drawPropsClick)
  if (propsTarget) showDrawProps(propsTarget.d, propsTarget.cell)
}
function onToolbarClick(e: MouseEvent): void {
  const b = tgt(e).closest<HTMLElement>('button'); if (!b) return
  if (b.dataset.iv) return setIv(b.dataset.iv)
  const c = cfg(active())
  switch (b.id) {
    case 'tbSymbol': return openSearch()
    case 'tbMoreIv': return intervalMenu(b)
    case 'tbInd': return openIndicators()
    case 'tbAlert': return openAlert()
    case 'tbNote': return openNote()
    case 'tbUndo': return undo()
    case 'tbRedo': return redo()
    case 'tbLayout': return layoutMenu(b)
    case 'tbShot': return screenshot()
    case 'tbShare':
      menuFrom(b, [
        { icon: 'camera', label: '复制图表截图', run: () => screenshot(true) },
        { icon: 'link', label: '复制这张图的链接', run: () => { void navigator.clipboard?.writeText(`${location.origin}${location.pathname}?s=${c.symbol}&i=${c.iv}#chart`); toast('链接已复制', '') } },
      ]); return
    case 'tbFull': return fullscreen()
  }
}
export function setLayout(k: Layout): void { st.layout = k; buildCells(); renderToolbar(); $$('.cell-foot [data-act="layout"]').forEach(e => { e.innerHTML = I(LAYOUT_ICON[k], 'icon-16') }) }

function intervalMenu(btn: HTMLElement): void {
  const c = cfg(active())
  const groups: [string, string[]][] = [['秒（打开页面起才有）', [...SECOND_IVS]], ['分钟', ['1m', '3m', '5m', '15m', '30m']], ['小时', ['1h', '2h', '4h', '6h', '8h', '12h']], ['日及以上', ['1d', '1w', '1M']]]
  if (st.customIvs.length) groups.push(['自定义', st.customIvs.filter(iv => IV_LABEL[iv])])
  const items: MenuItem[] = groups.flatMap(([h, ivs]): MenuItem[] => [{ header: h }, ...ivs.map(iv => ({
    label: IV_LABEL[iv], checked: iv === c.iv, check: true, sc: st.pinned.includes(iv) ? '已钉在栏上' : isCustomIv(iv) ? '右键移除' : '', run: () => setIv(iv),
  }))])
  items.push('-', { header: '右键周期可钉到栏上' })
  const m = menuFrom(btn, items, { width: 260 })
  // 自定义分钟：打一个数回车就切过去，并记进「自定义」
  const box = document.createElement('div'); box.className = 'iv-custom'
  box.innerHTML = `<input class="input num" type="text" inputmode="numeric" maxlength="4" placeholder="自定义分钟，如 7、45、90" aria-label="自定义分钟"><span class="faint">分</span>`
  m.appendChild(box)
  const inp = $<HTMLInputElement>('input', box)
  inp.addEventListener('keydown', e => {
    if (e.key !== 'Enter') return
    e.preventDefault()
    const iv = minutesIv(+inp.value.trim())
    if (!iv) { inp.classList.add('bad'); return }
    if (registerCustomIv(iv) && !st.customIvs.includes(iv)) { st.customIvs = [...st.customIvs, iv].slice(-12); save() }
    closeMenu(); setIv(iv)
  })
  inp.addEventListener('input', () => inp.classList.remove('bad'))
  // 右键一行 = 钉 / 取消钉
  m.addEventListener('contextmenu', e => {
    e.preventDefault()
    const b = tgt(e).closest<HTMLElement>('.mi'); if (!b) return
    const lab = b.querySelector('.label')?.textContent?.trim()
    const iv = Object.keys(IV_LABEL).find(k => IV_LABEL[k] === lab); if (!iv) return
    if (isCustomIv(iv)) { st.customIvs = st.customIvs.filter(x => x !== iv); save(); closeMenu(); intervalMenu($('#tbMoreIv')); return }
    if (!INTERVALS.includes(iv)) return
    st.pinned = st.pinned.includes(iv) ? st.pinned.filter(x => x !== iv) : INTERVALS.filter(x => st.pinned.includes(x) || x === iv)
    save(); closeMenu(); renderToolbar(); intervalMenu($('#tbMoreIv'))
  })
}

function screenshot(copy = false): void {
  const cell = active(); if (!cell) return
  const cv = cell.chart.canvas, c = cfg(cell)
  const d = sh(Date.now()), stamp = `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}-${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}`
  if (copy && navigator.clipboard && 'ClipboardItem' in window) {
    cv.toBlob(b => {
      if (!b) return
      navigator.clipboard.write([new ClipboardItem({ 'image/png': b })]).then(() => toast('截图已复制', '可以直接粘贴到聊天里', 'camera')).catch(() => toast('浏览器不让复制图片', '改用「保存图表截图」', 'info'))
    })
    return
  }
  const a = document.createElement('a'); a.download = `Hkline-${c.symbol}-${c.iv}-${stamp}.png`; a.href = cv.toDataURL('image/png'); a.click()
  toast('截图已保存', a.download, 'camera')
}
function fullscreen(): void { if (document.fullscreenElement) void document.exitFullscreen(); else void document.documentElement.requestFullscreen?.() }

// ------------------------------------------------------------ 图例、右键
function legendAction(id: string, act: string, btn?: HTMLElement): void {
  if (act === 'vpvrMode' && btn) {
    menuFrom(btn, [{ header: '成交量分布' }, ...VPVR_MODES.map((m): MenuItem => ({ label: m.label, check: true, checked: st.vpvrMode === m.id, run: () => { st.vpvrMode = m.id; save(); cells.forEach(c => c.chart.setVpvrMode(m.id)) } }))])
    return
  }
  if (act === 'remove') {
    if (isMainToggle(id)) st.ind[id] = false
    else st.ind.subs = st.ind.subs.filter(x => x !== id)
    cells.forEach(c => c.chart.setIndicators(st.ind)); save()
    toast(`已移除 ${CATALOG[id as IndicatorId]?.name || id}`, '在「指标」里可以加回来', 'close', 2200)
  }
  if (act === 'settings' && id in CATALOG) openParams(id as IndicatorId)
}
function chartContextMenu(cell: Cell, info: ContextMenuInfo): void {
  const c = cfg(cell), s = sym(c.symbol), p = info.price
  const pt = p != null ? fmt(p, s?.dec ?? 2) : ''
  const items: MenuItem[] = []
  const dr = info.drawing
  if (dr) {
    items.push({ header: '这条画线' }, { icon: 'lock', label: dr.locked ? '解锁' : '锁定', run: () => { dr.locked = !dr.locked; drawingsChanged(cell) } },
      { icon: 'trash', label: '删除', sc: 'Delete', run: () => { cell.chart.selected = dr; cell.chart.deleteSelected() } }, '-')
  }
  if (p != null) items.push(
    { icon: 'bellPlus', label: `在 ${pt} 创建提醒`, run: () => quickAlert(c.symbol, p) },
    { icon: 'hline', label: `在 ${pt} 画水平线`, sc: 'Alt H', run: () => { drawingsFor(c.symbol).push({ id: 'd' + Date.now(), type: 'hline', pts: [{ t: info.time, p }], color: st.drawColor, width: 2 }); cell.chart.dirty = true; drawingsChanged(cell) } },
    { icon: 'note', label: '在这根 K 线记一笔…', run: () => openNote(info.time, p) },
    { icon: 'link', label: `复制价格 ${pt}`, run: () => { void navigator.clipboard?.writeText(p.toFixed(s?.dec ?? 2)); toast('已复制', pt, 'check', 1500) } }, '-')
  items.push(
    { label: '重置视图', icon: 'candles', sc: 'Alt R', run: () => cell.chart.resetView() },
    { label: '对数坐标', check: true, checked: cell.chart.log, run: () => { cell.chart.setLog(!cell.chart.log); $('[data-act="log"]', cell.el)?.setAttribute('aria-pressed', String(cell.chart.log)) } },
    { label: '隐藏画线', check: true, checked: st.drawHidden, run: toggleHideDrawings },
  )
  menu(items, info.clientX, info.clientY, { width: 260 })
}

// ------------------------------------------------------------ 布局槽位
/** 按 st.slots 与侧栏开合算出图表页的网格；关着的槽位不占轨道，避免多出一道间隙 */
export function layoutSlots(): void {
  const page = $('#page-chart'); if (!page) return
  const { ladder, drawer } = st.slots
  const panel = !!st.panel
  const cols: [string, string][] = [['draw', 'var(--drawbar-w)'], ['chart', 'minmax(0,1fr)']]
  if (ladder) cols.push(['ladder', 'var(--ladder-w)'])
  if (panel) cols.push(['panel', 'var(--panel-w)'])
  cols.push(['rail', 'var(--rail-w)'])
  const row1 = cols.map(([k]) => k === 'draw' || k === 'chart' || k === 'ladder' ? 'tb' : k)
  const row2 = cols.map(([k]) => k)
  const rows = [row1, row2]
  const heights = ['var(--toolbar-h)', 'minmax(0,1fr)']
  if (drawer) { rows.push(cols.map(([k]) => k === 'chart' || k === 'ladder' ? 'drawer' : k)); heights.push('var(--drawer-h)') }
  page.style.gridTemplateColumns = cols.map(c => c[1]).join(' ')
  page.style.gridTemplateRows = heights.join(' ')
  page.style.gridTemplateAreas = rows.map(r => `"${r.join(' ')}"`).join(' ')
  const put = (sel: string, area: string, show: boolean) => { const e = $(sel); if (!e) return; e.style.gridArea = area; e.hidden = !show }
  put('#toolbar', 'tb', true); put('#drawbar', 'draw', true); put('#chartArea', 'chart', true); put('#rail', 'rail', true)
  put('#sidePanel', 'panel', panel); put('#ladderSlot', 'ladder', ladder); put('#drawerSlot', 'drawer', drawer)
  page.classList.toggle('panel-closed', !panel)
  cells.forEach(c => c.chart.resize())
}
function renderSlots(): void {
  $('#ladderSlot').innerHTML = `<div class="slot-head">深度梯子</div><div class="empty slot-empty">${I('layers', 'icon-24')}<div>订单簿大屏版下一阶段接入</div></div>`
  $('#drawerSlot').innerHTML = `<div class="slot-head">大单</div><div class="empty slot-empty">${I('list', 'icon-24')}<div>主力订单流大屏版下一阶段接入</div></div>`
}

// ------------------------------------------------------------ 侧栏
const RAIL: [PanelId, string, string][] = [['watch', 'star', '自选'], ['alerts', 'bell', '提醒'], ['flow', 'layers', '主力订单流'], ['notes', 'note', '笔记'], ['trades', 'trades', '成交']]
export function renderRail(): void {
  $('#rail').innerHTML = RAIL.map(([k, ic, l]) => `<button class="ibtn ${st.panel === k ? 'on' : ''}" data-panel="${k}" aria-label="${l}" aria-pressed="${st.panel === k}" data-tip="${l}" data-tip-side="left">${I(ic)}${k === 'alerts' && activeAlerts().length ? `<span class="dot">${activeAlerts().length}</span>` : ''}</button>`).join('') +
    `<div class="rail-spacer"></div>
    <button class="ibtn" id="railKeys" aria-label="快捷键" data-tip="快捷键" data-kbd="?" data-tip-side="left">${I('info')}</button>`
}
function onRailClick(e: MouseEvent): void {
  const b = tgt(e).closest<HTMLElement>('button'); if (!b) return
  if (b.id === 'railKeys') return openShortcuts()
  const p = b.dataset.panel as PanelId
  st.panel = st.panel === p ? null : p
  save(); renderRail(); renderPanel()
}
export function openPanel(p: PanelId): void { st.panel = p; save(); renderRail(); renderPanel() }

export function renderPanel(): void {
  layoutSlots()
  if (!st.panel || !cells.length) return
  const el = $('#sidePanel')
  ;({ watch: panelWatch, alerts: panelAlerts, flow: panelFlow, notes: panelNotes, trades: panelTrades } as Record<PanelId, (el: HTMLElement) => void>)[st.panel](el)
}

// ---- 自选（小部件堆叠：自选列表、详情；以后还有盘口 / 成交 / 大单 / 提醒）
const isWatched = (k: string): boolean => Object.values(st.watch).some(l => l.includes(k))
export { isWatched }
function panelWatch(el: HTMLElement): void {
  const widgets = st.slots.widgets.map(w => w === 'watch' ? widgetWatch() : w === 'detail' ? '<div class="detail" id="detail"></div>' : '').join('')
  el.innerHTML = widgets || '<div class="empty">没有小部件</div>'
  renderDetail()
  const tbl = $('#wTbl', el)
  if (tbl) bindDrag(tbl)
}
function widgetWatch(): string {
  const cur = cfg(active()).symbol
  const list = st.watch[st.watchTab]
  const empty = !S.symbols.size
    ? `<div class="empty">${I('wifiOff', 'icon-24')}<div>${S.live === false ? '连不上币安合约接口' : '正在取行情…'}</div></div>`
    : `<div class="empty">${I('star', 'icon-24')}<div>这一类还没有自选</div><button class="btn secondary sm" style="margin-top:12px" id="wAdd2">搜索品种</button></div>`
  return `<div class="widget widget-watch"><div class="sp-head"><h3>自选</h3>
      <button class="ibtn sm" id="wAdd" aria-label="添加品种" data-tip="添加品种" data-kbd="⌘ K">${I('plus')}</button>
      <button class="ibtn sm" id="wMore" aria-label="更多" data-tip="更多">${I('more')}</button></div>
    <div class="sp-sub" role="tablist">${TABS.map(([k, l]) => `<button class="chip" role="tab" data-tab="${k}" aria-pressed="${st.watchTab === k}">${l} ${st.watch[k].length}</button>`).join('')}</div>
    <div class="scroll" style="flex:1;min-height:0">
      ${list.length && S.symbols.size ? `<table class="tbl" id="wTbl"><thead><tr><th>品种</th><th>最新价</th><th>涨跌幅</th><th>成交额</th></tr></thead>
      <tbody>${list.map(k => watchRow(k, cur)).join('')}</tbody></table>` : empty}
    </div></div>`
}
function watchRow(k: string, cur: string): string {
  const s = sym(k)
  return `<tr data-sym="${k}" draggable="true" class="${k === cur ? 'sel' : ''}" aria-selected="${k === cur}">
    <td><div class="sym">${badge(s)}<b>${esc(s?.code || k)}</b><span class="cn">${esc(s?.cn || '')}</span></div></td>
    <td class="num price-live" data-f="price">${priceText(s)}</td>
    <td class="num ${cls(s?.pct)} price-live" data-f="pct">${pctText(s?.pct)}</td>
    <td class="num muted" data-f="vol">${fmtCompact(s?.vol)}</td></tr>`
}
function bindDrag(tbl: HTMLElement): void {
  let from: HTMLElement | null = null
  const clear = () => $$('tr', tbl).forEach(r => r.classList.remove('drop-above', 'drop-below'))
  tbl.addEventListener('dragstart', e => { from = tgt(e).closest('tr'); from?.classList.add('dragging'); if (e.dataTransfer) e.dataTransfer.effectAllowed = 'move' })
  tbl.addEventListener('dragend', () => { from?.classList.remove('dragging'); clear() })
  tbl.addEventListener('dragover', e => {
    const tr = tgt(e).closest<HTMLElement>('tbody tr'); if (!tr || !from) return
    e.preventDefault(); clear()
    const r = tr.getBoundingClientRect(); tr.classList.add(e.clientY < r.top + r.height / 2 ? 'drop-above' : 'drop-below')
  })
  tbl.addEventListener('drop', e => {
    const tr = tgt(e).closest<HTMLElement>('tbody tr'); if (!tr || !from || tr === from) return
    e.preventDefault()
    const list = st.watch[st.watchTab], a = from.dataset.sym || ''
    list.splice(list.indexOf(a), 1)
    let i = list.indexOf(tr.dataset.sym || ''); if (tr.classList.contains('drop-below')) i++
    list.splice(i, 0, a); save(); renderPanel()
  })
}
let lastWatchUndo: (() => void) | null = null
function onPanelClick(e: MouseEvent): void {
  const t = tgt(e)
  const tab = t.closest<HTMLElement>('[data-tab]'); if (tab) { st.watchTab = tab.dataset.tab as Kind; save(); renderPanel(); refreshStreams(); return }
  if (t.closest('#wAdd,#wAdd2')) return openSearch()
  const more = t.closest<HTMLElement>('#wMore')
  if (more) {
    const tabName = TABS.find(x => x[0] === st.watchTab)?.[1] || ''
    menuFrom(more, [{ icon: 'drag', label: '拖动行可以排序', disabled: true }, {
      icon: 'trash', label: `清空「${tabName}」自选`, disabled: !st.watch[st.watchTab].length, run: () => {
        const k = st.watchTab, bak = st.watch[k]; st.watch[k] = []; save(); renderPanel(); refreshStreams()
        lastWatchUndo = () => { st.watch[k] = bak; save(); renderPanel(); refreshStreams() }
        toast('已清空', '⌘Z 撤销', 'trash')
      },
    }]); return
  }
  const star = t.closest<HTMLElement>('[data-star]'); if (star) { toggleWatch(star.dataset.star || ''); return }
  const tr = t.closest<HTMLElement>('tr[data-sym]'); if (tr) return openSymbol(tr.dataset.sym || '')
  const sec = t.closest<HTMLElement>('[data-sector]'); if (sec) { hooks.openSector?.(sec.dataset.sector || ''); return }
  if (st.panel === 'alerts' && alertsPanelClick(e, cfg(active()).symbol)) return
  if (t.closest('#nNew')) return openNote()
  const delNote = t.closest<HTMLElement>('[data-del-note]'); if (delNote) { e.stopPropagation(); st.notes = st.notes.filter(n => n.id !== delNote.dataset.delNote); save(); renderPanel(); return }
  const note = t.closest<HTMLElement>('[data-note]'); if (note) return jumpNote(note.dataset.note || '')
}
export function toggleWatch(k: string): boolean {
  const s = sym(k), tab: Kind = s?.kind || 'crypto'
  const list = st.watch[tab]
  const on_ = list.includes(k)
  if (on_) list.splice(list.indexOf(k), 1); else list.push(k)
  save(); if (st.panel === 'watch') renderPanel(); refreshStreams()
  toast(on_ ? `已从自选移除 ${s?.code || k}` : `已加到自选 · ${TABS.find(x => x[0] === tab)?.[1] || ''}`, '', on_ ? 'starOff' : 'star', 1800)
  return !on_
}

// ---- 详情十二格
function renderDetail(): void {
  const el = $('#detail'); if (!el) return
  const k = cfg(active()).symbol, s = sym(k)
  if (!s) { el.innerHTML = ''; return }
  void fetchDetail(k)
  wantMeta([k])
  const d = detailOf(k) || { t: 0 }
  const secs = sectorsOf(s)
  const cap = marketCap(k)
  const w = isWatched(k)
  const basis = s.mark && s.index ? (s.mark / s.index - 1) * 100 : null
  el.innerHTML = `<div class="dh">${badge(s, 'xl')}<div class="names"><div class="code">${esc(s.code)}<span class="muted" style="font-weight:400;font-size:13px;margin-left:8px">${kindName(s)}</span></div><div class="cn">${esc(s.cn || '')}${cap ? `${s.cn ? ' · ' : ''}${term('市值')} <span class="num" data-f="cap">${fmtCompact(cap)}</span>` : ''}</div></div>
      <button class="ibtn" data-star="${k}" aria-pressed="${w}" aria-label="${w ? '移出自选' : '加入自选'}" data-tip="${w ? '移出自选' : '加入自选'}">${I(w ? 'star' : 'starOff')}</button></div>
    <div class="px"><span class="big num price-live ${st.stale ? '' : cls(s.pct)}" data-f="big">${priceText(s)}</span><span class="chg num ${cls(s.pct)}" data-f="chg">${chgText(s)}</span></div>
    ${s.hi && s.lo ? `<div class="range"><span class="num" data-f="lo">${fmt(s.lo, s.dec)}</span><div class="bar"><i data-f="pos" style="left:${clamp01(((s.price ?? s.lo) - s.lo) / (s.hi - s.lo || 1)) * 100}%"></i></div><span class="num" data-f="hi">${fmt(s.hi, s.dec)}</span></div>` : ''}
    <div class="stats cols3">
      <div><div class="k">${term('持仓量')}</div><div class="v num">${d.oiValue ? fmtCompact(d.oiValue) : '—'}</div></div>
      <div><div class="k">持仓 24h</div><div class="v num ${cls(d.oiChg)}">${d.oiChg == null ? '—' : pctText(d.oiChg)}</div></div>
      <div><div class="k">24h 成交额</div><div class="v num" data-f="vol">${s.vol ? fmtCompact(s.vol) : '—'}</div></div>
      <div><div class="k">${term('资金费率')}</div><div class="v num ${cls(s.fr)}" data-f="fr">${frText(s)}</div></div>
      <div><div class="k">${term('下次结算')}</div><div class="v num" data-f="cd">${s.nextFunding ? countdown(s.nextFunding - Date.now()) : '—'}</div></div>
      <div><div class="k">24h 笔数</div><div class="v num" data-f="count">${s.count ? fmtCompact(s.count) : '—'}</div></div>
      <div><div class="k">${term('多空人数比')}</div><div class="v num ${ratioCls(d.ls)}">${ratioText(d.ls)}</div></div>
      <div><div class="k">${term('大户持仓比')}</div><div class="v num ${ratioCls(d.top)}">${ratioText(d.top)}</div></div>
      <div><div class="k">${term('主动买卖比')}</div><div class="v num ${ratioCls(d.taker)}">${ratioText(d.taker)}</div></div>
      <div><div class="k">${term('标记价')}</div><div class="v num" data-f="mark">${s.mark ? fmt(s.mark, s.dec) : '—'}</div></div>
      <div><div class="k">${term('指数价')}</div><div class="v num" data-f="index">${s.index ? fmt(s.index, s.dec) : '—'}</div></div>
      <div><div class="k">${term('基差')}</div><div class="v num ${cls(basis)}" data-f="basis">${pctText(basis)}</div></div>
    </div>
    ${secs.length ? `<div class="sectors">${secs.map(x => `<button class="tag" data-sector="${x.id}">${esc(x.cn)}</button>`).join('')}</div>` : ''}`
}
const chgText = (s: Sym): string => s.price == null ? '—' : `${s.chg >= 0 ? '+' : ''}${fmt(s.chg, s.dec)}  ${pctText(s.pct)}`
const frText = (s: Sym): string => s.fr == null ? '—' : (s.fr * 100).toFixed(4) + '%'

/** 推送来的数只改那几格的字，不重画整块 */
function patchDetail(): void {
  const el = $('#detail'); if (!el) return
  const s = sym(cfg(active()).symbol); if (!s) return
  const set = (f: string, text: string, c?: string) => { const e = $(`[data-f="${f}"]`, el); if (!e) return; e.textContent = text; if (c != null) e.className = c }
  set('big', priceText(s), `big num price-live ${st.stale ? '' : cls(s.pct)}`)
  set('chg', chgText(s), `chg num ${cls(s.pct)}`)
  set('vol', s.vol ? fmtCompact(s.vol) : '—')
  set('count', s.count ? fmtCompact(s.count) : '—')
  set('fr', frText(s), `v num ${cls(s.fr)}`)
  set('mark', s.mark ? fmt(s.mark, s.dec) : '—')
  set('index', s.index ? fmt(s.index, s.dec) : '—')
  const basis = s.mark && s.index ? (s.mark / s.index - 1) * 100 : null
  set('basis', pctText(basis), `v num ${cls(basis)}`)
  if (s.hi && s.lo) { set('lo', fmt(s.lo, s.dec)); set('hi', fmt(s.hi, s.dec)); const p = $('[data-f="pos"]', el); if (p) p.style.left = clamp01(((s.price ?? s.lo) - s.lo) / (s.hi - s.lo || 1)) * 100 + '%' }
  const cap = marketCap(s.symbol); if (cap) set('cap', fmtCompact(cap))
}

// ---- 提醒（模块在 alerts/）
function panelAlerts(el: HTMLElement): void { renderAlertsPanel(el, cfg(active()).symbol) }
export function refreshAlerts(): void {
  cells.forEach(c => c.chart.setAlerts(priceAlerts(cfg(c).symbol)))
  renderRail(); if (st.panel === 'alerts') renderPanel()
  if (propsTarget) showDrawProps(propsTarget.d, propsTarget.cell)
  refreshStreams()
}

// ---- 主力订单流、成交：本阶段空态
function panelFlow(el: HTMLElement): void {
  el.innerHTML = `<div class="sp-head"><h3>${term('主力订单流')}</h3></div>
    <div class="empty">${I('layers', 'icon-24')}<div>网页版的大屏订单流下一阶段接入</div><div class="faint" style="font-size:12px;margin-top:4px">手机端已经可以看</div></div>`
}
function panelTrades(el: HTMLElement): void {
  el.innerHTML = `<div class="sp-head"><h3>成交</h3></div>
    <div class="empty">${I('trades', 'icon-24')}<div>需要登录并连上交易所只读密钥</div><div class="faint" style="font-size:12px;margin-top:4px">网页版登录下一阶段接入</div></div>`
}

// ---- 笔记
function panelNotes(el: HTMLElement): void {
  el.innerHTML = `<div class="sp-head"><h3>笔记</h3><button class="btn secondary sm" id="nNew">${I('plus', 'icon-16')}记一笔</button></div>
    <div class="scroll" style="flex:1;min-height:0">${st.notes.length ? st.notes.slice().reverse().map(n => {
      const s = sym(n.symbol)
      return `<div class="list-row" data-note="${n.id}" style="cursor:pointer;align-items:flex-start">${badge(s, 'lg')}<div class="main"><div class="t1">${esc(s?.code || n.symbol)}<span class="tag">${IV_LABEL[n.iv] || n.iv}</span><span class="faint" style="font-size:12px;font-weight:400;margin-left:auto">${shTime(n.t)}</span></div>
        <div class="t2" style="color:var(--text-1);font-size:13px;line-height:20px;white-space:pre-wrap">${esc(n.text)}</div></div>
        <button class="ibtn sm act" data-del-note="${n.id}" aria-label="删除笔记" data-tip="删除">${I('trash')}</button></div>`
    }).join('') : `<div class="empty">${I('note', 'icon-24')}<div>还没有笔记</div><div class="faint" style="font-size:12px;margin-top:4px">在图上右键「在这根 K 线记一笔」</div></div>`}</div>`
}
function openNote(t?: number, p?: number): void {
  const cell = active(); if (!cell) return
  const c = cfg(cell), s = sym(c.symbol), b = cell.chart.lastBar()
  const tt = t ?? b?.t ?? Date.now(), pp = p ?? b?.c ?? s?.price ?? 0
  const d = dialog(`${head('记一笔')}<div class="dialog-body"><div class="form-grid">
    <div class="sym-card">${badge(s, 'lg')}<div style="flex:1"><b>${esc(c.symbol)}</b> <span class="muted">${IV_LABEL[c.iv]} · ${shTime(tt)}</span></div><span class="num">${fmt(pp, s?.dec ?? 2)}</span></div>
    <div class="field"><label for="nTx">这时候在想什么</label><textarea id="nTx" class="input" style="height:120px;padding:8px 12px;resize:vertical;line-height:20px" placeholder="比如：放量突破前高，回踩不破再看多"></textarea></div>
    </div></div><div class="dialog-foot"><span class="faint" style="margin-right:auto;font-size:12px;align-self:center"><kbd>⌘</kbd> <kbd>↵</kbd> 保存</span><button class="btn ghost" data-close>取消</button><button class="btn primary" id="nOk">保存</button></div>`, 'alert-dlg', { label: '记一笔' })
  const tx = $<HTMLTextAreaElement>('#nTx', d.dlg); tx.focus()
  const ok = () => {
    if (!tx.value.trim()) { tx.focus(); return }
    st.notes.push({ id: 'n' + Date.now(), symbol: c.symbol, iv: c.iv, t: tt, p: pp, text: tx.value.trim() }); save(); d.close()
    toast('已记下', '在右侧「笔记」里能找回来', 'note'); if (st.panel === 'notes') renderPanel()
  }
  $('#nOk', d.dlg).onclick = ok
  tx.addEventListener('keydown', e => { if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) ok() })
}
function jumpNote(id: string): void {
  const n = st.notes.find(x => x.id === id); const cell = active(); if (!n || !cell) return
  const c = cfg(cell)
  const center = () => { const i = cell.chart.indexAt(n.t); cell.chart.rightBar = i + cell.chart.plotW() / cell.chart.spacing / 2; cell.chart.syncCrosshair(n.t); cell.chart.dirty = true; setTimeout(() => cell.chart.syncCrosshair(null), 2000) }
  if (c.symbol !== n.symbol || c.iv !== n.iv) { c.symbol = n.symbol; c.iv = n.iv; save(); void loadCell(cell, center); refreshStreams(); renderToolbar() } else center()
}

// ------------------------------------------------------------ 搜索
export function openSearch(initial = ''): void {
  if (dialogs.some(d => d.dlg.classList.contains('search-dlg'))) return
  let cat: 'all' | Kind = 'all', q = initial, activeIdx = 0, results: Sym[] = []
  const CATS: ['all' | Kind, string][] = [['all', '全部'], ['crypto', '加密'], ['us', '美股'], ['com', '大宗']]
  const d = dialog(`<div class="search-top">${I('search', 'icon-24')}<input id="sq" placeholder="搜索品种，比如 BTC、英伟达、黄金" autocomplete="off" spellcheck="false" aria-label="搜索品种" value="${esc(initial)}"><kbd>Esc</kbd></div>
    <div class="search-cats" role="tablist">${CATS.map(([k, l]) => `<button class="chip" data-cat="${k}" aria-pressed="${k === cat}">${l}</button>`).join('')}</div>
    <div class="search-list scroll" id="sl" role="listbox"></div>
    <div class="search-foot"><span><kbd>↑</kbd><kbd>↓</kbd>选择</span><span><kbd>↵</kbd>打开</span><span><kbd>⇧</kbd><kbd>↵</kbd>加自选</span><span><kbd>Tab</kbd>换分类</span></div>`, 'search-dlg', { label: '搜索品种' })
  const inp = $<HTMLInputElement>('#sq', d.dlg), listEl = $('#sl', d.dlg)
  function render(): void {
    const qq = q.trim().toUpperCase()
    const pool = [...S.symbols.values()].filter(s => cat === 'all' || s.kind === cat)
    results = rankSearch(pool, qq, isWatched)
    activeIdx = Math.min(activeIdx, Math.max(0, results.length - 1))
    const hl = (t: string) => qq && t.toUpperCase().startsWith(qq) ? `<mark>${esc(t.slice(0, qq.length))}</mark>${esc(t.slice(qq.length))}` : esc(t)
    listEl.innerHTML = !S.symbols.size ? `<div class="empty">${S.live === false ? '连不上币安合约接口，搜不了' : '正在取品种表…'}</div>`
      : results.length ? results.map((s, i) => { const w = isWatched(s.symbol); return `<div class="sr ${i === activeIdx ? 'active' : ''}" role="option" aria-selected="${i === activeIdx}" data-i="${i}">
      ${badge(s, 'lg')}<div><div class="n1">${hl(s.code)}<span class="muted" style="font-weight:400;font-size:12px;margin-left:6px">${esc(s.symbol === s.code ? '' : s.symbol)}</span></div><div class="n2">${esc(s.cn || '')}${s.cn ? ' · ' : ''}${kindName(s)}</div></div>
      <div class="r num">${priceText(s)}</div><div class="r num ${cls(s.pct)}">${pctText(s.pct)}</div><div class="r num muted">${fmtCompact(s.vol)}</div>
      <button class="ibtn sm" data-w="${s.symbol}" aria-label="${w ? '移出自选' : '加入自选'}" style="color:${w ? '#F5A623' : ''}">${I(w ? 'star' : 'starOff')}</button></div>` }).join('')
      : `<div class="empty">没有找到「${esc(q)}」<div class="faint" style="font-size:12px;margin-top:4px">代号、中文名都能搜，比如「英伟达」「黄金」</div></div>`
  }
  const setCat = (k: 'all' | Kind) => { cat = k; $$('[data-cat]', d.dlg).forEach(b => b.setAttribute('aria-pressed', String(b.dataset.cat === cat))); activeIdx = 0; render() }
  function move(k: number): void { activeIdx = Math.max(0, Math.min(results.length - 1, activeIdx + k)); render(); $('.sr.active', listEl)?.scrollIntoView({ block: 'nearest' }) }
  inp.addEventListener('input', () => { q = inp.value; activeIdx = 0; render() })
  inp.addEventListener('keydown', e => {
    if (e.key === 'ArrowDown') { e.preventDefault(); move(1) }
    else if (e.key === 'ArrowUp') { e.preventDefault(); move(-1) }
    else if (e.key === 'Enter') { e.preventDefault(); const s = results[activeIdx]; if (!s) return; if (e.shiftKey) { toggleWatch(s.symbol); render() } else { d.close(); go('chart'); openSymbol(s.symbol) } }
    else if (e.key === 'Tab') { e.preventDefault(); const cs = CATS.map(c => c[0]); setCat(cs[(cs.indexOf(cat) + (e.shiftKey ? 3 : 1)) % 4]) }
  })
  d.dlg.addEventListener('click', e => {
    const t = tgt(e)
    const c = t.closest<HTMLElement>('[data-cat]'); if (c) { setCat(c.dataset.cat as 'all' | Kind); inp.focus(); return }
    const w = t.closest<HTMLElement>('[data-w]'); if (w) { e.stopPropagation(); toggleWatch(w.dataset.w || ''); render(); inp.focus(); return }
    const r = t.closest<HTMLElement>('.sr'); if (r) { const s = results[+(r.dataset.i || 0)]; d.close(); if (s) { go('chart'); openSymbol(s.symbol) } }
  })
  listEl.addEventListener('mousemove', e => { const r = tgt(e).closest<HTMLElement>('.sr'); if (r && +(r.dataset.i || 0) !== activeIdx) { activeIdx = +(r.dataset.i || 0); $$('.sr', listEl).forEach((x, i) => x.classList.toggle('active', i === activeIdx)) } })
  render(); inp.focus(); inp.setSelectionRange(q.length, q.length)
}

// ------------------------------------------------------------ 指标
type IndRow = [IndicatorId, 'main' | 'sub', string, string]
const IND_ROWS: IndRow[] = [
  ['ma', 'main', 'MA', '均线'], ['ema', 'main', 'EMA', '指数均线'], ['boll', 'main', 'BOLL', '布林带'], ['vol', 'main', '成交量', '叠在主图底部'],
  ...(['vwap', 'st', 'ichi', 'vpvr'] as IndicatorId[]).map((id): IndRow => [id, 'main', CATALOG[id].name, CATALOG[id].cn]),
  ['macd', 'sub', 'MACD', '平滑异同移动平均'], ['rsi', 'sub', 'RSI', '相对强弱'], ['kdj', 'sub', 'KDJ', '随机指标'], ['oi', 'sub', '持仓量', '币安只给 30 天内的历史'],
  ...(['cvd', 'atr', 'obv', 'stochrsi', 'cci', 'wr'] as IndicatorId[]).map((id): IndRow => [id, 'sub', CATALOG[id].name, CATALOG[id].cn]),
]
/** 主图上用开关记的那几个（其余是副图） */
type MainToggle = 'ma' | 'ema' | 'boll' | 'vol' | 'vwap' | 'st' | 'ichi' | 'vpvr'
const MAIN_TOGGLES: string[] = ['ma', 'ema', 'boll', 'vol', 'vwap', 'st', 'ichi', 'vpvr']
const isMainToggle = (id: string): id is MainToggle => MAIN_TOGGLES.includes(id)
function openIndicators(): void {
  let cat: 'all' | 'main' | 'sub' = 'all'
  const d = dialog(`${head('指标', `<span class="faint" style="font-size:12px">副图最多四个</span>`)}<div class="body"><div class="ind-cats">${([['all', '全部'], ['main', '主图'], ['sub', '副图']] as ['all' | 'main' | 'sub', string][]).map(([k, l]) => `<button data-c="${k}" aria-pressed="${k === cat}">${l}<span class="faint">${k === 'all' ? IND_ROWS.length : IND_ROWS.filter(r => r[1] === k).length}</span></button>`).join('')}</div><div class="scroll" id="indList"></div></div>`, 'ind-dlg', { label: '指标' })
  const isOn = (id: IndicatorId) => isMainToggle(id) ? !!st.ind[id] : st.ind.subs.includes(id as SubId)
  function render(): void {
    const full = st.ind.subs.length >= MAX_SUBS
    $('#indList', d.dlg).innerHTML = IND_ROWS.filter(r => cat === 'all' || r[1] === cat).map(([id, pl, n, sub]) => {
      const on_ = isOn(id), dis = pl === 'sub' && !on_ && full
      return `<div class="ind-row ${dis ? 'disabled' : ''}" data-id="${id}" tabindex="0" role="checkbox" aria-checked="${on_}" aria-disabled="${dis}" ${dis ? 'data-tip="副图已经有四个了，先关一个"' : ''}>
        <span class="check-box ${on_ ? 'on' : ''}">${on_ ? I('check', 'icon-16') : ''}</span><span class="nm">${n}<small>${sub}</small></span>
        <span class="tag">${pl === 'main' ? '主图' : '副图'}</span>
        ${id !== 'vol' && Object.keys(CATALOG[id]?.params || {}).length ? `<button class="ibtn xs" data-set="${id}" aria-label="参数" data-tip="参数">${I('gear', 'icon-16')}</button>` : '<span style="width:24px"></span>'}</div>`
    }).join('')
  }
  function toggle(id: IndicatorId): void {
    if (isMainToggle(id)) st.ind[id] = !st.ind[id]
    else if (st.ind.subs.includes(id as SubId)) st.ind.subs = st.ind.subs.filter(x => x !== id)
    else if (st.ind.subs.length < MAX_SUBS) st.ind.subs = [...st.ind.subs, id as SubId]
    else return
    cells.forEach(c => c.chart.setIndicators(st.ind)); save(); render()
  }
  d.dlg.addEventListener('click', e => {
    const t = tgt(e)
    const c = t.closest<HTMLElement>('[data-c]'); if (c) { cat = c.dataset.c as typeof cat; $$('[data-c]', d.dlg).forEach(b => b.setAttribute('aria-pressed', String(b.dataset.c === cat))); render(); return }
    const s = t.closest<HTMLElement>('[data-set]'); if (s) { e.stopPropagation(); openParams(s.dataset.set as IndicatorId); return }
    const r = t.closest<HTMLElement>('.ind-row'); if (r && r.getAttribute('aria-disabled') !== 'true') toggle(r.dataset.id as IndicatorId)
  })
  d.dlg.addEventListener('keydown', e => { const t = tgt(e); if ((e.key === ' ' || e.key === 'Enter') && t.classList.contains('ind-row')) { e.preventDefault(); toggle(t.dataset.id as IndicatorId) } })
  render(); $('.ind-row', d.dlg)?.focus()
}
const PARAM_NAME: Record<string, string> = { n: '周期', k: '倍数', fast: '快线', slow: '慢线', signal: '信号线', m1: '平滑 1', m2: '平滑 2', stoch: '取值窗口', tenkan: '转换线', kijun: '基准线', senkou: '先行带 B' }
function openParams(id: IndicatorId): void {
  const cell = active(); if (!cell) return
  const catg = CATALOG[id], p = cell.chart.params[id] || catg.params || {}
  type Field = [string, number, string]
  const fields: Field[] = p.periods ? p.periods.map((v, k): Field => [`周期 ${k + 1}`, v, 'periods']) : Object.entries(p).map(([k, v]): Field => [PARAM_NAME[k] || k, v as number, k])
  if (!fields.length) return
  const d = dialog(`${head(`${catg.name} 参数`)}<div class="dialog-body"><div style="display:grid;grid-template-columns:1fr 1fr;gap:16px">
    ${fields.map((f, i) => `<div class="field"><label for="pf${i}">${f[0]}</label><div class="input-wrap"><input id="pf${i}" class="input num" inputmode="decimal" value="${f[1]}"></div></div>`).join('')}
    </div></div><div class="dialog-foot"><button class="btn ghost" id="pReset" style="margin-right:auto">恢复默认</button><button class="btn ghost" data-close>取消</button><button class="btn primary" id="pOk">应用</button></div>`, 'alert-dlg', { label: catg.name + ' 参数' })
  $<HTMLInputElement>('#pf0', d.dlg).select()
  const apply = (np: IndParams) => {
    st.params = { ...(st.params || {}), [id]: np }
    cells.forEach(c => c.chart.setParams(id, structuredClone(np))); save(); d.close()
  }
  $('#pOk', d.dlg).onclick = () => {
    const vals = fields.map((_, i) => +$<HTMLInputElement>('#pf' + i, d.dlg).value)
    if (vals.some(v => !(v > 0))) { toast('参数要是正数', '', 'info', 1800); return }
    apply(p.periods ? { periods: vals.map(Math.round) } : Object.fromEntries(fields.map((f, i) => [f[2], vals[i]])) as IndParams)
  }
  $('#pReset', d.dlg).onclick = () => apply(structuredClone(catg.params || {}))
  d.dlg.addEventListener('keydown', e => { if (e.key === 'Enter') $('#pOk', d.dlg).click() })
}

// ------------------------------------------------------------ 提醒对话框
function openAlert(price?: number): void {
  const cell = active(); if (!cell) return
  openCreateAlert(cfg(cell).symbol, price ?? cell.chart.crossPrice())
}

// ------------------------------------------------------------ 快捷键
export const SHORTCUTS: [string, [string, string][]][] = [
  ['品种与周期', [['直接打字母', '搜索品种'], ['⌘ K', '搜索品种'], ['1 – 9', '栏上钉的第几个周期'], [', 再打数字', '换任意周期（如 7、240、1D、5S）'], ['↑ ↓', '自选里上一只 / 下一只'], ['⇧ ↵', '在搜索里加自选']]],
  ['图表', [['滚轮', '缩放（以光标为中心）'], ['拖动', '平移'], ['← →', '平移一根（⇧ 十根）'], ['拖价格轴', '缩放价格'], ['双击价格轴', '价格回到自动'], ['Alt R', '重置视图'], ['右键', '在这里建提醒、画线、记一笔'], ['/', '指标']]],
  ['画线', [['Alt T', '趋势线'], ['Alt H', '水平线'], ['Alt V', '垂直线'], ['Alt F', '斐波那契回撤'], ['Alt ⇧ R', '矩形'], ['⇧ 拖', '临时测量'], ['Delete', '删除选中的画线'], ['Esc', '取消 / 回到光标'], ['⌘ Z / ⌘ ⇧ Z', '撤销 / 重做']]],
  ['其它', [['Alt A', '在现价（或十字线价位）建提醒'], ['⌥ S', '保存截图'], ['⇧ F', '全屏'], ['?', '这张表']]],
]
export function kbdHTML(s: string): string { return s.split(' ').map(k => /^[直拖滚双右]/.test(k) ? `<span class="muted">${k}</span>` : k === '/' && s.includes('⌘') ? ' / ' : `<kbd>${k}</kbd>`).join(' ') }
export function openShortcuts(): void {
  dialog(`${head('快捷键')}<div class="dialog-body"><div style="display:grid;grid-template-columns:1fr 1fr;gap:8px 48px">${SHORTCUTS.map(([h, rows]) => `<div><div class="group-title" style="margin-top:8px">${h}</div><table class="kbd-table">${rows.map(([k, v]) => `<tr><td>${kbdHTML(k)}</td><td class="muted">${v}</td></tr>`).join('')}</table></div>`).join('')}</div></div>`, '', { label: '快捷键' }).dlg.style.width = '880px'
}

// ------------------------------------------------------------ 周期快输
let ivPop: { buf: string; el: HTMLElement; timer?: ReturnType<typeof setTimeout> } | null = null
function ivRender(): void {
  if (!ivPop) return
  clearTimeout(ivPop.timer); ivPop.timer = setTimeout(() => ivCommit(), 2200)
  const iv = ivParse(ivPop.buf)
  ivPop.el.classList.toggle('bad', !iv)
  ivPop.el.innerHTML = `<div class="v num">${esc(ivPop.buf)}</div><div class="h">${iv ? `${IV_LABEL[iv]} · 回车切换` : !ivPop.buf ? '打分钟数，或带单位：H 小时、D 日、W 周、S 秒' : '没有这个周期，接着打或按 Esc'}</div>`
}
function ivInput(ch: string): void {
  if (!ivPop) { ivPop = { buf: '', el: document.createElement('div') }; ivPop.el.className = 'interval-pop'; document.body.appendChild(ivPop.el) }
  ivPop.buf += ch
  ivRender()
}
export function ivParse(b: string): string | null {
  const sec = b.match(/^(\d+)[sS]$/); if (sec) { const iv = `${+sec[1]}s`; return isSecondIv(iv) ? iv : null }
  const m = b.match(/^(\d+)([mhdwMHDW]?)$/); if (!m) return null
  const n = +m[1], u = m[2]
  let min = n
  if (!u || u === 'm') min = n
  else if (/h/i.test(u)) min = n * 60
  else if (/d/i.test(u)) min = n * 1440
  else if (/w/i.test(u)) min = n * 10080
  else if (u === 'M') min = n * 43200
  return Object.keys(IV_MS).find(k => IV_MS[k] === min * 60e3 && !isCustomIv(k)) || (min <= 1440 ? minutesIv(min) : null)
}
function ivCommit(apply = true): void {
  if (!ivPop) return
  const iv = ivParse(ivPop.buf)
  ivPop.el.remove(); clearTimeout(ivPop.timer); ivPop = null
  if (apply && iv) {
    if (registerCustomIv(iv) && !st.customIvs.includes(iv)) { st.customIvs = [...st.customIvs, iv].slice(-12); save() }
    setIv(iv)
  }
}

// ------------------------------------------------------------ 全局键盘
function onKey(e: KeyboardEvent): void {
  const t = tgt(e), tag = t.tagName
  const typing = tag === 'INPUT' || tag === 'TEXTAREA' || t.isContentEditable
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); openSearch(); return }
  if (dialogs.length || typing) return
  if (menuOpen()) { if (e.key === 'Escape') closeMenu(); return }
  if (ivPop) {
    if (e.key === 'Enter') { e.preventDefault(); ivCommit(); return }
    if (e.key === 'Escape') { ivCommit(false); return }
    if (e.key === 'Backspace') { e.preventDefault(); ivPop.buf = ivPop.buf.slice(0, -1); if (!ivPop.buf) ivCommit(false); else ivRender(); return }
    if (/^[0-9mhdwsMHDWS]$/.test(e.key)) { e.preventDefault(); ivInput(e.key) }
    return
  }
  if (st.page !== 'chart') { if (e.key === '?') openShortcuts(); return }
  const cell = active(); if (!cell) return
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'z') {
    e.preventDefault()
    if (!e.shiftKey && lastWatchUndo) { const u = lastWatchUndo; lastWatchUndo = null; u(); return }
    if (e.shiftKey) redo(); else undo()
    return
  }
  if (e.metaKey || e.ctrlKey) return
  if (e.altKey) {
    const map: Record<string, DrawingType> = { KeyT: 'trend', KeyH: 'hline', KeyV: 'vline', KeyF: 'fib' }
    if (e.code === 'KeyR' && e.shiftKey) { e.preventDefault(); selectTool('rect'); return }
    if (map[e.code]) { e.preventDefault(); selectTool(map[e.code]); return }
    if (e.code === 'KeyA') { e.preventDefault(); openAlert(); return }
    if (e.code === 'KeyR') { e.preventDefault(); cell.chart.resetView(); return }
    if (e.code === 'KeyS') { e.preventDefault(); screenshot(); return }
    return
  }
  if (e.key === 'Escape') { if (cell.chart.cancelDraft()) return; if (tool) { selectTool(null); return } if (cell.chart.selected) { cell.chart.selected = null; cell.chart.dirty = true; showDrawProps(null) } return }
  if (e.key === 'Delete' || e.key === 'Backspace') { if (cell.chart.deleteSelected()) e.preventDefault(); return }
  if (e.key === '?') { openShortcuts(); return }
  if (e.key === '/') { e.preventDefault(); openIndicators(); return }
  if (e.key === 'F' && e.shiftKey) { fullscreen(); return }
  if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') { e.preventDefault(); cell.chart.scrollBars((e.key === 'ArrowLeft' ? -1 : 1) * (e.shiftKey ? 10 : 1)); return }
  if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
    e.preventDefault()
    const list = st.watch[st.watchTab]; if (!list.length) return
    const i = list.indexOf(cfg(cell).symbol)
    const n = i < 0 ? 0 : (i + (e.key === 'ArrowDown' ? 1 : -1) + list.length) % list.length
    openSymbol(list[n]); $(`#wTbl tr[data-sym="${list[n]}"]`)?.scrollIntoView({ block: 'nearest' })
    return
  }
  if (e.key === '+' || e.key === '=') { cell.chart.zoom(1.25); return }
  if (e.key === '-') { cell.chart.zoom(0.8); return }
  // 1–9：栏上钉的第 N 个周期；0 或逗号：打周期（如 0 → 7 回车 = 7 分）
  if (/^[1-9]$/.test(e.key)) { e.preventDefault(); const iv = st.pinned[+e.key - 1]; if (iv) setIv(iv); return }
  if (e.key === '0' || e.key === ',') { e.preventDefault(); ivInput(''); return }
  if (/^[a-zA-Z]$/.test(e.key)) { e.preventDefault(); openSearch(e.key.toUpperCase()) }
}

// ------------------------------------------------------------ 实时
export function refreshStreams(): void {
  const set = new Set<string>(), core = new Set<string>()
  st.cells.slice(0, cells.length).forEach((c, i) => {
    // 秒级没有 K 线流，订逐笔自己攒；自定义分钟订它底下那个原生周期
    const siv = streamIvOf(c.iv), bar = siv ? streamName.kline(c.symbol, siv) : streamName.trade(c.symbol)
    set.add(bar); set.add(streamName.ticker(c.symbol))
    if (i === st.active) { core.add(bar); core.add(streamName.ticker(c.symbol)) }
  })
  const a = st.cells[st.active]
  if (a) { set.add(streamName.mark(a.symbol)); set.add(streamName.trade(a.symbol)) }
  if (st.panel === 'watch') for (const k of st.watch[st.watchTab]) set.add(streamName.ticker(k))
  // 提醒要在后台也盯着
  const al = alertStreams()
  for (const k of al.ticker) { set.add(streamName.ticker(k)); core.add(streamName.ticker(k)) }
  for (const k of al.mark) { set.add(streamName.mark(k)); core.add(streamName.mark(k)) }
  for (const fn of hooks.extraStreams) for (const x of fn()) set.add(x)
  const known = (name: string) => S.symbols.has(name.split('@')[0].toUpperCase())
  setStreams([...set].filter(known), [...core].filter(known))
}

// 秒级：一帧并一次
const pendingSec = new Set<string>()
let secRAF = 0
function flushSeconds(): void {
  secRAF = 0
  if (st.stale) { pendingSec.clear(); return }
  cells.forEach(c => {
    const cc = cfg(c); if (!pendingSec.has(cc.symbol) || !isSecondIv(cc.iv)) return
    if (!c.chart.bars.length) { c.chart.setData(secondBars(cc.symbol, cc.iv), metaFor(cc)); showCellEmpty(c, null); return }
    const b = secondLastBar(cc.symbol, cc.iv); if (b) c.chart.updateBar(b)
  })
  pendingSec.clear()
}

const pendingTick = new Map<string, number>()
let tickRAF = 0
function flushTicks(): void {
  tickRAF = 0
  const cur = cfg(active())?.symbol
  for (const [k, dir] of pendingTick) {
    const tr = $(`#wTbl tr[data-sym="${k}"]`), s = sym(k)
    if (tr && s) {
      const p = $('[data-f="price"]', tr), pc = $('[data-f="pct"]', tr), v = $('[data-f="vol"]', tr)
      if (p) { p.textContent = priceText(s); if (dir) { p.classList.remove('flash-up', 'flash-down'); void p.offsetWidth; p.classList.add(dir > 0 ? 'flash-up' : 'flash-down') } }
      if (pc) { pc.textContent = pctText(s.pct); pc.className = `num ${cls(s.pct)} price-live` }
      if (v) v.textContent = fmtCompact(s.vol)
    }
    if (k === cur && s) { patchDetail(); syncTitle() }
  }
  pendingTick.clear()
  hooks.onTicks.forEach(f => f())
}

let staleTimer: ReturnType<typeof setTimeout> | undefined
function updateStale(): void {
  const bad = S.live === false || S.wsState === 'closed'
  clearTimeout(staleTimer)
  if (bad) staleTimer = setTimeout(() => setStale(true), S.live === false ? 0 : 5000)
  else setStale(false)
}
function setStale(v: boolean): void {
  if (st.stale === v) return
  st.stale = v
  document.body.classList.toggle('stale', v); paintConn()
  cells.forEach(c => c.chart.setStale(v))
  patchDetail()
}

function afterUniverse(): void {
  // 品种表没取到时不能拿空表去筛，否则会把自选清空并存盘
  if (S.symbols.size) {
    for (const tab of Object.keys(st.watch) as Kind[]) st.watch[tab] = st.watch[tab].filter(k => S.symbols.has(k))
    st.cells.forEach(c => { if (!S.symbols.has(c.symbol)) c.symbol = 'BTCUSDT' })
    save()
  }
  if (!cells.length) buildCells(); else { cells.forEach(c => { void loadCell(c) }); refreshStreams() }
  renderToolbar(); renderPanel(); updateStale()
  hooks.booted.forEach(f => f())
}

// ------------------------------------------------------------ 启动
export async function initChart(): Promise<void> {
  $('#drawbar').addEventListener('click', onDrawbarClick)
  $('#toolbar').addEventListener('click', onToolbarClick)
  $('#rail').addEventListener('click', onRailClick)
  $('#sidePanel').addEventListener('click', onPanelClick)
  addEventListener('keydown', onKey)
  hooks.onSearch = openSearch
  hooks.onTheme.push(() => cells.forEach(c => c.chart.readTheme()))
  hooks.pageShown.chart = () => cells.forEach(c => c.chart.resize())
  $('#hdrAlerts').onclick = () => { go('chart'); openPanel('alerts') }
  installAlerts({ openSymbol: k => { go('chart'); openSymbol(k) } })
  st.customIvs.forEach(registerCustomIv); st.cells.forEach(c => registerCustomIv(c.iv))
  startSeconds()
  onSecondsTick(k => { pendingSec.add(k); if (!secRAF) secRAF = requestAnimationFrame(flushSeconds) })
  migrateDrawingFlags()
  onAlertsChange(refreshAlerts)

  on(e => {
    if (e.type === 'kline') cells.forEach(c => {
      const cc = cfg(c); if (cc.symbol !== e.symbol || st.stale) return
      if (cc.iv === e.iv) c.chart.updateBar({ ...e.bar })
      else if (isCustomIv(cc.iv) && customBase(cc.iv) === e.iv && c.chart.bars.length) c.chart.updateBar(customTick(cc.symbol, cc.iv, e.bar))
    })
    else if (e.type === 'ticker') {
      pendingTick.set(e.symbol, e.dir || pendingTick.get(e.symbol) || 0)
      if (!tickRAF) tickRAF = requestAnimationFrame(flushTicks)
    }
    else if (e.type === 'mark') { if (e.symbol === cfg(active())?.symbol) patchDetail() }
    else if (e.type === 'oi') cells.forEach(c => { const cc = cfg(c); if (cc.symbol === e.symbol && cc.iv === e.iv) { c.chart.recalc(); c.chart.dirty = true } })
    else if (e.type === 'detail' || e.type === 'meta') { if (st.panel === 'watch' && (e.type === 'meta' || e.symbol === cfg(active())?.symbol)) renderDetail() }
    else if (e.type === 'ws') { updateStale(); paintConn() }
  })

  // 每秒：钟、倒计时；每分钟：详情里的慢数、持仓量提醒
  setInterval(() => {
    const d = sh(Date.now()), t = `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}:${pad(d.getUTCSeconds())} UTC+8`
    $$('.cell-foot .clock').forEach(e => { e.textContent = t })
    cells.forEach(c => { c.chart.dirty = true })
    const s = sym(cfg(active())?.symbol || ''), cd = $('#detail [data-f="cd"]')
    if (cd && s?.nextFunding) cd.textContent = countdown(s.nextFunding - Date.now())
  }, 1000)
  setInterval(() => {
    if (document.visibilityState === 'hidden') return
    if (st.panel === 'watch') { const k = cfg(active())?.symbol; if (k) void fetchDetail(k) }
  }, 61e3)

  renderDrawbar(); renderRail(); renderSlots(); layoutSlots(); renderPanel()
  await loadUniverse()
  if (!S.live) toast('连不上币安合约接口', S.error || '检查网络后点图上的「重试」', 'wifiOff', 8000)
  afterUniverse()
}

export { cfg, buildCells }
