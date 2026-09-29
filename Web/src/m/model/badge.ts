/* 手机网页版 · 品种徽章与板块图标（照 CoinBadge.swift / BadgeTint / BadgeLine / LiuliBadge / SectorIcon）
 *
 * 画什么按品种走（badgeSpec + 认得出的牌子表），上什么色按皮肤走（BadgeTint：色相往 --accent 拢一成、
 * 饱和度与明度收进窄带）。输出 HTML 字符串，页面直接塞进 innerHTML。
 */
import brands from './coinBrands.json'
import { KNOWN } from './badgeKnown'
import { aliasKey, COPPER, DROP, FLAME, GAS, generated, GOLD_TOKENS, INGOT, MATERIAL, OILS, PRECIOUS, SPARE, spareIndex, type CoinSpec, type Part } from './badgeSpec'
import { sectorIconArt } from './sectorIcons'

type BrandJSON = Record<string, { from: string; to: string; inset?: number; mark: { text: string } | { parts: { d: string[]; stroke?: number }[] } }>
const BRANDS = brands as unknown as BrandJSON
const brandMemo = new Map<string, CoinSpec | null>()
function brand(key: string): CoinSpec | null {
  if (brandMemo.has(key)) return brandMemo.get(key)!
  const b = BRANDS[key]
  const out: CoinSpec | null = b ? {
    from: b.from, to: b.to, inset: b.inset ?? 0.62,
    mark: 'text' in b.mark ? { text: b.mark.text } : { parts: b.mark.parts.map(p => ({ d: p.d, stroke: p.stroke ?? null })) },
  } : null
  brandMemo.set(key, out)
  return out
}

/** 调用方手上的事实分类（照 SymbolClassification.Asset 用得到的两类） */
export type BadgeAsset = 'preciousMetal' | 'commodity' | null

const FX = /^(EUR|USD|GBP|JPY|AUD|CHF|CAD|NZD|CNH){2}$/
/** 品种表的 kind → 徽章用的事实分类：大宗里除了外汇都算实物商品 */
export function assetOf(kind: string | undefined, base: string): BadgeAsset {
  if (kind !== 'com') return null
  const b = base.toUpperCase()
  if (PRECIOUS.has(b)) return 'preciousMetal'
  return FX.test(b) ? null : 'commodity'
}

const specMemo = new Map<string, CoinSpec>()
/** 这个品种画什么记号（base 用合约名去掉计价币的原样，如 1000PEPE） */
export function coinSpec(base: string, asset: BadgeAsset = null): CoinSpec {
  const k = base.toUpperCase() + '|' + (asset || '')
  let s = specMemo.get(k)
  if (!s) { s = resolve(base, asset); specMemo.set(k, s) }
  return s
}

function resolve(base: string, asset: BadgeAsset): CoinSpec {
  const key = base.toUpperCase()
  const hit = KNOWN[key] ?? brand(key)
  if (hit) return hit
  const free = aliasKey(key)
  const stripped = free === key ? '' : free
  if (stripped) { const h2 = KNOWN[stripped] ?? brand(stripped); if (h2) return h2 }
  const name = stripped || key
  const pair = MATERIAL[name] ?? SPARE[spareIndex(key)]
  const mk = (mark: CoinSpec['mark'], inset: number): CoinSpec => ({ from: pair[0], to: pair[1], mark, inset })
  if (PRECIOUS.has(name) || GOLD_TOKENS.has(name) || asset === 'preciousMetal') return mk(INGOT, 0.68)
  if (OILS.has(name)) return mk(DROP, 0.6)
  if (GAS.has(name)) return mk(FLAME, 0.6)
  if (COPPER.has(name)) return mk(INGOT, 0.68)
  if (asset === 'commodity') return mk(DROP, 0.6)
  return generated(name, pair)
}

