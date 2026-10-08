// PC 大单带按「墙」合并（src/orderflow/bands.ts 的 mergedWalls / bookRows / wallOf，底下是和手机同一套 OrderFlowGroup）：
// 同侧同类、相邻价位、时间上连着的几家几本并成一道；读数卡一本簿一行、按金额从大到小。
import { describe, expect, it } from 'vitest'
import { mergedWalls, bookRows, wallOf, wallId, wallPeak } from '../src/orderflow/bands'
import { OrderFlowGroup } from '../src/orderflow/group'
import { exName, PRODUCT_SHORT } from '../src/orderflow/aggregate'
import { orderId, type BigOrder } from '../src/orderflow/types'

const M = 60_000
const order = (over: Partial<BigOrder>): BigOrder => ({
  venueID: 'binance:usdtPerp:BTCUSDT', exchange: 'binance', product: 'usdtPerp', side: 'bid', bucket: 100, price: 100_000,
  firstSeenMs: 0, endMs: null, status: 'live', initialNotional: 1_000_000, notional: 1_000_000, filledNotional: 0,
  threshold: 500_000, vanishedNotional: null, ...over,
})
const opts = { gapMs: OrderFlowGroup.mergeGapMs(5 * M), minLifeMs: 5 * M, step: 1000 }
const rowName = (r: ReturnType<typeof bookRows>[number]): string => `${exName(r.book.exchange)} ${PRODUCT_SHORT[r.book.product]}`

describe('PC 大单带：多家合并成墙', () => {
  const orders = [
    order({ venueID: 'binance:usdtPerp:BTCUSDT', exchange: 'binance', bucket: 100, notional: 800_000, firstSeenMs: 0 }),
    order({ venueID: 'bybit:usdtPerp:BTCUSDT', exchange: 'bybit', bucket: 100, notional: 1_200_000, firstSeenMs: 2 * M }),
    order({ venueID: 'hyperliquid:usdtPerp:BTC', exchange: 'hyperliquid', bucket: 101, notional: 600_000, firstSeenMs: 3 * M }),
    order({ venueID: 'okx:usdtPerp:BTC-USDT-SWAP', exchange: 'okx', bucket: 101, notional: 300_000, firstSeenMs: 1 * M, status: 'cancelled', endMs: 20 * M }),
    // 另一侧、另一类：各自成墙
    order({ venueID: 'bybit:usdtPerp:BTCUSDT', exchange: 'bybit', side: 'ask', bucket: 110, notional: 2_000_000 }),
    order({ venueID: 'coinbase:spot:BTC-USD', exchange: 'coinbase', product: 'spot', bucket: 100, notional: 700_000 }),
  ]

  it('同侧同类相邻桶的四家并成一道；另一侧、现货各自一道', () => {
    const walls = mergedWalls(orders, () => true, 'all', opts)
    const bid = walls.find(w => w.side === 'bid' && w.contract)!
    expect(bid.members).toHaveLength(4)
    expect(bid.bucketLow).toBe(100)
    expect(bid.bucketHigh).toBe(101)
    expect(bid.isLive).toBe(true)
    expect(bid.firstSeenMs).toBe(0)
    expect(walls.filter(w => w.side === 'ask')).toHaveLength(1)
    expect(walls.filter(w => !w.contract)).toHaveLength(1)
  })

  it('读数卡一本簿一行，按金额从大到小：「Bybit 永续 1.2M」排第一', () => {
    const walls = mergedWalls(orders, () => true, 'all', opts)
    const bid = walls.find(w => w.side === 'bid' && w.contract)!
    const rows = bookRows(bid, o => Math.max(o.initialNotional, o.notional))
    // 挂着的按最新额；已结束的 OKX 按峰值（initialNotional 1M，比它撤前的 30 万大）
    expect(rows.map(rowName)).toEqual(['Bybit 永续', 'OKX 永续', '币安 永续', 'Hyperliquid 永续'])
    expect(rows.map(r => r.usd)).toEqual([1_200_000, 1_000_000, 800_000, 600_000])
    expect(wallPeak(rows)).toBe(1_200_000 + 800_000 + 600_000 + 1_000_000)
  })

  it('过滤口径变了重新算，同一份 orders 同口径走缓存', () => {
    const a = mergedWalls(orders, () => true, 'all', opts)
    expect(mergedWalls(orders, () => true, 'all', opts)).toBe(a)
    const spotOnly = mergedWalls(orders, o => o.product === 'spot', 'spot', opts)
    expect(spotOnly).toHaveLength(1)
    expect(spotOnly[0].books.map(b => b.exchange)).toEqual(['coinbase'])
  })

  it('高亮：认得出它所在的墙；被过滤掉的单自己成一道；墙 id 优先用高亮那一单', () => {
    const walls = mergedWalls(orders, o => o.product !== 'spot', 'contract', opts)
    const hy = orders[2]
    const w = wallOf(walls, orderId(hy), orders, opts.step)!
    expect(walls).toContain(w)
    expect(wallId(w, orderId(hy))).toBe(orderId(hy))
    expect(wallId(w, null)).toBe(orderId(w.books[0].latest))
    const cb = orders[5]
    const lone = wallOf(walls, orderId(cb), orders, opts.step)!
    expect(walls).not.toContain(lone)
    expect(lone.members).toEqual([cb])
    expect(wallOf(walls, null, orders, opts.step)).toBeNull()
  })

  it('时间上隔太久的不并', () => {
    const far = [
      order({ venueID: 'bybit:usdtPerp:BTCUSDT', exchange: 'bybit', firstSeenMs: 0, status: 'cancelled', endMs: 10 * M }),
      order({ venueID: 'binance:usdtPerp:BTCUSDT', exchange: 'binance', firstSeenMs: 10 * M + opts.gapMs + 1 }),
    ]
    expect(mergedWalls(far, () => true, 'far', opts)).toHaveLength(2)
  })
})
