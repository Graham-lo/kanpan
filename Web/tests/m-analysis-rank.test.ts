/* 「分析」面板四节按用量排（2026-10-08，照 iOS Panels/AnalysisSectionRank.swift）：
 * 出厂 画线 → 主力订单流 → 指标 → 对比；用过的按次数降序、同次按出厂序；总数过 256 整体减半；
 * 面板打开那一刻定序、开着不重排；「恢复默认指标」永远最后。次数记在同步字段 analysisUsage（三端同一张表）。 */
import { beforeEach, describe, expect, it } from 'vitest'
import { DECAY_CEILING, DEFAULT_ORDER, ANALYSIS_SECTIONS, countedSection, sectionOrder } from '../src/m/pages/chart/analysisRank'
import { SYNCED_FIELDS, cleanAnalysisUsage, defaultPrefs, normalizePrefs } from '../src/m/app/prefs'
import { st } from '../src/m/app/store'
import { analysisHTML, type PanelContext } from '../src/m/pages/chart/panels'
import panelSource from '../src/m/pages/chart/panels.ts?raw'

describe('节序', () => {
  it('出厂：画线 → 主力订单流 → 指标 → 对比', () => {
    expect(DEFAULT_ORDER).toEqual(['draw', 'orderFlow', 'indicators', 'compare'])
    expect([...ANALYSIS_SECTIONS].sort()).toEqual([...DEFAULT_ORDER].sort())
    expect(sectionOrder({})).toEqual(DEFAULT_ORDER)
    expect(sectionOrder(undefined)).toEqual(DEFAULT_ORDER)
  })
  it('用过的按次数降序，没用过的按出厂序补齐', () => {
    expect(sectionOrder({ compare: 9, indicators: 3 })).toEqual(['compare', 'indicators', 'draw', 'orderFlow'])
    expect(sectionOrder({ indicators: 1 })).toEqual(['indicators', 'draw', 'orderFlow', 'compare'])
  })
  it('次数一样按出厂序', () => {
    expect(sectionOrder({ compare: 4, orderFlow: 4, indicators: 4, draw: 4 })).toEqual(DEFAULT_ORDER)
    expect(sectionOrder({ compare: 2, indicators: 2 })).toEqual(['indicators', 'compare', 'draw', 'orderFlow'])
  })
  it('未知键、0、负数、非有限数不影响顺序', () => {
    expect(sectionOrder({ alerts: 99, draw: 0, orderFlow: -3, compare: Number.NaN } as Record<string, number>)).toEqual(DEFAULT_ORDER)
  })
})

describe('计次', () => {
  it('+1 返回新对象，不改原表', () => {
    const u = { draw: 2 }
    const n = countedSection(u, 'compare')
    expect(n).toEqual({ draw: 2, compare: 1 })
    expect(u).toEqual({ draw: 2 })
    expect(countedSection(undefined, 'draw')).toEqual({ draw: 1 })
  })
  it('认不出的键、坏值顺手丢掉，表里最多四个键', () => {
    const n = countedSection({ alerts: 5, draw: 1.5, orderFlow: -1, indicators: 3 } as Record<string, number>, 'draw')
    expect(n).toEqual({ indicators: 3, draw: 1 })
    expect(Object.keys(n).length).toBeLessThanOrEqual(4)
  })
  it(`总数过 ${DECAY_CEILING} 整体减半，减成 0 的删掉`, () => {
    expect(DECAY_CEILING).toBe(256)
    const atCeiling = countedSection({ draw: 255 }, 'compare')
    expect(atCeiling).toEqual({ draw: 255, compare: 1 })
    const over = countedSection({ draw: 255, compare: 1 }, 'compare')
    expect(over).toEqual({ draw: 127, compare: 1 })
    expect(countedSection({ draw: 256 }, 'orderFlow')).toEqual({ draw: 128 })
  })
})

