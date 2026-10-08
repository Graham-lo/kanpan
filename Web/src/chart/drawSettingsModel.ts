/* Hkline Web · 画线设置对话框的「行」：给一把工具、一条线，算出每页有哪些行、每行几个控件、当前值与出厂值
 *
 * 对话框（pages/drawSettingsDialog.ts）只负责把这里的行画出来、把改动按 path 交回 applyEdit；
 * 哪把工具有哪几页、一页里排哪些行、改一项后 d 长什么样，全在这里（vitest 不用 DOM 就能测）。
 *
 * 页：输入 / 样式 / 文本 / 坐标 / 可见范围（照 TradingView 画线设置）。行的顺序照 TradingView 各工具弹窗，
 * 没单独排的工具按 drawSpec 的 ALLOWED 顺序；每把工具 ALLOWED 里的键（可见范围除外）恰好出现在某一页的某一行上。
 *
 * 控件的 path：
 *   main.color / main.width / main.dash / main.filled    三端共用的主字段
 *   text                                                  这条线写的那句字
 *   style.<键>          扩展项整值（bool / color / enum / num）；值给 undefined = 回到出厂（删键）
 *   style.<键>.<字段>   副线 / 方框的一个字段（on / color / width / dash / extend）；color 给 '' = 跟画线颜色
 *   lv.<levels|tlevels>.<行>.<on|v|c>                    刻度表一行；改完同时写 d.levels（三端口径）与 style 里整张表
 *   pt.<n>.<p|t>                                         第 n 个锚点的价格 / 时间（毫秒）
 *   vis.<类>.<on|lo|hi>                                  可见范围一类
 */
import type { Drawing, DrawingType } from './chart'
import { DS, fill } from '../terms'
import {
  ALLOWED, DEF, FILL_ALPHA, KEYS, LEVEL_TABLE, MAIN_DEF, TEXT_ON, VIS_CLASSES, VIS_RANGE,
  allows, boxS, cleanStyle, contractLevels, fillOn, joinHex, levelRows, lineS, splitHex, sv, svb, svs,
  type LevelRow, type VisClass,
} from './drawSpec'
import { PROFILE_INPUT_DEFAULTS, profileInputs, profileLookOf, styleColorOk, type DrawStyle, type StyleObject, type StyleValue } from './drawStyle'
import { profileDefaults } from './volumeProfile'
import { ANCHOR_COUNT, TEXT_LIMIT, isProfile, usesFill, usesLevels, usesText } from './drawTools'
import { graphemeCount } from '../m/chart/draw/fmt'
import { TZ_MS, pad } from '../util/format'

export type TabId = 'inputs' | 'style' | 'text' | 'coords' | 'vis'
export const TAB_LABEL: Readonly<Record<TabId, string>> = { inputs: DS.tabInputs, style: DS.tabStyle, text: DS.tabText, coords: DS.tabCoords, vis: DS.tabVis }

export type Dash = 'solid' | 'dashed' | 'dotted'
/** 一个控件：kind 决定画成什么；path 是改它时交给 applyEdit 的地址 */
export type Ctl =
  /** 勾选：行首那颗用行的标签；放在行尾控件里的（成交量分布各条线的「延伸」）带自己的 label */
  | { kind: 'check'; path: string; value: boolean; def?: boolean; label?: string }
  /** 色块：value 是存着的（'' = 没设，显示 shown）；alpha = 调色板带不透明度；clear = 有「默认」一键回到出厂 / 跟画线色 */
  | { kind: 'color'; path: string; value: string; shown: string; def?: string; alpha: boolean; clear: boolean }
  | { kind: 'width'; path: string; value: number; def?: number }
  | { kind: 'dash'; path: string; value: Dash; def?: Dash }
  | { kind: 'enum'; path: string; value: string; options: [string, string][]; def?: string }
  /** pre：框前的小字（「背景」一行里的透明度）；unit：框后的单位 */
  | { kind: 'num'; path: string; value: number; min: number; max: number; step: number; pre?: string; unit?: string; def?: number }
  /** 粗体 / 斜体：图标式的开关按钮 */
  | { kind: 'toggle'; path: string; value: boolean; icon: 'bold' | 'italic'; label: string; def?: boolean }
  | { kind: 'text'; path: string; value: string; max: number }
  | { kind: 'time'; path: string; value: number }

export type Row =
  | { kind: 'group'; label: string }
  /** 一行：key 是这行主要管的那个键（测试与对话框定位用）；check 在行首（勾选 + 标签），ctls 在右边 */
  | { kind: 'row'; key: string; label: string; check?: Ctl & { kind: 'check' }; ctls: Ctl[] }
  | { kind: 'levels'; key: 'levels' | 'tlevels'; label: string; rows: LevelRow[]; lineColor: string }

