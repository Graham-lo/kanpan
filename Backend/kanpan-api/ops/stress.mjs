#!/usr/bin/env node
// kanpan-api 有界负载（2026-09-29 网页版深度压测 C 路）。
//
// 用户规模只有几个人（上限约 10 人），这里按「几倍用户规模」打：每个场景阶梯加并发
// （默认 2 → 5 → 10 → 20），最后一档持续到给定时长。每 10 秒一个窗口，窗口里错误率超过 1%
// 或 p95 超过 2 秒立刻停下（先查原因，别硬打）。不是打垮它：线上有人在用。
//
//   node ops/stress.mjs meta|heat|history|sector|footprint|seconds [--secs 150] [--stages 2,5,10,20]
//   KANPAN_STRESS_USER=… KANPAN_STRESS_PASSWORD=… node ops/stress.mjs sync|auth|search
//
// 账号密码只从环境变量读，别写进任何文件。输出最后一行是整段的 JSON 汇总。
import { webcrypto } from 'node:crypto'
globalThis.crypto ??= webcrypto // VPS 上是 Node 18，全局 crypto 不一定有

const BASE = process.env.KANPAN_STRESS_BASE || 'https://kanpan.43-160-232-253.sslip.io'
const args = process.argv.slice(2)
const scenario = args[0]
const opt = (name, dflt) => { const i = args.indexOf('--' + name); return i >= 0 ? args[i + 1] : dflt }
const SECS = +opt('secs', 150)
const STAGES = opt('stages', '2,5,10,20').split(',').map(Number)
const STAGE_SECS = +opt('stage-secs', 20)
const HEADERS = { 'accept-encoding': 'gzip, br', 'user-agent': 'kanpan-stress-c/1' }

const pct = (xs, q) => { if (!xs.length) return null; const s = [...xs].sort((a, b) => a - b); return Math.round(s[Math.min(s.length - 1, Math.floor(q * s.length))]) }
const uuid = () => crypto.randomUUID()
const pick = xs => xs[Math.floor(Math.random() * xs.length)]
const jitter = span => span - Math.floor(Math.random() * span / 4 / 60_000) * 60_000 // 少掉至多四分之一、按整分钟
const sleep = ms => new Promise(r => setTimeout(r, ms))

// ------------------------------------------------------------------ 计量
class Meter {
  constructor() { this.reset() ; this.all = { ms: [], ttfb: [], n: 0, err: 0, refused: 0, codes: {}, bytes: 0 } }
  reset() { this.win = { ms: [], ttfb: [], n: 0, err: 0, refused: 0, codes: {} } }
  add(r) {
    for (const t of [this.win, this.all]) {
      t.n++; t.codes[r.code] = (t.codes[r.code] || 0) + 1
      if (r.refused) t.refused++
      else if (r.error) t.err++
      else { t.ms.push(r.ms); t.ttfb.push(r.ttfb) }
    }
    this.all.bytes += r.bytes || 0
  }
  static stat(t) { return { n: t.n, ok: t.ms.length, err: t.err, refused: t.refused, errRate: t.n ? +(t.err / t.n * 100).toFixed(2) : 0, p50: pct(t.ms, .5), p95: pct(t.ms, .95), p99: pct(t.ms, .99), ttfb95: pct(t.ttfb, .95), codes: t.codes } }
}

async function timed(path, init = {}, expect = r => r.status === 200, refusedIf = () => false) {
  const t0 = performance.now()
  let status = 0, bytes = 0, body = null, ttfb = 0
  try {
    const r = await fetch(BASE + path, { ...init, headers: { ...HEADERS, ...(init.headers || {}) }, signal: AbortSignal.timeout(30_000) })
    ttfb = performance.now() - t0
    status = r.status
    const txt = await r.text(); bytes = txt.length
    try { body = JSON.parse(txt) } catch { body = txt }
  } catch (e) { status = e?.name === 'TimeoutError' ? 'timeout' : 'neterr' }
  const ms = performance.now() - t0
  const refused = typeof status === 'number' && refusedIf(status, body)
  const ok = typeof status === 'number' && expect({ status, body })
  return { ms, ttfb, code: status, bytes, body, error: !ok && !refused, refused }
}

