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
  type Archive, type Body, type Json, type PushResponse, type RejectedOperation, type SyncObject, type SyncOperation, type SyncResult,
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

/** 云端那一项的字段戳是不是比这条操作**更新**（服务端 `merge()` 比的那一对：时间戳，再逻辑钟）。读不出戳就当不比它新 */
export function newerThan(stamp: Json | undefined, op: SyncOperation): boolean {
  if (!stamp || typeof stamp !== 'object' || Array.isArray(stamp)) return false
  const t = stamp.timestamp, l = stamp.logical
  if (typeof t !== 'number') return false
  const logical = typeof l === 'number' ? l : 0
  return t > op.timestamp || (t === op.timestamp && logical > op.logical)
}

/** 这条拒绝记录被这份云端对象了结了没有：被拒那几项要么本机和云端一样了，要么云端那一项比被拒那一刻新。
 *  删除 / 恢复看整份 */
export function settles(record: RejectedOperation, local: SyncObject | undefined, cloud: SyncObject): boolean {
  if (!local || local.deleted !== cloud.deleted) return false
  if (record.operation.action !== 'patch') return same(local.body, cloud.body)
  return Object.keys(record.operation.fields).every(k => same(local.body[k], cloud.body[k]) || newerThan(cloud.fields[k], record.operation))
}

/** 回执里的对象，叠回这条操作里**服务端不认识、没收下**的那几项（droppedFields − invalidFields）。
 *  不叠的话下一次记账又差出同一项、再推、再被丢——一个服务端还不认识的字段就能让这一页一直打转。
 *  值不对的那几项不叠：本机认云端那份（审查 2026-10-10 第 3 项） */
export function keepingUnknown(r: SyncResult, op: SyncOperation | undefined): SyncObject {
  if (!op || r.object.deleted || !r.droppedFields?.length) return r.object
  const invalid = new Set(r.invalidFields ?? [])
  let out: SyncObject | null = null
  for (const k of r.droppedFields) {
    if (invalid.has(k) || !(k in op.fields)) continue
    out ??= { ...r.object, body: { ...r.object.body } }
    const v = op.fields[k]
    if (v === null) delete out.body[k]; else out.body[k] = v
  }
  return out ?? r.object
}

export class SyncStore {
  a: Archive
  device: string
  now: () => number
  /** 每次账本变了就调一次（外面拿它落盘） */
  onChange: () => void = () => {}

  constructor(archive: Archive, device: string, now: () => number = Date.now) {
    this.a = archive; this.device = device; this.now = now
    this.adoptDevice()
  }

  /** 还没发出去的操作一律改记到这台设备名下，返回改了几条（审查 2026-10-10 第 1 项）。
   *  服务端只收会话那台设备的操作；设备号不是用户意图的一部分，未发出的改一下没有风险。
   *  **已发出去（sent）的不动**：那一条可能已经落库，同一个 id 换了载荷再发会撞上 idempotency_mismatch */
  adoptDevice(): number {
    let n = 0
    for (const op of this.a.operations) if (op.deviceId !== this.device && !this.a.sent.has(op.id)) { op.deviceId = this.device; n++ }
    if (n) this.changed()
    return n
  }

