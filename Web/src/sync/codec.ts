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
import type { Drawing, DrawingType, DrawPoint } from '../chart/chart'
import { MAX_SUBS, type IndParams, type SubId } from '../chart/calc'
import { INTERVALS, type Kind } from '../market/symbols'
import { type Body, type Json, type SyncObject, same } from './types'

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
const PREFIX = `${VENUE}/${MARKET}/`

/** 服务端 `sync_validation.rs` 的币安代号规则 */
export function validSymbol(s: string): boolean {
  if (!s || s.length > 40) return false
  if (!/^[A-Z0-9]+$/.test(s)) return false
  return /(USDT|USDC|FDUSD|BUSD|USD1|TUSD)$/.test(s)
}
/** 标题里用的品种名：去掉计价币（和手机 `Alert.base(of:)` 一致） */
export function baseName(s: string): string { return s.replace(/(USDT|USDC|FDUSD|BUSD|USD1|TUSD)$/, '') || s }

const lastSeg = (id: string): string => id.slice(id.lastIndexOf('/') + 1)
const num = (v: Json | undefined): number | null => typeof v === 'number' && isFinite(v) ? v : null
const str = (v: Json | undefined): string | null => typeof v === 'string' ? v : null
const obj = (v: Json | undefined): Record<string, Json> | null => v && typeof v === 'object' && !Array.isArray(v) ? v : null

// ═════════════════════════════ settings（id "chart"） ═════════════════════════════
//
// 网页只同步和手机同一回事的那几项：钉在周期条上的周期、主图 / 副图开了哪些指标、指标参数。
// 皮肤 / 深浅 / 涨跌色是网页自己的一套视觉（和手机不是一回事），线路是每台设备自己的，
// 当前周期是「每个图格一个」而手机是「整个 app 一个」，这几项不同步。
//
// 设置对象手机端有几十个字段，网页只认其中几个，所以按字段记一份 `seen`：
// 「这个字段上一次和云端对上时网页这边是什么样」。网页值 ≠ seen → 网页改了，推；
// 云端解码值 ≠ seen → 云端改了，装。云端的值网页表达不了（比如 3 日线）时 seen 记成网页现值，
// 不推也不装，免得网页一碰就把手机的值冲掉。

export interface SettingsState { pinned: string[]; ind: IndState; params: Record<string, IndParams> | null }

export const SETTINGS_ID = 'chart'
const PARAM_IDS: [string, string][] = [['ma', 'MA'], ['ema', 'EMA'], ['boll', 'BOLL'], ['macd', 'MACD'], ['rsi', 'RSI'], ['kdj', 'KDJ']]
export const SETTINGS_FIELDS = ['quickIntervals', 'overlays', 'subs', ...PARAM_IDS.map(([, p]) => 'params/' + p)]
const OVERLAY_MAP: [keyof IndState & ('ma' | 'ema' | 'boll'), string][] = [['ma', 'MA'], ['ema', 'EMA'], ['boll', 'BOLL']]
const SUB_MAP: [string, string][] = [['vol', 'VOL'], ['macd', 'MACD'], ['rsi', 'RSI'], ['kdj', 'KDJ'], ['oi', 'OI']]

