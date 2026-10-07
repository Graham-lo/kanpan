// Hkline Web · 2026-10-07 压测与回归（§50）浏览器段共用件
//   打线上 /web/（与本仓库构建同一份包）或本机 vite preview（P_URL=…）；真 K 线（直连币安），服务端历史接口同源。
//   一次只开一个无头 Chrome。截图写到 docs/acceptance/压测-2026-10-07/，逐项结果写 logs/<段>.json。
import fs from 'node:fs'
import { fileURLToPath } from 'node:url'
import { launch, INSTR, metrics, snapF, sleep, pct, med, corsShim } from './f-lib.mjs'
export { sleep, pct, med, metrics, snapF }

export const URL_ = process.env.P_URL || 'https://kanpan.43-160-232-253.sslip.io/web/'
export const OUT = fileURLToPath(new URL('../../docs/acceptance/压测-2026-10-07/', import.meta.url))
fs.mkdirSync(OUT + 'logs', { recursive: true })
export const KEY = 'hkline-web-v1'
export const PCV = { viewport: { width: 2560, height: 1440 }, deviceScaleFactor: 1, locale: 'zh-CN', timezoneId: 'Asia/Shanghai' }
export const BASE = {
  theme: 'light', skin: 'sage', updown: 'green-up', greenUpMigrated: true, route: 'direct', routePicked: true, panel: 'watch', active: 0,
  drawings: {}, alerts: [], notes: [], orderFlow: false, linkCross: true,
  ind: { ma: true, ema: false, boll: false, vol: true, subs: ['macd'] },
}

export const R = []
export const DATA = {}
let tag = 'p1007'
export const setTag = t => { tag = t }
export const ok = (id, name, pass, info = '') => { R.push({ id, name, pass: !!pass, info }); console.log(`${pass ? '✓' : '✗'} [${id}] ${name}${info ? '  — ' + info : ''}`) }
export const note = (id, name, info = '') => { R.push({ id, name, pass: null, info }); console.log(`· [${id}] ${name}${info ? '  — ' + info : ''}`) }
export const flush = () => fs.writeFileSync(`${OUT}logs/${tag}${/localhost/.test(URL_) ? "-local" : ""}.json`, JSON.stringify({ at: new Date().toISOString(), url: URL_, results: R, data: DATA }, null, 1))
export const shot = (page, name) => page.screenshot({ path: `${OUT}${name}.png` })

let browser
export async function browserUp() { browser ||= await launch(); return browser }
export async function browserDown() { await browser?.close(); browser = null }

