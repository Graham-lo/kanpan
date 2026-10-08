// 临时：质感收尾全页扫一遍截图（不入库）
import fs from 'node:fs'
import { chromium } from 'playwright-core'
import { corsShim } from './f-lib.mjs'

const BASE = process.env.URL || 'http://localhost:5391/web/'
const OUT = process.env.OUT || '/private/tmp/claude-501/-Users-mdd-zhk-kanpan/3b7c6b71-16af-4414-93f0-31525b78016d/scratchpad/sweep'
const W = +(process.env.W || 1440), H = +(process.env.H || 900)
const ONLY = process.argv.slice(2)
fs.mkdirSync(OUT, { recursive: true })
const sleep = ms => new Promise(r => setTimeout(r, ms))

const base = (over = {}) => ({
  theme: 'light', skin: process.env.SKIN || 'sage', updown: 'green-up', greenUpMigrated: true, route: 'gateway', routePicked: true,
  layout: '1', cells: [{ symbol: 'BTCUSDT', iv: '1h' }], active: 0, pinned: ['1m', '5m', '15m', '1h', '4h', '1d', '1w'], panel: 'watch', watchTab: 'crypto',
  watch: { crypto: ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'BNBUSDT', 'XRPUSDT', 'DOGEUSDT'], us: ['NVDAUSDT', 'TSLAUSDT'], com: ['XAUUSDT', 'XAGUSDT'] },
  ind: { ma: true, ema: false, boll: false, vol: true, subs: ['macd'] }, params: null,
  drawings: {}, alerts: [], notes: [], slots: { ladder: false, drawer: false, widgets: ['watch', 'detail'] }, linkCross: true, ...over,
})

const browser = await chromium.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true })
const errs = []
async function page(state, hash = '#chart') {
  const ctx = await browser.newContext({ viewport: { width: W, height: H }, deviceScaleFactor: 1, locale: 'zh-CN', timezoneId: 'Asia/Shanghai' })
  await corsShim(ctx)
  await ctx.addInitScript(kv => { if (sessionStorage.getItem('s')) return; sessionStorage.setItem('s', '1'); localStorage.clear(); localStorage.setItem('hkline-web-v1', kv) }, JSON.stringify(state))
  const p = await ctx.newPage()
  p.on('pageerror', e => errs.push(String(e)))
  await p.goto(BASE + hash, { waitUntil: 'load' })
  await sleep(3500)
  return { p, ctx }
}
const shot = async (p, name) => { await p.screenshot({ path: `${OUT}/${name}.png` }); console.log('shot', name) }
const theme = async (p, want) => { const t = await p.evaluate(() => document.documentElement.dataset.theme); if (t !== want) { await p.click('[aria-label="切换深浅色"]'); await sleep(400) } }
const esc = async p => { await p.keyboard.press('Escape'); await sleep(250) }

