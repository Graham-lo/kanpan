// 渲染器上的数值部分，移植自 KanpanChart/Tests/KanpanChartTests：
//   AxisWidthTests（右轴宽度按内容算）、ExternalChartTests（外部指标与盘口梯的几何）、
//   GeometryTableTests.table 与 PixelBoundaryTests（A3.2 / A3.10，走 renderer.probe）、
//   ChartAxisFreezeTests 里的纯函数那一半（新 K 线到货时 reconcile 跟不跟）。
// 夹具直接读 iOS 那边的定版快照（KanpanChart/Tests/KanpanChartTests/Fixtures/snapshot.json）。
// 注意：node 里没有 canvas，paint.textWidth 走「数字 0.6em、其余 0.55em」的近似字宽；
// 轴宽类断言只比关系（贴内容、位数决定宽度、胶囊不出右缘），不比 iOS 上的绝对像素。
import { describe, expect, it } from 'vitest'
// @ts-expect-error Web 的 tsconfig 不带 @types/node，这里只在 vitest（node 环境）里用
import { readFileSync } from 'node:fs'
import type { IndicatorID } from '../src/m/indicator/ids'
import type { ChartOptions, PriceRange } from '../src/m/chart/geometry'
import {
  AICoinBehavior, Layout, ViewMath, ViewWindow, daysFromCivil, defaultChartOptions, priceTransform, reconcile, reconcileBeforeUpsert,
} from '../src/m/chart/geometry'
import { fmtNum } from '../src/m/chart/format'
import { BarSeries, ExternalSeries, bar } from '../src/m/chart/series'
import type { Interval } from '../src/m/chart/series'
import type { ChartState } from '../src/m/chart/state'
import { changedLayers, makeOrderBook, makeState, withInput, withOverlay } from '../src/m/chart/state'
import { ChartFont, textWidth } from '../src/m/chart/paint'
import { ChartRenderer } from '../src/m/chart/renderer'
import { drawSub, subAxisLabels, subValueText } from '../src/m/chart/renderer.sub'
import { candleXs, probe, verticalHairlineXs } from '../src/m/chart/renderer.probe'

// ------------------------------------------------------------------ 夹具（EvidenceSupport.swift 的 Fixture）

const fx = JSON.parse(readFileSync(new URL('../../KanpanChart/Tests/KanpanChartTests/Fixtures/snapshot.json', import.meta.url), 'utf8')) as {
  symbol: string; interval: string; t0: number; step: number; p: number
  open: number[]; high: number[]; low: number[]; close: number[]; volume: number[]
  meta: { base: string; quote: string; pricePrecision: number; tickSize: number }
}

/** AxisWidthTests.series：把定版快照整条按倍数搬到别的价位上，用来模拟别的品种。 */
function scaledSeries(factor: number, symbol: string): BarSeries {
  const f = (xs: number[]) => xs.map(x => x * factor)
  return new BarSeries({
    symbol, interval: fx.interval as Interval, t0: fx.t0, step: fx.step,
    open: f(fx.open), high: f(fx.high), low: f(fx.low), close: f(fx.close), volume: fx.volume.slice(),
  })
}

const SIZE = { W: 402, H: 520 }

/** AxisWidthTests.renderer：线性价格轴、UTC、nowMs = 末根 + 30 分钟。 */
function axisRenderer(o: { factor?: number; decimals?: number; symbol?: string; subs?: IndicatorID[]; options?: ChartOptions } = {}): ChartRenderer {
  const symbol = o.symbol ?? 'BTCUSDT', decimals = o.decimals ?? 2, subs = o.subs ?? ['VOL', 'MACD']
  const b = scaledSeries(o.factor ?? 1, symbol)
  const L = new Layout(SIZE.W, SIZE.H, subs)
  return new ChartRenderer(makeState({
    series: b, symbol: { symbol, base: symbol, priceDecimals: decimals },
    view: ViewMath.reset(b, L.plotW, AICoinBehavior.initialSpacing),
    price: priceTransform('linear'), subs, tzOffset: 0, decimals,
    options: o.options ?? defaultChartOptions(), nowMs: b.lastTime + 1_800_000,
  }))
}

const FACTORS: [number, number][] = [[1, 2], [1.234e-5 / 80_000, 8], [420 / 80_000, 2]]

// ------------------------------------------------------------------ AxisWidthTests

