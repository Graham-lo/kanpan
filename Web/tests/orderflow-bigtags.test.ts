/* Hkline Web · 主力订单流 2026-10-08：图上「大单签」、底部抽屉四块摘要、爆仓数据、四个开关互不牵连
 * 签：相对档位（最近 300 根的 P85 / P95 / max(P99, 3×P95)，垫绝对下限，数据不变不重算）、一根一枚、另一侧过 P95 才描边、
 *     夹在主图里（让开成交量）、本侧放不下翻到另一侧、两侧都撞退成三角、三角也放不下不画；数据：分钟桶并根、服务端历史接缝；
 * 抽屉：北京时间零点、三窗口、现货 / 合约与三家占比、价位（浏览器真实价 + 服务端行 × 1 分钟典型价）、最近的墙、
 *     开方比例尺、占比条至少两段、十字线所在根；爆仓：解析、合计、30 秒轮询与失败重试、只留 16 只。 */
import { afterEach, describe, expect, it, vi } from 'vitest'
import { flowOf, recordTrade, beat, resetFlows } from '../src/chart/tradeFlow'
import type { TradeEvent } from '../src/orderflow/feed'
import { barBig, BigBarCache, TierCache, planTags, tierOf, tiersFrom, quantile, unitFor, ivName, TIER_BARS, type PlanEnv, type TagIn, type BarBig, type Tiers } from '../src/orderflow/bigTags'
import { dayStart8, windows, liveShares, priceLevels, nearestWalls, HOUR, PX_MINUTES } from '../src/orderflow/summary'
import { parseLiq, sumLiq, LiqStore, LIQ_POLL_MS, LIQ_MAX_SYMBOLS, LIQ_KEEP_MS, type LiqRow } from '../src/orderflow/liquidation'
import type { BigOrder } from '../src/orderflow/types'

afterEach(() => { resetFlows(); vi.restoreAllMocks(); vi.resetModules() })

const T0 = Date.UTC(2026, 9, 8, 2, 0, 0)   // 北京时间 10:00
function trade(sym: string, t: number, usd: number, buy: boolean, o: { ex?: string; product?: 'spot' | 'usdtPerp'; price?: number } = {}): void {
  const ev = {
    book: { venue: { exchange: o.ex ?? 'binance', product: o.product ?? 'usdtPerp', instrument: sym } },
    trade: { timeMs: t, hitSide: buy ? 'ask' : 'bid', price: o.price ?? 100 },
    usd,
  } as unknown as TradeEvent
  recordTrade(sym, ev, 10_000)   // 大单线 1 万 → 档位单位 10 万
}
/** 从 a 到 b 每半秒一拍心跳（覆盖区间） */
function cover(sym: string, a: number, b: number): void { for (let t = a; t <= b; t += 500) beat(sym, t, true) }

