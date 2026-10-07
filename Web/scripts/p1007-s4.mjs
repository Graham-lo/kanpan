// Hkline Web · 2026-10-07 压测与回归 第四节：回放压测
//   1m BTC 从 8 天前起 16× 连播 10 分钟（每秒 16 根，约 9600 根，跨预取边界几十次），量帧时间 / 主线程 / 内存；
//   回放中切 5 次周期、画线、把进度拖到两头；退出后实时恢复、最新价与币安一致。其余三格是实时格（15m / 1s / 1h）。
//   跑法：node scripts/p1007-s4.mjs [分钟=10]（P_URL=… 打本机预览）
import { URL_, BASE, open, cellsOf, waitCells, frames, metrics, sleep, ok, note, flush, setTag, shot, DATA, browserDown, startReplay, binancePx } from './p1007-lib.mjs'

setTag('s4-replay')
const MIN = +(process.argv[2] || 10)
const cells = [{ symbol: 'BTCUSDT', iv: '1m' }, { symbol: 'ETHUSDT', iv: '15m' }, { symbol: 'SOLUSDT', iv: '1s' }, { symbol: 'XRPUSDT', iv: '1h' }]
const state = { ...BASE, layout: '4', cells, pinned: ['1m', '5m', '15m', '1h', '4h', '1d'], drawColor: '#D500F9', magnet: false }
const { page, cdp, errs } = await open(state)
ok('4.0', '四格出图', await waitCells(page, 4, 50, 60000), (await cellsOf(page)).map(c => `${c.symbol}/${c.iv}:${c.bars}`).join(' '))

// 回放取数：带 startTime 的是往后补「未来」（预取），带 endTime 的是往前补历史
const fwd = [], back = []
page.on('request', r => {
  const u = r.url(); if (!/\/fapi\/v1\/klines\?/.test(u) || !/symbol=BTCUSDT/.test(u)) return
  const q = new URL(u).searchParams
  if (q.get('startTime')) fwd.push([Date.now(), q.get('interval'), +q.get('limit')])
  else if (q.get('endTime')) back.push([Date.now(), q.get('interval'), +q.get('limit')])
})

const start = Date.now() - 8 * 864e5
const rs0 = await startReplay(page, 0, start, 16)
ok('4.0', '第 1 格进回放、16× 播放', rs0?.idx === 0 && rs0.playing && rs0.speed === 16, JSON.stringify(rs0))
await page.mouse.move(5, 5)

// ───────── 4.1 16× 连播 MIN 分钟
const m0 = await metrics(cdp, page)
const trace = []
const fwd0 = fwd.length
const fr = await frames(page, cdp, async () => {
  for (let k = 0; k < MIN * 6; k++) {
    await sleep(10000)
    const r = await page.evaluate(() => window.__replay())
    const c = (await cellsOf(page))[0]
    trace.push({ s: (k + 1) * 10, clock: r?.clock, visible: r?.visible, future: r?.future, playing: r?.playing, holes: c.holes, fwd: fwd.length - fwd0 })
  }
})
const m1 = await metrics(cdp, page)
const rs1 = await page.evaluate(() => window.__replay())
DATA.play = { fr, trace, m0: { heap: m0.heap, nodes: m0.nodes, listeners: m0.listeners }, m1: { heap: m1.heap, nodes: m1.nodes, listeners: m1.listeners }, fwd: fwd.slice(fwd0) }
const adv = rs1 ? Math.round((rs1.clock - rs0.clock) / 6e4) : 0, want = MIN * 60 * 16
ok('4.1', `16× 连播 ${MIN} 分钟：一直在播、走了应走根数的 ≥ 85%`, rs1?.playing && adv >= want * 0.85, `走了 ${adv} 根（应 ${want}），图上 ${rs1?.visible} 根，手里未来 ${rs1?.future} 根`)
ok('4.1', '跨过预取边界至少两次（往后补「未来」的请求）', fwd.length - fwd0 >= 2, `${fwd.length - fwd0} 次，limit ${[...new Set(fwd.slice(fwd0).map(x => x[2]))].join('/')}；每 10 s 采样的未来根数 ${trace.map(t => t.future).join(' ')}`)
ok('4.1', '播放中未来从没见底（预取赶在播完之前）', trace.every(t => t.future > 0), `最少 ${Math.min(...trace.map(t => t.future))} 根`)
ok('4.1', '回放格 K 线连续（没有断档）', trace.every(t => !t.holes), `holes ${[...new Set(trace.map(t => t.holes))].join('/')}`)
ok('4.1', '帧时间中位 ≤ 17.5 ms、P95 ≤ 33 ms', fr.p50 <= 17.5 && fr.p95 <= 33, `中位 ${fr.p50} / P95 ${fr.p95} / P99 ${fr.p99} / 最长 ${fr.max} ms，> 33 ms 帧 ${fr.over33}/${fr.n}，长任务 ${fr.lt} 条（最长 ${fr.ltMax} ms）`)
ok('4.1', '主线程占用 < 60%', fr.cpu < 60, `${fr.cpu}%`)
ok('4.1', `${MIN} 分钟内存增长（两次 GC 后）< 20 MB`, m1.heap - m0.heap < 20, `堆 ${m0.heap} → ${m1.heap} MB，节点 ${m0.nodes}→${m1.nodes}，JS 监听 ${m0.listeners}→${m1.listeners}`)
await shot(page, 's4-16倍连播之后')

