/* Hkline 手机网页 · 图上大单与爆仓气泡：图层（画布、命中、光环、读屏）
 *
 * 自己一块画布（ChartView.addLayer，插在画线覆盖层下面），几何变了跟着图重画；数据从 BigTradeSource 拿
 * （每根向上 U = 大买 + 空爆、向下 D = 大卖 + 多爆，加两级金额线，见 bigTradeSource()；底下是 orderflow/bigTags.ts 的
 * BigBarCache / LevelCache 与 orderflow/liquidation.ts 的 LiqBarCache）。摆放是纯函数（bigTradeSigns.ts → planBubbles），
 * 这里只把它画出来、接住轻点、给读屏一排隐形按钮。规格 docs/design/大单爆仓气泡-三端规格-2026-10-08.md。
 *
 *   · 画法：柄全部先画（只有泡有柄：1.2 宽、方向色 60%），再画小圆点（方向色 85% 实心），最后画泡
 *     （方向色 16% 填充，深色皮肤 22%；1.4 描边；方向色字居中）。上侧涨色、下侧跌色，没有别的分别。
 *   · 轻点：ChartView.bigTradeTap → 44 × 44 命中、取最近的那枚泡 → onTap(bubble)；宿主说接了（返回真）才做反馈：
 *     泡放大到 1.3 倍 120 ms 再回（减少动效时不放大）。小圆点不响应。
 *   · 实时一根新进大单：那一枚外圈扩散一道 8 pt 光环，600 ms ease-out；减少动效时改成 150 ms 的透明度闪一下。
 *   · 读屏：图本身是 role=img，泡另给一排隐形按钮（「12:30 向上 1.2M」），点它和点泡一样；小圆点不进。
 *     按钮不吃指针（pointer-events: none），手指照样落在图上走手势；摆放 300 ms 内不再动才重建，免得拖图时狂改 DOM。
 */
import type { ChartView, ChartLayerHandle } from './view'
import type { ChartRenderer } from './renderer'
import type { BarSeries } from './series'
import { drawingLabelBoxes } from './renderer.orderflow'
import { css, alpha, bytes, textWidth, drawCentered, type ChartFontSpec, type Hex } from './paint'
import { dateParts, pad2 } from './format'
import { reduceMotion } from './gesture'
import { planSigns, hitSign, hitBox, signLabel, amtShort, SIGN, type Sign, type SignBar } from './bigTradeSigns'
import { BigBarCache, LevelCache, TIER_BARS, BUBBLE, udOf, type Levels, type LiqBars } from '../../orderflow/bigTags'
import { LiqBarCache } from '../../orderflow/liquidation'
import { flowOf, type SymbolFlow } from '../../chart/tradeFlow'
import { BT } from '../../terms'

/** 泡里的字：11、半粗、等宽数字（与 iOS 同） */
export const SIGN_FONT: ChartFontSpec = { size: BUBBLE.font, weight: 600, tabular: true }
const ARIA_SETTLE_MS = 300

/** 一根的数：U / D（图上画的）与其中的大买 / 大卖（光环只看大单） */
export interface BarUDB { up: number; down: number; bb: number; bs: number }

/** 一张图这一刻的数据：每根 U / D + 两级金额线。prepare 每画一次调一次（缓存在里面） */
export interface BigTradeSource {
  prepare(series: BarSeries, now: number): { bar(i: number): BarUDB | null; levels: Levels | null; live: number } | null
}

type LiqIn = Parameters<LiqBarCache['of']>[0]
/** 爆仓分钟账：给品种，返回那份 LiqStore 状态与基础币；现货 / 宏观 / 没开返回 null */
export type LiqGetter = (symbol: string) => { state: LiqIn; base: string } | null

/** 用 tradeFlow 的分钟桶 + 服务端历史做源：floor() = 金额线的绝对下限（门槛 ÷ 5）；liq 给了就把爆仓按根并进 U / D */
export function bigTradeSource(floor: () => number, liq?: LiqGetter): BigTradeSource {
  const cache = new BigBarCache(), lc = new LevelCache(), lq = new LiqBarCache()
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
      const src = liq?.(series.symbol) ?? null
      const lb: LiqBars | null = src ? lq.of(src.state, src.base, step) : null
      const levels = lc.get(cache, f, { bars: tail, timeAt: () => series.time(n - 1) + step }, now, floor(), lb)
      return {
        levels,
        live: f.live,
        bar: i => {
          const t0 = series.time(i), t1 = i + 1 < n ? series.time(i + 1) : t0 + step
          const d = cache.get(f, t0, t1, now), l = lb ? lb.at(t0, t1) : null
          if (!d && !l) return null
          const u = udOf(d, l)
          return { up: u.up, down: u.down, bb: d?.bb ?? 0, bs: d?.bs ?? 0 }
        },
      }
    },
  }
}

