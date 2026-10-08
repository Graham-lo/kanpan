/* 解码模糊：OKX / Bybit / Hyperliquid / Coinbase 的品种表、整表行情、K 线、推送帧（行情与订单流两套）
 * 喂畸形输入——缺字段、"NaN"、负价、超大数、乱序、重复、空数组、unicode 代号、超长——
 *   不崩（REST 的错误码按设计抛「OKX / Bybit 错误码」，推送一律不抛）、不产 NaN / 非正的价、坏行坏帧整条丢；
 *   键一律过那一家的代号规则、parseKey 认回同一家；
 *   时间戳写坏的（远在未来）不把「按交易所时间拒旧」卡死；
 * 另：Bybit tickers delta 的各种到达顺序、OKX K 线倒序与 UTC 对齐、Hyperliquid 大写键译回原名。 */
import { afterEach, describe, expect, it } from 'vitest'
import { decodeOKX, decodeOkxCandles, decodeOkxInstruments, decodeOkxPush, decodeOkxTickers, parseOkxCandles } from '../src/venues/okx'
import { bybitDecoder, decodeBybit, decodeBybitInstruments, decodeBybitKlines, decodeBybitTickers } from '../src/venues/bybit'
import { decodeHlCandles, decodeHlCtxs, decodeHlPush, decodeHlUniverse, decodeHyperliquid, hlCoin } from '../src/venues/hyperliquid'
import { decodeCbCandles, decodeCbProducts, decodeCbPush, decodeCbQuotes, decodeCoinbase, parseCoinbaseCandles } from '../src/venues/coinbase'
import { makeVenue, symbolOk, type DepthBook, type Push, type Quote } from '../src/venues'
import { bucketOf } from '../src/venues/bars'
import { parseKey } from '../src/market/identity'
import { handle } from '../src/market/venueStream'
import { S } from '../src/market/state'
import type { Bar } from '../src/chart/calc'
import type { Sym } from '../src/market/symbols'
import type { DepthMessage } from '../src/orderflow/types'

const BAD: unknown[] = [undefined, null, '', 'NaN', 'nan', 'Infinity', '-Infinity', '-1', '-0', '0', '1e400', '-1e400', 1e308 * 10, -5, NaN, {}, [], 'abc', '😀', 'x'.repeat(5000), true, '0x10', ' 12 ', '1,000']
const DAY = 86_400_000

