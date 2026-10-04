// 移植自 KanpanCore/Tests/KanpanCoreTests：ConstantsTests、ClampTests、FlingTests、AICoinBehaviorTests、
// GeometryTests（含 CandlePixelTests）、PriceScaleTests、TickTests、LayoutTests、PeriodSwitchTests、
// ChartOptionsTests（偏置 / 收盘价画法那几条），以及 KanpanChart 的 GeometryTableTests.primitives。
//
// 每条 it 的标题带 Swift 的测试函数名；数值与容差照抄 Swift。
import { describe, expect, it } from 'vitest'
import {
  AICoinBehavior, Chart, FlingCurve, Layout, ViewMath, ViewWindow, VelocityTracker, candleMetrics, candlePixels,
  clampView, defaultChartOptions, forward, hairline, inverse, niceStep, pOf, priceRange, priceTicks, priceTransform,
  reconcile, snap, swiftRound, timeStep, timeSteps, timeTicks, visibleRange, wickLineWidth, wickPixels, yOf, yOfValue,
} from '../src/m/chart/geometry'
import type { Pane, PriceBias, PriceMode, PriceRange } from '../src/m/chart/geometry'
import { BarSeries, INTERVALS, INTERVAL_STEP, bar, jsRound } from '../src/m/chart/series'
import type { Interval } from '../src/m/chart/series'
import { Rng, coreFixture, nums, rows, synthSeries } from './m-chart-fixtures'

const MODES: PriceMode[] = ['linear', 'log', 'percent']
const range = (lo: number, hi: number, base: number): PriceRange => ({ lo, hi, base, inverted: false })
const maxOf = (a: number[]): number => a.reduce((m, x) => Math.max(m, x), -Infinity)
const minOf = (a: number[]): number => a.reduce((m, x) => Math.min(m, x), Infinity)
const span = (lo: number, hi: number): number[] => Array.from({ length: hi - lo + 1 }, (_, k) => lo + k)

// ================================================================== ConstantsTests

describe('共用尺寸参数（ConstantsTests）', () => {
  it('defaults', () => {
    expect(AICoinBehavior.initialSpacing).toBe(4)
    expect(Chart.minBarSpacing === 1.6 && Chart.maxBarSpacing === 40).toBe(true)
    expect(AICoinBehavior.rightInset).toBe(0)
    expect(Chart.hitHandlePt).toBe(Chart.hitLinePt)
  })
})

// ================================================================== ClampTests

describe('AICoin 硬边界（ClampTests）', () => {
  it.each(Array.from({ length: 10 }, (_, k) => k))('bounds：十万随机视窗在左右列边界内（lane %i）', lane => {
    const rng = new Rng(999 + lane)
    const series = [1, 37, 500, 1500].map(n => synthSeries(n))
    let bad = 0
    for (let k = 0; k < 10000; k++) {
      const s = series[rng.i(0, 3)], width = rng.d(80, 1400), step = s.step
      const raw = new ViewWindow(s.lastTime + rng.d(-1e10, 1e10), step * Math.pow(10, rng.d(-3, 5)))
      const v = clampView(raw, s, width)
      const spacing = v.barSpacing(s.step, width)
      const firstX = v.x(s.firstTime, width)
      const lastX = v.x(s.lastTime, width)
      const expectedMinimumLastX = Math.min(s.count * spacing - spacing / 2, width - spacing / 2)
      if (spacing < 1.6 - 1e-6 || spacing > 40 + 1e-6 || firstX > spacing / 2 + 1e-6
        || lastX < expectedMinimumLastX - 1e-6) bad++
      const again = clampView(v, s, width)
      if (Math.abs(v.to - again.to) > 0.001 || Math.abs(v.span - again.span) > 0.001) bad++
    }
    expect(bad).toBe(0)
  })

  it('latest：最新柱列尾贴右缘，半根偏移一致', () => {
    const s = synthSeries(800)
    for (const spacing of [1.6, 4, 8, 40]) {
      const v = ViewMath.reset(s, 390, spacing)
      expect(Math.abs(v.x(s.lastTime, 390) + spacing / 2 - 390)).toBeLessThan(1e-6)
    }
  })

  it('empty：空数据不产生无效窗口', () => {
    const s = BarSeries.fromBars('X', '1h', [])
    const v = ViewWindow.fromTo(10, 20)
    expect(clampView(v, s, 300).equals(v)).toBe(true)
  })
})

// ================================================================== FlingTests