// ------------------------------------------------------------------ 场景
const PRICES = {}
async function prices() {
  for (const b of ['BTC', 'ETH', 'SOL']) {
    // 币安合约 REST 在美国机房回 451，那边跑时退到 OKX 的现货价（只拿来定价格范围，差一点无所谓）
    try { PRICES[b] = +(await (await fetch(`https://fapi.binance.com/fapi/v1/ticker/price?symbol=${b}USDT`)).json()).price } catch {}
    if (!(PRICES[b] > 0)) PRICES[b] = +(await (await fetch(`https://www.okx.com/api/v5/market/ticker?instId=${b}-USDT`)).json()).data[0].last
  }
}
let META_SYMBOLS = []
const LADDER = [5_000, 10_000, 30_000, 60_000, 150_000, 300_000, 900_000]
const STEPS = { BTC: 100, ETH: 1, SOL: 0.1 }

const scenarios = {
  async meta() {
    if (!META_SYMBOLS.length) META_SYMBOLS = Object.keys((await (await fetch(BASE + '/v1/market/meta', { headers: HEADERS })).json()).data)
    const batch = Array.from({ length: 60 }, () => pick(META_SYMBOLS))
    return timed(`/v1/market/meta?symbols=${[...new Set(batch)].join(',')}`)
  },
  async sector() { return timed('/v1/market/sector-history') },
  async heat() {
    const b = pick(['BTC', 'ETH', 'SOL']), px = PRICES[b], now = Date.now()
    const span = pick([3_600_000, 6 * 3_600_000, 24 * 3_600_000])
    const from = Math.floor((now - span) / 5000) * 5000, to = Math.ceil(now / 5000) * 5000
    const hint = pick(LADDER)
    const q = [`base=${b}`, `from=${from}`, `to=${to}`, `step=${STEPS[b]}`, `bucketMs=${hint}`]
    if (Math.random() < .5) q.push(`around=${px.toPrecision(6)}`, `pct=${pick([5, 8, 12])}`)
    else { const w = pick([.02, .04, .08]); q.push(`lo=${(px * (1 - w)).toPrecision(6)}`, `hi=${(px * (1 + w)).toPrecision(6)}`) }
    return timed('/v1/market/orderflow/heat?' + q.join('&'))
  },
  // 一个客户端的一轮：先取最近 6 小时，封顶了就按 nextBefore 往前翻一页（和网页 feed.ts 同一个写法）
  async history(ctx) {
    const b = pick(['BTC', 'ETH', 'SOL']), now = Date.now()
    if (ctx.next && Math.random() < .7) {
      const { base, before } = ctx.next; ctx.next = null
      const r = await timed(`/v1/market/orderflow/history?base=${base}&from=${before - 6 * 3_600_000}&to=${before}&limit=5000&minLifeMs=300000`)
      return r
    }
    const r = await timed(`/v1/market/orderflow/history?base=${b}&from=${now - 6 * 3_600_000}&to=${now}&limit=5000`)
    const nb = r.body?.data?.nextBefore
    if (nb) ctx.next = { base: b, before: nb }
    return r
  },
  // 2026-10-07 足迹图 / 秒线历史：起点按分钟随机错开（同样的请求 20 秒内合成一次读库，不错开就只是在打缓存）；
  // 5% 故意超过上限（足迹 24 小时、秒线 6 小时），要回 400 而不是 5xx。
  async footprint() {
    const b = pick(['BTC', 'ETH', 'SOL']), now = Date.now()
    const over = Math.random() < .05
    const span = over ? 25 * 3_600_000 : jitter(pick([3_600_000, 4 * 3_600_000, 24 * 3_600_000]))
    const to = now - Math.floor(Math.random() * 120) * 60_000
    return timed(`/v1/market/orderflow/footprint?symbol=${b}USDT&from=${to - span}&to=${to}`, {}, r => over ? r.status === 400 : r.status === 200)
  },
  async seconds() {
    const b = pick(['BTC', 'ETH', 'SOL']), now = Date.now()
    const over = Math.random() < .05
    const span = over ? 7 * 3_600_000 : jitter(pick([30 * 60_000, 3_600_000, 6 * 3_600_000]))
    const to = now - Math.floor(Math.random() * 120) * 60_000
    return timed(`/v1/market/klines/seconds?symbol=${b}USDT&from=${to - span}&to=${to}`, {}, r => over ? r.status === 400 : r.status === 200)
  },
}

