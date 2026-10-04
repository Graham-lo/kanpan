/* Hkline Web · 记一笔：上传队列
 *
 * 记下的那一刻先落本机（st.notes，带着完整草稿），再尽快传到服务端成为一条观点记录——
 * 复盘页「观点记录」和手机上都从服务端读。没登录、断网、服务端一时出错时它就留在本机等，
 * 登录上、网络回来、再记一笔、打开页面时各补传一次（不开定时轮询）。
 *
 * 服务端明确拒收的（400 / 409 / 422：区间不合法、规则不合法）不再重试，标成 failed 把原因写上，
 * 笔记本身仍留在本机；其余失败（没网、超时、5xx、429、401）原样留着下次再传。
 *
 * 每一笔记着记下时登录的账号（owner），只传给那个账号；没登录时记的由第一个登录上的账号认领。
 * 传的途中换了账号就停下，换上来的账号接着再跑一趟（只传它自己的）。
 *
 * 截图单独一步：记录建好之后再传（服务端要求记录先在）。图本身放在本机一个单独的键里，
 * 传上去就删；存不下（本机配额满）就不带图，记录照传。
 */
import { st, save, type Note } from '../app/store'
import { readStored } from '../account/client'
import { onSession, session } from '../account/session'
import { reviewApi, reviewToken, ReviewError, errorText } from '../review/api'
import { NOTE_SHOTS_KEY } from '../util/storage'

const SHOT_KEY = NOTE_SHOTS_KEY
/** 本机最多压几张没传上去的图（每张一两百 KB，localStorage 一共约 5 MB） */
const MAX_SHOTS = 6

function shots(): Record<string, string> {
  try { const v = JSON.parse(localStorage.getItem(SHOT_KEY) || '{}'); return v && typeof v === 'object' ? v : {} } catch { return {} }
}
function writeShots(m: Record<string, string>): boolean {
  try { localStorage.setItem(SHOT_KEY, JSON.stringify(m)); return true } catch { return false }
}
/** 存一张待传的图；存不下返回 false */
export function keepShot(id: string, base64: string): boolean {
  const m = shots()
  const keys = Object.keys(m)
  while (keys.length >= MAX_SHOTS) delete m[keys.shift()!]
  m[id] = base64
  return writeShots(m)
}
export function dropShot(id: string): void { const m = shots(); if (id in m) { delete m[id]; writeShots(m) } }
export function shotOf(id: string): string | null { return shots()[id] ?? null }

const listeners = new Set<() => void>()
/** 有笔记状态变了（传上了 / 被拒了）：侧栏笔记、复盘页刷新 */
export function onNotesSynced(fn: () => void): () => void { listeners.add(fn); return () => { listeners.delete(fn) } }
function emit(): void { listeners.forEach(fn => { try { fn() } catch (e) { console.error(e) } }) }

export const canUpload = (): boolean => !!readStored() || !!reviewToken()
/** 现在登录的账号编号（调试令牌没有账号编号时为 null） */
export const currentUid = (): string | null => readStored()?.userId ?? session.userId ?? null
/** 这一笔归不归现在这个账号传 */
const mine = (n: Note, uid: string | null): boolean => n.owner == null || n.owner === uid

/** 服务端明确拒收（重发也不会变）的错误 */
function rejected(e: unknown): boolean {
  return e instanceof ReviewError && (e.status === 400 || e.status === 409 || e.status === 422)
}

let running: Promise<number> | null = null
/** 跑着的这一趟期间又被叫了（换了账号、又记了一笔）：跑完再来一趟 */
let again = false

/** 把本机等上传的笔记与截图传上去；返回新传上的条数 */
export function flushNotes(): Promise<number> {
  if (running) { again = true; return running }
  running = (async () => {
    let done = 0
    do { again = false; done += await run() } while (again)
    return done
  })().finally(() => { running = null })
  return running
}

async function run(): Promise<number> {
  if (!canUpload()) return 0
  const uid = currentUid()
  /** 途中换了账号：后面的请求会带上新账号的令牌，停下交给下一趟 */
  const switched = (): boolean => currentUid() !== uid
  let done = 0, changed = false
  for (const n of [...st.notes]) {
    if (!n.draft || n.sync !== 'pending' || !mine(n, uid)) continue
    if (switched()) break
    try {
      await reviewApi.createRecord(n.draft)
      n.sync = 'synced'; n.err = undefined; done++; changed = true
      if (n.owner == null && uid) n.owner = uid
      save()
    } catch (e) {
      if (rejected(e)) { n.sync = 'failed'; n.err = errorText(e); changed = true; save(); continue }
      break // 没网 / 超时 / 服务端出错 / 没登录：整批留到下次
    }
  }
  for (const n of [...st.notes]) {
    if (n.sync !== 'synced' || n.shot !== 'pending' || !mine(n, uid)) continue
    if (switched()) break
    const img = shotOf(n.id)
    if (!img) { n.shot = 'none'; save(); continue }
    try {
      await reviewApi.putShot(n.id, img)
      n.shot = 'done'; dropShot(n.id); save(); changed = true
    } catch (e) {
      if (rejected(e) || (e instanceof ReviewError && e.status === 404)) { n.shot = 'none'; dropShot(n.id); save(); continue }
      break
    }
  }
  if (changed) emit()
  return done
}

/** 这一笔现在的状态（侧栏笔记上的小字） */
export function noteState(n: Note): { text: string; cls: string } | null {
  if (!n.draft) return { text: '仅本机', cls: '' }
  if (n.sync === 'synced') return null
  if (n.sync === 'failed') return { text: '没传上', cls: 'down' }
  if (n.owner != null && n.owner !== currentUid()) return { text: '原账号登录后上传', cls: 'accent' }
  return { text: canUpload() ? '待上传' : '登录后上传', cls: 'accent' }
}

let installed = false
/** 装一次：登录上、网络回来时补传，页面打开时先补一次 */
export function installNoteSync(): void {
  if (installed) return
  installed = true
  onSession(() => { void flushNotes() })
  addEventListener('online', () => { void flushNotes() })
  void flushNotes()
}
