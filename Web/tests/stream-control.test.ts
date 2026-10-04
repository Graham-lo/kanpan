/* Web 深度审查 C 线 2026-10-05 · 推送连接池对上游的三条硬规矩（market/stream.ts）：
 *   流名先过闸（网关 stream_hub 的 STREAM 正则）、控制消息限速（令牌桶）、订阅回执按 id 对账 */
import { afterEach, describe, expect, it, vi } from 'vitest'

class FakeWS {
  static OPEN = 1; static CONNECTING = 0; static CLOSED = 3
  static all: FakeWS[] = []
  readyState = 0
  sent: any[] = []
  sentAt: number[] = []
  onopen: (() => void) | null = null
  onmessage: ((e: { data: string }) => void) | null = null
  onclose: (() => void) | null = null
  onerror: (() => void) | null = null
  constructor(public url: string) { FakeWS.all.push(this) }
  send(s: string) { this.sent.push(JSON.parse(s)); this.sentAt.push(Date.now()) }
  close() { this.readyState = 3 }
  open() { this.readyState = 1; this.onopen?.() }
  push(o: unknown) { this.onmessage?.({ data: JSON.stringify(o) }) }
}

afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); vi.resetModules(); FakeWS.all = [] })

async function load(route: 'direct' | 'gateway') {
  vi.useFakeTimers()
  vi.stubGlobal('WebSocket', FakeWS)
  vi.stubGlobal('location', { protocol: 'https:', host: 'k.example' })
  vi.resetModules()
  const m = await import('../src/market')
  const stream = await import('../src/market/stream')
  if (route === 'gateway') stream.setRoute('gateway')
  return { ...m, ...stream }
}

const kline = (s: string) => ({ stream: `${s}@kline_1m`, data: { e: 'kline', s: s.toUpperCase(), k: { t: 0, o: '1', h: '1', l: '1', c: '1', q: '1', Q: '1', v: '1', i: '1m' } } })

describe('流名过闸：网关不认的名字从不发出去（Coinbase 现货在手机自选 / 提醒里）', () => {
  it('握手 URL 里不带 btc-usd@ticker；中文底名的 龙虾usdt@ticker 照常带上', async () => {
    const m = await load('gateway')
    m.setStreams(['btcusdt@ticker', 'btc-usd@ticker', '龙虾usdt@ticker'], [], { now: true })
    expect(FakeWS.all).toHaveLength(1)
    const url = decodeURIComponent(FakeWS.all[0].url)
    expect(url).toContain('wss://k.example/market/stream?streams=')
    expect(url).not.toContain('btc-usd')
    expect(url).toContain('龙虾usdt@ticker')
    expect(m.streamDebug().subscribed).toEqual(['btcusdt@ticker', '龙虾usdt@ticker'])
  })

  it('连上以后再加进来的 Coinbase 名字也不进 SUBSCRIBE', async () => {
    const m = await load('gateway')
    m.setStreams(['btcusdt@ticker'], [], { now: true })
    FakeWS.all[0].open()
    m.setStreams(['btcusdt@ticker', 'eth-usd@ticker', 'ethusdt@ticker'], [], { now: true })
    expect(FakeWS.all[0].sent).toEqual([{ method: 'SUBSCRIBE', params: ['ethusdt@ticker'], id: expect.any(Number) }])
  })

  it('validStream 与 stream_hub.py 的 STREAM 正则同一口径', async () => {
    const { validStream } = await load('direct')
    for (const ok of ['btcusdt@ticker', 'btcusdt@markPrice@1s', 'btcusdt@aggTrade', 'btcusdt@kline_1M', '币安人生usdt@kline_15m', '1000pepeusdt@ticker', '!ticker@arr'])
      expect(validStream(ok, 'gateway'), ok).toBe(true)
    for (const bad of ['btc-usd@ticker', 'BTCUSDT@ticker', 'btcusdt@depth@100ms', 'btcusdt@kline_2m', 'btcusdt@markPrice', 'a'.repeat(31) + '@ticker', '@ticker'])
      expect(validStream(bad, 'gateway'), bad).toBe(false)
    expect(validStream('btcusdt@depth5@100ms', 'direct')).toBe(true)
    expect(validStream('btc-usd@ticker', 'direct')).toBe(false)
  })
})

