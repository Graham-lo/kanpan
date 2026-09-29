// Hkline Web · 深度压测（图表、多图布局、画线、指标）：本机 Chrome、2560×1440、DPR 1
//   node scripts/stress.mjs [地址] <场景…>
//   场景：reqs（多图下的 REST 请求量）、layouts（十种布局逐格换品种周期）、sizes（尺寸存档塞坏值）、levels（关键价位各周期）、
//         oldstate（旧版 / 损坏的本机存档升级）、hf（300 次随机高频切换）、offline（断网 30 秒 × N 次）、draw500（画满 500 条）、
//         multitab（同账号两个标签页）、soak（长时间挂机，SOAK_MIN 分钟，默认 25）
//   环境变量：KP_USER / KP_PASS（multitab 要）、STRESS_OUT（截图目录，默认 /tmp/kpA-stress）、OFFLINE_N（断网次数，默认 5）
// 每一项打一行「✓ / ✗」，全程收集控制台报错、未捕获异常、网络失败。
import { chromium } from 'playwright-core'
import { mkdirSync, writeFileSync } from 'node:fs'

const URL_ = process.argv[2] || 'http://localhost:5181/web/'
const MODES = process.argv.slice(3)
const OUT = process.env.STRESS_OUT || '/tmp/kpA-stress'
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const KP_USER = process.env.KP_USER || '', KP_PASS = process.env.KP_PASS || ''
const API = new globalThis.URL(URL_).origin.includes('localhost') ? 'https://kanpan.107-174-172-10.sslip.io' : new globalThis.URL(URL_).origin
mkdirSync(OUT, { recursive: true })

const results = []
const ok = (name, pass, detail = '') => { results.push({ name, pass, detail }); console.log(`${pass ? '✓' : '✗'} ${name}${detail ? ' — ' + detail : ''}`) }
const log = (...a) => console.log('  ', ...a)

const browser = await chromium.launch({ executablePath: CHROME, headless: true, args: ['--enable-precise-memory-info'] })
const WS_SPY = () => {
  const W = window.WebSocket
  const reg = { opened: 0, closed: 0, live: [] }
  window.__ws = reg
  window.WebSocket = class extends W {
    constructor(u, p) {
      super(u, p)
      const me = { url: String(u), subs: new Set() }
      try { const q = new URL(String(u)).searchParams.get('streams'); if (q) q.split('/').forEach(x => x && me.subs.add(x)) } catch { /* 不是合法地址 */ }
      reg.opened++; reg.live.push(me)
      this.addEventListener('close', () => { reg.closed++; reg.live = reg.live.filter(x => x !== me) })
      const send = this.send.bind(this)
      this.send = d => {
        try {
          const m = JSON.parse(d)
          if (m.method === 'SUBSCRIBE') m.params.forEach(x => me.subs.add(x))
          if (m.method === 'UNSUBSCRIBE') m.params.forEach(x => me.subs.delete(x))
        } catch { /* 不是 JSON 的不管 */ }
        return send(d)
      }
    }
  }
  window.addEventListener('unhandledrejection', e => console.error('[unhandledrejection]', String(e.reason?.stack || e.reason)))
}
async function newCtx() {
  const ctx = await browser.newContext({ viewport: { width: 2560, height: 1440 }, deviceScaleFactor: 1 })
  await ctx.addInitScript(WS_SPY)
  await ctx.addInitScript(() => { window.__keepGate = ls => { const g = ls.getItem('hkline-web-rate-limit'); ls.clear(); if (g) ls.setItem('hkline-web-rate-limit', g) } })
  return ctx
}
let ctx = await newCtx()
let page = await ctx.newPage()
const errors = [], netFail = [], reqs = []
function watchPage(pg, tag = '') {
  // 「Ping received after close」：页面刚 close() 一条币安现货盘口连接、币安那头正好发来一个 ping，Chrome 自己打的协议日志；
  // 关连接是换品种时应该做的，页面拦不住也不影响什么，不算报错
  pg.on('console', m => { if (m.type() === 'error' && !/Ping received after close/.test(m.text())) errors.push(`${tag}[console] ${m.text()}`) })
  pg.on('pageerror', e => errors.push(`${tag}[pageerror] ${e.message}`))
  pg.on('response', r => { if (r.status() >= 400 && !/orderflow\/flow/.test(r.url())) errors.push(`${tag}[http ${r.status()}] ${r.url().slice(0, 140)}`) })
  pg.on('requestfailed', r => { const u = r.url(); if (!/sslip\.io\/v1\/market\/orderflow\/flow/.test(u)) netFail.push(`${tag}${r.failure()?.errorText} ${u.slice(0, 140)}`) })
  pg.on('request', r => { const u = r.url(); if (/fapi\.binance\.com|\/futures\/data/.test(u)) reqs.push({ t: Date.now(), u }) })
}
watchPage(page)
let cdp = await ctx.newCDPSession(page)

const wait = ms => page.waitForTimeout(ms)
const shot = async (name, opt = {}) => { await page.screenshot({ path: `${OUT}/${name}.png`, ...opt }); log('截图 ' + name) }
const state = () => page.evaluate(() => JSON.parse(localStorage.getItem('hkline-web-v1') || '{}'))
const cellsNow = () => page.evaluate(() => window.__cells())
const ws = () => page.evaluate(() => ({ opened: window.__ws.opened, closed: window.__ws.closed, live: window.__ws.live.map(x => ({ url: x.url.replace(/\?.*/, ''), q: x.url.includes('?'), subs: [...x.subs].sort() })) }))
const streamNow = () => page.evaluate(() => window.__stream())
const ready = async (pg = page) => {
  await pg.waitForFunction(() => (document.querySelector('#toolbar #tbSymbol') && document.title.includes('·')) || !!document.querySelector('.cell-empty:not([hidden])'), null, { timeout: 30000, polling: 250 })
  await pg.waitForTimeout(1500)
}
const open = async (qs = '', hash = 'chart') => { await page.goto(`${URL_}?${qs}#${hash}`, { waitUntil: 'domcontentloaded' }); await ready() }
/** 清空本机，写一份状态（可以只给一部分），再打开 */
// 写存档要在一张「同源但不跑 app」的空白页上写：在 app 页上写，app 启动时那次 save() 会把刚写的整份盖回默认
const BLANK = new URL('__stress_blank', URL_).href
await ctx.route(BLANK, r => r.fulfill({ status: 200, contentType: 'text/html', body: '<!doctype html><title>blank</title>' }))
const toBlank = async (pg = page) => { await pg.goto(BLANK, { waitUntil: 'domcontentloaded' }) }
// 压测自己也守币安的出口预算：连开页面前看一眼共用账本（页面里的限频闸门记的），这一分钟合约权重超过 400 或在暂停就等
async function pace(limit = 400) {
  for (let k = 0; k < 90; k++) {
    const g = await page.evaluate(() => { try { const s = JSON.parse(localStorage.getItem('hkline-web-rate-limit') || 'null'); const now = Date.now(); if (!s) return { used: 0, pause: 0 }; return { used: (s.used?.fapi || []).filter(x => now - x[0] < 60000).reduce((a, x) => a + x[1], 0), pause: Math.max(0, (s.cool?.['fapi.binance.com']?.until || 0) - now) } } catch { return { used: 0, pause: 0 } } })
    if (g.used <= limit && !g.pause) return
    if (k === 0) log(`  等币安预算：这一分钟合约权重 ${g.used}${g.pause ? '，暂停还剩 ' + Math.round(g.pause / 1000) + ' 秒' : ''}`)
    await wait(2000)
  }
}
async function seed(partial, qs = '', sizes) {
  await toBlank(); await pace()
  await page.evaluate(([p, z]) => {
    __keepGate(localStorage)
    if (p != null) localStorage.setItem('hkline-web-v1', typeof p === 'string' ? p : JSON.stringify(p))
    if (z != null) localStorage.setItem('hkline-web-sizes-v1', typeof z === 'string' ? z : JSON.stringify(z))
  }, [partial, sizes])
  await open(qs)
}
const metrics = async () => Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map(m => [m.name, m.value]))
const gc = async () => { await cdp.send('HeapProfiler.collectGarbage'); await wait(200); await cdp.send('HeapProfiler.collectGarbage') }
const menuClick = async label => { await page.locator('.menu .mi', { hasText: label }).first().click(); await wait(250) }
const pickLayout = async label => { await page.click('#tbLayout'); await wait(200); await menuClick(label) }
const LAYS = [['1', '一图', 1], ['2', '左右两图', 2], ['2v', '上下两图', 2], ['3', '左一右二', 3], ['4', '四图', 4], ['6', '六图', 6], ['8', '八图', 8], ['9', '九图', 9], ['12', '十二图', 12], ['16', '十六图', 16]]
const SYMS = ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'XAUUSDT', 'BNBUSDT', 'XRPUSDT', 'DOGEUSDT', 'NVDAUSDT', 'ADAUSDT', 'LINKUSDT', 'AVAXUSDT', 'SUIUSDT', 'XAGUSDT', 'TSLAUSDT', 'LTCUSDT', 'TRXUSDT', 'DOTUSDT', 'BCHUSDT', 'NEARUSDT', 'APTUSDT']
const IVS = ['1m', '3m', '5m', '15m', '30m', '1h', '2h', '4h', '6h', '12h', '1d', '1w']
const IV_MS = { '1m': 6e4, '3m': 18e4, '5m': 3e5, '15m': 9e5, '30m': 18e5, '1h': 36e5, '2h': 72e5, '4h': 144e5, '6h': 216e5, '8h': 288e5, '12h': 432e5, '1d': 864e5, '1w': 6048e5 }
const rnd = a => a[Math.floor(Math.random() * a.length)]
const since = t => reqs.filter(r => r.t >= t)

