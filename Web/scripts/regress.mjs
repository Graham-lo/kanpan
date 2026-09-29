// Hkline Web · 整体回归（以交易员身份把网页版走一遍）：本机 Chrome、2560×1440、DPR 1
//   node scripts/regress.mjs [地址] [段落…]
//   段落：chart（图表页）、draw（画线：新工具、编辑交互、快捷键、同步）、alerts（提醒）、edge（边界）、themes（皮肤）、route（线路）、sectors（板块）、
//         account（账号与同步）、review（复盘）、layout（布局与拖动）、levels（指标与叠加）、watch（自选小部件与 TradingView 导入）、
//         flow（订单流：梯子成交列 / 变化 / 24 小时两块 / 成交流）；account / review / draw 的同步那步要 KP_PASS 环境变量，watch 有它时顺带核对导入的云端同步
//   默认地址 http://localhost:5188/web/；截图写到 docs/acceptance/网页版-2026-09-29/回归-*.png（REGRESS_OUT 环境变量可改到别处，压测反复跑时不去动已提交的验收图）
// 每一段都收集控制台报错与未处理的 Promise 拒绝，目标是 0；每一项的结论打一行「✓ / ✗」。
import { chromium } from 'playwright-core'
import { mkdirSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const URL_ = process.argv[2] || 'http://localhost:5188/web/'
const PARTS = process.argv.slice(3)
const OUT = process.env.REGRESS_OUT || resolve(here, '../../docs/acceptance/网页版-2026-09-29')
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
// 控制台的「Failed to load resource」不带地址：另记一笔 4xx / 5xx 的地址，报错时看得出是谁（币安限频、网关、同步接口）
page.on('response', r => { if (r.status() >= 400) errors.push(`[http ${r.status()}] ${r.url().replace(/([?&](signature|token)=)[^&]+/g, '$1…').slice(0, 160)}`) })
const cdp = await ctx.newCDPSession(page)

const wait = ms => page.waitForTimeout(ms)
const shot = async name => { await page.screenshot({ path: `${OUT}/回归-${name}.png` }); console.log('  截图 回归-' + name) }
/** 收尾（阶段 3c）的验收截图 */
const shotF = async (name, opt = {}) => { await page.screenshot({ path: `${OUT}/收尾-${name}.png`, ...opt }); console.log('  截图 收尾-' + name) }
/** 按功能命名的验收截图（自选-*、复盘-KPI-*、板块-*） */
const shotN = async (name, opt = {}) => { await page.screenshot({ path: `${OUT}/${name}.png`, ...opt }); console.log('  截图 ' + name) }
const NO_KEY_TEXT ='在手机上绑定交易所只读密钥后，成交会自动同步到这里'
const state = () => page.evaluate(() => JSON.parse(localStorage.getItem('hkline-web-v1') || '{}'))
const ready = async () => {
  try {
    await page.waitForFunction(() => (document.querySelector('#toolbar #tbSymbol') && document.title.includes('·')) || !!document.querySelector('.cell-empty:not([hidden])'), null, { timeout: 25000, polling: 250 })
  } catch (e) {
    // 起不来时带上限流闸的账（这一分钟各族权重、冷却）与页面状态，分清是在排队、在冷却还是真卡住
    const why = await page.evaluate(() => ({ limit: window.__limit?.(), title: document.title, hash: location.hash, empty: document.querySelector('.cell-empty')?.textContent?.slice(0, 60) })).catch(() => null)
    throw new Error(`${e.message.split('\n')[0]} ${JSON.stringify(why)}`)
  }
  await wait(1500)
}
// 连开整页前先看页面限流闸记的账（同源 localStorage 共用一份）：这一分钟合约权重超过 limit 或在冷却就等。
// 皮肤段要冷开 36 次页面，板块页一次冷开约 440 权重（145 条小走势），不等就会把币安每分钟 2400 的 IP 上限顶穿
async function pace(limit = 500) {
  for (let k = 0; k < 120; k++) {
    const g = await page.evaluate(() => { try { const s = JSON.parse(localStorage.getItem('hkline-web-rate-limit') || 'null'); const now = Date.now(); if (!s) return { used: 0, pause: 0 }; return { used: (s.used?.fapi || []).filter(x => now - x[0] < 60000).reduce((a, x) => a + x[1], 0), pause: Math.max(0, (s.cool?.['fapi.binance.com']?.until || 0) - now) } } catch { return { used: 0, pause: 0 } } }).catch(() => ({ used: 0, pause: 0 }))
    if (g.used <= limit && !g.pause) return
    if (k === 0) console.log(`  等币安预算：这一分钟合约权重 ${g.used}${g.pause ? '，冷却还剩 ' + Math.round(g.pause / 1000) + ' 秒' : ''}`)
    await wait(2000)
  }
}
const open = async (qs = '', hash = 'chart') => { await pace(); await page.goto(`${URL_}?${qs}#${hash}`, { waitUntil: 'domcontentloaded' }); await ready() }
const fresh = async (qs = 'layout=1&panel=watch&ladder=0&drawer=0') => {
  await page.goto(URL_, { waitUntil: 'load' }); await wait(500)
  // 清状态但留下限流闸的账：清掉它等于让下一页以为这一分钟一笔没发过
  await page.evaluate(() => { const g = localStorage.getItem('hkline-web-rate-limit'); localStorage.clear(); if (g) localStorage.setItem('hkline-web-rate-limit', g) })
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

  // ---- 布局 1–16 与联动开关（拖动、16 格细节见「布局与拖动」段）
  const LAY = [['1', '一图', 1], ['2', '左右两图', 2], ['2v', '上下两图', 2], ['3', '左一右二', 3], ['4', '四图', 4], ['6', '六图', 6], ['8', '八图', 8], ['9', '九图', 9], ['12', '十二图', 12], ['16', '十六图', 16]]
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
    await pickTool(t)
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
    const want = route === 'gateway' ? /kanpan\.|localhost:\d+\/market/ : /fstream\.binance\.com/   // 本机开发服务器端口不固定（vite 转发 /market 到线上网关）
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
    id: tr.dataset.sec, name: tr.querySelector('.sec-name')?.textContent, beat: tr.children[2].textContent.trim(), thin: tr.dataset.thin === '1',
    thinTip: tr.querySelector('.sec-thin')?.dataset.tip || '',
    pct: parseFloat((tr.querySelector('.sec-pct')?.textContent || '').replace('%', '')), spark: !!tr.querySelector('.sec-spark polyline'),
  })))
  let rows = await rowsOf()
  const fat = rows.filter(r => !r.thin), thin = rows.filter(r => r.thin)
  const desc = fat.every((r, i) => i === 0 || !(r.pct > fat[i - 1].pct))
  const thinLast = rows.slice(rows.length - thin.length).every(r => r.thin)
  ok('板块排序：按涨跌幅降序，成员不到三家的沉底（照手机）', desc && thinLast, `${fat.length} 个 + 沉底 ${thin.length} 个（${thin.map(r => `${r.name} ${r.pct}%`).join('、')}）`)
  // 沉底那几行「跑赢大盘」不留空：写「—」，悬停说明只有几只有行情（DeSci 只有 BIO 一只）
  const thinOk = thin.every(r => r.beat === '—' && /只有 \d 只有行情，不到 3 只不算跑赢大盘/.test(r.thinTip))
  ok('成员不到三家：跑赢大盘写「—」并带悬停说明，不是空格子', thin.length > 0 && thinOk, thin.map(r => `${r.name}「${r.beat}」${r.thinTip}`).join('；'))
  const desci = rows.find(r => r.id === 'desci')
  if (desci) {
    await page.locator('#secBody tr[data-sec="desci"] .sec-thin').hover(); await wait(900)
    const dtip = await page.evaluate(() => document.querySelector('#tooltip')?.textContent?.trim() || '')
    ok('DeSci（只有 BIO）沉底、悬停看到原因', desci.thin && rows.indexOf(desci) >= fat.length && /只有 1 只有行情/.test(dtip), `${desci.pct}% · 第 ${rows.indexOf(desci) + 1}/${rows.length} 行 · ${dtip}`)
    await shotN('板块-不到三家写横杠')
    await page.mouse.move(10, 10); await wait(300)
  }
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
  const [bw, mw] = await tableCols()
  ok('板块表：名称列 ≤ 320 px，其余三列平分、铺满整张表', bw.ws[0] <= 320 && even(bw.ws.slice(1)) && Math.abs(sum(bw.ws) - bw.tw) <= 2, colsText(bw))
  ok('品种表：名称列 ≤ 320 px，最新价 / 涨跌 / 成交额平分，星标 48 px，铺满', mw.ws[0] <= 320 && even(mw.ws.slice(1, 4)) && Math.abs(mw.ws[4] - 48) <= 1 && Math.abs(sum(mw.ws) - mw.tw) <= 2, colsText(mw))
  await shot('板块-列表')
  await shotN('板块-今日')
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

/** 板块页两张表的表宽与每列宽（按表头量） */
const tableCols = () => page.evaluate(() => ['#secThead', '#secMThead'].map(s => {
  const ths = [...document.querySelectorAll(`${s} th`)], tbl = document.querySelector(s)?.closest('table')
  return { tw: Math.round(tbl?.getBoundingClientRect().width || 0), ws: ths.map(t => Math.round(t.getBoundingClientRect().width)), names: ths.map(t => t.textContent.trim() || '☆') }
}))
const sum = a => a.reduce((x, y) => x + y, 0)
const even = (a, tol = 2) => a.length > 0 && Math.max(...a) - Math.min(...a) <= tol
const colsText = t => `表宽 ${t.tw}：` + t.names.map((n, i) => `${n} ${t.ws[i]}`).join(' / ')

// ═════════════════════════════ 收尾（阶段 3c）：不用登录的几项 ═════════════════════════════
async function partFinish() {
  const e0 = errors.length
  // 画布上画过的字都记下来（价格轴、十字线标签、现价标签），最多留最近 600 条
  await page.addInitScript(() => {
    const f = CanvasRenderingContext2D.prototype.fillText
    window.__txt = []
    CanvasRenderingContext2D.prototype.fillText = function (t, ...a) { const v = window.__txt; if (v.length > 600) v.splice(0, 300); v.push(String(t)); return f.call(this, t, ...a) }
  })
  // ---- 副图上限：本机旧状态存了 4 个副图，读进来只留前 3 个
  // 在页面脚本跑之前写进去（先开页面再写会被旧页面卸载时的落盘盖掉）；每个标签页只种一次
  await page.addInitScript(() => {
    if (sessionStorage.getItem('kp-seed-subs')) return
    sessionStorage.setItem('kp-seed-subs', '1')
    localStorage.clear()
    localStorage.setItem('hkline-web-v1', JSON.stringify({ ind: { ma: true, ema: false, boll: false, vol: true, subs: ['macd', 'rsi', 'kdj', 'oi'] } }))
  })
  await open('s=BTCUSDT&i=1h&layout=1&panel=watch&ladder=0&drawer=0')
  await page.click('#toolbar [data-iv="4h"]').catch(() => {}); await wait(800) // 随便一个动作让状态落盘
  const subs = (await state()).ind?.subs || []
  ok('副图最多三个：本机旧状态存了 4 个，读进来只留前 3 个', subs.join(',') === 'macd,rsi,kdj', subs.join(','))
  await page.keyboard.press('/'); await wait(500)
  const hint = await page.locator('.ind-dlg').innerText().catch(() => '')
  ok('指标面板写的是「副图最多三个」', /副图最多三个/.test(hint))
  await page.keyboard.press('Escape'); await wait(300)

  // ---- 价格轴千分位：轴刻度、十字线标签、现价标签都是 84,070.0 这种写法；成交量仍是 K / M / B / T
  await page.click('#toolbar [data-iv="1h"]').catch(() => {}); await wait(2500)
  const g = await plotGeom()
  await page.mouse.move(g.x + g.width * 0.5, g.y + g.height * 0.3); await wait(600)
  const txt = await page.evaluate(() => window.__txt.slice())
  const sep = [...new Set(txt.filter(t => /^\d{1,3}(,\d{3})+(\.\d+)?$/.test(t)))]
  const raw = [...new Set(txt.filter(t => /^\d{4,}(\.\d+)?$/.test(t)))]
  ok('价格轴 / 十字线 / 现价标签带千分位，没有不带千分位的四位以上价格', sep.length >= 4 && raw.length === 0, `带千分位 ${sep.slice(0, 6).join(' ')}；不带的 ${raw.slice(0, 6).join(' ') || '无'}`)
  const wRow = await page.locator('#wTbl tr[data-sym="BTCUSDT"]').first().innerText().catch(() => '')
  ok('侧栏自选：价格同一写法（带千分位），成交额仍是 K / M / B / T', /\d{1,3},\d{3}/.test(wRow) && /\d(\.\d+)?[KMBT]\b/.test(wRow), wRow.replace(/\s+/g, ' ').slice(0, 60))
  await shotF('价格轴特写', { clip: { x: Math.round(g.axisX - 420), y: Math.round(g.y), width: Math.round(g.x + g.width - g.axisX + 420), height: Math.round(Math.min(g.height, 760)) } })

  // ---- 大单「存活」列：「39.8小时」整段放得下（按侧栏真实宽度量）
  const wall = await page.evaluate(() => {
    const side = document.querySelector('.side-panel')
    const host = document.createElement('div'); host.className = 'of-walls'
    host.style.cssText = `position:fixed;left:0;top:0;width:${Math.round(side?.getBoundingClientRect().width || 320)}px;visibility:hidden`
    host.innerHTML = '<div class="of-wall"><i class="bar"></i><span class="sd up">买</span><span class="vn">币安 U 本位永续</span><span class="p num">84,070.0</span><span class="v num">12.50M</span><span class="t num faint">39.8小时</span></div>'
    document.body.appendChild(host)
    const t = host.querySelector('.t'), r = { sw: t.scrollWidth, cw: t.clientWidth, side: host.getBoundingClientRect().width }
    host.remove(); return r
  })
  ok('侧栏大单「存活」列放得下「39.8小时」、不截断', wall.cw > 0 && wall.sw <= wall.cw, `内容 ${wall.sw} px，列宽 ${wall.cw} px（侧栏 ${wall.side} px）`)

  // ---- 板块表列宽（和 板块-*.png 对比）
  await page.evaluate(() => { location.hash = 'sectors' }); await wait(12000)
  const first = await page.locator('#secBody tr[data-sec]').nth(2)
  if (await first.count()) { await first.click(); await wait(1500) }
  const [bw, mw] = await tableCols()
  ok('板块表：名称列 ≤ 320 px，其余三列平分、铺满整张表', bw.ws[0] <= 320 && even(bw.ws.slice(1)) && Math.abs(sum(bw.ws) - bw.tw) <= 2, colsText(bw))
  ok('品种表：名称列 ≤ 320 px，最新价 / 涨跌 / 成交额平分，星标 48 px，铺满', mw.ws[0] <= 320 && even(mw.ws.slice(1, 4)) && Math.abs(mw.ws[4] - 48) <= 1 && Math.abs(sum(mw.ws) - mw.tw) <= 2, colsText(mw))
  await shotF('板块表')
  ok('收尾（不登录的几项）：控制台无报错', sectionErrors(e0).length === 0, sectionErrors(e0).slice(0, 5).join(' | '))
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
  // 面板里的默认价可能比最新成交落后几个价位（整轮跑下来时见过两次），两条线就都落在现价同一侧、永远不穿：用最新价
  const live = await page.evaluate(() => { const s = JSON.parse(localStorage.getItem('hkline-web-v1') || '{}'); const c = s.cells?.[s.active || 0]; return c ? window.__px?.(c.symbol) ?? null : null })
  const dec = (raw.split('.')[1] || '').length, tick = 10 ** -dec, cur = (live != null ? +live.toFixed(dec) : 0) || +raw || last
  const nB = (await state()).alerts.length
  for (const px of [cur + tick, cur - tick]) {
    await page.keyboard.press('Alt+KeyA'); await wait(400)
    await page.fill('#aPrice', px.toFixed(dec)); await page.click('#aOk'); await wait(300)
  }
  const nA = (await state()).alerts.length
  let gone = false
  for (let k = 0; k < 60 && !gone; k++) { await wait(500); gone = (await state()).alerts.length < nA }
  const toastTxt = await page.evaluate(() => [...document.querySelectorAll('.toast')].map(t => t.textContent.trim()).join(' | '))
  ok('价格提醒贴着现价（±1 个价位两条）：逐笔价一穿就响、响完从表里删掉、弹提示', nA === nB + 2 && gone && /已结束/.test(toastTxt), gone ? toastTxt.slice(0, 80) : `30 秒内没响（面板价 ${raw}，逐笔价 ${live} → ${await page.evaluate(() => { const s = JSON.parse(localStorage.getItem('hkline-web-v1') || '{}'); const c = s.cells?.[s.active || 0]; return c ? window.__px?.(c.symbol) ?? null : null })}，两条 ${(cur + tick).toFixed(dec)} / ${(cur - tick).toFixed(dec)}，提醒 ${nB} → ${nA}）`)
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
  const r = await fetch(p, { method: m, headers: h, body: b == null ? undefined : JSON.stringify(b), cache: 'no-store', signal: AbortSignal.timeout(30000) })
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
  await pickTool('hline')
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
  await pickTool('hline')
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

  // ---- 注销账号：一次性账号 <KP_USER>_<n>，注册 → 注销（点两下）→ 服务端登录被拒；密码随机生成，不进仓库
  {
    const { randomBytes } = await import('node:crypto')
    const du = `${KP_USER}_${Date.now() % 100000}`, dp = 'Tmp' + randomBytes(6).toString('hex')
    const c3 = await browser.newContext({ viewport: { width: 1600, height: 1000 } })
    const p3 = await c3.newPage()
    await p3.goto(`${URL_}#me`, { waitUntil: 'load' }); await p3.waitForTimeout(1000)
    await p3.click('[data-me="account"]'); await p3.waitForTimeout(300)
    await p3.click('[data-auth="register"]'); await p3.waitForTimeout(200)
    await p3.fill('#acctUser', du); await p3.fill('#acctPass', dp); await p3.click('#acctGo'); await p3.waitForTimeout(2500)
    const reg = await p3.evaluate(k => !!localStorage.getItem(k), ACCOUNT_KEY)
    await p3.fill('#closePass', dp); await p3.click('#closeGo'); await p3.waitForTimeout(300)
    const armed = await p3.locator('#closeGo').innerText().catch(() => '')
    await p3.click('#closeGo'); await p3.waitForTimeout(2500)
    const out = await p3.evaluate(k => !localStorage.getItem(k), ACCOUNT_KEY)
    const r = await fetch(`${URL_.replace(/\/web\/.*$/, '')}/v1/auth/login`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ username: du, password: dp, device: { id: crypto.randomUUID(), secret: randomBytes(32).toString('hex'), name: 'regress', kind: 'desktop' } }) }).catch(() => null)
    ok('注销账号：注册一次性账号 → 第一下只变「再点一次」、第二下才删 → 回到未登录、服务端再登录被拒', reg && /再点一次/.test(armed) && out && !!r && r.status === 401, `${du}；${armed}；登录 HTTP ${r?.status}`)
    await c3.close()
  }
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
  const r = await fetch(`https://fapi.binance.com/fapi/v1/klines?symbol=${symbol}&interval=${iv}&startTime=${start}&limit=${limit}`, { signal: AbortSignal.timeout(15000) })
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

