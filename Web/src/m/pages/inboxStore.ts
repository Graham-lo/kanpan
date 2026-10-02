/* 手机网页版 · 朋友与收件箱的运行时（照 iOS Share/ShareInbox.swift）
 *
 * 纯逻辑在 m/model/inbox.ts；这里管：按账号一份本机缓存（localStorage）、拉取（先发回执 → 收件箱一页 → 朋友名单）、
 * 已读 / 留下、加删朋友、缩略图（GET /v1/shares/{id}/shot，带令牌，内存里留最近 64 张）。
 * 什么时候拉：启动、登录、回前台、每一轮同步跑完、打开朋友页；未读数给「我的」根页那一行（底栏角标只数复盘待判定，照 iOS）。
 * 换号 / 退登：epoch 加一，在途的那一趟回来一律作废，不会把 A 的信写进 B 的缓存。
 */
import { hooks } from '../app/shell'
import { session, onSession } from '../../account/session'
import { ApiError, authed, fresh } from '../../account/client'
import { onSyncStatus, syncStatus } from '../app/sync'
import { drawingBook } from '../app/drawings'
import { newDrawingID, tryDecodeDrawing } from '../chart/draw/drawing'
import { shareErrorText } from './chart/share'
import {
  emptyCache, itemKey, markLocal, mergePage, plannedCopies, readCache, readItem, receiptIsDead, unseen, withFriend,
  type InboxCache, type ShareItem,
} from '../model/inbox'

const KEY = (owner: string): string => 'hkline-m-inbox-v1.' + owner.toLowerCase()

let owner = ''
let cache: InboxCache = emptyCache()
let epoch = 0
let busy = false
let again = false
/** 拉不下来时那句（「暂时连不上」…）；朋友页底下「· 重试」 */
let notice: string | null = null
const listeners = new Set<() => void>()

function emit(): void {
  listeners.forEach(f => { try { f() } catch (e) { console.error(e) } })
}

function load(): void {
  const o = session.userId ?? ''
  if (o === owner) return
  owner = o
  epoch++
  busy = false; again = false; notice = null
  dropThumbs()
  if (!o) { cache = emptyCache(); return }
  try { cache = readCache(JSON.parse(localStorage.getItem(KEY(o)) || 'null')) } catch { cache = emptyCache() }
}

/** 落盘；写不进（隐私模式、配额满）返回 false */
function persist(): boolean {
  if (!owner) return false
  try { localStorage.setItem(KEY(owner), JSON.stringify(cache)); return true } catch { return false }
}

// ───────── 对外：读 ─────────

export const inboxItems = (): readonly ShareItem[] => cache.items
export const inboxFriends = (): readonly string[] => cache.friends
export const inboxUnseen = (): number => unseen(cache.items).length
export const inboxNotice = (): string | null => notice
export const inboxBusy = (): boolean => busy
export function onInboxChange(fn: () => void): () => void { listeners.add(fn); return () => listeners.delete(fn) }

// ───────── 拉取 ─────────

async function flush(gen: number): Promise<void> {
  for (const [id, keep] of Object.entries(cache.pending)) {
    try {
      await authed('POST', `/v1/shares/${encodeURIComponent(id)}/${keep ? 'kept' : 'opened'}`)
    } catch (e) {
      if (!(e instanceof ApiError && receiptIsDead(e.status))) throw e
    }
    if (gen !== epoch) throw new Error('cancelled')
    // 发「已读」期间又点了「留下」：新回执不被旧的完成盖掉
    if (cache.pending[id] === keep) { const p = { ...cache.pending }; delete p[id]; cache = { ...cache, pending: p }; persist() }
  }
}

export function pullInbox(): void {
  load()
  if (!owner) return
  if (busy) { again = true; return }
  const gen = epoch
  busy = true
  void (async () => {
    try {
      await flush(gen)
      const q = cache.cursor ? '?after=' + encodeURIComponent(cache.cursor) : ''
      const page = await authed<{ items?: unknown[]; cursor?: string }>('GET', '/v1/shares/inbox' + q)
      if (gen !== epoch) return
      const items = (page?.items ?? []).map(readItem).filter((x): x is ShareItem => !!x)
      cache = { ...cache, items: mergePage(cache, items, Date.now()), cursor: typeof page?.cursor === 'string' ? page.cursor : cache.cursor }
      persist()
      emit()
      const friends = await authed<{ username?: unknown }[]>('GET', '/v1/friends')
      if (gen !== epoch) return
      cache = { ...cache, friends: (friends ?? []).map(f => f?.username).filter((n): n is string => typeof n === 'string').sort() }
      persist()
      notice = null
      emit()
    } catch (e) {
      if (gen !== epoch) return
      notice = shareErrorText(e)
      emit()
    } finally {
      if (gen === epoch) {
        busy = false
        if (again) { again = false; pullInbox() }
      }
    }
  })()
}