describe('AICoin OverScroller 参考惯性（FlingTests）', () => {
  it('speed：速度越快距离与持续时间越长；正负对称', () => {
    const slow = new FlingCurve(500)
    const fast = new FlingCurve(2000)
    const negative = new FlingCurve(-2000)
    expect(fast.durationMs > slow.durationMs && fast.distance > slow.distance).toBe(true)
    expect(fast.distance === -negative.distance && fast.durationMs === negative.durationMs).toBe(true)
    expect(new FlingCurve(0).sample(0).done).toBe(true)
  })

  it.each([-3000, -500, 500, 3000])('monotonic：曲线单调、有限、到达终点后停止（%d）', speed => {
    const curve = new FlingCurve(speed)
    let previous = 0
    for (let i = 0; i <= 200; i++) {
      const sample = curve.sample(curve.durationMs * i / 200)
      expect(Math.abs(sample.pastPx) >= previous && Math.abs(sample.pastPx) <= Math.abs(curve.distance)).toBe(true)
      previous = Math.abs(sample.pastPx)
    }
    expect(curve.sample(curve.durationMs).done).toBe(true)
    expect(curve.sample(curve.durationMs * 2).pastPx).toBe(curve.distance)
  })

  it('reference：AOSP 参考数值 1000dp/s', () => {
    const curve = new FlingCurve(1000)
    expect(curve.durationMs).toBe(555)
    expect(curve.distance).toBe(194)
  })

  it('velocity：速度取样排除过期采样', () => {
    const v = new VelocityTracker()
    v.add(0, 0); v.add(1000, 900)
    v.add(1100, 950); v.add(1200, 1000)
    expect(Math.abs(v.velocity - 2)).toBeLessThan(1e-9)
    v.reset(); expect(v.velocity).toBe(0)
  })
})

// ================================================================== AICoinBehaviorTests

describe('AICoin 冷启动与尺寸（AICoinBehaviorTests）', () => {
  const series = (start: number, count = 600): BarSeries =>
    BarSeries.fromBars('BTCUSDT', '1h', Array.from({ length: count }, (_, k) => bar(start + k * 3_600_000, 100, 120, 90, 110, 1)))

  it('snapshotFollow：快照补到现在时跟随末根；历史视野不跳', () => {
    const old = series(1_700_000_000_000)
    const next = series(old.firstTime + 48 * old.step)
    const view = ViewMath.reset(old, 352, 4)
    const moved = reconcile(view, old, next, 352)
    expect(moved.span).toBe(view.span)
    expect(Math.abs(view.x(old.lastTime, 352) - moved.x(next.lastTime, 352))).toBeLessThan(1e-8)
    const history = new ViewWindow(old.lastTime - 100 * old.step, view.span)
    expect(reconcile(history, old, next, 352).equals(history)).toBe(true)
  })

  it('rangeBounds：纯未来视野和短指标数组不越界，对数倒置可往返', () => {
    const b = series(1_700_000_000_000)
    const v = new ViewWindow(b.lastTime + b.step * 100, b.step * 10)
    const transform = { ...priceTransform('log'), inverted: true }
    const r = priceRange(v, b, { overlayValues: [[], [100]], transform, paneHeight: 300 })
    expect(r.lo > 0 && r.hi > r.lo).toBe(true)
    const pane: Pane = { indicator: null, y: 0, h: 300 }
    expect(yOf(120, pane, r, 'log')).toBeGreaterThan(yOf(90, pane, r, 'log'))
    expect(Math.abs(pOf(yOf(110, pane, r, 'log'), pane, r, 'log') - 110)).toBeLessThan(1e-8)
  })
})

// ================================================================== GeometryTests / CandlePixelTests

const isIntegral = (v: number): boolean => Math.abs(v - swiftRound(v)) < 1e-9
/** CandlePixelTests 的 `var sp = Chart.minBarSpacing; while sp <= max { …; sp += 0.05 }`（累加，不是乘）。 */
function spacingSweep(): number[] {
  const out: number[] = []
  for (let sp = Chart.minBarSpacing; sp <= Chart.maxBarSpacing; sp += 0.05) out.push(sp)
  return out
}

describe('根宽与像素对齐（GeometryTests）', () => {
  it('referenceWidth：当前参考手机 4pt 节距对应 8px 实体、2px 影线', () => {
    const w = candlePixels(4, 3)
    expect(w.body === 8 && w.wick === 2).toBe(true)
  })

  it.each([1, 2, 3, 3.5])('snapping：snap 落在设备像素边界（scale %d）', scale => {
    const r = new Rng(scale * 100)
    for (let k = 0; k < 2000; k++) {
      const x = r.d(-500, 1500)
      const s = snap(x, scale)
      expect(Math.abs(s * scale - swiftRound(s * scale)), `snap(${x}) = ${s} 没对齐`).toBeLessThan(1e-9)
      expect(Math.abs(s - x), 'snap 挪太远').toBeLessThanOrEqual(0.5 / scale + 1e-9)
      const h = hairline(x, scale)
      expect(Math.abs((h * scale - 0.5) - swiftRound(h * scale - 0.5)), `hairline(${x}) = ${h} 不在半像素上`).toBeLessThan(1e-9)
    }
  })

  it('thinFlag：thin 判定', () => {
    expect(candleMetrics(1.0, 2).thin, 'aicoin 挤成这样还画实体').toBe(true)
    expect(candleMetrics(20, 2).thin, 'aicoin 拉开了还不画实体').toBe(false)
  })

  it('wickWidth：影线粗细换算', () => {
    expect(wickPixels(2), 'aicoin 影线像素数（2x 就是风格表原值）').toBe(Math.max(1, jsRound(Math.max(0.5, 4 / 3))))
    for (const scale of [1, 2, 3]) {
      const px = wickPixels(scale)
      expect(px, `aicoin@${scale} 影线像素数`).toBe(Math.max(1, jsRound(Math.max(0.5, 4 / 3) * Math.max(1, scale) / 2)))
      expect(wickLineWidth(scale), `aicoin@${scale}`).toBe(px / scale)
      expect(Math.abs(wickLineWidth(scale) * scale - px)).toBeLessThan(1e-9)
      const m = candleMetrics(8, scale)
      expect(m.wickW, `aicoin@${scale} wickW`).toBe(px / scale)
      expect(m.minBody, `aicoin@${scale} minBody`).toBe(1 / scale)
      expect(m.outline, `aicoin@${scale} 描边线宽`).toBe(1 / scale)
      expect(m.bodyW > 0 && m.wickW > 0).toBe(true)
    }
  })
})

