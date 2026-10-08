/* Hkline Web · 等幅 K 线（Range bars，2026-10-07）
 *
 * 不按时间、按价格走满一个固定幅度出一根：每根的 高 − 低 正好等于「幅度」，走满了下一根从上一根收盘接着开。
 *   · 幅度自动：已加载 1 分钟线的 ATR(14) × 0.5，取最近的 1/2/5×10ⁿ，至少一个最小价位；同一格同一只品种在这次打开页面里不再变
 *     （重取、翻页、实时都用同一个幅度，图不会忽然整段换形）。不给用户设置。
 *   · 数据源：用已经加载的 1 分钟线合成（周期更粗时切到 1 分钟），往左翻页照旧取 1 分钟、实时推送照旧推 1 分钟。
 *     一根 1 分钟线里价格怎么走不知道，按 TradingView 的约定：阳线 开→低→高→收、阴线 开→高→低→收；
 *     成交量按走过的价格路程分到各根；每根的时间 = 走到它开盘那一刻在这一分钟里的位置（严格递增，时间 ↔ 下标一一对应）。
 *   · 实时：同一分钟的推送只把「新创的高 / 低、再到最新价」这段路接着走，只改最后一根、走满了往后加根；
 *     新根的时间用当前时刻（落在这一分钟之内）。
 *   · 横轴是根序号，时间刻度标的是那根开始的时间；均线、副图指标都按合成出来的根算（图表照旧拿 bars 算）。
 *   · 画线：照旧按时间存，落在哪根就是哪根；比已加载最早一根还早的线在等幅模式下藏起来（不删），往左翻到了或退出等幅就回来。
 *
 * 开关按格子记（十六图里各格独立）；和足迹、平均 K 线三选一，由 mainStyle.ts 管。
 */
import type { Bar } from './calc'
import type { ChartMetaInput, TVChart } from './chart'
import type { TimeTick } from './timeAxis'
import { TIME_STEPS, TIME_TICK_MIN_PX } from './timeAxis'
import { nearestNice } from './footprint'
import type { CellFlagSource } from './heikinAshi'
import { GLOSSARY, term } from '../ui/overlay'
import { TZ_MS, pad, sh } from '../util/format'

GLOSSARY['等幅 K 线'] = '每根 K 线不按时间、按价格走满同一个幅度画一根（Range bars），横盘时少画、单边时多画；幅度按近期 1 分钟波动自动取。'

const MIN = 60_000
const rnd = (x: number): number => +x.toPrecision(12)

// ------------------------------------------------------------ 幅度（纯函数）
/** 1 分钟线的 ATR(14)（Wilder）× 0.5，取最近的 1/2/5×10ⁿ，至少 10^-dec */
export function rangeStep(base: readonly Bar[], dec: number): number {
  const tick = Math.pow(10, -Math.max(0, dec))
  if (!base.length) return tick
  let atr = 0, n = 0
  for (let i = 0; i < base.length; i++) {
    const b = base[i], pc = i ? base[i - 1].c : b.o
    const tr = Math.max(b.h - b.l, Math.abs(b.h - pc), Math.abs(b.l - pc))
    if (n < 14) { n++; atr += (tr - atr) / n } else atr = (atr * 13 + tr) / 14
  }
  const step = atr > 0 ? nearestNice(atr * 0.5) : nearestNice(base[base.length - 1].c * 0.0005)
  return rnd(Math.max(step, tick))
}

// ------------------------------------------------------------ 合成
type Vol = { v: number; tb: number; bv: number }
const volOf = (b: Bar): Vol => ({ v: b.v || 0, tb: b.tb ?? 0, bv: b.bv ?? 0 })

export class RangeBuilder {
  /** 合成出来的根（最后一根可能还没走满） */
  out: Bar[] = []
  /** 已经走过的那根 1 分钟线到了哪（实时推送只接着走新多出来的那段） */
  private seen: ({ t: number; h: number; l: number; c: number } & Vol) | null = null
  private hasTb = false
  private hasBv = false
  constructor(readonly step: number) {}

  build(base: readonly Bar[]): this { for (const b of base) this.addHistory(b); return this }

