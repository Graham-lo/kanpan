// Hkline Web · 冷启动首屏与切换权重的量法（2026-09-30，压测遗留项第 2、4 项的验收）
//   node scripts/firstscreen.mjs <地址> cold [每条线路几次=5] [线路=direct,gateway]
//   node scripts/firstscreen.mjs <地址> switch [连切几只=10] [间隔毫秒=150] [heavy]
//   node scripts/firstscreen.mjs <地址> sectors [等几秒=20] [reload]
//     reload：量完再在同一个标签页里刷新一次、同样再量（sessionStorage 里的走势线缓存该让第二次不再取）
//     heavy：先把「主力订单流」与「关键价位」打开（B 路量「每次切换约 33 权重」时的状态）
//
// cold：本机 Chrome 无头、2560×1440、每次新开上下文（无缓存、无本地状态），和 C 路第 5 节同一测法。
//   各列从开始导航算起（performance.now()，毫秒）：
//   DOM 就绪   —— navigation 的 domContentLoadedEventEnd
//   价格出现   —— 标题里第一次出现价格（syncTitle 在品种表到了之后写）
//   K 线结束   —— 第一格那次 /fapi/v1/klines?…limit=1500 的 responseEnd
//   WS 建连    —— 第一条行情 WS（…/market/stream）的 open
//   WS 首帧    —— 这条 WS 上第一帧带数据的推送（不算订阅回执）
//   首次跳价   —— 标题里的价格第一次变（推送改的）
//   打印每次的数与中位数 / 最大值。
// sectors：新上下文直接开板块页，等 N 秒读限流账本（这一次冷启动花了多少币安权重），按主机 + 路径数请求，
//   列出没画出走势线的板块（点名看 比特币生态 / 基础设施 / 粉丝代币 / DeFi 其他）。
// switch：页面停稳后按 ↓ 在自选里连切 N 只（每下隔 M 毫秒），停 4 秒后读限流账本（window.__limit）的增量，
//   再单切一只量一次；另外按主机 + 路径数这段时间发出去的请求。
import { chromium } from 'playwright-core'

const URL_ = process.argv[2] || 'http://localhost:5193/web/'
const MODE = process.argv[3] || 'cold'
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const browser = await chromium.launch({ executablePath: CHROME, headless: true })

const probe = () => {
  const T = { ws: null, frame: null, price: null, tick: null, firstPrice: null }
  window.__fs = T
  const W = window.WebSocket
  window.WebSocket = class extends W {
    constructor(u, p) {
      super(u, p)
      if (!/\/market\/stream/.test(String(u)) || T.wsSeen) return
      T.wsSeen = true
      T.wsCtor = performance.now()
      this.addEventListener('open', () => { T.ws = performance.now() })
      this.addEventListener('message', ev => {
        if (T.frame != null) return
        try { const m = JSON.parse(ev.data); if (m && (m.data || m.e)) T.frame = performance.now() } catch { /* 不是 JSON */ }
      })
    }
  }
  const look = () => {
    const m = /^\S+ ([\d,.]+) /.exec(document.title)
    if (!m) return
    if (T.price == null) { T.price = performance.now(); T.firstPrice = m[1]; return }
    if (T.tick == null && m[1] !== T.firstPrice) T.tick = performance.now()
  }
  const hook = () => {
    const t = document.querySelector('title')
    if (!t) return false
    new MutationObserver(look).observe(t, { childList: true, characterData: true, subtree: true })
    look()
    return true
  }
  if (!hook()) document.addEventListener('DOMContentLoaded', hook)
}