// ------------------------------------------------------------ 能调哪些主字段（选中快捷条与设置框共用）
/** 这条画线能调哪些主字段（多空持仓固定红绿；两把成交量分布只有框色；标注类没有线宽线型；刻度一族没有线型） */
export function knobs(t: DrawingType): { color: boolean; width: boolean; dash: boolean; fill: boolean; text: boolean } {
  const fill = usesFill(t) && t !== 'position', text = usesText(t)
  if (t === 'position') return { color: false, width: false, dash: false, fill: false, text: false }
  if (t === 'fvp' || t === 'anchoredVolumeProfile') return { color: true, width: false, dash: false, fill: false, text: false }
  if (t === 'note' || t === 'callout' || t === 'flag' || t === 'priceLabel' || t === 'markerUp' || t === 'markerDown') return { color: true, width: false, dash: false, fill, text }
  return { color: true, width: true, dash: t !== 'fib' && !usesLevels(t), fill, text }
}

// ------------------------------------------------------------ 每页排哪些行
const STATS = ['statPrice', 'statPct', 'statBars', 'statTime', 'statAngle', 'statsPos', 'statsAlways']
const LINE_ORDER = ['main', 'startEnd', 'endEnd', 'extL', 'extR', 'midPt', 'priceLbl', '#stats', ...STATS]
const FIB_ORDER = ['trend', 'main', 'levels', 'extL', 'extR', 'fill', 'reverse', 'prices', 'coeffs', 'pct', 'lblPos', 'lblSize']
/** 照 TradingView 弹窗排的；没列的工具按 ALLOWED 顺序（主线、背景在前，文字一行在后） */
const STYLE_ORDER: Partial<Record<DrawingType, string[]>> = {
  trend: LINE_ORDER, ray: LINE_ORDER, extended: LINE_ORDER, arrowLine: LINE_ORDER,
  channel: ['main', 'midLine', 'extL', 'extR', 'fill'],
  regression: ['base', 'upLine', 'dnLine', 'main', 'extR', 'pearson', 'fill'],
  // TV 叉子样式页第一行就是「样式」（标准 / 希夫 / 改良希夫）
  pitchfork: ['fork', 'main', 'midLine', 'levels', 'extR', 'fill'],
  gannBox: ['main', 'angles', 'levels', 'tlevels', 'reverse', 'lblL', 'lblR', 'lblT', 'lblB', 'fill'],
  gannFan: ['main', 'levels', 'coeffs', 'fill'],
  fib: FIB_ORDER, fibExtension: FIB_ORDER,
  fibChannel: ['main', 'levels', 'extL', 'extR', 'fill', 'prices', 'coeffs', 'lblPos', 'lblSize'],
  fibTimeZone: ['trend', 'main', 'levels', 'fill', 'coeffs', 'lblPos', 'lblSize'],
  fibFan: ['main', 'grid', 'levels', 'tlevels', 'lblL', 'lblR', 'lblT', 'lblB', 'fill'],
}
/** 输入页（照 TradingView 的 Inputs：成交量分布的五项、回归的上 / 下偏差）；皮尔逊、叉子样式、艾略特浪级、
 *  斐波那契 / 江恩箱的反转在 TV 都是样式页上的项，跟着样式页走（10-09 用户：「pc 端按照 tv 做即可」） */
const INPUT_ORDER: Partial<Record<DrawingType, string[]>> = {
  fvp: ['rowsLayout', 'rowSize', 'volume', 'vaPct', 'extendRight'], anchoredVolumeProfile: ['rowsLayout', 'rowSize', 'volume', 'vaPct', 'extendRight'],
  regression: ['devUp', 'devDn'],
}
const TEXT_ORDER = ['text', 'font', 'hAlign', 'vAlign', 'txtBg', 'txtBorder']
/** 合成一行的键（行 → 它管的键） */
const COMPOSITE: Readonly<Record<string, string[]>> = {
  fill: ['fill', 'bgOn', 'bgAlpha'], font: ['txtColor', 'txtSize', 'bold', 'italic'], lblPos: ['lblH', 'lblV'], values: ['values', 'valuesColor'],
  devUp: ['devUp', 'useUp'], devDn: ['devDn', 'useDn'],
}
const tokenOf = (k: string): string => {
  for (const [tok, ks] of Object.entries(COMPOSITE)) if (ks.includes(k)) return tok
  return STATS.includes(k) ? '#stats' : k
}
const inputKeys = (t: DrawingType): string[] => (INPUT_ORDER[t] ?? []).flatMap(k => COMPOSITE[k] ?? [k])
const textKeys = (t: DrawingType): string[] => TEXT_ON.has(t) ? TEXT_ORDER.flatMap(k => COMPOSITE[k] ?? [k]) : []