// ───────── 4.2 回放中切 5 次周期（时钟原样留着、在新周期上重新定位、接着播）
const ivs = ['5m', '15m', '1h', '5m', '1m'], ivRes = []
for (const iv of ivs) {
  const a = await page.evaluate(() => window.__replay())
  await page.click(`#toolbar .intervals [data-iv="${iv}"]`)
  const okk = await page.waitForFunction(iv => { const r = window.__replay(), c = window.__cells()[0]; return r && r.iv === iv && c.iv === iv && c.bars > 50 && r.visible > 50 }, iv, { timeout: 20000 }).then(() => true, () => false)
  await sleep(1500)
  const b = await page.evaluate(() => window.__replay()), c = (await cellsOf(page))[0]
  const ivMs = { '1m': 6e4, '5m': 3e5, '15m': 9e5, '1h': 36e5 }[iv]
  // 切过去的那一刻时钟落在新周期的整根上，之后 1.5 s 里 16× 又播了几根
  ivRes.push({ iv, ok: okk && b.playing && b.clock >= a.clock - ivMs && b.clock - a.clock <= ivMs * 40 && !c.holes, from: a.clock, to: b.clock, visible: b.visible, holes: c.holes })
}
DATA.ivs = ivRes
ok('4.2', '回放中切 5 次周期：每次都在原时刻接着播、无断档', ivRes.every(x => x.ok), ivRes.map(x => `${x.iv}:${x.ok ? '✓' : '✗'}(+${Math.round((x.to - x.from) / 6e4)} 分钟, ${x.visible} 根, holes ${x.holes})`).join(' '))

// ───────── 4.3 回放中画线（先暂停，画一条趋势线），再继续播：线还在
await page.evaluate(() => { const b = document.querySelectorAll('.chart-cell')[0].querySelector('.rp-bar'); if (window.__replay().playing) b.querySelector('[data-rp="toggle"]').click() })
const host = await page.locator('.chart-cell').nth(0).locator('.canvas-host').boundingBox()
const n0 = await page.evaluate(() => (JSON.parse(localStorage.getItem('hkline-web-v1')).drawings?.BTCUSDT || []).length)
await page.keyboard.press('Alt+KeyT'); await sleep(150)
for (const [fx, fy] of [[0.45, 0.6], [0.7, 0.35]]) { await page.mouse.move(host.x + host.width * fx, host.y + host.height * fy, { steps: 3 }); await page.mouse.down(); await page.mouse.up(); await sleep(150) }
await page.keyboard.press('Escape'); await page.mouse.move(5, 5)
const d1 = await page.evaluate(() => JSON.parse(localStorage.getItem('hkline-web-v1')).drawings?.BTCUSDT || [])
await page.evaluate(() => { const b = document.querySelectorAll('.chart-cell')[0].querySelector('.rp-bar'); if (!window.__replay().playing) b.querySelector('[data-rp="toggle"]').click() })
await sleep(4000)
const d2 = await page.evaluate(() => JSON.parse(localStorage.getItem('hkline-web-v1')).drawings?.BTCUSDT || [])
ok('4.3', '回放中画趋势线：存下，继续播后原样', d1.length === n0 + 1 && JSON.stringify(d1) === JSON.stringify(d2), `画线 ${n0}→${d1.length}→${d2.length}`)

