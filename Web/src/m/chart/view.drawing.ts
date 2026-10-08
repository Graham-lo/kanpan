// 移植自 KanpanChart/Sources/KanpanChart/ChartView+Drawing.swift
//
// 画线的交互层：画线会话（DrawingSession）、按品种投影（projectDrawings）、触摸接管、
// 落点 / 拖动 / 长按锁定、覆盖层（选中态、预览线、放大镜读数、铃铛），以及画一条线的 paintDrawing。
//
// 与 Swift 的差异：
// - Swift 是 ChartView 的扩展，存储挂在视图上；这里是一个独立的控制器（attachDrawing 返回），
//   通过 view 上预留的五个挂点（drawingInput / drawingOverlayPaint / drawingProject / drawingKeyOf /
//   onDrawingKeyChanged）接进视图。公开 API 名字照 Swift 去掉 Drawing 前后缀（drawTool → setTool 等）。
// - 触摸用 pointerId 代替 UITouch；手指位置统一问 view.gestures.location(id)。
// - 覆盖层不需要 CADisplayLink：视图换 state 时只要主图层脏了就会顺手重画覆盖层。
// - Swift 用透明层整体压 0.35；Canvas 没有透明层，逐笔乘 globalAlpha（与 renderer.drawDrawings 一致）。
// - 放大镜的底图照 Swift 用 renderer.drawPlot 另画一张离屏画布（没有 document 时不画镜头，只画读数胶囊）。
// - DrawingBook 的观察用强引用 + 显式 detach()（Swift 是 weak owner）。

import type { ChartView, DrawingInput } from './view'
import type { ChartState } from './state'
import { withOverlay } from './state'
import type { Layout, Pane, PriceMode, PriceRange, ViewWindow } from './geometry'
import { yOf, pOf, Chart } from './geometry'
import type { BarSeries } from './series'
import type { ChartColors, Hex } from './paint'
import { ChartFont, css, textWidth, textHeight, drawCentered, roundRectPath } from './paint'
import { fmtFull, fmtNum } from './format'
import { ChartGesture } from './gesture.constants'
import {
  type Drawing, type DrawingKind, type DrawPart, type DrawPoint, type DrawHit, type DrawTool,
  DrawKind, cloneDrawing, drawingIsValid, drawingEquals, drawingsEqual, drawingWith, drawingA, newDrawingID, partIndex, partAnchor,
} from './draw/drawing'
import {
  type DrawBounds, type DrawPixel, type DrawTint, type DrawTextSize, type PlacedDrawLabel, DrawGeometry,
  boundsContains, drawingGeometry,
} from './draw/geometry'
import { type DrawSnap, snapDrawPoint, movedDrawing, DrawHistory } from './draw/edit'
import { type DrawingStyle, DrawingPreferences } from './draw/archive'
import { DrawingBook, type DrawingBookChange } from './draw/book'
import { canonicalInstrument } from './draw/instrument'
import { fittedRegression } from './draw/regression'
import { AlertGeometry, alertLinePrice, type AlertLine } from './draw/alert'
import { penAlpha, penColor, prefersReducedTransparency } from './draw/pen'
import { Parts } from './view.parts'

// ------------------------------------------------------------------ 常量与反馈

/** 画线的触觉 / 提示反馈（网页没有震动，宿主拿去做提示或什么都不做）。 */
export type DrawingFeedback = 'snapped' | 'rejected' | 'removed' | 'locked' | 'unlocked'

/** 按下到抬起不超过这么久才算「点」。 */
const DRAW_TAP_MS = 500
/** 挪过这么远就算「拖着画」（ChartGesture.panSlopPt × 2）。 */
export const DRAW_DRAG_SLOP_PT = ChartGesture.panSlopPt * 2

/**
 * 一条「提醒线」（2026-10-06，照 ChartView+Drawing.swift 的 ChartAlertSignal）。
 *
 * 画线与提醒互相独立之后，提醒所挂的那条画线可能已经删掉了，或者此刻没画出来（「隐藏画线」开着、
 * 那条线自己隐藏了、对比态把画线整层收了）。提醒照常生效，图上就得有个记号告诉人「这儿还有一条会响的线」：
 * 用提醒自己存下来的那份几何（Alert.lines，和会响的那条是同一份）画一条细虚线，右端挂同一枚小铃铛。
 * 画线在、而且画出来了，就不画它——铃铛照旧挂在画线上（alerted）。图这一侧只认 id 与几何。
 */
export interface AlertSignal {
  /** 提醒 id，点中时原样交出去 */
  id: string
  /** 它挂的那条画线自己的 id（不带品种前缀）；这条线此刻画在图上时提醒线不画 */
  drawingID: string | null
  lines: AlertLine[]
}

/**
 * 此刻真画在图上的那几条提醒线：画线整层收着（隐藏画线 / options.drawings 关）就全画；
 * 否则只画「挂的那条线不在、或者那条线自己隐藏了」的。百分比轴（对比态）上价格坐标不成立，不画。
 */
export function shownAlertSignals(s: ChartState | null, signals: readonly AlertSignal[]): AlertSignal[] {
  if (!s || s.input.percentAxis || signals.length === 0) return []
  if (!s.input.options.drawings) return signals.slice()
  const visible = new Set(s.overlay.drawings.filter(d => !d.hidden).map(d => d.id))
  return signals.filter(x => x.drawingID == null || !visible.has(x.drawingID))
}

/** 一条提醒线在图区里的折线（按 6pt 采样：对数轴上直线不再是直线，时间轴也未必等距）。 */
export function alertSignalPath(line: AlertLine, axes: DrawAxes): DrawPixel[] {
  const ts = line.points.map(p => p.t)
  if (!ts.length) return []
  const lo = Math.min(...ts), hi = Math.max(...ts)
  const right = axes.layout.plotW
  const x0 = line.extendLeft ? 0 : Math.max(0, axes.x(lo))
  const x1 = line.extendRight ? right : Math.min(right, axes.x(hi))
  if (!Number.isFinite(x0) || !Number.isFinite(x1) || x1 < x0) return []
  const out: DrawPixel[] = []
  for (let x = x0; ; x = Math.min(x1, x + 6)) {
    const p = alertLinePrice(line, axes.t(x))
    if (p != null && Number.isFinite(p)) {
      const y = axes.y(p)
      if (Number.isFinite(y)) out.push({ x, y })
    }
    if (x >= x1) break
  }
  return out
}

/** 提醒线右端那枚铃铛：两端无限延的贴图区右边，有头有尾的停在最后一个点上（和画线铃铛同一个规矩）。 */
export function alertSignalBell(signal: AlertSignal, axes: DrawAxes): DrawPixel | null {
  const line = signal.lines[0]
  if (!line) return null
  const right = axes.layout.plotW
  const last = line.points.length ? Math.max(...line.points.map(p => p.t)) : 0
  const x = line.extendRight ? right - 10 : Math.min(axes.x(last), right - 10)
  if (!Number.isFinite(x) || !(x > 2)) return null
  const p = alertLinePrice(line, axes.t(x))
  if (p == null || !Number.isFinite(p)) return null
  const y = axes.y(p)
  if (!Number.isFinite(y) || !(y > axes.pane.y) || !(y < axes.pane.y + axes.pane.h)) return null
  return { x, y }
}

const segDistance = (q: DrawPixel, a: DrawPixel, b: DrawPixel): number => {
  const dx = b.x - a.x, dy = b.y - a.y, len = dx * dx + dy * dy
  const u = len > 0 ? Math.max(0, Math.min(1, ((q.x - a.x) * dx + (q.y - a.y) * dy) / len)) : 0
  return Math.hypot(q.x - (a.x + u * dx), q.y - (a.y + u * dy))
}

