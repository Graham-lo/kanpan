/* Hkline Web · 主力订单流 2026-10-08：图上「大单签」、底部抽屉四块摘要、爆仓数据、四个开关互不牵连
 * 签：档位（门槛 ÷ 5 的 1 / 3 / 10 倍）、上下摆放与实心侧、让开 K 线与文字；数据：分钟桶并根、服务端历史接缝；
 * 抽屉：北京时间零点、三窗口、现货 / 合约与三家占比、价位桶、最近的墙；爆仓：解析、合计、30 秒轮询与失败重试、只留 16 只。 */
import { afterEach, describe, expect, it, vi } from 'vitest'
import { flowOf, recordTrade, beat, resetFlows } from '../src/chart/tradeFlow'
import type { TradeEvent } from '../src/orderflow/feed'
import { barBig, BigBarCache, planTags, tierOf, unitFor, ivName, type PlanEnv, type TagIn, type BarBig } from '../src/orderflow/bigTags'
import { dayStart8, windows, liveShares, priceLevels, nearestWalls, HOUR } from '../src/orderflow/summary'
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
  it('门槛 ÷ 5 为单位：不到 1 倍不画、1 倍三角、3 倍金额签、10 倍大签', () => {
    expect(tierOf(99_999, 100_000)).toBe(0)
    expect(tierOf(100_000, 100_000)).toBe(1)
    expect(tierOf(299_999, 100_000)).toBe(1)
    expect(tierOf(300_000, 100_000)).toBe(2)
    expect(tierOf(1_000_000, 100_000)).toBe(3)
    expect(tierOf(5, 0)).toBe(0)
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
    unit: 100_000, spacing: 8, top: 0, bottom: 400, plotW: 800,
    span: () => ({ hiY: 100, loY: 200 }),
    measure: t => t.length * 6, text: u => `${Math.round(u / 1000)}K`, avoid: [], ...o,
  })
  it('买挂最高价上方、卖挂最低价下方；两侧都够格时大的那侧实心、另一侧描边', () => {
    const tags = planTags([{ i: 0, t: 0, x: 100, data: big(500_000, 150_000) }], env())
    const buy = tags.find(t => t.side === 'buy')!, sell = tags.find(t => t.side === 'sell')!
    expect(buy.kind).toBe('tag'); expect(sell.kind).toBe('tri')
    expect(buy.y + buy.h).toBeLessThanOrEqual(100)
    expect(sell.y).toBeGreaterThanOrEqual(200)
    expect(buy.filled).toBe(true); expect(sell.filled).toBe(false)
    const only = planTags([{ i: 0, t: 0, x: 100, data: big(0, 2_000_000) }], env())
    expect(only).toHaveLength(1); expect(only[0].kind).toBe('big'); expect(only[0].filled).toBe(true)
  })
  it('一根太窄就退回三角；签与签不叠，撞上图例往外挪', () => {
    const narrow = planTags([{ i: 0, t: 0, x: 100, data: big(500_000, 0) }], env({ spacing: 2 }))
    expect(narrow[0].kind).toBe('tri')
    const list: TagIn[] = [0, 1, 2].map(i => ({ i, t: i, x: 100 + i * 8, data: big(400_000 + i, 0) }))
    const tags = planTags(list, env())
    for (let a = 0; a < tags.length; a++) for (let b = a + 1; b < tags.length; b++) {
      const p = tags[a], q = tags[b]
      if (p.kind === 'tri' && q.kind === 'tri') continue
      expect(p.x < q.x + q.w && q.x < p.x + p.w && p.y < q.y + q.h && q.y < p.y + p.h).toBe(false)
    }
    const legend = { x: 0, y: 70, w: 300, h: 20 }
    const moved = planTags([{ i: 0, t: 0, x: 100, data: big(500_000, 0) }], env({ avoid: [legend] }))
    expect(moved[0].y + moved[0].h).toBeLessThanOrEqual(legend.y)
  })
  it('放不进图（顶上没地方）就不画，不压出图外', () => {
    const tags = planTags([{ i: 0, t: 0, x: 100, data: big(500_000, 0) }], env({ span: () => ({ hiY: 3, loY: 200 }) }))
    expect(tags).toHaveLength(0)
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
  it('近 1 小时的大单按步长桶并，买卖各取金额最大的 3 档', () => {
    const s = 'SOLUSDT', now = T0 + HOUR
    trade(s, now - 2 * HOUR, 9e6, true, { price: 150 })
    const px = [100.1, 100.4, 101.2, 102.9, 103, 104, 99]
    px.forEach((p, i) => trade(s, now - 1000 * (i + 1), 100_000 * (i + 1), true, { price: p }))
    trade(s, now - 500, 50_000, false, { price: 98.7 })
    const { buy, sell } = priceLevels(flowOf(s), 1, now)
    expect(buy.map(l => l.price)).toEqual([99, 104, 103])
    expect(buy).toHaveLength(3)
    expect(sell).toEqual([{ price: 98, usd: 50_000, n: 1 }])
    const both = priceLevels(flowOf(s), 1, now, 10).buy.find(l => l.price === 100)!
    expect(both.usd).toBe(300_000); expect(both.n).toBe(2)
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