describe('同步字段 analysisUsage', () => {
  it('出厂 {}、进同步字段', () => {
    expect(defaultPrefs().analysisUsage).toEqual({})
    expect(SYNCED_FIELDS).toContain('analysisUsage')
  })
  it('clean：键只认四个节名、整数 > 0、夹 100000、最多 4 键', () => {
    expect(cleanAnalysisUsage({ draw: 3, orderFlow: 0, indicators: -1, compare: 2.5, alerts: 4 })).toEqual({ draw: 3 })
    expect(cleanAnalysisUsage({ compare: 200_000 })).toEqual({ compare: 100_000 })
    expect(cleanAnalysisUsage({ draw: '3' })).toEqual({})
    for (const bad of [null, 'draw', ['draw'], 3]) expect(cleanAnalysisUsage(bad)).toEqual({})
    const full = cleanAnalysisUsage({ draw: 1, orderFlow: 2, indicators: 3, compare: 4 })
    expect(Object.keys(full).length).toBe(4)
  })
  it('解码坏值不丢整份', () => {
    expect(normalizePrefs({ analysisUsage: { compare: 7, laser: 1 } }).analysisUsage).toEqual({ compare: 7 })
    expect(normalizePrefs({ analysisUsage: 'x' }).analysisUsage).toEqual({})
  })
})

describe('分析面板按节序排', () => {
  const ctx = (): PanelContext => ({ symbol: () => 'BTCUSDT', port: () => null, onDraw: () => {}, onAddCompare: () => {}, canCompare: () => true })
  const titles = (html: string): string[] => [...html.matchAll(/<div class="cp-gt">([^<]*)<\/div>/g)].map(m => m[1])
  beforeEach(() => { st.compareSymbols = []; st.analysisUsage = {} })

  it('按传入的 order 排四节，「恢复默认指标」永远最后', () => {
    const html = analysisHTML(ctx(), ['compare', 'indicators', 'orderFlow', 'draw'])
    const t = titles(html)
    expect(t[0]).toBe('对比')
    expect(t[t.length - 1]).toBe('画线')
    expect(t.indexOf('主力订单流')).toBe(t.length - 2)
    expect(t.findIndex(x => /^副图/.test(x))).toBe(t.length - 3)
    expect(html.lastIndexOf('data-act="reset"')).toBeGreaterThan(html.lastIndexOf('data-act="draw-hide"'))
  })
  it('不给 order 就按此刻的 analysisUsage 现算', () => {
    st.analysisUsage = { compare: 5, orderFlow: 2 }
    expect(titles(analysisHTML(ctx()))[0]).toBe('对比')
    expect(titles(analysisHTML(ctx()))[1]).toBe('主力订单流')
  })
  it('打开时定一次序、重画沿用同一份；各动作计到对应节，reset 不计', () => {
    expect(panelSource).toMatch(/const order = sectionOrder\(st\.analysisUsage\)/)
    expect(panelSource).toContain('host.innerHTML = analysisHTML(ctx, order)')
    const tallies: Record<string, string> = {}
    for (const m of panelSource.matchAll(/case '([a-z-]+)':[^\n]*?tally\('(\w+)'\)/g)) tallies[m[1]] = m[2]
    // 'sub' 的 tally 在 case 的下几行
    const sub = /case 'sub': \{[\s\S]*?tally\('(\w+)'\)[\s\S]*?break/.exec(panelSource)
    if (sub) tallies.sub = sub[1]
    expect(tallies).toEqual({
      draw: 'draw', 'draw-hide': 'draw',
      edit: 'indicators', height: 'indicators', ov: 'indicators', sub: 'indicators',
      'cmp-add': 'compare', 'cmp-rm': 'compare', 'cmp-clear': 'compare',
      of: 'orderFlow', 'of-history': 'orderFlow', 'of-edit': 'orderFlow', 'bt-signs': 'orderFlow', 'bt-open': 'orderFlow',
    })
    expect(panelSource).toMatch(/case 'reset': resetLayout\(\); break/)
    expect(panelSource).toMatch(/onMove\([^)]*\) \{[\s\S]*?tally\('indicators'\)[\s\S]*?save\(\)/)
  })
})
