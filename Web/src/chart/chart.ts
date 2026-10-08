/* Hkline Web · K 线引擎（TradingView 桌面版的那一套）
 *
 * 和手机那套（AICoin 复刻）完全分开。对齐的是 TradingView 桌面版：
 *   · 多窗格：主图 + 最多八个副图（MAX_SUBS），窗格之间 1 px 分隔、可拖动改高度
 *   · 右侧价格轴：最新价标签（实心、涨跌色）；十字线在轴上出深色标签。本根收线倒计时 2026-10-03 起不画
 *     （用户用不到，三端一起去掉；恢复见 tag before-remove-candle-countdown-2026-10-03）
 *   · 十字线：鼠标悬停就出（不用按住），虚线，横竖都在轴上标值
 *   · 左上角图例：品种 · 周期 · 交易所 + 开高低收 + 涨跌；每个指标一行，悬停出现 显示/设置/移除
 *   · 成交量叠在主图底部 16%，半透明
 *   · 滚轮缩放（以光标为中心）、拖动平移、拖价格轴缩放价格、拖时间轴缩放时间、双击价格轴回到自动
 *   · 往左拖到头自动加载更早的历史
 * 时间一律按上海时间（UTC+8）显示。
 *
 * 从原型 prototype/web-2026-09-29/chart.js 逐字移植；画法、数值不改。
 */
import { icon } from '../ui/icons'
import { esc } from '../ui/dom'
import { VALS_BOX, applyHidden, patchVals, toolsHtml, type LegVal } from './legendDom'
import { clamp, durText, fmt, fmtAxis, fmtCompact, fmtSub, hexA, niceStep } from '../util/format'
import { CATALOG, Calc, MAIN_IDS, paramText } from './calc'
import type { Bar, CalcEnv, CalcId, IndParams, IndicatorId, MainId, Series, SubId } from './calc'
import { TIME_TICK_MIN_PX, timeTicks } from './timeAxis'
import type { TimeTick } from './timeAxis'
import { subBandFills, subFixed, subLevelLines, subStyles, type LevelLine, type SubStyle } from './indicators'
import { mainOn } from './mainIndicators'
import { drawMoreMain, pivotPColor } from './overlaysMore'
import { VPVR_MODES, drawExtraMain, drawSubLevels, type Vpvr, type VpvrMode } from './overlays'
import { AXIS_H, FULL, dragPane, paneHeights, paneRatiosOf, type Degrade } from './panes'
import { COMPUTED, bbox, dashPattern, drawComputed, handlePixels, hitComputed, moveHandle, placeCount, setDraftEnd, snap45, widenPosition } from './drawTools'
import { drawKeyLevels, drawKeyAxis } from './keyLevels'
import { detachFlows } from './tradeFlow'
import { linePriceAt } from '../alerts/shape'
import { DEFAULTS as CS_DEFAULTS, crossText, dashOf, dayStartSh, marginRange, type ChartSettings } from './chartSettings'
import { COMPARE_COLORS, alignCompare, compareBaseIndexFrom, comparePercentAt, comparePercentLabel, compareSegments, pctOf, percentTickLabel, percentTicks, priceOfPct, type Aligned, type CompareLine } from './compare'

// 间距上下限、默认间距、右侧留白与滚轮手感都照 TradingView，见 ./wheel
import { DEFAULT_SPACING, anchoredRightBar, clampRightBar, clampSpacing, isWinChromium, panPx, pinchFactor, timeAxisDragSpacing, wheelDelta, wheelSpeed, zoomFactor, zoomScale, zoomStart, zoomStep, type ZoomAnim } from './wheel'
const SEP_HIT = 3 // 窗格分隔线上下各 3 px，热区 6 px

// 线条规格（网页版自己的一套，和手机端无关）。基准屏 1 CSS px = 1 物理像素：
// 横竖线一律整数宽、落在半像素上才锐利；指标曲线照 TradingView 内置指标默认 linewidth 1。
// K 线是主体：照 TradingView——影线 1 物理像素，实体宽按 TV optimalCandlestickWidth（间距越大占比越高，6 px 间距 5 px 实体），
// 实体奇偶跟影线走，让影线永远正好居中。
/** 不在价格轴上挂最新值的主图指标：它们画的是图形 / 档位，不是一条随 K 线走的线 */
const NO_AXIS_TAG = new Set<MainId>(['vpvr', 'keys', 'pivots', 'fractals', 'zigzag'])
export const LINE = {
  hair: 1,      // 网格、窗格分隔、轴线、RSI 参考线、最新价点线、提醒线、十字线
  plot: 1,      // 主图叠加线（MA / EMA / BOLL / 通道 / 均线族）、副图曲线：TV 内置指标默认都是 1 px
  band: 1,      // BOLL 上下轨、斐波那契各档、复盘的进出场连线
  draw: 2,      // 画线工具默认粗细（用户可改 1 / 2 / 3）
  measure: 1,   // 测量十字
  wallMin: 1, wallMax: 3, // 主力大单：按金额从 1 到 3 px，悬停 3 px
  handle: 2,    // 选中锚点的描边
  compare: 2,   // 对比线：比均线粗半档，一眼分得开
} as const
// 成交量：照 TradingView 默认——垫在主图底部 25%，涨 #26A69A / 跌 #EF5350 各 50% 透明，一根柱宽 = 间距 − 1 物理像素
const VOL_ALPHA = 0.5, VOL_H = 0.25, TV_VOL_UP = '#26A69A', TV_VOL_DOWN = '#EF5350'
/** K 线实体宽（物理像素）：TV / lightweight-charts optimalCandlestickWidth——间距 2.5–4 固定 3 px，
 *  其余按 1 − 0.2·atan(max(4, 间距) − 4)/(π/2) 取占比（间距越大越接近 80%），不足 1 物理像素按 1；
 *  再按影线（floor(pr)，至少 1）的奇偶收一格，影线正好居中。dpr 1 下：间距 6 → 5、10 → 7、20 → 15、50 → 39 */
export function candleBodyPx(spacing: number, pr: number): number {
  const wick = Math.max(1, Math.floor(pr))
  let w: number
  if (spacing >= 2.5 && spacing <= 4) w = Math.floor(3 * pr)
  else {
    const coeff = 1 - 0.2 * Math.atan(Math.max(4, spacing) - 4) / (Math.PI * 0.5)
    w = Math.max(Math.floor(pr), Math.min(Math.floor(spacing * coeff * pr), Math.floor(spacing * pr)))
  }
  if (w >= 2 && (wick % 2) !== (w % 2)) w--
  return Math.max(wick, w)
}

// ------------------------------------------------------------ 类型
/** avwap 锚定 VWAP、fvp 固定区间成交量分布、position 多空持仓（几何与画法在 drawTools.ts） */
export type DrawingType = 'trend' | 'ray' | 'hline' | 'vline' | 'rect' | 'fib' | 'measure' | 'avwap' | 'fvp' | 'position'
/** 画线锚点：时间（ms）+ 价格 */
export interface DrawPoint { t: number; p: number }
export interface Drawing {
  id: string
  type: DrawingType
  pts: DrawPoint[]
  color?: string
  width?: number
  /** 线型：没有就是实线 */
  dash?: 'dashed' | 'dotted'
  locked?: boolean
  /** 价格碰到这条线时提醒（fib / rect / measure 不给） */
  alert?: boolean
}

/** 主力订单流的一条大单（价位按步长并档） */
export interface Wall {
  price: number
  lo?: number
  hi?: number
  /** 美元金额 */
  size: number
  product: 'spot' | 'perp'
  venue?: string
  side?: 'bid' | 'ask'
  /** 首次出现的时间（ms） */
  from: number
  /** 撤单 / 成交的时间；还挂着为 null */
  to: number | null
  merged?: number
}

/** 价格提醒线：图上只用 price，其余字段是 app 自己的 */
export interface AlertLine {
  price: number
  id?: string
  symbol?: string
  kind?: string
  dir?: number
  created?: number
}

/** 提醒线（2026-10-06）：画线提醒挂的那条线删了、或者画线整层藏着时，按提醒自己存的那份几何（会响的就是它）
 *  在图上画一条细虚线、右端挂一枚铃铛——「画线和警报是不冲突的」，线没了提醒照常生效，图上也得看得见。
 *  线在、而且画出来了就不画（照 iOS ChartAlertSignal） */
export interface AlertSignal {
  id: string
  /** 它挂的那条画线自己的 id（不带品种前缀） */
  drawingID: string | null
  lines: { points: DrawPoint[]; extendLeft: boolean; extendRight: boolean }[]
}

/** 复盘的一个回合（开仓 → 平仓） */
export interface Marker {
  side: 'long' | 'short'
  entryT: number
  exitT: number
  entry: number
  exit: number
  pnl: number
  id?: string
  symbol?: string
  qty?: number
  gross?: number
  fee?: number
  fills?: number
  venue?: string
}

export interface ChartMeta {
  symbol: string
  title: string
  sub: string
  dec: number
  iv?: number
  /** 图例标题前的徽章 HTML */
  badge?: string
  /** 图例「主力订单流」一行的参数说明 */
  wallParam?: string
}
export type ChartMetaInput = Partial<ChartMeta> & { iv: number }

/** 美元指数没有成交量（恒 0）、没有持仓与成交明细：成交量、VWAP、成交量分布、CVD、OBV、大单、持仓量在它的图上不画。
 *  只是不画，用户的指标布局原样不动，切回别的品种照旧 */
const NO_VOLUME_MAIN = ['vwap', 'vpvr'] as const
const NO_VOLUME_MAINS = new Set<string>(['vwma'])
const NO_VOLUME_SUBS = new Set<string>(['oi', 'cvd', 'obv', 'whale'])
export function indFor(ind: IndState, symbol: string): IndState {
  if (symbol !== 'DXY') return ind
  const out: IndState = { ...ind, vol: false, subs: ind.subs.filter(id => !NO_VOLUME_SUBS.has(id)) }
  if (ind.mains) out.mains = ind.mains.filter(id => !NO_VOLUME_MAINS.has(id))
  for (const k of NO_VOLUME_MAIN) out[k] = false
  return out
}
/** 指标开关：老的几个主图叠加是布尔字段（会同步）；mains 是第三批主图叠加（加权均线、肯特纳通道、SAR…），只存本机 */
export interface IndState { ma: boolean; ema: boolean; boll: boolean; vol: boolean; subs: SubId[]; vwap?: boolean; st?: boolean; ichi?: boolean; vpvr?: boolean; keys?: boolean; mains?: string[] }

export interface ContextMenuInfo { clientX: number; clientY: number; price: number | null; time: number; drawing?: Drawing; /** 右键落在哪一格（主图 / 哪个副图） */ pane?: PaneId }

export interface ChartOptions {
  onActivate?: () => void
  onNeedMore?: () => void
  onCrosshairMove?: (t: number | null) => void
  onContextMenu?: (info: ContextMenuInfo) => void
  onLegendAction?: (id: string, act: string, btn: HTMLElement) => void
  onWallHover?: (w: Wall | null, clientX?: number, clientY?: number) => void
  onToolDone?: (d: Drawing, keep?: boolean) => void
  onSelectDrawing?: (d: Drawing | null) => void
  onDrawingsChanged?: () => void
  drawColor?: () => string | null | undefined
  /** 新画一条时的样式（同族工具记住上次改过的颜色、粗细、线型）；给了就不看 drawColor */
  drawStyle?: (t: DrawingType) => Partial<Pick<Drawing, 'color' | 'width' | 'dash'>>
  /** 再加这几条还在每只品种的上限以内吗；返回 false 就不加（由页面提示） */
  canAdd?: (add: Drawing[]) => boolean
  /** 开始 / 结束拖一条画线（选中快捷条拖动时淡出） */
  onDrawDrag?: (on: boolean) => void
  onAutoChange?: (on: boolean) => void
  /** 在价格轴上点「+」、拖到位松手：在这个价位建一条提醒 */
  onAlertCreate?: (price: number) => void
  /** 拖动已有的提醒线松手 */
  onAlertMove?: (a: AlertLine, price: number) => void
  /** 拖窗格分隔线松手：各副图占画布高的比例；双击分隔线回默认时给 null */
  onPaneResize?: (ratios: Record<string, number> | null) => void
  /** 用户平移 / 缩放了时间轴：当前可见的首尾时间（多图时间轴联动） */
  onViewChange?: (t0: number, t1: number) => void
}

export interface ThemeColors {
  bg: string; grid: string; text: string; text2: string; text3: string
  cross: string; crossLabel: string; scaleLine: string; sep: string
  up: string; down: string; accent: string; alert: string; line: string
}

export interface PriceRange { min: number; max: number }
export type PaneId = 'main' | SubId
export interface Pane { id: PaneId; y: number; h: number; ticks?: number[] }

/** 一条画线连同它的标签、提醒点、选中把手整个落在主图之外（拖到看不见的历史里、价格在视野上下）：这一帧不画。
 *  几百条画线的品种（C15 的 BTC 500 条）每次重画都把屏幕外的斐波那契逐级写字，挂机时占主线程约 0.6%。
 *  射线会往外延伸、不判；水平线只看高度；斐波那契的读数写在左端再往左，左边多留 240；测量的读数框在上下 50、宽 200 以内。 */
export function offPlot(type: string, pts: XY[], p: Pane, PW: number): boolean {
  if (!pts.length || type === 'ray') return false
  let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity
  for (const q of pts) { if (q.x < x0) x0 = q.x; if (q.x > x1) x1 = q.x; if (q.y < y0) y0 = q.y; if (q.y > y1) y1 = q.y }
  if (![x0, x1, y0, y1].every(Number.isFinite)) return false
  const m = type === 'measure' ? 200 : 16, left = type === 'fib' ? m + 240 : m
  if (y1 + m < p.y || y0 - m > p.y + p.h) return true
  if (type === 'hline') return false
  return x1 + m < 0 || x0 - left > PW
}
export interface Crosshair { x: number; y: number; pane?: PaneId }
export interface DrawingHit { d: Drawing; handle: number | null }

/** 主图的坐标映射（订单流的梯子、大单带、热力都靠它和 K 线对齐）。 */
export interface ChartGeometry {
  pane: Pane
  range: PriceRange
  plotW: number
  /** 可见的 K 线下标 */
  from: number
  to: number
  /** 一根 K 线的像素宽 */
  spacing: number
  iv: number
  log: boolean
  priceToY: (p: number) => number
  yToPrice: (y: number) => number
  /** 时间 → K 线中心的 x（落在一根 K 线内部时按比例插值） */
  timeToX: (t: number) => number
  xToTime: (x: number) => number
  /** 第 i 根 K 线的开盘时间（可以越过两头往外推） */
  timeOf: (i: number) => number
  indexToX: (i: number) => number
  colors: ThemeColors
  dec: number
  /** 最后一根 K 线的收盘（没有就 null） */
  last: number | null
  /** 第 i 根 K 线的开高低收（没有就 null）：订单流的记号要躲开蜡烛 */
  bar: (i: number) => { o: number; h: number; l: number; c: number } | null
  /** x → 连续下标（第几根，带小数） */
  xToIndex: (x: number) => number
}
/** 外挂的绘制层：under 画在蜡烛下面，over 画在画线上面；hover / click 返回 true 表示这一下归它 */
export interface ChartLayer {
  /** 画在成交量柱与蜡烛之下（深度热力这种铺底的） */
  back?: (c: CanvasRenderingContext2D, g: ChartGeometry) => void
  under?: (c: CanvasRenderingContext2D, g: ChartGeometry) => void
  over?: (c: CanvasRenderingContext2D, g: ChartGeometry) => void
  after?: (g: ChartGeometry) => void
  /** true = 认领悬停并换成手形；'soft' = 认领（出浮层）但光标保持十字 */
  hover?: (x: number, y: number, clientX: number, clientY: number) => boolean | 'soft'
  leave?: () => void
  click?: (x: number, y: number) => boolean
}

type Region = 'plot' | 'time' | 'price' | 'corner' | `sep:${string}`
interface XY { x: number; y: number }
/** `vertical`：右键拖画布 = 只做纵向平移（openmarket Hyperzoom 同款），松手时没动过才弹右键菜单 */
interface DragPan { kind: 'pan'; region: Region; x0: number; y0: number; right0: number; sp0: number; r0: PriceRange | null; moved: boolean; pane: Pane | undefined; vertical?: boolean }
/** copied：⌘ 拖出来的那份副本（按下时已放进 drawings），收手势时连它一起拿走 */
interface DragDrawing { kind: 'drawing'; hit: DrawingHit; start: DrawPoint; orig: DrawPoint[]; moved: boolean; copied?: Drawing[] }
/** 两点工具按下拖到位松手也算画完（点两下也行） */
interface DragPlace { kind: 'place'; x0: number; y0: number }
interface DragMeasure { kind: 'measure' }
interface DragAlert { kind: 'alert'; line: AlertLine | null; price: number; moved: boolean }
type DragState = DragPan | DragDrawing | DragMeasure | DragAlert | DragPlace
/** 价格轴左侧「+」建提醒的热区宽度 */
const ALERT_CHIP_W = 22

