/* Hkline 手机网页版 · Service Worker：只缓存壳，行情永远走网络。
 *
 * 版本号来自注册地址的 ?v=（main.ts 用本次构建的入口脚本名，构建一次变一次）：
 * 版本一变浏览器就装新的 SW，activate 时把旧版本的缓存全删掉。
 *
 * - 页面导航（/web/m/ 本身）：网络优先，断网时回缓存里的壳（冷启动不白屏）。
 * - /web/assets/*（带哈希的脚本、样式，内容不变）：缓存优先。
 * - /web/m/ 下的图标与 manifest：先回缓存、后台刷新。
 * - 其余一切（币安 REST / WS、/v1 账号与元数据、/market 网关）：不拦，原样走网络。
 */
const VERSION = new URL(self.location.href).searchParams.get('v') || 'dev'
const CACHE = 'hkline-m-shell-' + VERSION
const SCOPE = new URL(self.registration ? self.registration.scope : './', self.location.href).pathname // /web/m/
const BASE = SCOPE.replace(/m\/$/, '') // /web/

self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(c => c.addAll([SCOPE, SCOPE + 'manifest.webmanifest', SCOPE + 'icon-180.png'])).catch(() => {}).then(() => self.skipWaiting()))
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
      fetch(req).then(res => {
        if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put(SCOPE, copy)) }
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
