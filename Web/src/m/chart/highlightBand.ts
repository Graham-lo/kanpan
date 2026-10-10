/* Hkline 手机网页 · 图上的「要点带子」（盘口要点半页的价区 / 时段）
 *
 * 价区带：横向半透明带（主色 16%）+ 上下 0.8 的 70% 边线 + 右上角标签胶囊；
 * 时段带：竖向带 + 顶部标签。挂在图的附加图层上（不接触摸、不挡十字线），视野变了跟着重画。
 * 出现时 200 ms 淡入；减少动效时直接出现。
 */
import type { ChartHandle } from './index'
import type { ChartRenderer } from './renderer'
import type { ChartLayerHandle } from './view'
import { reducedMotion } from '../ui/dom'

export type Band =
  | { kind: 'price'; low: number; high: number; label: string }
  | { kind: 'time'; from: number; to: number; label: string }

/** 含时刻 t 的那一根（index 给的是最近的开盘时刻，往前挪到不晚于 t 的那根） */
export function barAt(series: { count: number; time(i: number): number; index(t: number): number }, t: number): number {
  if (series.count <= 0) return -1
  let i = series.index(t)
  if (i > 0 && series.time(i) > t) i -= 1
  return i
}

const FADE_MS = 200

let accentCache = { key: '', color: '#2E7D6B' }
function accent(): string {
  const root = document.documentElement
  const key = `${root.dataset.skin}|${root.dataset.theme}`
  if (key !== accentCache.key) {
    const v = getComputedStyle(root).getPropertyValue('--accent').trim()
    accentCache = { key, color: v || '#2E7D6B' }
  }
  return accentCache.color
}

export class HighlightBand {
  private layer: ChartLayerHandle | null = null
  private band: Band | null = null
  private alpha = 1
  private raf = 0

  constructor(private readonly chart: ChartHandle) {}

  get current(): Band | null { return this.band }

  set(b: Band | null): void {
    this.band = b
    if (this.raf) { cancelAnimationFrame(this.raf); this.raf = 0 }
    if (!b) { this.layer?.remove(); this.layer = null; return }
    if (!this.layer) this.layer = this.chart.view.addLayer((ctx, W, H, _s, r) => this.paint(ctx, W, H, r))
    if (reducedMotion() || typeof requestAnimationFrame === 'undefined') { this.alpha = 1; this.layer.redraw(); return }
    const t0 = performance.now()
    this.alpha = 0
    const step = (): void => {
      this.alpha = Math.min(1, (performance.now() - t0) / FADE_MS)
      this.layer?.redraw()
      this.raf = this.alpha < 1 ? requestAnimationFrame(step) : 0
    }
    this.raf = requestAnimationFrame(step)
  }

  clear(): void { this.set(null) }

  /** 皮肤换了：主色重取 */
  invalidate(): void { accentCache.key = ''; this.layer?.redraw() }

  private paint(ctx: CanvasRenderingContext2D, W: number, H: number, r: ChartRenderer): void {
    const b = this.band
    if (!b) return
    const L = r.layout(W, H)
    const pane = L.main
    const col = accent()
    ctx.save()
    ctx.beginPath(); ctx.rect(0, pane.y, L.plotW, pane.h); ctx.clip()
    ctx.globalAlpha = this.alpha
    ctx.font = '600 11px -apple-system, "PingFang SC", system-ui, sans-serif'
    const tw = ctx.measureText(b.label).width + 12
    if (b.kind === 'price') {
      const range = r.priceRange(W, H)
      const yHi = r.yOf(b.high, pane, range), yLo = r.yOf(b.low, pane, range)
      let top = Math.min(yHi, yLo), bot = Math.max(yHi, yLo)
      if (bot - top < 3) { const m = (top + bot) / 2; top = m - 1.5; bot = m + 1.5 }
      ctx.fillStyle = col
      ctx.globalAlpha = this.alpha * 0.16
      ctx.fillRect(0, top, L.plotW, bot - top)
      ctx.globalAlpha = this.alpha * 0.7
      ctx.lineWidth = 0.8; ctx.strokeStyle = col
      ctx.beginPath(); ctx.moveTo(0, top); ctx.lineTo(L.plotW, top); ctx.moveTo(0, bot); ctx.lineTo(L.plotW, bot); ctx.stroke()
      this.pill(ctx, b.label, L.plotW - tw - 6, Math.max(pane.y + 2, top - 18), tw, col)
    } else {
      const series = r.state.input.series
      if (series.count <= 0) { ctx.restore(); return }
      const i0 = barAt(series, b.from), i1 = barAt(series, b.to)
      const half = Math.max(2, r.spacing(L.plotW) / 2)
      const x0 = r.x(series.time(i0), L.plotW) - half, x1 = r.x(series.time(i1), L.plotW) + half
      ctx.fillStyle = col
      ctx.globalAlpha = this.alpha * 0.16
      ctx.fillRect(x0, pane.y, x1 - x0, pane.h)
      ctx.globalAlpha = this.alpha * 0.7
      ctx.lineWidth = 0.8; ctx.strokeStyle = col
      ctx.beginPath(); ctx.moveTo(x0, pane.y); ctx.lineTo(x0, pane.y + pane.h); ctx.moveTo(x1, pane.y); ctx.lineTo(x1, pane.y + pane.h); ctx.stroke()
      const lx = Math.max(2, Math.min(L.plotW - tw - 2, (x0 + x1) / 2 - tw / 2))
      this.pill(ctx, b.label, lx, pane.y + 6, tw, col)
    }
    ctx.restore()
  }

  private pill(ctx: CanvasRenderingContext2D, text: string, x: number, y: number, w: number, col: string): void {
    ctx.globalAlpha = this.alpha
    ctx.fillStyle = col
    ctx.beginPath(); ctx.roundRect(x, y, w, 16, 8); ctx.fill()
    ctx.fillStyle = '#fff'; ctx.textAlign = 'left'; ctx.textBaseline = 'middle'
    ctx.fillText(text, x + 6, y + 8.5)
  }
}
