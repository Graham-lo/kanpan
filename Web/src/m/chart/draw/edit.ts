// 移植自 KanpanCore/Sources/KanpanCore/Drawing/DrawEdit.swift
//
// 画线的编辑动作：落点吸附、拖动、撤销重做。全是纯值语义，手势层只负责把屏幕坐标换算好丢进来。

import type { BarSeries } from '../series'
import { type Drawing, type DrawPart, type DrawPoint, cloneDrawing, partIndex } from './drawing'

/** 一次吸附的结果。`index == -1` 表示没吸（磁吸关着，或者根本没数据）。 */
export interface DrawSnap { point: DrawPoint; index: number }

/** 在数组里按 key 取最小（并列取第一个，同 Swift `min(by:)`）。 */
function minBy<T>(xs: readonly T[], key: (v: T) => number): T | undefined {
  let best: T | undefined, bestK = 0, first = true
  for (const x of xs) {
    const k = key(x)
    if (first || k < bestK) { best = x; bestK = k; first = false }
  }
  return best
}

/** 把一个自由的 (时间, 价格) 吸到最近那根 K 线的 OHLC 上（纯数据版，不看屏幕距离）。 */
export function snapDrawPointSimple(t: number, p: number, series: BarSeries, magnet: boolean): DrawSnap {
  if (!magnet || !(series.count > 0)) return { point: { t, p }, index: -1 }
  const i = series.index(t)
  const ohlc = [series.open[i], series.high[i], series.low[i], series.close[i]]
  const snapped = minBy(ohlc, v => Math.abs(v - p)) ?? p
  return { point: { t: series.time(i), p: snapped }, index: i }
}

/** 拖一条线：时间按毫秒平移，价格按像素平移（`priceShift` = p ↦ pOf(yOf(p) + dy)）。`from` 是按下那一刻的那条线。 */
export function movedDrawing(from: Drawing, part: DrawPart, dt: number, priceShift: (p: number) => number): Drawing {
  if (from.locked) return from
  const d = cloneDrawing(from)
  const index = partIndex(part)
  for (let i = 0; i < d.points.length; i++) {
    if (index != null && index !== i) continue
    d.points[i] = {
      t: from.points[i].t + (from.kind === 'hline' ? 0 : dt),
      p: from.kind === 'vline' ? from.points[i].p : priceShift(from.points[i].p),
    }
  }
  return d
}

/** 吸住之后要离开多远才松开（屏幕 pt）。吸上去那一步用的是 radius（10pt）。 */
export const DRAW_SNAP_RELEASE_PT = 16
/** 换吸另一个 OHLC 的让步（屏幕 pt）。 */
const DRAW_SNAP_HOP_PT = 1

/**
 * 弱磁吸：比的是屏幕距离，反转轴、对数轴下都成立。`current` 是上一帧吸到的点，用来做迟滞：
 * ① 先算候选（手指底下那根的 OHLC，横纵都在 radius 之内）；② 已吸住且没走出 release：
 * 候选明显更近才跳，否则原样还回上一帧那个点；③ 否则有候选吸候选，没有就原样落点。
 */
export function snapDrawPoint(t: number, p: number, series: BarSeries, magnet: boolean,
  xOf: (t: number) => number, yOf: (p: number) => number,
  radius = 10, current: DrawSnap | null = null, release: number = DRAW_SNAP_RELEASE_PT): DrawSnap {
  const raw: DrawSnap = { point: { t, p }, index: -1 }
  if (!magnet || !(series.count > 0)) return raw
  const fx = xOf(t), fy = yOf(p)
  const reach = (s: DrawSnap): number => Math.hypot(xOf(s.point.t) - fx, yOf(s.point.p) - fy)

  let candidate: DrawSnap | null = null
  const i = series.index(t)
  const time = series.time(i)
  if (Math.abs(xOf(time) - fx) <= radius) {
    const prices = [series.open[i], series.high[i], series.low[i], series.close[i]]
    const near = minBy(prices, v => Math.abs(yOf(v) - fy))
    if (near !== undefined && Math.abs(yOf(near) - fy) <= radius) candidate = { point: { t: time, p: near }, index: i }
  }

  if (current && current.index >= 0) {
    const held = reach(current)
    if (held <= release) {
      if (candidate && reach(candidate) < held - DRAW_SNAP_HOP_PT) return candidate
      return current
    }
  }
  return candidate ?? raw
}

/** 画线的撤销栈：存每次改动之前的整份快照。 */
export class DrawHistory {
  static readonly depth = 50
  past: Drawing[][] = []
  future: Drawing[][] = []

  get canUndo(): boolean { return this.past.length > 0 }
  get canRedo(): boolean { return this.future.length > 0 }

  clone(): DrawHistory {
    const h = new DrawHistory()
    h.past = this.past.slice(); h.future = this.future.slice()
    return h
  }

  /** 改之前记一笔。任何新动作都会把「重做」那一摞作废。 */
  commit(before: Drawing[]): void {
    this.past.push(before)
    if (this.past.length > DrawHistory.depth) this.past.splice(0, this.past.length - DrawHistory.depth)
    this.future = []
  }

  /** 撤销。`current` 会被推进「重做」那摞。 */
  undo(current: Drawing[]): Drawing[] | null {
    const prev = this.past.pop()
    if (prev === undefined) return null
    this.future.push(current)
    return prev
  }

  redo(current: Drawing[]): Drawing[] | null {
    const next = this.future.pop()
    if (next === undefined) return null
    this.past.push(current)
    return next
  }

  clear(): void {
    this.past = []
    this.future = []
  }
}