/** 样式页的行序（记号：main 主线、fill 背景、font 文字一行、lblPos 标签位置、#stats 统计小节） */
function styleTokens(t: DrawingType): string[] {
  const ok = ALLOWED[t] ?? new Set<string>()
  const skip = new Set([...inputKeys(t), ...textKeys(t), 'vis'])
  const k = knobs(t)
  const out: string[] = []
  const push = (x: string) => { if (!out.includes(x)) out.push(x) }
  for (const x of STYLE_ORDER[t] ?? ['main', 'fill']) push(x)
  for (const x of ok) if (!skip.has(x)) { const tok = tokenOf(x); push(tok); if (tok === '#stats') STATS.filter(s => ok.has(s)).forEach(push) }
  return out.filter(x => {
    if (x === 'main') return k.color || k.width || k.dash
    if (x === 'fill') return k.fill || ok.has('bgOn') || ok.has('fill') || ok.has('bgAlpha')
    if (x === '#stats') return STATS.some(s => ok.has(s))
    if (COMPOSITE[x]) return COMPOSITE[x].some(s => ok.has(s))
    return ok.has(x)
  })
}

/** 这把工具有哪几页（只列有内容的） */
export function tabsOf(t: DrawingType): TabId[] {
  if (t === 'measure' || !ALLOWED[t]) return []
  const out: TabId[] = []
  if (INPUT_ORDER[t]?.length) out.push('inputs')
  if (styleTokens(t).length) out.push('style')
  if (TEXT_ON.has(t)) out.push('text')
  out.push('coords', 'vis')
  return out
}

// ------------------------------------------------------------ 选项与标签
const H_OPTS: [string, string][] = [['left', DS.left], ['center', DS.center], ['right', DS.right]]
const V_OPTS: [string, string][] = [['top', DS.top], ['middle', DS.middle], ['bottom', DS.bottom]]
const END_OPTS: [string, string][] = [['normal', DS.endNormal], ['arrow', DS.endArrow]]
const ENUM_OPTS: Readonly<Record<string, [string, string][]>> = {
  startEnd: END_OPTS, endEnd: END_OPTS, statsPos: H_OPTS, hAlign: H_OPTS, vAlign: V_OPTS, lblH: H_OPTS, lblV: V_OPTS,
  fork: [['original', DS.forkOriginal], ['schiff', DS.forkSchiff], ['modschiff', DS.forkModSchiff]],
  degree: [['primary', DS.degPrimary], ['intermediate', DS.degIntermediate], ['minor', DS.degMinor], ['minute', DS.degMinute]],
  rowsLayout: [['rows', DS.rowsByCount], ['ticks', DS.rowsByTicks]],
  volume: [['split', DS.volSplit], ['total', DS.volTotal], ['delta', DS.volDelta]],
  placement: [['left', DS.left], ['right', DS.right]],
}
/** 字号（照 TradingView 的字号下拉） */
export const FONT_SIZES = [10, 11, 12, 14, 16, 20, 24, 28, 32, 40]
export const WIDTHS = [1, 2, 3, 4]
export const DASH_OPTS: [Dash, string][] = [['solid', DS.solid], ['dashed', DS.dashed], ['dotted', DS.dotted]]
const LABEL: Readonly<Record<string, string>> = {
  ...Object.fromEntries(Object.keys(KEYS).filter(k => k in DS).map(k => [k, DS[k as keyof typeof DS]])),
  fill: DS.background, bgOn: DS.background, bg: DS.background, lblPos: DS.lblPos, lblSize: DS.fontSize, font: DS.text, mc: DS.mark,
  values: DS.values, valuesColor: DS.values, txtColor: DS.text, txtSize: DS.fontSize,
}
export const labelOf = (k: string): string => LABEL[k] ?? k
const NUM_STEP: Readonly<Record<string, number>> = { devUp: 0.1, devDn: 0.1 }
const NUM_UNIT: Readonly<Record<string, string>> = { widthPct: '%', vaPct: '%', bgAlpha: '%' }

// ------------------------------------------------------------ 当前值（成交量分布从 drawStyle 读，其余 drawSpec）
export interface Ctx { /** K 线区是深底吗（成交量分布的出厂灰随底色变） */ dark: boolean }
const isObj = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v)
const lineColor = (d: Drawing): string => d.color || MAIN_DEF[d.type]?.color || '#2962FF'

