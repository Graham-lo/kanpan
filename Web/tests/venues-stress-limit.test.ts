/* 压测 · 一家一把限流器（market/limit.ts Gate）：几百个并发请求经同一把，任意滚动窗口都不超预算；
 * 429 / 403 冷却中途插进来时排队的没有抢跑；直连与网关两道互不影响；排队中换线路时，发出去的地址与记账那一道一致；
 * 行情（venues/http vget）与订单流（orderflow/feed getJSON）共用一把；系统时钟往回拨不把一家锁上几小时。
 * 量化断言全按假时钟算（vi.useFakeTimers），不看墙上时钟。 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { Gate, RateLimited, admit, gateOf, noteStatus, resetLimits } from '../src/market/limit'
import { vget, vpost } from '../src/venues/http'
import { getJSON } from '../src/orderflow/feed'
import { hlWeight, HL } from '../src/venues/hyperliquid'
import { S } from '../src/market/state'
import '../src/venues'

interface Sent { t: number; url: string; cost: number }

/** 任意一个长 windowMs 的滚动窗口里（[t, t + W)）合计的最大值 */
function maxInWindow(sent: Sent[], windowMs: number, pick: (s: Sent) => boolean = () => true): number {
  const xs = sent.filter(pick).sort((a, b) => a.t - b.t)
  let best = 0
  for (let i = 0; i < xs.length; i++) {
    let sum = 0
    for (let j = i; j < xs.length && xs[j].t < xs[i].t + windowMs; j++) sum += xs[j].cost
    best = Math.max(best, sum)
  }
  return best
}

/** 推着假时钟走，直到这批都落地（或到上限） */
async function drain(ps: Promise<unknown>[], stepMs = 50, maxMs = 600_000): Promise<number> {
  let done = 0
  ps.forEach(p => p.then(() => { done++ }, () => { done++ }))
  let spent = 0
  while (done < ps.length && spent < maxMs) { await vi.advanceTimersByTimeAsync(stepMs); spent += stepMs }
  return spent
}

let sent: Sent[] = []
const okFetch = (status = 200) => vi.fn(async (u: string | URL) => {
  sent.push({ t: Date.now(), url: String(u), cost: 1 })
  return new Response(status === 200 ? '{"code":"0","data":[],"retCode":0,"result":{"list":[]}}' : '', { status })
})

beforeEach(() => {
  vi.useFakeTimers({ now: 1_800_000_000_000 })
  sent = []
  S.route = 'direct'
  resetLimits()
})
afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); vi.restoreAllMocks(); resetLimits(); S.route = 'direct' })

