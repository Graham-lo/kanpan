// 真实手机网页DOM手势冒烟，不合成行情、不保留空图截图。
// node scripts/m-insight-gestures.mjs [http://127.0.0.1:5178/web/m/]
import { chromium } from 'playwright-core'
import { CHROME, sleep } from './f-lib.mjs'
const browser = await chromium.launch({ executablePath: CHROME, headless: true })
let failures = 0
const check = (ok, name) => { if (!ok) failures++; console.log(`${ok ? '✓' : '✗'} ${name}`) }
try {
  for (const [name, width, height] of [['iPhone-16-Pro', 402, 874], ['iPhone-17-Pro-Max', 440, 956]]) {
    const ctx = await browser.newContext({ viewport: { width, height }, isMobile: true, hasTouch: true, deviceScaleFactor: 3, reducedMotion: 'reduce' })
    await ctx.addInitScript(() => localStorage.setItem('hkline-m-v1', JSON.stringify({ page: 'chart', symbol: 'BTCUSDT', interval: '15m', skin: 'sage', theme: 'light', bigTradeSigns: false, routePicked: true, routePolicy: 'gateway', greenUpMigrated: true })))
    const p = await ctx.newPage(), errors = []
    p.on('pageerror', e => errors.push(e.message))
    await p.goto((process.argv[2] || 'http://127.0.0.1:5178/web/m/') + '#chart', { waitUntil: 'domcontentloaded' })
    await p.waitForSelector('.cp-insight-entry:not([hidden])')
    const button = p.locator('.cp-insight-entry'), e = await button.boundingBox(), x = e.x + e.width / 2, y = e.y + e.height / 2
    await button.click(); await p.waitForSelector('.bt-wrap.in')
    check(await p.locator('.bt-wrap.in').count() === 1, `${name} 点击打开`)
    await sleep(450); await p.locator('.bt-bk').click(); await sleep(200)
    const drag = async (dx, dy) => { await p.mouse.move(x, y); await p.mouse.down(); await p.mouse.move(x + dx, y + dy, { steps: 8 }); await p.mouse.up() }
    await drag(90, 0)
    // 模拟浏览器在拖动完成后仍补发click，必须由业务抑制窗口吞掉。
    await button.dispatchEvent('click')
    check(await p.locator('.bt-wrap.in').count() === 0, `${name} 横向拖动及补发click不开`)
    await sleep(550); await drag(0, 55); await button.dispatchEvent('click')
    check(await p.locator('.bt-wrap.in').count() === 0, `${name} 下滑及补发click不开`)
    await sleep(550); await button.dispatchEvent('pointerdown', { isPrimary: true, pointerId: 93, clientX: x, clientY: y }); await button.dispatchEvent('pointercancel', { pointerId: 93 }); await button.dispatchEvent('click')
    check(await p.locator('.bt-wrap.in').count() === 0, `${name} pointercancel及补发click不开`)
    await sleep(550); await drag(0, -70); await p.waitForSelector('.bt-wrap.in')
    check(await p.locator('.bt-wrap.in').count() === 1, `${name} 合格纵向上滑打开`)
    check(errors.length === 0, `${name} 页面无异常${errors.length ? ': ' + errors.join('; ') : ''}`)
    await ctx.close()
  }
} finally { await browser.close() }
process.exit(failures ? 1 : 0)
