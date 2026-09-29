/* Hkline Web · 本机状态（localStorage「hkline-web-v1」）
 *
 * 沿用原型的 st：一个普通对象，改完调 save()；想知道「什么变了」的地方用 subscribe。
 * 布局槽位（深度梯子列、底部抽屉、侧栏小部件顺序）也在这里，后续跟账号同步。
 */
import type { Drawing } from '../chart/chart'
import type { IndParams, SubId } from '../chart/calc'
import { DEFAULT_WATCH, type Kind } from '../market/symbols'

export type Theme = 'light' | 'dark'
export type Skin = 'sage' | 'terra' | 'classic'
export type UpDown = 'red-up' | 'green-up'
export type Layout = '1' | '2' | '2v' | '4'
export type PanelId = 'watch' | 'alerts' | 'flow' | 'notes' | 'trades'
export type PageId = 'chart' | 'sectors' | 'review' | 'me'
/** 侧栏「自选」视图里按顺序堆叠的小部件；盘口 / 成交 / 大单 是下一阶段的 */
export type WidgetId = 'watch' | 'detail' | 'book' | 'tape' | 'walls' | 'alerts'

export interface CellCfg { symbol: string; iv: string }
export interface Alert {
  id: string; symbol: string; kind: 'price' | 'fr' | 'oi'; created: number
  price?: number; dir?: number; value?: number; op?: 'gt' | 'lt'; webhook?: string | null
}
export interface Note { id: string; symbol: string; iv: string; t: number; p: number; text: string }
export interface IndState { ma: boolean; ema: boolean; boll: boolean; vol: boolean; subs: SubId[] }

export interface Slots {
  /** 价格轴与侧栏之间的深度梯子列：开 240 / 关 0 */
  ladder: boolean
  /** 图表区下方的底部抽屉：开 280 / 关 0 */
  drawer: boolean
  /** 侧栏小部件的堆叠顺序 */
  widgets: WidgetId[]
}

export interface State {
  theme: Theme; skin: Skin; updown: UpDown
  route: 'direct' | 'gateway'
  layout: Layout; cells: CellCfg[]; active: number
  pinned: string[]
  panel: PanelId | null; watchTab: Kind; watch: Record<Kind, string[]>
  ind: IndState; params: Record<string, IndParams> | null
  drawings: Record<string, Drawing[]>; alerts: Alert[]; notes: Note[]
  magnet: boolean; drawHidden: boolean; drawLocked: boolean; drawColor: string
  alertScope: 'symbol' | 'all'
  meSection: string
  slots: Slots
  /** 以下不落盘 */
  page: PageId
  stale: boolean
}

export const KEY = 'hkline-web-v1'
const TRANSIENT: (keyof State)[] = ['page', 'stale']

function defaults(): State {
  return {
    theme: 'light', skin: 'sage', updown: 'red-up', route: 'direct',
    layout: '1', cells: [{ symbol: 'BTCUSDT', iv: '1h' }], active: 0,
    pinned: ['1m', '5m', '15m', '1h', '4h', '1d', '1w'],
    panel: 'watch', watchTab: 'crypto', watch: structuredClone(DEFAULT_WATCH),
    ind: { ma: true, ema: false, boll: false, vol: true, subs: ['macd', 'rsi'] }, params: null,
    drawings: {}, alerts: [], notes: [],
    magnet: false, drawHidden: false, drawLocked: false, drawColor: '#2962FF',
    alertScope: 'symbol', meSection: 'look',
    slots: { ladder: false, drawer: false, widgets: ['watch', 'detail'] },
    page: 'chart', stale: false,
  }
}

function load(): Partial<State> {
  try { return JSON.parse(localStorage.getItem(KEY) || '{}') || {} } catch { return {} }
}

/** 读盘并补齐：老版本存下来的缺字段一律回默认，字段形状不对的丢掉 */
export function hydrate(saved: Partial<State>): State {
  const d = defaults()
  const s = { ...d, ...saved } as State
  s.slots = { ...d.slots, ...(saved.slots || {}) }
  if (!Array.isArray(s.slots.widgets) || !s.slots.widgets.length) s.slots.widgets = d.slots.widgets
  s.watch = { ...d.watch, ...(saved.watch || {}) }
  s.ind = { ...d.ind, ...(saved.ind || {}) }
  if (!Array.isArray(s.ind.subs)) s.ind.subs = d.ind.subs
  s.ind.subs = s.ind.subs.slice(0, 4)
  if (!Array.isArray(s.cells) || !s.cells.length) s.cells = d.cells
  if (!['1', '2', '2v', '4'].includes(s.layout)) s.layout = '1'
  if (!['sage', 'terra', 'classic'].includes(s.skin)) s.skin = 'sage'
  if (s.theme !== 'dark') s.theme = 'light'
  if (s.updown !== 'green-up') s.updown = 'red-up'
  if (s.route !== 'gateway') s.route = 'direct'
  if (!Array.isArray(s.alerts)) s.alerts = []
  s.alerts = s.alerts.filter(a => a.kind === 'price' || a.kind === 'fr' || a.kind === 'oi')
  if (!Array.isArray(s.notes)) s.notes = []
  if (!s.drawings || typeof s.drawings !== 'object') s.drawings = {}
  s.page = 'chart'; s.stale = false
  return s
}

export const st: State = hydrate(load())

const subs = new Set<(s: State) => void>()
export function subscribe(fn: (s: State) => void): () => void { subs.add(fn); return () => { subs.delete(fn) } }

export function save(): void {
  const out: Record<string, unknown> = {}
  for (const [k, v] of Object.entries(st)) if (!TRANSIENT.includes(k as keyof State)) out[k] = v
  try { localStorage.setItem(KEY, JSON.stringify(out)) } catch { /* 存储满了就不存 */ }
  subs.forEach(fn => fn(st))
}

export function resetAll(): void { localStorage.removeItem(KEY) }
