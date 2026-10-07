/* Hkline Web · 同步引擎（手机端 KanpanAccount/SyncEngine.swift 的推送循环 + 拉取）
 *
 * 推送：
 * - 一批最多 100 条；有「嫌疑」时（上一批被整批拒了）每批减半，二分出那条坏的。
 * - 发之前先 markSent：结果没回来（断网、5xx、401）时 sent 保持，下一轮用同一个 op id 重发，
 *   服务端按 id 幂等交回上一次的结果。
 * - 413：退回，请求体预算减半（最低 16 KiB）再试；压到底还 413 就按条数二分；单条就超预算的挪进被拒。
 * - 409 resync_required：退回，按这批涉及的范围重拉云端，realign 把队列按服务端规则重新推演，再推；
 *   一轮最多重来 3 次。
 * - 永久错误（400 / 422 / invalid_operation / idempotency_mismatch）：整批事务已回滚，退回；
 *   不止一条就标嫌疑二分，只剩一条就把它挪进被拒。
 * - acknowledge 之后队列一条都没少就停（防止死循环）。
 *
 * 拉取：
 * - 全量：settings → favorites → groups → alerts → drawings 逐页 bootstrap，游标取第一页的
 *   （拉的过程中别处改的，下一次 changes 会补上），最后跑一遍 retryRejected。
 * - 增量：`/v1/sync/changes` 不带范围，全部回来的都是 invalidation；revision 不比本机新的跳过，
 *   其余按对象（多了按集合）重新 bootstrap。410 cursor_expired 就退回全量。
 *
 * 每次 receive / acknowledge 之前先 capture（页面上还没记账的改动先进队列，免得被云端那份盖掉），
 * 之后立刻 apply（云端的新值马上装进页面，中间不留 await）。
 */
import { SyncStore, encodedSize, pushBody, type Owned } from './store'
import { COLLECTIONS, type ChangesPage, type Collection, type Page, type PushResponse, type Scope, type SyncOperation, keyOf } from './types'

export interface Transport {
  push(body: string, idempotencyKey: string): Promise<PushResponse>
  bootstrap(collection: string, prefix?: string, after?: string | null): Promise<Page>
  changes(cursor: number): Promise<ChangesPage>
}

export interface Hooks {
  /** 页面状态 → 账本（没变化就什么都不做） */
  capture(): void
  /** 账本里云端改过的集合 → 页面状态 */
  apply(): void
}

interface Err { status?: number; code?: string; reason?: string }

/** 一条操作被服务端永久拒了（400 / 422，单条隔开挪进 rejected 之后）：谁关心谁订（提醒层拿它弹中文原因） */
export interface Rejected { op: SyncOperation; code: string; reason?: string }
const rejectedHandlers = new Set<(r: Rejected) => void>()
export function onRejected(fn: (r: Rejected) => void): () => void { rejectedHandlers.add(fn); return () => { rejectedHandlers.delete(fn) } }
function reportRejected(r: Rejected): void { rejectedHandlers.forEach(f => { try { f(r) } catch (e) { console.error(e) } }) }

export const MAX_BATCH = 100
export const MAX_BODY = 384 * 1024
export const MIN_BODY = 16 * 1024
export const RESYNC_BUDGET = 3
/** 一个集合里要重拉的对象超过这个数，就整张表重拉 */
const PER_OBJECT_LIMIT = 12

export function isPermanent(e: Err): boolean {
  if (e.code === 'idempotency_mismatch') return true
  if (e.status === 401 || e.status === 409 || e.status === 429) return false
  return e.status === 400 || e.status === 422 || e.code === 'invalid_operation'
}

/** 这批操作涉及的云端范围：画线与提醒按品种前缀（venue/market/SYM/），其余整张表 */
export function scopesOf(ops: SyncOperation[]): Scope[] {
  const out = new Map<string, Scope>()
  for (const op of ops) {
    let s: Scope = { collection: op.collection }
    if (op.collection === 'drawings' || op.collection === 'alerts') {
      const cut = op.objectId.lastIndexOf('/')
      if (cut > 0) s = { collection: op.collection, prefix: op.objectId.slice(0, cut + 1) }
    }
    out.set(s.collection + '|' + (s.prefix ?? ''), s)
  }
  // 整张表已经在里面了，同表的前缀就不必再拉
  for (const [k, s] of out) if (s.prefix && out.has(s.collection + '|')) out.delete(k)
  return [...out.values()]
}

/** 服务端回来的一页形状对不对。不对（代理吐了个错误页、网关截断、字段缺了）就当「没拉到」抛出——
 *  绝不能把它当成「云端是空的」装进账本：那样本机会以为别处删光了，或者把一份空表记账推上去 */
export function badPage(p: unknown, changes = false): boolean {
  const o = p as Partial<ChangesPage> | null
  if (!o || typeof o !== 'object' || !Array.isArray(o.objects) || !Number.isFinite(o.cursor) || !Number.isFinite(o.serverTime)) return true
  if (!o.objects.every(x => x && typeof x === 'object' && typeof x.collection === 'string' && typeof x.id === 'string' && x.body != null && typeof x.body === 'object')) return true
  if (changes) return !Array.isArray(o.invalidations) || typeof o.hasMore !== 'boolean'
  const n = (p as Page).next
  return n != null && typeof n !== 'string'
}
const BAD_PAGE: Err = { status: 502, code: 'bad_page' }

