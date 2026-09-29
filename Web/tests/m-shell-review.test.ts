/* 手机网页版收尾审查（同步与壳）：两个标签页、本机存储相关的回归用例 */
import { afterEach, describe, expect, it, vi } from 'vitest'
import { makeDrawing } from '../src/m/chart/draw/drawing'
import swSource from '../public/m/sw.js?raw'

function memStorage(seed: Record<string, string> = {}) {
  const mem = new Map(Object.entries(seed))
  return { mem, api: { getItem: (k: string) => mem.get(k) ?? null, setItem: (k: string, v: string) => { mem.set(k, v) }, removeItem: (k: string) => { mem.delete(k) } } }
}

afterEach(() => { vi.unstubAllGlobals(); vi.resetModules() })

describe('两个标签页共用 hkline-m-v1 / hkline-m-drawings-v1（m/app/tabGuard）', () => {
  it('另一页比我更近被人动过：我变旧，之后 save() 与画线落盘都不再写（不把它刚改的整份盖回去）', async () => {
    const { mem, api } = memStorage()
    vi.stubGlobal('localStorage', api)
    vi.resetModules()
    const { tabGuard } = await import('../src/m/app/tabGuard')
    const store = await import('../src/m/app/store')
    const { drawingBook, DRAWINGS_KEY } = await import('../src/m/app/drawings')
    tabGuard.touch(1000)
    store.st.skin = 'terra'; store.save()
    expect(JSON.parse(mem.get(store.KEY)!).skin).toBe('terra')
    expect(drawingBook.add([makeDrawing('trend', { t: 1_700_000_000_000, p: 100 }, { t: 1_700_000_060_000, p: 110 }, null, 'dA')], 'BTCUSDT')).toBe(true)
    expect(mem.get(DRAWINGS_KEY)).toContain('dA')
    // 另一页（2000 时被人动过）写了皮肤 classic
    mem.set(store.KEY, JSON.stringify({ ...JSON.parse(mem.get(store.KEY)!), skin: 'classic' }))
    mem.set('hkline-m-v1-writer', JSON.stringify({ at: 2000 }))
    expect(tabGuard.onForeignWrite(2000)).toBe('stale')
    // 本页后台自动存一次（同步拉到东西、滚动位置……）：不写
    store.st.scroll = { chart: 10 }; store.save(); store.persistQuiet()
    expect(JSON.parse(mem.get(store.KEY)!).skin).toBe('classic')
    const before = mem.get(DRAWINGS_KEY)
    expect(drawingBook.add([makeDrawing('trend', { t: 1_700_000_100_000, p: 100 }, { t: 1_700_000_160_000, p: 110 }, null, 'dX')], 'BTCUSDT')).toBe(true)
    expect(mem.get(DRAWINGS_KEY)).toBe(before)
  })

  it('另一页是后台拿旧内存自动存的（它被人动得比我早）：我立刻把两份都写回去', async () => {
    const { mem, api } = memStorage()
    vi.stubGlobal('localStorage', api)
    vi.resetModules()
    const { tabGuard } = await import('../src/m/app/tabGuard')
    const store = await import('../src/m/app/store')
    const { DRAWINGS_KEY } = await import('../src/m/app/drawings')
    tabGuard.touch(5000)
    store.st.skin = 'terra'; store.save()
    mem.set(store.KEY, JSON.stringify({ skin: 'classic' }))
    mem.delete(DRAWINGS_KEY)
    expect(tabGuard.onForeignWrite(1000)).toBe('repair')
    expect(JSON.parse(mem.get(store.KEY)!).skin).toBe('terra')
    expect(mem.has(DRAWINGS_KEY)).toBe(true)
    expect(tabGuard.stale).toBe(false)
  })

  it('旧了之后把别的页写的那份收进内存并照常通知（领头页据此把非领头页的改动推上云端），但仍不写盘；解不开的不收', async () => {
    const { mem, api } = memStorage()
    vi.stubGlobal('localStorage', api)
    vi.resetModules()
    const { tabGuard } = await import('../src/m/app/tabGuard')
    const store = await import('../src/m/app/store')
    const D = await import('../src/m/app/drawings')
    const { DrawArchive, encodeArchive } = await import('../src/m/chart/draw/archive')
    tabGuard.touch(1000)
    store.st.skin = 'terra'; store.st.page = 'me'; store.save()
    const seen: string[] = []
    store.subscribe(s => seen.push(s.skin))
    const kinds: string[] = []
    D.onDrawingsChanged(c => kinds.push(c.kind))
    // 另一页（更近被人动过）改了皮肤、换了页、画了一条线
    mem.set(store.KEY, JSON.stringify({ ...JSON.parse(mem.get(store.KEY)!), skin: 'classic', page: 'chart' }))
    const a = new DrawArchive(); a.set('binance/usd_m/BTCUSDT', [makeDrawing('trend', { t: 1_700_000_000_000, p: 100 }, { t: 1_700_000_060_000, p: 110 }, null, 'dB')])
    mem.set(D.DRAWINGS_KEY, JSON.stringify(encodeArchive(a)))
    const written = { st: mem.get(store.KEY), dr: mem.get(D.DRAWINGS_KEY) }
    tabGuard.onForeignWrite(2000, store.KEY)
    tabGuard.onForeignWrite(2000, D.DRAWINGS_KEY)
    tabGuard.flush()
    expect(store.st.skin).toBe('classic')
    expect(store.st.page).toBe('me') // 现场留本页的
    expect(seen).toContain('classic')
    expect(D.drawingBook.items('BTCUSDT').map(d => d.id)).toEqual(['dB'])
    expect(kinds).toContain('replaced')
    expect(mem.get(store.KEY)).toBe(written.st)
    expect(mem.get(D.DRAWINGS_KEY)).toBe(written.dr)
    // 读坏的画线存档：不收（不然同步会把空的当成本机删光了）
    mem.set(D.DRAWINGS_KEY, '{broken')
    tabGuard.onForeignWrite(3000, D.DRAWINGS_KEY); tabGuard.flush()
    expect(D.drawingBook.items('BTCUSDT').map(d => d.id)).toEqual(['dB'])
  })
})

