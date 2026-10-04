// 移植自 KanpanChart/Sources/KanpanChart/ChartRenderer+Sub.swift
//
// 副图（成交量、平滑异同、相对强弱、随机、动向、量差、持仓量、多空比 / 买卖比 / 基差）、
// 主图与副图的图例、画线层。Swift 是 ChartRenderer 的 extension，这里写成吃 renderer 的函数。

import type { IndicatorID } from '../indicator/ids'
import { guides as indicatorGuides, indicatorName, oiNoticeForEmptyPane } from '../indicator/ids'
import type { Layout, Pane } from './geometry'
import { candlePixels, snap, swiftRound, visibleRange, yOfValue } from './geometry'
import { fmtNum, fmtVol, toFixed } from './format'
import type { Hex } from './paint'
import { ChartFont, alpha, css, drawCentered, drawLeft, hairLine, textWidth } from './paint'
import type { ChartRenderer } from './renderer'
import { drawCompareLegend } from './renderer.compare'
import { drawOrderFlowLegend } from './renderer.orderflow'

type Extent = { lo: number; hi: number }

/** 副图内边：顶上留给图例，底下留一点呼吸。 */
export function inner(pane: Pane): Pane {
  const top = Math.min(pane.h * 0.4, pane.indicator === 'VOL' ? 30 : 28)
  const bottom = pane.indicator === 'VOL' ? 4 : 8
  return { indicator: pane.indicator, y: pane.y + top, h: Math.max(1, pane.h - top - bottom) }
}

const bounds = (r: ChartRenderer) => visibleRange(r.state.viewport.view, r.state.input.series)

export function drawSub(r: ChartRenderer, ctx: CanvasRenderingContext2D, pane: Pane, L: Layout, s: number, legend = true): void {
  const key = pane.indicator as IndicatorID | null
  if (!key) return
  const t = r.colors
  const { lo, hi } = bounds(r)
  hairLine(ctx, 0, L.W, pane.y, s, t.axis)

  const box = inner(pane)
  ctx.save()
  ctx.beginPath(); ctx.rect(0, box.y, L.plotW, box.h); ctx.clip()
  switch (key) {
    case 'VOL': subVol(r, ctx, box, L, lo, hi, s); break
    case 'MACD': subMacd(r, ctx, box, L, lo, hi, s); break
    case 'LSR': case 'TAKER': case 'BASIS': subExternal(r, ctx, box, L, lo, hi, key, s); break
    case 'OI': subOi(r, ctx, box, L, lo, hi, s); break
    case 'RSI': case 'SRSI': case 'KDJ': case 'ATR': case 'DMI': case 'CVD': subLines(r, ctx, box, L, lo, hi, key, s); break
    default: break
  }
  ctx.restore()
  drawSubAxis(r, ctx, key, box, L, lo, hi)
  if (legend) subLegend(r, ctx, pane, key, L.plotW)
}

function subExternal(r: ChartRenderer, ctx: CanvasRenderingContext2D, box: Pane, L: Layout, lo: number, hi: number, id: IndicatorID, s: number): void {
  const inp = r.state.input
  const values = r.displayed(id)?.lines[0] ?? []
  let any = false
  for (let i = lo; i <= hi; i++) if (i < values.length && Number.isFinite(values[i])) { any = true; break }
  if (!inp.externalSupported || !any) {
    const name = indicatorName(id)
    const text = !inp.externalSupported ? '当前线路不提供' + name : inp.external[id] == null ? name + '暂无数据' : '该时段暂无' + name
    drawLeft(ctx, text, 8, box.y + box.h / 2, ChartFont.notice, r.colors.dim)
    return
  }
  subLines(r, ctx, box, L, lo, hi, id, s)
}

function extent(arrs: number[][], lo: number, hi: number, guides: number[] = []): Extent {
  let mn = guides.length ? Math.min(...guides) : Infinity
  let mx = guides.length ? Math.max(...guides) : -Infinity
  for (const a of arrs) {
    if (!(a.length > lo)) continue
    const end = Math.min(hi, a.length - 1)
    for (let i = lo; i <= end; i++) {
      const v = a[i]
      if (!Number.isFinite(v)) continue
      if (v < mn) mn = v
      if (v > mx) mx = v
    }
  }
  if (!Number.isFinite(mn) || !Number.isFinite(mx)) return { lo: 0, hi: 1 }
  if (mn === mx) return { lo: mn - 0.5, hi: mx + 0.5 }
  return { lo: mn, hi: mx }
}

