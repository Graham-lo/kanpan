/* Hkline Web · 同步账本（手机端 KanpanAccount/SyncStore.swift 的移植）
 *
 * 三份东西：
 * - `objects`：云端最后一次告诉我的样子（每个对象的 revision / generation / 墓碑）
 * - `local`：本机最后一次记账时的样子（stage 拿它做差分）
 * - `operations`：还没被服务端认掉的操作，按记账顺序；`sent` 是已经发出去、结果未知的那几条
 *
 * 和手机端的差别只有一处：网页每次都是「立即应用」，没有手机那层 shelved（云端值先搁着、
 * 等界面空了再装），所以 stage 里关于 shelf 的分支都省掉了。其余逐行照搬，包括
 * 「先前有、这次没有的键只有自己拥有的才发 null」「同一对象 delete/restore 之后本批截断」
 * 「409 之后按服务端规则把没发出的操作重新推演一遍」这几条。
 */
import {
  type Archive, type Body, type Json, type PushResponse, type RejectedOperation, type SyncObject, type SyncOperation,
  blank, emptyArchive, keyOf, objKey, opKey, same, uuid,
} from './types'

export type Owned = Record<string, Set<string>>

/** 发给服务端的那一份（去掉只在本机用的 dependsOn） */
export function wire(op: SyncOperation): Omit<SyncOperation, 'dependsOn'> {
  const { dependsOn: _d, ...rest } = op
  return rest
}
export function pushBody(ops: SyncOperation[]): string {
  return JSON.stringify({ operations: ops.map(wire) })
}
const enc = new TextEncoder()
export function encodedSize(ops: SyncOperation[]): number { return enc.encode(pushBody(ops)).length }

export function differs(local: SyncObject | undefined, remote: SyncObject): boolean {
  if (!local) return true
  return local.deleted !== remote.deleted || !same(local.body, remote.body)
}

export class SyncStore {
  a: Archive
  device: string
  now: () => number
  /** 每次账本变了就调一次（外面拿它落盘） */
  onChange: () => void = () => {}

  constructor(archive: Archive, device: string, now: () => number = Date.now) {
    this.a = archive; this.device = device; this.now = now
  }

  private changed(): void { this.onChange() }

  /** 这个对象眼下还被本机「攥着」：队列里有它的操作，或者它有一条被拒的记录没了结 */
  heldKeys(): Set<string> {
    const s = new Set<string>()
    for (const op of this.a.operations) s.add(opKey(op))
    for (const r of this.a.rejected) s.add(opKey(r.operation))
    return s
  }

  // ───────── 记账 ─────────

  /** 批量记账。`owned`：collection → 本客户端替它说话的那些键（见 stage）。返回产生了几条操作 */
  capture(values: SyncObject[], owned: Owned = {}): number {
    let n = 0
    for (const v of values) if (this.stage(v, owned)) n++
    if (n) this.changed()
    return n
  }

