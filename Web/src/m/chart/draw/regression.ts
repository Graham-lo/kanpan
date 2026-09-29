// 移植自 KanpanCore/Sources/KanpanCore/Drawing/DrawRegression.swift
//
// 「回归通道」只让用户圈起止两点，中心线是区间里那段收盘价的最小二乘拟合，通道宽度取
// 拟合残差的标准差。拟合只在落笔那一刻做一次，结果落成 a / b（中心线两端）+ c（通道宽度
// 那一侧），之后它就是一条普通的三点线。

import type { BarSeries } from '../series'
import type { DrawPoint } from './drawing'

/** 把用户圈的两点补成回归通道的三点。K 线不够（少于 3 根）→ null。 */
export function fittedRegression(anchors: readonly DrawPoint[], series: BarSeries, sigma = 2): DrawPoint[] | null {
  if (anchors.length !== 2) return null
  const lo = Math.min(anchors[0].t, anchors[1].t), hi = Math.max(anchors[0].t, anchors[1].t)
  if (!Number.isFinite(lo) || !Number.isFinite(hi) || !(hi > lo) || series.count <= 0) return null

  const xs: number[] = [], ys: number[] = []
  for (let i = 0; i < series.count; i++) {
    const t = series.time(i)
    if (!(t >= lo && t <= hi)) continue
    const close = series.close[i]
    if (!Number.isFinite(close)) continue
    xs.push(t); ys.push(close)
  }
  if (xs.length < 3) return null

  // 时间戳是 1.7e12 量级，先把横轴平移到均值再拟合，免得 Σx² 吃掉有效数字。
  const mx = xs.reduce((s, x) => s + x, 0) / xs.length
  const my = ys.reduce((s, y) => s + y, 0) / ys.length
  let sxx = 0, sxy = 0
  for (let i = 0; i < xs.length; i++) { const dx = xs[i] - mx; sxx += dx * dx; sxy += dx * (ys[i] - my) }
  if (!(sxx > 0) || !Number.isFinite(sxx) || !Number.isFinite(sxy)) return null
  const slope = sxy / sxx
  if (!Number.isFinite(slope)) return null
  const fit = (t: number): number => my + slope * (t - mx)

  let sse = 0
  for (let i = 0; i < xs.length; i++) { const e = ys[i] - fit(xs[i]); sse += e * e }
  // 样本标准差（n-1）。
  const sd = Math.sqrt(sse / Math.max(1, xs.length - 1))
  if (!Number.isFinite(sd)) return null

  const a = { t: lo, p: fit(lo) }
  const b = { t: hi, p: fit(hi) }
  const c = { t: hi, p: fit(hi) + Math.max(sd * sigma, 0) }
  if (!Number.isFinite(a.p) || !Number.isFinite(b.p) || !Number.isFinite(c.p)) return null
  return [a, b, c]
}
