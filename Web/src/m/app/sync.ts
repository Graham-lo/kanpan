/* Hkline 手机网页版 · 同步接线：st（m/app/store）的状态适配器
 *
 * 账号会话、领头锁、账本、推拉节奏都在 sync/runtime.ts（和 PC 共用）；编解码在 ./syncCodec.ts。
 * 这里只回答「手机网页版的 st 怎么记账、云端的值怎么装回来、装完刷新哪块界面」。
 *
 * 规矩照 iOS AppAccountBridge：体验类设置与交互状态跟着人走——
 * - 没登录、服务器不通，照常用：st 永远是完整的一份，云端只是通道。
 * - 登录后第一次对上：设置按根比「本机最后一次改」与「云端那个根最后一次改」谁新用谁；
 *   自选新的那份做底、把旧的并进来；提醒取并集（云端墓碑的不带回）。上一次在这台设备同步的是
 *   另一个账号：云端整体覆盖。
 * - 之后每次 save() 立刻记账，400 ms 后推；前台每 15 秒拉一次。
 *
 * 界面：皮肤 / 深浅 / 涨跌色由这里 applyTheme()；自选页、「我的」页开着就重画；
 * 别的（图表的指标、周期……）订 shell 的 hooks.onSync 或 window 的 `hkline:sync` 事件自己重取。
 */
import { st, save, subscribe } from './store'
import { applyTheme, hooks, refreshPage, type SyncChange } from './shell'
import * as C from './syncCodec'
import { alertsReplaced, announceRemoteFire, onAlertFired } from '../model/alerts'
import { setSyncSource } from '../model/syncStatus'
import { type SyncAdapter, type SyncRuntime, type SyncStatus, createSyncRuntime } from '../../sync/runtime'
import type { SyncStore } from '../../sync/store'
import { syncKeys } from '../../sync/keys'
import { alertId, decodeAlerts, encodeAlerts, pausedLineAlerts } from '../../sync/codec'
import { COLLECTIONS, keyOf, same } from '../../sync/types'
import { DrawTracker, PREFS_COLLECTION, PREFS_ID, capArchive, mergeFirstDrawings, overlay } from './drawCodec'
import { clearDrawingsSuspect, drawingBook, drawingsRev, drawingsSuspect, onDrawingsChanged, replaceDrawings } from './drawings'
import type { Alert } from '../../alerts/shape'

function lsGet(k: string): string | null { try { return localStorage.getItem(k) } catch { return null } }
function lsSet(k: string, v: string): void { try { localStorage.setItem(k, v) } catch { /* 满了：这一轮不落盘 */ } }

// ───────── 本机「最后一次改」（没登录时也记；第一次对上时比谁新） ─────────

/** settings 按根记（iOS SettingsStamp），自选整张表一个时刻，画线按品种（规范键）记，画线工具偏好一个时刻 */
export interface Edited { settings: Record<string, number>; favorites: number; drawings: Record<string, number>; drawingPrefs: number }
export function readEdited(): Edited {
  try {
    const v = JSON.parse(lsGet(syncKeys().edited) || 'null') as Partial<Edited> | null
    const rec = (x: unknown): Record<string, number> => (x && typeof x === 'object' && !Array.isArray(x) ? x as Record<string, number> : {})
    const num = (x: unknown): number => (typeof x === 'number' && Number.isFinite(x) ? x : 0)
    if (v && typeof v === 'object') return { settings: rec(v.settings), favorites: num(v.favorites), drawings: rec(v.drawings), drawingPrefs: num(v.drawingPrefs) }
  } catch { /* 坏了当没改过 */ }
  return { settings: {}, favorites: 0, drawings: {}, drawingPrefs: 0 }
}

/**
 * 换到服务器钟上：本机「最后一次改」记的是本机 Date.now()，云端字段时间是服务器钟（记账时 op.timestamp =
 * 本机钟 + offset，服务端再按它记字段时间）。第一次对上比「谁新」之前必须先把本机的加上 offset，
 * 否则手机钟快几分钟就永远是本机赢（别的设备刚改的设置 / 自选 / 画线被盖回去），钟慢就永远是云端赢。
 */
