// Hkline Web · 画线交叉验证（一条命令跑完；画线是重点功能，性能和别的功能都要和画线交叉着验）
//   npx vite build && node scripts/draw-cross.mjs [段…]
//   段：tools indicators layouts intervals scroll-zoom theme bulk undo reload perf alerts（不写 = 全跑）
//   环境变量：DRAW_ROOT（要测的 Web 目录，默认本仓库 Web；也认 F_ROOT）、DRAW_OUT（截图目录，默认 /tmp/kp-draw-cross）、DRAW_PORT（默认 5303）
// 每段都在干净的浏览器上下文里：WebSocket 换成不连的空壳、K 线合成（画线落点不被实时行情挪动），
// 每段都跑一遍同一组不变量（scripts/draw-lib.mjs assertDrawings）：条数、几何、像素、点中 / 点空、拖 / ⌘Z、隐藏开关、切品种回来。
// 页内报错（未捕获异常、console.error，去掉被拦请求的网络噪声）每段单独算一项。全部 ✓ 才以 0 退出。
import { preview, launch, measure, sleep, PC } from './f-lib.mjs'
import {
  R, ok, log, OUT, COLOR, openCtx, seedAndOpen, ready, baseState, realErrors, frame, geo, stored, storeOf, dbg, away, abs,
  pickTool, drawVia, drawAllTools, assertDrawings, pixelCheck, selectCheck, hideCheck, switchSymbol, sameGeom, exactSame, shot, measureR,
} from './draw-lib.mjs'

const ROOT = process.env.DRAW_ROOT || process.env.F_ROOT || new URL('..', import.meta.url).pathname
const PORT = +(process.env.DRAW_PORT || 5303)
const ALL = ['tools', 'indicators', 'layouts', 'intervals', 'scroll-zoom', 'theme', 'bulk', 'undo', 'reload', 'perf', 'alerts']
const want = process.argv.slice(2).filter(a => !a.startsWith('-'))
const SEGS = want.length ? want : ALL
for (const s of SEGS) if (!ALL.includes(s)) { console.error(`不认识的段：${s}（可选 ${ALL.join(' ')}）`); process.exit(2) }

const SYM = 'BTCUSDT'
let URL_ = '', browser = null

// ───────── 共用小步
/** 一格（1h）画满全部工具，返回基准 */
async function toolsScene(env, over = {}) {
  await seedAndOpen(env, baseState({ cells: [{ symbol: SYM, iv: '1h' }], ...over }))
  const r = await drawAllTools(env.page, 0, SYM)
  return r
}
const waitIv = (page, ci, iv) => page.waitForFunction(([i, iv]) => { const c = window.__cells?.()[i]; return c && c.iv === iv && c.bars > 0 && c.metaIv === ({ '1m': 6e4, '5m': 3e5, '15m': 9e5, '1h': 36e5, '4h': 144e5, '1d': 864e5, '1w': 6048e5 })[iv] }, [ci, iv], { timeout: 30000, polling: 200 })
async function setIv(page, iv) {
  await away(page)
  await page.click(`#tbIv [data-iv="${iv}"], [data-iv="${iv}"]`)
  const ci = await page.evaluate(() => window.__dx.activeIdx())
  await waitIv(page, ci, iv); await frame(page); await sleep(400)
}
async function setLayout(page, label, n) {
  await away(page)
  await page.click('#tbLayout'); await sleep(250)
  const k = await page.evaluate(l => [...document.querySelectorAll('.menu .mi')].findIndex(e => e.textContent.trim().startsWith(l)), label)
  if (k < 0) throw new Error('布局菜单里没有 ' + label)
  await page.locator('.menu .mi').nth(k).click(); await sleep(400)
  await ready(page, n)
  await page.waitForFunction(n => window.__cells().length === n && window.__cells().every(c => c.bars > 0), n, { timeout: 45000, polling: 250 })
  await frame(page); await sleep(500)
}
async function toggleInd(page, ids) {
  await away(page)
  await page.click('#tbInd'); await sleep(300)
  for (const id of ids) {
    const row = page.locator(`.ind-row[data-id="${id}"]`).first()
    if (!(await row.count())) { log(`指标面板里没有 ${id}`); continue }
    if ((await row.getAttribute('aria-disabled')) === 'true') continue
    await row.click(); await sleep(250)
  }
  await page.keyboard.press('Escape'); await sleep(300)
  await frame(page); await sleep(300)
}
async function clickCell(page, ci, q) { const P = await abs(page, ci, q); await page.mouse.click(P.x, P.y); await sleep(200) }
async function segErrors(env) { const e = realErrors(env.errors); ok('本段无报错（未捕获异常 / console.error）', !e.length, e.slice(0, 4).join(' ‖ ')); env.errors.length = 0 }
const symIdx = (page, sym) => page.evaluate(s => window.__cells().findIndex(c => c.symbol === s), sym)

// ───────── 1 tools：每把工具画一条，落点、存档、像素、点中、拖、⌘Z、隐藏、切品种
async function segTools() {
  const env = await openCtx(browser, URL_)
  const { page } = env
  try {
    await seedAndOpen(env, baseState({ cells: [{ symbol: SYM, iv: '1h' }] }))
    const tools = await page.evaluate(() => window.__dx.drawTools())
    log('工具栏里的工具：', tools.join(' '))
    const { slots, order } = await import('./draw-lib.mjs').then(m => m.toolSlots(page, 0, tools))
    const g = await geo(page, 0)
    const pxTol = (g.max - g.min) / (g.pane.h - 16) * 1.5
    for (const t of order) {
      const expect = await page.evaluate(([pts]) => pts.map(q => window.__dx.tpAt(0, q.x, q.y)), [slots[t]])
      const d = await drawVia(page, 0, t, slots[t], SYM)
      await page.keyboard.press('Escape')
      if (!d) { ok(`${t}：画上并存档`, false, '存档里没多出来'); continue }
      const bad = expect.map((e, k) => { const q = d.pts[k]; if (!q) return `#${k} 缺`; const okT = t === 'hline' || q.t === e.t; const okP = t === 'vline' || t === 'avwap' || Math.abs(q.p - e.p) <= pxTol; return okT && okP ? '' : `#${k} 应 (${e.t},${e.p.toFixed(2)}) 实 (${q.t},${q.p})` }).filter(Boolean)
      ok(`${t}：画上并存档，锚点落在点下去的那根 K 线与价位上`, d.type === t && !bad.length && (t !== 'position' || d.pts.length === 3), `${d.pts.length} 个锚点 ${bad.join('；')}`)
    }
    const base = await stored(page, SYM)
    ok('全部持久工具各一条', base.length === order.length && order.every(t => base.some(d => d.type === t)), `${base.length}/${order.length}：${base.map(d => d.type).join(',')}`)
    if (tools.includes('measure')) {
      const g2 = await geo(page, 0)
      const m = await drawVia(page, 0, 'measure', [{ x: g2.plotW * 0.1, y: g2.pane.y + g2.pane.h * 0.9 }, { x: g2.plotW * 0.2, y: g2.pane.y + g2.pane.h * 0.7 }], SYM)
      const nOn = (await geo(page, 0)).n
      await page.keyboard.press('Escape'); await sleep(200)
      const nOff = (await geo(page, 0)).n
      ok('测量：画出来在图上、Esc 就收掉、不算进画线', !m && nOn === base.length + 1 && nOff === base.length && (await stored(page, SYM)).length === base.length, `图上 ${nOn} → ${nOff}`)
    }
    await assertDrawings(page, '刚画完', { sym: SYM, base, ci: 0 }, { drag: true, hide: true, swap: 'ETHUSDT' })
    // 每把工具单独拖一次
    await shot(page, '01-tools')
    await segErrors(env)
  } finally { await env.ctx.close() }
}

