/* Hkline 手机网页 · 行情页的「盘口要点」：入口条 + 半页 + 图上带子
 *
 * 入口条（图下方那一行）：有价位或事件时 44 高，「⌃ 要点  下方 86,120 买区 35M · 挂 48 分」；
 *   没有要点（或还没取到、服务端还没跟这只）缩成 16 高的抓手。高度变化 200 ms，图跟着伸缩。
 *   点它或在它上面往上滑开半页。宏观品种、横屏画线台、复盘回放里整条不出现。
 * 取数：页面开着时每 60 秒一次，半页开着时 30 秒一次；换品种立刻重取并收半页。
 * 带子：点开一条价位画价区带（半页盖着看不见，「回图」时露出来）；事件「回图」画时段带。
 *   用「回图」关的半页带子留着，其他方式关的撤掉；换品种或再开半页时撤掉。
 */
import { el } from '../../ui/dom'
import type { ChartHandle } from '../../chart'
import { HighlightBand, barAt } from '../../chart/highlightBand'
import { baseOfSymbol } from '../../../orderflow/settings'
import { fetchHighlights, type Highlights, type Level, type HlEvent } from '../../../highlights/api'
import { HL } from '../../../terms'
import { bandPx, eventAt, eventSpan, eventTime, stripSentence } from '../../../highlights/format'
import { HighlightsSheet, type Focus, type SheetState } from './highlightsSheet'
import { shouldOpenInsightSwipe } from './insights'
import { takeHighlightIntent } from './highlightIntent'

export const STRIP_POLL_MS = 60_000
export const SHEET_POLL_MS = 30_000
/** 首页点进来：行情页换好品种后多久升半页 */
export const INTENT_DELAY_MS = 240

export interface HighlightsDeps {
  page: HTMLElement
  chart: ChartHandle
  symbol(): string
  /** 行情头（价格 + 六格）：半页顶边贴它的下沿 */
  head(): HTMLElement
  /** 这会儿不出入口条（宏观品种 / 横屏 / 回放） */
  hidden(): boolean
  /** 现价（关键价位块里那条「现价」分隔线、区间行的圆点） */
  price(): number | null
  /** 开半页前收掉周期条网格这类东西 */
  beforeOpen(): void
}

type Entry = { at: number; data: Highlights | null; failed: boolean }

export class HighlightsController {
  readonly strip: HTMLButtonElement
  private textEl: HTMLElement
  private band: HighlightBand
  private sheet: HighlightsSheet | null = null
  private cache = new Map<string, Entry>()
  private shown = false
  private timer: ReturnType<typeof setInterval> | null = null
  private inflight = new Set<string>()
  private intentTimer: ReturnType<typeof setTimeout> | null = null
  private pendingFocus: Focus | null = null
  private lastBase = ''

  constructor(private readonly d: HighlightsDeps) {
    const s = this.strip = el('button', 'cp-insight-entry hl-strip thin')
    s.type = 'button'
    s.setAttribute('aria-label', HL.open)
    s.innerHTML = `<svg class="ch" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 15l6-6 6 6"/></svg><span class="k">${HL.entry}</span><span class="t"></span><i class="hd" aria-hidden="true"></i>`
    this.textEl = s.querySelector<HTMLElement>('.t')!
    d.page.append(s)
    this.band = new HighlightBand(d.chart)
    this.wireStrip()
  }

  get isOpen(): boolean { return !!this.sheet && !this.sheet.closed }
  private base(): string { return baseOfSymbol(this.d.symbol()).base }

  // ------------------------------------------------------------ 生命周期

  show(): void {
    this.shown = true
    this.restartTimer()
    this.paintStrip()
    void this.load(false)
    this.takeIntent()
  }

  hide(): void {
    this.shown = false
    if (this.timer) { clearInterval(this.timer); this.timer = null }
    if (this.intentTimer) { clearTimeout(this.intentTimer); this.intentTimer = null }
    this.sheet?.close()
    this.band.clear()
  }

  /** 换品种：收半页、撤带子、立刻重取 */
  onSymbol(): void {
    const base = this.base()
    if (base === this.lastBase && !this.isOpen) { this.takeIntent(); return }
    this.sheet?.close()
    this.band.clear()
    this.paintStrip()
    if (this.shown) void this.load(false)
    this.takeIntent()
  }

  /** 横屏 / 回放 / 宏观品种进出：入口条显隐，半页收掉 */
  sync(): void {
    if (this.d.hidden()) { this.sheet?.close(); this.band.clear() }
    this.paintStrip()
  }

  /** 皮肤换了：带子主色重取 */
  invalidate(): void { this.band.invalidate() }

  private restartTimer(): void {
    if (this.timer) clearInterval(this.timer)
    this.timer = setInterval(() => { if (this.shown && !document.hidden) void this.load(false) }, this.isOpen ? SHEET_POLL_MS : STRIP_POLL_MS)
  }

  // ------------------------------------------------------------ 取数

  private async load(force: boolean): Promise<void> {
    if (this.d.hidden()) return
    const base = this.base()
    if (!base || this.inflight.has(base)) return
    const c = this.cache.get(base)
    const fresh = this.isOpen ? SHEET_POLL_MS : STRIP_POLL_MS
    if (!force && c && Date.now() - c.at < fresh - 2_000) { this.paint(); return }
    this.inflight.add(base)
    try {
      const r = await fetchHighlights(base)
      const prev = this.cache.get(base)
      this.cache.set(base, r.ok ? { at: Date.now(), data: r.data, failed: false } : { at: Date.now(), data: prev?.data ?? null, failed: !prev?.data })
    } finally {
      this.inflight.delete(base)
    }
    if (base === this.base()) this.paint()
  }

  private entry(): Entry | null { return this.cache.get(this.base()) ?? null }

