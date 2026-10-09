/* 手机网页版 · 多交易所（2026-10-08）：品种键、列表行缩写、顶部小字、搜索分组、自选分类、同步编解码 */
import { afterEach, describe, expect, it } from 'vitest'
import { S, type Sym } from '../src/market'
import { chartSub } from '../src/ui/common'
import { chartSubOf, normKey, openableKey, pairOf, rowMeta, venueCategory, venueLine, venueTagHTML } from '../src/m/model/symKey'
import { factsOf, listRowHTML, liuliRowHTML } from '../src/m/model/rowHTML'
import { groupRanked, groupTitle, previewQuota, rank, SEARCH_ORDER } from '../src/m/model/search'
import { buildSections, countText, marketOf as pickerMarket, type PickerSym } from '../src/m/model/picker'
import * as F from '../src/m/model/favorites'
import type { SymbolPrefs } from '../src/m/app/store'
import * as C from '../src/m/app/syncCodec'
import { syncableKey } from '../src/m/app/drawCodec'
import { compareTargets } from '../src/m/chart/compare.source'
import { liveOrCached, liveOf, tableLive } from '../src/m/model/quoteCache'
import { noticeSymbol } from '../src/m/model/listingNotices'
import { makePriceAlert } from '../src/alerts/shape'
import { alertId, decodeAlerts, encodeAlerts } from '../src/sync/codec'
import { wireSymbol } from '../src/market/identity'
import type { SyncObject } from '../src/sync/types'

const OKX = 'okx/usd_m/BTCUSDT'
const HL = 'hyperliquid/usd_m/KPEPE'
const CB = 'coinbase/spot/BTC-USD'
const BYBIT = 'bybit/usd_m/1000PEPEUSDT'

const sym = (symbol: string, over: Partial<Sym> = {}): Sym => ({
  symbol, venue: 'binance', quote: 'USDT', base: symbol.replace(/USDT$/, ''), code: symbol.replace(/USDT$/, ''), kind: 'crypto', cn: '', dec: 2, color: '#000',
  price: 1, chg: 0, pct: 0, vol: 1, fr: null, nextFunding: null, ...over,
})

afterEach(() => { S.symbols = new Map(); S.venues = {}; S.live = null })

describe('品种键归一（normKey）', () => {
  it('裸代号大写、完整键 venue / market 小写代号大写；币安与美元指数的完整键回裸代号', () => {
    expect(normKey(' btcusdt ')).toBe('BTCUSDT')
    expect(normKey('dxy')).toBe('DXY')
    expect(normKey('OKX/USD_M/btcusdt')).toBe(OKX)
    expect(normKey('coinbase/spot/btc-usd')).toBe(CB)
    expect(normKey('binance/usd_m/ethusdt')).toBe('ETHUSDT')
    expect(normKey('macro/index/DXY')).toBe('DXY')
    expect(normKey('')).toBe('')
  })
})

