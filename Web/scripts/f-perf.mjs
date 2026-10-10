// Hkline Web · F 线性能与压测（深度审查 Web，2026-10-05）
//   先 npx vite build，然后 node scripts/f-perf.mjs <段> [参数]；脚本自己起 vite preview（端口 5302），跑完杀掉。
//   一次只开一个浏览器。K 线 REST 用合成数据（scripts/f-lib.mjs mockKlines），WebSocket 走线上网关。
//   对照修前：git worktree add /tmp/f-base <修前提交>，在 /tmp/f-base/Web 里 npm ci && npx vite build，再 F_ROOT=/tmp/f-base/Web node scripts/f-perf.mjs <段>。
//   段：
//     cold        冷启动：PC / 手机 × 空本机 / 重本机（数百自选、满画线、十六图），各 3 次取中位数；首屏请求数、重复请求
//     leak-pc     PC 长会话：切品种 ×200、切周期 ×200、开关指标面板 ×100、翻页 ×50（合成历史 4 万根，约第 29 页取尽，之后的翻页验证到头不再发请求）、十六图开关 ×20；每轮强制 GC 读趋势
//     leak-m      手机长会话：四页进出各 ×50、切品种 ×100、开关面板 ×50
//     idle        挂机：断网 2 分钟再恢复、前后台切换、时间跳变；看重连次数、重复订阅、定时器是否翻倍
//     big         大数据：十六图每格三副图 + 订单流（常态 / 联动十字线 / 滚轮 / 拖动）；一图 1m 往前翻 50 页（7.5 万根）后再量；每帧 p50 / p95、长任务、强制布局
//     hf          手机真页面满载手势（CPU 降速 4 倍）：1m 往前快甩翻页、横甩、捏合、长按十字线；[nova] 用 nova 16 视口
//     server      线上服务端轻量负载：REST 10 路并发 45 秒 + 10 条网关推送 60 秒（只读）
//     storage     本机存储接近 5 MB：每类写入是否降级正确、关键数据不丢、不死循环 [pc|m]
//     sidebar     PC 宽侧栏 300 只自选闲置 2 分钟：持仓额请求数、限流账本写盘（F1 / F2 / F4）
//     tabs-m      手机四页来回点 50 轮：ticker/24hr 全量次数、推送握手次数（F5 / F6 / F7）
//     scan-m      手机顶栏横滑连扫 100 只：行情类请求数、停下那只的首屏 K 线（F8）
//     of5         五家订单流满载（Bybit / HL 按 10-08 录帧速率 ×4 合成）：十六图常态 / 十字线 / 滚轮每帧 p50 / p95，对照不发帧
// 基线数字见 docs/acceptance/深度审查-Web-2026-10-05/F-性能与压测/报告.md
import { preview, launch, INSTR, metrics, line, mockKlines, measure, realPrices, sleep, med, pct, diffGl, PC, M, NOVA, heavyPc, heavyM, newCtx } from './f-lib.mjs'

const SEG = process.argv[2] || 'cold'
const ARG = process.argv.slice(3)
// ───────── cold
async function cold() {
  const { url, stop } = await preview()
  const browser = await launch()
  const out = []
  try {
    const hp = await heavyPc(), hm = await heavyM()
    const cases = [
      ['PC 空本机', PC, null, url + '#chart', 'pc'],
      ['PC 重本机（十六图 / 300 自选 / 1680 条画线）', PC, { 'hkline-web-v1': JSON.stringify(hp) }, url + '#chart', 'pc'],
      ['手机 15 Pro Max 空本机', M, null, url + 'm/', 'm'],
      ['手机 15 Pro Max 重本机（300 自选 / 2000 条画线）', M, { 'hkline-m-v1': JSON.stringify(hm.store), 'hkline-m-drawings-v1': JSON.stringify(hm.drawings) }, url + 'm/', 'm'],
      ['手机 nova 16 空本机', NOVA, null, url + 'm/', 'm'],
    ]
    for (const [name, opt, kv, u, kind] of cases) {
      const runs = []
      for (let r = 0; r < 3; r++) {
        const { ctx, count } = await newCtx(browser, opt, kv || { 'f-empty': '1' })
        const page = await ctx.newPage()
        const reqs = []
        page.on('request', q => { const t = q.resourceType(); if (t === 'fetch' || t === 'xhr' || t === 'script' || t === 'websocket' || t === 'stylesheet' || t === 'document') reqs.push({ t, u: q.url() }) })
        const cdp = await ctx.newCDPSession(page)
        await cdp.send('Performance.enable')
        await page.goto(u, { waitUntil: 'domcontentloaded' })
        if (kind === 'pc') await page.waitForFunction(() => window.__cells?.()?.[0]?.bars > 0, null, { timeout: 30000 }).catch(() => {})
        await page.waitForFunction(() => window.__f.firstKlFrame != null && window.__f.firstMsg != null, null, { timeout: 30000 }).catch(() => {})
        const firstK = kind === 'pc' ? await page.evaluate(() => new Promise(res => { const go = () => (window.__cells?.()?.every(c => c.bars > 0) ? res(performance.now()) : requestAnimationFrame(go)); go() })) : null
        await sleep(4000)
        const t = await page.evaluate(() => { const n = performance.getEntriesByType('navigation')[0]; const p = performance.getEntriesByType('paint'); return { dcl: n.domContentLoadedEventEnd, load: n.loadEventEnd, fcp: p.find(x => x.name === 'first-contentful-paint')?.startTime, kl: window.__f.firstKl, klFrame: window.__f.firstKlFrame, msg: window.__f.firstMsg, lt: window.__f.lt.slice() } })
        const m = await metrics(cdp, page)
        const api = reqs.filter(x => x.t === 'fetch' || x.t === 'xhr')
        const seen = {}; for (const x of api) seen[x.u] = (seen[x.u] || 0) + 1
        const dup = Object.entries(seen).filter(([, n]) => n > 1).map(([k, n]) => `${n}× ${k.replace(/^https?:\/\/[^/]+/, '').slice(0, 110)}`)
        runs.push({ ...t, allK: firstK, api: api.length, ws: reqs.filter(x => x.t === 'websocket').length, scripts: reqs.filter(x => x.t === 'script').length, kl: count.n, dup, heap: m.heap, nodes: m.nodes, lsN: m.ls.n, lsBytes: m.ls.bytes, lsMs: m.ls.ms, task: m.task, ltN: t.lt.length, ltMax: Math.max(0, ...t.lt) })
        await ctx.close()
      }
      const r = k => Math.round(med(runs.map(x => x[k])))
      const row = { name, dcl: r('dcl'), fcp: r('fcp'), 首K线帧: r('klFrame'), 全格K线: r('allK'), 首推送: r('msg'), 请求: r('api'), K线请求: r('kl'), WS: r('ws'), 长任务: r('ltN'), 最长任务: r('ltMax'), 主线程秒: +med(runs.map(x => x.task)).toFixed(2), 堆MB: med(runs.map(x => x.heap)), 节点: r('nodes'), 写盘次: r('lsN'), 写盘KB: Math.round(med(runs.map(x => x.lsBytes)) / 1024), 写盘ms: med(runs.map(x => x.lsMs)), 重复: runs[0].dup }
      console.log(JSON.stringify(row))
      out.push(row)
    }
  } finally { await browser.close(); stop() }
  return out
}

