// 移植自 KanpanCore/Tests/KanpanCoreTests/GestureMathTests.swift 与
// KanpanChart/Tests/KanpanChartTests/ChartGestureConstantsTests.swift。每条 it 的标题带 Swift 测试名。
//
// ChartGestureTests.swift（UIView 触摸驱动的状态机）不在这里：那一套要 UIKit 的触摸与 CADisplayLink，
// 网页这边对应的是 Pointer Events，不属于「数值测试」。
import { describe, expect, it } from 'vitest'
import {
  Chart, ViewMath, ViewTransition, ViewWindow, axisZoom, clampView, clampedCenter, isManualTransform,
  priceRange, priceTransform,
} from '../src/m/chart/geometry'
import { synthSeries } from './m-chart-fixtures'

describe('GestureMathTests（AICoin 统一手势算术）', () => {
  it('anchors · 历史区焦点缩放，右端缩放保持最新列尾贴右', () => {
    const s = synthSeries(1500)
    const w = 360
    const latest = ViewMath.reset(s, w, 4)
    const end = ViewMath.scaled(latest, s, w, 2, 100)
    expect(Math.abs(end.x(s.lastTime, w) - 356)).toBeLessThan(1e-6)
    const history = latest.dragged(500, w)
    const t = history.t(120, w)
    const zoom = ViewMath.scaled(history, s, w, 2, 120)
    expect(Math.abs(zoom.x(t, w) - 120)).toBeLessThan(1e-6)
    const back = ViewMath.scaled(zoom, s, w, 0.5, 120)
    expect(Math.abs(back.to - history.to)).toBeLessThan(0.001)
    expect(Math.abs(back.span - history.span)).toBeLessThan(0.001)
  })

  for (const width of [240, 360, 900]) {
    it(`latestEdgePull(width: ${width}) · 两端越界有限空白并回各自边界，历史中途不吸回`, () => {
      const series = synthSeries(1500)
      const latest = ViewMath.reset(series, width, 4)
      const history = latest.dragged(400, width)
      for (const finger of [-80, 80]) {
        const proposed = history.dragged(finger, width)
        const actual = ViewMath.dragging(proposed, series, width)
        expect(Math.abs(actual.to - proposed.to)).toBeLessThan(0.001)
        expect(actual.to).toBeLessThan(latest.to)
      }
      const oldest = clampView(latest.dragged(100000, width), series, width)
      const olderPull = ViewMath.dragging(oldest.dragged(100, width), series, width)
      expect(olderPull.to).toBeLessThan(oldest.to)
      expect((oldest.to - olderPull.to) / oldest.span * width).toBeLessThan(Math.min(32, width * 0.1))
      expect(Math.abs(clampView(olderPull, series, width).to - oldest.to)).toBeLessThan(0.001)
      let previous = 0
      for (const finger of [-10, -100, -10000]) {
        const pulled = ViewMath.dragging(latest.dragged(finger, width), series, width)
        const distance = (pulled.to - latest.to) / pulled.span * width
        expect(distance).toBeGreaterThan(previous)
        expect(distance).toBeLessThan(Math.min(32, width * 0.1))
        expect(pulled.span).toBe(latest.span)
        expect(Math.abs(clampView(pulled, series, width).to - latest.to)).toBeLessThan(0.001)
        previous = distance
      }
    })
  }

  it('latestEdgeRebound · 回弹有限时长单调回原边界，不改根宽或越过历史目标', () => {
    const end = new ViewWindow(1000, 500)
    const start = new ViewWindow(1200, 500)
    let previous = start.to
    for (let k = 0; k <= 20; k++) {
      const ms = k * 16
      const { view, done } = ViewTransition.rebound(start, end, ms)
      expect(view.to).toBeLessThanOrEqual(previous)
      expect(view.to).toBeGreaterThanOrEqual(end.to)
      expect(view.span).toBe(end.span)
      expect(done).toBe(ms >= 320)
      previous = view.to
    }
    expect(ViewTransition.rebound(start, end, 1000).view.equals(end)).toBe(true)
  })

  it('reverseAtLimit · 到达极限后反向捏合立即响应', () => {
    const s = synthSeries(1500)
    const v = ViewMath.reset(s, 360, 4)
    const maxed = ViewMath.scaled(v, s, 360, 100, 100)
    const back = ViewMath.scaled(maxed, s, 360, 0.9, 100)
    expect(Math.abs(back.barSpacing(s.step, 360) - 36)).toBeLessThan(1e-6)
  })

  it('yState · Y倍率与高度归一化，中心夹取，自动复位仅改Y', () => {
    expect(axisZoom(1, 100, 400)).toBe(0.5)
    expect(axisZoom(1, -10000, 400)).toBe(16)
    expect(axisZoom(1, 10000, 400)).toBe(0.03)
    expect(clampedCenter(50, 2)).toBe(1.5)
    expect(clampedCenter(-50, 2)).toBe(-0.5)
    // PriceTransform.reset()：TS 的变换是纯数据，复位就是把 zoom / centerFraction 写回默认，其余不动。
    const p = { ...priceTransform('log', 2, 0.7), inverted: true }
    const reset = { ...p, zoom: 1, centerFraction: 0.5 }
    expect(isManualTransform(p)).toBe(true)
    expect(isManualTransform(reset)).toBe(false)
    expect(reset.centerFraction).toBe(0.5)
    expect(reset.inverted).toBe(true)
    expect(reset.mode).toBe('log')
  })

  it('manualRange · 手动Y随新自动区间重算，不永久钉死旧价格', () => {
    const s = synthSeries(1500)
    const start = ViewMath.reset(s, 360, 4)
    const t = priceTransform('linear', 2, 0.7)
    for (const v of [start, start.dragged(300, 360)]) {
      const raw = priceRange(v, s)
      const actual = priceRange(v, s, { transform: t })
      const d = raw.hi - raw.lo
      expect(Math.abs((actual.hi - actual.lo) / d - 0.5)).toBeLessThan(1e-9)
      expect(Math.abs(((actual.hi + actual.lo) / 2 - raw.lo) / d - 0.7)).toBeLessThan(1e-9)
    }
  })
})

describe('ChartGestureConstantsTests（手势门槛）', () => {
  it('valuesAreUnchanged', async () => {
    // 动态引入：gesture.ts 连着订单流 / 画线的渲染模块，那几份在别的窗口里改，
    // 别让它们一时编不过就把上面的纯算术用例一起拖挂。
    const { ChartGesture } = await import('../src/m/chart/gesture')
    expect(ChartGesture.longPressMs).toBe(400)
    expect(ChartGesture.longPressSlopPt).toBe(6)
    expect(ChartGesture.panSlopPt).toBe(4)
    expect(ChartGesture.minPinchSpanPt).toBe(10)
    expect(ChartGesture.selectedHandlePt).toBe(22)
    expect(ChartGesture.selectedHandlePt).toBeGreaterThan(Chart.hitHandlePt)
    // 先引 gesture.ts、再取画线模块里顶层算好的门槛：gesture → renderer.orderflow → drawing → view.drawing 成环时，
    // view.drawing 顶层读到的 ChartGesture 是 undefined，整份 gesture.ts 一引就抛（门槛常量已拆到 gesture.constants.ts）
    const { DRAW_DRAG_SLOP_PT } = await import('../src/m/chart/view.drawing')
    expect(DRAW_DRAG_SLOP_PT).toBe(ChartGesture.panSlopPt * 2)
  })
})
