/* 手机网页版 · 行情页（照 iOS Main/MainScreen.swift、ChartHost.swift、LandscapeChrome.swift）
 *
 * 竖屏：顶栏 · 头部（价格 + 六格）· 周期条 · 图（主图 + 副图，同一屏）；图下沿让出底栏。
 * 横屏（手机横过来，高 ≤ 500）：画线工作台——左周期栏 · 中间 [品种胶囊、选中栏、图、画线条] · 右「画线 / 竖屏」；
 *   底栏让位（#m-app.landscape-free），图只留原始 K 线。浏览器转不了屏：竖屏点「开始画线」出一层引导，
 *   手机一横过来就直接进画线；转回竖屏自动收工。
 *
 * 状态全在 st：改完 save()，这里订阅 store 把图对齐（syncChart）；图上的手势（捏合根宽、双击翻转、
 * 拖副图高度、长按换序）一松手就写回 st 并 save()。云端同步装进来的改动走同一条路。
 * 行情推送：图自己要的 K 线流 + 当前品种的 ticker / mark，经 _streams.wantStreams('chart') 与别的页合并。
 *
 * 个性化学习只读结论（照 iOS Habits.opening / effectivePriceMode）：换品种那一下用学到的周期、
 * 价格轴用这一类学到的那档（不写回 st）；记录习惯这一半手机网页版不做。
 */
import { st, save, subscribe, onLayoutFork } from '../app/store'
import { INTERVALS, type IntervalId, type IndicatorId, type PriceMode, type LayoutGroup } from '../app/prefs'
import { hooks, nav, go, type PageHandle, type SyncChange } from '../app/shell'
import { drawingBook } from '../app/drawings'
import { S, on as onMarket, streamName } from '../../market'
import { createChart, type ChartHandle } from '../chart'
import { attachDrawing, type DrawingController } from '../chart/view.drawing'
import { canonicalInstrument } from '../chart/draw/instrument'
import type { ChartOrderFlowFocus } from '../chart/renderer.orderflow'
import { baseOfSymbol } from '../../orderflow/settings'
import { toast } from '../ui/toast'
import { el } from '../ui/dom'
import { icon } from '../ui/icons'
import { closeAllSheets } from '../ui/sheet'
import { wantStreams, ensureUniverse, takeOpenParam } from './_streams'
import { openSearch } from './search'
import { openAlertForm } from './alertForm'
import { isStale, swipeTarget, toggleQuick, replaceQuick, crosshairOHLC, habitCategory } from './chart/logic'
export { habitCategory }
import { createTopBar, createHeader, splitPair } from './chart/header'
import { createIntervalBar } from './chart/intervalBar'
import { createOrderFlowCard } from './chart/orderFlowCard'
import { createPagePort, type PagePort } from './chart/data'
import { openAnalysis, openChartSettings, openOrderFlowEditor, type PanelContext } from './chart/panels'
import { createBench, reconcileLineAlerts, type Bench } from './chart/drawingBench'
import { openNote, flushNotes, wireNoteUploads } from './chart/note'
import { openShare } from './chart/share'
import '../styles/chart.css'

const LANDSCAPE = '(orientation: landscape) and (max-height: 500px)'
const FORK_TEXT: Record<LayoutGroup, string> = {
  minute: '分钟周期的指标现在单独记',
  hour: '小时周期的指标现在单独记',
  day: '日线及以上的指标现在单独记',
}
const DAY_UP: readonly IntervalId[] = ['1d', '1w', '1M', '1y']

// ───────────────────────────── 个性化学习（只读结论）

/** 换到这只品种该开的周期：学到了、开关开着、和现在的不一样才有 */
export function learnedInterval(sym: string, current: IntervalId): IntervalId | null {
  if (!st.habitLearning) return null
  const c = st.learnedDefaults.intervals[canonicalInstrument(sym)]
  const iv = c?.v as IntervalId | undefined
  return iv && (INTERVALS as readonly string[]).includes(iv) && iv !== current ? iv : null
}
/** 图上真正用的价格轴：设置是线性 / 对数时换成这一类学到的那档；百分比引擎画不了，按线性 */
export function effectivePriceMode(sym: string): Exclude<PriceMode, 'percent'> {
  const pref = st.priceMode
  if (pref === 'percent') return 'linear'
  if (!st.habitLearning) return pref
  const s = S.symbols.get(sym)
  const learned = st.learnedDefaults.priceAxis[habitCategory(s?.kind, splitPair(sym).base)]?.v
  return learned === 'log' || learned === 'linear' ? learned : pref
}