/** 一项扩展值的出厂（成交量分布的看 profileDefaults / PROFILE_INPUT_DEFAULTS） */
function factoryOf(t: DrawingType, k: string, ctx: Ctx): StyleValue | undefined {
  if (isProfile(t)) {
    if (k in PROFILE_INPUT_DEFAULTS) return PROFILE_INPUT_DEFAULTS[k as keyof typeof PROFILE_INPUT_DEFAULTS] as StyleValue
    const look = profileDefaults(ctx.dark) as unknown as Record<string, StyleValue>
    return look[k]
  }
  return DEF[t]?.[k]
}
/** 一项扩展值的当前值（没设 = 出厂） */
function valueOf(d: Drawing, k: string, ctx: Ctx): StyleValue | undefined {
  if (isProfile(d.type)) {
    const inp = profileInputs(d.style) as unknown as Record<string, StyleValue>
    if (k in inp) return inp[k]
    return (profileLookOf(d.style, ctx.dark) as unknown as Record<string, StyleValue>)[k]
  }
  return sv(d, k)
}

function ctlFor(d: Drawing, k: string, ctx: Ctx): Ctl | null {
  const spec = KEYS[k]; if (!spec) return null
  const path = 'style.' + k, v = valueOf(d, k, ctx), def = factoryOf(d.type, k, ctx)
  if (spec === 'bool') return { kind: 'check', path, value: v === true, def: def === true }
  if (spec === 'color') {
    const stored = d.style?.[k]
    // 没设的色：记号跟涨跌色（这里给 TradingView 出厂绿 / 红），其余跟画线颜色
    const shown = styleColorOk(v) ? v : k === 'mc' ? (d.type === 'markerUp' ? '#089981' : '#F23645') : lineColor(d)
    return { kind: 'color', path, value: styleColorOk(stored) ? stored : '', shown, def: typeof def === 'string' ? def : undefined, alpha: true, clear: true }
  }
  if (typeof spec === 'object' && 'e' in spec) {
    const opts = ENUM_OPTS[k] ?? spec.e.map(x => [x, x] as [string, string])
    return { kind: 'enum', path, value: typeof v === 'string' ? v : spec.e[0], options: opts, def: typeof def === 'string' ? def : undefined }
  }
  if (typeof spec === 'object' && 'n' in spec) {
    if (k === 'txtSize' || k === 'lblSize') {
      const cur = typeof v === 'number' ? v : 12
      const sizes = FONT_SIZES.includes(cur) ? FONT_SIZES : [...FONT_SIZES, cur].sort((a, b) => a - b)
      return { kind: 'enum', path, value: String(cur), options: sizes.map(n => [String(n), String(n)]), def: typeof def === 'number' ? String(def) : undefined }
    }
    return { kind: 'num', path, value: typeof v === 'number' ? v : spec.n[0], min: spec.n[0], max: spec.n[1], step: NUM_STEP[k] ?? 1, ...(k === 'bgAlpha' ? { pre: DS.opacity } : {}), unit: NUM_UNIT[k], def: typeof def === 'number' ? def : undefined }
  }
  return null
}

/** 副线一行：勾选（开没开）+ 色块 + 粗细 + 线型；成交量分布的几条线行尾再多一颗「延伸」（照 TV 每条线的 Extend） */
function lineRow(d: Drawing, k: string, ctx: Ctx): Row {
  const p = 'style.' + k
  const raw = isObj(d.style?.[k]) ? d.style![k] as StyleObject : {}
  const prof = isProfile(d.type)
  const { on, color, width, dash, extend } = prof
    ? (profileLookOf(d.style, ctx.dark) as unknown as Record<string, { on: boolean; color: string; width: number; dash: Dash; extend?: boolean }>)[k]
    : { ...lineS(d, k), extend: undefined }
  const stored = styleColorOk(raw.color) ? raw.color : ''
  const def = factoryOf(d.type, k, ctx) as StyleObject | undefined
  const ctls: Ctl[] = [
    { kind: 'color', path: p + '.color', value: stored, shown: color, def: typeof def?.color === 'string' ? def.color : undefined, alpha: true, clear: true },
    { kind: 'width', path: p + '.width', value: width, def: typeof def?.width === 'number' ? def.width : undefined },
    { kind: 'dash', path: p + '.dash', value: dash, def: (def?.dash as Dash | undefined) },
  ]
  if (prof) ctls.push({ kind: 'check', path: p + '.extend', value: extend === true, def: def?.extend === true, label: DS.extend })
  return { kind: 'row', key: k, label: labelOf(k), check: { kind: 'check', path: p + '.on', value: on, def: def?.on !== false }, ctls }
}
/** 方框一行（文字背景、边框、读数底色、分布底色）：勾选 + 色块 */
function boxRow(d: Drawing, k: string, ctx: Ctx): Row {
  const p = 'style.' + k
  const raw = isObj(d.style?.[k]) ? d.style![k] as StyleObject : {}
  const b = isProfile(d.type) ? profileLookOf(d.style, ctx.dark).bg : boxS(d, k)
  const def = factoryOf(d.type, k, ctx) as StyleObject | undefined
  return {
    kind: 'row', key: k, label: labelOf(k),
    check: { kind: 'check', path: p + '.on', value: b.on, def: def?.on === true },
    ctls: [{ kind: 'color', path: p + '.color', value: styleColorOk(raw.color) ? raw.color : '', shown: b.color, def: typeof def?.color === 'string' ? def.color : undefined, alpha: true, clear: true }],
  }
}

