// Hkline Web · 2026-10-07 压测与回归 第三节：画线交叉验证（足迹 / 等幅 / 平均 K 线 / 回放 下画、拖改；
//   再切回普通 K 线、切周期、切布局集、刷新，画线都在原处、隐藏画线照样生效、画线提醒不受影响）
//   跑法：node scripts/p1007-s3.mjs（P_URL=… 打本机预览）
import { URL_, BASE, open, cellsOf, waitCells, sleep, ok, note, flush, setTag, shot, DATA, browserDown, startReplay, stateOf } from './p1007-lib.mjs'

setTag('s3-drawing-cross')
const COLOR = '#D500F9' // 指标、K 线、皮肤里都没有的一种品红，像素判定不会和别的东西撞
const SYMS = ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'BNBUSDT']
const MODE = ['足迹', '等幅 K 线', '平均 K 线', '回放']
const cells = [
  { symbol: 'BTCUSDT', iv: '1m', footprint: true },
  { symbol: 'ETHUSDT', iv: '1m', range: true },
  { symbol: 'SOLUSDT', iv: '15m', ha: true },
  { symbol: 'BNBUSDT', iv: '15m' },
]
const state = {
  ...BASE, layout: '4', cells, drawColor: COLOR, magnet: false, drawHidden: false, drawLocked: false,
  pinned: ['1m', '5m', '15m', '1h', '4h', '1d'], ind: { ma: false, ema: false, boll: false, vol: true, subs: [] },
  layouts: { active: 'q4', sets: [{ id: 'q4', name: '四图画法', layout: '4', cells }, { id: 'q1', name: '一图', layout: '1', cells: [{ symbol: 'XRPUSDT', iv: '1h' }] }] },
}

// ───────── 页内探针：拿到活的图表对象（借 __cells() 里那次 map 把格子数组捞出来），按图表自己的几何把画线投到像素，
//   同一帧里「有画线」与「关掉画线重画」各读一份，逐点看像素有没有朝画线颜色偏过去（K 线、足迹格、指标都不影响判定）
const PROBE = () => {
  const NS = (window.__q = {})
  // 弹出的提示都记下来（画线提醒要是响了，会在这里留一条）
  NS.toasts = []
  addEventListener('DOMContentLoaded', () => new MutationObserver(ms => { for (const m of ms) for (const n of m.addedNodes) if (n.nodeType === 1 && n.classList?.contains('toast')) NS.toasts.push([Date.now(), n.textContent.trim().slice(0, 120)]) }).observe(document.body, { childList: true, subtree: true }))
  NS.cells = () => {
    let got = null
    const orig = Array.prototype.map
    Array.prototype.map = function (...a) { if (!got && this.length && this[0] && this[0].chart && this[0].host) got = this; return orig.apply(this, a) }
    try { window.__cells?.() } catch { /* 还没起来 */ } finally { Array.prototype.map = orig }
    return got
  }
  NS.ch = i => NS.cells()?.[i]?.chart ?? null
  NS.geo = i => {
    const ch = NS.ch(i); if (!ch || !ch._panes) return null
    const rc = ch.ctx.canvas.getBoundingClientRect(), p = ch._panes[0]
    return { left: rc.left, top: rc.top, w: rc.width, h: rc.height, py: p.y, ph: p.h, PW: ch.plotW(), sel: ch.selected?.id ?? null, hidden: ch.drawingsHidden, n: ch.drawings.length }
  }
  const cvs = document.createElement('canvas'); cvs.width = cvs.height = 1
  const cx = cvs.getContext('2d', { willReadFrequently: true })
  const rgb = css => { cx.clearRect(0, 0, 1, 1); cx.fillStyle = '#000'; cx.fillStyle = css; cx.fillRect(0, 0, 1, 1); const d = cx.getImageData(0, 0, 1, 1).data; return [d[0], d[1], d[2]] }
  NS.frame = () => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => r())))
  const probes = (ch, d) => {
    const p = ch._panes[0], r = ch._ranges.main, PW = ch.plotW()
    const X = t => ch.indexToX(ch.indexAt(t)), Y = v => ch.priceToY(v, p, r)
    const inside = (x, y) => x >= 4 && x <= PW - 4 && y >= p.y + 4 && y <= p.y + p.h - 4
    const col = typeof d.color === 'string' && d.color ? d.color : '#2962FF'
    const A = d.pts[0], B = d.pts[1] || d.pts[0], a = { x: X(A.t), y: Y(A.p) }, b = { x: X(B.t), y: Y(B.p) }
    const P = []
    const pt = (x, y, color = col) => { if (inside(x, y)) P.push({ x, y, color }) }
    let click = null
    if (d.type === 'trend') { for (const k of [0.3, 0.5, 0.7]) pt(a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k); click = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 } }
    if (d.type === 'hline') { const x = PW * 0.48; pt(x, a.y); pt(PW * 0.3, a.y); click = { x, y: a.y } }
    if (d.type === 'fib') {
      const x0 = Math.min(a.x, b.x), x1 = Math.max(a.x, b.x)
      if (x1 - x0 >= 6) pt((x0 + x1) / 2, Math.round(Y(B.p + (A.p - B.p) * 0.5)) + 0.5, '#4CAF50')
      click = { x: (x0 + x1) / 2, y: (a.y + b.y) / 2 }
    }
    return { P, click: click && inside(click.x, click.y) ? click : null, a: inside(a.x, a.y) ? a : null }
  }
  NS.sample = i => {
    const ch = NS.ch(i); if (!ch || !ch._panes) return null
    const cv = ch.ctx.canvas, W = cv.width, H = cv.height, sc = W / cv.getBoundingClientRect().width
    ch.ctx.getImageData(0, 0, 1, 1); ch.render()
    const img = ch.ctx.getImageData(0, 0, W, H).data
    const was = ch.drawingsHidden
    ch.drawingsHidden = true; ch.render()
    const ref = ch.ctx.getImageData(0, 0, W, H).data
    ch.drawingsHidden = was; ch.render()
    const score = pr => {
      const tg = rgb(pr.color); let best = 0
      for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) {
        const X = Math.round((pr.x + dx) * sc), Y_ = Math.round((pr.y + dy) * sc)
        if (X < 0 || Y_ < 0 || X >= W || Y_ >= H) continue
        const o = (Y_ * W + X) * 4, bg = [ref[o], ref[o + 1], ref[o + 2]], px = [img[o], img[o + 1], img[o + 2]]
        const dd = [tg[0] - bg[0], tg[1] - bg[1], tg[2] - bg[2]], L = dd[0] ** 2 + dd[1] ** 2 + dd[2] ** 2
        if (L < 900) continue
        const v = [px[0] - bg[0], px[1] - bg[1], px[2] - bg[2]], f = (v[0] * dd[0] + v[1] * dd[1] + v[2] * dd[2]) / L
        if (Math.hypot(v[0] - f * dd[0], v[1] - f * dd[1], v[2] - f * dd[2]) <= 60 && f > best) best = Math.min(1.2, f)
      }
      return +best.toFixed(2)
    }
    return { hidden: was, list: ch.drawings.filter(d => d.type !== 'measure').map(d => { const q = probes(ch, d); return { id: d.id, type: d.type, vis: q.P.length > 0, s: q.P.map(score), click: q.click, a: q.a } }) }
  }
}

