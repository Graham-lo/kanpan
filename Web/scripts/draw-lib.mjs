// Hkline Web · 画线交叉验证共用件（被 scripts/draw-cross.mjs 引用，不单独跑）
//   · openCtx()：一个干净的浏览器上下文——WebSocket 换成不连的空壳（画线落点不受实时行情影响）、K 线 REST 合成、
//     币安全市场表三张整场只取一次（之后用缓存）、持仓量与 futures/data/* 给合成值；页里装 __dx 探针
//   · __dx（页内）：拿到活的格子与图表对象（不改 src：借 __cells() 里那次 cells.map 把数组本身捞出来），
//     按图表自己的几何把每条画线的 (t, p) 投到像素、给出「应该有线的颜色」的取样点；
//     取样时同一帧里先读真实画面、再关画线重画一遍作底，逐点比「这个像素有没有朝画线颜色偏过去」——
//     背后是 K 线、指标、云带、成交量分布都不影响判定
//   · assertDrawings(page, exp, opt)：每个场景都跑的一组不变量（条数、几何、像素、点中 / 点空、拖锚点 / 拖整条 / ⌘Z、
//     隐藏开关、切品种回来）
import { INSTR, mockKlines, sleep, measure, pct } from './f-lib.mjs'
import fs from 'node:fs'

export const KEY = 'hkline-web-v1'
export const SIZES_KEY = 'hkline-web-sizes-v1'
export const OUT = process.env.DRAW_OUT || '/tmp/kp-draw-cross'
fs.mkdirSync(OUT, { recursive: true })
/** 画线用的颜色：指标、K 线、皮肤里都没有的一种品红，像素判定不会和别的东西撞 */
export const COLOR = '#D500F9'

// ───────── 结果
export const R = { pass: 0, fail: 0, seg: '', bySeg: {}, fails: [] }
export function ok(name, pass, info = '') {
  const s = R.bySeg[R.seg] ||= { pass: 0, fail: 0 }
  if (pass) { R.pass++; s.pass++ } else { R.fail++; s.fail++; R.fails.push(`[${R.seg}] ${name}${info ? '  ' + info : ''}`) }
  console.log(`${pass ? '✓' : '✗'} ${name}${info ? '  ' + info : ''}`)
  return pass
}
export const log = (...a) => console.log('  ', ...a)