describe('每家几百个并发请求：任意窗口不超预算', () => {
  it('OKX 按接口各算：400 个混着 candles / tickers / mark-price / instruments，2 秒窗口各自 ≤ 20 / 10 / 5 / 10', async () => {
    vi.stubGlobal('fetch', okFetch())
    const paths = ['/api/v5/market/candles?instId=BTC-USDT-SWAP&bar=1m', '/api/v5/market/tickers?instType=SWAP', '/api/v5/public/mark-price?instId=BTC-USDT-SWAP', '/api/v5/public/instruments?instType=SWAP']
    const ps = Array.from({ length: 400 }, (_, i) => vget(`https://www.okx.com${paths[i % 4]}&i=${i}`))
    const spent = await drain(ps)
    expect(sent.length).toBe(400)
    const on = (p: string) => (s: Sent) => s.url.includes(p)
    expect(maxInWindow(sent, 2000, on('/market/candles'))).toBeLessThanOrEqual(20)
    expect(maxInWindow(sent, 2000, on('/market/tickers'))).toBeLessThanOrEqual(10)
    expect(maxInWindow(sent, 2000, on('/public/mark-price'))).toBeLessThanOrEqual(5)
    expect(maxInWindow(sent, 2000, on('/public/instruments'))).toBeLessThanOrEqual(10)
    // 不是串着发：最慢的那条接口（mark-price 100 条 / 每 2 秒 5 条）决定总耗时，约 40 秒
    expect(spent).toBeLessThan(45_000)
  })

  it('Bybit 整个 IP 共用：600 个跨接口请求，任意 5 秒 ≤ 300；api.bytick.com 备用主机记在同一把', async () => {
    vi.stubGlobal('fetch', okFetch())
    const urls = ['https://api.bybit.com/v5/market/kline?category=linear', 'https://api.bybit.com/v5/market/tickers?category=linear', 'https://api.bytick.com/v5/market/tickers?category=linear']
    const ps = Array.from({ length: 600 }, (_, i) => vget(`${urls[i % 3]}&i=${i}`).catch(() => null))
    await drain(ps)
    expect(sent.length).toBe(600)
    expect(maxInWindow(sent, 5000)).toBeLessThanOrEqual(300)
  })

  it('Hyperliquid 按权重：60 次 info + 40 次 candleSnapshot（每次 20 + 根数 / 60），任意 60 秒权重 ≤ 600', async () => {
    const bodies: unknown[] = []
    vi.stubGlobal('fetch', vi.fn(async (u: string, init?: RequestInit) => {
      const body = JSON.parse(String(init?.body))
      bodies.push(body)
      sent.push({ t: Date.now(), url: String(u), cost: hlWeight(String(u), body) })
      return new Response('[]', { status: 200 })
    }))
    const now = Date.now()
    const ps = Array.from({ length: 100 }, (_, i) => vpost(HL.info, i % 5 < 3 ? { type: 'metaAndAssetCtxs', i }
      : { type: 'candleSnapshot', req: { coin: 'BTC', interval: '1m', startTime: now - 3000 * 60_000, endTime: now } }))
    await drain(ps, 200, 1_200_000)
    expect(sent.length).toBe(100)
    expect(maxInWindow(sent, 60_000)).toBeLessThanOrEqual(600)
    // 记账按同一张权重表：candleSnapshot 3000 根 = 20 + 50
    expect(hlWeight(HL.info, bodies.find(b => (b as { type: string }).type === 'candleSnapshot'))).toBe(70)
  })

  it('Coinbase 按次：200 个，任意 1 秒 ≤ 5', async () => {
    vi.stubGlobal('fetch', okFetch())
    const ps = Array.from({ length: 200 }, (_, i) => vget(`https://api.coinbase.com/api/v3/brokerage/market/products/BTC-USD/candles?i=${i}`))
    await drain(ps, 20)
    expect(sent.length).toBe(200)
    expect(maxInWindow(sent, 1000)).toBeLessThanOrEqual(5)
  })

  it('后台请求只用一截：Bybit 300 个后台请求任意 5 秒 ≤ 180，前台的照样插得进去', async () => {
    vi.stubGlobal('fetch', okFetch())
    const bg = Array.from({ length: 300 }, (_, i) => vget(`https://api.bybit.com/v5/market/kline?bg=${i}`, { background: true }))
    await vi.advanceTimersByTimeAsync(10)
    const fgAt: number[] = []
    const fg = Array.from({ length: 20 }, (_, i) => vget(`https://api.bybit.com/v5/market/tickers?fg=${i}`).then(() => fgAt.push(Date.now())))
    const t0 = Date.now()
    await drain([...bg, ...fg])
    expect(maxInWindow(sent, 5000, s => s.url.includes('bg='))).toBeLessThanOrEqual(180)
    // 前台 20 条在后台那一截之外的 120 个名额里，立刻就发
    expect(Math.max(...fgAt) - t0).toBeLessThan(100)
  })
})

