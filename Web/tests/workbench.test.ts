import { describe, expect, it } from 'vitest'
import type { Bar } from '../src/chart/calc'
import { cvd, vwap, vwapAnchor, barDelta } from '../src/chart/indicators'
import { vpvr } from '../src/chart/overlays'
import {
  makePriceAlert, makeDrawingAlert, migrateAlert, linePriceAt, touchedBetween, alertLevel, priceTitle,
  drawingLines, cleanWebhook, rulePhrase, fundingHit, conditionLabel,
} from '../src/alerts/shape'

const bar = (t: number, o: number, h: number, l: number, c: number, v: number, extra: Partial<Bar> = {}): Bar => ({ t, o, h, l, c, v, ...extra })

describe('成交量分布（可见区间）', () => {
  it('每根 K 线的成交额按高低区间的重叠长度摊到各行，总量守恒', () => {
    const bars = [bar(0, 100, 110, 100, 105, 1000, { tb: 600 }), bar(60e3, 105, 105, 100, 101, 500, { tb: 100 })]
    const v = vpvr(bars, 0, 1, 10)!
    expect(v.lo).toBe(100); expect(v.hi).toBe(110); expect(v.step).toBe(1)
    const tot = v.rows.reduce((s, r) => s + r.buy + r.sell, 0)
    expect(tot).toBeCloseTo(1500, 9)
    // 第一根 10 行各 100（买 60 卖 40），第二根只在 100–105 的 5 行各 100（买 20 卖 80）
    expect(v.rows[0].buy).toBeCloseTo(80, 9); expect(v.rows[0].sell).toBeCloseTo(120, 9)
    expect(v.rows[9].buy).toBeCloseTo(60, 9); expect(v.rows[9].sell).toBeCloseTo(40, 9)
  })
  it('控制点是合计最大的一行；价值区从控制点往两边扩到 ≥ 七成', () => {
    const bars = [bar(0, 100, 101, 100, 100, 10), bar(1, 104, 105, 104, 104, 100), bar(2, 105, 106, 105, 105, 30), bar(3, 103, 104, 103, 103, 20), bar(4, 109, 110, 109, 110, 5)]
    const v = vpvr(bars, 0, 4, 10)!
    expect(v.poc).toBe(4)
    const inVa = v.rows.slice(v.vaLo, v.vaHi + 1).reduce((s, r) => s + r.buy + r.sell, 0)
    expect(inVa / v.total).toBeGreaterThanOrEqual(0.7)
    expect(v.vaLo).toBeLessThanOrEqual(v.poc); expect(v.vaHi).toBeGreaterThanOrEqual(v.poc)
    // 七成只要控制点 + 一行就够（100 + 30 = 130 / 165）
    expect(v.vaHi - v.vaLo).toBe(1)
  })
  it('没有主动买入数据时买卖对半；区间外的根不算', () => {
    const bars = [bar(0, 1, 2, 1, 2, 999), bar(1, 1, 2, 1, 1.5, 100)]
    const v = vpvr(bars, 1, 1, 4)!
    const buy = v.rows.reduce((s, r) => s + r.buy, 0), sell = v.rows.reduce((s, r) => s + r.sell, 0)
    expect(buy).toBeCloseTo(50, 9); expect(sell).toBeCloseTo(50, 9)
  })
  it('空区间给 null', () => { expect(vpvr([], 0, 0, 10)).toBeNull() })
})

describe('累计量差（CVD）', () => {
  it('每根的差 = 2 × 主动买入 − 总成交额，逐根累加', () => {
    const bars = [bar(0, 1, 1, 1, 1, 100, { tb: 70 }), bar(1, 1, 1, 1, 1, 50, { tb: 10 }), bar(2, 1, 1, 1, 1, 10)]
    expect(cvd(bars)[0]).toEqual([40, 10, 10])
  })
  it('多交易所聚合时用各家的差之和', () => {
    expect(barDelta(bar(0, 1, 1, 1, 1, 100, { tb: 90, venueDelta: { binance: 5, okx: -3, coinbase: 1 } }))).toBe(3)
  })
})

