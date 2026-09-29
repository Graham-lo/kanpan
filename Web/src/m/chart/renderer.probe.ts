// 移植自 KanpanChart/Sources/KanpanChart/ChartRenderer+Probe.swift
//
// 给测试与实验页用的只读探针：布局、区间、蜡烛像素位置。不参与绘制。

import { AICoinBehavior, candleMetrics, forward, hairline, priceTicks, snap, timeTicks, visibleRange, yOf } from './geometry'
import type { ChartRenderer } from './renderer'
import { effectiveGrid, effectivePriceMode, effectiveShape } from './state'

export interface ChartProbe {
  axisW: number; timeH: number; subH: number; spacing: number; bodyW: number; wickW: number
  padTop: number; padBottom: number
  plotW: number; mainH: number; thin: boolean; minBody: number; outline: number
  rangeLo: number; rangeHi: number; rangeBase: number
  visibleLo: number; visibleHi: number; viewFrom: number; viewTo: number
}

export interface CandleXProbe {
  index: number; center: number; bodyLeft: number; wickLeft: number; wickHair: number
  up: boolean; wickTop: number; wickBottom: number; bodyTop: number; bodyHeight: number; hollow: boolean
}

export function probe(r: ChartRenderer, W: number, H: number, s: number): ChartProbe {
  const L = r.layout(W, H), range = r.priceRange(W, H)
  const st = r.state, b = st.input.series
  const spacing = r.spacing(L.plotW)
  const m = candleMetrics(spacing, s)
  const { lo, hi } = visibleRange(st.viewport.view, b)
  const pane = L.main
  let hiP = -Infinity, loP = Infinity
  if (!b.isEmpty) {
    const closeOnly = st.input.options.kind === 'line'
    for (let i = lo; i <= hi; i++) {
      const h = closeOnly ? b.close[i] : b.high[i], l = closeOnly ? b.close[i] : b.low[i]
      if (h > hiP) hiP = h
      if (l < loP) loP = l
    }
    for (const arr of r.overlayLines()) {
      if (!(arr.length > lo)) continue
      for (let i = lo; i <= Math.min(hi, arr.length - 1); i++) {
        if (!Number.isFinite(arr[i])) continue
        if (arr[i] > hiP) hiP = arr[i]
        if (arr[i] < loP) loP = arr[i]
      }
    }
    for (const p of r.heikin?.extremes ?? []) {
      if (!Number.isFinite(p)) continue
      if (p > hiP) hiP = p
      if (p < loP) loP = p
    }
  }
  const mode = effectivePriceMode(st)
  const yHi = yOf(hiP, pane, range, mode), yLo = yOf(loP, pane, range, mode)
  return {
    axisW: L.axisW, timeH: AICoinBehavior.timeHeight, subH: L.subH, spacing, bodyW: m.bodyW, wickW: m.wickW,
    padTop: (yHi - pane.y) / pane.h, padBottom: (pane.y + pane.h - yLo) / pane.h,
    plotW: L.plotW, mainH: L.mainH, thin: m.thin, minBody: m.minBody, outline: m.outline,
    rangeLo: range.lo, rangeHi: range.hi, rangeBase: range.base,
    visibleLo: lo, visibleHi: hi, viewFrom: st.viewport.view.from, viewTo: st.viewport.view.to,
  }
}

export function candleXs(r: ChartRenderer, W: number, H: number, s: number): CandleXProbe[] {
  const L = r.layout(W, H), st = r.state, b = st.input.series
  if (b.isEmpty || st.input.options.kind === 'line') return []
  const range = r.priceRange(W, H), pane = L.main
  const shape = effectiveShape(st), ha = r.heikin
  const m = candleMetrics(r.spacing(L.plotW), s)
  const minBodyH = Math.max(m.wickW, snap(m.minBody, s))
  const { lo, hi } = visibleRange(st.viewport.view, b)
  const mode = effectivePriceMode(st)
  const y = (p: number) => yOf(p, pane, range, mode)
  const out: CandleXProbe[] = []
  for (let i = lo; i <= hi; i++) {
    const xc = r.x(b.time(i), L.plotW)
    if (xc < -4 || xc > L.plotW + 4) continue
    const bar = ha?.bar(i) ?? { o: b.open[i], h: b.high[i], l: b.low[i], c: b.close[i] }
    const up = bar.c >= bar.o
    const yo = y(bar.o), yc = y(bar.c)
    const top = snap(Math.min(yo, yc), s)
    const h = Math.max(minBodyH, snap(Math.max(yo, yc), s) - top)
    out.push({
      index: i, center: xc, bodyLeft: snap(xc - m.bodyW / 2, s), wickLeft: snap(xc - m.wickW / 2, s), wickHair: hairline(xc, s),
      up, wickTop: snap(y(bar.h), s), wickBottom: snap(y(bar.l), s), bodyTop: top, bodyHeight: h,
      hollow: shape === 'hollowUp' && up && h > m.outline * 2.2 && m.bodyW > m.outline * 2.2,
    })
  }
  return out
}

export function lastPriceY(r: ChartRenderer, W: number, H: number): { y: number; up: boolean } | null {
  const st = r.state, b = st.input.series
  if (!st.input.options.lastLine || b.isEmpty) return null
  const L = r.layout(W, H), range = r.priceRange(W, H), pane = L.main
  const i = b.count - 1
  const y = yOf(b.close[i], pane, range, effectivePriceMode(st))
  if (y < pane.y || y > pane.y + pane.h) return null
  return { y, up: b.close[i] >= b.open[i] }
}

export function priceGridYs(r: ChartRenderer, W: number, H: number): number[] {
  const L = r.layout(W, H), range = r.priceRange(W, H), pane = L.main
  const mode = effectivePriceMode(r.state)
  const a = forward(mode, range.lo, range.base), z = forward(mode, range.hi, range.base)
  const out: number[] = []
  for (const f of priceTicks(range, mode, pane.h)) {
    const y = pane.y + pane.h - ((f - a) / (z - a)) * pane.h
    if (y < pane.y + 6 || y > pane.y + pane.h - 2) continue
    out.push(y)
  }
  return out
}

export function verticalHairlineXs(r: ChartRenderer, W: number, H: number, s: number): number[] {
  const L = r.layout(W, H), st = r.state
  const out = [hairline(L.plotW, s)]
  if (effectiveGrid(st) !== 'both') return out
  for (const k of timeTicks(st.viewport.view, L.plotW, st.input.tzOffset)) {
    const xx = r.x(k.t, L.plotW)
    if (xx < 0 || xx > L.plotW) continue
    out.push(hairline(xx, s))
  }
  return out
}
