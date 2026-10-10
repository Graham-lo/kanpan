/* 2026-10-07「左上角指标悬停一直跳、点不到隐藏按钮」：图例外壳只在结构变了时重建，推送 / 十字线只改读数文字节点；
 * 工具按钮在名字与参数之后、读数之前，固定宽、只切 visibility——按钮的位置与读数无关。
 * vitest 跑在 node 环境（没有 jsdom），这里用一个只够图例用的小假 DOM：能解析拼出来的 HTML、查 [attr] / .cls、改文字节点 */
// @ts-expect-error Web 的 tsconfig 不带 @types/node；vitest 把 .css?raw 处理成空串，只能直接读文件（同 b-contrast.test.ts）
import { readFileSync } from 'node:fs'
import { describe, expect, it, vi } from 'vitest'

vi.mock('../src/market/rest', () => ({ klines: vi.fn(async () => ({ ok: false, bars: [] })) }))
const { TVChart } = await import('../src/chart/chart')
const { FULL } = await import('../src/chart/panes')
const { patchVals } = await import('../src/chart/legendDom')
type Any = Record<string, unknown>

// ------------------------------------------------------------ 小假 DOM
class FText { constructor(public data: string) {} }
class FEl {
  attrs = new Map<string, string>()
  kids: (FEl | FText)[] = []
  style: Record<string, string> = {}
  writes = 0
  constructor(public tag = 'div') {}
  get children(): FEl[] { return this.kids.filter((k): k is FEl => k instanceof FEl) }
  get firstChild(): FEl | FText | null { return this.kids[0] ?? null }
  get lastElementChild(): FEl | null { const c = this.children; return c[c.length - 1] ?? null }
  get className(): string { return this.attrs.get('class') ?? '' }
  set className(v: string) { this.attrs.set('class', v) }
  get classList() {
    return {
      contains: (c: string) => this.className.split(/\s+/).includes(c),
      toggle: (c: string, on: boolean) => { const s = new Set(this.className.split(/\s+/).filter(Boolean)); if (on) s.add(c); else s.delete(c); this.className = [...s].join(' ') },
    }
  }
  get dataset(): Record<string, string | undefined> {
    return new Proxy({}, {
      get: (_t, k: string) => this.attrs.get('data-' + k.replace(/[A-Z]/g, m => '-' + m.toLowerCase())),
      set: (_t, k: string, v: string) => { this.attrs.set('data-' + k.replace(/[A-Z]/g, m => '-' + m.toLowerCase()), v); return true },
    })
  }
  setAttribute(k: string, v: string): void { this.attrs.set(k, v) }
  get textContent(): string { return this.kids.map(k => k instanceof FText ? k.data : k.textContent).join('') }
  set textContent(v: string) { this.kids = [new FText(v)] }
  set innerHTML(h: string) { this.writes++; this.kids = parse(h) }
  get innerHTML(): string { return '' }
  all(): FEl[] { const out: FEl[] = []; for (const c of this.children) { out.push(c); out.push(...c.all()) } return out }
  matches(sel: string): boolean {
    const m = /^\[([\w-]+)(?:="([^"]*)")?\]$/.exec(sel)
    if (m) return this.attrs.has(m[1]) && (m[2] === undefined || this.attrs.get(m[1]) === m[2])
    if (sel.startsWith('.')) return this.classList.contains(sel.slice(1))
    return this.tag === sel
  }
  querySelectorAll(sel: string): FEl[] { return this.all().filter(e => e.matches(sel)) }
  querySelector(sel: string): FEl | null { return this.querySelectorAll(sel)[0] ?? null }
}
const VOID = new Set(['path', 'circle', 'line', 'rect', 'polyline', 'polygon', 'br', 'img', 'input'])
function parse(h: string): (FEl | FText)[] {
  const root = new FEl('#root'), stack = [root]
  const re = /<\/?([a-zA-Z][\w-]*)((?:\s+[\w:-]+(?:="[^"]*")?)*)\s*(\/?)>|([^<]+)/g
  for (let m; (m = re.exec(h));) {
    const top = stack[stack.length - 1]
    if (m[4] !== undefined) { if (m[4].trim()) top.kids.push(new FText(m[4])); continue }
    if (m[0].startsWith('</')) { stack.pop(); continue }
    const el = new FEl(m[1].toLowerCase())
    for (const a of m[2].matchAll(/([\w:-]+)(?:="([^"]*)")?/g)) el.attrs.set(a[1], a[2] ?? '')
    top.kids.push(el)
    if (!m[3] && !VOID.has(el.tag)) stack.push(el)
  }
  return root.kids
}

// ------------------------------------------------------------ 假图表
function chart(legend: 'full' | 'dense') {
  const bars = Array.from({ length: 5 }, (_, k) => ({ t: 1_700_000_000_000 + k * 36e5, o: 100 + k, h: 102 + k, l: 98 + k, c: 101 + k, v: 1000 }))
  const el = new FEl()
  const ch = Object.assign(Object.create(TVChart.prototype), {
    bars, legendEl: el, replay: null, cross: null, extCross: null, stale: false, walls: null, compare: null,
    meta: { dec: 2, title: 'BTCUSDT', sub: '1小时 · 币安', badge: '' },
    ind: { ma: true, ema: false, boll: false, vol: true, subs: [] },
    params: {}, hidden: new Set<string>(), calcStale: false,
    _series: { ma: [[1, 2, 3, 4, 5]] },
    deg: { ...FULL, legend }, _panes: [],
  } as Any) as InstanceType<typeof TVChart> & Any
  ch.renderPaneLegends = () => {}
  return { ch, el, bars }
}
const texts = (el: FEl): string[] => el.querySelectorAll('[data-v]').map(b => b.textContent)

describe('patchVals：读数只改文字节点', () => {
  it('格数与标签不变：格子、<b>、文字节点都还是原来那几个对象', () => {
    const box = new FEl('span')
    patchVals(box as unknown as HTMLElement, [['#f00', '上', '1.00'], ['#0f0', '', '2.00', 'up']])
    const cells = box.children, tn = cells.map(c => c.lastElementChild!.firstChild)
    expect(box.writes).toBe(1)
    for (let k = 0; k < 50; k++) patchVals(box as unknown as HTMLElement, [['#f00', '上', (1 + k / 7).toFixed(2)], ['#0f0', '', (2 + k * 1234.5).toFixed(2), k % 2 ? 'down' : 'up']])
    expect(box.writes).toBe(1)
    expect(box.children).toEqual(cells)
    box.children.forEach((c, j) => expect(c.lastElementChild!.firstChild).toBe(tn[j]))
    expect(box.textContent).toBe('上8.0060492.50')
    expect(box.children[1].className).toBe('down')
  })
  it('标签变了（带前缀的线这一根没值）才重建这一个读数盒', () => {
    const box = new FEl('span')
    patchVals(box as unknown as HTMLElement, [['', '上', '1'], ['', '下', '2']])
    patchVals(box as unknown as HTMLElement, [['', '下', '2']])
    expect(box.writes).toBe(2)
  })
})

describe.each(['full', 'dense'] as const)('主图图例（%s）：推送 / 十字线 / 隐藏都不换节点', legend => {
  it('推送改最后一根、十字线来回移动：外壳只写一次，指标行与工具按钮是同一批对象，读数跟着变', () => {
    const { ch, el, bars } = chart(legend)
    let idx = 4
    ch.legendIndex = () => idx
    ch.renderLegend()
    const rows = el.querySelectorAll('[data-lid]'), btns = el.querySelectorAll('[data-act="toggle"]')
    expect(rows.map(r => r.dataset.lid)).toEqual(['ma', 'vol'])
    const before = texts(el).join('|')
    for (let k = 0; k < 40; k++) {
      bars[4] = { ...bars[4], c: 105 + k * 0.37, h: 110 + k, v: 1000 + k * 977 }
      idx = k % 3 ? 4 : k % 4   // 十字线在历史 K 线与最新一根之间来回
      ch.renderLegend()
    }
    idx = 4; ch.renderLegend()
    expect(el.writes).toBe(1)
    expect(el.querySelectorAll('[data-lid]')).toEqual(rows)
    el.querySelectorAll('[data-lid]').forEach((r, k) => expect(r).toBe(rows[k]))
    el.querySelectorAll('[data-act="toggle"]').forEach((b, k) => expect(b).toBe(btns[k]))
    expect(texts(el).join('|')).not.toBe(before)
    expect(texts(el).join('|')).toContain('119.43')
  })
  it('结构：行里只有 lhead 与读数盒两块在流中，工具区在 lhead 末尾（绝对定位、出在整行右缘，见样式用例）', () => {
    const { ch, el } = chart(legend)
    ch.renderLegend()
    for (const row of el.querySelectorAll('[data-lid]')) {
      const kids = row.children
      expect(kids.map(k => k.className)).toEqual(['lhead', 'vals num'])
      const head = kids[0].children.map(k => k.className)
      expect(head[0]).toBe('ind-name')
      expect(head[head.length - 1]).toBe('tools')
    }
  })
  it('点「隐藏」：不重建外壳，就地切类与图标；再点回来也一样', () => {
    const { ch, el } = chart(legend)
    ch.renderLegend()
    const row = el.querySelector('[data-lid="ma"]')!, btn = row.querySelector('[data-act="toggle"]')!
    ;(ch.hidden as Set<string>).add('ma'); ch.renderLegend()
    expect(el.writes).toBe(1)
    expect(row.classList.contains('hidden-ind')).toBe(true)
    expect(btn.dataset.tip).toBe('显示')
    ;(ch.hidden as Set<string>).delete('ma'); ch.renderLegend()
    expect(el.writes).toBe(1)
    expect(row.classList.contains('hidden-ind')).toBe(false)
    expect(btn.dataset.tip).toBe('隐藏')
    expect(el.querySelector('[data-lid="ma"]')).toBe(row)
  })
  it('换参数（结构变了）才重建', () => {
    const { ch, el } = chart(legend)
    ch.renderLegend()
    ;(ch as Any).params = { ma: { p1: 30 } }
    ;(ch as Any).paramCell = (id: string) => id === 'ma' ? '<span class="ind-param">30</span>' : ''
    ch.renderLegend()
    expect(el.writes).toBe(2)
  })
})

describe('样式：工具区固定宽、只切 visibility，不改排版', () => {
  const css = readFileSync(new URL('../src/styles/app.css', import.meta.url), 'utf8')
  it('图例与副图图例的工具区绝对定位、默认 visibility:hidden，悬停只改 visibility', () => {
    const rule = /\.legend \.tools, \.pane-legend \.tools \{([^}]*)\}/.exec(css)?.[1] ?? ''
    expect(rule).toContain('position: absolute')
    expect(rule).toContain('visibility: hidden')
    expect(css).not.toMatch(/\.tools \{[^}]*display: none/)
    expect(css).not.toMatch(/:hover \.tools \{[^}]*display:/)
    expect(css).not.toMatch(/\.dense:hover \.dchip \{[^}]*display: flex/)
  })
  it('2026-10-10 审查 C6：按钮锚在整行右缘（读数后面），不再叠在读数开头；lhead 不是定位祖先', () => {
    // DOM：行里在流中的只有 lhead 与读数盒，工具区在 lhead 里且绝对定位——它不占位，读数紧跟参数，悬停前后位置一样
    const head = /\.legend \.lhead, \.pane-legend \.lhead \{([^}]*)\}/.exec(css)?.[1] ?? ''
    expect(head).not.toContain('position')
    // 定位祖先是整行（并排的 dchip 是它自己），工具区从行的右缘起（压进行的右内边距，和行之间没有缝）
    expect(css).toMatch(/\.legend \.lrow, \.pane-legend \.lrow, \.legend \.lrow\.dense \.dchip \{ position: relative; \}/)
    const rule = /\.legend \.tools, \.pane-legend \.tools \{([^}]*)\}/.exec(css)?.[1] ?? ''
    expect(rule).toContain('left: calc(100% - var(--s1))')
    expect(rule).not.toContain('margin-left')
    // 行的右内边距 --s2 比按钮压进去的 --s1 宽：按钮和行之间没有缝
    expect(css).toMatch(/\.legend \.lrow \{[^}]*padding-right: var\(--s2\)/)
    expect(css).toMatch(/\.pane-legend \.lrow \{[^}]*padding-right: var\(--s2\)/)
  })
  it('并排（dense）：按钮出在块右缘外，悬停期间后面那一块按按钮颗数让位（2–4 颗 × --h-sm），被悬停这一块自己不变宽', () => {
    expect(css).toMatch(/\.legend \.lrow\.dense \.dchip \.tools \{ left: 100%; \}/)
    expect(css).toMatch(/\.dchip:hover \+ \.dchip \{ margin-left: calc\(2 \* var\(--h-sm\) \+ var\(--s1\) - var\(--s3\)\); \}/)
    for (const n of [3, 4]) expect(css).toContain(`.dchip:hover:has(.tools > :nth-child(${n})) + .dchip { margin-left: calc(${n} * var(--h-sm) + var(--s1) - var(--s3)); }`)
    // 按钮宽就是 --h-sm，让位的算式才对得上
    expect(css).toMatch(/\.legend \.tools \.ibtn, \.pane-legend \.tools \.ibtn \{ width: var\(--h-sm\);/)
    // 被悬停的块不加内边距 / 外边距（加了它在行尾会折到下一行，读数跟着跳）
    expect(css).not.toMatch(/\.dchip:hover \{[^}]*(padding|margin)/)
  })
  it('读数等宽数字', () => {
    expect(css).toMatch(/\.legend \[data-v\], \.pane-legend \[data-v\] \{ font-variant-numeric: tabular-nums; \}/)
  })
})
