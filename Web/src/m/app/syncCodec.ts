/* Hkline 手机网页版 · 本机状态 ↔ 云端对象的编解码（纯函数，不碰 DOM、不碰 st，vitest 直接测）
 *
 * 线上形状照 iOS（Kanpan/Account/PersonalSyncCodec.swift、Settings/Model/PrefsCodec.swift、
 * Symbols/SymbolPrefs.swift），服务端白名单在 Backend/kanpan-api/src/sync_validation.rs。
 *
 * ## settings（id "chart"）
 * 手机网页版的 Prefs 与 iOS 同名同义，进同步的就是 prefs.ts 的 SYNCED_FIELDS 那 31 个「根」。
 * body 是拍平的：`params` / `indicatorColors` / `subHeightOverrides` / `indicatorLayouts` 这四个嵌套根
 * 拍成 `根/子`（颜色再深一层 `indicatorColors/<指标>/<序号>` = `{value:"#rrggbb"}`），其余一根一键。
 * 指标布局只有一份、跟人走（2026-10-03 起不再按周期分组）：顶层 overlays / subs / params / subHeightOverrides /
 * candleKind / priceMode 就是全部。`indicatorLayouts/<minute|hour|day>` 只为读老客户端写的分叉：装进来时取当前周期
 * 所在组那份、收拢成一份，下一次记账给这些分叉发 null，把云端也清干净。
 *
 * 按根记一份 `seen`（存在账本 a.seen 里）：「这个根上一次和云端对上时，本机归一化之后的线上样子」。
 *   - 记账：本机这个根 ≠ seen → 本机改了，从上一份 body 出发只换这个根的那几条路径；
 *     本机删掉的路径（清掉一个指标颜色）经 owned 的前缀集合发 null。
 *   - 应用：云端这个根 ≠ seen → 云端改了，装进来。指标布局那七个根是一个整体：按云端（含老分叉）取当前那份，再收拢。
 *   - 云端没有的标量根不记 seen：下一次记账会把本机的值推上去（老客户端、网页 PC 写的对象只带几个键）。
 *   - 云端的值本机表达不了（未知枚举）：seen 记成本机现值，不推也不装，免得一碰就把 iOS 的值冲掉。
 *
 * ## favorites / groups
 * iOS 的自选是一条全局列表：`groups:<id>` = {name, order}，`favorites:<venue/market/SYM>` =
 * {symbol, market, venue, groupId, order}。2026-10-08 起手机网页版管注册表里有行情面的每一家：币安 U 本位（网页里存裸代号，
 * = binance/usd_m/SYM）、美元指数（DXY = macro/index/DXY）、别家完整键（okx/usd_m/BTCUSDT、bybit/usd_m/…、hyperliquid/usd_m/KPEPE、
 * coinbase/spot/BTC-USD）。线上 symbol 段是那一家的代号（parseKey），venue / market 照三段身份；收回来按 keyOf 拼回网页里存的键。
 * 认不出的交易所 / 形状不合规的原位留着、不删不改。解码时同名分类按 iOS mergeSameNamed 并成一个（留 id 最小的）。
 *
 * ## alerts
 * 形状与 PC 网页一样（共用 alerts/shape.ts 的 19 个键），直接用 sync/codec.ts 的 encodeAlerts / decodeAlerts。
 */
import { type Body, type Json, type SyncObject, same } from '../../sync/types'
import type { Owned } from '../../sync/store'
import { OWNED as PC_OWNED } from '../../sync/bridge'
import { validSymbol, webSymbol, decodeAlerts, syncableAlert, alertId } from '../../sync/codec'
import { syncKeyOf, venueMarketOf } from '../../market/macro'
import { isDefaultVenue, keyOf, wireSymbol } from '../../market/identity'
import { DRAW_OWNED } from './drawCodec'
import type { Alert } from '../../alerts/shape'
import {
  LAYOUT_GROUPS, SYNCED_FIELDS, adoptBook, cleanColors, collapseLayouts, currentLayout, defaultPrefs, layoutBook, normalizePrefs, sanitizeLayout,
  type IndicatorLayout, type LayoutBook, type Prefs,
} from './prefs'
import type { FavoriteGroup, SymbolPrefs } from './store'

