/* Hkline 手机网页版 · 偏好的字段表（照 iOS Kanpan/Kanpan/Settings/Model/Prefs.swift）
 *
 * 三份清单必须一致（tests/m-prefs.test.ts 守着）：
 *   1. iOS 契约 Backend/kanpan-api/contract/settings-fields.json 里 fieldClasses 为 synced 的字段；
 *   2. 服务端 Backend/kanpan-api/src/sync.rs 的 SETTINGS_FIELDS（减去契约的 wireOnlyKeys——2026-10-10 起是空表：
 *      原来的 compactValues / drawToolGroup / routePolicy / styleID 进了服务端 RETIRED_SETTINGS_FIELDS）；
 *   3. 这里的 SYNCED_FIELDS。
 * 2026-10-10 三端退役 portraitHeight（竖屏主图占比，永远 0.5，图上用常量）与 indicatorLayouts（周期分组那阵子的分叉）：
 * 老档里的这两个键读时忽略，删除前的代码在 tag sync-fields-before-retire-2026-10-10。
 * 服务端对含未知字段的操作整条拒绝，多发一个键就会把整条队列堵死，所以宁可少不可多。
 */

import { compareKey } from '../../sync/codec'
import { syncKeyOf } from '../../market/identity'
import { isDrawingKind } from '../chart/draw/drawing'
import { ANALYSIS_SECTIONS, isAnalysisSection } from '../pages/chart/analysisRank'
import { defaultParams } from '../indicator/ids'
import { AUTO_LAYERS, type AutoLayerId } from '../../analysis/fvg'

export type IntervalId = '1m' | '3m' | '5m' | '15m' | '30m' | '1h' | '2h' | '4h' | '6h' | '12h' | '1d' | '1w' | '1M' | '1y'
export const INTERVALS: readonly IntervalId[] = ['1m', '3m', '5m', '15m', '30m', '1h', '2h', '4h', '6h', '12h', '1d', '1w', '1M', '1y']
/** 周期条出厂钉住的六档（Interval.quick），最多 6 个 */
export const QUICK_INTERVALS: readonly IntervalId[] = ['5m', '30m', '1h', '4h', '1d', '1w']
export const MAX_QUICK = 6

/** 指标 id：rawValue 与 iOS IndicatorID 一致（主图的全部排在副图前面） */
export type IndicatorId = 'MA' | 'EMA' | 'BOLL' | 'VWAP' | 'ST' | 'SAR' | 'ORDERFLOW'
  | 'VOL' | 'MACD' | 'RSI' | 'KDJ' | 'SRSI' | 'ATR' | 'OI' | 'LSR' | 'TAKER' | 'BASIS' | 'DMI' | 'CVD'
export const OVERLAY_IDS: readonly IndicatorId[] = ['MA', 'EMA', 'BOLL', 'VWAP', 'ST', 'SAR', 'ORDERFLOW']
export const SUB_IDS: readonly IndicatorId[] = ['VOL', 'MACD', 'RSI', 'KDJ', 'SRSI', 'ATR', 'OI', 'LSR', 'TAKER', 'BASIS', 'DMI', 'CVD']
/** 副图最多三个（VOL 不占名额，kanpan-max-three-sub-indicators） */
export const MAX_SUBS = 3

/** IndicatorID.defaultParams：只收有参数的那几把；值取自三端共用的 indicators.json（经 m/indicator/ids） */
export const DEFAULT_PARAMS: Partial<Record<IndicatorId, number[]>> = Object.fromEntries(
  ([...OVERLAY_IDS, ...SUB_IDS] as IndicatorId[])
    .map(id => [id, defaultParams(id)] as const)
    .filter(([, p]) => p.length > 0),
)
/** IndicatorID.factoryParams：新装只带这四把 */
export const FACTORY_PARAMS_IDS: readonly IndicatorId[] = ['MA', 'EMA', 'VOL', 'MACD']