// ------------------------------------------------------------ 引擎
export class TVChart {
  host: HTMLElement
  o: ChartOptions
  canvas: HTMLCanvasElement
  ctx: CanvasRenderingContext2D
  legendEl: HTMLDivElement
  paneLegendEls: HTMLDivElement[] = []
  /** 各副图图例外壳上次渲染的键（指标、参数、显隐），没变就不重建；读数另记在 .vals 元素的 _k 上 */
  paneLegendKeys: (string | null)[] = []
  /** 这一帧画完画布后要写的副图读数（见 tick：先把所有格子的画布画完，再统一写 DOM） */
  private paneLegendQ: Pane[] | null = null
  bars: Bar[] = []
  iv = 36e5
  meta: ChartMeta = { symbol: '', title: '', sub: '', dec: 2 }
  spacing = DEFAULT_SPACING
  rightBar = 0
  /** 进行中的滚轮缩放（共用帧里 stepZoom 一帧推一步）；null = 没在缩 */
  private zAnim: ZoomAnim | null = null
  ind: IndState = { ma: true, ema: false, boll: false, vol: true, subs: ['macd', 'rsi'] }
  /** 页面要的指标（偏好原样）；ind 是按品种收过的、真正画的那份（美元指数收掉成交量类与持仓） */
  indWanted: IndState = { ...this.ind }
  params: Record<IndicatorId, IndParams>
  hidden = new Set<string>()
  /** 用户拖过的副图高（占画布高的比例）；null = 默认分配 */
  paneR: Record<string, number> | null = null
  /** 多图时格子小了的降级（收副图、图例精简、字号小一档、去成交量） */
  deg: Degrade = FULL
  /** 鼠标停在哪条窗格分隔线上（高亮成强调色） */
  hoverSep: string | null = null
  /** 画布在不在屏幕上（切到别的页、滚出视口时不画） */
  onScreen = true
  /** 图例要在下一帧重写（逐笔更新不再每笔都重写一次 innerHTML） */
  legendDirty = false
  private _series: Partial<Record<CalcId, Series[]>> = {}
  /** 指标要重算但还没算：真正读到（这一帧要画、图例要读数、调试钩子）时才算一遍。
   *  一帧里来几条推送只算一次；不在屏幕上的格子（十六图滚出去的、切到别的标签页）不算 */
  private calcStale = false
  get series(): Partial<Record<CalcId, Series[]>> { if (this.calcStale) this.computeSeries(); return this._series }
  private env: CalcEnv | null = null
  log = false
  auto = true
  /** 对比（叠加别的品种）：有对比时价格轴换成百分比、对数坐标让位（compare.ts） */
  compare: CompareLine[] = []
  /** 对齐缓存：主图的时间轴（根数 / 首尾）或任一只对比的数据戳变了才重算 */
  private cmpAligned: { key: string; v: Aligned[] } | null = null
  /** 这一帧百分比轴的刻度步长（标签小数位跟它走） */
  private cmpStep = 0
  manual: PriceRange | null = null // 主图手动价格区间 {min,max}
  cross: Crosshair | null = null   // {x,y}
  extCross: number | null = null // 同步来的时间
  drawings: Drawing[] = []
  tool: DrawingType | null = null
  draft: Drawing | null = null
  selected: Drawing | null = null
  magnet = false
  /** 只读：复盘回放里的画线只看不改、也不能新画 */
  readOnly = false
  /** ⌘ 按着：磁吸临时反过来（开着的临时关、关着的临时开） */
  metaHeld = false
  walls: Wall[] | null = null
  alerts: AlertLine[] = []
  markers: Marker[] | null = null
  replay: number | null = null
  stale = false
  drag: DragState | null = null
  /** 拖窗格分隔线：按下那一刻的各格高度 */
  private sepHs: number[] | null = null
  /** 右键按下时（macOS 在按下那一刻就发 contextmenu）先存着的菜单，松手没拖动才弹 */
  private pendingMenu: ContextMenuInfo | null = null
  /** 上一次右键拖动过（Windows 在松手之后才发 contextmenu，那一次不弹） */
  private rightDragged = false
  /** 鼠标停在主图价格轴上时的 y（画「+」建提醒） */
  axisHoverY: number | null = null
  /** 成交量分布的看法与上一帧的结果 */
  vpvrMode: VpvrMode = 'split'
  vpvrLast: Vpvr | null = null
  dirty = true
  /** 只有十字线 / 读数要换（鼠标扫过、别的格子同步过来）：贴回静态层底图再画十字线，不整帧重画（dirty 优先） */
  crossDirty = false
  /** 静态层底图（K 线、指标、画线、挂单墙、标记、价格轴标签——十字线以下的全部），与主画布同尺寸；格子销毁时释放 */
  private statCv: HTMLCanvasElement | OffscreenCanvas | null = null
  private statCtx: CanvasRenderingContext2D | OffscreenCanvasRenderingContext2D | null = null
  /** 底图是上一次整帧重画的结果 */
  private statOk = false
  /** 主画布上现在正好是静态层（上次整帧重画时没有十字线）：要底图时直接从它拷 */
  private mainStatic = false
  hoverWall: Wall | null = null
  /** 外挂绘制层（订单流） */
  layers: ChartLayer[] = []
  /** 这一帧主图上画线 / 交易记号写过字的地方（订单流的大单签要躲开它们，不压也不被压）；每帧画线前清空 */
  textRects: { x: number; y: number; w: number; h: number }[] = []
  private layerHover: ChartLayer | null = null
  colors: ThemeColors = { bg: '', grid: '', text: '', text2: '', text3: '', cross: '', crossLabel: '', scaleLine: '', sep: '', up: '', down: '', accent: '', alert: '', line: '' }
  font = '12px sans-serif'
  /** 画布已套用的像素比（resize 时定）：K 线横向几何按物理像素取整用它 */
  pr = 1
  /** 画完的测量框（下一次点击就清掉） */
  measure: Drawing | null = null
  /** app 在加载更早历史时置 true，期间不再催 onNeedMore；左缘挂一个「加载更早…」小标（稍等一下才淡入，快的看不见） */
  private _loadingMore = false
  private moreEl: HTMLElement | null = null
  get loadingMore(): boolean { return this._loadingMore }
  set loadingMore(v: boolean) {
    if (v === this._loadingMore) return
    this._loadingMore = v
    if (v && !this.moreEl && typeof document !== 'undefined') {
      this.moreEl = document.createElement('div'); this.moreEl.className = 'chart-more'
      this.moreEl.innerHTML = '<span class="spin"></span>加载更早…'
      this.host.appendChild(this.moreEl)
    }
    if (this.moreEl) this.moreEl.hidden = !v
  }
  /** 新数据在路上（换品种 / 周期、冷启动）：图例先换成它的标题加「载入中」；手里有旧图就留着、淡下去、不能点
   *  （画线、拖提醒线这时按新品种记会串到别的品种上）。setData 一来就收 */
  pendingMeta: ChartMeta | null = null
  /** 画线整体隐藏 */
  drawingsHidden = false
  /** 足迹图等替换蜡烛的画法（chart/footprint.ts 挂）：返回 true 就不再画蜡烛；legendExtra 往图例末尾加行 */
  footprint: ((p: Pane, r: PriceRange, from: number, to: number) => boolean) | null = null
  legendExtra: ((i: number) => string) | null = null
  /** 等幅 K 线等换了横轴的画法（chart/rangeBars.ts 挂）：返回 false 的画线这时不画、点不中（不删） */
  drawingShown: ((d: Drawing) => boolean) | null = null
  /** 图表设置（所有格子共用一份，见 chartSettings.ts）；没设过（含测试里的假图）走 cs() 的默认值，所以这里不给初值 */
  settings?: ChartSettings
  /** 皮肤给的原色（readTheme 读的）；colors = 它叠上图表设置里的颜色覆盖 */
  baseColors?: ThemeColors
  /** 提醒线（见 AlertSignal）：页面把这只品种上还在生效的画线提醒整份给，画哪几条由 signalsShown 定 */
  alertSignals: AlertSignal[] = []
  dead = false
  ro: ResizeObserver
  w = 10
  h = 10
  aw = 56 // 价格轴宽；首帧前给最小值，免得 plotW() 是 NaN
  mainRange: PriceRange | null = null
  _panes: Pane[] | null = null
  _ranges: Record<string, PriceRange> = {}
  private io: IntersectionObserver | null = null
  /** 所有事件监听都挂在这个信号上，destroy 时一次摘掉（原型挂在 window 上的 mousemove / mouseup 不摘会泄漏） */
  private ac = new AbortController()

  constructor(host: HTMLElement, opts: ChartOptions = {}) {
    this.host = host
    this.o = opts
    this.canvas = document.createElement('canvas')
    host.appendChild(this.canvas)
    this.ctx = this.canvas.getContext('2d') as CanvasRenderingContext2D
    this.legendEl = document.createElement('div'); this.legendEl.className = 'legend'; host.appendChild(this.legendEl)
    this.params = JSON.parse(JSON.stringify(Object.fromEntries(Object.entries(CATALOG).map(([k, v]) => [k, v.params || {}])))) as Record<IndicatorId, IndParams>
    this.readTheme()
    this.bind()
    // 尺寸变了（拖分隔条、换布局）：ResizeObserver 本来就在排版之后、绘制之前、每帧最多一次，
    // 就在这里同步重设画布并重画，免得清空的画布闪一帧
    this.ro = new ResizeObserver(() => { if (this.dead) return; this.resize(); if (this.onScreen) { this.dirty = false; this.render() } })
    this.ro.observe(host)
    this.watchDpr()
    if (typeof IntersectionObserver !== 'undefined') {
      this.io = new IntersectionObserver(es => { const v = es[es.length - 1]?.isIntersecting ?? true; if (v && !this.onScreen) this.dirty = true; this.onScreen = v })
      this.io.observe(host)
    }
    this.resize()
    frames.add(this); kick()
  }

  // ---------------------------------------------------------- 外部接口
  readTheme(): void {
    const cs = getComputedStyle(this.host)
    const v = (n: string) => cs.getPropertyValue(n).trim()
    this.colors = {
      bg: v('--chart-bg'), grid: v('--chart-grid'), text: v('--chart-axis-text'), text2: v('--text-2'), text3: v('--text-3'),
      cross: v('--chart-cross'), crossLabel: v('--chart-cross-label'), scaleLine: v('--chart-scale-line'), sep: v('--chart-sep') || v('--chart-scale-line'),
      up: v('--up'), down: v('--down'), accent: v('--accent'), alert: v('--alert-line'), line: v('--line'),
    }
    this.baseColors = { ...this.colors }; this.mergeColors(); this.applyLegendOpts()
    this.font = `${this.deg.font}px ${getComputedStyle(document.body).getPropertyValue('--font-num').trim() || 'sans-serif'}`
    this.dirty = true
  }
  /** 多图降级：格子尺寸变了由页面算好传进来；没变就什么都不做 */
  setDegrade(d: Degrade): void {
    const o = this.deg
    if (o.subs === d.subs && o.legend === d.legend && o.font === d.font && o.vol === d.vol) return
    this.deg = d
    this.font = `${d.font}px ${this.fontFamily()}`
    // 多放出来的副图要现算（收掉的不用重算，下次 render 不画它就是了）
    const shown = (n: number): number => Math.min(n, this.ind.subs.length)
    if (shown(d.subs) > shown(o.subs)) this.recalc()
    this.paneLegendKeys.fill(null)
    this.dirty = true; this.renderLegend()
  }
  /** 副图高比例（所有格子共用一份，页面落盘） */
  setPaneRatios(r: Record<string, number> | null): void { this.paneR = r ? { ...r } : null; this.paneLegendKeys.fill(null); this.dirty = true }
  /** 多图时间轴联动：把别的格子的可见时间段套到自己身上（不改价格轴） */
  syncView(t0: number, t1: number): void {
    if (!this.bars.length || !(t1 > t0)) return
    const i0 = this.indexAt(t0), i1 = this.indexAt(t1)
    if (!(i1 > i0)) return
    this.spacing = clampSpacing(this.plotW() / (i1 - i0), this.plotW())
    this.rightBar = i1; this.dirty = true; this.legendDirty = true
    this.maybeMore()
  }
  /** 用户动了时间轴：告诉页面（联动别的格子） */
  private emitView(): void {
    if (!this.o.onViewChange || !this.bars.length) return
    this.o.onViewChange(this.timeOfIndex(this.xToIndex(0)), this.timeOfIndex(this.rightBar))
  }
  setData(bars: Bar[], meta: ChartMetaInput): void {
    // 上一份是空的（取 K 线失败、限流后重取）也要当新品种摆：否则视口还停在空数据的下标上，
    // 重取回来的 1500 根只露出最老的那几根，价格轴也按几十天前的价位摆
    const sameSym = this.meta.symbol === meta.symbol && this.iv === meta.iv && this.bars.length > 0
    this.bars = bars
    this.iv = meta.iv
    this.meta = Object.assign({}, this.meta, meta)
    this.ind = indFor(this.indWanted, this.meta.symbol)
    if (!sameSym) {
      // 换品种 / 周期时手里还按着：拖平移记的起点下标、分隔线起拖的高度、两下画线的第一下都是上一份数据上的，作废
      this.dropGesture(true)
      this.rightBar = bars.length - 1 + this.rightMarginBars(); this.manual = null; this.auto = true; this.o.onAutoChange?.(true)
    }
    if (this.pendingMeta) { this.pendingMeta = null; this.host.classList.remove('pending') }
    this.recalc(); this.dirty = true; this.renderLegend()
  }
  /** 见 pendingMeta；meta 为 null 是收起（数据没来也不等了） */
  setPending(meta: ChartMetaInput | null): void {
    if (!meta) {
      if (!this.pendingMeta) return
      this.pendingMeta = null
    } else {
      this.dropGesture(true)
      this.selected = null; this.measure = null; this.cross = null
      this.pendingMeta = Object.assign({}, this.meta, meta)
    }
    this.host.classList.toggle('pending', !!this.pendingMeta && this.bars.length > 0)
    this.dirty = true; this.renderLegend()
  }
  /** 只换图例 / 价格轴用的品种信息（品种表晚到：精度、名字补上），数据与视口不动 */
  setMeta(meta: Partial<ChartMeta>): void {
    if (this.pendingMeta) Object.assign(this.pendingMeta, meta.symbol == null || meta.symbol === this.pendingMeta.symbol ? meta : {})
    if (meta.symbol != null && meta.symbol !== this.meta.symbol) return
    const before = JSON.stringify(this.meta)
    this.meta = Object.assign({}, this.meta, meta)
    if (JSON.stringify(this.meta) === before) return
    this.recalc(); this.dirty = true; this.renderLegend()
  }
  prependData(more: Bar[]): void {
    if (!more.length) return
    const first = this.bars[0]?.t ?? Infinity
    more = more.filter(b => b.t < first)
    this.bars = more.concat(this.bars)
    this.rightBar += more.length
    // 拖着平移时翻到的页：起拖那一刻记的右缘下标也要跟着挪，否则下一次 mousemove 按旧下标算，视口一下跳回去 more.length 根
    if (this.drag?.kind === 'pan') this.drag.right0 += more.length
    if (this.replay != null) this.replay += more.length
    this.recalc(); this.dirty = true
  }
  updateBar(b: Bar): void {
    const n = this.bars.length
    if (!n) return
    const last = this.bars[n - 1]
    // 推送来的 K 线不带持仓量：同一根保留已取到的值；新开一根先顺延上一根的，等每分钟的尾巴补取换成币安那一桶的真值
    if (b.t === last.t) { const oi = last.oi; Object.assign(last, b); if (last.oi == null && oi != null) last.oi = oi }
    else if (b.t > last.t) {
      const atEdge = this.rightBar >= n - 1
      if (b.oi == null && last.oi != null) b.oi = last.oi
      this.bars.push(b)
      // 贴着右沿时新的一根顶出来：视口跟着挪一根；正拖着（平移 / 拖时间轴）的话起拖记的右缘下标也要 +1，
      // 否则下一次 mousemove 按旧下标算，视口跳回一根（1 秒线 / 1 分钟线拖动中每到收线就闪一下）
      if (atEdge) { this.rightBar += 1; if (this.drag?.kind === 'pan') this.drag.right0 += 1 }
    } else return
    this.recalcTail(); this.dirty = true
    if (!this.cross) this.legendDirty = true
  }
  setIndicators(ind: Partial<IndState>): void { this.indWanted = Object.assign({}, this.indWanted, ind); this.ind = indFor(this.indWanted, this.meta.symbol); this.recalc(); this.dirty = true; this.renderLegend() }
  setParams(id: IndicatorId, p: IndParams): void { this.params[id] = p; this.recalc(); this.dirty = true; this.renderLegend() }
  setDrawings(arr: Drawing[]): void {
    // 换了一份（换品种、撤销 / 重做、同步落地）：手里正拖的那条、画了一半的草稿属于上一份，不能带进这一份
    if (arr !== this.drawings) this.dropGesture(false)
    this.drawings = arr; this.selected = null; this.measure = null; this.dirty = true
  }
  /** 收掉手里正在做的事。拖画线：放回起拖时的位置（没松手就不算改过）；草稿与测量丢掉；
   *  拖提醒线也收（松手会按当前格子的品种建 / 挪提醒，品种已经换了）；
   *  all = 连平移 / 分隔线 / 右键平移也收（换了数据，起拖记的下标与高度都不对了） */
  private dropGesture(all: boolean): void {
    const d = this.drag
    this.draft = null
    if (!d) return
    if (d.kind === 'drawing') {
      d.hit.d.pts = d.orig.map(q => ({ ...q }))
      if (d.copied) { const k = d.copied.indexOf(d.hit.d); if (k >= 0) d.copied.splice(k, 1) }
      if (d.moved) this.o.onDrawDrag?.(false)
    } else if (d.kind === 'pan') { if (!all) return; this.sepHs = null; this.pendingMenu = null }
    this.drag = null
    if (this.canvas) this.canvas.style.cursor = 'crosshair'
    this.dirty = true
  }
  setTool(t: DrawingType | null): void { this.tool = t; this.draft = null; this.canvas.style.cursor = 'crosshair'; this.dirty = true }
  setMagnet(on: boolean): void { this.magnet = on }
  // ---------------------------------------------------------- 图表设置
  cs(): ChartSettings { return this.settings ?? CS_DEFAULTS }
  /** 右侧留白（根数）：图表设置「画布 · 边距 · 右」 */
  rightMarginBars(): number { return this.cs().rightBars }
  /** 换设置：立刻重画；右边距变了而最新一根正在屏幕上时，视图跟着让出 / 收回那几根 */
  setSettings(s: ChartSettings): void {
    const old = this.cs(); if (old === s) return
    this.settings = s
    if (old.rightBars !== s.rightBars && this.bars.length && this.rightBar >= this.lastIndex()) this.rightBar = Math.max(this.lastIndex(), this.rightBar + s.rightBars - old.rightBars)
    this.mergeColors(); this.applyLegendOpts()
    this.dirty = true; this.paneLegendKeys.fill(null); this.renderLegend()
  }
  private mergeColors(): void {
    const b = this.baseColors; if (!b) return
    const s = this.cs()
    this.colors = { ...b, bg: s.bg ?? b.bg, text: s.scaleText ?? b.text, scaleLine: s.scaleLine ?? b.scaleLine, cross: s.crossColor ?? b.cross }
  }
  /** 状态栏的显隐与底色：只切格子上的 class / 变量，图例的拼法不动（app.css 的 .ls-*） */
  private applyLegendOpts(): void {
    const h = this.host; if (!h) return
    const s = this.cs(), cl = h.classList
    cl.toggle('ls-no-ohlc', !s.ohlc); cl.toggle('ls-no-chg', !s.barChange)
    cl.toggle('ls-no-indtitle', !s.indTitles); cl.toggle('ls-no-indargs', !s.indArgs); cl.toggle('ls-no-indvals', !s.indValues)
    cl.toggle('ls-bg', s.legendBg)
    const bg = `color-mix(in srgb, ${this.colors.bg || 'transparent'} ${s.legendBgOpacity}%, transparent)`
    if (h.style.getPropertyValue('--ls-bg') !== bg) h.style.setProperty('--ls-bg', bg)
    // 画布背景改过色：图例悬停底、工具按钮底跟着换（--chart-bg 本身不动，readTheme 还要从它读皮肤色）
    cl.toggle('cs-bgset', !!s.bg)
    if (s.bg) h.style.setProperty('--cs-bg', s.bg); else h.style.removeProperty('--cs-bg')
  }
  /** 状态栏「成交量」：成交量指标没开时在开高低收后面带一个量（开着的话它自己那行已经有了） */
  legendVolume(b: Bar, cls: string): LegVal[] {
    return this.cs().volume && !this.ind.vol ? [['', '量', fmtCompact(b.v), cls]] : []
  }
  /** 最新一根的颜色（最新价线、最新价标签）：跟实体色走，行情断了是灰的 */
  lastColor(b: Bar): string {
    const C = this.colors, S = this.cs()
    if (this.stale) return C.text3
    const i = this.lastIndex(), prev = this.bars[i - 1]
    const up = S.prevCloseColor && prev ? b.c >= prev.c : b.c >= b.o
    return (up ? S.bodyUp : S.bodyDown) ?? (up ? C.up : C.down)
  }
  /** 画布背景：纯色或上下渐变 */
  private fillBg(W: number, H: number): void {
    const c = this.ctx, S = this.cs(), bg = this.colors.bg
    if (S.bgType === 'gradient') {
      const g = c.createLinearGradient(0, 0, 0, H)
      g.addColorStop(0, bg); g.addColorStop(1, S.bg2 ?? this.baseColors?.bg ?? bg)
      c.fillStyle = g
    } else c.fillStyle = bg
    c.fillRect(0, 0, W, H)
  }
  /** 水印：品种代号与周期，铺在主图正中 */
  private drawWatermark(p: Pane, PW: number): void {
    const S = this.cs(); if (!S.watermark || !this.meta.symbol) return
    const c = this.ctx, iv = this.meta.sub.split('·').map(x => x.trim()).filter(Boolean)[0] || ''
    const text = iv ? `${this.meta.symbol}, ${iv}` : this.meta.symbol
    let size = clamp(Math.round(p.h / 5), 16, 96)
    c.save()
    c.font = `600 ${size}px ${this.fontFamily()}`
    const w = c.measureText(text).width
    if (w > PW * 0.8) { size = Math.max(12, Math.floor(size * PW * 0.8 / w)); c.font = `600 ${size}px ${this.fontFamily()}` }
    c.globalAlpha = S.watermarkOpacity / 100; c.fillStyle = this.colors.text; c.textAlign = 'center'; c.textBaseline = 'middle'
    c.fillText(text, PW / 2, p.y + p.h / 2)
    c.restore()
  }
  /** 前一天（上海时间）最后一根的收盘价；日线及以上没有「前收盘」这条线 */
  prevDayClose(): number | null {
    if (this.iv >= 864e5) return null
    const i = this.lastIndex(), b = this.bars[i]; if (!b) return null
    const start = dayStartSh(b.t)
    for (let k = i; k >= 0 && i - k < 5000; k--) if (this.bars[k].t < start) return this.bars[k].c
    return null
  }
  /** 可见区间的最高 / 最低价 */
  visibleHiLo(): { hi: number; lo: number } | null {
    const { from, to } = this.visible()
    let hi = -Infinity, lo = Infinity
    for (let i = Math.max(0, from); i <= Math.min(to, this.lastIndex()); i++) { const b = this.bars[i]; if (!b) continue; if (b.h > hi) hi = b.h; if (b.l < lo) lo = b.l }
    return hi >= lo && Number.isFinite(hi) && Number.isFinite(lo) ? { hi, lo } : null
  }
  /** 主图里的参考线：最高最低价线、前收盘价线（画在主图裁剪区里） */
  private drawRefLines(p: Pane, r: PriceRange): void {
    const S = this.cs(); if (!S.hiloLine && !S.prevClose) return
    const c = this.ctx, PW = this.plotW()
    const line = (v: number, col: string) => {
      const y = Math.round(this.priceToY(v, p, r)) + .5; if (y < p.y || y > p.y + p.h) return
      c.strokeStyle = col; c.lineWidth = LINE.hair; c.setLineDash([4, 4]); c.beginPath(); c.moveTo(0, y); c.lineTo(PW, y); c.stroke(); c.setLineDash([])
    }
    if (S.hiloLine) { const hl = this.visibleHiLo(); if (hl) { line(hl.hi, this.colors.text2); line(hl.lo, this.colors.text2) } }
    if (S.prevClose) { const v = this.prevDayClose(); if (v != null) line(v, this.colors.text3) }
  }
  /** 价格轴上的一枚标签（和最新价标签一个样子） */
  private axisTag(p: Pane, y: number, text: string, bg: string, fg = '#fff'): void {
    const c = this.ctx, PW = this.plotW(), h = 20
    if (y < p.y || y > p.y + p.h) return
    const top = clamp(y - 10, p.y, p.y + p.h - h)
    c.fillStyle = bg; roundRect(c, PW + 1, top, this.aw - 2, h, 3); c.fill()
    c.fillStyle = fg; c.textAlign = 'left'; c.font = this.font // TV 轴上标签不加粗
    c.fillText(text, PW + 8, top + 10)
    c.font = this.font
  }
  /** 比例尺与线：指标最新值、最高最低价、前收盘价的轴标签（主图）。最新价标签最后画，压在最上面 */
  private drawSettingLabels(p: Pane, r: PriceRange): void {
    const S = this.cs(), C = this.colors, i = this.lastIndex()
    // TV showStudyLastValue：每个主图指标的每条线都在价格轴上挂当前值（成交量分布、关键位、枢轴、分形、之字转向是图形，不挂）
    if (S.indLabels) for (const id of MAIN_IDS) {
      if (NO_AXIS_TAG.has(id) || !mainOn(this.ind, id) || this.hidden.has(id)) continue
      const ser = this.series[id]; if (!ser) continue
      const cols = CATALOG[id].colors ?? []
      ser.forEach((s, k) => { const v = s[i]; if (v != null && Number.isFinite(v)) this.axisTag(p, this.priceToY(v, p, r), this.mainAxisText(v), cols[k % cols.length] || C.text2) })
    }
    if (S.hiloLabel) { const hl = this.visibleHiLo(); if (hl) { this.axisTag(p, this.priceToY(hl.hi, p, r), this.mainAxisText(hl.hi), C.text2); this.axisTag(p, this.priceToY(hl.lo, p, r), this.mainAxisText(hl.lo), C.text2) } }
    if (S.prevClose) { const v = this.prevDayClose(); if (v != null) this.axisTag(p, this.priceToY(v, p, r), this.mainAxisText(v), C.text3) }
  }
  /** 副图指标每条线 / 柱的最新值标签（TV showStudyLastValue），柱子的标签色就是这根柱子的颜色 */
  private drawSubLabels(panes: Pane[]): void {
    if (!this.cs().indLabels) return
    const i = this.lastIndex()
    for (const p of panes.slice(1)) {
      const id = p.id as SubId, r = this._ranges[p.id], ser = this.series[id]; if (!r || !ser || this.hidden.has(id)) continue
      const styles: readonly SubStyle[] = id === 'macd' ? ['line', 'line', 'hist4'] : subStyles(id) ?? []
      const cols = CATALOG[id]?.colors ?? []
      const h4 = this.hist4Colors()
      ser.forEach((s, k) => {
        const st = styles[k] ?? 'line', v = s[i]; if (v == null || !Number.isFinite(v)) return
        const col = st === 'hist' || st === 'hist4' || st === 'histTrend' ? this.histColor(st, v, s[i - 1] ?? v, h4) : cols[k % cols.length] || this.colors.text2
        this.axisTag(p, this.priceToY(v, p, r), this.subFmt(id, v), col)
      })
    }
  }
  /** 能不能新画、拖、改画线（复盘回放里不能） */
  editable(): boolean { return !this.readOnly && !this.pendingMeta }
  /** 把选中的画线挪 dx / dy 像素（方向键微调）；锁住的、只读时不动 */
  nudgeSelected(dx: number, dy: number): boolean {
    const d = this.selected
    if (!d || d.locked || !this.editable() || !this._panes) return false
    d.pts = this.shiftPts(d.pts, dx, dy); this.dirty = true; return true
  }
  /** 锚点整体挪 dx / dy 像素：横向按连续下标挪（不吸到整根，1 px 就是 1 px），纵向按像素换价 */
  shiftPts(pts: DrawPoint[], dx: number, dy: number): DrawPoint[] {
    const p = (this._panes as Pane[])[0], r = this._ranges.main
    return pts.map(q => ({
      t: dx ? Math.round(this.timeOfIndex(this.indexAt(q.t) + dx / this.spacing)) : q.t,
      p: dy ? this.yToPrice(this.priceToY(q.p, p, r) + dy, p, r) : q.p,
    }))
  }
  /** 拖整条画线：起拖时的各点按「鼠标从 start 挪到 now」平移。横向按整根挪；纵向在价格轴的空间里挪
   *  （对数轴按比例）——对数轴上加同一个价差，上下两个点在屏幕上挪的距离不一样，整条线跟着鼠标变形，
   *  往下拖还会把低的那个点拖到 0 以下、整条线消失 */
  dragBody(orig: DrawPoint[], start: DrawPoint, now: DrawPoint): DrawPoint[] {
    const dt = this.indexAt(now.t) - this.indexAt(start.t), dp = this.tf(now.p) - this.tf(start.p)
    return orig.map(q => ({ t: this.timeAt(Math.round(this.indexAt(q.t) + dt)), p: this.itf(this.tf(q.p) + dp) }))
  }
  /** 选中画线在画布上的上沿（选中快捷条躲开它） */
  selectedTop(): number | null {
    const d = this.selected
    if (!d || !this._panes) return null
    return bbox(this, d, this._panes[0], this._ranges.main)?.y0 ?? null
  }