function plainRow(d: Drawing, k: string, ctx: Ctx): Row | null {
  const spec = KEYS[k]
  if (spec === 'line') return lineRow(d, k, ctx)
  if (spec === 'box') return boxRow(d, k, ctx)
  const c = ctlFor(d, k, ctx); if (!c) return null
  if (c.kind === 'check') return { kind: 'row', key: k, label: labelOf(k), check: c, ctls: [] }
  return { kind: 'row', key: k, label: labelOf(k), ctls: [c] }
}

function mainRow(d: Drawing): Row | null {
  const k = knobs(d.type)
  if (!k.color && !k.width && !k.dash) return null
  const m = MAIN_DEF[d.type]
  const ctls: Ctl[] = []
  if (k.color) ctls.push({ kind: 'color', path: 'main.color', value: d.color ?? '', shown: lineColor(d), def: m?.color, alpha: true, clear: false })
  if (k.width) ctls.push({ kind: 'width', path: 'main.width', value: d.width ?? m?.width ?? 2, def: m?.width })
  if (k.dash) ctls.push({ kind: 'dash', path: 'main.dash', value: d.dash ?? 'solid', def: m?.dash ?? 'solid' })
  return { kind: 'row', key: 'main', label: k.width || k.dash ? DS.line : DS.color, ctls }
}

/** 背景一行：开关（能填色的听 d.filled，其余听 style.bgOn）+ 填色（style.fill）/ 透明度（style.bgAlpha，按刻度色铺的那几把） */
function fillRow(d: Drawing, ctx: Ctx): Row | null {
  const t = d.type, ok = ALLOWED[t]!
  let check: (Ctl & { kind: 'check' }) | undefined
  if (knobs(t).fill) check = { kind: 'check', path: 'main.filled', value: d.filled !== false, def: MAIN_DEF[t]?.filled !== false }
  else if (ok.has('bgOn')) check = { kind: 'check', path: 'style.bgOn', value: fillOn(d), def: DEF[t]?.bgOn !== false }
  const ctls: Ctl[] = []
  if (ok.has('fill')) {
    const f = sv(d, 'fill')
    const shown = styleColorOk(f) ? f : joinHex(splitHex(lineColor(d))[0], FILL_ALPHA[t] ?? 0.2)
    const stored = d.style?.fill
    ctls.push({ kind: 'color', path: 'style.fill', value: styleColorOk(stored) ? stored : '', shown, def: typeof DEF[t]?.fill === 'string' ? DEF[t]!.fill as string : undefined, alpha: true, clear: true })
  }
  if (ok.has('bgAlpha')) { const c = ctlFor(d, 'bgAlpha', ctx); if (c) ctls.push(c) }
  if (!check && !ctls.length) return null
  return { kind: 'row', key: 'fill', label: DS.background, ...(check ? { check } : {}), ctls }
}

/** 文字一行：色块 + 字号 + 粗体 + 斜体（这把工具认哪几项给哪几项） */
function fontRow(d: Drawing, ctx: Ctx): Row | null {
  const ok = ALLOWED[d.type]!
  const ctls: Ctl[] = []
  if (ok.has('txtColor')) { const c = ctlFor(d, 'txtColor', ctx); if (c && c.kind === 'color') ctls.push({ ...c, shown: svs(d, 'txtColor', '') || lineColor(d) }) }
  if (ok.has('txtSize')) { const c = ctlFor(d, 'txtSize', ctx); if (c) ctls.push(c) }
  if (ok.has('bold')) ctls.push({ kind: 'toggle', path: 'style.bold', value: svb(d, 'bold'), icon: 'bold', label: DS.bold, def: DEF[d.type]?.bold === true })
  if (ok.has('italic')) ctls.push({ kind: 'toggle', path: 'style.italic', value: svb(d, 'italic'), icon: 'italic', label: DS.italic, def: DEF[d.type]?.italic === true })
  return ctls.length ? { kind: 'row', key: 'font', label: DS.text, ctls } : null
}