  /** 一整根历史 1 分钟线 */
  addHistory(b: Bar): void {
    if (this.seen && b.t <= this.seen.t) return
    this.flags(b)
    const pts = b.c >= b.o ? [b.o, b.l, b.h, b.c] : [b.o, b.h, b.l, b.c]
    this.walk(b.t, pts, volOf(b), f => b.t + Math.floor(f * MIN))
    this.seen = { t: b.t, h: b.h, l: b.l, c: b.c, ...volOf(b) }
  }

  /** 实时推送（同一分钟反复推、或新的一分钟）；回要交给图表的根：改过的最后一根 + 新加的 */
  update(b: Bar, now = Date.now()): Bar[] {
    const s = this.seen, n0 = this.out.length
    if (s && b.t < s.t) return []
    this.flags(b)
    const same = !!s && b.t === s.t
    const from = same ? s! : { t: b.t, h: b.o, l: b.o, c: b.o, v: 0, tb: 0, bv: 0 }
    const pts: number[] = same ? [] : [b.o]
    const up = b.h > from.h, dn = b.l < from.l
    if (up && dn) pts.push(...(b.h - b.c > b.c - b.l ? [b.h, b.l] : [b.l, b.h]))
    else if (up) pts.push(b.h)
    else if (dn) pts.push(b.l)
    pts.push(b.c)
    const nv = volOf(b), dv: Vol = { v: Math.max(0, nv.v - from.v), tb: Math.max(0, nv.tb - from.tb), bv: Math.max(0, nv.bv - from.bv) }
    const at = Math.min(Math.max(now, b.t), b.t + MIN - 1)
    this.walk(b.t, pts, dv, () => at)
    this.seen = { t: b.t, h: Math.max(from.h, b.h), l: Math.min(from.l, b.l), c: b.c, ...nv }
    return this.out.slice(Math.max(0, n0 - 1))
  }

  private flags(b: Bar): void { if (b.tb != null) this.hasTb = true; if (b.bv != null) this.hasBv = true }

  private open(t: number, p: number): Bar {
    const last = this.out[this.out.length - 1]
    const bar: Bar = { t: last ? Math.max(t, last.t + 1) : t, o: p, h: p, l: p, c: p, v: 0 }
    if (this.hasTb) bar.tb = 0
    if (this.hasBv) bar.bv = 0
    this.out.push(bar)
    return bar
  }
  private add(bar: Bar, vol: Vol, k: number): void {
    bar.v += vol.v * k
    if (this.hasTb) bar.tb = (bar.tb ?? 0) + vol.tb * k
    if (this.hasBv) bar.bv = (bar.bv ?? 0) + vol.bv * k
  }

  /** 价格依次走过 pts（从最后一根的收盘出发）；走满幅度就收这一根、在 fracTime(走过的路程占比) 那一刻开下一根 */
  private walk(t: number, pts: number[], vol: Vol, fracTime: (f: number) => number): void {
    const step = this.step, eps = step * 1e-9
    let cur = this.out[this.out.length - 1] ?? this.open(t, pts[0])
    let pos = cur.c, L = 0, prev = pos
    for (const p of pts) { L += Math.abs(p - prev); prev = p }
    if (!(L > eps)) { this.add(cur, vol, 1); return }
    let gone = 0
    for (const p of pts) {
      while (Math.abs(p - pos) > eps) {
        const upward = p > pos
        const lim = upward ? rnd(cur.l + step) : rnd(cur.h - step)
        const full = upward ? p > lim + eps : p < lim - eps
        const to = full ? lim : p, d = Math.abs(to - pos)
        this.add(cur, vol, d / L); gone += d
        if (to > cur.h) cur.h = to
        if (to < cur.l) cur.l = to
        cur.c = to; pos = to
        if (full) cur = this.open(fracTime(gone / L), pos)
      }
    }
  }
}