  setWalls(w: Wall[] | null): void { this.walls = w; this.dirty = true }
  setAlerts(a: AlertLine[] | null | undefined): void { this.alerts = a || []; this.dirty = true }
  setAlertSignals(a: AlertSignal[] | null | undefined): void { this.alertSignals = a || []; this.dirty = true }
  setVpvrMode(m: VpvrMode): void { this.vpvrMode = m; this.dirty = true; this.renderLegend() }
  setMarkers(m: Marker[] | null): void { this.markers = m; this.dirty = true }
  setReplay(i: number | null): void { this.replay = i; this.dirty = true; this.renderLegend() }
  setLog(on: boolean): void { this.log = on; this.manual = null; this.dirty = true }
  /** 对数坐标真的在用（有对比时让位给百分比轴，偏好里的「对数」不动，撤掉对比就回来） */
  logOn(): boolean { return this.log && !this.compare?.length }
  compareOn(): boolean { return !!this.compare?.length }
  /** 叠加对比线（页面按偏好与这一格的主图挑好、取好数）；空数组 = 没有对比，一切照旧。
   *  开关翻转时价格轴回到自动（百分比轴与价格轴的手动区间不通用） */
  setCompare(lines: readonly CompareLine[]): void {
    const was = this.compare.length > 0, now = lines.length > 0
    this.compare = lines.slice()
    if (was !== now) { this.manual = null; if (!this.auto) { this.auto = true; this.o.onAutoChange?.(true) } }
    this.dirty = true; this.renderLegend()
  }
  /** 各条对比线按主图对齐好的开收（缓存） */
  compareAligned(): Aligned[] {
    const b = this.bars, n = b.length
    const key = `${n}:${b[0]?.t}:${b[n - 1]?.t}|` + this.compare.map(l => `${l.key}:${l.rev}`).join('|')
    if (this.cmpAligned?.key !== key) this.cmpAligned = { key, v: this.compare.map(l => alignCompare(b, l.bars)) }
    return this.cmpAligned.v
  }
  /** 百分比的基准：可见区第一根的下标与开盘价 */
  compareBase(): { index: number; price: number } | null {
    if (!this.compare?.length || !this.bars?.length) return null
    const i = clamp(this.visible().from, 0, this.bars.length - 1), o = this.bars[i]?.o
    return o > 0 ? { index: i, price: o } : null
  }
  /** 每条对比线此刻的几何：基准根、从哪根起画、读第 i 根的百分比 */
  compareViews(): { line: CompareLine; color: string; base: number | null; start: number; at: (i: number) => number | null }[] {
    const base = this.compareBase(), al = this.compareAligned(), hi = this.lastIndex()
    return this.compare.map((line, k) => {
      const a = al[k], color = line.color || COMPARE_COLORS[k % COMPARE_COLORS.length]
      const bi = base && a ? compareBaseIndexFrom(a.open, base.index, hi) : null
      // 基准就是主图那根：从可见区最左（含左边半根）起画；往后挪了（那几根它没数据）从它自己的基准起
      const start = bi == null ? Infinity : bi === base!.index ? Math.max(0, base!.index - 1) : bi
      return { line, color, base: bi, start, at: (i: number) => bi == null || i < start ? null : comparePercentAt(a, i, bi) }
    })
  }
  /** 主图价格轴上的文字：有对比时是相对基准的百分比 */
  mainAxisText(v: number, tick = false): string {
    const base = this.compareBase()
    if (!base) return fmtAxis(v, this.meta.dec)
    return tick ? percentTickLabel(v, base.price, this.cmpStep) : comparePercentLabel(pctOf(v, base.price))
  }
  setAuto(on: boolean): void { this.auto = on; if (on) this.manual = null; this.dirty = true; this.o.onAutoChange?.(on) }
  setStale(on: boolean): void { this.stale = on; this.dirty = true; this.renderLegend() }
  // 图例读数也跟着同步来的时间走（legendIndex 认 extCross），不然别的格子十字线挪了、图例还停在最新一根上
  syncCrosshair(t: number | null): void { if (t === this.extCross) return; this.extCross = t; this.crossDirty = true; this.legendDirty = true }
  resetView(): void { this.zAnim = null; this.spacing = DEFAULT_SPACING; this.rightBar = this.lastIndex() + this.rightMarginBars(); this.setAuto(true) }
  setVisibleRange(t0: number, t1: number): void {
    this.zAnim = null
    const i0 = this.indexAt(t0), i1 = this.indexAt(t1)
    const n = Math.max(10, i1 - i0 + 1)
    this.spacing = clampSpacing(this.plotW() / (n + this.rightMarginBars()), this.plotW())
    this.rightBar = i1 + this.rightMarginBars(); this.setAuto(true)
  }
  scrollBars(k: number): void { this.rightBar += k; this.dirty = true; this.maybeMore() }
  /** 一步到位的缩放（键盘 + / -）：anchorX 底下那根不动 */
  zoom(f: number, anchorX?: number): void {
    this.zAnim = null
    const ax = anchorX ?? this.plotW()
    const idx = this.xToIndex(ax)
    this.spacing = clampSpacing(this.spacing * f, this.plotW())
    this.rightBar = this.clampRB(idx + (this.plotW() - ax) / this.spacing)
    this.dirty = true; this.maybeMore()
  }
  /** 右沿下标夹住，两头至少各留 2 根看得见（TV correctOffset），不让一路滚 / 拖到整屏空白 */
  private clampRB(rb: number): number { return clampRightBar(rb, this.lastIndex(), this.plotW(), this.spacing) }
  /** 滚轮 / 捏合缩放（TV TimeScale.zoom）：x 底下那根 K 线不动（平常 x 给右沿 = 右沿不动，⌘ / Ctrl 时给鼠标处）；
   *  间距 ZOOM_MS 内顺滑插到目标（共用帧里 stepZoom 推），还没到位又滚一格就在目标上再乘一格，锚点换成这一格的 x */
  wheelZoom(f: number, x: number, now = performance.now(), instant = false): void {
    const W = this.plotW()
    if (!this.bars.length || !(W > 0) || !(f > 0) || f === 1) return
    const ax = clamp(x, 1, W) // TV zoomTime 把锚点夹在 [1, 宽]
    if (instant) { // 触控板捏合：一个事件一小口、每帧都来，直接按量缩才跟手（TV 同款）；再插值就是手指停了图还在追
      this.zAnim = null
      const idx = this.xToIndex(ax)
      this.spacing = clampSpacing(this.spacing * f, W)
      this.rightBar = this.clampRB(anchoredRightBar(idx, ax, W, this.spacing))
      this.dirty = true; this.legendDirty = true
      this.maybeMore(); this.emitView()
      return
    }
    this.zAnim = zoomStart(this.zAnim, this.spacing, this.rightBar, f, this.xToIndex(ax), ax, now, W)
    if (this.zAnim) kick()
  }
  /** 共用帧开头调（先于所有格子的 frame）：推进滚轮缩放一帧，联动的格子同一帧跟上。
   *  别处改了间距（双击时间轴复位、联动套来的时间段）就作罢；只挪了右沿（新的一根顶出来、补更早的历史、横滑）锚点跟着挪 */
  stepZoom(now: number): void {
    const a = this.zAnim
    if (!a) return
    if (this.dead || this.drag || this.spacing !== a.sp || !this.bars.length) { this.zAnim = null; return }
    if (this.rightBar !== a.rb) a.idx += this.rightBar - a.rb
    const r = zoomStep(a, now, this.plotW(), this.lastIndex())
    this.spacing = a.sp = r.spacing; this.rightBar = a.rb = r.rightBar
    if (r.done) this.zAnim = null
    this.dirty = true; this.legendDirty = true
    this.maybeMore(); this.emitView()
  }
  /** 滚轮横滑（TV scrollChart）：px > 0 往新的那头；不带惯性 */
  wheelPan(px: number): void {
    if (!this.bars.length || !px) return
    this.rightBar = this.clampRB(this.rightBar + px / this.spacing)
    this.dirty = true; this.maybeMore()
  }
  /** 纵向缩放主图价格轴（以 anchorY 为不动点；f > 1 放大价格区间） */
  zoomPrice(f: number, anchorY?: number): void {
    const p = this._panes?.[0], r = this.mainRange
    if (!p || !r) return
    const y = anchorY ?? p.y + p.h / 2
    const a = this.tf(this.yToPrice(y, p, r)), lo = this.tf(r.min), hi = this.tf(r.max)
    if (!this.scaleManual(lo, hi, a, f)) return
    if (this.auto) { this.auto = false; this.o.onAutoChange?.(false) }
    this.dirty = true
  }
  /** 手动价格区间：以 a 为不动点把 [lo, hi]（都在 tf 空间）缩放 f 倍。
   *  跨度夹在 [相对 1e-6, 1e6 倍] 之间（对数轴是 1e-6 到 ln 1e12）：一路往里缩会缩到浮点分辨率以下，
   *  刻度步长比价格的最小可表示间隔还小，刻度循环停不下来、整页卡死；一路往外放会溢出成 Infinity */
  scaleManual(lo: number, hi: number, a: number, f: number): boolean {
    const span = hi - lo, mid = (lo + hi) / 2
    if (!(span > 0) || !isFinite(span) || !isFinite(mid) || !isFinite(a) || !(f > 0)) return false
    const minSpan = this.logOn() ? 1e-6 : Math.max(Math.abs(mid) * 1e-6, 1e-12)
    const maxSpan = this.logOn() ? Math.log(1e12) : Math.max(Math.abs(mid), 1) * 1e6
    const k = clamp(f, minSpan / span, maxSpan / span)
    this.manual = { min: this.itf(a - (a - lo) * k), max: this.itf(a + (hi - a) * k) }
    return true
  }
  /** 把某个时间 / 价位挪到图中间（不改缩放） */
  centerOn(t: number | null, p: number | null): void {
    if (t != null && this.bars.length) this.rightBar = this.indexAt(t) + this.plotW() / 2 / this.spacing
    if (p != null && this.mainRange) {
      const half = (this.tf(this.mainRange.max) - this.tf(this.mainRange.min)) / 2, m = this.tf(p)
      this.manual = { min: this.itf(m - half), max: this.itf(m + half) }
      if (this.auto) { this.auto = false; this.o.onAutoChange?.(false) }
    }
    this.dirty = true; this.maybeMore()
  }
  geometry(): ChartGeometry | null {
    const p = this._panes?.[0], r = this.mainRange
    if (!p || !r || !this.bars.length) return null
    const { from, to } = this.visible()
    return {
      pane: p, range: r, plotW: this.plotW(), from, to, spacing: this.spacing, iv: this.iv, log: this.logOn(),
      priceToY: v => this.priceToY(v, p, r), yToPrice: y => this.yToPrice(y, p, r),
      timeToX: t => this.indexToX(this.indexAt(t)), xToTime: x => this.timeOfIndex(this.xToIndex(x)),
      timeOf: i => this.timeOfIndex(i), indexToX: i => this.indexToX(i),
      colors: this.colors, dec: this.meta.dec, last: this.lastBar()?.c ?? null,
      bar: i => { const b = this.bars[i]; return b ? { o: b.o, h: b.h, l: b.l, c: b.c } : null },
      xToIndex: x => this.xToIndex(x),
    }
  }
  /** 连续下标 → 时间（indexAt 的反函数） */
  timeOfIndex(i: number): number {
    const b = this.bars, n = b.length
    if (!n) return 0
    if (i <= 0) return b[0].t + i * this.iv
    if (i >= n - 1) return b[n - 1].t + (i - n + 1) * this.iv
    const k = Math.floor(i)
    return b[k].t + (i - k) * (b[k + 1].t - b[k].t)
  }
  lastIndex(): number { return this.replay != null ? this.replay : this.bars.length - 1 }
  destroy(): void {
    this.dead = true
    this.ro.disconnect()
    this.io?.disconnect()
    this.ac.abort()
    if (this.env) detachFlows(this.env.invalidate)
    frames.delete(this)
    this.drag = null
    if (this.statCv) { this.statCv.width = 0; this.statCv.height = 0 }
    this.statCv = null; this.statCtx = null; this.statOk = false
    this.host.innerHTML = ''
  }

  // ---------------------------------------------------------- 指标
  /** 标记指标要重算（K 线、指标开关、参数、异步数据变了）；真正的计算在第一次读 series 时做 */
  recalc(): void { this.calcStale = true; this.dirty = true }
  private computeSeries(): void {
    this.calcStale = false
    const series: Partial<Record<CalcId, Series[]>> = {}
    this._series = series
    const env = this.calcEnv()
    detachFlows(env.invalidate)  // 这一轮用到哪只再由量差 / 大单重新登记
    const b = this.bars
    if (!b.length) return
    for (const id of MAIN_IDS) if (mainOn(this.ind, id)) series[id] = Calc[id](b, this.params[id], env)
    // 降级收掉的副图不算（十六图里每格省下几个指标的整段重算）
    for (const id of this.subIds()) if (Calc[id]) series[id] = Calc[id](b, this.params[id], env)
  }
  /** 给指标的上下文（一个图一份，invalidate 是同一个函数，异步数据源拿它登记回调不会越攒越多） */
  calcEnv(): CalcEnv {
    if (this.env) return this.env
    const ch = this
    this.env = {
      get symbol() { return ch.meta.symbol },
      get iv() { return ch.iv },
      invalidate: () => { if (ch.dead) return; ch.recalc(); ch.legendDirty = true },
    }
    return this.env
  }
  /** 图例参数位置：没有参数的不占位 */
  paramCell(id: string): string {
    const t = paramText(id, this.params[id as IndicatorId])
    return t ? `<span class="ind-param">${t}</span>` : ''
  }
  recalcTail(): void { this.recalc() }

