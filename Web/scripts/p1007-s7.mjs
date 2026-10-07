// Hkline Web · 2026-10-07 压测与回归 第七节：技术指标提醒端到端（本机后端）
//   本机起一套 kanpan-api（serve + worker）和独立的 PostgreSQL，网页预览的账号 / 同步 / 日志接口转到本机，
//   行情类接口（/v1/market/*）照旧走线上。临时账号只建在本机库里，跑完在页面上注销。
//   在网页「创建提醒」里于 BTCUSDT 1m 上各建一条：均线交叉（EMA2 上穿 SMA3）、RSI(2) 上穿 50、收盘突破前 2 根最高。
//   每条：只响一次（网页与服务端两条判定路只算一次）、侧栏从「列表」挪进「日志」、服务端 alert_watches 不再 active、alert_log 恰一行。
//   跑法：P_URL=http://localhost:5307/web/ P_LOCAL_API=http://127.0.0.1:8899 P_PSQL='docker exec -i kanpan-e2e-pg psql -U e2e -d kanpan -tAq' node scripts/p1007-s7.mjs [最长分钟=20]
import crypto from 'node:crypto'
import { execSync } from 'node:child_process'
import { URL_, BASE, open, waitCells, sleep, ok, note, flush, setTag, shot, DATA, browserDown } from './p1007-lib.mjs'

setTag('s7-indicator-alerts')
const MAX_MIN = +(process.argv[2] || 20)
const LOCAL = process.env.P_LOCAL_API || 'http://127.0.0.1:8899'
const PSQL = process.env.P_PSQL
if (!PSQL || !/localhost|127\.0\.0\.1/.test(URL_)) { console.error('只在本机预览 + 本机后端上跑'); process.exit(2) }
// 本机 Docker 虚拟机偶尔断一下（10-07 两次）：查库失败隔 5 s 重试，最多 2 分钟
const sql = q => { for (let k = 0; ; k++) { try { return execSync(PSQL, { input: q, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }).trim() } catch (e) { if (k >= 24) throw e; execSync('sleep 5') } } }

const cells = [{ symbol: 'BTCUSDT', iv: '1m' }]
const state = { ...BASE, layout: '1', cells, panel: 'alerts', meSection: 'account', ind: { ma: true, ema: true, boll: false, vol: true, subs: ['rsi'] } }
const { ctx, page, errs } = await open(state)
// 账号、同步、提醒日志转到本机后端（后注册的路由先匹配）；/v1/market/* 不动，照旧由 corsShim 转线上
const hits = { local: 0, byPath: {} }
// 账号 / 同步 / 日志走同源相对路径（/v1/...）：本机预览的 vite preview 会把它代理到线上，所以同源与线上域名两种写法都要拦
await ctx.route(/^(https:\/\/kanpan\.43-160-232-253\.sslip\.io|http:\/\/(localhost|127\.0\.0\.1):\d+)\/v1\/(?!market\/)/, async route => {
  const q = route.request()
  const cors = { 'access-control-allow-origin': q.headers().origin || '*', 'access-control-allow-credentials': 'true', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS' }
  if (q.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors }).catch(() => {})
  const u = new URL(q.url()); hits.local++; hits.byPath[u.pathname] = (hits.byPath[u.pathname] || 0) + 1
  try { const r = await route.fetch({ url: LOCAL + u.pathname + u.search, timeout: 20000 }); await route.fulfill({ response: r, headers: { ...r.headers(), ...cors } }) } catch { await route.abort().catch(() => {}) }
})
await page.reload({ waitUntil: 'domcontentloaded' })
// 保险：先从页面同源发一条非行情 /v1 请求，必须落到本机后端（拦不住就停，绝不在线上注册）
const canary0 = hits.local
const canary = await page.evaluate(() => fetch('/v1/auth/canary-s7', { cache: 'no-store' }).then(r => r.status, () => -1))
if (hits.local === canary0) { console.error('非行情 /v1 请求没有转到本机后端（status ' + canary + '），停止，不注册'); await browserDown(); process.exit(3) }
ok('7.0', '单格 BTCUSDT 1m 出图', await waitCells(page, 1, 100, 60000))

