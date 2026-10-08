// 临时探针：连切冷门品种，量 K 线出图 / 订单流就绪耗时与期间请求
import { launch, sleep } from './f-lib.mjs'
const BASE = process.env.URL0 || 'https://kanpan.43-160-232-253.sslip.io/web/'
const SYMS = (process.env.SYMS || 'PAYPUSDT,ETHWUSDT,ZEREBROUSDT,ALCHUSDT,SLPUSDT,CETUSUSDT,ARIAUSDT,GOATUSDT,SQDUSDT,HMSTRUSDT').split(',')
const ROUTE = process.env.ROUTE || 'gateway'
const OFON = process.env.OF === '1'
const VERBOSE = process.env.V === '1'
const b = await launch()
const ctx = await b.newContext({ viewport: { width: 1600, height: 1000 }, locale: 'zh-CN', timezoneId: 'Asia/Shanghai' })
const seed = JSON.stringify({ theme: 'dark', skin: 'sage', orderFlow: OFON, routePicked: true, route: ROUTE, greenUpMigrated: true, layout: '1', panel: OFON ? 'flow' : 'watch', slots: OFON ? { ladder: true, drawer: true } : undefined })
const ofp = JSON.stringify({ heat: OFON })
await ctx.addInitScript(([s, o]) => { if (!sessionStorage.getItem('seeded')) { sessionStorage.setItem('seeded', '1'); localStorage.clear(); localStorage.setItem('hkline-web-v1', s); localStorage.setItem('hkline-web-of-v1', o) } }, [seed, ofp])
const page = await ctx.newPage()
const reqs = []
page.on('request', r => { r._t0 = Date.now() })
page.on('requestfinished', r => reqs.push({ u: r.url(), t0: r._t0, t1: Date.now() }))
page.on('requestfailed', r => reqs.push({ u: r.url(), t0: r._t0, t1: Date.now(), fail: r.failure()?.errorText }))
page.on('pageerror', e => console.log('  [pageerror]', e.message))
const T0 = Date.now()
await page.goto(BASE + '#chart')
await page.waitForFunction(() => document.querySelector('.chart-cell canvas') && !document.querySelector('.canvas-host.pending'), null, { timeout: 40000 })
console.log(`== route=${ROUTE} orderflow=${OFON ? '全开(图上+梯子+抽屉+热力+面板)' : '关'} 首屏 ${Date.now() - T0} ms`)
await sleep(5000)
const kl = [], ofs = []
for (const s of SYMS) {
  await page.keyboard.press('Meta+k')
  await page.waitForSelector('#sq')
  await page.fill('#sq', s.replace(/USDT$/, ''))
  await sleep(300)
  const n0 = reqs.length, t = Date.now()
  await page.keyboard.press('Enter')
  let k = null, o = null
  const until = t + 20000
  while (Date.now() < until && (k == null || (OFON && o == null))) {
    const r = await page.evaluate(sym => {
      const h = document.querySelector('.chart-cell.active .canvas-host') || document.querySelector('.chart-cell .canvas-host')
      const leg = document.querySelector('.chart-cell.active')?.textContent || ''
      const empty = document.querySelector('.chart-cell.active .cell-empty')
      const kOk = h && !h.classList.contains('pending') && leg.includes(sym.replace(/USDT$/, '')) && (!empty || empty.hidden)
      const d = globalThis.__of?.()
      const oOk = d && d.symbol === sym && (d.venues?.length > 0 || d.orders > 0 || d.tape > 0)
      return { kOk: !!kOk, oOk: !!oOk }
    }, s)
    if (r.kOk && k == null) k = Date.now() - t
    if (r.oOk && o == null) o = Date.now() - t
    await sleep(20)
  }
  kl.push(k ?? 20000); if (OFON) ofs.push(o ?? 20000)
  await sleep(2500)
  const mine = reqs.slice(n0).filter(r => r.t0 >= t - 50)
  console.log(`${s.padEnd(13)} K线 ${k ?? '超时'} ms${OFON ? `  订单流 ${o ?? '超时'} ms` : ''}  请求 ${mine.length}`)
  if (VERBOSE) for (const r of mine.sort((a, b) => a.t0 - b.t0)) console.log(`   +${r.t0 - t} → +${r.t1 - t} (${r.t1 - r.t0}ms) ${r.fail || ''} ${r.u.replace(/^https?:\/\//, '').slice(0, 120)}`)
  await sleep(500)
}
const med = a => [...a].sort((x, y) => x - y)[Math.floor((a.length - 1) / 2)]
console.log(`中位 K线 ${med(kl)} ms  最大 ${Math.max(...kl)}${OFON ? `  订单流中位 ${med(ofs)} 最大 ${Math.max(...ofs)}` : ''}`)
await b.close()
