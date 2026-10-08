import { describe, expect, it } from 'vitest'
import { bucketIndex, intervalMultiplier, mergeFactor } from '../src/orderflow/bucket'
import { buildFine, emptyFine, ladderRows, steppedBook, outcomeText, rowOf, type FineBook } from '../src/orderflow/aggregate'
import { OrderFlowModel } from '../src/orderflow/model'
import { HeatStore, HeatCache, parseHeat, percentile, buildGrid, heatEdges, aggregateColumn, heatHint, heatRing, heatUrl } from '../src/orderflow/heat'
import { parseHistory } from '../src/orderflow/model'
import { historyQuery, coveredFrom, HISTORY_PAGE } from '../src/orderflow/feed'
import { Tape, tapeBase } from '../src/orderflow/tape'
import { parseAmount, normalizeOverride, applyOverride } from '../src/orderflow/settings'
import type { BigOrder, BookLevel, Venue } from '../src/orderflow/types'
import { encodeSettings, applySettings, SETTINGS_ID, type SettingsState } from '../src/sync/codec'
import type { Json, SyncObject } from '../src/sync/types'
import type { SubId } from '../src/chart/calc'

// ------------------------------------------------------------------ 工具

const OKX_PERP: Venue = {
  exchange: 'okx', label: 'OKX', product: 'usdtPerp', instrument: 'BTC-USDT-SWAP',
  notional: { kind: 'linear', multiplier: 1 }, sequenceModel: 'previousFinalExact', snapshotInBand: true,
}
const CB_SPOT: Venue = {
  exchange: 'coinbase', label: 'Coinbase', product: 'spot', instrument: 'BTC-USD',
  notional: { kind: 'linear', multiplier: 1 }, sequenceModel: 'strictIncrementing', snapshotInBand: true,
}

let seq = 1
function snap(model: OrderFlowModel, id: string, bids: [number, number][], asks: [number, number][], now: number): void {
  const lv = (a: [number, number][]): BookLevel[] => a.map(([price, quantity]) => ({ price, quantity }))
  model.ingest(id, { type: 'snapshot', snapshot: { lastUpdateID: seq++, requestedLevels: 400, bids: lv(bids), asks: lv(asks), connection: 0, slidingWindow: false } }, now)
}

function fine(step: number, bids: [number, number][], asks: [number, number][], mid: number): FineBook {
  const f = emptyFine(step, [{ id: 'a', exchange: 'binance', label: '币安', product: 'usdtPerp', instrument: 'X' }, { id: 'b', exchange: 'okx', label: 'OKX', product: 'spot', instrument: 'Y' }])
  const put = (m: FineBook['bid'], idx: number, v: number): void => {
    const c = m.get(idx) ?? { total: 0, byVenue: new Float64Array(2) }
    c.total += v; c.byVenue[idx % 2] += v; m.set(idx, c)
  }
  for (const [i, v] of bids) put(f.bid, i, v)
  for (const [i, v] of asks) put(f.ask, i, v)
  f.mid = mid; f.bestBid = mid - step; f.bestAsk = mid
  return f
}

// ------------------------------------------------------------------ 分桶与合并倍数

describe('分桶', () => {
  it('价位落桶取下沿，离整数极近的先吸到整数', () => {
    expect(bucketIndex(64_123, 100)).toBe(641)
    expect(bucketIndex(64_100, 100)).toBe(641)
    expect(bucketIndex(0.3, 0.1)).toBe(3)
    expect(bucketIndex(0.29999999999, 0.1)).toBe(3)
    expect(bucketIndex(-1, 1)).toBe(-1)
  })
  it('周期倍数照设计稿', () => {
    expect(intervalMultiplier('1m')).toBe(1)
    expect(intervalMultiplier('1h')).toBe(15)
    expect(intervalMultiplier('1d')).toBe(50)
    expect(intervalMultiplier('1s')).toBe(1)
  })
  it('行高不到 6 px 按 2 / 5 / 10 倍合并', () => {
    expect(mergeFactor(8)).toBe(1)
    expect(mergeFactor(6)).toBe(1)
    expect(mergeFactor(4)).toBe(2)
    expect(mergeFactor(2)).toBe(5)
    expect(mergeFactor(1)).toBe(10)
    expect(mergeFactor(0.5)).toBe(20)
    expect(mergeFactor(0.1)).toBe(100)
    expect(mergeFactor(0.02)).toBe(500)
    expect(mergeFactor(0)).toBe(1)
    expect(mergeFactor(NaN)).toBe(1)
  })
})

