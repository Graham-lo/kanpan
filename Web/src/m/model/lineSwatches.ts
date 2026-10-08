/* 手机网页版 · 指标线可选色（照 iOS Palette.lineSwatchOptions / lift / readable，2026-10-08）
 *
 * 指标参数表里每条线可挑的颜色：这条线的出厂色排第一（界面上标「默认」），后面只从皮肤里派生——
 * 强调色、提亮一档的强调色、涨色、跌色、墨色，不再摆一排跟皮肤无关的通用色。画在图上的是线，
 * 按图形元素的 3:1 对图区底色收：不够的往墨色那边压深（浅色）/ 提亮（深色）；重复的只留一支（连出厂色一起比）。
 * 色块的标识按角色（default / accent / accentLift / up / down / ink）：色值随皮肤变，角色不变。
 * 纯函数，不碰 DOM；读令牌在调用方（panels.ts）。
 */
import { contrast, mix, rgba, type Hex } from '../chart/paint'

export type SwatchRole = 'default' | 'accent' | 'accentLift' | 'up' | 'down' | 'ink'
export interface LineSwatch { role: SwatchRole; hex: Hex }

/** 皮肤此刻的几支原色（都是 #RRGGBB）：bg = 图区底（--k-bg），up / down = 蜡烛本色（--k-up / --k-down，已按红涨绿涨对调） */
export interface SwatchSeed { accent: Hex; ink: Hex; up: Hex; down: Hex; bg: Hex }

const ROLE_NAME: Record<SwatchRole, string> = {
  default: '默认', accent: '强调色', accentLift: '浅强调色', up: '涨色', down: '跌色', ink: '墨色',
}
/** 色块的无障碍名（照 iOS IndicatorColorControl.roleName） */
export const swatchRoleName = (role: SwatchRole): string => ROLE_NAME[role] ?? '默认'

const byte = (n: number): string => Math.round(Math.min(1, Math.max(0, n)) * 255).toString(16).toUpperCase().padStart(2, '0')

/** 色相（0…360°，HSV）；灰色给 0（Palette.hue） */
export function hue(c: Hex): number {
  const v = rgba(c)
  const hi = Math.max(v.r, v.g, v.b), lo = Math.min(v.r, v.g, v.b), d = hi - lo
  if (d <= 0) return 0
  const h = hi === v.r ? (v.g - v.b) / d : hi === v.g ? 2 + (v.b - v.r) / d : 4 + (v.r - v.g) / d
  return (h * 60 + 360) % 360
}

/** 往亮里提一档：色相不动，饱和 ×(1 − 0.6·amount)、明度往白里走 amount（Palette.lift，HSB） */
export function lift(c: Hex, amount: number): Hex {
  const v = rgba(c)
  const hi = Math.max(v.r, v.g, v.b), lo = Math.min(v.r, v.g, v.b), d = hi - lo
  const h = hue(c) / 60
  const s = (hi > 0 ? d / hi : 0) * (1 - amount * 0.6)
  const b = hi + (1 - hi) * amount
  const chroma = b * s
  const x = chroma * (1 - Math.abs((h % 2) - 1))
  const seg = Math.trunc(h) % 6
  const [r1, g1, b1] = seg === 0 ? [chroma, x, 0] : seg === 1 ? [x, chroma, 0] : seg === 2 ? [0, chroma, x]
    : seg === 3 ? [0, x, chroma] : seg === 4 ? [x, 0, chroma] : [chroma, 0, x]
  const m = b - chroma
  return '#' + byte(r1 + m) + byte(g1 + m) + byte(b1 + m)
}

/** 一支色对所有底都够 `ratio` 为止，逐步往 ink 那边混（Palette.readable 的做法；线用 3、字用 4.5） */
export function readable(c: Hex, surfaces: Hex[], toward: Hex, ratio = 4.5): Hex {
  for (let step = 0; step <= 100; step++) {
    const cand = mix(c, toward, 1 - step / 100)
    if (surfaces.every(s => contrast(cand, s) >= ratio)) return cand
  }
  return toward.slice(0, 7).toUpperCase()
}

/** 指标线色板：出厂色第一，后面五支从皮肤派生、对图区底 ≥ 3:1、去重（Palette.lineSwatchOptions） */
export function lineSwatchOptions(fallback: Hex, seed: SwatchSeed): LineSwatch[] {
  const out: LineSwatch[] = [{ role: 'default', hex: fallback.slice(0, 7).toUpperCase() }]
  const derived: [SwatchRole, Hex][] = [
    ['accent', seed.accent], ['accentLift', lift(seed.accent, 0.42)], ['up', seed.up], ['down', seed.down], ['ink', seed.ink],
  ]
  for (const [role, c] of derived) {
    const v = readable(c, [seed.bg], seed.ink, 3)
    if (!out.some(o => o.hex.toUpperCase() === v.toUpperCase())) out.push({ role, hex: v })
  }
  return out
}
