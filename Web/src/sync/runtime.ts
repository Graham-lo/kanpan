/* Hkline Web · 同步运行时（PC 与手机网页版共用）：账号会话、领头锁、账本存档、推拉节奏
 *
 * 和页面状态有关的一切（怎么记账、怎么把云端装回来、第一次对上怎么合并、刷新哪块界面）
 * 都在「状态适配器」`SyncAdapter` 里，这里一行都不碰页面：
 *   - PC：sync/glue.ts（st = app/store，图格、侧栏、提醒模块）
 *   - 手机网页版：m/app/sync.ts（st = m/app/store）
 *
 * 规矩（两端一样）：
 * - 云端只是同步通道：没登录、服务器不通，页面照常用；本机状态永远是完整的一份。
 * - 登录且 `ready()` 之后才开始：同一账号在这个浏览器里只有一个标签页当「领头」（Web Locks），
 *   只有它推拉，免得两个标签页拿同一份账本各推各的。锁名、账本键名跟着账号键前缀走（sync/keys.ts）。
 * - 这台设备第一次和这个账号对上：全量拉一遍，交给 adapter.mergeFirst 合并，再把本机多出来的推上去。
 *   上一次在这台设备同步的是另一个账号时 override = true（云端整体覆盖本机）。
 * - 本机状态一变（adapter 调 changed()）立刻记账落盘，400 ms 后推；
 *   可见时每 15 秒推一次、拉一次增量，每 5 分钟做一次全量（兜住漏掉的与被拒的）。
 * - 账本按账号存 localStorage，推不出去的操作关掉页面也不会丢。
 */
import { authed, device } from '../account/client'
import { onSession, session } from '../account/session'
import { Engine, type Transport } from './engine'
import { type Owned, SyncStore, resumeArchive, serialize } from './store'
import { syncKeys } from './keys'
import { type ChangesPage, type Collection, type Page, type PushResponse, emptyArchive } from './types'
import { ago } from '../util/clock'

const POLL = 15e3
const FULL_EVERY = 5 * 60e3
const PUSH_DELAY = 400

/** 同步请求。`userId` 给了就只替这个账号发：会话换成别人之后，旧账本那一轮剩下的请求一律不发（见 authed 的 asUser） */
export function transportFor(userId?: string): Transport {
  return {
    push: (body, key) => authed<PushResponse>('POST', '/v1/sync/operations', body, { 'Idempotency-Key': key }, userId),
    bootstrap: (collection, prefix, after) => {
      const q = new URLSearchParams({ collection })
      if (prefix) q.set('prefix', prefix)
      if (after) q.set('after', after)
      return authed<Page>('GET', '/v1/sync/bootstrap?' + q.toString(), undefined, {}, userId)
    },
    changes: cursor => authed<ChangesPage>('GET', '/v1/sync/changes?cursor=' + cursor, undefined, {}, userId),
  }
}
export const transport: Transport = transportFor()

/** 状态适配器：页面状态这一侧的读 / 写 / 订阅 / 戳。runtime 只在「账本活着、合并完了」时调用它 */
export interface SyncAdapter {
  /** 每张表本客户端替它说话的那些键（store.stage 用：先前有、这次没有的键，属于这里的才发 null） */
  readonly owned: Owned
  /** 拉哪几张表；不给就是 COLLECTIONS（PC 那一套） */
  readonly collections?: readonly Collection[]
  /** 页面状态 → 账本（只记变了的那几块；正在装云端值时什么都不做）。返回记了几条 */
  capture(store: SyncStore): number
  /** 账本里 unapplied 的集合装回页面状态并刷新界面（外面已确认 unapplied 非空）。
   *  返回 true：装的过程里又记了账（比如服务端判响的提醒要记删除），需要推 */
  apply(store: SyncStore): boolean
  /** 这台设备第一次和这个账号对上：store 刚全量拉完。合并进页面状态、刷新界面；之后 runtime 会记账并推 */
  mergeFirst(store: SyncStore, override: boolean): void
  /** 续上已有账本、记账之前（PC：画线存档读坏过时先把云端那份并回来） */
  resume?(store: SyncStore): void
  /** 领头开始一个账号的账本（新建或续上）之前：丢掉按账本记的东西（指纹、已装过的值……） */
  begin(): void
  /** 退登 / 换账号：账本收起来之后。丢掉按会话记的一切 */
  end(): void
}

