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
/** 主图最少要多高：160 px 与 40% 取大（画布本身不够高时就是整块） */
export function mainMinH(H: number): number { return Math.min(H, Math.max(MAIN_MIN_PX, Math.ceil(H * MAIN_MIN_FRAC))) }
/** 自动分配（没拖过分隔线）时 K 线主图至少留这么高才往下加副图：格子矮了宁可只画主图 + 成交量，也不把 K 线压扁
 *  （UI 审查 2026-10-10 A3：十六图里三个副图把 K 线压到 120 px）。按格子实际像素判，不按格数——
 *  同一个十六图，大屏格子够高就留副图，小屏就不留；格数变了只是触发重算的时机 */
export const MAIN_KEEP_PX = 280
/** 自动分配时主图至少多高：280 px 与 40% 取大（画布本身不够高时就是整块） */
export function mainKeepH(H: number): number { return Math.min(H, Math.max(MAIN_KEEP_PX, Math.ceil(H * MAIN_MIN_FRAC))) }
/** 这么高的画布放得下几个副图（每个 ≥ 56，主图 ≥ mainKeepH），最多 MAX_SUBS 个 */
export function fitSubs(H: number): number { return clamp(Math.floor((H - mainKeepH(H)) / SUB_FIT_MIN), 0, MAX_SUBS) }
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
  // 放得下（主图 ≥ 下限、每个副图 ≥ 56）时副图合计夹在这两头之间：主图不被挤到下限以下，副图也不被比例压到 56 以下。
  // 下限：没拖过按 mainKeepH（280 / 40%，和 fitSubs 同一口径），拖过的按用户的手（mainMinH，160 / 40%）
  const room = H - (custom ? mainMinH(H) : mainKeepH(H)), need = subs.length * SUB_FIT_MIN
  if (need <= room) cap = clamp(cap, need, room)
  const floor = Math.min(SUB_MIN_H, Math.floor(cap / subs.length))
  const def = subDefaultH(H)
  let hs = subs.map(id => { const r = ratios?.[id]; return typeof r === 'number' && isFinite(r) && r > 0 ? r * H : def })
  hs = hs.map(h => Math.max(floor, h))
  const sum = hs.reduce((a, b) => a + b, 0)
  if (sum > cap) hs = hs.map(h => Math.max(floor, h * cap / sum))
  // 副图向下取整、零头归主图：四舍五入时几个副图各进 0.5 会把主图挤到下限以下 1 px（实测九图 K 线 279 < 280）
  const r = hs.map(h => Math.floor(h))
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
/** 门槛（按格子尺寸；2026-10-10 起格子里不再有底栏，整页只有图表区下面一条全局底栏）。
 *  app.css「多图格子降级」一段的类名与数值和这里对应：c-tiny：宽 < CELL_TINY_W，回放条收起倍速。
 *  成交量和副图同一套像素规则（2026-10-10 起，原来按格宽 < 420 一刀切）：它是第一优先、垫在主图底部 VOL_FRAC 高的一条，
 *  只要 K 线主图保得住 mainKeepH（≥ 280）且那一条 ≥ VOL_MIN_H 就画；主图都保不住才不画。高度只按主图高算，不看用户存过的副图比例。
 *  价格轴上挂不挂指标当前值标签也按格子像素判：画布高 < AXIS_IND_MIN_H 或宽 < CELL_COMPACT_W 时只留最新价与十字线读数
 *  （UI 审查 2026-10-10 A4；原来按格数 ≥ 4 一刀切，2026-10-10 改成跟着实际尺寸走） */
export const CELL_COMPACT_W = 480
export const CELL_TINY_W = 420
/** 成交量条占主图高的比例（chart.ts drawVolume 用它）与最矮多高 */
export const VOL_FRAC = 0.25
export const VOL_MIN_H = 40
/** 画布高 H（去掉时间轴）放不放得下成交量：主图保得住 MAIN_KEEP_PX、成交量条 ≥ VOL_MIN_H */
export function volFits(H: number): boolean { return H >= MAIN_KEEP_PX && Math.floor(mainKeepH(H) * VOL_FRAC) >= VOL_MIN_H }
export const CELL_SHORT_H = 360
export const CELL_DENSE_H = 500
export const AXIS_IND_MIN_H = 480

export type LegendMode = 'full' | 'dense' | 'compact'
export interface Degrade {
  /** 最多画几个副图（按用户 subs 顺序取前几个）；0 = 只留主图 */
  subs: number
  /** 图例：full 每个指标一行；dense 主图指标并成一行（悬停展开）；compact 只留品种与周期 */
  legend: LegendMode
  /** 价格轴等画布字号档：12 → 11（字号令牌 --t12 / --t11 的档位，实际像素由 chart/canvasType.ts canvasPx 从令牌取） */
  font: number
  /** 成交量照画 */
  vol: boolean
  /** 价格轴上挂指标当前值标签（主图均线、副图 MACD / RSI…）；关着只留最新价、提醒、对比与十字线读数 */
  axisInd: boolean
}
export const FULL: Degrade = { subs: MAX_SUBS, legend: 'full', font: 12, vol: true, axisInd: true }
/** 格子 w × h 的降级档。副图按画布剩下的高逐个放（主图 ≥ 280 / 40%、每个副图 ≥ 56；放不下就只画主图 + 成交量）；
 *  宽 < 480 或高 < 360：图例只留品种周期、字号小一档；高 < 500：主图指标图例并成一行；主图保不住 280 不画成交量（volFits）；
 *  画布高 < 480 或宽 < 480：价格轴不挂指标标签。 */
export function degradeFor(w: number, h: number): Degrade {
  const H = h - AXIS_H
  const subs = H > 0 ? fitSubs(H) : 0
  const compact = w < CELL_COMPACT_W || h < CELL_SHORT_H
  const legend: LegendMode = compact ? 'compact' : h < CELL_DENSE_H ? 'dense' : 'full'
  return { subs, legend, font: compact ? 11 : 12, vol: volFits(H), axisInd: H >= AXIS_IND_MIN_H && w >= CELL_COMPACT_W }
}
/** 格子的收缩类（watchCell 按它 toggle；回放条在窄格里收起倍速） */
export function cellClasses(w: number, _h: number): Record<'c-tiny', boolean> {
  return { 'c-tiny': w < CELL_TINY_W }
}
