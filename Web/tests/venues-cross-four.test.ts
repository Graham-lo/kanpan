/* 交叉 · 同一只币四家并存：BTCUSDT（币安）、okx/usd_m/BTCUSDT、bybit/usd_m/BTCUSDT、hyperliquid/usd_m/BTC（+ coinbase/spot/BTC-USD）
 * 同时在自选 / 提醒 / 对比 / 十六格里：
 *   流名不串、symbolOfStream 反查对、币安的进币安连接池、别家进各自那一家；
 *   品种表懒拉三家之后 S.symbols 不互相覆盖、价格各是各家的；推来的行情只落到自己那一行；
 *   同步编解码（电脑 sync/codec 与手机 m/app/syncCodec）每只往返一字不差，id 不撞；
 *   knownMissing 只对已到表的那一家判；
 *   订单流按 base 找簿：四只都是 BTC × 1；KPEPE / kPEPE / 1000PEPE 归 PEPE × 1000。 */
import { afterEach, describe, expect, it, vi } from 'vitest'
import { S } from '../src/market/state'
import { streamName, symbolOfStream } from '../src/market/stream'
import { isVenueStream, handle, planStreams } from '../src/market/venueStream'
import { knownMissing, loadVenue, resetVenuesForTest } from '../src/market/rest'
import { displayKey, parseKey, syncKeyOf, wireSymbol } from '../src/market/identity'
import { decodeAlerts, decodeDrawings, decodeFavorites, encodeAlerts, encodeDrawings, encodeFavorites, cleanCompare, alertId, drawingId, type Ctx } from '../src/sync/codec'
import * as MC from '../src/m/app/syncCodec'
import { makePriceAlert } from '../src/alerts/shape'
import { cleanCells } from '../src/app/layouts'
import { baseOfSymbol } from '../src/orderflow/settings'
import { primarySymbolOf } from '../src/orderflow/feed'
import { fallbackBooks, marketOf, venueLabel } from '../src/venues'
import { resetLimits } from '../src/market/limit'
import type { Sym } from '../src/market/symbols'
import type { Drawing } from '../src/chart/chart'

const FOUR = ['BTCUSDT', 'okx/usd_m/BTCUSDT', 'bybit/usd_m/BTCUSDT', 'hyperliquid/usd_m/BTC'] as const
const FIVE = [...FOUR, 'coinbase/spot/BTC-USD'] as const

const sym = (symbol: string, price: number, over: Partial<Sym> = {}): Sym => ({
  symbol, venue: parseKey(symbol).venue, quote: 'USDT', base: 'BTC', code: 'BTC', kind: 'crypto', cn: '比特币', dec: 1, color: '',
  price, chg: 0, pct: 0, vol: 0, fr: null, nextFunding: null, pxAt: 1, ...over,
})

afterEach(() => { S.symbols = new Map(); resetVenuesForTest(); resetLimits(); vi.unstubAllGlobals(); vi.restoreAllMocks(); S.live = null; S.route = 'direct' })

describe('流名：四家同一个币不串', () => {
  it('每一路流名不同；symbolOfStream 反查回同一个键；币安留在币安连接池、别家分到各自那一家', () => {
    const names = FIVE.flatMap(k => [streamName.kline(k, '1h'), streamName.ticker(k), streamName.mark(k), streamName.trade(k)])
    expect(new Set(names).size).toBe(names.length)
    for (const k of FIVE) for (const n of [streamName.kline(k, '1h'), streamName.ticker(k), streamName.mark(k), streamName.trade(k)]) {
      expect(symbolOfStream(n)).toBe(k)
      expect(isVenueStream(n)).toBe(k !== 'BTCUSDT')
    }
    expect(streamName.ticker('BTCUSDT')).toBe('btcusdt@ticker')
    const plan = planStreams(names.filter(isVenueStream))
    expect([...plan.topics.keys()].sort()).toEqual(['bybit', 'coinbase', 'hyperliquid', 'okx'])
    expect(plan.topics.get('okx')!.get('public')).toContain('tickers|BTC-USDT-SWAP')
    expect(plan.topics.get('bybit')!.get('linear')).toContain('tickers.BTCUSDT')
    expect(plan.topics.get('hyperliquid')!.get('main')).toContain('activeAssetCtx|BTC')
    expect(plan.topics.get('coinbase')!.get('main')).toContain('ticker|BTC-USD')
  })
  it('推来的行情只落到自己那一行（同一个价位、同一个 BTC，四家互不覆盖）', () => {
    S.symbols = new Map(FIVE.map((k, i) => [k, sym(k, 100 + i)]))
    handle({ type: 'quote', quote: { key: 'okx/usd_m/BTCUSDT', price: 200, at: 10 } })
    handle({ type: 'trade', key: 'hyperliquid/usd_m/BTC', price: 300, qty: 1, t: 10, sell: false })
    expect(FIVE.map(k => S.symbols.get(k)!.price)).toEqual([100, 200, 102, 300, 104])
  })
})

