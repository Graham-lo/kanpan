// Hkline Web · 多图布局（最多 16 格）专项审查走查（2026-10-07）
//   先 npx vite build --outDir /tmp/kp-layout16/dist，再 node scripts/layout16-review.mjs [段...]；
//   脚本自己起 vite preview（端口 5304，--outDir 同上，不碰别人的 dist），跑完杀掉。一次只开一个浏览器。
//   K 线 REST 用合成数据（f-lib.mjs mockKlines），WebSocket 走线上网关（只读）。
//   段：a1 布局切换 · a2 当前格 · a4 十字线联动 · a5 分隔条 · a6 全屏与右键 · a7 十六格可读性 · a8 窗口尺寸 · a9 画线共享
//       p0 自选 300 + 十六格跟推送 · b10 1↔16 ×20 · b11 十六格换品种 ×50 · b12 刷新恢复 · c13 性能（对照 F 线 big）· c14 长会话内存 · c15 挂机 3 分钟
//   不给段 = 全跑（约 20 分钟）。逐项打 ✓ / ✗（· 为只记数不判），截图与 results.json 写到 /tmp/kp-layout16/。
import { spawn } from 'node:child_process'
import fs from 'node:fs'
import { launch, INSTR, metrics, measure, sleep, med, pct, PC, heavyPc, newCtx } from './f-lib.mjs'

const PORT = 5304
const OUT = '/tmp/kp-layout16'
const DIST = process.env.L16_DIST || `${OUT}/dist`
fs.mkdirSync(OUT, { recursive: true })
const KEY = 'hkline-web-v1', SIZE_KEY = 'hkline-web-sizes-v1'
const LAYS = [['1', '一图', 1], ['2', '左右两图', 2], ['2v', '上下两图', 2], ['3', '左一右二', 3], ['4', '四图', 4], ['6', '六图（三列两行）', 6], ['8', '八图（四列两行）', 8], ['9', '九图（三列三行）', 9], ['12', '十二图（四列三行）', 12], ['16', '十六图（四列四行）', 16]]
const LAB = Object.fromEntries(LAYS.map(([k, l]) => [k, l]))
const N = Object.fromEntries(LAYS.map(([k, , n]) => [k, n]))
const IVMS = { '1m': 6e4, '3m': 18e4, '5m': 3e5, '15m': 9e5, '30m': 18e5, '1h': 36e5, '2h': 72e5, '4h': 144e5, '6h': 216e5, '12h': 432e5, '1d': 864e5, '1w': 6048e5 }
const same = c => c.metaSym === c.symbol && (IVMS[c.iv] == null || c.metaIv === IVMS[c.iv])

// ───────── 结果
const R = [], DATA = {}
const ok = (id, name, pass, info = '') => { R.push({ id, name, pass: !!pass, info }); console.log(`${pass ? '✓' : '✗'} [${id}] ${name}${info ? '  — ' + info : ''}`) }
const note = (id, name, info = '') => { R.push({ id, name, pass: null, info }); console.log(`· [${id}] ${name}${info ? '  — ' + info : ''}`) }
const flush = () => fs.writeFileSync(`${OUT}/results.json`, JSON.stringify({ at: new Date().toISOString(), results: R, data: DATA }, null, 1))

// ───────── 预览服务（独立 outDir，不与别的代理共用 dist）
function preview() {
  const srv = spawn(new URL('../node_modules/.bin/vite', import.meta.url).pathname, ['preview', '--port', String(PORT), '--strictPort', '--outDir', DIST], { cwd: new URL('..', import.meta.url).pathname, stdio: ['ignore', 'pipe', 'pipe'] })
  const stop = () => { try { srv.kill('SIGTERM') } catch { /* 已退 */ } }
  process.on('exit', stop); process.on('SIGINT', () => { stop(); process.exit(130) })
  return new Promise((res, rej) => {
    srv.stdout.on('data', d => { if (/localhost:/.test(String(d))) res({ url: `http://localhost:${PORT}/web/`, stop }) })
    srv.stderr.on('data', d => { if (!/EPIPE|ECONNRESET|ws proxy|    at /.test(String(d))) process.stderr.write(d) })
    srv.on('exit', c => rej(new Error('preview 退出 ' + c))); setTimeout(() => rej(new Error('preview 起不来')), 20000)
  })
}

// ───────── 页内探针补充：每块画布整幅清屏次数（≈ 重画次数）
const DRAWCOUNT = () => {
  const m = new WeakMap(); let all = 0
  const cr = CanvasRenderingContext2D.prototype.clearRect
  CanvasRenderingContext2D.prototype.clearRect = function (x, y, w, h) {
    if (x === 0 && y === 0) { all++; m.set(this.canvas, (m.get(this.canvas) || 0) + 1) }
    return cr.call(this, x, y, w, h)
  }
  // 每格把格子里所有画布的清屏次数加起来（主图之外还有十字线 / 订单流等叠加层）
  window.__redraw = () => ({ all, per: [...document.querySelectorAll('.chart-cell')].map(e => [...e.querySelectorAll('canvas')].reduce((a, c) => a + (m.get(c) || 0), 0)) })
}

// ───────── 状态
async function baseState(over = {}) {
  const hp = await heavyPc(30)
  return { ...hp, layout: '1', active: 0, orderFlow: false, drawings: {}, ind: { ma: true, ema: false, boll: false, vol: true, subs: ['macd', 'rsi'] }, ...over }
}

let browser, URL_
async function open(state, opt = PC, mock = { delay: 120, local: true, depth: 6000 }, q = '#chart') {
  const { ctx, count } = await newCtx(browser, opt, { [KEY]: JSON.stringify(state) }, mock)
  await ctx.addInitScript(DRAWCOUNT)
  const page = await ctx.newPage()
  const errs = [], kl = []
  page.on('pageerror', e => errs.push('pageerror ' + String(e).slice(0, 200)))
  page.on('console', m => { if (m.type() === 'error' && !/Failed to load resource|WebSocket connection/.test(m.text())) errs.push(m.text().slice(0, 200)) })
  page.on('request', r => { if (/\/klines\?/.test(r.url())) kl.push({ u: r.url(), t0: Date.now(), t1: null, req: r }) })
  page.on('requestfinished', r => { const x = kl.find(k => k.req === r); if (x) x.t1 = Date.now() })
  page.on('requestfailed', r => { const x = kl.find(k => k.req === r); if (x) x.t1 = Date.now() })
  const cdp = await ctx.newCDPSession(page); await cdp.send('Performance.enable')
  await page.goto(URL_ + q, { waitUntil: 'domcontentloaded' })
  return { ctx, page, cdp, count, errs, kl }
}
const cellsOf = page => page.evaluate(() => window.__cells?.() || [])
async function waitCells(page, n, ms = 30000) {
  return page.waitForFunction(n => { const c = window.__cells?.(); return c && c.length === n && c.every(x => x.bars > 0) }, n, { timeout: ms }).then(() => true, () => false)
}
// 页内点（同样走 #tbLayout 与菜单项的 click 处理）：Playwright 的 locator.click 会在它的隔离环境里留着元素句柄，
// 关掉的菜单因此一直摘不掉，节点数每轮 +180 左右，看起来像泄漏（2026-10-07 queryObjects 核实：页内点就不涨）
async function pickLayout(page, k) {
  await page.evaluate(l => {
    document.querySelector('#tbLayout').click()
    const b = [...document.querySelectorAll('.menu .mi')].find(x => x.querySelector('.label')?.textContent.trim() === l)
    if (!b) throw new Error('菜单里没有 ' + l)
    b.click()
  }, LAB[k])
}
const menuToggle = (page, label) => page.evaluate(l => { document.querySelector('#tbLayout').click(); [...document.querySelectorAll('.menu .mi')].find(x => x.textContent.includes(l)).click() }, label)
const stateOf = page => page.evaluate(k => JSON.parse(localStorage.getItem(k) || '{}'), KEY)
const sizesOf = page => page.evaluate(k => JSON.parse(localStorage.getItem(k) || '{}'), SIZE_KEY)
const hostRects = page => page.evaluate(() => [...document.querySelectorAll('.chart-cell .canvas-host')].map(e => { const r = e.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height } }))
const cellRects = page => page.evaluate(() => [...document.querySelectorAll('.chart-cell')].map(e => { const r = e.getBoundingClientRect(); return { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) } }))
const activeIdx = page => page.evaluate(() => [...document.querySelectorAll('.chart-cell')].findIndex(e => e.classList.contains('active')))
const noScroll = page => page.evaluate(() => {
  const d = document.documentElement
  const over = [...document.querySelectorAll('.chart-cell, #sidePanel, #chartArea')].filter(e => { const r = e.getBoundingClientRect(); return r.width && (r.right > innerWidth + 1 || r.bottom > innerHeight + 1) }).length
  return { ok: d.scrollWidth <= innerWidth && d.scrollHeight <= innerHeight && !over, info: `${d.scrollWidth}×${d.scrollHeight} / ${innerWidth}×${innerHeight}${over ? ` 溢出 ${over} 块` : ''}` }
})
const lsBytes = page => page.evaluate(() => { let n = 0; for (let i = 0; i < localStorage.length; i++) { const k = localStorage.key(i); n += k.length + (localStorage.getItem(k) || '').length } return n })
const shot = async (page, name, clip) => { await page.screenshot({ path: `${OUT}/${name}.png`, ...(clip ? { clip } : {}) }); return `${OUT}/${name}.png` }
const center = r => ({ x: r.x + r.w * 0.45, y: r.y + r.h * 0.4 })
async function clickCell(page, i) { const r = (await hostRects(page))[i]; const p = center(r); await page.mouse.click(p.x, p.y) }
const away = page => page.mouse.move(5, 300) // 移到画线栏上，十字线收起
/** 当前订阅里的 K 线流与格子对得上吗：多出来的（旧格 / 旧品种没退订）与缺的 */
async function streamsVsCells(page) {
  return page.evaluate(() => {
    const cs = window.__cells(), sub = window.__stream().subscribed
    const want = new Set(cs.map(c => `${c.symbol.toLowerCase()}@kline_${c.iv}`))
    const have = new Set(sub.filter(s => s.includes('@kline_')))
    return { want: want.size, have: have.size, extra: [...have].filter(s => !want.has(s)), missing: [...want].filter(s => !have.has(s)), total: sub.length, conns: window.__stream().conns }
  })
}
/** 起一个逐帧采样，盯到布局换成 want 格且每格都有 K 线：空格帧数、最多同时空几格、原有格子是否闪空 */
const TRANS = () => {
  window.__transStart = (want, keep) => {
    window.__transRes = new Promise(res => {
      const t0 = performance.now(); let frames = 0, blankFrames = 0, maxBlank = 0, keptBlank = 0, seenN = false
      const go = () => {
        frames++
        const cs = window.__cells()
        if (cs.length === want) seenN = true
        if (seenN) {
          const b = cs.filter(c => !c.bars).length
          if (b) blankFrames++
          maxBlank = Math.max(maxBlank, b)
          if (cs.slice(0, keep).some(c => !c.bars)) keptBlank++
          if (!b) return res({ ms: Math.round(performance.now() - t0), frames, blankFrames, maxBlank, keptBlank })
        }
        if (performance.now() - t0 > 30000) return res({ ms: -1, frames, blankFrames, maxBlank, keptBlank, timeout: true, blank: cs.filter(c => !c.bars).length })
        requestAnimationFrame(go)
      }
      requestAnimationFrame(go)
    })
  }
}