const SCENES = {
  async sectors(p, t) { await p.click('.nav a[data-page="sectors"]'); await sleep(2500); await shot(p, `sectors-${t}`); const r = await p.$('#page-sectors [data-sector], #page-sectors tr[data-id], #page-sectors .sec-row'); if (r) { await r.click(); await sleep(1500); await shot(p, `sectors-open-${t}`) } },
  async review(p, t) { await p.click('.nav a[data-page="review"]'); await sleep(2000); await shot(p, `review-${t}`) },
  async me(p, t) { await p.click('#hdrAvatar'); await sleep(800); for (const k of ['account', 'exchange', 'notify', 'look', 'general', 'devices', 'about']) { await p.click(`[data-me="${k}"]`); await sleep(400); await shot(p, `me-${k}-${t}`) } },
  async chart(p, t) { await shot(p, `chart-${t}`) },
  async watchmore(p, t) { await p.click('#wMore'); await sleep(400); await shot(p, `watchmore-${t}`); await esc(p) },
  async settings(p, t) { await p.click('#tbSettings'); await sleep(600); await shot(p, `chartsettings-${t}`); await esc(p) },
  async alert(p, t) { await p.click('#tbAlert'); await sleep(800); await shot(p, `alertdlg-${t}`); await esc(p); await p.click('[data-panel="alerts"]'); await sleep(600); await shot(p, `alertpanel-${t}`) },
  async search(p, t) { await p.click('#searchTrigger'); await sleep(800); await shot(p, `search-${t}`); await esc(p) },
  async share(p, t) { await p.click('#tbShare'); await sleep(800); await shot(p, `share-${t}`); await esc(p) },
  async ind(p, t) { await p.click('#tbInd'); await sleep(800); await shot(p, `ind-${t}`); await esc(p) },
  async layout(p, t) { await p.click('#tbLayout'); await sleep(500); await shot(p, `layoutmenu-${t}`); await esc(p) },
  async ctxmenu(p, t) { const c = await p.$('.chart-cell canvas'); const b = await c.boundingBox(); await p.mouse.click(b.x + b.width / 2, b.y + b.height / 2, { button: 'right' }); await sleep(500); await shot(p, `ctxmenu-${t}`); await esc(p) },
  async compare(p, t) { await p.click('#tbCompare'); await sleep(800); await shot(p, `compare-${t}`); await esc(p) },
  async rail(p, t) { for (const k of ['flow', 'notes', 'trades']) { await p.click(`[data-panel="${k}"]`); await sleep(700); await shot(p, `rail-${k}-${t}`) } },
}

