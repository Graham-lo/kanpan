// Hkline 手机网页版 · 2026-10-08 批次验收：自选行 24 小时走势线、药丸闪、设置「自选走势线」、板块行「领涨 X」
//   node scripts/m-favorites-trend.mjs [地址]
//   默认地址 http://localhost:5178/web/m/（npx vite --port 5178）；截图落在 /tmp/kanpan-mweb-1008/
// 查的事：
//   · 走势线画出来了、在价格与药丸之间、44×20；价格那一格没被截（390 / 360 两档宽）
//   · 15 分钟线只取露面那几行（请求数 ≤ 可见行 + 预取半屏），重画 / 回前台不重取
//   · 滚动：走势线开 / 关各量一次同样的 240 帧往返滚动，开着不能比关着明显差
//   · 关掉开关：整列不摆、之后不再发 15 分钟线请求
//   · 药丸闪：十秒内药丸挂过 fl-up / fl-down
//   · 板块行「领涨 X」在涨跌幅左边
// 有 ✗ 退出码 1。
import { chromium } from 'playwright-core'
import { mkdirSync } from 'node:fs'
import { CHROME, sleep, corsShim } from './f-lib.mjs'

const URL_ = process.argv[2] || 'http://localhost:5178/web/m/'
const OUT = '/tmp/kanpan-mweb-1008'
mkdirSync(OUT, { recursive: true })
const UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 26_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.6 Mobile/15E148 Safari/604.1'
let bad = 0

const scrollOn = {}
const info = msg => console.log('· ' + msg)
const fmtScroll = r => `中位 ${r.med.toFixed(1)}ms、长帧(>32ms) ${r.long}/${r.n}、长任务(>50ms) ${r.tasks}`
// 240 帧往返滚动：帧间隔中位数、长帧数、主线程长任务数
const scrollFrames = p => p.evaluate(() => new Promise(res => {
  const sc = document.querySelector('.fav-scroll'), dts = []
  let tasks = 0
  const po = new PerformanceObserver(l => { tasks += l.getEntries().length })
  try { po.observe({ type: 'longtask' }) } catch {}
  let last = performance.now(), i = 0
  const max = Math.max(1, sc.scrollHeight - sc.clientHeight)
  const step = now => {
    dts.push(now - last); last = now
    sc.scrollTop = (Math.sin(i / 20) * 0.5 + 0.5) * max; i++
    if (i < 240) requestAnimationFrame(step)
    else {
      po.disconnect(); sc.scrollTop = 0
      const f = dts.slice(1)
      res({ med: [...f].sort((a, b) => a - b)[f.length >> 1], long: f.filter(x => x > 32).length, n: f.length, tasks })
    }
  }
  requestAnimationFrame(step)
}))
const ok = (pass, msg) => { if (!pass) bad++; console.log(`${pass ? '✓' : '✗'} ${msg}`) }

