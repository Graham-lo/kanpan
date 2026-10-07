// Hkline Web · 滚轮缩放 / 平移手感量表（对照 TradingView：lightweight-charts ChartWidget._onMousewheel + TimeScale.zoom）
//   npx vite build --outDir /tmp/kp-wheel/dist && node scripts/wheel-feel.mjs
//   环境变量：WHEEL_DIST（要测的构建目录，默认 /tmp/kp-wheel/dist；改前 / 改后各 build 一份对照）、WHEEL_PORT（默认 5306）、
//             WHEEL_TAG（结果文件名后缀，默认 after）
// 自己起 vite preview（--outDir，不碰别人的 dist），K 线合成、WebSocket 空壳（draw-lib openCtx），2560×1440。
// 每一项：页内每帧采样（rAF）间距 / 右沿下标 / 主图手动价格区间 / 重画次数，Playwright 发真滚轮事件，量：
//   · 每格缩放比例（TV：一格 ±100 → 间距 ×1.1 / ×0.9）
//   · 鼠标下那根 K 线的 x 偏移（每一帧都量，取最大；TV 锚定在鼠标下那根）
//   · 平滑：中间帧数（既不是起点也不是终点的帧）与到位耗时（最后一个事件 → 落到终值）
//   · 右侧空白（根数与像素）
//   · 主图上 10 条画线时同样的量 + 动画期间每帧都整帧重画（画线跟着走）
//   · 四格时间联动：动画期间别的格子每帧跟上
// 只记数、不判对错的项打 ·；有硬指标的打 ✓ / ✗。结果写 /tmp/kp-wheel/wheel-<tag>.json。
import { spawn } from 'node:child_process'
import fs from 'node:fs'
import { launch, sleep } from './f-lib.mjs'
import { openCtx, seedAndOpen, baseState, geo, away } from './draw-lib.mjs'

const OUT = '/tmp/kp-wheel'
const DIST = process.env.WHEEL_DIST || `${OUT}/dist`
const PORT = +(process.env.WHEEL_PORT || 5306)
const TAG = process.env.WHEEL_TAG || 'after'
fs.mkdirSync(OUT, { recursive: true })

const R = [], DATA = {}
const ok = (name, pass, info = '') => { R.push({ name, pass: !!pass, info }); console.log(`${pass ? '✓' : '✗'} ${name}${info ? '  — ' + info : ''}`) }
const note = (name, info = '') => { R.push({ name, pass: null, info }); console.log(`· ${name}${info ? '  — ' + info : ''}`) }

function preview() {
  const srv = spawn(new URL('../node_modules/.bin/vite', import.meta.url).pathname, ['preview', '--port', String(PORT), '--strictPort', '--outDir', DIST], { cwd: new URL('..', import.meta.url).pathname, stdio: ['ignore', 'pipe', 'pipe'] })
  const stop = () => { try { srv.kill('SIGTERM') } catch { /* 已退 */ } }
  process.on('exit', stop); process.on('SIGINT', () => { stop(); process.exit(130) })
  return new Promise((res, rej) => {
    srv.stdout.on('data', d => { if (/localhost:/.test(String(d))) res({ url: `http://localhost:${PORT}/web/`, stop }) })
    srv.on('exit', c => rej(new Error('preview 退出 ' + c))); setTimeout(() => rej(new Error('preview 起不来')), 20000)
  })
}