// ───────── 长会话：每 N 次操作强制 GC 后读一次堆 / 节点 / JS 监听 / 窗口监听 / 定时器 / WS；同一段内多个检查点单调涨才算漏
const trend = xs => xs.length > 2 && xs.every((v, i) => i === 0 || v > xs[i - 1])
function checkpoints(rows, tag) {
  const r = rows.filter(x => x.tag.startsWith(tag))
  const keys = ['heap', 'nodes', 'listeners', 'iv', 'to', 'wsLive', 'glN']
  const grow = keys.filter(k => trend(r.map(x => x[k])))
  return { tag, n: r.length, first: r[0], last: r[r.length - 1], grow }
}
async function leakPc() {
  const { url, stop } = await preview()
  const browser = await launch()
  const rows = []
  try {
    const px = await realPrices()
    const syms = Object.keys(px).filter(s => /USDT$/.test(s)).slice(0, 40)
    const st = { theme: 'light', skin: 'sage', updown: 'green-up', greenUpMigrated: true, route: 'gateway', routePicked: true, layout: '1', cells: [{ symbol: 'BTCUSDT', iv: '1h' }], active: 0, pinned: ['1m', '5m', '15m', '1h', '4h', '1d', '1w'], panel: 'watch', watchTab: 'crypto', watch: { crypto: syms, us: [], com: [] }, ind: { ma: true, ema: false, boll: true, vol: true, subs: ['macd', 'rsi'] }, drawings: {}, alerts: [], notes: [] }
    const { ctx, count } = await newCtx(browser, PC, { 'hkline-web-v1': JSON.stringify(st) }, { delay: 30, local: true, depth: 40000 })
    const page = await ctx.newPage()
    const cdp = await ctx.newCDPSession(page); await cdp.send('Performance.enable')
    const errs = []; page.on('pageerror', e => errs.push(String(e))); page.on('console', m => { if (m.type() === 'error' && !/WebSocket|Failed to load resource/.test(m.text())) errs.push(m.text().slice(0, 160)) })
    await page.goto(url + '#chart')
    await page.waitForFunction(() => window.__cells?.()?.[0]?.bars > 0, null, { timeout: 30000 })
    await sleep(3000)
    const focus = async () => { await page.mouse.move(1100, 600) }
    const snap = async tag => {
      await sleep(1500)
      const m = await metrics(cdp, page)
      const glN = Object.values(m.gl).reduce((a, b) => a + b, 0)
      const row = { tag, heap: m.heap, nodes: m.nodes, listeners: m.listeners, iv: m.iv, to: m.to, wsLive: m.ws.live, wsOpened: m.ws.opened, subs: m.ws.subs, unsubs: m.ws.unsubs, glN, gl: m.gl, bars: (await page.evaluate(() => window.__cells().map(c => c.bars))).join('/'), kl: count.n }
      rows.push(row); console.log(JSON.stringify({ ...row, gl: undefined }))
      return row
    }
    await focus(); const base = await snap('起点')
    for (let i = 1; i <= 200; i++) { await page.keyboard.press('ArrowDown'); await sleep(60); if (i % 50 === 0) await snap(`切品种 ${i}`) }
    for (let i = 1; i <= 200; i++) { await page.keyboard.press(String(1 + (i % 7))); await sleep(60); if (i % 50 === 0) await snap(`切周期 ${i}`) }
    for (let i = 1; i <= 100; i++) {
      await page.keyboard.press('/'); await sleep(80)
      await page.locator('.ind-row[data-id="kdj"]').first().click({ timeout: 2000 }).catch(() => {}); await sleep(40)
      await page.keyboard.press('Escape'); await sleep(60); await focus()
      if (i % 25 === 0) await snap(`指标面板 ${i}`)
    }
    await page.keyboard.press('1'); await sleep(1500)   // 1m
    let pages = 0
    for (let i = 1; i <= 50; i++) {
      const b0 = (await page.evaluate(() => window.__cells()[0].bars))
      for (let k = 0; k < 40; k++) { await page.mouse.wheel(-3000, 0); await sleep(30); if ((await page.evaluate(() => window.__cells()[0].bars)) > b0) { pages++; break } }
      if (i % 10 === 0) await snap(`翻页 ${i}`)
    }
    const pickLayout = async label => { await page.click('#tbLayout'); await sleep(150); await page.locator('.menu .mi', { hasText: label }).first().click(); await sleep(250) }
    for (let i = 1; i <= 20; i++) { await pickLayout('十六图'); await sleep(1200); await pickLayout('一图'); await sleep(400); await focus(); if (i % 5 === 0) await snap(`十六图开关 ${i}`) }
    // 收尾：回到起点那只、那个周期，和起点比
    await page.evaluate(() => { location.hash = '#chart' })
    await page.keyboard.press('4'); await sleep(500)
    for (let i = 0; i < 200 && (await page.evaluate(() => window.__cells()[0].symbol)) !== 'BTCUSDT'; i++) { await page.keyboard.press('ArrowDown'); await sleep(40) }
    const end = await snap('终点（回到起点品种周期）')
    console.log('翻到页数', pages, '报错', errs.length, errs.slice(0, 5))
    for (const t of ['切品种', '切周期', '指标面板', '翻页', '十六图开关']) console.log(JSON.stringify(checkpoints(rows, t), (k, v) => (k === 'gl' ? undefined : v)))
    console.log('起点 → 终点', line('', { ...base, ws: { live: base.wsLive, opened: base.wsOpened, subs: base.subs, unsubs: base.unsubs } }, { ...end, ws: { live: end.wsLive, opened: end.wsOpened, subs: end.subs, unsubs: end.unsubs } }))
    await ctx.close()
  } finally { await browser.close(); stop() }
  return rows
}

// ───────── 手机长会话：底栏四页轮流进出、扫品种、开关面板；同 leak-pc 的检查点
async function leakM() {
  const { url, stop } = await preview()
  const browser = await launch()
  const rows = []
  try {
    const hm = await heavyM(60)
    hm.drawings = { v: 3, preferences: {}, d: {} }
    const { ctx, count } = await newCtx(browser, ARG[0] === 'nova' ? NOVA : M, { 'hkline-m-v1': JSON.stringify(hm.store) }, { delay: 30, local: true })
    const page = await ctx.newPage()
    const cdp = await ctx.newCDPSession(page); await cdp.send('Performance.enable')
    const errs = []; page.on('pageerror', e => errs.push(String(e))); page.on('console', m => { if (m.type() === 'error' && !/WebSocket|Failed to load resource/.test(m.text())) errs.push(m.text().slice(0, 160)) })
    await page.goto(url + 'm/#favorites'); await page.waitForSelector('.lr[data-sym]', { timeout: 30000 }); await sleep(2500)
    const snap = async tag => {
      await sleep(1500)
      const m = await metrics(cdp, page)
      const glN = Object.values(m.gl).reduce((a, b) => a + b, 0)
      const row = { tag, heap: m.heap, nodes: m.nodes, listeners: m.listeners, iv: m.iv, to: m.to, wsLive: m.ws.live, wsOpened: m.ws.opened, subs: m.ws.subs, unsubs: m.ws.unsubs, glN, gl: m.gl, kl: count.n }
      rows.push(row); console.log(JSON.stringify({ ...row, gl: undefined }))
      return row
    }
    // 板块分类 2026-10-10 并进首页第四段：点「首页」再点「板块」胶囊
    const tab = async id => { await page.evaluate(i => { if (i === 'sectors') { document.querySelector('.m-tab[data-page="home"]')?.click(); document.querySelector('.hm-caps [data-seg="sectors"]')?.click() } else document.querySelector(`.m-tab[data-page="${i}"]`)?.click() }, id); await sleep(250) }
    for (const id of ['chart', 'sectors', 'me', 'favorites']) await tab(id)
    const base = await snap('起点')
    for (let i = 1; i <= 50; i++) { for (const id of ['chart', 'favorites', 'sectors', 'me']) await tab(id); if (i % 10 === 0) await snap(`四页轮流 ${i}`) }
    // 自选点进图，顶栏横滑扫品种 100 次
    await tab('favorites'); await page.click('.lr[data-sym]'); await page.waitForSelector('.cp-head'); await sleep(3000)
    const box = await page.locator('.cp-head').boundingBox()
    let dir = -1, done = 0
    for (let k = 0; k < 160 && done < 100; k++) {
      const before = await page.evaluate(() => document.querySelector('.cp-base')?.textContent)
      const y = box.y + box.height / 2, x = box.x + box.width / 2
      await page.mouse.move(x, y); await page.mouse.down(); await page.mouse.move(x + dir * 120, y, { steps: 2 }); await page.mouse.up(); await sleep(90)
      if (await page.evaluate(() => document.querySelector('.cp-base')?.textContent) === before) dir = -dir; else { done++; if (done % 25 === 0) await snap(`扫品种 ${done}`) }
    }
    const open = [() => [...document.querySelectorAll('.cp-tail')].find(b => b.textContent.includes('分析'))?.click(), () => document.querySelector('.cp-gear')?.click(), () => document.querySelector('.cp-more')?.click()]
    for (let i = 1; i <= 50; i++) {
      await page.evaluate(open[i % 3]); await sleep(150)
      await page.evaluate(() => (document.querySelector('.m-sheet-scrim') || document.querySelector('.m-pop-scrim'))?.click()); await sleep(350)
      if (i % 10 === 0) await snap(`开关面板 ${i}`)
    }
    for (const id of ['sectors', 'me', 'favorites']) await tab(id)
    const end = await snap('终点（回到自选页）')
    console.log('扫到', done, '报错', errs.length, errs.slice(0, 5))
    for (const t of ['四页轮流', '扫品种', '开关面板']) console.log(JSON.stringify(checkpoints(rows, t), (k, v) => (k === 'gl' ? undefined : v)))
    console.log('起点 → 终点', line('', { ...base, ws: { live: base.wsLive, opened: base.wsOpened, subs: base.subs, unsubs: base.unsubs } }, { ...end, ws: { live: end.wsLive, opened: end.wsOpened, subs: end.subs, unsubs: end.unsubs } }))
    await ctx.close()
  } finally { await browser.close(); stop() }
  return rows
}

