// 电脑网页 2026-10-10 晚：首页 / 板块 / 复盘 / 我的 按图表页同一套「精致层级」收（层级靠对比与字重，颜色只给涨跌）
import { describe, expect, it } from 'vitest'
// @ts-expect-error Web 的 tsconfig 不带 @types/node，这里只在 vitest（node 环境）里用
import { readFileSync } from 'node:fs'

const read = (p: string): string => readFileSync(new URL(`../src/${p}`, import.meta.url), 'utf8') as string
const home = read('styles/home.css'), sectors = read('styles/sectors.css'), review = read('styles/review.css'), account = read('styles/account.css')

describe('首页', () => {
  it('涨跌药丸是轻薄淡底：涨跌色 12% 底 + 涨跌色字，不实心铺色', () => {
    expect(home).toMatch(/\.hm-pill\.up \{ background: color-mix\(in srgb, var\(--up\) 12%, transparent\); color: var\(--up-text\); \}/)
    expect(home).toMatch(/\.hm-pill\.down \{ background: color-mix\(in srgb, var\(--down\) 12%, transparent\); color: var\(--down-text\); \}/)
    expect(home).not.toMatch(/\.hm-pill\.(up|down) \{ background: var\(--(up|down)\); \}/)
  })
  it('分类胶囊没有色点、选中段是中性浮起；名次前三 text-1；首页 chrome 不用强调色', () => {
    expect(read('pages/home.ts')).not.toMatch(/<i><\/i>|linear-gradient/)
    expect(home).toMatch(/\.hm-chips button\.on, \.hm-wins button\.on \{ background: var\(--well-on\); color: var\(--text-1\); font-weight: 600;/)
    expect(home).toMatch(/\.rk-row:nth-child\(-n\+3\) \.i \{ color: var\(--text-1\); font-weight: 600; \}/)
    expect(home).not.toMatch(/--accent/)
  })
})

describe('板块页', () => {
  it('选中行 --row-on + text-1 600；排序 / 分段是中性凹槽；不用强调色', () => {
    expect(sectors).toMatch(/\.sec-boards tbody tr\.sel td, \.sec-boards tbody tr\.sel:hover td \{ background: var\(--row-on\); \}/)
    expect(sectors).toMatch(/\.sec-boards tr\.sel \.sec-name \{ color: var\(--text-1\); font-weight: 600; \}/)
    expect(sectors).toMatch(/\.sec-sort \.chip\[aria-pressed="true"\] \{ background: var\(--well-on\)/)
    expect(sectors).not.toMatch(/--accent|#F5A623/)
  })
})

describe('我的', () => {
  it('左栏选中项 --row-on + text-1 600，字形是 24 格细线（qsvg），不再用旧填充款 I()', () => {
    expect(account).toMatch(/#page-me \.me-nav a\[aria-current="page"\] \{ background: var\(--row-on\); color: var\(--text-1\); font-weight: 600; \}/)
    const me = read('pages/me.ts')
    expect(me).toMatch(/meIcon\(ic, 'me-ic'\)/)
    expect(me).not.toMatch(/\bI\(/)
    expect(account).not.toMatch(/--accent/)
  })
})

describe('复盘页', () => {
  it('标题 16/600；分段中性；未登录空态字形走 qicons，主按钮保留', () => {
    expect(review).toMatch(/\.rv-top \.rv-head h2 \{[^}]*font-size: var\(--t16\)[^}]*font-weight: 600;/)
    expect(review).toMatch(/#page-review \.seg button\[aria-pressed="true"\] \{ background: var\(--well-on\)/)
    const rv = read('pages/review.ts')
    expect(rv).toMatch(/<div class="empty">\$\{emptyIcon\('trades'\)\}/)
    expect(rv).toMatch(/class="btn primary" id="rvLogin"/)
  })
})