// ═════════════════ A1 十种布局切换
async function a1() {
  const st = await baseState()
  const { ctx, page, errs, count } = await open(st, PC, { delay: 250, local: true, depth: 6000 })
  await page.addInitScript(TRANS); await page.evaluate(TRANS)
  await waitCells(page, 1)
  const rows = []
  let prev = 1
  const seq = ['2', '2v', '3', '4', '6', '8', '9', '12', '16', '1', '16', '4', '16']
  for (let s = 0; s < seq.length; s++) {
    const k = seq[s], want = N[k]
    // 倒数第二步（16→4）先把当前格放到第 13 格，看缩布局后当前格落在哪
    if (k === '4' && prev === 16) { await clickCell(page, 12); await sleep(200) }
    const actBefore = await activeIdx(page)
    await page.evaluate(([w, kp]) => window.__transStart(w, kp), [want, Math.min(prev, want)])
    const k0 = count.n
    await pickLayout(page, k)
    if (k === '16' && prev === 1) await shot(page, `A1-一图到十六图-过渡`)
    const tr = await page.evaluate(() => window.__transRes)
    await sleep(300)
    const nAct = await page.evaluate(() => document.querySelectorAll('.chart-cell.active').length)
    const act = await activeIdx(page), sc = await noScroll(page)
    const focus = await page.evaluate(() => { const a = document.activeElement; return a ? (a.id || a.tagName + (a.className ? '.' + String(a.className).split(' ')[0] : '')) : 'null' })
    rows.push({ 从: prev, 到: k, 格: want, ...tr, K线请求: count.n - k0, 当前格: `${actBefore}→${act}`, 焦点: focus, 滚动条: sc.ok ? '无' : sc.info })
    ok('A1', `${prev}→${LAB[k]}：${want} 格齐、只有一格高亮、无滚动条`, !tr.timeout && nAct === 1 && sc.ok, `用时 ${tr.ms} ms，空格帧 ${tr.blankFrames}（最多同时空 ${tr.maxBlank} 格），原有格闪空帧 ${tr.keptBlank}，K 线请求 ${count.n - k0}，当前格 ${actBefore}→${act}，焦点 ${focus}`)
    if (tr.keptBlank) ok('A1', `${prev}→${LAB[k]}：保留下来的格子不闪空`, false, `${tr.keptBlank} 帧`)
    if (['3', '16', '12'].includes(k)) await shot(page, `A1-布局-${k}`)
    prev = want
  }
  DATA.a1 = rows
  // 切完布局，键盘还作用在当前格吗（焦点没被菜单吃掉）
  const a = await activeIdx(page), iv0 = (await cellsOf(page)).map(c => c.iv)
  await page.keyboard.press('2'); await sleep(600)
  const iv1 = (await cellsOf(page)).map(c => c.iv)
  const changed = iv1.map((v, i) => v !== iv0[i] ? i : -1).filter(i => i >= 0)
  ok('A1', '切完布局直接按数字键 2：只改当前格周期', changed.length === 1 && changed[0] === a, `当前格 ${a}，被改的格 ${JSON.stringify(changed)}`)
  // 16→1：第 0 格以外的格子销毁后，st.cells 仍留着 16 份配置，回到 16 时恢复原样
  const st16 = (await cellsOf(page)).map(c => c.symbol + '/' + c.iv)
  await pickLayout(page, '1'); await sleep(500); await pickLayout(page, '16'); await waitCells(page, 16)
  const st16b = (await cellsOf(page)).map(c => c.symbol + '/' + c.iv)
  ok('A1', '16→1→16：每格品种 / 周期原样回来', JSON.stringify(st16) === JSON.stringify(st16b), st16b.slice(0, 4).join(' '))
  ok('A1', '布局切换段：控制台无报错', !errs.length, errs.slice(0, 3).join(' | '))
  await ctx.close()
}

// ═════════════════ A2 当前格：高亮、工具栏跟随、快捷键作用对象；A3 每格自己的品种周期、指标全局
async function a2() {
  const cells = [['BTCUSDT', '1h'], ['ETHUSDT', '4h'], ['SOLUSDT', '15m'], ['XAUUSDT', '1d']].map(([symbol, iv]) => ({ symbol, iv }))
  const st = await baseState({ layout: '4', cells: cells.concat((await heavyPc(30)).cells.slice(4)) })
  const { ctx, page, cdp, errs } = await open(st)
  await waitCells(page, 4); await sleep(800)
  await clickCell(page, 2); await sleep(300)
  const tb = await page.evaluate(() => ({ sym: document.querySelector('#tbSymbol')?.textContent || '', iv: document.querySelector('#toolbar .intervals [aria-pressed="true"]')?.dataset.iv }))
  ok('A2', '点第 3 格：高亮到第 3 格，工具栏品种 / 周期跟着变', (await activeIdx(page)) === 2 && /^\s*SOL/.test(tb.sym) && tb.iv === '15m', `高亮 ${await activeIdx(page)}，工具栏 ${tb.sym.trim().slice(0, 20)} / ${tb.iv}`)
  await page.keyboard.press('1'); await sleep(700)
  let cs = await cellsOf(page)
  ok('A2', '按 1：只有当前格换到 1 分', cs[2].iv === '1m' && cs[0].iv === '1h' && cs[1].iv === '4h' && cs[3].iv === '1d', cs.map(c => c.iv).join(' '))
  await page.keyboard.press('/'); await sleep(400)
  const dlg = await page.evaluate(() => !!document.querySelector('.dialog[role=dialog]'))
  ok('A2', '按 /：指标面板打开', dlg)
  await page.keyboard.press('Escape'); await sleep(300)
  // 2026-10-10 起整页一条全局底栏（作用于当前格）：先点第 4 格设成当前格，底栏左头跟着写「作用于 · 格 4」，再点底栏的时间区间
  const cellN = await page.evaluate(() => document.querySelectorAll('.chart-cell .cell-foot').length)
  ok('A2', '格子里不再各带一条底栏，整页只有图表区下面一条', cellN === 0 && (await page.locator('#chartFoot').count()) === 1, `格内底栏 ${cellN} 条`)
  await clickCell(page, 3); await sleep(300)
  const lab = await page.evaluate(() => document.querySelector('#chartFoot .foot-target')?.textContent?.trim() || '')
  ok('A2', '点第 4 格：底栏左头写「作用于 · 格 4」', lab.startsWith('作用于 · 格 4'), lab)
  await page.locator('#chartFoot [data-range="0"]').click().catch(() => {}); await sleep(900)
  cs = await cellsOf(page)
  const actAfter = await activeIdx(page), tb2 = await page.evaluate(() => document.querySelector('#toolbar .intervals [aria-pressed="true"]')?.dataset.iv)
  ok('A2', '底栏的时间区间作用于当前格（第 4 格），当前格不变', actAfter === 3, `高亮 ${actAfter}，第 4 格周期 ${cs[3].iv}，工具栏显示 ${tb2}`)
  ok('A2', '底栏时间区间换周期走工具栏同一入口：第 4 格 1 分、工具栏跟着显示 1 分、别的格不动', cs[3].iv === '1m' && tb2 === '1m' && cs[0].iv === '1h' && cs[1].iv === '4h', cs.map(c => c.iv).join(' ') + ` 工具栏 ${tb2}`)
  // 每格右下角「对数 / 自动」：悬停才露出来，点了只改这一格（不切当前格）
  {
    const hr0 = await hostRects(page), p1 = center(hr0[1])
    await page.mouse.move(p1.x, p1.y); await sleep(250)
    const vis1 = await page.evaluate(() => [...document.querySelectorAll('.chart-cell')].map(e => getComputedStyle(e.querySelector('.cfoot')).visibility))
    await page.locator('.chart-cell').nth(1).locator('.cfoot [data-act="log"]').click(); await sleep(300)
    const logs = await page.evaluate(() => [...document.querySelectorAll('.chart-cell .cfoot [data-act="log"]')].map(b => b.getAttribute('aria-pressed')))
    const footLog = await page.evaluate(() => document.querySelector('#chartFoot [data-act="log"]')?.getAttribute('aria-pressed'))
    ok('A2', '悬停第 2 格：它和当前格（第 4 格）的「对数 / 自动」露出来，别的格藏着', vis1[1] === 'visible' && vis1[3] === 'visible' && vis1[0] === 'hidden' && vis1[2] === 'hidden', vis1.join(' '))
    ok('A2', '点第 2 格右下角「对数」：只有第 2 格开对数；当前格仍是第 4 格、底栏的「对数」跟着第 4 格（关）', logs.join(',') === 'false,true,false,false' && (await activeIdx(page)) === 3 && footLog === 'false', `各格 ${logs.join(',')}，当前 ${await activeIdx(page)}，底栏 ${footLog}`)
    await shot(page, 'A2-四图-悬停格子右下角')
    await page.locator('.chart-cell').nth(1).locator('.cfoot [data-act="log"]').click(); await sleep(200)
  }
  // 右键非当前格：激活
  // A3：每格图例与价格轴各显示自己的品种
  const leg = await page.evaluate(() => [...document.querySelectorAll('.chart-cell')].map(e => e.querySelector('.legend .title')?.textContent?.trim().slice(0, 30) || ''))
  cs = await cellsOf(page)
  ok('A3', '每格图例标题是自己的品种、图上数据与配置一致', cs.every((c, i) => leg[i].includes(c.symbol.replace(/USDT$/, '')) && same(c)), leg.join(' | '))
  const paneIds = cs.map(c => (c.panes || []).map(p => p[0]).join(','))
  ok('A3', '指标是全局一份：四格副图一样', new Set(paneIds).size === 1, paneIds.join(' / '))
  // 周期跨图同步开着时，点非当前格底栏的区间：这一格变当前格，其余格跟着换周期
  {
    const o2 = await open(await baseState({ layout: '4', linkIv: true, cells: cells.concat((await heavyPc(30)).cells.slice(4)) }))
    await waitCells(o2.page, 4); await sleep(600)
    await clickCell(o2.page, 1); await sleep(300)
    await o2.page.locator('#chartFoot [data-range="1"]').click().catch(() => {}); await sleep(900)
    const c2 = await cellsOf(o2.page)
    ok('A2', '周期跨图同步开着：点第 2 格再点底栏「5天」→ 第 2 格当前、四格都换 5 分', (await activeIdx(o2.page)) === 1 && c2.every(c => c.iv === '5m'), `高亮 ${await activeIdx(o2.page)}，周期 ${c2.map(c => c.iv).join(' ')}`)
    await o2.ctx.close()
  }
  // A2：十六格里逐格点选的代价（setActive → renderToolbar + renderPanel + layoutSlots）
  await pickLayout(page, '16'); await waitCells(page, 16); await sleep(1500)
  const hr = await hostRects(page)
  const per = []
  const m = await measure(page, cdp, async () => {
    for (let i = 0; i < 16; i++) {
      const p = center(hr[i])
      const t = await page.evaluate(([x, y]) => new Promise(res => {
        const el = document.elementFromPoint(x, y), t0 = performance.now()
        el.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, clientX: x, clientY: y, button: 0 }))
        el.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, clientX: x, clientY: y, button: 0 }))
        const t1 = performance.now()
        requestAnimationFrame(() => requestAnimationFrame(() => res([t1 - t0, performance.now() - t0])))
      }), [p.x, p.y])
      per.push(t); await sleep(120)
    }
  })
  DATA.a2Activate = { 同步耗时ms: per.map(x => +x[0].toFixed(1)), 到下一帧ms: per.map(x => +x[1].toFixed(1)), ...m }
  ok('A2', '十六格逐格点选：每次切当前格同步耗时 < 16 ms', med(per.map(x => x[0])) < 16, `中位 ${med(per.map(x => x[0])).toFixed(1)} ms、最大 ${Math.max(...per.map(x => x[0])).toFixed(1)} ms；16 次共布局 ${m.layouts} 次、样式重算 ${m.recalcs} 次、长任务 ${m.lt}`)
  await shot(page, 'A2-十六图-当前格高亮')
  ok('A2', '当前格段：控制台无报错', !errs.length, errs.slice(0, 3).join(' | '))
  await ctx.close()
}

