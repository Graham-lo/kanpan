/* Hkline Web · 画线：手机那套几何（DrawGeometry）在电脑网页图上的接入
 *
 * 2026-10-08 补全工具时，新加的 31 种画线（射线一族、通道、叉子与江恩、斐波那契扩展一族、形态、区间测量、形状、注释）
 * 不在网页另写一套几何：线段、填充、手柄、标签与命中都取手机网页版移植自 iOS 的 drawingGeometry（m/chart/draw/geometry.ts），
 * 三端画出来的形状、刻度、读数一致；这里只管换算坐标、按网页的视觉画出来（线宽、线型、胶囊字、手柄与 drawOne 一致）。
 *
 * 性能：几何按画线缓存（WeakMap），键是这一帧的坐标映射（每根间距、右沿、价格区间、窗格高、根数……）加上画线自己的
 * 锚点、颜色、粗细、线型、刻度、填色、文字；没变就直接拿上一帧的结果画，十六格满屏画线时悬停、跳价都不重算。
 */
import { hexA } from '../util/format'
import { drawingGeometry, placeDrawingLabels, type DrawGeometry, type DrawPixel, type DrawTint, type PlacedDrawLabel } from '../m/chart/draw/geometry'
import type { Drawing as MDrawing } from '../m/chart/draw/drawing'
import type { Drawing, DrawingType, Pane, PriceRange, TVChart } from './chart'
import { ANCHOR_COUNT, CONTRACT_KIND, DEFAULT_DRAW_COLOR, dashPattern, levelsOf, levelsOk, textOk } from './drawTools'

type Ctx = CanvasRenderingContext2D

/** 走这套几何的种类 */
export const GEOM: ReadonlySet<DrawingType> = new Set<DrawingType>([
  'hray', 'extended', 'crossLine', 'arrowLine', 'channel', 'regression', 'pitchfork', 'gannBox', 'gannFan',
  'fibExtension', 'fibChannel', 'fibTimeZone', 'fibFan', 'xabcd', 'abcd', 'headShoulders', 'triangle',
  'elliottImpulse', 'elliottCorrection', 'ptMeasure', 'priceRange', 'dateRange', 'datePriceRange',
  'ellipse', 'curve', 'note', 'callout', 'priceLabel', 'flag', 'markerUp', 'markerDown',
])
/** 形态类：画到一半（点还没点齐）时把字收掉，不然几个名字叠在同一点上 */
const PATTERN: ReadonlySet<DrawingType> = new Set<DrawingType>(['xabcd', 'abcd', 'headShoulders', 'elliottImpulse', 'elliottCorrection'])

/** 标签：11 px 字，胶囊 / 衬底 18 高 */
const LABEL_FONT = 11, LABEL_H = 18, LABEL_LINE = 13

interface Built { key: unknown[]; g: DrawGeometry; placed: PlacedDrawLabel[] }
const cache = new WeakMap<Drawing, Built>()

/** 几何依赖的一切（坐标映射 + 画线自己的字段），逐项比对；任何一项变了才重算 */
function keyOf(ch: TVChart, d: Drawing, p: Pane, r: PriceRange): unknown[] {
  const k: unknown[] = [
    ch.indexToX(0), ch.spacing, ch.plotW(), p.y, p.h,
    ch.priceToY(r.min, p, r), ch.priceToY(r.max, p, r), ch.priceToY((r.min + r.max) / 2, p, r),
    ch.bars.length, ch.bars[0]?.t, ch.iv, ch.meta.dec, ch.font,
    d.color, d.width, d.dash, d.filled, d.text, d.levels, d.levels?.length,
  ]
  for (const q of d.pts) k.push(q.t, q.p)
  if (d.levels) for (const v of d.levels) k.push(v)
  return k
}
const sameKey = (a: unknown[], b: unknown[]): boolean => a.length === b.length && a.every((v, i) => v === b[i])

/** 网页画线 → 手机画线（只供几何用）。点没点齐的草稿把最后一点重复补齐 */
export function toM(d: Drawing): { m: MDrawing; padded: boolean } | null {
  const kind = CONTRACT_KIND[d.type]
  if (!kind) return null
  const need = ANCHOR_COUNT[d.type]
  const points = d.pts.slice(0, need).map(q => ({ t: q.t, p: q.p }))
  const padded = points.length < need
  while (points.length && points.length < need) points.push({ ...points[points.length - 1] })
  const lv = levelsOf(d)
  return {
    padded,
    m: {
      id: d.id, kind, points, color: null,
      lineWidth: Math.min(6, Math.max(0.5, d.width || 2)), dash: d.dash ?? 'solid', filled: d.filled !== false,
      locked: false, hidden: false, levels: levelsOk(lv) ? lv : [], text: textOk(d.text) ? d.text : '',
    },
  }
}

const widths = new Map<string, number>()
function textW(c: Ctx, font: string, s: string): number {
  const k = font + '\u0000' + s
  let w = widths.get(k)
  if (w == null) {
    if (widths.size > 4000) widths.clear()
    const f = c.font; c.font = font; w = c.measureText(s).width; c.font = f
    widths.set(k, w)
  }
  return w
}
const famOf = (ch: TVChart): string => ch.font.split('px ')[1] || 'sans-serif'
const labelFont = (ch: TVChart, plate: string): string => `${plate === 'chip' ? '600 ' : ''}${LABEL_FONT}px ${famOf(ch)}`

