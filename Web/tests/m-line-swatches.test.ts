// 手机网页版 · 指标线可选色（照 iOS KanpanPresentationTests/LineSwatchTests.swift，2026-10-08）
import { describe, expect, it } from 'vitest'
// @ts-expect-error Web 的 tsconfig 不带 @types/node；vitest 把 .css?raw 处理成空串，只能直接读文件（同 b-contrast.test.ts）
import { readFileSync } from 'node:fs'
import { contrast } from '../src/m/chart/paint'
import { hue, lift, lineSwatchOptions, readable, swatchRoleName, type SwatchSeed } from '../src/m/model/lineSwatches'

/** 从 tokens.css 抠出一套皮肤的种子色（绿涨红跌：蜡烛色取 --seed-up / --seed-down） */
function seedOf(skin: string, theme: string): SwatchSeed & { fallback: string } {
  const block = tokens.split(`html[data-skin="${skin}"][data-theme="${theme}"] {`)[1].split('\n}')[0]
  const v = (name: string): string => {
    const m = block.match(new RegExp(`${name}:\\s*(#[0-9A-Fa-f]{6})\\b`))
    if (!m) throw new Error(`${skin}/${theme} 缺 ${name}`)
    return m[1].toUpperCase()
  }
  return { accent: v('--accent'), ink: v('--ink'), up: v('--seed-up'), down: v('--seed-down'), bg: v('--k-bg'), fallback: v('--palette-0') }
}
const tokens = readFileSync(new URL('../src/m/styles/tokens.css', import.meta.url), 'utf8')
const SKINS = (['sage', 'terra', 'classic'] as const).flatMap(s => (['light', 'dark'] as const).map(t => [s, t] as const))
const GENERIC = new Set(['#E2B34F', '#4A90E2', '#A078D0', '#37A78F', '#E46A76', '#D88040', '#B8C4D8'])

describe('指标线可选色', () => {
  it.each(SKINS)('%s · %s：出厂色第一，其余从皮肤派生、对图区 ≥ 3:1、不重复', (skin, theme) => {
    const s = seedOf(skin, theme)
    const list = lineSwatchOptions(s.fallback, s)
    expect(list[0]).toEqual({ role: 'default', hex: s.fallback })
    expect(list.length).toBeGreaterThanOrEqual(4)
    expect(list.length).toBeLessThanOrEqual(6)
    for (const c of list.slice(1)) {
      expect(contrast(c.hex, s.bg)).toBeGreaterThanOrEqual(3)
      expect(GENERIC.has(c.hex)).toBe(false)
    }
    expect(new Set(list.map(c => c.hex.toUpperCase())).size).toBe(list.length)
    const roles = list.map(c => c.role)
    expect(new Set(roles).size).toBe(roles.length)
    for (const r of roles) expect(['default', 'accent', 'accentLift', 'up', 'down', 'ink']).toContain(r)
  })

  it('出厂色和派生色撞了就只留出厂那支', () => {
    const s = seedOf('sage', 'light')
    const accentOk = readable(s.accent, [s.bg], s.ink, 3)
    const list = lineSwatchOptions(accentOk, s)
    expect(list[0].hex).toBe(accentOk)
    expect(list.some(c => c.role === 'accent')).toBe(false)
  })

  it('lift：色相不动、变亮；0 原样；黑提满是白', () => {
    const base = '#2E7D6B'
    const up = lift(base, 0.42)
    const d = Math.abs(hue(base) - hue(up))
    expect(Math.min(d, 360 - d)).toBeLessThan(2)
    expect(contrast(up, '#FFFFFF')).toBeLessThan(contrast(base, '#FFFFFF'))
    expect(lift(base, 0)).toBe(base)
    expect(lift('#000000', 1)).toBe('#FFFFFF')
  })

  it('角色名是中文', () => {
    expect(swatchRoleName('default')).toBe('默认')
    expect(swatchRoleName('accentLift')).toBe('浅强调色')
    expect(swatchRoleName('ink')).toBe('墨色')
  })
})