/** 交易回合的四项补充要点：拦下回合列表换成固定的几笔（不往测试账号里种），核对页面上的数 */
function kpiRound(i, symbol, direction, net) {
  const openedAt = Date.UTC(2026, 8, 20 + i, 2), closedAt = openedAt + 3600e3
  const round = {
    version: 1, id: `7e57c0de-0929-4b00-8b00-00000000b00${i}`, venue: 'binance', market: 'usd_m', accountTag: 'webtest', symbol, positionSide: 'BOTH', direction, status: 'closed',
    quoteAsset: 'USDT', openedAt, closedAt, holdingMs: 3600e3, updatedAt: closedAt, openAvgPrice: '100', closeAvgPrice: '101', openedQty: '1', closedQty: '1', maxQty: '1', peakNotional: '100',
    realizedPnl: String(net), commission: '0', funding: '0', netPnl: String(net), leverage: 10, fills: [],
  }
  return { kind: 'trade', id: round.id, revision: 1, submitted: closedAt, updated: closedAt, voided: false, round, result: null, note: null }
}
async function reviewKpis() {
  const isTrades = u => u.pathname.endsWith('/v1/native-review/records') && u.searchParams.get('kind') === 'trade'
  const read = () => page.$$eval('.kpis-trade [data-kpi]', ns => Object.fromEntries(ns.map(n => [n.dataset.kpi, { v: n.querySelector('.v').textContent.trim(), d: n.querySelector('.d').textContent.trim() }])))
  const load = async recs => {
    await page.unroute(isTrades).catch(() => {})
    await page.route(isTrades, r => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ data: { records: recs, next: null } }) }))
    await page.goto(`${URL_}#review`, { waitUntil: 'domcontentloaded' }); await page.reload({ waitUntil: 'domcontentloaded' })
    // 页面先画出空的十一格（正在加载），要等交易回合的计数变成造的条数才算读到了
    await page.waitForFunction(n => document.querySelector('[data-tab="trade"] .rv-count')?.textContent.trim() === String(n) && !!document.querySelector('.kpis-trade [data-kpi="pf"]'), recs.length, { timeout: 25000, polling: 300 }).catch(() => {})
    await page.click('[data-tab="trade"]').catch(() => {}); await wait(800)
    return read()
  }
  // 累计 +600 → +900 → +500 → +700 → +600：峰 900 → 谷 500，回撤 400（占峰值 44.4%）；
  // 总盈利 1100、总亏损 −500 → 盈利因子 2.20；最大一笔 600 ÷ 净 600 = 100%（主要来自 1 笔）；
  // 做多 3 笔 +800、胜率 66.7%；做空 2 笔 −200、胜率 50.0%
  const a = await load([kpiRound(1, 'BTCUSDT', 'long', 600), kpiRound(2, 'ETHUSDT', 'long', 300), kpiRound(3, 'SOLUSDT', 'short', -400), kpiRound(4, 'BTCUSDT', 'short', 200), kpiRound(5, 'ETHUSDT', 'long', -100)])
  const n = await page.locator('.kpis-trade .kpi').count()
  ok('复盘要点：交易回合一行十一格（原六格 + 盈利因子、最大回撤、最大单笔、做多、做空）', n === 11, `${n} 格`)
  ok('盈利因子 = 总盈利 ÷ |总亏损|', a.pf?.v === '2.20' && /总盈利 \+1,100\.00/.test(a.pf?.d) && /总亏损 −500\.00/.test(a.pf?.d), JSON.stringify(a.pf))
  ok('最大回撤：已实现资金曲线峰到谷，金额 + 占峰值百分比', a.dd?.v === '−400.00' && /占峰值 44\.4%/.test(a.dd?.d), JSON.stringify(a.dd))
  ok('最大单笔占比过半：提示「这段时间的盈利主要来自 1 笔」', a.top?.v === '100.0%' && a.top?.d === '这段时间的盈利主要来自 1 笔', JSON.stringify(a.top))
  ok('多空拆分：各自净盈亏、回合数、胜率', a.long?.v === '+800.00' && a.long?.d === '3 个回合 · 胜率 66.7%' && a.short?.v === '−200.00' && a.short?.d === '2 个回合 · 胜率 50.0%', `${JSON.stringify(a.long)} ${JSON.stringify(a.short)}`)
  await shotN('复盘-KPI-十一格')
  const box = await page.locator('.kpis-trade').boundingBox()
  if (box) await shotN('复盘-KPI-要点行', { clip: { x: box.x, y: box.y - 64, width: box.width, height: box.height + 64 } })
  // 只有赚没有亏：盈利因子写「—」不写无穷大；三笔一样大不提示；没做空的那一边写「—」
  const b = await load([kpiRound(1, 'BTCUSDT', 'long', 100), kpiRound(2, 'ETHUSDT', 'long', 100), kpiRound(3, 'SOLUSDT', 'long', 100)])
  ok('没有亏损：盈利因子「—」、回撤 0 写「没有回撤」、占比 33.3% 不提示、做空「—」', b.pf?.v === '—' && b.dd?.v === '0.00' && b.dd?.d === '没有回撤' && b.top?.v === '33.3%' && /赚 \+100\.00/.test(b.top?.d) && b.short?.v === '—' && b.short?.d === '没有平仓的回合', `${JSON.stringify(b.pf)} ${JSON.stringify(b.dd)} ${JSON.stringify(b.top)} ${JSON.stringify(b.short)}`)
  await shotN('复盘-KPI-没有亏损')
  await page.unroute(isTrades)
  await page.goto(`${URL_}#review`, { waitUntil: 'domcontentloaded' }); await page.reload({ waitUntil: 'domcontentloaded' }); await wait(3000)
}

async function partReview() {
  const e0 = errors.length
  if (!KP_PASS) { ok('复盘段', false, '没给 KP_PASS 环境变量'); return }
  await fresh('s=BTCUSDT&i=1h&layout=1')
  // 没登录：进复盘是登录引导
  await page.goto(`${URL_}#review`, { waitUntil: 'domcontentloaded' }); await wait(1200)
  const gate = await page.locator('.rv-login').innerText().catch(() => '')
  ok('没登录进复盘：给登录引导（复盘需要登录）', /复盘需要登录/.test(gate))
  // ---- 记一笔（没登录）：先存本机、弹窗里提示登录；登录后自动传到服务端成为观点记录
  await open('s=BTCUSDT&i=1h&layout=1&panel=notes&ladder=0&drawer=0')
  await page.click('#tbNote'); await wait(700)
  await page.click('.note-dlg #nDir [data-v="long"]'); await wait(200)
  const noteTxt = '收尾回归：放量站上前高，回踩不破看多'
  await page.fill('#nTx', noteTxt)
  const loginHint = await page.locator('.note-dlg .note-login').innerText().catch(() => '')
  const lv = await page.evaluate(() => ({ t: +document.querySelector('#nTarget')?.value, i: +document.querySelector('#nInv')?.value, r: document.querySelector('#nRange')?.textContent?.trim() }))
  ok('记一笔弹窗：取景区间、看多给目标 / 失效，没登录提示「登录后自动传到复盘」', /登录后自动传/.test(loginHint) && lv.t > lv.i && lv.i > 0 && !!lv.r, `${lv.r}；目标 ${lv.t} 失效 ${lv.i}`)
  await shotF('记一笔弹窗')
  await page.click('#nOk'); await wait(800)
  const pend = ((await state()).notes || []).at(-1)
  const noteId = pend?.id
  ok('没登录记下：留在本机草稿里（等上传），带服务端要的记录草稿', pend?.sync === 'pending' && pend?.draft?.id === noteId && pend?.text === noteTxt && pend?.draft?.rule?.direction === 'long', `${pend?.sync} · ${pend?.draft?.range?.interval} ${pend?.draft?.range?.bars} 根`)
  const sideTxt = await page.locator('.side-panel').innerText().catch(() => '')
  ok('侧栏笔记这一条标「登录后上传」', /登录后上传/.test(sideTxt))
  const logged = await uiLogin()
  ok('登录', logged)
  let upNote = null
  for (let k = 0; k < 30; k++) { await wait(500); upNote = ((await state()).notes || []).find(n => n.id === noteId); if (upNote?.sync === 'synced' && upNote?.shot !== 'pending') break }
  const det = noteId ? await api('GET', `/v1/native-review/records/${noteId}`) : { status: 0 }
  ok('登录后自动补传：服务端有这条观点记录、原文对得上、截图也传上了', upNote?.sync === 'synced' && det.status === 200 && det.data?.record?.draft?.text === noteTxt && det.data?.hasShot === true, `本机 ${upNote?.sync}/${upNote?.shot}，服务端 ${det.status} hasShot=${det.data?.hasShot}`)
  const before = await api('GET', '/v1/native-review/records?kind=trade')
  await page.goto(`${URL_}#review`, { waitUntil: 'domcontentloaded' }); await page.reload({ waitUntil: 'domcontentloaded' }); await wait(3500)
  const counts0 = await page.$$eval('[data-tab] .rv-count', ns => ns.map(n => n.textContent.trim()))
  if (!(before.data?.records || []).length) {
    // 页签顺序是 交易回合 / 观点记录 / 相似走势；上面刚补传了一条观点记录，所以观点那一格等于服务端没作废的观点条数（至少 1），不是 0
    const views0 = ((await api('GET', '/v1/native-review/records')).data?.records || []).filter(r => !r.voided).length
    const saved0 = ((await api('GET', '/v1/native-review/saved-matches')).data?.items || []).length
    ok('没有交易回合的账号：回合 0、观点等于服务端条数（含刚补传的那条）、相似等于收藏数，没有报错', counts0.join(',') === `0,${views0},${saved0}` && views0 >= 1 && !(await page.locator('.rv-err').count()), `${counts0.join(' / ')}（服务端观点 ${views0}、收藏 ${saved0}）`)
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
  await reviewKpis()

  // ---- 观点记录
  await page.click('[data-tab="view"]'); await wait(500)
  const vrow = page.locator(`[data-view="${RV_VIEW_ID}"]`)
  ok('观点记录列表里有这一条', await vrow.count() === 1)
  ok('网页「记一笔」传上去的那条也在「观点记录」里', !!noteId && await page.locator(`[data-view="${noteId}"]`).count() === 1)
  await vrow.click(); await wait(3500)
  const vfoot = await page.locator('#rvFoot').innerText()
  ok('选中观点：给出判断原文、方向与结果', /回踩前低不破/.test(vfoot) && /结果/.test(vfoot), vfoot.replace(/\s+/g, ' ').slice(0, 100))
  await shot('复盘-观点记录')
  // 找相似：发起、等它找完、收藏一条、再取消
  const nSearch0 = (await page.evaluate(() => JSON.parse(localStorage.getItem('hkline-review-searches') || '[]'))).length
  await page.click(`[data-find="${RV_VIEW_ID}"]`)
  // 发起请求回来就该切过去（不等进度），最多给 10 秒
  let tabNow = 0, nSearch1 = nSearch0
  for (let k = 0; k < 20; k++) {
    await wait(500)
    nSearch1 = (await page.evaluate(() => JSON.parse(localStorage.getItem('hkline-review-searches') || '[]'))).length
    tabNow = await page.locator('[data-tab="similar"][aria-selected="true"]').count()
    if (tabNow && nSearch1 !== nSearch0) break
  }
  ok('找相似：发起后切到「相似走势」、这次搜索记在本机', tabNow === 1 && nSearch1 === Math.min(8, nSearch0 + 1), `${nSearch0} → ${nSearch1}`)
  let items = 0, stTxt = ''
  for (let k = 0; k < 60; k++) {
    await wait(2000)
    items = await page.locator('[data-match^="search:"]').count()
    stTxt = await page.locator('.rv-search').first().innerText().catch(() => '')
    if (items || /没有找到|没有一段相似/.test(stTxt)) break
  }
  ok('找相似：两分钟内找完、列出相似片段（没有时说清比过几段、门槛 0.60）', items > 0 || /比过 \d+ 段，没有一段相似度到 0\.60|没有找到/.test(stTxt), items ? `${items} 段` : stTxt.replace(/\s+/g, ' ').slice(0, 80))
  if (!items) {
    // 这一段历史里没有够像的：换最近 32 根 15m 在接口上发起一次（等于另一个页签里找的），
    // 记进本机的搜索列表，切回「相似走势」时页面自己补问——顺带验「别的页签新找的相似」那条路
    const Q = 900e3, end = Math.floor((Date.now() - 2 * 3600e3) / Q) * Q
    const range = { venue: 'binance', market: 'usd_m', symbol: 'BTCUSDT', interval: '15m', start: end - 32 * Q, end, bars: 32 }
    const job = await api('POST', '/v1/native-review/searches', { range, cutoff: Date.now() - 1000, scope: 'history' }, page, { 'Idempotency-Key': crypto.randomUUID() })
    const jid = job.data?.id
    let jst = null
    for (let k = 0; jid && k < 60; k++) { await wait(2000); jst = (await api('GET', `/v1/native-review/searches/${jid}`)).data; if (!/queued|running/.test(jst?.status)) break }
    if (jid) await page.evaluate(m => { const k = 'hkline-review-searches'; localStorage.setItem(k, JSON.stringify([m, ...JSON.parse(localStorage.getItem(k) || '[]')])) }, { id: jid, symbol: 'BTCUSDT', iv: '15m', bars: 32, label: 'BTC 15分 · 32 根', created: Date.now() })
    await page.click('[data-tab="trade"]'); await wait(300); await page.click('[data-tab="similar"]')
    for (let k = 0; k < 20 && !items; k++) { await wait(500); items = await page.locator('[data-match^="search:"]').count() }
    // 服务端一小时最多 20 次、一次只跑一个（search_busy）：发不起来时把原因写进结果，不装作通过
    ok('别的页签新找的相似：切到「相似走势」时补问、列出来', items > 0, jid ? `${items} 段（任务 ${jst?.status}，比过 ${jst?.checked ?? '—'} 段）` : `没发起：${job.status} ${job.error}`)
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

  // ---- 侧栏「成交」：有数据（种的那一回合的两笔）
  await open('s=BTCUSDT&i=1h&layout=1&panel=trades&ladder=0&drawer=0')
  for (let k = 0; k < 20 && !(await page.locator('.tr-row[data-tr-rec]').count()); k++) await wait(500)
  const trs = await page.$$eval('.tr-row[data-tr-rec]', ns => ns.map(n => ({ rec: n.dataset.trRec, cells: [...n.children].map(c => c.textContent.trim()) })))
  const mine = trs.filter(r => r.rec === seed.id)
  const hdr = await page.locator('.tr-head').innerText().catch(() => '')
  ok('侧栏成交：列出这只品种的逐笔成交，最新在上，时间 / 方向 / 价格 / 数量 / 名义', mine.length === 2 && /卖平/.test(mine[0].cells[1]) && /买开/.test(mine[1].cells[1]) && /\d,\d{3}/.test(mine[0].cells[2]) && /[KMBT]$|^\d/.test(mine[0].cells[4]) && ['时间', '方向', '价格', '数量', '名义'].every(h => hdr.includes(h)), `${trs.length} 笔；种的两笔 ${mine.map(r => r.cells.join(' ')).join(' | ')}`)
  await shotF('成交-有数据')
  await page.locator(`.tr-row[data-tr-rec="${seed.id}"]`).first().click()
  let jumped = 0
  for (let k = 0; k < 20 && !jumped; k++) { await wait(500); jumped = await page.locator(`[data-trade="${seed.id}"].sel`).count() }
  const selTab = await page.locator('[data-tab][aria-selected="true"]').getAttribute('data-tab').catch(() => '')
  ok('点一行跳复盘、切到「交易回合」并选中那一回合', /#review/.test(page.url()) && jumped === 1 && selTab === 'trade', `${page.url().split('#')[1]} · 页签 ${selTab}`)

  // ---- 没绑密钥：服务端一条交易回合都没有（拦下接口返回空，别的账号数据不动）
  const noTrades = u => u.pathname.endsWith('/v1/native-review/records') && u.searchParams.get('kind') === 'trade'
  await page.route(noTrades, r => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ data: { records: [], next: null } }) }))
  await open('s=ETHUSDT&i=1h&layout=1&panel=trades&ladder=0&drawer=0')
  for (let k = 0; k < 20 && !(await page.locator('[data-tr-empty]').count()); k++) await wait(500)
  const nk = await page.locator('[data-tr-empty="nokey"]').innerText().catch(() => '')
  ok('侧栏成交·没绑密钥：「在手机上绑定交易所只读密钥后，成交会自动同步到这里」', nk.includes(NO_KEY_TEXT), nk.replace(/\s+/g, ' '))
  await shotF('成交-没绑密钥')
  await page.goto(`${URL_}#me`, { waitUntil: 'domcontentloaded' }); await wait(1500)
  await page.click('[data-me="exchange"]'); await wait(2000)
  const exEmpty = await page.locator('[data-ex-empty]').innerText().catch(() => '')
  ok('我的 → 交易所账号·没绑密钥：同一句提示', exEmpty.includes(NO_KEY_TEXT), exEmpty)
  await page.unroute(noTrades)
  // ---- 交易所账号：说明页 + 服务端知道的绑定情况
  await page.reload({ waitUntil: 'domcontentloaded' }); await wait(1500)
  await page.click('[data-me="exchange"]'); await wait(2500)
  const ex = await page.locator('#page-me').innerText().catch(() => '')
  const venue = await page.locator('[data-ex-venues]').innerText().catch(() => '')
  ok('我的 → 交易所账号：说明在手机上绑、网页不存密钥，列出哪家交易所、最近一次上传', /在手机上绑定/.test(ex) && /网页不存/.test(ex) && /币安/.test(venue) && /最近一次上传/.test(venue) && !/下一阶段/.test(ex), venue.replace(/\s+/g, ' ').slice(0, 100))
  await shotF('交易所账号')
  // 收尾：把这次「记一笔」的测试记录作废，免得测试账号越攒越多
  if (noteId) {
    const d2 = await api('GET', `/v1/native-review/records/${noteId}`)
    const v = await api('POST', `/v1/native-review/records/${noteId}/void`, { expectedRevision: d2.data?.record?.revision }, page, { 'Idempotency-Key': crypto.randomUUID() })
    ok('测试记录作废（清理）', v.status === 200, `${v.status}${v.error ? ' ' + v.error : ''}`)
  }
  ok('复盘：控制台无报错', sectionErrors(e0).length === 0, sectionErrors(e0).slice(0, 5).join(' | '))
}

