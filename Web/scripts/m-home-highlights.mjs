// 手机网页 · 首页（异动 · 涨跌 · 持仓 · 板块）与「盘口要点」验收截图：三套皮肤 × 深浅，393×852 @3x，真接口
// 用法：先起 `npx vite --port 5178 --strictPort`，再 `node scripts/m-home-highlights.mjs [输出目录] [base URL]`
// 每套：首页异动、有新异动药丸；SEGS=1 时加涨跌（跌幅榜「全部」展开）、持仓、板块与下钻（新页一套皮肤就够）；
// CHART=0 时跳过行情页那几张：点异动行进行情页（半页自动升起并展开那张卡）、入口条、点入口条升半页、展开价位、回图
// 只跑一部分：SKINS=sage THEMES=light SEGS=1 CHART=0
import { chromium } from 'playwright-core'
import { mkdirSync } from 'node:fs'
import { CHROME, sleep, corsShim } from './f-lib.mjs'

const OUT = process.argv[2] || '../docs/acceptance/首页与盘口要点-手机网页-2026-10-10'
const URL_ = process.argv[3] || 'http://localhost:5178/web/m/'
mkdirSync(OUT, { recursive: true })
const UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 26_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.6 Mobile/15E148 Safari/604.1'
// 只跑一部分：SKINS=sage THEMES=light,dark
const pick = (all, env) => (env ? all.filter(([id]) => env.split(',').includes(id)) : all)
const SKINS = pick([['sage', '青苔'], ['terra', '陶土'], ['classic', '经典']], process.env.SKINS)
const THEMES = pick([['light', '浅'], ['dark', '深']], process.env.THEMES)
const browser = await chromium.launch({ executablePath: CHROME, headless: true })
const problems = []

