/* 多交易所 · 行情面（2026-10-08）：身份、注册表、三家（+ Coinbase）的解码、搜索分组、一家一把限流器、线路规矩。
 *
 * 报文夹具：容器连不上任何交易所（代理 403），录不了真帧——一律按官方文档与 scratchpad「交易所接口速查」手写：
 *   OKX v5   https://www.okx.com/docs-v5/en/ （Public Data › Get instruments、Market Data › Get tickers / Get candlesticks、
 *            WebSocket › tickers / candle / trades / mark-price / funding-rate）
 *   Bybit v5 https://bybit-exchange.github.io/docs/v5/ （Market › Instruments Info / Tickers / Kline、WebSocket Public › Ticker / Kline / Trade）
 *   Hyperliquid https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api （Info endpoint › Perpetuals metaAndAssetCtxs、candleSnapshot；
 *            Websocket › Subscriptions candle / trades / activeAssetCtx）
 *   Coinbase Advanced Trade https://docs.cdp.coinbase.com/advanced-trade/ （Public › List Products / Get Product Candles、WebSocket ticker / market_trades）
 */
import { afterEach, describe, expect, it, vi } from 'vitest'
import { parseKey, keyOf, displayKey, syncKeyOf, venueOf, isDefaultVenue, alertMarketOf, wireSymbol } from '../src/market/identity'
import { MARKET_VENUES, VENUE_LIST, fundingPeriodOf, intervalPlan, marketKlines, marketOf, symbolOk, venueLabel, venueName } from '../src/venues'
import { decodeOkxCandles, decodeOkxInstruments, decodeOkxPush, decodeOkxTickers, okxInstId, okxKeyOf, okxMarket } from '../src/venues/okx'
import { bybitDecoder, decodeBybitInstruments, decodeBybitKlines, decodeBybitTickers, bybitMarket } from '../src/venues/bybit'
import { decodeHlCandles, decodeHlCtxs, decodeHlPush, decodeHlUniverse, hlCoin, hlMarket, hlWeight, nextHour } from '../src/venues/hyperliquid'
import { decodeCbCandles, decodeCbProducts, decodeCbPush, decodeCbQuotes, cbMarket } from '../src/venues/coinbase'
import { aggregateBars, bucketOf, WEEK_OFFSET } from '../src/venues/bars'
import { NoGatewayRoute, vget, vpost } from '../src/venues/http'
import { gateOf, admit, coolingFor, noteStatus, resetLimits, RateLimited } from '../src/market/limit'
import { groupSearch, baseOf, headName, kindName, type Sym } from '../src/market/symbols'
import { S } from '../src/market/state'
import { streamName, symbolOfStream } from '../src/market/stream'
import type { Bar } from '../src/chart/calc'

afterEach(() => { resetLimits(); vi.unstubAllGlobals(); vi.restoreAllMocks(); S.route = 'direct' })

describe('身份（market/identity.ts）', () => {
  it('裸代号 = 币安 U 本位、DXY = 美元指数、完整键原样', () => {
    expect(parseKey('BTCUSDT')).toEqual({ venue: 'binance', market: 'usd_m', symbol: 'BTCUSDT' })
    expect(parseKey('DXY')).toEqual({ venue: 'macro', market: 'index', symbol: 'DXY' })
    expect(parseKey('okx/usd_m/BTCUSDT')).toEqual({ venue: 'okx', market: 'usd_m', symbol: 'BTCUSDT' })
    expect(parseKey('coinbase/spot/BTC-USD')).toEqual({ venue: 'coinbase', market: 'spot', symbol: 'BTC-USD' })
    expect(parseKey('binance/usd_m/ETHUSDT')).toEqual({ venue: 'binance', market: 'usd_m', symbol: 'ETHUSDT' })
  })
  it('键 ↔ 三段：币安与美元指数回裸代号（本机存档不迁移），别家完整键', () => {
    expect(keyOf('binance', 'usd_m', 'BTCUSDT')).toBe('BTCUSDT')
    expect(keyOf('macro', 'index', 'DXY')).toBe('DXY')
    expect(keyOf('hyperliquid', 'usd_m', 'KPEPE')).toBe('hyperliquid/usd_m/KPEPE')
    expect(displayKey('binance/usd_m/BTCUSDT')).toBe('BTCUSDT')
    expect(displayKey('macro/index/DXY')).toBe('DXY')
    expect(displayKey('bybit/usd_m/1000PEPEUSDT')).toBe('bybit/usd_m/1000PEPEUSDT')
    expect(syncKeyOf('BTCUSDT')).toBe('binance/usd_m/BTCUSDT')
    expect(syncKeyOf('DXY')).toBe('macro/index/DXY')
    expect(syncKeyOf('okx/usd_m/BTCUSDT')).toBe('okx/usd_m/BTCUSDT')
    expect(venueOf('okx/usd_m/BTCUSDT')).toBe('okx')
    expect(isDefaultVenue('BTCUSDT')).toBe(true)
    expect(isDefaultVenue('DXY')).toBe(false)
    expect(isDefaultVenue('okx/usd_m/BTCUSDT')).toBe(false)
    expect(alertMarketOf('hyperliquid/usd_m/BTC')).toBe('hyperliquid/usd_m')
    expect(alertMarketOf('BTCUSDT')).toBe('binance/usd_m')
    expect(wireSymbol('coinbase/spot/BTC-USD')).toBe('BTC-USD')
  })
  it('展示：底、图表头、现货 / 永续', () => {
    expect(baseOf('okx/usd_m/BTCUSDT')).toBe('BTC')
    expect(baseOf('coinbase/spot/ETH-USD')).toBe('ETH')
    expect(baseOf('bybit/usd_m/1000PEPEUSDT')).toBe('PEPE')
    expect(headName({ symbol: 'bybit/usd_m/1000PEPEUSDT' })).toBe('1000PEPE')
    expect(headName({ symbol: 'hyperliquid/usd_m/KPEPE', title: 'kPEPE' })).toBe('kPEPE')
    expect(kindName({ kind: 'crypto', symbol: 'coinbase/spot/BTC-USD' })).toBe('现货')
    expect(kindName({ kind: 'crypto', symbol: 'okx/usd_m/BTCUSDT' })).toBe('永续')
  })
  it('流名：别家的品种段是完整键（大小写原样），币安照旧小写', () => {
    expect(streamName.kline('okx/usd_m/BTCUSDT', '1h')).toBe('okx/usd_m/BTCUSDT@kline_1h')
    expect(streamName.ticker('BTCUSDT')).toBe('btcusdt@ticker')
    expect(symbolOfStream('hyperliquid/usd_m/KPEPE@ticker')).toBe('hyperliquid/usd_m/KPEPE')
    expect(symbolOfStream('btcusdt@kline_1m')).toBe('BTCUSDT')
  })
})