  // ---------------------------------------------------------- 几何
  resize(): void {
    const r = this.host.getBoundingClientRect()
    // 格子被藏起来（多图放大了别的格）：宽高是 0，画布与视口原样留着，还原时尺寸没变、不用重铺
    if ((!r.width || !r.height) && this.w > 0) return
    const w = Math.max(10, r.width), h = Math.max(10, r.height), dpr = window.devicePixelRatio || 1
    // 尺寸没变就不动画布（重设 canvas.width 会清空画面；拖分隔线时每帧都会问一遍）
    if (w === this.w && h === this.h && this.canvas.width === Math.round(w * dpr) && this.canvas.height === Math.round(h * dpr)) return
    this.w = w; this.h = h
    this.canvas.width = Math.round(this.w * dpr); this.canvas.height = Math.round(this.h * dpr)
    this.canvas.style.width = this.w + 'px'; this.canvas.style.height = this.h + 'px'
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    this.pr = dpr
    this.dirty = true
  }
  /** 设备像素比变了（窗口从 2K 外接屏拖到 Retina 笔记本屏上）：格子的 CSS 尺寸没变，ResizeObserver 不响，
   *  画布还按旧的像素比铺，整张图发虚到下一次改尺寸。盯住「当前像素比」这条媒体查询，一变就按新的重铺、再盯新的 */
  private watchDpr(): void {
    if (typeof matchMedia !== 'function' || typeof window === 'undefined') return
    const mq = matchMedia(`(resolution: ${window.devicePixelRatio || 1}dppx)`)
    mq.addEventListener('change', () => { if (this.dead) return; this.resize(); this.watchDpr() }, { once: true, signal: this.ac.signal })
  }
  axisW(): number {
    this.ctx.font = this.font
    const max = this.mainRange ? this.mainRange.max : (this.bars[this.bars.length - 1]?.h || 100)
    const base = this.mainRange ? this.compareBase() : null
    const s = base ? [this.mainRange!.max, this.mainRange!.min].map(v => comparePercentLabel(pctOf(v, base.price))).sort((a, b) => b.length - a.length)[0] : fmtAxis(max, this.meta.dec)
    return Math.max(56, Math.ceil(this.ctx.measureText(s).width) + 20)
  }
  plotW(): number { return this.w - this.aw }
  // 副图默认矮：每个副图取画布高的 11%，夹在 96–136 px（2K 屏上约 132 px，TradingView 桌面版的比例），
  // 主图拿剩下的全部。用户拖过分隔线后按比例记（paneR），窗口高度变了各格等比伸缩；
  // 主图不少于 40% 与 160 px、每个副图不少于 80 px（挤时 56）。分配规则见 panes.ts。
  // 多图降级时按格子高度只留前 deg.subs 个副图（用户排在前面的先留）。
  subIds(): SubId[] { return this.deg.subs >= this.ind.subs.length ? this.ind.subs : this.ind.subs.slice(0, this.deg.subs) }
  panes(): Pane[] {
    const subs = this.subIds()
    const H = this.h - AXIS_H
    const hs = paneHeights(H, subs, this.paneR)
    let y = 0
    const ids: PaneId[] = ['main', ...subs]
    return ids.map((id, i) => { const p: Pane = { id, y, h: hs[i] }; y += hs[i]; return p })
  }
  indexToX(i: number): number { return this.plotW() - (this.rightBar - i) * this.spacing }
  xToIndex(x: number): number { return this.rightBar - (this.plotW() - x) / this.spacing }
  indexAt(t: number): number { // 时间 → 连续下标（可以在数据两头外推）
    const b = this.bars, n = b.length
    if (!n) return 0
    if (t <= b[0].t) return (t - b[0].t) / this.iv
    if (t >= b[n - 1].t) return n - 1 + (t - b[n - 1].t) / this.iv
    let lo = 0, hi = n - 1
    while (hi - lo > 1) { const m = (lo + hi) >> 1; if (b[m].t <= t) lo = m; else hi = m }
    return lo + (t - b[lo].t) / Math.max(1, b[hi].t - b[lo].t)
  }
  timeAt(i: number): number {
    const b = this.bars, n = b.length
    if (!n) return 0
    const k = Math.round(i)
    if (k < 0) return b[0].t + k * this.iv
    if (k >= n) return b[n - 1].t + (k - n + 1) * this.iv
    return b[k].t
  }
  visible(): { from: number; to: number } {
    const n = this.lastIndex() + 1
    const from = Math.max(0, Math.floor(this.xToIndex(0)))
    const to = Math.min(n - 1, Math.ceil(this.rightBar))
    return { from, to }
  }
  tf(v: number): number { return this.logOn() ? Math.log(Math.max(v, 1e-12)) : v }
  itf(v: number): number { return this.logOn() ? Math.exp(v) : v }
  priceToY(p: number, pane: Pane, r: PriceRange): number { const a = this.tf(r.max), b = this.tf(r.min); return pane.y + 8 + (a - this.tf(p)) / (a - b) * (pane.h - 16) }
  yToPrice(y: number, pane: Pane, r: PriceRange): number { const a = this.tf(r.max), b = this.tf(r.min); return this.itf(a - (y - pane.y - 8) / (pane.h - 16) * (a - b)) }

  rangeMain(from: number, to: number): PriceRange {
    if (this.manual) return this.manual
    // 只认有限值；对数轴只认正数——布林下轨、VWAP −2σ 在暴跌的小币上会穿到 0 以下，
    // 拿它取对数整条价格轴变 NaN、主图全空
    const log = this.logOn(), ok = (v: number) => Number.isFinite(v) && (!log || v > 0)
    let lo = Infinity, hi = -Infinity
    for (let i = from; i <= to; i++) { const b = this.bars[i]; if (!b) continue; if (ok(b.l)) lo = Math.min(lo, b.l); if (ok(b.h)) hi = Math.max(hi, b.h) }
    for (const id of MAIN_IDS) {
      const ser = this.series[id]
      // 枢轴点的 R3 / S3 常常离价格很远，照 TradingView 不参与自动缩放
      if (!ser || this.hidden.has(id) || id === 'pivots') continue
      for (const s of ser) for (let i = from; i <= to; i++) { const v = s[i]; if (v != null && ok(v)) { lo = Math.min(lo, v); hi = Math.max(hi, v) } }
    }
    // 对比：各条线换算到主图价格空间里的位置也要装得下
    const base = this.compareBase()
    if (base) for (const cv of this.compareViews()) for (let i = from; i <= to; i++) {
      const pct = cv.at(i); if (pct == null) continue
      const v = priceOfPct(pct, base.price); if (ok(v)) { lo = Math.min(lo, v); hi = Math.max(hi, v) }
    }
    if (!(hi >= lo)) { lo = log ? 1 : 0; hi = log ? 10 : 1 }
    // 上下留白照图表设置「画布 · 边距」（TV 默认上 10%、下 8%）：可见最高价离窗格上沿 top%、最低价离下沿 bottom%；
    // 一字线（停牌、涨跌停、刚上线只有一个价）按价格的 2% 当跨度，负价（价差类）按绝对值，上下沿不颠倒
    const S = this.cs()
    return marginRange(lo, hi, S.marginTop, S.marginBottom, log)
  }
  rangeSub(id: SubId, from: number, to: number): PriceRange {
    if (id === 'rsi') return { min: 0, max: 100 }
    const fixed = subFixed(id); if (fixed) return fixed
    let lo = Infinity, hi = -Infinity
    for (const s of this.series[id] || []) for (let i = from; i <= to; i++) { const v = s[i]; if (v != null && Number.isFinite(v)) { lo = Math.min(lo, v); hi = Math.max(hi, v) } }
    if (!isFinite(lo)) return { min: 0, max: 1 }
    if (id === 'macd') { const m = Math.max(Math.abs(lo), Math.abs(hi)) || 1; return { min: -m * 1.1, max: m * 1.1 } }
    // 一条平线（持仓量 5B 一动不动）：按量级留边，留 ±1 的话刻度步长 0.5、整列都是同一个「5.00B」
    const pad = (hi - lo) * 0.1 || Math.abs(hi) * 0.1 || 1; return { min: lo - pad, max: hi + pad }
  }

  // ---------------------------------------------------------- 渲染
  /** 共用的那一帧里调：脏了才画，不在屏幕上的不画（回到屏幕上时 IntersectionObserver 再置脏） */
  frame(): void {
    if (this.dead || !this.onScreen) return
    if (this.dirty) { this.dirty = false; this.crossDirty = false; this.render() }
    else if (this.crossDirty) { this.crossDirty = false; this.render(true) }
  }
  /** 共用的那一帧里、所有格子的画布都画完之后调：写图例 DOM。
   *  画布与 DOM 交错着来的话，前一格刚改了图例文字（样式变脏），后一格一设 ctx.font 浏览器就得先把样式重算一遍——
   *  十六格联动十字线时每帧重算十几次；先画后写，一帧只重算一次 */
  frameDom(): void {
    if (this.dead || !this.onScreen) { this.paneLegendQ = null; return }
    if (this.legendDirty) { this.legendDirty = false; this.paneLegendQ = null; this.renderLegend() }
    else if (this.paneLegendQ) { const p = this.paneLegendQ; this.paneLegendQ = null; this.renderPaneLegends(p) }
  }
  /** 画完一帧要更新副图读数：在共用帧里就排到 frameDom，别处（同步重画）直接写 */
  private paneLegends(panes: Pane[]): void { if (inTick) this.paneLegendQ = panes; else this.renderPaneLegends(panes) }
  /** 把主画布上此刻的内容（十字线以下的静态层）存成底图；建不出离屏画布时返回 false，之后照常整帧重画 */
  private snapStatic(): boolean {
    const cv = this.canvas, w = cv.width, h = cv.height
    if (!w || !h) return false
    try {
      if (!this.statCv) {
        this.statCv = typeof OffscreenCanvas !== 'undefined' ? new OffscreenCanvas(w, h) : document.createElement('canvas')
        this.statCtx = this.statCv.getContext('2d') as CanvasRenderingContext2D | OffscreenCanvasRenderingContext2D | null
      }
      const sc = this.statCv, x = this.statCtx
      if (!x) return false
      if (sc.width !== w || sc.height !== h) { sc.width = w; sc.height = h } // 尺寸 / DPR 变了：底图跟着换
      x.setTransform(1, 0, 0, 1, 0, 0)
      x.globalCompositeOperation = 'copy'
      x.drawImage(cv, 0, 0)
      x.globalCompositeOperation = 'source-over'
      return true
    } catch { this.statCv = null; this.statCtx = null; return false }
  }
  /** 轻量一帧：底图贴回主画布，只重画十字线与副图读数。底图不可用（尺寸变了、还没整帧画过）时返回 false 走整帧 */
  private renderCross(): boolean {
    const panes = this._panes, cv = this.canvas
    if (!panes || !this.bars.length) return false
    if (!this.statOk) {
      if (!this.mainStatic) return false
      this.statOk = this.snapStatic() // 主画布上正好是没有十字线的静态层：直接拿它当底图
      if (!this.statOk) return false
    } else {
      const sc = this.statCv
      if (!sc || sc.width !== cv.width || sc.height !== cv.height) { this.statOk = false; return false }
      const c = this.ctx
      c.save()
      c.setTransform(1, 0, 0, 1, 0, 0)
      c.globalCompositeOperation = 'copy'
      c.drawImage(sc, 0, 0)
      c.restore()
    }
    this.drawCrosshair(panes)
    this.paneLegends(panes)
    this.mainStatic = this.cross == null && this.extCross == null
    return true
  }
  /** crossOnly：只有十字线动了——贴底图、画十字线与副图读数；没有可用的底图时整帧重画并顺手存底图。
   *  只在十字线要单独动的时候才存：存底图要把这一帧先光栅化出来，缩放 / 平移这类连续整帧重画时存了也是白存 */
  render(crossOnly = false): void {
    if (crossOnly && this.renderCross()) return
    this.statOk = false; this.mainStatic = false
    const c = this.ctx, C = this.colors
    this.aw = this.axisW()
    const W = this.w, H = this.h, PW = this.plotW()
    // 图例不许压到价格轴上：窄格子里（四图、板块预览）让它在绘图区宽度内折行
    const lw = `${Math.max(120, PW - 16)}px`; if (this.legendEl.style.maxWidth !== lw) this.legendEl.style.maxWidth = lw
    c.clearRect(0, 0, W, H)
    this.fillBg(W, H)
    if (!this.bars.length) { this.renderSkeleton(); return }
    const { from, to } = this.visible()
    const panes = this.panes()
    this._panes = panes
    const mainPane = panes[0]
    const mr = this.rangeMain(from, to); this.mainRange = mr
    this._ranges = { main: mr }
    for (const p of panes.slice(1)) this._ranges[p.id] = this.rangeSub(p.id as SubId, from, to)
    this.drawWatermark(mainPane, PW)

    // 网格 + 价格刻度
    c.font = this.font; c.textBaseline = 'middle'
    const S = this.cs(), gh = S.grid === 'both' || S.grid === 'horz', gv = S.grid === 'both' || S.grid === 'vert'
    c.setLineDash(dashOf('dotted')) // 网格照 TV 默认是点线
    for (const p of panes) {
      const r = this._ranges[p.id]
      const ticks = this.priceTicks(p, r)
      p.ticks = ticks
      c.strokeStyle = S.horzColor ?? C.grid; c.lineWidth = LINE.hair; c.beginPath()
      if (gh) for (const t of ticks) { const y = Math.round(this.priceToY(t, p, r)) + .5; c.moveTo(0, y); c.lineTo(PW, y) }
      c.stroke()
    }
    const tticks = this.timeTicks(from, to)
    c.strokeStyle = S.vertColor ?? C.grid; c.beginPath()
    if (gv) for (const t of tticks) { const x = Math.round(this.indexToX(t.i)) + .5; c.moveTo(x, 0); c.lineTo(x, H - AXIS_H) }
    c.stroke()
    c.setLineDash([])

    // 主图
    c.save(); c.beginPath(); c.rect(0, mainPane.y, PW, mainPane.h); c.clip()
    const geo = this.layers.length ? this.geometry() : null
    if (geo) for (const l of this.layers) if (l.back) { c.save(); l.back(c, geo); c.restore() }
    if (this.ind.vol && this.deg.vol && !this.hidden.has('vol')) this.drawVolume(mainPane, from, to)
    if (geo) for (const l of this.layers) if (l.under) { c.save(); l.under(c, geo); c.restore() }
    if (this.walls && !this.hidden.has('walls')) this.drawWalls(mainPane, mr, from, to)
    if (this.markers) this.drawTradeSpan(mainPane, mr)
    if (this.ind.keys && !this.hidden.has('keys')) drawKeyLevels(this, mainPane, mr, from, to)
    if (!this.footprint?.(mainPane, mr, from, to)) this.drawCandles(mainPane, mr, from, to)
    for (const id of ['boll', 'ema', 'ma'] as MainId[]) if (this.series[id] && !this.hidden.has(id)) this.drawLines(id, mainPane, mr, from, to)
    drawExtraMain(this, mainPane, mr, from, to)
    drawMoreMain(this, mainPane, mr, from, to)
    if (this.compareOn()) this.drawCompare(mainPane, mr, from, to)
    this.drawRefLines(mainPane, mr)
    this.drawLastLine(mainPane, mr)
    this.drawAlertLines(mainPane, mr)
    this.drawAlertSignals(mainPane, mr)
    this.textRects.length = 0
    this.drawDrawings(mainPane, mr)
    if (this.markers) this.drawMarkers(mainPane, mr)
    if (geo) for (const l of this.layers) if (l.over) { c.save(); l.over(c, geo); c.restore() }
    c.restore()

    // 副图
    for (const p of panes.slice(1)) {
      c.save(); c.beginPath(); c.rect(0, p.y, PW, p.h); c.clip()
      this.drawSub(p, this._ranges[p.id], from, to)
      c.restore()
    }

    // 分隔线与轴
    c.strokeStyle = C.sep; c.lineWidth = LINE.hair; c.beginPath() // 窗格分隔线（TV separatorColor）
    for (const p of panes.slice(1)) { c.moveTo(0, p.y + .5); c.lineTo(W, p.y + .5) }
    c.stroke()
    c.strokeStyle = C.scaleLine; c.beginPath() // 价格轴 / 时间轴的轴线（TV 默认透明，图表设置里能给色）
    c.moveTo(PW + .5, 0); c.lineTo(PW + .5, H - AXIS_H)
    c.moveTo(0, H - AXIS_H + .5); c.lineTo(W, H - AXIS_H + .5)
    c.stroke()
    // 悬停 / 正在拖的那条窗格分隔线：强调色
    const hot = this.drag?.kind === 'pan' && this.drag.region.startsWith('sep:') ? this.drag.region.slice(4) : this.hoverSep
    const hp = hot ? panes.find(p => p.id === hot) : null
    if (hp) { c.strokeStyle = C.accent; c.beginPath(); c.moveTo(0, hp.y + .5); c.lineTo(W, hp.y + .5); c.stroke() }

    c.fillStyle = C.text; c.textAlign = 'left'
    for (const p of panes) {
      const r = this._ranges[p.id]
      for (const t of p.ticks ?? []) {
        const y = this.priceToY(t, p, r)
        if (y < p.y + 8 || y > p.y + p.h - 6) continue
        c.fillText(p.id === 'main' ? this.mainAxisText(t, true) : this.subFmt(p.id, t), PW + 8, y)
      }
    }
    c.textAlign = 'center'
    for (const t of tticks) {
      const x = this.indexToX(t.i)
      if (x < 20 || x > PW - 20) continue
      c.font = t.bold ? `600 ${this.font}` : this.font
      c.fillText(t.label, x, H - AXIS_H / 2)
    }
    c.font = this.font

    this.drawPriceLabels(mainPane, mr)
    this.drawSubLabels(panes)
    // 十字线以下到此画完：十字线在的话存一张底图（之后十字线再动只贴底图重画十字线），不在就记下主画布本身就是底图
    const crossOn = this.cross != null || this.extCross != null
    this.statOk = crossOn && crossOnly && this.snapStatic()
    this.mainStatic = !crossOn
    this.drawCrosshair(panes)
    this.paneLegends(panes)
    if (geo) for (const l of this.layers) l.after?.(geo)
  }

  /** 还没有 K 线：画网格、两条轴和轴上的占位短条（骨架），不留一块白板；标题与「载入中」在图例里 */
  private renderSkeleton(): void {
    const c = this.ctx, C = this.colors, W = this.w, H = this.h, PW = this.plotW(), bottom = H - AXIS_H
    c.strokeStyle = C.grid; c.lineWidth = LINE.hair; c.beginPath()
    const rows = Math.max(2, Math.floor(bottom / 56)), cols = Math.max(2, Math.floor(PW / 120))
    for (let k = 1; k < rows; k++) { const y = Math.round(bottom * k / rows) + .5; c.moveTo(0, y); c.lineTo(PW, y) }
    for (let k = 1; k < cols; k++) { const x = Math.round(PW * k / cols) + .5; c.moveTo(x, 0); c.lineTo(x, bottom) }
    c.stroke()
    c.strokeStyle = C.scaleLine; c.beginPath()
    c.moveTo(PW + .5, 0); c.lineTo(PW + .5, bottom)
    c.moveTo(0, bottom + .5); c.lineTo(W, bottom + .5)
    c.stroke()
    // 轴上的占位：价格轴每格一条、时间轴每列一条，淡色圆角短条
    c.save(); c.globalAlpha = .5; c.fillStyle = C.grid
    const bw = Math.max(20, Math.min(this.aw - 20, 40))
    for (let k = 1; k < rows; k++) { roundRect(c, PW + 8, Math.round(bottom * k / rows) - 4, bw, 8, 4); c.fill() }
    for (let k = 1; k < cols; k++) { roundRect(c, Math.round(PW * k / cols) - 16, bottom + AXIS_H / 2 - 4, 32, 8, 4); c.fill() }
    c.restore()
  }

