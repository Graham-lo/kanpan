/* Hkline Web · 电脑网页独有的设置（settings 对象的 webPrefs 字段，2026-10-10 起随账号走）
 *
 * 用手改出来、而手机没有对应字段的习惯都装在这一个对象里（服务端 sync.rs WEB_SETTINGS_FIELDS 单列：对象、序列化 ≤ 8 KB；
 * 手机 / 手机网页不认这个键，推送时原样带回）：
 * - 皮肤与深浅：电脑网页自己的一套视觉，不和手机的 skin / theme 共用
 * - 和手机上限不同的那几项的整份：周期条（手机最多 6 个）、副图（手机 3 个）、指标参数（手机只收 1…400 的整数）。
 *   共用字段（quickIntervals / subs / params/<ID>）只装各端都能表达的那部分（codec），这里留整份，装回来时合并
 * - 电脑网页独有的指标开关：一目均衡表、成交量分布、关键价位、第三批主图叠加（mains）
 * - 联动四项、梯子 / 抽屉 / 侧栏小部件、侧栏开的哪块、自选标签页、提醒范围、「我的」停在哪一节
 * - 画线锁定、同族画线样式与工具栏每组上次用的那把（手机的 drawingPreferences 只装得下其中一部分）
 * - 别的模块登记进来的块（registerWebPref）：订单流显示偏好、副图高与多图网格的比例、复盘页签
 * 不在这里的：线路（每台设备自己的）、像素尺寸、最近用过的颜色这类自动统计、自定义分钟周期与订单流「显示」那组（不做清单）。
 *
 * 规矩：键缺着（体积超了被挤掉）就不动本机那一项；块的值由登记它的模块自己清洗。
 * 不碰 DOM；st 那几项由 codec 传进来的状态读写，不 import app/store（store → codec → 这里，反向引用会成环）。
 */
import type { IndState, PanelId, Slots, State, WidgetId } from '../app/store'
import { CATALOG, MAX_SUBS, type IndParams, type IndicatorId } from '../chart/calc'
import { isMoreMain } from '../chart/mainIndicators'
import { INTERVALS, type Kind } from '../market/symbols'
import type { Json } from './types'

/** 序列化上限（和服务端 sync_validation WEB_PREFS_MAX_BYTES 同一个数） */
export const WEB_PREFS_MAX_BYTES = 8192

/** webPrefs 里 st 那几项的来源（单元测试里的精简状态可以只有 pinned / ind / params） */
export type WebPrefsState = { pinned: string[]; ind: IndState; params: Record<string, IndParams> | null } & Partial<Pick<State,
  'theme' | 'skin' | 'vpvrMode' | 'linkCross' | 'linkSymbol' | 'linkIv' | 'linkTime' | 'slots' | 'panel' | 'lastPanel' | 'watchTab' |
  'alertScope' | 'meSection' | 'drawLocked' | 'drawStyles' | 'toolLast'>>

// ───────── 别的模块登记的块 ─────────

export interface WebPrefPart {
  /** 现在的值（要能 JSON 序列化；没有自定义时也给一个值，比如 {}，免得别的电脑留着旧的） */
  read(): Json
  /** 装进云端那份：自己清洗、自己落本机、自己刷新界面；落盘时别叫 webPrefsTouched（这里会挡掉） */
  write(v: unknown): void
}
const parts = new Map<string, WebPrefPart>()
/** 体积超了先挤掉谁（靠前的先挤）：比例最占地方、丢了也只是回默认 */
const DROP_ORDER = ['grid', 'panes', 'toolLast', 'drawStyles', 'review', 'of']

export function registerWebPref(key: string, part: WebPrefPart): void { parts.set(key, part) }
const listeners = new Set<() => void>()
let writing = false
/** 登记的块被人改了：同步层据此记一次本机改动、排一次记账（装云端那份时的落盘不算） */
export function webPrefsTouched(): void { if (!writing) listeners.forEach(fn => fn()) }
export function onWebPrefsTouched(fn: () => void): () => void { listeners.add(fn); return () => { listeners.delete(fn) } }

// ───────── 清洗 ─────────

const isObj = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v)
const bool = (v: unknown): boolean | undefined => (typeof v === 'boolean' ? v : undefined)
const PANELS: PanelId[] = ['watch', 'alerts', 'flow', 'notes', 'trades']
const WIDGETS: WidgetId[] = ['watch', 'detail', 'book', 'tape', 'walls', 'alerts', 'liq', 'vol']
const KINDS: Kind[] = ['crypto', 'us', 'idx', 'com']
const SUB_IDS = new Set(Object.entries(CATALOG).filter(([, c]) => c.place === 'sub').map(([k]) => k))
const HEX = /^#[0-9A-Fa-f]{6}$/