export function subExtent(r: ChartRenderer, key: IndicatorID, lo: number, hi: number): Extent {
  const value = r.displayed(key)
  const lines = value?.lines ?? []
  switch (key) {
    case 'VOL': return extent((r.outputVisible('VOL', lines.length) ? [r.state.input.series.volume] : []).concat(lines), lo, hi, [0])
    case 'MACD': return extent(lines.concat([value?.histogram ?? []]), lo, hi, [0])
    default: return extent(lines, lo, hi, key === 'RSI' ? [] : key === 'KDJ' ? [0, 100] : indicatorGuides(key))
  }
}

export function subCrosshairValue(r: ChartRenderer, y: number, pane: Pane): number {
  const key = pane.indicator as IndicatorID | null
  if (!key) return 0
  const b = bounds(r)
  const ext = subExtent(r, key, b.lo, b.hi), box = inner(pane)
  const fraction = Math.max(0, Math.min(1, (y - box.y) / box.h))
  return r.state.input.subInverted.includes(key) ? ext.lo + fraction * (ext.hi - ext.lo) : ext.hi - fraction * (ext.hi - ext.lo)
}

export function subCrosshairY(r: ChartRenderer, value: number, pane: Pane): number {
  const key = pane.indicator as IndicatorID | null
  if (!key) return pane.y
  const b = bounds(r)
  return subY(r, inner(pane), subExtent(r, key, b.lo, b.hi), value)
}

function drawSubAxis(r: ChartRenderer, ctx: CanvasRenderingContext2D, key: IndicatorID, box: Pane, L: Layout, lo: number, hi: number): void {
  const ext = subExtent(r, key, lo, hi)
  const fractions = box.h < 35 ? [0.5] : box.h < 60 ? [0, 1] : [0, 0.5, 1]
  const inverted = r.state.input.subInverted.includes(key)
  for (const fraction of fractions) {
    const value = inverted ? ext.lo + fraction * (ext.hi - ext.lo) : ext.hi - fraction * (ext.hi - ext.lo)
    const label = subValueText(r, value, key)
    const y = Math.min(box.y + box.h - 4, Math.max(box.y + 4, box.y + box.h * fraction))
    drawCentered(ctx, label, L.plotW + L.axisW / 2, y, ChartFont.axis, r.colors.dim)
  }
}

function subY(r: ChartRenderer, box: Pane, ext: Extent, v: number): number {
  const y = yOfValue(v, box, ext.lo, ext.hi)
  return box.indicator != null && r.state.input.subInverted.includes(box.indicator as IndicatorID) ? box.y * 2 + box.h - y : y
}

function poly(r: ChartRenderer, ctx: CanvasRenderingContext2D, box: Pane, ext: Extent, L: Layout, arr: number[], lo: number, hi: number, color: Hex, width = 1): void {
  const b = r.state.input.series
  ctx.strokeStyle = css(color)
  ctx.lineWidth = width
  ctx.beginPath()
  let on = false
  for (let i = lo; i <= hi && i < arr.length; i++) {
    if (!Number.isFinite(arr[i])) { on = false; continue }
    const px = r.x(b.time(i), L.plotW), py = subY(r, box, ext, arr[i])
    if (on) ctx.lineTo(px, py); else { ctx.moveTo(px, py); on = true }
  }
  ctx.stroke()
}

function subLines(r: ChartRenderer, ctx: CanvasRenderingContext2D, box: Pane, L: Layout, lo: number, hi: number, key: IndicatorID, s: number): void {
  const v = r.displayed(key)
  if (!v) return
  const t = r.colors, inp = r.state.input
  const pal = t.sub
  const ext = subExtent(r, key, lo, hi)
  const guides = key === 'RSI' ? [inp.rsiLower, inp.rsiUpper] : indicatorGuides(key)
  if (key === 'RSI') {
    const a = subY(r, box, ext, inp.rsiLower), b = subY(r, box, ext, inp.rsiUpper)
    ctx.fillStyle = css(alpha(t.band, '18'))
    ctx.fillRect(0, Math.min(a, b), L.plotW, Math.abs(b - a))
  }
  if (guides.length) {
    ctx.save()
    ctx.setLineDash([2 / s, 3 / s])
    for (const g of guides) {
      const y = subY(r, box, ext, g)
      if (y < box.y || y > box.y + box.h) continue
      hairLine(ctx, 0, L.plotW, y, s, t.grid)
    }
    ctx.restore()
  }
  v.lines.forEach((a, k) => poly(r, ctx, box, ext, L, a, lo, hi, pal[k % pal.length], 2 / s))
}

