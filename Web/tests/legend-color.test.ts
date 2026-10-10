// 图例读数的「文字版」颜色（2026-10-10 审查 B2）：线色不动，图例字同色相压暗 / 提亮到对三套皮肤 --surface 全部 ≥ 4.5:1
import { describe, expect, it } from 'vitest'
// @ts-expect-error Web 的 tsconfig 不带 @types/node，这里只在 vitest（node 环境）里用
import { readFileSync } from 'node:fs'
import { CATALOG } from '../src/chart/calc'
import { LEGEND_SURFACES, contrast, legendTextColor, parseColor, toOklch } from '../src/chart/legendColor'

// 画布上会拿来当图例字色的线色：全部指标目录 + MACD 四色柱（TV hColor）+ 升降柱 + 主力订单流两色 + 枢轴点黑白
const LINE_COLORS = [...new Set([
  ...Object.values(CATALOG).flatMap(c => c.colors ?? []),
  '#26A69A', '#B2DFDB', '#FF5252', '#FFCDD2', '#009688', '#F44336', '#8B5CF6', '#06B6D4', '#000000', '#FFFFFF',
  'rgb(178, 223, 219)', 'rgba(246, 195, 9, 0.8)',
])]

const hueGap = (a: number, b: number): number => { const d = Math.abs(a - b) % 360; return d > 180 ? 360 - d : d }

describe('legendTextColor', () => {
  it('审查点名的三种在浅色下原本不够（< 4.5:1）', () => {
    const bg = parseColor('#F8FAF8')!
    for (const c of ['#F6C309', '#FB9800', '#B2DFDB']) expect(contrast(parseColor(c)!, bg)).toBeLessThan(4.5)
  })

  for (const dark of [false, true]) {
    const mode = dark ? '深色' : '浅色'
    it(`${mode}：每种线色的文字版对三套皮肤的 --surface 全部 ≥ 4.5:1`, () => {
      const bgs = LEGEND_SURFACES[dark ? 'dark' : 'light'].map(x => parseColor(x)!)
      expect(LINE_COLORS.length).toBeGreaterThan(30)
      for (const c of LINE_COLORS) {
        const t = parseColor(legendTextColor(c, dark))!
        for (const bg of bgs) expect(contrast(t, bg), `${c} → ${legendTextColor(c, dark)}`).toBeGreaterThanOrEqual(4.5)
      }
    })
    it(`${mode}：色相基本不变（彩色的 OKLCH 色相差 ≤ 6°），本来够的原样留着`, () => {
      const bgs = LEGEND_SURFACES[dark ? 'dark' : 'light'].map(x => parseColor(x)!)
      for (const c of LINE_COLORS) {
        const src = parseColor(c)!, out = parseColor(legendTextColor(c, dark))!
        const [, C0, h0] = toOklch(src), [, , h1] = toOklch(out)
        if (C0 >= 0.05) expect(hueGap(h0, h1), `${c} → ${legendTextColor(c, dark)}`).toBeLessThanOrEqual(6)
        if (Math.min(...bgs.map(b => contrast(src, b))) >= 4.5) expect(out).toEqual(src)
      }
    })
  }

  it('浅色压暗、深色提亮：MA10 黄在浅色下变暗、仍是黄褐', () => {
    const out = legendTextColor('#F6C309', false)
    const [L0] = toOklch(parseColor('#F6C309')!), [L1, C1] = toOklch(parseColor(out)!)
    expect(L1).toBeLessThan(L0)
    expect(C1).toBeGreaterThan(0.05)
    const d = legendTextColor('#2962FF', true)
    expect(toOklch(parseColor(d)!)[0]).toBeGreaterThan(toOklch(parseColor('#2962FF')!)[0])
  })

  it('认不出的写法原样返回（空串、CSS 变量、color-mix）', () => {
    for (const c of ['', 'var(--up-text)', 'color-mix(in srgb, red 50%, blue)']) expect(legendTextColor(c, false)).toBe(c)
  })

  it('parseColor 认 #rgb / #rrggbbaa / rgb() / rgba()', () => {
    expect(parseColor('#fff')).toEqual([255, 255, 255])
    expect(parseColor('#F6C309CC')).toEqual([246, 195, 9])
    expect(parseColor('rgb(178,223,219)')).toEqual([178, 223, 219])
    expect(parseColor('rgba(1, 2, 3, .5)')).toEqual([1, 2, 3])
    expect(parseColor('rgb(1 2 3 / 50%)')).toEqual([1, 2, 3])
    expect(parseColor('red')).toBeNull()
  })
})

describe('LEGEND_SURFACES 与 app.css 的 --surface 一致（皮肤改底色时这里要跟上）', () => {
  const css = readFileSync(new URL('../src/styles/app.css', import.meta.url), 'utf8') as string
  const surf = (sel: string): string | undefined => {
    const re = /([^{}]+)\{([^}]*)\}/g
    let out: string | undefined
    for (let m; (m = re.exec(css));) if (m[1].replace(/\/\*[\s\S]*?\*\//g, '').trim() === sel) out = /--surface\s*:\s*(#[0-9A-Fa-f]{6})/.exec(m[2])?.[1] ?? out
    return out?.toUpperCase()
  }
  it('三套皮肤 × 浅 / 深', () => {
    const light = [surf('html[data-skin="sage"][data-theme="light"]'), surf(':root, [data-theme="light"]'), surf('html[data-skin="terra"][data-theme="light"]')]
    const dark = [surf('html[data-skin="sage"][data-theme="dark"]'), surf('[data-theme="dark"]'), surf('html[data-skin="terra"][data-theme="dark"]')]
    expect(light).toEqual([...LEGEND_SURFACES.light])
    expect(dark).toEqual([...LEGEND_SURFACES.dark])
  })
})
