/* Hkline 手机网页版 · 偏好的字段表（照 iOS Kanpan/Kanpan/Settings/Model/Prefs.swift）
 *
 * 三份清单必须一致（tests/m-prefs.test.ts 守着）：
 *   1. iOS 契约 Backend/kanpan-api/contract/settings-fields.json 里 fieldClasses 为 synced 的字段；
 *   2. 服务端 Backend/kanpan-api/src/sync.rs 的 SETTINGS_FIELDS 减去契约的 wireOnlyKeys
 *      （compactValues / drawToolGroup / routePolicy / styleID：服务端还认、客户端早已不收不发）；
 *   3. 这里的 SYNCED_FIELDS。
 * 服务端对含未知字段的操作整条拒绝，多发一个键就会把整条队列堵死，所以宁可少不可多。
 */

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

/** IndicatorID.defaultParams */
export const DEFAULT_PARAMS: Partial<Record<IndicatorId, number[]>> = {
  MA: [10, 30, 120, 256], EMA: [12, 144, 169, 200], BOLL: [20, 2], VOL: [5, 10, 30, 60, 120],
  MACD: [10, 30, 9], RSI: [6, 12, 24], KDJ: [9, 3, 3], SRSI: [14, 14, 3, 3], ATR: [14], ST: [10, 3], DMI: [14],
}
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
/** IndicatorLayout：按周期组记住的一整套指标布局 */
export interface IndicatorLayout {
  overlays: IndicatorId[]; subs: IndicatorId[]; params: Partial<Record<IndicatorId, number[]>>
  subHeightOverrides: Partial<Record<IndicatorId, number>>; candleKind: CandleKind; priceMode: PriceMode
}
export interface IndicatorLayoutMemory { shared?: IndicatorLayout; others: Record<string, IndicatorLayout> }

/** 与 iOS Prefs 同名同义的那些字段（体验类状态，跟着人走） */
export interface Prefs {
  interval: IntervalId
  quickIntervals: IntervalId[]
  theme: ThemeChoice
  skin: Skin
  /** 红涨绿跌（出厂 true）；html 上对应 data-updown="red-up" */
  redUp: boolean
  compareSymbols: string[]
  priceMode: PriceMode
  depth: boolean
  orderFlow: boolean
  orderFlowOverrides: Record<string, OrderFlowOverride>
  candleKind: CandleKind
  barSpacing: number
  mainInverted: boolean
  subInverted: IndicatorId[]
  /** 竖屏时主图占图区的比例 */
  portraitHeight: number
  /** 指标 → 线序号 → 颜色（#RRGGBB） */
  indicatorColors: Partial<Record<IndicatorId, Record<string, string>>>
  alertSound: AlertSound
  watchMoveAlert: boolean
  notifyListingChanges: boolean
  habitLearning: boolean
  learnedDefaults: LearnedDefaults
  overlays: IndicatorId[]
  subs: IndicatorId[]
  params: Partial<Record<IndicatorId, number[]>>
  subHeightOverrides: Partial<Record<IndicatorId, number>>
  indicatorLayouts: IndicatorLayoutMemory
  /** 本机字段（deviceOnly）：不同步 */
  routePolicy: RoutePolicy
  favoritesGroup: string
  sectorMarket: SectorMarket
  sectorWindow: SectorWindow
  lastDrawTool: string
  reviewSearchScope: ReviewSearchScope
}

/** 进账号同步的字段（settings 集合）。顺序无意义，集合必须与 iOS 契约、服务端对齐 */
export const SYNCED_FIELDS = [
  'alertSound', 'barSpacing', 'candleKind', 'compareSymbols', 'depth', 'favoritesGroup', 'habitLearning',
  'indicatorColors', 'indicatorLayouts', 'interval', 'lastDrawTool', 'learnedDefaults', 'mainInverted',
  'notifyListingChanges', 'orderFlow', 'orderFlowOverrides', 'overlays', 'params', 'portraitHeight', 'priceMode',
  'quickIntervals', 'redUp', 'reviewSearchScope', 'sectorMarket', 'sectorWindow', 'skin', 'subHeightOverrides',
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
    interval: '1h', quickIntervals: [...QUICK_INTERVALS], theme: 'auto', skin: 'sage', redUp: true,
    compareSymbols: [], priceMode: 'log', depth: false, orderFlow: false, orderFlowOverrides: {},
    candleKind: 'candle', barSpacing: 4, mainInverted: false, subInverted: [], portraitHeight: 0.5,
    indicatorColors: {}, alertSound: 'default', watchMoveAlert: false, notifyListingChanges: false,
    habitLearning: true, learnedDefaults: emptyLearned(), overlays: ['MA'], subs: ['VOL', 'OI', 'MACD'],
    params, subHeightOverrides: {}, indicatorLayouts: { others: {} }, routePolicy: 'direct',
    favoritesGroup: '', sectorMarket: 'crypto', sectorWindow: 'today', lastDrawTool: '', reviewSearchScope: 'history',
  }
}

