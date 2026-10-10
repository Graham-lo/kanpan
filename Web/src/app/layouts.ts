/* Hkline Web · 图表布局与「布局集」
 *
 * 一套布局 = 几格（layout）+ 每格的配置（品种、周期、主图画法里的足迹开关……）。
 * 布局集 = 若干套有名字的布局（默认一套叫「默认」，最多 MAX_LAYOUTS 套）+ 当前用的是哪一套。
 *
 * 状态里有两份：st.layout / st.cells 是「当前这一套」的活数据（图表页一直在改它，地址栏参数也落在这），
 * st.layouts 是整个布局集。每次 save() 先把活数据抄回当前那一套（commitLive），切换时把另一套抄进活数据（loadLive）。
 * 整个布局集随账号同步（设置对象里的 chartLayouts 字段，网页独有；手机不认这个键、原样留着）。
 *
 * 指标不在布局里：指标布局一人一份、和手机共用（overlays / subs / params 那几个字段），换布局不换指标。
 * 这个文件不依赖 store：store 要在模块初始化时用它做迁移。
 */
import { INTERVALS } from '../market/symbols'
import { displayKey } from '../market/identity'
import { IV_MS } from '../util/format'

export type Layout = '1' | '2' | '2v' | '3' | '4' | '6' | '8' | '9' | '12' | '16'
/** 布局清单（TradingView 那种多窗口，最多 16 格） */
export const LAYOUTS: Layout[] = ['1', '2', '2v', '3', '4', '6', '8', '9', '12', '16']
/** 每种布局几格 */
export const LAYOUT_N: Record<Layout, number> = { '1': 1, '2': 2, '2v': 2, '3': 3, '4': 4, '6': 6, '8': 8, '9': 9, '12': 12, '16': 16 }
/** 最多几格 */
export const MAX_CELLS = 16

/** 一格的配置。主图画法三选一的开关只在开着时出现：footprint 足迹、ha 平均 K 线、range 等幅 K 线；
 *  log 对数坐标、bs 根宽（见下面「每格的视图」）；
 *  别的键（以后加的格子画法）按「短键 → 布尔 / 短串 / 数」原样留着，老版本读到也不丢 */
export interface CellCfg { symbol: string; iv: string; footprint?: boolean; ha?: boolean; range?: boolean; log?: boolean; bs?: number; [extra: string]: unknown }
/** 主图画法开关（每格各自记、随布局集跟人走） */
export const CELL_FLAGS = ['footprint', 'ha', 'range'] as const
export type CellFlag = typeof CELL_FLAGS[number]

/** 当前格子落在布局的格数以内（地址栏把八图改成一图时，参数要落到看得见的那一格上） */
export function clampActive(s: { active: number; layout: Layout }): void {
  const n = LAYOUT_N[s.layout] || 1
  s.active = Number.isInteger(s.active) ? Math.min(Math.max(0, s.active), n - 1) : 0
}
/** 多图时补齐格子的品种：先 BTC 与几只主流，再往后是热门山寨与美股、金银（16 格各不相同） */
export const FILL_SYMBOLS = ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'XAUUSDT', 'BNBUSDT', 'XRPUSDT', 'DOGEUSDT', 'NVDAUSDT', 'ADAUSDT', 'LINKUSDT', 'AVAXUSDT', 'SUIUSDT', 'XAGUSDT', 'TSLAUSDT', 'LTCUSDT', 'TRXUSDT']
/** 格子配置补到 n 格：缺的（含稀疏数组里的洞）按清单补一只还没用过的品种，周期跟第 0 格 */
export function ensureCells(s: { cells: CellCfg[] }, n: number): void {
  const iv = s.cells[0]?.iv || '1h'
  for (let i = 0; i < n; i++) {
    const c = s.cells[i]
    if (c && typeof c.symbol === 'string' && typeof c.iv === 'string') continue
    const used = new Set(s.cells.filter(Boolean).map(x => x.symbol))
    s.cells[i] = { symbol: FILL_SYMBOLS.find(k => !used.has(k)) || 'BTCUSDT', iv }
  }
}

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
/** 网页存的品种键：币安裸代号 / DXY，或别家的完整键 venue/market/SYMBOL（market/identity.ts） */
export const validSymbol = (v: unknown): v is string => typeof v === 'string' && (/^[\p{L}\p{N}._-]{2,40}$/u.test(v) || /^[a-z][a-z0-9_]{1,19}\/[a-z][a-z0-9_]{1,9}\/[\p{L}\p{N}._-]{1,40}$/u.test(v))

