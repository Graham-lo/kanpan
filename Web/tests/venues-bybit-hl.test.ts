// Bybit / Hyperliquid 适配器：用 2026-10-08 实测录帧（tests/fixtures/bybit-hl-probe-2026-10-08.json）
// 解码 → 本地簿（VenueBook）走一遍：快照、增量、断档只重订那一本、u==1 重启整本覆盖、pong / 回执吞掉、
// HL 每帧整本替换（snapshotOnly）、subscriptionResponse 不理、成交主动方方向；连接分组与订阅消息的上限。
import { describe, expect, it } from 'vitest'
import fx from './fixtures/bybit-hl-probe-2026-10-08.json'
import { VenueBook } from '../src/orderflow/localBook'
import type { DepthMessage, Notional, Product } from '../src/orderflow/types'
import { connectionSpecs, fallbackBooks, makeVenue, EXCHANGE_NAMES, EXCHANGE_CH, LIQ_EX, type DepthBook } from '../src/venues'
import { decodeBybit, bybitSubscribe, bybitResubscribe, BYBIT_MAX_BOOKS, BYBIT_ARGS_PER_MESSAGE } from '../src/venues/bybit'
import { decodeHyperliquid, hlSubscribe, HL_MAX_BOOKS, HL_WINDOW, HL_SILENCE_MS } from '../src/venues/hyperliquid'


const book = (exchange: string, product: Product, instrument: string, priceFactor = 1, notional: Notional = { kind: 'linear', multiplier: 1 }): DepthBook =>
  ({ id: `${exchange}:${product}:${instrument}`, venue: makeVenue(exchange, product, instrument, notional), priceFactor, expiryMs: null, tick: null })
const S = (x: unknown): string => JSON.stringify(x)
const msgs = (outs: [string, DepthMessage][]): DepthMessage[] => outs.map(o => o[1])

