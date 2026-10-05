// 横屏画线台对齐 iOS（2026-10-05）：主图指标默认展示但不撑价格区间、眼睛开关、「主图˅」面板拨开关、
// 横竖屏各记各的根宽，以及捏合用到的 ViewMath / 价格轴锚点几何（iOS a8012401）。
import { describe, expect, it } from 'vitest'
import { AICoinBehavior, ViewMath, ViewWindow, anchoredCenter, defaultChartOptions, priceRange } from '../src/m/chart/geometry'
import { BarSeries, INTERVAL_STEP } from '../src/m/chart/series'
import { makeState } from '../src/m/chart/state'
import { ChartRenderer } from '../src/m/chart/renderer'
import { mainOverlaysOf, spacingFor, spacingWrite, toggleMainOverlay } from '../src/m/pages/chart/logic'
import { OrientedPriceScale } from '../src/m/chart/orientedPrice'

function rising(count = 300): BarSeries {
  const o: number[] = [], h: number[] = [], l: number[] = [], c: number[] = [], v: number[] = []
  for (let k = 0; k < count; k++) {
    const p = 100 + k
    o.push(p - 0.2); c.push(p + 0.2); h.push(p + 0.5); l.push(p - 0.5); v.push(10)
  }
  return new BarSeries({ symbol: 'BTCUSDT', interval: '1h', t0: 1_700_000_000_000, step: INTERVAL_STEP['1h'], open: o, high: h, low: l, close: c, volume: v })
}

describe('横竖屏各记各的根宽', () => {
  const p = { barSpacing: 7, landscapeBarSpacing: 12 }
  it('spacingFor：横屏取 landscapeBarSpacing，竖屏取 barSpacing', () => {
    expect(spacingFor(true, p)).toBe(12)
    expect(spacingFor(false, p)).toBe(7)
  })
  it('spacingWrite：横屏松手写横屏那一格、竖屏写竖屏那一格；没变就不写', () => {
    expect(spacingWrite({ barSpacing: 9, landscape: true }, p)).toBe('landscapeBarSpacing')
    expect(spacingWrite({ barSpacing: 9, landscape: false }, p)).toBe('barSpacing')
    expect(spacingWrite({ barSpacing: 12, landscape: true }, p)).toBeNull()
    expect(spacingWrite({ barSpacing: 7 + 1e-9, landscape: false }, p)).toBeNull()
    // 横屏捏的根宽恰好等于竖屏那一格的值，也照样写横屏那格
    expect(spacingWrite({ barSpacing: 7, landscape: true }, p)).toBe('landscapeBarSpacing')
  })
})

describe('「主图˅」面板的开关', () => {
  it('mainOverlaysOf：主力订单流不算主图指标（眼睛只看主图叠加）', () => {
    expect(mainOverlaysOf(['MA', 'ORDERFLOW', 'BOLL'])).toEqual(['MA', 'BOLL'])
    expect(mainOverlaysOf(['ORDERFLOW'])).toEqual([])
  })
  it('眼睛关着时新开一个指标：眼睛跟着睁开', () => {
    expect(toggleMainOverlay({ overlays: ['MA'], drawingOverlaysShown: false }, 'BOLL'))
      .toEqual({ overlays: ['MA', 'BOLL'], drawingOverlaysShown: true })
  })
  it('关掉一个不动眼睛；眼睛开着时开新的也还是开着', () => {
    expect(toggleMainOverlay({ overlays: ['MA', 'BOLL'], drawingOverlaysShown: false }, 'MA'))
      .toEqual({ overlays: ['BOLL'], drawingOverlaysShown: false })
    expect(toggleMainOverlay({ overlays: ['MA'], drawingOverlaysShown: true }, 'MA'))
      .toEqual({ overlays: [], drawingOverlaysShown: true })
    expect(toggleMainOverlay({ overlays: [], drawingOverlaysShown: true }, 'EMA'))
      .toEqual({ overlays: ['EMA'], drawingOverlaysShown: true })
  })
})

describe('横屏主图指标只画不撑价格区间（ChartSession overlaysAffectPriceRange）', () => {
  const W = 932, H = 430
  const renderer = (affect: boolean) => {
    const series = rising()
    const span = series.step * 60
    return new ChartRenderer(makeState({
      series, symbol: { symbol: 'BTCUSDT', base: 'BTC', priceDecimals: 2 },
      view: new ViewWindow(series.lastTime + series.step / 2, span), overlays: ['MA'], subs: [],
      options: { ...defaultChartOptions(), overlaysAffectPriceRange: affect },
    }))
  }
  it('默认（竖屏）主图均线照常撑价格区间', () => {
    expect(defaultChartOptions().overlaysAffectPriceRange).toBe(true)
    const r = renderer(true)
    expect(r.overlayLines().length).toBeGreaterThan(0)
  })
  it('关掉之后价格区间只按 K 线算：涨势里滞后的长均线不再把下沿往下拽', () => {
    const on = renderer(true), off = renderer(false)
    expect(off.overlayLines()).toEqual([])
    const rOn = on.priceRange(W, H), rOff = off.priceRange(W, H)
    expect(rOff.lo).toBeGreaterThan(rOn.lo)
    const s = off.state
    const candleOnly = priceRange(s.viewport.view, s.input.series, { transform: s.viewport.price, paneHeight: off.layout(W, H).main.h, topInset: AICoinBehavior.mainTopInset })
    expect(rOff.lo).toBeGreaterThan(candleOnly.lo - 2)
  })
})