// ───────── 7.1 注册临时账号（只在本机库里）
const user = 'e2e_' + crypto.randomBytes(4).toString('hex'), pass = 'T' + crypto.randomBytes(9).toString('hex') + '9'
await page.goto(URL_ + '#me', { waitUntil: 'domcontentloaded' })
await page.click('[data-me="account"]').catch(() => {})
await page.click('[data-auth="register"]')
await page.fill('#acctUser', user); await page.fill('#acctPass', pass)
await page.click('#acctGo')
const signed = await page.waitForSelector('.acct-name', { timeout: 20000 }).then(() => true, () => false)
const uid = signed ? sql(`SELECT id FROM account_users WHERE email='${user}'`) : ''
ok('7.1', '本机后端注册临时账号并登录', signed && /^[0-9a-f-]{36}$/.test(uid), `用户 id ${uid.slice(0, 8)}…，本机接口命中 ${hits.local} 次`)

// ───────── 7.2 在「创建提醒」里建三条 1m 指标提醒
await page.goto(URL_ + '#chart', { waitUntil: 'domcontentloaded' })
await waitCells(page, 1, 100, 60000)
if (!(await page.$('#aNew'))) await page.click('#rail [data-panel="alerts"]')
const make = async (kind, fill) => {
  await page.click('#aNew'); await page.waitForSelector('#aKind')
  await page.click(`#aKind [data-k="${kind}"]`)
  await page.click('#aIv [data-iv="1m"]')
  await fill()
  await page.click('#aDir [data-dir="up"]')
  const phrase = await page.textContent('#aPreview')
  await page.click('#aOk')
  await sleep(400)
  return phrase
}
const phrases = []
phrases.push(await make('ma_cross', async () => { await page.click('[data-ma-fast="ema"]'); await page.fill('#afastN', '2'); await page.click('[data-ma-slow="sma"]'); await page.fill('#aslowN', '3') }))
phrases.push(await make('rsi_level', async () => { await page.fill('#aRsiN', '2'); await page.fill('#aLevel', '50') }))
phrases.push(await make('bar_breakout', async () => { await page.fill('#aBars', '2') }))
const local = await page.evaluate(() => JSON.parse(localStorage.getItem('hkline-web-v1')).alerts.filter(a => a.kind === 'condition').map(a => ({ id: a.id, rule: a.rule, armedAt: a.armedAt, status: a.status })))
ok('7.2', '三条指标提醒建好（预览文案）', local.length === 3, phrases.join(' / '))
const want = [
  { kind: 'ma_cross', interval: '1m', fast: { ma: 'ema', period: 2 }, slow: { ma: 'sma', period: 3 }, direction: 'up' },
  { kind: 'rsi_level', interval: '1m', period: 2, level: 50, direction: 'up' },
  { kind: 'bar_breakout', interval: '1m', bars: 2, direction: 'up' },
]
ok('7.2', '本机存下的 rule 与契约逐字一致', want.every(w => local.some(a => JSON.stringify(a.rule) === JSON.stringify(w))), local.map(a => JSON.stringify(a.rule)).join(' '))
// 推上去：服务端 alert_watches 里三条 active、rule 原样
const watch = () => sql(`SELECT alert_id||'|'||status||'|'||coalesce(rule::text,'') FROM alert_watches WHERE user_id='${uid}' AND kind='condition' ORDER BY alert_id`).split('\n').filter(Boolean).map(l => { const [id, status, ...rule] = l.split('|'); return { id, status, rule: rule.join('|') } })
const sameRule = (a, b) => { const k = o => JSON.stringify(o, Object.keys(o).sort()); try { const x = JSON.parse(a); return k(x) === k(b) && JSON.stringify(x.fast ?? null) === JSON.stringify(b.fast ?? null) } catch { return false } }
let w0 = []
for (let k = 0; k < 30 && w0.filter(x => x.status === 'active').length < 3; k++) { await sleep(1000); w0 = watch() }
ok('7.2', '同步到服务端：alert_watches 三条 active，rule 与本机一致', w0.length === 3 && w0.every(x => x.status === 'active') && want.every(r => w0.some(x => sameRule(x.rule, r))), w0.map(x => `${x.id.split('/').pop().slice(0, 8)}:${x.status}`).join(' '))
await shot(page, 's7-三条指标提醒已建')

