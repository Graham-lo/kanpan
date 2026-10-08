/**
 * 图表设置（照 TradingView 网页版「图表设置」：商品 / 状态栏 / 比例尺与线 / 画布四页）。
 *
 * - 一个人一份：所有图格共用同一个对象，本机存在 store（st.chartSettings），跟账号同步（settings 对象的 webChart 字段）。
 * - 颜色一律「可空覆盖」：null = 跟皮肤 / 深浅 / 涨跌色走（CSS 变量），换皮肤不会把用户没动过的颜色钉死。
 * - clean() 读档清洗：哪一项坏了就那一项回默认，其余照留；序列化后不超过 8 KB（服务端校验同一个上限）。
 */
import { sh } from '../util/format'

export type LineStyle = 'solid' | 'dashed' | 'dotted'
export type GridMode = 'both' | 'vert' | 'horz' | 'none'
export type TitleMode = 'code' | 'name' | 'both'
export type BgType = 'solid' | 'gradient'
export type DateFmt = 'yy-MM-dd' | 'yyyy-MM-dd' | 'yyyy/MM/dd' | 'dd/MM/yyyy' | 'MM/dd/yyyy' | 'dd MMM \'yy' | 'MMM dd, yyyy'
/** null = 跟皮肤 / 涨跌色 */
export type Color = string | null

export interface ChartSettings {
  // ── 商品
  /** 基于前收盘价着色（TV：Color bars based on previous close） */
  prevCloseColor: boolean
  body: boolean; bodyUp: Color; bodyDown: Color
  border: boolean; borderUp: Color; borderDown: Color
  wick: boolean; wickUp: Color; wickDown: Color
  /** 最新价线 */
  lastLine: boolean; lastLineStyle: LineStyle
  /** 最高最低价线（可见区间） */
  hiloLine: boolean
  /** 精度：null = 默认（按品种的最小变动价位），否则小数位数 */
  precision: number | null
  // ── 状态栏
  title: TitleMode
  ohlc: boolean
  barChange: boolean
  volume: boolean
  indTitles: boolean; indArgs: boolean; indValues: boolean
  legendBg: boolean; legendBgOpacity: number
  // ── 比例尺与线
  lastLabel: boolean
  indLabels: boolean
  hiloLabel: boolean
  prevClose: boolean
  weekday: boolean
  dateFmt: DateFmt
  hour12: boolean
  // ── 画布
  bgType: BgType; bg: Color; bg2: Color
  grid: GridMode; vertColor: Color; horzColor: Color
  crossColor: Color; crossWidth: number; crossStyle: LineStyle
  watermark: boolean; watermarkOpacity: number
  scaleText: Color; scaleLine: Color
  /** 画布边距：上 / 下（窗格高的百分比，K 线在主图里占多高由它定），右（根数） */
  marginTop: number; marginBottom: number; rightBars: number
}

/** 默认值照 TradingView（涨跌色、颜色跟皮肤走；边距 上 10% · 下 8% · 右 10 根） */
export const DEFAULTS: Readonly<ChartSettings> = Object.freeze({
  prevCloseColor: false,
  body: true, bodyUp: null, bodyDown: null,
  border: true, borderUp: null, borderDown: null,
  wick: true, wickUp: null, wickDown: null,
  lastLine: true, lastLineStyle: 'dotted',
  hiloLine: false,
  precision: null,
  title: 'code', ohlc: true, barChange: true, volume: false,
  indTitles: true, indArgs: true, indValues: true,
  legendBg: true, legendBgOpacity: 50,
  lastLabel: true, indLabels: true, hiloLabel: false, prevClose: false,
  weekday: true, dateFmt: 'yy-MM-dd', hour12: false,
  bgType: 'solid', bg: null, bg2: null,
  grid: 'both', vertColor: null, horzColor: null,
  crossColor: null, crossWidth: 1, crossStyle: 'dashed',
  watermark: false, watermarkOpacity: 8,
  scaleText: null, scaleLine: null,
  marginTop: 10, marginBottom: 8, rightBars: 10,
} satisfies ChartSettings)

export const LIMITS = { margin: [0, 40] as const, marginSum: 80, rightBars: [0, 200] as const, precision: [0, 10] as const, crossWidth: [1, 4] as const }
export const MAX_BYTES = 8192

