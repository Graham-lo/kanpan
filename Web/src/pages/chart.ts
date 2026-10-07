/* Hkline Web · 图表页
 *
 * 交互原则（和手机端刻意不同）：
 *   · 鼠标悬停就是查看：十字线、图例、术语解释都跟着指针走，不用先点
 *   · 右键是「在这里做事」：在这个价位建提醒 / 画水平线 / 记一笔
 *   · 键盘直达：打字就是搜品种，打数字就是换周期，Alt+字母选画线工具，⌘Z 撤销
 *   · 画线不是一个模式：左侧工具栏常驻，选了工具就在当前图上画，画完回到光标
 *   · 大屏同时看：1 / 2 / 3 / 4 / 6 / 8 / 9 / 12 / 16 图布局，每格各自的品种与周期；
 *     品种、周期、十字线、时间轴四样可以跨图联动；格子小了自动降级（只留主图、图例一行、字号小一档）
 *
 * 布局槽位（宽高都能拖，尺寸只存本机，见 chartLayout.ts / app/sizes.ts）：
 *   深度梯子列 —— 价格轴与侧栏之间，默认 240（160–480）/ 关 0
 *   底部抽屉   —— 图表区下方，默认 280（160 到页面高 60%）/ 关 0
 *   侧栏小部件 —— 「自选」视图里按 st.slots.widgets 的顺序堆叠，块与块之间能拖高度
 */
import { st, save, LAYOUT_N, ensureCells, FILL_SYMBOLS, type CellCfg, type PanelId, type Layout } from '../app/store'
import { sizes, saveSizes } from '../app/sizes'
import { degradeFor } from '../chart/panes'
import { applyPageSizes, placePageSplits, applyGrid, placeGridSplits } from './chartLayout'
import { installOrderFlow, mountLadder, mountDrawer, widgetHTML, mountWidgets, flowPanel, heatButtonHTML, toggleHeat, indicatorRowHTML, indicatorRowClick, isCollapsed } from '../orderflow'
import { deleteAlert } from '../alerts/model'
import { alertDesc } from '../alerts/panel'
import { activeAlerts, createAlertAt, moveAlert, onAlertsChange, reconcileDrawingAlerts, migrateDrawingFlags, alertLevel, drawingIdOf } from '../alerts/model'
import { SECOND_IVS, isSecondIv, isCustomIv, registerCustomIv, minutesIv, streamIvOf, startSeconds, onSecondsTick, secondBars, secondLastBar, customKlines, customTick, customBase } from '../chart/intervals'
import { VPVR_MODES } from '../chart/overlays'
import { keyLevelsShown, keyLevelsOf, levelsForInterval } from '../chart/keyLevels'
import { renderAlertsPanel, alertsPanelClick, openCreateAlert, installAlerts, alertStreams, askNotify } from '../alerts/panel'
import { hooks, go } from '../app/shell'
import { openNoteDialog, noteRuleText } from '../notes/dialog'
import { installNoteSync, noteState, onNotesSynced, dropShot } from '../notes/sync'
import { renderTradesPanel, tradesPanelClick, installTradesPanel } from '../trades/panel'
import { installWatch, widgetWatch, mountWatch, watchClick, patchWatchRow, takeWatchUndo } from '../watch/widget'
import { $, $$, I, esc, tgt } from '../ui/dom'
import { toast, menu, menuFrom, closeMenu, menuOpen, dialog, dialogs, head, term, type MenuItem } from '../ui/overlay'
import { sym, pctText, cls, priceText, badge, clamp01, countdown, shTime, ratioText, ratioCls } from '../ui/common'
import { TVChart, type Drawing, type DrawingType, type ContextMenuInfo, type AlertLine, type AlertSignal } from '../chart/chart'
import { installDrawing, selectTool, drawTool, drawSticky, toolDone, renderDrawbar, onDrawbarClick, onDrawbarContext, styleFor, canAdd, newDrawing, showQuick, hideQuick, refreshQuick, quickFade, copyDrawing, pasteDrawing, nudge, nudgeEnd } from './drawing'
import { CATALOG, MAX_SUBS, type Bar, type IndicatorId, type IndParams, type SubId } from '../chart/calc'
import { isMoreMain, MORE_PARAM_NAME } from '../chart/mainIndicators'
import { indicatorRows, matchRow, IND_GROUPS } from './indicatorPicker'
import { fmt, fmtCompact, pad, sh, IV_MS } from '../util/format'
import {
  S, on, REST, coolingFor, isRateLimit, klines, attachOI, loadUniverse, fetchDetail, detailOf, setStreams, streamName, streamDebug, wantMeta, marketCap,
  IV_LABEL, IV_SHORT, INTERVALS, TABS, kindName, sectorsOf, rankSearch, type Kind, type Sym, type KlineResult,
} from '../market'
import { settle } from '../market/settle'
import { normalize } from '../market/searchText'
import { PushBuffer, pushKey, alignPushes } from '../chart/pushBuffer'
import { TAIL_MAX, tailNeed, tailFrom, TailResync } from '../market/tail'
import { installCompare, openCompare, refreshCompare, removeCompare } from './compare'
import { bindFootprint, footprintMenuItem } from '../chart/footprint'
import { secondsKlines } from '../chart/secondsHistory'

// ------------------------------------------------------------ 图表格子
interface Cell {
  el: HTMLElement
  host: HTMLElement
  idx: number
  chart: TVChart
  loadToken: number
  more: boolean
  noMore: boolean
  /** K 线在路上：这一格在等的推送缓冲（品种 | 推送周期），到了就补上再切回实时 */
  hold: string | null
}
const cells: Cell[] = []
/** K 线在路上时攒着的推送（行情推送与 K 线并行建连，见 chart/pushBuffer.ts） */
const pushes = new PushBuffer()
/** 冷启动时和品种表并行先发出去的 K 线（品种 | 周期 → 结果），第一次装这一格时直接用 */
const early = new Map<string, { hold: string; res: Promise<KlineResult> }>()
export const allCells = (): readonly Cell[] => cells

type RangeDays = number | 'ytd' | 'all'
const RANGES: [string, string, RangeDays][] = [['1天', '1m', 1], ['5天', '5m', 5], ['1月', '30m', 30], ['3月', '2h', 91], ['6月', '4h', 182], ['今年', '1d', 'ytd'], ['1年', '1d', 365], ['全部', '1w', 'all']]

function cfg(cell: Cell | undefined): CellCfg { return st.cells[cell ? cell.idx : st.active] || st.cells[0] }
export const active = (): Cell | undefined => cells[st.active]

/** 图例副标题：美元指数这类自家服务器给的品种（macro）不是币安的，不挂「币安」，只写「指数」 */
function metaFor(c: CellCfg) {
  const s = sym(c.symbol)
  return { symbol: c.symbol, iv: IV_MS[c.iv], title: c.symbol, sub: `· ${IV_LABEL[c.iv]} · ${s?.macro ? '' : '币安'}${kindName(s)}`, dec: s?.dec ?? 2, badge: badge(s) }
}

/** 图上画的提醒线：这只品种还在等的价格提醒（画线提醒由画线本身表示） */
function priceAlerts(symbol: string): AlertLine[] {
  return activeAlerts(symbol).filter(a => a.kind === 'price').flatMap(a => { const p = alertLevel(a); return p == null ? [] : [{ price: p, id: a.id, symbol: a.symbol, kind: a.kind, created: a.created }] })
}
/** 图上的提醒线：这只品种还在生效的画线提醒（几何用提醒自己存的那份）。线在、画出来了图就不画，
 *  线删了 / 画线整层藏着才画（2026-10-06：画线和提醒互相独立） */
function lineSignals(symbol: string): AlertSignal[] {
  const pre = drawingIdOf(symbol, '')
  return activeAlerts(symbol).filter(a => a.kind === 'drawing' && a.lines.length > 0)
    .map(a => ({ id: a.id, drawingID: a.drawingID?.startsWith(pre) ? a.drawingID.slice(pre.length) : null, lines: a.lines }))
}
/** 在价位 p 直接建一条价格提醒（点 / 拖价格轴、右键菜单） */
function quickAlert(symbol: string, p: number): void {
  const a = createAlertAt(symbol, p); if (!a) return
  toast('提醒已创建', a.title, 'bell'); askNotify()
}

function buildCells(): void {
  const n = LAYOUT_N[st.layout] || 1
  ensureCells(st, n)
  st.active = Math.min(st.active, n - 1)
  const area = $('#chartArea'); area.dataset.layout = st.layout
  hideQuick()
  while (cells.length > n) { const c = cells.pop(); if (c) { cellRO?.unobserve(c.el); c.chart.destroy(); c.el.remove() } }
  for (let i = cells.length; i < n; i++) cells.push(makeCell(i))
  cells.forEach((c, i) => c.el.classList.toggle('active', i === st.active))
  layoutGrid()
  save(); refreshStreams()
}

/** 多图网格：按布局与本机比例排格子、摆格子间的分隔线 */
function layoutGrid(): void {
  const area = $('#chartArea'); if (!area) return
  applyGrid(area, st.layout, cells.map(c => c.el))
  placeGridSplits(area, st.layout, layoutGrid)
}

/**
 * 格子降级：按格子自己的尺寸算（不按窗口），宽 < 640 或高 < 360 只留主图、图例一行、
 * 价格轴字号小一档；宽 < 420 再去掉成交量。格子底栏也跟着收（见 app.css .c-narrow / .c-tiny）。
 */
