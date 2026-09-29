/* Hkline Web · K 线引擎（TradingView 桌面版的那一套）
 *
 * 和手机那套（AICoin 复刻）完全分开。对齐的是 TradingView 桌面版：
 *   · 多窗格：主图 + 最多三个副图，窗格之间 1 px 分隔、可拖动改高度
 *   · 右侧价格轴：最新价标签（实心、涨跌色）下面一行是本根收线倒计时；十字线在轴上出深色标签
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
import { clamp, crossTimeLabel, durText, fmt, fmtAxis, fmtCompact, hexA, niceStep, pad } from '../util/format'
import { CATALOG, Calc, MAIN_IDS, paramText } from './calc'
import type { Bar, CalcId, IndParams, IndicatorId, MainId, Series, SubId } from './calc'
import { TIME_TICK_MIN_PX, timeTicks } from './timeAxis'
import type { TimeTick } from './timeAxis'
import { SUB_FIXED, type ExtraSubId } from './indicators'
import { VPVR_MODES, drawExtraMain, drawSubLevels, type Vpvr, type VpvrMode } from './overlays'
import { FULL, dragPane, paneHeights, paneRatiosOf, type Degrade } from './panes'
import { COMPUTED, bbox, dashPattern, drawComputed, handlePixels, hitComputed, moveHandle, placeCount, setDraftEnd, snap45, widenPosition } from './drawTools'

const AXIS_H = 28
const MIN_SPACING = 1.5
const MAX_SPACING = 60
const DEFAULT_SPACING = 8
const RIGHT_MARGIN_BARS = 6
const SEP_HIT = 3 // 窗格分隔线上下各 3 px，热区 6 px

// 线条规格（网页版自己的一套，和手机端无关）。基准屏 1 CSS px = 1 物理像素：
// 横竖线一律整数宽、落在半像素上才锐利；曲线允许 1.5 px，靠抗锯齿显得顺滑又不压过 K 线。
// K 线是主体：影线 1 px（间距 ≥ 20 时 2 px），实体奇偶跟影线走，让影线永远正好居中。
export const LINE = {
  hair: 1,      // 网格、窗格分隔、轴线、RSI 参考线、最新价点线、提醒线、十字线
  plot: 1.5,    // 主图叠加线（MA / EMA / BOLL 中轨）、副图曲线（MACD / RSI / KDJ / 持仓量）
  band: 1,      // BOLL 上下轨、斐波那契各档、复盘的进出场连线
  draw: 2,      // 画线工具默认粗细（用户可改 1 / 2 / 3）
  measure: 1,   // 测量十字
  wallMin: 1, wallMax: 3, // 主力大单：按金额从 1 到 3 px，悬停 3 px
  handle: 2,    // 选中锚点的描边
} as const
const VOL_ALPHA = 0.3, VOL_H = 0.16 // 成交量：垫在主图底部 16%，三成不透明，不抢蜡烛

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

export interface IndState { ma: boolean; ema: boolean; boll: boolean; vol: boolean; subs: SubId[]; vwap?: boolean; st?: boolean; ichi?: boolean; vpvr?: boolean }

export interface ContextMenuInfo { clientX: number; clientY: number; price: number | null; time: number; drawing?: Drawing }

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
  cross: string; crossLabel: string; scaleLine: string
  up: string; down: string; accent: string; alert: string; line: string
}

export interface PriceRange { min: number; max: number }
export type PaneId = 'main' | SubId
export interface Pane { id: PaneId; y: number; h: number; ticks?: number[] }
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
interface DragDrawing { kind: 'drawing'; hit: DrawingHit; start: DrawPoint; orig: DrawPoint[]; moved: boolean }
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
  /** 各副图图例上次渲染的内容键，没变就不重写 innerHTML（原型挂在元素的 _k 上） */
  paneLegendKeys: (string | null)[] = []
  bars: Bar[] = []
  iv = 36e5
  meta: ChartMeta = { symbol: '', title: '', sub: '', dec: 2 }
  spacing = DEFAULT_SPACING
  rightBar = 0
  ind: IndState = { ma: true, ema: false, boll: false, vol: true, subs: ['macd', 'rsi'] }
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
  series: Partial<Record<CalcId, Series[]>> = {}
  log = false
  auto = true
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
  hoverWall: Wall | null = null
  /** 外挂绘制层（订单流） */
  layers: ChartLayer[] = []
  private layerHover: ChartLayer | null = null
  colors: ThemeColors = { bg: '', grid: '', text: '', text2: '', text3: '', cross: '', crossLabel: '', scaleLine: '', up: '', down: '', accent: '', alert: '', line: '' }
  font = '12px sans-serif'
  /** 画完的测量框（下一次点击就清掉） */
  measure: Drawing | null = null
  /** app 在加载更早历史时置 true，期间不再催 onNeedMore */
  loadingMore = false
  /** 画线整体隐藏 */
  drawingsHidden = false
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
      cross: v('--chart-cross'), crossLabel: v('--chart-cross-label'), scaleLine: v('--chart-scale-line'),
      up: v('--up'), down: v('--down'), accent: v('--accent'), alert: v('--alert-line'), line: v('--line'),
    }
    this.font = `${this.deg.font}px ${getComputedStyle(document.body).getPropertyValue('--font-num').trim() || 'sans-serif'}`
    this.dirty = true
  }
  /** 多图降级：格子尺寸变了由页面算好传进来；没变就什么都不做 */
  setDegrade(d: Degrade): void {
    const o = this.deg
    if (o.subs === d.subs && o.compact === d.compact && o.font === d.font && o.vol === d.vol) return
    this.deg = d
    this.font = `${d.font}px ${this.fontFamily()}`
    if (o.subs !== d.subs) this.recalc()
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
    this.spacing = clamp(this.plotW() / (i1 - i0), MIN_SPACING, MAX_SPACING)
    this.rightBar = i1; this.dirty = true; this.legendDirty = true
    this.maybeMore()
  }
  /** 用户动了时间轴：告诉页面（联动别的格子） */
  private emitView(): void {
    if (!this.o.onViewChange || !this.bars.length) return
    this.o.onViewChange(this.timeOfIndex(this.xToIndex(0)), this.timeOfIndex(this.rightBar))
  }
  setData(bars: Bar[], meta: ChartMetaInput): void {
    const sameSym = this.meta.symbol === meta.symbol && this.iv === meta.iv
    this.bars = bars
    this.iv = meta.iv
    this.meta = Object.assign({}, this.meta, meta)
    if (!sameSym) { this.rightBar = bars.length - 1 + RIGHT_MARGIN_BARS; this.manual = null; this.auto = true; this.o.onAutoChange?.(true) }
    this.recalc(); this.dirty = true; this.renderLegend()
  }
  prependData(more: Bar[]): void {
    if (!more.length) return
    const first = this.bars[0]?.t ?? Infinity
    more = more.filter(b => b.t < first)
    this.bars = more.concat(this.bars)
    this.rightBar += more.length
    if (this.replay != null) this.replay += more.length
    this.recalc(); this.dirty = true
  }
  updateBar(b: Bar): void {
    const n = this.bars.length
    if (!n) return
    const last = this.bars[n - 1]
    if (b.t === last.t) { Object.assign(last, b) }
    else if (b.t > last.t) {
      const atEdge = this.rightBar >= n - 1
      this.bars.push(b)
      if (atEdge) this.rightBar += 1
    } else return
    this.recalcTail(); this.dirty = true
    if (!this.cross) this.legendDirty = true
  }
  setIndicators(ind: Partial<IndState>): void { this.ind = Object.assign({}, this.ind, ind); this.recalc(); this.dirty = true; this.renderLegend() }
  setParams(id: IndicatorId, p: IndParams): void { this.params[id] = p; this.recalc(); this.dirty = true; this.renderLegend() }
  setDrawings(arr: Drawing[]): void { this.drawings = arr; this.selected = null; this.measure = null; this.dirty = true }
  setTool(t: DrawingType | null): void { this.tool = t; this.draft = null; this.canvas.style.cursor = 'crosshair'; this.dirty = true }
  setMagnet(on: boolean): void { this.magnet = on }
  /** 能不能新画、拖、改画线（复盘回放里不能） */
  editable(): boolean { return !this.readOnly }
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
  /** 选中画线在画布上的上沿（选中快捷条躲开它） */
  selectedTop(): number | null {
    const d = this.selected
    if (!d || !this._panes) return null
    return bbox(this, d, this._panes[0], this._ranges.main)?.y0 ?? null
  }


  setWalls(w: Wall[] | null): void { this.walls = w; this.dirty = true }
  setAlerts(a: AlertLine[] | null | undefined): void { this.alerts = a || []; this.dirty = true }
  setVpvrMode(m: VpvrMode): void { this.vpvrMode = m; this.dirty = true; this.renderLegend() }
  setMarkers(m: Marker[] | null): void { this.markers = m; this.dirty = true }
  setReplay(i: number | null): void { this.replay = i; this.dirty = true; this.renderLegend() }
  setLog(on: boolean): void { this.log = on; this.manual = null; this.dirty = true }
  setAuto(on: boolean): void { this.auto = on; if (on) this.manual = null; this.dirty = true; this.o.onAutoChange?.(on) }
  setStale(on: boolean): void { this.stale = on; this.dirty = true; this.renderLegend() }
  syncCrosshair(t: number | null): void { this.extCross = t; this.dirty = true }
  resetView(): void { this.spacing = DEFAULT_SPACING; this.rightBar = this.lastIndex() + RIGHT_MARGIN_BARS; this.setAuto(true) }
  setVisibleRange(t0: number, t1: number): void {
    const i0 = this.indexAt(t0), i1 = this.indexAt(t1)
    const n = Math.max(10, i1 - i0 + 1)
    this.spacing = clamp(this.plotW() / (n + RIGHT_MARGIN_BARS), MIN_SPACING, MAX_SPACING)
    this.rightBar = i1 + RIGHT_MARGIN_BARS; this.setAuto(true)
  }
  scrollBars(k: number): void { this.rightBar += k; this.dirty = true; this.maybeMore() }
  zoom(f: number, anchorX?: number): void {
    const ax = anchorX ?? this.plotW()
    const idx = this.xToIndex(ax)
    this.spacing = clamp(this.spacing * f, MIN_SPACING, MAX_SPACING)
    this.rightBar = idx + (this.plotW() - ax) / this.spacing
    this.dirty = true; this.maybeMore()
  }
  /** 纵向缩放主图价格轴（以 anchorY 为不动点；f > 1 放大价格区间） */
  zoomPrice(f: number, anchorY?: number): void {
    const p = this._panes?.[0], r = this.mainRange
    if (!p || !r) return
    const y = anchorY ?? p.y + p.h / 2
    const a = this.tf(this.yToPrice(y, p, r)), lo = this.tf(r.min), hi = this.tf(r.max)
    this.manual = { min: this.itf(a - (a - lo) * f), max: this.itf(a + (hi - a) * f) }
    if (this.auto) { this.auto = false; this.o.onAutoChange?.(false) }
    this.dirty = true
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
      pane: p, range: r, plotW: this.plotW(), from, to, spacing: this.spacing, iv: this.iv, log: this.log,
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
    frames.delete(this)
    this.drag = null
    this.host.innerHTML = ''
  }

  // ---------------------------------------------------------- 指标
  recalc(): void {
    this.series = {}
    const b = this.bars
    if (!b.length) return
    for (const id of MAIN_IDS) if (this.ind[id]) this.series[id] = Calc[id](b, this.params[id])
    // 降级收掉副图时不算副图（十六图里每格省下几个指标的整段重算）
    if (this.deg.subs) for (const id of this.ind.subs) if (Calc[id]) this.series[id] = Calc[id](b, this.params[id])
  }
  recalcTail(): void { this.recalc() }

  // ---------------------------------------------------------- 几何
  resize(): void {
    const r = this.host.getBoundingClientRect()
    const w = Math.max(10, r.width), h = Math.max(10, r.height), dpr = window.devicePixelRatio || 1
    // 尺寸没变就不动画布（重设 canvas.width 会清空画面；拖分隔线时每帧都会问一遍）
    if (w === this.w && h === this.h && this.canvas.width === Math.round(w * dpr) && this.canvas.height === Math.round(h * dpr)) return
    this.w = w; this.h = h
    this.canvas.width = Math.round(this.w * dpr); this.canvas.height = Math.round(this.h * dpr)
    this.canvas.style.width = this.w + 'px'; this.canvas.style.height = this.h + 'px'
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    this.dirty = true
  }
  axisW(): number {
    this.ctx.font = this.font
    const max = this.mainRange ? this.mainRange.max : (this.bars[this.bars.length - 1]?.h || 100)
    const s = fmtAxis(max, this.meta.dec)
    return Math.max(56, Math.ceil(this.ctx.measureText(s).width) + 20)
  }
  plotW(): number { return this.w - this.aw }
  // 副图默认矮：每个副图取画布高的 11%，夹在 96–136 px（2K 屏上约 132 px，TradingView 桌面版的比例），
  // 主图拿剩下的全部。用户拖过分隔线后按比例记（paneR），窗口高度变了各格等比伸缩；
  // 主图不少于 40%、每个副图不少于 80 px。分配规则见 panes.ts。多图降级时只留主图。
  subIds(): SubId[] { return this.deg.subs ? this.ind.subs : [] }
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
  tf(v: number): number { return this.log ? Math.log(Math.max(v, 1e-12)) : v }
  itf(v: number): number { return this.log ? Math.exp(v) : v }
  priceToY(p: number, pane: Pane, r: PriceRange): number { const a = this.tf(r.max), b = this.tf(r.min); return pane.y + 8 + (a - this.tf(p)) / (a - b) * (pane.h - 16) }
  yToPrice(y: number, pane: Pane, r: PriceRange): number { const a = this.tf(r.max), b = this.tf(r.min); return this.itf(a - (y - pane.y - 8) / (pane.h - 16) * (a - b)) }

  rangeMain(from: number, to: number): PriceRange {
    if (this.manual) return this.manual
    let lo = Infinity, hi = -Infinity
    for (let i = from; i <= to; i++) { const b = this.bars[i]; if (!b) continue; lo = Math.min(lo, b.l); hi = Math.max(hi, b.h) }
    for (const id of MAIN_IDS) {
      const ser = this.series[id]
      if (!ser || this.hidden.has(id)) continue
      for (const s of ser) for (let i = from; i <= to; i++) { const v = s[i]; if (v != null) { lo = Math.min(lo, v); hi = Math.max(hi, v) } }
    }
    if (!isFinite(lo)) { lo = 0; hi = 1 }
    if (this.log) { const a = Math.log(lo), b = Math.log(hi), pad = (b - a) * 0.08 || 0.01; return { min: Math.exp(a - pad), max: Math.exp(b + pad) } }
    const pad = (hi - lo) * 0.08 || hi * 0.01 || 1
    return { min: lo - pad, max: hi + pad }
  }
  rangeSub(id: SubId, from: number, to: number): PriceRange {
    if (id === 'rsi') return { min: 0, max: 100 }
    const fixed = SUB_FIXED[id as ExtraSubId]; if (fixed) return fixed
    let lo = Infinity, hi = -Infinity
    for (const s of this.series[id] || []) for (let i = from; i <= to; i++) { const v = s[i]; if (v != null) { lo = Math.min(lo, v); hi = Math.max(hi, v) } }
    if (!isFinite(lo)) return { min: 0, max: 1 }
    if (id === 'macd') { const m = Math.max(Math.abs(lo), Math.abs(hi)) || 1; return { min: -m * 1.1, max: m * 1.1 } }
    const pad = (hi - lo) * 0.1 || 1; return { min: lo - pad, max: hi + pad }
  }

  // ---------------------------------------------------------- 渲染
  /** 共用的那一帧里调：脏了才画，不在屏幕上的不画（回到屏幕上时 IntersectionObserver 再置脏） */
  frame(): void {
    if (this.dead || !this.onScreen) return
    if (this.legendDirty) { this.legendDirty = false; this.renderLegend() }
    if (this.dirty) { this.dirty = false; this.render() }
  }
  render(): void {
    const c = this.ctx, C = this.colors
    this.aw = this.axisW()
    const W = this.w, H = this.h, PW = this.plotW()
    // 图例不许压到价格轴上：窄格子里（四图、板块预览）让它在绘图区宽度内折行
    const lw = `${Math.max(120, PW - 16)}px`; if (this.legendEl.style.maxWidth !== lw) this.legendEl.style.maxWidth = lw
    c.clearRect(0, 0, W, H)
    c.fillStyle = C.bg; c.fillRect(0, 0, W, H)
    if (!this.bars.length) return
    const { from, to } = this.visible()
    const panes = this.panes()
    this._panes = panes
    const mainPane = panes[0]
    const mr = this.rangeMain(from, to); this.mainRange = mr
    this._ranges = { main: mr }
    for (const p of panes.slice(1)) this._ranges[p.id] = this.rangeSub(p.id as SubId, from, to)

    // 网格 + 价格刻度
    c.font = this.font; c.textBaseline = 'middle'
    for (const p of panes) {
      const r = this._ranges[p.id]
      const ticks = this.priceTicks(p, r)
      p.ticks = ticks
      c.strokeStyle = C.grid; c.lineWidth = LINE.hair; c.beginPath()
      for (const t of ticks) { const y = Math.round(this.priceToY(t, p, r)) + .5; c.moveTo(0, y); c.lineTo(PW, y) }
      c.stroke()
    }
    const tticks = this.timeTicks(from, to)
    c.strokeStyle = C.grid; c.beginPath()
    for (const t of tticks) { const x = Math.round(this.indexToX(t.i)) + .5; c.moveTo(x, 0); c.lineTo(x, H - AXIS_H) }
    c.stroke()

    // 主图
    c.save(); c.beginPath(); c.rect(0, mainPane.y, PW, mainPane.h); c.clip()
    const geo = this.layers.length ? this.geometry() : null
    if (geo) for (const l of this.layers) if (l.back) { c.save(); l.back(c, geo); c.restore() }
    if (this.ind.vol && this.deg.vol && !this.hidden.has('vol')) this.drawVolume(mainPane, from, to)
    if (geo) for (const l of this.layers) if (l.under) { c.save(); l.under(c, geo); c.restore() }
    if (this.walls && !this.hidden.has('walls')) this.drawWalls(mainPane, mr, from, to)
    if (this.markers) this.drawTradeSpan(mainPane, mr)
    this.drawCandles(mainPane, mr, from, to)
    for (const id of ['boll', 'ema', 'ma'] as MainId[]) if (this.series[id] && !this.hidden.has(id)) this.drawLines(id, mainPane, mr, from, to)
    drawExtraMain(this, mainPane, mr, from, to)
    this.drawLastLine(mainPane, mr)
    this.drawAlertLines(mainPane, mr)
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
    c.strokeStyle = C.scaleLine; c.lineWidth = LINE.hair; c.beginPath()
    for (const p of panes.slice(1)) { c.moveTo(0, p.y + .5); c.lineTo(W, p.y + .5) }
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
        c.fillText(p.id === 'main' ? fmtAxis(t, this.meta.dec) : this.subFmt(p.id, t), PW + 8, y)
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
    this.drawCrosshair(panes)
    this.renderPaneLegends(panes)
    if (geo) for (const l of this.layers) l.after?.(geo)
  }

  priceTicks(p: Pane, r: PriceRange): number[] {
    const n = Math.max(2, Math.floor(p.h / 56))
    if (this.log && p.id === 'main') {
      const out: number[] = [], a = Math.log(r.min), b = Math.log(r.max)
      for (let i = 1; i <= n; i++) { const v = Math.exp(a + (b - a) * i / (n + 1)); const st = niceStep(v / 20); out.push(Math.round(v / st) * st) }
      return out
    }
    const step = niceStep((r.max - r.min) / n)
    const out: number[] = []
    for (let v = Math.ceil(r.min / step) * step; v <= r.max; v += step) out.push(+v.toFixed(10))
    return out
  }
  subFmt(id: string, v: number): string { if (id === 'rsi' || id === 'kdj') return v.toFixed(0); if (id === 'oi') return fmtCompact(v); return fmtCompact(v) === '—' ? '' : (Math.abs(v) >= 1000 ? fmtCompact(v) : v.toFixed(Math.abs(v) < 10 ? 2 : 1)) }

  /** 时间轴刻度：规则在 timeAxis.ts 的纯函数里（from / to 参数沿用原型签名，不使用） */
  timeTicks(_from?: number, _to?: number): TimeTick[] {
    if (!this.bars.length) return []
    const lo = Math.max(0, Math.floor(this.xToIndex(0))), hi = Math.ceil(this.rightBar)
    return timeTicks(i => this.timeAt(i), lo, hi, this.spacing, this.iv, TIME_TICK_MIN_PX, i => this.indexToX(i))
  }

  wickW(): number { return this.spacing >= 20 ? 2 : 1 }
  candleW(): number { // 实体取间距的 3/4，再按影线的奇偶收一格，让影线正好居中；间距 < 2.5 时只剩影线
    const s = this.spacing, wick = this.wickW()
    if (s < 2.5) return 1
    let w = Math.max(3, Math.floor(s * 0.75))
    if (w % 2 !== wick % 2) w -= 1
    return Math.max(wick, w)
  }
  drawCandles(p: Pane, r: PriceRange, from: number, to: number): void {
    const c = this.ctx, C = this.colors, bw = this.candleW(), wick = this.wickW()
    const half = Math.floor(bw / 2), wh = wick >> 1
    for (const pass of [0, 1]) {
      c.fillStyle = pass ? C.up : C.down
      c.beginPath()
      for (let i = from; i <= to; i++) {
        const b = this.bars[i]; if (!b) continue
        const up = b.c >= b.o
        if ((pass === 1) !== up) continue
        const x = Math.round(this.indexToX(i))
        const yh = this.priceToY(b.h, p, r), yl = this.priceToY(b.l, p, r)
        const yo = this.priceToY(b.o, p, r), yc = this.priceToY(b.c, p, r)
        c.rect(x - wh, Math.round(yh), wick, Math.max(1, Math.round(yl) - Math.round(yh)))
        if (bw > wick) {
          const top = Math.round(Math.min(yo, yc)), bot = Math.round(Math.max(yo, yc))
          c.rect(x - half, top, bw, Math.max(1, bot - top))
        }
      }
      c.fill()
    }
  }
  drawVolume(p: Pane, from: number, to: number): void {
    const c = this.ctx, C = this.colors, bw = this.candleW()
    let mx = 0
    for (let i = from; i <= to; i++) mx = Math.max(mx, this.bars[i]?.v || 0)
    if (!mx) return
    const h = p.h * VOL_H, base = p.y + p.h
    const half = Math.floor(bw / 2)
    for (const pass of [0, 1]) {
      c.fillStyle = hexA(pass ? C.up : C.down, VOL_ALPHA)
      c.beginPath()
      for (let i = from; i <= to; i++) {
        const b = this.bars[i]; if (!b) continue
        if ((b.c >= b.o) !== (pass === 1)) continue
        const x = Math.round(this.indexToX(i)), vh = Math.max(1, b.v / mx * h)
        c.rect(x - half, Math.round(base - vh), Math.max(1, bw), Math.round(vh))
      }
      c.fill()
    }
  }
  drawLines(id: MainId, p: Pane, r: PriceRange, from: number, to: number): void {
    const c = this.ctx, cols = CATALOG[id].colors ?? [], ser = this.series[id]
    if (!ser) return
    if (id === 'boll') {
      c.fillStyle = hexA('#2962FF', 0.06); c.beginPath()
      let started = false
      for (let i = from; i <= to; i++) { const v = ser[1][i]; if (v == null) continue; const x = this.indexToX(i), y = this.priceToY(v, p, r); if (started) c.lineTo(x, y); else { c.moveTo(x, y); started = true } }
      for (let i = to; i >= from; i--) { const v = ser[2][i]; if (v == null) continue; c.lineTo(this.indexToX(i), this.priceToY(v, p, r)) }
      c.fill()
    }
    c.lineJoin = 'round'; c.lineCap = 'round'
    ser.forEach((s, k) => {
      c.lineWidth = id === 'boll' && k > 0 ? LINE.band : LINE.plot
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
  drawSub(p: Pane, r: PriceRange, from: number, to: number): void {
    const c = this.ctx, C = this.colors, id = p.id as SubId, ser = this.series[id], cols = CATALOG[id].colors ?? []
    if (!ser || this.hidden.has(id)) return
    const y = (v: number) => this.priceToY(v, p, r)
    if (id === 'macd') {
      const bw = this.candleW(), half = Math.floor(bw / 2), y0 = y(0)
      for (let i = from; i <= to; i++) {
        const v = ser[2][i]; if (v == null) continue
        const prev = ser[2][i - 1] ?? v
        const col = v >= 0 ? C.up : C.down
        c.fillStyle = (v >= 0 ? v >= prev : v <= prev) ? col : hexA(col, 0.45)
        const x = Math.round(this.indexToX(i)), yy = y(v)
        c.fillRect(x - half, Math.min(y0, yy), Math.max(1, bw), Math.max(1, Math.abs(yy - y0)))
      }
      this.polyline(ser[0], p, r, from, to, cols[0]); this.polyline(ser[1], p, r, from, to, cols[1])
    } else if (id === 'rsi') {
      const y70 = y(70), y30 = y(30)
      c.fillStyle = hexA('#7E57C2', 0.08); c.fillRect(0, y70, this.plotW(), y30 - y70)
      c.setLineDash([4, 4]); c.strokeStyle = hexA(C.text3 || '#888', 0.7); c.lineWidth = LINE.hair; c.beginPath()
      c.moveTo(0, Math.round(y70) + .5); c.lineTo(this.plotW(), Math.round(y70) + .5); c.moveTo(0, Math.round(y30) + .5); c.lineTo(this.plotW(), Math.round(y30) + .5); c.stroke(); c.setLineDash([])
      this.polyline(ser[0], p, r, from, to, cols[0])
    } else {
      drawSubLevels(this, p, r, id)
      ser.forEach((s, k) => this.polyline(s, p, r, from, to, cols[k % cols.length]))
    }
  }
  polyline(s: Series, p: Pane, r: PriceRange, from: number, to: number, col: string): void {
    const c = this.ctx; c.strokeStyle = col; c.lineWidth = LINE.plot; c.lineJoin = 'round'; c.lineCap = 'round'; c.beginPath(); let st = false
    for (let i = Math.max(0, from - 1); i <= to; i++) { const v = s[i]; if (v == null) { st = false; continue } const x = this.indexToX(i), y = this.priceToY(v, p, r); if (st) c.lineTo(x, y); else { c.moveTo(x, y); st = true } }
    c.stroke()
  }
  lastBar(): Bar | undefined { return this.bars[this.lastIndex()] }
  drawLastLine(p: Pane, r: PriceRange): void {
    const b = this.lastBar(); if (!b) return
    const c = this.ctx, y = Math.round(this.priceToY(b.c, p, r)) + .5
    c.strokeStyle = this.stale ? this.colors.text3 : (b.c >= b.o ? this.colors.up : this.colors.down)
    c.setLineDash([1, 2]); c.lineWidth = LINE.hair; c.beginPath(); c.moveTo(0, y); c.lineTo(this.plotW(), y); c.stroke(); c.setLineDash([])
  }
  drawAlertLines(p: Pane, r: PriceRange): void {
    const c = this.ctx
    for (const a of this.alertsShown()) {
      const y = Math.round(this.priceToY(a.price, p, r)) + .5
      if (y < p.y || y > p.y + p.h) continue
      c.strokeStyle = this.colors.alert; c.setLineDash([6, 4]); c.lineWidth = LINE.hair; c.beginPath(); c.moveTo(0, y); c.lineTo(this.plotW(), y); c.stroke(); c.setLineDash([])
    }
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
    const label = (y: number, text: string, bg: string, fg: string, sub?: string | null) => {
      const h = sub ? 34 : 20
      const top = clamp(y - 10, p.y, p.y + p.h - h)
      c.fillStyle = bg; roundRect(c, PW + 1, top, this.aw - 2, h, 3); c.fill()
      c.fillStyle = fg; c.textAlign = 'left'; c.font = `600 ${this.font}`
      c.fillText(text, PW + 8, top + 10)
      if (sub) { c.font = this.font; c.globalAlpha = .85; c.fillText(sub, PW + 8, top + 25); c.globalAlpha = 1 }
      c.font = this.font
    }
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
    const b = this.lastBar(); if (!b) return
    const y = this.priceToY(b.c, p, r)
    const col = this.stale ? C.text3 : (b.c >= b.o ? C.up : C.down)
    let sub: string | null = null
    if (this.replay == null && this.iv < 30 * 864e5) {
      const left = Math.max(0, b.t + this.iv - Date.now())
      const s = Math.floor(left / 1000), hh = Math.floor(s / 3600), mm = Math.floor(s % 3600 / 60), ss = s % 60
      sub = hh >= 24 ? `${Math.floor(hh / 24)}天 ${pad(hh % 24)}时` : hh ? `${pad(hh)}:${pad(mm)}:${pad(ss)}` : `${pad(mm)}:${pad(ss)}`
    }
    label(y, fmtAxis(b.c, this.meta.dec), col, '#fff', sub)
    // 十字线标签画在最上层（drawCrosshair）
  }
  drawCrosshair(panes: Pane[]): void {
    const c = this.ctx, C = this.colors, PW = this.plotW(), H = this.h
    let x: number | null = null, idx = 0
    if (this.cross) { idx = Math.round(this.xToIndex(this.cross.x)); x = this.indexToX(idx) }
    else if (this.extCross != null) { idx = Math.round(this.indexAt(this.extCross)); x = this.indexToX(idx) }
    if (x == null || x < 0 || x > PW) return
    c.strokeStyle = C.cross; c.lineWidth = LINE.hair; c.setLineDash([4, 4])
    c.beginPath(); c.moveTo(Math.round(x) + .5, 0); c.lineTo(Math.round(x) + .5, H - AXIS_H)
    let y = 0, pane: Pane | undefined
    if (this.cross) {
      const cy = this.cross.y
      y = cy
      if (this.magnet && this.cross.pane === 'main') { const b = this.bars[idx]; if (b) { const r = this._ranges.main, p = panes[0]; const cands = [b.o, b.h, b.l, b.c].map(v => this.priceToY(v, p, r)); y = cands.reduce((a, v) => Math.abs(v - cy) < Math.abs(a - cy) ? v : a) } }
      pane = panes.find(p => y >= p.y && y < p.y + p.h)
      if (pane) { c.moveTo(0, Math.round(y) + .5); c.lineTo(PW, Math.round(y) + .5) }
    }
    c.stroke(); c.setLineDash([])
    // 轴上标签
    c.font = this.font; c.textBaseline = 'middle'
    const tl = crossTimeLabel(this.timeAt(idx), this.iv)
    const tw = c.measureText(tl).width + 16
    c.fillStyle = C.crossLabel; roundRect(c, clamp(x - tw / 2, 0, PW - tw), H - AXIS_H + 2, tw, AXIS_H - 4, 3); c.fill()
    c.fillStyle = '#fff'; c.textAlign = 'center'; c.fillText(tl, clamp(x, tw / 2, PW - tw / 2), H - AXIS_H / 2)
    if (pane) {
      const r = this._ranges[pane.id], v = this.yToPrice(y, pane, r)
      const s = pane.id === 'main' ? fmtAxis(v, this.meta.dec) : this.subFmt(pane.id, v)
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
    for (const d of all) this.drawOne(d, p, r, d === this.selected || d === this.draft)
  }
  pt(q: DrawPoint, p: Pane, r: PriceRange): XY { return { x: this.indexToX(this.indexAt(q.t)), y: this.priceToY(q.p, p, r) } }
  drawOne(d: Drawing, p: Pane, r: PriceRange, sel: boolean): void {
    const c = this.ctx, PW = this.plotW(), col = d.color || '#2962FF'
    if (!d.pts.length) return
    if (drawComputed(this, d, p, r, sel)) return
    c.strokeStyle = col; c.lineWidth = d.width || LINE.draw; c.fillStyle = col; c.lineCap = d.dash === 'dotted' ? 'round' : d.dash ? 'butt' : 'round'; c.lineJoin = 'round'
    if (d.type !== 'fib' && d.type !== 'measure') c.setLineDash(dashPattern(d))
    const pts = d.pts.map(q => this.pt(q, p, r))
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
        c.fillText(`${L} (${fmt(pr, this.meta.dec)})`, x0 - 4, y + 5)
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
      if (!d.pts.length) continue
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
    const I = icon, b = this.bars[this.legendIndex()], dec = this.meta.dec
    if (!b) { this.legendEl.innerHTML = ''; return }
    const prev = this.bars[this.legendIndex() - 1]
    const chg = prev ? b.c - prev.c : b.c - b.o, pct = chg / (prev ? prev.c : b.o) * 100
    const cls = this.stale ? 'faint' : chg >= 0 ? 'up' : 'down'
    const v = (x: number) => `<span class="num ${cls}">${fmt(x, dec)}</span>`
    const tools = (id: string) => `<span class="tools"><button class="ibtn xs" data-act="toggle" data-id="${id}" data-tip="${this.hidden.has(id) ? '显示' : '隐藏'}">${I(this.hidden.has(id) ? 'eyeOff' : 'eye', 'icon-16')}</button><button class="ibtn xs" data-act="settings" data-id="${id}" data-tip="参数">${I('gear', 'icon-16')}</button><button class="ibtn xs" data-act="remove" data-id="${id}" data-tip="移除">${I('close', 'icon-16')}</button></span>`
    // 多图小格：只留品种与周期（周期是 sub 里「· 」后的第一段）
    if (this.deg.compact) {
      const iv = this.meta.sub.split('·').map(x => x.trim()).filter(Boolean)[0] || ''
      const html = `<div class="lrow compact"><span class="title">${this.meta.badge || ''}${this.meta.title}<span class="sub">${iv}</span></span></div>`
      if (this.legendEl.innerHTML !== html) this.legendEl.innerHTML = html
      this.renderPaneLegends(this._panes || [])
      return
    }
    let h = `<div class="lrow"><span class="title">${this.meta.badge || ''}${this.meta.title}<span class="sub">${this.meta.sub}</span></span>
        <span class="ohlc"><span><i>开</i>${v(b.o)}</span><span><i>高</i>${v(b.h)}</span><span><i>低</i>${v(b.l)}</span><span><i>收</i>${v(b.c)}</span>
        <span class="num ${cls}">${chg >= 0 ? '+' : ''}${fmt(chg, dec)} (${pct >= 0 ? '+' : ''}${pct.toFixed(2)}%)</span></span></div>`
    const i = this.legendIndex()
    for (const id of MAIN_IDS) {
      if (!this.ind[id]) continue
      const cat = CATALOG[id], cols = cat.colors ?? [], s = this.series[id] || []
      const extra = id === 'vpvr' ? `<button class="lchip" data-act="vpvrMode" data-id="vpvr" data-tip="看法">${VPVR_MODES.find(m => m.id === this.vpvrMode)?.label ?? ''}${I('chevronDown', 'icon-16')}</button>` : ''
      h += `<div class="lrow ${this.hidden.has(id) ? 'hidden-ind' : ''}"><span class="ind-name">${cat.name}</span><span class="ind-param">${paramText(id, this.params[id])}</span>${extra}
          <span class="vals num">${s.map((ser, k) => `<span style="color:${cols[k % cols.length]}">${fmt(ser[i], dec)}</span>`).join('')}</span>${tools(id)}</div>`
    }
    if (this.ind.vol) h += `<div class="lrow ${this.hidden.has('vol') ? 'hidden-ind' : ''}"><span class="ind-name">成交量</span><span class="vals num"><span class="${b.c >= b.o ? 'up' : 'down'}">${fmtCompact(b.v)}</span></span>${tools('vol')}</div>`
    if (this.walls) h += `<div class="lrow ${this.hidden.has('walls') ? 'hidden-ind' : ''}"><span class="ind-name">主力订单流</span><span class="ind-param">${this.meta.wallParam || ''}</span><span class="vals num"><span style="color:#8B5CF6">合约 ${this.walls.filter(w => !w.to && w.product !== 'spot').length}</span><span style="color:#06B6D4">现货 ${this.walls.filter(w => !w.to && w.product === 'spot').length}</span></span>${tools('walls')}</div>`
    this.legendEl.innerHTML = h
    this.renderPaneLegends(this._panes || [])
  }
  renderPaneLegends(panes: Pane[]): void {
    const subs = panes.slice(1)
    while (this.paneLegendEls.length < subs.length) { const e = document.createElement('div'); e.className = 'pane-legend'; this.host.appendChild(e); this.paneLegendEls.push(e); this.paneLegendKeys.push(null) }
    this.paneLegendEls.forEach((e, k) => { e.style.display = k < subs.length ? '' : 'none' })
    const i = this.legendIndex(), I = icon
    subs.forEach((p, k) => {
      const e = this.paneLegendEls[k], id = p.id as SubId, cat = CATALOG[id], cols = cat.colors ?? [], s = this.series[id] || []
      e.style.top = (p.y + 6) + 'px'
      const vals = s.map((ser, j) => {
        const val = ser[i]
        const col = id === 'macd' && j === 2 ? ((val ?? 0) >= 0 ? 'var(--up-text)' : 'var(--down-text)') : cols[j % cols.length]
        return `<span style="color:${col}">${val == null ? '—' : this.subFmt(id, val)}</span>`
      }).join('')
      const key = id + ':' + i + ':' + vals
      if (this.paneLegendKeys[k] === key) return
      this.paneLegendKeys[k] = key
      e.innerHTML = `<div class="lrow ${this.hidden.has(id) ? 'hidden-ind' : ''}"><span class="ind-name">${cat.name}</span><span class="ind-param">${paramText(id, this.params[id])}</span><span class="vals num">${vals}</span>
          <span class="tools"><button class="ibtn xs" data-act="toggle" data-id="${id}" data-tip="${this.hidden.has(id) ? '显示' : '隐藏'}">${I(this.hidden.has(id) ? 'eyeOff' : 'eye', 'icon-16')}</button><button class="ibtn xs" data-act="settings" data-id="${id}" data-tip="参数">${I('gear', 'icon-16')}</button><button class="ibtn xs" data-act="remove" data-id="${id}" data-tip="移除">${I('close', 'icon-16')}</button></span></div>`
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
      if (act === 'toggle') { if (this.hidden.has(id)) this.hidden.delete(id); else this.hidden.add(id); this.dirty = true; this.paneLegendKeys.fill(null); this.renderLegend() }
      else this.o.onLegendAction?.(id, act, btn)
    }, { signal })
    cv.addEventListener('mousemove', e => {
      const { x, y } = pos(e)
      if (this.drag) return
      const reg = this.region(x, y)
      cv.style.cursor = reg === 'price' ? 'ns-resize' : reg === 'time' ? 'ew-resize' : reg.startsWith('sep') ? 'row-resize' : 'crosshair'
      const sep = reg.startsWith('sep:') ? reg.slice(4) : null
      if (sep !== this.hoverSep) { this.hoverSep = sep; this.dirty = true }
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
        if (this.draft && this._panes) this.updateDraft(x, y, e.shiftKey)
        if (!this.tool) {
          const hit = this.editable() ? this.hitDrawing(x, y) : null
          if (hit) cv.style.cursor = hit.handle != null ? 'grab' : 'pointer'
          let soft = false
          const lh = pane?.id === 'main' && !hit ? this.layers.find(l => { const r = l.hover?.(x, y, e.clientX, e.clientY); soft = r === 'soft'; return !!r }) ?? null : null
          if (this.layerHover && this.layerHover !== lh) this.layerHover.leave?.()
          this.layerHover = lh
          if (lh && !soft) cv.style.cursor = 'pointer'
          const w = pane?.id === 'main' && !hit && !lh ? this.wallAt(x, y) : null
          if (w !== this.hoverWall) { this.hoverWall = w; this.o.onWallHover?.(w, e.clientX, e.clientY) }
          else if (w) this.o.onWallHover?.(w, e.clientX, e.clientY)
        }
        this.o.onCrosshairMove?.(this.timeAt(Math.round(this.xToIndex(x))))
      } else { this.cross = null; this.o.onCrosshairMove?.(null); if (this.layerHover) { this.layerHover.leave?.(); this.layerHover = null } }
      this.dirty = true; this.renderLegend()
    }, { signal })
    cv.addEventListener('mouseleave', () => {
      if (this.drag) return
      this.hoverSep = null
      this.cross = null; this.axisHoverY = null; this.dirty = true; this.renderLegend()
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
        if (hit && hit.handle == null && (e.metaKey || e.ctrlKey) && hit.d.type !== 'measure') { // ⌘ + 拖 = 复制一份拖走，原来那条不动
          const copy: Drawing = { ...structuredClone(hit.d), id: uid(), locked: false }
          delete copy.alert
          if (this.o.canAdd?.([copy]) === false) return
          this.drawings.push(copy); hit = { d: copy, handle: null }
        }
        if (hit) {
          this.selected = hit.d; this.o.onSelectDrawing?.(hit.d)
          const start = this.toTP(x, y), orig = hit.d.pts.map(q => ({ ...q }))
          this.drag = { kind: 'drawing', hit, start, orig, moved: false }
          this.o.onDrawDrag?.(true)
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
        d.moved = true
        if (d.hit.handle != null) {
          // ⇧ 拖端点：吸到 0° / 45° / 90°
          if (e.shiftKey && (dd.type === 'trend' || dd.type === 'ray') && dd.pts.length === 2) now = this.snapTP(dd.pts[1 - d.hit.handle], x, y)
          moveHandle(dd, d.hit.handle, now)
        } else {
          const dt = this.indexAt(now.t) - this.indexAt(d.start.t), dp = now.p - d.start.p
          dd.pts = d.orig.map(q => ({ t: this.timeAt(Math.round(this.indexAt(q.t) + dt)), p: q.p + dp }))
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
        this.rightBar = d.right0 - dx / this.spacing
        if (!this.auto && d.pane?.id === 'main' && d.r0 && this._panes) {
          const p = this._panes[0]; const k = (this.tf(d.r0.max) - this.tf(d.r0.min)) / (p.h - 16) * dy
          this.manual = { min: this.itf(this.tf(d.r0.min) + k), max: this.itf(this.tf(d.r0.max) + k) }
        }
        this.cross = null; this.maybeMore()
      } else if (d.region === 'time') {
        const f = Math.exp(dx / 200); this.spacing = clamp(d.sp0 * f, MIN_SPACING, MAX_SPACING)
        this.rightBar = d.right0; this.maybeMore()
      } else if (d.region === 'price' && d.pane?.id === 'main' && d.r0) {
        const f = Math.exp(dy / 200), mid = (this.tf(d.r0.max) + this.tf(d.r0.min)) / 2, half = (this.tf(d.r0.max) - this.tf(d.r0.min)) / 2 * f
        this.manual = { min: this.itf(mid - half), max: this.itf(mid + half) }
        if (this.auto) { this.auto = false; this.o.onAutoChange?.(false) }
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
      this.dirty = true; this.renderLegend()
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
    cv.addEventListener('wheel', e => {
      e.preventDefault()
      const { x } = pos(e)
      if (e.altKey) this.zoomPrice(Math.exp(e.deltaY * 0.002), pos(e).y) // Alt + 滚轮 = 纵向缩放
      else if (Math.abs(e.deltaX) > Math.abs(e.deltaY)) { this.rightBar += e.deltaX / this.spacing; this.maybeMore() }
      else this.zoom(Math.exp(-e.deltaY * (e.ctrlKey ? 0.01 : 0.0025)), Math.min(x, this.plotW()))
      this.dirty = true; this.renderLegend()
      if (!e.altKey) this.emitView()
    }, { passive: false, signal })
    cv.addEventListener('contextmenu', e => {
      e.preventDefault()
      const { x, y } = pos(e)
      if (this.region(x, y) !== 'plot') return
      const pane = this.paneAt(y)
      const hit = this.editable() ? this.hitDrawing(x, y) : null
      const price = pane?.id === 'main' ? this.yToPrice(y, pane, this._ranges.main) : null
      const info: ContextMenuInfo = { clientX: e.clientX, clientY: e.clientY, price, time: this.timeAt(Math.round(this.xToIndex(x))), drawing: hit?.d }
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
    if (!this.selected) return false
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
    if (this.bars.length && this.xToIndex(0) < 60 && !this.loadingMore) this.o.onNeedMore?.()
  }
  crossPrice(): number | null {
    if (!this.cross || this.cross.pane !== 'main' || !this._panes) return null
    return this.yToPrice(this.cross.y, this._panes[0], this._ranges.main)
  }
  private fontFamily(): string { return this.font.split('px ')[1] }
}

// ------------------------------------------------------------ 共用的一帧
// 十六格各自挂一个 requestAnimationFrame 循环，每帧就是十六次回调；合成一个循环，挨个问脏没脏。
const frames = new Set<TVChart>()
let frameId = 0
function tick(): void {
  frameId = 0
  for (const ch of frames) ch.frame()
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
