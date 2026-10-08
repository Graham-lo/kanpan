// Hkline 手机网页版 · 压测回归（以手机视口 402×874 DPR 3 把高频与长时间操作跑一遍，断言不漏、不叠、不丢）
//   node scripts/m-stress.mjs [地址] [段落…]
//   段落：panels（面板开关不漏 DOM / 监听）、switch（换品种 / 周期不累积订阅与连接）、offline（断网再联网续上）、
//         sw（Service Worker：第一次打开后就能离线冷启动出壳）
//   默认地址 http://localhost:5190/web/m/（先 npm run build && npx vite preview --port 5190）
//   sw 段要用不带 Vary: Origin 的静态服务器（线上 Caddy 是 Vary: Accept-Encoding）：vite preview 给每个产物都加
//   Vary: Origin，模块脚本请求带 Origin、SW 装时存的不带，caches.match 对不上，断网就取不到——那是本地假象。
//   例：mkdir -p /tmp/srv && ln -sfn $PWD/dist /tmp/srv/web && (cd /tmp/srv && python3 -m http.server 5299)
//       node scripts/m-stress.mjs http://localhost:5299/web/m/ sw
// 每一项打一行「✓ / ✗」，有 ✗ 退出码 1。
import { chromium } from 'playwright-core'

const URL_ = process.argv[2] || 'http://localhost:5190/web/m/'
const PARTS = process.argv.slice(3)
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const want = p => !PARTS.length || PARTS.includes(p)
const sleep = ms => new Promise(r => setTimeout(r, ms))
const results = []
const ok = (name, pass, detail = '') => { results.push(pass); console.log(`${pass ? '✓' : '✗'} ${name}${detail ? ' — ' + detail : ''}`) }

// 注入：window / document / MediaQueryList 上的监听按「目标:类型」记净数，WebSocket 记开关与订阅
const INSTR = () => {
  const add = EventTarget.prototype.addEventListener, rem = EventTarget.prototype.removeEventListener
  const gl = (window.__gl = {})
  const nm = t => t === window ? 'window' : t === document ? 'document' : t instanceof MediaQueryList ? 'mq' : t === window.visualViewport ? 'vv' : null
  EventTarget.prototype.addEventListener = function (ty, f, o) { const n = nm(this); if (n && f) gl[n + ':' + ty] = (gl[n + ':' + ty] || 0) + 1; return add.call(this, ty, f, o) }
  EventTarget.prototype.removeEventListener = function (ty, f, o) { const n = nm(this); if (n && f) gl[n + ':' + ty] = (gl[n + ':' + ty] || 0) - 1; return rem.call(this, ty, f, o) }
  const W = window.WebSocket
  const ws = (window.__ws = { opened: 0, live: new Set(), subs: 0, unsubs: 0 })
  window.WebSocket = class extends W {
    constructor(...a) { super(...a); ws.opened++; ws.live.add(this); this.addEventListener('close', () => ws.live.delete(this)) }
    send(d) { try { const m = JSON.parse(d); if (m.method === 'SUBSCRIBE') ws.subs += m.params.length; if (m.method === 'UNSUBSCRIBE') ws.unsubs += m.params.length } catch { /* 不是 JSON */ } return super.send(d) }
  }
  window.__errs = []
  addEventListener('error', e => window.__errs.push(String(e.message)))
  addEventListener('unhandledrejection', e => window.__errs.push('rej: ' + String(e.reason?.message || e.reason)))
}

// 连接分两类数：行情推送（K 线 / 报价那一条，任何时候只许一条）与主力订单流的逐笔 / 盘口连接。
// 订单流是 2026-10-08 起大单气泡出厂开、五家交易所都接之后的设计：每只按交易所注册表开几条（币安按品种拼进 URL，
// OKX / Coinbase / Bybit 各 category / Hyperliquid 一家一条），换走的那只由 orderflow/keep.ts 留着最多 KEEP_LIMIT（2）只、3 分钟。
// 所以断言写成：行情 = 1 条；订单流涉及的品种 ≤ 1 + 2 只，且每家的连接条数 ≤ 品种数（同一只不重建、不叠）。
const KEEP_LIMIT = 2
const WS_SNAP = () => {
  const flowRe = /\/v1\/market\/ws\/|@depth|@aggTrade|coinbase\.com|okx\.com|bybit\.com|hyperliquid\.xyz/
  const all = [...window.__ws.live], mk = all.filter(s => !flowRe.test(s.url)), flow = all.filter(s => flowRe.test(s.url))
  const syms = new Set(), perVenue = {}
  for (const s of flow) {
    const u = new URL(s.url), m = /streams=([a-z0-9_]+)@/.exec(s.url)
    if (m) syms.add(m[1].replace(/(usdt|usdc|usd_perp|usd)$/, ''))
    const k = m ? `${u.host}${u.pathname}|${m[1]}` : `${u.host}${u.pathname}${u.searchParams.get('category') ? '?' + u.searchParams.get('category') : ''}`
    perVenue[k] = (perVenue[k] || 0) + 1
  }
  return {
    live: all.length, open: all.filter(s => s.readyState === 1).length,
    mkLive: mk.length, mkOpen: mk.filter(s => s.readyState === 1).length,
    flowLive: flow.length, flowSyms: syms.size, flowDup: Object.entries(perVenue).filter(([k, n]) => n > (k.includes('|') ? 1 : Math.max(1, syms.size))).map(([k, n]) => `${k}×${n}`),
    subs: window.__ws.subs, unsubs: window.__ws.unsubs,
  }
}
const flowOk = w => w.flowSyms <= 1 + KEEP_LIMIT && !w.flowDup.length

