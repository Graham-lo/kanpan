// Hkline Web · 验收截图：本机 Chrome、2560×1440、DPR 1
//   node scripts/verify.mjs [地址] [截图目录]
//   默认地址是线上 https://kanpan.107-174-172-10.sslip.io/web/，默认目录是 docs/acceptance/网页版-2026-09-29/
// 截：三套皮肤 × 浅深、放大缩小、搜索、切周期、四图、槽位开合、各页；检查控制台无报错、最新价在几秒内有变化。
import { chromium } from 'playwright-core'
import { mkdirSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const URL_ = process.argv[2] || 'https://kanpan.107-174-172-10.sslip.io/web/'
const OUT = resolve(process.argv[3] || resolve(here, '../../docs/acceptance/网页版-2026-09-29'))
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
mkdirSync(OUT, { recursive: true })

const errors = []
const browser = await chromium.launch({ executablePath: CHROME, headless: true })
const ctx = await browser.newContext({ viewport: { width: 2560, height: 1440 }, deviceScaleFactor: 1 })
const page = await ctx.newPage()
page.on('console', m => { if (m.type() === 'error') errors.push(`[console] ${m.text()}`) })
page.on('pageerror', e => errors.push(`[pageerror] ${e.message}`))
page.on('requestfailed', r => { const u = r.url(); if (!u.includes('favicon')) errors.push(`[requestfailed] ${u} ${r.failure()?.errorText}`) })

const wait = ms => page.waitForTimeout(ms)
const shot = async name => { await page.screenshot({ path: `${OUT}/${name}.png` }); console.log('截图', name) }
const open = async (qs = '', hash = 'chart') => {
  await page.goto(`${URL_}?${qs}#${hash}`, { waitUntil: 'domcontentloaded' })
  try {
    await page.waitForFunction(() => (document.querySelector('#toolbar #tbSymbol') && document.title.includes('·')) || !!document.querySelector('.cell-empty:not([hidden])'), null, { timeout: 20000, polling: 250 })
  } catch (e) {
    await page.screenshot({ path: `${OUT}/超时-${hash}.png` })
    console.log('等页面超时', qs, hash, '\n' + errors.join('\n'))
    throw e
  }
  await wait(2500)
}
const lastPrice = () => page.evaluate(() => document.querySelector('#detail [data-f="big"]')?.textContent || '')

// 干净状态起步
await page.goto(URL_, { waitUntil: 'domcontentloaded' })
await page.evaluate(() => localStorage.clear())

for (const skin of ['sage', 'terra', 'classic']) {
  for (const theme of ['light', 'dark']) {
    await open(`skin=${skin}&theme=${theme}&layout=1&panel=watch&ladder=0&drawer=0`)
    await shot(`图表-${skin}-${theme}`)
  }
}

// 最新价在几秒内有变化
await open('skin=sage&theme=light&s=BTCUSDT&i=1m')
const p1 = await lastPrice()
let p2 = p1
for (let k = 0; k < 20 && p2 === p1; k++) { await wait(500); p2 = await lastPrice() }
console.log(`最新价 ${p1} → ${p2}`, p1 !== p2 ? '有变化' : '没变化（可能盘面静止）')
if (p1 === p2) errors.push(`[stale] 10 秒内最新价没有变化：${p1}`)

// 放大、缩小（以画布中心滚轮）
const box = await page.locator('.chart-cell canvas').first().boundingBox()
await page.mouse.move(box.x + box.width * 0.6, box.y + box.height * 0.4)
for (let k = 0; k < 6; k++) { await page.mouse.wheel(0, -240); await wait(60) }
await wait(400); await shot('放大')
for (let k = 0; k < 14; k++) { await page.mouse.wheel(0, 240); await wait(60) }
await wait(400); await shot('缩小')

// 十字线
await page.mouse.move(box.x + box.width * 0.5, box.y + box.height * 0.3); await wait(300); await shot('十字线')

// 搜索
await page.mouse.move(box.x + 4, box.y + 4)
await page.keyboard.press('Meta+K'); await wait(300)
await page.keyboard.type('英伟达'); await wait(500); await shot('搜索-英伟达')
await page.keyboard.press('Enter'); await wait(2500); await shot('打开-英伟达')

// 切周期：按钮与打数字
await page.click('#toolbar [data-iv="4h"]'); await wait(2500); await shot('周期-4时')
await page.keyboard.type('15'); await page.keyboard.press('Enter'); await wait(2500); await shot('周期-15分-键盘')

// 四图、槽位
await open('layout=4&ladder=0&drawer=0'); await wait(2000); await shot('四图')
await open('layout=1&ladder=1&drawer=1'); await shot('槽位-梯子与抽屉')
await open('layout=1&ladder=0&drawer=0&panel=none'); await shot('侧栏收起')

// 其它页
await open('layout=1&panel=watch', 'sectors'); await wait(3000); await shot('板块')
await open('', 'review'); await shot('复盘-空态')
await open('', 'me'); await shot('我的')

await browser.close()
if (errors.length) { console.log('\n报错：\n' + errors.join('\n')); process.exitCode = 1 } else console.log('\n控制台无报错')
