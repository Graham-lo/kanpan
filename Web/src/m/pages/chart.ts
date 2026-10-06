/* 手机网页版 · 行情页（照 iOS Main/MainScreen.swift、ChartHost.swift、LandscapeChrome.swift）
 *
 * 竖屏：顶栏 · 头部（价格 + 六格）· 周期条 · 图（主图 + 副图，同一屏）；图下沿让出底栏。
 * 横屏（手机横过来，高 ≤ 500）：画线工作台——左周期栏 · 中间 [品种胶囊、选中栏、图、画线条] · 右「画线 / 竖屏」；
 *   底栏让位（#m-app.landscape-free），图上不画副图与主力订单流；主图指标由品种胶囊行右端的眼睛管（drawingOverlaysShown），
 *   开着照画但价格轴只按 K 线定，「主图˅」就地换主图指标；横竖各记一份根宽（barSpacing / landscapeBarSpacing）。浏览器转不了屏：竖屏点「开始画线」出一层引导，
 *   手机一横过来就直接进画线；转回竖屏自动收工。
 *
 * 状态全在 st：改完 save()，这里订阅 store 把图对齐（syncChart）；图上的手势（捏合根宽、双击翻转、
 * 拖副图高度、长按换序）一松手就写回 st 并 save()。云端同步装进来的改动走同一条路。
 * 行情推送：图自己要的 K 线流 + 当前品种的 ticker / mark，经 _streams.wantStreams('chart') 与别的页合并。
 *
 * 复盘本的回放（在图上重温 / 交易回放 / 相似片段）：复盘本把计划写进 sessionStorage 再发事件、把页面切过来；
 * 这里认领（读后即删），在页面上盖一层回放（chart/replay.ts，一张自己的图，不碰实时图与偏好），
 * 盖着的时候实时图暂停、K 线流退订；退出就拆掉那层，回到「我的」原处（像 iOS 回放盖在复盘本上）。
 *
 * 个性化学习只读结论（照 iOS Habits.opening / effectivePriceMode）：换品种那一下用学到的周期、
 * 价格轴用这一类学到的那档（不写回 st）；记录停留这一半手机网页版不做，只照 notePriceAxisPicked
 * 把图表设置里亲手切的线性 / 对数记成这一类的结论（不然学到的那档会把亲手选的盖回去）。
 */
import { st, save, subscribe } from '../app/store'
import { INTERVALS, type IntervalId, type IndicatorId, type PriceMode } from '../app/prefs'
import { hooks, nav, go, openSymbol, type PageHandle, type SyncChange } from '../app/shell'
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
import { openAlertHub } from './alertHub'
import { onAlertsChange, pendingCount } from '../model/alerts'
import { chartIndicatorsFor, isStale, isLandscape, spacingFor, spacingWrite, priceModeFor, showsOtherChart, swipeTarget, toggleQuick, replaceQuick, crosshairOHLC, habitCategory } from './chart/logic'
export { habitCategory }
import { createTopBar, createHeader, splitPair } from './chart/header'
import { compareTargets } from '../chart/compare.source'
import { createIntervalBar } from './chart/intervalBar'
import { createOrderFlowCard } from './chart/orderFlowCard'
import { createPagePort, type PagePort } from './chart/data'
import { openAnalysis, openChartSettings, openOrderFlowEditor, type PanelContext, type AxisContext } from './chart/panels'
import { createBench, reconcileLineAlerts, type Bench } from './chart/drawingBench'
import { openNote, resumeNote, wireNoteRequests, flushNotes, wireNoteUploads } from './chart/note'
import { openShare } from './chart/share'
import { createSharePreview, wireSharePreview, type SharePreview } from './chart/sharePreview'
import { startReplay, type ReplaySession } from './chart/replay'
import { parseIntent } from '../model/replayLogic'
import { INTENT_KEY, INTENT_EVENT } from '../model/reviewBook'
import { onBack } from '../ui/backStack'
import '../styles/chart.css'

const LANDSCAPE = '(orientation: landscape) and (max-height: 500px)'
const DAY_UP: readonly IntervalId[] = ['1d', '1w', '1M', '1y']

// ───────────────────────────── 个性化学习（只读结论）