const { page, errs, ctx } = await open(state)
await ctx.addInitScript(PROBE)
await page.reload({ waitUntil: 'domcontentloaded' })
const ready4 = await waitCells(page, 4, 50, 60000)
ok('3.0', '四格出图（足迹 / 等幅 / 平均 / 普通 15m）', ready4, (await cellsOf(page)).map(c => `${c.symbol}/${c.iv}:${c.bars}`).join(' '))
await page.waitForFunction(() => window.__q?.ch(3)?._panes, null, { timeout: 20000 })

// 第 4 格进回放（三天前起，停着不播：在回放里画线）
const rp = await startReplay(page, 3, Date.now() - 3 * 864e5, 1)
await page.evaluate(() => { const b = document.querySelectorAll('.chart-cell')[3].querySelector('.rp-bar'); if (window.__replay()?.playing) b.querySelector('[data-rp="toggle"]').click() })
ok('3.0', '第 4 格进了回放（停在三天前）', rp?.idx === 3, JSON.stringify(rp))
const flags = (await stateOf(page)).cells.map(c => ['footprint', 'range', 'ha'].filter(k => c[k]).join() || '-')
ok('3.0', '画法：足迹 / 等幅 / 平均 / 回放', flags.slice(0, 3).join('|') === 'footprint|range|ha' && rp?.idx === 3, flags.join('|'))