describe('右轴宽度按内容算（AxisWidthTests）', () => {
  it('priceReadoutsUseTickSize：图表价格与价差读数按给定位数，百分比保留独立口径', () => {
    // 位数由 SymbolInfo 的报价步长推出来那一半网页里没有（网页的 SymbolInfo 直接给 priceDecimals），这里直接喂 Swift 推出来的位数。
    const cases: [string, number, number][] = [
      ['SNDKUSDT', 1774.23, 2], ['MUUSDT', 1045.4, 2], ['BTCUSDT', 76800.0, 1], ['1000SATSUSDT', 0.00001234, 8],
    ]
    for (const [symbol, price, digits] of cases) {
      const series = scaledSeries(price / 80_000, symbol)
      const r = new ChartRenderer(makeState({
        series, symbol: { symbol, base: symbol, priceDecimals: digits }, view: new ViewWindow(series.lastTime, 3_600_000),
      }))
      expect(r.state.input.decimals).toBe(digits)
      const range = r.priceRange(SIZE.W, SIZE.H)
      expect(r.axisLabel(price, range)).toBe(fmtNum(price, digits))
      expect(subValueText(r, price / 100, 'MACD')).toBe(fmtNum(price / 100, digits))
      expect(subValueText(r, price / 100, 'ATR')).toBe(fmtNum(price / 100, digits))
      expect(subValueText(r, 54.321, 'RSI')).toBe('54.32')
    }
  })

  it('hugsContent：轴宽贴着最宽的那条刻度走', () => {
    for (const [factor, decimals] of FACTORS) {
      const r = axisRenderer({ factor, decimals })
      const L = r.layout(SIZE.W, SIZE.H)
      const range = r.priceRange(SIZE.W, SIZE.H)
      let labels = [range.lo, range.hi].map(p => r.axisLabel(p, range))
      for (const pane of L.panes.slice(1)) if (pane.indicator) labels = labels.concat(subAxisLabels(r, pane.indicator as IndicatorID))
      const widest = Math.max(0, ...labels.map(l => textWidth(l, ChartFont.axis)))
      expect(Math.abs(L.axisW - (Math.ceil(widest) + 2 * AICoinBehavior.axisLabelPadding)),
        `刻度 ${labels} 量出来 ${widest}，轴却是 ${L.axisW}`).toBeLessThan(0.001)
    }
  })

  it('stepsFollowDigits：位数决定宽度，数字本身不决定', () => {
    const btc = axisRenderer().layout(SIZE.W, SIZE.H).axisW
    const stock = axisRenderer({ factor: 420 / 80_000 }).layout(SIZE.W, SIZE.H).axisW
    const shib = axisRenderer({ factor: 1.234e-5 / 80_000, decimals: 8 }).layout(SIZE.W, SIZE.H).axisW
    expect(stock < btc && btc < shib, `三位数 ${stock} / 五位数 ${btc} / 八位小数 ${shib}`).toBe(true)
    const a = axisRenderer({ factor: 1 }).layout(SIZE.W, SIZE.H).axisW
    const b = axisRenderer({ factor: 1.0001 }).layout(SIZE.W, SIZE.H).axisW
    expect(a, `同位数换了数字，轴宽从 ${a} 变成 ${b}`).toBe(b)
    expect(new ChartRenderer(axisRenderer().state).axisWidthTemplate('81,234.56K')).toBe('00,000.00K')
  })

  it('chipsStayInside：右轴上的胶囊不出右缘', () => {
    for (const [factor, decimals] of FACTORS) {
      const r = axisRenderer({ factor, decimals, options: { ...defaultChartOptions(), countdown: true } })
      const L = r.layout(SIZE.W, SIZE.H)
      const range = r.priceRange(SIZE.W, SIZE.H)
      const close = r.state.input.series.close
      const label = r.axisLabel(close[close.length - 1] ?? 0, range)
      const chip = r.axisChip(L, label)
      expect(chip.x).toBeGreaterThanOrEqual(L.plotW)
      expect(chip.x + chip.w, `最新价胶囊右缘 ${chip.x + chip.w} 越过了 ${L.W}`).toBeLessThanOrEqual(L.W - 1)
      expect(chip.w, `${label} 被胶囊裁掉了`).toBeGreaterThanOrEqual(textWidth(label, ChartFont.axis))
      const stamp = r.countdownTemplate()
      expect(stamp).not.toBeNull()
      const clock = r.axisChip(L, stamp!, ChartFont.tiny, chip.w)
      expect(clock.x + clock.w, `倒计时 ${stamp} 右缘 ${clock.x + clock.w} 越过了 ${L.W}`).toBeLessThanOrEqual(L.W - 1)
      expect(clock.w, `倒计时 ${stamp} 被裁掉了`).toBeGreaterThanOrEqual(textWidth(stamp!, ChartFont.tiny))
    }
  })

  it('countdownCostsNothingWhenOff：倒计时关着就不为它留地方', () => {
    const off = axisRenderer({ factor: 420 / 80_000, options: defaultChartOptions() }).layout(SIZE.W, SIZE.H).axisW
    const withIt = axisRenderer({ factor: 420 / 80_000, options: { ...defaultChartOptions(), countdown: true } }).layout(SIZE.W, SIZE.H).axisW
    expect(off).toBeLessThanOrEqual(withIt)
    expect(off).toBe(axisRenderer({ factor: 420 / 80_000 }).layout(SIZE.W, SIZE.H).axisW)
  })
})

