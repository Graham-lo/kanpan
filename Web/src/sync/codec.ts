/* Hkline Web · 网页状态 ↔ 云端对象的编解码
 *
 * 线上字段名和取值形状照手机端（Kanpan/Account/PersonalSyncCodec.swift、KanpanCore 的 Drawing /
 * Alert / AlertGeometry / AlertRule）来，服务端的白名单在 Backend/kanpan-api/src/sync_validation.rs。
 *
 * 通用规矩：
 * - 网页只替它「管得着」的对象说话。管不着的（手机上隐藏的线、网页没有的画线种类、Coinbase 现货、
 *   已触发的提醒、复盘到期提醒……）不删、不改、不显示。
 * - 一个对象网页没改过（把云端那份解码出来和网页现在这份一样），就原样用云端那份 body——
 *   往返不产生任何操作，手机那边的字段（文字、虚线、刻度、备注、webhook 文案）一个不丢。
 * - 改过的，从云端那份 body 出发，只覆盖网页拥有的那几个键。
 *
 * 纯函数，不碰 DOM、不碰全局状态，方便 vitest。
 */
import type { Alert, IndState } from '../app/store'
import { migrateAlert } from '../alerts/shape'
import { indicatorRuleOk, isIndicatorRule } from '../alerts/indicator'
import type { Drawing, DrawingType, DrawPoint } from '../chart/chart'
import { MAX_SUBS, type IndParams, type SubId } from '../chart/calc'
import { INTERVALS, type Kind } from '../market/symbols'
import { MACRO_ALERT_MARKET, MACRO_CN, MACRO_MARKET, MACRO_SYMBOL, MACRO_VENUE, isMacro, syncKeyOf, venueMarketOf } from '../market/macro'
import { type Body, type Json, type SyncObject, same } from './types'
import { MAX_OVERRIDES, isValidBase, normalizeOverride, type Override } from '../orderflow/settings'
import { LAYOUTS_FIELD, bookFrom, cleanBook, liveBook, loadLive, type CellCfg, type Layout, type LayoutBook } from '../app/layouts'

export interface Ctx {
  now(): number
  /** 品种在币安 U 本位表里的类别；表里没有返回 undefined */
  kindOf(symbol: string): Kind | undefined
  price(symbol: string): number | null
  /** 价格按这只品种的小数位格式化（标题用） */
  label(symbol: string, p: number): string
}

export const VENUE = 'binance'
export const MARKET = 'usd_m'
export const ALERT_MARKET = 'binance/usd_m'
/** 一只网页品种的同步前缀：币安 U 本位是 binance/usd_m/<代号>/，美元指数是 macro/index/DXY/ */
const prefixOf = (symbol: string): string => syncKeyOf(symbol) + '/'
/** 网页存的裸代号能不能上云：币安代号规则，或美元指数（DXY ↔ macro/index/DXY） */
export function webSymbol(s: string): boolean { return validSymbol(s) || isMacro(s) }
/** 提醒正文里的 market */
export function alertMarketOf(symbol: string): string { return isMacro(symbol) ? MACRO_ALERT_MARKET : ALERT_MARKET }
/** 同步正文的 venue / market 是不是这只网页品种的（美元指数认 macro/index） */
function venueOk(b: Body, symbol: string): boolean {
  const vm = venueMarketOf(symbol)
  return b.venue === vm.venue && b.market === vm.market && (vm.venue !== VENUE || validSymbol(symbol))
}

const QUOTE_ASSETS = ['USDT', 'USDC', 'FDUSD', 'BUSD', 'USD1', 'TUSD'] // instruments.rs QUOTE_ASSETS
/** 一个字符是 ASCII 大写 / 数字，或非 ASCII 的 Unicode 字母数字（Rust char::is_alphanumeric = Alphabetic ∪ Nd/Nl/No） */
const symbolChar = (c: string): boolean => /^[A-Z0-9]$/.test(c) || (c.codePointAt(0)! > 0x7f && /^[\p{Alphabetic}\p{N}]$/u.test(c))
/** 服务端 `sync_validation.rs` binance_symbol 的币安代号规则：按字符数（不按 UTF-16 长度）最长 40；
 *  ASCII 大写、数字，或非 ASCII 的 Unicode 字母数字（币安上架过「币安人生USDT」这种中文底名的合约）；
 *  以计价资产结尾，且前面还有底名。iOS 这些代号照常同步——只认 ASCII 的话网页管不着它们，
 *  PC 推自选时还会把它们当成「本机删了」发删除。 */
export function validSymbol(s: string): boolean {
  if (!s) return false
  const chars = [...s]
  if (chars.length > 40 || !chars.every(symbolChar)) return false
  return QUOTE_ASSETS.some(q => s.length > q.length && s.endsWith(q))
}
/** 服务端 coinbase_symbol：`BASE-USD`，BASE 只有 ASCII 大写与数字 */
export function coinbaseSymbol(s: string): boolean {
  return s.length <= 40 && /^[A-Z0-9]+-USD$/.test(s)
}
/** 服务端 identity(venue, market, symbol)：只认币安 U 本位与 Coinbase 现货两种，代号按各自的规则
 *  （自选、对比品种键 `venue/market/SYMBOL` 都走它——能收藏就能对比） */
export function instrumentIdentity(venue: string, market: string, symbol: string): boolean {
  if (venue === VENUE && market === MARKET) return validSymbol(symbol)
  if (venue === 'coinbase' && market === 'spot') return coinbaseSymbol(symbol)
  if (venue === MACRO_VENUE && market === MACRO_MARKET) return symbol === MACRO_SYMBOL   // 服务端白名单只放美元指数一只
  return false
}
/** 服务端 compare_key：`venue/market/SYMBOL`，整串 UTF-8 不超过 128 字节，三段过 identity */
export function compareKey(k: string): boolean {
  const p = k.split('/')
  return p.length === 3 && new TextEncoder().encode(k).length <= 128 && instrumentIdentity(p[0], p[1], p[2])
}
/** 对比品种最多三只（与手机 m/app/prefs MAX_COMPARE、服务端 sync_validation compareSymbols ≤ 3 同一个数） */
export const MAX_COMPARE = 3
/** 对比品种的规范形（照手机 m/app/prefs.cleanCompare，同一条规则，tests/compare-pc 对过账）：
 *  键是 `venue/market/SYMBOL`；裸代号按币安 U 本位补全；过服务端 compare_key、不重复、最多三只。
 *  美元指数只认 `macro/index/DXY`（裸 DXY 会被补成 binance/usd_m/DXY、过不了 compare_key 而丢掉）——网页存的从来是规范键。 */