describe('账号设备身份（account/client.device）', () => {
  it('存储写不进去（满了 / 无痕）：同一页里每次拿到的仍是同一个设备 id 与 secret（换令牌时对得上，不被 401 踢下线）', async () => {
    vi.stubGlobal('localStorage', { getItem: () => null, setItem: () => { throw new Error('QuotaExceededError') }, removeItem: () => {} })
    vi.resetModules()
    const A = await import('../src/account/client')
    A.configureAccount({ keyPrefix: 'hkline-m', kind: 'phone' })
    const a = A.device(), b = A.device()
    expect(b.id).toBe(a.id)
    expect(b.secret).toBe(a.secret)
    expect(a.kind).toBe('phone')
  })

  it('存档被清掉后又能写了：把内存里那一份写回去，而不是换一个新的', async () => {
    const { mem, api } = memStorage()
    vi.stubGlobal('localStorage', api)
    vi.resetModules()
    const A = await import('../src/account/client')
    A.configureAccount({ keyPrefix: 'hkline-m', kind: 'phone' })
    const a = A.device()
    mem.clear()
    expect(A.device().id).toBe(a.id)
    expect(JSON.parse(mem.get('hkline-m-device-v1')!).id).toBe(a.id)
  })
})

describe('离线壳（public/m/sw.js）', () => {
  const ORIGIN = 'https://h.example'
  const HTML = '<script type="module" crossorigin src="/web/assets/m-AAA.js"></script><link rel="modulepreload" href="/web/assets/chunk-BBB.js"><link rel="stylesheet" href="/web/assets/m-CCC.css"><link rel="manifest" href="/web/m/manifest.webmanifest">'

  async function loadSw() {
    const src = swSource
    const handlers: Record<string, (e: any) => void> = {}
    const store = new Map<string, unknown>()
    const cache = {
      match: async (k: any) => store.get(typeof k === 'string' ? k : new URL(k.url ?? k, ORIGIN).pathname) ?? undefined,
      put: async (k: any, v: unknown) => { store.set(typeof k === 'string' ? k : new URL(k.url ?? k, ORIGIN).pathname, v) },
      addAll: async (ks: string[]) => { for (const k of ks) store.set(k, 'x') },
    }
    const fetches: { input: unknown; init?: RequestInit }[] = []
    const fetchImpl = async (input: any, init?: RequestInit) => {
      fetches.push({ input, init })
      const path = new URL(typeof input === 'string' ? input : input.url, ORIGIN).pathname
      const body = path === '/web/m/' ? HTML : 'asset'
      return { ok: true, redirected: false, clone() { return this }, text: async () => body, path }
    }
    const self = {
      location: new URL(ORIGIN + '/web/m/sw.js?v=m-AAA.js'),
      registration: { scope: ORIGIN + '/web/m/' },
      addEventListener: (t: string, h: (e: any) => void) => { handlers[t] = h },
      skipWaiting: async () => {}, clients: { claim: async () => {} },
    }
    const cachesApi = { open: async () => cache, match: cache.match, keys: async () => [], delete: async () => true }
    new Function('self', 'caches', 'fetch', 'Response', src)(self, cachesApi, fetchImpl, { error: () => 'error' })
    const run = async (type: string, e: any) => {
      let p: Promise<unknown> | undefined
      handlers[type]({ ...e, waitUntil: (x: Promise<unknown>) => { p = x }, respondWith: (x: Promise<unknown>) => { p = x } })
      return p
    }
    return { run, store, fetches }
  }

  it('导航取壳不走 HTTP 缓存（服务器给 HTML 的 max-age=300 不能让新版发布后还拿 5 分钟旧壳）', async () => {
    const { run, fetches } = await loadSw()
    await run('fetch', { request: { method: 'GET', mode: 'navigate', url: ORIGIN + '/web/m/' } })
    expect(fetches).toHaveLength(1)
    expect(fetches[0].init?.cache).toBe('no-cache')
  })

  it('装的时候就把壳引用的入口脚本、modulepreload、样式存下（第一次打开后断网也能起来）', async () => {
    const { run, store, fetches } = await loadSw()
    await run('install', {})
    expect(fetches[0].init?.cache).toBe('no-cache')
    for (const k of ['/web/m/', '/web/assets/m-AAA.js', '/web/assets/chunk-BBB.js', '/web/assets/m-CCC.css', '/web/m/manifest.webmanifest']) expect(store.has(k), k).toBe(true)
  })

  it('页面报来的已加载产物只补存同源 /web/assets/ 下的，外站与接口不收', async () => {
    const { run, store } = await loadSw()
    await run('message', { data: { type: 'keep', urls: [ORIGIN + '/web/assets/page-me-DDD.js', 'https://fapi.binance.com/fapi/v1/ticker', ORIGIN + '/v1/auth/me', 42] } })
    expect(store.has('/web/assets/page-me-DDD.js')).toBe(true)
    expect([...store.keys()].some(k => k.includes('binance') || k.includes('/v1/'))).toBe(false)
  })
})