async function coldOnce(route) {
  const ctx = await browser.newContext({ viewport: { width: 2560, height: 1440 }, deviceScaleFactor: 1 })
  if (route === 'gateway') await ctx.addInitScript(() => { if (!localStorage.getItem('hkline-web-v1')) localStorage.setItem('hkline-web-v1', JSON.stringify({ route: 'gateway' })) })
  await ctx.addInitScript(probe)
  const page = await ctx.newPage()
  await page.goto(URL_, { waitUntil: 'domcontentloaded' })
  const t0 = Date.now()
  while (Date.now() - t0 < 15000) {
    const done = await page.evaluate(() => window.__fs && window.__fs.tick != null)
    if (done) break
    await page.waitForTimeout(100)
  }
  const r = await page.evaluate(() => {
    const nav = performance.getEntriesByType('navigation')[0]
    const k = performance.getEntriesByType('resource').find(e => /\/fapi\/v1\/klines\?.*limit=1500/.test(e.name) && !/endTime/.test(e.name))
    const f = window.__fs
    // 品种表那三个（exchangeInfo / ticker/24hr / premiumIndex）：最早发出与最晚到齐，看价格晚是晚在网络还是晚在主线程
    // （每个只取第一次；后面还有定时刷新的同名请求）
    const u = ['exchangeInfo', 'ticker/24hr', 'premiumIndex'].map(p => performance.getEntriesByType('resource').find(e => e.name.endsWith('/fapi/v1/' + p))).filter(Boolean)
    return { dom: nav?.domContentLoadedEventEnd, price: f.price, kline: k?.responseEnd, kStart: k?.startTime, wsCtor: f.wsCtor, ws: f.ws, frame: f.frame, tick: f.tick,
      uStart: u.length ? Math.min(...u.map(e => e.startTime)) : NaN, uEnd: u.length ? Math.max(...u.map(e => e.responseEnd)) : NaN }
  })
  await ctx.close()
  return r
}

const COLS = [['dom', 'DOM 就绪'], ['price', '价格出现'], ['kline', 'K 线结束'], ['ws', 'WS 建连'], ['frame', 'WS 首帧'], ['tick', '首次跳价']]
const med = a => { const s = a.filter(Number.isFinite).sort((x, y) => x - y); if (!s.length) return NaN; const n = s.length; return n % 2 ? s[n >> 1] : (s[n / 2 - 1] + s[n / 2]) / 2 }
const r0 = x => Number.isFinite(x) ? Math.round(x) : '—'