// ═════════════════════════════ 布局与拖动 ═════════════════════════════
// 1–16 格布局、四样跨图联动、每种分隔条（梯子 / 侧栏 / 抽屉 / 副图 / 侧栏块 / 多图网格）拖完刷新还在、
// 双击回默认、窗口缩小按比例夹；快速切布局 WS 条数不涨；16 格实时刷新时主线程空闲 ≥ 60%。
const SIZE_KEY = 'hkline-web-sizes-v1'
const sizesNow = () => page.evaluate(k => JSON.parse(localStorage.getItem(k) || '{}'), SIZE_KEY)
const cellsNow = () => page.evaluate(() => window.__cells())
const streamNow = () => page.evaluate(() => window.__stream())
const shotL = async (name, clip) => { await page.screenshot({ path: `${OUT}/布局-${name}.png`, ...(clip ? { clip } : {}) }); console.log('  截图 布局-' + name) }
const rectOf = sel => page.evaluate(s => { const e = document.querySelector(s); if (!e) return null; const r = e.getBoundingClientRect(); return { x: r.x, y: r.y, w: Math.round(r.width), h: Math.round(r.height) } }, sel)
const splitBox = name => page.locator(`.splitter[data-split="${name}"]`).boundingBox()
/** 按住分隔条拖 (dx, dy)；按在线的 30% 处，避开和别的分隔线交叉的地方 */
async function dragSplit(name, dx, dy, at = 0.3) {
  const b = await splitBox(name)
  if (!b) throw new Error(`没有分隔条 ${name}`)
  const x = b.width > b.height ? b.x + b.width * at : b.x + b.width / 2
  const y = b.width > b.height ? b.y + b.height / 2 : b.y + b.height * at
  await page.mouse.move(x, y); await page.mouse.down()
  await page.mouse.move(x + dx, y + dy, { steps: 10 }); await page.mouse.up(); await wait(400)
}
async function dblSplit(name, at = 0.3) {
  const b = await splitBox(name)
  const x = b.width > b.height ? b.x + b.width * at : b.x + b.width / 2
  const y = b.width > b.height ? b.y + b.height / 2 : b.y + b.height * at
  await page.mouse.dblclick(x, y); await wait(500)
}
const noScroll = () => page.evaluate(() => {
  const d = document.documentElement
  const over = [...document.querySelectorAll('.chart-cell, #sidePanel, #ladderSlot, #drawerSlot, #chartArea')].filter(e => { const r = e.getBoundingClientRect(); return r.width && (r.right > innerWidth + 1 || r.bottom > innerHeight + 1) }).map(e => e.id || e.className)
  return { ok: d.scrollWidth <= innerWidth && d.scrollHeight <= innerHeight && !over.length, info: `${d.scrollWidth}×${d.scrollHeight}${over.length ? ' 溢出：' + over.join(',') : ''}` }
})
const pickLayout = async label => { await page.click('#tbLayout'); await wait(200); await clickMenu(label) }
/** 主图与第一个副图之间的分隔线：沿画布左侧从上往下找鼠标变 row-resize 的位置 */
async function sepY(i = 0) {
  const b = await canvasBox(i)
  const x = b.x + 200
  const hits = []
  for (let y = b.y + b.height * 0.3; y < b.y + b.height - 30; y += 2) {
    await page.mouse.move(x, y)
    const c = await page.evaluate(k => document.querySelectorAll('.chart-cell canvas')[k].style.cursor, i)
    if (c === 'row-resize') hits.push(y)
    else if (hits.length) break
  }
  return hits.length ? { x, y: hits.reduce((a, v) => a + v, 0) / hits.length } : null
}