// ───────── 页内采样器：每帧记一条；同时在捕获阶段记下滚轮事件的时间
const SAMPLER = () => {
  const W = (window.__wf = { s: null, ev: [], on: false })
  // 事件里的鼠标位置（相对画布）也记下：锚点按真实鼠标量，不按脚本算出来的小数坐标（差零点几 px 会被当成漂移）
  window.addEventListener('wheel', e => {
    if (!W.on) return
    const r = e.target?.getBoundingClientRect?.()
    W.ev.push({ t: performance.now(), dx: e.deltaX, dy: e.deltaY, mode: e.deltaMode, ctrl: e.ctrlKey, shift: e.shiftKey, x: r ? e.clientX - r.left : null, y: r ? e.clientY - r.top : null })
  }, { capture: true, passive: true })
  W.hook = ch => {
    if (ch.__wfHooked) return
    ch.__wfHooked = true; ch.__full = 0; ch.__light = 0
    const r = ch.render
    ch.render = function (light) { if (light) ch.__light++; else ch.__full++; return r.call(this, light) }
  }
  W.start = idxs => {
    const chs = idxs.map(i => window.__dx.ch(i)); chs.forEach(W.hook)
    W.s = []; W.ev = []; W.on = true
    const snap = () => chs.map(ch => {
      const m = ch.manual || ch._ranges?.main
      return { sp: ch.spacing, rb: ch.rightBar, last: ch.bars.length - 1, pw: ch.plotW(), min: m?.min ?? null, max: m?.max ?? null, full: ch.__full, light: ch.__light, nd: ch.drawings.length }
    })
    const loop = () => { if (!W.on) return; W.s.push({ t: performance.now(), c: snap() }); requestAnimationFrame(loop) }
    W.s.push({ t: performance.now(), c: snap() }); requestAnimationFrame(loop)
  }
  W.stop = () => { W.on = false; return { s: W.s, ev: W.ev, zoom: window.visualViewport?.scale ?? 1, dpr: window.devicePixelRatio } }
}

const EPS = 1e-6
/** 一组采样 → 指标。mx / my：鼠标在格内的坐标；ci：看第几块（start 时传的顺序） */
function analyse(run, { mx, my, k = 0, paneY = 0, paneH = 1, useEv = true }) {
  const S = run.s.map(x => ({ t: x.t, ...x.c[k] })), ev = run.ev
  if (useEv && ev[0]?.x != null) { mx = ev[0].x; my = ev[0].y }
  const t0 = ev.length ? ev[0].t : S[0].t, tLast = ev.length ? ev[ev.length - 1].t : S[0].t
  const before = [...S].reverse().find(x => x.t <= t0) ?? S[0], end = S[S.length - 1]
  const ratio = end.sp / before.sp
  // 鼠标下那根（连续下标）在每一帧的 x
  const idx0 = before.rb - (before.pw - mx) / before.sp
  const xOf = x => x.pw - (x.rb - idx0) * x.sp
  const after = S.filter(x => x.t >= t0)
  const drift = Math.abs(xOf(end) - mx), driftMax = Math.max(0, ...after.map(x => Math.abs(xOf(x) - mx)))
  const mid = after.filter(x => Math.abs(x.sp - before.sp) > EPS * before.sp && Math.abs(x.sp - end.sp) > EPS * end.sp).length
  const settleAt = after.find((x, i) => after.slice(i).every(y => Math.abs(y.sp - end.sp) <= EPS * end.sp && Math.abs(y.rb - end.rb) <= 1e-6))
  const settle = settleAt ? Math.max(0, settleAt.t - tLast) : NaN
  // 只能在帧边界上看到「到位」：上一帧还没到位、这一帧到了，真正落定在两帧之间；settleLo = 上一帧的时刻（最早可能落定的时间）
  const si = settleAt ? after.indexOf(settleAt) : -1
  const settleLo = si > 0 ? Math.max(0, after[si - 1].t - tLast) : settle
  // 单调（一个方向的手势里间距不来回抖）
  let flips = 0, dir = 0
  for (let i = 1; i < after.length; i++) {
    const diff = after[i].sp - after[i - 1].sp, d = Math.abs(diff) > 1e-9 * after[i].sp ? Math.sign(diff) : 0
    if (d && dir && d !== dir) flips++
    if (d) dir = d
  }
  const blank = x => ({ bars: x.rb - x.last, px: (x.rb - x.last) * x.sp })
  // 价格：鼠标 y 处的价格保持（线性轴）
  const yToP = (x, y) => x.max - (y - paneY - 8) / (paneH - 16) * (x.max - x.min)
  const priceSpan = before.max != null && end.max != null ? (end.max - end.min) / (before.max - before.min) : NaN
  const pAt0 = before.max != null ? yToP(before, my) : NaN
  const yDrift = end.max != null && Number.isFinite(pAt0) ? Math.abs((paneY + 8 + (end.max - pAt0) / (end.max - end.min) * (paneH - 16)) - my) : NaN
  // 帧间隔（动画期间）
  const dts = []; for (let i = 1; i < after.length; i++) if (after[i].t <= tLast + 200) dts.push(after[i].t - after[i - 1].t)
  dts.sort((a, b) => a - b)
  const full = end.full - before.full, light = end.light - before.light
  return {
    ratio, drift, driftMax, mid, settle, settleLo, flips, panPx: (end.rb - before.rb) * before.sp, rbMove: end.rb - before.rb,
    blank0: blank(before), blank1: blank(end), priceSpan, yDrift, full, light, frames: after.length,
    dtP50: dts[Math.floor(dts.length / 2)] ?? NaN, dtMax: dts[dts.length - 1] ?? NaN, events: ev.length, spacing0: before.sp, spacing1: end.sp, nd: end.nd,
  }
}

