/* Hkline Web · 同步接线：页面状态、账号会话、同步引擎、界面刷新
 *
 * - 云端只是同步通道：没登录、服务器不通，页面照常用；本机 st 永远是完整的一份。
 * - 登录且品种表到了之后才开始：同一账号在这个浏览器里只有一个标签页当「领头」（Web Locks），
 *   只有它推拉，免得两个标签页拿同一份账本各推各的。
 * - 这台电脑第一次和这个账号对上：全量拉一遍，按 bridge.mergeFirst 合并，再把本机多出来的推上去。
 *   上一次在这台电脑同步的是另一个账号时，云端整体覆盖本机。
 * - 每次 save()（手势结束、改设置、加自选……）立刻记账落盘，400 ms 后推；
 *   可见时每 15 秒推一次、拉一次增量，每 5 分钟做一次全量（兜住漏掉的与被拒的）。
 * - 账本按账号存 localStorage，推不出去的操作关掉页面也不会丢。
 */
import { st, save, subscribe } from '../app/store'
import { hooks } from '../app/shell'
import { S } from '../market'
import { fmt } from '../util/format'
import type { IndicatorId } from '../chart/calc'
import { allCells, cfg, drawingsFor, renderPanel, renderToolbar } from '../pages/chart'
import { announceRemoteFire, notifyAlerts, onAlertFired } from '../alerts/model'
import { authed, device } from '../account/client'
import { onSession, session } from '../account/session'
import { type Applied, type Edited, type Prints, OWNED, applyInto, captureInto, fingerprint, mergeFirst } from './bridge'
import { type Ctx, alertId } from './codec'
import { Engine, type Transport } from './engine'
import { SyncStore, deserialize, serialize } from './store'
import { type ChangesPage, type Page, type PushResponse, emptyArchive } from './types'

const ARCHIVE_KEY = 'hkline-web-sync-v1:'
const OWNER_KEY = 'hkline-web-sync-owner'
const EDITED_KEY = 'hkline-web-edited-v1'
const POLL = 15e3
const FULL_EVERY = 5 * 60e3
const PUSH_DELAY = 400

export const transport: Transport = {
  push: (body, key) => authed<PushResponse>('POST', '/v1/sync/operations', body, { 'Idempotency-Key': key }),
  bootstrap: (collection, prefix, after) => {
    const q = new URLSearchParams({ collection })
    if (prefix) q.set('prefix', prefix)
    if (after) q.set('after', after)
    return authed<Page>('GET', '/v1/sync/bootstrap?' + q.toString())
  },
  changes: cursor => authed<ChangesPage>('GET', '/v1/sync/changes?cursor=' + cursor),
}

const ctx: Ctx & { ready: boolean } = {
  now: () => Date.now(),
  kindOf: s => S.symbols.get(s)?.kind,
  price: s => S.symbols.get(s)?.price ?? null,
  label: (s, p) => fmt(p, S.symbols.get(s)?.dec ?? 2),
  get ready() { return S.symbols.size > 0 },
}

function lsGet(k: string): string | null { try { return localStorage.getItem(k) } catch { return null } }
function lsSet(k: string, v: string): void { try { localStorage.setItem(k, v) } catch { /* 存储满了：这一轮不落盘，队列还在内存里 */ } }

// ───────── 本机「最后一次改」的时刻（没登录时也记，首次对上时比谁新） ─────────

function readEdited(): Edited {
  try { const v = JSON.parse(lsGet(EDITED_KEY) || 'null') as Edited | null; if (v) return { settings: v.settings || 0, favorites: v.favorites || 0 } } catch { /* 坏了当没改过 */ }
  return { settings: 0, favorites: 0 }
}

// ───────── 运行时 ─────────

let booted = false
let applying = false
/** 刚开始、还没合并完：记账与应用都先不做 */
let initial = false
let store: SyncStore | null = null
let engine: Engine | null = null
let uid: string | null = null
let gen = 0
let chain: Promise<void> = Promise.resolve()
let fp: Prints = {}
let pushTimer: ReturnType<typeof setTimeout> | null = null
let pollTimer: ReturnType<typeof setInterval> | null = null
let abort: AbortController | null = null
let release: (() => void) | null = null
let persistQueued = false
let lastTick = 0
/** 这个网页已经报过的已触发（同步 id）：记账时只删这些（codec.encodeAlerts 的 spent） */
const spent = new Set<string>()

function persist(): void {
  if (persistQueued) return
  persistQueued = true
  queueMicrotask(() => {
    persistQueued = false
    if (store && uid) lsSet(ARCHIVE_KEY + uid, serialize(store.a))
  })
}

function capture(): void {
  if (!store || initial || applying) return
  captureInto(st, store, ctx, fp, spent)
}

function apply(): void {
  if (!store || initial || !store.a.unapplied.size) return
  refreshUI(applyInto(st, store, ctx))
}

/** 云端的值已经装进 st：刷新受影响的界面、落盘，指纹对齐（这些不是本机的改动，不再记账） */
function refreshUI(r: Applied): void {
  applying = true
  try {
    if (r.settings.length) {
      allCells().forEach(c => {
        c.chart.setIndicators(structuredClone(st.ind))
        for (const [k, p] of Object.entries(st.params ?? {})) c.chart.setParams(k as IndicatorId, structuredClone(p))
      })
      renderToolbar()
    }
    if (r.drawings.size) allCells().forEach(c => { const s = cfg(c).symbol; if (r.drawings.has(s)) c.chart.setDrawings(drawingsFor(s)) })
    // 走提醒模块的通知：图、侧栏，以及开着的「全部提醒」「创建提醒」弹层都跟着刷新
    if (r.alerts || r.drawings.size) notifyAlerts()
    else if (r.favorites) renderPanel()
    if (r.settings.length || r.favorites || r.alerts || r.drawings.size) save()
  } catch (e) { console.error(e) } finally { applying = false }
  const now = fingerprint(st)
  fp.settings = now.settings; fp.drawings = now.drawings; fp.alerts = now.alerts
  if (ctx.ready) fp.favorites = now.favorites
  settleRemoteFires(r)
}