// ───────── 页内探针（addInitScript）
const PAGE = () => {
  const NS = (window.__dx = {})
  /** 活的格子数组（Cell[]）：__cells() 里第一次 .map 的 this 就是它 */
  NS.cells = () => {
    if (typeof window.__cells !== 'function') return null
    let got = null
    const orig = Array.prototype.map
    Array.prototype.map = function (...a) { if (!got && this.length && this[0] && this[0].chart && this[0].host) got = this; return orig.apply(this, a) }
    try { window.__cells() } catch { /* 还没起来 */ } finally { Array.prototype.map = orig }
    return got
  }
  NS.activeIdx = () => { const cs = NS.cells(); if (!cs) return -1; const k = cs.findIndex(c => c.el.classList.contains('active')); return k < 0 ? 0 : k }
  NS.ch = i => { const cs = NS.cells(); if (!cs) return null; return cs[i ?? NS.activeIdx()]?.chart ?? null }
  NS.store = () => { try { return JSON.parse(localStorage.getItem('hkline-web-v1') || '{}') } catch { return {} } }
  NS.stored = sym => (NS.store().drawings?.[sym] || []).filter(d => d && d.type !== 'measure') // 测量是临时的：读档时剔掉、云同步不认
  NS.storedRaw = sym => NS.store().drawings?.[sym] || []
  const cvs = document.createElement('canvas'); cvs.width = cvs.height = 1
  const cx = cvs.getContext('2d', { willReadFrequently: true })
  NS.rgb = css => { cx.clearRect(0, 0, 1, 1); cx.fillStyle = '#000'; cx.fillStyle = css; cx.fillRect(0, 0, 1, 1); const d = cx.getImageData(0, 0, 1, 1).data; return [d[0], d[1], d[2]] }
  NS.frame = () => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => r())))
  /** 格子的几何：画布在页面上的位置、主图窗格、绘图区宽 */
  NS.geo = i => {
    const ch = NS.ch(i); if (!ch || !ch._panes) return null
    const rc = ch.ctx.canvas.getBoundingClientRect(), p = ch._panes[0], r = ch._ranges.main
    return { left: rc.left, top: rc.top, w: rc.width, h: rc.height, pane: { y: p.y, h: p.h }, panes: ch._panes.map(q => [q.id, q.y, q.h]), plotW: ch.plotW(), spacing: ch.spacing, iv: ch.iv, dec: ch.meta?.dec ?? 2, min: r.min, max: r.max, bars: ch.bars.length, lastT: ch.bars[ch.bars.length - 1]?.t, from: ch.visible().from, to: ch.visible().to, hidden: ch.drawingsHidden, sel: ch.selected?.id ?? null, n: ch.drawings.length, symbol: ch.symbol ?? null }
  }
  /** 图上一点（格内坐标）的时间与价格（不吸附；与图表落点同一取整：下标四舍五入到整根） */
  NS.tpAt = (i, x, y) => { const ch = NS.ch(i), p = ch._panes[0], r = ch._ranges.main; return { t: ch.timeAt(Math.round(ch.xToIndex(x))), p: ch.yToPrice(y, p, r) } }
  NS.xyOf = (i, t, v) => { const ch = NS.ch(i), p = ch._panes[0], r = ch._ranges.main; return { x: ch.indexToX(ch.indexAt(t)), y: ch.priceToY(v, p, r) } }
  /** 一条画线的取样点（格内坐标）、点中它的位置、第一个锚点 */
  NS.probesOf = (ch, d) => {
    const p = ch._panes?.[0], r = ch._ranges?.main; if (!p || !r || !d.pts?.length) return null
    const PW = ch.plotW(), X = t => ch.indexToX(ch.indexAt(t)), Y = v => ch.priceToY(v, p, r)
    const inside = (x, y) => x >= 4 && x <= PW - 4 && y >= p.y + 4 && y <= p.y + p.h - 4
    const rc = ch.ctx.canvas.getBoundingClientRect(), cell = ch.ctx.canvas.closest('.chart-cell')
    /** 这一点上面没有 DOM 盖着（图例、格子标题、按钮），点下去落在画布上 */
    const free = (x, y) => { const el = document.elementFromPoint(rc.left + x, rc.top + y); return el?.tagName === 'CANVAS' && el.closest('.chart-cell') === cell }
    const col = typeof d.color === 'string' && d.color ? d.color : '#2962FF'
    const P = []
    let click = null
    const pt = (x, y, color = col, rr = 2) => { if (inside(x, y)) P.push({ k: 'pt', x, y, r: rr, color }) }
    const A = d.pts[0], B = d.pts[1] || d.pts[0]
    const a = { x: X(A.t), y: Y(A.p) }, b = { x: X(B.t), y: Y(B.p) }
    const lerp = k => ({ x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k })
    const setClick = q => { if (q && inside(q.x, q.y)) click = { x: q.x, y: q.y } }
    switch (d.type) {
      case 'trend': { const m = lerp(0.5), q = lerp(0.3); pt(m.x, m.y); pt(q.x, q.y); setClick(m); break }
      case 'ray': { const m = lerp(0.5), q = lerp(1.6); pt(m.x, m.y); pt(q.x, q.y); setClick(m); break }
      case 'hline': { let x = a.x; if (!(x >= 30 && x <= PW - 30)) x = PW * 0.5; pt(x, a.y); setClick({ x: [0.62, 0.5, 0.75, 0.4, 0.85, 0.3].map(f => PW * f).find(x => free(x, a.y)) ?? PW * 0.62, y: a.y }); break } // 水平线哪儿都能点：挑一处没被图例、格子标题盖住的
      case 'vline': { let y = a.y; if (!(y > p.y + 30 && y < p.y + p.h - 30)) y = p.y + p.h * 0.5; pt(a.x, y); setClick({ x: a.x, y }); break }
      case 'rect': {
        const x0 = Math.min(a.x, b.x), x1 = Math.max(a.x, b.x), y0 = Math.min(a.y, b.y), y1 = Math.max(a.y, b.y)
        if (x1 - x0 >= 6 && y1 - y0 >= 6) { pt(x0, (y0 + y1) / 2); pt((x0 + x1) / 2, y0) }
        setClick({ x: (x0 + x1) / 2, y: (y0 + y1) / 2 }); break
      }
      case 'fib': {
        const x0 = Math.min(a.x, b.x), x1 = Math.max(a.x, b.x)
        if (x1 - x0 >= 6) pt((x0 + x1) / 2, Math.round(Y(B.p + (A.p - B.p) * 0.5)) + 0.5, '#4CAF50')
        setClick({ x: (x0 + x1) / 2, y: (a.y + b.y) / 2 }); break
      }
      case 'position': {
        if (d.pts.length < 3) break
        const x0 = Math.min(a.x, b.x), x1 = Math.max(a.x, b.x), W = x1 - x0
        if (W >= 8) pt(x0 + 0.2 * W, Math.round(a.y) + 0.5)
        setClick({ x: x0 + 0.3 * W, y: (a.y + b.y) / 2 }); break
      }
      case 'avwap': {
        const i0 = Math.floor(ch.indexAt(A.t) + 1e-9); if (i0 < 0 || i0 > ch.lastIndex()) break
        const ax = ch.indexToX(i0)
        pt(ax, p.y + p.h - 7, col, 1) // 图底锚点小三角
        const k1 = Math.min(ch.lastIndex(), i0 + 3)
        let sw = 0, swp = 0
        for (let i = i0; i <= k1; i++) { const q = ch.bars[i]; const w = q.v || 1; sw += w; swp += w * (q.h + q.l + q.c) / 3 }
        const x = ch.indexToX(k1), yv = Y(swp / sw)
        if (inside(x, yv)) P.push({ k: 'col', xs: [x - 1, x, x + 1], y0: yv - 16, y1: yv + 16, color: col })
        const b0 = ch.bars[i0]; setClick({ x: ax, y: Y((b0.h + b0.l + b0.c) / 3) }); break
      }
      case 'fvp': {
        if (d.pts.length < 2) break
        const ia = Math.round(ch.indexAt(A.t)), ib = Math.round(ch.indexAt(B.t))
        const i0 = Math.max(0, Math.min(ia, ib)), i1 = Math.min(ch.lastIndex(), Math.max(ia, ib)); if (i1 < i0) break
        let lo = Infinity, hi = -Infinity
        for (let i = i0; i <= i1; i++) { const q = ch.bars[i]; if (q) { lo = Math.min(lo, q.l); hi = Math.max(hi, q.h) } }
        const x0 = ch.indexToX(i0) - ch.spacing / 2, x1 = ch.indexToX(i1) + ch.spacing / 2, W = x1 - x0
        const xm = x0 + 0.65 * W, yh = Y(hi), yl = Y(lo)
        if (W >= 12 && inside(xm, (yh + yl) / 2)) P.push({ k: 'col', xs: [xm, xm + 2, xm + 4], y0: Math.max(p.y + 2, yh - 2), y1: Math.min(p.y + p.h - 2, yl + 2), color: col, fmin: 0.4 })
        setClick({ x: xm, y: (yh + yl) / 2 }); break
      }
      case 'measure': {
        const up = B.p >= A.p, m = lerp(0.5)
        pt(Math.round((a.x + b.x) / 2) + 0.5, Math.round(m.y) + 0.5 - 6, up ? '#2962FF' : '#F23645', 1); break
      }
    }
    return { probes: P, click, covered: !!click && !free(click.x, click.y), a: inside(a.x, a.y) ? a : null, b: d.pts[1] && inside(b.x, b.y) ? b : null }
  }
  const score = (img, ref, W, H, sc, pr) => {
    const tg = NS.rgb(pr.color)
    let best = 0
    const one = (x, y) => {
      const X = Math.round(x * sc), Y_ = Math.round(y * sc)
      if (X < 0 || Y_ < 0 || X >= W || Y_ >= H) return
      const o = (Y_ * W + X) * 4
      const bg = [ref[o], ref[o + 1], ref[o + 2]], px = [img[o], img[o + 1], img[o + 2]]
      const d = [tg[0] - bg[0], tg[1] - bg[1], tg[2] - bg[2]], L = d[0] * d[0] + d[1] * d[1] + d[2] * d[2]
      if (L < 900) return // 底色本来就是这个颜色：判不了
      const v = [px[0] - bg[0], px[1] - bg[1], px[2] - bg[2]]
      const f = (v[0] * d[0] + v[1] * d[1] + v[2] * d[2]) / L
      const res = Math.hypot(v[0] - f * d[0], v[1] - f * d[1], v[2] - f * d[2])
      if (res <= 60 && f > best) best = Math.min(1.2, f)
    }
    if (pr.k === 'pt') { for (let dy = -pr.r; dy <= pr.r; dy++) for (let dx = -pr.r; dx <= pr.r; dx++) one(pr.x + dx, pr.y + dy) }
    else for (const x of pr.xs) for (let y = Math.floor(pr.y0); y <= Math.ceil(pr.y1); y++) one(x, y)
    return best
  }
  /** 取样：每条画线每个取样点的「朝画线颜色偏了多少」（0 = 没有，1 = 正好是那个颜色）；
   *  底图 = 同一帧里把画线关掉重画（不动存档、不出帧），画完照原样再画回来 */
  NS.sample = (i, ids) => {
    const ch = NS.ch(i); if (!ch || !ch._panes) return null
    const cv = ch.ctx.canvas, W = cv.width, H = cv.height, sc = W / cv.getBoundingClientRect().width
    // 先读一个像素：Chrome 会因为回读把画布在 GPU / CPU 光栅之间换（十字线轻量帧往主画布上贴底图之后尤其如此），
    // 换的那一下前后两次重画的抗锯齿差几个色阶；先读一下让下面三次重画落在同一种光栅上，才可比
    ch.ctx.getImageData(0, 0, 1, 1)
    ch.render()
    const img = ch.ctx.getImageData(0, 0, W, H).data
    const was = ch.drawingsHidden
    ch.drawingsHidden = true; ch.render()
    const ref = ch.ctx.getImageData(0, 0, W, H).data
    ch.drawingsHidden = was; ch.render()
    const want = ids ? new Set(ids) : null
    const out = []
    // 投影按存档里的那份算（不是图表内存里的）：存档 ↔ 像素直接对上；两边条目对不上也报出来
    const sym = window.__cells?.()[i]?.symbol
    const live = ch.drawings.filter(d => d.type !== 'measure')
    const disk = sym ? NS.stored(sym) : live
    const liveIds = new Set(live.map(d => d.id)), diskIds = new Set(disk.map(d => d.id))
    const mismatch = [...live.filter(d => !diskIds.has(d.id)).map(d => '图上多 ' + d.type), ...disk.filter(d => !liveIds.has(d.id)).map(d => '存档多 ' + d.type)]
    for (const d of disk) {
      if (want && !want.has(d.id)) continue
      const q = NS.probesOf(ch, d); if (!q) { out.push({ id: d.id, type: d.type, vis: false, s: [] }); continue }
      out.push({ id: d.id, type: d.type, vis: q.probes.length > 0, s: q.probes.map(pr => +score(img, ref, W, H, sc, pr).toFixed(2)), click: q.click, covered: q.covered, a: q.a, b: q.b })
    }
    return { hidden: was, list: out, mismatch }
  }
  /** 画布上一处没有画线的空地（用图表自己的命中判定挑） */
  NS.emptySpot = i => {
    const ch = NS.ch(i), p = ch._panes[0], PW = ch.plotW(), rc = ch.ctx.canvas.getBoundingClientRect()
    const prev = ch.drawingsHidden; ch.drawingsHidden = false
    try {
      for (let gy = 0.2; gy <= 0.8; gy += 0.1) for (let gx = 0.1; gx <= 0.9; gx += 0.04) {
        const x = PW * gx, y = p.y + p.h * gy
        const el = document.elementFromPoint(rc.left + x, rc.top + y)
        if (el?.tagName !== 'CANVAS' || el.closest('.chart-cell') !== ch.ctx.canvas.closest('.chart-cell')) continue // 图例、按钮这些 DOM 盖在上面的地方不算空地
        let clear = true
        for (let dx = -14; dx <= 14 && clear; dx += 7) for (let dy = -14; dy <= 14 && clear; dy += 7) if (ch.hitDrawing(x + dx, y + dy)) clear = false
        if (clear) return { x, y }
      }
    } finally { ch.drawingsHidden = prev }
    return null
  }
  /** 每次图表重画花多少毫秒（给每格的 render 套一层计时；只计时不改行为） */
  NS.rtOn = () => {
    NS.rt = []
    for (const c of NS.cells() || []) {
      const ch = c.chart; if (ch.__rtWrapped) continue
      const orig = ch.render
      ch.render = function (...a) { const t = performance.now(); try { return orig.apply(this, a) } finally { NS.rt?.push(performance.now() - t) } }
      ch.__rtWrapped = true
    }
  }
  NS.rtOff = () => { const r = NS.rt || []; NS.rt = null; return r }
  NS.drawTools = () => [...document.querySelectorAll('#drawbar [data-tools]')].flatMap(b => b.dataset.tools.split(' ')).filter((v, k, a) => a.indexOf(v) === k)
  NS.toasts = () => [...document.querySelectorAll('#toasts .toast')].map(e => e.textContent).join(' | ')
}

