/* 手机网页版 · 自选行的 24 小时迷你走势与药丸闪动（照 iOS Symbols/FavoriteTrend.swift，2026-10-08）
 *
 * 走势线：价格与涨跌药丸之间一条 44×20 的折线，取最近 24 小时的 15 分钟收盘（97 根），尾点接最新价；
 * 按这 24 小时的涨跌用涨 / 跌色描 1.5，不填充、不垫底。没取到就空着那 44，不摆占位、不闪。
 * 设置 › 通用「自选走势线」一颗全局开关（st.favoritesTrend，出厂开，跟账号同步）。
 * 药丸闪：同一只的价真动了一口时，按这一口的方向闪 150ms（底提亮一档再落回去）；换品种、换列表 / 分类都不算。
 *
 * 这一份是纯的（不碰 DOM、不取数），取数与缓存在 pages/favoritesTrend.ts。
 */

/** 一只品种最近 24 小时的走势：起点（24 小时前那根的开盘）和其后每根的收盘 */
export interface FavoriteTrend { open: number; closes: number[] }
/** 截走势要的那几格（chart/calc 的 Bar 子集） */
export interface TrendBar { t: number; o: number; c: number }

/** 窗口长度与根数上限：24 小时 15 分钟线，多给一根让窗口左缘正好落在 24 小时前 */
export const TREND_WINDOW_MS = 24 * 3_600_000
export const TREND_CAPACITY = 97
export const TREND_IV = '15m'
/** 走势线那一格：44×20、线宽 1.5（56 时 402 宽的机型上把价格挤截了，iOS 2026-10-08 收到 44） */
export const TREND_W = 44, TREND_H = 20, TREND_LW = 1.5

const ok = (x: number): boolean => Number.isFinite(x) && x > 0

/** 从一段 K 线里截出最近 24 小时。少于两根、价不成数时返回 null（画不出线就不画） */
export function makeTrend(bars: readonly TrendBar[], now: number): FavoriteTrend | null {
  const start = now - TREND_WINDOW_MS - 900_000
  const kept = bars.filter(b => b.t >= start).slice(-TREND_CAPACITY)
  if (kept.length < 2 || !ok(kept[0].o)) return null
  const closes = kept.map(b => b.c)
  if (!closes.every(ok)) return null
  return { open: kept[0].o, closes }
}

/** 画出来的那一串点：尾点换成最新价（有的话），线的右端和价格那一格说的是同一口价 */
export function trendPoints(t: FavoriteTrend, last: number | null | undefined): number[] {
  if (last == null || !ok(last) || !t.closes.length) return t.closes
  const out = t.closes.slice()
  out[out.length - 1] = last
  return out
}

/** 24 小时涨跌（比值，0.012 = +1.2%）：尾点对起点 */
export function trendChange(t: FavoriteTrend, last: number | null | undefined): number {
  const p = trendPoints(t, last)
  const end = p.length ? p[p.length - 1] : t.open
  return end / t.open - 1
}

/** 涨 / 跌 / 平：平盘用弱墨 */
export type TrendInk = 'up' | 'down' | 'flat'
export const trendInk = (change: number): TrendInk => change > 0 ? 'up' : change < 0 ? 'down' : 'flat'

const r2 = (x: number): string => String(Math.round(x * 100) / 100)

/** 折线本身：点按时间等距铺满宽，纵向按这一段的高低点铺满高（上下各留半根线宽，不被裁）；一条直线画在正中 */
export function trendPath(points: readonly number[], w = TREND_W, h = TREND_H, lw = TREND_LW): string {
  if (points.length < 2) return ''
  let lo = Infinity, hi = -Infinity
  for (const v of points) { if (v < lo) lo = v; if (v > hi) hi = v }
  const inset = lw / 2, ih = h - inset * 2, step = w / (points.length - 1), span = hi - lo
  let d = ''
  for (let i = 0; i < points.length; i++) {
    const y = span > 0 ? inset + ((hi - points[i]) / span) * ih : h / 2
    d += (i ? 'L' : 'M') + r2(i * step) + ' ' + r2(y)
  }
  return d
}

/** 走势线那一格里的 SVG；没有走势时是空串（那一格照样占着 44，行里其余几格不挪） */
export function trendSVG(t: FavoriteTrend | null | undefined, last: number | null | undefined): string {
  if (!t) return ''
  const d = trendPath(trendPoints(t, last))
  if (!d) return ''
  return `<svg width="${TREND_W}" height="${TREND_H}" viewBox="0 0 ${TREND_W} ${TREND_H}" aria-hidden="true"><path class="${trendInk(trendChange(t, last))}" d="${d}"/></svg>`
}