// ------------------------------------------------------------------ ExternalChartTests

/** 只记 fillRect 与当时 globalAlpha 的假画布，替代 Swift 那张 402×520 的位图。 */
function fakeContext() {
  const rects: { x: number; y: number; w: number; h: number; alpha: number }[] = []
  const ctx = {
    globalAlpha: 1, fillStyle: '',
    save() {}, restore() {}, beginPath() {}, rect() {}, clip() {},
    fillRect(x: number, y: number, w: number, h: number) { rects.push({ x, y, w, h, alpha: ctx.globalAlpha }) },
  }
  return { ctx: ctx as unknown as CanvasRenderingContext2D, rects }
}

describe('外部指标和盘口绘制（ExternalChartTests）', () => {
  it('inputRefresh：只更新外部指标会更新曲线与基差百分比', () => {
    const r = axisRenderer({ subs: ['LSR', 'TAKER', 'BASIS'] })
    const bars = r.state.input.series
    const a = new ExternalSeries({ t0: bars.t0, step: bars.step, columns: [Array(bars.count).fill(-0.03)] })
    r.state = withInput(r.state, { external: { BASIS: a } })
    expect(r.displayed('BASIS')?.lines[0]?.at(-1)).toBe(-0.03)
    expect(subValueText(r, -0.03, 'BASIS')).toBe('-0.030%')
    const b = new ExternalSeries({ t0: bars.t0, step: bars.step, columns: [Array(bars.count).fill(0.02)] })
    r.state = withInput(r.state, { external: { BASIS: b } })
    expect(r.displayed('BASIS')?.lines[0]?.at(-1)).toBe(0.02)
  })

  it('depthGeometry：盘口只刷新实时层，不改变布局、轴宽和价格范围', () => {
    const r = axisRenderer()
    const old = r.state
    const layout = r.layout(SIZE.W, SIZE.H), range = r.priceRange(SIZE.W, SIZE.H)
    const price = old.input.series.close[old.input.series.count - 1]
    r.state = withOverlay(old, {
      depth: makeOrderBook(old.input.symbol.symbol, old.input.series.lastTime,
        [{ price: price - 0.1, quantity: 10 }], [{ price: price + 0.1, quantity: 20 }]),
    })
    const L2 = r.layout(SIZE.W, SIZE.H)
    expect(L2.axisW).toBe(layout.axisW)
    expect(L2.plotW).toBe(layout.plotW)
    expect(L2.panes).toEqual(layout.panes)
    expect(r.priceRange(SIZE.W, SIZE.H)).toEqual(range)
    // Swift 的 ChartView.changed == .live；网页的分层是 输入 / 视野 / 叠层，盘口只落在叠层。
    expect(changedLayers(old, r.state)).toEqual({ input: false, viewport: false, overlay: true })
  })

  it('fixedDepthLadder：密集十档开方缩放，极小挂单至少两点宽', () => {
    const r = axisRenderer()
    const s0 = r.state, series = s0.input.series
    const price = series.close[series.count - 1]
    const book = (bids: [number, number][], asks: [number, number][]) => makeOrderBook(s0.input.symbol.symbol, series.lastTime,
      bids.map(([p, q]) => ({ price: p, quantity: q })), asks.map(([p, q]) => ({ price: p, quantity: q })))
    r.state = withOverlay(s0, {
      depth: book([1, 2, 3, 4, 5].map(k => [price - k * 0.1, k === 1 ? 0.000001 : k]), [1, 2, 3, 4, 5].map(k => [price + k * 0.1, k + 5])),
    })
    const layout = r.layout(SIZE.W, SIZE.H)
    const range: PriceRange = { lo: price - 1_000, hi: price + 1_000, base: price, inverted: false }
    const rows = r.depthRows(layout.main, range, layout)
    expect(rows.length).toBe(10)
    expect(rows.slice(0, 5).every(x => x.color === r.state.input.colors.down)).toBe(true)
    expect(rows.slice(5).every(x => x.color === r.state.input.colors.up)).toBe(true)
    expect(rows.every(x => x.frame.h === 6 && x.frame.x + x.frame.w === layout.plotW)).toBe(true)
    expect(Math.max(...rows.map(x => x.frame.w))).toBe(64)
    expect(rows[5].frame.w).toBe(2)
    expect(rows.every(x => x.frame.w >= 2)).toBe(true)
    expect(Math.abs(rows[6].frame.w - 64 * Math.sqrt(2 / 10))).toBeLessThan(0.001)
    expect(Math.abs(rows[4].frame.w - 64 * Math.sqrt(6 / 10))).toBeLessThan(0.001)
    for (let i = 1; i < rows.length; i++) expect(rows[i].frame.y - (rows[i - 1].frame.y + rows[i - 1].frame.h)).toBe(1)
    expect(Math.abs((rows[4].frame.y + rows[4].frame.h + rows[5].frame.y) / 2 - layout.main.h / 2)).toBeLessThan(0.001)

    // Swift 直接数位图里 alpha ≥ 130 的像素（> 1500）；这里数假画布上填了多少面积、用的透明度够不够。
    const { ctx, rects } = fakeContext()
    expect(r.drawDepth(ctx, layout.main, range, layout)).toBe(10)
    expect(rects.every(x => x.alpha * 255 >= 130)).toBe(true)
    expect(rects.reduce((a, x) => a + x.w * x.h, 0)).toBeGreaterThan(1_500)

    for (const edge of [price - 20_000, price + 20_000]) {
      const outside: PriceRange = { lo: edge, hi: edge + 1_000, base: price, inverted: false }
      const clamped = r.depthRows(layout.main, outside, layout)
      expect(clamped.length).toBe(10)
      expect(clamped.every(x => x.frame.y >= layout.main.y && x.frame.y + x.frame.h <= layout.main.y + layout.main.h)).toBe(true)
    }
    r.state = withOverlay(r.state, { depth: book([[price - 0.1, 0]], [[price + 0.1, 1]]) })
    expect(r.depthRows(layout.main, range, layout).length, '零数量和缺档不能被两点下限画成挂单').toBe(1)
    r.state = withOverlay(r.state, { depth: null })
    expect(r.depthRows(layout.main, range, layout)).toEqual([])
  })
})

