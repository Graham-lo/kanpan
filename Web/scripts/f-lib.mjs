// Hkline Web · F 线（2026-10-05 深度审查：性能与压测）共用件
//   被 scripts/f-perf.mjs 引用，不单独跑。
//   · preview()：自己起一个 vite preview（dist 要先 build），返回地址与关闭函数；进程退出时一定杀掉
//   · launch()：本机 Chrome 无头，关掉后台 / 遮挡降频（否则无头 rAF 时有时无，读数不可信——D 线结论）
//   · INSTR：注入页面的探针，按「目标:类型」记 window / document / MediaQueryList / visualViewport 上的净监听数，
//     记活着的 setInterval、挂着的 setTimeout、WebSocket 开关 / 订阅 / 消息数、localStorage 写入次数 / 字节 / 耗时、
//     rAF 回调数、fetch 次数（按主机 + 路径）、长任务
//   · mockKlines(ctx)：K 线 REST（直连 fapi.binance.com 与网关 /v1/market/raw/fapi/v1/klines 两种地址）用合成数据，
//     每只品种以真实现价为基准、往前 depth 根；带固定延迟模拟网络，串行瓶颈会被放大出来。WebSocket 照走线上
//   · metrics(cdp, page)：两次强制 GC 后读 CDP Performance.getMetrics 与探针
import { chromium } from 'playwright-core'
import { spawn } from 'node:child_process'
import os from "node:os"

export const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
export const sleep = ms => new Promise(r => setTimeout(r, ms))
export const med = a => { const s = [...a].filter(x => x != null && !Number.isNaN(x)).sort((x, y) => x - y); return s.length ? s[Math.floor((s.length - 1) / 2)] : NaN }
export const pct = (a, p) => { const s = [...a].sort((x, y) => x - y); return s.length ? s[Math.min(s.length - 1, Math.floor(s.length * p))] : NaN }

/** root：要预览的 Web 目录（默认本仓库；对照改动前的数字时传一个 git worktree 里构建好的目录，环境变量 F_ROOT 也行） */
export async function preview(port = 5302, root = process.env.F_ROOT || new URL('..', import.meta.url).pathname) {
  const srv = spawn(new URL('../node_modules/.bin/vite', import.meta.url).pathname, ['preview', '--port', String(port), '--strictPort'], { cwd: root, stdio: ['ignore', 'pipe', 'pipe'] })
  await new Promise((res, rej) => { srv.stdout.on('data', d => { if (/localhost:/.test(String(d))) res() }); srv.on('exit', c => rej(new Error('preview 退出 ' + c))); setTimeout(() => rej(new Error('preview 起不来')), 20000) })
  const stop = () => { try { srv.kill('SIGTERM') } catch { /* 已退 */ } }
  process.on('exit', stop)
  process.on('SIGINT', () => { stop(); process.exit(130) })
  return { url: `http://localhost:${port}/web/`, stop }
}

export async function launch() {
  return chromium.launch({
    executablePath: CHROME, headless: true,
    args: ['--enable-precise-memory-info', '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--disable-backgrounding-occluded-windows', '--js-flags=--expose-gc'],
  })
}

