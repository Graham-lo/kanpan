/* Hkline 手机网页 · 图上大单签：图层（画布、命中、光环、读屏）
 *
 * 自己一块画布（ChartView.addLayer，插在画线覆盖层下面），几何变了跟着图重画；数据从 BigTradeSource 拿
 * （每根大买 / 大卖合计 + 三档金额线，见 bigTradeSource()，底下是 orderflow/bigTags.ts 的 BigBarCache / TierCache）。
 * 排签是纯函数（bigTradeSigns.ts），这里只把它画出来、接住轻点、给读屏一排隐形按钮。
 *
 *   · 轻点：ChartView.bigTradeTap → 44 × 44 命中、取最近的那枚 → onTap(sign)；宿主说接了（返回真）才做反馈：
 *     签放大到 1.3 倍 120 ms 再回（减少动效时不放大）。
 *   · 实时一根新进大单：签外圈扩散一道 8 pt 光环，600 ms ease-out；减少动效时改成 150 ms 的透明度闪一下。
 *   · 读屏：图本身是 role=img，签另给一排隐形按钮（「买方大单 1.2M，12:30 这根」），点它和点签一样。
 *     按钮不吃指针（pointer-events: none），手指照样落在图上走手势；排签 300 ms 内不再动才重建，免得拖图时狂改 DOM。
 */
import type { ChartView, ChartLayerHandle } from './view'
import type { ChartRenderer } from './renderer'
import type { BarSeries } from './series'
import { drawingLabelBoxes, orderFlowAmount } from './renderer.orderflow'
import { css, textWidth, drawCentered, fillRoundRect, type ChartFontSpec, type Hex } from './paint'
import { dateParts, pad2 } from './format'
import { reduceMotion } from './gesture'
import { planSigns, hitSign, signLabel, SIGN, type Sign, type SignBar } from './bigTradeSigns'
import { BigBarCache, TierCache, TIER_BARS, type Tiers } from '../../orderflow/bigTags'
import { flowOf, type SymbolFlow } from '../../chart/tradeFlow'

export const SIGN_FONT: ChartFontSpec = { size: SIGN.capFont, weight: 600, tabular: true }
const WHITE: Hex = '#FFFFFF'
const RING_MS = 600
const FLASH_MS = 150
const POP_MS = 120
const ARIA_SETTLE_MS = 300

/** 一张图这一刻的大单数据：每根合计 + 三档金额线。prepare 每画一次调一次（缓存在里面） */
export interface BigTradeSource {
  prepare(series: BarSeries, now: number): { bar(i: number): { bb: number; bs: number } | null; tiers: Tiers | null; live: number } | null
}

/** 用 tradeFlow 的分钟桶 + 服务端历史做源：floor() = 档位的绝对下限（门槛 ÷ 5） */
export function bigTradeSource(floor: () => number): BigTradeSource {
  const cache = new BigBarCache(), tc = new TierCache()
  let tailKey = '', tail: { t: number }[] = []
  return {
    prepare(series, now) {
      const n = series.count
      if (!n) return null
      const f: SymbolFlow = flowOf(series.symbol)
      cache.begin(f, `${series.symbol}|${series.interval}`, now)
      const tk = `${series.symbol}|${series.interval}|${n}|${series.time(n - 1)}`
      if (tk !== tailKey) {
        tailKey = tk
        tail = []
        for (let i = Math.max(0, n - TIER_BARS); i < n; i++) tail.push({ t: series.time(i) })
      }
      const step = series.step
      const tiers = tc.get(cache, f, { bars: tail, timeAt: () => series.time(n - 1) + step }, now, floor())
      return {
        tiers,
        live: f.live,
        bar: i => {
          const t0 = series.time(i), t1 = i + 1 < n ? series.time(i + 1) : t0 + step
          const d = cache.get(f, t0, t1, now)
          return d ? { bb: d.bb, bs: d.bs } : null
        },
      }
    },
  }
}

