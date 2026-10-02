/* Hkline 手机网页版 · 偏好的字段表（照 iOS Kanpan/Kanpan/Settings/Model/Prefs.swift）
 *
 * 三份清单必须一致（tests/m-prefs.test.ts 守着）：
 *   1. iOS 契约 Backend/kanpan-api/contract/settings-fields.json 里 fieldClasses 为 synced 的字段；
 *   2. 服务端 Backend/kanpan-api/src/sync.rs 的 SETTINGS_FIELDS 减去契约的 wireOnlyKeys
 *      （compactValues / drawToolGroup / routePolicy / styleID：服务端还认、客户端早已不收不发）；
 *   3. 这里的 SYNCED_FIELDS。
 * 服务端对含未知字段的操作整条拒绝，多发一个键就会把整条队列堵死，所以宁可少不可多。
 */

import { compareKey } from '../../sync/codec'

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
    params, subHeightOverrides: {}, indicatorLayouts: { others: {} }, routePolicy: 'gateway',
    favoritesGroup: '', sectorMarket: 'crypto', sectorWindow: 'today', lastDrawTool: '', reviewSearchScope: 'history',
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
/** Prefs.clampPortraitHeight */
export const PORTRAIT_HEIGHT = [0.1, 1] as const
/** IndicatorLayout.sanitized：副图高度倍数 */
export const SUB_HEIGHT = [0.5, 2] as const
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
    const k = x.includes('/') ? x : 'binance/usd_m/' + x.toUpperCase()
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
const idList = (v: unknown, pool: readonly IndicatorId[]): IndicatorId[] => [...new Set(strs(v).filter(x => (pool as readonly string[]).includes(x)))] as IndicatorId[]

// ───────── 指标按周期分组记忆（照 iOS Settings/Model/IndicatorLayouts.swift） ─────────
//
// 周期分三组：分钟（1m…30m）、小时（1h…12h）、日（1d 起）。规则是「继承直到分叉」：三组起初共用一份，
// 在某一组里改了指标（主图 / 副图 / 参数 / 副图高度 / K 线画法 / 价格轴）那一组才分出自己的一份。
//
// 内存里：Prefs 顶层那六项永远是**当前周期所在组**的那份（读指标的地方只读顶层）；
// `indicatorLayouts.shared` 只在当前组分了叉时存共用的那份，`others` 是当前组以外分了叉的组。
// 改法：直接改顶层那几项（或 interval）再 save()，store 在落盘前调 settleIndicatorLayouts 理顺分组。
// 线上：顶层老键写共用的那份，`indicatorLayouts/<组>` 只写分了叉的组（sync 的 codec 管）。

export type LayoutGroup = 'minute' | 'hour' | 'day'
export const LAYOUT_GROUPS: readonly LayoutGroup[] = ['minute', 'hour', 'day']
export function layoutGroup(iv: IntervalId): LayoutGroup {
  return iv.endsWith('m') && iv !== '1M' ? 'minute' : iv.endsWith('h') ? 'hour' : 'day'
}
export interface LayoutBook { shared: IndicatorLayout; forks: Partial<Record<LayoutGroup, IndicatorLayout>> }

const LAYOUT_KEYS = ['overlays', 'subs', 'params', 'subHeightOverrides', 'candleKind', 'priceMode'] as const
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

/** 当前周期所在组的布局（顶层那六项，拷贝） */
export function currentLayout(p: Pick<Prefs, typeof LAYOUT_KEYS[number]>): IndicatorLayout {
  return clone({ overlays: p.overlays, subs: p.subs, params: p.params, subHeightOverrides: p.subHeightOverrides, candleKind: p.candleKind, priceMode: p.priceMode })
}
function setCurrentLayout(p: Prefs, l: IndicatorLayout): void {
  const c = clone(l)
  p.overlays = c.overlays; p.subs = c.subs; p.params = c.params; p.subHeightOverrides = c.subHeightOverrides
  p.candleKind = c.candleKind; p.priceMode = c.priceMode
}
/** 三组全貌；`group`：把顶层那份当成哪一组来读（换周期那一下顶层还是旧组的） */
export function layoutBook(p: Prefs, group: LayoutGroup = layoutGroup(p.interval)): LayoutBook {
  const forks: Partial<Record<LayoutGroup, IndicatorLayout>> = clone(p.indicatorLayouts.others) as Partial<Record<LayoutGroup, IndicatorLayout>>
  delete forks[group]
  if (!p.indicatorLayouts.shared) return { shared: currentLayout(p), forks }
  forks[group] = currentLayout(p)
  return { shared: clone(p.indicatorLayouts.shared), forks }
}
/** 按当前周期把三组全貌装回来：顶层换成当前组那份，其余进记忆 */
export function adoptBook(p: Prefs, book: LayoutBook): void {
  const g = layoutGroup(p.interval)
  const own = book.forks[g]
  setCurrentLayout(p, own ?? book.shared)
  const others = clone(book.forks) as Record<string, IndicatorLayout>
  delete others[g]
  p.indicatorLayouts = { ...(own ? { shared: clone(book.shared) } : {}), others }
}