describe('注册表：行情 + 订单流一张表', () => {
  it('五家都有行情面；缩写 / 全名 / 计价', () => {
    // 行情面的顺序和 iOS `VenueRegistry.all` 一致（币安 · OKX · Bybit · Hyperliquid · Coinbase）；
    // 订单流的合并顺序 `VENUE_LIST` 是服务端读数 / 热力通道的下标，两者成员相同、顺序各管各的。
    expect(MARKET_VENUES.map(v => v.key)).toEqual(['binance', 'okx', 'bybit', 'hyperliquid', 'coinbase'])
    expect([...MARKET_VENUES.map(v => v.key)].sort()).toEqual([...VENUE_LIST.map(v => v.key)].sort())
    expect(['BTCUSDT', 'okx/usd_m/BTCUSDT', 'bybit/usd_m/BTCUSDT', 'hyperliquid/usd_m/BTC', 'coinbase/spot/BTC-USD', 'DXY'].map(venueLabel)).toEqual(['币安', 'OKX', 'Bybit', 'HL', 'CB', ''])
    expect(venueName('hyperliquid')).toBe('Hyperliquid')
    expect(marketOf('okx/usd_m/BTCUSDT')?.quote).toBe('USDT')
    expect(marketOf('hyperliquid/usd_m/BTC')?.quote).toBe('USDC')
    // 费率一期多长：Hyperliquid 每小时，别家不给 = 8 小时
    expect(fundingPeriodOf('hyperliquid/usd_m/BTC')).toBe(36e5)
    expect(['BTCUSDT', 'okx/usd_m/BTCUSDT', 'bybit/usd_m/BTCUSDT', 'coinbase/spot/BTC-USD', 'DXY'].map(fundingPeriodOf)).toEqual(Array(5).fill(8 * 36e5))
    expect(marketOf('coinbase/usd_m/BTC-USD')).toBeUndefined()   // market 段对不上不认
    expect(marketOf('DXY')).toBeUndefined()
  })
  it('键形状和服务端 sync_validation identity 同一规则', () => {
    expect(symbolOk('okx/usd_m/BTCUSDT')).toBe(true)
    expect(symbolOk('okx/usd_m/BTC-USDT-SWAP')).toBe(false)
    expect(symbolOk('bybit/usd_m/1000PEPEUSDT')).toBe(true)
    expect(symbolOk('bybit/usd_m/BTCUSD')).toBe(false)
    expect(symbolOk('hyperliquid/usd_m/KPEPE')).toBe(true)
    expect(symbolOk('hyperliquid/usd_m/kPEPE')).toBe(false)
    expect(symbolOk('coinbase/spot/BTC-USD')).toBe(true)
    expect(symbolOk('coinbase/spot/BTC-USDC')).toBe(false)
    expect(symbolOk('ftx/usd_m/BTCUSDT')).toBe(false)
  })
  it('周期：原生档直接要；没有的拿原生档并（OKX / Bybit 8 时 ← 4 时、HL 6 时 ← 2 时、CB 周 ← 日）', () => {
    expect(intervalPlan(okxMarket, '1h')).toEqual({ native: true })
    expect(intervalPlan(okxMarket, '8h')).toEqual({ base: '4h' })
    expect(intervalPlan(bybitMarket, '8h')).toEqual({ base: '4h' })
    expect(intervalPlan(hlMarket, '6h')).toEqual({ base: '2h' })
    expect(intervalPlan(hlMarket, '8h')).toEqual({ native: true })
    expect(intervalPlan(cbMarket, '1w')).toEqual({ base: '1d' })
    expect(intervalPlan(cbMarket, '3m')).toEqual({ base: '1m' })
  })
  it('marketKlines：8 时由 4 时并，格头按 UTC 0/8/16 点；往前翻那页第一格是半截的丢掉', async () => {
    const H4 = 4 * 3600e3, t0 = Date.UTC(2026, 9, 1, 4)   // 04:00 开始：00:00 那一格是半截
    const raw: Bar[] = Array.from({ length: 6 }, (_, i) => ({ t: t0 + i * H4, o: i + 1, h: i + 2, l: i, c: i + 1.5, v: 10 }))
    const spy = vi.spyOn(okxMarket, 'klines').mockResolvedValue(raw)
    const bars = await marketKlines('okx/usd_m/BTCUSDT', '8h', { limit: 2, end: t0 + 6 * H4 })
    expect(spy).toHaveBeenCalledWith('okx/usd_m/BTCUSDT', '4h', { limit: 4, end: t0 + 6 * H4 }, undefined)
    expect(bars.map(b => new Date(b.t).getUTCHours())).toEqual([8, 16, 0])
    expect(bars[0]).toMatchObject({ o: 2, h: 4, l: 1, c: 3.5, v: 20 })
  })
  it('周线从周一 00:00 UTC 起、月线按自然月', () => {
    const mon = Date.UTC(2026, 9, 5)   // 2026-10-05 周一
    expect(bucketOf(mon + 3 * 864e5, '1w')).toBe(mon)
    expect((mon - WEEK_OFFSET) % (7 * 864e5)).toBe(0)
    expect(bucketOf(Date.UTC(2026, 9, 31, 12), '1M')).toBe(Date.UTC(2026, 9, 1))
    const days: Bar[] = [Date.UTC(2026, 8, 30), Date.UTC(2026, 9, 1), Date.UTC(2026, 9, 2)].map((t, i) => ({ t, o: i, h: i, l: i, c: i, v: 1 }))
    expect(aggregateBars(days, '1M').map(b => b.t)).toEqual([Date.UTC(2026, 8, 1), Date.UTC(2026, 9, 1)])
  })
})