  /** 把一个对象记进账本，返回有没有真的产生一条操作。
   *
   * 「先前有、这次没有」的键：先前那份不一定是本机写的（receive 会把云端那份写进 local），
   * 云端对象上可能带着网页根本不产出的字段（手机端的 text、indicatorLayouts…）。
   * 只有本客户端拥有的键才翻译成字段删除（null），不拥有的把先前的值原样带回——
   * 否则服务端对不收 null 的字段整条拒掉，或者把手机端的字段删掉。 */
  stage(input: SyncObject, owned: Owned = {}, stamp?: { timestamp: number; logical: number }): SyncOperation | null {
    const a = this.a
    const key = objKey(input)
    const value: SyncObject = { ...input, body: { ...input.body } }
    const ledger = a.local[key]
    const base = a.objects[key] ?? blank(value.collection, value.id)
    if (value.deleted && ledger?.deleted === true) return null
    const previous = ledger
    const changed: Body = {}
    for (const [k, v] of Object.entries(value.body)) {
      if (!previous || !(k in previous.body) || !same(previous.body[k], v)) changed[k] = v
    }
    const own = owned[value.collection]
    if (previous) {
      for (const k of Object.keys(previous.body)) {
        if (k in value.body) continue
        if (own && !own.has(k)) value.body[k] = previous.body[k]
        else changed[k] = null
      }
    }
    if (previous && same(previous.body, value.body) && previous.deleted === value.deleted) return null
    const action: SyncOperation['action'] = value.deleted ? 'delete' : (ledger?.deleted === true || base.deleted) ? 'restore' : 'patch'
    let dependsOn: string | null = null
    for (let i = a.operations.length - 1; i >= 0; i--) {
      const o = a.operations[i]
      if (o.collection === value.collection && o.objectId === value.id) { dependsOn = o.id; break }
    }
    const op: SyncOperation = {
      id: uuid(), collection: value.collection, objectId: value.id, deviceId: this.device,
      baseRevision: base.revision, generation: base.generation,
      timestamp: stamp?.timestamp ?? this.now() + a.offset,
      logical: stamp?.logical ?? a.logical + 1,
      action, fields: changed, importBatch: null, dependsOn,
    }
    if (!stamp) a.logical += 1
    a.operations.push(op)
    a.local[key] = { ...value, fields: ledger?.fields ?? base.fields, revision: base.revision, generation: base.generation }
    return op
  }

  // ───────── 取批 ─────────

  /** 一批里同一个对象出现了 delete / restore，这个对象后面的操作就得等下一批（服务端按批内顺序
   *  套用，但 restore 要求 base 精确等于删除后的 revision，同批里算不出来）；
   *  restore 之前本批已经有这个对象的操作，也截断。截断而不是跳过：队列是有序的 */
  static batch(queue: SyncOperation[], limit: number): SyncOperation[] {
    const picked: SyncOperation[] = []
    const sealed = new Set<string>(), touched = new Set<string>()
    for (const op of queue) {
      if (picked.length >= limit) break
      const k = opKey(op)
      if (sealed.has(k)) break
      if (op.action === 'restore' && touched.has(k)) break
      picked.push(op)
      touched.add(k)
      if (op.action === 'delete' || op.action === 'restore') sealed.add(k)
    }
    return picked
  }

  nextBatch(limit: number, maxBytes: number): SyncOperation[] {
    let picked = SyncStore.batch(this.a.operations, limit)
    while (picked.length > 1 && encodedSize(picked) > maxBytes) picked = picked.slice(0, Math.max(1, Math.floor(picked.length / 2)))
    return picked
  }

  markSent(ids: string[]): void {
    if (!ids.length) return
    for (const id of ids) this.a.sent.add(id)
    this.changed()
  }

  rollback(ids: string[]): void {
    if (!ids.length) return
    for (const id of ids) this.a.sent.delete(id)
    this.changed()
  }

  /** 409 resync_required 之后：云端那份重拉过了，按服务端的合并规则把整条队列重新推演一遍，
   *  修正还没发出去的那几条的 base / generation / 动作 */
  realign(): void {
    const a = this.a
    const projected = new Map<string, { revision: number; generation: number; deleted: boolean }>()
    const replaced = new Map<string, string>()
    for (let i = 0; i < a.operations.length; i++) {
      const op = { ...a.operations[i] }
      if (op.dependsOn && replaced.has(op.dependsOn)) op.dependsOn = replaced.get(op.dependsOn)!
      const k = opKey(op)
      const remote = a.objects[k]
      const state = projected.get(k) ?? { revision: remote?.revision ?? 0, generation: remote?.generation ?? 0, deleted: remote?.deleted ?? false }
      if (!a.sent.has(op.id)) {
        let action = op.action
        if (action === 'restore' && !state.deleted) action = 'patch'
        else if (action === 'patch' && state.deleted && a.local[k]?.deleted === false) action = 'restore'
        if (action !== op.action) {
          const fresh = uuid(); replaced.set(op.id, fresh)
          op.id = fresh; op.action = action
        }
        op.generation = state.generation
        op.baseRevision = action === 'restore' ? state.revision : Math.min(op.baseRevision, state.revision)
      }
      if (op.action === 'restore') {
        if (state.deleted) { state.deleted = false; state.generation += 1; state.revision += 1 }
      } else if (op.action === 'delete') {
        state.deleted = true; state.revision += 1
      } else if (!state.deleted) {
        state.revision += 1
      }
      projected.set(k, state)
      a.operations[i] = op
    }
    this.changed()
  }