// ------------------------------------------------------------ 不变量
function badBar(b: Bar): string | null {
  for (const k of ['o', 'h', 'l', 'c'] as const) if (!(Number.isFinite(b[k]) && b[k] > 0)) return `${k}=${b[k]}`
  if (!Number.isFinite(b.t) || b.t < 0 || b.t > Date.now() + 2 * DAY) return `t=${b.t}`
  if (!(Number.isFinite(b.v) && b.v >= 0)) return `v=${b.v}`
  if (b.bv != null && !(Number.isFinite(b.bv) && b.bv >= 0)) return `bv=${b.bv}`
  if (b.h < Math.max(b.o, b.c) || b.l > Math.min(b.o, b.c)) return `hl ${b.h} ${b.l} ${b.o} ${b.c}`
  return null
}
function checkBars(bars: Bar[], where: string): void {
  for (const b of bars) { const e = badBar(b); if (e) throw new Error(`${where}: 坏 K 线 ${e} ${JSON.stringify(b)}`) }
  for (let i = 1; i < bars.length; i++) if (!(bars[i].t > bars[i - 1].t)) throw new Error(`${where}: 不是严格升序`)
}
function checkQuote(q: Quote, venue: string, where: string): void {
  expect(parseKey(q.key).venue, where).toBe(venue)
  expect(symbolOk(q.key), `${where} ${q.key}`).toBe(true)
  for (const k of ['price', 'open', 'hi', 'lo', 'mark', 'index'] as const) if (q[k] !== undefined && !(Number.isFinite(q[k]) && q[k]! > 0)) throw new Error(`${where}: ${k}=${q[k]}`)
  for (const k of ['pct', 'chg'] as const) if (q[k] !== undefined && !Number.isFinite(q[k])) throw new Error(`${where}: ${k}=${q[k]}`)
  for (const k of ['vol', 'count', 'oi'] as const) if (q[k] !== undefined && !(Number.isFinite(q[k]) && q[k]! >= 0)) throw new Error(`${where}: ${k}=${q[k]}`)
  if (q.fr !== undefined && q.fr !== null && !Number.isFinite(q.fr)) throw new Error(`${where}: fr=${q.fr}`)
  if (q.nextFunding != null && !(Number.isFinite(q.nextFunding) && q.nextFunding > 0)) throw new Error(`${where}: nextFunding=${q.nextFunding}`)
  if (!(Number.isFinite(q.at) && q.at > 0 && q.at <= Date.now() + DAY)) throw new Error(`${where}: at=${q.at}`)
}
function checkSyms(list: Sym[], venue: string, where: string): void {
  for (const s of list) {
    expect(parseKey(s.symbol).venue, `${where} ${s.symbol}`).toBe(venue)
    expect(symbolOk(s.symbol), `${where} ${s.symbol}`).toBe(true)
    expect(Number.isInteger(s.dec) && s.dec >= 0 && s.dec <= 8, `${where} dec ${s.dec}`).toBe(true)
  }
}
function checkPushes(ps: Push[], venue: string, where: string): void {
  for (const p of ps) {
    if (p.type === 'quote') checkQuote(p.quote, venue, where)
    else if (p.type === 'kline') { expect(parseKey(p.key).venue).toBe(venue); expect(symbolOk(p.key), `${where} ${p.key}`).toBe(true); checkBars([p.bar], where) }
    else {
      expect(symbolOk(p.key), `${where} ${p.key}`).toBe(true)
      if (!(p.price > 0 && Number.isFinite(p.price) && p.qty > 0 && Number.isFinite(p.qty))) throw new Error(`${where}: 逐笔 ${p.price} × ${p.qty}`)
      if (!(Number.isFinite(p.t) && p.t > 0 && p.t <= Date.now() + DAY)) throw new Error(`${where}: 逐笔时刻 ${p.t}`)
    }
  }
}
function checkDepth(out: [string, DepthMessage][], where: string): void {
  for (const [, m] of out) {
    const lv = m.type === 'snapshot' ? [...m.snapshot.bids, ...m.snapshot.asks] : m.type === 'delta' ? [...m.delta.bids, ...m.delta.asks] : []
    for (const l of lv) if (!(Number.isFinite(l.price) && l.price > 0 && Number.isFinite(l.quantity) && l.quantity >= 0)) throw new Error(`${where}: 档位 ${JSON.stringify(l)}`)
    if (m.type === 'trade') { const t = m.trade; if (!(t.price > 0 && Number.isFinite(t.price) && t.quantity > 0 && Number.isFinite(t.quantity))) throw new Error(`${where}: 成交 ${JSON.stringify(t)}`) }
  }
}

/** 一个对象：每个字段轮流换成每一个坏值（一次一个），外加删掉这个字段 */
function* mutations<T extends Record<string, unknown>>(base: T): Generator<T> {
  for (const k of Object.keys(base)) {
    for (const v of BAD) yield { ...base, [k]: v }
    const { [k]: _, ...rest } = base
    yield rest as T
  }
}
/** 数组行：每一格轮流换成坏值，外加截短 */
function* rowMutations(base: unknown[]): Generator<unknown[]> {
  for (let i = 0; i < base.length; i++) for (const v of BAD) { const r = base.slice(); r[i] = v; yield r }
  for (let n = 0; n < base.length; n++) yield base.slice(0, n)
}
/** REST 回包：允许的唯一一种抛法是「那一家的错误码」 */
function tolerant<T>(f: () => T, where: string): T | null {
  try { return f() } catch (e) {
    if (/^(OKX|Bybit) /.test(String((e as Error).message))) return null
    throw new Error(`${where} 崩了：${(e as Error).stack}`)
  }
}
const WHOLE: unknown[] = [...BAD, { data: null }, { data: [null] }, { data: [[]] }, { data: {} }, { result: null }, { result: { list: [null, 1, 'x'] } }, [null], [[], null], { candles: [null] }, { products: [null, {}] }, { universe: 5 }]

