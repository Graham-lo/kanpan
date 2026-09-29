// 移植自 KanpanCore/Sources/KanpanCore/Drawing/Drawing.swift
//
// 画线模型；兼容第一版水平线与趋势线存档。
//
// 端点存的是**时间 + 价格**，不是像素——缩放、换周期、切对数轴之后线还在原来的
// 位置上。
//
// 与 Swift 的差异（只在写法上）：Swift 的 `Drawing` 是值类型结构体，这里是一份可以直接
// `JSON.stringify` 的纯对象（`Drawing`），种类上的问答（名字、点数、刻度……）收在 `DrawKind`
// 里；编解码走 `encodeDrawing` / `decodeDrawing`，JSON 的字段名与 Swift Codable 逐字一致，
// 颜色照 Swift `Hex` 的合成 Codable 写成 `{"value":"#RRGGBB"}`。

import type { Hex } from '../paint'
import { Chart } from '../geometry'
import { graphemeCount } from './fmt'
import { drawingGeometry, type DrawBounds } from './geometry'

/** 一个端点。`t` 是毫秒时间戳，`p` 是价格。 */
export interface DrawPoint { t: number; p: number }

export const DRAWING_KINDS = [
  'hline', 'trend', 'ray', 'hray', 'extended', 'vline', 'rectangle', 'channel', 'fibonacci', 'measure',
  // ---- 第二批高级工具（2026-09-18）。加在末尾，老存档里没有它们，解码不受影响。
  'position', 'regression', 'fibExtension', 'priceRange', 'dateRange', 'note',
  // ---- 全量对齐 TradingView 的工具面板（2026-09-18）。同样加在末尾。
  'crossLine', 'arrowLine',
  'pitchfork', 'fibChannel',
  'ellipse', 'triangle', 'curve', 'datePriceRange',
  'fibTimeZone', 'fibFan',
  'gannBox', 'gannFan',
  'xabcd', 'abcd', 'headShoulders', 'elliottImpulse', 'elliottCorrection',
  'callout', 'priceLabel', 'flag', 'markerUp', 'markerDown',
  // ---- 计算型工具（2026-09-20）：形状不由锚点几何决定，由锚点圈住的 K 线算出来。
  'anchoredVWAP', 'fixedVolumeProfile', 'anchoredVolumeProfile',
] as const
export type DrawingKind = typeof DRAWING_KINDS[number]
/** Swift 里 `DrawingStore.Tool` 就是 `Drawing.Kind`。 */
export type DrawTool = DrawingKind

const KIND_SET: ReadonlySet<string> = new Set(DRAWING_KINDS)
export const isDrawingKind = (v: unknown): v is DrawingKind => typeof v === 'string' && KIND_SET.has(v)

const TITLES: Record<DrawingKind, string> = {
  hline: '水平线',
  trend: '趋势线',
  // 这三种只在样式表「画法」一排里换得到，名字就是那排按钮上的字。
  ray: '向右延伸',
  hray: '向右延伸',
  extended: '两端延伸',
  vline: '垂直线',
  rectangle: '矩形',
  channel: '平行通道',
  fibonacci: '斐波那契回撤',
  measure: '价时测量',
  position: '多空持仓框',
  regression: '回归通道',
  fibExtension: '斐波那契扩展',
  priceRange: '价格区间',
  dateRange: '日期区间',
  note: '文字标注',
  crossLine: '十字线',
  arrowLine: '箭头',
  pitchfork: '安德鲁斯分叉',
  fibChannel: '斐波那契通道',
  ellipse: '椭圆',
  triangle: '三角形',
  curve: '曲线',
  datePriceRange: '日期价格区间',
  fibTimeZone: '斐波那契时区',
  fibFan: '斐波那契扇形',
  gannBox: '江恩箱',
  gannFan: '江恩扇形',
  xabcd: 'XABCD 形态',
  abcd: 'ABCD 形态',
  headShoulders: '头肩形态',
  elliottImpulse: '艾略特推动浪',
  elliottCorrection: '艾略特调整浪',
  callout: '气泡标注',
  priceLabel: '价格标签',
  flag: '旗标',
  markerUp: '向上箭头',
  markerDown: '向下箭头',
  // TV 那把叫「锚定 VWAP」；界面标签一律中文，从你点的那根起算，所以叫「锚定均价线」。
  anchoredVWAP: '锚定均价线',
  fixedVolumeProfile: '区间成交量分布',
  anchoredVolumeProfile: '锚定成交量分布',
}

