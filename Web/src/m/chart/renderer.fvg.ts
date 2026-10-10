// 移植自 KanpanChart/Sources/KanpanChart/ChartRenderer+FVG.swift（公允价值缺口这一层，画法与先后照 iOS）
//
// 只画几何事实、不下判定：区间由共用算法 analysis/fvg.ts 算（三端同口径、同一份黄金样例），这里只管
//   1. 已收线根数：末根还没走完（开盘 + 一个周期 > 此刻）就不算它——正在走的那根只参与回补、不参与生成；
//   2. 缓存：按（序列这一份、它的 revision、根数、已收线根数）记一份，序列不动就不重算（十字线那一层根本不调这里）；
//   3. 画：盒子从中间那根的左沿铺到图右缘，多头 t.band、空头 t.amber（BOLL 那一对皮肤色，不用涨跌色免得和
//      主力订单流的绿红墙撞色），填充 12%、不描边；中线（原始缺口 50%）0.5 虚线 35%，盒子回补到不含中线时不画。
// 画在主力订单流之后、蜡烛之前：订单流是预混的不透明色块，缺口少量真透明压在它上面，K 线压在最上面。
// 不撑价格轴；对比模式与百分比轴下不画。

import type { ChartRenderer } from './renderer'
import type { Layout, Pane, PriceRange } from './geometry'
import { yOf as coreYOf } from './geometry'
import type { BarSeries } from './series'
import { isIrregular } from './series'
import { advancing } from './format'
import { css } from './paint'
import { effectivePriceMode } from './state'
import { orderFlowBarX, orderFlowPlotClip } from './renderer.orderflow'
import { FVG_CONFIG, fvgZonesOfSeries, type FVGZone } from '../../analysis/fvg'

export const FVGStyle = {
  fillAlpha: 0.12,
  midAlpha: 0.35,
  midWidth: 0.5,
  midDash: [3, 2] as readonly number[],
} as const

// ------------------------------------------------------------------ 已收线根数

/** 第 i 根的收线时刻（月 / 年按日历走，其余开盘 + 步长；和倒计时同一口径）。 */
export function barCloseMs(b: BarSeries, i: number): number {
  const open = b.time(i)
  return isIrregular(b.interval) ? advancing(b.interval, open, 1) : open + b.step
}

/** 前多少根已收线：末根收线时刻还没到（> now）就是正在走的那根，不算。 */
export function closedBarCount(b: BarSeries, now: number): number {
  const n = b.count
  if (n <= 0) return 0
  return barCloseMs(b, n - 1) > now ? n - 1 : n
}

// ------------------------------------------------------------------ 缓存

interface FVGEntry { ref: BarSeries; revision: number; count: number; closed: number; zones: FVGZone[] }

const cache = new WeakMap<ChartRenderer, FVGEntry>()
let computed = 0

/** 测试用：到目前为止真算过几次（缓存命中不算）。 */
export const fvgComputeCount = (): number => computed

/** 这一份序列此刻还在的缺口（按序列 + 已收线根数缓存；同一份没动就原样返回同一个数组）。 */
export function fvgZonesFor(r: ChartRenderer, now: number = Date.now()): FVGZone[] {
  const b = r.state.input.series
  const closed = closedBarCount(b, now)
  const hit = cache.get(r)
  if (hit && hit.ref === b && hit.revision === b.revision && hit.count === b.count && hit.closed === closed) return hit.zones
  computed++
  const zones = fvgZonesOfSeries(b, closed, FVG_CONFIG)
  cache.set(r, { ref: b, revision: b.revision, count: b.count, closed, zones })
  return zones
}

/** 这一帧画不画：开关开着、不在对比 / 百分比轴下、有 K 线。 */
export function fvgShown(r: ChartRenderer): boolean {
  const s = r.state
  return s.input.fvg && !s.input.percentAxis && effectivePriceMode(s) !== 'percent' && !s.input.series.isEmpty
}

// ------------------------------------------------------------------ 画

/** 一块缺口在这一屏的矩形与中线 y（横向不在图里、纵向整块在主图外的给 null）。 */
export function fvgBox(r: ChartRenderer, z: FVGZone, pane: Pane, range: PriceRange, L: Layout, clipTop: number):
  { x0: number; x1: number; y0: number; y1: number; midY: number | null } | null {
  const plotW = L.plotW
  const x0 = Math.max(0, orderFlowBarX(r, z.startMs, r.spacing(plotW), plotW).left)
  if (!(x0 < plotW)) return null
  const mode = effectivePriceMode(r.state)
  const ya = coreYOf(z.top, pane, range, mode), yb = coreYOf(z.bottom, pane, range, mode)
  if (!Number.isFinite(ya) || !Number.isFinite(yb)) return null
  const y0 = Math.min(ya, yb), y1 = Math.max(ya, yb)
  if (y1 < clipTop || y0 > pane.y + pane.h) return null
  const my = z.midVisible ? coreYOf(z.mid, pane, range, mode) : NaN
  return { x0, x1: plotW, y0, y1, midY: Number.isFinite(my) ? my : null }
}

/** 在底图上画缺口（drawOrderFlow 之后、drawCandles 之前调）。返回画了几块。 */
export function drawFVG(r: ChartRenderer, ctx: CanvasRenderingContext2D, pane: Pane, range: PriceRange, L: Layout, now: number = Date.now()): number {
  if (!fvgShown(r) || !(L.plotW > 0)) return 0
  const zones = fvgZonesFor(r, now)
  if (!zones.length) return 0
  const clip = orderFlowPlotClip(r, pane, L.plotW)
  const t = r.colors
  let drawn = 0
  ctx.save()
  ctx.beginPath()
  ctx.rect(clip.x, clip.y, clip.w, clip.h)
  ctx.clip()
  for (const z of zones) {
    const box = fvgBox(r, z, pane, range, L, clip.y)
    if (!box) continue
    const color = css(z.side === 'bull' ? t.band : t.amber)
    ctx.globalAlpha = FVGStyle.fillAlpha
    ctx.fillStyle = color
    ctx.fillRect(box.x0, box.y0, box.x1 - box.x0, Math.max(box.y1 - box.y0, 0.5))
    if (box.midY != null) {
      ctx.globalAlpha = FVGStyle.midAlpha
      ctx.strokeStyle = color
      ctx.lineWidth = FVGStyle.midWidth
      ctx.setLineDash([...FVGStyle.midDash])
      ctx.beginPath()
      ctx.moveTo(box.x0, box.midY)
      ctx.lineTo(box.x1, box.midY)
      ctx.stroke()
      ctx.setLineDash([])
    }
    drawn++
  }
  ctx.globalAlpha = 1
  ctx.restore()
  return drawn
}
