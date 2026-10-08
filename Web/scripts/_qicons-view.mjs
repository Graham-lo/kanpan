import { chromium } from 'playwright-core'
const b = await chromium.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
const p = await b.newPage({ viewport: { width: 900, height: 400 }, deviceScaleFactor: 2 })
await p.goto('http://localhost:5391/web/#chart'); await p.waitForTimeout(1500)
await p.evaluate(async () => {
  const m = await import('/web/src/ui/icons.ts')
  const names = ['chevronDown','plus','close','check','more','drag','play','pause','toStart','replay','refresh','download','user','key','device','palette','link','logout','spec','wifiOff','candles','layers','logo']
  const row = (bg, col) => `<div style="display:flex;gap:10px;padding:10px;background:${bg};color:${col};--surface:${bg}">` + names.map(n => `<div style="text-align:center;font:9px sans-serif">${m.icon(n,'x')}<br>${n.slice(0,7)}</div>`).join('') + '</div>'
  document.body.innerHTML = '<style>svg.x{width:24px;height:24px}</style>' + row('#f3f6f4','#1d2a26') + row('#151a19','#e3ebe8') + `<div style="display:flex;gap:10px;padding:10px;background:#f3f6f4;color:#1d2a26">` + names.map(n => m.icon(n,'y')).join('') + '</div><style>svg.y{width:14px;height:14px}</style>'
})
await p.screenshot({ path: process.argv[2] }); await b.close()
