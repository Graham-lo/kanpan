// 公允价值缺口：直接读 iOS 那边的黄金样例（KanpanCore/Tests/KanpanCoreTests/Fixtures/fvg.json），不复制。
// 逐位相等：缺口边界都是原样的高低价或两者之半，Swift 与这里结果必须一模一样。
import { describe, it, expect } from 'vitest'
// @ts-expect-error Web 的 tsconfig 不带 @types/node，这里只在 vitest（node 环境）里用
import { readFileSync } from 'node:fs'
import { AUTO_LAYERS, FVG_CONFIG, fvgZones, fvgZonesOfSeries, type FVGConfig, type FVGZone } from '../src/analysis/fvg'
import { BarSeries, bar } from '../src/m/chart/series'

interface Case {
  name: string
  closedCount: number
  config: FVGConfig
  bars: [number, number, number, number, number][]
  expected: FVGZone[]
}

const FIXTURE = new URL('../../KanpanCore/Tests/KanpanCoreTests/Fixtures/fvg.json', import.meta.url)
const cases = JSON.parse(readFileSync(FIXTURE, 'utf8')) as Case[]

describe('公允价值缺口 fvg.json', () => {
  it('出厂参数只来自 Analysis/fvg.json', () => {
    expect(FVG_CONFIG).toEqual({ trPeriod: 14, minTrRatio: 0.25, maxAgeBars: 500, perSide: 6 })
    expect([...AUTO_LAYERS]).toEqual(['FVG'])
  })

  it('样例覆盖面：至少一例出厂参数、一例多空都有', () => {
    expect(cases.some(c => c.bars.length >= 40 && JSON.stringify(c.config) === JSON.stringify(FVG_CONFIG))).toBe(true)
    expect(cases.some(c => new Set(c.expected.map(z => z.side)).size === 2)).toBe(true)
  })

  for (const c of cases) {
    it(c.name, () => {
      // 电脑网页的 Bar（t/o/h/l/c）
      const desk = c.bars.map(([t, o, h, l, cl]) => ({ t, o, h, l, c: cl, v: 0 }))
      expect(fvgZones(desk, c.closedCount, c.config)).toEqual(c.expected)
      // 手机网页的列式序列
      const s = BarSeries.fromBars('FVG', '1m', c.bars.map(([t, o, h, l, cl]) => bar(t, o, h, l, cl, 0)))
      expect(fvgZonesOfSeries(s, c.closedCount, c.config)).toEqual(c.expected)
    })
  }
})