// ------------------------------------------------------------------ GeometryTableTests / PixelBoundaryTests

/** EvidenceSupport.swift 的 Evidence：叠加 MA、副图 MACD + RSI、UTC、视野 = ViewMath.reset(initialSpacing)。 */
const DEVICES = [
  { id: 'se', w: 375, h: 667, scale: 2 }, { id: 'mini', w: 375, h: 812, scale: 3 },
  { id: 'std', w: 393, h: 852, scale: 3 }, { id: 'pro', w: 402, h: 874, scale: 3 },
  { id: 'air', w: 420, h: 912, scale: 3 }, { id: 'plus', w: 430, h: 932, scale: 3 },
  { id: 'max', w: 440, h: 956, scale: 3 }, { id: 'ipad', w: 744, h: 1133, scale: 2 },
]
function evidenceState(W: number, H: number): ChartState {
  const series = scaledSeries(1, fx.symbol)
  const subs: IndicatorID[] = ['MACD', 'RSI']
  const L = new Layout(W, H, subs)
  return makeState({
    series, symbol: { symbol: fx.symbol, base: fx.meta.base, priceDecimals: fx.p },
    view: ViewMath.reset(series, L.plotW, AICoinBehavior.initialSpacing), overlays: ['MA'], subs, tzOffset: 0,
  })
}
const isIntegral = (v: number) => Math.abs(v - Math.round(v)) < 1e-9