const WS_STUB = () => {
  window.WebSocket = class { constructor() { this.readyState = 0 } send() {} close() {} addEventListener() {} removeEventListener() {} }
}

// ───────── 网络：K 线合成；全市场表三张整场取一次；慢数合成；其余一律合成空答复（不往线上打）
const restCache = new Map()
const SYNTH = u => {
  if (/\/openInterest\?/.test(u)) return { symbol: new URL(u).searchParams.get('symbol'), openInterest: '12345.6', time: Date.now() }
  if (/\/futures\/data\//.test(u)) { const now = Date.now(); return Array.from({ length: 30 }, (_, i) => ({ symbol: new URL(u).searchParams.get('symbol'), timestamp: now - (30 - i) * 3e5, sumOpenInterest: '1000', sumOpenInterestValue: '1000000', longShortRatio: '1.1', longAccount: '0.52', shortAccount: '0.48', buySellRatio: '1.0', buyVol: '10', sellVol: '10' })) }
  return null
}
async function netShim(ctx) {
  await ctx.route(/^https:\/\/(fapi|api|www)\.binance\.com\//, async route => {
    const q = route.request(), u = q.url()
    const cors = { 'access-control-allow-origin': q.headers().origin || '*', 'access-control-allow-headers': '*' }
    if (q.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors }).catch(() => {})
    const syn = SYNTH(u)
    if (syn) return route.fulfill({ status: 200, contentType: 'application/json', headers: cors, body: JSON.stringify(syn) }).catch(() => {})
    const key = /exchangeInfo|ticker\/24hr|premiumIndex|ticker\/price|fundingInfo/.test(u) && !/symbol=/.test(u) ? u.replace(/\?.*/, '') : u
    if (!restCache.has(key)) {
      try { const r = await route.fetch({ timeout: 20000 }); if (!r.ok()) return route.fulfill({ response: r, headers: { ...r.headers(), ...cors } }).catch(() => {}); restCache.set(key, { body: await r.body(), ct: r.headers()['content-type'] || 'application/json' }) } catch { return route.abort().catch(() => {}) }
    }
    const c = restCache.get(key)
    return route.fulfill({ status: 200, contentType: c.ct, headers: cors, body: c.body }).catch(() => {})
  })
}