/** 同步状态（「我的」账号行用）：上一次成功对上云端的时刻、是否正在同步、最近一次失败的原因 */
export interface SyncStatus {
  /** 登录着且这个页面在同步（别的标签页领头时为 false） */
  active: boolean
  syncing: boolean
  /** 上一次成功对上的时刻（ms），从没对上过为 0；按账号落盘 */
  lastSync: number
  /** 最近一次失败的原因（给人看的一句话），成功后清空 */
  error: string
  /** 还没推上去的操作数 */
  pending: number
  /** 服务端拒掉的操作数 */
  rejected: number
}

export interface SyncRuntime {
  /** 页面状态变了（每次 save 之后调）：记账，有操作就 400 ms 后推 */
  changed(): void
  /** 页面准备好了（PC：品种表到了）；之前登录着也不开始 */
  boot(): void
  /** 立即安排一次推送 */
  pushSoon(): void
  /** 账本活着、合并完了（记账 / 应用都在进行） */
  live(): boolean
  /** 当前同步状态 */
  status(): SyncStatus
  /** 状态变了（开始 / 结束一轮、队列变了、会话变了）就叫一声。返回取消订阅 */
  onStatus(fn: () => void): () => void
  /** 立即同步一轮（「立即同步」按钮）：还没对上就再试第一次合并，否则推、拉、再推 */
  syncNow(): Promise<void>
}

/** 失败原因 → 一句话（照 iOS AccountSyncStatus 的说法） */
export function syncErrorText(e: unknown): string {
  const status = (e as { status?: number } | null)?.status
  if (status === 0) return '网络不可用，请检查网络后重试'
  if (status === 408 || status === 504) return '连接超时，请稍后重试'
  return '暂时连不上账号服务，请稍后重试'
}

function lsGet(k: string): string | null { try { return globalThis.localStorage?.getItem(k) ?? null } catch { return null } }
function lsSet(k: string, v: string): void { try { globalThis.localStorage?.setItem(k, v) } catch { /* 存储满了：这一轮不落盘，队列还在内存里 */ } }