export function onServerClock(ed: Edited, offset: number): Edited {
  if (!offset || !Number.isFinite(offset)) return ed
  const shift = (t: number): number => (t > 0 ? t + offset : t)
  const each = (r: Record<string, number>): Record<string, number> => Object.fromEntries(Object.entries(r).map(([k, t]) => [k, shift(t)]))
  return { settings: each(ed.settings), favorites: shift(ed.favorites), drawings: each(ed.drawings), drawingPrefs: shift(ed.drawingPrefs) }
}

// ───────── 指纹 ─────────

interface Snap { subs: Record<string, Record<string, unknown>>; settings: string; favorites: string; alerts: string; seeded: boolean }
function snap(): Snap {
  const subs = C.settingsSubs(st)
  return { subs, settings: JSON.stringify(subs), favorites: C.favPrint(st.symbols), alerts: JSON.stringify(st.alerts), seeded: st.symbols.seeded }
}
type Prints = Partial<Record<'settings' | 'favorites' | 'alerts', string>>

// ───────── 适配器 ─────────

let applying = false
let fp: Prints = {}
/** 这个页面已经报过的已触发（同步 id）：记账时只删这些（codec.encodeAlerts 的 spent） */
const spent = new Set<string>()
/** 画线按品种分桶的指纹（drawCodec.DrawTracker）；和 fp 分开记，settle 不动它 */
const draw = new DrawTracker()
/** 画线本上一次记过账时的版本号（没变就不比指纹） */
let drawSeen = -1

function captureInto(store: SyncStore): number {
  if (applying) return 0
  const now = snap()
  const vals = []
  if (now.settings !== fp.settings) {
    const o = C.encodeSettings(st, store.get('settings', C.SETTINGS_ID), store.a.seen)
    if (o) vals.push(o)
    fp.settings = now.settings
  }
  if (now.favorites !== fp.favorites) {
    vals.push(...C.encodeFavorites(st.symbols, store.localOf('favorites'), store.localOf('groups')))
    fp.favorites = now.favorites
  }
  if (now.alerts !== fp.alerts) {
    vals.push(...encodeAlerts(st.alerts, store.localOf('alerts'), spent))
    fp.alerts = now.alerts
  }
  if (drawingsRev() !== drawSeen || draw.prints == null) {
    vals.push(...draw.capture(drawingBook.archive, store, drawingsSuspect()))
    drawSeen = drawingsRev()
  }
  return store.capture(vals, C.OWNED_M)
}

function assignFavorites(f: C.FavState): boolean {
  const cur = st.symbols
  if (same(f.favorites, cur.favorites) && same(f.groups, cur.groups) && same(f.groupForSymbol, cur.groupForSymbol)) return false
  cur.favorites = f.favorites; cur.groups = f.groups; cur.groupForSymbol = f.groupForSymbol
  return true
}

/** 云端的值已经装进 st：落盘、刷新界面、指纹对齐（这些不是本机的改动，不再记账）。
 *  并掉了同名分类、服务端判响了提醒、或云端还有暂停着的画线提醒（`revive`，要推回生效）：
 *  要再记一次账（返回 true = 记了，要推） */
function settle(store: SyncStore | null, r: SyncChange, fired: Alert[], merged: Record<string, string>, revive = false): boolean {
  applying = true
  try {
    if (st.favoritesGroup && merged[st.favoritesGroup]) st.favoritesGroup = merged[st.favoritesGroup]
    if (r.settings.length || r.favorites || r.alerts) save()
    if (r.settings.length) applyTheme()
    if (r.alerts) alertsReplaced()
    if (r.settings.length || r.favorites || r.alerts || r.drawings.length || r.drawingPreferences) {
      for (const fn of hooks.onSync) { try { fn(r) } catch (e) { console.error(e) } }
      globalThis.dispatchEvent?.(new CustomEvent('hkline:sync', { detail: r }))
      if (r.favorites || r.settings.includes('favoritesGroup')) refreshPage(['favorites'])
    }
  } catch (e) { console.error(e) } finally { applying = false }
  const now = snap()
  fp = { settings: now.settings, favorites: now.favorites, alerts: now.alerts }
  base = now
  let again = false
  if (Object.keys(merged).length) { delete fp.favorites; again = true }
  if (fired.length) {
    // 服务端判响、同步下来的（照手机 AlertWatcher.settle）：报给人，再记一笔删除推上去
    for (const a of fired) { spent.add(alertId(a.symbol, a.id)); announceRemoteFire(a) }
    delete fp.alerts; again = true
  }
  if (revive) { delete fp.alerts; again = true }
  return again && !!store && captureInto(store) > 0
}