/** 点在哪条提醒线上（铃铛 22pt、线体 12pt 的手指靶），取最近的那条。 */
export function alertSignalHit(q: DrawPixel, axes: DrawAxes, shown: readonly AlertSignal[]): string | null {
  let best: { id: string; d: number } | null = null
  for (const signal of shown.slice().reverse()) {
    let nearest = Infinity
    const b = alertSignalBell(signal, axes)
    if (b) { const d = Math.hypot(b.x - q.x, b.y - q.y); if (d <= ChartGesture.selectedHandlePt) nearest = d }
    for (const line of signal.lines) {
      const path = alertSignalPath(line, axes)
      for (let i = 1; i < path.length; i++) { const d = segDistance(q, path[i - 1], path[i]); if (d <= 12) nearest = Math.min(nearest, d) }
    }
    if (nearest < Infinity && (!best || nearest < best.d)) best = { id: signal.id, d: nearest }
  }
  return best?.id ?? null
}

// ------------------------------------------------------------------ 坐标

/** 画线用的那套坐标：主图那一格 + 当前视野与价格区间。 */
export class DrawAxes {
  constructor(readonly o: { layout: Layout; pane: Pane; range: PriceRange; mode: PriceMode; view: ViewWindow; decimals: number }) {}
  get layout(): Layout { return this.o.layout }
  get pane(): Pane { return this.o.pane }
  get range(): PriceRange { return this.o.range }
  get mode(): PriceMode { return this.o.mode }
  get view(): ViewWindow { return this.o.view }
  get decimals(): number { return this.o.decimals }
  get bounds(): DrawBounds { return { left: 0, top: this.o.pane.y, right: this.o.layout.plotW, bottom: this.o.pane.y + this.o.pane.h } }
  x = (t: number): number => this.o.view.x(t, this.o.layout.plotW)
  y = (p: number): number => yOf(p, this.o.pane, this.o.range, this.o.mode)
  t = (x: number): number => this.o.view.t(x, this.o.layout.plotW)
  p = (y: number): number => pOf(y, this.o.pane, this.o.range, this.o.mode)
}

/** 视图此刻的画线坐标；没数据、没尺寸时 null。 */
export function drawAxesOf(view: ChartView): DrawAxes | null {
  const s = view.state
  const L = view.chartLayout, r = view.chartPriceRange
  if (!s || s.input.series.isEmpty || !L || !r) return null
  return new DrawAxes({ layout: L, pane: L.main, range: r, mode: s.viewport.price.mode, view: s.viewport.view, decimals: s.input.decimals })
}

export function measureDrawLabel(text: string): DrawTextSize {
  return { width: textWidth(text, ChartFont.axis), height: textHeight(ChartFont.axis) }
}

/** 普通渲染、选中渲染与命中共用：几何算完顺手排好标签。 */
export function drawGeometryOn(item: Drawing, axes: DrawAxes, series: BarSeries | null): DrawGeometry {
  const g = drawingGeometry(item, axes.bounds, axes.x, axes.y, axes.decimals, series)
  g.layoutLabels(axes.layout.plotW, axes.pane.y, axes.pane.h, measureDrawLabel)
  return g
}

// ------------------------------------------------------------------ 放大镜位置

/** 拖锚点时浮在手指上的那只圆镜头摆在哪儿（上面摆不下翻到下方，上下都不行就横着让开）。 */
export class DrawLoupeFrame {
  center: DrawPixel
  box: { x: number; y: number; w: number; h: number }
  scale: number
  source: { x: number; y: number; w: number; h: number }
  constructor(q: DrawPixel, plotW: number, pane: Pane, scale = 1.8) {
    const halfW = 43, halfH = 33, lift = 95
    const top = pane.y, bottom = pane.y + pane.h
    let cx = Math.max(halfW + 5, Math.min(plotW - halfW - 5, q.x))
    let cy = q.y - lift
    if (cy - halfH < top) {
      cy = q.y + lift                                   // 上面摆不下：翻到手指下方
      if (cy + halfH > bottom) {                        // 上下都摆不下：贴住能放的位置，横着让开
        cy = Math.max(top + halfH, Math.min(bottom - halfH, q.y))
        const side = q.x > plotW / 2 ? -(halfW + 20) : (halfW + 20)
        cx = Math.max(halfW + 5, Math.min(plotW - halfW - 5, q.x + side))
      }
    }
    this.center = { x: cx, y: cy }
    this.box = { x: cx - halfW, y: cy - halfH, w: halfW * 2, h: halfH * 2 }
    this.scale = scale
    this.source = { x: q.x - halfW / scale, y: q.y - halfH / scale, w: halfW * 2 / scale, h: halfH * 2 / scale }
  }
}

// ------------------------------------------------------------------ 预览计划

/** 还没落成一条线时，覆盖层该画哪些点（锚点 + 拖着画的临时起点 + 瞄准点）。 */
export class DrawingPreview {
  constructor(public tool: DrawTool, public points: DrawPoint[]) {}
  get whole(): boolean { return this.points.length === DrawKind.pointCount(this.tool) }
  static plan(tool: DrawTool | null, anchors: readonly DrawPoint[], origin: DrawPoint | null, moved: number, aim: DrawPoint | null): DrawingPreview | null {
    if (!tool) return null
    const points = anchors.slice()
    if (anchors.length === 0 && DrawKind.pointCount(tool) >= 2 && moved >= DRAW_DRAG_SLOP_PT && origin) points.push(origin)
    if (aim) points.push(aim)
    return points.length === 0 ? null : new DrawingPreview(tool, points)
  }
}

// ------------------------------------------------------------------ 命中

/**
 * 点中了哪条线的哪一部分。顺序：手柄（选中那条的手柄半径放大到 22pt、并且优先）→ 墨（线段与文字块，取最近）→ 填充。
 * 后画的在上面，所以倒着找；隐藏的线点不中。
 */
export function drawHitTest(q: DrawPixel, axes: DrawAxes, drawings: readonly Drawing[], selected: string | null,
  series: BarSeries | null, drawingsOn = true): DrawHit | null {
  if (!drawingsOn || !boundsContains(axes.bounds, q)) return null
  const shapes = drawings.slice().reverse().filter(d => !d.hidden).map(item => ({ item, geometry: drawGeometryOn(item, axes, series) }))
  let handle: { hit: DrawHit; distance: number; selected: boolean } | null = null
  for (const shape of shapes) {
    const sel = shape.item.id === selected
    const radius = sel ? ChartGesture.selectedHandlePt : Chart.hitHandlePt
    const near = shape.geometry.nearestHandle(q.x, q.y, radius)
    if (!near) continue
    const better = handle ? (handle.selected === sel ? near.distance < handle.distance : sel) : true
    if (better) handle = { hit: { id: shape.item.id, part: partAnchor(near.index) }, distance: near.distance, selected: sel }
  }
  if (handle) return handle.hit
  let ink: { hit: DrawHit; distance: number } | null = null
  for (const shape of shapes) {
    const d = shape.geometry.inkDistance(q.x, q.y)
    if (d == null) continue
    if (!ink || d < ink.distance) ink = { hit: { id: shape.item.id, part: 'body' }, distance: d }
  }
  if (ink) return ink.hit
  for (const shape of shapes) if (shape.geometry.hitsFill(q.x, q.y)) return { id: shape.item.id, part: 'body' }
  return null
}

// ------------------------------------------------------------------ 画一条线

const dashOf = (d: Drawing): number[] => (d.dash === 'solid' ? [] : d.dash === 'dashed' ? [6, 4] : [1, 3])

