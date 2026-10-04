/* Hkline Web · 复盘：画在 K 线上面的一层（透明画布，不接鼠标）
 *
 * 图表引擎本身不改，这一层只借它的几何：indexAt / indexToX / priceToY / _panes / _ranges。
 * 交易回放不用引擎自带的 setMarkers——那个会把整段持仓区间先铺出来，等于提前露出平仓点；
 * 这里只画「已经放到」的成交、开仓均价和观点的参考 / 目标 / 失效线，未来一律不画。
 */
import type { TVChart } from '../chart/chart'
import { fmt, hexA } from '../util/format'
import { ROLE_LABEL } from './model'
import { visibleMarks, type Plan } from './replay'

interface Colors { up: string; down: string; accent: string; warn: string; text1: string; text2: string; text3: string; surface: string; font: string }

export class ReviewOverlay {
  canvas: HTMLCanvasElement
  ctx: CanvasRenderingContext2D
  chart: TVChart
  plan: Plan | null = null
  /** 已经放到的那根 K 线的开盘时间 */
  revealed = 0
  dec = 2
  private sig = ''
  private pw = 0
  private raf = 0
  private dead = false
  /** 复盘页切走时睡下：不再每帧比对几何（页面藏着时图表也不画） */
  private asleep = false
  private col: Colors = { up: '', down: '', accent: '', warn: '', text1: '', text2: '', text3: '', surface: '', font: '' }

  constructor(wrap: HTMLElement, chart: TVChart) {
    this.chart = chart
    this.canvas = document.createElement('canvas')
    this.canvas.className = 'rv-overlay'
    this.canvas.setAttribute('aria-hidden', 'true')
    wrap.appendChild(this.canvas)
    this.ctx = this.canvas.getContext('2d') as CanvasRenderingContext2D
    this.readTheme()
    this.raf = requestAnimationFrame(this.loop)
  }

  readTheme(): void {
    const cs = getComputedStyle(this.chart.host)
    const v = (n: string) => cs.getPropertyValue(n).trim()
    const fam = getComputedStyle(document.body).getPropertyValue('--font-num').trim() || 'sans-serif'
    this.col = { up: v('--up'), down: v('--down'), accent: v('--accent'), warn: v('--warn'), text1: v('--text-1'), text2: v('--text-2'), text3: v('--text-3'), surface: v('--surface'), font: fam }
    this.sig = ''
  }

  set(plan: Plan | null, revealed: number, dec: number): void { this.plan = plan; this.revealed = revealed; this.dec = dec; this.sig = '' }
  setRevealed(t: number): void { if (t !== this.revealed) { this.revealed = t; this.sig = '' } }

  destroy(): void { this.dead = true; cancelAnimationFrame(this.raf); this.canvas.remove() }
  sleep(): void { this.asleep = true; cancelAnimationFrame(this.raf); this.raf = 0 }
  wake(): void {
    if (this.dead || !this.asleep) return
    this.asleep = false; this.sig = ''
    this.raf = requestAnimationFrame(this.loop)
  }

  private loop = (): void => {
    if (this.dead || this.asleep) return
    const c = this.chart, r = c._ranges.main
    const s = [c.rightBar, c.spacing, c.replay, c.w, c.h, c.aw, r?.min, r?.max, c.bars.length, this.revealed, this.plan ? 1 : 0].join('|')
    if (s !== this.sig) { this.sig = s; this.draw() }
    this.raf = requestAnimationFrame(this.loop)
  }

  private draw(): void {
    const c = this.chart, ctx = this.ctx
    const w = c.w, h = c.h, dpr = window.devicePixelRatio || 1
    if (this.canvas.width !== Math.round(w * dpr) || this.canvas.height !== Math.round(h * dpr)) {
      this.canvas.width = Math.round(w * dpr); this.canvas.height = Math.round(h * dpr)
      this.canvas.style.width = w + 'px'; this.canvas.style.height = h + 'px'
    }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    ctx.clearRect(0, 0, w, h)
    const pane = c._panes?.[0], range = c._ranges.main
    if (!this.plan || !pane || !range || !c.bars.length) return
    const PW = c.plotW()
    this.pw = PW
    ctx.save(); ctx.beginPath(); ctx.rect(0, pane.y, PW, pane.h); ctx.clip()
    const X = (t: number) => c.indexToX(c.indexAt(t))
    const Y = (p: number) => c.priceToY(p, pane, range)
    const half = Math.max(1, c.spacing / 2)
    const p = this.plan
    if (p.kind === 'trade') this.drawTrade(p, X, Y, half, pane.y, pane.h)
    else if (p.kind === 'note') this.drawNote(p, X, Y, half, pane.y, pane.h, PW)
    else this.drawMatch(p, X, half, pane.y, pane.h)
    ctx.restore()
  }

