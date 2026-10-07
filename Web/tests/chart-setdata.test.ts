import { describe, expect, it } from 'vitest'
import type { Bar } from '../src/chart/calc'
import { TVChart } from '../src/chart/chart'

const bars = (n: number): Bar[] => Array.from({ length: n }, (_, i) => ({ t: i * 3_600_000, o: 1, h: 2, l: 0.5, c: 1, v: 1 }) as Bar)

/** 不起画布，只借 setData 的视口逻辑：给它一个最小的 this */
function fake(): TVChart {
  const me = { meta: { symbol: '' }, iv: '', bars: [] as Bar[], rightBar: 0, manual: null, auto: true, dirty: false, o: {}, drag: null, draft: null, recalc() {}, renderLegend() {},
    dropGesture: (TVChart.prototype as unknown as { dropGesture: unknown }).dropGesture,
    // 右侧留白读图表设置（没装设置按默认 10 根）
    rightMarginBars: TVChart.prototype.rightMarginBars, cs: TVChart.prototype.cs }
  return me as unknown as TVChart
}

describe('图表 setData 的视口', () => {
  it('取 K 线失败（先塞空数组）之后重取回来：视口贴到最新一根，不停在最老的那几根上', () => {
    const c = fake()
    TVChart.prototype.setData.call(c, [], { symbol: 'BTCUSDT', iv: '1h' } as never)
    TVChart.prototype.setData.call(c, bars(1500), { symbol: 'BTCUSDT', iv: '1h' } as never)
    expect(c.rightBar).toBeGreaterThanOrEqual(1499)
  })
  it('同品种同周期刷新（已有数据）不动用户的视口', () => {
    const c = fake()
    TVChart.prototype.setData.call(c, bars(1500), { symbol: 'BTCUSDT', iv: '1h' } as never)
    c.rightBar = 800
    TVChart.prototype.setData.call(c, bars(1500), { symbol: 'BTCUSDT', iv: '1h' } as never)
    expect(c.rightBar).toBe(800)
  })
})
