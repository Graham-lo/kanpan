/* Hkline Web · 主图第二批叠加的画法：VWAP 带、超级趋势、一目均衡表、成交量分布（VPVR）
 *
 * 成交量分布按「可见区间」现算：缩放、平移一动就重算（算量是可见根数 × 行数，2K 屏上几百根、几十行，可以每帧算）。
 * 画在绘图区右侧约四分之一宽，控制点（成交最多的一行）一条横线贯穿，七成价值区的行更实、区外更淡。
 * 三种看法一个下拉切：买卖分开、净差、合计。
 *
 * 只从 chart.ts 拿类型，运行时不反向依赖（chart.ts 调这里的函数）。
 */
import { hexA } from '../util/format'
import type { Bar, Series } from './calc'
import { SUB_LEVELS, barInterval, vwapAnchor, type ExtraSubId } from './indicators'
import type { Pane, PriceRange, TVChart } from './chart'
import { fineSplit } from './fineVolume'

export type VpvrMode = 'split' | 'delta' | 'total'
export const VPVR_MODES: { id: VpvrMode; label: string }[] = [
  { id: 'split', label: '买卖分开' },
  { id: 'delta', label: '净差' },
  { id: 'total', label: '合计' },
]

export interface VpvrRow { buy: number; sell: number }
export interface Vpvr {
  lo: number
  hi: number
  step: number
  rows: VpvrRow[]
  /** 控制点：合计最大的一行 */
  poc: number
  /** 价值区（含两端的行号） */
  vaLo: number
  vaHi: number
  total: number
}

/** 成交量分布：把 [from, to] 每根 K 线的成交额按它的高低区间摊到覆盖的各行（按重叠长度分），
 *  主动买入 = tb，主动卖出 = 总额 − tb（没有 tb 时对半）；再从控制点往两边扩，每次并进较大的一侧，直到 ≥ 七成 */
export function vpvr(bars: Bar[], from: number, to: number, rowCount: number, vaShare = 0.7, split?: ((i: number) => Bar[] | null) | null): Vpvr | null {
  from = Math.max(0, from); to = Math.min(bars.length - 1, to)
  if (to < from || rowCount < 1) return null
  let lo = Infinity, hi = -Infinity
  for (let i = from; i <= to; i++) { const b = bars[i]; if (Number.isFinite(b.l) && b.l < lo) lo = b.l; if (Number.isFinite(b.h) && b.h > hi) hi = b.h }
  if (!isFinite(lo) || !isFinite(hi)) return null
  const n = Math.max(1, Math.round(rowCount))
  if (hi <= lo) hi = lo + Math.max(Math.abs(lo) * 1e-6, 1e-12)
  const step = (hi - lo) / n
  const rows: VpvrRow[] = Array.from({ length: n }, () => ({ buy: 0, sell: 0 }))
  const rowOf = (p: number) => Math.min(n - 1, Math.max(0, Math.floor((p - lo) / step)))
  const spread = (b: Bar) => {
    const v = b.v
    // 坏量、坏价不摊：一根 Infinity 会让每一行和总量都变 Infinity，整张分布图画不出来
    if (!(v > 0) || !Number.isFinite(v) || !Number.isFinite(b.l) || !Number.isFinite(b.h)) return
    const buy = b.tb != null && isFinite(b.tb) ? Math.min(v, Math.max(0, b.tb)) : v / 2, sell = v - buy
    const r0 = rowOf(b.l), r1 = rowOf(b.h), span = b.h - b.l
    if (r0 === r1 || span <= 0) { rows[r0].buy += buy; rows[r0].sell += sell; return }
    for (let r = r0; r <= r1; r++) {
      const a = Math.max(b.l, lo + r * step), z = Math.min(b.h, lo + (r + 1) * step)
      const f = Math.max(0, z - a) / span
      rows[r].buy += buy * f; rows[r].sell += sell * f
    }
  }
  // 粗 K 线被细 K 线盖住时用细 K 线各自的高低去摊（4 小时及以上，见 fineVolume.ts）
  for (let i = from; i <= to; i++) {
    const sub = split?.(i)
    if (sub) for (const x of sub) spread(x)
    else spread(bars[i])
  }
  let total = 0, poc = 0, best = -1
  rows.forEach((r, k) => { const t = r.buy + r.sell; total += t; if (t > best) { best = t; poc = k } })
  let vaLo = poc, vaHi = poc, acc = best
  const tot = (k: number) => rows[k].buy + rows[k].sell
  while (acc < total * vaShare && (vaLo > 0 || vaHi < n - 1)) {
    const up = vaHi < n - 1 ? tot(vaHi + 1) : -1, dn = vaLo > 0 ? tot(vaLo - 1) : -1
    if (up >= dn) { vaHi++; acc += up } else { vaLo--; acc += dn }
  }
  return { lo, hi, step, rows, poc, vaLo, vaHi, total }
}

