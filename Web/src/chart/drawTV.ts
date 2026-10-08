/* Hkline Web · 电脑网页画线的几何（照 TradingView 的画法与设置项）
 *
 * 2026-10-09 起电脑网页 37 种画线（算出来的四把与临时测量除外）的形状都在这里算：线段、填色、字块、手柄。
 * 锚点、刻度、文字这几样三端共用的字段与手机网页的 drawingGeometry 同一口径（几何源自 m/chart/draw/geometry.ts），
 * TradingView 设置里多出来的项（延伸、箭头、统计、刻度表与背景、标签位置、中线、偏差……）从 d.style 读（drawSpec.ts），
 * 没设的取 TradingView 出厂值。这里只出几何，画由 drawGeom.ts 做、命中也用同一份。
 */
import { crossTimeLabel, durText, fmt } from '../util/format'
import type { Drawing, DrawingType, Pane, PriceRange, TVChart } from './chart'
import { ANCHOR_COUNT, dashPattern } from './drawTools'
import { boxS, fillOf, fillOn, levelRows, lineS, rgbaOf, sv, svb, svn, svs, waveLabels, type LevelRow, type LineS } from './drawSpec'

export interface XY { x: number; y: number }
export interface Bounds { left: number; top: number; right: number; bottom: number }
/** 一段线：main = 用画线自己的颜色 / 粗细 / 线型画的（验收按它取样）；tint = 跟图表涨跌色 */
export interface TSeg { a: XY; b: XY; col: string; w: number; dash: number[]; main: boolean; tint?: 'up' | 'down' }
export interface TFill { points: XY[]; col: string; solid: boolean; tint?: 'up' | 'down' }
export type Plate = 'none' | 'wash' | 'chip' | 'box'
export interface TLabel {
  text: string; x: number; y: number; col: string; size: number; bold?: boolean; italic?: boolean
  align: 'left' | 'center' | 'right'; base: 'top' | 'middle' | 'bottom'; plate: Plate
  /** chip / box 的底色与边框 */
  bg?: string; border?: string; tint?: 'up' | 'down'
}
export interface TPlaced { label: TLabel; box: Bounds; center: XY; font: string; lineH: number; lines: string[] }
export interface TGeom { segments: TSeg[]; fills: TFill[]; handles: XY[]; labels: TLabel[] }

/** 形态类：画到一半（点还没点齐）时把字收掉 */
export const PATTERN: ReadonlySet<DrawingType> = new Set<DrawingType>(['xabcd', 'abcd', 'headShoulders', 'elliottImpulse', 'elliottCorrection'])

const px = (x: number, y: number): XY => ({ x, y })
const level3 = (v: number): string => String(+v.toPrecision(4))
const BIG = 1e5

export function dashOf(name: string, w: number): number[] {
  return name === 'dashed' ? [Math.max(4, w * 3), Math.max(3, w * 2.5)] : name === 'dotted' ? [Math.max(1, w * 0.5), Math.max(2.5, w * 2)] : []
}