describe('捏合几何（ViewMath.isPinnedToLatest / pinched / clampedOffset，iOS a8012401）', () => {
  const b = rising()
  const plotW = 860
  it('reset 出来的视野贴着最新；往左拖两格就不贴了', () => {
    const v = ViewMath.reset(b, plotW, 8)
    expect(ViewMath.isPinnedToLatest(v, b, plotW)).toBe(true)
    expect(ViewMath.isPinnedToLatest(v.dragged(16, plotW), b, plotW)).toBe(false)
  })
  it('pinned：换根宽之后仍是「最新」那个位置', () => {
    const v = ViewMath.reset(b, plotW, 8)
    const p = ViewMath.pinched(v, b, plotW, 16, 300, true)
    expect(p.barSpacing(b.step, plotW)).toBeCloseTo(16, 9)
    expect(p.to).toBeCloseTo(ViewMath.reset(b, plotW, 16).to, 3)
  })
  it('不贴最新：焦点底下的时间不动', () => {
    const v = new ViewWindow(b.lastTime - b.step * 120, b.step * 100)
    const focus = 333
    const t = v.t(focus, plotW)
    const p = ViewMath.pinched(v, b, plotW, 12, focus, false)
    expect(p.barSpacing(b.step, plotW)).toBeCloseTo(12, 9)
    expect(p.x(t, plotW)).toBeCloseTo(focus, 6)
  })
  it('clampedOffset 只夹左右、不夹根宽', () => {
    const tooWide = new ViewWindow(b.lastTime + b.step * 1000, plotW / 60 * b.step)   // 根宽 60 > 40
    const c = ViewMath.clampedOffset(tooWide, b, plotW)
    expect(c.span).toBe(tooWide.span)
    expect(c.to).toBeLessThan(tooWide.to)
  })
})

describe('价格轴绕价位缩放（anchoredCenter）', () => {
  // 手动区间：mid = autoLow + autoH·center，half = autoH / (2·zoom)；价位应落在 g 处
  const where = (price: number, center: number, zoom: number, lo: number, hi: number, log: boolean) => {
    const mid = lo + (hi - lo) * center, half = (hi - lo) / (2 * zoom)
    const a = mid - half, z = mid + half
    return log ? (Math.log(price) - Math.log(a)) / (Math.log(z) - Math.log(a)) : (price - a) / (z - a)
  }
  it('线性：缩完之后那个价位还在原高度', () => {
    for (const [price, g, zoom] of [[105, 0.3, 2], [98, 0.8, 0.5], [100, 0.5, 3]] as const) {
      const c = anchoredCenter(price, g, zoom, 90, 110, 'linear')
      expect(where(price, c, zoom, 90, 110, false)).toBeCloseTo(g, 9)
    }
  })
  it('对数：二分出来的中心同样让价位留在原高度', () => {
    const c = anchoredCenter(104, 0.4, 2.5, 90, 110, 'log')
    expect(where(104, c, 2.5, 90, 110, true)).toBeCloseTo(0.4, 6)
  })
  it('坏输入回 0.5', () => {
    expect(anchoredCenter(NaN, 0.5, 2, 90, 110, 'linear')).toBe(0.5)
    expect(anchoredCenter(100, 0.5, 2, 110, 90, 'linear')).toBe(0.5)
  })
})

describe('价格轴倍率横竖各记一份（OrientedPriceScale，iOS 424a0160）', () => {
  const t = (zoom: number, centerFraction = 0.5, mode: 'log' | 'linear' = 'log') => ({ mode, inverted: false, zoom, centerFraction })
  it('横屏竖着捏出来的倍率不带回竖屏；再进横屏回到横屏那份', () => {
    const o = new OrientedPriceScale()
    // 竖屏 1.0 进横屏：第一次去横屏取 1.0
    let p = o.rotate(t(1), 'BTCUSDT', false, true)
    expect(p.zoom).toBe(1)
    // 横屏里捏到 2.8，回竖屏：竖屏那份是 1.0
    p = o.rotate(t(2.8, 0.6), 'BTCUSDT', true, false)
    expect(p.zoom).toBe(1)
    // 再进横屏：回到 2.8 / 0.6
    p = o.rotate(p, 'BTCUSDT', false, true)
    expect(p.zoom).toBe(2.8)
    expect(p.centerFraction).toBe(0.6)
  })
  it('第一次进横屏不抄竖屏那份；换品种 / 换轴模式作废', () => {
    const o = new OrientedPriceScale()
    expect(o.rotate(t(3), 'BTCUSDT', false, true).zoom).toBe(1)
    o.rotate(t(2), 'BTCUSDT', true, false)                 // 横屏记 2
    expect(o.rotate(t(1), 'ETHUSDT', false, true).zoom).toBe(1)   // 别的品种
    const o2 = new OrientedPriceScale()
    o2.rotate(t(1), 'BTCUSDT', false, true)
    o2.rotate(t(2), 'BTCUSDT', true, false)
    expect(o2.rotate(t(1, 0.5, 'linear'), 'BTCUSDT', false, true).zoom).toBe(1) // 换了轴模式
    const o3 = new OrientedPriceScale()
    o3.rotate(t(1), 'BTCUSDT', false, true)
    o3.rotate(t(2), 'BTCUSDT', true, false)
    o3.forget()
    expect(o3.rotate(t(1), 'BTCUSDT', false, true).zoom).toBe(1)
  })
  it('朝向没变原样返回', () => {
    const o = new OrientedPriceScale()
    const cur = t(2)
    expect(o.rotate(cur, 'BTCUSDT', true, true)).toBe(cur)
  })
})