// ------------------------------------------------------------------ 聚合

describe('梯子聚合', () => {
  it('k 个细桶并一行，按簿拆分，累计从盘口往外累且连续', () => {
    // 细桶步长 10，中间价 1000；买在 99x 以下，卖在 100x 以上
    const f = fine(10, [[99, 100], [98, 50], [97, 30], [90, 7]], [[100, 40], [101, 60], [104, 5]], 1000)
    const rows = ladderRows(f, 2, 45, 51, [])
    // 行 49 = 桶 98、99
    const r49 = rows.get(49)!
    expect(r49.low).toBe(980); expect(r49.high).toBe(1000)
    expect(r49.bid).toBe(150)
    expect(r49.bidBy[1]).toBe(100); expect(r49.bidBy[0]).toBe(50)
    expect(r49.cumBid).toBe(150)
    expect(rows.get(48)!.cumBid).toBe(180)
    // 行 46、47 没有挂单，累计仍要带上
    expect(rows.get(47)!.bid).toBe(0)
    expect(rows.get(47)!.cumBid).toBe(180)
    expect(rows.get(45)!.cumBid).toBe(187)
    expect(rows.get(50)!.ask).toBe(100)
    expect(rows.get(51)!.cumAsk).toBe(100)
    // 范围外（桶 104 → 行 52）不在结果里，但范围内的累计不受影响
    expect(rows.has(52)).toBe(false)
  })
  it('范围外的挂单也计进累计', () => {
    const f = fine(10, [[99, 10], [80, 1000]], [[100, 5], [130, 500]], 1000)
    const rows = ladderRows(f, 1, 95, 100, [])
    expect(rows.get(99)!.cumBid).toBe(10)
    const f2 = fine(10, [[99, 10], [80, 1000]], [[100, 5], [130, 500]], 1000)
    // 只看 [85, 90]：买的累计 = 99 那档
    const r2 = ladderRows(f2, 1, 85, 90, [])
    expect(r2.get(90)!.cumBid).toBe(10)
  })
  it('还挂着的大单落在对应的行，按金额排', () => {
    const f = fine(10, [[99, 100]], [[100, 40]], 1000)
    const o = (bucket: number, notional: number, status: BigOrder['status'] = 'live'): BigOrder => ({
      venueID: 'v', exchange: '币安', product: 'usdtPerp', side: 'bid', bucket, price: bucket * 10, firstSeenMs: 1, endMs: null,
      status, initialNotional: notional, notional, filledNotional: 0, threshold: 1, vanishedNotional: null,
    })
    const rows = ladderRows(f, 5, 18, 20, [o(99, 1), o(96, 3), o(95, 2), o(94, 9), o(97, 50, 'cancelled')])
    expect(rows.get(19)!.orders.map(x => x.notional)).toEqual([3, 2, 1])
    expect(rows.get(18)!.orders.map(x => x.notional)).toEqual([9])
    expect(rowOf(-1, 5)).toBe(-1)
  })
  it('分档盘口从最优价往外各 n 档，不算交割', () => {
    const f = fine(10, [[99, 100], [98, 50]], [[100, 40], [101, 60]], 1000)
    f.venues[1].product = 'delivery'
    const b = steppedBook(f, 1, 3)
    // 桶 99 的 100 记在第 1 本（交割），不算
    expect(b.bids.map(r => r.usd)).toEqual([0, 50, 0])
    expect(b.bids[1].cum).toBe(50)
    expect(b.asks.map(r => r.usd)).toEqual([40, 0, 0])
  })
})

// ------------------------------------------------------------------ 出现 / 消失 / 结局