const browser = await chromium.launch({ executablePath: CHROME, headless: true })
for (const scheme of ['light', 'dark']) {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true, userAgent: UA, locale: 'zh-CN', timezoneId: 'Asia/Shanghai', colorScheme: scheme })
  await corsShim(ctx)
  // 开发服务器的热更新通道接个空：同一工作树里别的窗口在改文件，热更新会把页面整页刷掉
  await ctx.routeWebSocket(u => /^wss?:\/\/localhost(:\d+)?\//.test(String(u)) && /[?&]token=/.test(String(u)), () => {})
  const trendReqs = []
  ctx.on('request', r => { if (r.method() === 'GET' && /klines\?.*interval=15m/.test(r.url()) && /limit=97/.test(r.url())) trendReqs.push(r.url()) })
  const p = await ctx.newPage()
  const errs = []
  p.on('pageerror', e => errs.push(e.message))

  // ---------------- 自选
  await p.goto(URL_ + '#favorites')
  await p.waitForSelector('.lr', { timeout: 30000 })
  await p.waitForFunction(() => document.querySelectorAll('.lr-trend svg').length >= 5, null, { timeout: 30000 }).catch(() => {})
  await sleep(1500)
  const geo = await p.evaluate(() => {
    const rows = [...document.querySelectorAll('.lr')].filter(r => { const b = r.getBoundingClientRect(); return b.bottom > 0 && b.top < innerHeight })
    const out = { visible: rows.length, drawn: 0, bad: [], clipped: [] }
    for (const r of rows) {
      const price = r.querySelector('.lr-price'), tr = r.querySelector('.lr-trend'), pill = r.querySelector('.m-pill')
      if (!tr) { out.bad.push(r.dataset.sym + ' 没有走势格'); continue }
      if (tr.querySelector('svg')) out.drawn++
      const a = price.getBoundingClientRect(), t = tr.getBoundingClientRect(), c = pill.getBoundingClientRect()
      if (Math.round(t.width) !== 44 || Math.round(t.height) !== 20) out.bad.push(`${r.dataset.sym} 走势格 ${t.width}×${t.height}`)
      if (!(a.right <= t.left && t.right <= c.left)) out.bad.push(`${r.dataset.sym} 次序不对`)
      if (Math.round(c.left - t.right) !== 8) out.bad.push(`${r.dataset.sym} 走势与药丸间距 ${c.left - t.right}`)
      if (price.scrollWidth > price.clientWidth + 1 && price.textContent) out.clipped.push(r.dataset.sym + '「' + price.textContent + '」')
    }
    return out
  })
  ok(geo.drawn >= Math.min(5, geo.visible) && !geo.bad.length, `${scheme} 自选：可见 ${geo.visible} 行、画出走势 ${geo.drawn} 行${geo.bad.length ? '；' + geo.bad.slice(0, 4).join('；') : ''}`)
  ok(!geo.clipped.length, `${scheme} 自选 390 宽价格不截${geo.clipped.length ? '：' + geo.clipped.join('；') : ''}`)
  const firstReqs = trendReqs.length
  const rowsTotal = await p.evaluate(() => document.querySelectorAll('.lr').length)
  ok(firstReqs <= Math.ceil(geo.visible * 2) + 2, `${scheme} 15 分钟线只取露面那几行：发了 ${firstReqs} 趟（表里 ${rowsTotal} 行、露面 ${geo.visible} 行）`)
  await p.screenshot({ path: `${OUT}/favorites-${scheme}.png` })

  // 药丸闪：盯十秒
  const flashes = await p.evaluate(() => new Promise(res => {
    let n = 0
    const mo = new MutationObserver(ms => { for (const m of ms) if (m.target.classList?.contains('fl-up') || m.target.classList?.contains('fl-down')) n++ })
    mo.observe(document.querySelector('.fav-list'), { subtree: true, attributes: true, attributeFilter: ['class'] })
    setTimeout(() => { mo.disconnect(); res(n) }, 10000)
  }))
  ok(flashes > 0, `${scheme} 药丸闪：十秒内闪了 ${flashes} 下`)

  // 滚动：无头浏览器在 3x 屏上本来就跑不满 60 帧，绝对帧时没意义——
  // 记下开着时的数，关掉开关那段再量一次同样的滚动做对照（见下）。
  scrollOn[scheme] = await scrollFrames(p)
  info(`${scheme} 自选滚动（走势线开）：${fmtScroll(scrollOn[scheme])}`)
  await p.evaluate(() => { document.querySelector('.fav-scroll').scrollTop = 0 })
  await sleep(1500)
  const afterScroll = trendReqs.length

  // 回前台 / 重画不重取
  await p.evaluate(() => { document.dispatchEvent(new Event('visibilitychange')); dispatchEvent(new Event('focus')) })
  await sleep(1500)
  ok(trendReqs.length === afterScroll, `${scheme} 重画不重取：滚动后 ${afterScroll} 趟，之后 ${trendReqs.length} 趟`)

  // 360 宽（窄屏）
  await p.setViewportSize({ width: 360, height: 780 })
  await sleep(600)
  const narrow = await p.evaluate(() => [...document.querySelectorAll('.lr-price')].filter(e => e.scrollWidth > e.clientWidth + 1 && e.textContent).map(e => e.textContent))
  ok(!narrow.length, `${scheme} 360 宽价格不截${narrow.length ? '：' + narrow.join('；') : ''}`)
  if (scheme === 'light') await p.screenshot({ path: `${OUT}/favorites-360-${scheme}.png` })
  await p.setViewportSize({ width: 390, height: 844 })

  // ---------------- 设置 › 通用
  await p.goto(URL_ + '?open=settings#me')
  await p.waitForSelector('[data-sw="trend"]', { timeout: 15000 })
  const first = await p.evaluate(() => {
    const g = [...document.querySelectorAll('.me-group')].find(x => x.textContent.trim() === '通用')
    const row = g?.nextElementSibling
    g?.scrollIntoView({ block: 'center' })
    return row?.textContent?.trim() ?? ''
  })
  ok(first.startsWith('自选走势线'), `${scheme} 设置 › 通用第一行是「${first.slice(0, 8)}」`)
  await sleep(400)
  await p.screenshot({ path: `${OUT}/settings-general-${scheme}.png` })

  if (scheme === 'light') {
    // 关掉：整列不摆、不再取
    await p.click('[data-sw="trend"]')
    await sleep(300)
    await p.goto(URL_ + '?r=off#favorites')
    await p.waitForSelector('.lr')
    const before = trendReqs.length
    await sleep(3000)
    const cols = await p.evaluate(() => document.querySelectorAll('.lr-trend').length)
    await p.evaluate(() => { const sc = document.querySelector('.fav-scroll'); sc.scrollTop = sc.scrollHeight })
    await sleep(1500)
    ok(cols === 0 && trendReqs.length === before, `关掉开关：走势格 ${cols} 个、关后新发 15 分钟线 ${trendReqs.length - before} 趟`)
    // 对照：同一页、同一套滚动，走势线关着
    const off = await scrollFrames(p), on = scrollOn[scheme]
    ok(on.med <= off.med * 1.25 + 4 && on.long <= off.long + 12 && on.tasks <= off.tasks + 2,
      `走势线不拖滚动：开 ${fmtScroll(on)}；关 ${fmtScroll(off)}`)
    await p.evaluate(() => { document.querySelector('.fav-scroll').scrollTop = 0 })
    await sleep(300)
    await p.screenshot({ path: `${OUT}/favorites-trend-off-${scheme}.png` })
    // 再打开（别把开关关着留给下一次）
    await p.goto(URL_ + '?open=settings#me')
    await p.waitForSelector('[data-sw="trend"]')
    await p.click('[data-sw="trend"]')
    await sleep(300)
  }

  // ---------------- 板块
  await p.goto(URL_ + '?r=sec#sectors')
  await p.waitForSelector('.sec-row', { timeout: 30000 })
  await sleep(2500)
  const lead = await p.evaluate(() => {
    const rows = [...document.querySelectorAll('.sec-row')]
    const withLead = rows.filter(r => r.querySelector('.sec-lead'))
    const order = withLead.every(r => { const l = r.querySelector('.sec-lead').getBoundingClientRect(), c = r.querySelector('.sec-pct').getBoundingClientRect(), n = r.querySelector('.sec-name').getBoundingClientRect(); return n.right <= l.left + 0.5 && l.right <= c.left + 0.5 })
    return { rows: rows.length, lead: withLead.length, order, sample: withLead.slice(0, 3).map(r => r.querySelector('.sec-n').textContent + '：' + r.querySelector('.sec-lead').textContent) }
  })
  ok(lead.lead > 0 && lead.order, `${scheme} 板块：${lead.rows} 行里 ${lead.lead} 行写了领涨（${lead.sample.join('；')}）${lead.order ? '' : '，位置不对'}`)
  await p.screenshot({ path: `${OUT}/sectors-${scheme}.png` })

  ok(!errs.length, `${scheme} 页面报错 ${errs.length} 个${errs.length ? '：' + errs.slice(0, 3).join(' | ') : ''}`)
  await ctx.close()
}
await browser.close()
console.log(bad ? `✗ ${bad} 项没过` : '✓ 全过')
process.exit(bad ? 1 : 0)