let cellRO: ResizeObserver | null = null
const cellOf = new WeakMap<Element, Cell>()
function watchCell(cell: Cell): void {
  cellRO ||= new ResizeObserver(es => {
    for (const e of es) {
      const c = cellOf.get(e.target); if (!c) continue
      const w = e.contentRect.width, h = e.contentRect.height
      if (!w || !h) continue
      c.el.classList.toggle('c-narrow', w < 640)
      c.el.classList.toggle('c-tiny', w < 420)
      c.el.classList.toggle('c-short', h < 360)
      c.chart.setDegrade(degradeFor(w, h))
    }
  })
  cellOf.set(cell.el, cell)
  cellRO.observe(cell.el)
}

/** 时间轴联动：一格动了时间轴，其余格子套同一段时间（防回声） */
let syncingView = false
function linkView(from: Cell, t0: number, t1: number): void {
  if (!st.linkTime || syncingView || cells.length < 2) return
  syncingView = true
  try { cells.forEach(o => { if (o !== from) o.chart.syncView(t0, t1) }) } finally { syncingView = false }
}

// 回归脚本（scripts/regress.mjs「布局与拖动」）读：各格子的品种、周期、可见时间段、同步来的十字线、降级档；行情连接
;(globalThis as unknown as { __cells?: () => unknown }).__cells = () => cells.map(c => {
  const g = c.chart.geometry(), k = cfg(c)
  const b = c.chart.bars
  // 压测脚本（scripts/stress.mjs）还读：图上真的装的是哪只、哪个周期、最后一根收盘价（验多图不串数据），以及 K 线里有没有断档（验断网后补齐）
  let holes = 0
  for (let j = 1; j < b.length; j++) if (b[j].t - b[j - 1].t > c.chart.iv && c.chart.iv < 864e5) holes++
  return { symbol: k.symbol, iv: k.iv, t0: g ? g.timeOf(g.from) : null, t1: g ? g.timeOf(g.to) : null, cross: c.chart.extCross, deg: c.chart.deg, bars: b.length, spacing: c.chart.spacing, plotW: c.chart.plotW(), panes: c.chart._panes?.map(p => [p.id, p.y, p.h]),
    metaSym: c.chart.meta.symbol, metaIv: c.chart.iv, last: b[b.length - 1]?.c ?? null, lastT: b[b.length - 1]?.t ?? null, holes, empty: !$('.cell-empty', c.el).hidden }
})
;(globalThis as unknown as { __px?: (s: string) => number | null }).__px = s => sym(s)?.price ?? null
;(globalThis as unknown as { __stream?: () => unknown }).__stream = streamDebug
// 回归脚本「指标」段读：关键价位画了哪些、VWAP 第一段从哪根起、累计量差的分界与两条、大单与散户有没有数、图例口径小字
;(globalThis as unknown as { __ind?: (i?: number) => unknown }).__ind = (i = 0) => {
  const ch = cells[i]?.chart
  if (!ch) return null
  const nn = (s?: (number | null)[]) => s ? s.filter(v => v != null).length : 0
  const first = (s?: (number | null)[]) => s ? s.findIndex(v => v != null) : -1
  const vw = ch.series.vwap?.[0], cvd = ch.series.cvd, wh = ch.series.whale
  return {
    bars: ch.bars.length, iv: ch.iv, t0: ch.bars[0]?.t ?? null,
    keys: keyLevelsShown(ch), keysAll: levelsForInterval(keyLevelsOf(ch), ch.iv).map(l => l.label),
    vwap: vw ? { first: first(vw), firstT: ch.bars[first(vw)]?.t ?? null, n: nn(vw) } : null,
    cvd: cvd ? { tot: nn(cvd[0]), spot: nn(cvd[1]), con: nn(cvd[2]), seam: first(cvd[1]) } : null,
    whale: wh ? { big: nn(wh[0]), small: nn(wh[1]), first: first(wh[0]), last: [wh[0][wh[0].length - 1], wh[1][wh[1].length - 1]] } : null,
  }
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
  const cell = { el, host, idx: i, loadToken: 0, more: false, noMore: false, hold: null } as unknown as Cell
  cell.chart = new TVChart(host, {
    onActivate: () => setActive(cell.idx),
    onNeedMore: () => { void loadMore(cell) },
    onCrosshairMove: t => { if (st.linkCross) cells.forEach(o => { if (o !== cell) o.chart.syncCrosshair(t) }) },
    onContextMenu: info => chartContextMenu(cell, info),
    onLegendAction: (id, act, btn) => legendAction(id, act, btn),
    onToolDone: d => toolDone(cell, d),
    onSelectDrawing: d => showQuick(d, cell),
    onDrawingsChanged: () => drawingsChanged(cell),
    onAlertCreate: p => quickAlert(cfg(cell).symbol, p),
    onAlertMove: (a, p) => { if (a.id) moveAlert(a.id, p) },
    drawColor: () => st.drawColor,
    drawStyle: styleFor,
    canAdd: add => canAdd(cfg(cell).symbol, add),
    onDrawDrag: quickFade,
    onAutoChange: v => { $('[data-act="auto"]', el)?.setAttribute('aria-pressed', String(v)) },
    // 副图高：所有格子共用一份比例，松手落本机
    onPaneResize: r => {
      if (r) sizes.panes = r; else delete sizes.panes
      saveSizes()
      cells.forEach(o => { if (o !== cell) o.chart.setPaneRatios(sizes.panes ?? null) })
    },
    onViewChange: (t0, t1) => linkView(cell, t0, t1),
  })
  cell.chart.setPaneRatios(sizes.panes ?? null)
  cell.chart.setIndicators(structuredClone(st.ind))
  if (st.params) for (const [k, p] of Object.entries(st.params)) cell.chart.params[k as IndicatorId] = structuredClone(p)
  cell.chart.setMagnet(st.magnet)
  cell.chart.setVpvrMode(st.vpvrMode)
  cell.chart.drawingsHidden = st.drawHidden
  bindFootprint(cell.chart, i)
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
  watchCell(cell)
  void loadCell(cell)
  return cell
}

function showCellEmpty(cell: Cell, msg: string | null, quiet = false): void {
  const e = $('.cell-empty', cell.el); if (!e) return
  e.hidden = !msg
  if (msg) e.innerHTML = quiet ? `<div class="empty">${I('trades', 'icon-24')}<div>${esc(msg)}</div></div>` : `<div class="empty">${I('wifiOff', 'icon-24')}<div>${esc(msg)}</div><button class="btn secondary sm" style="margin-top:12px" data-retry>重试</button></div>`
}
/** 取 K 线：秒级从逐笔攒的内存里拿，自定义分钟从原生周期并，其余走交易所。
 *  alive：这一格还要不要这份（换了品种 / 周期就不要了）——在限流闸里排队的作废请求不发、不占预算 */
async function barsFor(symbol: string, iv: string, endTime?: number, alive?: () => boolean, withOI = true): Promise<{ bars: Bar[]; ok: boolean; error?: string }> {
  if (isSecondIv(iv)) return secondsKlines(symbol, iv, endTime, alive)
  if (isCustomIv(iv)) return customKlines(symbol, iv, endTime, alive)
  return klines(symbol, iv, endTime, 1500, withOI, false, alive)
}

async function retryLoad(cell: Cell): Promise<void> {
  if (!S.live) { await loadUniverse(); if (S.live) { afterUniverse(); return } }
  void loadCell(cell)
}

async function loadCell(cell: Cell, then?: () => void): Promise<void> {
  const c = cfg(cell), token = ++cell.loadToken
  cell.noMore = false
  cell.chart.setDrawings(drawingsFor(c.symbol))
  if (lastSnap[c.symbol] == null) rebaseDrawings(c.symbol)
  // 推送不等 K 线：取数期间这一格的推送先攒进缓冲（上一次取数的缓冲在这里撒手，换品种 / 周期即作废）
  if (cell.hold) { pushes.release(cell.hold); cell.hold = null }
  const siv = streamIvOf(c.iv)
  const pre = early.get(`${c.symbol}|${c.iv}`)
  if (pre) early.delete(`${c.symbol}|${c.iv}`)
  if (pre) cell.hold = pre.hold                    // 冷启动先发的那次：缓冲它开着，接过来
  else if (siv) { cell.hold = pushKey(c.symbol, siv); pushes.open(cell.hold) }
  const { bars, ok, error } = await (pre ? pre.res : barsFor(c.symbol, c.iv, undefined, () => token === cell.loadToken && !cell.chart.dead, false))
  // 被后一次取数顶掉：缓冲已经由后一次撒手，这里什么都不动
  if (token !== cell.loadToken) return
  const hold = cell.hold
  cell.hold = null
  const late = hold && bars.length ? pushes.take(hold, bars[bars.length - 1].t) : []
  if (hold) pushes.release(hold)
  if (late.length && !isCustomIv(c.iv)) alignPushes(bars, late)
  if (ok && !bars.length && isSecondIv(c.iv)) showCellEmpty(cell, '等第一笔成交', true)
  else if (!ok || !bars.length) {
    cell.chart.setData([], metaFor(c))
    const limited = !ok && isRateLimit(error)
    showCellEmpty(cell, ok ? `${c.symbol} 在这个周期上还没有 K 线`
      : limited ? `币安限流了，${c.symbol} 的 K 线冷却后自动重取`
      : `取不到 ${c.symbol} 的 K 线${error ? `（${error.split(' ')[0]}）` : ''}`)
    // 限流：冷却一过这一格自己再取（期间换了品种 / 周期就作废），不让用户对着空图去点
    if (limited) setTimeout(() => { if (token === cell.loadToken) void loadCell(cell) }, Math.max(coolingFor(REST), 5000) + 500)
  } else showCellEmpty(cell, null)
  cell.chart.setData(bars, metaFor(c))
  refreshCompare()
  // 自定义分钟：攒下的原生周期推送逐根并进当前格（和实时时同一条路）
  if (late.length && isCustomIv(c.iv)) for (const p of late) cell.chart.updateBar(customTick(c.symbol, c.iv, p))
  // 持仓量副图不在首屏：品种停稳再取（连切时中间划过的品种不取）
  if (ok && bars.length && !isSecondIv(c.iv) && !isCustomIv(c.iv)) {
    settle.whenSettled(`oi:${cell.idx}`, () => { if (token === cell.loadToken && !cell.chart.dead) void attachOI(c.symbol, c.iv, cell.chart.bars) })
  }
  // 测量框是临时的，不进存档
  const ds = drawingsFor(c.symbol)
  for (let k = ds.length - 1; k >= 0; k--) if (ds[k].type === 'measure') ds.splice(k, 1)
  cell.chart.setDrawings(ds)
  refreshQuick()
  cell.chart.setAlerts(priceAlerts(c.symbol))
  cell.chart.setAlertSignals(lineSignals(c.symbol))
  cell.chart.setStale(st.stale)
  then?.()
  if (cell.idx === st.active) { renderToolbar(); renderPanel() }
}

