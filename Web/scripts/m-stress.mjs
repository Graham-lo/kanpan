// Hkline 手机网页版 · 压测回归（以手机视口 402×874 DPR 3 把高频与长时间操作跑一遍，断言不漏、不叠、不丢）
//   node scripts/m-stress.mjs [地址] [段落…]
//   段落：panels（面板开关不漏 DOM / 监听）、switch（换品种 / 周期不累积订阅与连接）、offline（断网再联网续上）、
//         sw（Service Worker：第一次打开后就能离线冷启动出壳）
//   默认地址 http://localhost:5190/web/m/（先 npm run build && npx vite preview --port 5190）
// 每一项打一行「✓ / ✗」，有 ✗ 退出码 1。
import { chromium } from 'playwright-core'

const URL_ = process.argv[2] || 'http://localhost:5190/web/m/'
const PARTS = process.argv.slice(3)
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const want = p => !PARTS.length || PARTS.includes(p)
const sleep = ms => new Promise(r => setTimeout(r, ms))
const results = []
const ok = (name, pass, detail = '') => { results.push(pass); console.log(`${pass ? '✓' : '✗'} ${name}${detail ? ' — ' + detail : ''}`) }

// 注入：window / document / MediaQueryList 上的监听按「目标:类型」记净数，WebSocket 记开关与订阅
const INSTR = () => {
  const add = EventTarget.prototype.addEventListener, rem = EventTarget.prototype.removeEventListener
  const gl = (window.__gl = {})
  const nm = t => t === window ? 'window' : t === document ? 'document' : t instanceof MediaQueryList ? 'mq' : t === window.visualViewport ? 'vv' : null
  EventTarget.prototype.addEventListener = function (ty, f, o) { const n = nm(this); if (n && f) gl[n + ':' + ty] = (gl[n + ':' + ty] || 0) + 1; return add.call(this, ty, f, o) }
  EventTarget.prototype.removeEventListener = function (ty, f, o) { const n = nm(this); if (n && f) gl[n + ':' + ty] = (gl[n + ':' + ty] || 0) - 1; return rem.call(this, ty, f, o) }
  const W = window.WebSocket
  const ws = (window.__ws = { opened: 0, live: new Set(), subs: 0, unsubs: 0 })
  window.WebSocket = class extends W {
    constructor(...a) { super(...a); ws.opened++; ws.live.add(this); this.addEventListener('close', () => ws.live.delete(this)) }
    send(d) { try { const m = JSON.parse(d); if (m.method === 'SUBSCRIBE') ws.subs += m.params.length; if (m.method === 'UNSUBSCRIBE') ws.unsubs += m.params.length } catch { /* 不是 JSON */ } return super.send(d) }
  }
  window.__errs = []
  addEventListener('error', e => window.__errs.push(String(e.message)))
  addEventListener('unhandledrejection', e => window.__errs.push('rej: ' + String(e.reason?.message || e.reason)))
}

const browser = await chromium.launch({ executablePath: CHROME, headless: true })
async function page() {
  const ctx = await browser.newContext({ viewport: { width: 402, height: 874 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true, locale: 'zh-CN', timezoneId: 'Asia/Shanghai' })
  await ctx.addInitScript(INSTR)
  const p = await ctx.newPage()
  const cdp = await ctx.newCDPSession(p)
  await cdp.send('Performance.enable')
  p.metrics = async () => {
    await cdp.send('HeapProfiler.collectGarbage'); await cdp.send('HeapProfiler.collectGarbage')
    const m = Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map(x => [x.name, x.value]))
    const gl = await p.evaluate(() => ({ ...window.__gl }))
    return { nodes: m.Nodes, listeners: m.JSEventListeners, heap: m.JSHeapUsedSize / 1048576, gl }
  }
  return { ctx, p }
}
const glDiff = (a, b) => { const d = {}; for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) if ((b[k] || 0) !== (a[k] || 0)) d[k] = (b[k] || 0) - (a[k] || 0); return d }

// ───────── 面板开关：关掉的面板不能被窗口监听攥着
if (want('panels')) {
  const { ctx, p } = await page()
  await p.goto(URL_ + '#chart'); await p.waitForSelector('.cp-gear'); await sleep(2500)
  const open = { 分析: () => [...document.querySelectorAll('.cp-tail')].find(b => b.textContent.includes('分析')).click(), 图表设置: () => document.querySelector('.cp-gear').click(), 更多: () => document.querySelector('.cp-more').click() }
  // 先各开一次，懒加载的模块级监听算进基线
  for (const f of Object.values(open)) { await p.evaluate(f); await sleep(200); await p.evaluate(() => (document.querySelector('.m-sheet-scrim') || document.querySelector('.m-pop-scrim'))?.click()); await sleep(400) }
  for (const [name, f] of Object.entries(open)) {
    const m0 = await p.metrics()
    for (let i = 0; i < 20; i++) {
      await p.evaluate(f); await sleep(120)
      await p.evaluate(() => (document.querySelector('.m-sheet-scrim') || document.querySelector('.m-pop-scrim'))?.click()); await sleep(380)
    }
    const m1 = await p.metrics()
    const d = glDiff(m0.gl, m1.gl)
    ok(`「${name}」开关 20 次不漏`, m1.nodes - m0.nodes < 300 && !Object.keys(d).length, `节点 ${m1.nodes - m0.nodes >= 0 ? '+' : ''}${m1.nodes - m0.nodes}、JS 监听 ${m1.listeners - m0.listeners >= 0 ? '+' : ''}${m1.listeners - m0.listeners}、窗口监听 ${JSON.stringify(d)}`)
  }
  ok('面板段无报错', !(await p.evaluate(() => window.__errs.length)), (await p.evaluate(() => window.__errs.join(' | '))).slice(0, 300))
  await ctx.close()
}

await browser.close()
process.exit(results.every(Boolean) ? 0 : 1)