const geo = i => page.evaluate(i => window.__q.geo(i), i)
const at = async (i, fx, fy) => { const g = await geo(i); return { x: g.left + g.PW * fx, y: g.top + g.py + g.ph * fy } }
const away = async () => { await page.mouse.move(3, 3); await sleep(80) }
const tap = async P => { await page.mouse.move(P.x, P.y, { steps: 3 }); await page.mouse.down(); await page.mouse.up(); await sleep(150) }
const drag = async (P, dx, dy) => { await page.mouse.move(P.x, P.y, { steps: 2 }); await sleep(60); await page.mouse.down(); await page.mouse.move(P.x + dx, P.y + dy, { steps: 10 }); await page.mouse.up(); await sleep(300) }
const stored = sym => page.evaluate(([k, s]) => (JSON.parse(localStorage.getItem(k)).drawings?.[s] || []).filter(d => d.type !== 'measure'), ['hkline-web-v1', sym])
const alertsOf = () => page.evaluate(() => (JSON.parse(localStorage.getItem('hkline-web-v1')).alerts || []).map(a => ({ id: a.id, kind: a.kind, symbol: a.symbol, status: a.status, drawingID: a.drawingID, lines: a.lines })))
/** 点一下这一格（变成当前格），落在价格轴旁边的空处 */
const activate = async i => { await page.keyboard.press('Escape'); const g = await geo(i); await page.mouse.click(g.left + g.PW * 0.97, g.top + g.py + g.ph * 0.08); await sleep(200); await page.keyboard.press('Escape'); await sleep(100) }
const geom = ds => JSON.stringify(ds.map(d => [d.id, d.type, d.pts.map(q => [q.t, +q.p.toPrecision(12)])]).sort())
async function pix(i, { hidden = false, fmin = 0.4 } = {}) {
  await away(); await page.evaluate(() => window.__q.frame())
  const s = await page.evaluate(i => window.__q.sample(i), i)
  if (!s) return { ok: false, info: '取样失败', vis: 0 }
  const vis = s.list.filter(x => x.vis), bad = []
  for (const x of vis) { if (hidden ? x.s.some(v => v >= 0.25) : x.s.some(v => v < fmin)) bad.push(`${x.type}:${x.s.join('/')}`) }
  return { ok: !bad.length && (hidden || vis.length >= 1), vis: vis.length, n: s.list.length, info: `看得见 ${vis.length}/${s.list.length}${bad.length ? '，不对 ' + bad.join(' ') : ''}` }
}

// ───────── 3.1 四种画法下各画趋势线 / 水平线 / 斐波那契，再拖改；水平线开画线提醒
const edits = []
for (let i = 0; i < 4; i++) {
  const sym = SYMS[i]
  await activate(i)
  await page.keyboard.press('Alt+KeyT'); await sleep(150)
  await tap(await at(i, 0.14, 0.62)); await tap(await at(i, 0.36, 0.34))
  await page.keyboard.press('Escape')
  await page.keyboard.press('Alt+KeyH'); await sleep(150)
  await tap(await at(i, 0.48, 0.9))
  await page.keyboard.press('Escape')
  await page.keyboard.press('Alt+KeyF'); await sleep(150)
  await tap(await at(i, 0.62, 0.72)); await tap(await at(i, 0.86, 0.3))
  await page.keyboard.press('Escape'); await away()
  const d0 = await stored(sym)
  const types = d0.map(d => d.type).sort().join(',')
  ok('3.1', `${MODE[i]}下画三条（趋势 / 水平 / 斐波那契）都存下`, types === 'fib,hline,trend', `${sym}：${types || '一条都没有'}`)
  const px0 = await pix(i)
  ok('3.1', `${MODE[i]}下三条线画在投影位置上（像素）`, px0.ok && px0.vis === 3, px0.info)

  // 拖改：趋势线拖第一个锚点、水平线整条往上拖、斐波那契整条平移
  const s = await page.evaluate(i => window.__q.sample(i), i)
  const tr = s.list.find(x => x.type === 'trend'), hl = s.list.find(x => x.type === 'hline'), fb = s.list.find(x => x.type === 'fib')
  const g = await geo(i), base = { x: g.left, y: g.top }
  const T0 = d0.find(d => d.type === 'trend'), H0 = d0.find(d => d.type === 'hline'), F0 = d0.find(d => d.type === 'fib')
  // 先点中再拖（选中后锚点才能拖）
  await tap({ x: base.x + tr.click.x, y: base.y + tr.click.y }); await drag({ x: base.x + tr.a.x, y: base.y + tr.a.y }, 30, 22)
  await page.keyboard.press('Escape')
  await tap({ x: base.x + hl.click.x, y: base.y + hl.click.y }); await drag({ x: base.x + hl.click.x, y: base.y + hl.click.y }, 0, -26)
  await page.keyboard.press('Escape')
  await tap({ x: base.x + fb.click.x, y: base.y + fb.click.y }); await drag({ x: base.x + fb.click.x, y: base.y + fb.click.y }, 24, -18)
  await page.keyboard.press('Escape'); await away()
  const d1 = await stored(sym)
  const T1 = d1.find(d => d.id === T0.id), H1 = d1.find(d => d.id === H0.id), F1 = d1.find(d => d.id === F0.id)
  const tOk = T1 && (T1.pts[0].t !== T0.pts[0].t || T1.pts[0].p !== T0.pts[0].p) && T1.pts[1].t === T0.pts[1].t && T1.pts[1].p === T0.pts[1].p
  const hOk = H1 && H1.pts[0].p > H0.pts[0].p
  const dp = F1 ? F1.pts.map((q, k) => q.p - F0.pts[k].p) : []
  const fOk = F1 && F1.pts.every((q, k) => q.t !== F0.pts[k].t) && Math.abs(dp[0] - dp[1]) <= Math.abs(dp[0]) * 1e-6 + 1e-9 && dp[0] > 0
  ok('3.1', `${MODE[i]}下拖改：趋势线只动拖的锚点、水平线整条上移、斐波那契整体平移`, tOk && hOk && fOk, `趋势 ${tOk ? '✓' : '✗'} 水平 ${hOk ? '✓' : '✗'} 斐波 ${fOk ? '✓' : '✗'}`)
  edits.push({ sym, T0, T1, H0, H1, F0, F1 })

  // 水平线开「画线提醒」（选中栏的铃铛）
  const s2 = await page.evaluate(i => window.__q.sample(i), i)
  const hl2 = s2.list.find(x => x.type === 'hline')
  await tap({ x: base.x + hl2.click.x, y: base.y + hl2.click.y })
  const bell = page.locator('.chart-cell').nth(i).locator('.draw-quick [data-q="alert"]')
  const hasBell = await bell.count()
  if (hasBell) await bell.first().click()
  await sleep(300); await page.keyboard.press('Escape'); await away()
  const al = (await alertsOf()).filter(a => a.kind === 'drawing' && a.symbol === sym)
  ok('3.1', `${MODE[i]}下水平线开了画线提醒`, al.length === 1 && al[0].status === 'active', `铃铛 ${hasBell ? '有' : '没有'}，提醒 ${al.length} 条`)
  const px1 = await pix(i)
  ok('3.1', `${MODE[i]}下拖改后像素跟到新位置`, px1.ok && px1.vis === 3, px1.info)
}
await shot(page, 's3-四种画法下画线')
DATA.edits = edits