/** 断线重连 / 页面藏久了回来：把这段时间收线的几根补回图上（币安只推当前那一根，错过的不会再推），
 *  断线前那一根的开高低收也按交易所的定稿盖掉。只取尾巴、逐根并进去，视口与往前翻过的历史都不动；
 *  断得太久（超过 TAIL_MAX 根）整段重取。取数期间这一格的推送照 loadCell 先攒着，取到再按顺序补上 */
const tailing = new Set<Cell>()
async function resyncTail(cell: Cell, tries = 0): Promise<void> {
  const c = cfg(cell), bars = cell.chart.bars
  if (tailing.has(cell) || cell.hold || cell.chart.dead || isSecondIv(c.iv) || !bars.length) return
  const n = tailNeed(bars[bars.length - 1].t, IV_MS[c.iv], Date.now())
  if (n > TAIL_MAX) { void loadCell(cell); return }
  const token = cell.loadToken, alive = () => token === cell.loadToken && !cell.chart.dead
  const siv = streamIvOf(c.iv), hold = siv ? pushKey(c.symbol, siv) : null
  if (hold) { pushes.open(hold); cell.hold = hold }
  tailing.add(cell)
  try {
    const r = isCustomIv(c.iv) ? await customKlines(c.symbol, c.iv, undefined, alive) : await klines(c.symbol, c.iv, undefined, n, false, false, alive)
    // 期间换了品种 / 周期：loadCell 已经接手并撒掉了这份缓冲
    if (!alive()) return
    cell.hold = null
    const late = hold ? pushes.take(hold, 0) : []
    if (hold) pushes.release(hold)
    if (r.ok) for (const b of tailFrom(cell.chart.bars, r.bars)) cell.chart.updateBar(b)
    for (const p of late) cell.chart.updateBar(isCustomIv(c.iv) ? customTick(c.symbol, c.iv, p) : p)
    // 没取到（刚连上时网络还在抖、限流）：冷却过了再补，最多再试三次；之后的重连 / 回前台还会再补
    if (!r.ok && tries < 3) setTimeout(() => { if (alive()) void resyncTail(cell, tries + 1) }, Math.max(coolingFor(REST), 5000) + 500)
  } finally { tailing.delete(cell) }
}
const tailGate = new TailResync()

async function loadMore(cell: Cell): Promise<void> {
  if (cell.more || cell.noMore || !cell.chart.bars.length) return
  cell.more = true; cell.chart.loadingMore = true
  const c = cfg(cell), token = cell.loadToken
  const { bars, ok } = await barsFor(c.symbol, c.iv, cell.chart.bars[0].t, () => token === cell.loadToken && !cell.chart.dead)
  cell.more = false; cell.chart.loadingMore = false
  if (token !== cell.loadToken) return
  if (!ok) return
  if (!bars.length) { cell.noMore = true; return }
  cell.chart.prependData(bars)
  refreshCompare()
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
  settle.noteSwitch()
  c.symbol = symbol; save()
  if (st.linkSymbol && cells.length > 1) return linkAll(symbol)
  void loadCell(cell); refreshStreams(); renderToolbar(); renderPanel()
}

function setIv(iv: string, cell: Cell | undefined = active()): void {
  if (!cell) return
  const c = cfg(cell); if (c.iv === iv) return
  settle.noteSwitch()
  c.iv = iv
  // 周期跨图同步：其余格子一起换
  if (st.linkIv && cells.length > 1) cells.forEach(o => { const oc = cfg(o); if (o !== cell && oc.iv !== iv) { oc.iv = iv; void loadCell(o) } })
  save(); void loadCell(cell); refreshStreams(); renderToolbar()
}

// ------------------------------------------------------------ 画线
export function drawingsFor(s: string): Drawing[] { return (st.drawings[s] ||= []) }
/** 一步撤销：某只品种的画线（json），批量删除指标时再带上删之前的指标（ind） */
interface Snap { s: string; json: string; ind?: string }
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
  save(); renderToolbar(); refreshQuick()
}
/** 这只品种的画线是整份装进来的（打开时从本机存档、云端同步装回来）：把眼下的样子记成撤销的基准。
 *  基准空着的时候第一次改动拿「[]」当改之前的样子——刷新页面后挪一下线再 ⌘Z，这只品种的画线整份没了；
 *  同步装回来不更新基准的话，下一次本机改动的撤销会把同步来的那份一起退掉 */
export function rebaseDrawings(s: string): void { lastSnap[s] = snapOf(s) }
/** 锁定全部是工具栏上的一个开关（同 TradingView），不进撤销栈；但要把锁后的样子记成每只品种的基准——
 *  不记的话下一次随手挪一条线，撤销会把「解锁」连同那一下一起退回去。测量尺是临时的，不锁 */
export function lockAllDrawings(on: boolean): void {
  for (const s of Object.keys(st.drawings)) {
    for (const d of st.drawings[s]) if (d.type !== 'measure') d.locked = on
    if (lastSnap[s] != null) lastSnap[s] = snapOf(s)
  }
  cells.forEach(c => { c.chart.dirty = true })
}
function setDrawingsOf(s: string, list: Drawing[]): void {
  st.drawings[s] = list; lastSnap[s] = snapOf(s)
  cells.forEach(c => { if (cfg(c).symbol === s) c.chart.setDrawings(st.drawings[s]) })
  reconcileDrawingAlerts(s, st.drawings[s])
}
function applyInd(): void { cells.forEach(c => c.chart.setIndicators(structuredClone(st.ind))) }
function restoreSnap(u: Snap, toStack: Snap[]): void {
  toStack.push({ s: u.s, json: snapOf(u.s), ...(u.ind != null ? { ind: JSON.stringify(st.ind) } : {}) })
  setDrawingsOf(u.s, JSON.parse(u.json) as Drawing[])
  if (u.ind != null) { st.ind = JSON.parse(u.ind) as typeof st.ind; applyInd() }
  hideQuick(); save(); renderToolbar()
}
function undo(): void { const u = undoStack.pop(); if (!u) return; restoreSnap(u, redoStack); toast('已撤销', '⌘ Y 或 ⌘ ⇧ Z 重做', 'undo', 1800) }
function redo(): void { const u = redoStack.pop(); if (!u) return; restoreSnap(u, undoStack) }

function toggleHideDrawings(): void {
  st.drawHidden = !st.drawHidden
  applyDrawingsHidden()
  save()
  toast(st.drawHidden ? '画线已隐藏' : '画线已显示', '⌘ ⌥ H 切换', st.drawHidden ? 'eyeOff' : 'eye', 1500)
}

/** st.drawHidden → 各图格与画线工具条（本机切换、手机 / 别的电脑同步过来的 drawingsHidden 共用）。
 *  藏着时画线不画、点不中，提醒照判、图上改画提醒线（TVChart.signalsShown） */
export function applyDrawingsHidden(): void {
  cells.forEach(c => { c.chart.drawingsHidden = st.drawHidden; c.chart.dirty = true })
  if (st.drawHidden) hideQuick()
  renderDrawbar()
}