describe('OKX 解码', () => {
  const INST = { code: '0', msg: '', data: [
    { instId: 'BTC-USDT-SWAP', instType: 'SWAP', settleCcy: 'USDT', ctType: 'linear', tickSz: '0.1', state: 'live', listTime: '1606468572000' },
    { instId: 'ETH-USD-SWAP', instType: 'SWAP', settleCcy: 'ETH', ctType: 'inverse', tickSz: '0.01', state: 'live' },
    { instId: 'NEW-USDT-SWAP', instType: 'SWAP', settleCcy: 'USDT', ctType: 'linear', tickSz: '0.0001', state: 'preopen' },
  ] }
  it('品种表：只收 USDT 线性永续、在交易的；键是币安形状，instId 互译', () => {
    const list = decodeOkxInstruments(INST)
    expect(list.map(s => s.symbol)).toEqual(['okx/usd_m/BTCUSDT'])
    expect(list[0]).toMatchObject({ venue: 'okx', quote: 'USDT', raw: 'BTC-USDT-SWAP', base: 'BTC', dec: 1, onboard: 1606468572000 })
    expect(okxInstId('okx/usd_m/BTCUSDT')).toBe('BTC-USDT-SWAP')
    expect(okxKeyOf('BTC-USDT-SWAP')).toBe('okx/usd_m/BTCUSDT')
    expect(okxKeyOf('BTC-USDT')).toBeNull()
    expect(() => decodeOkxInstruments({ code: '50011', msg: 'Too Many Requests', data: [] })).toThrow(/50011/)
  })
  it('24h 行情：额 = 币数 × 最新价（近似），涨跌幅相对 open24h', () => {
    const [q] = decodeOkxTickers({ code: '0', data: [{ instId: 'BTC-USDT-SWAP', last: '110', open24h: '100', high24h: '120', low24h: '90', vol24h: '5000', volCcy24h: '50', ts: '1700000000000' }] })
    expect(q).toEqual({ key: 'okx/usd_m/BTCUSDT', price: 110, open: 100, hi: 120, lo: 90, pct: 10.000000000000009, chg: 10, vol: 5500, at: 1700000000000 })
  })
  it('K 线新的在前 → 倒成升序；额用 volCcyQuote、量用 volCcy', () => {
    const bars = decodeOkxCandles({ code: '0', data: [['1700003600000', '2', '3', '1', '2.5', '100', '10', '25', '0'], ['1700000000000', '1', '2', '0.5', '1.5', '80', '8', '12', '1']] })
    expect(bars).toEqual([{ t: 1700000000000, o: 1, h: 2, l: 0.5, c: 1.5, v: 12, bv: 8 }, { t: 1700003600000, o: 2, h: 3, l: 1, c: 2.5, v: 25, bv: 10 }])
  })
  it('K 线按 UTC 对齐的 bar 要（1Dutc，不是默认 UTC+8 的 1D）；首屏一发 candles，往前翻走 history-candles', async () => {
    const urls: string[] = []
    vi.stubGlobal('fetch', vi.fn(async (u: string) => { urls.push(u); return new Response(JSON.stringify({ code: '0', data: [] }), { status: 200 }) }))
    await okxMarket.klines('okx/usd_m/BTCUSDT', '1d', { limit: 1500 })
    await okxMarket.klines('okx/usd_m/BTCUSDT', '6h', { limit: 100, end: 1700000000000 })
    expect(urls[0]).toBe('https://www.okx.com/api/v5/market/candles?instId=BTC-USDT-SWAP&bar=1Dutc&limit=300')
    expect(urls[1]).toBe('https://www.okx.com/api/v5/market/history-candles?instId=BTC-USDT-SWAP&bar=6Hutc&limit=100&after=1700000000000')
  })
  it('推送：tickers / candle（business）/ trades / mark-price / funding-rate；pong、回执回空', () => {
    expect(decodeOkxPush('pong')).toEqual([])
    expect(decodeOkxPush(JSON.stringify({ event: 'subscribe', arg: { channel: 'tickers', instId: 'BTC-USDT-SWAP' } }))).toEqual([])
    const k = decodeOkxPush(JSON.stringify({ arg: { channel: 'candle1Dutc', instId: 'BTC-USDT-SWAP' }, data: [['1700006400000', '1', '2', '0.5', '1.5', '9', '3', '4.5', '0']] }))
    expect(k).toEqual([{ type: 'kline', key: 'okx/usd_m/BTCUSDT', iv: '1d', bar: { t: 1700006400000, o: 1, h: 2, l: 0.5, c: 1.5, v: 4.5, bv: 3 } }])
    const t = decodeOkxPush(JSON.stringify({ arg: { channel: 'trades', instId: 'BTC-USDT-SWAP' }, data: [{ instId: 'BTC-USDT-SWAP', tradeId: '1', px: '100', sz: '2', side: 'sell', ts: '5' }] }))
    expect(t).toEqual([{ type: 'trade', key: 'okx/usd_m/BTCUSDT', price: 100, qty: 2, t: 5, sell: true }])
    expect(decodeOkxPush(JSON.stringify({ arg: { channel: 'mark-price', instId: 'BTC-USDT-SWAP' }, data: [{ instId: 'BTC-USDT-SWAP', markPx: '99.5', ts: '6' }] })))
      .toEqual([{ type: 'quote', quote: { key: 'okx/usd_m/BTCUSDT', mark: 99.5, at: 6 } }])
    expect(decodeOkxPush(JSON.stringify({ arg: { channel: 'funding-rate', instId: 'BTC-USDT-SWAP' }, data: [{ fundingRate: '0.0001', fundingTime: '1700028800000', ts: '7' }] })))
      .toEqual([{ type: 'quote', quote: { key: 'okx/usd_m/BTCUSDT', fr: 0.0001, nextFunding: 1700028800000, at: 7 } }])
  })
})