describe('蜡烛整像素光栅化（CandlePixelTests）', () => {
  it.each([1, 2, 3, 3.5])('wickIsWholePixels：影线整像素（scale %d）', scale => {
    const px = wickPixels(scale)
    expect(px, 'aicoin 影线归零').toBeGreaterThanOrEqual(1)
    const w = wickLineWidth(scale)
    expect(Math.abs(w * scale - swiftRound(w * scale))).toBeLessThan(1e-9)
    const want = Math.max(0.5, 4 / 3) / 2
    expect(px === 1 || Math.abs(w - want) <= 0.5 / scale + 1e-9, `aicoin@${scale} 物理宽度跑了：${w} vs ${want}`).toBe(true)
  })

  it.each([1, 2, 3, 3.5])('parity：实体与影线奇偶相同（scale %d）', scale => {
    for (const sp of spacingSweep()) {
      const w = candlePixels(sp, scale)
      expect(w.body % 2, `aicoin@${scale} spacing=${sp} 奇偶不同`).toBe(w.wick % 2)
      expect(w.body, `aicoin@${scale} spacing=${sp} 实体比影线细`).toBeGreaterThanOrEqual(w.wick)
    }
  })

  it.each([1, 2, 3, 3.5])('gapAtLeastOnePixel：实体之间至少 1 像素缝（scale %d）', scale => {
    for (const sp of spacingSweep()) {
      const w = candlePixels(sp, scale)
      const cell = Math.floor(sp * scale)
      const ink = candleMetrics(sp, scale).thin ? w.wick : w.body
      if (cell >= 2) expect(cell - ink, `aicoin@${scale} spacing=${sp}`).toBeGreaterThanOrEqual(1)
    }
  })

  it.each([1, 2, 3, 3.5])('monotonic：实体宽单调（scale %d）', scale => {
    let prev = -1
    for (const sp of spacingSweep()) {
      const b = candlePixels(sp, scale).body
      expect(b, `aicoin@${scale} spacing=${sp} 变细了 ${prev}→${b}`).toBeGreaterThanOrEqual(prev)
      prev = b
    }
  })

  it.each([2, 3, 3.5])('thinIsPhysical：thin 是物理判据（scale %d）', scale => {
    expect(candleMetrics(3 / scale, scale).thin, `aicoin@${scale} 一格 3 像素还画实体`).toBe(true)
    expect(candleMetrics(AICoinBehavior.initialSpacing, scale).thin, `aicoin@${scale} 默认根间距就退化了`).toBe(false)
  })

  it.each([2, 3, 3.5])('defaultSpacingIsFat：默认根间距下实体够胖（scale %d）', scale => {
    const w = candlePixels(AICoinBehavior.initialSpacing, scale)
    const cell = Math.floor(AICoinBehavior.initialSpacing * scale)
    expect(w.body).toBeGreaterThan(w.wick)
    expect(cell - w.body).toBeGreaterThanOrEqual(1)
  })

  it('garbageIn：非法输入兜底', () => {
    for (const sp of [0, -5, NaN, Infinity]) {
      const w = candlePixels(sp, 2)
      expect(w.body >= 1 && w.wick >= 1, `spacing=${sp}`).toBe(true)
    }
    for (const sc of [0, -2, NaN]) {
      const w = candlePixels(8, sc)
      expect(w.body >= 1 && w.wick >= 1, `scale=${sc}`).toBe(true)
    }
  })
})

describe('A3.10 像素边界（KanpanChart PixelBoundaryTests）', () => {
  it('primitives：snap / hairline 在 1×/2×/3× 下都对', () => {
    for (const s of [1, 2, 3]) {
      // stride(from: -3.0, through: 60.0, by: 0.137)：Swift 的 stride 按 start + i·step 算，不累加。
      for (let i = 0; ; i++) {
        const raw = -3 + i * 0.137
        if (raw > 60) break
        const a = snap(raw, s)
        expect(isIntegral(a * s)).toBe(true)
        expect(Math.abs(a - raw)).toBeLessThanOrEqual(0.5 / s + 1e-9)
        const b = hairline(raw, s)
        expect(isIntegral(b * s - 0.5)).toBe(true)
        expect(Math.abs(b - raw)).toBeLessThanOrEqual(1.0 / s + 1e-9)
      }
    }
  })
})