/** 注入探针（addInitScript） */
export const INSTR = () => {
  const F = (window.__f = { gl: {}, iv: new Map(), to: new Map(), ws: { opened: 0, closed: 0, live: new Set(), subs: 0, unsubs: 0, msgs: 0, sent: 0 }, ls: { n: 0, bytes: 0, ms: 0, byKey: {} }, raf: 0, fetch: {}, lt: [], errs: [] })
  const add = EventTarget.prototype.addEventListener, rem = EventTarget.prototype.removeEventListener
  const nm = t => t === window ? 'window' : t === document ? 'document' : (typeof MediaQueryList !== 'undefined' && t instanceof MediaQueryList) ? 'mq' : t === window.visualViewport ? 'vv' : null
  // 同一个 (目标, 类型, 函数, capture) 重复 add 浏览器只认一次，这里也只记一次
  const seen = new WeakMap()
  const keyOf = (ty, o) => ty + ':' + (typeof o === 'boolean' ? o : !!(o && o.capture))
  EventTarget.prototype.addEventListener = function (ty, f, o) {
    const n = nm(this)
    if (n && f) {
      let s = seen.get(f); if (!s) { s = new Set(); seen.set(f, s) }
      const k = n + '|' + keyOf(ty, o)
      if (!s.has(k)) {
        s.add(k); F.gl[n + ':' + ty] = (F.gl[n + ':' + ty] || 0) + 1
        // 挂在 AbortSignal 上的监听，abort 时浏览器自己摘，不走 removeEventListener
        const sig = o && typeof o === 'object' ? o.signal : null
        if (sig) add.call(sig, 'abort', () => { if (s.has(k)) { s.delete(k); F.gl[n + ':' + ty] = (F.gl[n + ':' + ty] || 0) - 1 } }, { once: true })
      }
    }
    return add.call(this, ty, f, o)
  }
  EventTarget.prototype.removeEventListener = function (ty, f, o) {
    const n = nm(this)
    if (n && f) { const s = seen.get(f), k = n + '|' + keyOf(ty, o); if (s && s.has(k)) { s.delete(k); F.gl[n + ':' + ty] = (F.gl[n + ':' + ty] || 0) - 1 } }
    return rem.call(this, ty, f, o)
  }
  // 定时器：记下是谁起的（栈的第二、三帧），泄漏时好找
  const where = () => { const s = new Error().stack?.split('\n') || []; return (s[3] || '').trim().replace(/https?:\/\/[^/]+/, '').slice(0, 120) }
  const si = window.setInterval, ci = window.clearInterval, sto = window.setTimeout, cto = window.clearTimeout
  window.setInterval = function (fn, ms, ...a) { const id = si.call(window, fn, ms, ...a); F.iv.set(id, { ms, at: where() }); return id }
  window.clearInterval = function (id) { F.iv.delete(id); return ci.call(window, id) }
  window.setTimeout = function (fn, ms, ...a) {
    let id
    const wrapped = typeof fn === 'function' ? function (...x) { F.to.delete(id); return fn.apply(this, x) } : fn
    id = sto.call(window, wrapped, ms, ...a); F.to.set(id, { ms, at: where() }); return id
  }
  window.clearTimeout = function (id) { F.to.delete(id); return cto.call(window, id) }
  const raf = window.requestAnimationFrame
  window.requestAnimationFrame = function (cb) { return raf.call(window, t => { F.raf++; cb(t) }) }
  const W = window.WebSocket
  window.WebSocket = class extends W {
    constructor(u, p) {
      super(u, p)
      F.ws.opened++; F.ws.live.add(this); this.__u = String(u)
      this.addEventListener('close', () => { F.ws.closed++; F.ws.live.delete(this) })
      this.addEventListener('message', () => { F.ws.msgs++; if (F.firstMsg == null) F.firstMsg = performance.now() })
    }
    send(d) {
      F.ws.sent++
      try { const m = JSON.parse(d); if (m.method === 'SUBSCRIBE') F.ws.subs += m.params.length; if (m.method === 'UNSUBSCRIBE') F.ws.unsubs += m.params.length } catch { /* 不是 JSON */ }
      return super.send(d)
    }
  }
  const setItem = Storage.prototype.setItem
  Storage.prototype.setItem = function (k, v) {
    const t = performance.now()
    try { return setItem.call(this, k, v) } finally {
      if (this === window.localStorage) { const dt = performance.now() - t; F.ls.n++; F.ls.bytes += String(v).length; F.ls.ms += dt; const b = (F.ls.byKey[k] ||= { n: 0, bytes: 0, ms: 0 }); b.n++; b.bytes += String(v).length; b.ms += dt }
    }
  }
  const ft = window.fetch
  window.fetch = function (input, init) {
    try { const u = new URL(typeof input === 'string' ? input : input.url, location.href); const k = u.host.replace(/^kanpan\.43-160-232-253\.sslip\.io$/, 'api') + u.pathname; F.fetch[k] = (F.fetch[k] || 0) + 1 } catch { /* 无 */ }
    const pr = ft.call(this, input, init)
    if (F.firstKl == null && /klines/.test(String(typeof input === 'string' ? input : input.url))) pr.then(() => { if (F.firstKl == null) { F.firstKl = performance.now(); raf.call(window, () => raf.call(window, () => { F.firstKlFrame = performance.now() })) } }, () => {})
    return pr
  }
  try { new PerformanceObserver(l => { for (const e of l.getEntries()) F.lt.push(Math.round(e.duration)) }).observe({ type: 'longtask', buffered: true }) } catch { /* 无 */ }
  window.addEventListener('error', e => F.errs.push(String(e.message)))
  window.addEventListener('unhandledrejection', e => F.errs.push('rej: ' + String(e.reason?.message || e.reason)))
  // 每帧主线程时间：两次 rAF 之间的间隔（真实刷新下 16.7 ms 为满帧）
  F.frames = []
  F.frameOn = false
  const tick = t => { if (F.frameOn) { if (F._last != null) F.frames.push(t - F._last); F._last = t; raf.call(window, tick) } }
  F.startFrames = () => { F.frames = []; F._last = null; F.frameOn = true; raf.call(window, tick) }
  F.stopFrames = () => { F.frameOn = false; return F.frames }
}