// ═════════════════ A4 十字线联动
async function a4() {
  const hp = await heavyPc(30)
  const cells = hp.cells.map((c, i) => ({ ...c, iv: i === 5 ? '4h' : i === 6 ? '1d' : '1h' }))
  const st = await baseState({ layout: '16', cells, linkCross: true })
  const { ctx, page, cdp, errs } = await open(st)
  await waitCells(page, 16); await sleep(1500)
  const hr = await hostRects(page)
  const p = center(hr[0])
  await page.mouse.move(p.x, p.y); await page.mouse.move(p.x + 10, p.y)
  const r = await page.evaluate(() => new Promise(res => requestAnimationFrame(() => res(window.__cells().map(c => c.cross)))))
  const same = r.slice(1).filter((c, i) => c != null && (i + 1 === 5 || i + 1 === 6 || c === r[1])).length
  ok('A4', '第 1 格动十字线：其余 15 格在同一帧内都显示同步十字线', same === 15, `有十字线的格 ${r.filter(x => x != null).length - 0}/16（第 1 格自己不记 extCross）；4h、1d 格取到 ${r[5]}、${r[6]}`)
  await shot(page, 'A4-十字线联动', { x: hr[0].x - 4, y: hr[0].y - 4, width: hr[3].x + hr[3].w - hr[0].x + 8, height: hr[4].y + hr[4].h - hr[0].y + 8 })
  await away(page); await sleep(100)
  const r2 = await cellsOf(page)
  ok('A4', '鼠标离开：所有格的同步十字线都收起', r2.every(c => c.cross == null), r2.filter(c => c.cross != null).length + ' 格残留')
  // 每次 mousemove 的同步成本
  const cost = await page.evaluate(([x, y]) => {
    const cv = document.elementFromPoint(x, y), out = []
    for (let i = 0; i < 200; i++) { const t0 = performance.now(); cv.dispatchEvent(new MouseEvent('mousemove', { bubbles: true, clientX: x + (i % 50) * 3, clientY: y })); out.push(performance.now() - t0) }
    out.sort((a, b) => a - b); return { p50: out[100], p95: out[190], max: out[199] }
  }, [p.x, p.y])
  DATA.a4 = cost
  ok('A4', '一次 mousemove 联动 15 格的同步代价 < 2 ms（p95）', cost.p95 < 2, `p50 ${cost.p50.toFixed(2)} ms、p95 ${cost.p95.toFixed(2)} ms、max ${cost.max.toFixed(2)} ms`)
  void cdp
  ok('A4', '十字线段：控制台无报错', !errs.length, errs.slice(0, 3).join(' | '))
  await ctx.close()
}

// ═════════════════ A5 分隔条：网格、侧栏、主副图；松手落盘、刷新还原、不出零高、无滚动条
async function a5() {
  const st = await baseState({ layout: '4' })
  const { ctx, page, errs } = await open(st)
  await waitCells(page, 4); await sleep(800)
  const box = name => page.locator(`.splitter[data-split="${name}"]`).boundingBox()
  async function drag(name, dx, dy, at = 0.3, steps = 12) {
    const b = await box(name); if (!b) throw new Error('没有分隔条 ' + name)
    const x = b.width > b.height ? b.x + b.width * at : b.x + b.width / 2, y = b.width > b.height ? b.y + b.height / 2 : b.y + b.height * at
    await page.mouse.move(x, y); await page.mouse.down()
    const w0 = await page.evaluate(k => window.__f.ls.byKey[k]?.n || 0, SIZE_KEY)
    await page.mouse.move(x + dx, y + dy, { steps })
    const w1 = await page.evaluate(k => window.__f.ls.byKey[k]?.n || 0, SIZE_KEY)
    await page.mouse.up(); await sleep(400)
    const w2 = await page.evaluate(k => window.__f.ls.byKey[k]?.n || 0, SIZE_KEY)
    return { during: w1 - w0, after: w2 - w1 }
  }
  const r0 = await cellRects(page)
  const w = await drag('grid-cols-0', 300, 0)
  const r1 = await cellRects(page), s1 = await sizesOf(page)
  ok('A5', '网格竖线右拖 300：左列变宽、拖动中不写盘、松手写一次', r1[0].w > r0[0].w + 250 && w.during === 0 && w.after >= 1, `左列 ${r0[0].w}→${r1[0].w}；拖动中写 ${w.during} 次、松手写 ${w.after} 次；存档 cols ${JSON.stringify(s1.grid?.['4']?.cols)}`)
  await page.reload({ waitUntil: 'domcontentloaded' }); await waitCells(page, 4); await sleep(600)
  const r2 = await cellRects(page)
  ok('A5', '刷新后网格比例还原', Math.abs(r2[0].w - r1[0].w) <= 2, `${r1[0].w} → ${r2[0].w}`)
  await drag('grid-cols-0', -4000, 0)
  const r3 = await cellRects(page), sc3 = await noScroll(page)
  ok('A5', '网格竖线拖到最左：左列不小于 240、无滚动条', r3[0].w >= 236 && sc3.ok, `左列 ${r3[0].w}；${sc3.info}`)
  await drag('grid-rows-0', 0, 4000)
  const r4 = await cellRects(page), h4 = await hostRects(page), sc4 = await noScroll(page)
  ok('A5', '网格横线拖到最下：下行不小于 160、画布高 > 0、无滚动条', r4[2].h >= 156 && h4.every(h => h.h > 40) && sc4.ok, `下行 ${r4[2].h}，画布高 ${h4.map(h => Math.round(h.h)).join('/')}；${sc4.info}`)
  await shot(page, 'A5-四图-拖到极限')
  // 双击回平均
  const b = await box('grid-rows-0'); await page.mouse.dblclick(b.x + b.width * 0.3, b.y + b.height / 2); await sleep(400)
  const bc = await box('grid-cols-0'); await page.mouse.dblclick(bc.x + bc.width / 2, bc.y + bc.height * 0.3); await sleep(400)
  const r5 = await cellRects(page)
  ok('A5', '双击网格分隔线回平均', Math.abs(r5[0].w - r5[1].w) <= 3 && Math.abs(r5[0].h - r5[2].h) <= 3, JSON.stringify(r5.map(r => [r.w, r.h])))
  // 侧栏
  const pw0 = (await page.locator('#sidePanel').boundingBox()).width
  await drag('panel', -3000, 0)
  const pw1 = (await page.locator('#sidePanel').boundingBox()).width
  await drag('panel', 3000, 0)
  const pw2 = (await page.locator('#sidePanel').boundingBox()).width, sc5 = await noScroll(page)
  ok('A5', '侧栏拖到最宽 / 最窄：夹在 320–640、无滚动条', pw1 <= 642 && pw2 >= 318 && sc5.ok, `${pw0}→${pw1}→${pw2}`)
  // 主副图分隔线（四图格子够大，不降级）
  const c0 = (await cellsOf(page))[0]
  const host0 = (await hostRects(page))[0]
  const sepY = host0.y + c0.panes[1][1]
  await page.mouse.move(host0.x + 200, sepY)
  const cur = await page.evaluate(() => document.querySelector('.chart-cell canvas').style.cursor)
  await page.mouse.down(); await page.mouse.move(host0.x + 200, sepY - 4000, { steps: 10 }); await page.mouse.up(); await sleep(300)
  let cs = await cellsOf(page)
  const minMain = Math.min(...cs.map(c => c.panes[0][2])), minSub = Math.min(...cs.flatMap(c => c.panes.slice(1).map(p => p[2])))
  ok('A5', '主副图分隔线往上拖到底：主图不塌成 0、四格副图比例一起变', cur === 'row-resize' && minMain > 40 && minSub > 20 && new Set(cs.map(c => c.panes.map(p => p[2]).join(','))).size <= 2, `光标 ${cur}；主图最矮 ${minMain}、副图最矮 ${minSub}；${cs.map(c => c.panes.map(p => p[2]).join('/')).join(' | ')}`)
  await shot(page, 'A5-副图分隔拖到顶')
  const sp = (await sizesOf(page)).panes
  await page.reload({ waitUntil: 'domcontentloaded' }); await waitCells(page, 4); await sleep(600)
  const cs2 = await cellsOf(page)
  ok('A5', '刷新后主副图比例还原', JSON.stringify(cs2[0].panes.map(p => p[2])) === JSON.stringify(cs[0].panes.map(p => p[2])), `存档 ${JSON.stringify(sp)}；${cs[0].panes.map(p => p[2]).join('/')} → ${cs2[0].panes.map(p => p[2]).join('/')}`)
  // 十六格里网格拖到极限：每格最矮多少
  await pickLayout(page, '16'); await waitCells(page, 16); await sleep(600)
  await drag('grid-rows-0', 0, 4000); await drag('grid-rows-1', 0, 4000); await drag('grid-rows-2', 0, 4000)
  const h16 = await hostRects(page), sc6 = await noScroll(page)
  cs = await cellsOf(page)
  ok('A5', '十六图横线全拖到底：每格画布高 > 0、无滚动条', h16.every(h => h.h > 40) && sc6.ok, `画布高 ${[...new Set(h16.map(h => Math.round(h.h)))].join('/')}；${sc6.info}`)
  await shot(page, 'A5-十六图-横线拖到底')
  ok('A5', '分隔条段：控制台无报错', !errs.length, errs.slice(0, 3).join(' | '))
  await ctx.close()
}

