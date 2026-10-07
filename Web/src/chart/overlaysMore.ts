/* Hkline Web · 第三批主图叠加的画法（算法与目录在 mainIndicators.ts）
 *
 * 画法照 TradingView 各内置指标的默认样式：
 *   均线族一条 1.5 px 线；肯特纳 / 唐奇安 / 包络线三条线 + 5% 蓝色填充；抛物线 SAR 小蓝点；
 *   波动止损多头绿、空头红的小十字；鳄鱼线三条往右推的线（画到最新一根之后）；
 *   威廉分形高点上方红三角、低点下方绿三角；之字转向蓝线 1.5 px，最后一段虚线连到最新收盘；
 *   枢轴点每段一组水平虚线，P 深色底白 / 浅色底黑、R 红、S 绿，段尾标名字。
 *
 * 只从 chart.ts 拿类型，运行时不反向依赖（chart.ts 调这里的函数）。
 */
import { hexA } from '../util/format'
import type { Series } from './calc'
import type { Pane, PriceRange, TVChart } from './chart'
import { MORE_MAIN_CATALOG, mainOn, pivotPeriodStart, type MoreMainId } from './mainIndicators'

type Ctx = CanvasRenderingContext2D
const BLUE = '#2962FF'

function path(ch: TVChart, s: Series, p: Pane, r: PriceRange, from: number, to: number, col: string, width: number): void {
  const c: Ctx = ch.ctx
  c.strokeStyle = col; c.lineWidth = width; c.lineJoin = 'round'; c.lineCap = 'round'; c.beginPath()
  let st = false
  for (let i = Math.max(0, from - 1); i <= Math.min(to, s.length - 1); i++) {
    const v = s[i]; if (v == null) { st = false; continue }
    const x = ch.indexToX(i), y = ch.priceToY(v, p, r)
    if (st) c.lineTo(x, y); else { c.moveTo(x, y); st = true }
  }
  c.stroke()
}
function fillBetween(ch: TVChart, a: Series, b: Series, p: Pane, r: PriceRange, from: number, to: number, color: string): void {
  const c: Ctx = ch.ctx
  c.fillStyle = color
  for (let i = Math.max(1, from); i <= Math.min(to, a.length - 1, b.length - 1); i++) {
    const a0 = a[i - 1], a1 = a[i], b0 = b[i - 1], b1 = b[i]
    if (a0 == null || a1 == null || b0 == null || b1 == null) continue
    const x0 = ch.indexToX(i - 1), x1 = ch.indexToX(i)
    c.beginPath()
    c.moveTo(x0, ch.priceToY(a0, p, r)); c.lineTo(x1, ch.priceToY(a1, p, r)); c.lineTo(x1, ch.priceToY(b1, p, r)); c.lineTo(x0, ch.priceToY(b0, p, r)); c.closePath(); c.fill()
  }
}
/** 深色主题：底色够暗（枢轴点 P 线深色底白、浅色底黑） */
export function darkBg(bg: string): boolean {
  const m = /^#?([0-9a-f]{6})$/i.exec(bg.trim())
  if (!m) return true
  const n = parseInt(m[1], 16), lum = 0.2126 * (n >> 16 & 255) + 0.7152 * (n >> 8 & 255) + 0.0722 * (n & 255)
  return lum < 128
}
export const pivotPColor = (ch: TVChart): string => darkBg(ch.colors.bg) ? '#FFFFFF' : '#000000'

const MA_FAMILY: MoreMainId[] = ['wma', 'hma', 'dema', 'tema', 'smma', 'vwma', 'lsma', 'alma', 'mcg']

