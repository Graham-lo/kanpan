/* 压测 · 别家的推送（market/venueStream.ts）：假 WebSocket、假时钟。
 *   每家 200 个订阅、100 次快速切品种：控制帧次数最少、最后订着的正好是最后要的；
 *   OKX 每连接每小时 480 条订 / 退：任意一小时不越线、排着的不丢（最后收敛到要的那一份）；
 *   Bybit 每帧 ≤ 10 个 args；HL 一帧一个订阅；Coinbase 一个频道一帧；
 *   重连风暴退避单调（1 → 2 → 4 → 8 → 15 → 15 s），风暴中再调 setVenueStreams 不绕过退避；
 *   页面隐藏只留核心流、回前台补回；换线路老连接全收、不留定时器；全不要了 pending timers 为 0；
 *   Hyperliquid 品种表晚到：已经按大写 KPEPE 订的那一路改订原名 kPEPE。 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { setVenueStreams, setVenueRoute, venueStreamDebug } from '../src/market/venueStream'
import { S, emit } from '../src/market/state'
import { streamName } from '../src/market/stream'
import { decodeHlUniverse } from '../src/venues/hyperliquid'
import { okxMarket } from '../src/venues/okx'
import { bybitMarket } from '../src/venues/bybit'
import { hlMarket } from '../src/venues/hyperliquid'
import { cbMarket } from '../src/venues/coinbase'

class FakeWS {
  static all: FakeWS[] = []
  static OPEN = 1
  static autoOpen = false
  readyState = 0
  sent: { t: number; text: string }[] = []
  onopen: (() => void) | null = null
  onmessage: ((e: { data: string }) => void) | null = null
  onclose: (() => void) | null = null
  onerror: (() => void) | null = null
  constructor(readonly url: string) { FakeWS.all.push(this); if (FakeWS.autoOpen) queueMicrotask(() => this.open()) }
  send(t: string): void { if (this.readyState !== 1) throw new Error('send on closed socket'); this.sent.push({ t: Date.now(), text: t }) }
  close(): void { this.readyState = 3 }
  open(): void { this.readyState = 1; this.onopen?.() }
  kill(): void { this.readyState = 3; this.onclose?.() }
  control(): string[] { return this.sent.map(x => x.text).filter(x => !/ping/.test(x)) }
}
const live = (): FakeWS[] => FakeWS.all.filter(w => w.readyState !== 3)
const byUrl = (part: string): FakeWS[] => live().filter(w => w.url.includes(part))

const OKX = (b: string) => `okx/usd_m/${b}USDT`
const BY = (b: string) => `bybit/usd_m/${b}USDT`
const HLK = (b: string) => `hyperliquid/usd_m/${b}`
const CB = (b: string) => `coinbase/spot/${b}-USD`
const coins = Array.from({ length: 200 }, (_, i) => `C${i}`)

beforeEach(() => {
  vi.useFakeTimers({ now: 1_800_000_000_000 })
  FakeWS.all = []; FakeWS.autoOpen = false
  vi.stubGlobal('WebSocket', FakeWS)
  S.route = 'direct'; S.symbols = new Map()
  // 并线 / 逐笔垫底的 REST 不出网
  for (const m of [okxMarket, bybitMarket, hlMarket, cbMarket]) vi.spyOn(m, 'klines').mockResolvedValue([])
})
afterEach(() => { setVenueStreams([]); vi.clearAllTimers(); vi.useRealTimers(); vi.unstubAllGlobals(); vi.restoreAllMocks(); S.route = 'direct' })

/** 一家 200 只的行情 + 第一只的 K 线（当前格） */
function names(mk: (b: string) => string, cur: string, iv = '1m'): string[] {
  return [streamName.kline(mk(cur), iv), ...coins.map(c => streamName.ticker(mk(c)))]
}
const parse = (f: string) => JSON.parse(f) as Record<string, unknown>