describe('429 / 403 冷却中途插进来：排队的不抢跑', () => {
  it('Bybit：300 个排着队，第 50 个之后回 403（封 IP）——冷却期间一条都不发，排队的全部按限流失败', async () => {
    let n = 0
    let coolFrom = 0, coolUntil = 0
    vi.stubGlobal('fetch', vi.fn(async (u: string) => {
      sent.push({ t: Date.now(), url: u, cost: 1 })
      if (++n === 50) { coolFrom = Date.now(); return new Response('', { status: 403, headers: { 'Retry-After': '30' } }) }
      return new Response('{"retCode":0,"result":{"list":[]}}', { status: 200 })
    }))
    // 先把窗口占满一部分，让后面的排队
    const ps = Array.from({ length: 700 }, (_, i) => vget(`https://api.bybit.com/v5/market/tickers?i=${i}`).then(() => 'ok', e => (e instanceof RateLimited ? 'limited' : 'err')))
    const results: string[] = []
    ps.forEach(p => p.then(r => results.push(r)))
    await drain(ps)
    coolUntil = coolFrom + 30_000
    expect(coolFrom).toBeGreaterThan(0)
    // 冷却期内没有任何一条发出去
    expect(sent.filter(s => s.t > coolFrom && s.t < coolUntil)).toEqual([])
    expect(results.filter(r => r === 'limited').length).toBeGreaterThan(300)
    // 403 之后再犯翻倍、冷却结束成功一次清零：冷却过了新的请求照发
    vi.setSystemTime(coolUntil + 1)
    await expect(vget('https://api.bybit.com/v5/market/tickers?after=1')).resolves.toBeTruthy()
  })

  it('OKX：candles 回 429 时整家冷却（同一把），排队中的 mark-price 也不抢跑；Bybit 不受影响', async () => {
    let n = 0, at = 0
    vi.stubGlobal('fetch', vi.fn(async (u: string) => {
      sent.push({ t: Date.now(), url: u, cost: 1 })
      if (u.includes('candles') && ++n === 10) { at = Date.now(); return new Response('', { status: 429 }) }
      return new Response('{"code":"0","data":[],"retCode":0,"result":{"list":[]}}', { status: 200 })
    }))
    const ps = [
      ...Array.from({ length: 60 }, (_, i) => vget(`https://www.okx.com/api/v5/market/candles?i=${i}`).catch(() => null)),
      ...Array.from({ length: 30 }, (_, i) => vget(`https://www.okx.com/api/v5/public/mark-price?i=${i}`).catch(() => null)),
      ...Array.from({ length: 30 }, (_, i) => vget(`https://api.bybit.com/v5/market/tickers?i=${i}`).catch(() => null)),
    ]
    await drain(ps)
    expect(at).toBeGreaterThan(0)
    const okxAfter = sent.filter(s => s.url.includes('okx.com') && s.t > at && s.t < at + 10_000)
    expect(okxAfter).toEqual([])
    expect(sent.filter(s => s.url.includes('bybit')).length).toBe(30)
  })
})

describe('直连与网关两道互不影响；排队中换线路不串道', () => {
  it('直连那道 Coinbase 占满 + 冷却，网关那道照常放行；网关的 429 也不连累直连', async () => {
    const cb = 'https://api.coinbase.com/api/v3/brokerage/market/products'
    const g = gateOf('coinbase')!
    const now = Date.now()
    for (let i = 0; i < 5; i++) expect(g.take(now, false, 1, cb)).toBe(0)
    expect(g.take(now, false, 1, cb)).toBeGreaterThan(0)
    for (let i = 0; i < 5; i++) expect(g.take(now, true, 1, cb)).toBe(0)
    noteStatus(cb, 429, '9', now, false)
    expect(g.coolingFor(now, false)).toBe(9000)
    expect(g.coolingFor(now, true)).toBe(0)
    noteStatus(cb, 429, '4', now, true)
    expect(g.coolingFor(now, true)).toBe(4000)
    expect(g.coolingFor(now, false)).toBe(9000)
  })

  it('排队中用户把线路切到网关：这一条走网关地址、记在网关那一道（原来照旧打直连、却记到网关那道）', async () => {
    const hit: string[] = []
    vi.stubGlobal('fetch', vi.fn(async (u: string) => { hit.push(u); return new Response('{"products":[]}', { status: 200 }) }))
    const cb = 'https://api.coinbase.com/api/v3/brokerage/market/products'
    const g = gateOf('coinbase')!
    for (let i = 0; i < 5; i++) g.take(Date.now(), false, 1, cb)   // 直连那道这一秒满了
    const p = vget(`${cb}?q=1`)
    await vi.advanceTimersByTimeAsync(10)
    expect(hit).toEqual([])
    S.route = 'gateway'
    await vi.advanceTimersByTimeAsync(1500)
    await p
    expect(hit).toEqual(['https://kanpan.43-160-232-253.sslip.io/v1/market/raw/products?q=1&source=coinbase'])
    expect(g.usedOf(Date.now(), cb, true)).toBe(1)
  })

  it('指定了线路的请求（route 参数）按那条线路记账，不看当前选的', async () => {
    const hit: string[] = []
    vi.stubGlobal('fetch', vi.fn(async (u: string) => { hit.push(u); return new Response('{"code":"0","data":[]}', { status: 200 }) }))
    S.route = 'direct'
    await vget('https://www.okx.com/api/v5/market/tickers?instType=SWAP', { route: 'gateway' })
    expect(hit[0]).toContain('/v1/market/raw/api/v5/market/tickers')
    const g = gateOf('okx')!
    expect(g.usedOf(Date.now(), 'https://www.okx.com/api/v5/market/tickers', true, 2)).toBe(1)
    expect(g.usedOf(Date.now(), 'https://www.okx.com/api/v5/market/tickers', false, 2)).toBe(0)
  })
})