function levelsRow(d: Drawing, k: 'levels' | 'tlevels'): Row {
  const both = !!LEVEL_TABLE[d.type]?.tlevels
  return { kind: 'levels', key: k, label: k === 'tlevels' ? DS.tlevels : both ? DS.plevels : DS.levels, rows: levelRows(d, k), lineColor: lineColor(d) }
}

function tokenRow(d: Drawing, tok: string, ctx: Ctx): Row | null {
  const ok = ALLOWED[d.type]!
  switch (tok) {
    case 'main': return mainRow(d)
    case 'fill': return fillRow(d, ctx)
    case 'font': return fontRow(d, ctx)
    case '#stats': return { kind: 'group', label: DS.stats }
    case 'levels': case 'tlevels': return ok.has(tok) ? levelsRow(d, tok) : null
    case 'lblPos': {
      const ctls = ['lblH', 'lblV'].filter(k => ok.has(k)).map(k => ctlFor(d, k, ctx)).filter((c): c is Ctl => !!c)
      return ctls.length ? { kind: 'row', key: 'lblPos', label: DS.lblPos, ctls } : null
    }
    case 'values': {
      const c = ctlFor(d, 'values', ctx) as Ctl & { kind: 'check' }
      const col = ctlFor(d, 'valuesColor', ctx)
      return { kind: 'row', key: 'values', label: DS.values, check: c, ctls: col ? [col] : [] }
    }
    case 'devUp': case 'devDn': {
      const use = tok === 'devUp' ? 'useUp' : 'useDn'
      const n = ctlFor(d, tok, ctx)
      return { kind: 'row', key: tok, label: labelOf(tok), check: { kind: 'check', path: 'style.' + use, value: sv(d, use) !== false, def: DEF[d.type]?.[use] !== false }, ctls: n ? [n] : [] }
    }
    case 'text': return { kind: 'row', key: 'text', label: DS.text, ctls: [{ kind: 'text', path: 'text', value: d.text ?? '', max: TEXT_LIMIT }] }
    default: return ok.has(tok) ? plainRow(d, tok, ctx) : null
  }
}

/** 一页的行 */
export function rowsOf(d: Drawing, tab: TabId, ctx: Ctx = { dark: true }): Row[] {
  const t = d.type
  if (!ALLOWED[t]) return []
  const map = (toks: string[]) => toks.map(x => tokenRow(d, x, ctx)).filter((r): r is Row => !!r)
  if (tab === 'inputs') return map(INPUT_ORDER[t] ?? [])
  if (tab === 'style') return map(styleTokens(t))
  if (tab === 'text') return TEXT_ON.has(t) ? map(TEXT_ORDER) : []
  if (tab === 'coords') return coordRows(d)
  return visRows(d)
}

// ------------------------------------------------------------ 坐标
/** 只看价格 / 只看时间的几把（水平线没有时间，竖线与按时间圈的成交量工具没有价格） */
const PRICE_ONLY: ReadonlySet<DrawingType> = new Set<DrawingType>(['hline'])
const TIME_ONLY: ReadonlySet<DrawingType> = new Set<DrawingType>(['vline', 'avwap', 'fvp', 'anchoredVolumeProfile'])
function coordRows(d: Drawing): Row[] {
  const n = Math.min(d.pts.length, ANCHOR_COUNT[d.type] ?? d.pts.length)
  const pos = d.type === 'position' ? [DS.entry, DS.target, DS.stop] : null
  return d.pts.slice(0, n).map((q, i): Row => {
    const ctls: Ctl[] = []
    if (!TIME_ONLY.has(d.type)) ctls.push({ kind: 'num', path: `pt.${i}.p`, value: q.p, min: -Infinity, max: Infinity, step: 0 })
    // 持仓的止损跟着目标那一格的时间走（拖手柄也是），只给价格
    if (!PRICE_ONLY.has(d.type) && !(d.type === 'position' && i === 2)) ctls.push({ kind: 'time', path: `pt.${i}.t`, value: q.t })
    return { kind: 'row', key: 'pt' + i, label: pos ? pos[i] : fill(DS.point, { n: i + 1 }), ctls }
  })
}