describe('大单判定（照手机端模型）', () => {
  const bids = (big: number): [number, number][] => [[99, 1], [95, big], [90, 1]]
  const asks: [number, number][] = [[101, 1], [110, 1]]

  function setup(): { m: OrderFlowModel; id: string } {
    const m = new OrderFlowModel('BTCUSDT', { usdtPerp: 1_000_000, step: 1 })
    const id = m.addVenue(OKX_PERP)
    m.connectionOpened(id)
    return { m, id }
  }

  it('过门槛要连续两次、间隔 ≥ 300 ms 才算出现', () => {
    const { m, id } = setup()
    snap(m, id, bids(20_000), asks, 0)
    expect(m.evaluate(0).orders).toHaveLength(0)
    expect(m.evaluate(200).orders).toHaveLength(0)
    const s = m.evaluate(400)
    expect(s.orders).toHaveLength(1)
    const o = s.orders[0]
    expect(o.status).toBe('live')
    expect(o.side).toBe('bid')
    expect(o.bucket).toBe(95)
    expect(o.firstSeenMs).toBe(0)
    expect(o.notional).toBe(95 * 20_000)
  })

  it('不到门槛不出现', () => {
    const { m, id } = setup()
    snap(m, id, bids(5_000), asks, 0)
    m.evaluate(0); m.evaluate(500)
    expect(m.evaluate(1000).orders).toHaveLength(0)
  })

  it('没有成交就消失 → 已撤销，结束时刻取第一次看不见的那一刻', () => {
    const { m, id } = setup()
    snap(m, id, bids(20_000), asks, 0)
    m.evaluate(0); m.evaluate(400)
    snap(m, id, [[99, 1], [90, 1]], asks, 1000)
    expect(m.evaluate(1000).orders[0].status).toBe('live')
    const o = m.evaluate(1400).orders[0]
    expect(o.status).toBe('cancelled')
    expect(o.endMs).toBe(1000)
    expect(o.filledNotional).toBe(0)
    expect(outcomeText(o)).toBe('已撤销')
  })

  it('消失前被主动卖吃掉 → 已成交', () => {
    const { m, id } = setup()
    snap(m, id, bids(20_000), asks, 0)
    m.evaluate(0); m.evaluate(400)
    m.ingest(id, { type: 'trade', trade: { price: 95, quantity: 20_000, hitSide: 'bid', timeMs: 900 } }, 900)
    snap(m, id, [[99, 1], [90, 1]], asks, 1000)
    m.evaluate(1000)
    const o = m.evaluate(1400).orders[0]
    expect(o.status).toBe('filled')
    expect(o.filledNotional).toBeCloseTo(95 * 20_000)
    expect(outcomeText(o)).toBe('已成交')
  })

  it('吃掉一部分再撤 → 部分成交后撤', () => {
    const { m, id } = setup()
    snap(m, id, bids(20_000), asks, 0)
    m.evaluate(0); m.evaluate(400)
    m.ingest(id, { type: 'trade', trade: { price: 95, quantity: 4_000, hitSide: 'bid', timeMs: 900 } }, 900)
    snap(m, id, [[99, 1], [90, 1]], asks, 1000)
    m.evaluate(1000)
    const o = m.evaluate(1400).orders[0]
    expect(o.status).toBe('cancelled')
    expect(o.filledNotional).toBeCloseTo(95 * 4_000)
    expect(outcomeText(o)).toBe('部分成交后撤')
  })

  it('降到门槛一半以上仍算挂着，金额跟着变', () => {
    const { m, id } = setup()
    snap(m, id, bids(20_000), asks, 0)
    m.evaluate(0); m.evaluate(400)
    snap(m, id, bids(12_000), asks, 800)
    const o = m.evaluate(800).orders[0]
    expect(o.status).toBe('live')
    expect(o.notional).toBe(95 * 12_000)
    expect(o.initialNotional).toBe(95 * 20_000)
  })

  it('门槛调高：初始金额不够的大单被剔除（改门槛即重算）', () => {
    const { m, id } = setup()
    snap(m, id, bids(20_000), asks, 0)
    m.evaluate(0); m.evaluate(400)
    m.setThresholds({ usdtPerp: 5_000_000, step: 1 })
    expect(m.evaluate(600).orders).toHaveLength(0)
    m.setThresholds({ usdtPerp: 1_000_000, step: 5 })
    // 步长变了：整体重来
    expect(m.scheme?.step).toBe(5)
  })

  it('聚合细桶：多本簿按同一步长加总并按簿拆分，参考中间价取中位数', () => {
    const m = new OrderFlowModel('BTCUSDT', { usdtPerp: 1_000_000, spot: 500_000, step: 10 })
    const a = m.addVenue(OKX_PERP), b = m.addVenue(CB_SPOT)
    m.connectionOpened(a); m.connectionOpened(b)
    snap(m, a, [[995, 100], [991, 100]], [[1005, 10]], 0)
    snap(m, b, [[996, 50]], [[1004, 20]], 0)
    const f = buildFine(m, 500, 0)!
    expect(f.ready).toBe(2)
    expect(f.venues.map(v => v.exchange)).toEqual(['okx', 'coinbase'])
    const c = f.bid.get(99)!
    expect(c.total).toBeCloseTo(995 * 100 + 991 * 100 + 996 * 50)
    expect(c.byVenue[1]).toBeCloseTo(996 * 50)
    expect(f.ask.get(100)!.total).toBeCloseTo(1005 * 10 + 1004 * 20)
    expect(f.mid).toBe(1000)
  })
})

