import { describe, it, expect } from 'vitest'
import { reorderWatch, undoClear } from '../src/watch/logic'

describe('PC 自选拖动排序落点（B4）', () => {
  it('落在淡行（空格取消后留着的那一行）上方：挪到它画出来的位置，不甩到最后', () => {
    // 自选 A B D E；C 是淡行，画在 B 与 D 之间
    const list = ['A', 'B', 'D', 'E'], rendered = ['A', 'B', 'C', 'D', 'E']
    expect(reorderWatch(list, rendered, 'E', 'C', false)).toEqual(['A', 'B', 'E', 'D'])
  })
  it('普通落点照旧：落在 B 下方', () => {
    expect(reorderWatch(['A', 'B', 'C'], ['A', 'B', 'C'], 'C', 'A', true)).toEqual(['A', 'C', 'B'])
  })
  it('拖动途中同步删掉了落点上面那一行：按画出来的相对位置落，不挪错别人', () => {
    // 画面 A B C D，同步把 A 删了；把 D 拖到 C 上方
    expect(reorderWatch(['B', 'C', 'D'], ['A', 'B', 'C', 'D'], 'D', 'C', false)).toEqual(['B', 'D', 'C'])
  })
  it('画完之后才同步进来的那只按它在自选里的位置留着', () => {
    expect(reorderWatch(['A', 'X', 'B', 'C'], ['A', 'B', 'C'], 'C', 'A', false)).toEqual(['C', 'X', 'A', 'B'])
  })
  it('被拖的那只已被同步删掉、落点不在画面上、拖到自己身上：不动', () => {
    expect(reorderWatch(['A', 'B'], ['A', 'B', 'C'], 'C', 'A', false)).toBeNull()
    expect(reorderWatch(['A', 'B'], ['A', 'B'], 'A', 'Z', false)).toBeNull()
    expect(reorderWatch(['A', 'B'], ['A', 'B'], 'A', 'A', true)).toBeNull()
  })
})

describe('清空自选后 ⌘Z（B5）', () => {
  it('清空之后新加的不被撤销覆盖掉', () => {
    expect(undoClear(['A', 'B'], ['C'])).toEqual(['A', 'B', 'C'])
    expect(undoClear(['A', 'B'], ['B'])).toEqual(['A', 'B'])
    expect(undoClear(['A'], [])).toEqual(['A'])
  })
})
