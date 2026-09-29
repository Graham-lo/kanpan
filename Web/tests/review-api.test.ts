import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { st } from '../src/app/store'
import { ACCOUNT_KEY, ISSUER } from '../src/account/client'
import { ReviewError, reviewApi } from '../src/review/api'

/** 最小的 localStorage：client.ts 只用 getItem / setItem / removeItem */
function memoryStorage(): Storage {
  const m = new Map<string, string>()
  return {
    get length() { return m.size },
    clear: () => m.clear(),
    getItem: k => m.get(k) ?? null,
    key: i => [...m.keys()][i] ?? null,
    removeItem: k => { m.delete(k) },
    setItem: (k, v) => { m.set(k, String(v)) },
  }
}

const json = (status: number, body: unknown): Response => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })

describe('复盘接口走账号模块的令牌', () => {
  let calls: { url: string; auth: string | null }[]
  beforeEach(() => {
    vi.stubGlobal('localStorage', memoryStorage())
    st.account = null
    calls = []
    vi.stubGlobal('fetch', async (url: string, init: RequestInit) => {
      const auth = (init.headers as Record<string, string>)?.Authorization ?? null
      calls.push({ url, auth })
      if (url === '/v1/auth/refresh') return json(200, { data: { sessionId: 's1', accessToken: 'fresh-access', refreshToken: 'r2', expiresAt: 900e3, serverTime: 0 } })
      if (url === '/v1/native-review/statistics') return auth === 'Bearer fresh-access' ? json(200, { data: { groups: [] } }) : json(401, { error: { code: 'authentication_failed' } })
      return json(404, { error: { code: 'not_found' } })
    })
  })
  afterEach(() => { vi.unstubAllGlobals() })

  it('access 已过期（浏览器关了一阵再打开）：先换令牌再取，不判「登录已过期」', async () => {
    localStorage.setItem(ACCOUNT_KEY, JSON.stringify({ issuer: ISSUER, username: 'u', userId: 'u1', sessionId: 's1', accessToken: 'stale', refreshToken: 'r1', accessDeadline: Date.now() - 60e3 }))
    await expect(reviewApi.statistics()).resolves.toEqual({ groups: [] })
    expect(calls.map(c => c.url)).toEqual(['/v1/auth/refresh', '/v1/native-review/statistics'])
  })

  it('access 没到期但被服务端拒：换一次再试', async () => {
    localStorage.setItem(ACCOUNT_KEY, JSON.stringify({ issuer: ISSUER, username: 'u', userId: 'u1', sessionId: 's1', accessToken: 'revoked', refreshToken: 'r1', accessDeadline: Date.now() + 600e3 }))
    await expect(reviewApi.statistics()).resolves.toEqual({ groups: [] })
    expect(calls.map(c => c.url)).toEqual(['/v1/native-review/statistics', '/v1/auth/refresh', '/v1/native-review/statistics'])
  })

  it('收藏相似片段：服务端只回 {item}，存完从列表取回版本号（取消收藏要带它）', async () => {
    localStorage.setItem(ACCOUNT_KEY, JSON.stringify({ issuer: ISSUER, username: 'u', userId: 'u1', sessionId: 's1', accessToken: 'fresh-access', refreshToken: 'r1', accessDeadline: Date.now() + 600e3 }))
    const item = { id: 'm1', range: {}, score: 0.8, source: 'history' }
    vi.stubGlobal('fetch', async (url: string, init: RequestInit) => {
      calls.push({ url, auth: (init.headers as Record<string, string>)?.Authorization ?? null })
      if (url === '/v1/native-review/saved-matches' && init.method === 'POST') return json(200, { data: { item } })
      if (url === '/v1/native-review/saved-matches') return json(200, { data: { items: [{ item: { id: 'm0' }, revision: 1 }, { item, revision: 3 }], next: null } })
      return json(404, { error: { code: 'not_found' } })
    })
    const s = await reviewApi.save('s1', 'm1')
    expect(s.revision).toBe(3)
    expect(s.item.id).toBe('m1')
  })

  it('没登录：不发请求，回 not_logged_in（401）', async () => {
    const e = await reviewApi.statistics().catch(x => x)
    expect(e).toBeInstanceOf(ReviewError)
    expect([e.code, e.status]).toEqual(['not_logged_in', 401])
    expect(calls).toEqual([])
  })
})
