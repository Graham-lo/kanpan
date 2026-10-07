// §50 第二节：十六图（重点）——足迹 / 等幅 / 平均 K 线 / 回放各一格，其余 1 秒 / 1 分 / 15 分混排
//   5 分钟帧时间中位 / P95、主线程占用、内存增长、WebSocket 连接数；布局集切 20 次（耗时、监听 / 定时器 / 连接有无泄漏）；
//   切 4 / 9 / 1 格再回 16。node scripts/p1007-s2.mjs [分钟=5]
import { URL_, BASE, open, cellsOf, waitCells, pickLayout, frames, metrics, sleep, med, pct, ok, note, flush, setTag, shot, DATA, browserDown, startReplay, armReady } from './p1007-lib.mjs'
import { diffGl } from './f-lib.mjs'

setTag('s2-layout16')
const MIN = +(process.argv[2] || 5)
const A = [
  { symbol: 'BTCUSDT', iv: '1m', footprint: true },
  { symbol: 'ETHUSDT', iv: '1m', range: true }, // 等幅只由 1 分钟合成
  { symbol: 'SOLUSDT', iv: '15m', ha: true },
  { symbol: 'BNBUSDT', iv: '15m' }, // 回放这一格
  ...['XRPUSDT', 'DOGEUSDT', 'ADAUSDT', 'LINKUSDT'].map(symbol => ({ symbol, iv: '1s' })),
  ...['AVAXUSDT', 'SUIUSDT', 'XAUUSDT', 'LTCUSDT'].map(symbol => ({ symbol, iv: '1m' })),
  ...['TRXUSDT', 'NVDAUSDT', 'XAGUSDT', 'TSLAUSDT'].map(symbol => ({ symbol, iv: '15m' })),
]
const B = [
  { symbol: 'ETHUSDT', iv: '1m', footprint: true }, { symbol: 'BTCUSDT', iv: '1h', ha: true }, { symbol: 'SOLUSDT', iv: '1m', range: true },
  { symbol: 'BTCUSDT', iv: '1s' }, { symbol: 'XRPUSDT', iv: '4h' }, { symbol: 'DOGEUSDT', iv: '15m' },
  { symbol: 'BNBUSDT', iv: '1m' }, { symbol: 'XAUUSDT', iv: '1h' }, { symbol: 'NVDAUSDT', iv: '1d' },
]
const state = { ...BASE, layout: '16', cells: A, layouts: { active: 'p16', sets: [{ id: 'p16', name: '十六图压测', layout: '16', cells: A }, { id: 'p9', name: '九图', layout: '9', cells: B }] } }

const { page, cdp, errs, api, ctx } = await open(state)
const t0 = Date.now()
const loaded = await waitCells(page, 16, 1, 60000)
const firstMs = Date.now() - t0
let cs = await cellsOf(page)
ok('2.0', '十六格全部出图（真 K 线、直连）', loaded, `首屏 ${firstMs} ms；` + cs.map(c => `${c.symbol.replace('USDT', '')}/${c.iv}:${c.bars}`).join(' '))
const flags = await page.evaluate(() => JSON.parse(localStorage.getItem('hkline-web-v1')).cells.slice(0, 3).map(c => ['footprint', 'ha', 'range'].filter(k => c[k]).join()))
ok('2.0', '第 0 / 1 / 2 格分别是足迹 / 等幅 / 平均 K 线', flags.join('|') === 'footprint|range|ha', flags.join('|'))
DATA.firstLoad = { ms: firstMs, api: { ...api, slow: api.slow.slice(0, 20) } }
note('2.0', '首屏服务端历史请求', `共 ${api.n} 条、同时在途峰值 ${api.max}、状态 ${JSON.stringify(api.byStatus)}、按路径 ${JSON.stringify(api.byPath)}`)
ok('2.0', '首屏历史请求没有 429 / 5xx', !Object.keys(api.byStatus).some(s => s === '429' || /^5/.test(s)), JSON.stringify(api.byStatus))