const book = (exchange: string, instrument: string): DepthBook => ({ id: `${exchange}:usdtPerp:${instrument}`, venue: makeVenue(exchange, 'usdtPerp', instrument, { kind: 'linear', multiplier: 1 }), priceFactor: 1, expiryMs: null, tick: null })

afterEach(() => { S.symbols = new Map() })

describe('OKX', () => {
  const ROW = { instId: 'BTC-USDT-SWAP', last: '110', open24h: '100', high24h: '120', low24h: '90', volCcy24h: '50', ts: '1700000000000' }
  const INST = { instId: 'BTC-USDT-SWAP', settleCcy: 'USDT', ctType: 'linear', tickSz: '0.1', state: 'live', listTime: '1606468572000' }
  const CANDLE = ['1700003600000', '2', '3', '1', '2.5', '100', '10', '25', '0']
  it('整表 / 品种表 / K 线：每个字段换成坏值都不崩、不出坏数', () => {
    for (const r of mutations(ROW)) { const q = tolerant(() => decodeOkxTickers({ code: '0', data: [r] }), 'okx tickers'); for (const x of q ?? []) checkQuote(x, 'okx', `okx ticker ${JSON.stringify(r).slice(0, 80)}`) }
    for (const r of mutations(INST)) checkSyms(tolerant(() => decodeOkxInstruments({ code: '0', data: [r] }), 'okx ins') ?? [], 'okx', 'okx ins')
    for (const r of rowMutations(CANDLE)) checkBars(tolerant(() => decodeOkxCandles({ code: '0', data: [r] }), 'okx candles') ?? [], `okx candle ${JSON.stringify(r).slice(0, 80)}`)
    for (const w of WHOLE) { tolerant(() => decodeOkxTickers(w), 'okx'); tolerant(() => decodeOkxInstruments(w), 'okx'); tolerant(() => decodeOkxCandles(w), 'okx'); expect(parseOkxCandles(w)).toBeInstanceOf(Array) }
  })
  it('unicode / 超长 instId 不进表（原来 104 位的代号做出的键 parseKey 认成币安裸代号）', () => {
    const rows = ['币-USDT-SWAP', '😀-USDT-SWAP', `${'A'.repeat(100)}-USDT-SWAP`, 'btc-USDT-SWAP', '-USDT-SWAP'].map(instId => ({ ...INST, instId }))
    expect(decodeOkxInstruments({ code: '0', data: rows })).toEqual([])
    expect(decodeOkxTickers({ code: '0', data: rows.map(r => ({ ...ROW, instId: r.instId })) })).toEqual([])
  })
  it('推送：每个字段换成坏值都不崩、不出坏数；乱 JSON、空数组、超长都回空', () => {
    const frames: unknown[] = []
    for (const r of mutations(ROW)) frames.push({ arg: { channel: 'tickers', instId: 'BTC-USDT-SWAP' }, data: [r] })
    for (const r of rowMutations(CANDLE)) frames.push({ arg: { channel: 'candle1H', instId: 'BTC-USDT-SWAP' }, data: [r] })
    for (const r of mutations({ px: '100', sz: '2', side: 'sell', ts: '5' })) frames.push({ arg: { channel: 'trades', instId: 'BTC-USDT-SWAP' }, data: [r] })
    for (const r of mutations({ markPx: '99', ts: '6' })) frames.push({ arg: { channel: 'mark-price', instId: 'BTC-USDT-SWAP' }, data: [r] })
    for (const r of mutations({ fundingRate: '0.0001', fundingTime: '1700028800000', ts: '7' })) frames.push({ arg: { channel: 'funding-rate', instId: 'BTC-USDT-SWAP' }, data: [r] })
    for (const v of BAD) frames.push({ arg: { channel: 'tickers', instId: v }, data: [ROW] }, { arg: v, data: [ROW] }, { arg: { channel: v, instId: 'BTC-USDT-SWAP' }, data: v })
    for (const f of frames) checkPushes(decodeOkxPush(JSON.stringify(f)), 'okx', `okx push ${JSON.stringify(f).slice(0, 100)}`)
    for (const t of ['', 'pong', '{', '[]', 'null', '"x"', '😀', 'x'.repeat(100_000), '{"data":[]}']) expect(decodeOkxPush(t)).toEqual([])
  })
  it('订单流解帧：坏档位 / 坏成交不进簿', () => {
    const b = book('okx', 'BTC-USDT-SWAP'), map = new Map([['BTC-USDT-SWAP', b]])
    for (const v of BAD) {
      checkDepth(decodeOKX(JSON.stringify({ arg: { channel: 'books', instId: 'BTC-USDT-SWAP' }, action: 'snapshot', data: [{ bids: [[v, '1'], ['100', v]], asks: [['101', '1']], seqId: 5, prevSeqId: -1, ts: '1' }] }), map), 'okx books')
      checkDepth(decodeOKX(JSON.stringify({ arg: { channel: 'trades', instId: 'BTC-USDT-SWAP' }, data: [{ px: v, sz: '1', side: 'buy', ts: '1' }, { px: '1', sz: v, side: 'buy', ts: '1' }] }), map), 'okx trades')
    }
  })
  it('K 线倒序、重复、乱序 → 严格升序去重；6 时以上按 UTC 对齐的 bar（6Hutc）解出来格头落在 UTC 0/6/12/18 点', () => {
    const t0 = Date.UTC(2026, 9, 1), H6 = 6 * 3600e3
    const rows = [3, 1, 2, 0, 2, 1].map(i => [String(t0 + i * H6), '1', '2', '0.5', '1.5', '1', '1', '1', '1'])
    const bars = decodeOkxCandles({ code: '0', data: rows })
    expect(bars.map(b => b.t)).toEqual([0, 1, 2, 3].map(i => t0 + i * H6))
    expect(bars.every(b => bucketOf(b.t, '6h') === b.t)).toBe(true)
    expect(decodeOkxCandles({ code: '0', data: [] })).toEqual([])
  })
})