/** 这条线这一帧的几何 */
export function buildTV(ch: TVChart, d: Drawing, p: Pane, r: PriceRange, sel: boolean): TGeom {
  const g: TGeom = { segments: [], fills: [], handles: [], labels: [] }
  const need = ANCHOR_COUNT[d.type] ?? d.pts.length
  const P = d.pts.slice(0, need)
  const padded = P.length < need
  while (P.length && P.length < need) P.push({ ...P[P.length - 1] })
  if (!P.length) return g
  const X = (t: number) => ch.indexToX(ch.indexAt(t)), Y = (v: number) => ch.priceToY(v, p, r)
  const pts = P.map(q => px(X(q.t), Y(q.p)))
  if (!pts.every(q => Number.isFinite(q.x) && Number.isFinite(q.y))) return g
  g.handles = pts.slice(0, d.pts.length)
  const PW = ch.plotW(), R: Bounds = { left: 0, top: p.y, right: PW, bottom: p.y + p.h }
  const dec = ch.meta.dec
  const price = (v: number) => fmt(v, dec)
  /** 像素高度 → 价格（图表的反算；测试里的假图没有时按线性） */
  const priceAtY = (y: number): number => typeof ch.yToPrice === 'function' ? ch.yToPrice(y, p, r)
    : r.min + (Y(r.min) - y) / (Y(r.min) - Y(r.max)) * (r.max - r.min)
  const signed = (v: number) => (v < 0 ? '−' : '+') + fmt(Math.abs(v), dec)
  const pct = (a: number, b: number) => a !== 0 && Number.isFinite(a) && Number.isFinite(b) ? `${b >= a ? '+' : '−'}${Math.abs((b - a) / a * 100).toFixed(2)}%` : '—'
  const nBars = (t0: number, t1: number) => Math.round(ch.indexAt(t1) - ch.indexAt(t0))
  const barsText = (t0: number, t1: number) => `${nBars(t0, t1)} 根，${durText(Math.abs(t1 - t0))}`
  const col = d.color || '#2962FF'
  const M: LineS = { on: true, color: col, width: d.width || 2, dash: d.dash ?? 'solid' }
  const mainDash = dashPattern(d)
  const isMain = (s: LineS) => s === M
  const st = (s: LineS) => ({ col: s.color, w: s.width, dash: isMain(s) ? mainDash : dashOf(s.dash, s.width), main: isMain(s) })
  const A = pts[0], B = pts[1] ?? A, C = pts[2] ?? B
  const tint = (t: 'up' | 'down') => t === 'up' ? ch.colors.up || '#089981' : ch.colors.down || '#F23645'

  // ---- 基本笔画
  /** a → b 按参数 [from, to] 裁进图区（射线 / 延长线用 ±Infinity） */
  const line = (a: XY, b: XY, s: LineS, from = 0, to = 1, t?: 'up' | 'down'): void => {
    const dx = b.x - a.x, dy = b.y - a.y
    let lo = from, hi = to
    for (const [o, dd, l, u] of [[a.x, dx, R.left, R.right], [a.y, dy, R.top, R.bottom]] as [number, number, number, number][]) {
      if (Math.abs(dd) < 1e-12) { if (o < l || o > u) return }
      else { const t1 = (l - o) / dd, t2 = (u - o) / dd; lo = Math.max(lo, Math.min(t1, t2)); hi = Math.min(hi, Math.max(t1, t2)) }
    }
    if (!(lo <= hi && Number.isFinite(lo) && Number.isFinite(hi))) return
    g.segments.push({ a: px(a.x + lo * dx, a.y + lo * dy), b: px(a.x + hi * dx, a.y + hi * dy), ...st(s), ...(t ? { tint: t, col: tint(t), main: true } : {}) })
  }
  const polyline = (ps: XY[], s: LineS) => { for (let i = 1; i < ps.length; i++) line(ps[i - 1], ps[i], s) }
  const fillPoly = (ps: XY[], c: string, solid = false, t?: 'up' | 'down') => { if (ps.length >= 3) g.fills.push({ points: ps, col: c, solid, ...(t ? { tint: t } : {}) }) }
  const arrowHead = (tip: XY, tail: XY, c: string, w: number, t?: 'up' | 'down') => {
    const dx = tip.x - tail.x, dy = tip.y - tail.y, len = Math.hypot(dx, dy)
    if (!(len > 1e-6)) return
    const size = 7 + w * 2, ux = dx / len, uy = dy / len, hw = size * 0.5
    fillPoly([tip, px(tip.x - ux * size - uy * hw, tip.y - uy * size + ux * hw), px(tip.x - ux * size + uy * hw, tip.y - uy * size - ux * hw)], c, true, t)
  }
  const dot = (q: XY, rad: number, c: string) => fillPoly(Array.from({ length: 12 }, (_, i) => px(q.x + rad * Math.cos(i / 12 * Math.PI * 2), q.y + rad * Math.sin(i / 12 * Math.PI * 2))), c, true)
  const label = (L: Omit<TLabel, 'size'> & { size?: number }) => { if (L.text) g.labels.push({ size: 11, ...L }) }
  const bgA = () => 1 - svn(d, 'bgAlpha', 80) / 100
  const levelCol = (x: LevelRow) => x.c || col
  /** 用户写的那句字的样式（文字页） */
  const txt = (base: { x: number; y: number; align: TLabel['align']; base: TLabel['base'] }, text = d.text || ''): void => {
    const tb = boxS(d, 'txtBg')
    const tr = boxS(d, 'txtBorder')
    label({
      text, ...base, col: svs(d, 'txtColor', col) || col, size: svn(d, 'txtSize', 14), bold: svb(d, 'bold'), italic: svb(d, 'italic'),
      plate: tb.on || tr.on ? 'box' : 'none', bg: tb.on ? rgbaOf(tb.color) : undefined, border: tr.on ? tr.color : undefined,
    })
  }
  /** 沿一条线写字：水平对齐 = 起点 / 中点 / 终点，垂直 = 线上方 / 压线 / 线下方 */
  const textOnLine = (a: XY, b: XY) => {
    if (!d.text) return
    const h = svs(d, 'hAlign', 'center'), v = svs(d, 'vAlign', 'top')
    const L = a.x <= b.x ? a : b, Rr = a.x <= b.x ? b : a
    const q = h === 'left' ? L : h === 'right' ? Rr : px((a.x + b.x) / 2, (a.y + b.y) / 2)
    txt({ x: q.x, y: v === 'top' ? q.y - 6 : v === 'bottom' ? q.y + 6 : q.y, align: h === 'left' ? 'left' : h === 'right' ? 'right' : 'center', base: v === 'top' ? 'bottom' : v === 'bottom' ? 'top' : 'middle' })
  }
  /** 框里写字（矩形、椭圆） */
  const textInBox = (x0: number, y0: number, x1: number, y1: number) => {
    if (!d.text) return
    const h = svs(d, 'hAlign', 'center'), v = svs(d, 'vAlign', 'middle')
    txt({ x: h === 'left' ? x0 + 6 : h === 'right' ? x1 - 6 : (x0 + x1) / 2, y: v === 'top' ? y0 + 6 : v === 'bottom' ? y1 - 6 : (y0 + y1) / 2, align: h as TLabel['align'], base: v as TLabel['base'] })
  }
  const chipAt = (text: string, x: number, y: number, align: TLabel['align'] = 'center', base: TLabel['base'] = 'middle', bg = col, t?: 'up' | 'down') =>
    label({ text, x, y, col: '#FFFFFF', bg, plate: 'chip', align, base, size: 11, bold: true, ...(t ? { tint: t } : {}) })
  const priceChip = (v: number, y: number) => chipAt(price(v), PW - 2, y, 'right')
  const timeChip = (t: number, x: number) => chipAt(crossTimeLabel(t, ch.iv), x, R.bottom - 2, 'center', 'bottom')

  switch (d.type) {
    // ------------------------------------------------------------ 线
    case 'trend': case 'ray': case 'extended': case 'arrowLine': {
      const from = svb(d, 'extL') ? -Infinity : 0, to = svb(d, 'extR') ? Infinity : 1
      line(A, B, M, from, to)
      if (svs(d, 'startEnd', 'normal') === 'arrow') arrowHead(A, B, col, M.width)
      if (svs(d, 'endEnd', 'normal') === 'arrow') arrowHead(B, A, col, M.width)
      if (svb(d, 'midPt')) dot(px((A.x + B.x) / 2, (A.y + B.y) / 2), 3 + M.width / 2, col)
      if (svb(d, 'priceLbl') && !padded) {
        chipAt(price(P[0].p), A.x, A.y + (A.y <= B.y ? -8 : 8), 'center', A.y <= B.y ? 'bottom' : 'top')
        chipAt(price(P[1].p), B.x, B.y + (B.y < A.y ? -8 : 8), 'center', B.y < A.y ? 'bottom' : 'top')
      }
      textOnLine(A, B)
      // 统计：选中时显示（或「始终显示」）
      if ((sel || svb(d, 'statsAlways')) && !padded) {
        const rows: string[] = []
        const dp = P[1].p - P[0].p
        if (svb(d, 'statPrice') && svb(d, 'statPct')) rows.push(`${signed(dp)}（${pct(P[0].p, P[1].p)}）`)
        else if (svb(d, 'statPrice')) rows.push(signed(dp))
        else if (svb(d, 'statPct')) rows.push(pct(P[0].p, P[1].p))
        if (svb(d, 'statBars') && svb(d, 'statTime')) rows.push(barsText(P[0].t, P[1].t))
        else if (svb(d, 'statBars')) rows.push(`${nBars(P[0].t, P[1].t)} 根`)
        else if (svb(d, 'statTime')) rows.push(durText(Math.abs(P[1].t - P[0].t)))
        if (svb(d, 'statAngle')) rows.push(`${(-Math.atan2(B.y - A.y, B.x - A.x) * 180 / Math.PI).toFixed(1)}°`)
        if (rows.length) {
          const pos = svs(d, 'statsPos', 'right')
          const q = pos === 'left' ? (A.x <= B.x ? A : B) : pos === 'center' ? px((A.x + B.x) / 2, (A.y + B.y) / 2) : (A.x <= B.x ? B : A)
          label({ text: rows.join('\n'), x: q.x + (pos === 'right' ? 10 : pos === 'left' ? -10 : 0), y: q.y + 12, col: ch.colors.text || col, size: 12, align: pos === 'right' ? 'left' : pos === 'left' ? 'right' : 'center', base: 'top', plate: 'box', bg: rgbaOf((ch.colors.bg || '#FFFFFF').slice(0, 7), 0.92), border: col })
        }
      }
      break
    }
    case 'hline': {
      line(px(R.left, A.y), px(R.right, A.y), M)
      if (sv(d, 'showPrice') !== false) priceChip(P[0].p, A.y)
      if (d.text) {
        const h = svs(d, 'hAlign', 'center'), v = svs(d, 'vAlign', 'top')
        txt({ x: h === 'left' ? 8 : h === 'right' ? PW - 80 : PW / 2, y: v === 'top' ? A.y - 5 : v === 'bottom' ? A.y + 5 : A.y, align: h === 'left' ? 'left' : h === 'right' ? 'right' : 'center', base: v === 'top' ? 'bottom' : v === 'bottom' ? 'top' : 'middle' })
      }
      g.handles = [A]
      break
    }
    case 'hray': {
      line(A, px(A.x + 1, A.y), M, 0, Infinity)
      if (g.segments.length && sv(d, 'showPrice') !== false) priceChip(P[0].p, A.y)
      if (d.text) {
        const h = svs(d, 'hAlign', 'center'), v = svs(d, 'vAlign', 'top'), x0 = Math.max(0, A.x)
        txt({ x: h === 'left' ? x0 + 6 : h === 'right' ? PW - 80 : (x0 + PW) / 2, y: v === 'top' ? A.y - 5 : v === 'bottom' ? A.y + 5 : A.y, align: h === 'left' ? 'left' : h === 'right' ? 'right' : 'center', base: v === 'top' ? 'bottom' : v === 'bottom' ? 'top' : 'middle' })
      }
      break
    }
    case 'vline': {
      line(px(A.x, R.top), px(A.x, R.bottom), M)
      if (sv(d, 'showTime') !== false) timeChip(P[0].t, A.x)
      if (d.text) {
        const h = svs(d, 'hAlign', 'center'), v = svs(d, 'vAlign', 'top')
        txt({ x: h === 'left' ? A.x - 6 : h === 'right' ? A.x + 6 : A.x, y: v === 'top' ? R.top + 8 : v === 'bottom' ? R.bottom - 28 : (R.top + R.bottom) / 2, align: h === 'left' ? 'right' : h === 'right' ? 'left' : 'center', base: v === 'top' ? 'top' : v === 'bottom' ? 'bottom' : 'middle' })
      }
      g.handles = [A]
      break
    }
    case 'crossLine':
      line(px(R.left, A.y), px(R.right, A.y), M)
      line(px(A.x, R.top), px(A.x, R.bottom), M)
      if (sv(d, 'showPrice') !== false) priceChip(P[0].p, A.y)
      if (sv(d, 'showTime') !== false) timeChip(P[0].t, A.x)
      g.handles = [A]
      break

    // ------------------------------------------------------------ 通道
    case 'channel': {
      const dx = B.x - A.x, dy = B.y - A.y, len = dx * dx + dy * dy
      if (!(len > 1e-9)) break
      const f = ((C.x - A.x) * -dy + (C.y - A.y) * dx) / len
      const U = px(A.x - dy * f, A.y + dx * f), V = px(B.x - dy * f, B.y + dx * f)
      const corners = [px(R.left, R.top), px(R.right, R.top), px(R.right, R.bottom), px(R.left, R.bottom)]
      const proj = corners.map(q => ((q.x - A.x) * dx + (q.y - A.y) * dy) / len)
      const lo = svb(d, 'extL') ? Math.min(0, ...proj) : 0, hi = svb(d, 'extR') ? Math.max(1, ...proj) : 1
      const first = px(A.x + dx * lo, A.y + dy * lo), last = px(A.x + dx * hi, A.y + dy * hi)
      if (fillOn(d)) fillPoly([first, last, px(last.x - dy * f, last.y + dx * f), px(first.x - dy * f, first.y + dx * f)], fillOf(d))
      line(A, B, M, lo, hi); line(U, V, M, lo, hi)
      const mid = lineS(d, 'midLine')
      if (mid.on) line(px((A.x + U.x) / 2, (A.y + U.y) / 2), px((B.x + V.x) / 2, (B.y + V.y) / 2), mid, lo, hi)
      textOnLine(A, B)
      break
    }
    case 'regression': {
      const dx = B.x - A.x, dy = B.y - A.y, len = dx * dx + dy * dy
      if (!(len > 1e-9)) break
      const f = ((C.x - A.x) * -dy + (C.y - A.y) * dx) / len
      let ox = -dy * f, oy = dx * f
      if (oy > 0) { ox = -ox; oy = -oy } // 朝上的那一侧
      const k1 = svn(d, 'devUp', 2) / 2, k2 = svn(d, 'devDn', -2) / 2
      const to = svb(d, 'extR') ? Infinity : 1
      const up = [px(A.x + ox * k1, A.y + oy * k1), px(B.x + ox * k1, B.y + oy * k1)]
      const dn = [px(A.x + ox * k2, A.y + oy * k2), px(B.x + ox * k2, B.y + oy * k2)]
      const useUp = sv(d, 'useUp') !== false, useDn = sv(d, 'useDn') !== false
      if (fillOn(d)) {
        const ext = (q: XY[]) => to === Infinity ? [q[0], px(q[0].x + (q[1].x - q[0].x) * BIG, q[0].y + (q[1].y - q[0].y) * BIG)] : q
        const u = useUp ? ext(up) : ext([A, B]), w = useDn ? ext(dn) : ext([A, B])
        fillPoly([u[0], u[1], w[1], w[0]], fillOf(d))
      }
      const base = lineS(d, 'base'), ul = lineS(d, 'upLine'), dl = lineS(d, 'dnLine')
      if (base.on) line(A, B, base, 0, to)
      const asMain = (s: LineS) => s.color === col && s.width === M.width && s.dash === M.dash ? M : s
      if (useUp && ul.on) line(up[0], up[1], asMain(ul), 0, to)
      if (useDn && dl.on) line(dn[0], dn[1], asMain(dl), 0, to)
      if (sv(d, 'pearson') !== false && !padded) {
        const rr = pearson(ch, P[0].t, P[1].t)
        if (rr != null) label({ text: rr.toFixed(3), x: dn[0].x, y: dn[0].y + 6, col, size: 12, align: 'left', base: 'top', plate: 'none' })
      }
      break
    }

    // ------------------------------------------------------------ 叉子与江恩
    case 'pitchfork': {
      const fork = svs(d, 'fork', 'original')
      const mBC = px((B.x + C.x) / 2, (B.y + C.y) / 2)
      const O = fork === 'schiff' ? px(A.x, (A.y + B.y) / 2) : fork === 'modschiff' ? px((A.x + B.x) / 2, (A.y + B.y) / 2) : A
      const dx = mBC.x - O.x, dy = mBC.y - O.y
      if (!(Math.hypot(dx, dy) > 1e-6)) break
      const to = svb(d, 'extR') ? Infinity : 1
      const rows = levelRows(d).filter(x => x.on).sort((a, b) => a.v - b.v)
      const at = (v: number, side: 1 | -1) => { const e = side > 0 ? B : C; return px(mBC.x + (e.x - mBC.x) * v, mBC.y + (e.y - mBC.y) * v) }
      const far = (q: XY) => to === Infinity ? px(q.x + dx * BIG, q.y + dy * BIG) : px(q.x + dx, q.y + dy)
      if (fillOn(d)) {
        let prev = 0
        for (const x of rows) for (const s of [1, -1] as const) {
          const a0 = at(prev, s), a1 = at(x.v, s)
          fillPoly([a0, far(a0), far(a1), a1], rgbaOf(levelCol(x).slice(0, 7), bgA()))
          if (s === -1) prev = x.v
        }
      }
      line(B, C, M)
      const med = lineS(d, 'midLine')
      if (med.on) line(O, mBC, med, 0, to)
      if (fork !== 'original') line(A, O, M)
      for (const x of rows) for (const s of [1, -1] as const) {
        const q = at(x.v, s)
        line(q, px(q.x + dx, q.y + dy), x.c ? { on: true, color: x.c, width: M.width, dash: M.dash } : M, 0, to)
      }
      break
    }
    case 'gannBox': {
      const x0 = Math.min(A.x, B.x), x1 = Math.max(A.x, B.x), y0 = Math.min(A.y, B.y), y1 = Math.max(A.y, B.y)
      const rev = svb(d, 'reverse')
      const prs = levelRows(d).filter(x => x.on).sort((a, b) => a.v - b.v), tms = levelRows(d, 'tlevels').filter(x => x.on).sort((a, b) => a.v - b.v)
      const yAt = (v: number) => rev ? y0 + (y1 - y0) * v : y1 - (y1 - y0) * v
      const xAt = (v: number) => rev ? x1 - (x1 - x0) * v : x0 + (x1 - x0) * v
      const sOf = (x: LevelRow): LineS => x.c ? { on: true, color: x.c, width: M.width, dash: M.dash } : M
      if (fillOn(d)) for (let i = 1; i < prs.length; i++) fillPoly([px(x0, yAt(prs[i - 1].v)), px(x1, yAt(prs[i - 1].v)), px(x1, yAt(prs[i].v)), px(x0, yAt(prs[i].v))], rgbaOf(levelCol(prs[i]).slice(0, 7), bgA()))
      for (const x of prs) line(px(x0, yAt(x.v)), px(x1, yAt(x.v)), sOf(x))
      for (const x of tms) line(px(xAt(x.v), y0), px(xAt(x.v), y1), sOf(x))
      const ang = lineS(d, 'angles')
      if (ang.on) { line(px(x0, y1), px(x1, y0), ang); line(px(x0, y0), px(x1, y1), ang) }
      for (const x of prs) {
        if (sv(d, 'lblL') !== false) label({ text: level3(x.v), x: x0 - 4, y: yAt(x.v), col: levelCol(x), align: 'right', base: 'middle', plate: 'none' })
        if (sv(d, 'lblR') !== false) label({ text: level3(x.v), x: x1 + 4, y: yAt(x.v), col: levelCol(x), align: 'left', base: 'middle', plate: 'none' })
      }
      for (const x of tms) {
        if (sv(d, 'lblT') !== false) label({ text: level3(x.v), x: xAt(x.v), y: y0 - 3, col: levelCol(x), align: 'center', base: 'bottom', plate: 'none' })
        if (sv(d, 'lblB') !== false) label({ text: level3(x.v), x: xAt(x.v), y: y1 + 3, col: levelCol(x), align: 'center', base: 'top', plate: 'none' })
      }
      break
    }
    case 'gannFan': {
      const dx = B.x - A.x, dy = B.y - A.y
      if (!(Math.abs(dx) > 1e-6)) break
      const rows = levelRows(d).filter(x => x.on).sort((a, b) => a.v - b.v)
      const thru = (v: number) => px(B.x, A.y + dy * v)
      const far = (q: XY) => px(A.x + (q.x - A.x) * BIG, A.y + (q.y - A.y) * BIG)
      if (fillOn(d)) for (let i = 1; i < rows.length; i++) fillPoly([A, far(thru(rows[i - 1].v)), far(thru(rows[i].v))], rgbaOf(levelCol(rows[i]).slice(0, 7), bgA()))
      for (const x of rows) {
        const q = thru(x.v)
        line(A, q, x.c ? { on: true, color: x.c, width: M.width, dash: M.dash } : M, 0, Infinity)
        if (sv(d, 'coeffs') !== false) label({ text: x.v >= 1 ? `${level3(x.v)}/1` : `1/${level3(1 / x.v)}`, x: q.x + 4, y: q.y, col: levelCol(x), align: 'left', base: 'middle', plate: 'none' })
      }
      break
    }

    // ------------------------------------------------------------ 斐波那契
    case 'fib': case 'fibExtension': {
      const ext = d.type === 'fibExtension'
      const tr = lineS(d, 'trend')
      if (tr.on) { line(A, B, tr); if (ext) line(B, C, tr) }
      const rev = svb(d, 'reverse')
      const valueOf = (v: number) => ext ? P[2].p + (P[1].p - P[0].p) * (rev ? -v : v) : rev ? P[0].p + (P[1].p - P[0].p) * v : P[1].p + (P[0].p - P[1].p) * v
      let x0 = ext ? C.x : Math.min(A.x, B.x), x1 = ext ? C.x + Math.max(Math.abs(B.x - A.x), 60) : Math.max(A.x, B.x)
      if (svb(d, 'extL')) x0 = R.left
      if (svb(d, 'extR')) x1 = R.right
      const rows = levelRows(d).filter(x => x.on).sort((a, b) => a.v - b.v)
      if (fillOn(d)) for (let i = 1; i < rows.length; i++) {
        const ya = Y(valueOf(rows[i - 1].v)), yb = Y(valueOf(rows[i].v))
        fillPoly([px(x0, ya), px(x1, ya), px(x1, yb), px(x0, yb)], rgbaOf(levelCol(rows[i]).slice(0, 7), bgA()))
      }
      levelLines(rows, valueOf, x0, x1)
      break
    }
    case 'fibChannel': {
      const dx = B.x - A.x, dy = B.y - A.y, len = dx * dx + dy * dy
      if (!(len > 1e-9)) break
      const f = ((C.x - A.x) * -dy + (C.y - A.y) * dx) / len
      const corners = [px(R.left, R.top), px(R.right, R.top), px(R.right, R.bottom), px(R.left, R.bottom)]
      const proj = corners.map(q => ((q.x - A.x) * dx + (q.y - A.y) * dy) / len)
      const lo = svb(d, 'extL') ? Math.min(0, ...proj) : 0, hi = svb(d, 'extR') ? Math.max(1, ...proj) : 1
      const rows = levelRows(d).filter(x => x.on).sort((a, b) => a.v - b.v)
      const off = (v: number) => px(-dy * f * v, dx * f * v)
      if (fillOn(d)) for (let i = 1; i < rows.length; i++) {
        const o0 = off(rows[i - 1].v), o1 = off(rows[i].v)
        const s0 = px(A.x + dx * lo, A.y + dy * lo), s1 = px(A.x + dx * hi, A.y + dy * hi)
        fillPoly([px(s0.x + o0.x, s0.y + o0.y), px(s1.x + o0.x, s1.y + o0.y), px(s1.x + o1.x, s1.y + o1.y), px(s0.x + o1.x, s0.y + o1.y)], rgbaOf(levelCol(rows[i]).slice(0, 7), bgA()))
      }
      const lh = svs(d, 'lblH', 'left'), lv = svs(d, 'lblV', 'middle'), size = svn(d, 'lblSize', 12)
      for (const x of rows) {
        const o = off(x.v), a = px(A.x + o.x, A.y + o.y), b = px(B.x + o.x, B.y + o.y)
        line(a, b, x.c ? { on: true, color: x.c, width: M.width, dash: M.dash } : M, lo, hi)
        const q = lh === 'right' ? b : lh === 'center' ? px((a.x + b.x) / 2, (a.y + b.y) / 2) : a
        const text = [sv(d, 'coeffs') !== false ? level3(x.v) : '', sv(d, 'prices') !== false ? `(${price(priceAtY(q.y))})` : ''].filter(Boolean).join(' ')
        label({ text, x: q.x + (lh === 'left' ? -4 : lh === 'right' ? 4 : 0), y: q.y + (lv === 'top' ? -3 : lv === 'bottom' ? 3 : 0), col: levelCol(x), size, align: lh === 'left' ? 'right' : lh === 'right' ? 'left' : 'center', base: lv === 'top' ? 'bottom' : lv === 'bottom' ? 'top' : 'middle', plate: 'none' })
      }
      break
    }
    case 'fibTimeZone': {
      const unit = P[1].t - P[0].t
      const tr = lineS(d, 'trend')
      if (tr.on) line(A, B, tr)
      if (!(Math.abs(unit) > 0)) break
      const rows = levelRows(d).filter(x => x.on).sort((a, b) => a.v - b.v)
      const xs = rows.map(x => X(P[0].t + unit * x.v))
      if (fillOn(d)) for (let i = 1; i < rows.length; i++) fillPoly([px(xs[i - 1], R.top), px(xs[i], R.top), px(xs[i], R.bottom), px(xs[i - 1], R.bottom)], rgbaOf(levelCol(rows[i]).slice(0, 7), bgA()))
      const lh = svs(d, 'lblH', 'right'), lv = svs(d, 'lblV', 'bottom'), size = svn(d, 'lblSize', 12)
      rows.forEach((x, i) => {
        if (!Number.isFinite(xs[i])) return
        line(px(xs[i], R.top), px(xs[i], R.bottom), x.c ? { on: true, color: x.c, width: M.width, dash: M.dash } : M)
        if (sv(d, 'coeffs') !== false) label({ text: level3(x.v), x: xs[i] + (lh === 'right' ? 4 : lh === 'left' ? -4 : 0), y: lv === 'top' ? R.top + 4 : lv === 'bottom' ? R.bottom - 4 : (R.top + R.bottom) / 2, col: levelCol(x), size, align: lh === 'right' ? 'left' : lh === 'left' ? 'right' : 'center', base: lv === 'top' ? 'top' : lv === 'bottom' ? 'bottom' : 'middle', plate: 'none' })
      })
      break
    }
    case 'fibFan': {
      const pr = levelRows(d).filter(x => x.on).sort((a, b) => a.v - b.v), tm = levelRows(d, 'tlevels').filter(x => x.on).sort((a, b) => a.v - b.v)
      const thruP = (v: number) => px(B.x, A.y + (B.y - A.y) * v), thruT = (v: number) => px(A.x + (B.x - A.x) * v, B.y)
      const far = (q: XY) => px(A.x + (q.x - A.x) * BIG, A.y + (q.y - A.y) * BIG)
      const sOf = (x: LevelRow): LineS => x.c ? { on: true, color: x.c, width: M.width, dash: M.dash } : M
      if (fillOn(d)) {
        for (let i = 1; i < pr.length; i++) fillPoly([A, far(thruP(pr[i - 1].v)), far(thruP(pr[i].v))], rgbaOf(levelCol(pr[i]).slice(0, 7), bgA()))
        for (let i = 1; i < tm.length; i++) fillPoly([A, far(thruT(tm[i - 1].v)), far(thruT(tm[i].v))], rgbaOf(levelCol(tm[i]).slice(0, 7), bgA()))
      }
      const grid = lineS(d, 'grid')
      if (grid.on) {
        for (const x of pr) line(px(A.x, thruP(x.v).y), thruP(x.v), grid)
        for (const x of tm) line(px(thruT(x.v).x, A.y), thruT(x.v), grid)
      }
      for (const x of pr) line(A, thruP(x.v), sOf(x), 0, Infinity)
      for (const x of tm) line(A, thruT(x.v), sOf(x), 0, Infinity)
      const xl = Math.min(A.x, B.x), xr = Math.max(A.x, B.x), yt = Math.min(A.y, B.y), yb = Math.max(A.y, B.y)
      for (const x of pr) {
        const y = thruP(x.v).y
        if (sv(d, 'lblL') !== false) label({ text: level3(x.v), x: xl - 4, y, col: levelCol(x), align: 'right', base: 'middle', plate: 'none' })
        if (sv(d, 'lblR') !== false) label({ text: level3(x.v), x: xr + 4, y, col: levelCol(x), align: 'left', base: 'middle', plate: 'none' })
      }
      for (const x of tm) {
        const xx = thruT(x.v).x
        if (sv(d, 'lblT') !== false) label({ text: level3(x.v), x: xx, y: yt - 3, col: levelCol(x), align: 'center', base: 'bottom', plate: 'none' })
        if (sv(d, 'lblB') !== false) label({ text: level3(x.v), x: xx, y: yb + 3, col: levelCol(x), align: 'center', base: 'top', plate: 'none' })
      }
      break
    }

    // ------------------------------------------------------------ 形态
    case 'xabcd': case 'abcd': {
      const xa = d.type === 'xabcd'
      if (xa && fillOn(d) && pts.length >= 5) { fillPoly([pts[0], pts[1], pts[2]], fillOf(d)); fillPoly([pts[2], pts[3], pts[4]], fillOf(d)) }
      polyline(pts, M)
      if (padded) break
      const dashS: LineS = { on: true, color: col, width: 1, dash: 'dashed' }
      const ratio = (i: number, j: number, k: number, l: number) => { const den = Math.abs(P[j].p - P[i].p); return den > 0 ? Math.abs(P[l].p - P[k].p) / den : null }
      const conn = (i: number, j: number, rv: number | null) => {
        line(pts[i], pts[j], dashS)
        if (rv != null) label({ text: rv.toFixed(3), x: (pts[i].x + pts[j].x) / 2, y: (pts[i].y + pts[j].y) / 2, col, size: svn(d, 'txtSize', 12) - 1, align: 'center', base: 'middle', plate: 'wash' })
      }
      if (xa) { conn(0, 2, ratio(0, 1, 1, 2)); conn(1, 3, ratio(1, 2, 2, 3)); conn(2, 4, ratio(2, 3, 3, 4)); conn(0, 4, ratio(0, 1, 1, 4)) }
      else { conn(0, 2, ratio(0, 1, 1, 2)); conn(1, 3, ratio(1, 2, 2, 3)) }
      pointNames(xa ? ['X', 'A', 'B', 'C', 'D'] : ['A', 'B', 'C', 'D'], true)
      break
    }
    case 'headShoulders': {
      if (fillOn(d) && pts.length >= 7) { fillPoly([pts[0], pts[1], pts[2]], fillOf(d)); fillPoly([pts[2], pts[3], pts[4]], fillOf(d)); fillPoly([pts[4], pts[5], pts[6]], fillOf(d)) }
      polyline(pts, M)
      if (pts.length >= 7 && !padded) {
        const dx = pts[4].x - pts[2].x
        if (Math.abs(dx) > 1e-6) {
          const k0 = (pts[0].x - pts[2].x) / dx, k1 = (pts[6].x - pts[2].x) / dx
          line(pts[2], pts[4], M, Math.min(k0, k1, 0), Math.max(k0, k1, 1))
        }
        pointNames(['', '左肩', '', '头', '', '右肩', ''], true)
      }
      break
    }
    case 'elliottImpulse': case 'elliottCorrection':
      polyline(pts, M)
      if (!padded) pointNames(waveLabels(d.type, svs(d, 'degree', 'minor')), false)
      break
    case 'triangle':
      if (fillOn(d)) fillPoly([A, B, C], fillOf(d))
      polyline([A, B, C, A], M)
      break

    // ------------------------------------------------------------ 预测与测量
    case 'ptMeasure': {
      const rose = P[1].p >= P[0].p, t: 'up' | 'down' = rose ? 'up' : 'down'
      const x0 = Math.min(A.x, B.x), x1 = Math.max(A.x, B.x), y0 = Math.min(A.y, B.y), y1 = Math.max(A.y, B.y)
      if (fillOn(d)) fillPoly([px(x0, y0), px(x1, y0), px(x1, y1), px(x0, y1)], d.style?.fill ? fillOf(d) : rgbaOf(tint(t), 0.15), false, t)
      const mid = (x0 + x1) / 2, mY = (y0 + y1) / 2
      line(px(mid, A.y), px(mid, B.y), M, 0, 1, t); arrowHead(px(mid, B.y), px(mid, A.y), tint(t), M.width, t)
      line(px(A.x, mY), px(B.x, mY), M, 0, 1, t); arrowHead(px(B.x, mY), px(A.x, mY), tint(t), M.width, t)
      if (!padded) rangeLabel(`${signed(P[1].p - P[0].p)}（${pct(P[0].p, P[1].p)}）\n${barsText(P[0].t, P[1].t)}`, mid, rose ? y0 - 6 : y1 + 6, rose ? 'bottom' : 'top', t)
      break
    }
    case 'priceRange': {
      let x0 = Math.min(A.x, B.x), x1 = Math.max(A.x, B.x)
      if (svb(d, 'extL')) x0 = R.left
      if (svb(d, 'extR')) x1 = R.right
      if (fillOn(d)) fillPoly([px(x0, A.y), px(x1, A.y), px(x1, B.y), px(x0, B.y)], fillOf(d))
      line(px(x0, A.y), px(x1, A.y), M); line(px(x0, B.y), px(x1, B.y), M)
      const mid = (Math.min(A.x, B.x) + Math.max(A.x, B.x)) / 2
      line(px(mid, A.y), px(mid, B.y), M); arrowHead(px(mid, B.y), px(mid, A.y), col, M.width)
      const up = B.y <= A.y
      if (!padded) rangeLabel(`${signed(P[1].p - P[0].p)}（${pct(P[0].p, P[1].p)}）`, mid, up ? B.y - 6 : B.y + 6, up ? 'bottom' : 'top')
      break
    }
    case 'dateRange': {
      const y0 = Math.min(A.y, B.y), y1 = Math.max(A.y, B.y)
      if (fillOn(d)) fillPoly([px(A.x, y0), px(B.x, y0), px(B.x, y1), px(A.x, y1)], fillOf(d))
      line(px(A.x, y0), px(A.x, y1), M); line(px(B.x, y0), px(B.x, y1), M)
      const mY = (y0 + y1) / 2
      line(px(A.x, mY), px(B.x, mY), M); arrowHead(px(B.x, mY), px(A.x, mY), col, M.width)
      if (!padded) rangeLabel(barsText(P[0].t, P[1].t), (A.x + B.x) / 2, y1 + 6, 'top')
      break
    }
    case 'datePriceRange': {
      const x0 = Math.min(A.x, B.x), x1 = Math.max(A.x, B.x), y0 = Math.min(A.y, B.y), y1 = Math.max(A.y, B.y)
      if (fillOn(d)) fillPoly([px(x0, y0), px(x1, y0), px(x1, y1), px(x0, y1)], fillOf(d))
      const bd = lineS(d, 'border')
      if (bd.on) polyline([px(x0, y0), px(x1, y0), px(x1, y1), px(x0, y1), px(x0, y0)], bd.color === col && bd.width === M.width ? M : bd)
      const mid = (x0 + x1) / 2, mY = (y0 + y1) / 2
      line(px(mid, A.y), px(mid, B.y), M); arrowHead(px(mid, B.y), px(mid, A.y), col, M.width)
      line(px(A.x, mY), px(B.x, mY), M); arrowHead(px(B.x, mY), px(A.x, mY), col, M.width)
      if (!padded) rangeLabel(`${signed(P[1].p - P[0].p)}（${pct(P[0].p, P[1].p)}）\n${barsText(P[0].t, P[1].t)}`, mid, y1 + 6, 'top')
      break
    }

    // ------------------------------------------------------------ 形状
    case 'rect': {
      const x0 = Math.min(A.x, B.x), x1 = Math.max(A.x, B.x), y0 = Math.min(A.y, B.y), y1 = Math.max(A.y, B.y)
      const eL = svb(d, 'extL') ? R.left : x0, eR = svb(d, 'extR') ? R.right : x1
      if (fillOn(d)) fillPoly([px(eL, y0), px(eR, y0), px(eR, y1), px(eL, y1)], fillOf(d))
      line(px(x0, y0), px(x0, y1), M); line(px(x1, y0), px(x1, y1), M)
      line(px(eL, y0), px(eR, y0), M); line(px(eL, y1), px(eR, y1), M)
      const mid = lineS(d, 'midLine')
      if (mid.on) line(px(eL, (y0 + y1) / 2), px(eR, (y0 + y1) / 2), mid)
      textInBox(x0, y0, x1, y1)
      break
    }
    case 'ellipse': {
      const cx = (A.x + B.x) / 2, cy = (A.y + B.y) / 2, rx = Math.abs(B.x - A.x) / 2, ry = Math.abs(B.y - A.y) / 2
      if (!(rx > 0.5 && ry > 0.5)) break
      const ring = Array.from({ length: 64 }, (_, i) => px(cx + rx * Math.cos(i / 64 * Math.PI * 2), cy + ry * Math.sin(i / 64 * Math.PI * 2)))
      if (fillOn(d)) fillPoly(ring, fillOf(d))
      polyline(ring.concat([ring[0]]), M)
      textInBox(cx - rx, cy - ry, cx + rx, cy + ry)
      break
    }
    case 'curve': {
      const ps: XY[] = []
      for (let i = 0; i <= 32; i++) { const t = i / 32, u = 1 - t; ps.push(px(u * u * A.x + 2 * u * t * C.x + t * t * B.x, u * u * A.y + 2 * u * t * C.y + t * t * B.y)) }
      polyline(ps, M)
      if (svs(d, 'startEnd', 'normal') === 'arrow') arrowHead(ps[0], ps[2], col, M.width)
      if (svs(d, 'endEnd', 'normal') === 'arrow') arrowHead(ps[32], ps[30], col, M.width)
      break
    }

    // ------------------------------------------------------------ 注释
    case 'note':
      txt({ x: A.x, y: A.y - 4, align: 'left', base: 'bottom' }, d.text || '点这里写字')
      break
    case 'callout': {
      line(B, A, M); arrowHead(A, B, col, M.width)
      label({ text: d.text || '点这里写字', x: B.x, y: B.y, col: svs(d, 'txtColor', '#FFFFFF'), size: svn(d, 'txtSize', 14), bold: svb(d, 'bold'), italic: svb(d, 'italic'), align: 'left', base: 'bottom', plate: 'box', bg: fillOn(d) ? fillOf(d) : undefined, border: col })
      break
    }
    case 'priceLabel':
      fillPoly([A, px(A.x - 5, A.y - 9), px(A.x + 5, A.y - 9)], col, true)
      label({ text: price(P[0].p), x: A.x, y: A.y - 8, col: svs(d, 'txtColor', '#FFFFFF'), size: svn(d, 'txtSize', 14), bold: sv(d, 'bold') !== false, align: 'center', base: 'bottom', plate: 'chip', bg: col })
      break
    case 'flag': {
      line(A, px(A.x, A.y - 24), M)
      const flag = [px(A.x, A.y - 24), px(A.x + 18, A.y - 19), px(A.x, A.y - 14)]
      if (fillOn(d)) fillPoly(flag, col, true)
      polyline(flag, M)
      if (d.text) label({ text: d.text, x: A.x + 22, y: A.y - 19, col: svs(d, 'txtColor', col), size: svn(d, 'txtSize', 12), align: 'left', base: 'middle', plate: 'wash' })
      break
    }
    case 'markerUp': case 'markerDown': {
      const up = d.type === 'markerUp', mc = sv(d, 'mc') as string | undefined
      const t: 'up' | 'down' | undefined = mc ? undefined : up ? 'up' : 'down'
      const c = mc ? mc : tint(up ? 'up' : 'down')
      const s = up ? 1 : -1
      const shape = [A, px(A.x - 8, A.y + s * 10), px(A.x - 3.5, A.y + s * 10), px(A.x - 3.5, A.y + s * 22), px(A.x + 3.5, A.y + s * 22), px(A.x + 3.5, A.y + s * 10), px(A.x + 8, A.y + s * 10)]
      if (fillOn(d)) fillPoly(shape, c, true, t)
      const ms: LineS = { on: true, color: c, width: 1, dash: 'solid' }
      for (let i = 0; i < shape.length; i++) line(shape[i], shape[(i + 1) % shape.length], ms, 0, 1, t)
      if (d.text) label({ text: d.text, x: A.x, y: A.y + s * 26, col: svs(d, 'txtColor', c), size: svn(d, 'txtSize', 12), align: 'center', base: up ? 'top' : 'bottom', plate: 'none', ...(t && !d.style?.txtColor ? { tint: t } : {}) })
      break
    }
  }
  if (padded && PATTERN.has(d.type)) g.labels = []
  return g

  // ---- 共用的几样（function 声明，提到前面可用）
  function levelLines(rows: LevelRow[], valueOf: (v: number) => number, x0: number, x1: number): void {
    const lh = svs(d, 'lblH', 'left'), lv = svs(d, 'lblV', 'middle'), size = svn(d, 'lblSize', 12)
    const showP = sv(d, 'prices') !== false, showC = sv(d, 'coeffs') !== false, asPct = svb(d, 'pct')
    for (const x of rows) {
      const v = valueOf(x.v), y = Y(v)
      if (!Number.isFinite(y)) continue
      line(px(x0, y), px(x1, y), x.c ? { on: true, color: x.c, width: M.width, dash: M.dash } : M)
      const text = [showC ? (asPct ? `${+(x.v * 100).toFixed(1)}%` : level3(x.v)) : '', showP ? `(${price(v)})` : ''].filter(Boolean).join(' ')
      label({ text, x: lh === 'left' ? x0 - 4 : lh === 'right' ? x1 + 4 : (x0 + x1) / 2, y: lv === 'top' ? y - 2 : lv === 'bottom' ? y + 2 : y, col: levelCol(x), size, align: lh === 'left' ? 'right' : lh === 'right' ? 'left' : 'center', base: lv === 'top' ? 'bottom' : lv === 'bottom' ? 'top' : 'middle', plate: lh === 'center' && lv === 'middle' ? 'wash' : 'none' })
    }
  }
  /** 形态各点的名字：高点写在上方、低点写在下方 */
  function pointNames(names: string[], chip: boolean): void {
    pts.forEach((q, i) => {
      const nm = names[i]; if (!nm) return
      const nb = [pts[i - 1], pts[i + 1]].filter(Boolean) as XY[]
      const high = !nb.length || q.y <= nb.reduce((s, o) => s + o.y, 0) / nb.length
      const size = svn(d, 'txtSize', 12)
      if (chip) label({ text: nm, x: q.x, y: q.y + (high ? -6 : 6), col: svs(d, 'txtColor', '#FFFFFF'), bg: col, size, bold: svb(d, 'bold'), italic: svb(d, 'italic'), align: 'center', base: high ? 'bottom' : 'top', plate: 'chip' })
      else label({ text: nm, x: q.x, y: q.y + (high ? -6 : 6), col: svs(d, 'txtColor', col), size, bold: svb(d, 'bold'), italic: svb(d, 'italic'), align: 'center', base: high ? 'bottom' : 'top', plate: 'none' })
    })
  }
  /** 区间测量的读数块：底色（关了就只有字） */
  function rangeLabel(text: string, x: number, y: number, base: TLabel['base'], t?: 'up' | 'down'): void {
    const bg = boxS(d, 'lblBg')
    const custom = !!(d.style?.lblBg as { color?: string } | undefined)?.color
    const bgc = t && !custom ? tint(t) : bg.color
    label({ text, x, y, col: svs(d, 'txtColor', '#FFFFFF'), size: svn(d, 'txtSize', 12), align: 'center', base, plate: bg.on ? 'chip' : 'none', bg: bgc, ...(t && !custom ? { tint: t } : {}) })
  }
}

