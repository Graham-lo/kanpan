/* 底部抽屉「大单列表」（2026-10-08 改版）的纯计算：对撞条字摆放、价位竖轴、爆仓 15 分钟分桶、只有历史时的「—」、累计净额点位 */
import { describe, expect, it } from 'vitest'
import {
  barText, bfHtml, placeAxis, liqBuckets, pickBucket, bucketCount, LIQ_BUCKETS, NET_BUCKETS, histFmt, srcHtml, pct, signed, tone,
  cumPoints, cumSvg, hourTicks, ivShort, levelsSvg, maxOf, hoverCardHtml,
} from '../src/orderflow/drawerView'
import type { LiqRow } from '../src/orderflow/liquidation'
import type { BarBig } from '../src/orderflow/bigTags'

const MIN = 60_000, HOUR = 3_600_000
const tw = (t: string): number => t.length * 7

describe('对撞条 · 字摆放', () => {
  it('条比字长：字在条里，不挪', () => expect(barText(80, 40, 100)).toEqual({ bar: 80, shift: 0 }))
  it('条比字短、条外放得下：字挪到条外（shift = 条长）', () => expect(barText(10, 40, 100)).toEqual({ bar: 10, shift: 10 }))
  it('条外放不下：条撑到字宽 + 4，字仍在条里，且不超过半边', () => {
    expect(barText(30, 40, 60)).toEqual({ bar: 44, shift: 0 })
    expect(barText(30, 70, 60)).toEqual({ bar: 60, shift: 0 })
  })
  it('没量：条长 0，字不挪', () => expect(barText(0, 40, 100)).toEqual({ bar: 0, shift: 0 }))
  it('bfHtml：左卖右买，0 那边写灰色 0；挪到条外时带 margin', () => {
    const h = bfHtml({ s: 0, b: 2e6, max: 2e6, half: 100, tw })
    expect(h).toContain('<div class="h s"><i style="width:0.0px"></i><span class="num z"')
    expect(h).toMatch(/<div class="h b"><i style="width:100\.0px"><\/i><span class="num">2(\.0+)?M<\/span>/)
    const small = bfHtml({ s: 1e5, b: 1e7, max: 1e7, half: 200, tw })
    expect(small).toMatch(/h s"><i style="width:2\.0px"><\/i><span class="num" style="margin-right:2\.0px">/)
  })
})

describe('价位 · 竖轴', () => {
  it('按真实价摆：价高在上，间距成比例', () => {
    const y = placeAxis([{ p: 110, hh: 10 }, { p: 100, hh: 10 }, { p: 90, hh: 10 }], 200)
    expect(y[0]).toBeCloseTo(9); expect(y[2]).toBeCloseTo(191); expect(y[1]).toBeCloseTo(100)
  })
  it('挤了互相让开：相邻两项至少隔 (h1 + h2) / 2 + 2；入参顺序随意，输出按入参同序', () => {
    const items = [{ p: 100, hh: 16 }, { p: 100.01, hh: 12 }, { p: 99.99, hh: 12 }, { p: 50, hh: 16 }]
    const y = placeAxis(items, 200)
    expect(y[1]).toBeLessThan(y[0]); expect(y[0]).toBeLessThan(y[2])
    expect(y[0] - y[1]).toBeGreaterThanOrEqual(16 - 1e-9)
    expect(y[2] - y[0]).toBeGreaterThanOrEqual(16 - 1e-9)
    expect(y[3]).toBeCloseTo(191)
  })
  it('一堆挤到底：整列往上推，最下一项不越过 h − pad', () => {
    const items = [{ p: 100, hh: 16 }, ...[1, 2, 3, 4, 5].map(i => ({ p: 10 - i * 0.001, hh: 16 }))]
    const y = placeAxis(items, 120)
    expect(Math.max(...y)).toBeLessThanOrEqual(111 + 1e-9)
    const s = [...y].sort((a, b) => a - b)
    for (let i = 1; i < s.length; i++) expect(s[i] - s[i - 1]).toBeGreaterThanOrEqual(18 - 1e-9)
  })
  it('只有一项 / 价全相同不出 NaN', () => {
    expect(placeAxis([{ p: 5, hh: 10 }], 100).every(Number.isFinite)).toBe(true)
    expect(placeAxis([{ p: 5, hh: 10 }, { p: 5, hh: 10 }], 100).every(Number.isFinite)).toBe(true)
    expect(placeAxis([], 100)).toEqual([])
  })
  it('levelsSvg：墙给命中区；「N分」与墙的金额撞上时省掉', () => {
    const base = { w: 170, h: 200, sell: [{ price: 101, usd: 2e6 }], buy: [{ price: 99, usd: 1e6 }], cur: 100, fmt: (p: number) => p.toFixed(2), pxCol: 46 }
    const r = levelsSvg({ ...base, ask: { price: 102, usd: 5e6, age: 30 * MIN }, bid: { price: 98, usd: 3e6, age: 5 * MIN } })
    expect(r.hits).toHaveLength(2)
    expect(r.hits[0].ask).toBe(true)
    expect(r.svg).toContain('30分')
    const narrow = levelsSvg({ ...base, w: 120, ask: { price: 102, usd: 5e6, age: 30 * MIN }, bid: null, tw })
    expect(narrow.svg).not.toContain('30分')
    expect(narrow.svg).toContain('卖墙')
  })
})

describe('爆仓 · 分桶', () => {
  const from = Date.UTC(2026, 9, 8)
  const row = (t: number, long: number, short: number): LiqRow => [t, long, short, 1, Math.max(long, short), 100, short > long ? 1 : 0, 0]
  it('今天按 15 分钟一桶：00:14 与 00:00 同桶，00:15 下一桶；今天以前的不算', () => {
    const now = from + 2 * HOUR + 5 * MIN
    const q = liqBuckets([row(from, 10, 0), row(from + 14 * MIN, 5, 2), row(from + 15 * MIN, 0, 7), row(from - MIN, 99, 99), row(from + 2 * HOUR, 1, 1)], from, now, 15 * MIN)
    expect(q).toHaveLength(bucketCount(from, now, 15 * MIN))
    expect(q).toHaveLength(9)
    expect(q[0]).toEqual({ t: from, long: 15, short: 2 })
    expect(q[1]).toEqual({ t: from + 15 * MIN, long: 0, short: 7 })
    expect(q[8]).toEqual({ t: from + 2 * HOUR, long: 1, short: 1 })
  })
  it('窄了自动并桶：每柱至少 4 px', () => {
    const now = from + 23 * HOUR
    expect(pickBucket(from, now, 400, LIQ_BUCKETS, 4)).toBe(15 * MIN)   // 93 桶 × 4 = 372
    expect(pickBucket(from, now, 150, LIQ_BUCKETS, 4)).toBe(HOUR)       // 24 × 4 = 96
    expect(pickBucket(from, now, 10, LIQ_BUCKETS, 4)).toBe(2 * HOUR)    // 放不下取最大
  })
  it('净额分桶不细于 5 分钟（floor）', () => {
    expect(pickBucket(from, from + HOUR, 2000, NET_BUCKETS, 1.5, 5 * MIN)).toBe(5 * MIN)
  })
})

describe('只有历史时的写法', () => {
  it('histFmt：null → —', () => {
    expect(histFmt(null, (v: number) => `${v} 笔`)).toBe('—')
    expect(histFmt(3, (v: number) => `${v} 笔`)).toBe('3 笔')
  })
  it('srcHtml：spot / ex 为 null 时数字全是「—」、条是底轨', () => {
    const h = srcHtml(5e6, null, null)
    expect((h.match(/<b class="num">—<\/b>/g) ?? []).length).toBe(5)
    expect(h).toContain('var(--of-track)')
    const live = srcHtml(100, 25, [50, 30, 20])
    expect(live).toContain('25%'); expect(live).toContain('75%'); expect(live).toContain('50%')
  })
  it('悬停卡：只有历史的根不摆四行「—」，收成一行「历史回填」', () => {
    const d: BarBig = { t: 0, t1: 300_000, bb: 2e6, bs: 1e6, bn: null, sn: null, bmax: null, smax: null, spot: null, ex: null, exact: false } as unknown as BarBig
    const h = hoverCardHtml(d, '10-08 12:30', '5分')
    expect(h).toContain('+1')
    expect(h).toContain('历史回填')
    expect(h).not.toContain('最大一笔'); expect(h).not.toContain('现货'); expect(h).not.toContain('>—<')
  })
  it('pct / signed / tone', () => {
    expect(pct(1, 0)).toBe('—'); expect(pct(1, 3)).toBe('33%')
    expect(signed(0)).toBe('0'); expect(signed(-2e6).startsWith('−')).toBe(true); expect(signed(2e6).startsWith('+')).toBe(true)
    expect(tone(1)).toBe('up'); expect(tone(-1)).toBe('dn'); expect(tone(0)).toBe('t3')
  })
  it('maxOf：买卖两笔取大的，带方向', () => {
    expect(maxOf({ bmax: null, smax: null })).toBeNull()
    const m = maxOf({ bmax: { usd: 5, price: 1, exchange: 'binance' }, smax: { usd: 9, price: 2, exchange: 'okx' } } as never)
    expect(m).toMatchObject({ usd: 9, buy: false, exchange: 'okx' })
  })
})

describe('累计净额 · 点位', () => {
  it('逐桶累加；零线在最大与最小之间；首点 x = 0、末点 x = w − 4', () => {
    const c = cumPoints([10, -30, 40], 104, 0, 100)
    expect(c.last).toBe(20)
    expect(c.max).toBe(20); expect(c.min).toBe(-20)
    expect(c.zero).toBeCloseTo(50)
    expect(c.pts.map(p => p[0])).toEqual([0, 50, 100])
    expect(c.pts[1][1]).toBeCloseTo(100)   // 累计 −20 在最底
    expect(c.pts[2][1]).toBeCloseTo(0)     // 累计 +20 在最顶
  })
  it('全为正：零线贴底', () => {
    const c = cumPoints([1, 1], 50, 4, 40)
    expect(c.zero).toBeCloseTo(44)
  })
  it('cumSvg：空的只画一道虚线，有数画面积 + 线', () => {
    expect(cumSvg({ w: 100, h: 38, nets: [], tall: false })).toContain('stroke-dasharray')
    expect(cumSvg({ w: 100, h: 38, nets: [1, -2, 3], tall: false })).toContain('<path')
  })
  it('整点刻度：间距至少 minPx，标签按北京时间', () => {
    const from = Date.UTC(2026, 9, 8), now = from + 10 * HOUR
    const ticks = hourTicks(from, now, 15 * MIN, 400, t => new Date(t + 8 * HOUR).getUTCHours())
    expect(ticks[0]).toEqual({ i: 0, label: '8:00' })
    const bw = 396 / bucketCount(from, now, 15 * MIN)
    for (let i = 1; i < ticks.length; i++) expect((ticks[i].i - ticks[i - 1].i) * bw).toBeGreaterThanOrEqual(44)
  })
})

describe('周期短名', () => {
  it('秒 / 分 / 时 / 日 / 周 / 月', () => {
    expect(ivShort(1000)).toBe('1秒')
    expect(ivShort(5 * MIN)).toBe('5分')
    expect(ivShort(4 * HOUR)).toBe('4时')
    expect(ivShort(24 * HOUR)).toBe('1日')
    expect(ivShort(7 * 24 * HOUR)).toBe('1周')
    expect(ivShort(30 * 24 * HOUR)).toBe('1月')
  })
})