// ------------------------------------------------------------------ 账号：两类设备各一条会话
const DEVICES = {}
function device(kind) { return DEVICES[kind] ||= { id: uuid(), name: `stress-c-${kind}`, secret: [...crypto.getRandomValues(new Uint8Array(24))].map(x => x.toString(16).padStart(2, '0')).join(''), kind } }
async function login(kind) {
  const user = process.env.KANPAN_STRESS_USER, password = process.env.KANPAN_STRESS_PASSWORD
  if (!user || !password) throw new Error('KANPAN_STRESS_USER / KANPAN_STRESS_PASSWORD 没给')
  const r = await timed('/v1/auth/login', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ username: user, password, device: device(kind) }) }, r => r.status === 200)
  if (r.error) throw new Error(`login ${kind} ${r.code} ${JSON.stringify(r.body).slice(0, 200)}`)
  return { kind, ...r.body.data, loginMs: r.ms }
}
async function refresh(s) {
  const r = await timed('/v1/auth/refresh', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ refreshToken: s.refreshToken, requestId: uuid(), device: device(s.kind) }) },
    r => r.status === 200, st => st === 429)
  if (r.code === 200) { s.accessToken = r.body.data.accessToken; s.refreshToken = r.body.data.refreshToken }
  return r
}
const authed = (s, path, init = {}) => timed(path, { ...init, headers: { authorization: 'Bearer ' + s.accessToken, 'content-type': 'application/json', ...(init.headers || {}) } })

// 压测画线：固定 12 个对象（每个设备 6 个），反复 patch 同一批；base_revision 给 0（字段级按时间戳后写赢，不会冲突）
const KINDS = ['trend', 'rectangle', 'ray']
function drawingOp(s, slot) {
  const kind = KINDS[slot % KINDS.length]
  const t = Date.now()
  return {
    id: uuid(), collection: 'drawings', objectId: `binance/usd_m/BTCUSDT/stress-c-${s.kind}-${slot}`, deviceId: DEVICES[s.kind].id,
    baseRevision: 0, generation: 0, timestamp: t, logical: 0, action: 'patch', importBatch: null,
    fields: { kind, symbol: 'BTCUSDT', market: 'usd_m', venue: 'binance', anchors: [{ t: t - 3_600_000, p: 80000 + Math.random() * 1000 }, { t, p: 81000 + Math.random() * 1000 }] },
  }
}