describe('行情与订单流共用一把', () => {
  it('OKX candles：行情 vget 与订单流 getJSON 同时各 60 条，合计任意 2 秒 ≤ 20', async () => {
    vi.stubGlobal('fetch', okFetch())
    const ps = [
      ...Array.from({ length: 60 }, (_, i) => vget(`https://www.okx.com/api/v5/market/candles?instId=BTC-USDT-SWAP&m=${i}`)),
      ...Array.from({ length: 60 }, (_, i) => getJSON(`https://www.okx.com/api/v5/market/candles?instId=BTC-USDT-SWAP&bar=30m&o=${i}`, 10_000)),
    ]
    await drain(ps)
    expect(sent.length).toBe(120)
    expect(maxInWindow(sent, 2000)).toBeLessThanOrEqual(20)
    expect(sent.some(s => s.url.includes('m=')) && sent.some(s => s.url.includes('o='))).toBe(true)
  })
  it('网关线路下订单流与行情也记在同一道（网关那道）', async () => {
    vi.stubGlobal('fetch', okFetch())
    S.route = 'gateway'
    await vget('https://api.bybit.com/v5/market/tickers?category=linear')
    await getJSON('https://api.bybit.com/v5/market/kline?category=linear&interval=30', 10_000)
    const g = gateOf('bybit')!
    expect(g.usedOf(Date.now(), '', true)).toBe(2)
    expect(g.usedOf(Date.now(), '', false)).toBe(0)
  })
})

describe('系统时钟往回拨（同 limit.ts 币安那把的 rebase）', () => {
  it('账上的时刻比现在晚一小时：不把这一家锁一小时，当作「刚刚」记的', () => {
    const g = new Gate('t', { hosts: ['t.example'], rules: [{ windowMs: 5000, cap: 3 }] })
    const t = 10_000_000
    for (let i = 0; i < 3; i++) expect(g.take(t, false, 1, '')).toBe(0)
    const back = t - 3_600_000
    const w = g.take(back, false, 1, '')
    expect(w).toBeGreaterThan(0)
    expect(w).toBeLessThanOrEqual(5000)
    expect(g.take(back + 5000, false, 1, '')).toBe(0)
  })
  it('冷却记下之后时钟往回拨：冷却不跟着拉长', () => {
    const g = new Gate('t2', { hosts: ['t2.example'], rules: [{ windowMs: 1000, cap: 5 }] })
    const t = 50_000_000
    g.noteStatus(429, '10', t)
    expect(g.coolingFor(t)).toBe(10_000)
    expect(g.coolingFor(t - 7_200_000)).toBeLessThanOrEqual(10_000)
  })
})

describe('admit 直接压：500 个同一把的排队者在假时钟下不漏不重', () => {
  it('Coinbase 500 个 admit：每个只放行一次，放行时刻在任意 1 秒内 ≤ 5', async () => {
    const at: number[] = []
    const ps = Array.from({ length: 500 }, () => admit('https://api.coinbase.com/api/v3/brokerage/market/products').then(() => at.push(Date.now())))
    await drain(ps, 20, 400_000)
    expect(at.length).toBe(500)
    expect(maxInWindow(at.map(t => ({ t, url: '', cost: 1 })), 1000)).toBeLessThanOrEqual(5)
  })
})