describe('Bybit', () => {
  const ROW = { symbol: 'BTCUSDT', lastPrice: '101', prevPrice24h: '100', price24hPcnt: '0.01', highPrice24h: '105', lowPrice24h: '95', turnover24h: '1000000', markPrice: '101.1', indexPrice: '101.2', openInterest: '500', fundingRate: '0.0001', nextFundingTime: '1700028800000' }
  const INST = { symbol: 'BTCUSDT', contractType: 'LinearPerpetual', status: 'Trading', quoteCoin: 'USDT', launchTime: '1683000000000', priceFilter: { tickSize: '0.1' } }
  const K = ['120000', '2', '3', '1', '2', '5', '10']
  it('整表 / 品种表 / K 线：每个字段换成坏值都不崩、不出坏数', () => {
    for (const r of mutations(ROW)) for (const q of tolerant(() => decodeBybitTickers({ retCode: 0, time: 1700000000000, result: { list: [r] } }), 'bybit') ?? []) checkQuote(q, 'bybit', `bybit ticker ${JSON.stringify(r).slice(0, 80)}`)
    for (const r of mutations(INST)) checkSyms(tolerant(() => decodeBybitInstruments({ retCode: 0, result: { list: [r] } }), 'bybit') ?? [], 'bybit', 'bybit ins')
    for (const r of rowMutations(K)) checkBars(tolerant(() => decodeBybitKlines({ retCode: 0, result: { list: [r] } }), 'bybit') ?? [], `bybit kline ${JSON.stringify(r)}`)
    for (const w of WHOLE) { tolerant(() => decodeBybitTickers(w), 'bybit'); tolerant(() => decodeBybitInstruments(w), 'bybit'); tolerant(() => decodeBybitKlines(w), 'bybit') }
  })
  it('推送：坏字段、坏 topic、unicode / 超长代号都不崩、不出坏数', () => {
    const dec = bybitDecoder()
    const frames: unknown[] = []
    for (const r of mutations(ROW)) frames.push({ topic: 'tickers.BTCUSDT', type: 'snapshot', ts: 10, data: r }, { topic: 'tickers.BTCUSDT', type: 'delta', ts: 11, data: r })
    for (const r of mutations({ start: 3600000, open: '1', close: '2', high: '3', low: '0.5', volume: '4', turnover: '8' })) frames.push({ topic: 'kline.60.BTCUSDT', data: [r] })
    for (const r of mutations({ T: 9, S: 'Buy', v: '0.5', p: '100' })) frames.push({ topic: 'publicTrade.BTCUSDT', data: [r] })
    for (const s of ['币安人生USDT', '😀USDT', 'A'.repeat(60) + 'USDT', 'btcusdt', '']) frames.push({ topic: `tickers.${s}`, type: 'snapshot', ts: 1, data: { ...ROW, symbol: s } }, { topic: `publicTrade.${s}`, data: [{ T: 1, S: 'Buy', v: '1', p: '1' }] })
    for (const v of BAD) frames.push({ topic: v, data: v }, { topic: 'tickers.BTCUSDT', type: v, ts: v, data: v })
    for (const f of frames) checkPushes(dec(JSON.stringify(f)), 'bybit', `bybit push ${JSON.stringify(f).slice(0, 100)}`)
    for (const t of ['', '{', '[]', 'null', 'x'.repeat(100_000)]) expect(dec(t)).toEqual([])
  })
  it('订单流解帧：坏档位 / 坏成交不进簿', () => {
    const b = book('bybit', 'BTCUSDT'), map = new Map([['BTCUSDT', b]])
    for (const v of BAD) {
      checkDepth(decodeBybit(JSON.stringify({ topic: 'orderbook.1000.BTCUSDT', type: 'snapshot', ts: 1, data: { s: 'BTCUSDT', b: [[v, '1'], ['100', v]], a: [['101', '1']], u: 3 } }), map), 'bybit book')
      checkDepth(decodeBybit(JSON.stringify({ topic: 'publicTrade.BTCUSDT', data: [{ T: 1, S: 'Buy', v, p: '100' }, { T: 1, S: 'Sell', v: '1', p: v }] }), map), 'bybit trade')
    }
  })
  describe('tickers delta 的各种到达顺序', () => {
    const snap = (ts: number, d: Record<string, string>) => JSON.stringify({ topic: 'tickers.BTCUSDT', type: 'snapshot', ts, data: { symbol: 'BTCUSDT', ...d } })
    const delta = (ts: number, d: Record<string, string>) => JSON.stringify({ topic: 'tickers.BTCUSDT', type: 'delta', ts, data: { symbol: 'BTCUSDT', ...d } })
    const last = (ps: Push[]) => (ps.at(-1) as Extract<Push, { type: 'quote' }> | undefined)?.quote
    it('delta 先于 snapshot：不出；snapshot 之后的 delta 只改它带的字段', () => {
      const dec = bybitDecoder()
      expect(dec(delta(1, { lastPrice: '1' }))).toEqual([])
      expect(last(dec(snap(2, { lastPrice: '100', markPrice: '100', fundingRate: '0.0001' })))?.price).toBe(100)
      expect(last(dec(delta(3, { markPrice: '101' })))).toMatchObject({ price: 100, mark: 101, fr: 0.0001 })
    })
    it('同一条 delta 到两次：结果一样（幂等）', () => {
      const dec = bybitDecoder()
      dec(snap(1, { lastPrice: '100' }))
      const a = last(dec(delta(2, { lastPrice: '102' }))), b = last(dec(delta(2, { lastPrice: '102' })))
      expect(a).toEqual(b)
    })
    it('旧的 delta 晚到（ts 倒退）：不并进快照——否则旧价被后面只带成交额的 delta 当成新价带出去', () => {
      const dec = bybitDecoder()
      dec(snap(1, { lastPrice: '100' }))
      dec(delta(3, { lastPrice: '102' }))
      expect(dec(delta(2, { lastPrice: '101' }))).toEqual([])
      expect(last(dec(delta(4, { turnover24h: '9' })))).toMatchObject({ price: 102, vol: 9, at: 4 })
    })
    it('重订后新的 snapshot 整个盖掉旧快照（旧字段不残留）；fundingRate 空串 = 没有资金费', () => {
      const dec = bybitDecoder()
      dec(snap(1, { lastPrice: '100', openInterest: '5' }))
      const q = last(dec(snap(5, { lastPrice: '90', fundingRate: '' })))!
      expect(q.price).toBe(90)
      expect(q.oi).toBeUndefined()
      expect(q.fr).toBeNull()
    })
    it('两只交错到达：互不串', () => {
      const dec = bybitDecoder()
      dec(snap(1, { lastPrice: '100' }))
      dec(JSON.stringify({ topic: 'tickers.ETHUSDT', type: 'snapshot', ts: 1, data: { symbol: 'ETHUSDT', lastPrice: '5' } }))
      const e = last(dec(JSON.stringify({ topic: 'tickers.ETHUSDT', type: 'delta', ts: 2, data: { markPrice: '5.1' } })))!
      expect(e).toMatchObject({ key: 'bybit/usd_m/ETHUSDT', price: 5, mark: 5.1 })
      expect(last(dec(delta(2, { markPrice: '100.5' })))).toMatchObject({ key: 'bybit/usd_m/BTCUSDT', price: 100 })
    })
  })
})