/** 指标参数的规范形（和 app/store cleanParams 同一口径：认识的指标、认识的键、0 < x ≤ 2000，周期列表 ≤ 8 个整数） */
export function cleanParamsMap(raw: unknown): Record<string, IndParams> | null {
  if (!isObj(raw)) return null
  const out: Record<string, IndParams> = {}
  for (const [id, p] of Object.entries(raw)) {
    const cat = CATALOG[id as IndicatorId]
    if (!cat || !isObj(p)) continue
    const one: Record<string, unknown> = { ...(cat.params || {}) }
    for (const [k, v] of Object.entries(p)) {
      if (k === 'periods') { if (Array.isArray(v) && v.length && v.length <= 8 && v.every(x => Number.isInteger(x) && x >= 1 && x <= 2000)) one.periods = v.slice() }
      else if (typeof v === 'number' && Number.isFinite(v) && v > 0 && v <= 2000 && k in (cat.params || {})) one[k] = v
    }
    if (Object.keys(one).length) out[id] = one as IndParams
  }
  return Object.keys(out).length ? out : null
}
const strList = (v: unknown, ok: (x: string) => boolean, max: number): string[] | undefined =>
  Array.isArray(v) ? [...new Set(v.filter((x): x is string => typeof x === 'string' && ok(x)))].slice(0, max) : undefined
function styleMap(v: unknown): Record<string, { color?: string; width?: number; dash?: 'dashed' | 'dotted' }> | undefined {
  if (!isObj(v)) return undefined
  const out: Record<string, { color?: string; width?: number; dash?: 'dashed' | 'dotted' }> = {}
  for (const [k, x] of Object.entries(v)) {
    if (!isObj(x) || k.length > 32) continue
    const one: { color?: string; width?: number; dash?: 'dashed' | 'dotted' } = {}
    if (typeof x.color === 'string' && HEX.test(x.color)) one.color = x.color
    if (typeof x.width === 'number' && x.width >= 1 && x.width <= 8) one.width = x.width
    if (x.dash === 'dashed' || x.dash === 'dotted') one.dash = x.dash
    out[k] = one
  }
  return out
}
function strMap(v: unknown): Record<string, string> | undefined {
  if (!isObj(v)) return undefined
  const out: Record<string, string> = {}
  for (const [k, x] of Object.entries(v)) if (typeof x === 'string' && k.length <= 32 && x.length <= 32) out[k] = x
  return out
}

// ───────── 读写 ─────────

const enc = new TextEncoder()
const bytes = (v: unknown): number => enc.encode(JSON.stringify(v)).length

/** 网页这一侧的 webPrefs（codec.webSetting 用）：st 那几项 + 登记的块；超过 8 KB 按 DROP_ORDER 挤掉几块 */
export function buildWebPrefs(s: WebPrefsState): Record<string, Json> {
  const o: Record<string, Json> = {}
  if (s.theme) o.theme = s.theme
  if (s.skin) o.skin = s.skin
  // 和手机上限不同的几项整份留着：周期条按周期顺序、副图按用户排的先后
  o.pins = INTERVALS.filter(iv => s.pinned.includes(iv))
  o.subs = [...s.ind.subs]
  o.mains = [...(s.ind.mains ?? [])]
  o.ind = { ichi: s.ind.ichi === true, vpvr: s.ind.vpvr === true, keys: s.ind.keys === true }
  o.params = (s.params ? JSON.parse(JSON.stringify(s.params)) : {}) as Json
  if (s.vpvrMode) o.vpvrMode = s.vpvrMode
  if ([s.linkCross, s.linkSymbol, s.linkIv, s.linkTime].some(x => x !== undefined)) o.link = { cross: s.linkCross !== false, symbol: s.linkSymbol === true, iv: s.linkIv === true, time: s.linkTime === true }
  if (s.slots) o.slots = { ladder: s.slots.ladder, drawer: s.slots.drawer, widgets: [...s.slots.widgets] }
  if (s.panel !== undefined) o.panel = s.panel
  if (s.lastPanel !== undefined) o.lastPanel = s.lastPanel
  if (s.watchTab) o.watchTab = s.watchTab
  if (s.alertScope) o.alertScope = s.alertScope
  if (s.meSection) o.meSection = s.meSection
  if (s.drawLocked !== undefined) o.drawLocked = s.drawLocked === true
  if (s.drawStyles) o.drawStyles = JSON.parse(JSON.stringify(s.drawStyles)) as Json
  if (s.toolLast) o.toolLast = { ...s.toolLast }
  for (const [k, p] of parts) { try { o[k] = p.read() } catch { /* 这一块读坏了：这次不带它 */ } }
  for (const k of DROP_ORDER) { if (bytes(o) <= WEB_PREFS_MAX_BYTES) break; delete o[k] }
  return o
}

