/* 订单流吸收（2026-09-29）：梯子成交列、变化模式、24 小时流动性 / 成交、成交流 bps 与行高 */
import { describe, expect, it } from 'vitest'
import { TradeLadder, deltaPct, fromMidPct, signedPct } from '../src/orderflow/tradeLadder'
import { parseHeatSplit, colSum, colRows, scopedHeatUrl, type SplitCol } from '../src/orderflow/heatFetch'
import { snapFine, deltaRows, firstFrom, niceCeil, rowSeries, sparkSVG } from '../src/orderflow/depthDelta'
import { parseBinanceKlines, parseOkxCandles, parseCoinbaseCandles, mergeVol, mergeLiq, liqOfCol, TpsMeter, SLOT_MS, SLOTS, slotOf } from '../src/orderflow/stats'
import { Tape, bpsOf, bpsText, tapeRowH, tapeRowAlpha, TAPE_ROW_SMALL, TAPE_ROW_BIG } from '../src/orderflow/tape'
import type { FineBook, VenueMeta } from '../src/orderflow/aggregate'

const col = (t: number, step: number, lo: number, bid: number[], ask: number[], dur = 60_000): SplitCol =>
  ({ t, dur, step, lo, n: Math.max(bid.length, ask.length), bid: Float32Array.from(bid), ask: Float32Array.from(ask) })

describe('梯子成交列（TradeLadder）', () => {
  it('按细桶累加主动买 / 主动卖，按行再并；换步长清零、since 是第一笔', () => {
    const t = new TradeLadder()
    t.add(100_050, 10, 'buy', 100, 1000)
    t.add(100_150, 5, 'sell', 100, 2000)
    t.add(100_199, 7, 'buy', 100, 3000)
    expect(t.since).toBe(1000)
    const rows = t.rows(2, 0, 1e9)
    // 细桶 1000、1001 在 k=2 下都落在第 500 行
    expect(rows.get(500)).toEqual({ buy: 17, sell: 5 })
    const fine = t.rows(1, 1001, 1001)
    expect(fine.size).toBe(1)
    expect(fine.get(1001)).toEqual({ buy: 7, sell: 5 })
    const v = t.version
    t.add(100_000, 1, 'buy', 50, 4000)
    expect(t.version).toBeGreaterThan(v)
    expect(t.since).toBe(4000)
    expect(t.size).toBe(1)
    t.add(0, 1, 'buy', 50, 5000); t.add(1, -1, 'buy', 50, 5000)
    expect(t.size).toBe(1)
    t.clear()
    expect(t.since).toBeNull()
  })
  it('净差 % 与距中间价、带符号的百分比', () => {
    expect(deltaPct({ buy: 75, sell: 25 })).toBeCloseTo(50)
    expect(deltaPct({ buy: 0, sell: 0 })).toBeNull()
    expect(fromMidPct(100.42, 100)).toBeCloseTo(0.42)
    expect(fromMidPct(1, null)).toBeNull()
    expect(signedPct(0.42)).toBe('+0.42%')
    expect(signedPct(-1.3)).toBe('−1.30%')
    expect(signedPct(12.34)).toBe('+12.3%')
    expect(signedPct(0.001)).toBe('0.00%')
    expect(signedPct(null)).toBe('—')
    expect(signedPct(-50, 0)).toBe('−50%')
  })
})

