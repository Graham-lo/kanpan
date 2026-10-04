/* 手机网页行情页头部：一秒一次（结算倒计时）+ 每跳行情都重画，同值的字和属性不能每次重写
 * （浏览器不比较新旧，每次都换文字节点、记一次属性变动）。实测 10 秒 266 次变动 → 13 次。 */
import { describe, expect, it } from 'vitest'
import { setAttr, setText } from '../src/m/ui/dom'
import header from '../src/m/pages/chart/header.ts?raw'
import bench from '../src/m/pages/chart/drawingBench.ts?raw'

function fakeNode() {
  const n = { writes: 0, attrWrites: 0, _t: '', attrs: {} as Record<string, string>,
    get textContent() { return this._t }, set textContent(v: string) { this._t = v; this.writes++ },
    getAttribute(k: string) { return this.attrs[k] ?? null }, setAttribute(k: string, v: string) { this.attrs[k] = v; this.attrWrites++ } }
  return n
}

describe('setText / setAttr', () => {
  it('同值不写，变了才写', () => {
    const n = fakeNode()
    setText(n as unknown as Node, '1.23'); setText(n as unknown as Node, '1.23'); setText(n as unknown as Node, '1.24')
    expect(n.writes).toBe(2)
    setAttr(n as unknown as Element, 'aria-label', 'a'); setAttr(n as unknown as Element, 'aria-label', 'a')
    expect(n.attrWrites).toBe(1)
  })
})

describe('行情页头部与横屏胶囊接线', () => {
  it('价格、涨跌、六格、读数都走 setText；返回键 hidden 只在变了时写', () => {
    const render = header.slice(header.indexOf('render(sym: string, stale: boolean'))
    expect(render).not.toMatch(/\.textContent = (?!vc\.label)/)
    expect(render).toContain('setText(priceEl,')
    expect(render).toContain('setText(chgEl,')
    expect(render).toContain('setText(b, text)')
    expect(header).toContain('if (back.hidden === hasOrigin) back.hidden = !hasOrigin')
  })
  it('横屏画线品种胶囊：disabled / aria-label / 读数同值不写', () => {
    const q = bench.slice(bench.indexOf('const renderQuote'), bench.indexOf('// ---- 选中栏'))
    expect(q).not.toMatch(/\.textContent =|pill\.setAttribute\(/)
    expect(q).toContain("setAttr(pill, 'aria-label'")
    expect(q).toContain('if (pill.disabled === active) pill.disabled = !active')
  })
})