export type ThemeChoice = 'auto' | 'light' | 'dark'
export type Skin = 'sage' | 'terra' | 'classic'
export type PriceMode = 'linear' | 'log' | 'percent'
export type CandleKind = 'candle' | 'heikin' | 'line'
export type AlertSound = 'default' | 'crisp' | 'electronic' | 'glass'
export type SectorMarket = 'crypto' | 'us'
export type SectorWindow = 'today' | 'd5' | 'd20'
export type RoutePolicy = 'direct' | 'gateway'
export type ReviewSearchScope = 'history' | 'private'
/** 复盘本「观点 / 交易」两面（与 iOS `Prefs.reviewSegments`、服务端 sync_validation 逐字相同） */
export const REVIEW_SEGMENTS = ['views', 'trades'] as const
export type ReviewSegment = typeof REVIEW_SEGMENTS[number]
/** 复盘本筛选三档：全部 / 待判定 / 已判定（与 iOS `Prefs.reviewBookFilters`、服务端逐字相同） */
export const REVIEW_BOOK_FILTERS = ['all', 'todo', 'decided'] as const
export type ReviewBookFilter = typeof REVIEW_BOOK_FILTERS[number]

/** OrderFlowOverride：门槛（美元）与步长（价格），缺省走默认表 */
export interface OrderFlowOverride { spot?: number; usdtPerp?: number; coinPerp?: number; delivery?: number; step?: number }
/** LearnedDefaults（个性化学习）：Choice = {v, n, at}，Factor 同形但 v 是数 */
export interface LearnedChoice { v: string; n: number; at: number }
export interface LearnedFactor { v: number; n: number; at: number }
export interface LearnedDefaults {
  intervals: Record<string, LearnedChoice>
  priceAxis: Record<string, LearnedChoice>
  sectorWindow: Record<string, LearnedChoice>
  watchMove: Record<string, LearnedFactor>
}
/** IndicatorLayout：一整套指标布局（所有周期共用这一份） */
export interface IndicatorLayout {
  overlays: IndicatorId[]; subs: IndicatorId[]; params: Partial<Record<IndicatorId, number[]>>
  subHeightOverrides: Partial<Record<IndicatorId, number>>; candleKind: CandleKind; priceMode: PriceMode
}