describe('热力收窄请求与买卖分开的解析', () => {
  it('URL 一律带 lo / hi / bucketMs，价格按 chartScale 换回每个币，时间对齐', () => {
    const u = scopedHeatUrl('BTC', 1_000_123, 2_000_001, 100, 95_000, 105_000, 60_000, 1, 60_000)
    expect(u).toBe('/v1/market/orderflow/heat?base=BTC&from=960000&to=2040000&step=100&lo=95000&hi=105000&bucketMs=60000')
    const k = scopedHeatUrl('PEPE', 0, 5000, 0.01, 1, 2, 1_800_000, 1000)
    expect(k).toContain('step=0.00001&lo=0.001&hi=0.002')
  })
  it('按服务端步长落格，买卖分开；坏行跳过；步长以服务端为准', () => {
    const h = parseHeatSplit({ step: 200, bucketMs: 60_000, rows: [[0, 100_000, 5, 0], [0, 100_200, 0, 7], [60_000, 100_000, 1, 2], [0, -1, 1, 1], 'x', [0, 100_400, 0, 0]] }, 1, 100)!
    expect(h.step).toBe(200)
    expect(h.cols.map(c => c.t)).toEqual([0, 60_000])
    const c0 = h.cols[0]
    expect(c0.lo).toBe(500)
    expect(c0.n).toBe(2)
    expect([...c0.bid]).toEqual([5, 0])
    expect([...c0.ask]).toEqual([0, 7])
    expect(parseHeatSplit([], 1, 1)).toBeNull()
    expect(parseHeatSplit({ rows: [] }, 1, 0)).toBeNull()
  })
  it('colSum 只算格中点落在范围里的；colRows 按行并', () => {
    const c = col(0, 100, 10, [1, 2, 3, 4], [10, 20, 30, 40])
    // 格 10..13 = [1000,1400)，中点 1050/1150/1250/1350
    expect(colSum(c, 1100, 1300)).toEqual([5, 50])
    expect(colSum(c, 0, 1e9)).toEqual([10, 100])
    const r = colRows(c, 200, 0, 100)
    expect(r.get(5)).toEqual([3, 30])
    expect(r.get(6)).toEqual([7, 70])
    expect(colRows(c, 200, 6, 6).size).toBe(1)
  })
})

describe('梯子「变化」模式', () => {
  const venues: VenueMeta[] = [
    { id: 'a', exchange: 'binance', label: '币安', product: 'usdtPerp', instrument: 'BTCUSDT' },
    { id: 'b', exchange: 'okx', label: 'OKX', product: 'spot', instrument: 'BTC-USDT' },
  ]
  const cell = (a: number, b: number) => ({ total: a + b, byVenue: Float64Array.from([a, b]) })
  const fine: FineBook = {
    step: 100, asOfMs: 1, venues, mid: 100_000, bestBid: 99_950, bestAsk: 100_050, ready: 2,
    bid: new Map([[999, cell(1_000_000, 10)], [990, cell(0, 60_000)], [10, cell(9e9, 0)]]),
    ask: new Map([[1000, cell(500_000, 0)]]),
  }
  it('snapFine：中间价 ±半径，按产品门槛 5% 过滤（与服务端同口径）', () => {
    const c = snapFine(fine, { usdtPerp: 5_000_000, spot: 1_000_000 }, 7, 30_000)!
    expect(c.t).toBe(7)
    expect(c.step).toBe(100)
    // 币安 1M ≥ 25 万留；OKX 10 < 5 万丢；OKX 6 万 ≥ 5 万留；±5% 以外的 idx 10 不要
    expect(colSum(c, 99_900, 100_100)).toEqual([1_000_000, 500_000])
    expect(colSum(c, 99_000, 99_100)[0]).toBe(60_000)
    expect(c.bid.reduce((a, b) => a + b, 0)).toBe(1_060_000)
    expect(snapFine({ ...fine, mid: null }, {}, 0, 0)).toBeNull()
  })
  it('deltaRows：现在 − 窗口开始，买卖分开；只算开始那一列覆盖到的行', () => {
    const start = col(0, 100, 998, [5, 10, 0], [0, 0, 8])
    const now = col(1, 100, 998, [5, 4, 0], [0, 0, 20])
    const d = deltaRows(start, null, now, 100, 990, 1010)
    expect(d.get(999)).toMatchObject({ bid0: 10, bid: 4, dBid: -6, dAsk: 0 })
    expect(d.get(1000)).toMatchObject({ ask0: 8, ask: 20, dAsk: 12 })
    expect(d.get(998)).toMatchObject({ dBid: 0 })
    // 服务端只覆盖 [99 900, 100 000)：别的行不给
    const cut = deltaRows(start, [99_900, 100_000], now, 100, 990, 1010)
    expect([...cut.keys()]).toEqual([999])
    expect(deltaRows(start, [100_000, 99_000], now, 100, 990, 1010).size).toBe(0)
  })
  it('firstFrom 取最早一列覆盖到窗口开始的；rowSeries 与小折线', () => {
    const cols = [col(0, 100, 999, [1], [0], 60_000), col(60_000, 100, 999, [3], [2], 60_000), col(120_000, 100, 999, [2], [4], 60_000)]
    expect(firstFrom(cols, 30_000)!.t).toBe(0)
    expect(firstFrom(cols, 60_000)!.t).toBe(60_000)
    expect(firstFrom(cols, 1e9)).toBeNull()
    const s = rowSeries(cols, 999, 100)
    expect(s.map(p => p.bid)).toEqual([1, 3, 2])
    expect(s.map(p => p.ask)).toEqual([0, 2, 4])
    const svg = sparkSVG(s, 200, 40, '#0a0', '#a00')
    expect(svg).toContain('<svg')
    expect(svg.match(/<path/g)!.length).toBe(2)
    expect(sparkSVG(s.slice(0, 1), 200, 40, '#0a0', '#a00')).toBe('')
  })
  it('niceCeil 取 1 / 2 / 5 × 10ⁿ', () => {
    expect(niceCeil(0.3)).toBe(1)
    expect(niceCeil(1)).toBe(1)
    expect(niceCeil(1.2)).toBe(2)
    expect(niceCeil(3)).toBe(5)
    expect(niceCeil(7)).toBe(10)
    expect(niceCeil(15)).toBe(20)
    expect(niceCeil(480)).toBe(500)
  })
})