/** 十字线读数里的时刻（上海）：日线及以上只写日期 */
function crossTime(iv: IntervalId): (ms: number) => string {
  return ms => {
    const d = new Date(ms + 480 * 60_000)
    const p = (n: number) => (n < 10 ? '0' + n : String(n))
    const day = `${d.getUTCFullYear()}-${p(d.getUTCMonth() + 1)}-${p(d.getUTCDate())}`
    return DAY_UP.includes(iv) ? day : `${day} ${p(d.getUTCHours())}:${p(d.getUTCMinutes())}`
  }
}
const colorTable = (t: typeof st.indicatorColors): Partial<Record<IndicatorId, Record<number, string>>> => {
  const out: Partial<Record<IndicatorId, Record<number, string>>> = {}
  for (const [id, m] of Object.entries(t)) {
    if (!m) continue
    const row: Record<number, string> = {}
    for (const [k, v] of Object.entries(m)) if (/^\d+$/.test(k) && typeof v === 'string') row[+k] = v
    out[id as IndicatorId] = row
  }
  return out
}

export function initChart(root: HTMLElement): PageHandle {
  root.classList.add('page-fixed')
  const page = el('div', 'cp')
  root.append(page)
  wireNoteUploads()

  let shown = false
  let port: PagePort | null = null
  const sym = (): string => st.symbol
  const iv = (): IntervalId => st.interval

  // ---- 顶栏 / 头部 / 周期条
  const topBar = createTopBar(page, {
    onBack: () => { const o = nav.origin; nav.origin = null; if (o && o !== 'chart') go(o); else render() },
    onNote: () => { openNote({ chart, symbol: sym, interval: iv }) },
    onShare: () => { openShare({ chart, symbol: sym, interval: iv }) },
    onSearch: () => openSearch(),
  })
  const header = createHeader(page, { onSwipe: (dx, dy) => scan(dx, dy) })
  let crossPrice: number | null = null
  const ivBar = createIntervalBar(page, {
    onPick: next => { if (next !== st.interval) { st.interval = next; save() } },
    onPin: x => {
      const r = toggleQuick(st.quickIntervals, x, INTERVALS)
      if ('refused' in r) { toast(r.refused); return }
      st.quickIntervals = r.list; save()
    },
    onReplace: (old, add) => { st.quickIntervals = replaceQuick(st.quickIntervals, old, add, INTERVALS); save() },
    onLatest: () => chart.scrollToLatest(true),
    onAnalysis: () => { openAnalysis(panelCtx) },
    onSettings: () => { openChartSettings() },
    onAlert: () => { const p = crossPrice; chart.clearCrosshair(); openAlertForm(sym(), p) },
  })

  // ---- 图
  const box = el('div', 'cp-chart')
  page.append(box)
  let chartStreams: string[] = []
  const pushStreams = (): void => {
    if (!shown) { wantStreams('chart', []); return }
    wantStreams('chart', [...chartStreams, streamName.ticker(sym()), streamName.mark(sym())])
  }
  const chart: ChartHandle = createChart(box, {
    symbol: sym(), interval: iv(),
    overlays: st.overlays, subs: st.subs, params: st.params,
    indicatorColors: colorTable(st.indicatorColors),
    priceMode: effectivePriceMode(sym()), mainInverted: st.mainInverted, subInverted: st.subInverted,
    subScale: { ...st.subHeightOverrides },
    barSpacing: st.barSpacing, orderFlow: st.orderFlow,
    streams: list => { chartStreams = list; pushStreams() },
    // 页面藏着时订单流停订（几条簿 / 成交 WS 与 500ms 评估），show / hide 里 resume / suspend
    orderFlowSource: push => (port = createPagePort(push, s => st.orderFlowOverrides[baseOfSymbol(s).base] ?? null, !shown)),
  })
  chart.setCandleStyle({ kind: st.candleKind, portraitHeight: st.portraitHeight })
  const card = createOrderFlowCard((chart.el.firstElementChild as HTMLElement | null) ?? chart.el)

  // ---- 画线
  const c: DrawingController = attachDrawing(chart.view)
  c.bindDrawings(drawingBook)
  let benchRef: Bench | null = null // createBench 里就会回调 onState，那时 bench 还没赋上
  c.onChanged = items => { reconcileLineAlerts(sym(), items); benchRef?.render() }
  c.onState = () => benchRef?.render()
  c.onFull = () => toast('这只品种的画线满了（最多 50 条）')
  c.onFeedback = k => {
    if (k === 'locked') toast('已锁定')
    else if (k === 'unlocked') toast('已解锁')
    else if (k === 'removed') toast('已删除')
  }
  const bench: Bench = createBench({
    chart, c, symbol: sym, interval: iv,
    onPickInterval: x => { if (x !== st.interval) { st.interval = x; save() } },
    onPickSymbol: s => switchSymbol(s, false),
    onActive: () => { layout() },
  })
  benchRef = bench
  page.append(bench.rail, bench.line, bench.sel, bench.dock, bench.tools)

  // 竖屏点「开始画线」：引导转横屏
  const guide = el('div', 'cp-guide')
  guide.hidden = true
  guide.innerHTML = `<div class="cp-guide-card">${icon('landscape', 36)}<b>把手机横过来</b><span>横屏就是画线台，转过来直接开始画</span>
    <button type="button" class="cp-guide-x">取消</button></div>`
  guide.querySelector<HTMLButtonElement>('.cp-guide-x')!.onclick = () => { wantDraw = false; guide.hidden = true }
  page.append(guide)
  let wantDraw = false
  const mq = matchMedia(LANDSCAPE)
  const isLand = (): boolean => mq.matches
  function startDrawing(): void {
    closeAllSheets()
    if (isLand()) { bench.setActive(true); return }
    wantDraw = true
    guide.hidden = false
  }
  function layout(): void {
    const land = isLand()
    page.classList.toggle('land', land)
    page.classList.toggle('drawing', bench.active)
    document.getElementById('m-app')?.classList.toggle('landscape-free', land && shown)
    chart.setLandscape(land)
    if (!land && bench.active) bench.setActive(false)
    if (land && wantDraw) { wantDraw = false; guide.hidden = true; bench.setActive(true) }
    bench.render()
  }
  mq.addEventListener('change', () => { card.set(null, '', 2); layout() })

  const panelCtx: PanelContext = { symbol: sym, port: () => port, onDraw: startDrawing }

  // ---- 图上的事件 → st（手指一松就落盘）
  chart.on('scale', e => { if (Math.abs(st.barSpacing - e.barSpacing) > 1e-6) { st.barSpacing = e.barSpacing; save() } })
  chart.on('inversion', e => { st.mainInverted = e.main; st.subInverted = [...e.subs] as IndicatorId[]; save() })
  chart.on('subScale', e => { st.subHeightOverrides = { ...st.subHeightOverrides, [e.id]: e.scale }; save() })
  chart.on('subOrder', list => { st.subs = [...list] as IndicatorId[]; save() })
  chart.on('visibleRange', e => ivBar.render({ atLatest: e.atLatest }))
  chart.on('notice', t => toast(t))
  chart.on('crosshair', e => {
    const x = e.crosshair, b = e.bar
    const onMain = !!x && x.pane == null && !!b
    const s = S.symbols.get(sym())
    const text = onMain && b ? crosshairOHLC({ t: b.openTime, o: b.open, h: b.high, l: b.low, c: b.close, v: b.volume }, s?.dec ?? chart.state?.input.symbol.priceDecimals ?? 2, crossTime(iv())) : null
    crossPrice = onMain ? (x!.price ?? b!.close) : null
    header.setReadout(text)
    ivBar.render({ crosshairOnMain: onMain })
    bench.setReadout(text ? text.replace(/\n/g, '  ') : null)
  })
  chart.on('select', e => {
    if (e.kind === 'orderFlow') {
      const s = S.symbols.get(sym())
      card.set(e.focus as unknown as ChartOrderFlowFocus | null, splitPair(sym()).base, s?.dec ?? 2)
    } else bench.render()
  })

  // ---- st → 图
  let lookKey = '', indKey = ''
  function syncChart(): void {
    if (chart.symbol !== sym()) { card.set(null, '', 2); chart.setSymbol(sym()); pushStreams(); bench.refreshAlerts() }
    if (chart.interval !== iv()) chart.setInterval(iv())
    const ik = JSON.stringify([st.overlays, st.subs, st.params, st.orderFlow])
    if (ik !== indKey) {
      indKey = ik
      chart.setIndicators([...st.overlays] as IndicatorId[], [...st.subs] as IndicatorId[], st.params)
      chart.setOrderFlow(st.orderFlow)
      if (!st.orderFlow) card.set(null, '', 2)
    }
    const pm = effectivePriceMode(sym())
    const lk = JSON.stringify([st.indicatorColors, st.subInverted, st.subHeightOverrides, st.mainInverted, pm, st.candleKind, st.portraitHeight])
    if (lk !== lookKey) {
      lookKey = lk
      chart.setLook({ indicatorColors: colorTable(st.indicatorColors), subInverted: [...st.subInverted] as IndicatorId[], subScale: { ...st.subHeightOverrides } })
      chart.setCandleStyle({ kind: st.candleKind, portraitHeight: st.portraitHeight, priceMode: pm, mainInverted: st.mainInverted })
    }
    port?.setOverride(st.orderFlowOverrides[baseOfSymbol(sym()).base] ?? null)
    render()
  }
  indKey = JSON.stringify([st.overlays, st.subs, st.params, st.orderFlow])
  lookKey = JSON.stringify([st.indicatorColors, st.subInverted, st.subHeightOverrides, st.mainInverted, effectivePriceMode(sym()), st.candleKind, st.portraitHeight])

  // ---- 头部与各条的刷新（行情推送经 rAF 合并）
  let raf = 0
  function render(): void {
    if (raf) { cancelAnimationFrame(raf); raf = 0 }
    const now = Date.now()
    const s = S.symbols.get(sym())
    const stale = isStale({ flag: st.stale, live: S.live, lastTick: s?.lastTick ?? null, now })
    topBar.render(sym(), nav.origin != null && nav.origin !== 'chart')
    header.render(sym(), stale, now)
    ivBar.render({ quick: st.quickIntervals, current: iv(), atLatest: chart.isAtLatest })
    bench.renderQuote()
  }
  const schedule = (): void => { if (!raf && shown) raf = requestAnimationFrame(() => { raf = 0; render() }) }
  onMarket(e => {
    if (!shown) return
    if ((e.type === 'ticker' || e.type === 'mark' || e.type === 'detail') && e.symbol !== sym()) return
    if (e.type === 'kline' || e.type === 'oi') return
    schedule()
  })
  let tick = 0

  // ---- 换品种 / 扫图
  function switchSymbol(s: string, recordRecent: boolean): void {
    const next = s.toUpperCase()
    if (next === st.symbol) return
    st.symbol = next
    if (recordRecent) st.symbols.recents = [next, ...st.symbols.recents.filter(x => x !== next)].slice(0, 10)
    const learned = learnedInterval(next, st.interval)
    if (learned) st.interval = learned
    save()
  }
  function scan(dx: number, dy: number): void {
    const fav = st.symbols.favorites
    const list = fav.includes(sym()) ? fav : st.symbols.recents
    const next = swipeTarget(list, sym(), dx, dy)
    if (next) switchSymbol(next, false)
  }

  // ---- 订阅
  subscribe(() => syncChart())
  onLayoutFork(g => { if (shown) toast(FORK_TEXT[g]) })
  hooks.onSymbol.push(s => {
    const learned = learnedInterval(s, st.interval)
    if (learned) { st.interval = learned; save() }
    syncChart()
  })
  // 云端装进来的设置已经 save() 过（subscribe → syncChart 按键比对只换变了的那几样），这里不再清键整套重设；
  // 画线本由 bindDrawings 自己重读，这里只补工具偏好与画线上的铃
  hooks.onSync.push((ch: SyncChange) => {
    if (ch.drawingPreferences) bench.pullPreferences()
    if (ch.alerts) bench.refreshAlerts()
  })
  hooks.onTheme.push(() => { topBar.invalidate(); lookKey = ''; syncChart(); bench.render() })
  hooks.onForeground.push(() => { if (shown) { render(); void flushNotes() } })

  // ---- 深链（验收截图用）
  function deepLink(): void {
    const v = takeOpenParam(['more', 'analysis', 'settings', 'orderflow', 'land'])
    if (!v) return
    setTimeout(() => {
      if (v === 'more') ivBar.openGrid()
      else if (v === 'analysis') openAnalysis(panelCtx)
      else if (v === 'settings') openChartSettings()
      else if (v === 'orderflow') openOrderFlowEditor(panelCtx)
      else if (v === 'land') startDrawing()
    }, 600)
  }

  layout()
  syncChart()

  return {
    show(): void {
      shown = true
      void ensureUniverse().then(() => schedule())
      pushStreams()
      port?.resume()
      layout()
      syncChart()
      clearInterval(tick)
      tick = window.setInterval(render, 1000)
      void flushNotes()
      deepLink()
    },
    hide(): void {
      shown = false
      clearInterval(tick)
      if (bench.active) bench.setActive(false)
      bench.closeSheets()
      wantDraw = false; guide.hidden = true
      chart.clearCrosshair()
      pushStreams()
      port?.suspend()
      card.set(null, '', 2)
      document.getElementById('m-app')?.classList.remove('landscape-free')
    },
    reselect(): void {
      if (!chart.isAtLatest) chart.scrollToLatest(true)
    },
  }
}