// ───────── 2 indicators：主图指标一个个打开、副图开到加不进为止、再全关；每步不变量
async function segIndicators() {
  const env = await openCtx(browser, URL_)
  const { page } = env
  try {
    await toolsScene(env)
    const base = await stored(page, SYM)
    const steps = [['ma'], ['boll'], ['vwap'], ['ichi'], ['vpvr']]
    for (const s of steps) {
      await toggleInd(page, s)
      const on = (await storeOf(page)).ind
      ok(`打开 ${s[0]}`, !!on?.[s[0]], JSON.stringify(on))
      await assertDrawings(page, `+${s[0]}`, { sym: SYM, base, ci: 0 })
    }
    await shot(page, '02-indicators-main')
    // 副图：按面板顺序一个个开，开到数目不再涨
    await page.click('#tbInd'); await sleep(300)
    const subs = await page.evaluate(() => [...document.querySelectorAll('.ind-row[data-id]')].filter(r => !r.hasAttribute('data-of-row') && /副图/.test(r.querySelector('.tag')?.textContent || '')).map(r => r.dataset.id))
    await page.keyboard.press('Escape'); await sleep(200)
    let n0 = (await storeOf(page)).ind.subs.length
    for (const id of subs) {
      if ((await storeOf(page)).ind.subs.includes(id)) continue
      await toggleInd(page, [id])
      const n = (await storeOf(page)).ind.subs.length
      if (n === n0) break
      n0 = n
      await assertDrawings(page, `副图 ${n} 个（+${id}）`, { sym: SYM, base, ci: 0 }, { select: n % 2 === 0 })
    }
    const g = await geo(page, 0)
    log(`副图开满：${n0} 个；窗格 ${g.panes.map(p => p[0] + ':' + Math.round(p[2])).join(' ')}`)
    await assertDrawings(page, `副图开满（${n0} 个）`, { sym: SYM, base, ci: 0 }, { drag: true, hide: true })
    await shot(page, '02-indicators-full')
    // 全关
    const cur = (await storeOf(page)).ind
    const offs = [...['ma', 'ema', 'boll', 'vol', 'vwap', 'st', 'ichi', 'vpvr', 'keys'].filter(k => cur[k]), ...cur.subs]
    await toggleInd(page, offs)
    const after = (await storeOf(page)).ind
    ok('指标全关', !after.subs.length && !['ma', 'ema', 'boll', 'vol', 'vwap', 'st', 'ichi', 'vpvr', 'keys'].some(k => after[k]), JSON.stringify(after))
    await assertDrawings(page, '指标全关', { sym: SYM, base, ci: 0 }, { drag: true })
    await segErrors(env)
  } finally { await env.ctx.close() }
}

// ───────── 3 layouts：1 → 2×2 → 16 → 1；换活动格再换回；两格同品种，非活动格也有线、在那格画的这格也看得见
async function segLayouts() {
  const env = await openCtx(browser, URL_)
  const { page } = env
  try {
    await toolsScene(env)
    const base = await stored(page, SYM)
    for (const [label, n] of [['四图', 4], ['十六图', 16], ['一图', 1]]) {
      await setLayout(page, label, n)
      const ci = await symIdx(page, SYM)
      ok(`${label}：${SYM} 还在某一格`, ci >= 0, `格 ${ci}`)
      if (ci < 0) continue
      await assertDrawings(page, label, { sym: SYM, base, ci }, { select: n <= 4, drag: n === 4 })
      if (n === 16) await shot(page, '03-layouts-16')
      if (n === 4) {
        // 换活动格再换回
        const other = ci === 0 ? 1 : 0
        const g = await geo(page, other)
        await clickCell(page, other, { x: g.plotW * 0.5, y: g.pane.y + 6 })
        const a1 = await page.evaluate(() => window.__dx.activeIdx())
        const g0 = await geo(page, ci)
        const e = await page.evaluate(i => window.__dx.emptySpot(i), ci)
        await clickCell(page, ci, e || { x: g0.plotW * 0.5, y: g0.pane.y + 6 })
        const a2 = await page.evaluate(() => window.__dx.activeIdx())
        ok('四图：换到别的格再换回来', a1 === other && a2 === ci, `${a1} → ${a2}`)
        await assertDrawings(page, '四图换回活动格', { sym: SYM, base, ci }, { select: false })
      }
    }
    // 两格同品种（左右两图），活动格是左
    await seedAndOpen(env, baseState({ layout: '2', cells: [{ symbol: SYM, iv: '1h' }, { symbol: SYM, iv: '1h' }], active: 0, drawings: { [SYM]: base } }))
    await ready(page, 2)
    ok('两格同品种：都起来了', (await page.evaluate(() => window.__cells().map(c => c.symbol).join(','))) === `${SYM},${SYM}`)
    await assertDrawings(page, '同品种·活动格', { sym: SYM, base, ci: 0 }, { select: false })
    const px1 = await pixelCheck(page, 1)
    ok('同品种·非活动格也画着这些线', px1.ok && px1.vis >= 3, px1.info)
    // 在右格（非活动）里点线：先激活再选中
    const sc = await selectCheck(page, 1, { max: 4 })
    ok('同品种·右格里点线能选中', sc.ok, sc.info)
    // 在右格画一条，左格也看得见
    const g1 = await geo(page, 1)
    const d = await drawVia(page, 1, 'trend', [{ x: g1.plotW * 0.08, y: g1.pane.y + g1.pane.h * 0.92 }, { x: g1.plotW * 0.22, y: g1.pane.y + g1.pane.h * 0.88 }], SYM)
    await page.keyboard.press('Escape'); await sleep(300)
    const pxL = d ? await pixelCheck(page, 0, { ids: [d.id] }) : { ok: false, info: '没画上' }
    ok('同品种·右格画的线左格立刻也有', !!d && pxL.ok && pxL.vis === 1, pxL.info)
    await shot(page, '03-layouts-same-symbol')
    await segErrors(env)
  } finally { await env.ctx.close() }
}

