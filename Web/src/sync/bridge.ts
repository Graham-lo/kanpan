/* Hkline Web · 页面状态 ↔ 同步账本（纯函数，不碰 DOM，vitest 直接测）
 *
 * - captureInto：页面状态里「指纹变了」的那几块编码成云端对象，交给账本记账。
 * - applyInto：账本里云端改过的那几张表解码回页面状态，返回改了什么（外面据此刷新界面）。
 * - mergeFirst：这台电脑第一次和这个账号对上时的合并规则：
 *     · 设置、自选：比「本机最后一次改」和「云端字段时间戳里最新的」，谁新用谁；
 *       云端一条自选都没有时保留本机的（新账号不该把自选清空）。
 *     · 画线、提醒：取并集；云端已经删掉（墓碑）的那几条不从本机带回去。
 *     · 布局集（chartLayouts）单独比时间：换品种 / 周期只算「动了布局」，不让指标看起来比手机上的新；
 *       云端新时以云端为准，本机多出来的几套接在后面（layouts.mergeBooks），不丢。
 *     · 上一次在这台电脑同步的是另一个账号（override）：云端整体覆盖，不把上一个人的东西带进来。
 */
import type { State } from '../app/store'
import type { Alert } from '../alerts/shape'
import { DEFAULT_WATCH, type Kind } from '../market/symbols'
import {
  type Ctx, SETTINGS_FIELDS, SETTINGS_ID, alertId, applySettings, webSetting, decodeSetting, putSetting, decodeAlert, decodeAlerts, decodeDrawings, decodeFavorites, drawingId,
  encodeAlerts, encodeDrawings, encodeFavorites, encodeSettings, keepLocalStyle, lastTouched, resetSettings, syncableAlert, syncableDrawing, validSymbol, pausedLineAlerts, seenWhenUndecodable,
} from './codec'
import { LAYOUTS_FIELD, cleanBook, liveBook, mergeBooks } from '../app/layouts'
import type { Owned, SyncStore } from './store'
import { type Json, type SyncObject, keyOf, same } from './types'

export type WebState = Pick<State, 'pinned' | 'ind' | 'params' | 'watch' | 'drawings' | 'alerts'> & Partial<Pick<State, 'orderFlowOverrides' | 'orderFlowHistory' | 'compareSymbols' | 'autoLayers' | 'drawHidden' | 'layouts' | 'layout' | 'cells' | 'active' | 'chartSettings'>>
export type Part = 'settings' | 'favorites' | 'drawings' | 'alerts'
export type Prints = Partial<Record<Part, string>>

/** 每张表网页替它说话的那些键：先前有、这次没有的键，属于这里的才发 null，其余原样带回 */
export const OWNED: Owned = {
  settings: new Set(SETTINGS_FIELDS),
  favorites: new Set(['symbol', 'market', 'venue', 'groupId', 'order']),
  // style：网页独有的扩展样式，只有网页写，本机清掉时发 null（codec.WEB_ONLY_BODY_KEYS）
  drawings: new Set(['kind', 'anchors', 'color', 'lineWidth', 'locked', 'symbol', 'market', 'venue', 'dash', 'filled', 'hidden', 'levels', 'style']),
  alerts: new Set(['kind', 'symbol', 'market', 'drawingID', 'lines', 'condition', 'armedAt', 'once', 'status', 'firedAt', 'firedPrice', 'dueAt', 'reviewID', 'title', 'created', 'note', 'webhook', 'webhookText', 'rule']),
}

/** 设置里除布局集以外的那几项（指标、周期条、对比……） */
const CORE_FIELDS = SETTINGS_FIELDS.filter(f => f !== LAYOUTS_FIELD)
export const corePrint = (s: WebState): string => JSON.stringify([s.pinned, s.ind, s.params, s.orderFlowOverrides ?? {}, s.orderFlowHistory === true, s.compareSymbols ?? [], s.drawHidden === true, s.autoLayers ?? []])
/** 布局集（活数据抄回之后）的指纹 */
export const layoutsPrint = (s: WebState): string => (s.layouts && s.layout && s.cells ? JSON.stringify(liveBook({ layouts: s.layouts, layout: s.layout, cells: s.cells, active: s.active ?? 0 })) : '')