  private label(x: number, y: number, text: string, bg: string, fg = '#fff', align: 'left' | 'right' | 'center' = 'left'): void {
    const ctx = this.ctx
    ctx.font = `600 11px ${this.col.font}`
    const tw = Math.ceil(ctx.measureText(text).width) + 12
    let lx = align === 'left' ? x : align === 'right' ? x - tw : x - tw / 2
    // 贴着右边放不下就翻到线的左边，再夹进画布，别被价格轴切掉
    if (align === 'left' && lx + tw > this.pw - 2) lx = x - 8 - tw
    lx = Math.max(2, Math.min(this.pw - tw - 2, lx))
    ctx.fillStyle = bg
    ctx.beginPath(); ctx.roundRect(lx, y - 9, tw, 18, 4); ctx.fill()
    ctx.fillStyle = fg; ctx.textAlign = 'left'; ctx.textBaseline = 'middle'
    ctx.fillText(text, lx + 6, y + .5)
  }

  private drawTrade(p: Extract<Plan, { kind: 'trade' }>, X: (t: number) => number, Y: (v: number) => number, half: number, py: number, ph: number): void {
    const ctx = this.ctx, C = this.col, rv = this.revealed
    if (rv < p.openBar) return
    // 持仓区间：从开仓那根到「已放到」或平仓那根，淡淡铺一层
    const end = Math.min(rv, p.closed ? p.closeBar : rv)
    ctx.fillStyle = hexA(C.accent, 0.06)
    ctx.fillRect(X(p.openBar) - half, py, X(end) + half - (X(p.openBar) - half), ph)
    // 开仓均价：每次开 / 加仓后的一段虚线
    ctx.setLineDash([5, 4]); ctx.lineWidth = 1; ctx.strokeStyle = hexA(C.accent, 0.9)
    let lastSeg: { x: number; y: number; price: number } | null = null
    for (const s of p.avgSegs) {
      if (s.from > rv) break
      const to = Math.min(s.to, rv)
      const x0 = X(s.from) - half, x1 = X(to) + half, y = Math.round(Y(s.price)) + .5
      ctx.beginPath(); ctx.moveTo(x0, y); ctx.lineTo(x1, y); ctx.stroke()
      lastSeg = { x: x1, y, price: s.price }
    }
    ctx.setLineDash([])
    if (lastSeg && (!p.closed || rv < p.closeBar)) this.label(lastSeg.x + 4, lastSeg.y, `均价 ${fmt(lastSeg.price, this.dec)}`, C.accent)
    // 成交：买在下方朝上的三角，卖在上方朝下的三角，旁边标开仓 / 加仓 / 减仓 / 平仓
    for (const m of visibleMarks(p, rv)) {
      const x = X(m.bar), y = Y(m.price)
      const buy = m.side === 'BUY'
      const col = buy ? C.up : C.down
      ctx.fillStyle = col
      ctx.beginPath()
      if (buy) { ctx.moveTo(x, y + 3); ctx.lineTo(x - 6, y + 12); ctx.lineTo(x + 6, y + 12) }
      else { ctx.moveTo(x, y - 3); ctx.lineTo(x - 6, y - 12); ctx.lineTo(x + 6, y - 12) }
      ctx.closePath(); ctx.fill()
      ctx.strokeStyle = col; ctx.lineWidth = 1
      ctx.beginPath(); ctx.moveTo(x - 8, Math.round(y) + .5); ctx.lineTo(x + 8, Math.round(y) + .5); ctx.stroke()
      const text = `${ROLE_LABEL[m.role] ?? m.role} ${fmt(m.price, this.dec)}`
      this.label(x, buy ? y + 25 : y - 25, text, col, '#fff', 'center')
    }
  }

