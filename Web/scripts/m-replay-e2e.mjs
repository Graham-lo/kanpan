// 手机网页版 · 行情页回放的端到端检查（2026-10-03）：复盘本交过来的三种回放（交易回放 / 在图上重温 / 相似片段）
// 在行情页上盖一层自己播：页头时刻往前走、交易回放的浮动盈亏胶囊与成交记号出来、拖进度线能跳、
// 「开仓处 / 判断处 / 相似段」能跳、「退出」回到「我的」且实时图原样。
//   npx vite --port 5197 后 node scripts/m-replay-e2e.mjs [地址] [机型…]
//   交易回放用真 K 线现编的一笔交易（测试账号没有交易所成交）；重温 / 相似的计划同样现编，经复盘本同一条路（sessionStorage + 事件）交过去。
//   若环境变量 KP_E2E_USER / KP_E2E_PASS 都有，再用这个账号走一遍复盘本界面：记一笔 → 复盘本 → 在图上重温 → 退出，最后注销账号。
//   截图落在 /tmp/m-replay/<机型>/；有 ✗ 退出码 1
import { chromium } from 'playwright-core'
import { mkdirSync } from 'node:fs'

const URL_ = process.argv[2] || 'http://localhost:5197/web/m/'
const ONLY = process.argv.slice(3)
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const IOS_UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 26_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.6 Mobile/15E148 Safari/604.1'
const HM_UA = 'Mozilla/5.0 (Phone; OpenHarmony 6.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36 ArkWeb/6.0.0.0 Mobile HuaweiBrowser/16.0.0.300'
const DEVICES = [
  { id: 'iPhone15ProMax', w: 430, h: 932, dpr: 3, ua: IOS_UA },
  { id: 'nova16', w: 366, h: 720, dpr: 3.5, ua: HM_UA },
].filter(d => !ONLY.length || ONLY.includes(d.id))
const sleep = ms => new Promise(r => setTimeout(r, ms))
let bad = 0
const fail = msg => { bad++; console.log('✗ ' + msg) }
const ok = msg => console.log('✓ ' + msg)
const SRC = new URL('../src/', URL_).href // http://host/web/src/

// 页面里：现编三份计划（交易回放的成交价取真 K 线，标签和三角才落在蜡烛旁边）
const MAKE_PLANS = async src => {
  const R = await import(src + 'review/replay.ts')
  const H = 3_600_000, now = Date.now()
  const open = Math.floor((now - 9 * 24 * H) / H) * H
  const rows = await (await fetch(`https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT&interval=1h&startTime=${open}&limit=40`)).json()
  const px = i => rows[i][4]
  const fill = (i, role, side) => ({ id: 'f' + i, orderId: 'o' + i, time: +rows[i][0] + 17 * 60_000, side, positionSide: 'BOTH', price: px(i), qty: '0.01', quoteQty: '0', commission: '0', commissionAsset: 'USDT', realizedPnl: '0', maker: false, role, split: false })
  const fills = [fill(0, 'open', 'BUY'), fill(6, 'add', 'BUY'), fill(14, 'reduce', 'SELL'), fill(22, 'close', 'SELL')]
  const round = { id: 'e2e', version: 1, venue: 'binance', market: 'usd_m', symbol: 'BTCUSDT', accountTag: 'e2e', positionSide: 'BOTH', direction: 'long', status: 'closed', quoteAsset: 'USDT', openedAt: fills[0].time, closedAt: fills[3].time, holdingMs: null, openAvgPrice: px(0), closeAvgPrice: px(22), openedQty: '0.02', closedQty: '0.02', maxQty: '0.02', peakNotional: '0', leverage: null, realizedPnl: '0', commission: '0', funding: '0', netPnl: '0', fills, updatedAt: now }
  const trade = R.planTrade(round, null, now, '突破回踩，轻仓试多', '1h')
  const range = { venue: 'binance', market: 'usd_m', symbol: 'ETHUSDT', interval: '1h', start: open, end: open + 24 * H, bars: 24 }
  const ref = +rows[23][4] > 0 ? +(await (await fetch(`https://fapi.binance.com/fapi/v1/klines?symbol=ETHUSDT&interval=1h&startTime=${open + 23 * H}&limit=1`)).json())[0][4] : 0
  const rec = { draft: { id: 'e2e-note', range, rule: { version: '1', direction: 'long', confirmation: 'bar_close', reference: ref, target: ref * 1.03, invalidation: ref * 0.98, expires: open + 24 * H + 72 * H }, text: 'e2e', confidence: null, origin: 'chart_first', created: open + 24 * H }, serverId: 'x', submitted: open + 24 * H, revision: 1, assessment: null, eligible: true, voided: false }
  const note = R.planNote(rec, now)
  const match = R.planMatch({ id: 'm', range: { ...range, symbol: 'SOLUSDT' }, score: 0.9 }, now)
  return { trade, note, match }
}

