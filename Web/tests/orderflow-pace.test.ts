// 主力订单流 · 出帧节奏（src/orderflow/pace.ts，照 iOS OrderFlowFeed 的 skip / amountRefreshMs / heartbeatMs）
import { describe, expect, it } from 'vitest'
import { AMOUNT_REFRESH_MS, FramePacer, HEARTBEAT_MS, holdAmounts, sameExactContent, samePixels } from '../src/orderflow/pace'
import type { Snapshot } from '../src/orderflow/model'
import type { BigOrder } from '../src/orderflow/types'

const order = (over: Partial<BigOrder> = {}): BigOrder => ({
  venueID: 'binance:usdtPerp:ETHUSDT', exchange: '币安', product: 'usdtPerp', side: 'ask', bucket: 3, price: 2000,
  firstSeenMs: 1, endMs: null, status: 'live', initialNotional: 3_000_000, notional: 3_000_000, filledNotional: 0,
  threshold: 1_000_000, vanishedNotional: null, ...over,
})
const T = { spot: 1e6, usdtPerp: 1e6, coinPerp: undefined, delivery: undefined, step: 1 }
const snap = (orders: BigOrder[], asOfMs: number, phase: Snapshot['phase'] = 'ready'): Snapshot =>
  ({ phase, orders, asOfMs, thresholds: { ...T }, venues: [{ id: 'v', label: '币安', exchange: 'binance', product: 'usdtPerp', instrument: 'ETHUSDT', ready: true }] })

describe('订单流出帧节奏', () => {
  it('像素相同：金额变（连带厚度跨档）不算变，状态变、成交格变才算', () => {
    const a = order()
    expect(samePixels(a, order({ notional: 3_020_000 }))).toBe(true)
    expect(samePixels(a, order({ notional: 3_500_000 }))).toBe(true)
    expect(samePixels(a, order({ notional: 9_000_000 }))).toBe(true)
    expect(samePixels(a, order({ price: 2000.7 }))).toBe(true)     // 桶内均价随量抖，桶才是身份
    expect(samePixels(a, order({ status: 'cancelled', endMs: 5 }))).toBe(false)
    expect(samePixels(a, order({ filledNotional: 300_000 }))).toBe(false)
    // 成交格按上一帧的挂单量算底：挂单量翻倍、成交没动，格不算变；成交多了 15 万（一格）才算
    const half = order({ filledNotional: 1_500_000 })
    expect(samePixels(half, order({ notional: 6_000_000, filledNotional: 1_500_000 }))).toBe(true)
    expect(samePixels(half, order({ notional: 6_000_000, filledNotional: 1_650_000 }))).toBe(false)
  })

  it('按住金额：活着、画面没变的单金额照上一次交出去的（翻倍了也按住）；新单、成交格变了的单取新的', () => {
    const last = snap([order({ notional: 3_000_000 })], 1)
    const fresh = snap([order({ notional: 3_020_000 }), order({ bucket: 4, notional: 2_000_000 })], 2)
    const held = holdAmounts(fresh, last)
    expect(held.orders[0].notional).toBe(3_000_000)
    expect(held.orders[1].notional).toBe(2_000_000)
    expect(held.orders[0]).not.toBe(fresh.orders[0])   // 拷贝，不共享模型原地改的那份
    const grown = holdAmounts(snap([order({ notional: 6_500_000 })], 2), last)
    expect(grown.orders[0].notional).toBe(3_000_000)
    const moved = holdAmounts(snap([order({ notional: 3_020_000, price: 2000.7 })], 2), last)
    expect(moved.orders[0].price).toBe(2000)
    const filled = holdAmounts(snap([order({ notional: 2_600_000, filledNotional: 400_000 })], 2), last)
    expect(filled.orders[0].notional).toBe(2_600_000)
    expect(filled.orders[0].filledNotional).toBe(400_000)
  })

  it('画面没变、只是金额在抖：不发；每 5 秒换一次金额；十字线停着逐拍发；30 秒心跳', () => {
    const p = new FramePacer(() => false)
    const first = p.next(snap([order()], 0), 0)
    expect(first?.orders[0].notional).toBe(3_000_000)
    // 半秒后金额抖了 2 万：按住，不发
    expect(p.next(snap([order({ notional: 3_020_000 })], 500), 500)).toBeNull()
    expect(p.next(snap([order({ notional: 2_980_000 })], 1000), 1000)).toBeNull()
    // 到 5 秒：换成新金额发一帧
    const at5 = p.next(snap([order({ notional: 2_990_000 })], AMOUNT_REFRESH_MS), AMOUNT_REFRESH_MS)
    expect(at5?.orders[0].notional).toBe(2_990_000)
    // 之后完全没变：不发，直到 30 秒心跳
    expect(p.next(snap([order({ notional: 2_990_000 })], AMOUNT_REFRESH_MS + 500), AMOUNT_REFRESH_MS + 500)).toBeNull()
    const beat = p.next(snap([order({ notional: 2_990_000 })], AMOUNT_REFRESH_MS + HEARTBEAT_MS), AMOUNT_REFRESH_MS + HEARTBEAT_MS)
    expect(beat?.asOfMs).toBe(AMOUNT_REFRESH_MS + HEARTBEAT_MS)
    // 十字线停着：逐拍发精确金额
    let precise = true
    const q = new FramePacer(() => precise)
    q.next(snap([order()], 0), 0)
    expect(q.next(snap([order({ notional: 3_010_000 })], 500), 500)?.orders[0].notional).toBe(3_010_000)
    precise = false
    expect(q.next(snap([order({ notional: 3_015_000 })], 1000), 1000)).toBeNull()
  })

  it('画面变了（新单出现 / 单结束）立刻发，但其余活单的金额仍按住；reset 后下一拍取新金额', () => {
    const p = new FramePacer()
    p.next(snap([order()], 0), 0)
    const appeared = p.next(snap([order({ notional: 3_030_000 }), order({ bucket: 9, notional: 1_500_000 })], 500), 500)
    expect(appeared?.orders.map(o => o.notional)).toEqual([3_000_000, 1_500_000])
    const ended = p.next(snap([order({ notional: 3_040_000 }), order({ bucket: 9, notional: 1_500_000, status: 'filled', endMs: 900 })], 1000), 1000)
    expect(ended?.orders[1].status).toBe('filled')
    expect(ended?.orders[0].notional).toBe(3_000_000)
    p.reset()
    expect(p.next(snap([order({ notional: 3_050_000 }), order({ bucket: 9, notional: 1_500_000, status: 'filled', endMs: 900 })], 1500), 1500)?.orders[0].notional).toBe(3_050_000)
  })

  it('加载中 → 就绪、簿就绪位变了、门槛变了都算内容变', () => {
    const p = new FramePacer()
    expect(p.next(snap([], 0, 'loading'), 0)?.phase).toBe('loading')
    expect(p.next(snap([], 500, 'loading'), 500)).toBeNull()
    expect(p.next(snap([], 1000), 1000)?.phase).toBe('ready')
    const a = snap([], 0), b = snap([], 0)
    b.venues[0].ready = false
    expect(sameExactContent(a, b)).toBe(false)
    const c = snap([], 0); c.thresholds.usdtPerp = 2e6
    expect(sameExactContent(a, c)).toBe(false)
  })
})