// ------------------------------------------------------------------ 热力

describe('热力', () => {
  it('p95 线性插值，空数组给 0，大样本抽样', () => {
    expect(percentile([], 0.95)).toBe(0)
    expect(percentile([5], 0.95)).toBe(5)
    const a = Array.from({ length: 101 }, (_, i) => i)
    expect(percentile(a, 0.95)).toBeCloseTo(95)
    expect(percentile(a, 0.5)).toBeCloseTo(50)
    const big = new Float32Array(100_000).map((_, i) => i)
    expect(percentile(big, 0.95, 1000)).toBeGreaterThan(93_000)
    expect(percentile(big, 0.95, 1000)).toBeLessThan(97_000)
  })

  it('回填：列宽照服务端 bucketMs，价格乘 chartScale，同一时刻多行并成一列', () => {
    const cols = parseHeat({ step: 100, bucketMs: 30_000, rows: [[60_000, 64_000, 1e6, 0], [60_000, 64_100, 0, 2e6], [90_000, 64_000, 5e5, 5e5]] }, 100, 1)!
    expect(cols).toHaveLength(2)
    expect(cols[0].dur).toBe(30_000)
    expect(cols[0].lo).toBe(640); expect(cols[0].n).toBe(2)
    expect(cols[0].data[0]).toBe(1e6); expect(cols[0].data[5]).toBe(2e6)
    expect(cols[0].split).toBe(false)
    expect(cols[1].data[0]).toBe(1e6)
    // 1000PEPE：服务端按每个币，图上一格 = 1000 个
    const pepe = parseHeat({ step: 0.000001, bucketMs: 5000, rows: [[0, 0.000012, 1, 0]] }, 0.001, 1000)!
    expect(pepe[0].lo).toBe(12)
  })

  it('没跟踪的品种给空行 → 空列表；接口坏了给 null', () => {
    expect(parseHeat({ step: 1, bucketMs: 5000, rows: [] }, 1, 1)).toEqual([])
    expect(parseHeat('oops', 1, 1)).toBeNull()
    expect(parseHeat({ nope: 1 }, 1, 1)).toBeNull()
  })

  it('服务端步长比图上细桶粗：一格的量均摊到它覆盖的细桶', () => {
    const cols = parseHeat({ step: 100, bucketMs: 5000, rows: [[0, 64_000, 1000, 0]] }, 10, 1)!
    expect(cols[0].lo).toBe(6400)
    expect(cols[0].n).toBe(10)
    for (let i = 0; i < 10; i++) expect(cols[0].data[i * 5]).toBeCloseTo(100)
  })

  it('放粗的回填列能被跨进窗口的查询找到；clearBack 清掉', () => {
    const s = new HeatStore(100)
    s.addBackfill(parseHeat({ step: 100, bucketMs: 3_600_000, rows: [[0, 64_000, 1, 0]] }, 100, 1)!)
    const seen: number[] = []
    s.forEach(1_800_000, 1_900_000, c => seen.push(c.t))
    expect(seen).toEqual([0])
    expect(s.backRange).toEqual([0, 3_600_000])
    const v = s.backVersion
    s.clearBack()
    expect(s.back).toHaveLength(0)
    expect(s.backVersion).toBe(v + 1)
  })

  it('实时每秒一列、五家分通道，不到门槛 5% 的桶不计；实时开始之后不再用回填', () => {
    const s = new HeatStore(10)
    const f = emptyFine(10, [
      { id: 'a', exchange: 'binance', label: '币安', product: 'usdtPerp', instrument: 'X' },
      { id: 'b', exchange: 'okx', label: 'OKX', product: 'usdtPerp', instrument: 'Y' },
      { id: 'c', exchange: 'coinbase', label: 'Coinbase', product: 'spot', instrument: 'Z' },
      { id: 'd', exchange: 'bybit', label: 'Bybit', product: 'usdtPerp', instrument: 'X' },
      { id: 'e', exchange: 'hyperliquid', label: 'Hyperliquid', product: 'usdtPerp', instrument: 'B' },
    ])
    f.mid = 1000
    f.bid.set(99, { total: 0, byVenue: new Float64Array([100_000, 60_000, 10, 70_000, 0]) })
    f.ask.set(100, { total: 0, byVenue: new Float64Array([0, 0, 80_000, 0, 90_000]) })
    const th = { usdtPerp: 1_000_000, spot: 1_000_000 }
    expect(s.sample(f, th, 5_400)).toBe(true)
    expect(s.sample(f, th, 5_900)).toBe(true) // 同一秒：替换
    expect(s.sample(f, th, 6_100)).toBe(true)
    expect(s.live).toHaveLength(2)
    const col = s.live[0]
    expect(col.t).toBe(5_000)
    expect(col.split).toBe(true)
    const i99 = (99 - col.lo) * 5
    expect(col.data[i99]).toBe(100_000)
    expect(col.data[i99 + 1]).toBe(60_000)
    expect(col.data[i99 + 2]).toBe(0) // 10 美元 < 5 万，不计
    expect(col.data[i99 + 3]).toBe(70_000) // Bybit
    expect(col.data[(100 - col.lo) * 5 + 2]).toBe(80_000)
    expect(col.data[(100 - col.lo) * 5 + 4]).toBe(90_000) // Hyperliquid

    s.addBackfill([{ t: 0, dur: 5000, lo: 99, n: 1, data: new Float32Array([7, 0, 0, 0, 0]), split: false }, { t: 5000, dur: 5000, lo: 99, n: 1, data: new Float32Array([9, 0, 0, 0, 0]), split: false }])
    const ts: number[] = []
    s.forEach(0, 10_000, c => ts.push(c.t))
    expect(ts).toEqual([0, 5000, 6000])
  })

  it('画面网格：每格取样本平均，亮度基准是可见格子的 p95，1 分钟图按秒成列', () => {
    const s = new HeatStore(1)
    const mk = (t: number, v: number): { t: number; dur: number; lo: number; n: number; data: Float32Array; split: boolean } =>
      ({ t, dur: 1000, lo: 10, n: 2, data: new Float32Array([v, 0, 0, 0, 0, 0, v, 0, 0, 0]), split: true })
    s.live = [mk(0, 10), mk(1000, 30), mk(2000, 100)]
    const g = buildGrid(s, [0, 2000, 3000], 10, 11, 1, 5000)!
    expect(g.cols).toBe(2); expect(g.rows).toBe(2)
    expect(g.values[0]).toBe(20) // (10 + 30) / 2
    expect(g.values[2]).toBe(100)
    expect(g.parts[5 * 1 + 1]).toBe(20) // 第 0 列第 1 行在 OKX 通道（五家，stride 5）
    expect(g.p95).toBeGreaterThan(20)
    expect(g.splitKnown[0]).toBe(1)
    // k = 2：两个细桶并一行
    const c = aggregateColumn(s, 0, 1000, 2, 5000)
    expect(c.n).toBe(1); expect(c.vals[0]).toBe(20)
    // 列边界
    expect(heatEdges(3_600_000, 0, 7_200_000, 1e-4)).toEqual([0, 3_600_000, 7_200_000, 10_800_000])
    const e = heatEdges(60_000, 0, 10_000, 0.004) // 每秒 4 px
    expect(e[1] - e[0]).toBe(1000)
    const e2 = heatEdges(60_000, 0, 60_000, 0.0005) // 每秒 0.5 px → 至少 2 px 一列 → 5 秒
    expect(e2[1] - e2[0]).toBe(5000)
  })

  it('列缓存：定稿列复用，回填到了重算', () => {
    const s = new HeatStore(1)
    s.live = [{ t: 0, dur: 1000, lo: 1, n: 1, data: new Float32Array([5, 0, 0]), split: true }]
    const cache = new HeatCache()
    cache.reset('k')
    const a = cache.column(s, 0, 1000, 1, 10_000)
    expect(cache.column(s, 0, 1000, 1, 11_000)).toBe(a)
    s.addBackfill([{ t: -5000, dur: 5000, lo: 1, n: 1, data: new Float32Array([1, 0, 0]), split: false }])
    expect(cache.column(s, 0, 1000, 1, 12_000)).not.toBe(a)
  })
})