describe('档位', () => {
  it('三档的线：不到 t1 不画、t1 三角、t2 金额签、t3 大签；没有档位一律不画', () => {
    const k: Tiers = { t1: 100_000, t2: 300_000, t3: 1_000_000 }
    expect(tierOf(99_999, k)).toBe(0)
    expect(tierOf(100_000, k)).toBe(1)
    expect(tierOf(299_999, k)).toBe(1)
    expect(tierOf(300_000, k)).toBe(2)
    expect(tierOf(1_000_000, k)).toBe(3)
    expect(tierOf(5, null)).toBe(0)
    expect(tierOf(0, k)).toBe(0)
  })
  it('分位数线性插值（同 numpy 默认）', () => {
    expect(quantile([1, 2, 3, 4, 5], 0.5)).toBe(3)
    expect(quantile([0, 10], 0.85)).toBeCloseTo(8.5)
    expect(quantile([7], 0.99)).toBe(7)
    expect(quantile([], 0.5)).toBe(0)
  })
  it('相对档位：P85 / P95 / max(P99, 3×P95)，只看非零的根；绝对下限垫底', () => {
    const vals = Array.from({ length: 100 }, (_, i) => (i + 1) * 1000).concat([0, 0, 0])   // 1K..100K + 三根没大单
    const k = tiersFrom(vals, 0)!
    expect(k.t1).toBeCloseTo(85_150); expect(k.t2).toBeCloseTo(95_050)
    expect(k.t3).toBeCloseTo(3 * 95_050)   // 3 × P95 比 P99 大
    // 一屏 100 根里够得上三角的约 15 根
    expect(vals.filter(v => v >= k.t1).length).toBe(15)
    const floored = tiersFrom(vals, 200_000)!
    expect(floored).toEqual({ t1: 200_000, t2: 200_000, t3: 3 * 95_050 })
    expect(tiersFrom([0, 0], 1)).toBeNull()
  })
  it('档位缓存：取最近 300 根；数据版本（缓存代数 / 最后一根）不变就不重算', () => {
    const s = 'SOLUSDT', f = flowOf(s), c = new BigBarCache(), tc = new TierCache()
    const N = 400, now = T0 + N * 60_000
    cover(s, T0, now)
    for (let k = 0; k < N; k++) trade(s, T0 + k * 60_000 + 5, 100_000 + (k < N - TIER_BARS ? 9e7 : k * 1000), true)
    const bars = Array.from({ length: N }, (_, k) => ({ t: T0 + k * 60_000 }))
    const ch = { bars, timeAt: (i: number) => T0 + i * 60_000 }
    c.begin(f, 'SOLUSDT|60000', now)
    const k1 = tc.get(c, f, ch, now, 0)!
    expect(tc.computed).toBe(1)
    // 最早那 100 根（9 千万）不在最近 300 根里，不进分布
    expect(k1.t3).toBeLessThan(9e7)
    expect(tc.get(c, f, ch, now, 0)).toBe(k1)
    expect(tc.computed).toBe(1)
    f.srv.ver++; c.begin(f, 'SOLUSDT|60000', now)
    tc.get(c, f, ch, now, 0)
    expect(tc.computed).toBe(2)
    tc.get(c, f, ch, now, 500_000)   // 下限变了也重算
    expect(tc.computed).toBe(3)
  })
  it('单位：这只的大单线 × 10（= 门槛 ÷ 5），不知道就用活动那只的', () => {
    const f = flowOf('SOLUSDT')
    expect(unitFor(f, 777)).toBe(777)
    f.localCut = 20_000
    expect(unitFor(f, 777)).toBe(200_000)
    f.srv.bigUsd = 30_000
    expect(unitFor(f, 777)).toBe(300_000)
  })
  it('周期中文名', () => {
    expect(ivName(60_000)).toBe('1 分钟')
    expect(ivName(300_000)).toBe('5 分钟')
    expect(ivName(3_600_000)).toBe('1 小时')
    expect(ivName(86_400_000)).toBe('日线')
  })
})

