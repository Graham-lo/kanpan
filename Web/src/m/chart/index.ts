// 移植自 Kanpan/Kanpan/Main/ChartHost.swift（ViewIntent、ChartBox 的 applyPending / 副图拖高 / 长按换序、
// updateUIView 的新旧状态合并）与 Kanpan/Kanpan/Main/ChartSession.swift（compose、一秒心跳）。
// 取数那一半（首屏一页、向左翻页、推送接末根、断线补缺口、外部副图）照 MarketModel 的行为写，
// 数据源是 Web/src/market（K 线）与 ./external.source（持仓量 / 多空比 / 主动买卖比 / 基差）。
//
// 对外只有 createChart(host, opts) 一个入口，合同写在同目录 README.md。

import { j, on as onMarket, REST, S, streamName } from '../../market'
import type { Bar as MarketBar } from '../../chart/calc'
import type { IndicatorID } from '../indicator/ids'
import { alive, placement } from '../indicator/ids'
import type { ChartOptions, PriceMode, ViewWindow as VW } from './geometry'
import {
  AICoinBehavior, ChartContentLayout, ChartGestureRoute, SubPaneResize, ViewMath, ViewWindow,
  clampView, defaultChartOptions, priceTransform, reconcile, reconcileBeforeUpsert, SHANGHAI_OFFSET_MIN,
} from './geometry'
import type { Bar, Interval } from './series'
import { BarSeries, ExternalSeries, isIrregular } from './series'
import type { ChartState, Crosshair, OrderBook, SymbolInfo } from './state'
import { makeState, withInput, withOverlay, withViewport } from './state'
import type { ChartColors } from './paint'
import { readChartColors, skinKey } from './paint'
import type { Drawing } from './drawing'
import type { OrderFlowDisplay, OrderFlowSnapshot } from './orderflowGroup'
import { defaultOrderFlowDisplay } from './orderflowGroup'
import type { ChartOrderFlowFocus } from './view'
import { ChartView } from './view'
import type { ExternalID } from './external.source'
import { ExternalFeed, isExternalID } from './external.source'
import { createOrderFlowPort } from './orderflow.source'
import { CompareFeed, compareSymbolOf, compareTargets } from './compare.source'
import { DepthFeed } from './depth.source'
import { ChartBeat } from './beat'

// ================================================================ ViewIntent

/** 下一次量出图区宽度时，视野该怎么落（ChartHost.swift 的 ViewIntent）。 */
export type ViewIntent =
  | { kind: 'keep' }
  | { kind: 'reset' }
  | { kind: 'switchInterval'; spacing: number; anchorRight: number | null }
  | { kind: 'resize'; spacing: number }
  | { kind: 'adopt'; spacing: number }
  | { kind: 'window'; view: VW }

/** applyPending 的纯函数部分：按意图在给定图区宽度上算视野。 */
export function resolveIntent(intent: ViewIntent, s: ChartState, plotW: number, resetSpacing: number): VW | null {
  const series = s.input.series, anchor = s.input.options.anchor
  switch (intent.kind) {
    case 'keep': return null
    case 'reset': return ViewMath.reset(series, plotW, resetSpacing, anchor)
    case 'switchInterval': return ViewMath.switchInterval(series, plotW, intent.spacing, intent.anchorRight)
    case 'resize': case 'adopt': return ViewMath.resized(s.viewport.view, series, plotW, intent.spacing, anchor)
    case 'window': return clampView(intent.view, series, plotW, anchor)
  }
}

// ================================================================ 对外类型

export interface ChartLook {
  overlays: IndicatorID[]
  subs: IndicatorID[]
  params: Partial<Record<IndicatorID, number[]>>
  indicatorColors: Partial<Record<IndicatorID, Record<number, string>>>
  hiddenOutputs: Partial<Record<IndicatorID, number[]>>
  options: ChartOptions
  /** 价格轴：线性 / 对数 / 百分比（百分比以视野最左那根的收盘为 0%）。对比态时整张图换成对比的百分比轴。 */
  priceMode: PriceMode
  mainInverted: boolean
  subInverted: IndicatorID[]
  subScale: Partial<Record<IndicatorID, number>>
  rsiUpper: number
  rsiLower: number
}

export interface CreateChartOptions extends Partial<ChartLook> {
  symbol: string
  interval: Interval
  /** 用户上次捏到的根宽（Prefs.barSpacing）；没有就是出厂 4。 */
  barSpacing?: number
  orderFlow?: boolean
  orderFlowDisplay?: OrderFlowDisplay
  drawings?: Drawing[]
  landscape?: boolean
  /**
   * 图要订的推送流名（`market.streamName.kline`）。行情推送是全页共用的一条连接，
   * 由宿主页把各处要的流并起来再交给 `market.setStreams`；图自己不直接动连接。
   */
  streams?: (list: string[]) => void
  /** 品种信息；默认读 market.S.symbols。 */
  symbolInfo?: (symbol: string) => SymbolInfo | null
  /** 取一页 K 线（endTime 为 null 是最新一页）；默认走 market.klines。测试与复盘可换。 */
  loadBars?: (symbol: string, iv: Interval, endTime: number | null) => Promise<Bar[] | null>
  /** 关掉推送 / 心跳 / 外部副图（复盘、截图用静态图）。 */
  offline?: boolean
  /** 主力订单流的数据口：图把「要不要、哪只、哪个周期、看到哪段」告诉它，它把快照推回来。 */
  orderFlowSource?: ((push: (snap: OrderFlowSnapshot | null) => void) => OrderFlowPort) | null
  /**
   * 对比品种（Prefs.compareSymbols，键如 `binance/usd_m/ETHUSDT`，最多三只）。非空时主图换成百分比轴，
   * 叠上各只的涨跌幅线；横屏（画线台）暂退、集合不动。只认币安合约的键，别家的键不取不画。
   */
  compareSymbols?: string[]
  /** 盘口（Prefs.depth）：主图右缘的五档条。只在直连线路上有（和 iOS 一样，网关没有盘口）。 */
  depth?: boolean
  /** 盘口的数据口；默认 DepthFeed（币安 `@depth5@100ms`）。传 null 表示不要（测试、截图）。 */
  depthSource?: ((push: (book: OrderBook | null) => void) => DepthPort) | null
  /** 此刻是不是直连线路（盘口只在直连上有）；默认读 market.S.route。 */
  isDirectRoute?: () => boolean
}