describe('控制消息限速：快速换品种不再被网关以 control rate exceeded 掐断', () => {
  it('网关上一秒内连换 30 次品种：任何 1 秒窗口不超过 stream_hub 的突发 16 条、长期不超过 4 条/秒，最后订着的正是最后一只', async () => {
    const m = await load('gateway')
    m.setStreams(['btcusdt@ticker'], [], { now: true })
    const ws = FakeWS.all[0]
    ws.open(); ws.push(kline('btcusdt'))
    for (let i = 0; i < 30; i++) { m.setStreams([`s${i}usdt@ticker`], [], { now: true }); vi.advanceTimersByTime(33) }
    vi.advanceTimersByTime(10_000)
    const at = ws.sentAt
    // stream_hub 的 Bucket(4, 16)：按同样的桶回放一遍，必须一次都不透支
    let tokens = 16, last = at[0] ?? 0
    for (const t of at) { tokens = Math.min(16, tokens + (t - last) * 4 / 1000); last = t; tokens -= 1; expect(tokens).toBeGreaterThanOrEqual(-1e-9) }
    expect(m.streamDebug().subscribed).toEqual(['s29usdt@ticker'])
    expect(FakeWS.all).toHaveLength(1)
  })

  it('直连：任何 1 秒窗口不超过 10 条（币安每条连接的上限）', async () => {
    const m = await load('direct')
    m.setStreams(['btcusdt@ticker'], [], { now: true })
    const ws = FakeWS.all[0]
    ws.open(); ws.push(kline('btcusdt'))
    for (let i = 0; i < 40; i++) { m.setStreams([`s${i}usdt@ticker`], [], { now: true }); vi.advanceTimersByTime(20) }
    vi.advanceTimersByTime(10_000)
    const at = ws.sentAt
    for (let i = 0; i < at.length; i++) expect(at.filter(t => t >= at[i] && t < at[i] + 1000).length).toBeLessThanOrEqual(10)
    expect(m.streamDebug().subscribed).toEqual(['s39usdt@ticker'])
  })
})

describe('订阅回执按 id 对账', () => {
  it('SUBSCRIBE 回 error：那批订阅记成被拒、从订阅里拿掉，之后对账不再重发', async () => {
    const m = await load('direct')
    m.setStreams(['btcusdt@ticker'], [], { now: true })
    const ws = FakeWS.all[0]
    ws.open()
    ws.push(kline('btcusdt'))
    m.setStreams(['btcusdt@ticker', 'xyzusdt@ticker'], [], { now: true })
    const sub = ws.sent.at(-1)
    expect(sub.params).toEqual(['xyzusdt@ticker'])
    ws.push({ error: { code: 2, msg: 'Invalid request' }, id: sub.id })
    expect(m.streamDebug().subscribed).toEqual(['btcusdt@ticker'])
    m.setStreams(['btcusdt@ticker', 'xyzusdt@ticker', 'ethusdt@ticker'], [], { now: true })
    vi.advanceTimersByTime(2000)
    expect(ws.sent.slice(1).map(x => x.params)).toEqual([['ethusdt@ticker']])
  })

  it('想要的订阅全被拒：不再每 30 秒静默一次就重连一轮', async () => {
    const m = await load('direct')
    m.setStreams(['aaausdt@ticker'], [], { now: true })
    const ws = FakeWS.all[0]
    m.setStreams(['bbbusdt@ticker'], [], { now: true })   // 还没连上就换了名单：连上后对账 UNSUB + SUB
    ws.open()
    const sub = ws.sent.find(x => x.method === 'SUBSCRIBE')
    ws.push({ result: null, id: ws.sent.find(x => x.method === 'UNSUBSCRIBE').id })
    ws.push({ error: { code: 2, msg: 'Invalid request' }, id: sub.id })
    vi.advanceTimersByTime(120_000)
    expect(FakeWS.all).toHaveLength(1)
    expect(m.S.wsState).not.toBe('closed')
  })

  it('只有回执、没有一帧行情：回执不算「上游在来帧」，8 秒首帧看门狗照样判断线重连', async () => {
    const m = await load('direct')
    m.setStreams(['aaausdt@ticker'], [], { now: true })
    const ws = FakeWS.all[0]
    m.setStreams(['bbbusdt@ticker'], [], { now: true })
    ws.open()
    for (const x of ws.sent) ws.push({ result: null, id: x.id })
    vi.advanceTimersByTime(8_100)
    expect(ws.readyState).toBe(3)
    vi.advanceTimersByTime(2_000)
    expect(FakeWS.all.length).toBeGreaterThan(1)
  })
})
