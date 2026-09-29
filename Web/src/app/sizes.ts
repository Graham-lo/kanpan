/* Hkline Web · 行情页各区域的尺寸（本机 localStorage「hkline-web-sizes-v1」，不进账号同步）
 *
 * 用户拖出来的宽高只跟这台电脑的屏幕有关，换台电脑没有意义，所以不放进 st（st 有一部分随账号同步）。
 * 这里只存「用户想要多大」；真正生效的尺寸由下面的纯函数按当前窗口夹一遍：
 * 窗口变小时按比例收，窗口变回来又回到用户拖的那个值，存着的数不被改写。
 *
 *   深度梯子列  宽  默认 240，160–480
 *   右侧面板    宽  默认 400，320–640
 *   底部抽屉    高  默认 280，160 到页面高的 60%
 *   主图 / 副图 高  存比例（占画布高）；主图 ≥ 40%、每个副图 ≥ 80 px
 *   侧栏各块    高  默认分配 + 用户覆盖（像素，按总高按比例铺满）
 *   多图网格    宽 / 高  每种布局各记一组列宽、行高比例
 */
import type { Layout } from './store'

export const SIZE_KEY = 'hkline-web-sizes-v1'

export interface RegionSpec { def: number; min: number; max: number }
export type RegionId = 'ladder' | 'panel' | 'drawer'
export const REGIONS: Record<RegionId, RegionSpec> = {
  ladder: { def: 240, min: 160, max: 480 },
  panel: { def: 400, min: 320, max: 640 },
  drawer: { def: 280, min: 160, max: Infinity }, // 上限按页面高的 60% 另算
}
/** 抽屉最高占页面（图表页）高的比例 */
export const DRAWER_MAX_FRAC = 0.6
/** 图表区至少留这么宽，梯子与面板再宽也不能把它挤没 */
export const CHART_MIN_W = 480
/** 图表区至少留这么高（抽屉拉高时） */
export const CHART_MIN_H = 240
/** 多图网格：一列至少这么宽、一行至少这么高（16 格在 2560×1440 上约 500×300，留足拖动余地） */
export const TRACK_MIN_W = 240
export const TRACK_MIN_H = 160

export interface GridSizes { cols?: number[]; rows?: number[] }
export interface Sizes {
  ladder?: number
  panel?: number
  drawer?: number
  /** 副图高占画布高（去掉时间轴）的比例，按副图 id */
  panes?: Record<string, number>
  /** 侧栏各块用户拖出来的高（像素），按块 id */
  side?: Record<string, number>
  /** 多图网格列宽 / 行高比例，按布局 */
  grid?: Partial<Record<Layout, GridSizes>>
}

export const clamp = (v: number, lo: number, hi: number): number => Math.min(hi, Math.max(lo, v))

/** 一个区域的值夹进它的范围；max 可以另给（抽屉按页面高） */
export function clampSize(v: number | undefined, spec: RegionSpec, max = spec.max): number {
  const x = typeof v === 'number' && isFinite(v) ? v : spec.def
  return Math.round(clamp(x, spec.min, Math.max(spec.min, max)))
}

/**
 * 横向：梯子列与面板的实际宽度。两者之和把图表区挤到 CHART_MIN_W 以下时按比例一起收，
 * 但各自不低于自己的下限（再小的窗口就由图表区让）。
 */
export function fitWidths(ladder: number | null, panel: number | null, room: number): { ladder: number | null; panel: number | null } {
  const l = ladder == null ? null : clampSize(ladder, REGIONS.ladder)
  const p = panel == null ? null : clampSize(panel, REGIONS.panel)
  const want = (l ?? 0) + (p ?? 0), can = room - CHART_MIN_W
  if (want <= can || want === 0) return { ladder: l, panel: p }
  const k = Math.max(0, can) / want
  return {
    ladder: l == null ? null : Math.round(Math.max(REGIONS.ladder.min, l * k)),
    panel: p == null ? null : Math.round(Math.max(REGIONS.panel.min, p * k)),
  }
}

/** 纵向：抽屉的实际高度（≤ 页面高 60%，且给图表区至少留 CHART_MIN_H） */
export function fitDrawer(drawer: number | undefined, pageH: number): number {
  const max = Math.min(Math.round(pageH * DRAWER_MAX_FRAC), pageH - CHART_MIN_H)
  return clampSize(drawer, REGIONS.drawer, max)
}

// ------------------------------------------------------------ 多图网格
/** n 条轨道的比例（和为 1）；存的不对就回平均 */
export function trackFracs(saved: number[] | undefined, n: number): number[] {
  if (Array.isArray(saved) && saved.length === n && saved.every(x => typeof x === 'number' && x > 0 && isFinite(x))) {
    const s = saved.reduce((a, b) => a + b, 0)
    return saved.map(x => x / s)
  }
  return Array.from({ length: n }, () => 1 / n)
}
/**
 * 把第 i 条与第 i+1 条轨道之间的线拖 dx 像素：只在这两条之间挪，每条不小于 minPx。
 * total = 轨道区总像素（不含间隙）。
 */
export function dragTracks(fr: readonly number[], i: number, dx: number, total: number, minPx: number): number[] {
  const out = fr.slice()
  if (i < 0 || i >= fr.length - 1 || total <= 0) return out
  const a = fr[i] * total, b = fr[i + 1] * total, sum = a + b
  const m = Math.min(minPx, sum / 2)
  const na = clamp(a + dx, m, sum - m)
  out[i] = na / total; out[i + 1] = (sum - na) / total
  return out
}

// ------------------------------------------------------------ 读写
function read(): Sizes {
  try { const v = JSON.parse(localStorage.getItem(SIZE_KEY) || '{}'); return v && typeof v === 'object' ? v : {} } catch { return {} }
}
export const sizes: Sizes = read()
/** 松手立刻落盘（本机） */
export function saveSizes(): void {
  try { localStorage.setItem(SIZE_KEY, JSON.stringify(sizes)) } catch { /* 存满了就算了 */ }
}