/** 一个干净的上下文 + 页面；errors 收集未捕获异常与控制台报错 */
export async function openCtx(browser, url, { viewport = { width: 1600, height: 1000 }, depth = 20000, delay = 20, dpr = 1 } = {}) {
  const ctx = await browser.newContext({ viewport, deviceScaleFactor: dpr, locale: 'zh-CN', timezoneId: 'Asia/Shanghai' })
  await ctx.addInitScript(INSTR)
  await ctx.addInitScript(WS_STUB)
  await ctx.addInitScript(PAGE)
  await netShim(ctx)
  await mockKlines(ctx, { depth, delay }) // 后注册的路由先匹配：K 线走合成
  const blank = new URL('__draw_blank', url).href
  await ctx.route(blank, r => r.fulfill({ status: 200, contentType: 'text/html', body: '<!doctype html><title>blank</title>' }))
  const page = await ctx.newPage()
  const errors = []
  page.on('pageerror', e => errors.push('pageerror: ' + String(e.stack || e).split('\n').slice(0, 3).join(' ⟵ ')))
  page.on('console', m => { if (m.type() === 'error') errors.push('console: ' + m.text().slice(0, 300)) })
  return { ctx, page, errors, url, blank }
}
/** 控制台报错里与本套件无关的网络噪声（被拦的请求、空壳 WebSocket） */
export const realErrors = errs => errs.filter(x => !/Failed to load resource|net::ERR|ERR_FAILED|WebSocket|status of 4\d\d|status of 5\d\d|blocked by CORS policy/.test(x))