// ═════════════════════════════ settings ═════════════════════════════

export const SETTINGS_ID = 'chart'
export type Root = typeof SYNCED_FIELDS[number]
export const ROOTS: readonly Root[] = SYNCED_FIELDS
const NESTED = new Set<string>(['params', 'indicatorColors', 'subHeightOverrides', 'indicatorLayouts'])
/** 指标布局的六个键（顶层写共用那份） */
const LAYOUT_KEYS = ['overlays', 'subs', 'params', 'subHeightOverrides', 'candleKind', 'priceMode'] as const
/** 指标布局作为一个整体应用的七个根 */
export const LAYOUT_ROOTS: readonly Root[] = [...LAYOUT_KEYS, 'indicatorLayouts']
const isLayoutRoot = (r: string): boolean => (LAYOUT_ROOTS as readonly string[]).includes(r)
const IND_IDS = new Set(['MA', 'EMA', 'BOLL', 'VWAP', 'ST', 'SAR', 'ORDERFLOW', 'VOL', 'MACD', 'RSI', 'KDJ', 'SRSI', 'ATR', 'OI', 'LSR', 'TAKER', 'BASIS', 'DMI', 'CVD'])

const clone = <T>(v: T): T => JSON.parse(JSON.stringify(v ?? null)) as T
const isRecord = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v)
const rootOf = (path: string): string => { const i = path.indexOf('/'); return i < 0 ? path : path.slice(0, i) }

/** settings 的 owned：31 个根和它们下面的一切路径（先前有、这次没有的发 null） */
class RootSet extends Set<string> {
  override has(k: string): boolean { return (ROOTS as readonly string[]).includes(rootOf(k)) }
}

/** 每张表手机网页版替它说话的那些键 */
export const OWNED_M: Owned = {
  settings: new RootSet(),
  favorites: new Set(['symbol', 'market', 'venue', 'groupId', 'order']),
  groups: new Set(['name', 'order']),
  alerts: PC_OWNED.alerts,
  drawings: DRAW_OWNED.drawings,
  drawingPreferences: DRAW_OWNED.drawingPreferences,
}

/** 一组布局的线上写法（iOS Prefs.encode(layout)） */
function layoutWire(l: IndicatorLayout): Record<string, Json> {
  const s = sanitizeLayout(l, l)
  return clone({ priceMode: s.priceMode, candleKind: s.candleKind, overlays: s.overlays, subs: s.subs, params: s.params, subHeightOverrides: s.subHeightOverrides }) as Record<string, Json>
}

/** 一个根的线上值（没拍平）。book 由调用方算一次传进来 */
function wireValue(p: Prefs, root: Root, book: LayoutBook): Json {
  if ((LAYOUT_KEYS as readonly string[]).includes(root)) return layoutWire(book.shared)[root]
  if (root === 'indicatorLayouts') {
    const out: Record<string, Json> = {}
    for (const g of LAYOUT_GROUPS) { const f = book.forks[g]; if (f) out[g] = layoutWire(f) }
    return out
  }
  if (root === 'indicatorColors') {
    const out: Record<string, Json> = {}
    for (const [id, m] of Object.entries(p.indicatorColors)) {
      const one: Record<string, Json> = {}
      for (const [n, hex] of Object.entries(m ?? {})) one[n] = { value: hex }
      out[id] = one
    }
    return out
  }
  if (root === 'subInverted') return [...p.subInverted].sort()
  return clone(p[root] as Json)
}

/** 拍平一个根（iOS PersonalSyncCodec.flatten） */
function flattenRoot(root: string, v: Json): Body {
  if (!NESTED.has(root) || !isRecord(v)) return { [root]: v }
  const out: Body = {}
  for (const [child, content] of Object.entries(v)) {
    if (root === 'indicatorColors' && isRecord(content)) for (const [n, c] of Object.entries(content)) out[`${root}/${child}/${n}`] = c as Json
    else out[`${root}/${child}`] = content as Json
  }
  return out
}

/** 一个根在 body 里的那几条路径（嵌套根的 null 丢掉 = iOS expand） */
function pathsOf(body: Body, root: string): Body {
  const out: Body = {}
  for (const [k, v] of Object.entries(body)) if (k === root || k.startsWith(root + '/')) { if (!(NESTED.has(root) && v === null)) out[k] = v }
  return out
}