// ═════════════════ A6 单格最大化（放大这一格）、双击、右键
async function a6() {
  const st = await baseState({ layout: '16' })
  const { ctx, page, errs } = await open(st)
  await waitCells(page, 16); await sleep(1000)
  const hr = await hostRects(page)
  const area = await page.evaluate(() => { const r = document.querySelector('#chartArea').getBoundingClientRect(); return { w: r.width, h: r.height } })
  const sv0 = await streamsVsCells(page)
  const zoomOf = () => page.evaluate(() => window.__zoom?.() ?? -2)
  const vis = () => page.evaluate(() => [...document.querySelectorAll('.chart-cell')].filter(e => e.getBoundingClientRect().width > 0).length)
  // 1) 双击第 6 格画布顶部（图例以外的空白，价格轴左边一点）
  const top5 = { x: hr[5].x + hr[5].w * 0.7, y: hr[5].y + 14 }
  await page.mouse.dblclick(top5.x, top5.y); await sleep(600)
  const big = (await hostRects(page))[5], cs = await cellsOf(page), sv1 = await streamsVsCells(page)
  ok('A6', '十六图里双击第 6 格顶部标题区：这一格放大铺满图表区（别的格子藏起来）', (await zoomOf()) === 5 && (await vis()) === 1 && big.w > area.w * 0.9 && big.h > hr[5].h * 2, `放大 ${await zoomOf()}、看得见 ${await vis()} 格、第 6 格 ${Math.round(big.w)}×${Math.round(big.h)}（之前 ${Math.round(hr[5].w)}×${Math.round(hr[5].h)}，图表区 ${Math.round(area.w)}×${Math.round(area.h)}）`)
  ok('A6', '放大时别的格子没销毁、行情没退订', cs.length === 16 && cs.every(c => c.bars > 0) && sv1.have === sv0.have && sv1.missing.length === 0, `格子 ${cs.length}、有 K 线 ${cs.filter(c => c.bars > 0).length}；K 线流 ${sv1.have}/${sv1.want}（放大前 ${sv0.have}）`)
  const saved = await page.evaluate(k => JSON.parse(localStorage.getItem(k) || '{}').layout, KEY)
  ok('A6', '放大不改布局存档', saved === '16', `存档布局 ${saved}`)
  await shot(page, 'A6-十六图-放大第6格')
  // 2) Esc 还原
  await page.mouse.move(big.x + big.w / 2, big.y + big.h / 2)
  await page.keyboard.press('Escape'); await sleep(500)
  const hr2 = await hostRects(page)
  ok('A6', 'Esc 还原：十六格回来、尺寸和放大前一样', (await zoomOf()) === -1 && (await vis()) === 16 && hr2.every((r, i) => Math.abs(r.w - hr[i].w) < 2 && Math.abs(r.h - hr[i].h) < 2), `放大 ${await zoomOf()}、看得见 ${await vis()} 格、第 6 格 ${Math.round(hr2[5].w)}×${Math.round(hr2[5].h)}`)
  // 3) ⌥↩ 放大当前格、再按还原
  await page.keyboard.press('Alt+Enter'); await sleep(500)
  const z1 = await zoomOf()
  await page.keyboard.press('Alt+Enter'); await sleep(500)
  const z2 = await zoomOf()
  ok('A6', '⌥↩ 放大当前格，再按一次还原', z1 === 5 && z2 === -1 && (await vis()) === 16, `第一次 ${z1}、第二次 ${z2}`)
  // 4) 全局底栏空白双击：放大当前格、再双击还原（先点第 3 格设成当前格）
  { const p2 = center((await hostRects(page))[2]); await page.mouse.click(p2.x, p2.y); await sleep(300) }
  const footBlank = () => page.evaluate(() => { const f = document.querySelector('#chartFoot'); const r = f.getBoundingClientRect(), fr = f.querySelector('.foot-right').getBoundingClientRect(); const bs = [...f.querySelectorAll(':scope > button')].filter(b => b.offsetWidth).map(b => b.getBoundingClientRect().right); return { x: (Math.max(...bs) + fr.left) / 2, y: r.y + r.height / 2 } })
  const foot = await footBlank()
  await page.mouse.dblclick(foot.x, foot.y); await sleep(500)
  const z3 = await zoomOf()
  const foot2 = await footBlank()
  await page.mouse.dblclick(foot2.x, foot2.y); await sleep(500)
  ok('A6', '点第 3 格、双击底栏空白：放大第 3 格；再双击还原', z3 === 2 && (await zoomOf()) === -1, `第一次 ${z3}、第二次 ${await zoomOf()}`)
  // 5) 画布中间双击不放大（留给画线 / 别的手势）
  const hr3 = await hostRects(page), mid = center(hr3[7])
  await page.mouse.dblclick(mid.x, mid.y); await sleep(400)
  ok('A6', '双击画布中间不放大', (await zoomOf()) === -1, `放大 ${await zoomOf()}`)
  // 6) 右键非当前格：先设成当前格，菜单里有「放大这一格」，点了放大；放大后右键菜单是「还原布局」
  const p9 = center(hr3[9])
  await page.mouse.click(p9.x, p9.y, { button: 'right' }); await sleep(400)
  const act = await activeIdx(page)
  const items = await page.evaluate(() => [...document.querySelectorAll('.menu .mi .label')].map(e => e.textContent.trim()))
  ok('A6', '右键第 10 格（非当前格）：先把它设成当前格，再弹菜单', act === 9 && items.length > 0, `高亮 ${act}；菜单 ${items.length} 项：${items.join('、').slice(0, 160)}`)
  ok('A6', '右键菜单有「放大这一格」', items.includes('放大这一格'), items.join('、').slice(-60))
  await shot(page, 'A6-十六图-右键菜单')
  await page.evaluate(() => [...document.querySelectorAll('.menu .mi')].find(e => e.textContent.includes('放大这一格'))?.click()); await sleep(500)
  const z4 = await zoomOf()
  const b9 = (await hostRects(page))[9], c9 = center(b9)
  await page.mouse.click(c9.x, c9.y, { button: 'right' }); await sleep(400)
  const items2 = await page.evaluate(() => [...document.querySelectorAll('.menu .mi .label')].map(e => e.textContent.trim()))
  await page.evaluate(() => [...document.querySelectorAll('.menu .mi')].find(e => e.textContent.includes('还原布局'))?.click()); await sleep(500)
  ok('A6', '菜单「放大这一格」放大第 10 格；放大后菜单变「还原布局」，点了还原', z4 === 9 && items2.includes('还原布局') && (await zoomOf()) === -1 && (await vis()) === 16, `放大 ${z4}、菜单 ${items2.slice(-2).join('、')}、还原后 ${await zoomOf()}`)
  // 7) 放大状态刷新后不保留
  await page.keyboard.press('Alt+Enter'); await sleep(400)
  const z5 = await zoomOf()
  await page.reload({ waitUntil: 'domcontentloaded' }); await waitCells(page, 16); await sleep(800)
  ok('A6', '放大着刷新页面：回到十六图（放大不存）', z5 === 9 && (await zoomOf()) === -1 && (await vis()) === 16, `刷新前 ${z5}、刷新后 ${await zoomOf()}、看得见 ${await vis()} 格`)
  await page.keyboard.press('Escape')
  ok('A6', '全屏与右键段：控制台无报错', !errs.length, errs.slice(0, 3).join(' | '))
  await ctx.close()
}

