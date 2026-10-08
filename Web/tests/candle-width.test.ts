// K 线实体宽照 TradingView（lightweight-charts optimalCandlestickWidth + 影线奇偶）：数值是在 TV 网页版 dpr 1 下量的
import { describe, expect, it } from 'vitest'
import { candleBodyPx } from '../src/chart/chart'

describe('K 线实体宽（TV optimalCandlestickWidth）', () => {
  it('dpr 1：和 TV 网页版量出来的一样', () => {
    const tv: [number, number][] = [[3, 3], [4, 3], [5, 3], [6, 5], [7, 5], [8, 5], [10, 7], [12, 9], [15, 11], [20, 15], [25, 19], [30, 23], [40, 31], [50, 39], [80, 63], [120, 95]]
    for (const [sp, w] of tv) expect(candleBodyPx(sp, 1), `间距 ${sp}`).toBe(w)
  })
  it('最密时只剩影线；Retina 上实体和影线奇偶一致（影线正好居中）', () => {
    expect(candleBodyPx(1, 1)).toBe(1); expect(candleBodyPx(2, 1)).toBe(1)
    for (const sp of [3, 6, 10, 20, 37]) expect(candleBodyPx(sp, 2) % 2).toBe(0)
    expect(candleBodyPx(6, 2)).toBe(10)
  })
})
