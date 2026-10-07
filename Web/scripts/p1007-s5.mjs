// Hkline Web · 2026-10-07 压测与回归 第五节：秒线与足迹数据
//   四格都是 BTCUSDT：1s / 1m 足迹 / 15m 足迹 / 1h 足迹。
//   5.1 1s 开 MIN 分钟：每 30 s 看一次——连续（每根差 1 秒）、不重、最后一根跟得上现在。
//   5.2 秒线往左翻页：翻到服务端最早那一秒（或 3 天上限）就停、不再发请求；每页窗口 ≤ 6 小时、不早于 3 天前。
//   5.3 足迹 1m / 15m / 1h：每一分钟只用一份（实时 L / 服务端 H），接缝两边不漏不重——逐分钟和服务端接口对、整根 = 各分钟之和。
//   5.4 抽 3 分钟：图上的秒线 vs 服务端秒线接口 vs 币安 1m K 线；图上足迹逐档 vs 服务端足迹接口。
//   读图上足迹用 __fpBars（footprint.ts 的调试钩子，线上包还没有），所以这一段打本机预览：P_URL=http://localhost:5307/web/（服务端接口仍是线上的）。
//   跑法：node scripts/p1007-s5.mjs [分钟=10]
import { URL_, BASE, open, cellsOf, waitCells, sleep, ok, note, flush, setTag, shot, DATA, browserDown, sh } from './p1007-lib.mjs'

setTag('s5-data')
const MIN = +(process.argv[2] || 10)
const API = 'https://kanpan.43-160-232-253.sslip.io'
const S = 'BTCUSDT'
const cells = [{ symbol: S, iv: '1s' }, { symbol: S, iv: '1m', footprint: true }, { symbol: S, iv: '15m', footprint: true }, { symbol: S, iv: '1h', footprint: true }]
const state = { ...BASE, layout: '4', cells, pinned: ['1s', '1m', '15m', '1h', '4h', '1d'] }

const PROBE = () => {
  const NS = (window.__q = {})
  NS.cells = () => {
    let got = null
    const orig = Array.prototype.map
    Array.prototype.map = function (...a) { if (!got && this.length && this[0] && this[0].chart && this[0].host) got = this; return orig.apply(this, a) }
    try { window.__cells?.() } catch { /* 还没起来 */ } finally { Array.prototype.map = orig }
    return got
  }
  NS.ch = i => NS.cells()?.[i]?.chart ?? null
  NS.cell = i => NS.cells()?.[i] ?? null
  /** 秒线那一格：总根数、首尾、断档 / 重复 / 倒序、最后一根离现在多久 */
  NS.sec = () => {
    const b = NS.ch(0).bars
    let gaps = 0, dups = 0, back = 0, firstBad = null
    for (let j = 1; j < b.length; j++) {
      const d = b[j].t - b[j - 1].t
      if (d === 1000) continue
      if (d === 0) dups++; else if (d < 0) back++; else gaps++
      firstBad ??= [b[j - 1].t, b[j].t]
    }
    return { n: b.length, t0: b[0]?.t, t1: b[b.length - 1]?.t, lag: Date.now() - (b[b.length - 1]?.t ?? 0), gaps, dups, back, firstBad, more: NS.cell(0).more, noMore: NS.cell(0).noMore }
  }
  // 第 6 列给成交量（币的个数，Bar.bv）：服务端秒线与币安 1m 的量都是币的个数；Bar.v 是成交额（量 × 价），两边不能直接比
  NS.secRange = (a, z) => NS.ch(0).bars.filter(x => x.t >= a && x.t < z).map(x => [x.t, x.o, x.h, x.l, x.c, x.bv ?? 0])
}