// ───────── 4 intervals：1h 画一组跨几天的、1m 画一组近两小时的；1m → 1h → 1d → 1m 存档时间不变、看得见的都落在对的像素上
async function segIntervals() {
  const env = await openCtx(browser, URL_)
  const { page } = env
  try {
    await seedAndOpen(env, baseState({ cells: [{ symbol: SYM, iv: '1h' }] }))
    let g = await geo(page, 0)
    const P = (fx, fy) => ({ x: g.plotW * fx, y: g.pane.y + g.pane.h * fy })
    const hour = []
    for (const [t, pts] of [['rect', [P(0.3, 0.3), P(0.7, 0.55)]], ['fib', [P(0.25, 0.85), P(0.75, 0.62)]], ['trend', [P(0.1, 0.15), P(0.9, 0.25)]], ['vline', [P(0.5, 0.5)]]]) {
      const d = await drawVia(page, 0, t, pts, SYM); await page.keyboard.press('Escape'); if (d) hour.push(d.id)
    }
    await setIv(page, '1m')
    g = await geo(page, 0)
    const minute = []
    for (const [t, pts] of [['rect', [P(0.55, 0.3), P(0.8, 0.5)]], ['fib', [P(0.6, 0.85), P(0.9, 0.65)]], ['trend', [P(0.5, 0.12), P(0.95, 0.2)]]]) {
      const d = await drawVia(page, 0, t, pts, SYM); await page.keyboard.press('Escape'); if (d) minute.push(d.id)
    }
    const base = await stored(page, SYM)
    ok('1h 画 4 条、1m 画 3 条', hour.length === 4 && minute.length === 3, `${hour.length} + ${minute.length}`)
    for (const iv of ['1h', '1d', '1m']) {
      await setIv(page, iv)
      const now = await stored(page, SYM)
      ok(`${iv}：存档原封不动（时间、价位一个字不改）`, exactSame(base, now))
      const px = await pixelCheck(page, 0)
      const fibRect = px.list.filter(x => x.vis && (x.type === 'fib' || x.type === 'rect'))
      ok(`${iv}：看得见的线都落在投影位置上（其中矩形 / 斐波那契 ${fibRect.length} 条）`, px.ok && px.vis >= 1, px.info)
      if (iv === '1d') ok('1d：1h 画的矩形与斐波那契看得见且对', hour.every(id => px.list.find(x => x.id === id)?.vis !== false) && fibRect.length >= 2, fibRect.map(x => x.type + ':' + x.s.join('/')).join(' '))
      if (iv === '1m') ok('回到 1m：1m 画的三条都看得见且对', minute.every(id => { const x = px.list.find(y => y.id === id); return x && x.vis && x.s.every(v => v >= 0.5) }), px.list.filter(x => minute.includes(x.id)).map(x => x.type + ':' + x.s.join('/')).join(' '))
      await shot(page, `04-intervals-${iv}`)
    }
    await assertDrawings(page, '周期转一圈回 1m', { sym: SYM, base, ci: 0 }, { drag: true, hide: true })
    await segErrors(env)
  } finally { await env.ctx.close() }
}

// ───────── 5 scroll-zoom：滚轮 ±、拖时间轴、拖价格轴、双击价格轴复位；每步不变量
async function segScrollZoom() {
  const env = await openCtx(browser, URL_)
  const { page } = env
  try {
    await toolsScene(env)
    const base = await stored(page, SYM)
    const g = await geo(page, 0)
    const C = await abs(page, 0, { x: g.plotW * 0.5, y: g.pane.y + g.pane.h * 0.5 })
    const ops = [
      ['滚轮放大', async () => { await page.mouse.move(C.x, C.y); for (let i = 0; i < 2; i++) { await page.mouse.wheel(0, -120); await sleep(40) } }],
      ['滚轮缩小', async () => { await page.mouse.move(C.x, C.y); for (let i = 0; i < 10; i++) { await page.mouse.wheel(0, 120); await sleep(40) } }],
      ['横向滚轮平移', async () => { await page.mouse.move(C.x, C.y); for (let i = 0; i < 6; i++) { await page.mouse.wheel(-120, 0); await sleep(40) } }],
      ['拖时间轴', async () => { const a = await abs(page, 0, { x: g.plotW * 0.5, y: g.h - 10 }); await page.mouse.move(a.x, a.y); await page.mouse.down(); await page.mouse.move(a.x + 160, a.y, { steps: 10 }); await page.mouse.up() }],
      // 价格轴贴着绘图区的那 22 px 是「从轴上拖出一条提醒」，拖缩放要从再往右的地方下手
      ['拖价格轴', async () => { const a = await abs(page, 0, { x: g.plotW + Math.max(30, (g.w - g.plotW) * 0.7), y: g.pane.y + g.pane.h * 0.5 }); await page.mouse.move(a.x, a.y); await page.mouse.down(); await page.mouse.move(a.x, a.y + 90, { steps: 10 }); await page.mouse.up() }],
      ['双击价格轴复位', async () => { const a = await abs(page, 0, { x: g.plotW + Math.max(30, (g.w - g.plotW) * 0.7), y: g.pane.y + g.pane.h * 0.5 }); await page.mouse.dblclick(a.x, a.y) }],
      ['拖图平移', async () => { const e = await page.evaluate(() => window.__dx.emptySpot(0)); const a = await abs(page, 0, e); await page.mouse.move(a.x, a.y); await page.mouse.down(); await page.mouse.move(a.x - 120, a.y + 30, { steps: 10 }); await page.mouse.up() }],
    ]
    for (const [name, fn] of ops) {
      const v0 = await geo(page, 0)
      await fn(); await sleep(250); await away(page); await frame(page)
      const v1 = await geo(page, 0)
      const moved = v0.spacing !== v1.spacing || v0.from !== v1.from || v0.min !== v1.min || v0.max !== v1.max
      ok(`${name}：视图真的变了`, moved, `间距 ${v0.spacing.toFixed(2)}→${v1.spacing.toFixed(2)} 起 ${v0.from}→${v1.from} 价 ${v0.min.toFixed(1)}–${v0.max.toFixed(1)} → ${v1.min.toFixed(1)}–${v1.max.toFixed(1)}`)
      await assertDrawings(page, name, { sym: SYM, base, ci: 0 }, { minVisible: 3, select: name !== '横向滚轮平移' })
    }
    await shot(page, '05-scroll-zoom')
    await assertDrawings(page, '缩放平移之后', { sym: SYM, base, ci: 0 }, { drag: true, minVisible: 3 })
    await segErrors(env)
  } finally { await env.ctx.close() }
}