// ═════════════════ 多图下的 REST 请求量（关键价位、成交量分布细 K 线的缓存够不够 16 格用） ═════════════════
async function modeReqs() {
  const e0 = errors.length
  // 16 格各一只、1 小时、只开关键价位
  await seed({ layout: '16', ind: { ma: false, ema: false, boll: false, vol: true, subs: [], keys: true } }, 'layout=16&i=1h&panel=watch')
  await wait(8000)
  let t0 = Date.now()
  await wait(60000)
  let r = since(t0).filter(x => /interval=(1d|5m)/.test(x.u))
  const perSym = {}
  r.forEach(x => { const s = /symbol=(\w+)/.exec(x.u)[1]; perSym[s] = (perSym[s] || 0) + 1 })
  ok('16 格开关键价位：稳定后 60 秒内不再反复要日线 / 5 分钟线', r.length <= 4, `${r.length} 次；${Object.entries(perSym).map(([k, v]) => `${k}×${v}`).join(' ')}`)
  const cs = await cellsNow()
  // 16 格 4 小时、开成交量分布：细 K 线缓存
  const tSeed = Date.now()
  // 地址里的 i= 只改当前格，16 格都要是 4 小时得写进格子里
  await seed({ layout: '16', cells: SYMS.slice(0, 16).map(symbol => ({ symbol, iv: '4h' })), ind: { ma: false, ema: false, boll: false, vol: true, subs: [], vpvr: true } }, 'layout=16&panel=watch')
  // 先等 16 格都要到过细 K 线：限流闸在排队时一条也发不出去，「60 秒里 0 次」就不说明缓存管用（第一轮就是这样漏掉的）
  const gotFine = () => new Set(since(tSeed).filter(x => /interval=15m/.test(x.u)).map(x => /symbol=(\w+)/.exec(x.u)[1])).size
  for (let k = 0; k < 45 && gotFine() < 16; k++) await wait(2000)
  await wait(5000)
  ok('16 格 4 小时开成交量分布：每格都要到过细 K 线', gotFine() >= 16, `${gotFine()} 只`)
  t0 = Date.now()
  await wait(60000)
  r = since(t0).filter(x => /interval=15m/.test(x.u))
  const per2 = {}
  r.forEach(x => { const s = /symbol=(\w+)/.exec(x.u)[1]; per2[s] = (per2[s] || 0) + 1 })
  ok('16 格 4 小时开成交量分布：稳定后 60 秒内不再反复要 15 分钟细 K 线', r.length <= 4, `${r.length} 次；${Object.entries(per2).map(([k, v]) => `${k}×${v}`).join(' ')}`)
  const all = since(t0).length
  ok('16 格 4 小时：60 秒内币安 REST 请求总数合理（≤ 60）', all <= 60, `${all} 次`)
  ok('请求量：控制台无报错', errors.length === e0, errors.slice(e0, e0 + 5).join(' | '))
  void cs
}

// ═════════════════ 十种布局逐个开，每格给不同品种与周期 ═════════════════
async function modeLayouts() {
  const e0 = errors.length
  await seed(null, 'layout=1&s=BTCUSDT&i=1h&panel=watch')
  const base = await page.evaluate(() => window.__cells()[0])
  for (const [k, label, n] of LAYS) {
    await pickLayout(label); await wait(1500)
    // 每格点一下激活，用 ⌘K 搜品种、数字键不行（栏上周期有限）→ 直接在「更多」里点
    const want = []
    for (let i = 0; i < n; i++) {
      const s = SYMS[(i * 3 + LAYS.findIndex(x => x[0] === k)) % SYMS.length], iv = IVS[(i + n) % IVS.length]
      want.push({ s, iv })
    }
    // 走 UI：点格子 → ⌘K → 打代号 → 回车；周期用「更多」菜单
    for (let i = 0; i < n; i++) {
      const cb = await page.locator('.chart-cell').nth(i).boundingBox()
      await page.mouse.click(cb.x + cb.width * 0.3, cb.y + cb.height * 0.4); await wait(80)
      await page.keyboard.press('Escape')
      await page.keyboard.press('Meta+k'); await wait(150)
      await page.keyboard.type(want[i].s.replace('USDT', '')); await wait(250); await page.keyboard.press('Enter'); await wait(150)
      await page.click('#tbMoreIv'); await wait(150)
      await page.locator('.menu .mi', { hasText: new RegExp(`^${{ '1m': '1分', '3m': '3分', '5m': '5分', '15m': '15分', '30m': '30分', '1h': '1小时', '2h': '2小时', '4h': '4小时', '6h': '6小时', '12h': '12小时', '1d': '日线|1日', '1w': '周线|1周' }[want[i].iv]}`) }).first().click().catch(async () => { await page.keyboard.press('Escape') })
      await wait(120)
    }
    await wait(n >= 12 ? 7000 : 4000)
    const cs = await cellsNow()
    const bad = cs.map((c, i) => ({ i, c, w: want[i] })).filter(({ c, w }) => c.symbol !== w.s || c.iv !== w.iv || c.metaSym !== w.s || c.metaIv !== IV_MS[w.iv] || !c.bars)
    // 数据没串：每格最后一根收盘价要和这只品种的最新价接近（1.5% 以内）
    const px = await page.evaluate(ss => ss.map(s => window.__px?.(s) ?? null), cs.map(c => c.symbol))
    const off = cs.map((c, i) => ({ i, s: c.symbol, last: c.last, p: px[i] })).filter(x => x.p && x.last && Math.abs(x.last / x.p - 1) > 0.015)
    ok(`布局 ${label}：${n} 格各自的品种周期对得上、没串数据`, bad.length === 0 && off.length === 0 && cs.length === n,
      bad.length ? bad.slice(0, 4).map(({ i, c, w }) => `#${i} 要 ${w.s}/${w.iv} 得 ${c.symbol}/${c.iv} 图 ${c.metaSym}/${c.metaIv} ${c.bars} 根`).join('；') : off.length ? off.map(x => `#${x.i} ${x.s} 收 ${x.last} 价 ${x.p}`).join('；') : `${cs.map(c => `${c.symbol.replace('USDT', '')}/${c.iv}`).join(' ')}`)
    const deg = cs.map(c => c.deg), rect = await page.evaluate(() => [...document.querySelectorAll('.chart-cell')].map(e => { const r = e.getBoundingClientRect(); return [Math.round(r.width), Math.round(r.height)] }))
    const wrongDeg = deg.map((d, i) => ({ d, r: rect[i], i })).filter(({ d, r }) => (r[0] < 640 || r[1] < 400) === d.subs)
    const paneBad = cs.filter(c => (c.deg.subs ? c.panes.length !== 1 + (c.subs ?? 2) : c.panes.length !== 1))
    ok(`布局 ${label}：副图按格子尺寸降级（小格只留主图）`, wrongDeg.length === 0 && paneBad.length === 0, `格子 ${rect[0].join('×')}，降级 ${JSON.stringify(deg[0])}，窗格 ${cs.map(c => c.panes.length).join('')}`)
    if (k === '16' || k === '6') await shot(`A-布局-${label}`)
  }
  // 回到一图：指标、窗格、第 0 格的品种周期
  await pickLayout('一图'); await wait(2500)
  const one = (await cellsNow())[0]
  ok('回到一图：副图恢复、不降级', one.deg.subs && !one.deg.compact && one.panes.length === 3, `${JSON.stringify(one.deg)} 窗格 ${one.panes.length}（开始时 ${base.panes.length}）`)
  // 16 格切品种 / 周期 / 皮肤：主线程与报错
  await pickLayout('十六图'); await wait(6000)
  await cdp.send('Performance.enable', { timeDomain: 'timeTicks' })
  const m0 = await metrics()
  const lt0 = await page.evaluate(() => { window.__lt = []; const po = new PerformanceObserver(l => l.getEntries().forEach(e => window.__lt.push(Math.round(e.duration)))); po.observe({ type: 'longtask', buffered: false }); return 0 })
  for (let k = 0; k < 16; k++) {
    const cb = await page.locator('.chart-cell').nth(k).boundingBox()
    await page.mouse.click(cb.x + cb.width * 0.3, cb.y + cb.height * 0.4); await wait(50)
    await page.keyboard.press(String(1 + (k % 7))); await wait(120)
  }
  for (let k = 0; k < 4; k++) { await page.click('#hdrTheme'); await wait(300) }
  await wait(3000)
  const m1 = await metrics()
  const lts = await page.evaluate(() => window.__lt)
  void lt0
  const busy = (m1.TaskDuration - m0.TaskDuration) / (m1.Timestamp - m0.Timestamp)
  ok('16 格连续切周期 / 皮肤：主线程占用 < 70%、没有 > 200 ms 的长任务', busy < 0.7 && !lts.some(x => x > 200), `占用 ${(busy * 100).toFixed(0)}%，长任务 ${lts.length} 个，最长 ${Math.max(0, ...lts)} ms`)
  await cdp.send('Performance.disable')
  ok('布局：控制台无报错', errors.length === e0, errors.slice(e0, e0 + 5).join(' | '))
}

