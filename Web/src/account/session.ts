/* Hkline Web · 账号会话（页面这一侧的状态）
 *
 * 登录与否只影响「跨设备同步」和需要服务端运算的功能（复盘、成交）；
 * 没登录时自选、画线、提醒照常存在这台电脑上。
 *
 * `session.accessToken`（不落盘）给别的页面同步读 access：复盘页按约定读它。
 * 令牌本身存在 client.ts 的 localStorage 键里。
 * 这个文件不 import 任何一端的 store：PC（/web/）与手机（/web/m/）共用它。
 */

export interface SessionUser { username: string; userId: string; sessionId: string; accessToken: string }
/** 会话是怎么没的：主动退登是 null；被另一台同类设备顶掉带上对方的类别 */
export type Ended = null | 'expired' | { replaced: string }

export const session = {
  /** 用户名；未登录为 null */
  user: null as string | null,
  userId: null as string | null,
  sessionId: null as string | null,
  /** 当前 access（可能已过期；要保证能用走 client.ts 的 fresh / authed） */
  accessToken: null as string | null,
  /** 上一次会话结束的原因，账号卡片上显示一次 */
  notice: null as string | null,
}

export function loggedIn(): boolean { return !!session.user }

const subs = new Set<() => void>()
export function onSession(fn: () => void): () => void { subs.add(fn); return () => { subs.delete(fn) } }
function emit(): void { subs.forEach(fn => { try { fn() } catch (e) { console.error(e) } }) }

const KIND_CN: Record<string, string> = { desktop: '电脑', phone: '手机', tablet: '平板' }
export function endedText(e: Ended): string | null {
  if (!e) return null
  if (e === 'expired') return '登录已失效，请重新登录'
  return `已在另一台${KIND_CN[e.replaced] ?? '设备'}登录`
}

export function setSession(v: SessionUser): void {
  const changed = session.user !== v.username || session.userId !== v.userId || session.sessionId !== v.sessionId
  session.user = v.username; session.userId = v.userId; session.sessionId = v.sessionId
  session.notice = null
  session.accessToken = v.accessToken
  if (changed) emit()
}

export function endSession(why: Ended): void {
  const was = session.user
  session.user = null; session.userId = null; session.sessionId = null
  session.notice = endedText(why)
  session.accessToken = null
  if (was || why) emit()
}
