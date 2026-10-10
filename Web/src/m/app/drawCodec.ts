/* Hkline 手机网页版 · 画线 ↔ 云端对象（纯函数与一个记账小助手，不碰 DOM、不碰 localStorage，vitest 直接测）
 *
 * 线上形状照 iOS（Kanpan/Account/PersonalSyncCodec.swift · drawings / drawing，SyncOverlay.swift · drawings /
 * capDrawings / drawingAges），服务端白名单在 Backend/kanpan-api/src/sync_validation.rs，
 * 字段契约是 Backend/kanpan-api/contract/drawing-fields.json。手机网页版的画线模型（m/chart/draw）就是 iOS 那一套，
 * 所以这里全部工具都进同步（PC 网页只认其中九种）。
 *
 * ## drawings（一条线一个对象）
 * id = `<venue>/<market>/<SYMBOL>/<画线 id>`（桶键就是 InstrumentID.canonical）；
 * body = `Drawing` 的编码去掉 `id`、`points` 改名 `anchors`，再加 `symbol` / `market` / `venue`。
 * `color` 为空时不写（stage 把「先前有、这次没有」的键发成 null，服务端收 color 的 null），
 * 带文字的工具总写 `text`（空也写 ""）。老客户端留下的 `created` 不归这里管，原样带回。
 *
 * ## drawingPreferences（id "tools"，一份）
 * DrawingPreferences 的编码拍平一层：`magnet` / `continuous`，`styles/<工具>`、`variants/<一格>`。
 * （`favorites` 2026-10-10 三端退役：不发、不认领，云端老对象里的残留由服务端 strip_retired 洗掉。）
 *
 * ## 规矩
 * - 应用：云端对象叠到本机存档上（删 → 移除；活 → 原位替换或接在后面；解不开的跳过），再按「多老」裁到每品种 50 条
 *   （DrawArchive.capToLimit，「多老」= 对象各字段写入戳里最早的那个；云端还没确认过的算最新）。
 *   裁掉的那几条下一次记账推成删除，各设备算出来的「多老」一样，裁掉的也是同一批。
 * - 记账：按品种分桶比指纹，只编码变了的桶；桶里没有了的（本机删了、被裁了）记删除。本机解不开的对象（更新版本的工具）不删。
 * - 第一次对上：并集。云端有墓碑的不带回；同一条两边都有时，按这只品种「本机最后一次改」和云端那条最后一次写谁新用谁。
 *   工具偏好同理整份比。上一次在这台设备同步的是另一个账号：云端整体覆盖。
 */
import type { Owned, SyncStore } from '../../sync/store'
import type { Body, Json, SyncObject } from '../../sync/types'
import { type Drawing, encodeDrawing, tryDecodeDrawing, drawingIsValid, cloneDrawing, drawingsEqual } from '../chart/draw/drawing'
import { type DrawAge, DrawArchive, DrawingPreferences, decodePreferences, encodePreferences } from '../chart/draw/archive'
import { canonicalInstrument } from '../chart/draw/instrument'
import { instrumentIdentity } from '../../sync/codec'

export const PREFS_COLLECTION = 'drawingPreferences'
export const PREFS_ID = 'tools'

const rootOf = (path: string): string => { const i = path.indexOf('/'); return i < 0 ? path : path.slice(0, i) }
const isRecord = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v)

/** 按路径第一段认领的 owned（`styles/<工具>` 这种拍平路径） */
class RootSet extends Set<string> {
  constructor(private readonly roots: readonly string[]) { super() }
  override has(k: string): boolean { return this.roots.includes(rootOf(k)) }
}

/** 画线与工具偏好里手机网页版替它说话的键 */
export const DRAW_OWNED: Owned = {
  drawings: new Set(['kind', 'anchors', 'color', 'lineWidth', 'dash', 'filled', 'locked', 'hidden', 'levels', 'text', 'symbol', 'market', 'venue']),
  drawingPreferences: new RootSet(['magnet', 'continuous', 'styles', 'variants']),
}

