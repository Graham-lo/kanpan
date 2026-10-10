// 电脑网页右侧栏重做（2026-10-10 定版原型 §3，审查 A1 / C1）：自选按分类分节、组头折叠 / 数量 / 吸顶、
// 胶囊只做跳转、当前品种强调、行尾悬停「铃 · 星」、右键加创建提醒 / 记一笔 / 加入对比 / 移到分类
import { describe, expect, it } from 'vitest'
import { st } from '../src/app/store'
import { S, TABS, type Kind } from '../src/market'
import { HL } from '../src/terms'
import { installWatch, widgetWatch, quickHTML, rowMenu, watchVisible } from '../src/watch/widget'
import { FOLD_KEY, loadFold, saveFold, watchSections, navRows, sectionAt, dropAcross, moveToTab } from '../src/watch/sections'
import type { MenuItem } from '../src/ui/overlay'

const W = (o: Partial<Record<Kind, string[]>>): Record<Kind, string[]> => ({ crypto: [], us: [], idx: [], com: [], ...o })
const memStore = () => { const m = new Map<string, string>(); return { m, getItem: (k: string) => m.get(k) ?? null, setItem: (k: string, v: string) => { m.set(k, v) } } }

describe('分节', () => {
  it('按分类顺序连续列出、空的不出，数量是本节品种数', () => {
    const s = watchSections(W({ crypto: ['BTCUSDT', 'ETHUSDT'], com: ['XAUUSDT'] }), TABS, null, new Set())
    expect(s.map(x => [x.tab, x.count, x.rows])).toEqual([['crypto', 2, ['BTCUSDT', 'ETHUSDT']], ['com', 1, ['XAUUSDT']]])
  })
  it('空格取消后淡着留下的那一行还在原位，但不算进数量；一节只剩它也照样出', () => {
    const s = watchSections(W({ crypto: ['BTCUSDT', 'SOLUSDT'], us: [] }), TABS, { k: 'ETHUSDT', i: 1, tab: 'crypto' }, new Set())
    expect(s[0].rows).toEqual(['BTCUSDT', 'ETHUSDT', 'SOLUSDT'])
    expect(s[0].count).toBe(2)
    const only = watchSections(W({}), TABS, { k: 'TSLAUSDT', i: 0, tab: 'us' }, new Set())
    expect(only.map(x => [x.tab, x.count, x.rows])).toEqual([['us', 0, ['TSLAUSDT']]])
  })
  it('键盘 ↑ ↓ 跨节连续走，收起的节跳过', () => {
    const s = watchSections(W({ crypto: ['A', 'B'], us: ['C'], com: ['D'] }), TABS, null, new Set<Kind>(['us']))
    expect(navRows(s)).toEqual(['A', 'B', 'D'])
  })
})

describe('折叠只记本机一个键', () => {
  it('存取往返；坏值 / 陌生分类一律丢掉', () => {
    const m = memStore()
    saveFold(new Set<Kind>(['us', 'com']), m)
    expect(m.m.get(FOLD_KEY)).toBe('["us","com"]')
    expect([...loadFold(m)]).toEqual(['us', 'com'])
    m.m.set(FOLD_KEY, '["us","zzz",3]'); expect([...loadFold(m)]).toEqual(['us'])
    m.m.set(FOLD_KEY, '{oops'); expect(loadFold(m).size).toBe(0)
    expect(loadFold(undefined).size).toBe(0)
  })
})