// ═════════════════ 尺寸存档：极值与坏值 ═════════════════
const rectOf = sel => page.evaluate(s => { const e = document.querySelector(s); if (!e) return null; const r = e.getBoundingClientRect(); return { x: r.x, y: r.y, w: Math.round(r.width), h: Math.round(r.height) } }, sel)
const noScroll = () => page.evaluate(() => {
  const d = document.documentElement
  const over = [...document.querySelectorAll('.chart-cell, #sidePanel, #ladderSlot, #drawerSlot, #chartArea, #sidePanel [data-w]')].filter(e => { const r = e.getBoundingClientRect(); return r.width && (r.right > innerWidth + 1 || r.bottom > innerHeight + 1 || r.height < 0) }).map(e => e.id || e.dataset.w || e.className)
  return { ok: d.scrollWidth <= innerWidth && d.scrollHeight <= innerHeight && !over.length, info: `${d.scrollWidth}×${d.scrollHeight}${over.length ? ' 溢出：' + over.join(',') : ''}` }
})
async function dragSplit(name, dx, dy, at = 0.3) {
  const b = await page.locator(`.splitter[data-split="${name}"]`).boundingBox()
  if (!b) throw new Error(`没有分隔条 ${name}`)
  const x = b.width > b.height ? b.x + b.width * at : b.x + b.width / 2
  const y = b.width > b.height ? b.y + b.height / 2 : b.y + b.height * at
  await page.mouse.move(x, y); await page.mouse.down()
  await page.mouse.move(x + dx, y + dy, { steps: 8 }); await page.mouse.up(); await wait(300)
}
async function modeSizes() {
  const e0 = errors.length
  const qs = 'layout=4&s=BTCUSDT&i=1h&panel=watch&ladder=1&drawer=1'
  const BAD = [
    ['负数', { ladder: -500, panel: -1, drawer: -9999, panes: { macd: -0.5, rsi: -3 }, side: { watch: -400 }, grid: { '4': { cols: [-1, 2], rows: [0, 0] } } }],
    ['超大', { ladder: 1e9, panel: 1e12, drawer: 1e7, panes: { macd: 50, rsi: 1e6 }, side: { watch: 1e9, book: 1e9 }, grid: { '4': { cols: [1e9, 1], rows: [1, 1e-12] } } }],
    ['非数字', { ladder: 'wide', panel: null, drawer: true, panes: 'x', side: [1, 2], grid: { '4': 'abc' } }],
    ['字段形状全错', { ladder: {}, panel: [], drawer: 'NaN', panes: [0.3], side: 'side', grid: 7 }],
    ['缺字段', { grid: { '4': { cols: [0.7] } } }],
    ['数组', [1, 2, 3]],
    ['不是 JSON', '{"ladder": 300, "panel":'],
    ['NaN 字面量', '{"ladder": NaN, "panel": Infinity}'],
  ]
  for (const [name, z] of BAD) {
    const e1 = errors.length
    await seed({ slots: { ladder: true, drawer: true, widgets: ['watch', 'book', 'detail'] } }, qs, z)
    await wait(800)
    const lad = await rectOf('#ladderSlot'), pan = await rectOf('#sidePanel'), dra = await rectOf('#drawerSlot'), ca = await rectOf('#chartArea')
    const sc = await noScroll()
    const cs = await cellsNow()
    const side = await page.evaluate(() => [...document.querySelectorAll('#sidePanel [data-w]')].map(e => Math.round(e.getBoundingClientRect().height)))
    const good = lad && lad.w >= 160 && lad.w <= 480 && pan.w >= 320 && pan.w <= 640 && dra.h >= 160 && ca.w >= 480 && ca.h >= 240 && sc.ok && cs.length === 4 && cs.every(c => c.bars > 0 && c.panes.every(p => p[2] >= 0)) && side.every(h => h >= 20)
    // 拖一下各条分隔线，不能抛错
    let dragErr = ''
    try { await dragSplit('grid-cols-0', 60, 0, 0.2); await dragSplit('grid-rows-0', 0, 40, 0.2); await dragSplit('panel', -30, 0); await dragSplit('side-0', 0, 30, 0.5) } catch (e) { dragErr = String(e.message || e) }
    const saved = await page.evaluate(() => localStorage.getItem('hkline-web-sizes-v1'))
    ok(`尺寸存档「${name}」：页面自愈、不破版、分隔条还能拖`, good && !dragErr && errors.length === e1, `梯子 ${lad?.w} 侧栏 ${pan?.w} 抽屉 ${dra?.h} 图表区 ${ca?.w}×${ca?.h} 侧栏块 ${side.join('/')} ${sc.info}${dragErr ? ' 拖动出错 ' + dragErr : ''}${errors.length > e1 ? ' 报错 ' + errors.slice(e1, e1 + 2).join(' | ') : ''}；存档 ${String(saved).slice(0, 120)}`)
  }
  // 极值：拖到最小 / 最大，图与侧栏不破版
  await seed({ slots: { ladder: true, drawer: true, widgets: ['watch', 'book', 'detail'] } }, qs)
  await dragSplit('panel', -2000, 0); await dragSplit('ladder', -2000, 0); await dragSplit('drawer', 0, -3000)
  await dragSplit('grid-cols-0', 3000, 0, 0.2); await dragSplit('grid-rows-0', 0, 3000, 0.2); await dragSplit('side-0', 0, 3000, 0.5)
  let sc = await noScroll(), ca = await rectOf('#chartArea')
  const cells = await page.evaluate(() => [...document.querySelectorAll('.chart-cell')].map(e => { const r = e.getBoundingClientRect(); return [Math.round(r.width), Math.round(r.height)] }))
  const side = await page.evaluate(() => [...document.querySelectorAll('#sidePanel [data-w]')].map(e => Math.round(e.getBoundingClientRect().height)))
  ok('全部拖到极值：图表区 ≥ 480×240、每格 ≥ 240×160、侧栏块不为负、不溢出', sc.ok && ca.w >= 480 && ca.h >= 240 && cells.every(([w, h]) => w >= 236 && h >= 156) && side.every(h => h >= 20), `图表区 ${ca.w}×${ca.h}，格子 ${cells.map(c => c.join('×')).join(' ')}，侧栏块 ${side.join('/')}，${sc.info}`)
  await shot('A-尺寸-全部拖到极值')
  await dragSplit('panel', 3000, 0); await dragSplit('ladder', 3000, 0); await dragSplit('drawer', 0, 3000)
  sc = await noScroll()
  const lad = await rectOf('#ladderSlot'), pan = await rectOf('#sidePanel'), dra = await rectOf('#drawerSlot')
  ok('反方向拖到极值：梯子 160、侧栏 320、抽屉 160', lad.w === 160 && pan.w === 320 && dra.h === 160 && sc.ok, `${lad.w} / ${pan.w} / ${dra.h} ${sc.info}`)
  await page.reload({ waitUntil: 'domcontentloaded' }); await ready()
  const lad2 = await rectOf('#ladderSlot'), pan2 = await rectOf('#sidePanel'), dra2 = await rectOf('#drawerSlot')
  ok('刷新后极值尺寸还在', lad2.w === 160 && pan2.w === 320 && dra2.h === 160, `${lad2.w} / ${pan2.w} / ${dra2.h}`)
  // 小窗口
  for (const [w, h] of [[1280, 720], [1024, 640], [800, 600]]) {
    await page.setViewportSize({ width: w, height: h }); await wait(800)
    sc = await noScroll(); ca = await rectOf('#chartArea')
    // 设计目标是 27 寸 2K，小窗只要求页面本身不出滚动条（800 宽时梯子 + 侧栏 + 图表区下限加起来已超宽，只记录）；侧栏块被裁记为信息
    const pageOk = w < 1000 || sc.info.split(" ")[0] === `${w}×${h}`
    ok(`窗口 ${w}×${h}：页面不出横竖滚动条、图表区还有（侧栏块被裁只记录）`, pageOk && ca.w > 100 && ca.h > 100, `图表区 ${ca.w}×${ca.h} ${sc.info}`)
  }
  await page.setViewportSize({ width: 2560, height: 1440 }); await wait(800)
  ok('尺寸：控制台无报错', errors.length === e0, errors.slice(e0, e0 + 5).join(' | '))
}