describe('Bybit 解码', () => {
  it('品种表：USDT 线性永续、Trading；1000PEPEUSDT 原样', () => {
    const list = decodeBybitInstruments({ retCode: 0, result: { list: [
      { symbol: '1000PEPEUSDT', contractType: 'LinearPerpetual', status: 'Trading', baseCoin: '1000PEPE', quoteCoin: 'USDT', launchTime: '1683000000000', priceFilter: { tickSize: '0.0000001' } },
      { symbol: 'BTCPERP', contractType: 'LinearPerpetual', status: 'Trading', quoteCoin: 'USDC', priceFilter: { tickSize: '0.5' } },
      { symbol: 'BTCUSDT-26DEC25', contractType: 'LinearFutures', status: 'Trading', quoteCoin: 'USDT', priceFilter: { tickSize: '0.1' } },
    ], nextPageCursor: '' } })
    expect(list.map(s => [s.symbol, s.base, s.dec])).toEqual([['bybit/usd_m/1000PEPEUSDT', 'PEPE', 7]])
  })
  it('整表行情一条就有价、额、标记价、指数价、持仓量、费率；price24hPcnt 是小数', () => {
    const [q] = decodeBybitTickers({ retCode: 0, time: 1700000000000, result: { list: [{ symbol: 'BTCUSDT', lastPrice: '101', prevPrice24h: '100', price24hPcnt: '0.01', highPrice24h: '105', lowPrice24h: '95', turnover24h: '1000000', volume24h: '10000', markPrice: '101.1', indexPrice: '101.2', openInterest: '500', fundingRate: '0.0001', nextFundingTime: '1700028800000' }] } })
    expect(q).toEqual({ key: 'bybit/usd_m/BTCUSDT', price: 101, open: 100, hi: 105, lo: 95, pct: 1, chg: 1, vol: 1000000, mark: 101.1, index: 101.2, fr: 0.0001, nextFunding: 1700028800000, oi: 500, at: 1700000000000 })
  })
  it('K 线新的在前 → 升序；额 turnover、量 volume', () => {
    expect(decodeBybitKlines({ retCode: 0, result: { list: [['120000', '2', '3', '1', '2', '5', '10'], ['60000', '1', '2', '1', '2', '4', '8']] } }))
      .toEqual([{ t: 60000, o: 1, h: 2, l: 1, c: 2, v: 8, bv: 4 }, { t: 120000, o: 2, h: 3, l: 1, c: 2, v: 10, bv: 5 }])
  })
  it('tickers 推送：snapshot 打底、delta 只带变了的字段，按品种合并后再出行情；没底的 delta 不出', () => {
    const dec = bybitDecoder()
    expect(dec(JSON.stringify({ topic: 'tickers.BTCUSDT', type: 'delta', ts: 1, data: { symbol: 'BTCUSDT', lastPrice: '1' } }))).toEqual([])
    const a = dec(JSON.stringify({ topic: 'tickers.BTCUSDT', type: 'snapshot', ts: 10, data: { symbol: 'BTCUSDT', lastPrice: '100', prevPrice24h: '90', price24hPcnt: '0.111', turnover24h: '5', markPrice: '100.5', fundingRate: '0.0002', openInterest: '7' } }))
    expect(a[0]).toMatchObject({ type: 'quote', quote: { key: 'bybit/usd_m/BTCUSDT', price: 100, mark: 100.5, fr: 0.0002, oi: 7, at: 10 } })
    const b = dec(JSON.stringify({ topic: 'tickers.BTCUSDT', type: 'delta', ts: 11, data: { symbol: 'BTCUSDT', markPrice: '101' } }))
    expect(b[0]).toMatchObject({ type: 'quote', quote: { price: 100, open: 90, mark: 101, fr: 0.0002, oi: 7, at: 11 } })
    expect(dec(JSON.stringify({ success: true, ret_msg: 'pong', op: 'ping' }))).toEqual([])
  })
  it('kline / publicTrade 推送', () => {
    const dec = bybitDecoder()
    expect(dec(JSON.stringify({ topic: 'kline.60.BTCUSDT', data: [{ start: 3600000, end: 7199999, interval: '60', open: '1', close: '2', high: '3', low: '0.5', volume: '4', turnover: '8', confirm: false, timestamp: 5 }] })))
      .toEqual([{ type: 'kline', key: 'bybit/usd_m/BTCUSDT', iv: '1h', bar: { t: 3600000, o: 1, h: 3, l: 0.5, c: 2, v: 8, bv: 4 } }])
    expect(dec(JSON.stringify({ topic: 'publicTrade.BTCUSDT', data: [{ T: 9, s: 'BTCUSDT', S: 'Buy', v: '0.5', p: '100', i: 'x' }] })))
      .toEqual([{ type: 'trade', key: 'bybit/usd_m/BTCUSDT', price: 100, qty: 0.5, t: 9, sell: false }])
  })
})

