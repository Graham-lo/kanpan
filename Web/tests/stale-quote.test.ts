/* Web 深度审查 C 线 2026-10-05 · 晚到的 REST 全市场表不许把推送刚刷新过的价格 / 标记价盖回旧值
 * （rest.ts loadUniverse；stream.ts 按交易所时间收帧），和 iOS QuoteState 拒旧帧同一条规矩 */
import { afterEach, describe, expect, it, vi } from 'vitest'

class FakeWS {
  static OPEN = 1; static CONNECTING = 0; static CLOSED = 3
  static all: FakeWS[] = []
  readyState = 0
  onopen: (() => void) | null = null
  onmessage: ((e: { data: string }) => void) | null = null
  onclose: (() => void) | null = null
  onerror: (() => void) | null = null
  constructor(public url: string) { FakeWS.all.push(this) }
  send() {}
  close() { this.readyState = 3 }
  open() { this.readyState = 1; this.onopen?.() }
  push(o: unknown) { this.onmessage?.({ data: JSON.stringify(o) }) }
}

afterEach(() => { vi.unstubAllGlobals(); vi.resetModules(); FakeWS.all = [] })

const EX = { symbols: [{ symbol: 'BTCUSDT', baseAsset: 'BTC', quoteAsset: 'USDT', contractType: 'PERPETUAL', status: 'TRADING', filters: [{ filterType: 'PRICE_FILTER', tickSize: '0.1' }], pricePrecision: 1 }] }
const tk = (price: number, vol: number, closeTime: number) => [{ symbol: 'BTCUSDT', lastPrice: String(price), priceChange: '1', priceChangePercent: '1', quoteVolume: String(vol), openPrice: '99', highPrice: '200', lowPrice: '50', count: 10, closeTime }]
const pi = (mark: number, time: number) => [{ symbol: 'BTCUSDT', lastFundingRate: '0.0001', nextFundingTime: 0, markPrice: String(mark), indexPrice: String(mark), time }]

async function setup() {
  vi.stubGlobal('WebSocket', FakeWS)
  vi.resetModules()
  let ticker = tk(100, 1000, 1000), prem = pi(100, 1000)
  vi.stubGlobal('fetch', vi.fn(async (u: string) => {
    const body = u.includes('exchangeInfo') ? EX : u.includes('ticker/24hr') ? ticker : prem
    return new Response(JSON.stringify(body), { status: 200 })
  }))
  const m = await import('../src/market')
  await m.loadUniverse()
  m.setStreams(['btcusdt@ticker', 'btcusdt@aggTrade', 'btcusdt@markPrice@1s'], [], { now: true })
  const ws = FakeWS.all[0]; ws.open()
  return { m, ws, rest(t: typeof ticker, p: typeof prem) { ticker = t; prem = p } }
}

describe('晚到的 REST 24h 行情不覆盖更新的推送', () => {
  it('推送 5 秒时的 24h 行情之后，3 秒时的 REST 表回来：价格、成交额、标记价都不回跳', async () => {
    const { m, ws, rest } = await setup()
    ws.push({ stream: 'btcusdt@ticker', data: { e: '24hrTicker', E: 5000, C: 5000, s: 'BTCUSDT', c: '110', p: '11', P: '11', q: '5000', o: '99', h: '200', l: '50', n: 50 } })
    ws.push({ stream: 'btcusdt@markPrice@1s', data: { e: 'markPriceUpdate', E: 5000, s: 'BTCUSDT', p: '111', i: '111', r: '0.0002', T: 0 } })
    rest(tk(105, 3000, 3000), pi(104, 3000))
    await m.loadUniverse()
    const s = m.S.symbols.get('BTCUSDT')!
    expect(s.price).toBe(110)
    expect(s.vol).toBe(5000)
    expect(s.mark).toBe(111)
    // 比推送新的 REST 照常收
    rest(tk(120, 9000, 6000), pi(121, 6000))
    await m.loadUniverse()
    expect(s.price).toBe(120)
    expect(s.vol).toBe(9000)
    expect(s.mark).toBe(121)
  })

  it('逐笔推到 7 秒后，6 秒时的 REST 价格不盖回去，但 6 秒时的成交额照收（逐笔不带成交额）', async () => {
    const { m, ws, rest } = await setup()
    ws.push({ stream: 'btcusdt@aggTrade', data: { e: 'aggTrade', s: 'BTCUSDT', p: '130', q: '1', T: 7000, m: false } })
    rest(tk(125, 8000, 6000), pi(100, 1000))
    await m.loadUniverse()
    const s = m.S.symbols.get('BTCUSDT')!
    expect(s.price).toBe(130)
    expect(s.vol).toBe(8000)
  })

  it('推送里晚到一笔早于手里时间的逐笔：价格不回跳', async () => {
    const { m, ws } = await setup()
    ws.push({ stream: 'btcusdt@ticker', data: { e: '24hrTicker', E: 5000, C: 5000, s: 'BTCUSDT', c: '110', p: '11', P: '11', q: '5000', o: '99', h: '200', l: '50', n: 50 } })
    ws.push({ stream: 'btcusdt@aggTrade', data: { e: 'aggTrade', s: 'BTCUSDT', p: '108', q: '1', T: 4900, m: false } })
    expect(m.S.symbols.get('BTCUSDT')!.price).toBe(110)
  })
})
