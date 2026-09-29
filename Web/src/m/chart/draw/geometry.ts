// 移植自 KanpanCore/Sources/KanpanCore/Drawing/DrawGeometry.swift
//
// 一条画线在屏幕上的全部几何：线段、填充、手柄、标签。普通渲染、选中渲染、预览与命中测试
// 共用这一份；无限长的线（射线、延长线）按参数化裁剪到图区，不用一个随手的延长长度。

import { Chart } from '../geometry'
import { fmtNum } from '../format'
import type { BarSeries } from '../series'
import { cFixed, cG, cSignedFixed } from './fmt'
import { type Drawing, type DrawPart, drawingA, drawingIsValid, distSeg, partAnchor } from './drawing'
import { volumeProfile, vwapTrail } from './volume'

export interface DrawBounds { left: number; top: number; right: number; bottom: number }
export const boundsContains = (b: DrawBounds, p: DrawPixel): boolean => p.x >= b.left && p.x <= b.right && p.y >= b.top && p.y <= b.bottom
/** 两块地有没有真的叠上。边挨着边不算叠（和 `CGRect.intersects` 同一口径）。 */
export const boundsIntersects = (a: DrawBounds, o: DrawBounds): boolean =>
  a.left < o.right && o.left < a.right && a.top < o.bottom && o.top < a.bottom

export interface DrawPixel { x: number; y: number }
const px = (x: number, y: number): DrawPixel => ({ x, y })

/** 这一笔用哪个颜色画：线自己的颜色、图表涨色、图表跌色。 */
export type DrawTint = 'line' | 'up' | 'down'

export interface DrawSegment {
  a: DrawPixel
  b: DrawPixel
  tint: DrawTint
  /** 这一段单独画成虚线，不跟这条线自己的线型走（只有成交量分布用得上）。 */
  dashed: boolean
}

export interface DrawFill {
  points: DrawPixel[]
  tint: DrawTint
  /** 这一块自己的透明度；null 走老的 0.12。 */
  opacity: number | null
}
const fill = (points: DrawPixel[], tint: DrawTint = 'line', opacity: number | null = null): DrawFill => ({ points, tint, opacity })

/** 字底下垫什么：none 什么都不垫；wash 垫一层图表底色；chip 实心胶囊 + 反白字。 */
export type DrawPlate = 'none' | 'wash' | 'chip'

export interface DrawLabel {
  point: DrawPixel
  text: string
  tint: DrawTint
  /** 以 point 为中心画，而不是默认的「右对齐、底边对齐」。 */
  centered: boolean
  plate: DrawPlate
}
export const drawLabel = (point: DrawPixel, text: string, o: { tint?: DrawTint; centered?: boolean; plate?: DrawPlate } = {}): DrawLabel =>
  ({ point, text, tint: o.tint ?? 'line', centered: o.centered ?? false, plate: o.plate ?? 'none' })

export interface DrawTextSize { width: number; height: number }

/** 排好版的一条标签：center 是字的中心，box 是它在屏幕上真正盖住的那块地。 */
export interface PlacedDrawLabel { label: DrawLabel; center: DrawPixel; box: DrawBounds }

/**
 * 一条画线上那些字的排版。画和点共用同一份输出（A-01）。
 * 先按纵向排一遍，横向真的有交叠就把后来的那条往下让一行；让满 16 次还叠着、或者让到图外，就不画。
 */
