/* Hkline 手机网页 · 图上大单与爆仓气泡 + 「大单与爆仓」弹层的胶水（照 iOS / 原型 docs/原型-手机大单与爆仓-2026-10-08.html；
 * 气泡规格 docs/design/大单爆仓气泡-三端规格-2026-10-08.md）
 *
 * 一处管三件事：
 *   · 图层：BigTradeLayer 挂在行情图上，开关跟 Prefs.bigTradeSigns（出厂开、跟人走，和挂单墙互不牵连；大单与爆仓同开同关）；宏观品种（DXY）不画。
 *   · 数据：气泡或弹层要时叫数据口 setSigns 订逐笔；分钟桶 + 服务端 /flow 历史走 tradeFlow.ensureHistory；
 *     爆仓 /liq 在图层开着或弹层开着时 30 秒补一次（并进气泡的 U / D），现货与宏观不拉。
 *   · 弹层：点泡开整页（横屏只画泡不开）；开着时再点泡只换根；「每根」里点哪根 / 十字线落在哪根，本根卡片就看哪根，抬手 3 秒回到本根。
 * 页面藏起来时停 1 秒的钟；换品种时摘掉旧品种的历史监听。
 */
import { st, save } from '../../app/store'
import { S } from '../../../market'
import type { ChartHandle } from '../../chart'
import type { PagePort } from './data'
import { BigTradeLayer, bigTradeSource } from '../../chart/bigTradeLayer'
import type { Sign } from '../../chart/bigTradeSigns'
import { flowOf, ensureHistory, detachFlows } from '../../../chart/tradeFlow'
import { windows, windowSum, priceLevels, nearestWalls, HOUR, DAY, type WinSum } from '../../../orderflow/summary'
import { LiqStore, sumLiq } from '../../../orderflow/liquidation'
import { tierFloor } from '../../../orderflow/flowTap'
import { ivName } from '../../../orderflow/bigTags'
import { baseOfSymbol } from '../../../orderflow/settings'
import type { Thresholds } from '../../../orderflow/types'
import { BT, fill } from '../../../terms'
import { orderFlowAmount } from '../../chart/renderer.orderflow'
import {
  BigTradeSheet, ladderRows, liqCells, summaryLine, LIQ_CELL_MS, LADDER_HOURS,
  type BtModel, type BarCol, type HeroModel, type LiqModel,
} from './bigTradeSheet'

/** 抬手之后本根卡片停在那一根多久再回到本根 */
export const RETURN_MS = 3000
/** 多久没进一笔成交算「数据停住」 */
export const STALE_MS = 20_000
/** 骨架最多挂多久（之后按「还没有」画） */
export const SKELETON_MS = 1000
const LIQ_WAIT_MS = 8000
const BARS = 40

/** 测试与截图用的强制状态（只在开发构建里从 ?bt= 读） */
export type BtForce = 'loading' | 'spot' | 'liqEmpty' | 'stale' | 'untracked' | null

export interface BigTradeDeps {
  chart: ChartHandle
  symbol(): string
  port(): PagePort | null
  /** 当前生效门槛（数据口还没到时查表 + 改动） */
  thresholds(): Thresholds | null
  isLand(): boolean
  isMacro(): boolean
  /** 开门槛页；那页关了叫 back */
  openThreshold(back: () => void): void
  now?: () => number
  liq?: LiqStore
  force?: BtForce
}

const SHORT = (v: number): string => orderFlowAmount(v)
/** 现货（Coinbase 的 X-USD）：没有爆仓 */
const isSpotSymbol = (sym: string): boolean => /-USD$/.test(sym)

export class BigTradeController {
  readonly layer: BigTradeLayer
  readonly liq: LiqStore
  private sheet: BigTradeSheet | null = null
  private timer: ReturnType<typeof setInterval> | null = null
  private returnTimer: ReturnType<typeof setTimeout> | null = null
  /** 十字线 / 点泡挑的那根；null = 本根 */
  private pick: { t: number; from: 'cross' | 'sign' | 'bars' } | null = null
  private sym = ''
  private seen = { live: -1, ver: -1 }
  private openedAt = 0
  private shown = false
  private readonly now: () => number
  private readonly onHist = (): void => { this.layer.invalidate(); this.refresh() }

