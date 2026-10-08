// Hkline Web · 多交易所真浏览器压测（2026-10-08）：本机 Chrome、2560×1440、DPR 1，真行情
//   node scripts/venues-stress.mjs [地址]          默认 http://localhost:5178/web/（npm run dev），线上可给 https://kanpan.43-160-232-253.sslip.io/web/
//   环境变量：VS_SOAK_S（稳态挂多久，秒，默认 60）、VS_OUT（截图目录，默认 /tmp/kp-venues-stress）、VS_GATEWAY=0（跳过切网关那一段）
// 场景（每段打一行 ✓ / ✗，最后汇总）：
//   1. 十六格：币安 / OKX / Bybit / Hyperliquid 各四只（BTC、ETH、SOL、DOGE），1 分钟线，直连。等格子都出图，挂 VS_SOAK_S 秒：
//      帧间隔 p50 / p95、长任务、JS 堆、WS 连接数（按主机分）、别家推送的控制帧数（__venueStream().controlSent）、每格最后一根的时刻没停。
//   2. 搜索连打：开搜索弹层，逐字打 12 组查询（BTC、ｂｔｃ、比特币、bitebi、pepe、kpepe、😀、单字母、超长……），每字之间 40 ms；
//      记打字期间的帧 p95 / 长任务、组头数、控制台报错；关弹层后别家的品种表都到了（S.venues 全 live）。
//   3. 当前格连切 40 次别家品种（四家轮流，每次 150 ms）：控制帧增量（应远小于 80）、最后那只的 K 线到了。
//   4. 切线路：直连 → 网关 → 直连。老连接全收（直连那几条主机的 WS 全关）、新连接全是网关主机、十六格重新出数；切回来同理。
//   5. 全程：控制台 error、未捕获异常、HTTP ≥ 400（订单流 flow 除外）、WS 被拒；定时器 / interval 数前后对比（泄漏）。
// 容器里跑不了（没有浏览器），只保证 node --check 通过；给用户在 Mac 上跑。
import { mkdirSync } from 'node:fs'
import { INSTR, PC, corsShim, launch, measure, metrics, pct, sleep } from './f-lib.mjs'

const URL_ = process.argv[2] || 'http://localhost:5178/web/'
const OUT = process.env.VS_OUT || '/tmp/kp-venues-stress'
const SOAK_S = Number(process.env.VS_SOAK_S || 60)
mkdirSync(OUT, { recursive: true })

const results = []
const ok = (name, pass, detail = '') => { results.push({ name, pass, detail }); console.log(`${pass ? '✓' : '✗'} ${name}${detail ? ' — ' + detail : ''}`) }
const log = (...a) => console.log('  ', ...a)

const COINS = ['BTC', 'ETH', 'SOL', 'DOGE']
const KEY = {
  binance: c => `${c}USDT`,
  okx: c => `okx/usd_m/${c}USDT`,
  bybit: c => `bybit/usd_m/${c}USDT`,
  hyperliquid: c => `hyperliquid/usd_m/${c}`,
}
const CELLS = Object.values(KEY).flatMap(f => COINS.map(c => ({ symbol: f(c), iv: '1m' })))
const VENUE_HOSTS = /okx\.com|bybit\.com|hyperliquid\.xyz|coinbase\.com/

const browser = await launch()
const ctx = await browser.newContext(PC)
await corsShim(ctx)
await ctx.addInitScript(INSTR)
const state = {
  theme: 'light', skin: 'sage', updown: 'green-up', greenUpMigrated: true, route: 'direct', routePicked: true,
  layout: '16', cells: CELLS, active: 0, pinned: ['1m', '5m', '15m', '1h', '4h', '1d'], panel: 'watch', watchTab: 'crypto',
  watch: { crypto: CELLS.map(c => c.symbol), us: [], com: [], idx: [] },
  ind: { ma: true, ema: false, boll: false, vol: true, subs: [] }, params: null, orderFlow: false,
  drawings: {}, alerts: [], notes: [], slots: { ladder: false, drawer: false, widgets: ['watch', 'detail'] }, linkCross: true,
}
await ctx.addInitScript(s => { if (!sessionStorage.getItem('vs')) { sessionStorage.setItem('vs', '1'); localStorage.clear(); localStorage.setItem('hkline-web-v1', s) } }, JSON.stringify(state))