/** 写一份存档（在同源空白页上写，app 启动那次 save 不会把它盖掉），再打开图表 */
export async function seedAndOpen(env, state, { sizes = null, hash = 'chart', qs = '' } = {}) {
  const { page, blank, url } = env
  await page.goto(blank, { waitUntil: 'domcontentloaded' })
  await page.evaluate(([k, s, sk, z]) => {
    localStorage.clear()
    if (s != null) localStorage.setItem(k, typeof s === 'string' ? s : JSON.stringify(s))
    if (z != null) localStorage.setItem(sk, JSON.stringify(z))
  }, [KEY, state, SIZES_KEY, sizes])
  await page.goto(`${url}${qs ? '?' + qs : ''}#${hash}`, { waitUntil: 'domcontentloaded' })
  await ready(page)
}
export async function ready(page, n = 1) {
  await page.waitForFunction(n => { const c = window.__cells?.(); return c && c.length >= n && c.slice(0, n).every(x => x.bars > 0) && window.__dx?.ch(0)?._panes }, n, { timeout: 45000, polling: 200 })
  await page.evaluate(() => window.__dx.frame())
  await sleep(300)
}
/** 一份最小存档（其余项走默认） */
export function baseState(over = {}) {
  return {
    theme: 'light', skin: 'sage', updown: 'green-up', greenUpMigrated: true, route: 'direct', routePicked: true,
    layout: '1', cells: [{ symbol: 'BTCUSDT', iv: '1m' }], active: 0, panel: null,
    pinned: ['1m', '5m', '15m', '1h', '4h', '1d', '1w'],
    ind: { ma: false, ema: false, boll: false, vol: false, subs: [] },
    drawings: {}, alerts: [], drawColor: COLOR, magnet: false, drawHidden: false, drawLocked: false, linkCross: true,
    ...over,
  }
}

// ───────── 页面小工具
export const frame = page => page.evaluate(() => window.__dx.frame())
export const geo = (page, i) => page.evaluate(i => window.__dx.geo(i), i)
export const stored = (page, sym) => page.evaluate(s => window.__dx.stored(s), sym)
export const storeOf = page => page.evaluate(() => window.__dx.store())
export const dbg = page => page.evaluate(() => window.__draw())
/** 把鼠标挪出画布（十字线不挡取样） */
export async function away(page) { await page.mouse.move(2, 2); await sleep(60) }
/** 格内坐标 → 页面坐标 */
export async function abs(page, i, q) { const g = await geo(page, i); return { x: g.left + q.x, y: g.top + q.y } }

export async function pickTool(page, t) {
  const b = page.locator(`#drawbar [data-tool="${t}"]`)
  if (await b.count()) { if ((await b.getAttribute('aria-pressed')) !== 'true') await b.click(); await sleep(150); return }
  const [gid, k] = await page.evaluate(t => {
    const b = [...document.querySelectorAll('#drawbar [data-tools]')].find(x => x.dataset.tools.split(' ').includes(t))
    return [b?.closest('.tool-grp')?.dataset.grp, b ? b.dataset.tools.split(' ').indexOf(t) : -1]
  }, t)
  await page.click(`#drawbar [data-fly="${gid}"]`); await sleep(250)
  await page.locator('.menu .mi').nth(k).click(); await sleep(150)
}
/** 用工具栏画一条：pts 是格内像素点（1 个或 2 个），点下去；返回新存下的那条（measure 不存，返回 null） */
export async function drawVia(page, ci, tool, pts, sym) {
  const before = (await stored(page, sym)).map(d => d.id)
  await pickTool(page, tool)
  for (const q of pts) { const P = await abs(page, ci, q); await page.mouse.move(P.x, P.y, { steps: 3 }); await page.mouse.down(); await page.mouse.up(); await sleep(120) }
  await sleep(250)
  const after = await stored(page, sym)
  return after.find(d => !before.includes(d.id)) || null
}