export const LINE_STYLES: [LineStyle, string][] = [['solid', '实线'], ['dashed', '虚线'], ['dotted', '点线']]
export const GRID_MODES: [GridMode, string][] = [['both', '横竖'], ['vert', '竖线'], ['horz', '横线'], ['none', '无']]
export const TITLE_MODES: [TitleMode, string][] = [['code', '代码'], ['name', '全称'], ['both', '代码和全称']]
export const DATE_FMTS: DateFmt[] = ['yy-MM-dd', 'yyyy-MM-dd', 'yyyy/MM/dd', 'dd/MM/yyyy', 'MM/dd/yyyy', 'dd MMM \'yy', 'MMM dd, yyyy']

const COLOR_RE = /^#(?:[0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i
const BOOL_KEYS = ['prevCloseColor', 'body', 'border', 'wick', 'lastLine', 'hiloLine', 'ohlc', 'barChange', 'volume', 'indTitles', 'indArgs', 'indValues',
  'legendBg', 'lastLabel', 'indLabels', 'hiloLabel', 'prevClose', 'weekday', 'hour12', 'watermark'] as const
const COLOR_KEYS = ['bodyUp', 'bodyDown', 'borderUp', 'borderDown', 'wickUp', 'wickDown', 'bg', 'bg2', 'vertColor', 'horzColor', 'crossColor', 'scaleText', 'scaleLine'] as const
export const CANDLE_COLOR_KEYS = ['bodyUp', 'bodyDown', 'borderUp', 'borderDown', 'wickUp', 'wickDown'] as const

const pick = <T extends string>(v: unknown, ok: readonly T[], d: T): T => ok.includes(v as T) ? v as T : d
const int = (v: unknown, lo: number, hi: number, d: number): number => typeof v === 'number' && Number.isFinite(v) ? Math.min(hi, Math.max(lo, Math.round(v))) : d

/** 读档清洗：坏值回默认，未知键丢掉；永远返回一份完整的新对象 */
export function clean(raw: unknown): ChartSettings {
  const r = raw && typeof raw === 'object' && !Array.isArray(raw) ? raw as Record<string, unknown> : {}
  const s: ChartSettings = { ...DEFAULTS }
  const w = s as unknown as Record<string, unknown>
  for (const k of BOOL_KEYS) if (typeof r[k] === 'boolean') w[k] = r[k]
  for (const k of COLOR_KEYS) { const v = r[k]; if (v === null || (typeof v === 'string' && COLOR_RE.test(v))) w[k] = v === null ? null : (v as string).toUpperCase() }
  s.lastLineStyle = pick(r.lastLineStyle, LINE_STYLES.map(x => x[0]), DEFAULTS.lastLineStyle)
  s.crossStyle = pick(r.crossStyle, LINE_STYLES.map(x => x[0]), DEFAULTS.crossStyle)
  s.grid = pick(r.grid, GRID_MODES.map(x => x[0]), DEFAULTS.grid)
  s.title = pick(r.title, TITLE_MODES.map(x => x[0]), DEFAULTS.title)
  s.bgType = pick(r.bgType, ['solid', 'gradient'] as BgType[], DEFAULTS.bgType)
  s.dateFmt = pick(r.dateFmt, DATE_FMTS, DEFAULTS.dateFmt)
  s.precision = r.precision === null ? null : typeof r.precision === 'number' ? int(r.precision, ...LIMITS.precision, 2) : DEFAULTS.precision
  s.legendBgOpacity = int(r.legendBgOpacity, 0, 100, DEFAULTS.legendBgOpacity)
  s.watermarkOpacity = int(r.watermarkOpacity, 1, 100, DEFAULTS.watermarkOpacity)
  s.crossWidth = int(r.crossWidth, ...LIMITS.crossWidth, DEFAULTS.crossWidth)
  s.marginTop = int(r.marginTop, ...LIMITS.margin, DEFAULTS.marginTop)
  s.marginBottom = int(r.marginBottom, ...LIMITS.margin, DEFAULTS.marginBottom)
  if (s.marginTop + s.marginBottom > LIMITS.marginSum) { s.marginTop = DEFAULTS.marginTop; s.marginBottom = DEFAULTS.marginBottom }
  s.rightBars = int(r.rightBars, ...LIMITS.rightBars, DEFAULTS.rightBars)
  return s
}

