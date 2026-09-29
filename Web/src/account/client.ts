/* Hkline Web · 账号客户端（Backend/kanpan-api/src/auth.rs）
 *
 * - 只有用户名 + 密码；设备类别默认 desktop（服务端「每类一台」：另一台电脑登录会把这里顶下去）。
 *   手机网页版（/web/m/）在入口最早处调 `configureAccount({ keyPrefix: 'hkline-m', kind: 'phone' })`：
 *   键名换一套（同源的 /web/ 与 /web/m/ 共用 localStorage，不能互相覆盖），设备类别按手机算。
 * - 令牌存 localStorage，带签发主机（issuer）：换了主机的旧令牌一律丢掉。
 * - 设备 id / secret 第一次生成后固定，退登也不换（服务端拿它绑定 refresh）。
 * - refresh 单飞：同一浏览器的多个标签页用 Web Locks 排队，拿到锁之后先看别人是不是已经换过了；
 *   requestId 在拿到新令牌之前一直落盘，断网重试用同一个 id，服务端原样交回封存的那份结果，
 *   不会被当成「重用旧 refresh」把整条会话吊销掉。
 * - 被另一台电脑顶掉（401 session_replaced）：清掉本机会话、回到未登录，不再重试。
 */
import { uuid } from '../sync/types'
import { endSession, setSession, type Ended } from './session'

export const ISSUER = 'kanpan.107-174-172-10.sslip.io'
/** PC 版的键名（默认值；测试与回归脚本按这个名字读写）。当前实际用的键见 `accountKey()` */
export const ACCOUNT_KEY = 'hkline-web-account-v1'

export type DeviceKind = 'desktop' | 'phone' | 'tablet'
export interface AccountConfig { keyPrefix: string; kind: DeviceKind }
const config: AccountConfig = { keyPrefix: 'hkline-web', kind: 'desktop' }

/** 换一套键名与设备类别。必须在 `resume()` / 任何登录请求之前调用（键名在每次读写时现取，不怕 import 顺序） */
export function configureAccount(c: Partial<AccountConfig>): void {
  if (c.keyPrefix) config.keyPrefix = c.keyPrefix
  if (c.kind) config.kind = c.kind
}
export function accountConfig(): Readonly<AccountConfig> { return config }
/** 当前这一端存会话的 localStorage 键（PC：hkline-web-account-v1，手机：hkline-m-account-v1） */
export function accountKey(): string { return config.keyPrefix + '-account-v1' }
function deviceKey(): string { return config.keyPrefix + '-device-v1' }
const LIFETIME_CAP = 15 * 60e3
const EARLY = 30e3

export interface Stored {
  issuer: string
  username: string
  userId: string
  sessionId: string
  accessToken: string
  refreshToken: string
  /** 本机时钟下 access 该换的时刻（已经提前 30 秒） */
  accessDeadline: number
  /** 正在换的那一次：拿到新令牌之前一直留着，重试用同一个 requestId */
  pending?: { requestId: string; refreshToken: string }
}

export interface Device { id: string; name: string; secret: string; kind: DeviceKind }

export class ApiError extends Error {
  status: number; code: string; deviceKind?: string
  constructor(status: number, code: string, deviceKind?: string) { super(code); this.status = status; this.code = code; this.deviceKind = deviceKind }
}

// ───────── 本机存储 ─────────

function ls(): Storage | null { try { return globalThis.localStorage ?? null } catch { return null } }

export function readStored(): Stored | null {
  try {
    const v = JSON.parse(ls()?.getItem(accountKey()) || 'null') as Stored | null
    if (!v || v.issuer !== ISSUER || !v.refreshToken || !v.userId) return null
    return v
  } catch { return null }
}
function writeStored(v: Stored | null): void {
  try { if (v) ls()?.setItem(accountKey(), JSON.stringify(v)); else ls()?.removeItem(accountKey()) } catch { /* 存储满了 */ }
}

function browserName(): string {
  const ua = globalThis.navigator?.userAgent || ''
  const b = /Edg\//.test(ua) ? 'Edge' : /Firefox\//.test(ua) ? 'Firefox' : /Chrome\//.test(ua) ? 'Chrome' : /Safari\//.test(ua) ? 'Safari' : '浏览器'
  const os = /iPhone/.test(ua) ? 'iPhone' : /iPad/.test(ua) ? 'iPad' : /Android/.test(ua) ? 'Android' : /Mac OS X|Macintosh/.test(ua) ? 'macOS' : /Windows/.test(ua) ? 'Windows' : /Linux/.test(ua) ? 'Linux' : ''
  return ['网页', b, os].filter(Boolean).join(' · ')
}

