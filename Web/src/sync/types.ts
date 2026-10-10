/* Hkline Web · 同步协议的类型（和 Backend/kanpan-api/src/sync.rs、手机端 KanpanAccount/SyncStore.swift 同一套形状） */

export type Json = null | boolean | number | string | Json[] | { [k: string]: Json }
export type Body = Record<string, Json>

export type Collection = 'settings' | 'favorites' | 'groups' | 'drawings' | 'alerts' | 'drawingPreferences'
/** 网页版拉取的全部集合，按这个顺序。`drawingPreferences`（手机的画线工具偏好）PC 网页用不上，不拉；
 *  手机网页版的适配器另给一份带它的清单（SyncAdapter.collections） */
export const COLLECTIONS: Collection[] = ['settings', 'favorites', 'groups', 'alerts', 'drawings']

export interface SyncObject {
  collection: string
  id: string
  body: Body
  /** 每个字段的时间戳：{revision, timestamp, logical, deviceId, operationId} */
  fields: Record<string, Json>
  revision: number
  deleted: boolean
  generation: number
}

export interface SyncOperation {
  id: string
  collection: string
  objectId: string
  deviceId: string
  baseRevision: number
  generation: number
  timestamp: number
  logical: number
  action: 'patch' | 'delete' | 'restore'
  fields: Body
  importBatch: null
  /** 同一个对象上这条操作的本地前驱。**只存在本机，绝不发给服务端**（服务端 deny_unknown_fields） */
  dependsOn?: string | null
}

export interface RejectedOperation {
  operation: SyncOperation
  reason: string
  at: number
  /** 用户当时的值 */
  intent: SyncObject
}

/** 一条操作的回执。`droppedFields`：服务端认下了这条、但这几项没收下；其中**值不对**的那几项
 *  （设置这类宽松集合，2026-10-10 起只丢字段不拒整条）另在 `invalidFields` 里列一遍——那一类重发多少次
 *  都是被丢，本机认云端那份；剩下的是服务端还不认识的字段，记账叠回本机的值，等服务端升级 */
export interface SyncResult { operationId: string; object: SyncObject; cursor: number; droppedFields?: string[]; invalidFields?: string[] }
/** 服务端**只拒了这一条**（`?rejections=inline`）：同批其余照常提交，这一格写在线上 `results` 里，
 *  `status: 'rejected'`。`code` 是 `invalid_device`（设备号对不上，改记重发）或语义错误（隔离这一条） */
export interface SyncRejection { operationId: string; status: 'rejected'; code: string; message?: string }
/** 推送的回话。线上 `results` 一格要么是回执、要么是一条拒绝；`splitPush` 把后者挪进 `rejections` */
export interface PushResponse { results: SyncResult[]; serverTime: number; rejections?: SyncRejection[] }
/** 线上原样的那份 */
export interface RawPushResponse { results: (SyncResult | SyncRejection)[]; serverTime: number; rejections?: SyncRejection[] }
export function splitPush(raw: RawPushResponse | PushResponse): PushResponse {
  const results: SyncResult[] = [], rejections: SyncRejection[] = [...(raw.rejections ?? [])]
  for (const r of raw.results as (SyncResult | SyncRejection)[]) {
    if ((r as SyncRejection).status === 'rejected') rejections.push(r as SyncRejection); else results.push(r as SyncResult)
  }
  return { results, serverTime: raw.serverTime, rejections }
}
export interface Page { objects: SyncObject[]; next: string | null; cursor: number; serverTime: number }
export interface Invalidation { collection: string; id: string; deleted: boolean; revision: number }
export interface ChangesPage { objects: SyncObject[]; invalidations: Invalidation[]; cursor: number; hasMore: boolean; serverTime: number }

export interface Scope { collection: string; prefix?: string }

/** 云端的值变了、但还没装进页面状态的那几张表 */
export type Unapplied = Set<string>

export interface Archive {
  operations: SyncOperation[]
  sent: Set<string>
  objects: Record<string, SyncObject>
  local: Record<string, SyncObject>
  logical: number
  offset: number
  rejected: RejectedOperation[]
  /** `/v1/sync/changes` 的游标；null 表示还没做过全量 */
  cursor: number | null
  /** 上一次全量（含补推被拒）的时刻 */
  lastFull: number
  /** 设置里每个网页字段「上一次和云端对上时」的样子，见 codec 的 settings 部分 */
  seen: Record<string, Json>
  unapplied: Unapplied
}

export const keyOf = (collection: string, id: string): string => collection + ':' + id
export const opKey = (op: SyncOperation): string => keyOf(op.collection, op.objectId)
export const objKey = (o: SyncObject): string => keyOf(o.collection, o.id)

export function blank(collection: string, id: string): SyncObject {
  return { collection, id, body: {}, fields: {}, revision: 0, deleted: false, generation: 0 }
}

export function emptyArchive(): Archive {
  return { operations: [], sent: new Set(), objects: {}, local: {}, logical: 0, offset: 0, rejected: [], cursor: null, lastFull: 0, seen: {}, unapplied: new Set() }
}

/** 值相等（键序无关）。JSON 形状以外的东西不会出现在这里 */
export function same(a: unknown, b: unknown): boolean {
  if (a === b) return true
  if (a === null || b === null || typeof a !== 'object' || typeof b !== 'object') return false
  if (Array.isArray(a) !== Array.isArray(b)) return false
  if (Array.isArray(a)) {
    const bb = b as unknown[]
    if (a.length !== bb.length) return false
    for (let i = 0; i < a.length; i++) if (!same(a[i], bb[i])) return false
    return true
  }
  const ao = a as Record<string, unknown>, bo = b as Record<string, unknown>
  const ak = Object.keys(ao).filter(k => ao[k] !== undefined), bk = Object.keys(bo).filter(k => bo[k] !== undefined)
  if (ak.length !== bk.length) return false
  for (const k of ak) if (!(k in bo) || !same(ao[k], bo[k])) return false
  return true
}

export function uuid(): string {
  const c = (globalThis as { crypto?: Crypto }).crypto
  if (c?.randomUUID) return c.randomUUID()
  // 非安全上下文（http 局域网地址）没有 randomUUID：用 getRandomValues 拼一个 v4
  const b = new Uint8Array(16)
  if (c?.getRandomValues) c.getRandomValues(b); else for (let i = 0; i < 16; i++) b[i] = Math.floor(Math.random() * 256)
  b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80
  const h = [...b].map(x => x.toString(16).padStart(2, '0')).join('')
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`
}