export function placeDrawingLabels(labels: readonly DrawLabel[], plotW: number, paneY: number, paneH: number,
  measure: (text: string) => DrawTextSize, lineHeight: number = Chart.drawLabelLineH): PlacedDrawLabel[] {
  const placed: PlacedDrawLabel[] = []
  // Swift `sorted(by:)` 不保证稳定；JS 的 sort 是稳定的。同高的标签在 Swift 里本来就只按内容让位，结果一致。
  const sorted = labels.slice().sort((l, r) => l.point.y - r.point.y)
  for (const label of sorted) {
    if (label.text === '') continue
    const size = measure(label.text)
    const pad = label.plate === 'none' ? 0 : 4
    const half = size.width / 2 + pad
    const cx = Math.max(half + 2, Math.min(plotW - half - 2, label.centered ? label.point.x : label.point.x - size.width / 2))
    let cy = label.centered ? label.point.y : label.point.y - size.height / 2
    const boxAt = (y: number): DrawBounds => ({ left: cx - half, top: y - lineHeight / 2, right: cx + half, bottom: y + lineHeight / 2 })
    let box = boxAt(cy)
    let tries = 0
    while (tries < 16 && placed.some(p => boundsIntersects(p.box, box))) {
      cy += lineHeight; tries += 1
      box = boxAt(cy)
    }
    if (!(box.top >= paneY && box.bottom <= paneY + paneH)) continue
    placed.push({ label, center: px(cx, cy), box })
  }
  return placed
}

export class DrawGeometry {
  segments: DrawSegment[] = []
  fills: DrawFill[] = []
  handles: DrawPixel[] = []
  labels: DrawLabel[] = []
  /** 那些字排好版之后各自盖住的矩形，由 `layoutLabels` 填。 */
  labelBoxes: DrawBounds[] = []

  /** 只有一块填充区时的老写法。 */
  get polygon(): DrawPixel[] { return this.fills[0]?.points ?? [] }
  set polygon(v: DrawPixel[]) { this.fills = v.length === 0 ? [] : [fill(v)] }

  /** 把标签排好版，画出来的矩形顺手记进 labelBoxes，命中测试用同一批。 */
  layoutLabels(plotW: number, paneY: number, paneH: number, measure: (text: string) => DrawTextSize): PlacedDrawLabel[] {
    const placed = placeDrawingLabels(this.labels, plotW, paneY, paneH, measure)
    this.labelBoxes = placed.map(p => p.box)
    return placed
  }

  /** 离 (x, y) 最近的那个手柄。超出 radius 的不算。 */
  nearestHandle(x: number, y: number, radius: number = Chart.hitHandlePt): { index: number; distance: number } | null {
    let best: { index: number; distance: number } | null = null
    this.handles.forEach((p, i) => {
      const d = Math.hypot(p.x - x, p.y - y)
      if (!(d < radius) || (best != null && !(d < best.distance))) return
      best = { index: i, distance: d }
    })
    return best
  }

  /** 到这条线「看得见的墨」的距离：落在文字块里算 0；够不着是 null。 */
  inkDistance(x: number, y: number): number | null {
    if (this.labelBoxes.some(b => boundsContains(b, px(x, y)))) return 0
    let best = Infinity
    for (const s of this.segments) best = Math.min(best, distSeg(x, y, s.a.x, s.a.y, s.b.x, s.b.y))
    return best < Chart.hitLinePt ? best : null
  }

  /** 点在不在某块填充区里面（射线法）。 */
  hitsFill(x: number, y: number): boolean {
    for (const f of this.fills) {
      if (f.points.length < 3) continue
      const poly = f.points
      let inside = false
      let j = poly.length - 1
      for (let i = 0; i < poly.length; i++) {
        const a = poly[i], b = poly[j]
        if ((a.y > y) !== (b.y > y) && x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x) inside = !inside
        j = i
      }
      if (inside) return true
    }
    return false
  }

  /** 单条线自己的命中：手柄 → 线体/文字 → 填充。 */
  hit(x: number, y: number, handleRadius: number = Chart.hitHandlePt): DrawPart | null {
    const nearest = this.nearestHandle(x, y, handleRadius)
    if (nearest) return partAnchor(nearest.index)
    if (this.inkDistance(x, y) != null) return 'body'
    if (this.hitsFill(x, y)) return 'body'
    return null
  }
}