function paintDrawingLabels(placed: readonly PlacedDrawLabel[], ctx: CanvasRenderingContext2D, t: ChartColors, ink: (tint: DrawTint) => Hex): void {
  for (const item of placed) {
    const label = item.label
    const x = item.box.left, y = item.box.top, w = item.box.right - item.box.left, h = item.box.bottom - item.box.top
    const tint = ink(label.tint)
    if (label.plate === 'wash') {
      ctx.save()
      ctx.globalAlpha *= 0.85
      ctx.fillStyle = css(t.bg); roundRectPath(ctx, x, y, w, h, 3); ctx.fill()
      ctx.restore()
    } else if (label.plate === 'chip') {
      ctx.fillStyle = css(tint); roundRectPath(ctx, x, y, w, h, 3); ctx.fill()
    }
    drawCentered(ctx, label.text, item.center.x, item.center.y, ChartFont.axis, label.plate === 'chip' ? t.bg : tint)
  }
}

export interface PaintDrawingOptions {
  /** 画成选中态（配合 handles 画手柄） */
  selected?: boolean
  handles?: boolean
  /** false：线本身不画（拖动中，主图层那一份已经跳过，由覆盖层画 preview），只画手柄 */
  shape?: boolean
}

/**
 * 画一条线。renderer.drawDrawings 的调用 `paintDrawing(d, ctx, axes, colors, series, scale)` 保持不变；
 * 覆盖层额外传 opts（选中、手柄、shape）。scale 只为兼容签名保留：线宽照 Swift 不做像素对齐。
 */
export function paintDrawing(d: Drawing, ctx: CanvasRenderingContext2D, axes: DrawAxes, t: ChartColors,
  series: BarSeries | null = null, _scale = 1, opts: PaintDrawingOptions = {}): void {
  const selected = opts.selected ?? false, handles = opts.handles ?? false, shape = opts.shape ?? true
  const g = drawingGeometry(d, axes.bounds, axes.x, axes.y, axes.decimals, series)
  const placedLabels = g.layoutLabels(axes.layout.plotW, axes.pane.y, axes.pane.h, measureDrawLabel)
  if (d.hidden) return
  // 一条线上所有的墨都出自这一支笔（DrawPen）：没挑过颜色就跟皮肤。
  const color = penColor(d.color, t)
  ctx.save()
  try {
    ctx.beginPath(); ctx.rect(axes.bounds.left, axes.bounds.top, axes.layout.plotW, axes.pane.h); ctx.clip()
    const paint = (tint: DrawTint): Hex => (tint === 'line' ? color : tint === 'up' ? t.up : t.down)
    ctx.strokeStyle = css(color); ctx.lineWidth = d.lineWidth
    ctx.lineCap = 'butt'; ctx.lineJoin = 'miter'
    ctx.setLineDash(dashOf(d))
    // 「背景填充」开关在几何那一层已经收过了（drawingGeometry），这里照几何给的原样画。
    if (shape) {
      for (const fill of g.fills) {
        const first = fill.points[0]
        if (!first) continue
        ctx.save()
        ctx.globalAlpha *= fill.opacity ?? 0.12
        ctx.fillStyle = css(paint(fill.tint))
        ctx.beginPath(); ctx.moveTo(first.x, first.y)
        for (let i = 1; i < fill.points.length; i++) ctx.lineTo(fill.points[i].x, fill.points[i].y)
        ctx.closePath(); ctx.fill()
        ctx.restore()
      }
    }
    if (shape) {
      for (const line of g.segments) {
        ctx.strokeStyle = css(paint(line.tint))
        if (line.dashed) ctx.setLineDash([4, 3])
        ctx.beginPath(); ctx.moveTo(line.a.x, line.a.y); ctx.lineTo(line.b.x, line.b.y); ctx.stroke()
        if (line.dashed) ctx.setLineDash(dashOf(d))
      }
      paintDrawingLabels(placedLabels, ctx, t, paint)
    }
    if (selected && handles) {
      ctx.setLineDash([])
      const a = drawingA(d)
      const points: DrawPixel[] = g.handles.length === 0
        ? [{ x: d.kind === 'hline' ? axes.layout.plotW / 2 : axes.x(a.t), y: d.kind === 'vline' ? axes.pane.y + axes.pane.h / 2 : axes.y(a.p) }]
        : g.handles
      for (const p of points) {
        ctx.beginPath(); ctx.ellipse(p.x, p.y, 6, 6, 0, 0, Math.PI * 2)
        ctx.fillStyle = css(t.panel); ctx.fill()
        ctx.strokeStyle = css(color); ctx.lineWidth = 1.5; ctx.stroke()
      }
    }
  } finally {
    ctx.restore()
  }
}

// ------------------------------------------------------------------ 会话

interface Drag { id: string; part: DrawPart; from: Drawing; start: DrawPixel }
type StateUpdate = (s: ChartState) => ChartState
const same: StateUpdate = s => s
/** 收掉「正在拖的那条」的预览 id：底层按它跳过那条线，留着它那条线就只剩覆盖层里的旧预览。 */
const clearPreviewID: StateUpdate = s => (s.overlay.drawingPreviewID == null ? s : withOverlay(s, { drawingPreviewID: null }))

/** 画线控制器：一张图一个（DrawingSession + ChartView+Drawing 的公开 API）。 */
export class DrawingController {
  // ---- 会话状态（DrawingSession）
  private _tool: DrawTool | null = null
  private _selected: string | null = null
  anchors: DrawPoint[] = []
  get pending(): DrawPoint | null { return this.anchors[0] ?? null }
  set pending(v: DrawPoint | null) { this.anchors = v ? [v] : [] }
  styles: Record<string, DrawingStyle> = {}
  variants: Record<string, DrawingKind> = {}
  private _continuous = false
  private _magnet = true
  navigating = false
  aim: DrawPoint | null = null
  origin: DrawSnap | null = null
  lastSnap: DrawSnap | null = null
  preview: Drawing | null = null
  loupe: CanvasImageSource | null = null
  /** 放大镜底图那张画布：建一次反复用（见 captureLoupe）。 */
  private loupeCanvas: HTMLCanvasElement | null = null
  drag: Drag | null = null
  committing = false
  claimed: number | null = null
  /** 不在画线态时收手：点中旧线也不选中（宿主进出画线态时切）。 */
  editable = true
  startPoint: DrawPixel = { x: 0, y: 0 }
  beganMs = 0
  moved = 0
  lockTouch: number | null = null
  private lockPress: ReturnType<typeof setTimeout> | null = null
  /** 落成了几条（测试与宿主统计用）。 */
  commits = 0
  private _alerted = new Set<string>()
  private _signals: AlertSignal[] = []
  /** 点中一条提醒线或它的铃铛（不在画线态也认：它不是画线）。外面拿提醒 id 去开提醒 */
  onSignalTap: ((id: string) => void) | null = null

  // ---- 回调
  onChanged: ((items: Drawing[]) => void) | null = null
  onState: (() => void) | null = null
  onFull: (() => void) | null = null
  onCommitted: ((d: Drawing) => void) | null = null
  onDragged: ((d: Drawing) => void) | null = null
  onFeedback: ((kind: DrawingFeedback) => void) | null = null

  // ---- 本与投影键
  private _book: DrawingBook
  bound = false
  private keyCache: { raw: string; key: string } = { raw: '', key: '' }
  private key: string | null = null
  private readonly input: DrawingInput

  constructor(readonly view: ChartView) {
    this._book = new DrawingBook()
    this._book.observe(this, c => this.bookChanged(c))
    this.input = {
      began: (ids, now) => this.touchesBegan(ids, now),
      moved: (ids, now) => this.touchesMoved(ids, now),
      ended: (ids, now, cancelled) => this.touchesEnded(ids, now, cancelled),
    }
  }

  // ================================================================ 本与投影

  get book(): DrawingBook { return this._book }

  /** 接到共享的那本线（宿主的 DrawingBook）；之后线只从本里来。 */
  bindDrawings(book: DrawingBook): void {
    if (this.bound && this._book === book) return
    this._book.stopObserving(this)
    this._book = book
    this.bound = true
    book.observe(this, c => this.bookChanged(c))
    this.reproject()
  }