/** 九把（或 TOOL_GROUPS 里现有的全部）持久画线工具在一格里错开摆好：每把占自己的一列时间、自己的一段价位，
 *  像素判定互不干扰。返回 { tool: [格内点…] } */
export async function toolSlots(page, ci, tools) {
  const g = await geo(page, ci)
  const order = ['hline', 'vline', 'trend', 'rect', 'fib', 'position', 'fvp', 'ray', 'avwap']
  const list = [...order.filter(t => tools.includes(t)), ...tools.filter(t => !order.includes(t) && t !== 'measure')]
  const n = list.length, PW = g.plotW, p = g.pane
  const xL = PW * 0.05, xR = PW * 0.93, w = (xR - xL) / n
  const yT = p.y + p.h * 0.2, yB = p.y + p.h * 0.85, bh = (yB - yT) / n
  const snapX = x => { const i = Math.round((x - PW) / g.spacing); return PW + i * g.spacing } // 吸到整根（落点本来就按整根取）
  const out = {}
  list.forEach((t, k) => {
    const x0 = snapX(xL + k * w + w * 0.15), x1 = snapX(xL + k * w + w * 0.85)
    const y0 = yT + k * bh + bh * 0.2, y1 = yT + k * bh + bh * 0.8
    if (t === 'hline') out[t] = [{ x: x0 + (x1 - x0) / 2, y: p.y + 8 + (p.h - 16) * 0.975 }] // 价位在所有 K 线之下（下沿留白里；上沿留白被格子的开高低收图例盖着）
    else if (t === 'vline' || t === 'avwap') out[t] = [{ x: snapX(xL + k * w + w * 0.4), y: (y0 + y1) / 2 }]
    else if (t === 'ray') out[t] = [{ x: x0, y: y1 }, { x: x0 + 2 * g.spacing, y: y1 - 70 }]
    else if (t === 'position') out[t] = [{ x: x0, y: (y0 + y1) / 2 }, { x: x1, y: y0 }]
    else out[t] = [{ x: x0, y: y1 }, { x: x1, y: y0 }]
  })
  return { slots: out, order: list }
}

/** 把一组画线按格内点画上去；返回按存档读回的列表 */
export async function drawAllTools(page, ci, sym) {
  const tools = await page.evaluate(() => window.__dx.drawTools())
  const { slots, order } = await toolSlots(page, ci, tools)
  const res = []
  for (const t of order) {
    const d = await drawVia(page, ci, t, slots[t], sym)
    res.push({ tool: t, d })
    await page.keyboard.press('Escape'); await sleep(80)
  }
  await page.keyboard.press('Escape')
  return { tools, order, res, list: await stored(page, sym) }
}

// ───────── 不变量
const near = (a, b, tol) => Math.abs(a - b) <= tol
/** 画线几何与基准是否一致（时间差不过一根、价差不过一个最小价位） */
export function sameGeom(base, now, { tolT = 60e3, tolP = null } = {}) {
  const bad = []
  for (const b of base) {
    const n = now.find(x => x.id === b.id)
    if (!n) { bad.push(`${b.type}:${b.id} 不见了`); continue }
    if (n.pts.length !== b.pts.length) { bad.push(`${b.type} 锚点 ${b.pts.length}→${n.pts.length}`); continue }
    b.pts.forEach((q, k) => {
      const tp = tolP ?? Math.max(Math.abs(q.p) * 2e-6, 1e-9)
      if (!near(q.t, n.pts[k].t, tolT) || !near(q.p, n.pts[k].p, tp)) bad.push(`${b.type}#${k} (${q.t},${q.p})→(${n.pts[k].t},${n.pts[k].p})`)
    })
  }
  return bad
}
export const exactSame = (a, b) => JSON.stringify(a.map(d => [d.id, d.type, d.pts, d.locked ?? false]).sort()) === JSON.stringify(b.map(d => [d.id, d.type, d.pts, d.locked ?? false]).sort())

/** 像素：每条看得见的画线，取样点都朝它的颜色偏 ≥ fmin；隐藏时都 < 0.25 */
export async function pixelCheck(page, ci, { ids = null, expectHidden = false, fmin = 0.5 } = {}) {
  await away(page); await frame(page)
  const s = await page.evaluate(([i, ids]) => window.__dx.sample(i, ids), [ci, ids])
  if (!s) return { ok: false, info: '取样失败（图表没起来）', vis: 0 }
  const vis = s.list.filter(x => x.vis)
  const bad = (s.mismatch || []).slice(0, 4)
  for (const x of vis) {
    if (expectHidden) { if (x.s.some(v => v >= 0.25)) bad.push(`${x.type}:${x.s.join('/')}`) }
    else if (x.s.some(v => v < fmin)) bad.push(`${x.type}:${x.s.join('/')}`)
  }
  return { ok: !bad.length, vis: vis.length, total: s.list.length, bad, list: s.list, info: `看得见 ${vis.length}/${s.list.length} 条${bad.length ? '；不对的 ' + bad.slice(0, 6).join('，') : ''}` }
}

