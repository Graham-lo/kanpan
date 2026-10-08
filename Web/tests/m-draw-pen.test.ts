// 移植自 KanpanChartTests/DrawPenLegendFocusTests.swift 里「笔」那几条（2026-10-08 视觉整改）。
import { describe, expect, it } from 'vitest'
import { drawingWith } from '../src/m/chart/draw/drawing'
import { DRAW_REST_ALPHA, penAlpha, penColor, penLighter, penSwatches } from '../src/m/chart/draw/pen'
import { ChartRenderer } from '../src/m/chart/renderer'

// 照 Web/src/m/styles/tokens.css 六档皮肤（绿涨红跌出厂）：--accent、--seed-up/down（即 --k-up/--k-down）、--k-ink。
const SEEDS = {
  sage: { accent: '#2E7D6B', up: '#36B257', down: '#E64552', ink: '#14211B' },
  sageNight: { accent: '#4FB69C', up: '#4FB69C', down: '#E36159', ink: '#E9F2EC' },
  terra: { accent: '#B25735', up: '#36B257', down: '#E64552', ink: '#241A13' },
  terraNight: { accent: '#E2874F', up: '#3FA783', down: '#E0584A', ink: '#F7EFE6' },
  classic: { accent: '#2E7D6B', up: '#36B257', down: '#E64552', ink: '#292D33' },
  classicNight: { accent: '#4FB69C', up: '#2F9347', down: '#CC3333', ink: '#E6EAF2' },
}

describe('画线笔', () => {
  it('没挑过颜色的线跟皮肤强调色，老线的显式色原样', () => {
    for (const t of [SEEDS.sage, SEEDS.sageNight]) {
      const d = drawingWith('trend', [{ t: 0, p: 1 }, { t: 1, p: 2 }])
      expect(penColor(d.color, t)).toBe(t.accent)
      d.color = '#4A90E2'
      expect(penColor(d.color, t)).toBe('#4A90E2')
    }
  })

  it('色板五格全从皮肤来，第一格存 null', () => {
    const t = SEEDS.sage
    const s = penSwatches(t)
    expect(s.map(x => x.role)).toEqual(['skin', 'light', 'up', 'down', 'ink'])
    expect(s[0].stored).toBeNull()
    expect(s[0].shown).toBe(t.accent)
    expect(s[2].stored).toBe(t.up)
    expect(s[3].stored).toBe(t.down)
    expect(s[4].stored).toBe(t.ink)
    expect(s[1].stored).not.toBe(t.accent)
    expect(s[1].stored).toBe(penLighter(t))
    expect(new Set(s.map(x => x.shown)).size).toBe(5)
  })

  it('跟皮肤的笔是皮肤强调色：青苔与陶土分得开，深浅两版都是；同色的格不重复摆', () => {
    for (const [a, b] of [[SEEDS.sage, SEEDS.terra], [SEEDS.sageNight, SEEDS.terraNight]]) {
      expect(penColor(null, a)).toBe(a.accent)
      expect(penColor(null, b)).toBe(b.accent)
      expect(penColor(null, a)).not.toBe(penColor(null, b))
    }
    for (const [name, t] of Object.entries(SEEDS)) {
      const shown = penSwatches(t).map(x => x.shown.toUpperCase())
      expect(new Set(shown).size, `${name} 色板里有两格同色`).toBe(shown.length)
      expect(shown.length).toBeGreaterThanOrEqual(4)
    }
    // 深色青苔的强调色就是涨色：涨色那格不摆
    expect(penSwatches(SEEDS.sageNight).map(x => x.role)).toEqual(['skin', 'light', 'down', 'ink'])
  })

  it('非编辑态 70%，选中 100%，降低透明度时一律 100%', () => {
    expect(penAlpha('a', null, false)).toBe(0.7)
    expect(penAlpha('a', 'b', false)).toBe(0.7)
    expect(penAlpha('a', 'a', false)).toBe(1)
    expect(penAlpha('a', null, true)).toBe(1)
    expect(DRAW_REST_ALPHA).toBe(0.7)
    const r = Object.create(ChartRenderer.prototype) as ChartRenderer
    r.reduceTransparency = false
    expect(r.drawingRestAlpha).toBe(0.7)
    r.reduceTransparency = true
    expect(r.drawingRestAlpha).toBe(1)
  })
})
