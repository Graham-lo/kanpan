/* PC 网页三套皮肤 × 浅 / 深：辅助字（--text-3）与涨跌字（--up-text / --down-text）在面板、悬停行、选中行上都要 ≥ 4.5:1 */
import { describe, expect, it } from 'vitest'
// @ts-expect-error Web 的 tsconfig 不带 @types/node，这里只在 vitest（node 环境）里用；vitest 把 .css?raw 处理成空串，只能直接读文件
import { readFileSync } from 'node:fs'

const css = readFileSync(new URL('../src/styles/app.css', import.meta.url), 'utf8') as string

/** 收集某个选择器下（完全相同的选择器文本）声明的所有 #RRGGBB 变量；同一选择器出现多次按出现顺序叠 */
function vars(selector: string): Record<string, string> {
  const out: Record<string, string> = {}
  const re = /([^{}]+)\{([^}]*)\}/g
  for (let m; (m = re.exec(css));) {
    if (m[1].replace(/\/\*[\s\S]*?\*\//g, '').trim() !== selector) continue
    for (const d of m[2].matchAll(/(--[\w-]+)\s*:\s*(#[0-9A-Fa-f]{6})\b/g)) out[d[1]] = d[2]
  }
  return out
}
function palette(skin: 'classic' | 'sage' | 'terra', theme: 'light' | 'dark'): Record<string, string> {
  const base = theme === 'light' ? vars(':root, [data-theme="light"]') : { ...vars(':root, [data-theme="light"]'), ...vars('[data-theme="dark"]') }
  return skin === 'classic' ? base : { ...base, ...vars(`html[data-skin="${skin}"][data-theme="${theme}"]`) }
}
const lum = (h: string): number => {
  const c = [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16) / 255).map(x => x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4)
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
}
const ratio = (a: string, b: string): number => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05) }

describe('三套皮肤的对比度', () => {
  for (const skin of ['classic', 'sage', 'terra'] as const) for (const theme of ['light', 'dark'] as const) {
    it(`${skin} · ${theme}`, () => {
      const p = palette(skin, theme)
      const fgs = { '--text-3': p['--text-3'], '涨（绿）': p['--tv-green-text'], '跌（红）': p['--tv-red-text'] }
      const bgs = { 面板: p['--surface'], 悬停行: p['--surface-2'], 选中行: p['--accent-soft'] }
      const bad: string[] = []
      for (const [fn, f] of Object.entries(fgs)) for (const [bn, b] of Object.entries(bgs)) {
        expect(f && b, `${fn} / ${bn} 取不到`).toBeTruthy()
        const r = ratio(f, b); if (r < 4.5) bad.push(`${fn} ${f} 在${bn} ${b} 上 ${r.toFixed(2)}`)
      }
      expect(bad).toEqual([])
    })
  }
})
