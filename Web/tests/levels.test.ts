import { beforeEach, describe, expect, it } from 'vitest'
import type { Bar } from '../src/chart/calc'
import { vwap } from '../src/chart/indicators'
import { vpvr } from '../src/chart/overlays'
import { fineOf } from '../src/chart/fineVolume'
import { dailyLevels, profileLevels, touchIndex, levelsForInterval, weekStartOf, dayStartOf } from '../src/chart/keyLevels'
import { flowOf, resetFlows, recordTrade, beat, cvdFlow, whaleFlow, parseFlow, shortUsd, SMALL_USD } from '../src/chart/tradeFlow'
import type { TradeEvent } from '../src/orderflow/feed'

const bar = (t: number, o: number, h: number, l: number, c: number, v: number, extra: Partial<Bar> = {}): Bar => ({ t, o, h, l, c, v, ...extra })
const DAY = 864e5, MIN = 60e3

describe('VWAP 第一段', () => {
  const day = Date.UTC(2026, 8, 29)
  const mk = (from: number, n: number) => Array.from({ length: n }, (_, k) => { const t = from + k * 36e5 / 4; const p = 100 + Math.sin(k) * 3; return bar(t, p, p + 1, p - 1, p, 1000, { bv: 10 + k % 5 }) })
  it('加载进来的第一根不是一段的开头：这一段整段是空的，到下一个锚点才出值', () => {
    const bars = mk(day - 6 * 36e5, 40) // 15 分钟线，从前一天 18:00 UTC 开始
    const [m] = vwap(bars, 15 * MIN)
    const first = bars.findIndex(b => b.t >= day)
    expect(m.slice(0, first).every(v => v == null)).toBe(true)
    expect(m[first]).not.toBeNull()
  })
  it('第一根正好是开头：第一段照常画', () => {
    const bars = mk(day, 8)
    expect(vwap(bars, 15 * MIN)[0][0]).not.toBeNull()
  })
  it('往左补历史：已经画出来的值一个都不变', () => {
    const all = mk(day - 30 * 36e5, 200)
    const tail = all.slice(80)
    const a = vwap(tail, 15 * MIN), b = vwap(all, 15 * MIN)
    for (let j = 0; j < 5; j++) for (let i = 0; i < tail.length; i++) {
      const x = a[j][i]
      if (x != null) expect(b[j][i + 80]).toBeCloseTo(x, 9)
    }
    // 补进来以后前面那段也有值了
    expect(b[0].filter(v => v != null).length).toBeGreaterThan(a[0].filter(v => v != null).length)
  })
})

describe('成交量分布：粗周期用细 K 线', () => {
  it('细周期：4 小时起 15 分钟，1 天起 1 小时，更短不用', () => {
    expect(fineOf(36e5)).toBeNull()
    expect(fineOf(4 * 36e5)?.name).toBe('15m')
    expect(fineOf(DAY)?.name).toBe('1h')
    expect(fineOf(7 * DAY)?.name).toBe('1h')
  })
  it('拆开的根按细 K 线各自的高低摊，总量守恒；控制点落到细 K 线真正放量的价位', () => {
    // 一根粗 K 线 100–110：均匀摊的话每行一样；细 K 线说量全在 108–109
    const coarse = [bar(0, 100, 110, 100, 105, 1000, { tb: 500 })]
    const fine = [bar(0, 100, 101, 100, 101, 10, { tb: 5 }), bar(1, 108, 109, 108, 109, 980, { tb: 490 }), bar(2, 104, 105, 104, 105, 10, { tb: 5 })]
    const even = vpvr(coarse, 0, 0, 10)!
    const split = vpvr(coarse, 0, 0, 10, 0.7, i => i === 0 ? fine : null)!
    expect(split.total).toBeCloseTo(even.total, 9)
    expect(split.poc).toBe(8)
    expect(split.vaHi - split.vaLo).toBe(0)
    // 拆分函数回 null 的根照旧均匀摊
    const none = vpvr(coarse, 0, 0, 10, 0.7, () => null)!
    expect(none.rows.map(r => r.buy + r.sell)).toEqual(even.rows.map(r => r.buy + r.sell))
  })
})

