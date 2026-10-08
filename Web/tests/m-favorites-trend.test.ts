// 手机网页自选行的 24 小时走势线与药丸闪（照 iOS FavoriteTrend / PillTick，2026-10-08）
import { describe, expect, it } from 'vitest'
import { makeTrend, trendChange, trendInk, trendPath, trendPoints, trendSVG, TREND_CAPACITY, TREND_WINDOW_MS, type TrendBar } from '../src/m/model/favoriteTrend'

const Q = 900_000
const now = 1_760_000_000_000
const bars = (n: number, f: (i: number) => number, end = now): TrendBar[] =>
  Array.from({ length: n }, (_, i) => ({ t: end - (n - 1 - i) * Q, o: f(i), c: f(i) + 1 }))

describe('makeTrend', () => {
  it('只留最近 24 小时（多一根）、最多 97 根；起点是第一根的开盘', () => {
    const t = makeTrend(bars(120, i => 100 + i), now)!
    expect(t.closes.length).toBe(TREND_CAPACITY)
    expect(t.open).toBe(100 + 120 - TREND_CAPACITY)
    expect(t.closes[t.closes.length - 1]).toBe(100 + 119 + 1)
  })
  it('窗口以外的旧根丢掉', () => {
    const old = bars(10, () => 5, now - TREND_WINDOW_MS - 2 * Q - 9 * Q)
    const t = makeTrend([...old, ...bars(3, i => 10 + i)], now)!
    expect(t.closes).toEqual([11, 12, 13])
  })
  it('少于两根 / 价不成数返回 null', () => {
    expect(makeTrend(bars(1, () => 1), now)).toBeNull()
    expect(makeTrend([{ t: now - Q, o: 1, c: 2 }, { t: now, o: 2, c: NaN }], now)).toBeNull()
    expect(makeTrend([{ t: now - Q, o: 0, c: 2 }, { t: now, o: 2, c: 3 }], now)).toBeNull()
  })
})

describe('尾点接最新价与涨跌', () => {
  const t = { open: 100, closes: [101, 99, 102] }
  it('尾点换成最新价；最新价不成数就不换', () => {
    expect(trendPoints(t, 98)).toEqual([101, 99, 98])
    expect(trendPoints(t, null)).toEqual([101, 99, 102])
    expect(trendPoints(t, NaN)).toEqual([101, 99, 102])
    expect(t.closes).toEqual([101, 99, 102])
  })
  it('24 小时涨跌 = 尾点 / 起点 − 1，颜色跟着它', () => {
    expect(trendChange(t, 110)).toBeCloseTo(0.1)
    expect(trendInk(trendChange(t, 110))).toBe('up')
    expect(trendInk(trendChange(t, 90))).toBe('down')
    expect(trendInk(trendChange(t, 100))).toBe('flat')
  })
})

describe('折线', () => {
  it('等距铺满 44 宽，纵向留半根线宽', () => {
    expect(trendPath([1, 2, 3])).toBe('M0 19.25L22 10L44 0.75')
  })
  it('平线画在正中', () => {
    expect(trendPath([5, 5])).toBe('M0 10L44 10')
  })
  it('没有走势时空串（那一格空着）', () => {
    expect(trendSVG(null, 1)).toBe('')
    expect(trendSVG({ open: 1, closes: [2] }, null)).toBe('')
    expect(trendSVG({ open: 1, closes: [1, 2] }, 3)).toContain('class="up"')
  })
})