// ───────── 7.3 等它们收盘时响：每条只响一次
const shortId = id => id.split('/').pop()
const fires = []
await page.exposeFunction('__s7fired', (who, id, at) => { fires.push([at, who, id]) })
await page.evaluate(ids => {
  // 网页这一侧：盯着本机表里每条从 active 变没（本机判响走 fire()，服务端判响走同步下来的那一笔）
  window.__s7ids = ids
  const seen = new Set()
  setInterval(() => {
    const now = JSON.parse(localStorage.getItem('hkline-web-v1')).alerts.filter(a => a.kind === 'condition' && a.status === 'active').map(a => a.id)
    for (const id of window.__s7ids) if (!now.includes(id) && !seen.has(id)) { seen.add(id); window.__s7fired('gone', id, Date.now()) }
  }, 500)
}, local.map(a => a.id))
const t0 = Date.now()
const logRows = () => sql(`SELECT alert_id||'|'||fired_at||'|'||coalesce(fired_price::text,'')||'|'||title FROM alert_log WHERE user_id='${uid}' ORDER BY fired_at`).split('\n').filter(Boolean).map(l => { const [id, at, px, ...title] = l.split('|'); return { id, at: +at, px: +px, title: title.join('|') } })
let rows = [], w1 = []
while (Date.now() - t0 < MAX_MIN * 6e4) {
  await sleep(5000)
  rows = logRows()
  if (local.every(a => rows.some(r => r.id.endsWith(a.id)))) break
}
const waited = Math.round((Date.now() - t0) / 1e3)
// 全部响过之后再多等两根收盘：不许再响第二次
await sleep(125000)
rows = logRows(); w1 = watch()
const perAlert = local.map(a => ({ id: a.id, kind: a.rule.kind, n: rows.filter(r => r.id.endsWith(a.id)).length, row: rows.find(r => r.id.endsWith(a.id)), watch: w1.find(x => x.id.endsWith(a.id)) }))
DATA.alerts = { local, w0, w1, rows, perAlert, fires, waited, hits }
for (const p of perAlert) {
  ok('7.3', `${p.kind}：alert_log 恰好一行（两条判定路只记一次），多等两根收盘也没再响`, p.n === 1, p.row ? `${new Date(p.row.at + 8 * 36e5).toISOString().slice(11, 19)} 响，价 ${p.row.px}，「${p.row.title}」，共 ${p.n} 行` : `没响（等了 ${waited} s）`)
  ok('7.3', `${p.kind}：服务端 alert_watches 状态一致（fired 或已删，不再 active）`, !p.watch || p.watch.status !== 'active', p.watch ? p.watch.status : '行已删（响完删）')
}
const gone = fires.filter(f => f[1] === 'gone')
ok('7.4', '网页本机表：三条都离开了「在等」（各一次）', local.every(a => gone.filter(g => g[2] === a.id).length === 1), gone.map(g => `${shortId(g[2]).slice(0, 8)} @${new Date(g[0] + 8 * 36e5).toISOString().slice(11, 19)}`).join(' '))
const listLeft = await page.$$eval('.alert-row', els => els.length).catch(() => -1)
ok('7.4', '侧栏「列表」空了', listLeft === 0, `还剩 ${listLeft} 行`)
await page.click('[data-atab="log"]')
await page.waitForFunction(() => document.querySelectorAll('.alog-row').length >= 3, null, { timeout: 15000 }).catch(() => {})
const logTxt = await page.$$eval('.alog-row', els => els.map(e => e.textContent.replace(/\s+/g, ' ').trim()))
ok('7.4', '侧栏「日志」里三条各一行', logTxt.length === 3, logTxt.join(' ｜ '))
await shot(page, 's7-响完挪进日志')

// ───────── 7.5 在页面上注销临时账号，库里这个用户与其提醒、日志都没了
await page.goto(URL_ + '#me', { waitUntil: 'domcontentloaded' })
await page.click('[data-me="account"]').catch(() => {})
await page.fill('#closePass', pass)
await page.click('#closeGo'); await sleep(300); await page.click('#closeGo')
const out = await page.waitForSelector('#acctForm', { timeout: 20000 }).then(() => true, () => false)
const left = sql(`SELECT (SELECT count(*) FROM account_users WHERE id='${uid}')||'|'||(SELECT count(*) FROM alert_log WHERE user_id='${uid}')||'|'||(SELECT count(*) FROM alert_watches WHERE user_id='${uid}')`)
ok('7.5', '页面上注销临时账号：库里账号、提醒、日志全没了', out && left === '0|0|0', `账号|日志|提醒 = ${left}`)
note('7.6', '本机接口命中', JSON.stringify(hits.byPath))
ok('7.6', '整段控制台无报错', !errs.length, errs.slice(0, 3).join(' | '))
flush()
await browserDown()