  /** 视图收到的每份 state 先过这里：线换成本里这一桶（projectDrawings）。 */
  project(incoming: ChartState): ChartState {
    const raw = incoming.input.series.symbol
    if (raw !== this.keyCache.raw || this.keyCache.key === '') this.keyCache = { raw, key: canonicalInstrument(raw) }
    const key = this.keyCache.key
    const book = this._book
    if (!this.bound && !drawingsEqual(incoming.overlay.drawings, book.items(key))) book.mirror(incoming.overlay.drawings, key)
    const items = book.items(key)
    // 值相同就留着原来的数组：视图按引用比脏位，不能每份 state 都换一个新 []
    const drawings = incoming.overlay.drawings === items || drawingsEqual(incoming.overlay.drawings, items) ? incoming.overlay.drawings : items
    const patch: { drawings?: Drawing[]; drawingPreviewID?: null } = {}
    if (drawings !== incoming.overlay.drawings) patch.drawings = drawings
    if (key !== this.key && incoming.overlay.drawingPreviewID != null) patch.drawingPreviewID = null
    return Object.keys(patch).length ? withOverlay(incoming, patch) : incoming
  }

  /** 视图记下的投影键（projectDrawings 刚算好的那个）。 */
  keyOf(_s: ChartState): string { return this.keyCache.key }

  keyDidChange(from: string | null): void {
    this.key = this.keyCache.key
    if (from != null) this.resetInteraction()
    this.changed()
  }

  /**
   * 刚装上时接住投影键。视图的投影键是它自己记着的：同一张图上一个控制器摘下之后它还记着那只品种，
   * 新装的控制器投影出来还是同一个键，视图就不会再喊 onDrawingKeyChanged——新控制器的键一直是空的，
   * 落笔、撤销、提交全都悄悄不生效。所以装上时自己对一次：投影过了、键还没接上，就当第一次有了品种。
   */
  adoptKey(): void {
    if (this.key == null && this.keyCache.key !== '' && this.view.state) this.keyDidChange(null)
  }

  private reproject(update: StateUpdate = same): void {
    const s = this.view.state
    const key = this.key
    if (!s || key == null) return
    const items = this._book.items(key)
    const patched = update(s)
    if (drawingsEqual(s.overlay.drawings, items) && patched === s) return
    this.view.state = drawingsEqual(patched.overlay.drawings, items) ? patched : withOverlay(patched, { drawings: items })
  }

  private commitDrawings(next: Drawing[], update: StateUpdate = same): boolean {
    const key = this.key
    if (key == null) return false
    this.committing = true
    let wrote = false
    try { wrote = this._book.commit(next, key) } finally { this.committing = false }
    this.reproject(update)
    return wrote
  }

  private bookChanged(change: DrawingBookChange): void {
    const key = this.key
    if (key == null) return
    // 别处改了这只（另一张图、同步整批换进来、setDrawings 整桶换）也把最终的线交给 onChanged：
    // 宿主靠它对账画线提醒，线被同步删了提醒要跟着撤，不能只重画
    if (change.kind === 'edited') {
      if (change.key !== key || this.committing) return
      // 正拖着的那条在真值里没了（另一台设备同步删了它、另一张图上删 / 清空）：拖动当场作废，
      // 预览、放大镜、预览 id 一起收；手指还按着，剩下的移动和抬手都落空（审查 B·拖动残留）。
      const drag = this.drag
      const gone = drag != null && !this._book.items(key).some(d => d.id === drag.id)
      this.reproject(gone ? this.dropDrag() : same)
      if (this._selected != null && !this.drawings.some(d => d.id === this._selected)) this._selected = null
      this.changed(this.drawings)
    } else {
      if (!change.keys.has(key)) return
      this.resetInteraction()
      this.reproject(s => (s.overlay.drawingPreviewID == null ? s : withOverlay(s, { drawingPreviewID: null })))
      this.changed(this.drawings)
    }
  }

  private resetInteraction(): void {
    this.cancelLockPress()
    this.preview = null
    this._selected = null
    this.pending = null
    this.aim = null
    this.origin = null
    this.drag = null
    this._tool = null
    this.claimed = null
    this.navigating = false
  }

  /**
   * 手指正拖着一条线时，线被按钮改了（撤销 / 重做、删除、清空、全部隐藏、改样式）：这一程拖动作废。
   *
   * 拖动途中线只画在预览里，真值里还是按下时那条；按钮一改真值，预览就成了过期的一份——
   * 留着它，抬手会把过期那份写回去（隐藏了的又显出来、改的样式被冲掉），预览 id 也一直挂着，
   * 底层按它跳过这条线（撤销回来的线整条看不见）。手指本身还留在 claimed 上：抬手照常走
   * 那条路解钉坐标轴，只是不再有东西可落。返回给 reproject 用的「收预览 id」。
   */
  private dropDrag(): StateUpdate {
    this.drag = null
    this.preview = null
    this.loupe = null
    return clearPreviewID
  }

  private feedback(kind: DrawingFeedback): void { this.onFeedback?.(kind) }

  /** didMoveToWindow(nil)：半截手势、预览、放大镜全部收掉。 */
  teardown(): void {
    this.cancelLockPress()
    this.claimed = null
    this.drag = null
    this.preview = null
    this.aim = null
    this.origin = null
    this.lastSnap = null
    this.loupe = null
    this.view.gestures.cancelAxisFreeze()
    // 拖动作废了，「正在拖的那条」的预览 id 也得收：底层按它跳过这条线，摘下控制器之后覆盖层不再画它，
    // 留着它这条线就整条看不见（Swift 的 teardownDrawingLink 也漏了这一步）。
    const s = this.view.state
    if (s && s.overlay.drawingPreviewID != null) this.view.state = withOverlay(s, { drawingPreviewID: null })
  }

  /** 图销毁时由视图调（view.drawingTeardown）。 */
  readonly teardownHook = (): void => this.detach()

  /** 从视图上拆下来（挂点全部清空、退订本）。 */
  detach(): void {
    this.teardown()
    this._book.stopObserving(this)
    // 底图的位图立刻放掉（Safari 要等 GC 才收整张画布的内存）
    if (this.loupeCanvas) { this.loupeCanvas.width = 0; this.loupeCanvas.height = 0; this.loupeCanvas = null }
    const v = this.view
    if (v.drawingInput === this.input) v.drawingInput = null
    v.drawingOverlayPaint = null
    v.drawingProject = null
    v.drawingKeyOf = null
    v.onDrawingKeyChanged = null
    if (v.signalTap === this.signalTapHook) v.signalTap = null
    if (v.drawingTeardown === this.teardownHook) v.drawingTeardown = null
    v.refreshDrawingOverlay()
  }

  // ================================================================ 公开 API

  /** 覆盖层接不接触摸（drawingInteractive）。attachDrawing 之后默认接。 */
  get interactive(): boolean { return this.view.drawingInput === this.input }
  set interactive(on: boolean) {
    if (on) this.view.drawingInput = this.input
    else if (this.view.drawingInput === this.input) this.view.drawingInput = null
  }

  get tool(): DrawTool | null { return this._tool }
  /** 拿起 / 放下工具（drawTool）：半截的点、选中、十字线一起收掉。 */
  setTool(tool: DrawTool | null): void {
    if (this._tool === tool) return
    this._tool = tool
    this.pending = null
    this.aim = null
    this.origin = null
    this._selected = null
    const s = this.view.state
    if (s && s.overlay.crosshair != null) this.view.state = withOverlay(s, { crosshair: null })
    if (tool != null) this.interactive = true
    this.changed()
  }

  get selected(): string | null { return this._selected }
  set selected(id: string | null) {
    if (this._selected === id) return
    this._selected = id
    this.changed()
  }