export interface BigTradeLayerOptions {
  source: BigTradeSource
  /** 点中一枚签：宿主接了（开 / 换弹层）返回真 */
  onTap: (s: Sign) => boolean
  now?: () => number
}

const easeOut = (k: number) => 1 - Math.pow(1 - k, 3)

export class BigTradeLayer {
  private handle: ChartLayerHandle
  private signs: Sign[] = []
  private on = true
  private ring: { t: number; start: number } | null = null
  private pop: { t: number; start: number } | null = null
  private raf = 0
  private liveSeen: { t: number; live: number; usd: number } | null = null
  private aria: HTMLDivElement
  private ariaTimer: ReturnType<typeof setTimeout> | null = null
  private ariaKey = ''
  private tz = 480
  private stepMs = 60_000
  private readonly now: () => number

  constructor(private readonly view: ChartView, private readonly opts: BigTradeLayerOptions) {
    this.now = opts.now ?? Date.now
    this.handle = view.addLayer((ctx, W, H, scale, r) => this.paint(ctx, W, H, scale, r))
    this.handle.canvas.dataset.layer = 'big-trade'
    view.bigTradeTap = (x, y) => this.tap(x, y)
    const a = document.createElement('div')
    a.className = 'm-bigtrade-aria'
    Object.assign(a.style, { position: 'absolute', inset: '0', pointerEvents: 'none', overflow: 'hidden' })
    a.setAttribute('aria-label', '图上大单签')
    view.el.appendChild(a)
    this.aria = a
  }

  /** 这一屏排好的签（测试、弹层定位用） */
  get current(): readonly Sign[] { return this.signs }

  setEnabled(on: boolean): void {
    if (on === this.on) return
    this.on = on
    if (!on) { this.signs = []; this.ring = null; this.pop = null; this.syncAria(true) }
    this.handle.redraw()
  }
  get enabled(): boolean { return this.on }

  /** 数据变了（服务端历史到了、门槛变了） */
  invalidate(): void { if (this.on) this.handle.redraw() }

  /** 点签之外的地方（弹层「每根」）让某根的签弹一下 */
  popAt(t: number): void {
    if (reduceMotion() || !this.signs.some(s => s.t === t)) return
    this.pop = { t, start: performance.now() }
    this.animate()
  }

  destroy(): void {
    if (this.raf) cancelAnimationFrame(this.raf)
    this.raf = 0
    if (this.ariaTimer) clearTimeout(this.ariaTimer)
    if (this.view.bigTradeTap) this.view.bigTradeTap = null
    this.handle.remove()
    this.aria.remove()
  }

  // ------------------------------------------------------------ 轻点

  private tap(x: number, y: number): boolean {
    if (!this.on) return false
    const s = hitSign(this.signs, x, y)
    if (!s || !this.opts.onTap(s)) return false
    this.popAt(s.t)
    return true
  }

  // ------------------------------------------------------------ 画

