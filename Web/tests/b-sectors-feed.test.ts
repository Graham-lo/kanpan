import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'

const h = vi.hoisted(() => ({ calls: [] as string[], pending: [] as ((v: unknown) => void)[] }))
vi.mock('../src/market', () => ({
  REST: 'https://x', S: { symbols: new Map() },
  j: (url: string) => {
    h.calls.push(url)
    if (url.includes('exchangeInfo')) return Promise.resolve({ symbols: [{ symbol: 'BTCUSDT', baseAsset: 'BTC', quoteAsset: 'USDT', contractType: 'PERPETUAL', status: 'TRADING' }] })
    return new Promise(res => h.pending.push(res))
  },
}))

describe('板块页轮询：离开又回来不叠出第二条链（B12）', () => {
  beforeEach(() => { vi.useFakeTimers(); (globalThis as { document?: unknown }).document = { hidden: false } })
  afterEach(() => { vi.useRealTimers() })
  it('上一轮拉取在途时 stop → start，回来的旧拉取不再排下一次', async () => {
    const { startFeed, stopFeed, POLL_MS } = await import('../src/sectors/feed')
    const tickers = (): number => h.calls.filter(u => u.includes('ticker/24hr')).length
    startFeed(() => {})
    await vi.advanceTimersByTimeAsync(0)
    expect(tickers()).toBe(1)
    stopFeed(); startFeed(() => {})
    await vi.advanceTimersByTimeAsync(0)
    expect(tickers()).toBe(2)
    // 两次拉取都回来
    h.pending.splice(0).forEach(r => r([]))
    await vi.advanceTimersByTimeAsync(0)
    await vi.advanceTimersByTimeAsync(POLL_MS)
    // 只有一条链：一个周期只多拉一次
    expect(tickers()).toBe(3)
    h.pending.splice(0).forEach(r => r([]))
    await vi.advanceTimersByTimeAsync(POLL_MS)
    expect(tickers()).toBe(4)
    stopFeed()
    h.pending.splice(0).forEach(r => r([]))
    await vi.advanceTimersByTimeAsync(POLL_MS * 3)
    expect(tickers()).toBe(4)
  })
})
