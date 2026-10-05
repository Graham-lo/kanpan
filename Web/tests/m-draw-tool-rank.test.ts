// 画线条只露几把常用的（照 iOS KanpanTests/Main/DrawingToolRankTests，2026-10-05）
import { describe, expect, it } from 'vitest'
import { DrawKind } from '../src/m/chart/draw/drawing'
import { DECAY_CEILING, DEFAULT_ORDER, countedTool, shownTools } from '../src/m/chart/draw/toolRank'
import benchSource from '../src/m/pages/chart/drawingBench.ts?raw'

describe('画线条露哪几把', () => {
  it('没用过：竖屏四把、横屏五把，按出厂偏好的顺序', () => {
    expect(shownTools({}, 4)).toEqual(['trend', 'hline', 'fibonacci', 'channel'])
    expect(shownTools({}, 5)).toEqual(['trend', 'hline', 'fibonacci', 'channel', 'measure'])
    expect(shownTools({}, 12)).toHaveLength(12)
    expect(new Set(DEFAULT_ORDER)).toEqual(new Set(DrawKind.palette))
  })
  it('按次数从多到少排，没用过的接在后面按出厂偏好补', () => {
    const u = { position: 9, note: 5, measure: 7 }
    expect(shownTools(u, 4)).toEqual(['position', 'measure', 'note', 'trend'])
    expect(shownTools(u, 5)).toEqual(['position', 'measure', 'note', 'trend', 'hline'])
  })
  it('次数一样按面板顺序（水平线在趋势线前面）', () => {
    expect(shownTools({ trend: 3, hline: 3, anchoredVWAP: 3 }, 4)).toEqual(['hline', 'trend', 'anchoredVWAP', 'fibonacci'])
  })
  it('认不出的键、0 和负数不算数', () => {
    expect(shownTools({ laser: 99, note: 0, vline: -4 }, 4)).toEqual(['trend', 'hline', 'fibonacci', 'channel'])
  })
  it('手上拿着的不在前几把里就顶掉最后一格；已经在里面就不动；变体归到族首', () => {
    expect(shownTools({}, 4, 'position')).toEqual(['trend', 'hline', 'fibonacci', 'position'])
    expect(shownTools({}, 4, 'hline')).toEqual(['trend', 'hline', 'fibonacci', 'channel'])
    expect(shownTools({ note: 4, measure: 4, vline: 4, position: 4 }, 4, 'ray')).toEqual(['vline', 'measure', 'note', 'trend'])
  })
})

describe('次数表', () => {
  it('每选一次 +1；变体记在族首名下；面板外的不记', () => {
    let u: Record<string, number> = {}
    u = countedTool(u, 'fibonacci')
    u = countedTool(u, 'fibonacci')
    u = countedTool(u, 'ray')
    expect(u).toEqual({ fibonacci: 2, trend: 1 })
    expect(countedTool(u, 'gannFan')).toEqual(u)
  })
  it('总数过 256 整体减半，减成 0 的删掉；一直点同一把也不会无限涨', () => {
    expect(countedTool({ trend: 200, hline: 56 }, 'note')).toEqual({ trend: 100, hline: 28 })
    expect(countedTool({ trend: 255 }, 'note')).toEqual({ trend: 255, note: 1 })
    let u: Record<string, number> = {}
    for (let i = 0; i < 5000; i++) u = countedTool(u, 'measure')
    expect(Object.values(u).reduce((a, b) => a + b, 0)).toBeLessThanOrEqual(DECAY_CEILING)
  })
  it('不改传进来的那张表', () => {
    const u = Object.freeze({ trend: 1 })
    expect(countedTool(u, 'trend')).toEqual({ trend: 2 })
    expect(u).toEqual({ trend: 1 })
  })
})

describe('横屏画线台接上了', () => {
  it('条上只摆 dockTools()（不再把面板十二把全铺），进画线那一下快照次数表，挑工具时记次数与上次用的', () => {
    expect(benchSource).toMatch(/cp-dscroll">\$\{dockTools\(\)\.map/)
    expect(benchSource).not.toMatch(/cp-dscroll">\$\{DrawKind\.palette\.map/)
    expect(benchSource).toMatch(/if \(on\) \{ sessionUsage = \{ \.\.\.\(st\.drawToolUsage \?\? \{\}\) \}; sessionPicks = \[\] \}/)
    expect(benchSource).toMatch(/st\.drawToolUsage = countedTool\(/)
    // 条上点的、面板里挑的都走 notePick（一次 save）
    expect(benchSource.match(/notePick\(k\)/g)?.length).toBe(2)
  })
})