// ───────── 挂机：常态一分钟、前后台来回切、长时间藏起、断网两分钟、时钟往前 / 往后跳；每段记各接口请求数、WS、定时器
//   node scripts/f-perf.mjs idle pc|m
const VIS = () => {
  window.__vis = h => {
    Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => (h ? 'hidden' : 'visible') })
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => h })
    document.dispatchEvent(new Event('visibilitychange'))
  }
  // 系统时钟跳变：Date.now / new Date() 整体偏 off 毫秒（performance.now 不动，和真机睡眠 / 改时间一致）
  const D = Date
  let off = 0
  class FD extends D { constructor(...a) { if (a.length) super(...a); else super(D.now() + off) } static now() { return D.now() + off } }
  window.__jump = ms => { off += ms; window.Date = FD }
}
async function idle() {
  const kind = ARG[0] === 'm' ? 'm' : 'pc'
  const { url, stop } = await preview()
  const browser = await launch()
  const phases = []
  try {
    const px = await realPrices()
    const syms = Object.keys(px).filter(s => /USDT$/.test(s)).slice(0, 40)
    const st = { theme: 'light', skin: 'sage', updown: 'green-up', greenUpMigrated: true, route: 'gateway', routePicked: true, layout: '4', cells: ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'XAUUSDT'].map(symbol => ({ symbol, iv: '1m' })), active: 0, pinned: ['1m', '5m', '15m', '1h', '4h', '1d', '1w'], panel: 'watch', watchTab: 'crypto', watch: { crypto: syms, us: [], com: [] }, ind: { ma: true, ema: false, boll: true, vol: true, subs: ['macd'] }, drawings: {}, alerts: [], notes: [] }
    const hm = await heavyM(60)
    hm.store.page = 'chart'
    const { ctx, count } = await newCtx(browser, kind === 'm' ? M : PC, kind === 'm' ? { 'hkline-m-v1': JSON.stringify(hm.store) } : { 'hkline-web-v1': JSON.stringify(st) }, { delay: 30, local: true })
    await ctx.addInitScript(VIS)
    const page = await ctx.newPage()
    const cdp = await ctx.newCDPSession(page); await cdp.send('Performance.enable')
    const errs = []; page.on('pageerror', e => errs.push(String(e)))
    const reqs = {}; let failed = 0
    page.on('request', r => { const u = r.url(); if (/\/v1\/|binance|fapi/.test(u) && r.resourceType() !== 'websocket') { const k = u.replace(/^https?:\/\/[^/]+/, '').replace(/[?].*/, '').replace(/^\/v1\/market\/raw/, ''); reqs[k] = (reqs[k] || 0) + 1 } })
    page.on('requestfailed', () => { failed++ })
    // 手机：从自选点进图（冻结扫图名单），顶栏横滑才翻得动
    if (kind === 'm') { await page.goto(url + 'm/#favorites'); await page.waitForSelector('.lr[data-sym]', { timeout: 30000 }); await sleep(800); await page.click('.lr[data-sym]'); await page.waitForSelector('.cp-head', { timeout: 30000 }) }
    else { await page.goto(url + '#chart'); await page.waitForFunction(() => window.__cells?.()?.every(c => c.bars > 0), null, { timeout: 30000 }) }
    await sleep(5000)
    const bars = () => page.evaluate(k => (k === 'pc' ? window.__cells().map(c => c.bars).join('/') : document.querySelector('.cp-base')?.textContent), kind)
    let prevReq = { ...reqs }, prevKl = count.n, prevFailed = failed, prevM = await metrics(cdp, page, false), t0 = Date.now()
    const phase = async (name, fn) => {
      t0 = Date.now()
      const cpu0 = (await cdp.send('Performance.getMetrics')).metrics.find(x => x.name === 'TaskDuration').value
      await fn()
      const cpu1 = (await cdp.send('Performance.getMetrics')).metrics.find(x => x.name === 'TaskDuration').value
      const m = await metrics(cdp, page)
      const d = {}; for (const k of Object.keys(reqs)) if (reqs[k] !== (prevReq[k] || 0)) d[k] = reqs[k] - (prevReq[k] || 0)
      const sec = (Date.now() - t0) / 1000
      const row = { 段: name, 秒: Math.round(sec), CPU: +((cpu1 - cpu0) / sec * 100).toFixed(1) + '%', K线: count.n - prevKl, 请求: d, 失败: failed - prevFailed, WS开: m.ws.opened - prevM.ws.opened, WS活: m.ws.live, 订: m.ws.subs - prevM.ws.subs, 退: m.ws.unsubs - prevM.ws.unsubs, 推送: m.ws.msgs - prevM.ws.msgs, interval: m.iv, timeout: m.to, 窗口监听差: diffGl(prevM.gl, m.gl), 堆: m.heap, 图: await bars() }
      console.log(JSON.stringify(row))
      phases.push(row)
      prevReq = { ...reqs }; prevKl = count.n; prevFailed = failed; prevM = m
    }
    await phase('常态挂机 60 秒', () => sleep(60000))
    await phase('前后台来回切 20 次（各 1.5 秒）', async () => { for (let i = 0; i < 20; i++) { await page.evaluate(() => window.__vis(true)); await sleep(1500); await page.evaluate(() => window.__vis(false)); await sleep(1500) } await sleep(5000) })
    await phase('藏起 90 秒再回来', async () => { await page.evaluate(() => window.__vis(true)); await sleep(90000); await page.evaluate(() => window.__vis(false)); await sleep(10000) })
    await phase('断网 120 秒', async () => { await ctx.setOffline(true); await sleep(120000) })
    await phase('恢复网络 20 秒', async () => { await ctx.setOffline(false); await sleep(20000) })
    await phase('时钟往前跳 30 分钟（睡眠唤醒）', async () => { await page.evaluate(() => { window.__vis(true); window.__jump(30 * 60e3); window.__vis(false) }); await sleep(15000) })
    await phase('时钟往回拨 2 小时后挂机 90 秒', async () => { await page.evaluate(() => window.__jump(-150 * 60e3)); await sleep(90000) })
    console.log('报错', errs.length, errs.slice(0, 5))
    await ctx.close()
  } finally { await browser.close(); stop() }
  return phases
}

