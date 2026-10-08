/* Hkline Web · 画线设置：每把工具照 TradingView 的出厂值、可设的项（style 白名单）、清洗与取值
 *
 * 主字段（color / width / dash / filled / levels / text）三端共用；TradingView 设置里多出来的项都进 Drawing.style，
 * 每把工具只收自己那几项（ALLOWED），值按 KEYS 的规格清洗，不认识的键、坏值一律丢（cleanStyle）。
 * 取值一律 sv(d, k)：style 里有就用，没有取这把工具的出厂值（DEF）。手机画的、老存档里的线没有 style，照出厂值画。
 *
 * 刻度（斐波那契 / 江恩 / 叉子）：style.levels（江恩箱与斐波那契扇的时间刻度 style.tlevels）是整张表 [{ v, c, on }]，
 * c 为空 = 跟画线颜色；没存过表的线按出厂表上色、开着的刻度取 d.levels（三端共用的那份）。
 * 可见范围：style.vis = { sec | min | hour | day | week | month: { on, lo, hi } }，没有 = 每个周期都显示。
 */
import type { Drawing, DrawingType } from './chart'
import { DASHES, styleColorOk, type DrawStyle, type StyleObject, type StyleValue } from './drawStyle'
import { usesFill, usesLevels } from './drawTools'

const isObj = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v)
const isNum = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v)

// ------------------------------------------------------------ 值的规格
type Spec = 'bool' | 'color' | 'line' | 'box' | 'levels' | 'vis' | { n: [number, number] } | { e: readonly string[] }
const ALIGN_H = ['left', 'center', 'right'] as const, ALIGN_V = ['top', 'middle', 'bottom'] as const
export const KEYS: Readonly<Record<string, Spec>> = {
  // 成交量分布（drawStyle.ts 读）
  rowsLayout: { e: ['rows', 'ticks'] }, rowSize: { n: [1, 1000] }, volume: { e: ['split', 'total', 'delta'] }, vaPct: { n: [1, 100] }, extendRight: 'bool',
  vp: 'bool', widthPct: { n: [1, 100] }, placement: { e: ['left', 'right'] }, up: 'color', down: 'color', vaUp: 'color', vaDown: 'color',
  values: 'bool', valuesColor: 'color', vah: 'line', val: 'line', poc: 'line', devPoc: 'line', devVa: 'line', bg: 'box',
  // 线
  extL: 'bool', extR: 'bool', startEnd: { e: ['normal', 'arrow'] }, endEnd: { e: ['normal', 'arrow'] }, midPt: 'bool', priceLbl: 'bool',
  statPrice: 'bool', statPct: 'bool', statBars: 'bool', statTime: 'bool', statAngle: 'bool', statsAlways: 'bool', statsPos: { e: ALIGN_H },
  showPrice: 'bool', showTime: 'bool',
  // 文字
  txtColor: 'color', txtSize: { n: [8, 40] }, bold: 'bool', italic: 'bool', hAlign: { e: ALIGN_H }, vAlign: { e: ALIGN_V }, txtBg: 'box', txtBorder: 'box',
  // 形状、通道
  midLine: 'line', base: 'line', upLine: 'line', dnLine: 'line', devUp: { n: [-50, 50] }, devDn: { n: [-50, 50] }, useUp: 'bool', useDn: 'bool', pearson: 'bool',
  fill: 'color', bgOn: 'bool', bgAlpha: { n: [0, 100] }, border: 'line', lblBg: 'box',
  // 斐波那契、江恩、叉子
  trend: 'line', reverse: 'bool', prices: 'bool', coeffs: 'bool', pct: 'bool', lblH: { e: ALIGN_H }, lblV: { e: ALIGN_V }, lblSize: { n: [8, 40] },
  levels: 'levels', tlevels: 'levels', angles: 'line', grid: 'line', lblL: 'bool', lblR: 'bool', lblT: 'bool', lblB: 'bool',
  fork: { e: ['original', 'schiff', 'modschiff'] }, degree: { e: ['primary', 'intermediate', 'minor', 'minute'] }, mc: 'color',
  tgtBg: 'color', stopBg: 'color',
  vis: 'vis',
}

