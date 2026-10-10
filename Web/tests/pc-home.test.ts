/* 电脑版首页（2026-10-10 定板原型第 2 节）：四栏折行、榜单展开、药丸方向、板块精简榜、冷启动落首页 */
import { describe, it, expect, vi } from 'vitest'
import { MID_MIN, RANK_HEAD_H, RANK_ROWS, RANK_ROW_H, WIDE_MIN, beatParts, rankRowsFor, homeCols, pillOf, rankView, sectorLines } from '../src/home/layout'
import { landingPage, noteQueryKeys } from '../src/home/landing'
import { isThin, marketReturn, type Quotes, type SectorStat } from '../src/sectors/aggregate'
import { applyQueryTo } from '../src/app/query'
import { hydrate } from '../src/app/store'

describe('四栏折行', () => {
  it('2560 / 1800 四栏，1799 / 1300 三栏（板块并到持仓下方），1299 以下两栏两行', () => {
    expect(homeCols(2560)).toBe(4)
    expect(homeCols(WIDE_MIN)).toBe(4)
    expect(homeCols(WIDE_MIN - 1)).toBe(3)
    expect(homeCols(1440)).toBe(3)
    expect(homeCols(MID_MIN)).toBe(3)
    expect(homeCols(MID_MIN - 1)).toBe(2)
    expect(homeCols(1024)).toBe(2)
  })
  it('量不到宽度（页面藏着是 0）按四栏', () => {
    expect(homeCols(0)).toBe(4)
    expect(homeCols(NaN)).toBe(4)
  })
})

describe('榜单默认 8 行、全部 / 收起', () => {
  const rows = Array.from({ length: 20 }, (_, i) => i)
  it('收着：前 8 行 + 「全部」', () => {
    const v = rankView(rows, false)
    expect(RANK_ROWS).toBe(8)
    expect(v.rows).toEqual([0, 1, 2, 3, 4, 5, 6, 7])
    expect(v.more).toBe('all')
  })
  it('展开：全部行 + 「收起」', () => {
    const v = rankView(rows, true)
    expect(v.rows).toHaveLength(20)
    expect(v.more).toBe('collapse')
  })
  it('不超过 8 行的榜不给链接，展开状态也不影响', () => {
    expect(rankView(rows.slice(0, 8), false)).toEqual({ rows: rows.slice(0, 8), more: null })
    expect(rankView(rows.slice(0, 3), true)).toEqual({ rows: [0, 1, 2], more: null })
    expect(rankView([], false)).toEqual({ rows: [], more: null })
  })
  it('按栏高给的行数照算：多于默认就多切，展开照旧全给', () => {
    const many = Array.from({ length: 30 }, (_, i) => i)
    expect(rankView(many, false, 15)).toEqual({ rows: many.slice(0, 15), more: 'all' })
    expect(rankView(many.slice(0, 15), false, 15).more).toBeNull()
    expect(rankView(many, true, 15)).toEqual({ rows: many, more: 'collapse' })
  })
})

describe('rankRowsFor 按栏高算每张榜的行数', () => {
  it('两张榜各占半栏、减榜头、整行向下取整', () => {
    // 1440 高全屏：栏体约 1328 → 每张 664 − 46 = 618 → 15 行
    expect(rankRowsFor(1328)).toBe(15)
    expect(rankRowsFor(2 * (RANK_HEAD_H + 20 * RANK_ROW_H))).toBe(20)
    expect(rankRowsFor(2 * (RANK_HEAD_H + 20 * RANK_ROW_H) - 1)).toBe(19)
  })
  it('最少 8 行，量不到高度也给 8', () => {
    expect(rankRowsFor(0)).toBe(RANK_ROWS)
    expect(rankRowsFor(NaN)).toBe(8)
    expect(rankRowsFor(-50)).toBe(8)
    expect(rankRowsFor(400)).toBe(8)
  })
  it('榜数与下限可调', () => {
    expect(rankRowsFor(RANK_HEAD_H + 12 * RANK_ROW_H, 1)).toBe(12)
    expect(rankRowsFor(400, 2, 3)).toBe(3)
    expect(rankRowsFor(1000, 0)).toBe(8)
  })
})

describe('涨跌药丸', () => {
  it('一位小数、负号 U+2212、颜色跟写出来的号走', () => {
    expect(pillOf(12.44)).toEqual({ text: '+12.4%', cls: 'up' })
    expect(pillOf(-6.3)).toEqual({ text: '−6.3%', cls: 'down' })
    expect(pillOf(-0.04)).toEqual({ text: '+0.0%', cls: 'up' })
  })
  it('没有数是灰的「—」', () => {
    expect(pillOf(null)).toEqual({ text: '—', cls: 'none' })
    expect(pillOf(NaN)).toEqual({ text: '—', cls: 'none' })
  })
})

