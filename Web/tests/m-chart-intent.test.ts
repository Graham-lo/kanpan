// 行情页 applyPending 的纯函数部分（index.ts resolveIntent）对照 Kanpan/Kanpan/Main/ChartHost.swift 的 applyPending：
// reset → ViewMath.reset(anchor)、switchInterval → ViewMath.switchInterval（不带 anchor，Swift 也不带）、
// resize / adopt → ViewMath.resized(anchor)、window → clampView(anchor)、keep → 不动。
// 切周期那两条语义断言照 KanpanCore/Tests/KanpanCoreTests/ReviewA5Tests.swift 的「用例 6」，数值与容差照抄。
import { beforeAll, describe, expect, it } from 'vitest'
import type { ViewAnchor } from '../src/m/chart/geometry'
import { AICoinBehavior, ViewMath, ViewWindow, clampView, defaultChartOptions } from '../src/m/chart/geometry'
import type { BarSeries, Interval } from '../src/m/chart/series'
import { INTERVALS } from '../src/m/chart/series'
import type { ChartState } from '../src/m/chart/state'
import { makeState, withViewport } from '../src/m/chart/state'
import { synthSeries } from './m-chart-fixtures'

// index.ts 连着行情、画图、订单流等模块，别的代理正在改；动态引入，只取 resolveIntent。
type Resolve = typeof import('../src/m/chart/index').resolveIntent
let resolveIntent: Resolve
beforeAll(async () => { resolveIntent = (await import('../src/m/chart/index')).resolveIntent })

const plotW = 390
const T0 = 1_700_000_000_000
const ANCHORS: ViewAnchor[] = ['right', 'center', 'left']

function state(series: BarSeries, view: ViewWindow, anchor: ViewAnchor = 'right'): ChartState {
  return makeState({
    series, view, symbol: { symbol: 'BTCUSDT', base: 'BTC', priceDecimals: 2 },
    options: { ...defaultChartOptions(), anchor },
  })
}
const same = (a: ViewWindow | null, b: ViewWindow) => {
  expect(a).not.toBeNull()
  expect(a!.to).toBe(b.to)
  expect(a!.span).toBe(b.span)
}

