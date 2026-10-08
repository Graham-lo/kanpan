// Hkline Web · 图例悬停探针（2026-10-07 用户报：行情页左上角指标悬停时一直跳、点不到「隐藏」按钮）
//
// 用法：node scripts/legend-hover-probe.mjs [目标…]
//   目标：online（线上 https://kanpan.43-160-232-253.sslip.io/web/）
//         local（本工作树 dist，自起 vite preview :5341 起、被占就往后挪；先 npx vite build）
//         dir=/某个/dist（任意一份构建产物，比如改动前留的一份），可写多个，默认 online local
//   环境变量 LH_SECS=5（每个场景悬停秒数）、LH_SCN=full,dense,pane,wl,watch（只跑其中几个）
//
// 每个场景：把鼠标放到某一行图例的名字上 → 在行内来回慢慢挪几像素（每 40 ms 一步，持续 LH_SECS 秒）→
// 再把指针停在「隐藏」按钮上 LH_SECS 秒（±2 像素）看它稳不稳；最后像人一样挪过去、停 300 ms 瞄准、按下停 90 ms 松开，最多试 5 次。行情走真实推送（WebSocket 照连）。
// 记录：
//   · 悬停期间图例子树替换（childList 记录里带走元素节点的条数）/ 秒、文本节点改字次数 / 秒
//   · 指针下那一行（按节点身份）被换掉的次数；隐藏按钮 getBoundingClientRect().x 的抖动范围（max − min）、
//     按钮看不见（宽 0）的帧占比
//   · 点击：第几次才生效（hidden 集合里有没有这个指标）、按下与松开落在不是同一个节点上的次数、线有没有从画面上消失
// 场景：
//   full  一图，主图图例 MA 那一行（每个指标一行）
//   dense 九图（格高 360–500 → 主图图例并成一行、悬停展开），MA 那一块（行首）
//   densevol 同上，「成交量」那一块（行尾：悬停展开后行变窄，指针可能落到行外又收起来）
//   pane  一图，副图图例 MACD 那一行
//   wl    一图，主图图例「成交量」那一行（读数每笔成交都变）
//   ——以下是「同类问题」全局排查的通用场景（LH_SCN 点名才跑，或 LH_AUDIT=1 全跑）：指针停在某个可点的元素上，
//     数这块容器的子树替换、指针下的节点被换掉（detach：上一帧指针下的节点已不在文档里）的次数、点一次能不能派发到它
//   watch    右侧自选第一行（推送改价）
//   foot     格子底栏「1天」范围按钮（钟每秒走）
//   detail   右侧品种头的星（61 秒一次的详情刷新、品种元数据到达都会重画这块；LH_DETAIL_SECS 默认 70）
//   ofband   订单流「盘口」块的 ±2% 档位钮（订单流每帧）
//   ofwall   订单流「大单」块第一行（订单流每帧）
//   ofdrawer 大单抽屉第一行（订单流每帧 + 悬停行时 500 ms 一帧）
//   ofpanel  订单流侧栏「改门槛与步长」齿轮（订单流每帧）
//   ofvenue  订单流「盘口」块各家格子（带悬停说明）
//   sector   板块页第一行（10 秒一轮的行情轮询；LH_SECTOR_SECS 默认 25）
import { chromium } from 'playwright-core'
import { spawn } from 'node:child_process'
import { CHROME, sleep, corsShim } from './f-lib.mjs'
import { baseState, KEY } from './draw-lib.mjs'

const ONLINE = 'https://kanpan.43-160-232-253.sslip.io/web/'
const SECS = Number(process.env.LH_SECS || 5)
const ONLY = (process.env.LH_SCN || '').split(',').filter(Boolean)
const args = process.argv.slice(2)
const targets = (args.length ? args : ['online', 'local']).map(a => a === 'online' ? { name: 'online', url: ONLINE } : a === 'local' ? { name: 'local', dir: 'dist' } : a.startsWith('dir=') ? { name: a.slice(4), dir: a.slice(4) } : { name: a, url: a })