  constructor(private readonly d: BigTradeDeps) {
    this.now = d.now ?? Date.now
    this.liq = d.liq ?? new LiqStore()
    this.liq.onUpdate = () => { this.layer.invalidate(); this.refresh() }
    this.layer = new BigTradeLayer(d.chart.view, {
      source: bigTradeSource(() => tierFloor(this.d.thresholds()), sym => {
        if (!this.wantsLiq(sym)) return null
        const base = baseOfSymbol(sym).base
        return { state: this.liq.state(base), base }
      }),
      onTap: s => this.tapSign(s),
      now: this.now,
    })
    d.chart.on('crosshair', e => this.onCrosshair(e.bar ? e.bar.openTime : null))
    d.chart.on('interaction', e => { if (e === 'ended') this.onLift() })
  }

  get isOpen(): boolean { return !!this.sheet && !this.sheet.closed }
  get current(): BigTradeSheet | null { return this.isOpen ? this.sheet : null }

  // ------------------------------------------------------------ 宿主叫

  /** 偏好 / 品种 / 朝向变了 */
  sync(): void {
    const sym = this.d.symbol()
    if (sym !== this.sym) {
      if (this.sym) detachFlows(this.onHist)
      this.sym = sym
      this.pick = null
      this.seen = { live: -1, ver: -1 }
      this.openedAt = this.now()
      if (this.shown) this.tick()
    }
    const macro = this.d.isMacro()
    this.layer.setEnabled(st.bigTradeSigns && !macro)
    this.d.port()?.setSigns((st.bigTradeSigns || this.isOpen) && !macro, sym)
    if (macro && this.isOpen) this.close()
    if (this.isOpen && this.d.isLand()) this.close()
    this.refresh()
  }

  show(): void {
    this.shown = true
    this.tick()
    if (this.timer) clearInterval(this.timer)
    this.timer = setInterval(() => this.tick(), 1000)
  }
  hide(): void {
    this.shown = false
    if (this.timer) clearInterval(this.timer)
    this.timer = null
    this.close()
  }
  destroy(): void { this.hide(); detachFlows(this.onHist); this.layer.destroy() }

  /** 开弹层（分析面板那一行 / 深链）；t = 先看哪根 */
  open(t: number | null = null): void {
    if (this.d.isLand() || this.d.isMacro()) return
    if (t != null) this.pick = { t, from: 'sign' }
    if (this.isOpen) { this.refresh(); return }
    this.openedAt = this.now()
    this.sheet = new BigTradeSheet({
      onClose: () => { this.sheet = null; this.pick = null; this.sync() },
      onThreshold: () => this.threshold(),
      onPickBar: bt => this.pickBar(bt),
    })
    this.sync()
    this.tick()
  }
  close(): void { this.sheet?.close() }

  /** 分析面板那一行的实时小字 */
  summaryText(): string {
    const s = this.series()
    if (!s || !s.count) return summaryLine(null)
    const n = s.count, t0 = s.time(n - 1)
    return summaryLine(windows(flowOf(this.d.symbol()), t0, t0 + s.step, this.now()).bar)
  }

  // ------------------------------------------------------------ 事件

  private tapSign(s: Sign): boolean {
    if (this.d.isLand()) return false
    const series = this.series()
    if (series?.count) this.d.chart.view.crosshairTo(series.index(s.t), 'bigTrade')
    if (this.isOpen) {
      this.pick = { t: s.t, from: 'sign' }
      this.clearReturn()
      this.refresh()
    } else this.open(s.t)
    return true
  }

  onCrosshair(t: number | null): void {
    if (t == null) {
      if (this.pick?.from === 'cross') this.scheduleReturn()
      return
    }
    this.clearReturn()
    if (!this.isOpen) return
    // 「每根」点一根时十字线是跟着跳过去的：那一下不算人拉十字线
    if (this.pick && this.pick.from === 'bars' && this.series()?.time(this.series()!.index(this.pick.t)) === t) return
    if (this.pick?.t !== t || this.pick.from !== 'cross') { this.pick = { t, from: 'cross' }; this.refresh() }
  }
  onLift(): void {
    if (this.pick?.from === 'cross') this.scheduleReturn()
  }

  private scheduleReturn(): void {
    this.clearReturn()
    this.returnTimer = setTimeout(() => { this.returnTimer = null; this.pick = null; this.refresh() }, RETURN_MS)
  }
  private clearReturn(): void { if (this.returnTimer) { clearTimeout(this.returnTimer); this.returnTimer = null } }

  private pickBar(t: number): void {
    const s = this.series()
    if (!s) return
    const i = s.index(t)
    this.d.chart.view.crosshairTo(i, 'bigTrade')
    try { navigator.vibrate?.(10) } catch { /* 不支持就算了 */ }
    this.layer.popAt(t)
    this.pick = { t, from: 'bars' }
    this.clearReturn()
    this.sheet?.flash(t)
    this.refresh()
  }

