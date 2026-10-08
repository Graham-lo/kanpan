// 2026-10-08 行情页整改（手机网页跟 iOS）：主图 / 副图 / 对比图例恒为一行（全称 → 短称 → 「+N」），
// 主图叠加线超过六条时非焦点线淡出。移植自 KanpanChart/Tests/KanpanChartTests/DrawPenLegendFocusTests.swift
// 的图例与焦点两节（笔那一节是画线组的事）。
import { describe, expect, it } from 'vitest'
import type { IndicatorID } from '../src/m/indicator/ids'
import { AICoinBehavior, Layout, ViewMath, defaultChartOptions, priceTransform } from '../src/m/chart/geometry'
import { BarSeries } from '../src/m/chart/series'
import type { ChartState } from '../src/m/chart/state'
import { makeState, withInput, withOverlay } from '../src/m/chart/state'
import { ChartFont, textWidth } from '../src/m/chart/paint'
import { ChartRenderer, overlayKey } from '../src/m/chart/renderer'
import { mainLegendItems, subLegendItems } from '../src/m/chart/renderer.sub'
import { LegendFit, legendItem } from '../src/m/chart/legendFit'

const W = 402, H = 680

function series(n = 240): BarSeries {
  const close = Array.from({ length: n }, (_, i) => 100 + 8 * Math.sin(i / 9) + i * 0.05)
  const open = close.map((c, i) => (i ? close[i - 1] : c))
  return new BarSeries({
    symbol: 'BTCUSDT', interval: '1h', t0: 1_700_000_000_000, step: 3_600_000,
    open, high: close.map((c, i) => Math.max(c, open[i]) + 0.6), low: close.map((c, i) => Math.min(c, open[i]) - 0.6),
    close, volume: close.map((_, i) => 1000 + (i % 17) * 40),
  })
}

function state(overlays: IndicatorID[], subs: IndicatorID[] = ['VOL'], params: Partial<Record<IndicatorID, number[]>> = {}): ChartState {
  const b = series()
  const L = new Layout(W, H, subs)
  return makeState({
    series: b, symbol: { symbol: 'BTCUSDT', base: 'BTC', priceDecimals: 2 },
    view: ViewMath.reset(b, L.plotW, AICoinBehavior.initialSpacing),
    price: priceTransform('linear'), subs, overlays, params, tzOffset: 480, decimals: 2,
    options: defaultChartOptions(), nowMs: b.lastTime + 1_800_000,
  })
}

const MA6 = [5, 10, 20, 30, 60, 120]
const axis = (s: string): number => textWidth(s, ChartFont.axis)