function subVol(r: ChartRenderer, ctx: CanvasRenderingContext2D, box: Pane, L: Layout, lo: number, hi: number, s: number): void {
  const b = r.state.input.series, t = r.colors
  const ext = subExtent(r, 'VOL', lo, hi)
  const bodyW = candlePixels(r.spacing(L.plotW), s).body / s
  const v = r.displayed('VOL')
  if (r.outputVisible('VOL', v?.lines.length ?? 0)) {
    const zero = subY(r, box, ext, 0)
    const up = css(t.up), down = css(t.down)
    for (let i = lo; i <= hi; i++) {
      // 坏量（NaN / ±inf）不画：算出来的矩形不是有限数，量轴区间（extent）也早就把它剔掉了，
      // 这里跟它同一口径（ChartRenderer+Sub.swift，审查 B·P3-4）。
      const volume = b.volume[i]
      if (!Number.isFinite(volume)) continue
      const xc = r.x(b.time(i), L.plotW)
      if (xc < -4 || xc > L.plotW + 4) continue
      const y = subY(r, box, ext, volume)
      // 量柱与蜡烛同色、不透明（原型的 40% 透明在白底上发灰，Swift 已改掉）。
      ctx.fillStyle = b.close[i] >= b.open[i] ? up : down
      ctx.fillRect(snap(xc - bodyW / 2, s), Math.min(y, zero), bodyW, Math.abs(zero - y))
    }
  }
  if (v) v.lines.forEach((a, k) => poly(r, ctx, box, ext, L, a, lo, hi, t.sub[k % t.sub.length], 2 / s))
}

function subMacd(r: ChartRenderer, ctx: CanvasRenderingContext2D, box: Pane, L: Layout, lo: number, hi: number, s: number): void {
  const v = r.displayed('MACD')
  const hist = v?.histogram
  if (!v || !hist || v.lines.length < 2) return
  const b = r.state.input.series, t = r.colors
  const e = subExtent(r, 'MACD', lo, hi)
  const zero = subY(r, box, e, 0)
  // 柱宽占格子的 2/3、落整像素；线宽 2 物理像素。
  const cell = r.spacing(L.plotW) * s
  const bw = Math.max(1, swiftRound(cell * 2 / 3)) / s
  const line = 2 / s
  for (let i = lo; i <= hi && i < hist.length; i++) {
    const v0 = hist[i]
    if (!Number.isFinite(v0)) continue
    const xc = r.x(b.time(i), L.plotW)
    const y = subY(r, box, e, v0)
    const prev = i > 0 ? hist[i - 1] : NaN
    // 比上一根小（在收缩）画实心，放大画空心：AICoin 的做法。
    const solid = Number.isFinite(prev) && v0 < prev
    const col = css(v0 >= 0 ? t.up : t.down)
    const top = snap(Math.min(y, zero), s)
    const rx = snap(xc - bw / 2, s), rw = bw, rh = Math.max(line, snap(Math.max(y, zero), s) - top)
    const sw = rw - line, sh = rh - line
    if (solid || sw <= 0 || sh <= 0) {
      ctx.fillStyle = col
      ctx.fillRect(rx, top, rw, rh)
    } else {
      ctx.strokeStyle = col
      ctx.lineWidth = line
      ctx.strokeRect(rx + line / 2, top + line / 2, sw, sh)
    }
  }
  hairLine(ctx, 0, L.plotW, zero, s, t.grid)
  poly(r, ctx, box, e, L, v.lines[0], lo, hi, t.sub[0], 2 / s)
  poly(r, ctx, box, e, L, v.lines[1], lo, hi, t.sub[1], 2 / s)
}

function subOi(r: ChartRenderer, ctx: CanvasRenderingContext2D, box: Pane, L: Layout, lo: number, hi: number, s: number): void {
  const t = r.colors, inp = r.state.input
  if (!r.outputVisible('OI', 0)) return
  const a = r.displayed('OI')?.lines[0] ?? []
  let has = false
  for (let i = lo; i <= hi && i < a.length; i++) if (Number.isFinite(a[i])) { has = true; break }
  if (!has) {
    drawLeft(ctx, oiNoticeForEmptyPane(inp.oiSupported, inp.oi != null), 8, box.y + box.h / 2, ChartFont.notice, t.dim)
    return
  }
  const b = inp.series
  const ext = subExtent(r, 'OI', lo, hi)
  ctx.beginPath()
  let started = false
  for (let i = lo; i <= hi && i < a.length; i++) {
    if (!Number.isFinite(a[i])) { started = false; continue }
    const px = r.x(b.time(i), L.plotW), py = subY(r, box, ext, a[i])
    if (started) ctx.lineTo(px, py); else { ctx.moveTo(px, py); started = true }
  }
  ctx.strokeStyle = css(t.oi)
  ctx.lineWidth = 2 / s
  ctx.stroke()
}