// ------------------------------------------------------------ 每把工具收哪些键
const STATS = ['statPrice', 'statPct', 'statBars', 'statTime', 'statAngle', 'statsAlways', 'statsPos']
const TXT = ['txtColor', 'txtSize', 'bold', 'italic']
const TXT_AL = [...TXT, 'hAlign', 'vAlign']
const LINE = ['extL', 'extR', 'startEnd', 'endEnd', 'midPt', 'priceLbl', ...STATS, ...TXT_AL]
const FIB = ['trend', 'extL', 'extR', 'reverse', 'prices', 'coeffs', 'pct', 'lblH', 'lblV', 'lblSize', 'bgOn', 'bgAlpha', 'levels']
const RANGE = ['fill', 'lblBg', 'txtColor', 'txtSize']
const PROFILE_KEYS = ['rowsLayout', 'rowSize', 'volume', 'vaPct', 'extendRight', 'vp', 'widthPct', 'placement', 'up', 'down', 'vaUp', 'vaDown', 'values', 'valuesColor', 'vah', 'val', 'poc', 'devPoc', 'devVa', 'bg']
const ALLOWED_LIST: Partial<Record<DrawingType, string[]>> = {
  trend: LINE, ray: LINE, extended: LINE, arrowLine: LINE,
  hline: ['showPrice', ...TXT_AL], hray: ['showPrice', ...TXT_AL], vline: ['showTime', ...TXT_AL], crossLine: ['showPrice', 'showTime'],
  channel: ['midLine', 'fill', 'extL', 'extR', ...TXT_AL],
  regression: ['base', 'upLine', 'dnLine', 'devUp', 'devDn', 'useUp', 'useDn', 'pearson', 'fill', 'extR'],
  pitchfork: ['fork', 'midLine', 'extR', 'bgAlpha', 'levels'],
  gannBox: ['reverse', 'angles', 'lblL', 'lblR', 'lblT', 'lblB', 'bgAlpha', 'levels', 'tlevels'],
  gannFan: ['coeffs', 'bgOn', 'bgAlpha', 'levels'],
  fib: FIB, fibExtension: FIB,
  fibChannel: ['extL', 'extR', 'prices', 'coeffs', 'lblH', 'lblV', 'lblSize', 'bgAlpha', 'levels'],
  fibTimeZone: ['trend', 'coeffs', 'lblH', 'lblV', 'lblSize', 'bgOn', 'bgAlpha', 'levels'],
  fibFan: ['grid', 'lblL', 'lblR', 'lblT', 'lblB', 'bgOn', 'bgAlpha', 'levels', 'tlevels'],
  xabcd: ['fill', ...TXT], abcd: TXT, headShoulders: ['fill', 'bgOn', ...TXT], triangle: ['fill'],
  elliottImpulse: ['degree', ...TXT], elliottCorrection: ['degree', ...TXT],
  ptMeasure: RANGE, priceRange: ['extL', 'extR', ...RANGE], dateRange: RANGE, datePriceRange: ['border', ...RANGE],
  rect: ['fill', 'midLine', 'extL', 'extR', ...TXT_AL], ellipse: ['fill', ...TXT_AL], curve: ['startEnd', 'endEnd'],
  note: [...TXT, 'txtBg', 'txtBorder'], callout: [...TXT, 'fill'], priceLabel: ['txtColor', 'txtSize', 'bold'], flag: ['txtColor', 'txtSize'],
  markerUp: ['mc', 'txtColor', 'txtSize'], markerDown: ['mc', 'txtColor', 'txtSize'],
  avwap: ['priceLbl'], position: ['tgtBg', 'stopBg', 'txtColor', 'txtSize'],
  fvp: PROFILE_KEYS, anchoredVolumeProfile: PROFILE_KEYS,
}
export const ALLOWED: Readonly<Partial<Record<DrawingType, ReadonlySet<string>>>> = Object.fromEntries(
  Object.entries(ALLOWED_LIST).map(([t, ks]) => [t, new Set([...ks, 'vis'])]))