/**
 * 普通渲染、选中渲染、预览与命中测试共用的几何源。
 * `decimals` 是价格轴当前的小数位；null 退回 `%.8g`。`series` 只有计算型工具会看。
 */
export function drawingGeometry(d: Drawing, r: DrawBounds, xOf: (t: number) => number, yOf: (p: number) => number,
  decimals: number | null = null, series: BarSeries | null = null): DrawGeometry {
  const g = new DrawGeometry()
  const price = (v: number): string => (decimals == null ? cG(v, 8) : fmtNum(v, decimals))
  const signedPrice = (v: number): string => (v < 0 ? '-' : '+') + price(Math.abs(v))
  const percent = (from: number, to: number): string => {
    if (!(from !== 0 && Number.isFinite(from) && Number.isFinite(to))) return '—'
    return cSignedFixed((to - from) / Math.abs(from) * 100, 2) + '%'
  }
  const span = (ms: number): string => {
    const minutes = Math.abs(ms) / 60_000
    if (minutes < 90) return cFixed(minutes, 0) + ' 分钟'
    const hours = minutes / 60
    if (hours < 48) return cFixed(hours, 1) + ' 小时'
    return cFixed(hours / 24, 1) + ' 天'
  }
  const level3 = (v: number): string => cG(v, 3)

  if (!drawingIsValid(d) || d.hidden) return g
  const pts = d.points.map(p => px(xOf(p.t), yOf(p.p)))
  if (!pts.every(p => Number.isFinite(p.x) && Number.isFinite(p.y))) return g
  const a = pts[0]
  const b = pts.length > 1 ? pts[1] : a
  const A = drawingA(d)
  const P = d.points
  g.handles = pts

  const line = (a: DrawPixel, b: DrawPixel, from = 0, to = 1): void => {
    const dx = b.x - a.x, dy = b.y - a.y
    let lo = from, hi = to
    const axes: [number, number, number, number][] = [[a.x, dx, r.left, r.right], [a.y, dy, r.top, r.bottom]]
    for (const [origin, delta, lower, upper] of axes) {
      if (Math.abs(delta) < 1e-12) { if (origin < lower || origin > upper) return }
      else {
        const t1 = (lower - origin) / delta, t2 = (upper - origin) / delta
        lo = Math.max(lo, Math.min(t1, t2)); hi = Math.min(hi, Math.max(t1, t2))
      }
    }
    if (!(lo <= hi && Number.isFinite(lo) && Number.isFinite(hi))) return
    g.segments.push({ a: px(a.x + lo * dx, a.y + lo * dy), b: px(a.x + hi * dx, a.y + hi * dy), tint: 'line', dashed: false })
  }
  const seg = (a: DrawPixel, b: DrawPixel, tint: DrawTint = 'line', dashed = false): void => { g.segments.push({ a, b, tint, dashed }) }
  const polyline = (ps: DrawPixel[]): void => { for (let i = 1; i < Math.max(ps.length, 1); i++) line(ps[i - 1], ps[i]) }
  const marks = (ps: DrawPixel[], names: string[]): void => {
    ps.forEach((p, i) => {
      if (i < names.length && names[i] !== '') g.labels.push(drawLabel(px(p.x, p.y - 10), names[i], { centered: true, plate: 'wash' }))
    })
  }
  const arrowHead = (tip: DrawPixel, tail: DrawPixel, size = 9, tint: DrawTint = 'line'): void => {
    const dx = tip.x - tail.x, dy = tip.y - tail.y
    const len = Math.sqrt(dx * dx + dy * dy)
    if (!(len > 1e-6)) return
    const ux = dx / len, uy = dy / len, w = size * 0.42
    g.fills.push(fill([
      tip,
      px(tip.x - ux * size - uy * w, tip.y - uy * size + ux * w),
      px(tip.x - ux * size + uy * w, tip.y - uy * size - ux * w),
    ], tint))
  }
  const shape = (ps: DrawPixel[], tint: DrawTint = 'line'): void => {
    if (ps.length < 3) return
    g.fills.push(fill(ps, tint))
    for (let i = 0; i < ps.length; i++) seg(ps[i], ps[(i + 1) % ps.length], tint)
  }
  const offsetChannel = (a: DrawPixel, b: DrawPixel, c: DrawPixel): { dx: number; dy: number; f: number } | null => {
    const dx = b.x - a.x, dy = b.y - a.y
    const len = dx * dx + dy * dy
    if (!(len > 1e-9)) return null
    return { dx, dy, f: ((c.x - a.x) * -dy + (c.y - a.y) * dx) / len }
  }
  const corners4 = (x0: number, y0: number, x1: number, y1: number): DrawPixel[] => [px(x0, y0), px(x1, y0), px(x1, y1), px(x0, y1)]

  switch (d.kind) {
    case 'hline':
      line(px(r.left, a.y), px(r.right, a.y)); g.handles = []
      g.labels = [drawLabel(px(r.right - 4, a.y - 4), price(A.p), { plate: 'chip' })]
      break
    case 'vline':
      line(px(a.x, r.top), px(a.x, r.bottom)); g.handles = []
      break
    case 'hray':
      line(a, px(a.x + 1, a.y), 0, Infinity)
      g.labels = [drawLabel(px(r.right - 4, a.y - 4), price(A.p), { plate: 'chip' })]
      break
    case 'trend': line(a, b); break
    case 'ray': line(a, b, 0, Infinity); break
    case 'extended': line(a, b, -Infinity, Infinity); break
    case 'rectangle': {
      const c = px(b.x, a.y), e = px(a.x, b.y)
      g.polygon = [a, c, b, e]
      line(a, c); line(c, b); line(b, e); line(e, a)
      break
    }
    case 'measure': {
      // 「测量」是一个按涨跌上色的框，中间一根竖轴带箭头，读数贴在框外。
      const rose = P[1].p >= A.p
      const tint: DrawTint = rose ? 'up' : 'down'
      const x0 = Math.min(a.x, b.x), x1 = Math.max(a.x, b.x)
      const y0 = Math.min(a.y, b.y), y1 = Math.max(a.y, b.y)
      shape(corners4(x0, y0, x1, y1), tint)
      const mid = (x0 + x1) / 2
      seg(px(mid, a.y), px(mid, b.y), tint)
      arrowHead(px(mid, b.y), px(mid, a.y), 9, tint)
      const delta = P[1].p - A.p
      const pct = A.p !== 0 ? cSignedFixed(delta / Math.abs(A.p) * 100, 2) + '%' : '—'
      const readoutY = y0 - 12 >= r.top + 10 ? y0 - 10 : Math.min(r.bottom - 9, y1 + 10)
      g.labels = [drawLabel(px(mid, readoutY), signedPrice(delta) + ' · ' + pct + ' · ' + span(Math.abs(P[1].t - A.t)),
        { tint, centered: true, plate: 'chip' })]
      break
    }
    case 'channel': {
      const c = pts[2], dx = b.x - a.x, dy = b.y - a.y
      const len = dx * dx + dy * dy
      if (!(len > 1e-9)) return g
      const f = ((c.x - a.x) * -dy + (c.y - a.y) * dx) / len
      const u = px(a.x - dy * f, a.y + dx * f), v = px(b.x - dy * f, b.y + dx * f)
      const corners = [px(r.left, r.top), px(r.right, r.top), px(r.right, r.bottom), px(r.left, r.bottom)]
      const projections = corners.map(q => ((q.x - a.x) * dx + (q.y - a.y) * dy) / len)
      const low = Math.min(...projections), high = Math.max(...projections)
      const first = px(a.x + dx * low, a.y + dy * low), last = px(a.x + dx * high, a.y + dy * high)
      g.polygon = [first, last, px(last.x - dy * f, last.y + dx * f), px(first.x - dy * f, first.y + dx * f)]
      line(a, b, -Infinity, Infinity)
      line(u, v, -Infinity, Infinity)
      line(px((a.x + u.x) / 2, (a.y + u.y) / 2), px((b.x + v.x) / 2, (b.y + v.y) / 2), -Infinity, Infinity)
      break
    }
    case 'fibonacci':
      line(a, b)
      for (const level of d.levels) {
        // 回撤：0 是被量那一段的终点，1 是起点。
        const value = P[1].p + (A.p - P[1].p) * level
        const y = yOf(value)
        if (!Number.isFinite(y)) continue
        line(px(Math.min(a.x, b.x), y), px(Math.max(a.x, b.x), y))
        g.labels.push(drawLabel(px(Math.max(a.x, b.x), y - 3), level3(level) + ' · ' + price(value), { plate: 'wash' }))
      }
      break
    case 'regression': {
      // 中心线是落笔那一刻拟合好的；回归通道不往两头无限延伸。
      const c = pts[2], dx = b.x - a.x, dy = b.y - a.y
      const len = dx * dx + dy * dy
      if (!(len > 1e-9)) return g
      const f = ((c.x - a.x) * -dy + (c.y - a.y) * dx) / len
      const u = px(a.x - dy * f, a.y + dx * f), v = px(b.x - dy * f, b.y + dx * f)
      const u2 = px(a.x + dy * f, a.y - dx * f), v2 = px(b.x + dy * f, b.y - dx * f)
      g.fills = [fill([u, v, v2, u2])]
      line(a, b); line(u, v); line(u2, v2)
      break
    }
    case 'position': {
      // 三点：① 入场 ② 目标 ③ 止损。目标在入场上方就是做多。
      const c = pts[2]
      const x0 = Math.min(a.x, b.x), x1 = Math.max(a.x, b.x)
      const entry = A.p, target = P[1].p, stop = P[2].p
      const box = (yTop: number, yBottom: number, tint: DrawTint): void => {
        const poly = corners4(x0, yTop, x1, yBottom)
        g.fills.push(fill(poly, tint))
        for (let i = 0; i < poly.length; i++) seg(poly[i], poly[(i + 1) % poly.length], tint)
      }
      box(a.y, b.y, 'up')
      box(a.y, c.y, 'down')
      seg(px(x0, a.y), px(x1, a.y))
      const gain = Math.abs(target - entry), risk = Math.abs(entry - stop)
      const ratio = risk > 0 ? cFixed(gain / risk, 2) : '—'
      const long = target >= entry
      g.labels = [
        drawLabel(px(x1 - 3, b.y + (long ? -4 : 13)), '目标 ' + percent(entry, target), { tint: 'up', plate: 'chip' }),
        drawLabel(px(x1 - 3, c.y + (long ? 13 : -4)), '止损 ' + percent(entry, stop), { tint: 'down', plate: 'chip' }),
        drawLabel(px((x0 + x1) / 2, a.y), '盈亏比 ' + ratio, { centered: true, plate: 'chip' }),
      ]
      g.handles = [a, px(x1, b.y), px(x1, c.y)]
      break
    }
    case 'fibExtension': {
      // A → B 是被量的那一段，C 是从哪儿开始往外投。刻度值 = C + (B − A) × 比例。
      const c = pts[2]
      line(a, b); line(b, c)
      const move = P[1].p - A.p
      for (const level of d.levels) {
        const value = P[2].p + move * level
        const y = yOf(value)
        if (!Number.isFinite(y)) continue
        line(px(c.x, y), px(r.right, y))
        g.labels.push(drawLabel(px(r.right - 4, y - 3), level3(level) + ' · ' + price(value), { plate: 'wash' }))
      }
      break
    }
    case 'priceRange': {
      const top = Math.min(a.y, b.y), bottom = Math.max(a.y, b.y)
      g.polygon = corners4(r.left, top, r.right, bottom)
      line(px(r.left, a.y), px(r.right, a.y))
      line(px(r.left, b.y), px(r.right, b.y))
      const delta = P[1].p - A.p
      g.labels = [drawLabel(px(r.right - 4, top - 4), signedPrice(delta) + ' · ' + percent(A.p, P[1].p), { plate: 'chip' })]
      break
    }
    case 'dateRange': {
      const left = Math.min(a.x, b.x), right = Math.max(a.x, b.x)
      g.polygon = corners4(left, r.top, right, r.bottom)
      line(px(a.x, r.top), px(a.x, r.bottom))
      line(px(b.x, r.top), px(b.x, r.bottom))
      g.labels = [drawLabel(px(right, r.top + 16), span(P[1].t - A.t), { plate: 'chip' })]
      break
    }
    case 'note':
      g.labels = [drawLabel(px(a.x, a.y - 4), d.text === '' ? '点这里写字' : d.text, { plate: 'wash' })]
      break
    case 'crossLine':
      line(px(r.left, a.y), px(r.right, a.y))
      line(px(a.x, r.top), px(a.x, r.bottom))
      g.labels = [drawLabel(px(r.right - 4, a.y - 4), price(A.p), { plate: 'chip' })]
      break
    case 'arrowLine':
      line(a, b)
      arrowHead(b, a)
      break
    case 'pitchfork': {
      const c = pts[2]
      const mid = px((b.x + c.x) / 2, (b.y + c.y) / 2)
      line(b, c)
      line(a, mid, 0, Infinity)
      const dx = mid.x - a.x, dy = mid.y - a.y
      line(b, px(b.x + dx, b.y + dy), 0, Infinity)
      line(c, px(c.x + dx, c.y + dy), 0, Infinity)
      if (d.filled) g.fills = [fill([b, px(b.x + dx, b.y + dy), px(c.x + dx, c.y + dy), c])]
      break
    }
    case 'fibChannel': {
      const ch = offsetChannel(a, b, pts[2])
      if (!ch) return g
      for (const level of d.levels) {
        const ox = -ch.dy * ch.f * level, oy = ch.dx * ch.f * level
        line(px(a.x + ox, a.y + oy), px(b.x + ox, b.y + oy), -Infinity, Infinity)
        g.labels.push(drawLabel(px(b.x + ox, b.y + oy - 3), level3(level), { plate: 'wash' }))
      }
      if (d.filled) {
        const ox = -ch.dy * ch.f, oy = ch.dx * ch.f
        g.fills = [fill([a, b, px(b.x + ox, b.y + oy), px(a.x + ox, a.y + oy)])]
      }
      break
    }
    case 'ellipse': {
      const cx = (a.x + b.x) / 2, cy = (a.y + b.y) / 2
      const rx = Math.abs(b.x - a.x) / 2, ry = Math.abs(b.y - a.y) / 2
      if (!(rx > 0.5 && ry > 0.5)) return g
      const ring: DrawPixel[] = []
      for (let i = 0; i < 48; i++) {
        const t = i / 48 * 2 * Math.PI
        ring.push(px(cx + rx * Math.cos(t), cy + ry * Math.sin(t)))
      }
      shape(ring)
      break
    }
    case 'triangle':
      shape([a, b, pts[2]])
      break
    case 'curve': {
      // 二次贝塞尔：A 起、C 控、B 止。
      const c = pts[2]
      const ps: DrawPixel[] = []
      for (let i = 0; i <= 32; i++) {
        const t = i / 32, u = 1 - t
        ps.push(px(u * u * a.x + 2 * u * t * c.x + t * t * b.x, u * u * a.y + 2 * u * t * c.y + t * t * b.y))
      }
      polyline(ps)
      break
    }
    case 'datePriceRange': {
      const x0 = Math.min(a.x, b.x), x1 = Math.max(a.x, b.x)
      const y0 = Math.min(a.y, b.y), y1 = Math.max(a.y, b.y)
      const corners = corners4(x0, y0, x1, y1)
      g.polygon = corners
      for (let i = 0; i < corners.length; i++) line(corners[i], corners[(i + 1) % corners.length])
      const delta = P[1].p - A.p
      g.labels = [
        drawLabel(px(x1, y0 - 4), signedPrice(delta) + ' · ' + percent(A.p, P[1].p), { plate: 'chip' }),
        drawLabel(px(x1, y1 + 13), span(P[1].t - A.t), { plate: 'chip' }),
      ]
      break
    }
    case 'fibTimeZone': {
      const unit = P[1].t - A.t
      if (!(Math.abs(unit) > 0)) return g
      for (const level of d.levels) {
        const x = xOf(A.t + unit * level)
        if (!Number.isFinite(x)) continue
        line(px(x, r.top), px(x, r.bottom))
        g.labels.push(drawLabel(px(x, r.top + 16), level3(level), { plate: 'wash' }))
      }
      break
    }
    case 'fibFan':
      for (const level of d.levels) {
        const through = px(b.x, a.y + (b.y - a.y) * level)
        line(a, through, 0, Infinity)
        g.labels.push(drawLabel(px(b.x, through.y - 3), level3(level), { plate: 'wash' }))
      }
      line(a, b)
      break
    case 'gannBox': {
      const x0 = Math.min(a.x, b.x), x1 = Math.max(a.x, b.x)
      const y0 = Math.min(a.y, b.y), y1 = Math.max(a.y, b.y)
      const corners = corners4(x0, y0, x1, y1)
      g.polygon = corners
      for (let i = 0; i < corners.length; i++) line(corners[i], corners[(i + 1) % corners.length])
      for (const level of d.levels) {
        const x = x0 + (x1 - x0) * level, y = y0 + (y1 - y0) * level
        line(px(x, y0), px(x, y1))
        line(px(x0, y), px(x1, y))
      }
      break
    }
    case 'gannFan': {
      const dx = b.x - a.x, dy = b.y - a.y
      if (!(Math.abs(dx) > 1e-6)) return g
      for (const level of d.levels) line(a, px(b.x, a.y + dy * level), 0, Infinity)
      line(a, b)
      break
    }
    case 'xabcd':
      polyline(pts); marks(pts, ['X', 'A', 'B', 'C', 'D'])
      if (d.filled && pts.length >= 5) g.fills = [fill([pts[0], pts[1], pts[2]]), fill([pts[2], pts[3], pts[4]])]
      break
    case 'abcd':
      polyline(pts); marks(pts, ['A', 'B', 'C', 'D'])
      break
    case 'headShoulders':
      polyline(pts); marks(pts, ['', '左肩', '', '头', '', '右肩', ''])
      // 颈线：两个谷（第 3、第 5 个点）连起来往两头延伸。
      if (pts.length >= 7) line(pts[2], pts[4], -Infinity, Infinity)
      break
    case 'elliottImpulse':
      polyline(pts); marks(pts, ['0', '1', '2', '3', '4', '5'])
      break
    case 'elliottCorrection':
      polyline(pts); marks(pts, ['0', 'A', 'B', 'C'])
      break
    case 'callout':
      line(b, a)
      arrowHead(a, b, 8)
      g.labels = [drawLabel(px(b.x, b.y - 4), d.text === '' ? '点这里写字' : d.text, { plate: 'wash' })]
      break
    case 'priceLabel':
      g.labels = [drawLabel(px(a.x, a.y - 4), price(A.p), { plate: 'chip' })]
      break
    case 'flag':
      line(px(a.x, a.y), px(a.x, a.y - 22))
      shape([px(a.x, a.y - 22), px(a.x + 16, a.y - 18), px(a.x, a.y - 14)])
      if (d.text !== '') g.labels = [drawLabel(px(a.x + 18, a.y - 12), d.text, { plate: 'wash' })]
      break
    case 'markerUp':
      shape([px(a.x, a.y), px(a.x - 6, a.y + 12), px(a.x + 6, a.y + 12)], 'up')
      break
    case 'markerDown':
      shape([px(a.x, a.y), px(a.x - 6, a.y - 12), px(a.x + 6, a.y - 12)], 'down')
      break
    case 'anchoredVWAP': {
      if (!series) break
      const trail = vwapTrail(A.t, series)
      if (!trail) break
      let prev: DrawPixel | null = null
      let tip: { point: DrawPixel; value: number } | null = null
      trail.values.forEach((v, k) => {
        if (!Number.isFinite(v)) { prev = null; return }
        const p = px(xOf(series.time(trail.start + k)), yOf(v))
        const q: DrawPixel | null = prev
        if (q && Math.max(q.x, p.x) >= r.left - 2 && Math.min(q.x, p.x) <= r.right + 2) seg(q, p)
        prev = p
        tip = { point: p, value: v }
      })
      const t = tip as { point: DrawPixel; value: number } | null
      if (t) g.labels = [drawLabel(px(t.point.x, t.point.y - 4), price(t.value), { plate: 'chip' })]
      break
    }
    case 'fixedVolumeProfile':
    case 'anchoredVolumeProfile': {
      if (!series || !(r.right > r.left)) break
      const second = P.length > 1 ? P[1].t : A.t
      const fixed = d.kind === 'fixedVolumeProfile'
      const fromT = fixed ? Math.min(A.t, second) : A.t
      const vp = volumeProfile(fromT, fixed ? Math.max(A.t, second) : null, series)
      if (!vp || !(vp.maxRow > 0)) break
      const clampX = (x: number): number => Math.min(Math.max(x, r.left), r.right)
      const xL = clampX(xOf(series.time(vp.first)))
      const xR = clampX(xOf(series.time(vp.last)))
      const root = xL
      const width = Math.min(Math.max(0.30 * (xR - xL), 24), 0.5 * (r.right - r.left))
      const bar = (x0: number, x1: number, top: number, bottom: number, tint: DrawTint, opacity: number): void => {
        g.fills.push(fill(corners4(x0, top, x1, bottom), tint, opacity))
      }
      const maxRow = vp.maxRow
      for (let row = 0; row < vp.rowCount; row++) {
        if (!(vp.rowTotal(row) > 0)) continue
        let top = yOf(vp.rowHigh(row)), bottom = yOf(vp.rowLow(row))
        if (top > bottom) { const s = top; top = bottom; bottom = s }
        if (bottom - top < 1) {
          const mid = (top + bottom) / 2
          top = mid - 3; bottom = mid + 3
        } else {
          const inset = Math.min(0.5, (bottom - top) / 4)
          top += inset; bottom -= inset
        }
        const upW = width * vp.up[row] / maxRow
        const downW = width * vp.down[row] / maxRow
        const opacity = vp.inValueArea(row) ? 0.45 : 0.22
        if (upW > 0) bar(root, root + upW, top, bottom, 'up', opacity)
        if (downW > 0) bar(root + upW, root + upW + downW, top, bottom, 'down', opacity)
      }
      const yPOC = yOf(vp.rowMid(vp.poc))
      seg(px(xL, yPOC), px(xR, yPOC))
      for (const y of [yOf(vp.rowHigh(vp.vaHigh)), yOf(vp.rowLow(vp.vaLow))]) seg(px(xL, y), px(xR, y), 'line', true)
      seg(px(xL, r.top), px(xL, r.bottom), 'line', true)
      if (fixed) seg(px(xR, r.top), px(xR, r.bottom), 'line', true)
      g.labels = [drawLabel(px(xR, yPOC - 4), price(vp.rowMid(vp.poc)), { plate: 'chip' })]
      break
    }
  }
  return g
}