// ═════════════════ 关键价位各周期 ═════════════════
const indNow = (i = 0) => page.evaluate(k => window.__ind(k), i)
async function until(fn, limit, step = 1000) { const t0 = Date.now(); for (;;) { const v = await fn(); if (v || Date.now() - t0 > limit) return v; await wait(step) } }
async function modeLevels() {
  const e0 = errors.length
  const DAY = 864e5
  const daily = await (await fetch('https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT&interval=1d&limit=16')).json()
  const now = Date.now(), today = Math.floor(now / DAY) * DAY
  const y = daily.find(r => r[0] === today - DAY), t = daily.find(r => r[0] === today)
  const d = Math.floor(now / DAY), week = (d - (d + 3) % 7) * DAY
  const lw = daily.filter(r => r[0] >= week - 7 * DAY && r[0] < week)
  const exp = { 昨高: +y[2], 昨低: +y[3], 今开: +t[1], 上周高: Math.max(...lw.map(r => +r[2])), 上周低: Math.min(...lw.map(r => +r[3])) }
  for (const iv of ['1m', '15m', '1h', '4h', '1d']) {
    await seed({ ind: { ma: true, ema: false, boll: false, vol: true, subs: ['macd', 'rsi'], keys: true } }, `layout=1&s=BTCUSDT&i=${iv}&panel=watch`)
    const x = await until(async () => { const v = await indNow(); return v && v.keysAll.length >= (iv === '1d' ? 2 : 8) ? v : null }, 20000, 800) || await indNow()
    const labels = x.keysAll
    const wantL = iv === '1d' ? ['上周高', '上周低'] : ['昨高', '昨低', '今开', '上周高', '上周低', '昨控', '昨值上', '昨值下']
    const priceOk = x.keys.filter(k => exp[k.label] != null).every(k => Math.abs(k.price - exp[k.label]) < 1e-6)
    ok(`关键价位 ${iv}：${wantL.length} 条都有、价位与币安日线（UTC 0 点 = 上海 8 点换日）对得上`, wantL.every(w => labels.includes(w)) && labels.length === wantL.length && priceOk,
      `${labels.join(' ')}；画出 ${x.keys.map(k => `${k.label}@${k.price}`).join(' ')}；期望 ${Object.entries(exp).map(([k, v]) => `${k}@${v}`).join(' ')}`)
    // 视图拉到把所有线都装进来：Alt 滚轮缩价格轴
    await page.mouse.move(5, 700); await wait(400)
    await shot(`A-关键价位-${iv}`)
  }
  ok('关键价位：控制台无报错', errors.length === e0, errors.slice(e0, e0 + 5).join(' | '))
}

// ═════════════════ 旧版 / 损坏的本机存档 ═════════════════
async function modeOldState() {
  const e0 = errors.length
  // 2026-09-29 16:05 第一阶段的形状：四图、老提醒（price/fr/oi）、老画线（没有线型）、没有 slots 之后加的字段
  const draw = { id: 'old1', type: 'trend', pts: [{ t: Date.now() - 20 * 36e5, p: 60000 }, { t: Date.now() - 5 * 36e5, p: 65000 }], color: '#2962FF', width: 2 }
  const v1 = {
    theme: 'dark', skin: 'terra', updown: 'green-up', route: 'direct', layout: '4',
    cells: [{ symbol: 'ETHUSDT', iv: '15m' }, { symbol: 'SOLUSDT', iv: '1h' }, { symbol: 'BTCUSDT', iv: '4h' }, { symbol: 'DOGEUSDT', iv: '1d' }], active: 2,
    pinned: ['1m', '5m', '15m', '1h', '4h', '1d', '1w'], panel: 'watch', watchTab: 'crypto',
    watch: { crypto: ['BTCUSDT', 'ETHUSDT', 'PEPEUSDT'], stock: ['NVDAUSDT'], metal: ['XAUUSDT'] },
    ind: { ma: true, ema: true, boll: false, vol: true, subs: ['macd', 'kdj'] }, params: null,
    drawings: { BTCUSDT: [draw] }, alerts: [{ id: 'a1', symbol: 'BTCUSDT', kind: 'price', created: Date.now() - 1e6, price: 150000, dir: 1 }],
    notes: [{ id: 'n1', symbol: 'BTCUSDT', iv: '1h', t: Date.now() - 36e5, p: 60000, text: '旧笔记' }],
    magnet: true, drawHidden: false, drawLocked: false, drawColor: '#FF0000', alertScope: 'symbol', meSection: 'look',
    slots: { ladder: false, drawer: false, widgets: ['watch', 'detail'] },
  }
  const cases = [
    ['第一阶段（16:05）的四图老存档', v1, s => s.layout === '4' && s.cells.length >= 4 && s.cells[0].symbol === 'ETHUSDT' && s.watch.crypto.includes('ETHUSDT') && s.drawings.BTCUSDT?.[0]?.id === 'old1' && Array.isArray(s.customIvs) && s.orderFlow === false && s.skin === 'terra'],
    ['多图扩到 16 格之前的八图（当时最多 8）', { ...v1, layout: '8', cells: v1.cells.concat([{ symbol: 'XRPUSDT', iv: '5m' }]) }, s => s.layout === '8' && s.cells.length >= 8],
    ['cells 里有洞和坏项', { ...v1, layout: '9', cells: [{ symbol: 'ETHUSDT', iv: '15m' }, null, { symbol: 42 }, { iv: '1h' }, 'x'] }, s => s.layout === '9' && s.cells.slice(0, 9).every(c => c && typeof c.symbol === 'string' && typeof c.iv === 'string')],
    ['cells 里有不存在的周期', { ...v1, layout: '2', cells: [{ symbol: 'ETHUSDT', iv: '7x' }, { symbol: 'BTCUSDT', iv: '' }] }, s => s.cells.slice(0, 2).every(c => /^(\d+[smhdwM])$/.test(c.iv))],
    ['pinned 不是数组', { ...v1, pinned: 'abc' }, s => Array.isArray(s.pinned) && s.pinned.length > 0],
    ['pinned 里有坏周期', { ...v1, pinned: ['1m', 'zz', 5, '4h'] }, s => Array.isArray(s.pinned) && s.pinned.every(x => /^\d+[mhdwM]$/.test(x))],
    ['watch 各类不是数组', { ...v1, watch: { crypto: 'BTCUSDT', stock: null, metal: 5 } }, s => Object.values(s.watch).every(Array.isArray)],
    ['ind.subs 里有不存在的副图', { ...v1, ind: { ma: true, vol: true, subs: ['macd', 'nope', 7] } }, s => s.ind.subs.every(x => ['macd', 'rsi', 'kdj', 'oi', 'cvd', 'whale', 'atr', 'obv', 'ls', 'fr', 'wr', 'cci', 'dmi', 'mfi', 'stochrsi', 'trix', 'roc', 'mom'].includes(x) || typeof x === 'string')],
    ['panel / watchTab / active 乱填', { ...v1, panel: 'nope', watchTab: 'zzz', active: 'x', lastPanel: 3 }, s => s.active === 0],
    ['params 形状不对', { ...v1, params: { ma: 'x', macd: { fast: 'a' }, boll: null } }, () => true],
    ['drawStyles / recentColors / toolLast 形状不对', { ...v1, drawStyles: { line: 'red', shape: { color: 5, width: 'x' } }, recentColors: ['red', '#12345G', '#AABBCC'], toolLast: { line: 5 } }, () => true],
    ['slots.widgets 里有未知块', { ...v1, slots: { ladder: 'yes', drawer: 1, widgets: ['watch', 'zzz', 'detail', 'detail'] } }, s => Array.isArray(s.slots.widgets)],
    ['数字当布局', { ...v1, layout: 4 }, s => ['1', '4'].includes(s.layout)],
    ['整个是数组', [1, 2, 3], s => s.layout === '1'],
    ['截断的 JSON', JSON.stringify(v1).slice(0, 200), s => s.layout === '1'],
    ['null', 'null', s => s.layout === '1'],
  ]
  for (const [name, v, check] of cases) {
    const e1 = errors.length
    await toBlank(); await pace()
    await page.evaluate(x => { __keepGate(localStorage); localStorage.setItem('hkline-web-v1', typeof x === 'string' ? x : JSON.stringify(x)) }, v)
    let loaded = true
    try { await page.goto(`${URL_}#chart`, { waitUntil: 'domcontentloaded' }); await ready() } catch { loaded = false }
    const blank = await page.evaluate(() => !document.querySelector('.chart-cell canvas') || !document.querySelector('#toolbar #tbSymbol'))
    const cs = loaded ? await cellsNow().catch(() => []) : []
    // 页面自己存一次再读回来
    await page.evaluate(() => window.dispatchEvent(new Event('beforeunload')))
    const s = await state()
    let pass = false
    try { pass = check(s) } catch { pass = false }
    const errs = errors.slice(e1)
    ok(`旧存档「${name}」：不白屏、各格有图、缺的字段补默认`, loaded && !blank && cs.length > 0 && cs.every(c => c.bars > 0 || c.empty) && pass && !errs.length,
      `${loaded ? '' : '加载超时 '}${blank ? '白屏 ' : ''}格子 ${cs.length}（${cs.map(c => `${c.symbol}/${c.iv}:${c.bars}`).join(' ')}）${errs.length ? ' 报错 ' + errs.slice(0, 2).join(' | ') : ''}${pass ? '' : ' 存档没补好 ' + JSON.stringify({ layout: s.layout, cells: s.cells?.slice(0, 3), pinned: s.pinned, watch: s.watch, subs: s.ind?.subs, active: s.active }).slice(0, 300)}`)
    if (name.startsWith('第一阶段')) {
      const sv = await state()
      ok('旧存档：老提醒补成同步形状、老画线与笔记都在', sv.alerts?.length === 1 && sv.alerts[0].kind === 'price' && sv.alerts[0].symbol === 'BTCUSDT' && sv.alerts[0].lines?.[0]?.points?.[0]?.p === 150000 && sv.drawings.BTCUSDT?.length === 1 && sv.notes?.[0]?.id === 'n1', JSON.stringify({ a: sv.alerts?.[0]?.lines, d: sv.drawings?.BTCUSDT?.length, n: sv.notes?.length }).slice(0, 300))
      await shot('A-旧存档-第一阶段四图')
    }
  }
  ok('旧存档：控制台无报错', errors.length === e0, errors.slice(e0, e0 + 5).join(' | '))
}

