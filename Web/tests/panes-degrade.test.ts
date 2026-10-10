/* 多图格子降级（P2-1 / P2-2）：副图按剩下的高度逐个留、宽门槛 480、图例 dense / compact 两档；
 * 表格照十六图审查报告的「视口 × 布局」实测格子尺寸。2026-10-10 起格子里不再有底栏（整页一条全局底栏，
 * 见 pages/chartFoot.ts），画布高 = 格高 − 时间轴；副图要 K 线主图还能留 ≥ 280 px（MAIN_KEEP_PX）才加，放不下只画主图 + 成交量。
 * 全按格子实际像素判、不按格数：同一个十六图大屏小屏结果不同 */
import { describe, it, expect } from 'vitest'
import {
  degradeFor, cellClasses, fitSubs, mainMinH, mainKeepH, paneHeights, dragPane, FULL,
  AXIS_H, MAIN_MIN_PX, MAIN_KEEP_PX, SUB_FIT_MIN, AXIS_IND_MIN_H, CELL_COMPACT_W, CELL_TINY_W, VOL_FRAC, VOL_MIN_H, volFits, CELL_SHORT_H, CELL_DENSE_H,
} from '../src/chart/panes'
import { GFOOT_H } from '../src/pages/chartFoot'
import { MAX_SUBS } from '../src/chart/calc'
// @ts-expect-error Web 的 tsconfig 不带 @types/node；vitest 把 .css?raw 处理成空串，只能直接读文件（同 b-contrast.test.ts）
import { readFileSync } from 'node:fs'
const css = readFileSync(new URL('../src/styles/app.css', import.meta.url), 'utf8') as string

const sum = (xs: readonly number[]): number => xs.reduce((a, b) => a + b, 0)
const SUBS3 = ['macd', 'rsi', 'kdj']

// [视口, 布局, 格宽, 格高, 期望副图数, 期望图例档, 期望成交量]
const TABLE: [string, string, number, number, number, 'full' | 'dense' | 'compact', boolean][] = [
  // 格子尺寸是 2026-10-10 layout16-review a7 实测（格内已无底栏）；成交量只看高：画布高（格高 − 28）≥ 280 才画
  ['1920×1080', '16', 375, 234, 0, 'compact', false],
  ['1920×1080', '12', 375, 313, 0, 'compact', true],
  ['1920×1080', '9', 501, 313, 0, 'compact', true],
  ['2560×1440', '16', 527, 324, 0, 'compact', true],
  ['2560×1440', '12', 527, 433, 2, 'dense', true],
  ['2560×1440', '9', 704, 433, 2, 'dense', true],
  ['2560×1440', '4', 1050, 640, 5, 'full', true],
  ['3440×1440', '16', 736, 324, 0, 'compact', true],
  ['3440×1440', '12', 736, 433, 2, 'dense', true],
  ['3440×1440', '9', 983, 433, 2, 'dense', true],
  ['125% 缩放', '16', 406, 252, 0, 'compact', false],
  ['125% 缩放', '12', 406, 337, 0, 'compact', true],
  ['125% 缩放', '9', 542, 337, 0, 'compact', true],
  ['1440×900', '4', 600, 380, 1, 'dense', true],
  ['1440×900', '16', 257, 189, 0, 'compact', false],
]