// ───────── 已读 / 留下 ─────────

function mark(id: string, keep: boolean): void {
  load()
  const next = markLocal(cache, id, keep, new Date().toISOString())
  if (next === cache) return
  cache = next
  persist()
  emit()
  pullInbox()
}

/** 点开看过 */
export const markOpened = (item: ShareItem): void => mark(item.id, false)

/**
 * 「保存到图上」：先给每条线分好新 id 并落盘（重试、刷新都不会复制两遍），再把线追加进那只品种的画线；
 * 返回给人看的结果。已经留下过的信：线已在图上，直接算成功。
 */
export function keepItem(item: ShareItem): { ok: true } | { ok: false; reason: string } {
  load()
  const cur = cache.items.find(i => i.id === item.id) ?? item
  if (cur.keptAt) return { ok: true }
  const planned = plannedCopies(cache, cur, newDrawingID)
  cache = planned.cache
  if (!persist()) return { ok: false, reason: '暂时无法保存，请重试' }
  const lines = cur.drawings.map((raw, i) => {
    const d = tryDecodeDrawing(raw)
    return d ? { ...d, id: planned.ids[i] } : null
  }).filter((d): d is NonNullable<typeof d> => !!d)
  if (!lines.length) return { ok: false, reason: '这封信里的线打不开' }
  const key = itemKey(cur)
  if (!drawingBook.add(lines, key)) {
    return { ok: false, reason: drawingBook.hasRoom(key, lines.length) ? '这封信里的线打不开' : '这只品种上的线满了，删掉几条再保存' }
  }
  mark(cur.id, true)
  return { ok: true }
}

// ───────── 朋友 ─────────

/** 加朋友；失败抛给输入框那一行去说（文案见 friendErrorText） */
export async function addFriend(name: string): Promise<void> {
  load()
  const gen = epoch
  await authed('POST', '/v1/friends', { username: name })
  if (gen !== epoch) throw new Error('cancelled')
  cache = { ...cache, friends: withFriend(cache.friends, name) }
  persist()
  emit()
}

/** 加朋友失败那一句（照 iOS FriendsPage.add：加自己单独一句） */
export function friendErrorText(e: unknown): string {
  if (e instanceof ApiError && e.code === 'cannot_send_self') return '不能加自己'
  return shareErrorText(e)
}

export async function removeFriend(name: string): Promise<void> {
  load()
  const gen = epoch
  try {
    await authed('DELETE', '/v1/friends/' + encodeURIComponent(name))
    if (gen !== epoch) return
    cache = { ...cache, friends: cache.friends.filter(f => f !== name) }
    persist()
  } catch (e) {
    if (gen !== epoch) return
    notice = shareErrorText(e)
  }
  emit()
}

// ───────── 缩略图 ─────────

const THUMB_MAX = 64
const thumbs = new Map<string, string>() // 信 id → object URL（按最近用过排）
const thumbLoads = new Map<string, Promise<string | null>>()

function dropThumbs(): void {
  for (const url of thumbs.values()) URL.revokeObjectURL(url)
  thumbs.clear()
  thumbLoads.clear()
}

/** 这封信的缩略图（object URL）；没传图、拉不到返回 null */
export function thumbOf(id: string): Promise<string | null> {
  const have = thumbs.get(id)
  if (have) { thumbs.delete(id); thumbs.set(id, have); return Promise.resolve(have) }
  let p = thumbLoads.get(id)
  if (p) return p
  const gen = epoch
  p = (async () => {
    try {
      const v = await fresh()
      const r = await fetch(`/v1/shares/${encodeURIComponent(id)}/shot`, { cache: 'no-store', headers: { Authorization: 'Bearer ' + v.accessToken } })
      if (!r.ok) return null
      const blob = await r.blob()
      if (gen !== epoch || !blob.size) return null
      const url = URL.createObjectURL(blob)
      thumbs.set(id, url)
      while (thumbs.size > THUMB_MAX) {
        const [oldId, oldUrl] = thumbs.entries().next().value as [string, string]
        thumbs.delete(oldId); URL.revokeObjectURL(oldUrl)
      }
      return url
    } catch { return null } finally { thumbLoads.delete(id) }
  })()
  thumbLoads.set(id, p)
  return p
}

// ───────── 启动 ─────────

let started = false
/** 启动（幂等） */
export function startInbox(): void {
  if (started) return
  started = true
  load()
  emit()
  onSession(() => { load(); emit(); pullInbox() })
  hooks.onForeground.push(() => pullInbox())
  let lastSync = syncStatus().lastSync
  onSyncStatus(() => {
    const s = syncStatus()
    if (s.lastSync && s.lastSync !== lastSync) { lastSync = s.lastSync; pullInbox() }
  })
  pullInbox()
}