/** 样式表里一排「换一种画法」的按钮。 */
export interface KindSwapOption { label: string; kind: DrawingKind }
export interface KindSwap { title: string; options: KindSwapOption[] }
const opt = (kind: DrawingKind, label?: string): KindSwapOption => ({ label: label ?? TITLES[kind], kind })

const RETRACE_LEVELS = [0, 0.236, 0.382, 0.5, 0.618, 0.786, 1]

/** Swift `Drawing.Kind` 上的那些问答。 */
export const DrawKind = {
  all: DRAWING_KINDS,
  title: (k: DrawingKind): string => TITLES[k],
  /** 存几个点。 */
  pointCount(k: DrawingKind): number {
    switch (k) {
      case 'hline': case 'vline': case 'hray': case 'note': case 'crossLine': case 'priceLabel': case 'flag':
      case 'markerUp': case 'markerDown': case 'anchoredVWAP': case 'anchoredVolumeProfile': return 1
      case 'channel': case 'regression': case 'position': case 'fibExtension': case 'pitchfork': case 'fibChannel':
      case 'triangle': case 'curve': return 3
      case 'abcd': case 'elliottCorrection': return 4
      case 'xabcd': return 5
      case 'elliottImpulse': return 6
      case 'headShoulders': return 7
      default: return 2
    }
  },
  /** 要在图上点几下。只有回归通道例外：用户圈起止两点，第三点由最小二乘拟合补上。 */
  placeCount: (k: DrawingKind): number => (k === 'regression' ? 2 : DrawKind.pointCount(k)),
  /** 这把工具的出厂刻度。 */
  defaultLevels(k: DrawingKind): number[] {
    switch (k) {
      case 'fibExtension': return [0, 0.382, 0.618, 1, 1.618, 2.618]
      case 'fibTimeZone': return [0, 1, 2, 3, 5, 8]
      case 'fibFan': return [0.382, 0.5, 0.618]
      case 'gannBox': return [0.25, 0.382, 0.5, 0.618, 0.75]
      // 江恩扇的「刻度」是斜率倍数。
      case 'gannFan': return [0.25, 0.333, 0.5, 1, 2, 3, 4]
      default: return RETRACE_LEVELS.slice()
    }
  },
  /** 吃不吃 `levels`。 */
  usesLevels: (k: DrawingKind): boolean =>
    k === 'fibonacci' || k === 'fibExtension' || k === 'fibChannel' || k === 'fibTimeZone' || k === 'fibFan' || k === 'gannBox' || k === 'gannFan',
  /** 画出来是「一块面」的那几种（测量不在里面：它的底色就是结论，恒亮）。 */
  usesFill(k: DrawingKind): boolean {
    switch (k) {
      case 'rectangle': case 'channel': case 'regression': case 'position': case 'priceRange': case 'dateRange':
      case 'ellipse': case 'triangle': case 'datePriceRange': case 'gannBox': case 'pitchfork': case 'fibChannel':
      case 'xabcd': case 'callout': case 'flag': case 'markerUp': case 'markerDown': return true
      default: return false
    }
  },
  /** 形状要拿 K 线算出来的那几把。 */
  isComputed: (k: DrawingKind): boolean => k === 'anchoredVWAP' || k === 'fixedVolumeProfile' || k === 'anchoredVolumeProfile',
  /** 带不带一段文字。 */
  usesText: (k: DrawingKind): boolean => k === 'note' || k === 'callout' || k === 'flag',
  /** 「绘图」面板上摆出来的那 12 把，顺序即面板顺序。 */
  palette: ['hline', 'trend', 'vline', 'channel', 'fibonacci', 'fibExtension', 'measure', 'note',
    'anchoredVWAP', 'fixedVolumeProfile', 'anchoredVolumeProfile', 'position'] as readonly DrawingKind[],
  /** 样式表里的「换一种画法」。同一族里 `pointCount` 必须相同。 */
  swaps(k: DrawingKind): KindSwap[] {
    switch (k) {
      case 'hline': case 'hray':
        return [{ title: '画法', options: [opt('hline', '整条'), opt('hray')] }]
      case 'trend': case 'ray': case 'extended': case 'arrowLine':
        return [{ title: '画法', options: [opt('trend', '线段'), opt('ray'), opt('extended'), opt('arrowLine')] }]
      case 'vline': case 'crossLine':
        return [{ title: '画法', options: [opt('vline'), opt('crossLine')] }]
      default: return []
    }
  },
  /** 这一把所在的「换画法」那一族摆在面板上的是哪一格；不在任何一族里是 null。 */
  paletteHead(k: DrawingKind): DrawingKind | null {
    const first = DrawKind.swaps(k)[0]
    if (!first) return null
    for (const o of first.options) if (DrawKind.palette.includes(o.kind)) return o.kind
    return null
  },
}