export const allows = (t: DrawingType, k: string): boolean => !!ALLOWED[t]?.has(k)
/** 能写字的（文字页有输入框）：手机 usesText 的三把，加上 TradingView 线、形状、记号上那句字 */
export const TEXT_ON: ReadonlySet<DrawingType> = new Set<DrawingType>([
  'note', 'callout', 'flag', 'trend', 'ray', 'extended', 'arrowLine', 'hline', 'hray', 'vline', 'channel', 'rect', 'ellipse', 'markerUp', 'markerDown',
])
/** 背景按各条刻度的颜色铺（设置里是「背景 + 透明度」）的几把 */
export const LEVEL_BG: ReadonlySet<DrawingType> = new Set<DrawingType>(['fib', 'fibExtension', 'fibChannel', 'fibTimeZone', 'fibFan', 'gannBox', 'gannFan', 'pitchfork'])

// ------------------------------------------------------------ TradingView 出厂值
export interface LevelRow { v: number; c: string; on: boolean }
const LV = (rows: [number, string, boolean?][]): LevelRow[] => rows.map(([v, c, on]) => ({ v, c, on: on !== false }))
const FIB_TABLE = LV([
  [0, ''], [0.236, '#F23645'], [0.382, '#FF9800'], [0.5, '#4CAF50'], [0.618, '#089981'], [0.786, '#00BCD4'], [1, ''],
  [1.618, '#2962FF'], [2.618, '#F23645'], [3.618, '#9C27B0'], [4.236, '#E91E63'], [1.272, '#FF9800', false],
  [1.414, '#F23645', false], [2.272, '#FF9800', false], [2.414, '#4CAF50', false], [2, '#089981', false], [3, '#00BCD4', false],
  [3.272, '#808080', false], [3.414, '#2962FF', false], [4, '#F23645', false], [4.272, '#9C27B0', false], [4.414, '#E91E63', false],
  [4.618, '#FF9800', false], [4.764, '#089981', false],
])
const RETRACE7 = LV([[0, ''], [0.236, '#F23645'], [0.382, '#FF9800'], [0.5, '#4CAF50'], [0.618, '#089981'], [0.786, '#00BCD4'], [1, '']])
const TZ_TABLE = LV([[0, ''], [1, '#2962FF'], [2, '#2962FF'], [3, '#2962FF'], [5, '#2962FF'], [8, '#2962FF'], [13, '#2962FF'], [21, '#2962FF'], [34, '#2962FF'], [55, '#2962FF'], [89, '#2962FF']])
const GANN_BOX = LV([[0, ''], [0.25, '#FF9800'], [0.382, '#00BCD4'], [0.5, '#4CAF50'], [0.618, '#089981'], [0.75, '#2962FF'], [1, '']])
const GANN_FAN = LV([[0.125, '#FF9800'], [0.25, '#089981'], [0.333, '#4CAF50'], [0.5, '#089981'], [1, ''], [2, '#2962FF'], [3, '#9C27B0'], [4, '#E91E63'], [8, '#F23645']])
const FORK = LV([[0.25, '#FFB74D', false], [0.382, '#81C784', false], [0.5, '#089981'], [0.618, '#089981', false], [0.75, '#00BCD4', false],
  [1, '#2962FF'], [1.5, '#9C27B0', false], [1.75, '#E91E63', false], [2, '#F77C80', false]])
export const LEVEL_TABLE: Partial<Record<DrawingType, { levels: LevelRow[]; tlevels?: LevelRow[] }>> = {
  fib: { levels: FIB_TABLE }, fibExtension: { levels: FIB_TABLE }, fibChannel: { levels: FIB_TABLE }, fibTimeZone: { levels: TZ_TABLE },
  fibFan: { levels: RETRACE7, tlevels: RETRACE7 }, gannBox: { levels: GANN_BOX, tlevels: GANN_BOX }, gannFan: { levels: GANN_FAN }, pitchfork: { levels: FORK },
}
/** 江恩箱的 0 与 1 是箱框本身，不进三端共用的 d.levels */
const FRAME_ONLY: Partial<Record<DrawingType, number[]>> = { gannBox: [0, 1] }

