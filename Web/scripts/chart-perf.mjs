// Hkline Web · PC 图表引擎性能量法（2026-10-05 深度审查 A 线）
//   node scripts/chart-perf.mjs [轮数=3]
// 自己起一个 vite preview（dist 要先 build），量完关掉，不留后台进程。本机 Chrome 无头、2560×1440、DPR 1。
//   冷启：每轮新开上下文（无缓存），从开始导航到第一格画出 K 线（__cells()[0].bars > 0 之后的那一帧）的毫秒
//   满载：BTC 1m、往左拖到 ≥ 6000 根、30 条画线、三个副图（MACD / RSI / 累计量差）+ 均线 + 成交量 + VWAP，
//         依次做十字线扫动 / 拖动平移 / 滚轮缩放三段，每段量主线程长任务（≥ 50 ms）条数、最长、总阻塞（各条超 50 ms 的部分之和）
//         与主线程占用（CDP TaskDuration 增量 ÷ 墙钟）。不量 fps。
import { chromium } from 'playwright-core'
import { spawn } from 'node:child_process'

const ROUNDS = +(process.argv[2] || 3)
const PORT = 5291
const URL_ = `http://localhost:${PORT}/web/`
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'

const srv = spawn(new URL('../node_modules/.bin/vite', import.meta.url).pathname, [ 'preview', '--port', String(PORT), '--strictPort'], { cwd: new URL('..', import.meta.url).pathname, stdio: ['ignore', 'pipe', 'pipe'] })
await new Promise((res, rej) => { srv.stdout.on('data', d => { if (/localhost:/.test(String(d))) res() }); srv.on('exit', c => rej(new Error('preview 退出 ' + c))); setTimeout(() => rej(new Error('preview 起不来')), 20000) })
const browser = await chromium.launch({ executablePath: CHROME, headless: true })
const stop = () => { try { srv.kill('SIGTERM') } catch { /* 已退 */ } }
process.on('exit', stop)
process.on('uncaughtException', e => { console.error(e); stop(); process.exit(1) })
const TOTAL = 6000
const med = a => { const s = [...a].sort((x, y) => x - y); return s.length ? s[Math.floor((s.length - 1) / 2)] : NaN }
const probe = () => {
  window.__lt = []
  try { new PerformanceObserver(l => { for (const e of l.getEntries()) window.__lt.push(e.duration) }).observe({ type: 'longtask', buffered: true }) } catch { /* 无 */ }
  const look = () => {
    try { const c = window.__cells?.(); if (c && c[0] && c[0].bars > 0) { requestAnimationFrame(() => { window.__first = performance.now() }); return } } catch { /* 还没好 */ }
    requestAnimationFrame(look)
  }
  requestAnimationFrame(look)
}
function state(price, now) {
  const m = 60e3, t0 = Math.floor(now / m) * m
  const types = ['trend', 'ray', 'hline', 'vline', 'rect', 'fib', 'avwap', 'fvp', 'position', 'trend']
  const drawings = Array.from({ length: 30 }, (_, k) => {
    const type = types[k % types.length], a = t0 - (40 + k * 37) * m, b = a + 25 * m
    const p0 = price * (1 - 0.004 + k * 0.0003), p1 = price * (1 + 0.003 - k * 0.0002)
    const pts = type === 'position' ? [{ t: a, p: p0 }, { t: b, p: p0 * 1.004 }, { t: b, p: p0 * 0.996 }] : ['hline', 'vline', 'avwap'].includes(type) ? [{ t: a, p: p0 }] : [{ t: a, p: p0 }, { t: b, p: p1 }]
    return { id: 'perf' + k, type, pts, color: '#2962FF', width: 2 }
  })
  return { layout: '1', cells: [{ symbol: 'BTCUSDT', iv: '1m' }], active: 0, greenUpMigrated: true, panel: null, route: 'direct', routePicked: true,
    ind: { ma: true, ema: false, boll: false, vol: true, vwap: true, subs: ['macd', 'rsi', 'cvd'] }, drawings: { BTCUSDT: drawings } }
}
async function ctxWith(st) {
  const ctx = await browser.newContext({ viewport: { width: 2560, height: 1440 }, deviceScaleFactor: 1 })
  await ctx.addInitScript(probe)
  // K 线 REST 用合成数据（往前正好 TOTAL 根），量出来的数不受当时网络、限流、行情冷热影响；WebSocket 照走线上
  if (price > 0) await ctx.route(/fapi\.binance\.com\/fapi\/v1\/klines/, route => {
    const u = new URL(route.request().url()), lim = +u.searchParams.get('limit') || 500, end = u.searchParams.get('endTime')
    const m = 60e3, t0 = Math.floor(now / m) * m, first = t0 - (TOTAL - 1) * m
    let hi = end ? Math.floor(+end / m) * m : t0
    if (hi > t0) hi = t0
    const rows = []
    for (let t = Math.max(first, hi - (lim - 1) * m); t <= hi; t += m) {
      const k = (t0 - t) / m, c = price * (1 + 0.004 * Math.sin(k / 37) + 0.002 * Math.sin(k / 5.3)), o = price * (1 + 0.004 * Math.sin((k + 1) / 37) + 0.002 * Math.sin((k + 1) / 5.3))
      const h = Math.max(o, c) * 1.0006, l = Math.min(o, c) * 0.9994, v = 40 + 30 * Math.abs(Math.sin(k / 3))
      rows.push([t, String(o), String(h), String(l), String(c), String(v), t + m - 1, String(v * c), 500, String(v * 0.5), String(v * c * 0.52), '0'])
    }
    route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(rows) })
  })
  if (st) await ctx.addInitScript(s => { if (!sessionStorage.getItem('seeded')) { localStorage.setItem('hkline-web-v1', s); sessionStorage.setItem('seeded', '1') } }, JSON.stringify(st))
  return ctx
}
// 先拿一次现价（画线要落在价位附近）
let price = 0, now = Date.now()
{
  const ctx = await ctxWith({ route: 'direct', routePicked: true, greenUpMigrated: true }), pg = await ctx.newPage()
  await pg.goto(URL_ + '?s=BTCUSDT&i=1m#chart')
  await pg.waitForFunction(() => window.__cells?.()[0]?.last > 0, null, { timeout: 30000 })
  price = await pg.evaluate(() => window.__cells()[0].last); now = await pg.evaluate(() => Date.now())
  await ctx.close()
}
const cold = []
for (let r = 0; r < ROUNDS; r++) {
  const ctx = await ctxWith(state(price, now)), pg = await ctx.newPage()
  await pg.goto(URL_ + '#chart')
  await pg.waitForFunction(() => window.__first != null, null, { timeout: 30000 })
  cold.push(await pg.evaluate(() => window.__first))
  await ctx.close()
}
console.log('冷启到出 K 线（ms）', cold.map(x => Math.round(x)).join(' / '), '中位', Math.round(med(cold)))