/** 探针快照（页内） */
export const snapF = () => {
  const F = window.__f
  const ivBy = {}
  for (const v of F.iv.values()) ivBy[v.at] = (ivBy[v.at] || 0) + 1
  const toBy = {}
  for (const v of F.to.values()) { const k = v.at + ' ' + v.ms + 'ms'; toBy[k] = (toBy[k] || 0) + 1 }
  return { gl: { ...F.gl }, iv: F.iv.size, ivBy, to: F.to.size, toBy, ws: { opened: F.ws.opened, closed: F.ws.closed, live: F.ws.live.size, subs: F.ws.subs, unsubs: F.ws.unsubs, msgs: F.ws.msgs, sent: F.ws.sent, urls: [...F.ws.live].map(w => w.__u.replace(/\?.*/, '')) }, ls: { n: F.ls.n, bytes: F.ls.bytes, ms: Math.round(F.ls.ms * 10) / 10, byKey: F.ls.byKey }, raf: F.raf, fetch: { ...F.fetch }, lt: F.lt.slice(), errs: F.errs.slice() }
}

export async function metrics(cdp, page, gc = true) {
  if (gc) { await cdp.send('HeapProfiler.collectGarbage'); await cdp.send('HeapProfiler.collectGarbage') }
  const m = Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map(x => [x.name, x.value]))
  const f = await page.evaluate(snapF)
  return { heap: +(m.JSHeapUsedSize / 1048576).toFixed(2), nodes: m.Nodes, listeners: m.JSEventListeners, docs: m.Documents, layouts: m.LayoutCount, recalcs: m.RecalcStyleCount, task: m.TaskDuration, script: m.ScriptDuration, layoutMs: m.LayoutDuration, ...f }
}
export const diffGl = (a, b) => { const d = {}; for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) if ((b[k] || 0) !== (a[k] || 0)) d[k] = (b[k] || 0) - (a[k] || 0); return d }
export const line = (tag, m0, m1) => `${tag}：堆 ${m0.heap}→${m1.heap} MB、节点 ${m0.nodes}→${m1.nodes}、JS 监听 ${m0.listeners}→${m1.listeners}、窗口监听差 ${JSON.stringify(diffGl(m0.gl, m1.gl))}、interval ${m0.iv}→${m1.iv}、timeout ${m0.to}→${m1.to}、WS 活 ${m0.ws.live}→${m1.ws.live}（开 ${m1.ws.opened - m0.ws.opened}、订 ${m1.ws.subs - m0.ws.subs} 退 ${m1.ws.unsubs - m0.ws.unsubs}）`