/** 各家一帧能解出东西的数据帧（让连接算「活着」：连上 8 秒没帧、静默 30 秒都当断线） */
function frameFor(w: FakeWS): string {
  if (w.url.includes('okx')) return JSON.stringify({ arg: { channel: 'tickers', instId: 'C0-USDT-SWAP' }, data: [{ instId: 'C0-USDT-SWAP', last: '1', ts: String(Date.now()) }] })
  if (w.url.includes('bybit')) return JSON.stringify({ topic: 'tickers.C0USDT', type: 'snapshot', ts: Date.now(), data: { symbol: 'C0USDT', lastPrice: '1' } })
  if (w.url.includes('hyperliquid')) return JSON.stringify({ channel: 'trades', data: [{ coin: 'C0', px: '1', sz: '1', time: Date.now(), side: 'B' }] })
  return JSON.stringify({ channel: 'ticker', timestamp: new Date().toISOString(), events: [{ tickers: [{ product_id: 'C0-USD', price: '1' }] }] })
}
/** 推着假时钟走，每秒给开着的连接各喂一帧 */
async function run(ms: number, step = 1000): Promise<void> {
  for (let t = 0; t < ms; t += step) {
    for (const w of live()) if (w.readyState === 1) w.onmessage?.({ data: frameFor(w) })
    await vi.advanceTimersByTimeAsync(Math.min(step, ms - t))
  }
}

describe('每家 200 个订阅：上限、拆帧', () => {
  it('OKX：public 48 个 topic 4 帧（一帧 ≤ 12 args），business 一条 K 线；Bybit 一帧 ≤ 10 args；HL 一帧一个；CB 一个频道一帧', async () => {
    setVenueStreams([...names(OKX, 'C0'), ...names(BY, 'C0'), ...names(HLK, 'C0'), ...names(CB, 'C0')])
    await vi.advanceTimersByTimeAsync(500)
    for (const w of live()) w.open()
    await run(60_000)
    const pub = byUrl('/ws/v5/public')[0], biz = byUrl('/ws/v5/business')[0]
    expect(pub.control().length).toBe(4)
    expect(pub.control().every(f => (parse(f).args as unknown[]).length <= 12)).toBe(true)
    expect(biz.control()).toEqual([JSON.stringify({ op: 'subscribe', args: [{ channel: 'candle1m', instId: 'C0-USDT-SWAP' }] })])
    const by = byUrl('bybit')[0]
    expect(by.control().length).toBe(5)
    expect(by.control().every(f => (parse(f).args as unknown[]).length <= 10)).toBe(true)
    const hl = byUrl('hyperliquid')[0]
    expect(hl.control().length).toBe(32)
    const cb = byUrl('coinbase')[0]
    // heartbeats + market_trades（K 线由逐笔拼）+ ticker
    expect(cb.control().map(f => parse(f).channel)).toEqual(['heartbeats', 'market_trades', 'ticker'])
    expect((parse(cb.control()[2]).product_ids as string[]).length).toBe(47)
    // 控制帧之间的间隔：同一条连接两条之间 ≥ 250 ms（HL / CB 官方按 IP 计上行）
    for (const w of [hl, cb, by, pub]) {
      const ts = w.sent.filter(x => !/ping/.test(x.text)).map(x => x.t)
      for (let i = 1; i < ts.length; i++) expect(ts[i] - ts[i - 1]).toBeGreaterThanOrEqual(250)
    }
  })
})

describe('100 次快速切品种：控制帧最少，最后订着的正好是最后要的', () => {
  const cases: [string, (b: string) => string, string][] = [['OKX', OKX, '/ws/v5/business'], ['Bybit', BY, 'bybit'], ['Hyperliquid', HLK, 'hyperliquid']]
  for (const [name, mk, part] of cases) {
    it(`${name}：每 20 ms 换一次当前格的 K 线（其余 199 只行情不动）`, async () => {
      setVenueStreams(names(mk, 'C0'))
      await vi.advanceTimersByTimeAsync(500)
      for (const w of live()) w.open()
      await run(30_000)
      const w = byUrl(part)[0]
      const before = w.control().length
      for (let i = 1; i <= 100; i++) { setVenueStreams(names(mk, `C${i % 200}`, i % 2 ? '5m' : '1m')); await vi.advanceTimersByTimeAsync(20) }
      await run(60_000)
      expect(byUrl(part)[0]).toBe(w)
      const extra = w.control().length - before
      // 原来每切一次排一退一订两条，100 次 = 200 条，全按 250 ms 一条慢慢发，最后要的那只排在 50 秒之后；
      // 现在排着的期间只记「要什么」，轮到发时按最后要的那一份对账：至多几条
      // 2 秒的连切：能发的节拍（250 ms 一条）每拍对一次账，至多 2000 / 250 + 收尾的一退一订 + 余量
      expect(extra).toBeLessThanOrEqual(12)
      const want = venueStreamDebug().conns.find(c => c.url === w.url)!.subscribed
      const last = name === 'OKX' ? 'candle1m|C100-USDT-SWAP' : name === 'Bybit' ? 'kline.1.C100USDT' : 'candle|C100|1m'
      expect(want).toContain(last)
      expect(want.filter(t => /candle|kline/.test(t))).toEqual([last])
    })
  }
  it('最后要的那一只在切完 1 秒内就订上（不排在一长串作废的帧后面）', async () => {
    setVenueStreams(names(BY, 'C0'))
    await vi.advanceTimersByTimeAsync(10)
    byUrl('bybit')[0].open()
    await vi.advanceTimersByTimeAsync(5_000)
    for (let i = 1; i <= 100; i++) { setVenueStreams(names(BY, `C${i}`)); await vi.advanceTimersByTimeAsync(5) }
    const w = byUrl('bybit')[0]
    await vi.advanceTimersByTimeAsync(1_000)
    const sentArgs = w.control().flatMap(f => (parse(f).op === 'subscribe' ? parse(f).args as string[] : []))
    expect(sentArgs).toContain('kline.1.C100USDT')
  })
})