// ───────── 布局集 ─────────

/** 最多几套 */
export const MAX_LAYOUTS = 20
/** 名字最长几个字 */
export const NAME_MAX = 24
export const DEFAULT_LAYOUT_ID = 'default'
export const DEFAULT_LAYOUT_NAME = '默认'
/** 同步字段名（设置对象 id "chart" 里的一个键，网页独有） */
export const LAYOUTS_FIELD = 'chartLayouts'

export interface SavedLayout { id: string; name: string; layout: Layout; cells: CellCfg[] }
export interface LayoutBook { active: string; sets: SavedLayout[] }
/** 状态里和布局有关的那几项（store 的 State 是它的超集） */
export interface LiveLayout { layout: Layout; cells: CellCfg[]; active: number; layouts: LayoutBook }

const isObj = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v)
const ID_RE = /^[A-Za-z0-9_-]{1,32}$/
const EXTRA_KEY = /^[A-Za-z][A-Za-z0-9]{0,15}$/
const MAX_EXTRAS = 6

/** 名字：去控制字符、空白收成一个、去首尾空白，最多 NAME_MAX 个字；空的返回 '' */
export function cleanName(v: unknown): string {
  if (typeof v !== 'string') return ''
  // eslint-disable-next-line no-control-regex
  const s = v.replace(/[\u0000-\u001f\u007f\u2028\u2029]/g, ' ').replace(/\s+/g, ' ').trim()
  return [...s].slice(0, NAME_MAX).join('').trim()
}
export const cleanLayout = (v: unknown): Layout => {
  const k = typeof v === 'number' ? String(v) : v
  return LAYOUTS.includes(k as Layout) ? k as Layout : '1'
}

/** 一格的规范形：键顺序固定（symbol、iv、footprint、ha、range、其余按字母），比较时不受顺序影响 */
function cleanCell(c: Record<string, unknown>, iv0: string): CellCfg | undefined {
  if (!validSymbol(c.symbol)) return undefined
  // 完整三段写的币安 / 美元指数（binance/usd_m/BTCUSDT、macro/index/DXY，对比键、通知就是这么写的）收回网页存的规范键：
  // 原样留着的话这一格拿完整键去要币安的 K 线，本地就被拒（rest.ts guardVenue），格子一直空着
  const out: CellCfg = { symbol: displayKey(c.symbol), iv: validIv(c.iv) ? c.iv : iv0 }
  for (const f of CELL_FLAGS) if (c[f] === true) out[f] = true
  const ok = (v: unknown): boolean => typeof v === 'boolean' || (typeof v === 'number' && Number.isFinite(v)) || (typeof v === 'string' && v.length <= 16)
  const keys = Object.keys(c).sort().filter(k => k !== 'symbol' && k !== 'iv' && !(CELL_FLAGS as readonly string[]).includes(k) && EXTRA_KEY.test(k) && ok(c[k]))
  // 最多 MAX_EXTRAS 个短键（服务端同一个数）：对数坐标与根宽先占位，别的按字母排在后面的超了丢掉；写出来仍按字母排
  const view = keys.filter(k => (CELL_VIEW_KEYS as readonly string[]).includes(k))
  const keep = new Set([...view, ...keys.filter(k => !view.includes(k)).slice(0, MAX_EXTRAS - view.length)])
  for (const k of keys) if (keep.has(k)) out[k] = c[k]
  return out
}