const page = await ctx.newPage()
const errors = []
page.on('console', m => { if (m.type() === 'error' && !/Ping received after close/.test(m.text())) errors.push(`[console] ${m.text().slice(0, 200)}`) })
page.on('pageerror', e => errors.push(`[pageerror] ${e.message}`))
page.on('response', r => { if (r.status() >= 400 && !/orderflow\/flow/.test(r.url())) errors.push(`[http ${r.status()}] ${r.url().slice(0, 160)}`) })
page.on('websocket', ws => ws.on('socketerror', e => errors.push(`[ws] ${ws.url().slice(0, 120)} ${e}`)))
const cdp = await ctx.newCDPSession(page)
await cdp.send('Performance.enable')

const cells = () => page.evaluate(() => window.__cells())
const vstream = () => page.evaluate(() => window.__venueStream?.() ?? null)
const wsUrls = () => page.evaluate(() => [...window.__f.ws.live].filter(w => w.readyState <= 1).map(w => w.__u))
const hostsOf = urls => urls.reduce((m, u) => { const h = new URL(u).host; m[h] = (m[h] || 0) + 1; return m }, {})
const shot = async name => { await page.screenshot({ path: `${OUT}/${name}.png` }); log('截图 ' + name) }
async function waitCells(label, timeout = 90_000) {
  const t0 = Date.now()
  for (;;) {
    const cs = await cells().catch(() => [])
    const filled = cs.filter(c => c.bars > 0 && !c.empty).length
    if (filled >= cs.length && cs.length) return { ms: Date.now() - t0, filled, n: cs.length }
    if (Date.now() - t0 > timeout) return { ms: Date.now() - t0, filled, n: cs.length, timeout: true }
    await sleep(500)
  }
}

// ═════════════════ 1. 十六格四家各四只，稳态
await page.goto(URL_ + '?layout=16#chart', { waitUntil: 'domcontentloaded' })
{
  const r = await waitCells('十六格')
  ok('十六格四家各四只都出图', !r.timeout, `${r.filled}/${r.n} 格，${(r.ms / 1000).toFixed(1)} 秒`)
  const cs = await cells()
  const wrong = cs.filter((c, i) => c.symbol !== CELLS[i].symbol || c.metaSym !== CELLS[i].symbol)
  ok('每格装的就是那一家那一只（不串）', !wrong.length, wrong.map(c => `${c.symbol}≠${c.metaSym}`).join('，'))
  // 同一个币四家价格各是各的（差不多、但不是同一个对象写出来的同一个数——四家全一样多半是串了）
  for (const c of COINS) {
    const px = await page.evaluate(ks => ks.map(k => window.__px(k)), Object.values(KEY).map(f => f(c)))
    const fine = px.every(p => p != null && p > 0)
    const spread = fine ? (Math.max(...px) / Math.min(...px) - 1) * 100 : NaN
    ok(`${c}：四家的价都有、相差 < 2%`, fine && spread < 2, px.map(p => p ?? '—').join(' / ') + (fine ? `（差 ${spread.toFixed(3)}%）` : ''))
  }
  await shot('1-十六格')
  const m0 = await metrics(cdp, page)
  const v0 = await vstream()
  const last0 = (await cells()).map(c => c.lastT)
  const meas = await measure(page, cdp, () => sleep(SOAK_S * 1000))
  const m1 = await metrics(cdp, page)
  const v1 = await vstream()
  const last1 = (await cells()).map(c => c.lastT)
  const urls = await wsUrls()
  const hosts = hostsOf(urls)
  log(`帧 p50 ${meas.p50} / p95 ${meas.p95} ms、最长 ${meas.max} ms、长任务 ${meas.lt}（最长 ${meas.ltMax} ms）、CPU ${meas.cpu}%`)
  log(`堆 ${m0.heap} → ${m1.heap} MB、interval ${m0.iv} → ${m1.iv}、timeout ${m0.to} → ${m1.to}`)
  log(`WS：${JSON.stringify(hosts)}；别家连接 ${JSON.stringify(v1?.conns.map(c => `${c.venue}:${c.endpoint} ${c.subscribed.length} 路`))}`)
  ok(`稳态 ${SOAK_S} 秒：帧 p95 ≤ 50 ms、长任务 ≤ ${Math.ceil(SOAK_S / 10)}`, meas.p95 <= 50 && meas.lt <= Math.ceil(SOAK_S / 10), `p95 ${meas.p95} ms，长任务 ${meas.lt}`)
  ok('稳态：堆涨幅 ≤ 30 MB、interval 不涨', m1.heap - m0.heap <= 30 && m1.iv <= m0.iv, `${m0.heap} → ${m1.heap} MB，interval ${m0.iv} → ${m1.iv}`)
  ok('别家一家一条连接（OKX K 线另一条），共 ≤ 4 条', (v1?.conns.length ?? 99) <= 4 && urls.filter(u => VENUE_HOSTS.test(u)).length <= 4, `${urls.filter(u => VENUE_HOSTS.test(u)).length} 条`)
  ok('稳态期间没有多余的订 / 退', v1 && v0 && v1.controlSent - v0.controlSent <= 2, `控制帧 ${v0?.controlSent} → ${v1?.controlSent}`)
  const stuck = last1.map((t, i) => (t != null && t === last0[i] && SOAK_S >= 70 ? CELLS[i].symbol : null)).filter(Boolean)
  ok('每格的最后一根在走（挂满 70 秒以上才判）', !stuck.length, stuck.join('，'))
}