const { ctx, page, errs, api } = await open(state)
await ctx.addInitScript(PROBE)
const secReq = []
page.on('request', r => {
  const u = r.url(); if (!/\/v1\/market\/klines\/seconds\?/.test(u)) return
  const q = new URL(u).searchParams
  secReq.push({ at: Date.now(), from: +q.get('from'), to: +q.get('to') })
})
await page.reload({ waitUntil: 'domcontentloaded' })
const T0 = Date.now()
ok('5.0', '四格出图（1s / 1m 足迹 / 15m 足迹 / 1h 足迹）', await waitCells(page, 4, 50, 60000), (await cellsOf(page)).map(c => `${c.iv}:${c.bars}`).join(' '))
await page.waitForFunction(() => window.__q?.ch(0) && window.__fpBars?.(1, 5), null, { timeout: 30000 })
const sec0 = await page.evaluate(() => window.__q.sec())
note('5.0', '秒线开图', `${sec0.n} 根，从 ${sh(sec0.t0)}:${new Date(sec0.t0).getUTCSeconds()} 起（服务端历史 + 逐笔），断档 ${sec0.gaps}、重复 ${sec0.dups}`)

// ───────── 5.1 1s 连开 MIN 分钟
const trace = []
for (let k = 0; k < MIN * 2; k++) {
  await sleep(30000)
  const s = await page.evaluate(() => window.__q.sec())
  trace.push({ s: (k + 1) * 30, n: s.n, gaps: s.gaps, dups: s.dups, back: s.back, lag: s.lag, firstBad: s.firstBad })
  if (k % 4 === 3) console.log(`  ${(k + 1) * 30}s：${s.n} 根，断档 ${s.gaps}、重复 ${s.dups}、倒序 ${s.back}，最后一根滞后 ${s.lag} ms`)
}
DATA.sec = { sec0, trace }
const sec1 = await page.evaluate(() => window.__q.sec())
ok('5.1', `1s 连开 ${MIN} 分钟：每 30 s 都是逐秒连续、不重不倒序`, trace.every(t => !t.gaps && !t.dups && !t.back), `采样 ${trace.length} 次；断档 ${Math.max(...trace.map(t => t.gaps))}，重复 ${Math.max(...trace.map(t => t.dups))}，倒序 ${Math.max(...trace.map(t => t.back))}${trace.find(t => t.firstBad) ? '，第一处 ' + JSON.stringify(trace.find(t => t.firstBad).firstBad) : ''}`)
ok('5.1', '最后一根一直跟得上现在（滞后 ≤ 2.5 s）', trace.every(t => t.lag <= 2500), `滞后最大 ${Math.max(...trace.map(t => t.lag))} ms、中位 ${trace.map(t => t.lag).sort((a, b) => a - b)[trace.length >> 1]} ms`)
const grew = sec1.n - sec0.n, wall = Math.round((Date.now() - T0) / 1000)
ok('5.1', '根数按秒增长（每秒一根，含补平的无成交秒）', Math.abs(grew - wall) <= 15, `${sec0.n} → ${sec1.n}（+${grew}，墙钟 ${wall} s）`)
await shot(page, 's5-1s连开之后')

