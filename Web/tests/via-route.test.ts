/* 网关线路下币安合约 REST 改走新加坡透传（2026-10-02：国内不开代理连不上 fapi.binance.com，手机 4G 上 K 线全空） */
import { describe, it, expect, afterEach } from 'vitest'
import { S } from '../src/market/state'
import { viaRoute, apiOrigin } from '../src/market/rest'

const SG = 'https://kanpan.43-160-232-253.sslip.io'

describe('viaRoute', () => {
  afterEach(() => { S.route = 'direct' })

  it('直连线路原样', () => {
    S.route = 'direct'
    expect(viaRoute('https://fapi.binance.com/fapi/v1/klines?symbol=LINKUSDT&interval=30m&limit=500')).toBe('https://fapi.binance.com/fapi/v1/klines?symbol=LINKUSDT&interval=30m&limit=500')
  })

  it('网关线路把 fapi / dapi 改成 /v1/market/raw/<path>?…&source=binance（没有 location 时打线上那台）', () => {
    S.route = 'gateway'
    expect(apiOrigin()).toBe(SG)
    expect(viaRoute('https://fapi.binance.com/fapi/v1/klines?symbol=LINKUSDT&interval=30m&limit=500'))
      .toBe(`${SG}/v1/market/raw/fapi/v1/klines?symbol=LINKUSDT&interval=30m&limit=500&source=binance`)
    expect(viaRoute('https://fapi.binance.com/fapi/v1/exchangeInfo')).toBe(`${SG}/v1/market/raw/fapi/v1/exchangeInfo?source=binance`)
    expect(viaRoute('https://fapi.binance.com/futures/data/openInterestHist?symbol=BTCUSDT&period=5m&limit=13'))
      .toBe(`${SG}/v1/market/raw/futures/data/openInterestHist?symbol=BTCUSDT&period=5m&limit=13&source=binance`)
    expect(viaRoute('https://dapi.binance.com/dapi/v1/depth?symbol=BTCUSD_PERP&limit=1000')).toBe(`${SG}/v1/market/raw/dapi/v1/depth?symbol=BTCUSD_PERP&limit=1000&source=binance`)
  })

  it('不是币安合约的地址不动（现货 binance.vision 国内能直连、OKX、自家 /v1）', () => {
    S.route = 'gateway'
    for (const u of ['https://data-api.binance.vision/api/v3/klines?symbol=BTCUSDT&interval=30m', 'https://www.okx.com/api/v5/market/candles?instId=BTC-USDT', '/v1/market/depth?symbol=BTCUSDT&limit=1000&market=um', 'wss://fstream.binance.com/market/stream']) {
      expect(viaRoute(u)).toBe(u)
    }
  })
})
