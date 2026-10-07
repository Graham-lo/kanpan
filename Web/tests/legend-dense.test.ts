/* P2-2：格子矮（dense 档）时主图图例把指标并成一行（悬停展开），full 档每个指标一行，compact 只留品种周期 */
import { describe, expect, it, vi } from 'vitest'

vi.mock('../src/market/rest', () => ({ klines: vi.fn(async () => ({ ok: false, bars: [] })) }))
const { TVChart } = await import('../src/chart/chart')
const { degradeFor, FULL } = await import('../src/chart/panes')
type Any = Record<string, unknown>

function legendOf(legend: 'full' | 'dense' | 'compact'): string {
  const bars = Array.from({ length: 5 }, (_, k) => ({ t: 1_700_000_000_000 + k * 36e5, o: 100 + k, h: 102 + k, l: 98 + k, c: 101 + k, v: 1000 }))
  const el = { innerHTML: '', querySelectorAll: () => [] }
  const ch = Object.assign(Object.create(TVChart.prototype), {
    bars, legendEl: el, replay: null, cross: null, extCross: null, stale: false, walls: null, compare: null,
    meta: { dec: 2, title: 'BTCUSDT', sub: '1小时 · 币安', badge: '' },
    ind: { ma: true, ema: true, boll: true, vol: true, subs: ['macd', 'rsi', 'kdj'] },
    params: {}, hidden: new Set<string>(), calcStale: false,
    _series: { ma: [[1, 2, 3, 4, 5]], ema: [[1, 2, 3, 4, 5]], boll: [[1, 2, 3, 4, 5], [1, 2, 3, 4, 5], [1, 2, 3, 4, 5]] },
    deg: { ...FULL, legend }, _panes: [],
  } as Any) as InstanceType<typeof TVChart> & Any
  ch.renderPaneLegends = () => {}
  ch.renderLegend()
  return el.innerHTML
}
const rows = (h: string): number => (h.match(/class="lrow[ "]/g) || []).length

describe('主图图例三档', () => {
  it('full：标题一行 + 每个指标一行（均线、指数均线、布林、成交量 = 5 行）', () => {
    const h = legendOf('full')
    expect(rows(h)).toBe(5)
    expect(h).not.toContain('dense')
  })
  it('dense：标题一行 + 所有指标并成一行（可折叠、悬停展开），指标都还在、工具都还在', () => {
    const h = legendOf('dense')
    expect(rows(h)).toBe(2)
    expect((h.match(/class="dchip/g) || []).length).toBe(4)
    expect(h).toContain('成交量')
    expect((h.match(/data-act="remove"/g) || []).length).toBe(4)
  })
  it('compact：只留品种与周期一行', () => {
    const h = legendOf('compact')
    expect(rows(h)).toBe(1)
    expect(h).toContain('1小时')
    expect(h).not.toContain('成交量')
  })
  it('九图 / 十二图（格高 412 < 500）走 dense，一图大格走 full', () => {
    expect(degradeFor(705, 412).legend).toBe('dense')
    expect(degradeFor(528, 412).legend).toBe('dense')
    expect(degradeFor(1900, 1200).legend).toBe('full')
  })
})