describe('Hyperliquid', () => {
  const CTX = { funding: '0.0000125', openInterest: '100', prevDayPx: '100', dayNtlVlm: '1000000', markPx: '110', midPx: '110.5', oraclePx: '109.9' }
  const CANDLE = { t: 60000, T: 119999, s: 'BTC', i: '1m', o: '1', c: '2', h: '3', l: '0.5', v: '10', n: 4 }
  it('品种表 / 整表行情 / K 线：每个字段换成坏值都不崩、不出坏数', () => {
    for (const c of mutations(CTX)) for (const q of decodeHlCtxs([{ universe: [{ name: 'BTC', szDecimals: 5 }] }, [c]], 1_700_000_000_000)) checkQuote(q, 'hyperliquid', `hl ctx ${JSON.stringify(c).slice(0, 80)}`)
    for (const u of mutations({ name: 'BTC', szDecimals: 5 as unknown, isDelisted: false as unknown })) checkSyms(decodeHlUniverse([{ universe: [u] }, []]), 'hyperliquid', 'hl uni')
    for (const k of mutations(CANDLE)) checkBars(decodeHlCandles([k]), `hl candle ${JSON.stringify(k).slice(0, 80)}`)
    for (const w of WHOLE) { decodeHlCtxs(w); decodeHlUniverse(w); decodeHlCandles(w) }
  })
  it('unicode / 超长 / 小写 k 之外的名字：品种表不收、推送不出', () => {
    expect(decodeHlUniverse([{ universe: [{ name: '😀' }, { name: 'A'.repeat(17) }, { name: '' }, { name: 'BT C' }] }, []])).toEqual([])
    for (const coin of ['😀', 'A'.repeat(40), '', 'BT C']) {
      expect(decodeHlPush(JSON.stringify({ channel: 'trades', data: [{ coin, side: 'A', px: '1', sz: '1', time: 1 }] }))).toEqual([])
      expect(decodeHlPush(JSON.stringify({ channel: 'activeAssetCtx', data: { coin, ctx: CTX } }))).toEqual([])
      expect(decodeHlPush(JSON.stringify({ channel: 'candle', data: { ...CANDLE, s: coin } }))).toEqual([])
    }
  })
  it('推送：坏字段都不崩、不出坏数；大写键译回原名、原名译回大写键', () => {
    const frames: unknown[] = []
    for (const k of mutations(CANDLE)) frames.push({ channel: 'candle', data: k })
    for (const t of mutations({ coin: 'BTC', side: 'A', px: '100', sz: '1', time: 7 })) frames.push({ channel: 'trades', data: [t] })
    for (const c of mutations(CTX)) frames.push({ channel: 'activeAssetCtx', data: { coin: 'BTC', ctx: c } })
    for (const v of BAD) frames.push({ channel: v, data: v }, { channel: 'candle', data: v }, { channel: 'activeAssetCtx', data: { coin: v, ctx: v } })
    for (const f of frames) checkPushes(decodeHlPush(JSON.stringify(f)), 'hyperliquid', `hl push ${JSON.stringify(f).slice(0, 100)}`)
    decodeHlUniverse([{ universe: [{ name: 'kPEPE', szDecimals: 0 }, { name: 'kBONK', szDecimals: 0 }] }, []])
    expect(hlCoin('hyperliquid/usd_m/KPEPE')).toBe('kPEPE')
    expect(hlCoin('hyperliquid/usd_m/KBONK')).toBe('kBONK')
    expect(hlCoin('hyperliquid/usd_m/BTC')).toBe('BTC')
    expect(decodeHlPush(JSON.stringify({ channel: 'trades', data: [{ coin: 'kBONK', side: 'B', px: '0.02', sz: '5', time: 1 }] }))[0]).toMatchObject({ key: 'hyperliquid/usd_m/KBONK', sell: false })
  })
  it('订单流解帧：坏档位 / 坏成交不进簿', () => {
    const b = book('hyperliquid', 'BTC'), map = new Map([['BTC', b]])
    for (const v of BAD) {
      checkDepth(decodeHyperliquid(JSON.stringify({ channel: 'l2Book', data: { coin: 'BTC', time: 1, levels: [[{ px: v, sz: '1' }, { px: '100', sz: v }], [{ px: '101', sz: '1' }]] } }), map), 'hl book')
      checkDepth(decodeHyperliquid(JSON.stringify({ channel: 'trades', data: [{ coin: 'BTC', side: 'B', px: v, sz: '1', time: 1 }, { coin: 'BTC', side: 'A', px: '1', sz: v, time: 1 }] }), map), 'hl trade')
    }
  })
})