export function cleanCompare(v: unknown): string[] {
  const out: string[] = []
  for (const x of Array.isArray(v) ? v.filter((y): y is string => typeof y === 'string') : []) {
    const k = x.includes('/') ? x : 'binance/usd_m/' + x.toUpperCase()
    if (compareKey(k) && !out.includes(k)) out.push(k)
    if (out.length >= MAX_COMPARE) break
  }
  return out
}
/** 标题里用的品种名：去掉计价币（和手机 `Alert.base(of:)` 一致） */
export function baseName(s: string): string { return isMacro(s) ? MACRO_CN : s.replace(/(USDT|USDC|FDUSD|BUSD|USD1|TUSD)$/, '') || s }

const lastSeg = (id: string): string => id.slice(id.lastIndexOf('/') + 1)
const num = (v: Json | undefined): number | null => typeof v === 'number' && isFinite(v) ? v : null
const str = (v: Json | undefined): string | null => typeof v === 'string' ? v : null
const obj = (v: Json | undefined): Record<string, Json> | null => v && typeof v === 'object' && !Array.isArray(v) ? v : null

// ═════════════════════════════ settings（id "chart"） ═════════════════════════════
//
// 网页只同步和手机同一回事的那几项：钉在周期条上的周期、主图 / 副图开了哪些指标、指标参数、主力订单流的门槛与步长、
// 对比品种、隐藏画线（drawingsHidden ↔ st.drawHidden）；外加网页独有的布局集（chartLayouts，手机不认这个键、原样留着）。
// 皮肤 / 深浅 / 涨跌色是网页自己的一套视觉（和手机不是一回事），线路是每台设备自己的，
// 当前周期是「每个图格一个」而手机是「整个 app 一个」，这几项不同步。
//
// 设置对象手机端有几十个字段，网页只认其中几个，所以按字段记一份 `seen`：
// 「这个字段上一次和云端对上时网页这边是什么样」。网页值 ≠ seen → 网页改了，推；
// 云端解码值 ≠ seen → 云端改了，装。云端的值网页表达不了（比如 3 日线）时 seen 记成网页现值，
// 不推也不装，免得网页一碰就把手机的值冲掉。

export interface SettingsState {
  pinned: string[]; ind: IndState; params: Record<string, IndParams> | null
  /** 主力订单流门槛 / 步长里用户改过的项（按 base），线上形状和手机一样：{ BTC: { spot, usdtPerp, coinPerp, delivery, step } } */
  orderFlowOverrides?: Record<string, Override>
  /** 对比品种（规范键 venue/market/SYMBOL，最多三只），和手机 Prefs.compareSymbols 同一个字段 */
  compareSymbols?: string[]
  /** 隐藏画线（PC 画线工具条的眼睛 / ⌘⌥H），和手机 Prefs.drawingsHidden 同一个字段，2026-10-06 起跟账号同步 */
  drawHidden?: boolean
  /** 布局集（app/layouts.ts）与当前那套的活数据：chartLayouts 字段 = 活数据抄回之后的整个布局集，2026-10-07 起跟账号同步 */
  layouts?: LayoutBook; layout?: Layout; cells?: CellCfg[]; active?: number
}

export const SETTINGS_ID = 'chart'
const PARAM_IDS: [string, string][] = [['ma', 'MA'], ['ema', 'EMA'], ['boll', 'BOLL'], ['macd', 'MACD'], ['rsi', 'RSI'], ['kdj', 'KDJ']]
export const SETTINGS_FIELDS = ['quickIntervals', 'overlays', 'subs', ...PARAM_IDS.map(([, p]) => 'params/' + p), 'orderFlowOverrides', 'compareSymbols', 'drawingsHidden', LAYOUTS_FIELD]
/** 云端没有这个字段时本机的值要推上去（网页独有，没有别的端会写它）：seen 记成 null，下一次记账一定推 */
const PUSH_WHEN_CLOUD_EMPTY = new Set([LAYOUTS_FIELD])
/** 状态里有没有布局集那几项（单元测试里的精简状态可以没有） */
const hasLayouts = (s: SettingsState): s is SettingsState & { layouts: LayoutBook; layout: Layout; cells: CellCfg[]; active: number } =>
  !!s.layouts && !!s.layout && Array.isArray(s.cells)

/** 订单流覆盖项的规范形：base 合规、每项过 normalizeOverride、最多 MAX_OVERRIDES 只、键排序（比较不受顺序影响） */
function cleanOverrides(v: unknown): Record<string, Override> | null {
  if (!v || typeof v !== 'object' || Array.isArray(v)) return null
  const out: Record<string, Override> = {}
  for (const k of Object.keys(v).sort().slice(0, MAX_OVERRIDES)) {
    const n = normalizeOverride((v as Record<string, Override>)[k])
    if (n && isValidBase(k)) out[k] = n
  }
  return out
}
const OVERLAY_MAP: [keyof IndState & ('ma' | 'ema' | 'boll'), string][] = [['ma', 'MA'], ['ema', 'EMA'], ['boll', 'BOLL']]
const SUB_MAP: [string, string][] = [['vol', 'VOL'], ['macd', 'MACD'], ['rsi', 'RSI'], ['kdj', 'KDJ'], ['oi', 'OI']]

