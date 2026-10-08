// Hkline 手机网页版 · 2026-10-08「图上大单签 + 大单与爆仓」验收（393×852，iPhone 视口）
//   node scripts/m-bigtrade.mjs [地址]
//   默认地址 http://localhost:5178/web/m/（npx vite --port 5178，开发构建才认 ?bt=）；截图落在 docs/acceptance/大单与爆仓-手机-2026-10-08/
// 走一遍：图上有签 → 点签开半屏（该根）→ 上拉提示进满屏 → 每根点一根（十字线跳过去）→ 门槛（弹层收下去）→ 关门槛回原档 → ‹ 关
// 再截：三套皮肤 × 浅 / 深的半屏，满屏，骨架 / 现货 / 爆仓空 / 停住 / 不跟。有 ✗ 退出码 1。
import { chromium } from 'playwright-core'
import { mkdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { CHROME, sleep, corsShim } from './f-lib.mjs'

const URL_ = process.argv[2] || 'http://localhost:5178/web/m/'
const OUT = fileURLToPath(new URL('../../docs/acceptance/大单与爆仓-手机-2026-10-08/', import.meta.url))
mkdirSync(OUT, { recursive: true })
const UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 26_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.6 Mobile/15E148 Safari/604.1'
let bad = 0
const ok = (pass, msg) => { if (!pass) bad++; console.log(`${pass ? '✓' : '✗'} ${msg}`) }

const browser = await chromium.launch({ executablePath: CHROME, headless: true })
async function page({ skin = 'sage', scheme = 'light', query = '', symbol = 'BTCUSDT', interval = '15m' } = {}) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true, userAgent: UA, locale: 'zh-CN', timezoneId: 'Asia/Shanghai', colorScheme: scheme })
  await corsShim(ctx)
  // 热更新通道接个空：同一工作树里别的窗口在改文件，热更新会把页面整页刷掉
  await ctx.routeWebSocket(u => /^wss?:\/\/localhost(:\d+)?\//.test(String(u)) && /[?&]token=/.test(String(u)), () => {})
  const seed = JSON.stringify({ page: 'chart', symbol, interval, skin, theme: scheme, bigTradeSigns: true, routePicked: true, routePolicy: 'gateway', greenUpMigrated: true })
  await ctx.addInitScript(s => { if (!sessionStorage.getItem('bt-seeded')) { sessionStorage.setItem('bt-seeded', '1'); localStorage.clear(); localStorage.setItem('hkline-m-v1', s) } }, seed)
  const p = await ctx.newPage()
  const errs = []
  p.on('pageerror', e => errs.push(e.message))
  await p.goto(URL_ + query + '#chart')
  return { ctx, p, errs }
}
// BT_ONLY=state-stale,sage-light-full-bottom 只重截点名的几张（其余照跑核对、不覆盖）
const ONLY = process.env.BT_ONLY ? process.env.BT_ONLY.split(',') : null
const shot = (p, name) => (ONLY && !ONLY.includes(name) ? Promise.resolve() : p.screenshot({ path: OUT + `m-${name}.png` }))
const hero = p => p.evaluate(() => ({
  title: document.querySelector('.bt-ht')?.textContent, rt: document.querySelector('[data-card="hero"] h5 .rt')?.textContent,
  full: document.querySelector('.bt-sheet')?.classList.contains('full'), parked: document.querySelector('.bt-wrap')?.classList.contains('parked'),
  open: !!document.querySelector('.bt-wrap.in'),
}))