describe('摆放', () => {
  const big = (bb: number, bs: number): BarBig => ({ t: 0, t1: 1, bb, bs, bn: null, sn: null, bmax: null, smax: null, spot: null, ex: null, exact: false })
  const env = (o: Partial<PlanEnv> = {}): PlanEnv => ({
    tiers: { t1: 100_000, t2: 300_000, t3: 1_000_000 }, spacing: 8, top: 0, bottom: 400, plotW: 800,
    span: () => ({ hiY: 100, loY: 200 }),
    measure: t => t.length * 6, text: u => `${Math.round(u / 1000)}K`, avoid: [], ...o,
  })
  it('一根一枚：买卖里大的那一侧（买挂最高价上方、卖挂最低价下方）；另一侧没过 P95 不画', () => {
    const tags = planTags([{ i: 0, t: 0, x: 100, data: big(500_000, 150_000) }], env())
    expect(tags).toHaveLength(1)
    expect(tags[0]).toMatchObject({ side: 'buy', kind: 'tag', filled: true })
    expect(tags[0].y + tags[0].h).toBeLessThanOrEqual(100)
    const sell = planTags([{ i: 0, t: 0, x: 100, data: big(120_000, 2_000_000) }], env())
    expect(sell).toHaveLength(1)
    expect(sell[0]).toMatchObject({ side: 'sell', kind: 'big', filled: true })
    expect(sell[0].y).toBeGreaterThanOrEqual(200)
  })
  it('另一侧自己也过 P95：另画一枚描边签', () => {
    const tags = planTags([{ i: 0, t: 0, x: 100, data: big(1_500_000, 400_000) }], env())
    expect(tags).toHaveLength(2)
    const buy = tags.find(t => t.side === 'buy')!, sell = tags.find(t => t.side === 'sell')!
    expect(buy).toMatchObject({ kind: 'big', filled: true })
    expect(sell).toMatchObject({ kind: 'tag', filled: false })
  })
  it('一根太窄就退回三角；签与签不叠', () => {
    const narrow = planTags([{ i: 0, t: 0, x: 100, data: big(500_000, 0) }], env({ spacing: 2 }))
    expect(narrow[0].kind).toBe('tri')
    const list: TagIn[] = [0, 1, 2].map(i => ({ i, t: i, x: 100 + i * 8, data: big(400_000 + i, 0) }))
    const tags = planTags(list, env())
    for (let a = 0; a < tags.length; a++) for (let b = a + 1; b < tags.length; b++) {
      const p = tags[a], q = tags[b]
      if (p.kind === 'tri' && q.kind === 'tri') continue
      expect(p.x < q.x + q.w && q.x < p.x + p.w && p.y < q.y + q.h && q.y < p.y + p.h).toBe(false)
    }
  })
  it('本侧撞上图例 / 画线文字：先翻到 K 线另一侧，颜色与朝向不变', () => {
    const t = planTags([{ i: 0, t: 0, x: 100, data: big(500_000, 0) }], env({ avoid: [{ x: 0, y: 70, w: 300, h: 30 }] }))
    expect(t).toHaveLength(1); expect(t[0]).toMatchObject({ side: 'buy', kind: 'tag' }); expect(t[0].y).toBe(204)
  })
  it('两侧都撞：退成三角（先本侧），不往外挪；三角两侧也撞就不画', () => {
    // 上方盖住签（80–96）但露出三角（90–96）；下方盖住签（204–220）与三角（204–210）
    const avoid = [{ x: 0, y: 70, w: 300, h: 19 }, { x: 0, y: 200, w: 300, h: 30 }]
    const t = planTags([{ i: 0, t: 0, x: 100, data: big(500_000, 0) }], env({ avoid }))
    expect(t).toHaveLength(1); expect(t[0].kind).toBe('tri'); expect(t[0].y + t[0].h).toBe(96)
    const none = planTags([{ i: 0, t: 0, x: 100, data: big(500_000, 0) }], env({ avoid: [{ x: 0, y: 70, w: 300, h: 30 }, avoid[1]] }))
    expect(none).toHaveLength(0)
  })
  it('夹在主图里：顶上没地方的买签翻到最低价下方；卖签掉进成交量那一截（bottom 以下）翻到最高价上方', () => {
    const top = planTags([{ i: 0, t: 0, x: 100, data: big(500_000, 0) }], env({ span: () => ({ hiY: 3, loY: 200 }) }))
    expect(top).toHaveLength(1); expect(top[0]).toMatchObject({ side: 'buy', kind: 'tag' }); expect(top[0].y).toBe(204)
    const low = planTags([{ i: 0, t: 0, x: 100, data: big(0, 500_000) }], env({ span: () => ({ hiY: 100, loY: 330 }), bottom: 336 }))
    expect(low).toHaveLength(1); expect(low[0]).toMatchObject({ side: 'sell', kind: 'tag' }); expect(low[0].y + low[0].h).toBe(96)
    // 两侧签都放不下、三角本侧放得下：退成本侧三角
    const tri = planTags([{ i: 0, t: 0, x: 100, data: big(0, 500_000) }], env({ span: () => ({ hiY: 12, loY: 320 }), bottom: 336 }))
    expect(tri).toHaveLength(1); expect(tri[0].kind).toBe('tri'); expect(tri[0].y).toBe(324); expect(tri[0].y + tri[0].h).toBeLessThanOrEqual(336)
    // 窗格矮到两侧连三角都放不下：不画
    expect(planTags([{ i: 0, t: 0, x: 100, data: big(0, 500_000) }], env({ span: () => ({ hiY: 5, loY: 330 }), bottom: 336 }))).toHaveLength(0)
  })
  it('不越过价格轴：右沿出界的签退成三角', () => {
    const t = planTags([{ i: 0, t: 0, x: 796, data: big(500_000, 0) }], env())
    expect(t).toHaveLength(1); expect(t[0].kind).toBe('tri'); expect(t[0].x + t[0].w).toBeLessThanOrEqual(800)
  })
})