describe('列表行与顶部小字', () => {
  it('两截名字：币安按代号拆；别家按品种表 title / quote，表没到按键与注册表猜', () => {
    expect(pairOf('1000PEPEUSDT')).toEqual({ base: '1000PEPE', quote: 'USDT' })
    expect(pairOf('DXY')).toEqual({ base: 'DXY', quote: '' })
    expect(pairOf(OKX)).toEqual({ base: 'BTC', quote: 'USDT' })
    expect(pairOf(CB)).toEqual({ base: 'BTC', quote: 'USD' })
    expect(pairOf(HL)).toEqual({ base: 'KPEPE', quote: 'USDC' })
    expect(pairOf(HL, { title: 'kPEPE', quote: 'USDC' })).toEqual({ base: 'kPEPE', quote: 'USDC' })
  })
  it('名字前的灰小字缩写：币安 / OKX / Bybit / HL / CB，美元指数不带', () => {
    expect(venueTagHTML('BTCUSDT')).toBe('<span class="row-vtag">币安</span>')
    expect(venueTagHTML(OKX)).toContain('>OKX<')
    expect(venueTagHTML(BYBIT)).toContain('>Bybit<')
    expect(venueTagHTML(HL)).toContain('>HL<')
    expect(venueTagHTML(CB)).toContain('>CB<')
    expect(venueTagHTML('DXY')).toBe('')
  })
  it('搜索与板块行带缩写，自选连写品种和计价币；别家的名字照品种表写', () => {
    const f = factsOf(HL, sym(HL, { venue: 'hyperliquid', quote: 'USDC', title: 'kPEPE', base: 'PEPE' }))
    expect(f.base).toBe('kPEPE')
    expect(f.quote).toBe('USDC')
    expect(f.mark).toBe('PEPE')
    const sr = listRowHTML(f, { price: 1, pct: 1, meta: 'kPEPE 永续', fav: false })
    expect(sr).toContain('<span class="row-vtag">HL</span><span class="sr-base">kPEPE</span>')
    expect(sr).toContain(`data-sym="${HL}"`)
    const lr = liuliRowHTML(factsOf('BTCUSDT', sym('BTCUSDT')), { price: 1, pct: 1, vol: 1 }, true)
    expect(lr).toContain('<span class="row-vtag">币安</span><span class="lr-base">BTC</span>')
    const favorite = liuliRowHTML(f, { price: 1, pct: 1, vol: 1 }, true, { compactName: true })
    expect(favorite).toContain('<span class="lr-base">kPEPEUSDC</span>')
    expect(favorite).not.toContain('row-vtag')
    expect(favorite).toContain(`data-sym="${HL}"`)
    expect(liuliRowHTML(factsOf('DXY', sym('DXY', { kind: 'idx', macro: true, quote: '' })), { price: 1, pct: 1, vol: null }, true)).not.toContain('row-vtag')
  })
  it('顶部小字和电脑版 chartSub 一字不差：「币安 USDT 永续」「HL USDC 永续」「CB USD 现货」「指数」', () => {
    expect(chartSubOf('BTCUSDT')).toBe('币安 USDT 永续')
    expect(chartSubOf(HL)).toBe('HL USDC 永续')
    expect(chartSubOf(CB)).toBe('CB USD 现货')
    expect(chartSubOf(OKX)).toBe('OKX USDT 永续')
    expect(chartSubOf('DXY')).toBe('指数')
    for (const k of ['BTCUSDT', OKX, HL, CB, BYBIT, 'DXY']) expect(chartSubOf(k)).toBe(chartSub(k, undefined))
  })
  it('搜索行第二行与提醒卡那一行', () => {
    expect(rowMeta('BTCUSDT')).toBe('BTCUSDT 永续')
    expect(rowMeta(OKX, { raw: 'BTC-USDT-SWAP' })).toBe('BTC-USDT-SWAP 永续')
    expect(rowMeta(CB)).toBe('BTC-USD 现货')
    expect(rowMeta('DXY', { macro: true })).toBe('DXY 指数')
    expect(venueLine('BTCUSDT')).toBe('币安 · USDT 永续')
    expect(venueLine(HL)).toBe('HL · USDC 永续')
    expect(venueLine(CB)).toBe('CB · USD 现货')
  })
})

describe('搜索按交易所分组', () => {
  const pool = [
    sym('BTCUSDT', { vol: 100 }), sym('BTCDOMUSDT', { vol: 5 }),
    sym(OKX, { venue: 'okx', base: 'BTC', code: 'BTC', vol: 50 }),
    sym(CB, { venue: 'coinbase', quote: 'USD', base: 'BTC', code: 'BTC', vol: 70 }),
    sym(HL, { venue: 'hyperliquid', quote: 'USDC', title: 'kPEPE', base: 'PEPE', vol: 9 }),
    sym('hyperliquid/usd_m/BTC', { venue: 'hyperliquid', quote: 'USDC', base: 'BTC', code: 'BTC', vol: 30 }),
  ]
  const search = (q: string) => groupRanked(rank(pool, q, s => pairOf(s.symbol, s).base, s => wireSymbol(s.symbol)))
  it('一家一组，组头交易所全名；同档按注册表顺序（币安 · OKX · Bybit · Hyperliquid · Coinbase，同 iOS VenueRegistry.all）', () => {
    const g = search('btc')
    expect(g.map(x => x.venue)).toEqual(['binance', 'okx', 'hyperliquid', 'coinbase'])
    expect(g.map(x => x.title)).toEqual(['币安', 'OKX', 'Hyperliquid', 'Coinbase'])
    expect(g[0].hits.map(h => h.item.symbol)).toEqual(['BTCUSDT', 'BTCDOMUSDT'])
    // 别家完整键比的是代号那一段：整词命中、高亮落在 BTC 上
    expect(g[1].hits[0].hit.hl).toEqual([0, 3])
    expect(SEARCH_ORDER.at(-1)).toBe('macro')
    expect(groupTitle('macro')).toBe('指数')
  })
  it('组序先按组内最好的匹配档：只有 Hyperliquid 整词命中 KPEPE 时它排第一', () => {
    const g = search('kpepe')
    expect(g[0].venue).toBe('hyperliquid')
  })
  it('预览行数按组轮流分，每家至少一行，取完的组把名额让出来（同 iOS previewQuota）', () => {
    expect(previewQuota([12], 6)).toEqual([6])
    expect(previewQuota([3], 6)).toEqual([3])
    expect(previewQuota([12, 3], 6)).toEqual([3, 3])
    expect(previewQuota([12, 1], 6)).toEqual([5, 1])
    expect(previewQuota([1, 12], 6)).toEqual([1, 5])
    expect(previewQuota([9, 9, 9, 9, 9], 6)).toEqual([2, 1, 1, 1, 1])
    expect(previewQuota([2, 2, 2, 2, 2, 2, 2], 6)).toEqual([1, 1, 1, 1, 1, 1, 1])
    expect(previewQuota([], 6)).toEqual([])
    expect(previewQuota([2, 1], 6)).toEqual([2, 1])
  })
  it('品种整页：打了字按交易所分组、组头带命中数；别家归「加密」市场；页头计数分永续与现货', () => {
    const cat: PickerSym[] = pool.map(s => ({ symbol: s.symbol, base: s.base, vol: s.vol, price: 1, venue: s.venue, ut: s.venue === 'binance' ? 'COIN' : undefined }))
    const secs = buildSections(cat, { query: 'btc', favorites: [], recents: [], known: new Set(cat.map(s => s.symbol)) })
    expect(secs.map(s => [s.title, s.count])).toEqual([['币安', 2], ['OKX', 1], ['Hyperliquid', 1], ['Coinbase', 1]])
    expect(pickerMarket({ base: 'BTC', venue: 'okx' })).toBe('crypto')
    expect(pickerMarket({ base: 'BTC' })).toBe('other')
    expect(countText(cat)).toBe('5 个永续合约 · 1 个现货')
  })
})