describe('品种表懒拉三家：S.symbols 不互相覆盖；knownMissing 只对已到表的那家判', () => {
  it('OKX / Bybit / Hyperliquid 各拉一遍，币安那一行原样；Coinbase 没拉不判缺', async () => {
    S.symbols = new Map([['BTCUSDT', sym('BTCUSDT', 100)]])
    S.live = true
    vi.stubGlobal('fetch', vi.fn(async (u: string, init?: RequestInit) => {
      const url = String(u)
      const j = (x: unknown) => new Response(JSON.stringify(x), { status: 200 })
      if (url.includes('okx.com') && url.includes('instruments')) return j({ code: '0', data: [{ instId: 'BTC-USDT-SWAP', settleCcy: 'USDT', ctType: 'linear', tickSz: '0.1', state: 'live' }] })
      if (url.includes('okx.com')) return j({ code: '0', data: [{ instId: 'BTC-USDT-SWAP', last: '201', ts: '5' }] })
      if (url.includes('bybit.com') && url.includes('instruments')) return j({ retCode: 0, result: { list: [{ symbol: 'BTCUSDT', contractType: 'LinearPerpetual', status: 'Trading', quoteCoin: 'USDT', priceFilter: { tickSize: '0.1' } }] } })
      if (url.includes('bybit.com')) return j({ retCode: 0, time: 5, result: { list: [{ symbol: 'BTCUSDT', lastPrice: '202' }] } })
      if (url.includes('hyperliquid')) { expect(JSON.parse(String(init?.body)).type).toBe('metaAndAssetCtxs'); return j([{ universe: [{ name: 'BTC', szDecimals: 5 }] }, [{ markPx: '203', midPx: '203' }]]) }
      throw new Error('不该出网 ' + url)
    }))
    await Promise.all([loadVenue('okx'), loadVenue('bybit'), loadVenue('hyperliquid')])
    expect(FOUR.map(k => S.symbols.get(k)?.price)).toEqual([100, 201, 202, 203])
    expect(new Set(FOUR.map(k => S.symbols.get(k))).size).toBe(4)
    expect(FOUR.map(k => S.symbols.get(k)!.venue)).toEqual(['binance', 'okx', 'bybit', 'hyperliquid'])
    expect(FOUR.map(venueLabel)).toEqual(['币安', 'OKX', 'Bybit', 'HL'])
    // 已到表那几家：表里没有的才算「确定不存在」；没拉的 Coinbase 不判
    expect(knownMissing('okx/usd_m/ETHUSDT')).toBe(true)
    expect(knownMissing('bybit/usd_m/ETHUSDT')).toBe(true)
    expect(knownMissing('hyperliquid/usd_m/ETH')).toBe(true)
    expect(knownMissing('coinbase/spot/BTC-USD')).toBe(false)
    expect(knownMissing('coinbase/spot/ETH-USD')).toBe(false)
    for (const k of FOUR) expect(knownMissing(k)).toBe(false)
    // 认不出的交易所 / 不存在的组合：确定开不了
    expect(knownMissing('kraken/spot/BTC-USD')).toBe(true)
    expect(knownMissing('coinbase/usd_m/BTC-USD')).toBe(true)
  })
})

