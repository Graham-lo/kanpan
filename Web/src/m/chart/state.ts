// 移植自 KanpanChart/Sources/KanpanChart/ChartState.swift（外加 CompareSeries.swift、
// KanpanCore/Model/MarketMicrostructure.swift 的 OrderBook）
//
// 三层：输入层（K 线、指标、参数、样式）、视野层（视窗、价格变换、副图比例）、叠加层（画线、
// 十字线、订单流、盘口、倒计时时刻）。Swift 是值类型、按 == 比；这里每一层是一个不可变对象，
// 改哪层就换哪层的引用（with* 助手），渲染器按引用判断哪一层失效。
// 唯一例外是 BarSeries：它原地改（tick 只动末根），另带 revision / prefixRevision 两个戳，
// 渲染器按戳判断「只是末根变了」「追加了一根」还是整条换了。

import type { IndicatorID } from '../indicator/ids'
import type { ExternalSeries, BarSeries } from './series'
import type { ChartOptions, PriceMode, PriceTransform, ViewWindow } from './geometry'
import { defaultChartOptions, priceTransform, SHANGHAI_OFFSET_MIN } from './geometry'
import { toFixed } from './format'
import type { ChartColors, Hex } from './paint'
import { FALLBACK_COLORS } from './paint'
import type { Drawing } from './drawing'
import type { OrderFlowSnapshot, OrderFlowDisplay, OrderFlowGroupKey } from '../../orderflow/group'
import { defaultOrderFlowDisplay } from '../../orderflow/group'

/** 图表要知道的品种信息（SymbolInfo 的子集）。 */
export interface SymbolInfo {
  /** 交易所代号，如 BTCUSDT */
  symbol: string
  /** 基础资产，如 BTC（对比图例用） */
  base: string
  /** 价格小数位 */
  priceDecimals: number
}

export interface Crosshair {
  index: number
  /** null = 主图；否则是那一格副图的指标 */
  pane: IndicatorID | null
  t: number | null
  price: number | null
}

/** OISeries 在网页里直接是一条对齐好的外部序列。 */
export type OISeries = ExternalSeries

export interface CompareSeries {
  key: string
  name: string
  color: Hex
  open: (number | null)[]
  close: (number | null)[]
}

export function comparePercentAt(s: CompareSeries, index: number, baseIndex: number): number | null {
  if (baseIndex < 0 || baseIndex >= s.open.length || index < 0 || index >= s.close.length) return null
  const base = s.open[baseIndex], price = s.close[index]
  if (base == null || !Number.isFinite(base) || base <= 0 || price == null || !Number.isFinite(price) || price <= 0) return null
  const v = (price / base - 1) * 100
  return Number.isFinite(v) ? v : null
}

/** 这条线自己的 0% 基准：从主品种的基准根 `start` 起往后（到 `end` 为止）第一根有开盘价的。
 *  从前每条线都死认主品种那一根：那一根上比价品种恰好缺根（还没上市、停牌、数据没到）时
 *  整条线一个点都画不出来（CompareSeries.swift baseIndex(from:through:)，审查 B·P1-2）。 */
export function compareBaseIndexFrom(s: CompareSeries, start: number, end: number): number | null {
  const last = Math.min(end, s.open.length - 1)
  for (let i = Math.max(0, start); i <= last; i++) {
    const v = s.open[i]
    if (v != null && Number.isFinite(v) && v > 0) return i
  }
  return null
}

export interface BookLevel { price: number; quantity: number }
export interface OrderBook { symbol: string; time: number; bids: BookLevel[]; asks: BookLevel[] }

/** OrderBook.init：滤掉非法档、买降序卖升序、各留五档。 */
export function makeOrderBook(symbol: string, time: number, bids: BookLevel[], asks: BookLevel[]): OrderBook {
  const ok = (l: BookLevel) => Number.isFinite(l.price) && l.price > 0 && Number.isFinite(l.quantity) && l.quantity > 0
  return {
    symbol: symbol.toUpperCase(), time,
    bids: bids.filter(ok).sort((a, b) => b.price - a.price).slice(0, 5),
    asks: asks.filter(ok).sort((a, b) => a.price - b.price).slice(0, 5),
  }
}

export interface ChartInput {
  series: BarSeries
  compare: CompareSeries[]
  percentAxis: boolean
  oi: OISeries | null
  external: Partial<Record<IndicatorID, ExternalSeries>>
  symbol: SymbolInfo
  /** 读自 tokens.css 的一整套颜色（Swift 由 paletteSeed / dark / redUp 推出） */
  colors: ChartColors
  overlays: IndicatorID[]
  subs: IndicatorID[]
  params: Partial<Record<IndicatorID, number[]>>
  /** 时区偏移（分钟）。看盘统一上海时间，固定 480。 */
  tzOffset: number
  indicatorColors: Partial<Record<IndicatorID, Record<number, Hex>>>
  decimals: number
  options: ChartOptions
  hiddenOutputs: Partial<Record<IndicatorID, number[]>>
  subInverted: IndicatorID[]
  rsiUpper: number
  rsiLower: number
  oiSupported: boolean
  externalSupported: boolean
}

export interface ChartViewport {
  view: ViewWindow
  price: PriceTransform
  axisScaleAnchor: number | null
  subScale: Partial<Record<IndicatorID, number>>
}

