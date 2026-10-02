/* Hkline Web · 本机状态（localStorage「hkline-web-v1」）
 *
 * 沿用原型的 st：一个普通对象，改完调 save()；想知道「什么变了」的地方用 subscribe。
 * 布局槽位（深度梯子列、底部抽屉、侧栏小部件顺序）也在这里，后续跟账号同步。
 */
import type { Drawing } from '../chart/chart'
import { MAX_SUBS, CATALOG, type IndParams, type IndicatorId, type SubId } from '../chart/calc'
import { migrateAlert, type Alert } from '../alerts/shape'
import type { VpvrMode } from '../chart/overlays'
import type { NoteDraft } from '../notes/draft'
import { DEFAULT_WATCH, INTERVALS, type Kind } from '../market/symbols'
import { IV_MS } from '../util/format'
import { normalizeOverride, MAX_OVERRIDES, type Override } from '../orderflow/settings'

export type Theme = 'light' | 'dark'
export type Skin = 'sage' | 'terra' | 'classic'
export type UpDown = 'red-up' | 'green-up'
export type Layout = '1' | '2' | '2v' | '3' | '4' | '6' | '8' | '9' | '12' | '16'
/** 布局清单（TradingView 那种多窗口，最多 16 格） */
export const LAYOUTS: Layout[] = ['1', '2', '2v', '3', '4', '6', '8', '9', '12', '16']
/** 每种布局几格 */
export const LAYOUT_N: Record<Layout, number> = { '1': 1, '2': 2, '2v': 2, '3': 3, '4': 4, '6': 6, '8': 8, '9': 9, '12': 12, '16': 16 }
/** 最多几格 */
export const MAX_CELLS = 16
/**
 * 每种布局的网格：几列几行；areas 只有「左一右二」要（第 0 格占左边整列，右边两格上下分）。
 * 列宽 / 行高的比例用户能拖，按布局分别记在本机（app/sizes.ts）。
 */
export interface GridSpec { cols: number; rows: number; areas?: string[][] }
export const GRID: Record<Layout, GridSpec> = {
  '1': { cols: 1, rows: 1 }, '2': { cols: 2, rows: 1 }, '2v': { cols: 1, rows: 2 },
  '3': { cols: 2, rows: 2, areas: [['a', 'b'], ['a', 'c']] },
  '4': { cols: 2, rows: 2 }, '6': { cols: 3, rows: 2 }, '8': { cols: 4, rows: 2 },
  '9': { cols: 3, rows: 3 }, '12': { cols: 4, rows: 3 }, '16': { cols: 4, rows: 4 },
}
/** 当前格子落在布局的格数以内（地址栏把八图改成一图时，参数要落到看得见的那一格上） */
export function clampActive(s: Pick<State, 'active' | 'layout'>): void {
  const n = LAYOUT_N[s.layout] || 1
  s.active = Number.isInteger(s.active) ? Math.min(Math.max(0, s.active), n - 1) : 0
}
/** 多图时补齐格子的品种：先 BTC 与几只主流，再往后是热门山寨与美股、金银（16 格各不相同） */
export const FILL_SYMBOLS = ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'XAUUSDT', 'BNBUSDT', 'XRPUSDT', 'DOGEUSDT', 'NVDAUSDT', 'ADAUSDT', 'LINKUSDT', 'AVAXUSDT', 'SUIUSDT', 'XAGUSDT', 'TSLAUSDT', 'LTCUSDT', 'TRXUSDT']
/** 格子配置补到 n 格：缺的（含稀疏数组里的洞）按清单补一只还没用过的品种，周期跟第 0 格 */
export function ensureCells(s: Pick<State, 'cells'>, n: number): void {
  const iv = s.cells[0]?.iv || '1h'
  for (let i = 0; i < n; i++) {
    const c = s.cells[i]
    if (c && typeof c.symbol === 'string' && typeof c.iv === 'string') continue
    const used = new Set(s.cells.filter(Boolean).map(x => x.symbol))
    s.cells[i] = { symbol: FILL_SYMBOLS.find(k => !used.has(k)) || 'BTCUSDT', iv }
  }
}
export type PanelId = 'watch' | 'alerts' | 'flow' | 'notes' | 'trades'
export type PageId = 'chart' | 'sectors' | 'review' | 'me'
/** 侧栏「自选」视图里按顺序堆叠的小部件（自选、品种详情、盘口、逐笔成交、大单、提醒、24 小时流动性、24 小时成交），用户可调顺序与开合 */
export type WidgetId = 'watch' | 'detail' | 'book' | 'tape' | 'walls' | 'alerts' | 'liq' | 'vol'

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
  /** 关键价位（昨高低、上周高低、今开、昨控与价值区） */
  keys?: boolean
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
  /** 用户亲手选过线路没有：没选过的，出厂值改了就跟着改（2026-10-02 出厂从直连改成网关） */
  routePicked: boolean
  layout: Layout; cells: CellCfg[]; active: number
  pinned: string[]
  panel: PanelId | null; watchTab: Kind; watch: Record<Kind, string[]>
  ind: IndState; params: Record<string, IndParams> | null
  drawings: Record<string, Drawing[]>; alerts: Alert[]; notes: Note[]
  magnet: boolean; drawHidden: boolean; drawLocked: boolean; drawColor: string
  /** 画线：同族工具上次改过的样式（族 → 颜色 / 粗细 / 线型）、最近用过的颜色（新的在前）、
   *  工具栏每组上次用的那把、侧栏上一次开的是哪块（⌥⇧W 收起再打开） */
  drawStyles: Record<string, DrawStyle>; recentColors: string[]; toolLast: Record<string, string>; lastPanel: PanelId | null
  alertScope: 'symbol' | 'all'
  meSection: string
  slots: Slots
  /** 成交量分布的看法：买卖分开 / 净差 / 合计 */
  vpvrMode: VpvrMode
  /** 多图时十字线跨图同步、换品种时所有图一起换 */
  linkCross: boolean
  linkSymbol: boolean
  /** 多图时换周期所有图一起换；平移缩放时间轴所有图对齐同一段时间 */
  linkIv: boolean
  linkTime: boolean
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