// 第 3 格回放（BNB 15 分，2 天前起，4×）
// 4× = 每秒 4 根；15m 从 30 天前起播有 2880 根，挂满 5 分钟（1200 根）也走不到现在
const rs0 = await startReplay(page, 3, Date.now() - 30 * 864e5, 4)
ok('2.0', '第 4 格进入回放、4× 播放', rs0?.idx === 3 && rs0.playing && rs0.speed === 4, JSON.stringify(rs0))
await page.mouse.move(5, 700)
await sleep(15000)
await shot(page, 's2-十六图-足迹等幅平均回放秒线')

// ── 5 分钟挂着跟推送
const m0 = await metrics(cdp, page)
const heap = [], wsN = []
const fr = await frames(page, cdp, async () => {
  for (let k = 0; k < MIN * 6; k++) {
    await sleep(10000)
    const h = await page.evaluate(() => performance.memory.usedJSHeapSize / 1048576)
    const s = await page.evaluate(() => ({ live: window.__f.ws.live.size, conns: window.__stream().conns.length, subs: window.__stream().subscribed.length }))
    heap.push(+h.toFixed(1)); wsN.push(s)
  }
})
const m1 = await metrics(cdp, page)
const rs1 = await page.evaluate(() => window.__replay())
DATA.idle = { fr, heap, wsN, m0: { heap: m0.heap, nodes: m0.nodes, listeners: m0.listeners, iv: m0.iv, to: m0.to, ws: m0.ws.live }, m1: { heap: m1.heap, nodes: m1.nodes, listeners: m1.listeners, iv: m1.iv, to: m1.to, ws: m1.ws.live }, replay: rs1 }
ok('2.1', `十六格挂 ${MIN} 分钟：帧时间中位 ≤ 17.5 ms、P95 ≤ 33 ms`, fr.p50 <= 17.5 && fr.p95 <= 33.4, `中位 ${fr.p50} / P95 ${fr.p95} / P99 ${fr.p99} / 最长 ${fr.max} ms，> 33 ms 帧 ${fr.over33}/${fr.n}，长任务 ${fr.lt} 条（最长 ${fr.ltMax} ms）`)
ok('2.1', '主线程占用 < 60%', fr.cpu < 60, `${fr.cpu}%`)
const growth = +(m1.heap - m0.heap).toFixed(1)
ok('2.1', `${MIN} 分钟内存增长（两次 GC 后）< 15 MB`, growth < 15, `堆 ${m0.heap} → ${m1.heap} MB（+${growth}），期间未 GC 采样 ${heap.join(' ')}；节点 ${m0.nodes}→${m1.nodes}，JS 监听 ${m0.listeners}→${m1.listeners}`)
const live = wsN.map(x => x.live)
note('2.1', 'WebSocket 活连接', JSON.stringify(await page.evaluate(() => [...window.__f.ws.live].map(w => w.__u.replace(/\?.*/, '')))))
ok('2.1', 'WebSocket 连接数稳定（不随时间涨）', Math.max(...live) === Math.min(...live), `活连接 ${[...new Set(live)].join('/')} 条，流内连接 ${[...new Set(wsN.map(x => x.conns))].join('/')}，订阅 ${[...new Set(wsN.map(x => x.subs))].join('/')} 路`)
ok('2.1', '回放一直在走（没被别格推送打断）', rs1 && rs1.playing && (rs1.clock - rs0.clock) / 9e5 >= MIN * 60 * 4 * 0.8, rs1 ? `回放钟推进 ${((rs1.clock - rs0.clock) / 9e5).toFixed(0)} 根（4× 挂 ${MIN} 分钟应走 ${MIN * 240} 根）` : '回放没了')
cs = await cellsOf(page)
ok('2.1', '十六格 K 线没有断档（holes=0；秒线一秒没成交就没有那根、等幅 K 线本来不按时间等距，这两种只记数）', cs.filter((c, i) => c.iv !== '1s' && i !== 1).every(c => !c.holes), cs.map(c => `${c.symbol.replace('USDT', '')}/${c.iv}:${c.holes}`).join(' '))

