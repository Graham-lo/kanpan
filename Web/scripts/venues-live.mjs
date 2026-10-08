// Hkline Web · 2026-10-08 多交易所（Bybit + Hyperliquid）线上验收：真浏览器、真行情、直连线路
//   node scripts/venues-live.mjs [PC 地址] [手机地址]
//   默认线上 https://kanpan.43-160-232-253.sslip.io/web/ 与 /web/m/；截图落在 docs/acceptance/多交易所-Bybit-HL-2026-10-08/
// 线上品种目录（/v1/market/orderflow/instruments）与网关中继（/v1/market/ws/bybit、/hyperliquid）等服务端上线后才有 Bybit / HL；
// 在那之前只把目录这一个 REST 补上 Bybit 三本真簿（BTCUSDT 永续 / 现货、BTCUSD 币本位），WebSocket 一律不拦——
// 直连 stream.bybit.com 的真盘口、真成交。VL_HL=1 时目录里再补 HL BTC（中继没上线会连不上，只看它不拖垮别家）。
// 有 ✗ 退出码 1。
import { chromium } from 'playwright-core'
import { mkdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { CHROME, sleep, corsShim } from './f-lib.mjs'

const PC_URL = process.argv[2] || 'https://kanpan.43-160-232-253.sslip.io/web/'
const M_URL = process.argv[3] || 'https://kanpan.43-160-232-253.sslip.io/web/m/'
const OUT = fileURLToPath(new URL('../../docs/acceptance/多交易所-Bybit-HL-2026-10-08/', import.meta.url))
mkdirSync(OUT, { recursive: true })
let bad = 0
const ok = (pass, msg) => { if (!pass) bad++; console.log(`${pass ? '✓' : '✗'} ${msg}`) }

const EXTRA = [
  { exchange: 'bybit', product: 'usdtPerp', instrument: 'BTCUSDT', notional: { kind: 'linear', multiplier: 1 }, tick: 0.1 },
  { exchange: 'bybit', product: 'spot', instrument: 'BTCUSDT', notional: { kind: 'linear', multiplier: 1 }, tick: 0.1 },
  { exchange: 'bybit', product: 'coinPerp', instrument: 'BTCUSD', notional: { kind: 'inverse', contractUsd: 1 }, tick: 0.5 },
  ...(process.env.VL_HL ? [{ exchange: 'hyperliquid', product: 'usdtPerp', instrument: 'BTC', notional: { kind: 'linear', multiplier: 1 }, tick: 1 }] : []),
]
let catalogPatched = false
async function patchCatalog(ctx) {
  await ctx.route(/\/v1\/market\/orderflow\/instruments\?/, async route => {
    const cors = { 'access-control-allow-origin': route.request().headers().origin || '*', 'access-control-allow-credentials': 'true' }
    const r = await route.fetch({ timeout: 15000 })
    const body = await r.json()
    const base = new URL(route.request().url()).searchParams.get('base')
    const has = new Set((body.venues || []).map(v => v.exchange))
    if (base === 'BTC') {
      const add = EXTRA.filter(v => !has.has(v.exchange))
      if (add.length) catalogPatched = true
      body.venues = [...(body.venues || []), ...add]
    }
    route.fulfill({ status: 200, contentType: 'application/json', headers: cors, body: JSON.stringify(body) }).catch(() => {})
  })
}

const browser = await chromium.launch({ executablePath: CHROME, headless: true })
const venuesOf = p => p.evaluate(() => (window.__of?.()?.venues || []).map(v => `${v.exchange}:${v.product}:${v.ready ? 'ready' : '…'}`))

// ---------------- PC：大单带合墙 + 读数卡分簿 + 抽屉五家分项
{
  const ctx = await browser.newContext({ viewport: { width: 2560, height: 1440 }, deviceScaleFactor: 1, locale: 'zh-CN', timezoneId: 'Asia/Shanghai' })
  await corsShim(ctx)
  await patchCatalog(ctx)
  const st = {
    theme: 'light', skin: 'sage', updown: 'green-up', greenUpMigrated: true, route: 'direct', routePicked: true,
    layout: '1', cells: [{ symbol: 'BTCUSDT', iv: '15m' }], active: 0, pinned: ['1m', '5m', '15m', '1h', '4h', '1d'], panel: 'watch', watchTab: 'crypto',
    ind: { ma: true, ema: false, boll: false, vol: true, subs: [] }, params: null, orderFlow: true,
    drawings: {}, alerts: [], notes: [], slots: { ladder: false, drawer: true, widgets: ['watch', 'detail'] }, linkCross: true,
  }
  await ctx.addInitScript(s => { if (!sessionStorage.getItem('vl')) { sessionStorage.setItem('vl', '1'); localStorage.clear(); localStorage.setItem('hkline-web-v1', s) } }, JSON.stringify(st))
  const p = await ctx.newPage()
  const errs = []
  p.on('pageerror', e => errs.push(e.message))
  await p.goto(PC_URL + '?s=BTCUSDT&i=15m&layout=1&drawer=1#chart')
  // 三本 Bybit 簿都就绪（1000 档快照先后到）
  await p.waitForFunction(() => { const b = (window.__of?.()?.venues || []).filter(v => v.exchange === 'bybit'); return b.length >= 3 && b.every(v => v.ready) }, null, { timeout: 60000 }).catch(() => {})
  const vs = await venuesOf(p)
  ok(vs.filter(v => v.startsWith('bybit:') && v.endsWith(':ready')).length >= 3, `Bybit 簿直连就绪：${vs.filter(v => v.startsWith('bybit') || v.startsWith('hyper')).join('，')}`)
  ok(catalogPatched || vs.some(v => v.startsWith('bybit')), catalogPatched ? '线上目录还没有 Bybit，已在目录这一处补上（WebSocket 未拦）' : '线上目录已带 Bybit')
  // 等大单：线上有服务端历史，再等 Bybit 簿上的墙冒出来
  await p.waitForFunction(() => { const s = window.__of?.(); return s && s.live > 0 }, null, { timeout: 60000 }).catch(() => {})
  await sleep(20000)
  const of = await p.evaluate(() => { const s = window.__of(); return { orders: s.orders, live: s.live, vol: s.vol, liq: s.liq, tps: s.tps } })
  console.log('订单流：', JSON.stringify(of))
  await p.screenshot({ path: OUT + 'pc-1-图上大单带.png' })

  // 扫图右侧找大单带，挑读数卡里行数最多（多家合墙）的那一道
  const host = await p.evaluate(() => { const r = document.querySelector('.chart-cell .canvas-host').getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height } })
  let best = null, seen = null
  console.log('图区：', JSON.stringify(host))
  for (const fx of [0.9, 0.75, 0.6]) {
    for (let y = host.y + 30; y < host.y + host.h - 30; y += 3) {
      const x = host.x + host.w * fx
      await p.mouse.move(x, y)
      const c = await p.evaluate(() => { const e = document.querySelector('.of-card.show .hc-band'); return e ? { rows: e.querySelectorAll('.hc-books b').length, text: e.innerText } : null })
      if (!c && !seen) seen = await p.evaluate(() => document.querySelector('.of-card.show')?.innerHTML.slice(0, 200) ?? null)
      // 挑：带 Bybit 的优先，其次挂单中的、多家合并的（分簿那行最多点 3 本）
      if (c) c.score = (/Bybit/.test(c.text) ? 1000 : 0) + (/挂单中/.test(c.text) ? 100 : 0) + Math.min(c.rows, 9) + (new Set(c.text.match(/币安|OKX|Coinbase|Bybit|Hyperliquid/g)).size * 10)
      if (c && (!best || c.score > best.score)) best = { ...c, x, y }
    }
    if (best && best.score >= 1100) break
  }
  if (best) {
    await p.mouse.move(best.x, best.y); await sleep(300)
    await p.screenshot({ path: OUT + 'pc-2-大单带读数卡.png' })
    const card = await p.evaluate(() => { const r = document.querySelector('.of-card.show').getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height } })
    await p.screenshot({ path: OUT + 'pc-2b-读数卡特写.png', clip: { x: Math.max(0, card.x - 40), y: Math.max(0, card.y - 40), width: card.w + 80, height: card.h + 80 } })
    console.log('读数卡：\n' + best.text)
  }
  if (!best) console.log('扫到的别的卡：', seen)
  ok(!!best, `悬停大单带出读数卡${best ? `（分簿一行点了 ${best.rows} 本）` : ''}`)
  ok(!!best && /Bybit/.test(best.text), '读数卡分簿那行里有 Bybit')
  ok(!!best && /挂单中|已结束/.test(best.text) && !/挂着|在场|已挂/.test(best.text), '读数卡状态词是「挂单中 / 已结束」，没有口语')
  ok(!!best && best.text.indexOf('首见') < best.text.indexOf('Bybit'), '主数据（首见 / 持续 / 累计成交）在分簿行之前')
  await p.mouse.move(10, 10)

  // 抽屉：五家分项
  const dr = await p.evaluate(() => {
    const slot = document.querySelector('#drawerSlot'); if (!slot) return null
    const r = slot.getBoundingClientRect()
    const rows = [...slot.querySelectorAll('.of-sr .tx')].map(t => ({ text: t.innerText.replace(/\s+/g, ' '), over: t.scrollWidth > t.clientWidth + 1 }))
    return { rect: { x: r.x, y: r.y, w: r.width, h: r.height }, rows }
  })
  if (dr) {
    await p.screenshot({ path: OUT + 'pc-3-大单抽屉.png', clip: { x: dr.rect.x, y: dr.rect.y, width: dr.rect.w, height: dr.rect.h } })
    console.log('抽屉分项：', JSON.stringify(dr.rows))
  }
  const ex = dr?.rows.find(r => /OKX/.test(r.text))
  ok(!!ex && ['币安', 'OKX', 'Coinbase', 'Bybit', 'Hyperliquid'].every(n => ex.text.includes(n)), `抽屉分家五家：${ex?.text ?? '没找到'}`)
  ok(!!dr && dr.rows.every(r => !r.over), '抽屉分项一行放得下、没被截')
  ok(!errs.length, `PC 无页面报错${errs.length ? '：' + errs.slice(0, 3).join('；') : ''}`)
  await ctx.close()
}