export interface CrosshairEvent { crosshair: Crosshair | null; bar: Bar | null }
export interface VisibleRangeEvent { from: number; to: number; atLatest: boolean }
export interface ScaleEvent { barSpacing: number }
export type SelectEvent =
  | { kind: 'orderFlow'; focus: ChartOrderFlowFocus | null }
  | { kind: 'drawing'; id: string | null }
export interface StatusEvent { loading: boolean; error: string | null; bars: number }

export interface ChartEvents {
  crosshair: CrosshairEvent
  scale: ScaleEvent
  select: SelectEvent
  visibleRange: VisibleRangeEvent
  tap: void
  notice: string
  status: StatusEvent
  inversion: { main: boolean; subs: IndicatorID[] }
  subScale: { id: IndicatorID; scale: number }
  subOrder: IndicatorID[]
  interaction: 'began' | 'ended'
}

export interface ChartHandle {
  readonly el: HTMLElement
  readonly view: ChartView
  readonly symbol: string
  readonly interval: Interval
  readonly state: ChartState | null
  readonly isAtLatest: boolean
  setSymbol(symbol: string): void
  setInterval(iv: Interval): void
  setIndicators(main: IndicatorID[], subs: IndicatorID[], params?: Partial<Record<IndicatorID, number[]>>): void
  setCandleStyle(p: Partial<ChartOptions> & { priceMode?: PriceMode; mainInverted?: boolean }): void
  setLook(p: Partial<ChartLook>): void
  setOrderFlow(on: boolean, display?: OrderFlowDisplay): void
  /** 对比品种（整组替换；空数组 = 退出对比）。 */
  setCompare(keys: string[]): void
  /** 盘口五档开关。 */
  setDepth(on: boolean): void
  setDrawings(list: Drawing[]): void
  setLandscape(on: boolean): void
  /** 「铺到某段时间」（扫图、复盘跳转）：数据到了就按这段摆视野。 */
  showWindow(from: number, to: number): void
  scrollToLatest(animated?: boolean): void
  clearCrosshair(): void
  resetPriceScale(): void
  on<K extends keyof ChartEvents>(name: K, fn: (e: ChartEvents[K]) => void): () => void
  /** 立刻把脏层画完（验收截图用）。 */
  redrawNow(): void
  /**
   * 宿主把图收起来（行情页切到别的页）：停一秒心跳（倒计时、外部副图的到点刷新）。
   * 推送、盘口、订单流的起停归宿主（它们各有自己的口子），这里不动。
   */
  pause(): void
  /** 亮出来：立刻补一拍；收起超过 5 秒再补主图与对比的缺口（收着时 K 线推送是退订的）。 */
  resume(): void
  destroy(): void
}

/** 盘口数据口（DepthFeed 就是一个）。 */
export interface DepthPort {
  setWanted(on: boolean, symbol: string, direct: boolean): void
  setVisible(visible: boolean): void
  dispose(): void
}

/** 订单流、画线两块在各自模块里接进来，这里只要这几个口子。 */
export interface OrderFlowPort {
  setWanted(on: boolean, symbol: string, interval: Interval): void
  noteView(view: VW, series: BarSeries): void
  dispose(): void
}

// ================================================================ 小工具

/**
 * 新序列还空着时要不要留着上一张图（ChartHost 的 holdOnEmpty）：只有「还在取」的那一拍留，
 * 取完了（出错、或取到零根）就撤——否则新品种 / 新周期的名字底下一直画着上一只 / 上一档的 K 线。
 */
export function holdsPrevious(loading: boolean, shown: ChartState | null): boolean {
  return loading && !!shown && shown.input.series.count > 0
}

/**
 * 推送来的一根换成图表的根。手机端的量是「币」（takerBuyBaseVolume 同口径），共用行情层给的是成交额，
 * 币量在 bv；推送里没有主动买的币量，按这一根的成交均价从主动买成交额折回（收盘后下一次补缺口会拿到原值）。
 */
const toChartBar = (b: MarketBar): Bar => {
  const vol = b.bv ?? NaN
  const tb = b.tb != null && b.v > 0 && Number.isFinite(vol) ? b.tb * vol / b.v : NaN
  return { openTime: b.t, open: b.o, high: b.h, low: b.l, close: b.c, volume: Number.isFinite(vol) ? vol : b.v, takerBuy: tb }
}

type KlineRow = [number, string, string, string, string, string, number, string, number, string, string, ...unknown[]]

function defaultSymbolInfo(symbol: string): SymbolInfo | null {
  const s = S.symbols.get(symbol.toUpperCase())
  return s ? { symbol: s.symbol, base: s.base, priceDecimals: s.dec } : null
}

/** 表还没到时按价位猜小数位：保留约五位有效数字。 */
function guessDecimals(price: number): number {
  if (!(price > 0)) return 2
  return Math.max(1, Math.min(8, 4 - Math.floor(Math.log10(price))))
}

/** 一页 K 线（KanpanCore 的 Bar：量取 r[5] 币量、主动买取 r[9] takerBuyBaseVolume）。取不到回 null。 */
async function defaultLoad(symbol: string, iv: Interval, endTime: number | null): Promise<Bar[] | null> {
  try {
    const u = `${REST}/fapi/v1/klines?symbol=${symbol}&interval=${iv}&limit=${HISTORY_PAGE}${endTime ? `&endTime=${endTime - 1}` : ''}`
    const rows = await j<KlineRow[]>(u, 10000)
    return rows.map(r => ({ openTime: r[0], open: +r[1], high: +r[2], low: +r[3], close: +r[4], volume: +r[5], takerBuy: +r[9] }))
  } catch {
    return null
  }
}

/**
 * 手机端 `Prefs.chartOptions` 那一包（主界面只认这一句）：网格「经典」不画、青苔 / 陶土画淡网格，
 * 本根倒计时常开，十字线读数写在头部、顺带报到最新价的涨跌幅，主 / 副轴双击翻转，图例折行让位。
 * 网格跟皮肤走，所以这里不定 grid，由 compose 按当时的 data-skin 取。
 */
export const appChartOptions = (): ChartOptions => ({
  ...defaultChartOptions(),
  kind: 'candle', body: 'solid', lastLine: true, drawings: true, countdown: true, sinceChange: true,
  anchor: 'right', bias: 'center', dataDisplay: 'top', crossPrice: 'selected',
  allowMainInversion: true, allowSubInversion: true, adaptiveIndicators: true, portraitHeight: 0.5,
})

const skinGrid = (): ChartOptions['grid'] => (document.documentElement.dataset.skin === 'classic' ? 'off' : 'on')