// ═════════════════ 2. 搜索连打
{
  const e0 = errors.length
  await page.click('#tbSymbol')
  await page.waitForSelector('#sq')
  const QUERIES = ['BTC', 'ｂｔｃ', '比特币', 'bitebi', 'pepe', 'kpepe', '😀', 'e', 'x'.repeat(60), 'btc/usdt', 'doge', 'hype']
  const groups = []
  const meas = await measure(page, cdp, async () => {
    for (const q of QUERIES) {
      await page.fill('#sq', '')
      for (const ch of [...q]) { await page.type('#sq', ch); await sleep(40) }
      await sleep(250)
      groups.push(await page.evaluate(() => [...document.querySelectorAll('.search-dlg .sr-group')].map(x => x.textContent)))
    }
  })
  await shot('2-搜索')
  await page.keyboard.press('Escape')
  log(`打字期间帧 p95 ${meas.p95} ms、长任务 ${meas.lt}（最长 ${meas.ltMax} ms）`)
  log(`各查询的组头：${groups.map((g, i) => `${QUERIES[i].slice(0, 8)}→${g.length}`).join('，')}`)
  ok('搜索连打：帧 p95 ≤ 50 ms、长任务最长 ≤ 200 ms', meas.p95 <= 50 && meas.ltMax <= 200, `p95 ${meas.p95}，长任务 ${meas.lt} 个最长 ${meas.ltMax} ms`)
  ok('BTC 五家都出组（品种表懒拉到了）', (groups[0]?.filter(g => !/正在取|取不到/.test(g)).length ?? 0) >= 5, (groups[0] || []).join(' | '))
  ok('😀、超长查询不崩、没有报错', errors.length === e0, errors.slice(e0).join('\n'))
}

