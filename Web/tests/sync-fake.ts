/* 测试用的假服务端：合并规则照 Backend/kanpan-api/src/sync.rs 的 `merge`（字段级 LWW、
 * baseRevision / generation 冲突 → 409 resync_required、restore 要求精确的 base），
 * 整批一个事务：任何一条出错整批回滚。 */
import type { Transport } from '../src/sync/engine'
import type { Ctx } from '../src/sync/codec'
import type { Kind } from '../src/market/symbols'
import { type ChangesPage, type Page, type PushResponse, type SyncObject, type SyncOperation, keyOf } from '../src/sync/types'

export class HttpError extends Error {
  constructor(public status: number, public code: string) { super(code) }
}

interface Stamp { revision: number; timestamp: number; logical: number; deviceId: string; operationId: string }

export class FakeServer {
  objects = new Map<string, SyncObject>()
  changes: { seq: number; collection: string; id: string; revision: number; deleted: boolean }[] = []
  seq = 0
  now = 1_800_000_000_000
  /** 已处理过的 op id → 结果（幂等） */
  done = new Map<string, { opKey: string; result: PushResponse['results'][number] }>()
  /** 测试钩子：返回一个错误就整批拒掉 */
  reject: ((ops: SyncOperation[], body: string) => HttpError | null) | null = null
  pushes: SyncOperation[][] = []
  bootstraps: { collection: string; prefix?: string }[] = []

  merge(old: SyncObject, op: SyncOperation): SyncObject {
    const o: SyncObject = structuredClone(old)
    if (op.baseRevision > o.revision || op.generation !== o.generation) throw new HttpError(409, 'resync_required')
    if (op.action === 'restore') {
      if (!o.deleted || op.baseRevision !== o.revision) throw new HttpError(409, 'resync_required')
      o.deleted = false; o.generation += 1
    } else if (op.action === 'delete') o.deleted = true
    else if (o.deleted) return o
    const next = o.revision + 1
    if (!o.deleted) {
      for (const [k, v] of Object.entries(op.fields)) {
        const prev = o.fields[k] as unknown as Stamp | undefined
        const st: Stamp = { revision: next, timestamp: op.timestamp, logical: op.logical, deviceId: op.deviceId, operationId: op.id }
        const accept = !prev || op.baseRevision >= prev.revision || st.timestamp > prev.timestamp || (st.timestamp === prev.timestamp && st.logical > prev.logical)
        if (accept) { o.body[k] = v; o.fields[k] = st as unknown as SyncObject['fields'][string] }
      }
    }
    o.revision = next
    return o
  }

  push(body: string): PushResponse {
    const { operations } = JSON.parse(body) as { operations: SyncOperation[] }
    this.pushes.push(operations)
    for (const op of operations) if ('dependsOn' in op) throw new HttpError(400, 'invalid_batch')
    const e = this.reject?.(operations, body)
    if (e) throw e
    const staged = new Map<string, SyncObject>()
    const results: PushResponse['results'] = []
    for (const op of operations) {
      const k = keyOf(op.collection, op.objectId)
      const d = this.done.get(op.id)
      if (d) { if (d.opKey !== k) throw new HttpError(409, 'idempotency_mismatch'); results.push(d.result); continue }
      const cur = staged.get(k) ?? this.objects.get(k) ?? { collection: op.collection, id: op.objectId, body: {}, fields: {}, revision: 0, deleted: false, generation: 0 }
      const next = this.merge(cur, op)
      staged.set(k, next)
      results.push({ operationId: op.id, object: next, cursor: 0 })
    }
    for (const [k, o] of staged) {
      this.objects.set(k, o)
      this.changes.push({ seq: ++this.seq, collection: o.collection, id: o.id, revision: o.revision, deleted: o.deleted })
    }
    for (const r of results) { r.cursor = this.seq; this.done.set(r.operationId, { opKey: keyOf(r.object.collection, r.object.id), result: r }) }
    return { results: structuredClone(results), serverTime: this.now }
  }

  /** 别的设备（手机）直接写一个对象 */
  put(o: Omit<SyncObject, 'fields' | 'revision' | 'generation'> & Partial<SyncObject>): SyncObject {
    const k = keyOf(o.collection, o.id)
    const old = this.objects.get(k)
    const fields: SyncObject['fields'] = {}
    for (const f of Object.keys(o.body)) fields[f] = { revision: (old?.revision ?? 0) + 1, timestamp: this.now, logical: 1, deviceId: 'phone', operationId: 'x' }
    const next: SyncObject = { ...o, fields, revision: (old?.revision ?? 0) + 1, generation: old?.generation ?? 0 }
    this.objects.set(k, next)
    this.changes.push({ seq: ++this.seq, collection: next.collection, id: next.id, revision: next.revision, deleted: next.deleted })
    return next
  }

  bootstrap(collection: string, prefix?: string, after?: string | null): Page {
    this.bootstraps.push({ collection, prefix })
    const all = [...this.objects.values()].filter(o => o.collection === collection && (!prefix || o.id.startsWith(prefix))).sort((a, b) => a.id < b.id ? -1 : 1)
    const from = after ? all.findIndex(o => o.id > after) : 0
    const page = from < 0 ? [] : all.slice(from, from + 100)
    const next = from >= 0 && from + 100 < all.length ? page[page.length - 1].id : null
    return { objects: structuredClone(page), next, cursor: this.seq, serverTime: this.now }
  }

  changesSince(cursor: number): ChangesPage {
    const list = this.changes.filter(c => c.seq > cursor).slice(0, 200)
    return {
      objects: [],
      invalidations: list.map(c => ({ collection: c.collection, id: c.id, deleted: c.deleted, revision: c.revision })),
      cursor: list.length ? list[list.length - 1].seq : cursor,
      hasMore: this.changes.filter(c => c.seq > cursor).length > 200,
      serverTime: this.now,
    }
  }

  transport(): Transport {
    return {
      push: async (body) => this.push(body),
      bootstrap: async (c, p, a) => this.bootstrap(c, p, a),
      changes: async cur => this.changesSince(cur),
    }
  }
}

const KINDS: Record<string, Kind> = { BTCUSDT: 'crypto', ETHUSDT: 'crypto', SOLUSDT: 'crypto', NVDAUSDT: 'us', XAUUSDT: 'com', XAGUSDT: 'com' }
export const ctx: Ctx & { ready: boolean } = {
  now: () => 1_800_000_000_000,
  kindOf: s => KINDS[s],
  price: s => (s === 'BTCUSDT' ? 100000 : s === 'ETHUSDT' ? 4000 : null),
  label: (_s, p) => p.toFixed(1),
  ready: true,
}