// ------------------------------------------------------------------ 驱动
async function drive(name, fn, ctxFor = () => ({})) {
  const meter = new Meter()
  const stages = []
  let stop = null, workers = 0, alive = true
  const start = Date.now()
  const plan = STAGES.map((c, i) => ({ c, until: i < STAGES.length - 1 ? (i + 1) * STAGE_SECS * 1000 : SECS * 1000 }))
  let stageIdx = 0, stageMeter = new Meter()
  const spawn = async id => {
    const ctx = ctxFor(id)
    while (alive && id < plan[stageIdx].c) {
      const r = await fn(ctx, id)
      meter.add(r); stageMeter.add(r)
    }
  }
  const tick = setInterval(() => {
    const w = Meter.stat(meter.win); meter.reset()
    const el = Math.round((Date.now() - start) / 1000)
    console.log(JSON.stringify({ t: el, c: plan[stageIdx].c, ...w }))
    if (w.n >= 20 && (w.errRate > 1 || w.p95 > 2000)) { stop = `窗口 t=${el}s c=${plan[stageIdx].c}: errRate ${w.errRate}% p95 ${w.p95} ms`; alive = false }
  }, 10_000)
  const pool = []
  while (alive) {
    const el = Date.now() - start
    if (el >= plan[stageIdx].until) {
      stages.push({ c: plan[stageIdx].c, ...Meter.stat(stageMeter.all) }); stageMeter = new Meter()
      if (stageIdx === plan.length - 1) break
      stageIdx++
    }
    while (workers < plan[stageIdx].c) pool.push(spawn(workers++))
    await sleep(250)
  }
  if (!alive && stageMeter.all.n) stages.push({ c: plan[stageIdx].c, partial: true, ...Meter.stat(stageMeter.all) })
  alive = false; clearInterval(tick)
  await Promise.allSettled(pool)
  const out = { scenario: name, secs: Math.round((Date.now() - start) / 1000), stop, stages, total: Meter.stat(meter.all), mb: +(meter.all.bytes / 1e6).toFixed(1) }
  console.log('SUMMARY ' + JSON.stringify(out))
  return out
}