describe('Coinbase', () => {
  const P = { product_id: 'BTC-USD', price: '110', price_percentage_change_24h: '10', volume_24h: '2', quote_increment: '0.01', status: 'online', trading_disabled: false, product_type: 'SPOT' }
  const C = { start: '120', low: '1', high: '3', open: '2', close: '2', volume: '5' }
  it('品种表 / 整表行情 / K 线：每个字段换成坏值都不崩、不出坏数（涨跌 −100% 不出无穷大的开盘价）', () => {
    for (const p of mutations(P)) { checkSyms(decodeCbProducts({ products: [p] }), 'coinbase', 'cb products'); for (const q of decodeCbQuotes({ products: [p] }, 5)) checkQuote(q, 'coinbase', `cb quote ${JSON.stringify(p).slice(0, 80)}`) }
    for (const pct of ['-100', '-150', '-99.9999999999']) for (const q of decodeCbQuotes({ products: [{ ...P, price_percentage_change_24h: pct }] }, 5)) checkQuote(q, 'coinbase', `cb pct ${pct}`)
    for (const c of mutations(C)) checkBars(decodeCbCandles({ candles: [c] }), `cb candle ${JSON.stringify(c).slice(0, 80)}`)
    for (const w of WHOLE) { decodeCbProducts(w); decodeCbQuotes(w); decodeCbCandles(w); expect(parseCoinbaseCandles(w)).toBeInstanceOf(Array) }
    expect(decodeCbProducts({ products: ['ÄBC-USD', '😀-USD', 'A'.repeat(50) + '-USD', 'btc-USD'].map(product_id => ({ ...P, product_id })) })).toEqual([])
  })
  it('推送：坏字段都不崩、不出坏数', () => {
    const frames: unknown[] = []
    const T = { product_id: 'BTC-USD', price: '100', price_percent_chg_24_h: '1', volume_24_h: '3', high_24_h: '105', low_24_h: '95' }
    for (const t of mutations(T)) frames.push({ channel: 'ticker', timestamp: '2026-10-08T00:00:00Z', events: [{ tickers: [t] }] })
    for (const t of mutations({ product_id: 'BTC-USD', price: '100', size: '1', side: 'BUY', time: '2026-10-08T00:00:00Z' })) frames.push({ channel: 'market_trades', events: [{ trades: [t] }] })
    for (const v of BAD) frames.push({ channel: 'ticker', timestamp: v, events: v }, { channel: 'ticker', events: [{ tickers: v }] }, { channel: 'ticker', events: [{ tickers: [{ ...T, price_percent_chg_24_h: v }] }] })
    for (const f of frames) checkPushes(decodeCbPush(JSON.stringify(f)), 'coinbase', `cb push ${JSON.stringify(f).slice(0, 100)}`)
  })
  it('订单流解帧：坏档位 / 坏成交不进簿', () => {
    const b = { ...book('coinbase', 'BTC-USD'), venue: makeVenue('coinbase', 'spot', 'BTC-USD', { kind: 'linear', multiplier: 1 }) }
    for (const v of BAD) {
      checkDepth(decodeCoinbase(JSON.stringify({ channel: 'l2_data', sequence_num: 1, events: [{ type: 'snapshot', product_id: 'BTC-USD', updates: [{ side: 'bid', price_level: v, new_quantity: '1' }, { side: 'offer', price_level: '1', new_quantity: v }] }] }), b), 'cb book')
      checkDepth(decodeCoinbase(JSON.stringify({ channel: 'market_trades', sequence_num: 2, events: [{ type: 'update', trades: [{ product_id: 'BTC-USD', price: v, size: '1', side: 'BUY' }, { product_id: 'BTC-USD', price: '1', size: v, side: 'SELL' }] }] }), b), 'cb trade')
    }
  })
})