/** 主图上第三批叠加（紧跟 drawExtraMain 画，在最新价线与画线之下） */
export function drawMoreMain(ch: TVChart, p: Pane, r: PriceRange, from: number, to: number): void {
  if (!ch.ind.mains?.length) return
  const on = (id: MoreMainId) => mainOn(ch.ind, id) && !ch.hidden.has(id) && !!ch.series[id]
  const c: Ctx = ch.ctx, last = ch.lastIndex()
  c.save()
  // 通道：先铺底色再画线
  for (const id of ['kc', 'dc', 'env'] as const) {
    if (!on(id)) continue
    const s = ch.series[id]!, cols = MORE_MAIN_CATALOG[id].colors!
    fillBetween(ch, s[1], s[2], p, r, from, to, hexA(BLUE, 0.05))
    path(ch, s[1], p, r, from, to, cols[1], 1); path(ch, s[2], p, r, from, to, cols[2], 1)
    path(ch, s[0], p, r, from, to, cols[0], 1)
  }
  if (on('pivots')) drawPivots(ch, p, r, from, to)
  for (const id of MA_FAMILY) if (on(id)) path(ch, ch.series[id]![0], p, r, from, to, MORE_MAIN_CATALOG[id].colors![0], 1.5)
  if (on('alligator')) {
    const s = ch.series.alligator!, cols = MORE_MAIN_CATALOG.alligator.colors!
    const far = Math.min(Math.max(...s.map(x => x.length)) - 1, Math.ceil(ch.rightBar) + 1)
    // 回放时只画到回放那根往右推的位置，不泄露后面的 K 线
    s.forEach((x, k) => path(ch, x, p, r, from, Math.min(far, last + (x.length - ch.bars.length)), cols[k], 1.5))
  }
  if (on('zigzag')) drawZigzag(ch, p, r, from, to)
  if (on('vstop')) {
    const [lg, sh] = ch.series.vstop!, cols = MORE_MAIN_CATALOG.vstop.colors!
    c.lineWidth = 1.5; c.lineCap = 'butt'
    const h = Math.max(2, Math.min(4, ch.candleW() / 2))
    for (const [s, col] of [[lg, cols[0]], [sh, cols[1]]] as const) {
      c.strokeStyle = col; c.beginPath()
      for (let i = Math.max(0, from); i <= Math.min(to, last); i++) {
        const v = s[i]; if (v == null) continue
        const x = Math.round(ch.indexToX(i)) + .5, y = Math.round(ch.priceToY(v, p, r)) + .5
        c.moveTo(x - h, y); c.lineTo(x + h, y); c.moveTo(x, y - h); c.lineTo(x, y + h)
      }
      c.stroke()
    }
  }
  if (on('sar')) {
    const s = ch.series.sar![0], rad = Math.max(1.25, Math.min(2.5, ch.candleW() / 4))
    c.fillStyle = BLUE; c.beginPath()
    for (let i = Math.max(0, from); i <= Math.min(to, last); i++) {
      const v = s[i]; if (v == null) continue
      const x = ch.indexToX(i), y = ch.priceToY(v, p, r)
      c.moveTo(x + rad, y); c.arc(x, y, rad, 0, Math.PI * 2)
    }
    c.fill()
  }
  if (on('fractals')) {
    const [up, dn] = ch.series.fractals!, cols = MORE_MAIN_CATALOG.fractals.colors!, n = Math.max(1, Math.round(ch.params.fractals?.n ?? 2))
    const w = Math.max(3, Math.min(5, ch.candleW() / 2)), gap = 6
    for (const [s, col, isUp] of [[up, cols[0], true], [dn, cols[1], false]] as const) {
      c.fillStyle = col; c.beginPath()
      for (let i = Math.max(0, from); i <= to; i++) {
        const v = s[i]; if (v == null || i + n > last) continue
        const x = ch.indexToX(i), y = ch.priceToY(v, p, r)
        // 上分形：最高价上方一个尖朝上的三角；下分形：最低价下方一个尖朝下的三角
        if (isUp) { const b = y - gap; c.moveTo(x, b - w * 1.4); c.lineTo(x + w, b); c.lineTo(x - w, b) }
        else { const t = y + gap; c.moveTo(x, t + w * 1.4); c.lineTo(x + w, t); c.lineTo(x - w, t) }
        c.closePath()
      }
      c.fill()
    }
  }
  c.restore()
}