// ---------------------------------------------------------------- 图例

type Put = (text: string, color: Hex) => void

function putter(ctx: CanvasRenderingContext2D, plotW: number, start: { x: number; y: number }, wrap: number, limit: () => number): { put: Put; pos: { x: number; y: number } } {
  const pos = { ...start }
  const put: Put = (text, color) => {
    if (text.includes('NaN') || text.includes('--')) return
    const w = textWidth(text, ChartFont.axis)
    if (pos.x + w > plotW - 4) { pos.x = 8; pos.y += wrap }
    if (!(pos.y < limit())) return
    drawLeft(ctx, text, pos.x, pos.y, ChartFont.axis, color)
    pos.x += w + 8
  }
  return { put, pos }
}

export function drawLegend(r: ChartRenderer, ctx: CanvasRenderingContext2D, pane: Pane, L: Layout): void {
  const inp = r.state.input
  if (inp.percentAxis) { drawCompareLegend(r, ctx, pane, L); return }
  const t = r.colors
  const i = r.legendIndex
  const p = inp.decimals
  const { put, pos } = putter(ctx, L.plotW, { x: 8, y: pane.y + 9 }, 12, () => pane.y + Math.min(pane.h - 6, r.mainLegendInset(L.plotW) - 4))
  for (const id of inp.overlays) {
    const v = r.displayed(id)
    if (!v) continue
    switch (id) {
      case 'MA': case 'EMA':
        r.params(id).forEach((n, k) => {
          if (k < v.lines.length && r.outputVisible(id, k)) put(`${indicatorName(id)}${n} ` + r.indicatorNumber(r.reading(v.lines[k]), p), r.indicatorColor(id, k))
        })
        break
      case 'BOLL': {
        if (v.lines.length < 3) break
        const at = (k: number) => (i >= 0 && i < v.lines[k].length ? v.lines[k][i] : NaN)
        put('上轨 ' + fmtNum(at(1), p), t.band)
        put('中轨 ' + fmtNum(at(0), p), t.amber)
        put('下轨 ' + fmtNum(at(2), p), t.band)
        break
      }
      case 'VWAP': {
        const a = v.lines[0]
        if (!a || !r.outputVisible(id, 0)) break
        put('当日均价 ' + r.indicatorNumber(r.reading(a), p), r.indicatorColor(id, 0))
        break
      }
      case 'ST': case 'SAR': {
        const a = v.lines[0]
        if (!a || !r.outputVisible(id, 0)) break
        const d = v.dir ? r.reading(v.dir) : NaN
        put(indicatorName(id) + ' ' + r.indicatorNumber(r.reading(a), p), d > 0 ? t.up : t.down)
        break
      }
      default: break
    }
  }
  const chip = sinceChangeChip(r)
  if (chip) put(chip.text, chip.color)
  drawOrderFlowLegend(r, ctx, pane, L, pos.x, pos.y)
}

/** 十字线停在某根时，从那根收盘到最新收盘的涨跌（「至今」）。 */
export function sinceChangeChip(r: ChartRenderer): { text: string; color: Hex } | null {
  const st = r.state
  if (!st.input.options.sinceChange || !st.overlay.crosshair) return null
  const b = st.input.series
  const i = r.legendIndex
  if (!(b.count > 0 && i >= 0 && i < b.count)) return null
  const from = b.close[i], to = b.close[b.count - 1]
  if (!Number.isFinite(from) || !Number.isFinite(to) || from === 0) return null
  const pct = (to / from - 1) * 100
  return { text: '至今 ' + (pct >= 0 ? '+' : '') + toFixed(pct, 2) + '%', color: pct >= 0 ? r.colors.up : r.colors.down }
}

export function drawLegends(r: ChartRenderer, ctx: CanvasRenderingContext2D, L: Layout): void {
  for (let k = 1; k < L.panes.length; k++) {
    const key = L.panes[k].indicator as IndicatorID | null
    if (!key) continue
    subLegend(r, ctx, L.panes[k], key, L.plotW)
  }
  drawLegend(r, ctx, L.main, L)
}