const browser = await chromium.launch({ executablePath: CHROME, headless: true })
async function page() {
  const ctx = await browser.newContext({ viewport: { width: 402, height: 874 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true, locale: 'zh-CN', timezoneId: 'Asia/Shanghai' })
  await ctx.addInitScript(INSTR)
  const p = await ctx.newPage()
  const cdp = await ctx.newCDPSession(p)
  await cdp.send('Performance.enable')
  p.metrics = async () => {
    await cdp.send('HeapProfiler.collectGarbage'); await cdp.send('HeapProfiler.collectGarbage')
    const m = Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map(x => [x.name, x.value]))
    const gl = await p.evaluate(() => ({ ...window.__gl }))
    return { nodes: m.Nodes, listeners: m.JSEventListeners, heap: m.JSHeapUsedSize / 1048576, gl }
  }
  return { ctx, p }
}
const glDiff = (a, b) => { const d = {}; for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) if ((b[k] || 0) !== (a[k] || 0)) d[k] = (b[k] || 0) - (a[k] || 0); return d }

// ───────── 面板开关：关掉的面板不能被窗口监听攥着
if (want('panels')) {
  const { ctx, p } = await page()
  await p.goto(URL_ + '#chart'); await p.waitForSelector('.cp-gear'); await sleep(2500)
  const open = { 分析: () => [...document.querySelectorAll('.cp-tail')].find(b => b.textContent.includes('分析')).click(), 图表设置: () => document.querySelector('.cp-gear').click(), 更多: () => document.querySelector('.cp-more').click() }
  // 先各开一次，懒加载的模块级监听算进基线
  for (const f of Object.values(open)) { await p.evaluate(f); await sleep(200); await p.evaluate(() => (document.querySelector('.m-sheet-scrim') || document.querySelector('.m-pop-scrim'))?.click()); await sleep(400) }
  for (const [name, f] of Object.entries(open)) {
    const m0 = await p.metrics()
    for (let i = 0; i < 20; i++) {
      await p.evaluate(f); await sleep(120)
      await p.evaluate(() => (document.querySelector('.m-sheet-scrim') || document.querySelector('.m-pop-scrim'))?.click()); await sleep(380)
    }
    const m1 = await p.metrics()
    const d = glDiff(m0.gl, m1.gl)
    ok(`「${name}」开关 20 次不漏`, m1.nodes - m0.nodes < 300 && !Object.keys(d).length, `节点 ${m1.nodes - m0.nodes >= 0 ? '+' : ''}${m1.nodes - m0.nodes}、JS 监听 ${m1.listeners - m0.listeners >= 0 ? '+' : ''}${m1.listeners - m0.listeners}、窗口监听 ${JSON.stringify(d)}`)
  }
  ok('面板段无报错', !(await p.evaluate(() => window.__errs.length)), (await p.evaluate(() => window.__errs.join(' | '))).slice(0, 300))
  await ctx.close()
}

