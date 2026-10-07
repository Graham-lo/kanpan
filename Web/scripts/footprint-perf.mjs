// Hkline Web · 足迹图画一帧的耗时（2026-10-07）
//   node scripts/footprint-perf.mjs [轮数=3]
// 自己起一个 vite preview（dist 要先 build），量完关掉。本机 Chrome 无头、2560×1440、DPR 1。
// K 线与足迹历史都用合成数据：BTC 1m，每分钟约 20 个价位格；一屏摆 300 根（横条模式），再放到最宽（写数字模式）各量一次。
// 量法：页面里 __fpBench 连着整帧 render() 若干次，回整帧与其中足迹那一段的中位 / P95 毫秒。
import { chromium } from 'playwright-core'
import { spawn } from 'node:child_process'

const ROUNDS = +(process.argv[2] || 3)
const PORT = 5293
const URL_ = `http://localhost:${PORT}/web/`
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const M = 60e3, TOTAL = 1500

const srv = spawn(new URL('../node_modules/.bin/vite', import.meta.url).pathname, ['preview', '--port', String(PORT), '--strictPort'], { cwd: new URL('..', import.meta.url).pathname, stdio: ['ignore', 'pipe', 'pipe'] })
await new Promise((res, rej) => { srv.stdout.on('data', d => { if (/localhost:/.test(String(d))) res() }); srv.on('exit', c => rej(new Error('preview 退出 ' + c))); setTimeout(() => rej(new Error('preview 起不来')), 20000) })
const browser = await chromium.launch({ executablePath: CHROME, headless: true })
const stop = () => { try { srv.kill('SIGTERM') } catch { /* 已退 */ } }
process.on('exit', stop)
process.on('uncaughtException', e => { console.error(e); stop(); process.exit(1) })

// 先拿一次现价：最新一根会被实时推送改成真价，合成数据要落在它附近，否则纵轴被撑得很大
let PRICE = 0
{
  const c0 = await browser.newContext()
  await c0.addInitScript(() => { localStorage.setItem('hkline-web-v1', JSON.stringify({ route: 'direct', routePicked: true, greenUpMigrated: true })) })
  const p0 = await c0.newPage()
  await p0.goto(URL_ + '?s=BTCUSDT&i=1m#chart')
  await p0.waitForFunction(() => window.__cells?.()[0]?.last > 0, null, { timeout: 30000 })
  PRICE = await p0.evaluate(() => window.__cells()[0].last)
  await c0.close()
}
const now = Date.now(), t0 = Math.floor(now / M) * M, first = t0 - (TOTAL - 1) * M
const bar = t => {
  const k = (t0 - t) / M, f = x => PRICE * (1 + 0.004 * Math.sin(x / 37) + 0.002 * Math.sin(x / 5.3))
  const c = f(k), o = f(k + 1), h = Math.max(o, c) * 1.0006, l = Math.min(o, c) * 0.9994
  return { o, h, l, c, v: 40 + 30 * Math.abs(Math.sin(k / 3)) }
}
// 足迹步长：让中位高低差约 20 格
const ranges = Array.from({ length: 300 }, (_, k) => { const b = bar(t0 - k * M); return b.h - b.l }).sort((a, b) => a - b)
const STEP = Math.max(1, Math.round(ranges[150] / 20))

const ctx = await browser.newContext({ viewport: { width: 2560, height: 1440 }, deviceScaleFactor: 1 })
await ctx.route(/fapi\.binance\.com\/fapi\/v1\/klines/, route => {
  const u = new URL(route.request().url()), lim = +u.searchParams.get('limit') || 500, end = u.searchParams.get('endTime')
  let hi = end ? Math.floor(+end / M) * M : t0
  if (hi > t0) hi = t0
  const rows = []
  for (let t = Math.max(first, hi - (lim - 1) * M); t <= hi; t += M) {
    const { o, h, l, c, v } = bar(t)
    rows.push([t, String(o), String(h), String(l), String(c), String(v), t + M - 1, String(v * c), 500, String(v * 0.5), String(v * c * 0.52), '0'])
  }
  route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(rows) })
})
let footHits = 0
await ctx.route(/\/v1\/market\/orderflow\/footprint/, route => {
  footHits++
  const u = new URL(route.request().url()), from = +u.searchParams.get('from'), to = +u.searchParams.get('to')
  const minutes = []
  for (let t = Math.ceil(from / M) * M; t < to; t += M) {
    if (t < first || t > t0) continue
    const { h, l } = bar(t), rows = []
    for (let p = Math.floor(l / STEP) * STEP; p <= h; p += STEP) {
      const x = Math.abs(Math.sin(p / 97 + t / 7e5))
      rows.push([p, Math.round(20_000 + 400_000 * x), Math.round(20_000 + 400_000 * (1 - x))])
    }
    minutes.push({ t, rows })
  }
  route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ symbol: 'BTCUSDT', step: STEP, minutes }) })
})
await ctx.addInitScript(() => {
  if (sessionStorage.getItem('seeded')) return
  localStorage.setItem('hkline-web-v1', JSON.stringify({ layout: '1', cells: [{ symbol: 'BTCUSDT', iv: '1m' }], active: 0, greenUpMigrated: true, panel: null, route: 'direct', routePicked: true,
    ind: { ma: true, ema: false, boll: false, vol: true, vwap: false, subs: ['macd', 'rsi'] } }))
  localStorage.setItem('hkline-web-footprint', '[0]')
  sessionStorage.setItem('seeded', '1')
})
const pg = await ctx.newPage()
await pg.goto(URL_ + '#chart')
await pg.waitForFunction(() => window.__cells?.()[0]?.bars > 300, null, { timeout: 30000 })
const res = { bar: [], num: [] }
for (let r = 0; r < ROUNDS; r++) {
  await pg.evaluate(() => window.__fpBench(0, 5, 300))
  await pg.waitForFunction(() => window.__footprint(0)?.drawn > 250, null, { timeout: 20000 })
  res.bar.push(await pg.evaluate(() => window.__fpBench(0, 120, 300)))
  await pg.evaluate(() => window.__fpBench(0, 5, 36))
  await pg.waitForTimeout(400)
  res.num.push(await pg.evaluate(() => window.__fpBench(0, 120, 36)))
}
const med = a => { const s = [...a].sort((x, y) => x - y); return s[Math.floor((s.length - 1) / 2)] }
for (const [k, list] of Object.entries(res)) {
  const s = list[0].stat
  console.log(`${k === 'bar' ? '一屏 300 根（横条）' : '放到最宽（写数字）'}：画了 ${s.drawn} 根、${s.rows} 个格、桶 ${s.d}（步长 ${s.step}，中位高低差 ${s.med?.toFixed(1)}，每价位 ${s.ppp?.toFixed(3)} 像素）、模式 ${s.mode}`)
  console.log('  整帧 render 中位 ms', list.map(x => x.frameMed.toFixed(2)).join(' / '), '→', med(list.map(x => x.frameMed)).toFixed(2),
    '| P95', med(list.map(x => x.frameP95)).toFixed(2), '| 其中足迹中位', med(list.map(x => x.footprintMed)).toFixed(2))
}
console.log('足迹历史请求', footHits, '次')
await browser.close()
stop()