/** 开一页：注入探针、种状态（只在这个标签页第一次加载时种，刷新不重种）；记下所有 /v1/ 业务请求（并发峰值、状态码、慢请求） */
export async function open(state, { opt = PCV, q = '#chart' } = {}) {
  const b = await browserUp()
  const ctx = await b.newContext({ ...opt, acceptDownloads: true })
  if (/^http:\/\/localhost/.test(URL_)) await corsShim(ctx) // 本机预览：服务端接口替页面转一手补 CORS 头（线上同源不经过）
  await ctx.addInitScript(INSTR)
  await ctx.addInitScript(([k, v]) => { if (!sessionStorage.getItem('p-seeded')) { sessionStorage.setItem('p-seeded', '1'); localStorage.clear(); localStorage.setItem(k, v) } }, [KEY, JSON.stringify(state)])
  const page = await ctx.newPage()
  const errs = [], api = { inflight: 0, max: 0, n: 0, byStatus: {}, byPath: {}, slow: [] }
  const t0 = new Map()
  const isApi = u => /\/v1\//.test(u) && !/\/v1\/market\/raw\//.test(u)
  page.on('pageerror', e => errs.push('pageerror ' + String(e).slice(0, 240)))
  page.on('console', m => { if (m.type() === 'error' && !/Failed to load resource|WebSocket connection|ERR_/.test(m.text())) errs.push(m.text().slice(0, 240)) })
  page.on('request', r => {
    if (!isApi(r.url())) return
    api.n++; api.inflight++; api.max = Math.max(api.max, api.inflight); t0.set(r, Date.now())
    const u = new URL(r.url()), p = u.pathname; api.byPath[p] = (api.byPath[p] || 0) + 1
    // 币安 K 线按 limit 分档记权重（limit.ts 同口径：<100→1，<500→2，≤1000→5，其余 10）
    if (p === '/fapi/v1/klines') { const l = +(u.searchParams.get('limit') || 500), w = l < 100 ? 1 : l < 500 ? 2 : l <= 1000 ? 5 : 10; api.kw ||= { n: 0, w: 0, byW: {} }; api.kw.n++; api.kw.w += w; api.kw.byW[w] = (api.kw.byW[w] || 0) + 1 }
  })
  const done = async r => {
    if (!t0.has(r)) return
    api.inflight--; const ms = Date.now() - t0.get(r); t0.delete(r)
    let s = 'fail'; try { s = (await r.response())?.status() ?? 'fail' } catch { /* 无 */ }
    api.byStatus[s] = (api.byStatus[s] || 0) + 1
    if (ms > 3000) api.slow.push([new URL(r.url()).pathname, ms, s])
  }
  page.on('requestfinished', done); page.on('requestfailed', done)
  const cdp = await ctx.newCDPSession(page); await cdp.send('Performance.enable')
  await page.goto(URL_ + q, { waitUntil: 'domcontentloaded' })
  return { ctx, page, cdp, errs, api }
}
export const cellsOf = page => page.evaluate(() => window.__cells?.() || [])
export const stateOf = page => page.evaluate(k => JSON.parse(localStorage.getItem(k) || '{}'), KEY)
export async function waitCells(page, n, min = 1, ms = 45000) {
  // 换了品种 / 周期的格子在新 K 线到之前还挂着旧的那份：要图上装的就是配置里的那只那个周期（metaSym / metaIv）才算到位
  return page.waitForFunction(([n, min]) => {
    const IV = { '1s': 1e3, '5s': 5e3, '15s': 15e3, '1m': 6e4, '3m': 18e4, '5m': 3e5, '15m': 9e5, '30m': 18e5, '1h': 36e5, '2h': 72e5, '4h': 144e5, '6h': 216e5, '8h': 288e5, '12h': 432e5, '1d': 864e5, '1w': 6048e5 }
    const c = window.__cells?.()
    return c && c.length === n && c.every(x => x.bars >= min && !x.empty && x.metaSym === x.symbol && (IV[x.iv] == null || x.metaIv === IV[x.iv]))
  }, [n, min], { timeout: ms, polling: 50 }).then(() => true, () => false)
}
/** 起一个页内计时：每格第一次「装的就是配置里那只那个周期」是在第几毫秒（布局切换时看哪一格拖后腿） */
export async function armReady(page) {
  await page.evaluate(() => {
    const IV = { '1s': 1e3, '5s': 5e3, '15s': 15e3, '1m': 6e4, '3m': 18e4, '5m': 3e5, '15m': 9e5, '30m': 18e5, '1h': 36e5, '2h': 72e5, '4h': 144e5, '6h': 216e5, '8h': 288e5, '12h': 432e5, '1d': 864e5, '1w': 6048e5 }
    const t0 = performance.now(), seen = {}
    window.__ready = new Promise(res => {
      const go = () => {
        const cs = window.__cells()
        cs.forEach((x, i) => { if (seen[i] == null && x.bars && !x.empty && x.metaSym === x.symbol && (IV[x.iv] == null || x.metaIv === IV[x.iv])) seen[i] = Math.round(performance.now() - t0) })
        if (performance.now() - t0 > 60000) return res(seen)
        if (Object.keys(seen).length >= cs.length && performance.now() - t0 > 200) return res(seen)
        requestAnimationFrame(go)
      }
      requestAnimationFrame(go)
    })
  })
}
export const hostRects = page => page.evaluate(() => [...document.querySelectorAll('.chart-cell .canvas-host')].map(e => { const r = e.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height } }))
export const LAB = { '1': '一图', '2': '左右两图', '2v': '上下两图', '3': '左一右二', '4': '四图', '6': '六图（三列两行）', '8': '八图（四列两行）', '9': '九图（三列三行）', '12': '十二图（四列三行）', '16': '十六图（四列四行）' }
/** 页内点布局菜单（Playwright locator.click 会留元素句柄，看起来像节点泄漏——layout16-review 的结论） */
export async function pickLayout(page, k) {
  await page.evaluate(l => {
    document.querySelector('#tbLayout').click()
    const b = [...document.querySelectorAll('.menu .mi')].find(x => x.querySelector('.label')?.textContent.trim() === l)
    if (!b) throw new Error('菜单里没有 ' + l)
    b.click()
  }, LAB[k])
}
/** CDP 主线程累计时长（秒） */
export async function td(cdp) { return (await cdp.send('Performance.getMetrics')).metrics.find(m => m.name === 'TaskDuration').value }
/** 一段操作里的帧间隔（页内 rAF）、主线程占用（TaskDuration / 墙钟）、长任务 */
export async function frames(page, cdp, fn) {
  await page.evaluate(() => { window.__f.lt.length = 0; window.__f.startFrames() })
  const a = await td(cdp), w = Date.now()
  await fn()
  const b = await td(cdp), wall = (Date.now() - w) / 1000
  const fr = await page.evaluate(() => window.__f.stopFrames())
  const lt = await page.evaluate(() => window.__f.lt.slice())
  return {
    wall: +wall.toFixed(1), cpu: +((b - a) / wall * 100).toFixed(1), p50: +pct(fr, 0.5).toFixed(1), p95: +pct(fr, 0.95).toFixed(1), p99: +pct(fr, 0.99).toFixed(1),
    max: +Math.max(0, ...fr).toFixed(1), n: fr.length, over33: fr.filter(x => x > 33.4).length, lt: lt.length, ltMax: lt.length ? Math.max(...lt) : 0,
  }
}
export const sh = t => new Date(t + 8 * 36e5).toISOString().slice(0, 16).replace('T', ' ')
/** 币安现价（REST 直连） */
export async function binancePx(symbol) {
  const r = await fetch(`https://fapi.binance.com/fapi/v1/ticker/price?symbol=${symbol}`, { signal: AbortSignal.timeout(8000) })
  return +(await r.json()).price
}
/** 第 i 格回放：点底栏「回放」→ 输入起点 → 回车；speed 档、开始播 */
export async function startReplay(page, i, at, speed = 4) {
  await page.evaluate(i => document.querySelectorAll('.chart-cell')[i].querySelector('.cell-foot [data-act="replay"]').click(), i)
  const inp = page.locator('.chart-cell').nth(i).locator('.rp-bar input[data-rp="start"]')
  await inp.fill(sh(at)); await inp.press('Enter')
  await page.waitForFunction(() => !!window.__replay?.(), null, { timeout: 20000 })
  await sleep(800)
  await page.evaluate(([i, v]) => {
    const bar = document.querySelectorAll('.chart-cell')[i].querySelector('.rp-bar')
    bar.querySelector(`[data-rp="speed"][data-v="${v}"]`)?.click()
    if (!window.__replay().playing) bar.querySelector('[data-rp="toggle"]').click()
  }, [i, speed])
  await sleep(300)
  return page.evaluate(() => window.__replay())
}
