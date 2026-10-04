/* Web 深度审查 C 线 2026-10-05 · /v1/market/meta：失败可重取、一只品种只发一次（market/meta.ts、手机行情页估值格 data.ts） */
import { afterEach, describe, expect, it, vi } from 'vitest'

afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); vi.resetModules() })

async function load(fetchImpl: (u: string) => Promise<Response>) {
  vi.useFakeTimers()
  vi.resetModules()
  const f = vi.fn(fetchImpl)
  vi.stubGlobal('fetch', f)
  const market = await import('../src/market')
  market.S.symbols.set('BTCUSDT', { symbol: 'BTCUSDT', price: 100 } as never)
  return { f, market }
}
const flushAll = async () => { await vi.advanceTimersByTimeAsync(250); await vi.advanceTimersByTimeAsync(10) }

describe('元数据失败可重取', () => {
  it('第一次断网：两分钟后再要会重取，市值补上（原来整场空着）', async () => {
    let fail = true
    const { f, market } = await load(async () => {
      if (fail) throw new TypeError('Failed to fetch')
      return new Response(JSON.stringify({ data: { BTCUSDT: { totalSupply: 21e6 } } }))
    })
    market.wantMeta(['BTCUSDT']); await flushAll()
    expect(f).toHaveBeenCalledTimes(1)
    expect(market.marketCap('BTCUSDT')).toBeNull()
    fail = false
    market.wantMeta(['BTCUSDT']); await flushAll()
    expect(f).toHaveBeenCalledTimes(1)                // 两分钟内不连着打
    await vi.advanceTimersByTimeAsync(120_000)
    market.wantMeta(['BTCUSDT']); await flushAll()
    expect(f).toHaveBeenCalledTimes(2)
    expect(market.marketCap('BTCUSDT')).toBe(21e6 * 100)
  })

  it('服务端 5xx 同样可重取；200 但没这只的不再重取', async () => {
    let status = 502
    const { f, market } = await load(async () => status === 502 ? new Response('', { status }) : new Response(JSON.stringify({ data: {} })))
    market.wantMeta(['BTCUSDT']); await flushAll()
    status = 200
    await vi.advanceTimersByTimeAsync(120_000)
    market.wantMeta(['BTCUSDT']); await flushAll()
    await vi.advanceTimersByTimeAsync(120_000)
    market.wantMeta(['BTCUSDT']); await flushAll()
    expect(f).toHaveBeenCalledTimes(2)
  })
})

describe('一只品种只发一次', () => {
  it('手机行情页头部的估值格与总供应量同一次请求（原来估值格自己另发一次 /v1/market/meta）', async () => {
    const { f } = await load(async () => new Response(JSON.stringify({ data: { NVDAUSDT: { forwardEarnings: 1e11, revenue: 2e11 } } })))
    const { fetchValuation, valuationOf } = await import('../src/m/pages/chart/data')
    const market = await import('../src/market')
    market.wantMeta(['NVDAUSDT'])
    const p = fetchValuation('NVDAUSDT')
    await flushAll()
    expect(await p).toEqual({ forwardEarnings: 1e11, revenue: 2e11 })
    expect(valuationOf('NVDAUSDT')).toEqual({ forwardEarnings: 1e11, revenue: 2e11 })
    expect(f).toHaveBeenCalledTimes(1)
    expect(String(f.mock.calls[0][0])).toMatch(/\/v1\/market\/meta\?symbols=NVDAUSDT$/)
  })

  it('元数据先于全市场表到：表到了以后新建的品种带上总供应量', async () => {
    const { market } = await load(async () => new Response(JSON.stringify({ data: { ETHUSDT: { totalSupply: 1.2e8 } } })))
    market.wantMeta(['ETHUSDT']); await flushAll()
    expect(market.supplyOf('ETHUSDT')).toBe(1.2e8)
  })
})
