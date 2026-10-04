// 移植自 KanpanChart/Sources/KanpanChart/ChartRenderer+Compare.swift
//
// 对比模式（百分比轴）：区间、刻度、对比线、对比图例。

import type { Layout, Pane, PriceRange, PriceTransform, ViewWindow } from './geometry'
import { AICoinBehavior, PriceMapping, priceRange, priceTicks, visibleRange } from './geometry'
import { advancing } from './format'
import type { Hex } from './paint'
import { ChartFont, css, drawLeft, textWidth } from './paint'
import type { ChartRenderer } from './renderer'
import type { CompareSeries } from './state'
import { compareBase, compareBaseIndex, compareBaseIndexFrom, comparePercentAt, comparePercentLabel, effectivePriceMode } from './state'

export function compareRange(r: ChartRenderer, view: ViewWindow, transform: PriceTransform, paneHeight: number, topInset: number): PriceRange {
  const st = r.state
  const base = compareBase(st, view)
  const extra = [base]
  for (const line of compareLines(r, view)) {
    for (const point of line.percents) if (point) extra.push((1 + point.percent / 100) * base)
  }
  const linear: PriceTransform = { ...transform, mode: 'linear' }
  const result = priceRange(view, st.input.series, {
    transform: linear, extraPrices: extra.concat(r.heikin?.extremes ?? []), bias: st.input.options.bias,
    paneHeight, topInset, anchorPrice: transform.zoom !== 1 ? st.viewport.axisScaleAnchor : null,
  })
  return { ...result, base }
}

/** 一条比价线在某个视野里的样子：它自己的基准根、从哪根起画、可见段 lo…hi 上逐根的读数（缺根 null）。 */
export interface CompareLine {
  series: CompareSeries
  baseIndex: number
  from: number
  percents: ({ index: number; percent: number } | null)[]
}

/** 一条比价线的基准根与起画根：基准就是主品种那根时从可见段最左（含左侧护栏根）起，
 *  往后挪了就从基准那根起；可见段里一根开盘价都没有时 null（整条不画）。 */
export function compareAnchor(r: ChartRenderer, series: CompareSeries, view?: ViewWindow): { baseIndex: number; from: number } | null {
  const st = r.state
  if (st.input.series.isEmpty) return null
  const v = view ?? st.viewport.view
  const b = visibleRange(v, st.input.series)
  const mainBase = compareBaseIndex(st, v)
  const base = compareBaseIndexFrom(series, mainBase, b.hi)
  if (base == null) return null
  return { baseIndex: base, from: base === mainBase ? b.lo : base }
}

/** 区间、画线、图例共用的一份比价几何（ChartRenderer+Compare.swift compareLines）：
 *  三处各算各的就会出现「线画在 A 基准上、图例报 B 基准」。 */
export function compareLines(r: ChartRenderer, view?: ViewWindow): CompareLine[] {
  const st = r.state
  if (st.input.series.isEmpty) return []
  const v = view ?? st.viewport.view
  const b = visibleRange(v, st.input.series)
  return st.input.compare.map(series => {
    const anchor = compareAnchor(r, series, v)
    const percents: CompareLine['percents'] = []
    for (let i = b.lo; i <= b.hi; i++) {
      const value = anchor && i >= anchor.from ? comparePercentAt(series, i, anchor.baseIndex) : null
      percents.push(value == null ? null : { index: i, percent: value })
    }
    return { series, baseIndex: anchor?.baseIndex ?? b.hi + 1, from: anchor?.from ?? b.hi + 1, percents }
  })
}

/** 百分比轴上 0% 那条一定要有；离 0% 太近（< 14pt）的刻度让位。 */
export function mainPriceTicks(r: ChartRenderer, range: PriceRange, paneHeight: number): number[] {
  const st = r.state
  let ticks = priceTicks(range, effectivePriceMode(st), paneHeight)
  if (st.input.percentAxis && range.lo <= range.base && range.hi >= range.base) {
    const span = (range.hi - range.lo) / range.base * 100
    ticks = ticks.filter(t => !(Math.abs(t) / Math.max(span, 1e-12) * paneHeight < 14))
    ticks.push(0)
    ticks.sort((a, b) => a - b)
  }
  return ticks
}

