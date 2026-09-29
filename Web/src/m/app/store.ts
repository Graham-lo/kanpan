/* Hkline 手机网页版 · 本机状态（localStorage「hkline-m-v1」）
 *
 * 形状照 PC 的 Web/src/app/store.ts：一个可变的 `st`，改完调 `save()` 落盘并通知订阅者；
 * `subscribe(fn)` 返回取消函数。字段分三块：
 *   - Prefs（与 iOS Prefs.swift 同名同义，见 ./prefs.ts；其中 SYNCED_FIELDS 进账号同步）
 *   - 自选（iOS SymbolPrefs：favorites 顺序、分组、最近打开）
 *   - 现场（当前页、品种、各页滚动位置）：随时落盘，冷启动恢复到原地
 *
 * 首帧前的皮肤由 m/index.html 的内联脚本按同一个键套上（theme / skin / redUp 三个字段）。
 */
import { defaultPrefs, normalizePrefs, type Prefs } from './prefs'

export const KEY = 'hkline-m-v1'

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
  /** 各页滚动位置（px），冷启动恢复 */
  scroll: Partial<Record<PageId, number>>
  symbols: SymbolPrefs
  /** 行情停住了没有（不落盘） */
  stale: boolean
}

/** 不落盘的字段 */
const TRANSIENT: (keyof State)[] = ['stale']

export function defaults(): State {
  return {
    ...defaultPrefs(),
    page: 'chart', symbol: 'BTCUSDT', scroll: {},
    symbols: { favorites: [], recents: [], groups: [], groupForSymbol: {}, seeded: false },
    stale: false,
  }
}

function ls(): Storage | null { try { return globalThis.localStorage ?? null } catch { return null } }

export function load(): Record<string, unknown> {
  try { return JSON.parse(ls()?.getItem(KEY) || '{}') as Record<string, unknown> } catch { return {} }
}

const strs = (v: unknown): string[] => Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []

export function hydrate(raw: Record<string, unknown>): State {
  const d = defaults()
  const sym = (raw.symbols && typeof raw.symbols === 'object' ? raw.symbols : {}) as Partial<SymbolPrefs>
  const scroll = (raw.scroll && typeof raw.scroll === 'object' ? raw.scroll : {}) as Record<string, unknown>
  return {
    ...normalizePrefs(raw),
    page: (PAGES as readonly unknown[]).includes(raw.page) ? raw.page as PageId : d.page,
    symbol: typeof raw.symbol === 'string' && /^[A-Z0-9]{2,30}$/.test(raw.symbol) ? raw.symbol : d.symbol,
    scroll: Object.fromEntries(Object.entries(scroll).filter(([k, v]) => (PAGES as readonly string[]).includes(k) && typeof v === 'number' && v >= 0)),
    symbols: {
      favorites: [...new Set(strs(sym.favorites))],
      recents: [...new Set(strs(sym.recents))].slice(0, 10),
      groups: Array.isArray(sym.groups) ? sym.groups.filter(g => g && typeof g.id === 'string' && g.id).map(g => ({ id: g.id, name: typeof g.name === 'string' && g.name ? g.name : g.id })) : [],
      groupForSymbol: sym.groupForSymbol && typeof sym.groupForSymbol === 'object' ? { ...sym.groupForSymbol } : {},
      seeded: sym.seeded === true,
    },
    stale: false,
  }
}

export const st: State = hydrate(load())

const subs = new Set<(s: State) => void>()
/** 每次 save() 之后回调；返回取消函数 */
export function subscribe(fn: (s: State) => void): () => void { subs.add(fn); return () => { subs.delete(fn) } }

/** 落盘（手势结束、改设置、切页……立刻调，不节流）并通知订阅者 */
export function save(): void {
  const out: Record<string, unknown> = {}
  for (const [k, v] of Object.entries(st)) if (!TRANSIENT.includes(k as keyof State)) out[k] = v
  try { ls()?.setItem(KEY, JSON.stringify(out)) } catch { /* 存储满了：这一轮不落盘 */ }
  subs.forEach(fn => { try { fn(st) } catch (e) { console.error(e) } })
}

/** 只落盘、不通知（滚动位置这种高频又没人关心的） */
export function persistQuiet(): void {
  const out: Record<string, unknown> = {}
  for (const [k, v] of Object.entries(st)) if (!TRANSIENT.includes(k as keyof State)) out[k] = v
  try { ls()?.setItem(KEY, JSON.stringify(out)) } catch { /* 忽略 */ }
}

/** 恢复出厂（我的 → 设置里用） */
export function resetAll(): void {
  Object.assign(st, defaults())
  save()
}

/** theme = auto 时跟系统；返回实际的浅 / 深 */
export function resolvedTheme(s: Pick<State, 'theme'> = st): 'light' | 'dark' {
  if (s.theme === 'light' || s.theme === 'dark') return s.theme
  try { return globalThis.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light' } catch { return 'light' }
}