// ═════════════════════════════ 一条线 ═════════════════════════════

export const drawingObjectId = (key: string, id: string): string => canonicalInstrument(key) + '/' + id

/** 对象 id → 桶键（前三段，规范写法）；不够三段 → "" */
export function instrumentOf(o: SyncObject): string {
  const p = o.id.split('/')
  return p.length >= 4 ? canonicalInstrument(p.slice(0, 3).join('/')) : ''
}
const localId = (o: SyncObject): string => o.id.slice(o.id.lastIndexOf('/') + 1)

/** 服务端收得下的桶键（sync_validation.rs identity：按 venue / market 认那一家的代号形状——币安 binance_symbol、
 *  Coinbase BASE-USD、美元指数只放 DXY，2026-10-08 起 OKX / Bybit / Hyperliquid 按注册表登记的形状；和电脑版 sync/codec instrumentIdentity 同一份） */
export function syncableKey(key: string): boolean {
  const p = key.split('/')
  return p.length === 3 && key.length <= 128 && instrumentIdentity(p[0], p[1], p[2])
}

/** 这条线能不能上云（桶键合规、线本身合法、id 没有斜杠、端点在服务端的范围里） */
export function syncableDrawing(key: string, d: Drawing): boolean {
  return syncableKey(key) && !!d.id && !d.id.includes('/') && drawingIsValid(d)
    && d.points.length >= 1 && d.points.length <= 8
    && d.points.every(p => p.t >= 0 && p.t <= 9e15 && Math.abs(p.p) <= 1e15)
}

export function encodeDrawingObject(key: string, d: Drawing): SyncObject {
  const k = canonicalInstrument(key)
  const { id: _id, points, ...rest } = encodeDrawing(d) as unknown as Record<string, Json>
  const [venue, market, symbol] = k.split('/')
  const body: Body = { ...(JSON.parse(JSON.stringify(rest)) as Body), anchors: JSON.parse(JSON.stringify(points)) as Json, symbol, market, venue }
  return { collection: 'drawings', id: k + '/' + d.id, body, fields: {}, revision: 0, deleted: false, generation: 0 }
}

/** 云端对象 → 一条线；墓碑、解不开的（本机不认识的工具、端点坏了）→ null */
export function decodeDrawingObject(o: SyncObject): { key: string; d: Drawing } | null {
  if (o.deleted || o.collection !== 'drawings') return null
  const key = instrumentOf(o)
  if (!key) return null
  const { anchors, symbol: _s, market: _m, venue: _v, created: _c, ...rest } = o.body
  const d = tryDecodeDrawing({ ...rest, id: localId(o), points: anchors })
  return d ? { key, d } : null
}

// ═════════════════════════════ 工具偏好 ═════════════════════════════

export function encodePrefsObject(p: DrawingPreferences): SyncObject {
  const j = encodePreferences(p)
  const body: Body = {}
  for (const [k, v] of Object.entries(j)) {
    if ((k === 'styles' || k === 'variants') && isRecord(v)) for (const [c, x] of Object.entries(v)) body[k + '/' + c] = JSON.parse(JSON.stringify(x)) as Json
    else body[k] = JSON.parse(JSON.stringify(v)) as Json
  }
  return { collection: PREFS_COLLECTION, id: PREFS_ID, body, fields: {}, revision: 0, deleted: false, generation: 0 }
}

/** iOS PersonalSyncCodec.expand + DrawingPreferences 解码；解不开 → null（跳过，不整批抛） */
export function decodePrefsObject(o: SyncObject | undefined): DrawingPreferences | null {
  if (!o || o.deleted) return null
  const out: Record<string, unknown> = {}
  for (const [path, v] of Object.entries(o.body)) {
    const i = path.indexOf('/')
    if (i < 0) { if (v !== null) out[path] = v; continue }
    const root = path.slice(0, i), child = path.slice(i + 1)
    const kids = isRecord(out[root]) ? out[root] as Record<string, unknown> : {}
    if (v !== null) kids[child] = v
    out[root] = kids
  }
  try { return decodePreferences(out) } catch { return null }
}