  private paint(ctx: CanvasRenderingContext2D, W: number, H: number, _scale: number, r: ChartRenderer): void {
    if (!this.on) { this.signs = []; return }
    const st = r.state, series = st.input.series
    this.tz = st.input.tzOffset
    this.stepMs = series.step
    const now = this.now()
    const data = series.isEmpty ? null : this.opts.source.prepare(series, now)
    if (!data || !data.tiers) { this.signs = []; this.syncAria(); return }
    const L = r.layout(W, H), pane = L.main, range = r.priceRange(W, H)
    const { lo, hi } = r.visible()
    const bars: SignBar[] = []
    for (let i = Math.max(0, lo); i <= hi && i < series.count; i++) {
      const x = r.x(series.time(i), L.plotW)
      if (x < -4 || x > L.plotW + 4) continue
      // 没大单的根也进来（胶囊要让开横跨的那几根的高 / 低点），planSigns 自己跳过不够档的
      const d = data.bar(i)
      const ha = r.heikin?.bar(i)
      const h = ha ? Math.max(ha.h, ha.l) : series.high[i], l = ha ? Math.min(ha.h, ha.l) : series.low[i]
      const yh = r.yOf(h, pane, range), yl = r.yOf(l, pane, range)
      bars.push({ i, t: series.time(i), x, yHigh: Math.min(yh, yl), yLow: Math.max(yh, yl), bb: d?.bb ?? 0, bs: d?.bs ?? 0 })
    }
    const signs = planSigns(bars, {
      top: pane.y + Math.max(SIGN.legendBand, r.mainLegendInset(L.plotW)), bottom: pane.y + pane.h, plotW: L.plotW,
      spacing: r.spacing(L.plotW), tiers: data.tiers,
      avoid: drawingLabelBoxes(r, pane, range, L),
      measure: t => textWidth(t, SIGN_FONT), fmt: orderFlowAmount,
      span: spanOf(bars),
    })
    this.signs = signs
    this.watchLive(series, data, signs)

    const col = st.input.colors
    const t = performance.now()
    ctx.save()
    ctx.beginPath(); ctx.rect(0, pane.y, L.plotW, pane.h); ctx.clip()
    for (const s of signs) {
      const c = s.side === 'buy' ? col.up : col.down
      let a = 1, k = 1
      if (this.ring && this.ring.t === s.t && reduceMotion()) {
        const p = (t - this.ring.start) / FLASH_MS
        if (p < 1) a = 0.35 + 0.65 * Math.abs(1 - 2 * p)
      }
      if (this.pop && this.pop.t === s.t) {
        const p = (t - this.pop.start) / POP_MS
        if (p < 1) k = 1 + 0.3 * Math.sin(Math.PI * p)
      }
      ctx.globalAlpha = a
      if (k !== 1) {
        const bx = s.bounds.x + s.bounds.w / 2, by = s.bounds.y + s.bounds.h / 2
        ctx.save(); ctx.translate(bx, by); ctx.scale(k, k); ctx.translate(-bx, -by)
      }
      drawSign(ctx, s, c)
      if (k !== 1) ctx.restore()
      if (this.ring && this.ring.t === s.t && !reduceMotion()) {
        const p = (t - this.ring.start) / RING_MS
        if (p < 1) {
          const e = easeOut(p)
          const r0 = Math.max(s.mark.w, s.mark.h) / 2 + 1
          ctx.globalAlpha = 0.8 * (1 - e)
          ctx.strokeStyle = css(c)
          ctx.lineWidth = 1.5
          ctx.beginPath(); ctx.arc(s.cx, s.cy, r0 + 8 * e, 0, Math.PI * 2); ctx.stroke()
        }
      }
    }
    ctx.restore()
    this.syncAria()
  }

  /** 实时一根的主导金额涨了 = 新大单落进来 → 光环 */
  private watchLive(series: BarSeries, data: { bar(i: number): { bb: number; bs: number } | null; live: number }, signs: Sign[]): void {
    const n = series.count
    if (!n) return
    const t = series.time(n - 1), d = data.bar(n - 1)
    const usd = d ? Math.max(d.bb, d.bs) : 0
    const prev = this.liveSeen
    this.liveSeen = { t, live: data.live, usd }
    if (!prev || prev.t !== t || data.live === prev.live || !(usd > prev.usd)) return
    if (!signs.some(s => s.t === t)) return
    this.ring = { t, start: performance.now() }
    this.animate()
  }

  private animate(): void {
    if (this.raf) return
    const step = () => {
      this.raf = 0
      const t = performance.now()
      const ringOn = this.ring != null && t - this.ring.start < (reduceMotion() ? FLASH_MS : RING_MS)
      const popOn = this.pop != null && t - this.pop.start < POP_MS
      if (!ringOn) this.ring = null
      if (!popOn) this.pop = null
      this.handle.redraw()
      if (ringOn || popOn) this.raf = requestAnimationFrame(step)
    }
    this.raf = requestAnimationFrame(step)
  }

