/* 手机网页行情页顶栏（照 iOS 2026-10-08）：右上只剩「提醒铃 · ⋯ · 搜索」三颗，
 * 记一笔 / 分享 / 添加对比收进「⋯」菜单；用户原话「分享和记一笔用的极少，我觉得可以放到二级菜单里」。 */
import { describe, expect, it } from 'vitest'
import header from '../src/m/pages/chart/header.ts?raw'
import chart from '../src/m/pages/chart.ts?raw'
import sheet from '../src/m/ui/sheet.ts?raw'
// @ts-expect-error Web 的 tsconfig 不带 @types/node；vitest 把 .css?raw 处理成空串，只能直接读文件
import { readFileSync } from 'node:fs'

const css = readFileSync(new URL('../src/m/styles/chart.css', import.meta.url), 'utf8') as string

describe('顶栏三颗 + 「⋯」菜单', () => {
  it('右上从左到右：提醒 · 更多 · 搜索，不再有对比＋ / 记一笔 / 分享圆片', () => {
    const acts = [...header.matchAll(/<button class="cp-disc[^"]*" data-act="(\w+)"/g)].map(m => m[1])
    expect(acts).toEqual(['alerts', 'more', 'search'])
    expect(header).toMatch(/data-act="more" aria-label="更多"/)
    expect(header).not.toContain('cp-cmpdisc')
  })

  it('菜单从上到下：添加对比 · 记一笔 · 分享，各带 data-act；满三只时添加对比置灰', () => {
    const titles = [...header.matchAll(/\{ title: '([^']+)', icon: '\w+', act: '(\w+)'/g)].map(m => m[1] + ':' + m[2])
    expect(titles).toEqual(['添加对比:compare', '记一笔:note', '分享:share'])
    expect(header).toMatch(/act: 'compare', disabled: compareFull/)
    expect(sheet).toContain('if (it.act) b.dataset.act = it.act')
    expect(chart).toContain("st.compareSymbols.length >= MAX_COMPARE, pendingCount(sym())")
  })

  it('圆片间距回到 m 档；「永续」角标不再在窄屏带返回键时被藏掉', () => {
    expect(css).toMatch(/\.cp-top-acts \{[^}]*gap: var\(--s-m\)/)
    expect(css).not.toMatch(/\.cp-perp \{ display: none \}/)
    expect(css).not.toContain('.cp-cmpdisc')
  })
})
