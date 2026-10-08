// 移植自 KanpanChart/Sources/KanpanChart/Paint.swift
// （外加 KanpanPresentation/Palette.swift 里 ChartColors、orderFlow(bg:)、contrast、mix、orderFlowUnfilled，
//  以及 KanpanCore/Style/Hex.swift 的取值法）
//
// 颜色一律从 A 的 tokens.css 读（html[data-skin|data-theme|data-updown] 上的 --k-* / --of-* /
// --palette-N / --sub-N），这里不另立令牌；读不到时退回青苔浅 + 红涨绿跌（出厂默认）那一组。
//
// 文字：iOS 用 monospacedDigitSystemFont（等宽数字的 SF）。canvas 没有 font-variant-numeric，
// 于是「等宽数字」按 '0' 的字宽给每个数字一个格子、居中画进去——轴宽、读数与 iOS 一样不跳。
// 纵向：UIKit 的 draw(at:) 把字的行盒顶放在 y - 行高 / 2，SF 的 ascender 0.952、行高 1.193，
// 于是基线 = y + 0.3555 × 字号（中文 PingFang 同一把尺，肉眼差 < 0.5pt）。

import { swiftRound } from './geometry'

export type Hex = string

/** 图表用色（照 Palette.swift ChartColors）。另带订单流四色（Palette.orderFlow(bg:)）。 */
export interface ChartColors {
  bg: Hex; grid: Hex; axis: Hex; text: Hex; dim: Hex; ink: Hex; amber: Hex; cross: Hex
  band: Hex; oi: Hex; oiFill: Hex
  chip: Hex; panel: Hex
  crossBg: Hex; crossInk: Hex
  hair: Hex
  amberSoft: Hex; amberLine: Hex
  up: Hex; down: Hex
  /** 皮肤主色（`--accent`）：没定颜色的画线、把手、铃铛、放大镜都用它（照 iOS DrawPen，2026-10-08）。 */
  accent: Hex
  palette: Hex[]
  sub: Hex[]
  orderFlow: OrderFlowColors
}

export interface OrderFlowColors { contractBid: Hex; contractAsk: Hex; spotBid: Hex; spotAsk: Hex }

export const orderFlowOnDark: OrderFlowColors = { contractBid: '#5A7DFF', contractAsk: '#E04BF0', spotBid: '#CCE21E', spotAsk: '#B89CFF' }
export const orderFlowOnLight: OrderFlowColors = { contractBid: '#0A78C2', contractAsk: '#8A149F', spotBid: '#76850A', spotAsk: '#8566E8' }

/** 读不到令牌时的兜底：青苔 · 浅，绿涨红跌（iOS Prefs.redUp 出厂 false）。值照 tokens.css / Palette.sageSeed。 */
export const FALLBACK_COLORS: ChartColors = {
  bg: '#F3F7F4', grid: '#D6E3DA', axis: '#E2EBE5', text: '#606F67', dim: '#606F6799', ink: '#14211B', amber: '#B57C28', cross: '#4E6158',
  band: '#1478C8', oi: '#2FD2B2', oiFill: '#2FD2B22E',
  chip: '#F3F7F4', panel: '#F3F7F4',
  crossBg: '#14211B', crossInk: '#F3F7F4',
  hair: '#14211B0F',
  amberSoft: '#B57C2816', amberLine: '#B57C2855',
  up: '#36B257', down: '#E64552',
  accent: '#2E7D6B',
  palette: ['#FFB400', '#E849B9', '#6EBF26', '#F55B58', '#1478C8', '#2FD2B2'],
  sub: ['#2FD2B2', '#FFB400', '#E849B9', '#1478C8', '#6EBF26', '#F55B58'],
  orderFlow: orderFlowOnLight,
}