// ═════════════════════════════ 叠加 / 多老 / 裁 ═════════════════════════════

/** 对象最后一次被写的时刻（各字段写入戳里最大的） */
export function touched(o: SyncObject | undefined): number {
  let t = 0
  for (const s of Object.values(o?.fields ?? {})) { const ts = isRecord(s) && typeof s.timestamp === 'number' ? s.timestamp : 0; if (ts > t) t = ts }
  return t
}

/** 每条线（本地 id）多老：各字段写入戳里最早的那个（SyncOverlay.drawingAges）。没有戳的不列（本机最新的改动） */
export function drawingAges(objs: Iterable<SyncObject>): Map<string, DrawAge> {
  const out = new Map<string, DrawAge>()
  for (const o of objs) {
    if (o.collection !== 'drawings' || o.deleted) continue
    let best: DrawAge | null = null
    for (const s of Object.values(o.fields ?? {})) {
      if (!isRecord(s) || typeof s.timestamp !== 'number' || !Number.isFinite(s.timestamp)) continue
      const a: DrawAge = { timestamp: s.timestamp, logical: typeof s.logical === 'number' && s.logical >= 0 ? s.logical : 0 }
      if (!best || a.timestamp < best.timestamp || (a.timestamp === best.timestamp && a.logical < best.logical)) best = a
    }
    if (best) out.set(localId(o), best)
  }
  return out
}

/** 云端对象叠到存档上（原地改 a）：删 → 移除；活 → 原位替换或接在后面；解不开的跳过。工具偏好解得开就换 */
export function overlay(a: DrawArchive, objs: Iterable<SyncObject>, prefs?: SyncObject): void {
  for (const o of objs) {
    if (o.collection !== 'drawings') continue
    const key = instrumentOf(o)
    if (!key) continue
    const id = localId(o)
    const bucket = a.get(key)
    if (o.deleted) { if (bucket.some(d => d.id === id)) a.set(key, bucket.filter(d => d.id !== id)); continue }
    const x = decodeDrawingObject(o)
    if (!x) continue
    const i = bucket.findIndex(d => d.id === id)
    a.set(key, i >= 0 ? bucket.map((d, j) => (j === i ? x.d : d)) : bucket.concat([x.d]))
  }
  const p = decodePrefsObject(prefs)
  if (p) a.preferences = p
}

/** 进门的上限：每品种 50 条，多出来的丢最老的。返回一共丢了几条 */
export function capArchive(a: DrawArchive, objs: Iterable<SyncObject>): number {
  const ages = drawingAges(objs)
  return Object.values(a.capToLimit(d => ages.get(d.id) ?? null)).reduce((s, n) => s + n, 0)
}

/** 本机「最后一次改」：每只品种一个时刻，工具偏好一个 */
export interface DrawEdited { drawings: Record<string, number>; prefs: number }

/** 第一次对上的合并（见文件头）。返回新存档（不改 local） */
export function mergeFirstDrawings(local: DrawArchive, objs: SyncObject[], prefsObj: SyncObject | undefined, edited: DrawEdited, override: boolean): DrawArchive {
  const next = new DrawArchive(local.version)
  overlay(next, objs.filter(o => !o.deleted))
  const cloudPrefs = decodePrefsObject(prefsObj)
  if (override) {
    next.preferences = cloudPrefs ?? new DrawingPreferences()
  } else {
    const byId = new Map(objs.map(o => [o.id, o]))
    for (const [key, bucket] of Object.entries(local.bySymbol)) {
      for (const d of bucket) {
        const o = byId.get(drawingObjectId(key, d.id))
        if (o?.deleted) continue
        const cur = next.get(key)
        const i = cur.findIndex(x => x.id === d.id)
        if (i < 0) next.set(key, cur.concat([cloneDrawing(d)]))
        else if ((edited.drawings[key] ?? 0) > touched(o)) next.set(key, cur.map((x, j) => (j === i ? cloneDrawing(d) : x)))
      }
    }
    next.preferences = cloudPrefs && !(edited.prefs > touched(prefsObj)) ? cloudPrefs : local.preferences.clone()
  }
  capArchive(next, objs)
  return next
}

