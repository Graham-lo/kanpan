/* Hkline Web · PC 的同步接线：页面状态适配器（st、图格、侧栏、提醒模块）
 *
 * 账号会话、领头锁、账本存档、推拉节奏都在 sync/runtime.ts（手机网页版共用那一份）；
 * 这里只回答「PC 的页面状态怎么记账、云端的值怎么装回来、装完刷新哪块界面」。
 *
 * - 登录且品种表到了（hooks.booted）之后才开始。
 * - 这台电脑第一次和这个账号对上：按 bridge.mergeFirst 合并（上一次同步的是另一个账号时云端整体覆盖本机）。
 * - 每次 save()（手势结束、改设置、加自选……）立刻记账落盘，400 ms 后推。
 */
import { st, save, subscribe, drawingsSuspect, clearDrawingsSuspect } from '../app/store'
import { hooks } from '../app/shell'
import { S } from '../market'
import { fmt } from '../util/format'
import type { IndicatorId } from '../chart/calc'
import { allCells, cfg, drawingsFor, rebaseDrawings, renderPanel, renderToolbar } from '../pages/chart'
import { announceRemoteFire, notifyAlerts, onAlertFired } from '../alerts/model'
import { type Applied, type Edited, type Prints, OWNED, adoptNewSettings, applyInto, captureInto, fingerprint, mergeFirst, restoreDrawings } from './bridge'
import { refreshCompare } from '../pages/compare'
import { type Ctx, alertId } from './codec'
import { type SyncAdapter, type SyncRuntime, createSyncRuntime } from './runtime'
import type { SyncStore } from './store'
import { syncKeys } from './keys'

export { transport } from './runtime'

const ctx: Ctx & { ready: boolean } = {
  now: () => Date.now(),
  kindOf: s => S.symbols.get(s)?.kind,
  price: s => S.symbols.get(s)?.price ?? null,
  label: (s, p) => fmt(p, S.symbols.get(s)?.dec ?? 2),
  get ready() { return S.symbols.size > 0 },
}

function lsGet(k: string): string | null { try { return localStorage.getItem(k) } catch { return null } }
function lsSet(k: string, v: string): void { try { localStorage.setItem(k, v) } catch { /* 存储满了：这一轮不落盘 */ } }

// ───────── 本机「最后一次改」的时刻（没登录时也记，首次对上时比谁新） ─────────

function readEdited(): Edited {
  try { const v = JSON.parse(lsGet(syncKeys().edited) || 'null') as Edited | null; if (v) return { settings: v.settings || 0, favorites: v.favorites || 0 } } catch { /* 坏了当没改过 */ }
  return { settings: 0, favorites: 0 }
}

// ───────── 状态适配器 ─────────

let applying = false
let fp: Prints = {}
/** 这个网页已经报过的已触发（同步 id）：记账时只删这些（codec.encodeAlerts 的 spent） */
const spent = new Set<string>()

/** 画线存档读坏过（标记还在）时只补不删 */
const hold = (): { holdDeletes: boolean } => ({ holdDeletes: drawingsSuspect() })

/** 云端的值已经装进 st：刷新受影响的界面、落盘，指纹对齐（这些不是本机的改动，不再记账）。
 *  返回 true：服务端判响的提醒记了删除，要推 */
function refreshUI(store: SyncStore, r: Applied): boolean {
  applying = true
  try {
    if (r.settings.length) {
      allCells().forEach(c => {
        c.chart.setIndicators(structuredClone(st.ind))
        for (const [k, p] of Object.entries(st.params ?? {})) c.chart.setParams(k as IndicatorId, structuredClone(p))
      })
      // 对比品种（手机 / 别的电脑改了）：每格按自己的主图重配对比
      if (r.settings.includes('compareSymbols')) refreshCompare()
      renderToolbar()
    }
    if (r.drawings.size) { r.drawings.forEach(rebaseDrawings); allCells().forEach(c => { const s = cfg(c).symbol; if (r.drawings.has(s)) c.chart.setDrawings(drawingsFor(s)) }) }
    // 走提醒模块的通知：图、侧栏，以及开着的「全部提醒」「创建提醒」弹层都跟着刷新
    if (r.alerts || r.drawings.size) notifyAlerts()
    // 自选与提醒同一轮变了也要重画自选侧栏（notifyAlerts 只在开着提醒侧栏时重画）
    if (r.favorites) renderPanel()
    if (r.settings.length || r.favorites || r.alerts || r.drawings.size) save()
  } catch (e) { console.error(e) } finally { applying = false }
  const now = fingerprint(st)
  fp.settings = now.settings; fp.drawings = now.drawings; fp.alerts = now.alerts
  if (ctx.ready) fp.favorites = now.favorites
  return settleRemoteFires(store, r)
}

/** 服务端判响、同步下来的（照手机 AlertWatcher.settle）：报给人，再记一笔删除推上去。
 *  云端还有暂停着的画线提醒：也再记一次账，把它推回生效（codec.encodeAlerts） */
function settleRemoteFires(store: SyncStore, r: Applied): boolean {
  if (!r.fired.length && !r.revive) return false
  for (const a of r.fired) { spent.add(alertId(a.symbol, a.id)); announceRemoteFire(a) }
  delete fp.alerts
  return captureInto(st, store, ctx, fp, spent, hold()) > 0
}

const pc: SyncAdapter = {
  owned: OWNED,
  capture: store => applying ? 0 : captureInto(st, store, ctx, fp, spent, hold()),
  apply: store => refreshUI(store, applyInto(st, store, ctx)),
  mergeFirst(store, override) {
    const r = mergeFirst(st, store, ctx, readEdited(), override)
    fp = {}
    const again = refreshUI(store, r)
    fp = {}
    clearDrawingsSuspect() // 并集合并过了：本机 ⊇ 云端
    if (again) rt?.pushSoon()
  },
  resume(store) {
    // 新版本新加的同步字段（compareSymbols）：老账本没记过它，先按云端装，免得续上那一下把出厂值推上去冲掉手机的
    const adopted = adoptNewSettings(st, store)
    if (adopted.length) refreshUI(store, { settings: adopted, favorites: false, drawings: new Set(), alerts: false, fired: [] })
    // 本机画线存档读坏过：先把账本里的云端那份并回来，再记账（不然本机的「空」会记成删除）
    if (drawingsSuspect()) { if (refreshUI(store, restoreDrawings(st, store))) rt?.pushSoon(); clearDrawingsSuspect() }
  },
  begin() { fp = {} },
  end() { fp = {}; spent.clear() },
}

let rt: SyncRuntime | null = null

export function initSync(): void {
  if (rt) return
  const r = rt = createSyncRuntime(pc)
  // 本机改动时刻：以启动时的样子为底
  let base = fingerprint(st)
  subscribe(() => {
    const now = fingerprint(st)
    if (!applying && (now.settings !== base.settings || now.favorites !== base.favorites)) {
      const ed = readEdited()
      if (now.settings !== base.settings) ed.settings = Date.now()
      if (now.favorites !== base.favorites && ctx.ready) ed.favorites = Date.now()
      lsSet(syncKeys().edited, JSON.stringify(ed))
    }
    base = now
    r.changed()
  })
  // 本机判响的：fire() 先记「已触发」、报完再删，删之前记下来
  onAlertFired(({ alert }) => spent.add(alertId(alert.symbol, alert.id)))
  hooks.booted.push(() => r.boot())
}