describe('单行图例', () => {
  it('放得下用全称，放不下换短称，再放不下收「+N」；读不出数的段剔掉', () => {
    const measure = (s: string) => [...s].length * 10
    const items = [legendItem('MA5 100', 'MA 100', '#000000'), legendItem('MA10 101', '101', '#000000'),
      legendItem('MA20 102', '102', '#000000'), legendItem('MA30 --', '--', '#000000')]
    const full = LegendFit.fit(items, 1000, measure)
    expect(full.more).toBe(0)
    expect(full.texts.map(t => t.text)).toEqual(['MA5 100', 'MA10 101', 'MA20 102'])
    const short = LegendFit.fit(items, 160, measure)
    expect(short.more).toBe(0)
    expect(short.texts.map(t => t.text)).toEqual(['MA 100', '101', '102'])
    const tight = LegendFit.fit(items, 120, measure)
    expect(tight.texts.map(t => t.text)).toEqual(['MA 100'])
    expect(tight.more).toBe(2)
    const total = tight.texts.reduce((a, t) => a + measure(t.text) + LegendFit.gap, 0) + measure(LegendFit.moreText(tight.more))
    expect(total).toBeLessThanOrEqual(120)
  })

  it('主图图例恒为一行：叠加再多（自适应开着）内缩也不长高；十字线开着也一样', () => {
    let st = state(['MA', 'EMA', 'BOLL', 'VWAP'], ['VOL'], { MA: MA6 })
    st = withInput(st, { options: { ...st.input.options, adaptiveIndicators: true } })
    const r = new ChartRenderer(st)
    expect(r.mainLegendInset(300)).toBe(AICoinBehavior.mainTopInset)
    const items = mainLegendItems(r)
    expect(items.length).toBeGreaterThanOrEqual(10)
    expect(LegendFit.fit(items, 300, axis).more).toBeGreaterThan(0)
    const rc = new ChartRenderer(withOverlay(st, { crosshair: { index: 40, pane: null, t: null, price: null } }))
    expect(rc.mainLegendInset(300)).toBe(AICoinBehavior.mainTopInset)
    expect(mainLegendItems(rc).length).toBe(items.length)
  })

  it('短称去参数、留读数：均线第一段留名，后面只剩数；副图同理', () => {
    const r = new ChartRenderer(state(['MA'], ['MACD', 'VOL'], { MA: [5, 10] }))
    const main = mainLegendItems(r)
    expect(main[0].full.startsWith('MA5 ')).toBe(true)
    expect(main[0].short.startsWith('MA ')).toBe(true)
    expect(main[1].full.startsWith('MA10 ')).toBe(true)
    expect(main[1].short.includes('MA')).toBe(false)
    const macd = subLegendItems(r, 'MACD')
    expect(macd[0].full.startsWith('MACD(')).toBe(true)
    expect(macd[0].short).toBe('MACD')
    const vol = subLegendItems(r, 'VOL')
    expect(vol[0].full.startsWith('成交量 ')).toBe(true)
    expect(vol[0].short.startsWith('量 ')).toBe(true)
  })

  it('对比图例单行：八只对比内缩也只有一行', () => {
    const st = state([])
    const s = st.input.series
    const compare = Array.from({ length: 8 }, (_, k) => ({
      key: `binance/usd_m/C${k}USDT`, name: `COIN${k}`, color: '#FFB400' as const,
      open: Array.from(s.open), close: Array.from(s.close),
    }))
    const r = new ChartRenderer(withInput(st, { percentAxis: true, compare }))
    expect(r.mainLegendInset(300)).toBe(AICoinBehavior.mainTopInset)
  })
})

describe('叠加焦点', () => {
  it('六条以内一条都不淡', () => {
    const r = new ChartRenderer(state(['MA'], ['VOL'], { MA: MA6 }))
    expect(r.overlayLineKeys().length).toBe(6)
    expect(r.overlayFocus()).toBeNull()
  })

  it('超过六条：默认前六条，改过的那把优先，十字线读的那条最优先', () => {
    const st = state(['MA', 'EMA'], ['VOL'], { MA: MA6, EMA: [7, 25] })
    const r = new ChartRenderer(st)
    const keys = r.overlayLineKeys()
    expect(keys.length).toBe(8)
    expect(r.overlayFocus()).toEqual(new Set(keys.slice(0, 6).map(overlayKey)))

    // 改了指数均线的参数：焦点换到它那两条
    const edited = withInput(st, { params: { ...st.input.params, EMA: [7, 30] } })
    r.state = edited
    expect(r.overlayEdited).toBe('EMA')
    const ema = new Set(['EMA:0', 'EMA:1'])
    expect(r.overlayFocus()).toEqual(ema)

    // 十字线停在主图：焦点是读数离十字线价格最近的那一条
    const index = st.input.series.count - 5
    const target = r.displayed('MA')!.lines[3][index]
    expect(Number.isFinite(target)).toBe(true)
    r.state = withOverlay(edited, { crosshair: { index, pane: null, t: null, price: target } })
    expect(r.overlayFocus()).toEqual(new Set(['MA:3']))

    // 十字线在副图上不算读主图的线
    r.state = withOverlay(edited, { crosshair: { index, pane: 'VOL', t: null, price: target } })
    expect(r.overlayFocus()).toEqual(ema)
  })

  it('一次换整套布局不算编辑了某一把', () => {
    const a = state([])
    expect(ChartRenderer.editedOverlay(a, withInput(a, { overlays: ['MA', 'EMA'] }))).toBeNull()
    expect(ChartRenderer.editedOverlay(a, withInput(a, { overlays: ['VWAP'] }))).toBe('VWAP')
  })
})