describe('胶囊跟着滚动亮到当前那一节（scroll-spy）', () => {
  const heads = [{ tab: 'crypto' as Kind, top: 0 }, { tab: 'us' as Kind, top: 400 }, { tab: 'com' as Kind, top: 700 }]
  it('组头到顶（或在顶上）的最后一节', () => {
    expect(sectionAt(heads, 0)).toBe('crypto')
    expect(sectionAt(heads, 399)).toBe('us')       // 差 1 px 也算到顶（滚动取整）
    expect(sectionAt(heads, 650)).toBe('us')
    expect(sectionAt(heads, 9999)).toBe('com')
    expect(sectionAt([], 0)).toBeNull()
  })
  it('滚到底：最后一节组头到不了顶，刚点的那一节只要组头露着就留它亮；没露着照常', () => {
    const end = { viewH: 480, scrollH: 863, keep: 'com' as Kind }     // 最多滚到 383
    expect(sectionAt(heads, 383, end)).toBe('com')
    expect(sectionAt(heads, 383, { ...end, keep: 'crypto' })).toBe('com')  // 刚点的不在视口里：到底亮最后一节
    expect(sectionAt(heads, 200, end)).toBe('crypto')               // 没到底：照组头到顶算
  })
})

describe('拖动排序可以跨节', () => {
  it('同一节里只重排', () => {
    expect(dropAcross(W({ crypto: ['A', 'B', 'C'] }), 'crypto', 'crypto', ['A', 'B', 'C'], 'C', 'A', false)).toEqual({ crypto: ['C', 'A', 'B'] })
    expect(dropAcross(W({ crypto: ['A', 'B', 'C'] }), 'crypto', 'crypto', ['A', 'B', 'C'], 'A', 'C', true)).toEqual({ crypto: ['B', 'C', 'A'] })
  })
  it('拖到别的节 = 移到那个分类、落在松手的位置', () => {
    expect(dropAcross(W({ crypto: ['A', 'B'], us: ['X', 'Y'] }), 'crypto', 'us', ['X', 'Y'], 'B', 'Y', false)).toEqual({ crypto: ['A'], us: ['X', 'B', 'Y'] })
  })
  it('拖到自己身上 / 不在源分类里：不动', () => {
    expect(dropAcross(W({ crypto: ['A'] }), 'crypto', 'crypto', ['A'], 'A', 'A', false)).toBeNull()
    expect(dropAcross(W({ crypto: ['A'] }), 'crypto', 'crypto', ['A'], 'Q', 'A', false)).toBeNull()
  })
  it('右键「移到分类」：接到目标末尾', () => {
    expect(moveToTab(W({ crypto: ['A', 'B'], com: ['G'] }), 'B', 'crypto', 'com')).toEqual({ crypto: ['A'], com: ['G', 'B'] })
    expect(moveToTab(W({ crypto: ['A'] }), 'A', 'crypto', 'crypto')).toBeNull()
  })
})