describe('Bybit：解码与本地簿', () => {
  const b = book('bybit', 'usdtPerp', 'BTCUSDT')
  const map = new Map([['BTCUSDT', b]])

  it('注册表：五家、Bybit 第 3 路（下标 3）、爆仓第 2 家是 Bybit', () => {
    expect(EXCHANGE_NAMES).toEqual(['币安', 'OKX', 'Coinbase', 'Bybit', 'Hyperliquid'])
    expect(EXCHANGE_CH.bybit).toBe(3)
    expect(EXCHANGE_CH.hyperliquid).toBe(4)
    expect(LIQ_EX[2]).toBe('Bybit')
    expect(b.venue.sequenceModel).toBe('strictIncrementing')
    expect(b.venue.snapshotInBand).toBe(true)
  })

  it('快照 → 增量（u 严格 +1）→ ready，价量换算正确', () => {
    const vb = new VenueBook(b.venue)
    vb.connectionOpened()
    const [snap] = msgs(decodeBybit(S(fx.bybitLinearSnapshot), map))
    expect(snap.type).toBe('snapshot')
    if (snap.type !== 'snapshot') return
    expect(snap.snapshot.lastUpdateID).toBe(33344277)
    expect(snap.snapshot.slidingWindow).toBe(true)
    expect(snap.snapshot.restart).toBe(false)
    expect(snap.snapshot.bids[0]).toEqual({ price: 82642.8, quantity: 1.336 })
    expect(vb.ingest(snap, 1)).toBe('none')
    expect(vb.isReady).toBe(true)
    const [d] = msgs(decodeBybit(S(fx.bybitLinearDeltas[0]), map))
    expect(d.type).toBe('delta')
    expect(vb.ingest(d, 2)).toBe('none')
    expect(vb.book.lastUpdateID).toBe(33344278)
    expect(vb.book.quantity(82642.8, 'bid')).toBe(1.034) // 增量改了最优买一档
  })

  it('断档（u 跳号）→ 只要求重订这一本；退订 + 订阅只带它的 orderbook topic', () => {
    const vb = new VenueBook(b.venue)
    vb.connectionOpened()
    vb.ingest(msgs(decodeBybit(S(fx.bybitLinearSnapshot), map))[0], 1)
    const gap = structuredClone(fx.bybitLinearDeltas[0]) as { data: { u: number } }
    gap.data.u = 33344277 + 5
    expect(vb.ingest(msgs(decodeBybit(S(gap), map))[0], 2)).toBe('resubscribe')
    expect(vb.isReady).toBe(false)
    expect(bybitResubscribe(b).map(m => JSON.parse(m))).toEqual([
      { op: 'unsubscribe', args: ['orderbook.1000.BTCUSDT'] },
      { op: 'subscribe', args: ['orderbook.1000.BTCUSDT'] },
    ])
    // 重订回来的新快照让它重新可用
    expect(vb.ingest(msgs(decodeBybit(S(fx.bybitLinearSnapshot), map))[0], 3)).toBe('none')
    expect(vb.isReady).toBe(true)
  })

  it('u == 1 的快照（对方服务重启）整本覆盖，不当倒退', () => {
    const vb = new VenueBook(b.venue)
    vb.connectionOpened()
    vb.ingest(msgs(decodeBybit(S(fx.bybitLinearSnapshot), map))[0], 1)
    const restart = structuredClone(fx.bybitLinearSnapshot)
    restart.data.u = 1
    restart.data.b = [['80000.00', '2']]
    restart.data.a = [['80001.00', '3']]
    const [m] = msgs(decodeBybit(S(restart), map))
    expect(m.type === 'snapshot' && m.snapshot.restart).toBe(true)
    expect(vb.ingest(m, 2)).toBe('none')
    expect(vb.book.lastUpdateID).toBe(1)
    expect(vb.book.quantity(82642.8, 'bid')).toBe(0)
    expect(vb.book.quantity(80000, 'bid')).toBe(2)
    // 普通（非 1）的倒退快照仍判错 → 重订
    const back = structuredClone(fx.bybitLinearSnapshot)
    back.data.u = 0
    expect(vb.ingest(msgs(decodeBybit(S(back), map))[0], 3)).toBe('resubscribe')
  })

  it('pong 两种形状、订阅回执都静默吞掉', () => {
    for (const f of [...fx.bybitAcks, ...fx.bybitPongs, { op: 'pong' }]) expect(decodeBybit(S(f), map)).toEqual([])
    expect(decodeBybit('not json', map)).toEqual([])
  })

  it('成交：S=Buy 吃卖盘（hit ask），S=Sell 吃买盘；现货 / 币本位一样', () => {
    const [t] = msgs(decodeBybit(S(fx.bybitLinearTrade), map))
    expect(t).toEqual({ type: 'trade', trade: { price: 82642.9, quantity: 0.011, hitSide: 'ask', timeMs: 1791457528911 } })
    const sell = structuredClone(fx.bybitLinearTrade)
    sell.data[0].S = 'Sell'
    expect(msgs(decodeBybit(S(sell), map))[0]).toMatchObject({ trade: { hitSide: 'bid' } })
    const spot = book('bybit', 'spot', 'BTCUSDT')
    const st = msgs(decodeBybit(S(fx.bybitSpotTrade), new Map([['BTCUSDT', spot]])))
    expect(st.length).toBe(fx.bybitSpotTrade.data.length)
    const inv = book('bybit', 'coinPerp', 'ETHUSD', 1, { kind: 'inverse', contractUsd: 1 })
    const it2 = msgs(decodeBybit(S(fx.bybitInverseTrade), new Map([['ETHUSD', inv]])))
    expect(it2[0]).toMatchObject({ trade: { price: 2544.39, quantity: 424 } })
  })

  it('不认识的 symbol、爆仓 topic 不进簿', () => {
    expect(decodeBybit(S(fx.bybitLinearLiq), map)).toEqual([])
    expect(decodeBybit(S({ ...fx.bybitLinearTrade, topic: 'publicTrade.ETHUSDT' }), map)).toEqual([])
  })

  it('连接：一个 category 一组、每条 ≤ 12 本、每条订阅消息 ≤ 10 个 args；直连在前中继在后，网关线路只走中继', () => {
    const books = [
      ...Array.from({ length: 13 }, (_, i) => book('bybit', 'usdtPerp', `C${i}USDT`)),
      book('bybit', 'spot', 'BTCUSDT'),
      book('bybit', 'coinPerp', 'BTCUSD', 1, { kind: 'inverse', contractUsd: 1 }),
    ]
    const specs = connectionSpecs(books, { route: 'direct', gw: 'wss://gw.example' })
    expect(specs.map(s => s.key)).toEqual(['bybit-spot0', 'bybit-linear0', 'bybit-linear1', 'bybit-inverse0'])
    expect(specs.every(s => s.books.length <= BYBIT_MAX_BOOKS)).toBe(true)
    expect(specs[1].urls).toEqual(['wss://stream.bybit.com/v5/public/linear', 'wss://gw.example/v1/market/ws/bybit?category=linear'])
    expect(specs[1].ping).toEqual({ text: '{"op":"ping"}', everyMs: 20_000 })
    const subs = specs[1].subscribe().map(m => JSON.parse(m) as { op: string; args: string[] })
    expect(subs.every(m => m.op === 'subscribe' && m.args.length <= BYBIT_ARGS_PER_MESSAGE)).toBe(true)
    expect(subs.flatMap(m => m.args)).toHaveLength(24)
    expect(subs[0].args.slice(0, 2)).toEqual(['orderbook.1000.C0USDT', 'publicTrade.C0USDT'])
    const gw = connectionSpecs(books, { route: 'gateway', gw: 'wss://gw.example' })
    expect(gw[0].urls).toEqual(['wss://gw.example/v1/market/ws/bybit?category=spot'])
    expect(bybitSubscribe([])).toEqual([])
  })
})