// ================================================================== PriceScaleTests

describe('价格轴（PriceScaleTests）', () => {
  const pane: Pane = { indicator: null, y: 12, h: 480 }

  it.each(MODES)('roundTrip：pOf(yOf(p)) == p（%s）', mode => {
    const r = new Rng(mode.length * 7919)
    let worst = 0
    for (let k = 0; k < 20000; k++) {
      const lo = Math.pow(10, r.d(-4, 5))
      const hi = lo * r.d(1.0001, 4)
      const rg = range(lo, hi, r.d(lo, hi))
      const p = r.d(lo, hi)
      const y = yOf(p, pane, rg, mode)
      const back = pOf(y, pane, rg, mode)
      worst = Math.max(worst, Math.abs(back - p) / Math.max(1, Math.abs(p)))
    }
    expect(worst, `${mode} 最差相对误差 ${worst}`).toBeLessThanOrEqual(1e-9)
  })

  it.each(MODES)('edges：边界对齐（%s）', mode => {
    const rg = range(100, 200, 150)
    const yLo = yOf(rg.lo, pane, rg, mode)
    const yHi = yOf(rg.hi, pane, rg, mode)
    expect(Math.abs(yLo - (pane.y + pane.h)), `${mode} 下沿 ${yLo}`).toBeLessThan(1e-9)
    expect(Math.abs(yHi - pane.y), `${mode} 上沿 ${yHi}`).toBeLessThan(1e-9)
    expect(yOf(150, pane, rg, mode)).toBeLessThan(yLo)
    expect(yOf(150, pane, rg, mode)).toBeGreaterThan(yHi)
  })

  it('percentBase：百分比以可见区首根收盘为基准', () => {
    const rg = range(90, 110, 100)
    expect(forward('percent', 100, 100)).toBe(0)
    expect(Math.abs(forward('percent', 110, 100) - 10)).toBeLessThan(1e-12)
    expect(Math.abs(inverse('percent', -5, 100) - 95)).toBeLessThan(1e-12)
    const y = yOf(100, pane, rg, 'percent')
    expect(Math.abs(y - (pane.y + pane.h / 2)), `0% 不在正中 ${y}`).toBeLessThan(1e-9)
  })

  it('logIsGeometric：对数模式等比等距', () => {
    const rg = range(10, 1000, 100)
    const ys = [10, 100, 1000].map(p => yOf(p, pane, rg, 'log'))
    expect(Math.abs((ys[0] - ys[1]) - (ys[1] - ys[2]))).toBeLessThan(1e-9)
  })

  // 审查 Web D 线（对齐 iOS 3588be36 · B·P1-1）：一字板留白跟价格同量级；坏数不进区间。
  const flat = (price: number, n: number) =>
    BarSeries.fromBars('FLAT', '1h', Array.from({ length: n }, (_, k) => bar(1_700_000_000_000 + k * 3_600_000, price, price, price, price, 0)))
  it.each([0.00001234, 0.5, 60_000])('flatSeriesPadIsRelative：一字板留白按价格比例（%s）', price => {
    const s = flat(price, 50)
    const v = ViewMath.reset(s, 390, 9.2)
    for (const mode of ['linear', 'log'] as PriceMode[]) {
      const r = priceRange(v, s, { transform: priceTransform(mode) })
      expect(r.lo, `${mode} ${price} 下沿进了负价`).toBeGreaterThan(0)
      expect(r.lo < price && price < r.hi, `${mode} 价格不在区间里 ${r.lo}…${r.hi}`).toBe(true)
      expect((r.hi - r.lo) / price, `${mode} ${price} 被撑开`).toBeLessThan(0.01)
      expect((r.hi - r.lo) / price, `${mode} ${price} 塌得太薄`).toBeGreaterThan(0.001)
    }
  })
  it('flatZeroSeries：一字板价格为 0 仍有厚度', () => {
    const s = flat(0, 10)
    const r = priceRange(ViewMath.reset(s, 390, 9.2), s)
    expect(r.hi > r.lo && Number.isFinite(r.lo) && Number.isFinite(r.hi)).toBe(true)
  })
  it('nonFiniteBarsIgnored：高低价与画线价格里的坏数不进区间', () => {
    const n = 50
    const bars = Array.from({ length: n }, (_, k) => bar(1_700_000_000_000 + k * 3_600_000, 100, 101, 99, 100, 1))
    bars[n - 3].high = Infinity; bars[n - 4].low = -Infinity; bars[n - 5].high = NaN
    const s = BarSeries.fromBars('BAD', '1h', bars)
    const r = priceRange(ViewMath.reset(s, 390, 9.2), s, { drawingPrices: [NaN, Infinity] })
    expect(r.lo > 90 && r.hi < 110, `坏数顶飞了区间 ${r.lo}…${r.hi}`).toBe(true)
  })

  it('rangeIncludesOverlaysAndDrawings：极值并入叠加指标与画线', () => {
    const s = synthSeries(400, { seed: 55 })
    const plotW = 390
    const v = ViewMath.reset(s, plotW, AICoinBehavior.initialSpacing)
    const bare = priceRange(v, s)
    const { lo, hi } = visibleRange(v, s)
    const top = maxOf(span(lo, hi).map(i => s.high[i])) * 1.5
    const bottom = minOf(span(lo, hi).map(i => s.low[i])) * 0.5
    const overlay = new Array<number>(s.count).fill(NaN)
    overlay[Math.floor((lo + hi) / 2)] = top
    const wide = priceRange(v, s, { overlayValues: [overlay], drawingPrices: [bottom] })
    expect(wide.hi, '叠加指标没抬高上界').toBeGreaterThan(bare.hi)
    expect(wide.lo, '画线端点没压低下界').toBeLessThan(bare.lo)
    expect(wide.hi).toBeGreaterThanOrEqual(top)
    expect(wide.lo).toBeLessThanOrEqual(bottom)
    const withNaN = priceRange(v, s, { overlayValues: [new Array<number>(s.count).fill(NaN)] })
    expect(withNaN.lo === bare.lo && withNaN.hi === bare.hi, '全 NaN 的线改变了区间').toBe(true)
  })

  it('padding：留白按风格 pad', () => {
    const s = synthSeries(300, { seed: 56 })
    const v = ViewMath.reset(s, 390, 9.2)
    const { lo, hi } = visibleRange(v, s)
    const maxV = maxOf(span(lo, hi).map(i => s.high[i]))
    const minV = minOf(span(lo, hi).map(i => s.low[i]))
    const r = priceRange(v, s)
    const top = AICoinBehavior.mainTopInset, bottom = AICoinBehavior.mainBottomInset
    const perPoint = (maxV - minV) / (300 - top - bottom)
    expect(Math.abs((maxV + perPoint * top) - r.hi), 'aicoin 上留白').toBeLessThan(1e-9)
    expect(Math.abs((minV - perPoint * bottom) - r.lo), 'aicoin 下留白').toBeLessThan(1e-9)
  })

  it('transform：价格轴缩放与平移', () => {
    const s = synthSeries(300, { seed: 57 })
    const v = ViewMath.reset(s, 390, 9.2)
    const base = priceRange(v, s)
    const mid = (base.lo + base.hi) / 2
    const zoomed = priceRange(v, s, { transform: priceTransform('linear', 2) })
    expect(Math.abs((zoomed.lo + zoomed.hi) / 2 - mid), '缩放挪了中心').toBeLessThan(1e-9)
    expect(Math.abs((zoomed.hi - zoomed.lo) - (base.hi - base.lo) / 2), '缩放比例不对').toBeLessThan(1e-9)
    const shifted = priceRange(v, s, { transform: priceTransform('linear', 2, 0.75) })
    expect(Math.abs((shifted.hi - shifted.lo) - (base.hi - base.lo) / 2), '平移改了高度').toBeLessThan(1e-9)
    expect(Math.abs((shifted.lo + shifted.hi) / 2 - (mid + (base.hi - base.lo) * 0.25)), '平移距离不对').toBeLessThan(1e-9)
    const crazy = priceRange(v, s, { transform: priceTransform('linear', 0.0001) })
    expect(Math.abs((crazy.hi - crazy.lo) - (base.hi - base.lo) / 0.03), 'zoom 下限没兜住').toBeLessThan(1e-6)
  })

  it('flatSeries：十字星不塌成零高度', () => {
    const n = 50
    const fill = (x: number): number[] => new Array<number>(n).fill(x)
    const s = new BarSeries({ symbol: 'FLAT', interval: '1h', t0: 1_700_000_000_000, open: fill(100), high: fill(100), low: fill(100), close: fill(100), volume: fill(0) })
    const v = ViewMath.reset(s, 390, 9.2)
    const r = priceRange(v, s)
    expect(r.hi).toBeGreaterThan(r.lo)
    for (const mode of MODES) expect(Number.isFinite(yOf(100, pane, r, mode)), mode).toBe(true)
  })

  it('subPane：副图值 → y', () => {
    const p: Pane = { indicator: 'RSI', y: 100, h: 80 }
    expect(Math.abs(yOfValue(0, p, 0, 100) - 180)).toBeLessThan(1e-9)
    expect(Math.abs(yOfValue(100, p, 0, 100) - 100)).toBeLessThan(1e-9)
    expect(Math.abs(yOfValue(50, p, 0, 100) - 140)).toBeLessThan(1e-9)
    expect(yOfValue(5, p, 3, 3)).toBe(140)
  })
})

