// 手机网页 · 首页（异动 / 榜单）与「盘口要点」验收截图：三套皮肤 × 深浅，393×852 @3x，真接口
// 用法：先起 `npx vite --port 5178 --strictPort`，再 `node scripts/m-home-highlights.mjs [输出目录] [base URL]`
// 每套：首页异动、有新异动药丸、首页榜单（涨幅卡展开）、点异动行进行情页（半页自动升起并展开那张卡）、
// 入口条、点入口条升半页、展开价位、回图（图上带子 + 十字线）
import { chromium } from 'playwright-core'
import { mkdirSync } from 'node:fs'
import { CHROME, sleep, corsShim } from './f-lib.mjs'

const OUT = process.argv[2] || '../docs/acceptance/首页与盘口要点-手机网页-2026-10-10'
const URL_ = process.argv[3] || 'http://localhost:5178/web/m/'
mkdirSync(OUT, { recursive: true })
const UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 26_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.6 Mobile/15E148 Safari/604.1'
const SKINS = [['sage', '青苔'], ['terra', '陶土'], ['classic', '经典']]
const THEMES = [['light', '浅'], ['dark', '深']]
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
    const res = await route.fetch()
    const body = await res.json()
    if (boardHits++ === 0) body.rows = body.rows.slice(2)
    await route.fulfill({ response: res, json: body })
  })
  const p = await ctx.newPage()
  p.on('pageerror', e => problems.push(`${tag} pageerror ${e.message}`))
  const shot = async name => { await p.screenshot({ path: `${OUT}/${tag}-${name}.png` }) }

  await p.goto(URL_)
  await p.waitForSelector('.hm-row:not(.skel), .hm-calm', { timeout: 30000 })
  await sleep(900)
  if (await p.evaluate(() => location.hash) !== '#home') problems.push(`${tag} 冷启动没落在首页`)
  if (await p.$$eval('.m-tab', a => a.length) !== 5) problems.push(`${tag} 底栏不是五格`)
  await shot('1-首页异动')
  // 回前台触发一次轮询 → 药丸
  await p.evaluate(() => document.dispatchEvent(new Event('visibilitychange')))
  await p.waitForSelector('.hm-newpill:not([hidden])', { timeout: 15000 }).catch(() => problems.push(`${tag} 没浮出新异动药丸`))
  await sleep(500)
  await shot('2-有新异动')
  await p.click('.hm-newpill').catch(() => {})
  await sleep(600)

  await p.click('.hm-seg [data-seg=board]')
  await p.waitForSelector('.hm-card .br[data-base]', { timeout: 20000 }).catch(() => problems.push(`${tag} 榜单没出行`))
  await sleep(700)
  await shot('3-首页榜单')
  await p.click('.hm-card[data-kind=gainers] [data-more]').catch(() => {})
  await sleep(300)
  await p.evaluate(() => document.querySelector('.hm-card[data-kind=gainers]')?.scrollIntoView({ block: 'start' }))
  await sleep(300)
  await shot('4-榜单展开')
  await p.click('.hm-seg [data-seg=moves]')
  await sleep(400)

  // 点第一条盘口类异动（有价位就展开价位），没有就点第一行
  const target = await p.evaluate(() => (document.querySelector('.hm-row[style*="accent"][data-base]') || document.querySelector('.hm-row[data-base]'))?.dataset.base)
  await p.click(`.hm-row[data-base="${target}"]`)
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