  /** 服务端明确说「这条永远不会被接受」：挪出队列，记成被拒（每个对象只留最新一条），
   *  依赖它的那条改接到它的前驱 */
  quarantine(id: string, reason: string): void {
    const a = this.a
    const index = a.operations.findIndex(o => o.id === id)
    if (index < 0) return
    const [op] = a.operations.splice(index, 1)
    a.sent.delete(id)
    for (const o of a.operations) if (o.dependsOn === id) o.dependsOn = op.dependsOn ?? null
    const k = opKey(op)
    const intent = a.local[k] ?? a.objects[k] ?? blank(op.collection, op.objectId)
    a.rejected = a.rejected.filter(r => opKey(r.operation) !== k)
    a.rejected.push({ operation: op, reason, at: this.now() + a.offset, intent: structuredClone(intent) })
    this.changed()
  }

  /** 只在全量同步之后跑：被拒的对象，本机值和云端还不一样，就拿被拒那条的时间戳对着
   *  最新的云端重新记一次账（云端可能已经修好了导致被拒的那一侧） */
  retryRejected(owned: Owned = {}): void {
    const a = this.a
    if (!a.rejected.length) return
    let resolved = false
    const keep: RejectedOperation[] = []
    const queued = new Set(a.operations.map(opKey))
    const before = a.operations.length
    for (const record of a.rejected) {
      const k = opKey(record.operation)
      const local = a.local[k]
      if (!local) { resolved = true; continue }
      const remote = a.objects[k] ?? blank(record.operation.collection, record.operation.objectId)
      if (!differs(local, remote)) { resolved = true; continue }
      if (queued.has(k)) { keep.push(record); continue }
      a.local[k] = remote
      const op = this.stage(local, owned, { timestamp: record.operation.timestamp, logical: record.operation.logical })
      if (op) { queued.add(k); keep.push(record) } else resolved = true
    }
    if (!resolved && keep.length === a.rejected.length && a.operations.length === before) return
    a.rejected = keep
    this.changed()
  }

  // ───────── 收 ─────────

  acknowledge(res: PushResponse): void {
    const a = this.a
    const pending = new Set(a.operations.map(o => o.id))
    const mine = res.results.filter(r => pending.has(r.operationId))
    if (!mine.length) return
    a.offset = res.serverTime - this.now()
    const sentBefore = new Set(a.sent)
    const removed = new Set<string>()
    const rejectedKeys = new Set(a.rejected.map(r => opKey(r.operation)))
    let rejectedCleared = false
    const latest = new Map<string, SyncObject>(), latestRestore = new Map<string, SyncObject>()
    for (const r of mine) {
      const k = objKey(r.object)
      const acked = a.operations.find(o => o.id === r.operationId && !removed.has(o.id))
      if (acked) removed.add(acked.id)
      a.objects[k] = r.object
      a.sent.delete(r.operationId)
      for (const o of a.operations) if (!removed.has(o.id) && o.dependsOn === r.operationId) o.dependsOn = acked?.dependsOn ?? null
      latest.set(k, r.object)
      if (acked?.action === 'restore') latestRestore.set(k, r.object)
      const local = a.local[k]
      if (local && !differs(local, r.object) && rejectedKeys.delete(k)) rejectedCleared = true
      const queued = a.operations.some(o => !removed.has(o.id) && opKey(o) === k)
      if (!queued && !rejectedKeys.has(k)) {
        if (differs(a.local[k], r.object)) a.unapplied.add(r.object.collection)
        a.local[k] = r.object
      }
    }
    for (const [k, obj] of latest) {
      for (const o of a.operations) {
        if (removed.has(o.id) || sentBefore.has(o.id) || opKey(o) !== k) continue
        if (o.action === 'restore') { o.baseRevision = obj.revision; o.generation = obj.generation }
        else if (latestRestore.has(k)) o.generation = latestRestore.get(k)!.generation
      }
    }
    if (removed.size) a.operations = a.operations.filter(o => !removed.has(o.id))
    if (rejectedCleared) a.rejected = a.rejected.filter(r => rejectedKeys.has(opKey(r.operation)))
    this.changed()
  }