  private threshold(): void {
    const sh = this.sheet
    if (!sh) return
    sh.park()
    this.d.openThreshold(() => { if (this.sheet === sh && !sh.closed) { sh.unpark(); this.layer.invalidate(); this.refresh() } })
  }

  // ------------------------------------------------------------ 钟

  tick(): void {
    const sym = this.d.symbol()
    if (!sym || this.d.isMacro()) return
    const now = this.now()
    const f = flowOf(sym)
    if (st.bigTradeSigns || this.isOpen) ensureHistory(f, this.onHist, now)
    if (f.live !== this.seen.live || f.srv.ver !== this.seen.ver) {
      this.seen = { live: f.live, ver: f.srv.ver }
      this.layer.invalidate()
    }
    // 爆仓：图层开着（并进气泡）或弹层开着都要
    if ((st.bigTradeSigns || this.isOpen) && this.wantsLiq(sym)) this.liq.ensure(baseOfSymbol(sym).base, now)
    if (this.isOpen) this.refresh()
  }

  /** 这只有没有爆仓项：现货（X-USD）、宏观、截图强制「现货」都没有 */
  private wantsLiq(sym: string): boolean {
    return !!sym && !isSpotSymbol(sym) && !this.d.isMacro() && this.d.force !== 'spot'
  }

  refresh(): void {
    if (!this.isOpen) return
    const m = this.model()
    if (m) this.sheet!.update(m)
  }

  // ------------------------------------------------------------ 模型

  private series() { return this.d.chart.state?.input.series ?? null }
  private tz(): number { return this.d.chart.state?.input.tzOffset ?? 480 }

  /** 时刻 → 「12:30」（日线以上「10-08」） */
  label(t: number, step: number): string {
    const iso = new Date(t + this.tz() * 60_000).toISOString()
    return step >= DAY ? iso.slice(5, 10) : iso.slice(11, 16)
  }

  model(): BtModel | null {
    const sym = this.d.symbol()
    const s = this.series()
    const now = this.now()
    const force = this.d.force ?? null
    const f = flowOf(sym)
    const port = this.d.port()
    const meta = S.symbols.get(sym)
    const base = baseOfSymbol(sym).base
    const step = s?.step ?? 3_600_000
    const n = s?.count ?? 0
    const lastT = n ? s!.time(n - 1) : Math.floor(now / step) * step

    // 看哪根
    let t0 = lastT
    if (this.pick && s && n) {
      const i = s.index(this.pick.t)
      t0 = s.time(i)
    }
    const live = t0 === lastT
    const i0 = s && n ? s.index(t0) : 0
    const t1 = s && i0 + 1 < n ? s.time(i0 + 1) : t0 + step
    const w = windows(f, t0, t1, now)

    const offline = S.live === false || (typeof navigator !== 'undefined' && navigator.onLine === false)
    const lastTrade = port?.lastTradeMs ?? 0
    const stale = force === 'stale' || offline || (lastTrade > 0 && now - lastTrade > STALE_MS && !meta?.closed)
    const stoppedAt = force === 'stale' ? now - 25_000 : lastTrade || now
    let rt: string
    if (stale) rt = fill(BT.staleSince, { t: this.label(stoppedAt, 60_000) })
    else rt = ivName(step)
    const hero: HeroModel = {
      title: live ? BT.currentBar : this.label(t0, step), live, rt,
      bar: w.bar, hour: w.hour, today: w.today,
      untracked: force === 'untracked' || f.srv.tracked === false,
    }
    const loading = force === 'loading' || (f.srv.tracked === null && !w.today.has && !w.hour.has && now - this.openedAt < SKELETON_MS)

    const spot = force === 'spot' || isSpotSymbol(sym)
    const liq = spot ? null : this.liqModel(base, now, t0, step, meta?.dec ?? 2, force === 'liqEmpty')

    const bars: BarCol[] = []
    if (s && n) {
      for (let i = Math.max(0, n - BARS); i < n; i++) {
        const a = s.time(i), b = i + 1 < n ? s.time(i + 1) : a + step
        const x: WinSum = windowSum(f, a, b, now, b - a < 60_000)
        bars.push({ t: a, bb: x.bb, bs: x.bs, label: this.label(a, step) })
      }
    }

    const mid = (n ? s!.close[n - 1] : NaN) || meta?.price || 0
    const pstep = port?.step ?? 0
    const typ = s && n && step <= 15 * 60_000 ? (minute: number): number | null => {
      const i = s.index(minute)
      const a = s.time(i)
      if (minute < a || minute >= a + step) return null
      return (s.high[i] + s.low[i] + s.close[i]) / 3
    } : null
    const lv = priceLevels(f, pstep, now, typ, 999, LADDER_HOURS * 60)
    const ladder = ladderRows(lv, mid, pstep, nearestWalls(port?.snapshot?.orders ?? [], mid))

    return {
      ...((subs: string[]) => ({ sub: subs[0], subs }))(this.subtitles(base, spot)), loading, stale, hero, liq, bars,
      sel: this.pick ? t0 : null, ladder, thr: this.thrText(),
    }
  }