const L = (color: string, width = 1, dash: 'solid' | 'dashed' | 'dotted' = 'solid', on = true): StyleObject => ({ on, color, width, dash })
const LINE_DEF = { extL: false, extR: false, startEnd: 'normal', endEnd: 'normal', midPt: false, priceLbl: false, statPrice: false, statPct: false, statBars: false, statTime: false, statAngle: false, statsAlways: false, statsPos: 'right', txtSize: 14, bold: false, italic: false, hAlign: 'center', vAlign: 'top' }
const FIB_DEF = { trend: L('#808080', 1, 'dashed'), extL: false, extR: false, reverse: false, prices: true, coeffs: true, pct: false, lblH: 'left', lblV: 'middle', lblSize: 12, bgOn: true, bgAlpha: 80 }
const RANGE_DEF = { lblBg: { on: true, color: '' }, txtColor: '#FFFFFF', txtSize: 12 }
/** 主字段的出厂值（新画一条、恢复出厂用）：颜色、粗细、线型、填色 */
export interface MainDef { color: string; width: number; dash?: 'dashed' | 'dotted'; filled?: boolean }
const M = (color: string, width = 2, filled?: boolean, dash?: 'dashed' | 'dotted'): MainDef => ({ color, width, ...(dash ? { dash } : {}), ...(filled != null ? { filled } : {}) })
export const MAIN_DEF: Partial<Record<DrawingType, MainDef>> = {
  trend: M('#2962FF'), ray: M('#2962FF'), extended: M('#2962FF'), arrowLine: M('#2962FF'), hline: M('#2962FF'), hray: M('#2962FF'),
  vline: M('#2962FF'), crossLine: M('#2962FF'), channel: M('#2962FF', 2, true), regression: M('#2962FF', 2, true), pitchfork: M('#F23645', 2, true),
  gannBox: M('#808080', 1, true), gannFan: M('#808080', 1), fib: M('#808080', 1), fibExtension: M('#808080', 1), fibChannel: M('#808080', 1, true),
  fibTimeZone: M('#808080', 1), fibFan: M('#808080', 1), xabcd: M('#2962FF', 2, true), abcd: M('#089981'), headShoulders: M('#089981', 2),
  triangle: M('#F57C00', 2, true), elliottImpulse: M('#3D85C6'), elliottCorrection: M('#3D85C6'), ptMeasure: M('#2962FF', 1),
  priceRange: M('#2962FF', 1, true), dateRange: M('#2962FF', 1, true), datePriceRange: M('#2962FF', 1, true), rect: M('#9C27B0', 2, true),
  ellipse: M('#F23645', 2, true), curve: M('#2962FF'), note: M('#2962FF'), callout: M('#0097A7', 2, true), priceLabel: M('#2962FF'),
  flag: M('#2962FF', 2, true), markerUp: M('#089981', 2, true), markerDown: M('#CC2F3C', 2, true), avwap: M('#1E88E5', 1),
  fvp: M('#2962FF'), anchoredVolumeProfile: M('#2962FF'), position: M('#808080', 1, true),
}
export const DEF: Readonly<Partial<Record<DrawingType, StyleObject>>> = {
  trend: LINE_DEF, ray: { ...LINE_DEF, extR: true }, extended: { ...LINE_DEF, extL: true, extR: true }, arrowLine: { ...LINE_DEF, endEnd: 'arrow' },
  hline: { showPrice: true, txtSize: 12, bold: false, italic: false, hAlign: 'center', vAlign: 'top' },
  hray: { showPrice: true, txtSize: 12, bold: false, italic: false, hAlign: 'center', vAlign: 'top' },
  vline: { showTime: true, txtSize: 14, bold: false, italic: false, hAlign: 'center', vAlign: 'top' },
  crossLine: { showPrice: true, showTime: true },
  channel: { midLine: L('#2962FF', 1, 'dashed'), extL: false, extR: false, txtSize: 14, bold: false, italic: false, hAlign: 'left', vAlign: 'bottom' },
  regression: { base: L('#F236454D', 1, 'dashed'), upLine: { on: true, color: '' }, dnLine: { on: true, color: '' }, devUp: 2, devDn: -2, useUp: true, useDn: true, pearson: true, extR: false },
  pitchfork: { fork: 'original', midLine: L('#F23645', 2), extR: true, bgAlpha: 80 },
  gannBox: { reverse: false, angles: L('#9C9C9C', 1, 'solid', false), lblL: true, lblR: true, lblT: true, lblB: true, bgAlpha: 80 },
  gannFan: { coeffs: true, bgOn: true, bgAlpha: 80 },
  fib: FIB_DEF, fibExtension: FIB_DEF,
  fibChannel: { extL: false, extR: false, prices: true, coeffs: true, lblH: 'left', lblV: 'middle', lblSize: 12, bgAlpha: 80 },
  fibTimeZone: { trend: L('#808080', 1, 'dashed'), coeffs: true, lblH: 'right', lblV: 'bottom', lblSize: 12, bgOn: false, bgAlpha: 80 },
  fibFan: { grid: L('#153899CC', 1), lblL: true, lblR: true, lblT: true, lblB: true, bgOn: true, bgAlpha: 80 },
  xabcd: { txtColor: '#FFFFFF', txtSize: 12, bold: false, italic: false }, abcd: { txtSize: 12, bold: false, italic: false },
  headShoulders: { bgOn: true, txtColor: '#FFFFFF', txtSize: 12, bold: false, italic: false },
  elliottImpulse: { degree: 'minor', txtSize: 12, bold: false, italic: false }, elliottCorrection: { degree: 'minor', txtSize: 12, bold: false, italic: false },
  ptMeasure: RANGE_DEF, priceRange: { extL: false, extR: false, ...RANGE_DEF }, dateRange: RANGE_DEF,
  datePriceRange: { border: L('', 1, 'solid', false), ...RANGE_DEF },
  rect: { midLine: L('', 1, 'dashed', false), extL: false, extR: false, txtSize: 14, bold: false, italic: false, hAlign: 'center', vAlign: 'middle' },
  ellipse: { txtSize: 14, bold: false, italic: false, hAlign: 'center', vAlign: 'middle' }, curve: { startEnd: 'normal', endEnd: 'normal' },
  note: { txtSize: 14, bold: false, italic: false, txtBg: { on: false, color: '' }, txtBorder: { on: false, color: '' } },
  callout: { txtColor: '#FFFFFF', txtSize: 14, bold: false, italic: false, fill: '#0097A7B3' },
  priceLabel: { txtColor: '#FFFFFF', txtSize: 14, bold: true }, flag: { txtSize: 12 },
  markerUp: { txtSize: 12 }, markerDown: { txtSize: 12 },
  avwap: { priceLbl: true }, position: { tgtBg: '#08998133', stopBg: '#F2364533', txtColor: '#FFFFFF', txtSize: 12 },
}
/** 没设填色时：画线颜色 × 这把工具的出厂透明度 */
export const FILL_ALPHA: Partial<Record<DrawingType, number>> = {
  rect: 0.2, channel: 0.2, regression: 0.1, ellipse: 0.2, triangle: 0.2, xabcd: 0.15, headShoulders: 0.15, ptMeasure: 0.15,
  priceRange: 0.15, dateRange: 0.15, datePriceRange: 0.15, flag: 1, markerUp: 1, markerDown: 1,
}