describe('一根的大单合计', () => {
  it('浏览器的分钟桶按根并：金额、笔数、最大一笔、现货与三家', () => {
    const s = 'SOLUSDT'
    cover(s, T0, T0 + 5 * 60_000)
    trade(s, T0 + 10_000, 120_000, true, { ex: 'okx', product: 'spot', price: 101 })
    trade(s, T0 + 70_000, 300_000, true, { price: 102 })
    trade(s, T0 + 200_000, 50_000, false, { ex: 'coinbase', product: 'spot' })
    trade(s, T0 + 200_000, 5_000, false)   // 不到大单线，不算
    const b = barBig(flowOf(s), T0, T0 + 5 * 60_000, T0 + 5 * 60_000)!
    expect(b.bb).toBe(420_000); expect(b.bs).toBe(50_000)
    expect(b.bn).toBe(2); expect(b.sn).toBe(1)
    expect(b.bmax?.usd).toBe(300_000); expect(b.bmax?.price).toBe(102)
    expect(b.spot).toBe(170_000)
    expect(b.ex).toEqual([300_000, 120_000, 50_000])
    expect(b.exact).toBe(true)
  })
  it('接缝：覆盖之前的分钟用服务端的行（只有金额，笔数等给 null）；覆盖之后用浏览器的', () => {
    const s = 'BTCUSDT', f = flowOf(s)
    f.srv.tracked = true
    f.srv.rows.set(T0, [700_000, 0, 0, 0]); f.srv.rows.set(T0 + 60_000, [0, 0, 0, 0])
    f.srv.lo = T0; f.srv.hi = T0 + 60_000
    cover(s, T0 + 2 * 60_000, T0 + 5 * 60_000)
    trade(s, T0 + 3 * 60_000 + 1, 200_000, false)
    const b = barBig(f, T0, T0 + 5 * 60_000, T0 + 5 * 60_000)!
    expect(b.bb).toBe(700_000); expect(b.bs).toBe(200_000)
    expect(b.exact).toBe(false); expect(b.bn).toBeNull(); expect(b.bmax).toBeNull(); expect(b.ex).toBeNull()
    // 纯浏览器那一根照样精确
    const live = barBig(f, T0 + 3 * 60_000, T0 + 4 * 60_000, T0 + 5 * 60_000)!
    expect(live.exact).toBe(true); expect(live.sn).toBe(1)
    // 服务端在跟、历史里这分钟没大单 → 这根没有签
    expect(barBig(f, T0 + 60_000, T0 + 2 * 60_000, T0 + 5 * 60_000)).toBeNull()
  })
  it('缓存：算过的根拖动缩放时不再算；服务端来新行整份作废；有新大单只放掉最近 3 分钟的根', () => {
    const s = 'ETHUSDT', f = flowOf(s), c = new BigBarCache()
    cover(s, T0, T0 + 30 * 60_000)
    for (let k = 0; k < 30; k++) trade(s, T0 + k * 60_000 + 5, 150_000, true)
    const now = T0 + 30 * 60_000
    const run = (): void => { c.begin(f, 'ETHUSDT|60000', now); for (let k = 0; k < 30; k++) c.get(f, T0 + k * 60_000, T0 + (k + 1) * 60_000, now) }
    run(); expect(c.computed).toBe(30)
    run(); run(); expect(c.computed).toBe(30)
    trade(s, now - 10_000, 150_000, true)
    run(); expect(c.computed).toBeLessThanOrEqual(34)
    expect(c.computed).toBeGreaterThan(30)
    f.srv.ver++
    run(); expect(c.computed).toBeGreaterThanOrEqual(60)
  })
})