// ------------------------------------------------------------ 上色（BadgeTint）
interface HSB { h: number; s: number; b: number }
export function hexRGB(hex: string): [number, number, number] {
  let h = hex.trim().replace('#', '')
  if (h.length === 3) h = h.split('').map(c => c + c).join('')
  const n = parseInt(h.slice(0, 6), 16)
  return [((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255]
}
export function hsb(hex: string): HSB {
  const [r, g, bl] = hexRGB(hex)
  const mx = Math.max(r, g, bl), mn = Math.min(r, g, bl), d = mx - mn
  let h = 0
  if (d > 0) {
    if (mx === r) h = (g - bl) / d + (g < bl ? 6 : 0)
    else if (mx === g) h = (bl - r) / d + 2
    else h = (r - g) / d + 4
    h /= 6
  }
  return { h, s: mx === 0 ? 0 : d / mx, b: mx }
}
/** HSB → #rrggbb */
export function hsbHex(h: number, s: number, v: number): string {
  const i = Math.floor(h * 6), f = h * 6 - i
  const p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
  const [r, g, b] = [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][((i % 6) + 6) % 6]
  const x = (n: number): string => Math.round(Math.min(1, Math.max(0, n)) * 255).toString(16).padStart(2, '0')
  return '#' + x(r) + x(g) + x(b)
}
function pull(h: number, target: number, k: number): number {
  let d = target - h
  if (d > 0.5) d -= 1; else if (d < -0.5) d += 1
  const r = h + d * k
  return r < 0 ? r + 1 : (r >= 1 ? r - 1 : r)
}
const gold = (h: number): boolean => h > 0.07 && h < 0.2
const clamp = (v: number, lo: number, hi: number): number => Math.min(Math.max(v, Math.min(lo, hi)), hi)

const tintMemo = new Map<string, { top: string; bottom: string }>()
/** 一对渐变端点（top 左上、bottom 右下），按品牌两端 + 皮肤主色 + 深浅 */
export function badgeTint(from: string, to: string, accent: string, dark: boolean): { top: string; bottom: string } {
  const k = `${from}|${to}|${accent}|${dark ? 1 : 0}`
  let out = tintMemo.get(k)
  if (out) return out
  const a = hsb(from), b = hsb(to), skin = hsb(accent)
  if (Math.max(a.s, b.s) < 0.12) {
    const s = dark ? 0.15 : 0.13
    out = { top: hsbHex(skin.h, s, dark ? 0.46 : 0.74), bottom: hsbHex(skin.h, s + 0.05, dark ? 0.30 : 0.52) }
  } else {
    const hueA = pull(a.h, skin.h, gold(a.h) ? 0.04 : 0.11)
    const hueB = pull(b.h, skin.h, gold(b.h) ? 0.04 : 0.11)
    const give = gold(a.h) ? 0.14 : 0
    const hi = clamp(a.s, dark ? 0.20 : 0.24, (dark ? 0.56 : 0.52) + give)
    const lo = clamp(b.s, dark ? 0.26 : 0.30, (dark ? 0.66 : 0.60) + give)
    const top = clamp(a.b, dark ? 0.42 : 0.62, (dark ? 0.70 : 0.88) + (give > 0 ? 0.04 : 0))
    out = { top: hsbHex(hueA, hi, top), bottom: hsbHex(hueB, lo, clamp(b.b, dark ? 0.30 : 0.46, dark ? 0.56 : 0.70)) }
  }
  tintMemo.set(k, out)
  return out
}

/** 记号笔画宽度（屏幕点）：收进 1.86…2.16 的窄带，再按边长的 0.72 次方缩 */
export function badgeLine(declared: number, size: number): number {
  const band = Math.min(Math.max(2 + (declared - 2) * 0.28, 1.86), 2.16)
  return band * Math.pow(size / 33, 0.72)
}

// ------------------------------------------------------------ 皮肤（运行时从令牌读）
let skinKey = '', skinVal = { accent: '#2E7D6B', dark: false }
/** 当前皮肤主色与深浅（按 data-skin / data-theme 缓存） */
export function skinSeed(): { accent: string; dark: boolean } {
  if (typeof document === 'undefined') return skinVal
  const root = document.documentElement
  const k = (root.dataset.skin || '') + '|' + (root.dataset.theme || '')
  if (k !== skinKey) {
    skinKey = k
    const acc = getComputedStyle(root).getPropertyValue('--accent').trim()
    skinVal = { accent: /^#[0-9a-f]{3,8}$/i.test(acc) ? acc : '#2E7D6B', dark: root.dataset.theme === 'dark' }
  }
  return skinVal
}

// ------------------------------------------------------------ 画
const r2 = (n: number): string => String(Math.round(n * 100) / 100)

function partsSVG(list: Part[], size: number, inset: number): string {
  const box = size * inset
  return `<svg class="m-badge-mark" width="${r2(box)}" height="${r2(box)}" viewBox="0 0 24 24" aria-hidden="true">` + list.map(p => {
    if (!p.d.length) return ''
    if (p.stroke == null) return `<path fill="#fff" d="${p.d.join('')}"/>`
    const w = badgeLine(p.stroke, size) * 24 / box
    return `<path fill="none" stroke="#fff" stroke-width="${r2(w)}" stroke-linecap="round" stroke-linejoin="round" d="${p.d.join('')}"/>`
  }).join('') + '</svg>'
}

/** 徽章 HTML（size：顶栏 29、自选行 33、搜索行 32、面板 24） */
export function badgeHTML(base: string, size: number, asset: BadgeAsset = null, seed = skinSeed()): string {
  const s = coinSpec(base, asset)
  const t = badgeTint(s.from, s.to, seed.accent, seed.dark)
  const shadow = `0 ${r2(size * 0.1)}px ${r2(size * 0.34)}px ${t.bottom}${seed.dark ? '42' : '2e'}`
  let mark: string
  if ('text' in s.mark) {
    const n = [...s.mark.text].length
    const fs = Math.min(size * 0.5, (size * 0.86) / Math.max(1, n * 0.62))
    mark = `<span class="m-badge-text" style="font-size:${r2(Math.max(fs, size * 0.25))}px">${s.mark.text.replace(/[&<>]/g, '')}</span>`
  } else mark = partsSVG(s.mark.parts, size, s.inset)
  return `<span class="m-badge" style="width:${size}px;height:${size}px;border-radius:${r2(size * 0.31)}px;background:linear-gradient(to bottom right,${t.top},${t.bottom});box-shadow:${shadow}" aria-hidden="true">${mark}</span>`
}

/** 琉璃行的徽章（33）：背后一圈品牌色光晕 + 外扩 3.5 的角向渐变细环 */
export function liuliBadgeHTML(base: string, asset: BadgeAsset = null, seed = skinSeed()): string {
  const s = coinSpec(base, asset)
  const brandC = badgeTint(s.from, s.to, seed.accent, seed.dark).bottom
  return `<span class="m-liuli" style="--brand:${brandC}">${badgeHTML(base, 33, asset, seed)}</span>`
}

// ------------------------------------------------------------ 板块图标
/** 板块图标 HTML：渐变圆底 + 白色记号（照 SectorIcon） */
export function sectorIconHTML(id: string, size: number, seed = skinSeed()): string {
  const art = sectorIconArt(id)
  if (!art) return `<span class="m-sector-icon" style="width:${size}px;height:${size}px"></span>`
  const t = badgeTint(art.from, art.to, seed.accent, seed.dark)
  const k = Math.min(Math.max((20 - size) / 8, 0), 1)
  const inset = Math.min(art.inset * (1 + 0.1 * k), 0.82)
  const box = size * inset
  const paths = art.parts.map(p => {
    if (p.stroke != null) return `<path fill="none" stroke="#fff" stroke-width="${r2(badgeLine(p.stroke, size) * 24 / box)}" stroke-linecap="round" stroke-linejoin="round" d="${p.d}"/>`
    return `<path fill="#fff"${p.eo ? ' fill-rule="evenodd"' : ''} d="${p.d}"/>`
  }).join('')
  const shadow = `0 ${r2(size * 0.1)}px ${r2(size * 0.34)}px ${t.bottom}${seed.dark ? '42' : '2e'}`
  return `<span class="m-sector-icon" style="width:${size}px;height:${size}px;background:linear-gradient(to bottom right,${t.top},${t.bottom});box-shadow:${shadow}" aria-hidden="true"><svg width="${r2(box)}" height="${r2(box)}" viewBox="0 0 24 24">${paths}</svg></span>`
}