const B = {}
for (const s of SYMS) B[s] = geom(await stored(s))
DATA.toasts = await page.evaluate(() => window.__q.toasts)
DATA.alerts0 = await alertsOf()
note('3.1', '画线过程中弹出的提示', JSON.stringify(DATA.toasts.map(x => x[1])))
note('3.1', '基准时还在的画线提醒', DATA.alerts0.map(a => a.symbol + ':' + a.status + '@' + a.lines?.[0]?.points?.[0]?.p).join(' '))
const A0 = JSON.stringify((await alertsOf()).sort((a, b) => a.id.localeCompare(b.id)))
note('3.1', '基准', `画线 ${SYMS.map(s => s.replace('USDT', '') + ':' + JSON.parse(B[s]).length).join(' ')}，提醒 ${JSON.parse(A0).length} 条`)

/** 一个场景下的不变量：存档里的画线逐字段不变、像素落在投影上、画线提醒原样 */
async function same(tag, { pixel = true, minVis = 1 } = {}) {
  const bad = [], px = []
  for (let i = 0; i < 4; i++) {
    const sym = SYMS[i]
    if (geom(await stored(sym)) !== B[sym]) bad.push(`${sym} 画线变了`)
    if (pixel) {
      const c = (await cellsOf(page)).findIndex(c => c.symbol === sym)
      if (c < 0) continue
      const p = await pix(c)
      px.push(`${sym.replace('USDT', '')} ${p.info}`)
      if (!p.ok || p.vis < minVis) bad.push(`${sym} 像素 ${p.info}`)
    }
  }
  const A1 = JSON.stringify((await alertsOf()).sort((a, b) => a.id.localeCompare(b.id)))
  ok(tag.split(' ')[0], `${tag.slice(tag.indexOf(' ') + 1)}：画线原位（存档逐字段 + 像素）`, !bad.length, bad.length ? bad.join('；') : px.join('；'))
  ok(tag.split(' ')[0], `${tag.slice(tag.indexOf(' ') + 1)}：画线提醒不受影响（条数、状态、价位）`, A1 === A0, A1 === A0 ? `${JSON.parse(A1).length} 条原样` : A1.slice(0, 300))
}
async function hideCheck(tag) {
  await page.keyboard.press('Escape'); await activate(0)
  await page.keyboard.press('Meta+Alt+KeyH'); await sleep(400)
  const st1 = await stateOf(page)
  const res = []
  for (let i = 0; i < (await cellsOf(page)).length; i++) res.push(await pix(i, { hidden: true }))
  const A1 = JSON.stringify((await alertsOf()).sort((a, b) => a.id.localeCompare(b.id)))
  await shot(page, `s3-隐藏画线-${tag}`)
  await page.keyboard.press('Meta+Alt+KeyH'); await sleep(400)
  const st2 = await stateOf(page)
  const back = []
  for (let i = 0; i < (await cellsOf(page)).length; i++) back.push(await pix(i))
  ok('3.4', `${tag}：⌘⌥H 隐藏画线（每格像素是底色）、再按一下回来；提醒不动`, st1.drawHidden === true && res.every(r => r.ok) && st2.drawHidden === false && back.every(r => r.ok) && A1 === A0,
    `藏：${st1.drawHidden} ${res.map(r => r.info).join(' / ')}；显：${st2.drawHidden} ${back.map(r => r.info).join(' / ')}；提醒${A1 === A0 ? '原样' : '变了'}`)
}