function subLegend(r: ChartRenderer, ctx: CanvasRenderingContext2D, pane: Pane, key: IndicatorID, plotW: number): void {
  const t = r.colors, inp = r.state.input
  const i = r.legendIndex
  const pal = t.sub
  const { put } = putter(ctx, plotW, { x: 8, y: pane.y + 8 }, 11, () => pane.y + (key === 'VOL' ? 24 : 26))
  const v = r.displayed(key)
  const at = (a: number[]) => r.reading(a)
  const joined = (id: IndicatorID) => r.params(id).map(String).join(',')
  switch (key) {
    case 'VOL':
      if (r.outputVisible('VOL', v?.lines.length ?? 0)) put('成交量 ' + r.amountNumber(inp.series.volume[i]), t.text)
      if (v) r.params('VOL').forEach((n, k) => { if (k < v.lines.length) put(`均量${n} ` + r.amountNumber(at(v.lines[k])), pal[k % pal.length]) })
      break
    case 'MACD': {
      put('平滑异同(' + joined('MACD') + ')', t.dim)
      const hist = v?.histogram
      if (!v || !hist || v.lines.length < 2) break
      put('差值 ' + r.indicatorNumber(at(v.lines[0]), inp.decimals), pal[0])
      put('信号 ' + r.indicatorNumber(at(v.lines[1]), inp.decimals), pal[1])
      const h = at(hist)
      put('柱值 ' + r.indicatorNumber(h, inp.decimals), h >= 0 ? t.up : t.down)
      break
    }
    case 'RSI':
      put(`强弱(${Math.trunc(inp.rsiUpper)}/${Math.trunc(inp.rsiLower)})`, t.dim)
      if (!v) break
      r.params('RSI').forEach((n, k) => { if (k < v.lines.length) put(`${n} ` + r.indicatorNumber(at(v.lines[k]), 1), pal[k % pal.length]) })
      break
    case 'KDJ':
      put('随机(' + joined('KDJ') + ')', t.dim)
      if (!v || v.lines.length < 3) break
      put('快线 ' + r.indicatorNumber(at(v.lines[0]), 1), pal[0])
      put('慢线 ' + r.indicatorNumber(at(v.lines[1]), 1), pal[1])
      put('敏感线 ' + r.indicatorNumber(at(v.lines[2]), 1), pal[2])
      break
    case 'SRSI':
      put('随机强弱', t.dim)
      if (!v || v.lines.length < 2) break
      put('快线 ' + r.indicatorNumber(at(v.lines[0]), 1), pal[0])
      put('慢线 ' + r.indicatorNumber(at(v.lines[1]), 1), pal[1])
      break
    case 'ATR': {
      const a = v?.lines[0]
      if (!a) break
      put(`真实波幅${r.params('ATR')[0]} ` + fmtNum(at(a), inp.decimals), pal[0])
      break
    }
    case 'LSR': case 'TAKER': case 'BASIS': {
      put(indicatorName(key), t.dim)
      const values = v?.lines[0]
      if (values && Number.isFinite(r.reading(values))) put(subValueText(r, r.reading(values), key), r.indicatorColor(key, 0))
      break
    }
    case 'DMI':
      put('动向(' + joined('DMI') + ')', t.dim)
      if (!v || v.lines.length < 3) break
      put('多头动向 ' + r.indicatorNumber(at(v.lines[0]), 1), pal[0])
      put('空头动向 ' + r.indicatorNumber(at(v.lines[1]), 1), pal[1])
      put('趋势强度 ' + r.indicatorNumber(at(v.lines[2]), 1), pal[2])
      break
    case 'CVD': {
      put(indicatorName(key), t.dim)
      const a = v?.lines[0]
      const x = a ? at(a) : NaN
      if (Number.isFinite(x)) put(r.amountNumber(x), x >= 0 ? t.up : t.down)
      break
    }
    case 'OI': {
      const a = v?.lines[0]
      const x = a ? at(a) : NaN
      // 「--」会被 put 滤掉，和 Swift 一样：没有读数时整条不画。
      put('持仓量 ' + (Number.isFinite(x) ? r.amountNumber(x) : '--'), t.oi)
      break
    }
    default: break
  }
}

export function subValueText(r: ChartRenderer, value: number, indicator: IndicatorID | string): string {
  if (indicator === 'BASIS') return fmtNum(value, 3) + '%'
  if (indicator === 'VOL' || indicator === 'OI' || indicator === 'CVD') return fmtVol(value)
  return fmtNum(value, indicator === 'MACD' || indicator === 'ATR' ? r.state.input.decimals : 2)
}

export function subAxisLabels(r: ChartRenderer, id: IndicatorID): string[] {
  const b = bounds(r)
  const e = subExtent(r, id, b.lo, b.hi)
  return [e.lo, e.hi].map(v => subValueText(r, v, id))
}
