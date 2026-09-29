// 移植自 KanpanCore/Sources/KanpanCore/Drawing/DrawArchive.swift
//
// 画线的存档模型：按品种分桶，每品种上限 50 条；纯值，不碰存储（落盘由页面层接 DrawingBook.observe 去做）。
// 画线只按品种分桶，不按周期分：端点存的是「时间 + 价格」，同一条线在各个周期上就是同一条。

import type { Hex } from '../paint'
import {
  type Drawing, type DrawDash, type DrawingKind, type DrawPoint, DRAW_DASHES, DrawKind,
  cloneDrawing, decodeHex, drawingWith, drawingsEqual, encodeDrawing, isDrawingKind, tryDecodeDrawing,
} from './drawing'
import { canonicalInstrument } from './instrument'

// ------------------------------------------------------------ 工具样式

/** 一把工具记住的样式（只有样式，从不含被删掉那条线的端点）。 */
export interface DrawingStyle {
  color: Hex | null
  lineWidth: number
  dash: DrawDash
  filled: boolean
  levels: number[]
}
export const styleOf = (d: Drawing): DrawingStyle =>
  ({ color: d.color, lineWidth: d.lineWidth, dash: d.dash, filled: d.filled, levels: d.levels.slice() })

export function styleEquals(a: DrawingStyle, b: DrawingStyle): boolean {
  return (a.color ?? null) === (b.color ?? null) && a.lineWidth === b.lineWidth && a.dash === b.dash && a.filled === b.filled
    && a.levels.length === b.levels.length && a.levels.every((v, i) => v === b.levels[i])
}

export interface DrawingStyleJSON { color?: { value: string }; lineWidth: number; dash: DrawDash; filled: boolean; levels: number[] }

export function encodeStyle(s: DrawingStyle): DrawingStyleJSON {
  const out = {} as DrawingStyleJSON
  if (s.color != null) out.color = { value: s.color }
  out.lineWidth = s.lineWidth; out.dash = s.dash; out.filled = s.filled; out.levels = s.levels.slice()
  return out
}

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)

/** Swift 合成 Codable：除 color 外都是必需键；解不开 → null（`TolerantStyle`）。 */
export function decodeStyle(v: unknown): DrawingStyle | null {
  if (!isObj(v)) return null
  if (typeof v.lineWidth !== 'number' || typeof v.filled !== 'boolean') return null
  if (typeof v.dash !== 'string' || !DRAW_DASHES.includes(v.dash as DrawDash)) return null
  if (!Array.isArray(v.levels) || !v.levels.every(x => typeof x === 'number')) return null
  let color: Hex | null = null
  if (v.color !== undefined && v.color !== null) {
    try { color = decodeHex(v.color) } catch { return null }
  }
  return { color, lineWidth: v.lineWidth, dash: v.dash as DrawDash, filled: v.filled, levels: (v.levels as number[]).slice() }
}

// ------------------------------------------------------------ 画线偏好

/** 收藏、磁吸、连续画、每把工具的样式、每一族「换画法」记住的那一种。 */
export class DrawingPreferences {
  /** 收藏的那几把工具。界面上已经没有入口，字段只剩兼容与同步。 */
  favorites: DrawingKind[] = ['trend', 'hline', 'fibonacci', 'measure']
  magnet = true
  continuous = false
  styles: Record<string, DrawingStyle> = {}
  /** 键是面板上那一格（trend / hline / vline），值是同族里的一种。 */
  variants: Record<string, DrawingKind> = {}

  clone(): DrawingPreferences {
    const p = new DrawingPreferences()
    p.favorites = this.favorites.slice(); p.magnet = this.magnet; p.continuous = this.continuous
    p.styles = Object.fromEntries(Object.entries(this.styles).map(([k, s]) => [k, { ...s, levels: s.levels.slice() }]))
    p.variants = { ...this.variants }
    return p
  }

  equals(o: DrawingPreferences): boolean {
    const sk = Object.keys(this.styles), ok = Object.keys(o.styles)
    const vk = Object.keys(this.variants), ovk = Object.keys(o.variants)
    return this.magnet === o.magnet && this.continuous === o.continuous
      && this.favorites.length === o.favorites.length && this.favorites.every((f, i) => f === o.favorites[i])
      && sk.length === ok.length && sk.every(k => o.styles[k] !== undefined && styleEquals(this.styles[k], o.styles[k]))
      && vk.length === ovk.length && vk.every(k => this.variants[k] === o.variants[k])
  }

  /** 面板上点的是 tool，这一笔落下来该是哪一种。 */
  kindFor(tool: DrawingKind): DrawingKind { return DrawingPreferences.kindFor(tool, this.variants) }
  static kindFor(tool: DrawingKind, variants: Readonly<Record<string, DrawingKind>>): DrawingKind {
    if (DrawKind.paletteHead(tool) !== tool) return tool
    const chosen = Object.prototype.hasOwnProperty.call(variants, tool) ? variants[tool] : undefined
    if (chosen === undefined || DrawKind.paletteHead(chosen) !== tool) return tool
    return chosen
  }