describe('24 小时成交 / 流动性 / 每秒成交', () => {
  const now = Date.UTC(2026, 8, 29, 12, 10)
  const first = slotOf(now) - (SLOTS - 1) * SLOT_MS
  it('三家 K 线解析：币安带主动买，OKX / Coinbase 只有总额（Coinbase 计价额 = 量 × 收盘）', () => {
    const bn = parseBinanceKlines([[first, '1', '2', '0.5', '1.5', '10', 0, '1000', 5, '4', '600', '0'], 'bad'])
    expect(bn).toEqual([{ t: first, h: 2, l: 0.5, c: 1.5, quote: 1000, buy: 600 }])
    const ok = parseOkxCandles({ data: [[String(first + SLOT_MS), '1', '2', '1', '1', '1', '1', '300', '1'], [String(first), '1', '2', '1', '1', '1', '1', '200', '1']] })
    expect(ok.map(k => k.t)).toEqual([first, first + SLOT_MS])
    expect(ok[0].buy).toBeNull()
    const cb = parseCoinbaseCandles({ candles: [{ start: String(first / 1000), low: '1', high: '3', open: '2', close: '2', volume: '50' }] })
    expect(cb[0].quote).toBe(100)
    expect(parseOkxCandles({})).toEqual([])
  })
  it('mergeVol：48 格，币安拆买卖，OKX / Coinbase 只计总额，窗口外的丢', () => {
    const s = mergeVol([
      { exchange: 'binance', k: [{ t: first, h: 0, l: 0, c: 0, quote: 1000, buy: 600 }, { t: first - SLOT_MS, h: 0, l: 0, c: 0, quote: 9, buy: 9 }] },
      { exchange: 'okx', k: [{ t: first, h: 0, l: 0, c: 0, quote: 200, buy: null }] },
      { exchange: 'coinbase', k: [{ t: slotOf(now), h: 0, l: 0, c: 0, quote: 50, buy: null }] },
    ], now)
    expect(s.length).toBe(SLOTS)
    expect(s[0]).toEqual({ t: first, total: 1200, bnBuy: 600, bnSell: 400, okx: 200, cb: 0 })
    expect(s[SLOTS - 1]).toMatchObject({ t: slotOf(now), total: 50, cb: 50 })
  })
  it('liqOfCol：中间价 ±2.5%；没给中间价按买卖分界算', () => {
    // 步长 1000：格 95..104 = 95 000..105 000
    const c = col(0, 1000, 95, [1, 1, 1, 1, 1, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 2, 2, 2, 2, 2])
    // ±2.5% of 100 000 = [97 500, 102 500]：中点 97 500 起的格 97..101
    expect(liqOfCol(c, 100_000)).toEqual([3, 4])
    expect(liqOfCol(c, undefined)).toEqual([3, 4])
    expect(liqOfCol(col(0, 1, 0, [0], [0]), undefined)).toBeNull()
  })
  it('mergeLiq：服务端优先、实时点补空格，按时间排、最多 48 个', () => {
    const srv = new Map<number, [number, number]>([[first, [10, 20]], [first - SLOT_MS, [1, 1]]])
    const live = new Map([[first, { bid: 99, ask: 99, n: 1 }], [slotOf(now), { bid: 30, ask: 60, n: 3 }]])
    const p = mergeLiq(srv, live, now)
    expect(p).toEqual([{ t: first, bid: 10, ask: 20, src: 'server' }, { t: slotOf(now), bid: 10, ask: 20, src: 'live' }])
  })
  it('TpsMeter：最近 10 秒平均，旧的滚出去；还没有成交给 null', () => {
    const m = new TpsMeter()
    expect(m.rate(0)).toBeNull()
    const t0 = 1_000_000_000
    for (let s = 0; s < 10; s++) for (let i = 0; i < 4; i++) m.add(t0 + s * 1000 + i)
    expect(m.rate(t0 + 10_000)).toBeCloseTo(4)
    expect(m.series(t0 + 10_000).slice(-10)).toEqual(Array(10).fill(4))
    expect(m.rate(t0 + 300_000)).toBe(0)
    m.clear()
    expect(m.rate(t0 + 300_000)).toBeNull()
  })
})