describe('OKX 每条连接订 / 退每小时 ≤ 480：任意一小时不越线、不丢', () => {
  it('3 小时里每 2 秒切一次（远超额度）：任意滚动一小时控制帧 ≤ 480，最后收敛到最后要的那一只', async () => {
    setVenueStreams([streamName.ticker(OKX('C0'))])
    await vi.advanceTimersByTimeAsync(10)
    const w = byUrl('/public')[0]
    w.open()
    const tick = () => w.onmessage?.({ data: JSON.stringify({ arg: { channel: 'tickers', instId: 'C0-USDT-SWAP' }, data: [{ instId: 'C0-USDT-SWAP', last: '1', ts: String(Date.now()) }] }) })
    let i = 0
    for (let t = 0; t < 3 * 3600_000; t += 2000) { i++; tick(); setVenueStreams([streamName.ticker(OKX(`C${i}`))]); await vi.advanceTimersByTimeAsync(2000) }
    for (let k = 0; k < 40; k++) { tick(); await vi.advanceTimersByTimeAsync(25_000) }
    expect(live().filter(x => x.url.includes('okx')).length).toBe(1)   // 没有因为额度满了重连
    const ts = w.sent.filter(x => x.text !== 'ping').map(x => x.t)
    let worst = 0
    for (let a = 0, b = 0; b < ts.length; b++) { while (ts[b] - ts[a] >= 3600_000) a++; worst = Math.max(worst, b - a + 1) }
    expect(worst).toBeLessThanOrEqual(480)
    expect(venueStreamDebug().conns[0].subscribed).toEqual([`tickers|C${i}-USDT-SWAP`])
  })
})

describe('重连风暴', () => {
  it('一开就断：退避 1 → 2 → 4 → 8 → 15 → 15 s 单调；风暴中反复 setVenueStreams 不绕过退避、不多开', async () => {
    const list = [streamName.ticker(BY('C0'))]
    setVenueStreams(list)
    const opened: number[] = []
    let seen = 0
    for (let k = 0; k < 120_000 / 100; k++) {
      while (seen < FakeWS.all.length) { const w = FakeWS.all[seen++]; opened.push(Date.now()); w.open(); w.kill() }
      if (k % 3 === 0) setVenueStreams([...list])   // 页面别处一直在重算要什么
      await vi.advanceTimersByTimeAsync(100)
    }
    const gaps = opened.slice(1).map((t, i) => t - opened[i])
    for (let i = 1; i < gaps.length; i++) expect(gaps[i]).toBeGreaterThanOrEqual(gaps[i - 1] - 100)
    expect(gaps.slice(0, 5).map(g => Math.round(g / 1000))).toEqual([1, 2, 4, 8, 15])
    expect(Math.max(...gaps)).toBeLessThanOrEqual(15_100)
    expect(S.wsState).toBe('closed')
  })
  it('收到一帧就算活了：退避清零，下次断从 1 秒起', async () => {
    setVenueStreams([streamName.ticker(BY('C0'))])
    for (let k = 0; k < 3; k++) { const w = FakeWS.all.at(-1)!; w.open(); w.kill(); await vi.advanceTimersByTimeAsync(20_000) }
    const w = FakeWS.all.at(-1)!
    w.open()
    w.onmessage?.({ data: JSON.stringify({ topic: 'tickers.C0USDT', type: 'snapshot', ts: 1, data: { symbol: 'C0USDT', lastPrice: '1' } }) })
    const n = FakeWS.all.length
    w.kill()
    await vi.advanceTimersByTimeAsync(999)
    expect(FakeWS.all.length).toBe(n)
    await vi.advanceTimersByTimeAsync(2)
    expect(FakeWS.all.length).toBe(n + 1)
  })
})