// ───────── 5.4 抽 3 分钟：图上秒线 vs 服务端秒线 vs 币安 1m
const nowMin = Math.floor(Date.now() / 6e4) * 6e4
const histMin = Math.floor((T0 - 20 * 6e4) / 6e4) * 6e4           // 开图之前（历史那段）
const liveMins = [Math.floor((T0 + 3 * 6e4) / 6e4) * 6e4, nowMin - 2 * 6e4] // 开图之后（逐笔那段，已入库）
const pick = [histMin, ...liveMins]
const srvSec = async (a, z) => (await (await fetch(`${API}/v1/market/klines/seconds?symbol=${S}&from=${a}&to=${z}`)).json()).bars
const bn1m = async t => (await (await fetch(`https://fapi.binance.com/fapi/v1/klines?symbol=${S}&interval=1m&startTime=${t}&limit=1`)).json())[0]
const cmpSec = []
for (const m of pick) {
  const [mine, srv, k] = await Promise.all([page.evaluate(([a, z]) => window.__q.secRange(a, z), [m, m + 6e4]), srvSec(m, m + 6e4 - 1), bn1m(m)])
  const byT = new Map(srv.map(b => [b[0], b]))
  let same = 0, diff = [], padOk = 0, padBad = 0
  for (const b of mine) {
    const s = byT.get(b[0])
    if (!s) { if (b[5] === 0) padOk++; else padBad++; continue }
    const eq = b[1] === s[1] && b[2] === s[2] && b[3] === s[3] && b[4] === s[4] && Math.abs(b[5] - s[5]) <= 1e-6 + 1e-9 * s[5]
    if (eq) same++; else diff.push([b, s])
  }
  const agg = mine.length ? { o: mine[0][1], h: Math.max(...mine.map(b => b[2])), l: Math.min(...mine.map(b => b[3])), c: mine[mine.length - 1][4], v: mine.reduce((a, b) => a + b[5], 0) } : null
  const bn = { o: +k[1], h: +k[2], l: +k[3], c: +k[4], v: +k[5] }
  const bnOk = agg && agg.o === bn.o && agg.h === bn.h && agg.l === bn.l && agg.c === bn.c && Math.abs(agg.v - bn.v) / bn.v < 0.005
  cmpSec.push({ m, src: m === histMin ? '历史' : '逐笔', mine: mine.length, srv: srv.length, same, diff: diff.length, diffEx: diff.slice(0, 2), padOk, padBad, agg, bn, bnOk })
}
DATA.cmpSec = cmpSec
for (const c of cmpSec) {
  ok('5.4', `秒线 ${sh(c.m)}（${c.src}那段）：图上 60 根 = 服务端逐秒、补平的秒没量`, c.mine === 60 && c.same === c.srv && !c.diff && !c.padBad, `图上 ${c.mine} 根，服务端 ${c.srv} 根，相同 ${c.same}，不同 ${c.diff}${c.diff ? ' 例 ' + JSON.stringify(c.diffEx) : ''}，补平 ${c.padOk}（带量的 ${c.padBad}）`)
  ok('5.4', `秒线 ${sh(c.m)} 并成 1 分钟 = 币安 1m（开高低收相同、量差 < 0.5%）`, c.bnOk, `图上 ${JSON.stringify(c.agg)} / 币安 ${JSON.stringify(c.bn)}`)
}