// ───────── 6 theme：深 / 浅、三套皮肤、红绿互换
async function lookSet(page, kv) {
  await away(page)
  await page.evaluate(() => { location.hash = '#me' }); await sleep(400)
  await page.click('[data-me="look"]').catch(() => {}); await sleep(300)
  for (const [k, v] of Object.entries(kv)) { await page.click(`[data-seg="${k}"][data-v="${v}"]`); await sleep(250) }
  await page.evaluate(() => { location.hash = '#chart' }); await sleep(400)
  await ready(page); await frame(page); await sleep(300)
}
async function segTheme() {
  const env = await openCtx(browser, URL_)
  const { page } = env
  try {
    await toolsScene(env, { ind: { ma: true, vol: true, subs: ['macd'] } })
    const base = await stored(page, SYM)
    await page.click('#hdrTheme'); await sleep(400); await frame(page)
    ok('切到深色', (await storeOf(page)).theme === 'dark')
    await assertDrawings(page, '深色', { sym: SYM, base, ci: 0 })
    await shot(page, '06-theme-dark')
    for (const skin of ['terra', 'classic', 'sage']) {
      await lookSet(page, { skin })
      ok(`皮肤 ${skin}`, (await storeOf(page)).skin === skin)
      await assertDrawings(page, `深色·${skin}`, { sym: SYM, base, ci: 0 }, { select: skin === 'classic' })
    }
    await page.click('#hdrTheme'); await sleep(400)
    ok('切回浅色', (await storeOf(page)).theme === 'light')
    for (const skin of ['terra', 'classic']) { await lookSet(page, { skin }); await assertDrawings(page, `浅色·${skin}`, { sym: SYM, base, ci: 0 }, { select: false }) }
    await lookSet(page, { skin: 'sage', updown: 'red-up' })
    ok('红涨绿跌', (await storeOf(page)).updown === 'red-up')
    await assertDrawings(page, '红涨绿跌', { sym: SYM, base, ci: 0 }, { drag: true })
    await shot(page, '06-theme-redup')
    await lookSet(page, { updown: 'green-up' })
    await segErrors(env)
  } finally { await env.ctx.close() }
}

// ───────── 7 bulk：500 条
function bulkList(v) {
  // v：可见区（时间与价位）。其余 498 条压在下半区；第 250 条是一条摆在所有 K 线之上的趋势线（点得到、拖得动）
  const { ts, lo, hi } = v, R = hi - lo, n = ts.length
  const T = f => ts[Math.max(0, Math.min(n - 1, Math.round(f * (n - 1))))]
  const lowP = f => lo + R * 0.42 * f
  const types = ['trend', 'ray', 'hline', 'vline', 'rect', 'fib', 'avwap', 'fvp', 'position']
  const out = []
  let s = 7
  const rnd = () => (s = (s * 16807) % 2147483647) / 2147483647
  for (let i = 0; i < 499; i++) {
    if (i === 250) { out.push({ id: 'k250', type: 'trend', pts: [{ t: T(0.55), p: hi + R * 0.02 }, { t: T(0.82), p: hi + R * 0.055 }], color: '#00B8D4', width: 2 }); continue }
    const t = types[i % types.length]
    const a = rnd(), b = rnd(), c = rnd()
    let pts
    switch (t) {
      case 'vline': pts = [{ t: T(0.02 + 0.35 * a), p: lowP(0.5) }]; break
      case 'avwap': pts = [{ t: T(0.02 + 0.3 * a), p: lowP(0.5) }]; break
      case 'fvp': { const x = 0.02 + 0.3 * a; pts = [{ t: T(x), p: lowP(0.2) }, { t: T(x + 0.04), p: lowP(0.6) }]; break }
      case 'hline': pts = [{ t: T(a), p: lowP(b) }]; break
      case 'ray': { const x = 0.05 + 0.6 * a; pts = [{ t: T(x), p: lowP(0.5 + 0.5 * b) }, { t: T(x + 0.05), p: lowP(0.4 * b) }]; break }
      case 'position': { const x = 0.05 + 0.6 * a; pts = [{ t: T(x), p: lowP(0.5) }, { t: T(x + 0.1), p: lowP(0.8) }, { t: T(x + 0.1), p: lowP(0.2) }]; break }
      default: { const x = 0.02 + 0.85 * a; pts = [{ t: T(x), p: lowP(b) }, { t: T(Math.min(0.98, x + 0.02 + 0.1 * c)), p: lowP(c) }] }
    }
    out.push({ id: `k${i}`, type: t, pts, color: COLOR, width: 1 })
  }
  return out
}
async function visibleOf(page, ci) {
  return page.evaluate(i => { const ch = window.__dx.ch(i), v = ch.visible(), b = ch.bars.slice(Math.max(0, v.from), v.to + 1); return { ts: b.map(x => x.t), lo: Math.min(...b.map(x => x.l)), hi: Math.max(...b.map(x => x.h)) } }, ci)
}
async function segBulk() {
  const env = await openCtx(browser, URL_)
  const { page } = env
  const cdp = await env.ctx.newCDPSession(page); await cdp.send('Performance.enable')
  try {
    await seedAndOpen(env, baseState({ cells: [{ symbol: SYM, iv: '1h' }], ind: { ma: true, vol: true, subs: ['macd', 'rsi'] } }))
    const list = bulkList(await visibleOf(page, 0))
    await seedAndOpen(env, baseState({ cells: [{ symbol: SYM, iv: '1h' }], ind: { ma: true, vol: true, subs: ['macd', 'rsi'] }, drawings: { [SYM]: list } }))
    const s0 = await stored(page, SYM)
    ok('种下 499 条', s0.length === 499 && (await geo(page, 0)).n === 499, `存档 ${s0.length} 图上 ${(await geo(page, 0)).n}`)
    const g = await geo(page, 0)
    const d500 = await drawVia(page, 0, 'hline', [{ x: g.plotW * 0.9, y: g.pane.y + g.pane.h * 0.75 }], SYM)
    await page.keyboard.press('Escape')
    ok('第 500 条用工具栏画上', !!d500 && (await stored(page, SYM)).length === 500)
    await page.evaluate(() => document.querySelectorAll('#toasts .toast').forEach(e => e.remove()))
    const d501 = await drawVia(page, 0, 'trend', [{ x: g.plotW * 0.85, y: g.pane.y + g.pane.h * 0.8 }, { x: g.plotW * 0.9, y: g.pane.y + g.pane.h * 0.85 }], SYM)
    await page.keyboard.press('Escape'); await page.keyboard.press('Escape')
    const toasts = await page.evaluate(() => window.__dx.toasts())
    ok('第 501 条画不上、提示到上限', !d501 && (await stored(page, SYM)).length === 500 && /上限/.test(toasts), `提示：${toasts.slice(0, 60)}`)
    const base = await stored(page, SYM)
    const px = await pixelCheck(page, 0, { ids: ['k250', d500?.id].filter(Boolean) })
    ok('第 250 条与第 500 条在图上对的位置', px.ok && px.vis === 2, px.info)
    // 选中第 250 条、拖、撤销；量帧
    const s = await page.evaluate(() => window.__dx.sample(0, ['k250']))
    const c = s.list[0]?.click
    let dragOk = false, info = ''
    const ops = async () => {
      const e = await page.evaluate(() => window.__dx.emptySpot(0)) // 拖平移从空地下手，不抓到线
      const C = await abs(page, 0, e || { x: g.plotW * 0.5, y: g.pane.y + g.pane.h * 0.5 })
      await page.mouse.move(C.x, C.y)
      for (let i = 0; i < 120; i++) { await page.mouse.wheel(0, i % 40 < 20 ? 60 : -60); await sleep(6) }
      await page.mouse.down(); for (let i = 0; i < 120; i++) { await page.mouse.move(C.x + Math.sin(i / 15) * 200, C.y); await sleep(8) } await page.mouse.up()
      for (let i = 0; i < 200; i++) { await page.mouse.move(C.x - 300 + (i * 13) % 600, C.y - 150 + (i * 7) % 300); await sleep(4) }
    }
    const m = await measureR(page, cdp, async () => {
      if (!c) return
      const P = await abs(page, 0, c)
      await page.mouse.click(P.x, P.y); await sleep(200)
      const sel = (await geo(page, 0)).sel
      await page.mouse.down(); await page.mouse.move(P.x + 40, P.y + 20, { steps: 30 }); await page.mouse.up(); await sleep(250)
      const moved = (await stored(page, SYM)).find(d => d.id === 'k250')
      await page.keyboard.press('Meta+z'); await sleep(350)
      const back = await stored(page, SYM)
      const b0 = base.find(d => d.id === 'k250')
      dragOk = sel === 'k250' && moved && moved.pts[0].t !== b0.pts[0].t && exactSame(base, back)
      info = `选中 ${sel}；拖后 ${moved ? moved.pts[0].t - b0.pts[0].t : '?'} ms；⌘Z ${exactSame(base, back) ? '复原' : '没复原'}`
      await page.keyboard.press('Escape')
      await ops()
    })
    ok('500 条：点中第 250 条、拖、⌘Z 复原', dragOk, info)
    // 同一页、同样的操作、不带画线再量一遍作对照（无头浏览器的帧节拍本身就是 33 ms 一拍，帧间隔只作参考；判定看每次重画的耗时）
    await page.keyboard.press('Alt+r'); await sleep(200)
    const keep = await page.evaluate(() => { const ch = window.__dx.ch(0); const d = ch.drawings; ch.drawings = []; ch.dirty = true; window.__dx.__keep = d; return d.length })
    const ref = await measureR(page, cdp, ops)
    await page.evaluate(() => { const ch = window.__dx.ch(0); ch.drawings = window.__dx.__keep; ch.dirty = true })
    ok(`500 条下选中 / 拖 / 缩放 / 平移 / 十字线：每次重画 p95 < 32 ms`, m.r95 < 32 && m.ltMax < 200, `重画 ${m.rN} 次 p50 ${m.r50} p95 ${m.r95} 最长 ${m.rMax} ms；帧间隔 p50 ${m.p50} p95 ${m.p95}；长任务 ${m.lt}（最长 ${m.ltMax} ms）CPU ${m.cpu}% ｜ 对照（同页不画这 ${keep} 条）重画 p50 ${ref.r50} p95 ${ref.r95} 最长 ${ref.rMax} ms；帧间隔 p50 ${ref.p50} p95 ${ref.p95}`)
    R.bulkPerf = { m, ref }
    await page.keyboard.press('Alt+r'); await sleep(200)
    await page.keyboard.press('Escape'); await page.keyboard.press('Alt+r'); await sleep(300) // 视图复位，第 250 条回到视野里
    const hc = await hideCheck(page, 0, SYM, 500, { ids: ['k250'] })
    ok('500 条：隐藏开关', hc.ok, hc.info)
    const a = await switchSymbol(page, 0, 'ETHUSDT'), b = await switchSymbol(page, 0, SYM)
    const back = await stored(page, SYM)
    ok('500 条：切品种回来都在、几何不变', a && b && back.length === 500 && !sameGeom(base, back).length && (await geo(page, 0)).n === 500, `${back.length} 条 图上 ${(await geo(page, 0)).n}`)
    await shot(page, '07-bulk')
    await segErrors(env)
  } finally { await env.ctx.close() }
}