// ------------------------------------------------------------ 时间刻度（根距不等：按跨过整点 / 整几分钟挑）
export function rangeTicks(timeAt: (i: number) => number, lo: number, hi: number, xOf: (i: number) => number, nBars: number): TimeTick[] {
  const out: TimeTick[] = []
  const a = Math.max(0, lo), b = Math.min(nBars - 1, hi)
  if (!(b > a)) return out
  const msPerPx = (timeAt(b) - timeAt(a)) / Math.max(1, xOf(b) - xOf(a))
  const step = TIME_STEPS.find(s => s >= msPerPx * TIME_TICK_MIN_PX && s >= MIN) || 864e5
  let lastX = -Infinity
  for (let i = Math.max(1, lo); i <= hi; i++) {
    const t = timeAt(i), tp = timeAt(i - 1)
    const d = sh(t), dp = sh(tp)
    let label = '', bold = false
    if (d.getUTCDate() !== dp.getUTCDate()) { label = d.getUTCDate() === 1 ? `${d.getUTCMonth() + 1}月` : String(d.getUTCDate()); bold = true }
    else if (Math.floor((t + TZ_MS) / step) !== Math.floor((tp + TZ_MS) / step)) label = `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`
    else continue
    const x = xOf(i)
    if (x - lastX < TIME_TICK_MIN_PX * 0.8) { if (bold && out.length && !out[out.length - 1].bold) { out[out.length - 1] = { i, label, bold }; lastX = x } continue }
    out.push({ i, label, bold }); lastX = x
  }
  return out
}

/** 幅度的写法：普通数字、不带货币符号、去掉尾零 */
export function stepText(step: number): string {
  const dp = Math.max(0, Math.min(12, -Math.floor(Math.log10(step)) + 2))
  return step.toFixed(dp).replace(/\.?0+$/, '')
}

// ------------------------------------------------------------ 每格开关与挂到图表上
// 开关记在格子配置里、随布局集跟人走（pages/chart.ts 用 setRangeBarsSource 接到 store；老的本机存法由 store 迁走）；没接时只记内存
const memory = new Set<number>()
const memorySource: CellFlagSource = { on: i => memory.has(i), set: (i, on) => { if (on) memory.add(i); else memory.delete(i) } }
let source: CellFlagSource = memorySource
export function setRangeBarsSource(s: CellFlagSource | null): void { source = s ?? memorySource }
const onCells = { has: (i: number): boolean => source.on(i) }
const bound = new Map<number, TVChart>()
/** 同一格同一只品种这次打开页面里用同一个幅度 */
const steps = new Map<string, number>()

interface St {
  idx: number
  orig: { setData: TVChart['setData']; prependData: TVChart['prependData']; updateBar: TVChart['updateBar'] }
  /** 开着等幅时手里的原始 1 分钟线；null = 没在等幅模式（图上就是原始 K 线） */
  base: Bar[] | null
  b: RangeBuilder | null
  meta: ChartMetaInput | null
}
const states = new WeakMap<TVChart, St>()

export function rangeBarsOn(idx: number): boolean { return onCells.has(idx) }
export function setRangeBars(idx: number, on: boolean): void {
  if (on === onCells.has(idx)) return
  source.set(idx, on)
  syncRangeBars(idx)
}
/** 图上的状态对齐开关（setRangeBars 之后；换了一套布局、这一格没重取 K 线时也调一下） */
export function syncRangeBars(idx: number): void {
  const on = onCells.has(idx), c = bound.get(idx), s = c && states.get(c)
  if (!c || !s) return
  if (on && !s.base && c.iv === MIN) enter(c, s, c.bars, { ...c.meta, iv: c.iv })
  else if (!on && s.base) leave(c, s)
}
/** 等幅模式下图上那份是合成的；要原始 1 分钟线（断线补尾巴对齐）时读这个 */
export function baseBars(c: TVChart): Bar[] { return states.get(c)?.base ?? c.bars }
/** 这一格当前的幅度（没在等幅模式回 null） */
export function rangeStepOf(c: TVChart): number | null { return states.get(c)?.b?.step ?? null }

