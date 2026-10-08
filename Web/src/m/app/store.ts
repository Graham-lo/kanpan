/* Hkline 手机网页版 · 本机状态（localStorage「hkline-m-v1」）
 *
 * 形状照 PC 的 Web/src/app/store.ts：一个可变的 `st`，改完调 `save()` 落盘并通知订阅者；
 * `subscribe(fn)` 返回取消函数。字段分三块：
 *   - Prefs（与 iOS Prefs.swift 同名同义，见 ./prefs.ts；其中 SYNCED_FIELDS 进账号同步）
 *   - 自选（iOS SymbolPrefs：favorites 顺序、分组、最近打开）
 *   - 提醒表（形状共用 Web/src/alerts/shape.ts，与手机、服务端同步的 alerts 对象一字不差；
 *     读写经 m/model/alerts.ts，响一次就删）
 *   - 现场（当前页、品种、各页滚动位置）：随时落盘，冷启动恢复到原地
 *
 * Prefs、自选、提醒登录后经 ./sync.ts 与账号同步；本机这份永远完整，云端只是通道。
 *
 * 首帧前的皮肤由 m/index.html 的内联脚本按同一个键套上（theme / skin / redUp 三个字段，
 * redUp 只在 greenUpMigrated 之后才当真）。
 */
import { defaultPrefs, layoutSnapshot, normalizePrefs, settleIndicatorLayouts, type Prefs } from './prefs'
import { migrateAlert, type Alert } from '../../alerts/shape'
import { tabGuard } from './tabGuard'
import { backupUnreadable } from './unreadable'
import { validSymbol, webSymbol } from '../../sync/codec'

export const KEY = 'hkline-m-v1'
/** 提醒表并进 st 之前单独存的键（m/model/alerts.ts 早先用的）：第一次读档时搬进来，之后不再写 */
export const LEGACY_ALERTS_KEY = 'hkline-m-alerts-v1'

export type PageId = 'chart' | 'favorites' | 'sectors' | 'me'
export const PAGES: readonly PageId[] = ['chart', 'favorites', 'sectors', 'me']

export interface FavoriteGroup { id: string; name: string }
/** iOS SymbolPrefs */
export interface SymbolPrefs {
  /** 自选，用户自己的顺序（拖排序改的就是它） */
  favorites: string[]
  /** 最近打开，时间倒序，最多 10 条 */
  recents: string[]
  groups: FavoriteGroup[]
  /** 品种 → 分组 id；不在表里 = 未分类 */
  groupForSymbol: Record<string, string>
  /** 访客第一次打开时给过默认自选没有（只给一次，本机记号，不同步） */
  seeded: boolean
}

export interface State extends Prefs {
  /** 当前页 */
  page: PageId
  /** 当前品种（币安代号，如 BTCUSDT） */
  symbol: string
  /** 各页滚动位置（px），冷启动恢复。键是页 id，页里自己的滚动容器用「页.名」（shell.trackScroll） */
  scroll: Record<string, number>
  symbols: SymbolPrefs
  /** 提醒（价格 / 画线 / 条件）。只存还在等的；响了先标已触发、报完就删 */
  alerts: Alert[]
  /** 行情停住了没有（不落盘） */
  stale: boolean
  /** 用户亲手选过线路没有：没选过的，出厂值改了就跟着改（2026-10-02 出厂从直连改成网关） */
  routePicked: boolean
  /** 「一律绿涨红跌」（2026-10-03）那一次迁移做过没有：没做过的老档不论存的是什么都先迁成绿涨，
   *  做过之后的红涨就是用户自己切回去的，不再动。云端那份由服务端迁移 0041 同时翻，同步不会盖回去 */
  greenUpMigrated: boolean
}

/** 不落盘的字段 */
const TRANSIENT: (keyof State)[] = ['stale']

export function defaults(): State {
  return {
    ...defaultPrefs(),
    page: 'chart', symbol: 'BTCUSDT', scroll: {},
    symbols: { favorites: [], recents: [], groups: [], groupForSymbol: {}, seeded: false },
    routePicked: false,
    greenUpMigrated: true,
    alerts: [],
    stale: false,
  }
}

function ls(): Storage | null { try { return globalThis.localStorage ?? null } catch { return null } }

export function load(): Record<string, unknown> {
  // 读出来得是个对象：存档被写成 null / 数字 / 数组（别的版本、手改、扩展）时当空档，不然 hydrate 读 .symbols 直接白屏
  // 解不开时原文另存（m/app/unreadable）：下一次 save 会把主键整份盖掉，自选、分类、提醒只存在这一处
  let raw: string | null = null
  try { raw = ls()?.getItem(KEY) ?? null } catch { return {} }
  if (!raw) return {}
  let v: unknown
  try { v = JSON.parse(raw) } catch { v = undefined }
  if (v != null && typeof v === 'object' && !Array.isArray(v)) return v as Record<string, unknown>
  backupUnreadable(KEY, raw)
  return {}
}

const strs = (v: unknown): string[] => Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []
const alertList = (v: unknown): Alert[] => (Array.isArray(v) ? v : []).map(migrateAlert).filter((a): a is Alert => !!a)

/** 老档里单独存的提醒表（hkline-m-alerts-v1）；读不到是空表 */
function legacyAlerts(): unknown {
  try { return JSON.parse(ls()?.getItem(LEGACY_ALERTS_KEY) || '[]') as unknown } catch { return [] }
}