/** 和默认值不同的那几项（落盘 / 同步只存这一份，小） */
export function diff(s: ChartSettings): Partial<ChartSettings> {
  const out: Record<string, unknown> = {}
  for (const [k, v] of Object.entries(s)) if ((DEFAULTS as unknown as Record<string, unknown>)[k] !== v) out[k] = v
  return out as Partial<ChartSettings>
}

export const sameSettings = (a: ChartSettings, b: ChartSettings): boolean => JSON.stringify(a) === JSON.stringify(b)

/** 换了涨跌配色（红涨绿跌 ↔ 绿涨红跌）：K 线的涨跌颜色覆盖清掉，回到跟涨跌色走——两处是同一个状态 */
export function withUpDownReset(s: ChartSettings): ChartSettings {
  const out = { ...s }
  for (const k of CANDLE_COLOR_KEYS) out[k] = null
  return out
}

// ───────────────────────────────── 引擎用的小工具

/** 线型 → 虚线段（照 TradingView 画布：点线 [w, 3w]、虚线 [5w, 6w]） */
export const dashOf = (s: LineStyle, w = 1): number[] => s === 'solid' ? [] : s === 'dashed' ? [5 * w, 6 * w] : [w, 3 * w]

/** 主图自动缩放时上下留白：可见的最高 / 最低价分别离窗格上 / 下沿 top% / bottom%（对数轴在对数空间里算） */
export function marginRange(lo: number, hi: number, top: number, bottom: number, log: boolean): { min: number; max: number } {
  const t = top / 100, b = bottom / 100, f = Math.max(0.05, 1 - t - b)
  if (log) {
    const a = Math.log(lo), z = Math.log(hi), span = (z - a) || 0.02
    return { min: Math.exp(a - span * b / f), max: Math.exp(z + span * t / f) }
  }
  // 一字线：按价格的 2% 当跨度，免得上下沿重合
  const span = (hi - lo) || Math.abs(hi) * 0.02 || 2
  return { min: lo - span * b / f, max: hi + span * t / f }
}

const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
const WEEK = ['日', '一', '二', '三', '四', '五', '六']
const p2 = (n: number): string => String(n).padStart(2, '0')

/** 日期按设置的格式（上海时间） */
export function dateText(t: number, f: DateFmt): string {
  const d = sh(t), y = d.getUTCFullYear(), m = d.getUTCMonth(), dd = d.getUTCDate()
  switch (f) {
    case 'yyyy-MM-dd': return `${y}-${p2(m + 1)}-${p2(dd)}`
    case 'yyyy/MM/dd': return `${y}/${p2(m + 1)}/${p2(dd)}`
    case 'dd/MM/yyyy': return `${p2(dd)}/${p2(m + 1)}/${y}`
    case 'MM/dd/yyyy': return `${p2(m + 1)}/${p2(dd)}/${y}`
    case 'dd MMM \'yy': return `${p2(dd)} ${MON[m]} '${p2(y % 100)}`
    case 'MMM dd, yyyy': return `${MON[m]} ${p2(dd)}, ${y}`
    default: return `${p2(y % 100)}-${p2(m + 1)}-${p2(dd)}`
  }
}

/** 十字线时间轴标签：日期格式 / 星期 / 12·24 小时制照设置 */
export function crossText(t: number, iv: number, s: Pick<ChartSettings, 'dateFmt' | 'weekday' | 'hour12'>): string {
  const d = sh(t)
  const date = dateText(t, s.dateFmt) + (s.weekday ? ` 周${WEEK[d.getUTCDay()]}` : '')
  if (iv >= 864e5) return date
  const h = d.getUTCHours(), sec = iv < 60e3 ? `:${p2(d.getUTCSeconds())}` : ''
  if (!s.hour12) return `${date}  ${p2(h)}:${p2(d.getUTCMinutes())}${sec}`
  return `${date}  ${p2(h % 12 || 12)}:${p2(d.getUTCMinutes())}${sec} ${h < 12 ? 'AM' : 'PM'}`
}

/** 上海时间这一天的 0 点（毫秒时间戳） */
export function dayStartSh(t: number): number { const off = 8 * 36e5; return Math.floor((t + off) / 864e5) * 864e5 - off }