// ------------------------------------------------------------ 可见范围
const VIS_LABEL: Readonly<Record<VisClass, string>> = { sec: DS.visSec, min: DS.visMin, hour: DS.visHour, day: DS.visDay, week: DS.visWeek, month: DS.visMonth }
function visOf(d: Drawing, k: VisClass): { on: boolean; lo: number; hi: number } {
  const v = d.style?.vis, x = isObj(v) && isObj(v[k]) ? v[k] as StyleObject : null
  const [lo0, hi0] = VIS_RANGE[k]
  return { on: x ? x.on !== false : true, lo: typeof x?.lo === 'number' ? x.lo : lo0, hi: typeof x?.hi === 'number' ? x.hi : hi0 }
}
function visRows(d: Drawing): Row[] {
  return VIS_CLASSES.map((k): Row => {
    const v = visOf(d, k), [lo0, hi0] = VIS_RANGE[k]
    return {
      kind: 'row', key: 'vis.' + k, label: VIS_LABEL[k],
      check: { kind: 'check', path: `vis.${k}.on`, value: v.on, def: true },
      ctls: [
        { kind: 'num', path: `vis.${k}.lo`, value: v.lo, min: lo0, max: hi0, step: 1, def: lo0 },
        { kind: 'num', path: `vis.${k}.hi`, value: v.hi, min: lo0, max: hi0, step: 1, def: hi0 },
      ],
    }
  })
}

// ------------------------------------------------------------ 改
const same = (a: unknown, b: unknown): boolean => JSON.stringify(a) === JSON.stringify(b)
/** 和出厂一样的项就不存（style 只留改过的，清空了整份去掉） */
function prune(t: DrawingType, s: StyleObject): StyleObject {
  const out: StyleObject = {}
  for (const [k, v] of Object.entries(s)) {
    if (isProfile(t) && k in PROFILE_INPUT_DEFAULTS) { if (v !== PROFILE_INPUT_DEFAULTS[k as keyof typeof PROFILE_INPUT_DEFAULTS]) out[k] = v; continue }
    if (k === 'levels' || k === 'tlevels') {
      const f = LEVEL_TABLE[t]?.[k]
      if (!f || !same((v as StyleObject[]).map(x => ({ v: x.v, c: x.c || '', on: x.on !== false })), f)) out[k] = v
      continue
    }
    if (k === 'vis' && isObj(v)) {
      const o: StyleObject = {}
      for (const [c, x] of Object.entries(v)) {
        const r = VIS_RANGE[c as VisClass]; if (!r || !isObj(x)) continue
        if (!(x.on !== false && x.lo === r[0] && x.hi === r[1])) o[c] = x as StyleObject
      }
      if (Object.keys(o).length) out.vis = o
      continue
    }
    const def = DEF[t]?.[k]
    if (def === undefined) { out[k] = v; continue }
    if (isObj(def) && isObj(v)) { if (!same({ ...def, ...v }, def) || Object.keys(v).some(f => !(f in def))) out[k] = v; continue }
    if (!same(v, def)) out[k] = v
  }
  return out
}
/** 换一份 style：清洗、去掉与出厂一样的；清空了删掉；超了上限（8 KB）不收、返回 false */
export function setStyle(d: Drawing, next: StyleObject): boolean {
  const p = prune(d.type, next)
  if (!Object.keys(p).length) { delete d.style; return true }
  const c = cleanStyle(d.type, p)
  if (!c) return false
  d.style = c
  return true
}
const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v))
function clipText(v: string): string {
  if (graphemeCount(v) <= TEXT_LIMIT) return v
  const seg = typeof Intl !== 'undefined' && 'Segmenter' in Intl ? [...new Intl.Segmenter('zh', { granularity: 'grapheme' }).segment(v)].map(x => x.segment) : [...v]
  return seg.slice(0, TEXT_LIMIT).join('')
}

/** 刻度表整张写回：三端共用的 d.levels（开着的、口径内的）+ style 里整张表（颜色、关着的、超口径的） */
export function writeLevels(d: Drawing, k: 'levels' | 'tlevels', rows: readonly LevelRow[]): boolean {
  const table: StyleValue[] = rows.slice(0, 24).map(x => ({ v: x.v, c: styleColorOk(x.c) ? x.c : '', on: x.on }))
  const prev = d.levels
  if (k === 'levels' && usesLevels(d.type)) d.levels = contractLevels(d.type, rows)
  if (setStyle(d, { ...(d.style ?? {}), [k]: table })) return true
  if (prev) d.levels = prev; else delete d.levels
  return false
}