/** 与 iOS Prefs 同名同义的那些字段（体验类状态，跟着人走） */
export interface Prefs {
  interval: IntervalId
  quickIntervals: IntervalId[]
  theme: ThemeChoice
  skin: Skin
  /** 红涨绿跌（出厂 false = 绿涨红跌，2026-10-03 起一律如此）；html 上对应 data-updown="red-up" / "green-up" */
  redUp: boolean
  compareSymbols: string[]
  priceMode: PriceMode
  depth: boolean
  orderFlow: boolean
  orderFlowHistory: boolean
  orderFlowOverrides: Record<string, OrderFlowOverride>
  candleKind: CandleKind
  barSpacing: number
  /** 横屏自己记的根间距（与 iOS `Prefs.landscapeBarSpacing` 同义；老档案没有就取同一份里的 barSpacing） */
  landscapeBarSpacing: number
  mainInverted: boolean
  subInverted: IndicatorId[]
  /** 指标 → 线序号 → 颜色（#RRGGBB） */
  indicatorColors: Partial<Record<IndicatorId, Record<string, string>>>
  alertSound: AlertSound
  watchMoveAlert: boolean
  /** 自选行上那条 24 小时迷你走势（2026-10-08，出厂开；跟人走） */
  favoritesTrend: boolean
  /** 图上大单与爆仓气泡（2026-10-08，出厂开；跟人走，和挂单墙开关互不牵连） */
  bigTradeSigns: boolean
  /** 自动分析层（2026-10-10，与 iOS `Prefs.autoLayers` 同义，出厂全关；跟人走）：目前只有公允价值缺口 'FVG'。
   *  按打开先后排、不重复，只认 AUTO_LAYERS 里的名字 */
  autoLayers: AutoLayerId[]
  notifyListingChanges: boolean
  habitLearning: boolean
  learnedDefaults: LearnedDefaults
  overlays: IndicatorId[]
  subs: IndicatorId[]
  params: Partial<Record<IndicatorId, number[]>>
  subHeightOverrides: Partial<Record<IndicatorId, number>>
  /** 本机字段（deviceOnly）：不同步 */
  routePolicy: RoutePolicy
  favoritesGroup: string
  sectorMarket: SectorMarket
  sectorWindow: SectorWindow
  lastDrawTool: string
  /** 画线条按它挑最常用的几把（每把工具用了几次；iOS 竖屏画线条与横屏画线台、手机网页横屏画线台同一张表，m/chart/draw/toolRank.ts） */
  drawToolUsage: Record<string, number>
  /** 「分析」面板四节（画线 / 主力订单流 / 指标 / 对比）各用了几次，面板打开时按它排节序
   *  （iOS `Prefs.analysisUsage`、服务端 `analysisUsage` 同一张表，m/pages/chart/analysisRank.ts） */
  analysisUsage: Record<string, number>
  /** iOS 横屏画线台里主图指标画不画（手机网页没有画线台，只随账号带着走、不丢） */
  drawingOverlaysShown: boolean
  /** 竖屏「隐藏画线」（与 iOS `Prefs.drawingsHidden` 同义，出厂 false）：开着时竖屏图上不画、点不中任何画线，
   *  提醒照常判、图上改画提醒线；横屏画线台不管它、一律显示 */
  drawingsHidden: boolean
  reviewSearchScope: ReviewSearchScope
  /** 复盘本停在「观点 / 交易」哪一面（2026-10-10，跟人走）。只记**手点**的那面：观点空、交易有时自动翻到交易
   *  只改这次显示、不回写（与 iOS `Prefs.reviewSegment` 同义） */
  reviewSegment: ReviewSegment
  /** 复盘本筛选停在哪一档（2026-10-10，跟人走，出厂「待判定」；与 iOS `Prefs.reviewBookFilter` 同义） */
  reviewBookFilter: ReviewBookFilter
}

/** 进账号同步的字段（settings 集合）。顺序无意义，集合必须与 iOS 契约、服务端对齐 */
export const SYNCED_FIELDS = [
  'alertSound', 'analysisUsage', 'autoLayers', 'barSpacing', 'bigTradeSigns', 'candleKind', 'compareSymbols', 'depth', 'drawToolUsage', 'drawingOverlaysShown', 'drawingsHidden', 'favoritesGroup', 'favoritesTrend', 'habitLearning',
  'indicatorColors', 'interval', 'landscapeBarSpacing', 'lastDrawTool', 'learnedDefaults', 'mainInverted',
  'notifyListingChanges', 'orderFlow', 'orderFlowHistory', 'orderFlowOverrides', 'overlays', 'params', 'priceMode',
  'quickIntervals', 'redUp', 'reviewBookFilter', 'reviewSearchScope', 'reviewSegment', 'sectorMarket', 'sectorWindow', 'skin', 'subHeightOverrides',
  'subInverted', 'subs', 'theme', 'watchMoveAlert',
] as const satisfies readonly (keyof Prefs)[]
/** 只在这台设备上的字段 */
export const DEVICE_ONLY_FIELDS = ['routePolicy'] as const satisfies readonly (keyof Prefs)[]

export function emptyLearned(): LearnedDefaults { return { intervals: {}, priceAxis: {}, sectorWindow: {}, watchMove: {} } }