// ───────── 8 undo：20 步，撤到底再重做到头，逐步比
async function segUndo() {
  const env = await openCtx(browser, URL_)
  const { page } = env
  try {
    await seedAndOpen(env, baseState({ cells: [{ symbol: SYM, iv: '1h' }] }))
    const g = await geo(page, 0)
    const P = (fx, fy) => ({ x: g.plotW * fx, y: g.pane.y + g.pane.h * fy })
    const snap = async () => JSON.stringify((await stored(page, SYM)).map(d => ({ ...d })).sort((a, b) => a.id < b.id ? -1 : 1))
    let u = (await dbg(page)).undo
    const cps = [{ u, s: await snap() }] // 每一步做完的样子与当时撤销栈的深度（一步可能压不止一格）
    const steps = []
    const step = async (name, fn) => {
      await fn(); await sleep(250)
      const u2 = (await dbg(page)).undo
      const s = await snap()
      if (u2 > u) cps.push({ u: u2, s })
      steps.push(`${name}${u2 > u ? (u2 - u > 1 ? `（压 ${u2 - u} 格）` : '') : '（不入撤销栈）'}`)
      u = u2
    }
    const ids = []
    const plan = [['hline', [P(0.15, 0.1)]], ['trend', [P(0.1, 0.3), P(0.3, 0.2)]], ['rect', [P(0.35, 0.3), P(0.5, 0.45)]], ['fib', [P(0.55, 0.85), P(0.75, 0.6)]], ['ray', [P(0.8, 0.5), P(0.85, 0.4)]]]
    for (const [t, pts] of plan) await step(`画 ${t}`, async () => { const d = await drawVia(page, 0, t, pts, SYM); await page.keyboard.press('Escape'); if (d) ids.push(d.id) })
    const clickOf = async id => (await page.evaluate(id => window.__dx.sample(0, [id]), id)).list[0]?.click
    for (const id of ids) await step('拖', async () => { const c = await clickOf(id); if (!c) return; const A = await abs(page, 0, c); await page.mouse.move(A.x, A.y); await page.mouse.down(); await page.mouse.move(A.x + 14, A.y + 10, { steps: 6 }); await page.mouse.up(); await page.keyboard.press('Escape') })
    const sel = async id => { const c = await clickOf(id); if (c) await clickCell(page, 0, c) }
    await step('锁定', async () => { await sel(ids[1]); await page.click('.draw-quick [data-q="lock"]').catch(() => {}) })
    await step('解锁', async () => { await page.click('.draw-quick [data-q="lock"]').catch(() => {}); await page.keyboard.press('Escape') })
    const uN = () => dbg(page).then(d => d.undo)
    let nudgeU = 0
    await step('按住方向键微移', async () => { await sel(ids[2]); const a = await uN(); for (let i = 0; i < 4; i++) { await page.keyboard.down('ArrowUp'); await sleep(40) } await page.keyboard.up('ArrowUp'); await sleep(300); nudgeU = (await uN()) - a; await page.keyboard.press('Escape') })
    await step('隐藏', () => page.keyboard.press('Meta+Alt+h'))
    await step('显示', () => page.keyboard.press('Meta+Alt+h'))
    for (const id of [...ids].reverse()) await step('删', async () => { await sel(id); await page.keyboard.press('Delete'); await sleep(150) })
    log('步骤：', steps.join(' → '))
    ok('按住方向键连续微移（自动连发 4 下）只记一步撤销', nudgeU === 1, `压了 ${nudgeU} 格`)
    const final = await stored(page, SYM)
    ok(`20 步做完（改了画线的 ${cps.length - 1} 步、撤销栈 ${u} 格）、最后全删光`, steps.length === 20 && cps.length - 1 >= 17 && final.length === 0, steps.filter(x => /压|不入/.test(x)).join('，'))
    // 撤到底：每撤到上一步记下的栈深，就和那一步做完时的样子逐字段比
    const depth = async () => (await dbg(page)).undo
    const badU = []
    let presses = 0
    for (let k = cps.length - 2; k >= 0; k--) {
      for (let g = 0; g < 10 && (await depth()) > cps[k].u; g++) { await page.keyboard.press('Meta+z'); presses++; await sleep(200) }
      if ((await snap()) !== cps[k].s) badU.push(`${cps.length - 1 - k}（栈 ${await depth()}）`)
    }
    ok('⌘Z 一步步撤回，每一步都和当时一模一样', !badU.length, badU.length ? `第 ${badU.slice(0, 5).join(',')} 步不对` : `${cps.length - 1} 步 ${presses} 下`)
    const u0 = await depth()
    await page.keyboard.press('Meta+z'); await sleep(200)
    ok('撤到底再按 ⌘Z 不出错不乱改', (await snap()) === cps[0].s && u0 === 0, `栈 ${u0}`)
    const px0 = await pixelCheck(page, 0)
    const badR = []
    const rdepth = async () => (await dbg(page)).redo
    const R0 = await rdepth()
    for (let k = 1; k < cps.length; k++) {
      const want = R0 - (cps[k].u - cps[0].u) // 重做到第 k 步时 redo 栈剩多少
      for (let g = 0; g < 10 && (await rdepth()) > want; g++) { await page.keyboard.press('Meta+Shift+z'); await sleep(200) }
      if ((await snap()) !== cps[k].s) badR.push(k)
    }
    ok('⇧⌘Z 一步步重做到头，每一步都和当时一模一样', !badR.length && (await rdepth()) === 0, badR.length ? `第 ${badR.slice(0, 5).join(',')} 步不对` : `${cps.length - 1} 步`)
    // 中途：撤到一半看像素
    for (let k = 0; k < 6; k++) { await page.keyboard.press('Meta+z'); await sleep(200) }
    const mid = await stored(page, SYM)
    await assertDrawings(page, '撤到中间（5 条都在）', { sym: SYM, base: mid, ci: 0 }, { select: true })
    ok('撤到底时图上没有残影', px0.total === 0, px0.info)
    await shot(page, '08-undo')
    await segErrors(env)
  } finally { await env.ctx.close() }
}