  private liqModel(base: string, now: number, t0: number, step: number, dec: number, forceEmpty: boolean): LiqModel {
    const stt = this.liq.state(base)
    const z = { long: 0, short: 0, n: 0, max: null }
    const empty: LiqModel = { state: 'loading', hour: z, today: z, day: z, cells: [], from: '', maxWhen: '', maxPrice: '', selCell: -1 }
    if (forceEmpty) {
      const { start, cells } = liqCells([], now)
      return { ...empty, state: 'data', cells, from: this.dayLabel(start, now) }
    }
    if (!stt || stt.tracked === null) return now - this.openedAt < LIQ_WAIT_MS ? empty : { ...empty, state: 'none' }
    if (stt.tracked === false && stt.rows.size === 0) return { ...empty, state: 'none' }
    const rows = [...stt.rows.values()]
    const todayStart = Math.floor(now / DAY) * DAY // 和汇总的「今日」同一个起点：北京时间 8 点（UTC 0 点）
    const hour = sumLiq(rows, now - HOUR, now + 1), today = sumLiq(rows, todayStart, now + 1), day = sumLiq(rows, now - DAY, now + 1)
    const { start, cells } = liqCells(rows, now)
    const mx = today.max
    const tAt = Math.max(t0, start)
    const sel = Math.floor((tAt - start) / LIQ_CELL_MS)
    return {
      state: 'data', hour, today, day, cells, from: this.dayLabel(start, now),
      maxWhen: mx ? this.label(mx[0], 60_000) : '', maxPrice: mx ? mx[5].toFixed(dec) : '',
      selCell: step <= LIQ_CELL_MS * 4 && t0 >= start ? Math.min(cells.length - 1, sel) : -1,
    }
  }

  private dayLabel(t: number, now: number): string {
    const tz = this.tz() * 60_000
    const sameDay = Math.floor((t + tz) / DAY) === Math.floor((now + tz) / DAY)
    return `${sameDay ? BT.todayDay : BT.yesterday} ${this.label(t, 60_000)}`
  }

  /** 副标题只写品种（现货加「现货」，和 iOS BigTradeSheet.subtitle 同一套）。用户 2026-10-08：标题没必要写交易所——
   *  他关心的是品种和数据，哪几家合在一起权重不大；分家的信息留在读数卡与爆仓「最大一笔」里 */
  private subtitles(base: string, spot: boolean): string[] {
    return [spot ? `${base} ${BT.spot}` : base]
  }

  private thrText(): string {
    const t = this.d.thresholds()
    if (!t) return BT.auto
    const parts: string[] = []
    const perp = t.usdtPerp ?? t.coinPerp
    if (perp != null) parts.push(`${BT.perp} ${SHORT(perp)}`)
    if (t.spot != null) parts.push(`${BT.spot} ${SHORT(t.spot)}`)
    if (t.delivery != null && perp == null) parts.push(`${BT.delivery} ${SHORT(t.delivery)}`)
    const stepV = (t as Thresholds & { step?: number }).step ?? this.d.port()?.step ?? null
    if (stepV != null) parts.push(fill(BT.step, { v: +stepV.toPrecision(6) }))
    return parts.join(' · ')
  }
}

/** 图上气泡的偏好开关（分析面板那颗） */
export function toggleSigns(): void { st.bigTradeSigns = !st.bigTradeSigns; save() }

/** 开发构建里 ?bt=loading|spot|liqEmpty|stale|untracked（截图用） */
export function devForce(): BtForce | null {
  if (!import.meta.env.DEV) return null
  try {
    const v = new URLSearchParams(location.search).get('bt')
    return v === 'loading' || v === 'spot' || v === 'liqEmpty' || v === 'stale' || v === 'untracked' ? v : null
  } catch { return null }
}
