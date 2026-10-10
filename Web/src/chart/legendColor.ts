/* Hkline Web · 图例读数的「文字版」颜色（2026-10-10 审查 B2）
 *
 * 画布上的 K 线 / 均线 / 副图线是 AICoin 那套颜色，一律不动；可同一个颜色拿来当图例文字，在浅色柔白底上读不清
 * （MA10 黄 #F6C309 对 --surface #F8FAF8 只有 1.6:1，MACD 柱浅青 #B2DFDB 1.3:1）。
 * 这里给图例文字另取一个「文字版」：在 OKLCH 里保持色相与（尽量）彩度，只把明度压暗（深色下提亮），
 * 一步 0.01 地走，直到对这一档主题下三套皮肤的 --surface 全部 ≥ 4.5:1（规范第 5b 节）。
 * 出界的颜色先降彩度回到 sRGB 里，色相不动。认不出的写法（空串、var(...)、color-mix）原样返回。 */

/** 三套皮肤的内容底 --surface（规范第 1 节表），图例就压在它上面 */
export const LEGEND_SURFACES = {
  light: ['#F8FAF8', '#F8F9FA', '#FBF8F4'],
  dark: ['#121815', '#14171D', '#18120C'],
} as const

export const LEGEND_MIN_CONTRAST = 4.5

type RGB = [number, number, number]

/** #rgb / #rgba / #rrggbb / #rrggbbaa / rgb() / rgba()（逗号或空格写法）→ 0–255；认不出返回 null（透明度忽略：文字一律实色） */
export function parseColor(c: string): RGB | null {
  const s = c.trim().toLowerCase()
  let m = /^#([0-9a-f]{3,8})$/.exec(s)
  if (m) {
    const h = m[1]
    if (h.length === 3 || h.length === 4) return [0, 1, 2].map(i => parseInt(h[i] + h[i], 16)) as RGB
    if (h.length === 6 || h.length === 8) return [0, 2, 4].map(i => parseInt(h.slice(i, i + 2), 16)) as RGB
    return null
  }
  m = /^rgba?\(\s*([\d.]+)[\s,]+([\d.]+)[\s,]+([\d.]+)/.exec(s)
  if (m) return [+m[1], +m[2], +m[3]].map(v => Math.max(0, Math.min(255, v))) as RGB
  return null
}

const lin = (v: number): number => { const x = v / 255; return x <= 0.04045 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4 }
const gam = (x: number): number => 255 * (x <= 0.0031308 ? 12.92 * x : 1.055 * x ** (1 / 2.4) - 0.055)

/** WCAG 相对亮度 */
export function luminance(c: RGB): number { const [r, g, b] = c.map(lin); return 0.2126 * r + 0.7152 * g + 0.0722 * b }
/** WCAG 对比度（1–21） */
export function contrast(a: RGB, b: RGB): number { const la = luminance(a), lb = luminance(b); return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05) }

/** sRGB(0–255) → OKLCH [L 0–1, C, h 度] */
export function toOklch(c: RGB): [number, number, number] {
  const [r, g, b] = c.map(lin)
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
  const L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
  const A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
  const B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
  const h = (Math.atan2(B, A) * 180 / Math.PI + 360) % 360
  return [L, Math.hypot(A, B), h]
}

/** OKLCH → 线性 sRGB（可能越界） */
function oklchToLinear(L: number, C: number, h: number): RGB {
  const a = C * Math.cos(h * Math.PI / 180), b = C * Math.sin(h * Math.PI / 180)
  const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
  const m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
  const s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
  return [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
  ]
}
const inGamut = (x: RGB): boolean => x.every(v => v >= -1e-4 && v <= 1 + 1e-4)

/** OKLCH → sRGB 0–255；出界时保持 L、h，二分降彩度回到界内 */
export function fromOklch(L: number, C: number, h: number): RGB {
  let x = oklchToLinear(L, C, h)
  if (!inGamut(x)) {
    let lo = 0, hi = C
    for (let k = 0; k < 24; k++) { const mid = (lo + hi) / 2; if (inGamut(oklchToLinear(L, mid, h))) lo = mid; else hi = mid }
    x = oklchToLinear(L, lo, h)
  }
  return x.map(v => Math.round(gam(Math.max(0, Math.min(1, v))))) as RGB
}

const hex = (c: RGB): string => '#' + c.map(v => v.toString(16).padStart(2, '0')).join('').toUpperCase()

const minContrast = (c: RGB, bgs: readonly RGB[]): number => Math.min(...bgs.map(b => contrast(c, b)))
const BG: Record<'light' | 'dark', RGB[]> = {
  light: LEGEND_SURFACES.light.map(x => parseColor(x)!),
  dark: LEGEND_SURFACES.dark.map(x => parseColor(x)!),
}

const memo = new Map<string, string>()

/** 线色 → 图例文字色：已经够 4.5:1 的原样返回（大写 #RRGGBB）；不够的同色相压暗（浅色）/ 提亮（深色）到够为止 */
export function legendTextColor(lineColor: string, dark: boolean): string {
  const key = (dark ? 'd' : 'l') + lineColor
  const hit = memo.get(key); if (hit !== undefined) return hit
  const out = compute(lineColor, dark)
  if (memo.size > 512) memo.clear()
  memo.set(key, out)
  return out
}

function compute(lineColor: string, dark: boolean): string {
  const rgb = parseColor(lineColor)
  if (!rgb) return lineColor
  const bgs = BG[dark ? 'dark' : 'light']
  if (minContrast(rgb, bgs) >= LEGEND_MIN_CONTRAST) return hex(rgb)
  const [L0, C, h] = toOklch(rgb)
  const step = dark ? 0.01 : -0.01
  for (let L = L0 + step; L >= 0 && L <= 1; L += step) {
    const c = fromOklch(L, C, h)
    if (minContrast(c, bgs) >= LEGEND_MIN_CONTRAST) return hex(c)
  }
  return dark ? '#FFFFFF' : '#000000'
}