/** 云端那份 webPrefs 的规范形（对象才认；各键在 applyWebPrefs 里逐项验） */
export function cleanWebPrefs(v: unknown): Record<string, Json> | null {
  return isObj(v) && bytes(v) <= WEB_PREFS_MAX_BYTES ? v as Record<string, Json> : null
}

/** 把云端那份装进状态（原地改）与登记的块。缺的键、形状不对的键不动本机那一项 */
export function applyWebPrefs(s: WebPrefsState, raw: unknown): void {
  const v = cleanWebPrefs(raw)
  if (!v) return
  if (v.theme === 'light' || v.theme === 'dark') s.theme = v.theme
  if (v.skin === 'sage' || v.skin === 'terra' || v.skin === 'classic') s.skin = v.skin
  const pins = strList(v.pins, x => INTERVALS.includes(x), INTERVALS.length)
  if (pins?.length) s.pinned = pins
  const subs = strList(v.subs, x => SUB_IDS.has(x), MAX_SUBS)
  if (subs) s.ind.subs = subs as IndState['subs']
  const mains = strList(v.mains, isMoreMain, 64)
  if (mains) { if (mains.length) s.ind.mains = mains; else delete s.ind.mains }
  // 关着的可选叠加层不留 false 键（和本机关掉时同一个样子，指纹不抖）
  if (isObj(v.ind)) for (const k of ['ichi', 'vpvr', 'keys'] as const) { const b = bool(v.ind[k]); if (b === true) s.ind[k] = true; else if (b === false) delete s.ind[k] }
  if (isObj(v.params)) s.params = cleanParamsMap(v.params)
  if (v.vpvrMode === 'split' || v.vpvrMode === 'delta' || v.vpvrMode === 'total') s.vpvrMode = v.vpvrMode
  if (isObj(v.link)) {
    const l = v.link
    if (bool(l.cross) !== undefined) s.linkCross = l.cross as boolean
    if (bool(l.symbol) !== undefined) s.linkSymbol = l.symbol as boolean
    if (bool(l.iv) !== undefined) s.linkIv = l.iv as boolean
    if (bool(l.time) !== undefined) s.linkTime = l.time as boolean
  }
  if (isObj(v.slots)) {
    const w = strList(v.slots.widgets, x => WIDGETS.includes(x as WidgetId), WIDGETS.length) as WidgetId[] | undefined
    const cur: Slots = s.slots ?? { ladder: false, drawer: false, widgets: ['watch', 'detail'] }
    s.slots = { ladder: bool(v.slots.ladder) ?? cur.ladder, drawer: bool(v.slots.drawer) ?? cur.drawer, widgets: w?.length ? w : cur.widgets }
  }
  if (v.panel === null || PANELS.includes(v.panel as PanelId)) s.panel = v.panel as PanelId | null
  if (v.lastPanel === null || PANELS.includes(v.lastPanel as PanelId)) s.lastPanel = v.lastPanel as PanelId | null
  if (KINDS.includes(v.watchTab as Kind)) s.watchTab = v.watchTab as Kind
  if (v.alertScope === 'symbol' || v.alertScope === 'all') s.alertScope = v.alertScope
  if (typeof v.meSection === 'string' && /^[a-z]{1,16}$/.test(v.meSection)) s.meSection = v.meSection
  if (bool(v.drawLocked) !== undefined) s.drawLocked = v.drawLocked as boolean
  const ds = styleMap(v.drawStyles); if (ds) s.drawStyles = ds
  const tl = strMap(v.toolLast); if (tl) s.toolLast = tl
  writing = true
  try { for (const [k, p] of parts) if (k in v) { try { p.write(v[k]) } catch (e) { console.error(e) } } } finally { writing = false }
}

/** 换了人（上一次在这台电脑同步的是另一个账号）：登记的块回出厂 */
export function resetWebPrefParts(): void {
  writing = true
  try { for (const p of parts.values()) { try { p.write(undefined) } catch (e) { console.error(e) } } } finally { writing = false }
}

/** 测试用 */
export function clearWebPrefParts(): void { parts.clear(); listeners.clear() }