/** 把一处改动写进 d（只改 d，不重画、不落盘）；改不了（坏值、锁定、超上限）返回 false */
export function applyEdit(d: Drawing, path: string, v: unknown): boolean {
  if (d.locked) return false
  const seg = path.split('.')
  const head = seg[0]
  if (head === 'main') {
    const f = seg[1]
    if (f === 'color') { if (typeof v !== 'string' || !styleColorOk(v)) return false; d.color = v.toUpperCase(); return true }
    if (f === 'width') { if (typeof v !== 'number' || !(v >= 0.5 && v <= 6)) return false; d.width = v; return true }
    if (f === 'dash') { if (v === 'dashed' || v === 'dotted') d.dash = v; else delete d.dash; return true }
    if (f === 'filled') { if (v === false) d.filled = false; else delete d.filled; return true }
    return false
  }
  if (head === 'text') {
    if (typeof v !== 'string') return false
    const s = clipText(v)
    if (s) d.text = s; else delete d.text
    return true
  }
  if (head === 'style') {
    const k = seg[1], spec = KEYS[k]
    if (!spec || !allows(d.type, k)) return false
    const s: StyleObject = { ...(d.style ?? {}) }
    if (seg.length === 2) {
      if (v === undefined || v === null || v === '') delete s[k]
      else if (typeof spec === 'object' && 'n' in spec) { const n = typeof v === 'string' ? Number(v) : v; if (typeof n !== 'number' || !Number.isFinite(n)) return false; s[k] = clamp(n, spec.n[0], spec.n[1]) }
      else s[k] = v as StyleValue
    } else {
      const f = seg[2]
      const o: StyleObject = isObj(s[k]) ? { ...(s[k] as StyleObject) } : {}
      if (v === undefined || v === null) delete o[f]
      else o[f] = v as StyleValue
      // 颜色给 '' = 跟画线颜色：副线 / 方框的出厂多半就是 ''，存不存一样，去掉
      if (f === 'color' && v === '') delete o.color
      // 延伸出厂都是关：关回去就不存
      if (f === 'extend' && v === false) delete o.extend
      if (Object.keys(o).length) s[k] = o; else delete s[k]
    }
    return setStyle(d, s)
  }
  if (head === 'lv') {
    const k = seg[1] as 'levels' | 'tlevels', i = Number(seg[2]), f = seg[3]
    if ((k !== 'levels' && k !== 'tlevels') || !allows(d.type, k)) return false
    const rows = levelRows(d, k)
    const r = rows[i]; if (!r) return false
    if (f === 'on') r.on = v === true
    else if (f === 'v') { const n = typeof v === 'string' ? Number(v) : v; if (typeof n !== 'number' || !Number.isFinite(n) || Math.abs(n) > 1000) return false; r.v = n }
    else if (f === 'c') { if (v !== '' && !styleColorOk(v)) return false; r.c = v as string }
    else return false
    return writeLevels(d, k, rows)
  }
  if (head === 'pt') {
    const i = Number(seg[1]), f = seg[2], q = d.pts[i]
    const n = typeof v === 'string' ? Number(v) : v
    if (!q || typeof n !== 'number' || !Number.isFinite(n)) return false
    if (f === 'p') d.pts[i] = { ...q, p: n }
    else if (f === 't') {
      d.pts[i] = { ...q, t: Math.round(n) }
      if (d.type === 'position' && i === 1 && d.pts[2]) d.pts[2] = { ...d.pts[2], t: Math.round(n) }
    } else return false
    return true
  }
  if (head === 'vis') {
    const k = seg[1] as VisClass, f = seg[2]
    if (!VIS_CLASSES.includes(k)) return false
    const cur = visOf(d, k), [lo0, hi0] = VIS_RANGE[k]
    if (f === 'on') cur.on = v === true
    else if (f === 'lo' || f === 'hi') {
      const n = typeof v === 'string' ? Number(v) : v
      if (typeof n !== 'number' || !Number.isFinite(n)) return false
      const x = clamp(Math.round(n), lo0, hi0)
      if (f === 'lo') { cur.lo = x; if (cur.hi < x) cur.hi = x } else { cur.hi = x; if (cur.lo > x) cur.lo = x }
    } else return false
    const vis: StyleObject = isObj(d.style?.vis) ? { ...(d.style!.vis as StyleObject) } : {}
    vis[k] = cur as unknown as StyleObject
    return setStyle(d, { ...(d.style ?? {}), vis })
  }
  return false
}

// ------------------------------------------------------------ 时间（上海时间，datetime-local 的值）
/** 毫秒 → 'YYYY-MM-DDTHH:mm'（上海时间） */
export function shInput(ms: number): string {
  const x = new Date(ms + TZ_MS)
  return `${x.getUTCFullYear()}-${pad(x.getUTCMonth() + 1)}-${pad(x.getUTCDate())}T${pad(x.getUTCHours())}:${pad(x.getUTCMinutes())}`
}
/** 'YYYY-MM-DDTHH:mm'（上海时间）→ 毫秒；认不出返回 null */
export function shParse(s: string): number | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?$/.exec(s)
  if (!m) return null
  return Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +(m[6] ?? 0)) - TZ_MS
}

export type { DrawStyle }