// ── 布局集切 20 次（⌥2 / ⌥1）
await page.locator('.chart-cell').nth(5).locator('.canvas-host').click({ position: { x: 40, y: 40 } }).catch(() => {})
await page.mouse.move(5, 700)
const sw = []
const want = { 1: 16, 2: 9 }
// 先来回一趟预热（第一次进九图要建格子、拉历史）
for (const n of [2, 1]) { await page.keyboard.press(`Alt+Digit${n}`); await waitCells(page, want[n], 1, 60000); await sleep(2000) }
await sleep(5000)
const s0 = await metrics(cdp, page)
const kw0 = { ...(api.kw || { n: 0, w: 0 }) }, sw0 = Date.now()
for (let k = 0; k < 20; k++) {
  const n = k % 2 ? 1 : 2
  await armReady(page)
  const a = Date.now()
  await page.keyboard.press(`Alt+Digit${n}`)
  let done = await waitCells(page, want[n], 1, 2500), slow = null
  if (!done) { slow = (await cellsOf(page)).map((c, i) => ({ i, s: c.symbol, iv: c.iv, bars: c.bars, empty: c.empty, metaSym: c.metaSym, metaIv: c.metaIv })).filter(c => !c.bars || c.empty); done = await waitCells(page, want[n], 1, 60000) }
  const per = await page.evaluate(() => window.__ready)
  sw.push({ to: want[n], ms: Date.now() - a, done, slow, per })
  if (slow) console.log('  慢切换', Date.now() - a, 'ms，2.5 s 时没出图的格：', JSON.stringify(slow))
  await sleep(1200)
}
const kwN = (api.kw?.n || 0) - kw0.n, kwW = (api.kw?.w || 0) - kw0.w, kwMin = (Date.now() - sw0) / 6e4
DATA.kw = { n: kwN, w: kwW, min: +kwMin.toFixed(2), byW: api.kw?.byW }
ok('2.2', '切 20 次花的币安 K 线权重 / 分钟 < 本地预算一半（600）', kwW / kwMin < 600, `${kwN} 次 K 线请求，权重 ${kwW}（${(kwW / kwMin).toFixed(0)} / 分钟，预算 1200），整段权重分档 ${JSON.stringify(api.kw?.byW)}`)
const slowCell = {}
for (const x of sw) for (const [i, ms] of Object.entries(x.per || {})) if (ms > 600) slowCell[`${x.to}:${i}`] = (slowCell[`${x.to}:${i}`] || 0) + 1
note('2.2', '每次切换里 > 600 ms 才出图的格（布局:格号→次数）', JSON.stringify(slowCell))
await sleep(8000)
const s1 = await metrics(cdp, page)
const msTo = n => sw.filter(x => x.to === n).map(x => x.ms)
DATA.switch = { sw, s0: { heap: s0.heap, nodes: s0.nodes, listeners: s0.listeners, iv: s0.iv, ivBy: s0.ivBy, to: s0.to, ws: s0.ws, gl: s0.gl }, s1: { heap: s1.heap, nodes: s1.nodes, listeners: s1.listeners, iv: s1.iv, ivBy: s1.ivBy, to: s1.to, ws: s1.ws, gl: s1.gl } }
ok('2.2', '布局集切 20 次全部到位', sw.every(x => x.done), `→十六图 中位 ${med(msTo(16))} ms / 最长 ${Math.max(...msTo(16))} ms；→九图 中位 ${med(msTo(9))} ms / 最长 ${Math.max(...msTo(9))} ms`)
ok('2.2', '切换耗时中位 < 1500 ms', med(sw.map(x => x.ms)) < 1500, `全部 ${sw.map(x => x.ms).join(' ')}`)
const dgl = diffGl(s0.gl, s1.gl)
ok('2.2', '切 20 次后窗口 / 文档监听不涨', !Object.values(dgl).some(v => v > 0), JSON.stringify(dgl))
ok('2.2', '切 20 次后 interval 不涨、timeout 不堆积', s1.iv <= s0.iv && s1.to <= s0.to + 20, `interval ${s0.iv}→${s1.iv}，timeout ${s0.to}→${s1.to}`)
ok('2.2', '切 20 次后 WebSocket 活连接不涨', s1.ws.live <= s0.ws.live, `活 ${s0.ws.live}→${s1.ws.live}，期间开 ${s1.ws.opened - s0.ws.opened} 关 ${s1.ws.closed - s0.ws.closed}，订 ${s1.ws.subs - s0.ws.subs} 退 ${s1.ws.unsubs - s0.ws.unsubs}`)
ok('2.2', '切 20 次后 DOM 节点 / JS 监听 / 堆不涨（容差：节点 +5%、堆 +10 MB）', s1.nodes <= s0.nodes * 1.05 && s1.listeners <= s0.listeners * 1.05 && s1.heap - s0.heap < 10, `节点 ${s0.nodes}→${s1.nodes}，JS 监听 ${s0.listeners}→${s1.listeners}，堆 ${s0.heap}→${s1.heap} MB`)
const sub = await page.evaluate(() => { const cs = window.__cells(), s = window.__stream().subscribed; const want = new Set(cs.map(c => `${c.symbol.toLowerCase()}@kline_${c.iv}`)); const have = s.filter(x => x.includes('@kline_')); return { extra: have.filter(x => !want.has(x) && !x.endsWith('_1s')), total: s.length } })
ok('2.2', '切完订阅与格子对得上（没有残留旧格的 K 线流）', !sub.extra.length, `总订阅 ${sub.total}，多余 ${JSON.stringify(sub.extra)}`)