// ═════════════════ A7 十六格可读性；A8 窗口尺寸与 125% 缩放
const READ = () => [...document.querySelectorAll('.chart-cell')].map(e => {
  const h = e.querySelector('.canvas-host'), lg = e.querySelector('.legend'), ft = document.querySelector('#chartFoot')
  const hr = h.getBoundingClientRect(), lr = lg?.getBoundingClientRect()
  const fs = lg ? [...lg.querySelectorAll('*')].filter(x => x.childElementCount === 0 && x.textContent.trim() && !x.closest('.badge')).map(x => parseFloat(getComputedStyle(x).fontSize)) : []
  const footVis = ft ? [...ft.querySelectorAll('button, .clock, .conn-dot')].filter(b => b.offsetParent && getComputedStyle(b).display !== 'none') : []
  const fr = ft?.getBoundingClientRect()
  const footClip = footVis.filter(b => { const r = b.getBoundingClientRect(); return r.right > fr.right + 1 || r.left < fr.left - 1 }).length
  return {
    w: Math.round(hr.width), h: Math.round(hr.height), cls: ['c-tiny'].filter(c => e.classList.contains(c)).join(' '),
    legendH: lr ? Math.round(lr.height) : 0, legendRatio: lr ? +(lr.height / hr.height).toFixed(2) : 0, legendOver: lg ? lg.scrollWidth > lg.clientWidth + 1 : false,
    legendRows: lg ? lg.querySelectorAll('.lrow').length : 0, minFont: fs.length ? Math.min(...fs) : null,
    footH: fr ? Math.round(fr.height) : 0, footBtns: footVis.length, footClip, footOver: ft ? ft.scrollWidth > ft.clientWidth + 1 : false,
  }
})
async function a7a8() {
  const VIEWS = [
    ['1920×1080', { ...PC, viewport: { width: 1920, height: 1080 } }],
    ['2560×1440', PC],
    ['3440×1440', { ...PC, viewport: { width: 3440, height: 1440 } }],
    ['2560×1440 缩放 125%', { ...PC, viewport: { width: 2048, height: 1152 }, deviceScaleFactor: 1.25 }],
  ]
  const rows = []
  for (const [name, opt] of VIEWS) {
    const st = await baseState({ layout: '16', ind: { ma: true, ema: true, boll: true, vol: true, subs: ['macd', 'rsi', 'kdj'] } })
    const { ctx, page, errs } = await open(st, opt)
    await waitCells(page, 16); await sleep(1200)
    for (const k of ['16', '12', '9']) {
      if (k !== '16') { await pickLayout(page, k); await waitCells(page, N[k]); await sleep(800) }
      const rd = await page.evaluate(READ), cs = await cellsOf(page), sc = await noScroll(page)
      const c0 = rd[0], d0 = cs[0].deg
      const row = { 视口: name, 布局: k, 格: `${c0.w}×${c0.h}`, 降级: d0 ? `副图≤${d0.subs}·图例${d0.legend ?? (d0.compact ? 'compact' : 'full')}${d0.vol ? '' : '·无量'}·字${d0.font}` : '?', 副图: (cs[0].panes || []).length - 1, 类: c0.cls, 图例高: `${c0.legendH}（${Math.round(c0.legendRatio * 100)}%）`, 图例最小字: c0.minFont, 图例横溢: rd.filter(r => r.legendOver).length, 底栏按钮: c0.footBtns, 底栏裁切: rd.reduce((a, r) => a + r.footClip, 0), 滚动条: sc.ok ? '无' : sc.info }
      rows.push(row)
      // 副图按格子实际像素定（panes.ts：K 线主图留 ≥ 280 才加副图），不按格数：同一布局大屏小屏结果不同
      const fit = h => { const H = h - 28; if (H <= 0) return 0; const m = Math.min(H, Math.max(280, Math.ceil(H * 0.4))); return Math.min(8, Math.max(0, Math.floor((H - m) / 56))) }
      ok('A7', `${name} ${LAB[k]}：副图按格子像素留（K 线 ≥ 280 才加），K 线不被压扁`, cs.every((c, i) => (c.panes || []).length - 1 === Math.min(3, fit(rd[i].h)) && (c.panes?.[0]?.[2] ?? 0) >= Math.min(rd[i].h - 28, 280) - 2), cs.map((c, i) => `${(c.panes || []).length - 1}副/主${c.panes?.[0]?.[2]}`).slice(0, 4).join(' ') + ` …（格 ${rd[0].w}×${rd[0].h}）`)
      // 成交量和副图同一套像素规则（panes.ts volFits）：画布高 ≥ 280 才画，不看宽；同尺寸格子全画或全不画、条高同一公式（主图 × 0.25）
      const volWant = rd.map(r => r.h - 28 >= 280)
      ok('A7', `${name} ${LAB[k]}：成交量按格子高统一定（画布 ≥ 280 才画），同尺寸格子一致`, cs.every((c, i) => !!c.deg?.vol === volWant[i]) && new Set(cs.map(c => `${c.deg?.vol}/${Math.round(c.panes?.[0]?.[2] ?? 0)}`)).size === 1, `${cs[0].deg?.vol ? '画' : '不画'}，主图 ${[...new Set(cs.map(c => Math.round(c.panes?.[0]?.[2] ?? 0)))].join('/')}（格 ${rd[0].w}×${rd[0].h}）`)
      ok('A8', `${name} ${LAB[k]}：无滚动条、底栏不裁切、图例不横溢`, sc.ok && !row.底栏裁切 && !row.图例横溢, JSON.stringify(row))
      if (k === '16') {
        await shot(page, `A8-${name.replace(/[ ×%]/g, '_')}-十六图`)
        if (name === '2560×1440') {
          const hr = await hostRects(page)
          await page.mouse.move(hr[0].x + hr[0].w * 0.6, hr[0].y + hr[0].h * 0.5)
          await sleep(200)
          await shot(page, 'A7-十六图-单格放大看字', { x: hr[0].x - 2, y: hr[0].y - 2, width: Math.round(hr[0].w * 2 + 10), height: Math.round(hr[0].h + 40) })
          // A7：字号台阶（HIG：主 16 / 副 12 / 最小 11）
          ok('A7', '十六图图例最小字号 ≥ 11 px', rd.every(r => r.minFont == null || r.minFont >= 11), rd.map(r => r.minFont).join(','))
          ok('A7', '十六图图例最多占画布高 25%（不压 K 线）', rd.every(r => r.legendRatio <= 0.25), rd.map(r => r.legendRatio).join(','))
          const deg = cs[0].deg, mainH = cs[0].panes?.[0]?.[2] ?? 0
          // 2026-10-10（UI 审查 A3）：2560×1440 的十六图格子放不下副图，只画主图 + 成交量，K 线从 ≈120 回到 ≈300 高
          ok('A7', '2560×1440 十六图（用户开着三副图）只画主图 + 成交量，K 线不再被压扁', cs.every(c => (c.panes || []).length === 1) && mainH >= 250, `画了 ${(cs[0].panes || []).map(p => p[0]).join(',')}，主图 ${mainH} 高（格子 ${c0.w}×${c0.h}，降级档 ${JSON.stringify(deg)}）`)
        }
      }
    }
    // 切回四图：用户的三副图原样回来
    if (name === '2560×1440') {
      await pickLayout(page, '4'); await waitCells(page, 4); await sleep(1000)
      const c4 = await cellsOf(page)
      ok('A7', '从九图切回四图（格子变高）：用户的副图（MACD / RSI / KDJ）原样画回来', c4.every(c => (c.panes || []).length - 1 === Math.min(3, c.deg?.subs ?? 3)) && (c4[0].panes || []).length > 1, c4.map(c => (c.panes || []).map(p => p[0]).join(',')).join(' | '))
    }
    if (errs.length) ok('A8', `${name}：控制台无报错`, false, errs.slice(0, 3).join(' | '))
    await ctx.close()
  }
  DATA.a8 = rows
}

// ═════════════════ A9 两格同品种的画线共享、切布局后位置、撤销作用在哪格
const CANVAS_SIG = () => window.__sig = (i) => {
  const cv = document.querySelectorAll('.chart-cell canvas')[i]; const g = cv.getContext('2d')
  const w = Math.floor(cv.width * 0.5), h = cv.height, d = g.getImageData(0, 0, w, h).data
  let blue = 0
  for (let k = 0; k < d.length; k += 4) if (d[k] < 90 && d[k + 1] > 70 && d[k + 1] < 130 && d[k + 2] > 220) blue++
  return blue
}
async function a9() {
  const st = await baseState({ layout: '2', cells: [{ symbol: 'BTCUSDT', iv: '1h' }, { symbol: 'BTCUSDT', iv: '4h' }, { symbol: 'ETHUSDT', iv: '1h' }].concat((await heavyPc(30)).cells.slice(3)), drawColor: '#2962FF', ind: { ma: false, ema: false, boll: false, vol: true, subs: [] } })
  const { ctx, page, errs } = await open(st)
  await page.addInitScript(CANVAS_SIG); await page.evaluate(CANVAS_SIG)
  await waitCells(page, 2); await sleep(1000); await away(page); await sleep(200)
  const b0 = [await page.evaluate(() => window.__sig(0)), await page.evaluate(() => window.__sig(1))]
  const hr = await hostRects(page)
  await clickCell(page, 0); await page.keyboard.press('Alt+KeyH'); await sleep(200)
  await page.mouse.click(hr[0].x + hr[0].w * 0.3, hr[0].y + hr[0].h * 0.35); await sleep(300)
  await page.keyboard.press('Escape'); await away(page); await sleep(300)
  const n1 = ((await stateOf(page)).drawings?.BTCUSDT || []).length
  const b1 = [await page.evaluate(() => window.__sig(0)), await page.evaluate(() => window.__sig(1))]
  ok('A9', '第 1 格（BTC 1h）画水平线：第 2 格（BTC 4h）同时看得到', n1 === 1 && b1[0] > b0[0] + 100 && b1[1] > b0[1] + 100, `存档 ${n1} 条；蓝色像素 第1格 ${b0[0]}→${b1[0]}、第2格 ${b0[1]}→${b1[1]}`)
  await shot(page, 'A9-两格同品种共享画线')
  await pickLayout(page, '4'); await waitCells(page, 4); await sleep(600); await pickLayout(page, '2'); await waitCells(page, 2); await sleep(800); await away(page); await sleep(200)
  const b2 = [await page.evaluate(() => window.__sig(0)), await page.evaluate(() => window.__sig(1))]
  ok('A9', '2→4→2 之后两格的画线还在', b2[0] > b0[0] + 100 && b2[1] > b0[1] + 100, `蓝色像素 ${b2.join('/')}`)
  // 在第 2 格画（非当前格）：落在哪格、当前格跟过去
  const hr2 = await hostRects(page)
  await page.keyboard.press('Alt+KeyH'); await sleep(150)
  await page.mouse.click(hr2[1].x + hr2[1].w * 0.3, hr2[1].y + hr2[1].h * 0.6); await sleep(300); await page.keyboard.press('Escape')
  const act = await activeIdx(page), n2 = ((await stateOf(page)).drawings?.BTCUSDT || []).length
  ok('A9', '工具选好后在第 2 格画：画进去、第 2 格成为当前格', n2 === 2 && act === 1, `BTC 画线 ${n2} 条、当前格 ${act}`)
  // 撤销作用对象：换到 左一右二，第 3 格是 ETH，设成当前格后 ⌘Z
  await pickLayout(page, '3'); await waitCells(page, 3); await sleep(600)
  await clickCell(page, 2); await sleep(200)
  await page.keyboard.press('Meta+z'); await sleep(400)
  const n3 = ((await stateOf(page)).drawings?.BTCUSDT || []).length
  const toast = await page.evaluate(() => document.querySelector('.toast')?.textContent?.trim() || '')
  note('A9', '当前格是 ETH 时按 ⌘Z：撤的是别格（BTC）的最后一条画线', `BTC 画线 ${n2}→${n3}；提示「${toast}」`)
  ok('A9', '画线段：控制台无报错', !errs.length, errs.slice(0, 3).join(' | '))
  await ctx.close()
}