// ───────── 大数据：PC 十六图每格三副图 + 订单流（常态 / 十字线扫十六格 / 滚轮 / 拖动）；一图 1m 连续往前翻 50 页（7.5 万根）后再量
//   node scripts/f-perf.mjs big
async function big() {
  const { url, stop } = await preview()
  const browser = await launch()
  const out = []
  try {
    const hp = await heavyPc()
    hp.orderFlow = true
    const { ctx, count } = await newCtx(browser, PC, { 'hkline-web-v1': JSON.stringify(hp) }, { delay: 30, local: true, depth: 80000 })
    const page = await ctx.newPage()
    const cdp = await ctx.newCDPSession(page); await cdp.send('Performance.enable')
    const errs = []; page.on('pageerror', e => errs.push(String(e)))
    await page.goto(url + '#chart')
    await page.waitForFunction(() => window.__cells?.()?.length === 16 && window.__cells().every(c => c.bars > 0), null, { timeout: 60000 })
    await sleep(8000)
    const rect = await page.evaluate(() => [...document.querySelectorAll('.chart-cell .canvas-host')].slice(0, 1).map(c => { const r = c.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height } })[0])
    const grid = await page.evaluate(() => { const cs = [...document.querySelectorAll('.chart-cell')].map(e => e.getBoundingClientRect()); const x = Math.min(...cs.map(r => r.x)), y = Math.min(...cs.map(r => r.y)); return { x, y, w: Math.max(...cs.map(r => r.right)) - x, h: Math.max(...cs.map(r => r.bottom)) - y } })
    const row = async (name, fn) => { const r = await measure(page, cdp, fn); const m = await metrics(cdp, page, false); const o = { 段: name, ...r, 堆: m.heap, 节点: m.nodes }; console.log(JSON.stringify(o)); out.push(o); return o }
    await row('十六图 × 三副图 + 订单流 常态 10 秒', () => sleep(10000))
    await row('十字线扫过十六格（联动十字线）600 下', async () => {
      for (let i = 0; i < 600; i++) { const t = i / 600; await page.mouse.move(grid.x + 20 + (grid.w - 40) * ((t * 4) % 1), grid.y + 20 + (grid.h - 40) * t); await sleep(4) }
    })
    const cx = rect.x + rect.w * 0.5, cy = rect.y + rect.h * 0.3
    await page.mouse.move(cx, cy)
    await row('第一格滚轮缩放 300 下', async () => { for (let i = 0; i < 300; i++) { await page.mouse.wheel(0, i % 60 < 30 ? 40 : -40); await sleep(4) } })
    await row('第一格拖动平移 3 秒', async () => { await page.mouse.down(); for (let i = 0; i < 180; i++) { await page.mouse.move(cx + Math.sin(i / 20) * 200, cy); await sleep(8) } await page.mouse.up() })
    const m16 = await metrics(cdp, page)
    console.log(JSON.stringify({ 十六图稳态: { 堆: m16.heap, 节点: m16.nodes, WS活: m16.ws.live, 长任务: m16.lt.length } }))
    // 一图 1m，往前翻 50 页
    await page.click('#tbLayout'); await sleep(150); await page.locator('.menu .mi', { hasText: '一图' }).first().click(); await sleep(800)
    await page.mouse.move(1100, 600); await page.keyboard.press('1'); await sleep(2000)
    const bars = () => page.evaluate(() => window.__cells()[0].bars)
    let pages = 0
    const pg = await row('一图 1m 连续往前翻 50 页', async () => {
      for (let i = 0; i < 50; i++) {
        const b0 = await bars()
        for (let k = 0; k < 80; k++) { await page.mouse.wheel(-4000, 0); await sleep(25); if ((await bars()) > b0) { pages++; break } }
      }
    })
    const nb = await bars()
    console.log(JSON.stringify({ 翻到页数: pages, 根数: nb, K线请求: count.n }))
    await row(`${nb} 根下十字线 300 下`, async () => { for (let i = 0; i < 300; i++) { await page.mouse.move(400 + (i * 7) % 1600, 300 + (i * 3) % 700); await sleep(4) } })
    await page.mouse.move(1100, 600)
    await row(`${nb} 根下缩到最小再放回（滚轮 200 下）`, async () => { for (let i = 0; i < 200; i++) { await page.mouse.wheel(0, i < 100 ? 120 : -120); await sleep(4) } })
    await row(`${nb} 根下拖动平移 3 秒`, async () => { await page.mouse.down(); for (let i = 0; i < 180; i++) { await page.mouse.move(1100 + Math.sin(i / 20) * 500, 600); await sleep(8) } await page.mouse.up() })
    await row(`${nb} 根下常态 10 秒（推送照常）`, () => sleep(10000))
    console.log('报错', errs.length, errs.slice(0, 5), 'pg', pg.ltMax)
    await ctx.close()
  } finally { await browser.close(); stop() }
  return out
}

// ───────── 手机满载手势：真页面 m/#chart（不是 bench），1m 往前甩 30 页后横甩 / 捏合 / 十字线；CPU 降速 4 倍
//   node scripts/f-perf.mjs hf [nova]
async function hf() {
  const { url, stop } = await preview()
  const browser = await launch()
  const out = []
  try {
    const hm = await heavyM(60)
    hm.store.page = 'chart'
    const { ctx, count } = await newCtx(browser, ARG[0] === 'nova' ? NOVA : M, { 'hkline-m-v1': JSON.stringify(hm.store), 'hkline-m-drawings-v1': JSON.stringify(hm.drawings) }, { delay: 30, local: true, depth: 60000 })
    const page = await ctx.newPage()
    const cdp = await ctx.newCDPSession(page); await cdp.send('Performance.enable')
    const errs = []; page.on('pageerror', e => errs.push(String(e)))
    let minEnd = Infinity
    page.on('request', r => { const m = /klines\?.*endTime=(\d+)/.exec(r.url()); if (m) minEnd = Math.min(minEnd, +m[1]) })
    await page.goto(url + 'm/#chart'); await page.waitForSelector('.cp-head', { timeout: 30000 }); await sleep(5000)
    const box = await page.evaluate(() => { const r = (document.querySelector('.m-chart') || document.querySelector('canvas')).getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height } })
    const touch = (type, pts) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: pts.map((q, i) => ({ x: q[0], y: q[1], id: i })) })
    const cx = box.x + box.w * 0.5, cy = box.y + box.h * 0.3
    const row = async (name, fn) => { const r = await measure(page, cdp, fn); const m = await metrics(cdp, page, false); const o = { 段: name, ...r, 堆: m.heap, 节点: m.nodes, K线请求: count.n }; console.log(JSON.stringify(o)); out.push(o); return o }
    const fling = async dir => { await touch('touchStart', [[cx - dir * 120, cy]]); for (let i = 1; i <= 8; i++) { await touch('touchMove', [[cx - dir * 120 + dir * i * 30, cy]]); await sleep(12) } await touch('touchEnd', []) }
    // 切 1m：周期条里点「1分」（没有就按当前周期量）
    await page.evaluate(() => { const b = [...document.querySelectorAll('button, .iv, [data-iv]')].find(x => /^1\s*分|^1m$/.test(x.textContent.trim()) || x.getAttribute?.('data-iv') === '1m'); b?.click() })
    await sleep(2500)
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 })
    await row('常态 10 秒（CPU 4 倍降速）', () => sleep(10000))
    await row('往前快甩 40 下（翻页）', async () => { for (let i = 0; i < 40; i++) { await fling(1); await sleep(700) } })
    console.log(JSON.stringify({ 最早请求到: new Date(minEnd).toISOString(), K线请求: count.n }))
    await row('横甩来回 20 下', async () => { for (let i = 0; i < 20; i++) { await fling(i % 2 ? 1 : -1); await sleep(500) } })
    await row('双指捏合 10 轮', async () => {
      for (let r = 0; r < 10; r++) {
        await touch('touchStart', [[cx - 30, cy], [cx + 30, cy]])
        for (let i = 1; i <= 30; i++) { await touch('touchMove', [[cx - 30 - i * 3, cy], [cx + 30 + i * 3, cy]]); await sleep(12) }
        for (let i = 1; i <= 30; i++) { await touch('touchMove', [[cx - 120 + i * 3, cy], [cx + 120 - i * 3, cy]]); await sleep(12) }
        await touch('touchEnd', []); await sleep(200)
      }
    })
    await row('长按十字线拎着走 5 轮', async () => {
      for (let r = 0; r < 5; r++) {
        await touch('touchStart', [[cx, cy]]); await sleep(550)
        for (let i = 1; i <= 60; i++) { await touch('touchMove', [[cx + Math.sin(i / 8) * 150, cy + Math.cos(i / 8) * 80]]); await sleep(12) }
        await touch('touchEnd', []); await sleep(200)
        await touch('touchStart', [[cx - 100, cy - 50]]); await sleep(30); await touch('touchEnd', []); await sleep(300)
      }
    })
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: 1 })
    console.log('报错', errs.length, errs.slice(0, 5))
    await ctx.close()
  } finally { await browser.close(); stop() }
  return out
}

