// 移植自 KanpanCore/Drawing/DrawReference.swift（2026-10-08 视觉整改）。
/**
 * 画线列表里那一行「距现价」：一条线的代表价，和它离最新价有多远。
 *
 * 代表价 = 线上离最新价最近的那个价位：
 * - 能长出提醒的那几种照 `AlertGeometry` 摊出来的线取——每条线取它在最新那根 K 线的时刻上的价；
 *   那一刻落在线段外（线没开延长）就取时间上离它最近的端点；摊出好几条的取离最新价最近的那条。
 * - 其余（垂直线、文字、形态……）取锚点里离最新价最近的那个价。
 */
import type { Drawing } from './drawing'
import { AlertGeometry, alertLinePrice } from './alert'

/** 最新那根 K 线在 `t`（毫秒）、最新价 `latest` 时，这条线的代表价；一个可用的价都没有就是 null。 */
export function referencePrice(d: Drawing, t: number, latest: number): number | null {
  let candidates: number[] = []
  const lines = AlertGeometry.lines(d)
  if (lines) {
    for (const line of lines) {
      const p = alertLinePrice(line, t)
      if (p != null) { candidates.push(p); continue }
      const sorted = [...line.points].sort((a, b) => a.t - b.t)
      const first = sorted[0], last = sorted[sorted.length - 1]
      if (!first || !last) continue
      candidates.push(t <= first.t ? first.p : last.p)
    }
  }
  if (!candidates.length) candidates = d.points.map(p => p.p)
  const finite = candidates.filter(Number.isFinite)
  if (!Number.isFinite(latest)) return finite[0] ?? null
  let best: number | null = null
  for (const p of finite) if (best == null || Math.abs(p - latest) < Math.abs(best - latest)) best = p
  return best
}

/** 代表价离最新价多远（%）：线在价上方为正、下方为负。算不出来是 null。 */
export function distancePercent(d: Drawing, t: number, latest: number): number | null {
  if (!Number.isFinite(latest) || latest === 0) return null
  const p = referencePrice(d, t, latest)
  if (p == null) return null
  const pct = (p / latest - 1) * 100
  return Number.isFinite(pct) ? pct : null
}
