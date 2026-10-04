// 画线文字长度校验（drawingIsValid → graphemeCount）是几何每帧每条线都要走的一步。
// 修前每次调用都 new 一个 Intl.Segmenter，满载（30 条线 + 订单流签避让让几何多算一遍）平移时是最热的一段，
// 6000 根 + 三副图 + 30 线 + 订单流、4× 降频下横甩 p95 从 4.6 ms 涨到 6.0 ms。
import { describe, test, expect, vi, afterEach } from 'vitest'

type SegCtor = new (l?: string, o?: { granularity: string }) => { segment(s: string): Iterable<unknown> }
const RealSeg = (Intl as unknown as { Segmenter: SegCtor }).Segmenter

/** 把 Intl.Segmenter 换成计数的子类，重新加载模块（分段器缓存在模块里）。 */
async function withCountingSegmenter() {
  const box = { built: 0 }
  class Counting extends RealSeg { constructor(l?: string, o?: { granularity: string }) { super(l, o); box.built++ } }
  vi.stubGlobal('Intl', { ...Intl, Segmenter: Counting })
  vi.resetModules()
  const fmt = await import('../src/m/chart/draw/fmt')
  const drawing = await import('../src/m/chart/draw/drawing')
  return { box, fmt, drawing }
}

afterEach(() => { vi.unstubAllGlobals(); vi.resetModules() })

describe('graphemeCount', () => {
  test('与 Swift String.count 同口径', async () => {
    const { graphemeCount } = await import('../src/m/chart/draw/fmt')
    expect(graphemeCount('')).toBe(0)
    expect(graphemeCount('abc 123')).toBe(7)
    expect(graphemeCount('\r\n')).toBe(1)
    expect(graphemeCount('a\r\nb\n')).toBe(4)
    expect(graphemeCount('支撑位')).toBe(3)
    expect(graphemeCount('é')).toBe(1)
    expect(graphemeCount('👍🏽')).toBe(1)
    expect(graphemeCount('👨‍👩‍👧‍👦 顶')).toBe(3)
    expect(graphemeCount('🇨🇳BTC')).toBe(4)
  })

  test('分段器整个模块只建一次，纯 ASCII 与空串不建', async () => {
    const { box, fmt, drawing } = await withCountingSegmenter()
    const note = { ...drawing.makeDrawing('note', { t: 1, p: 100 }, null, null, 'n'), text: 'break out 1.2345' }
    for (let i = 0; i < 1000; i++) expect(drawing.drawingIsValid(note)).toBe(true)
    for (let i = 0; i < 100; i++) fmt.graphemeCount('ascii only\r\n')
    fmt.graphemeCount('')
    expect(box.built).toBe(0)
    for (let i = 0; i < 1000; i++) expect(fmt.graphemeCount('突破 👍🏽')).toBe(4)
    expect(box.built).toBe(1)
  })

  test('超长文字仍按字素判：60 个 emoji 有效、61 个无效', async () => {
    const { drawingIsValid, makeDrawing, DRAWING_TEXT_LIMIT } = await import('../src/m/chart/draw/drawing')
    const base = makeDrawing('note', { t: 1, p: 100 }, null, null, 'n')
    expect(drawingIsValid({ ...base, text: '👍🏽'.repeat(DRAWING_TEXT_LIMIT) })).toBe(true)
    expect(drawingIsValid({ ...base, text: '👍🏽'.repeat(DRAWING_TEXT_LIMIT + 1) })).toBe(false)
    expect(drawingIsValid({ ...base, text: 'a'.repeat(DRAWING_TEXT_LIMIT + 1) })).toBe(false)
  })
})