/** 拖的是哪一个端点；`body` 是整条一起走。 */
export type DrawPart = 'a' | 'b' | 'c' | 'd' | 'e' | 'f' | 'g' | 'h' | 'body'
export const DRAW_PART_ANCHORS: readonly DrawPart[] = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']
/** 在 `points` 里的下标；`body` 没有下标（null）。 */
export function partIndex(part: DrawPart): number | null {
  const i = DRAW_PART_ANCHORS.indexOf(part)
  return i < 0 ? null : i
}
export const partAnchor = (i: number): DrawPart => DRAW_PART_ANCHORS[Math.min(Math.max(i, 0), DRAW_PART_ANCHORS.length - 1)]

export type DrawDash = 'solid' | 'dashed' | 'dotted'
export const DRAW_DASHES: readonly DrawDash[] = ['solid', 'dashed', 'dotted']
export const dashTitle = (d: DrawDash): string => (d === 'solid' ? '实线' : d === 'dashed' ? '虚线' : '点线')

export interface Drawing {
  id: string
  kind: DrawingKind
  /** 只存时间与价格，像素每个视口现算。 */
  points: DrawPoint[]
  /** 用户挑的颜色；null = 跟着图表的 `band`。 */
  color: Hex | null
  lineWidth: number
  dash: DrawDash
  filled: boolean
  locked: boolean
  hidden: boolean
  levels: number[]
  /** 「文字标注」等写的那句话，上限 60 个字素。别的工具一律空串。 */
  text: string
}

export const DRAWING_TEXT_LIMIT = 60

/** `"d" + UUID`（大写，和 Swift `UUID().uuidString` 同一写法）。 */
export function newDrawingID(): string {
  const c = (globalThis as { crypto?: Crypto }).crypto
  if (c && typeof c.randomUUID === 'function') return 'd' + c.randomUUID().toUpperCase()
  // 非安全上下文（局域网 http）没有 randomUUID：用 getRandomValues 拼一个 v4。
  const b = new Uint8Array(16)
  if (c && typeof c.getRandomValues === 'function') c.getRandomValues(b)
  else for (let i = 0; i < 16; i++) b[i] = Math.floor(Math.random() * 256)
  b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80
  const h = Array.from(b, x => x.toString(16).padStart(2, '0')).join('').toUpperCase()
  return `d${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`
}

/** Swift `Drawing(id:kind:a:b:color:)`：刻度用回撤那套默认值（不看 kind）。 */
export function makeDrawing(kind: DrawingKind, a: DrawPoint, b?: DrawPoint | null, color?: Hex | null, id: string = newDrawingID()): Drawing {
  return {
    id, kind, points: b ? [{ ...a }, { ...b }] : [{ ...a }], color: color ?? null,
    lineWidth: 1.3, dash: 'solid', filled: true, locked: false, hidden: false, levels: RETRACE_LEVELS.slice(), text: '',
  }
}