/** 格子数组的规范形：坏项与洞补上（ensureCells），认不出的周期回第 0 格的（第 0 格自己坏了回 1 小时） */
export function cleanCells(raw: unknown): CellCfg[] {
  const list: unknown[] = Array.isArray(raw) ? raw.slice(0, MAX_CELLS) : []
  const iv0 = isObj(list[0]) && validIv(list[0].iv) ? list[0].iv : '1h'
  const s = { cells: list.map(c => (isObj(c) ? cleanCell(c, iv0) : undefined)) as CellCfg[] }
  if (!s.cells.length || !s.cells[0]) s.cells[0] = { symbol: 'BTCUSDT', iv: iv0 }
  ensureCells(s, s.cells.length)
  return s.cells
}
export const cloneCells = (cells: CellCfg[]): CellCfg[] => cells.map(c => ({ ...c }))

/** 布局集的规范形；一套能用的都没有返回 null。id 重复的后一个丢掉，名字空的给「未命名」，最多 MAX_LAYOUTS 套 */
export function cleanBook(raw: unknown): LayoutBook | null {
  if (!isObj(raw) || !Array.isArray(raw.sets)) return null
  const sets: SavedLayout[] = [], ids = new Set<string>()
  for (const x of raw.sets) {
    if (sets.length >= MAX_LAYOUTS) break
    if (!isObj(x) || typeof x.id !== 'string' || !ID_RE.test(x.id) || ids.has(x.id)) continue
    ids.add(x.id)
    sets.push({ id: x.id, name: cleanName(x.name) || '未命名', layout: cleanLayout(x.layout), cells: cleanCells(x.cells) })
  }
  if (!sets.length) return null
  const active = typeof raw.active === 'string' && ids.has(raw.active) ? raw.active : sets[0].id
  return { active, sets }
}

/** 只有一套「默认」的布局集（旧的单套 layout + cells 迁进来就是它） */
export function bookFrom(layout: Layout, cells: CellCfg[]): LayoutBook {
  return { active: DEFAULT_LAYOUT_ID, sets: [{ id: DEFAULT_LAYOUT_ID, name: DEFAULT_LAYOUT_NAME, layout, cells: cloneCells(cells) }] }
}
export const activeSet = (b: LayoutBook): SavedLayout => b.sets.find(x => x.id === b.active) || b.sets[0]

/** 活数据抄回当前那一套 */
export function commitLive(s: LiveLayout): void {
  const set = activeSet(s.layouts)
  s.layouts.active = set.id
  set.layout = s.layout
  set.cells = cloneCells(s.cells)
}
/** 当前那一套抄进活数据（格子补到布局的格数、当前格收进来） */
export function loadLive(s: LiveLayout): void {
  const set = activeSet(s.layouts)
  s.layouts.active = set.id
  s.layout = set.layout
  s.cells = cloneCells(set.cells)
  ensureCells(s, LAYOUT_N[s.layout])
  clampActive(s)
}
/** 「活数据已抄回」的布局集（不改状态）：同步记账、指纹用 */
export function liveBook(s: LiveLayout): LayoutBook {
  const a = activeSet(s.layouts).id
  return cleanBook({ active: a, sets: s.layouts.sets.map(x => (x.id === a ? { ...x, layout: s.layout, cells: s.cells } : x)) }) ?? bookFrom(s.layout, s.cells)
}

/** 新 id：时间 + 随机，够短、只用 [a-z0-9] */
export function genId(taken: Iterable<string> = []): string {
  const has = new Set(taken)
  for (;;) {
    const id = 'l' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6)
    if (!has.has(id)) return id
  }
}
/** 名字撞了就在后面加「 2」「 3」… */
export function uniqueName(b: LayoutBook, name: string, except?: string): string {
  const base = cleanName(name) || '未命名'
  const taken = new Set(b.sets.filter(x => x.id !== except).map(x => x.name))
  if (!taken.has(base)) return base
  for (let k = 2; ; k++) {
    const tail = ` ${k}`, head = [...base].slice(0, NAME_MAX - tail.length).join('')
    if (!taken.has(head + tail)) return head + tail
  }
}