// ------------------------------------------------------------------ 成交带、设置

describe('成交带', () => {
  const base = { exchange: 'binance', label: '币安', product: 'usdtPerp' as const, side: 'buy' as const, price: 100, qty: 1 }
  it('同家同向同价 1 秒以内并成一行，超过另开', () => {
    const t = new Tape()
    t.push({ ...base, t: 0, usd: 100 })
    t.push({ ...base, t: 800, usd: 200 })
    t.push({ ...base, t: 1700, usd: 300 })
    t.push({ ...base, t: 3000, usd: 1 })
    t.push({ ...base, side: 'sell', t: 3100, usd: 5 })
    expect(t.rows.map(r => r.usd)).toEqual([600, 1, 5])
    expect(t.rows[0].n).toBe(3)
    expect(t.visible(5, 10).map(r => r.usd)).toEqual([5, 600])
  })
  it('成交带不再给图上打点（2026-10-08 起图上是每根一枚大单签，见 orderflow-bigtags.test.ts）', () => {
    const t = new Tape() as unknown as Record<string, unknown>
    expect(t.dots).toBeUndefined()
    expect(t.dotFor).toBeUndefined()
  })
  it('每秒 50 笔以上一小时也有上限', () => {
    const t = new Tape()
    for (let i = 0; i < 10_000; i++) t.push({ ...base, price: 100 + (i % 97), t: i * 20, usd: 10 })
    expect(t.rows.length).toBeLessThanOrEqual(3600)
  })
  it('门槛基准：U 本位永续，没有就现货', () => {
    expect(tapeBase({ usdtPerp: 5e6, spot: 1e6 })).toBe(5e6)
    expect(tapeBase({ spot: 1e6 })).toBe(1e6)
    expect(tapeBase({ coinPerp: 2e6, delivery: 3e6 })).toBe(2e6)
    expect(tapeBase({})).toBeNull()
  })
})