/** Swift `Drawing(id:kind:points:)`：刻度用这把工具自己的出厂值。 */
export function drawingWith(kind: DrawingKind, points: DrawPoint[], id: string = newDrawingID()): Drawing {
  return {
    id, kind, points: points.map(p => ({ t: p.t, p: p.p })), color: null,
    lineWidth: 1.3, dash: 'solid', filled: true, locked: false, hidden: false, levels: DrawKind.defaultLevels(kind), text: '',
  }
}

/** 深拷贝一条（Swift 值语义）。 */
export function cloneDrawing(d: Drawing): Drawing {
  return { ...d, points: d.points.map(p => ({ t: p.t, p: p.p })), levels: d.levels.slice() }
}

/** 第一点（没有点时是 (0, 0)）。 */
export const drawingA = (d: Drawing): DrawPoint => d.points[0] ?? { t: 0, p: 0 }
/** 第二点。 */
export const drawingB = (d: Drawing): DrawPoint | null => (d.points.length > 1 ? d.points[1] : null)
export const drawingPrices = (d: Drawing): number[] => d.points.map(p => p.p)

export function drawingIsValid(d: Drawing): boolean {
  return d.points.length === DrawKind.pointCount(d.kind)
    && d.points.every(p => Number.isFinite(p.t) && Number.isFinite(p.p))
    && Number.isFinite(d.lineWidth) && d.lineWidth >= 0.5 && d.lineWidth <= 6
    && d.levels.length <= 24 && d.levels.every(v => Number.isFinite(v) && Math.abs(v) <= 10)
    && graphemeCount(d.text) <= DRAWING_TEXT_LIMIT
}

const samePoint = (a: DrawPoint, b: DrawPoint): boolean => a.t === b.t && a.p === b.p

/** Swift 合成 `Equatable`：逐字段相等。 */
export function drawingEquals(a: Drawing, b: Drawing): boolean {
  if (a === b) return true
  return a.id === b.id && a.kind === b.kind && (a.color ?? null) === (b.color ?? null)
    && a.lineWidth === b.lineWidth && a.dash === b.dash && a.filled === b.filled
    && a.locked === b.locked && a.hidden === b.hidden && a.text === b.text
    && a.points.length === b.points.length && a.points.every((p, i) => samePoint(p, b.points[i]))
    && a.levels.length === b.levels.length && a.levels.every((v, i) => v === b.levels[i])
}

export function drawingsEqual(a: readonly Drawing[], b: readonly Drawing[]): boolean {
  if (a === b) return true
  return a.length === b.length && a.every((d, i) => drawingEquals(d, b[i]))
}

// ------------------------------------------------------------ 编解码

/** Swift `Drawing` 的 JSON 形状。 */
export interface DrawingJSON {
  id: string
  kind: string
  points: DrawPoint[]
  color?: { value: string }
  lineWidth: number
  dash: DrawDash
  filled: boolean
  locked: boolean
  hidden: boolean
  levels: number[]
  text?: string
}

export function encodeDrawing(d: Drawing): DrawingJSON {
  const out: DrawingJSON = {
    id: d.id, kind: d.kind, points: d.points.map(p => ({ t: p.t, p: p.p })),
    lineWidth: d.lineWidth, dash: d.dash, filled: d.filled, locked: d.locked, hidden: d.hidden, levels: d.levels.slice(),
  }
  if (d.color != null) out.color = { value: d.color }
  // 带文字的工具总是写 `text`（空也写 ""），不带文字的恒空就省略；非空一律写，给老存档兜底。
  if (DrawKind.usesText(d.kind) || d.text !== '') out.text = d.text
  // 键的顺序照 Swift 的编码顺序排（id, kind, points, color, lineWidth, dash, filled, locked, hidden, levels, text）。
  const ordered: DrawingJSON = { id: out.id, kind: out.kind, points: out.points } as DrawingJSON
  if (out.color) ordered.color = out.color
  Object.assign(ordered, { lineWidth: out.lineWidth, dash: out.dash, filled: out.filled, locked: out.locked, hidden: out.hidden, levels: out.levels })
  if (out.text !== undefined) ordered.text = out.text
  return ordered
}