  priceTicks(p: Pane, r: PriceRange): number[] {
    const n = Math.max(2, Math.floor(p.h / 56))
    if (!(r.max > r.min) || !isFinite(r.min) || !isFinite(r.max)) return []
    // 主图刻度不细过品种的价格精度：细过了一列刻度会印出好几个一样的价（BTC 一位小数，步长 0.05 → 两个「60000.0」）
    const floor = p.id === 'main' && this.meta.dec >= 0 ? Math.pow(10, -this.meta.dec) : 0
    const round = (v: number, st: number) => +(Math.round(v / st) * st).toFixed(Math.max(0, Math.min(20, 1 - Math.floor(Math.log10(st)))))
    if (p.id === 'main' && this.compareOn()) {
      const base = this.compareBase()
      if (base) { const t = percentTicks(r.min, r.max, base.price, n, niceStep); this.cmpStep = t.step; return t.prices }
    }
    if (this.logOn() && p.id === 'main') {
      if (!(r.min > 0)) return []
      const out: number[] = [], a = Math.log(r.min), b = Math.log(r.max)
      for (let i = 1; i <= n; i++) {
        const v = Math.exp(a + (b - a) * i / (n + 1)), t = round(v, Math.max(niceStep(v / 20), floor))
        if (t > r.min && t < r.max && out[out.length - 1] !== t) out.push(t)
      }
      return out
    }
    const step = Math.max(niceStep((r.max - r.min) / n), floor)
    if (!(step > 0) || !isFinite(step)) return []
    // 按整数倍数走：v += step 在步长小于价格的浮点间隔时永远加不上去，循环停不下来
    const out: number[] = [], k0 = Math.ceil(r.min / step), k1 = Math.floor(r.max / step)
    for (let k = k0; k <= k1 && out.length < 64; k++) out.push(round(k * step, step))
    return out
  }
  subFmt(id: string, v: number): string { return fmtSub(id, v, this.meta.dec) }

  /** 时间轴刻度：规则在 timeAxis.ts 的纯函数里（from / to 参数沿用原型签名，不使用） */
  timeTicks(_from?: number, _to?: number): TimeTick[] {
    if (!this.bars.length) return []
    const lo = Math.max(0, Math.floor(this.xToIndex(0))), hi = Math.ceil(this.rightBar)
    return timeTicks(i => this.timeAt(i), lo, hi, this.spacing, this.iv, TIME_TICK_MIN_PX, i => this.indexToX(i))
  }

  /** K 线的横向几何一律按物理像素取整（TV 的 pixelRatio 做法），返回值仍是 CSS 像素（画布已按 pr 缩放）：
   *  Retina 上一根能挪半个 CSS 像素、宽度一次只变一个物理像素——按 CSS 像素取整时缩放中每根都是 2 个物理像素一跳，整屏在爬 */
  snapX(x: number): number { const k = this.pr; return Math.round(x * k) / k }
  /** 影线：1 个物理像素向上凑到 CSS 像素（TV wickWidth = floor(pixelRatio)，最密时不超过间距），任何间距都一样粗——
   *  原来间距过 20 跳成 2 px，放大过这一档时整屏影线一起变粗、实体同时换奇偶，就是「闪一下」 */
  wickW(): number { const k = this.pr; return Math.max(1, Math.min(Math.floor(k), Math.floor(this.spacing * k))) / k }
  candleW(): number { return candleBodyPx(this.spacing, this.pr) / this.pr }
  /** 成交量柱宽（CSS 像素）：TV 直方图——间距按物理像素取整再减 1，相邻两根留一条 1 物理像素的缝 */
  volW(): number { const k = this.pr; return Math.max(1, Math.round(this.spacing * k) - 1) / k }
  /** 成交量涨跌色：涨跌色还是 TV 默认（绿 #089981 / 红 #F23645）时换成 TV 成交量自己那两色，改过颜色就跟着蜡烛走 */
  volColor(up: boolean): string {
    const c = up ? this.colors.up : this.colors.down, u = c.toUpperCase()
    return u === '#089981' ? TV_VOL_UP : u === '#F23645' ? TV_VOL_DOWN : c
  }
  /** K 线：实体 / 边框 / 影线各自开关与涨跌色（图表设置「商品」；颜色没改过就跟涨跌色）。
   *  边框和实体同色（默认）时不另描——实体本身就是边，和原来一样两遍填充 */
  drawCandles(p: Pane, r: PriceRange, from: number, to: number): void {
    if (this.spacing * this.pr < 1) { this.drawColumns(p, r, from, to); return }
    const c = this.ctx, C = this.colors, S = this.cs(), k = this.pr, bw = this.candleW(), wick = this.wickW()
    const half = Math.floor(bw * k / 2) / k, wh = (Math.round(wick * k) >> 1) / k
    const bodyOn = S.body && (bw > wick || !S.wick), borderOn = S.border && bw * k >= 3
    const isUp = (i: number, b: Bar): boolean => { const q = S.prevCloseColor ? this.bars[i - 1] : undefined; return q ? b.c >= q.c : b.c >= b.o }
    for (const pass of [0, 1]) {
      const base = pass ? C.up : C.down
      const bodyCol = (pass ? S.bodyUp : S.bodyDown) ?? base, borderCol = (pass ? S.borderUp : S.borderDown) ?? base, wickCol = (pass ? S.wickUp : S.wickDown) ?? base
      const stroke = borderOn && (!bodyOn || borderCol !== bodyCol)
      for (const part of [0, 1, 2]) { // 0 影线 · 1 实体 · 2 边框
        if (part === 0 ? !S.wick : part === 1 ? !bodyOn : !stroke) continue
        if (part === 2) { c.strokeStyle = borderCol; c.lineWidth = 1 } else c.fillStyle = part ? bodyCol : wickCol
        c.beginPath()
        for (let i = from; i <= to; i++) {
          const b = this.bars[i]; if (!b) continue
          if ((pass === 1) !== isUp(i, b)) continue
          const x = this.snapX(this.indexToX(i))
          if (part === 0) {
            const yh = Math.round(this.priceToY(b.h, p, r)), yl = Math.round(this.priceToY(b.l, p, r))
            if (bodyOn || bw <= wick) { c.rect(x - wh, yh, wick, Math.max(1, yl - yh)); continue }
            // 空心（实体关了）：影线只画实体上下两段，不穿过实体
            const top = Math.round(this.priceToY(Math.max(b.o, b.c), p, r)), bot = Math.round(this.priceToY(Math.min(b.o, b.c), p, r))
            if (top > yh) c.rect(x - wh, yh, wick, top - yh)
            if (yl > bot) c.rect(x - wh, bot, wick, yl - bot)
            continue
          }
          const yo = this.priceToY(b.o, p, r), yc = this.priceToY(b.c, p, r)
          const top = Math.round(Math.min(yo, yc)), bot = Math.round(Math.max(yo, yc))
          if (part === 1) c.rect(x - half, top, bw, Math.max(1, bot - top))
          else c.rect(x - half + .5, top + .5, bw - 1, Math.max(0, bot - top - 1))
        }
        if (part === 2) c.stroke(); else c.fill()
      }
    }
  }
  /** 间距不到 1 px（最密 0.5）时同一像素列上会落好几根：按列并成一根（首根开、末根收、最高、最低、量相加）。
   *  不并的话几根叠在一列上，涨色盖住跌色、影线糊成一片；TV 也是间距小于 1 个物理像素时并柱（conflation） */
  columns(from: number, to: number): { x: number[]; b: Bar[] } {
    const xs: number[] = [], bs: Bar[] = []
    for (let i = Math.max(0, from); i <= to; i++) {
      const b = this.bars[i]; if (!b) continue
      const x = this.snapX(this.indexToX(i)), k = bs.length - 1
      if (k >= 0 && xs[k] === x) {
        const m = bs[k]; m.c = b.c; if (b.h > m.h) m.h = b.h; if (b.l < m.l) m.l = b.l
        m.v = (Number.isFinite(m.v) && m.v > 0 ? m.v : 0) + (Number.isFinite(b.v) && b.v > 0 ? b.v : 0)
      } else { xs.push(x); bs.push({ t: b.t, o: b.o, h: b.h, l: b.l, c: b.c, v: b.v }) }
    }
    return { x: xs, b: bs }
  }
  /** 最密时的 K 线：每列一根 1 px 细线（最高到最低），按并后的开收定涨跌色 */
  private drawColumns(p: Pane, r: PriceRange, from: number, to: number): void {
    const c = this.ctx, C = this.colors, S = this.cs(), { x: xs, b: bs } = this.columns(from, to)
    for (const pass of [0, 1]) {
      const base = pass ? C.up : C.down
      c.fillStyle = (S.body ? (pass ? S.bodyUp : S.bodyDown) : (pass ? S.wickUp : S.wickDown)) ?? base
      c.beginPath()
      for (let k = 0; k < bs.length; k++) {
        const b = bs[k], up = S.prevCloseColor && k > 0 ? b.c >= bs[k - 1].c : b.c >= b.o
        if ((pass === 1) !== up) continue
        const yh = Math.round(this.priceToY(b.h, p, r)), yl = Math.round(this.priceToY(b.l, p, r))
        c.rect(xs[k], yh, 1 / this.pr, Math.max(1, yl - yh))
      }
      c.fill()
    }
  }
  drawVolume(p: Pane, from: number, to: number): void {
    if (this.spacing * this.pr < 1) { this.drawVolumeColumns(p, from, to); return }
    const c = this.ctx, k = this.pr, bw = this.volW()
    let mx = 0
    // 坏量（NaN / Infinity / 负数）不画也不参与取顶：一根 Infinity 会把整屏的量柱压成 0 高
    const vOk = (v: number | undefined): v is number => v != null && Number.isFinite(v) && v > 0
    for (let i = from; i <= to; i++) { const v = this.bars[i]?.v; if (vOk(v)) mx = Math.max(mx, v) }
    if (!mx) return
    const h = p.h * VOL_H, base = p.y + p.h
    const half = Math.floor(bw * k / 2) / k
    for (const pass of [0, 1]) {
      c.fillStyle = hexA(this.volColor(pass === 1), VOL_ALPHA)
      c.beginPath()
      for (let i = from; i <= to; i++) {
        const b = this.bars[i]; if (!b || !vOk(b.v)) continue
        if ((b.c >= b.o) !== (pass === 1)) continue
        const x = this.snapX(this.indexToX(i)), vh = Math.max(1, b.v / mx * h)
        c.rect(x - half, Math.round(base - vh), bw, Math.round(vh))
      }
      c.fill()
    }
  }
  /** 最密时的成交量：按列相加，一列一根 1 px */
  private drawVolumeColumns(p: Pane, from: number, to: number): void {
    const c = this.ctx, { x: xs, b: bs } = this.columns(from, to)
    let mx = 0
    for (const b of bs) if (Number.isFinite(b.v) && b.v > mx) mx = b.v
    if (!mx) return
    const h = p.h * VOL_H, base = p.y + p.h
    for (const pass of [0, 1]) {
      c.fillStyle = hexA(this.volColor(pass === 1), VOL_ALPHA)
      c.beginPath()
      for (let k = 0; k < bs.length; k++) {
        const b = bs[k]
        if (!(Number.isFinite(b.v) && b.v > 0) || (b.c >= b.o) !== (pass === 1)) continue
        const vh = Math.max(1, b.v / mx * h)
        c.rect(xs[k], Math.round(base - vh), 1 / this.pr, Math.round(vh))
      }
      c.fill()
    }
  }
  drawLines(id: MainId, p: Pane, r: PriceRange, from: number, to: number): void {
    const c = this.ctx, cols = CATALOG[id].colors ?? [], ser = this.series[id]
    if (!ser) return
    if (id === 'boll') {
      c.fillStyle = 'rgba(33,150,243,0.05)'; c.beginPath() // TV 布林 Background：color.rgb(33, 150, 243, 95)
      let started = false
      for (let i = from; i <= to; i++) { const v = ser[1][i]; if (v == null) continue; const x = this.indexToX(i), y = this.priceToY(v, p, r); if (started) c.lineTo(x, y); else { c.moveTo(x, y); started = true } }
      for (let i = to; i >= from; i--) { const v = ser[2][i]; if (v == null) continue; c.lineTo(this.indexToX(i), this.priceToY(v, p, r)) }
      c.fill()
    }
    c.lineJoin = 'round'; c.lineCap = 'round'
    ser.forEach((s, k) => {
      c.lineWidth = LINE.plot
      c.strokeStyle = cols[k % cols.length]; c.beginPath()
      let started = false
      for (let i = Math.max(0, from - 1); i <= to; i++) {
        const v = s[i]; if (v == null) { started = false; continue }
        const x = this.indexToX(i), y = this.priceToY(v, p, r)
        if (started) c.lineTo(x, y); else { c.moveTo(x, y); started = true }
      }
      c.stroke()
    })
  }
  /** 涨色是不是绿的（绿涨红跌）：MACD 四色柱照 TradingView 的青绿 / 红两组，红涨绿跌时两组对调 */
  greenUp(): boolean {
    const m = /^#?([0-9a-f]{6})$/i.exec((this.colors.up || '').trim())
    if (!m) return true
    const n = parseInt(m[1], 16)
    return (n >> 8 & 255) >= (n >> 16 & 255)
  }
  /** TradingView MACD 柱的四色（STD;MACD 的 hColor）：[零上变长, 零上变短, 零下变长, 零下变短] */
  hist4Colors(): [string, string, string, string] {
    const g: [string, string] = ['#26A69A', '#B2DFDB'], rd: [string, string] = ['#FF5252', '#FFCDD2']
    const [pos, neg] = this.greenUp() ? [g, rd] : [rd, g]
    return [pos[0], pos[1], neg[0], neg[1]]
  }
  /** 副图柱子一根的颜色：零轴柱看正负（涨跌色）、升降柱看比上一根（TV AO 的 #009688 / #F44336）、四色柱照 TV MACD */
  histColor(st: SubStyle, v: number, prev: number, h4 = this.hist4Colors()): string {
    if (st === 'hist') return v >= 0 ? this.colors.up : this.colors.down
    if (st === 'histTrend') { const [u, d] = this.greenUp() ? ['#009688', '#F44336'] : ['#F44336', '#009688']; return v >= prev ? u : d }
    // TV：hist >= 0 ? (hist > hist[1] ? 深绿 : 浅绿) : (hist > hist[1] ? 浅红 : 深红)
    return v >= 0 ? (v > prev ? h4[0] : h4[1]) : (v > prev ? h4[3] : h4[2])
  }
  /** 副图参考线：照 TV hline——#787B86（中线 50% 透明）、1 px、style_dashed 用 TV 的 [5, 6] 虚线（威廉 −50 是点线） */
  private levelLines(p: Pane, r: PriceRange, lines: readonly LevelLine[]): void {
    const c = this.ctx, PW = this.plotW()
    c.lineWidth = LINE.hair
    for (const l of lines) {
      const yy = Math.round(this.priceToY(l.v, p, r)) + .5
      c.setLineDash(dashOf(l.dash, LINE.hair)); c.strokeStyle = l.color; c.beginPath(); c.moveTo(0, yy); c.lineTo(PW, yy); c.stroke()
    }
    c.setLineDash([])
  }
  /** 副图：参考带底色 → 参考线 → 柱 / 面 → 线 → 点。画法照 TradingView 各指标默认样式 */
  drawSub(p: Pane, r: PriceRange, from: number, to: number): void {
    const c = this.ctx, C = this.colors, id = p.id as SubId, ser = this.series[id], cols = CATALOG[id].colors ?? []
    if (!ser || this.hidden.has(id)) return
    const y = (v: number) => this.priceToY(v, p, r), PW = this.plotW()
    // 上下轨之间的底色（TV 的 hline 间 fill：RSI 等紫 10%、随机等 #2196F3 10%），夹在窗格里
    for (const f of subBandFills(id)) {
      const ya = clamp(y(f.a), p.y, p.y + p.h), yb = clamp(y(f.b), p.y, p.y + p.h)
      if (ya !== yb) { c.fillStyle = f.color; c.fillRect(0, Math.min(ya, yb), PW, Math.abs(yb - ya)) }
    }
    drawSubLevels(this, p, r, id)
    this.levelLines(p, r, subLevelLines(id))
    const styles: readonly SubStyle[] = id === 'macd' ? ['line', 'line', 'hist4'] : subStyles(id) ?? []
    const style = (k: number): SubStyle => styles[k] ?? 'line'
    const bw = this.candleW(), half = Math.floor(bw * this.pr / 2) / this.pr, y0 = y(0)
    const bar = (i: number, v: number) => { const x = this.snapX(this.indexToX(i)), yy = y(v); c.fillRect(x - half, Math.round(Math.min(y0, yy)), Math.max(1 / this.pr, bw), Math.max(1, Math.round(Math.abs(yy - y0)))) }
    const h4 = this.hist4Colors()
    ser.forEach((s, k) => {
      const st = style(k), col = cols[k % cols.length] || C.text2
      if (st === 'hist' || st === 'hist4' || st === 'histTrend') {
        for (let i = Math.max(0, from); i <= to; i++) {
          const v = s[i]; if (v == null) continue
          c.fillStyle = this.histColor(st, v, s[i - 1] ?? v, h4)
          bar(i, v)
        }
      } else if (st === 'area') {
        c.fillStyle = hexA(col, 0.15)
        let run: [number, number][] = []
        const flush = () => {
          if (run.length > 1) { c.beginPath(); c.moveTo(run[0][0], y0); for (const [x, yy] of run) c.lineTo(x, yy); c.lineTo(run[run.length - 1][0], y0); c.closePath(); c.fill() }
          run = []
        }
        for (let i = Math.max(0, from - 1); i <= to; i++) { const v = s[i]; if (v == null) { flush(); continue } run.push([this.indexToX(i), y(v)]) }
        flush()
      }
    })
    ser.forEach((s, k) => { const st = style(k); if (st === 'line' || st === 'area') this.polyline(s, p, r, from, to, cols[k % cols.length] || C.text2) })
    ser.forEach((s, k) => {
      if (style(k) !== 'dots') return
      const rad = Math.max(1.25, Math.min(2.5, bw / 4))
      c.fillStyle = cols[k % cols.length] || C.text2; c.beginPath()
      for (let i = Math.max(0, from); i <= to; i++) { const v = s[i]; if (v == null) continue; const x = this.indexToX(i), yy = y(v); c.moveTo(x + rad, yy); c.arc(x, yy, rad, 0, Math.PI * 2) }
      c.fill()
    })
  }
  polyline(s: Series, p: Pane, r: PriceRange, from: number, to: number, col: string): void {
    const c = this.ctx; c.strokeStyle = col; c.lineWidth = LINE.plot; c.lineJoin = 'round'; c.lineCap = 'round'; c.beginPath(); let st = false
    for (let i = Math.max(0, from - 1); i <= to; i++) { const v = s[i]; if (v == null) { st = false; continue } const x = this.indexToX(i), y = this.priceToY(v, p, r); if (st) c.lineTo(x, y); else { c.moveTo(x, y); st = true } }
    c.stroke()
  }
  lastBar(): Bar | undefined { return this.bars[this.lastIndex()] }
  /** 对比线：每只一条，缺根与主图跳空处断开 */
  drawCompare(p: Pane, r: PriceRange, from: number, to: number): void {
    const base = this.compareBase(); if (!base) return
    const c = this.ctx, times = (i: number) => this.bars[i]?.t ?? 0, hi = Math.min(to + 1, this.lastIndex())
    c.lineWidth = LINE.compare; c.lineJoin = 'round'; c.lineCap = 'round'
    for (const cv of this.compareViews()) {
      c.strokeStyle = cv.color; c.beginPath()
      for (const seg of compareSegments(times, this.iv, Math.max(from - 1, 0), hi, cv.at)) {
        seg.forEach(([i, v], k) => { const x = this.indexToX(i), y = this.priceToY(priceOfPct(v, base.price), p, r); if (k) c.lineTo(x, y); else c.moveTo(x, y) })
        if (seg.length === 1) { const [i, v] = seg[0]; const x = this.indexToX(i), y = this.priceToY(priceOfPct(v, base.price), p, r); c.moveTo(x - 1.5, y); c.lineTo(x + 1.5, y) }
      }
      c.stroke()
    }
  }
  drawLastLine(p: Pane, r: PriceRange): void {
    const S = this.cs(); if (!S.lastLine) return
    const b = this.lastBar(); if (!b) return
    const c = this.ctx, y = Math.round(this.priceToY(b.c, p, r)) + .5
    c.strokeStyle = this.lastColor(b)
    c.setLineDash(dashOf(S.lastLineStyle)); c.lineWidth = LINE.hair; c.beginPath(); c.moveTo(0, y); c.lineTo(this.plotW(), y); c.stroke(); c.setLineDash([])
  }
  drawAlertLines(p: Pane, r: PriceRange): void {
    const c = this.ctx
    for (const a of this.alertsShown()) {
      const y = Math.round(this.priceToY(a.price, p, r)) + .5
      if (y < p.y || y > p.y + p.h) continue
      c.strokeStyle = this.colors.alert; c.setLineDash([6, 4]); c.lineWidth = LINE.hair; c.beginPath(); c.moveTo(0, y); c.lineTo(this.plotW(), y); c.stroke(); c.setLineDash([])
    }
  }
  /** 此刻真画在图上的提醒线：画线整层藏着就全画；否则只画挂的那条线不在了的。对比态（百分比轴）上价格坐标不成立，不画 */
  signalsShown(): AlertSignal[] {
    if (!this.alertSignals.length || this.compareOn()) return []
    if (this.drawingsHidden) return this.alertSignals.slice()
    const ids = new Set(this.drawings.map(d => d.id))
    return this.alertSignals.filter(a => a.drawingID == null || !ids.has(a.drawingID))
  }
  /** 一条提醒线在图区里的折线（按 6px 采样：对数轴上直线不再是直线） */
  signalPath(line: AlertSignal['lines'][number], p: Pane, r: PriceRange): XY[] {
    const ts = line.points.map(q => q.t); if (!ts.length) return []
    const PW = this.plotW(), tx = (t: number) => this.indexToX(this.indexAt(t))
    const x0 = line.extendLeft ? 0 : Math.max(0, tx(Math.min(...ts))), x1 = line.extendRight ? PW : Math.min(PW, tx(Math.max(...ts)))
    if (!isFinite(x0) || !isFinite(x1) || x1 < x0) return []
    const out: XY[] = []
    for (let x = x0; ; x = Math.min(x1, x + 6)) {
      const v = linePriceAt(line, this.timeOfIndex(this.xToIndex(x)))
      if (v != null && isFinite(v)) { const y = this.priceToY(v, p, r); if (isFinite(y)) out.push({ x, y }) }
      if (x >= x1) break
    }
    return out
  }
  drawAlertSignals(p: Pane, r: PriceRange): void {
    const shown = this.signalsShown(); if (!shown.length) return
    const c = this.ctx, col = this.colors.alert
    c.save()
    c.strokeStyle = col; c.lineWidth = LINE.hair; c.setLineDash([6, 4])
    for (const a of shown) for (const l of a.lines) {
      const path = this.signalPath(l, p, r); if (path.length < 2) continue
      c.beginPath(); c.moveTo(path[0].x, path[0].y); for (let k = 1; k < path.length; k++) c.lineTo(path[k].x, path[k].y); c.stroke()
    }
    c.setLineDash([])
    // 右端一枚铃铛：两端无限延的贴图区右边，有头有尾的停在最后一个点上
    for (const a of shown) {
      const path = a.lines[0] ? this.signalPath(a.lines[0], p, r) : []
      const e = path[path.length - 1]; if (!e) continue
      const x = Math.min(e.x, this.plotW() - 12) , y = path.length > 1 ? this.priceToY(linePriceAt(a.lines[0], this.timeOfIndex(this.xToIndex(x))) ?? NaN, p, r) : e.y
      if (!isFinite(y) || y < p.y + 6 || y > p.y + p.h - 6) continue
      bellGlyph(c, x, y, col)
    }
    c.restore()
  }
  /** 图上要画的提醒线：拖动中的那条换成手上的价位，新建中的草稿也算一条 */
  alertsShown(): AlertLine[] {
    const d = this.drag
    if (!d || d.kind !== 'alert') return this.alerts
    if (!d.line) return [...this.alerts, { price: d.price }]
    return this.alerts.map(a => a === d.line ? { ...a, price: d.price } : a)
  }
  /** 主图上 y 附近（±tol px）的提醒线 */
  alertNear(y: number, tol: number): AlertLine | null {
    const p = this._panes?.[0], r = this._ranges.main
    if (!p || !r) return null
    let best: AlertLine | null = null, bd = tol
    for (const a of this.alerts) { const dy = Math.abs(this.priceToY(a.price, p, r) - y); if (dy <= bd) { bd = dy; best = a } }
    return best
  }
  drawPriceLabels(p: Pane, r: PriceRange): void {
    const c = this.ctx, C = this.colors, PW = this.plotW()
    const label = (y: number, text: string, bg: string, fg: string) => {
      const h = 20
      const top = clamp(y - 10, p.y, p.y + p.h - h)
      c.fillStyle = bg; roundRect(c, PW + 1, top, this.aw - 2, h, 3); c.fill()
      c.fillStyle = fg; c.textAlign = 'left'; c.font = this.font // TV 轴上标签不加粗
      c.fillText(text, PW + 8, top + 10)
      c.font = this.font
    }
    if (this.ind.keys && !this.hidden.has('keys')) drawKeyAxis(this, p, r)
    for (const a of this.alertsShown()) {
      const y = this.priceToY(a.price, p, r); if (y < p.y || y > p.y + p.h) continue
      label(y, fmtAxis(a.price, this.meta.dec), C.alert, '#fff')
    }
    // 价格轴上的「+」：点下去拖到位松手就建一条提醒
    if (this.axisHoverY != null && !this.drag && this.axisHoverY >= p.y && this.axisHoverY < p.y + p.h) {
      const y = this.axisHoverY, top = clamp(y - 9, p.y, p.y + p.h - 18)
      c.fillStyle = C.alert; roundRect(c, PW + 2, top, ALERT_CHIP_W - 4, 18, 4); c.fill()
      c.strokeStyle = '#fff'; c.lineWidth = 1.5; c.beginPath()
      const cx = PW + 2 + (ALERT_CHIP_W - 4) / 2, cy = top + 9
      c.moveTo(cx - 4, cy); c.lineTo(cx + 4, cy); c.moveTo(cx, cy - 4); c.lineTo(cx, cy + 4); c.stroke()
      c.fillStyle = C.text; c.textAlign = 'left'; c.font = this.font
      c.fillText(fmtAxis(this.yToPrice(y, p, r), this.meta.dec), PW + ALERT_CHIP_W + 2, top + 9)
    }
    // 对比线的最新值：各自的颜色，压在主图最新价下面
    const cb = this.compareBase()
    if (cb) for (const cv of this.compareViews()) {
      const v = cv.at(this.lastIndex()); if (v == null) continue
      const y = this.priceToY(priceOfPct(v, cb.price), p, r); if (y < p.y || y > p.y + p.h) continue
      label(y, comparePercentLabel(v), cv.color, '#fff')
    }
    this.drawSettingLabels(p, r)
    const b = this.lastBar(); if (!b || !this.cs().lastLabel) return
    const y = this.priceToY(b.c, p, r)
    label(y, this.mainAxisText(b.c), this.lastColor(b), '#fff')
    // 十字线标签画在最上层（drawCrosshair）
  }
  drawCrosshair(panes: Pane[]): void {
    const c = this.ctx, C = this.colors, PW = this.plotW(), H = this.h
    let x: number | null = null, idx = 0
    if (this.cross) { idx = Math.round(this.xToIndex(this.cross.x)); x = this.indexToX(idx) }
    else if (this.extCross != null) { idx = Math.round(this.indexAt(this.extCross)); x = this.indexToX(idx) }
    if (x == null || x < 0 || x > PW) return
    const S = this.cs()
    c.strokeStyle = C.cross; c.lineWidth = S.crossWidth; c.setLineDash(dashOf(S.crossStyle, S.crossWidth))
    c.beginPath(); c.moveTo(Math.round(x) + .5, 0); c.lineTo(Math.round(x) + .5, H - AXIS_H)
    let y = 0, pane: Pane | undefined
    if (this.cross) {
      const cy = this.cross.y
      // 横线一律跟着鼠标走，不吸开高低收（磁吸只管画线落点，见 toTP）；读数与「在这个价建提醒」用的是同一个 y
      y = cy
      pane = panes.find(p => y >= p.y && y < p.y + p.h)
      if (pane) { c.moveTo(0, Math.round(y) + .5); c.lineTo(PW, Math.round(y) + .5) }
    }
    c.stroke(); c.setLineDash([])
    // 轴上标签
    c.font = this.font; c.textBaseline = 'middle'
    const tl = crossText(this.timeAt(idx), this.iv, S)
    const tw = c.measureText(tl).width + 16
    c.fillStyle = C.crossLabel; roundRect(c, clamp(x - tw / 2, 0, PW - tw), H - AXIS_H + 2, tw, AXIS_H - 4, 3); c.fill()
    c.fillStyle = '#fff'; c.textAlign = 'center'; c.fillText(tl, clamp(x, tw / 2, PW - tw / 2), H - AXIS_H / 2)
    if (pane) {
      const r = this._ranges[pane.id], v = this.yToPrice(y, pane, r)
      const s = pane.id === 'main' ? this.mainAxisText(v) : this.subFmt(pane.id, v)
      c.fillStyle = C.crossLabel; roundRect(c, PW + 1, y - 10, this.aw - 2, 20, 3); c.fill()
      c.fillStyle = '#fff'; c.textAlign = 'left'; c.fillText(s, PW + 8, y)
    }
  }