const oneOf = <T extends string>(v: unknown, list: readonly T[], d: T): T => (list as readonly unknown[]).includes(v) ? v as T : d
const bool = (v: unknown, d: boolean): boolean => typeof v === 'boolean' ? v : d
const num = (v: unknown, d: number, lo = -Infinity, hi = Infinity): number => typeof v === 'number' && Number.isFinite(v) ? Math.min(hi, Math.max(lo, v)) : d
const obj = <T>(v: unknown, d: T): T => v && typeof v === 'object' && !Array.isArray(v) ? v as T : d
const strs = (v: unknown): string[] => Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []
const ALL_IDS: readonly IndicatorId[] = [...OVERLAY_IDS, ...SUB_IDS]

/** 把任意来源（本机旧档、云端）的值理成合法的 Prefs；缺的、坏的用出厂值 */
export function normalizePrefs(raw: unknown): Prefs {
  const d = defaultPrefs()
  const r = obj<Record<string, unknown>>(raw, {})
  const ids = (v: unknown, pool: readonly IndicatorId[]): IndicatorId[] => [...new Set(strs(v).filter(x => (pool as readonly string[]).includes(x)))] as IndicatorId[]
  const quick = [...new Set(strs(r.quickIntervals).filter(x => (INTERVALS as readonly string[]).includes(x)))].slice(0, MAX_QUICK) as IntervalId[]
  const subs = Array.isArray(r.subs) ? ids(r.subs, SUB_IDS) : d.subs
  const nonVol = subs.filter(x => x !== 'VOL')
  return {
    interval: oneOf(r.interval, INTERVALS, d.interval),
    quickIntervals: quick.length ? quick : d.quickIntervals,
    theme: oneOf(r.theme, ['auto', 'light', 'dark'] as const, d.theme),
    skin: oneOf(r.skin, ['sage', 'terra', 'classic'] as const, d.skin),
    redUp: bool(r.redUp, d.redUp),
    compareSymbols: strs(r.compareSymbols),
    priceMode: oneOf(r.priceMode, ['linear', 'log', 'percent'] as const, d.priceMode),
    depth: bool(r.depth, d.depth),
    orderFlow: bool(r.orderFlow, d.orderFlow),
    orderFlowOverrides: obj(r.orderFlowOverrides, d.orderFlowOverrides),
    candleKind: oneOf(r.candleKind, ['candle', 'heikin', 'line'] as const, d.candleKind),
    barSpacing: num(r.barSpacing, d.barSpacing, 0.5, 60),
    mainInverted: bool(r.mainInverted, d.mainInverted),
    subInverted: ids(r.subInverted, SUB_IDS),
    portraitHeight: num(r.portraitHeight, d.portraitHeight, 0.2, 0.9),
    indicatorColors: obj(r.indicatorColors, d.indicatorColors),
    alertSound: oneOf(r.alertSound, ['default', 'crisp', 'electronic', 'glass'] as const, d.alertSound),
    watchMoveAlert: bool(r.watchMoveAlert, d.watchMoveAlert),
    notifyListingChanges: bool(r.notifyListingChanges, d.notifyListingChanges),
    habitLearning: bool(r.habitLearning, d.habitLearning),
    learnedDefaults: { ...emptyLearned(), ...obj<Partial<LearnedDefaults>>(r.learnedDefaults, {}) },
    overlays: Array.isArray(r.overlays) ? ids(r.overlays, OVERLAY_IDS) : d.overlays,
    subs: subs.filter(x => x === 'VOL' || nonVol.indexOf(x) < MAX_SUBS),
    params: (() => {
      const p = obj<Record<string, unknown>>(r.params, d.params as Record<string, unknown>)
      const out: Partial<Record<IndicatorId, number[]>> = {}
      for (const [k, v] of Object.entries(p)) if ((ALL_IDS as readonly string[]).includes(k) && Array.isArray(v)) out[k as IndicatorId] = v.filter(x => typeof x === 'number' && Number.isFinite(x))
      return out
    })(),
    subHeightOverrides: obj(r.subHeightOverrides, d.subHeightOverrides),
    indicatorLayouts: (() => { const m = obj<Partial<IndicatorLayoutMemory>>(r.indicatorLayouts, {}); return { ...(m.shared ? { shared: m.shared } : {}), others: obj(m.others, {}) } })(),
    routePolicy: oneOf(r.routePolicy, ['direct', 'gateway'] as const, d.routePolicy),
    favoritesGroup: typeof r.favoritesGroup === 'string' ? r.favoritesGroup : d.favoritesGroup,
    sectorMarket: oneOf(r.sectorMarket, ['crypto', 'us'] as const, d.sectorMarket),
    sectorWindow: oneOf(r.sectorWindow, ['today', 'd5', 'd20'] as const, d.sectorWindow),
    lastDrawTool: typeof r.lastDrawTool === 'string' ? r.lastDrawTool : d.lastDrawTool,
    reviewSearchScope: oneOf(r.reviewSearchScope, ['history', 'private'] as const, d.reviewSearchScope),
  }
}

/** 取出要上云的那一份（只含 SYNCED_FIELDS） */
export function syncedSlice(p: Prefs): Record<string, unknown> {
  const out: Record<string, unknown> = {}
  for (const k of SYNCED_FIELDS) out[k] = p[k]
  return out
}