/** 切到另一套：先把当前活数据抄回去，再把那一套装进来。没这套或就是当前返回 false */
export function switchLayout(s: LiveLayout, id: string): boolean {
  if (id === s.layouts.active || !s.layouts.sets.some(x => x.id === id)) return false
  commitLive(s)
  s.layouts.active = id
  loadLive(s)
  return true
}
/** 另存为：当前活数据存成新的一套（排在当前那套后面）并切过去。满了返回 null */
export function saveAsLayout(s: LiveLayout, name: string, id?: string): SavedLayout | null {
  if (s.layouts.sets.length >= MAX_LAYOUTS) return null
  commitLive(s)
  const set: SavedLayout = { id: id && ID_RE.test(id) && !s.layouts.sets.some(x => x.id === id) ? id : genId(s.layouts.sets.map(x => x.id)), name: uniqueName(s.layouts, name), layout: s.layout, cells: cloneCells(s.cells) }
  const at = s.layouts.sets.findIndex(x => x.id === s.layouts.active)
  s.layouts.sets.splice(at + 1, 0, set)
  s.layouts.active = set.id
  return set
}
/** 改名：空名不改；和别的套撞名自动加序号。返回改成了什么（没改返回 null） */
export function renameLayout(b: LayoutBook, id: string, name: string): string | null {
  const set = b.sets.find(x => x.id === id)
  if (!set || !cleanName(name)) return null
  const n = uniqueName(b, name, id)
  if (n === set.name) return null
  set.name = n
  return n
}
/** 删一套：最后一套不删；删的是当前那套就切到它后面那套（没有就前面那套）。返回删没删 */
export function deleteLayout(s: LiveLayout, id: string): boolean {
  const b = s.layouts, i = b.sets.findIndex(x => x.id === id)
  if (i < 0 || b.sets.length <= 1) return false
  const wasActive = b.active === id
  if (!wasActive) commitLive(s)
  b.sets.splice(i, 1)
  if (wasActive) { b.active = b.sets[Math.min(i, b.sets.length - 1)].id; loadLive(s) }
  return true
}

// ───────── 每格的视图：对数坐标与根宽 ─────────
// 2026-10-10 起跟人走：记成格子配置里的两个短键（随布局集同步，服务端按格子短键收：布尔 / 数）。
// log：这一格开着对数坐标；bs：K 线间距（px / 根，即根宽）。都是出厂值时不写（出厂那一格仍是 { symbol, iv }）。
// 只记根宽、不记位置：刷新、换品种后回到最新一根，根宽留着

/** 格子配置里的两个短键 */
export const CELL_VIEW_KEYS = ['log', 'bs'] as const
/** 根宽的出厂值（chart/wheel.ts DEFAULT_SPACING，TV barSpacing 默认 6）：这个文件不引图表模块，抄一份，测试里对着 */
export const CELL_BS_DEFAULT = 6
/** 记的根宽夹在这里（读出来再按格子的宽夹一次，见 chart/wheel.ts clampSpacing） */
const BS_MIN = 0.5, BS_MAX = 2000
export interface CellView { log: boolean; spacing: number }
/** 这一格记着的视图（没记的是出厂：线性坐标、根宽 6） */
export function cellView(c: CellCfg | undefined): CellView {
  const bs = c?.bs
  return { log: c?.log === true, spacing: typeof bs === 'number' && Number.isFinite(bs) ? Math.min(BS_MAX, Math.max(BS_MIN, bs)) : CELL_BS_DEFAULT }
}
/** 把图上眼下的视图记进格子配置（根宽留两位小数），返回改没改。出厂值删键 */
export function writeCellView(c: CellCfg, v: CellView): boolean {
  let changed = false
  if (v.log) { if (c.log !== true) { c.log = true; changed = true } } else if ('log' in c) { delete c.log; changed = true }
  const bs = Number.isFinite(v.spacing) ? Math.round(Math.min(BS_MAX, Math.max(BS_MIN, v.spacing)) * 100) / 100 : CELL_BS_DEFAULT
  if (bs === CELL_BS_DEFAULT) { if ('bs' in c) { delete c.bs; changed = true } } else if (c.bs !== bs) { c.bs = bs; changed = true }
  return changed
}
/** 去掉视图两键的格子（比两套布局是不是同一套时不看缩放与坐标） */
const withoutView = (c: CellCfg): CellCfg => { const { log: _l, bs: _b, ...rest } = c; return rest as CellCfg }