async function main() {
  await prices()
  if (scenarios[scenario]) return drive(scenario, (ctx) => scenarios[scenario](ctx))
  if (scenario === 'sync') {
    const sessions = [await login('desktop'), await login('tablet')]
    // 每条会话一个续期器：每 5 秒轮换一次（会话限速 30 次/分），工作者拿当下的 access
    let running = true
    const refresher = sessions.map(async s => { const m = new Meter(); while (running) { m.add(await refresh(s)); await sleep(5000) } return Meter.stat(m.all) })
    const res = await drive('sync', async (ctx, id) => {
      const s = sessions[id % 2]
      const roll = Math.random()
      if (roll < .45) {
        const ops = Array.from({ length: 1 + Math.floor(Math.random() * 3) }, () => drawingOp(s, Math.floor(Math.random() * 6)))
        return authed(s, '/v1/sync/operations', { method: 'POST', body: JSON.stringify({ operations: ops }), headers: { 'Idempotency-Key': uuid() } })
      }
      if (roll < .85) {
        const r = await authed(s, '/v1/sync/changes?cursor=' + (ctx.cursor ?? 0))
        const c = r.body?.data?.cursor; if (typeof c === 'number') ctx.cursor = c
        return r
      }
      return authed(s, '/v1/sync/bootstrap?collection=drawings&prefix=binance/usd_m/BTCUSDT/stress-c-')
    })
    running = false
    res.refresh = await Promise.all(refresher)
    res.logins = sessions.map(s => Math.round(s.loginMs))
    console.log('SUMMARY2 ' + JSON.stringify(res))
    return
  }
  if (scenario === 'cleanup') {
    // 删掉压测画线（12 个对象），会话退掉
    for (const kind of ['desktop', 'tablet']) {
      const s = await login(kind)
      const ops = Array.from({ length: 6 }, (_, slot) => ({ ...drawingOp(s, slot), action: 'delete', fields: {} }))
      const r = await authed(s, '/v1/sync/operations', { method: 'POST', body: JSON.stringify({ operations: ops }), headers: { 'Idempotency-Key': uuid() } })
      const out = await authed(s, '/v1/auth/logout', { method: 'POST', body: '{}' })
      console.log(kind, 'delete', r.code, 'logout', out.code)
    }
    return
  }
  if (scenario === 'auth') {
    // 登录限速是按 IP 的 60 次/分，网页版另两路压测也从这台机器登录，所以这里只用它的六分之一：
    // 每 6 秒一次登录（两类设备轮流），其间每条会话每 3 秒续期一次（会话限速 30 次/分的三分之二）
    const m = { login: new Meter(), refresh: new Meter(), me: new Meter() }
    const t0 = Date.now(); const sessions = {}
    let i = 0
    while (Date.now() - t0 < SECS * 1000) {
      const kind = i++ % 2 ? 'tablet' : 'desktop'
      try { const s = await login(kind); sessions[kind] = s; m.login.add({ ms: s.loginMs, ttfb: s.loginMs, code: 200 }) } catch (e) { m.login.add({ code: String(e.message).split(' ')[2], error: true }); console.log(e.message) }
      for (let k = 0; k < 2; k++) {
        for (const s of Object.values(sessions)) { m.refresh.add(await refresh(s)); m.me.add(await authed(s, '/v1/auth/me')) }
        await sleep(3000)
      }
    }
    const out = Object.fromEntries(Object.entries(m).map(([k, v]) => [k, Meter.stat(v.all)]))
    console.log('SUMMARY ' + JSON.stringify({ scenario: 'auth', secs: SECS, ...out }))
    return
  }
  if (scenario === 'search') {
    // 找相似：一个账号同一时刻只准一条在跑、一小时最多 20 条（search.rs）。所以这里是串行：
    // 发起 → 每秒问一次状态 → 完成后取结果；同时并发再发一条，确认第二条被明确拒绝（429 search_busy）而不是挂住。
    const s = await login('desktop')
    const combos = []
    for (const iv of ['15m', '1h', '4h']) for (const bars of [32, 48, 64]) combos.push({ iv, bars, sym: pick(['BTCUSDT', 'ETHUSDT', 'SOLUSDT']) })
    const ms = { '15m': 900_000, '1h': 3_600_000, '4h': 14_400_000 }
    const limit = +opt('count', combos.length)
    const rows = []
    for (const c of combos.slice(0, limit)) {
      const step = ms[c.iv], end = Math.floor(Date.now() / step) * step, start = end - c.bars * step
      const range = { venue: 'binance', market: 'usd_m', symbol: c.sym, interval: c.iv, start, end, bars: c.bars }
      const t0 = performance.now()
      const r = await authed(s, '/v1/native-review/searches', { method: 'POST', body: JSON.stringify({ range, cutoff: Date.now(), scope: 'history' }), headers: { 'Idempotency-Key': uuid() } })
      if (r.code !== 200) { rows.push({ ...c, start: r.code, body: JSON.stringify(r.body).slice(0, 160) }); console.log(JSON.stringify(rows.at(-1))); continue }
      const id = r.body.data.id
      const dup = await authed(s, '/v1/native-review/searches', { method: 'POST', body: JSON.stringify({ range, cutoff: Date.now(), scope: 'history' }), headers: { 'Idempotency-Key': uuid() } })
      let st = null, polls = 0
      while (polls++ < 120) { await sleep(1000); const q = await authed(s, `/v1/native-review/searches/${id}`); st = q.body?.data; if (st && !['queued', 'running'].includes(st.status)) break }
      const done = performance.now() - t0
      const res = await authed(s, `/v1/native-review/searches/${id}/results`)
      rows.push({ ...c, startMs: Math.round(r.ms), secondStart: `${dup.code} ${dup.body?.error?.code ?? ''}`, status: st?.status, error: st?.error, checked: st?.checked, total: st?.total, doneMs: Math.round(done), results: res.body?.data?.items?.length, resultsMs: Math.round(res.ms), at: new Date().toISOString() })
      console.log(JSON.stringify(rows.at(-1)))
    }
    console.log('SUMMARY ' + JSON.stringify({ scenario: 'search', rows }))
    return
  }
  throw new Error('未知场景 ' + scenario)
}
main().catch(e => { console.error(e); process.exit(1) })