// 和复盘本 sendIntent 同一条路：写 sessionStorage → go('chart') → 发事件
const send = async ([kind, plan, src]) => {
  const { go } = await import(src + 'm/app/shell.ts')
  const detail = { kind, at: Date.now(), plan, market: 'binance/usd_m' }
  sessionStorage.setItem('hkline-m-review-intent', JSON.stringify(detail))
  go('chart')
  window.dispatchEvent(new CustomEvent('hkline:review-intent', { detail }))
}
/** 等回放层取完 K 线；打不开时把那句提示带回来 */
const ready = (p, what) => p.waitForFunction(() => document.querySelector('.cp-replay .cp-rwait')?.hidden === true || !!document.querySelector('.m-toast'), null, { timeout: 20000 })
  .then(() => p.evaluate(() => document.querySelector('.m-toast')?.textContent || null))
  .then(t => { if (t) fail(`${what}打不开：${t}`) }, () => fail(what + '没等到 K 线'))
const headText = p => p.evaluate(() => {
  const q = s => document.querySelector(s)
  return { title: q('.cp-rtitle')?.textContent, time: q('.cp-rtime')?.textContent, cap: q('.cp-rcap')?.hidden ? null : q('.cp-rcap')?.textContent, ohlc: q('.cp-rohlc')?.textContent, key: q('.cp-rkey')?.textContent, play: q('.cp-rplay')?.getAttribute('aria-label'), fill: q('.cp-rfill')?.style.width }
})
/** 覆盖层上有没有成交三角（涨色 / 跌色的实心像素） */
const overlayInk = p => p.evaluate(() => {
  const c = document.querySelector('.cp-rchart canvas[data-part="4"]') || [...document.querySelectorAll('.cp-rchart canvas')].pop()
  const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data
  let n = 0
  for (let i = 3; i < d.length; i += 4) if (d[i] > 200) n++
  return n
})