/** settleIndicatorLayouts 要看的「改动之前」 */
export type LayoutSnapshot = Pick<Prefs, 'interval' | 'indicatorLayouts' | typeof LAYOUT_KEYS[number]>
export function layoutSnapshot(p: Prefs): LayoutSnapshot {
  return clone({ interval: p.interval, indicatorLayouts: p.indicatorLayouts, overlays: p.overlays, subs: p.subs, params: p.params, subHeightOverrides: p.subHeightOverrides, candleKind: p.candleKind, priceMode: p.priceMode })
}

/** Prefs.settleIndicatorLayouts(after:)：一次改动（before → 现在）之后理顺分组记忆。
 *  - 调用方连 indicatorLayouts 一起换了（云端装进来、恢复出厂）：那份就是答案，只按现在的周期重新投影；
 *  - 顶层那几项被改了：改的是改完之后周期所在的那一组，那组还共用就此分叉；
 *  - 只换了周期、跨了组：顶层换成新组那份。
 *  返回这一下新分叉出来的组，没有就是 null */
export function settleIndicatorLayouts(p: Prefs, before: LayoutSnapshot): LayoutGroup | null {
  if (!sameValue(p.indicatorLayouts, before.indicatorLayouts)) { adoptBook(p, layoutBook(p)); return null }
  const prev = { ...defaultPrefs(), ...clone(before) } as Prefs
  const book = layoutBook(prev)
  const g = layoutGroup(p.interval)
  const now = currentLayout(p)
  let forked: LayoutGroup | null = null
  if (!sameValue(now, currentLayout(prev)) && !sameValue(now, book.forks[g] ?? book.shared)) {
    if (!book.forks[g]) forked = g
    book.forks[g] = now
  }
  adoptBook(p, book)
  return forked
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
  const mem = obj<Record<string, unknown>>(r.indicatorLayouts, {})
  const others: Record<string, IndicatorLayout> = {}
  for (const [g, l] of Object.entries(obj<Record<string, unknown>>(mem.others, {}))) if ((LAYOUT_GROUPS as readonly string[]).includes(g) && isRecord(l)) others[g] = sanitizeLayout(l, top)
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
    orderFlowOverrides: cleanOrderFlowOverrides(r.orderFlowOverrides),
    candleKind: top.candleKind,
    barSpacing: num(r.barSpacing, d.barSpacing, BAR_SPACING[0], BAR_SPACING[1]),
    mainInverted: bool(r.mainInverted, d.mainInverted),
    subInverted: idList(r.subInverted, SUB_IDS),
    portraitHeight: num(r.portraitHeight, d.portraitHeight, PORTRAIT_HEIGHT[0], PORTRAIT_HEIGHT[1]),
    indicatorColors: cleanColors(r.indicatorColors),
    alertSound: oneOf(r.alertSound, ['default', 'crisp', 'electronic', 'glass'] as const, d.alertSound),
    watchMoveAlert: bool(r.watchMoveAlert, d.watchMoveAlert),
    notifyListingChanges: bool(r.notifyListingChanges, d.notifyListingChanges),
    habitLearning: bool(r.habitLearning, d.habitLearning),
    learnedDefaults: cleanLearned(r.learnedDefaults),
    overlays: top.overlays,
    subs: top.subs,
    params: top.params,
    subHeightOverrides: top.subHeightOverrides,
    indicatorLayouts: { ...(isRecord(mem.shared) ? { shared: sanitizeLayout(mem.shared, top) } : {}), others },
    routePolicy: oneOf(r.routePolicy, ['direct', 'gateway'] as const, d.routePolicy),
    favoritesGroup: typeof r.favoritesGroup === 'string' ? r.favoritesGroup.slice(0, 128) : d.favoritesGroup,
    sectorMarket: oneOf(r.sectorMarket, ['crypto', 'us'] as const, d.sectorMarket),
    sectorWindow: oneOf(r.sectorWindow, ['today', 'd5', 'd20'] as const, d.sectorWindow),
    lastDrawTool: typeof r.lastDrawTool === 'string' ? r.lastDrawTool : d.lastDrawTool,
    reviewSearchScope: oneOf(r.reviewSearchScope, ['history', 'private'] as const, d.reviewSearchScope),
  }
  // 记忆里不该有当前组自己（当前组那份就是顶层）
  delete out.indicatorLayouts.others[layoutGroup(out.interval)]
  return out
}

/** 取出要上云的那一份（只含 SYNCED_FIELDS） */
export function syncedSlice(p: Prefs): Record<string, unknown> {
  const out: Record<string, unknown> = {}
  for (const k of SYNCED_FIELDS) out[k] = p[k]
  return out
}