// ───────── 本机存储接近 5 MB：重本机档 + 填充键把同源存储塞到只剩不到 1 KB，再连切 50 只品种 / 四页轮流；
//   记 setItem 次数、失败次数（按键）、写盘耗时、长任务；最后重载看「最后停下的那只」有没有存住
//   node scripts/f-perf.mjs storage pc|m
const LSFAIL = () => {
  const F = (window.__lsFail = { n: 0, byKey: {} })
  const set = Storage.prototype.setItem
  Storage.prototype.setItem = function (k, v) { try { return set.call(this, k, v) } catch (e) { F.n++; F.byKey[k] = (F.byKey[k] || 0) + 1; throw e } }
}
async function storage() {
  const kind = ARG[0] === 'm' ? 'm' : 'pc'
  const { url, stop } = await preview()
  const browser = await launch()
  const out = {}
  try {
    const hp = await heavyPc(), hm = await heavyM(300)
    hm.store.page = 'chart'
    const kv = kind === 'm' ? { 'hkline-m-v1': JSON.stringify(hm.store), 'hkline-m-drawings-v1': JSON.stringify(hm.drawings) } : { 'hkline-web-v1': JSON.stringify({ ...hp, layout: '1', cells: [{ symbol: 'BTCUSDT', iv: '1h' }] }) }
    const { ctx } = await newCtx(browser, kind === 'm' ? M : PC, kv, { delay: 30, local: true })
    await ctx.addInitScript(LSFAIL)
    const page = await ctx.newPage()
    const cdp = await ctx.newCDPSession(page); await cdp.send('Performance.enable')
    const errs = []; page.on('pageerror', e => errs.push(String(e)))
    const warns = []; page.on('console', m => { if (m.type() === 'warning' || m.type() === 'error') warns.push(m.text().slice(0, 100)) })
    // 手机：从自选点进图（冻结扫图名单），顶栏横滑才翻得动
    if (kind === 'm') { await page.goto(url + 'm/#favorites'); await page.waitForSelector('.lr[data-sym]', { timeout: 30000 }); await sleep(800); await page.click('.lr[data-sym]'); await page.waitForSelector('.cp-head', { timeout: 30000 }) }
    else { await page.goto(url + '#chart'); await page.waitForFunction(() => window.__cells?.()?.[0]?.bars > 0, null, { timeout: 30000 }) }
    await sleep(4000)
    const used = () => page.evaluate(() => { let n = 0; for (let i = 0; i < localStorage.length; i++) { const k = localStorage.key(i); n += k.length + (localStorage.getItem(k) || '').length } return n })
    out.起始字符 = await used()
    out.大键 = await page.evaluate(() => { const o = {}; for (let i = 0; i < localStorage.length; i++) { const k = localStorage.key(i), n = (localStorage.getItem(k) || '').length; if (n > 2000) o[k] = n } return o })
    // 二分出能塞下的最大填充，只留不到 1 KB
    const filled = await page.evaluate(() => {
      let lo = 0, hi = 6e6
      while (hi - lo > 512) { const mid = (lo + hi) >> 1; try { localStorage.setItem('f-filler', 'x'.repeat(mid)); lo = mid } catch { hi = mid } }
      localStorage.setItem('f-filler', 'x'.repeat(lo)); window.__lsFail.n = 0; window.__lsFail.byKey = {}
      Object.assign(window.__f.ls, { n: 0, bytes: 0, ms: 0, byKey: {} })
      // 提示条一出现就记下（PC 的「本机存储已满」只停 8 秒、手机 1.6 秒，跑完再看就没了）
      window.__toasts = []
      new MutationObserver(ms => { for (const m of ms) for (const n of m.addedNodes) if (n.nodeType === 1 && n.matches?.('.toast, .m-toast, [role="status"]')) setTimeout(() => window.__toasts.push(n.textContent.trim()), 0) }).observe(document.body, { childList: true, subtree: true })
      return lo
    })
    out.填充字符 = filled; out.塞满后字符 = await used()
    const r = await measure(page, cdp, async () => {
      if (kind === 'pc') { await page.mouse.move(1100, 600); for (let i = 0; i < 50; i++) { await page.keyboard.press('ArrowDown'); await sleep(120) } }
      else {
        const box = await page.locator('.cp-head').boundingBox()
        const x = box.x + box.width / 2, y = box.y + box.height / 2
        for (let i = 0; i < 50; i++) { await page.mouse.move(x, y); await page.mouse.down(); await page.mouse.move(x - 120, y, { steps: 2 }); await page.mouse.up(); await sleep(150) }
      }
      await sleep(2000)
    })
    out.连切 = r
    const want = kind === 'pc' ? await page.evaluate(() => window.__cells()[0].symbol) : await page.evaluate(() => document.querySelector('.cp-base')?.textContent?.trim())
    const ls = await page.evaluate(() => ({ fail: window.__lsFail, n: window.__f.ls.n, kb: Math.round(window.__f.ls.bytes / 1024), ms: Math.round(window.__f.ls.ms), byKey: Object.fromEntries(Object.entries(window.__f.ls.byKey).map(([k, v]) => [k, v.n])) }))
    out.跑时提示 = [...new Set(await page.evaluate(() => window.__toasts))]
    out.写盘 = ls
    await page.evaluate(() => sessionStorage.setItem('f-seeded', '1'))
    await page.reload()
    if (kind === 'm') await page.waitForSelector('.cp-head', { timeout: 30000 }); else await page.waitForFunction(() => window.__cells?.()?.[0]?.bars > 0, null, { timeout: 30000 })
    await sleep(1500)
    const got = kind === 'pc' ? await page.evaluate(() => window.__cells()[0].symbol) : await page.evaluate(() => document.querySelector('.cp-base')?.textContent?.trim())
    out.最后停下 = want; out.重载后 = got; out.存住 = want === got
    out.提示 = await page.evaluate(() => [...document.querySelectorAll('.toast, .m-toast, [role="status"]')].map(e => e.textContent.trim()).filter(Boolean).slice(0, 3))
    out.报错 = errs.slice(0, 5); out.警告 = [...new Set(warns)].slice(0, 5); out.警告条数 = warns.length
    console.log(JSON.stringify(out))
    await ctx.close()
  } finally { await browser.close(); stop() }
  return out
}