describe('板块精简榜', () => {
  const q = (base: string, pct: number) => [base, { base, pct, quoteVolume: 1e6, price: 1 }] as const
  it('大盘：板块页同一条基准（marketReturn），落在成员涨跌之间', () => {
    const quotes: Quotes = new Map([q('BTC', 2), q('ETH', -1), q('SOL', 4), q('DOGE', 8)])
    const m = marketReturn('crypto', quotes, [{ id: 'x', name: 'x', members: ['BTC', 'ETH', 'SOL', 'DOGE'] }])
    expect(m).not.toBeNull()
    expect(m!).toBeGreaterThan(-1); expect(m!).toBeLessThan(8)
  })
  const st = (id: string, pct: number, memberCount = 5): SectorStat => ({
    id, name: id, market: 'crypto', pct, memberCount, staticCount: memberCount, quoteVolume: 0, isFallback: false, breadth: 0.5, upCount: 0, frontier: [], jackknife: null,
  })
  it('不到三家的不上；跑赢 / 落后 = 板块 − 大盘；强弱条按最大幅度归一、从中线往两边画', () => {
    const lines = sectorLines([st('ai', 6), st('meme', -3), st('thin', 9, 2)], 2, isThin)
    expect(lines.map(l => l.id)).toEqual(['ai', 'meme'])
    expect(lines[0].beat).toBeCloseTo(4)
    expect(lines[1].beat).toBeCloseTo(-5)
    expect(lines[0].bar).toEqual({ left: 50, width: 50, up: true })
    expect(lines[1].bar).toEqual({ left: 25, width: 25, up: false })
  })
  it('没有大盘时跑赢写不出（null）；全是 0 不画条', () => {
    const lines = sectorLines([st('a', 0), st('b', 0)], null, isThin)
    expect(lines.every(l => l.beat === null && l.bar.width === 0)).toBe(true)
  })
  it('「跑赢 3.9%」/「落后 1.1%」，舍成 0 的算跑赢', () => {
    expect(beatParts(3.94)).toEqual({ ahead: true, v: '3.9%' })
    expect(beatParts(-1.06)).toEqual({ ahead: false, v: '1.1%' })
    expect(beatParts(-0.04)).toEqual({ ahead: true, v: '0.0%' })
  })
})

describe('冷启动落哪页', () => {
  it('不带参数、只带深浅 / 皮肤：首页；带品种 / 周期 / 布局 / 侧栏的深链：图表', () => {
    expect(landingPage([])).toBe('home')
    expect(landingPage(['theme', 'skin'])).toBe('home')
    expect(landingPage(['s'])).toBe('chart')
    expect(landingPage(['theme', 'i'])).toBe('chart')
    expect(landingPage(['layout'])).toBe('chart')
    expect(landingPage(['panel'])).toBe('chart')
  })
  it('app/query 落参数时记下用过的键，外壳不传参时读它', () => {
    applyQueryTo(hydrate({}), '?s=ETHUSDT&theme=dark')
    expect(landingPage()).toBe('chart')
    applyQueryTo(hydrate({}), '?theme=dark')
    expect(landingPage()).toBe('home')
    noteQueryKeys([])
    expect(landingPage()).toBe('home')
  })
})

describe('外壳：首页进导航、地址不带 #页名 时落首页', async () => {
  vi.doMock('../src/ui/dom', () => ({ $: () => ({ onclick: null, innerHTML: '', classList: { toggle: () => {} } }), $$: () => [], I: () => '', esc: (s: string) => s }))
  vi.doMock('../src/ui/overlay', () => ({ hideTip: () => {} }))
  vi.doMock('../src/app/store', () => ({ st: { page: 'chart' }, save: () => {} }))
  vi.doMock('../src/account/session', () => ({ session: { user: null } }))
  const loc = { hash: '' }
  const replaced: string[] = []
  vi.stubGlobal('location', loc)
  vi.stubGlobal('history', { state: null, replaceState: (_s: unknown, _t: string, u: string) => { replaced.push(u); loc.hash = u } })
  vi.stubGlobal('addEventListener', () => {})
  const shell = await import('../src/app/shell')
  it('PAGES 首页排第一', () => {
    expect(shell.PAGES).toEqual(['home', 'chart', 'sectors', 'review', 'me'])
  })
  it('冷启动没有 #页名 → #home；已有 #页名不动', () => {
    noteQueryKeys([])
    shell.installShell()
    expect(replaced).toEqual(['#home'])
    replaced.length = 0; loc.hash = '#sectors'
    shell.installShell()
    expect(replaced).toEqual([])
  })
  it('带品种参数的深链（参数已被拿掉）→ #chart', () => {
    replaced.length = 0; loc.hash = ''
    noteQueryKeys(['s', 'i'])
    shell.installShell()
    expect(replaced).toEqual(['#chart'])
    noteQueryKeys([])
  })
  it('不认的 #页名照旧换成图表', () => {
    replaced.length = 0; loc.hash = '#foo'
    shell.go('foo', false)
    expect(replaced).toEqual(['#chart'])
  })
})