export function device(): Device {
  try {
    const v = JSON.parse(ls()?.getItem(deviceKey()) || 'null') as Partial<Device> | null
    if (v?.id && v.secret && v.secret.length >= 32) return { id: v.id, secret: v.secret, name: browserName(), kind: config.kind }
  } catch { /* 坏了就重来 */ }
  const b = new Uint8Array(32)
  globalThis.crypto.getRandomValues(b)
  const d: Device = { id: uuid(), secret: [...b].map(x => x.toString(16).padStart(2, '0')).join(''), name: browserName(), kind: config.kind }
  try { ls()?.setItem(deviceKey(), JSON.stringify({ id: d.id, secret: d.secret })) } catch { /* 只能这一次用 */ }
  return d
}

// ───────── 请求 ─────────

interface Envelope<T> { data?: T; error?: { code?: string; deviceKind?: string } }

/** 同源请求，解包 `{data}`，错误统一成 ApiError（网络不通是 status 0 / network） */
export async function request<T>(method: string, path: string, body?: unknown, headers: Record<string, string> = {}): Promise<T> {
  let res: Response
  try {
    res = await fetch(path, {
      method,
      headers: { ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}), ...headers },
      body: body === undefined ? undefined : typeof body === 'string' ? body : JSON.stringify(body),
      cache: 'no-store',
    })
  } catch { throw new ApiError(0, 'network') }
  let j: Envelope<T> | null = null
  try { j = await res.json() as Envelope<T> } catch { /* 413 之类可能不是 JSON */ }
  if (!res.ok) throw new ApiError(res.status, j?.error?.code || (res.status === 413 ? 'payload_too_large' : 'http_' + res.status), j?.error?.deviceKind)
  return (j?.data ?? (null as T))
}

interface Tokens { user?: { id: string; email: string }; sessionId: string; accessToken: string; refreshToken: string; expiresAt: number; serverTime: number }

function fromTokens(t: Tokens, username: string, userId: string): Stored {
  const life = Math.min(LIFETIME_CAP, Math.max(60e3, t.expiresAt - t.serverTime))
  return { issuer: ISSUER, username, userId, sessionId: t.sessionId, accessToken: t.accessToken, refreshToken: t.refreshToken, accessDeadline: Date.now() + life - EARLY }
}

// ───────── 登录 / 注册 / 退登 ─────────

export async function login(username: string, password: string, create = false): Promise<void> {
  const t = await request<Tokens>('POST', create ? '/v1/auth/register' : '/v1/auth/login', { username: username.trim().toLowerCase(), password, device: device() })
  const v = fromTokens(t, t.user?.email ?? username.trim().toLowerCase(), t.user?.id ?? '')
  writeStored(v)
  setSession(v)
  scheduleRefresh()
}

/** 先清本地（页面立刻回到未登录），吊销在后台做；服务器不通也不卡住 */
export function logout(): void {
  const v = readStored()
  writeStored(null)
  endSession(null)
  if (v) void request('POST', '/v1/auth/session/revoke', { refreshToken: v.refreshToken, device: device() }).catch(() => {})
}

function end(e: ApiError): never {
  const why: Ended = e.code === 'session_replaced' ? { replaced: e.deviceKind || config.kind } : 'expired'
  writeStored(null)
  endSession(why)
  throw e
}

// ───────── refresh 单飞 ─────────

let inflight: Promise<Stored> | null = null

async function withLock<T>(fn: () => Promise<T>): Promise<T> {
  const locks = (globalThis.navigator as Navigator | undefined)?.locks
  // 锁名跟键前缀走：PC 与手机网页版同源，但各换各的令牌，不必互相排队
  const name = config.keyPrefix === 'hkline-web' ? 'hkline-refresh' : config.keyPrefix + '-refresh'
  if (locks?.request) return locks.request(name, fn) as Promise<T>
  return fn()
}

/** 换一对新令牌。`stale` 是调用方手上那把 refresh：拿到锁时存储里已经不是它了，说明别的标签页换过，直接用 */
export function refresh(stale?: string): Promise<Stored> {
  if (inflight) return inflight
  inflight = withLock(async () => {
    const cur = readStored()
    if (!cur) { endSession('expired'); throw new ApiError(401, 'authentication_failed') }
    if (stale && cur.refreshToken !== stale && cur.accessDeadline > Date.now()) { setSession(cur); return cur }
    const requestId = cur.pending?.refreshToken === cur.refreshToken ? cur.pending.requestId : uuid()
    writeStored({ ...cur, pending: { requestId, refreshToken: cur.refreshToken } })
    let t: Tokens
    try {
      t = await request<Tokens>('POST', '/v1/auth/refresh', { refreshToken: cur.refreshToken, requestId, device: device() })
    } catch (e) {
      const err = e as ApiError
      // 401：过期、被顶掉、被踢；400 invalid_device：设备凭据对不上。都只能重新登录
      if (err.status === 401 || (err.status === 400 && err.code === 'invalid_device')) end(err)
      throw err
    }
    const v = fromTokens(t, cur.username, cur.userId)
    writeStored(v)
    setSession(v)
    return v
  }).finally(() => { inflight = null; scheduleRefresh() })
  return inflight
}