// ---------------- 走一遍
{
  const { ctx, p, errs } = await page()
  await p.waitForFunction(() => document.querySelectorAll('.m-bigtrade-aria-sign').length >= 1, null, { timeout: 40000 }).catch(() => {})
  await sleep(800)
  const signs = await p.evaluate(() => [...document.querySelectorAll('.m-bigtrade-aria-sign')].map(b => { const r = b.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2, label: b.getAttribute('aria-label') } }))
  ok(signs.length > 0, `图上有大单签 ${signs.length} 枚${signs[0] ? '，读屏「' + signs[signs.length - 1].label + '」' : ''}`)
  await shot(p, 'sage-light-signs')
  if (signs.length) {
    const s = signs[Math.max(0, signs.length - 2)]
    await p.touchscreen.tap(s.x, s.y)
    await p.waitForSelector('.bt-wrap.in', { timeout: 5000 }).catch(() => {})
    await sleep(900)
    const h = await hero(p)
    ok(h.open && !h.full, `点签开半屏：${h.title} · ${h.rt}`)
    await shot(p, 'flow-1-sign-half')
    // 开着再点另一枚：只换根不关
    if (signs.length > 1) {
      const s2 = signs[signs.length - 1]
      await p.touchscreen.tap(s2.x, s2.y); await sleep(400)
      const h2 = await hero(p)
      ok(h2.open && h2.title !== h.title, `开着点另一枚只换根：${h.title} → ${h2.title}`)
    }
  } else {
    await p.evaluate(() => { location.search = '?open=bigtrade' }); await p.waitForSelector('.bt-wrap.in', { timeout: 8000 })
  }
  await p.click('.bt-more'); await sleep(600)
  ok((await hero(p)).full, '上拉提示 → 满屏')
  await sleep(800)
  await shot(p, 'flow-2-full')
  const col = await p.evaluate(() => { const g = [...document.querySelectorAll('svg.bt-cols g')]; const sv = document.querySelector('svg.bt-cols').getBoundingClientRect(); const i = Math.max(0, g.length - 6); return { t: g[i]?.dataset.t, x: sv.left + (i + 0.5) * sv.width / g.length, y: sv.top + sv.height / 2 } })
  await p.mouse.click(col.x, col.y); await sleep(500)
  const after = await p.evaluate(() => ({ on: document.querySelector('svg.bt-cols g.on')?.dataset.t, title: document.querySelector('.bt-ht')?.textContent }))
  ok(after.on === col.t && /^该根/.test(after.title || ''), `每根点一根：选中 ${after.on === col.t ? '对' : '错'}、卡片「${after.title}」`)
  await shot(p, 'flow-3-pick-bar')
  await p.click('.bt-hdr .bt-pill'); await sleep(700)
  const th = await hero(p)
  ok(th.parked, '门槛：弹层收下去、门槛页盖上来')
  await shot(p, 'flow-4-threshold')
  await p.evaluate(() => history.back()); await sleep(700)
  const back = await hero(p)
  ok(back.open && !back.parked && back.full, `关门槛回到原档（${back.full ? '满屏' : '半屏'}）`)
  await p.click('.bt-bk'); await sleep(500)
  ok(!(await hero(p)).open, '‹ 关掉')
  ok(!errs.length, `走一遍无页面报错${errs.length ? '：' + errs.slice(0, 3).join('；') : ''}`)
  await ctx.close()
}

// ---------------- 皮肤 × 浅深
for (const skin of ['sage', 'terra', 'classic']) {
  for (const scheme of ['light', 'dark']) {
    const { ctx, p, errs } = await page({ skin, scheme, query: '?open=bigtrade' })
    await p.waitForSelector('.bt-wrap.in', { timeout: 20000 }).catch(() => {})
    await sleep(3500)
    await shot(p, `${skin}-${scheme}-half`)
    ok(!errs.length && (await hero(p)).open, `${skin} ${scheme} 半屏${errs.length ? '：' + errs[0] : ''}`)
    if (skin === 'sage' || scheme === 'dark') {
      await p.click('.bt-more'); await sleep(1500)
      await shot(p, `${skin}-${scheme}-full`)
      await p.evaluate(() => { const b = document.querySelector('.bt-body'); b.scrollTop = b.scrollHeight }); await sleep(400)
      await shot(p, `${skin}-${scheme}-full-bottom`)
    }
    await ctx.close()
  }
}

// ---------------- 状态
for (const [bt, extra] of [['loading', {}], ['spot', { symbol: 'BTC-USD' }], ['liqEmpty', {}], ['stale', {}], ['untracked', {}]]) {
  const { ctx, p, errs } = await page({ query: `?open=bigtrade&bt=${bt}`, ...extra })
  await p.waitForSelector('.bt-wrap.in', { timeout: 20000 }).catch(() => {})
  await sleep(2500)
  const st = await p.evaluate(() => ({
    skel: !document.querySelector('.bt-hero-skel')?.hidden, liq: !!document.querySelector('.bt-liq .bt-card'),
    liqEmpty: !!document.querySelector('[data-liq="empty"]'), stale: document.querySelector('.bt-sheet')?.classList.contains('stale'),
    rt: document.querySelector('[data-card="hero"] h5 .rt')?.textContent, untracked: !document.querySelector('.bt-untracked')?.hidden,
  }))
  const pass = bt === 'loading' ? st.skel : bt === 'spot' ? !st.liq : bt === 'liqEmpty' ? st.liqEmpty : bt === 'stale' ? st.stale && /^数据停在/.test(st.rt) : st.untracked
  ok(pass && !errs.length, `状态 ${bt}：${JSON.stringify(st)}${errs.length ? '；' + errs[0] : ''}`)
  await shot(p, `state-${bt}`)
  await ctx.close()
}

await browser.close()
console.log(bad ? `✗ ${bad} 项没过` : '✓ 全部通过', '截图：', OUT)
process.exit(bad ? 1 : 0)
