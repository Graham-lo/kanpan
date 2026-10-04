/* 手机网页版深度审查 E 线 C8（iOS A-4②）：画线样式面板开着时线被同步改了（另一台挪了点、上了锁）或删了，
 * 「保存」拿打开那一刻的整条快照写回去——把别处的改动回滚掉。修法：按 id 取现在那条，只盖面板里真改过的样式字段。 */
import { describe, expect, it } from 'vitest'
import { mergeStyleEdits } from '../src/m/pages/chart/logic'
import type { Drawing } from '../src/m/chart/draw/drawing'
import benchSource from '../src/m/pages/chart/drawingBench.ts?raw'

const line = (o: Partial<Drawing> = {}): Drawing => ({
  id: 'd1', kind: 'trend', points: [{ t: 1, p: 100 }, { t: 2, p: 110 }],
  color: null, lineWidth: 1.5, dash: 'solid', filled: false, locked: false, hidden: false, levels: [], text: '', ...o,
})

describe('样式面板保存不回滚别处的改动', () => {
  it('复现：打开后另一台挪了点、上了锁；这边只改了颜色——点与锁保留 live 的，颜色用这次改的', () => {
    const opened = line()
    const edited = { ...opened, color: '#FF0000' as Drawing['color'] }
    const live = line({ points: [{ t: 5, p: 200 }, { t: 6, p: 210 }], locked: true })
    const out = mergeStyleEdits(live, opened, edited)!
    expect(out.points).toEqual(live.points)
    expect(out.locked).toBe(true)
    expect(out.color).toBe('#FF0000')
  })
  it('没在面板里动过的样式字段也用 live 的（另一台改的粗细不被打开时的快照盖掉）', () => {
    const opened = line()
    const edited = { ...opened, text: '突破' }
    const live = line({ lineWidth: 3 })
    const out = mergeStyleEdits(live, opened, edited)!
    expect(out.lineWidth).toBe(3)
    expect(out.text).toBe('突破')
  })
  it('比例、换画法按值比较；线已经被删了返回 null（不复活）', () => {
    const opened = line({ kind: 'fibonacci', levels: [0, 0.5, 1] })
    expect(mergeStyleEdits(opened, opened, { ...opened, levels: [0, 0.5, 1] })!.levels).toEqual([0, 0.5, 1])
    const out = mergeStyleEdits(line({ kind: 'fibonacci', levels: [0, 1] }), opened, { ...opened, levels: [0, 0.618, 1], kind: 'fibExtension' })!
    expect(out.levels).toEqual([0, 0.618, 1])
    expect(out.kind).toBe('fibExtension')
    expect(mergeStyleEdits(undefined, opened, opened)).toBeNull()
  })
  it('保存那一处按 id 取现在那条再合并，不直接写快照', () => {
    expect(benchSource).toMatch(/mergeStyleEdits\(c\.drawings\.find\(d => d\.id === orig\.id\), orig, item\)/)
    expect(benchSource).not.toMatch(/c\.updateDrawing\(item\)/)
  })
})
