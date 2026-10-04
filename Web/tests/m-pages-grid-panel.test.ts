/* 手机网页版深度审查 E 线 C6：「更多」网格开着时点顶栏的记一笔 / 分享 / 搜索，网格压在面板底下、面板一关又露出来
 * （iOS A-3：收网格挪到 onPanel 一处）。网格遮罩只从周期条下沿起，顶栏点得到——所以开任何面板都要先收网格。
 * 连带：#m-layer > * 的 id 特异性把 .m-pop-wrap 的 pointer-events: none 盖成 auto，锚点上方整片是点了没反应的死区。 */
import { describe, expect, it } from 'vitest'
import chartSource from '../src/m/pages/chart.ts?raw'
import barSource from '../src/m/pages/chart/intervalBar.ts?raw'
// @ts-expect-error Web 的 tsconfig 不带 @types/node，这里只在 vitest（node 环境）里用
import { readFileSync } from 'node:fs'

// vitest 把 .css?raw 处理成空串，直接读文件
const uiCss = readFileSync(new URL('../src/m/styles/ui.css', import.meta.url), 'utf8')

describe('开面板先收「更多」网格', () => {
  it('panel 包装先 closeGrid 再开面板', () => {
    expect(chartSource).toMatch(/const panel = \(open: \(\) => void\) => \(\): void => \{ ivBar\.closeGrid\(\); open\(\) \}/)
  })
  it('顶栏三件与周期条三件全部走 panel', () => {
    for (const k of ['onNote', 'onShare', 'onSearch', 'onAnalysis', 'onSettings', 'onAlert']) {
      expect(chartSource, k).toMatch(new RegExp(`${k}: panel\\(`))
    }
  })
  it('周期条自己不再各收各的（收网格只有一处）', () => {
    expect(barSource).not.toMatch(/grid\?\.close\(\); h\.on/)
    expect(barSource).toMatch(/closeGrid/)
  })
  it('弹层外壳不接点按：#m-layer 的默认 auto 特异性为 0，.m-pop-wrap / .m-sheet-wrap 的 none 作数', () => {
    expect(uiCss).not.toMatch(/^#m-layer > \* \{ pointer-events: auto \}/m)
    expect(uiCss).toMatch(/:where\(#m-layer\) > \* \{ pointer-events: auto \}/)
    expect(uiCss).toMatch(/\.m-pop-wrap \{[^}]*pointer-events: none/)
    expect(uiCss).toMatch(/\.m-sheet-wrap \{[^}]*pointer-events: none/)
  })
})