// ───────── 5.3 足迹接缝：1m / 15m / 1h 逐分钟对服务端
const srvFp = async (a, z) => (await (await fetch(`${API}/v1/market/orderflow/footprint?symbol=${S}&from=${a}&to=${z}`)).json())
const fpCheck = []
for (const [i, n] of [[1, 40], [2, 6], [3, 3]]) {
  const fb = await page.evaluate(([i, n]) => window.__fpBars(i, n), [i, n])
  const allMins = fb.bars.flatMap(b => b.mins)
  const a = allMins[0][0], z = Math.floor(Date.now() / 6e4) * 6e4
  const srv = []
  for (let e = z; e > a; e -= 864e5) srv.push(...(await srvFp(Math.max(a, e - 864e5), e)).minutes)
  const sm = new Map(srv.map(m => [m.t, m.rows.reduce((x, r) => [x[0] + r[1], x[1] + r[2]], [0, 0])]))
  const done = Date.now() - 70e3                                    // 收线 + 3 s 入库之后才拿得到；最近那分钟不比
  const res = { i, iv: cells[i].iv, step: fb.step, srcLine: fb.bars.map(b => b.src).join('|'), H: 0, L: 0, gapL: 0, miss: 0, hExact: 0, hBad: [], lRatio: [], sumBad: [] }
  for (const b of fb.bars) {
    const sb = b.mins.reduce((x, m) => x + m[2], 0), ss = b.mins.reduce((x, m) => x + m[3], 0)
    if (Math.abs(sb - b.buy) > 1e-6 * (b.buy + 1) || Math.abs(ss - b.sell) > 1e-6 * (b.sell + 1)) res.sumBad.push(b.t)
    for (const [mt, src, buy, sell] of b.mins) {
      if (mt + 6e4 > done) continue
      const s = sm.get(mt)
      if (src === 'l') res.gapL++
      if (src === '-') { if (s && s[0] + s[1] > 0) res.miss++; continue }
      if (!s) continue
      if (src === 'H') { res.H++; if (Math.abs(buy - s[0]) <= 1e-6 * (s[0] + 1) && Math.abs(sell - s[1]) <= 1e-6 * (s[1] + 1)) res.hExact++; else res.hBad.push([mt, buy, sell, s]) }
      if (src === 'L') { res.L++; res.lRatio.push(+((buy + sell) / (s[0] + s[1])).toFixed(3)) }
    }
  }
  fpCheck.push(res)
}
DATA.fp = fpCheck
for (const r of fpCheck) {
  const lr = r.lRatio, lo = lr.length ? Math.min(...lr) : null, hi = lr.length ? Math.max(...lr) : null
  const seam = /H+L/.test(r.srcLine.replace(/\|/g, ''))
  ok('5.3', `足迹 ${r.iv}：历史 → 实时接缝在图上（H…H 接 L…L，中间没有空分钟）`, seam && !r.gapL && !r.miss, `每根每分钟来源 ${r.srcLine.slice(-90)}；实时覆盖里缺的分钟 ${r.gapL}，服务端有而图上空的 ${r.miss}`)
  ok('5.3', `足迹 ${r.iv}：服务端那段逐分钟和接口完全一样`, r.H > 0 && r.hExact === r.H, `${r.hExact}/${r.H} 分钟${r.hBad.length ? '，不同例 ' + JSON.stringify(r.hBad.slice(0, 2)) : ''}`)
  ok('5.3', `足迹 ${r.iv}：实时那段逐分钟成交额 ≈ 服务端（0.85–1.15 倍：重了会 ≈2、漏了会 ≈0）`, lr.length >= 3 && lo >= 0.85 && hi <= 1.15, `${lr.length} 分钟，比值 ${lo}–${hi}：${lr.join(' ')}`)
  ok('5.3', `足迹 ${r.iv}：整根 = 各分钟之和（并分钟不重算）`, !r.sumBad.length, r.sumBad.length ? `不等的根 ${r.sumBad.map(sh).join(', ')}` : `${r.srcLine.split('|').length} 根都等`)
}

// 抽 3 分钟逐档：历史一分钟（应完全一样）+ 实时两分钟（逐档差额占比）
const fb1 = await page.evaluate(() => window.__fpBars(1, 40, true))
const byT1 = new Map(fb1.bars.map(b => [b.t, b]))
const rowsPick = [fb1.bars.find(b => b.src === 'H')?.t, ...fb1.bars.filter(b => b.src === 'L' && b.t + 6e4 < Date.now() - 70e3).slice(-2).map(b => b.t)].filter(Boolean)
const rowCmp = []
for (const t of rowsPick) {
  const mine = byT1.get(t), srv = (await srvFp(t, t + 6e4)).minutes.find(m => m.t === t)
  const sm = new Map((srv?.rows || []).map(r => [Math.round(r[0] / fb1.step), r]))
  const mm = new Map(mine.rows.map(r => [Math.round(r[0] / fb1.step), r]))
  let l1 = 0, tot = 0
  for (const k of new Set([...sm.keys(), ...mm.keys()])) { const a = mm.get(k) || [0, 0, 0], b = sm.get(k) || [0, 0, 0]; l1 += Math.abs(a[1] - b[1]) + Math.abs(a[2] - b[2]); tot += b[1] + b[2] }
  rowCmp.push({ t, src: mine.src, levelsMine: mm.size, levelsSrv: sm.size, l1: +(l1 / tot).toFixed(4) })
}
DATA.rowCmp = rowCmp
for (const r of rowCmp) ok('5.4', `足迹逐档 ${sh(r.t)}（${r.src === 'H' ? '服务端' : '实时'}那段）：和接口逐档${r.src === 'H' ? '完全一样' : '差额占比 < 15%'}`, r.src === 'H' ? r.l1 < 1e-9 && r.levelsMine === r.levelsSrv : r.l1 < 0.15, `档数 图上 ${r.levelsMine} / 接口 ${r.levelsSrv}，逐档绝对差之和 / 成交额 = ${r.l1}`)
ok('5.4', '抽满 3 分钟逐档', rowCmp.length === 3, rowCmp.map(r => sh(r.t)).join(', '))
await shot(page, 's5-足迹1m-15m-1h')

