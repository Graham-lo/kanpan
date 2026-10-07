/* 体感优化 2026-10-07 · 全市场表先摆本机那份再刷新；exchangeInfo / ticker/24hr 全站只取一次 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { Sym } from '../src/market/symbols'

class MemStorage {
  m = new Map<string, string>()
  getItem(k: string) { return this.m.has(k) ? this.m.get(k)! : null }
  setItem(k: string, v: string) { this.m.set(k, String(v)) }
  removeItem(k: string) { this.m.delete(k) }
  clear() { this.m.clear() }
  key(i: number) { return [...this.m.keys()][i] ?? null }
  get length() { return this.m.size }
}

const EX = { symbols: [
  { symbol: 'BTCUSDT', baseAsset: 'BTC', quoteAsset: 'USDT', contractType: 'PERPETUAL', status: 'TRADING', underlyingType: 'COIN', underlyingSubType: ['PoW'], filters: [{ filterType: 'PRICE_FILTER', tickSize: '0.10' }], pricePrecision: 2 },
  { symbol: 'ETHUSDC', baseAsset: 'ETH', quoteAsset: 'USDC', contractType: 'PERPETUAL', status: 'TRADING', underlyingType: 'COIN', filters: [{ filterType: 'PRICE_FILTER', tickSize: '0.01' }], pricePrecision: 2 },
] }
const TK = (price: number, closeTime: number) => [{ symbol: 'BTCUSDT', lastPrice: String(price), priceChange: '1', priceChangePercent: '2.5', quoteVolume: '1000', openPrice: '99', highPrice: '200', lowPrice: '50', count: 10, closeTime }]
const PI = [{ symbol: 'BTCUSDT', lastFundingRate: '0.0001', nextFundingTime: Date.now() + 3_600_000, markPrice: '100', indexPrice: '100', time: 1000 }]

type Gate = { url: string; ok: (body: unknown) => void; fail: () => void }
let store: MemStorage
let gates: Gate[]
function stubFetch(): void {
  gates = []
  vi.stubGlobal('fetch', vi.fn((u: string) => new Promise<Response>((res, rej) => {
    gates.push({ url: u, ok: b => res(new Response(JSON.stringify(b), { status: 200 })), fail: () => rej(new Error('net')) })
  })))
}
const count = (part: string) => gates.filter(g => g.url.includes(part) && !/DXY|macro/.test(g.url)).length
async function answerAll(price = 105, at = 5000) {
  for (const g of gates.splice(0)) {
    g.ok(g.url.includes('exchangeInfo') ? EX : g.url.includes('ticker/24hr') ? TK(price, at) : g.url.includes('premiumIndex') ? PI : {})
  }
  await vi.advanceTimersByTimeAsync(0)
}
async function settle() { for (let i = 0; i < 6; i++) await Promise.resolve(); await vi.advanceTimersByTimeAsync(0) }

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'Date'] })
  vi.resetModules()
  store = new MemStorage()
  vi.stubGlobal('localStorage', store)
  stubFetch()
})
afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); delete (globalThis as { document?: unknown }).document })

describe('全市场表的本机副本', () => {
  it('写进去再读出来：价、涨跌、精度、分类、标签都在；过了的结算时刻丢掉；超过 7 天不认；坏数据不认', async () => {
    const m = await import('../src/market')
    const { macroFallback } = await import('../src/market/macro')
    const map = new Map<string, Sym>([['BTCUSDT', { symbol: 'BTCUSDT', base: 'BTC', code: 'BTC', kind: 'crypto' as const, cn: '比特币', dec: 1, color: '#f7931a', price: 123.4, chg: 1, pct: 2.5, vol: 99, fr: 0.0001, nextFunding: Date.now() - 1, ut: 'COIN', tags: ['pow'], pxAt: 7, statAt: 7, markAt: 7, mark: 123, index: 122, open: 120, hi: 130, lo: 110, count: 5 }]])
    const dxy = macroFallback(); dxy.price = 98.7; dxy.cn = '美元指数X'
    map.set(dxy.symbol, dxy)
    expect(m.saveUniverse(map, store as unknown as Storage)).toBe(true)
    const raw = store.getItem(m.UNIVERSE_CACHE_KEY)!
    expect(raw.length).toBeLessThan(600)
    const back = m.readUniverse(store as unknown as Storage)!
    const b = back.get('BTCUSDT')!
    expect([b.price, b.pct, b.dec, b.kind, b.ut, b.tags, b.mark, b.hi, b.pxAt]).toEqual([123.4, 2.5, 1, 'crypto', 'COIN', ['pow'], 123, 130, 7])
    expect(b.nextFunding).toBeNull()
    expect(b.lastTick).toBeUndefined()
    expect(back.get(dxy.symbol)!.macro).toBe(true)
    expect(back.get(dxy.symbol)!.cn).toBe('美元指数X')
    expect(m.readUniverse(store as unknown as Storage, Date.now() + 8 * 86_400_000)).toBeNull()
    store.setItem(m.UNIVERSE_CACHE_KEY, '{oops')
    expect(m.readUniverse(store as unknown as Storage)).toBeNull()
  })

  it('冷启动有本机表：马上返回、发 universe（S.live 仍是 null），网络回来再发一次并换成新价', async () => {
    const m = await import('../src/market')
    m.saveUniverse(new Map([['BTCUSDT', { symbol: 'BTCUSDT', base: 'BTC', code: 'BTC', kind: 'crypto' as const, cn: '', dec: 3, color: '#000', price: 90, chg: 0, pct: 1, vol: 1, fr: null, nextFunding: null, pxAt: 1, statAt: 1, markAt: 1 }]]), store as unknown as Storage)
    const seen: (boolean | null)[] = []
    m.on(e => { if (e.type === 'universe') seen.push(m.S.live) })
    let resolved = false
    const p = m.loadUniverse().then(() => { resolved = true })
    await settle()
    expect(resolved).toBe(true)
    expect(m.S.symbols.get('BTCUSDT')!.price).toBe(90)
    expect(m.S.live).toBeNull()
    expect(seen).toEqual([null])
    expect(count('exchangeInfo')).toBe(1)
    await p
    await answerAll(105, 5000)
    await settle()
    expect(seen).toEqual([null, true])
    const s = m.S.symbols.get('BTCUSDT')!
    expect(s.price).toBe(105)
    expect(s.dec).toBe(1)          // 精度以交易所这次的 tickSize 为准
    expect(m.S.symbols.has('ETHUSDC')).toBe(false)
  })

  it('本机没有表：照旧等网络回来才返回（不造数据）', async () => {
    const m = await import('../src/market')
    let resolved = false
    void m.loadUniverse().then(() => { resolved = true })
    await settle()
    expect(resolved).toBe(false)
    await answerAll()
    await settle()
    expect(resolved).toBe(true)
    expect(m.S.live).toBe(true)
    await vi.advanceTimersByTimeAsync(2000)
    expect(m.readUniverse(store as unknown as Storage)?.get('BTCUSDT')?.price).toBe(105)   // 取到就写一份
  })

  it('摆着本机表、后台那次失败：表留着、S.live 变 false，自己隔 30 秒再取', async () => {
    const m = await import('../src/market')
    m.saveUniverse(new Map([['BTCUSDT', { symbol: 'BTCUSDT', base: 'BTC', code: 'BTC', kind: 'crypto' as const, cn: '', dec: 1, color: '#000', price: 90, chg: 0, pct: 1, vol: 1, fr: null, nextFunding: null }]]), store as unknown as Storage)
    await m.loadUniverse()
    gates.splice(0).forEach(g => g.fail())
    await settle()
    expect(m.S.live).toBe(false)
    expect(m.S.symbols.get('BTCUSDT')!.price).toBe(90)
    expect(count('exchangeInfo')).toBe(0)
    await vi.advanceTimersByTimeAsync(30_000)
    expect(count('exchangeInfo')).toBe(1)
    await answerAll(111)
    await settle()
    expect(m.S.live).toBe(true)
    expect(m.S.symbols.get('BTCUSDT')!.price).toBe(111)
  })

  it('同一时刻两处要表只发一组请求', async () => {
    const m = await import('../src/market')
    const a = m.loadUniverse(), b = m.loadUniverse()
    await settle()
    expect(count('exchangeInfo')).toBe(1)
    expect(count('ticker/24hr')).toBe(1)
    await answerAll()
    expect(await a).toBe(await b)
  })
})

describe('exchangeInfo / ticker/24hr 全站共用', () => {
  it('全市场表在途时板块页开始轮询：exchangeInfo 与 ticker/24hr 各只发一次；目录各计价币都留', async () => {
    ;(globalThis as { document?: unknown }).document = { hidden: false, visibilityState: 'visible', addEventListener() {} }
    const m = await import('../src/market')
    const { startFeed, stopFeed, feed } = await import('../src/sectors/feed')
    void m.loadUniverse()
    startFeed(() => {})
    await settle()
    expect(count('exchangeInfo')).toBe(1)
    expect(count('ticker/24hr')).toBe(1)
    await answerAll()
    await settle()
    expect(feed.entries.map(e => e.symbol).sort()).toEqual(['BTCUSDT', 'ETHUSDC'])
    expect(m.exchangeRows()?.length).toBe(2)
    stopFeed()
  })

  it('全市场表取过之后才进板块页：目录直接用那一份，不再取 exchangeInfo', async () => {
    ;(globalThis as { document?: unknown }).document = { hidden: false, visibilityState: 'visible', addEventListener() {} }
    const m = await import('../src/market')
    void m.loadUniverse()
    await settle(); await answerAll(); await settle()
    const { startFeed, stopFeed, feed } = await import('../src/sectors/feed')
    startFeed(() => {})
    await settle()
    expect(count('exchangeInfo')).toBe(0)
    expect(count('ticker/24hr')).toBe(1)
    expect(feed.entries.length).toBe(2)
    stopFeed()
  })
})