describe('Hyperliquid 解码', () => {
  const BODY = [
    { universe: [{ name: 'BTC', szDecimals: 5, maxLeverage: 40 }, { name: 'kPEPE', szDecimals: 0, maxLeverage: 10 }, { name: 'OLD', szDecimals: 1, isDelisted: true }] },
    [
      { funding: '0.0000125', openInterest: '100', prevDayPx: '100', dayNtlVlm: '1000000', markPx: '110', midPx: '110.5', oraclePx: '109.9' },
      { funding: '-0.00001', openInterest: '5000', prevDayPx: '0.01', dayNtlVlm: '2000', markPx: '0.011', midPx: null, oraclePx: '0.011' },
      { funding: '0', openInterest: '0', prevDayPx: '1', dayNtlVlm: '0', markPx: '1' },
    ],
  ]
  it('品种表与整表行情同一次 metaAndAssetCtxs；kPEPE 进键大写 KPEPE、原名留着发请求用；下架的不收', () => {
    const list = decodeHlUniverse(BODY)
    expect(list.map(s => [s.symbol, s.raw, s.base, s.title, s.dec, s.quote])).toEqual([
      ['hyperliquid/usd_m/BTC', 'BTC', 'BTC', 'BTC', 1, 'USDC'],
      ['hyperliquid/usd_m/KPEPE', 'kPEPE', 'PEPE', 'kPEPE', 6, 'USDC'],
    ])
    expect(hlCoin('hyperliquid/usd_m/KPEPE')).toBe('kPEPE')
    const q = decodeHlCtxs(BODY, Date.UTC(2026, 9, 8, 3, 20))
    expect(q[0]).toMatchObject({ key: 'hyperliquid/usd_m/BTC', price: 110.5, open: 100, vol: 1000000, mark: 110, index: 109.9, fr: 0.0000125, oi: 100, nextFunding: Date.UTC(2026, 9, 8, 4) })
    expect(q[1]).toMatchObject({ key: 'hyperliquid/usd_m/KPEPE', price: 0.011 })   // 没有 midPx 用 markPx
    expect(nextHour(Date.UTC(2026, 9, 8, 3, 0))).toBe(Date.UTC(2026, 9, 8, 4))
  })
  it('candleSnapshot 按起止要、发原名；额 ≈ 量 × 收盘', async () => {
    decodeHlUniverse(BODY)
    const bodies: unknown[] = []
    vi.stubGlobal('fetch', vi.fn(async (_u: string, init: RequestInit) => { bodies.push(JSON.parse(String(init.body))); return new Response(JSON.stringify([{ t: 60000, T: 119999, s: 'kPEPE', i: '1m', o: '1', c: '2', h: '3', l: '0.5', v: '10', n: 4 }]), { status: 200 }) }))
    const bars = await hlMarket.klines('hyperliquid/usd_m/KPEPE', '1m', { limit: 10, end: 600000 })
    expect(bodies[0]).toEqual({ type: 'candleSnapshot', req: { coin: 'kPEPE', interval: '1m', startTime: 0, endTime: 599999 } })
    expect(bars).toEqual([{ t: 60000, o: 1, h: 3, l: 0.5, c: 2, v: 20, bv: 10 }])
    expect(decodeHlCandles('bad')).toEqual([])
  })
  it('推送：candle / trades / activeAssetCtx 的大写 coin 译回同一个键；pong 回空', () => {
    expect(decodeHlPush(JSON.stringify({ channel: 'pong' }))).toEqual([])
    expect(decodeHlPush(JSON.stringify({ channel: 'candle', data: { t: 60000, T: 119999, s: 'kPEPE', i: '1m', o: '1', c: '2', h: '3', l: '0.5', v: '1', n: 1 } }))[0])
      .toMatchObject({ type: 'kline', key: 'hyperliquid/usd_m/KPEPE', iv: '1m' })
    expect(decodeHlPush(JSON.stringify({ channel: 'trades', data: [{ coin: 'BTC', side: 'A', px: '100', sz: '1', time: 7, tid: 1 }] })))
      .toEqual([{ type: 'trade', key: 'hyperliquid/usd_m/BTC', price: 100, qty: 1, t: 7, sell: true }])
    expect(decodeHlPush(JSON.stringify({ channel: 'activeAssetCtx', data: { coin: 'kPEPE', ctx: { funding: '0.00001', openInterest: '9', prevDayPx: '0.01', dayNtlVlm: '5', markPx: '0.012', midPx: '0.0121', oraclePx: '0.012' } } }))[0])
      .toMatchObject({ type: 'quote', quote: { key: 'hyperliquid/usd_m/KPEPE', price: 0.0121, mark: 0.012, oi: 9 } })
  })
})

