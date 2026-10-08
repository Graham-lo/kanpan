// Hkline 电脑网页版 · 2026-10-08「图上大单与爆仓气泡」验收（1440×900，浅 / 深）
//   node scripts/pc-bigtrade.mjs [地址]
//   默认地址 http://localhost:5178/web/（开发构建才在画布上挂 __bubbles）；截图落在 docs/acceptance/大单爆仓气泡-2026-10-08/
// 每套主题：1 小时整页 → 悬停最大的一枚泡（读数卡顶上要有向上 / 向下）→ 点它（抽屉开到那根）→ 切 5 分（密集：泡 ≤ 6 枚）
import { chromium } from 'playwright-core'
import { mkdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { CHROME, sleep, corsShim } from './f-lib.mjs'

const URL_ = process.argv[2] || 'http://localhost:5178/web/'
const OUT = fileURLToPath(new URL('../../docs/acceptance/大单爆仓气泡-2026-10-08/', import.meta.url))
mkdirSync(OUT, { recursive: true })
let bad = 0
const ok = (pass, msg) => { if (!pass) bad++; console.log(`${pass ? '✓' : '✗'} ${msg}`) }
const browser = await chromium.launch({ executablePath: CHROME, headless: true })

const bubbles = p => p.evaluate(() => {
  const c = [...document.querySelectorAll('canvas')].find(x => x.__bubbles)
  if (!c) return null
  const r = c.getBoundingClientRect()
  return c.__bubbles.map(b => ({ ...b, px: r.left + b.x, py: r.top + b.y }))
})

for (const theme of ['light', 'dark']) {
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2, locale: 'zh-CN', timezoneId: 'Asia/Shanghai', colorScheme: theme })
  await corsShim(ctx)
  await ctx.routeWebSocket(u => /^wss?:\/\/localhost(:\d+)?\//.test(String(u)) && /[?&]token=/.test(String(u)), () => {})
  const seed = JSON.stringify({ theme, skin: 'sage', orderFlow: true, routePicked: true, route: 'gateway', greenUpMigrated: true })
  await ctx.addInitScript(s => { if (!sessionStorage.getItem('pc-seeded')) { sessionStorage.setItem('pc-seeded', '1'); localStorage.clear(); localStorage.setItem('hkline-web-v1', s) } }, seed)
  const p = await ctx.newPage()
  const errs = []
  p.on('pageerror', e => errs.push(e.message))
  await p.goto(URL_ + '#chart')
  await p.waitForFunction(() => [...document.querySelectorAll('canvas')].some(c => c.__bubbles && c.__bubbles.some(b => b.bubble)), null, { timeout: 60000 }).catch(() => {})
  await sleep(1500)
  let bs = await bubbles(p)
  const named = (bs || []).filter(b => b.bubble)
  ok(bs && named.length > 0, `${theme} 1 小时：泡 ${named.length} 枚、点 ${(bs || []).length - named.length} 枚，字「${named.map(b => b.text).join(' ')}」`)
  await p.screenshot({ path: OUT + `pc-${theme}-1h.png` })
  if (named.length) {
    const big = named.slice().sort((a, b) => b.r - a.r)[0]
    await p.mouse.move(big.px, big.py)
    await sleep(500)
    const card = await p.evaluate(() => document.querySelector('.of-card')?.innerText ?? '')
    ok(/向上/.test(card) && /向下/.test(card), `悬停泡出读数卡，顶上有向上 / 向下：${card.split('\n').slice(0, 4).join(' · ')}`)
    await p.screenshot({ path: OUT + `pc-${theme}-hover.png` })
    await p.mouse.click(big.px, big.py)
    await sleep(900)
    const drawer = await p.evaluate(() => { const d = document.querySelector('.of-drawer, [class*="drawer"]'); return d ? { cls: d.className, h: Math.round(d.getBoundingClientRect().height), hi: !!d.querySelector('.hi, .on, [aria-selected="true"]') } : null })
    ok(drawer && drawer.h > 80, `点泡：抽屉开着（${JSON.stringify(drawer)}）`)
    await p.screenshot({ path: OUT + `pc-${theme}-click.png` })
    await p.mouse.move(700, 60); await sleep(600)
    // 离每枚泡的命中圈（r × 1.1 + 2）都够远的点，不然摸到的是旁边那枚泡
    const dots = (bs || []).filter(b => !b.bubble && named.every(n => Math.hypot(n.px - b.px, n.py - b.py) > n.r * 1.1 + 8))
    if (dots.length) {
      await p.mouse.move(dots[0].px, dots[0].py); await sleep(500)
      // 点常落在挂单带里，带的卡可以出；不许出的是那根的读数卡（有向上 / 向下两行）。hideCard 只摘 show 类、不清内容，所以只看亮着的卡
      const c2 = await p.evaluate(() => document.querySelector('.of-card.show')?.textContent ?? '')
      ok(!/向上/.test(c2), `悬停小圆点不出那根的读数卡${c2 ? '（出的是：' + c2.slice(0, 24).replace(/\s+/g, ' ') + '）' : ''}`)
    }
  }
  // 5 分：密集
  const five = p.locator('button', { hasText: /^5分$/ }).first()
  if (await five.count()) {
    await five.click(); await sleep(4000)
    bs = await bubbles(p)
    const n5 = (bs || []).filter(b => b.bubble)
    ok(bs && n5.length <= 6, `${theme} 5 分：泡 ${n5.length} 枚（≤ 6）、点 ${(bs || []).length - n5.length} 枚，字「${n5.map(b => b.text).join(' ')}」`)
    await p.screenshot({ path: OUT + `pc-${theme}-5m.png` })
  }
  ok(errs.length === 0, `无页面错误${errs.length ? '：' + errs.join(' | ') : ''}`)
  await ctx.close()
}
await browser.close()
process.exit(bad ? 1 : 0)