describe('成交均价（VWAP）', () => {
  it('典型价按成交量（币）加权，±σ 对称', () => {
    const bars = [bar(0, 10, 12, 9, 9, 0, { bv: 1 }), bar(60e3, 9, 12, 9, 12, 0, { bv: 3 })]
    const [m, u1, d1, u2, d2] = vwap(bars, 60e3)
    expect(m[0]).toBeCloseTo(10, 9)
    expect(m[1]).toBeCloseTo((10 * 1 + 11 * 3) / 4, 9)
    const sd = Math.sqrt((1 * 100 + 3 * 121) / 4 - (43 / 4) ** 2)
    expect(u1[1]! - m[1]!).toBeCloseTo(sd, 9); expect(m[1]! - d1[1]!).toBeCloseTo(sd, 9)
    expect(u2[1]! - m[1]!).toBeCloseTo(2 * sd, 9); expect(d2[1]).toBeCloseTo(m[1]! - 2 * sd, 9)
  })
  it('分钟线在 UTC 0 点（上海 8 点）换日，从头累计', () => {
    const day = Date.UTC(2026, 8, 29)
    const bars = [bar(day - 60e3, 1, 1, 1, 1, 0, { bv: 5 }), bar(day, 3, 3, 3, 3, 0, { bv: 1 })]
    const [m] = vwap(bars, 60e3)
    expect(m[1]).toBeCloseTo(3, 9)
    expect(vwapAnchor(day + 5 * 36e5, 60e3)).toBe(day)
  })
  it('没有币量时用成交额 / 收盘价折算', () => {
    const [m] = vwap([bar(0, 2, 2, 2, 2, 200), bar(60e3, 4, 4, 4, 4, 400)], 60e3)
    expect(m[1]).toBeCloseTo(3, 9)
  })
})