describe('Coinbase 现货解码', () => {
  const PRODUCTS = { products: [
    { product_id: 'BTC-USD', price: '110', price_percentage_change_24h: '10', volume_24h: '2', quote_increment: '0.01', quote_currency_id: 'USD', status: 'online', trading_disabled: false, product_type: 'SPOT' },
    { product_id: 'BTC-EUR', price: '100', status: 'online', product_type: 'SPOT', quote_increment: '0.01' },
    { product_id: 'XYZ-USD', price: '1', status: 'delisted', product_type: 'SPOT', quote_increment: '0.01' },
  ] }
  it('品种表与整表行情同一次 products；只收 USD、在线可交易；额 = 量 × 价', () => {
    expect(decodeCbProducts(PRODUCTS).map(s => [s.symbol, s.base, s.quote, s.dec])).toEqual([['coinbase/spot/BTC-USD', 'BTC', 'USD', 2]])
    const [q] = decodeCbQuotes(PRODUCTS, 5)
    expect(q).toMatchObject({ key: 'coinbase/spot/BTC-USD', price: 110, pct: 10, vol: 220, at: 5 })
    expect(q.open).toBeCloseTo(100)
  })
  it('K 线新的在前（秒）→ 升序毫秒', () => {
    expect(decodeCbCandles({ candles: [{ start: '120', low: '1', high: '3', open: '2', close: '2', volume: '5' }, { start: '60', low: '1', high: '2', open: '1', close: '2', volume: '4' }] }).map(b => [b.t, b.v]))
      .toEqual([[60000, 8], [120000, 10]])
  })
  it('推送：ticker → 行情、market_trades → 逐笔（BUY = 主动买）', () => {
    expect(decodeCbPush(JSON.stringify({ channel: 'ticker', timestamp: '2026-10-08T00:00:00Z', events: [{ type: 'update', tickers: [{ product_id: 'BTC-USD', price: '100', volume_24_h: '3', price_percent_chg_24_h: '0', low_24_h: '90', high_24_h: '110' }] }] }))[0])
      .toMatchObject({ type: 'quote', quote: { key: 'coinbase/spot/BTC-USD', price: 100, vol: 300, hi: 110, lo: 90 } })
    expect(decodeCbPush(JSON.stringify({ channel: 'market_trades', events: [{ type: 'update', trades: [{ product_id: 'BTC-USD', price: '100', size: '0.1', side: 'BUY', time: '2026-10-08T00:00:01Z' }] }] })))
      .toEqual([{ type: 'trade', key: 'coinbase/spot/BTC-USD', price: 100, qty: 0.1, t: Date.parse('2026-10-08T00:00:01Z'), sell: false }])
    expect(decodeCbPush(JSON.stringify({ channel: 'heartbeats', events: [] }))).toEqual([])
  })
})