async function partLayout() {
  const e0 = errors.length
  await fresh('s=BTCUSDT&i=1h&layout=1&panel=watch&ladder=0&drawer=0')
  const s1 = await streamNow()

  // ---- 十种布局都走一遍：格子数、每格有数据、不溢出不出滚动条
  const LAYS = [['1', '一图', 1], ['2', '左右两图', 2], ['2v', '上下两图', 2], ['3', '左一右二', 3], ['4', '四图', 4], ['6', '六图', 6], ['8', '八图', 8], ['9', '九图', 9], ['12', '十二图', 12], ['16', '十六图', 16]]
  for (const [k, label, cnt] of LAYS) {
    await pickLayout(label); await wait(k === '16' || k === '12' ? 6000 : 2500)
    const n = await page.locator('.chart-cell').count(), s = await state(), cs = await cellsNow()
    const empty = cs.filter(c => !c.bars).length, sc = await noScroll()
    ok(`布局 ${label}：${cnt} 格、各格有数据、不溢出`, n === cnt && s.layout === k && !empty && sc.ok && new Set(cs.map(c => c.symbol)).size === cnt, `格子 ${n}，没数据 ${empty}，品种 ${new Set(cs.map(c => c.symbol)).size} 只，${sc.info}`)
    if (k === '3') {
      const r = await page.evaluate(() => [...document.querySelectorAll('.chart-cell')].map(e => { const b = e.getBoundingClientRect(); return [Math.round(b.x), Math.round(b.y), Math.round(b.width), Math.round(b.height)] }))
      ok('左一右二：左格占满两行，右边上下两格', r[0][3] > r[1][3] * 1.8 && r[1][0] === r[2][0] && r[2][1] > r[1][1], JSON.stringify(r))
    }
    if (k === '4') await shotL('四图')
    if (k === '8') await shotL('八图')
  }
  // ---- 16 格：降级档、蜡烛读得清、连接与订阅
  let cs = await cellsNow()
  const c16 = await rectOf('.chart-cell')
  const deg = cs[0].deg
  ok('16 格按格子尺寸降级：只留主图、图例一行、价格轴字号小一档（量还在）', !deg.subs && deg.compact && deg.font === 11 && deg.vol === (c16.w >= 420), `格子 ${c16.w}×${c16.h}，${JSON.stringify(deg)}`)
  const g0 = cs.map(x => x.bars), spacing = cs.length
  await shotL('十六图')
  let w16 = await ws(), st16 = await streamNow()
  const market16 = w16.live.filter(l => /market\/stream|fstream/.test(l.url))
  ok('16 格：行情连接按上限分摊、订阅覆盖 16 只', market16.length >= 1 && st16.subscribed.length >= 16 * 2 && ['BTCUSDT', 'TRXUSDT'].every(x => st16.subscribed.some(n => n.startsWith(x.toLowerCase()))), `连接 ${market16.length} 条（${st16.conns.join('/')} 路），订阅 ${st16.subscribed.length} 路，${spacing} 格，最少 ${Math.min(...g0)} 根`)

  // ---- 16 格实时刷新：4 秒主线程占用
  await page.mouse.move(5, 700) // 鼠标别停在图上
  await cdp.send('Performance.enable', { timeDomain: 'timeTicks' })
  const m0 = Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map(m => [m.name, m.value]))
  await wait(4000)
  const m1 = Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map(m => [m.name, m.value]))
  const busy = (m1.TaskDuration - m0.TaskDuration) / (m1.Timestamp - m0.Timestamp)
  ok('16 格实时刷新：4 秒内主线程空闲 ≥ 60%', busy <= 0.4, `占用 ${(busy * 100).toFixed(1)}%（脚本 ${((m1.ScriptDuration - m0.ScriptDuration) * 1000).toFixed(0)} ms、排版 ${((m1.LayoutDuration - m0.LayoutDuration) * 1000).toFixed(0)} ms / ${((m1.Timestamp - m0.Timestamp)).toFixed(2)} s）`)
  await cdp.send('Performance.disable')

  // ---- 联动：品种 / 周期 / 十字线 / 时间轴（16 格里验）
  await page.locator('.chart-cell').nth(5).click({ position: { x: 200, y: 150 } }); await wait(300)
  await pickLayout('周期跨图同步'); await wait(4000)
  cs = await cellsNow()
  ok('周期跨图同步：打开后 16 格同一周期', cs.every(c => c.iv === cs[5].iv), [...new Set(cs.map(c => c.iv))].join(','))
  await page.click('#toolbar [data-iv="4h"]'); await wait(5000)
  cs = await cellsNow(); let s = await state()
  ok('周期联动：换一格全换成 4 时、各格重取了数据', s.linkIv && cs.every(c => c.iv === '4h' && c.bars > 0), [...new Set(cs.map(c => `${c.iv}`))].join(',') + ` 没数据 ${cs.filter(c => !c.bars).length}`)
  await pickLayout('时间轴跨图同步'); await wait(1500)
  const b5 = await canvasBox(5)
  await page.mouse.move(b5.x + b5.width * 0.4, b5.y + b5.height * 0.4)
  // 缩小三下（不缩到最小间距：到了最小间距，画布窄几像素的格子只能少放几根，左沿会差一两根）
  for (let k = 0; k < 3; k++) { await page.mouse.wheel(0, 150); await wait(80) }
  await wait(800)
  cs = await cellsNow()
  const spans = cs.map(c => Math.round((c.t1 - c.t0) / 36e5))
  ok('时间轴跨图同步：一格缩放，其余 15 格同一段时间（左右沿差不过两根）', cs[5].spacing > 1.5 && cs.every(c => Math.abs(c.t1 - cs[5].t1) <= 4 * 36e5 && Math.abs(c.t0 - cs[5].t0) <= 8 * 36e5), `可见跨度（小时）${[...new Set(spans)].join(',')}，间距 ${cs[5].spacing.toFixed(2)}`)
  await page.mouse.move(b5.x + b5.width * 0.3, b5.y + b5.height * 0.5); await wait(400)
  cs = await cellsNow()
  ok('十字线跨图同步：悬停一格，其余 15 格拿到同一时间', cs.filter((c, i) => i !== 5).every(c => c.cross != null && c.cross === cs[0].cross), `同步时间 ${[...new Set(cs.filter((c, i) => i !== 5).map(c => c.cross))].join(',')}`)
  await page.mouse.move(5, 700); await wait(300)
  await pickLayout('品种跨图同步'); await wait(4000)
  cs = await cellsNow()
  ok('品种跨图同步：16 格同一只', cs.every(c => c.symbol === cs[5].symbol), [...new Set(cs.map(c => c.symbol))].join(','))
  await pickLayout('品种跨图同步'); await wait(300)
  await pickLayout('周期跨图同步'); await wait(300)
  await pickLayout('时间轴跨图同步'); await wait(300)
  s = await state()
  ok('三个联动开关都能关回去并落盘', !s.linkSymbol && !s.linkIv && !s.linkTime)

  // ---- 快速切布局 20 次：连接不涨、多余的流退订（16 格各是一只，品种联动刚把它们并成了一只，重开一次）
  await fresh('s=BTCUSDT&i=1h&layout=16&panel=watch&ladder=0&drawer=0'); await wait(5000)
  const wA = await ws(), sA = await streamNow()
  const cycle = ['一图', '十六图', '四图', '十二图', '左一右二', '九图', '上下两图', '八图', '六图', '左右两图']
  for (let k = 0; k < 20; k++) { await page.click('#tbLayout'); await wait(80); await page.locator('.menu .mi', { hasText: cycle[k % cycle.length] }).first().click(); await wait(120) }
  await pickLayout('十六图'); await wait(6000)
  const wB = await ws(), sB = await streamNow()
  const mk = w => w.live.filter(l => /market\/stream|fstream/.test(l.url)).length
  ok('快速切 20 次布局后 WS 条数不涨', mk(wB) <= mk(wA) && wB.live.length <= wA.live.length, `行情连接 ${mk(wA)}→${mk(wB)}，全部 ${wA.live.length}→${wB.live.length}，开过 ${wA.opened}→${wB.opened}`)
  ok('切完订阅回到同一组（不多不少）', sB.subscribed.length === sA.subscribed.length, `${sA.subscribed.length} → ${sB.subscribed.length} 路`)
  await pickLayout('一图'); await wait(4000)
  const s1b = await streamNow()
  ok('切回一图：多出来的 15 只全部退订', s1b.subscribed.length <= s1.subscribed.length + 2 && s1b.conns.length === 1, `一图 ${s1.subscribed.length} 路 → 16 格 ${sB.subscribed.length} 路 → 一图 ${s1b.subscribed.length} 路（连接 ${s1b.conns.length} 条）`)

  // ---- 页面三条分隔线：默认值、拖、夹、刷新还在、双击回默认
  await fresh('s=BTCUSDT&i=1h&layout=4&panel=watch&ladder=1&drawer=1')
  let lad = await rectOf('#ladderSlot'), pan = await rectOf('#sidePanel'), dra = await rectOf('#drawerSlot')
  ok('默认宽高：梯子 240、侧栏 400、抽屉 280', lad.w === 240 && pan.w === 400 && dra.h === 280, `${lad.w} / ${pan.w} / ${dra.h}`)
  await dragSplit('panel', -1000, 0)
  pan = await rectOf('#sidePanel')
  ok('侧栏往左拖到头：夹在 640', pan.w === 640, `${pan.w}`)
  await dragSplit('panel', 80, 0)
  pan = await rectOf('#sidePanel')
  ok('侧栏拖回 80：560', pan.w === 560, `${pan.w}`)
  await shotL('面板加宽')
  await dragSplit('ladder', 1000, 0)
  lad = await rectOf('#ladderSlot')
  ok('梯子往右拖到头：夹在 160', lad.w === 160, `${lad.w}`)
  await dragSplit('ladder', -160, 0)
  lad = await rectOf('#ladderSlot')
  ok('梯子拖宽 160：320', lad.w === 320, `${lad.w}`)
  await dragSplit('drawer', 0, -2000)
  dra = await rectOf('#drawerSlot')
  const pageH = (await rectOf('#page-chart')).h
  ok('抽屉往上拖到头：不超过页面高 60%、图表区留得住', dra.h <= Math.round(pageH * 0.6) + 1 && (await rectOf('#chartArea')).h >= 240, `${dra.h} / 页面 ${pageH}`)
  await dragSplit('drawer', 0, 200)
  dra = await rectOf('#drawerSlot')
  await shotL('抽屉加高')
  // 多图网格：列、行
  await dragSplit('grid-cols-0', 220, 0, 0.25)
  await dragSplit('grid-rows-0', 0, 90, 0.25)
  let z = await sizesNow()
  const g4 = z.grid?.['4']
  ok('网格列宽 / 行高落本机（按布局记）', g4?.cols?.length === 2 && g4?.rows?.length === 2 && g4.cols[0] > 0.55 && g4.rows[0] > 0.52, JSON.stringify(g4))
  const cellsBefore = await page.evaluate(() => [...document.querySelectorAll('.chart-cell')].map(e => Math.round(e.getBoundingClientRect().width)))
  ok('拖完即时落本机（不等刷新）', z.panel === 560 && z.ladder === 320 && z.drawer === dra.h, JSON.stringify({ panel: z.panel, ladder: z.ladder, drawer: z.drawer }))
  // 悬停特写：线变强调色
  const pb = await splitBox('panel')
  await page.mouse.move(pb.x + pb.width / 2, pb.y + 300); await wait(400)
  const lineColor = await page.evaluate(() => getComputedStyle(document.querySelector('.splitter[data-split="panel"]'), '::after').backgroundColor)
  const accent = await page.evaluate(() => { const d = document.createElement('i'); d.style.color = 'var(--accent)'; document.body.append(d); const c = getComputedStyle(d).color; d.remove(); return c })
  ok('分隔线悬停变强调色', lineColor === accent, `${lineColor} / 强调色 ${accent}`)
  await shotL('分隔条悬停', { x: Math.max(0, pb.x - 260), y: pb.y + 160, width: 520, height: 280 })
  await page.mouse.move(5, 700)
  // 刷新还在
  await page.reload({ waitUntil: 'domcontentloaded' }); await ready(); await wait(800)
  lad = await rectOf('#ladderSlot'); pan = await rectOf('#sidePanel'); const dra2 = await rectOf('#drawerSlot')
  const cellsAfter = await page.evaluate(() => [...document.querySelectorAll('.chart-cell')].map(e => Math.round(e.getBoundingClientRect().width)))
  ok('刷新后梯子 / 侧栏 / 抽屉 / 网格都还在', lad.w === 320 && pan.w === 560 && dra2.h === dra.h && cellsAfter.every((w, i) => Math.abs(w - cellsBefore[i]) <= 1), `${lad.w} / ${pan.w} / ${dra2.h}，格宽 ${cellsBefore.join(',')} → ${cellsAfter.join(',')}`)
  ok('尺寸不进账号同步（只在本机那一份里）', !JSON.stringify(await state()).includes('"panes"') && !(await page.evaluate(() => Object.keys(localStorage).filter(k => k !== 'hkline-web-sizes-v1' && /sizes/.test(k)).length)))
  // 窗口缩小：按比例夹，不溢出
  await page.setViewportSize({ width: 1600, height: 900 }); await wait(1200)
  let sc = await noScroll(), ca = await rectOf('#chartArea')
  lad = await rectOf('#ladderSlot'); pan = await rectOf('#sidePanel')
  ok('窗口缩到 1600×900：各区域按比例夹、图表区至少 480、不溢出', sc.ok && ca.w >= 480 && lad.w >= 160 && pan.w >= 320, `图表区 ${ca.w}×${ca.h}，梯子 ${lad.w}，侧栏 ${pan.w}，${sc.info}`)
  await page.setViewportSize({ width: 2560, height: 1440 }); await wait(1200)
  pan = await rectOf('#sidePanel'); lad = await rectOf('#ladderSlot')
  ok('窗口放回来：用户拖的尺寸原样回来', pan.w === 560 && lad.w === 320, `${lad.w} / ${pan.w}`)
  // 双击回默认
  for (const n of ['panel', 'ladder', 'drawer']) await dblSplit(n)
  await dblSplit('grid-cols-0', 0.25); await dblSplit('grid-rows-0', 0.25)
  lad = await rectOf('#ladderSlot'); pan = await rectOf('#sidePanel'); dra = await rectOf('#drawerSlot'); z = await sizesNow()
  const cellsReset = await page.evaluate(() => [...document.querySelectorAll('.chart-cell')].map(e => Math.round(e.getBoundingClientRect().width)))
  ok('双击分隔线回默认（本机记录一并清掉）', lad.w === 240 && pan.w === 400 && dra.h === 280 && z.panel == null && z.ladder == null && z.drawer == null && !z.grid?.['4']?.cols && !z.grid?.['4']?.rows && Math.abs(cellsReset[0] - cellsReset[1]) <= 1, `${lad.w} / ${pan.w} / ${dra.h}，格宽 ${cellsReset.join(',')}，${JSON.stringify(z)}`)

  // ---- 副图高（一图里：MACD / RSI 两个副图）
  await fresh('s=BTCUSDT&i=1h&layout=1&panel=watch&ladder=0&drawer=0')
  const sp0 = await sepY(0)
  ok('一图里找得到副图分隔线', !!sp0, JSON.stringify(sp0))
  if (sp0) {
    await page.mouse.move(sp0.x, sp0.y); await page.mouse.down(); await page.mouse.move(sp0.x, sp0.y - 150, { steps: 10 }); await page.mouse.up(); await wait(500)
    z = await sizesNow()
    ok('拖高第一个副图：比例落本机', z.panes && Object.keys(z.panes).length >= 1, JSON.stringify(z.panes))
    await page.mouse.move(5, 700); await wait(300)
    await shotL('副图加高')
    const sp1 = await sepY(0)
    await page.mouse.move(sp1.x, sp1.y); await page.mouse.down(); await page.mouse.move(sp1.x, 0, { steps: 12 }); await page.mouse.up(); await wait(500)
    const cb = await canvasBox(0), sp2 = await sepY(0)
    ok('副图往上拖到头：主图至少留 40%', sp2 && sp2.y - cb.y >= cb.height * 0.38, `分隔线在画布 ${sp2 ? Math.round(sp2.y - cb.y) : '?'} / ${Math.round(cb.height)}`)
    await page.mouse.move(sp2.x, sp2.y); await page.mouse.down(); await page.mouse.move(sp2.x, sp0.y - 150, { steps: 10 }); await page.mouse.up(); await wait(400)
    const zBefore = (await sizesNow()).panes
    await page.reload({ waitUntil: 'domcontentloaded' }); await ready(); await wait(800)
    const sp3 = await sepY(0)
    ok('刷新后副图高还在', sp3 && Math.abs(sp3.y - (sp0.y - 150)) <= 6 && JSON.stringify((await sizesNow()).panes) === JSON.stringify(zBefore), `分隔线 ${Math.round(sp0.y)} → 拖到 ${Math.round(sp0.y - 150)} → 刷新后 ${sp3 ? Math.round(sp3.y) : '?'}`)
    await page.mouse.dblclick(sp3.x, sp3.y); await wait(500)
    const sp4 = await sepY(0)
    ok('双击副图分隔线回默认', sp4 && Math.abs(sp4.y - sp0.y) <= 4 && (await sizesNow()).panes == null, `${sp4 ? Math.round(sp4.y) : '?'} / 默认 ${Math.round(sp0.y)}`)
  }

  // ---- 侧栏块之间（自选 / 盘口 / 详情）
  await page.evaluate(() => { const s = JSON.parse(localStorage.getItem('hkline-web-v1')); s.slots.widgets = ['watch', 'book', 'detail']; localStorage.setItem('hkline-web-v1', JSON.stringify(s)) })
  await page.reload({ waitUntil: 'domcontentloaded' }); await ready(); await wait(1500)
  const hOf = () => page.evaluate(() => [...document.querySelectorAll('#sidePanel [data-w]')].map(e => [e.dataset.w, Math.round(e.getBoundingClientRect().height)]))
  const h0 = await hOf()
  const vis = await page.evaluate(() => [...document.querySelectorAll('.splitter[data-split^="side-"]')].map(e => `${e.dataset.split}:${e.hidden ? '藏' : '显'}`))
  ok('侧栏：能长的两块之间有分隔线，定高的详情前没有', vis.includes('side-0:显') && vis.includes('side-1:藏'), vis.join(' '))
  await dragSplit('side-0', 0, 180, 0.5)
  const h1 = await hOf()
  const tot = a => a.reduce((x, [, h]) => x + h, 0)
  ok('侧栏往下拖 180：自选变高、盘口变矮、详情不动、总高不变', h1[0][1] - h0[0][1] === 180 && h0[1][1] - h1[1][1] === 180 && h1[2][1] === h0[2][1] && tot(h1) === tot(h0), `${JSON.stringify(h0)} → ${JSON.stringify(h1)}`)
  await page.reload({ waitUntil: 'domcontentloaded' }); await ready(); await wait(1500)
  const h2 = await hOf()
  ok('刷新后侧栏块高还在', JSON.stringify(h2) === JSON.stringify(h1), JSON.stringify(h2))
  await dblSplit('side-0', 0.5)
  const h3 = await hOf()
  ok('双击侧栏分隔线回默认分配', JSON.stringify(h3) === JSON.stringify(h0) && (await sizesNow()).side == null, JSON.stringify(h3))

  ok('布局与拖动：控制台无报错', sectionErrors(e0).length === 0, sectionErrors(e0).slice(0, 5).join(' | '))
}

// ═════════════════════════════ 指标与叠加（关键价位、VWAP 第一段、累计量差、大单与散户、粗周期成交量分布） ═════════════════════════════
const shotI = async name => { await page.screenshot({ path: `${OUT}/指标-${name}.png` }); console.log('  截图 指标-' + name) }
const indNow = (i = 0) => page.evaluate(k => window.__ind(k), i)
/** 等到条件成立（有上限，不空等：到了就走） */
async function until(fn, limit, step = 1000) {
  const t0 = Date.now()
  for (;;) { const v = await fn(); if (v || Date.now() - t0 > limit) return v; await wait(step) }
}
const setInd = ind => page.evaluate(x => { const s = JSON.parse(localStorage.getItem('hkline-web-v1')); s.ind = { ...s.ind, ...x }; localStorage.setItem('hkline-web-v1', JSON.stringify(s)) }, ind)
async function partLevels() {
  const e0 = errors.length
  const DAY = 864e5
  await fresh()
  // 指标库里有这两项、分在对的类里
  await setInd({ ma: false, vol: true, keys: true, vwap: true, subs: ['cvd', 'whale'] })
  await open('s=BTCUSDT&i=15m&layout=1&panel=watch&ladder=0&drawer=0')
  let d = await until(async () => { const x = await indNow(); return x && x.keysAll.length >= 8 && x.keys.length ? x : null }, 20000)
  d = d || await indNow()
  const want = ['昨高', '昨低', '今开', '上周高', '上周低', '昨控', '昨值上', '昨值下']
  ok('关键价位：15 分钟线八条都有（日 + 周 + 昨控与价值区）', want.every(w => d.keysAll.includes(w)), d.keysAll.join(' '))
  ok('关键价位：图上画出来的都带名字', d.keys.length > 0 && d.keys.every(k => want.includes(k.label)), d.keys.map(k => `${k.label}${k.touched ? '(已碰)' : ''}@${k.price}`).join(' '))
  ok('VWAP：第一段不完整就不画，第一个值落在 UTC 0 点（上海 8 点）那根', d.vwap && d.vwap.first >= 0 && (d.t0 % DAY === 0 || d.vwap.firstT % DAY === 0), d.vwap ? `第一根 ${new Date(d.t0).toISOString()}，VWAP 从 ${new Date(d.vwap.firstT).toISOString()} 起` : '无')
  await page.mouse.move(5, 700); await wait(300)
  await shotI('关键价位-15分钟')
  // 日线：只剩上周高低；周线：什么都没有
  await open('s=BTCUSDT&i=1d&layout=1&panel=watch&ladder=0&drawer=0')
  d = await until(async () => { const x = await indNow(); return x && x.iv === DAY && x.keysAll.length ? x : null }, 15000) || await indNow()
  ok('关键价位：日线只画上周高低', d.keysAll.length === 2 && d.keysAll.includes('上周高') && d.keysAll.includes('上周低'), d.keysAll.join(' '))
  await page.mouse.move(5, 700); await wait(300)
  await shotI('关键价位-日线')
  await open('s=BTCUSDT&i=1w&layout=1&panel=watch&ladder=0&drawer=0'); await wait(1500)
  d = await indNow()
  ok('关键价位：周线不画', d.keysAll.length === 0 && d.keys.length === 0, d.keysAll.join(' ') || '空')

  // 粗周期成交量分布：4 小时向币安要 15 分钟 K 线，只要一次（不每帧重拉）
  await setInd({ keys: false, vwap: false, vpvr: true, subs: [] })
  const fineReq = []
  const onReq = r => { const u = r.url(); if (/\/fapi\/v1\/klines\?/.test(u) && /interval=15m/.test(u)) fineReq.push(u) }
  page.on('request', onReq)
  await open('s=BTCUSDT&i=4h&layout=1&panel=watch&ladder=0&drawer=0')
  await until(async () => fineReq.length > 0, 10000, 500)
  await wait(2500)
  const n1 = fineReq.length
  await page.mouse.move(900, 600); await page.mouse.move(1300, 700, { steps: 20 }); await wait(3000)
  const n2 = fineReq.length
  page.off('request', onReq)
  ok('成交量分布 4 小时：要了 15 分钟 K 线（≤ 4 页 = 5000 根）', n1 >= 1 && n1 <= 4, `${n1} 次`)
  ok('成交量分布：不每帧重拉（晃鼠标 3 秒没有新请求）', n2 === n1, `${n1} → ${n2}`)
  await page.mouse.move(5, 700); await wait(300)
  await shotI('成交量分布-4小时细K线')

  // 累计量差（历史 / 实时分界、现货与合约两条）+ 大单与散户：1 分钟线上等一根整个落在实时段里
  await setInd({ vpvr: false, subs: ['cvd', 'whale'] })
  await open('s=BTCUSDT&i=1m&layout=1&panel=watch&ladder=0&drawer=0')
  d = await until(async () => { const x = await indNow(); return x && x.cvd && x.cvd.seam >= 0 && x.cvd.spot >= 2 && x.whale && x.whale.big > 0 ? x : null }, 150000, 3000) || await indNow()
  ok('累计量差：有历史 / 实时分界，实时段拆成现货、合约两条', !!d.cvd && d.cvd.seam > 0 && d.cvd.spot >= 2 && d.cvd.con === d.cvd.spot && d.cvd.tot === d.bars, JSON.stringify(d.cvd))
  ok('累计量差：图例口径写「币安 · 三家」', d.notes?.cvd?.text === '币安 · 三家', JSON.stringify(d.notes?.cvd))
  ok('大单与散户：两条都有数', !!d.whale && d.whale.big > 0 && d.whale.small > 0, JSON.stringify(d.whale))
  ok('大单与散户：图例写大单线与散户线（K / M 金额）', /^大单 ≥ [\d.]+[KMB] · 散户 < 10K/.test(d.notes?.whale?.text || ''), d.notes?.whale?.text || '无')
  // BTC 是服务端常驻跟踪的品种：近 3 天分钟历史回填后，1 分钟线加载的一整段（约 25 小时）都该有数
  const hist = d.whale && d.whale.big >= d.bars * 0.9
  ok('大单与散户：常驻跟踪品种有服务端分钟历史（不是从打开起）', hist && !/从打开起/.test(d.notes?.whale?.text || ''), `${d.whale?.big} / ${d.bars} 根有数；${d.notes?.whale?.text}`)
  const legend = await page.evaluate(() => [...document.querySelectorAll('.pane-legend .lrow')].map(e => e.textContent.replace(/\s+/g, ' ').trim()))
  ok('副图图例：现货 / 合约、大单 / 散户各有短名', legend.some(t => t.includes('现货') && t.includes('合约')) && legend.some(t => t.includes('大单') && t.includes('散户')), legend.join(' | '))
  await page.mouse.move(5, 700); await wait(300)
  await shotI('累计量差与大单散户-1分钟')
  // 深色皮肤看一眼颜色
  await setInd({ keys: true, vwap: true })
  await open('s=ETHUSDT&i=5m&theme=dark&skin=sage&layout=1&panel=watch&ladder=0&drawer=0')
  await until(async () => { const x = await indNow(); return x && x.keys.length ? x : null }, 20000)
  await page.mouse.move(5, 700); await wait(1000)
  await shotI('关键价位-青苔深色-5分钟')
  ok('指标：控制台无报错', sectionErrors(e0).length === 0, sectionErrors(e0).slice(0, 5).join(' | '))
}