describe('A3.2 几何量化 / A3.10 像素边界（GeometryTableTests / PixelBoundaryTests）', () => {
  it('table：AICoin 底座，时间轴高 17、实体与影线都有宽度', () => {
    const dev = DEVICES.find(d => d.id === 'pro')!
    const actual = probe(new ChartRenderer(evidenceState(dev.w, dev.h)), dev.w, dev.h, dev.scale)
    expect(actual.bodyW > 0 && actual.wickW > 0).toBe(true)
    expect(actual.timeH).toBe(17)
  })

  it('candleEdges：8 机型实体与影线左缘 x·scale 为整数', () => {
    let count = 0
    for (const dev of DEVICES) {
      const r = new ChartRenderer(evidenceState(dev.w, dev.h))
      const xs = candleXs(r, dev.w, dev.h, dev.scale)
      expect(xs.length, `${dev.id}/aicoin 一根都没画`).toBeGreaterThan(0)
      for (const c of xs) {
        expect(isIntegral(c.bodyLeft * dev.scale), `${dev.id}/aicoin 第 ${c.index} 根实体左缘 ${c.bodyLeft}`).toBe(true)
        expect(isIntegral(c.wickLeft * dev.scale), `${dev.id}/aicoin 第 ${c.index} 根影线左缘 ${c.wickLeft}`).toBe(true)
        expect(isIntegral(c.wickHair * dev.scale - 0.5), `${dev.id}/aicoin 第 ${c.index} 根影线中线 ${c.wickHair}`).toBe(true)
        count++
      }
    }
    expect(count).toBeGreaterThan(0)
  })

  it('verticalHairlines：竖向细线（价格轴分隔 + 时间网格）中线压在半像素上', () => {
    for (const dev of DEVICES) {
      for (const grid of ['off', 'on'] as const) {
        const st = evidenceState(dev.w, dev.h)
        const r = new ChartRenderer(withInput(st, { options: { ...st.input.options, grid } }))
        const xs = verticalHairlineXs(r, dev.w, dev.h, dev.scale)
        expect(xs.length).toBeGreaterThan(0)
        for (const x of xs) expect(isIntegral(x * dev.scale - 0.5), `${dev.id}/aicoin 竖线 ${x} 没落在像素中线上`).toBe(true)
      }
    }
  })
})

// ------------------------------------------------------------------ ChartAxisFreezeTests（纯函数那一半）

/** ChartAxisFreezeTests.freezeState：LCG 种子 20_260_920、BTCUSDT 1m、600 根、起价 62_000。 */
function freezeSeries(count = 600): BarSeries {
  let seed = 20_260_920n
  const M = (1n << 64n) - 1n
  const next = () => {
    seed = (seed * 6_364_136_223_846_793_005n + 1_442_695_040_888_963_407n) & M
    return Number((seed >> 33n) % 10_000n) / 10_000
  }
  const o: number[] = [], h: number[] = [], l: number[] = [], c: number[] = [], v: number[] = []
  let p = 62_000
  for (let i = 0; i < count; i++) {
    const open = p
    const close = open * (1 + (next() - 0.5) * 0.01)
    o.push(open)
    h.push(Math.max(open, close) * (1 + next() * 0.003))
    l.push(Math.min(open, close) * (1 - next() * 0.003))
    c.push(close)
    v.push(100 + next() * 900)
    p = close
  }
  return new BarSeries({ symbol: 'BTCUSDT', interval: '1m', t0: 1_700_000_000_000, step: 60_000, open: o, high: h, low: l, close: c, volume: v })
}

/** pushNewBar 的数据那一半：新 K 线到货，而且走出一根远高于现价的新高。 */
function withNewBar(old: BarSeries, highMultiplier = 1.06): BarSeries {
  const next = old.clone()
  const last = old.close[old.count - 1]
  next.upsert({ openTime: old.lastTime + old.step, open: last, high: last * highMultiplier, low: last * 0.999, close: last * (highMultiplier - 0.01), volume: 500, takerBuy: NaN })
  return next
}