// ───────── 断网再联网、切后台再回来：连接续上、价格重新走、断着时价格变灰（iOS LinkGrace：断满 5 秒算断）
if (want('offline')) {
  const { ctx, p } = await page()
  await p.goto(URL_ + '#chart'); await p.waitForSelector('.cp-price'); await sleep(6000)
  const snap = async () => ({ ...(await p.evaluate(WS_SNAP)), ...(await p.evaluate(() => ({ price: document.querySelector('.cp-price')?.textContent, stale: document.querySelector('.cp-price')?.classList.contains('stale'), opened: window.__ws.opened }))) })
  const brief = w => JSON.stringify({ price: w.price, stale: w.stale, 行情: `${w.mkOpen}/${w.mkLive}`, 订单流: `${w.flowLive} 条 ${w.flowSyms} 只`, 重复: w.flowDup.join(',') || undefined, opened: w.opened })
  const s0 = await snap()
  ok('联网时价格是实时的、行情推送一条', !s0.stale && s0.mkOpen === 1 && s0.mkLive === 1 && flowOk(s0), brief(s0))
  await ctx.setOffline(true)
  await sleep(8000)
  const s1 = await snap()
  ok('断网 8 秒价格变灰', s1.stale === true, brief(s1))
  await ctx.setOffline(false)
  let s2 = s1
  for (let i = 0; i < 20 && !(s2.mkOpen === 1 && !s2.stale); i++) { await sleep(500); s2 = await snap() }
  ok('联网后 10 秒内连上、不再灰、连接不叠', s2.mkOpen === 1 && s2.mkLive === 1 && !s2.stale && flowOk(s2) && s2.flowLive <= s0.flowLive, brief(s2))
  // 切后台：只留核心几路；回前台补回来
  const subsOf = () => p.evaluate(() => ({ subs: window.__ws.subs, unsubs: window.__ws.unsubs }))
  await p.evaluate(() => { Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' }); Object.defineProperty(document, 'hidden', { configurable: true, get: () => true }); document.dispatchEvent(new Event('visibilitychange')) })
  await sleep(4000)
  await p.evaluate(() => { Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'visible' }); Object.defineProperty(document, 'hidden', { configurable: true, get: () => false }); document.dispatchEvent(new Event('visibilitychange')) })
  await sleep(4000)
  const s3 = await snap(), n3 = await subsOf()
  const p0 = s3.price; await sleep(6000); const s4 = await snap()
  ok('切后台再回来行情连接只有一条、订单流不叠、价格照常走', s3.mkLive === 1 && s3.mkOpen === 1 && flowOk(s3) && s3.flowLive <= s0.flowLive && !s4.stale, `${brief(s3)} 订/退 ${JSON.stringify(n3)} 6 秒后 ${s4.price}（之前 ${p0}）`)
  ok('断网段无报错', !(await p.evaluate(() => window.__errs.length)), (await p.evaluate(() => window.__errs.join(' | '))).slice(0, 300))
  await ctx.close()
}

// ───────── 换品种（顶栏价格区横滑）、换周期各 40 次：行情连接始终一条、订单流不叠、订阅不累积、DOM 不涨
// 横滑扫图只在「从自选 / 板块列表点进来」时有名单（照 iOS ScanList：直接开图、搜索进来都不冻结名单），
// 所以从自选页点第一行进图，不能直接开 #chart。
if (want('switch')) {
  const { ctx, p } = await page()
  await p.goto(URL_ + '#favorites'); await p.waitForSelector('.lr[data-sym]'); await sleep(1500)
  const rows = await p.evaluate(() => document.querySelectorAll('.lr[data-sym]').length)
  await p.click('.lr[data-sym]'); await p.waitForSelector('.cp-head'); await sleep(6000)
  const box = await p.locator('.cp-head').boundingBox()
  const ws = () => p.evaluate(WS_SNAP)
  const brief = w => JSON.stringify({ 行情: `${w.mkOpen}/${w.mkLive}`, 订单流: `${w.flowLive} 条 ${w.flowSyms} 只`, 重复: w.flowDup.join(',') || undefined, subs: w.subs, unsubs: w.unsubs })
  const m0 = await p.metrics(), w0 = await ws()
  let dir = -1, done = 0, bounce = 0
  while (done < 40 && bounce < 80) {
    const before = await p.evaluate(() => document.querySelector('.cp-base')?.textContent)
    const y = box.y + box.height / 2, x = box.x + box.width / 2
    await p.mouse.move(x, y); await p.mouse.down(); await p.mouse.move(x + dir * 120, y, { steps: 2 }); await p.mouse.up()
    await sleep(80)
    if (await p.evaluate(() => document.querySelector('.cp-base')?.textContent) === before) { dir = -dir; bounce++ } else done++
  }
  // 换完品种等新那只的订单流连齐，再量换周期前后（同一只，周期换来换去不该新开任何连接）
  await sleep(8000)
  const wA = await ws()
  const ivs = await p.evaluate(() => [...document.querySelectorAll('.cp-chip[data-iv]')].map(b => b.dataset.iv))
  for (let i = 0; i < 40; i++) { await p.evaluate(iv => document.querySelector(`.cp-chip[data-iv="${iv}"]`)?.click(), ivs[i % ivs.length]); await sleep(60) }
  await sleep(4000)
  const m1 = await p.metrics(), w1 = await ws()
  // 在场的订阅 = 净订阅；换来换去之后应当和开始时同一个量级（只剩当前这一只的几路）
  const net0 = w0.subs - w0.unsubs, net1 = w1.subs - w1.unsubs
  ok(`换品种 ${done} 次（自选 ${rows} 只来回扫）`, done >= 20, `撞到头 ${bounce} 次`)
  ok(`换品种后行情一条、订单流只连着正在看的 + 留着的 ≤ ${KEEP_LIMIT} 只`, wA.mkLive === 1 && wA.mkOpen === 1 && flowOk(wA), brief(wA))
  ok('换周期 40 次连接不涨（同一只不重建行情 / 订单流连接）', w1.mkLive === 1 && w1.mkOpen === 1 && w1.live <= wA.live && flowOk(w1), `${brief(wA)} → ${brief(w1)}`)
  ok('订阅不累积', net1 <= net0 + 4, `开始净订阅 ${net0}，结束 ${net1}（订 ${w1.subs} / 退 ${w1.unsubs}）`)
  ok('DOM 不涨', m1.nodes - m0.nodes < 300, `节点 ${m1.nodes - m0.nodes >= 0 ? '+' : ''}${m1.nodes - m0.nodes}、堆 ${m0.heap.toFixed(1)}→${m1.heap.toFixed(1)} MB`)
  ok('换品种段无报错', !(await p.evaluate(() => window.__errs.length)), (await p.evaluate(() => window.__errs.join(' | '))).slice(0, 300))
  await ctx.close()
}