// ------------------------------------------------------------ 画
type Ctx = CanvasRenderingContext2D

function path(ch: TVChart, s: Series, p: Pane, r: PriceRange, from: number, to: number, col: string, width: number, breakAt?: (i: number) => boolean): void {
  const c: Ctx = ch.ctx
  c.strokeStyle = col; c.lineWidth = width; c.lineJoin = 'round'; c.lineCap = 'round'; c.beginPath()
  let st = false
  for (let i = Math.max(0, from - 1); i <= to; i++) {
    const v = s[i]; if (v == null) { st = false; continue }
    if (st && breakAt?.(i)) st = false
    const x = ch.indexToX(i), y = ch.priceToY(v, p, r)
    if (st) c.lineTo(x, y); else { c.moveTo(x, y); st = true }
  }
  c.stroke()
}

function fillBetween(ch: TVChart, a: Series, b: Series, p: Pane, r: PriceRange, from: number, to: number, color: (va: number, vb: number) => string, breakAt?: (i: number) => boolean): void {
  const c: Ctx = ch.ctx
  for (let i = Math.max(1, from); i <= to; i++) {
    const a0 = a[i - 1], a1 = a[i], b0 = b[i - 1], b1 = b[i]
    if (a0 == null || a1 == null || b0 == null || b1 == null || breakAt?.(i)) continue
    const x0 = ch.indexToX(i - 1), x1 = ch.indexToX(i)
    c.fillStyle = color(a1, b1); c.beginPath()
    c.moveTo(x0, ch.priceToY(a0, p, r)); c.lineTo(x1, ch.priceToY(a1, p, r)); c.lineTo(x1, ch.priceToY(b1, p, r)); c.lineTo(x0, ch.priceToY(b0, p, r)); c.closePath(); c.fill()
  }
}

/** 主图上第二批叠加（在均线之后、最新价线之前画） */
export function drawExtraMain(ch: TVChart, p: Pane, r: PriceRange, from: number, to: number): void {
  const on = (id: 'vwap' | 'st' | 'ichi' | 'vpvr') => !!ch.ind[id] && !ch.hidden.has(id)
  const C = ch.colors
  if (on('vpvr')) drawVpvr(ch, p, r, from, to)
  if (on('ichi')) {
    const s = ch.series.ichi
    if (s && s.length === 5) {
      const far = Math.min(s[2].length - 1, Math.ceil(ch.rightBar))
      fillBetween(ch, s[2], s[3], p, r, from, far, (a, b) => hexA(a >= b ? '#43A047' : '#F44336', 0.1))
      const cols = ['#2962FF', '#B71C1C', '#43A047', '#F44336', '#9C27B0']
      path(ch, s[0], p, r, from, to, cols[0], 1.5); path(ch, s[1], p, r, from, to, cols[1], 1.5)
      path(ch, s[2], p, r, from, far, cols[2], 1); path(ch, s[3], p, r, from, far, cols[3], 1)
      path(ch, s[4], p, r, from, to, cols[4], 1)
    }
  }
  if (on('vwap')) {
    const s = ch.series.vwap
    if (s && s.length === 5) {
      const iv = ch.iv || barInterval(ch.bars)
      const brk = (i: number) => i > 0 && !!ch.bars[i] && !!ch.bars[i - 1] && vwapAnchor(ch.bars[i].t, iv) !== vwapAnchor(ch.bars[i - 1].t, iv)
      fillBetween(ch, s[1], s[2], p, r, from, to, () => hexA('#26A69A', 0.06), brk)
      path(ch, s[3], p, r, from, to, hexA('#FF9800', 0.8), 1, brk); path(ch, s[4], p, r, from, to, hexA('#FF9800', 0.8), 1, brk)
      path(ch, s[1], p, r, from, to, '#26A69A', 1, brk); path(ch, s[2], p, r, from, to, '#26A69A', 1, brk)
      path(ch, s[0], p, r, from, to, '#2962FF', 1.5, brk)
    }
  }
  if (on('st')) {
    const s = ch.series.st
    if (s && s.length === 2) {
      // 线与收盘之间淡淡铺一层，多头涨色、空头跌色
      const close: Series = ch.bars.map(b => b.c)
      fillBetween(ch, s[0], close, p, r, from, to, () => hexA(C.up || '#089981', 0.07))
      fillBetween(ch, s[1], close, p, r, from, to, () => hexA(C.down || '#F23645', 0.07))
      path(ch, s[0], p, r, from, to, C.up || '#089981', 1.5); path(ch, s[1], p, r, from, to, C.down || '#F23645', 1.5)
    }
  }
}

