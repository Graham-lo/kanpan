/* P3-4 / C13：图例 DOM 写入——拼好的字符串没变就不写（不拿浏览器序列化回来的 innerHTML 比）；
   共用帧里先画所有格子的画布、再统一写图例，避免「写 DOM → 下一格设 ctx.font → 强制样式重算」逐格交错 */
import { describe, expect, it, vi } from 'vitest'

vi.mock('../src/market/rest', () => ({ klines: vi.fn(async () => ({ ok: false, bars: [] })) }))
const { TVChart } = await import('../src/chart/chart')
const { FULL } = await import('../src/chart/panes')
type Any = Record<string, unknown>

function fake(legend: 'full' | 'compact') {
  const bars = Array.from({ length: 5 }, (_, k) => ({ t: 1_700_000_000_000 + k * 36e5, o: 100 + k, h: 102 + k, l: 98 + k, c: 101 + k, v: 1000 }))
  // 模拟浏览器：写进去的 HTML 读回来是另一种写法（徽标 SVG 自闭合标签会被展开）
  let stored = '', writes = 0
  const el = { get innerHTML() { return stored.replace(/\/>/g, '></path>') }, set innerHTML(v: string) { stored = v; writes++ }, querySelectorAll: () => [] }
  const ch = Object.assign(Object.create(TVChart.prototype), {
    bars, legendEl: el, replay: null, cross: null, extCross: null, stale: false, walls: null, compare: null,
    meta: { dec: 2, title: 'BTCUSDT', sub: '1小时 · 币安', badge: '<svg><path d="M0 0"/></svg>' },
    ind: { ma: true, ema: false, boll: false, vol: true, subs: [] },
    params: {}, hidden: new Set<string>(), calcStale: false,
    _series: { ma: [[1, 2, 3, 4, 5]] },
    deg: { ...FULL, legend }, _panes: [],
  } as Any) as InstanceType<typeof TVChart> & Any
  ch.renderPaneLegends = () => {}
  return { ch, writes: () => writes }
}

describe('图例只在内容变了时写 DOM', () => {
  it.each(['compact', 'full'] as const)('%s：同一根 K 线连着渲染三次只写一次（徽标序列化不同也不误判）', legend => {
    const { ch, writes } = fake(legend)
    ch.renderLegend(); ch.renderLegend(); ch.renderLegend()
    expect(writes()).toBe(1)
  })
  it('换了品种标题才重写', () => {
    const { ch, writes } = fake('compact')
    ch.renderLegend()
    ch.meta = { ...ch.meta, title: 'ETHUSDT' }
    ch.renderLegend()
    expect(writes()).toBe(2)
  })
})

describe('共用帧：先画画布、后写图例', () => {
  it('frame() 只画画布不碰图例；frameDom() 再写图例', () => {
    const order: string[] = []
    const ch = Object.assign(Object.create(TVChart.prototype), { dead: false, onScreen: true, dirty: true, crossDirty: false, legendDirty: true } as Any) as InstanceType<typeof TVChart> & Any
    ch.render = () => { order.push('canvas') }
    ch.renderLegend = () => { order.push('legend') }
    ch.frame()
    expect(order).toEqual(['canvas'])
    ch.frameDom()
    expect(order).toEqual(['canvas', 'legend'])
    ch.frameDom()
    expect(order).toEqual(['canvas', 'legend'])
  })
  it('格子不在屏幕上：frameDom 不写', () => {
    const order: string[] = []
    const ch = Object.assign(Object.create(TVChart.prototype), { dead: false, onScreen: false, dirty: false, crossDirty: false, legendDirty: true } as Any) as InstanceType<typeof TVChart> & Any
    ch.renderLegend = () => { order.push('legend') }
    ch.frameDom()
    expect(order).toEqual([])
  })
})