export class DrawingDecodeError extends Error {}

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)
const present = (o: Record<string, unknown>, k: string): boolean => o[k] !== undefined && o[k] !== null

function decodePoint(v: unknown): DrawPoint {
  if (!isObj(v) || typeof v.t !== 'number' || typeof v.p !== 'number') throw new DrawingDecodeError('端点格式不对')
  return { t: v.t, p: v.p }
}

/** Swift `Hex` 的 JSON：`{"value": "#RRGGBB"}`；也收裸字符串（网页老数据）。 */
export function decodeHex(v: unknown): Hex {
  if (typeof v === 'string') return v
  if (isObj(v) && typeof v.value === 'string') return v.value
  throw new DrawingDecodeError('颜色格式不对')
}

const HEX_COLOR = /^#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?$/
/**
 * 外来的颜色（存档、云端、朋友分享）只收 #RRGGBB / #RRGGBBAA，别的一律当「没设颜色」（null，画的时候用默认色）。
 *
 * Swift 的 Hex 什么字符串都收，因为手机上它只会进 CoreGraphics；网页上线的颜色会被页面拼进 innerHTML
 * （样式面板的色块 style="--c:…"、取色器 value="…"），一个带引号的「颜色」就是一段注入。iOS 写出来的永远是
 * #RRGGBB（DrawingBar 的取色器），所以收紧不会误伤真数据；不整条拒收是为了「读坏数据只补不删」——线还在，只是颜色回到默认。
 */
export function sanitizeHex(v: Hex | null): Hex | null {
  return v != null && HEX_COLOR.test(v) ? v : null
}

function optNumber(o: Record<string, unknown>, k: string, fallback: number): number {
  if (!present(o, k)) return fallback
  if (typeof o[k] !== 'number') throw new DrawingDecodeError(`${k} 不是数`)
  return o[k] as number
}
function optBool(o: Record<string, unknown>, k: string, fallback: boolean): boolean {
  if (!present(o, k)) return fallback
  if (typeof o[k] !== 'boolean') throw new DrawingDecodeError(`${k} 不是布尔`)
  return o[k] as boolean
}

/** Swift `Drawing.init(from:)`：缺的键取默认，最后 `isValid` 不过就抛。 */
export function decodeDrawing(json: unknown): Drawing {
  if (!isObj(json)) throw new DrawingDecodeError('不是对象')
  if (typeof json.id !== 'string') throw new DrawingDecodeError('缺 id')
  if (!isDrawingKind(json.kind)) throw new DrawingDecodeError('不认识的 kind')
  const kind = json.kind
  let points: DrawPoint[]
  if (present(json, 'points')) {
    if (!Array.isArray(json.points)) throw new DrawingDecodeError('points 不是数组')
    points = json.points.map(decodePoint)
  } else {
    points = [decodePoint(json.a)]
    if (present(json, 'b')) points.push(decodePoint(json.b))
  }
  const color = present(json, 'color') ? sanitizeHex(decodeHex(json.color)) : null
  let dash: DrawDash = 'solid'
  if (present(json, 'dash')) {
    if (!DRAW_DASHES.includes(json.dash as DrawDash)) throw new DrawingDecodeError('不认识的线型')
    dash = json.dash as DrawDash
  }
  let levels = DrawKind.defaultLevels(kind)
  if (present(json, 'levels')) {
    if (!Array.isArray(json.levels) || !json.levels.every(v => typeof v === 'number')) throw new DrawingDecodeError('levels 格式不对')
    levels = (json.levels as number[]).slice()
  }
  let text = ''
  if (present(json, 'text')) {
    if (typeof json.text !== 'string') throw new DrawingDecodeError('text 不是字符串')
    text = json.text
  }
  const d: Drawing = {
    id: json.id, kind, points, color,
    lineWidth: optNumber(json, 'lineWidth', 1.3), dash,
    filled: optBool(json, 'filled', true), locked: optBool(json, 'locked', false), hidden: optBool(json, 'hidden', false),
    levels, text,
  }
  if (!drawingIsValid(d)) throw new DrawingDecodeError('Invalid drawing')
  return d
}