// ---------------- 手机网页：「大单与爆仓」弹层的五家口径
{
  const UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 26_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.6 Mobile/15E148 Safari/604.1'
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true, userAgent: UA, locale: 'zh-CN', timezoneId: 'Asia/Shanghai' })
  await corsShim(ctx)
  await patchCatalog(ctx)
  const seed = JSON.stringify({ page: 'chart', symbol: 'BTCUSDT', interval: '15m', skin: 'sage', theme: 'light', bigTradeSigns: true, routePicked: true, routePolicy: 'direct', greenUpMigrated: true })
  await ctx.addInitScript(s => { if (!sessionStorage.getItem('vl')) { sessionStorage.setItem('vl', '1'); localStorage.clear(); localStorage.setItem('hkline-m-v1', s) } }, seed)
  const p = await ctx.newPage()
  const errs = []
  p.on('pageerror', e => errs.push(e.message))
  await p.goto(M_URL + '#chart')
  await p.waitForFunction(() => (window.__of?.()?.venues || []).some(v => v.exchange === 'bybit' && v.ready), null, { timeout: 60000 }).catch(() => {})
  const vs = await venuesOf(p).catch(() => [])
  console.log('手机订单流簿：', vs.join('，') || '（手机没挂 __of）')
  await sleep(15000)
  await p.screenshot({ path: OUT + 'm-1-图上大单签.png' })
  await p.evaluate(() => { location.search = '?open=bigtrade' })
  await p.waitForSelector('.bt-wrap.in', { timeout: 20000 }).catch(() => {})
  await sleep(4000)
  await p.screenshot({ path: OUT + 'm-2-大单与爆仓.png' })
  const sub = await p.evaluate(() => document.querySelector('.bt-sub')?.textContent ?? '')
  console.log('弹层副标题：', JSON.stringify(sub))
  ok(/^BTC( 现货)?$/.test(sub.trim()), `弹层副标题只写品种（用户 2026-10-08：标题不写交易所）：${JSON.stringify(sub)}`)
  const words = await p.evaluate(() => [...document.querySelectorAll('.bt-sheet *')].map(e => e.childElementCount === 0 ? e.textContent || '' : '').filter(t => /挂着|在场|已挂|已撤销|合并/.test(t)))
  ok(!words.length, `弹层没有口语 / 交易所合并字样${words.length ? '：' + words.slice(0, 3).join('，') : ''}`)
  await p.evaluate(() => { const b = document.querySelector('.bt-body'); if (b) b.scrollTop = b.scrollHeight }); await sleep(500)
  await p.screenshot({ path: OUT + 'm-3-大单与爆仓-底部.png' })
  ok(!errs.length, `手机无页面报错${errs.length ? '：' + errs.slice(0, 3).join('；') : ''}`)
  await ctx.close()
}

await browser.close()
console.log(bad ? `✗ ${bad} 项没过` : '✓ 全过')
process.exit(bad ? 1 : 0)
