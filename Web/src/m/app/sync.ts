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
import { st, save, subscribe, layoutSettled } from './store'
import { applyTheme, hooks, refreshPage, type SyncChange } from './shell'
import * as C from './syncCodec'
import { alertsReplaced, announceRemoteFire, onAlertFired } from '../model/alerts'
import { setSyncSource } from '../model/syncStatus'
import { type SyncAdapter, type SyncRuntime, type SyncStatus, createSyncRuntime } from '../../sync/runtime'
import type { SyncStore } from '../../sync/store'
import { syncKeys } from '../../sync/keys'
import { alertId, decodeAlerts, encodeAlerts, unseenDrawings } from '../../sync/codec'
import { keyOf, same } from '../../sync/types'
import type { Alert } from '../../alerts/shape'

function lsGet(k: string): string | null { try { return localStorage.getItem(k) } catch { return null } }
function lsSet(k: string, v: string): void { try { localStorage.setItem(k, v) } catch { /* 满了：这一轮不落盘 */ } }

// ───────── 本机「最后一次改」（没登录时也记；第一次对上时比谁新） ─────────

/** settings 按根记（iOS SettingsStamp），自选整张表一个时刻 */
export interface Edited { settings: Record<string, number>; favorites: number }
export function readEdited(): Edited {
  try {
    const v = JSON.parse(lsGet(syncKeys().edited) || 'null') as Partial<Edited> | null
    if (v && typeof v === 'object') return { settings: v.settings && typeof v.settings === 'object' ? v.settings : {}, favorites: typeof v.favorites === 'number' ? v.favorites : 0 }
  } catch { /* 坏了当没改过 */ }
  return { settings: {}, favorites: 0 }
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
    vals.push(...encodeAlerts(st.alerts, store.localOf('alerts'), unseenDrawings(store.localOf('drawings')), spent))
    fp.alerts = now.alerts
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
 *  并掉了同名分类、或服务端判响了提醒：要再记一次账（返回 true = 记了，要推） */
function settle(store: SyncStore | null, r: SyncChange, fired: Alert[], merged: Record<string, string>): boolean {
  applying = true
  try {
    if (st.favoritesGroup && merged[st.favoritesGroup]) st.favoritesGroup = merged[st.favoritesGroup]
    if (r.settings.length) layoutSettled()
    if (r.settings.length || r.favorites || r.alerts) save()
    if (r.settings.length) applyTheme()
    if (r.alerts) alertsReplaced()
    if (r.settings.length || r.favorites || r.alerts) {
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
  return again && !!store && captureInto(store) > 0
}

const mobile: SyncAdapter = {
  owned: C.OWNED_M,
  capture: store => captureInto(store),
  apply(store) {
    const u = store.a.unapplied
    const r: SyncChange = { settings: [], favorites: false, alerts: false }
    let fired: Alert[] = []
    let merged: Record<string, string> = {}
    if (u.has('settings')) r.settings = C.applySettings(st, store.get('settings', C.SETTINGS_ID), store.a.seen)
    if (u.has('favorites') || u.has('groups')) {
      const d = C.decodeFavorites(store.localOf('favorites'), store.localOf('groups'), st.symbols)
      merged = d.merged
      r.favorites = assignFavorites(d)
    }
    if (u.has('alerts') || u.has('drawings')) {
      fired = C.remoteFired(st.alerts, id => store.get('alerts', id))
      const alerts = decodeAlerts(store.localOf('alerts'), st.alerts, unseenDrawings(store.localOf('drawings')))
      if (!same(alerts, st.alerts)) { st.alerts = alerts; r.alerts = true }
    }
    u.clear()
    return settle(store, r, fired, merged)
  },
  mergeFirst(store, override) {
    const ed = readEdited()
    store.a.seen = {}
    const r: SyncChange = { settings: C.mergeSettings(st, store.get('settings', C.SETTINGS_ID), store.a.seen, ed.settings, override), favorites: false, alerts: false }
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
    const alerts = C.mergeAlerts(st.alerts, store.localOf('alerts'), store.localOf('drawings'), override, id => !!store.a.objects[keyOf('alerts', id)])
    if (!same(alerts, st.alerts)) { st.alerts = alerts; r.alerts = true }
    store.a.unapplied.clear()
    settle(null, r, [], merged)
    fp = {} // runtime 接着记一次全量账：本机多出来的都推上去
  },
  begin() { fp = {} },
  end() { fp = {}; spent.clear() },
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