export function fingerprint(s: WebState): Record<Part, string> {
  return {
    settings: corePrint(s) + layoutsPrint(s) + JSON.stringify(s.chartSettings ?? null),
    favorites: JSON.stringify(s.watch),
    drawings: JSON.stringify(s.drawings),
    alerts: JSON.stringify(s.alerts),
  }
}

/** 记账。`ready`：品种表到了没有（没到时分不出自选的类别，不碰自选）。
 *  `holdDeletes`：本机画线存档读坏过（app/store 的 drawingsSuspect），画线只补不删 */
export function captureInto(s: WebState, store: SyncStore, ctx: Ctx & { ready: boolean }, fp: Prints, spent?: ReadonlySet<string>, opts: { holdDeletes?: boolean } = {}): number {
  const now = fingerprint(s)
  const vals: SyncObject[] = []
  if (now.settings !== fp.settings) {
    const o = encodeSettings(s, store.get('settings', SETTINGS_ID), store.a.seen)
    if (o) vals.push(o)
    fp.settings = now.settings
  }
  if (now.favorites !== fp.favorites && ctx.ready) {
    vals.push(...encodeFavorites(s.watch, store.localOf('favorites'), ctx, store.localOf('groups')))
    fp.favorites = now.favorites
  }
  if (now.drawings !== fp.drawings) { vals.push(...encodeDrawings(s.drawings, store.localOf('drawings'), opts)); fp.drawings = now.drawings }
  if (now.alerts !== fp.alerts) { vals.push(...encodeAlerts(s.alerts, store.localOf('alerts'), spent)); fp.alerts = now.alerts }
  return store.capture(vals, OWNED)
}

/** `fired`：本机还在等、云端已经是已触发的那几条（服务端判响了）——外面报给人，再记删除 */
export interface Applied {
  settings: string[]; favorites: boolean; drawings: Set<string>; alerts: boolean; fired: Alert[]
  /** 云端还有暂停着的画线提醒（老版本「线找不到」时暂停的）：网页已当生效的装进来，要再记一次账推回 active */
  revive?: boolean
}

/** 把账本里的云端值装进页面状态（原地改 s）。`all`：不看 unapplied，全部重装 */
export function applyInto(s: WebState, store: SyncStore, ctx: Ctx & { ready: boolean }, all = false): Applied {
  const u = store.a.unapplied
  const r: Applied = { settings: [], favorites: false, drawings: new Set(), alerts: false, fired: [] }
  if (all || u.has('settings')) r.settings = applySettings(s, store.get('settings', SETTINGS_ID), store.a.seen)
  if ((all || u.has('favorites')) && ctx.ready) {
    const w = decodeFavorites(store.localOf('favorites'), ctx)
    // 本机那几条上不了云的（代号不合规）原样留着
    for (const k of Object.keys(w) as Kind[]) w[k].push(...(s.watch[k] ?? []).filter(x => !validSymbol(x) && !w[k].includes(x)))
    if (!same(w, s.watch)) { s.watch = w; r.favorites = true }
  }
  if (all || u.has('alerts') || u.has('drawings')) {
    for (const x of s.alerts) {
      if (!syncableAlert(x)) continue
      const o = store.get('alerts', alertId(x.symbol, x.id))
      const f = o && o.body.status === 'fired' ? decodeAlert(o, true) : null
      if (f) r.fired.push(f)
    }
    const alerts = decodeAlerts(store.localOf('alerts'), s.alerts)
    if (!same(alerts, s.alerts)) { s.alerts = alerts; r.alerts = true }
    r.revive = pausedLineAlerts(store.localOf('alerts'))
    const d = decodeDrawings(store.localOf('drawings'), s.drawings)
    for (const sym of new Set([...Object.keys(d), ...Object.keys(s.drawings)])) {
      if (same(d[sym] ?? [], s.drawings[sym] ?? [])) continue
      s.drawings[sym] = d[sym] ?? []
      r.drawings.add(sym)
    }
  }
  if (all || ctx.ready) u.clear()
  else for (const c of [...u]) if (c !== 'favorites') u.delete(c)
  return r
}