/** 拍平的路径 → 这个根的值（iOS expand）。标量根不在或是 null 返回 undefined；嵌套根不在 = 空表 */
function expandRoot(body: Body, root: string): Json | undefined {
  if (!NESTED.has(root)) { const v = body[root]; return v === undefined || v === null ? undefined : v }
  const out: Record<string, Json> = {}
  for (const [k, v] of Object.entries(pathsOf(body, root))) {
    const keys = k.split('/')
    if (keys.length === 2) out[keys[1]] = v
    else if (keys.length === 3) { const c = isRecord(out[keys[1]]) ? out[keys[1]] as Record<string, Json> : {}; c[keys[2]] = v; out[keys[1]] = c }
  }
  return out
}

/** 这个本机认得的路径（认不得的——更新版 iOS 的新指标、新分组——记账时原样留着，不发 null） */
function knownPath(path: string): boolean {
  const k = path.split('/')
  if (k.length === 1) return true
  if (k[0] === 'indicatorLayouts') return k.length === 2 && (LAYOUT_GROUPS as readonly string[]).includes(k[1])
  if (!IND_IDS.has(k[1])) return false
  if (k[0] === 'indicatorColors') return k.length === 3 && /^(?:[0-9]|1[0-9]|20)$/.test(k[2])
  return k.length === 2
}

/** 本机每个根拍平之后的样子（记账、比对、改动时刻都用它） */
export function settingsSubs(p: Prefs, roots: readonly Root[] = ROOTS): Record<string, Body> {
  const book = layoutBook(p)
  const out: Record<string, Body> = {}
  for (const r of roots) out[r] = flattenRoot(r, wireValue(p, r, book))
  return out
}

/** 本机 → 整个 settings 对象（测试、诊断用） */
export function settingsBody(p: Prefs): Body {
  return Object.assign({}, ...Object.values(settingsSubs(p))) as Body
}

/** 记账：本机和 seen 不同的根换进上一份 body（其余路径原样带回）。没有要推的返回 null */
export function encodeSettings(p: Prefs, prev: SyncObject | undefined, seen: Record<string, Json>): SyncObject | null {
  const body: Body = { ...(prev && !prev.deleted ? prev.body : {}) }
  const subs = settingsSubs(p)
  let touched = false
  for (const r of ROOTS) {
    const sub = subs[r]
    if (r in seen && same(sub, seen[r])) continue
    seen[r] = sub
    const before = pathsOf(body, r)
    // 本机认不得的子路径原样留着
    const keep: Body = {}
    for (const [k, v] of Object.entries(before)) if (!knownPath(k)) keep[k] = v
    const next = { ...keep, ...sub }
    if (same(before, next)) continue
    for (const k of Object.keys(body)) if (k === r || k.startsWith(r + '/')) delete body[k]
    Object.assign(body, next)
    touched = true
  }
  if (!touched) return null
  return { collection: 'settings', id: SETTINGS_ID, body, fields: {}, revision: 0, deleted: false, generation: 0 }
}

/** 云端一个非布局根 → 本机的值；表达不了返回 undefined */
function decodeRoot(root: Root, raw: Json): unknown {
  if (root === 'indicatorColors') {
    const flat: Record<string, Record<string, unknown>> = {}
    if (isRecord(raw)) for (const [id, m] of Object.entries(raw)) {
      if (!isRecord(m)) continue
      const one: Record<string, unknown> = {}
      for (const [n, c] of Object.entries(m)) one[n] = isRecord(c) ? c.value : c
      flat[id] = one
    }
    return cleanColors(flat)
  }
  const v = (normalizePrefs({ [root]: raw }) as unknown as Record<string, unknown>)[root]
  // 标量：归一化改了它（未知枚举、越界）就是本机表达不了
  if (raw === null || typeof raw !== 'object') return same(v, raw) ? v : undefined
  return v
}