  // ---- 订单流：大单画成垫在蜡烛下面的细线，签在右端
  drawWalls(p: Pane, r: PriceRange, _from: number, _to: number): void {
    const c = this.ctx, PW = this.plotW()
    if (!this.walls) return
    c.font = `500 11px ${this.fontFamily()}`
    for (const w of this.walls) {
      const y0 = this.priceToY(w.price, p, r)
      if (y0 < p.y || y0 > p.y + p.h) continue
      const x0 = Math.max(0, this.indexToX(this.indexAt(w.from)))
      const x1 = w.to ? Math.min(PW, this.indexToX(this.indexAt(w.to))) : PW
      if (x1 < 0 || x0 > PW) continue
      const col = w.product === 'spot' ? '#06B6D4' : '#8B5CF6'
      const hot = this.hoverWall === w
      const lw = hot ? LINE.wallMax : Math.round(clamp(1 + w.size / 1.5e7, LINE.wallMin, LINE.wallMax))
      const y = lw % 2 ? Math.round(y0) + .5 : Math.round(y0) // 整数宽的横线落在像素格上才锐利
      c.strokeStyle = hexA(col, hot ? 1 : Math.min(0.9, 0.35 + w.size / 4e7))
      c.lineWidth = lw
      c.beginPath(); c.moveTo(x0, y); c.lineTo(x1, y); c.stroke()
      if (!w.to) {
        const t = fmtCompact(w.size), tw = c.measureText(t).width + 10
        c.fillStyle = hexA(col, hot ? 1 : 0.85); roundRect(c, PW - tw - 4, y - 8, tw, 16, 3); c.fill()
        c.fillStyle = '#fff'; c.textAlign = 'center'; c.fillText(t, PW - 4 - tw / 2, y + .5)
      }
    }
    c.font = this.font
  }
  wallAt(x: number, y: number): Wall | null {
    if (!this.walls || !this._panes || this.hidden.has('walls')) return null // 隐藏着的大单不响应悬停
    const p = this._panes[0], r = this._ranges.main
    let best: Wall | null = null, bd = 6
    for (const w of this.walls) {
      const wy = this.priceToY(w.price, p, r)
      const x0 = this.indexToX(this.indexAt(w.from)), x1 = w.to ? this.indexToX(this.indexAt(w.to)) : this.plotW()
      if (x < x0 - 4 || x > x1 + 4) continue
      const d = Math.abs(wy - y); if (d < bd) { bd = d; best = w }
    }
    return best
  }

  // ---- 复盘：持仓区间、进出场记号
  drawTradeSpan(p: Pane, _r: PriceRange): void {
    const c = this.ctx
    for (const m of this.markers ?? []) {
      const x0 = this.indexToX(this.indexAt(m.entryT)), x1 = this.indexToX(this.indexAt(m.exitT))
      const col = m.pnl >= 0 ? this.colors.up : this.colors.down
      c.fillStyle = hexA(col, 0.07); c.fillRect(x0, p.y, x1 - x0, p.h)
    }
  }
  drawMarkers(p: Pane, r: PriceRange): void {
    const c = this.ctx, C = this.colors
    for (const m of this.markers ?? []) {
      const i0 = this.indexAt(m.entryT), i1 = this.indexAt(m.exitT)
      const x0 = this.indexToX(i0), x1 = this.indexToX(i1)
      const y0 = this.priceToY(m.entry, p, r), y1 = this.priceToY(m.exit, p, r)
      const shown = this.replay == null || this.replay >= Math.round(i1)
      const lb = this.lastBar()
      c.strokeStyle = hexA(C.text2, .8); c.setLineDash([4, 3]); c.lineWidth = LINE.band
      c.beginPath(); c.moveTo(x0, y0); c.lineTo(shown ? x1 : this.indexToX(this.lastIndex()), shown || !lb ? y1 : this.priceToY(lb.c, p, r)); c.stroke(); c.setLineDash([])
      const tag = (x: number, y: number, text: string, col: string, below: boolean) => {
        c.font = `600 11px ${this.fontFamily()}`
        const tw = c.measureText(text).width + 12, ty = below ? y + 14 : y - 30
        this.textRects.push({ x: x - tw / 2, y: below ? ty - 5 : ty, w: tw, h: 23 })
        c.fillStyle = col; roundRect(c, x - tw / 2, ty, tw, 18, 4); c.fill()
        c.beginPath(); c.moveTo(x - 4, below ? ty : ty + 18); c.lineTo(x + 4, below ? ty : ty + 18); c.lineTo(x, below ? ty - 5 : ty + 23); c.closePath(); c.fill()
        c.fillStyle = '#fff'; c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillText(text, x, ty + 9)
        c.font = this.font
      }
      const longCol = C.up, shortCol = C.down
      if (this.replay == null || this.replay >= Math.round(i0)) tag(x0, y0, m.side === 'long' ? '开多' : '开空', m.side === 'long' ? longCol : shortCol, m.side === 'long')
      if (shown) tag(x1, y1, '平仓', C.text2, m.side !== 'long')
    }
  }

  // ---- 画线
  drawDrawings(p: Pane, r: PriceRange): void {
    const all = this.draft ? this.drawings.concat([this.draft]) : this.drawings
    if (this.drawingsHidden) return
    for (const d of all) if (!this.drawingShown || d === this.draft || this.drawingShown(d)) this.drawOne(d, p, r, d === this.selected || d === this.draft)
  }
  pt(q: DrawPoint, p: Pane, r: PriceRange): XY { return { x: this.indexToX(this.indexAt(q.t)), y: this.priceToY(q.p, p, r) } }
  drawOne(d: Drawing, p: Pane, r: PriceRange, sel: boolean): void {
    const c = this.ctx, PW = this.plotW(), col = d.color || '#2962FF'
    if (!d.pts.length) return
    if (drawComputed(this, d, p, r, sel)) return
    c.strokeStyle = col; c.lineWidth = d.width || LINE.draw; c.fillStyle = col; c.lineCap = d.dash === 'dotted' ? 'round' : d.dash ? 'butt' : 'round'; c.lineJoin = 'round'
    if (d.type !== 'fib' && d.type !== 'measure') c.setLineDash(dashPattern(d))
    const pts = d.pts.map(q => this.pt(q, p, r))
    if (offPlot(d.type, pts, p, PW)) return
    const a = pts[0], b = pts[1] || pts[0]
    const q0 = d.pts[0], q1 = d.pts[1] || d.pts[0]
    c.beginPath()
    if (d.type === 'trend') { c.moveTo(a.x, a.y); c.lineTo(b.x, b.y) }
    else if (d.type === 'ray') { const k = extend(a, b, PW * 3); c.moveTo(a.x, a.y); c.lineTo(k.x, k.y) }
    else if (d.type === 'hline') { c.moveTo(0, a.y); c.lineTo(PW, a.y) }
    else if (d.type === 'vline') { c.moveTo(a.x, p.y); c.lineTo(a.x, p.y + p.h) }
    else if (d.type === 'rect') { c.rect(Math.min(a.x, b.x), Math.min(a.y, b.y), Math.abs(b.x - a.x), Math.abs(b.y - a.y)); c.save(); c.fillStyle = hexA(col, .12); c.fill(); c.restore() }
    else if (d.type === 'fib') {
      const lv = [0, .236, .382, .5, .618, .786, 1], cols = ['#787B86', '#F23645', '#FF9800', '#4CAF50', '#089981', '#00BCD4', '#787B86']
      const x0 = Math.min(a.x, b.x), x1 = Math.max(a.x, b.x) + 0
      c.stroke(); c.lineWidth = LINE.band
      lv.forEach((L, k) => {
        const pr = q1.p + (q0.p - q1.p) * L, y = Math.round(this.priceToY(pr, p, r)) + .5
        c.strokeStyle = cols[k]; c.beginPath(); c.moveTo(x0, y); c.lineTo(x1, y); c.stroke()
        c.fillStyle = cols[k]; c.textAlign = 'right'; c.textBaseline = 'bottom'; c.font = `11px ${this.fontFamily()}`
        const ft = `${L} (${fmt(pr, this.meta.dec)})`, fw = c.measureText(ft).width
        c.fillText(ft, x0 - 4, y + 5)
        this.textRects.push({ x: x0 - 4 - fw, y: y + 5 - 13, w: fw, h: 13 })
      })
      c.font = this.font; c.textBaseline = 'middle'
      c.setLineDash([3, 3]); c.strokeStyle = hexA('#787B86', .8); c.beginPath(); c.moveTo(a.x, a.y); c.lineTo(b.x, b.y); c.stroke(); c.setLineDash([])
      c.beginPath()
    }
    else if (d.type === 'measure') {
      const up = q1.p >= q0.p, mc = up ? '#2962FF' : '#F23645'
      c.fillStyle = hexA(mc, .12); c.fillRect(Math.min(a.x, b.x), Math.min(a.y, b.y), Math.abs(b.x - a.x), Math.abs(b.y - a.y))
      c.strokeStyle = mc; c.lineWidth = LINE.measure; c.beginPath()
      const mx = Math.round((a.x + b.x) / 2) + .5, my = Math.round((a.y + b.y) / 2) + .5
      c.moveTo(mx, a.y); c.lineTo(mx, b.y); c.moveTo(a.x, my); c.lineTo(b.x, my); c.stroke()
      const dp = q1.p - q0.p, pct = dp / q0.p * 100
      const nb = Math.round(this.indexAt(q1.t) - this.indexAt(q0.t))
      const t1 = `${dp >= 0 ? '+' : ''}${fmt(dp, this.meta.dec)} (${pct >= 0 ? '+' : ''}${pct.toFixed(2)}%)`, t2 = `${nb} 根 · ${durText(Math.abs(nb) * this.iv)}`
      c.font = `600 12px ${this.fontFamily()}`
      const tw = Math.max(c.measureText(t1).width, c.measureText(t2).width) + 20
      const ly = up ? Math.min(a.y, b.y) - 50 : Math.max(a.y, b.y) + 8
      c.fillStyle = mc; roundRect(c, mx - tw / 2, ly, tw, 42, 6); c.fill()
      this.textRects.push({ x: mx - tw / 2, y: ly, w: tw, h: 42 })
      c.fillStyle = '#fff'; c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillText(t1, mx, ly + 13); c.font = this.font; c.fillText(t2, mx, ly + 29)
      c.beginPath()
    }
    c.stroke(); c.setLineDash([]); c.lineCap = 'round'
    if (sel) {
      for (const q of pts) { c.fillStyle = this.colors.bg; c.strokeStyle = col; c.lineWidth = LINE.handle; c.beginPath(); c.arc(q.x, q.y, 4.5, 0, Math.PI * 2); c.fill(); c.stroke() }
    }
    if (d.alert && d.type !== 'fib') { const e = pts[pts.length - 1]; c.fillStyle = this.colors.alert; c.beginPath(); c.arc(e.x + 10, e.y - 10, 4, 0, Math.PI * 2); c.fill() }
  }
  hitDrawing(x: number, y: number): DrawingHit | null {
    if (!this._panes || this.drawingsHidden) return null // 隐藏着的画线不能被点中、拖动
    const p = this._panes[0], r = this._ranges.main, PW = this.plotW()
    for (let k = this.drawings.length - 1; k >= 0; k--) {
      const d = this.drawings[k]
      if (!d.pts.length || (this.drawingShown && !this.drawingShown(d))) continue
      const pts = COMPUTED.has(d.type) ? handlePixels(this, d, p, r) : d.pts.map(q => this.pt(q, p, r)), a = pts[0], b = pts[1] || a
      for (let j = 0; j < pts.length; j++) if (Math.hypot(pts[j].x - x, pts[j].y - y) < 8) return { d, handle: j }
      let dist = hitComputed(this, d, x, y, p, r) ?? Infinity
      if (d.type === 'trend') dist = segDist(x, y, a, b)
      else if (d.type === 'ray') dist = segDist(x, y, a, extend(a, b, PW * 3))
      else if (d.type === 'hline') dist = Math.abs(y - a.y)
      else if (d.type === 'vline') dist = Math.abs(x - a.x)
      else if (d.type === 'rect' || d.type === 'measure' || d.type === 'fib') {
        const x0 = Math.min(a.x, b.x), x1 = Math.max(a.x, b.x), y0 = Math.min(a.y, b.y), y1 = Math.max(a.y, b.y)
        if (x >= x0 - 4 && x <= x1 + 4 && y >= y0 - 4 && y <= y1 + 4) dist = 0
      }
      if (dist < 6) return { d, handle: null }
    }
    return null
  }
  /** 像素 → 时间 + 价格（磁吸时吸到最近的开高低收）；调用前须已渲染过一帧（_panes 存在） */
  toTP(x: number, y: number): DrawPoint {
    const p = (this._panes as Pane[])[0], r = this._ranges.main
    let i = this.xToIndex(x), price = this.yToPrice(y, p, r)
    if (this.magnet !== this.metaHeld) { // 按住 ⌘ 临时反过来
      const k = Math.round(i), b = this.bars[k]
      if (b) { i = k; price = [b.o, b.h, b.l, b.c].reduce((a, v) => Math.abs(this.priceToY(v, p, r) - y) < Math.abs(this.priceToY(a, p, r) - y) ? v : a) }
    } else i = Math.round(i)
    return { t: this.timeAt(i), p: price }
  }