/** 云端的画线装进画线本（applying 期间调）：只有真变了才换；返回变了的品种、工具偏好换没换、裁掉几条 */
function applyDrawings(store: SyncStore, r: SyncChange): number {
  const { next, keys, dropped } = draw.apply(drawingBook.archive, store)
  if (next) {
    r.drawings = keys
    r.drawingPreferences = !drawingBook.preferences.equals(next.preferences)
    replaceDrawings(next)
  }
  // 指纹已对齐到「裁之前」：裁掉了的话下一次记账要比指纹（推删除），否则不必
  drawSeen = dropped > 0 ? -1 : drawingsRev()
  return dropped
}

const blankChange = (): SyncChange => ({ settings: [], favorites: false, alerts: false, drawings: [], drawingPreferences: false })

const mobile: SyncAdapter = {
  owned: C.OWNED_M,
  collections: [...COLLECTIONS, PREFS_COLLECTION as 'drawingPreferences'],
  capture: store => captureInto(store),
  apply(store) {
    const u = store.a.unapplied
    const r = blankChange()
    let fired: Alert[] = []
    let dropped = 0
    let merged: Record<string, string> = {}
    let revive = false
    if (u.has('settings')) r.settings = C.applySettings(st, store.get('settings', C.SETTINGS_ID), store.a.seen)
    if (u.has('favorites') || u.has('groups')) {
      const d = C.decodeFavorites(store.localOf('favorites'), store.localOf('groups'), st.symbols)
      merged = d.merged
      r.favorites = assignFavorites(d)
    }
    if (u.has('alerts') || u.has('drawings')) {
      fired = C.remoteFired(st.alerts, id => store.get('alerts', id))
      const alerts = decodeAlerts(store.localOf('alerts'), st.alerts)
      if (!same(alerts, st.alerts)) { st.alerts = alerts; r.alerts = true }
      revive = pausedLineAlerts(store.localOf('alerts'))
    }
    if (u.has('drawings') || u.has(PREFS_COLLECTION)) {
      applying = true
      try { dropped = applyDrawings(store, r) } finally { applying = false }
    }
    u.clear()
    const again = settle(store, r, fired, merged, revive)
    // 进门裁掉了几条（每品种 50 条）：推成删除，云端和别的设备收敛到同一份
    return (dropped > 0 && captureInto(store) > 0) || again
  },
  mergeFirst(store, override) {
    const ed = onServerClock(readEdited(), store.a.offset)
    store.a.seen = {}
    const r: SyncChange = { ...blankChange(), settings: C.mergeSettings(st, store.get('settings', C.SETTINGS_ID), store.a.seen, ed.settings, override) }
    const fresh = (): C.FavState => ({ favorites: [], groups: [], groupForSymbol: {} })
    const fav = C.mergeFavorites(st.symbols, store.localOf('favorites'), store.localOf('groups'), ed.favorites, override, fresh)
    let merged: Record<string, string> = {}
    if (fav) {
      merged = fav.merged
      r.favorites = assignFavorites(fav)
      // 云端给了自选：不再往上面种默认那几只；覆盖成空的（换了人）：让自选页重新种
      const cloudEmpty = !fav.favorites.length && !fav.groups.length
      const seeded = !(override && cloudEmpty)
      if (st.symbols.seeded !== seeded) { st.symbols.seeded = seeded; r.favorites = true }
    }
    const alerts = C.mergeAlerts(st.alerts, store.localOf('alerts'), override, id => !!store.a.objects[keyOf('alerts', id)])
    if (!same(alerts, st.alerts)) { st.alerts = alerts; r.alerts = true }
    // 画线：并集（云端墓碑的不带回，同一条谁新用谁），换账号云端整体覆盖；再裁到每品种 50 条
    const before = drawingBook.archive
    const next = mergeFirstDrawings(before, store.localOf('drawings'), store.get(PREFS_COLLECTION, PREFS_ID),
      { drawings: ed.drawings, prefs: ed.drawingPrefs }, override)
    applying = true
    try {
      r.drawingPreferences = !before.preferences.equals(next.preferences)
      r.drawings = [...new Set([...Object.keys(before.bySymbol), ...Object.keys(next.bySymbol)])].filter(k => before.bucketChanged(next, k))
      replaceDrawings(next, override)
      clearDrawingsSuspect()
    } finally { applying = false }
    store.a.unapplied.clear()
    settle(null, r, [], merged)
    fp = {} // runtime 接着记一次全量账：本机多出来的都推上去
    draw.reset()
  },
  resume(store) {
    // 本机画线存档读坏过：先把云端那份并回来（本机剩下的留着），之后才按「本机删了」推删除
    if (!drawingsSuspect()) return
    const next = drawingBook.archive.clone()
    const objs = store.localOf('drawings')
    overlay(next, objs.filter(o => !o.deleted), store.get(PREFS_COLLECTION, PREFS_ID))
    capArchive(next, objs)
    applying = true
    try { replaceDrawings(next) } finally { applying = false }
    clearDrawingsSuspect()
    draw.reset()
  },
  begin() { fp = {}; draw.reset() },
  end() { fp = {}; spent.clear(); draw.reset() },
}