/**
 * 新版本新加的同步设置字段（例如 compareSymbols）：老账本的 seen 里没有它。
 * 不先处理的话，续上账本那一下的记账会把「网页这边的出厂值」当成网页改过的推上去，把手机早就设好的值冲掉。
 * 所以账本已经对上过（seen 非空）时，seen 里缺的字段先按云端装一次（云端没有 / 表达不了就记成网页现值），
 * 返回装进来改了的字段。第一次对上（seen 为空）不走这里，由 mergeFirst 按「谁新用谁」定。
 */
export function adoptNewSettings(s: WebState, store: SyncStore): string[] {
  const seen = store.a.seen
  if (!Object.keys(seen).length) return []
  const missing = SETTINGS_FIELDS.filter(f => !(f in seen))
  if (!missing.length) return []
  const cloud = store.get('settings', SETTINGS_ID)
  const body = cloud && !cloud.deleted ? cloud.body : {}
  const changed: string[] = []
  for (const f of missing) {
    if (f === LAYOUTS_FIELD) { changed.push(...adoptBook(s, body[f], seen, 'cloud')); continue }
    const d = decodeSetting(f, body[f], s)
    if (d === undefined) { seen[f] = seenWhenUndecodable(s, f, body[f]); continue }
    seen[f] = d
    if (same(d, webSetting(s, f))) continue
    putSetting(s, f, d); changed.push(f)
  }
  return changed
}

/**
 * 布局集第一次和云端对上：云端没有 → seen 记 null（本机这份推上去）；有 → seen 记云端那份，再按 how 定本机成什么样：
 *   cloud：以云端为准，本机多出来的几套接在后面；local：以本机为准，云端多出来的几套接在后面（之后记账推上去）；
 *   replace：整份用云端的（换了人）。返回改了的字段
 */
export function adoptBook(s: WebState, cloud: Json | undefined, seen: Record<string, Json>, how: 'cloud' | 'local' | 'replace'): string[] {
  const d = decodeSetting(LAYOUTS_FIELD, cloud, s)
  if (d === undefined) { seen[LAYOUTS_FIELD] = seenWhenUndecodable(s, LAYOUTS_FIELD, cloud); return [] }
  seen[LAYOUTS_FIELD] = d
  const local = webSetting(s, LAYOUTS_FIELD)
  const cb = cleanBook(d), lb = cleanBook(local)
  const want = (how !== 'replace' && cb && lb ? (how === 'cloud' ? mergeBooks(cb, lb) : mergeBooks(lb, cb)) : d) as unknown as Json
  if (same(want, local)) return []
  putSetting(s, LAYOUTS_FIELD, want)
  return [LAYOUTS_FIELD]
}

/** 本机「最后一次改」的时刻：设置（指标、周期条……）、自选、布局集各一个 */
export interface Edited { settings: number; favorites: number; layouts?: number }