/** 服务端判响、同步下来的（照手机 AlertWatcher.settle）：报给人，再记一笔删除推上去 */
function settleRemoteFires(r: Applied): void {
  if (!r.fired.length || !store) return
  for (const a of r.fired) { spent.add(alertId(a.symbol, a.id)); announceRemoteFire(a) }
  delete fp.alerts
  if (captureInto(st, store, ctx, fp, spent)) schedulePush()
}

/** 同步任务串行执行；会话换了（gen 变了）的旧任务直接跳过 */
function run(fn: (e: Engine) => Promise<void>): Promise<void> {
  const g = gen
  chain = chain.then(async () => {
    if (g !== gen || !engine) return
    try { await fn(engine) } catch (e) { if ((e as { status?: number }).status !== 0) console.debug('[sync]', e) }
  })
  return chain
}

function schedulePush(): void {
  if (pushTimer) clearTimeout(pushTimer)
  pushTimer = setTimeout(() => { pushTimer = null; void run(e => e.push()) }, PUSH_DELAY)
}

function tick(force = false): void {
  if (!engine || initial) return
  if (typeof document !== 'undefined' && document.visibilityState === 'hidden') return
  const now = Date.now()
  if (!force && now - lastTick < 3e3) return
  lastTick = now
  void run(async e => {
    await e.push()
    if (Date.now() - e.store.a.lastFull > FULL_EVERY) await e.full()
    else await e.pull()
    await e.push()
  })
}

/** 这台电脑第一次和这个账号对上（或上一次同步的是另一个账号） */
async function firstSync(e: Engine, override: boolean): Promise<void> {
  await e.full()
  const r = mergeFirst(st, e.store, ctx, readEdited(), override)
  initial = false
  fp = {}
  refreshUI(r)
  fp = {}
  lsSet(OWNER_KEY, uid!)
  capture()
  persist()
  await e.push()
}

async function lead(id: string): Promise<void> {
  const owner = lsGet(OWNER_KEY)
  const saved = owner === id ? deserialize(lsGet(ARCHIVE_KEY + id)) : null
  const fresh = !saved || saved.cursor == null
  store = new SyncStore(saved ?? emptyArchive(), device().id)
  store.onChange = persist
  engine = new Engine(store, transport, OWNED, { capture, apply })
  uid = id
  fp = {}
  initial = fresh
  const g = gen
  if (fresh) {
    const override = !!owner && owner !== id
    // 全量拉不下来（断网、服务器挂了）就等下一轮再试，本机照常用
    const attempt = (): Promise<void> => run(async e => { if (initial) await firstSync(e, override) })
    await attempt()
    pollTimer = setInterval(() => { if (g !== gen) return; if (initial) void attempt(); else tick() }, POLL)
  } else {
    // 离线期间（包括没登录时）的改动：先记账推上去，再拉
    capture()
    tick(true)
    pollTimer = setInterval(() => tick(), POLL)
  }
}

function start(): void {
  const id = session.userId
  if (!booted || !id || uid === id || abort) return
  gen++
  abort = new AbortController()
  const signal = abort.signal
  const locks = (globalThis.navigator as Navigator | undefined)?.locks
  if (!locks?.request) { void lead(id); return }
  locks.request('hkline-sync:' + id, { signal }, async () => {
    if (signal.aborted) return
    await lead(id)
    await new Promise<void>(r => { release = r })
  }).catch(() => { /* 退登时还没轮到就被取消 */ })
}

function stop(): void {
  gen++
  if (pushTimer) clearTimeout(pushTimer)
  if (pollTimer) clearInterval(pollTimer)
  pushTimer = pollTimer = null
  if (store && uid && !initial) lsSet(ARCHIVE_KEY + uid, serialize(store.a))
  abort?.abort(); abort = null
  release?.(); release = null
  store = null; engine = null; uid = null; initial = false; fp = {}
  spent.clear()
}

export function initSync(): void {
  // 本机改动时刻：以启动时的样子为底
  let base = fingerprint(st)
  subscribe(() => {
    const now = fingerprint(st)
    if (!applying && (now.settings !== base.settings || now.favorites !== base.favorites)) {
      const ed = readEdited()
      if (now.settings !== base.settings) ed.settings = Date.now()
      if (now.favorites !== base.favorites && ctx.ready) ed.favorites = Date.now()
      lsSet(EDITED_KEY, JSON.stringify(ed))
    }
    base = now
    if (!store || initial || applying) return
    if (captureInto(st, store, ctx, fp, spent)) schedulePush()
  })
  // 本机判响的：fire() 先记「已触发」、报完再删，删之前记下来
  onAlertFired(({ alert }) => spent.add(alertId(alert.symbol, alert.id)))
  hooks.booted.push(() => { booted = true; start() })
  onSession(() => {
    if (session.userId && session.userId === uid) return
    stop()
    start()
  })
  if (typeof document !== 'undefined') document.addEventListener('visibilitychange', () => tick())
  globalThis.addEventListener?.('focus', () => tick())
  globalThis.addEventListener?.('online', () => tick(true))
}
