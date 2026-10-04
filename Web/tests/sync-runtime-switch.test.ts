/* Web 深度审查 C 线 2026-10-05 · 同步运行时在第一次合并 / 推拉途中退登、换账号（sync/runtime.ts、account/client.ts authed） */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { SyncAdapter } from '../src/sync/runtime'
import type { SyncStore } from '../src/sync/store'

// 每条用例一套新模块：运行时挂在会话模块的订阅上，上一条用例的运行时不能跟着下一条的登录走
let session: typeof import('../src/account/session').session
let login: typeof import('../src/account/client').login
let logout: typeof import('../src/account/client').logout
let createSyncRuntime: typeof import('../src/sync/runtime').createSyncRuntime

function memoryStorage(): Storage {
  const m = new Map<string, string>()
  return {
    get length() { return m.size }, clear: () => m.clear(), getItem: k => m.get(k) ?? null,
    key: i => [...m.keys()][i] ?? null, removeItem: k => { m.delete(k) }, setItem: (k, v) => { m.set(k, String(v)) },
  }
}
const json = (status: number, body: unknown): Response => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
const USERS: Record<string, { id: string; token: string }> = { xx: { id: 'ux', token: 'ax' }, yy: { id: 'uy', token: 'ay' } }
const OWNER_OF: Record<string, string> = { 'Bearer ax': 'x', 'Bearer ay': 'y' }

/** 一个按令牌分账号的假服务端：每张表一个对象，id 前缀是账号（x- / y-）。`hold` 命中的那一趟扣住 */
let requests: { url: string; who: string }[]
let held: ((r: Response) => void)[]
let hold: (url: string, who: string) => boolean
function fakeServer(): void {
  vi.stubGlobal('fetch', async (url: string, init: RequestInit) => {
    if (url === '/v1/auth/login') {
      const u = JSON.parse(String(init.body)).username as string
      return json(200, { data: { user: { id: USERS[u].id, email: u }, sessionId: 's' + u, accessToken: USERS[u].token, refreshToken: 'r' + u, expiresAt: 900e3, serverTime: 0 } })
    }
    if (url === '/v1/auth/session/revoke') return json(200, { data: null })
    const who = OWNER_OF[(init.headers as Record<string, string>).Authorization] ?? '?'
    requests.push({ url, who })
    const answer = (): Response => {
      if (url.startsWith('/v1/sync/bootstrap')) {
        const c = new URLSearchParams(url.split('?')[1]).get('collection')!
        return json(200, { data: { objects: [{ collection: c, id: `${who}-${c}`, body: { v: 1 }, fields: {}, revision: 1, deleted: false, generation: 0 }], next: null, cursor: 777, serverTime: 1 } })
      }
      if (url.startsWith('/v1/sync/changes')) return json(200, { data: { objects: [], invalidations: [], cursor: 777, hasMore: false, serverTime: 1 } })
      return json(200, { data: { results: [], serverTime: 1 } })
    }
    if (hold(url, who)) return new Promise<Response>(r => held.push(() => r(answer())))
    return answer()
  })
}

/** 最小的 Web Locks：同名排队；轮到时信号已取消就拒 */
function fakeLocks() {
  const tail = new Map<string, Promise<unknown>>()
  return {
    request(name: string, opts: { signal?: AbortSignal }, fn: () => Promise<unknown>) {
      const p = (tail.get(name) ?? Promise.resolve()).then(() => {
        if (opts.signal?.aborted) throw new DOMException('aborted', 'AbortError')
        return fn()
      })
      tail.set(name, p.catch(() => {}))
      return p
    },
  }
}

/** 记下每次第一次合并时：当时登录的是谁、合并进来的账本里有哪些对象 */
let merges: { as: string | null; ids: string[] }[]
const adapter: SyncAdapter = {
  owned: {}, collections: ['settings', 'favorites'],
  capture: () => 0, apply: () => false,
  mergeFirst: (s: SyncStore) => { merges.push({ as: session.userId, ids: Object.keys(s.a.objects).sort() }) },
  begin: () => {}, end: () => {},
}

let live: Set<unknown>
const settle = async (n = 20) => { for (let i = 0; i < n; i++) await new Promise(r => setTimeout(r, 0)) }

beforeEach(async () => {
  vi.resetModules()
  ;({ session } = await import('../src/account/session'))
  ;({ login, logout } = await import('../src/account/client'))
  ;({ createSyncRuntime } = await import('../src/sync/runtime'))
  vi.stubGlobal('localStorage', memoryStorage())
  session.user = session.userId = session.sessionId = null
  requests = []; held = []; merges = []; hold = () => false
  fakeServer()
  // 数运行时挂着的轮询定时器（15 秒那个）
  live = new Set()
  const si = globalThis.setInterval, ci = globalThis.clearInterval
  vi.stubGlobal('setInterval', ((fn: () => void, ms: number) => { const t = si(fn, ms); if (ms === 15e3) live.add(t); return t }) as typeof setInterval)
  vi.stubGlobal('clearInterval', ((t: ReturnType<typeof setInterval>) => { live.delete(t); ci(t) }) as typeof clearInterval)
})
afterEach(() => { for (const t of live) clearInterval(t as ReturnType<typeof setInterval>); vi.unstubAllGlobals() })

describe('第一次合并途中换账号', () => {
  it('上一个人的账本不合并进下一个人的页面，下一个人照样做自己的第一次合并；旧账本剩下的请求不拿新令牌发', async () => {
    vi.stubGlobal('navigator', {})
    await login('xx', 'pass1234')
    hold = (url, who) => who === 'x' && url.includes('collection=settings')
    const rt = createSyncRuntime(adapter)
    rt.boot()
    await settle()
    expect(held).toHaveLength(1)
    logout(); await login('yy', 'pass1234')
    held.shift()!(undefined as never)
    await settle()
    // 拿着 y 的令牌去拉的只能是 y 自己的第一次合并（两张表各一趟），不能替 x 的账本多拉一趟
    expect(requests.filter(r => r.who === 'y').map(r => r.url)).toEqual(['/v1/sync/bootstrap?collection=settings', '/v1/sync/bootstrap?collection=favorites'])
    expect(merges).toEqual([{ as: 'uy', ids: ['favorites:y-favorites', 'settings:y-settings'] }])
    expect(localStorage.getItem('hkline-web-sync-owner')).toBe('uy')
    expect(rt.live()).toBe(true)
  })
})

describe('第一次合并途中退登', () => {
  it('不留轮询定时器；同一账号再登录能拿到领头锁、重新做第一次合并', async () => {
    vi.stubGlobal('navigator', { locks: fakeLocks() })
    await login('xx', 'pass1234')
    let once = true
    hold = (url, who) => { const h = once && who === 'x' && url.includes('collection=settings'); if (h) once = false; return h }
    const rt = createSyncRuntime(adapter)
    rt.boot()
    await settle()
    expect(held).toHaveLength(1)
    logout()
    held.shift()!(undefined as never)
    await settle()
    expect(live.size).toBe(0)
    await login('xx', 'pass1234')
    await settle()
    expect(merges.map(m => m.as)).toEqual(['ux'])
    expect(rt.live()).toBe(true)
  })
})