// ═════════════════════════════ 记账 ═════════════════════════════

const bucketPrint = (items: readonly Drawing[]): string => JSON.stringify(items.map(encodeDrawing))

/** 记账小助手：记着上一次对齐时每只品种的指纹，只编码变了的桶 */
export class DrawTracker {
  /** null：还没对齐过（下一次记账全量比，连云端有、本机整桶没了的也记删除） */
  prints: Map<string, string> | null = null
  prefs: string | null = null

  reset(): void { this.prints = null; this.prefs = null }

  /** 指纹对齐到 a（这些不是本机的改动，不再记账） */
  align(a: DrawArchive): void {
    this.prints = new Map(Object.entries(a.bySymbol).map(([k, v]) => [k, bucketPrint(v)]))
    this.prefs = JSON.stringify(encodePreferences(a.preferences))
  }

  /** 存档 → 要记账的对象（含删除）。`hold`：本机存档读坏过，只补不删 */
  capture(a: DrawArchive, store: SyncStore, hold = false): SyncObject[] {
    const out: SyncObject[] = []
    const now = new Map(Object.entries(a.bySymbol).map(([k, v]) => [k, bucketPrint(v)]))
    const prev = this.prints
    const byKey = new Map<string, SyncObject[]>()
    for (const o of store.localOf('drawings')) {
      const k = instrumentOf(o)
      if (!k) continue
      let l = byKey.get(k); if (!l) byKey.set(k, l = []); l.push(o)
    }
    const keys = new Set([...now.keys(), ...(prev ? prev.keys() : byKey.keys())])
    for (const key of keys) {
      if (prev && (prev.get(key) ?? '') === (now.get(key) ?? '')) continue
      const keep = new Set<string>()
      for (const d of a.get(key)) {
        if (!syncableDrawing(key, d)) continue
        const o = encodeDrawingObject(key, d)
        if (keep.has(o.id)) continue
        keep.add(o.id); out.push(o)
      }
      if (!hold) for (const o of byKey.get(key) ?? []) if (!o.deleted && !keep.has(o.id) && decodeDrawingObject(o)) out.push({ ...o, body: { ...o.body }, deleted: true })
    }
    const pp = JSON.stringify(encodePreferences(a.preferences))
    if (pp !== this.prefs) out.push(encodePrefsObject(a.preferences))
    this.prints = now
    this.prefs = pp
    return out
  }

  /** 账本里的云端值叠到 a 的一份拷贝上并裁上限。返回新存档（没变就是 null）、变了的桶、裁掉几条。
   *  指纹对齐到「裁之前」：裁掉的那几条下一次记账推成删除 */
  apply(a: DrawArchive, store: SyncStore): { next: DrawArchive | null; keys: string[]; dropped: number } {
    const objs = store.localOf('drawings')
    const next = a.clone()
    overlay(next, objs, store.get(PREFS_COLLECTION, PREFS_ID))
    this.align(next)
    const dropped = capArchive(next, objs)
    const keys = [...new Set([...Object.keys(a.bySymbol), ...Object.keys(next.bySymbol)])]
      .filter(k => !drawingsEqual(a.get(k), next.get(k)))
    const changed = keys.length > 0 || !a.preferences.equals(next.preferences)
    return { next: changed ? next : null, keys, dropped }
  }
}