const runs = { cross: [], pan: [], zoom: [] }
for (let r = 0; r < ROUNDS; r++) {
  const ctx = await ctxWith(state(price, now)), pg = await ctx.newPage()
  const cdp = await ctx.newCDPSession(pg)
  await cdp.send('Performance.enable')
  await pg.goto(URL_ + '#chart')
  await pg.waitForFunction(() => window.__first != null, null, { timeout: 30000 })
  await pg.waitForTimeout(1500)
  const box = await pg.locator('.canvas-host canvas').first().boundingBox()
  const cx = box.x + box.width * 0.5, cy = box.y + box.height * 0.3
  // 往左拖到 6000 根全进来
  for (let k = 0; k < 60; k++) {
    if ((await pg.evaluate(() => window.__cells()[0].bars)) >= TOTAL) break
    await pg.mouse.move(box.x + 300, cy); await pg.mouse.down()
    for (let s = 1; s <= 20; s++) await pg.mouse.move(box.x + 300 + s * 80, cy)
    await pg.mouse.up(); await pg.waitForTimeout(700)
  }
  const bars = await pg.evaluate(() => window.__cells()[0].bars)
  // 缩到最小间距、看满一屏
  for (let k = 0; k < 30; k++) { await pg.mouse.move(cx, cy); await pg.mouse.wheel(0, 240) }
  await pg.waitForTimeout(800)
  const metric = async () => Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map(m => [m.name, m.value]))
  const phase = async (name, fn) => {
    await pg.evaluate(() => { window.__lt = [] })
    const prof = process.env.PROFILE === name && r === 0
    if (prof) { await cdp.send('Profiler.enable'); await cdp.send('Profiler.setSamplingInterval', { interval: 200 }); await cdp.send('Profiler.start') }
    const m0 = await metric(), w0 = Date.now()
    await fn()
    await pg.waitForTimeout(300)
    if (prof) {
      const { profile } = await cdp.send('Profiler.stop')
      const self = new Map(), byId = new Map(profile.nodes.map(n => [n.id, n]))
      const dt = profile.timeDeltas, total = dt.reduce((a, b) => a + b, 0)
      profile.samples.forEach((id, i) => { const n = byId.get(id), f = n.callFrame, k = `${f.functionName || '(anon)'} ${f.url.split('/').pop()}:${f.lineNumber + 1}`; self.set(k, (self.get(k) || 0) + (dt[i] || 0)) })
      console.log(`[${name}] 自身耗时前 25（总 ${(total / 1000).toFixed(0)} ms）`)
      ;[...self].sort((a, b) => b[1] - a[1]).slice(0, 25).forEach(([k, v]) => console.log(`  ${(v / 1000).toFixed(1)} ms  ${k}`))
    }
    const m1 = await metric(), wall = (Date.now() - w0) / 1000
    const lt = await pg.evaluate(() => window.__lt)
    runs[name].push({ n: lt.length, max: lt.length ? Math.max(...lt) : 0, tbt: lt.reduce((s, d) => s + Math.max(0, d - 50), 0), cpu: (m1.TaskDuration - m0.TaskDuration) / wall * 100, script: (m1.ScriptDuration - m0.ScriptDuration) / wall * 100, bars })
  }
  await phase('cross', async () => { for (let s = 0; s < 300; s++) { await pg.mouse.move(box.x + 100 + (s * 7) % (box.width - 300), box.y + 80 + (s * 13) % (box.height * 0.5)); await pg.waitForTimeout(8) } })
  await phase('pan', async () => {
    for (let k = 0; k < 4; k++) {
      await pg.mouse.move(cx - 600, cy); await pg.mouse.down()
      for (let s = 1; s <= 60; s++) { await pg.mouse.move(cx - 600 + s * 20 * (k % 2 ? -1 : 1) + (k % 2 ? 1200 : 0), cy + (s % 5)); await pg.waitForTimeout(8) }
      await pg.mouse.up()
    }
  })
  await phase('zoom', async () => { for (let s = 0; s < 120; s++) { await pg.mouse.move(cx, cy); await pg.mouse.wheel(0, s % 40 < 20 ? -120 : 120); await pg.waitForTimeout(12) } })
  await ctx.close()
}
for (const [k, list] of Object.entries(runs)) {
  const name = { cross: '十字线扫动', pan: '拖动平移', zoom: '滚轮缩放' }[k]
  console.log(`${name}（${list[0]?.bars} 根）`, list.map(x => `长任务 ${x.n} 条 最长 ${Math.round(x.max)} ms 阻塞 ${Math.round(x.tbt)} ms 主线程 ${x.cpu.toFixed(1)}%（脚本 ${x.script.toFixed(1)}%）`).join(' | '))
  console.log(`  中位：长任务 ${med(list.map(x => x.n))} 条、阻塞 ${Math.round(med(list.map(x => x.tbt)))} ms、主线程 ${med(list.map(x => x.cpu)).toFixed(1)}%、脚本 ${med(list.map(x => x.script)).toFixed(1)}%`)
}
await browser.close()
srv.kill('SIGTERM')