// ================================================================== TickTests

describe('刻度（TickTests）', () => {
  const ticks = coreFixture<{ nice: unknown; time: unknown; timeSteps: unknown }>('ticks')
  const nice = rows(ticks.nice), time = rows(ticks.time)

  it('niceStepMatches：niceStep 与原型全等', () => {
    let bad = 0, first = ''
    for (const row of nice) {
      const got = niceStep(row[0], row[1])
      if (Math.abs(got - row[2]) > 1e-12 * Math.max(1, Math.abs(row[2]))) {
        bad++
        if (!first) first = `span=${row[0]} want=${row[1]} 期望 ${row[2]} 得到 ${got}`
      }
    }
    expect(bad, `${nice.length} 组里 ${bad} 组不符，首个 ${first}`).toBe(0)
    expect(nice.length).toBeGreaterThanOrEqual(200)
  })

  it('timeStepMatches：timeStep 与原型全等', () => {
    let bad = 0, first = ''
    for (const row of time) {
      const got = timeStep(row[0], row[1], row[2])
      if (got !== row[3]) { bad++; if (!first) first = `span=${row[0]} plotW=${row[1]} 期望 ${row[3]} 得到 ${got}` }
    }
    expect(bad, `${time.length} 组里 ${bad} 组不符，首个 ${first}`).toBe(0)
    expect(time.length).toBeGreaterThanOrEqual(200)
  })

  it('stepsTable：阶梯表与原型一致', () => {
    expect(timeSteps).toEqual(nums(ticks.timeSteps))
  })

  it('niceStepMantissa：niceStep 尾数只有五种', () => {
    const r = new Rng(515)
    for (let k = 0; k < 20000; k++) {
      const sp = Math.pow(10, r.d(-6, 9))
      const want = r.i(2, 16)
      const s = niceStep(sp, want)
      expect(s > 0 && Number.isFinite(s), `span=${sp} 得到 ${s}`).toBe(true)
      const m = s / Math.pow(10, Math.floor(Math.log10(s)))
      expect([1, 2, 2.5, 5, 10].some(x => Math.abs(x - m) < 1e-9), `span=${sp} want=${want} 尾数 ${m}`).toBe(true)
    }
    expect(niceStep(0, 5), 'span=0 要有兜底').toBe(1)
    expect(niceStep(-3, 5)).toBe(1)
  })

  it('density：刻度密度合理', () => {
    const r = new Rng(717)
    for (let k = 0; k < 5000; k++) {
      const sp = Math.pow(10, r.d(-4, 6))
      const want = r.i(2, 14)
      const n = sp / niceStep(sp, want)
      expect(n, `span=${sp} want=${want} 出了 ${n} 格`).toBeLessThanOrEqual(want * 2 + 1e-9)
      expect(n, `span=${sp} want=${want} 只出了 ${n} 格`).toBeGreaterThanOrEqual(want / 4 - 1e-9)
    }
  })

  // Swift 是 TZChoice.allCases（local / utc / exchange）；网页只有固定偏移（上海 +480，没有夏令时），
  // 所以换成三个固定偏移：UTC、上海、纽约冬令时。
  it.each([0, 480, -300])('timeTicksAligned：时间刻度按时区对齐（偏移 %i 分）', offsetMinutes => {
    const r = new Rng(919)
    for (let k = 0; k < 400; k++) {
      const from = r.d(1.6e12, 1.8e12)
      const sp = Math.pow(10, r.d(5, 10.5))
      const plotW = r.d(120, 900)
      const v = ViewWindow.fromTo(from, from + sp)
      const off = offsetMinutes * 60_000
      const ts = timeTicks(v, plotW, offsetMinutes)
      for (const { t, step } of ts) {
        expect(t >= v.from - 1 && t <= v.to + 1, `刻度跑到视野外 ${t}`).toBe(true)
        const m = (t + off) % step
        expect(Math.abs(m) < 1e-6 || Math.abs(Math.abs(m) - step) < 1e-6, `${offsetMinutes} 没对齐：${t} % ${step} = ${m}`).toBe(true)
      }
      const expected = Math.floor(v.span / (ts[0]?.step ?? 1))
      expect(ts.length, '刻度多了').toBeLessThanOrEqual(expected + 2)
    }
  })

  it.each(MODES)('priceTicksEven：价格刻度等距（%s）', mode => {
    const r = new Rng(1213)
    for (let k = 0; k < 600; k++) {
      const lo = r.d(0.01, 90000)
      const rg = range(lo, lo * r.d(1.001, 3), lo)
      const h = r.d(60, 700)
      const ts = priceTicks(rg, mode, h)
      if (ts.length < 2) continue
      const d0 = ts[1] - ts[0]
      for (let i = 1; i < ts.length; i++) {
        expect(Math.abs((ts[i] - ts[i - 1]) - d0), `${mode} 第 ${i} 格不等距`).toBeLessThanOrEqual(1e-9 * Math.max(1, Math.abs(d0)))
      }
      const a = forward(mode, rg.lo, rg.base), z = forward(mode, rg.hi, rg.base)
      expect(ts[0] >= a - 1e-9 && ts[ts.length - 1] <= z + 1e-9, `${mode} 刻度出界`).toBe(true)
      expect(ts.length, `${mode} 刻度太密`).toBeLessThanOrEqual(Math.max(2, Math.floor(h / Chart.priceLabelPx)) * 2 + 2)
    }
  })
})

