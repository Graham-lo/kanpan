// 盘口洞察：真实只读网络、两台目标视口、三皮肤浅深；不合成行情或价区。
// node scripts/m-insights.mjs [http://127.0.0.1:5178/web/m/] [/tmp/kanpan-insights-web-evidence]
import { chromium } from 'playwright-core'
import { mkdirSync, writeFileSync } from 'node:fs'
import { CHROME, corsShim, sleep } from './f-lib.mjs'
const url = process.argv[2] || 'http://127.0.0.1:5178/web/m/'
const out = process.argv[3] || '/tmp/kanpan-insights-web-evidence'
const smoke = process.env.INSIGHT_SMOKE === '1'
mkdirSync(out, { recursive: true })
const browser = await chromium.launch({ executablePath: CHROME, headless: true })
const results = [], responses = []; let failures = 0
const check = (ok, label) => { if (!ok) failures++; results.push({ ok, label }); console.log(`${ok ? '✓' : '✗'} ${label}`) }
try {
  for (const [device, width, height] of [['iPhone-16-Pro', 402, 874], ['iPhone-17-Pro-Max', 440, 956]]) {
    for (const skin of ['sage', 'terra', 'classic']) for (const scheme of ['light', 'dark']) {
      if (smoke && (skin !== 'sage' || scheme !== 'light')) continue
      const ctx = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 3, isMobile: true, hasTouch: true, locale: 'zh-CN', timezoneId: 'Asia/Shanghai', colorScheme: scheme })
      await corsShim(ctx)
      await ctx.routeWebSocket(u => /^wss?:\/\/(?:localhost|127\.0\.0\.1)(:\d+)?\//.test(String(u)) && /[?&]token=/.test(String(u)), () => {})
      await ctx.addInitScript(seed => { localStorage.clear(); localStorage.setItem('hkline-m-v1', JSON.stringify(seed)) }, { page: 'chart', symbol: 'BTCUSDT', interval: '15m', skin, theme: scheme, bigTradeSigns: true, routePicked: true, routePolicy: 'gateway', greenUpMigrated: true })
      const p = await ctx.newPage(), errors = []; p.on('pageerror', e => errors.push(e.message))
      p.on('response', r => { if (r.url().includes('/orderflow/insights?')) responses.push({ device, skin, scheme, status: r.status() }) })
      await p.goto(url + '#chart', { waitUntil: 'domcontentloaded' })
      await p.waitForSelector('.cp-insight-entry:not([hidden])')
      // Require real candle pixels before preserving an entry screenshot; no empty-chart acceptance.
      const candles = await p.waitForFunction(() => [...document.querySelectorAll('.cp-chart canvas')].some(c => {
        if (!c.width || !c.height) return false
        const data = c.getContext('2d')?.getImageData(0, 0, c.width, c.height).data
        if (!data) return false
        let n = 0
        for (let j = 0; j < data.length; j += 4) if (data[j + 3] > 180 && ((data[j + 1] > 100 && data[j] < data[j + 1] * .65 && data[j + 2] < data[j + 1] * 1.1) || (data[j] > 100 && data[j + 1] < data[j] * .65 && data[j + 2] < data[j] * .7))) { if (++n > 20) return true }
        return false
      }), null, { timeout: 45_000 }).then(() => true, () => false)
      check(candles, `${device} ${skin}/${scheme} 真实K线已绘制`)
      if (!candles) { await ctx.close(); continue }
      if (skin === 'sage' && scheme === 'light') {
        const e = await p.locator('.cp-insight-entry').boundingBox()
        check(e.height >= 44, `${device} 入口44px且在图表外`)
        await p.screenshot({ path: `${out}/${device}-entry.png` })
        await p.mouse.move(e.x + e.width / 2, e.y + e.height / 2); await p.mouse.down(); await p.mouse.move(e.x + e.width / 2 + 95, e.y + e.height / 2, { steps: 8 }); await p.mouse.up()
        check(await p.locator('.bt-wrap.in').count() === 0, `${device} 入口横向手势不打开洞察`)
        await p.mouse.move(e.x + e.width / 2, e.y + e.height / 2); await p.mouse.down(); await p.mouse.move(e.x + e.width / 2, e.y - 80, { steps: 8 }); await p.mouse.up()
      } else await p.locator('.cp-insight-entry').click()
      await p.waitForSelector('.bt-wrap.in')
      await sleep(1600)
      const state = await p.evaluate(() => {
        const root = document.querySelector('.bt-sheet'), body = document.querySelector('.bt-body'), r = root.getBoundingClientRect()
        return { top: r.top, height: r.height, viewport: innerHeight, overflow: body.scrollWidth > body.clientWidth, title: root.getAttribute('aria-label'), modal: root.getAttribute('aria-modal'), inert: document.querySelector('#m-app').inert,
          sections: [...document.querySelectorAll('[data-insight]')].map(s => s.dataset.insight), status: document.querySelector('.bt-insight-status').textContent }
      })
      check(Math.abs(state.top) < 1 && Math.abs(state.height - state.viewport) < 1 && !state.overflow && state.title === '盘口洞察' && state.modal === 'true' && state.inert, `${device} ${skin}/${scheme} 真全屏、安全区、模态、无横向溢出`)
      check(state.sections.join(',') === 'walls,zones,activity,liquidation,events', `${device} ${skin}/${scheme} 信息纵向顺序一致`)
      await p.screenshot({ path: `${out}/${device}-${skin}-${scheme}-top.png` })
      const summary = p.locator('[data-insight="zones"] summary')
      await summary.click(); await summary.focus()
      await p.evaluate(() => { window.__insightFocusRef = document.activeElement; window.__insightScrollTop = document.querySelector('.bt-body').scrollTop })
      await sleep(1100)
      const keep = await p.evaluate(() => ({ sameFocus: window.__insightFocusRef === document.activeElement, sameScroll: Math.abs(window.__insightScrollTop - document.querySelector('.bt-body').scrollTop) < 2, open: document.querySelector('[data-insight="zones"] details').open }))
      check(keep.sameFocus && keep.sameScroll && keep.open, `${device} ${skin}/${scheme} 实时刷新保留证据展开/焦点/滚动`)
      await p.evaluate(() => { const b = document.querySelector('.bt-body'); b.scrollTop = b.scrollHeight })
      await p.screenshot({ path: `${out}/${device}-${skin}-${scheme}-bottom.png` })
      await p.locator('.bt-hdr .bt-pill').click(); await sleep(400)
      check(await p.locator('.bt-wrap').evaluate(n => n.classList.contains('parked')), `${device} ${skin}/${scheme} 门槛页仍可进入`)
      await p.evaluate(() => history.back()); await sleep(450)
      await p.locator('.bt-bk').click(); await sleep(350)
      check(await p.locator('.bt-wrap.in').count() === 0 && await p.locator('#m-app').evaluate(n => !n.inert), `${device} ${skin}/${scheme} 返回恢复行情交互`)
      check(errors.length === 0, `${device} ${skin}/${scheme} 页面无异常${errors.length ? ': ' + errors.join('; ') : ''}`)
      await ctx.close()
    }
  }
} finally { await browser.close(); writeFileSync(`${out}/result.json`, JSON.stringify({ recordedAt: new Date().toISOString(), network: '真实只读；新 insights 接口部署前可能404，页面应显示无法更新', failures, responses, results }, null, 2)) }
process.exit(failures ? 1 : 0)