// ───────── 线上服务端轻量负载（只读、并发 ≤ 10、≤ 60 秒；gateway-is-production）：
//   REST：10 路并发轮流打服务端自己出数 / 带缓存合流的接口 45 秒（不打每次都要回源币安的接口，免得占全站共用的币安额度）；
//   WS：10 条网关推送连接各订 BTC/ETH 的 K 线与行情 + 全市场行情 60 秒；记握手、首帧、每秒帧数、断线
//   node scripts/f-perf.mjs server
async function server() {
  const H = 'https://kanpan.43-160-232-253.sslip.io'
  const end = (Date.now() - 3 * 86400e3) - ((Date.now() - 3 * 86400e3) % 3600e3)
  const urls = [
    '/v1/market/sector-history',
    '/v1/market/hourly-closes?symbols=BTCUSDT,ETHUSDT,SOLUSDT',
    '/v1/market/raw/fapi/v1/exchangeInfo?source=binance',
    `/v1/market/raw/fapi/v1/klines?symbol=BTCUSDT&interval=1h&limit=500&endTime=${end}&source=binance`,
    '/web/', '/web/m/',
  ]
  const lat = {}, codes = {}
  const t0 = Date.now(), DUR = 45000
  let i = 0
  const worker = async () => {
    while (Date.now() - t0 < DUR) {
      const u = urls[i++ % urls.length], a = performance.now()
      let c = 'ERR'
      try { const r = await fetch(H + u, { headers: { origin: H, 'user-agent': 'hkline-f-perf' } }); await r.arrayBuffer(); c = r.status } catch { /* 记 ERR */ }
      const k = u.replace(/\?.*/, '')
      ;(lat[k] ||= []).push(performance.now() - a); codes[k + ' ' + c] = (codes[k + ' ' + c] || 0) + 1
    }
  }
  await Promise.all(Array.from({ length: 10 }, worker))
  const rest = Object.fromEntries(Object.entries(lat).map(([k, v]) => [k, { n: v.length, p50: Math.round(pct(v, 0.5)), p95: Math.round(pct(v, 0.95)), max: Math.round(Math.max(...v)) }]))
  const total = Object.values(lat).reduce((s, v) => s + v.length, 0)
  console.log(JSON.stringify({ REST: rest, 状态: codes, 合计: total, 每秒: +(total / (DUR / 1000)).toFixed(1) }))
  // WS
  const conns = []
  const W0 = Date.now()
  await Promise.all(Array.from({ length: 10 }, (_, k) => new Promise(res => {
    const c = { k, open: null, first: null, msgs: 0, closed: null, err: 0 }
    conns.push(c)
    const a = performance.now()
    const ws = new WebSocket(H.replace('https', 'wss') + '/market/stream')
    ws.onopen = () => { c.open = performance.now() - a; ws.send(JSON.stringify({ method: 'SUBSCRIBE', params: ['btcusdt@kline_1m', 'btcusdt@ticker', 'ethusdt@kline_1m', 'ethusdt@ticker', '!ticker@arr'], id: 1 })) }
    ws.onmessage = () => { c.msgs++; if (c.first == null) c.first = performance.now() - a }
    ws.onerror = () => { c.err++ }
    ws.onclose = e => { if (c.closed == null) c.closed = { at: Math.round((Date.now() - W0) / 1000), code: e.code } }
    setTimeout(() => { try { ws.close() } catch { /* 已关 */ } res() }, 60000)
  })))
  console.log(JSON.stringify({ WS: { 握手ms: { p50: Math.round(pct(conns.map(c => c.open ?? 99999), 0.5)), max: Math.round(Math.max(...conns.map(c => c.open ?? 99999))) }, 首帧ms: { p50: Math.round(pct(conns.map(c => c.first ?? 99999), 0.5)), max: Math.round(Math.max(...conns.map(c => c.first ?? 99999))) }, 每条每秒帧: conns.map(c => +(c.msgs / 60).toFixed(1)), 中途断: conns.filter(c => c.closed && c.closed.at < 59).map(c => c.closed), 错误: conns.reduce((s, c) => s + c.err, 0) } }))
}

// ───────── 回归段（F1–F8 的现场数字，见报告）：
//   sidebar  PC 十六图 + 300 只自选宽侧栏挂 120 秒：持仓额请求数、限流账本写盘次数 / 字节、闲置 20 秒布局与样式重算（F1–F4）
//   tabs-m   手机四页（行情 / 自选 / 板块 / 我的）轮流点 50 轮：全量 24hr 次数、推送握手次数、回行情页 K 线请求、限流排队（F5–F7）
//   scan-m   手机从自选点进图后顶栏横滑连扫 100 只：行情类请求总数、限流排队等待、首屏 K 线取到的品种数（F8）
const reqCounter = page => { const REQ = {}; page.on('request', r => { const u = r.url(); if (/klines|fapi|futures|dapi|api\/v3/.test(u)) { const k = u.replace(/^https?:\/\/[^/]+/, '').replace(/[?].*/, '').replace(/^\/v1\/market\/raw/, ''); REQ[k] = (REQ[k] || 0) + 1 } }); return REQ }
async function sidebar() {
  const { url, stop } = await preview()
  const browser = await launch()
  try {
    const hp = await heavyPc()
    const { ctx } = await newCtx(browser, PC, { 'hkline-web-v1': JSON.stringify(hp) }, { local: true })
    const page = await ctx.newPage()
    const cdp = await ctx.newCDPSession(page); await cdp.send('Performance.enable')
    await page.goto(url + '#chart'); await sleep(10000)
    const idle20 = await measure(page, cdp, () => sleep(20000))
    const a = await metrics(cdp, page, false)
    await sleep(+(process.env.DUR || 120000))
    const b = await metrics(cdp, page, false)
    const d = {}; for (const k of Object.keys(b.fetch)) { const n = b.fetch[k] - (a.fetch[k] || 0); if (n) d[k] = n }
    const lsBy = Object.fromEntries(Object.entries(b.ls.byKey).map(([k, v]) => [k, { n: v.n - (a.ls.byKey[k]?.n || 0), kb: Math.round((v.bytes - (a.ls.byKey[k]?.bytes || 0)) / 1024) }]).filter(([, v]) => v.n))
    console.log(JSON.stringify({ 闲置20秒: { 布局: idle20.layouts, 布局ms: idle20.layoutMs, 样式重算: idle20.recalcs, CPU: idle20.cpu }, '120秒请求': d, '120秒写盘': lsBy }))
  } finally { await browser.close(); stop() }
}
async function tabsM() {
  const { url, stop } = await preview()
  const browser = await launch()
  try {
    const hm = await heavyM(60)
    const { ctx, count } = await newCtx(browser, M, { 'hkline-m-v1': JSON.stringify(hm.store) }, { delay: 30, local: true })
    const page = await ctx.newPage(); const cdp = await ctx.newCDPSession(page); await cdp.send('Performance.enable')
    const REQ = reqCounter(page)
    await page.goto(url + 'm/#favorites'); await page.waitForSelector('.lr[data-sym]'); await sleep(2000)
    const ws0 = await page.evaluate(() => window.__f.ws.opened)
    for (let i = 0; i < 50; i++) for (const id of ['chart', 'favorites', 'sectors', 'me']) { await page.evaluate(i => { if (i === 'sectors') { document.querySelector('.m-tab[data-page="home"]')?.click(); document.querySelector('.hm-caps [data-seg="sectors"]')?.click() } else document.querySelector(`.m-tab[data-page="${i}"]`)?.click() }, id); await sleep(250) }
    await sleep(1500)
    const m = await metrics(cdp, page)
    console.log(JSON.stringify({ 请求: REQ, K线mock: count.n, 推送握手: m.ws.opened - ws0, 挂着的timeout: m.to, 限流: await page.evaluate(() => globalThis.__limit?.()) }))
  } finally { await browser.close(); stop() }
}
async function scanM() {
  const { url, stop } = await preview()
  const browser = await launch()
  try {
    const hm = await heavyM(300)
    const { ctx } = await newCtx(browser, M, { 'hkline-m-v1': JSON.stringify(hm.store) }, { delay: 30, local: true })
    const page = await ctx.newPage(); const cdp = await ctx.newCDPSession(page); await cdp.send('Performance.enable')
    const REQ = reqCounter(page)
    const klSyms = new Set()
    page.on('request', r => { const u = r.url(); if (/klines\?/.test(u) && !/endTime/.test(u)) klSyms.add(new URL(u).searchParams.get('symbol')) })
    await page.goto(url + 'm/#favorites'); await page.waitForSelector('.lr[data-sym]'); await sleep(2000)
    await page.click('.lr[data-sym]'); await page.waitForSelector('.cp-head'); await sleep(3000)
    for (const k of Object.keys(REQ)) delete REQ[k]
    klSyms.clear()
    const box = await page.locator('.cp-head').boundingBox()
    const y = box.y + box.height / 2, x = box.x + box.width / 2
    let dir = -1, done = 0
    for (let k = 0; k < 300 && done < 100; k++) {
      const before = await page.evaluate(() => document.querySelector('.cp-base')?.textContent)
      await page.mouse.move(x, y); await page.mouse.down(); await page.mouse.move(x + dir * 120, y, { steps: 2 }); await page.mouse.up(); await sleep(90)
      if (await page.evaluate(() => document.querySelector('.cp-base')?.textContent) === before) dir = -dir; else done++
    }
    await sleep(1500)
    const lim = await page.evaluate(() => globalThis.__limit?.())
    console.log(JSON.stringify({ 横滑: done, 行情类请求: Object.values(REQ).reduce((a, b) => a + b, 0), 请求: REQ, 首屏K线品种: klSyms.size, 限流: lim }))
  } finally { await browser.close(); stop() }
}