export function hydrate(raw: Record<string, unknown>): State {
  const d = defaults()
  const sym = (raw.symbols && typeof raw.symbols === 'object' ? raw.symbols : {}) as Partial<SymbolPrefs>
  const scroll = (raw.scroll && typeof raw.scroll === 'object' ? raw.scroll : {}) as Record<string, unknown>
  return {
    ...normalizePrefs(raw),
    page: (PAGES as readonly unknown[]).includes(raw.page) ? raw.page as PageId : d.page,
    // 别家的完整键（okx/usd_m/BTCUSDT、coinbase/spot/BTC-USD……，2026-10-08 起）按注册表那一家的代号形状认（webSymbol）
    symbol: typeof raw.symbol === 'string' && (/^[A-Z0-9]{2,30}$/.test(raw.symbol) || validSymbol(raw.symbol) || webSymbol(raw.symbol)) ? raw.symbol : d.symbol,
    scroll: Object.fromEntries(Object.entries(scroll).filter((e): e is [string, number] => /^[\w.-]{1,48}$/.test(e[0]) && typeof e[1] === 'number' && e[1] >= 0)),
    symbols: {
      favorites: [...new Set(strs(sym.favorites))],
      recents: [...new Set(strs(sym.recents))].slice(0, 10),
      groups: Array.isArray(sym.groups) ? sym.groups.filter(g => g && typeof g.id === 'string' && g.id).map(g => ({ id: g.id, name: typeof g.name === 'string' && g.name ? g.name : g.id })) : [],
      // 归属只收「代号 → 分类 id 字符串」：别的形状推上去会被服务端整条拒掉（groupId 只收字符串）
      groupForSymbol: sym.groupForSymbol && typeof sym.groupForSymbol === 'object' ? Object.fromEntries(Object.entries(sym.groupForSymbol).filter((e): e is [string, string] => typeof e[1] === 'string' && !!e[1])) : {},
      seeded: sym.seeded === true,
    },
    // 并进 st 之前提醒存在自己的键里：档里还没有 alerts 字段时搬一次
    alerts: alertList('alerts' in raw ? raw.alerts : legacyAlerts()),
    stale: false,
    routePicked: raw.routePicked === true,
    ...(raw.routePicked === true ? {} : { routePolicy: d.routePolicy }),
    greenUpMigrated: true,
    ...(raw.greenUpMigrated === true ? {} : { redUp: false }),
  }
}

export const st: State = hydrate(load())

const subs = new Set<(s: State) => void>()
/** 每次 save() 之后回调；返回取消函数 */
export function subscribe(fn: (s: State) => void): () => void { subs.add(fn); return () => { subs.delete(fn) } }

let layoutBefore = layoutSnapshot(st)

/** 指标布局是整份换进来的（云端装进来、恢复出厂）：以现在这份为「改动之前」，下一次 save 不把它当成用户在当前组改了指标 */
export function layoutSettled(): void { layoutBefore = layoutSnapshot(st) }

/** 落盘（手势结束、改设置、切页……立刻调，不节流）并通知订阅者。
 *  落盘前先把指标布局收拢成一份（iOS PrefsStore 的每一条改法都过 settleIndicatorLayouts） */
export function save(): void {
  settleIndicatorLayouts(st, layoutBefore)
  layoutBefore = layoutSnapshot(st)
  // 被别的标签页比下去了（tabGuard）就不写盘，切回来会重载
  tabGuard.write(KEY)
  subs.forEach(fn => { try { fn(st) } catch (e) { console.error(e) } })
}

/** 只落盘、不通知（滚动位置这种高频又没人关心的） */
export function persistQuiet(): void {
  settleIndicatorLayouts(st, layoutBefore)
  layoutBefore = layoutSnapshot(st)
  tabGuard.write(KEY)
}

function serialize(): string {
  const out: Record<string, unknown> = {}
  for (const [k, v] of Object.entries(st)) if (!TRANSIENT.includes(k as keyof State)) out[k] = v
  return JSON.stringify(out)
}
/** 旧了（别的标签页更近被人动过、写了新的）：把它写的那份收进内存并照常通知（同步据此记账推上去），不写盘。
 *  现场（当前页、品种、滚动）留本页的，免得后台页的界面跟着跳；读不出东西就不收。 */
function adopt(): void {
  const raw = load()
  if (!Object.keys(raw).length) return
  const keep = { page: st.page, symbol: st.symbol, scroll: st.scroll, stale: st.stale }
  Object.assign(st, hydrate(raw), keep)
  layoutSettled()
  save()
}
tabGuard.register(KEY, serialize, adopt)

// 老档的提醒表迁进 st.alerts 之后，写成了就把老键删掉：留着的话，哪天主档读不出来（被清、写坏）
// hydrate 会把这份早已删过、响过的老提醒又搬回来
if (ls()?.getItem(LEGACY_ALERTS_KEY) != null && tabGuard.write(KEY) && 'alerts' in load()) ls()?.removeItem(LEGACY_ALERTS_KEY)

/** 恢复出厂（我的 → 设置里用） */
export function resetAll(): void {
  // 提醒不是设置：恢复出厂不动它
  Object.assign(st, defaults(), { alerts: st.alerts })
  layoutSettled()
  save()
}

/** theme = auto 时跟系统；返回实际的浅 / 深 */
export function resolvedTheme(s: Pick<State, 'theme'> = st): 'light' | 'dark' {
  if (s.theme === 'light' || s.theme === 'dark') return s.theme
  try { return globalThis.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light' } catch { return 'light' }
}