describe('抽屉 · 汇总', () => {
  it('今日按北京时间零点切：UTC 15:59 还是前一天，16:00 是新的一天', () => {
    const d = Date.UTC(2026, 9, 7, 16, 0, 0)
    expect(dayStart8(d)).toBe(d)
    expect(dayStart8(d - 1)).toBe(d - 86_400_000)
    expect(dayStart8(d + 23 * HOUR)).toBe(d)
    expect(new Date(dayStart8(T0) + 8 * HOUR).getUTCHours()).toBe(0)
  })
  it('本根 / 近 1 小时 / 今日：窗口边界各自算', () => {
    const s = 'SOLUSDT', midnight = Date.UTC(2026, 9, 7, 16, 0, 0)
    const now = midnight + 90 * 60_000   // 北京时间 01:30
    cover(s, midnight - 10 * 60_000, now)
    trade(s, midnight - 60_000, 900_000, true)          // 昨天：都不算
    trade(s, midnight + 5 * 60_000, 100_000, true)      // 今日，不在近 1 小时
    trade(s, now - 30 * 60_000, 200_000, false)         // 近 1 小时
    trade(s, now - 20_000, 300_000, true)               // 本根（5 分钟）
    const w = windows(flowOf(s), now - 5 * 60_000, now, now)
    expect(w.bar).toMatchObject({ bb: 300_000, bs: 0, bn: 1 })
    expect(w.hour).toMatchObject({ bb: 300_000, bs: 200_000 })
    expect(w.today).toMatchObject({ bb: 400_000, bs: 200_000, bn: 2, sn: 1 })
  })
  it('近 1 小时的现货 / 合约、三家占比只用浏览器记的；一笔都没有给 null', () => {
    const s = 'SOLUSDT', now = T0 + HOUR
    expect(liveShares(flowOf(s), now)).toBeNull()
    trade(s, now - 2 * HOUR, 999_999, true)                                // 一小时之前
    trade(s, now - 10 * 60_000, 100_000, true, { ex: 'coinbase', product: 'spot' })
    trade(s, now - 5 * 60_000, 300_000, false, { ex: 'okx' })
    const sh = liveShares(flowOf(s), now)!
    expect(sh.total).toBe(400_000); expect(sh.spot).toBe(100_000); expect(sh.contract).toBe(300_000)
    expect(sh.ex).toEqual([0, 300_000, 100_000])
  })
})

describe('抽屉 · 价位', () => {
  it('浏览器在记的分钟：逐笔真实价按步长桶并，买卖各取金额最大的 3 档', () => {
    const s = 'SOLUSDT', now = T0 + HOUR
    cover(s, now - HOUR, now)
    trade(s, now - 2 * HOUR, 9e6, true, { price: 150 })
    const px = [100.1, 100.4, 101.2, 102.9, 103, 104, 99]
    px.forEach((p, i) => trade(s, now - 1000 * (i + 1), 100_000 * (i + 1), true, { price: p }))
    trade(s, now - 500, 50_000, false, { price: 98.7 })
    const { buy, sell } = priceLevels(flowOf(s), 1, now, null)
    expect(buy.map(l => l.price)).toEqual([99, 104, 103])
    expect(buy).toHaveLength(3)
    expect(sell).toEqual([{ price: 98, usd: 50_000, n: 1 }])
    const both = priceLevels(flowOf(s), 1, now, null, 10).buy.find(l => l.price === 100)!
    expect(both.usd).toBe(300_000); expect(both.n).toBe(2)
  })
  it('浏览器没在记的分钟：服务端的大买 / 大卖记在那分钟 1 分钟 K 线的典型价上；取不到 K 线就不算', () => {
    const s = 'BTCUSDT', f = flowOf(s), now = T0 + HOUR + 30_000
    const cur = Math.floor(now / 60_000) * 60_000, oldest = cur - (PX_MINUTES - 1) * 60_000
    f.srv.tracked = true; f.srv.lo = oldest - 10 * 60_000; f.srv.hi = cur - 5 * 60_000
    f.srv.rows.set(oldest - 60_000, [9e6, 0, 0, 0])           // 窗口外
    f.srv.rows.set(oldest, [400_000, 100_000, 0, 0])
    f.srv.rows.set(cur - 20 * 60_000, [300_000, 0, 0, 0])
    f.srv.rows.set(cur - 10 * 60_000, [0, 700_000, 0, 0])
    f.srv.rows.set(cur - 6 * 60_000, [5e6, 0, 0, 0])            // 这分钟浏览器也在记：用浏览器的
    cover(s, cur - 6 * 60_000, now)
    trade(s, cur - 6 * 60_000 + 10, 200_000, true, { price: 207.4 })
    trade(s, cur - 60_000 + 10, 250_000, false, { price: 199.2 })
    const typ = new Map([[oldest, 200.6], [cur - 20 * 60_000, 205.2], [cur - 10 * 60_000, 198.9]])
    const r = priceLevels(f, 1, now, m => typ.get(m) ?? null)
    expect(r.buy).toEqual([{ price: 200, usd: 400_000, n: 0 }, { price: 205, usd: 300_000, n: 0 }, { price: 207, usd: 200_000, n: 1 }])
    expect(r.sell).toEqual([{ price: 198, usd: 700_000, n: 0 }, { price: 199, usd: 250_000, n: 1 }, { price: 200, usd: 100_000, n: 0 }])
    // 没有 1 分钟 K 线：服务端那几分钟没有价，不进价位（不瞎猜）
    const bare = priceLevels(f, 1, now, null)
    expect(bare.buy).toEqual([{ price: 207, usd: 200_000, n: 1 }])
    expect(bare.sell).toEqual([{ price: 199, usd: 250_000, n: 1 }])
  })
  it('最近的墙：只看还挂着的，现价上方最近的卖墙、下方最近的买墙，同一价位桶几家合计', () => {
    const o = (side: 'bid' | 'ask', price: number, notional: number, bucket: number, status = 'live', first = 1): BigOrder =>
      ({ side, price, notional, bucket, status, firstSeenMs: first } as unknown as BigOrder)
    const w = nearestWalls([
      o('ask', 105, 1e6, 105), o('ask', 102, 2e6, 102), o('ask', 102, 1e6, 102, 'live', 0), o('ask', 101, 9e6, 101, 'gone'),
      o('bid', 95, 3e6, 95), o('bid', 98, 1e6, 98), o('bid', 103, 1e6, 103),
    ], 100)
    expect(w.ask).toMatchObject({ price: 102, usd: 3e6, n: 2, since: 0 })
    expect(w.bid).toMatchObject({ price: 98, usd: 1e6 })
    expect(nearestWalls([], 100)).toEqual({ ask: null, bid: null })
  })
})