/** 每条比价线断成的若干段折线（屏幕坐标）。drawCompare 照它画，测试照它量。 */
export function compareSegments(r: ChartRenderer, pane: Pane, range: PriceRange, L: Layout): { x: number; y: number }[][][] {
  const series0 = r.state.input.series
  const map = new PriceMapping(range, 'percent')
  return compareLines(r).map(line => {
    const segments: { x: number; y: number }[][] = []
    let current: { x: number; y: number }[] = []
    let previousTime: number | null = null
    for (const entry of line.percents) {
      if (!entry) {
        if (current.length) { segments.push(current); current = [] }
        previousTime = null; continue
      }
      const time = series0.time(entry.index)
      // 中间缺了 K 线（停牌、没数据）就断开，不拿直线连过去。
      if (previousTime != null && advancing(series0.interval, previousTime, 1) !== time && current.length) {
        segments.push(current); current = []
      }
      current.push({ x: r.x(time, L.plotW), y: map.y((1 + entry.percent / 100) * range.base, pane) })
      previousTime = time
    }
    if (current.length) segments.push(current)
    return segments
  })
}

export function drawCompare(r: ChartRenderer, ctx: CanvasRenderingContext2D, pane: Pane, range: PriceRange, L: Layout): void {
  const st = r.state
  const all = compareSegments(r, pane, range, L)
  ctx.save()
  ctx.beginPath(); ctx.rect(0, pane.y, L.plotW, pane.h); ctx.clip()
  ctx.lineWidth = 1; ctx.lineJoin = 'round'
  st.input.compare.forEach((series, k) => {
    ctx.strokeStyle = css(series.color)
    ctx.beginPath()
    for (const segment of all[k] ?? []) {
      if (!segment.length) continue
      ctx.moveTo(segment[0].x, segment[0].y)
      for (let j = 1; j < segment.length; j++) ctx.lineTo(segment[j].x, segment[j].y)
    }
    ctx.stroke()
  })
  ctx.restore()
}

export function compareLegend(r: ChartRenderer): { name: string; value: number | null; color: Hex }[] {
  const st = r.state, b = st.input.series
  if (!st.input.percentAxis || b.isEmpty) return []
  const index = r.legendIndex
  const main = (b.close[index] / compareBase(st) - 1) * 100
  const head: { name: string; value: number | null; color: Hex }[] = [{ name: st.input.symbol.base, value: main, color: r.colors.text }]
  return head.concat(st.input.compare.map(c => {
    // 十字线停在这条线的基准之前：那一根没有「相对于它」的涨跌，报「—」。
    const anchor = compareAnchor(r, c)
    const value = anchor && index >= anchor.from ? comparePercentAt(c, index, anchor.baseIndex) : null
    return { name: c.name, value, color: c.color }
  }))
}

export function compareLegendInset(r: ChartRenderer, plotW: number): number {
  let x = 8, rows = 1
  for (const entry of compareLegend(r)) {
    const width = textWidth(entry.name + ' −999.99%', ChartFont.axis) + 8
    if (x + width > plotW - 4) { rows += 1; x = 8 }
    x += Math.min(width, plotW - 12)
  }
  return Math.max(AICoinBehavior.mainTopInset, rows * 12 + 12)
}

export function drawCompareLegend(r: ChartRenderer, ctx: CanvasRenderingContext2D, pane: Pane, L: Layout): void {
  let x = 8, y = pane.y + 9
  ctx.save()
  ctx.beginPath(); ctx.rect(0, pane.y, L.plotW, r.mainLegendInset(L.plotW)); ctx.clip()
  for (const entry of compareLegend(r)) {
    const width = textWidth(entry.name + ' −999.99%', ChartFont.axis) + 8
    if (x + width > L.plotW - 4) { x = 8; y += 12 }
    drawLeft(ctx, entry.name + ' ' + comparePercentLabel(entry.value), x, y, ChartFont.axis, entry.color)
    x += Math.min(width, L.plotW - 12)
  }
  ctx.restore()
}
