/* 手机网页离线壳换版：新版没存全不许顶掉旧版；页面报的已加载产物要送到接管后的那个 SW */
import { describe, expect, it } from 'vitest'
import swSource from '../public/m/sw.js?raw'
import mainSource from '../src/m/main.ts?raw'

const ORIGIN = 'https://h.example'
const HTML = '<script type="module" crossorigin src="/web/assets/m-AAA.js"></script><link rel="modulepreload" href="/web/assets/chunk-BBB.js"><link rel="stylesheet" href="/web/assets/m-CCC.css">'

/** 装一份 v=新版 的 SW；caches 里事先放着旧版那份完整缓存 */
function loadSw(fail: (path: string) => 'throw' | number | null) {
  const handlers: Record<string, (e: any) => void> = {}
  const caches = new Map<string, Map<string, unknown>>([['hkline-m-shell-m-OLD.js', new Map([['/web/m/', 'old-shell'], ['/web/assets/m-OLD.js', 'x']])]])
  const cacheOf = (name: string) => {
    if (!caches.has(name)) caches.set(name, new Map())
    const m = caches.get(name)!
    const key = (k: any) => typeof k === 'string' ? k : new URL(k.url ?? k, ORIGIN).pathname
    return { match: async (k: any) => m.get(key(k)), put: async (k: any, v: unknown) => { m.set(key(k), v) }, addAll: async (ks: string[]) => { for (const k of ks) m.set(k, 'x') } }
  }
  const fetchImpl = async (input: any) => {
    const path = new URL(typeof input === 'string' ? input : input.url, ORIGIN).pathname
    const f = fail(path)
    if (f === 'throw') throw new TypeError('Failed to fetch')
    return { ok: f === null, status: f ?? 200, redirected: false, clone() { return this }, text: async () => path === '/web/m/' ? HTML : 'asset' }
  }
  let skipped = 0
  const self = {
    location: new URL(ORIGIN + '/web/m/sw.js?v=m-NEW.js'),
    registration: { scope: ORIGIN + '/web/m/' },
    addEventListener: (t: string, h: (e: any) => void) => { handlers[t] = h },
    skipWaiting: async () => { skipped++ }, clients: { claim: async () => {} },
  }
  const cachesApi = {
    open: async (n: string) => cacheOf(n),
    keys: async () => [...caches.keys()],
    delete: async (n: string) => caches.delete(n),
    match: async () => undefined,
  }
  new Function('self', 'caches', 'fetch', 'Response', swSource)(self, cachesApi, fetchImpl, { error: () => 'error' })
  const install = () => { let p!: Promise<unknown>; handlers.install({ waitUntil: (x: Promise<unknown>) => { p = x } }); return p }
  return { install, caches, skipped: () => skipped }
}

describe('离线壳换版（public/m/sw.js install）', () => {
  for (const [name, fail] of [
    ['入口脚本取回 404', (p: string) => p === '/web/assets/chunk-BBB.js' ? 404 : null],
    ['取壳时断网', (p: string) => p === '/web/m/' ? 'throw' : null],
    ['壳本身 503', (p: string) => p === '/web/m/' ? 503 : null],
    ['样式取到一半断网', (p: string) => p === '/web/assets/m-CCC.css' ? 'throw' : null],
  ] as const) {
    it(`${name}：本次安装失败、不 skipWaiting、不留半份缓存，旧版那份完整的照旧在`, async () => {
      const sw = loadSw(fail as (p: string) => 'throw' | number | null)
      await expect(sw.install()).rejects.toBeTruthy()
      expect(sw.skipped()).toBe(0)
      expect(sw.caches.has('hkline-m-shell-m-NEW.js')).toBe(false)
      expect(sw.caches.get('hkline-m-shell-m-OLD.js')!.get('/web/m/')).toBe('old-shell')
    })
  }

  it('全都取到：壳与产物都进新缓存，然后才 skipWaiting', async () => {
    const sw = loadSw(() => null)
    await sw.install()
    expect(sw.skipped()).toBe(1)
    const c = sw.caches.get('hkline-m-shell-m-NEW.js')!
    for (const k of ['/web/m/', '/web/assets/m-AAA.js', '/web/assets/chunk-BBB.js', '/web/assets/m-CCC.css']) expect(c.has(k), k).toBe(true)
  })
})

describe('已加载产物补存（src/m/main.ts）', () => {
  it('接管者换成新版时（controllerchange）再报一次，报给新的 controller', () => {
    expect(mainSource).toMatch(/addEventListener\('controllerchange',[^\n]*report\(navigator\.serviceWorker\.controller\)/)
  })
})