/** 按云端 body 重建指标布局（缺的键取本机现在共用的那份；分叉的组从新的共用那份起步） */
function layoutFromCloud(cur: LayoutBook, body: Body): LayoutBook {
  const raw: Record<string, unknown> = {}
  for (const k of LAYOUT_KEYS) { const v = expandRoot(body, k); if (v !== undefined) raw[k] = v }
  const shared = sanitizeLayout(raw, cur.shared)
  const forks: LayoutBook['forks'] = {}
  for (const g of LAYOUT_GROUPS) { const v = body['indicatorLayouts/' + g]; if (isRecord(v)) forks[g] = sanitizeLayout(v, shared) }
  return { shared, forks }
}

/** 应用：云端值和 seen 不同的根写回 p。`only`：只看这些根（第一次对上时按根比新旧）。返回改了哪些根 */
export function applySettings(p: Prefs, cloud: SyncObject | undefined, seen: Record<string, Json>, only?: ReadonlySet<string>): Root[] {
  if (!cloud || cloud.deleted) return []
  const changed: Root[] = []
  const want = (r: string): boolean => !only || only.has(r)
  const mine = settingsSubs(p)
  // 三组全貌按装之前的周期读（下面可能先装了云端的 interval，跨组时顶层那份就对不上了）
  const book0 = layoutBook(p)
  for (const r of ROOTS) {
    if (isLayoutRoot(r) || !want(r)) continue
    const raw = expandRoot(cloud.body, r)
    if (raw === undefined) continue
    const v = decodeRoot(r, raw)
    if (v === undefined) { if (!(r in seen)) seen[r] = mine[r]; continue }
    const probe = { ...p, [r]: v } as Prefs
    const sub = settingsSubs(probe, [r])[r]
    if (r in seen && same(sub, seen[r])) continue
    seen[r] = sub
    if (same(sub, mine[r])) continue
    ;(p as unknown as Record<string, unknown>)[r] = v
    changed.push(r)
  }
  let layoutDone = false
  if (LAYOUT_ROOTS.some(want)) {
    const cand = clone(p)
    adoptBook(cand, layoutFromCloud(book0, cloud.body))
    // seen 记云端原样（含老客户端的分叉），本机收拢成一份：下一次记账顶层推那一份、分叉发 null 删掉
    const subs = settingsSubs(cand, LAYOUT_ROOTS)
    collapseLayouts(cand)
    if (!LAYOUT_ROOTS.every(r => r in seen && same(subs[r], seen[r]))) {
      for (const r of LAYOUT_ROOTS) seen[r] = subs[r]
      const after = settingsSubs(cand, LAYOUT_ROOTS)
      const diff = LAYOUT_ROOTS.filter(r => !same(after[r], mine[r]))
      if (diff.length || !same(currentLayout(cand), currentLayout(p))) {
        for (const k of LAYOUT_KEYS) (p as unknown as Record<string, unknown>)[k] = cand[k]
        p.indicatorLayouts = cand.indicatorLayouts
        changed.push(...(diff.length ? diff : LAYOUT_ROOTS))
        layoutDone = true
      }
    }
  }
  // 只换了周期：本机若还留着老档的分叉，按新周期取那一份再收拢
  if (!layoutDone && changed.includes('interval')) { adoptBook(p, book0); collapseLayouts(p) }
  return changed
}

/** 这个根在云端最后一次被改的时刻（它那几条路径的字段时间戳里最大的） */
export function rootTouched(o: SyncObject | undefined, root: string): number {
  if (!o) return 0
  let t = 0
  for (const [k, stamp] of Object.entries(o.fields || {})) {
    if (k !== root && !k.startsWith(root + '/')) continue
    const ts = isRecord(stamp) && typeof stamp.timestamp === 'number' ? stamp.timestamp : 0
    if (ts > t) t = ts
  }
  return t
}

/** 第一次对上时设置的合并（iOS SettingsStamp：按根比「本机最后一次改」和「云端这个根最后一次改」，谁新用谁）。
 *  指标布局七个根一起比、一起装。override：上一次在这台设备同步的是另一个账号，云端整体覆盖。
 *  seen 由调用方先清空；本机新的根不记 seen，记账时推上去。返回改了哪些根 */