/** 换到这只品种该开的周期：学到了、开关开着、和现在的不一样才有 */
export function learnedInterval(sym: string, current: IntervalId): IntervalId | null {
  if (!st.habitLearning) return null
  const c = st.learnedDefaults.intervals[canonicalInstrument(sym)]
  const iv = c?.v as IntervalId | undefined
  return iv && (INTERVALS as readonly string[]).includes(iv) && iv !== current ? iv : null
}
/** 品种的习惯类别（价格轴按类别学） */
const axisCategory = (sym: string): string => habitCategory(S.symbols.get(sym)?.kind, splitPair(sym).base)
/** 图上真正用的价格轴：设置是线性 / 对数时换成这一类学到的那档；百分比照原样交给引擎 */
export function effectivePriceMode(sym: string): PriceMode {
  return priceModeFor(st.priceMode, st.habitLearning, st.learnedDefaults.priceAxis[axisCategory(sym)]?.v)
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
  let replay: ReplaySession | null = null
  let port: PagePort | null = null
  /** 看朋友的线（头部那一格、临时周期）；建在画线之后，前面的回调只读它 */
  let preview: SharePreview | null = null
  const sym = (): string => st.symbol
  /** 图上的周期：预览朋友的线时是信上的那个（临时的，不写偏好），否则是偏好里的 */
  const iv = (): IntervalId => preview?.interval() ?? st.interval
  /** 人自己挑的周期：预览的临时周期作废；和偏好里一样时 st 不变，要手动对一次图 */
  const pickInterval = (next: IntervalId): void => {
    preview?.userPickedInterval()
    if (next !== st.interval) { st.interval = next; save() } else syncChart()
  }

  // ---- 顶栏 / 头部 / 周期条
  /** 开任何面板（记一笔、分享、搜索、分析、图表设置、创建提醒）都先收「更多」网格：网格的遮罩只从周期条下沿起，
   *  顶栏还点得到，不收的话网格压在面板底下、面板一关又露出来（iOS A-3：收网格挪到 onPanel 一处） */
  const panel = (open: () => void) => (): void => { ivBar.closeGrid(); open() }
  const topBar = createTopBar(page, {
    onBack: () => { const o = nav.origin; nav.origin = null; if (o && o !== 'chart') go(o); else render() },
    // 顶栏 ＋：开对比模式的搜索页（照 iOS d26df149；10-06 起「分析」面板的「对比」一节也开这一页）
    onCompare: panel(() => openSearch({ compare: { current: sym() } })),
    // 铃铛：开「提醒」表（列表 | 日志，照 iOS 543a308d），创建页预填最新价
    onAlerts: panel(() => { openAlertHub(sym(), S.symbols.get(sym())?.price ?? null) }),
    onNote: panel(() => { openNote({ chart, symbol: sym, interval: iv }) }),
    onShare: panel(() => { openShare({ chart, symbol: sym, interval: iv, previewing: () => !!preview?.previewing() }) }),
    onSearch: panel(() => openSearch()),
  })
  const header = createHeader(page, { onSwipe: (dx, dy) => { if (!preview?.cardVisible()) scan(dx, dy) } })
  let crossPrice: number | null = null
  const ivBar = createIntervalBar(page, {
    onPick: next => pickInterval(next),
    onPin: x => {
      const r = toggleQuick(st.quickIntervals, x, INTERVALS)
      if ('refused' in r) { toast(r.refused); return }
      st.quickIntervals = r.list; save()
    },
    onReplace: (old, add) => { st.quickIntervals = replaceQuick(st.quickIntervals, old, add, INTERVALS); save() },
    onAnalysis: panel(() => { openAnalysis(panelCtx) }),
    onSettings: panel(() => { openChartSettings(axisCtx) }),
    onAlert: panel(() => { const p = crossPrice; chart.clearCrosshair(); openAlertForm(sym(), p) }),
  })

  // ---- 图
  const box = el('div', 'cp-chart')
  page.append(box)
  let chartStreams: string[] = []
  const pushStreams = (): void => {
    if (!shown || replay) { wantStreams('chart', []); return }
    wantStreams('chart', [...chartStreams, streamName.ticker(sym()), streamName.mark(sym())])
  }
  // 美元指数在图上收掉成交量类与合约衍生指标、不起订单流与盘口（偏好原样不动）
  const isMacroSym = (x: string): boolean => x === 'DXY' || S.symbols.get(x)?.macro === true
  const shownInd = () => chartIndicatorsFor(isMacroSym(sym()), st.overlays as IndicatorId[], st.subs as IndicatorId[])
  const chart: ChartHandle = createChart(box, {
    symbol: sym(), interval: iv(),
    overlays: shownInd().overlays, subs: shownInd().subs, params: st.params,
    indicatorColors: colorTable(st.indicatorColors),
    priceMode: effectivePriceMode(sym()), mainInverted: st.mainInverted, subInverted: st.subInverted,
    subScale: { ...st.subHeightOverrides },
    barSpacing: st.barSpacing, orderFlow: st.orderFlow && shownInd().orderFlow,
    landscapeOverlays: st.drawingOverlaysShown,
    // 对比整串交给引擎（它自己去掉主图那只、去重、最多三只）；盘口只在页面露着时开，见 syncChart 的 extraKey
    compareSymbols: [...st.compareSymbols], depth: false,
    streams: list => { chartStreams = list; pushStreams() },
    // 页面藏着时订单流停订（几条簿 / 成交 WS 与 500ms 评估），show / hide 里 resume / suspend
    orderFlowSource: push => (port = createPagePort(push, s => st.orderFlowOverrides[baseOfSymbol(s).base] ?? null, !shown)),
  })
  // 引擎心跳（每秒按视野补外部数据、覆盖层重算）只在页面露着时跑：壳是在后台把各页先建出来的，
  // 建的时候行情页多半没露着，先停；show / hide 里 resume / pause，跟订单流口一样
  if (!shown) chart.pause()
  chart.setCandleStyle({ kind: st.candleKind, portraitHeight: st.portraitHeight })
  // 取不到行情（下架 / 不认得的品种、断网时换品种或周期）：引擎换的时候只在取数那一拍留着上一张图（不闪空图），
  // 出错或取到零根就撤图；这层底色盖住空图区写一句取不到，取到了就撤掉（图上仍是别的品种 / 周期时也兜底盖住）
  const empty = el('div', 'cp-nodata')
  empty.hidden = true
  empty.textContent = '暂时取不到这只品种的行情'
  box.append(empty)
  chart.on('status', e => {
    const shown = chart.state?.input.series
    empty.hidden = !showsOtherChart(e, shown ? { symbol: shown.symbol, interval: shown.interval } : null, chart.symbol, chart.interval)
  })
  const card = createOrderFlowCard((chart.el.firstElementChild as HTMLElement | null) ?? chart.el)

  // ---- 画线
  const c: DrawingController = attachDrawing(chart.view)
  c.bindDrawings(drawingBook)
  let benchRef: Bench | null = null // createBench 里就会回调 onState，那时 bench 还没赋上
  // 对账用图上真画着的那只（换品种取数的那一拍图上还是上一只，线也是上一只的），不是页面状态里的新代号
  c.onChanged = items => { reconcileLineAlerts(chart.state?.input.series.symbol ?? sym(), items); benchRef?.render() }
  // 同步 / 别的标签页整批换进来的画线由壳层对账（m/app/lineAlerts.ts，启动时就记下基线，不等行情页挂上）
  c.onState = () => benchRef?.render()
  c.onFull = () => toast('这只品种的画线满了（最多 50 条）')
  // 点中提醒线（画线删了 / 藏了还在生效的提醒）：开「提醒」表，照 iOS onAlertSignalTap → openAlertHub
  c.onSignalTap = () => { chart.clearCrosshair(); openAlertHub(sym(), S.symbols.get(sym())?.price ?? null) }
  c.onFeedback = k => {
    if (k === 'locked') toast('已锁定')
    else if (k === 'unlocked') toast('已解锁')
    else if (k === 'removed') toast('已删除')
  }
  const bench: Bench = createBench({
    chart, c, symbol: sym, interval: iv,
    onPickInterval: x => pickInterval(x),
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
  let landShown: boolean | null = null
  const mq = matchMedia(LANDSCAPE)
  // 只看视口宽高比不够：安卓上竖着拿、弹出键盘（记一笔、参数输入框）视口会变成「宽 > 高」，媒体查询就误判成横屏，
  // 整页翻成画线台布局、指标全收。设备自己的朝向（screen.orientation）还是竖的就不算横屏
  const so: ScreenOrientation | undefined = typeof screen !== 'undefined' ? screen.orientation : undefined
  const isLand = (): boolean => isLandscape(mq.matches, so?.type)
  function startDrawing(): void {
    closeAllSheets()
    if (isLand()) { bench.setActive(true); return }
    wantDraw = true
    guide.hidden = false
  }
  function layout(): void {
    const land = isLand()
    landShown = land
    page.classList.toggle('land', land)
    page.classList.toggle('drawing', bench.active)
    document.getElementById('m-app')?.classList.toggle('landscape-free', land && shown)
    // 转过去那一边自己记着的根宽（第一次进横屏还没记过时，prefs 已经拿竖屏那份兜底）
    chart.setLandscape(land, spacingFor(land, st))
    if (!land && bench.active) bench.setActive(false)
    if (land && wantDraw) { wantDraw = false; guide.hidden = true; bench.setActive(true) }
    bench.render()
  }
  const onOrientation = (): void => {
    if (isLand() === landShown) return // 媒体查询与设备朝向各报一次，只按真正翻了的那一次重排
    card.set(null, '', 2)
    layout()
  }
  mq.addEventListener('change', onOrientation)
  so?.addEventListener('change', onOrientation)

  const panelCtx: PanelContext = {
    symbol: sym, port: () => port, onDraw: startDrawing,
    // 「分析」里的「对比」一节（10-06 与顶栏 ＋ 并存）：开的是同一张对比模式搜索页
    onAddCompare: () => openSearch({ compare: { current: sym() } }),
    // 照 iOS：复盘回放、横屏画线台、看朋友分享的线时不能对比，整节不排
    canCompare: () => !replay && !isLand() && !bench.active && !preview?.previewing(),
  }
  const axisCtx: AxisContext = { mode: () => effectivePriceMode(sym()), category: () => axisCategory(sym()) }

  // ---- 图上的事件 → st（手指一松就落盘）
  // 横竖各记一份：这一捏在哪一边的图上捏的，就写哪一格（iOS ChartViewport.userIsZooming(to:landscape:)）
  chart.on('scale', e => { const k = spacingWrite(e, st); if (k) { st[k] = e.barSpacing; save() } })
  chart.on('inversion', e => { st.mainInverted = e.main; st.subInverted = [...e.subs] as IndicatorId[]; save() })
  chart.on('subScale', e => { st.subHeightOverrides = { ...st.subHeightOverrides, [e.id]: e.scale }; save() })
  chart.on('subOrder', list => { st.subs = [...list] as IndicatorId[]; save() })
  chart.on('notice', t => toast(t))
  chart.on('crosshair', e => {
    const x = e.crosshair, b = e.bar
    // 照 iOS：十字线落在任何一格（主图或副图）上都出开高低收读数、周期条让位；「创建提醒」只在主图上出
    const alive = !!x && !!b
    const onMain = alive && x!.pane == null
    const s = S.symbols.get(sym())
    const text = alive ? crosshairOHLC({ t: b!.openTime, o: b!.open, h: b!.high, l: b!.low, c: b!.close, v: b!.volume }, s?.dec ?? chart.state?.input.symbol.priceDecimals ?? 2, crossTime(iv())) : null
    crossPrice = onMain ? (x!.price ?? b!.close) : null
    header.setReadout(text)
    ivBar.render({ crosshair: alive, crosshairOnMain: onMain })
    bench.setReadout(text ? text.replace(/\n/g, '  ') : null)
  })
  chart.on('select', e => {
    if (e.kind === 'orderFlow') {
      const s = S.symbols.get(sym())
      card.set(e.focus as unknown as ChartOrderFlowFocus | null, splitPair(sym()).base, s?.dec ?? 2)
    } else bench.render()
  })

  // ---- st → 图
  let lookKey = '', indKey = '', extraKey = JSON.stringify([st.compareSymbols, false])
  function syncChart(): void {
    preview?.symbolChanged()
    if (chart.symbol !== sym()) { card.set(null, '', 2); chart.setSymbol(sym()); pushStreams(); bench.refreshAlerts() }
    if (chart.interval !== iv()) chart.setInterval(iv())
    bench.renderRail()
    const ind = shownInd()
    const of = st.orderFlow && ind.orderFlow
    const ik = JSON.stringify([ind.overlays, ind.subs, st.params, of])
    if (ik !== indKey) {
      indKey = ik
      chart.setIndicators(ind.overlays, ind.subs, st.params)
      chart.setOrderFlow(of)
      if (!of) card.set(null, '', 2)
    }
    chart.setLandscapeOverlays(st.drawingOverlaysShown)
    const pm = effectivePriceMode(sym())
    const lk = JSON.stringify([st.indicatorColors, st.subInverted, st.subHeightOverrides, st.mainInverted, pm, st.candleKind, st.portraitHeight])
    if (lk !== lookKey) {
      lookKey = lk
      chart.setLook({ indicatorColors: colorTable(st.indicatorColors), subInverted: [...st.subInverted] as IndicatorId[], subScale: { ...st.subHeightOverrides } })
      chart.setCandleStyle({ kind: st.candleKind, portraitHeight: st.portraitHeight, priceMode: pm, mainInverted: st.mainInverted })
    }
    // 对比、盘口（图表设置里的开关）。盘口是一条单独的 depth5 小连接，页面藏着时关掉，回来再按偏好开
    const depthOn = st.depth && shown && !isMacroSym(sym())
    const xk = JSON.stringify([st.compareSymbols, depthOn])
    if (xk !== extraKey) {
      extraKey = xk
      chart.setCompare([...st.compareSymbols])
      chart.setDepth(depthOn)
    }
    port?.setOverride(st.orderFlowOverrides[baseOfSymbol(sym()).base] ?? null)
    render()
  }
  indKey = ((i) => JSON.stringify([i.overlays, i.subs, st.params, st.orderFlow && i.orderFlow]))(shownInd())
  lookKey = JSON.stringify([st.indicatorColors, st.subInverted, st.subHeightOverrides, st.mainInverted, effectivePriceMode(sym()), st.candleKind, st.portraitHeight])

  // ---- 头部与各条的刷新（行情推送经 rAF 合并）
  let raf = 0
  function render(): void {
    if (raf) { cancelAnimationFrame(raf); raf = 0 }
    const now = Date.now()
    const s = S.symbols.get(sym())
    const stale = isStale({ flag: st.stale, live: S.live, lastTick: s?.lastTick ?? null, now }) || s?.closed === true
    topBar.render(sym(), nav.origin != null && nav.origin !== 'chart', compareTargets(st.compareSymbols, sym()).length > 0, pendingCount(sym()))
    header.render(sym(), stale, now)
    ivBar.render({ quick: st.quickIntervals, current: iv() })
    bench.renderRail()
    bench.renderQuote()
  }
  const schedule = (): void => { if (!raf && shown) raf = requestAnimationFrame(() => { raf = 0; render() }) }
  // 提醒表变了（建、删、响、同步拉回）：铃铛角标跟着改
  onAlertsChange(schedule)
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
  /** 扫图按来源页冻结的名单走（iOS ScanList）；没有名单（搜索进来、底栏回来的）就什么都不做 */
  function scan(dx: number, dy: number): void {
    const list = nav.scan
    if (!list || list.length < 2) return
    const next = swipeTarget(list, sym(), dx, dy)
    if (next) switchSymbol(next, false)
  }

  // ---- 订阅
  subscribe(() => syncChart())
  hooks.onSymbol.push(s => {
    // 回放盖着时从提醒「查看」、通知、复盘本换到别的品种：回放那层还画着旧品种，退出又被送回「我的」——
    // 换品种就是人要看新那只，先收回放、留在行情页（iOS A-6：换品种两个入口都先 endReview）
    if (replay) endReplay()
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
      else if (v === 'settings') openChartSettings(axisCtx)
      else if (v === 'orderflow') openOrderFlowEditor(panelCtx)
      else if (v === 'land') startDrawing()
    }, 600)
  }

  // ---- 复盘本来的回放（replay 声明在前头：K 线流回调里要看它）
  let offReplayBack: (() => void) | null = null
  let lastIntentAt = 0
  const takeIntent = (detail?: unknown): void => {
    let raw: unknown = detail
    try {
      const v = sessionStorage.getItem(INTENT_KEY)
      if (v != null) { sessionStorage.removeItem(INTENT_KEY); raw = JSON.parse(v) }
    } catch { /* 读不到就只靠事件 */ }
    const intent = parseIntent(raw, Date.now())
    if (!intent || intent.at === lastIntentAt) return
    lastIntentAt = intent.at
    beginReplay(intent)
  }
  function endReplay(): void {
    if (!replay) return
    replay.destroy(); replay = null
    offReplayBack?.(); offReplayBack = null
    document.getElementById('m-app')?.classList.remove('replay-free')
    if (shown) { chart.resume(); port?.resume(); pushStreams(); render() }
  }
  function leaveReplay(): void { endReplay(); go('me') }
  function beginReplay(intent: NonNullable<ReturnType<typeof parseIntent>>): void {
    endReplay()
    closeAllSheets()
    if (bench.active) bench.setActive(false)
    wantDraw = false; guide.hidden = true
    chart.clearCrosshair()
    chart.pause(); port?.suspend(); wantStreams('chart', [])
    document.getElementById('m-app')?.classList.add('replay-free')
    replay = startReplay(intent, {
      page,
      priceMode: effectivePriceMode,
      indicatorColors: () => colorTable(st.indicatorColors),
      onExit: leaveReplay,
      onFail: msg => { toast(msg); leaveReplay() },
    })
    offReplayBack = onBack(() => { offReplayBack = null; leaveReplay() }, 'chart')
  }
  window.addEventListener(INTENT_EVENT, e => { if (shown) takeIntent((e as CustomEvent).detail) })
  hooks.onTheme.push(() => { (replay as (ReplaySession & { restyle?: () => void }) | null)?.restyle?.() })

  // 复盘本右上「+」/「继续未完成的记录」：有没记完的先切回它那只、那个周期，K 线到了再开卡
  wireNoteRequests(() => {
    if (replay) endReplay()
    bench.closeSheets()
    resumeNote({
      chart, symbol: sym, interval: iv,
      switchTo: (s, i) => {
        if (st.symbol !== s) openSymbol(s)
        if (st.interval !== i) { st.interval = i; save() }
        syncChart()
      },
    })
  })

  // 朋友发来的线：头部那一格（未读信 / 正在看 / 回给他 / 顺便建提醒），「我的 › 朋友」点信也走这里
  preview = createSharePreview({
    chart, head: header.el, symbol: sym, interval: iv,
    // 同一只只切到行情页（不再套学到的周期、不动偏好）；换品种走壳的 openSymbol（记最近、来路）
    openSymbol: s => (s === st.symbol ? go('chart') : openSymbol(s)),
    sync: syncChart,
    clearStage: () => {
      if (replay) endReplay()
      closeAllSheets()
      bench.closeSheets()
      if (bench.active) bench.setActive(false)
      wantDraw = false; guide.hidden = true
      chart.clearCrosshair()
    },
  })
  wireSharePreview(preview)

  layout()
  syncChart()

  return {
    show(): void {
      shown = true
      void ensureUniverse().then(() => schedule())
      pushStreams()
      // 藏着时 K 线流是退订的；自选 / 板块页还订着行情，连接一直开着、不会有「重连上了」那一下，
      // 所以缺口只能靠这里：收起超过 5 秒回来，引擎重拉末页补上（最后一根不再停在离开那一刻）
      chart.resume()
      port?.resume()
      layout()
      syncChart()
      clearInterval(tick)
      tick = window.setInterval(render, 1000)
      void flushNotes()
      deepLink()
      takeIntent()
    },
    hide(): void {
      shown = false
      endReplay()
      clearInterval(tick)
      if (bench.active) bench.setActive(false)
      bench.closeSheets()
      wantDraw = false; guide.hidden = true
      chart.clearCrosshair()
      pushStreams()
      chart.pause()
      port?.suspend()
      card.set(null, '', 2)
      chart.setDepth(false) // 盘口那条小连接跟着页面收掉；show 里 syncChart 按偏好再开
      extraKey = JSON.stringify([st.compareSymbols, false])
      document.getElementById('m-app')?.classList.remove('landscape-free')
    },
    reselect(): void {
      if (!chart.isAtLatest) chart.scrollToLatest(true)
    },
  }
}