// ───────── 5.2 秒线往左翻页到头
const before = await page.evaluate(() => window.__q.sec())
const nReq0 = secReq.length
// 拖到最左那根之外，跟手拖一样催一次 maybeMore（只改 rightBar 不会去取更早的）
const push = () => page.evaluate(() => { const ch = window.__q.ch(0); ch.rightBar = Math.floor(ch.plotW() / ch.spacing) - 5; ch.dirty = true; ch.maybeMore() })
const pages = []
for (let k = 0; k < 20; k++) {
  await push(); await sleep(1500)
  const s = await page.evaluate(() => window.__q.sec())
  pages.push({ n: s.n, t0: s.t0, noMore: s.noMore, req: secReq.length - nReq0 })
  if (s.noMore) break
}
await push(); await sleep(1500); await push(); await sleep(1500)
const after = await page.evaluate(() => window.__q.sec())
const pageReq = secReq.slice(nReq0)
const srvFirst = (await srvSec(Date.now() - 6 * 36e5 + 1000, Date.now()))[0]?.[0]
DATA.paging = { before, after, pages, pageReq, srvFirst }
const okWin = pageReq.every(r => r.to - r.from <= 6 * 36e5 && r.from >= Math.floor((r.at - 3 * 864e5) / 1e3) * 1e3 - 1000)
ok('5.2', '往左翻页：翻到服务端最早那一秒就停（标记到头、之后再推也不发请求）', after.noMore && pages[pages.length - 1].req === pageReq.length, `翻页请求 ${pageReq.length} 次，到头后又推 2 次请求数不变；图上最早 ${sh(after.t0)}:${new Date(after.t0).getUTCSeconds()}，服务端最早 ${srvFirst ? sh(srvFirst) + ':' + new Date(srvFirst).getUTCSeconds() : '—'}（秒线 14:57 才上线，攒的还不到 3 天）`)
ok('5.2', '每页窗口 ≤ 6 小时、左沿不早于 3 天前', okWin, pageReq.map(r => `${sh(r.from)}→${sh(r.to)}（${((r.to - r.from) / 36e5).toFixed(2)} h）`).join('；'))
ok('5.2', '翻页之后秒线仍连续', !after.gaps && !after.dups && !after.back, `${after.n} 根，断档 ${after.gaps}、重复 ${after.dups}`)
// 3 天上限直接问服务端：3 天又 1 小时前那一窗应是空的（只留 3 天），前端在 floor 以左也不再发
const old = await srvSec(Date.now() - (3 * 24 + 6) * 36e5, Date.now() - (3 * 24 + 1) * 36e5)
note('5.2', '3 天以前那一窗（服务端直接问）', `${old.length} 根`)

ok('5.5', '整段控制台无报错、接口无 5xx', !errs.length && !Object.keys(api.byStatus).some(s => +s >= 500), `${errs.slice(0, 3).join(' | ')} 接口状态 ${JSON.stringify(api.byStatus)}`)
flush()
await browserDown()
console.log('地址', URL_)
