/* Hkline Web · 本机状态（localStorage「hkline-web-v1」）
 *
 * 沿用原型的 st：一个普通对象，改完调 save()；想知道「什么变了」的地方用 subscribe。
 * 布局槽位（深度梯子列、底部抽屉、侧栏小部件顺序）也在这里，后续跟账号同步。
 */
import type { Drawing } from '../chart/chart'
import { MAX_SUBS, type IndParams, type SubId } from '../chart/calc'
import { migrateAlert, type Alert } from '../alerts/shape'
import type { VpvrMode } from '../chart/overlays'
import type { NoteDraft } from '../notes/draft'
import { DEFAULT_WATCH, type Kind } from '../market/symbols'
import { normalizeOverride, MAX_OVERRIDES, type Override } from '../orderflow/settings'

export type Theme = 'light' | 'dark'
export type Skin = 'sage' | 'terra' | 'classic'
export type UpDown = 'red-up' | 'green-up'
export type Layout = '1' | '2' | '2v' | '4' | '6' | '8'
export const LAYOUTS: Layout[] = ['1', '2', '2v', '4', '6', '8']
/** 每种布局几格 */
export const LAYOUT_N: Record<Layout, number> = { '1': 1, '2': 2, '2v': 2, '4': 4, '6': 6, '8': 8 }
/** 当前格子落在布局的格数以内（地址栏把八图改成一图时，参数要落到看得见的那一格上） */
export function clampActive(s: Pick<State, 'active' | 'layout'>): void {
  const n = LAYOUT_N[s.layout] || 1
  s.active = Number.isInteger(s.active) ? Math.min(Math.max(0, s.active), n - 1) : 0
}
export type PanelId = 'watch' | 'alerts' | 'flow' | 'notes' | 'trades'
export type PageId = 'chart' | 'sectors' | 'review' | 'me'
/** 侧栏「自选」视图里按顺序堆叠的小部件（自选、品种详情、盘口、逐笔成交、大单、提醒），用户可调顺序与开合 */
export type WidgetId = 'watch' | 'detail' | 'book' | 'tape' | 'walls' | 'alerts'

export interface CellCfg { symbol: string; iv: string }
/** 提醒：形状和手机端同步的 alerts 对象一致（19 个字段），见 alerts/shape.ts */
export type { Alert }
export interface Note {
  id: string; symbol: string; iv: string; t: number; p: number; text: string
  /** 发给服务端的观点记录（2026-09-29 起）；更早只存本机的笔记没有这一项，也不上传 */
  draft?: NoteDraft
  /** pending 等上传（没登录、断网时先留在本机）· synced 已在服务端 · failed 服务端拒收（原因在 err） */
  sync?: 'pending' | 'synced' | 'failed'
  err?: string
  /** 这一笔的截图：pending 还没传（图在 notes/shots 的本机存储里）· done 传上了 · none 没有图 */
  shot?: 'pending' | 'done' | 'none'
}
export interface IndState {
  ma: boolean; ema: boolean; boll: boolean; vol: boolean; subs: SubId[]
  /** 主图第二批叠加：VWAP、超级趋势、一目均衡表、成交量分布 */
  vwap?: boolean; st?: boolean; ichi?: boolean; vpvr?: boolean
}

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
  /** 成交量分布的看法：买卖分开 / 净差 / 合计 */
  vpvrMode: VpvrMode
  /** 多图时十字线跨图同步、换品种时所有图一起换 */
  linkCross: boolean
  linkSymbol: boolean
  /** 自定义分钟周期（如 45m），「更多」里输入后记下来 */
  customIvs: string[]
  /** 指标「主力订单流」开没开（图上大单带、抽屉） */
  orderFlow: boolean
  /** 主力订单流门槛 / 步长里用户改过的项，按 base（BTC、PEPE…）存；随账号同步 */
  orderFlowOverrides: Record<string, Override>
  /** 以下不落盘 */
  page: PageId
  stale: boolean
  /** 当前登录的账号（account/session.ts 维护，令牌另存）；未登录为 null。别的页面读 accessToken 调接口 */
  account: { username: string; userId: string; accessToken: string } | null
}

export const KEY = 'hkline-web-v1'
const TRANSIENT: (keyof State)[] = ['page', 'stale', 'account']

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
    vpvrMode: 'split', linkCross: true, linkSymbol: false, customIvs: [],
    orderFlow: false, orderFlowOverrides: {},
    page: 'chart', stale: false, account: null,
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
  s.ind.subs = s.ind.subs.slice(0, MAX_SUBS)
  if (!Array.isArray(s.cells) || !s.cells.length) s.cells = d.cells
  if (!LAYOUTS.includes(s.layout)) s.layout = '1'
  clampActive(s)
  if (!['split', 'delta', 'total'].includes(s.vpvrMode)) s.vpvrMode = 'split'
  s.linkCross = s.linkCross !== false; s.linkSymbol = s.linkSymbol === true
  if (!Array.isArray(s.customIvs)) s.customIvs = []
  s.customIvs = s.customIvs.filter(x => typeof x === 'string' && /^\d+m$/.test(x)).slice(0, 12)
  if (!['sage', 'terra', 'classic'].includes(s.skin)) s.skin = 'sage'
  if (s.theme !== 'dark') s.theme = 'light'
  if (s.updown !== 'green-up') s.updown = 'red-up'
  if (s.route !== 'gateway') s.route = 'direct'
  if (!Array.isArray(s.alerts)) s.alerts = []
  // 第一阶段的老形状（price / fr / oi）就地补成同步形状；触发过的不留
  s.alerts = (s.alerts as unknown[]).map(migrateAlert).filter((a): a is Alert => !!a && a.status !== 'fired')
  if (!Array.isArray(s.notes)) s.notes = []
  s.notes = s.notes.filter(n => n && typeof n.id === 'string' && typeof n.symbol === 'string')
  if (!s.drawings || typeof s.drawings !== 'object') s.drawings = {}
  s.orderFlow = s.orderFlow === true
  const ofo: Record<string, Override> = {}
  if (s.orderFlowOverrides && typeof s.orderFlowOverrides === 'object') {
    for (const [k, v] of Object.entries(s.orderFlowOverrides).slice(0, MAX_OVERRIDES)) { const n = normalizeOverride(v); if (n && /^[A-Z0-9]{1,20}$/.test(k)) ofo[k] = n }
  }
  s.orderFlowOverrides = ofo
  s.page = 'chart'; s.stale = false; s.account = null
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