// ------------------------------------------------------------ 清洗
function cleanLine(v: unknown): StyleObject | null {
  if (!isObj(v)) return null
  const o: StyleObject = {}
  if (typeof v.on === 'boolean') o.on = v.on
  if (styleColorOk(v.color)) o.color = v.color
  if (isNum(v.width) && v.width >= 0.5 && v.width <= 6) o.width = v.width
  if (DASHES.includes(v.dash as never)) o.dash = v.dash as string
  if (typeof v.extend === 'boolean') o.extend = v.extend
  return Object.keys(o).length ? o : null
}
function cleanBox(v: unknown): StyleObject | null {
  if (!isObj(v)) return null
  const o: StyleObject = {}
  if (typeof v.on === 'boolean') o.on = v.on
  if (styleColorOk(v.color) || v.color === '') o.color = v.color as string
  return Object.keys(o).length ? o : null
}
function cleanLevels(v: unknown): StyleValue[] | null {
  if (!Array.isArray(v) || v.length > 24) return null
  const out: StyleValue[] = []
  for (const x of v) {
    if (!isObj(x) || !isNum(x.v) || Math.abs(x.v) > 1000) return null
    out.push({ v: x.v, c: styleColorOk(x.c) ? x.c : '', on: x.on !== false })
  }
  return out
}
export const VIS_CLASSES = ['sec', 'min', 'hour', 'day', 'week', 'month'] as const
export type VisClass = typeof VIS_CLASSES[number]
export const VIS_RANGE: Readonly<Record<VisClass, [number, number]>> = { sec: [1, 59], min: [1, 59], hour: [1, 24], day: [1, 366], week: [1, 52], month: [1, 12] }
function cleanVis(v: unknown): StyleObject | null {
  if (!isObj(v)) return null
  const o: StyleObject = {}
  for (const k of VIS_CLASSES) {
    const x = v[k]; if (!isObj(x)) continue
    const [lo0, hi0] = VIS_RANGE[k]
    const lo = isNum(x.lo) ? Math.max(lo0, Math.min(hi0, Math.round(x.lo))) : lo0
    const hi = isNum(x.hi) ? Math.max(lo, Math.min(hi0, Math.round(x.hi))) : hi0
    o[k] = { on: x.on !== false, lo, hi }
  }
  return Object.keys(o).length ? o : null
}
function cleanValue(spec: Spec, v: unknown): StyleValue | null {
  if (spec === 'bool') return typeof v === 'boolean' ? v : null
  if (spec === 'color') return styleColorOk(v) ? v : null
  if (spec === 'line') return cleanLine(v)
  if (spec === 'box') return cleanBox(v)
  if (spec === 'levels') return cleanLevels(v)
  if (spec === 'vis') return cleanVis(v)
  if ('n' in spec) return isNum(v) && v >= spec.n[0] && v <= spec.n[1] ? v : null
  return typeof v === 'string' && spec.e.includes(v) ? v : null
}
/** 一条画线的 style 只留这把工具认的键与合规的值；清完是空的返回 null。整份超过 8 KB 也返回 null（服务端同一上限） */
export function cleanStyle(type: DrawingType, raw: unknown): DrawStyle | null {
  if (!isObj(raw)) return null
  const ok = ALLOWED[type]; if (!ok) return null
  const out: DrawStyle = {}
  for (const [k, v] of Object.entries(raw)) {
    if (!ok.has(k)) continue
    const spec = KEYS[k]; if (!spec) continue
    const c = cleanValue(spec, v)
    if (c != null) out[k] = c
  }
  if (!Object.keys(out).length) return null
  return JSON.stringify(out).length <= 8192 ? out : null
}