  get drawings(): Drawing[] { return this.view.state?.overlay.drawings ?? [] }

  /** 整桶换掉（切品种之类）：清撤销栈与交互。 */
  setDrawings(items: Drawing[]): void {
    if (!this.view.state || this.key == null) return
    this._book.replaceBucket(items, this.key)
  }

  get placedAnchors(): number { return this.anchors.length }

  get alerted(): ReadonlySet<string> { return this._alerted }
  set alerted(v: ReadonlySet<string>) {
    if (v.size === this._alerted.size && [...v].every(id => this._alerted.has(id))) return
    this._alerted = new Set(v)
    this.view.refreshDrawingOverlay()
  }

  /** 提醒线（见 AlertSignal）：外面把这只品种上还在生效的画线提醒整份扔进来，画哪几条由图按「那条画线此刻画没画出来」定 */
  get signals(): readonly AlertSignal[] { return this._signals }
  set signals(v: readonly AlertSignal[]) {
    if (JSON.stringify(v) === JSON.stringify(this._signals)) return
    this._signals = v.slice()
    this.view.refreshDrawingOverlay()
  }
  /** 此刻真画在图上的那几条提醒线 */
  get shownSignals(): AlertSignal[] { return shownAlertSignals(this.view.state, this._signals) }

  /** 一下轻点落在提醒线上：交给 onSignalTap，返回真表示这一下被吃掉了（view.signalTap，手势层在判十字线之前问） */
  readonly signalTapHook = (x: number, y: number): boolean => {
    const axes = drawAxesOf(this.view)
    if (!this.onSignalTap || !axes || this._tool != null) return false
    const id = alertSignalHit({ x, y }, axes, this.shownSignals)
    if (id == null) return false
    this.onSignalTap(id)
    return true
  }

  get continuous(): boolean { return this._continuous }
  set continuous(v: boolean) { this._continuous = v; this.changed() }
  get magnet(): boolean { return this._magnet }
  set magnet(v: boolean) { this._magnet = v; this.changed() }

  updateDrawing(item: Drawing): void {
    const next = this.drawings.slice()
    const i = next.findIndex(d => d.id === item.id)
    if (!drawingIsValid(item) || i < 0 || drawingEquals(next[i], item)) return
    next[i] = item
    this.commitDrawings(next, this.dropDrag()); this.changed(this.drawings)
  }

  /** 复制选中那条：往右下各挪 20pt，解锁、显示，选中新的那条。 */
  duplicateSelected(): void {
    const item = this.drawings.find(d => d.id === this._selected)
    const axes = drawAxesOf(this.view)
    const key = this.key
    if (!item || !axes || key == null) return
    if (!this._book.hasRoom(key)) { this.onFull?.(); return }
    let copy = cloneDrawing(item); copy.locked = false; copy.hidden = false
    copy = movedDrawing(copy, 'body', axes.view.span * 20 / axes.layout.plotW, p => axes.p(axes.y(p) + 20))
    copy = { ...copy, id: newDrawingID() }
    this.commitDrawings(this.drawings.concat([copy]))
    this._selected = copy.id; this.changed(this.drawings)
  }

  clear(): void {
    if (!this.view.state || this.drawings.length === 0) return
    this.commitDrawings([], this.dropDrag())
    this._selected = null; this.pending = null; this.aim = null; this.origin = null
    this.feedback('removed')
    this.changed([])
  }

  setAllHidden(hidden: boolean): void {
    const cur = this.drawings
    if (!this.view.state || !cur.some(d => d.hidden !== hidden)) return
    this.commitDrawings(cur.map(d => (d.hidden === hidden ? d : { ...d, hidden })), this.dropDrag())
    this._selected = null; this.changed(this.drawings)
  }

  deleteSelected(): void {
    const sel = this._selected
    if (!this.view.state || sel == null || !this.drawings.some(d => d.id === sel)) return
    this.commitDrawings(this.drawings.filter(d => d.id !== sel), this.dropDrag())
    this._selected = null
    this.feedback('removed')
    this.changed(this.drawings)
  }

  /** 在某个价位落一条水平线（十字线菜单「画水平线」）；t 缺省取十字线那根或最后一根。 */
  addHorizontalLine(price: number, t?: number): boolean {
    const s = this.view.state
    const key = this.key
    if (!Number.isFinite(price) || !s || !(s.input.series.count > 0) || key == null) return false
    if (!this._book.hasRoom(key)) {
      this.feedback('rejected')
      this.onFull?.()
      return false
    }
    const series = s.input.series
    const c = s.overlay.crosshair
    const stamp = t ?? series.time(c ? Math.min(Math.max(c.index, 0), series.count - 1) : series.count - 1)
    const item = drawingWith('hline', [{ t: stamp, p: price }])
    const style = Object.prototype.hasOwnProperty.call(this.styles, 'hline') ? this.styles.hline : undefined
    if (style) { item.color = style.color; item.lineWidth = style.lineWidth; item.levels = style.levels.slice() }
    if (!drawingIsValid(item)) return false
    this.commitDrawings(this.drawings.concat([item]))
    this.feedback('snapped')
    this.changed(this.drawings)
    this.commits += 1
    this.onCommitted?.(item)
    return true
  }

  /** 完成：放下工具、取消选中，线都留着。 */
  endDrawing(): void {
    this._tool = null
    this.pending = null
    this.aim = null
    this.origin = null
    this._selected = null
    this.drag = null
    this.claimed = null
    this.preview = null
    const s = this.view.state
    if (s && s.overlay.drawingPreviewID != null) this.view.state = withOverlay(s, { drawingPreviewID: null })
    this.changed()
  }

  get history(): DrawHistory { return this.key != null ? this._book.history(this.key) : new DrawHistory() }
  set history(h: DrawHistory) { if (this.key != null) this._book.setHistory(h, this.key) }

  get canUndo(): boolean { return this.anchors.length > 0 || this.history.canUndo }
  get canRedo(): boolean { return this.history.canRedo }

  /** 撤销：先退半截的锚点，没有了才退已落成的线。 */
  undo(): void {
    if (this.anchors.length > 0) {
      this.anchors = this.anchors.slice(0, -1); this.aim = null; this.origin = null
      this.changed(); return
    }
    const key = this.key
    if (!this.view.state || key == null) return
    this.committing = true
    let moved = false
    try { moved = this._book.undo(key) } finally { this.committing = false }
    if (!moved) return
    this.reproject(this.dropDrag())
    this.afterHistoryJump(this.drawings)
  }

  redo(): void {
    const key = this.key
    if (!this.view.state || key == null) return
    this.committing = true
    let moved = false
    try { moved = this._book.redo(key) } finally { this.committing = false }
    if (!moved) return
    this.reproject(this.dropDrag())
    this.afterHistoryJump(this.drawings)
  }

  private afterHistoryJump(items: Drawing[]): void {
    this.pending = null
    this.aim = null
    this.origin = null
    this.drag = null
    if (this._selected != null && !items.some(d => d.id === this._selected)) this._selected = null
    this.changed(items)
  }

  /** drawingChanged：重画覆盖层，线变了叫外面存盘，状态变了叫面板刷新。 */
  private changed(items?: Drawing[]): void {
    this.view.refreshDrawingOverlay()
    if (items) this.onChanged?.(items)
    this.onState?.()
  }

  // ================================================================ 触摸

  private get gs() { return this.view.gestures }
  private get g() { return this.view.gesture }
  private loc(id: number): DrawPixel { return this.gs.location(id) }