describe('ChartHost.applyPending · resolveIntent', () => {
  it('keep：不动视野', () => {
    const s = synthSeries(300, { interval: '1h', t0: T0 })
    expect(resolveIntent({ kind: 'keep' }, state(s, ViewWindow.fromTo(0, 1)), plotW, 4)).toBeNull()
  })

  it('reset：按用户的起始位置（右 / 中 / 左）贴住末根，根宽夹在 AICoin 上下限里', () => {
    for (const iv of INTERVALS) {
      const s = synthSeries(600, { interval: iv, t0: T0 })
      for (const anchor of ANCHORS) {
        for (const spacing of [0.5, 4, 8, 40, 400]) {
          const st = state(s, ViewWindow.fromTo(0, 1), anchor)
          const v = resolveIntent({ kind: 'reset' }, st, plotW, spacing)
          same(v, ViewMath.reset(s, plotW, spacing, anchor))
          const w = Math.min(AICoinBehavior.maximumSpacing, Math.max(AICoinBehavior.minimumSpacing, spacing))
          expect(Math.abs(v!.barSpacing(s.step, plotW) - w)).toBeLessThan(1e-9)
          expect(v!.to).toBeGreaterThanOrEqual(s.lastTime)
        }
      }
    }
  })

  it('reset：空序列给 0…1 的占位视野', () => {
    const empty = synthSeries(0, { interval: '1h', t0: T0 })
    const v = resolveIntent({ kind: 'reset' }, state(empty, ViewWindow.fromTo(5, 9)), plotW, 4)
    same(v, ViewWindow.fromTo(0, 1))
  })

  it('switchInterval：不看用户的起始位置（Swift 也不传 anchor），与 ViewMath.switchInterval 一致', () => {
    const s = synthSeries(600, { interval: '4h', t0: T0 })
    for (const anchor of ANCHORS) {
      for (const anchorRight of [null, s.lastTime - s.step * 40, s.lastTime + s.step * 1000, s.firstTime - s.step * 10]) {
        const v = resolveIntent({ kind: 'switchInterval', spacing: 8, anchorRight }, state(s, ViewWindow.fromTo(0, 1), anchor), plotW, 4)
        same(v, ViewMath.switchInterval(s, plotW, 8, anchorRight))
      }
    }
  })

  it('case6_historyAnchorSurvivesRoundTrip 用例 6：历史右缘切周期来回，右缘与根宽都不动', () => {
    const h1 = synthSeries(2000, { interval: '1h', t0: T0 })
    const h4 = synthSeries(800, { interval: '4h', t0: T0 })
    const spacing = 8
    const span = plotW / spacing * h1.step
    const history = clampView(new ViewWindow(h1.lastTime - span * 3, span), h1, plotW)
    const measured = history.barSpacing(h1.step, plotW)
    const toH4 = resolveIntent({ kind: 'switchInterval', spacing: measured, anchorRight: history.to }, state(h4, history), plotW, 4)!
    expect(Math.abs(toH4.barSpacing(h4.step, plotW) - 8)).toBeLessThan(1e-9)
    expect(Math.abs(toH4.to - history.to)).toBeLessThan(1e-6)
    const back = resolveIntent({ kind: 'switchInterval', spacing: toH4.barSpacing(h4.step, plotW), anchorRight: toH4.to }, state(h1, toH4), plotW, 4)!
    expect(Math.abs(back.barSpacing(h1.step, plotW) - 8)).toBeLessThan(1e-9)
    expect(Math.abs(back.to - history.to), '来回一趟右缘漂了').toBeLessThan(1e-6)
  })

  it('case6_followingLatestSticksToTheNewLastBar 用例 6：跟着最新的视野切周期永远贴住新末根', () => {
    const spacing = 8
    for (const iv of INTERVALS as Interval[]) {
      const s = synthSeries(600, { interval: iv, t0: T0 })
      const st = state(s, ViewWindow.fromTo(0, 1))
      const v = resolveIntent({ kind: 'switchInterval', spacing, anchorRight: null }, st, plotW, 4)!
      const latest = ViewMath.reset(s, plotW, spacing)
      expect(Math.abs(v.to - latest.to), `${iv}：跟随态没贴住新末根`).toBeLessThan(1e-9)
      expect(v.to, `${iv}：末根被切到视野外面去了`).toBeGreaterThanOrEqual(s.lastTime)
      const stale = resolveIntent({ kind: 'switchInterval', spacing, anchorRight: s.lastTime - s.step * 40 }, st, plotW, 4)!
      expect(stale.to, '拿具体右缘锚的那条路本该停在历史上').toBeLessThan(latest.to)
    }
  })

  it('resize / adopt：右缘不动、根宽照给定的来，再按起始位置夹一次', () => {
    const s = synthSeries(1200, { interval: '15m', t0: T0 })
    for (const anchor of ANCHORS) {
      const base = ViewMath.reset(s, plotW, 6, anchor)
      const history = clampView(new ViewWindow(s.lastTime - s.step * 300, base.span), s, plotW, anchor)
      for (const view of [base, history]) {
        for (const w of [plotW, 280, 844]) {
          for (const kind of ['resize', 'adopt'] as const) {
            const st = withViewport(state(s, ViewWindow.fromTo(0, 1), anchor), { view })
            const v = resolveIntent({ kind, spacing: 6 }, st, w, 4)
            same(v, ViewMath.resized(view, s, w, 6, anchor))
            expect(Math.abs(v!.barSpacing(s.step, w) - 6)).toBeLessThan(1e-9)
          }
        }
        const st = withViewport(state(s, ViewWindow.fromTo(0, 1), anchor), { view: history })
        expect(resolveIntent({ kind: 'resize', spacing: 6 }, st, plotW, 4)!.to).toBe(history.to)
      }
    }
    const empty = synthSeries(0, { interval: '1h', t0: T0 })
    const keep = ViewWindow.fromTo(3, 7)
    same(resolveIntent({ kind: 'resize', spacing: 6 }, state(empty, keep), plotW, 4), keep)
  })

  it('window：要的视野按起始位置夹进可达范围，越过末根右侧留白的被拉回', () => {
    const s = synthSeries(800, { interval: '1h', t0: T0 })
    for (const anchor of ANCHORS) {
      const st = state(s, ViewWindow.fromTo(0, 1), anchor)
      const latest = ViewMath.reset(s, plotW, 8, anchor)
      for (const want of [
        latest,
        new ViewWindow(s.lastTime - s.step * 200, latest.span),
        new ViewWindow(s.lastTime + s.step * 5000, latest.span),
        new ViewWindow(s.firstTime - s.step * 5000, latest.span),
      ]) {
        same(resolveIntent({ kind: 'window', view: want }, st, plotW, 4), clampView(want, s, plotW, anchor))
      }
      const far = resolveIntent({ kind: 'window', view: new ViewWindow(s.lastTime + s.step * 5000, latest.span) }, st, plotW, 4)!
      expect(Math.abs(far.to - latest.to)).toBeLessThan(1e-6)
    }
  })
})