  private drawNote(p: Extract<Plan, { kind: 'note' }>, X: (t: number) => number, Y: (v: number) => number, half: number, py: number, ph: number, PW: number): void {
    const ctx = this.ctx, C = this.col, rv = this.revealed
    // 当时看的那段图表区间
    const lastRangeBar = p.rangeEnd - p.step
    const r0 = X(p.rangeStart) - half, r1 = X(Math.min(lastRangeBar, rv)) + half
    if (rv >= p.rangeStart) { ctx.fillStyle = hexA(C.text3, 0.07); ctx.fillRect(r0, py, r1 - r0, ph) }
    if (rv < p.judgeBar) return
    // 判断处竖线
    const xj = Math.round(X(p.judgeBar)) + .5
    ctx.strokeStyle = hexA(C.text2, 0.7); ctx.lineWidth = 1; ctx.setLineDash([3, 3])
    ctx.beginPath(); ctx.moveTo(xj, py); ctx.lineTo(xj, py + ph); ctx.stroke(); ctx.setLineDash([])
    this.label(xj + 4, py + 100, '判断', hexA(C.text2, 0.9))
    // 参考 / 目标 / 失效：从判断处画到已放到的位置（或到期、答案处）
    const stopT = Math.min(rv, p.eventBar ?? Infinity, p.expireBar ?? Infinity)
    const x1 = Math.min(PW, X(stopT) + half)
    const tags: { y: number; text: string; col: string }[] = []
    const line = (price: number, col: string, dash: number[], text: string) => {
      const y = Math.round(Y(price)) + .5
      ctx.strokeStyle = col; ctx.lineWidth = 1; ctx.setLineDash(dash)
      ctx.beginPath(); ctx.moveTo(xj, y); ctx.lineTo(x1, y); ctx.stroke(); ctx.setLineDash([])
      tags.push({ y, text: `${text} ${fmt(price, this.dec)}`, col })
    }
    const rule = p.rule
    if (rule.direction !== 'observe') {
      line(rule.target, C.accent, [], '目标')
      line(rule.invalidation, C.warn, [], '失效')
    }
    line(rule.reference, hexA(C.text2, 0.9), [4, 3], rule.direction === 'observe' ? '当时价' : '参考')
    // 三条线价位挨得近时标签会叠在一起：按高低排好，至少隔开一个标签高
    tags.sort((a, b) => a.y - b.y)
    for (let i = 1; i < tags.length; i++) tags[i].y = Math.max(tags[i].y, tags[i - 1].y + 20)
    for (const t of tags) this.label(x1 + 4, t.y, t.text, t.col)
    // 答案处 / 到期处
    const endMark = (t: number | null, text: string, col: string) => {
      if (t == null || t > rv) return
      const x = Math.round(X(t)) + .5
      ctx.strokeStyle = col; ctx.lineWidth = 1
      ctx.beginPath(); ctx.moveTo(x, py); ctx.lineTo(x, py + ph); ctx.stroke()
      this.label(x + 4, py + 124, text, col)
    }
    const good = p.outcome === 'realized'
    if (p.eventBar != null) endMark(p.eventBar, good ? '判对' : p.outcome === 'unrealized' ? '判错' : '答案', good ? C.accent : C.warn)
    else endMark(p.expireBar, '到期', C.text2)
  }

  private drawMatch(p: Extract<Plan, { kind: 'match' }>, X: (t: number) => number, half: number, py: number, ph: number): void {
    const ctx = this.ctx, C = this.col
    const x0 = X(p.rangeStart) - half, x1 = X(Math.min(p.rangeEnd - p.step, this.revealed)) + half
    ctx.fillStyle = hexA(C.accent, 0.08); ctx.fillRect(x0, py, x1 - x0, ph)
    ctx.strokeStyle = hexA(C.accent, 0.6); ctx.lineWidth = 1
    ctx.beginPath(); ctx.moveTo(Math.round(x0) + .5, py); ctx.lineTo(Math.round(x0) + .5, py + ph)
    if (this.revealed >= p.rangeEnd - p.step) { ctx.moveTo(Math.round(x1) + .5, py); ctx.lineTo(Math.round(x1) + .5, py + ph) }
    ctx.stroke()
    this.label(x0 + 4, py + 100, '相似段', C.accent)
  }
}