  private paint(): void {
    this.paintStrip()
    if (this.sheet && !this.sheet.closed) {
      this.sheet.update(this.sheetState())
      if (this.pendingFocus && this.entry()?.data) { const f = this.pendingFocus; this.pendingFocus = null; this.sheet.focus(f) }
    }
  }

  private sheetState(): SheetState {
    const e = this.entry()
    if (!e) return { kind: 'loading' }
    if (!e.data) return e.failed ? { kind: 'failed' } : { kind: 'loading' }
    return { kind: 'data', data: e.data, price: this.d.price(), now: Date.now() }
  }

  // ------------------------------------------------------------ 入口条

  private paintStrip(): void {
    const hidden = this.d.hidden()
    this.strip.hidden = hidden
    const data = this.entry()?.data
    const html = data && data.tracked ? stripSentence(data.levels, data.events, data.flow, this.d.price()) : null
    this.lastBase = this.base()
    this.strip.classList.toggle('thin', html == null)
    this.strip.classList.toggle('stale', !!data && data.staleMs != null && data.staleMs > 0)
    if (html != null) {
      if (this.textEl.innerHTML !== html) this.textEl.innerHTML = html
      this.strip.setAttribute('aria-label', `${HL.entry} ${this.textEl.textContent ?? ''}`)
    } else {
      this.textEl.textContent = ''
      this.strip.setAttribute('aria-label', HL.open)
    }
  }

  private wireStrip(): void {
    const s = this.strip
    let swipe: { x: number; y: number; at: number } | null = null, suppress = 0
    s.addEventListener('click', () => { if (performance.now() >= suppress) this.open() })
    s.addEventListener('pointerdown', e => {
      if (!e.isPrimary) return
      swipe = { x: e.clientX, y: e.clientY, at: performance.now() }
      try { s.setPointerCapture(e.pointerId) } catch { /* 指针已经结束 */ }
    })
    s.addEventListener('pointerup', e => {
      const start = swipe; swipe = null
      if (!start) return
      const dx = e.clientX - start.x, dy = e.clientY - start.y, now = performance.now()
      // 拖动结束后浏览器可能补发 click：明显拖过就吞掉，只有合格上滑才开
      if (Math.hypot(dx, dy) > 10) suppress = now + 500
      if (shouldOpenInsightSwipe(dx, dy, now - start.at, start.x, innerWidth)) this.open()
    })
    s.addEventListener('pointercancel', () => { swipe = null; suppress = performance.now() + 500 })
  }

  // ------------------------------------------------------------ 半页

  open(focus?: Focus): void {
    if (this.d.hidden()) return
    if (this.isOpen) { if (focus) this.sheet!.focus(focus); return }
    this.d.beforeOpen()
    this.band.clear()
    this.d.chart.clearCrosshair()
    /** 这次是「回图」关的：带子留着 */
    let returned = false
    this.sheet = new HighlightsSheet({
      top: () => this.d.head().getBoundingClientRect().bottom,
      onClose: () => {
        this.sheet = null
        if (!returned) this.band.clear()
        this.restartTimer()
      },
      onLevel: l => this.band.set(l ? this.levelBand(l) : null),
      onBack: t => { returned = true; this.goBack(t) },
      onRetry: () => { this.cache.delete(this.base()); this.sheet?.update({ kind: 'loading' }); void this.load(true) },
    })
    this.sheet.update(this.sheetState())
    if (focus) {
      if (this.entry()?.data) this.sheet.focus(focus)
      else this.pendingFocus = focus
    }
    this.restartTimer()
    void this.load(false)
  }

  close(): void { this.sheet?.close() }

  private levelBand(l: Level): { kind: 'price'; low: number; high: number; label: string } {
    return { kind: 'price', low: l.low, high: l.high, label: `${l.side === 'bid' ? HL.buyZone : HL.sellZone} ${bandPx(l.low, l.high)}` }
  }

  /** 「回图」：关半页，画带子，把图挪到带子上（价区：十字线落到价区中价、价不在视野里就拉进来；时段：落到那一根） */
  private goBack(t: { level: Level } | { event: HlEvent }): void {
    const chart = this.d.chart
    const series = chart.state?.input.series
    if ('level' in t) {
      const l = t.level
      this.band.set(this.levelBand(l))
      this.sheet?.close()
      if (series?.count) chart.view.crosshairTo(series.count - 1, 'bigTrade', (l.low + l.high) / 2)
      return
    }
    const e = t.event
    const [from, to] = eventSpan(e)
    if (e.t === 'levelBroken') this.band.set({ kind: 'price', low: e.low, high: e.high, label: `${eventTime(e)} ${e.side === 'ask' ? HL.brokenUp : HL.brokenDown}` })
    else this.band.set({ kind: 'time', from, to, label: eventTime(e) })
    this.sheet?.close()
    if (series?.count) {
      const i = barAt(series, eventAt(e))
      if (e.t === 'levelBroken') chart.view.crosshairTo(i, 'bigTrade', (e.low + e.high) / 2)
      else if (e.t === 'wallEaten' || e.t === 'wallCancel') chart.view.crosshairTo(i, 'bigTrade', e.price)
      else chart.view.crosshairTo(i, 'bigTrade')
    }
  }

  // ------------------------------------------------------------ 首页带来的意图

  private takeIntent(): void {
    if (!this.shown) return
    const f = takeHighlightIntent(this.d.symbol())
    if (!f) return
    if (this.intentTimer) clearTimeout(this.intentTimer)
    this.intentTimer = setTimeout(() => {
      this.intentTimer = null
      if (!this.shown || this.d.hidden()) return
      this.open(f.kind === 'none' ? undefined : f)
    }, INTENT_DELAY_MS)
  }
}
