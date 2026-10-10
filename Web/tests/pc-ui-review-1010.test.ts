// 电脑网页 UI 审查 2026-10-10：B3 工具条尺寸、B5 十字光标块、C4 提示方向、C5 一个动作一个入口
import { describe, expect, it } from 'vitest'
// @ts-expect-error Web 的 tsconfig 不带 @types/node，这里只在 vitest（node 环境）里用
import { readFileSync } from 'node:fs'

const read = (p: string): string => readFileSync(new URL(`../src/${p}`, import.meta.url), 'utf8') as string
const app = read('styles/app.css'), icons = read('styles/icons.css')

describe('B3 工具条：38 高、按钮 32 高', () => {
  it('--toolbar-h 38，工具条按钮 / 周期分段 / 右侧图标按钮都是 --h-md（32）', () => {
    expect(app).toMatch(/--toolbar-h:\s*38px/)
    expect(app).toMatch(/\.tb-btn \{\s*height: var\(--h-md\)/)
    expect(app).toMatch(/\.chart-toolbar \.intervals button \{ height: var\(--h-md\)/)
    expect(app).toMatch(/\.chart-toolbar #tbMoreIv \{ height: var\(--h-md\)/)
    expect(app).toMatch(/\.chart-toolbar \.tb-right \.ibtn \{ width: var\(--h-md\); height: var\(--h-md\); \}/)
  })
  it('周期选中项：强调软底 + 强调字 600', () => {
    expect(app).toMatch(/\.intervals button\[aria-pressed="true"\][^{]*\{ background: var\(--accent-soft\); color: var\(--accent-text\); font-weight: 600; \}/)
  })
})

describe('B5 十字光标块不再是强调色玻璃块', () => {
  it('按下时单独一条：强调软底 + 强调色字形，不用玻璃块的 --qs0 / --qs1', () => {
    const m = /\.drawbar \.ibtn\[data-tool="cursor"\]\[aria-pressed="true"\] > svg\.q,[^{]*\{([^}]*)\}/.exec(icons)
    expect(m).toBeTruthy()
    expect(m![1]).toContain('--q1: var(--qac)')
    expect(m![1]).not.toMatch(/--qs0|--qs1/)
  })
})

describe('C4 提示方向', () => {
  it('主力订单流面板的开关行提示出在左侧；顶栏右侧按钮出在下方', () => {
    expect(read('orderflow/index.ts')).toMatch(/class="of-p-row" data-tip="\$\{tip\}" data-tip-side="left"/)
    const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8') as string
    for (const id of ['hdrAlerts', 'hdrTheme', 'hdrAvatar']) expect(html).toMatch(new RegExp(`id="${id}"[^>]*data-tip-side="bottom"`))
  })
})

describe('C5 一个动作一个入口', () => {
  it('涨跌颜色只在「我的 → 外观」：图表设置对话框里没有这一行', () => {
    expect(read('pages/chartSettingsDialog.ts')).not.toMatch(/updown|涨跌颜色/)
    expect(read('pages/me.ts')).toMatch(/row\('涨跌颜色'/)
  })
  it('深度热力只在主力订单流面板：工具条没有「热力」按钮，面板开关还在', () => {
    expect(read('pages/chart.ts')).not.toMatch(/tbHeat|heatButtonHTML/)
    const of = read('orderflow/index.ts')
    expect(of).not.toMatch(/heatButtonHTML|id="tbHeat"/)
    expect(of).toMatch(/sw\('heat', '深度热力'/)
    expect(of).toMatch(/case 'heat': toggleHeat\(\)/)
  })
})
