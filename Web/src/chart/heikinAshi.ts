/* Hkline Web · 平均 K 线（Heikin Ashi，2026-10-07）
 *
 * 照 TradingView：平均 K 线只是主图蜡烛的画法——
 *   收 = (开 + 高 + 低 + 收) / 4；开 = (上一根平均开 + 上一根平均收) / 2（第一根取 (开 + 收) / 2）；
 *   高 = max(高, 平均开, 平均收)；低 = min(低, 平均开, 平均收)。
 * 换算只在画蜡烛这一层做：指标、提醒、十字线读数、最新价标签照旧用真实开高低收；图例多一行平均 K 线的开高低收。
 * 实时：最后一根每次推送都从倒数第二根的平均值重算，跟着逐笔走；往左翻页、换数据整段重算（1500 根不到 0.1 ms）。
 *
 * 开关按格子记（和足迹同一个做法，十六图里各格各自独立）；和足迹、等幅 K 线三选一，由 mainStyle.ts 管。
 */
import type { Bar } from './calc'
import type { TVChart } from './chart'
import { GLOSSARY, term } from '../ui/overlay'
import { fmt } from '../util/format'

export interface HA { o: number; h: number; l: number; c: number }

GLOSSARY['平均 K 线'] = '每根蜡烛用前后平均过的开收价画（Heikin Ashi），趋势里颜色更连贯、少噪声；价格轴、十字线、指标仍是真实价格。'

/** 整段换算 */
export function heikinAshi(bars: readonly Bar[]): HA[] {
  const out: HA[] = new Array(bars.length)
  for (let i = 0; i < bars.length; i++) out[i] = haStep(bars[i], i ? out[i - 1] : null)
  return out
}
/** 一根：prev 是上一根的平均值（第一根给 null） */
export function haStep(b: Bar, prev: HA | null): HA {
  const c = (b.o + b.h + b.l + b.c) / 4
  const o = prev ? (prev.o + prev.c) / 2 : (b.o + b.c) / 2
  return { o, h: Math.max(b.h, o, c), l: Math.min(b.l, o, c), c }
}

/** 增量缓存：同一份 K 线（同一个数组、同一个开头）只重算末尾那根和新来的 */
export class HACache {
  private src: readonly Bar[] | null = null
  private first = NaN
  private out: HA[] = []
  get(bars: readonly Bar[]): HA[] {
    const n = bars.length
    if (bars !== this.src || !n || bars[0].t !== this.first || this.out.length > n) {
      this.src = bars; this.first = n ? bars[0].t : NaN; this.out = heikinAshi(bars)
      return this.out
    }
    // 最后一根是原地改的（实时推送），从它开始往后重算
    for (let i = Math.max(0, this.out.length - 1); i < n; i++) this.out[i] = haStep(bars[i], i ? this.out[i - 1] : null)
    return this.out
  }
}

// ------------------------------------------------------------ 每格开关
// 开关记在格子配置里、随布局集跟人走（pages/chart.ts 用 setHeikinAshiSource 接到 store；老的本机存法由 store 迁走）；没接时只记内存
export interface CellFlagSource { on(idx: number): boolean; set(idx: number, on: boolean): void }
const memory = new Set<number>()
const memorySource: CellFlagSource = { on: i => memory.has(i), set: (i, on) => { if (on) memory.add(i); else memory.delete(i) } }
let source: CellFlagSource = memorySource
export function setHeikinAshiSource(s: CellFlagSource | null): void { source = s ?? memorySource }
const onCells = { has: (i: number): boolean => source.on(i) }
const bound = new Map<number, TVChart>()
const caches = new WeakMap<TVChart, HACache>()
export function heikinAshiOn(idx: number): boolean { return onCells.has(idx) }
export function setHeikinAshi(idx: number, on: boolean): void {
  if (on === onCells.has(idx)) return
  source.set(idx, on)
  const c = bound.get(idx)
  if (c) { c.dirty = true; c.legendDirty = true }
}
function cacheOf(c: TVChart): HACache {
  let h = caches.get(c)
  if (!h) { h = new HACache(); caches.set(c, h) }
  return h
}

/** 用平均值画蜡烛：借图表自己的 drawCandles（同一套实体 / 影线宽度与涨跌色），画的那一瞬把 bars 换成平均值 */
function paint(c: TVChart, ...args: Parameters<TVChart['drawCandles']>): void {
  const real = c.bars, ha = cacheOf(c).get(real)
  c.bars = ha as unknown as Bar[]
  try { c.drawCandles(...args) } finally { c.bars = real }
}

/** 格子销毁时放掉（bound 按格号记，布局从十六图收回一图时 1…15 号格不会再 bind，不删就一直攥着死图的整块 DOM 与 K 线） */
export function unbindHeikinAshi(chart: TVChart): void { for (const [i, c] of bound) if (c === chart) bound.delete(i) }

/** pages/chart.ts 建格子时挂上（在 bindFootprint 之后）：接在足迹那个槽后面——足迹画了就不画，没画且开着平均 K 线就画平均值 */
export function bindHeikinAshi(chart: TVChart, idx: number): void {
  bound.set(idx, chart)
  const fp = chart.footprint, legend = chart.legendExtra
  chart.footprint = (p, r, from, to) => {
    if (fp?.(p, r, from, to)) return true
    if (!onCells.has(idx) || !chart.bars.length) return false
    paint(chart, p, r, from, to)
    return true
  }
  chart.legendExtra = i => (legend?.(i) ?? '') + legendRow(chart, idx, i)
}

function legendRow(c: TVChart, idx: number, i: number): string {
  if (!onCells.has(idx) || !c.bars[i]) return ''
  const h = cacheOf(c).get(c.bars)[i]; if (!h) return ''
  const cls = c.stale ? 'faint' : h.c >= h.o ? 'up' : 'down', v = (x: number) => `<span class="num ${cls}">${fmt(x, c.meta.dec)}</span>`
  return `<div class="lrow"><span class="ind-name">${term('平均 K 线')}</span>`
    + `<span class="ohlc"><span><i>开</i>${v(h.o)}</span><span><i>高</i>${v(h.h)}</span><span><i>低</i>${v(h.l)}</span><span><i>收</i>${v(h.c)}</span></span></div>`
}

/** 测试用 */
export function resetHeikinAshi(): void { memory.clear(); bound.clear() }