describe('格子降级：视口 × 布局', () => {
  for (const [vp, k, w, h, subs, legend, vol] of TABLE) {
    it(`${vp} ${k} 图（${w}×${h}）→ 副图 ${subs}、图例 ${legend}${vol ? '、带量' : ''}`, () => {
      const d = degradeFor(w, h)
      expect(d).toMatchObject({ subs, legend, vol, font: legend === 'compact' ? 11 : 12 })
      // 真的按这个档分配窗格：主图 ≥ 160、每个副图 ≥ 56、合计正好是画布高
      const H = h - AXIS_H
      const hs = paneHeights(H, SUBS3.slice(0, d.subs), null)
      expect(sum(hs)).toBe(H)
      // 没拖过：K 线主图 ≥ 280（或整块），副图放不下就不画
      expect(hs[0]).toBeGreaterThanOrEqual(Math.min(H, MAIN_KEEP_PX))
      if (d.subs) {
        expect(hs[0]).toBeGreaterThanOrEqual(MAIN_MIN_PX)
        for (const x of hs.slice(1)) expect(x).toBeGreaterThanOrEqual(SUB_FIT_MIN)
      }
    })
  }
  it('一图大格不降级：副图最多 8 个、图例全、字 12、带量', () => {
    expect(degradeFor(1900, 1200)).toEqual(FULL)
    expect(FULL.subs).toBe(MAX_SUBS)
  })
  it('副图逐个留，不再全有全无：K 线留够 280 后高每多 56 多放一个', () => {
    // 格高 h = 画布高 H + 时间轴；H 每多 56 多放一个
    const at = (H: number): number => degradeFor(1000, H + AXIS_H).subs
    expect(at(MAIN_KEEP_PX + SUB_FIT_MIN - 1)).toBe(0)
    expect(at(MAIN_KEEP_PX + SUB_FIT_MIN)).toBe(1)
    expect(at(MAIN_KEEP_PX + 2 * SUB_FIT_MIN)).toBe(2)
    expect(at(MAIN_KEEP_PX + 3 * SUB_FIT_MIN)).toBe(3)
    expect(mainKeepH(200)).toBe(200)
    expect(mainKeepH(1000)).toBe(400)
    // 高了以后主图还要 ≥ 40%
    expect(fitSubs(1000)).toBe(Math.min(MAX_SUBS, Math.floor((1000 - 400) / SUB_FIT_MIN)))
    expect(mainMinH(1000)).toBe(400)
    expect(mainMinH(100)).toBe(100)
  })
  it('宽门槛 480：479 只留品种周期，480 起是 dense / full；成交量只看高、不看宽', () => {
    expect(degradeFor(CELL_COMPACT_W - 1, 600).legend).toBe('compact')
    expect(degradeFor(CELL_COMPACT_W, 600).legend).toBe('full')
    expect(degradeFor(CELL_COMPACT_W, CELL_DENSE_H - 1).legend).toBe('dense')
    expect(degradeFor(1000, CELL_SHORT_H - 1).legend).toBe('compact')
    expect(degradeFor(CELL_TINY_W - 1, 600).vol).toBe(true)
    expect(degradeFor(200, 600).vol).toBe(true)
    // 窄只影响图例，不再一刀收掉副图
    expect(degradeFor(CELL_COMPACT_W - 1, 600).subs).toBeGreaterThan(0)
  })
  it('价格轴指标标签按格子像素：画布 ≥ 480 高且格宽 ≥ 480 才挂', () => {
    expect(degradeFor(1000, AXIS_IND_MIN_H + AXIS_H).axisInd).toBe(true)
    expect(degradeFor(1000, AXIS_IND_MIN_H + AXIS_H - 1).axisInd).toBe(false)
    expect(degradeFor(CELL_COMPACT_W - 1, 900).axisInd).toBe(false)
    expect(FULL.axisInd).toBe(true)
  })
  it('拖过分隔线的照用户的手：主图守 160 / 40%，不按 280 弹回去', () => {
    const H = 384
    const hs = paneHeights(H, ['macd'], { macd: 0.5 })
    expect(hs[0]).toBeLessThan(MAIN_KEEP_PX)
    expect(hs[0]).toBeGreaterThanOrEqual(mainMinH(H))
  })
  it('副图挤的时候也不把主图压到 160 以下；拖分隔线也守住', () => {
    const H = 352
    const hs = paneHeights(H, SUBS3, { macd: 0.3, rsi: 0.3, kdj: 0.3 })
    expect(hs[0]).toBeGreaterThanOrEqual(MAIN_MIN_PX)
    const up = dragPane(hs, 1, -500, H)
    expect(up[0]).toBeGreaterThanOrEqual(MAIN_MIN_PX)
    const down = dragPane(hs, 1, 500, H)
    expect(down[1]).toBeGreaterThanOrEqual(SUB_FIT_MIN)
  })
})

describe('JS 与 CSS 共用一组门槛', () => {
  it('格子收缩类按同一组常量（格子里没有底栏了，只剩 c-tiny 给回放条用）', () => {
    expect(cellClasses(CELL_TINY_W, 600)).toEqual({ 'c-tiny': false })
    expect(cellClasses(CELL_TINY_W - 1, CELL_SHORT_H - 1)).toEqual({ 'c-tiny': true })
  })
  it('app.css 里全局底栏高与降级说明的数值和常量一致；格子里不再有 .cell-foot', () => {
    expect(css).toMatch(/\.chart-foot \{\s*height: var\(--gfoot-h\)/)
    expect(css).toContain('--gfoot-h: var(--h-md)')
    expect(css).toMatch(new RegExp(`--h-md: ${GFOOT_H}px`))
    expect(css).not.toMatch(/\.chart-cell \.cell-foot \{/)
    expect(css).toContain(`CELL_TINY_W（${CELL_TINY_W}）`)
  })
})

describe('成交量和副图同一套像素规则（2026-10-10）', () => {
  it('主图保得住 280 才画成交量，成交量条 = 主图 × VOL_FRAC ≥ VOL_MIN_H；同尺寸格子结果一样', () => {
    expect(volFits(MAIN_KEEP_PX - 1)).toBe(false)
    expect(volFits(MAIN_KEEP_PX)).toBe(true)
    expect(Math.floor(MAIN_KEEP_PX * VOL_FRAC)).toBeGreaterThanOrEqual(VOL_MIN_H)
    // 各档十六格（画布高 = 格高 − 28）：1440 189 / 1920 234 不画，2560 324 画
    expect(degradeFor(257, 189).vol).toBe(false)
    expect(degradeFor(375, 234).vol).toBe(false)
    expect(degradeFor(527, 324).vol).toBe(true)
    expect(degradeFor(527, 324)).toEqual(degradeFor(527, 324))
  })
})