describe('提醒的形状与判定', () => {
  it('价格提醒：一个点两侧延伸，标题按现价判涨到 / 跌到', () => {
    const a = makePriceAlert('BTCUSDT', 70000, 65000, { now: 1000, dec: 1 })
    expect(a.kind).toBe('price'); expect(a.once).toBe(true); expect(a.status).toBe('active'); expect(a.market).toBe('binance/usd_m')
    expect(a.lines).toEqual([{ points: [{ t: 1000, p: 70000 }], extendLeft: true, extendRight: true }])
    expect(a.title).toBe('BTC 涨到 70000')
    expect(priceTitle('ETHUSDT', 3000, 3100, 2)).toBe('ETH 跌到 3000')
    expect(conditionLabel('touch')).toBe('价格达到')
  })
  it('趋势线插值、只在延伸的一侧外推', () => {
    const l = { points: [{ t: 0, p: 100 }, { t: 100, p: 200 }], extendLeft: false, extendRight: true }
    expect(linePriceAt(l, 50)).toBe(150)
    expect(linePriceAt(l, 200)).toBe(300)
    expect(linePriceAt(l, -10)).toBeNull()
  })
  it('画线摊平：水平线两侧延伸，射线往画的方向延伸，矩形不给', () => {
    expect(drawingLines({ type: 'hline', pts: [{ t: 5, p: 9 }] })).toEqual([{ points: [{ t: 5, p: 9 }], extendLeft: true, extendRight: true }])
    const ray = drawingLines({ type: 'ray', pts: [{ t: 10, p: 1 }, { t: 0, p: 2 }] })[0]
    expect(ray.extendLeft).toBe(true); expect(ray.extendRight).toBe(false)
    expect(drawingLines({ type: 'rect', pts: [{ t: 0, p: 1 }, { t: 1, p: 2 }] })).toEqual([])
  })
  it('两笔之间穿过线才响；上一笔正好在线上不重复响；布置之前的不算', () => {
    const a = makePriceAlert('BTCUSDT', 100, 90, { now: 1000 })
    expect(touchedBetween(a, 95, 101, 2000)).toBe(100)
    expect(touchedBetween(a, 95, 99, 2000)).toBeNull()
    expect(touchedBetween(a, 100, 101, 2000)).toBeNull()
    expect(touchedBetween(a, 95, 101, 500)).toBeNull()
    const d = makeDrawingAlert('BTCUSDT', { id: 'd1', type: 'trend', pts: [{ t: 0, p: 100 }, { t: 1000, p: 200 }], color: '#000', width: 2 }, 0)
    expect(alertLevel(d, 500)).toBe(150)
    expect(touchedBetween(d, 140, 160, 500)).toBe(150)
  })
  it('第一阶段的老形状迁过来：价格、资金费率、持仓量；认不得的丢掉', () => {
    const p = migrateAlert({ id: 'x', symbol: 'BTCUSDT', kind: 'price', price: 50000, dir: 1, created: 5 })!
    expect(p.kind).toBe('price'); expect(alertLevel(p)).toBe(50000); expect(p.title).toBe('BTC 涨到 50000')
    const f = migrateAlert({ symbol: 'ETHUSDT', kind: 'fr', value: 0.05, op: 'gt' })!
    expect(f.rule).toEqual({ type: 'funding', side: 'above', rate: '0.0005' })
    expect(rulePhrase(f.rule)).toBe('资金费率高于 0.05%')
    const o = migrateAlert({ symbol: 'ETHUSDT', kind: 'oi', value: 5 })!
    expect(rulePhrase(o.rule)).toBe('1 小时持仓量变化超过 5%')
    expect(migrateAlert({ symbol: 'X', kind: 'weird' })).toBeNull()
    expect(migrateAlert(null)).toBeNull()
  })
  it('资金费率只在结算前 15 分钟里判', () => {
    const r = { type: 'funding' as const, side: 'above' as const, rate: '0.0005' }
    expect(fundingHit(r, 0.001, 20 * 60e3, 0)).toBe(false)
    expect(fundingHit(r, 0.001, 10 * 60e3, 0)).toBe(true)
    expect(fundingHit(r, 0.0001, 10 * 60e3, 0)).toBe(false)
  })
  it('Webhook 只认 http(s) 地址', () => {
    expect(cleanWebhook(' https://x.y/h ')).toBe('https://x.y/h')
    expect(cleanWebhook('ftp://x')).toBeNull()
    expect(cleanWebhook('https://a b')).toBeNull()
  })
})

describe('秒级与自定义分钟', async () => {
  const iv = await import('../src/chart/intervals')
  it('按周期对齐并线：开取第一根、收取最后一根、量相加', () => {
    const bars = [bar(0, 1, 2, 1, 2, 10, { tb: 4, bv: 5 }), bar(60e3, 2, 5, 2, 3, 20, { tb: 1, bv: 7 }), bar(180e3, 3, 3, 0.5, 1, 5)]
    const out = iv.aggregate(bars, 120e3)
    expect(out).toHaveLength(2)
    expect(out[0]).toMatchObject({ t: 0, o: 1, h: 5, l: 1, c: 3, v: 30, tb: 5, bv: 12 })
    expect(out[1]).toMatchObject({ t: 120e3, o: 3, c: 1, l: 0.5, v: 5 })
  })
  it('自定义分钟取能整除它的最大原生周期当底；原生的不算自定义', () => {
    expect(iv.customBase('7m')).toBe('1m')
    expect(iv.customBase('45m')).toBe('15m')
    expect(iv.customBase('90m')).toBe('30m')
    expect(iv.customBase('180m')).toBe('1h')
    expect(iv.isCustomIv('15m')).toBe(false)
    expect(iv.minutesIv(60)).toBe('1h')
    expect(iv.minutesIv(7)).toBe('7m')
    expect(iv.isSecondIv('5s')).toBe(true)
    expect(iv.streamIvOf('1s')).toBeNull()
    expect(iv.streamIvOf('45m')).toBe('15m')
  })
})