for (const dev of DEVICES) {
  const dir = `/tmp/m-replay/${dev.id}`
  mkdirSync(dir, { recursive: true })
  const b = await chromium.launch({ executablePath: CHROME, headless: true, args: ['--disable-web-security'] })
  const ctx = await b.newContext({ viewport: { width: dev.w, height: dev.h }, deviceScaleFactor: dev.dpr, isMobile: true, hasTouch: true, userAgent: dev.ua, locale: 'zh-CN', timezoneId: 'Asia/Shanghai' })
  const p = await ctx.newPage()
  const errs = []
  p.on('pageerror', e => errs.push(e.message))
  p.on('console', m => { if (m.type() === 'error' && !/Failed to load resource|net::ERR/.test(m.text())) errs.push(m.text()) })
  await p.goto(URL_ + '#chart')
  await p.waitForSelector('.cp-chart .m-chart', { timeout: 20000 })
  await sleep(2500)
  const live = await p.evaluate(() => ({ title: document.querySelector('.cp-top')?.textContent, iv: document.querySelector('.cp-ivrow .on, .cp-ivrow [aria-selected="true"]')?.textContent }))
  const plans = await p.evaluate(MAKE_PLANS, SRC)
  const shot = name => p.screenshot({ path: `${dir}/${name}.png` })

  // ── 交易回放：自动播、胶囊、记号、拖进度线、跳开仓处、播完变重播
  await p.evaluate(send, ['trade', plans.trade, SRC])
  await ready(p, '交易回放')
  const t0 = await headText(p)
  console.log(dev.id, '交易回放 打开', JSON.stringify(t0))
  if (!/^回放 · BTCUSDT · 1时$/.test(t0.title || '')) fail('交易回放标题不对')
  if (await p.evaluate(() => getComputedStyle(document.querySelector('.m-tabbar')).display) !== 'none') fail('回放时底栏没让位')
  await sleep(2600)
  const t1 = await headText(p)
  if (t1.time === t0.time) fail('交易回放没有自动往前播'); else ok('交易回放自动播放（' + t0.time + ' → ' + t1.time + '）')
  await shot('1-交易回放-播放中')
  // 跳开仓处：胶囊要出来、开仓三角要画
  await p.click('.cp-rkey'); await sleep(400)
  const tk = await headText(p)
  if (!tk.cap) fail('开仓处没有浮动盈亏胶囊'); else ok('开仓处胶囊 ' + tk.cap)
  // 拖进度线到 95%：过了平仓，胶囊收起、四笔成交都在
  const sb = await (await p.$('.cp-rscrub')).boundingBox()
  const cdp = await ctx.newCDPSession(p)
  const touch = (type, pts) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: pts.map((q, i) => ({ x: q[0], y: q[1], id: i })) })
  await touch('touchStart', [[sb.x + sb.width * 0.2, sb.y + sb.height / 2]])
  for (let i = 1; i <= 12; i++) { await touch('touchMove', [[sb.x + sb.width * (0.2 + i * 0.0625), sb.y + sb.height / 2]]); await sleep(30) }
  const dragging = await p.evaluate(() => document.querySelector('.cp-rscrub').classList.contains('dragging'))
  await touch('touchEnd', []); await sleep(400)
  const td = await headText(p)
  console.log(dev.id, '拖到 95%', JSON.stringify(td))
  if (!dragging) fail('拖进度线时没出拖动态（圆点）')
  if (parseFloat(td.fill) < 80) fail('拖进度线没跳到位：' + td.fill)
  if (td.cap) fail('平仓之后胶囊还在：' + td.cap)
  await p.click('.cp-rplay'); await sleep(200) // 暂停，截一张静止的
  await shot('2-交易回放-拖到平仓后')
  const ink = await overlayInk(p)
  if (ink < 50) fail('覆盖层上没有成交记号（像素 ' + ink + '）'); else ok('覆盖层有成交记号（像素 ' + ink + '）')
  // 播到头：重播
  await touch('touchStart', [[sb.x + sb.width - 1, sb.y + sb.height / 2]]); await touch('touchEnd', []); await sleep(300)
  const te = await headText(p)
  if (te.play !== '重播') fail('播到头按钮没变重播：' + te.play); else ok('播到头变「重播」')
  // 倍速
  const sp0 = await p.textContent('.cp-rspeed'); await p.click('.cp-rspeed'); const sp1 = await p.textContent('.cp-rspeed')
  if (sp0 === sp1) fail('倍速没变'); else ok(`倍速 ${sp0} → ${sp1}`)
  // 退出 → 「我的」，实时图原样
  await p.click('.cp-rexit'); await sleep(600)
  const after = await p.evaluate(() => ({ page: location.hash, layer: !!document.querySelector('.cp-replay'), free: document.getElementById('m-app').classList.contains('replay-free') }))
  if (after.layer || after.free) fail('退出后回放层没拆干净')
  if (after.page !== '#me') fail('退出没回到「我的」：' + after.page); else ok('退出回到「我的」')

  // ── 在图上重温：不自动播、判断处、播放后往前走
  await p.evaluate(send, ['revisit', plans.note, SRC])
  await ready(p, '重温')
  const n0 = await headText(p)
  console.log(dev.id, '重温 打开', JSON.stringify(n0))
  if (n0.title !== '重温 · ETHUSDT') fail('重温标题不对')
  if (n0.key !== '判断处') fail('重温关键点不是判断处')
  await sleep(1500)
  if ((await headText(p)).time !== n0.time) fail('重温不该自动播')
  await shot('3-重温-判断处')
  await p.click('.cp-rplay'); await sleep(2300)
  const n1 = await headText(p)
  if (n1.time === n0.time) fail('重温点播放没往前走'); else ok('重温播放（' + n0.time + ' → ' + n1.time + '）')
  await p.click('.cp-rplay')
  await shot('4-重温-播放后')
  await p.click('.cp-rexit'); await sleep(500)

  // ── 相似片段
  await p.evaluate(send, ['match', plans.match, SRC])
  await ready(p, '相似片段')
  const m0 = await headText(p)
  console.log(dev.id, '相似 打开', JSON.stringify(m0))
  if (m0.title !== '重温 · SOLUSDT' || m0.key !== '相似段') fail('相似片段页头不对')
  await shot('5-相似片段')
  // 系统返回（左沿右划 / 返回键）= 退出
  await p.goBack(); await sleep(600)
  const back = await p.evaluate(() => ({ page: location.hash, layer: !!document.querySelector('.cp-replay') }))
  if (back.layer || back.page !== '#me') fail('系统返回没退出回放：' + JSON.stringify(back)); else ok('系统返回退出回放')
  // 实时图没被动过
  await p.evaluate(() => { location.hash = '#chart' }); await sleep(1500)
  const live2 = await p.evaluate(() => ({ title: document.querySelector('.cp-top')?.textContent, iv: document.querySelector('.cp-ivrow .on, .cp-ivrow [aria-selected="true"]')?.textContent }))
  if (JSON.stringify(live2) !== JSON.stringify(live)) fail('实时图被回放改了：' + JSON.stringify(live) + ' → ' + JSON.stringify(live2)); else ok('实时图品种、周期原样')
  await shot('6-退出后实时图')

  if (errs.length) fail('页面报错：' + errs.slice(0, 5).join(' | '))
  await b.close()
}
console.log(bad ? `共 ${bad} 处不对` : '全部通过')
process.exit(bad ? 1 : 0)