/** 之字转向：把可见区里（连同两边各一个）的转折连起来；最后一个转折到最新收盘画虚线 */
function drawZigzag(ch: TVChart, p: Pane, r: PriceRange, from: number, to: number): void {
  const s = ch.series.zigzag![0], c: Ctx = ch.ctx, last = ch.lastIndex()
  const half = Math.max(1, Math.floor(Math.round(ch.params.zigzag?.n ?? 10) / 2))
  const pts: [number, number][] = []
  let before: [number, number] | null = null, after: [number, number] | null = null
  for (let i = 0; i < Math.min(s.length, last + 1); i++) {
    const v = s[i]; if (v == null || i + half > last) continue
    if (i < from) before = [i, v]
    else if (i <= to) pts.push([i, v])
    else { after = [i, v]; break }
  }
  if (before) pts.unshift(before)
  if (after) pts.push(after)
  if (!pts.length) return
  c.strokeStyle = BLUE; c.lineWidth = 1.5; c.lineJoin = 'round'; c.lineCap = 'round'
  c.beginPath()
  pts.forEach(([i, v], k) => { const x = ch.indexToX(i), y = ch.priceToY(v, p, r); if (k) c.lineTo(x, y); else c.moveTo(x, y) })
  c.stroke()
  const tail = pts[pts.length - 1], lb = ch.bars[last]
  if (!after && lb && tail[0] < last) {
    c.setLineDash([4, 4]); c.beginPath()
    c.moveTo(ch.indexToX(tail[0]), ch.priceToY(tail[1], p, r)); c.lineTo(ch.indexToX(last), ch.priceToY(lb.c, p, r))
    c.stroke(); c.setLineDash([])
  }
}

/** 枢轴点：每一段（天 / 周 / 月 / 年）一组水平虚线，段尾标 P / R1 / S1…；最后一段画到绘图区右沿 */
function drawPivots(ch: TVChart, p: Pane, r: PriceRange, from: number, to: number): void {
  const s = ch.series.pivots!, c: Ctx = ch.ctx, cols = MORE_MAIN_CATALOG.pivots.colors!, labels = MORE_MAIN_CATALOG.pivots.labels!
  const last = ch.lastIndex(), iv = ch.iv, pc = pivotPColor(ch), half = ch.candleW() / 2 + 1
  const font = ch.font.split('px ')[1] || 'sans-serif'
  c.font = `11px ${font}`; c.textBaseline = 'bottom'; c.textAlign = 'right'; c.lineWidth = 1
  const hi = Math.min(to, last)
  let i = Math.max(0, from)
  // 从这段的第一根找起（左沿切进一段时，那段从屏幕外开始）
  while (i > 0 && ch.bars[i - 1] && pivotPeriodStart(ch.bars[i - 1].t, iv) === pivotPeriodStart(ch.bars[i].t, iv)) i--
  while (i <= hi) {
    const st = pivotPeriodStart(ch.bars[i].t, iv)
    let j = i
    while (j + 1 <= last && ch.bars[j + 1] && pivotPeriodStart(ch.bars[j + 1].t, iv) === st) j++
    if (s[0][i] != null) {
      const x0 = ch.indexToX(i) - half, x1 = j === last ? Math.max(ch.indexToX(j) + half, ch.plotW() - 2) : ch.indexToX(j) + half
      for (let k = 0; k < 7; k++) {
        const v = s[k][i]; if (v == null) continue
        const y = Math.round(ch.priceToY(v, p, r)) + .5, col = cols[k] || pc
        if (y < p.y - 20 || y > p.y + p.h + 20) continue
        c.strokeStyle = hexA(col, 0.85); c.setLineDash([4, 3]); c.beginPath(); c.moveTo(x0, y); c.lineTo(x1, y); c.stroke(); c.setLineDash([])
        if (x1 - x0 > 28) { c.fillStyle = col; c.fillText(labels[k], x1 - 2, y - 2) }
      }
    }
    i = j + 1
  }
}
