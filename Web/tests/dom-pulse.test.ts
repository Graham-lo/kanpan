/* C13 常态：推送改出来的 DOM 读数攒到节拍边界一起写（chart/domPulse.ts）；交互引起的图例当帧写 */
import { describe, expect, it, vi } from 'vitest'
import { DOM_MS, ROW_MS, PulseDebt, pulseSlot } from '../src/chart/domPulse'

vi.mock('../src/market/rest', () => ({ klines: vi.fn(async () => ({ ok: false, bars: [] })) }))
const { TVChart } = await import('../src/chart/chart')
type Any = Record<string, unknown>

describe('PulseDebt：这一拍欠下的，下一拍的第一帧还', () => {
  it('同一拍里不还、进了下一拍就还，还完清账', () => {
    const d = new PulseDebt(DOM_MS)
    expect(d.due(10)).toBe(false) // 没欠
    d.owe(10)
    expect(d.owing).toBe(true)
    expect(d.due(DOM_MS - 1)).toBe(false)
    expect(d.due(DOM_MS)).toBe(true)
    expect(d.owing).toBe(false)
    expect(d.due(DOM_MS * 3)).toBe(false)
  })
  it('一直有推送也不往后推：按第一次欠下的拍号算（最多晚一拍）', () => {
    const d = new PulseDebt(ROW_MS)
    d.owe(100); d.owe(900); d.owe(990)
    expect(d.due(999)).toBe(false)
    expect(d.due(1000)).toBe(true)
  })
  it('不同节拍的欠账在同一个帧时间戳上拍号一致：详情与自选行在整秒那一帧一起写', () => {
    const a = new PulseDebt(DOM_MS), b = new PulseDebt(ROW_MS)
    a.owe(1900); b.owe(1300)
    expect(a.due(2000) && b.due(2000)).toBe(true)
    expect(pulseSlot(2000)).toBe(8)
  })
})

describe('frameDom：推送引起的图例等拍点，交互的当帧写', () => {
  const mk = (o: Any) => {
    const order: string[] = []
    const ch = Object.assign(Object.create(TVChart.prototype), { dead: false, onScreen: true, dirty: false, crossDirty: false, legendDirty: false, legendPush: false, ...o } as Any) as InstanceType<typeof TVChart> & Any
    ch.renderLegend = () => { order.push('legend') }
    ch.renderPaneLegends = () => { order.push('panes') }
    return { ch, order }
  }
  it('推送（legendPush）：不是拍点不写，拍点上写一次', () => {
    const { ch, order } = mk({ legendPush: true })
    ch.frameDom(false); ch.frameDom(false)
    expect(order).toEqual([])
    ch.frameDom(true); ch.frameDom(true)
    expect(order).toEqual(['legend'])
  })
  it('推送重画出来的副图读数也等拍点', () => {
    const { ch, order } = mk({ paneLegendQ: [] })
    ch.frameDom(false)
    expect(order).toEqual([])
    ch.frameDom(true)
    expect(order).toEqual(['panes'])
  })
  it('交互（legendDirty：十字线、拖动、滚轮）不等拍点，当帧写，顺带把推送欠的一起写掉', () => {
    const { ch, order } = mk({ legendDirty: true, legendPush: true })
    ch.frameDom(false)
    expect(order).toEqual(['legend'])
    ch.frameDom(true)
    expect(order).toEqual(['legend'])
  })
  it('updateBar 改最新一根：记成推送欠账，不置 legendDirty；十字线在图上时不动图例', () => {
    const bars = [{ t: 0, o: 1, h: 2, l: 0.5, c: 1.5, v: 1 }]
    const { ch } = mk({ bars, rightBar: 0, drag: null, cross: null, recalcTail: () => {} })
    ch.updateBar({ t: 0, o: 1, h: 2, l: 0.5, c: 1.6, v: 2 })
    expect([ch.legendPush, ch.legendDirty]).toEqual([true, false])
    const h = mk({ bars: bars.map(b => ({ ...b })), rightBar: 0, drag: null, cross: { x: 1, y: 1 }, recalcTail: () => {} }).ch
    h.updateBar({ t: 0, o: 1, h: 2, l: 0.5, c: 1.7, v: 3 })
    expect([h.legendPush, h.legendDirty]).toEqual([false, false])
  })
})