const sameList = <T>(a: readonly T[], b: readonly T[]): boolean => a.length === b.length && a.every((x, i) => x === b[i])

const SNAPSHOT_LIMIT = 8
/** 对比行情揉进图的节流（CompareFeed 的 flush：100 ms） */
const COMPARE_FLUSH_MS = 100
const HISTORY_PAGE = 1500
const MAX_SUBS = 3

// ================================================================ createChart

export function createChart(host: HTMLElement, opts: CreateChartOptions): ChartHandle {
  // ---------------------------------------------------------------- DOM：滚动容器 → 内容 → 画布
  const scroller = document.createElement('div')
  scroller.className = 'm-chart-scroll'
  Object.assign(scroller.style, { position: 'relative', width: '100%', height: '100%', overflowX: 'hidden', overflowY: 'auto', overscrollBehavior: 'contain' })
  const content = document.createElement('div')
  Object.assign(content.style, { position: 'relative', width: '100%', height: '100%' })
  scroller.appendChild(content)
  host.appendChild(scroller)
  const view = new ChartView(content)

  // ---------------------------------------------------------------- 会话
  const listeners = new Map<keyof ChartEvents, Set<(e: unknown) => void>>()
  const emit = <K extends keyof ChartEvents>(name: K, e: ChartEvents[K]) => {
    listeners.get(name)?.forEach(fn => { try { fn(e) } catch (err) { console.error(err) } })
  }

  let symbol = opts.symbol.toUpperCase()
  let interval = opts.interval
  let series: BarSeries | null = null
  let generation = 0
  let loading = false
  let error: string | null = null
  let historyLoading = false
  let historyDone = false
  let colors: ChartColors = readChartColors()
  let colorKey = skinKey()
  let oi: ExternalSeries | null = null
  let external: Partial<Record<IndicatorID, ExternalSeries>> = {}
  let feed: ExternalFeed | null = null
  let nowMs: number | null = null
  let destroyed = false
  let landscape = !!opts.landscape
  let orderFlowOn = !!opts.orderFlow
  let orderFlowDisplay = opts.orderFlowDisplay ?? defaultOrderFlowDisplay()
  let orderFlowSnapshot: OrderFlowSnapshot | null = null
  let orderFlowPort = null as OrderFlowPort | null
  let drawings: Drawing[] = opts.drawings ?? []
  let compareKeys: string[] = [...(opts.compareSymbols ?? [])]
  let depthOn = !!opts.depth
  let depthBook: OrderBook | null = null
  let depthPort = null as DepthPort | null
  const isDirect = opts.isDirectRoute ?? (() => S.route !== 'gateway')
  let resetSpacing = opts.barSpacing && opts.barSpacing > 0 ? opts.barSpacing : AICoinBehavior.initialSpacing
  let pending: ViewIntent = { kind: 'reset' }
  let lastPlotW: number | null = null
  let lastInversion: string | null = null
  let lastLookInversion: string | null = null
  const snapshots = new Map<string, BarSeries>()
  const symbolInfo = opts.symbolInfo ?? defaultSymbolInfo
  const loadBars = opts.loadBars ?? defaultLoad

  const look: ChartLook = {
    overlays: [], subs: [], params: opts.params ?? {}, indicatorColors: opts.indicatorColors ?? {},
    hiddenOutputs: opts.hiddenOutputs ?? {}, options: { ...appChartOptions(), ...(opts.options ?? {}) },
    priceMode: opts.priceMode ?? 'log', mainInverted: !!opts.mainInverted, subInverted: opts.subInverted ?? [],
    subScale: opts.subScale ?? {}, rsiUpper: opts.rsiUpper ?? 70, rsiLower: opts.rsiLower ?? 30,
  }
  let gridAuto = opts.options?.grid === undefined
  const applyIndicators = (main: IndicatorID[], subs: IndicatorID[]) => {
    const m = alive(main).filter(id => placement(id) === 'main')
    if (m.includes('ORDERFLOW')) orderFlowOn = true
    look.overlays = m.filter(id => id !== 'ORDERFLOW')
    look.subs = alive(subs).filter(id => placement(id) === 'sub').filter((id, i, a) => a.indexOf(id) === i).slice(0, MAX_SUBS)
  }
  applyIndicators(opts.overlays ?? ['MA'], opts.subs ?? ['VOL', 'MACD'])

  const snapshotKey = (sym: string, iv: Interval) => `${sym}|${iv}`
  const remember = (s: BarSeries) => {
    if (s.isEmpty) return // 空序列不当快照：下回换回来别拿它开张
    const k = snapshotKey(s.symbol, s.interval)
    snapshots.delete(k)
    snapshots.set(k, s)
    while (snapshots.size > SNAPSHOT_LIMIT) snapshots.delete(snapshots.keys().next().value as string)
  }

  const status = () => emit('status', { loading, error, bars: series?.count ?? 0 })

  // ---------------------------------------------------------------- compose（ChartSession.compose）

  const info = (s: BarSeries): SymbolInfo => {
    const known = symbolInfo(s.symbol)
    if (known) return known
    const last = s.count ? s.close[s.count - 1] : NaN
    const base = s.symbol.replace(/USDT$|USDC$|USD$/, '') || s.symbol
    return { symbol: s.symbol, base, priceDecimals: guessDecimals(last) }
  }

  // ---------------------------------------------------------------- 对比（CompareModel）与盘口

  /** 此刻是不是对比态（MainScreen.comparing）：有认得出的对比品种、且不在横屏画线台。 */
  const comparingFor = (sym: string) => !landscape && compareTargets(compareKeys, sym).length > 0
  /** 盘口要不要连：开着、竖屏、不在对比态（对比态不画盘口，连着也白连）。 */
  const depthWanted = () => depthOn && !landscape && !comparingFor(symbol)
  const syncDepth = () => depthPort?.setWanted(depthWanted(), symbol, isDirect())

  /** 颜色按它在偏好里的位置取调色板（ChartSession.compose：palette[slot % count]）。 */
  const compareColor = (key: string) => {
    const pal = colors.palette, slot = Math.max(0, compareKeys.indexOf(key))
    return pal[slot % pal.length]
  }
  const compareName = (key: string) => {
    const sym = compareSymbolOf(key) ?? key
    return symbolInfo(sym)?.base ?? (sym.replace(/USDT$|USDC$|USD$/, '') || sym)
  }
  let compareStreamKey = ''
  let compareTimer: ReturnType<typeof setTimeout> | null = null
  const compareFeed = new CompareFeed(loadBars, () => scheduleCompare())
  /** 按当前键集合与主序列起停对比取数；在取的品种变了就重订推送。 */
  const syncCompare = (s: BarSeries | null) => {
    compareFeed.configure(comparingFor(symbol) ? compareKeys : [], s, symbol, interval)
    const key = compareFeed.symbols.join(',')
    if (key !== compareStreamKey) { compareStreamKey = key; subscribe() }
  }
  const compareSeries = (s: BarSeries) => {
    syncCompare(s)
    return compareFeed.series(s, compareColor, compareName)
  }
  const sameCompare = (a: ChartState['input']['compare'], b: ChartState['input']['compare']) =>
    a.length === b.length && a.every((x, i) => x.key === b[i].key && x.name === b[i].name && x.color === b[i].color && x.open === b[i].open && x.close === b[i].close)
  const scheduleCompare = () => {
    if (compareTimer || destroyed) return
    compareTimer = setTimeout(() => { compareTimer = null; publishCompare() }, COMPARE_FLUSH_MS)
  }
  /** 对比行情到了一截：只换 input.compare（对比态进出要重揉整份状态，走 update）。 */
  const publishCompare = () => {
    const st = view.state
    if (destroyed || !st || !series || st.input.series !== series) return
    const comparing = comparingFor(series.symbol)
    if (comparing !== st.input.percentAxis) { update(); return }
    if (!comparing) return
    const compare = compareSeries(series)
    if (!sameCompare(compare, st.input.compare)) view.state = withInput(st, { compare })
  }

  const compose = (s: BarSeries): ChartState => {
    const si = info(s)
    const price = { ...priceTransform(look.priceMode), inverted: look.mainInverted }
    const overlays = landscape ? [] : look.overlays
    const subs = landscape ? [] : look.subs
    const options: ChartOptions = { ...look.options, grid: gridAuto ? skinGrid() : look.options.grid }
    if (landscape) options.drawings = true
    const comparing = comparingFor(s.symbol)
    // 对比态：百分比轴、不画线（ChartSession.compose）；集合本身不动，退出对比就回来。
    if (comparing) options.drawings = false
    let st = makeState({
      series: s, symbol: si, view: new ViewWindow(s.lastTime, s.step * 80), colors, price,
      overlays, subs, params: look.params, tzOffset: SHANGHAI_OFFSET_MIN, oi, magnet: true,
      decimals: si.priceDecimals, options,
      nowMs, subScale: look.subScale, drawings,
    })
    st = withInput(st, {
      external, subInverted: look.subInverted, indicatorColors: look.indicatorColors, hiddenOutputs: look.hiddenOutputs,
      rsiUpper: look.rsiUpper, rsiLower: look.rsiLower, oiSupported: true, externalSupported: true,
      percentAxis: comparing, compare: comparing ? compareSeries(s) : (syncCompare(s), []),
    })
    st = withOverlay(st, {
      orderFlow: landscape || !orderFlowOn ? null : orderFlowSnapshot,
      orderFlowDisplay,
      depth: depthWanted() ? depthBook : null,
    })
    return st
  }

  // ---------------------------------------------------------------- 灌状态（ChartHost.updateUIView）

  const inversionKey = (main: boolean, subs: readonly IndicatorID[]) => `${main ? 1 : 0}|${[...subs].sort().join(',')}`

  let resizing: { id: IndicatorID; height: number; scale: number; content: number; other: number; originY: number; pointer: number } | null = null
  let reordering: { id: IndicatorID; start: IndicatorID[]; frames: { y: number; h: number }[]; pointer: number } | null = null

  /** 把会话与样式揉成一份新状态交给图。视野、十字线、倍率这些图上的交互态按 Swift 的规矩从旧图接过来。 */
  const update = () => {
    if (destroyed) return
    if (!series || series.isEmpty) {
      // 换周期 / 换品种时新序列要一个往返：这一拍留着上一张图，不闪空图（holdOnEmpty）。
      // 只留到这次取数有结果为止——出错、或者这只根本没有 K 线，就撤掉，不然新品种名底下一直画着上一只
      if (holdsPrevious(loading, view.state)) return
      view.state = null
      pending = { kind: 'reset' }
      return
    }
    let s = compose(series)
    const wanted = inversionKey(look.mainInverted, look.subInverted)
    const adoptInversion = lastLookInversion !== null && lastLookInversion !== wanted
    lastLookInversion = wanted
    const old = view.state
    if (old && old.input.series.count > 0) {
      const oi0 = old.input, ov = old.overlay
      let cross = ov.crosshair
      let vp = { ...s.viewport, view: old.viewport.view }
      let input = { ...s.input }
      let overlay = { ...s.overlay, crosshair: cross, orderFlowSelected: s.overlay.orderFlow == null ? null : ov.orderFlowSelected }
      input.subInverted = adoptInversion ? look.subInverted : oi0.subInverted
      if (resizing) vp.subScale = old.viewport.subScale
      if (reordering) input.subs = oi0.subs
      if (oi0.options.dataDisplay !== input.options.dataDisplay || oi0.options.crossPrice !== input.options.crossPrice) cross = null
      if (cross?.pane != null && !input.subs.includes(cross.pane)) cross = null
      const oldSeries = oi0.series
      if (cross && cross.index >= 0 && cross.index < oldSeries.count) {
        cross = { ...cross, index: input.series.index(oldSeries.time(cross.index)) }
      }
      if (oldSeries.symbol === input.series.symbol) overlay.drawingPreviewID = ov.drawingPreviewID
      if (oldSeries.symbol !== input.series.symbol) {
        cross = null
        overlay.orderFlowSelected = null
        pending = { kind: 'reset' }
      } else if (oldSeries.interval !== input.series.interval) {
        cross = null
        overlay.orderFlowSelected = null
        const plotW = view.chartLayout?.plotW ?? lastPlotW ?? view.width
        // 「跟着最新」与「在看历史」换周期时右缘落在两个地方（A-05）
        const followingLatest = oldSeries.count > 0 && old.viewport.view.to >= oldSeries.lastTime
        pending = {
          kind: 'switchInterval',
          spacing: old.viewport.view.barSpacing(oldSeries.step, plotW),
          anchorRight: followingLatest ? null : old.viewport.view.to,
        }
        vp.price = old.viewport.price.mode === vp.price.mode ? old.viewport.price : { ...vp.price, inverted: old.viewport.price.inverted }
        if (adoptInversion) vp.price = { ...vp.price, inverted: look.mainInverted }
      } else {
        // 同一张图：序列在推送路径里已经按 reconcileBeforeUpsert 推过视野；
        // 这里是整条换（补缺口、翻页）后的兜底，手指按着时不动（axesFrozen）
        const L = view.chartLayout
        if (!view.axesFrozen && L && oldSeries !== input.series) {
          vp.view = reconcile(old.viewport.view, oldSeries, input.series, L.plotW, input.options.anchor)
        }
        vp.price = old.viewport.price.mode === vp.price.mode ? old.viewport.price : { ...vp.price, inverted: old.viewport.price.inverted }
        if (adoptInversion) vp.price = { ...vp.price, inverted: look.mainInverted }
      }
      overlay.crosshair = cross
      s = { input, viewport: vp, overlay }
    } else {
      pending = { kind: 'reset' }
    }
    const prevW = view.chartLayout?.plotW ?? null
    const prevSpacing = view.state && prevW ? view.state.viewport.view.barSpacing(view.state.input.series.step, prevW) : null
    view.state = s
    const w = view.chartLayout?.plotW ?? null
    if (pending.kind === 'keep' && prevW != null && prevSpacing != null && w != null && w !== prevW) pending = { kind: 'resize', spacing: prevSpacing }
    layoutContent()
    applyPending()
  }

  /** ChartBox.applyPending：新视野会改变价格轴标签宽度，最多迭代四次把图区宽度追平。 */
  let wantWindow: VW | null = null
  const applyPending = () => {
    let s = view.state
    const L = view.chartLayout
    if (wantWindow && s && s.input.series.count > 0) { pending = { kind: 'window', view: wantWindow }; wantWindow = null }
    if (pending.kind === 'keep' || !s || s.input.series.count === 0 || !L) return
    const intent = pending
    pending = { kind: 'keep' }
    let plotW = L.plotW
    for (let k = 0; k < 4; k++) {
      const v = resolveIntent(intent, s, plotW, resetSpacing)
      if (!v) return
      s = withViewport(s, { view: v })
      view.state = s
      const resolved = view.chartLayout?.plotW ?? plotW
      if (Math.abs(resolved - plotW) < 0.001) break
      plotW = resolved
    }
    lastPlotW = view.chartLayout?.plotW ?? plotW
    view.onViewChanged?.(s.viewport.view)
  }

  // ---------------------------------------------------------------- 内容高度（ChartContentLayout）

  const layoutContent = () => {
    const vh = scroller.clientHeight
    if (!(vh > 0)) return
    const subs = view.state?.input.subs.length ?? 0
    const h = ChartContentLayout.height(vh, subs, !landscape)
    const px = `${h}px`
    if (content.style.height !== px) content.style.height = px
    const maxTop = Math.max(0, h - vh)
    if (scroller.scrollTop > maxTop) scroller.scrollTop = maxTop
  }
  const scrollerObserver = new ResizeObserver(() => layoutContent())
  scrollerObserver.observe(scroller)

  // ---------------------------------------------------------------- 图的回调（ChartHost.wire）

  view.onResize = () => {
    const L = view.chartLayout
    if (!L) return
    const s = view.state
    if (pending.kind === 'keep' && lastPlotW != null && s && L.plotW !== lastPlotW) {
      pending = { kind: 'resize', spacing: s.viewport.view.barSpacing(s.input.series.step, lastPlotW) }
    }
    applyPending()
    lastPlotW = view.chartLayout?.plotW ?? lastPlotW
  }
  view.onViewChanged = v => {
    const s = view.state
    if (s && series && orderFlowPort) orderFlowPort.noteView(v, series)
    emit('visibleRange', { from: v.from, to: v.to, atLatest: !!s && s.input.series.count > 0 && v.to >= s.input.series.lastTime })
  }
  view.onUserViewChanged = v => {
    const L = view.chartLayout, s = view.state
    if (!L || !s || s.input.series.count === 0) return
    const w = v.barSpacing(s.input.series.step, L.plotW)
    if (!(w > 0) || !Number.isFinite(w)) return
    resetSpacing = w
    emit('scale', { barSpacing: w })
  }
  view.onCrosshairChanged = c => {
    const s = view.state
    const bar = c && s && c.index >= 0 && c.index < s.input.series.count ? s.input.series.bar(c.index) : null
    emit('crosshair', { crosshair: c, bar })
  }
  view.onOrderFlowFocusChanged = f => emit('select', { kind: 'orderFlow', focus: f })
  view.onNeedsHistory = () => { void loadHistory() }
  view.onTapped = () => emit('tap', undefined)
  view.onNotice = t => emit('notice', t)
  view.onInteractionBegan = () => { wantWindow = null; emit('interaction', 'began') }
  view.onInteractionEnded = () => emit('interaction', 'ended')
  view.onParentScroll = dy => { scroller.scrollTop += dy }
  view.onStateChanged = (s, layers) => {
    if (!s || !(layers.input || layers.viewport)) return
    const key = inversionKey(s.viewport.price.inverted, s.input.subInverted)
    if (lastInversion === key) return
    const first = lastInversion === null
    lastInversion = key
    if (first) return
    look.mainInverted = s.viewport.price.inverted
    look.subInverted = [...s.input.subInverted]
    lastLookInversion = inversionKey(look.mainInverted, look.subInverted)
    emit('inversion', { main: look.mainInverted, subs: look.subInverted })
  }

  // ---------------------------------------------------------------- 取数

  const wantedExternal = (): ExternalID[] => (landscape ? [] : look.subs.filter(isExternalID))

  const resetFeed = () => {
    feed?.dispose()
    oi = null
    external = {}
    if (opts.offline) { feed = null; return }
    const sym = symbol, iv = interval
    feed = new ExternalFeed(sym, iv, (id, xs) => {
      if (destroyed || sym !== symbol || iv !== interval) return
      if (id === 'OI') oi = xs
      else external = { ...external, [id]: xs }
      const st = view.state
      if (st && st.input.series.symbol === sym && st.input.series.interval === iv) {
        view.state = withInput(st, id === 'OI' ? { oi } : { external })
      }
    })
  }

  const subscribe = () => {
    if (opts.offline) return
    const list = [streamName.kline(symbol, interval), ...compareFeed.symbols.map(sym => streamName.kline(sym, interval))]
    opts.streams?.(destroyed ? [] : list)
  }

  const takeSeries = (s: BarSeries) => {
    series = s
    remember(s)
    historyDone = false
    feed?.want(wantedExternal(), s)
    update()
    status()
  }

  /** 首屏：有快照先用快照开张（换回来的那只立刻有图），再拉最新一页接上。 */
  const load = async () => {
    const gen = ++generation
    const sym = symbol, iv = interval
    const cached = snapshots.get(snapshotKey(sym, iv))
    loading = true
    error = null
    series = cached ?? null
    if (cached) takeSeries(cached)
    else { update(); status() }
    const bars = await loadBars(sym, iv, null)
    if (destroyed || gen !== generation) return
    loading = false
    if (!bars) { error = '行情暂时取不到'; update(); status(); return }
    if (cached && cached.count > 0) {
      mergeLatest(cached, bars)
      status()
      return
    }
    // 一根都没有（下架、不认得的代号）：当出错报，宿主据此盖「取不到」
    if (!bars.length) error = '这只品种没有行情'
    takeSeries(BarSeries.fromBars(sym, iv, bars))
  }

  /** 最新一页并回已有序列：接得上就 replaceSuffix，接不上（离开太久）整条换。 */
  const mergeLatest = (s: BarSeries, bars: Bar[]) => {
    if (!bars.length) return
    const first = bars[0].openTime
    if (first > s.lastTime + (isIrregular(s.interval) ? 32 * 86_400_000 : s.step)) {
      const fresh = BarSeries.fromBars(s.symbol, s.interval, bars)
      series = fresh
      remember(fresh)
      historyDone = false
      update()
      return
    }
    const L = view.chartLayout
    const st = view.state
    const at = first <= s.firstTime ? 0 : s.firstIndexAtOrAfter(first)
    let v = st?.viewport.view ?? null
    if (st && L && !view.axesFrozen && st.input.series === s) {
      v = reconcileBeforeUpsert(st.viewport.view, s, bars[bars.length - 1].openTime, L.plotW, st.input.options.anchor)
    }
    if (at === 0 && first <= s.firstTime) {
      const keep = BarSeries.fromBars(s.symbol, s.interval, bars)
      series = keep
      remember(keep)
      update()
      return
    }
    s.replaceSuffix(at, bars)
    if (st && st.input.series === s && v) view.state = withViewport({ ...st }, { view: v })
    else update()
    scheduleCompare()
  }

  const resync = async () => {
    const s = series
    if (!s || opts.offline || loading) return
    const gen = generation
    const bars = await loadBars(s.symbol, s.interval, null)
    if (destroyed || gen !== generation || series !== s || !bars) return
    mergeLatest(s, bars)
  }

  /** 向左翻页（ChartView.onNeedsHistory）：一次 1500 根，到头就不再问。 */
  const loadHistory = async () => {
    const s = series
    if (!s || s.isEmpty || historyLoading || historyDone || opts.offline && !opts.loadBars) return
    historyLoading = true
    const gen = generation
    try {
      const bars = await loadBars(s.symbol, s.interval, s.firstTime)
      if (destroyed || gen !== generation || series !== s) return
      if (!bars || !bars.length) { if (bars) historyDone = true; return }
      const before = s.count
      s.prepend(bars)
      if (s.count === before) { historyDone = true; return }
      if (bars.length < HISTORY_PAGE) historyDone = true
      const st = view.state
      if (st && st.input.series === s) view.state = { ...st }
      feed?.want(wantedExternal(), s)
      // 主图往左翻了：对比跟着往左补，并按新长度重新对齐
      syncCompare(s)
      scheduleCompare()
    } finally {
      historyLoading = false
      // 翻完一页若仍贴着左缘，让下一次视野变化再问一页
      view.gesture.askedHistory = false
    }
  }

  /** 推送来一根：先按旧序列推视野（reconcileBeforeUpsert），再原地 upsert。 */
  const onKline = (b: MarketBar) => {
    const s = series
    if (!s || s.isEmpty || loading) return
    const bar = toChartBar(b)
    if (bar.openTime < s.lastTime) return
    if (!isIrregular(s.interval) && bar.openTime > s.lastTime + s.step) { void resync(); return }
    const st = view.state
    const L = view.chartLayout
    let v = st?.viewport.view ?? null
    if (st && L && v && !view.axesFrozen && st.input.series === s) {
      v = reconcileBeforeUpsert(v, s, bar.openTime, L.plotW, st.input.options.anchor)
    }
    const appended = bar.openTime > s.lastTime
    if (!s.upsert(bar)) return
    if (st && st.input.series === s) {
      view.state = v && !v.equals(st.viewport.view) ? withViewport(st, { view: v }) : { ...st }
    }
    if (appended) {
      feed?.refresh(wantedExternal(), s, Date.now() + 60_000)
      if (st?.input.percentAxis) scheduleCompare()
    }
  }

  const offMarket = opts.offline ? () => {} : onMarket(e => {
    if (destroyed) return
    if (e.type === 'kline' && e.symbol === symbol && e.iv === interval) onKline(e.bar)
    else if (e.type === 'kline' && e.iv === interval) compareFeed.upsert(e.symbol, interval, toChartBar(e.bar))
    else if (e.type === 'universe') {
      const st = view.state
      if (st) {
        const si = symbolInfo(st.input.symbol.symbol)
        if (si && (si.priceDecimals !== st.input.symbol.priceDecimals || si.base !== st.input.symbol.base)) update()
      }
    } else if (e.type === 'ws') {
      // 线路换了（直连 ↔ 网关）盘口跟着起停；重连上了补主图与对比的缺口
      syncDepth()
      if (S.wsState === 'open') { void resync(); compareFeed.resync() }
    }
  })

  // ---------------------------------------------------------------- 心跳（ChartSession.heartbeat）

  const tick = () => {
    const st = view.state
    const want = st && look.options.countdown && look.options.lastLine ? Date.now() : null
    if (want !== nowMs) {
      nowMs = want
      if (st) view.state = withOverlay(st, { nowMs })
    }
    if (series) feed?.refresh(wantedExternal(), series)
  }
  // 网页藏到后台、或宿主 pause（行情页切走）时停；回来立刻补一拍，离开超过 5 秒补主图与对比的缺口
  const beat = new ChartBeat({
    tick,
    stopped: () => { nowMs = null },
    onReturn: () => { void resync(); compareFeed.resync() },
  }, document.hidden, !opts.offline)
  const onVisibility = () => {
    depthPort?.setVisible(!document.hidden)
    beat.setHidden(document.hidden)
  }
  document.addEventListener('visibilitychange', onVisibility)

  // ---------------------------------------------------------------- 皮肤 / 深浅 / 涨跌色

  const refreshColors = () => {
    const key = skinKey()
    const next = readChartColors()
    if (key === colorKey && JSON.stringify(next) === JSON.stringify(colors)) return
    colorKey = key
    colors = next
    update()
  }
  const skinObserver = new MutationObserver(refreshColors)
  skinObserver.observe(document.documentElement, { attributes: true, attributeFilter: ['data-skin', 'data-theme', 'data-updown', 'class', 'style'] })
  const scheme = typeof matchMedia !== 'undefined' ? matchMedia('(prefers-color-scheme: dark)') : null
  scheme?.addEventListener('change', refreshColors)

  // ---------------------------------------------------------------- 副图：分隔线拖高、长按换序（ChartBox.resizePane / reorderPane）

  const GRIP = 8
  const REORDER_MS = 350
  const REORDER_SLOP = 10
  let candidate: { pointer: number; x: number; y: number; grip: IndicatorID | null; timer: ReturnType<typeof setTimeout> | null; reorder: IndicatorID | null } | null = null
  const local = (e: PointerEvent) => {
    const r = view.el.getBoundingClientRect()
    return { x: e.clientX - r.left, y: e.clientY - r.top }
  }
  const gripAt = (y: number): IndicatorID | null => {
    const L = view.chartLayout
    if (!L || landscape) return null
    for (const p of L.panes.slice(1)) {
      if (p.indicator == null) continue
      const top = Math.min(L.H - 2 * GRIP, p.y + p.h - GRIP)
      if (y >= top && y < top + 2 * GRIP) return p.indicator as IndicatorID
    }
    return null
  }
  const dropCandidate = () => {
    if (candidate?.timer) clearTimeout(candidate.timer)
    candidate = null
  }
  const beginResize = (id: IndicatorID, pointer: number, originY: number) => {
    const s = view.state, L = view.chartLayout
    const pane = L?.panes.find(p => p.indicator === id)
    if (!s || !L || !pane) return
    view.gestures.cancelPointer(pointer)
    view.clearCrosshair()
    const scale = s.viewport.subScale[id] ?? 1
    const c = L.H - AICoinBehavior.timeHeight
    resizing = { id, height: pane.h, scale, content: c, other: scale * (c - pane.h) / pane.h, originY, pointer }
  }
  const beginReorder = (id: IndicatorID, pointer: number) => {
    const s = view.state, L = view.chartLayout
    if (!s || !L) return
    view.gestures.cancelPointer(pointer)
    view.clearCrosshair()
    reordering = { id, start: [...s.input.subs], frames: L.panes.slice(1).map(p => ({ y: p.y, h: p.h })), pointer }
    try { navigator.vibrate?.(8) } catch { /* 不支持就算了 */ }
  }
  const onDownCapture = (e: PointerEvent) => {
    if (candidate || resizing || reordering) {
      // 第二根手指落下：长按换序不成立（UILongPress 只认一指）
      if (candidate && candidate.pointer !== e.pointerId) dropCandidate()
      return
    }
    if (view.drawingInput || (e.pointerType === 'mouse' && e.button !== 0)) return
    const L = view.chartLayout
    if (!L) return
    const p = local(e)
    const grip = gripAt(p.y)
    const reorder = landscape ? null : ChartGestureRoute.reorderPane(p.x, p.y, L.plotW, L.panes) as IndicatorID | null
    if (!grip && !reorder) return
    candidate = { pointer: e.pointerId, x: p.x, y: p.y, grip, reorder, timer: null }
    if (reorder) {
      const pointer = e.pointerId
      candidate.timer = setTimeout(() => {
        if (!candidate || candidate.pointer !== pointer || !candidate.reorder) return
        const id = candidate.reorder
        candidate.timer = null
        candidate = null
        beginReorder(id, pointer)
      }, REORDER_MS)
    }
  }
  const onMoveCapture = (e: PointerEvent) => {
    if (resizing && e.pointerId === resizing.pointer) {
      e.stopPropagation()
      e.preventDefault()
      const s = view.state
      if (!s) return
      const delta = local(e).y - resizing.originY
      const scale = SubPaneResize.scale(resizing.height, delta, resizing.content, resizing.other)
      view.state = withViewport(s, { subScale: { ...s.viewport.subScale, [resizing.id]: scale } })
      return
    }
    if (reordering && e.pointerId === reordering.pointer) {
      e.stopPropagation()
      e.preventDefault()
      const s = view.state
      if (!s) return
      const y = local(e).y
      const r = reordering
      let target = r.frames.findIndex(f => y < f.y + f.h)
      if (target < 0) target = Math.max(0, r.start.length - 1)
      const subs = [...s.input.subs]
      const from = subs.indexOf(r.id)
      if (from >= 0 && from !== target) {
        subs.splice(from, 1)
        subs.splice(target, 0, r.id)
        view.state = withInput(s, { subs })
        layoutContent()
      }
      return
    }
    if (!candidate || e.pointerId !== candidate.pointer) return
    const p = local(e)
    const dx = p.x - candidate.x, dy = p.y - candidate.y
    const moved = Math.hypot(dx, dy)
    if (candidate.grip && moved > 4) {
      const id = candidate.grip, y0 = candidate.y
      const vertical = Math.abs(dy) > Math.abs(dx)
      dropCandidate()
      if (vertical) {
        beginResize(id, e.pointerId, y0)
        e.stopPropagation()
      }
      return
    }
    if (moved > REORDER_SLOP) dropCandidate()
  }
  const onUpCapture = (e: PointerEvent, cancelled: boolean) => {
    if (candidate && e.pointerId === candidate.pointer) dropCandidate()
    if (resizing && e.pointerId === resizing.pointer) {
      e.stopPropagation()
      const r = resizing
      resizing = null
      const s = view.state
      if (!s) return
      const scale = cancelled ? r.scale : (s.viewport.subScale[r.id] ?? r.scale)
      view.state = withViewport(s, { subScale: { ...s.viewport.subScale, [r.id]: scale } })
      if (!cancelled) {
        look.subScale = { ...look.subScale, [r.id]: scale }
        emit('subScale', { id: r.id, scale })
      }
    }
    if (reordering && e.pointerId === reordering.pointer) {
      e.stopPropagation()
      const r = reordering
      reordering = null
      const s = view.state
      if (!s) return
      if (cancelled) { view.state = withInput(s, { subs: r.start }); layoutContent(); return }
      look.subs = [...s.input.subs]
      if (!sameList(look.subs, r.start)) emit('subOrder', look.subs)
    }
  }
  const upCapture = (e: PointerEvent) => onUpCapture(e, false)
  const cancelCapture = (e: PointerEvent) => onUpCapture(e, true)
  scroller.addEventListener('pointerdown', onDownCapture, true)
  scroller.addEventListener('pointermove', onMoveCapture, true)
  scroller.addEventListener('pointerup', upCapture, true)
  scroller.addEventListener('pointercancel', cancelCapture, true)

  // ---------------------------------------------------------------- 开张

  resetFeed()
  subscribe()
  // 没传就用默认的三家聚合源（orderflow.source.ts）；传 null 表示这张图不要订单流数据（测试、截图）。
  const orderFlowFactory = opts.orderFlowSource === undefined ? (opts.offline ? null : createOrderFlowPort) : opts.orderFlowSource
  if (orderFlowFactory) {
    orderFlowPort = orderFlowFactory(snap => {
      if (destroyed) return
      orderFlowSnapshot = snap
      const st = view.state
      if (st) view.state = withOverlay(st, { orderFlow: landscape || !orderFlowOn ? null : snap })
    })
    orderFlowPort.setWanted(orderFlowOn && !landscape, symbol, interval)
  }
  // 盘口：默认币安五档流（depth.source.ts）；传 null 表示不要。
  const depthFactory = opts.depthSource === undefined ? (opts.offline ? null : (push: (b: OrderBook | null) => void) => new DepthFeed(push)) : opts.depthSource
  if (depthFactory) {
    depthPort = depthFactory(b => {
      if (destroyed) return
      depthBook = b
      const st = view.state
      const shown = depthWanted() ? b : null
      if (st && st.overlay.depth !== shown) view.state = withOverlay(st, { depth: shown })
    })
    if (typeof document !== 'undefined' && document.hidden) depthPort.setVisible(false)
    syncDepth()
  }
  void load()

  const restyle = () => {
    update()
    if (series) feed?.want(wantedExternal(), series)
  }

  const handle: ChartHandle = {
    el: scroller,
    view,
    get symbol() { return symbol },
    get interval() { return interval },
    get state() { return view.state },
    get isAtLatest() { return view.isAtLatest },

    setSymbol(next: string) {
      const up = next.toUpperCase()
      if (up === symbol) return
      symbol = up
      wantWindow = null
      resetFeed()
      subscribe()
      orderFlowPort?.setWanted(orderFlowOn && !landscape, symbol, interval)
      syncDepth()
      void load()
    },

    setInterval(iv: Interval) {
      if (iv === interval) return
      interval = iv
      wantWindow = null
      resetFeed()
      subscribe()
      orderFlowPort?.setWanted(orderFlowOn && !landscape, symbol, interval)
      void load()
    },

    setIndicators(main, subs, params) {
      applyIndicators(main, subs)
      if (params) look.params = { ...look.params, ...params }
      orderFlowPort?.setWanted(orderFlowOn && !landscape, symbol, interval)
      restyle()
      layoutContent()
    },

    setCandleStyle(p) {
      const { priceMode, mainInverted, ...rest } = p
      if (rest.grid !== undefined) gridAuto = false
      look.options = { ...look.options, ...rest }
      if (priceMode) look.priceMode = priceMode
      if (mainInverted != null) look.mainInverted = mainInverted
      if (!look.options.countdown) nowMs = null
      restyle()
    },

    setLook(p) {
      Object.assign(look, p)
      if (p.overlays || p.subs) applyIndicators(p.overlays ?? look.overlays, p.subs ?? look.subs)
      restyle()
      layoutContent()
    },

    setOrderFlow(on, display) {
      orderFlowOn = on
      if (display) orderFlowDisplay = display
      if (!on) orderFlowSnapshot = null
      orderFlowPort?.setWanted(on && !landscape, symbol, interval)
      update()
    },

    setCompare(keys) {
      const next = [...keys]
      if (sameList(next, compareKeys)) return
      compareKeys = next
      syncDepth()
      update()
      if (!series || series.isEmpty) syncCompare(null)
    },

    pause() { beat.pause() },
    resume() { beat.resume() },
    setDepth(on) {
      if (on === depthOn) return
      depthOn = on
      syncDepth()
      update()
    },

    setDrawings(list) {
      drawings = list
      const st = view.state
      if (st) view.state = withOverlay(st, { drawings: list })
    },

    setLandscape(on) {
      if (on === landscape) return
      landscape = on
      orderFlowPort?.setWanted(orderFlowOn && !landscape, symbol, interval)
      syncDepth()
      view.clearCrosshair()
      update()
      layoutContent()
    },

    showWindow(from, to) {
      if (!(to > from)) return
      wantWindow = ViewWindow.fromTo(from, to)
      applyPending()
    },

    scrollToLatest(animated = true) { view.scrollToLatest(animated) },
    clearCrosshair() { view.clearCrosshair() },
    resetPriceScale() { view.resetPriceScale() },

    on(name, fn) {
      let set = listeners.get(name)
      if (!set) { set = new Set(); listeners.set(name, set) }
      set.add(fn as (e: unknown) => void)
      return () => { set!.delete(fn as (e: unknown) => void) }
    },

    redrawNow() { view.redrawNow() },

    destroy() {
      if (destroyed) return
      destroyed = true
      generation++
      offMarket()
      beat.dispose()
      dropCandidate()
      document.removeEventListener('visibilitychange', onVisibility)
      skinObserver.disconnect()
      scheme?.removeEventListener('change', refreshColors)
      scrollerObserver.disconnect()
      scroller.removeEventListener('pointerdown', onDownCapture, true)
      scroller.removeEventListener('pointermove', onMoveCapture, true)
      scroller.removeEventListener('pointerup', upCapture, true)
      scroller.removeEventListener('pointercancel', cancelCapture, true)
      feed?.dispose()
      orderFlowPort?.dispose()
      depthPort?.dispose()
      compareFeed.dispose()
      if (compareTimer) { clearTimeout(compareTimer); compareTimer = null }
      opts.streams?.([])
      view.destroy()
      scroller.remove()
      listeners.clear()
    },
  }
  return handle
}

export type { Interval } from './series'
export type { IndicatorID } from '../indicator/ids'
export type { ChartState, Crosshair } from './state'
export type { ChartOptions } from './geometry'