async function measureOp(page, idxs, fire, settleMs = 450) {
  await page.evaluate(ix => window.__wf.start(ix), idxs)
  await sleep(60)
  await fire()
  await sleep(settleMs)
  return page.evaluate(() => window.__wf.stop())
}

const f2 = (v, d = 3) => Number.isFinite(v) ? v.toFixed(d) : String(v)
// 无头 Chrome 在这台机器上 rAF 只有 15–30 帧（空白页也一样），2560 宽的图每帧还要画十几 ms：
// 「中间帧 ≥ 3」按 60 帧算（单元测试 tests/wheel-zoom.test.ts 用虚拟时钟验），这里按实测帧间隔折算——120 ms 的动画里能落几帧就要几帧（最多 3）；
// 到位按「最早可能落定的时刻」（上一帧还在动）≤ 150 ms 判
const ZOOM_MS = 120
// 应有中间帧 = max(1, floor(120 / 帧间隔 p50) − 1)，封顶 3：无头 Chrome 帧间隔 15–150 ms 不等，减 1 是给首帧落在 rAF 之前留余量
const needMid = a => Math.max(1, Math.min(3, Math.floor(ZOOM_MS / (a.dtP50 || 16.7)) - 1))
const smooth = a => a.mid >= needMid(a) && a.settleLo <= 150
const smoothInfo = a => `中间帧 ${a.mid}（此帧率下应 ≥ ${needMid(a)}）、到位 ${f2(a.settleLo, 0)}–${f2(a.settle, 0)} ms、帧间隔 p50 ${f2(a.dtP50, 1)} ms`