describe('关键价位', () => {
  const today = Date.UTC(2026, 8, 29) // 周二
  const now = today + 5 * 36e5
  it('日界 UTC 0 点（上海 8 点），周界周一 UTC 0 点', () => {
    expect(dayStartOf(now)).toBe(today)
    expect(weekStartOf(now)).toBe(Date.UTC(2026, 8, 28))
    expect(new Date(weekStartOf(Date.UTC(2026, 9, 4, 23))).getUTCDay()).toBe(1) // 周日晚 → 本周一
    expect(weekStartOf(Date.UTC(2026, 8, 28))).toBe(Date.UTC(2026, 8, 28))
  })
  it('日线 → 昨高昨低、今开、上周高低（只用走完的上一整周）', () => {
    const daily: Bar[] = []
    for (let d = 16; d >= 0; d--) { const t = today - d * DAY; daily.push(bar(t, 100 + d, 110 + d, 90 - d, 100, 1)) }
    const lv = dailyLevels(daily, now), by = (k: string) => lv.find(l => l.key === k)!
    expect(by('yh').price).toBe(111); expect(by('yl').price).toBe(89)
    expect(by('to').price).toBe(100)
    // 上一整周：9-21（周一）到 9-27，d = 8..2
    expect(by('wh').price).toBe(118); expect(by('wl').price).toBe(82)
    expect(by('wh').from).toBe(Date.UTC(2026, 8, 28)); expect(by('yh').from).toBe(today)
    expect(by('wh').tier).toBe('week'); expect(by('to').tier).toBe('day')
  })
  it('昨天的 5 分钟 K 线 → 昨控、昨值上下（裸线）；不够九成不出', () => {
    const y = today - DAY, bars: Bar[] = []
    for (let k = 0; k < 288; k++) bars.push(bar(y + k * 5 * MIN, 100, 101, 99, 100, k === 100 ? 50_000 : 100))
    bars[100] = bar(y + 100 * 5 * MIN, 150, 151, 149, 150, 50_000)
    const lv = profileLevels(bars, now)
    expect(lv.map(l => l.label)).toEqual(['昨控', '昨值上', '昨值下'])
    expect(lv.every(l => l.naked && l.tier === 'day')).toBe(true)
    expect(lv[0].price).toBeGreaterThan(149); expect(lv[0].price).toBeLessThan(151)
    expect(lv[1].price).toBeGreaterThanOrEqual(lv[0].price); expect(lv[2].price).toBeLessThanOrEqual(lv[0].price)
    expect(profileLevels(bars.slice(0, 200), now)).toEqual([])
  })
  it('裸线：今天第一次碰到的那根；昨天的碰不算', () => {
    const bars = [bar(today - MIN, 1, 5, 1, 5, 1), bar(today, 2, 3, 2, 3, 1), bar(today + MIN, 3, 4, 3, 4, 1), bar(today + 2 * MIN, 4, 6, 4, 6, 1)]
    expect(touchIndex(bars, 5, today)).toBe(3)
    expect(touchIndex(bars, 10, today)).toBe(-1)
  })
  it('1 天以下全画，1 天到 1 周只画周，1 周及以上不画', () => {
    const all = [{ key: 'yh', label: '昨高', price: 1, tier: 'day' as const, from: 0, naked: false }, { key: 'wh', label: '上周高', price: 2, tier: 'week' as const, from: 0, naked: false }]
    expect(levelsForInterval(all, 36e5).length).toBe(2)
    expect(levelsForInterval(all, DAY).map(l => l.key)).toEqual(['wh'])
    expect(levelsForInterval(all, 7 * DAY)).toEqual([])
  })
})

const ev = (symbol: string, exchange: string, product: string, usd: number, buy: boolean, t: number): TradeEvent => ({
  book: { venue: { exchange, product, instrument: symbol } }, trade: { price: 1, quantity: usd, hitSide: buy ? 'ask' : 'bid', timeMs: t }, usd,
} as unknown as TradeEvent)