/** 手上可用的 access；快到期就先换 */
export async function fresh(): Promise<Stored> {
  const v = readStored()
  if (!v) throw new ApiError(401, 'authentication_failed')
  if (v.accessDeadline > Date.now()) return v
  return refresh(v.refreshToken)
}

/** 带登录的请求：access 被拒（过期）就换一次再试；被顶掉 / 换不动就结束会话 */
export async function authed<T>(method: string, path: string, body?: unknown, headers: Record<string, string> = {}): Promise<T> {
  let v = await fresh()
  for (let attempt = 0; ; attempt++) {
    try {
      return await request<T>(method, path, body, { ...headers, Authorization: 'Bearer ' + v.accessToken })
    } catch (e) {
      const err = e as ApiError
      if (err.status !== 401) throw err
      if (err.code === 'session_replaced') end(err)
      if (err.code !== 'authentication_failed' || attempt > 0) throw err
      v = await refresh(v.refreshToken)
    }
  }
}

// 页面开着时提前换好 access，别的模块（复盘页）同步读 session.accessToken 也拿得到能用的
let timer: ReturnType<typeof setTimeout> | null = null
export function scheduleRefresh(): void {
  if (timer) clearTimeout(timer)
  timer = null
  const v = readStored()
  if (!v) return
  const wait = Math.max(5e3, v.accessDeadline - Date.now())
  timer = setTimeout(() => {
    timer = null
    const cur = readStored()
    if (!cur) return
    if (cur.accessDeadline > Date.now() + 5e3) { scheduleRefresh(); return }
    // 网络不通就过一会再试；会话没了 refresh 自己会收尾
    refresh(cur.refreshToken).catch(() => { if (readStored()) timer = setTimeout(scheduleRefresh, 30e3) })
  }, wait)
}

// ───────── 账号页用的几个接口 ─────────

export interface DeviceRow { id: string; name: string; kind: string; createdAt: number; lastSeen: number; current: boolean }

export async function devices(): Promise<DeviceRow[]> {
  const r = await authed<{ devices: DeviceRow[] }>('GET', '/v1/auth/devices')
  return r?.devices ?? []
}
export async function kick(sessionId: string): Promise<void> { await authed('DELETE', '/v1/auth/devices/' + encodeURIComponent(sessionId)) }

export async function changePassword(currentPassword: string, newPassword: string): Promise<void> {
  await authed('POST', '/v1/auth/password/change', { currentPassword, newPassword })
}

/**
 * 注销账号：服务端把这个人的云端数据（自选、画线、提醒、复盘……）连同全部会话一起删掉（DELETE /v1/auth/account，要当前密码）。
 * 本机这份和退出登录一样留着，只是不再同步。手机上有同一个入口（「账号 → 注销账号」），网页以前没有。
 */
export async function deleteAccount(password: string): Promise<void> {
  await authed('DELETE', '/v1/auth/account', { password })
  writeStored(null)
  endSession(null)
}

/** 启动时：存储里有会话就接上（不发请求；access 过期了等第一次用的时候再换） */
export function resume(): void {
  const v = readStored()
  if (v) { setSession(v); scheduleRefresh() }
  else { try { if (ls()?.getItem(accountKey())) writeStored(null) } catch { /* 忽略 */ } }
  // 别的标签页登录 / 退登 / 换了令牌
  globalThis.addEventListener?.('storage', e => {
    if (e.key !== accountKey()) return
    const n = readStored()
    if (n) setSession(n); else endSession(null)
    scheduleRefresh()
  })
}

/** 服务端错误码 → 界面上的一句话 */
export function errorText(e: unknown, ctx: 'login' | 'register' | 'password' | 'other' = 'other'): string {
  const err = e as ApiError
  if (!(err instanceof ApiError)) return '出了点问题，再试一次'
  if (err.status === 0) return '连不上服务器'
  switch (err.code) {
    case 'invalid_username': return '用户名 3–32 位，只能用小写字母、数字、下划线'
    case 'invalid_password': return '密码至少 8 位，要同时有字母和数字'
    case 'username_taken': return '这个用户名已经有人用了'
    case 'try_later': return '试得太频繁，稍后再试'
    case 'wrong_password': return '当前密码不对'
    case 'temporarily_unavailable': return '服务器忙，稍后再试'
  }
  if (err.status === 429) return '试得太频繁，稍后再试'
  if (err.status === 401 && ctx === 'login') return '用户名或密码不对'
  if (err.status === 401) return '登录已失效，请重新登录'
  if (err.status >= 500) return '服务器忙，稍后再试'
  return '出了点问题，再试一次'
}