// ───────── Service Worker：第一次打开（四页各走一遍）之后断网，冷启动出壳、四页都进得去
if (want('sw')) {
  const { ctx, p } = await page()
  await p.goto(URL_ + '#chart'); await p.waitForSelector('.cp-head')
  const ready = await p.evaluate(() => navigator.serviceWorker ? navigator.serviceWorker.ready.then(r => !!r.active) : false)
  ok('Service Worker 装好', ready)
  const vary = await p.evaluate(async () => { const s = document.querySelector('script[type=module][src]'); return s ? (await fetch(s.src, { method: 'HEAD' })).headers.get('vary') || '' : '' })
  if (/origin/i.test(vary)) { console.log(`- 跳过断网冷启动：这台服务器给产物加了 Vary: ${vary}（vite preview），换静态服务器再跑，见文件头`); await ctx.close() } else {
  for (const h of ['#favorites', '#sectors', '#me', '#chart']) { await p.evaluate(h => { location.hash = h }, h); await sleep(1200) }
  await sleep(2500) // 让页面把这次实际加载的产物报给 SW 补存
  await ctx.setOffline(true)
  await p.close()
  const q = await ctx.newPage()
  const failed = []
  q.on('requestfailed', r => { const u = r.url(); if (u.includes('/web/') && !u.includes('/v1/') && !u.includes('/market')) failed.push(u.replace(/^.*\/web\//, '')) })
  q.on('pageerror', e => failed.push('err: ' + e.message.slice(0, 120)))
  await q.goto(URL_ + '#chart').catch(e => failed.push('goto: ' + e.message.slice(0, 80)))
  const shell = await q.waitForSelector('.cp-head', { timeout: 8000 }).then(() => true, () => false)
  ok('断网冷启动出壳（行情页）', shell, failed.join(' | ').slice(0, 300))
  const pages = {}
  for (const h of ['#favorites', '#sectors', '#me']) {
    await q.evaluate(h => { location.hash = h }, h); await sleep(1500)
    pages[h] = await q.evaluate(() => { const pg = [...document.querySelectorAll('.page')].find(e => getComputedStyle(e).visibility !== 'hidden' && getComputedStyle(e).display !== 'none'); return pg ? pg.innerText.trim().length : 0 })
  }
  ok('断网时四页都进得去', Object.values(pages).every(n => n > 0) && !failed.some(f => /\.js|\.css/.test(f)), `${JSON.stringify(pages)} ${failed.join(' | ').slice(0, 200)}`)
  await ctx.setOffline(false)
  await sleep(3000) // 让 SW 在断网那段里存下的壳变旧：联网后若还回缓存，Date 会落在断网之前
  const t0 = Date.now()
  const res = await q.reload()
  const age = res ? t0 - Date.parse((await res.headerValue('date')) || '') : NaN
  ok('联网后导航取壳走服务器（新版本不拿旧壳）', !!res && res.status() === 200 && age < 2500, `status ${res?.status()}，壳的 Date 比刷新时刻早 ${age} ms`)
  await ctx.close()
  }
}

await browser.close()
process.exit(results.every(Boolean) ? 0 : 1)