const TOKEN: Record<Exclude<keyof ChartColors, 'palette' | 'sub' | 'orderFlow' | 'accent'>, string> = {
  bg: '--k-bg', grid: '--k-grid', axis: '--k-axis', text: '--k-text', dim: '--k-dim', ink: '--k-ink', amber: '--k-amber', cross: '--k-cross',
  band: '--k-band', oi: '--k-oi', oiFill: '--k-oi-fill', chip: '--k-chip', panel: '--k-panel',
  crossBg: '--k-cross-bg', crossInk: '--k-cross-ink', hair: '--k-hair', amberSoft: '--k-amber-soft', amberLine: '--k-amber-line',
  up: '--k-up', down: '--k-down',
}

const HEX_RE = /^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/

/** 把 getComputedStyle 读到的值收成 #RRGGBB[AA]；var() 串起来的会被浏览器解析成最终值。 */
export function normalizeColor(raw: string | null | undefined): Hex | null {
  if (!raw) return null
  const v = raw.trim()
  if (HEX_RE.test(v)) return v.toUpperCase()
  if (/^#[0-9a-fA-F]{3}$/.test(v)) return ('#' + v.slice(1).split('').map(c => c + c).join('')).toUpperCase()
  const m = /^rgba?\(\s*([\d.]+)[\s,]+([\d.]+)[\s,]+([\d.]+)(?:[\s,/]+([\d.]+%?))?\s*\)$/.exec(v)
  if (m) {
    const h = (n: number) => Math.max(0, Math.min(255, Math.round(n))).toString(16).padStart(2, '0').toUpperCase()
    let a = 1
    if (m[4] != null) a = m[4].endsWith('%') ? parseFloat(m[4]) / 100 : parseFloat(m[4])
    return '#' + h(+m[1]) + h(+m[2]) + h(+m[3]) + (a < 1 ? h(a * 255) : '')
  }
  return null
}

/** 从 <html> 的计算样式读一整套图表色。每次皮肤 / 深浅 / 涨跌色开关变了重读一次即可（有缓存键）。 */
export function readChartColors(root?: Element | null): ChartColors {
  const el = root ?? (typeof document !== 'undefined' ? document.documentElement : null)
  if (!el || typeof getComputedStyle === 'undefined') return FALLBACK_COLORS
  const cs = getComputedStyle(el)
  const get = (name: string, fb: Hex): Hex => normalizeColor(cs.getPropertyValue(name)) ?? fb
  const out = { ...FALLBACK_COLORS } as ChartColors
  let found = 0
  for (const k of Object.keys(TOKEN) as (keyof typeof TOKEN)[]) {
    const v = normalizeColor(cs.getPropertyValue(TOKEN[k]))
    if (v) { found++; out[k] = v }
  }
  if (found === 0) return FALLBACK_COLORS
  out.accent = get('--accent', FALLBACK_COLORS.accent)
  out.palette = FALLBACK_COLORS.palette.map((fb, i) => get(`--palette-${i}`, fb))
  out.sub = FALLBACK_COLORS.sub.map((fb, i) => get(`--sub-${i}`, out.palette[i] ?? fb))
  const auto = orderFlowFor(out.bg)
  out.orderFlow = {
    contractBid: get('--of-contract-bid', auto.contractBid), contractAsk: get('--of-contract-ask', auto.contractAsk),
    spotBid: get('--of-spot-bid', auto.spotBid), spotAsk: get('--of-spot-ask', auto.spotAsk),
  }
  return out
}

/** html 上三个开关拼成的键：变了才需要重读颜色。 */
export function skinKey(root?: Element | null): string {
  const el = root ?? (typeof document !== 'undefined' ? document.documentElement : null)
  if (!el) return ''
  return [el.getAttribute('data-skin'), el.getAttribute('data-theme'), el.getAttribute('data-updown')].join('|')
}

// ---------------------------------------------------------------- Hex 运算（Hex.swift / Palette.swift）

export function rgba(h: Hex): { r: number; g: number; b: number; a: number } {
  const s = h.startsWith('#') ? h.slice(1) : h
  if ((s.length !== 6 && s.length !== 8) || !/^[0-9a-fA-F]+$/.test(s)) return { r: 0, g: 0, b: 0, a: 0 }
  const n = parseInt(s, 16)
  if (s.length === 6) return { r: ((n >> 16) & 0xff) / 255, g: ((n >> 8) & 0xff) / 255, b: (n & 0xff) / 255, a: 1 }
  return { r: ((n >>> 24) & 0xff) / 255, g: ((n >>> 16) & 0xff) / 255, b: ((n >>> 8) & 0xff) / 255, a: (n & 0xff) / 255 }
}

export function bytes(h: Hex): { r: number; g: number; b: number; a: number } {
  const d = (h.startsWith('#') ? h.slice(1) : h).split('').map(c => parseInt(c, 16)).filter(x => !Number.isNaN(x))
  if (d.length < 6) return { r: 0, g: 0, b: 0, a: 255 }
  return { r: d[0] * 16 + d[1], g: d[2] * 16 + d[3], b: d[4] * 16 + d[5], a: d.length >= 8 ? d[6] * 16 + d[7] : 255 }
}

/** Hex.alpha：在六位色后面接两位透明度。已经是八位的再接，iOS 解析成全透明——这里照办。 */
export function alpha(h: Hex, aa: string): Hex {
  const s = h.startsWith('#') ? h.slice(1) : h
  return s.length === 6 ? '#' + s + aa : '#00000000'
}

/** 把任意 Hex 交给 canvas：非法值给全透明，免得 canvas 静默沿用上一笔颜色。 */
export function css(h: Hex): string {
  return HEX_RE.test(h) ? h : 'rgba(0,0,0,0)'
}

export function mix(a: Hex, b: Hex, amount: number): Hex {
  const x = bytes(a), y = bytes(b), f = Math.min(1, Math.max(0, amount))
  const ch = (p: number, q: number) => {
    const v = p * f + q * (1 - f)
    return Math.max(0, Math.min(255, v < 0 ? -Math.round(-v) : Math.round(v))).toString(16).toUpperCase().padStart(2, '0')
  }
  return '#' + ch(x.r, y.r) + ch(x.g, y.g) + ch(x.b, y.b)
}

export function contrast(fg: Hex, bg: Hex): number {
  const lum = (c: Hex) => {
    const v = rgba(c)
    const lin = (n: number) => (n <= 0.04045 ? n / 12.92 : Math.pow((n + 0.055) / 1.055, 2.4))
    return 0.2126 * lin(v.r) + 0.7152 * lin(v.g) + 0.0722 * lin(v.b)
  }
  const a = lum(fg), b = lum(bg)
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05)
}