// ------------------------------------------------------------ 取值
/** 这条线这一项的值：style 里有就用，没有取这把工具的出厂值 */
export function sv<T extends StyleValue = StyleValue>(d: Pick<Drawing, 'type' | 'style'>, k: string): T | undefined {
  const v = d.style?.[k]
  return (v !== undefined ? v : DEF[d.type]?.[k]) as T | undefined
}
export const svb = (d: Pick<Drawing, 'type' | 'style'>, k: string): boolean => sv(d, k) === true
export const svn = (d: Pick<Drawing, 'type' | 'style'>, k: string, def: number): number => { const v = sv(d, k); return isNum(v) ? v : def }
export const svs = (d: Pick<Drawing, 'type' | 'style'>, k: string, def: string): string => { const v = sv(d, k); return typeof v === 'string' ? v : def }
export interface LineS { on: boolean; color: string; width: number; dash: 'solid' | 'dashed' | 'dotted' }
/** style 里一条副线（中线、趋势线、基线……）：颜色为空 = 跟画线颜色 */
export function lineS(d: Pick<Drawing, 'type' | 'style' | 'color' | 'width'>, k: string): LineS {
  const def = isObj(DEF[d.type]?.[k]) ? DEF[d.type]![k] as StyleObject : {}
  const v = isObj(d.style?.[k]) ? d.style![k] as StyleObject : {}
  const pick = <T>(f: string, fb: T): T => (v[f] !== undefined ? v[f] : def[f] !== undefined ? def[f] : fb) as T
  const color = pick<string>('color', '')
  return { on: pick('on', true), color: styleColorOk(color) ? color : d.color || '#2962FF', width: pick('width', d.width || 1), dash: pick('dash', 'solid') }
}
/** 方框类（文字底色、边框、读数底色）：颜色为空 = 跟画线颜色 */
export function boxS(d: Pick<Drawing, 'type' | 'style' | 'color'>, k: string): { on: boolean; color: string } {
  const def = isObj(DEF[d.type]?.[k]) ? DEF[d.type]![k] as StyleObject : {}
  const v = isObj(d.style?.[k]) ? d.style![k] as StyleObject : {}
  const on = (v.on ?? def.on ?? false) as boolean, c = (v.color ?? def.color ?? '') as string
  return { on, color: styleColorOk(c) ? c : d.color || '#2962FF' }
}
/** #RRGGBB(AA) × mul → rgba()（透明度乘上去） */
export function rgbaOf(hex: string, mul = 1): string {
  const h = /^#([0-9a-f]{6})([0-9a-f]{2})?$/i.exec(hex || '')
  if (!h) return hex
  const n = parseInt(h[1], 16), a = (h[2] ? parseInt(h[2], 16) / 255 : 1) * mul
  return `rgba(${n >> 16 & 255},${n >> 8 & 255},${n & 255},${Math.max(0, Math.min(1, +a.toFixed(3)))})`
}
/** #RRGGBB(AA) → 六位色 + 不透明度 0–1 */
export function splitHex(hex: string): [string, number] {
  const h = /^#([0-9a-f]{6})([0-9a-f]{2})?$/i.exec(hex || '')
  return h ? ['#' + h[1].toUpperCase(), h[2] ? parseInt(h[2], 16) / 255 : 1] : ['#2962FF', 1]
}
export function joinHex(hex6: string, alpha: number): string {
  const a = Math.round(Math.max(0, Math.min(1, alpha)) * 255)
  return a >= 255 ? hex6.toUpperCase() : hex6.toUpperCase() + a.toString(16).padStart(2, '0').toUpperCase()
}
/** 这块面用什么颜色：style.fill，没有就画线颜色 × 出厂透明度 */
export function fillOf(d: Pick<Drawing, 'type' | 'style' | 'color'>): string {
  const f = sv(d, 'fill')
  if (styleColorOk(f)) return rgbaOf(f)
  return rgbaOf((d.color || '#2962FF').slice(0, 7), FILL_ALPHA[d.type] ?? 0.2)
}
/** 填色开着吗：手机认的那几把听 d.filled，其余听 style.bgOn */
export function fillOn(d: Pick<Drawing, 'type' | 'style' | 'filled'>): boolean {
  return usesFill(d.type) ? d.filled !== false : sv(d, 'bgOn') !== false
}