/** 第一次对上（账本是空的、刚全量拉完）：按规则合并进页面状态，之后正常记账会把本机多出来的推上去 */
export function mergeFirst(s: WebState, store: SyncStore, ctx: Ctx & { ready: boolean }, edited: Edited, override: boolean): Applied {
  const r: Applied = { settings: [], favorites: false, drawings: new Set(), alerts: false, fired: [] }
  const a = store.a
  // 本机「最后一次改」是本机钟，云端字段时间是服务器钟（op.timestamp = 本机钟 + offset）：先换到服务器钟上再比
  const onServer = (t: number): number => (t > 0 && Number.isFinite(a.offset) ? t + a.offset : t)
  edited = { settings: onServer(edited.settings), favorites: onServer(edited.favorites), layouts: onServer(edited.layouts ?? 0) }
  // 设置：云端新（或覆盖）就装云端的；本机新就什么都不装、seen 留空，记账时每个字段都会和云端比一遍
  const cloudSettings = store.get('settings', SETTINGS_ID)
  a.seen = {}
  // 换了人：先回出厂再装云端的——云端没有（新账号）或缺了的字段不能留着上一个账号的
  const reset = override ? resetSettings(s) : []
  if (override || !(edited.settings > lastTouched(cloudSettings, CORE_FIELDS))) r.settings = applySettings(s, cloudSettings, a.seen, CORE_FIELDS)
  // 布局集：换了人整份用云端的（上面已回到出厂）；同一个人时谁新以谁为准，另一边多出来的几套接在后面
  {
    const body = cloudSettings && !cloudSettings.deleted ? cloudSettings.body : {}
    const how = override ? 'replace' : (edited.layouts ?? 0) > lastTouched(cloudSettings, [LAYOUTS_FIELD]) ? 'local' : 'cloud'
    r.settings.push(...adoptBook(s, body[LAYOUTS_FIELD], a.seen, how))
  }
  r.settings = [...new Set([...reset, ...r.settings])]

  // 自选
  if (ctx.ready) {
    const favs = store.localOf('favorites').filter(o => !o.deleted)
    const cloudT = Math.max(0, ...favs.map(o => lastTouched(o)))
    let w: Record<Kind, string[]> | null = null
    if (!favs.length) { if (override) w = structuredClone(DEFAULT_WATCH) }
    else if (override || !(edited.favorites > cloudT)) w = decodeFavorites(store.localOf('favorites'), ctx)
    if (w && !same(w, s.watch)) { s.watch = w; r.favorites = true }
  }

  // 画线、提醒：并集
  const cloudAlerts = decodeAlerts(store.localOf('alerts'), [])
  r.revive = pausedLineAlerts(store.localOf('alerts'))
  const cloudDraw = decodeDrawings(store.localOf('drawings'), {})
  const draw: Record<string, typeof s.drawings[string]> = {}
  for (const [sym, list] of Object.entries(cloudDraw)) draw[sym] = [...list]
  if (!override) {
    for (const [sym, list] of Object.entries(s.drawings)) {
      for (const d of list) {
        // 云端有这条（活的已经在 cloudDraw 里，墓碑说明别处删了）就听云端的；云端从没写过 style 而本机有，扩展样式留本机的
        const o = syncableDrawing(sym, d) ? a.objects[keyOf('drawings', drawingId(sym, d.id))] : undefined
        if (o) {
          const list = draw[sym], i = list ? list.findIndex(x => x.id === d.id) : -1
          if (list && i >= 0 && !o.deleted) list[i] = keepLocalStyle(list[i], o.body, d)
          continue
        }
        ;(draw[sym] ||= []).push(d)
      }
    }
  }
  for (const sym of new Set([...Object.keys(draw), ...Object.keys(s.drawings)])) {
    if (same(draw[sym] ?? [], s.drawings[sym] ?? [])) continue
    s.drawings[sym] = draw[sym] ?? []
    r.drawings.add(sym)
  }
  const alerts = [...cloudAlerts]
  if (!override) for (const x of s.alerts) if (!syncableAlert(x) || !a.objects[keyOf('alerts', alertId(x.symbol, x.id))]) alerts.push(x)
  if (!same(alerts, s.alerts)) { s.alerts = alerts; r.alerts = true }
  a.unapplied.clear()
  return r
}

/** 本机画线存档读坏过之后第一次对上账本：把账本里云端那份（活的）并回本机，本机现有的一条不动。
 *  并完本机 ⊇ 云端，接下来的记账不会产生删除；返回并进来的品种 */
export function restoreDrawings(s: WebState, store: SyncStore): Applied {
  const r: Applied = { settings: [], favorites: false, drawings: new Set(), alerts: false, fired: [] }
  const cloud = decodeDrawings(store.localOf('drawings'), {})
  for (const [sym, list] of Object.entries(cloud)) {
    const mine = s.drawings[sym] ?? []
    const have = new Set(mine.map(d => d.id))
    const add = list.filter(d => !have.has(d.id))
    if (!add.length) continue
    s.drawings[sym] = [...mine, ...add]
    r.drawings.add(sym)
  }
  return r
}
