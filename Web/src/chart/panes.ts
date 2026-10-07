/* Hkline Web · 图表窗格的高度分配与多图降级（纯逻辑，引擎与测试共用）
 *
 * 主图 / 副图：用户拖出来的副图高按「占画布高的比例」存（窗口变了跟着等比缩放），
 * 主图永远是剩下的全部，但不少于 40% 且不少于 160 px；每个副图不少于 80 px（画布矮时让到 56 px）。
 * 多图降级：按格子剩下的高度逐个留副图（先留用户排在前面的），放得下几个画几个；
 * 格子矮时主图指标图例并成一行，再小就只留品种周期、字号小一档，再窄就不画成交量。
 * 这里的门槛常量 JS 与 CSS 共用（app.css「多图格子降级」一段的数值照抄这里）。
 */
import { MAX_SUBS } from './calc'

const clamp = (v: number, lo: number, hi: number): number => Math.min(hi, Math.max(lo, v))

export const MAIN_MIN_FRAC = 0.4
export const SUB_MIN_H = 80
/** 主图最少 160 px（画布高去掉时间轴）；副图挤的时候最少 56 px */
export const MAIN_MIN_PX = 160
export const SUB_FIT_MIN = 56
/** 画布底部时间轴高（引擎 AXIS_H 用这个） */
export const AXIS_H = 28
/** 格子底栏高：常态 32，格子矮（< CELL_SHORT_H）时 28 —— app.css .cell-foot / .c-short */
export const FOOT_H = 32
export const FOOT_SHORT_H = 28
/** 主图最少要多高：160 px 与 40% 取大（画布本身不够高时就是整块） */
export function mainMinH(H: number): number { return Math.min(H, Math.max(MAIN_MIN_PX, Math.ceil(H * MAIN_MIN_FRAC))) }
/** 这么高的画布放得下几个副图（每个 ≥ 56，主图 ≥ mainMinH），最多 MAX_SUBS 个 */
export function fitSubs(H: number): number { return clamp(Math.floor((H - mainMinH(H)) / SUB_FIT_MIN), 0, MAX_SUBS) }
/** 副图默认高：画布高的 11%，夹在 96–136（和之前的固定分配一样） */
export function subDefaultH(H: number): number { return Math.round(clamp(H * 0.11, 96, 136)) }

/**
 * 各窗格高度（H = 画布高去掉时间轴）。ratios 是用户拖出来的副图比例，没有就用默认高。
 * 规则：每个副图 ≥ 80（画布太矮时让到能装下为止），副图合计 ≤ 60%（主图 ≥ 40%）；没拖过时合计 ≤ 55%（和原来一样）。
 * 返回 [主图, ...副图]，合计正好等于 H。
 */
export function paneHeights(H: number, subs: readonly string[], ratios: Readonly<Record<string, number>> | null | undefined): number[] {
  if (!subs.length) return [H]
  const custom = !!ratios && subs.some(id => typeof ratios[id] === 'number')
  let cap = Math.round(H * (custom ? 1 - MAIN_MIN_FRAC : 0.55))
  // 放得下（主图 ≥ mainMinH、每个副图 ≥ 56）时副图合计夹在这两头之间：主图不被挤到 160 以下，副图也不被比例压到 56 以下
  const room = H - mainMinH(H), need = subs.length * SUB_FIT_MIN
  if (need <= room) cap = clamp(cap, need, room)
  const floor = Math.min(SUB_MIN_H, Math.floor(cap / subs.length))
  const def = subDefaultH(H)
  let hs = subs.map(id => { const r = ratios?.[id]; return typeof r === 'number' && isFinite(r) && r > 0 ? r * H : def })
  hs = hs.map(h => Math.max(floor, h))
  const sum = hs.reduce((a, b) => a + b, 0)
  if (sum > cap) hs = hs.map(h => Math.max(floor, h * cap / sum))
  const r = hs.map(h => Math.round(h))
  return [H - r.reduce((a, b) => a + b, 0), ...r]
}