// ───────── 合成 K 线
const IV = { '1s': 1e3, '5s': 5e3, '15s': 15e3, '1m': 6e4, '3m': 18e4, '5m': 3e5, '15m': 9e5, '30m': 18e5, '1h': 36e5, '2h': 72e5, '4h': 144e5, '6h': 216e5, '8h': 288e5, '12h': 432e5, '1d': 864e5, '3d': 2592e5, '1w': 6048e5, '1M': 2592e6 }
let prices = null
export async function realPrices() {
  if (prices) return prices
  prices = {}
  try {
    const r = await fetch('https://fapi.binance.com/fapi/v1/ticker/price', { signal: AbortSignal.timeout(8000) })
    for (const x of await r.json()) prices[x.symbol] = +x.price
  } catch {
    try { const r = await fetch('https://kanpan.43-160-232-253.sslip.io/v1/market/raw/fapi/v1/ticker/price?source=binance', { signal: AbortSignal.timeout(8000) }); for (const x of await r.json()) prices[x.symbol] = +x.price } catch { /* 用 100 */ }
  }
  return prices
}
export function synthBars(symbol, iv, endTime, limit, depth, now = Date.now()) {
  const m = IV[iv] || 6e4, base = prices?.[symbol] || 100
  const t0 = Math.floor(now / m) * m, first = t0 - (depth - 1) * m
  let hi = endTime ? Math.floor(+endTime / m) * m : t0
  if (hi > t0) hi = t0
  const rows = []
  for (let t = Math.max(first, hi - (limit - 1) * m); t <= hi; t += m) {
    const k = (t0 - t) / m
    const f = x => base * (1 + 0.004 * Math.sin(x / 37) + 0.002 * Math.sin(x / 5.3) + 0.01 * Math.sin(x / 400))
    const c = f(k), o = f(k + 1), h = Math.max(o, c) * 1.0006, l = Math.min(o, c) * 0.9994, v = 40 + 30 * Math.abs(Math.sin(k / 3))
    rows.push([t, String(o), String(h), String(l), String(c), String(v), t + m - 1, String(v * c), 500, String(v * 0.5), String(v * c * 0.52), '0'])
  }
  return rows
}
/** K 线 REST 用合成数据；depth = 每只品种往前最多多少根；delay = 每次请求的人造延迟（ms） */
export async function mockKlines(ctx, { depth = 6000, delay = 120, count } = {}) {
  await realPrices()
  await ctx.route(/\/fapi\/v1\/klines\?/, async route => {
    const u = new URL(route.request().url())
    const rows = synthBars(u.searchParams.get('symbol'), u.searchParams.get('interval'), u.searchParams.get('endTime'), +u.searchParams.get('limit') || 500, depth)
    if (count) count.n++
    if (delay) await sleep(delay)
    route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(rows) }).catch(() => {})
  })
}

/** 一段操作里每帧间隔与长任务（页内 rAF 计时；CDP TaskDuration 算主线程占用） */
export async function measure(page, cdp, fn) {
  await page.evaluate(() => { window.__f.lt.length = 0; window.__f.startFrames() })
  const g = async () => Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map(x => [x.name, x.value]))
  const m0 = await g(), w0 = Date.now()
  let load = os.loadavg()[0]; const lw = setInterval(() => { load = Math.max(load, os.loadavg()[0]) }, 1000)
  try { await fn() } finally { clearInterval(lw) }
  const m1 = await g(), wall = (Date.now() - w0) / 1000
  const frames = await page.evaluate(() => window.__f.stopFrames())
  const lt = await page.evaluate(() => window.__f.lt.slice())
  return {
    wall, cpu: +((m1.TaskDuration - m0.TaskDuration) / wall * 100).toFixed(1), script: +((m1.ScriptDuration - m0.ScriptDuration) / wall * 100).toFixed(1),
    layouts: m1.LayoutCount - m0.LayoutCount, layoutMs: Math.round((m1.LayoutDuration - m0.LayoutDuration) * 1000), recalcs: m1.RecalcStyleCount - m0.RecalcStyleCount,
    p50: +pct(frames, 0.5).toFixed(1), p95: +pct(frames, 0.95).toFixed(1), max: +Math.max(0, ...frames).toFixed(1), dropped: frames.filter(x => x > 25).length, frames: frames.length,
    lt: lt.length, ltMax: lt.length ? Math.max(...lt) : 0, 机器负载: +load.toFixed(1),
  }
}