  /** 服务端明说「这一条没落库、设备不对」（invalid_device）之后：改记到这台设备、退回未发送，返回改了几条。
   *  没落库是服务端先查回执再查设备保证的，同一个 id 换了设备号再发不会撞上幂等摘要 */
  reassign(ids: string[]): number {
    const wanted = new Set(ids)
    let n = 0
    for (const op of this.a.operations) {
      if (!wanted.has(op.id) || op.deviceId === this.device) continue
      op.deviceId = this.device; this.a.sent.delete(op.id); n++
    }
    if (n) this.changed()
    return n
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

  /** 只在全量同步之后跑：被拒的对象，被拒的那几项和云端还不一样、云端那一项也没有更新过，就用一条新 id 的操作
   *  补推那几项（云端可能已经修好了导致被拒的那一侧）。
   *
   *  **只补被拒的那几项**（审查 2026-10-10 第 2 项）。从前拿整份本地值对整份云端值现做差分：拒绝记录挡着整个
   *  对象，这段时间别的设备改的字段进得了 objects、进不了 local，整份一差，别人后来改的字段全被当成「本机要改回去」，
   *  还带着被拒那一刻的旧时间戳推上去。现在逐项看：本机和云端一样的不补；云端那一项比被拒那一刻新的按云端了结
   *  （记账跟上云端）；剩下的才补，baseRevision 保持被拒那条当初看到的那一版，时间戳 / 逻辑钟也沿用。
   *  删除 / 恢复是整对象的动作，仍走整份差分。返回每个对象上按云端了结的那几项 */
  retryRejected(owned: Owned = {}): Record<string, string[]> {
    const a = this.a
    const settled: Record<string, string[]> = {}
    if (!a.rejected.length) return settled
    let resolved = false, touched = false
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
      const rejected = record.operation
      if (rejected.action === 'patch' && !local.deleted && !remote.deleted) {
        const own = owned[rejected.collection]
        const next: SyncObject = { ...local, body: { ...local.body } }
        const fields: Body = {}
        const cloudWins: string[] = []
        for (const path of Object.keys(rejected.fields)) {
          if (same(next.body[path], remote.body[path])) { cloudWins.push(path); continue }
          if (newerThan(remote.fields[path], rejected)) {
            cloudWins.push(path)
            if (path in remote.body) next.body[path] = remote.body[path]; else delete next.body[path]
            continue
          }
          if (!(path in next.body) && own && !own.has(path)) {
            // 外来字段：本机不替它说话，不补 null，记账带回云端那一项
            if (path in remote.body) next.body[path] = remote.body[path]
            continue
          }
          fields[path] = path in next.body ? next.body[path] : null
        }
        if (cloudWins.length) settled[k] = cloudWins
        if (!Object.keys(fields).length) {
          // 被拒的那几项都了结了：记录作废，记账跟上云端那份（别的字段这段时间被挡在 local 外面，现在放进来）
          resolved = true
          if (differs(a.local[k], remote)) a.unapplied.add(remote.collection)
          a.local[k] = remote
          continue
        }
        if (!same(next.body, local.body)) { a.unapplied.add(next.collection); a.local[k] = next; touched = true }
        let dependsOn: string | null = null
        for (let i = a.operations.length - 1; i >= 0; i--) if (opKey(a.operations[i]) === k) { dependsOn = a.operations[i].id; break }
        a.operations.push({
          id: uuid(), collection: rejected.collection, objectId: rejected.objectId, deviceId: this.device,
          baseRevision: Math.min(rejected.baseRevision, remote.revision), generation: remote.generation,
          timestamp: rejected.timestamp, logical: rejected.logical, action: 'patch', fields, importBatch: null, dependsOn,
        })
        queued.add(k); keep.push(record)
        continue
      }
      a.local[k] = remote
      const op = this.stage(local, owned, { timestamp: rejected.timestamp, logical: rejected.logical })
      if (op) { queued.add(k); keep.push(record) } else resolved = true
    }
    if (!resolved && !touched && keep.length === a.rejected.length && a.operations.length === before) return settled
    a.rejected = keep
    this.changed()
    return settled
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
      // 被拒的那几项云端已经和本机一样（或者云端那一项更新）：那条拒绝记录可以了结。只看被拒的那几项，
      // 不看整份：这段时间别的设备改过别的字段，整份永远对不上（审查 2026-10-10 第 2 项）
      if (rejectedKeys.has(k)) {
        const record = [...a.rejected].reverse().find(x => opKey(x.operation) === k)
        if (record && settles(record, a.local[k], r.object)) { rejectedKeys.delete(k); rejectedCleared = true }
      }
      const queued = a.operations.some(o => !removed.has(o.id) && opKey(o) === k)
      if (!queued && !rejectedKeys.has(k)) {
        const next = keepingUnknown(r, acked)
        if (differs(a.local[k], next)) a.unapplied.add(r.object.collection)
        a.local[k] = next
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