/**
 * 拖第 k 条分隔线（第 k-1 格与第 k 格之间，0 是主图）到 dy：两格之间挪高度，其余不动。
 * 返回新的各格高度（主图在前）。
 */
export function dragPane(hs: readonly number[], k: number, dy: number, H: number): number[] {
  const out = hs.slice()
  if (k < 1 || k >= hs.length) return out
  const total = hs[k - 1] + hs[k]
  const n = hs.length - 1, room = H - mainMinH(H)
  const fits = n * SUB_FIT_MIN <= room
  const subFloor = fits ? Math.min(SUB_MIN_H, Math.floor(room / n)) : Math.min(SUB_MIN_H, Math.floor(H * (1 - MAIN_MIN_FRAC) / n))
  const lo = k - 1 === 0 ? (fits ? mainMinH(H) : Math.ceil(H * MAIN_MIN_FRAC)) : subFloor
  const top = clamp(hs[k - 1] + dy, lo, total - subFloor)
  out[k - 1] = Math.round(top); out[k] = total - out[k - 1]
  return out
}
/** 各副图高 → 比例（存盘用） */
export function paneRatiosOf(ids: readonly string[], hs: readonly number[], H: number): Record<string, number> {
  const r: Record<string, number> = {}
  ids.forEach((id, i) => { r[id] = Math.round(hs[i + 1] / H * 10000) / 10000 })
  return r
}

// ------------------------------------------------------------ 多图降级
/** 门槛（按格子含底栏的尺寸）。app.css「多图格子降级」一段的类名与数值和这里一一对应：
 *  c-narrow：宽 < FOOT_TRIM_W，底栏只留前四个时间范围；
 *  c-tiny：宽 < CELL_NO_VOL_W，底栏时间范围全藏、不画成交量；
 *  c-short：高 < CELL_SHORT_H，底栏 28 高。 */
export const CELL_COMPACT_W = 480
export const CELL_NO_VOL_W = 420
export const CELL_SHORT_H = 360
export const CELL_DENSE_H = 500
export const FOOT_TRIM_W = 640

export type LegendMode = 'full' | 'dense' | 'compact'
export interface Degrade {
  /** 最多画几个副图（按用户 subs 顺序取前几个）；0 = 只留主图 */
  subs: number
  /** 图例：full 每个指标一行；dense 主图指标并成一行（悬停展开）；compact 只留品种与周期 */
  legend: LegendMode
  /** 价格轴等画布字号：12 → 11 */
  font: number
  /** 成交量照画 */
  vol: boolean
}
export const FULL: Degrade = { subs: MAX_SUBS, legend: 'full', font: 12, vol: true }
/** 格子底栏高 */
export function footH(h: number): number { return h < CELL_SHORT_H ? FOOT_SHORT_H : FOOT_H }
/** 格子（含底栏）w × h 的降级档。副图按画布剩下的高逐个放（主图 ≥ 160、每个副图 ≥ 56）；
 *  宽 < 480 或高 < 360：图例只留品种周期、字号小一档；高 < 500：主图指标图例并成一行；宽 < 420 不画成交量。 */
export function degradeFor(w: number, h: number): Degrade {
  const H = h - footH(h) - AXIS_H
  const subs = H > 0 ? fitSubs(H) : 0
  const compact = w < CELL_COMPACT_W || h < CELL_SHORT_H
  const legend: LegendMode = compact ? 'compact' : h < CELL_DENSE_H ? 'dense' : 'full'
  return { subs, legend, font: compact ? 11 : 12, vol: w >= CELL_NO_VOL_W }
}
/** 格子底栏的收缩类（watchCell 按它 toggle） */
export function cellClasses(w: number, h: number): Record<'c-narrow' | 'c-tiny' | 'c-short', boolean> {
  return { 'c-narrow': w < FOOT_TRIM_W, 'c-tiny': w < CELL_NO_VOL_W, 'c-short': h < CELL_SHORT_H }
}
