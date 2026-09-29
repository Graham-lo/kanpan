// 移植自 KanpanCore/Sources/KanpanCore/Alerts/AlertGeometry.swift 与 Alert.swift 里的 AlertLine
// （只取画线覆盖层画「铃铛」要的那部分：一条线在某个时刻对应的价格）。

import type { Drawing, DrawingKind, DrawPoint } from './drawing'

export interface AlertLine { points: DrawPoint[]; extendLeft: boolean; extendRight: boolean }
const al = (points: DrawPoint[], extendLeft = false, extendRight = false): AlertLine => ({ points, extendLeft, extendRight })

const SUPPORTED: ReadonlySet<DrawingKind> = new Set<DrawingKind>([
  'hline', 'hray', 'trend', 'ray', 'extended', 'arrowLine', 'crossLine', 'channel', 'rectangle', 'fibonacci',
])
const MAX_LINES = 32

export const AlertGeometry = {
  supports: (k: DrawingKind): boolean => SUPPORTED.has(k),

  /** 画线换成提醒要盯的那几条线；不支持的工具 → null。 */
  lines(d: Drawing): AlertLine[] | null {
    if (!SUPPORTED.has(d.kind)) return null
    const pts = d.points
    const a = pts[0]
    if (!a) return null
    const b = pts[1]
    switch (d.kind) {
      case 'hline':
      case 'crossLine':
        return [al([a], true, true)]
      case 'hray':
        return [al([a], false, true)]
      case 'trend':
      case 'arrowLine':
        return b ? [al([a, b])] : null
      case 'ray':
        return b ? [al([a, b], false, true)] : null
      case 'extended':
        return b ? [al([a, b], true, true)] : null
      case 'rectangle': {
        if (!b) return null
        const t0 = Math.min(a.t, b.t), t1 = Math.max(a.t, b.t)
        const top = Math.max(a.p, b.p), bottom = Math.min(a.p, b.p)
        return [al([{ t: t0, p: top }, { t: t1, p: top }]), al([{ t: t0, p: bottom }, { t: t1, p: bottom }])]
      }
      case 'channel': {
        if (pts.length < 3) return null
        const bb = pts[1], c = pts[2]
        const dd = { t: c.t + (bb.t - a.t), p: c.p + (bb.p - a.p) }
        return [al([a, bb], true, true), al([c, dd], true, true)]
      }
      case 'fibonacci': {
        if (!b) return null
        const t0 = Math.min(a.t, b.t), t1 = Math.max(a.t, b.t)
        const lines: AlertLine[] = []
        for (const level of d.levels) {
          const value = b.p + (a.p - b.p) * level
          if (!Number.isFinite(value)) continue
          lines.push(al([{ t: t0, p: value }, { t: t1, p: value }]))
        }
        return lines.length === 0 ? null : lines.slice(0, MAX_LINES)
      }
      default:
        return null
    }
  },
}

/** 某一时刻这条线在哪个价；线没覆盖到这个时刻 → null。 */
export function alertLinePrice(line: AlertLine, t: number): number | null {
  const pts = line.points.slice().sort((x, y) => x.t - y.t)
  const first = pts[0], last = pts[pts.length - 1]
  if (!first || !last) return null
  if (pts.length === 1) {
    if (t < first.t) return line.extendLeft ? first.p : null
    if (t > first.t) return line.extendRight ? first.p : null
    return first.p
  }
  const extrapolate = (a: DrawPoint, b: DrawPoint): number => {
    const span = b.t - a.t
    if (span === 0) return b.p
    return b.p + (b.p - a.p) * (t - b.t) / span
  }
  if (t < first.t) return line.extendLeft ? extrapolate(pts[1], pts[0]) : null
  if (t > last.t) return line.extendRight ? extrapolate(pts[pts.length - 2], last) : null
  for (let i = 0; i < pts.length - 1; i++) {
    const a = pts[i], b = pts[i + 1]
    if (!(t >= a.t && t <= b.t)) continue
    const span = b.t - a.t
    if (!(span > 0)) return a.p
    return a.p + (b.p - a.p) * (t - a.t) / span
  }
  return last.p
}