/** 这一帧这条线的几何（缓存命中就不重算） */
export function geomOf(ch: TVChart, d: Drawing, p: Pane, r: PriceRange): Built | null {
  if (!GEOM.has(d.type) || !d.pts.length) return null
  const key = keyOf(ch, d, p, r)
  const hit = cache.get(d)
  if (hit && sameKey(hit.key, key)) return hit
  const x = toM(d); if (!x) return null
  const PW = ch.plotW()
  const g = drawingGeometry(x.m, { left: 0, top: p.y, right: PW, bottom: p.y + p.h },
    t => ch.indexToX(ch.indexAt(t)), v => ch.priceToY(v, p, r), ch.meta.dec ?? null, null)
  if (x.padded) {
    if (PATTERN.has(d.type)) g.labels = []
    g.handles = g.handles.slice(0, d.pts.length)
  }
  const c = ch.ctx
  const placed = placeDrawingLabels(g.labels, PW, p.y, p.h, s => ({ width: textW(c, labelFont(ch, 'chip'), s), height: LABEL_LINE }), LABEL_H)
  g.labelBoxes = placed.map(q => q.box)
  const b: Built = { key, g, placed }
  cache.set(d, b)
  return b
}

/** 手柄位置（拖哪一个就改第几个锚点；水平线一族没有手柄时退回锚点本身） */
export function geomHandles(ch: TVChart, d: Drawing, p: Pane, r: PriceRange): DrawPixel[] {
  const b = geomOf(ch, d, p, r)
  if (b && b.g.handles.length) return b.g.handles
  return d.pts.map(q => ({ x: ch.indexToX(ch.indexAt(q.t)), y: ch.priceToY(q.p, p, r) }))
}

/** 到这条线的距离（px）：落在字块里或填色面里算 0；够不着 Infinity */
export function hitGeom(ch: TVChart, d: Drawing, x: number, y: number, p: Pane, r: PriceRange): number {
  const b = geomOf(ch, d, p, r); if (!b) return Infinity
  const ink = b.g.inkDistance(x, y)
  if (ink != null) return ink
  return b.g.hitsFill(x, y) ? 0 : Infinity
}

/** 看得见的部分的包围框（选中时快捷条贴在它上方） */
export function geomBox(ch: TVChart, d: Drawing, p: Pane, r: PriceRange): DrawPixel[] {
  const b = geomOf(ch, d, p, r); if (!b) return []
  const out: DrawPixel[] = []
  for (const s of b.g.segments) out.push(s.a, s.b)
  for (const f of b.g.fills) out.push(...f.points)
  for (const q of b.placed) out.push({ x: q.box.left, y: q.box.top }, { x: q.box.right, y: q.box.bottom })
  return out.length ? out : b.g.handles
}

/** 画一条；不归这里管的种类返回 false */
export function drawGeom(ch: TVChart, d: Drawing, p: Pane, r: PriceRange, sel: boolean): boolean {
  if (!GEOM.has(d.type)) return false
  const b = geomOf(ch, d, p, r); if (!b) return true
  const { g, placed } = b
  const c: Ctx = ch.ctx, col = d.color || DEFAULT_DRAW_COLOR
  const tint = (t: DrawTint): string => t === 'up' ? ch.colors.up || '#089981' : t === 'down' ? ch.colors.down || '#F23645' : col
  c.save()
  c.beginPath(); c.rect(0, p.y, ch.plotW(), p.h); c.clip()
  for (const f of g.fills) {
    if (f.points.length < 3) continue
    c.fillStyle = f.solid ? tint(f.tint) : hexA(tint(f.tint), f.opacity ?? 0.12)
    c.beginPath(); c.moveTo(f.points[0].x, f.points[0].y)
    for (let i = 1; i < f.points.length; i++) c.lineTo(f.points[i].x, f.points[i].y)
    c.closePath(); c.fill()
  }
  const w = d.width || 2
  c.lineWidth = w; c.lineJoin = 'round'; c.lineCap = d.dash === 'dotted' ? 'round' : d.dash ? 'butt' : 'round'
  // 同色同线型的线段并成一笔画（形态、江恩箱、扇形一条几十段）
  for (const t of ['line', 'up', 'down'] as DrawTint[]) for (const dashed of [false, true]) {
    let any = false
    for (const s of g.segments) {
      if (s.tint !== t || s.dashed !== dashed) continue
      if (!any) { c.beginPath(); any = true }
      c.moveTo(s.a.x, s.a.y); c.lineTo(s.b.x, s.b.y)
    }
    if (!any) continue
    c.strokeStyle = tint(t); c.setLineDash(dashed ? [4, 4] : dashPattern(d)); c.stroke()
  }
  c.setLineDash([])
  c.textAlign = 'center'; c.textBaseline = 'middle'
  for (const q of placed) {
    const L = q.label, tc = tint(L.tint), bx = q.box
    c.font = labelFont(ch, L.plate)
    if (L.plate === 'chip') {
      c.fillStyle = tc; roundRect(c, bx.left, bx.top, bx.right - bx.left, bx.bottom - bx.top, 4); c.fill()
      c.fillStyle = '#fff'
    } else if (L.plate === 'wash') {
      c.fillStyle = hexA(ch.colors.bg || '#ffffff', 0.82); roundRect(c, bx.left, bx.top, bx.right - bx.left, bx.bottom - bx.top, 4); c.fill()
      c.fillStyle = tc
    } else c.fillStyle = tc
    c.fillText(L.text, q.center.x, q.center.y + 0.5)
    ch.textRects.push({ x: bx.left, y: bx.top, w: bx.right - bx.left, h: bx.bottom - bx.top })
  }
  c.restore()
  if (sel) {
    for (const h of g.handles) { c.fillStyle = ch.colors.bg; c.strokeStyle = col; c.lineWidth = 2; c.beginPath(); c.arc(h.x, h.y, 4.5, 0, Math.PI * 2); c.fill(); c.stroke() }
  }
  return true
}

function roundRect(c: Ctx, x: number, y: number, w: number, h: number, r: number): void { c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath() }