/** 点中 / 点空：逐条点它的取样位置看选中的是不是它；最后点空地看选中清空 */
export async function selectCheck(page, ci, { ids = null, max = 12 } = {}) {
  const s = await page.evaluate(([i, ids]) => window.__dx.sample(i, ids), [ci, ids])
  const cand = s.list.filter(x => x.click && !x.covered).slice(0, max)
  const covered = s.list.filter(x => x.click && x.covered).map(x => x.type)
  const bad = []
  for (const x of cand) {
    const P = await abs(page, ci, x.click)
    await page.mouse.move(P.x, P.y, { steps: 2 }); await page.mouse.down(); await page.mouse.up(); await sleep(120)
    const g = await geo(page, ci)
    const quick = await page.locator('.chart-cell .draw-quick').count()
    if (g.sel !== x.id) bad.push(`${x.type} 点中的是 ${g.sel ?? '无'}`)
    else if (x.type !== 'measure' && !quick) bad.push(`${x.type} 选中了但没有快捷条`)
  }
  const e = await page.evaluate(i => window.__dx.emptySpot(i), ci)
  let cleared = null
  if (e) {
    const P = await abs(page, ci, e)
    await page.mouse.move(P.x, P.y, { steps: 2 }); await page.mouse.down(); await page.mouse.up(); await sleep(150)
    cleared = (await geo(page, ci)).sel == null
    if (!cleared) bad.push('点空地没取消选中')
  }
  await away(page)
  return { ok: !bad.length && cand.length > 0, n: cand.length, bad, info: `点了 ${cand.length} 条${covered.length ? `（${covered.join(',')} 的点中位置被 DOM 盖着，跳过）` : ''}${e ? '' : '（没找到空地）'}${bad.length ? '；' + bad.slice(0, 5).join('，') : ''}` }
}

async function dragPx(page, ci, from, dx, dy) {
  const P = await abs(page, ci, from)
  await page.mouse.move(P.x, P.y, { steps: 2 }); await sleep(40)
  await page.mouse.down(); await page.mouse.move(P.x + dx, P.y + dy, { steps: 8 }); await page.mouse.up(); await sleep(200)
}
/** 拖：拖第一个锚点 → 只有它动；拖线身 → 每个锚点同样平移；⌘Z 两下 → 回到拖之前（逐字段相等） */
export async function dragCheck(page, ci, sym, { prefer = ['trend', 'rect', 'fib', 'ray'] } = {}) {
  const base = await stored(page, sym)
  const s = await page.evaluate(i => window.__dx.sample(i), ci)
  const pick = prefer.map(t => s.list.find(x => x.type === t && x.vis && x.a && x.click && !base.find(b => b.id === x.id)?.locked)).find(Boolean)
  if (!pick) return { ok: false, info: '没有能拖的画线（都不在视野里）' }
  const b0 = base.find(d => d.id === pick.id)
  const u0 = (await dbg(page)).undo
  // 1) 锚点
  await dragPx(page, ci, pick.a, 24, 18)
  const s1 = (await stored(page, sym)).find(d => d.id === pick.id)
  const anchorOk = !!s1 && (s1.pts[0].t !== b0.pts[0].t || s1.pts[0].p !== b0.pts[0].p) && s1.pts.slice(1).every((q, k) => q.t === b0.pts[k + 1].t && q.p === b0.pts[k + 1].p)
  // 2) 线身（重新算一次点中位置：锚点刚动过）
  const s2pre = await page.evaluate(([i, id]) => window.__dx.sample(i, [id]), [ci, pick.id])
  const c2 = s2pre.list[0]?.click
  let bodyOk = false, s2 = null
  if (c2) {
    await dragPx(page, ci, c2, 20, -16)
    s2 = (await stored(page, sym)).find(d => d.id === pick.id)
    if (s2 && s1) {
      const dt = s2.pts.map((q, k) => q.t - s1.pts[k].t), dp = s2.pts.map((q, k) => q.p - s1.pts[k].p)
      bodyOk = dt.every(v => v === dt[0]) && dp.every(v => Math.abs(v - dp[0]) <= Math.abs(dp[0]) * 1e-6 + 1e-9) && (dt[0] !== 0 || dp[0] !== 0)
    }
  }
  const u1 = (await dbg(page)).undo
  await page.keyboard.press('Meta+z'); await sleep(250)
  await page.keyboard.press('Meta+z'); await sleep(350)
  const after = await stored(page, sym)
  const back = exactSame(base, after)
  await page.keyboard.press('Escape'); await away(page)
  const info = `${pick.type}：锚点${anchorOk ? '只动了它' : '不对'}、线身${bodyOk ? '整体平移' : '不对'}、撤销栈 ${u0}→${u1}、⌘Z×2 ${back ? '回到原样' : '没回到原样'}`
  return { ok: anchorOk && bodyOk && back, info, type: pick.type }
}