// ═════════════════ P0 自选 300 + 十六格：网关按同一 IP 160 路拒掉后开的连接，图上 16 格照常跟推送（2026-10-07 P0-1）
//   修前：16→1→16 之后第 3 条连接（装着新格子的 K 线）被拒，整页判断线（state closed），16 格 30 秒内最新价一格都没动
async function p0() {
  const st = await heavyPc(300)          // 十六图、自选面板开着 300 只、网关线路
  const { ctx, page, errs, count } = await open(st, PC, { delay: 30, local: true, depth: 80000 })
  ok('P0', '自选 300 + 十六格：16 格都出 K 线', await waitCells(page, 16, 60000))
  await sleep(8000)
  const s0 = await page.evaluate(() => window.__stream())
  ok('P0', '首屏 8 秒：连接点不判断线', s0.state !== 'closed', `state ${s0.state}、连接 ${s0.conns.join('+')}、总上限 ${s0.cap}`)
  const k0 = count.n
  await pickLayout(page, '1'); await sleep(1500)
  await pickLayout(page, '16'); await waitCells(page, 16, 30000); await sleep(6000)
  const s1 = await page.evaluate(() => window.__stream()), sv = await streamsVsCells(page)
  ok('P0', '16→1→16：连接点不判断线、16 路 K 线流都订着', s1.state !== 'closed' && sv.have === 16 && !sv.missing.length,
    `state ${s1.state}、K 线流 ${sv.have}/${sv.want}、连接 ${s1.conns.join('+')}、总上限 ${s1.cap}${sv.missing.length ? `、缺 ${sv.missing.slice(0, 3).join(',')}` : ''}`)
  // 60 秒里每 2 秒看一次：各格最新价变没变过、连接点有没有判过断线
  const l0 = (await cellsOf(page)).map(c => c.last), moved = l0.map(() => false), states = new Set()
  for (let t = 0; t < 60000; t += 2000) {
    await sleep(2000)
    const cs = await cellsOf(page)
    cs.forEach((c, i) => { if (c.last !== l0[i]) moved[i] = true })
    states.add((await page.evaluate(() => window.__stream())).state)
    if (moved.every(Boolean) && t >= 10000) break
  }
  const cs = await cellsOf(page)
  ok('P0', '60 秒内 16 格最新价都变过（都在跟推送）', moved.every(Boolean), `${moved.filter(Boolean).length}/16${moved.every(Boolean) ? '' : `；没动：${cs.filter((_, i) => !moved[i]).map(c => c.symbol).join(',')}`}`)
  ok('P0', '采样期间连接点没判过断线', !states.has('closed'), [...states].join('/'))
  note('P0', '16→1→16 打出的 K 线请求', `${count.n - k0} 次（切回来的 15 格走会话缓存）`)
  await shot(page, 'P0-修后')
  ok('P0', 'P0 段：控制台无报错', !errs.length, errs.slice(0, 3).join(' | '))
  await ctx.close()
}

