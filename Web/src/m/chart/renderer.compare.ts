// 移植自 KanpanChart/Sources/KanpanChart/ChartRenderer+Compare.swift
//
// 对比模式（百分比轴）：区间、刻度、对比线、对比图例。

import type { Layout, Pane, PriceRange, PriceTransform, ViewWindow } from './geometry'
import { AICoinBehavior, PriceMapping, priceRange, priceTicks, visibleRange } from './geometry'
import { advancing } from './format'
import type { Hex } from './paint'
import { ChartFont, css, drawLeft, textWidth } from './paint'
import type { ChartRenderer } from './renderer'
import { compareBase, compareBaseIndex, comparePercentAt, comparePercentLabel, effectivePriceMode } from './state'

export function compareRange(r: ChartRenderer, view: ViewWindow, transform: PriceTransform, paneHeight: number, topInset: number): PriceRange {
  const st = r.state
  const base = compareBase(st, view), index = compareBaseIndex(st, view)
  const b = visibleRange(view, st.input.series)
  const extra = [base]
  for (const series of st.input.compare) {
    for (let i = b.lo; i <= b.hi; i++) {
      const value = comparePercentAt(series, i, index)
      if (value != null) extra.push((1 + value / 100) * base)
    }
  }
  const linear: PriceTransform = { ...transform, mode: 'linear' }
  const result = priceRange(view, st.input.series, {
    transform: linear, extraPrices: extra.concat(r.heikin?.extremes ?? []), bias: st.input.options.bias,
    paneHeight, topInset, anchorPrice: transform.zoom !== 1 ? st.viewport.axisScaleAnchor : null,
  })
  return { ...result, base }
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

export function drawCompare(r: ChartRenderer, ctx: CanvasRenderingContext2D, pane: Pane, range: PriceRange, L: Layout): void {
  const st = r.state, series0 = st.input.series
  const b = visibleRange(st.viewport.view, series0)
  const baseIndex = compareBaseIndex(st)
  const map = new PriceMapping(range, 'percent')
  ctx.save()
  ctx.beginPath(); ctx.rect(0, pane.y, L.plotW, pane.h); ctx.clip()
  ctx.lineWidth = 1; ctx.lineJoin = 'round'
  for (const series of st.input.compare) {
    ctx.strokeStyle = css(series.color)
    ctx.beginPath()
    let connected = false
    let previousTime: number | null = null
    for (let i = b.lo; i <= b.hi; i++) {
      const percent = comparePercentAt(series, i, baseIndex)
      if (percent == null) { connected = false; previousTime = null; continue }
      const time = series0.time(i)
      // 中间缺了 K 线（停牌、没数据）就断开，不拿直线连过去。
      if (previousTime != null && advancing(series0.interval, previousTime, 1) !== time) connected = false
      const px = r.x(time, L.plotW), py = map.y((1 + percent / 100) * range.base, pane)
      if (connected) ctx.lineTo(px, py); else ctx.moveTo(px, py)
      connected = true; previousTime = time
    }
    ctx.stroke()
  }
  ctx.restore()
}

export function compareLegend(r: ChartRenderer): { name: string; value: number | null; color: Hex }[] {
  const st = r.state, b = st.input.series
  if (!st.input.percentAxis || b.isEmpty) return []
  const index = r.legendIndex, baseIndex = compareBaseIndex(st)
  const main = (b.close[index] / compareBase(st) - 1) * 100
  const head: { name: string; value: number | null; color: Hex }[] = [{ name: st.input.symbol.base, value: main, color: r.colors.text }]
  return head.concat(
    st.input.compare.map(c => ({ name: c.name, value: comparePercentAt(c, index, baseIndex), color: c.color })))
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
