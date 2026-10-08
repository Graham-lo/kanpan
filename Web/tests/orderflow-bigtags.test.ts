/* Hkline Web · 主力订单流 2026-10-08：图上大单与爆仓气泡、底部抽屉四块摘要、爆仓数据、四个开关互不牵连
 * 气泡（规格 docs/design/大单爆仓气泡-三端规格-2026-10-08.md）：两级金额线（最近 300 根 max(U, D) 的 P90 / P97，垫绝对下限，数据不变不重算）、
 *     U = 大买 + 空爆 / D = 大卖 + 多爆、一屏最多 6 枚泡、同侧错层、出窗格退成点、根宽不到 4 只画点、躲图例与画线文字；
 *     数据：分钟桶并根、服务端历史接缝、爆仓分钟行按根并；
 * 抽屉：北京时间零点、三窗口、现货 / 合约与三家占比、价位（浏览器真实价 + 服务端行 × 1 分钟典型价）、最近的墙、
 *     开方比例尺、占比条至少两段、十字线所在根；爆仓：解析、合计、30 秒轮询与失败重试、只留 16 只。 */
import { afterEach, describe, expect, it, vi } from 'vitest'
import { flowOf, recordTrade, beat, resetFlows } from '../src/chart/tradeFlow'
import type { TradeEvent } from '../src/orderflow/feed'
import { barBig, BigBarCache, LevelCache, planBubbles, levelOf, levelsFrom, udOf, quantile, unitFor, ivName, dotRadius, bubbleText, stemEnd, TIER_BARS, BUBBLE, type BubbleEnv, type BubbleIn, type Levels, type LiqBars, type Rect } from '../src/orderflow/bigTags'
import { dayStart8, dayStartUtc, windows, liveShares, priceLevels, nearestWalls, HOUR, PX_MINUTES } from '../src/orderflow/summary'
import { parseLiq, sumLiq, LiqStore, LiqBarCache, noLiq, LIQ_POLL_MS, LIQ_MAX_SYMBOLS, LIQ_KEEP_MS, type LiqRow } from '../src/orderflow/liquidation'
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