if (MODE === 'cold') {
  const N = +(process.argv[4] || 5)
  const routes = (process.argv[5] || 'direct,gateway').split(',')
  const all = Object.fromEntries(routes.map(r => [r, []]))
  // 两条线路交替跑，免得某一段网络抖动全落在一条上
  for (let i = 0; i < N; i++) for (const route of routes) {
    const r = await coldOnce(route)
    all[route].push(r)
    console.log(`${route} #${i + 1}  ` + COLS.map(([k, n]) => `${n} ${r0(r[k])}`).join('  ') + `  （品种表 ${r0(r.uStart)}→${r0(r.uEnd)}、K 线发出 ${r0(r.kStart)}、new WebSocket ${r0(r.wsCtor)}）`)
  }
  console.log('\n| 线路 | ' + COLS.map(c => c[1]).join(' | ') + ' |')
  console.log('|---|' + COLS.map(() => '---').join('|') + '|')
  for (const route of routes) {
    const xs = all[route]
    console.log(`| ${route} | ` + COLS.map(([k]) => `${r0(med(xs.map(x => x[k])))} / ${r0(Math.max(...xs.map(x => x[k]).filter(Number.isFinite)))}`).join(' | ') + ' |')
  }
} else if (MODE === 'switch') {
  const N = +(process.argv[4] || 10)
  const GAP = +(process.argv[5] || 150)
  const HEAVY = process.argv[6] === 'heavy'
  const ctx = await browser.newContext({ viewport: { width: 2560, height: 1440 }, deviceScaleFactor: 1 })
  if (HEAVY) await ctx.addInitScript(() => {
    if (!localStorage.getItem('hkline-web-v1')) localStorage.setItem('hkline-web-v1', JSON.stringify({ orderFlow: true, ind: { ma: true, ema: false, boll: false, vol: true, subs: ['macd', 'rsi'], keys: true } }))
  })
  const page = await ctx.newPage()
  const reqs = []
  let counting = false
  page.on('request', q => { if (counting) { const u = new URL(q.url()); reqs.push(`${u.host}${u.pathname}`) } })
  await page.goto(URL_, { waitUntil: 'domcontentloaded' })
  await page.waitForFunction(() => /\d/.test(document.title), null, { timeout: 30000 })
  await page.waitForTimeout(8000)
  const lim = () => page.evaluate(() => window.__limit())
  const tally = () => { const m = new Map(); for (const r of reqs) m.set(r, (m.get(r) || 0) + 1); return [...m].sort((a, b) => b[1] - a[1]).map(([k, v]) => `${v}× ${k}`).join('\n    ') }
  // 等上一分钟的账滚出窗口一部分也无妨：只看增量
  await page.mouse.click(1280, 700)
  let a = await lim(); counting = true; reqs.length = 0
  for (let i = 0; i < N; i++) { await page.keyboard.press('ArrowDown'); await page.waitForTimeout(GAP) }
  await page.waitForTimeout(4000)
  let b = await lim(); counting = false
  const title = await page.title()
  console.log(`${HEAVY ? '（订单流 + 关键价位开着）' : ''}连切 ${N} 只（每下隔 ${GAP} ms）后停 4 秒：合约权重 +${b.fapi - a.fapi}、现货权重 +${b.spot - a.spot}，请求 ${reqs.length} 个；停在 ${title}`)
  console.log('    ' + tally())
  await page.waitForTimeout(3000)
  a = await lim(); counting = true; reqs.length = 0
  await page.keyboard.press('ArrowDown')
  await page.waitForTimeout(4000)
  b = await lim(); counting = false
  console.log(`单切一只停 4 秒：合约权重 +${b.fapi - a.fapi}、现货权重 +${b.spot - a.spot}，请求 ${reqs.length} 个`)
  console.log('    ' + tally())
  await ctx.close()
}
if (MODE === 'sectors') {
  const SEC = +(process.argv[4] || 20)
  const RELOAD = process.argv[5] === 'reload'
  const ctx = await browser.newContext({ viewport: { width: 2560, height: 1440 }, deviceScaleFactor: 1 })
  const page = await ctx.newPage()
  const reqs = []
  page.on('request', q => { const u = new URL(q.url()); reqs.push(`${u.host}${u.pathname}`) })
  await page.goto(URL_.replace(/#.*$/, '') + '#sectors', { waitUntil: 'domcontentloaded' })
  await page.waitForTimeout(SEC * 1000)
  let lim = await page.evaluate(() => window.__limit())
  if (RELOAD) {
    console.log(`第一次：合约权重 ${lim.fapi}，K 线请求 ${reqs.filter(r => r.endsWith('/fapi/v1/klines')).length} 个；刷新后：`)
    reqs.length = 0
    const before = lim.fapi
    await page.reload({ waitUntil: 'domcontentloaded' })
    await page.waitForTimeout(SEC * 1000)
    lim = await page.evaluate(() => window.__limit())
    // 限流账本跨刷新留着（localStorage），这里只看刷新后的增量
    lim.fapi -= before
  }
  const rows = await page.evaluate(() => [...document.querySelectorAll('tr[data-sec]')].map(tr => ({ name: tr.querySelector('.sec-name')?.textContent || '' })))
  const m = new Map(); for (const r of reqs) m.set(r, (m.get(r) || 0) + 1)
  console.log(`板块页冷启动 ${SEC} 秒：合约权重 ${lim.fapi}、现货权重 ${lim.spot}；板块 ${rows.length} 个（走势线列 2026-10-10 已删，板块页不再拉成员 K 线）`)
  console.log('    ' + [...m].sort((a, b) => b[1] - a[1]).filter(([k]) => !/\.(js|css|svg|png|woff2?)$/.test(k)).slice(0, 12).map(([k, v]) => `${v}× ${k}`).join('\n    '))
  await ctx.close()
}
await browser.close()