/** 刻度表（整张，含关着的）：存过表的用存的；没存过的照出厂表上色、开着的取 d.levels（三端共用那份）；出厂表里没有的值补在后面 */
export function levelRows(d: Pick<Drawing, 'type' | 'style' | 'levels'>, k: 'levels' | 'tlevels' = 'levels'): LevelRow[] {
  const s = d.style?.[k]
  const table = Array.isArray(s) ? (s as StyleObject[]).map(x => ({ v: x.v as number, c: (x.c as string) || '', on: x.on !== false })) : (LEVEL_TABLE[d.type]?.[k] ?? []).map(x => ({ ...x }))
  if (k === 'tlevels' || !usesLevels(d.type) || !d.levels) return table
  // 三端口径内（|v| ≤ 10、不是箱框）的刻度开没开听 d.levels：手机上关掉一条，网页存过的表也跟着
  const frame = FRAME_ONLY[d.type] ?? []
  const on = new Set(d.levels)
  const rows = table.map(x => ({ ...x, on: frame.includes(x.v) || Math.abs(x.v) > 10 ? x.on : on.has(x.v) }))
  for (const v of d.levels) if (!table.some(x => x.v === v)) rows.push({ v, c: '', on: true })
  return rows
}
/** 刻度表 → 三端共用的 d.levels（开着的、|v| ≤ 10、江恩箱去掉箱框那两条，最多 24 个） */
export function contractLevels(type: DrawingType, rows: readonly LevelRow[]): number[] {
  const frame = FRAME_ONLY[type] ?? []
  return rows.filter(x => x.on && Math.abs(x.v) <= 10 && !frame.includes(x.v)).map(x => x.v).slice(0, 24)
}
/** 新画一条的出厂刻度：d.levels 与（出厂表里开着的值超出三端口径时）整张表 */
export function factoryLevels(type: DrawingType): { levels?: number[]; style?: StyleObject } {
  const t = LEVEL_TABLE[type]; if (!t) return {}
  const out: { levels?: number[]; style?: StyleObject } = {}
  if (usesLevels(type)) out.levels = contractLevels(type, t.levels)
  if (t.levels.some(x => x.on && Math.abs(x.v) > 10)) out.style = { levels: t.levels.map(x => ({ ...x })) }
  return out
}

