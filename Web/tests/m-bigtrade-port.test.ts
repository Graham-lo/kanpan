// 手机网页版 · 大单签的数据接线：共用的 flowTap（门槛 ÷ 50 记大单、覆盖心跳）与行情页数据口的「签」这个理由
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { bigCut, tierFloor, recordFeedTrade, feedBeat } from '../src/orderflow/flowTap'
import { flowOf, resetFlows } from '../src/chart/tradeFlow'
import type { TradeEvent } from '../src/orderflow/feed'

const fake = vi.hoisted(() => ({ inst: [] as { push: (s: unknown) => void; started: string[]; stopped: number; parked: number; current: string | null }[] }))
vi.mock('../src/m/chart/orderflow.source', () => ({
  OrderFlowSource: class {
    started: string[] = []; stopped = 0; parked = 0; current: string | null = null
    lastTradeMs = 0; step = 0.1
    constructor(public push: (s: unknown) => void) { fake.inst.push(this as never) }
    start(sym: string) { this.started.push(sym); this.current = sym }
    stop() { this.stopped++; this.current = null; this.push(null) }
    park() { this.parked++; this.current = null; this.push(null) }
    setRoute() {}
    setOverride() {}
    setVisible() {}
  },
}))
import { createPagePort } from '../src/m/pages/chart/data'

const ev = (usd: number, buy: boolean, t: number): TradeEvent => ({
  usd,
  trade: { price: 100, quantity: usd / 100, hitSide: buy ? 'ask' : 'bid', timeMs: t },
  book: { venue: { exchange: 'binance', product: 'usdtPerp', instrument: 'BTCUSDT' } },
} as unknown as TradeEvent)

describe('flowTap（电脑与手机共用）', () => {
  beforeEach(() => resetFlows())
  it('大单线 = 门槛 ÷ 50，档位地板 = 门槛 ÷ 5，取 U 本位永续那个门槛', () => {
    expect(bigCut({ usdtPerp: 2_500_000, spot: 750_000 })).toBe(50_000)
    expect(bigCut({ spot: 750_000 })).toBe(15_000)
    expect(bigCut(null)).toBeNull()
    expect(tierFloor({ usdtPerp: 2_500_000 })).toBe(500_000)
    expect(tierFloor(undefined)).toBe(0)
  })
  it('过线的那笔记进分钟桶的大单，没过的只记成交', () => {
    const t = Date.UTC(2026, 9, 8, 4, 30, 5)
    recordFeedTrade('BTCUSDT', ev(60_000, true, t), { usdtPerp: 2_500_000 })
    recordFeedTrade('BTCUSDT', ev(40_000, false, t), { usdtPerp: 2_500_000 })
    const c = flowOf('BTCUSDT').min.get(Math.floor(t / 60_000) * 60_000)!
    expect(c.bb).toBe(60_000)
    expect(c.bs).toBe(0)
    expect(c.cs).toBe(40_000)
  })
  it('覆盖心跳：连接都开着才接上', () => {
    feedBeat({ symbol: 'ETHUSDT', debug: () => ({ conns: [{ open: true }, { open: false }] }) }, 1000)
    expect(flowOf('ETHUSDT').cover).toEqual([])
    feedBeat({ symbol: 'ETHUSDT', debug: () => ({ conns: [{ open: true }] }) }, 2000)
    expect(flowOf('ETHUSDT').cover).toEqual([[2000, 2000]])
  })
})

describe('行情页数据口：挂单墙与大单签两个理由', () => {
  beforeEach(() => { fake.inst.length = 0 })
  it('只开签：照订，但快照不交给图', () => {
    const push = vi.fn()
    const port = createPagePort(push, () => null)
    const src = fake.inst[0]
    port.setSigns(true, 'btcusdt')
    expect(src.started).toEqual(['BTCUSDT'])
    src.push({ thresholds: { usdtPerp: 1 }, orders: [] })
    expect(push).not.toHaveBeenCalled()
    expect(port.snapshot).not.toBeNull()
    port.dispose()
  })
  it('签开着时再开墙：不重订，手上的那帧马上交给图；关墙：图上清掉、照订', () => {
    const push = vi.fn()
    const port = createPagePort(push, () => null)
    const src = fake.inst[0]
    port.setSigns(true, 'BTCUSDT')
    const snap = { thresholds: {}, orders: [] }
    src.push(snap)
    port.setWanted(true, 'BTCUSDT', '1h' as never)
    expect(src.started).toEqual(['BTCUSDT'])
    expect(push).toHaveBeenLastCalledWith(snap)
    port.setWanted(false, 'BTCUSDT', '1h' as never)
    expect(push).toHaveBeenLastCalledWith(null)
    expect(src.stopped).toBe(0)
    port.setSigns(false, 'BTCUSDT')
    expect(src.stopped).toBe(1)
    port.dispose()
  })
  it('两个都关：停掉', () => {
    const port = createPagePort(vi.fn(), () => null)
    const src = fake.inst[0]
    port.setWanted(true, 'SOLUSDT', '1h' as never)
    port.setWanted(false, 'SOLUSDT', '1h' as never)
    expect(src.stopped).toBe(1)
    port.dispose()
  })
})