/** Palette.orderFlow(bg:)：相对亮度（非线性分量直接加权）> 0.5 算浅底。 */
export function orderFlowFor(bg: Hex): OrderFlowColors {
  const v = rgba(bg)
  return 0.2126 * v.r + 0.7152 * v.g + 0.0722 * v.b > 0.5 ? orderFlowOnLight : orderFlowOnDark
}

/** 没成交的主力单画浅一档：往底色混，最多 45%，混完对底色仍 ≥ 3:1；二分八次。 */
export function orderFlowUnfilled(color: Hex, bg: Hex, maxMix = 0.45): Hex {
  const mixed = (m: number) => mix(color, bg, 1 - m)
  if (contrast(mixed(maxMix), bg) >= 3) return mixed(maxMix)
  let lo = 0, hi = maxMix
  for (let i = 0; i < 8; i++) {
    const m = (lo + hi) / 2
    if (contrast(mixed(m), bg) >= 3) lo = m; else hi = m
  }
  return mixed(lo)
}

// ---------------------------------------------------------------- 字体（ChartFont）

/** mono：整串等宽（iOS monospacedSystemFont，即 SF Mono），不只是数字等宽。 */
export interface ChartFontSpec { size: number; weight: number; tabular: boolean; mono?: boolean }

export const FONT_FAMILY = '-apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Helvetica Neue", system-ui, sans-serif'

