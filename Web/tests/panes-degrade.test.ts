/* 多图格子降级（P2-1 / P2-2）：副图按剩下的高度逐个留、宽门槛 480、图例 dense / compact 两档；
 * 表格照十六图审查报告的「视口 × 布局」实测格子尺寸（含底栏） */
import { describe, it, expect } from 'vitest'
import {
  degradeFor, cellClasses, fitSubs, mainMinH, paneHeights, dragPane, footH, FULL,
  AXIS_H, MAIN_MIN_PX, SUB_FIT_MIN, CELL_COMPACT_W, CELL_NO_VOL_W, CELL_SHORT_H, CELL_DENSE_H, FOOT_TRIM_W, FOOT_H, FOOT_SHORT_H,
} from '../src/chart/panes'
import { MAX_SUBS } from '../src/chart/calc'
// @ts-expect-error Web 的 tsconfig 不带 @types/node；vitest 把 .css?raw 处理成空串，只能直接读文件（同 b-contrast.test.ts）
import { readFileSync } from 'node:fs'
const css = readFileSync(new URL('../src/styles/app.css', import.meta.url), 'utf8') as string

const sum = (xs: readonly number[]): number => xs.reduce((a, b) => a + b, 0)
const SUBS3 = ['macd', 'rsi', 'kdj']

// [视口, 布局, 格宽, 格高, 期望副图数, 期望图例档, 期望成交量]
const TABLE: [string, string, number, number, number, 'full' | 'dense' | 'compact', boolean][] = [
  ['1920×1080', '16', 368, 214, 0, 'compact', false],
  ['1920×1080', '12', 368, 296, 1, 'compact', false],
  ['1920×1080', '9', 492, 296, 1, 'compact', true],
  ['2560×1440', '16', 528, 304, 1, 'compact', true],
  ['2560×1440', '12', 528, 412, 3, 'dense', true],
  ['2560×1440', '9', 705, 412, 3, 'dense', true],
  ['3440×1440', '16', 748, 304, 1, 'compact', true],
  ['3440×1440', '12', 748, 412, 3, 'dense', true],
  ['3440×1440', '9', 999, 412, 3, 'dense', true],
  ['125% 缩放', '16', 400, 232, 0, 'compact', false],
  ['125% 缩放', '12', 400, 320, 1, 'compact', false],
  ['125% 缩放', '9', 535, 320, 1, 'compact', true],
]

describe('格子降级：视口 × 布局', () => {
  for (const [vp, k, w, h, subs, legend, vol] of TABLE) {
    it(`${vp} ${k} 图（${w}×${h}）→ 副图 ${subs}、图例 ${legend}${vol ? '、带量' : ''}`, () => {
      const d = degradeFor(w, h)
      expect(d).toMatchObject({ subs, legend, vol, font: legend === 'compact' ? 11 : 12 })
      // 真的按这个档分配窗格：主图 ≥ 160、每个副图 ≥ 56、合计正好是画布高
      const H = h - footH(h) - AXIS_H
      const hs = paneHeights(H, SUBS3.slice(0, d.subs), null)
      expect(sum(hs)).toBe(H)
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
  it('副图逐个留，不再全有全无：高每多 56 多放一个', () => {
    // 格高 h 含底栏（矮格底栏 28、常态 32）与时间轴；画布高 H 每多 56 多放一个
    const at = (H: number): number => { const h = H + FOOT_SHORT_H + AXIS_H; return degradeFor(1000, h < CELL_SHORT_H ? h : H + FOOT_H + AXIS_H).subs }
    expect(at(MAIN_MIN_PX + SUB_FIT_MIN - 1)).toBe(0)
    expect(at(MAIN_MIN_PX + SUB_FIT_MIN)).toBe(1)
    expect(at(MAIN_MIN_PX + 2 * SUB_FIT_MIN)).toBe(2)
    expect(at(MAIN_MIN_PX + 3 * SUB_FIT_MIN)).toBe(3)
    // 高了以后主图还要 ≥ 40%
    expect(fitSubs(1000)).toBe(Math.min(MAX_SUBS, Math.floor((1000 - 400) / SUB_FIT_MIN)))
    expect(mainMinH(1000)).toBe(400)
    expect(mainMinH(100)).toBe(100)
  })
  it('宽门槛 480：479 只留品种周期，480 起是 dense / full；420 以下不画量', () => {
    expect(degradeFor(CELL_COMPACT_W - 1, 600).legend).toBe('compact')
    expect(degradeFor(CELL_COMPACT_W, 600).legend).toBe('full')
    expect(degradeFor(CELL_COMPACT_W, CELL_DENSE_H - 1).legend).toBe('dense')
    expect(degradeFor(1000, CELL_SHORT_H - 1).legend).toBe('compact')
    expect(degradeFor(CELL_NO_VOL_W - 1, 600).vol).toBe(false)
    expect(degradeFor(CELL_NO_VOL_W, 600).vol).toBe(true)
    // 窄只影响图例，不再一刀收掉副图
    expect(degradeFor(CELL_COMPACT_W - 1, 600).subs).toBeGreaterThan(0)
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
  it('底栏收缩类按同一组常量', () => {
    expect(cellClasses(FOOT_TRIM_W - 1, 600)).toEqual({ 'c-narrow': true, 'c-tiny': false, 'c-short': false })
    expect(cellClasses(CELL_NO_VOL_W - 1, CELL_SHORT_H - 1)).toEqual({ 'c-narrow': true, 'c-tiny': true, 'c-short': true })
    expect(footH(CELL_SHORT_H - 1)).toBe(FOOT_SHORT_H)
    expect(footH(CELL_SHORT_H)).toBe(FOOT_H)
  })
  it('app.css 里底栏高与降级说明的数值和常量一致', () => {
    expect(css).toMatch(new RegExp(`\\.chart-cell \\.cell-foot \\{\\s*height: ${FOOT_H}px`))
    expect(css).toMatch(new RegExp(`\\.chart-cell\\.c-short \\.cell-foot \\{ height: ${FOOT_SHORT_H}px`))
    expect(css).toContain(`FOOT_TRIM_W（${FOOT_TRIM_W}）`)
    expect(css).toContain(`CELL_NO_VOL_W（${CELL_NO_VOL_W}）`)
    expect(css).toContain(`CELL_SHORT_H（${CELL_SHORT_H}）`)
  })
})