describe('搜索按交易所分组', () => {
  const mk = (symbol: string, code: string, vol: number): Sym => ({ symbol, venue: parseKey(symbol).venue, quote: 'USDT', base: code, code, cn: '', kind: 'crypto', dec: 2, color: '', price: 1, chg: 0, pct: 0, vol, fr: null, nextFunding: null })
  const order = VENUE_LIST.map(v => v.key).concat('macro')
  it('一家一组；组内按匹配档再按成交额；组序先按组内最好匹配档、同档按注册表顺序；每组各自封顶', () => {
    const list = [
      mk('okx/usd_m/BTCUSDT', 'BTC', 5), mk('okx/usd_m/BTCDOMUSDT', 'BTCDOM', 9),
      mk('BTCUSDT', 'BTC', 10), mk('BTCDOMUSDT', 'BTCDOM', 1),
      mk('bybit/usd_m/WBTCUSDT', 'WBTC', 100),
      mk('hyperliquid/usd_m/BTC', 'BTC', 1),
    ]
    const g = groupSearch(list, 'btc', order, () => false, 1)
    expect(g.map(x => x.venue)).toEqual(['binance', 'okx', 'hyperliquid', 'bybit'])   // 三家都有完全匹配，同档按注册表；Bybit 只有包含
    expect(g.map(x => x.items.map(s => s.symbol))).toEqual([['BTCUSDT'], ['okx/usd_m/BTCUSDT'], ['hyperliquid/usd_m/BTC'], ['bybit/usd_m/WBTCUSDT']])
    expect(groupSearch(list, 'btc', order, () => false, 5)[0].items.map(s => s.symbol)).toEqual(['BTCUSDT', 'BTCDOMUSDT'])
  })
})

describe('一家一把限流器（market/limit.ts），按各家官方口径', () => {
  const OKXC = 'https://www.okx.com/api/v5/market/candles?instId=BTC-USDT-SWAP', OKXT = 'https://www.okx.com/api/v5/market/tickers?instType=SWAP'
  const OKXM = 'https://www.okx.com/api/v5/public/mark-price?instType=SWAP&instId=BTC-USDT-SWAP'
  it('OKX 按接口各算各的（2 秒窗口，官方的一半：candles 20、mark-price 5、其余 10）', () => {
    const g = gateOf('okx')!
    for (let i = 0; i < 20; i++) expect(g.take(0, false, 1, OKXC)).toBe(0)
    expect(g.take(0, false, 1, OKXC)).toBe(2000)
    for (let i = 0; i < 10; i++) expect(g.take(0, false, 1, OKXT)).toBe(0)   // candles 满了不连累 tickers
    expect(g.take(0, false, 1, OKXT)).toBeGreaterThan(0)
    for (let i = 0; i < 5; i++) expect(g.take(0, false, 1, OKXM)).toBe(0)
    expect(g.take(0, false, 1, OKXM)).toBeGreaterThan(0)
    expect(g.take(2000, false, 1, OKXC)).toBe(0)
  })
  it('Bybit 整个 IP 所有接口共用一个 5 秒窗口（官方 600，取 300）', () => {
    const g = gateOf('bybit')!
    for (let i = 0; i < 300; i++) g.take(i, false, 1, i % 2 ? 'https://api.bybit.com/v5/market/kline' : 'https://api.bybit.com/v5/market/tickers')
    expect(g.usedOf(300)).toBe(300)
    expect(g.take(300, false, 1, 'https://api.bybit.com/v5/market/instruments-info')).toBeGreaterThan(0)
  })
  it('Hyperliquid 按权重（官方 1200 / 分钟，取 600）：info 20、candleSnapshot 20 + 每 60 根 1、allMids 2', () => {
    const g = gateOf('hyperliquid')!
    expect(hlWeight('', { type: 'metaAndAssetCtxs' })).toBe(20)
    expect(hlWeight('', { type: 'allMids' })).toBe(2)
    expect(hlWeight('', { type: 'candleSnapshot', req: { coin: 'BTC', interval: '1m', startTime: 0, endTime: 1500 * 60_000 } })).toBe(45)
    for (let i = 0; i < 30; i++) expect(g.take(0, false, 1, 'https://api.hyperliquid.xyz/info', 20)).toBe(0)
    expect(g.take(0, false, 1, 'https://api.hyperliquid.xyz/info', 2)).toBe(60_000)
  })
  it('Coinbase 公开接口按次（官方 10 次 / 秒，取 5）', () => {
    const g = gateOf('coinbase')!
    for (let i = 0; i < 5; i++) expect(g.take(0, false, 1, 'https://api.coinbase.com/api/v3/brokerage/market/products')).toBe(0)
    expect(g.take(0, false, 1, 'https://api.coinbase.com/api/v3/brokerage/market/products')).toBe(1000)
  })
  it('OKX 回 429 只冷却 OKX：币安、Bybit 照发', async () => {
    noteStatus('https://www.okx.com/api/v5/market/tickers?instType=SWAP', 429, '3', 1000)
    expect(coolingFor('https://www.okx.com/api/v5/market/candles', 1000)).toBe(3000)
    expect(coolingFor('https://api.bybit.com/v5/market/tickers', 1000)).toBe(0)
    expect(coolingFor('https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT', 1000)).toBe(0)
    noteStatus('https://www.okx.com/api/v5/market/tickers?instType=SWAP', 429, '3', Date.now())
    await expect(admit('https://www.okx.com/api/v5/market/candles')).rejects.toBeInstanceOf(RateLimited)
    await expect(admit('https://api.bybit.com/v5/market/tickers')).resolves.toBe(false)
  })
  it('直连与网关各一道；同一道上行情与订单流共用', () => {
    const okx = gateOf('okx')!
    okx.noteStatus(429, '5', 0, true)
    expect(okx.coolingFor(0, true)).toBe(5000)
    expect(okx.coolingFor(0, false)).toBe(0)
    for (let i = 0; i < 20; i++) okx.take(0, true, 1, OKXC)
    expect(okx.take(0, false, 1, OKXC)).toBe(0)
  })
})