describe('自选分类：别家各自一类（照 iOS assignVenueCategory）', () => {
  const prefs = (): SymbolPrefs => ({ favorites: [], recents: [], groups: [{ id: 'c', name: '加密' }, { id: 'u', name: '美股' }, { id: 'm', name: '贵金属' }], groupForSymbol: {}, seeded: true })
  it('类名是交易所全名，开在「美股」后面；美元指数仍在「指数」；币安落进站着的那一类', () => {
    expect(venueCategory(OKX)).toBe('OKX')
    expect(venueCategory(HL)).toBe('Hyperliquid')
    expect(venueCategory(CB)).toBe('Coinbase')
    expect(venueCategory('BTCUSDT')).toBeNull()
    const p = prefs()
    F.addFavorite(p, 'okx/usd_m/btcusdt', 'm', { kind: 'crypto' })
    expect(p.favorites).toEqual([OKX])
    const okx = p.groups.find(g => g.name === 'OKX')!
    expect(p.groupForSymbol[OKX]).toBe(okx.id)
    expect(p.groups.map(g => g.name)).toEqual(['加密', '美股', 'OKX', '贵金属'])
    F.addFavorite(p, CB, 'm', { kind: 'crypto' })
    expect(p.groupForSymbol[CB]).toBe(p.groups.find(g => g.name === 'Coinbase')!.id)
    F.addFavorite(p, 'DXY', 'c', { kind: 'idx' })
    expect(p.groupForSymbol.DXY).toBe(p.groups.find(g => g.name === '指数')!.id)
    F.addFavorite(p, 'ethusdt', 'm', { kind: 'crypto' })
    expect(p.groupForSymbol.ETHUSDT).toBe('m')
    // 同一个币在两家是两只
    F.addFavorite(p, 'BTCUSDT', 'c', { kind: 'crypto' })
    expect(F.isFavorite(p, 'BTCUSDT') && F.isFavorite(p, 'OKX/usd_m/BTCUSDT')).toBe(true)
    F.removeFavorite(p, OKX)
    expect(p.favorites).not.toContain(OKX)
    expect(F.isFavorite(p, 'BTCUSDT')).toBe(true)
  })
  it('默认自选的成交额榜不挑别家的', () => {
    const rows = [{ symbol: 'okx/usd_m/AAAUSDT', base: 'AAA', kind: 'crypto' as const, vol: 1e12 }, { symbol: 'BBBUSDT', base: 'BBB', kind: 'crypto' as const, vol: 5 }]
    expect(F.hotCoins(rows)).toEqual(['BBBUSDT'])
  })
})

