// Hkline 手机网页版 · 机型适配检查：按几台目标手机的视口把四个整页与常用弹层各走一遍，
// 自动查「整页横向溢出」「元素出了屏幕右沿」「本该一行写完的字被截成省略号」，并逐张截图供肉眼看。
//   node scripts/m-devices.mjs [地址] [机型…]
//   默认地址 http://localhost:5190/web/m/（先 npm run build && npx vite preview --port 5190）
//   截图落在 /tmp/m-devices/<机型>/
// 机型（2026-10-03 用户点名适配 iPhone 15 Pro Max 与华为 nova 16，16 Pro 是一直以来的基准）：
//   iPhone 16 Pro       402×874  DPR 3
//   iPhone 15 Pro Max   430×932  DPR 3（Safari）
//   nova 16             1280×2800 物理像素、鸿蒙 7 自带浏览器（ArkWeb，Chromium 系）。默认显示大小下
//                       CSS 宽约 366（密度 3.5）；调大「显示大小」会更窄，所以再跑一档 360 兜住。
//                       浏览器里有地址栏与底部工具栏，可视高度按 720 算（比加到桌面后的全屏更紧）。
// 有 ✗ 退出码 1。
import { chromium } from 'playwright-core'
import { mkdirSync } from 'node:fs'

const URL_ = process.argv[2] || 'http://localhost:5190/web/m/'
const ONLY = process.argv.slice(3)
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const IOS_UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 26_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.6 Mobile/15E148 Safari/604.1'
const HM_UA = 'Mozilla/5.0 (Phone; OpenHarmony 6.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36 ArkWeb/6.0.0.0 Mobile HuaweiBrowser/16.0.0.300'
const DEVICES = [
  { id: 'iPhone16Pro', w: 402, h: 874, dpr: 3, ua: IOS_UA },
  { id: 'iPhone15ProMax', w: 430, h: 932, dpr: 3, ua: IOS_UA },
  { id: 'nova16', w: 366, h: 720, dpr: 3.5, ua: HM_UA },
  { id: 'nova16-大字', w: 360, h: 720, dpr: 3.556, ua: HM_UA },
].filter(d => !ONLY.length || ONLY.includes(d.id))
const sleep = ms => new Promise(r => setTimeout(r, ms))
let bad = 0

// 在页面里查：横向溢出、出右沿的可见元素、被省略号截掉的单行字
const PROBE = () => {
  const W = innerWidth, out = [], clipped = []
  const name = el => (el.id ? '#' + el.id : el.tagName.toLowerCase()) + (typeof el.className === 'string' && el.className ? '.' + el.className.trim().split(/\s+/).slice(0, 2).join('.') : '')
  const scrollsX = el => { for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) { const s = getComputedStyle(p); if (/(auto|scroll|hidden|clip)/.test(s.overflowX)) return true } return false }
  const visible = el => { const s = getComputedStyle(el); if (s.visibility === 'hidden' || s.display === 'none' || +s.opacity === 0) return false; const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0 && r.bottom > 0 && r.top < innerHeight }
  for (const el of document.body.querySelectorAll('*')) {
    if (!visible(el)) continue
    const r = el.getBoundingClientRect()
    if ((r.right > W + 0.5 || r.left < -0.5) && !scrollsX(el) && !el.closest('[aria-hidden="true"]')) out.push(`${name(el)} [${Math.round(r.left)}–${Math.round(r.right)}]`)
    const s = getComputedStyle(el)
    if (s.textOverflow === 'ellipsis' && el.scrollWidth > el.clientWidth + 1 && el.textContent.trim()) clipped.push(`${name(el)}「${el.textContent.trim().slice(0, 24)}」`)
  }
  return { overflow: document.documentElement.scrollWidth - W, out: [...new Set(out)].slice(0, 12), clipped: [...new Set(clipped)].slice(0, 12) }
}

const browser = await chromium.launch({ executablePath: CHROME, headless: true })
for (const d of DEVICES) {
  const dir = `/tmp/m-devices/${d.id}`; mkdirSync(dir, { recursive: true })
  const ctx = await browser.newContext({ viewport: { width: d.w, height: d.h }, deviceScaleFactor: d.dpr, isMobile: true, hasTouch: true, userAgent: d.ua, locale: 'zh-CN', timezoneId: 'Asia/Shanghai' })
  const p = await ctx.newPage()
  const errs = []
  p.on('pageerror', e => errs.push(e.message))
  const check = async (label) => {
    const r = await p.evaluate(PROBE)
    await p.screenshot({ path: `${dir}/${label}.png`, scale: "css" })
    const pass = r.overflow <= 0 && !r.out.length
    if (!pass) bad++
    console.log(`${pass ? '✓' : '✗'} ${d.id} · ${label}${r.overflow > 0 ? ` 整页横溢 ${r.overflow}px` : ''}${r.out.length ? ' 出界：' + r.out.join('；') : ''}${r.clipped.length ? '  省略号：' + r.clipped.join('；') : ''}`)
  }
  const closeSheet = () => p.evaluate(() => (document.querySelector('.m-sheet-scrim') || document.querySelector('.m-pop-scrim'))?.click())
  await p.goto(URL_ + '#chart'); await p.waitForSelector('.cp-gear'); await sleep(5000)
  await check('行情')
  for (const [label, fn] of [
    ['周期更多', () => document.querySelector('.cp-more')?.click()],
    ['分析面板', () => [...document.querySelectorAll('.cp-tail')].find(b => b.textContent.includes('分析'))?.click()],
    ['图表设置', () => document.querySelector('.cp-gear')?.click()],
  ]) { await p.evaluate(fn); await sleep(700); await check(label); await closeSheet(); await sleep(500) }
  for (const pg of ['favorites', 'sectors', 'me']) { await p.evaluate(h => { location.hash = h }, pg); await sleep(2500); await check(pg) }
  await p.evaluate(() => { location.hash = 'chart' }); await sleep(1500)
  await p.evaluate(() => document.querySelector('[data-act="search"]')?.click()); await sleep(1200); await check('搜索')
  if (errs.length) { bad++; console.log(`✗ ${d.id} 页面报错：${errs.slice(0, 3).join(' | ')}`) }
  await ctx.close()
}
await browser.close()
console.log(bad ? `✗ ${bad} 处不过` : '✓ 全过')
process.exit(bad ? 1 : 0)