export interface BigTradeLayerOptions {
  source: BigTradeSource
  /** 点中一枚泡：宿主接了（开 / 换弹层）返回真 */
  onTap: (s: Sign) => boolean
  now?: () => number
}

const easeOut = (k: number) => 1 - Math.pow(1 - k, 3)
/** 底色够暗就当深色皮肤（泡填充 22%） */
const isDark = (bg: Hex): boolean => { const c = bytes(bg); return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b < 128 }
const aa = (k: number): string => Math.round(Math.max(0, Math.min(1, k)) * 255).toString(16).padStart(2, '0').toUpperCase()

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
    a.setAttribute('aria-label', BT.chartMarks)
    view.el.appendChild(a)
    this.aria = a
  }

  /** 这一屏排好的泡与点（测试、弹层定位用） */
  get current(): readonly Sign[] { return this.signs }

  setEnabled(on: boolean): void {
    if (on === this.on) return
    this.on = on
    if (!on) { this.signs = []; this.ring = null; this.pop = null; this.syncAria(true) }
    this.handle.redraw()
  }
  get enabled(): boolean { return this.on }

  /** 数据变了（服务端历史到了、爆仓补到了、门槛变了） */
  invalidate(): void { if (this.on) this.handle.redraw() }

  /** 点泡之外的地方（弹层「每根」）让某根的泡弹一下；那根只有点就不弹 */
  popAt(t: number): void {
    if (reduceMotion() || !this.signs.some(s => s.t === t && s.bubble)) return
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
    const K = data?.levels ?? null
    if (!data || !K) { this.signs = []; this.syncAria(); return }
    const L = r.layout(W, H), pane = L.main, range = r.priceRange(W, H)
    const { lo, hi } = r.visible()
    const bars: SignBar[] = []
    for (let i = Math.max(0, lo); i <= hi && i < series.count; i++) {
      const x = r.x(series.time(i), L.plotW)
      if (x < -4 || x > L.plotW + 4) continue
      const d = data.bar(i)
      if (!d || Math.max(d.up, d.down) < K.dot) continue
      const ha = r.heikin?.bar(i)
      const h = ha ? Math.max(ha.h, ha.l) : series.high[i], l = ha ? Math.min(ha.h, ha.l) : series.low[i]
      const yh = r.yOf(h, pane, range), yl = r.yOf(l, pane, range)
      bars.push({ i, t: series.time(i), x, yHigh: Math.min(yh, yl), yLow: Math.max(yh, yl), up: d.up, down: d.down })
    }
    const signs = planSigns(bars, {
      levels: K,
      top: pane.y + Math.max(SIGN.legendBand, r.mainLegendInset(L.plotW)), bottom: pane.y + pane.h, plotW: L.plotW,
      spacing: r.spacing(L.plotW),
      avoid: drawingLabelBoxes(r, pane, range, L),
      measure: t => textWidth(t, SIGN_FONT), fmt: amtShort,
    })
    this.signs = signs
    this.watchLive(series, data, signs)

    const col = st.input.colors
    const fillK = isDark(col.bg) ? BUBBLE.fillDark : BUBBLE.fill
    const colOf = (s: Sign): Hex => (s.side === 'up' ? col.up : col.down)
    const t = performance.now()
    const popK = (s: Sign): number => {
      if (!s.bubble || !this.pop || this.pop.t !== s.t) return 1
      const p = (t - this.pop.start) / SIGN.popMs
      return p < 1 ? 1 + (SIGN.pop - 1) * Math.sin(Math.PI * p) : 1
    }
    const flashA = (s: Sign): number => {
      if (!this.ring || this.ring.t !== s.t || !reduceMotion()) return 1
      const p = (t - this.ring.start) / SIGN.flashMs
      return p < 1 ? 0.35 + 0.65 * Math.abs(1 - 2 * p) : 1
    }
    ctx.save()
    ctx.beginPath(); ctx.rect(0, pane.y, L.plotW, pane.h); ctx.clip()
    // 柄全部先画（只有泡有柄）
    ctx.lineWidth = BUBBLE.stemW
    for (const s of signs) {
      if (!s.bubble) continue
      const rr = s.r * popK(s), end = s.side === 'up' ? s.cy + rr : s.cy - rr
      if (Math.abs(end - s.anchor) < 0.5) continue
      ctx.globalAlpha = flashA(s)
      ctx.strokeStyle = css(alpha(colOf(s), aa(BUBBLE.stemAlpha)))
      ctx.beginPath(); ctx.moveTo(s.x, s.anchor); ctx.lineTo(s.x, end); ctx.stroke()
    }
    // 再画点
    for (const s of signs) {
      if (s.bubble) continue
      ctx.globalAlpha = flashA(s) * BUBBLE.dotAlpha
      ctx.fillStyle = css(colOf(s))
      ctx.beginPath(); ctx.arc(s.x, s.cy, s.r, 0, Math.PI * 2); ctx.fill()
    }
    // 最后画泡
    ctx.lineWidth = BUBBLE.stroke
    for (const s of signs) {
      if (!s.bubble) continue
      const c = colOf(s), k = popK(s)
      ctx.globalAlpha = flashA(s)
      if (k !== 1) { ctx.save(); ctx.translate(s.x, s.cy); ctx.scale(k, k); ctx.translate(-s.x, -s.cy) }
      ctx.beginPath(); ctx.arc(s.x, s.cy, s.r, 0, Math.PI * 2)
      ctx.fillStyle = css(alpha(c, aa(fillK))); ctx.fill()
      ctx.strokeStyle = css(c); ctx.stroke()
      drawCentered(ctx, s.text, s.x, s.cy, SIGN_FONT, c)
      if (k !== 1) ctx.restore()
    }
    // 新大单光环（点和泡都可能是那一枚）
    if (this.ring && !reduceMotion()) {
      const p = (t - this.ring.start) / SIGN.ringMs
      if (p < 1) {
        const e = easeOut(p)
        ctx.lineWidth = 1.5
        for (const s of signs) {
          if (s.t !== this.ring.t) continue
          ctx.globalAlpha = 0.8 * (1 - e)
          ctx.strokeStyle = css(colOf(s))
          ctx.beginPath(); ctx.arc(s.x, s.cy, s.r + 1 + SIGN.ring * e, 0, Math.PI * 2); ctx.stroke()
        }
      }
    }
    ctx.restore()
    this.syncAria()
  }

  /** 实时一根的大单金额涨了 = 新大单落进来 → 光环（只看大单；爆仓补数不算「新大单」） */
  private watchLive(series: BarSeries, data: { bar(i: number): BarUDB | null; live: number }, signs: Sign[]): void {
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
      const ringOn = this.ring != null && t - this.ring.start < (reduceMotion() ? SIGN.flashMs : SIGN.ringMs)
      const popOn = this.pop != null && t - this.pop.start < SIGN.popMs
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
      const list = this.signs.filter(s => s.bubble).sort((a, b) => a.t - b.t || (a.side === 'up' ? -1 : 1))
      const key = list.map(s => `${s.t}${s.side}${s.usd}${Math.round(s.cy)}`).join('|')
      if (key === this.ariaKey) return
      this.ariaKey = key
      this.aria.replaceChildren(...list.map(s => {
        const b = document.createElement('button')
        b.type = 'button'
        b.className = 'm-bigtrade-aria-sign'
        b.setAttribute('aria-label', signLabel(s, amtShort, this.when(s.t)))
        const box = hitBox(s)
        Object.assign(b.style, {
          position: 'absolute', left: `${box.x}px`, top: `${box.y}px`, width: `${box.w}px`, height: `${box.h}px`,
          opacity: '0', pointerEvents: 'none', border: '0', padding: '0', background: 'transparent',
        })
        b.addEventListener('click', () => { if (this.opts.onTap(s)) this.popAt(s.t) })
        return b
      }))
    }
    if (now) run(); else this.ariaTimer = setTimeout(run, ARIA_SETTLE_MS)
  }
}