export function mergeSettings(p: Prefs, cloud: SyncObject | undefined, seen: Record<string, Json>, edited: Record<string, number>, override: boolean): Root[] {
  if (override) {
    // 换了人：先回出厂再装云端的——云端没有（新账号）或缺了的根不能留着上一个账号的（iOS 按账号分目录存偏好，新人就是出厂）
    const reset = resetSynced(p)
    const applied = cloud && !cloud.deleted ? applySettings(p, cloud, seen) : []
    return [...new Set([...reset, ...applied])]
  }
  if (!cloud || cloud.deleted) return []
  const only = new Set<string>()
  for (const r of ROOTS) if (!isLayoutRoot(r) && !((edited[r] ?? 0) > rootTouched(cloud, r))) only.add(r)
  const localLayout = Math.max(0, ...LAYOUT_ROOTS.map(r => edited[r] ?? 0))
  const cloudLayout = Math.max(0, ...LAYOUT_ROOTS.map(r => rootTouched(cloud, r)))
  if (!(localLayout > cloudLayout)) for (const r of LAYOUT_ROOTS) only.add(r)
  return applySettings(p, cloud, seen, only)
}

/** 进同步的字段整份回到出厂（原地改），返回变了的根 */
export function resetSynced(p: Prefs): Root[] {
  const before = settingsSubs(p)
  const d = defaultPrefs() as unknown as Record<string, unknown>
  for (const k of SYNCED_FIELDS) (p as unknown as Record<string, unknown>)[k] = d[k]
  const after = settingsSubs(p)
  return ROOTS.filter(r => !same(before[r], after[r]))
}

/** 两份拍平值之间变了的根（记「本机最后一次改」用） */
export function changedRoots(a: Record<string, Body>, b: Record<string, Body>): Root[] {
  return ROOTS.filter(r => !same(a[r], b[r]))
}

// ═════════════════════════════ favorites / groups ═════════════════════════════

export const FAV_VENUE = 'binance'
export const FAV_MARKET = 'usd_m'
/** 网页里存的键 → 同步 id（三段身份）：裸代号 → binance/usd_m/<代号>；DXY → macro/index/DXY；别家完整键原样 */
export const favId = (symbol: string): string => syncKeyOf(symbol)
export type FavState = Pick<SymbolPrefs, 'favorites' | 'groups' | 'groupForSymbol'>