describe('同步编解码：每只往返一字不差，id 不撞', () => {
  const ctx: Ctx = { now: () => 1_700_000_000_000, kindOf: () => 'crypto', price: () => 100, label: (_s, p) => String(p) } as Ctx
  it('电脑：自选五家同一个币 + 美元指数，编码后解回来顺序与键不变', () => {
    const watch = { crypto: [...FIVE], us: [], com: [], idx: ['DXY'] }
    const objs = encodeFavorites(watch, [], ctx)
    expect(new Set(objs.map(o => o.id)).size).toBe(objs.length)
    expect(objs.map(o => o.id)).toEqual([...FIVE.map(syncKeyOf), 'macro/index/DXY'])
    expect(objs.map(o => [o.body.venue, o.body.market, o.body.symbol])).toEqual([
      ['binance', 'usd_m', 'BTCUSDT'], ['okx', 'usd_m', 'BTCUSDT'], ['bybit', 'usd_m', 'BTCUSDT'], ['hyperliquid', 'usd_m', 'BTC'], ['coinbase', 'spot', 'BTC-USD'], ['macro', 'index', 'DXY'],
    ])
    expect(decodeFavorites(objs, ctx)).toEqual({ crypto: [...FIVE], us: [], com: [], idx: ['DXY'] })
  })
  it('手机：同上', () => {
    const out = MC.encodeFavorites({ favorites: [...FIVE], groups: [], groupForSymbol: {} }, [], [])
    const live = out.filter(o => o.collection === 'favorites' && !o.deleted)
    expect(MC.decodeFavorites(live, [], { favorites: [], groups: [], groupForSymbol: {} }).favorites).toEqual([...FIVE])
  })
  it('画线：五家各一条同 id 的线，各进各的桶、解回来各回各家', () => {
    const d = (p: number): Drawing => ({ id: 'same', type: 'trend', pts: [{ t: 1_700_000_000_000, p }, { t: 1_700_003_600_000, p: p + 1 }], color: '#F23645', width: 2 })
    const book = Object.fromEntries(FIVE.map((k, i) => [k, [d(100 + i)]]))
    const objs = encodeDrawings(book, [])
    expect(objs.map(o => o.id)).toEqual(FIVE.map(k => drawingId(k, 'same')))
    expect(new Set(objs.map(o => o.id)).size).toBe(5)
    expect(decodeDrawings(objs, {})).toEqual(book)
  })
  it('提醒：五家各一条价格提醒，id 前缀不撞、正文 market / symbol 各是各家的，解回来键不变', () => {
    const alerts = FIVE.map((k, i) => makePriceAlert(k, 110 + i, 100, { now: 1_700_000_000_000 + i }))
    const objs = encodeAlerts(alerts, [])
    expect(new Set(objs.map(o => o.id)).size).toBe(5)
    expect(objs.map(o => o.id)).toEqual(alerts.map(a => alertId(a.symbol, a.id)))
    expect(objs.map(o => o.body.market)).toEqual(['binance/usd_m', 'okx/usd_m', 'bybit/usd_m', 'hyperliquid/usd_m', 'coinbase/spot'])
    expect(objs.map(o => o.body.symbol)).toEqual(['BTCUSDT', 'BTCUSDT', 'BTCUSDT', 'BTC', 'BTC-USD'])
    expect(decodeAlerts(objs, []).map(a => a.symbol)).toEqual([...FIVE])
  })
  it('对比：完整键、最多三只、不重复；裸代号按币安补全', () => {
    expect(cleanCompare([...FIVE])).toEqual(['binance/usd_m/BTCUSDT', 'okx/usd_m/BTCUSDT', 'bybit/usd_m/BTCUSDT'])
    expect(cleanCompare(['okx/usd_m/BTCUSDT', 'hyperliquid/usd_m/BTC', 'okx/usd_m/BTCUSDT', 'coinbase/spot/BTC-USD'])).toEqual(['okx/usd_m/BTCUSDT', 'hyperliquid/usd_m/BTC', 'coinbase/spot/BTC-USD'])
  })
  it('十六格：四家各四只原样留着；写成完整三段的币安 / 美元指数键收回成网页存的规范键（不然那一格拿完整键去要币安 K 线，本地就被拒）', () => {
    const cells = Array.from({ length: 16 }, (_, i) => ({ symbol: FOUR[i % 4], iv: '1h' }))
    expect(cleanCells(cells).map(c => c.symbol)).toEqual(cells.map(c => c.symbol))
    const odd = cleanCells([{ symbol: 'binance/usd_m/ETHUSDT', iv: '1h' }, { symbol: 'macro/index/DXY', iv: '1h' }, { symbol: 'okx/usd_m/BTCUSDT', iv: '4h' }])
    expect(odd.map(c => c.symbol)).toEqual(['ETHUSDT', 'DXY', 'okx/usd_m/BTCUSDT'])
    for (const c of odd) expect(c.symbol).toBe(displayKey(c.symbol))
  })
})