/** 网页那一侧某个字段的规范值（seen 里存的就是这个） */
export function webSetting(s: SettingsState, field: string): Json {
  if (field === 'quickIntervals') return INTERVALS.filter(iv => s.pinned.includes(iv))
  if (field === 'overlays') return OVERLAY_MAP.filter(([w]) => s.ind[w]).map(([, c]) => c)
  if (field === 'subs') return [...(s.ind.vol ? ['VOL'] : []), ...s.ind.subs.map(x => SUB_MAP.find(([w]) => w === x)?.[1]).filter((x): x is string => !!x)]
  if (field === 'orderFlowOverrides') return (cleanOverrides(s.orderFlowOverrides) ?? {}) as unknown as Json
  if (field === 'compareSymbols') return cleanCompare(s.compareSymbols)
  if (field === 'drawingsHidden') return s.drawHidden === true
  if (field === LAYOUTS_FIELD) return hasLayouts(s) ? liveBook({ ...s, active: s.active ?? 0 }) as unknown as Json : null
  if (field.startsWith('params/')) {
    const id = PARAM_IDS.find(([, c]) => 'params/' + c === field)?.[0]
    const p = id ? s.params?.[id] : undefined
    return p ? (JSON.parse(JSON.stringify(p)) as Json) : null
  }
  return null
}

const okInt = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v) && v >= 1 && v <= 400

/** 把「网页认识的那几个」按网页的新顺序填回云端列表里它们原来占的位置；
 *  网页不认识的（手机独有的指标）原地不动，多出来的接在后面，少了的位置去掉 */
export function mergeList(prev: string[], known: Set<string>, web: string[]): string[] {
  const queue = [...web], out: string[] = []
  for (const x of prev) {
    if (!known.has(x)) { out.push(x); continue }
    const next = queue.shift()
    if (next !== undefined) out.push(next)
  }
  out.push(...queue)
  return out
}

/** 网页值 → 云端值；表达不了（参数不是整数、超出范围）返回 undefined，意思是「不推」 */
export function encodeSetting(field: string, web: Json, prev: Json | undefined): Json | undefined {
  const prevList = Array.isArray(prev) ? prev.filter((x): x is string => typeof x === 'string') : []
  if (field === 'quickIntervals') {
    // 手机独有的周期（网页没有的）原地留着，网页钉的按网页来；超过 10 个先挤掉手机独有的
    const pinned = web as string[]
    const kept = prevList.filter(iv => !INTERVALS.includes(iv) || pinned.includes(iv))
    const out = [...kept, ...pinned.filter(iv => !kept.includes(iv))]
    while (out.length > 10) {
      const i = out.map(x => !INTERVALS.includes(x)).lastIndexOf(true)
      if (i < 0) break
      out.splice(i, 1)
    }
    return out.slice(0, 10)
  }
  if (field === 'overlays') return mergeList(prevList, new Set(OVERLAY_MAP.map(([, c]) => c)), web as string[])
  if (field === 'subs') return mergeList(prevList, new Set(SUB_MAP.map(([, c]) => c)), web as string[])
  if (field === 'orderFlowOverrides') return (cleanOverrides(web) ?? undefined) as unknown as Json | undefined
  if (field === 'compareSymbols') return cleanCompare(web)
  if (field === 'drawingsHidden') return web === true
  if (field === LAYOUTS_FIELD) return (cleanBook(web) ?? undefined) as unknown as Json | undefined
  if (field.startsWith('params/')) {
    const p = web as IndParams | null
    if (!p) return undefined
    const pv = Array.isArray(prev) ? prev.filter((x): x is number => typeof x === 'number') : []
    let out: number[] | null = null
    switch (field) {
      case 'params/MA': case 'params/EMA': out = p.periods ?? null; break
      case 'params/BOLL': out = p.n != null && p.k != null ? [p.n, p.k] : null; break
      case 'params/MACD': out = p.fast != null && p.slow != null && p.signal != null ? [p.fast, p.slow, p.signal] : null; break
      case 'params/RSI': out = p.n != null ? [p.n, ...pv.slice(1)] : null; break
      case 'params/KDJ': out = p.n != null && p.m1 != null && p.m2 != null ? [p.n, p.m1, p.m2] : null; break
    }
    if (!out || !out.length || out.length > 20 || !out.every(okInt)) return undefined
    return out
  }
  return undefined
}

/** 云端值 → 网页值；网页表达不了返回 undefined */
export function decodeSetting(field: string, cloud: Json | undefined, cur: SettingsState): Json | undefined {
  if (cloud === undefined || cloud === null) return undefined
  const list = Array.isArray(cloud) ? cloud.filter((x): x is string => typeof x === 'string') : null
  if (field === 'quickIntervals') {
    if (!list) return undefined
    const out = INTERVALS.filter(iv => list.includes(iv))
    return out.length ? out : undefined
  }
  if (field === 'overlays') return list ? OVERLAY_MAP.filter(([, c]) => list.includes(c)).map(([, c]) => c) : undefined
  if (field === 'subs') {
    if (!list) return undefined
    const vol = list.includes('VOL')
    const others = list.filter(c => c !== 'VOL' && SUB_MAP.some(([, x]) => x === c)).slice(0, MAX_SUBS)
    return [...(vol ? ['VOL'] : []), ...others]
  }
  if (field === 'orderFlowOverrides') return (cleanOverrides(cloud) ?? undefined) as unknown as Json | undefined
  // 别家的键（Coinbase 现货）照样留着：网页画不了就不画，但不能一装一推把手机那只冲掉
  if (field === 'compareSymbols') return Array.isArray(cloud) ? cleanCompare(cloud) : undefined
  if (field === 'drawingsHidden') return typeof cloud === 'boolean' ? cloud : undefined
  if (field === LAYOUTS_FIELD) return (cleanBook(cloud) ?? undefined) as unknown as Json | undefined
  if (field.startsWith('params/')) {
    const v = Array.isArray(cloud) ? cloud.filter((x): x is number => typeof x === 'number') : null
    if (!v || !v.length || !v.every(okInt)) return undefined
    const old = webSetting(cur, field) as IndParams | null
    switch (field) {
      case 'params/MA': case 'params/EMA': return { ...(old ?? {}), periods: v } as Json
      case 'params/BOLL': return v.length >= 2 ? { ...(old ?? {}), n: v[0], k: v[1] } as Json : undefined
      case 'params/MACD': return v.length >= 3 ? { ...(old ?? {}), fast: v[0], slow: v[1], signal: v[2] } as Json : undefined
      case 'params/RSI': return { ...(old ?? {}), n: v[0] } as Json
      case 'params/KDJ': return v.length >= 3 ? { ...(old ?? {}), n: v[0], m1: v[1], m2: v[2] } as Json : undefined
    }
  }
  return undefined
}

