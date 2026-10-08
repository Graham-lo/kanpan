/* 底部抽屉「大单列表」（2026-10-08 改版）的纯计算：对撞条字摆放、价位竖轴、爆仓 15 分钟分桶、只有历史时的「—」、累计净额点位 */
import { describe, expect, it } from 'vitest'
import {
  barText, bfHtml, placeAxis, liqBuckets, pickBucket, bucketCount, LIQ_BUCKETS, NET_BUCKETS, histFmt, srcHtml, pct, signed, tone,
  cumPoints, cumSvg, hourTicks, ivShort, levelsSvg, maxOf, hoverCardHtml,
  bfLabel, barCols, barNeed, barHeadHtml, barRowHtml, type BarNeed, type BarCols, type Measure,
} from '../src/orderflow/drawerView'
import { pillFit, PILL_DOT } from '../src/orderflow/state'
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
    // 窄卡逐级让位：先省「N分」只留圆环，再把金额收成整数，再省「卖墙」两字（墙在现价上方自明），字不压到圆环底下
    const mid = levelsSvg({ ...base, w: 130, ask: { price: 102, usd: 5e6, age: 30 * MIN }, bid: null, tw })
    expect(mid.svg).not.toContain('30分')
    expect(mid.svg).toContain('卖墙 5.0M')
    const tight = levelsSvg({ ...base, w: 120, ask: { price: 102, usd: 15.2e6, age: 30 * MIN }, bid: null, tw })
    expect(tight.svg).toContain('卖墙 15M')
    expect(tight.svg).not.toContain('15.2M')
    const narrow = levelsSvg({ ...base, w: 120, ask: { price: 102, usd: 5e6, age: 30 * MIN }, bid: null, tw })
    expect(narrow.svg).not.toContain('30分')
    expect(narrow.svg).not.toContain('卖墙')
    expect(narrow.svg).toContain('>5.0M<')
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
    expect((h.match(/<b class="num">—<\/b>/g) ?? []).length).toBe(7) // 现货、合约 + 五家
    expect(h).toContain('var(--of-track)')
    const live = srcHtml(100, 25, [40, 20, 10, 18, 12])
    expect(live).toContain('25%'); expect(live).toContain('75%'); expect(live).toContain('40%')
    for (const n of ['币安', 'OKX', 'Coinbase', 'Bybit', 'Hyperliquid']) expect(live).toContain(n)
    expect(live).toContain('18%'); expect(live).toContain('12%')
    expect(live).toContain('var(--of-bybit)'); expect(live).toContain('var(--of-hl)')
  })
  it('悬停卡：只有历史的根不摆笔数 / 最大一笔 / 来源，也不写说明', () => {
    const d: BarBig = { t: 0, t1: 300_000, bb: 2e6, bs: 1e6, bn: null, sn: null, bmax: null, smax: null, spot: null, ex: null, exact: false } as unknown as BarBig
    const h = hoverCardHtml(d, '10-08 12:30', '5分')
    expect(h).toContain('+1')
    expect(h).not.toContain('历史回填'); expect(h).not.toContain('hc-src')
    expect(h).not.toContain('最大一笔'); expect(h).not.toContain('现货'); expect(h).not.toContain('>—<')
  })
  it('悬停卡顶上两行：向上 = 买入 + 空单爆仓、向下 = 卖出 + 多单爆仓，零的那项不写', () => {
    const d: BarBig = { t: 0, t1: 300_000, bb: 2e6, bs: 1e6, bn: null, sn: null, bmax: null, smax: null, spot: null, ex: null, exact: false } as unknown as BarBig
    const h = hoverCardHtml(d, '10-08 12:30', '5分', { long: 0, short: 5e5 })
    const kv = h.slice(h.indexOf('hc-kv'))
    expect(kv.indexOf('向上')).toBeGreaterThan(-1)
    expect(kv.indexOf('向上')).toBeLessThan(kv.indexOf('向下'))
    expect(kv.indexOf('向下')).toBeLessThan(kv.indexOf('卖出'))
    expect(kv).toContain('空单爆仓'); expect(kv).not.toContain('多单爆仓')
    expect(kv).toMatch(/向上<\/span><b class="num up">2\.5M</)
    expect(kv).toMatch(/向下<\/span><b class="num dn">1(\.0)?M</)
  })
  it('只有爆仓没有大单的根：只有时间与向上 / 向下两行；没有爆仓项（liq 不传）不加那两行', () => {
    const h = hoverCardHtml(null, '10-08 12:30', '5分', { long: 3e6, short: 0 })
    expect(h).toContain('向上'); expect(h).toContain('多单爆仓'); expect(h).not.toContain('hc-net'); expect(h).not.toContain('卖出')
    const d: BarBig = { t: 0, t1: 300_000, bb: 2e6, bs: 1e6, bn: null, sn: null, bmax: null, smax: null, spot: null, ex: null, exact: false } as unknown as BarBig
    expect(hoverCardHtml(d, '10-08 12:30', '5分')).not.toContain('向上')
    expect(hoverCardHtml(d, '10-08 12:30', '5分', null)).toContain('向上')
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

// ---- 逐根列布局（1024 宽窗口里列重叠：1 时「242/191」比 38 px 的笔数列宽，压到最大单笔）
/** 假字宽：中文一个字 = 字号，其余 0.62 字号 */
const mw: Measure = (t, _w = 600, size = 11) => [...t].reduce((a, ch) => a + (/[一-鿿]/.test(ch) ? size : size * 0.62), 0)
const NEED: BarNeed = { tm: 40, tmWide: 70, bf: 30, n: 40, c: 30, m: 40, x: 30, v: 26 }
/** cols 里定宽各列（px）与对撞条的下限 */
const parseCols = (k: BarCols): { fixed: number[]; bfMin: number } => {
  const m = /^(\d+)px minmax\((\d+)px, 1fr\)((?: \d+px)*)$/.exec(k.cols)!
  return { fixed: [+m[1], ...m[3].trim().split(' ').filter(Boolean).map(x => parseInt(x))], bfMin: +m[2] }
}
const bigBar = (t: number, over: Partial<BarBig> = {}): { t: number; d: BarBig } => ({
  t, d: { t, t1: t + HOUR, bb: 57.5e6, bs: 38.7e6, bn: 217, sn: 264, bmax: { usd: 17.3e6, price: 1, exchange: 'binance', product: 'usdtPerp', t }, smax: null, spot: 1e7, ex: [5e7, 3e7, 1e7, 5e6, 1.2e6], exact: true, ...over },
})

describe('逐根 · 列布局', () => {
  it('行内宽 ≥ 788：宽卡大档（时间带日期、多一列现货），照原来的疏密', () => {
    const k = barCols(800, NEED)
    expect(k).toMatchObject({ wide: true, c: true, m: true, v: true, gap: 10 })
    expect(k.cols).toBe('92px minmax(200px, 1fr) 80px 64px 80px 60px 120px')
  })
  it('628–787：宽卡小档', () => {
    const k = barCols(640, NEED)
    expect(k).toMatchObject({ wide: true, gap: 8 })
    expect(k.cols.startsWith('80px minmax(150px, 1fr)')).toBe(true)
  })
  it('窄卡放得下：原来那套 52 / ≥76 / 52 / 38 / 50 / 26', () => {
    const k = barCols(560, NEED)
    expect(k).toMatchObject({ wide: false, c: true, m: true, v: true, gap: 6 })
    expect(k.cols).toBe('52px minmax(76px, 1fr) 52px 38px 50px 26px')
  })
  it('字比设计宽宽：列跟着字放宽，不再让字压到隔壁（笔数 46 不再塞进 38）', () => {
    const k = barCols(560, { ...NEED, c: 46 })
    expect(parseCols(k).fixed[2]).toBe(46)
  })
  it('放不下时依次省来源、笔数、最大单笔；净额与时间一直在', () => {
    const need = { ...NEED, tm: 46, n: 49, c: 48, m: 46, bf: 38 }
    const order = [600, 330, 300, 250, 200].map(w => barCols(w, need))
    expect(order.map(k => [k.v, k.c, k.m])).toEqual([[true, true, true], [false, true, true], [false, true, true], [false, false, true], [false, false, false]])
  })
  it('任何宽度：放得下的那档定宽 + 对撞条下限 + 间距不超过行宽，每列不比字窄', () => {
    for (let w = 120; w <= 1000; w += 7) {
      const need = { ...NEED, c: 30 + (w % 23), n: 38 + (w % 11), bf: 28 + (w % 13) }
      const k = barCols(w, need), p = parseCols(k)
      if (p.bfMin > 0) expect(p.fixed.reduce((a, b) => a + b, 0) + p.bfMin + p.fixed.length * k.gap).toBeLessThanOrEqual(w)
      if (p.bfMin > 0) expect(p.bfMin).toBeGreaterThanOrEqual(2 * need.bf + 2)
      expect(p.fixed[0]).toBeGreaterThanOrEqual(k.wide ? need.tmWide : need.tm)
      expect(p.fixed[1]).toBeGreaterThanOrEqual(need.n)
      if (k.c) expect(p.fixed[2]).toBeGreaterThanOrEqual(need.c)
      expect(p.fixed.length).toBe(2 + (k.c ? 1 : 0) + (k.m ? 1 : 0) + (k.wide ? 1 : 0) + (k.v ? 1 : 0))
    }
  })
  it('连最窄那档都放不下：对撞条退到 minmax(0, 1fr)（条里的字由 bfLabel 自己收）', () => {
    expect(barCols(120, NEED).cols).toMatch(/minmax\(0px, 1fr\)/)
  })
  it('barNeed：表头「逐根 15分」、三位数笔数、收短的金额都量进去', () => {
    const n = barNeed([bigBar(Date.UTC(2026, 9, 8, 5))], 15 * MIN, mw)
    expect(n.tm).toBeGreaterThanOrEqual(mw('逐根', 650, 12) + 4 + mw('15分', 500, 11))
    expect(n.c).toBeGreaterThanOrEqual(mw('217/264', 400))
    expect(n.bf).toBeGreaterThanOrEqual(mw('58M') + 10)
    expect(n.m).toBeGreaterThanOrEqual(9 + mw('17.3M', 400))
  })
  it('表头与行按同一份列摆：省掉的列两边都不出', () => {
    const k: BarCols = { cols: '', gap: 6, wide: false, c: false, m: true, v: false }
    const head = barHeadHtml(HOUR, k)
    expect(head).not.toContain('笔数')
    expect(head.match(/class="rt"/g)!.length).toBe(2) // 净额、最大单笔
    const row = barRowHtml(bigBar(Date.UTC(2026, 9, 8, 5)), { k, half: 60, max: 1, lastT: 0, live: false, daily: false, sel: null, cross: null, tw })
    expect(row).not.toContain('class="c num"')
    expect(row).not.toContain('class="v"')
    expect(row).toContain('class="m num"')
    const wide = barRowHtml(bigBar(Date.UTC(2026, 9, 8, 5)), { k: { ...k, wide: true, c: true, v: true }, half: 60, max: 1, lastT: 0, live: false, daily: false, sel: null, cross: null, tw })
    expect(wide.match(/class="c num"/g)!.length).toBe(2) // 笔数 + 现货
    expect(wide).toContain('10-08 13:00')
  })
  it('没有行：表头只有标题', () => expect(barHeadHtml(MIN, null)).not.toContain('bf-h'))
})

describe('对撞条 · 半边放不下', () => {
  it('完整 → 收成整数 → 不写字', () => {
    expect(bfLabel(15.2e6, 100, tw)).toBe('15.2M')
    expect(bfLabel(15.2e6, 32, tw)).toBe('15M')
    expect(bfLabel(15.2e6, 20, tw)).toBe('')
  })
  it('不写字时只剩条，没有会漫进时间列的 span', () => {
    const h = bfHtml({ s: 15.2e6, b: 1, max: 15.2e6, half: 20, tw })
    expect(h).toMatch(/<div class="h s"><i style="width:20\.0px"><\/i><\/div>/)
  })
})

describe('梯子大单胶囊 · 选档', () => {
  it('放得下带交易所名（连小点）就用它', () => expect(pillFit(200, [80, 33, 22], 2)).toEqual({ i: 0, dots: 2, w: 80 + 12 + 16 }))
  it('先丢名字、再丢小点、再收短', () => {
    expect(pillFit(60, [80, 33, 22], 2)).toEqual({ i: 1, dots: 1, w: 33 + 12 + 9 })
    expect(pillFit(46, [80, 33, 22], 2)).toEqual({ i: 1, dots: 0, w: 45 })
    expect(pillFit(44, [80, 33, 22], 2)).toEqual({ i: 2, dots: 1, w: 22 + 12 + 9 })
  })
  it('连收短的金额也放不下：不写字只画小圆点；再窄连点也不画', () => {
    expect(pillFit(24, [80, 33, 22], 0)).toEqual({ i: -1, dots: 0, w: PILL_DOT })
    expect(pillFit(8, [80, 33, 22], 0)).toEqual({ i: -1, dots: 0, w: 0 })
  })
  it('任何 room：胶囊都不比 room 宽（不会被画布边裁成半截字）', () => {
    for (let room = 0; room < 120; room++) for (const o of [0, 1, 3, 5]) expect(pillFit(room, [70, 30, 20], o).w).toBeLessThanOrEqual(room)
  })
})