/** 解不开就是 null（`TolerantDrawing`）。 */
export function tryDecodeDrawing(json: unknown): Drawing | null {
  try { return decodeDrawing(json) } catch { return null }
}

// ------------------------------------------------------------ 命中

/** 命中结果。 */
export interface DrawHit { id: string; part: DrawPart }

/** 点到线段的距离（原型 `distSeg`）。 */
export function distSeg(px: number, py: number, x1: number, y1: number, x2: number, y2: number): number {
  const dx = x2 - x1, dy = y2 - y1
  const len = dx * dx + dy * dy
  let t = len !== 0 ? ((px - x1) * dx + (py - y1) * dy) / len : 0
  t = Math.max(0, Math.min(1, t))
  const ex = px - (x1 + t * dx), ey = py - (y1 + t * dy)
  return Math.sqrt(ex * ex + ey * ey)
}

const HUGE_BOUNDS: DrawBounds = { left: -1e9, top: -1e9, right: 1e9, bottom: 1e9 }

/** 画线集合的命中判定。从最后一条往前找——后画的在上面。 */
export function hitDraw(draws: readonly Drawing[], px: number, py: number, xOf: (t: number) => number, yOf: (p: number) => number): DrawHit | null {
  for (let i = draws.length - 1; i >= 0; i--) {
    const d = draws[i]
    if (d.hidden) continue
    if (d.kind === 'hline') {
      if (Math.abs(yOf(drawingA(d).p) - py) < Chart.hitLinePt) return { id: d.id, part: 'body' }
      continue
    }
    const g = drawingGeometry(d, HUGE_BOUNDS, xOf, yOf)
    const part = g.hit(px, py)
    if (part) return { id: d.id, part }
  }
  return null
}

// ------------------------------------------------------------ DrawingStore

/** 画线的编辑状态：待落的点、选中项、当前工具（Swift 的值类型，这里给 `clone()`）。 */
export class DrawingStore {
  items: Drawing[] = []
  selected: string | null = null
  /** 落了几个点、还差几个。 */
  anchors: DrawPoint[] = []
  tool: DrawTool | null = null
  /** 吸附到 K 线。 */
  magnet = true

  get pending(): DrawPoint | null { return this.anchors[0] ?? null }
  set pending(v: DrawPoint | null) { this.anchors = v ? [v] : [] }

  clone(): DrawingStore {
    const s = new DrawingStore()
    s.items = this.items.map(cloneDrawing); s.selected = this.selected
    s.anchors = this.anchors.map(p => ({ ...p })); s.tool = this.tool; s.magnet = this.magnet
    return s
  }

  /** 落一个点。点数够了就收成一条线。 */
  place(pt: DrawPoint, id: string = newDrawingID()): void {
    const tool = this.tool
    if (!tool) return
    this.anchors.push(pt)
    if (this.anchors.length === DrawKind.pointCount(tool)) {
      this.items.push(drawingWith(tool, this.anchors, id))
      this.anchors = []; this.tool = null
    }
  }

  removeSelected(): void {
    const sel = this.selected
    if (sel == null) return
    this.items = this.items.filter(d => d.id !== sel)
    this.selected = null
  }

  clear(): void {
    this.items = []
    this.selected = null
    this.pending = null
  }

  /** 拖动：`part` 决定动哪一端，`body` 全部一起走。 */
  move(id: string, part: DrawPart, start: Drawing, dt: number, dp: number): void {
    const i = this.items.findIndex(d => d.id === id)
    if (i < 0 || this.items[i].locked) return
    const index = partIndex(part)
    const item = cloneDrawing(this.items[i])
    for (let j = 0; j < item.points.length; j++) {
      if ((index == null || j === index) && j < start.points.length) {
        item.points[j] = { t: start.points[j].t + dt, p: start.points[j].p + dp }
      }
    }
    this.items[i] = item
  }

  /** 所有画线端点的价格。 */
  get prices(): number[] { return this.items.flatMap(drawingPrices) }
}