describe('订单流按 base 找簿（五家聚合）', () => {
  it('四只 BTC 都是 BTC × 1；参考簿代号都是 BTCUSDT；保底簿按 BTC 给（OKX 没有保底簿，同 iOS OrderFlowExchange）', () => {
    for (const k of FIVE) expect(baseOfSymbol(k)).toEqual({ base: 'BTC', scale: 1 })
    // 订单流按图上那只的代号段（大写）算参考簿：HL 的 BTC、CB 的 BTC-USD 原来原样拿去要币安日线（400）
    for (const k of FIVE) expect(primarySymbolOf(wireSymbol(k).toUpperCase(), 'BTC', 1)).toBe('BTCUSDT')
    expect(primarySymbolOf('KPEPE', 'PEPE', 1000)).toBe('1000PEPEUSDT')
    expect(primarySymbolOf('1000PEPEUSDT', 'PEPE', 1000)).toBe('1000PEPEUSDT')
    const books = fallbackBooks(primarySymbolOf('BTC-USD', 'BTC', 1), 'BTC', 1)
    expect(new Set(books.map(b => b.venue.exchange))).toEqual(new Set(['binance', 'coinbase', 'bybit', 'hyperliquid']))
    expect(books.filter(b => b.venue.exchange !== 'coinbase' && b.venue.product === 'usdtPerp').map(b => b.venue.instrument)).toEqual(['BTCUSDT', 'BTCUSDT', 'BTC'])
    const pepe = fallbackBooks(primarySymbolOf('KPEPE', 'PEPE', 1000), 'PEPE', 1000)
    expect(pepe.filter(b => b.venue.product === 'usdtPerp').map(b => b.venue.instrument)).toEqual(['1000PEPEUSDT', '1000PEPEUSDT', 'kPEPE'])
  })
  it('KPEPE（品种表原名 kPEPE / 表没到但币安有 1000PEPEUSDT）、kPEPE、1000PEPE（币安 / Bybit）都归 PEPE × 1000；OKX / Coinbase 的 PEPE 是 × 1', () => {
    S.symbols = new Map([['hyperliquid/usd_m/KPEPE', sym('hyperliquid/usd_m/KPEPE', 1, { raw: 'kPEPE' })]])
    expect(baseOfSymbol('hyperliquid/usd_m/KPEPE')).toEqual({ base: 'PEPE', scale: 1000 })
    S.symbols = new Map([['1000PEPEUSDT', sym('1000PEPEUSDT', 1)]])
    expect(baseOfSymbol('hyperliquid/usd_m/KPEPE')).toEqual({ base: 'PEPE', scale: 1000 })
    expect(baseOfSymbol('1000PEPEUSDT')).toEqual({ base: 'PEPE', scale: 1000 })
    expect(baseOfSymbol('bybit/usd_m/1000PEPEUSDT')).toEqual({ base: 'PEPE', scale: 1000 })
    expect(baseOfSymbol('okx/usd_m/PEPEUSDT')).toEqual({ base: 'PEPE', scale: 1 })
    expect(baseOfSymbol('coinbase/spot/PEPE-USD')).toEqual({ base: 'PEPE', scale: 1 })
    // 保底簿：图上 × 1000 时 HL 给 kPEPE、Bybit 给 1000PEPEUSDT
    const fb = fallbackBooks('1000PEPEUSDT', 'PEPE', 1000)
    expect(fb.find(b => b.venue.exchange === 'hyperliquid')!.venue.instrument).toBe('kPEPE')
  })
  it('四家的行情面各自能找到（marketOf 不串）', () => {
    expect(FIVE.map(k => marketOf(k)?.shortName)).toEqual(['币安', 'OKX', 'Bybit', 'HL', 'CB'])
  })
})