// ---- 批量删除：这只品种的全部画线 / 全部指标 / 全部，菜单上是实时的数量，⌘Z 能撤回来
const indCount = (): number => MAIN_TOGGLES.filter(k => st.ind[k as MainToggle]).length + (st.ind.mains?.length ?? 0) + st.ind.subs.length
const drawCount = (s: string): number => drawingsFor(s).filter(d => d.type !== 'measure').length
function clearMenu(b: HTMLElement): void {
  const s = cfg(active()).symbol, nd = drawCount(s), ni = indCount()
  menuFrom(b, [{ header: '删除' },
    { icon: 'trend', label: '全部画线', sc: `${nd} 条`, disabled: !nd, run: () => bulkDelete(true, false) },
    { icon: 'indicators', label: '全部指标', sc: `${ni} 个`, disabled: !ni, run: () => bulkDelete(false, true) },
    { icon: 'trash', label: '全部', sc: `${nd + ni} 项`, disabled: !(nd + ni), run: () => bulkDelete(true, true) }], { width: 220 })
}
function bulkDelete(draw: boolean, ind: boolean): void {
  const s = cfg(active()).symbol
  const nd = draw ? drawCount(s) : 0, ni = ind ? indCount() : 0
  if (!nd && !ni) return
  const snap: Snap = { s, json: snapOf(s) }
  if (ni) {
    snap.ind = JSON.stringify(st.ind)
    MAIN_TOGGLES.forEach(k => { st.ind[k as MainToggle] = false }); st.ind.mains = []; st.ind.subs = []
    applyInd()
  }
  if (nd) setDrawingsOf(s, [])
  undoStack.push(snap); redoStack.length = 0
  hideQuick(); save(); renderToolbar()
  toast(`已删除${[nd ? ` ${nd} 条画线` : '', ni ? ` ${ni} 个指标` : ''].filter(Boolean).join('、')}`, '⌘ Z 撤销', 'trash')
}
// 回归脚本（scripts/regress.mjs「画线」）读：撤销栈深度、手里的工具、连续画、当前格子看得见的开高低收（验磁吸）
;(globalThis as unknown as { __draw?: () => unknown }).__draw = () => {
  const c = active(), v = c?.chart.visible()
  return { undo: undoStack.length, redo: redoStack.length, tool: drawTool(), sticky: drawSticky(), ohlc: c && v ? c.chart.bars.slice(v.from, v.to + 1).flatMap(b => [b.o, b.h, b.l, b.c]) : [] }
}