  private drawPoint(q: DrawPixel, axes: DrawAxes): DrawSnap {
    const s = this.view.state
    if (!s) return { point: { t: 0, p: 0 }, index: -1 }
    const px = Math.max(0, Math.min(axes.layout.plotW, q.x))
    const py = Math.max(axes.pane.y, Math.min(axes.pane.y + axes.pane.h, q.y))
    const snap = snapDrawPoint(axes.t(px), axes.p(py), s.input.series, this._magnet, axes.x, axes.y, 10, this.lastSnap)
    this.lastSnap = snap.index >= 0 ? snap : null
    return snap
  }

  private hitTest(q: DrawPixel, axes: DrawAxes): DrawHit | null {
    const s = this.view.state
    return drawHitTest(q, axes, this.drawings, this._selected, s?.input.series ?? null, s?.input.options.drawings === true)
  }

  touchesBegan(ids: number[], now: number): void {
    this.cancelLockPress()
    this.beganMs = now
    const claimed = this.claimed
    if (claimed != null) {
      if (ids.includes(claimed)) return
      // 第二根手指落下：半截的画线 / 拖动全部作废，两根手指交给图去捏合
      const s = this.view.state
      if (this.drag != null && s) this.view.state = withOverlay(s, { drawingPreviewID: null })
      this.loupe = null
      this.preview = null; this.drag = null; this.claimed = null; this.aim = null; this.origin = null
      this.lastSnap = null
      this.navigating = true
      this.gs.cancelAxisFreeze()
      this.gs.touchesBegan([claimed, ...ids.filter(i => i !== claimed)], now)
      this.changed(); return
    }
    if (!this.editable) { this.gs.touchesBegan(ids, now); return }
    if (this.g.touches.length > 0) {
      this.navigating = true
      this.gs.touchesBegan(ids, now)
      return
    }
    const axes = drawAxesOf(this.view)
    if (ids.length !== 1 || !axes) { this.gs.touchesBegan(ids, now); return }
    const id = ids[0]
    const q = this.loc(id)
    if (!boundsContains(axes.bounds, q)) { this.gs.touchesBegan(ids, now); return }
    this.startPoint = { ...q }
    this.moved = 0
    this.lastSnap = null
    if (this.pending != null) {
      this.claimed = id
      this.gs.beginAxisFreeze()
      this.captureLoupe()
      this.aimPending(q, axes, true)
      return
    }
    if (this._tool != null && this.anchors.length === 0) {
      this.claimed = id
      this.gs.beginAxisFreeze()
      this.captureLoupe()
      this.origin = this.drawPoint(q, axes)
      this.aimPending(q, axes, true)
      return
    }
    const s0 = this.view.state
    const pressed = this._tool == null && s0?.overlay.crosshair == null ? this.hitTest(q, axes) : null
    if (pressed) this.scheduleLockPress(pressed.id, id)
    const from = pressed ? this.drawings.find(d => d.id === pressed.id) : undefined
    if (this._tool == null && pressed && this._selected === pressed.id && from && !from.locked && s0) {
      this.claimed = id
      this._selected = pressed.id
      this.gs.beginAxisFreeze()
      this.captureLoupe()
      this.preview = from
      this.drag = { id: pressed.id, part: pressed.part, from, start: { ...q } }
      // 拖线的时候十字线碍事
      this.view.state = withOverlay(this.view.state ?? s0, { drawingPreviewID: from.id, crosshair: null })
      this.changed()
      return
    }
    this.gs.touchesBegan(ids, now)
    if (this._tool != null || pressed != null) this.g.cancelLongPress()
  }

  touchesMoved(ids: number[], now: number): void {
    const lt = this.lockTouch
    if (lt != null && ids.includes(lt)) {
      const q = this.loc(lt)
      if (Math.hypot(q.x - this.startPoint.x, q.y - this.startPoint.y) > ChartGesture.longPressSlopPt) this.cancelLockPress()
    }
    const t = this.claimed
    const axes = drawAxesOf(this.view)
    if (t == null || !ids.includes(t) || !axes) { this.gs.touchesMoved(now, ids); return }
    const q = this.loc(t)
    this.moved = Math.max(this.moved, Math.hypot(q.x - this.startPoint.x, q.y - this.startPoint.y))
    if (this.drag) this.applyDrag(q, axes)
    else if (this._tool != null) this.aimPending(q, axes)
  }

  touchesEnded(ids: number[], now: number, cancelled: boolean): void {
    const lt = this.lockTouch
    if (lt != null && ids.includes(lt)) this.cancelLockPress()
    const t = this.claimed
    if (t == null || !ids.includes(t)) { this.finishUnclaimed(ids, now, cancelled); return }
    this.claimed = null
    try {
      this.loupe = null
      const axes = drawAxesOf(this.view)
      const drag = this.drag
      if (drag) {
        const preview = this.preview
        this.drag = null; this.preview = null
        const clearPreview: StateUpdate = s => (s.overlay.drawingPreviewID == null ? s : withOverlay(s, { drawingPreviewID: null }))
        // 拖到一半这条线没了：拖动整个作废。原来「线还在」和「在拖」写在同一个条件里，线一没就掉进
        // 下面落笔那条路，drag / preview / 预览 id 全留着——读数胶囊挂在图上，下一次落笔的手指还被
        // 当成在拖那条已不存在的线（ChartView+Drawing.swift，审查 B·拖动残留）。
        const i = this.drawings.findIndex(d => d.id === drag.id)
        if (i < 0) {
          this.reproject(clearPreview)
          this.changed()
          return
        }
        const cur = this.drawings
        const next = cur.slice()
        if (!cancelled && preview) next[i] = preview
        if (!cancelled && !drawingEquals(next[i], cur[i])) {
          this.commitDrawings(next, clearPreview)
          this.changed(this.drawings)
        } else {
          this.reproject(clearPreview)
          this.changed()
        }
        return
      }
      const origin = this.origin
      this.origin = null
      const tool = this._tool
      if (!axes || tool == null) return
      if (cancelled) {
        this.aim = null
        this.changed()
        return
      }
      const q = this.loc(t)
      if (this.anchors.length > 0) { this.placeAt(q, axes); return }
      this.aim = null
      if (DrawKind.pointCount(tool) === 1) { this.placeAt(q, axes); return }
      if (this.moved >= DRAW_DRAG_SLOP_PT && origin) {
        this.place(origin, axes)
        this.placeAt(q, axes)
      } else {
        this.placeAt(this.startPoint, axes)
      }
    } finally {
      this.gs.endAxisFreeze()
      this.lastSnap = null
    }
  }

  private finishUnclaimed(ids: number[], now: number, cancelled: boolean): void {
    const g = this.g
    const isTap = !this.navigating && !cancelled && g.mode === 'pan' && g.moved < ChartGesture.panSlopPt
      && !g.cameFromPinch && now - this.beganMs < DRAW_TAP_MS
    const busy = this.view.state?.overlay.crosshair != null
    const axes = drawAxesOf(this.view)
    if (isTap && !busy && axes && boundsContains(axes.bounds, g.startPoint)) {
      const q = { ...g.startPoint }
      const hit = this.editable ? this.hitTest(q, axes) : null
      if (hit != null || this._selected != null) {
        g.mode = null   // consumeTap：这一下归画线，图不再当轻点处理
        this.gs.finishTouches(ids, now, false)
        this._selected = hit?.id ?? null
        this.changed()
        return
      }
    }
    this.gs.finishTouches(ids, now, cancelled)
    if (g.touches.length === 0) this.navigating = false
  }

  private scheduleLockPress(id: string, touch: number): void {
    this.lockTouch = touch
    this.lockPress = setTimeout(() => {
      if (this.lockTouch !== touch) return
      this.lockPress = null; this.lockTouch = null
      this.toggleLock(id, touch)
    }, ChartGesture.longPressMs)
  }

  cancelLockPress(): void {
    if (this.lockPress != null) clearTimeout(this.lockPress)
    this.lockPress = null; this.lockTouch = null
  }