// ───────── 9 reload：刷新后全部不变量；坏档不崩、好的留下
async function segReload() {
  const env = await openCtx(browser, URL_)
  const { page } = env
  try {
    await toolsScene(env)
    const base = await stored(page, SYM)
    await page.reload({ waitUntil: 'domcontentloaded' }); await ready(page)
    await assertDrawings(page, '刷新后', { sym: SYM, base, ci: 0 }, { drag: true, hide: true })
    // 坏档：好的趋势线 / 矩形 / 水平线 + 各种坏条目（摆在左下角空地，互不压）
    const g = await geo(page, 0)
    const tp = (fx, fy) => page.evaluate(([x, y]) => window.__dx.tpAt(0, x, y), [g.plotW * fx, g.pane.y + g.pane.h * fy])
    const good = base.filter(d => ['trend', 'rect', 'hline'].includes(d.type))
    const a1 = await tp(0.05, 0.92), b1 = await tp(0.18, 0.88), a2 = await tp(0.05, 0.80), b2 = await tp(0.18, 0.76), a3 = await tp(0.05, 0.68), b3 = await tp(0.18, 0.64), h3 = await tp(0.1, 0.96)
    const bad = [
      { id: 'b-nop', type: 'trend', pts: [{ t: a1.t }, { t: b1.t, p: b1.p }], color: COLOR },
      { id: 'b-num', type: 'trend', pts: [a1, b1], color: 123 },
      { id: 'b-str', type: 'hline', pts: [h3], color: 'notacolor' },
      { id: 'b-inj', type: 'trend', pts: [a2, b2], color: '#fff" onmouseover="window.__xss=1"><img src=x onerror="window.__xss=2">' },
      { type: 'hline', pts: [h3], color: COLOR },
      { id: 'b-type', type: 'nosuchtool', pts: [a1, b1], color: COLOR },
      { id: 'b-empty', type: 'trend', pts: [], color: COLOR },
      { id: 'b-nan', type: 'trend', pts: [{ t: a1.t, p: null }, b1], color: COLOR },
      { id: 'b-wid', type: 'trend', pts: [a3, b3], color: COLOR, width: 'x', dash: 7 },
      null, 5, 'str',
    ]
    const st = await storeOf(page)
    st.drawings = { [SYM]: [...good, ...bad] }
    st.drawHidden = false
    // 最近用过的颜色非空：快捷条会拿当前线色去和它们比大小写（drawing.ts renderQuick），坏颜色要在这条路上过一遍
    st.recentColors = ['#FF0000', '#00FF00']
    await seedAndOpen(env, st)
    const errs = realErrors(env.errors)
    ok('坏档：打开不崩（没有未捕获异常）', !errs.length, errs.slice(0, 3).join(' ‖ '))
    const now = await stored(page, SYM)
    const kept = now.map(d => d.id)
    log('坏档读回来留下的：', kept.join(','))
    ok('坏档：好的三条都留着且几何不变', good.every(d => kept.includes(d.id)) && !sameGeom(good, now).length)
    ok('坏档：缺价位、空锚点、没 id 的丢掉', !kept.includes('b-nop') && !kept.includes('b-empty') && !kept.includes('b-nan') && now.every(d => typeof d.id === 'string'), kept.join(','))
    const px = await pixelCheck(page, 0, { ids: good.map(d => d.id) })
    ok('坏档：好的照样画在对的像素上', px.ok && px.vis === good.length, px.info)
    // 选中颜色不合法的那几条：快捷条要能出来、不能抛错、不能把颜色串当 HTML 执行
    ok('坏档：不认识的画线类型读档时丢掉', !kept.includes('b-type'), kept.includes('b-type') ? '「nosuchtool」留在存档里（画不出、点不中、删不掉，只能整份清掉）' : '')
    for (const id of ['b-num', 'b-str', 'b-inj', 'b-wid']) {
      if (!kept.includes(id)) { ok(`坏档 ${id}：读档时已剔除或修正`, true); continue }
      const d = now.find(x => x.id === id)
      env.errors.length = 0
      await page.evaluate(() => { delete window.__xss })
      const c = (await page.evaluate(id => window.__dx.sample(0, [id]), id)).list[0]?.click
      if (c) { await clickCell(page, 0, c); await sleep(300) }
      const sel = (await geo(page, 0)).sel
      const quick = await page.locator('.chart-cell .draw-quick').count()
      // 真把调色板点开：调色板按当前线色标「选中」那一格（drawing.ts 调色板），坏颜色要走这条路
      let pal = 0
      if (quick) {
        await page.click('.chart-cell .draw-quick [data-q="palette"]', { timeout: 1500 }).catch(() => {})
        await sleep(250)
        pal = await page.evaluate(() => document.querySelectorAll('.dq-palette .swatch-btn').length)
        await page.keyboard.press('Escape'); await sleep(120)
      }
      const xss = await page.evaluate(() => window.__xss ?? null)
      const inj = await page.evaluate(() => document.querySelectorAll('.draw-quick img, .draw-quick [onmouseover], .draw-quick [onerror]').length)
      const e = realErrors(env.errors)
      ok(`坏档 ${id}（color=${JSON.stringify(d.color)}${d.width != null ? ' width=' + JSON.stringify(d.width) : ''}）：选中不抛错、快捷条正常、颜色串不当 HTML`, sel === id && quick > 0 && !e.length && xss == null && !inj && pal > 0, `选中 ${sel} 快捷条 ${quick} 调色板色块 ${pal} 报错 ${e.slice(0, 2).join(' ‖ ')} xss ${xss} 注入节点 ${inj}`)
      await page.keyboard.press('Escape'); await sleep(150)
    }
    await shot(page, '09-reload-corrupt')
    env.errors.length = 0
    await segErrors(env)
  } finally { await env.ctx.close() }
}