describe('同步编解码：别家的键往返', () => {
  const fav = (id: string, body: Record<string, unknown>): SyncObject => ({ collection: 'favorites', id, body: body as never, fields: {}, revision: 1, deleted: false, generation: 0 })
  it('自选：发 venue / market / 那一家的代号，id 是三段身份；收回来拼回网页的键（币安与美元指数照旧）', () => {
    const out = C.encodeFavorites({ favorites: ['BTCUSDT', OKX, HL, CB, 'DXY'], groups: [], groupForSymbol: {} }, [], [])
    const live = out.filter(o => o.collection === 'favorites' && !o.deleted)
    expect(live.map(o => o.id)).toEqual(['binance/usd_m/BTCUSDT', OKX, HL, CB, 'macro/index/DXY'])
    expect(live.map(o => [o.body.venue, o.body.market, o.body.symbol])).toEqual([
      ['binance', 'usd_m', 'BTCUSDT'], ['okx', 'usd_m', 'BTCUSDT'], ['hyperliquid', 'usd_m', 'KPEPE'], ['coinbase', 'spot', 'BTC-USD'], ['macro', 'index', 'DXY'],
    ])
    const back = C.decodeFavorites(live, [], { favorites: [], groups: [], groupForSymbol: {} })
    expect(back.favorites).toEqual(['BTCUSDT', OKX, HL, CB, 'DXY'])
  })
  it('id 与三段对不上、认不出的交易所、代号形状不对的：原位留着，不进本机、不删', () => {
    const bad = [
      fav('okx/usd_m/ETHUSDT', { symbol: 'BTCUSDT', venue: 'okx', market: 'usd_m', order: 0 }),
      fav('kraken/spot/BTC-USD', { symbol: 'BTC-USD', venue: 'kraken', market: 'spot', order: 1 }),
      fav('okx/usd_m/BTC-USDT-SWAP', { symbol: 'BTC-USDT-SWAP', venue: 'okx', market: 'usd_m', order: 2 }),
    ]
    expect(C.decodeFavorites(bad, [], { favorites: [], groups: [], groupForSymbol: {} }).favorites).toEqual([])
    const out = C.encodeFavorites({ favorites: ['BTCUSDT'], groups: [], groupForSymbol: {} }, bad, [])
    expect(out.filter(o => o.deleted)).toEqual([])
  })
  it('提醒：market 是 venue/market、正文代号是那一家的，收回来是完整键', () => {
    const a = makePriceAlert(HL, 0.02, 0.019, { now: 1_700_000_000_000 })
    expect(a.market).toBe('hyperliquid/usd_m')
    const objs = encodeAlerts([a], [])
    const o = objs.find(x => x.id === alertId(HL, a.id))!
    expect(o.body.symbol).toBe('KPEPE')
    expect(o.body.market).toBe('hyperliquid/usd_m')
    const back = decodeAlerts(objs, [])
    expect(back.map(x => [x.symbol, x.market])).toEqual([[HL, 'hyperliquid/usd_m']])
  })
  it('画线桶键：注册表里的别家按那一家的代号形状收', () => {
    expect(syncableKey(OKX)).toBe(true)
    expect(syncableKey(CB)).toBe(true)
    expect(syncableKey('okx/usd_m/BTC-USDT-SWAP')).toBe(false)
  })
})

describe('行情页：别家的键', () => {
  it('对比目标认完整键，主图那只（完整键）自己不算', () => {
    expect(compareTargets([OKX, 'binance/usd_m/BTCUSDT', CB], OKX)).toEqual([{ key: 'binance/usd_m/BTCUSDT', symbol: 'BTCUSDT' }, { key: CB, symbol: CB }])
  })
  it('那一家的表到没到：币安看 S.live，别家看 S.venues；到了却没有才算下架，没到先拿上次记下的', () => {
    S.live = true
    S.symbols = new Map([['BTCUSDT', sym('BTCUSDT')]])
    expect(tableLive('BTCUSDT')).toBe(true)
    expect(liveOf(OKX)).toBeNull()
    expect(tableLive(OKX)).toBe(false)
    S.venues = { okx: { live: true, error: '', at: 1 } }
    expect(tableLive(OKX)).toBe(true)
    expect(liveOrCached(OKX)).toBeUndefined()
    S.venues = { okx: { live: false, error: 'x', at: 1 } }
    expect(liveOf(OKX)).toBe(false)
  })
  it('通知 / 朋友的画线：注册表里的别家开得了', () => {
    expect(noticeSymbol({ venue: 'OKX', market: 'usd_m', symbol: 'btcusdt' })).toBe(OKX)
    expect(openableKey('binance', 'usd_m', 'ethusdt')).toBe('ETHUSDT')
    expect(openableKey('okx', 'swap', 'X')).toBeNull()
  })
})

describe('行情页顶部', () => {
  it('品种名只写基础币（headName），旁边小字按交易所 / 计价 / 市场；横屏画线台、成片身份条用同一份', async () => {
    const { topBarText } = await import('../src/m/pages/chart/header')
    expect(topBarText('DOGEUSDT', sym('DOGEUSDT'))).toEqual({ name: 'DOGE', sub: '币安 USDT 永续' })
    expect(topBarText(HL, sym(HL, { venue: 'hyperliquid', quote: 'USDC', title: 'kPEPE' }))).toEqual({ name: 'kPEPE', sub: 'HL USDC 永续' })
    expect(topBarText(CB, undefined)).toEqual({ name: 'BTC', sub: 'CB USD 现货' })
    expect(topBarText('DXY', sym('DXY', { macro: true, quote: '', code: 'DXY', kind: 'idx' }))).toEqual({ name: 'DXY', sub: '指数' })
  })
})