describe('线路规矩：选网关就只走网关，选直连只直连，失败报错不切', () => {
  it('网关档 GET 改写成同源透传，POST 也是', async () => {
    const seen: string[] = []
    vi.stubGlobal('fetch', vi.fn(async (u: string) => { seen.push(u); return new Response('{"code":"0","data":[]}', { status: 200 }) }))
    S.route = 'gateway'
    await vget('https://www.okx.com/api/v5/market/tickers?instType=SWAP')
    await vpost('https://api.hyperliquid.xyz/info', { type: 'meta' })
    expect(seen).toEqual([
      'https://kanpan.43-160-232-253.sslip.io/v1/market/raw/api/v5/market/tickers?instType=SWAP&source=okx',
      'https://kanpan.43-160-232-253.sslip.io/v1/market/raw/info?source=hyperliquid',
    ])
  })
  it('直连失败就报错，不偷偷换网关；网关没开的地址直接报错', async () => {
    const f = vi.fn(async () => { throw new TypeError('Failed to fetch') })
    vi.stubGlobal('fetch', f)
    S.route = 'direct'
    await expect(vget('https://api.bybit.com/v5/market/tickers?category=linear')).rejects.toThrow(/Failed to fetch/)
    expect(f).toHaveBeenCalledTimes(1)
    S.route = 'gateway'
    await expect(vget('https://example.org/x')).rejects.toBeInstanceOf(NoGatewayRoute)
  })
})

describe('图表角标只按市场分（和 iOS 顶栏一致）', () => {
  it('缩写 + 计价币 + 永续 / 现货 / 指数；美股、大宗也写「永续」', async () => {
    const { chartSub } = await import('../src/ui/common')
    expect(chartSub('NVDAUSDT', { kind: 'us', quote: 'USDT' })).toBe('币安 USDT 永续')
    expect(chartSub('XAUUSDT', { kind: 'com', quote: 'USDT' })).toBe('币安 USDT 永续')
    expect(chartSub('coinbase/spot/BTC-USD', { kind: 'crypto', quote: 'USD' })).toBe('CB USD 现货')
    expect(chartSub('hyperliquid/usd_m/BTC', undefined)).toBe('HL USDC 永续')
    expect(chartSub('DXY', { kind: 'idx', macro: true })).toBe('指数')
  })
})

describe('主力订单流按 base 找簿：Hyperliquid 的 k 前缀 = 1000 枚', () => {
  it('原名 kPEPE / 大写键 KPEPE（币安有 1000PEPEUSDT）归到 PEPE × 1000；KAITO 这种真名不拆', async () => {
    const { normalizeBase, baseOfSymbol } = await import('../src/orderflow/settings')
    expect(normalizeBase('kPEPE')).toEqual({ base: 'PEPE', scale: 1000 })
    expect(normalizeBase('KAITO')).toEqual({ base: 'KAITO', scale: 1 })
    expect(normalizeBase('1000PEPE')).toEqual({ base: 'PEPE', scale: 1000 })
    const mk = (symbol: string, raw?: string): Sym => ({ symbol, venue: parseKey(symbol).venue, quote: 'USDC', raw, base: '', code: '', cn: '', kind: 'crypto', dec: 2, color: '', price: 1, chg: 0, pct: 0, vol: 0, fr: null, nextFunding: null })
    S.symbols = new Map([['hyperliquid/usd_m/KPEPE', mk('hyperliquid/usd_m/KPEPE', 'kPEPE')], ['hyperliquid/usd_m/KAITO', mk('hyperliquid/usd_m/KAITO', 'KAITO')]])
    expect(baseOfSymbol('hyperliquid/usd_m/KPEPE')).toEqual({ base: 'PEPE', scale: 1000 })
    expect(baseOfSymbol('hyperliquid/usd_m/KAITO')).toEqual({ base: 'KAITO', scale: 1 })
    // 表里没有原名时：只有币安表里有 1000<名>USDT 才拆
    S.symbols = new Map([['1000BONKUSDT', mk('1000BONKUSDT')]])
    expect(baseOfSymbol('hyperliquid/usd_m/KBONK')).toEqual({ base: 'BONK', scale: 1000 })
    expect(baseOfSymbol('hyperliquid/usd_m/KAITO')).toEqual({ base: 'KAITO', scale: 1 })
    expect(baseOfSymbol('1000PEPEUSDT')).toEqual({ base: 'PEPE', scale: 1000 })
    S.symbols = new Map()
  })
})
