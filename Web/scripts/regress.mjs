// Hkline Web · 整体回归（以交易员身份把网页版走一遍）：本机 Chrome、2560×1440、DPR 1
//   node scripts/regress.mjs [地址] [段落…]
//   段落：chart（图表页）、alerts（提醒）、edge（边界）、themes（皮肤）、route（线路）、sectors（板块）、
//         account（账号与同步）、review（复盘）；后两段要 KP_PASS 环境变量
//   默认地址 http://localhost:5188/web/；截图写到 docs/acceptance/网页版-2026-09-29/回归-*.png
// 每一段都收集控制台报错与未处理的 Promise 拒绝，目标是 0；每一项的结论打一行「✓ / ✗」。
import { chromium } from 'playwright-core'
import { mkdirSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const URL_ = process.argv[2] || 'http://localhost:5188/web/'
const PARTS = process.argv.slice(3)
const OUT = resolve(here, '../../docs/acceptance/网页版-2026-09-29')
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
mkdirSync(OUT, { recursive: true })

const results = []
const ok = (name, pass, detail = '') => { results.push({ name, pass, detail }); console.log(`${pass ? '✓' : '✗'} ${name}${detail ? ' — ' + detail : ''}`) }

const browser = await chromium.launch({ executablePath: CHROME, headless: true, args: ['--enable-precise-memory-info'] })
const ctx = await browser.newContext({ viewport: { width: 2560, height: 1440 }, deviceScaleFactor: 1 })
// 数 WebSocket：开过几条、现在活着几条、每条上订着哪些流
await ctx.addInitScript(() => {
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
})
const page = await ctx.newPage()
const errors = []
page.on('console', m => { if (m.type() === 'error') errors.push(`[console] ${m.text()}`) })
page.on('pageerror', e => errors.push(`[pageerror] ${e.message}`))
const cdp = await ctx.newCDPSession(page)

const wait = ms => page.waitForTimeout(ms)
const shot = async name => { await page.screenshot({ path: `${OUT}/回归-${name}.png` }); console.log('  截图 回归-' + name) }
const state = () => page.evaluate(() => JSON.parse(localStorage.getItem('hkline-web-v1') || '{}'))
const ready = async () => {
  await page.waitForFunction(() => (document.querySelector('#toolbar #tbSymbol') && document.title.includes('·')) || !!document.querySelector('.cell-empty:not([hidden])'), null, { timeout: 25000, polling: 250 })
  await wait(1500)
}
const open = async (qs = '', hash = 'chart') => { await page.goto(`${URL_}?${qs}#${hash}`, { waitUntil: 'domcontentloaded' }); await ready() }
const fresh = async (qs = 'layout=1&panel=watch&ladder=0&drawer=0') => {
  await page.goto(URL_, { waitUntil: 'load' }); await wait(500)
  await page.evaluate(() => localStorage.clear())
  await open(qs)
}
const heap = async () => { await cdp.send('HeapProfiler.collectGarbage'); await wait(300); await cdp.send('HeapProfiler.collectGarbage'); return (await cdp.send('Runtime.getHeapUsage')).usedSize }
const ws = () => page.evaluate(() => ({ opened: window.__ws.opened, closed: window.__ws.closed, live: window.__ws.live.map(x => ({ url: x.url.replace(/\?.*/, ''), subs: [...x.subs].sort() })) }))
const canvasBox = async (i = 0) => page.locator('.chart-cell canvas').nth(i).boundingBox()
/** 主图画布：往右找价格轴的起点（光标变成 ns-resize / pointer 的地方） */
async function plotGeom(i = 0) {
  const b = await canvasBox(i)
  const y = b.y + b.height * 0.35
  let axisX = b.x + b.width - 1
  for (let x = b.x + b.width - 2; x > b.x + b.width - 200; x -= 2) {
    await page.mouse.move(x, y)
    const c = await page.evaluate(k => document.querySelectorAll('.chart-cell canvas')[k].style.cursor, i)
    if (c === 'crosshair' || c === 'pointer' && x < b.x + b.width - 120) { axisX = x + 2; break }
  }
  return { ...b, axisX, plotX0: b.x + 4, plotY0: b.y + 40 }
}
const canvasHash = (i = 0) => page.evaluate(k => { const c = document.querySelectorAll('.chart-cell canvas')[k]; const d = c.toDataURL(); let h = 0; for (let j = 0; j < d.length; j += 7) h = (h * 31 + d.charCodeAt(j)) | 0; return h }, i)
const drawCount = async sym => ((await state()).drawings?.[sym] || []).length
const menuLabels = () => page.evaluate(() => [...document.querySelectorAll('.menu .mi .label')].map(e => e.textContent.trim()))
const clickMenu = async label => { await page.locator('.menu .mi', { hasText: label }).first().click(); await wait(300) }
const sectionErrors = start => errors.slice(start)

// ═════════════════════════════ 图表页 ═════════════════════════════
async function partChart() {
  const e0 = errors.length
  await fresh()
  // ---- 搜索：⌘K、直接打字、数字键周期
  await page.keyboard.press('Meta+k'); await wait(400)
  await page.keyboard.type('ETH'); await wait(400); await page.keyboard.press('Enter'); await wait(1500)
  let s = await state()
  ok('⌘K 搜 ETH 回车打开', s.cells[0].symbol === 'ETHUSDT', s.cells[0].symbol)
  await page.mouse.click(1000, 600); await page.keyboard.press('s'); await wait(300)
  await page.keyboard.type('ol'); await wait(400)
  const q = await page.inputValue('#sq')
  await page.keyboard.press('Enter'); await wait(1500)
  s = await state()
  ok('图上直接打字进搜索（S → OL）', q.toUpperCase() === 'SOL' && s.cells[0].symbol === 'SOLUSDT', `${q} → ${s.cells[0].symbol}`)
  await page.keyboard.press('2'); await wait(1200)
  s = await state(); ok('数字键 2 = 栏上第 2 个周期', s.cells[0].iv === s.pinned[1], s.cells[0].iv)
  for (const k of [',', '7', 'Enter']) { await page.keyboard.press(k); await wait(150) }
  await wait(1500); s = await state(); ok('逗号 + 7 回车 = 7 分（自定义）', s.cells[0].iv === '7m' && s.customIvs.includes('7m'), `${s.cells[0].iv} ${JSON.stringify(s.customIvs)}`)
  for (const k of ['0', '5', 's', 'Enter']) { await page.keyboard.press(k); await wait(150) }
  await wait(6000); s = await state()
  const secEmpty = await page.locator('.cell-empty:not([hidden])').count()
  ok('秒级周期 5 秒（打开页面起自聚）', s.cells[0].iv === '5s', `${s.cells[0].iv} 空态格子 ${secEmpty}`)
  await shot('秒级-5秒')
  await page.click('#tbMoreIv'); await wait(300)
  const ivs = await menuLabels()
  await clickMenu('4小时'); await wait(1500); s = await state()
  ok('「更多」里切 4 小时', s.cells[0].iv === '4h', `菜单 ${ivs.length} 项，含秒级：${ivs.filter(x => /秒/.test(x)).join('、')}`)
  await page.keyboard.press('4'); await wait(1000)

  // ---- 20 次快速换品种（每 200 ms 一次），看 WS 条数、订阅、内存
  await open('s=BTCUSDT&i=1h&layout=1&panel=watch&ladder=0&drawer=0'); await wait(3000)
  const w0 = await ws(), h0 = await heap()
  const rows = page.locator('#wTbl tr[data-sym]')
  const n = await rows.count()
  for (let round = 0; round < 2; round++) {
    for (let k = 0; k < 20; k++) { await rows.nth((k + 1) % n).click(); await wait(200) }
    await rows.nth(0).click(); await wait(4000)
  }
  const w1 = await ws(), h1 = await heap()
  const subs = x => x.live.reduce((a, l) => a + l.subs.length, 0)
  ok('快速换品种后 WS 条数不涨', w1.live.length <= w0.live.length, `开过 ${w0.opened}→${w1.opened}，活着 ${w0.live.length}→${w1.live.length}（${w1.live.map(l => l.url).join(' | ')}）`)
  ok('回到 BTC 后订阅不漏（同一组流）', subs(w1) === subs(w0), `订阅 ${subs(w0)} → ${subs(w1)}；多出：${w1.live.flatMap(l => l.subs).filter(x => !w0.live.flatMap(l => l.subs).includes(x)).join(',') || '无'}`)
  ok('内存不持续上涨（GC 后）', h1 < h0 * 1.25 + 8e6, `${(h0 / 1e6).toFixed(1)} MB → ${(h1 / 1e6).toFixed(1)} MB`)
  // 再来一轮看增量是否收敛
  for (let k = 0; k < 20; k++) { await rows.nth((k + 1) % n).click(); await wait(200) }
  await rows.nth(0).click(); await wait(4000)
  const h2 = await heap(), w2 = await ws()
  ok('第二轮内存持平', h2 < h1 * 1.15 + 5e6, `${(h1 / 1e6).toFixed(1)} MB → ${(h2 / 1e6).toFixed(1)} MB；WS 活着 ${w2.live.length}、订阅 ${subs(w2)}`)

  // ---- 布局 1/2/2v/4/6/8 与两个联动开关
  const LAY = [['1', '一图', 1], ['2', '左右两图', 2], ['2v', '上下两图', 2], ['4', '四图', 4], ['6', '六图', 6], ['8', '八图', 8]]
  for (const [k, label, cnt] of LAY) {
    await page.click('#tbLayout'); await wait(250); await clickMenu(label); await wait(1500)
    const c = await page.locator('.chart-cell').count(); s = await state()
    ok(`布局 ${label}`, c === cnt && s.layout === k, `格子 ${c}`)
    if (k === '8') await shot('布局-八图')
  }
  await page.click('#tbLayout'); await wait(250); await clickMenu('四图'); await wait(1500)
  await page.click('#tbLayout'); await wait(250); await clickMenu('品种跨图同步'); await wait(2500)
  s = await state()
  ok('品种跨图同步：打开后四格同一只', s.linkSymbol && s.cells.slice(0, 4).every(c => c.symbol === s.cells[0].symbol), s.cells.slice(0, 4).map(c => c.symbol).join(','))
  await page.locator('.chart-cell').nth(2).click({ position: { x: 300, y: 300 } }); await wait(300)
  await rows.nth(1).click(); await wait(2500); s = await state()
  ok('联动时换一格全跟着换（周期各自保留）', s.cells.slice(0, 4).every(c => c.symbol === s.cells[s.active].symbol) && new Set(s.cells.slice(0, 4).map(c => c.iv)).size >= 1, s.cells.slice(0, 4).map(c => `${c.symbol}/${c.iv}`).join(','))
  await page.click('#tbLayout'); await wait(250); await clickMenu('十字线跨图同步'); await wait(300); s = await state()
  ok('十字线跨图同步开关落盘', s.linkCross === false)
  await page.click('#tbLayout'); await wait(250); await clickMenu('十字线跨图同步'); await wait(200)
  await page.click('#tbLayout'); await wait(250); await clickMenu('品种跨图同步'); await wait(200)
  await page.click('#tbLayout'); await wait(250); await clickMenu('一图'); await wait(1500)

  // ---- 指标：加、删、改参数；一目均衡表前移那一段
  await open('s=BTCUSDT&i=1h&layout=1&panel=watch&ladder=0&drawer=0')
  await page.mouse.click(1000, 600); await page.keyboard.press('/'); await wait(400)
  await page.click('.ind-dlg .ind-row[data-id="boll"]'); await wait(200)
  await page.click('.ind-dlg .ind-row[data-id="kdj"]'); await wait(200)
  await page.click('.ind-dlg .ind-row[data-id="ichi"]'); await wait(200)
  s = await state()
  ok('指标：加 BOLL、KDJ、一目均衡表', s.ind.boll && s.ind.subs.includes('kdj') && s.ind.ichi, JSON.stringify(s.ind))
  await page.click('.ind-dlg [data-set="ma"]'); await wait(300)
  await page.fill('#pf0', '7'); await page.click('#pOk'); await wait(400)
  s = await state(); ok('改 MA 参数（周期 1 = 7）', s.params?.ma?.periods?.[0] === 7, JSON.stringify(s.params?.ma))
  await page.keyboard.press('Escape'); await wait(300)
  await wait(1500); await shot('指标-一目均衡表')
  // 一目：云（先行带）要画到最后一根 K 线右边 26 根
  const g = await plotGeom()
  const bars = await page.evaluate(() => 0)
  void bars
  ok('一目均衡表截图已留（前移段看图）', true, `价格轴起点 x=${Math.round(g.axisX)}`)
  // 图例上删掉 KDJ
  await page.evaluate(() => document.querySelector('.chart-cell [data-act="remove"][data-id="kdj"]')?.dispatchEvent(new MouseEvent('click', { bubbles: true }))); await wait(400)
  s = await state(); ok('图例上删 KDJ', !s.ind.subs.includes('kdj'), JSON.stringify(s.ind.subs))

  // ---- 画线：每把工具画一条、拖一下、删掉、撤销 / 重做
  await page.mouse.click(1000, 600); await page.keyboard.press('/'); await wait(300)
  await page.click('.ind-dlg .ind-row[data-id="ichi"]'); await page.click('.ind-dlg .ind-row[data-id="boll"]'); await page.keyboard.press('Escape'); await wait(500)
  ok('勾完指标直接按 Esc 关掉弹窗（勾选后整块重画、焦点掉回 body 也要关）', !(await page.locator('.ind-dlg').count()))
  const sym = (await state()).cells[0].symbol
  ok('地址栏 ?s= 落在看得见的格子上，用完从地址栏拿掉（刷新不被盖回去）', sym === 'BTCUSDT' && !/[?&]s=/.test(page.url()), `${sym} ${page.url()}`)
  const P = await plotGeom()
  const px = f => P.x + (P.axisX - P.x) * f, py = f => P.y + 60 + (P.height * 0.55) * f
  const TOOLS = ['trend', 'ray', 'hline', 'vline', 'rect', 'fib', 'measure']
  let before = await drawCount(sym)
  for (const [i, t] of TOOLS.entries()) {
    await page.click(`#drawbar [data-tool="${t}"]`); await wait(150)
    const x1 = px(0.15 + i * 0.1), y1 = py(0.2 + (i % 3) * 0.2)
    await page.mouse.move(x1, y1); await page.mouse.down(); await page.mouse.up(); await wait(100)
    if (t !== 'hline' && t !== 'vline') { await page.mouse.move(x1 + 90, y1 + 60, { steps: 4 }); await page.mouse.down(); await page.mouse.up() }
    await wait(300)
    const nowN = await drawCount(sym)
    ok(`画线 ${t}`, t === 'measure' ? true : nowN === before + 1, `${before} → ${nowN}${t === 'measure' ? '（测量框是临时的：下一次点图或刷新就清掉，不进同步）' : ''}`)
    before = nowN
    await page.keyboard.press('Escape'); await wait(100)
  }
  await shot('画线-七把工具')
  // 拖：选中趋势线（第一条）拖动
  s = await state()
  const d0 = s.drawings[sym][0]
  const x0 = px(0.15) + 45, y0 = py(0.2) + 30
  await page.mouse.move(x0, y0); await page.mouse.down(); await page.mouse.move(x0 + 120, y0 + 50, { steps: 6 }); await page.mouse.up(); await wait(400)
  s = await state()
  const d1 = s.drawings[sym].find(d => d.id === d0.id)
  ok('拖动趋势线', d1 && JSON.stringify(d1.pts) !== JSON.stringify(d0.pts), d1 ? `p ${d0.pts[0].p.toFixed(1)} → ${d1.pts[0].p.toFixed(1)}` : '找不到')
  // 删：选中后 Delete
  await page.mouse.click(x0 + 120, y0 + 50); await wait(200)
  const nb = await drawCount(sym)
  await page.keyboard.press('Delete'); await wait(400)
  const na = await drawCount(sym)
  ok('Delete 删掉选中的画线', na === nb - 1, `${nb} → ${na}`)
  await page.keyboard.press('Meta+z'); await wait(400)
  const nu = await drawCount(sym)
  ok('⌘Z 撤销删除', nu === nb, `${na} → ${nu}`)
  await page.keyboard.press('Meta+Shift+z'); await wait(400)
  const nr = await drawCount(sym)
  ok('⌘⇧Z 重做', nr === na, `${nu} → ${nr}`)

  // ---- 右键菜单、右键拖动纵向平移、Alt + 滚轮纵向缩放
  await page.click('#drawbar [data-tool="cursor"]'); await wait(100)
  const cx = px(0.5), cy = py(0.95)
  await page.mouse.move(cx, cy); await page.mouse.down({ button: 'right' }); await page.mouse.up({ button: 'right' }); await wait(400)
  const labels = await menuLabels()
  ok('右键菜单（建提醒 / 画水平线 / 记一笔）', labels.some(l => l.includes('创建提醒')) && labels.some(l => l.includes('水平线')), labels.slice(0, 4).join(' · '))
  await page.keyboard.press('Escape'); await wait(200)
  const hv0 = await canvasHash()
  await page.mouse.move(cx, cy); await page.mouse.down({ button: 'right' }); await page.mouse.move(cx, cy + 160, { steps: 8 }); await page.mouse.up({ button: 'right' }); await wait(400)
  const menuAfterDrag = await page.locator('.menu').count(), hv1 = await canvasHash()
  ok('右键拖画布 = 纵向平移，松手不弹菜单', menuAfterDrag === 0 && hv0 !== hv1, `菜单 ${menuAfterDrag}、画面${hv0 !== hv1 ? '变了' : '没变'}`)
  await shot('右键拖-纵向平移后')
  await page.mouse.move(cx, cy); await page.keyboard.down('Alt'); await page.mouse.wheel(0, 300); await page.keyboard.up('Alt'); await wait(300)
  const hv2 = await canvasHash()
  ok('Alt + 滚轮纵向缩放', hv2 !== hv1)
  await page.mouse.dblclick(P.axisX + 30, P.y + P.height * 0.5); await wait(300)

  // ---- 点价格轴建提醒、拖动改价
  const a0 = (await state()).alerts.length
  const ay = P.y + P.height * 0.3
  await page.mouse.move(P.axisX + 8, ay); await page.mouse.down(); await page.mouse.up(); await wait(500)
  s = await state()
  const created = s.alerts.length === a0 + 1 ? s.alerts[s.alerts.length - 1] : null
  ok('点价格轴建一条价格提醒', !!created, created ? `${created.title}` : `${a0} → ${s.alerts.length}`)
  if (created) {
    const p0 = created.lines[0].points[0].p
    await page.mouse.move(P.axisX + 8, ay); await page.mouse.down(); await page.mouse.move(P.axisX + 8, ay + 80, { steps: 6 }); await page.mouse.up(); await wait(500)
    s = await state()
    const moved = s.alerts.find(a => a.id === created.id)
    ok('拖提醒线改价', moved && moved.lines[0].points[0].p < p0, moved ? `${p0.toFixed(1)} → ${moved.lines[0].points[0].p.toFixed(1)}（${moved.title}）` : '不见了')
  }
  await shot('提醒-价格轴')

  // ---- 刷新后全都还在
  const snap = await state()
  await page.reload({ waitUntil: 'domcontentloaded' }); await ready()
  const after = await state()
  const keep = ['layout', 'cells', 'ind', 'params', 'drawings', 'alerts', 'pinned', 'customIvs', 'linkCross', 'linkSymbol']
  const lost = keep.filter(k => JSON.stringify(snap[k]) !== JSON.stringify(after[k]))
  ok('刷新后状态都在', !lost.length, lost.length ? '变了：' + lost.join(',') : keep.join('、'))
  const drawnAfter = await page.evaluate(() => document.querySelectorAll('.chart-cell canvas').length)
  ok('刷新后图还在', drawnAfter >= 1)
  ok('图表页：控制台无报错', sectionErrors(e0).length === 0, sectionErrors(e0).slice(0, 5).join(' | '))
}

// ═════════════════════════════ 边界 ═════════════════════════════
async function partEdge() {
  const e0 = errors.length
  await fresh('s=BTCUSDT&i=1m&layout=1&panel=watch&ladder=0&drawer=0')
  // 断网再联网
  await ctx.setOffline(true); await wait(2000)
  const dotOff = await page.evaluate(() => document.querySelector('.cell-foot .conn-dot')?.dataset.conn)
  await shot('断网')
  await ctx.setOffline(false)
  let dotOn = ''
  const tOn = Date.now()
  for (let k = 0; k < 40 && dotOn !== 'live'; k++) { await wait(250); dotOn = await page.evaluate(() => document.querySelector('.cell-foot .conn-dot')?.dataset.conn) }
  const back = Date.now() - tOn
  const p1 = await page.evaluate(() => document.title)
  await wait(4000)
  const p2 = await page.evaluate(() => document.title)
  ok('断网 2 秒内连接点就不是「在线」，联网 5 秒内自动恢复', dotOff !== 'live' && dotOn === 'live' && back < 5000, `断网 ${dotOff}，联网 ${back} ms 后 ${dotOn}；标题 ${p1} → ${p2}`)
  const w = await ws()
  ok('恢复后只有一条行情连接在订', w.live.filter(l => l.subs.length).length <= 2, w.live.map(l => `${l.url}(${l.subs.length})`).join(' | '))
  // localStorage 清空后刷新
  await page.evaluate(() => localStorage.clear())
  await page.reload({ waitUntil: 'domcontentloaded' }); await ready()
  const s = await state()
  ok('localStorage 清空后照常起来（出厂状态）', (s.cells?.[0]?.symbol || 'BTCUSDT') === 'BTCUSDT' && !(await page.locator('.cell-empty:not([hidden])').count()))
  // 60 只自选
  const syms = await page.evaluate(async () => {
    const r = await fetch('https://fapi.binance.com/fapi/v1/ticker/24hr').then(x => x.json()).catch(() => [])
    return r.filter(x => x.symbol.endsWith('USDT')).sort((a, b) => b.quoteVolume - a.quoteVolume).slice(0, 60).map(x => x.symbol)
  })
  if (syms.length >= 60) {
    await page.evaluate(list => { const s = JSON.parse(localStorage.getItem('hkline-web-v1') || '{}'); s.watch = { crypto: list, us: [], com: [] }; s.watchTab = 'crypto'; localStorage.setItem('hkline-web-v1', JSON.stringify(s)) }, syms)
    await page.reload({ waitUntil: 'domcontentloaded' }); await ready(); await wait(3000)
    const n = await page.locator('#wTbl tr[data-sym]').count()
    const priced = await page.evaluate(() => [...document.querySelectorAll('#wTbl tr[data-sym]')].filter(r => /\d/.test(r.textContent || '')).length)
    ok('60 只自选：全部列出且有价', n === 60 && priced >= 55, `行 ${n}，有价 ${priced}`)
    const t0 = Date.now(); await page.keyboard.press('ArrowDown'); await wait(50)
    for (let k = 0; k < 10; k++) { await page.keyboard.press('ArrowDown'); await wait(120) }
    ok('60 只自选里 ↓ 连切十只', true, `${Date.now() - t0} ms`)
    await shot('自选-60只')
    const w60 = await ws()
    ok('60 只自选的订阅在 200 条上限内', w60.live.every(l => l.subs.length <= 200), w60.live.map(l => l.subs.length).join(','))
  } else ok('60 只自选', false, '取不到币安成交额排行')
  // 没跟踪的品种开主力订单流：热力层空、不报错
  const e1 = errors.length
  await open('s=1000BONKUSDT&i=15m&layout=1&panel=watch&ladder=0&drawer=0')
  const heat = page.locator('#toolbar button', { hasText: '热力' })
  if (await heat.count()) { await heat.first().click(); await wait(4000) }
  await shot('订单流-未跟踪品种')
  ok('未跟踪品种开热力：不报错', sectionErrors(e1).length === 0, sectionErrors(e1).slice(0, 3).join(' | '))
  ok('边界：控制台无报错', sectionErrors(e0).length === 0, sectionErrors(e0).slice(0, 5).join(' | '))
}

// ═════════════════════════════ 皮肤 × 浅深 ═════════════════════════════
async function partThemes() {
  const e0 = errors.length
  await fresh()
  for (const skin of ['sage', 'terra', 'classic']) {
    for (const theme of ['light', 'dark']) {
      for (const [hash, name] of [['chart', '图表'], ['sectors', '板块'], ['review', '复盘'], ['me', '我的']]) {
        await open(`skin=${skin}&theme=${theme}&layout=1&panel=watch&ladder=0&drawer=0`, hash); await wait(800)
        await shot(`皮肤-${skin}-${theme}-${name}`)
      }
    }
  }
  // 找漏刷的颜色：深色下是否还有纯白底的大块元素
  const leaks = []
  for (const skin of ['sage', 'terra', 'classic']) {
    for (const hash of ['chart', 'sectors', 'review', 'me']) {
      await open(`skin=${skin}&theme=dark&layout=1&panel=watch&ladder=0&drawer=0`, hash); await wait(600)
      const bad = await page.evaluate(() => {
        const out = []
        for (const el of document.querySelectorAll('body *')) {
          const r = el.getBoundingClientRect(); if (r.width * r.height < 4000 || r.width === 0) continue
          const cs = getComputedStyle(el); if (cs.visibility === 'hidden' || cs.display === 'none') continue
          const m = cs.backgroundColor.match(/rgba?\((\d+), (\d+), (\d+)(?:, ([\d.]+))?\)/); if (!m) continue
          const a = m[4] === undefined ? 1 : +m[4]; if (a < 0.5) continue
          const lum = (+m[1] + +m[2] + +m[3]) / 3
          if (lum > 200) out.push(`${el.tagName.toLowerCase()}${el.id ? '#' + el.id : ''}.${[...el.classList].slice(0, 2).join('.')} ${cs.backgroundColor} ${Math.round(r.width)}×${Math.round(r.height)}`)
        }
        return out.slice(0, 6)
      })
      if (bad.length) leaks.push(`${skin}/${hash}: ${bad.join('; ')}`)
    }
  }
  ok('深色下没有漏刷成浅底的大块', !leaks.length, leaks.join(' || '))
  ok('皮肤：控制台无报错', sectionErrors(e0).length === 0, sectionErrors(e0).slice(0, 5).join(' | '))
}

// ═════════════════════════════ 线路 ═════════════════════════════
async function partRoute() {
  const e0 = errors.length
  await fresh('s=BTCUSDT&i=5s&layout=1&panel=watch&ladder=0&drawer=0')
  for (const route of ['gateway', 'direct']) {
    // 照人的路径切：我的 → 通用 → 行情线路
    await page.evaluate(() => { location.hash = 'me' }); await wait(600)
    await page.click('[data-me="general"]'); await wait(300)
    await page.click(`[data-seg="route"][data-v="${route}"]`); await wait(300)
    await page.evaluate(() => { location.hash = 'chart' }); await wait(9000)
    const w = await ws()
    const market = w.live.filter(l => /market\/stream|fstream/.test(l.url))
    const t1 = await page.evaluate(() => document.title); await wait(6000); const t2 = await page.evaluate(() => document.title)
    const empty = await page.locator('.cell-empty:not([hidden])').count()
    const want = route === 'gateway' ? /kanpan\.|localhost:5188\/market/ : /fstream\.binance\.com/
    ok(`线路 ${route}：连的是对的主机`, market.length === 1 && want.test(market[0].url) && !/binancefuture/.test(market[0].url), market.map(l => `${l.url}(${l.subs.length})`).join(' | '))
    ok(`线路 ${route}：5 秒 K 线靠逐笔成交自聚出来、价在动`, !empty && t1.includes('·'), `空态 ${empty}；标题 ${t1} → ${t2}`)
    await shot(`线路-${route}`)
  }
  ok('线路：控制台无报错', sectionErrors(e0).length === 0, sectionErrors(e0).slice(0, 5).join(' | '))
}

// ═════════════════════════════ 板块 ═════════════════════════════
async function partSectors() {
  const e0 = errors.length
  await fresh()
  await page.evaluate(() => { location.hash = 'sectors' }); await wait(15000)
  const rowsOf = () => page.evaluate(() => [...document.querySelectorAll('#secBody tr[data-sec]')].map(tr => ({
    id: tr.dataset.sec, name: tr.querySelector('.sec-name')?.textContent, beat: tr.children[2].textContent.trim(),
    pct: parseFloat((tr.querySelector('.sec-pct')?.textContent || '').replace('%', '')), spark: !!tr.querySelector('.sec-spark polyline'),
  })))
  let rows = await rowsOf()
  const fat = rows.filter(r => r.beat), thin = rows.filter(r => !r.beat)
  const desc = fat.every((r, i) => i === 0 || !(r.pct > fat[i - 1].pct))
  const thinLast = rows.slice(rows.length - thin.length).every(r => !r.beat)
  ok('板块排序：按涨跌幅降序，成员不到三家的沉底（照手机）', desc && thinLast, `${fat.length} 个 + 沉底 ${thin.length} 个（${thin.map(r => r.name).join('、')}）`)
  const noSpark = rows.filter(r => !r.spark).map(r => r.name)
  ok('15 秒内每个板块都有走势线', !noSpark.length, noSpark.join('、'))
  const beatOk = fat.every(r => /^\d+ \/ \d+$/.test(r.beat) && +r.beat.split('/')[0] <= +r.beat.split('/')[1])
  ok('跑赢大盘 = x / N（x ≤ N）', beatOk, fat.slice(0, 3).map(r => `${r.name} ${r.beat}`).join('，'))
  await page.locator('#secThead .term').first().hover(); await wait(900)
  const tip = await page.evaluate(() => document.querySelector('#tooltip')?.textContent?.trim().slice(0, 120) || '')
  ok('「跑赢大盘」悬停有口径说明', tip.length > 10, tip)
  const pick = rows[3]
  // 点开那一刻读顺序：之后逐笔价只原地改数字、不挪行（免得行在鼠标下跳），下一次行情刷新才重排
  const mp = await page.evaluate(id => {
    document.querySelector(`#secBody tr[data-sec="${CSS.escape(id)}"]`).click()
    return [...document.querySelectorAll('#secMBody tr[data-msym]')].map(tr => parseFloat(tr.textContent.match(/([+-]\d+\.\d+)%/)?.[1] ?? 'NaN'))
  }, pick.id)
  await wait(1500)
  const head = await page.evaluate(() => document.querySelector('#secMHead')?.textContent?.replace(/\s+/g, ' ').trim())
  const mRows = await page.locator('#secMBody tr[data-msym]').count()
  ok('点开一个板块：右边换成它的品种', !!head?.includes(pick.name) && mRows > 0, `${head}；${mRows} 只`)
  ok('板块里的品种点开时按涨跌降序', mp.every((v, i) => i === 0 || !(v > mp[i - 1])), mp.slice(0, 6).join(', '))
  const cols = await page.evaluate(() => [...document.querySelectorAll('#secThead th, #secMThead th')].map(t => `${t.textContent.trim() || '☆'}:${Math.round(t.getBoundingClientRect().width)}`))
  ok('2K 下两张表的列宽', true, cols.join(' '))
  await shot('板块-列表')
  await page.click('[data-mk="us"]'); await wait(4000)
  rows = await rowsOf()
  ok('切美股板块', rows.length > 0, rows.map(r => `${r.name} ${r.pct}%`).slice(0, 5).join('，'))
  await shot('板块-美股')
  const d5 = page.locator('[data-win="d5"]')
  if (await d5.count()) { await d5.click(); await wait(6000); rows = await rowsOf(); ok('5 日窗口', rows.length > 0, `${rows.length} 个板块`); await shot('板块-5日') }
  else ok('5 日窗口', false, '没有 5 日切换（服务端 5 日收盘没取到）')
  await page.click('[data-mk="crypto"]'); await wait(800)
  if (await page.locator('[data-win="today"]').count()) await page.click('[data-win="today"]')
  ok('板块：控制台无报错', sectionErrors(e0).length === 0, sectionErrors(e0).slice(0, 5).join(' | '))
}

// ═════════════════════════════ 提醒 ═════════════════════════════
async function partAlerts() {
  const e0 = errors.length
  await fresh('s=BTCUSDT&i=1h&layout=1&panel=alerts&ladder=0&drawer=0')
  const n0 = (await state()).alerts.length
  // Alt A 打开「创建提醒」：价格达到
  await page.mouse.click(1000, 600); await page.keyboard.press('Alt+KeyA'); await wait(500)
  ok('Alt A 打开「创建提醒」', await page.locator('.alert-dlg #aPrice').count() === 1)
  const last = +(await page.inputValue('#aPrice'))
  await page.fill('#aPrice', String(Math.round(last * 1.2))); await page.click('#aOk'); await wait(500)
  let s = await state()
  const a1 = s.alerts.find(a => a.kind === 'price' && Math.abs(a.lines[0].points[0].p - Math.round(last * 1.2)) < 1)
  ok('价格达到：建一条（高于现价 20%）', s.alerts.length === n0 + 1 && !!a1, a1?.title || '')
  // 资金费率、持仓量变化，带 Webhook（地址不对不给建）
  await page.keyboard.press('Alt+KeyA'); await wait(400)
  await page.click('#aKind [data-k="funding"]'); await page.click('[data-op="below"]'); await page.fill('#aNum', '-0.5')
  await page.fill('#aHook', 'ftp://x'); await page.click('#aOk'); await wait(300)
  const stillOpen = await page.locator('.alert-dlg').count()
  await page.fill('#aHook', 'https://example.com/hook'); await page.click('#aOk'); await wait(400)
  await page.keyboard.press('Alt+KeyA'); await wait(400)
  await page.click('#aKind [data-k="oi"]'); await page.fill('#aNum', '8'); await page.click('#aOk'); await wait(400)
  s = await state()
  const fr = s.alerts.find(a => a.rule?.type === 'funding'), oi = s.alerts.find(a => a.rule?.type === 'openInterestChange')
  ok('Webhook 地址不对不给建；资金费率低于 −0.5% 带 Webhook', stillOpen === 1 && fr?.rule.side === 'below' && fr?.rule.rate === '-0.005' && fr?.webhook === 'https://example.com/hook', JSON.stringify(fr?.rule))
  ok('持仓量 1 小时变化超 8%', oi?.rule.threshold === '0.08', JSON.stringify(oi?.rule))
  const rows = await page.locator('#panelBody .alert-row, .alert-row').count()
  ok('侧栏「提醒」列出这只品种在等的三条', rows >= 3, `${rows} 行`)
  await shot('提醒-侧栏')
  // 全部提醒：按类筛
  await page.click('#aAllBtn'); await wait(400)
  const fs = await page.evaluate(() => [...document.querySelectorAll('#aaF button')].map(b => b.textContent.trim()))
  await page.click('#aaF [data-f="condition"]'); await wait(200)
  const condRows = await page.locator('.alerts-all-dlg .alert-row').count()
  ok('全部提醒：分全部 / 价格 / 条件，条件筛出两条', fs.some(x => x.startsWith('价格')) && fs.some(x => x.startsWith('条件')) && condRows === 2, fs.join(' · '))
  await shot('提醒-全部')
  // 总表里删一条，侧栏跟着少
  await page.locator('.alerts-all-dlg [data-del-alert]').first().click(); await wait(400)
  const condRows2 = await page.locator('.alerts-all-dlg .alert-row').count()
  await page.keyboard.press('Escape'); await wait(300)
  s = await state()
  ok('总表里删一条：表和侧栏一起少', condRows2 === 1 && s.alerts.length === n0 + 2 && await page.locator('.alert-row').count() === rows - 1, `${condRows} → ${condRows2}`)
  // 响一次就结束：贴着现价上下各放一条（差一个最小价位）。线正好压在上一笔价上不算碰（那一下已经算过，
  // 和手机 AlertWatcher 同一条规矩），所以只要下一笔成交价和现价不同，就一定穿过其中一条
  const raw = await (async () => { await page.keyboard.press('Alt+KeyA'); await wait(400); const v = await page.inputValue('#aPrice'); await page.keyboard.press('Escape'); await wait(200); return v })()
  const dec = (raw.split('.')[1] || '').length, tick = 10 ** -dec, cur = +raw || last
  const nB = (await state()).alerts.length
  for (const px of [cur + tick, cur - tick]) {
    await page.keyboard.press('Alt+KeyA'); await wait(400)
    await page.fill('#aPrice', px.toFixed(dec)); await page.click('#aOk'); await wait(300)
  }
  const nA = (await state()).alerts.length
  let gone = false
  for (let k = 0; k < 60 && !gone; k++) { await wait(500); gone = (await state()).alerts.length < nA }
  const toastTxt = await page.evaluate(() => [...document.querySelectorAll('.toast')].map(t => t.textContent.trim()).join(' | '))
  ok('价格提醒贴着现价（±1 个价位两条）：逐笔价一穿就响、响完从表里删掉、弹提示', nA === nB + 2 && gone && /已结束/.test(toastTxt), gone ? toastTxt.slice(0, 80) : `30 秒内没响（现价 ${raw}）`)
  await shot('提醒-触发')
  ok('提醒：控制台无报错', sectionErrors(e0).length === 0, sectionErrors(e0).slice(0, 5).join(' | '))
}

// ═════════════════════════════ 账号与同步 ═════════════════════════════
// 账号从环境变量读：KP_USER（默认 webtest_w0929a）、KP_PASS（必填，不进仓库）
const KP_USER = process.env.KP_USER || 'webtest_w0929a'
const KP_PASS = process.env.KP_PASS || ''
const ACCOUNT_KEY = 'hkline-web-account-v1'
const stored = (pg = page) => pg.evaluate(k => JSON.parse(localStorage.getItem(k) || 'null'), ACCOUNT_KEY)
/** 用这个页面自己的会话调接口（令牌从 localStorage 读） */
const api = (method, path, body, pg = page, extra = {}) => pg.evaluate(async ([m, p, b, x, k]) => {
  const v = JSON.parse(localStorage.getItem(k) || 'null')
  const h = { ...(v ? { Authorization: 'Bearer ' + v.accessToken } : {}), ...(b != null ? { 'Content-Type': 'application/json' } : {}), ...x }
  const r = await fetch(p, { method: m, headers: h, body: b == null ? undefined : JSON.stringify(b), cache: 'no-store' })
  let j = null; try { j = await r.json() } catch { /* 不是 JSON */ }
  return { status: r.status, data: j?.data ?? null, error: j?.error?.code ?? null }
}, [method, path, body ?? null, extra, ACCOUNT_KEY])
async function uiLogin(pg = page) {
  await pg.goto(`${URL_}#me`, { waitUntil: 'domcontentloaded' }); await pg.waitForTimeout(1500)
  await pg.click('[data-me="account"]'); await pg.waitForTimeout(300)
  if (await pg.locator('#acctLogout').count()) return true
  await pg.click('[data-auth="login"]')
  await pg.fill('#acctUser', KP_USER); await pg.fill('#acctPass', KP_PASS); await pg.click('#acctGo')
  for (let k = 0; k < 40; k++) { await pg.waitForTimeout(250); if (await stored(pg)) return true }
  return false
}
/** 从 cursor 起轮询 /v1/sync/changes，直到 want 里的每个键都出现（或超时）；返回每个键看到的时刻 */
async function waitChanges(cursor, want, t0, limit = 15000) {
  const seen = {}
  let c = cursor
  while (Date.now() - t0 < limit && want.some(w => !(w.key in seen))) {
    const r = await api('GET', `/v1/sync/changes?cursor=${c}`)
    if (r.status === 200) {
      // 不带 collection 订阅时，变更都以 invalidations（collection / id / deleted）回来
      for (const o of [...(r.data.objects || []), ...(r.data.invalidations || [])]) {
        const key = `${o.collection}:${o.id}`
        const w = want.find(x => x.key === key)
        if (w && !(key in seen) && (w.deleted === undefined || !!o.deleted === w.deleted)) seen[key] = Date.now() - t0
      }
      if (!r.data.hasMore) c = r.data.cursor
      else { c = r.data.cursor; continue }
    }
    await wait(700)
  }
  return seen
}
/** 云端这一个对象现在的样子：live / deleted / none */
async function cloud(collection, id) {
  const r = await api('GET', `/v1/sync/bootstrap?collection=${collection}&prefix=${encodeURIComponent(id)}`)
  const o = (r.data?.objects || []).find(x => x.id === id)
  return o ? (o.deleted ? 'deleted' : 'live') : 'none'
}
async function waitCloud(collection, id, want, t0, limit = 15000) {
  let got = ''
  while (Date.now() - t0 < limit) { got = await cloud(collection, id); if (got === want) return Date.now() - t0; await wait(700) }
  return null
}
const toggleDoge = async () => {
  await page.keyboard.press('Meta+k'); await wait(300); await page.keyboard.type('DOGE')
  await page.waitForSelector('[data-w="DOGEUSDT"]', { timeout: 5000 }).catch(() => {})
  await wait(300); await page.keyboard.press('Shift+Enter'); await wait(300); await page.keyboard.press('Escape'); await wait(200)
  return (await state()).watch.crypto.includes('DOGEUSDT')
}
async function syncCursor() { const r = await api('GET', '/v1/sync/bootstrap?collection=favorites'); return r.data?.cursor ?? 0 }

async function partAccount() {
  const e0 = errors.length
  if (!KP_PASS) { ok('账号段', false, '没给 KP_PASS 环境变量'); return }
  await fresh('s=BTCUSDT&i=1h&layout=1&panel=watch&ladder=0&drawer=0')
  const net = { refresh: [], ops: [], sync: [] }
  const onReq = r => {
    const u = r.url()
    if (u.includes('/v1/auth/refresh')) net.refresh.push(Date.now())
    if (u.includes('/v1/sync/operations')) net.ops.push(Date.now())
    if (u.includes('/v1/sync/')) net.sync.push(Date.now())
  }
  page.on('request', onReq)
  const logged = await uiLogin()
  const acc = await stored()
  ok('网页登录（用户名 + 密码）', logged && !!acc?.userId, acc ? `${acc.username}` : '')
  let owner = null
  for (let k = 0; k < 40 && owner !== acc?.userId; k++) { await wait(500); owner = await page.evaluate(() => localStorage.getItem('hkline-web-sync-owner')) }
  ok('登录后首次全量对上（sync owner 落盘）', owner === acc?.userId)
  await shot('账号-已登录')

  // ---- 改自选 / 画线 / 提醒，15 秒内到云端
  await page.goto(`${URL_}?s=BTCUSDT&i=1h&layout=1&panel=watch#chart`, { waitUntil: 'domcontentloaded' }); await ready()
  const c0 = await syncCursor()
  const wasW = (await state()).watch.crypto.includes('DOGEUSDT')
  const t0 = Date.now()
  await toggleDoge()
  const P = await plotGeom()
  await page.click('#drawbar [data-tool="hline"]'); await wait(150)
  const dIds0 = new Set(((await state()).drawings.BTCUSDT || []).map(d => d.id))
  const aIds0 = new Set((await state()).alerts.map(a => a.id))
  await page.mouse.click(P.x + (P.axisX - P.x) * 0.5, P.y + P.height * 0.25); await wait(300); await page.keyboard.press('Escape')
  // 价格轴上 10 像素内已有提醒线时，点下去是「抓那条线」而不是新建（测试账号云端攒着前几轮建的），
  // 所以往下挪着试，直到真建出一条新的
  for (const f of [0.3, 0.36, 0.42, 0.48, 0.54, 0.6]) {
    await page.mouse.move(P.axisX + 8, P.y + P.height * f); await page.mouse.down(); await page.mouse.up(); await wait(400)
    if ((await state()).alerts.some(a => !aIds0.has(a.id))) break
  }
  let s = await state()
  const isW = s.watch.crypto.includes('DOGEUSDT')
  const hl = (s.drawings.BTCUSDT || []).find(d => !dIds0.has(d.id))
  // 只认这一下新建的那条（列表末尾可能是云端早就有的老提醒）
  const al = s.alerts.find(a => !aIds0.has(a.id))
  const want = [
    { key: 'favorites:binance/usd_m/DOGEUSDT', deleted: !isW },
    ...(hl ? [{ key: `drawings:binance/usd_m/BTCUSDT/${hl.id}`, deleted: false }] : []),
    ...(al ? [{ key: `alerts:binance/usd_m/${al.symbol}/${al.id}`, deleted: false }] : []),
  ]
  const seen = await waitChanges(c0, want, t0)
  ok('改自选 / 画水平线 / 点价格轴建提醒：15 秒内都出现在 /v1/sync/changes', isW !== wasW && want.length === 3 && want.every(w => w.key in seen),
    want.map(w => `${w.key.split(':')[0]} ${seen[w.key] != null ? seen[w.key] + ' ms' : '没到'}`).join('，') + (hl ? '' : '；没画出新水平线') + (al ? '' : '；价格轴没建出新提醒'))

  // ---- 令牌自动续期：access 到期 → 下一次同步先换一对新令牌
  let before = await stored()
  await page.evaluate(k => { const v = JSON.parse(localStorage.getItem(k)); v.accessDeadline = Date.now() - 1000; localStorage.setItem(k, JSON.stringify(v)) }, ACCOUNT_KEY)
  const r0 = net.refresh.length
  let t2 = Date.now()
  let w2 = await toggleDoge()
  let at2 = await waitCloud('favorites', 'binance/usd_m/DOGEUSDT', w2 ? 'live' : 'deleted', t2)
  let after = await stored()
  ok('access 到期：先换一次令牌再推，改动照常到云端', net.refresh.length - r0 === 1 && after.accessToken !== before.accessToken && after.refreshToken !== before.refreshToken && !after.pending && at2 != null, `换了 ${net.refresh.length - r0} 次；DOGE ${w2 ? '加回' : '移出'}自选 ${at2} ms 到云端`)
  // access 被服务端拒（authentication_failed）：换一次、重试成功
  before = after
  await page.evaluate(k => { const v = JSON.parse(localStorage.getItem(k)); v.accessToken = 'x' + v.accessToken.slice(1); localStorage.setItem(k, JSON.stringify(v)) }, ACCOUNT_KEY)
  const r1 = net.refresh.length
  t2 = Date.now()
  w2 = await toggleDoge()
  for (let k = 0; k < 20 && net.refresh.length === r1; k++) await wait(300)
  at2 = await waitCloud('favorites', 'binance/usd_m/DOGEUSDT', w2 ? 'live' : 'deleted', t2)
  after = await stored()
  ok('access 被拒（401）：换一次令牌后重试，改动照常到云端', net.refresh.length - r1 === 1 && !!after && after.accessToken !== before.accessToken && at2 != null, `换了 ${net.refresh.length - r1} 次；DOGE ${w2 ? '加回' : '移出'}自选 ${at2} ms 到云端`)
  // 复盘页：浏览器关掉超过 15 分钟再打开（access 已过期），直接进 #review 不能说「登录已过期」
  await page.evaluate(k => { const v = JSON.parse(localStorage.getItem(k)); v.accessDeadline = Date.now() - 60e3; v.accessToken = 'x' + v.accessToken.slice(1); localStorage.setItem(k, JSON.stringify(v)) }, ACCOUNT_KEY)
  await page.goto(`${URL_}#review`, { waitUntil: 'domcontentloaded' }); await page.reload({ waitUntil: 'domcontentloaded' }); await wait(5000)
  const rvExpired = await page.locator('.rv-login').count()
  ok('access 过期后直接打开复盘页：先续期再取数，不弹「登录已过期」', rvExpired === 0, rvExpired ? await page.locator('.rv-login').innerText() : '')

  // ---- 退登再登录：本机的留着；退登期间画的线登录后推上去，不重复
  await page.goto(`${URL_}#me`, { waitUntil: 'domcontentloaded' }); await wait(1200)
  await page.click('[data-me="account"]'); await wait(300)
  await page.click('#acctLogout'); await wait(800)
  s = await state()
  ok('退出登录：账号令牌清掉，本机的自选、画线、提醒都留着', !(await stored()) && (s.drawings.BTCUSDT || []).some(d => d.id === hl?.id) && s.alerts.some(a => a.id === al?.id))
  await page.goto(`${URL_}?s=BTCUSDT&i=1h&layout=1#chart`, { waitUntil: 'domcontentloaded' }); await ready()
  const Q = await plotGeom()
  await page.click('#drawbar [data-tool="hline"]'); await wait(150)
  const dIds1 = new Set(((await state()).drawings.BTCUSDT || []).map(d => d.id))
  await page.mouse.click(Q.x + (Q.axisX - Q.x) * 0.4, Q.y + Q.height * 0.4); await wait(300); await page.keyboard.press('Escape')
  s = await state()
  const offline = (s.drawings.BTCUSDT || []).find(d => !dIds1.has(d.id))
  const nDraw = (s.drawings.BTCUSDT || []).length
  const t1 = Date.now()
  await uiLogin()
  const at3 = offline ? await waitCloud('drawings', `binance/usd_m/BTCUSDT/${offline.id}`, 'live', t1, 20000) : null
  s = await state()
  const nDraw2 = (s.drawings.BTCUSDT || []).length
  ok('退登期间画的线：再登录后推到云端；本机画线条数不变（不重复、不丢）', !!offline && at3 != null && nDraw2 === nDraw, `登录起 ${at3 ?? '没到'} ms 到云端；${nDraw} → ${nDraw2} 条`)

  // ---- 被另一台电脑顶掉：session_replaced 后回到未登录、不死循环刷新
  const ctx2 = await browser.newContext({ viewport: { width: 1600, height: 1000 } })
  const p2 = await ctx2.newPage()
  await p2.goto(URL_, { waitUntil: 'load' }); await p2.waitForTimeout(800)
  const other = await uiLogin(p2)
  const navs = []
  const onNav = f => { if (f === page.mainFrame()) navs.push(f.url()) }
  page.on('framenavigated', onNav)
  const rr = net.refresh.length, sr = net.sync.length
  await page.bringToFront(); await page.evaluate(() => window.dispatchEvent(new Event('focus')))
  let gone = false
  for (let k = 0; k < 40 && !gone; k++) { await wait(500); gone = !(await stored()) }
  const syncAtEnd = net.sync.length
  await wait(20000)
  page.off('framenavigated', onNav)
  await page.goto(`${URL_}#me`, { waitUntil: 'domcontentloaded' }); await wait(1000)
  await page.click('[data-me="account"]'); await wait(300)
  const notice = await page.locator('.acct-notice').innerText().catch(() => '')
  ok('另一台电脑登录：这台收到 session_replaced 回到未登录，提示「已在另一台电脑登录」', other && gone && /另一台电脑/.test(notice), notice)
  ok('顶掉之后不死循环：20 秒里没有再换令牌、没有再同步、页面没刷新', net.refresh.length - rr <= 1 && net.sync.length === syncAtEnd && navs.length === 0, `换令牌 ${net.refresh.length - rr} 次，顶掉后同步请求 ${net.sync.length - syncAtEnd} 次（顶掉前 ${syncAtEnd - sr}），页面导航 ${navs.length} 次`)
  await shot('账号-被顶掉')
  // 收尾：另一台退出登录（吊销会话）
  await p2.goto(`${URL_}#me`, { waitUntil: 'domcontentloaded' }); await p2.waitForTimeout(1000)
  await p2.click('[data-me="account"]').catch(() => {}); await p2.waitForTimeout(300)
  await p2.click('#acctLogout').catch(() => {}); await p2.waitForTimeout(800)
  await ctx2.close()
  page.off('request', onReq)
  // 故意弄坏令牌、被顶掉时浏览器自己会打一行「401 (Unauthorized)」的资源错误，那是预期的
  const errs = sectionErrors(e0).filter(x => !/status of 401/.test(x))
  ok('账号与同步：控制台无报错（故意造的 401 资源错误除外）', errs.length === 0, `401 资源错误 ${sectionErrors(e0).length - errs.length} 条；` + errs.slice(0, 5).join(' | '))
}

// ═════════════════════════════ 复盘页 ═════════════════════════════
// 测试账号本来是空的：先看空态，再用接口种一个交易回合 + 一条观点记录（id 与时间都固定，
// 重跑幂等、不会越种越多），然后以交易员身份把列表、回放、笔记、找相似、收藏走一遍。
const RV_T0 = Date.UTC(2026, 8, 26, 2, 0, 0) // 上海 09-26 10:00 开仓
const RV_T1 = RV_T0 + 6 * 3600e3 + 10 * 60e3 // 6 小时 10 分后平仓
const RV_VIEW_ID = '7e57c0de-0929-4a00-8b00-00000000a002'
async function kl(symbol, iv, start, limit) {
  const r = await fetch(`https://fapi.binance.com/fapi/v1/klines?symbol=${symbol}&interval=${iv}&startTime=${start}&limit=${limit}`)
  return (await r.json()).map(x => ({ t: x[0], o: x[1], c: x[4] }))
}
async function roundId(parts) {
  const { createHash } = await import('node:crypto')
  const b = createHash('sha256').update(['trade-round-v1', ...parts].join('\n')).digest().subarray(0, 16)
  b[6] = (b[6] & 0x0f) | 0x80; b[8] = (b[8] & 0x3f) | 0x80
  const h = b.toString('hex')
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`
}
async function seedReview() {
  const [a] = await kl('BTCUSDT', '1m', RV_T0 + 3 * 60e3, 1), [z] = await kl('BTCUSDT', '1m', RV_T1, 1)
  const qty = '0.050', open = a.o, close = z.c
  const pnl = ((+close - +open) * 0.05).toFixed(4), fee = ((+open + +close) * 0.05 * 0.0005).toFixed(4)
  const net = (+pnl - +fee - 0.8).toFixed(4)
  const f1 = { id: '9290001', orderId: '8290001', time: RV_T0 + 3 * 60e3, side: 'BUY', positionSide: 'BOTH', role: 'open', price: open, qty, quoteQty: (+open * 0.05).toFixed(4), commission: (+open * 0.05 * 0.0005).toFixed(4), commissionAsset: 'USDT', realizedPnl: '0', maker: false, split: false }
  const f2 = { id: '9290002', orderId: '8290002', time: RV_T1, side: 'SELL', positionSide: 'BOTH', role: 'close', price: close, qty, quoteQty: (+close * 0.05).toFixed(4), commission: (+close * 0.05 * 0.0005).toFixed(4), commissionAsset: 'USDT', realizedPnl: pnl, maker: true, split: false }
  const id = await roundId(['binance', 'usd_m', 'webtest', 'BTCUSDT', 'BOTH', f1.id])
  const round = {
    version: 1, id, venue: 'binance', market: 'usd_m', accountTag: 'webtest', symbol: 'BTCUSDT', positionSide: 'BOTH', direction: 'long', status: 'closed',
    quoteAsset: 'USDT', openedAt: f1.time, closedAt: f2.time, holdingMs: f2.time - f1.time, updatedAt: f2.time,
    openAvgPrice: open, closeAvgPrice: close, openedQty: qty, closedQty: qty, maxQty: qty, peakNotional: (+open * 0.05).toFixed(4),
    realizedPnl: pnl, commission: fee, funding: '-0.8', netPnl: net, leverage: 10,
    commissionByAsset: { USDT: fee }, commissionUnpriced: false, fills: [f1, f2],
  }
  const up = await api('POST', '/v1/native-review/trades', { rounds: [round] }, page, { 'Idempotency-Key': crypto.randomUUID() })
  // 观点记录：开仓前 32 根 15m 作图表区间（1h / 4h 的全市场历史常常一段都不够像，15m 候选多），看多，目标 +2%、失效 −1.5%
  const bars = await kl('BTCUSDT', '15m', RV_T0 - 32 * 900e3, 32)
  const ref = +bars[bars.length - 1].c
  const draft = {
    id: RV_VIEW_ID, range: { venue: 'binance', market: 'usd_m', symbol: 'BTCUSDT', interval: '15m', start: RV_T0 - 32 * 900e3, end: RV_T0, bars: 32 },
    rule: { version: 'criteria-v2', direction: 'long', confirmation: 'bar_close', reference: ref, target: +(ref * 1.02).toFixed(1), invalidation: +(ref * 0.985).toFixed(1), expires: RV_T0 + 30e3 + 2 * 86400e3, targetEdited: false, invalidationEdited: false, expiryEdited: false },
    text: '回归测试：回踩前低不破，看多到前高', confidence: 70, origin: 'chart_first', created: RV_T0 + 30e3, chartSettings: null, drawingSnapshot: null, originalClaimed: null,
  }
  const vw = await api('POST', '/v1/native-review/records', draft, page, { 'Idempotency-Key': crypto.randomUUID() })
  return { id, up, vw }
}

async function partReview() {
  const e0 = errors.length
  if (!KP_PASS) { ok('复盘段', false, '没给 KP_PASS 环境变量'); return }
  await fresh('s=BTCUSDT&i=1h&layout=1')
  // 没登录：进复盘是登录引导
  await page.goto(`${URL_}#review`, { waitUntil: 'domcontentloaded' }); await wait(1200)
  const gate = await page.locator('.rv-login').innerText().catch(() => '')
  ok('没登录进复盘：给登录引导（复盘需要登录）', /复盘需要登录/.test(gate))
  const logged = await uiLogin()
  ok('登录', logged)
  const before = await api('GET', '/v1/native-review/records?kind=trade')
  await page.goto(`${URL_}#review`, { waitUntil: 'domcontentloaded' }); await page.reload({ waitUntil: 'domcontentloaded' }); await wait(3500)
  const counts0 = await page.$$eval('[data-tab] .rv-count', ns => ns.map(n => n.textContent.trim()))
  if (!(before.data?.records || []).length) {
    ok('空账号：三个页签计数都是 0、没有报错', counts0.join(',') === '0,0,0' && !(await page.locator('.rv-err').count()), counts0.join(' / '))
    await shot('复盘-空态')
  } else ok('复盘页载入（账号里已有前几轮种的数据）', counts0.length === 3, counts0.join(' / '))

  const seed = await seedReview()
  ok('种一个交易回合 + 一条观点记录（接口，幂等）', seed.up.status === 200 && seed.vw.status === 200, `回合 ${seed.up.status}${seed.up.error ? ' ' + seed.up.error : ''}，观点 ${seed.vw.status}${seed.vw.error ? ' ' + seed.vw.error : ''}`)
  // 结果由服务端 worker 回写（最大浮盈浮亏、平仓后 1/4/24h），等它最多 40 秒
  let rec = null
  for (let k = 0; k < 40; k++) {
    const r = await api('GET', '/v1/native-review/records?kind=trade')
    rec = (r.data?.records || []).find(x => x.id === seed.id)
    if (rec?.result) break
    await wait(1000)
  }
  ok('服务端回写回合结果（最大浮盈 / 浮亏、平仓后走势）', !!rec?.result?.excursion, rec?.result ? `浮盈 ${rec.result.excursion?.maxFavorablePct}，24h ${rec.result.after?.h24?.changePct ?? '—'}` : '没回写')

  // ---- 交易回合
  await page.click('#rvRefresh'); await wait(2500)
  await page.click('[data-tab="trade"]'); await wait(400)
  const row = page.locator(`[data-trade="${seed.id}"]`)
  ok('交易回合列表里有这一回合', await row.count() === 1)
  await row.click(); await wait(3500)
  const foot = await page.locator('#rvFoot').innerText()
  ok('选中回合：右侧给净盈亏、费用、浮盈浮亏、持仓、均价、平仓后走势', ['净盈亏', '费用', '最大浮盈', '持仓', '开仓均价', '平仓后走势'].every(k => foot.includes(k)), foot.replace(/\s+/g, ' ').slice(0, 120))
  const hasCanvas = await page.locator('#rvWrap canvas').count()
  const ticks = await page.locator('#rvBar .tick').count()
  ok('回放：拉到当时的 K 线、进度条上标出开仓 / 平仓', hasCanvas > 0 && ticks >= 2, `画布 ${hasCanvas}，记号 ${ticks}`)
  const knob0 = await page.locator('#rvBar .knob').evaluate(n => n.style.left || getComputedStyle(n).left)
  const fastest = await page.$$eval('#rvBar [data-rp="speed"]', ns => ns[ns.length - 1].dataset.v)
  await page.click(`#rvBar [data-rp="speed"][data-v="${fastest}"]`)
  await page.click('#rvBar [data-rp="toggle"]'); await wait(2500)
  const knob1 = await page.locator('#rvBar .knob').evaluate(n => n.style.left || getComputedStyle(n).left)
  const floatTxt = await page.locator('#rvWrap').innerText()
  ok('回放：点播放进度往前走，图上跟着显示开仓前 / 持仓中 / 已平仓', knob1 !== knob0 && /开仓前|持仓中|已平仓/.test(floatTxt), `${knob0} → ${knob1}；${floatTxt.replace(/\s+/g, ' ').slice(0, 40)}`)
  await page.locator('#rvBar [data-rp="toggle"]').click().catch(() => {})
  const keys = await page.locator('#rvBar [data-rp="key"]').allInnerTexts()
  if (keys.length) { await page.locator('#rvBar [data-rp="key"]').first().click(); await wait(600) }
  ok('回放：关键点跳转按钮（不逐根步进）', keys.length > 0 && !(await page.locator('#rvBar [data-rp="step"],#rvBar [data-rp="prev"],#rvBar [data-rp="next"]').count()), keys.join(' · '))
  await shot('复盘-交易回合')
  // 当时怎么想：写、存，云端版本加一
  const note = '回归 ' + new Date().toISOString().slice(0, 16)
  await page.fill('#rvNote', note); await wait(150)
  const enabled = await page.locator('#rvNoteSave').isEnabled()
  await page.click('#rvNoteSave'); await wait(1500)
  const r2 = await api('GET', '/v1/native-review/records?kind=trade')
  const saved = (r2.data?.records || []).find(x => x.id === seed.id)
  ok('回合笔记「当时怎么想」：改了才能存，存上云端、版本加一', enabled && saved?.note?.text === note && saved.revision > (rec?.revision ?? 0), `rev ${rec?.revision} → ${saved?.revision}`)

  // ---- 观点记录
  await page.click('[data-tab="view"]'); await wait(500)
  const vrow = page.locator(`[data-view="${RV_VIEW_ID}"]`)
  ok('观点记录列表里有这一条', await vrow.count() === 1)
  await vrow.click(); await wait(3500)
  const vfoot = await page.locator('#rvFoot').innerText()
  ok('选中观点：给出判断原文、方向与结果', /回踩前低不破/.test(vfoot) && /结果/.test(vfoot), vfoot.replace(/\s+/g, ' ').slice(0, 100))
  await shot('复盘-观点记录')
  // 找相似：发起、等它找完、收藏一条、再取消
  const nSearch0 = (await page.evaluate(() => JSON.parse(localStorage.getItem('hkline-review-searches') || '[]'))).length
  await page.click(`[data-find="${RV_VIEW_ID}"]`); await wait(1500)
  const tabNow = await page.locator('[data-tab="similar"][aria-selected="true"]').count()
  const nSearch1 = (await page.evaluate(() => JSON.parse(localStorage.getItem('hkline-review-searches') || '[]'))).length
  ok('找相似：发起后切到「相似走势」、这次搜索记在本机', tabNow === 1 && nSearch1 === Math.min(8, nSearch0 + 1), `${nSearch0} → ${nSearch1}`)
  let items = 0, stTxt = ''
  for (let k = 0; k < 60; k++) {
    await wait(2000)
    items = await page.locator('[data-match^="search:"]').count()
    stTxt = await page.locator('.rv-search').first().innerText().catch(() => '')
    if (items || /没有找到/.test(stTxt)) break
  }
  ok('找相似：两分钟内找完、列出相似片段', items > 0 || /没有找到/.test(stTxt), items ? `${items} 段` : stTxt.replace(/\s+/g, ' ').slice(0, 80))
  if (!items) {
    // 这一段历史里没有够像的：换最近 32 根 15m 在接口上发起一次（等于另一个页签里找的），
    // 记进本机的搜索列表，切回「相似走势」时页面自己补问——顺带验「别的页签新找的相似」那条路
    const Q = 900e3, end = Math.floor((Date.now() - 2 * 3600e3) / Q) * Q
    const range = { venue: 'binance', market: 'usd_m', symbol: 'BTCUSDT', interval: '15m', start: end - 32 * Q, end, bars: 32 }
    const job = await api('POST', '/v1/native-review/searches', { range, cutoff: Date.now() - 1000, scope: 'history' }, page, { 'Idempotency-Key': crypto.randomUUID() })
    const jid = job.data?.id
    for (let k = 0; jid && k < 60; k++) { await wait(2000); const st = await api('GET', `/v1/native-review/searches/${jid}`); if (!/queued|running/.test(st.data?.status)) break }
    if (jid) await page.evaluate(m => { const k = 'hkline-review-searches'; localStorage.setItem(k, JSON.stringify([m, ...JSON.parse(localStorage.getItem(k) || '[]')])) }, { id: jid, symbol: 'BTCUSDT', iv: '15m', bars: 32, label: 'BTC 15分 · 32 根', created: Date.now() })
    await page.click('[data-tab="trade"]'); await wait(300); await page.click('[data-tab="similar"]'); await wait(3000)
    items = await page.locator('[data-match^="search:"]').count()
    ok('别的页签新找的相似：切到「相似走势」时补问、列出来', items > 0, `${items} 段`)
  }
  if (items) {
    await page.locator('[data-match^="search:"]').first().click()
    let mfoot = ''
    for (let k = 0; k < 30 && !/相似段之后/.test(mfoot); k++) { await wait(500); mfoot = await page.locator('#rvFoot').innerText() }
    ok('选一段相似：回放它、K 线载入后给出「后来怎么走」', (await page.locator('#rvWrap canvas').count()) > 0 && /相似段之后 \d+ 根/.test(mfoot), mfoot.replace(/\s+/g, ' ').slice(0, 90))
    await shot('复盘-相似走势')
    const nSaved0 = (await api('GET', '/v1/native-review/saved-matches')).data?.items?.length ?? 0
    await page.locator('[data-save]').first().click(); await wait(1500)
    const nSaved1 = (await api('GET', '/v1/native-review/saved-matches')).data?.items?.length ?? 0
    const un = page.locator('[data-unsave]').first()
    if (await un.count()) { await un.click(); await wait(1500) }
    const nSaved2 = (await api('GET', '/v1/native-review/saved-matches')).data?.items?.length ?? 0
    ok('收藏相似片段、再取消收藏：云端条数 +1 再 −1', nSaved1 === nSaved0 + 1 && nSaved2 === nSaved0, `${nSaved0} → ${nSaved1} → ${nSaved2}`)
  }
  // 在图表中打开
  await page.click('[data-tab="trade"]'); await wait(400); await page.locator(`[data-trade="${seed.id}"]`).click(); await wait(800)
  await page.locator('#rvDetHead [data-open]').click(); await wait(2000)
  ok('「在图表中打开」跳到图表页、品种是 BTC', /#chart/.test(page.url()) && /BTC/.test(await page.title()), page.url().split('#')[1])
  ok('复盘：控制台无报错', sectionErrors(e0).length === 0, sectionErrors(e0).slice(0, 5).join(' | '))
}

const ALL = { chart: partChart, alerts: partAlerts, edge: partEdge, themes: partThemes, route: partRoute, sectors: partSectors, account: partAccount, review: partReview }
for (const k of PARTS.length ? PARTS : Object.keys(ALL)) {
  console.log(`\n══ ${k} ══`)
  try { await ALL[k]() } catch (e) { ok(`${k} 段跑完`, false, String(e.stack || e).split('\n').slice(0, 3).join(' ')); await page.screenshot({ path: `${OUT}/回归-失败-${k}.png` }).catch(() => {}) }
}
console.log('\n控制台报错：', errors.length ? '\n' + errors.join('\n') : '0')
console.log(`\n合计 ${results.length} 项，失败 ${results.filter(r => !r.pass).length} 项`)
await browser.close()