// ───────── 视口与重本机档
export const PC = { viewport: { width: 2560, height: 1440 }, deviceScaleFactor: 1, locale: 'zh-CN', timezoneId: 'Asia/Shanghai' }
export const M = { viewport: { width: 430, height: 932 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true, locale: 'zh-CN', timezoneId: 'Asia/Shanghai', userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 26_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1' }
export const NOVA = { ...M, viewport: { width: 412, height: 915 }, deviceScaleFactor: 2.625, userAgent: 'Mozilla/5.0 (Linux; Android 12; HarmonyOS; nova 16) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36' }

// ───────── 重本机档
export async function heavyPc(nSyms = 300) {
  const px = await realPrices()
  const syms = Object.keys(px).filter(s => /USDT$/.test(s)).slice(0, nSyms)
  const drawings = {}
  const now = Date.now()
  const mk = (sym, i) => ({ id: `f${sym}${i}`, type: ['hline', 'trend', 'rect', 'fib', 'ray'][i % 5], pts: [{ t: now - (i + 10) * 36e5, p: (px[sym] || 100) * (1 + (i % 7) / 100) }, { t: now - i * 36e5, p: (px[sym] || 100) * (1 - (i % 5) / 100) }], color: '#2962FF', width: 1 })
  drawings.BTCUSDT = Array.from({ length: 500 }, (_, i) => mk('BTCUSDT', i))
  for (const s of syms.slice(1, 60)) drawings[s] = Array.from({ length: 20 }, (_, i) => mk(s, i))
  const cells = ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'XAUUSDT', 'BNBUSDT', 'XRPUSDT', 'DOGEUSDT', 'NVDAUSDT', 'ADAUSDT', 'LINKUSDT', 'AVAXUSDT', 'SUIUSDT', 'XAGUSDT', 'TSLAUSDT', 'LTCUSDT', 'TRXUSDT'].map(symbol => ({ symbol, iv: '1h' }))
  return {
    theme: 'light', skin: 'sage', updown: 'green-up', greenUpMigrated: true, route: 'gateway', routePicked: true,
    layout: '16', cells, active: 0, pinned: ['1m', '5m', '15m', '1h', '4h', '1d', '1w'], panel: 'watch', watchTab: 'crypto',
    watch: { crypto: syms, us: ['NVDAUSDT', 'TSLAUSDT'], com: ['XAUUSDT', 'XAGUSDT'] },
    ind: { ma: true, ema: true, boll: true, vol: true, subs: ['macd', 'rsi', 'kdj'] }, params: null,
    drawings, alerts: [], notes: [], slots: { ladder: false, drawer: false, widgets: ['watch', 'detail'] }, linkCross: true,
  }
}
export async function heavyM(nFav = 300) {
  const px = await realPrices()
  const syms = Object.keys(px).filter(s => /USDT$/.test(s)).slice(0, nFav)
  const now = Date.now()
  const d = {}
  const kinds = ['hline', 'trend', 'rectangle']
  for (const s of syms.slice(0, 40)) d[`binance/usd_m/${s}`] = Array.from({ length: 50 }, (_, i) => { const k = kinds[i % 3]; const a = { t: now - (i + 10) * 36e5, p: (px[s] || 100) * 1.01 }, b = { t: now - i * 36e5, p: (px[s] || 100) * 0.99 }; return { id: `m${s}${i}`, kind: k, points: k === 'hline' ? [a] : [a, b], color: { value: '#2962FF' }, lineWidth: 1, dash: 'solid', filled: false, locked: false, hidden: false, levels: [] } })
  return {
    store: { page: 'chart', symbol: 'BTCUSDT', scroll: {}, symbols: { favorites: syms, recents: syms.slice(0, 10), groups: [], groupForSymbol: {}, seeded: true }, alerts: [], routePicked: true, route: 'gateway', greenUpMigrated: true },
    drawings: { v: 3, preferences: {}, d },
  }
}

export const seed = (kv) => {
  if (sessionStorage.getItem('f-seeded')) return
  sessionStorage.setItem('f-seeded', '1')
  localStorage.clear()
  for (const [k, v] of Object.entries(kv)) localStorage.setItem(k, v)
}

/** 本机预览（http://localhost）下网关线路的 REST 直接打线上域名，线上只对同源放行、不回 CORS 头；
 *  这里替页面转一手并补上 CORS 头（线上同源部署不经过这一步），否则网关线路的品种表、持仓额全是 Failed to fetch */
//  local = true（长会话 / 大数据段）：全市场表三张（exchangeInfo、24hr、premiumIndex）整场只向线上取一次、之后用缓存，
//  持仓额与 futures/data/* 的慢数给合成值——几百次切换不往线上网关打几百个 REST（gateway-is-production：只读、轻量）
const restCache = new Map()
const SYNTH = u => {
  if (/\/openInterest\?/.test(u)) return { symbol: new URL(u).searchParams.get('symbol'), openInterest: '12345.6', time: Date.now() }
  if (/\/futures\/data\//.test(u)) { const now = Date.now(); return Array.from({ length: 30 }, (_, i) => ({ symbol: new URL(u).searchParams.get('symbol'), timestamp: now - (30 - i) * 3e5, sumOpenInterest: '1000', sumOpenInterestValue: '1000000', longShortRatio: '1.1', longAccount: '0.52', shortAccount: '0.48', buySellRatio: '1.0', buyVol: '10', sellVol: '10' })) }
  return null
}
export async function corsShim(ctx, { local = false } = {}) {
  await ctx.route(/^https:\/\/kanpan\.43-160-232-253\.sslip\.io\/v1\//, async route => {
    const q = route.request()
    const cors = { 'access-control-allow-origin': q.headers().origin || '*', 'access-control-allow-credentials': 'true', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'GET,POST,PUT,DELETE,OPTIONS' }
    if (q.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors }).catch(() => {})
    if (local && q.method() === 'GET' && /\/v1\/market\/raw\//.test(q.url())) {
      const u = q.url(), syn = SYNTH(u)
      if (syn) return route.fulfill({ status: 200, contentType: 'application/json', headers: cors, body: JSON.stringify(syn) }).catch(() => {})
      const key = /exchangeInfo|ticker\/24hr|premiumIndex\?source|ticker\/price/.test(u) ? u.replace(/\?.*/, '') : u
      if (!restCache.has(key)) { try { const r = await route.fetch({ timeout: 20000 }); if (r.ok()) restCache.set(key, { body: await r.body(), ct: r.headers()['content-type'] || 'application/json' }); else return route.fulfill({ response: r, headers: { ...r.headers(), ...cors } }) } catch { return route.abort().catch(() => {}) } }
      const c = restCache.get(key)
      return route.fulfill({ status: 200, contentType: c.ct, headers: cors, body: c.body }).catch(() => {})
    }
    try { const r = await route.fetch({ timeout: 20000 }); await route.fulfill({ response: r, headers: { ...r.headers(), ...cors } }) } catch { await route.abort().catch(() => {}) }
  })
}

export async function newCtx(browser, opt, kv, mock = {}) {
  const ctx = await browser.newContext(opt)
  await corsShim(ctx, { local: !!mock.local })
  await ctx.addInitScript(INSTR)
  if (kv) await ctx.addInitScript(seed, kv)
  const count = { n: 0 }
  await mockKlines(ctx, { count, ...mock, local: undefined })
  return { ctx, count }
}