describe('门槛输入', () => {
  it('金额可以写 K / M / B、逗号', () => {
    expect(parseAmount('500K')).toBe(500_000)
    expect(parseAmount('2.5m')).toBe(2_500_000)
    expect(parseAmount('1,000,000')).toBe(1_000_000)
    expect(parseAmount('$3B')).toBe(3e9)
    expect(parseAmount('')).toBeNull()
    expect(parseAmount('abc')).toBeNull()
    expect(parseAmount('0')).toBeNull()
  })
  it('越界项丢掉，改过的项盖在默认上', () => {
    expect(normalizeOverride({ usdtPerp: 10, spot: 2e6, step: 0 })).toEqual({ spot: 2e6 })
    expect(normalizeOverride({ usdtPerp: 10 })).toBeNull()
    expect(applyOverride({ spot: 1e6, usdtPerp: 5e6, step: 100 }, { usdtPerp: 3e6, step: 50 })).toEqual({ spot: 1e6, usdtPerp: 3e6, step: 50 })
  })
})

describe('门槛随账号同步（settings.orderFlowOverrides）', () => {
  const ind = { ma: true, ema: false, boll: false, vol: true, subs: ['macd'] as SubId[] }
  it('网页改了推上去，形状和手机一样；不合法的项不上云', () => {
    const seen: Record<string, Json> = {}
    const s: SettingsState = { pinned: ['1h'], ind, params: null, orderFlowOverrides: { BTC: { usdtPerp: 1e7, step: 50 }, 'bad-base': { spot: 2e6 } } }
    const o = encodeSettings(s, undefined, seen)!
    expect(o.body.orderFlowOverrides).toEqual({ BTC: { usdtPerp: 1e7, step: 50 } })
    expect(encodeSettings(s, o, seen)).toBeNull()
  })
  it('手机改了装下来，越界项丢掉', () => {
    const seen: Record<string, Json> = {}
    const s: SettingsState = { pinned: ['1h'], ind, params: null, orderFlowOverrides: {} }
    const cloud = { collection: 'settings', id: SETTINGS_ID, body: { orderFlowOverrides: { ETH: { spot: 5e5, usdtPerp: 1 } } }, fields: {}, revision: 1, deleted: false, generation: 0 } as unknown as SyncObject
    expect(applySettings(s, cloud, seen)).toContain('orderFlowOverrides')
    expect(s.orderFlowOverrides).toEqual({ ETH: { spot: 5e5 } })
  })
})