  // ---------------------------------------------------------- 图例
  legendIndex(): number {
    if (this.cross) return clamp(Math.round(this.xToIndex(this.cross.x)), 0, this.lastIndex())
    if (this.extCross != null) return clamp(Math.round(this.indexAt(this.extCross)), 0, this.lastIndex())
    return this.lastIndex()
  }
  renderLegend(): void {
    const i = this.legendIndex(), b = this.bars[i], dec = this.meta.dec
    // 新数据在路上 / 还没有 K 线：只摆标题（加「载入中」），旧图的开高低收不挂在新品种名下
    const pm = this.pendingMeta
    if (pm || !b) {
      const m = pm ?? this.meta
      if (!m.title) { this.setLegend('', []); return }
      const sub = this.deg.legend === 'compact' ? m.sub.split('·').map(x => x.trim()).filter(Boolean)[0] || '' : m.sub
      this.setLegend(`<div class="lrow${this.deg.legend === 'compact' ? ' compact' : ''}"><span class="title">${m.badge || ''}${esc(m.title)}<span class="sub">${sub}</span></span>${pm ? '<span class="loading-tag">载入中</span>' : ''}</div>`, [])
      return
    }
    const prev = this.bars[i - 1]
    const chg = prev ? b.c - prev.c : b.c - b.o, pct = chg / (prev ? prev.c : b.o) * 100
    const cls = this.stale ? 'faint' : chg >= 0 ? 'up' : 'down'
    // 结构（shell）只带「指标集 / 参数 / 降级档 / 对比线」，读数一个字都不进 shell——读数按 data-v 盒的出现顺序收进 boxes，
    // 由 patchVals 只改文字节点。推送与十字线移动不会再把指针下那一行换成新节点（2026-10-07「悬停一直跳、点不到隐藏」）
    const boxes: LegVal[][] = []
    // 多图小格：只留品种与周期（周期是 sub 里「· 」后的第一段）
    if (this.deg.legend === 'compact') {
      const iv = this.meta.sub.split('·').map(x => x.trim()).filter(Boolean)[0] || ''
      let cmp = ''
      if (this.compareOn()) for (const cv of this.compareViews()) {
        // 还在取数：名字后面一枚等待圈（在壳里，取到数壳才换）
        cmp += cv.line.loading ? `<span class="cmp-mini num" style="color:${cv.color}">${esc(cv.line.name)} <span class="cmp-wait"></span></span>` : '<span class="cmp-mini num" data-v></span>'
        if (!cv.line.loading) boxes.push([[cv.color, '', `${cv.line.name} ${comparePercentLabel(cv.at(i))}`]])
      }
      this.setLegend(`<div class="lrow compact"><span class="title">${this.meta.badge || ''}${esc(this.meta.title)}<span class="sub">${iv}</span></span>${cmp}</div>`, boxes)
      this.renderPaneLegends(this._panes || [])
      return
    }
    let h = `<div class="lrow"><span class="title">${this.meta.badge || ''}${esc(this.meta.title)}<span class="sub">${this.meta.sub}</span></span><span class="ohlc num" data-v></span></div>`
    boxes.push([['', '开', fmt(b.o, dec), cls], ['', '高', fmt(b.h, dec), cls], ['', '低', fmt(b.l, dec), cls], ['', '收', fmt(b.c, dec), cls],
      ['', '', `${chg >= 0 ? '+' : ''}${fmt(chg, dec)} (${pct >= 0 ? '+' : ''}${pct.toFixed(2)}%)`, cls], ...this.legendVolume(b, cls)])
    // 对比：每只一行「代号 +x.xx%」，悬停出移除（按钮在名字之后、读数之前）
    if (this.compareOn()) for (const cv of this.compareViews()) {
      h += `<div class="lrow cmp-row"><span class="lhead"><span class="cmp-dot" style="background:${cv.color}"></span><span class="ind-name">${esc(cv.line.name)}</span>${cv.line.loading ? '<span class="cmp-wait"></span>' : ''}<span class="tools"><button class="ibtn xs" data-act="cmpRemove" data-id="${cv.line.key}" data-tip="移除对比" aria-label="移除对比">${icon('close', 'icon-16')}</button></span></span>${VALS_BOX}</div>`
      boxes.push([[cv.color, '', comparePercentLabel(cv.at(i))]])
    }
    const items: [string, string, LegVal[]][] = []
    for (const id of MAIN_IDS) {
      if (!mainOn(this.ind, id)) continue
      const cat = CATALOG[id], cols = cat.colors ?? [], s = this.series[id] || [], labels = cat.labels
      const extra = id === 'vpvr' ? `<button class="lchip" data-act="vpvrMode" data-id="vpvr" data-tip="看法">${VPVR_MODES.find(m => m.id === this.vpvrMode)?.label ?? ''}${icon('chevronDown', 'icon-16')}</button>` : ''
      const vals: LegVal[] = []
      s.forEach((ser, k) => {
        // 之字转向只在转折那根有值：读数取到这根为止最近的一个转折
        let val = ser[i]
        if (id === 'zigzag') for (let j = Math.min(i, ser.length - 1); j >= 0 && val == null; j--) val = ser[j]
        const lab = labels?.[k]
        // 带前缀的线（上 / 下轨、R1 / S1、上 / 下分形、多 / 空）这一根没值就不列
        if (lab && val == null) return
        vals.push([cols[k % cols.length] || (id === 'pivots' ? pivotPColor(this) : 'var(--text)'), lab ?? '', fmt(val, dec)])
      })
      items.push([id, `<span class="lhead"><span class="ind-name">${cat.name}</span>${this.paramCell(id)}${extra}${this.legendTools(id)}</span>${VALS_BOX}`, vals])
    }
    if (this.ind.vol) items.push(['vol', `<span class="lhead"><span class="ind-name">成交量</span>${this.legendTools('vol')}</span>${VALS_BOX}`, [['', '', fmtCompact(b.v), b.c >= b.o ? 'up' : 'down']]])
    if (this.walls) {
      const fut = this.walls.filter(w => !w.to && w.product !== 'spot').length, spot = this.walls.filter(w => !w.to && w.product === 'spot').length
      items.push(['walls', `<span class="lhead"><span class="ind-name">主力订单流</span><span class="ind-param">${this.meta.wallParam || ''}</span>${this.legendTools('walls')}</span>${VALS_BOX}`, [['#8B5CF6', '', `合约 ${fut}`], ['#06B6D4', '', `现货 ${spot}`]]])
    }
    // 格子矮（dense）：主图指标并成一行，放不下的折成「…」，悬停这一行就地换行展开（第一行的块不挪位）；否则每个指标一行
    if (this.deg.legend === 'dense') { if (items.length) h += `<div class="lrow dense">${items.map(([id, x]) => `<span class="dchip" data-lid="${id}">${x}</span>`).join('')}</div>` }
    else for (const [id, x] of items) h += `<div class="lrow" data-lid="${id}">${x}</div>`
    for (const it of items) boxes.push(it[2])
    // 足迹图等挂的附加行（chart/footprint.ts）：整行是文字读数，直接进壳；它变了壳才重建
    if (this.legendExtra) h += this.legendExtra(i)
    this.setLegend(h, boxes)
    this.renderPaneLegends(this._panes || [])
  }
  /** 图例结构跟上一次拼的一样就不写：拿拼好的字符串比，不拿 innerHTML 比——
   *  浏览器序列化回来的 innerHTML（徽标 SVG 的自闭合标签、属性写法）跟拼的不一样，那样比每帧都会判成「变了」整块重写，
   *  十六格联动十字线时每帧 16 块图例重建，样式重算翻几倍 */
  private legendHtml: string | null = null
  private legendBoxes: HTMLElement[] = []
  private legendHidKey: string | null = null
  setLegendHtml(h: string): boolean {
    if (this.legendHtml === h) return false
    this.legendHtml = h
    this.legendEl.innerHTML = h
    return true
  }
  /** 结构变了才重建外壳；显隐就地改；读数只改文字节点 */
  setLegend(shell: string, boxes: readonly LegVal[][]): void {
    if (this.setLegendHtml(shell)) {
      this.legendBoxes = Array.from(this.legendEl.querySelectorAll<HTMLElement>('[data-v]'))
      this.legendHidKey = null
    }
    const hk = [...this.hidden].sort().join(',')
    if (this.legendHidKey !== hk) { this.legendHidKey = hk; applyHidden(this.legendEl, this.hidden) }
    boxes.forEach((v, k) => { const box = this.legendBoxes[k]; if (box) patchVals(box, v) })
  }
  /** 图例里名字与参数之后的 显示 / 参数 / 移除（固定宽、悬停才可见、不占位）；没有可调参数的不放齿轮 */
  legendTools(id: string): string {
    // 均线 / 指数均线 / RSI：一键带着图上的参数去建技术指标提醒
    const alertBtn = (id === 'ma' || id === 'ema' || id === 'rsi') && this.o?.onAlertCreate ? `<button class="ibtn xs" data-act="alert" data-id="${id}" data-tip="以此建提醒" aria-label="以此建提醒">${icon('bellPlus', 'icon-16')}</button>` : ''
    return toolsHtml(id, Object.keys(CATALOG[id as IndicatorId]?.params ?? {}).length > 0, alertBtn)
  }
  renderPaneLegends(panes: Pane[]): void {
    const subs = panes.slice(1)
    while (this.paneLegendEls.length < subs.length) { const e = document.createElement('div'); e.className = 'pane-legend'; this.host.appendChild(e); this.paneLegendEls.push(e); this.paneLegendKeys.push(null) }
    this.paneLegendEls.forEach((e, k) => { const d = k < subs.length ? '' : 'none'; if (e.style.display !== d) e.style.display = d })
    const i = this.legendIndex(), h4 = this.hist4Colors()
    subs.forEach((p, k) => {
      const e = this.paneLegendEls[k], id = p.id as SubId, cat = CATALOG[id], cols = cat.colors ?? [], s = this.series[id] || [], labels = cat.labels
      const top = (p.y + 6) + 'px'
      if (e.style.top !== top) e.style.top = top
      const vals = s.map((ser, j): LegVal | null => {
        const val = ser[i], lab = labels?.[j]
        // 带前缀的线（现货 / 合约、大单 / 散户）这一根没值就不列
        if (lab && val == null) return null
        // 柱的读数跟这一根柱子的颜色完全一样（TV 图例值随 plot 当根颜色）；零轴柱用文字涨跌色保证浅底可读
        const st = id === 'macd' ? (j === 2 ? 'hist4' : 'line') : subStyles(id)?.[j] ?? 'line'
        const v0 = val ?? 0, prev = ser[i - 1] ?? v0
        const col = st === 'hist' ? (v0 >= 0 ? 'var(--up-text)' : 'var(--down-text)')
          : st === 'hist4' || st === 'histTrend' ? this.histColor(st, v0, prev, h4)
          : cols[j % cols.length]
        return [col, lab ?? '', val == null ? '—' : this.subFmt(id, val)]
      }).filter((v): v is LegVal => v != null)
      // 外壳（名称、参数、显示 / 参数 / 移除按钮）只在指标、参数变了时重建；显隐就地改（applyHidden），
      // 十字线移动与推送只改读数那几个字（patchVals）
      const shell = id + ':' + this.paramCell(id)
      const em = e as HTMLElement & { _h?: string }
      if (this.paneLegendKeys[k] !== shell) {
        this.paneLegendKeys[k] = shell; em._h = undefined
        e.innerHTML = `<div class="lrow" data-lid="${id}"><span class="lhead"><span class="ind-name">${cat.name}</span>${this.paramCell(id)}${this.legendTools(id)}</span>${VALS_BOX}</div>`
      }
      const hk = String(this.hidden.has(id))
      if (em._h !== hk) { em._h = hk; applyHidden(e, this.hidden) }
      const box = e.querySelector<HTMLElement>('[data-v]'); if (box) patchVals(box, vals)
    })
  }

