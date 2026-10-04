// 手机网页版 · 图表引擎满载手势压测（深度审查 Web D 线，2026-10-05）
//   npx vite --port 5197 后 node scripts/m-chart-perf.mjs [地址] [CPU 降速倍数，默认 4] [轮数，默认 3]
//   打开 src/m/chart/bench.html（离线合成：6000 根 1m + VOL/MACD/RSI + 30 条画线 + 约 2400 单主力订单流），
//   手机视口 402×874、DPR 3、触屏；分三段各做若干轮：横甩（单指平移 + 惯性）、双指捏合、长按出十字线后拎着走。
//   每段报：主线程长任务（≥ 50 ms）个数与合计、主线程任务 CPU 时间（CDP TaskDuration 差）、脚本时间、
//   rAF 帧数与超 16.7 / 33 ms 的帧数。一次只开一个浏览器，跑完关掉。
import { chromium } from 'playwright-core'
const URL_ = process.argv[2] || 'http://localhost:5197/web/src/m/chart/bench.html'
const RATE = Number(process.argv[3] || 4)
const ROUNDS = Number(process.argv[4] || 3)
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const sleep = ms => new Promise(r => setTimeout(r, ms))
const browser = await chromium.launch({ executablePath: CHROME, headless: true })
try {
  const ctx = await browser.newContext({ viewport: { width: 402, height: 874 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true, locale: 'zh-CN', timezoneId: 'Asia/Shanghai' })
  await ctx.addInitScript(() => {
    window.__lt = []
    new PerformanceObserver(l => { for (const e of l.getEntries()) window.__lt.push(e.duration) }).observe({ type: 'longtask', buffered: true })
    window.__frames = []
    window.__cb = []
    const raf = window.requestAnimationFrame.bind(window)
    window.requestAnimationFrame = cb => raf(t => { const a = performance.now(); try { cb(t) } finally { window.__cb.push(performance.now() - a) } })
    let last = 0
    const tick = t => { if (last) window.__frames.push(t - last); last = t; raf(tick) }
    requestAnimationFrame(tick)
  })
  const p = await ctx.newPage()
  const errs = []; p.on('pageerror', e => errs.push(e.message))
  await p.goto(URL_)
  await p.waitForFunction(() => window.benchReady && window.benchReady(), null, { timeout: 30000 })
  await sleep(1500)
  const cdp = await ctx.newCDPSession(p)
  await cdp.send('Performance.enable')
  if (RATE > 1) await cdp.send('Emulation.setCPUThrottlingRate', { rate: RATE })
  const box = await (await p.$('#bench .m-chart')).boundingBox()
  const touch = (type, pts) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: pts.map((q, i) => ({ x: q[0], y: q[1], id: i })) })
  const metrics = async () => Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map(x => [x.name, x.value]))
  const phase = async (name, run) => {
    await p.evaluate(() => { window.__lt.length = 0; window.__frames.length = 0; window.__cb.length = 0 })
    const a = await metrics()
    const t0 = Date.now()
    for (let r = 0; r < ROUNDS; r++) await run(r)
    await sleep(600)
    const wall = Date.now() - t0
    const b = await metrics()
    const { lt, frames, cb } = await p.evaluate(() => ({ lt: window.__lt.slice(), frames: window.__frames.slice(), cb: window.__cb.filter(x => x > 0.05).sort((a, b) => a - b) }))
    const q = f => cb.length ? Math.round(cb[Math.min(cb.length - 1, Math.floor(cb.length * f))] * 10) / 10 : 0
    const out = {
      段: name, 墙钟ms: wall,
      长任务: lt.length, 长任务合计ms: Math.round(lt.reduce((s, x) => s + x, 0)), 最长ms: Math.round(Math.max(0, ...lt)),
      主线程CPUms: Math.round((b.TaskDuration - a.TaskDuration) * 1000), 脚本ms: Math.round((b.ScriptDuration - a.ScriptDuration) * 1000),
      布局ms: Math.round((b.LayoutDuration - a.LayoutDuration) * 1000),
      绘帧: cb.length, 绘帧p50ms: q(0.5), 绘帧p95ms: q(0.95), 绘帧最长ms: q(1), 绘帧超8ms: cb.filter(x => x > 8).length, 绘帧超16ms: cb.filter(x => x > 16.7).length,
      帧: frames.length, 超16ms帧: frames.filter(f => f > 17.5).length, 超33ms帧: frames.filter(f => f > 34).length,
    }
    console.log(JSON.stringify(out))
    return out
  }
  const cx = box.x + box.width * 0.45, cy = box.y + box.height * 0.3
  const results = []
  // 1. 横甩：单指从右往左拖 240 点再往回，最后一下快甩起惯性
  results.push(await phase('横甩', async r => {
    await touch('touchStart', [[cx + 100, cy]])
    for (let i = 1; i <= 60; i++) { await touch('touchMove', [[cx + 100 - i * 4, cy]]); await sleep(16) }
    for (let i = 1; i <= 60; i++) { await touch('touchMove', [[cx - 140 + i * 4, cy]]); await sleep(16) }
    for (let i = 1; i <= 6; i++) { await touch('touchMove', [[cx + 100 - i * 25, cy]]); await sleep(16) }
    await touch('touchEnd', []); await sleep(900 + r * 0)
  }))
  // 2. 捏合：两指张开再合拢
  results.push(await phase('捏合', async () => {
    await touch('touchStart', [[cx - 30, cy], [cx + 30, cy]])
    for (let i = 1; i <= 50; i++) { await touch('touchMove', [[cx - 30 - i * 2, cy], [cx + 30 + i * 2, cy]]); await sleep(16) }
    for (let i = 1; i <= 50; i++) { await touch('touchMove', [[cx - 130 + i * 2, cy], [cx + 130 - i * 2, cy]]); await sleep(16) }
    await touch('touchEnd', []); await sleep(300)
  }))
  // 3. 十字线：长按出线，拎着横竖走一圈，抬手，轻点收起
  results.push(await phase('十字线', async () => {
    await touch('touchStart', [[cx, cy]]); await sleep(550)
    for (let i = 1; i <= 50; i++) { await touch('touchMove', [[cx + i * 2, cy + i]]); await sleep(16) }
    for (let i = 1; i <= 50; i++) { await touch('touchMove', [[cx + 100 - i * 4, cy + 50 - i * 2]]); await sleep(16) }
    await touch('touchEnd', []); await sleep(200)
    await touch('touchStart', [[cx - 100, cy - 50]]); await sleep(30); await touch('touchEnd', []); await sleep(300)
  }))
  if (errs.length) { console.log('页面错误', errs); process.exitCode = 1 }
  console.log('合计', JSON.stringify({ 降速: RATE, 轮数: ROUNDS, 长任务: results.reduce((s, x) => s + x.长任务, 0), 主线程CPUms: results.reduce((s, x) => s + x.主线程CPUms, 0) }))
} finally {
  await browser.close()
}