describe('Hyperliquid：解码与本地簿', () => {
  const b = book('hyperliquid', 'usdtPerp', 'BTC')
  const map = new Map([['BTC', b]])

  it('snapshotOnly：每帧整本替换，20 档窗口', () => {
    expect(b.venue.sequenceModel).toBe('snapshotOnly')
    const vb = new VenueBook(b.venue)
    vb.connectionOpened()
    expect(vb.isReady).toBe(false) // 连上到第一帧之间算 bootstrapping
    const [m] = msgs(decodeHyperliquid(S(fx.hlL2Book), map))
    expect(m.type).toBe('snapshot')
    if (m.type !== 'snapshot') return
    expect(m.snapshot.requestedLevels).toBe(HL_WINDOW)
    expect(m.snapshot.bids[0]).toEqual({ price: 82640, quantity: 7.49922 })
    expect(vb.ingest(m, 1)).toBe('none')
    expect(vb.isReady).toBe(true)
    const next = structuredClone(fx.hlL2BookNext)
    next.data.time += 500
    next.data.levels[0] = [{ px: '82000.0', sz: '1.5', n: 3 }]
    vb.ingest(msgs(decodeHyperliquid(S(next), map))[0], 2)
    expect(vb.book.quantity(82640, 'bid')).toBe(0) // 上一帧的档整本换掉
    expect(vb.book.quantity(82000, 'bid')).toBe(1.5)
  })

  it('kPEPE：一单位 1000 个币，按图的倍数换算', () => {
    const k = book('hyperliquid', 'usdtPerp', 'kPEPE', 1000 / 1000)
    const [m] = msgs(decodeHyperliquid(S(fx.hlKpepeBook), new Map([['kPEPE', k]])))
    expect(m.type === 'snapshot' && m.snapshot.bids[0].price).toBeCloseTo(0.004031, 9)
    const fb = fallbackBooks('1000PEPEUSDT', 'PEPE', 1000).find(x => x.venue.exchange === 'hyperliquid')!
    expect(fb.venue.instrument).toBe('kPEPE')
    expect(fb.priceFactor).toBe(1)
    expect(fallbackBooks('BTCUSDT', 'BTC', 1).find(x => x.venue.exchange === 'hyperliquid')!.venue.instrument).toBe('BTC')
    expect(fallbackBooks('BTCUSDT', 'BTC', 1).find(x => x.venue.exchange === 'bybit')!.venue.instrument).toBe('BTCUSDT')
  })

  it('subscriptionResponse、pong 不理；成交 B = 主动买 → hit ask，A → hit bid', () => {
    for (const f of [...fx.hlSubResp, fx.hlPong]) expect(decodeHyperliquid(S(f), map)).toEqual([])
    const all = new Map(['BTC', 'ETH', 'SOL'].map(c => [c, book('hyperliquid', 'usdtPerp', c)]))
    const out = decodeHyperliquid(S(fx.hlTrades), all)
    expect(out.map(([id, m]) => [id.split(':')[2], m.type === 'trade' && m.trade.hitSide]))
      .toEqual([['BTC', 'ask'], ['BTC', 'ask'], ['ETH', 'bid'], ['ETH', 'ask'], ['SOL', 'bid'], ['SOL', 'ask']])
  })

  it('连接：恒走中继、每条 ≤ 8 本、nSigFigs 4、30 秒 ping、60 秒没帧重连', () => {
    const books = Array.from({ length: 9 }, (_, i) => book('hyperliquid', 'usdtPerp', `C${i}`))
    const specs = connectionSpecs(books, { route: 'direct', gw: 'wss://gw.example' })
    expect(specs.map(s => s.books.length)).toEqual([HL_MAX_BOOKS, 1])
    expect(specs[0].urls).toEqual(['wss://gw.example/v1/market/ws/hyperliquid'])
    expect(specs[0].ping).toEqual({ text: '{"method":"ping"}', everyMs: 30_000 })
    expect(specs[0].silenceMs).toBe(HL_SILENCE_MS)
    expect(HL_SILENCE_MS).toBe(60_000)
    expect(hlSubscribe([b]).map(m => JSON.parse(m))).toEqual([
      { method: 'subscribe', subscription: { type: 'l2Book', coin: 'BTC', nSigFigs: 4 } },
      { method: 'subscribe', subscription: { type: 'trades', coin: 'BTC' } },
    ])
  })
})
