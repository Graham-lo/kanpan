// 美元指数（DXY）当一只普通品种：路由、搜索、自选「指数」、对比白名单、同步编码、图上收掉的指标
import { describe, expect, it } from 'vitest'
import { MacroUnsupported, applyMacroTicker, isMacro, macroFallback, macroRewrite, syncKeyOf, venueMarketOf } from '../src/market/macro'
import { validMacroStream } from '../src/market/macroStream'
import { matchOne, normalize, rank, Tier } from '../src/m/model/search'
import { rankSearch, type Sym } from '../src/market/symbols'
import { addFavorite } from '../src/m/model/favorites'
import { compareSymbolOf } from '../src/m/chart/compare.source'
import { canonicalInstrument } from '../src/m/chart/draw/instrument'
import { alertMarketOf, decodeAlert, decodeFavorites, encodeAlerts, encodeFavorites, favId, webSymbol } from '../src/sync/codec'
import { makePriceAlert } from '../src/alerts/shape'
import { chartIndicatorsFor } from '../src/m/pages/chart/logic'
import { indFor } from '../src/chart/chart'
import type { SyncObject } from '../src/sync/types'
import { ctx } from './sync-fake'

const O = 'https://api.example'

describe('美元指数 · 取数路由', () => {
  it('K 线与 24h 行情改走 kanpan-api 的 macro 源，不碰币安', () => {
    expect(macroRewrite('https://fapi.binance.com/fapi/v1/klines?symbol=DXY&interval=1h&limit=500', O))
      .toBe(`${O}/v1/market/raw/klines?symbol=DXY&interval=1h&limit=500&source=macro`)
    expect(macroRewrite('https://fapi.binance.com/fapi/v1/ticker/24hr?symbol=DXY', O))
      .toBe(`${O}/v1/market/raw/ticker/24hr?symbol=DXY&source=macro`)
  })
  it('它没有的数据（持仓、资金费、深度）本地就拦下，别的品种原样不动', () => {
    expect(() => macroRewrite('https://fapi.binance.com/fapi/v1/openInterest?symbol=DXY', O)).toThrow(MacroUnsupported)
    expect(() => macroRewrite('https://fapi.binance.com/fapi/v1/depth?symbol=DXY&limit=20', O)).toThrow(MacroUnsupported)
    expect(macroRewrite('https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT&interval=1h', O)).toBeNull()
    expect(macroRewrite('https://fapi.binance.com/fapi/v1/klines?symbol=DXYUSDT&interval=1h', O)).toBeNull()
  })
  it('推送只认 ticker 与 K 线两种流', () => {
    expect(validMacroStream('dxy@ticker')).toBe(true)
    expect(validMacroStream('dxy@kline_15m')).toBe(true)
    expect(validMacroStream('dxy@markPrice@1s')).toBe(false)
    expect(validMacroStream('dxy@depth5')).toBe(false)
  })
  it('行情帧：涨跌照服务端原样用，成交量恒 0，marketState 决定休市', () => {
    const s = macroFallback()
    expect(applyMacroTicker(s, { lastPrice: '98.765', priceChange: '-0.123', priceChangePercent: '-0.124', openPrice: '98.8', highPrice: '99', lowPrice: '98.5', marketState: 'closed' }, 1000)).toBe(true)
    expect(s.price).toBe(98.765); expect(s.pct).toBe(-0.124); expect(s.vol).toBe(0); expect(s.closed).toBe(true)
    // 旧帧不覆盖价，但休市状态照认
    expect(applyMacroTicker(s, { lastPrice: '1', marketState: 'open' }, 10)).toBe(false)
    expect(s.price).toBe(98.765); expect(s.closed).toBe(false)
  })
  it('身份：DXY ↔ macro/index/DXY', () => {
    expect(isMacro('DXY')).toBe(true)
    expect(isMacro('macro/index/DXY')).toBe(true)
    expect(isMacro('DXYUSDT')).toBe(false)
    expect(syncKeyOf('DXY')).toBe('macro/index/DXY')
    expect(syncKeyOf('BTCUSDT')).toBe('binance/usd_m/BTCUSDT')
    expect(venueMarketOf('DXY')).toEqual({ venue: 'macro', market: 'index' })
    expect(canonicalInstrument('DXY')).toBe('macro/index/DXY')
  })
})