/** Prefs.defaults */
export function defaultPrefs(): Prefs {
  const params: Partial<Record<IndicatorId, number[]>> = {}
  for (const id of FACTORY_PARAMS_IDS) params[id] = [...(DEFAULT_PARAMS[id] ?? [])]
  return {
    interval: '1h', quickIntervals: [...QUICK_INTERVALS], theme: 'auto', skin: 'sage', redUp: false,
    compareSymbols: [], priceMode: 'log', depth: false, orderFlow: false, orderFlowHistory: false, orderFlowOverrides: {},
    candleKind: 'candle', barSpacing: 4, landscapeBarSpacing: 4, mainInverted: false, subInverted: [],
    indicatorColors: {}, alertSound: 'default', watchMoveAlert: false, favoritesTrend: true, bigTradeSigns: true, autoLayers: [], notifyListingChanges: false,
    habitLearning: true, learnedDefaults: emptyLearned(), overlays: ['MA'], subs: ['VOL', 'OI', 'MACD'],
    params, subHeightOverrides: {}, routePolicy: 'gateway',
    favoritesGroup: '', sectorMarket: 'crypto', sectorWindow: 'today', lastDrawTool: '', drawToolUsage: {}, analysisUsage: {}, reviewSearchScope: 'history',
    reviewSegment: 'views', reviewBookFilter: 'todo',
    drawingOverlaysShown: true, drawingsHidden: false,
  }
}

const oneOf = <T extends string>(v: unknown, list: readonly T[], d: T): T => (list as readonly unknown[]).includes(v) ? v as T : d
const bool = (v: unknown, d: boolean): boolean => typeof v === 'boolean' ? v : d
const num = (v: unknown, d: number, lo = -Infinity, hi = Infinity): number => typeof v === 'number' && Number.isFinite(v) ? Math.min(hi, Math.max(lo, v)) : d
const obj = <T>(v: unknown, d: T): T => v && typeof v === 'object' && !Array.isArray(v) ? v as T : d
const strs = (v: unknown): string[] => Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []
const isRecord = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v)
const ALL_IDS: readonly IndicatorId[] = [...OVERLAY_IDS, ...SUB_IDS]
const isId = (x: unknown): x is IndicatorId => (ALL_IDS as readonly unknown[]).includes(x)
const isSub = (x: unknown): x is IndicatorId => (SUB_IDS as readonly unknown[]).includes(x)

// ───────── 取值范围（与 iOS Prefs、服务端 sync_validation.rs 同一组数） ─────────

/** Prefs.clampSpacing：AICoinBehavior 的 1.6…40 pt */
export const BAR_SPACING = [1.6, 40] as const
/** IndicatorLayout.sanitized：副图高度倍数（KanpanCore `SubPaneResize.minimumScale` / `maximumScale`，2026-10-10 下界 0.5 → 0.25） */
export const SUB_HEIGHT = [0.25, 2] as const
/** 对比品种最多三个（compareSymbols） */
export const MAX_COMPARE = 3
/** Prefs.maxOrderFlowOverrides */
export const MAX_ORDERFLOW_OVERRIDES = 200
/** LearnedDefaults.maxBytes */
export const LEARNED_MAX_BYTES = 16_384

