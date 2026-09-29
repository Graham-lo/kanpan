/* Hkline 手机网页版 · Service Worker：只缓存壳，行情永远走网络。
 *
 * 版本号来自注册地址的 ?v=（main.ts 用本次构建的入口脚本名，构建一次变一次）：
 * 版本一变浏览器就装新的 SW，activate 时把旧版本的缓存全删掉。
 *
 * - 页面导航（/web/m/ 本身）：网络优先，断网时回缓存里的壳（冷启动不白屏）。
 * - /web/assets/*（带哈希的脚本、样式，内容不变）：缓存优先。
 * - /web/m/ 下的图标与 manifest：先回缓存、后台刷新。
 * - 其余一切（币安 REST / WS、/v1 账号与元数据、/market 网关）：不拦，原样走网络。
 *
 * 装的时候就把壳和它引用的入口脚本、样式（从壳的 HTML 里读出来）一起存下；页面起来之后再把这一次
 * 实际加载过的构建产物（懒加载的各页）报过来补存——否则第一次打开时这些都是 SW 装好之前取的，
 * 进不了缓存，下一次断网打开就是白屏。
 * 导航取壳一律向服务器验证（cache: 'no-cache'，没改就是 304）：静态服务器给 HTML 的 max-age=300
 * 会让新版发布后还在 5 分钟里拿到旧壳。
 */
const VERSION = new URL(self.location.href).searchParams.get('v') || 'dev'
const CACHE = 'hkline-m-shell-' + VERSION
const SCOPE = new URL(self.registration ? self.registration.scope : './', self.location.href).pathname // /web/m/
const BASE = SCOPE.replace(/m\/$/, '') // /web/

/** 壳 HTML 里引用的构建产物（入口脚本、样式、modulepreload） */
function assetsOf(html) {
  const out = new Set()
  for (const m of html.matchAll(/(?:src|href)="([^"]+)"/g)) {
    const u = new URL(m[1], self.location.href)
    if (u.origin === self.location.origin && u.pathname.startsWith(BASE + 'assets/')) out.add(u.pathname)
  }
  return [...out]
}

/** 只存同源、在 /web/assets/ 下、这一版缓存里还没有的 */
async function keep(cache, urls) {
  const want = urls.map(u => new URL(u, self.location.href)).filter(u => u.origin === self.location.origin && u.pathname.startsWith(BASE + 'assets/'))
  await Promise.all(want.map(async u => {
    if (await cache.match(u.pathname)) return
    const res = await fetch(u.pathname)
    if (res.ok) await cache.put(u.pathname, res)
  }))
}

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE)
    try {
      const res = await fetch(SCOPE, { cache: 'no-cache' })
      if (res.ok) {
        const html = await res.clone().text()
        await cache.put(SCOPE, res)
        await keep(cache, assetsOf(html))
      }
      await cache.addAll([SCOPE + 'manifest.webmanifest', SCOPE + 'icon-180.png'])
    } catch (e) {
      // 装的时候网不好：壳照样装上，下一次在线打开时导航与构建产物会顺手补进缓存
      console.warn('[sw] 预存壳失败', e)
    }
    await self.skipWaiting()
  })())
})

// 页面报来这一次实际加载过的构建产物（main.ts 在 SW 就绪后发）
self.addEventListener('message', event => {
  const d = event.data
  if (!d || d.type !== 'keep' || !Array.isArray(d.urls)) return
  event.waitUntil(caches.open(CACHE).then(c => keep(c, d.urls.filter(u => typeof u === 'string'))).catch(e => console.warn('[sw] 补存失败', e)))
})

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k.startsWith('hkline-m-shell-') && k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim()),
  )
})

self.addEventListener('fetch', event => {
  const req = event.request
  if (req.method !== 'GET') return
  const url = new URL(req.url)
  if (url.origin !== self.location.origin) return

  // 页面导航：网络优先
  if (req.mode === 'navigate' && url.pathname.startsWith(SCOPE)) {
    event.respondWith(
      fetch(req, { cache: 'no-cache' }).then(res => {
        if (res.ok && !res.redirected) { const copy = res.clone(); caches.open(CACHE).then(c => c.put(SCOPE, copy)) }
        return res
      }).catch(() => caches.match(SCOPE).then(r => r || Response.error())),
    )
    return
  }
  // 带哈希的构建产物：缓存优先
  if (url.pathname.startsWith(BASE + 'assets/')) {
    event.respondWith(
      caches.match(req).then(hit => hit || fetch(req).then(res => {
        if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put(req, copy)) }
        return res
      })),
    )
    return
  }
  // 图标、manifest：先回缓存，后台刷新
  if (url.pathname.startsWith(SCOPE) && /\.(png|webmanifest|svg)$/.test(url.pathname)) {
    event.respondWith(
      caches.open(CACHE).then(c => c.match(req).then(hit => {
        const net = fetch(req).then(res => { if (res.ok) c.put(req, res.clone()); return res }).catch(() => hit)
        return hit || net
      })),
    )
  }
  // 其余不拦
})