describe('成交流：bps、行高、底色', () => {
  const base = { exchange: 'binance', label: '币安', product: 'usdtPerp' as const, qty: 1, usd: 1000 }
  it('bps 对同一家同一本簿的上一笔算；|bps| < 0.5 不显示', () => {
    const t = new Tape()
    const a = t.push({ ...base, t: 0, side: 'buy', price: 100_000, instrument: 'BTCUSDT' })
    expect(a.bps).toBeNull()
    t.push({ ...base, exchange: 'okx', t: 10, side: 'buy', price: 90_000, instrument: 'BTC-USDT-SWAP' })
    const b = t.push({ ...base, t: 2000, side: 'sell', price: 100_100, instrument: 'BTCUSDT' })
    expect(b.bps).toBeCloseTo(10)
    const c = t.push({ ...base, t: 4000, side: 'sell', price: 100_100, instrument: 'BTCUSDT_260925' })
    expect(c.bps).toBeNull()
    expect(bpsOf(99, 100)).toBeCloseTo(-100)
    expect(bpsOf(1, undefined)).toBeNull()
    expect(bpsText(0.49)).toBeNull()
    expect(bpsText(0.5)).toBe('+0.5')
    expect(bpsText(-12.34)).toBe('−12.3')
    expect(bpsText(250)).toBe('+250')
    expect(bpsText(null)).toBeNull()
  })
  it('行高：≥ 门槛 ÷ 5 长到 28；底色浓度 clamp(金额 ÷ 门槛, 0.04, 0.35)', () => {
    expect(tapeRowH(199, 200)).toBe(TAPE_ROW_SMALL)
    expect(tapeRowH(200, 200)).toBe(TAPE_ROW_BIG)
    expect(tapeRowH(1e9, 0)).toBe(TAPE_ROW_SMALL)
    expect(tapeRowAlpha(1, 1000)).toBe(0.04)
    expect(tapeRowAlpha(200, 1000)).toBeCloseTo(0.2)
    expect(tapeRowAlpha(5000, 1000)).toBe(0.35)
    expect(tapeRowAlpha(5000, 0)).toBe(0.04)
  })
})

describe('侧栏：加上 24 小时流动性 / 成交两块', () => {
  it('2560×1440 全开八块：总和不超过侧栏，两块统计压到 floor（图 72 高，B 路 d580296c 的收缩次序），其余不低于 floor', async () => {
    const { planSidebar, PARTS, STAT_H, SEP } = await import('../src/orderflow/sidebar')
    const ids = ['watch', 'detail', 'book', 'tape', 'walls', 'liq', 'vol', 'alerts'] as const
    const h = planSidebar(1384, ids, new Set())
    expect(h.reduce((a, b) => a + b, 0)).toBeLessThanOrEqual(1384)
    expect(h[5]).toBe(SEP + STAT_H - 16)
    expect(h[6]).toBe(SEP + STAT_H - 16)
    ids.forEach((id, i) => expect(h[i]).toBeGreaterThanOrEqual(PARTS[id].floor))
    // 收起一块统计：只剩标题行
    const c = planSidebar(1384, ids, new Set(['liq']))
    expect(c[5]).toBe(PARTS.liq.head)
  })
})