const list = ONLY.length ? ONLY : ['chart', 'sectors', 'review', 'me', 'watchmore', 'settings', 'alert', 'search', 'share', 'ind', 'layout', 'ctxmenu', 'compare', 'rail', 'drawer', 'l16']
for (const t of ['light', 'dark']) {
  for (const s of list) {
    try {
      if (s === 'drawer') {
        const { p, ctx } = await page(base({ orderFlow: true, panel: 'flow', slots: { ladder: true, drawer: true, widgets: ['watch', 'detail'] } }))
        await theme(p, t); await sleep(+(process.env.DW || 6000)); await shot(p, `drawer-${t}`); await ctx.close(); continue
      }
      if (s === 'dprobe') {
        const { p, ctx } = await page(base({ orderFlow: true, panel: 'flow', slots: { ladder: true, drawer: true, widgets: ['watch', 'detail'] } }))
        await theme(p, t); await sleep(14000)
        for (const w of [1024, 1100, 1180, 1280, 1366, 1440, 1600, 1680, 1920, 2240, 2560]) {
          await p.setViewportSize({ width: w, height: Math.max(800, Math.round(w * .56)) }); await sleep(1800)
          const r = await p.evaluate(() => {
            const out = []
            const box = el => { const rg = document.createRange(); rg.selectNodeContents(el); const b = rg.getBoundingClientRect(); return b }
            for (const blk of document.querySelectorAll('.of-dr .of-blk')) {
              const name = blk.className
              for (const row of blk.querySelectorAll('.bh, .br, .wr, .lr, .ct, .of-sr .tx')) {
                const kids = [...row.children].filter(k => getComputedStyle(k).display !== 'none' && k.offsetWidth)
                for (const k of kids) if (k.scrollWidth > k.clientWidth + 1 && getComputedStyle(k).overflow !== 'visible') out.push(`${name} ${row.className} clip .${k.className} ${k.scrollWidth}>${k.clientWidth} "${k.textContent.trim().slice(0, 20)}"`)
                const bs = kids.map(k => ({ k, b: box(k) })).filter(x => x.b.width > 0)
                for (let i = 0; i < bs.length; i++) for (let j = i + 1; j < bs.length; j++) {
                  const a = bs[i].b, b = bs[j].b
                  if (a.right > b.left + .5 && b.right > a.left + .5 && a.bottom > b.top + .5 && b.bottom > a.top + .5) out.push(`${name} ${row.className} overlap .${bs[i].k.className}"${bs[i].k.textContent.trim().slice(0, 12)}" × .${bs[j].k.className}"${bs[j].k.textContent.trim().slice(0, 12)}"`)
                }
                // 子元素文字溢出到自己格子外
                for (const x of bs) { const cb = x.k.getBoundingClientRect(); if (x.b.right > cb.right + 1 || x.b.left < cb.left - 1) out.push(`${name} ${row.className} spill .${x.k.className} "${x.k.textContent.trim().slice(0, 16)}" text ${x.b.left.toFixed(0)}-${x.b.right.toFixed(0)} cell ${cb.left.toFixed(0)}-${cb.right.toFixed(0)}`) }
              }
            }
            for (const blk of document.querySelectorAll('.of-dr .of-blk')) {
              const bb = blk.getBoundingClientRect()
              for (const el of blk.querySelectorAll('*')) {
                if (el.closest('[hidden]') || !el.textContent.trim() || [...el.children].some(c => c.textContent.trim())) continue
                if (el.closest('.bl') && el.closest('.br')) { const bl = el.closest('.bl').getBoundingClientRect(); const rb = el.getBoundingClientRect(); if (rb.bottom < bl.top || rb.top > bl.bottom) continue }
                const rb = el instanceof SVGElement ? el.getBoundingClientRect() : box(el)
                if (rb.width && (rb.right > bb.right - 2 || rb.left < bb.left + 2)) out.push(`${blk.className} outside "${el.textContent.trim().slice(0, 20)}" ${rb.left.toFixed(0)}-${rb.right.toFixed(0)} blk ${bb.left.toFixed(0)}-${bb.right.toFixed(0)}`)
                const sv = el.closest('svg'); if (sv && el.tagName === 'text') { const sb = sv.getBoundingClientRect(); if (rb.right > sb.right + .5) out.push(`${blk.className} svg-clip "${el.textContent.trim()}"`) }
              }
              // 墙字压到圆环
              for (const g of blk.querySelectorAll('g.wall')) { const ts = [...g.querySelectorAll('text')]; const ring = g.querySelector('circle, path'); if (ts[1] && ring) { const a = ts[1].getBoundingClientRect(), r = [...g.querySelectorAll('circle,path')].map(e => e.getBoundingClientRect().left); const rl = Math.min(...r); if (a.right > rl) out.push(`wall label under ring "${ts[1].textContent}"`) } }
            }
            const dr = document.querySelector('.of-dr')
            return { w: dr?.clientWidth, issues: [...new Set(out)].slice(0, 30) }
          })
          console.log(t, w, 'drawer', r.w, r.issues.length ? '\n  ' + r.issues.join('\n  ') : 'OK')
          const dr = await p.$('.of-dr'); if (dr) await dr.screenshot({ path: `${OUT}/dprobe-${t}-${w}.png` })
        }
        await ctx.close(); continue
      }
      if (s === 'l16') {
        const cells = ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'XAUUSDT', 'BNBUSDT', 'XRPUSDT', 'DOGEUSDT', 'NVDAUSDT', 'ADAUSDT', 'LINKUSDT', 'AVAXUSDT', 'SUIUSDT', 'XAGUSDT', 'TSLAUSDT', 'LTCUSDT', 'TRXUSDT'].map(symbol => ({ symbol, iv: '1h' }))
        const { p, ctx } = await page(base({ layout: '16', cells }))
        await theme(p, t); await sleep(2500); await shot(p, `l16-${t}`); await ctx.close(); continue
      }
      const { p, ctx } = await page(base())
      await theme(p, t)
      await SCENES[s](p, t)
      await ctx.close()
    } catch (e) { console.log('FAIL', s, t, String(e).split('\n')[0]) }
  }
}
console.log('errors', errs.slice(0, 10))
await browser.close()