// ================================================================== LayoutTests

describe('AICoin 共用布局（LayoutTests）', () => {
  it('sharedGeometry：主图、时间轴、副图铺满且互不重叠', () => {
    for (const [w, h] of [[402, 600], [375, 450], [874, 270], [744, 950], [320, 200]]) {
      for (const subs of [[], ['MACD'], ['VOL', 'OI', 'MACD']]) {
        const layout = new Layout(w, h, subs)
        expect(layout.main.h).toBeGreaterThan(0)
        expect(layout.timeY).toBe(layout.mainH)
        expect(layout.plotW).toBeGreaterThan(0)
        let end = layout.mainH + AICoinBehavior.timeHeight
        for (const p of layout.panes.slice(1)) {
          expect(Math.abs(p.y - end)).toBeLessThan(1e-8)
          expect(p.h).toBeGreaterThan(0)
          end = p.y + p.h
        }
        expect(Math.abs(end - h)).toBeLessThan(1e-8)
      }
    }
  })

  it('proportionalPanes：主副比例与自定义副图高度不随风格改变', () => {
    const layout = new Layout(402, 617, ['VOL', 'OI', 'MACD'], { VOL: 1, OI: 1, MACD: 1 })
    expect(layout.mainH).toBe(300)
    expect(layout.panes[1].h).toBe(100)
    expect(layout.panes[1].y).toBe(317)
    const custom = new Layout(402, 617, ['MACD', 'RSI'], { MACD: 2, RSI: 0.5 })
    expect(custom.panes[1].h).toBe(custom.panes[2].h * 4)
    expect(new Layout(402, 617, ['MACD', 'RSI'], { MACD: 2, RSI: 0.5 })).toEqual(custom)
    // 没拖过的副图按 DEFAULT_SUB_SCALE（0.7）：三个副图时 K 线占图区约六成，不再是一半
    const plain = new Layout(402, 617, ['VOL', 'OI', 'MACD'])
    expect(plain.mainH / 600).toBeCloseTo(3 / 5.1, 5)
    expect(plain.panes[1].h).toBeCloseTo(600 * 0.7 / 5.1, 5)
  })
})