describe('时间戳写坏的一帧不把「按交易所时间拒旧」卡死', () => {
  const sym = (symbol: string): Sym => ({ symbol, venue: parseKey(symbol).venue, quote: 'USDT', base: 'BTC', code: 'BTC', kind: 'crypto', cn: '', dec: 2, color: '', price: 100, chg: 0, pct: 0, vol: 0, fr: null, nextFunding: null, open: 100, pxAt: 1 })
  it('OKX 一帧 ts 写成五千年后：之后正常的行情照样落进去', () => {
    const K = 'okx/usd_m/BTCUSDT'
    S.symbols = new Map([[K, sym(K)]])
    for (const p of decodeOkxPush(JSON.stringify({ arg: { channel: 'tickers', instId: 'BTC-USDT-SWAP' }, data: [{ instId: 'BTC-USDT-SWAP', last: '120', ts: '99999999999999' }] }))) handle(p)
    for (const p of decodeOkxPush(JSON.stringify({ arg: { channel: 'tickers', instId: 'BTC-USDT-SWAP' }, data: [{ instId: 'BTC-USDT-SWAP', last: '130', ts: String(Date.now()) }] }))) handle(p)
    expect(S.symbols.get(K)!.price).toBe(130)
  })
  it('Hyperliquid 逐笔 time 写坏：当前价照样跟着之后的逐笔走', () => {
    const K = 'hyperliquid/usd_m/BTC'
    S.symbols = new Map([[K, sym(K)]])
    for (const p of decodeHlPush(JSON.stringify({ channel: 'trades', data: [{ coin: 'BTC', side: 'B', px: '101', sz: '1', time: 1e15 }] }))) handle(p)
    for (const p of decodeHlPush(JSON.stringify({ channel: 'trades', data: [{ coin: 'BTC', side: 'B', px: '102', sz: '1', time: Date.now() }] }))) handle(p)
    expect(S.symbols.get(K)!.price).toBe(102)
  })
  it('直接喂一份 at 在遥远未来的行情（哪一家的解码漏了都兜得住）：之后的照样落', () => {
    const K = 'bybit/usd_m/BTCUSDT'
    S.symbols = new Map([[K, sym(K)]])
    handle({ type: 'quote', quote: { key: K, price: 111, at: 9e15 } })
    handle({ type: 'quote', quote: { key: K, price: 112, at: Date.now() } })
    expect(S.symbols.get(K)!.price).toBe(112)
  })
})