describe('订单流 · 收窄的服务端请求（2026-09-29）', () => {
  it('热力的时间格提示取阶梯上不粗过 2 像素的最粗一档', () => {
    expect(heatHint(100)).toBe(5000)
    expect(heatHint(2500)).toBe(5000)
    expect(heatHint(5000)).toBe(10_000)
    expect(heatHint(20_000)).toBe(30_000)
    expect(heatHint(40_000)).toBe(60_000)
    expect(heatHint(80_000)).toBe(150_000)
    expect(heatHint(1e7)).toBe(3_600_000)
  })
  it('价格环以可见中点为心，至少 ±5%、盖住可见高度 1.25 倍、至多 ±50%', () => {
    const r = heatRing(99_000, 101_000)!
    expect(r.around).toBe(100_000)
    expect(r.pct).toBe(5)
    expect(r.lo).toBeCloseTo(95_000)
    expect(r.hi).toBeCloseTo(105_000)
    expect(heatRing(80_000, 120_000)!.pct).toBe(25)
    expect(heatRing(10, 1000)!.pct).toBe(50)
    expect(heatRing(0, 0)).toBeNull()
    expect(heatRing(5, 4)).toBeNull()
  })
  it('热力 URL：时间对齐 5 秒、价格换回「每个币」、带提示与环', () => {
    const url = heatUrl('PEPE', 1_000_001, 1_010_001, 0.001, 1000, 30_000, heatRing(0.0099, 0.0101))
    const q = new URLSearchParams(url.split('?')[1])
    expect(url.startsWith('/v1/market/orderflow/heat?')).toBe(true)
    expect(q.get('base')).toBe('PEPE')
    expect(q.get('from')).toBe('1000000')
    expect(q.get('to')).toBe('1015000')
    expect(q.get('step')).toBe('0.000001')
    expect(q.get('bucketMs')).toBe('30000')
    expect(Number(q.get('around'))).toBeCloseTo(0.00001, 12)
    expect(q.get('pct')).toBe('5')
    expect(new URLSearchParams(heatUrl('BTC', 0, 5000, 100, 1, 5000, null).split('?')[1]).has('around')).toBe(false)
  })
  it('历史请求带 limit，nextBefore 决定这一页覆盖到哪儿', () => {
    const q = new URLSearchParams(historyQuery('BTC', 1000.7, 2000.2).split('?')[1])
    expect([q.get('from'), q.get('to'), q.get('limit')]).toEqual(['1000', '2000', String(HISTORY_PAGE)])
    expect(HISTORY_PAGE).toBe(5000)
    const page = parseHistory({ base: 'BTC', thresholds: { step: 1 }, orders: [], nextBefore: 1500 }, 1000, 2000)!
    expect(page.nextBefore).toBe(1500)
    expect(coveredFrom(page)).toBe(1500)
    const old = parseHistory({ base: 'BTC', thresholds: {}, orders: [] }, 1000, 2000)!
    expect(old.nextBefore).toBeNull()
    expect(coveredFrom(old)).toBe(1000)
    expect(coveredFrom(parseHistory({ base: 'BTC', orders: [], nextBefore: null }, 1000, 2000)!)).toBe(1000)
  })
})