// ================================================================== PeriodSwitchTests

describe('切周期（PeriodSwitchTests）', () => {
  const plotW = 390
  const end = 1_789_300_800_000
  const spacings = [1.6, 2.0, 2.3, 2.6, 4.8, 9.2, 15, 23.5, 32, 40]
  const cache = new Map<Interval, BarSeries>()
  const series = (iv: Interval, count = 2200): BarSeries => {
    const hit = cache.get(iv)
    if (hit) return hit
    const step = INTERVAL_STEP[iv]
    const s = synthSeries(count, { interval: iv, t0: end - (count - 1) * step, seed: step % 9973 })
    cache.set(iv, s)
    return s
  }

  it.each(INTERVALS)('switchKeepsPixelWidth：14 × 14 组互切，根宽不变、右缘不动（从 %s）', from => {
    const a = series(from)
    for (const to of INTERVALS) {
      const b = series(to)
      for (const spacing of spacings) {
        const span0 = (plotW / spacing) * a.step
        const old = clampView(new ViewWindow(a.lastTime, span0), a, plotW)
        const measured = old.barSpacing(a.step, plotW)
        const v = ViewMath.switchInterval(b, plotW, measured, old.to)
        const got = v.barSpacing(b.step, plotW)
        expect(Math.abs(got - measured), `${from}→${to} @${spacing}：根宽 ${measured} → ${got}`).toBeLessThan(1e-9)
        expect(Math.abs(v.to - old.to), `${from}→${to} @${spacing}：右缘 ${old.to} → ${v.to}`).toBeLessThanOrEqual(Math.max(1e-6, Math.abs(old.to) * 1e-12))
      }
    }
  })

  it.each(INTERVALS)('switchFromScrolledView：拖回历史后再切（从 %s）', from => {
    for (const to of INTERVALS) {
      const b = series(to)
      for (const spacing of spacings) {
        const sp = (plotW / spacing) * b.step
        const anchor = end - 0.2 * sp
        const v = ViewMath.switchInterval(b, plotW, spacing, anchor)
        expect(Math.abs(v.barSpacing(b.step, plotW) - spacing), `${from}→${to} @${spacing} 根宽变了`).toBeLessThan(1e-9)
        expect(Math.abs(v.to - anchor), `${from}→${to} @${spacing} 右缘动了`).toBeLessThanOrEqual(Math.max(1e-6, Math.abs(anchor) * 1e-12))
      }
    }
  })

  it.each(INTERVALS)('noAnchorFallsBackToRightGap：无锚点时落回右缘留白（%s）', iv => {
    const s = series(iv)
    for (const spacing of spacings) {
      const v = ViewMath.switchInterval(s, plotW, spacing, null)
      expect(Math.abs(v.barSpacing(s.step, plotW) - spacing), `${iv} @${spacing}`).toBeLessThan(1e-9)
      expect(Math.abs((v.to - s.lastTime) / v.span - (AICoinBehavior.rightInset + spacing / 2) / plotW), `${iv} @${spacing} 留白不对`).toBeLessThan(1e-9)
    }
  })

  it('spacingClamped：根间距越界先夹', () => {
    const s = series('1h')
    for (const bad of [-5, 0, 0.01, 1e9, Infinity]) {
      const v = ViewMath.switchInterval(s, plotW, bad, null)
      const got = v.barSpacing(s.step, plotW)
      expect(got >= Chart.minBarSpacing - 1e-9 && got <= Chart.maxBarSpacing + 1e-9, `spacing=${bad} → ${got}`).toBe(true)
    }
  })

  it('roundTripNoDrift：来回切十次不漂', () => {
    const order: Interval[] = ['1h', '5m', '1d', '1m', '4h', '1w', '15m', '1M', '12h', '30m', '1h']
    let s = series('1h')
    let v = clampView(new ViewWindow(s.lastTime, (plotW / 9.2) * s.step), s, plotW)
    const want = v.barSpacing(s.step, plotW)
    for (const iv of order.slice(1)) {
      const spacing = v.barSpacing(s.step, plotW)
      const next = series(iv)
      v = ViewMath.switchInterval(next, plotW, spacing, v.to)
      s = next
    }
    expect(Math.abs(v.barSpacing(s.step, plotW) - want)).toBeLessThan(1e-9)
  })
})

