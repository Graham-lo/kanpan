/* Hkline Web · 行情页各区域的尺寸（本机 localStorage「hkline-web-sizes-v1」）
 *
 * 像素尺寸（梯子宽、面板宽、抽屉高、侧栏各块高）只跟这台电脑的屏幕有关，留本机、不进账号同步；
 * 比例（主图 / 副图高、多图网格的列宽行高）换台屏幕照样成立，2026-10-10 起登记进 webPrefs 的 panes / grid 两块随账号走。
 * 这里只存「用户想要多大」；真正生效的尺寸由下面的纯函数按当前窗口夹一遍：
 * 窗口变小时按比例收，窗口变回来又回到用户拖的那个值，存着的数不被改写。
 *
 *   深度梯子列  宽  默认 240，160–480
 *   右侧面板    宽  默认跟视口走（panelDefault：1440 → 280、2560 → 320、封顶 400），280–640
 *   底部抽屉    高  默认 280，160 到页面高的 60%；四块排不下一行折成几排时，
 *                   至少给到「抽屉头 + 排数 × 240」，此时 60% 上限放开（图表区仍留 240），
 *                   这是临时托底、不写回存值：回到一排放得下时恢复用户拖的高度
 *   主图 / 副图 高  存比例（占画布高）；主图 ≥ 40%、每个副图 ≥ 80 px
 *   侧栏各块    高  默认分配 + 用户覆盖（像素，按总高按比例铺满）
 *   多图网格    宽 / 高  每种布局各记一组列宽、行高比例
 */
import type { Layout } from './store'
import { registerWebPref, webPrefsTouched } from '../sync/webPrefs'
import type { Json } from '../sync/types'

export const SIZE_KEY = 'hkline-web-sizes-v1'

export interface RegionSpec { def: number; min: number; max: number }
export type RegionId = 'ladder' | 'panel' | 'drawer'
export const REGIONS: Record<RegionId, RegionSpec> = {
  ladder: { def: 240, min: 160, max: 480 },
  // 出厂宽跟视口走（panelDefault）；用户拖过的宽照旧优先
  panel: { get def() { return panelDefault(globalThis.innerWidth || 2560) }, min: 280, max: 640 },
  drawer: { def: 280, min: 160, max: Infinity }, // 上限按页面高的 60% 另算
}
/** 右侧栏出厂宽：≈ 0.05 × 视口宽 + 192，夹在 280–400（1440 → 280、1920 → 288、2560 → 320、3840 → 384）。
 *  2026-10-10 用户：不同屏幕 / 分辨率下不写死，跟着视口走 */
export function panelDefault(vw: number): number { return Math.round(Math.min(400, Math.max(280, 0.05 * vw + 192))) }
/** 抽屉最高占页面（图表页）高的比例 */
export const DRAWER_MAX_FRAC = 0.6
/** 图表区至少留这么宽，梯子与面板再宽也不能把它挤没 */
export const CHART_MIN_W = 480
/** 图表区至少留这么高（抽屉拉高时） */
export const CHART_MIN_H = 240
/** 抽屉里四块折行时每排给的高（块本身最矮 220，留 20 给标题与边线） */
export const DRAWER_ROW_H = 240
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

/** 一行宽 width 的 flex-wrap 容器里，依次排外宽为 items 的块要几排（照浏览器的折行：放不下就换一排） */
export function wrapRows(width: number, items: readonly number[]): number {
  let rows = 0, used = 0
  for (const w of items) {
    if (rows === 0 || used + w > width + 0.5) { rows++; used = w } else used += w
  }
  return rows
}
/**
 * 抽屉折成几排时的托底高：need = 抽屉头 + 排数 × DRAWER_ROW_H（一排时传 0）。
 * 有效高 = max(用户的高, need)，need 可越过 60% 上限，但图表区仍至少留 CHART_MIN_H。
 */