/** 网页那一侧某个字段的规范值（seen 里存的就是这个） */
export function webSetting(s: SettingsState, field: string): Json {
  if (field === 'quickIntervals') return INTERVALS.filter(iv => s.pinned.includes(iv))
  if (field === 'overlays') return OVERLAY_MAP.filter(([w]) => s.ind[w]).map(([, c]) => c)
  if (field === 'subs') return [...(s.ind.vol ? ['VOL'] : []), ...s.ind.subs.map(x => SUB_MAP.find(([w]) => w === x)?.[1]).filter((x): x is string => !!x)]
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
  else if (field === 'overlays') for (const [w, c] of OVERLAY_MAP) s.ind[w] = list.includes(c)
  else if (field === 'subs') {
    s.ind.vol = list.includes('VOL')
    s.ind.subs = list.map(c => SUB_MAP.find(([, x]) => x === c)?.[0]).filter((x): x is SubId => !!x && x !== 'vol').slice(0, MAX_SUBS)
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

/** 应用：云端值和 seen 不同的字段写回状态。返回改了哪些字段 */
export function applySettings(s: SettingsState, cloud: SyncObject | undefined, seen: Record<string, Json>): string[] {
  if (!cloud || cloud.deleted) return []
  const changed: string[] = []
  for (const f of SETTINGS_FIELDS) {
    const d = decodeSetting(f, cloud.body[f], s)
    if (d === undefined) {
      // 云端这个字段网页表达不了：记成网页现值，免得下一次捕获把它当成网页改过的推上去
      if (!(f in seen)) seen[f] = webSetting(s, f)
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

export const favId = (symbol: string): string => PREFIX + symbol
const KIND_ORDER: Kind[] = ['crypto', 'us', 'com']

function liveSorted(objs: SyncObject[]): SyncObject[] {
  return objs.filter(o => !o.deleted).sort((a, b) => (num(a.body.order) ?? 0) - (num(b.body.order) ?? 0) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
}
/** 网页管得着的自选：币安 U 本位、在品种表里 */
function favKind(o: SyncObject, ctx: Ctx): Kind | undefined {
  if (o.body.venue !== VENUE || o.body.market !== MARKET) return undefined
  const s = str(o.body.symbol)
  if (!s || o.id !== favId(s)) return undefined
  return ctx.kindOf(s)
}

/** 网页自选 → 要记账的对象（含删除）。品种表还没到时返回空：分不出类别就不动 */
export function encodeFavorites(watch: Record<Kind, string[]>, prevAll: SyncObject[], ctx: Ctx): SyncObject[] {
  const prev = liveSorted(prevAll)
  // 云端有、网页分不出类别的（Coinbase、表里没有的）原地留着；网页那边同名的不再重复排
  const pinnedIds = new Set(prev.filter(o => !favKind(o, ctx)).map(o => o.id))
  const seen = new Set<string>()
  const queues = new Map<Kind, string[]>()
  for (const k of KIND_ORDER) {
    queues.set(k, (watch[k] ?? []).filter(s => validSymbol(s) && !pinnedIds.has(favId(s)) && !seen.has(s) && (seen.add(s), true)))
  }
  const seq: { id: string; symbol: string | null; prev?: SyncObject }[] = []
  const byId = new Map(prevAll.map(o => [o.id, o]))
  for (const o of prev) {
    const k = favKind(o, ctx)
    if (!k) { seq.push({ id: o.id, symbol: null, prev: o }); continue }
    const next = queues.get(k)!.shift()
    if (next !== undefined) seq.push({ id: favId(next), symbol: next, prev: byId.get(favId(next)) })
  }
  for (const k of KIND_ORDER) for (const s of queues.get(k)!) seq.push({ id: favId(s), symbol: s, prev: byId.get(favId(s)) })
  const unchanged = seq.length === prev.length && seq.every((x, i) => x.id === prev[i].id)
  const out: SyncObject[] = []
  const keep = new Set(seq.map(x => x.id))
  seq.forEach((x, i) => {
    const order = unchanged ? (num(x.prev?.body.order) ?? i) : i
    const base = x.prev && !x.prev.deleted ? x.prev.body : null
    const body: Body = x.symbol == null
      ? { ...(base ?? {}), order }
      : { symbol: x.symbol, market: MARKET, venue: VENUE, groupId: base && 'groupId' in base ? base.groupId : null, order }
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
  const out: Record<Kind, string[]> = { crypto: [], us: [], com: [] }
  for (const o of liveSorted(all)) {
    const k = favKind(o, ctx)
    const s = str(o.body.symbol)
    if (k && s && !out[k].includes(s)) out[k].push(s)
  }
  return out
}

// ═════════════════════════════ drawings ═════════════════════════════

const KIND_OF: Partial<Record<DrawingType, string>> = { trend: 'trend', ray: 'ray', hline: 'hline', vline: 'vline', rect: 'rectangle', fib: 'fibonacci' }
const TYPE_OF: Record<string, DrawingType> = { trend: 'trend', ray: 'ray', hline: 'hline', vline: 'vline', rectangle: 'rect', fibonacci: 'fib' }
const ANCHORS: Record<string, number> = { hline: 1, vline: 1, trend: 2, ray: 2, rectangle: 2, fibonacci: 2 }
/** 手机 `Drawing` 的出厂值（Drawing.swift） */
export const DRAWING_DEFAULTS = { dash: 'solid', filled: true, hidden: false, levels: [0, 0.236, 0.382, 0.5, 0.618, 0.786, 1] as number[] }
export const WEB_LINE_WIDTH = 2
const HEX = /^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/

export const drawingId = (symbol: string, id: string): string => PREFIX + symbol + '/' + id

/** 网页画线的规范形（比对用） */
function normDrawing(d: Drawing): Json {
  return { type: d.type, pts: d.pts.map(p => ({ t: p.t, p: p.p })), color: d.color && HEX.test(d.color) ? d.color : null, width: d.width ?? WEB_LINE_WIDTH, locked: !!d.locked }
}

/** 这条云端画线网页管不管得着：币安 U 本位、网页有的种类、没隐藏、锚点数对 */
export function drawingManaged(o: SyncObject): boolean {
  const b = o.body
  const kind = str(b.kind)
  if (!kind || !TYPE_OF[kind]) return false
  if (b.venue !== VENUE || b.market !== MARKET) return false
  const s = str(b.symbol)
  if (!s || !o.id.startsWith(PREFIX + s + '/')) return false
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
  if (b.locked === true) d.locked = true
  return { symbol: str(b.symbol)!, d }
}

function encodeDrawing(symbol: string, d: Drawing, prev: SyncObject | undefined): SyncObject | null {
  const kind = KIND_OF[d.type]
  if (!kind || !validSymbol(symbol) || d.pts.length !== ANCHORS[kind] || !d.id || d.id.includes('/')) return null
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
  body.locked = !!d.locked
  body.symbol = symbol; body.market = MARKET; body.venue = VENUE
  return { collection: 'drawings', id, body, fields: {}, revision: 0, deleted: false, generation: 0 }
}

/** 网页画线 → 要记账的对象（含删除）。只动网页管得着的那部分 */
export function encodeDrawings(drawings: Record<string, Drawing[]>, prevAll: SyncObject[]): SyncObject[] {
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
  for (const o of prevAll) if (!o.deleted && !keep.has(o.id) && drawingManaged(o)) out.push({ ...o, deleted: true })
  return out
}

/** 云端画线装进网页：网页管不着的本地画线（量测、代号不合规的）原样留着，其余按云端来；
 *  已有画线保持原来的先后，新来的接在后面 */
export function decodeDrawings(all: SyncObject[], current: Record<string, Drawing[]>, alertOn: Set<string>): Record<string, Drawing[]> {
  const cloud = new Map<string, Map<string, Drawing>>()
  for (const o of all) {
    if (o.deleted) continue
    const x = decodeDrawing(o)
    if (!x) continue
    if (alertOn.has(drawingId(x.symbol, x.d.id)) && ALERTABLE.has(x.d.type)) x.d.alert = true
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
      if (c) { list.push(same(normDrawing(c), normDrawing(d)) && !!c.alert === !!d.alert ? d : c); m.delete(d.id) }
    }
    list.push(...m.values())
    if (list.length || current[s]) out[s] = list
  }
  return out
}

export function syncableDrawing(symbol: string, d: Drawing): boolean {
  const kind = KIND_OF[d.type]
  return !!kind && validSymbol(symbol) && d.pts.length === ANCHORS[kind] && !!d.id && !d.id.includes('/')
}

// ═════════════════════════════ alerts ═════════════════════════════

/** 网页能开提醒的画线种类（chart.ts 的 linePriceAt 只认这三种） */
export const ALERTABLE = new Set<DrawingType>(['hline', 'trend', 'ray'])
const LINE_TITLE: Record<string, string> = { hline: '水平线', trend: '趋势线', ray: '向右延伸', rect: '矩形', fib: '斐波那契回撤', vline: '垂直线' }
export const alertId = (symbol: string, id: string): string => PREFIX + symbol + '/' + id

interface AlertLineJ { points: { t: number; p: number }[]; extendLeft: boolean; extendRight: boolean }
/** AlertGeometry.lines(for:)：网页四种能画的种类 */
export function alertLines(d: Drawing): AlertLineJ[] | null {
  const [a, b] = d.pts
  if (!a) return null
  const L = (points: DrawPoint[], extendLeft = false, extendRight = false): AlertLineJ => ({ points: points.map(p => ({ t: p.t, p: p.p })), extendLeft, extendRight })
  switch (d.type) {
    case 'hline': return [L([a], true, true)]
    case 'trend': return b ? [L([a, b])] : null
    case 'ray': return b ? [L([a, b], false, true)] : null
    case 'rect': {
      if (!b) return null
      const t0 = Math.min(a.t, b.t), t1 = Math.max(a.t, b.t), top = Math.max(a.p, b.p), bottom = Math.min(a.p, b.p)
      return [L([{ t: t0, p: top }, { t: t1, p: top }]), L([{ t: t0, p: bottom }, { t: t1, p: bottom }])]
    }
    case 'fib': {
      if (!b) return null
      const t0 = Math.min(a.t, b.t), t1 = Math.max(a.t, b.t)
      const out = DRAWING_DEFAULTS.levels.map(l => b.p + (a.p - b.p) * l).filter(isFinite).map(v => L([{ t: t0, p: v }, { t: t1, p: v }]))
      return out.length ? out.slice(0, 32) : null
    }
  }
  return null
}

/** AlertRule.percent：比值 × 100，四舍五入到 dp 位，去掉尾巴上的 0 */
export function percent(ratio: number, dp: number): string {
  const v = Math.round(ratio * 100 * 10 ** dp) / 10 ** dp
  return trimDec(v.toFixed(dp))
}
function trimDec(s: string): string { return s.includes('.') ? s.replace(/0+$/, '').replace(/\.$/, '') : s }
/** 网页的百分数 → 服务端的十进制比值串（"0.05" → "0.0005"），不经过浮点除法 */
export function pctToRatio(v: number): string {
  const neg = v < 0
  const [i, f = ''] = Math.abs(v).toFixed(8).split('.')
  const digits = (i.padStart(3, '0') + f)
  const cut = digits.length - f.length - 2
  const s = trimDec(digits.slice(0, cut).replace(/^0+(?=\d)/, '') + '.' + digits.slice(cut))
  return (neg && s !== '0' ? '-' : '') + s
}
export const ratioToPct = (r: string): number => Math.round(parseFloat(r) * 100 * 1e8) / 1e8

const FUNDING_MAX = 0.1, OI_MIN = 0.001, OI_MAX = 10

/** 网页提醒的规范形（比对用） */
function normAlert(a: Alert): Json {
  const base = { symbol: a.symbol, kind: a.kind, webhook: a.webhook ?? null }
  if (a.kind === 'price') return { ...base, price: a.price ?? null, dir: (a.dir ?? 1) >= 0 ? 1 : -1 }
  if (a.kind === 'fr') return { ...base, value: a.value ?? null, op: a.op === 'lt' ? 'lt' : 'gt' }
  return { ...base, value: a.value ?? null }
}

/** 这条网页提醒能不能上云（代号合规、数值在服务端允许的范围里） */
export function syncableAlert(a: Alert): boolean {
  if (!validSymbol(a.symbol) || !a.id || a.id.includes('/')) return false
  if (a.kind === 'price') return a.price != null && isFinite(a.price) && a.price > 0
  if (a.kind === 'fr') return a.value != null && isFinite(a.value) && Math.abs(parseFloat(pctToRatio(a.value))) <= FUNDING_MAX
  if (a.kind === 'oi') { if (a.value == null || !isFinite(a.value)) return false; const r = parseFloat(pctToRatio(a.value)); return r >= OI_MIN && r <= OI_MAX }
  return false
}

const validWebhook = (w: string | null | undefined): string | null => {
  const t = (w ?? '').trim()
  return /^https?:\/\/\S+$/i.test(t) ? t : null
}

/** 云端提醒 → 网页提醒；网页管不着的返回 null */
export function decodeAlert(o: SyncObject, ctx: Ctx): Alert | null {
  const b = o.body
  if (o.deleted || b.status !== 'active' || b.market !== ALERT_MARKET) return null
  const symbol = str(b.symbol)
  if (!symbol || !o.id.startsWith(PREFIX + symbol + '/')) return null
  const created = num(b.created) ?? 0
  const webhook = str(b.webhook)
  const base = { id: lastSeg(o.id), symbol, created, webhook: webhook ?? null }
  const rule = obj(b.rule)
  if (b.kind === 'price' && !rule) {
    if (b.condition !== 'touch') return null
    const line = obj((b.lines as Json[] | undefined)?.[0])
    const p = num(obj((line?.points as Json[] | undefined)?.[0])?.p)
    if (p == null || !(p > 0)) return null
    const title = str(b.title) ?? ''
    let dir = title.includes('涨到') ? 1 : title.includes('跌到') ? -1 : 0
    if (!dir) { const cur = ctx.price(symbol); dir = cur != null && cur > 0 ? (p >= cur ? 1 : -1) : 1 }
    return { ...base, kind: 'price', price: p, dir }
  }
  if (b.kind === 'condition' && rule) {
    if (rule.type === 'funding') {
      const rate = str(rule.rate), side = rule.side
      if (rate == null || (side !== 'above' && side !== 'below')) return null
      return { ...base, kind: 'fr', value: ratioToPct(rate), op: side === 'below' ? 'lt' : 'gt' }
    }
    if (rule.type === 'openInterestChange') {
      const th = str(rule.threshold)
      if (th == null) return null
      return { ...base, kind: 'oi', value: ratioToPct(th), op: 'gt' }
    }
  }
  return null
}

/** 云端的画线提醒：活着、指向一条画线。返回画线的对象 id */
export function drawingAlertTarget(o: SyncObject): string | null {
  const b = o.body
  if (o.deleted || b.kind !== 'drawing' || b.status !== 'active' || b.market !== ALERT_MARKET) return null
  const symbol = str(b.symbol), did = str(b.drawingID)
  if (!symbol || !did || !o.id.startsWith(PREFIX + symbol + '/')) return null
  return drawingId(symbol, did)
}

function alertBody(prev: Body | null, over: Body): Body {
  const body: Body = {
    kind: 'price', symbol: '', market: ALERT_MARKET, drawingID: null, lines: [], condition: 'touch', armedAt: 0, once: true,
    status: 'active', firedAt: null, firedPrice: null, dueAt: null, reviewID: null, title: '', created: 0,
    note: null, webhook: null, webhookText: null, rule: null,
  }
  if (prev) for (const k of ['armedAt', 'note', 'webhookText', 'created'] as const) if (k in prev) body[k] = prev[k]
  return Object.assign(body, over)
}

export interface AlertInputs {
  alerts: Alert[]
  drawings: Record<string, Drawing[]>
  /** 本机账本里画线那张表（判断「画线提醒指向的线网页管不管得着」） */
  drawingObjs: SyncObject[]
}

/** 网页提醒（价格 / 资金费率 / 持仓量 + 画线上的提醒开关）→ 要记账的对象（含删除） */
export function encodeAlerts(inp: AlertInputs, prevAll: SyncObject[], ctx: Ctx): SyncObject[] {
  const out: SyncObject[] = []
  const keep = new Set<string>()
  const byId = new Map(prevAll.map(o => [o.id, o]))
  const now = ctx.now()
  for (const a of inp.alerts) {
    if (!syncableAlert(a)) continue
    const id = alertId(a.symbol, a.id)
    if (keep.has(id)) continue
    const prev = byId.get(id)
    const live = prev && !prev.deleted ? prev : undefined
    keep.add(id)
    const was = live ? decodeAlert(live, ctx) : null
    if (live && was && same(normAlert(was), normAlert(a))) { out.push({ ...live, body: { ...live.body } }); continue }
    const name = baseName(a.symbol)
    const webhook = validWebhook(a.webhook)
    let over: Body
    if (a.kind === 'price') {
      const dir = (a.dir ?? 1) >= 0 ? 1 : -1
      const sameMeaning = was?.kind === 'price' && was.price === a.price && (was.dir ?? 1) === dir
      over = {
        kind: 'price', symbol: a.symbol, lines: [{ points: [{ t: a.created, p: a.price! }], extendLeft: true, extendRight: true }],
        title: sameMeaning && live ? live.body.title : `${name} ${dir > 0 ? '涨到' : '跌到'} ${ctx.label(a.symbol, a.price!)}`,
        created: a.created, webhook, rule: null,
      }
    } else if (a.kind === 'fr') {
      const rate = pctToRatio(a.value!), side = a.op === 'lt' ? 'below' : 'above'
      over = { kind: 'condition', symbol: a.symbol, lines: [], rule: { type: 'funding', side, rate }, title: `${name} 资金费率${side === 'above' ? '高于' : '低于'} ${percent(parseFloat(rate), 6)}%`, created: a.created, webhook }
    } else {
      const th = pctToRatio(a.value!)
      over = { kind: 'condition', symbol: a.symbol, lines: [], rule: { type: 'openInterestChange', threshold: th }, title: `${name} 1 小时持仓量变化超过 ${percent(parseFloat(th), 4)}%`, created: a.created, webhook }
    }
    const body = alertBody(live?.body ?? null, over)
    if (!live || !('armedAt' in live.body)) body.armedAt = a.created
    out.push({ collection: 'alerts', id, body, fields: {}, revision: 0, deleted: false, generation: 0 })
  }
  // 画线提醒：一条画线最多一条活着的提醒；已有的就沿用它的 id（可能是手机建的）
  const existing = new Map<string, SyncObject>()
  for (const o of prevAll) { const t = drawingAlertTarget(o); if (t && !existing.has(t)) existing.set(t, o) }
  for (const [symbol, list] of Object.entries(inp.drawings)) {
    for (const d of list) {
      if (!d.alert || !ALERTABLE.has(d.type) || !syncableDrawing(symbol, d)) continue
      const target = drawingId(symbol, d.id)
      const prev = existing.get(target)
      const id = prev?.id ?? alertId(symbol, 'a' + d.id)
      if (keep.has(id)) continue
      keep.add(id)
      const lines = alertLines(d)
      if (!lines) continue
      const over: Body = { kind: 'drawing', symbol, drawingID: d.id, lines: lines as unknown as Json, title: `${baseName(symbol)} 触到你画的${LINE_TITLE[d.type] ?? '线'}`, rule: null }
      if (prev && same(prev.body.lines, over.lines) && prev.body.drawingID === d.id) { out.push({ ...prev, body: { ...prev.body } }); continue }
      const body = alertBody(prev?.body ?? null, over)
      if (!prev) { body.created = now; body.armedAt = now }
      else { body.webhook = prev.body.webhook ?? null; if (typeof prev.body.title === 'string' && prev.body.title) body.title = prev.body.title }
      out.push({ collection: 'alerts', id, body, fields: {}, revision: 0, deleted: false, generation: 0 })
    }
  }
  // 删除：网页管得着、却已经不在网页上的
  const drawingKinds = new Map<string, string>()
  for (const o of inp.drawingObjs) if (drawingManaged(o)) drawingKinds.set(o.id, str(o.body.kind) ?? '')
  const webDrawing = new Set<string>()
  for (const [s, list] of Object.entries(inp.drawings)) for (const d of list) if (ALERTABLE.has(d.type) && syncableDrawing(s, d)) webDrawing.add(drawingId(s, d.id))
  for (const o of prevAll) {
    if (o.deleted || keep.has(o.id)) continue
    if (decodeAlert(o, ctx)) { out.push({ ...o, deleted: true }); continue }
    const t = drawingAlertTarget(o)
    if (!t) continue
    const kind = drawingKinds.get(t)
    const managed = webDrawing.has(t) || (kind != null && ALERTABLE.has(TYPE_OF[kind]))
    if (managed) out.push({ ...o, deleted: true })
  }
  return out
}

/** 云端提醒装进网页：本机上不了云的那几条原样留着，其余按云端来，保持原来的先后 */
export function decodeAlerts(all: SyncObject[], current: Alert[], ctx: Ctx): { alerts: Alert[]; drawingAlerts: Set<string> } {
  const cloud = new Map<string, Alert>()
  const drawingAlerts = new Set<string>()
  for (const o of all) {
    const a = decodeAlert(o, ctx)
    if (a) cloud.set(o.id, a)
    const t = drawingAlertTarget(o)
    if (t) drawingAlerts.add(t)
  }
  const list: Alert[] = []
  for (const a of current) {
    if (!syncableAlert(a)) { list.push(a); continue }
    const id = alertId(a.symbol, a.id)
    const c = cloud.get(id)
    if (c) { list.push(same(normAlert(c), normAlert(a)) ? a : c); cloud.delete(id) }
  }
  list.push(...cloud.values())
  return { alerts: list, drawingAlerts }
}
