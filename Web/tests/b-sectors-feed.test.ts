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
  it('上一轮拉取在途时 stop → start：共用在途那次，回来的旧拉取不再排下一次', async () => {
    const { startFeed, stopFeed, POLL_MS } = await import('../src/sectors/feed')
    const tickers = (): number => h.calls.filter(u => u.includes('ticker/24hr')).length
    startFeed(() => {})
    await vi.advanceTimersByTimeAsync(0)
    expect(tickers()).toBe(1)
    stopFeed(); startFeed(() => {})
    await vi.advanceTimersByTimeAsync(0)
    expect(tickers()).toBe(1)   // F5：在途那次共用，不另发
    h.pending.splice(0).forEach(r => r([]))
    await vi.advanceTimersByTimeAsync(0)
    await vi.advanceTimersByTimeAsync(POLL_MS)
    // 只有一条链：一个周期只多拉一次
    expect(tickers()).toBe(2)
    h.pending.splice(0).forEach(r => r([]))
    await vi.advanceTimersByTimeAsync(POLL_MS)
    expect(tickers()).toBe(3)
    stopFeed()
    h.pending.splice(0).forEach(r => r([]))
    await vi.advanceTimersByTimeAsync(POLL_MS * 3)
    expect(tickers()).toBe(3)
  })
  it('F5：几页之间来回点 50 次，拉到的行情不满一个周期就不重拉（全量 24hr 权重 40）', async () => {
    const { startFeed, stopFeed, POLL_MS, feed } = await import('../src/sectors/feed')
    const tickers = (): number => h.calls.filter(u => u.includes('ticker/24hr')).length
    const n0 = tickers()
    let changes = 0
    startFeed(() => { changes++ })
    await vi.advanceTimersByTimeAsync(0)
    h.pending.splice(0).forEach(r => r([{ symbol: 'BTCUSDT', lastPrice: '1', priceChangePercent: '1', quoteVolume: '1' }]))
    await vi.advanceTimersByTimeAsync(0)
    expect(feed.quotes.size).toBe(1)
    expect(tickers()).toBe(n0 + 1)
    for (let i = 0; i < 50; i++) { stopFeed(); await vi.advanceTimersByTimeAsync(100); startFeed(() => { changes++ }); await vi.advanceTimersByTimeAsync(50) }
    // 来回 7.5 秒：一次没多拉，但每次回来都拿手上的行情先画
    expect(tickers()).toBe(n0 + 1)
    expect(changes).toBeGreaterThanOrEqual(51)
    // 满一个周期照常拉
    await vi.advanceTimersByTimeAsync(POLL_MS)
    expect(tickers()).toBe(n0 + 2)
    stopFeed(); h.pending.splice(0).forEach(r => r([]))
  })
})