describe('自选栏渲染', () => {
  let cur = 'ETHUSDT'
  installWatch({
    openSymbol() {}, renderPanel() {}, refreshStreams() {}, openSearch() {},
    current: () => cur, activeIndex: () => 0, cellCount: () => 1, collapsed: () => false, collapseBtn: () => '',
    createAlert() {}, note() {}, toggleCompare() {}, inCompare: () => false, toggleWatch() {},
  })
  const setup = (): void => {
    S.symbols.clear()
    st.watch.crypto = ['BTCUSDT', 'ETHUSDT']; st.watch.us = ['TSLAUSDT']; st.watch.idx = []; st.watch.com = ['XAUUSDT']
  }
  it('每节一个 tbody、组头带数量与展开状态；胶囊只出有品种的分类、带 data-tab 用来跳转；没有表头行', () => {
    setup(); globalThis.localStorage?.removeItem?.(FOLD_KEY)
    const html = widgetWatch()
    expect(html.match(/<tbody data-grp="(\w+)"/g)!.map(x => x.slice(17, -1))).toEqual(['crypto', 'us', 'com'])
    expect(html).toContain('data-fold="crypto"')
    expect(html).toMatch(/aria-expanded="true" aria-label="加密 2 · 收起"/)
    expect(html.match(/<button class="chip" role="tab" data-tab="(\w+)"/g)!.length).toBe(3)
    expect(html).toContain('data-tab="crypto" aria-pressed="true" aria-label="加密 2">加密</button>')
    expect(html).not.toContain('data-tab="idx"')
    expect(html).not.toContain('<thead')
    expect(html.match(/<tr data-sym="([^"]+)"/g)!.map(x => x.slice(14, -1))).toEqual(['BTCUSDT', 'ETHUSDT', 'TSLAUSDT', 'XAUUSDT'])
    expect(watchVisible()).toEqual(['BTCUSDT', 'ETHUSDT', 'TSLAUSDT', 'XAUUSDT'])
  })
  it('当前品种那一行带 sel（强调软底），别的行不带', () => {
    setup(); cur = 'TSLAUSDT'
    const html = widgetWatch()
    expect(html).toMatch(/<tr data-sym="TSLAUSDT" data-tab="us" [^>]*class="sel /)
    expect(html).toMatch(/<tr data-sym="BTCUSDT" data-tab="crypto" [^>]*class=" /)
  })
  it('涨跌幅在一个带 data-f 的 span 里（快捷块悬停时顶替它，推送照常改字）', () => {
    setup()
    expect(widgetWatch()).toContain('<td class="wc-pct"><span class="num  price-live" data-f="pct">')
  })
})

describe('行尾悬停快捷块「铃 · 星」', () => {
  it('铃 = 创建提醒；星按是否在自选里切实心 / 空心与文案', () => {
    const on = quickHTML('BTCUSDT', true), off = quickHTML('BTCUSDT', false)
    expect(on).toContain('data-wq="alert" data-k="BTCUSDT"')
    expect(on).toContain(`aria-label="${HL.sideAlert}"`)
    expect(on).toContain(`class="wv-q on" data-wq="star" data-k="BTCUSDT" aria-pressed="true" aria-label="${HL.sideWatchOff}"`)
    expect(off).toContain(`class="wv-q" data-wq="star" data-k="BTCUSDT" aria-pressed="false" aria-label="${HL.addFavorite}"`)
    expect(on).not.toEqual(off)
  })
})

describe('右键菜单', () => {
  const calls: string[] = []
  const run = { open: () => calls.push('open'), alert: () => calls.push('alert'), note: () => calls.push('note'), compare: () => calls.push('cmp'), toggle: () => calls.push('toggle'), remove: () => calls.push('rm'), move: (t: Kind) => calls.push('move:' + t) }
  const labels = (m: MenuItem[]): string[] => m.map(x => x === '-' ? '-' : 'header' in x && x.header ? `#${x.header}` : (x as { label: string }).label)
  const base = { ghost: false, tab: 'crypto' as Kind, multi: false, target: '在图上打开', current: 'BTCUSDT', compared: false, tabs: TABS.filter(([t]) => t !== 'idx') }
  it('打开 · 创建提醒 · 记一笔 · 加入对比 · 移到分类（别的几类）· 移出自选', () => {
    const m = rowMenu('ETHUSDT', base, run)
    expect(labels(m).slice(1)).toEqual(['在图上打开', HL.sideAlert, HL.sideNote, HL.sideCompare, '-', `#${HL.sideMoveTo}`, '美股', '大宗', '-', HL.sideWatchOff])
    for (const x of m) if (x !== '-' && 'run' in x && x.run) x.run()
    expect(calls).toEqual(['open', 'alert', 'note', 'cmp', 'move:us', 'move:com', 'rm'])
  })
  it('已在对比里写「移出对比」；当前品种不能对比自己；淡行只给「加回自选」、不给移到分类', () => {
    const m = rowMenu('ETHUSDT', { ...base, compared: true }, run)
    expect(labels(m)).toContain(HL.sideCompareOff)
    const self = rowMenu('BTCUSDT', base, run).find(x => x !== '-' && 'label' in x && x.label === HL.sideCompare) as { disabled?: boolean }
    expect(self.disabled).toBe(true)
    const g = labels(rowMenu('ETHUSDT', { ...base, ghost: true }, run))
    expect(g).not.toContain(`#${HL.sideMoveTo}`)
    expect(g.at(-1)).toBe('加回自选')
  })
})