// ═════════════════ 300 次随机高频切换 ═════════════════
async function modeHf(n = 300) {
  const e0 = errors.length, f0 = netFail.length
  await seed(null, 'layout=4&s=BTCUSDT&i=1h&panel=watch')
  await gc(); const h0 = (await cdp.send('Runtime.getHeapUsage')).usedSize
  const ops = []
  const LAYLAB = LAYS.map(x => x[1])
  for (let k = 0; k < n; k++) {
    const r = Math.random()
    let op
    try {
      if (r < 0.25) {
        op = 'sym'; const rows = page.locator('#wTbl tr[data-sym]'); const c = await rows.count()
        if (c) await rows.nth(Math.floor(Math.random() * c)).click({ timeout: 1000 }); else { await page.keyboard.press('Meta+k'); await page.keyboard.type(rnd(SYMS).replace('USDT', '')); await page.keyboard.press('Enter') }
      } else if (r < 0.45) { op = 'iv'; await page.mouse.move(1200, 700); await page.keyboard.press(String(1 + Math.floor(Math.random() * 7))) }
      else if (r < 0.58) { op = 'layout'; await page.click('#tbLayout', { timeout: 1000 }); await page.locator('.menu .mi', { hasText: rnd(LAYLAB) }).first().click({ timeout: 1000 }) }
      else if (r < 0.68) { op = 'theme'; await page.click('#hdrTheme', { timeout: 1000 }) }
      else if (r < 0.80) { op = 'panel'; const b = page.locator('#rail button[data-panel]'); const c = await b.count(); if (c) await b.nth(Math.floor(Math.random() * c)).click({ timeout: 1000 }) }
      else if (r < 0.88) { op = 'cell'; const c = await page.locator('.chart-cell').count(); const cb = await page.locator('.chart-cell').nth(Math.floor(Math.random() * c)).boundingBox(); if (cb) await page.mouse.click(cb.x + cb.width * 0.3, cb.y + cb.height * 0.4) }
      else if (r < 0.94) { op = 'wheel'; await page.mouse.move(900, 600); await page.mouse.wheel(0, (Math.random() - 0.5) * 600) }
      else { op = 'esc'; await page.keyboard.press('Escape') }
    } catch (e) { op += '(点不到)' }
    ops.push(op)
    await wait(50 + Math.random() * 100)
  }
  await page.keyboard.press('Escape')
  log(`操作完那一刻的限流闸：${JSON.stringify(await page.evaluate(() => window.__limit?.()))}`)
  // 最后固定落到十六图，再等画面追上存档：一分钟权重被前面的切换用满时新格子要排队，排队要有尽头（≤ 60 秒）
  await pickLayout('十六图').catch(() => {})
  const LN = { '1': 1, '2': 2, '2v': 2, '3': 3, '4': 4, '6': 6, '8': 8, '9': 9, '12': 12, '16': 16 }
  const tS = Date.now()
  let cs, s, mismatch
  for (;;) {
    await wait(2000)
    cs = await cellsNow(); s = await state()
    mismatch = cs.map((c, i) => ({ i, c, cfg: s.cells[i] })).filter(({ c, cfg }) => !cfg || c.symbol !== cfg.symbol || c.iv !== cfg.iv || c.metaSym !== cfg.symbol || c.metaIv !== IV_MS[cfg.iv] || !c.bars)
    if (!mismatch.length || Date.now() - tS > 60000) break
  }
  const settle = Date.now() - tS
  log(`十六图画面追上存档用了 ${(settle / 1000).toFixed(0)} 秒；限流闸 ${JSON.stringify(await page.evaluate(() => window.__limit?.()))}`)
  ok('高频切换后换到十六图：60 秒内每格都画上自己的品种周期', !mismatch.length, `${(settle / 1000).toFixed(0)} 秒`)
  const sn = await streamNow(), w = await ws()
  const nCells = await page.locator('.chart-cell').count()
  ok(`${n} 次高频切换后：格子数 = 布局、每格画面与存档一致`, nCells === LN[s.layout] && cs.length === nCells && mismatch.length === 0, `布局 ${s.layout} 格子 ${nCells}；不一致 ${mismatch.slice(0, 4).map(({ i, c, cfg }) => `#${i} 存 ${cfg?.symbol}/${cfg?.iv} 图 ${c.metaSym}/${c.metaIv} ${c.bars} 根`).join('；') || '无'}`)
  const px = await page.evaluate(ss => ss.map(x => window.__px?.(x) ?? null), cs.map(c => c.symbol))
  const off = cs.map((c, i) => ({ i, s: c.symbol, last: c.last, p: px[i] })).filter(x => x.p && x.last && Math.abs(x.last / x.p - 1) > 0.015)
  ok('高频切换后：每格最后一根收盘价 ≈ 这只品种最新价（没串数据）', off.length === 0, off.map(x => `#${x.i} ${x.s} 收 ${x.last} 价 ${x.p}`).join('；') || `${cs.length} 格都对`)
  const wantStreams = new Set(cs.flatMap(c => [`${c.symbol.toLowerCase()}@kline_${c.iv}`, `${c.symbol.toLowerCase()}@ticker`]))
  const missing = [...wantStreams].filter(x => !sn.subscribed.includes(x))
  const market = w.live.filter(l => /market\/stream/.test(l.url))
  ok('高频切换后：每格的 K 线与行情流都订着、行情连接 ≤ ⌈流数/200⌉', missing.length === 0 && market.length <= Math.max(1, Math.ceil(sn.subscribed.length / 200)), `缺 ${missing.join(',') || '无'}；连接 ${market.length} 条 ${sn.conns.join('/')} 路；开过 ${w.opened}`)
  const tb = await page.evaluate(() => document.querySelector('#tbSymbol > span:not(.kind):not(.badge)')?.textContent)
  ok('高频切换后：顶栏品种 = 当前格', tb === s.cells[s.active]?.symbol, `${tb} / ${s.cells[s.active]?.symbol}`)
  await gc(); const h1 = (await cdp.send('Runtime.getHeapUsage')).usedSize
  log(`堆 ${(h0 / 1e6).toFixed(1)} → ${(h1 / 1e6).toFixed(1)} MB；操作分布 ${Object.entries(ops.reduce((a, o) => (a[o] = (a[o] || 0) + 1, a), {})).map(([k, v]) => `${k}×${v}`).join(' ')}`)
  const errs = errors.slice(e0)
  ok('高频切换：没有控制台报错 / 未捕获异常', errs.length === 0, errs.slice(0, 6).join(' | '))
  const nf = netFail.slice(f0).filter(x => !/ERR_ABORTED/.test(x))
  ok('高频切换：没有网络失败（被中止的请求除外）', nf.length === 0, `${nf.length} 条 ${nf.slice(0, 4).join(' | ')}；中止 ${netFail.slice(f0).length - nf.length} 条`)
  await shot('A-高频切换之后')
}

// ═════════════════ 断网重连 ═════════════════
async function modeOffline(times = +(process.env.OFFLINE_N || 5)) {
  const e0 = errors.length
  await seed(null, 'layout=4&i=1m&panel=watch')
  await wait(5000)
  for (let k = 0; k < times; k++) {
    const before = await cellsNow()
    const tOff = Date.now()
    await ctx.setOffline(true)
    await wait(8000)
    const mid = await page.evaluate(() => ({ stale: document.body.classList.contains('stale'), dot: document.querySelector('.conn-dot')?.dataset.conn, st: window.__stream().state }))
    await wait(Math.max(0, 30000 - (Date.now() - tOff) + (k % 2 ? 35000 : 0)))   // 单数次多断一会儿，跨过整分钟
    const offMs = Date.now() - tOff
    await ctx.setOffline(false)
    const tOn = Date.now()
    const back = await until(async () => { const s = await streamNow(); return s.state === 'open' && s.subscribed.length ? s : null }, 20000, 250)
    const reMs = Date.now() - tOn
    await wait(4000)
    const after = await cellsNow(), sn = await streamNow()
    const want = new Set(after.flatMap(c => [`${c.symbol.toLowerCase()}@kline_${c.iv}`, `${c.symbol.toLowerCase()}@ticker`]))
    const miss = [...want].filter(x => !sn.subscribed.includes(x))
    // 缺口：每格的 1 分钟 K 线在断网这段时间里要一根不少（和币安 REST 对照）
    const px = await page.evaluate(ss => ss.map(x => window.__px(x)), after.map(c => c.symbol))
    const gaps = after.map((c, i) => ({ symbol: c.symbol, iv: c.iv, holes: c.holes > (before[i]?.holes ?? 0) ? [`${before[i]?.holes}→${c.holes}`] : [], lastOk: !!px[i] && Math.abs(c.last / px[i] - 1) < 0.003 && Date.now() - c.lastT < 2 * IV_MS[c.iv], lastInfo: `${c.last} vs ${px[i]} 末根 ${Math.round((Date.now() - c.lastT) / 1000)} 秒前` }))
    const stale = await page.evaluate(() => document.body.classList.contains('stale'))
    ok(`断网 #${k + 1}（${Math.round(offMs / 1000)} 秒）：断着时变灰、恢复后 ${(reMs / 1000).toFixed(1)} 秒内重连、补订 ${want.size} 路`, mid.stale && !!back && reMs < 8000 && !miss.length && !stale, `断着 ${JSON.stringify(mid)}；缺订 ${miss.join(',') || '无'}；恢复后仍灰 ${stale}`)
    ok(`断网 #${k + 1}：K 线把断网期间的缺口补齐（每格相邻两根都差一个周期、最后一根收盘价对得上）`, gaps && gaps.every(g => !g.holes.length && g.lastOk), gaps ? gaps.map(g => `${g.symbol}/${g.iv} 洞 ${g.holes.length}${g.holes.length ? '(' + g.holes.slice(0, 2).join(',') + ')' : ''} 末根${g.lastOk ? '对' : '错 ' + g.lastInfo}`).join('；') : '没有 __gaps')
    // 最新价恢复跳动
    const p0 = await page.evaluate(() => document.title)
    const moved = await until(async () => (await page.evaluate(() => document.title)) !== p0, 15000, 500)
    ok(`断网 #${k + 1}：最新价恢复跳动`, !!moved, `${p0}`)
  }
  await shot('A-断网恢复之后')
  const errs = errors.slice(e0).filter(x => !/ERR_INTERNET_DISCONNECTED|Failed to fetch|net::ERR/.test(x))
  ok('断网：除断网本身的请求失败外没有报错', errs.length === 0, errs.slice(0, 5).join(' | '))
}

// ═════════════════ 画满 500 条 ═════════════════
async function modeDraw500() {
  const e0 = errors.length
  const sym = 'LINKUSDT'
  await seed(null, `layout=1&s=${sym}&i=1h&panel=watch`)
  const bars = await page.evaluate(() => window.__cells()[0].bars)
  // 直接往存档里塞 499 条各种类型的画线（真实用户一条条画出来的形状）
  const lastT = await page.evaluate(() => window.__ind(0).t0)
  const types = ['trend', 'ray', 'hline', 'vline', 'rect', 'fib', 'avwap', 'fvp', 'position']
  await page.evaluate(([sym, t0, types]) => {
    const s = JSON.parse(localStorage.getItem('hkline-web-v1'))
    const H = 36e5, list = []
    const base = window.__px?.(sym) || 20
    for (let i = 0; i < 499; i++) {
      const ty = types[i % types.length], a = t0 + (100 + (i % 800)) * H, p = base * (0.9 + (i % 97) / 500)
      const pts = ty === 'hline' || ty === 'vline' || ty === 'avwap' ? [{ t: a, p }] : ty === 'position' ? [{ t: a, p }, { t: a + 20 * H, p: p * 1.03 }, { t: a + 20 * H, p: p * 0.985 }] : [{ t: a, p }, { t: a + 30 * H, p: p * 1.02 }]
      list.push({ id: 'z' + i, type: ty, pts, color: '#2962FF', width: 1 + (i % 3), ...(i % 5 === 0 ? { dash: 'dashed' } : {}) })
    }
    s.drawings = { [sym]: list }
    localStorage.setItem('hkline-web-v1', JSON.stringify(s))
  }, [sym, lastT, types])
  await open(`layout=1&s=${sym}&i=1h&panel=watch`)
  await cdp.send('Performance.enable')
  const box = await page.locator('.chart-cell canvas').first().boundingBox()
  // 悬停扫一遍 + 平移：量主线程忙了多久、有没有卡顿的长任务。
  // 不量 rAF 帧间隔——无头 Chrome 的 rAF 被节流量化，0 条画线时 p95 也是 133 ms，量不出 app 自己的开销（2026-09-29 实测）
  const m0 = Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map(m => [m.name, m.value])), w0 = Date.now()
  await page.evaluate(() => { window.__lt = []; new PerformanceObserver(l => l.getEntries().forEach(e => window.__lt.push(e.duration))).observe({ type: 'longtask' }) })
  for (let k = 0; k < 60; k++) await page.mouse.move(box.x + 100 + k * 25, box.y + 200 + (k % 7) * 30)
  await page.mouse.move(box.x + 1200, box.y + 400); await page.mouse.down(); await page.mouse.move(box.x + 700, box.y + 380, { steps: 30 }); await page.mouse.up()
  await wait(500)
  const m1 = Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map(m => [m.name, m.value])), w1 = Date.now()
  const lt = await page.evaluate(() => window.__lt)
  const busy = (m1.TaskDuration - m0.TaskDuration) * 1000 / (w1 - w0), longest = Math.max(0, ...lt)
  ok('499 条画线：悬停与平移时主线程占用 ≤ 50%、没有超过 100 ms 的长任务', busy <= 0.5 && longest <= 100,
    `占用 ${Math.round(busy * 100)}%（空图约 6%），脚本 ${Math.round((m1.ScriptDuration - m0.ScriptDuration) * 1000)} ms / ${w1 - w0} ms，长任务 ${lt.length} 个、最长 ${Math.round(longest)} ms`)
  // 再画两条：第 500 条成、第 501 条提示上限
  await page.keyboard.press('Alt+h'); await wait(150)
  await page.mouse.click(box.x + 600, box.y + 300); await wait(400)
  await page.keyboard.press('Alt+h'); await wait(150)
  await page.mouse.click(box.x + 650, box.y + 350); await wait(400)
  const n = (await state()).drawings[sym].length
  const toast = await page.evaluate(() => [...document.querySelectorAll('#toasts .toast')].map(e => e.textContent).join(' | '))
  ok('第 500 条能画、第 501 条被拦并提示上限', n === 500 && /上限/.test(toast), `${n} 条；${toast.slice(0, 120)}`)
  // 存档大小
  const bytes = await page.evaluate(() => localStorage.getItem('hkline-web-v1').length)
  log(`存档 ${Math.round(bytes / 1024)} KB`)
  // 全部画线删除 → 撤销 → 重做
  await page.click('#drawbar [data-dact="clear"]'); await wait(300); await menuClick('全部画线'); await wait(400)
  const n0 = (await state()).drawings[sym].length
  await page.keyboard.press('Meta+z'); await wait(500)
  const n1 = (await state()).drawings[sym].length
  await page.keyboard.press('Meta+y'); await wait(500)
  const n2 = (await state()).drawings[sym].length
  await page.keyboard.press('Meta+z'); await wait(500)
  const n3 = (await state()).drawings[sym].length
  ok('500 条「全部画线」删 → 撤销 → 重做 → 撤销', n0 === 0 && n1 === 500 && n2 === 0 && n3 === 500, `${n0} / ${n1} / ${n2} / ${n3}`)
  // 隐藏 / 锁定 / 刷新 / 切品种回来
  await page.mouse.click(box.x + 400, box.y + 400)
  await page.keyboard.press('Meta+Alt+h'); await wait(400)
  const hid = (await state()).drawHidden
  await page.keyboard.press('Meta+Alt+h'); await wait(400)
  await page.reload({ waitUntil: 'domcontentloaded' }); await ready()
  const n4 = (await state()).drawings[sym].length
  await page.keyboard.press('Meta+k'); await page.keyboard.type('ETH'); await wait(300); await page.keyboard.press('Enter'); await wait(1500)
  await page.keyboard.press('Meta+k'); await page.keyboard.type('LINK'); await wait(300); await page.keyboard.press('Enter'); await wait(1500)
  const n5 = (await state()).drawings[sym].length
  ok('隐藏开关、刷新、切品种回来后 500 条都在', hid === true && n4 === 500 && n5 === 500, `隐藏 ${hid}，刷新后 ${n4}，切回 ${n5}`)
  await page.evaluate(sym => { const s = JSON.parse(localStorage.getItem('hkline-web-v1')); delete s.drawings[sym]; localStorage.setItem('hkline-web-v1', JSON.stringify(s)) }, sym)
  await cdp.send('Performance.disable')
  ok('500 条：控制台无报错', errors.length === e0, errors.slice(e0, e0 + 5).join(' | '))
  void bars
}