// ═════════════════ B10 1↔16 ×20
let B10_T0 = 0
async function b10() {
  const st = await baseState({ layout: '1' })
  B10_T0 = Date.now()
  const { ctx, page, cdp, count, errs } = await open(st, PC, { delay: 120, local: true, depth: 6000 })
  await page.addInitScript(TRANS); await page.evaluate(TRANS)
  await waitCells(page, 1); await sleep(1500)
  const rows = []
  const m0 = await metrics(cdp, page)
  for (let i = 0; i < 20; i++) {
    const k0 = count.n, t0 = Date.now()
    await page.evaluate(() => window.__transStart(16, 1))
    await pickLayout(page, '16')
    const tr = await Promise.race([page.evaluate(() => window.__transRes), sleep(15000).then(() => ({ ms: -1, timeout: true }))])
    const cs = await cellsOf(page)
    const limited = await page.evaluate(() => [...document.querySelectorAll('.chart-cell .cell-empty:not([hidden])')].map(e => e.textContent.trim().slice(0, 30)))
    await sleep(500)
    const sv16 = await streamsVsCells(page)
    await pickLayout(page, '1'); await sleep(700)
    const sv1 = await streamsVsCells(page)
    const f = await page.evaluate(() => ({ live: window.__f.ws.live.size, subs: window.__f.ws.subs, unsubs: window.__f.ws.unsubs }))
    rows.push({ 轮: i + 1, 齐用时ms: tr.timeout ? `>${Date.now() - t0}` : tr.ms, 空格: cs.filter(c => !c.bars).length, 空格提示: limited[0] || '', K线请求: count.n - k0, 十六图K线流: `${sv16.have}/${sv16.want}`, 一图K线流: `${sv1.have}/${sv1.want}`, 多余流: sv1.extra.length + sv16.extra.length, 订阅总数16: sv16.total, 订阅总数1: sv1.total, 连接: sv16.conns.join('+'), WS活: f.live, 本机字节: await lsBytes(page) })
    console.log('  ', JSON.stringify(rows[rows.length - 1]))
  }
  const m1 = await metrics(cdp, page)
  DATA.b10 = { rows, heap: [m0.heap, m1.heap], nodes: [m0.nodes, m1.nodes], listeners: [m0.listeners, m1.listeners], iv: [m0.iv, m1.iv], to: [m0.to, m1.to], ws: [m0.ws.live, m1.ws.live] }
  const slow = rows.filter(r => typeof r.齐用时ms !== 'number' || r.齐用时ms > 3000)
  ok('B10', '1↔16 ×20：每轮 16 格都在 3 秒内出 K 线', !slow.length, `超时 / 慢的轮：${slow.map(r => `#${r.轮} ${r.齐用时ms}ms 空 ${r.空格}（${r.空格提示}）`).join('；') || '无'}`)
  ok('B10', '1↔16 ×20：K 线订阅流始终 = 格子数、没有多余流', rows.every(r => r.多余流 === 0 && r.十六图K线流 === '16/16' && r.一图K线流 === '1/1'), rows.map(r => `${r.十六图K线流}|${r.一图K线流}`).slice(-3).join(' '))
  const ls = rows.map(r => r.本机字节)
  ok('B10', '1↔16 ×20：本机存档大小不涨', ls[ls.length - 1] - ls[0] < 2048, `${ls[0]} → ${ls[ls.length - 1]} 字节`)
  const kr = rows.map(r => r.K线请求), krSum = kr.reduce((a, b) => a + b, 0)
  // 会话 K 线缓存（rest.ts）：只有第一次 1→16 的 15 格去取（非当前格 499 根、权重 2）；之后切回来直接出图，
  // 收过线才补尾巴——跑的这段时间跨过整点（格子是 1h）时每跨一次多 15 次尾巴请求，按跨过的次数放宽
  const hours = Math.floor(Date.now() / 36e5) - Math.floor(B10_T0 / 36e5)
  const allow = 16 + 4 + hours * 15
  ok('B10', `1↔16 ×20：K 线请求合计 ≤ 16 + 几次（会话缓存命中，不再每轮重取 15 格）`, krSum <= allow, `${kr.join(',')}；合计 ${krSum} 次（上限 ${allow}${hours ? `，期间跨过 ${hours} 个整点` : ''}）`)
  const blank = rows.filter(r => r.空格 > 0)
  ok('B10', '1↔16 ×20：没有哪一格空白超过 3 秒', !slow.length && !blank.length, blank.map(r => `#${r.轮} 空 ${r.空格}（${r.空格提示}）`).join('；') || '无')
  ok('B10', '1↔16 ×20：堆、节点、定时器不涨', m1.heap - m0.heap < 3 && m1.iv === m0.iv && Math.abs(m1.nodes - m0.nodes) < 200, `堆 ${m0.heap}→${m1.heap} MB、节点 ${m0.nodes}→${m1.nodes}、监听 ${m0.listeners}→${m1.listeners}、interval ${m0.iv}→${m1.iv}、timeout ${m0.to}→${m1.to}、WS 活 ${m0.ws.live}→${m1.ws.live}`)
  ok('B10', '1↔16 段：控制台无报错', !errs.length, errs.slice(0, 3).join(' | '))
  await ctx.close()
}

// ═════════════════ B11 十六格换品种 ×50 ×2 段（第二段验缓存满后不再涨）
async function b11() {
  const hp = await heavyPc(80)
  const others = hp.watch.crypto.filter(s => !hp.cells.some(c => c.symbol === s))
  const list = hp.cells.flatMap((c, i) => [c.symbol, ...others.slice(i * 3, i * 3 + 3)])
  const st = await baseState({ layout: '16', watch: { ...hp.watch, crypto: list } })
  const { ctx, page, cdp, count, errs } = await open(st, PC, { delay: 120, local: true, depth: 6000 })
  await waitCells(page, 16); await sleep(2000)
  const m0 = await metrics(cdp, page), k0 = count.n
  const hr = await hostRects(page)
  const f0 = await page.evaluate(() => ({ subs: window.__f.ws.subs, unsubs: window.__f.ws.unsubs }))
  // 换品种 50 次一段，共两段（同一批品种继续往下循环）。rest.ts 有 K 线会话 LRU 缓存（KLINE_CACHE_MAX = 32 份「品种|周期」），
  // 第一段会把缓存填满——那是设计内的有界内存；第二段缓存已满、只替换不增长，堆再涨才算泄漏
  const swap = async from => {
    for (let i = from; i < from + 50; i++) {
      const c = (i * 7) % 16, p = center(hr[c])
      await page.mouse.click(p.x, p.y); await page.keyboard.press('ArrowDown'); await sleep(350)
    }
    // 不能只等「每格有 K 线」：被限流闸排队的格子还挂着上一只的图（bars > 0、角上写「排队取数…」）。
    // 等到每格图上品种 = 配置为止；连换 100 次超过前端自己的权重预算（fapi 1200 / 分钟）时闸会让后面的排一会儿，最多等 90 秒
    const t0 = Date.now()
    const ok16 = await page.waitForFunction(() => { const c = window.__cells?.(); return c && c.length === 16 && c.every(x => x.bars > 0 && x.metaSym === x.symbol) }, null, { timeout: 90000, polling: 200 }).then(() => true, () => false)
    const ms = Date.now() - t0
    await sleep(1500)
    return { ok16, ms }
  }
  const s1 = await swap(0)
  const mMid = await metrics(cdp, page)
  const s2 = await swap(50)
  const done = s1.ok16 && s2.ok16
  const sv = await streamsVsCells(page), m1 = await metrics(cdp, page)
  const f1 = await page.evaluate(() => ({ subs: window.__f.ws.subs, unsubs: window.__f.ws.unsubs }))
  const cs = await cellsOf(page)
  const mism = cs.filter(c => !same(c)).length
  const mismInfo = cs.filter(c => !same(c)).slice(0, 4).map(c => `${c.symbol}/${c.iv}≠${c.metaSym}/${c.metaIv}`).join(',')
  DATA.b11 = { K线请求: count.n - k0, 等齐ms: [s1.ms, s2.ms], 订阅: f1.subs - f0.subs, 退订: f1.unsubs - f0.unsubs, sv, heap: [m0.heap, mMid.heap, m1.heap], nodes: [m0.nodes, mMid.nodes, m1.nodes], iv: [m0.iv, mMid.iv, m1.iv] }
  console.log('  ', JSON.stringify(DATA.b11))
  ok('B11', '十六格换品种 ×50 ×2 段后：每格都出图、图上品种与配置一致', done && !mism, `齐 ${done}、不一致 ${mism}${mism ? `（${mismInfo}）` : ''}`)
  ok('B11', '十六格换品种 ×50 ×2 段后：旧品种的 K 线流都退订了', !sv.extra.length && !sv.missing.length, `K 线流 ${sv.have}/${sv.want}，多余 ${sv.extra.slice(0, 4).join(',')}，缺 ${sv.missing.slice(0, 4).join(',')}；累计订 ${f1.subs - f0.subs} 退 ${f1.unsubs - f0.unsubs}`)
  note('B11', '换 100 次品种的 K 线请求', `${count.n - k0} 次`)
  note('B11', '每段换完到 16 格都换上新品种的等待（含限流闸排队）', `第一段 ${s1.ms} ms、第二段 ${s2.ms} ms`)
  note('B11', '第一段 ×50 堆增量（填满 32 份 K 线会话缓存，设计内有界内存）', `堆 ${m0.heap}→${mMid.heap} MB（+${(mMid.heap - m0.heap).toFixed(2)}）`)
  ok('B11', '十六格换品种第二段 ×50（缓存已满）：堆不再涨过 3 MB', m1.heap - mMid.heap < 3, `堆 ${m0.heap}→${mMid.heap}→${m1.heap} MB（第二段 +${(m1.heap - mMid.heap).toFixed(2)}）`)
  ok('B11', '十六格换品种 ×100：节点、interval 不涨', Math.abs(m1.nodes - m0.nodes) < 200 && m1.iv <= m0.iv, `节点 ${m0.nodes}→${mMid.nodes}→${m1.nodes}、interval ${m0.iv}→${mMid.iv}→${m1.iv}`)
  ok('B11', '换品种段：控制台无报错', !errs.length, errs.slice(0, 3).join(' | '))
  await ctx.close()
}

// ═════════════════ B12 刷新恢复十六格：首屏、逐格 K 线到达、是否串行
const ARRIVE = () => {
  window.__arrive = []
  const go = () => {
    const cs = window.__cells?.()
    if (cs && cs.length) cs.forEach((c, i) => { if (c.bars > 0 && window.__arrive[i] == null) window.__arrive[i] = Math.round(performance.now()) })
    if (!(cs && cs.length === 16 && window.__arrive.filter(x => x != null).length === 16) && performance.now() < 60000) requestAnimationFrame(go)
  }
  requestAnimationFrame(go)
}
async function b12() {
  const hp = await heavyPc(300)
  const st = { ...hp, orderFlow: false }
  const runs = []
  for (const [tag, mock] of [['延迟 120 ms', { delay: 120, local: true, depth: 6000 }], ['延迟 400 ms（慢网）', { delay: 400, local: true, depth: 6000 }]]) {
    const { ctx, page, kl, errs } = await open(st, PC, mock)
    await page.addInitScript(ARRIVE)
    await waitCells(page, 16, 60000)
    for (let r = 0; r < 2; r++) {
      kl.length = 0
      const tNav = Date.now()
      await page.reload({ waitUntil: 'domcontentloaded' })
      await waitCells(page, 16, 60000); await sleep(1500)
      const a = await page.evaluate(() => window.__arrive.slice())
      const fcp = await page.evaluate(() => performance.getEntriesByType('paint').find(x => x.name === 'first-contentful-paint')?.startTime)
      // 当前格取 1500 根、其他格取 SIDE_LIMIT = 499 根（rest.ts）；带 endTime 的是补历史，不算
      const ks = kl.filter(x => /limit=(1500|499)\b/.test(x.u) && !/endTime/.test(x.u))
      // 最大并发：K 线请求在飞的最多条数
      const ev = ks.flatMap(x => [[x.t0 - tNav, 1], [(x.t1 || x.t0) - tNav, -1]]).sort((p, q) => p[0] - q[0] || p[1] - q[1])
      let cur = 0, mx = 0; for (const [, d] of ev) { cur += d; mx = Math.max(mx, cur) }
      const starts = ks.map(x => x.t0 - tNav).sort((p, q) => p - q)
      runs.push({ 场景: tag, 轮: r + 1, FCP: Math.round(fcp), 首格K线: Math.min(...a), 末格K线: Math.max(...a), 中位格: med(a), K线请求: ks.length, 最大并发: mx, 发起跨度ms: starts.length ? starts[starts.length - 1] - starts[0] : 0, 逐格到达: a.join(',') })
      console.log('  ', JSON.stringify(runs[runs.length - 1]))
    }
    await shot(page, `B12-刷新后十六图-${tag.split(' ')[0]}`)
    if (errs.length) ok('B12', `${tag}：控制台无报错`, false, errs.slice(0, 3).join(' | '))
    await ctx.close()
  }
  DATA.b12 = runs
  const r0 = runs.filter(r => r.场景.startsWith('延迟 120'))
  ok('B12', '刷新恢复十六图（120 ms）：16 格 K 线 ≤ 2 秒内到齐（F 线冷启动基线 1568 ms）', med(r0.map(r => r.末格K线)) <= 2000, r0.map(r => `末格 ${r.末格K线} ms、并发 ${r.最大并发}`).join('；'))
  ok('B12', '刷新恢复十六图：K 线请求并行发出（16 个、并发 ≥ 8、发起跨度 ≤ 50 ms，不是一格等一格）', runs.every(r => r.K线请求 >= 16 && r.最大并发 >= 8 && r.发起跨度ms <= 50), runs.map(r => `${r.场景}#${r.轮} 请求 ${r.K线请求} 并发 ${r.最大并发} 跨度 ${r.发起跨度ms}ms`).join('；'))
}

// ═════════════════ C13 性能：对照 F 线 big；C15 挂机 3 分钟
const BASE = { '常态 10 秒': [112, 166, 0], '联动十字线 600 下': [569, 862, 52], '第一格滚轮 300 下': [661, 970, 0], '第一格拖动 3 秒': [213, 331, 0] }
async function c13(idleMin = 3) {
  const hp = await heavyPc()
  hp.orderFlow = true
  const { ctx, page, cdp, errs } = await open(hp, PC, { delay: 30, local: true, depth: 80000 })
  await waitCells(page, 16, 60000)
  await sleep(8000)
  const out = []
  const rect = (await hostRects(page))[0]
  const grid = await page.evaluate(() => { const cs = [...document.querySelectorAll('.chart-cell')].map(e => e.getBoundingClientRect()); const x = Math.min(...cs.map(r => r.x)), y = Math.min(...cs.map(r => r.y)); return { x, y, w: Math.max(...cs.map(r => r.right)) - x, h: Math.max(...cs.map(r => r.bottom)) - y } })
  const row = async (name, fn) => { const r = await measure(page, cdp, fn); const o = { 段: name, ...r }; console.log('  ', JSON.stringify(o)); out.push(o); return o }
  const deg = (await cellsOf(page))[0]
  note('C13', '十六图实测格子与副图', `格子画布 ${Math.round(rect.w)}×${Math.round(rect.h)}，降级 ${JSON.stringify(deg.deg)}，画了 ${deg.panes.map(p => p[0]).join(',')}`)
  await row('常态 10 秒', () => sleep(10000))
  await row('联动十字线 600 下', async () => { for (let i = 0; i < 600; i++) { const t = i / 600; await page.mouse.move(grid.x + 20 + (grid.w - 40) * ((t * 4) % 1), grid.y + 20 + (grid.h - 40) * t); await sleep(4) } })
  const cx = rect.x + rect.w * 0.5, cy = rect.y + rect.h * 0.3
  await page.mouse.move(cx, cy)
  await row('第一格滚轮 300 下', async () => { for (let i = 0; i < 300; i++) { await page.mouse.wheel(0, i % 60 < 30 ? 40 : -40); await sleep(4) } })
  await row('第一格拖动 3 秒', async () => { await page.mouse.down(); for (let i = 0; i < 180; i++) { await page.mouse.move(cx + Math.sin(i / 20) * 200, cy); await sleep(8) } await page.mouse.up() })
  // 附加：开着时间轴联动拖第一格（十六格一起平移）
  await menuToggle(page, '时间轴跨图同步'); await sleep(400)
  await page.mouse.move(cx, cy)
  await row('附加：时间轴联动下拖第一格 3 秒', async () => { await page.mouse.down(); for (let i = 0; i < 180; i++) { await page.mouse.move(cx + Math.sin(i / 20) * 200, cy); await sleep(8) } await page.mouse.up() })
  await row('附加：时间轴联动下滚轮 300 下', async () => { for (let i = 0; i < 300; i++) { await page.mouse.wheel(0, i % 60 < 30 ? 40 : -40); await sleep(4) } })
  await menuToggle(page, '时间轴跨图同步'); await sleep(400)
  // 附加：十六格逐格点选（300 只自选的侧栏会跟着重画）
  const hr = await hostRects(page)
  await row('附加：十六格逐格点选 16 次（300 只自选）', async () => { for (let i = 0; i < 16; i++) { const p = center(hr[(i + 1) % 16]); await page.mouse.click(p.x, p.y); await sleep(150) } })
  // 附加：16→1→16 一次的主线程
  await row('附加：十六图→一图→十六图 一次', async () => { await pickLayout(page, '1'); await sleep(800); await pickLayout(page, '16'); await waitCells(page, 16, 30000); await sleep(500) })
  DATA.c13 = out
  for (const o of out) {
    const b = BASE[o.段]
    if (b) ok('C13', `${o.段}：布局 / 重算不比 F 线 big 基线多 20% 以上，最长任务 ≤ 100 ms`, o.layouts <= b[0] * 1.2 + 10 && o.recalcs <= b[1] * 1.2 + 10 && o.ltMax <= 100, `布局 ${o.layouts}（基线 ${b[0]}）、重算 ${o.recalcs}（${b[1]}）、最长 ${o.ltMax} ms（${b[2]}）、p50 ${o.p50} / p95 ${o.p95} ms、掉帧 ${o.dropped}/${o.frames}、CPU ${o.cpu}%、负载 ${o.机器负载}`)
    else note('C13', o.段, `布局 ${o.layouts}、重算 ${o.recalcs}、最长 ${o.ltMax} ms、p50 ${o.p50} / p95 ${o.p95} ms、掉帧 ${o.dropped}/${o.frames}、CPU ${o.cpu}%、负载 ${o.机器负载}`)
  }
  const idle = out.find(o => o.段 === '常态 10 秒')
  if (idle) ok('C13', '常态 10 秒：布局次数低于 F 线 big 基线 112（时钟只写当前格、只在变了时写）', idle.layouts < BASE['常态 10 秒'][0], `布局 ${idle.layouts}、重算 ${idle.recalcs}`)
  // ── C15 挂机：鼠标移出图表，什么都不动
  if (idleMin > 0) {
    await away(page); await sleep(2000)
    const r0 = await page.evaluate(() => window.__redraw()), f0 = await metrics(cdp, page, false), raf0 = f0.raf
    const last0 = (await cellsOf(page)).map(c => c.lastT + ':' + c.last)
    const ms = await measure(page, cdp, () => sleep(idleMin * 60000))
    const r1 = await page.evaluate(() => window.__redraw()), f1 = await metrics(cdp, page, false)
    const per = r1.per.map((v, i) => v - (r0.per[i] || 0))
    const last1 = (await cellsOf(page)).map(c => c.lastT + ':' + c.last), sv = await streamsVsCells(page)
    const moved = last1.filter((v, i) => v !== last0[i]).length
    ok('C15', `挂机 ${idleMin} 分钟：16 格的最新一根都在跟推送走`, moved >= 15, `${moved}/16 格的最新价变过；K 线流 ${sv.have}/${sv.want}、订阅总数 ${sv.total}、连接 ${JSON.stringify(sv.conns)}`)
    const secs = idleMin * 60
    DATA.c15 = { ...ms, 秒: secs, 重画总: r1.all - r0.all, 每格重画: per, raf: f1.raf - raf0, interval: f1.iv, ivBy: f1.ivBy, timeout: f1.to, toBy: f1.toBy, msgs: f1.ws.msgs - f0.ws.msgs, WS活: f1.ws.live, 写盘次: f1.ls.n - f0.ls.n, 写盘KB: Math.round((f1.ls.bytes - f0.ls.bytes) / 1024), 写盘按键: Object.fromEntries(Object.entries(f1.ls.byKey).map(([k, v]) => [k, v.n - (f0.ls.byKey[k]?.n || 0)]).filter(([, n]) => n)) }
    console.log('  ', JSON.stringify(DATA.c15))
    ok('C15', `挂机 ${idleMin} 分钟（十六图 + 订单流 + 300 只自选）：主线程占用 ≤ 15%`, ms.cpu <= 15, `CPU ${ms.cpu}%、脚本 ${ms.script}%、布局 ${ms.layouts}（${(ms.layouts / secs).toFixed(1)}/s）、重算 ${ms.recalcs}、长任务 ${ms.lt}（最长 ${ms.ltMax} ms）、负载 ${ms.机器负载}`)
    ok('C15', '挂机：interval 数量稳定（≤ 8）', f1.iv <= 8, `${f1.iv} 个：${JSON.stringify(f1.ivBy)}`)
    note('C15', '挂机：画布重画', `${r1.all - r0.all} 次（${((r1.all - r0.all) / secs).toFixed(1)}/s），每格 ${per.join(',')}；rAF 回调 ${f1.raf - raf0}（${((f1.raf - raf0) / secs).toFixed(1)}/s）；推送 ${f1.ws.msgs - f0.ws.msgs} 条；写盘 ${f1.ls.n - f0.ls.n} 次 ${Math.round((f1.ls.bytes - f0.ls.bytes) / 1024)} KB ${JSON.stringify(DATA.c15.写盘按键)}`)
  }
  ok('C13', '性能段：控制台无报错', !errs.length, errs.slice(0, 3).join(' | '))
  await ctx.close()
}

// ═════════════════ C14 长会话内存：布局 ×50、换品种 ×100，强制 GC
async function c14() {
  const st = await baseState({ layout: '16', drawings: (await heavyPc(30)).drawings, ind: { ma: true, ema: true, boll: true, vol: true, subs: ['macd', 'rsi', 'kdj'] } })
  const { ctx, page, cdp, count, errs } = await open(st, PC, { delay: 30, local: true, depth: 6000 })
  await waitCells(page, 16, 60000); await sleep(3000)
  const pts = []
  const snap = async tag => { const m = await metrics(cdp, page); const p = { 点: tag, 堆MB: m.heap, 节点: m.nodes, 监听: m.listeners, interval: m.iv, timeout: m.to, WS活: m.ws.live, K线请求: count.n, 本机KB: Math.round(await lsBytes(page) / 1024) }; pts.push(p); console.log('  ', JSON.stringify(p)); return p }
  await snap('起点')
  const order = LAYS.map(l => l[0])
  for (let i = 1; i <= 50; i++) {
    const k = order[i % order.length]
    await pickLayout(page, k)
    await waitCells(page, N[k], 8000)
    await sleep(150)
    if (i % 10 === 0) await snap(`布局 ×${i}`)
  }
  await pickLayout(page, '16'); await waitCells(page, 16, 60000); await sleep(1000)
  await snap('回十六图')
  const hr = await hostRects(page)
  for (let i = 1; i <= 100; i++) {
    const p = center(hr[(i * 5) % 16]); await page.mouse.click(p.x, p.y); await page.keyboard.press('ArrowDown'); await sleep(250)
    if (i % 25 === 0) { await waitCells(page, 16, 60000); await snap(`换品种 ×${i}`) }
  }
  await sleep(3000); await snap('终点')
  DATA.c14 = pts
  const lay = pts.filter(p => /布局/.test(p.点)).map(p => p.堆MB), sym = pts.filter(p => /换品种/.test(p.点)).map(p => p.堆MB)
  ok('C14', '布局 ×50：堆不单调上涨（末点 − 第一个检查点 < 3 MB）', lay[lay.length - 1] - lay[0] < 3, lay.join(' → '))
  ok('C14', '换品种 ×100：堆不单调上涨（末点 − 第一个检查点 < 3 MB）', sym[sym.length - 1] - sym[0] < 3, sym.join(' → '))
  ok('C14', '长会话：interval 数不变、WS 不涨', new Set(pts.map(p => p.interval)).size === 1 && Math.max(...pts.map(p => p.WS活)) <= 3, `interval ${[...new Set(pts.map(p => p.interval))].join('/')}，WS ${pts.map(p => p.WS活).join(',')}`)
  ok('C14', '长会话段：控制台无报错', !errs.length, errs.slice(0, 3).join(' | '))
  await ctx.close()
}

// ───────── 主程序
const SEGS = { p0, a1, a2, a4, a5, a6, a7: a7a8, a9, b10, b11, b12, c13, c14 }
const want = process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(SEGS)
const { url, stop } = await preview()
URL_ = url
browser = await launch()
try {
  for (const s of want) {
    const f = SEGS[s === 'a8' ? 'a7' : s === 'c15' ? 'c13' : s]
    if (!f) { console.log('没有这一段', s); continue }
    console.log(`\n══ ${s} ══`)
    try { await f() } catch (e) { ok(s.toUpperCase(), `${s} 段跑崩了`, false, String(e).slice(0, 300)) }
    flush()
  }
} finally {
  await browser.close(); stop()
  flush()
  const bad = R.filter(r => r.pass === false)
  console.log(`\n合计 ✓ ${R.filter(r => r.pass === true).length}  ✗ ${bad.length}  · ${R.filter(r => r.pass === null).length}`)
  bad.forEach(r => console.log(`✗ [${r.id}] ${r.name}  — ${r.info}`))
}
void pct