function plain(c: TVChart, s: St): void {
  s.base = null; s.b = null
  delete (c as { timeTicks?: unknown }).timeTicks
  c.drawingShown = null
}
function enter(c: TVChart, s: St, base: Bar[], meta: ChartMetaInput): void {
  const key = `${s.idx}|${meta.symbol ?? c.meta.symbol}`
  let step = steps.get(key)
  if (step == null && base.length) { step = rangeStep(base, meta.dec ?? c.meta.dec); steps.set(key, step) }
  s.base = base; s.meta = meta
  s.b = new RangeBuilder(step ?? 1).build(base)
  c.timeTicks = () => rangeTicks(i => c.timeAt(i), Math.floor(c.xToIndex(0)), Math.ceil(c.rightBar), i => c.indexToX(i), c.bars.length)
  // 比最早一根还早的画线：等幅横轴上没有它的位置（往左按 1 分钟外推会错位），先藏着
  c.drawingShown = d => !c.bars.length || d.pts.every(q => q.t >= c.bars[0].t)
  c.bars = [] // 换成另一条横轴：视口按新数据重摆
  s.orig.setData(s.b.out.slice(), meta)
}
function leave(c: TVChart, s: St): void {
  const base = s.base ?? [], n = c.bars.length
  const edge = c.rightBar - (n - 1), tRight = c.timeOfIndex(c.rightBar)
  const meta = s.meta ?? { ...c.meta, iv: c.iv }
  plain(c, s)
  s.orig.setData(base, meta)
  // 停在最右边就还停最右边；往左看着的就把右缘那一刻接着放在右缘
  if (base.length) c.rightBar = edge >= 0 ? base.length - 1 + edge : c.indexAt(tRight)
  c.dirty = true; c.legendDirty = true
}

/** 格子销毁时放掉（bound 按格号记，布局从十六图收回一图时 1…15 号格不会再 bind，不删就一直攥着死图的整块 DOM 与 K 线） */
export function unbindRangeBars(chart: TVChart): void { for (const [i, c] of bound) if (c === chart) bound.delete(i) }

/** pages/chart.ts 建格子时挂上（在 bindFootprint / bindHeikinAshi 之后） */
export function bindRangeBars(chart: TVChart, idx: number): void {
  bound.set(idx, chart)
  const s: St = { idx, base: null, b: null, meta: null, orig: { setData: chart.setData.bind(chart), prependData: chart.prependData.bind(chart), updateBar: chart.updateBar.bind(chart) } }
  states.set(chart, s)
  chart.setData = (bars, meta) => {
    if (onCells.has(idx) && meta.iv === MIN) { enter(chart, s, bars, meta); return }
    if (s.base) plain(chart, s)
    // 等幅开着却换到了别的周期：当成退出等幅
    if (onCells.has(idx)) source.set(idx, false)
    s.orig.setData(bars, meta)
  }
  chart.prependData = more => {
    const base = s.base, b = s.b
    if (!base || !b) { s.orig.prependData(more); return }
    const first = base[0]?.t ?? Infinity
    more = more.filter(x => x.t < first)
    if (!more.length) return
    // 更早的一段单独合成接在前面：已经画着的根一根不动（画线、视口都不跳）
    const older = new RangeBuilder(b.step).build(more).out
    s.base = more.concat(base)
    b.out = older.concat(b.out)
    s.orig.prependData(older)
  }
  chart.updateBar = bar => {
    const base = s.base, b = s.b
    if (!base || !b) { s.orig.updateBar(bar); return }
    const last = base[base.length - 1]
    if (last && bar.t < last.t) return
    const changed = b.update(bar)
    if (last && bar.t === last.t) Object.assign(last, bar); else base.push({ ...bar })
    // 取数失败后图是空的、第一根从推送来：整份交给图表
    if (!chart.bars.length) { if (changed.length) s.orig.setData(b.out.slice(), s.meta ?? { ...chart.meta, iv: chart.iv }); return }
    for (const x of changed) s.orig.updateBar(x)
  }
  const legend = chart.legendExtra
  chart.legendExtra = i => (legend?.(i) ?? '') + (s.b ? `<div class="lrow"><span class="ind-name">${term('等幅 K 线')}</span><span class="vals num"><span>幅度 ${stepText(s.b.step)}</span></span></div>` : '')
}

/** 测试用 */
export function resetRangeBars(): void { memory.clear(); bound.clear(); steps.clear() }
