// 手机网页版 · 指标布局跟人走的端到端检查（2026-10-03）：在 1 小时加副图 KDJ、主图 BOLL，拖最下面那块副图的下沿、
// 双指捏开放大，然后切 4 小时、5 分、日线、回 1 小时、刷新，指标 / 副图高度 / 根宽必须一模一样，且不留按周期的分叉。
//   npx vite --port 5190 后 node scripts/m-layout-e2e.mjs（本机来源会被线上接口的 CORS 拦，所以无头 Chrome 关掉同源检查）
//   截图落在 /tmp/m-layout-e2e/；有不一致退出码 1
import { chromium } from 'playwright-core'
import { mkdirSync } from 'node:fs'
const URL_ = process.argv[2] || 'http://localhost:5190/web/m/'
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const sleep = ms => new Promise(r => setTimeout(r, ms))
const out = '/tmp/m-layout-e2e'; mkdirSync(out, { recursive: true })
const b = await chromium.launch({ executablePath: CHROME, headless: true, args: ['--disable-web-security'] })
const ctx = await b.newContext({ viewport: { width: 402, height: 874 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true, locale: 'zh-CN', timezoneId: 'Asia/Shanghai' })
const p = await ctx.newPage()
const errs = []; p.on('pageerror', e => errs.push(e.message))
const prefs = () => p.evaluate(() => { const s = JSON.parse(localStorage.getItem('hkline-m-v1') || '{}'); const x = s.prefs || s; return { interval: x.interval, subs: x.subs, overlays: x.overlays, h: x.subHeightOverrides, bs: x.barSpacing, layouts: x.indicatorLayouts, params: x.params?.MACD } })
const pick = async iv => { await p.click(`.cp-chip[data-iv="${iv}"]`).catch(async () => { await p.evaluate(iv => document.querySelector(`[data-iv="${iv}"]`)?.click(), iv) }); await sleep(900) }
await p.goto(URL_ + '#/chart'); await p.waitForFunction(() => !document.body.innerText.includes("暂时取不到"), null, { timeout: 15000 }).catch(() => {}); await sleep(4000)
console.log('出厂', JSON.stringify(await prefs()))
await p.screenshot({ path: `${out}/0-出厂.png` })
const ivs = await p.$$eval('.cp-chip[data-iv]', a => a.map(x => x.dataset.iv)); console.log('周期条', ivs)
await pick('1h')
// 开分析面板加 KDJ、BOLL
await p.click('.cp-tail:has-text("分析")'); await sleep(700)
for (const a of ['sub:KDJ', 'ov:BOLL']) await p.evaluate(a => document.querySelector(`[data-act="${a}"]`)?.click(), a)
await sleep(300); await p.evaluate(() => document.querySelector('.m-sheet-scrim')?.click()); await sleep(700)
// 拖最下面那块副图的下沿往下
const box = await (await p.$('.cp-chart canvas')).boundingBox()
const cdp = await ctx.newCDPSession(p)
const touch = async (type, pts) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: pts.map((q, i) => ({ x: q[0], y: q[1], id: i })) })
const y0 = box.y + box.height - 6, x0 = box.x + box.width / 2
await touch('touchStart', [[x0, y0]]); for (let i = 1; i <= 10; i++) { await touch('touchMove', [[x0, y0 + i * 6]]); await sleep(16) } await touch('touchEnd', []); await sleep(500)
// 双指捏开放大
const cy = box.y + box.height * 0.3
await touch('touchStart', [[x0 - 30, cy], [x0 + 30, cy]]); for (let i = 1; i <= 10; i++) { await touch('touchMove', [[x0 - 30 - i * 8, cy], [x0 + 30 + i * 8, cy]]); await sleep(16) } await touch('touchEnd', []); await sleep(800)
const after = await prefs(); console.log('1 小时改完', JSON.stringify(after))
await p.screenshot({ path: `${out}/1-1h改完.png` })
let bad = 0
const same = (a, label) => { const ok = JSON.stringify([a.subs, a.overlays, a.h, a.bs, a.params]) === JSON.stringify([after.subs, after.overlays, after.h, after.bs, after.params]) && JSON.stringify(a.layouts ?? {others:{}}) === '{"others":{}}'; if (!ok) bad++; console.log(ok ? '✓' : '✗', label, JSON.stringify(a)) }
for (const iv of ['4h', '5m', '1d', '1h']) { if (!ivs.includes(iv)) continue; await pick(iv); same(await prefs(), `切到 ${iv}`); await p.screenshot({ path: `${out}/2-${iv}.png` }) }
await p.reload(); await p.waitForFunction(() => !document.body.innerText.includes("暂时取不到"), null, { timeout: 15000 }).catch(() => {}); await sleep(4000); same(await prefs(), '刷新之后')
await p.screenshot({ path: `${out}/3-刷新.png` })
console.log(errs.length ? '页面错误：' + errs.join(' | ') : '无页面错误', bad ? `✗ ${bad} 处不一致` : '✓ 全部一致')
await b.close(); process.exit(bad ? 1 : 0)