export interface DrawStyle { color?: string; width?: number; dash?: 'dashed' | 'dotted' }

export const KEY = 'hkline-web-v1'
const TRANSIENT: (keyof State)[] = ['page', 'stale', 'account']

function defaults(): State {
  return {
    theme: 'light', skin: 'sage', updown: 'red-up', route: 'gateway', routePicked: false,
    layout: '1', cells: [{ symbol: 'BTCUSDT', iv: '1h' }], active: 0,
    pinned: ['1m', '5m', '15m', '1h', '4h', '1d', '1w'],
    panel: 'watch', watchTab: 'crypto', watch: structuredClone(DEFAULT_WATCH),
    ind: { ma: true, ema: false, boll: false, vol: true, subs: ['macd', 'rsi'] }, params: null,
    drawings: {}, alerts: [], notes: [],
    magnet: false, drawHidden: false, drawLocked: false, drawColor: '#2962FF',
    drawStyles: {}, recentColors: [], toolLast: {}, lastPanel: 'watch',
    alertScope: 'symbol', meSection: 'look',
    slots: { ladder: false, drawer: false, widgets: ['watch', 'detail'] },
    vpvrMode: 'split', linkCross: true, linkSymbol: false, linkIv: false, linkTime: false, customIvs: [],
    orderFlow: false, orderFlowOverrides: {},
    page: 'chart', stale: false, account: null,
  }
}

/** `corrupt`：盘上有东西但解析不了（被截断、被别的程序写坏）——和「从没存过」分开 */
function load(): { saved: Partial<State>; corrupt: boolean } {
  let text: string | null = null
  try { text = localStorage.getItem(KEY) } catch { return { saved: {}, corrupt: false } }
  if (!text) return { saved: {}, corrupt: false }
  try {
    const v: unknown = JSON.parse(text)
    return v && typeof v === 'object' && !Array.isArray(v) ? { saved: v as Partial<State>, corrupt: false } : { saved: {}, corrupt: true }
  } catch { return { saved: {}, corrupt: true } }
}

// ───────── 画线存档读坏了（同步自检） ─────────
// 本机画线读出来是「空」有两种：用户真删光了，或者存档坏了被丢掉。后一种绝不能当成删除推上云端，
// 所以读坏时落一个标记，同步层看到它就只补不删、先把云端那份并回来，并回来之后才清掉标记。
export const DRAW_SUSPECT_KEY = 'hkline-web-drawings-suspect'
export function drawingsSuspect(): boolean { try { return localStorage.getItem(DRAW_SUSPECT_KEY) === '1' } catch { return false } }
export function markDrawingsSuspect(): void { try { localStorage.setItem(DRAW_SUSPECT_KEY, '1') } catch { /* 存不下：本轮内存里照样按坏处理不了，下次读盘还会再判 */ } }
export function clearDrawingsSuspect(): void { try { localStorage.removeItem(DRAW_SUSPECT_KEY) } catch { /* 无 */ } }