const num = (v: Json | undefined): number | null => typeof v === 'number' && isFinite(v) ? v : null
function liveSorted(objs: SyncObject[]): SyncObject[] {
  return objs.filter(o => !o.deleted).sort((a, b) => (num(a.body.order) ?? 0) - (num(b.body.order) ?? 0) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
}
/** 手机网页版管得着的自选：venue / market / symbol 三段拼得回网页的键（币安裸代号、DXY、注册表里那一家的完整键）、
 *  代号形状合规、id 与三段对得上；返回网页里存的键 */
function managed(o: SyncObject): string | null {
  const w = o.body.symbol, v = o.body.venue, m = o.body.market
  if (typeof w !== 'string' || typeof v !== 'string' || typeof m !== 'string' || !w || !v || !m) return null
  const s = keyOf(v, m, w)
  if (!webSymbol(s) || o.id !== favId(s)) return null
  if (isDefaultVenue(s) && !validSymbol(s)) return null
  return s
}
const syncable = (s: string): boolean => webSymbol(s)

/** 自选指纹（seeded 这种本机记号不算） */
export function favPrint(f: FavState): string {
  return JSON.stringify([f.favorites, f.groups, Object.entries(f.groupForSymbol).sort()])
}

/** 本机自选 → 要记账的对象（含删除）。groups 在前（favorites 的 groupId 要指得到） */
export function encodeFavorites(f: FavState, prevFavs: SyncObject[], prevGroups: SyncObject[]): SyncObject[] {
  const out: SyncObject[] = []
  const mk = (collection: string, id: string, body: Body, deleted = false): SyncObject => ({ collection, id, body, fields: {}, revision: 0, deleted, generation: 0 })
  // 分类
  const gPrev = liveSorted(prevGroups)
  const gById = new Map(prevGroups.map(o => [o.id, o]))
  const gUnchanged = gPrev.length === f.groups.length && gPrev.every((o, i) => o.id === f.groups[i].id)
  const groupIds = new Set(f.groups.map(g => g.id))
  f.groups.forEach((g, i) => {
    const prev = gById.get(g.id)
    const base = prev && !prev.deleted ? prev.body : {}
    out.push(mk('groups', g.id, { ...base, name: g.name, order: gUnchanged ? (num(prev?.body.order) ?? i) : i }))
  })
  for (const o of gPrev) if (!groupIds.has(o.id)) out.push({ ...o, deleted: true })
  // 自选：管不着的原位不动，管得着的位置按本机顺序填，新加的接在最后
  const prev = liveSorted(prevFavs)
  const pinned = new Set(prev.filter(o => !managed(o)).map(o => o.id))
  const seen = new Set<string>()
  const queue = f.favorites.filter(s => syncable(s) && !pinned.has(favId(s)) && !seen.has(s) && (seen.add(s), true))
  const byId = new Map(prevFavs.map(o => [o.id, o]))
  const seq: { id: string; symbol: string | null; prev?: SyncObject }[] = []
  for (const o of prev) {
    if (!managed(o)) { seq.push({ id: o.id, symbol: null, prev: o }); continue }
    const next = queue.shift()
    if (next !== undefined) seq.push({ id: favId(next), symbol: next, prev: byId.get(favId(next)) })
  }
  for (const s of queue) seq.push({ id: favId(s), symbol: s, prev: byId.get(favId(s)) })
  const unchanged = seq.length === prev.length && seq.every((x, i) => x.id === prev[i].id)
  const keep = new Set(seq.map(x => x.id))
  seq.forEach((x, i) => {
    const order = unchanged ? (num(x.prev?.body.order) ?? i) : i
    const base = x.prev && !x.prev.deleted ? x.prev.body : null
    if (x.symbol == null) { out.push(mk('favorites', x.id, { ...(base ?? {}), order })); return }
    const g = f.groupForSymbol[x.symbol]
    out.push(mk('favorites', x.id, { symbol: wireSymbol(x.symbol), ...venueMarketOf(x.symbol), groupId: g && groupIds.has(g) ? g : null, order }))
  })
  for (const o of prev) if (!keep.has(o.id) && managed(o)) out.push({ ...o, deleted: true })
  return out
}

const identity = (name: string): string => name.trim()
/** iOS SymbolPrefs.mergeSameNamed：同名分类留 id 最小的，站在同名里最靠前的位置 */
export function mergeSameNamed(groups: FavoriteGroup[]): { groups: FavoriteGroup[]; merged: Record<string, string> } {
  const keeper = new Map<string, FavoriteGroup>()
  for (const g of groups) { const n = identity(g.name); const k = keeper.get(n); if (k && k.id <= g.id) continue; keeper.set(n, g) }
  const out: FavoriteGroup[] = [], placed = new Set<string>(), merged: Record<string, string> = {}
  for (const g of groups) {
    const n = identity(g.name), kept = keeper.get(n)!
    if (g.id !== kept.id) merged[g.id] = kept.id
    if (!placed.has(n)) { placed.add(n); out.push(kept) }
  }
  return { groups: out, merged }
}

/** 云端 → 本机自选。本机那几只上不了云的（代号不合规）原样留着。merged：并掉的分类（外面要再记一次账把它们删掉） */
export function decodeFavorites(favs: SyncObject[], groups: SyncObject[], local: FavState): FavState & { merged: Record<string, string> } {
  const raw = liveSorted(groups).map(o => ({ id: o.id, name: typeof o.body.name === 'string' && o.body.name ? o.body.name : o.id }))
  const { groups: gs, merged } = mergeSameNamed(raw)
  const ids = new Set(gs.map(g => g.id))
  const favorites: string[] = []
  const groupForSymbol: Record<string, string> = {}
  for (const o of liveSorted(favs)) {
    const s = managed(o)
    if (!s || favorites.includes(s)) continue
    favorites.push(s)
    const g0 = typeof o.body.groupId === 'string' ? o.body.groupId : null
    const g = g0 ? merged[g0] ?? g0 : null
    if (g && ids.has(g)) groupForSymbol[s] = g
  }
  for (const s of local.favorites) {
    if (syncable(s) || favorites.includes(s)) continue
    favorites.push(s)
    const g = local.groupForSymbol[s]
    if (g && ids.has(g)) groupForSymbol[s] = g
  }
  return { favorites, groups: gs, groupForSymbol, merged }
}

/** iOS SymbolPrefs.absorb(guest:)：分类按名字并（留 base 的 id 与位置），自选按代号并（base 已有的归属不动） */
export function absorb(base: FavState, guest: FavState): FavState {
  const out: FavState = { favorites: [...base.favorites], groups: base.groups.map(g => ({ ...g })), groupForSymbol: { ...base.groupForSymbol } }
  const byName = new Map<string, string>()
  for (const g of out.groups) if (!byName.has(identity(g.name))) byName.set(identity(g.name), g.id)
  const remap: Record<string, string> = {}
  for (const g of guest.groups) {
    if (out.groups.some(x => x.id === g.id)) continue
    const kept = byName.get(identity(g.name))
    if (kept) { remap[g.id] = kept; continue }
    out.groups.push({ ...g }); byName.set(identity(g.name), g.id)
  }
  for (const s of guest.favorites) {
    if (out.favorites.includes(s)) continue
    out.favorites.push(s)
    const g = guest.groupForSymbol[s]
    if (g) out.groupForSymbol[s] = remap[g] ?? g
  }
  return out
}

/** 第一次对上时自选的合并（iOS AppAccountBridge）：
 *  - 云端一条都没有：留本机的（新账号不该把自选清空）；override 时给 fresh()（不把上一个人的带进来）
 *  - override，或本机从没改过：云端的
 *  - 否则新的那份做底，把旧的那份并进来（不丢任何一边的自选）
 *  返回合并后的样子（null = 本机不动） */
export function mergeFavorites(local: FavState, favs: SyncObject[], groups: SyncObject[], edited: number, override: boolean, fresh: () => FavState): (FavState & { merged: Record<string, string> }) | null {
  const liveFavs = favs.filter(o => !o.deleted), liveGroups = groups.filter(o => !o.deleted)
  if (!liveFavs.length && !liveGroups.length) return override ? { ...fresh(), merged: {} } : null
  const cloud = decodeFavorites(favs, groups, override ? { favorites: [], groups: [], groupForSymbol: {} } : local)
  if (override || !(edited > 0)) return cloud
  const cloudT = Math.max(0, ...[...liveFavs, ...liveGroups].map(o => rootTouchedAll(o)))
  const merged = edited > cloudT ? absorb(local, cloud) : absorb(cloud, local)
  const again = mergeSameNamed(merged.groups)
  const remap = (g: string): string => again.merged[g] ?? g
  return {
    favorites: merged.favorites, groups: again.groups,
    groupForSymbol: Object.fromEntries(Object.entries(merged.groupForSymbol).map(([s, g]) => [s, remap(g)])),
    merged: { ...cloud.merged, ...again.merged },
  }
}
function rootTouchedAll(o: SyncObject): number {
  let t = 0
  for (const stamp of Object.values(o.fields || {})) { const ts = isRecord(stamp) && typeof stamp.timestamp === 'number' ? stamp.timestamp : 0; if (ts > t) t = ts }
  return t
}

// ═════════════════════════════ alerts ═════════════════════════════

/** 本机还在等、云端已经是已触发的那几条（服务端判响了）：外面报给人，再记删除 */
export function remoteFired(alerts: Alert[], cloud: (id: string) => SyncObject | undefined): Alert[] {
  const out: Alert[] = []
  for (const a of alerts) {
    if (!syncableAlert(a)) continue
    const o = cloud(alertId(a.symbol, a.id))
    if (o && !o.deleted && o.body.status === 'fired') out.push({ ...a, status: 'fired', firedAt: num(o.body.firedAt) ?? a.firedAt, firedPrice: num(o.body.firedPrice) ?? a.firedPrice })
  }
  return out
}

/** 第一次对上时提醒的合并：并集；云端有这一条（活的已在云端那份里，墓碑说明别处删了）就听云端的 */
export function mergeAlerts(local: Alert[], all: SyncObject[], override: boolean, has: (id: string) => boolean): Alert[] {
  const out = decodeAlerts(all, [])
  if (!override) for (const a of local) if (!syncableAlert(a) || !has(alertId(a.symbol, a.id))) out.push(a)
  return out
}