  // ---------------------------------------------------------- 交互
  region(x: number, y: number): Region {
    if (y > this.h - AXIS_H) return x > this.plotW() ? 'corner' : 'time'
    if (x > this.plotW()) return 'price'
    const panes = this._panes || []
    for (const p of panes.slice(1)) if (Math.abs(y - p.y) <= SEP_HIT) return `sep:${p.id}`
    return 'plot'
  }
  paneAt(y: number): Pane | undefined { return (this._panes || []).find(p => y >= p.y && y < p.y + p.h) }
  bind(): void {
    const cv = this.canvas, signal = this.ac.signal
    const pos = (e: MouseEvent): XY => { const r = cv.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top } }
    this.host.addEventListener('mousedown', () => this.o.onActivate?.(), { capture: true, signal })
    this.host.addEventListener('click', e => {
      const btn = (e.target as Element | null)?.closest<HTMLElement>('[data-act]'); if (!btn) return
      e.stopPropagation()
      const id = btn.dataset.id ?? '', act = btn.dataset.act ?? ''
      if (act === 'toggle') { if (this.hidden.has(id)) this.hidden.delete(id); else this.hidden.add(id); this.dirty = true; this.renderLegend() }   // 显隐就地改（applyHidden），不重建图例外壳
      else this.o.onLegendAction?.(id, act, btn)
    }, { signal })
    cv.addEventListener('mousemove', e => {
      const { x, y } = pos(e)
      if (this.drag) return
      const reg = this.region(x, y)
      cv.style.cursor = reg === 'price' ? 'ns-resize' : reg === 'time' ? 'ew-resize' : reg.startsWith('sep') ? 'row-resize' : 'crosshair'
      const sep = reg.startsWith('sep:') ? reg.slice(4) : null
      if (sep !== this.hoverSep) { this.hoverSep = sep; this.dirty = true }
      let full = false
      const onMainAxis = reg === 'price' && this.paneAt(y)?.id === 'main' && !!this.o.onAlertCreate
      const hy = onMainAxis ? y : null
      if (hy !== this.axisHoverY) { this.axisHoverY = hy; this.dirty = true }
      if (onMainAxis) {
        if (x <= this.plotW() + ALERT_CHIP_W || this.alertNear(y, 10)) cv.style.cursor = this.alertNear(y, 10) ? 'grab' : 'pointer'
        cv.title = x <= this.plotW() + ALERT_CHIP_W ? '点一下或拖到位松手，在这个价位建提醒' : ''
      } else if (cv.title) cv.title = ''
      if (reg === 'plot') {
        const pane = this.paneAt(y)
        this.cross = { x, y, pane: pane?.id }
        this.metaHeld = e.metaKey || e.ctrlKey
        if (this.draft && this._panes) { this.updateDraft(x, y, e.shiftKey); full = true }
        if (!this.tool) {
          const hit = this.editable() ? this.hitDrawing(x, y) : null
          if (hit) cv.style.cursor = hit.handle != null ? 'grab' : 'pointer'
          let soft = false
          const lh = pane?.id === 'main' && !hit ? this.layers.find(l => { const r = l.hover?.(x, y, e.clientX, e.clientY); soft = r === 'soft'; return !!r }) ?? null : null
          if (this.layerHover !== lh) full = true
          if (this.layerHover && this.layerHover !== lh) this.layerHover.leave?.()
          this.layerHover = lh
          if (lh && !soft) cv.style.cursor = 'pointer'
          const w = pane?.id === 'main' && !hit && !lh ? this.wallAt(x, y) : null
          if (w !== this.hoverWall) { this.hoverWall = w; full = true; this.o.onWallHover?.(w, e.clientX, e.clientY) }
          else if (w) this.o.onWallHover?.(w, e.clientX, e.clientY)
        }
        this.o.onCrosshairMove?.(this.timeAt(Math.round(this.xToIndex(x))))
      } else { this.cross = null; this.o.onCrosshairMove?.(null); if (this.layerHover) { this.layerHover.leave?.(); this.layerHover = null; full = true } }
      // 草稿、挂单墙高亮、图层悬停变了要整帧重画；只是十字线挪了就走轻量帧（贴底图 + 十字线）
      if (full) this.dirty = true; else this.crossDirty = true
      this.legendDirty = true  // 图例读数并到下一帧：高回报率鼠标一帧里来好几次 mousemove，只拼一次 DOM
    }, { signal })
    cv.addEventListener('mouseleave', () => {
      if (this.drag) return
      this.hoverSep = null
      this.cross = null; this.axisHoverY = null; this.dirty = true; this.legendDirty = true
      if (this.hoverWall) { this.hoverWall = null; this.o.onWallHover?.(null) }
      if (this.layerHover) { this.layerHover.leave?.(); this.layerHover = null }
      this.o.onCrosshairMove?.(null)
    }, { signal })
    cv.addEventListener('mousedown', e => {
      if (e.button === 2) {
        const { x, y } = pos(e)
        this.rightDragged = false; this.pendingMenu = null
        if (this.region(x, y) === 'plot' && this.paneAt(y)?.id === 'main' && this.mainRange && !this.drag)
          this.drag = { kind: 'pan', region: 'plot', x0: x, y0: y, right0: this.rightBar, sp0: this.spacing, r0: { ...this.mainRange }, moved: false, pane: this.paneAt(y), vertical: true }
        return
      }
      if (e.button !== 0) return
      const { x, y } = pos(e), reg = this.region(x, y)
      if (reg === 'price' && this.o.onAlertCreate && this._panes && this.paneAt(y)?.id === 'main') {
        const near = this.alertNear(y, 10)
        if (near || x <= this.plotW() + ALERT_CHIP_W) {
          this.drag = { kind: 'alert', line: near, price: near ? near.price : this.yToPrice(y, this._panes[0], this._ranges.main), moved: false }
          cv.style.cursor = 'grabbing'; this.dirty = true; return
        }
      }
      if (reg === 'plot' && !this.tool && this.o.onAlertMove && this.paneAt(y)?.id === 'main' && !this.hitDrawing(x, y)) {
        const near = this.alertNear(y, 4)
        if (near) { this.drag = { kind: 'alert', line: near, price: near.price, moved: false }; cv.style.cursor = 'grabbing'; this.dirty = true; return }
      }
      this.metaHeld = e.metaKey || e.ctrlKey
      if (reg === 'plot' && this.tool) {
        const pane = this.paneAt(y); if (pane?.id !== 'main' || !this.editable() || !this._panes) return
        const tp = this.toTP(x, y), t = this.tool
        if (!this.draft) {
          const sty = this.styleFor(t)
          // 到了每只品种的上限：不新建（页面提示）
          if (t !== 'measure' && this.o.canAdd?.([{ id: '', type: t, pts: [tp, tp, tp], ...sty }]) === false) return
          if (placeCount(t) === 1) { const d: Drawing = { id: uid(), type: t, pts: [tp], ...sty }; this.drawings.push(d); this.selected = d; this.finishTool(d); return }
          this.draft = { id: uid(), type: t, pts: [tp, { ...tp }], ...sty }
          setDraftEnd(this.draft, { ...tp })
          this.drag = { kind: 'place', x0: x, y0: y }
        } else { this.updateDraft(x, y, e.shiftKey); this.completeDraft() }
        this.dirty = true; return
      }
      if (reg === 'plot' && this._panes) {
        let hit = this.editable() ? this.hitDrawing(x, y) : null
        let copied: Drawing[] | undefined
        if (hit && hit.handle == null && (e.metaKey || e.ctrlKey) && hit.d.type !== 'measure') { // ⌘ + 拖 = 复制一份拖走，原来那条不动
          const copy: Drawing = { ...structuredClone(hit.d), id: uid(), locked: false }
          delete copy.alert
          if (this.o.canAdd?.([copy]) === false) return
          this.drawings.push(copy); hit = { d: copy, handle: null }; copied = this.drawings
        }
        if (hit) {
          this.selected = hit.d; this.o.onSelectDrawing?.(hit.d)
          const start = this.toTP(x, y), orig = hit.d.pts.map(q => ({ ...q }))
          this.drag = { kind: 'drawing', hit, start, orig, moved: false, copied }
          this.dirty = true; return
        }
        if (this.selected) { this.selected = null; this.o.onSelectDrawing?.(null) }
        if (this.measure) this.removeMeasure()
        if (e.shiftKey) { // Shift + 拖 = 临时测量（TradingView 同款）
          const tp = this.toTP(x, y); this.draft = { id: uid(), type: 'measure', pts: [tp, { ...tp }], color: '#2962FF', width: LINE.measure }; this.drag = { kind: 'measure' }; return
        }
      }
      const r0 = this.mainRange ? { ...this.mainRange } : null
      this.drag = { kind: 'pan', region: reg, x0: x, y0: y, right0: this.rightBar, sp0: this.spacing, r0, moved: false, pane: this.paneAt(y) }
      if (reg === 'plot') cv.style.cursor = 'grabbing'
    }, { signal })
    window.addEventListener('mousemove', e => {
      if (!this.drag || this.dead) return
      const { x, y } = pos(e), d = this.drag
      if (d.kind === 'alert') {
        if (this._panes) { const np = this.yToPrice(y, this._panes[0], this._ranges.main); if (Math.abs(np - d.price) > 0) { d.moved = true; d.price = np } }
        this.dirty = true; return
      }
      this.metaHeld = e.metaKey || e.ctrlKey
      if (d.kind === 'measure') { if (this.draft) this.draft.pts[1] = this.toTP(x, y); this.cross = { x, y, pane: 'main' }; this.dirty = true; return }
      if (d.kind === 'place') { this.updateDraft(x, y, e.shiftKey); this.cross = { x, y, pane: 'main' }; this.dirty = true; return }
      if (d.kind === 'drawing') {
        const dd = d.hit.d
        if (dd.locked) return
        let now = this.toTP(x, y)
        if (!d.moved) this.o.onDrawDrag?.(true) // 真拖起来才让快捷条淡出（只是点选不闪）
        d.moved = true
        if (d.hit.handle != null) {
          // ⇧ 拖端点：吸到 0° / 45° / 90°
          if (e.shiftKey && (dd.type === 'trend' || dd.type === 'ray') && dd.pts.length === 2) now = this.snapTP(dd.pts[1 - d.hit.handle], x, y)
          moveHandle(dd, d.hit.handle, now)
        } else {
          dd.pts = this.dragBody(d.orig, d.start, now)
        }
        this.dirty = true; return
      }
      const dx = x - d.x0, dy = y - d.y0
      if (Math.abs(dx) + Math.abs(dy) > 2) d.moved = true
      if (d.vertical) {
        if (!d.moved || !d.r0 || !this._panes) return
        const p = this._panes[0], k = (this.tf(d.r0.max) - this.tf(d.r0.min)) / (p.h - 16) * dy
        this.manual = { min: this.itf(this.tf(d.r0.min) + k), max: this.itf(this.tf(d.r0.max) + k) }
        if (this.auto) { this.auto = false; this.o.onAutoChange?.(false) }
        this.cross = null
      } else if (d.region === 'plot') {
        this.rightBar = this.clampRB(d.right0 - dx / this.spacing)
        if (!this.auto && d.pane?.id === 'main' && d.r0 && this._panes) {
          const p = this._panes[0]; const k = (this.tf(d.r0.max) - this.tf(d.r0.min)) / (p.h - 16) * dy
          this.manual = { min: this.itf(this.tf(d.r0.min) + k), max: this.itf(this.tf(d.r0.max) + k) }
        }
        this.cross = null; this.maybeMore()
      } else if (d.region === 'time') {
        // TV 拖时间轴：右沿不动、按下处那根跟着鼠标（往左拖放大，往右拖缩小）
        const sp = timeAxisDragSpacing(d.sp0, d.x0, x, this.plotW())
        if (sp != null) this.spacing = sp
        this.rightBar = this.clampRB(d.right0); this.maybeMore()
      } else if (d.region === 'price' && d.pane?.id === 'main' && d.r0) {
        const lo = this.tf(d.r0.min), hi = this.tf(d.r0.max)
        if (this.scaleManual(lo, hi, (lo + hi) / 2, Math.exp(dy / 200)) && this.auto) { this.auto = false; this.o.onAutoChange?.(false) }
      } else if (d.region.startsWith('sep:') && this._panes) {
        const id = d.region.slice(4), panes = this._panes, k = panes.findIndex(p => p.id === id)
        if (k >= 1) {
          // 起点的各格高度在按下时记下（sepHs），拖动只在上下两格之间挪
          const H = this.h - AXIS_H, base = this.sepHs ?? panes.map(p => p.h)
          this.sepHs = base
          const hs = dragPane(base, k, y - d.y0, H)
          this.paneR = paneRatiosOf(this.subIds(), hs, H)
          this.paneLegendKeys.fill(null)
        }
      }
      if (!d.vertical && (d.region === 'plot' || d.region === 'time')) this.emitView()
      this.dirty = true; this.legendDirty = true
    }, { signal })
    window.addEventListener('mouseup', e => {
      if (!this.drag || this.dead) return
      const d = this.drag; this.drag = null
      if (d.kind === 'alert') {
        this.canvas.style.cursor = 'crosshair'; this.dirty = true
        if (!(d.price > 0)) return
        if (!d.line) this.o.onAlertCreate?.(d.price)
        else if (d.moved) { d.line.price = d.price; this.o.onAlertMove?.(d.line, d.price) }
        return
      }
      if (d.kind === 'pan' && d.vertical) {
        const menu = this.pendingMenu; this.pendingMenu = null
        this.rightDragged = d.moved
        this.canvas.style.cursor = 'crosshair'
        if (!d.moved && menu) this.o.onContextMenu?.(menu)
        return
      }
      if (d.kind === 'pan' && !d.moved && d.region === 'plot' && d.pane?.id === 'main' && this.layers.length) {
        const { x, y } = pos(e)
        if (this.layers.some(l => l.click?.(x, y))) { this.canvas.style.cursor = 'crosshair'; return }
      }
      if (d.kind === 'measure') { const m = this.draft; this.draft = null; if (m) { this.measure = m; this.drawings.push(m) } this.dirty = true; return }
      if (d.kind === 'place') {
        const { x, y } = pos(e)
        // 按下拖出一段才松手 = 画完；原地点一下就等第二下
        if (this.draft && Math.hypot(x - d.x0, y - d.y0) > 5) { this.updateDraft(x, y, e.shiftKey); this.completeDraft() }
        this.dirty = true; return
      }
      if (d.kind === 'drawing') { this.o.onDrawDrag?.(false); this.o.onDrawingsChanged?.(); return }
      if (d.kind === 'pan' && d.region.startsWith('sep:')) {
        this.sepHs = null; this.dirty = true
        if (d.moved && this.paneR) this.o.onPaneResize?.({ ...this.paneR })
        return
      }
      if (d.kind === 'pan' && d.moved && (d.region === 'plot' || d.region === 'time')) this.emitView()
      this.canvas.style.cursor = 'crosshair'
    }, { signal })
    // ⌘ 按下 / 松开：磁吸临时反过来，草稿跟着重吸
    const meta = (e: KeyboardEvent) => { const on = e.metaKey || e.ctrlKey; if (on !== this.metaHeld) { this.metaHeld = on; if (this.draft && this.cross) { this.updateDraft(this.cross.x, this.cross.y, e.shiftKey); this.dirty = true } } }
    window.addEventListener('keydown', meta, { signal }); window.addEventListener('keyup', meta, { signal })
    window.addEventListener('blur', () => { this.metaHeld = false }, { signal })
    cv.addEventListener('dblclick', e => {
      const { x, y } = pos(e), reg = this.region(x, y)
      if (reg === 'price') this.setAuto(true)
      else if (reg === 'time') { this.resetView(); this.emitView() }
      else if (reg.startsWith('sep:')) { this.paneR = null; this.paneLegendKeys.fill(null); this.dirty = true; this.o.onPaneResize?.(null) }
    }, { signal })
    // 滚轮 / 触控板照 TradingView（ChartWidget._onMousewheel，算法见 ./wheel）：
    // 竖向 = 缩放（右沿不动：最新一根和右侧留白原地不动，一格 ×1.1 / ×0.9，顺滑插到位；按住 ⌘（Mac）/ Ctrl（Windows）才以鼠标处为锚）；
    // 横向（触控板横扫、Shift + 滚轮）= 平移，一格 80 px、不带惯性；触控板捏合（带 ctrlKey 的滚轮）= 跟手缩放；
    // 价格轴上 / Alt + 滚轮 = 缩价格（鼠标那一价不动）
    cv.addEventListener('wheel', e => {
      if (e.cancelable) e.preventDefault()
      const { x, y } = pos(e), reg = this.region(x, y)
      const { dx, dy } = wheelDelta(e, wheelSpeed(e.deltaMode, WIN_CHROMIUM, window.devicePixelRatio || 1))
      const zf = dy ? (e.ctrlKey ? pinchFactor(dy) : zoomFactor(zoomScale(dy))) : 1
      if (e.altKey || reg === 'price') {
        const main = this.paneAt(y)?.id === 'main'
        if (reg === 'price' && !main) return // 副图的价格轴各自自适应，不缩
        if (zf !== 1) this.zoomPrice(1 / zf, main ? y : undefined)
        return
      }
      const atCursor = reg === 'plot' && (IS_MAC ? e.metaKey : e.ctrlKey)
      if (zf !== 1) this.wheelZoom(zf, atCursor ? x : this.plotW(), undefined, e.ctrlKey)
      if (dx) { this.wheelPan(panPx(dx)); this.legendDirty = true; this.emitView() }
    }, { passive: false, signal })
    cv.addEventListener('contextmenu', e => {
      e.preventDefault()
      const { x, y } = pos(e)
      if (this.region(x, y) !== 'plot') return
      const pane = this.paneAt(y)
      const hit = this.editable() ? this.hitDrawing(x, y) : null
      const price = pane?.id === 'main' ? this.yToPrice(y, pane, this._ranges.main) : null
      const info: ContextMenuInfo = { clientX: e.clientX, clientY: e.clientY, price, time: this.timeAt(Math.round(this.xToIndex(x))), drawing: hit?.d, pane: pane?.id }
      // 右键还按着（macOS 按下就发）：等松手，没拖动才弹；刚右键拖过（Windows 松手后才发）：这一次不弹
      if (this.drag?.kind === 'pan' && this.drag.vertical) { this.pendingMenu = info; return }
      if (this.rightDragged) { this.rightDragged = false; return }
      this.o.onContextMenu?.(info)
    }, { signal })
  }
  finishTool(d: Drawing, keep?: boolean): void { this.o.onToolDone?.(d, keep); this.o.onDrawingsChanged?.(); if (!keep && this.selected === d) this.o.onSelectDrawing?.(d); this.dirty = true }
  /** 新画一条的样式：测量固定蓝细线，其它问页面（同族记忆），没有就用默认 */
  styleFor(t: DrawingType): Pick<Drawing, 'color' | 'width' | 'dash'> {
    if (t === 'measure') return { color: '#2962FF', width: LINE.measure }
    const s = this.o.drawStyle?.(t) ?? {}
    const out: Pick<Drawing, 'color' | 'width' | 'dash'> = { color: s.color || this.o.drawColor?.() || '#2962FF', width: s.width || LINE.draw }
    if (s.dash) out.dash = s.dash
    return out
  }
  /** 草稿的最后一点跟到 (x, y)；⇧ 按着时趋势线 / 射线吸 45° */
  private updateDraft(x: number, y: number, shift: boolean): void {
    const d = this.draft
    if (!d || !this._panes) return
    setDraftEnd(d, shift && (d.type === 'trend' || d.type === 'ray') ? this.snapTP(d.pts[0], x, y) : this.toTP(x, y))
  }
  private completeDraft(): void {
    const d = this.draft; if (!d) return
    this.draft = null
    if (d.type === 'measure') { this.measure = d; this.drawings.push(d); this.finishTool(d, true); return }
    if (d.type === 'position') widenPosition(this, d)
    this.drawings.push(d); this.selected = d; this.finishTool(d)
  }
  /** 从 anchor 到 (x, y) 吸 45° 之后的锚点 */
  private snapTP(anchor: DrawPoint, x: number, y: number): DrawPoint {
    const p = (this._panes as Pane[])[0], r = this._ranges.main
    const s = snap45(this.pt(anchor, p, r), { x, y }, X => this.indexToX(Math.round(this.xToIndex(X))))
    return { t: this.timeAt(Math.round(this.xToIndex(s.x))), p: this.yToPrice(s.y, p, r) }
  }
  deleteSelected(): boolean {
    if (!this.selected || !this.editable()) return false
    const i = this.drawings.indexOf(this.selected); if (i >= 0) this.drawings.splice(i, 1)
    this.selected = null; this.o.onDrawingsChanged?.(); this.o.onSelectDrawing?.(null); this.dirty = true; return true
  }
  cancelDraft(): boolean {
    if (this.draft) { this.draft = null; this.dirty = true; return true }
    if (this.measure) { this.removeMeasure(); this.dirty = true; return true }
    return false
  }
  /** 清掉画完的测量框。原型直接 splice(indexOf(measure))：画线数组被 setDrawings 换掉后 indexOf 是 -1，会误删最后一条画线 */
  private removeMeasure(): void {
    const m = this.measure; this.measure = null
    if (!m) return
    const i = this.drawings.indexOf(m)
    if (i >= 0) this.drawings.splice(i, 1)
  }
  maybeMore(): void {
    if (this.bars.length && this.xToIndex(0) < 60 && !this.loadingMore && !this.pendingMeta) this.o.onNeedMore?.()
  }
  crossPrice(): number | null {
    if (!this.cross || this.cross.pane !== 'main' || !this._panes) return null
    return this.yToPrice(this.cross.y, this._panes[0], this._ranges.main)
  }
  private fontFamily(): string { return this.font.split('px ')[1] }
}

/** Windows 上的 Chromium 滚轮量要再除 DPR（TV 同款修正，见 ./wheel wheelSpeed） */
const WIN_CHROMIUM = typeof navigator !== 'undefined' && isWinChromium(navigator.userAgent)
/** ⌘ 是 Mac 上的修饰键、别处是 Ctrl（TV 同款：按住它滚轮才以鼠标处为锚缩放） */
const IS_MAC = typeof navigator !== 'undefined' && /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent)

// ------------------------------------------------------------ 共用的一帧
// 十六格各自挂一个 requestAnimationFrame 循环，每帧就是十六次回调；合成一个循环，挨个问脏没脏。
const frames = new Set<TVChart>()
let frameId = 0, inTick = false
function tick(): void {
  frameId = 0
  // 先推进滚轮缩放（会经 emitView 把时间段套到联动的格子上），再统一画：联动的格子同一帧跟上
  const now = performance.now()
  for (const ch of frames) ch.stepZoom(now)
  inTick = true
  try { for (const ch of frames) ch.frame() } finally { inTick = false }
  for (const ch of frames) ch.frameDom()
  if (frames.size) frameId = requestAnimationFrame(tick)
}
function kick(): void { if (!frameId && typeof requestAnimationFrame !== 'undefined') frameId = requestAnimationFrame(tick) }

// ------------------------------------------------------------ 小工具
function roundRect(c: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void { c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath() }
function segDist(x: number, y: number, a: XY, b: XY): number {
  const dx = b.x - a.x, dy = b.y - a.y, L = dx * dx + dy * dy
  const t = L ? clamp(((x - a.x) * dx + (y - a.y) * dy) / L, 0, 1) : 0
  return Math.hypot(x - (a.x + t * dx), y - (a.y + t * dy))
}
function extend(a: XY, b: XY, len: number): XY { const dx = b.x - a.x, dy = b.y - a.y, L = Math.hypot(dx, dy) || 1; return { x: a.x + dx / L * len, y: a.y + dy / L * len } }
let _u = 0; function uid(): string { return 'd' + Date.now().toString(36) + (_u++) }

/** 提醒线右端的小铃铛（钟罩 + 锤子），以 (x, y) 为中心，约 9px */
function bellGlyph(c: CanvasRenderingContext2D, x: number, y: number, color: string): void {
  c.save()
  c.fillStyle = color; c.strokeStyle = color; c.lineWidth = 1.2; c.lineJoin = 'round'
  const w = 8, h = 8, top = y - h / 2 - 1
  c.beginPath()
  c.moveTo(x - w / 2, top + h)
  c.lineTo(x - w / 2 + 1, top + h * 0.4)
  c.arc(x, top + h * 0.4, w / 2 - 1, Math.PI, 0, false)
  c.lineTo(x + w / 2, top + h)
  c.closePath(); c.fill()
  c.beginPath(); c.arc(x, top + h + 1.6, 1.3, 0, Math.PI * 2); c.fill()
  c.restore()
}