// ================================================================== ChartOptionsTests（几何部分；倒计时在 m-chart-format）

describe('K 线设置（ChartOptionsTests）', () => {
  const BIASES: PriceBias[] = ['up', 'center', 'down']

  it('defaults：默认值一律维持现状', () => {
    const o = defaultChartOptions()
    expect(o.kind).toBe('candle')
    expect(o.grid === 'off' && o.body === 'solid', '默认必须是隐藏网格 + 实心阳线（AICoin 的画法）').toBe(true)
    expect(o.lastLine && o.drawings, '实时价格线和画线默认都画').toBe(true)
    expect(!o.countdown && !o.sinceChange, '新画法默认一律关').toBe(true)
    expect(o.bias === 'center' && o.anchor === 'right').toBe(true)
    expect(defaultChartOptions()).toEqual(defaultChartOptions())
  })

  it('biasKeepsSpan：三档偏置跨度完全相同', () => {
    const s = synthSeries(400, { seed: 11 })
    const v = ViewMath.reset(s, 353, 8)
    const spans = BIASES.map(bias => { const r = priceRange(v, s, { bias }); return r.hi - r.lo })
    expect(Math.abs(spans[0] - spans[1]) < 1e-8 && Math.abs(spans[1] - spans[2]) < 1e-8, `跨度变了：${spans}`).toBe(true)
  })

  it('biasDirection：偏上把蜡烛顶上去', () => {
    const s = synthSeries(400, { seed: 12 })
    const v = ViewMath.reset(s, 353, 8)
    const up = priceRange(v, s, { bias: 'up' })
    const mid = priceRange(v, s, { bias: 'center' })
    const down = priceRange(v, s, { bias: 'down' })
    expect(up.lo < mid.lo && up.hi < mid.hi, '偏上没把区间往下挪').toBe(true)
    expect(down.lo > mid.lo && down.hi > mid.hi, '偏下没把区间往上挪').toBe(true)
    const pane: Pane = { indicator: null, y: 0, h: 400 }
    const px = s.close[s.count - 1]
    expect(yOf(px, pane, up, 'linear')).toBeLessThan(yOf(px, pane, mid, 'linear'))
  })

  it('closeOnlyRange：收盘价画法只按收盘撑区间', () => {
    const s = synthSeries(400, { seed: 13 })
    const v = ViewMath.reset(s, 353, 8)
    const candle = priceRange(v, s, { paneHeight: 400 })
    const line = priceRange(v, s, { paneHeight: 400, closeOnly: true })
    expect(line.hi - line.lo, '收盘价档没收窄区间').toBeLessThan(candle.hi - candle.lo)
    const { lo, hi } = visibleRange(v, s)
    const closes = span(lo, hi).map(i => s.close[i])
    expect(closes.every(c => c >= line.lo && c <= line.hi), '有收盘价掉出区间').toBe(true)
    const maxHigh = maxOf(span(lo, hi).map(i => s.high[i]))
    if (maxHigh > maxOf(closes)) expect(line.hi).toBeLessThan(candle.hi)
    expect(priceRange(v, s, { paneHeight: 400, closeOnly: false })).toEqual(candle)
  })
})