/** 建一个运行时并挂上会话 / 前后台 / 联网事件。一个页面只建一次 */
export function createSyncRuntime(adapter: SyncAdapter): SyncRuntime {
  let booted = false
  /** 刚开始、还没合并完：记账与应用都先不做 */
  let initial = false
  let store: SyncStore | null = null
  let engine: Engine | null = null
  let uid: string | null = null
  let gen = 0
  let chain: Promise<void> = Promise.resolve()
  let pushTimer: ReturnType<typeof setTimeout> | null = null
  let pollTimer: ReturnType<typeof setInterval> | null = null
  let abort: AbortController | null = null
  let release: (() => void) | null = null
  let persistQueued = false
  let lastTick = 0
  let syncing = 0
  /** 第一次合并还没成时的 override（「立即同步」重试用同一个） */
  let firstOverride = false
  let lastSync = 0
  let error = ''
  const listeners = new Set<() => void>()
  let emitQueued = false
  function emit(): void {
    if (emitQueued) return
    emitQueued = true
    queueMicrotask(() => { emitQueued = false; for (const fn of [...listeners]) { try { fn() } catch (e) { console.error(e) } } })
  }
  const lastKey = (id: string): string => syncKeys().archive.replace(/:$/, '') + '-last:' + id

  function persist(): void {
    if (persistQueued) return
    persistQueued = true
    queueMicrotask(() => {
      persistQueued = false
      if (store && uid) lsSet(syncKeys().archive + uid, serialize(store.a))
    })
    emit()
  }

  function capture(): void {
    if (!store || initial) return
    adapter.capture(store)
  }

  function apply(): void {
    if (!store || initial || !store.a.unapplied.size) return
    if (adapter.apply(store)) schedulePush()
  }

  /** 同步任务串行执行；会话换了（gen 变了）的旧任务直接跳过 */
  function run(fn: (e: Engine) => Promise<void>): Promise<void> {
    const g = gen
    chain = chain.then(async () => {
      if (g !== gen || !engine) return
      syncing++; emit()
      try {
        await fn(engine)
        if (g === gen && !initial) { error = ''; lastSync = Date.now(); if (uid) lsSet(lastKey(uid), String(lastSync)) }
      } catch (e) {
        if (g === gen) error = syncErrorText(e)
        if ((e as { status?: number }).status !== 0) console.debug('[sync]', e)
      } finally { syncing--; emit() }
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
    if (!force && ago(lastTick, now) < 3e3) return
    lastTick = now
    void run(async e => {
      await e.push()
      if (ago(e.store.a.lastFull) > FULL_EVERY) await e.full()
      else await e.pull()
      await e.push()
    })
  }

  /** 这台设备第一次和这个账号对上（或上一次同步的是另一个账号） */
  async function firstSync(e: Engine, override: boolean): Promise<void> {
    const g = gen
    await e.full()
    // 全量拉的途中退登 / 换了账号：这份是上一个人的，不能合并进页面（页面现在是下一个人的）
    if (g !== gen) return
    initial = false
    adapter.mergeFirst(e.store, override)
    lsSet(syncKeys().owner, uid!)
    capture()
    persist()
    await e.push()
  }

  async function lead(id: string): Promise<void> {
    const owner = lsGet(syncKeys().owner)
    const saved = resumeArchive(owner, id, lsGet(syncKeys().archive + id))
    const fresh = !saved || saved.cursor == null
    store = new SyncStore(saved ?? emptyArchive(), device().id)
    store.onChange = persist
    engine = new Engine(store, transportFor(id), adapter.owned, { capture, apply }, adapter.collections)
    uid = id
    lastSync = Number(lsGet(lastKey(id))) || 0
    error = ''
    emit()
    adapter.begin()
    initial = fresh
    const g = gen
    if (fresh) {
      const override = firstOverride = !!owner && owner !== id
      // 全量拉不下来（断网、服务器挂了）就等下一轮再试，本机照常用
      const attempt = (): Promise<void> => run(async e => { if (initial) await firstSync(e, override) })
      await attempt()
      // 第一次合并的途中退登了：stop() 已经收拾过，这里再挂一个定时器就再也没人清（还会盖掉下一个账号的那个）
      if (g !== gen) return
      pollTimer = setInterval(() => { if (g !== gen) return; if (initial) void attempt(); else tick() }, POLL)
    } else {
      adapter.resume?.(store)
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
    locks.request(syncKeys().lock + id, { signal }, async () => {
      if (signal.aborted) return
      await lead(id)
      // 第一次合并的途中退登了：stop() 那时还没有 release 可调，这里再挂起就永远不放锁——
      // 同一个账号在这个标签页里再登录，锁永远轮不到，再也不同步
      if (signal.aborted) return
      await new Promise<void>(r => { release = r })
    }).catch(() => { /* 退登时还没轮到就被取消 */ })
  }

  function stop(): void {
    gen++
    if (pushTimer) clearTimeout(pushTimer)
    if (pollTimer) clearInterval(pollTimer)
    pushTimer = pollTimer = null
    if (store && uid && !initial) lsSet(syncKeys().archive + uid, serialize(store.a))
    abort?.abort(); abort = null
    release?.(); release = null
    store = null; engine = null; uid = null; initial = false
    syncing = 0; error = ''; lastSync = 0
    adapter.end()
    emit()
  }

  onSession(() => {
    if (session.userId && session.userId === uid) return
    stop()
    start()
  })
  if (typeof document !== 'undefined') document.addEventListener('visibilitychange', () => tick())
  globalThis.addEventListener?.('focus', () => tick())
  globalThis.addEventListener?.('online', () => tick(true))

  return {
    changed() {
      if (!store || initial) return
      if (adapter.capture(store)) schedulePush()
    },
    boot() { booted = true; start() },
    pushSoon() { if (store && !initial) schedulePush() },
    live() { return !!store && !initial },
    status() {
      return {
        active: !!store, syncing: syncing > 0, lastSync, error,
        pending: store?.a.operations.length ?? 0, rejected: store?.a.rejected.length ?? 0,
      }
    },
    onStatus(fn) { listeners.add(fn); return () => { listeners.delete(fn) } },
    syncNow() {
      if (!engine) return Promise.resolve()
      if (initial) {
        return run(async e => { if (initial) await firstSync(e, firstOverride) })
      }
      lastTick = Date.now()
      return run(async e => { await e.push(); await e.pull(); await e.push() })
    },
  }
}