describe('拖动期间轴冻结 · 纯函数那一半（ChartAxisFreezeTests）', () => {
  const plotW = 390 - 50 // 390 宽的图，右轴按出厂 50 算；reconcile 只看比例，取哪个宽度都一样成立。

  it('crosshairHoldsTheViewport（抬手之后那一步）：贴着末根的图，新 K 线到货视野跟到新末根', () => {
    const old = freezeSeries()
    const spacing = new ViewWindow(old.lastTime, old.step * 120).barSpacing(old.step, plotW)
    const pinned = ViewMath.reset(old, plotW, spacing)
    const next = withNewBar(old)
    expect(next.count).toBe(601)
    const after = reconcile(pinned, old, next, plotW)
    expect(after.to).toBeGreaterThan(pinned.to)
    expect(Math.abs(after.to - ViewMath.reset(next, plotW, after.barSpacing(next.step, plotW)).to)).toBeLessThan(0.001)
    // 原地改的版本（网页推送走这条）与之同判。
    const inPlace = reconcileBeforeUpsert(pinned, old, old.lastTime + old.step, plotW)
    expect(inPlace.to).toBe(after.to)
    expect(inPlace.span).toBe(after.span)
  })

  it('historyViewDoesNotCatchUp：在看历史的图，新 K 线到货不会被拽回最新', () => {
    const old = freezeSeries()
    const spacing = new ViewWindow(old.lastTime, old.step * 120).barSpacing(old.step, plotW)
    const history = ViewMath.reset(old, plotW, spacing).dragged(600, plotW)
    const next = withNewBar(old)
    const after = reconcile(history, old, next, plotW)
    expect(after.to).toBe(history.to)
    expect(after.span).toBe(history.span)
    expect(reconcileBeforeUpsert(history, old, old.lastTime + old.step, plotW).to).toBe(history.to)
  })

  // 2026-10-02 手机网页版：右缘漂到最新右边几根（补缺口时 REST 末页比推送旧），原来新 K 线到货只原样不动，右边一直空着
  it('右缘漂到最新右边：新 K 线到货收回到最新再往前推', () => {
    const old = freezeSeries()
    const spacing = new ViewWindow(old.lastTime, old.step * 120).barSpacing(old.step, plotW)
    const latest = ViewMath.reset(old, plotW, spacing)
    const drifted = new ViewWindow(latest.to + 3 * old.step, latest.span)
    const after = reconcileBeforeUpsert(drifted, old, old.lastTime + old.step, plotW)
    expect(after.to).toBeCloseTo(latest.to + old.step, 6)
    expect(after.span).toBe(drifted.span)
  })
})

// ------------------------------------------------------------------ TimeAxisLabelTests（iOS 63994ab2 · 审查 B·P3-3）

