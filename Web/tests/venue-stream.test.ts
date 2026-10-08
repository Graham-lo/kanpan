/* 多交易所 · 别家的推送（market/venueStream.ts）：要订什么、并线周期、逐笔拼 K 线、推来的落进品种表、连接与线路。
 * 报文按官方文档手写（来源见 tests/venues-market.test.ts 头注释）；WebSocket 用假的。 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { AggBar, TradeBar, handle, parseStream, planStreams, setVenueStreams, setVenueRoute, venueStreamDebug } from '../src/market/venueStream'
import { S, on } from '../src/market/state'
import { streamName } from '../src/market/stream'
import { okxMarket } from '../src/venues/okx'
import type { MarketEvent } from '../src/market/state'
import type { Sym } from '../src/market/symbols'

const OKX = 'okx/usd_m/BTCUSDT', BY = 'bybit/usd_m/BTCUSDT', HL = 'hyperliquid/usd_m/BTC', CB = 'coinbase/spot/BTC-USD'

describe('要订什么', () => {
  it('流名解析', () => {
    expect(parseStream(`${OKX}@kline_8h`)).toEqual({ key: OKX, kind: 'kline', iv: '8h' })
    expect(parseStream(`${OKX}@markPrice@1s`)).toEqual({ key: OKX, kind: 'mark' })
    expect(parseStream('nope')).toBeNull()
  })
  it('OKX：K 线在 business 端点，其余在 public；8 时订 4 时并；标记价 = mark-price + funding-rate', () => {
    const p = planStreams([streamName.kline(OKX, '1h'), streamName.kline(OKX, '8h'), streamName.ticker(OKX), streamName.mark(OKX)])
    expect(Object.fromEntries(p.topics.get('okx')!)).toEqual({
      business: ['candle1H|BTC-USDT-SWAP', 'candle4H|BTC-USDT-SWAP'],
      public: ['tickers|BTC-USDT-SWAP', 'mark-price|BTC-USDT-SWAP', 'funding-rate|BTC-USDT-SWAP'],
    })
    expect([...p.agg]).toEqual([[`${OKX}|8h`, '4h']])
  })
  it('Bybit / Hyperliquid：行情与标记价共用一个 topic，只订一次', () => {
    const p = planStreams([streamName.ticker(BY), streamName.mark(BY), streamName.trade(BY), streamName.ticker(HL), streamName.mark(HL), streamName.kline(HL, '6h')])
    expect(p.topics.get('bybit')!.get('linear')).toEqual(['tickers.BTCUSDT', 'publicTrade.BTCUSDT'])
    expect(p.topics.get('hyperliquid')!.get('main')).toEqual(['activeAssetCtx|BTC', 'candle|BTC|2h'])
    expect([...p.agg]).toEqual([[`${HL}|6h`, '2h']])
  })
  it('Coinbase 没有任意周期的 K 线推送：订逐笔、由这里拼', () => {
    const p = planStreams([streamName.kline(CB, '1h'), streamName.ticker(CB)])
    expect(p.topics.get('coinbase')!.get('main')).toEqual(['market_trades|BTC-USD', 'ticker|BTC-USD'])
    expect([...p.fromTrades]).toEqual([`${CB}|1h`])
  })
  it('每条连接最多 maxTopics 个，排在后面的不订', () => {
    const names = Array.from({ length: 60 }, (_, i) => streamName.ticker(`bybit/usd_m/C${i}USDT`))
    expect(planStreams(names).topics.get('bybit')!.get('linear')!.length).toBe(48)
  })
})

describe('并线与逐笔拼', () => {
  it('8 时 ← 4 时：垫底之前不出；垫底后合成这一格；下一格开始清掉上一格', () => {
    const H4 = 4 * 3600e3, t0 = Date.UTC(2026, 9, 8, 8)
    const a = new AggBar('8h')
    expect(a.push({ t: t0 + H4, o: 5, h: 6, l: 4, c: 5.5, v: 2 })).toBeNull()
    expect(a.seed([{ t: t0, o: 1, h: 3, l: 1, c: 2, v: 1 }])).toEqual({ t: t0, o: 1, h: 6, l: 1, c: 5.5, v: 3 })
    expect(a.push({ t: t0 + H4, o: 5, h: 7, l: 4, c: 6, v: 3 })).toEqual({ t: t0, o: 1, h: 7, l: 1, c: 6, v: 4 })
    expect(a.push({ t: t0 + 2 * H4, o: 6, h: 6, l: 6, c: 6, v: 1 })).toEqual({ t: t0 + 2 * H4, o: 6, h: 6, l: 6, c: 6, v: 1 })
  })
  it('逐笔拼：REST 那根垫底，之后的逐笔往上并；跨格开新的一根；垫底前来的先攒着', () => {
    const t = new TradeBar('1m')
    expect(t.trade(105, 1, 60_500)).toBeNull()
    expect(t.seed({ t: 60_000, o: 100, h: 104, l: 99, c: 101, v: 50 })).toEqual({ t: 60_000, o: 100, h: 105, l: 99, c: 105, v: 155, bv: 1 })
    expect(t.trade(98, 2, 61_000)).toMatchObject({ t: 60_000, l: 98, c: 98 })
    expect(t.trade(97, 1, 120_000)).toEqual({ t: 120_000, o: 97, h: 97, l: 97, c: 97, v: 97, bv: 1 })
  })
})

describe('推来的落进品种表', () => {
  const sym = (): Sym => ({ symbol: BY, venue: 'bybit', quote: 'USDT', base: 'BTC', code: 'BTC', kind: 'crypto', cn: '', dec: 1, color: '', price: 100, chg: 0, pct: 0, vol: 0, fr: null, nextFunding: null, open: 100, pxAt: 10 })
  beforeEach(() => { S.symbols = new Map([[BY, sym()]]) })
  it('行情按交易所时间拒旧；发 ticker / mark 事件', () => {
    const seen: MarketEvent[] = []
    const off = on(e => seen.push(e))
    handle({ type: 'quote', quote: { key: BY, price: 110, mark: 109, fr: 0.0001, at: 20 } })
    handle({ type: 'quote', quote: { key: BY, price: 90, at: 15 } })   // 旧的不覆盖
    off()
    const s = S.symbols.get(BY)!
    expect([s.price, s.pct, s.mark, s.fr]).toEqual([110, 10.000000000000009, 109, 0.0001])
    expect(seen.filter(e => e.type === 'ticker').map(e => (e as { dir: number }).dir)).toEqual([1, 0])
    expect(seen.some(e => e.type === 'mark')).toBe(true)
  })
  it('逐笔：当前价跟着走、逐笔旁路照发', async () => {
    const { tapTrade } = await import('../src/market/trades')
    const got: number[] = []
    const off = tapTrade(t => got.push(t.price))
    handle({ type: 'trade', key: BY, price: 120, qty: 1, t: 30, sell: false })
    off()
    expect(S.symbols.get(BY)!.price).toBe(120)
    expect(got).toEqual([120])
  })
})

// ------------------------------------------------------------ 连接（假 WebSocket）
class FakeWS {
  static all: FakeWS[] = []
  static OPEN = 1
  readyState = 0
  sent: string[] = []
  onopen: (() => void) | null = null
  onmessage: ((e: { data: string }) => void) | null = null
  onclose: (() => void) | null = null
  onerror: (() => void) | null = null
  constructor(readonly url: string) { FakeWS.all.push(this) }
  send(t: string): void { this.sent.push(t) }
  close(): void { this.readyState = 3 }
  open(): void { this.readyState = 1; this.onopen?.() }
}

describe('连接：一家一条（OKX K 线另一条），线路由用户选', () => {
  beforeEach(() => { vi.useFakeTimers(); FakeWS.all = []; vi.stubGlobal('WebSocket', FakeWS); S.route = 'direct'; S.symbols = new Map() })
  afterEach(() => { setVenueStreams([]); vi.useRealTimers(); vi.unstubAllGlobals(); S.route = 'direct' })

  it('直连拨交易所；网关只连中继（K 线 ?endpoint=business）；订阅按控制帧节奏发', async () => {
    vi.spyOn(okxMarket, 'klines').mockResolvedValue([])
    setVenueStreams([streamName.kline(OKX, '1h'), streamName.ticker(OKX), streamName.ticker(BY)])
    // OKX 新连接按 IP 3 次 / 秒：第二条隔 400 ms 才开
    expect(FakeWS.all.filter(w => w.url.includes('okx')).length).toBe(1)
    vi.advanceTimersByTime(400)
    expect(FakeWS.all.map(w => w.url).sort()).toEqual(['wss://stream.bybit.com/v5/public/linear', 'wss://ws.okx.com:8443/ws/v5/business', 'wss://ws.okx.com:8443/ws/v5/public'])
    const pub = FakeWS.all.find(w => w.url.endsWith('/public'))!
    pub.open()
    expect(pub.sent).toEqual([JSON.stringify({ op: 'subscribe', args: [{ channel: 'tickers', instId: 'BTC-USDT-SWAP' }] })])
    S.route = 'gateway'
    FakeWS.all = []
    setVenueRoute()
    vi.advanceTimersByTime(800)
    expect(FakeWS.all.map(w => w.url).sort()).toEqual([
      'wss://kanpan.43-160-232-253.sslip.io/v1/market/ws/bybit?category=linear',
      'wss://kanpan.43-160-232-253.sslip.io/v1/market/ws/okx',
      'wss://kanpan.43-160-232-253.sslip.io/v1/market/ws/okx?endpoint=business',
    ])
  })
  it('断了按退避重连同一条线路（不换线路），重连后补订', () => {
    setVenueStreams([streamName.ticker(BY)])
    const w = FakeWS.all[0]
    w.open()
    w.onclose?.()
    expect(S.wsState).toBe('closed')
    vi.advanceTimersByTime(1000)
    const again = FakeWS.all[1]
    expect(again.url).toBe('wss://stream.bybit.com/v5/public/linear')
    again.open()
    expect(again.sent).toEqual([JSON.stringify({ op: 'subscribe', args: ['tickers.BTCUSDT'] })])
    again.onmessage?.({ data: JSON.stringify({ topic: 'tickers.BTCUSDT', type: 'snapshot', ts: 1, data: { symbol: 'BTCUSDT', lastPrice: '1' } }) })
    expect(S.wsState).toBe('open')
  })
  it('OKX 每条连接订 / 退每小时最多 480 条：满了排到窗口滚出再发，不丢不重连', () => {
    const names = (n: number) => [streamName.ticker(`okx/usd_m/C${n}USDT`)]
    setVenueStreams(names(0))
    const w = FakeWS.all[0]
    w.open()
    const tick = () => w.onmessage?.({ data: JSON.stringify({ arg: { channel: 'tickers', instId: 'C0-USDT-SWAP' }, data: [{ instId: 'C0-USDT-SWAP', last: '1', ts: '1' }] }) })
    for (let i = 1; i <= 260; i++) { tick(); setVenueStreams(names(i)); vi.advanceTimersByTime(600) }   // 每次一退一订
    const control = () => w.sent.filter(x => x !== 'ping').length   // 保活的 ping 不算订退
    expect(control()).toBe(480)
    for (let k = 0; k < 130; k++) { tick(); vi.advanceTimersByTime(28_000) }   // 连接一直活着，额度滚出窗口后补发
    expect(control()).toBe(521)
  })

  it('不要了就退订；全不要了关掉连接', () => {
    setVenueStreams([streamName.ticker(BY), streamName.trade(BY)])
    const w = FakeWS.all[0]
    w.open()
    vi.advanceTimersByTime(300)
    setVenueStreams([streamName.ticker(BY)])
    vi.advanceTimersByTime(300)
    expect(w.sent.at(-1)).toBe(JSON.stringify({ op: 'unsubscribe', args: ['publicTrade.BTCUSDT'] }))
    setVenueStreams([])
    expect(venueStreamDebug().conns).toEqual([])
    expect(w.readyState).toBe(3)
  })
})