export class Engine {
  budget = MAX_BODY
  suspects = 0
  constructor(public store: SyncStore, public t: Transport, public owned: Owned, public hooks: Hooks,
    /** 拉哪几张表（全量按这个顺序；增量只重拉这几张的失效） */
    public collections: readonly Collection[] = COLLECTIONS) {}

  /** 把队列推空（或推到推不动为止）。网络 / 服务器 / 登录类错误原样抛出，下一轮再来 */
  async push(): Promise<void> {
    const s = this.store
    let resyncs = 0
    for (;;) {
      this.hooks.capture()
      const limit = this.suspects > 0 ? Math.max(1, Math.floor(this.suspects / 2)) : MAX_BATCH
      const batch = s.nextBatch(limit, this.budget)
      if (!batch.length) return
      if (batch.length === 1 && encodedSize(batch) > this.budget) {
        s.quarantine(batch[0].id, 'payload_too_large')
        this.suspects = Math.max(0, this.suspects - 1)
        continue
      }
      const ids = batch.map(o => o.id)
      s.markSent(ids)
      let res: PushResponse
      try {
        res = await this.t.push(pushBody(batch), batch[0].id)
      } catch (e) {
        const err = e as Err
        if (err.status === 413) {
          s.rollback(ids)
          // 预算已经压到底还是太大：按条数二分，只剩一条就挪进被拒（不然会原地打转）
          if (this.budget <= MIN_BODY) {
            if (batch.length > 1) { this.suspects = batch.length; continue }
            s.quarantine(batch[0].id, 'payload_too_large')
            continue
          }
          this.budget = Math.max(MIN_BODY, Math.floor(Math.min(this.budget, encodedSize(batch)) / 2))
          continue
        }
        if (err.status === 409 && err.code === 'resync_required') {
          s.rollback(ids)
          if (++resyncs > RESYNC_BUDGET) throw e
          await this.refetch(scopesOf(batch))
          s.realign()
          continue
        }
        if (isPermanent(err)) {
          s.rollback(ids)
          if (batch.length > 1) { this.suspects = batch.length; continue }
          s.quarantine(batch[0].id, err.code || 'rejected')
          reportRejected({ op: batch[0], code: err.code || 'rejected', reason: err.reason })
          this.suspects = 0
          continue
        }
        throw e
      }
      this.hooks.capture()
      const before = s.a.operations.length
      s.acknowledge(res)
      this.hooks.apply()
      this.suspects = Math.max(0, this.suspects - batch.length)
      if (s.a.operations.length >= before) return
    }
  }

  /** 拉一个范围的全部对象（逐页），装进账本并立刻应用。返回第一页的游标 */
  async fetchScope(scope: Scope): Promise<number> {
    let after: string | null = null
    let first: number | null = null
    do {
      const p: Page = await this.t.bootstrap(scope.collection, scope.prefix, after)
      if (badPage(p)) throw BAD_PAGE
      if (first == null) first = p.cursor
      this.hooks.capture()
      this.store.receive(p.objects, p.serverTime)
      this.hooks.apply()
      after = p.next
    } while (after)
    return first ?? 0
  }

  async refetch(scopes: Scope[]): Promise<void> {
    for (const sc of scopes) await this.fetchScope(sc)
  }

  /** 全量：每张表从头拉一遍，然后补推被拒过的 */
  async full(): Promise<void> {
    let cursor: number | null = null
    for (const c of this.collections) {
      const cur = await this.fetchScope({ collection: c })
      if (cursor == null || cur < cursor) cursor = cur
    }
    this.hooks.capture()
    this.store.retryRejected(this.owned)
    this.store.a.cursor = cursor ?? 0
    this.store.a.lastFull = Date.now()
    this.store.onChange()
  }

  /** 增量：从游标往后看谁变了，变了的重拉 */
  async pull(): Promise<void> {
    const a = this.store.a
    if (a.cursor == null) return this.full()
    try {
      for (let guard = 0; guard < 50; guard++) {
        const p: ChangesPage = await this.t.changes(a.cursor ?? 0)
        if (badPage(p, true)) throw BAD_PAGE
        if (p.objects.length) {
          this.hooks.capture()
          this.store.receive(p.objects, p.serverTime)
          this.hooks.apply()
        }
        const need = new Map<string, Set<string>>()
        for (const inv of p.invalidations) {
          if (!(this.collections as readonly string[]).includes(inv.collection)) continue
          const known = a.objects[keyOf(inv.collection, inv.id)]
          if (known && known.revision >= inv.revision) continue
          let set = need.get(inv.collection); if (!set) need.set(inv.collection, set = new Set())
          set.add(inv.id)
        }
        for (const [c, ids] of need) {
          if (ids.size > PER_OBJECT_LIMIT) await this.fetchScope({ collection: c })
          else for (const id of ids) await this.fetchScope({ collection: c, prefix: id })
        }
        a.cursor = p.cursor
        this.store.onChange()
        if (!p.hasMore) return
      }
    } catch (e) {
      if ((e as Err).status === 410) { a.cursor = null; return this.full() }
      throw e
    }
  }
}