describe('抽屉 · 画法', () => {
  it('开方比例尺：今日是本根的 100 倍时本根还有十分之一长；超出比例按满算', async () => {
    const { sqrtLen } = await import('../src/orderflow/drawer')
    expect(sqrtLen(100, 10_000, 80)).toBeCloseTo(8)
    expect(sqrtLen(10_000, 10_000, 80)).toBe(80)
    expect(sqrtLen(20_000, 10_000, 80)).toBe(80)
    expect(sqrtLen(0, 10_000, 80)).toBe(0)
  })
  it('对撞条填充：短于条宽是圆角 3 的矮矩形（最矮 4），长过条宽才是圆头；没数不画', async () => {
    const { fillLen, fillRadius } = await import('../src/orderflow/drawer')
    expect(fillLen(1, 10_000, 80)).toBe(4)                // 0.8 px 托到 4
    expect(fillLen(100, 10_000, 80)).toBeCloseTo(8)
    expect(fillLen(0, 10_000, 80)).toBe(0)
    expect(fillRadius(8, 26)).toBe(3)
    expect(fillRadius(26, 26)).toBe(3)
    expect(fillRadius(60, 26)).toBe(13)
  })
  it('占比条至少两段才画（100% 一段什么也没说）', async () => {
    const { splitWorth } = await import('../src/orderflow/drawer')
    expect(splitWorth([{ v: 5 }, { v: 0 }])).toBe(false)
    expect(splitWorth([{ v: 5 }, { v: 1 }, { v: 0 }])).toBe(true)
    expect(splitWorth([])).toBe(false)
  })
  it('价位块：同一档既是买前三又是卖前三并成一行，价位不重复，按价从高到低', async () => {
    const { pxRows } = await import('../src/orderflow/drawer')
    const rows = pxRows([{ price: 115.6, usd: 4.8e6, n: 0 }, { price: 115.2, usd: 7.2e6, n: 0 }, { price: 114.8, usd: 4.8e6, n: 0 }],
      [{ price: 115.6, usd: 7e6, n: 0 }, { price: 115.4, usd: 3.3e6, n: 0 }, { price: 115.2, usd: 3.7e6, n: 0 }])
    expect(rows.map(r => r.price)).toEqual([115.6, 115.4, 115.2, 114.8])
    expect(rows[0]).toEqual({ price: 115.6, buy: 4.8e6, sell: 7e6 })
    expect(rows[1]).toEqual({ price: 115.4, buy: 0, sell: 3.3e6 })
    expect(rows[3]).toEqual({ price: 114.8, buy: 4.8e6, sell: 0 })
    // 分档价有浮点误差（0.1 + 0.2）也算同一档
    expect(pxRows([{ price: 0.1 + 0.2, usd: 1, n: 0 }], [{ price: 0.3, usd: 2, n: 0 }])).toHaveLength(1)
  })
  it('深色判断按主文字亮度：#rgb / #rrggbb / rgb()', async () => {
    const { lum } = await import('../src/orderflow/drawer')
    expect(lum('#131722')).toBeLessThan(0.2)
    expect(lum('#fff')).toBeCloseTo(1)
    expect(lum('rgb(209, 212, 220)')).toBeGreaterThan(0.5)
    expect(lum('rgba(19, 23, 34, 1)')).toBeLessThan(0.2)
  })
  it('十字线所在根：自己的十字线按横坐标取根，别的格子同步来的按时间取根；出了数据两头为 null', async () => {
    const { crossTime } = await import('../src/orderflow/drawer')
    const bars = [{ t: 0 }, { t: 300 }, { t: 600 }]
    const ch = { cross: null as null | { x: number }, extCross: null as number | null, bars, xToIndex: (x: number) => x / 10, indexAt: (t: number) => t / 300 }
    expect(crossTime(ch as never)).toBeNull()
    ch.cross = { x: 14 }; expect(crossTime(ch as never)).toBe(300)
    ch.cross = { x: 60 }; expect(crossTime(ch as never)).toBeNull()
    ch.cross = null; ch.extCross = 610; expect(crossTime(ch as never)).toBe(600)
  })
})

