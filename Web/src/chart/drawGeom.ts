/* Hkline Web · 画线几何的接入：缓存、画、命中、手柄、包围框
 *
 * 2026-10-08 补全工具时新加的 31 种（GEOM）先接的是手机网页版的 drawingGeometry；2026-10-09 起这 31 种连同
 * 趋势线、射线、水平线、垂直线、矩形、斐波那契回撤（TVK = 37 种）都改由 drawTV.ts 照 TradingView 的画法出几何——
 * 线段可以各有颜色 / 粗细 / 线型，字块可以有底色、边框、粗斜体、多行。这里管换算、缓存和按网页视觉画出来。
 * 算出来的四把（锚定均价线、两种成交量分布、持仓）与临时测量不走这里（drawTools.ts / chart.ts）。
 *
 * 性能：几何按画线缓存（WeakMap），键是这一帧的坐标映射（每根间距、右沿、价格区间、窗格高、根数、涨跌色……）加上画线自己的
 * 锚点、主样式、style、选中态；没变就直接拿上一帧的结果画，十六格满屏画线时悬停、跳价都不重算。
 */
import { hexA } from '../util/format'
import type { Drawing, DrawingType, Pane, PriceRange, TVChart } from './chart'
import { ANCHOR_COUNT, CONTRACT_KIND, DEFAULT_DRAW_COLOR, levelsOf, levelsOk, textOk } from './drawTools'
import { buildTV, placeLabels, type TGeom, type TPlaced, type XY } from './drawTV'
import type { Drawing as MDrawing } from '../m/chart/draw/drawing'

type Ctx = CanvasRenderingContext2D

/** 2026-10-08 新加的 31 种（命名沿用：验收脚本与测试按它分组） */
export const GEOM: ReadonlySet<DrawingType> = new Set<DrawingType>([
  'hray', 'extended', 'crossLine', 'arrowLine', 'channel', 'regression', 'pitchfork', 'gannBox', 'gannFan',
  'fibExtension', 'fibChannel', 'fibTimeZone', 'fibFan', 'xabcd', 'abcd', 'headShoulders', 'triangle',
  'elliottImpulse', 'elliottCorrection', 'ptMeasure', 'priceRange', 'dateRange', 'datePriceRange',
  'ellipse', 'curve', 'note', 'callout', 'priceLabel', 'flag', 'markerUp', 'markerDown',
])
/** 照 TradingView 出几何的全部种类 = GEOM + 最早的六种 */
export const TVK: ReadonlySet<DrawingType> = new Set<DrawingType>([...GEOM, 'trend', 'ray', 'hline', 'vline', 'rect', 'fib'])

interface Built { key: unknown[]; g: TGeom; placed: TPlaced[] }
const cache = new WeakMap<Drawing, Built>()

function keyOf(ch: TVChart, d: Drawing, p: Pane, r: PriceRange, sel: boolean): unknown[] {
  const k: unknown[] = [
    ch.indexToX(0), ch.spacing, ch.plotW(), p.y, p.h,
    ch.priceToY(r.min, p, r), ch.priceToY(r.max, p, r), ch.priceToY((r.min + r.max) / 2, p, r),
    ch.bars.length, ch.bars[0]?.t, ch.bars[ch.bars.length - 1]?.c, ch.iv, ch.meta.dec, ch.font,
    ch.colors.up, ch.colors.down, ch.colors.bg, ch.colors.text,
    d.color, d.width, d.dash, d.filled, d.text, d.levels?.length, d.style ? JSON.stringify(d.style) : '', sel,
  ]
  for (const q of d.pts) k.push(q.t, q.p)
  if (d.levels) for (const v of d.levels) k.push(v)
  return k
}
const sameKey = (a: unknown[], b: unknown[]): boolean => a.length === b.length && a.every((v, i) => v === b[i])

/** 网页画线 → 手机画线的字段（供同步测试比对手机那套几何的口径用）。点没点齐的草稿把最后一点重复补齐 */
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

/** 这一帧这条线的几何（缓存命中就不重算）；sel 不传时按图表自己的选中态 */
export function geomOf(ch: TVChart, d: Drawing, p: Pane, r: PriceRange, sel?: boolean): Built | null {
  if (!TVK.has(d.type) || !d.pts.length) return null
  const s = sel ?? (ch.selected === d || ch.draft === d)
  const key = keyOf(ch, d, p, r, s)
  const hit = cache.get(d)
  if (hit && sameKey(hit.key, key)) return hit
  const g = buildTV(ch, d, p, r, s)
  const c = ch.ctx
  const placed = placeLabels(g.labels, famOf(ch), (f, t) => textW(c, f, t), p.y, p.h, ch.plotW())
  const b: Built = { key, g, placed }
  cache.set(d, b)
  return b
}

/** 手柄位置（拖哪一个就改第几个锚点） */
export function geomHandles(ch: TVChart, d: Drawing, p: Pane, r: PriceRange): XY[] {
  const b = geomOf(ch, d, p, r)
  if (b && b.g.handles.length) return b.g.handles
  return d.pts.map(q => ({ x: ch.indexToX(ch.indexAt(q.t)), y: ch.priceToY(q.p, p, r) }))
}

function segDist(x: number, y: number, a: XY, b: XY): number {
  const dx = b.x - a.x, dy = b.y - a.y, L = dx * dx + dy * dy
  const t = L > 0 ? Math.max(0, Math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / L)) : 0
  return Math.hypot(x - a.x - dx * t, y - a.y - dy * t)
}
function inPoly(x: number, y: number, ps: readonly XY[]): boolean {
  let inside = false
  for (let i = 0, j = ps.length - 1; i < ps.length; j = i++) {
    const a = ps[i], b = ps[j]
    if ((a.y > y) !== (b.y > y) && x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x) inside = !inside
  }
  return inside
}