export const ChartFont = {
  /** monospacedDigitSystemFont(ofSize: 9) */
  axis: { size: 9, weight: 400, tabular: true } as ChartFontSpec,
  /** systemFont(ofSize: 11) */
  notice: { size: 11, weight: 400, tabular: false } as ChartFontSpec,
  /** monospacedDigitSystemFont(ofSize: 9) */
  tiny: { size: 9, weight: 400, tabular: true } as ChartFontSpec,
}

export const MONO_FAMILY = 'ui-monospace, "SF Mono", SFMono-Regular, Menlo, monospace'

export const fontString = (f: ChartFontSpec): string => `${f.weight} ${f.size}px ${f.mono ? MONO_FAMILY : FONT_FAMILY}`

/** SF 的行高（UIFont.lineHeight / pointSize）。NSString.size 的高度就是它。 */
export const LINE_HEIGHT = 1.193
/** 行盒中线到字母基线：-行高/2 + ascender(0.952)。 */
const BASELINE_FROM_CENTER = 0.952 - LINE_HEIGHT / 2

let measureCtx: CanvasRenderingContext2D | null | undefined
function mctx(): CanvasRenderingContext2D | null {
  if (measureCtx !== undefined) return measureCtx
  measureCtx = null
  try {
    if (typeof document !== 'undefined') measureCtx = document.createElement('canvas').getContext('2d')
    else if (typeof OffscreenCanvas !== 'undefined') measureCtx = new OffscreenCanvas(1, 1).getContext('2d') as unknown as CanvasRenderingContext2D
  } catch { measureCtx = null }
  return measureCtx
}

const sizeCache = new Map<string, number>()
const SIZE_LIMIT = 512
const isDigit = (c: string) => c >= '0' && c <= '9'

let measureFont = ''

function rawWidth(text: string, f: ChartFontSpec): number {
  const c = mctx()
  if (!c) {
    // 测试环境（无 canvas）：按 SF 的平均字宽近似；数字 0.6em，中文 1em，其余 0.55em
    let w = 0
    for (const ch of text) w += f.mono ? (ch.charCodeAt(0) > 0x2e80 ? 1 : 0.6) : isDigit(ch) ? 0.6 : ch.charCodeAt(0) > 0x2e80 ? 1 : 0.55
    return w * f.size
  }
  // canvas 每设一次 font 都要重新解析字体串；同一个字体就别再设
  const fs = fontString(f)
  if (fs !== measureFont) { c.font = fs; measureFont = fs }
  return c.measureText(text).width
}

/** 每个字体十个数字各自的字宽（逐字居中落笔用）。数字字形不随帧变，量一次就够。 */
const digitCache = new Map<string, number[]>()
function digitWidth(ch: string, f: ChartFontSpec): number {
  const key = fontString(f)
  let row = digitCache.get(key)
  if (!row) { row = new Array<number>(10).fill(NaN); digitCache.set(key, row) }
  const i = ch.charCodeAt(0) - 48
  let w = row[i]
  if (Number.isNaN(w)) { w = rawWidth(ch, f); row[i] = w }
  return w
}

/** 同一字体的「非等宽数字」版本（量非数字那几段用），按对象身份缓存，免得每段现造一个。 */
const plainSpec = new WeakMap<ChartFontSpec, ChartFontSpec>()
function plain(f: ChartFontSpec): ChartFontSpec {
  let p = plainSpec.get(f)
  if (!p) { p = { ...f, tabular: false }; plainSpec.set(f, p) }
  return p
}

/** String.width(font)：带缓存；等宽数字的字体里每个数字按 '0' 的宽度算。 */
export function textWidth(text: string, f: ChartFontSpec): number {
  const key = `${f.size}|${f.weight}|${f.tabular ? 1 : 0}${f.mono ? 'm' : ''}|${text}`
  const hit = sizeCache.get(key)
  if (hit !== undefined) return hit
  let w: number
  if (f.tabular && !f.mono && /\d/.test(text)) {
    const zero = rawWidth('0', f)
    w = 0
    let run = ''
    for (const ch of text) {
      if (isDigit(ch)) { if (run) { w += rawWidth(run, f); run = '' } w += zero } else run += ch
    }
    if (run) w += rawWidth(run, f)
  } else w = rawWidth(text, f)
  if (sizeCache.size >= SIZE_LIMIT) sizeCache.clear()
  sizeCache.set(key, w)
  return w
}