// ------------------------------------------------------------ 工具栏
const LAYOUT_ICON: Record<Layout, string> = { '1': 'layout1', '2': 'layout2', '2v': 'layout2v', '3': 'layout3', '4': 'layout4', '6': 'layout6', '8': 'layout8', '9': 'layout9', '12': 'layout12', '16': 'layout16' }
const LAYOUT_NAME: [Layout, string][] = [['1', '一图'], ['2', '左右两图'], ['2v', '上下两图'], ['3', '左一右二'], ['4', '四图'], ['6', '六图（三列两行）'], ['8', '八图（四列两行）'], ['9', '九图（三列三行）'], ['12', '十二图（四列三行）'], ['16', '十六图（四列四行）']]
function layoutMenu(b: HTMLElement): void {
  const items: MenuItem[] = [{ header: '布局' }, ...LAYOUT_NAME.map(([k, l]): MenuItem => ({ icon: LAYOUT_ICON[k], label: l, checked: st.layout === k, sc: k === st.layout ? '当前' : '', run: () => setLayout(k) })), '-',
    { header: '多图联动' },
    { label: '十字线跨图同步', check: true, checked: st.linkCross, run: () => { st.linkCross = !st.linkCross; if (!st.linkCross) cells.forEach(c => c.chart.syncCrosshair(null)); save() } },
    { label: '品种跨图同步', check: true, checked: st.linkSymbol, sc: st.linkSymbol ? '' : '换一格全跟着换', run: () => { st.linkSymbol = !st.linkSymbol; save(); if (st.linkSymbol) linkAll(cfg(active()).symbol) } },
    { label: '周期跨图同步', check: true, checked: st.linkIv, run: () => { st.linkIv = !st.linkIv; save(); if (st.linkIv) { const iv = cfg(active()).iv; cells.forEach(c => { const cc = cfg(c); if (cc.iv !== iv) { cc.iv = iv; void loadCell(c) } }); save(); refreshStreams(); renderToolbar() } } },
    { label: '时间轴跨图同步', check: true, checked: st.linkTime, run: () => { st.linkTime = !st.linkTime; save(); const a = active(); if (st.linkTime && a) { const g = a.chart.geometry(); if (g) linkView(a, g.timeOf(g.from), g.timeOf(g.to)) } } }]
  menuFrom(b, items)
}
/** 品种跨图同步：一格换了品种，其余格一起换（周期各自保留） */
function linkAll(symbol: string): void {
  settle.noteSwitch()
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
    <button class="tb-btn" id="tbInd" aria-label="指标" data-tip="指标" data-kbd="/">${I('indicators')}<span class="tb-label">指标</span></button>
    <button class="tb-btn${st.compareSymbols.length ? ' on' : ''}" id="tbCompare" aria-label="对比" data-tip="叠加别的品种，按百分比比涨跌">${I('compare')}<span class="tb-label">对比</span>${st.compareSymbols.length ? `<span class="num tb-count">${st.compareSymbols.length}</span>` : ''}</button>
    <button class="tb-btn" id="tbAlert" aria-label="提醒" data-tip="在现价创建提醒" data-kbd="Alt A">${I('bellPlus')}<span class="tb-label">提醒</span></button>
    <button class="tb-btn" id="tbNote" aria-label="记一笔" data-tip="把这一刻记下来">${I('note')}<span class="tb-label">记一笔</span></button>
    ${heatButtonHTML()}
    <div class="tb-right">
      <button class="ibtn sm" id="tbUndo" aria-label="撤销" data-tip="撤销" data-kbd="⌘ Z" ${undoStack.length ? '' : 'disabled style="opacity:.4"'}>${I('undo')}</button>
      <button class="ibtn sm" id="tbRedo" aria-label="重做" data-tip="重做" data-kbd="⌘ Y" ${redoStack.length ? '' : 'disabled style="opacity:.4"'}>${I('redo')}</button>
      <span class="tb-sep"></span>
      <button class="ibtn sm" id="tbLayout" aria-label="布局" data-tip="图表布局">${I(LAYOUT_ICON[st.layout])}</button>
      <button class="ibtn sm" id="tbShot" aria-label="截图" data-tip="保存图表截图" data-kbd="⌥ S">${I('camera')}</button>
      <button class="ibtn sm" id="tbShare" aria-label="分享" data-tip="分享">${I('share')}</button>
      <button class="ibtn sm" id="tbFull" aria-label="全屏" data-tip="全屏" data-kbd="⇧ F">${I('fullscreen')}</button>
    </div>`
}
function onToolbarClick(e: MouseEvent): void {
  const b = tgt(e).closest<HTMLElement>('button'); if (!b) return
  if (b.dataset.iv) return setIv(b.dataset.iv)
  const c = cfg(active())
  switch (b.id) {
    case 'tbSymbol': return openSearch()
    case 'tbMoreIv': return intervalMenu(b)
    case 'tbInd': return openIndicators()
    case 'tbCompare': return openCompare()
    case 'tbAlert': return openAlert()
    case 'tbNote': return openNote()
    case 'tbHeat': return toggleHeat()
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
  const groups: [string, string[]][] = [['秒', [...SECOND_IVS]], ['分钟', ['1m', '3m', '5m', '15m', '30m']], ['小时', ['1h', '2h', '4h', '6h', '8h', '12h']], ['日及以上', ['1d', '1w', '1M']]]
  if (st.customIvs.length) groups.push(['自定义', st.customIvs.filter(iv => IV_LABEL[iv])])
  // 照 TradingView：每行行尾一颗星，点星钉到周期条上 / 取消，菜单不关；自定义周期行尾是 ×，点了删掉
  const star = (on: boolean): string => I(on ? 'star' : 'starLine', on ? 'icon-16 pin on' : 'icon-16 pin')
  const items: MenuItem[] = groups.flatMap(([h, ivs]): MenuItem[] => [{ header: h }, ...ivs.map((iv): MenuItem => {
    const base = { label: IV_LABEL[iv], checked: iv === c.iv, check: true, run: () => setIv(iv) }
    if (isCustomIv(iv)) return { ...base, trail: I('close', 'icon-16'), trailTip: '移除', trailRun: () => { st.customIvs = st.customIvs.filter(x => x !== iv); save(); intervalMenu(btn) } }
    if (!INTERVALS.includes(iv)) return base
    return { ...base, trail: star(st.pinned.includes(iv)), trailTip: '钉到周期条', trailRun: el => {
      const on = !st.pinned.includes(iv)
      st.pinned = on ? INTERVALS.filter(x => st.pinned.includes(x) || x === iv) : st.pinned.filter(x => x !== iv)
      save(); renderToolbar()
      el.innerHTML = star(on)
    } }
  })])
  items.push('-', footprintMenuItem(st.active, c.iv))
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
  if (act === 'cmpRemove') { removeCompare(id); return }
  if (act === 'remove') {
    if (isMainToggle(id)) st.ind[id] = false
    else if (isMoreMain(id)) st.ind.mains = (st.ind.mains ?? []).filter(x => x !== id)
    else st.ind.subs = st.ind.subs.filter(x => x !== id)
    cells.forEach(c => c.chart.setIndicators(st.ind)); save()
    toast(`已移除 ${CATALOG[id as IndicatorId]?.name || id}`, '在「指标」里可以加回来', 'close', 2200)
  }
  if (act === 'settings' && id in CATALOG) openParams(id as IndicatorId)
}
/** 在价位 p 画一条水平线（右键菜单、订单流「在这里画线」）：同族样式、到上限就不画 */
function addHlineAt(cell: Cell, t: number, p: number): void {
  const s = cfg(cell).symbol, d = newDrawing('hline', [{ t, p }])
  if (!cell.chart.editable() || !canAdd(s, [d])) return
  drawingsFor(s).push(d); cell.chart.dirty = true; drawingsChanged(cell)
}
function chartContextMenu(cell: Cell, info: ContextMenuInfo): void {
  // 拿着工具时右键 = 放下（连续画也退出），不弹菜单
  if (drawTool()) { cell.chart.cancelDraft(); selectTool(null); return }
  const c = cfg(cell), s = sym(c.symbol), p = info.price
  const pt = p != null ? fmt(p, s?.dec ?? 2) : ''
  const items: MenuItem[] = []
  const dr = info.drawing
  if (dr) {
    items.push({ header: '这条画线' }, { icon: 'lock', label: dr.locked ? '解锁' : '锁定', run: () => { dr.locked = !dr.locked; drawingsChanged(cell) } },
      { icon: 'link', label: '复制', sc: '⌘ C', disabled: dr.type === 'measure', run: () => { cell.chart.selected = dr; cell.chart.dirty = true; copyDrawing(cell) } },
      { icon: 'trash', label: '删除', sc: 'Delete', run: () => { cell.chart.selected = dr; cell.chart.deleteSelected() } }, '-')
  }
  if (p != null) items.push(
    { icon: 'bellPlus', label: `在 ${pt} 创建提醒`, run: () => quickAlert(c.symbol, p) },
    { icon: 'hline', label: `在 ${pt} 画水平线`, sc: 'Alt H', run: () => addHlineAt(cell, info.time, p) },
    { icon: 'note', label: '在这根 K 线记一笔…', run: () => openNote(info.time, p) },
    { icon: 'link', label: `复制价格 ${pt}`, run: () => { void navigator.clipboard?.writeText(p.toFixed(s?.dec ?? 2)); toast('已复制', pt, 'check', 1500) } }, '-')
  items.push(
    { label: '重置视图', icon: 'candles', sc: 'Alt R', run: () => cell.chart.resetView() },
    { label: '对数坐标', check: true, checked: cell.chart.log, run: () => { cell.chart.setLog(!cell.chart.log); $('[data-act="log"]', cell.el)?.setAttribute('aria-pressed', String(cell.chart.log)) } },
    { label: '隐藏画线', check: true, checked: st.drawHidden, sc: '⌘ ⌥ H', run: toggleHideDrawings },
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
  if (!page.clientWidth) return   // 图表页没在显示：回来时 pageShown 再排
  applyPageSizes(page, { ladder, panel, drawer })
  placePageSplits(page, { ladder, panel, drawer }, layoutSlots)
  layoutGrid()
  cells.forEach(c => c.chart.resize())
}
function renderSlots(): void {
  mountLadder($('#ladderSlot')); mountDrawer($('#drawerSlot'))
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
  if (st.panel) st.lastPanel = st.panel
  save(); renderRail(); renderPanel()
}
/** Alt ⇧ W：开 / 关侧栏（开的时候回到上一次看的那一栏） */
function togglePanel(): void {
  st.panel = st.panel ? null : st.lastPanel || 'watch'
  if (st.panel) st.lastPanel = st.panel
  save(); renderRail(); renderPanel(); layoutSlots()
}
export function openPanel(p: PanelId): void { st.panel = p; st.lastPanel = p; save(); renderRail(); renderPanel() }

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
  const widgets = st.slots.widgets.map(w => w === 'watch' ? widgetWatch() : w === 'detail' ? `<div class="detail ${isCollapsed('detail') ? 'collapsed' : ''}" id="detail"></div>` : widgetHTML(w)).join('')
  el.innerHTML = widgets || '<div class="empty">没有小部件</div>'
  renderDetail()
  mountWatch(el)
  mountWidgets(el)
}
function collapseBtn(c: boolean): string {
  return `<button class="ibtn xs" data-of="collapse" aria-label="${c ? '展开' : '收起'}" aria-expanded="${!c}" data-tip="${c ? '展开' : '收起'}">${I('chevronDown', 'icon-16 of-chev')}</button>`
}
function onPanelClick(e: MouseEvent): void {
  const t = tgt(e)
  if (st.panel === 'watch' && watchClick(e)) return
  const star = t.closest<HTMLElement>('[data-star]'); if (star) { toggleWatch(star.dataset.star || ''); return }
  const tr = t.closest<HTMLElement>('tr[data-sym]'); if (tr) return openSymbol(tr.dataset.sym || '')
  const sec = t.closest<HTMLElement>('[data-sector]'); if (sec) { hooks.openSector?.(sec.dataset.sector || ''); return }
  if (st.panel === 'alerts' && alertsPanelClick(e, cfg(active()).symbol)) return
  if (t.closest('#nNew')) return openNote()
  const delNote = t.closest<HTMLElement>('[data-del-note]'); if (delNote) { e.stopPropagation(); const id = delNote.dataset.delNote || ''; st.notes = st.notes.filter(n => n.id !== id); dropShot(id); save(); renderPanel(); return }
  if (st.panel === 'trades' && tradesPanelClick(e, cfg(active()).symbol)) return
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
/** 取当前品种的五个慢数（一分钟最多一次，见 fetchDetail）；经「停稳」闸调 */
function detailNow(): void { const k = cfg(active())?.symbol; if (k) void fetchDetail(k) }
function renderDetail(): void {
  const el = $('#detail'); if (!el) return
  const k = cfg(active()).symbol, s = sym(k)
  if (!s) { el.innerHTML = ''; return }
  // 五个慢数不在首屏：品种停稳再取；没到之前格子里是「—」，到了自己补上
  settle.whenSettled('detail', detailNow)
  wantMeta([k])
  const d = detailOf(k) || { t: 0 }
  const secs = sectorsOf(s)
  const cap = marketCap(k)
  const w = isWatched(k)
  const basis = s.mark && s.index ? (s.mark / s.index - 1) * 100 : null
  // 一屏放得下：板块标签并进名字下面那一行，十二格改成「名 值」四行三列
  const secHTML = secs.slice(0, 3).map(x => `<button class="sec-link" data-sector="${x.id}">${esc(x.cn)}</button>`).join('')
  const cell = (k: string, v: string, c = '', f = ''): string => `<div><span class="k">${k}</span><span class="v num ${c}"${f ? ` data-f="${f}"` : ''}>${v}</span></div>`
  el.innerHTML = `<div class="dh">${badge(s, 'lg')}<div class="names"><div class="code">${esc(s.code)}<span class="kind">${kindName(s)}</span></div><div class="cn">${esc(s.cn || '')}${cap ? `${s.cn ? ' · ' : ''}${term('市值')} <span class="num" data-f="cap">${fmtCompact(cap)}</span>` : ''}${secHTML ? `<span class="secs">${secHTML}</span>` : ''}</div></div>
      <button class="ibtn sm" data-star="${k}" aria-pressed="${w}" aria-label="${w ? '移出自选' : '加入自选'}" data-tip="${w ? '移出自选' : '加入自选'}">${I(w ? 'star' : 'starOff')}</button>${collapseBtn(isCollapsed('detail'))}</div>
    <div class="px"><span class="big num price-live ${st.stale || s.closed ? '' : cls(s.pct)}${s.closed ? ' closed' : ''}" data-f="big">${priceText(s)}</span><span class="chg num ${cls(s.pct)}" data-f="chg">${chgText(s)}</span></div>
    ${s.hi && s.lo ? `<div class="range"><span class="num" data-f="lo">${fmt(s.lo, s.dec)}</span><div class="bar"><i data-f="pos" style="left:${clamp01(((s.price ?? s.lo) - s.lo) / (s.hi - s.lo || 1)) * 100}%"></i></div><span class="num" data-f="hi">${fmt(s.hi, s.dec)}</span></div>` : ''}
    ${s.macro ? `<div class="stats inline">
      ${cell('开盘', s.open ? fmt(s.open, s.dec) : '—')}
      ${cell('最高', s.hi ? fmt(s.hi, s.dec) : '—')}
      ${cell('最低', s.lo ? fmt(s.lo, s.dec) : '—')}
      ${cell('状态', s.closed ? '休市' : '交易中', '', 'mstate')}
    </div>` : `<div class="stats inline">
      ${cell(term('持仓量'), d.oiValue ? fmtCompact(d.oiValue) : '—')}
      ${cell('持仓 24h', d.oiChg == null ? '—' : pctText(d.oiChg), cls(d.oiChg))}
      ${cell('成交额', s.vol ? fmtCompact(s.vol) : '—', '', 'vol')}
      ${cell(term('资金费率', '费率'), frText(s), cls(s.fr), 'fr')}
      ${cell(term('下次结算'), s.nextFunding ? countdown(s.nextFunding - Date.now()) : '—', '', 'cd')}
      ${cell('笔数', s.count ? fmtCompact(s.count) : '—', '', 'count')}
      ${cell(term('多空人数比'), ratioText(d.ls), ratioCls(d.ls))}
      ${cell(term('大户持仓比'), ratioText(d.top), ratioCls(d.top))}
      ${cell(term('主动买卖比'), ratioText(d.taker), ratioCls(d.taker))}
      ${cell(term('标记价'), s.mark ? fmt(s.mark, s.dec) : '—', '', 'mark')}
      ${cell(term('指数价'), s.index ? fmt(s.index, s.dec) : '—', '', 'index')}
      ${cell(term('基差'), pctText(basis), cls(basis), 'basis')}
    </div>`}`
}
const chgText = (s: Sym): string => s.price == null ? '—' : `${s.chg >= 0 ? '+' : ''}${fmt(s.chg, s.dec)}  ${pctText(s.pct)}`
const frText = (s: Sym): string => s.fr == null ? '—' : (s.fr * 100).toFixed(4) + '%'

/** 推送来的数只改那几格的字，不重画整块 */
function patchDetail(): void {
  const el = $('#detail'); if (!el) return
  const s = sym(cfg(active()).symbol); if (!s) return
  const set = (f: string, text: string, c?: string) => { const e = $(`[data-f="${f}"]`, el); if (!e) return; e.textContent = text; if (c != null) e.className = c }
  set('big', priceText(s), `big num price-live ${st.stale || s.closed ? '' : cls(s.pct)}${s.closed ? ' closed' : ''}`)
  set('mstate', s.closed ? '休市' : '交易中')
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
  cells.forEach(c => { c.chart.setAlerts(priceAlerts(cfg(c).symbol)); c.chart.setAlertSignals(lineSignals(cfg(c).symbol)) })
  renderRail(); if (st.panel === 'alerts') renderPanel()
  refreshQuick()
  refreshStreams()
}

// ---- 主力订单流、成交（成交：手机拉来、服务端拼好的回合里摊出来，见 trades/panel.ts）
function panelFlow(el: HTMLElement): void { flowPanel(el) }
function panelTrades(el: HTMLElement): void { renderTradesPanel(el, cfg(active()).symbol) }

// ---- 笔记（记一笔：先落本机，再传服务端成为观点记录，见 notes/）
function panelNotes(el: HTMLElement): void {
  el.innerHTML = `<div class="sp-head"><h3>笔记</h3><button class="btn secondary sm" id="nNew">${I('plus', 'icon-16')}记一笔</button></div>
    <div class="scroll" style="flex:1;min-height:0">${st.notes.length ? st.notes.slice().reverse().map(n => {
      const s = sym(n.symbol), state = noteState(n), rule = noteRuleText(n)
      return `<div class="list-row" data-note="${n.id}" style="cursor:pointer;align-items:flex-start">${badge(s, 'lg')}<div class="main"><div class="t1">${esc(s?.code || n.symbol)}<span class="tag">${IV_LABEL[n.iv] || n.iv}</span>${state ? `<span class="note-state ${state.cls}" ${n.err ? `data-tip="${esc(n.err)}"` : ''}>${state.text}</span>` : ''}<span class="faint" style="font-size:12px;font-weight:400;margin-left:auto">${shTime(n.draft?.created ?? n.t)}</span></div>
        ${rule ? `<div class="note-rule num">${esc(rule)}</div>` : ''}
        ${n.text ? `<div class="t2" style="color:var(--text-1);font-size:13px;line-height:20px;white-space:pre-wrap">${esc(n.text)}</div>` : ''}</div>
        <button class="ibtn sm act" data-del-note="${n.id}" aria-label="从这台电脑删掉" data-tip="${n.sync === 'synced' ? '从这台电脑删掉（复盘里的记录还在）' : '删除'}">${I('trash')}</button></div>`
    }).join('') : `<div class="empty">${I('note', 'icon-24')}<div>还没有笔记</div><div class="faint" style="font-size:12px;margin-top:4px">在图上右键「在这根 K 线记一笔」</div></div>`}</div>`
}
function openNote(t?: number, p?: number): void {
  const cell = active(); if (!cell) return
  const c = cfg(cell), s = sym(c.symbol), b = cell.chart.lastBar()
  const { from, to } = cell.chart.visible()
  openNoteDialog({
    symbol: c.symbol, iv: c.iv, bars: cell.chart.bars, from, to, canvas: cell.chart.canvas,
    t: t ?? b?.t ?? Date.now(), p: p ?? b?.c ?? s?.price ?? 0,
    onSaved: () => { if (st.panel === 'notes') renderPanel() },
  })
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
    const qq = normalize(q)
    const pool = [...S.symbols.values()].filter(s => cat === 'all' || s.kind === cat)
    results = rankSearch(pool, q, isWatched)
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
/** 主图上用开关记的那几个（第二批主图叠加记在 st.ind.mains，其余是副图） */
type MainToggle = 'ma' | 'ema' | 'boll' | 'vol' | 'vwap' | 'st' | 'ichi' | 'vpvr' | 'keys'
const MAIN_TOGGLES: string[] = ['ma', 'ema', 'boll', 'vol', 'vwap', 'st', 'ichi', 'vpvr', 'keys']
const isMainToggle = (id: string): id is MainToggle => MAIN_TOGGLES.includes(id)
/** 主力订单流那一行（orderflow 模块出的 HTML）只取开关与齿轮，说明小字不要 */
const OF_NAME = '主力订单流'
function openIndicators(): void {
  let cat: 'all' | 'main' | 'sub' = 'all', q = ''
  const rows = indicatorRows()
  const count = (k: typeof cat) => (k === 'sub' ? 0 : 1) + rows.filter(r => k === 'all' || r.place === k).length
  const d = dialog(`${head('指标')}<div class="body"><div class="ind-side"><div class="ind-search">${I('search', 'icon-16')}<input id="indQ" type="search" placeholder="搜索" autocomplete="off" spellcheck="false" aria-label="搜索指标"></div><div class="ind-cats">${([['all', '全部'], ['main', '主图'], ['sub', '副图']] as ['all' | 'main' | 'sub', string][]).map(([k, l]) => `<button data-c="${k}" aria-pressed="${k === cat}">${l}<span class="faint">${count(k)}</span></button>`).join('')}</div></div><div class="scroll" id="indList"></div></div>`, 'ind-dlg', { label: '指标' })
  const inp = $<HTMLInputElement>('#indQ', d.dlg), list = $('#indList', d.dlg)
  const isOn = (id: IndicatorId) => isMainToggle(id) ? !!st.ind[id] : isMoreMain(id) ? !!st.ind.mains?.includes(id) : st.ind.subs.includes(id as SubId)
  const ofRow = () => indicatorRowHTML().replace(/<small>[\s\S]*?<\/small>/, '')
  const ofHit = () => { const k = q.toLowerCase().replace(/\s+/g, ''); return cat !== 'sub' && (!k || `${OF_NAME}|orderflow`.includes(k)) }
  function render(): void {
    const full = st.ind.subs.length >= MAX_SUBS
    const shown = rows.filter(r => (cat === 'all' || r.place === cat) && matchRow(r, q))
    const html = IND_GROUPS.map(g => {
      const rs = shown.filter(r => r.group === g)
      const of = g === '成交量类' && ofHit()
      if (!rs.length && !of) return ''
      // 订单流行排在成交量类主图那几行的末尾
      const mainEnd = rs.filter(r => r.place === 'main').length
      const items = rs.map(({ id, place }) => {
        const on_ = isOn(id), dis = place === 'sub' && !on_ && full
        return `<div class="ind-row ${dis ? 'disabled' : ''}" data-id="${id}" tabindex="0" role="checkbox" aria-checked="${on_}" aria-disabled="${dis}" ${dis ? `data-tip="副图已满 ${MAX_SUBS} 个"` : ''}>
        <span class="check-box ${on_ ? 'on' : ''}">${on_ ? I('check', 'icon-16') : ''}</span><span class="nm">${CATALOG[id].name}</span>
        <span class="tag">${place === 'main' ? '主图' : '副图'}</span>
        ${id !== 'vol' && Object.keys(CATALOG[id]?.params || {}).length ? `<button class="ibtn xs" data-set="${id}" aria-label="参数" data-tip="参数">${I('gear', 'icon-16')}</button>` : '<span style="width:24px"></span>'}</div>`
      })
      if (of) items.splice(mainEnd, 0, ofRow())
      return `<div class="ind-group" role="group" aria-label="${g}"><div class="ind-gh">${g}</div>${items.join('')}</div>`
    }).join('')
    list.innerHTML = html || '<div class="ind-empty faint">没有匹配的指标</div>'
  }
  function toggle(id: IndicatorId): void {
    if (isMainToggle(id)) st.ind[id] = !st.ind[id]
    else if (isMoreMain(id)) { const m = st.ind.mains ?? []; st.ind.mains = m.includes(id) ? m.filter(x => x !== id) : [...m, id] }
    else if (st.ind.subs.includes(id as SubId)) st.ind.subs = st.ind.subs.filter(x => x !== id)
    else if (st.ind.subs.length < MAX_SUBS) st.ind.subs = [...st.ind.subs, id as SubId]
    else return
    cells.forEach(c => c.chart.setIndicators(st.ind)); save(); render()
    $<HTMLElement>(`.ind-row[data-id="${id}"]`, list)?.focus()
  }
  inp.addEventListener('input', () => { q = inp.value; render(); list.scrollTop = 0 })
  d.dlg.addEventListener('click', e => {
    const t = tgt(e)
    const c = t.closest<HTMLElement>('[data-c]'); if (c) { cat = c.dataset.c as typeof cat; $$('[data-c]', d.dlg).forEach(b => b.setAttribute('aria-pressed', String(b.dataset.c === cat))); render(); return }
    if (indicatorRowClick(t)) { render(); return }
    const s = t.closest<HTMLElement>('[data-set]'); if (s) { e.stopPropagation(); openParams(s.dataset.set as IndicatorId); return }
    const r = t.closest<HTMLElement>('.ind-row'); if (r && r.getAttribute('aria-disabled') !== 'true') toggle(r.dataset.id as IndicatorId)
  })
  d.dlg.addEventListener('keydown', e => {
    const t = tgt(e)
    // 焦点在列表上直接打字 = 搜索（进来不抢键盘，打字才落到搜索框）
    if (t !== inp && e.key.length === 1 && e.key !== ' ' && !e.metaKey && !e.ctrlKey && !e.altKey) { inp.focus(); return }
    const rowsEl = $$<HTMLElement>('.ind-row', list)
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      if (!rowsEl.length) return
      e.preventDefault()
      const i = rowsEl.indexOf(t), n = e.key === 'ArrowDown' ? (i < 0 ? 0 : Math.min(rowsEl.length - 1, i + 1)) : (i <= 0 ? (t === inp ? -1 : 0) : i - 1)
      if (n < 0) return
      if (e.key === 'ArrowUp' && i === 0) { inp.focus(); return }
      rowsEl[n].focus(); rowsEl[n].scrollIntoView({ block: 'nearest' }); return
    }
    if (t === inp && e.key === 'Enter') { e.preventDefault(); rowsEl[0]?.focus(); return }
    if ((e.key !== ' ' && e.key !== 'Enter') || !t.classList.contains('ind-row')) return
    e.preventDefault()
    if (t.hasAttribute('data-of-row')) { indicatorRowClick(t); render(); $<HTMLElement>('[data-of-row]', d.dlg)?.focus() } else if (t.getAttribute('aria-disabled') !== 'true') toggle(t.dataset.id as IndicatorId)
  })
  render(); $<HTMLElement>('.ind-row', list)?.focus()
}
const PARAM_NAME: Record<string, string> = { n: '周期', k: '倍数', fast: '快线', slow: '慢线', signal: '信号线', m1: '平滑 1', m2: '平滑 2', stoch: '取值窗口', tenkan: '转换线', kijun: '基准线', senkou: '先行带 B' }
function openParams(id: IndicatorId): void {
  const cell = active(); if (!cell) return
  const catg = CATALOG[id], p = cell.chart.params[id] || catg.params || {}
  type Field = [string, number, string]
  const fields: Field[] = p.periods ? p.periods.map((v, k): Field => [`周期 ${k + 1}`, v, 'periods']) : Object.entries(p).map(([k, v]): Field => [(MORE_PARAM_NAME as Record<string, Record<string, string> | undefined>)[id]?.[k] || PARAM_NAME[k] || k, v as number, k])
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
  ['品种与周期', [['直接打字母', '搜索品种'], ['⌘ K', '搜索品种'], ['1 – 9', '栏上钉的第几个周期'], [', 再打数字', '换任意周期（如 7、240、1D、5S）'], ['↑ ↓', '自选里上一只 / 下一只'], ['Home End', '自选列表里：第一只 / 最后一只'], ['空格 Delete', '自选列表里：收藏 / 移出（⌘ Z 撤销）'], ['⇧ ↵', '在搜索里加自选']]],
  ['图表', [['滚轮', '缩放（以光标为中心）'], ['拖动', '平移'], ['← →', '平移一根（⇧ 十根）'], ['拖价格轴', '缩放价格'], ['双击价格轴', '价格回到自动'], ['Alt R', '重置视图'], ['右键', '在这里建提醒、画线、记一笔'], ['/', '指标（对所有图格同时生效）'], ['⇧ T', '图表布局'], ['Alt ⇧ W', '开 / 关侧栏']]],
  ['画线工具', [['Alt T', '趋势线'], ['Alt J', '射线'], ['Alt H', '水平线'], ['Alt V', '垂直线'], ['Alt ⇧ R', '矩形'], ['Alt F', '斐波那契回撤'], ['双击工具', '连续画（右键或 Esc 退出）'], ['右键', '拿着工具时：放下工具'], ['⇧ 拖', '临时测量']]],
  ['编辑画线', [['⇧ 拖端点', '吸到 45° / 水平 / 竖直'], ['按住 ⌘', '临时反过来用磁吸'], ['⌘ 拖', '复制一条再拖走'], ['⌘ C / ⌘ V', '复制 / 粘贴画线（同一只品种）'], ['← → ↑ ↓', '微移选中的画线（⇧ 10 像素）'], ['Delete', '删除选中的画线'], ['Esc', '取消 / 回到光标'], ['⌘ Z', '撤销'], ['⌘ Y / ⌘ ⇧ Z', '重做'], ['⌘ ⌥ H / ⌃ ⌥ H', '隐藏 / 显示全部画线']]],
  ['其它', [['Alt A', '在现价（或十字线价位）建提醒'], ['Alt N', '记一笔'], ['⌥ S', '保存截图'], ['⇧ F', '全屏'], ['?', '这张表']]],
]
export function kbdHTML(s: string): string { return s.split(' ').map(k => /^[直拖滚双右按]/.test(k) ? `<span class="muted">${k}</span>` : k === '/' && /[⌘⌃]/.test(s) ? ' / ' : `<kbd>${k}</kbd>`).join(' ') }
/** 搜快捷键：按键与说明一起搜；Alt / Option / ⌥、Cmd / ⌘、Shift / ⇧、Ctrl / ⌃ 当成同一个 */
export function kbdNorm(s: string): string {
  return s.toLowerCase().replace(/\s+/g, '')
    .replace(/option|opt|alt|⌥/g, 'alt').replace(/command|cmd|⌘/g, 'cmd').replace(/shift|⇧/g, 'shift').replace(/control|ctrl|⌃/g, 'ctrl')
}
export function filterShortcuts(q: string): [string, [string, string][]][] {
  const k = kbdNorm(q)
  if (!k) return SHORTCUTS
  return SHORTCUTS.map(([h, rows]): [string, [string, string][]] => [h, kbdNorm(h).includes(k) ? rows : rows.filter(([a, b]) => kbdNorm(a).includes(k) || kbdNorm(b).includes(k))]).filter(([, rows]) => rows.length)
}
export function openShortcuts(): void {
  const d = dialog(`${head('快捷键', `<input class="input kbd-search" id="kbdQ" type="search" placeholder="搜按键或功能，如 射线、Alt J" aria-label="搜快捷键" autocomplete="off" spellcheck="false">`)}<div class="dialog-body"><div class="kbd-grid" id="kbdGrid"></div></div>`, 'kbd-dlg', { label: '快捷键' })
  d.dlg.style.width = '880px'
  const q = $<HTMLInputElement>('#kbdQ', d.dlg), grid = $('#kbdGrid', d.dlg)
  const render = (): void => {
    const groups = filterShortcuts(q.value)
    grid.innerHTML = groups.length
      ? groups.map(([h, rows]) => `<div><div class="group-title">${h}</div><table class="kbd-table">${rows.map(([k, v]) => `<tr><td>${kbdHTML(k)}</td><td class="muted">${v}</td></tr>`).join('')}</table></div>`).join('')
      : `<div class="empty kbd-none">${I('search', 'icon-24')}<div>没有「${esc(q.value.trim())}」相关的快捷键</div></div>`
  }
  q.addEventListener('input', render)
  render(); q.focus()
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
  if (st.page !== 'chart') { if (e.key === '?') { e.preventDefault(); openShortcuts() } return }
  const cell = active(); if (!cell) return
  if ((e.metaKey || e.ctrlKey) && !e.altKey && e.key.toLowerCase() === 'z') {
    e.preventDefault()
    const wu = e.shiftKey ? null : takeWatchUndo(); if (wu) { wu(); return }
    if (e.shiftKey) redo(); else undo()
    return
  }
  if (e.metaKey || e.ctrlKey) {
    if (e.code === 'KeyY' && !e.altKey) { e.preventDefault(); redo(); return }
    // ⌘⌥H：macOS 自己拿去「隐藏其它应用」时按 ⌃⌥H 也行
    if (e.code === 'KeyH' && e.altKey) { e.preventDefault(); toggleHideDrawings(); return }
    if (e.code === 'KeyC' && !e.altKey && !e.shiftKey) { if (!getSelection()?.toString() && copyDrawing(cell)) e.preventDefault(); return }
    if (e.code === 'KeyV' && !e.altKey && !e.shiftKey) { if (pasteDrawing(cell)) e.preventDefault(); return }
    return
  }
  if (e.altKey) {
    const map: Record<string, DrawingType> = { KeyT: 'trend', KeyJ: 'ray', KeyH: 'hline', KeyV: 'vline', KeyF: 'fib' }
    if (e.code === 'KeyR' && e.shiftKey) { e.preventDefault(); selectTool('rect'); return }
    if (e.code === 'KeyW' && e.shiftKey) { e.preventDefault(); togglePanel(); return }
    if (map[e.code]) { e.preventDefault(); selectTool(map[e.code]); return }
    if (e.code === 'KeyN') { e.preventDefault(); openNote(); return }
    if (e.code === 'KeyA') { e.preventDefault(); openAlert(); return }
    if (e.code === 'KeyR') { e.preventDefault(); cell.chart.resetView(); return }
    if (e.code === 'KeyS') { e.preventDefault(); screenshot(); return }
    return
  }
  if (e.key === 'Escape') { if (cell.chart.cancelDraft()) return; if (drawTool()) { selectTool(null); return } if (cell.chart.selected) { cell.chart.selected = null; cell.chart.dirty = true; hideQuick() } return }
  if (e.key === 'Delete' || e.key === 'Backspace') { if (cell.chart.deleteSelected()) e.preventDefault(); return }
  if (e.key === '?') { e.preventDefault(); openShortcuts(); return } // 焦点落在搜索框：吃掉这次按键，不然「?」会被打进去
  if (e.key === '/') { e.preventDefault(); openIndicators(); return }
  if (e.key === 'F' && e.shiftKey) { fullscreen(); return }
  if (e.key === 'T' && e.shiftKey) { e.preventDefault(); const b = $('#tbLayout'); if (b) layoutMenu(b); return }
  // 选中了画线：方向键只管微移它（1 px，⇧ 10 px；锁住的就不动），不再落到平移图 / 换品种上
  if (e.key.startsWith('Arrow') && cell.chart.selected) { e.preventDefault(); nudge(cell, e.key, e.shiftKey); return }
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
export function refreshStreams(early = false): void {
  const set = new Set<string>(), core = new Set<string>()
  // early：格子还没摆出来（品种表在路上），按存档里这套布局的格子先订
  const n = early ? LAYOUT_N[st.layout] || 1 : cells.length
  st.cells.slice(0, n).forEach((c, i) => {
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
  // 品种表没到时没法筛（冷启动先订的那次）；到了之后下一次对账会把表里没有的撤掉
  const known = (name: string) => !S.symbols.size || S.symbols.has(name.split('@')[0].toUpperCase())
  setStreams([...set].filter(known), [...core].filter(known), { now: early })
}

/**
 * 冷启动：行情推送、K 线和品种表三路并行。
 *   · 按存档里的格子立刻建 WS、订阅（不等品种表、不等 150 ms 合并窗口）
 *   · 每格的 K 线同时发出去，推送先攒进缓冲，第一次装格子时接过来
 * 以前是品种表到了（约 0.5 秒）才发 K 线、再过 150 ms 才建 WS，第一次跳价要等到 1.6–1.9 秒。
 */
function bootInParallel(): void {
  if (cells.length) return   // 品种表已经先回来（例如限流立刻失败），格子已按正常路径装好，不用再预取
  const n = LAYOUT_N[st.layout] || 1
  ensureCells(st, n)
  refreshStreams(true)
  for (const c of st.cells.slice(0, n)) {
    const k = `${c.symbol}|${c.iv}`, siv = streamIvOf(c.iv)
    if (early.has(k) || !siv || isSecondIv(c.iv) || isCustomIv(c.iv)) continue
    const hold = pushKey(c.symbol, siv)
    pushes.open(hold)
    early.set(k, { hold, res: klines(c.symbol, c.iv, undefined, 1500, false, false, undefined, 'low') })
  }
}
/** 品种表把存档里的品种换掉了：先发的那几次没人接，缓冲撒手 */
function dropEarly(): void {
  for (const e of early.values()) pushes.release(e.hold)
  early.clear()
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
    patchWatchRow(k, dir)
    if (k === cur && sym(k)) { patchDetail(); syncTitle() }
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
    // 表里没有的品种换成一只还没摆出来的常用品种（多图时不要一排全是 BTC）
    st.cells.forEach((c, i) => {
      if (S.symbols.has(c.symbol)) return
      const used = new Set(st.cells.map(x => x.symbol))
      c.symbol = i === 0 ? 'BTCUSDT' : FILL_SYMBOLS.find(k => !used.has(k) && S.symbols.has(k)) || 'BTCUSDT'
    })
    save()
  }
  if (!cells.length) buildCells(); else { cells.forEach(c => { void loadCell(c) }); refreshStreams() }
  renderToolbar(); renderPanel(); updateStale()
  hooks.booted.forEach(f => f())
}

// ------------------------------------------------------------ 启动
export async function initChart(): Promise<void> {
  installDrawing({
    cells: () => cells, active, symbolOf: c => cfg(cells.find(x => x.el === c.el)).symbol, drawings: drawingsFor,
    changed: c => { const x = cells.find(y => y.el === c.el); if (x) drawingsChanged(x) },
    clearMenu, toggleHide: toggleHideDrawings, lockAll: lockAllDrawings,
  })
  $('#drawbar').addEventListener('click', onDrawbarClick)
  $('#drawbar').addEventListener('contextmenu', onDrawbarContext)
  addEventListener('keyup', e => { if (e.key.startsWith('Arrow')) nudgeEnd() })
  $('#toolbar').addEventListener('click', onToolbarClick)
  $('#rail').addEventListener('click', onRailClick)
  $('#sidePanel').addEventListener('click', onPanelClick)
  installWatch({
    openSymbol: k => openSymbol(k), renderPanel, refreshStreams, openSearch: () => openSearch(),
    current: () => cfg(active()).symbol, activeIndex: () => st.active, cellCount: () => cells.length,
    collapsed: () => isCollapsed('watch'), collapseBtn,
  })
  addEventListener('keydown', onKey)
  hooks.onSearch = openSearch
  hooks.onTheme.push(() => cells.forEach(c => c.chart.readTheme()))
  hooks.pageShown.chart = () => layoutSlots()
  $('#hdrAlerts').onclick = () => { go('chart'); openPanel('alerts') }
  installAlerts({ openSymbol: k => { go('chart'); openSymbol(k) } })
  installNoteSync()
  onNotesSynced(() => { if (st.panel === 'notes') renderPanel() })
  installTradesPanel(() => { if (st.panel === 'trades') renderPanel() })
  st.customIvs.forEach(registerCustomIv); st.cells.forEach(c => registerCustomIv(c.iv))
  startSeconds()
  onSecondsTick(k => { pendingSec.add(k); if (!secRAF) secRAF = requestAnimationFrame(flushSeconds) })
  migrateDrawingFlags()
  onAlertsChange(refreshAlerts)
  installCompare({
    cells: () => cells.map(c => ({ idx: c.idx, chart: c.chart, symbol: cfg(c).symbol, iv: cfg(c).iv })),
    load: async (symbol, iv, endTime) => { const r = await barsFor(symbol, iv, endTime ?? undefined, undefined, false); return r.ok ? r.bars : null },
    refreshStreams, renderToolbar, activeSymbol: () => cfg(active()).symbol, isWatched,
  })

  // 藏着时非当前格的 K 线推送是退订的（stream.ts 只留核心），藏久了回来各格都补一次尾巴
  document.addEventListener('visibilitychange', () => {
    if (tailGate.visibility(document.visibilityState === 'visible', Date.now())) cells.forEach(c => void resyncTail(c))
  })
  on(e => {
    if (e.type === 'kline') {
      // K 线在路上的格子：先攒着，到了再补（这时格子里还是上一只品种的线，不能往上并）
      pushes.offer(pushKey(e.symbol, e.iv), e.bar)
    }
    if (e.type === 'kline') cells.forEach(c => {
      if (c.hold) return
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
    else if (e.type === 'ws') {
      updateStale(); paintConn()
      if (tailGate.ws(S.wsState)) cells.forEach(c => void resyncTail(c))
      // 换了线路刚连上：品种表没拉到的先拉，空着报错的格子重取（直连在国内连不上币安，切到网关后不用再点「重试」）
      if (S.wsState === 'open') cells.filter(c => $('.cell-empty', c.el)?.hidden === false).forEach(c => void retryLoad(c))
    }
  })

  // 每秒：钟、资金费率结算倒计时（图上的收线倒计时 2026-10-03 起不画，不再每秒重画各图）；每分钟：详情里的慢数、持仓量提醒
  setInterval(() => {
    const d = sh(Date.now()), t = `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}:${pad(d.getUTCSeconds())} UTC+8`
    $$('.cell-foot .clock').forEach(e => { e.textContent = t })
    const s = sym(cfg(active())?.symbol || ''), cd = $('#detail [data-f="cd"]')
    if (cd && s?.nextFunding) cd.textContent = countdown(s.nextFunding - Date.now())
  }, 1000)
  setInterval(() => {
    if (document.visibilityState === 'hidden') return
    if (st.panel === 'watch') settle.whenSettled('detail', detailNow)
  }, 61e3)

  renderDrawbar(); renderRail(); renderSlots(); layoutSlots(); renderPanel()
  // 窗口变了：各区域按比例重新夹、分隔线重摆（一帧一次）
  let relayRAF = 0
  new ResizeObserver(() => { if (!relayRAF) relayRAF = requestAnimationFrame(() => { relayRAF = 0; layoutSlots() }) }).observe($('#page-chart'))
  installOrderFlow({
    activeChart: () => { const c = active(); return c ? { chart: c.chart, symbol: cfg(c).symbol, iv: cfg(c).iv, host: c.host } : null },
    charts: () => cells.map(c => ({ chart: c.chart, symbol: cfg(c).symbol, iv: cfg(c).iv })),
    openAlert,
    addHline: p => {
      const c = active(); if (c) addHlineAt(c, c.chart.lastBar()?.t ?? Date.now(), p)
    },
    alertsFor: s => activeAlerts(s), alertDesc, deleteAlert,
    renderPanel, layoutSlots, renderToolbar,
    dec: s => sym(s)?.dec ?? 2, crypto: s => (sym(s)?.kind ?? 'crypto') === 'crypto', turnover: s => sym(s)?.vol ?? null,
  })
  // 品种表先发（标题价、自选都等它），K 线与推送下一拍再并行起：建 WS、算订阅要同步占 5 ms 左右，
  // 放在同一拍里会把品种表的三个请求和 DOMContentLoaded 一起往后推；K 线用低优先级，不在同一条 HTTP/2 连接上抢品种表的带宽
  const universe = loadUniverse()
  setTimeout(bootInParallel, 0)
  await universe
  if (!S.live) toast(S.limited ? '币安限流了' : '连不上币安合约接口', S.error || '检查网络后点图上的「重试」', 'wifiOff', 8000)
  afterUniverse()
  dropEarly()
  retryUniverseAfterCooldown()
}

/** 品种表是被限流挡掉的：冷却一过自己再取一次，不要等用户点「重试」 */
function retryUniverseAfterCooldown(): void {
  if (S.live || !S.limited) return
  setTimeout(async () => {
    if (S.live) return
    await loadUniverse()
    if (S.live) { afterUniverse(); cells.forEach(c => void loadCell(c)) } else retryUniverseAfterCooldown()
  }, Math.max(coolingFor(REST), 5000) + 500)
}

export { cfg, buildCells }