function drawVpvr(ch: TVChart, p: Pane, r: PriceRange, from: number, to: number): void {
  const rows = Math.max(4, Math.min(200, Math.round(ch.params.vpvr?.n || 48)))
  const split = fineSplit(ch.meta.symbol, ch.iv, ch.bars, from, to, () => { if (!ch.dead) ch.dirty = true })
  const v = vpvr(ch.bars, from, to, rows, 0.7, split)
  if (!v || !v.total) return
  ch.vpvrLast = v
  const c: Ctx = ch.ctx, C = ch.colors, PW = ch.plotW(), maxW = PW * 0.25, mode = ch.vpvrMode
  let mx = 0
  for (const row of v.rows) mx = Math.max(mx, mode === 'delta' ? Math.abs(row.buy - row.sell) : row.buy + row.sell)
  if (!mx) return
  const up = C.up || '#089981', down = C.down || '#F23645', neutral = '#5B8DEF'
  v.rows.forEach((row, k) => {
    const y0 = ch.priceToY(v.lo + (k + 1) * v.step, p, r), y1 = ch.priceToY(v.lo + k * v.step, p, r)
    const top = Math.round(Math.min(y0, y1)) + 1, h = Math.max(1, Math.round(Math.abs(y1 - y0)) - 1)
    if (top > p.y + p.h || top + h < p.y) return
    const inVa = k >= v.vaLo && k <= v.vaHi, a = inVa ? 0.42 : 0.18
    if (mode === 'total') {
      const w = (row.buy + row.sell) / mx * maxW
      c.fillStyle = hexA(neutral, a); c.fillRect(PW - w, top, w, h)
    } else if (mode === 'delta') {
      const d = row.buy - row.sell, w = Math.abs(d) / mx * maxW
      c.fillStyle = hexA(d >= 0 ? up : down, a); c.fillRect(PW - w, top, w, h)
    } else {
      const wb = row.buy / mx * maxW, ws = row.sell / mx * maxW
      c.fillStyle = hexA(up, a); c.fillRect(PW - wb - ws, top, wb, h)
      c.fillStyle = hexA(down, a); c.fillRect(PW - ws, top, ws, h)
    }
  })
  const py = Math.round(ch.priceToY(v.lo + (v.poc + 0.5) * v.step, p, r)) + .5
  c.strokeStyle = '#FF9800'; c.lineWidth = 1; c.beginPath(); c.moveTo(0, py); c.lineTo(PW, py); c.stroke()
}

/** 副图参考线（随机 RSI 80/20、CCI ±100、威廉 −20/−80） */
export function drawSubLevels(ch: TVChart, p: Pane, r: PriceRange, id: string): void {
  if (id === 'cvd') drawCvdSeams(ch, p)
  const lv = SUB_LEVELS[id as ExtraSubId]
  if (!lv) return
  const c: Ctx = ch.ctx, PW = ch.plotW()
  c.setLineDash([4, 4]); c.strokeStyle = hexA(ch.colors.text3 || '#888', 0.7); c.lineWidth = 1; c.beginPath()
  for (const v of lv) { const y = Math.round(ch.priceToY(v, p, r)) + .5; c.moveTo(0, y); c.lineTo(PW, y) }
  c.stroke(); c.setLineDash([])
}

/** 累计量差的历史段（只有币安）/ 实时段（三家）分界：竖虚线，线两边底部各一个小字 */
function drawCvdSeams(ch: TVChart, p: Pane): void {
  const s = ch.series.cvd?.[1]
  if (!s) return
  const c: Ctx = ch.ctx, PW = ch.plotW(), col = hexA(ch.colors.text3 || '#888', 0.85)
  const from = Math.max(1, Math.floor(ch.xToIndex(0)) - 1), to = Math.min(s.length - 1, Math.ceil(ch.xToIndex(PW)) + 1)
  const seam = (at: number, left: string, right: string) => {
    const x = Math.round(ch.indexToX(at)) + .5
    if (x < 0 || x > PW) return
    c.setLineDash([3, 3]); c.strokeStyle = col; c.lineWidth = 1; c.beginPath(); c.moveTo(x, p.y); c.lineTo(x, p.y + p.h); c.stroke(); c.setLineDash([])
    c.fillStyle = col; c.font = `11px ${ch.font.split('px ')[1] || 'sans-serif'}`; c.textBaseline = 'alphabetic'
    const y = p.y + p.h - 6
    c.textAlign = 'right'; c.fillText(left, x - 5, y)
    c.textAlign = 'left'; c.fillText(right, x + 5, y)
    c.textBaseline = 'middle'; c.font = ch.font
  }
  for (let i = from; i <= to; i++) {
    const on = s[i] != null, prev = s[i - 1] != null
    // 实时段的第一个点是分叉点（进入实时段前一根的合计），分界画在它和下一根之间
    if (on && !prev) seam(i + 0.5, '币安', '三家')
    else if (!on && prev) seam(i - 0.5, '三家', '币安')
  }
}