describe('两级金额线', () => {
  it('点线 / 泡线：不到点线不画、过点线画点、过泡线画泡；没有金额线一律不画', () => {
    const k: Levels = { dot: 100_000, bubble: 300_000 }
    expect(levelOf(99_999, k)).toBe(0)
    expect(levelOf(100_000, k)).toBe(1)
    expect(levelOf(299_999, k)).toBe(1)
    expect(levelOf(300_000, k)).toBe(2)
    expect(levelOf(5e9, k)).toBe(2)
    expect(levelOf(5, null)).toBe(0)
    expect(levelOf(0, k)).toBe(0)
  })
  it('分位数线性插值（同 numpy 默认）', () => {
    expect(quantile([1, 2, 3, 4, 5], 0.5)).toBe(3)
    expect(quantile([0, 10], 0.85)).toBeCloseTo(8.5)
    expect(quantile([7], 0.99)).toBe(7)
    expect(quantile([], 0.5)).toBe(0)
  })
  it('P90 / P97，只看非零的根；绝对下限垫底（两级同一个下限），泡线不低于点线', () => {
    const vals = Array.from({ length: 100 }, (_, i) => (i + 1) * 1000).concat([0, 0, 0])   // 1K..100K + 三根没数
    const k = levelsFrom(vals, 0)!
    expect(k.dot).toBeCloseTo(90_100); expect(k.bubble).toBeCloseTo(97_030)
    // 一屏 100 根里过点线的 10 根、过泡线的 3 根
    expect(vals.filter(v => v >= k.dot).length).toBe(10)
    expect(vals.filter(v => v >= k.bubble).length).toBe(3)
    expect(levelsFrom(vals, 200_000)).toEqual({ dot: 200_000, bubble: 200_000 })
    const mid = levelsFrom(vals, 95_000)!
    expect(mid.dot).toBe(95_000); expect(mid.bubble).toBeCloseTo(97_030)
    expect(levelsFrom([0, 0], 1)).toBeNull()
  })
  it('缓存：取最近 300 根；数据版本（缓存代数 / 最后一根 / 下限 / 爆仓版本）不变就不重算', () => {
    const s = 'SOLUSDT', f = flowOf(s), c = new BigBarCache(), lc = new LevelCache()
    const N = 400, now = T0 + N * 60_000
    cover(s, T0, now)
    for (let k = 0; k < N; k++) trade(s, T0 + k * 60_000 + 5, 100_000 + (k < N - TIER_BARS ? 9e7 : k * 1000), true)
    const bars = Array.from({ length: N }, (_, k) => ({ t: T0 + k * 60_000 }))
    const ch = { bars, timeAt: (i: number) => T0 + i * 60_000 }
    c.begin(f, 'SOLUSDT|60000', now)
    const k1 = lc.get(c, f, ch, now, 0)!
    expect(lc.computed).toBe(1)
    // 最早那 100 根（9 千万）不在最近 300 根里，不进分布
    expect(k1.bubble).toBeLessThan(9e7)
    expect(lc.get(c, f, ch, now, 0)).toBe(k1)
    expect(lc.computed).toBe(1)
    f.srv.ver++; c.begin(f, 'SOLUSDT|60000', now)
    lc.get(c, f, ch, now, 0)
    expect(lc.computed).toBe(2)
    lc.get(c, f, ch, now, 500_000)   // 下限变了也重算
    expect(lc.computed).toBe(3)
    const liq: LiqBars = { key: 'a', at: () => null }
    lc.get(c, f, ch, now, 500_000, liq); expect(lc.computed).toBe(4)   // 爆仓版本变了重算
    lc.get(c, f, ch, now, 500_000, liq); expect(lc.computed).toBe(4)
  })
  it('分布按每根 max(U, D) 算（和过线比的同一口径）：买卖两边相近的粗周期也有泡', () => {
    const s = 'SOLUSDT', f = flowOf(s), c = new BigBarCache(), lc = new LevelCache()
    const IV = 3_600_000, N = 20, now = T0 + N * IV
    cover(s, T0, now)
    // 20 根 1 小时：每根买 (k+1)×100 万、卖同样多（两边相近）
    for (let k = 0; k < N; k++) { trade(s, T0 + k * IV + 5, (k + 1) * 1_000_000, true); trade(s, T0 + k * IV + 6, (k + 1) * 1_000_000, false) }
    const bars = Array.from({ length: N }, (_, k) => ({ t: T0 + k * IV }))
    const ch = { bars, timeAt: (i: number) => T0 + i * IV }
    c.begin(f, `SOLUSDT|${IV}`, now)
    const k = lc.get(c, f, ch, now, 0)!
    // 线落在单边的分布上（P90 = 1810 万），最大的两根过线；按合计定线单边一根都过不了
    expect(k.dot).toBeCloseTo(18_100_000)
    const over = bars.filter((b, i) => { const d = c.get(f, b.t, ch.timeAt(i + 1), now)!; return Math.max(d.bb, d.bs) >= k.dot })
    expect(over.length).toBe(2)
  })
  it('爆仓也进分布：只有爆仓的根照样算一根（U / D 合并后的 max）', () => {
    const s = 'ETHUSDT', f = flowOf(s), c = new BigBarCache(), lc = new LevelCache()
    const N = 10, now = T0 + N * 60_000
    cover(s, T0, now)
    trade(s, T0 + 5, 100_000, true)   // 只有第 0 根有大单
    const bars = Array.from({ length: N }, (_, k) => ({ t: T0 + k * 60_000 }))
    const ch = { bars, timeAt: (i: number) => T0 + i * 60_000 }
    c.begin(f, 'ETHUSDT|60000', now)
    const without = lc.get(c, f, ch, now, 0)!
    expect(without).toEqual({ dot: 100_000, bubble: 100_000 })
    // 每根都有 5 万空爆（向上），第 9 根 9 百万多爆（向下）
    const liq: LiqBars = { key: 'x', at: t0 => ({ long: t0 === T0 + 9 * 60_000 ? 9e6 : 0, short: 50_000 }) }
    const withLiq = lc.get(c, f, ch, now, 0, liq)!
    // 样本：第 0 根 15 万、1..8 根 5 万、第 9 根 900 万
    expect(withLiq.bubble).toBeGreaterThan(150_000)
    expect(withLiq.dot).toBeCloseTo(quantile([50_000, 50_000, 50_000, 50_000, 50_000, 50_000, 50_000, 50_000, 150_000, 9e6], 0.9))
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

describe('U / D 与爆仓并根', () => {
  it('U = 大买 + 空爆，D = 大卖 + 多爆；缺哪样算 0', () => {
    expect(udOf({ bb: 100, bs: 20 }, { long: 7, short: 3 })).toEqual({ up: 103, down: 27 })
    expect(udOf({ bb: 100, bs: 20 }, null)).toEqual({ up: 100, down: 20 })
    expect(udOf(null, { long: 7, short: 3 })).toEqual({ up: 3, down: 7 })
    expect(udOf(null, null)).toEqual({ up: 0, down: 0 })
  })
  it('分钟行按本图 K 线并成根（多爆 / 空爆），整分钟落在 [t0, t1) 的都算；一行都没有给 null', () => {
    const rows = new Map<number, LiqRow>([
      [T0, [T0, 100, 0, 1, 100, 1, 0, 0]],
      [T0 + 60_000, [T0 + 60_000, 0, 500, 2, 400, 2, 1, 1]],
      [T0 + 300_000, [T0 + 300_000, 50, 60, 2, 30, 3, 0, 0]],
    ])
    const lc = new LiqBarCache()
    const lb = lc.of({ rows, tracked: true, ver: 1 }, 'SOL', 300_000)!
    expect(lb.at(T0, T0 + 300_000)).toEqual({ long: 100, short: 500 })
    expect(lb.at(T0 + 300_000, T0 + 600_000)).toEqual({ long: 50, short: 60 })
    expect(lb.at(T0 + 600_000, T0 + 900_000)).toBeNull()
    expect(lb.at(T0 - 300_000, T0)).toBeNull()
    // 算过的根不再算；数据版本不变复用同一份
    const n = lc.computed
    lb.at(T0, T0 + 300_000); expect(lc.computed).toBe(n)
    expect(lc.of({ rows, tracked: true, ver: 1 }, 'SOL', 300_000)).toBe(lb)
    const lb2 = lc.of({ rows, tracked: true, ver: 2 }, 'SOL', 300_000)!
    expect(lb2).not.toBe(lb); expect(lb2.key).not.toBe(lb.key)
  })
  it('秒级周期、还没拉到、没有行：不并（null）', () => {
    const rows = new Map<number, LiqRow>([[T0, [T0, 1, 1, 1, 1, 1, 0, 0]]])
    const lc = new LiqBarCache()
    expect(lc.of({ rows, tracked: true, ver: 1 }, 'SOL', 15_000)).toBeNull()
    expect(lc.of(null, 'SOL', 60_000)).toBeNull()
    expect(lc.of({ rows: new Map(), tracked: false, ver: 1 }, 'SOL', 60_000)).toBeNull()
  })
  it('没有爆仓项的品种：Coinbase 现货（X-USD）与 DXY', () => {
    expect(noLiq('BTC-USD')).toBe(true)
    expect(noLiq('DXY')).toBe(true)
    expect(noLiq('BTCUSDT')).toBe(false)
    expect(noLiq('BTCUSD_PERP')).toBe(false)
  })
})

describe('气泡摆放', () => {
  const K: Levels = { dot: 100_000, bubble: 300_000 }
  const env = (o: Partial<BubbleEnv> = {}): BubbleEnv => ({
    levels: K, bw: 8, top: 0, bottom: 400, plotW: 800, avoid: [],
    measure: t => t.length * 6, text: u => `${Math.round(u / 1000)}K`, ...o,
  })
  const bar = (o: { i?: number; x?: number; hi?: number; lo?: number; up: number; down: number }): BubbleIn => {
    const i = o.i ?? 0
    return { i, t: i * 60_000, x: o.x ?? 100, yHigh: o.hi ?? 100, yLow: o.lo ?? 200, up: o.up, down: o.down }
  }
  const circleRect = (x: number, y: number, r: number, a: Rect): boolean => {
    const cx = Math.max(a.x, Math.min(x, a.x + a.w)), cy = Math.max(a.y, Math.min(y, a.y + a.h))
    return Math.hypot(x - cx, y - cy) < r
  }

  it('一根上下各至多一枚：U 挂最高价之上（泡：柄 4）、D 挂最低价之下（点：柄 2、半径 clamp(bw×0.4, 1.5, 2.8)）', () => {
    const out = planBubbles([bar({ up: 500_000, down: 150_000 })], env())
    expect(out).toHaveLength(2)
    const [u, d] = out
    expect(u).toMatchObject({ side: 'up', bubble: true, text: '500K', anchor: 100, x: 100, usd: 500_000 })
    // r = max(11 + 6 × min(1, (500K − 300K) / 600K), 字宽 24 / 2 + 4) = 16
    expect(u.r).toBe(16); expect(u.cy).toBe(100 - 4 - 16)
    expect(stemEnd(u)).toBe(96)
    expect(d).toMatchObject({ side: 'down', bubble: false, text: '', anchor: 200 })
    expect(d.r).toBeCloseTo(2.8); expect(d.cy).toBeCloseTo(200 + 2 + 2.8)
    expect(dotRadius(2)).toBe(1.5); expect(dotRadius(5)).toBe(2); expect(dotRadius(20)).toBe(2.8)
  })
  it('泡的半径随金额长到 17 封顶；字宽撑大优先', () => {
    const big = planBubbles([bar({ up: 5e6, down: 0 })], env({ measure: () => 4 }))[0]
    expect(big.r).toBe(BUBBLE.r0 + BUBBLE.rGrow)
    const at = planBubbles([bar({ up: 300_000, down: 0 })], env({ measure: () => 4 }))[0]
    expect(at.r).toBe(BUBBLE.r0)
    const wide = planBubbles([bar({ up: 300_000, down: 0 })], env({ measure: () => 40 }))[0]
    expect(wide.r).toBe(24)
  })
  it('泡里的字去掉末尾 M（1.2M → 1.2），K / B 留着', () => {
    expect(bubbleText('1.2M')).toBe('1.2'); expect(bubbleText('860K')).toBe('860K'); expect(bubbleText('1.1B')).toBe('1.1B')
    const [b] = planBubbles([bar({ up: 1.2e6, down: 0 })], env({ text: () => '1.2M' }))
    expect(b.text).toBe('1.2')
  })
  it('不到点线不画；没有金额线不画；输出按根序、同根上侧在前', () => {
    expect(planBubbles([bar({ up: 99_000, down: 90_000 })], env())).toEqual([])
    expect(planBubbles([bar({ up: 5e6, down: 5e6 })], env({ levels: null }))).toEqual([])
    const out = planBubbles([bar({ i: 3, x: 300, up: 0, down: 2e6 }), bar({ i: 1, x: 100, up: 2e5, down: 4e5 })], env())
    expect(out.map(b => `${b.i}${b.side}`)).toEqual(['1up', '1down', '3down'])
  })
  it('一屏带字的泡最多 6 枚：金额大的先占位，其余退成点', () => {
    const list = Array.from({ length: 10 }, (_, i) => bar({ i, x: 40 + i * 70, up: 1e6 + i * 1000, down: 0 }))
    const out = planBubbles(list, env())
    expect(out).toHaveLength(10)
    expect(out.filter(b => b.bubble).map(b => b.i)).toEqual([4, 5, 6, 7, 8, 9])
    expect(out.filter(b => !b.bubble).every(b => b.text === '' && b.r === dotRadius(8))).toBe(true)
  })
  it('根宽不到 4：全部只画点', () => {
    const out = planBubbles([bar({ up: 5e6, down: 5e6 })], env({ bw: 3.9 }))
    expect(out).toHaveLength(2)
    expect(out.every(b => !b.bubble)).toBe(true)
    expect(out[0].r).toBe(1.56)
  })
  it('同侧错层：挨着的两根往外推一层（大的先占贴近的位置），两枚不相交', () => {
    const out = planBubbles([bar({ i: 0, x: 100, up: 1e6, down: 0 }), bar({ i: 1, x: 108, up: 2e6, down: 0 })], env())
    const a = out.find(b => b.i === 1)!, b = out.find(b => b.i === 0)!
    expect(a.cy).toBe(100 - 4 - a.r)                // 大的贴着最高价
    expect(b.cy).toBe(a.cy - a.r - b.r - 2)          // 小的往上推一层
    expect(Math.hypot(a.x - b.x, a.cy - b.cy)).toBeGreaterThanOrEqual(a.r + b.r + 2 - 1e-9)
    // 下侧同理往下推
    const dn = planBubbles([bar({ i: 0, x: 100, up: 0, down: 1e6 }), bar({ i: 1, x: 108, up: 0, down: 2e6 })], env())
    expect(dn[0].cy).toBe(dn[1].cy + dn[1].r + dn[0].r + 2)
    // 上下两侧互不推
    const both = planBubbles([bar({ i: 0, x: 100, up: 1e6, down: 1e6 })], env())
    expect(both[0].cy).toBe(100 - 4 - both[0].r); expect(both[1].cy).toBe(200 + 4 + both[1].r)
  })
  it('推出窗格就退成点（不占 6 枚配额）；点也出窗格就不画', () => {
    // 最大那根的最高价贴着顶：泡放不下 → 点；其余 6 根照样都是泡
    const list = [bar({ i: 0, x: 40, hi: 20, up: 9e6, down: 0 }), ...Array.from({ length: 6 }, (_, k) => bar({ i: k + 1, x: 120 + k * 80, up: 1e6, down: 0 }))]
    const out = planBubbles(list, env())
    const top = out.find(b => b.i === 0)!
    expect(top).toMatchObject({ bubble: false, text: '' })
    expect(top.cy).toBeCloseTo(20 - 2 - 2.8)
    expect(out.filter(b => b.bubble)).toHaveLength(6)
    // 下沿同理（bottom 让开成交量那一截）
    const low = planBubbles([bar({ lo: 380, up: 0, down: 2e6 })], env())[0]
    expect(low).toMatchObject({ bubble: false }); expect(low.cy + low.r).toBeLessThanOrEqual(400)
    // 最高价已经在窗格顶上：点也放不下
    expect(planBubbles([bar({ hi: 2, up: 2e6, down: 0 })], env())).toEqual([])
  })
  it('横向：根中心在价格轴外的不画；泡右沿出界退成点', () => {
    expect(planBubbles([bar({ x: -10, up: 2e6, down: 0 }), bar({ i: 1, x: 812, up: 2e6, down: 0 })], env())).toEqual([])
    const [edge] = planBubbles([bar({ x: 796, up: 2e6, down: 0 })], env())
    expect(edge.bubble).toBe(false)
  })
  it('躲图例 / 画线文字：泡被推到字外面；推不开退成点；点压字不画', () => {
    const [p] = planBubbles([bar({ up: 2e6, down: 0 })], env({ avoid: [{ x: 0, y: 70, w: 300, h: 20 }] }))
    expect(p.bubble).toBe(true)
    expect(p.cy + p.r).toBeLessThanOrEqual(70)
    // 字一直铺到顶：推不开 → 点（点在字下面 96 附近，不压字）
    const [q] = planBubbles([bar({ up: 2e6, down: 0 })], env({ avoid: [{ x: 0, y: 0, w: 300, h: 92 }] }))
    expect(q.bubble).toBe(false)
    expect(planBubbles([bar({ up: 2e6, down: 0 })], env({ avoid: [{ x: 0, y: 0, w: 300, h: 99 }] }))).toEqual([])
  })
  it('随机 200 屏：泡不压字、不出窗格、每屏至多 6 枚；点不压字', () => {
    let seed = 42
    const rnd = (lo: number, hi: number) => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return lo + (hi - lo) * (seed / 0x7fffffff) }
    let total = 0, nb = 0
    for (let k = 0; k < 200; k++) {
      const avoid: Rect[] = Array.from({ length: 4 }, () => ({ x: rnd(0, 700), y: rnd(24, 380), w: rnd(20, 120), h: rnd(12, 20) }))
      const list = Array.from({ length: 80 }, (_, i) => { const hi = rnd(30, 300); return bar({ i, x: 4 + i * 9.5, hi, lo: hi + rnd(2, 80), up: rnd(0, 3e6), down: rnd(0, 3e6) }) })
      const out = planBubbles(list, env({ bw: 9.5, avoid, top: 24 }))
      total += out.length
      const bubbles = out.filter(b => b.bubble)
      nb += bubbles.length
      expect(bubbles.length).toBeLessThanOrEqual(BUBBLE.cap)
      for (const b of out) {
        for (const a of avoid) expect(circleRect(b.x, b.cy, b.r, a)).toBe(false)
        expect(b.cy - b.r).toBeGreaterThanOrEqual(24 - 1e-9); expect(b.cy + b.r).toBeLessThanOrEqual(400 + 1e-9)
        if (b.bubble) { expect(b.cy - b.r).toBeGreaterThanOrEqual(24 + BUBBLE.edge - 1e-9); expect(b.x - b.r).toBeGreaterThanOrEqual(0); expect(b.x + b.r).toBeLessThanOrEqual(800) }
      }
    }
    expect(total).toBeGreaterThan(1000)
    expect(nb).toBeGreaterThan(600)
  })
})

describe('一根的大单合计', () => {
  it('浏览器的分钟桶按根并：金额、笔数、最大一笔、现货与五家', () => {
    const s = 'SOLUSDT'
    cover(s, T0, T0 + 5 * 60_000)
    trade(s, T0 + 10_000, 120_000, true, { ex: 'okx', product: 'spot', price: 101 })
    trade(s, T0 + 70_000, 300_000, true, { price: 102 })
    trade(s, T0 + 200_000, 50_000, false, { ex: 'coinbase', product: 'spot' })
    trade(s, T0 + 200_000, 5_000, false)   // 不到大单线，不算
    trade(s, T0 + 210_000, 80_000, true, { ex: 'bybit' })
    trade(s, T0 + 220_000, 60_000, false, { ex: 'hyperliquid' })
    const b = barBig(flowOf(s), T0, T0 + 5 * 60_000, T0 + 5 * 60_000)!
    expect(b.bb).toBe(500_000); expect(b.bs).toBe(110_000)
    expect(b.bn).toBe(3); expect(b.sn).toBe(2)
    expect(b.bmax?.usd).toBe(300_000); expect(b.bmax?.price).toBe(102)
    expect(b.spot).toBe(170_000)
    expect(b.ex).toEqual([300_000, 120_000, 50_000, 80_000, 60_000])
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
    // 服务端在跟、历史里这分钟没大单 → 这根没有大单
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
  it('「今日」从北京时间 8 点（UTC 0 点）起：7:59 还算昨天', () => {
    const d = Date.UTC(2026, 9, 8, 0, 0, 0)
    expect(dayStartUtc(d)).toBe(d)
    expect(dayStartUtc(d - 1)).toBe(d - 86_400_000)
    expect(dayStartUtc(d + 23 * HOUR)).toBe(d)
  })
  it('本根 / 近 1 小时 / 今日：窗口边界各自算', () => {
    const s = 'SOLUSDT', midnight = Date.UTC(2026, 9, 8, 0, 0, 0)
    const now = midnight + 90 * 60_000   // 北京时间 09:30
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
  it('近 1 小时的现货 / 合约、五家占比只用浏览器记的；一笔都没有给 null', () => {
    const s = 'SOLUSDT', now = T0 + HOUR
    expect(liveShares(flowOf(s), now)).toBeNull()
    trade(s, now - 2 * HOUR, 999_999, true)                                // 一小时之前
    trade(s, now - 10 * 60_000, 100_000, true, { ex: 'coinbase', product: 'spot' })
    trade(s, now - 5 * 60_000, 300_000, false, { ex: 'okx' })
    trade(s, now - 4 * 60_000, 50_000, true, { ex: 'bybit', product: 'spot' })
    trade(s, now - 3 * 60_000, 70_000, false, { ex: 'hyperliquid' })
    const sh = liveShares(flowOf(s), now)!
    expect(sh.total).toBe(520_000); expect(sh.spot).toBe(150_000); expect(sh.contract).toBe(370_000)
    expect(sh.ex).toEqual([0, 300_000, 100_000, 50_000, 70_000])
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

describe('抽屉 · 十字线', () => {
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