export interface ChartOverlay {
  drawings: Drawing[]
  drawingPreviewID: string | null
  crosshair: Crosshair | null
  magnet: boolean
  orderFlow: OrderFlowSnapshot | null
  orderFlowDisplay: OrderFlowDisplay
  orderFlowSelected: OrderFlowGroupKey | null
  depth: OrderBook | null
  nowMs: number | null
}

export interface ChartState {
  readonly input: Readonly<ChartInput>
  readonly viewport: Readonly<ChartViewport>
  readonly overlay: Readonly<ChartOverlay>
}

export interface MakeStateOptions {
  series: BarSeries
  symbol: SymbolInfo
  view: ViewWindow
  colors?: ChartColors
  price?: PriceTransform
  overlays?: IndicatorID[]
  subs?: IndicatorID[]
  params?: Partial<Record<IndicatorID, number[]>>
  tzOffset?: number
  oi?: OISeries | null
  drawings?: Drawing[]
  crosshair?: Crosshair | null
  magnet?: boolean
  decimals?: number
  options?: ChartOptions
  nowMs?: number | null
  subScale?: Partial<Record<IndicatorID, number>>
}

/** ChartState.init：默认值照 Swift（对数价格轴、主图 MA、副图 AICoinBehavior.subpanels = 成交量 + MACD）。 */
export function makeState(o: MakeStateOptions): ChartState {
  return {
    input: {
      series: o.series, compare: [], percentAxis: false, oi: o.oi ?? null, external: {},
      symbol: o.symbol, colors: o.colors ?? FALLBACK_COLORS,
      overlays: o.overlays ?? ['MA'], subs: o.subs ?? ['VOL', 'MACD'], params: o.params ?? {},
      tzOffset: o.tzOffset ?? SHANGHAI_OFFSET_MIN, indicatorColors: {},
      decimals: o.decimals ?? o.symbol.priceDecimals, options: o.options ?? defaultChartOptions(),
      hiddenOutputs: {}, subInverted: [], rsiUpper: 70, rsiLower: 30, oiSupported: true, externalSupported: true,
    },
    viewport: { view: o.view, price: o.price ?? priceTransform('log'), axisScaleAnchor: null, subScale: o.subScale ?? {} },
    overlay: {
      drawings: o.drawings ?? [], drawingPreviewID: null, crosshair: o.crosshair ?? null, magnet: o.magnet ?? false,
      orderFlow: null, orderFlowDisplay: defaultOrderFlowDisplay(), orderFlowSelected: null, depth: null, nowMs: o.nowMs ?? null,
    },
  }
}

export const withInput = (s: ChartState, p: Partial<ChartInput>): ChartState => ({ ...s, input: { ...s.input, ...p } })
export const withViewport = (s: ChartState, p: Partial<ChartViewport>): ChartState => ({ ...s, viewport: { ...s.viewport, ...p } })
export const withOverlay = (s: ChartState, p: Partial<ChartOverlay>): ChartState => ({ ...s, overlay: { ...s.overlay, ...p } })

/** CandleStyle.Grid：「跟风格」= 不画（AICoin 手机端默认无网格）。 */
export type GridMode = 'none' | 'both'
export function effectiveGrid(s: ChartState): GridMode {
  return s.input.options.grid === 'on' ? 'both' : 'none'
}
export type Shape = 'solid' | 'hollowUp'
export const effectiveShape = (s: ChartState): Shape => (s.input.options.body === 'hollowUp' ? 'hollowUp' : 'solid')

export const effectivePriceMode = (s: ChartState): PriceMode => (s.input.percentAxis ? 'percent' : s.viewport.price.mode)

/** 指标的外部输入：持仓量并进 external[OI]。 */
export function indicatorInputs(s: ChartState): Partial<Record<IndicatorID, ExternalSeries>> {
  const out = { ...s.input.external }
  if (s.input.oi) out.OI = s.input.oi
  return out
}

export function compareBaseIndex(s: ChartState, view?: ViewWindow): number {
  const b = s.input.series
  if (b.isEmpty) return 0
  return b.index((view ?? s.viewport.view).from)
}

export function compareBase(s: ChartState, view?: ViewWindow): number {
  const b = s.input.series
  if (b.isEmpty) return 1
  const v = b.open[compareBaseIndex(s, view)]
  return Number.isFinite(v) && v > 0 ? v : 1
}

export function comparePercentLabel(value: number | null | undefined): string {
  if (value == null || !Number.isFinite(value)) return '—'
  if (Math.abs(value) < 0.005) return '0%'
  return (value > 0 ? '+' : '') + toFixed(value, 2) + '%'
}

/** 哪几层变了（changedLayers）。series 原地改时引用不变，另按 revision 比。 */
export interface Layers { input: boolean; viewport: boolean; overlay: boolean }
export function changedLayers(old: ChartState | null, next: ChartState, oldSeriesRev?: number): Layers {
  if (!old) return { input: true, viewport: true, overlay: true }
  return {
    input: old.input !== next.input || (oldSeriesRev !== undefined && oldSeriesRev !== next.input.series.revision),
    viewport: old.viewport !== next.viewport,
    overlay: old.overlay !== next.overlay,
  }
}
