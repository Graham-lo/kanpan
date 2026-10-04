// Hkline Web · PC 画线撤销基准回归（2026-10-05 深度审查 A 线）
//   npx vite build && node scripts/a-drawing-undo.mjs
// 自己起 vite preview、量完关掉。K 线用合成数据、WebSocket 换成不连的空壳（画线落点不受实时行情影响）。
//   1. 刷新后（画线从本机存档装回来）新画一条再 ⌘Z：只撤掉新画的那条，原来的几条都在
//      （撤销基准没记时第一次改动拿「[]」当改之前的样子，⌘Z 把这只品种的画线整份清空）
//   2. 画一条 → 工具栏「锁定全部」→ 再画一条 → ⌘Z：撤掉第二条，锁照旧（锁前的样子不能被当成撤销点退回去）
import { chromium } from 'playwright-core'
import { spawn } from 'node:child_process'

const PORT = 5292
const URL_ = `http://localhost:${PORT}/web/`
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const srv = spawn(new URL('../node_modules/.bin/vite', import.meta.url).pathname, ['preview', '--port', String(PORT), '--strictPort'], { cwd: new URL('..', import.meta.url).pathname, stdio: ['ignore', 'pipe', 'pipe'] })
const stop = () => { try { srv.kill('SIGTERM') } catch { /* 已退 */ } }
process.on('exit', stop)
await new Promise((res, rej) => { srv.stdout.on('data', d => { if (/localhost:/.test(String(d))) res() }); srv.on('exit', c => rej(new Error('preview 退出 ' + c))); setTimeout(() => rej(new Error('preview 起不来')), 20000) })
const browser = await chromium.launch({ executablePath: CHROME, headless: true })
let fails = 0
const ok = (name, pass, info = '') => { if (!pass) fails++; console.log(`${pass ? '✓' : '✗'} ${name}${info ? '  ' + info : ''}`) }

const PRICE = 60000, M = 60e3, NOW = Math.floor(Date.now() / M) * M
const seed = { layout: '1', cells: [{ symbol: 'BTCUSDT', iv: '1m' }], active: 0, greenUpMigrated: true, panel: null, route: 'direct', routePicked: true,
  ind: { ma: false, ema: false, boll: false, vol: false, subs: [] },
  drawings: { BTCUSDT: [0, 1, 2].map(k => ({ id: 'seed' + k, type: 'hline', pts: [{ t: NOW - 50 * M, p: PRICE * (1 + (k - 1) * 0.002) }], color: '#2962FF', width: 2 })) } }

async function open() {
  const ctx = await browser.newContext({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 1 })
  await ctx.addInitScript(s => {
    if (!sessionStorage.getItem('seeded')) { localStorage.setItem('hkline-web-v1', s); sessionStorage.setItem('seeded', '1') }
    window.WebSocket = class { constructor() { this.readyState = 0 } send() {} close() {} addEventListener() {} removeEventListener() {} }
  }, JSON.stringify(seed))
  await ctx.route(/\/fapi\/v1\/klines/, route => {
    const u = new URL(route.request().url()), lim = +u.searchParams.get('limit') || 500, end = u.searchParams.get('endTime')
    const hi = Math.min(NOW, end ? Math.floor(+end / M) * M : NOW), rows = []
    for (let t = hi - (lim - 1) * M; t <= hi; t += M) {
      const k = (NOW - t) / M, c = PRICE * (1 + 0.004 * Math.sin(k / 37)), o = PRICE * (1 + 0.004 * Math.sin((k + 1) / 37))
      rows.push([t, String(o), String(Math.max(o, c) * 1.0005), String(Math.min(o, c) * 0.9995), String(c), '50', t + M - 1, String(50 * c), 500, '25', String(25 * c), '0'])
    }
    route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(rows) })
  })
  const pg = await ctx.newPage()
  await pg.goto(URL_ + '#chart')
  await pg.waitForFunction(() => window.__cells?.()[0]?.bars > 0, null, { timeout: 30000 })
  await pg.waitForTimeout(400)
  return { ctx, pg }
}
const drawings = pg => pg.evaluate(() => JSON.parse(localStorage.getItem('hkline-web-v1') || '{}').drawings?.BTCUSDT || [])
async function hlineAt(pg, fy) {
  const b = await pg.locator('.chart-cell canvas').first().boundingBox()
  const direct = pg.locator('#drawbar [data-tool="hline"]')
  if (await direct.count()) await direct.click()
  else {
    const [gid, k] = await pg.evaluate(() => {
      const b = [...document.querySelectorAll('#drawbar [data-tools]')].find(x => x.dataset.tools.split(' ').includes('hline'))
      return [b?.closest('.tool-grp')?.dataset.grp, b ? b.dataset.tools.split(' ').indexOf('hline') : -1]
    })
    await pg.click(`#drawbar [data-fly="${gid}"]`); await pg.waitForTimeout(250)
    await pg.locator('.menu .mi').nth(k).click()
  }
  await pg.waitForTimeout(150)
  await pg.mouse.click(b.x + b.width * 0.4, b.y + b.height * fy); await pg.waitForTimeout(300)
  await pg.keyboard.press('Escape'); await pg.waitForTimeout(100)
}

try {
  {
    const { ctx, pg } = await open()
    const n0 = (await drawings(pg)).length
    await hlineAt(pg, 0.3)
    const n1 = (await drawings(pg)).length
    await pg.keyboard.press('Meta+z'); await pg.waitForTimeout(400)
    const after = await drawings(pg)
    ok('刷新后新画一条再 ⌘Z：只撤掉新画的那条', n1 === n0 + 1 && after.length === n0 && after.every(d => d.id.startsWith('seed')), `${n0} → ${n1} → ${after.length}`)
    await ctx.close()
  }
  {
    const { ctx, pg } = await open()
    await hlineAt(pg, 0.3)
    await pg.locator('#drawbar [data-dact="lock"]').click(); await pg.waitForTimeout(200)
    const locked = await drawings(pg)
    await hlineAt(pg, 0.6)
    const n2 = (await drawings(pg)).length
    await pg.keyboard.press('Meta+z'); await pg.waitForTimeout(400)
    const after = await drawings(pg)
    ok('锁定全部后再画一条、⌘Z：撤掉第二条，锁照旧', locked.every(d => d.locked) && n2 === locked.length + 1 && after.length === locked.length && after.every(d => d.locked),
      `锁后 ${locked.length} 条全锁=${locked.every(d => d.locked)}；再画 ${n2}；撤销后 ${after.length} 条、全锁=${after.every(d => d.locked)}`)
    await ctx.close()
  }
} finally {
  await browser.close(); stop()
}
process.exit(fails ? 1 : 0)