// ───────── 10 perf：十六图 + 副图开满，每格 20 条 vs 不画；滚轮 / 拖 / 联动十字线
const PERF_SYMS = ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'BNBUSDT', 'XRPUSDT', 'DOGEUSDT', 'ADAUSDT', 'AVAXUSDT', 'LINKUSDT', 'DOTUSDT', 'LTCUSDT', 'TRXUSDT', 'BCHUSDT', 'NEARUSDT', 'APTUSDT', 'ARBUSDT']
function perDraw(sym, v) {
  const { ts, lo, hi } = v, R = hi - lo, n = ts.length
  const T = f => ts[Math.max(0, Math.min(n - 1, Math.round(f * (n - 1))))]
  const types = ['trend', 'ray', 'hline', 'vline', 'rect', 'fib', 'avwap', 'fvp', 'position', 'trend']
  return Array.from({ length: 20 }, (_, i) => {
    const t = types[i % 10], f = (i * 0.37) % 0.8 + 0.05, q = (i * 0.29) % 0.9 + 0.05
    const pts = t === 'hline' || t === 'vline' || t === 'avwap' ? [{ t: T(f), p: lo + R * q }]
      : t === 'position' ? [{ t: T(f), p: lo + R * 0.5 }, { t: T(f + 0.12), p: lo + R * 0.7 }, { t: T(f + 0.12), p: lo + R * 0.3 }]
        : [{ t: T(f), p: lo + R * q }, { t: T(Math.min(0.98, f + 0.15)), p: lo + R * (1 - q) }]
    return { id: `p${sym}${i}`, type: t, pts, color: i % 2 ? COLOR : '#2962FF', width: 1 + (i % 2) }
  })
}
async function segPerf() {
  const env = await openCtx(browser, URL_, { viewport: PC.viewport, depth: 20000, delay: 10 })
  const { page } = env
  const cdp = await env.ctx.newCDPSession(page); await cdp.send('Performance.enable')
  try {
    const st0 = baseState({ layout: '16', cells: PERF_SYMS.map(s => ({ symbol: s, iv: '1h' })), active: 0, ind: { ma: true, vol: true, subs: ['macd', 'rsi', 'kdj', 'atr', 'obv', 'cci', 'wr', 'stochrsi'] }, linkCross: true })
    await seedAndOpen(env, st0); await ready(page, 16)
    const subsN = (await storeOf(page)).ind.subs.length
    const vis = []
    for (let i = 0; i < 16; i++) vis.push(await visibleOf(page, i))
    const drawings = Object.fromEntries(PERF_SYMS.map((s, i) => [s, perDraw(s, vis[i])]))
    const grid = await page.evaluate(() => { const cs = [...document.querySelectorAll('.chart-cell')].map(e => e.getBoundingClientRect()); const x = Math.min(...cs.map(r => r.x)), y = Math.min(...cs.map(r => r.y)); return { x, y, w: Math.max(...cs.map(r => r.right)) - x, h: Math.max(...cs.map(r => r.bottom)) - y } })
    const rows = { wheel: [[], []], drag: [[], []], cross: [[], []] }
    const run = async (B) => {
      await seedAndOpen(env, B ? { ...st0, drawings } : st0); await ready(page, 16); await sleep(1500)
      if (B) {
        let seen = 0
        for (let i = 0; i < 16; i++) { const p = await pixelCheck(page, i); seen += p.vis }
        R.perfSeen = seen
      }
      const g0 = await geo(page, 0)
      const cx = g0.left + g0.plotW * 0.5, cy = g0.top + g0.pane.y + g0.pane.h * 0.4
      const k = B ? 1 : 0
      await page.mouse.move(cx, cy)
      rows.wheel[k].push(await measureR(page, cdp, async () => { for (let i = 0; i < 300; i++) { await page.mouse.wheel(0, i % 60 < 30 ? 40 : -40); await sleep(4) } }))
      rows.drag[k].push(await measureR(page, cdp, async () => { await page.mouse.move(cx, cy); await page.mouse.down(); for (let i = 0; i < 180; i++) { await page.mouse.move(cx + Math.sin(i / 20) * 200, cy); await sleep(8) } await page.mouse.up() }))
      rows.cross[k].push(await measureR(page, cdp, async () => { for (let i = 0; i < 600; i++) { const t = i / 600; await page.mouse.move(grid.x + 20 + (grid.w - 40) * ((t * 4) % 1), grid.y + 20 + (grid.h - 40) * t); await sleep(4) } }))
      await away(page)
    }
    for (let rep = 0; rep < 2; rep++) { await run(false); await run(true) }
    ok(`十六图 × ${subsN} 副图、每格 20 条：画线都在图上`, (R.perfSeen ?? 0) >= 16 * 10, `看得见 ${R.perfSeen} 条（共 320）`)
    const avg = (a, k) => +(a.reduce((s, x) => s + x[k], 0) / a.length).toFixed(1)
    const tbl = []
    for (const [name, lab] of [['wheel', '第一格滚轮缩放 300 下'], ['drag', '第一格拖动平移 3 秒'], ['cross', '联动十字线扫过十六格 600 下']]) {
      const [A, B] = rows[name]
      const pick = X => ({ rN: avg(X, 'rN'), r50: avg(X, 'r50'), r95: avg(X, 'r95'), rMax: avg(X, 'rMax'), rSum: avg(X, 'rSum'), f95: avg(X, 'p95'), lt: avg(X, 'lt'), ltMax: avg(X, 'ltMax'), cpu: avg(X, 'cpu') })
      const a = pick(A), b = pick(B)
      tbl.push({ lab, a, b })
      // 判据看「每次重画的耗时」（headless 的 rAF 空闲也是 30 Hz，帧间隔不可用）。画线本身就要花时间，拿「不画」当基线算百分比没有意义，
      // 所以：单次重画 p95 ≤ 4 ms（一帧 16.7 ms 的四分之一，十六格同帧也要撑得住）；长任务最多多 3 个；整页 CPU 最多多 10 个百分点
      ok(`${lab}：每格 20 条画线（单次重画 p95 ≤ 4 ms、长任务 +≤3、CPU +≤10 点）`, b.r95 <= 4 && b.lt <= a.lt + 3 && b.cpu <= a.cpu + 10,
        `无画线 重画 ${a.rN} 次 p50 ${a.r50} p95 ${a.r95} 总 ${a.rSum} ms 长任务 ${a.lt} CPU ${a.cpu}% ｜ 每格 20 条 重画 ${b.rN} 次 p50 ${b.r50} p95 ${b.r95} 总 ${b.rSum} ms 长任务 ${b.lt} CPU ${b.cpu}%`)
    }
    R.perfTable = tbl
    console.log('\n  场景 │ 无画线：重画次数 / 每次 p50 / p95 / 总耗时 / 帧 p95 / 长任务 / CPU │ 每格 20 条：同列')
    const row = x => `${x.rN} / ${x.r50} / ${x.r95} / ${x.rSum} ms / ${x.f95} ms / ${x.lt} / ${x.cpu}%`
    for (const r of tbl) console.log(`  ${r.lab} │ ${row(r.a)} │ ${row(r.b)}`)
    await shot(page, '10-perf-16')
    await segErrors(env)
  } finally { await env.ctx.close() }
}