  /** 长按一条线：锁上 / 解开，并选中它。 */
  private toggleLock(id: string, touch: number): void {
    const i = this.drawings.findIndex(d => d.id === id)
    if (!this.editable || this._tool != null || i < 0) return
    if (this.claimed === touch) {
      this.drag = null; this.preview = null; this.loupe = null
    } else {
      this.g.cancelLongPress()
      this.g.mode = null
    }
    const next = this.drawings.slice()
    next[i] = { ...next[i], locked: !next[i].locked }
    const locked = next[i].locked
    this._selected = id
    this.commitDrawings(next, s => (s.overlay.drawingPreviewID == null ? s : withOverlay(s, { drawingPreviewID: null })))
    this.changed(this.drawings)
    this.feedback(locked ? 'locked' : 'unlocked')
  }

  private aimPending(q: DrawPixel, axes: DrawAxes, began = false): void {
    const snap = this.drawPoint(q, axes)
    this.aim = snap.point
    if (began && snap.index >= 0) this.feedback('snapped')
    this.view.refreshDrawingOverlay()
  }

  private placeAt(q: DrawPixel, axes: DrawAxes): void { this.place(this.drawPoint(q, axes), axes) }

  private place(snap: DrawSnap, axes: DrawAxes): void {
    const s = this.view.state
    const tool = this._tool
    const key = this.key
    if (!s || tool == null || key == null) return
    const pt = snap.point
    const commit = (item: Drawing): void => {
      if (!this._book.hasRoom(key)) {
        this.feedback('rejected')
        this.pending = null
        this.aim = null
        this.onFull?.()
        this.changed()
        return
      }
      this.commitDrawings(this.drawings.concat([item]))
      this._tool = this._continuous ? tool : null
      this._selected = this._continuous ? null : item.id
      this.pending = null
      this.aim = null
      if (snap.index >= 0) this.feedback('snapped')
      this.changed(this.drawings)
      this.commits += 1
      this.onCommitted?.(item)
    }
    const last = this.anchors[this.anchors.length - 1]
    if (last && Math.hypot(axes.x(last.t) - axes.x(pt.t), axes.y(last.p) - axes.y(pt.p)) < 3) return
    let points = this.anchors.concat([pt])
    if (points.length === DrawKind.placeCount(tool)) {
      if (tool === 'regression') {
        const fitted = fittedRegression(points, s.input.series)
        if (!fitted) { this.feedback('rejected'); return }
        points = fitted
      }
      commit(DrawingPreferences.newDrawing(tool, points, this.styles, this.variants))
    } else {
      this.anchors = points; this.aim = null
      if (snap.index >= 0) this.feedback('snapped')
      this.changed()
    }
  }

  private applyDrag(q: DrawPixel, axes: DrawAxes): void {
    const drag = this.drag
    if (!drag) return
    const dx = q.x - drag.start.x, dy = q.y - drag.start.y
    let item = movedDrawing(drag.from, drag.part, dx / axes.layout.plotW * axes.view.span, p => axes.p(axes.y(p) + dy))
    if (drag.part !== 'body') {
      const index = partIndex(drag.part) ?? 0
      if (index < item.points.length) {
        if (item === drag.from) item = cloneDrawing(item)
        item.points[index] = this.drawPoint(q, axes).point
      }
    }
    this.preview = item
    this.view.refreshDrawingOverlay()
    this.onDragged?.(item)
  }

  /** 按下那一刻把主图层另画一张（放大镜的底图）。 */
  private captureLoupe(): void {
    const v = this.view
    const r = v.renderer
    if (!r || typeof document === 'undefined' || !(v.width > 0) || !(v.height > 0)) return
    // 画布建一次反复用。iOS Safari 的画布内存有总上限，一张 3 倍屏的整屏底图十几 MB，
    // 每按一下新建一张、等 GC 慢慢收，连着画几十下就顶到上限，之后新画布一律拿不到上下文。
    // 每次照样重设宽高：尺寸跟着转屏走，而且重设会把上一次的内容和绘图状态一并清掉。
    const c = this.loupeCanvas ?? (this.loupeCanvas = document.createElement('canvas'))
    c.width = Math.max(1, Math.round(v.width * v.scale)); c.height = Math.max(1, Math.round(v.height * v.scale))
    const ctx = c.getContext('2d')
    if (!ctx) return
    ctx.setTransform(v.scale, 0, 0, v.scale, 0, 0)
    r.drawPlot(ctx, v.width, v.height, v.scale)
    this.loupe = c
  }

  // ================================================================ 覆盖层

  /** 系统「降低透明度」此刻开没开（每次画覆盖层时读一次，设置一变下一帧就跟上）。 */
  private get reduceTransparency(): boolean { return prefersReducedTransparency() }

  /**
   * 把「选中哪条、系统降不降透明度」交给底图：没选中的线按 DRAW_REST_ALPHA 退后一步，选中的那条画满。
   * 选中散在各处改（_selected），覆盖层每次重画都会走到这里，对不上就让底图重画一次。
   */
  private syncFocus(): void {
    const r = this.view.renderer
    if (!r) return
    const selected = this._selected, reduce = this.reduceTransparency
    if (r.drawingSelected === selected && r.reduceTransparency === reduce) return
    r.drawingSelected = selected
    r.reduceTransparency = reduce
    this.view.setNeedsRedraw(Parts.plot)
  }

  /** DrawingOverlayView.draw：选中那条、半截预览、读数与放大镜、铃铛。 */
  paintOverlay(ctx: CanvasRenderingContext2D): void {
    const v = this.view
    const s = v.state
    const axes = drawAxesOf(v)
    if (!s || !axes) return
    this.syncFocus()
    ctx.save()
    try {
      if (v.ownDimmed) ctx.globalAlpha = 0.35
      const t = s.input.colors
      // 提醒线排在画线开关之前：「隐藏画线」收的是画线，提醒照常生效、记号照常在
      this.paintSignals(ctx, axes, t)
      if (!s.input.options.drawings) return
      ctx.beginPath(); ctx.rect(0, axes.pane.y, axes.layout.plotW, axes.pane.h); ctx.clip()
      const series = s.input.series
      const sel = this._selected
      const item = sel != null ? s.overlay.drawings.find(d => d.id === sel) : undefined
      if (item) {
        const live = s.overlay.drawingPreviewID === sel
        const shown = this.preview ?? item
        paintDrawing(shown, ctx, axes, t, series, v.scale, { selected: true, handles: !shown.locked, shape: live })
      }
      const plan = DrawingPreview.plan(this._tool, this.anchors, this.origin?.point ?? null, this.moved, this.aim)
      if (plan) {
        const tool = plan.tool
        if (plan.points.length === DrawKind.placeCount(tool) && tool === 'regression') {
          plan.points = fittedRegression(plan.points, series) ?? plan.points
        }
        const points = plan.points
        const kind = DrawingPreferences.kindFor(tool, this.variants)
        // 落下来会带上这种线记住的颜色（styles），预览、手柄、连线就先用同一支笔，不然画的一路是皮肤色、松手才换色。
        const pen = Object.prototype.hasOwnProperty.call(this.styles, kind) ? this.styles[kind]?.color ?? null : null
        if (plan.whole) {
          const preview = drawingWith(kind, points)
          preview.color = pen
          preview.dash = 'dashed'
          paintDrawing(preview, ctx, axes, t, series, v.scale, { selected: true, handles: true })
        } else {
          for (const pt of points) handleDot(ctx, axes.x(pt.t), axes.y(pt.p), t, penColor(pen, t))
          for (let i = 1; i < Math.max(points.length, 1); i++) {
            const link = drawingWith('trend', points.slice(i - 1, i + 1))
            link.dash = 'dashed'
            link.color = pen
            paintDrawing(link, ctx, axes, t, null, v.scale, { selected: true, handles: false })
          }
        }
        if (this.aim) this.readout(ctx, { x: axes.x(this.aim.t), y: axes.y(this.aim.p) }, this.aim, s, axes)
      }
      const drag = this.drag
      if (drag && drag.part !== 'body') {
        const it = this.preview ?? s.overlay.drawings.find(d => d.id === drag.id)
        const index = partIndex(drag.part) ?? 0
        if (it && index < it.points.length) {
          const pt = it.points[index]
          this.readout(ctx, { x: axes.x(pt.t), y: axes.y(pt.p) }, pt, s, axes)
        }
      }
      this.bells(ctx, s.overlay.drawings, axes, t)
    } finally {
      ctx.restore()
    }
  }