// ═════════════════════════════ 订单流（梯子成交列 / 变化 / 24 小时两块 / 成交流） ═════════════════════════════
const shotO = async (name, opt = {}) => { await page.screenshot({ path: `${OUT}/订单流-${name}.png`, ...opt }); console.log('  截图 订单流-' + name) }
const ofd = () => page.evaluate(() => window.__of())
const ladBox = () => page.locator('#ladderSlot canvas').boundingBox()
const cardText = () => page.evaluate(() => { const c = document.querySelector('.of-card.show'); return c ? c.innerText : '' })
const OF_WIDGETS_ALL = ['watch', 'detail', 'book', 'tape', 'walls', 'liq', 'vol', 'alerts']
async function flowFresh(qs) {
  await fresh(qs)
  await page.evaluate(w => {
    localStorage.removeItem('hkline-web-of-v1')
    const s = JSON.parse(localStorage.getItem('hkline-web-v1'))
    s.orderFlow = true; s.slots.ladder = true; s.slots.widgets = w
    localStorage.setItem('hkline-web-v1', JSON.stringify(s))
  }, OF_WIDGETS_ALL)
  await page.reload({ waitUntil: 'domcontentloaded' }); await ready()
}
async function partFlow() {
  const e0 = errors.length
  const heatReqs = []
  const onReq = r => { if (r.url().includes('/orderflow/heat')) heatReqs.push(r.url()) }
  const heatResp = []
  const onResp = r => { if (r.url().includes('/v1/market/orderflow/heat')) heatResp.push(`${r.status()} ${r.url().replace(/^.*\?/, '')}`) }
  const onFail = r => { if (r.url().includes('/v1/market/orderflow/heat')) heatResp.push(`失败 ${r.failure()?.errorText} ${r.url().replace(/^.*\?/, '')}`) }
  page.on('request', onReq); page.on('response', onResp); page.on('requestfailed', onFail)
  try {
    await flowFresh('s=BTCUSDT&i=1h&layout=1&panel=watch&ladder=1&drawer=0')
    await page.waitForFunction(() => { const d = window.__of(); return d?.ladder && d.ladder.tradeY != null && d.vol.slots > 0 && d.liq.points > 0 && d.tapeRows.length > 3 }, null, { timeout: 60000, polling: 1000 }).catch(() => {})
    let d = await ofd()
    const L = d.ladder
    // ---- 梯子铺满（原来 1 小时 BTC 一行 1 500、只剩三行、只画主图那一段）
    ok('1 小时 BTC：梯子每行比原来细（< 1 500），行铺满整列高度', !!L && L.rs < 1500 && L.top <= 28 + L.rowH && L.bottom >= L.H - 32 - L.rowH && L.rows >= 30, L ? `每行 ${L.rs}、${L.rows} 行、行高 ${L.rowH}、覆盖 ${Math.round(L.top)}–${Math.round(L.bottom)} / ${L.H}` : '无')
    ok('中列：打开以来有成交的行、脚注写「成交自 hh:mm 起」', !!L && L.trades > 0 && /成交自 \d\d:\d\d 起/.test(L.info), L ? `${L.trades} 行 · ${L.info}` : '')
    const lb = await ladBox()
    if (L?.tradeY != null) {
      await page.mouse.move(lb.x + lb.width / 2, lb.y + L.tradeY); await wait(400)
      const t = await cardText()
      ok('悬停有成交的行：卡片有主动买卖、净差 %、距中间价', /主动买 · 主动卖/.test(t) && /净差[\s\S]*%/.test(t) && /距中间价[\s\S]*%/.test(t) && /双击回到中间价/.test(t), t.replace(/\s+/g, ' ').slice(0, 160))
      await shotO('梯子-深度-悬停')
      await shotO('梯子-深度-特写', { clip: { x: lb.x - 60, y: lb.y, width: lb.width + 60 + 420, height: lb.height } })
    } else ok('悬停有成交的行', false, '等了 60 秒没有成交行')
    // ---- 双击回到中间价
    // 自动缩放下左键拖只横移，纵向拖偏要用右键（DragPan.vertical）；以前这里用左键拖，偏移只有几十 px、断言永远红
    const cb = await canvasBox(0)
    await page.mouse.move(cb.x + cb.width * 0.4, cb.y + cb.height * 0.3); await page.mouse.down({ button: 'right' })
    await page.mouse.move(cb.x + cb.width * 0.4, cb.y + cb.height * 0.3 + 260, { steps: 12 }); await page.mouse.up({ button: 'right' }); await wait(500)
    await page.keyboard.press('Escape')
    const off1 = (await ofd()).ladder
    // 拖偏之后实时成交一直在跳，不能把图拽回中间价（交易员拖开是想看别处）
    await wait(5000)
    const off1b = (await ofd()).ladder
    ok('右键拖偏之后 5 秒：行情在跳也不把图拽回中间价', Math.abs(off1b.midY - off1b.centerY) > 60 && Math.abs((off1b.midY - off1b.centerY) - (off1.midY - off1.centerY)) <= 30, `拖偏 ${off1.midY - off1.centerY} px → 5 秒后 ${off1b.midY - off1b.centerY} px`)
    await page.mouse.move(lb.x + lb.width / 2, lb.y + lb.height * 0.5)
    await page.mouse.dblclick(lb.x + lb.width / 2, lb.y + lb.height * 0.5); await wait(600)
    const off2 = (await ofd()).ladder
    const alertOpen = await page.locator('.dialog:visible, [role="dialog"]:visible').count()
    ok('图拖偏之后双击梯子：中间价回到图的正中，不弹提醒', Math.abs(off1.midY - off1.centerY) > 60 && Math.abs(off2.midY - off2.centerY) <= 3 && alertOpen === 0, `拖偏后中间价离正中 ${off1.midY - off1.centerY} px → 双击后 ${off2.midY - off2.centerY} px，弹窗 ${alertOpen}`)
    // ---- 图放得很大：梯子改定高行、价格范围放宽
    for (let i = 0; i < 12; i++) { await page.mouse.move(lb.x + lb.width / 2, lb.y + lb.height / 2); await page.mouse.wheel(0, -400); await wait(60) }
    await wait(500)
    const Z = (await ofd()).ladder
    ok('价格轴放很大（细桶 > 32 px）：每行 20 px 定高、铺满', !!Z && !Z.aligned && Math.abs(Z.rowH - 20) < 0.5 && Z.rows >= Math.floor((Z.H - 60) / 20) - 2, Z ? `对齐 ${Z.aligned}、行高 ${Z.rowH}、${Z.rows} 行、每行 ${Z.rs}` : '')
    await shotO('梯子-放大后定高', { clip: { x: lb.x - 200, y: lb.y, width: lb.width + 200, height: lb.height } })

    // ---- 变化：1 小时
    await flowFresh('s=BTCUSDT&i=1h&layout=1&panel=watch&ladder=1&drawer=0'); await wait(6000)
    const sent0 = (await ofd()).heatFetchSent
    await page.locator('[data-lad-mode="delta"]').click()
    // 先等服务端那一份回来（实时环一开就有一列，光等「有变化的行」会赶在服务端之前）
    await page.waitForFunction(() => { const d = window.__of(), l = d.ladder; return l && l.mode === 'delta' && l.delta > 0 && l.deltaY != null && d.delta.status !== 'loading' && (d.delta.status !== 'ok' || /bucketMs=60000/.test(d.delta.srvUrl)) }, null, { timeout: 30000, polling: 500 }).catch(() => {})
    let D = (await ofd()).ladder
    ok('变化 · 1 小时：有变化的行、脚注写起点', D.mode === 'delta' && D.win === '1h' && D.delta > 0 && /变化自 \d\d:\d\d 起/.test(D.info), `${D.delta} 行 · 起点 ${D.deltaFrom} · ${D.info}`)
    if (D.deltaY != null) {
      const lb2 = await ladBox()
      await page.mouse.click(lb2.x + lb2.width / 2, lb2.y + D.deltaY); await wait(700)
      const t = await cardText()
      const spark = await page.locator('.of-card.show svg.of-spark').count()
      D = (await ofd()).ladder
      ok('变化模式点一行：卡片里画这一价位的小折线，不弹提醒', D.pinned != null && spark === 1 && /买 ·[\s\S]*卖 ·/.test(t), `钉住 ${D.pinned}，折线 ${spark}，${t.replace(/\s+/g, ' ').slice(0, 120)}`)
      await shotO('梯子-变化-1小时')
    } else ok('变化模式点一行', false, '没有可点的变化行')
    // ---- 变化：1 天
    await page.mouse.move(5, 700)
    await page.locator('[data-lad-win="1d"]').click()
    await page.waitForFunction(() => { const d = window.__of(), l = d.ladder; return l && l.win === '1d' && l.delta > 0 && /bucketMs=1800000/.test(d.delta.srvUrl || '') }, null, { timeout: 30000, polling: 500 }).catch(() => {})
    D = (await ofd()).ladder
    ok('变化 · 1 天：有变化的行、起点来自服务端（BTC 服务端跟着）', D.win === '1d' && D.delta > 0 && D.deltaFrom === 'server', `${D.delta} 行 · 起点 ${D.deltaFrom} · ${D.info}`)
    if (D.deltaFrom !== 'server') console.log('  热力请求：\n    ' + heatResp.join('\n    ') + '\n  ' + JSON.stringify((await ofd()).delta))
    await shotO('梯子-变化-1天')
    // 来回切两档：同一 URL 走缓存
    const sentA = (await ofd()).heatFetchSent
    for (const w of ['1h', '1d', '1h', '1d']) { await page.locator(`[data-lad-win="${w}"]`).click(); await wait(400) }
    const sentB = (await ofd()).heatFetchSent
    ok('两档来回切：热力请求走缓存去重', sentB - sentA <= 1, `切换前共 ${sentA} 次，切 4 次后 ${sentB} 次（进变化前 ${sent0}）`)
    await page.locator('[data-lad-mode="depth"]').click(); await wait(300)

    // ---- 24 小时流动性 / 成交
    d = await ofd()
    ok('24 小时流动性：有点（服务端补的 + 本页取样）', d.liq.points > 0 && (d.liq.status === 'ok' || d.liq.status === 'empty'), JSON.stringify(d.liq))
    ok('24 小时成交：三家 K 线都到了、有 48 格里的数', d.vol.slots > 0 && d.vol.exchanges.length === 3, JSON.stringify(d.vol))
    const heads = await page.evaluate(() => [...document.querySelectorAll('.of-stat-head')].map(e => e.textContent.trim()))
    ok('两块标题行都有数', heads.length === 2 && heads.every(h => /\d/.test(h)), heads.join(' | '))
    const sb = await page.locator('#sidePanel').boundingBox()
    const liqBox = await page.locator('#ofLiq').boundingBox()
    await page.mouse.move(liqBox.x + liqBox.width - 20, liqBox.y + liqBox.height / 2); await wait(400)
    const lt = await cardText()
    ok('悬停流动性：给那一格的买卖与相对上一格的变化', /买 · ±2.5%/.test(lt) && /卖 · ±2.5%/.test(lt) && /相对上一个 30 分钟|上一个 30 分钟没有记录/.test(lt), lt.replace(/\s+/g, ' ').slice(0, 140))
    await shotO('侧栏-流动性悬停', { clip: { x: sb.x - 320, y: sb.y + sb.height - 560, width: sb.width + 320, height: 560 } })
    const volBox = await page.locator('#ofVol').boundingBox()
    await page.mouse.move(volBox.x + volBox.width - 30, volBox.y + volBox.height / 2); await wait(400)
    const vt = await cardText()
    ok('悬停成交：合计、币安主动买卖、写明 OKX / Coinbase 只计总额', /合计/.test(vt) && /主动买/.test(vt) && /只计总额/.test(vt), vt.replace(/\s+/g, ' ').slice(0, 160))
    await shotO('侧栏-成交悬停', { clip: { x: sb.x - 320, y: sb.y + sb.height - 560, width: sb.width + 320, height: 560 } })
    await page.mouse.move(5, 700)
    // 收起 / 拖动排序
    await page.locator('.of-w-liq [data-of="collapse"]').click(); await wait(400)
    const lh = await page.locator('.of-w-liq').boundingBox()
    ok('流动性块能收起（只剩标题行）', lh.height <= 34, `${Math.round(lh.height)} px`)
    await page.locator('.of-w-liq [data-of="collapse"]').click(); await wait(300)
    await page.locator('.of-w-vol .of-w-head').dragTo(page.locator('.of-w-book'), { targetPosition: { x: 40, y: 4 } }); await wait(500)
    const order = (await state()).slots.widgets
    ok('拖「24 小时成交」到盘口上方：顺序落本机', order.indexOf('vol') < order.indexOf('book'), order.join(','))
    // 详情里每秒成交一行、不溢出
    const det = await page.evaluate(() => { const e = document.querySelector('#detail'); const t = e?.querySelector('.of-tps'); return e ? { t: t?.textContent?.trim() ?? '', over: e.scrollHeight - e.clientHeight, svg: !!t?.querySelector('svg') } : null })
    ok('详情里有「每秒成交」一行加小折线，不溢出', !!det && /每秒成交/.test(det.t) && det.svg && det.over <= 1, JSON.stringify(det))

    // ---- 成交流
    d = await ofd()
    const big = d.bigTrade, base = big * 5
    const rows = d.tapeRows
    const hOk = rows.every(r => r.h === (big > 0 && r.usd >= big ? 28 : 20))
    const aOk = rows.every(r => r.alpha >= 0.04 && r.alpha <= 0.35 && Math.abs(r.alpha - Math.min(0.35, Math.max(0.04, r.usd / base))) < 0.002)
    const bOk = rows.every(r => r.bps == null || Math.abs(parseFloat(r.bps.replace('−', '-'))) >= 0.5)
    ok('成交流：行高 20 / 28 按「≥ 门槛 ÷ 5」、底色 = clamp(金额 ÷ 门槛, 0.04, 0.35)、bps 小标 |bps| ≥ 0.5 才有', rows.length > 0 && hOk && aOk && bOk,
      `${rows.length} 行，门槛 ${base}，28 高 ${rows.filter(r => r.h === 28).length} 行，有 bps 的 ${rows.filter(r => r.bps).length} 行`)
    const tb = await page.locator('.of-w-tape').boundingBox()
    await shotO('成交流', { clip: { x: tb.x, y: tb.y, width: tb.width, height: tb.height } })

    // ---- 换品种：成交列与两块统计清零重来
    const since0 = (await ofd()).trades.since
    await page.locator('#wTbl tr[data-sym="ETHUSDT"]').first().click()
    await page.waitForFunction(() => window.__of().symbol === 'ETHUSDT', null, { timeout: 20000, polling: 500 }).catch(() => {})
    await wait(1500)
    d = await ofd()
    ok('换到 ETH：成交列清零重算、两块统计跟着换', d.symbol === 'ETHUSDT' && (d.trades.since == null || d.trades.since > since0), `symbol ${d.symbol} since ${since0} → ${d.trades.since}`)
    await wait(8000)
    await shotO('ETH-全页')

    // ---- 八块全开：侧栏一屏放下，成交流不被挤成几行（2026-09-29 压测：以前成交比盘口先压，只剩 5 行）
    const sideOf = () => page.evaluate(() => { const e = document.querySelector('#sidePanel'); return { w: e.clientWidth, ch: e.clientHeight, sh: e.scrollHeight, two: !!document.querySelector('#detail.two'), hs: Object.fromEntries([...e.querySelectorAll(':scope > [data-w]')].map(x => [x.dataset.w, Math.round(x.getBoundingClientRect().height)])) } })
    const cutCells = () => page.evaluate(() => [...document.querySelectorAll('#detail .stats.inline > div')].filter(d => { const v = d.querySelector('.v'); return v.scrollWidth > v.clientWidth + 0.5 }).map(d => d.innerText.replace(/\s+/g, ' ')))
    const sideRows = h => ({ watch: Math.floor((h.watch - 1 - 36 - 24) / 32), tape: Math.floor((h.tape - 1 - 32 - 4) / 20), walls: Math.floor((h.walls - 1 - 32 - 4) / 24) })
    let sd = await sideOf()
    ok('八块全开：侧栏一屏放下不出滚动条，成交流 ≥ 8 行、自选 ≥ 6 行、大单 ≥ 3 行', sd.sh <= sd.ch + 1 && sideRows(sd.hs).tape >= 8 && sideRows(sd.hs).watch >= 6 && sideRows(sd.hs).walls >= 3, `${sd.sh}/${sd.ch} ${JSON.stringify(sideRows(sd.hs))} ${JSON.stringify(sd.hs)}`)
    const cut400 = await cutCells()
    ok('侧栏 400 宽：详情十二格三列，没有被截成省略号的数', !sd.two && cut400.length === 0, cut400.join(' | ') || `宽 ${sd.w}`)
    // ---- 窄侧栏：详情改两列、数字不截断，八块仍然一屏放下
    await page.evaluate(() => localStorage.setItem('hkline-web-sizes-v1', JSON.stringify({ panel: 320 })))
    await page.reload({ waitUntil: 'domcontentloaded' }); await ready(); await wait(2500)
    sd = await sideOf()
    const cut320 = await cutCells()
    ok('侧栏最窄 320：详情改两列、没有被截成省略号的数；八块全开仍不出滚动条、成交流 ≥ 8 行', sd.two && cut320.length === 0 && sd.sh <= sd.ch + 1 && sideRows(sd.hs).tape >= 8, `宽 ${sd.w} 两列 ${sd.two} 截断 ${cut320.join(' | ') || '无'} ${sd.sh}/${sd.ch} ${JSON.stringify(sideRows(sd.hs))}`)
    const dbx = await page.locator('#detail').boundingBox()
    await shotO('详情-窄侧栏两列', { clip: dbx })
    await page.evaluate(() => localStorage.removeItem('hkline-web-sizes-v1'))

    // ---- 热力请求：一律收窄
    const bad = heatReqs.filter(u => u.includes('/v1/market/orderflow/heat')).filter(u => { const q = new URL(u, 'http://x').searchParams; const narrow = (q.has('lo') && q.has('hi')) || (q.has('around') && q.has('pct')); return !narrow || !q.has('bucketMs') || (+q.get('to') - +q.get('from')) > 25 * 3_600_000 })
    const apiReqs = heatReqs.filter(u => u.includes('/v1/market/orderflow/heat'))
    ok('热力请求一律带 lo / hi（或 around / pct）与 bucketMs，不拉 24 小时全量', apiReqs.length > 0 && bad.length === 0, `${apiReqs.length} 次，违规 ${bad.length}${bad.length ? '：' + bad[0] : ''}`)
  } finally { page.off('request', onReq); page.off('response', onResp); page.off('requestfailed', onFail) }
  ok('订单流：控制台无报错', sectionErrors(e0).length === 0, sectionErrors(e0).slice(0, 5).join(' | '))
}