// ------------------------------------------------------------ 可见范围
const CLASS_MS: Readonly<Record<VisClass, number>> = { sec: 1e3, min: 6e4, hour: 36e5, day: 864e5, week: 6048e5, month: 2592e6 }
/** 周期（毫秒）归哪一类、是几（秒 / 分 / 时 / 日 / 周 / 月） */
export function visClass(ivMs: number): { k: VisClass; n: number } {
  const k: VisClass = ivMs < 6e4 ? 'sec' : ivMs < 36e5 ? 'min' : ivMs < 864e5 ? 'hour' : ivMs < 6048e5 ? 'day' : ivMs < 2592e6 ? 'week' : 'month'
  return { k, n: Math.max(1, Math.round(ivMs / CLASS_MS[k])) }
}
/** 这条线在这个周期上显示吗（设置「可见范围」）；没设 = 都显示 */
export function visibleAt(d: Pick<Drawing, 'style'>, ivMs: number): boolean {
  const v = d.style?.vis
  if (!isObj(v) || !(ivMs > 0)) return true
  const { k, n } = visClass(ivMs)
  const x = v[k]
  if (!isObj(x)) return true
  if (x.on === false) return false
  const [lo0, hi0] = VIS_RANGE[k]
  return n >= (isNum(x.lo) ? x.lo : lo0) && n <= (isNum(x.hi) ? x.hi : hi0)
}

/** 艾略特浪级：标签写法 */
export function waveLabels(type: DrawingType, degree: string): string[] {
  const imp = type === 'elliottImpulse'
  const base = imp ? ['0', '1', '2', '3', '4', '5'] : ['0', 'A', 'B', 'C']
  switch (degree) {
    case 'primary': return imp ? ['⓪', '①', '②', '③', '④', '⑤'] : ['⓪', 'Ⓐ', 'Ⓑ', 'Ⓒ']
    case 'intermediate': return base.map(x => `(${x})`)
    case 'minute': return imp ? ['0', 'i', 'ii', 'iii', 'iv', 'v'] : ['0', 'a', 'b', 'c']
    default: return base
  }
}
