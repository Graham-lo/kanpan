// 手机网页版 · 十字线跟手的端到端检查（2026-10-03）：轻点图上空白处出十字线，然后按住十字线竖着拖，
// 横线（价格线）必须跟着手指走、一路不跳；再贴着交叉点几个点内微调，十字线不许被当成轻点收掉。
//   npx vite --port 5196 后 node scripts/m-crosshair-e2e.mjs（本机来源会被线上接口的 CORS 拦，所以无头 Chrome 关掉同源检查）
//   每一步打印「手指 y / 横线 y」，有不跟手或跳动退出码 1
import { chromium } from 'playwright-core'
const URL_ = process.argv[2] || 'http://localhost:5196/web/m/'
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const sleep = ms => new Promise(r => setTimeout(r, ms))
const b = await chromium.launch({ executablePath: CHROME, headless: true, args: ['--disable-web-security'] })
const ctx = await b.newContext({ viewport: { width: 402, height: 874 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true, locale: 'zh-CN', timezoneId: 'Asia/Shanghai' })
const p = await ctx.newPage()
const errs = []; p.on('pageerror', e => errs.push(e.message))
await p.goto(URL_ + '#/chart'); await p.waitForFunction(() => !document.body.innerText.includes('暂时取不到'), null, { timeout: 15000 }).catch(() => {}); await sleep(4000)
const box = await (await p.$('.cp-chart .m-chart')).boundingBox()
const cdp = await ctx.newCDPSession(p)
const touch = async (type, pts) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: pts.map((q, i) => ({ x: q[0], y: q[1], id: i })) })
// 十字线层上虚线最密的那一行 / 那一列就是横线 / 竖线（点，相对图表左上角）
// 没有十字线时这一层也有别的东西（副图图例、分隔处的签），先记下那时的行 / 列，后面排除掉
let base = { rows: [], cols: [] }
const cross = () => p.evaluate(base => {
  const c = document.querySelector('.cp-chart canvas[data-part="4"]')
  const s = c.width / c.clientWidth, W = c.width, H = c.height
  const d = c.getContext('2d').getImageData(0, 0, W, H).data
  const plotW = Math.floor(W * 0.8)
  let by = -1, bn = 0, bx = -1, bm = 0
  const rows = [], cols = []
  for (let y = 0; y < H; y++) { let n = 0; for (let x = 0; x < plotW; x++) if (d[(y * W + x) * 4 + 3] > 40) n++; if (n > plotW * 0.3) rows.push(y); if (n > bn && !base.rows.includes(y)) { bn = n; by = y } }
  for (let x = 0; x < plotW; x++) { let n = 0; for (let y = 0; y < H; y++) if (d[(y * W + x) * 4 + 3] > 40) n++; if (n > H * 0.3) cols.push(x); if (n > bm && !base.cols.includes(x)) { bm = n; bx = x } }
  return { hit: bn > plotW * 0.3 ? { x: bx / s, y: by / s } : null, rows, cols }
}, base).then(r => { cross.raw = r; return r.hit })
await cross(); base = { rows: cross.raw.rows, cols: cross.raw.cols }
let bad = 0
const x0 = box.x + box.width * 0.45, y0 = box.y + box.height * 0.25
await touch('touchStart', [[x0, y0]]); await sleep(30); await touch('touchEnd', []); await sleep(300)
const c0 = await cross()
console.log('轻点', JSON.stringify({ 手指: y0 - box.y, 十字线: c0 }))
if (!c0) { console.log('✗ 轻点没出十字线'); process.exit(1) }
if (Math.abs(c0.y - (y0 - box.y)) > 2) { bad++; console.log('✗ 轻点出来的横线不在手指那一行') }
// 按在交叉点右下 12 点处，竖着往下拖 80 点：横线要和手指保持按下时的那段距离一起走
const gx = box.x + c0.x + 12, gy = box.y + c0.y + 12
await touch('touchStart', [[gx, gy]]); await sleep(30)
let prev = c0.y, maxJump = 0, maxLag = 0
for (let i = 1; i <= 40; i++) {
  await touch('touchMove', [[gx + (i % 3) * 0.7, gy + i * 2]]); await sleep(20)
  const c = await cross(); if (!c) { bad++; console.log('✗ 拖着拖着十字线没了', i); break }
  const want = c0.y + i * 2
  maxLag = Math.max(maxLag, Math.abs(c.y - want)); maxJump = Math.max(maxJump, Math.abs(c.y - prev)); prev = c.y
  if (i % 8 === 0) console.log(`  手指下移 ${i * 2} 点 → 横线 ${c.y.toFixed(1)}（应在 ${want.toFixed(1)}）`)
}
await touch('touchEnd', []); await sleep(300)
console.log('拖动', JSON.stringify({ 最大偏离: +maxLag.toFixed(1), 单步最大跳: +maxJump.toFixed(1) }))
if (maxLag > 2.5) { bad++; console.log('✗ 横线不跟手') }
if (maxJump > 5) { bad++; console.log('✗ 横线有跳动') }
// 微调：按住交叉点往上挪 5 点再松手，十字线要留在新位置，不能被当成轻点收掉
const c1 = await cross()
await touch('touchStart', [[box.x + c1.x, box.y + c1.y]]); await sleep(30)
for (let i = 1; i <= 5; i++) { await touch('touchMove', [[box.x + c1.x, box.y + c1.y - i]]); await sleep(20) }
await touch('touchEnd', []); await sleep(300)
const c2 = await cross()
console.log('微调 5 点', JSON.stringify({ 之前: c1?.y, 之后: c2?.y }))
if (!c2) { bad++; console.log('✗ 微调把十字线收掉了') } else if (Math.abs(c2.y - (c1.y - 5)) > 2.5) { bad++; console.log('✗ 微调没挪到位') }
// 轻点交叉点（不挪）照旧收起
await touch('touchStart', [[box.x + c2.x, box.y + c2.y]]); await sleep(30); await touch('touchEnd', []); await sleep(300)
// 收起后这一层还剩副图的签之类，只要原来那条横线不在了就算收起
const c3 = await cross(); if (c3 && Math.abs(c3.y - c2.y) < 3) { bad++; console.log("✗ 轻点十字线没收起", JSON.stringify(c3)) } else console.log('✓ 轻点十字线收起')
// 按在横线上离交叉点很远的地方（图左边）竖着往上拖 60 点：价格线跟着走；横着拖照旧是拖图
await touch('touchStart', [[x0, y0 + 100]]); await sleep(30); await touch('touchEnd', []); await sleep(400)
const c4 = await cross()
const lx = box.x + 30, ly = box.y + c4.y + 6
await touch('touchStart', [[lx, ly]]); await sleep(30)
for (let i = 1; i <= 30; i++) { await touch('touchMove', [[lx, ly - i * 2]]); await sleep(16) }
await touch('touchEnd', []); await sleep(300)
const c5 = await cross()
console.log('按在横线远端竖拖 60 点', JSON.stringify({ 之前: c4?.y, 之后: c5?.y }))
if (!c5 || Math.abs(c5.y - (c4.y - 60)) > 2.5) { bad++; console.log('✗ 横线远端竖拖挪不动价格线') }
await touch('touchStart', [[lx, box.y + c5.y]]); await sleep(30)
for (let i = 1; i <= 15; i++) { await touch('touchMove', [[lx + i * 6, box.y + c5.y]]); await sleep(16) }
await touch('touchEnd', []); await sleep(400)
const c6 = await cross()
if (c6 && Math.abs(c6.y - c5.y) < 3) { bad++; console.log('✗ 横线上横拖没有拖图') } else console.log('✓ 横线上横拖照旧拖图、十字线收起')
console.log(errs.length ? '页面错误：' + errs.join(' | ') : '无页面错误', bad ? `✗ ${bad} 处问题` : '✓ 跟手')
await b.close(); process.exit(bad ? 1 : 0)