export function fitDrawerWrapped(drawer: number | undefined, pageH: number, need: number): number {
  if (!(need > 0)) return fitDrawer(drawer, pageH)
  // 折行时 60% 上限一并放开（不然 900 高的窗口托底 512 已顶到 60%，往上再也拖不动），只守住图表区 240
  const h = clampSize(drawer, REGIONS.drawer, pageH - CHART_MIN_H)
  return Math.max(h, Math.min(Math.ceil(need), pageH - CHART_MIN_H))
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
 * 生效前把比例按像素再夹一遍：每条轨道不小于 minPx（总宽不够时平均分），多出来的从其余轨道按比例扣。
 * 拖动本身已经守着下限，这一步防的是存档被写坏（[1e9, 1] 这种）或窗口缩小后把某一格挤成一条缝。
 */
export function fitTracks(fr: readonly number[], total: number, minPx: number): number[] {
  const n = fr.length
  if (n < 2 || !(total > 0)) return fr.slice()
  const m = Math.min(minPx, total / n) / total
  let out = fr.slice()
  const pinned = new Array<boolean>(n).fill(false)
  for (;;) {
    const low = out.map((x, i) => !pinned[i] && x < m - 1e-9)
    if (!low.some(Boolean)) break
    low.forEach((b, i) => { if (b) pinned[i] = true })
    const k = pinned.filter(Boolean).length, rest = 1 - k * m
    const sum = out.reduce((a, x, i) => (pinned[i] ? a : a + x), 0)
    out = out.map((x, i) => (pinned[i] ? m : sum > 0 ? x * rest / sum : rest / (n - k)))
  }
  return out
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
const isObj = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v)
const num = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v)
/** 正数表（副图比例、侧栏块高）：非数、非正的项丢掉 */
function posMap(v: unknown, max: number): Record<string, number> | undefined {
  if (!isObj(v)) return undefined
  const out: Record<string, number> = {}
  for (const [k, x] of Object.entries(v)) if (num(x) && x > 0 && x <= max) out[k] = x
  return Object.keys(out).length ? out : undefined
}
/**
 * 读盘整理：形状不对的项丢掉（回默认），数值范围交给用的地方去夹。
 * 2026-09-29 压测：存档里 grid 是数字、grid['4'] 是字符串时，拖多图分隔线在 `grid[layout] ||= {}` 上抛错，
 * 分隔线从此拖不动；side 是数组时侧栏块按下标记高。本机存档可能被别的版本、扩展或手改写坏，读进来先洗一遍。
 */
export function normalizeSizes(raw: unknown): Sizes {
  if (!isObj(raw)) return {}
  const out: Sizes = {}
  for (const k of ['ladder', 'panel', 'drawer'] as const) if (num(raw[k])) out[k] = raw[k] as number
  const panes = posMap(raw.panes, 1); if (panes) out.panes = panes
  const side = posMap(raw.side, 100_000); if (side) out.side = side
  if (isObj(raw.grid)) {
    const grid: Partial<Record<Layout, GridSizes>> = {}
    for (const [lay, g] of Object.entries(raw.grid)) {
      if (!isObj(g)) continue
      const one: GridSizes = {}
      for (const ax of ['cols', 'rows'] as const) {
        const a = g[ax]
        if (Array.isArray(a) && a.length > 1 && a.every(x => num(x) && x > 0)) one[ax] = a as number[]
      }
      if (one.cols || one.rows) grid[lay as Layout] = one
    }
    if (Object.keys(grid).length) out.grid = grid
  }
  return out
}
function read(): Sizes {
  try { return normalizeSizes(JSON.parse(localStorage.getItem(SIZE_KEY) || '{}')) } catch { return {} }
}
export const sizes: Sizes = read()
function store(): void { try { localStorage.setItem(SIZE_KEY, JSON.stringify(sizes)) } catch { /* 存满了就算了 */ } }
/** 松手立刻落盘（本机），比例那两块顺带排一次同步 */
export function saveSizes(): void { store(); webPrefsTouched() }

/** 比例只留四位小数（同步体积小一半，屏幕上差不到半个像素） */
const r4 = (x: number): number => Math.round(x * 1e4) / 1e4
/** 同步进来的比例：同读盘一样洗一遍；网格每种布局一组、每组最多 8 条轨道 */
export function cleanPanes(v: unknown): Record<string, number> | undefined { return posMap(v, 1) }
export function cleanGrid(v: unknown): Partial<Record<Layout, GridSizes>> | undefined {
  const g = normalizeSizes({ grid: v }).grid
  if (!g) return undefined
  for (const one of Object.values(g)) for (const ax of ['cols', 'rows'] as const) if (one?.[ax] && one[ax]!.length > 8) delete one[ax]
  return g
}
// 界面由同步层随后整块刷新（图表页 refreshWebPrefs：各格副图比例、网格重排）
registerWebPref('panes', {
  read: () => Object.fromEntries(Object.entries(sizes.panes ?? {}).map(([k, x]) => [k, r4(x)])),
  write: v => { const p = cleanPanes(v); if (p) sizes.panes = p; else delete sizes.panes; store() },
})
registerWebPref('grid', {
  read: () => Object.fromEntries(Object.entries(sizes.grid ?? {}).map(([k, g]) => [k, Object.fromEntries(Object.entries(g ?? {}).map(([ax, a]) => [ax, (a as number[]).map(r4)]))])) as Json,
  write: v => { const g = cleanGrid(v); if (g) sizes.grid = g; else delete sizes.grid; store() },
})
