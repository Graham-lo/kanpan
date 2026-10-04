/* Web 深度审查 C 线 2026-10-05 · 换令牌在路上时退登 / 换账号（account/client.ts refresh） */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { session } from '../src/account/session'
import { ACCOUNT_KEY, ISSUER, login, logout, readStored, refresh } from '../src/account/client'

function memoryStorage(): Storage {
  const m = new Map<string, string>()
  return {
    get length() { return m.size }, clear: () => m.clear(), getItem: k => m.get(k) ?? null,
    key: i => [...m.keys()][i] ?? null, removeItem: k => { m.delete(k) }, setItem: (k, v) => { m.set(k, String(v)) },
  }
}
const json = (status: number, body: unknown): Response => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
const X = { issuer: ISSUER, username: 'xx', userId: 'ux', sessionId: 'sx', accessToken: 'ax', refreshToken: 'rx', accessDeadline: 0 }

/** 换令牌请求挂起，由测试决定什么时候、以什么结果回 */
let release: (r: Response) => void
beforeEach(() => {
  vi.stubGlobal('localStorage', memoryStorage())
  localStorage.setItem(ACCOUNT_KEY, JSON.stringify(X))
  session.user = 'xx'; session.userId = 'ux'; session.sessionId = 'sx'; session.notice = null
  vi.stubGlobal('fetch', async (url: string) => {
    if (url === '/v1/auth/refresh') return new Promise<Response>(r => { release = r })
    if (url === '/v1/auth/login') return json(200, { data: { user: { id: 'uy', email: 'yy' }, sessionId: 'sy', accessToken: 'ay', refreshToken: 'ry', expiresAt: 900e3, serverTime: 0 } })
    return json(200, { data: null })
  })
})
afterEach(() => { vi.unstubAllGlobals() })
const tick = () => new Promise(r => setTimeout(r, 0))

describe('换令牌在路上时换了账号', () => {
  it('旧账号换回来的令牌不盖掉新登录的账号', async () => {
    const p = refresh('rx').catch(e => e)
    await tick()
    logout(); await login('yy', 'pass1234')
    release(json(200, { data: { sessionId: 'sx', accessToken: 'ax2', refreshToken: 'rx2', expiresAt: 900e3, serverTime: 0 } }))
    await p
    expect(readStored()?.userId).toBe('uy')
    expect(readStored()?.refreshToken).toBe('ry')
    expect(session.user).toBe('yy')
  })

  it('旧账号的换令牌被拒（退登时已吊销）不把新账号的会话清掉', async () => {
    const p = refresh('rx').catch(e => e)
    await tick()
    logout(); await login('yy', 'pass1234')
    release(json(401, { error: { code: 'authentication_failed' } }))
    await p
    expect(readStored()?.userId).toBe('uy')
    expect(session.user).toBe('yy')
    expect(session.notice).toBeNull()
  })

  it('退登后又登录：新账号的换令牌不拿旧会话那一次的结果', async () => {
    const p1 = refresh('rx').catch(e => e)
    await tick()
    logout(); await login('yy', 'pass1234')
    const p2 = refresh('ry')
    expect(p2).not.toBe(p1)
    release(json(200, { data: { sessionId: 'sx', accessToken: 'ax2', refreshToken: 'rx2', expiresAt: 900e3, serverTime: 0 } }))
    await p1; await tick()
    release(json(200, { data: { sessionId: 'sy', accessToken: 'ay2', refreshToken: 'ry2', expiresAt: 900e3, serverTime: 0 } }))
    expect((await p2).refreshToken).toBe('ry2')
  })
})

describe('主动退登不报「登录已失效」', () => {
  it('别的标签页退登后这一页再换令牌：回到未登录，不显示失效提示', async () => {
    localStorage.removeItem(ACCOUNT_KEY)   // 别的标签页退登（storage 事件还没到）
    await expect(refresh('rx')).rejects.toThrow()
    expect(session.user).toBeNull()
    expect(session.notice).toBeNull()
  })

  it('真的过期（服务端 401）照旧提示失效', async () => {
    const p = refresh('rx').catch(e => e)
    await tick()
    release(json(401, { error: { code: 'authentication_failed' } }))
    await p
    expect(readStored()).toBeNull()
    expect(session.notice).toBe('登录已失效，请重新登录')
  })
})