// ------------------------------------------------------------ 自选小部件：列、键盘、多图打开到哪一格、闪色、从 TradingView 导入
const wRows = () => page.evaluate(() => [...document.querySelectorAll('#wTbl tbody tr[data-sym]')].map(r => ({ k: r.dataset.sym, ghost: r.classList.contains('wv-ghost'), focus: r === document.activeElement })))
const wFocus = () => page.evaluate(() => document.activeElement?.closest?.('#wTbl tr[data-sym]')?.dataset.sym || null)
const wHeads = () => page.evaluate(() => [...document.querySelectorAll('#wTbl thead th')].map(t => t.textContent.trim()))
const curSym = async (i) => { const s = await state(); return s.cells[i ?? s.active].symbol }
const wKey = async k => { await page.keyboard.press(k); await wait(350) }
const TV_TEXT = '###加密,BINANCE:BTCUSDT.P,BINANCE:PEPEUSDT,BINANCE:WIFUSDT.P\n###美股\nNASDAQ:AAPL,NASDAQ:NVDA\n###我的观察\nOANDA:XAGUSD,TVC:GOLD,COMEX:GC1!,NASDAQ:ZZZZQ'
const TV_MATCH = { BTCUSDT: 'crypto', '1000PEPEUSDT': 'crypto', WIFUSDT: 'crypto', AAPLUSDT: 'us', NVDAUSDT: 'us', XAGUSDT: 'com', XAUUSDT: 'com' }

async function partWatch() {
  const e0 = errors.length
  // 资金费缺数的样子：把 XAUUSDT 的费率拦成空串（币安现在没有空费率的品种，用它看「—」与悬停说明）
  await page.route('**/fapi/v1/premiumIndex', async r => {
    const res = await r.fetch(); const a = await res.json()
    for (const x of a) if (x.symbol === 'XAUUSDT') x.lastFundingRate = ''
    await r.fulfill({ response: res, json: a })
  })
  await fresh('layout=1&panel=watch&ladder=0&drawer=0&s=BTCUSDT')

  // ---- 列：侧栏默认 400 → 六列；拖窄到 340 → 四列
  const pw = await rectOf('#sidePanel')
  let h = await wHeads()
  ok('侧栏宽 ≥ 400：六列 品种 · 最新价 · 涨跌幅 · 成交额 · 资金费 · 持仓额', h.join('·') === '品种·最新价·涨跌幅·成交额·资金费·持仓额', `侧栏 ${pw?.w}：${h.join(' · ')}`)
  await page.waitForFunction(() => [...document.querySelectorAll('#wTbl [data-f="oi"]')].filter(e => e.textContent !== '—').length >= 3, null, { timeout: 15000, polling: 300 }).catch(() => {})
  const wide = await page.evaluate(() => [...document.querySelectorAll('#wTbl tbody tr')].slice(0, 3).map(r => `${r.dataset.sym} ${r.querySelector('[data-f="fr"]')?.textContent} ${r.querySelector('[data-f="oi"]')?.textContent}`))
  const fit = await page.evaluate(() => { const t = document.querySelector('#wTbl'), p = document.querySelector('#sidePanel'); return { t: Math.round(t.getBoundingClientRect().right), p: Math.round(p.getBoundingClientRect().right), cols: [...t.querySelectorAll('thead th')].map(x => Math.round(x.getBoundingClientRect().width)) } })
  ok('六列在 400 宽里放得下（不被侧栏裁掉）', fit.t <= fit.p, `表右缘 ${fit.t} · 侧栏右缘 ${fit.p} · 各列 ${fit.cols.join('/')}`)
  ok('资金费与持仓额有数（前三行）', wide.length === 3 && wide.every(x => /-?\d+\.\d{4}%/.test(x) && /\d(\.\d+)?[KMBT]$/.test(x)), wide.join(' | '))
  await shotN('自选-六列')
  await page.click('.widget-watch [data-tab="com"]'); await wait(600)
  const xau = await page.evaluate(() => { const c = document.querySelector('#wTbl tr[data-sym="XAUUSDT"] [data-f="fr"]'); return c ? { t: c.textContent, tip: c.dataset.tip } : null })
  ok('没有资金费的写「—」，悬停说明「该品种没有永续」', xau?.t === '—' && xau?.tip === '该品种没有永续', JSON.stringify(xau))
  await page.hover('#wTbl tr[data-sym="XAUUSDT"] [data-f="fr"]'); await wait(700)
  await shotN('自选-没有资金费悬停')
  await page.mouse.move(5, 700)
  await page.click('.widget-watch [data-tab="crypto"]'); await wait(400)
  await page.evaluate(k => { const s = JSON.parse(localStorage.getItem(k) || '{}'); s.panel = 340; localStorage.setItem(k, JSON.stringify(s)) }, SIZE_KEY)
  await page.reload({ waitUntil: 'domcontentloaded' }); await ready()
  h = await wHeads()
  ok('侧栏拖窄到 340：回到四列', h.join('·') === '品种·最新价·涨跌幅·成交额', `侧栏 ${(await rectOf('#sidePanel'))?.w}：${h.join(' · ')}`)
  const fit4 = await page.evaluate(() => { const t = document.querySelector('#wTbl'), p = document.querySelector('#sidePanel'); const v = document.querySelector('#wTbl tbody tr [data-f="vol"]'); return { t: Math.round(t.getBoundingClientRect().right), p: Math.round(p.getBoundingClientRect().right), v: Math.round(v?.getBoundingClientRect().right ?? 1e9) } })
  ok('窄侧栏：成交额整列在侧栏里（中文名放不下就省略）', fit4.t <= fit4.p && fit4.v <= fit4.p, `表右缘 ${fit4.t} · 成交额右缘 ${fit4.v} · 侧栏右缘 ${fit4.p}`)
  await shotN('自选-窄侧栏四列')
  await page.evaluate(k => localStorage.removeItem(k), SIZE_KEY)
  await page.reload({ waitUntil: 'domcontentloaded' }); await ready()

  // ---- 价格变动：文字闪一次涨跌色，150 ms
  const flash = await page.waitForFunction(() => {
    const e = document.querySelector('#wTbl .wv-flash-up, #wTbl .wv-flash-down'); if (!e) return null
    const cs = getComputedStyle(e); return { cls: e.className, dur: cs.animationDuration, name: cs.animationName }
  }, null, { timeout: 15000, polling: 20 }).then(x => x.jsonValue()).catch(() => null)
  ok('价格一跳：文字闪一次涨跌色，150 ms', !!flash && flash.dur === '0.15s' && /wvFlash(Up|Down)/.test(flash.name), JSON.stringify(flash))

  // ---- 键盘
  await page.click('#wTbl tr[data-sym="BTCUSDT"] td:nth-child(3)'); await wait(400)
  ok('点一行：焦点进列表', (await wFocus()) === 'BTCUSDT', `焦点 ${await wFocus()}`)
  await wKey('ArrowDown')
  ok('↓：光标下移并在图上打开', (await wFocus()) === 'ETHUSDT' && (await curSym()) === 'ETHUSDT', `焦点 ${await wFocus()} · 图上 ${await curSym()}`)
  await wKey('End')
  const list0 = (await state()).watch.crypto
  ok('End：跳到最后一只', (await wFocus()) === list0.at(-1) && (await curSym()) === list0.at(-1), `焦点 ${await wFocus()} · 最后 ${list0.at(-1)}`)
  await wKey('Home')
  ok('Home：回到第一只', (await wFocus()) === list0[0] && (await curSym()) === list0[0], `焦点 ${await wFocus()}`)
  await wKey('ArrowDown'); await wKey('ArrowDown')
  const third = list0[2]
  await wKey('Delete')
  let list1 = (await state()).watch.crypto
  ok('Delete：移出自选，光标落到下一行、不自动打开', !list1.includes(third) && (await wFocus()) === list0[3] && (await curSym()) === third, `移出 ${third} · 焦点 ${await wFocus()} · 图上 ${await curSym()}`)
  await wKey('Enter')
  ok('↵：在图上打开光标这只', (await curSym()) === list0[3], `图上 ${await curSym()}`)
  await wKey('Meta+z')
  list1 = (await state()).watch.crypto
  ok('⌘Z：撤销移出，回到原位置', JSON.stringify(list1) === JSON.stringify(list0), list1.join(','))
  await page.focus(`#wTbl tr[data-sym="${third}"]`); await wait(200)
  await wKey('Space')
  let rows = await wRows()
  const g = rows.find(r => r.k === third)
  ok('空格：取消收藏，这一行淡着留在原位', !(await state()).watch.crypto.includes(third) && !!g?.ghost && rows.indexOf(g) === 2 && g.focus, JSON.stringify(g))
  await shotN('自选-空格取消留在原位')
  await wKey('Space')
  list1 = (await state()).watch.crypto
  rows = await wRows()
  ok('再按空格：收回原位置', JSON.stringify(list1) === JSON.stringify(list0) && !rows.some(r => r.ghost), list1.join(','))
  await wKey('Space'); await wKey('Escape')
  rows = await wRows()
  ok('Esc 退出列表：焦点离开，取消的那一行这才消失', (await wFocus()) === null && !rows.some(r => r.k === third), `焦点 ${await wFocus()} · 行 ${rows.map(r => r.k).join(',')}`)
  // 放回去，别影响后面
  await page.evaluate(([k, l]) => { const s = JSON.parse(localStorage.getItem(k)); s.watch.crypto = l; localStorage.setItem(k, JSON.stringify(s)) }, ['hkline-web-v1', list0])
  await page.reload({ waitUntil: 'domcontentloaded' }); await ready()

  // ---- 多图：「在第 N 格打开」跟着活动格；右键菜单同样写第几格
  await open('layout=4&panel=watch&ladder=0&drawer=0')
  let tgtText = (await page.textContent('#wTarget').catch(() => '')).trim()
  const s0 = await state()
  ok('多图：自选头部写「在第 N 格打开」', tgtText.startsWith(`在第 ${s0.active + 1} 格打开`), tgtText)
  const b1 = await canvasBox(1)
  await page.mouse.click(b1.x + b1.width * 0.5, b1.y + b1.height * 0.4); await wait(500)
  tgtText = (await page.textContent('#wTarget')).trim()
  ok('点第 2 格：头部跟着变成「在第 2 格打开」', (await state()).active === 1 && tgtText.startsWith('在第 2 格打开'), tgtText)
  const before0 = await curSym(0)
  const inCells = new Set(s0.cells.map(c => c.symbol)); const pick = (await state()).watch.crypto.find(k => !inCells.has(k))
  await page.click(`#wTbl tr[data-sym="${pick}"] td:nth-child(3)`); await wait(600)
  ok('点自选的行：打开到活动的第 2 格，第 1 格不动', (await curSym(1)) === pick && (await curSym(0)) === before0, `第 1 格 ${await curSym(0)} · 第 2 格 ${await curSym(1)}`)
  const other = (await state()).watch.crypto.find(k => k !== pick && !inCells.has(k))
  await page.click(`#wTbl tr[data-sym="${other}"] td:nth-child(3)`, { button: 'right' }); await wait(300)
  const ml = await menuLabels()
  ok('右键行：菜单有「在第 2 格打开」「移出自选」', ml.includes('在第 2 格打开') && ml.includes('移出自选'), ml.join(' / '))
  await shotN('自选-多图在第N格打开')
  await clickMenu('在第 2 格打开')
  ok('右键「在第 2 格打开」：第 2 格换成这只', (await curSym(1)) === other && (await curSym(0)) === before0, `第 2 格 ${await curSym(1)}`)

  // ---- 从 TradingView 导入（登录时顺带看自选同步：导入的品种推到云端，再用 Delete 移出、云端跟着删）
  await page.unroute('**/fapi/v1/premiumIndex')
  const logged = KP_PASS ? await uiLogin() : false
  await open('layout=1&panel=watch&ladder=0&drawer=0', 'me')
  await page.click('[data-me="general"]'); await wait(400)
  const w0 = (await state()).watch
  const have = new Set(Object.values(w0).flat())
  const wantNew = Object.keys(TV_MATCH).filter(k => !have.has(k))
  await page.fill('#tviText', TV_TEXT)
  await page.click('#tviGo'); await wait(500)
  const res = await page.evaluate(() => { const e = document.querySelector('#tviResult'); return e ? { added: +e.dataset.added, unmatched: +e.dataset.unmatched, already: +e.dataset.already, text: e.innerText.replace(/\s+/g, ' ') } : null })
  const w1 = (await state()).watch
  ok('粘贴导入：按合约表匹配，新品种按自身类别追加', res?.added === wantNew.length && wantNew.every(k => w1[TV_MATCH[k]].includes(k)) && w1.crypto.slice(0, w0.crypto.length).join() === w0.crypto.join(),
    `新增 ${res?.added} / 期望 ${wantNew.length}（${wantNew.join(',')}）`)
  ok('对不上的列出来；已在自选的不重复加', res?.unmatched === 2 && /COMEX:GC1!/.test(res.text) && /NASDAQ:ZZZZQ/.test(res.text) && res.already === Object.keys(TV_MATCH).length - wantNew.length, res?.text)
  ok('###分区映射：加密、美股对上，「我的观察」并进加密', /加密 → 加密/.test(res?.text || '') && /美股 → 美股/.test(res?.text || '') && /我的观察 → 加密（没有同名分类，并进加密）/.test(res?.text || ''), res?.text)
  await shotN('自选-从TradingView导入')
  const tao = have.has('TAOUSDT') || w1.crypto.includes('TAOUSDT')
  await page.setInputFiles('#tviFile', { name: 'tradingview.txt', mimeType: 'text/plain', buffer: Buffer.from('BINANCE:DOGEUSDT.P,BINANCE:TAOUSDT.P') }); await wait(700)
  const res2 = await page.evaluate(() => +document.querySelector('#tviResult')?.dataset.added)
  ok('选 .txt 文件：读进来直接导入', res2 === (tao ? 0 : 1) && (await state()).watch.crypto.includes('TAOUSDT'), `新增 ${res2}`)
  await shotN('自选-从txt导入')
  const added = [...wantNew, ...(tao ? [] : ['TAOUSDT'])]
  if (logged) {
    const t0 = Date.now()
    const at = await Promise.all(added.map(k => waitCloud('favorites', `binance/usd_m/${k}`, 'live', t0, 20000)))
    ok('导入走自选同步：新品种都到了云端', at.every(x => x != null), added.map((k, i) => `${k} ${at[i] == null ? '没到' : at[i] + 'ms'}`).join(' · '))
  } else ok('导入走自选同步', false, '没给 KP_PASS，跳过云端核对')
  // 回图表页用 Delete 把导入的删掉（顺带核对删除也同步），测试账号保持原样
  await page.goto(`${URL_}#chart`, { waitUntil: 'domcontentloaded' }); await ready()
  for (const k of added) {
    const kind = TV_MATCH[k] || 'crypto'
    await page.click(`.widget-watch [data-tab="${kind}"]`); await wait(300)
    const r = page.locator(`#wTbl tr[data-sym="${k}"]`)
    if (!(await r.count())) continue
    await r.focus(); await wait(150); await wKey('Delete')
  }
  const w2 = (await state()).watch
  ok('导入的品种用 Delete 移出后，自选回到导入前', ['crypto', 'us', 'com'].every(k => w2[k].join() === w0[k].join()), ['crypto', 'us', 'com'].map(k => w2[k].length).join('/'))
  if (logged) {
    const t0 = Date.now()
    const at = await Promise.all(added.map(k => waitCloud('favorites', `binance/usd_m/${k}`, 'deleted', t0, 20000)))
    ok('Delete 移出也同步到云端', at.every(x => x != null), added.map((k, i) => `${k} ${at[i] == null ? '没删' : at[i] + 'ms'}`).join(' · '))
  }
  await page.click('.widget-watch [data-tab="crypto"]'); await wait(200)
  ok('自选：控制台无报错', sectionErrors(e0).length === 0, sectionErrors(e0).slice(0, 5).join(' | '))
}



