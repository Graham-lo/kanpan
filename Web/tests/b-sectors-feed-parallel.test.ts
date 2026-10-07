// 板块页：品种表与全量行情并排取、表晚到了按表重算一次、表留在本机 24 小时（2026-10-07）
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'

const h = vi.hoisted(() => ({ calls: [] as string[], pendingEx: [] as ((v: unknown) => void)[], pendingTk: [] as ((v: unknown) => void)[] }))
vi.mock('../src/market', () => ({
  REST: 'https://x', S: { symbols: new Map() },
  j: (url: string) => {
    h.calls.push(url)
    return new Promise(res => (url.includes('exchangeInfo') ? h.pendingEx : h.pendingTk).push(res))
  },
}))

class MemStorage {
  private m = new Map<string, string>()
  getItem(k: string): string | null { return this.m.get(k) ?? null }
  setItem(k: string, v: string): void { this.m.set(k, v) }
  removeItem(k: string): void { this.m.delete(k) }
}

const ex = { symbols: [
  { symbol: 'BTCUSDT', baseAsset: 'BTC', quoteAsset: 'USDT', contractType: 'PERPETUAL', status: 'TRADING' },
  { symbol: '1000PEPEUSDT', baseAsset: '1000PEPE', quoteAsset: 'USDT', contractType: 'PERPETUAL', status: 'TRADING', underlyingSubType: ['Meme'] },
] }
const tk = [
  { symbol: 'BTCUSDT', lastPrice: '1', priceChangePercent: '1', quoteVolume: '1' },
  { symbol: '1000PEPEUSDT', lastPrice: '1', priceChangePercent: '2', quoteVolume: '1' },
]

describe('板块页：表与行情并排', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    ;(globalThis as { document?: unknown }).document = { hidden: false }
    ;(globalThis as { localStorage?: unknown }).localStorage = new MemStorage()
  })
  afterEach(() => { vi.useRealTimers(); delete (globalThis as { localStorage?: unknown }).localStorage })

  it('两问同时发出；行情先回先出第一帧，表回来按表重算并再回调一次；表存进本机', async () => {
    const { startFeed, stopFeed, feed, CATALOG_CACHE_KEY } = await import('../src/sectors/feed')
    let changes = 0
    startFeed(() => { changes++ })
    await vi.advanceTimersByTimeAsync(0)
    expect(h.calls.filter(u => u.includes('exchangeInfo')).length).toBe(1)
    expect(h.calls.filter(u => u.includes('ticker/24hr')).length).toBe(1)
    // 行情先回：不等表就有第一帧（按合约名拆）
    h.pendingTk.splice(0).forEach(r => r(tk))
    await vi.advanceTimersByTimeAsync(0)
    expect(changes).toBe(1)
    expect(feed.quotes.size).toBe(2)
    expect(feed.entries.length).toBe(0)
    // 表回来：按表重算、再回调一次，不另发行情请求
    h.pendingEx.splice(0).forEach(r => r(ex))
    await vi.advanceTimersByTimeAsync(0)
    expect(feed.entries.length).toBe(2)
    expect(changes).toBe(2)
    expect(h.calls.filter(u => u.includes('ticker/24hr')).length).toBe(1)
    const saved = JSON.parse(localStorage.getItem(CATALOG_CACHE_KEY)!) as { entries: unknown[] }
    expect(saved.entries.length).toBe(2)
    stopFeed()
  })

  it('本机留着的表直接用，不再问 exchangeInfo', async () => {
    vi.resetModules()
    const { CATALOG_CACHE_KEY } = await import('../src/sectors/feed')
    localStorage.setItem(CATALOG_CACHE_KEY, JSON.stringify({ atMs: Date.now(), entries: ex.symbols.map(e => ({ symbol: e.symbol, baseAsset: e.baseAsset, quoteAsset: e.quoteAsset, underlyingSubType: e.underlyingSubType })) }))
    vi.resetModules()
    const { startFeed, stopFeed, feed } = await import('../src/sectors/feed')
    const n0 = h.calls.filter(u => u.includes('exchangeInfo')).length
    startFeed(() => {})
    await vi.advanceTimersByTimeAsync(0)
    expect(feed.entries.length).toBe(2)
    expect(h.calls.filter(u => u.includes('exchangeInfo')).length).toBe(n0)
    h.pendingTk.splice(0).forEach(r => r(tk))
    await vi.advanceTimersByTimeAsync(0)
    expect(feed.quotes.size).toBe(2)
    stopFeed()
  })
})
