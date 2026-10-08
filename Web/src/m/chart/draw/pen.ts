// 移植自 KanpanChart/DrawPen.swift（2026-10-08 视觉整改）。
/**
 * 画线的那支笔：颜色与浓淡全部从当前皮肤派生。
 *
 * - **一支笔**：线、填充、把手描边、端点、铃铛、放大镜，一条线上所有的墨都出自 `penColor` 这一个颜色。
 * - **跟皮肤**：`Drawing.color == null` 就是「跟皮肤」，画的时候取这一刻皮肤的强调色 `accent`，
 *   换皮肤、切深浅色线跟着变。存档格式不变，老线存着的显式色照旧按那支色画。
 * - **色板**：五格全部从皮肤来——跟皮肤、浅一阶、涨、跌、墨；第一格存 null，其余存挑的那一刻的色值。
 * - **浓淡**：不选中的线退后到 70%，选中的那条与正在画的那条 100%；「降低透明度」打开时一律 100%。
 */
import { mix, type ChartColors, type Hex } from '../paint'

/** 没在编辑的线画多浓。 */
export const DRAW_REST_ALPHA = 0.7

/** 这条线用哪支色。 */
export function penColor(stored: Hex | null | undefined, t: Pick<ChartColors, 'accent'>): Hex {
  return stored ?? t.accent
}

/** 强调色浅一阶：往白里掺三成。 */
export function penLighter(t: Pick<ChartColors, 'accent'>): Hex {
  return mix(t.accent, '#FFFFFF', 0.7)
}

export interface PenSwatch {
  role: 'skin' | 'light' | 'up' | 'down' | 'ink'
  name: string
  /** 选它之后写进 `Drawing.color` 的值（null = 跟皮肤）。 */
  stored: Hex | null
  shown: Hex
}

/** 色板，顺序固定：跟皮肤、浅一阶、涨、跌、墨；和前面某一格同色的那格不摆。 */
export function penSwatches(t: Pick<ChartColors, 'accent' | 'up' | 'down' | 'ink'>): PenSwatch[] {
  const light = penLighter(t)
  const all: PenSwatch[] = [
    { role: 'skin', name: '跟皮肤', stored: null, shown: t.accent },
    { role: 'light', name: '浅色', stored: light, shown: light },
    { role: 'up', name: '涨色', stored: t.up, shown: t.up },
    { role: 'down', name: '跌色', stored: t.down, shown: t.down },
    { role: 'ink', name: '墨色', stored: t.ink, shown: t.ink },
  ]
  const out: PenSwatch[] = []
  for (const s of all) {
    if (!out.some(o => o.shown.toUpperCase() === s.shown.toUpperCase())) out.push(s)
  }
  return out
}

/** 一条线此刻画多浓：降低透明度或选中 → 1，其余 → `DRAW_REST_ALPHA`。 */
export function penAlpha(id: string, selected: string | null | undefined, reduceTransparency: boolean): number {
  if (reduceTransparency || id === selected) return 1
  return DRAW_REST_ALPHA
}

/** 系统「降低透明度」是否打开（浏览器支持 `prefers-reduced-transparency` 时）。 */
export function prefersReducedTransparency(): boolean {
  return typeof matchMedia === 'function' && matchMedia('(prefers-reduced-transparency: reduce)').matches
}