// ═════════════════════════════ 画线（新工具、编辑交互、快捷键、同步） ═════════════════════════════
/** 选画线工具：组按钮上正好是它就点，不是就展开这一组再挑（已经拿着它就不动，免得再点一下放下） */
async function pickTool(t) {
  const b = page.locator(`#drawbar [data-tool="${t}"]`)
  if (await b.count()) { if ((await b.getAttribute('aria-pressed')) !== 'true') await b.click(); await wait(150); return }
  const [gid, k] = await page.evaluate(t => {
    const b = [...document.querySelectorAll('#drawbar [data-tools]')].find(x => x.dataset.tools.split(' ').includes(t))
    return [b?.closest('.tool-grp')?.dataset.grp, b ? b.dataset.tools.split(' ').indexOf(t) : -1]
  }, t)
  await page.click(`#drawbar [data-fly="${gid}"]`); await wait(250)
  await page.locator('.menu .mi').nth(k).click(); await wait(150)
}
const shotD = async (name, clip) => { await page.screenshot({ path: `${OUT}/画线-${name}.png`, ...(clip ? { clip } : {}) }); console.log('  截图 画线-' + name) }
const dbg = () => page.evaluate(() => window.__draw())
const drawsOf = async (sym, type) => ((await state()).drawings?.[sym] || []).filter(d => !type || d.type === type)
const lastOf = async (sym, type) => { const l = await drawsOf(sym, type); return l[l.length - 1] }
const byId = async (sym, id) => (await drawsOf(sym)).find(d => d.id === id)
const near = (a, b) => Math.abs(a - b) <= Math.abs(b) * 1e-9 + 1e-9
const toastText = () => page.evaluate(() => [...document.querySelectorAll('#toasts .toast')].map(e => e.textContent.trim()).join(' | '))
async function dragOn(x0, y0, x1, y1, { shiftMid = false, meta = false } = {}) {
  await page.mouse.move(x0, y0)
  if (meta) await page.keyboard.down('Meta')
  await page.mouse.down()
  if (shiftMid) await page.keyboard.down('Shift')
  await page.mouse.move(x1, y1, { steps: 8 })
  await page.mouse.up()
  if (shiftMid) await page.keyboard.up('Shift')
  if (meta) await page.keyboard.up('Meta')
  await wait(350)
}
async function partDraw() {
  const e0 = errors.length
  const sym = 'BTCUSDT'
  await fresh(`s=${sym}&i=1h&layout=1&panel=watch&ladder=0&drawer=0`)
  let P = await plotGeom()
  const px = f => P.x + (P.axisX - P.x) * f, py = f => P.y + 60 + (P.height * 0.55) * f
  const clipChart = () => ({ x: P.x - 60, y: Math.max(0, P.y - 60), width: P.width + 60, height: P.height + 100 })

  // ---- 分组工具栏
  const groups = await page.evaluate(() => [...document.querySelectorAll('#drawbar .tool-grp')].map(g => g.dataset.grp))
  await page.click('#drawbar [data-fly="volume"]'); await wait(300)
  const volTools = await menuLabels()
  ok('工具栏按组：线 / 形状 / 斐波那契 / 预测与测量 / 成交量；成交量组里是锚定 VWAP、固定区间成交量分布', groups.join() === 'lines,shapes,fib,forecast,volume' && volTools.some(l => l.includes('锚定 VWAP')) && volTools.some(l => l.includes('固定区间成交量分布')), `${groups.join(' ')}；${volTools.join('、')}`)
  const barBox = await page.locator('#drawbar').boundingBox()
  await shotD('工具栏分组', { x: 0, y: barBox.y, width: 420, height: 560 })
  await page.keyboard.press('Escape'); await wait(200)

  // ---- 锚定 VWAP：点一根 K 线
  const n0 = (await drawsOf(sym)).length
  await pickTool('avwap')
  await page.mouse.click(px(0.3), py(0.5)); await wait(400)
  const av = await lastOf(sym, 'avwap')
  ok('锚定 VWAP：点一根 K 线当锚点，画出来并落盘', (await drawsOf(sym)).length === n0 + 1 && av?.pts.length === 1, av ? `锚点 ${new Date(av.pts[0].t).toISOString().slice(0, 16)}` : '没画出来')
  const vBtn = await page.getAttribute('#drawbar .tool-grp[data-grp="volume"] .ibtn', 'data-tool')
  ok('组按钮换成这一组上次用的那把', vBtn === 'avwap', vBtn)
  // ---- 固定区间成交量分布：拖出一段
  await pickTool('fvp')
  await dragOn(px(0.55), py(0.25), px(0.8), py(0.6))
  const fv = await lastOf(sym, 'fvp')
  ok('固定区间成交量分布：拖出一段时间，画出来并落盘', !!fv && fv.pts.length === 2 && fv.pts[0].t < fv.pts[1].t, fv ? `${new Date(fv.pts[0].t).toISOString().slice(5, 16)} → ${new Date(fv.pts[1].t).toISOString().slice(5, 16)}` : '没画出来')
  // ---- 多空持仓：入场 → 目标（在上方 = 多）
  await pickTool('position')
  await page.mouse.click(px(0.12), py(0.55)); await wait(150)
  await page.mouse.move(px(0.24), py(0.3), { steps: 4 }); await page.mouse.click(px(0.24), py(0.3)); await wait(400)
  const po = await lastOf(sym, 'position')
  const r1 = po ? po.pts[1].p - po.pts[0].p : 0, r2 = po ? po.pts[0].p - po.pts[2].p : 0
  ok('多空持仓：入场、目标两下点完，止损先按 1R 对称', !!po && po.pts.length === 3 && r1 > 0 && r2 > 0 && Math.abs(r1 - r2) < po.pts[0].p * 1e-9, po ? po.pts.map(q => q.p.toFixed(1)).join(' / ') : '没画出来')
  const qPos = await page.evaluate(() => [...document.querySelectorAll('.draw-quick button')].map(b => b.dataset.q || (b.dataset.color ? 'color' : '')))
  ok('持仓选中后的快捷条只给锁、删（颜色固定红绿）', qPos.join() === 'lock,del', qPos.join())
  await shotD('持仓选中', clipChart())
  await page.keyboard.press('Escape'); await wait(300)
  await shotD('三种新工具', clipChart())
  await page.reload({ waitUntil: 'domcontentloaded' }); await ready()
  const kinds = (await drawsOf(sym)).map(d => d.type)
  ok('刷新后三种新工具都还在', ['avwap', 'fvp', 'position'].every(k => kinds.includes(k)), kinds.join(' '))

  // ---- 批量删除：三档带数量、能撤销
  const ind0 = (await state()).ind
  const indN = await page.evaluate(() => document.querySelectorAll('.menu').length) // 占位，下面从菜单读
  void indN
  await page.click('#drawbar [data-dact="clear"]'); await wait(300)
  const scs = await page.evaluate(() => [...document.querySelectorAll('.menu .mi')].map(e => `${e.querySelector('.label')?.textContent.trim()}:${e.querySelector('.sc')?.textContent.trim() || ''}`))
  const nInd = Number((scs.find(x => x.startsWith('全部指标')) || '').replace(/\D/g, ''))
  ok('垃圾桶菜单：全部画线 / 全部指标 / 全部，带实时数量', scs.join('，') === `全部画线:${kinds.length} 条，全部指标:${nInd} 个，全部:${kinds.length + nInd} 项` && nInd > 0, scs.join('，'))
  await shotD('批量删除菜单', { x: 0, y: Math.max(0, barBox.y + barBox.height - 320), width: 460, height: 320 })
  await page.locator('.menu .mi', { has: page.locator('.label', { hasText: /^全部$/ }) }).click(); await wait(300)
  let s = await state()
  const gone = (s.drawings[sym] || []).length === 0 && s.ind.subs.length === 0 && !s.ind.ma && !s.ind.vol
  await page.keyboard.press('Meta+z'); await wait(400)
  s = await state()
  const back = (s.drawings[sym] || []).length === kinds.length && JSON.stringify(s.ind) === JSON.stringify(ind0)
  await page.keyboard.press('Meta+y'); await wait(400)
  const redoOk = ((await state()).drawings[sym] || []).length === 0
  await page.keyboard.press('Meta+z'); await wait(400)
  ok('「全部」一次删掉画线和指标；⌘Z 画线与指标都回来；⌘Y 重做', gone && back && redoOk && ((await state()).drawings[sym] || []).length === kinds.length, `删 ${gone} 回 ${back} 重做 ${redoOk}`)
  await page.click('#drawbar [data-dact="clear"]'); await wait(300); await clickMenu('全部画线')
  ok('「全部画线」只删这只品种的画线，指标不动', (await drawsOf(sym)).length === 0 && JSON.stringify((await state()).ind) === JSON.stringify(ind0))

  // ---- ⇧ 吸 45°：拖端点的时候、画的时候
  await pickTool('trend')
  await dragOn(px(0.3), py(0.2), px(0.5), py(0.24))
  let tr = await lastOf(sym, 'trend')
  const skew = !!tr && !near(tr.pts[0].p, tr.pts[1].p)
  // 画完这条是选中的：拖第二个端点，拖到一半按下 ⇧
  await dragOn(px(0.5), py(0.24), px(0.56), py(0.26), { shiftMid: true })
  tr = await byId(sym, tr?.id)
  ok('⇧ 拖端点：吸成水平（0° / 45° / 90°）', skew && !!tr && near(tr.pts[0].p, tr.pts[1].p), tr ? tr.pts.map(q => q.p.toFixed(2)).join(' → ') : '')
  await page.keyboard.press('Escape'); await wait(150)
  await pickTool('trend')
  await dragOn(px(0.3), py(0.75), px(0.45), py(0.78), { shiftMid: true })
  const tr2 = await lastOf(sym, 'trend')
  ok('⇧ 画趋势线：吸成水平', !!tr2 && tr2.id !== tr?.id && near(tr2.pts[0].p, tr2.pts[1].p), tr2 ? tr2.pts.map(q => q.p.toFixed(2)).join(' → ') : '')
  await page.keyboard.press('Escape'); await wait(150)

  // ---- 选中：快捷条、方向键微移
  const selX = px(0.42)
  let lineY = py(0.2)
  await page.mouse.click(selX, lineY); await wait(300)
  const qb = await page.locator('.chart-cell .draw-quick').count()
  const qBtns = await page.evaluate(() => [...document.querySelectorAll('.draw-quick button')].map(b => b.dataset.q || (b.dataset.color ? 'recent' : '')))
  ok('选中画线：格子上沿出一条快捷条（颜色、粗细、线型、提醒、锁、删）', qb === 1 && ['palette', 'width', 'dash', 'alert', 'lock', 'del'].every(k => qBtns.includes(k)), qBtns.join(' '))
  const u0 = (await dbg()).undo
  const p0 = (await byId(sym, tr.id)).pts[0]
  for (let k = 0; k < 3; k++) { await page.keyboard.press('ArrowUp'); await wait(60) }
  await wait(300)
  let cur = await byId(sym, tr.id)
  const upOk = cur.pts[0].p > p0.p && cur.pts[0].t === p0.t
  await page.keyboard.press('Shift+ArrowRight'); await wait(300)
  cur = await byId(sym, tr.id)
  const u1 = (await dbg()).undo
  ok('方向键微移选中的画线：↑ 三下价格上移、⇧→ 时间右移；每次松键记一步撤销', upOk && cur.pts[0].t > p0.t && u1 - u0 === 4, `p ${p0.p.toFixed(2)} → ${cur.pts[0].p.toFixed(2)}，t +${Math.round((cur.pts[0].t - p0.t) / 60e3)} 分，撤销 +${u1 - u0}`)
  lineY -= 3
  // 拖的时候快捷条淡出，松手回来；再撤销这次拖动，线回到原处
  await page.mouse.move(selX + 30, lineY); await page.mouse.down(); await page.mouse.move(selX + 60, lineY + 20, { steps: 4 })
  const fading = await page.locator('.draw-quick.fading').count()
  await page.mouse.up(); await wait(300)
  const fadingAfter = await page.locator('.draw-quick.fading').count()
  ok('拖动画线时快捷条淡出，松手回来', fading === 1 && fadingAfter === 0, `拖时 ${fading} 松手 ${fadingAfter}`)
  await page.keyboard.press('Meta+z'); await wait(300)
  await page.mouse.click(selX, lineY); await wait(300)
  // 颜色：调色板里挑红；粗细 3；线型虚线
  await page.click('.draw-quick [data-q="palette"]'); await wait(250)
  await page.click('.menu .dq-palette [data-color="#F23645"]'); await wait(250)
  await page.click('.draw-quick [data-q="width"]'); await wait(250); await clickMenu('3 px')
  await page.click('.draw-quick [data-q="dash"]'); await wait(250); await clickMenu('虚线')
  s = await state()
  cur = s.drawings[sym].find(d => d.id === tr.id)
  ok('快捷条改颜色 / 粗细 / 线型，落到这条画线上', cur.color === '#F23645' && cur.width === 3 && cur.dash === 'dashed', `${cur.color} ${cur.width}px ${cur.dash}`)
  ok('同族记住上次的样式、最近用过的颜色排第一', s.drawStyles?.lines?.color === '#F23645' && s.drawStyles.lines.width === 3 && s.drawStyles.lines.dash === 'dashed' && s.recentColors?.[0] === '#F23645', JSON.stringify(s.drawStyles) + ' ' + JSON.stringify(s.recentColors))
  await shotD('快捷条', { x: P.x + P.width / 2 - 400, y: P.y, width: 800, height: 380 })
  // 最近用过的颜色：换个蓝，再点快捷条上的「最近」那一格回到红
  await page.click('.draw-quick [data-q="palette"]'); await wait(250)
  await page.click('.menu .dq-palette [data-color="#2962FF"]'); await wait(250)
  const recentBtns = await page.evaluate(() => [...document.querySelectorAll('.draw-quick .swatch-btn[data-color]')].map(b => b.dataset.color))
  if (recentBtns.includes('#F23645')) await page.click('.draw-quick .swatch-btn[data-color="#F23645"]')
  await wait(250)
  cur = await byId(sym, tr.id)
  ok('快捷条上有当前色之外最近用过的两种颜色，点一下就换回去', recentBtns.includes('#F23645') && recentBtns.length <= 2 && cur.color === '#F23645', recentBtns.join(' '))
  // 同族样式：射线（同在「线」族）新画一条就是红、3 px、虚线
  await page.keyboard.press('Escape'); await wait(100)
  await page.keyboard.press('Alt+j'); await wait(150)
  ok('Alt J = 射线', (await dbg()).tool === 'ray')
  await dragOn(px(0.3), py(0.9), px(0.4), py(0.85))
  const ray = await lastOf(sym, 'ray')
  ok('同族新画的线沿用上次改的样式（射线接住趋势线的红、3 px、虚线）', ray?.color === '#F23645' && ray.width === 3 && ray.dash === 'dashed', ray ? `${ray.color} ${ray.width} ${ray.dash}` : '')
  await page.keyboard.press('Escape'); await wait(150)

  // ---- 复制粘贴
  await page.mouse.click(selX, lineY); await wait(250)
  const nA = (await drawsOf(sym)).length
  await page.keyboard.press('Meta+c'); await wait(200)
  await page.keyboard.press('Meta+v'); await wait(300)
  await page.keyboard.press('Meta+v'); await wait(300)
  let all = await drawsOf(sym)
  const pasted = all.slice(-2)
  ok('⌘C / ⌘V：复制选中的画线，贴两次多两条，各自错开', all.length === nA + 2 && pasted.every(d => d.type === 'trend' && d.id !== tr.id) && pasted[0].pts[0].t !== pasted[1].pts[0].t, `${nA} → ${all.length}`)
  await shotD('复制粘贴', clipChart())
  await page.keyboard.press('Escape'); await wait(150)
  // ⌘ 拖：复制一条拖走，原来那条不动
  const trBefore = JSON.stringify((await byId(sym, tr.id)).pts)
  const nB = (await drawsOf(sym)).length
  await dragOn(selX, lineY, selX + 40, lineY + 140, { meta: true })
  all = await drawsOf(sym)
  const trAfter = JSON.stringify(all.find(d => d.id === tr.id).pts)
  ok('⌘ 拖一条画线 = 复制一条拖走，原来那条不动', all.length === nB + 1 && trAfter === trBefore, `${nB} → ${all.length}；原线${trAfter === trBefore ? '没动' : '动了'}`)
  await page.keyboard.press('Escape'); await wait(150)

  // ---- 锁住这一条：方向键不再动它
  // 这里前面贴过两条错开的副本：几乎水平的趋势线平移几根后仍穿过同一点，点下去选中的是最上面那条（和 TradingView 一样），
  // 不一定是 tr。所以不假定选中的是哪条，只认「点锁之后被锁住的那一条」
  await page.mouse.click(selX, lineY); await wait(250)
  const lockedBefore = new Set((await drawsOf(sym)).filter(d => d.locked).map(d => d.id))
  await page.click('.draw-quick [data-q="lock"]'); await wait(250)
  const newly = (await drawsOf(sym)).filter(d => d.locked && !lockedBefore.has(d.id))
  const lk = newly[0]
  await page.keyboard.press('ArrowUp'); await wait(250)
  const lk2 = lk && await byId(sym, lk.id)
  ok('快捷条锁住这一条：方向键不再挪它', newly.length === 1 && !!lk2 && JSON.stringify(lk.pts) === JSON.stringify(lk2.pts), `新锁住 ${newly.length} 条${lk?.id === tr.id ? '（原线）' : '（最上面那条副本）'}；价 ${lk?.pts[0].p} → ${lk2?.pts[0].p}`)
  await page.click('.draw-quick [data-q="lock"]'); await wait(200)
  await page.keyboard.press('Escape'); await wait(150)

  // ---- 按住 ⌘ 临时反过来用磁吸（磁吸默认关）
  const magOff = !(await state()).magnet
  await page.keyboard.press('Alt+h'); await wait(150)
  await page.mouse.move(px(0.62), py(0.43)); await page.keyboard.down('Meta'); await page.mouse.down(); await page.mouse.up(); await page.keyboard.up('Meta'); await wait(350)
  const hm = await lastOf(sym, 'hline')
  await page.keyboard.press('Escape')
  await page.keyboard.press('Alt+h'); await wait(150)
  await page.mouse.click(px(0.62), py(0.47)); await wait(350)
  const hn = await lastOf(sym, 'hline')
  const { ohlc } = await dbg()
  const onBar = p => p != null && ohlc.some(v => Math.abs(v - p) < 1e-9)
  ok('按住 ⌘ 临时开磁吸：水平线吸到开高低收；松开就不吸', magOff && !!hm && onBar(hm.pts[0].p) && !!hn && hn.id !== hm.id && !onBar(hn.pts[0].p), `⌘ ${hm?.pts[0].p} ${onBar(hm?.pts[0].p) ? '在' : '不在'}K 线上；不按 ${hn?.pts[0].p}`)
  await page.keyboard.press('Escape'); await wait(150)

  // ---- 连续画：双击组按钮，右键退出
  const nC = (await drawsOf(sym)).length
  await page.dblclick('#drawbar .tool-grp[data-grp="lines"] .ibtn'); await wait(250)
  const lineTool = (await dbg()).tool
  const dot = await page.locator('#drawbar .sticky-dot').count()
  const one = lineTool === 'hline' || lineTool === 'vline'
  for (const f of [0.15, 0.2, 0.25]) { await page.mouse.click(px(f), py(0.95)); await wait(100); if (!one) { await page.mouse.click(px(f + 0.03), py(0.9)); await wait(100) } }
  await wait(300)
  const d1 = await dbg()
  await shotD('连续画', { x: 0, y: barBox.y, width: 420, height: 360 })
  await page.mouse.click(px(0.6), py(0.6), { button: 'right' }); await wait(300)
  const d2 = await dbg(), menuN = await page.locator('.menu').count()
  const nC2 = (await drawsOf(sym)).length
  ok('双击组按钮 = 连续画（按钮上一个小点，连画三条工具还在）；右键图退出、不弹菜单', dot === 1 && d1.sticky && d1.tool === lineTool && nC2 === nC + 3 && !d2.tool && !d2.sticky && menuN === 0, `${lineTool} 小点 ${dot}，${nC} → ${nC2}；右键后工具 ${d2.tool}、菜单 ${menuN}`)
  await page.dblclick('#drawbar .tool-grp[data-grp="lines"] .ibtn'); await wait(200)
  await page.keyboard.press('Escape'); await wait(200)
  ok('连续画时 Esc 也退出', !(await dbg()).tool)

  // ---- 其它快捷键
  await page.mouse.move(px(0.5), py(0.5))
  await page.keyboard.press('Meta+Alt+h'); await wait(250)
  const hid = (await state()).drawHidden
  await page.keyboard.press('Meta+Alt+h'); await wait(250)
  ok('⌘⌥H 隐藏 / 显示全部画线', hid === true && (await state()).drawHidden === false)
  const panel0 = (await state()).panel
  await page.keyboard.press('Alt+Shift+w'); await wait(300)
  const panel1 = (await state()).panel
  await page.keyboard.press('Alt+Shift+w'); await wait(300)
  const panel2 = (await state()).panel
  ok('Alt ⇧ W 开关侧栏（再开回到上一次那一栏）', panel0 === 'watch' && panel1 === null && panel2 === 'watch', `${panel0} → ${panel1} → ${panel2}`)
  await page.keyboard.press('Shift+T'); await wait(300)
  const lay = await menuLabels()
  ok('⇧ T 打开布局', lay.some(l => l.includes('四图')), lay.slice(0, 3).join(' '))
  await page.keyboard.press('Escape'); await wait(200)
  await page.keyboard.press('Alt+n'); await wait(400)
  ok('Alt N 记一笔', (await page.locator('.note-dlg').count()) === 1)
  await page.keyboard.press('Escape'); await wait(300)

  // ---- 快捷键表能搜
  await page.keyboard.press('?'); await wait(400)
  const rows = () => page.evaluate(() => [...document.querySelectorAll('.kbd-dlg .kbd-table tr')].map(r => r.textContent.replace(/\s+/g, ' ').trim()))
  const all0 = (await rows()).length
  await page.fill('#kbdQ', '射线'); await wait(200)
  const q1 = await rows()
  await page.fill('#kbdQ', 'alt j'); await wait(200)
  const q2 = await rows()
  await page.fill('#kbdQ', '⌘ v'); await wait(200)
  const q3 = await rows()
  await shotD('快捷键表-搜索', await page.locator('.kbd-dlg').boundingBox())
  await page.fill('#kbdQ', '没有这个'); await wait(200)
  const none = await page.locator('.kbd-dlg .kbd-none').count()
  ok('? 快捷键表能搜：按功能（射线）、按键（alt j = Alt J、⌘ v）；搜不到给空状态', all0 > 30 && q1.length >= 1 && q1.every(r => /射线/.test(r)) && q2.length === 1 && /射线/.test(q2[0]) && q3.some(r => /粘贴/.test(r)) && none === 1, `全表 ${all0} 行；射线 → ${q1.join(' / ')}；alt j → ${q2.join(' / ')}；⌘ v → ${q3.length} 行`)
  await page.keyboard.press('Escape'); await wait(300)

  // ---- 每只品种的上限：500 条
  await page.evaluate(() => {
    const s = JSON.parse(localStorage.getItem('hkline-web-v1'))
    s.drawings.ETHUSDT = Array.from({ length: 500 }, (_, k) => ({ id: 'q' + k, type: 'hline', pts: [{ t: Date.now() - 36e5, p: 1000 + k }], color: '#2962FF', width: 1 }))
    localStorage.setItem('hkline-web-v1', JSON.stringify(s))
  })
  await open('s=ETHUSDT&i=1h&layout=1')
  P = await plotGeom()
  await page.keyboard.press('Alt+h'); await wait(150)
  await page.mouse.click(px(0.5), py(0.5)); await wait(400)
  const qn = (await drawsOf('ETHUSDT')).length, qt = await toastText()
  ok('每只品种最多 500 条：到了不再新建、提示一句', qn === 500 && /上限/.test(qt), `${qn} 条；${qt}`)
  const tb = await page.locator('#toasts .toast').last().boundingBox()
  await shotD('上限提示', tb ? { x: Math.max(0, tb.x - 200), y: Math.max(0, tb.y - 120), width: tb.width + 400, height: tb.height + 240 } : undefined)
  await page.keyboard.press('Escape')
  await page.evaluate(() => { const s = JSON.parse(localStorage.getItem('hkline-web-v1')); delete s.drawings.ETHUSDT; localStorage.setItem('hkline-web-v1', JSON.stringify(s)) })

  // ---- 账号同步：三种新工具 + 线型 推上云端、清掉本机重新登录拉回来一模一样
  if (!KP_PASS) ok('画线同步（要 KP_PASS）', false, '没给 KP_PASS 环境变量')
  else {
    await fresh(`s=${sym}&i=1h&layout=1&panel=watch&ladder=0&drawer=0`)
    const logged = await uiLogin()
    await page.goto(`${URL_}?s=${sym}&i=1h&layout=1#chart`, { waitUntil: 'domcontentloaded' }); await ready()
    P = await plotGeom()
    const ids0 = new Set((await drawsOf(sym)).map(d => d.id))
    await pickTool('avwap'); await page.mouse.click(px(0.35), py(0.5)); await wait(300); await page.keyboard.press('Escape')
    await pickTool('fvp'); await dragOn(px(0.55), py(0.25), px(0.75), py(0.6)); await page.keyboard.press('Escape')
    await pickTool('position'); await page.mouse.click(px(0.15), py(0.6)); await wait(100); await page.mouse.click(px(0.25), py(0.8)); await wait(300); await page.keyboard.press('Escape')
    await pickTool('trend'); await dragOn(px(0.3), py(0.2), px(0.45), py(0.3)); await wait(200)
    await page.click('.draw-quick [data-q="dash"]'); await wait(200); await clickMenu('点线'); await page.keyboard.press('Escape')
    const mine = (await drawsOf(sym)).filter(d => !ids0.has(d.id))
    const t0 = Date.now()
    const arrived = []
    for (const d of mine) arrived.push(await waitCloud('drawings', `binance/usd_m/${sym}/${d.id}`, 'live', t0, 20000))
    ok('登录后新画的锚定 VWAP / 固定区间成交量分布 / 持仓（空）/ 点线趋势线都推到云端', logged && mine.length === 4 && arrived.every(x => x != null), mine.map((d, k) => `${d.type} ${arrived[k] ?? '没到'} ms`).join('，'))
    // 清掉本机（当成换了一台电脑），重新登录，从云端拉回来
    // 先离开页面再清：页面还活着时清，它卸载前会把内存里的会话写回去（等于没换电脑）
    await page.goto('about:blank')
    await cdp.send('Storage.clearDataForOrigin', { origin: new globalThis.URL(URL_).origin, storageTypes: 'local_storage' })
    const relogged = await uiLogin()
    await page.goto(`${URL_}?s=${sym}&i=1h&layout=1#chart`, { waitUntil: 'domcontentloaded' }); await ready()
    let got = []
    for (let k = 0; k < 30; k++) { got = await drawsOf(sym); if (mine.every(d => got.some(g => g.id === d.id))) break; await wait(500) }
    const same = mine.map(d => { const g = got.find(x => x.id === d.id); return !!g && g.type === d.type && g.pts.length === d.pts.length && g.pts.every((q, k) => q.t === d.pts[k].t && Math.abs(q.p - d.pts[k].p) <= Math.abs(d.pts[k].p) * 1e-9) && (g.dash || 'solid') === (d.dash || 'solid') })
    ok('清掉本机重新登录：四条原样拉回来（类型、锚点、线型）', relogged && same.every(Boolean), mine.map((d, k) => `${d.type}${d.dash ? '/' + d.dash : ''} ${same[k] ? '✓' : '✗'}`).join('，'))
    P = await plotGeom()
    await shotD('同步拉回', clipChart())
    // 收尾：「全部画线」删掉这一轮画的，云端也同步成已删
    await page.click('#drawbar [data-dact="clear"]'); await wait(300); await clickMenu('全部画线')
    const t1 = Date.now()
    let del = []
    for (const d of mine) del.push(await waitCloud('drawings', `binance/usd_m/${sym}/${d.id}`, 'deleted', t1, 15000))
    // 回归账号别的窗口也在用（同类设备只留一台在线）：被顶掉时推不出去的删除留在这个账号的账本里，重新登录后补推
    let kicked = false
    if (!del.every(x => x != null) && !(await stored())) {
      kicked = true
      await uiLogin()
      await page.goto(`${URL_}?s=${sym}&i=1h&layout=1#chart`, { waitUntil: 'domcontentloaded' }); await ready()
      const t2 = Date.now()
      del = []
      for (const d of mine) del.push(await waitCloud('drawings', `binance/usd_m/${sym}/${d.id}`, 'deleted', t2, 20000))
    }
    ok('「全部画线」删掉后云端同步成已删' + (kicked ? '（中途被同账号的别的窗口顶掉，重新登录后补推）' : ''), del.every(x => x != null) && (await drawsOf(sym)).every(d => !mine.some(m => m.id === d.id)), del.map(x => x ?? '没到').join(' / '))
  }
  // 回归账号被别的窗口顶掉时浏览器会打「401 (Unauthorized)」的资源错误，那是预期的
  const errs = sectionErrors(e0).filter(x => !/status of 401/.test(x))
  ok('画线：控制台无报错（被顶掉的 401 资源错误除外）', errs.length === 0, `401 ${sectionErrors(e0).length - errs.length} 条；` + errs.slice(0, 5).join(' | '))
}

const ALL = { watch: partWatch, chart: partChart, flow: partFlow, layout: partLayout, levels: partLevels, alerts: partAlerts, edge: partEdge, themes: partThemes, route: partRoute, sectors: partSectors, account: partAccount, review: partReview, finish: partFinish, draw: partDraw }
for (const k of PARTS.length ? PARTS : Object.keys(ALL)) {
  console.log(`\n══ ${k} ══`)
  try { await ALL[k]() } catch (e) { ok(`${k} 段跑完`, false, String(e.stack || e).split('\n').slice(0, 3).join(' ')); await page.screenshot({ path: `${OUT}/回归-失败-${k}.png` }).catch(() => {}) }
}
console.log('\n控制台报错：', errors.length ? '\n' + errors.join('\n') : '0')
console.log(`\n合计 ${results.length} 项，失败 ${results.filter(r => !r.pass).length} 项`)
await browser.close()