// ───────── 五家订单流满载：十六图（每格三副图）+ 订单流，币安 / OKX / Coinbase 走真流，Bybit / Hyperliquid 走合成帧
//   node scripts/f-perf.mjs of5
//   合成速率照 2026-10-08 实测录帧（Bybit linear 4 只币 7 分钟 30852 帧：orderbook 8407 + publicTrade 22287，增量最多 1832 档；
//   HL 5 本 7 分钟 632 帧 l2Book + 2396 帧 trades）——这里把 4 只币的量全压到图上这一只（BTC）的每一本 Bybit 簿上（×4），
//   spot / linear / inverse 三本都按这个速率，HL 也按 ×4。品种表在线上那份后面补上 Bybit 三本 + HL 一本（服务端没上线前也能量）。
//   对照：同一页先量「Bybit / HL 不发帧」再量「满载」，十字线 / 滚轮各再量一遍。
async function of5() {
  const { url, stop } = await preview()
  const browser = await launch()
  const out = []
  try {
    const hp = await heavyPc()
    hp.orderFlow = true
    const { ctx } = await newCtx(browser, PC, { 'hkline-web-v1': JSON.stringify(hp) }, { delay: 30, local: true, depth: 80000 })
    const px0 = (await realPrices()).BTCUSDT || 100000
    const extra = [
      { exchange: 'bybit', product: 'usdtPerp', instrument: 'BTCUSDT', notional: { kind: 'linear', multiplier: 1 }, tick: 0.1 },
      { exchange: 'bybit', product: 'spot', instrument: 'BTCUSDT', notional: { kind: 'linear', multiplier: 1 }, tick: 0.1 },
      { exchange: 'bybit', product: 'coinPerp', instrument: 'BTCUSD', notional: { kind: 'inverse', contractUsd: 1 }, tick: 0.5 },
      { exchange: 'hyperliquid', product: 'usdtPerp', instrument: 'BTC', notional: { kind: 'linear', multiplier: 1 }, tick: 1 },
    ]
    await ctx.route(/\/v1\/market\/orderflow\/instruments\?/, async route => {
      const cors = { 'access-control-allow-origin': route.request().headers().origin || '*', 'access-control-allow-credentials': 'true' }
      let venues = []
      try { const r = await route.fetch({ timeout: 15000 }); venues = (await r.json()).venues || [] } catch { /* 线上表拿不到就只有补的这几本 */ }
      const base = new URL(route.request().url()).searchParams.get('base')
      if (base === 'BTC') venues = [...venues.filter(v => v.exchange !== 'bybit' && v.exchange !== 'hyperliquid'), ...extra]
      route.fulfill({ status: 200, contentType: 'application/json', headers: cors, body: JSON.stringify({ venues }) }).catch(() => {})
    })
    const LOAD = { on: false, churn: false, sent: 0, bytes: 0 }
    const rnd = (a, b) => a + Math.random() * (b - a)
    // Bybit：一条连接一个 category；订到的每本簿各一套 u 计数，先发 1000 档快照，再按速率发增量与成交
    await ctx.routeWebSocket(/\/v1\/market\/ws\/bybit|stream\.bybit\.com\/v5\/public/, ws => {
      const books = new Map() // symbol → { u, tick }
      const timers = []
      const send = o => { const t = JSON.stringify(o); LOAD.sent++; LOAD.bytes += t.length; ws.send(t) }
      // 墙：每侧 6 道固定价位 30–80 个币，5 秒左右撤一道再挂回（真盘口的样子）；极端档（churn）每帧随机 1% 的档冒 20–80 个币
      const WALL_IX = [37, 120, 260, 410, 640, 880]
      const qty = () => rnd(0.001, 2).toFixed(4)
      const side = (n, tick, sign) => Array.from({ length: n }, (_, i) => [(px0 + sign * tick * (i + 1)).toFixed(1), WALL_IX.includes(i + 1) ? rnd(30, 80).toFixed(4) : qty()])
      const snapshot = (sym, b) => { b.u += 1; send({ topic: `orderbook.1000.${sym}`, type: 'snapshot', ts: Date.now(), data: { s: sym, b: side(1000, b.tick, -1), a: side(1000, b.tick, 1), u: b.u, seq: b.u } }) }
      const delta = (sym, b) => {
        const n = Math.random() < 0.1 ? 1832 : Math.floor(rnd(40, 200))
        const pick = sign => Array.from({ length: n >> 1 }, () => { const ix = Math.floor(rnd(1, 1000)); return WALL_IX.includes(ix) ? null : [(px0 + sign * b.tick * ix).toFixed(1), (Math.random() < 0.15 ? 0 : LOAD.churn && Math.random() < 0.01 ? rnd(20, 80) : rnd(0.001, 2)).toFixed(4)] }).filter(Boolean)
        b.flip = (b.flip || 0) + 1
        const wall = sign => (b.flip % 100 === 0 ? [[(px0 + sign * b.tick * WALL_IX[(b.flip / 100) % 6]).toFixed(1), Math.floor(b.flip / 100) % 2 ? rnd(30, 80).toFixed(4) : '0']] : [])
        b.u += 1
        send({ topic: `orderbook.1000.${sym}`, type: 'delta', ts: Date.now(), data: { s: sym, b: [...pick(-1), ...wall(-1)], a: [...pick(1), ...wall(1)], u: b.u, seq: b.u } })
      }
      const trades = sym => send({ topic: `publicTrade.${sym}`, type: 'snapshot', ts: Date.now(), data: Array.from({ length: 1 + Math.floor(rnd(0, 3)) }, () => ({ T: Date.now(), s: sym, S: Math.random() < 0.5 ? 'Buy' : 'Sell', v: rnd(0.001, 3).toFixed(4), p: (px0 + rnd(-2, 2)).toFixed(1), L: 'PlusTick', i: String(Math.random()), BT: false, RPI: false })) })
      ws.onMessage(m => {
        let r; try { r = JSON.parse(String(m)) } catch { return }
        if (r.op === 'ping') return ws.send(JSON.stringify({ success: true, ret_msg: 'pong', op: 'ping' }))
        if (r.op !== 'subscribe') return
        ws.send(JSON.stringify({ success: true, ret_msg: 'subscribe', op: 'subscribe' }))
        for (const a of r.args || []) {
          const mm = /^orderbook\.\d+\.(.+)$/.exec(a)
          if (!mm) continue
          const sym = mm[1], b = books.get(sym) || { u: 0, tick: sym.endsWith('USD') ? 0.5 : 0.1 }
          books.set(sym, b)
          setTimeout(() => snapshot(sym, b), 50)
        }
      })
      // 增量 20 帧/秒、成交 53 帧/秒（每本）
      timers.push(setInterval(() => { if (LOAD.on) for (const [s, b] of books) if (b.u) delta(s, b) }, 50))
      timers.push(setInterval(() => { if (LOAD.on) for (const s of books.keys()) trades(s) }, 19))
      ws.onClose(() => timers.forEach(clearInterval))
    })
    // HL 中继：每帧整本 20 档（BTC 4 位有效数字 = 10 美元一格），6 帧/秒；成交 23 帧/秒
    await ctx.routeWebSocket(/\/v1\/market\/ws\/hyperliquid/, ws => {
      const coins = new Set(), timers = []
      const send = o => { const t = JSON.stringify(o); LOAD.sent++; LOAD.bytes += t.length; ws.send(t) }
      const g = Math.round(px0 / 10) * 10
      const lv = sign => Array.from({ length: 20 }, (_, i) => ({ px: (g + sign * 10 * (i + (sign > 0 ? 1 : 0))).toFixed(1), sz: (i === 7 || i === 15 ? rnd(40, 90) : LOAD.churn && Math.random() < 0.05 ? rnd(30, 90) : rnd(1, 20)).toFixed(5), n: 10 }))
      const book = c => send({ channel: 'l2Book', data: { coin: c, time: Date.now(), levels: [lv(-1), lv(1)] } })
      ws.onMessage(m => {
        let r; try { r = JSON.parse(String(m)) } catch { return }
        if (r.method === 'ping') return ws.send(JSON.stringify({ channel: 'pong' }))
        if (r.method !== 'subscribe') return
        ws.send(JSON.stringify({ channel: 'subscriptionResponse', data: r }))
        if (r.subscription?.type === 'l2Book') { coins.add(r.subscription.coin); setTimeout(() => book(r.subscription.coin), 50) }
      })
      timers.push(setInterval(() => { if (LOAD.on) for (const c of coins) book(c) }, 167))
      timers.push(setInterval(() => { if (LOAD.on) for (const c of coins) send({ channel: 'trades', data: [{ coin: c, side: Math.random() < 0.5 ? 'B' : 'A', px: (px0 + rnd(-5, 5)).toFixed(1), sz: rnd(0.001, 2).toFixed(5), time: Date.now(), tid: Math.floor(Math.random() * 1e12) }] }) }, 43))
      ws.onClose(() => timers.forEach(clearInterval))
    })
    const page = await ctx.newPage()
    const cdp = await ctx.newCDPSession(page); await cdp.send('Performance.enable')
    const errs = []; page.on('pageerror', e => errs.push(String(e)))
    await page.goto(url + '#chart')
    await page.waitForFunction(() => window.__cells?.()?.length === 16 && window.__cells().every(c => c.bars > 0), null, { timeout: 60000 })
    await sleep(8000)
    const grid = await page.evaluate(() => { const cs = [...document.querySelectorAll('.chart-cell')].map(e => e.getBoundingClientRect()); const x = Math.min(...cs.map(r => r.x)), y = Math.min(...cs.map(r => r.y)); return { x, y, w: Math.max(...cs.map(r => r.right)) - x, h: Math.max(...cs.map(r => r.bottom)) - y } })
    const rect = await page.evaluate(() => { const r = document.querySelector('.chart-cell .canvas-host').getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height } })
    const venues = () => page.evaluate(() => (window.__of?.()?.venues || []).map(v => `${v.exchange}:${v.product}:${v.ready ? 'ready' : '…'}`))
    const row = async (name, fn) => {
      const s0 = LOAD.sent, b0 = LOAD.bytes, t0 = Date.now()
      const r = await measure(page, cdp, fn)
      const m = await metrics(cdp, page, false)
      const sec = (Date.now() - t0) / 1000
      const gc = await metrics(cdp, page)
      const o = { 段: name, ...r, 合成帧每秒: Math.round((LOAD.sent - s0) / sec), 合成KB每秒: Math.round((LOAD.bytes - b0) / sec / 1024), 堆: m.heap, GC后堆: gc.heap, 节点: m.nodes, 大单: await page.evaluate(() => window.__of?.()?.orders) }
      console.log(JSON.stringify(o)); out.push(o); return o
    }
    const sweep = async () => { for (let i = 0; i < 600; i++) { const t = i / 600; await page.mouse.move(grid.x + 20 + (grid.w - 40) * ((t * 4) % 1), grid.y + 20 + (grid.h - 40) * t); await sleep(4) } }
    const cx = rect.x + rect.w * 0.5, cy = rect.y + rect.h * 0.3
    const wheel = async () => { await page.mouse.move(cx, cy); for (let i = 0; i < 300; i++) { await page.mouse.wheel(0, i % 60 < 30 ? 40 : -40); await sleep(4) } }
    await row('四家真流（Bybit / HL 不发帧）常态 10 秒', () => sleep(10000))
    await row('四家真流 十字线扫十六格 600 下', sweep)
    await row('四家真流 第一格滚轮 300 下', wheel)
    LOAD.on = true
    await sleep(3000)
    console.log(JSON.stringify({ 订单流簿: await venues(), 大单: await page.evaluate(() => window.__of?.()?.orders) }))
    await row('五家满载 常态 10 秒', () => sleep(10000))
    await row('五家满载 十字线扫十六格 600 下', sweep)
    await row('五家满载 第一格滚轮 300 下', wheel)
    await row('五家满载 常态 30 秒（看堆是否涨）', () => sleep(30000))
    LOAD.churn = true
    await row('极端：每帧随机冒大单 常态 10 秒', () => sleep(10000))
    await row('极端：每帧随机冒大单 十字线扫十六格 600 下', sweep)
    await row('极端：每帧随机冒大单 常态 30 秒', () => sleep(30000))
    LOAD.churn = false
    await row('回到正常满载 30 秒（堆回落）', () => sleep(30000))
    console.log(JSON.stringify({ 订单流簿: await venues(), 大单: await page.evaluate(() => window.__of?.()?.orders), 报错: errs.slice(0, 5) }))
    await ctx.close()
  } finally { await browser.close(); stop() }
  return out
}

const SEGS = { cold, 'leak-pc': leakPc, 'leak-m': leakM, idle, big, hf, storage, server, sidebar, 'tabs-m': tabsM, 'scan-m': scanM, of5 }
if (!SEGS[SEG]) { console.error('未知段 ' + SEG + '；可选 ' + Object.keys(SEGS).join(' ')); process.exit(2) }
await SEGS[SEG]()
process.exit(0)