// ───────── 4.4 进度拖到两头：最右 = 现在（一路补到最新）、最左 = 起点
const track = await page.locator('.chart-cell').nth(0).locator('.rp-track').boundingBox()
const dragTo = async fx => {
  const y = track.y + track.height / 2, x0 = track.x + track.width * 0.5
  await page.mouse.move(x0, y); await page.mouse.down(); await page.mouse.move(track.x + track.width * fx, y, { steps: 12 }); await page.mouse.up()
}
const fwdA = fwd.length
await dragTo(1.05)
const right = await page.waitForFunction(() => { const r = window.__replay(), c = window.__cells()[0]; return r && r.clock >= Math.floor(Date.now() / 6e4) * 6e4 - 2 * 6e4 && c.bars > 100 }, null, { timeout: 45000, polling: 200 }).then(() => true, () => false)
await sleep(1000)
const rR = await page.evaluate(() => window.__replay()), cR = (await cellsOf(page))[0]
ok('4.4', '进度拖到最右：时钟到现在、图上补到最新一根、无断档', right && !cR.holes, `时钟离现在 ${Math.round((Date.now() - rR.clock) / 1e3)} s，图上 ${rR.visible} 根，最后一根 ${new Date(cR.lastT + 8 * 36e5).toISOString().slice(11, 16)}，补了 ${fwd.length - fwdA} 次，holes ${cR.holes}`)
await shot(page, 's4-进度拖到最右')
await dragTo(-0.05)
const left = await page.waitForFunction(() => { const r = window.__replay(); return r && r.clock === r.start }, null, { timeout: 20000, polling: 200 }).then(() => true, () => false)
await sleep(800)
const rL = await page.evaluate(() => window.__replay()), cL = (await cellsOf(page))[0]
ok('4.4', '进度拖到最左：时钟回到起点、起点左边留着历史', left && rL.visible >= 300 && !cL.holes, `时钟 = 起点 ${left}，图上 ${rL.visible} 根，holes ${cL.holes}`)
await shot(page, 's4-进度拖到最左')

// ───────── 4.5 退出回放：实时恢复，最新价与币安一致
await page.evaluate(() => document.querySelectorAll('.chart-cell')[0].querySelector('.rp-bar [data-rp="exit"]').click())
const live = await page.waitForFunction(() => !window.__replay() && window.__cells()[0].lastT >= Math.floor(Date.now() / 6e4) * 6e4 - 6e4, null, { timeout: 30000, polling: 200 }).then(() => true, () => false)
await sleep(3000)
const px = []
for (let k = 0; k < 3; k++) {
  const [mine, bn] = await Promise.all([page.evaluate(() => window.__cells()[0].last), binancePx('BTCUSDT')])
  px.push({ mine, bn, d: Math.abs(mine - bn) / bn })
  await sleep(2000)
}
const c5 = (await cellsOf(page))[0]
ok('4.5', '退出回放：回到实时（最后一根是这一分钟）、无断档', live && !c5.holes && c5.iv === '1m', `最后一根 ${new Date(c5.lastT + 8 * 36e5).toISOString().slice(11, 16)}，${c5.bars} 根，holes ${c5.holes}`)
ok('4.5', '退出后最新价与币安一致（三次取样都差 < 0.05%）', px.every(x => x.d < 5e-4), px.map(x => `${x.mine} vs ${x.bn}（${(x.d * 100).toFixed(3)}%）`).join('；'))
const tick0 = (await cellsOf(page))[0].last; await sleep(6000); const tick1 = (await cellsOf(page))[0]
note('4.5', '推送还在走', `6 s 内最新价 ${tick0} → ${tick1.last}`)
await shot(page, 's4-退出回放回到实时')
ok('4.6', '整段控制台无报错', !errs.length, errs.slice(0, 5).join(' | '))
flush()
await browserDown()
console.log('地址', URL_)