describe('爆仓', () => {
  it('解析：坏行跳过、负数归零、方向与交易所只认 0 / 1', () => {
    const b = parseLiq({ base: 'SOL', tracked: true, rows: [
      [T0, 1000, 2000, 3, 1500, 150.5, 1, 1], 'x', [T0 + 60_000, 'a', 1, 1], [T0 + 120_000, -5, 10, 1, 10, 150, 7, 9], [T0 + 180_000, 1, 2, 3],
    ] })!
    expect(b.base).toBe('SOL'); expect(b.tracked).toBe(true)
    expect(b.rows).toHaveLength(3)
    expect(b.rows[0]).toEqual([T0, 1000, 2000, 3, 1500, 150.5, 1, 1])
    expect(b.rows[1]).toEqual([T0 + 120_000, 0, 10, 1, 10, 150, 0, 0])
    expect(b.rows[2]).toEqual([T0 + 180_000, 1, 2, 3, 0, 0, 0, 0])
    expect(parseLiq(null)).toBeNull(); expect(parseLiq({ rows: 3 })).toBeNull()
  })
  it('合计：区间 [a, b) 按分钟，最大一笔跟着最大的那行', () => {
    const rows: LiqRow[] = [[T0, 100, 0, 1, 100, 1, 0, 0], [T0 + 60_000, 0, 500, 2, 400, 2, 1, 1], [T0 + 120_000, 50, 50, 2, 30, 3, 0, 0]]
    const s = sumLiq(rows, T0 + 60_000, T0 + 180_000)
    expect(s).toMatchObject({ long: 50, short: 550, n: 4 }); expect(s.max?.[4]).toBe(400)
    expect(sumLiq(rows, T0, T0 + 60_000)).toMatchObject({ long: 100, short: 0, n: 1 })
    expect(sumLiq([], 0, 1)).toEqual({ long: 0, short: 0, n: 0, max: null })
  })
  it('轮询：30 秒一次、增量从最后一行往回两分钟；失败 30 秒后再试；超过 3 天的行丢掉', async () => {
    const urls: string[] = []
    let fail = false
    const store = new LiqStore(async url => {
      urls.push(url)
      if (fail) throw new Error('net')
      return { status: 200, body: { base: 'SOL', tracked: true, rows: [[T0 - LIQ_KEEP_MS - 60_000, 1, 1, 1], [T0 - 60_000, 10, 20, 2, 15, 150, 1, 0]] } }
    })
    let hits = 0
    store.onUpdate = () => { hits++ }
    store.ensure('SOL', T0); await Promise.resolve(); await Promise.resolve()
    expect(urls).toHaveLength(1)
    expect(urls[0]).toBe(`/v1/market/orderflow/liq?base=SOL&from=${T0 - LIQ_KEEP_MS}&to=${T0}`)
    expect(hits).toBe(1)
    expect([...store.state('SOL')!.rows.keys()]).toEqual([T0 - 60_000])
    store.ensure('SOL', T0 + LIQ_POLL_MS - 1); await Promise.resolve()
    expect(urls).toHaveLength(1)
    fail = true
    store.ensure('SOL', T0 + LIQ_POLL_MS); await Promise.resolve(); await Promise.resolve()
    expect(urls).toHaveLength(2)
    expect(urls[1]).toContain(`from=${T0 - 60_000 - 120_000}&`)
    store.ensure('SOL', T0 + LIQ_POLL_MS + 1000); await Promise.resolve()
    expect(urls).toHaveLength(2)
    store.ensure('SOL', T0 + 2 * LIQ_POLL_MS); await Promise.resolve()
    expect(urls).toHaveLength(3)
    expect(hits).toBe(1)
  })
  it('没数据：tracked=false、没有行；最多记 16 只，按最近看过的淘汰', async () => {
    const store = new LiqStore(async () => ({ status: 200, body: { base: 'X', tracked: false, rows: [] } }))
    store.ensure('AAA', T0); await Promise.resolve(); await Promise.resolve()
    expect(store.state('AAA')).toMatchObject({ tracked: false }); expect(store.state('AAA')!.rows.size).toBe(0)
    for (let i = 0; i < LIQ_MAX_SYMBOLS + 4; i++) store.ensure(`B${i}`, T0 + 1 + i)
    expect(store.size()).toBe(LIQ_MAX_SYMBOLS)
    expect(store.state('AAA')).toBeNull()
    const bad = new LiqStore(async () => ({ status: 404, body: null }))
    bad.ensure('SOL', T0); await Promise.resolve(); await Promise.resolve()
    expect(bad.state('SOL')).toMatchObject({ tracked: null, ver: 0 })
  })
})