// ═════════════════ 同账号两个标签页 ═════════════════
const ACCOUNT_KEY = 'hkline-web-account-v1'
/** 用这个页面自己的会话调接口（令牌从 localStorage 读） */
const api = (pg, method, path) => pg.evaluate(async ([m, p, k]) => {
  const v = JSON.parse(localStorage.getItem(k) || 'null')
  const r = await fetch(p, { method: m, headers: v ? { Authorization: 'Bearer ' + v.accessToken } : {}, cache: 'no-store' })
  let j = null; try { j = await r.json() } catch { /* 不是 JSON */ }
  return { status: r.status, data: j?.data ?? null }
}, [method, path, ACCOUNT_KEY])
async function uiLogin(pg) {
  await pg.goto(`${URL_}#me`, { waitUntil: 'domcontentloaded' }); await pg.waitForTimeout(1500)
  await pg.click('[data-me="account"]'); await pg.waitForTimeout(300)
  if (await pg.locator('#acctLogout').count()) return true
  await pg.click('[data-auth="login"]')
  await pg.fill('#acctUser', KP_USER); await pg.fill('#acctPass', KP_PASS); await pg.click('#acctGo')
  for (let k = 0; k < 40; k++) { await pg.waitForTimeout(250); if (await pg.evaluate(k => !!localStorage.getItem(k), ACCOUNT_KEY)) return true }
  return false
}
/** 云端这只品种的画线：id → { deleted, price } */
async function cloudDraws(pg, sym) {
  const r = await api(pg, 'GET', `/v1/sync/bootstrap?collection=drawings&prefix=${encodeURIComponent('binance/usd_m/' + sym + '/')}`)
  const out = {}
  for (const o of r.data?.objects || []) out[o.id.split('/').pop()] = o.deleted ? 'deleted' : 'live'
  return { status: r.status, out }
}
async function modeMultitab() {
  const e0 = errors.length
  if (!KP_PASS) { ok('两个标签页（要 KP_PASS）', false, '没给 KP_PASS'); return }
  const sym = 'AVAXUSDT'
  const A = page
  await A.goto(URL_, { waitUntil: 'domcontentloaded' }); await A.evaluate(() => __keepGate(localStorage))
  ok('标签页 A 登录', await uiLogin(A))
  // 云端先清掉这只的画线（上一轮留下的）
  const B = await ctx.newPage(); watchPage(B, 'B:')
  await A.goto(`${URL_}?s=${sym}&i=1h&layout=1&panel=watch#chart`, { waitUntil: 'domcontentloaded' }); await ready(A)
  await B.goto(`${URL_}?s=${sym}&i=1h&layout=1&panel=watch#chart`, { waitUntil: 'domcontentloaded' }); await ready(B)
  const disk = pg => pg.evaluate(s => { const v = JSON.parse(localStorage.getItem('hkline-web-v1')); return { d: (v.drawings[s] || []).filter(x => x.type !== 'measure'), watch: v.watch.crypto, subs: v.ind.subs } }, sym)
  const box = await A.locator('.chart-cell canvas').first().boundingBox()
  // B 路的多标签页规矩（store.ts tabGuard）：最近被人动过的那页为准，旧页不再写盘，人一回到旧页（焦点 / 可见 / 点按）就整页重载。
  // 所以每次换到另一页先按一下 Shift（没有功能的键）：旧页在这一下就重载，等它起来再真的操作
  const reloads = []
  const activate = async pg => {
    await pg.evaluate(() => { window.__mark = 1 }).catch(() => {})
    await pg.bringToFront(); await pg.keyboard.press('Shift'); await pg.waitForTimeout(500)
    const alive = await pg.evaluate(() => window.__mark === 1).catch(() => false)
    if (!alive) { await pg.waitForLoadState('domcontentloaded'); await ready(pg); reloads.push(pg === A ? 'A' : 'B') }
    return !alive
  }
  const hline = async (pg, y) => { await activate(pg); await pg.mouse.move(box.x + 300, box.y + 300); await pg.keyboard.press('Alt+h'); await pg.waitForTimeout(150); await pg.mouse.click(box.x + 700, box.y + y); await pg.waitForTimeout(500); await pg.keyboard.press('Escape') }
  const poke = async pg => { await activate(pg); await pg.mouse.move(box.x + 900, box.y + 600); await pg.keyboard.press(rnd(['2', '3', '4'])); await pg.waitForTimeout(600) }
  // 1. A 画一条，B 随手换个周期（整份存盘）：A 的线不能从盘上消失
  await hline(A, 300)
  const idA = (await disk(A)).d.at(-1)?.id
  await poke(B)
  let dk = await disk(B)
  ok('A 画的线：B 换周期（整份存盘）之后还在本机存档里', dk.d.some(d => d.id === idA), `盘上 ${dk.d.length} 条`)
  // B 画一条，A 换周期：两条都在
  await hline(B, 420)
  const idB = (await disk(B)).d.find(d => d.id !== idA)?.id
  await poke(A)
  dk = await disk(A)
  ok('B 画的线：A 换周期后两条都在、没有重复', dk.d.length === 2 && new Set(dk.d.map(d => d.id)).size === 2 && dk.d.some(d => d.id === idB), `盘上 ${dk.d.map(d => d.id).join(',')}`)
  // 2. A 加自选 DOGE（⌘K、⇧回车），B 换周期：自选还在
  const had = (await disk(A)).watch.includes('DOGEUSDT')
  await activate(A); await A.keyboard.press('Meta+k'); await A.waitForTimeout(300); await A.keyboard.type('DOGE')
  await A.waitForSelector('[data-w="DOGEUSDT"]', { timeout: 5000 }).catch(() => {}); await A.waitForTimeout(300); await A.keyboard.press('Shift+Enter'); await A.waitForTimeout(300); await A.keyboard.press('Escape')
  const nowHas = (await disk(A)).watch.includes('DOGEUSDT')
  await poke(B)
  ok('A 改自选：B 存盘后不被改回去', nowHas !== had && (await disk(B)).watch.includes('DOGEUSDT') === nowHas, `A 前 ${had} 后 ${nowHas}，B 存盘后 ${(await disk(B)).watch.includes('DOGEUSDT')}`)
  // 3. 云端：两条线都推上去（领头只有一个标签页，另一个页的改动由领头推）
  const t0 = Date.now()
  const up = await until(async () => { const c = await cloudDraws(A, sym); return c.out[idA] === 'live' && c.out[idB] === 'live' ? c : null }, 30000, 1500)
  ok('两个标签页各画的线都上了云端', !!up, up ? `${Date.now() - t0} ms` : JSON.stringify((await cloudDraws(A, sym)).out))
  // 4. 同一条线两边几乎同时拖：最后两边一致、只有一条
  const dragLine = async (pg, dy) => { await pg.bringToFront(); await pg.mouse.move(box.x + 500, box.y + 300); await pg.mouse.down(); await pg.mouse.move(box.x + 500, box.y + 300 + dy, { steps: 5 }); await pg.mouse.up(); await pg.waitForTimeout(100) }
  await activate(A); await activate(B)
  await Promise.all([dragLine(A, 60), dragLine(B, -60)])
  await A.waitForTimeout(1500)
  await poke(A); await poke(B)
  const [dA, dB] = [await disk(A), await disk(B)]
  const pA = dA.d.find(d => d.id === idA)?.pts[0].p
  ok('同一条线两边同时拖：盘上只有一份、两条线都还在', dA.d.length === 2 && new Set(dA.d.map(d => d.id)).size === 2, `A 盘 ${dA.d.length} 条 idA 价 ${pA}；B 盘 ${dB.d.length} 条`)
  // 5. B 删掉全部画线 → A 也没了、云端两条都成墓碑
  await activate(B); await B.click('#drawbar [data-dact="clear"]'); await B.waitForTimeout(300)
  await B.locator('.menu .mi', { hasText: '全部画线' }).first().click(); await B.waitForTimeout(600)
  await poke(A)
  dk = await disk(A)
  ok('B 删光画线：A 存盘后不复活', dk.d.length === 0, `盘上 ${dk.d.length} 条`)
  const t1 = Date.now()
  const gone = await until(async () => { const c = await cloudDraws(A, sym); return c.out[idA] !== 'live' && c.out[idB] !== 'live' ? c : null }, 30000, 1500)
  ok('删除同步到云端（两条都不再是活的）', !!gone, gone ? `${Date.now() - t1} ms` : JSON.stringify((await cloudDraws(A, sym)).out))
  ok('旧页切回来整页重载（B 路 tabGuard 的设计），重载后读到的是新的', reloads.length > 0, `重载 ${reloads.length} 次：${reloads.join('')}`)
  // 6. 关掉 A，刷新 B（B 当上领头）：云端不能冒出「删除」之外的动作，自选还是 A 改的样子
  await A.close()
  await B.reload({ waitUntil: 'domcontentloaded' }); await ready(B); await B.waitForTimeout(4000); await activate(B)
  ok('A 关掉、B 刷新：自选保持', (await disk(B)).watch.includes('DOGEUSDT') === nowHas)
  // 还原自选
  if (nowHas !== had) { await B.keyboard.press('Meta+k'); await B.waitForTimeout(300); await B.keyboard.type('DOGE'); await B.waitForTimeout(600); await B.keyboard.press('Shift+Enter'); await B.waitForTimeout(300); await B.keyboard.press('Escape'); await B.waitForTimeout(3000) }
  page = B; cdp = await ctx.newCDPSession(page)
  ok('两个标签页：控制台无报错', errors.length === e0, errors.slice(e0, e0 + 5).join(' | '))
}