// ───────── 11 alerts：线上建提醒、删线后提醒还在
async function segAlerts() {
  const env = await openCtx(browser, URL_)
  const { page } = env
  try {
    await seedAndOpen(env, baseState({ cells: [{ symbol: SYM, iv: '1h' }] }))
    const g = await geo(page, 0)
    const h = await drawVia(page, 0, 'hline', [{ x: g.plotW * 0.4, y: g.pane.y + g.pane.h * 0.15 }], SYM)
    await page.keyboard.press('Escape')
    const t = await drawVia(page, 0, 'trend', [{ x: g.plotW * 0.2, y: g.pane.y + g.pane.h * 0.8 }, { x: g.plotW * 0.6, y: g.pane.y + g.pane.h * 0.7 }], SYM)
    await page.keyboard.press('Escape')
    ok('画上一条水平线、一条趋势线', !!h && !!t)
    const mk = async d => {
      const c = (await page.evaluate(id => window.__dx.sample(0, [id]), d.id)).list[0]?.click
      await clickCell(page, 0, c)
      const btn = page.locator('.chart-cell .draw-quick [data-q="alert"]')
      const has = await btn.count()
      if (has) { await btn.click(); await sleep(300) }
      await page.keyboard.press('Escape'); await sleep(150)
      return has
    }
    const hb = await mk(h), tb = await mk(t)
    const al = (await storeOf(page)).alerts || []
    const dAl = al.filter(a => a.kind === 'drawing')
    ok('选中线点「提醒」：水平线、趋势线各建一条画线提醒', hb && tb && dAl.length === 2 && dAl.every(a => a.status === 'active'), `按钮 ${hb}/${tb}；提醒 ${JSON.stringify(dAl.map(a => [a.drawingID, a.status]))}`)
    const base = await stored(page, SYM)
    // 提醒是独立模块：线本身不带标记，按 drawingID（…/<线 id>）对上；选中时快捷条的铃要亮
    ok('两条提醒各对上一条线（drawingID 指向线 id）', base.every(d => dAl.some(a => String(a.drawingID).endsWith('/' + d.id))), JSON.stringify({ 线: base.map(d => d.id), 提醒: dAl.map(a => a.drawingID) }))
    const bells = []
    for (const d of base) {
      const c = (await page.evaluate(id => window.__dx.sample(0, [id]), d.id)).list[0]?.click
      if (c) { await clickCell(page, 0, c); await sleep(250) }
      bells.push(await page.locator('.chart-cell .draw-quick [data-q="alert"]').getAttribute('aria-pressed', { timeout: 1000 }).catch(() => null))
      await page.keyboard.press('Escape'); await sleep(120)
    }
    ok('再选中这两条线：快捷条上的提醒铃是亮的', bells.every(b => b === 'true'), JSON.stringify(bells))
    await assertDrawings(page, '带提醒的线', { sym: SYM, base, ci: 0 }, { hide: true })
    const al2 = ((await storeOf(page)).alerts || []).filter(a => a.kind === 'drawing')
    ok('隐藏画线不动提醒', al2.length === 2 && al2.every(a => a.status === 'active'))
    // 删线
    const c = (await page.evaluate(id => window.__dx.sample(0, [id]), h.id)).list[0]?.click
    await clickCell(page, 0, c); await page.keyboard.press('Delete'); await sleep(300)
    const left = await stored(page, SYM)
    const al3 = ((await storeOf(page)).alerts || []).filter(a => a.kind === 'drawing')
    ok('删掉水平线：线没了，它的提醒还在且仍有效', left.length === 1 && al3.length === 2 && al3.every(a => a.status === 'active'), `线 ${left.length} 提醒 ${JSON.stringify(al3.map(a => [a.drawingID, a.status, a.lines?.length]))}`)
    await page.reload({ waitUntil: 'domcontentloaded' }); await ready(page)
    const al4 = ((await storeOf(page)).alerts || []).filter(a => a.kind === 'drawing')
    ok('刷新后提醒照旧', al4.length === 2 && al4.every(a => a.status === 'active'))
    await assertDrawings(page, '删线刷新后', { sym: SYM, base: left, ci: 0 })
    await shot(page, '11-alerts')
    await segErrors(env)
  } finally { await env.ctx.close() }
}

const FN = { tools: segTools, indicators: segIndicators, layouts: segLayouts, intervals: segIntervals, 'scroll-zoom': segScrollZoom, theme: segTheme, bulk: segBulk, undo: segUndo, reload: segReload, perf: segPerf, alerts: segAlerts }

const { url, stop } = await preview(PORT, ROOT)
URL_ = url
console.log(`被测：${ROOT}  ${url}  截图 → ${OUT}`)
browser = await launch()
const t0 = Date.now()
try {
  for (const s of SEGS) {
    R.seg = s
    console.log(`\n━━ ${s}`)
    const ts = Date.now()
    try { await FN[s]() } catch (e) { ok(`${s} 段跑完（套件自身没抛错）`, false, String(e.stack || e).split('\n').slice(0, 4).join(' ⟵ ')) }
    console.log(`  （${((Date.now() - ts) / 1000).toFixed(0)} 秒）`)
  }
} finally { await browser.close().catch(() => {}); stop() }
console.log(`\n━━ 汇总：✓ ${R.pass}  ✗ ${R.fail}  （${((Date.now() - t0) / 1000).toFixed(0)} 秒）`)
for (const [s, v] of Object.entries(R.bySeg)) console.log(`  ${v.fail ? '✗' : '✓'} ${s.padEnd(12)} ${v.pass} 过 ${v.fail} 不过`)
if (R.fails.length) { console.log('\n不过的项：'); for (const f of R.fails) console.log('  ✗ ' + f) }
console.log(`截图：${OUT}`)
process.exit(R.fail ? 1 : 0)