// ───────── 对外 ─────────

let rt: SyncRuntime | null = null
let base: Snap | null = null

/** 壳启动时调一次：登录着就开始同步，没登录就等登录 */
export function initMobileSync(): void {
  if (rt) return
  const r = rt = createSyncRuntime(mobile)
  base = snap()
  subscribe(() => {
    const now = snap()
    if (!applying && base) {
      const roots = C.changedRoots(base.subs as never, now.subs as never)
      // 种默认自选（seeded 由 false 变 true 的那一下）不算用户改过
      const favEdited = now.favorites !== base.favorites && !(now.seeded && !base.seeded)
      if (roots.length || favEdited) {
        const ed = readEdited()
        const t = Date.now()
        for (const k of roots) ed.settings[k] = t
        if (favEdited) ed.favorites = t
        lsSet(syncKeys().edited, JSON.stringify(ed))
      }
    }
    base = now
    r.changed()
  })
  // 画线：本机编辑记下这只品种「最后一次改」（第一次对上时比谁新），然后记账
  onDrawingsChanged(c => {
    // 同步换进来的都在 applying 里；这之外的 replaced（控制器 setDrawings 整桶换）也是本机改的
    if (!applying) {
      const ed = readEdited()
      const t = Date.now()
      if (c.kind === 'edited') ed.drawings[c.key] = t
      else if (c.kind === 'replaced') for (const k of c.keys) ed.drawings[k] = t
      else ed.drawingPrefs = t
      lsSet(syncKeys().edited, JSON.stringify(ed))
    }
    r.changed()
  })
  // 本机判响的：fire() 先记「已触发」、报完再删，删之前记下来（服务端判响的那种由 settle 记）
  onAlertFired(({ alert, remote }) => { if (!remote) spent.add(alertId(alert.symbol, alert.id)) })
  setSyncSource({
    state: () => {
      const s = r.status()
      return { error: s.error || (s.rejected ? `${s.rejected} 项暂未同步` : ''), pending: s.pending, lastSync: s.lastSync || null }
    },
    syncNow: () => { void r.syncNow() },
    onChange: fn => r.onStatus(fn),
  })
  r.boot()
}

const idle: SyncStatus = { active: false, syncing: false, lastSync: 0, error: '', pending: 0, rejected: 0 }
/** 同步状态：上次同步时间 / 进行中 / 失败原因 / 待推条数 */
export const syncStatus = (): SyncStatus => rt?.status() ?? idle
/** 状态变了叫一声；返回退订 */
export const onSyncStatus = (fn: () => void): (() => void) => rt?.onStatus(fn) ?? (() => {})
/** 「立即同步」 */
export const syncNow = (): Promise<void> => rt?.syncNow() ?? Promise.resolve()