// ── 4 / 9 / 1 再回 16
const before = (await cellsOf(page)).map(c => c.symbol + '/' + c.iv)
const lay = []
for (const k of ['4', '9', '1', '16']) {
  const a = Date.now(); await pickLayout(page, k); const d = await waitCells(page, +k, 1, 60000); lay.push({ k, ms: Date.now() - a, d })
  await sleep(1500)
  if (k === '9') await shot(page, 's2-九格')
}
const after = (await cellsOf(page)).map(c => c.symbol + '/' + c.iv)
const fl2 = await page.evaluate(() => JSON.parse(localStorage.getItem('hkline-web-v1')).cells.slice(0, 3).map(c => ['footprint', 'ha', 'range'].filter(k => c[k]).join()))
ok('2.3', '十六 → 4 → 9 → 1 → 十六：每步出图', lay.every(x => x.d), lay.map(x => `${x.k} 格 ${x.ms} ms`).join('，'))
ok('2.3', '回到十六格每格品种 / 周期 / 画法原样', JSON.stringify(before) === JSON.stringify(after) && fl2.join('|') === 'footprint|range|ha', after.slice(0, 5).join(' ') + ' … ' + fl2.join('|'))
await shot(page, 's2-回到十六图')

DATA.api = { ...api, slow: api.slow.slice(0, 30) }
note('2.4', '整段服务端历史请求', `共 ${api.n} 条，同时在途峰值 ${api.max}，状态 ${JSON.stringify(api.byStatus)}，> 3 s 的 ${api.slow.length} 条`)
ok('2.4', '整段没有 429 / 5xx', !Object.keys(api.byStatus).some(s => s === '429' || /^5/.test(s)), JSON.stringify(api.byStatus))
ok('2.4', '整段控制台无报错', !errs.length && !(await page.evaluate(() => window.__f.errs.length)), errs.slice(0, 4).join(' | '))
console.log('地址', URL_)
flush()
await ctx.close(); await browserDown()