for (const [skin, skinCn] of SKINS) for (const [theme, themeCn] of THEMES) {
  const tag = `${skinCn}${themeCn}`
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true, userAgent: UA, locale: 'zh-CN', timezoneId: 'Asia/Shanghai', colorScheme: theme })
  await corsShim(ctx)
  await ctx.routeWebSocket(u => /^wss?:\/\/localhost(:\d+)?\//.test(String(u)) && /[?&]token=/.test(String(u)), () => {})
  const seed = JSON.stringify({ symbol: 'BTCUSDT', interval: '15m', skin, theme, routePicked: true, routePolicy: 'gateway', greenUpMigrated: true })
  await ctx.addInitScript(s => { if (!sessionStorage.getItem('s')) { sessionStorage.setItem('s', '1'); localStorage.clear(); localStorage.setItem('hkline-m-v1', s) } }, seed)
  // 第一次拉异动时少给两行，第二次照实给 → 截到「有 N 条新异动」药丸
  let boardHits = 0
  await ctx.route(/\/v1\/market\/orderflow\/highlights\/board/, async route => {
    try {
      const res = await route.fetch()
      const body = await res.json()
      if (boardHits++ === 0) body.rows = body.rows.slice(2)
      await route.fulfill({ response: res, json: body })
    } catch { /* 这一套截完、上下文已关时还在路上的那次 */ }
  })
  const p = await ctx.newPage()
  p.on('pageerror', e => problems.push(`${tag} pageerror ${e.message}`))
  const shot = async name => { await p.screenshot({ path: `${OUT}/${tag}-${name}.png` }) }

  await p.goto(URL_)
  await p.waitForSelector('.hm-row:not(.skel), .hm-calm', { timeout: 30000 })
  await sleep(900)
  if (await p.evaluate(() => location.hash) !== '#home') problems.push(`${tag} 冷启动没落在首页`)
  if (await p.$$eval('.m-tab', a => a.length) !== 4) problems.push(`${tag} 底栏不是四格`)
  if (await p.$$eval('.hm-caps .hm-cap', a => a.map(b => b.textContent).join(' ')) !== '异动 涨跌 持仓 板块') problems.push(`${tag} 分段胶囊不对`)
  const capsRow = await p.$$eval('.hm-caps .hm-cap', a => new Set(a.map(b => Math.round(b.getBoundingClientRect().top))).size)
  if (capsRow !== 1) problems.push(`${tag} 分段胶囊没在一行`)
  await shot('1-首页异动')
  // 回前台触发一次轮询 → 药丸
  await p.evaluate(() => document.dispatchEvent(new Event('visibilitychange')))
  await p.waitForSelector('.hm-newpill:not([hidden])', { timeout: 15000 }).catch(() => problems.push(`${tag} 没浮出新异动药丸`))
  await sleep(500)
  await shot('2-有新异动')
  await p.click('.hm-newpill').catch(() => {})
  await sleep(600)

  if (process.env.SEGS === '1') {
    // 波动胶囊：胶囊上不带计数，点进去有急涨 / 急跌行才截一张
    await p.click('.hm-chips [data-chip=move]')
    await sleep(500)
    const moves = await p.$$eval('.hm-list .hm-row', rs => rs.length).catch(() => 0)
    if (moves > 0) await shot('2b-波动')
    else problems.push(`${tag} 看板里暂无波动行（没截 2b-波动）`)
    if (await p.$eval('.hm-chips', el => /\d/.test(el.textContent || '')).catch(() => false)) problems.push(`${tag} 胶囊条上还有数字`)
    // 费率胶囊：事实行带 30 天百分位箭头（↑N / ↓N）
    await p.click('.hm-chips [data-chip=funding]')
    await sleep(500)
    if (await p.$$eval('.hm-list .hm-row', rs => rs.length).catch(() => 0) > 0) await shot('2c-费率')
    else problems.push(`${tag} 看板里暂无费率行（没截 2c-费率）`)
    await p.click('.hm-chips [data-chip=all]')
    await sleep(300)
    await p.click('.hm-caps [data-seg=change]')
    await p.waitForSelector('.hm-rank[data-page=change] .hm-rr[data-base]', { timeout: 20000 }).catch(() => problems.push(`${tag} 涨跌没出行`))
    await sleep(900)
    await shot('3-涨跌')
    await p.click('.hm-sect[data-kind=losers] [data-more]').catch(() => problems.push(`${tag} 跌幅榜没有「全部」`))
    await sleep(300)
    await p.evaluate(() => document.querySelector('.hm-sect[data-kind=losers]')?.scrollIntoView({ block: 'start' }))
    await sleep(400)
    await shot('3b-涨跌全部')
    await p.click('.hm-caps [data-seg=oi]')
    await p.waitForSelector('.hm-rank[data-page=oi] .hm-sect[data-kind=oi] .hm-rr[data-base]', { timeout: 20000 }).catch(() => problems.push(`${tag} 增仓榜没出行`))
    await p.waitForSelector('.hm-rank[data-page=oi] .hm-sect[data-kind=oidown] :is(.hm-rr[data-base], .hm-gempty)', { timeout: 20000 }).catch(() => problems.push(`${tag} 减仓榜没落定`))
    await sleep(900)
    await shot('4-持仓')
    // 两页窗口各自记：持仓换 24 时，涨跌仍是 4 时
    await p.click('.hm-rank[data-page=oi] [data-win="24h"]')
    await sleep(1500)
    const wins = await p.evaluate(() => [...document.querySelectorAll('.hm-rank')].map(r => r.querySelector('[data-win].on')?.getAttribute('data-win')).join(','))
    if (wins !== '4h,24h') problems.push(`${tag} 两页窗口没各自记：${wins}`)
    await p.click('.hm-rank[data-page=oi] [data-win="4h"]')
    await p.click('.hm-caps [data-seg=sectors]')
    await p.waitForSelector('.hm-sectors .sec-row[data-sec]', { timeout: 30000 }).catch(() => problems.push(`${tag} 板块没出行`))
    await sleep(1200)
    await shot('4b-板块')
    await p.click('.hm-sectors .sec-row[data-sec]')
    await p.waitForSelector('.hm-sectors .sec-drill .lr[data-sym]', { timeout: 20000 }).catch(() => problems.push(`${tag} 板块下钻没出品种`))
    await sleep(1500)
    await shot('4c-板块下钻')
    await p.click('.hm-sectors .sec-drill .lr[data-sym]')
    await p.waitForFunction(() => location.hash === '#chart', null, { timeout: 10000 }).catch(() => problems.push(`${tag} 点板块品种没进图`))
    await sleep(800)
    // 深链 #sectors：落首页「板块」段（下钻那层还在）
    await p.evaluate(() => { location.hash = '#sectors' })
    await sleep(800)
    const deep = await p.evaluate(() => [location.hash, document.querySelector('.hm-cap.on')?.getAttribute('data-seg'), !document.querySelector('.hm-sectors').hidden].join(','))
    if (deep !== '#home,sectors,true') problems.push(`${tag} 深链 #sectors 没落到板块段：${deep}`)
    await p.click('.hm-caps [data-seg=moves]')
    await sleep(400)
  }
  if (process.env.CHART === '0') { await ctx.close(); console.log('完成', tag); continue }

  // 点第一条盘口类异动（有价位就展开价位），没有就点第一行
  const target = await p.evaluate(() => (document.querySelector('.hm-row[style*="accent"][data-key]') || document.querySelector('.hm-row[data-key]:not([data-key^="move:"])'))?.dataset.key)
  await p.click(`.hm-row[data-key="${target}"]`)
  await p.waitForSelector('.hl-wrap.in', { timeout: 15000 }).catch(() => problems.push(`${tag} 从首页进图半页没升`))
  await sleep(1800)
  await shot('5-从首页进图半页展开')
  // 关半页，看入口条
  await p.evaluate(() => document.querySelector('.hl-catch')?.dispatchEvent(new MouseEvent('click', { bubbles: true })))
  await sleep(800)
  await p.click('.cp-tab, .m-tab[data-page=chart]').catch(() => {})
  await p.goto(URL_ + '#chart')
  await p.waitForFunction(() => document.querySelector('.hl-strip:not(.thin)'), null, { timeout: 30000 }).catch(() => problems.push(`${tag} 入口条一直是抓手`))
  await sleep(1500)
  await shot('6-入口条')
  await p.click('.hl-strip')
  await sleep(1200)
  await shot('7-半页')
  const lv = await p.$('.hl-lv .row')
  if (lv) {
    await lv.click(); await sleep(500)
    await shot('8-展开价位')
    const back = await p.$('.hl-lv .lev .go, .lev .go')
    if (back) { await back.click(); await sleep(900); await shot('9-回图带子') } else problems.push(`${tag} 没有回图按钮`)
  } else problems.push(`${tag} 半页没有价位`)
  await ctx.close()
  console.log('完成', tag)
}
await browser.close()
console.log(problems.length ? '问题：\n' + problems.join('\n') : '全部通过')