const finite = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v)
/** 画线那块整理成「代号 → 画线数组」；形状不对的丢掉并报 damaged */
export function sanitizeDrawings(raw: unknown): { drawings: Record<string, Drawing[]>; damaged: boolean } {
  const out: Record<string, Drawing[]> = {}
  if (raw == null) return { drawings: out, damaged: false }
  if (typeof raw !== 'object' || Array.isArray(raw)) return { drawings: out, damaged: true }
  let damaged = false
  for (const [sym, list] of Object.entries(raw as Record<string, unknown>)) {
    if (!Array.isArray(list)) { damaged = true; continue }
    const ok = list.filter((d): d is Drawing => {
      const x = d as Partial<Drawing> | null
      return !!x && typeof x.id === 'string' && typeof x.type === 'string' && Array.isArray(x.pts) && x.pts.length > 0 && x.pts.every(p => p && finite(p.t) && finite(p.p))
    })
    if (ok.length !== list.length) damaged = true
    out[sym] = ok
  }
  return { drawings: out, damaged }
}

// ───────── 读盘时逐项验形状 ─────────
// 2026-09-29 压测：存档里格子的周期是「7x」「」时原样拿去要 K 线，币安回 400、那一格永远空着；
// pinned 是字符串时周期条按字符拆；watch 某类不是数组、ind.subs 里有不认识的副图、params 里 fast 是字符串时
// 各自在渲染里出错或算出 NaN。本机存档会被老版本、别的标签页的老代码、手改写坏，所以每一项都要验。
const isObj = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v)
const rec = (v: unknown): Record<string, unknown> => (isObj(v) ? v : {})
const PANELS: PanelId[] = ['watch', 'alerts', 'flow', 'notes', 'trades']
const WIDGETS: WidgetId[] = ['watch', 'detail', 'book', 'tape', 'walls', 'alerts', 'liq', 'vol']
const KINDS: Kind[] = ['crypto', 'us', 'com']
const HEX = /^#[0-9A-Fa-f]{6}$/
/** 周期键认不认：原生、秒级（1s / 5s / 15s）、自定义分钟（2–1440 分且不和原生重复） */
export function validIv(iv: unknown): iv is string {
  if (typeof iv !== 'string') return false
  if (INTERVALS.includes(iv) || iv === '1s' || iv === '5s' || iv === '15s') return true
  const m = /^(\d+)m$/.exec(iv)
  if (!m) return false
  const n = +m[1]
  return n >= 2 && n <= 1440 && !INTERVALS.some(k => IV_MS[k] === n * 60e3)
}
/** 本机存档里的品种代号：字母数字（1000PEPEUSDT、XAUUSDT），也有中文名的（币安人生USDT、龙虾USDT——
 *  2026-09-30 regress 60 只自选少了一只，就是一开始只认 ASCII 把它丢了），留一点余量给点号与横线。
 *  这只管「形状像不像代号」；能不能上云是 sync/codec.ts 的另一条规则（服务端只收 ASCII，中文名的只留本机） */
export const validSymbol = (v: unknown): v is string => typeof v === 'string' && /^[\p{L}\p{N}._-]{2,40}$/u.test(v)
const SUB_IDS = new Set(Object.entries(CATALOG).filter(([, c]) => c.place === 'sub').map(([k]) => k))
/** 指标参数：只留认识的指标、认识的数值键；缺的项照目录默认补上（各指标算法按整份参数取值） */
function cleanParams(raw: unknown): Record<string, IndParams> | null {
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
    out[id] = one as IndParams
  }
  return Object.keys(out).length ? out : null
}
const strMap = (v: unknown): Record<string, string> => {
  const out: Record<string, string> = {}
  if (isObj(v)) for (const [k, x] of Object.entries(v)) if (typeof x === 'string') out[k] = x
  return out
}