await same('3.2 四种画法下（拖改之后）')
await hideCheck('画法下')

// ───────── 3.3 切回普通 K 线：足迹 / 等幅 / 平均三格在周期「更多」里关掉，回放格退出
for (let i = 0; i < 3; i++) {
  await activate(i)
  await page.click('#tbMoreIv'); await sleep(300)
  const lab = ['足迹', '等幅 K 线', '平均 K 线'][i]
  await page.evaluate(l => { const b = [...document.querySelectorAll('.menu .mi')].find(x => x.textContent.replace(/\s+/g, ' ').includes(l)); b?.click() }, lab)
  await sleep(600); await page.keyboard.press('Escape')
}
await page.evaluate(() => document.querySelectorAll('.chart-cell')[3].querySelector('.rp-bar [data-rp="exit"]')?.click())
await waitCells(page, 4, 50, 30000); await sleep(1500)
const flags2 = (await stateOf(page)).cells.map(c => ['footprint', 'range', 'ha'].filter(k => c[k]).join() || '-')
ok('3.3', '切回普通 K 线（三格画法关掉、回放退出）', flags2.every(f => f === '-') && !(await page.evaluate(() => window.__replay?.())), flags2.join('|'))
await shot(page, 's3-切回普通K线')
await same('3.3 切回普通 K 线后', { minVis: 1 })

// ───────── 3.3 切周期：四格都切到 5 分钟，再切回原周期
for (let i = 0; i < 4; i++) { await activate(i); await page.click('#toolbar .intervals [data-iv="5m"]'); await sleep(300) }
await waitCells(page, 4, 50, 30000); await sleep(1200)
ok('3.3', '四格都切到 5 分钟', (await cellsOf(page)).every(c => c.iv === '5m'), (await cellsOf(page)).map(c => c.iv).join(' '))
await same('3.3 切到 5 分钟后')
for (let i = 0; i < 4; i++) { await activate(i); await page.click(`#toolbar .intervals [data-iv="${cells[i].iv}"]`); await sleep(300) }
await waitCells(page, 4, 50, 30000); await sleep(1200)
await same('3.3 切回原周期后')

// ───────── 3.3 切布局集（⌥2 一图 XRP，再 ⌥1 回来）
await page.keyboard.press('Alt+Digit2'); await waitCells(page, 1, 50, 30000); await sleep(800)
const one = await cellsOf(page)
await page.keyboard.press('Alt+Digit1'); await waitCells(page, 4, 50, 30000); await sleep(1500)
ok('3.3', '布局集 ⌥2 → ⌥1 来回', one.length === 1 && one[0].symbol === 'XRPUSDT' && (await cellsOf(page)).length === 4, `中间 ${one.map(c => c.symbol + '/' + c.iv).join()}`)
await same('3.3 切布局集回来后')

// ───────── 3.3 刷新
await page.reload({ waitUntil: 'domcontentloaded' })
await waitCells(page, 4, 50, 60000)
await page.waitForFunction(() => window.__q?.ch(3)?._panes, null, { timeout: 20000 }); await sleep(1500)
await shot(page, 's3-刷新后')
await same('3.3 刷新后')
await hideCheck('刷新后')

ok('3.5', '整段控制台无报错', !errs.length, errs.slice(0, 5).join(' | '))
flush()
await browserDown()
console.log('地址', URL_)