const ROOT = new URL('..', import.meta.url).pathname
let port = Number(process.env.LH_PORT || 5341)
async function preview(dir, tries = 6) {
  const p = port++
  try { return await preview1(dir, p) } catch (e) { if (tries > 1) return preview(dir, tries - 1); throw e }
}
async function preview1(dir, p) {
  const srv = spawn(new URL('../node_modules/.bin/vite', import.meta.url).pathname, ['preview', '--port', String(p), '--strictPort', '--outDir', dir], { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'] })
  await new Promise((res, rej) => { srv.stdout.on('data', d => { if (/localhost:/.test(String(d))) res() }); srv.on('exit', c => rej(new Error('preview 退出 ' + c))); setTimeout(() => rej(new Error('preview 起不来')), 20000) })
  const stop = () => { try { srv.kill('SIGTERM') } catch { /* 已退 */ } }
  process.on('exit', stop)
  return { url: `http://localhost:${p}/web/`, stop }
}

/** 页内：拿活的格子（借 __cells() 里那次 cells.map 把数组捞出来）、装 MutationObserver 与逐帧取样 */
const PAGE = () => {
  const NS = (window.__lh = {})
  NS.cells = () => {
    if (typeof window.__cells !== 'function') return null
    let got = null
    const orig = Array.prototype.map
    Array.prototype.map = function (...a) { if (!got && this.length && this[0] && this[0].chart && this[0].host) got = this; return orig.apply(this, a) }
    try { window.__cells() } catch { /* 还没起来 */ } finally { Array.prototype.map = orig }
    return got
  }
  NS.ch = (i = 0) => NS.cells()?.[i]?.chart ?? null
  const ids = new WeakMap(); let nid = 0
  NS.idOf = el => { if (!el) return 0; let v = ids.get(el); if (!v) { v = ++nid; ids.set(el, v) } return v }
  /** 找场景要点的那一行 / 那一块 / 那个按钮 */
  NS.find = (scn, cell = 0) => {
    if (NS.dom) { const el = document.querySelector(NS.dom.target); return el ? { row: el, name: el, btn: el } : null }
    const host = NS.cells()?.[cell]?.host
    if (scn === 'watch') {
      const row = document.querySelector('.watch-list .wrow, .watch .wrow, [data-watch-row], .wl-row, .watch-row')
      return row ? { row, name: row.firstElementChild, btn: row.querySelector('.star, [data-act="star"], button') } : null
    }
    if (!host) return null
    const want = { full: 'MA', dense: 'MA', densevol: '成交量', pane: 'MACD', wl: '成交量' }[scn]
    const dense = scn === 'dense' || scn === 'densevol'
    const box = scn === 'pane' ? host.querySelectorAll('.pane-legend .lrow') : dense ? host.querySelectorAll('.legend .dchip') : host.querySelectorAll('.legend .lrow')
    const pick = list => { for (const row of list) { const n = row.querySelector('.ind-name'); if (n && n.textContent.trim() === want) return { row, name: n, btn: row.querySelector('[data-act="toggle"]') } } return null }
    // 没有 dense 档的旧包（线上）在九图里仍是每个指标一行
    return pick(box) ?? (dense ? pick(host.querySelectorAll('.legend .lrow')) : null)
  }
  NS.start = (scn, cell = 0) => {
    const host = NS.dom ? document.querySelector(NS.dom.box) : NS.cells()?.[cell]?.host
    const S = (NS.s = { detach: 0, lastU: null, hits: 0, onBtn: 0, mx: -1, my: -1, muts: 0, repl: 0, chars: 0, attrs: 0, rowIds: new Set(), xs: [], ws: [], hov: 0, hidden: 0, frames: 0, t0: performance.now(), stop: false, downT: null, upT: null, mism: 0, clicks: 0 })
    const mo = new MutationObserver(recs => {
      for (const r of recs) {
        if (r.type === 'characterData') S.chars++
        else if (r.type === 'attributes') S.attrs++
        else { S.muts++; for (const n of r.removedNodes) if (n.nodeType === 1) { S.repl++; break } }
      }
    })
    const target = host
    mo.observe(target, { subtree: true, childList: true, characterData: true, attributes: false })
    S.mo = mo
    const tick = () => {
      if (S.stop) return
      const f = NS.find(scn, cell)
      if (f) {
        S.rowIds.add(NS.idOf(f.row))
        if (f.btn) { const r = f.btn.getBoundingClientRect(); if (r.width > 0) S.xs.push(r.x); else S.hidden++ }
        if (f.row.matches(':hover')) S.hov++
        // 指针此刻落在哪：按钮（点下去能生效）还是别处（行收起后露出来的画布）
        if (S.mx >= 0 && f.btn) { const el = document.elementFromPoint(S.mx, S.my); if (el && (el === f.btn || f.btn.contains(el))) S.onBtn++; else if ((S.miss ||= []).length < 6) S.miss.push(el ? `${el.tagName.toLowerCase()}.${String(el.className).slice(0, 40)}@vis=${getComputedStyle(f.btn).visibility}` : 'null') }
      }
      // 指针下的节点被换掉：上一帧指针下的那个节点这一帧已不在文档里（:hover 要等下一次 mousemove 才落到新节点上）
      if (S.mx >= 0) { const u = document.elementFromPoint(S.mx, S.my); if (S.lastU && S.lastU !== u && !S.lastU.isConnected) S.detach++; S.lastU = u }
      S.frames++
      requestAnimationFrame(tick)
    }
    requestAnimationFrame(tick)
    // 按下 / 松开落在哪个节点上（click 只在两者是同一个节点或其祖先时才派发）
    const dn = e => { S.downT = e.target }, up = e => { S.upT = e.target; if (S.downT && S.downT !== S.upT && !S.downT.contains?.(S.upT) && !S.upT.contains?.(S.downT)) S.mism++; if (S.downT && !S.downT.isConnected) S.mism += 0 }
    const ck = e => { S.clicks++; if (NS.dom && e.target?.closest?.(NS.dom.target)) S.hits++ }
    const mv = e => { S.mx = e.clientX; S.my = e.clientY }
    document.addEventListener('mousemove', mv, true)
    document.addEventListener('mousedown', dn, true); document.addEventListener('mouseup', up, true); document.addEventListener('click', ck, true)
    S.off = () => { document.removeEventListener('mousedown', dn, true); document.removeEventListener('mouseup', up, true); document.removeEventListener('click', ck, true); document.removeEventListener('mousemove', mv, true) }
  }
  NS.stop = () => {
    const S = NS.s; S.stop = true; S.mo.disconnect(); S.off()
    const secs = (performance.now() - S.t0) / 1000
    const xs = S.xs
    return { secs, replPerSec: S.repl / secs, mutsPerSec: S.muts / secs, charsPerSec: S.chars / secs, rowNodes: S.rowIds.size, xJitter: xs.length ? Math.max(...xs) - Math.min(...xs) : null, miss: S.miss || [], btnHiddenPct: S.frames ? 100 * S.hidden / S.frames : 0, hoverPct: S.frames ? 100 * S.hov / S.frames : 0, frames: S.frames, mism: S.mism, clicks: S.clicks, hits: S.hits, detach: S.detach, onBtnPct: S.frames ? 100 * S.onBtn / S.frames : 0 }
  }
  NS.btnRect = (scn, cell = 0) => { const f = NS.find(scn, cell); if (!f?.btn) return null; const r = f.btn.getBoundingClientRect(); return r.width ? { x: r.x + r.width / 2, y: r.y + r.height / 2, w: r.width } : null }
  NS.nameRect = (scn, cell = 0) => { const f = NS.find(scn, cell); if (!f?.name) return null; const r = f.name.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2, w: r.width, h: r.height } }
  /** 主图上某种颜色（指标线）的像素数：隐藏生效后应当掉到接近 0 */
  NS.colorPx = (hex, cell = 0) => {
    const ch = NS.ch(cell); const cv = ch?.canvas || ch?.ctx?.canvas; if (!cv) return -1
    const p = ch._panes?.[0]; const g = cv.getContext('2d'); const dpr = cv.width / cv.getBoundingClientRect().width
    const d = g.getImageData(0, Math.round((p?.y ?? 0) * dpr), Math.round(ch.plotW() * dpr), Math.round((p?.h ?? 200) * dpr)).data
    const R = parseInt(hex.slice(1, 3), 16), G = parseInt(hex.slice(3, 5), 16), B = parseInt(hex.slice(5, 7), 16)
    let n = 0; for (let i = 0; i < d.length; i += 4) if (Math.abs(d[i] - R) + Math.abs(d[i + 1] - G) + Math.abs(d[i + 2] - B) < 40) n++
    return n
  }
  NS.isHidden = (id, cell = 0) => !!NS.ch(cell)?.hidden?.has(id)
}

const SCN = {
  full: { layout: '1', id: 'ma', color: '#F7A600' },
  wl: { layout: '1', id: 'vol' },
  pane: { layout: '1', id: 'macd' },
  dense: { layout: '9', id: 'ma', color: '#F7A600' },
  densevol: { layout: '9', id: 'vol' },
  watch: { dom: { target: '#sidePanel tr[data-sym]', box: '#sidePanel' }, panel: 'watch' },
  foot: { dom: { target: '.cell-foot [data-range="1"]', box: '.cell-foot' } },
  detail: { dom: { target: '#detail [data-star]', box: '#sidePanel' }, panel: 'watch', secs: Number(process.env.LH_DETAIL_SECS || 70) },
  ofband: { dom: { target: '#ofPress [data-of="band"][data-v="2"]', box: '#sidePanel' }, panel: 'watch', of: true },
  ofvenue: { dom: { target: '#ofVenues .of-vc', box: '#sidePanel' }, panel: 'watch', of: true },
  ofwall: { dom: { target: '#ofWalls .of-wall', box: '#sidePanel' }, panel: 'watch', of: true },
  ofdrawer: { dom: { target: '.of-kr-list .of-kr', box: '.of-kr-list' }, panel: 'watch', of: true, drawer: true },
  ofpanel: { dom: { target: '#ofpThr [data-ofp="settings"]', box: '#sidePanel' }, panel: 'flow', of: true },
  sector: { dom: { target: '#secBody tr[data-sec]', box: '#secBody' }, hash: '#sectors', secs: Number(process.env.LH_SECTOR_SECS || 25) },
}
const DOM_SCN = Object.keys(SCN).filter(k => SCN[k].dom)

async function runScenario(browser, url, scn) {
  const cfg = SCN[scn]
  const ctx = await browser.newContext({ viewport: { width: 2560, height: 1440 }, deviceScaleFactor: 1, locale: 'zh-CN', timezoneId: 'Asia/Shanghai' })
  await corsShim(ctx)
  const state = baseState({ layout: cfg.layout || '1', panel: cfg.panel ?? null, ind: { ma: true, ema: false, boll: false, vol: true, subs: ['macd'] }, drawColor: null,
    ...(cfg.of ? { orderFlow: true, slots: { ladder: false, drawer: !!cfg.drawer, widgets: ['watch', 'detail', 'book', 'walls', 'alerts'] } } : {}) })
  await ctx.addInitScript(([k, s]) => { if (!sessionStorage.getItem('lh-seeded')) { sessionStorage.setItem('lh-seeded', '1'); localStorage.clear(); localStorage.setItem(k, s) } }, [KEY, JSON.stringify(state)])
  await ctx.addInitScript(PAGE)
  if (cfg.dom) await ctx.addInitScript(d => { window.__lhDom = d }, cfg.dom)
  // LH_TRACE=1：谁整块重写了包着目标的节点（innerHTML / replaceChildren），把调用栈记下来，结果里打印
  if (cfg.dom && process.env.LH_TRACE) await ctx.addInitScript(sel => {
    window.__lhTrace = []
    const rec = (el, how) => { try { if (el.querySelector?.(sel) || el.matches?.(sel)) window.__lhTrace.push(how + ' ' + (el.id || el.className) + ' @' + ((performance.now() - (window.__lhT0 ?? 0)) / 1000).toFixed(1) + 's（相对悬停开始）\n' + new Error().stack.split('\n').slice(2, 8).join('\n')) } catch {} }
    const d = Object.getOwnPropertyDescriptor(Element.prototype, 'innerHTML')
    Object.defineProperty(Element.prototype, 'innerHTML', { ...d, set(v) { rec(this, 'innerHTML'); d.set.call(this, v) } })
    const rc = Element.prototype.replaceChildren
    Element.prototype.replaceChildren = function (...a) { rec(this, 'replaceChildren'); return rc.apply(this, a) }
  }, cfg.dom.target)
  // 数 WebSocket 消息（推送多快）
  await ctx.addInitScript(() => {
    window.__wsMsgs = 0
    const W = window.WebSocket
    window.WebSocket = class extends W { constructor(...a) { super(...a); this.addEventListener('message', () => { window.__wsMsgs++ }) } }
  })
  const page = await ctx.newPage()
  const errs = []
  page.on('pageerror', e => errs.push(String(e).slice(0, 200)))
  await page.goto(url + (cfg.hash || '#chart'), { waitUntil: 'domcontentloaded' })
  const n = cfg.layout === '9' ? 9 : 1
  if (cfg.dom) {
    await page.evaluate(() => { window.__lh.dom = window.__lhDom })
    if (!cfg.hash) await page.waitForFunction(() => { const c = window.__cells?.(); return c && c.length >= 1 && c[0].bars > 0 }, null, { timeout: 60000, polling: 200 })
    await page.waitForSelector(cfg.dom.target, { timeout: 60000, state: 'visible' }).catch(() => {})
    await sleep(cfg.of ? 6000 : 1500)
  } else
  await page.waitForFunction(n => { const c = window.__cells?.(); return c && c.length >= n && c[0].bars > 0 && window.__lh?.ch(0)?._panes }, n, { timeout: 60000, polling: 200 })
  // 等推送真的来（实时 K 线的 WebSocket）
  await page.waitForFunction(() => window.__wsMsgs > 5, null, { timeout: 30000, polling: 200 }).catch(() => {})
  await sleep(1500)
  const out = { scn }
  const nr = await page.evaluate(s => window.__lh.nameRect(s), scn)
  if (!nr) { out.err = '找不到目标行'; out.dom = await page.evaluate(() => document.querySelector('.legend')?.innerHTML.slice(0, 300)); await ctx.close(); return out }
  const px0 = cfg.color ? await page.evaluate(c => window.__lh.colorPx(c), cfg.color) : null
  const ws0 = await page.evaluate(() => window.__wsMsgs)
  // 1) 悬停：放到名字上，在名字范围里来回慢慢挪几像素
  await page.mouse.move(nr.x, nr.y)
  await sleep(100)
  await page.evaluate(s => { window.__lh.start(s); window.__lhT0 = performance.now() }, scn)
  const t0 = Date.now(); let k = 0
  const secs = cfg.secs || (cfg.dom ? Math.max(SECS, 8) : SECS)
  while (Date.now() - t0 < secs * 1000) {
    k++
    const dx = Math.round(Math.sin(k / 6) * Math.min(4, nr.w / 2 - 1)), dy = Math.round(Math.cos(k / 9) * Math.min(2, nr.h / 2 - 2))
    await page.mouse.move(nr.x + dx, nr.y + dy)
    await sleep(40)
  }
  const hover = await page.evaluate(() => window.__lh.stop())
  out.hover = hover
  out.wsPerSec = (await page.evaluate(() => window.__wsMsgs) - ws0) / hover.secs
  // 1b) 指针停在「隐藏」按钮上（用户瞄准要点的那一刻）：在按钮范围里来回挪 ±2 像素（通用场景悬停的就是目标本身，不另测）
  if (!cfg.dom) {
    await page.mouse.move(nr.x, nr.y); await sleep(150)
    const b = await page.evaluate(s => window.__lh.btnRect(s), scn)
    if (b) {
      await page.mouse.move(b.x, b.y, { steps: 6 }); await sleep(60)
      await page.evaluate(s => window.__lh.start(s), scn)
      const t1 = Date.now(); let j = 0
      while (Date.now() - t1 < SECS * 1000) { j++; await page.mouse.move(b.x + Math.round(Math.sin(j / 5) * 2), b.y + Math.round(Math.cos(j / 7) * 2)); await sleep(40) }
      out.onBtn = await page.evaluate(() => window.__lh.stop())
    }
  }
  // 2) 点隐藏：像人一样挪过去（8 步 / 160 ms）、按下停 90 ms 松开；没生效就再来，最多 5 次
  await page.evaluate(s => window.__lh.start(s), scn)
  let tries = 0, okAt = null
  const isDone = () => cfg.dom ? page.evaluate(() => window.__lh.s.hits) : cfg.id ? page.evaluate(id => window.__lh.isHidden(id), cfg.id) : page.evaluate(() => false)
  const was = cfg.id ? await isDone() : null
  for (tries = 1; tries <= 5; tries++) {
    // 每次先回到名字上让按钮出来，再找按钮当前位置
    const r0 = await page.evaluate(s => window.__lh.nameRect(s), scn)
    if (r0) await page.mouse.move(r0.x, r0.y)
    await sleep(120)
    const b = await page.evaluate(s => window.__lh.btnRect(s), scn)
    if (!b) continue
    await page.mouse.move(b.x, b.y, { steps: 8 })
    await sleep(300) // 瞄准：停一下再按
    await page.mouse.down(); await sleep(90); await page.mouse.up()
    await sleep(150)
    if ((cfg.id || cfg.dom) && (await isDone()) !== was) { okAt = tries; break }
  }
  const clk = await page.evaluate(() => window.__lh.stop())
  out.click = { okAt, tries: okAt ?? tries - 1, mism: clk.mism, clicks: clk.clicks, replPerSec: clk.replPerSec, detach: clk.detach }
  if (cfg.color && okAt) {
    await page.mouse.move(5, 5); await sleep(400)
    out.click.px = [px0, await page.evaluate(c => window.__lh.colorPx(c), cfg.color)]
  }
  if (process.env.LH_TRACE) out.trace = await page.evaluate(() => window.__lhTrace?.slice(-8))
  out.errs = errs.slice(0, 3)
  await ctx.close()
  return out
}

const cfg0 = k => SCN[k]
const fmt = (v, d = 1) => v == null ? '—' : typeof v === 'number' ? v.toFixed(d) : String(v)
const browser = await chromium.launch({ executablePath: CHROME, headless: true, args: ['--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--disable-backgrounding-occluded-windows'] })
const rows = []
try {
  for (const t of targets) {
    let url = t.url, srv = null
    if (t.dir) { srv = await preview(t.dir); url = srv.url }
    for (const scn of Object.keys(SCN)) {
      if (ONLY.length && !ONLY.includes(scn)) continue
      if (!ONLY.length && cfg0(scn).dom && !process.env.LH_AUDIT) continue // 通用场景（全局排查）点名或 LH_AUDIT=1 才跑
      let r
      try { r = await runScenario(browser, url, scn) } catch (e) { r = { scn, err: String(e).split('\n')[0] } }
      rows.push({ t: t.name, ...r })
      if (r.trace?.length) console.log(`[${t.name}] ${scn} 重写包着目标的节点（最近 ${r.trace.length} 次）：\n` + r.trace.join('\n---\n'))
      if (r.err) { console.log(`[${t.name}] ${scn}  出错：${r.err}${r.dom ? '  ' + r.dom : ''}`); continue }
      const h = r.hover, c = r.click, o = r.onBtn
      if (SCN[scn].dom) {
        console.log(`[${t.name}] ${scn}  悬停 ${fmt(h.secs)}s：容器子树替换 ${fmt(h.replPerSec)}/s、改字 ${fmt(h.charsPerSec)}/s、指针下的节点被换掉 ${h.detach} 次、目标节点换了 ${h.rowNodes - 1} 次、目标 x 抖动 ${fmt(h.xJitter)}px、指针真在目标上 ${fmt(h.onBtnPct)}% 帧 | 点击：${c.okAt ? `第 ${c.okAt} 次派发到目标` : `${c.tries} 次都没派发到目标`}、按下松开不在同一节点 ${c.mism} 次${r.errs?.length ? '  页面报错：' + r.errs.join(' | ') : ''}`)
        continue
      }
      console.log(`[${t.name}] ${scn}  推送 ${fmt(r.wsPerSec)}/s | 悬停 ${fmt(h.secs)}s：子树替换 ${fmt(h.replPerSec)}/s、childList ${fmt(h.mutsPerSec)}/s、改字 ${fmt(h.charsPerSec)}/s、指针下的行换了 ${h.rowNodes - 1} 次、按钮 x 抖动 ${fmt(h.xJitter)}px、按钮不见 ${fmt(h.hoverPct != null ? h.btnHiddenPct : null)}% 帧、行处于悬停 ${fmt(h.hoverPct)}% 帧 | 停在按钮上：${o ? `子树替换 ${fmt(o.replPerSec)}/s、按钮 x 抖动 ${fmt(o.xJitter)}px、指针真落在按钮上 ${fmt(o.onBtnPct)}%${o.miss?.length ? "（没落在时指针下是 " + o.miss.join(" ｜ ") + "）" : ""} 帧` : '按钮没出来'} | 点击：${c.okAt ? `第 ${c.okAt} 次生效` : `${c.tries} 次都没生效`}、按下松开不在同一节点 ${c.mism} 次、click 事件 ${c.clicks} 次${c.px ? `、线的像素 ${c.px[0]} → ${c.px[1]}` : ''}${r.errs?.length ? '  页面报错：' + r.errs.join(' | ') : ''}`)
    }
    srv?.stop()
  }
} finally { await browser.close() }
// 场景跑出错（等不到 K 线、页面崩）也算未达标，不许在出错时还打「全部达标」
const bad = rows.filter(r => r.err ? true : SCN[r.scn].dom ? (r.hover.detach > 0 || r.click.okAt !== 1) : (r.hover.replPerSec > 0 || (r.hover.xJitter ?? 0) > 0.5 || r.click.okAt !== 1 || !r.onBtn || r.onBtn.replPerSec > 0 || r.onBtn.onBtnPct < 99))
console.log(bad.length ? `\n未达标 ${bad.length} 项（悬停期间子树替换 > 0、按钮 x 抖动 > 0.5px、指针停在按钮上却有帧不在按钮上，或点一次没生效）：${bad.map(r => r.t + '/' + r.scn).join(' ')}` : '\n全部达标：悬停期间子树替换 0、按钮 x 不动、点一次就生效')
process.exitCode = bad.length && process.env.LH_STRICT ? 1 : 0