  receive(objects: SyncObject[], serverTime: number): void {
    const a = this.a
    a.offset = serverTime - this.now()
    const held = this.heldKeys()
    for (const o of objects) {
      const k = objKey(o)
      a.objects[k] = o
      if (!held.has(k)) {
        if (differs(a.local[k], o)) a.unapplied.add(o.collection)
        a.local[k] = o
      }
    }
    this.changed()
  }

  /** 本机眼下认定的某个集合的全部对象（含墓碑） */
  localOf(collection: string): SyncObject[] {
    const out: SyncObject[] = []
    for (const [k, v] of Object.entries(this.a.local)) if (k.startsWith(collection + ':')) out.push(v)
    return out
  }
  get(collection: string, id: string): SyncObject | undefined { return this.a.local[keyOf(collection, id)] }
}

// ───────── 存档（localStorage） ─────────

interface Stored {
  v: 1
  operations: SyncOperation[]
  sent: string[]
  objects: SyncObject[]
  /** 和 objects 不同的那几份 local；`null` 表示「objects 有、local 没有」 */
  local: Record<string, SyncObject | null>
  logical: number
  offset: number
  rejected: RejectedOperation[]
  cursor: number | null
  lastFull: number
  seen: Record<string, Json>
  unapplied: string[]
}

export function serialize(a: Archive): string {
  const local: Record<string, SyncObject | null> = {}
  for (const [k, v] of Object.entries(a.local)) {
    const o = a.objects[k]
    if (!o || o.deleted !== v.deleted || o.revision !== v.revision || !same(o.body, v.body)) local[k] = v
  }
  for (const k of Object.keys(a.objects)) if (!(k in a.local)) local[k] = null
  const s: Stored = {
    v: 1, operations: a.operations, sent: [...a.sent], objects: Object.values(a.objects), local,
    logical: a.logical, offset: a.offset, rejected: a.rejected, cursor: a.cursor, lastFull: a.lastFull,
    seen: a.seen, unapplied: [...a.unapplied],
  }
  return JSON.stringify(s)
}

export function deserialize(text: string | null): Archive | null {
  if (!text) return null
  try {
    const s = JSON.parse(text) as Stored
    if (s.v !== 1) return null
    const a = emptyArchive()
    a.operations = s.operations ?? []
    a.sent = new Set(s.sent ?? [])
    for (const o of s.objects ?? []) a.objects[objKey(o)] = o
    for (const [k, o] of Object.entries(a.objects)) a.local[k] = o
    for (const [k, v] of Object.entries(s.local ?? {})) { if (v) a.local[k] = v; else delete a.local[k] }
    a.logical = s.logical ?? 0; a.offset = s.offset ?? 0
    a.rejected = s.rejected ?? []
    a.cursor = s.cursor ?? null; a.lastFull = s.lastFull ?? 0
    a.seen = s.seen ?? {}; a.unapplied = new Set(s.unapplied ?? [])
    return a
  } catch { return null }
}

/** 这台电脑上存着的账本能不能给 `id` 这个账号接着用：只有上次同步的就是它（owner）才行。
 *  别的账号留下的账本（连同里面没推出去的操作）一律不重放——那是另一个人的改动 */
export function resumeArchive(owner: string | null, id: string, text: string | null): Archive | null {
  return owner === id ? deserialize(text) : null
}