/** 收盘价对时间的皮尔逊相关系数（回归通道圈住的那段） */
function pearson(ch: TVChart, t0: number, t1: number): number | null {
  const i0 = Math.max(0, Math.round(ch.indexAt(Math.min(t0, t1)))), i1 = Math.min(ch.bars.length - 1, Math.round(ch.indexAt(Math.max(t0, t1))))
  const n = i1 - i0 + 1
  if (n < 3) return null
  let sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0
  for (let i = i0; i <= i1; i++) { const y = ch.bars[i].c, x = i - i0; sx += x; sy += y; sxx += x * x; syy += y * y; sxy += x * y }
  const cov = sxy - sx * sy / n, vx = sxx - sx * sx / n, vy = syy - sy * sy / n
  return vx > 0 && vy > 0 ? cov / Math.sqrt(vx * vy) : null
}

/** 字块排版：按对齐量出盖住的矩形；整个落在窗格外的不要 */
export function placeLabels(labels: readonly TLabel[], fam: string, measure: (font: string, s: string) => number, paneY: number, paneH: number, plotW: number): TPlaced[] {
  const out: TPlaced[] = []
  for (const L of labels) {
    const font = `${L.italic ? 'italic ' : ''}${L.bold ? '600 ' : ''}${L.size}px ${fam}`
    const lines = L.text.split('\n')
    const w = Math.max(...lines.map(s => measure(font, s)))
    const lineH = Math.round(L.size * 1.3)
    const padX = L.plate === 'none' ? 0 : L.plate === 'wash' ? 3 : L.plate === 'chip' ? 5 : 7
    const padY = L.plate === 'none' ? 0 : L.plate === 'wash' ? 1 : L.plate === 'chip' ? 2 : 4
    const W = w + padX * 2, H = lines.length * lineH + padY * 2
    let left = L.align === 'left' ? L.x : L.align === 'right' ? L.x - W : L.x - W / 2
    if (L.plate === 'chip') left = Math.max(2, Math.min(plotW - W - 2, left))
    const top = L.base === 'top' ? L.y : L.base === 'bottom' ? L.y - H : L.y - H / 2
    const box = { left, top, right: left + W, bottom: top + H }
    if (box.bottom < paneY || box.top > paneY + paneH || box.right < 0 || box.left > plotW) continue
    out.push({ label: L, box, center: { x: (box.left + box.right) / 2, y: (box.top + box.bottom) / 2 }, font, lineH, lines })
  }
  return out
}