async function main() {
  const { url, stop } = await preview()
  const browser = await launch()
  try {
    const env = await openCtx(browser, url, { viewport: { width: 2560, height: 1440 } })
    await env.ctx.addInitScript(SAMPLER)
    const { page } = env
    await seedAndOpen(env, baseState({ cells: [{ symbol: 'BTCUSDT', iv: '1h' }], ind: { ma: true, ema: false, boll: false, vol: true, subs: ['macd'] } }))
    await page.evaluate(() => { if (!window.__wf) { /* addInitScript 在 seedAndOpen 之前已注入 */ } })
    const g = await geo(page, 0)
    const C = { x: g.left + g.plotW * 0.5, y: g.top + g.pane.y + g.pane.h * 0.5 }
    const mx = g.plotW * 0.5, my = g.pane.y + g.pane.h * 0.5
    const reset = async () => { await page.evaluate(() => { const ch = window.__dx.ch(0); ch.resetView(); ch.dirty = true }); await sleep(250) }
    console.log(`\n== ${TAG}：一图 BTCUSDT 1h，绘图区 ${g.plotW}×${g.pane.h}，初始间距 ${g.spacing}`)
    DATA.init = { spacing: g.spacing, plotW: g.plotW }

    const rows = {}
    const run = async (name, fire, opt = {}) => {
      if (opt.reset !== false) await reset()
      const r = await measureOp(page, opt.idxs ?? [0], fire, opt.settle)
      const a = analyse(r, { mx: opt.mx ?? mx, my: opt.my ?? my, paneY: g.pane.y, paneH: g.pane.h, k: opt.k ?? 0, useEv: opt.mx == null })
      a.browserZoom = r.zoom
      rows[name] = a
      return a
    }

    // 1 鼠标一格（deltaMode 0，±100）
    const notchIn = await run('滚轮一格放大', async () => { await page.mouse.move(C.x, C.y); await page.mouse.wheel(0, -100) })
    const notchOut = await run('滚轮一格缩小', async () => { await page.mouse.move(C.x, C.y); await page.mouse.wheel(0, 100) })
    note('滚轮一格：缩放比例', `放大 ×${f2(notchIn.ratio, 4)}（TV ×1.1），缩小 ×${f2(notchOut.ratio, 4)}（TV ×0.9）`)
    ok('滚轮一格：每格比例 = TV（放大 1.1、缩小 0.9，误差 < 0.5%）', Math.abs(notchIn.ratio - 1.1) < 0.0055 && Math.abs(notchOut.ratio - 0.9) < 0.0045, `${f2(notchIn.ratio, 4)} / ${f2(notchOut.ratio, 4)}`)
    ok('滚轮一格：鼠标下那根 K 线不动（每一帧 < 0.5 px）', notchIn.driftMax < 0.5 && notchOut.driftMax < 0.5, `终值偏 ${f2(notchIn.drift)} / ${f2(notchOut.drift)} px，过程中最大 ${f2(notchIn.driftMax)} / ${f2(notchOut.driftMax)} px`)
    ok('滚轮一格：平滑（有中间帧、停手 ≤ 150 ms 到位）', smooth(notchIn) && smooth(notchOut), `放大：${smoothInfo(notchIn)}；缩小：${smoothInfo(notchOut)}`)
    note('滚轮一格：右侧空白', `放大前 ${f2(notchIn.blank0.bars, 2)} 根 ${f2(notchIn.blank0.px, 1)} px → 后 ${f2(notchIn.blank1.bars, 2)} 根 ${f2(notchIn.blank1.px, 1)} px`)

    // 2 连续三格（累加目标）
    const three = await run('滚轮连续三格放大', async () => { await page.mouse.move(C.x, C.y); for (let i = 0; i < 3; i++) { await page.mouse.wheel(0, -100); await sleep(30) } })
    ok('连续三格：目标累加（×1.1³ = 1.331，误差 < 1%）、不来回抖、最后一格后 ≤ 150 ms 到位', Math.abs(three.ratio - 1.331) < 0.0133 && three.flips === 0 && three.settleLo <= 150, `×${f2(three.ratio, 4)}，${smoothInfo(three)}，来回抖 ${three.flips} 次`)
    ok('连续三格：锚点不动（< 0.5 px）', three.driftMax < 0.5, `最大偏 ${f2(three.driftMax)} px`)

    // 3 触控板：20 次 ±4（像素级小量）
    const tpIn = await run('触控板 20×(-4)', async () => { await page.mouse.move(C.x, C.y); for (let i = 0; i < 20; i++) { await page.mouse.wheel(0, -4); await sleep(10) } })
    const tpOut = await run('触控板 20×(+4)', async () => { await page.mouse.move(C.x, C.y); for (let i = 0; i < 20; i++) { await page.mouse.wheel(0, 4); await sleep(10) } })
    note('触控板 20 次 ±4：总比例', `放大 ×${f2(tpIn.ratio, 4)}、缩小 ×${f2(tpOut.ratio, 4)}（TV：(1±0.004)^20 = ${f2(1.004 ** 20, 4)} / ${f2(0.996 ** 20, 4)}）`)
    ok('触控板：锚点不动、不来回抖', tpIn.driftMax < 0.5 && tpOut.driftMax < 0.5 && tpIn.flips === 0 && tpOut.flips === 0, `偏 ${f2(tpIn.driftMax)} / ${f2(tpOut.driftMax)} px，抖 ${tpIn.flips} / ${tpOut.flips}`)

    // 4 Ctrl + 滚轮（一格）与捏合（ctrl + 小量）
    const ctrl = await run('Ctrl+滚轮一格', async () => { await page.mouse.move(C.x, C.y); await page.keyboard.down('Control'); await page.mouse.wheel(0, -100); await page.keyboard.up('Control') })
    const pinch = await run('捏合 20×(ctrl,-3)', async () => { await page.mouse.move(C.x, C.y); await page.keyboard.down('Control'); for (let i = 0; i < 20; i++) { await page.mouse.wheel(0, -3); await sleep(10) } await page.keyboard.up('Control') })
    ok('Ctrl+滚轮：缩放图表、浏览器不缩放', ctrl.ratio > 1.01 && ctrl.browserZoom === 1, `×${f2(ctrl.ratio, 4)}，页面缩放 ${ctrl.browserZoom}，锚点偏 ${f2(ctrl.driftMax)} px`)
    note('捏合（ctrl + 20×-3）', `×${f2(pinch.ratio, 4)}（手指 ×${f2(Math.exp(0.6), 3)}），锚点偏 ${f2(pinch.driftMax)} px`)

    // 5 Shift + 滚轮 / 触控板横滑
    const shift = await run('Shift+滚轮一格', async () => { await page.mouse.move(C.x, C.y); await page.keyboard.down('Shift'); await page.mouse.wheel(0, 100); await page.keyboard.up('Shift') })
    const hx = await run('横滑一格 deltaX=100', async () => { await page.mouse.move(C.x, C.y); await page.mouse.wheel(100, 0) })
    ok('Shift+滚轮：横向平移、不缩放', Math.abs(shift.ratio - 1) < EPS && Math.abs(shift.panPx) > 10, `平移 ${f2(shift.panPx, 1)} px（TV 80 px），间距 ×${f2(shift.ratio, 4)}`)
    ok('横滑 deltaX=100：平移 80 px（TV 系数 0.8）、不缩放、不加惯性', Math.abs(Math.abs(hx.panPx) - 80) < 1 && Math.abs(hx.ratio - 1) < EPS && hx.settle <= 20, `平移 ${f2(hx.panPx, 1)} px，到位 ${f2(hx.settle, 0)} ms`)

    // 6 价格轴上滚轮：纵向缩放价格，锚在鼠标 y
    const ax = g.left + g.plotW + Math.max(30, (g.w - g.plotW) * 0.7), ay = g.top + g.pane.y + g.pane.h * 0.3
    const pAxis = await run('价格轴上滚轮一格（缩小）', async () => { await page.mouse.move(ax, ay); await page.mouse.wheel(0, 100) }, { my: g.pane.y + g.pane.h * 0.3, mx: g.plotW })
    await page.evaluate(() => window.__dx.ch(0).setAuto(true)); await sleep(150)
    ok('价格轴上滚轮：只缩价格、时间轴不动、鼠标处价格不动', Math.abs(pAxis.ratio - 1) < EPS && Math.abs(pAxis.priceSpan - 1) > 0.02 && pAxis.yDrift < 0.5, `价格跨度 ×${f2(pAxis.priceSpan, 4)}，间距 ×${f2(pAxis.ratio, 4)}，鼠标处价格偏 ${f2(pAxis.yDrift)} px`)

    // 7 时间轴上滚轮：横向缩放、锚在右沿
    const tx = g.left + g.plotW * 0.3, ty = g.top + g.h - 10
    const tAxis = await run('时间轴上滚轮一格（缩小）', async () => { await page.mouse.move(tx, ty); await page.mouse.wheel(0, 100) }, { mx: g.plotW })
    ok('时间轴上滚轮：缩放时间、锚在右沿（右沿下标不动、右侧空白根数不变）', Math.abs(tAxis.ratio - 0.9) < 0.0045 && Math.abs(tAxis.rbMove) < 1e-6, `×${f2(tAxis.ratio, 4)}，右沿挪 ${f2(tAxis.rbMove, 4)} 根，空白 ${f2(tAxis.blank0.bars, 2)} → ${f2(tAxis.blank1.bars, 2)} 根（${f2(tAxis.blank0.px, 1)} → ${f2(tAxis.blank1.px, 1)} px）`)

    // 8 Alt + 滚轮：纵向缩放（保留）
    const alt = await run('Alt+滚轮一格', async () => { await page.mouse.move(C.x, C.y); await page.keyboard.down('Alt'); await page.mouse.wheel(0, 100); await page.keyboard.up('Alt') })
    await page.evaluate(() => window.__dx.ch(0).setAuto(true)); await sleep(150)
    ok('Alt+滚轮：纵向缩放价格、时间不动', Math.abs(alt.ratio - 1) < EPS && Math.abs(alt.priceSpan - 1) > 0.02, `价格跨度 ×${f2(alt.priceSpan, 4)}，间距 ×${f2(alt.ratio, 4)}`)

    // 9 deltaMode 1（按行：Firefox / Windows 鼠标）：合成事件
    const line = await run('按行滚动一格（deltaMode 1，deltaY 3）', async () => {
      await page.mouse.move(C.x, C.y)
      await page.evaluate(([x, y]) => { const cv = document.elementFromPoint(x, y); cv.dispatchEvent(new WheelEvent('wheel', { deltaY: -3, deltaMode: 1, clientX: x, clientY: y, bubbles: true, cancelable: true })) }, [C.x, C.y])
    })
    ok('按行滚动一格（3 行）：TV 折 3×32/100 = 0.96 档 → ×1.096', Math.abs(line.ratio - 1.096) < 0.001, `×${f2(line.ratio, 4)}`)

    // 10 上下限：一路缩小 / 放大到头
    await reset()
    await page.mouse.move(C.x, C.y)
    for (let i = 0; i < 60; i++) { await page.mouse.wheel(0, 100); await sleep(8) }
    await sleep(300)
    const lo = await page.evaluate(() => window.__dx.ch(0).spacing)
    for (let i = 0; i < 80; i++) { await page.mouse.wheel(0, -100); await sleep(8) }
    await sleep(300)
    const hi = await page.evaluate(() => window.__dx.ch(0).spacing)
    ok('间距上下限 = TV（0.5 – 50 px）', Math.abs(lo - 0.5) < 1e-6 && Math.abs(hi - 50) < 1e-6, `最密 ${f2(lo, 3)} px，最疏 ${f2(hi, 3)} px`)
    DATA.limits = { lo, hi }
    // 最密档还看得清：K 线区里有画出来的像素（不是空白、不是糊成一块）
    await page.evaluate(() => { const ch = window.__dx.ch(0); ch.spacing = 0.5; ch.rightBar = ch.bars.length - 1 + 10; ch.dirty = true }); await away(page); await sleep(300)
    await page.screenshot({ path: `${OUT}/densest-${TAG}.png`, clip: { x: g.left, y: g.top, width: g.w, height: g.pane.h } })
    await reset()

    // 11 画线交叉：10 条画线在图上时同样量
    await page.evaluate(() => {
      const ch = window.__dx.ch(0), n = ch.bars.length, b = ch.bars
      const mk = (k) => ({ id: 'wf' + k, type: 'trend', pts: [{ t: b[n - 120 + k * 8].t, p: b[n - 120 + k * 8].l }, { t: b[n - 60 + k * 5].t, p: b[n - 60 + k * 5].h }], color: '#D500F9', width: 2 })
      ch.drawings = Array.from({ length: 10 }, (_, k) => mk(k)); ch.dirty = true
    })
    await sleep(200)
    const dIn = await run('10 条画线：滚轮一格放大', async () => { await page.mouse.move(C.x, C.y); await page.mouse.wheel(0, -100) })
    const dTp = await run('10 条画线：触控板 20×(-4)', async () => { await page.mouse.move(C.x, C.y); for (let i = 0; i < 20; i++) { await page.mouse.wheel(0, -4); await sleep(10) } })
    ok('10 条画线：比例、锚点与无画线时一致', Math.abs(dIn.ratio - notchIn.ratio) < 1e-6 && dIn.driftMax < 0.5 && Math.abs(dTp.ratio - tpIn.ratio) < 0.002, `一格 ×${f2(dIn.ratio, 4)}、触控板 ×${f2(dTp.ratio, 4)}，锚点偏 ${f2(dIn.driftMax)} px`)
    ok('10 条画线：动画每一帧都整帧重画（画线跟着走）、条数不变', dIn.full >= dIn.mid && dIn.nd === 10, `整帧 ${dIn.full}、中间帧 ${dIn.mid}、帧间隔 p50 ${f2(dIn.dtP50, 1)} ms / max ${f2(dIn.dtMax, 1)} ms、画线 ${dIn.nd} 条`)
    const geoOk = await page.evaluate(() => {
      const ch = window.__dx.ch(0), p = ch._panes[0], r = ch._ranges.main
      return ch.drawings.every(d => d.pts.every(q => Number.isFinite(ch.indexToX(ch.indexAt(q.t))) && Number.isFinite(ch.priceToY(q.p, p, r))))
    })
    ok('10 条画线：缩放后锚点都还能投到像素', geoOk)

    // 12 四格时间联动：动画期间别的格子每帧跟上
    await seedAndOpen(env, baseState({ layout: '4', linkTime: true, cells: [{ symbol: 'BTCUSDT', iv: '1h' }, { symbol: 'ETHUSDT', iv: '1h' }, { symbol: 'SOLUSDT', iv: '1h' }, { symbol: 'BNBUSDT', iv: '1h' }] }))
    await page.waitForFunction(() => window.__cells().length === 4 && window.__cells().every(c => c.bars > 0), null, { timeout: 45000 })
    await sleep(600)
    const g4 = await geo(page, 0)
    const C4 = { x: g4.left + g4.plotW * 0.5, y: g4.top + g4.pane.y + g4.pane.h * 0.5 }
    await page.mouse.move(C4.x, C4.y); await page.mouse.click(C4.x, C4.y); await sleep(200)
    const lk = await measureOp(page, [0, 1], async () => { await page.mouse.move(C4.x, C4.y); await page.mouse.wheel(0, -100) })
    const lag = lk.s.filter(x => x.t >= (lk.ev[0]?.t ?? 0)).map(x => Math.abs(x.c[0].sp - x.c[1].sp) / x.c[0].sp)
    const midA = analyse(lk, { mx: g4.plotW * 0.5, my: 0, k: 0 }), midB = analyse(lk, { mx: g4.plotW * 0.5, my: 0, k: 1, useEv: false })
    // 联动按同样的折算口径：应有中间帧 = max(1, floor(120 / 帧间隔 p50) − 1)，和 needMid 一样封顶 3（帧率高时 p50 只有 7–8 ms，
    // 不封顶会要 14 帧，而单测口径就是 ≥ 3）；且第二格与第一格中间帧数相同（每帧都跟上）
    const needLink = Math.min(3, Math.max(1, Math.floor(ZOOM_MS / (midA.dtP50 || 16.7)) - 1))
    ok('四格时间联动：动画期间第二格每帧同一间距（相对差 < 1%）、也有中间帧', Math.max(0, ...lag) < 0.01 && midA.mid >= needLink && midB.mid === midA.mid, `最大相对差 ${f2(Math.max(0, ...lag) * 100, 2)}%，第一格中间帧 ${midA.mid}、第二格中间帧 ${midB.mid}（此帧率下应 ≥ ${needLink}、帧间隔 p50 ${f2(midA.dtP50, 1)} ms）`)
    rows['四格联动'] = { a: midA, b: midB, lagMax: Math.max(0, ...lag) }
    const errs = env.errors.filter(x => !/Failed to load resource|net::ERR|ERR_FAILED|WebSocket|status of [45]\d\d|blocked by CORS/.test(x))
    ok('控制台无报错', !errs.length, errs.slice(0, 3).join(' | '))

    DATA.rows = rows
    console.log('\n表：项目 | 比例 | 锚点偏(终/最大 px) | 中间帧 | 到位 ms(最早–看到) | 帧间隔 p50 ms | 平移 px | 价格跨度 | 右空白(根→根)')
    for (const [k, a] of Object.entries(rows)) if (a.ratio != null) console.log(`${k} | ×${f2(a.ratio, 4)} | ${f2(a.drift, 2)}/${f2(a.driftMax, 2)} | ${a.mid} | ${f2(a.settleLo, 0)}–${f2(a.settle, 0)} | ${f2(a.dtP50, 1)} | ${f2(a.panPx, 1)} | ${f2(a.priceSpan, 4)} | ${f2(a.blank0.bars, 2)}→${f2(a.blank1.bars, 2)}`)
    await env.ctx.close()
  } finally {
    await browser.close(); stop()
    fs.writeFileSync(`${OUT}/wheel-${TAG}.json`, JSON.stringify({ at: new Date().toISOString(), results: R, data: DATA }, null, 1))
  }
  const fail = R.filter(r => r.pass === false).length
  console.log(`\n${R.filter(r => r.pass).length} ✓ · ${fail} ✗ · ${R.filter(r => r.pass === null).length} 只记数`)
  process.exit(fail ? 1 : 0)
}
main().catch(e => { console.error(e); process.exit(2) })