  /** 提醒线：细虚线（1pt，4/3 的点划）+ 右端一枚铃铛，皮肤的强调色（和手柄同一个 amber，照 iOS） */
  private paintSignals(ctx: CanvasRenderingContext2D, axes: DrawAxes, t: ChartColors): void {
    const shown = this.shownSignals
    if (!shown.length) return
    ctx.save()
    try {
      ctx.beginPath(); ctx.rect(0, axes.pane.y, axes.layout.plotW, axes.pane.h); ctx.clip()
      ctx.strokeStyle = css(t.amber); ctx.lineWidth = 1; ctx.setLineDash([4, 3])
      for (const signal of shown) {
        for (const line of signal.lines) {
          const path = alertSignalPath(line, axes)
          if (path.length < 2) continue
          ctx.beginPath(); ctx.moveTo(path[0].x, path[0].y)
          for (let i = 1; i < path.length; i++) ctx.lineTo(path[i].x, path[i].y)
          ctx.stroke()
        }
      }
      ctx.setLineDash([])
      for (const signal of shown) { const b = alertSignalBell(signal, axes); if (b) bell(ctx, b.x, b.y, t.amber) }
    } finally {
      ctx.restore()
    }
  }

  private bells(ctx: CanvasRenderingContext2D, drawings: readonly Drawing[], axes: DrawAxes, t: ChartColors): void {
    if (this._alerted.size === 0) return
    const right = axes.layout.plotW
    for (const item of drawings) {
      if (!this._alerted.has(item.id) || item.hidden) continue
      const line = AlertGeometry.lines(item)?.[0]
      if (!line) continue
      const last = line.points.length ? Math.max(...line.points.map(p => p.t)) : 0
      const x = line.extendRight ? right - 10 : Math.min(axes.x(last), right - 10)
      if (!Number.isFinite(x) || !(x > 2)) continue
      const p = alertLinePrice(line, axes.t(x))
      if (p == null || !Number.isFinite(p)) continue
      const y = axes.y(p)
      if (!Number.isFinite(y) || !(y > axes.pane.y) || !(y < axes.pane.y + axes.pane.h)) continue
      // 铃铛是这条线的记号：同一支笔、同一档浓淡（没选中就和线一起退后一步）。
      ctx.save()
      ctx.globalAlpha *= penAlpha(item.id, this._selected, this.reduceTransparency)
      bell(ctx, x, y, penColor(item.color, t))
      ctx.restore()
    }
  }

  private readout(ctx: CanvasRenderingContext2D, q: DrawPixel, point: DrawPoint, s: ChartState, axes: DrawAxes): void {
    const t = s.input.colors
    const backdrop = this.loupe
    if (backdrop) {
      const lens = new DrawLoupeFrame(q, axes.layout.plotW, axes.pane)
      const c = lens.center, box = lens.box
      ctx.save()
      ctx.beginPath(); ctx.ellipse(c.x, c.y, box.w / 2, box.h / 2, 0, 0, Math.PI * 2); ctx.clip()
      ctx.translate(c.x, c.y); ctx.scale(lens.scale, lens.scale)
      ctx.drawImage(backdrop, -q.x, -q.y, this.view.width, this.view.height)
      ctx.restore()
      ctx.save()
      ctx.setLineDash([])
      ctx.strokeStyle = css(t.accent); ctx.lineWidth = 1.5
      ctx.beginPath(); ctx.ellipse(c.x, c.y, box.w / 2, box.h / 2, 0, 0, Math.PI * 2); ctx.stroke()
      ctx.beginPath()
      ctx.moveTo(c.x - 7, c.y); ctx.lineTo(c.x + 7, c.y)
      ctx.moveTo(c.x, c.y - 7); ctx.lineTo(c.x, c.y + 7)
      ctx.stroke()
      ctx.restore()
    }
    const text = fmtFull(point.t, s.input.tzOffset) + ' · ' + fmtNum(point.p, s.input.decimals)
    const w = textWidth(text, ChartFont.axis) + 12
    const x = Math.max(2, Math.min(axes.layout.plotW - w - 2, q.x - w / 2))
    const y = Math.max(2, q.y - 28)
    ctx.fillStyle = css(t.crossBg)
    roundRectPath(ctx, x, y, w, 17, 3); ctx.fill()
    drawCentered(ctx, text, x + w / 2, y + 8.5, ChartFont.axis, t.crossInk)
  }
}

/** 半截预览上的锚点圆：半径 5，面板底、笔色描边 1.4（和将要落下的线同一支笔）。 */
function handleDot(ctx: CanvasRenderingContext2D, x: number, y: number, t: ChartColors, pen: Hex): void {
  ctx.save()
  ctx.setLineDash([])
  ctx.beginPath(); ctx.ellipse(x, y, 5, 5, 0, 0, Math.PI * 2)
  ctx.fillStyle = css(t.panel); ctx.fill()
  ctx.strokeStyle = css(pen); ctx.lineWidth = 1.4; ctx.stroke()
  ctx.restore()
}

/** 设了提醒的线尾上的小铃铛。 */
function bell(ctx: CanvasRenderingContext2D, qx: number, qy: number, color: Hex): void {
  ctx.save()
  ctx.setLineDash([])
  ctx.strokeStyle = css(color); ctx.fillStyle = css(color)
  ctx.lineWidth = 1; ctx.lineJoin = 'round'
  const w = 5, h = 5.5
  const x = qx, y = qy - 1.5
  ctx.beginPath()
  ctx.moveTo(x - w / 2, y + h / 2)
  ctx.lineTo(x - w / 2 + 0.6, y - h / 6)
  // CG 的 clockwise:false 在翻转坐标系下是屏幕上的顺时针：从左（π）经顶到右（0）
  ctx.arc(x, y - h / 6, w / 2 - 0.6, Math.PI, 0, false)
  ctx.lineTo(x + w / 2, y + h / 2)
  ctx.closePath()
  ctx.stroke()
  ctx.beginPath(); ctx.ellipse(x, y + h / 2 + 0.2 + 0.9, 0.9, 0.9, 0, 0, Math.PI * 2); ctx.fill()
  ctx.restore()
}

// ------------------------------------------------------------------ 接线

/** 把画线层装到一张图上：五个挂点一起接好，覆盖层默认接触摸。 */
export function attachDrawing(view: ChartView): DrawingController {
  const c = new DrawingController(view)
  view.drawingProject = s => c.project(s)
  view.drawingKeyOf = s => c.keyOf(s)
  view.onDrawingKeyChanged = from => c.keyDidChange(from)
  view.drawingOverlayPaint = ctx => c.paintOverlay(ctx)
  view.drawingTeardown = c.teardownHook
  view.signalTap = c.signalTapHook
  c.interactive = true
  // 已经有 state 的图：重新过一遍投影，拿到投影键
  const s = view.state
  if (s) view.state = s
  c.adoptKey()
  return c
}

/** Swift 的 projectDrawings(into:)：按品种把本里那一桶线投到这份 state 上。 */
export function projectDrawings(controller: DrawingController, incoming: ChartState): ChartState {
  return controller.project(incoming)
}
