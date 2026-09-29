import { afterEach, describe, expect, it, vi } from 'vitest'
import { COOL_418_MS, COOL_429_MS, RateLimited, coolingFor, isRateLimit, noteStatus, resetLimits } from '../src/market/limit'
import { j } from '../src/market/rest'

const FAPI = 'https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT'

afterEach(() => { resetLimits(); vi.unstubAllGlobals() })

describe('交易所限流闸', () => {
  it('429 关 60 秒、418 关 5 分钟，按主机分，不连累别家', () => {
    noteStatus(FAPI, 429, null, 1000)
    expect(coolingFor(FAPI, 1000)).toBe(COOL_429_MS)
    expect(coolingFor('https://fapi.binance.com/fapi/v1/depth?symbol=ETHUSDT', 1000)).toBe(COOL_429_MS)
    expect(coolingFor('https://dapi.binance.com/dapi/v1/depth', 1000)).toBe(0)
    expect(coolingFor('https://www.okx.com/api/v5/market/candles', 1000)).toBe(0)
    expect(coolingFor(FAPI, 1000 + COOL_429_MS)).toBe(0)
    noteStatus('https://data-api.binance.vision/api/v3/depth', 418, '', 0)
    expect(coolingFor('https://data-api.binance.vision/api/v3/depth', 0)).toBe(COOL_418_MS)
  })
  it('读得到 Retry-After 就按它；200 / 500 不关', () => {
    noteStatus(FAPI, 429, '7', 0)
    expect(coolingFor(FAPI, 0)).toBe(7000)
    resetLimits()
    noteStatus(FAPI, 500, null, 0); noteStatus(FAPI, 200, null, 0)
    expect(coolingFor(FAPI, 0)).toBe(0)
  })
  it('j()：回一次 429 之后，冷却期内同主机的请求不再发出去', async () => {
    const f = vi.fn(async () => new Response('', { status: 429 }))
    vi.stubGlobal('fetch', f)
    await expect(j(FAPI)).rejects.toThrow(/^429/)
    for (let k = 0; k < 20; k++) await expect(j(`${FAPI}&k=${k}`)).rejects.toBeInstanceOf(RateLimited)
    expect(f).toHaveBeenCalledTimes(1)
    const e = await j(FAPI).catch(x => x)
    expect(isRateLimit(e)).toBe(true)
    expect(isRateLimit(new Error('500 x'))).toBe(false)
  })
})