/** 到这条线的距离（px）：落在字块里或填色面里算 0；够不着 Infinity */
export function hitGeom(ch: TVChart, d: Drawing, x: number, y: number, p: Pane, r: PriceRange): number {
  const b = geomOf(ch, d, p, r); if (!b) return Infinity
  for (const q of b.placed) if (x >= q.box.left - 2 && x <= q.box.right + 2 && y >= q.box.top - 2 && y <= q.box.bottom + 2) return 0
  let best = Infinity
  for (const s of b.g.segments) best = Math.min(best, Math.max(0, segDist(x, y, s.a, s.b) - s.w / 2))
  if (best < 6) return best
  for (const f of b.g.fills) if (inPoly(x, y, f.points)) return 0
  return best
}

/** 看得见的部分的包围框（选中时快捷条贴在它上方） */
export function geomBox(ch: TVChart, d: Drawing, p: Pane, r: PriceRange): XY[] {
  const b = geomOf(ch, d, p, r); if (!b) return []
  const out: XY[] = []
  for (const s of b.g.segments) out.push(s.a, s.b)
  for (const f of b.g.fills) out.push(...f.points)
  for (const q of b.placed) out.push({ x: q.box.left, y: q.box.top }, { x: q.box.right, y: q.box.bottom })
  return out.length ? out : b.g.handles
}

const PADX = { none: 0, wash: 3, chip: 5, box: 7 } as const

/** 画一条；不归这里管的种类返回 false */
export function drawGeom(ch: TVChart, d: Drawing, p: Pane, r: PriceRange, sel: boolean): boolean {
  if (!TVK.has(d.type)) return false
  const b = geomOf(ch, d, p, r, sel); if (!b) return true
  const { g, placed } = b
  const c: Ctx = ch.ctx, col = d.color || DEFAULT_DRAW_COLOR
  c.save()
  c.beginPath(); c.rect(0, p.y, ch.plotW(), p.h); c.clip()
  for (const f of g.fills) {
    c.fillStyle = f.col
    c.beginPath(); c.moveTo(f.points[0].x, f.points[0].y)
    for (let i = 1; i < f.points.length; i++) c.lineTo(f.points[i].x, f.points[i].y)
    c.closePath(); c.fill()
  }
  // 同色同粗细同线型的线段并成一笔画（形态、江恩箱、扇形一条几十段）；横平竖直的奇数宽线贴半像素，不糊成两像素
  c.lineJoin = 'round'
  const groups = new Map<string, typeof g.segments>()
  for (const s of g.segments) {
    const k = `${s.col}|${s.w}|${s.dash.join(',')}`
    const a = groups.get(k); if (a) a.push(s); else groups.set(k, [s])
  }
  for (const segs of groups.values()) {
    const s0 = segs[0], odd = Math.round(s0.w) % 2 === 1
    c.strokeStyle = s0.col; c.lineWidth = s0.w; c.setLineDash(s0.dash)
    c.lineCap = s0.dash.length ? (s0.dash[0] <= s0.w ? 'round' : 'butt') : 'round'
    c.beginPath()
    for (const s of segs) {
      let { a, b: e } = s
      if (odd && a.y === e.y) { const y = Math.round(a.y) + 0.5; a = { x: a.x, y }; e = { x: e.x, y } }
      else if (odd && a.x === e.x) { const x = Math.round(a.x) + 0.5; a = { x, y: a.y }; e = { x, y: e.y } }
      c.moveTo(a.x, a.y); c.lineTo(e.x, e.y)
    }
    c.stroke()
  }
  c.setLineDash([])
  c.textBaseline = 'middle'
  for (const q of placed) {
    const L = q.label, bx = q.box, w = bx.right - bx.left, h = bx.bottom - bx.top
    if (L.plate === 'chip') { c.fillStyle = L.bg || col; roundRect(c, bx.left, bx.top, w, h, 4); c.fill() }
    else if (L.plate === 'wash') { c.fillStyle = hexA((ch.colors.bg || '#ffffff').slice(0, 7), 0.82); roundRect(c, bx.left, bx.top, w, h, 4); c.fill() }
    else if (L.plate === 'box') {
      roundRect(c, bx.left + 0.5, bx.top + 0.5, w - 1, h - 1, 4)
      if (L.bg) { c.fillStyle = L.bg; c.fill() }
      if (L.border) { c.strokeStyle = L.border; c.lineWidth = 1; c.stroke() }
    }
    c.font = q.font; c.fillStyle = L.col
    const pad = PADX[L.plate]
    c.textAlign = L.align
    const tx = L.align === 'left' ? bx.left + pad : L.align === 'right' ? bx.right - pad : q.center.x
    const top = q.center.y - (q.lines.length - 1) * q.lineH / 2
    q.lines.forEach((s, i) => c.fillText(s, tx, top + i * q.lineH + 0.5))
    ch.textRects.push({ x: bx.left, y: bx.top, w, h })
  }
  c.restore()
  if (sel) {
    for (const hd of g.handles) { c.fillStyle = ch.colors.bg; c.strokeStyle = col.slice(0, 7); c.lineWidth = 2; c.beginPath(); c.arc(hd.x, hd.y, 4.5, 0, Math.PI * 2); c.fill(); c.stroke() }
  }
  if (d.alert && d.type !== 'fib' && g.handles.length) {
    const e = g.handles[g.handles.length - 1]
    c.fillStyle = ch.colors.alert; c.beginPath(); c.arc(e.x + 10, e.y - 10, 4, 0, Math.PI * 2); c.fill()
  }
  return true
}

function roundRect(c: Ctx, x: number, y: number, w: number, h: number, r: number): void { c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath() }
