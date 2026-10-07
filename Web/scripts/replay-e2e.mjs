// Hkline Web · K 线回放端到端验收（2026-10-07）：以交易员身份走一遍
//   BTCUSDT 15 分 → 底栏「回放」→ 竖线选约 3 天前的起点 → 4× 播放 → 中途画一条趋势线 → 切 1 小时 → 拖进度线 → 16× 量主线程 → 退出
//   另开两格的布局验「只有当前格回放，别的格照常实时」，以及秒级周期按钮置灰。
//   npx vite --port 5191 后 node scripts/replay-e2e.mjs [地址] [截图目录]
//   真 K 线（直连币安，本机走系统代理）；截图默认落 docs/acceptance/K线回放-2026-10-07/；有 ✗ 退出码 1
import { chromium } from 'playwright-core'
import { mkdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const URL_ = process.argv[2] || 'http://localhost:5191/web/'
const OUT = process.argv[3] || fileURLToPath(new URL('../../docs/acceptance/K线回放-2026-10-07/', import.meta.url))
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
mkdirSync(OUT, { recursive: true })
const sleep = ms => new Promise(r => setTimeout(r, ms))
let bad = 0
const fail = msg => { bad++; console.log('✗ ' + msg) }
const ok = msg => console.log('✓ ' + msg)
const check = (cond, msg) => cond ? ok(msg) : fail(msg)
const Q = 9e5, H = 36e5
const sh = t => { const d = new Date(t + 8 * H); return d.toISOString().slice(0, 16).replace('T', ' ') }

const browser = await chromium.launch({ executablePath: CHROME, headless: true })
async function open(st) {
  const ctx = await browser.newContext({ viewport: { width: 1600, height: 960 }, deviceScaleFactor: 2 })
  await ctx.addInitScript(s => { if (!sessionStorage.getItem('seeded')) { localStorage.setItem('hkline-web-v1', s); sessionStorage.setItem('seeded', '1') } }, JSON.stringify(st))
  const pg = await ctx.newPage()
  pg.on('pageerror', e => fail('页面报错：' + e.message))
  if (process.env.DEBUG) pg.on('console', m => console.log('  [console] ' + m.text().slice(0, 300)))
  await pg.goto(URL_ + '#chart')
  await pg.waitForFunction(n => { const c = window.__cells?.(); return c && c.length === n && c.every(x => x.bars > 300 && !x.empty) }, st.cells.length, { timeout: 30000 })
  await sleep(800)
  return { ctx, pg }
}
const base = { route: 'direct', routePicked: true, greenUpMigrated: true, panel: 'watch', active: 0, drawings: {} }
const rs = pg => pg.evaluate(() => window.__replay())
const cells = pg => pg.evaluate(() => window.__cells())
/** 第 i 格画布在页面上的位置与「时刻 → x」 */
async function geo(pg, i = 0) {
  const box = await pg.locator('.chart-cell').nth(i).locator('.canvas-host canvas').first().boundingBox()
  const c = (await cells(pg))[i]
  return { box, c, xOf: t => box.x + c.plotW * (t - c.t0) / (c.t1 - c.t0) }
}
const shot = (pg, name) => pg.screenshot({ path: OUT + name + '.png' })

// ------------------------------------------------------------ 主流程：一格 BTCUSDT 15 分
{
  const { ctx, pg } = await open({ ...base, layout: '1', cells: [{ symbol: 'BTCUSDT', iv: '15m' }] })
  const live0 = (await cells(pg))[0]
  // 对照：不回放、实时推送照常时主线程占多少
  const cdp = await ctx.newCDPSession(pg)
  await cdp.send('Performance.enable')
  const td = async () => (await cdp.send('Performance.getMetrics')).metrics.find(m => m.name === 'TaskDuration').value
  await pg.mouse.move(10, 10)
  const l0 = await td(), lw = Date.now(); await sleep(10000)
  const livePct = (await td() - l0) / ((Date.now() - lw) / 1000) * 100
  console.log(`  实时（不回放）：主线程占用 ${livePct.toFixed(1)}%`)
  // 往外缩，让 3 天前那一根露在图上
  let g = await geo(pg)
  for (let k = 0; k < 12 && g.c.t0 > Date.now() - 4 * 864e5; k++) {
    await pg.mouse.move(g.box.x + g.c.plotW * 0.8, g.box.y + 200)
    await pg.mouse.wheel(0, 300); await sleep(120)
    g = await geo(pg)
  }
  check(g.c.t0 < Date.now() - 3 * 864e5, `缩到能看见 3 天前（左缘 ${sh(g.c.t0)}）`)

  // 1. 底栏「回放」→ 选起点
  await pg.locator('.cell-foot [data-act="replay"]').click()
  check(await pg.locator('.rp-bar.picking').isVisible(), '点「回放」出选起点条（在图上点一下定起点 / 或输入 / 取消）')
  const want = Date.now() - 3 * 864e5
  // 竖线标签读出鼠标下那根的时刻，照着差值挪几下，落到 3 天前那一根
  let x = g.xOf(want), lab = ''
  const y = g.box.y + 260
  await pg.mouse.move(x - 40, y)
  for (let k = 0; k < 6; k++) {
    await pg.mouse.move(x, y, { steps: 3 }); await sleep(150)
    lab = await pg.locator('.rp-pick .lab').textContent()
    const at = Date.parse(lab.replace(/^起点\s*/, '').replace(' ', 'T') + ':00+08:00')
    if (Math.abs(at - want) <= Q) break
    x += (want - at) / (g.c.t1 - g.c.t0) * g.c.plotW
  }
  check(!!lab && lab.includes('起点'), `竖线跟着鼠标，标出起点时刻（${lab}）`)
  await shot(pg, '01-选起点-竖线跟鼠标')
  await pg.mouse.click(x, y)
  for (let k = 0; k < 40 && !(await rs(pg)); k++) await sleep(200)
  let s = await rs(pg)
  check(!!s, '点一下进入回放')
  check(Math.abs(s.start - want) < 2 * H, `起点约在 3 天前（${sh(s.start - Q)}）`)
  let c = (await cells(pg))[0]
  check(c.lastT === s.clock - Q, `图上最后一根就是起点那根（${sh(c.lastT)}）`)
  check(c.bars >= 300, `起点左边留了 ${c.bars} 根（≥ 300）`)
  const big = Number((await pg.locator('#detail [data-f="big"]').textContent()).replace(/,/g, ''))
  check(Math.abs(big - c.last) < 1e-6 * c.last + 0.01, `头部最新价跟着回放（${big} = 那根收盘 ${c.last}）`)
  check((await pg.title()).includes('回放'), `标签页标题标着回放（${await pg.title()}）`)
  const px0 = await pg.evaluate(() => window.__px('BTCUSDT'))
  await sleep(2000)
  const c2 = (await cells(pg))[0], px1 = await pg.evaluate(() => window.__px('BTCUSDT'))
  check(c2.lastT === c.lastT && c2.last === c.last && c2.bars === c.bars, `定起点后 2 秒：回放这一格的最后一根一动不动（同时实时价 ${px0} → ${px1}）`)
  await shot(pg, '02-定起点-起点之后藏起来')

  // 2. 4× 播放
  await pg.locator('.rp-bar [data-rp="speed"][data-v="4"]').click()
  await pg.locator('.rp-bar [data-rp="toggle"]').click()
  const n0 = c.bars
  await sleep(3000)
  c = (await cells(pg))[0]; s = await rs(pg)
  check(s.playing && s.speed === 4, '4× 播放中')
  check(c.bars - n0 >= 10 && c.bars - n0 <= 14, `3 秒进了 ${c.bars - n0} 根（4×，约 12 根）`)
  check(c.lastT === s.clock - Q, '最后一根跟着回放钟')
  await shot(pg, '03-4倍播放')

  // 3. 播放中画一条趋势线（⌥ T，两下）
  const drawn0 = await pg.evaluate(() => JSON.parse(localStorage.getItem('hkline-web-v1')).drawings?.BTCUSDT?.length || 0)
  await pg.keyboard.press('Alt+KeyT')
  g = await geo(pg)
  const xa = g.box.x + g.c.plotW * 0.55, xb = g.box.x + g.c.plotW * 0.8
  await pg.mouse.click(xa, g.box.y + 330); await sleep(150)
  await pg.mouse.click(xb, g.box.y + 220); await sleep(400)
  const drawn1 = await pg.evaluate(() => JSON.parse(localStorage.getItem('hkline-web-v1')).drawings?.BTCUSDT?.length || 0)
  check(drawn1 === drawn0 + 1, `回放中画趋势线照常存下（${drawn0} → ${drawn1}）`)
  check((await rs(pg)).playing, '画线不打断播放')
  await sleep(1500)
  await shot(pg, '04-回放中画趋势线')

  // 4. 切 1 小时：同一时刻重新定位
  const clockBefore = (await rs(pg)).clock
  await pg.locator('#toolbar [data-iv="1h"]').click()
  await pg.waitForFunction(() => window.__cells()[0].metaIv === 36e5 && window.__cells()[0].bars > 300, null, { timeout: 20000 })
  await pg.locator('.rp-bar [data-rp="toggle"]').click({ trial: true })
  s = await rs(pg); c = (await cells(pg))[0]
  check(s && s.iv === '1h', '切 1 小时仍在回放')
  check(c.lastT + H <= s.clock && s.clock - (c.lastT + H) < H, `1 小时上最后一根 ${sh(c.lastT)} 收线不晚于回放钟 ${sh(s.clock)}`)
  check(Math.abs(s.clock - clockBefore) < 2 * H, `回放钟按同一时刻接着走（${sh(clockBefore)} → ${sh(s.clock)}）`)
  check(c.bars >= 300, `1 小时左边也留了 ${c.bars} 根`)
  await sleep(1500)
  await shot(pg, '05-切1小时-同一时刻重新定位')

  // 5. 拖进度线
  const tr = await pg.locator('.rp-track').boundingBox()
  const clockA = (await rs(pg)).clock
  await pg.mouse.move(tr.x + tr.width * 0.3, tr.y + tr.height / 2)
  await pg.mouse.down()
  await pg.mouse.move(tr.x + tr.width * 0.75, tr.y + tr.height / 2, { steps: 12 })
  await sleep(150)
  await shot(pg, '06-拖进度线')
  await pg.mouse.up(); await sleep(800)
  s = await rs(pg); c = (await cells(pg))[0]
  check(s.clock > clockA, `拖到 75%：回放钟往后跳（${sh(clockA)} → ${sh(s.clock)}）`)
  check(c.lastT + H === s.clock, '图上最后一根跟着落过去')
  // 跳到起点
  await pg.locator('.rp-bar [data-rp="toStart"]').click(); await sleep(300)
  s = await rs(pg)
  check(s.clock <= s.start + H && s.clock >= s.start - H, `「跳到起点」回到起点（${sh(s.clock)}）`)

  // 6. 16× 量主线程（回 15 分，最密的那档）
  await pg.locator('#toolbar [data-iv="15m"]').click()
  await pg.waitForFunction(() => window.__cells()[0].metaIv === 9e5, null, { timeout: 20000 })
  await sleep(1200)
  await pg.locator('.rp-bar [data-rp="speed"][data-v="16"]').click()
  if (!(await rs(pg)).playing) await pg.locator('.rp-bar [data-rp="toggle"]').click()
  await pg.mouse.move(10, 10)
  await pg.evaluate(() => { window.__lt = []; new PerformanceObserver(l => { for (const e of l.getEntries()) window.__lt.push(e.duration) }).observe({ type: 'longtask' }) })
  const b0 = (await cells(pg))[0].bars, t0 = await td(), w0 = Date.now()
  await sleep(10000)
  const t1 = await td(), w1 = Date.now(), b1 = (await cells(pg))[0].bars
  const lt = await pg.evaluate(() => window.__lt)
  const pct = (t1 - t0) / ((w1 - w0) / 1000) * 100
  console.log(`  16×：10 秒进 ${b1 - b0} 根，主线程占用 ${pct.toFixed(1)}%，长任务 ${lt.length} 条${lt.length ? `（最长 ${Math.max(...lt).toFixed(0)} ms）` : ''}`)
  check(b1 - b0 >= 140, `16× 每秒约 16 根（10 秒 ${b1 - b0} 根）`)
  check(pct < 10, `16× 主线程占用 < 10%（${pct.toFixed(1)}%）`)
  await shot(pg, '07-16倍播放')

  // 7. 退出
  await pg.locator('.rp-bar [data-rp="exit"]').click()
  await pg.waitForFunction(() => !window.__replay(), null, { timeout: 5000 })
  await pg.waitForFunction(() => { const c = window.__cells()[0]; return c.lastT >= Math.floor(Date.now() / 9e5) * 9e5 }, null, { timeout: 20000 })
  await sleep(1500)
  c = (await cells(pg))[0]
  check(c.lastT === Math.floor(Date.now() / Q) * Q, `退出：回到实时，最后一根是正在走的那根（${sh(c.lastT)}）`)
  check(c.t1 >= c.lastT, '视口跳回最新')
  check(await pg.locator('.rp-bar').count() === 0, '回放条收起')
  check(!(await pg.title()).includes('回放'), '标签页标题回到实时')
  const drawn2 = await pg.evaluate(() => JSON.parse(localStorage.getItem('hkline-web-v1')).drawings?.BTCUSDT?.length || 0)
  check(drawn2 === drawn1, '回放里画的线留着')
  check(live0.symbol === c.symbol, '品种没变')
  await shot(pg, '08-退出回放-回到实时')
  await ctx.close()
}

// ------------------------------------------------------------ 两格：只有当前格回放；换品种退出；秒级置灰
{
  const { ctx, pg } = await open({ ...base, layout: '2', cells: [{ symbol: 'BTCUSDT', iv: '15m' }, { symbol: 'ETHUSDT', iv: '15m' }] })
  await pg.locator('.chart-cell').nth(0).locator('[data-act="replay"]').click()
  await pg.locator('.rp-bar input[data-rp="start"]').fill(sh(Date.now() - 2 * 864e5))
  await pg.keyboard.press('Enter')
  await sleep(1500)
  let s = await rs(pg)
  check(!!s && s.idx === 0, '输入起点时间也能开始回放')
  await pg.locator('.rp-bar [data-rp="speed"][data-v="8"]').click()
  await pg.locator('.rp-bar [data-rp="toggle"]').click()
  await sleep(2500)
  const cs = await cells(pg)
  check(cs[0].lastT < Date.now() - 864e5, `左格在回放（${sh(cs[0].lastT)}）`)
  check(cs[1].lastT === Math.floor(Date.now() / Q) * Q, `右格照常实时（${sh(cs[1].lastT)}）`)
  await shot(pg, '09-两格-只有当前格回放')
  // 换品种：退出回放
  await pg.evaluate(() => { location.hash = '#chart' })
  await pg.keyboard.press('Meta+KeyK'); await sleep(300)
  await pg.keyboard.type('SOLUSDT'); await sleep(500); await pg.keyboard.press('Enter')
  await sleep(2500)
  s = await rs(pg)
  const c0 = (await cells(pg))[0]
  check(!s, `换品种退出回放（左格 ${c0.symbol}）`)
  check(c0.lastT === Math.floor(Date.now() / Q) * Q, '换过去的品种是实时数据')
  await ctx.close()
}

// ------------------------------------------------------------ 秒级周期：回放按钮置灰，点了不进
{
  const ctx = await browser.newContext({ viewport: { width: 1600, height: 960 }, deviceScaleFactor: 2 })
  await ctx.addInitScript(s => { if (!sessionStorage.getItem('seeded')) { localStorage.setItem('hkline-web-v1', s); sessionStorage.setItem('seeded', '1') } },
    JSON.stringify({ ...base, layout: '1', cells: [{ symbol: 'BTCUSDT', iv: '1s' }] }))
  const pg = await ctx.newPage()
  await pg.goto(URL_ + '#chart')
  await pg.waitForFunction(() => window.__cells?.()[0]?.bars > 0, null, { timeout: 30000 })
  await sleep(1500)
  const btn = pg.locator('.cell-foot [data-act="replay"]')
  check(await btn.getAttribute('aria-disabled') === 'true', `1 秒周期：回放按钮置灰（提示「${await btn.getAttribute('data-tip')}」）`)
  await btn.hover(); await sleep(700)
  await shot(pg, '10-秒级周期-回放置灰')
  await btn.click({ force: true }); await sleep(400)
  check(!(await rs(pg)) && await pg.locator('.rp-bar').count() === 0, '点了也不进回放')
  await ctx.close()
}

await browser.close()
console.log(bad ? `\n${bad} 项不过` : '\n全部通过')
process.exit(bad ? 1 : 0)