/** 读盘并补齐：老版本存下来的缺字段一律回默认，字段形状不对的丢掉 */
export function hydrate(saved: Partial<State>): State {
  const d = defaults()
  if (!isObj(saved)) saved = {}
  const s = { ...d, ...saved } as State
  const slots = rec(saved.slots)
  s.slots = {
    ladder: slots.ladder === true, drawer: slots.drawer === true,
    widgets: Array.isArray(slots.widgets) ? [...new Set((slots.widgets as unknown[]).filter((w): w is WidgetId => WIDGETS.includes(w as WidgetId)))] : [],
  }
  if (!s.slots.widgets.length) s.slots.widgets = d.slots.widgets
  const watch = rec(saved.watch)
  s.watch = Object.fromEntries(KINDS.map(k => {
    const list = watch[k]
    return [k, Array.isArray(list) ? [...new Set((list as unknown[]).filter(validSymbol))] : d.watch[k]]
  })) as Record<Kind, string[]>
  const ind = rec(saved.ind)
  s.ind = { ...d.ind }
  for (const k of ['ma', 'ema', 'boll', 'vol', 'vwap', 'st', 'ichi', 'vpvr', 'keys'] as const) if (typeof ind[k] === 'boolean') s.ind[k] = ind[k] as boolean
  if (Array.isArray(ind.subs)) s.ind.subs = [...new Set((ind.subs as unknown[]).filter((x): x is SubId => typeof x === 'string' && SUB_IDS.has(x)))]
  s.ind.subs = s.ind.subs.slice(0, MAX_SUBS)
  s.params = cleanParams(saved.params)
  s.pinned = Array.isArray(saved.pinned) ? [...new Set(saved.pinned.filter(x => typeof x === 'string' && INTERVALS.includes(x)))] : d.pinned
  if (!s.pinned.length) s.pinned = d.pinned
  s.panel = s.panel === null ? null : PANELS.includes(s.panel as PanelId) ? s.panel : d.panel
  s.lastPanel = PANELS.includes(s.lastPanel as PanelId) ? s.lastPanel : d.lastPanel
  if (!KINDS.includes(s.watchTab)) s.watchTab = d.watchTab
  s.customIvs = Array.isArray(s.customIvs) ? [...new Set(s.customIvs.filter(x => typeof x === 'string' && /^\d+m$/.test(x) && validIv(x)))].slice(0, 12) : []
  // 格子：坏项与洞交给 ensureCells 补；认不出的周期回第 0 格的（第 0 格自己坏了回 1 小时）；自定义分钟启动时照格子注册
  const ivOk = (iv: unknown): iv is string => validIv(iv)
  const rawCells: unknown[] = Array.isArray(saved.cells) ? saved.cells.slice(0, MAX_CELLS) : []
  const iv0 = isObj(rawCells[0]) && ivOk(rawCells[0].iv) ? rawCells[0].iv : d.cells[0].iv
  s.cells = rawCells.map(c => (isObj(c) && validSymbol(c.symbol) ? { symbol: c.symbol, iv: ivOk(c.iv) ? c.iv : iv0 } : undefined)) as CellCfg[]
  if (!s.cells.length || !s.cells[0]) s.cells[0] = { symbol: d.cells[0].symbol, iv: iv0 }
  ensureCells(s, s.cells.length)
  if (typeof s.layout === 'number') s.layout = String(s.layout) as Layout
  if (!LAYOUTS.includes(s.layout)) s.layout = '1'
  clampActive(s)
  for (const k of ['magnet', 'drawHidden', 'drawLocked'] as const) s[k] = s[k] === true
  if (typeof s.drawColor !== 'string' || !HEX.test(s.drawColor)) s.drawColor = d.drawColor
  if (s.alertScope !== 'all') s.alertScope = 'symbol'
  if (typeof s.meSection !== 'string') s.meSection = d.meSection
  if (!['split', 'delta', 'total'].includes(s.vpvrMode)) s.vpvrMode = 'split'
  s.linkCross = s.linkCross !== false; s.linkSymbol = s.linkSymbol === true; s.linkIv = s.linkIv === true; s.linkTime = s.linkTime === true
  if (!['sage', 'terra', 'classic'].includes(s.skin)) s.skin = 'sage'
  if (s.theme !== 'dark') s.theme = 'light'
  if (s.updown !== 'green-up') s.updown = 'red-up'
  s.routePicked = saved.routePicked === true
  if (!s.routePicked) s.route = d.route
  else if (s.route !== 'gateway') s.route = 'direct'
  if (!Array.isArray(s.alerts)) s.alerts = []
  // 第一阶段的老形状（price / fr / oi）就地补成同步形状；触发过的不留
  s.alerts = (s.alerts as unknown[]).map(migrateAlert).filter((a): a is Alert => !!a && a.status !== 'fired')
  if (!Array.isArray(s.notes)) s.notes = []
  s.notes = s.notes.filter(n => n && typeof n.id === 'string' && typeof n.symbol === 'string')
  s.drawings = sanitizeDrawings(saved.drawings).drawings
  const ds: Record<string, DrawStyle> = {}
  if (isObj(s.drawStyles)) for (const [k, v] of Object.entries(s.drawStyles as unknown as Record<string, unknown>)) {
    if (!isObj(v)) continue
    const one: DrawStyle = {}
    if (typeof v.color === 'string' && HEX.test(v.color)) one.color = v.color
    if (typeof v.width === 'number' && v.width >= 1 && v.width <= 8) one.width = v.width
    if (v.dash === 'dashed' || v.dash === 'dotted') one.dash = v.dash
    ds[k] = one
  }
  s.drawStyles = ds
  s.recentColors = Array.isArray(s.recentColors) ? s.recentColors.filter(c => typeof c === 'string' && /^#[0-9A-Fa-f]{6}$/.test(c)).slice(0, 3) : []
  s.toolLast = strMap(s.toolLast)
  s.orderFlow = s.orderFlow === true
  const ofo: Record<string, Override> = {}
  if (s.orderFlowOverrides && typeof s.orderFlowOverrides === 'object') {
    for (const [k, v] of Object.entries(s.orderFlowOverrides).slice(0, MAX_OVERRIDES)) { const n = normalizeOverride(v); if (n && /^[A-Z0-9]{1,20}$/.test(k)) ofo[k] = n }
  }
  s.orderFlowOverrides = ofo
  s.page = 'chart'; s.stale = false; s.account = null
  return s
}

const loaded = load()
export const st: State = hydrate(loaded.saved)
if (loaded.corrupt || sanitizeDrawings(loaded.saved.drawings).damaged) markDrawingsSuspect()

const subs = new Set<(s: State) => void>()
export function subscribe(fn: (s: State) => void): () => void { subs.add(fn); return () => { subs.delete(fn) } }

/* 同一浏览器开了两个标签页：每页内存里各有一份 st，谁 save 谁把整份写进同一个键。
 * 以前后台那页一存（同步拉到东西、提醒响了、切了个周期）就把另一页刚改的主题、画线、自选整份盖回旧的。
 * 规矩：人最近一次动过的那页（按键 / 按下指针）内存为准。每次写盘顺带记下「写的这页最近一次被人动的时刻」；
 *   · 别的页写了，而它比我更近被人动过：我这份旧了，此后不再写盘；人一回到这页（获得焦点、变可见、
 *     或者直接在这页上点 / 按键）就整页重载，读新的；
 *   · 别的页写了，但我才是更近被人动过的（它是后台自动存的旧内存）：立刻用我这份写回去。
 * 不靠 document.hasFocus()：并排两个窗口、无头浏览器里它都不可靠。 */
const WRITER_KEY = KEY + '-writer'
let stale = false
let touchedAt = 0
export const tabGuard = {
  /** 别的标签页写了 KEY；theirs = 它写时记下的「最近被人动的时刻」 */
  onForeignWrite(theirs: number): 'stale' | 'repair' {
    if (stale || theirs >= touchedAt) { stale = true; return 'stale' }
    write(); return 'repair'
  },
  touch(now = Date.now()): void { touchedAt = now },
  get stale(): boolean { return stale },
  reset(): void { stale = false; touchedAt = 0 },
}
if (typeof window !== 'undefined' && typeof document !== 'undefined') {
  window.addEventListener('storage', e => {
    if (e.key !== KEY && e.key !== null) return
    let theirs = Infinity
    try { theirs = Number(JSON.parse(localStorage.getItem(WRITER_KEY) || '{}').at) || 0 } catch { /* 读不到按对方更新算 */ }
    tabGuard.onForeignWrite(theirs)
  })
  const back = (): void => { if (stale) location.reload() }
  // 人在这页上动手：旧了就先重载（这一下不生效，免得改在旧内存上又被丢掉），没旧就记下时刻
  const hand = (e: Event): void => {
    if (stale) { e.preventDefault(); e.stopImmediatePropagation(); location.reload(); return }
    tabGuard.touch()
  }
  window.addEventListener('pointerdown', hand, true)
  window.addEventListener('keydown', hand, true)
  window.addEventListener('focus', back)
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') back() })
}

function write(): void {
  const out: Record<string, unknown> = {}
  for (const [k, v] of Object.entries(st)) if (!TRANSIENT.includes(k as keyof State)) out[k] = v
  try {
    localStorage.setItem(WRITER_KEY, JSON.stringify({ at: touchedAt }))
    localStorage.setItem(KEY, JSON.stringify(out))
  } catch { /* 存储满了就不存 */ }
}

export function save(): void {
  // 这份已经被别的标签页比下去了：不写盘（写了就把新的盖成旧的），切回来会重载
  if (!stale) write()
  subs.forEach(fn => fn(st))
}

export function resetAll(): void { localStorage.removeItem(KEY) }