describe('时间轴标签按日历对齐、互不相压（TimeAxisLabelTests）', () => {
  const DAYMS = 86_400_000
  /** 每月 1 号 00:00 UTC 开盘的月线（币安口径），从 2017-08 到 2026-10。 */
  const monthly = (): BarSeries => {
    const bars = []
    let p = 4_000
    for (let k = 0; k < 111; k++) {
      const year = 2017 + Math.floor((7 + k) / 12), month = ((7 + k) % 12) + 1
      bars.push(bar(daysFromCivil(year, month, 1) * DAYMS, p, p * 1.2, p * 0.8, p * 1.05, 1_000))
      p *= 1.03
    }
    return BarSeries.fromBars('BTCUSDT', '1M', bars)
  }
  /** 2019-01-07（周一）起 400 根周线。 */
  const weekly = (): BarSeries => {
    const t0 = daysFromCivil(2019, 1, 7) * DAYMS
    return BarSeries.fromBars('BTCUSDT', '1w', Array.from({ length: 400 }, (_, k) => {
      const c = 4_000 + k * 10
      return bar(t0 + k * 7 * DAYMS, c, c + 50, c - 50, c, 1)
    }))
  }
  const renderer = (series: BarSeries, view: ViewWindow, width: number) => {
    const r = new ChartRenderer(makeState({
      series, symbol: { symbol: 'BTCUSDT', base: 'BTC', priceDecimals: 2 }, view, price: priceTransform('linear'),
      subs: ['VOL'], tzOffset: 480, decimals: 2, options: defaultChartOptions(), nowMs: series.lastTime,
    }))
    return { r, L: r.layout(width, 600) }
  }
  const expectNoOverlap = (labels: { text: string; x: number; w: number }[], plotW: number, note: string) => {
    for (const l of labels) expect(l.x >= 0 && l.x + l.w <= plotW, `${note}「${l.text}」出了图区`).toBe(true)
    for (let i = 1; i < labels.length; i++) {
      const a = labels[i - 1], b = labels[i]
      expect(b.x, `${note}「${a.text}」与「${b.text}」压在一起`).toBeGreaterThanOrEqual(a.x + a.w + 4)
    }
  }

  it.each([300, 390, 440])('monthlyWholeHistory：月线整段历史缩进窄图只写年、互不相压（宽 %i）', width => {
    const s = monthly()
    const { r, L } = renderer(s, ViewWindow.fromTo(s.time(0), s.lastTime + 30 * DAYMS), width)
    const labels = r.timeAxisLabels(L)
    expect(labels.length, '九年历史一个年份都没写出来').toBeGreaterThanOrEqual(2)
    expectNoOverlap(labels, L.plotW, `宽 ${width}`)
    for (const l of labels) expect(/^20\d\d$/.test(l.text), `年档该只写年，得到「${l.text}」`).toBe(true)
  })

  it('everyZoomNoOverlap：周线 / 月线各档缩放标签互不相压', () => {
    const cases: [BarSeries, number[]][] = [[weekly(), [8, 20, 52, 120, 300, 400]], [monthly(), [6, 12, 24, 60, 111]]]
    for (const [s, counts] of cases) {
      for (const n of counts) {
        for (const width of [300, 402, 440]) {
          const to = s.lastTime + s.step
          const from = s.time(Math.max(0, s.count - n))
          const { r, L } = renderer(s, ViewWindow.fromTo(from, to), width)
          expectNoOverlap(r.timeAxisLabels(L), L.plotW, `${s.interval} ${n} 根 宽 ${width}`)
        }
      }
    }
  })

  it('weeklyLabelsAreMondays：周线刻度落在周一（上海时间）', () => {
    const s = weekly()
    const to = s.lastTime + s.step
    for (const weeks of [3, 6]) {
      const { r, L } = renderer(s, ViewWindow.fromTo(to - weeks * 7 * DAYMS, to), 402)
      const labels = r.timeAxisLabels(L)
      expect(labels.length).toBeGreaterThan(0)
      const view = r.state.viewport.view
      for (const l of labels) {
        const t = view.from + ((l.x + l.w / 2) / L.plotW) * view.span
        const days = Math.round((t + 480 * 60_000) / DAYMS)
        expect((((days - 4) % 7) + 7) % 7, `「${l.text}」不在周一`).toBe(0)
      }
    }
  })
})

// ------------------------------------------------------------------ VolumeBarTests（iOS 953c8766）

describe('成交量副图遇到坏量（VolumeBarTests）', () => {
  it('NaN / ±inf 那根直接跳过：不往画布塞非有限矩形，其余量柱照画', () => {
    const base = scaledSeries(1, fx.symbol)
    const bars = Array.from({ length: base.count }, (_, i) => bar(base.time(i), base.open[i], base.high[i], base.low[i], base.close[i], base.volume[i]))
    const n = bars.length
    const bad = [n - 2, n - 5, n - 9]
    bars[bad[0]] = { ...bars[bad[0]], volume: NaN }
    bars[bad[1]] = { ...bars[bad[1]], volume: Infinity }
    bars[bad[2]] = { ...bars[bad[2]], volume: -Infinity }
    const series = BarSeries.fromBars(fx.symbol, base.interval, bars)
    const L0 = new Layout(SIZE.W, SIZE.H, ['VOL'])
    const r = new ChartRenderer(makeState({
      series, symbol: { symbol: fx.symbol, base: fx.meta.base, priceDecimals: 2 },
      view: ViewMath.reset(series, L0.plotW, AICoinBehavior.initialSpacing), overlays: [], subs: ['VOL'], tzOffset: 0, decimals: 2,
      options: defaultChartOptions(), nowMs: series.lastTime,
    }))
    const rects: number[][] = []
    const ctx = new Proxy({} as Record<string, unknown>, {
      get: (target, key) => key === 'fillRect' ? (...a: number[]) => { rects.push(a) }
        : key === 'measureText' ? () => ({ width: 10 })
        : key in target ? target[key as string] : () => {},
      set: (target, key, value) => { target[key as string] = value; return true },
    }) as unknown as CanvasRenderingContext2D
    const L = r.layout(SIZE.W, SIZE.H)
    drawSub(r, ctx, L.panes[1], L, 3)
    expect(rects.length).toBeGreaterThan(20)
    for (const a of rects) expect(a.every(Number.isFinite), `非有限矩形 ${a}`).toBe(true)
  })
})