  /** 样式表里把一条线从 old 换成了 new：同一族就记成这一族以后的画法。返回有没有真的改动。 */
  rememberSwap(old: DrawingKind, next: DrawingKind): boolean {
    const head = DrawKind.paletteHead(next)
    if (old === next || head == null || DrawKind.paletteHead(old) !== head || this.variants[head] === next) return false
    this.variants[head] = next
    return true
  }

  /** 面板上的 tool 落下一条新线：kind 换成这一族记住的画法，样式铺这类工具记住的默认。 */
  newDrawing(tool: DrawingKind, points: DrawPoint[]): Drawing {
    return DrawingPreferences.newDrawing(tool, points, this.styles, this.variants)
  }
  static newDrawing(tool: DrawingKind, points: DrawPoint[], styles: Readonly<Record<string, DrawingStyle>>,
    variants: Readonly<Record<string, DrawingKind>>, id?: string): Drawing {
    const kind = DrawingPreferences.kindFor(tool, variants)
    const item = drawingWith(kind, points, id)
    const own = (k: string): DrawingStyle | undefined => (Object.prototype.hasOwnProperty.call(styles, k) ? styles[k] : undefined)
    const style = own(kind) ?? own(tool)
    if (style) {
      // 线型与填充 2026-09-28 起不再给选：只套颜色、线宽、刻度。
      item.color = style.color; item.lineWidth = style.lineWidth; item.levels = style.levels.slice()
    }
    return item
  }

  toJSON(): Record<string, unknown> { return encodePreferences(this) }
}

export function encodePreferences(p: DrawingPreferences): Record<string, unknown> {
  return {
    favorites: p.favorites.slice(),
    magnet: p.magnet,
    continuous: p.continuous,
    styles: Object.fromEntries(Object.entries(p.styles).map(([k, s]) => [k, encodeStyle(s)])),
    variants: { ...p.variants },
  }
}

export class PreferencesDecodeError extends Error {}

/** 缺的键取默认、认不出的那一条丢掉；只有 magnet / continuous 类型不对才整份抛（同 Swift）。 */
export function decodePreferences(v: unknown): DrawingPreferences {
  if (!isObj(v)) throw new PreferencesDecodeError('偏好不是对象')
  const p = new DrawingPreferences()
  const favs = v.favorites
  if (Array.isArray(favs) && favs.every(x => typeof x === 'string')) p.favorites = (favs as string[]).filter(isDrawingKind)
  for (const k of ['magnet', 'continuous'] as const) {
    const x = v[k]
    if (x === undefined || x === null) continue
    if (typeof x !== 'boolean') throw new PreferencesDecodeError(`${k} 不是布尔`)
    p[k] = x
  }
  if (isObj(v.styles)) {
    const out: Record<string, DrawingStyle> = {}
    for (const [k, raw] of Object.entries(v.styles)) { const s = decodeStyle(raw); if (s) out[k] = s }
    p.styles = out
  }
  if (isObj(v.variants) && Object.values(v.variants).every(x => typeof x === 'string')) {
    const out: Record<string, DrawingKind> = {}
    for (const [k, raw] of Object.entries(v.variants)) if (isDrawingKind(raw)) out[k] = raw
    p.variants = out
  }
  return p
}

// ------------------------------------------------------------ 存档

/** 一条线「多老」：它在同步里第一次被写下的那一刻。大的新。 */
export interface DrawAge { timestamp: number; logical: number }
const ageLess = (a: DrawAge, b: DrawAge): boolean => a.timestamp < b.timestamp || (a.timestamp === b.timestamp && a.logical < b.logical)
const ageEq = (a: DrawAge, b: DrawAge): boolean => a.timestamp === b.timestamp && a.logical === b.logical

/** Swift `String <`（ASCII 范围内与 UTF-16 码元比较一致）。 */
const strLess = (a: string, b: string): boolean => a < b

export class DrawArchive {
  static readonly currentVersion = 3
  static readonly perSymbolLimit = 50

  preferences = new DrawingPreferences()
  version: number
  bySymbol: Record<string, Drawing[]>

  constructor(version: number = DrawArchive.currentVersion, bySymbol: Record<string, Drawing[]> = {}) {
    this.version = version
    this.bySymbol = DrawArchive.migrate(bySymbol)
  }

  /** 老键（裸代号）并进规范键；同 id 时规范键那一份胜出。 */
  static migrate(values: Readonly<Record<string, Drawing[]>>): Record<string, Drawing[]> {
    const output: Record<string, Drawing[]> = {}
    for (const key of Object.keys(values).sort()) {
      const canonical = canonicalInstrument(key)
      for (const drawing of values[key] ?? []) {
        const bucket = output[canonical]
        const i = bucket ? bucket.findIndex(d => d.id === drawing.id) : -1
        if (i >= 0) { if (key === canonical) bucket[i] = drawing }
        else (output[canonical] ??= []).push(drawing)
      }
    }
    return output
  }