describe('三家逐笔：累计量差的实时段', () => {
  beforeEach(() => resetFlows())
  it('覆盖区间以外只有币安；以内合计 = 币安 U 本位 + 三家其余；现货 / 合约从前一根分叉', () => {
    const t0 = Date.UTC(2026, 8, 29, 1), now = t0 + 10 * MIN
    const bars = Array.from({ length: 4 }, (_, k) => bar(t0 + k * MIN, 1, 1, 1, 1, 100, { tb: 60 })) // 每根币安差 +20
    const f = flowOf('BTCUSDT')
    for (let s = t0 + 2 * MIN - 1000; s <= now; s += 500) beat('BTCUSDT', s, true)
    for (const k of [2, 3]) {
      const t = t0 + k * MIN + 1000
      recordTrade('BTCUSDT', ev('BTCUSDT', 'binance', 'usdtPerp', 50, true, t), null) // 与 K 线自带的是同一份
      recordTrade('BTCUSDT', ev('BTCUSDT', 'okx', 'usdtPerp', 30, false, t), null)
      recordTrade('BTCUSDT', ev('BTC-USD', 'coinbase', 'spot', 40, true, t), null)
    }
    const [tot, spot, con] = cvdFlow(bars, MIN, f, now)
    expect(tot.slice(0, 2)).toEqual([20, 40])
    expect(spot[0]).toBeNull(); expect(spot[1]).toBe(40); expect(con[1]).toBe(40)
    // 每根：现货 +40，合约 = 20（币安）− 30（OKX）= −10
    expect(spot[2]).toBe(80); expect(con[2]).toBe(30); expect(tot[2]).toBe(70)
    expect(tot[3]).toBe(100)
  })
})

describe('大单与散户累计量差', () => {
  beforeEach(() => resetFlows())
  it('服务端有行用服务端的；在跟且落在历史里却没有行 = 这分钟没成交；之前是空', () => {
    const t0 = Date.UTC(2026, 8, 29, 1), now = t0 + 60 * MIN
    const f = flowOf('ETHUSDT')
    f.srv.tracked = true
    f.srv.rows.set(t0 + MIN, [1000, 0, 5, 10]); f.srv.rows.set(t0 + 3 * MIN, [0, 400, 20, 0])
    f.srv.lo = t0 + MIN; f.srv.hi = t0 + 3 * MIN
    const bars = Array.from({ length: 5 }, (_, k) => bar(t0 + k * MIN, 1, 1, 1, 1, 1))
    const [big, small] = whaleFlow(bars, MIN, f, now)
    expect(big).toEqual([null, 1000, 1000, 600, 600]) // 有数据以后没有新数据的根沿用前值
    expect(small).toEqual([null, -5, -5, 15, 15])
  })
  it('覆盖区间里用浏览器的：≥ 大单线算大单、< 1 万算散户、中间的都不算', () => {
    const t0 = Date.UTC(2026, 8, 29, 2), now = t0 + 3 * MIN
    const f = flowOf('SOLUSDT')
    for (let s = t0 - 1000; s <= now; s += 500) beat('SOLUSDT', s, true)
    recordTrade('SOLUSDT', ev('SOLUSDT', 'binance', 'usdtPerp', 200_000, true, t0 + 1000), 100_000)
    recordTrade('SOLUSDT', ev('SOLUSDT', 'okx', 'spot', 50_000, false, t0 + 2000), 100_000)
    recordTrade('SOLUSDT', ev('SOLUSDT', 'coinbase', 'spot', SMALL_USD - 1, false, t0 + 3000), 100_000)
    const bars = [bar(t0, 1, 1, 1, 1, 1), bar(t0 + MIN, 1, 1, 1, 1, 1)]
    const [big, small] = whaleFlow(bars, MIN, f, now)
    expect(big).toEqual([200_000, 200_000])
    expect(small).toEqual([-(SMALL_USD - 1), -(SMALL_USD - 1)])
  })
  it('没有任何数据：两条都是空', () => {
    const [big] = whaleFlow([bar(0, 1, 1, 1, 1, 1)], MIN, flowOf('XRPUSDT'), 1e12)
    expect(big).toEqual([null])
  })
  it('解服务端答复：坏行丢掉，没在跟也照样认', () => {
    expect(parseFlow({ tracked: true, bigUsd: 100000, rows: [[60000, 1, 2, 3, 4], [1, 'x'], null] })).toEqual({ tracked: true, bigUsd: 100000, rows: [[60000, 1, 2, 3, 4]] })
    expect(parseFlow({ tracked: false, rows: [] })).toEqual({ tracked: false, bigUsd: null, rows: [] })
    expect(parseFlow({})).toBeNull()
  })
  it('金额短写用 K / M / B', () => {
    expect(shortUsd(100_000)).toBe('100K'); expect(shortUsd(1_500_000)).toBe('1.5M'); expect(shortUsd(2e9)).toBe('2B')
  })
})