// ═════════════════ 3. 当前格连切别家品种
{
  const v0 = await vstream()
  const seq = Array.from({ length: 40 }, (_, i) => Object.values(KEY)[i % 4](['XRP', 'LINK', 'AVAX', 'SUI', 'ADA'][i % 5]))
  for (const k of seq) {
    await page.click('#tbSymbol'); await page.waitForSelector('#sq')
    await page.fill('#sq', k.split('/').pop().replace(/USDT$/, ''))
    await sleep(60)
    // 组头之后第一行是哪一家由组序定；直接点那一家那一行
    const clicked = await page.evaluate(key => {
      const rows = [...document.querySelectorAll('.search-dlg .sr[data-i]')]
      const row = rows.find(r => r.querySelector(`[data-w="${CSS.escape(key)}"]`))
      if (row) { row.click(); return true }
      return false
    }, k)
    if (!clicked) await page.keyboard.press('Escape')
    await sleep(150)
  }
  await sleep(5000)
  const v1 = await vstream()
  const last = seq.at(-1)
  const c0 = (await cells())[0]
  log(`控制帧 ${v0?.controlSent} → ${v1?.controlSent}；第一格 ${c0.symbol} ${c0.bars} 根`)
  ok('连切 40 次：控制帧增量 ≤ 60（一切一退一订是 80）', v1 && v0 && v1.controlSent - v0.controlSent <= 60, `${v1?.controlSent - v0?.controlSent} 条`)
  ok('最后那只装上了、有 K 线', c0.symbol === last && c0.bars > 0, `${c0.symbol} ${c0.bars} 根（要 ${last}）`)
}

// ═════════════════ 4. 切线路：直连 → 网关 → 直连
if (process.env.VS_GATEWAY !== '0') {
  const setRoute = async v => {
    await page.evaluate(() => { location.hash = '#me' })
    await page.click('[data-me="general"]').catch(() => {})
    await page.click(`[data-seg="route"][data-v="${v}"]`)
    await sleep(300)
    await page.evaluate(() => { location.hash = '#chart' })
  }
  for (const [route, want] of [['gateway', /sslip\.io|\/v1\/market\/ws\/|\/market\/stream/], ['direct', VENUE_HOSTS]]) {
    const before = await wsUrls()
    await setRoute(route)
    const r = await waitCells(route, 60_000)
    await sleep(8000)
    const after = await wsUrls()
    const v = await vstream()
    const venueConns = v?.conns ?? []
    log(`${route}：WS ${JSON.stringify(hostsOf(after))}；别家 ${venueConns.map(c => c.url.replace(/\?.*/, '')).join('，')}`)
    ok(`切到${route === 'gateway' ? '网关' : '直连'}：十六格重新出数`, !r.timeout, `${r.filled}/${r.n}`)
    ok(`切到${route === 'gateway' ? '网关' : '直连'}：别家的连接全按新线路`, venueConns.length > 0 && venueConns.every(c => want.test(c.url)), venueConns.map(c => c.url).join('，'))
    const leaked = after.filter(u => before.includes(u) && VENUE_HOSTS.test(u) && route === 'gateway')
    ok(`切到${route === 'gateway' ? '网关' : '直连'}：老的直连别家连接全收`, !leaked.length, leaked.join('，'))
  }
  await shot('4-切回直连')
}

// ═════════════════ 5. 汇总
{
  const m = await metrics(cdp, page, true)
  const intervals = Object.entries(m.ivBy).map(([k, n]) => `${n}× ${k}`).join('；')
  log(`收尾：堆 ${m.heap} MB、interval ${m.iv}（${intervals}）、timeout ${m.to}、WS 活 ${m.ws.live}（开 ${m.ws.opened} 关 ${m.ws.closed}）、localStorage 写 ${m.ls.n} 次 ${(m.ls.bytes / 1024).toFixed(0)} KB`)
  const byKey = Object.entries(m.ls.byKey).sort((a, b) => b[1].bytes - a[1].bytes).slice(0, 5).map(([k, v]) => `${k} ${v.n} 次 ${(v.bytes / 1024).toFixed(0)} KB`)
  log(`落盘最多的键：${byKey.join('；')}`)
  ok('全程没有控制台报错 / 未捕获异常 / HTTP ≥ 400', !errors.length, errors.slice(0, 20).join('\n'))
  const p95s = results.filter(r => /p95/.test(r.detail)).map(r => Number(/p95 ([\d.]+)/.exec(r.detail)?.[1])).filter(Number.isFinite)
  if (p95s.length) log(`各段帧 p95 的 p95：${pct(p95s, 0.95)} ms`)
}

const bad = results.filter(r => !r.pass)
console.log(`\n${results.length - bad.length}/${results.length} 通过${bad.length ? '；没过：' + bad.map(r => r.name).join('、') : ''}`)
await browser.close()
process.exit(bad.length ? 1 : 0)