describe('美元指数 · 搜索', () => {
  const list = [
    { symbol: 'USDCUSDT', vol: 9e9, price: 1 },
    { symbol: 'BTCUSDT', vol: 8e9, price: 1 },
    { symbol: 'DXY', vol: 0, price: 98 },
  ]
  it('美元 / 美指 / 美元指数 / DXY / dxy / USD 都排第一（成交额为 0 也一样）', () => {
    for (const q of ['美元', '美指', '美元指数', 'DXY', 'dxy', 'USD', 'usd']) expect(rank(list, q)[0]?.item.symbol, q).toBe('DXY')
  })
  it('USD 整词算最匹配；打「US」不算', () => {
    expect(matchOne('DXY', 'DXY', normalize('USD'))?.tier).toBe(Tier.exact)
    expect(matchOne('DXY', 'DXY', normalize('US'))).toBeNull()
  })
  it('电脑搜索同一套', () => {
    const syms = [
      { symbol: 'USDCUSDT', code: 'USDC', cn: '', vol: 9e9 },
      { symbol: 'DXY', code: 'DXY', cn: '美元指数', vol: 0 },
    ] as Pick<Sym, 'symbol' | 'code' | 'cn' | 'vol'>[]
    expect(rankSearch(syms, 'USD')[0].symbol).toBe('DXY')
    expect(rankSearch(syms, '美元')[0].symbol).toBe('DXY')
  })
})

describe('美元指数 · 自选', () => {
  const prefs = () => ({
    favorites: ['BTCUSDT', 'NVDAUSDT'], recents: [],
    groups: [{ id: 'g1', name: '加密' }, { id: 'g2', name: '美股' }, { id: 'g3', name: '贵金属' }],
    groupForSymbol: { BTCUSDT: 'g1', NVDAUSDT: 'g2' } as Record<string, string>,
  })
  it('不论当前在哪个分类，星一点落进「指数」，分类建在美股后面', () => {
    const p = prefs() as unknown as Parameters<typeof addFavorite>[0]
    addFavorite(p, 'DXY', 'g1', { kind: 'idx', base: 'DXY' })
    const names = p.groups.map(g => g.name)
    expect(names).toEqual(['加密', '美股', '指数', '贵金属'])
    const idx = p.groups.find(g => g.name === '指数')!
    expect(p.groupForSymbol.DXY).toBe(idx.id)
    expect(p.favorites).toContain('DXY')
  })
  it('电脑同步：DXY 编码成 macro/index/DXY，解码回「指数」', () => {
    expect(webSymbol('DXY')).toBe(true)
    expect(favId('DXY')).toBe('macro/index/DXY')
    const out = encodeFavorites({ crypto: ['BTCUSDT'], us: [], idx: ['DXY'], com: [] }, [], ctx)
    const dxy = out.find(o => o.id === 'macro/index/DXY')!
    expect(dxy.body).toMatchObject({ symbol: 'DXY', venue: 'macro', market: 'index' })
    expect(decodeFavorites(out, ctx).idx).toEqual(['DXY'])
  })
})

describe('美元指数 · 对比与提醒', () => {
  it('对比白名单认 DXY', () => {
    expect(compareSymbolOf('DXY')).toBe('DXY')
    expect(compareSymbolOf('macro/index/DXY')).toBe('DXY')
  })
  it('价格提醒的市场是 macro/index，往返不丢', () => {
    expect(alertMarketOf('DXY')).toBe('macro/index')
    const a = makePriceAlert('DXY', 99.5, 98.7, { now: 1000, dec: 3 })
    const out = encodeAlerts([a], [] as SyncObject[])
    expect(out).toHaveLength(1)
    expect(out[0].id.startsWith('macro/index/DXY/')).toBe(true)
    expect(out[0].body.market).toBe('macro/index')
    const back = decodeAlert(out[0])
    expect(back?.symbol).toBe('DXY')
  })
})

describe('美元指数 · 图上收掉的指标（偏好不动）', () => {
  it('手机：成交量 / 均量 / VWAP / CVD / 合约衍生副图收掉，订单流不起', () => {
    const r = chartIndicatorsFor(true, ['MA', 'VWAP'], ['VOL', 'MACD', 'OI', 'CVD', 'RSI'])
    expect(r).toEqual({ overlays: ['MA'], subs: ['MACD', 'RSI'], orderFlow: false })
    expect(chartIndicatorsFor(false, ['MA', 'VWAP'], ['VOL'])).toEqual({ overlays: ['MA', 'VWAP'], subs: ['VOL'], orderFlow: true })
  })
  it('电脑：成交量、VWAP、成交量分布、持仓量、CVD 不画', () => {
    const want = { ma: true, ema: false, boll: false, vol: true, vwap: true, vpvr: true, subs: ['macd', 'oi', 'cvd', 'rsi'] } as Parameters<typeof indFor>[0]
    const r = indFor(want, 'DXY')
    expect(r.vol).toBe(false); expect(r.vwap).toBe(false); expect(r.vpvr).toBe(false)
    expect(r.subs).toEqual(['macd', 'rsi'])
    expect(want.vol).toBe(true)
    expect(indFor(want, 'BTCUSDT')).toBe(want)
  })
})

describe('美元指数 · 电脑图例不挂「币安」', async () => {
  const src = (await import('../src/pages/chart.ts?raw')).default as string
  it('图例副标题：macro 品种只写「指数」，币安品种照旧「币安永续」', () => {
    expect(src).toContain("${s?.macro ? '' : '币安'}${kindName(s)}")
    expect(src).not.toContain('· 币安${kindName(s)}`')
  })
})
