// 深度审查 Web F 线 F9：系统时钟往回拨之后，缓存、节流、限流账本、失败退避不再停摆（往回拨多久停多久）。
// 现场复现见 scripts/f-perf.mjs idle 段最后一段（往回拨 2 小时后挂机 90 秒：修前 0 笔请求，修后照常轮询）。
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { CLOCK_SKEW_MS, ago, before } from '../src/util/clock'
import { Limiter, resetLimits, type LimitSnap } from '../src/market/limit'
import { Settle, SETTLE_MS } from '../src/market/settle'
import { fetchDetail } from '../src/market'

const H2 = 2 * 3600_000
const FAPI = 'https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT&limit=1500'

describe('ago / before', () => {
  it('正常流逝原样返回；几秒内的往回拨当刚刚；往回拨更多当早就过期', () => {
    expect(ago(1000, 4000)).toBe(3000)
    expect(ago(5000, 5000 - CLOCK_SKEW_MS + 1)).toBe(0)
    expect(ago(5000 + H2, 5000)).toBe(Infinity)
    expect(ago(0, 10)).toBe(10)
  })
  it('退避还没到点照旧等；剩下的比定好的最长时长还长（往回拨过）当作到点', () => {
    expect(before(10_000, 15_000, 0)).toBe(true)
    expect(before(10_000, 15_000, 10_000)).toBe(false)
    expect(before(H2 + 10_000, 15_000, 0)).toBe(false)
    expect(before(15_000 + CLOCK_SKEW_MS, 15_000, 0)).toBe(true)
  })
})

describe('限流账本：时钟往回拨两小时', () => {
  const mem = () => { let s: string | null = null; return { load: () => s && JSON.parse(s), save: (x: LimitSnap) => { s = JSON.stringify(x) }, raw: () => s } }
  it('一分钟内记满了预算，往回拨两小时后不等两小时：账上那几笔当作刚记的，一分钟后放行', () => {
    const T = 10_000_000
    const lim = new Limiter({ fapi: 100, dapi: 100, spot: 100 }, mem())
    for (let i = 0; i < 10; i++) expect(lim.take(FAPI, T + i * 10)).toBe(0) // 1500 根权重 10 × 10 = 100
    const back = T - H2
    const wait = lim.take(FAPI, back)
    expect(wait).toBeGreaterThan(0)
    expect(wait).toBeLessThanOrEqual(60_000) // 修前 ≈ 2 小时 + 60 秒
    expect(lim.take(FAPI, back + 60_000)).toBe(0)
  })
  it('冷却中往回拨：剩下的冷却跟着挪回来，不多关两小时', () => {
    const T = 10_000_000
    const lim = new Limiter(undefined, mem())
    lim.noteStatus(FAPI, 429, null, T)
    expect(lim.coolingFor(FAPI, T + 10_000)).toBe(50_000)
    const back = T + 10_000 - H2
    expect(lim.coolingFor(FAPI, back)).toBeLessThanOrEqual(60_000) // 修前 ≈ 2 小时
    expect(lim.coolingFor(FAPI, back + 60_000)).toBe(0)
  })
  it('几秒内的往回拨（NTP 微调）不动账', () => {
    const lim = new Limiter({ fapi: 10, dapi: 10, spot: 10 }, mem())
    expect(lim.take(FAPI, 1_000_000)).toBe(0)
    expect(lim.usedOf('fapi', 1_000_000 - 2000)).toBe(10)
    expect(lim.take(FAPI, 1_000_000 - 2000)).toBeGreaterThan(55_000)
  })
})

describe('品种停稳闸：时钟往回拨', () => {
  beforeEach(() => { vi.useFakeTimers(); vi.setSystemTime(10_000_000) })
  afterEach(() => { vi.useRealTimers() })
  it('换了品种后时钟往回拨两小时，登记的活照样在半秒内做、之后立刻做', () => {
    const s = new Settle(), f = vi.fn(), g = vi.fn()
    s.noteSwitch()
    vi.setSystemTime(10_000_000 - H2)
    s.whenSettled('a', f)
    vi.advanceTimersByTime(SETTLE_MS)
    expect(f).toHaveBeenCalledTimes(1)
    s.whenSettled('b', g)
    expect(g).toHaveBeenCalledTimes(1) // 修前要等两小时
  })
})

describe('详情五个慢数：一分钟内取过的判断', () => {
  let calls = 0
  beforeEach(() => {
    resetLimits(); calls = 0
    vi.useFakeTimers({ toFake: ['Date'] }); vi.setSystemTime(50_000_000)
    vi.stubGlobal('fetch', vi.fn(async () => { calls++; return new Response('[]', { status: 200 }) }))
  })
  afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); resetLimits() })
  it('往回拨两小时后照常重取（修前要等两小时）', async () => {
    await fetchDetail('F9AUSDT')
    const first = calls
    expect(first).toBeGreaterThan(0)
    await fetchDetail('F9AUSDT')
    expect(calls).toBe(first) // 一分钟内不重取
    vi.setSystemTime(50_000_000 - H2)
    await fetchDetail('F9AUSDT')
    expect(calls).toBe(first * 2)
  })
})

describe('推送连接的控制消息令牌桶：时钟往回拨两小时', () => {
  class FakeWS {
    static OPEN = 1; static CONNECTING = 0; static CLOSED = 3
    static all: FakeWS[] = []
    readyState = 0
    sent: any[] = []
    onopen: (() => void) | null = null
    onmessage: ((e: { data: string }) => void) | null = null
    onclose: (() => void) | null = null
    onerror: (() => void) | null = null
    constructor(public url: string) { FakeWS.all.push(this) }
    send(s: string) { this.sent.push(JSON.parse(s)) }
    close() { this.readyState = 3 }
    open() { this.readyState = 1; this.onopen?.() }
    push(o: unknown) { this.onmessage?.({ data: JSON.stringify(o) }) }
  }
  afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); vi.resetModules(); FakeWS.all = [] })

  it('往回拨后换品种：SUBSCRIBE 照常在一两秒内发出，不是等两小时攒回令牌', async () => {
    vi.useFakeTimers()
    vi.setSystemTime(10_000_000_000)
    vi.stubGlobal('WebSocket', FakeWS)
    vi.stubGlobal('location', { protocol: 'https:', host: 'k.example' })
    vi.resetModules()
    const s = await import('../src/market/stream')
    s.setRoute('gateway')
    s.setStreams(['btcusdt@ticker'], [], { now: true })
    const ws = FakeWS.all[0]
    ws.open()
    ws.push({ stream: 'btcusdt@kline_1m', data: { e: 'kline', s: 'BTCUSDT', k: { t: 0, o: '1', h: '1', l: '1', c: '1', q: '1', Q: '1', v: '1', i: '1m' } } })
    vi.setSystemTime(10_000_000_000 - H2)
    s.setStreams(['ethusdt@ticker'], [], { now: true })
    vi.advanceTimersByTime(2_000)
    expect(ws.sent.some(x => x.method === 'SUBSCRIBE' && x.params.includes('ethusdt@ticker'))).toBe(true)
    expect(s.streamDebug().subscribed).toEqual(['ethusdt@ticker'])
  })
})