/** ChartFont.measure(...).height：UIFont.lineHeight。 */
export const textHeight = (f: ChartFontSpec): number => f.size * LINE_HEIGHT

function drawRun(ctx: CanvasRenderingContext2D, text: string, x: number, baseline: number, f: ChartFontSpec): void {
  if (!f.tabular || f.mono || !/\d/.test(text)) { ctx.fillText(text, x, baseline); return }
  const zero = textWidth('0', f)
  let run = '', rx = x
  const flush = () => { if (run) { ctx.fillText(run, rx, baseline); rx += textWidth(run, plain(f)); run = '' } }
  for (const ch of text) {
    if (isDigit(ch)) {
      flush()
      const dw = digitWidth(ch, f)
      ctx.fillText(ch, rx + (zero - dw) / 2, baseline)
      rx += zero
    } else run += ch
  }
  flush()
}

/** String.drawLeft(at:)：左边对齐 x，纵向以 y 为行盒中线。 */
export function drawLeft(ctx: CanvasRenderingContext2D, text: string, x: number, y: number, f: ChartFontSpec, color: Hex): void {
  ctx.font = fontString(f)
  ctx.fillStyle = css(color)
  ctx.textAlign = 'left'
  ctx.textBaseline = 'alphabetic'
  drawRun(ctx, text, x, y + BASELINE_FROM_CENTER * f.size, f)
}

/** String.drawCentered(at:)：以 (x, y) 为中心。 */
export function drawCentered(ctx: CanvasRenderingContext2D, text: string, x: number, y: number, f: ChartFontSpec, color: Hex): void {
  drawLeft(ctx, text, x - textWidth(text, f) / 2, y, f, color)
}

// ---------------------------------------------------------------- CGContext 扩展

/** 1 物理像素的横线，落在像素中心（hairline）。 */
export function hairLine(ctx: CanvasRenderingContext2D, x0: number, x1: number, y: number, scale: number, color: Hex): void {
  const yy = (swiftRound(y * scale) + 0.5) / scale
  ctx.strokeStyle = css(color)
  ctx.lineWidth = 1 / scale
  ctx.beginPath()
  ctx.moveTo(x0, yy)
  ctx.lineTo(x1, yy)
  ctx.stroke()
}

export function hairLineV(ctx: CanvasRenderingContext2D, x: number, y0: number, y1: number, scale: number, color: Hex): void {
  const xx = (swiftRound(x * scale) + 0.5) / scale
  ctx.strokeStyle = css(color)
  ctx.lineWidth = 1 / scale
  ctx.beginPath()
  ctx.moveTo(xx, y0)
  ctx.lineTo(xx, y1)
  ctx.stroke()
}

/** addRoundRect：半径不超过短边一半；0 退成直角。开新路径，调用方再 fill / stroke。 */
export function roundRectPath(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, radius: number): void {
  const rr = Math.min(radius, Math.min(w, h) / 2)
  ctx.beginPath()
  if (rr <= 0) { ctx.rect(x, y, w, h); return }
  ctx.moveTo(x + rr, y)
  ctx.arcTo(x + w, y, x + w, y + h, rr)
  ctx.arcTo(x + w, y + h, x, y + h, rr)
  ctx.arcTo(x, y + h, x, y, rr)
  ctx.arcTo(x, y, x + w, y, rr)
  ctx.closePath()
}

export function fillRoundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, radius: number, color: Hex): void {
  ctx.fillStyle = css(color)
  roundRectPath(ctx, x, y, w, h, radius)
  ctx.fill()
}

export function fillRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, color: Hex): void {
  ctx.fillStyle = css(color)
  ctx.fillRect(x, y, w, h)
}

/** ctx.clip(to: rect) */
export function clipRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number): void {
  ctx.beginPath()
  ctx.rect(x, y, w, h)
  ctx.clip()
}