/** 网页值写回状态（原地改） */
export function putSetting(s: SettingsState, field: string, v: Json): void {
  const list = Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []
  if (field === 'quickIntervals') s.pinned = list
  else if (field === 'orderFlowOverrides') s.orderFlowOverrides = cleanOverrides(v) ?? {}
  else if (field === 'compareSymbols') s.compareSymbols = cleanCompare(v)
  else if (field === 'drawingsHidden') s.drawHidden = v === true
  else if (field === LAYOUTS_FIELD) {
    const b = cleanBook(v)
    if (b && hasLayouts(s)) { s.layouts = b; const live = { ...s, active: s.active ?? 0 }; loadLive(live); s.layout = live.layout; s.cells = live.cells; s.active = live.active }
  }
  else if (field === 'overlays') for (const [w, c] of OVERLAY_MAP) s.ind[w] = list.includes(c)
  else if (field === 'subs') {
    s.ind.vol = list.includes('VOL')
    // 云端那几个（手机也认识的）按云端的顺序填回它们在本机列表里的位置；网页独有的副图（累计量差、随机指标…）原地留着
    const cloud = list.map(c => SUB_MAP.find(([, x]) => x === c)?.[0]).filter((x): x is SubId => !!x && x !== 'vol')
    const known = new Set(SUB_MAP.map(([w]) => w))
    s.ind.subs = [...new Set(mergeList(s.ind.subs, known, cloud))].slice(0, MAX_SUBS) as SubId[]
  } else if (field.startsWith('params/')) {
    const id = PARAM_IDS.find(([, c]) => 'params/' + c === field)?.[0]
    if (id && v && typeof v === 'object') s.params = { ...(s.params ?? {}), [id]: v as IndParams }
  }
}

/** 捕获：网页改过的字段编码进 body（其余字段原样沿用云端那份），同时更新 seen。
 *  返回 null 表示这次没有要推的 */
export function encodeSettings(s: SettingsState, prev: SyncObject | undefined, seen: Record<string, Json>): SyncObject | null {
  const body: Body = { ...(prev && !prev.deleted ? prev.body : {}) }
  let touched = false
  for (const f of SETTINGS_FIELDS) {
    const w = webSetting(s, f)
    if (f in seen && same(w, seen[f])) continue
    seen[f] = w
    const e = encodeSetting(f, w, body[f])
    if (e === undefined || same(e, body[f])) continue
    body[f] = e; touched = true
  }
  if (!touched) return null
  return { collection: 'settings', id: SETTINGS_ID, body, fields: {}, revision: 0, deleted: false, generation: 0 }
}

/** 出厂的同步设置（与 app/store 的 defaults() 同一组值，tests/sync-bridge 对过账）：
 *  换了账号、云端又没有这个人的设置时，这台电脑回到出厂，不把上一个账号的指标布局带进新账号（iOS 按账号分目录存偏好，同理） */
export function factorySettings(): Required<SettingsState> {
  return {
    pinned: ['1m', '5m', '15m', '1h', '4h', '1d', '1w'],
    ind: { ma: true, ema: false, boll: false, vol: true, subs: ['macd', 'rsi'] },
    params: null,
    orderFlowOverrides: {},
    compareSymbols: [],
    drawHidden: false,
    layouts: bookFrom('1', [{ symbol: 'BTCUSDT', iv: '1h' }]),
    layout: '1', cells: [{ symbol: 'BTCUSDT', iv: '1h' }], active: 0,
  }
}

/** 换人：同步设置整份回到出厂（原地改），返回变了的字段 */
export function resetSettings(s: SettingsState): string[] {
  const before = SETTINGS_FIELDS.map(f => webSetting(s, f))
  const f = factorySettings()
  s.pinned = f.pinned; s.ind = f.ind; s.params = f.params; s.orderFlowOverrides = f.orderFlowOverrides; s.compareSymbols = f.compareSymbols; s.drawHidden = f.drawHidden
  if (hasLayouts(s)) { s.layouts = f.layouts; s.layout = f.layout; s.cells = f.cells; s.active = f.active }
  return SETTINGS_FIELDS.filter((x, i) => !same(before[i], webSetting(s, x)))
}

/** 云端这个字段装不了（没有 / 表达不了）时 seen 记什么：一般记网页现值（不推）；网页独有的记 null（推） */
export function seenWhenUndecodable(s: SettingsState, f: string, cloud: Json | undefined): Json {
  return PUSH_WHEN_CLOUD_EMPTY.has(f) && (cloud === undefined || cloud === null) ? null : webSetting(s, f)
}

/** 应用：云端值和 seen 不同的字段写回状态。返回改了哪些字段（fields：只看这几个，缺省全部） */
export function applySettings(s: SettingsState, cloud: SyncObject | undefined, seen: Record<string, Json>, fields: readonly string[] = SETTINGS_FIELDS): string[] {
  if (!cloud || cloud.deleted) return []
  const changed: string[] = []
  for (const f of fields) {
    const d = decodeSetting(f, cloud.body[f], s)
    if (d === undefined) {
      // 云端这个字段网页表达不了：记成网页现值，免得下一次捕获把它当成网页改过的推上去（网页独有的、云端没有：记 null，推）
      if (!(f in seen)) seen[f] = seenWhenUndecodable(s, f, cloud.body[f])
      continue
    }
    if (f in seen && same(d, seen[f])) continue
    seen[f] = d
    if (same(d, webSetting(s, f))) continue
    putSetting(s, f, d); changed.push(f)
  }
  return changed
}