// ═════════════════ 长时间挂机 ═════════════════
async function modeSoak(min = +(process.env.SOAK_MIN || 25)) {
  const e0 = errors.length
  await seed({ layout: '4', ind: { ma: true, ema: false, boll: false, vol: true, subs: ['macd', 'rsi'], keys: true, vwap: true } }, 'layout=4&i=1m&panel=watch&ladder=1&drawer=0')
  await cdp.send('Performance.enable', { timeDomain: 'timeTicks' })
  const rows = []
  const t0 = Date.now()
  for (let m = 0; m <= min; m++) {
    // 每分钟：一次测量 + 一些操作
    await gc()
    const mt = await metrics(), w = await ws(), sn = await streamNow()
    const row = { m, heapMB: +(mt.JSHeapUsedSize / 1e6).toFixed(1), nodes: mt.Nodes, listeners: mt.JSEventListeners, docs: mt.Documents, wsLive: w.live.length, wsMarket: w.live.filter(x => /\/market\/stream$/.test(x.url) && !x.q).length, wsOpened: w.opened, conns: sn.conns.length, subs: sn.subscribed.length }
    rows.push(row); console.log('  ' + JSON.stringify(row))
    writeFileSync(`${OUT}/soak.json`, JSON.stringify(rows))
    if (m === min) break
    const tEnd = t0 + (m + 1) * 60000
    // 这一分钟里：切几下、隐藏 20 秒再回来（偶数分钟）
    const act = m % 4
    if (act === 0) { for (let k = 0; k < 6; k++) { await page.keyboard.press(String(1 + (k % 7))); await wait(400) } }
    if (act === 1) { await pickLayout(rnd(['一图', '四图', '九图', '十六图'])); await wait(3000); await pickLayout('四图') }
    if (act === 2) {
      await cdp.send('Emulation.setFocusEmulationEnabled', { enabled: false }).catch(() => {})
      await page.evaluate(() => { Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' }); Object.defineProperty(document, 'hidden', { configurable: true, get: () => true }); document.dispatchEvent(new Event('visibilitychange')) })
      await wait(20000)
      const hid = await streamNow()
      await page.evaluate(() => { Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'visible' }); Object.defineProperty(document, 'hidden', { configurable: true, get: () => false }); document.dispatchEvent(new Event('visibilitychange')) })
      console.log(`   隐藏时订阅 ${hid.subscribed.length} 路 / ${hid.conns.length} 条`)
    }
    if (act === 3) { const r = page.locator('#wTbl tr[data-sym]'); const c = await r.count(); for (let k = 0; k < 5 && c; k++) { await r.nth(k % c).click(); await wait(500) } }
    const left = tEnd - Date.now()
    if (left > 0) await wait(left)
  }
  const first = rows[1] || rows[0], last = rows[rows.length - 1]
  const heapUp = rows.slice(1).every((r, i) => i === 0 || r.heapMB >= rows[i].heapMB - 0.05)
  ok(`挂机 ${min} 分钟：堆内存不单调上涨（${first.heapMB} → ${last.heapMB} MB）`, !heapUp || last.heapMB - first.heapMB < 5, rows.map(r => r.heapMB).join(' '))
  ok(`挂机：DOM 节点不持续增长（${first.nodes} → ${last.nodes}）`, last.nodes <= first.nodes * 1.3 + 500, rows.map(r => r.nodes).join(' '))
  ok(`挂机：事件监听器不只增不减（${first.listeners} → ${last.listeners}）`, last.listeners <= first.listeners * 1.3 + 100, rows.map(r => r.listeners).join(' '))
  ok('挂机：WS 连接数始终 ≤ 池上限（⌈订阅数 / 200⌉；只数行情池那几条，订单流与盘口另算）', rows.every(r => r.conns <= Math.max(1, Math.ceil(r.subs / 200)) && r.wsMarket <= r.conns), rows.map(r => `${r.wsMarket}/${r.conns}(全部 ${r.wsLive})`).join(' '))
  await cdp.send('Performance.disable')
  const errs = errors.slice(e0)
  ok('挂机：控制台无报错', errs.length === 0, errs.slice(0, 5).join(' | '))
}

const ALL = { reqs: modeReqs, layouts: modeLayouts, sizes: modeSizes, levels: modeLevels, oldstate: modeOldState, hf: modeHf, offline: modeOffline, draw500: modeDraw500, multitab: modeMultitab, soak: modeSoak }
for (const k of MODES.length ? MODES : Object.keys(ALL)) {
  console.log(`\n══ ${k} ══`)
  try { await ALL[k]() } catch (e) { ok(`${k} 跑完`, false, String(e.stack || e).split('\n').slice(0, 3).join(' ')); await page.screenshot({ path: `${OUT}/失败-${k}.png` }).catch(() => {}) }
}
console.log('\n控制台报错：', errors.length ? '\n' + [...new Set(errors)].slice(0, 30).join('\n') : '0')
console.log('网络失败：', netFail.length ? '\n' + [...new Set(netFail)].slice(0, 20).join('\n') : '0')
console.log(`\n合计 ${results.length} 项，失败 ${results.filter(r => !r.pass).length} 项`)
await browser.close()