/** 隐藏开关（⌘⌥H）：开着时像素是底色、点不中、存档 drawHidden=true、条数不变；关掉后线回来 */
export async function hideCheck(page, ci, sym, n, { ids = null } = {}) {
  await page.keyboard.press('Escape')
  await page.keyboard.press('Meta+Alt+h'); await sleep(300)
  const st1 = await storeOf(page)
  const px1 = await pixelCheck(page, ci, { expectHidden: true })
  const sel = await page.evaluate(([i, ids]) => window.__dx.sample(i, ids), [ci, ids])
  const c = sel.list.find(x => x.click)
  let noHit = true
  if (c) { const P = await abs(page, ci, c.click); await page.mouse.click(P.x, P.y); await sleep(150); noHit = (await geo(page, ci)).sel == null }
  await page.keyboard.press('Escape')
  await page.keyboard.press('Meta+Alt+h'); await sleep(300)
  const st2 = await storeOf(page)
  const px2 = await pixelCheck(page, ci, { ids })
  const n1 = st1.drawings?.[sym]?.length ?? 0, n2 = st2.drawings?.[sym]?.length ?? 0
  const pass = st1.drawHidden === true && px1.ok && noHit && st2.drawHidden === false && px2.ok && n1 === n && n2 === n
  return { ok: pass, info: `藏：存档 ${st1.drawHidden}、像素${px1.ok ? '全是底色' : '还有线 ' + px1.bad.slice(0, 3).join(',')}、点${noHit ? '不中' : '中了'}；显：存档 ${st2.drawHidden}、${px2.info}；条数 ${n1}/${n2}（应 ${n}）` }
}

/** 切品种（⌘K 搜）并等这一格换好 */
export async function switchSymbol(page, ci, to) {
  await away(page)
  await page.keyboard.press('Escape')
  await page.keyboard.press('Meta+k'); await sleep(300)
  await page.keyboard.type(to.replace(/USDT$/, '')); await sleep(500)
  await page.keyboard.press('Enter')
  await page.waitForFunction(([i, s]) => { const c = window.__cells?.()[i]; return c && c.symbol === s && c.bars > 0 && c.metaSym === s }, [ci, to], { timeout: 30000, polling: 200 }).catch(() => {})
  await frame(page); await sleep(400)
  return (await page.evaluate(i => window.__cells()[i].symbol, ci)) === to
}

/** 每个场景共用的一组不变量。exp = { sym, base: 基准画线（存档里的样子）, ci } */
export async function assertDrawings(page, tag, exp, opt = {}) {
  const { sym, base, ci = await page.evaluate(() => window.__dx.activeIdx()) } = exp
  const o = { pixels: true, select: true, drag: false, hide: false, swap: null, minVisible: 1, ...opt }
  const now = await stored(page, sym)
  ok(`${tag}：条数不变（${base.length}）`, now.length === base.length, `存档 ${now.length}`)
  const bad = sameGeom(base, now)
  ok(`${tag}：几何不变（时间差 ≤ 1 根、价差 ≤ 1 跳）`, !bad.length, bad.slice(0, 4).join('；'))
  if (o.pixels) {
    const px = await pixelCheck(page, ci)
    ok(`${tag}：像素落在投影位置上（取样点是画线颜色）`, px.ok && px.vis >= o.minVisible, px.info)
  }
  if (o.select) {
    const sc = await selectCheck(page, ci, { max: o.selectMax ?? 12 })
    ok(`${tag}：点线选中、点空地取消`, sc.ok, sc.info)
  }
  if (o.drag) {
    const dc = await dragCheck(page, ci, sym)
    ok(`${tag}：拖锚点 / 拖整条 / ⌘Z 复原`, dc.ok, dc.info)
  }
  if (o.hide) {
    const hc = await hideCheck(page, ci, sym, base.length)
    ok(`${tag}：隐藏开关（藏了是底色、显了回来）`, hc.ok, hc.info)
  }
  if (o.swap) {
    const a = await switchSymbol(page, ci, o.swap), b = await switchSymbol(page, ci, sym)
    const back = await stored(page, sym)
    const bad2 = sameGeom(base, back)
    const px = o.pixels ? await pixelCheck(page, ci) : { ok: true, info: '' }
    ok(`${tag}：切到 ${o.swap} 再切回来，画线都在原处`, a && b && back.length === base.length && !bad2.length && px.ok, `切过去 ${a} 切回 ${b}；${back.length} 条；${bad2.slice(0, 3).join('；')} ${px.info}`)
  }
}

export async function shot(page, name) {
  const f = `${OUT}/${name}.png`
  await page.screenshot({ path: f }).catch(() => {})
  return f
}

/** 量一段操作：帧间隔（页内 rAF）、长任务、CPU（f-lib measure），外加每次图表重画的耗时（render 本身，和无头浏览器的帧节拍无关） */
export async function measureR(page, cdp, fn) {
  await page.evaluate(() => window.__dx.rtOn())
  const m = await measure(page, cdp, fn)
  const rt = await page.evaluate(() => window.__dx.rtOff())
  const r1 = x => +x.toFixed(2)
  return { ...m, rN: rt.length, r50: r1(pct(rt, 0.5) || 0), r95: r1(pct(rt, 0.95) || 0), rMax: r1(Math.max(0, ...rt)), rSum: Math.round(rt.reduce((a, b) => a + b, 0)) }
}