describe('四个开关互不牵连', () => {
  it('图上订单流、深度梯子、大单列表、热力：开关一个不动别的，也不替用户开抽屉', async () => {
    const mem = new Map<string, string>()
    vi.stubGlobal('localStorage', { getItem: (k: string) => mem.get(k) ?? null, setItem: (k: string, v: string) => { mem.set(k, v) }, removeItem: (k: string) => { mem.delete(k) } })
    const { st } = await import('../src/app/store')
    const { OF } = await import('../src/orderflow/state')
    const { setOrderFlow, toggleHeat } = await import('../src/orderflow/index')
    st.orderFlow = false; st.slots.drawer = false; st.slots.ladder = false; st.slots.widgets = []; OF.prefs.heat = false
    const snap = (): unknown => ({ flow: st.orderFlow, drawer: st.slots.drawer, ladder: st.slots.ladder, widgets: [...st.slots.widgets], heat: OF.prefs.heat })
    setOrderFlow(true)
    expect(snap()).toEqual({ flow: true, drawer: false, ladder: false, widgets: [], heat: false })
    toggleHeat()
    expect(snap()).toEqual({ flow: true, drawer: false, ladder: false, widgets: [], heat: true })
    setOrderFlow(false)
    expect(snap()).toEqual({ flow: false, drawer: false, ladder: false, widgets: [], heat: true })
    st.slots.drawer = true; st.slots.ladder = true
    setOrderFlow(true); setOrderFlow(false)
    expect(snap()).toEqual({ flow: false, drawer: true, ladder: true, widgets: [], heat: true })
    toggleHeat()
    expect(snap()).toEqual({ flow: false, drawer: true, ladder: true, widgets: [], heat: false })
    vi.unstubAllGlobals()
  })
})