/** 出厂那一套（只有一格 BTC 1 小时、没开足迹）：首次合并云端时不把它当成「本机自己的布局」另存一份。
 *  只缩放过、开过对数坐标的也算出厂（视图不是一套布局） */
function isFactory(x: SavedLayout): boolean {
  return x.layout === '1' && x.cells.length === 1 && x.cells[0].symbol === 'BTCUSDT' && x.cells[0].iv === '1h' && Object.keys(withoutView(x.cells[0])).length === 2
}
const sameSet = (a: SavedLayout, b: SavedLayout): boolean => a.layout === b.layout && JSON.stringify(a.cells.map(withoutView)) === JSON.stringify(b.cells.map(withoutView))

/**
 * 这台电脑第一次和云端的布局集对上（刚登录、或老版本升上来）：以云端为准，
 * 本机有而云端没有的（格子数或格子配置不同）接在后面，撞名的带「（本机）」，不丢；出厂那一套不接。
 * 满 MAX_LAYOUTS 套就不再接。
 */
export function mergeBooks(cloud: LayoutBook, local: LayoutBook): LayoutBook {
  const out: LayoutBook = { active: cloud.active, sets: cloud.sets.map(x => ({ ...x, cells: cloneCells(x.cells) })) }
  for (const x of local.sets) {
    if (out.sets.length >= MAX_LAYOUTS) break
    if (isFactory(x) || out.sets.some(y => sameSet(x, y))) continue
    const ids = out.sets.map(y => y.id)
    const name = out.sets.some(y => y.name === x.name) ? uniqueName(out, `${x.name}（本机）`) : x.name
    out.sets.push({ id: ids.includes(x.id) ? genId(ids) : x.id, name, layout: x.layout, cells: cloneCells(x.cells) })
  }
  return out
}

/** 主图画法开关的老存法（只记本机：localStorage 里一串格子序号） */
export const LEGACY_FLAG_KEYS: Record<CellFlag, string> = { footprint: 'hkline-web-footprint', ha: 'hkline-web-heikin', range: 'hkline-web-range' }
export const LEGACY_FOOTPRINT_KEY = LEGACY_FLAG_KEYS.footprint
/** 老存法并进格子配置；返回并进了几格（读不懂的当没有）。一格已经开着别的画法就不再叠（三选一） */
export function migrateLegacyFlag(s: { cells: CellCfg[] }, flag: CellFlag, raw: string | null): number {
  if (!raw) return 0
  let v: unknown
  try { v = JSON.parse(raw) } catch { return 0 }
  if (!Array.isArray(v)) return 0
  let n = 0
  for (const i of v) {
    const c = Number.isInteger(i) && i >= 0 && i < s.cells.length ? s.cells[i] : undefined
    if (!c || CELL_FLAGS.some(f => c[f] === true)) continue
    c[flag] = true; n++
  }
  return n
}
export const migrateLegacyFootprint = (s: { cells: CellCfg[] }, raw: string | null): number => migrateLegacyFlag(s, 'footprint', raw)