/** IndicatorParamRule 的外沿：整数、1…400、最多 20 个 */
export function cleanParams(v: unknown): number[] | null {
  if (!Array.isArray(v)) return null
  return v.filter(x => typeof x === 'number' && Number.isFinite(x)).slice(0, 20).map(x => Math.min(400, Math.max(1, Math.round(x as number))))
}
export function cleanParamTable(v: unknown): Partial<Record<IndicatorId, number[]>> {
  const out: Partial<Record<IndicatorId, number[]>> = {}
  if (!isRecord(v)) return out
  for (const [k, x] of Object.entries(v)) { const p = isId(k) ? cleanParams(x) : null; if (p) out[k as IndicatorId] = p }
  return out
}
export function cleanSubHeights(v: unknown): Partial<Record<IndicatorId, number>> {
  const out: Partial<Record<IndicatorId, number>> = {}
  if (!isRecord(v)) return out
  for (const [k, x] of Object.entries(v)) if (isSub(k) && typeof x === 'number' && Number.isFinite(x)) out[k as IndicatorId] = Math.min(SUB_HEIGHT[1], Math.max(SUB_HEIGHT[0], x))
  return out
}
/** 指标 → 线序号（0…20）→ #RRGGBB */
export function cleanColors(v: unknown): Partial<Record<IndicatorId, Record<string, string>>> {
  const out: Partial<Record<IndicatorId, Record<string, string>>> = {}
  if (!isRecord(v)) return out
  for (const [k, x] of Object.entries(v)) {
    if (!isId(k) || !isRecord(x)) continue
    const one: Record<string, string> = {}
    for (const [n, c] of Object.entries(x)) if (/^(?:[0-9]|1[0-9]|20)$/.test(n) && typeof c === 'string' && /^#[0-9a-fA-F]{6}$/.test(c)) one[n] = c
    out[k as IndicatorId] = one
  }
  return out
}
/** 对比品种：iOS 存的是 `venue/market/SYMBOL`；裸代号按币安 U 本位补全。最多三个、不重复 */
export function cleanCompare(v: unknown): string[] {
  const out: string[] = []
  for (const x of strs(v)) {
    const k = x.includes('/') ? x : syncKeyOf(x.toUpperCase())
    // 与服务端 compare_key 同一条规则（按交易所分流：币安代号允许「币安人生USDT」这种中文底名，Coinbase 是 BASE-USD）；
    // 服务端对不合规的键整条 settings 拒收，所以这里认不下的就丢，不带上去
    if (compareKey(k) && !out.includes(k)) out.push(k)
    if (out.length >= MAX_COMPARE) break
  }
  return out
}
const THRESHOLD_KEYS = ['spot', 'usdtPerp', 'coinPerp', 'delivery'] as const
/** OrderFlowOverride.normalized + OrderFlowBase.isValid：越界的一项丢掉，一项不剩的整只丢掉 */
export function cleanOrderFlowOverrides(v: unknown): Record<string, OrderFlowOverride> {
  const out: Record<string, OrderFlowOverride> = {}
  if (!isRecord(v)) return out
  for (const base of Object.keys(v).sort()) {
    if (Object.keys(out).length >= MAX_ORDERFLOW_OVERRIDES) break
    const o = v[base]
    if (!/^[A-Z0-9]{1,20}$/.test(base) || !isRecord(o)) continue
    const one: OrderFlowOverride = {}
    for (const k of THRESHOLD_KEYS) { const x = o[k]; if (typeof x === 'number' && Number.isFinite(x) && x >= 1e3 && x <= 1e9) one[k] = x }
    if (typeof o.step === 'number' && Number.isFinite(o.step) && o.step >= 1e-8 && o.step <= 1e6) one.step = o.step
    if (Object.keys(one).length) out[base] = one
  }
  return out
}
/** iOS Prefs.cleanDrawToolUsage / 服务端 draw_tool_usage：键是画线种类、值是 1…100000 的整数、最多 12 个键 */
export function cleanDrawToolUsage(v: unknown): Record<string, number> {
  const out: Record<string, number> = {}
  if (!isRecord(v)) return out
  const kept = Object.entries(v)
    .filter((e): e is [string, number] => isDrawingKind(e[0]) && Number.isInteger(e[1]) && (e[1] as number) > 0)
    .map(([k, n]) => [k, Math.min(n, 100_000)] as const)
    .sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
    .slice(0, 12)
  for (const [k, n] of kept) out[k] = n
  return out
}
/** iOS Prefs.cleanAnalysisUsage / 服务端 analysis_usage：键只认四个节名、值是 1…100000 的整数、最多 4 个键 */
export function cleanAnalysisUsage(v: unknown): Record<string, number> {
  const out: Record<string, number> = {}
  if (!isRecord(v)) return out
  const kept = Object.entries(v)
    .filter((e): e is [string, number] => isAnalysisSection(e[0]) && Number.isInteger(e[1]) && (e[1] as number) > 0)
    .map(([k, n]) => [k, Math.min(n, 100_000)] as const)
    .sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
    .slice(0, ANALYSIS_SECTIONS.length)
  for (const [k, n] of kept) out[k] = n
  return out
}
/** LearnedDefaults.sanitized：每条恰好 {v, n, at}；整份 ≤ 16 KB（超了按最旧的先丢） */
export function cleanLearned(v: unknown): LearnedDefaults {
  const r = isRecord(v) ? v : {}
  const table = <T extends string | number>(t: unknown, key: (k: string) => boolean, val: (x: unknown) => x is T): Record<string, { v: T; n: number; at: number }> => {
    const out: Record<string, { v: T; n: number; at: number }> = {}
    if (!isRecord(t)) return out
    for (const [k, e] of Object.entries(t)) {
      if (!k || k.length > 128 || !key(k) || !isRecord(e) || !val(e.v)) continue
      const n = typeof e.n === 'number' && Number.isFinite(e.n) ? Math.max(0, Math.floor(e.n)) : 0
      const at = typeof e.at === 'number' && Number.isFinite(e.at) ? Math.min(9e15, Math.max(0, e.at)) : 0
      out[k] = { v: e.v, n, at }
    }
    return out
  }
  const isIv = (x: unknown): x is string => (INTERVALS as readonly unknown[]).includes(x)
  const out: LearnedDefaults = {
    intervals: table(r.intervals, () => true, isIv),
    priceAxis: table(r.priceAxis, k => ['crypto', 'equity', 'metal', 'index', 'other'].includes(k), (x): x is string => x === 'linear' || x === 'log'),
    sectorWindow: table(r.sectorWindow, k => k === 'crypto' || k === 'us', (x): x is string => x === 'today' || x === 'd5'),
    watchMove: table(r.watchMove, () => true, (x): x is number => typeof x === 'number' && Number.isFinite(x) && x >= 0.5 && x <= 2),
  }
  // 超了 16 KB：四张表里按 at 从旧到新丢，直到装得下
  const size = (): number => new TextEncoder().encode(JSON.stringify(out)).length
  if (size() > LEARNED_MAX_BYTES) {
    const all = (Object.keys(out) as (keyof LearnedDefaults)[]).flatMap(t => Object.entries(out[t]).map(([k, e]) => ({ t, k, at: e.at })))
    all.sort((a, b) => a.at - b.at)
    for (const x of all) { if (size() <= LEARNED_MAX_BYTES) break; delete (out[x.t] as Record<string, unknown>)[x.k] }
  }
  return out
}

/** Prefs.cappedSubs：成交量不占名额，别的最多三个 */
export function cappedSubs(subs: readonly IndicatorId[]): IndicatorId[] {
  const nonVol = subs.filter(x => x !== 'VOL')
  return subs.filter(x => x === 'VOL' || nonVol.indexOf(x) < MAX_SUBS)
}
/** 自动分析层：认不出的名字丢掉、去重（iOS `Prefs.cleanAutoLayers`） */
export const autoLayerList = (v: unknown): AutoLayerId[] => [...new Set(strs(v).filter(x => (AUTO_LAYERS as readonly string[]).includes(x)))] as AutoLayerId[]
const idList = (v: unknown, pool: readonly IndicatorId[]): IndicatorId[] => [...new Set(strs(v).filter(x => (pool as readonly string[]).includes(x)))] as IndicatorId[]

// ───────── 指标布局：只有一份，跟人走（照 iOS Settings/Model/IndicatorLayouts.swift） ─────────
//
// 2026-09-27 曾按周期分三组（分钟 / 小时 / 日）各记一份、「继承直到分叉」。2026-10-03 用户在 1 小时调了副图
// 大小和顺序、切到 30 分「又被改回去了」，随后说死：「应该是通用的啊，不管什么周期……换了一个指标，切换四小时
// 发现不是自己要的指标这样就很怪」。所以现在指标布局（开了哪些指标、参数、副图顺序与高度、K 线画法、价格轴）
// 只有顶层这一份，任何周期都一样，并经云端在 iOS、手机网页、电脑网页之间互通。
//
// 当时还留着 `indicatorLayouts` 这个根认老档、老客户端的分叉（取当前周期所在组那份收拢、经同步发 null 清掉云端）。
// 2026-10-10 三端退役：10-03 之前的老客户端已经没了，这段迁移连同那个根一起删掉；老档里的这个键读时忽略，
// 云端残留由服务端 strip_retired 洗掉。删除前的代码在 tag sync-fields-before-retire-2026-10-10。
// 改法：直接改顶层那几项再 save()。

export const LAYOUT_KEYS = ['overlays', 'subs', 'params', 'subHeightOverrides', 'candleKind', 'priceMode'] as const
const clone = <T>(v: T): T => JSON.parse(JSON.stringify(v)) as T
/** 键序无关的相等 */
export function sameValue(a: unknown, b: unknown): boolean { return canon(a) === canon(b) }
function canon(v: unknown): string {
  if (Array.isArray(v)) return '[' + v.map(canon).join(',') + ']'
  if (v && typeof v === 'object') return '{' + Object.keys(v).filter(k => (v as Record<string, unknown>)[k] !== undefined).sort().map(k => JSON.stringify(k) + ':' + canon((v as Record<string, unknown>)[k])).join(',') + '}'
  return JSON.stringify(v) ?? 'null'
}

/** IndicatorLayout.sanitized（也用来把任意来源的值理成一份完整布局，缺的项取 base） */
export function sanitizeLayout(raw: unknown, base: IndicatorLayout = factoryLayout()): IndicatorLayout {
  const r = isRecord(raw) ? raw : {}
  return {
    overlays: Array.isArray(r.overlays) ? idList(r.overlays, OVERLAY_IDS) : [...base.overlays],
    subs: cappedSubs(Array.isArray(r.subs) ? idList(r.subs, SUB_IDS) : base.subs),
    params: isRecord(r.params) ? cleanParamTable(r.params) : clone(base.params),
    subHeightOverrides: isRecord(r.subHeightOverrides) ? cleanSubHeights(r.subHeightOverrides) : cleanSubHeights(base.subHeightOverrides),
    candleKind: oneOf(r.candleKind, ['candle', 'heikin', 'line'] as const, base.candleKind),
    priceMode: oneOf(r.priceMode, ['linear', 'log', 'percent'] as const, base.priceMode),
  }
}
export function factoryLayout(): IndicatorLayout { return currentLayout(defaultPrefs()) }

/** 这个人的布局（顶层那六项，拷贝） */
export function currentLayout(p: Pick<Prefs, typeof LAYOUT_KEYS[number]>): IndicatorLayout {
  return clone({ overlays: p.overlays, subs: p.subs, params: p.params, subHeightOverrides: p.subHeightOverrides, candleKind: p.candleKind, priceMode: p.priceMode })
}
/** 把一份布局装到顶层那六项上（拷贝） */
export function setCurrentLayout(p: Prefs, l: IndicatorLayout): void {
  const c = clone(l)
  p.overlays = c.overlays; p.subs = c.subs; p.params = c.params; p.subHeightOverrides = c.subHeightOverrides
  p.candleKind = c.candleKind; p.priceMode = c.priceMode
}

/** 把任意来源（本机旧档、云端）的值理成合法的 Prefs；缺的、坏的用出厂值 */
export function normalizePrefs(raw: unknown): Prefs {
  const d = defaultPrefs()
  const r = obj<Record<string, unknown>>(raw, {})
  const quick = [...new Set(strs(r.quickIntervals).filter(x => (INTERVALS as readonly string[]).includes(x)))]
    .sort((a, b) => INTERVALS.indexOf(a as IntervalId) - INTERVALS.indexOf(b as IntervalId)).slice(0, MAX_QUICK) as IntervalId[]
  const top = sanitizeLayout({
    overlays: r.overlays, subs: r.subs, params: isRecord(r.params) ? r.params : undefined,
    subHeightOverrides: r.subHeightOverrides, candleKind: r.candleKind, priceMode: r.priceMode,
  }, currentLayout(d))
  const out: Prefs = {
    interval: oneOf(r.interval, INTERVALS, d.interval),
    quickIntervals: quick.length ? quick : d.quickIntervals,
    theme: oneOf(r.theme, ['auto', 'light', 'dark'] as const, d.theme),
    skin: oneOf(r.skin, ['sage', 'terra', 'classic'] as const, d.skin),
    redUp: bool(r.redUp, d.redUp),
    compareSymbols: cleanCompare(r.compareSymbols),
    priceMode: top.priceMode,
    depth: bool(r.depth, d.depth),
    orderFlow: bool(r.orderFlow, d.orderFlow),
    orderFlowHistory: bool(r.orderFlowHistory, d.orderFlowHistory),
    orderFlowOverrides: cleanOrderFlowOverrides(r.orderFlowOverrides),
    candleKind: top.candleKind,
    barSpacing: num(r.barSpacing, d.barSpacing, BAR_SPACING[0], BAR_SPACING[1]),
    landscapeBarSpacing: num(r.landscapeBarSpacing, num(r.barSpacing, d.barSpacing, BAR_SPACING[0], BAR_SPACING[1]), BAR_SPACING[0], BAR_SPACING[1]),
    mainInverted: bool(r.mainInverted, d.mainInverted),
    subInverted: idList(r.subInverted, SUB_IDS),
    indicatorColors: cleanColors(r.indicatorColors),
    alertSound: oneOf(r.alertSound, ['default', 'crisp', 'electronic', 'glass'] as const, d.alertSound),
    watchMoveAlert: bool(r.watchMoveAlert, d.watchMoveAlert),
    favoritesTrend: bool(r.favoritesTrend, d.favoritesTrend),
    bigTradeSigns: bool(r.bigTradeSigns, d.bigTradeSigns),
    autoLayers: autoLayerList(r.autoLayers),
    notifyListingChanges: bool(r.notifyListingChanges, d.notifyListingChanges),
    habitLearning: bool(r.habitLearning, d.habitLearning),
    learnedDefaults: cleanLearned(r.learnedDefaults),
    overlays: top.overlays,
    subs: top.subs,
    params: top.params,
    subHeightOverrides: top.subHeightOverrides,
    routePolicy: oneOf(r.routePolicy, ['direct', 'gateway'] as const, d.routePolicy),
    favoritesGroup: typeof r.favoritesGroup === 'string' ? r.favoritesGroup.slice(0, 128) : d.favoritesGroup,
    sectorMarket: oneOf(r.sectorMarket, ['crypto', 'us'] as const, d.sectorMarket),
    sectorWindow: oneOf(r.sectorWindow, ['today', 'd5', 'd20'] as const, d.sectorWindow),
    // 只认画线工具词表里的名字（iOS PrefsCodec / 服务端 settings.lastDrawTool 同一把尺子）：认不出的退回空，
    // 不然手改的档、更高版本写下的新工具名会被原样推上去、整条 settings 被拒收。
    lastDrawTool: typeof r.lastDrawTool === 'string' && isDrawingKind(r.lastDrawTool) ? r.lastDrawTool : d.lastDrawTool,
    drawToolUsage: cleanDrawToolUsage(r.drawToolUsage),
    analysisUsage: cleanAnalysisUsage(r.analysisUsage),
    drawingOverlaysShown: bool(r.drawingOverlaysShown, d.drawingOverlaysShown),
    drawingsHidden: bool(r.drawingsHidden, d.drawingsHidden),
    reviewSearchScope: oneOf(r.reviewSearchScope, ['history', 'private'] as const, d.reviewSearchScope),
    reviewSegment: oneOf(r.reviewSegment, REVIEW_SEGMENTS, d.reviewSegment),
    reviewBookFilter: oneOf(r.reviewBookFilter, REVIEW_BOOK_FILTERS, d.reviewBookFilter),
  }
  return out
}

/** 取出要上云的那一份（只含 SYNCED_FIELDS） */
export function syncedSlice(p: Prefs): Record<string, unknown> {
  const out: Record<string, unknown> = {}
  for (const k of SYNCED_FIELDS) out[k] = p[k]
  return out
}
