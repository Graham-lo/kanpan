// 手机首页轮询直接更新并保留阅读位置；要点的精简文案与破位方向。
import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import { launch, preview, mockKlines } from './f-lib.mjs'
const test = await fs.readFile(new URL('../tests/m-highlights.test.ts', import.meta.url), 'utf8')
const sample = new Function(test.slice(test.indexOf('const GEN ='), test.indexOf("describe('盘口要点")) + '; return SAMPLE')()
sample.generatedAtMs = Date.now()
sample.events = [
 { id:'up', t:'levelBroken', atMs:Date.now(), low:82940, high:83139, side:'ask', distPct:0.2 },
 { id:'down', t:'levelBroken', atMs:Date.now()-1000, low:82609, high:82940, side:'bid', distPct:-0.1 },
 ...sample.events.slice(0,2),
]
for (const l of sample.levels) if (l.side) l.wallState = 'broken'
const bases=['BTC','ETH','SOL','DOGE','XRP','BNB','ADA','AVAX','LINK','LTC','BCH','DOT','TRX','TON','SUI','WIF','PEPE','APT','ARB','OP']
let revision=0
const row = (base,i) => ({base, cat:'book', atMs:Date.now(), tier:2, favorite:false, count:1, price:82700+i+revision, changePct:1,
 top:{kind:'level', ...sample.levels[2], id:'L:'+base}})
const srv=await preview(5326), browser=await launch()
try {
 const ctx=await browser.newContext({viewport:{width:393,height:852},deviceScaleFactor:3,isMobile:true,hasTouch:true})
 await mockKlines(ctx)
 await ctx.addInitScript(() => {
  const si=window.setInterval
  window.__homePolls=[]
  window.setInterval=function(fn,ms,...a) { if(ms===60000) window.__homePolls.push(()=>fn(...a));return si.call(window,fn,ms,...a) }
 })
 await ctx.route('**/v1/market/orderflow/highlights**',async route=>{
  const u=new URL(route.request().url())
  const body=u.pathname.endsWith('/board') ? {generatedAtMs:Date.now(),rows:(revision?['UNI',...bases.filter(b=>b!=='ETH')]:bases).map(row)} : {...sample,base:u.searchParams.get('base')}
  await route.fulfill({json:body})
 })
 const page=await ctx.newPage()
 const errors=[];page.on('pageerror',e=>errors.push(e.message))
 await page.goto(srv.url+'m/#home')
 await page.locator('.hm-row[data-key="BTC"]').waitFor()
 assert.equal(await page.locator('.hm-newpill').count(),0)
 await page.locator('.hm-moves .hm-scroll').evaluate(el=>el.scrollTop=250)
 const anchor=await page.locator('.hm-moves .hm-scroll').evaluate(sc=>{
  const r=[...sc.querySelectorAll('.hm-row[data-key]')].find(r=>r.getBoundingClientRect().bottom>sc.getBoundingClientRect().top)
  return {key:r.dataset.key,top:r.getBoundingClientRect().top}
 })
 revision=1
 await page.evaluate(()=>window.__homePolls.forEach(fn=>fn()))
 await page.locator('.hm-row[data-key="UNI"]').waitFor()
 assert.equal(await page.locator('.hm-row[data-key="ETH"]').count(),0)
 const top=await page.locator(`.hm-row[data-key="${anchor.key}"]`).evaluate(el=>el.getBoundingClientRect().top)
 assert.ok(Math.abs(top-anchor.top)<2,`anchor moved ${top-anchor.top}px`)
 const out=process.env.OUT || '/tmp/kanpan-home-browser'
 await fs.mkdir(out,{recursive:true})
 await page.screenshot({path:out+'/手机网页-首页静默刷新.png',animations:'disabled'})
 await page.locator('.m-tab[data-page="chart"]').click()
 await page.locator('.hl-strip').click()
 await page.locator('.hl-sheet .hl-lv .row').first().waitFor()
 assert.equal(await page.locator('.hl-lv .px small').count(),0)
 let copy=await page.locator('.hl-sheet').innerText()
 assert.doesNotMatch(copy,/测\s*\d+\s*次|距价|已破/)
 assert.ok(copy.includes('已突破')&&copy.includes('已跌破'))
 await page.locator('.hl-lv [data-lv="L:14163"]').click()
 copy=await page.locator('.hl-sheet').innerText()
 assert.doesNotMatch(copy,/测\s*\d+\s*次|距价|已破/)
 assert.ok(copy.includes('已突破'))
 await page.screenshot({path:out+'/手机网页-要点精简与方向.png',animations:'disabled'})
 await page.locator('.hl-evl').scrollIntoViewIfNeeded()
 await page.screenshot({path:out+'/手机网页-近四小时方向.png',animations:'disabled'})
 assert.deepEqual(errors,[])
 console.log(JSON.stringify({passed:true,anchor:anchor.key,offsetChange:top-anchor.top,screenshots:out}))
} finally {await browser.close();srv.stop()}