describe('换线路 / 全不要了：老连接全收、不留定时器', () => {
  it('四家都开着时换到网关：老连接全关且不再收帧，新连接全是中继；再全不要了 pending timers 为 0', async () => {
    setVenueStreams([...names(OKX, 'C0').slice(0, 5), ...names(BY, 'C0').slice(0, 5), ...names(HLK, 'C0').slice(0, 5), ...names(CB, 'C0').slice(0, 5)])
    await vi.advanceTimersByTimeAsync(500)
    for (const w of live()) w.open()
    await run(5_000)
    const old = live()
    expect(old.length).toBe(5)
    S.route = 'gateway'
    setVenueRoute()
    await vi.advanceTimersByTimeAsync(500)
    expect(old.every(w => w.readyState === 3 && w.onmessage == null && w.onclose == null)).toBe(true)
    const fresh = live()
    expect(fresh.length).toBe(5)
    expect(fresh.every(w => w.url.startsWith('wss://kanpan.43-160-232-253.sslip.io/'))).toBe(true)
    for (const w of fresh) w.open()
    await run(30_000)
    setVenueStreams([])
    expect(live()).toEqual([])
    expect(vi.getTimerCount()).toBe(0)
  })
  it('一直连不上、退避中全不要了：退避定时器也收掉', async () => {
    setVenueStreams([streamName.ticker(OKX('C0')), streamName.kline(OKX('C0'), '1m')])
    await vi.advanceTimersByTimeAsync(500)
    for (const w of live()) w.kill()
    expect(vi.getTimerCount()).toBeGreaterThan(0)
    setVenueStreams([])
    expect(vi.getTimerCount()).toBe(0)
  })
})

describe('Hyperliquid 品种表晚到：大写键译回原名', () => {
  it('表没到时按大写 KPEPE 订了；表一到（universe）改订原名 kPEPE，大写那一路退掉', async () => {
    setVenueStreams([streamName.ticker(HLK('KPEPE')), streamName.trade(HLK('KPEPE'))])
    await vi.advanceTimersByTimeAsync(10)
    const w = byUrl('hyperliquid')[0]
    w.open()
    await vi.advanceTimersByTimeAsync(2_000)
    decodeHlUniverse([{ universe: [{ name: 'kPEPE', szDecimals: 0 }] }, []])
    emit({ type: 'universe' })
    await vi.advanceTimersByTimeAsync(5_000)
    const coinsSubbed = (on: string) => w.control().map(parse).filter(f => f.method === on).map(f => (f.subscription as { coin: string }).coin)
    expect(new Set(venueStreamDebug().conns[0].subscribed)).toEqual(new Set(['activeAssetCtx|kPEPE', 'trades|kPEPE']))
    expect(coinsSubbed('subscribe').slice(-2)).toEqual(['kPEPE', 'kPEPE'])
    expect(coinsSubbed('unsubscribe')).toEqual(['KPEPE', 'KPEPE'])
  })
})

describe('页面隐藏只留核心流', () => {
  it('隐藏：只订核心几路（其余退掉）；回前台补回；连接不重开', async () => {
    const vis = { state: 'visible' as 'visible' | 'hidden', fns: [] as (() => void)[] }
    vi.stubGlobal('document', { get visibilityState() { return vis.state }, addEventListener: (_: string, f: () => void) => vis.fns.push(f) })
    vi.resetModules()
    const vs = await import('../src/market/venueStream')
    const { streamName: sn } = await import('../src/market/stream')
    const all = [sn.kline(BY('C0'), '1m'), sn.ticker(BY('C0')), ...coins.slice(1, 30).map(c => sn.ticker(BY(c)))]
    const core = all.slice(0, 2)
    vs.setVenueStreams(all, core)
    await vi.advanceTimersByTimeAsync(10)
    const w = byUrl('bybit')[0]
    w.open()
    await run(5_000)
    expect(vs.venueStreamDebug().conns[0].subscribed.length).toBe(31)
    vis.state = 'hidden'; vis.fns.forEach(f => f())
    await run(5_000)
    expect(new Set(vs.venueStreamDebug().conns[0].subscribed)).toEqual(new Set(['kline.1.C0USDT', 'tickers.C0USDT']))
    vis.state = 'visible'; vis.fns.forEach(f => f())
    await run(5_000)
    expect(vs.venueStreamDebug().conns[0].subscribed.length).toBe(31)
    expect(FakeWS.all.filter(x => x.url.includes('bybit')).length).toBe(1)
    vs.setVenueStreams([])
    expect(vi.getTimerCount()).toBe(0)
  })
})