  clone(): DrawArchive {
    const a = new DrawArchive(this.version)
    a.preferences = this.preferences.clone()
    a.bySymbol = Object.fromEntries(Object.entries(this.bySymbol).map(([k, v]) => [k, v.map(cloneDrawing)]))
    return a
  }

  equals(o: DrawArchive): boolean {
    const ks = Object.keys(this.bySymbol), ok = Object.keys(o.bySymbol)
    return this.version === o.version && this.preferences.equals(o.preferences)
      && ks.length === ok.length && ks.every(k => o.bySymbol[k] !== undefined && drawingsEqual(this.bySymbol[k], o.bySymbol[k]))
  }

  /** Swift 下标 get：按规范键取，缺省是空数组。 */
  get(symbol: string): Drawing[] { return this.bySymbol[canonicalInstrument(symbol)] ?? [] }
  /** Swift 下标 set：空数组不占位。 */
  set(symbol: string, items: Drawing[]): void {
    const key = canonicalInstrument(symbol)
    if (items.length === 0) delete this.bySymbol[key]
    else this.bySymbol[key] = items
  }

  /** 眼下这个品种的那一桶，跟另一份存档比有没有变。 */
  bucketChanged(old: DrawArchive, symbol: string): boolean { return !drawingsEqual(this.get(symbol), old.get(symbol)) }

  /** 还能不能再画一条。 */
  hasRoom(symbol: string): boolean { return this.get(symbol).length < DrawArchive.perSymbolLimit }

  /** 进门的上限：每桶最多 50 条，多出来的从最老的丢起；留下的保持原先后。返回每个品种丢了几条。 */
  capToLimit(age: (d: Drawing) => DrawAge | null = () => null): Record<string, number> {
    const dropped: Record<string, number> = {}
    for (const [key, bucket] of Object.entries(this.bySymbol)) {
      if (bucket.length <= DrawArchive.perSymbolLimit) continue
      const ages = bucket.map(age)
      const less = (i: number, j: number): boolean => {
        const x = ages[i], y = ages[j]
        if (x && y) return ageEq(x, y) ? strLess(bucket[i].id, bucket[j].id) : ageLess(x, y)
        if (!x && !y) return i < j
        if (!x) return false
        return true
      }
      const ranked = bucket.map((_, i) => i).sort((i, j) => (less(i, j) ? -1 : less(j, i) ? 1 : 0))
      const keep = new Set(ranked.slice(ranked.length - DrawArchive.perSymbolLimit))
      dropped[key] = bucket.length - DrawArchive.perSymbolLimit
      this.bySymbol[key] = bucket.filter((_, i) => keep.has(i))
    }
    return dropped
  }

  /** 一串画线里最新的 50 条（数组尾上的那几条）。 */
  static newest(drawings: readonly Drawing[]): Drawing[] {
    return drawings.length > DrawArchive.perSymbolLimit ? drawings.slice(drawings.length - DrawArchive.perSymbolLimit) : drawings.slice()
  }

  /** 编码：键名 v / d / preferences（与 Swift 一致）。 */
  toJSON(): Record<string, unknown> { return encodeArchive(this) }
}

export function encodeArchive(a: DrawArchive): Record<string, unknown> {
  return {
    preferences: encodePreferences(a.preferences),
    v: a.version,
    d: Object.fromEntries(Object.entries(a.bySymbol).map(([k, v]) => [k, v.map(encodeDrawing)])),
  }
}

/** 解码：v 缺省 3；偏好坏了只丢偏好；逐条解画线，解不开的那一条丢掉，空桶丢掉，然后迁移。 */
export function decodeArchive(json: unknown): DrawArchive {
  if (!isObj(json)) throw new Error('画线存档不是对象')
  let version = DrawArchive.currentVersion
  if (json.v !== undefined && json.v !== null) {
    if (typeof json.v !== 'number' || !Number.isInteger(json.v)) throw new Error('v 不是整数')
    version = json.v
  }
  let preferences = new DrawingPreferences()
  if (json.preferences !== undefined && json.preferences !== null) {
    try { preferences = decodePreferences(json.preferences) } catch { preferences = new DrawingPreferences() }
  }
  const raw: Record<string, Drawing[]> = {}
  if (json.d !== undefined && json.d !== null) {
    if (!isObj(json.d)) throw new Error('d 不是对象')
    for (const [k, bucket] of Object.entries(json.d)) {
      if (!Array.isArray(bucket)) throw new Error('桶不是数组')
      const kept = bucket.map(tryDecodeDrawing).filter((d): d is Drawing => d != null)
      if (kept.length) raw[k] = kept
    }
  }
  const a = new DrawArchive(version, raw)
  a.preferences = preferences
  return a
}