  // ------------------------------------------------------------ 读屏

  private when(t: number): string {
    const p = dateParts(t, this.tz)
    return this.stepMs >= 86_400_000 ? `${p.month}月${p.day}日` : `${pad2(p.hour)}:${pad2(p.minute)}`
  }

  private syncAria(now = false): void {
    if (this.ariaTimer) clearTimeout(this.ariaTimer)
    this.ariaTimer = null
    const run = () => {
      this.ariaTimer = null
      const list = this.signs.slice().sort((a, b) => a.t - b.t)
      const key = list.map(s => `${s.t}${s.side}${s.usd}`).join('|')
      if (key === this.ariaKey) return
      this.ariaKey = key
      this.aria.replaceChildren(...list.map(s => {
        const b = document.createElement('button')
        b.type = 'button'
        b.className = 'm-bigtrade-aria-sign'
        b.setAttribute('aria-label', signLabel(s, orderFlowAmount, this.when(s.t)))
        Object.assign(b.style, {
          position: 'absolute', left: `${s.bounds.x + s.bounds.w / 2 - Math.max(SIGN.hit, s.bounds.w) / 2}px`, top: `${s.cy - SIGN.hit / 2}px`,
          width: `${Math.max(SIGN.hit, s.bounds.w)}px`, height: `${SIGN.hit}px`,
          opacity: '0', pointerEvents: 'none', border: '0', padding: '0', background: 'transparent',
        })
        b.addEventListener('click', () => { if (this.opts.onTap(s)) this.popAt(s.t) })
        return b
      }))
    }
    if (now) run(); else this.ariaTimer = setTimeout(run, ARIA_SETTLE_MS)
  }
}

/** 胶囊横跨的那几根的最高 / 最低（bars 按 x 升序；二分找左沿） */
export function spanOf(bars: readonly SignBar[]): (x0: number, x1: number) => { hiY: number; loY: number } | null {
  return (x0, x1) => {
    let a = 0, b = bars.length
    while (a < b) { const m = (a + b) >> 1; if (bars[m].x < x0) a = m + 1; else b = m }
    let hiY = Infinity, loY = -Infinity
    for (let k = a; k < bars.length && bars[k].x <= x1; k++) {
      if (bars[k].yHigh < hiY) hiY = bars[k].yHigh
      if (bars[k].yLow > loY) loY = bars[k].yLow
    }
    return hiY === Infinity ? null : { hiY, loY }
  }
}

/** 画一枚签（点 / 三角 / 三角 + 金额签）。买三角朝上、卖朝下，翻侧后朝向不变 */
export function drawSign(ctx: CanvasRenderingContext2D, s: Sign, c: Hex): void {
  const m = s.mark
  if (s.shape === 'dot') {
    const a = ctx.globalAlpha
    ctx.globalAlpha = a * SIGN.dotAlpha
    ctx.fillStyle = css(c)
    ctx.beginPath(); ctx.arc(m.x + m.w / 2, m.y + m.h / 2, m.w / 2, 0, Math.PI * 2); ctx.fill()
    ctx.globalAlpha = a
    return
  }
  ctx.fillStyle = css(c)
  ctx.beginPath()
  if (s.side === 'buy') { ctx.moveTo(m.x, m.y + m.h); ctx.lineTo(m.x + m.w, m.y + m.h); ctx.lineTo(m.x + m.w / 2, m.y) }
  else { ctx.moveTo(m.x, m.y); ctx.lineTo(m.x + m.w, m.y); ctx.lineTo(m.x + m.w / 2, m.y + m.h) }
  ctx.closePath(); ctx.fill()
  const cap = s.cap
  if (!cap || s.shape !== 'cap') return
  fillRoundRect(ctx, cap.x, cap.y, cap.w, cap.h, cap.h / 2, c)
  drawCentered(ctx, s.text, cap.x + cap.w / 2, cap.y + cap.h / 2, SIGN_FONT, WHITE)
}