/** 这个设置对象最后一次被改的时刻（字段时间戳里最大的那个），首次登录「谁新用谁」用 */
export function lastTouched(o: SyncObject | undefined, fields?: string[]): number {
  if (!o) return 0
  let t = 0
  for (const [k, stamp] of Object.entries(o.fields || {})) {
    if (fields && !fields.includes(k)) continue
    const ts = num(obj(stamp)?.timestamp)
    if (ts != null && ts > t) t = ts
  }
  return t
}

// ═════════════════════════════ favorites ═════════════════════════════
//
// 手机的自选是一条全局列表（order 是全局下标、可以挂分组）；网页按 加密 / 美股 / 大宗 三个标签页各排各的。
// 合并用「类别占位」：云端列表里每个位置按它原来的类别，填回网页那个类别的新顺序；
// 网页不认识的（Coinbase 现货、表里没有的）原地不动；新加的接在最后。

export const favId = (symbol: string): string => syncKeyOf(symbol)
const KIND_ORDER: Kind[] = ['crypto', 'us', 'idx', 'com']

function liveSorted(objs: SyncObject[]): SyncObject[] {
  return objs.filter(o => !o.deleted).sort((a, b) => (num(a.body.order) ?? 0) - (num(b.body.order) ?? 0) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
}
/** 网页管得着的自选：币安 U 本位、在品种表里 */
function favKind(o: SyncObject, ctx: Ctx): Kind | undefined {
  const s = str(o.body.symbol)
  if (!s || !venueOk(o.body, s) || o.id !== favId(s)) return undefined
  return isMacro(s) ? 'idx' : ctx.kindOf(s)
}

const PRECIOUS = new Set(['XAU', 'XAG', 'XPT', 'XPD'])
/** 手机端 FavoriteCategory.name 的同一套类名（加密 / 美股 / 贵金属 / 其他） */
function categoryName(kind: Kind, symbol: string): string {
  if (kind === 'crypto') return '加密'
  if (kind === 'us') return '美股'
  if (kind === 'idx') return '指数'
  return PRECIOUS.has(symbol.replace(/USDT$|USDC$/, '').toUpperCase()) ? '贵金属' : '其他'
}
/** 网页上新加的一只自选落进手机的哪一类（审查 D-01）。
 *  网页的标签页就是他此刻站着的那一类：先找同名的分类（同名并成一格时手机留 id 最小的那个）；
 *  没有同名的，就跟着同一标签页里已经有的自选挂在哪一类（多数那一类）。都找不到才留空——
 *  以前一律留空，手机分类页按分类过滤，这只自选在手机上就看不见了。 */
function groupForNew(kind: Kind, symbol: string, prev: SyncObject[], groups: SyncObject[], ctx: Ctx): string | null {
  const live = groups.filter(o => !o.deleted && typeof o.body.name === 'string')
  const ids = new Set(live.map(o => o.id))
  const name = categoryName(kind, symbol)
  const named = live.filter(o => (o.body.name as string).trim() === name).map(o => o.id).sort()
  if (named.length) return named[0]
  const counts = new Map<string, number>()
  for (const o of prev) {
    const g = o.body.groupId
    if (typeof g === 'string' && ids.has(g) && favKind(o, ctx) === kind) counts.set(g, (counts.get(g) ?? 0) + 1)
  }
  let best: string | null = null, most = 0
  for (const [g, n] of [...counts].sort((a, b) => (a[0] < b[0] ? -1 : 1))) if (n > most) { best = g; most = n }
  return best
}

/** 网页自选 → 要记账的对象（含删除）。品种表还没到时返回空：分不出类别就不动。
 *  `groups`：云端的分类（只读，网页不建分类），新加的自选按它挂进手机那一类 */
export function encodeFavorites(watch: Record<Kind, string[]>, prevAll: SyncObject[], ctx: Ctx, groups: SyncObject[] = []): SyncObject[] {
  const prev = liveSorted(prevAll)
  // 云端有、网页分不出类别的（Coinbase、表里没有的）原地留着；网页那边同名的不再重复排
  const pinnedIds = new Set(prev.filter(o => !favKind(o, ctx)).map(o => o.id))
  const seen = new Set<string>()
  const queues = new Map<Kind, string[]>()
  for (const k of KIND_ORDER) {
    queues.set(k, (watch[k] ?? []).filter(s => webSymbol(s) && !pinnedIds.has(favId(s)) && !seen.has(s) && (seen.add(s), true)))
  }
  const seq: { id: string; symbol: string | null; prev?: SyncObject; kind?: Kind }[] = []
  const byId = new Map(prevAll.map(o => [o.id, o]))
  for (const o of prev) {
    const k = favKind(o, ctx)
    if (!k) { seq.push({ id: o.id, symbol: null, prev: o }); continue }
    const next = queues.get(k)!.shift()
    if (next !== undefined) seq.push({ id: favId(next), symbol: next, prev: byId.get(favId(next)), kind: k })
  }
  for (const k of KIND_ORDER) for (const s of queues.get(k)!) seq.push({ id: favId(s), symbol: s, prev: byId.get(favId(s)), kind: k })
  const unchanged = seq.length === prev.length && seq.every((x, i) => x.id === prev[i].id)
  const out: SyncObject[] = []
  const keep = new Set(seq.map(x => x.id))
  seq.forEach((x, i) => {
    const order = unchanged ? (num(x.prev?.body.order) ?? i) : i
    const base = x.prev && !x.prev.deleted ? x.prev.body : null
    const body: Body = x.symbol == null
      ? { ...(base ?? {}), order }
      : { symbol: x.symbol, ...venueMarketOf(x.symbol), groupId: base && 'groupId' in base ? base.groupId : (x.kind ? groupForNew(x.kind, x.symbol, prev, groups, ctx) : null), order }
    out.push({ collection: 'favorites', id: x.id, body, fields: {}, revision: 0, deleted: false, generation: 0 })
  })
  for (const o of prev) {
    if (keep.has(o.id) || !favKind(o, ctx)) continue
    out.push({ ...o, deleted: true })
  }
  return out
}

/** 云端自选 → 网页三个标签页 */
export function decodeFavorites(all: SyncObject[], ctx: Ctx): Record<Kind, string[]> {
  const out: Record<Kind, string[]> = { crypto: [], us: [], com: [], idx: [] }
  for (const o of liveSorted(all)) {
    const k = favKind(o, ctx)
    const s = str(o.body.symbol)
    if (k && s && !out[k].includes(s)) out[k].push(s)
  }
  return out
}

// ═════════════════════════════ drawings ═════════════════════════════

// 网页工具 ↔ 手机 Drawing.Kind 的 rawValue；锚点数必须等于契约 drawing-fields.json 的 anchorCounts（tests/sync-codec 对账）。
// 多空持仓的三个锚点照手机：入场、目标、止损；固定区间成交量分布两点只用时间；锚定 VWAP 一点只用时间。
export const KIND_OF: Partial<Record<DrawingType, string>> = { trend: 'trend', ray: 'ray', hline: 'hline', vline: 'vline', rect: 'rectangle', fib: 'fibonacci', avwap: 'anchoredVWAP', fvp: 'fixedVolumeProfile', position: 'position' }
const TYPE_OF: Record<string, DrawingType> = { trend: 'trend', ray: 'ray', hline: 'hline', vline: 'vline', rectangle: 'rect', fibonacci: 'fib', anchoredVWAP: 'avwap', fixedVolumeProfile: 'fvp', position: 'position' }
export const ANCHORS: Record<string, number> = { hline: 1, vline: 1, trend: 2, ray: 2, rectangle: 2, fibonacci: 2, anchoredVWAP: 1, fixedVolumeProfile: 2, position: 3 }
/** 网页写进 body 的键（对账用：必须是契约 syncFields 的子集） */
export const WEB_BODY_KEYS = ['anchors', 'color', 'dash', 'filled', 'hidden', 'kind', 'levels', 'lineWidth', 'locked', 'market', 'symbol', 'venue'] as const
/** 手机 `Drawing` 的出厂值（Drawing.swift） */
export const DRAWING_DEFAULTS = { dash: 'solid', filled: true, hidden: false, levels: [0, 0.236, 0.382, 0.5, 0.618, 0.786, 1] as number[] }
export const WEB_LINE_WIDTH = 2
const HEX = /^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/

export const drawingId = (symbol: string, id: string): string => prefixOf(symbol) + id

/** 网页画线的规范形（比对用） */
function normDrawing(d: Drawing): Json {
  return { type: d.type, pts: d.pts.map(p => ({ t: p.t, p: p.p })), color: d.color && HEX.test(d.color) ? d.color : null, width: d.width ?? WEB_LINE_WIDTH, dash: d.dash ?? 'solid', locked: !!d.locked }
}

/** 这条云端画线网页管不管得着：币安 U 本位、网页有的种类、没隐藏、锚点数对 */
export function drawingManaged(o: SyncObject): boolean {
  const b = o.body
  const kind = str(b.kind)
  if (!kind || !TYPE_OF[kind]) return false
  const s = str(b.symbol)
  if (!s || !venueOk(b, s) || !o.id.startsWith(prefixOf(s))) return false
  if (b.hidden === true) return false
  const anchors = Array.isArray(b.anchors) ? b.anchors : null
  return !!anchors && anchors.length === ANCHORS[kind]
}

export function decodeDrawing(o: SyncObject): { symbol: string; d: Drawing } | null {
  if (!drawingManaged(o)) return null
  const b = o.body
  const pts: DrawPoint[] = []
  for (const a of b.anchors as Json[]) {
    const t = num(obj(a)?.t), p = num(obj(a)?.p)
    if (t == null || p == null) return null
    pts.push({ t, p })
  }
  const color = str(obj(b.color)?.value)
  const d: Drawing = { id: lastSeg(o.id), type: TYPE_OF[str(b.kind)!], pts }
  if (color && HEX.test(color)) d.color = color
  const w = num(b.lineWidth)
  d.width = w ?? WEB_LINE_WIDTH
  if (b.dash === 'dashed' || b.dash === 'dotted') d.dash = b.dash
  if (b.locked === true) d.locked = true
  return { symbol: str(b.symbol)!, d }
}

function encodeDrawing(symbol: string, d: Drawing, prev: SyncObject | undefined): SyncObject | null {
  const kind = KIND_OF[d.type]
  if (!kind || !webSymbol(symbol) || d.pts.length !== ANCHORS[kind] || !d.id || d.id.includes('/')) return null
  if (!d.pts.every(p => isFinite(p.t) && isFinite(p.p))) return null
  const id = drawingId(symbol, d.id)
  const live = prev && !prev.deleted ? prev : undefined
  if (live) {
    const was = decodeDrawing(live)
    if (was && was.symbol === symbol && same(normDrawing(was.d), normDrawing(d))) return { ...live, body: { ...live.body } }
  }
  const body: Body = { ...(live?.body ?? {}) }
  if (!live) Object.assign(body, { dash: DRAWING_DEFAULTS.dash, filled: DRAWING_DEFAULTS.filled, hidden: DRAWING_DEFAULTS.hidden, levels: [...DRAWING_DEFAULTS.levels] })
  body.kind = kind
  body.anchors = d.pts.map(p => ({ t: p.t, p: p.p }))
  body.color = d.color && HEX.test(d.color) ? { value: d.color } : null
  body.lineWidth = Math.min(6, Math.max(0.5, d.width ?? WEB_LINE_WIDTH))
  body.dash = d.dash ?? 'solid'
  body.locked = !!d.locked
  const vm = venueMarketOf(symbol)
  body.symbol = symbol; body.market = vm.market; body.venue = vm.venue
  return { collection: 'drawings', id, body, fields: {}, revision: 0, deleted: false, generation: 0 }
}

/** 网页画线 → 要记账的对象（含删除）。只动网页管得着的那部分。
 *  `holdDeletes`：本地画线存档读坏过（解析失败、形状不对被清空）时，本地「没有」不代表用户删了——
 *  这时只推新增与修改、一条删除都不发，免得拿一份空表把云端整只品种的画线清掉 */
export function encodeDrawings(drawings: Record<string, Drawing[]>, prevAll: SyncObject[], opts: { holdDeletes?: boolean } = {}): SyncObject[] {
  const byId = new Map(prevAll.map(o => [o.id, o]))
  const out: SyncObject[] = []
  const keep = new Set<string>()
  for (const [symbol, list] of Object.entries(drawings)) {
    for (const d of list) {
      const o = encodeDrawing(symbol, d, byId.get(drawingId(symbol, d.id)))
      if (!o || keep.has(o.id)) continue
      keep.add(o.id); out.push(o)
    }
  }
  if (!opts.holdDeletes) for (const o of prevAll) if (!o.deleted && !keep.has(o.id) && drawingManaged(o)) out.push({ ...o, deleted: true })
  return out
}

/** 云端画线装进网页：网页管不着的本地画线（量测、代号不合规的）原样留着，其余按云端来；
 *  已有画线保持原来的先后，新来的接在后面 */
export function decodeDrawings(all: SyncObject[], current: Record<string, Drawing[]>): Record<string, Drawing[]> {
  const cloud = new Map<string, Map<string, Drawing>>()
  for (const o of all) {
    if (o.deleted) continue
    const x = decodeDrawing(o)
    if (!x) continue
    let m = cloud.get(x.symbol); if (!m) cloud.set(x.symbol, m = new Map())
    m.set(x.d.id, x.d)
  }
  const out: Record<string, Drawing[]> = {}
  for (const s of new Set([...Object.keys(current), ...cloud.keys()])) {
    const m = cloud.get(s) ?? new Map<string, Drawing>()
    const list: Drawing[] = []
    for (const d of current[s] ?? []) {
      if (!syncableDrawing(s, d)) { list.push(d); continue }
      const c = m.get(d.id)
      if (c) { list.push(same(normDrawing(c), normDrawing(d)) ? d : c); m.delete(d.id) }
    }
    list.push(...m.values())
    if (list.length || current[s]) out[s] = list
  }
  return out
}

export function syncableDrawing(symbol: string, d: Drawing): boolean {
  const kind = KIND_OF[d.type]
  return !!kind && webSymbol(symbol) && d.pts.length === ANCHORS[kind] && !!d.id && !d.id.includes('/')
}

// ═════════════════════════════ alerts ═════════════════════════════
//
// 网页的提醒本来就是同步形状（alerts/shape.ts，19 个字段），一条提醒 = 一个对象，
// 身体 = 这 19 个键（照手机 `Alert.encode(to:)`：可空的九个空就写 null，不省略）。
// 只有两处换算：
// - 对象 id：`${market}/${symbol}/${id}`（和手机 `PersonalSyncCodec.alerts` 一样）。
// - 画线提醒的 `drawingID`：线上是画线自己的 id（手机 AlertStore 写的是 `drawing.id`），
//   网页本机存的是画线对象 id（`binance/usd_m/SYM/<id>`，alerts/shape.ts 的 drawingIdOf），进出时加减前缀。
// 网页只替「币安 U 本位、还在等（active）的价格 / 画线 / 条件提醒」说话；已触发的、暂停的、
// 复盘到期的、Coinbase 的不删不改不显示。

export const ALERT_KEYS = ['kind', 'market', 'symbol', 'lines', 'condition', 'status', 'once', 'armedAt', 'firedAt', 'firedPrice',
  'title', 'note', 'webhook', 'webhookText', 'drawingID', 'reviewID', 'dueAt', 'rule', 'created'] as const
export const alertId = (symbol: string, id: string): string => prefixOf(symbol) + id

const DECIMAL = /^-?\d+(\.\d+)?$/
function decIn(v: unknown, lo: number, hi: number): boolean {
  return typeof v === 'string' && DECIMAL.test(v) && +v >= lo && +v <= hi
}
/** 服务端 `conditions::Rule::parse` 收不收（认不得的 type 服务端也收，只要是纯字母）。
 *  技术指标条件（`{kind:'ma_cross'|'rsi_level'|'bar_breakout',…}`，没有 type）按约定的线格式严格校验：
 *  不合格的不上云，合格的照推——服务端还不认时回 400，同步层把这一条单独隔开、过几分钟再推（见 alerts/indicator.ts） */
export function ruleOk(r: Alert['rule']): boolean {
  if (isIndicatorRule(r)) return indicatorRuleOk(r)
  if (!r || typeof r !== 'object' || typeof r.type !== 'string' || !/^[A-Za-z]{1,40}$/.test(r.type)) return false
  const o = r as Record<string, unknown>
  if (r.type === 'funding') return (o.side === 'above' || o.side === 'below') && decIn(o.rate, -0.1, 0.1)
  if (r.type === 'openInterestChange') return decIn(o.threshold, 0.001, 10)
  if (r.type === 'orderflowWall') return decIn(o.threshold, 1e4, 1e10)
  if (r.type === 'maCross') return typeof o.interval === 'string' && Number.isInteger(o.length) && (o.side === 'above' || o.side === 'below')
  return true
}

/** 这条网页提醒能不能上云（身份合规、形状过得了服务端 sync_validation） */
export function syncableAlert(a: Alert): boolean { return a.status === 'active' && alertShapeOk(a) }
/** 记账时还认刚响的那一下（`active → fired`，照手机 markFired 先推一次已触发，服务端据此发 Webhook） */
export function encodableAlert(a: Alert): boolean { return (a.status === 'active' || a.status === 'fired') && alertShapeOk(a) }
function alertShapeOk(a: Alert): boolean {
  if (!webSymbol(a.symbol) || a.market !== alertMarketOf(a.symbol) || !a.id || a.id.includes('/')) return false
  // 美元指数只有价格 / 画线提醒（服务端白名单不收条件提醒）
  if (isMacro(a.symbol) && a.kind !== 'price' && a.kind !== 'drawing') return false
  if (a.kind === 'price' || a.kind === 'drawing') {
    if (!a.lines.length || !a.lines.every(l => l.points.length && l.points.every(p => isFinite(p.t) && isFinite(p.p)))) return false
    if (a.kind === 'drawing' && !a.drawingID) return false
    return true
  }
  if (a.kind === 'condition') return ruleOk(a.rule)
  return false
}

const wireDrawingId = (a: Alert): string | null => {
  const pre = prefixOf(a.symbol)
  return a.drawingID && a.drawingID.startsWith(pre) ? a.drawingID.slice(pre.length) : a.drawingID
}
/** 网页提醒 → 线上身体（19 个键） */
export function alertToBody(a: Alert): Body {
  const b: Body = {}
  for (const k of ALERT_KEYS) b[k] = (k === 'drawingID' ? wireDrawingId(a) : a[k]) as Json
  return JSON.parse(JSON.stringify(b)) as Body
}

/** 画线提醒的状态在云端是 `paused`（老版本「线找不到」时暂停的）：网页一律当生效的装进来。
 *  2026-10-06 起提醒不再依附画线（用户：「画线和警报是不冲突的，我删除画线也不应该删除警报才对」），
 *  线删了、藏了、网页认不出那种工具，提醒都照自己的 lines 判；记账时把它推回 `active`（encodeAlerts） */
const revivable = (b: Body): boolean => b.kind === 'drawing' && b.status === 'paused'
/** 云端有没有还暂停着的画线提醒（有就要再记一次账，把它推回生效） */
export function pausedLineAlerts(all: SyncObject[]): boolean {
  return all.some(o => o.collection === 'alerts' && !o.deleted && revivable(o.body))
}

/** 云端提醒 → 网页提醒；网页管不着的返回 null。`fired`：已触发的也解（记账比对、同步下来的「服务端响了」）。
 *  挂在哪条线上都不影响解不解：线不在、网页认不出那条线，提醒照样装进来（照它自己的 lines 判、在图上画提醒线） */
export function decodeAlert(o: SyncObject, fired = false): Alert | null {
  const b = o.body
  if (o.deleted || !(b.status === 'active' || revivable(b) || (fired && b.status === 'fired'))) return null
  if (b.kind !== 'price' && b.kind !== 'drawing' && b.kind !== 'condition') return null
  const symbol = str(b.symbol)
  if (!symbol || !webSymbol(symbol) || b.market !== alertMarketOf(symbol) || !o.id.startsWith(prefixOf(symbol))) return null
  const raw: Record<string, unknown> = { id: lastSeg(o.id) }
  for (const k of ALERT_KEYS) if (k in b) raw[k] = structuredClone(b[k])
  if (revivable(b)) raw.status = 'active'
  if (!Array.isArray(raw.lines)) raw.lines = []
  const did = str(b.drawingID)
  raw.drawingID = did ? (did.includes('/') ? did : prefixOf(symbol) + did) : null
  const a = migrateAlert(raw)
  return a && a.symbol === symbol ? a : null
}

const normAlert = (a: Alert): Json => alertToBody(a)

/** 网页提醒 → 要记账的对象（含删除）。只动网页管得着的那部分。
 *  `spent`：这个网页已经报过的已触发（本机响的、同步下来服务端响的）——只有这些已触发的会被删；
 *  没报过的已触发留给报它的那台设备去删（照手机 AlertWatcher：报完才 purgeFired），不抢先删掉 */
export function encodeAlerts(alerts: Alert[], prevAll: SyncObject[], spent?: ReadonlySet<string>, now = Date.now()): SyncObject[] {
  const out: SyncObject[] = []
  const byId = new Map(prevAll.map(o => [o.id, o]))
  const local = new Set<string>()
  for (const a of alerts) {
    const id = alertId(a.symbol, a.id)
    if (local.has(id)) continue
    local.add(id)
    if (!encodableAlert(a)) continue
    const prev = byId.get(id)
    const live = prev && !prev.deleted ? prev : undefined
    // 已触发的不再往回改成 active（服务端先响了、本机这份还没装进来：以云端为准）
    if (a.status === 'active' && live?.body.status === 'fired') continue
    const was = live ? decodeAlert(live, true) : null
    const paused = !!live && revivable(live.body)
    if (live && was && !paused && same(normAlert(was), normAlert(a))) { out.push({ ...live, body: { ...live.body } }); continue }
    const body: Body = { ...(live?.body ?? {}), ...alertToBody(a) }
    // 云端暂停着的画线提醒推回生效：从这一刻起算（暂停那段不补判，照 iOS reconcile 线回来时重置 armedAt）
    if (paused && a.status === 'active' && same(normAlert(was!), normAlert(a))) body.armedAt = Math.max(a.armedAt, now)
    out.push({ collection: 'alerts', id, body, fields: {}, revision: 0, deleted: false, generation: 0 })
  }
  // 删除：网页管得着、本机已经没有这一条了（响过、用户在提醒表里删掉）。本机还在只是暂时上不了云的不删。
  // 画线删了不在此列：提醒不跟着线走，本机表里还留着它
  for (const o of prevAll) {
    if (o.deleted || local.has(o.id)) continue
    if (decodeAlert(o) || (o.body.status === 'fired' && spent?.has(o.id) && decodeAlert(o, true))) out.push({ ...o, deleted: true })
  }
  return out
}

/** 云端提醒装进网页：本机上不了云的那几条原样留着，其余按云端来，保持原来的先后 */
export function decodeAlerts(all: SyncObject[], current: Alert[]): Alert[] {
  const cloud = new Map<string, Alert>()
  for (const o of all) { const a = decodeAlert(o); if (a) cloud.set(o.id, a) }
  const list: Alert[] = []
  for (const a of current) {
    const id = alertId(a.symbol, a.id)
    const c = cloud.get(id)
    if (c) { list.push(same(normAlert(c), normAlert(a)) ? a : c); cloud.delete(id); continue }
    if (!syncableAlert(a)) list.push(a)
  }
  list.push(...cloud.values())
  return list
}
