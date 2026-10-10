/* 手机网页版 · 首页四段（异动 · 涨跌 · 持仓 · 板块，2026-10-10）
 *   底栏收成四格、#sectors 落到首页「板块」段；涨跌 / 持仓两页各自一个窗口（旧档迁移）；
 *   波动行（急涨 / 急跌）的解析与事实句；服务端还没上新字段（没有波动行、减仓榜 400、缺字段）时不出错 */
import { afterEach, describe, expect, it, vi } from 'vitest'
import { parseBoard, parseMarketBoard, marketBoardUrl, type BoardRow } from '../src/highlights/api'
import { boardFact, moveFact, movePill } from '../src/highlights/format'
import { RANK_KINDS, filterRows, focusOf, mergeBoard, parseHomeLocal } from '../src/highlights/home'
import { HL } from '../src/terms'
import shellSource from '../src/m/app/shell.ts?raw'
import homeSource from '../src/m/pages/home.ts?raw'
import homeCss from '../src/m/styles/home.css?raw'

afterEach(() => { vi.unstubAllGlobals(); vi.resetModules() })

async function loadShell(hash = '#chart') {
  const mem = new Map<string, string>()
  vi.stubGlobal('localStorage', { getItem: (k: string) => mem.get(k) ?? null, setItem: (k: string, v: string) => { mem.set(k, v) }, removeItem: (k: string) => { mem.delete(k) } })
  const pageEl = { classList: { contains: () => true, toggle: () => {} }, scrollTop: 0 }
  vi.stubGlobal('document', { getElementById: () => pageEl, addEventListener: () => {}, removeEventListener: () => {} })
  const loc = { hash }
  vi.stubGlobal('location', loc)
  vi.stubGlobal('history', { replaceState: (_s: unknown, _t: string, url: string) => { loc.hash = url } })
  vi.resetModules()
  const shell = await import('../src/m/app/shell')
  const store = await import('../src/m/app/store')
  const seg = await import('../src/m/app/homeSeg')
  store.st.page = 'chart'
  return { shell, store, seg, loc }
}

describe('底栏四格与 #sectors', () => {
  it('底栏只剩 首页 · 图表 · 自选 · 我的', async () => {
    const { store } = await loadShell()
    expect(store.PAGES).toEqual(['home', 'chart', 'favorites', 'me'])
  })
  it('go("sectors")（深链 / 旧来路）落到首页，并选中「板块」段；地址摆成 #home', async () => {
    const { shell, store, seg, loc } = await loadShell()
    const h = { show: vi.fn(), hide: vi.fn() }
    shell.registerPage('home', h)
    const seen: string[] = []
    seg.onHomeSeg(s => seen.push(s))
    shell.go('sectors')
    expect(store.st.page).toBe('home')
    expect(seg.homeSeg()).toBe('sectors')
    expect(seen).toEqual(['sectors'])
    expect(loc.hash).toBe('#home')
    expect(h.show).toHaveBeenCalledTimes(1)
    // 已经站在首页：再来一次 #sectors 只换段、不重进页
    seg.setHomeSeg('moves')
    shell.go('sectors')
    expect(seg.homeSeg()).toBe('sectors')
    expect(h.show).toHaveBeenCalledTimes(1)
  })
  it('冷启动：分段回「异动」；地址带 #sectors 时壳在认页前先选「板块」段', async () => {
    const { seg } = await loadShell()
    expect(seg.homeSeg()).toBe('moves')
    expect(seg.segOfRoute('sectors')).toBe('sectors')
    expect(seg.segOfRoute('favorites')).toBeNull()
    expect(shellSource).toMatch(/segOfRoute\(fromHash\)/)
    expect(shellSource).not.toMatch(/sectors: '板块分类'/)
  })
  it('不认得的段不换', async () => {
    const { seg } = await loadShell()
    seg.setHomeSeg('nope' as never)
    expect(seg.homeSeg()).toBe('moves')
  })
})

describe('涨跌 / 持仓两页各自的窗口', () => {
  it('出厂都是 4 时、分类「全部」；不认得的值不用', () => {
    expect(parseHomeLocal(null)).toEqual({ chip: 'all', win: { change: '4h', oi: '4h' } })
    expect(parseHomeLocal({ chip: 'x', win: { change: '2h', oi: 7 } })).toEqual({ chip: 'all', win: { change: '4h', oi: '4h' } })
  })
  it('两页互不牵连', () => {
    expect(parseHomeLocal({ chip: 'move', win: { change: '1h', oi: '24h' } })).toEqual({ chip: 'move', win: { change: '1h', oi: '24h' } })
  })
  it('旧档（榜单一页三张卡）迁过来：涨幅卡的窗口给涨跌页、持仓卡的给持仓页；旧的「榜单」段不再记', () => {
    const v = parseHomeLocal({ seg: 'board', chip: 'oi', win: { oi: '1h', gainers: '24h', losers: '4h' } })
    expect(v).toEqual({ chip: 'oi', win: { change: '24h', oi: '1h' } })
    expect('seg' in v).toBe(false)
  })
  it('涨跌 = 涨幅榜 + 跌幅榜，持仓 = 增仓榜 + 减仓榜（kind=oidown）', () => {
    expect(RANK_KINDS).toEqual({ change: ['gainers', 'losers'], oi: ['oi', 'oidown'] })
    expect(marketBoardUrl('oidown', '4h')).toBe('/v1/market/board?kind=oidown&window=4h')
    const m = parseMarketBoard({ generatedAtMs: 1, rows: [{ base: 'A', changePct: -6.4, oiUsd: 2.1e7, price: 3 }, { base: 'B', changePct: 'x' }] })!
    expect(m.rows).toEqual([{ base: 'A', changePct: -6.4, oiUsd: 2.1e7, price: 3 }])
  })
})

describe('波动行（急涨 / 急跌）', () => {
  const move = (o: Record<string, unknown> = {}) => ({ base: 'PEPE', cat: 'move', kind: 'moveUp', window: '1m', pct: 2.4, price: 0.0123, volUsd: 3.2e6, atMs: 50, tier: 2, ...o })
  it('解析：字段平铺在行上，没有 top；没带涨跌幅、次数照常', () => {
    const b = parseBoard({ generatedAtMs: 99, rows: [move(), move({ base: 'WIF', kind: 'moveDown', window: '5m', pct: -1.8, volUsd: null })] })!
    expect(b.rows).toHaveLength(2)
    expect(b.rows[0]).toMatchObject({ key: 'move:PEPE', cat: 'move', changePct: null, count: 1, price: 0.0123, tier: 2, atMs: 50, top: { kind: 'move', dir: 'up', window: '1m', pct: 2.4, volUsd: 3.2e6 } })
    expect(b.rows[1].top).toEqual({ kind: 'move', dir: 'down', window: '5m', pct: -1.8, volUsd: null })
  })
  it('事实句只写窗口与成交额「1 分 · 额 3.2M」，没有成交额只写窗口；药丸写波动本身、按方向着色', () => {
    const b = parseBoard({ generatedAtMs: 99, rows: [move(), move({ base: 'WIF', kind: 'moveDown', window: '5m', pct: -1.8, volUsd: 0 })] })!
    expect(boardFact(b.rows[0])).toBe('1 分 · 额 3.2M')
    expect(boardFact(b.rows[1])).toBe('5 分')
    expect(moveFact({ dir: 'up', window: '5m', pct: 12.06, volUsd: 1.25e9 })).toBe('5 分 · 额 1.3B')
    expect(moveFact({ dir: 'down', window: '1m', pct: -1.4, volUsd: 1.14e8 })).toBe('1 分 · 额 114M')
    // 急跌行哪怕 24 时大涨，药丸也是这次的 −1.4%、红色
    expect(movePill({ dir: 'down', window: '1m', pct: -1.4, volUsd: 1.14e8 })).toEqual({ text: '−1.4%', cls: 'down' })
    expect(movePill({ dir: 'up', window: '5m', pct: 1.4, volUsd: null })).toEqual({ text: '+1.4%', cls: 'up' })
    expect([HL.catMove, HL.moveUp, HL.moveDown]).toEqual(['波动', '急涨', '急跌'])
  })
  it('认不出的整行不要（方向 / 窗口 / 涨跌幅缺一样），不抛错', () => {
    const b = parseBoard({ generatedAtMs: 1, rows: [move({ kind: 'moveSideways' }), move({ window: '15m' }), move({ pct: null }), move({ base: 3 }), { cat: 'move' }, null, 'x'] })!
    expect(b.rows).toEqual([])
  })
  it('同一只既有盘口又有波动：两行都留，各自按键合并', () => {
    const level = { kind: 'event', id: 'E:1', t: 'oiJump', atMs: 10, pct: 3 }
    const b = parseBoard({ generatedAtMs: 99, rows: [{ base: 'PEPE', cat: 'book', atMs: 10, tier: 1, top: level }, move()] })!
    expect(b.rows.map(r => r.key)).toEqual(['PEPE', 'move:PEPE'])
    const later = parseBoard({ generatedAtMs: 120, rows: [move({ atMs: 110, pct: 3.1 }), { base: 'PEPE', cat: 'book', atMs: 10, tier: 1, top: level }] })!
    const m = mergeBoard(b.rows, later.rows)
    expect(m.rows.map(r => r.key)).toEqual(['PEPE', 'move:PEPE'])   // 不换位
    expect(m.fresh).toBe(1)                                         // 波动那行有了更新
    expect((m.rows[1].top as { pct: number }).pct).toBe(3.1)
  })
  it('筛选、点行只进图（不升半页）', () => {
    const b = parseBoard({ generatedAtMs: 99, rows: [move(), move({ base: 'WIF' }), { base: 'BTC', cat: 'funding', top: { kind: 'event', id: 'E:2', t: 'oiJump', atMs: 1, pct: 2 } }] })!
    expect(filterRows(b.rows, 'move').map(r => r.base)).toEqual(['PEPE', 'WIF'])
    expect(focusOf(b.rows[0].top)).toBeNull()
    expect(focusOf(b.rows[2].top)).toEqual({ kind: 'event', id: 'E:2' })
  })
})

describe('顶部胶囊条不带计数', () => {
  it('首页胶囊只写类名：不再算计数、不出数字徽记、不带色点', () => {
    expect(homeSource).not.toMatch(/chipCounts/)
    expect(homeCss).not.toMatch(/\.hm-chips b\b/)
    expect(homeCss).not.toMatch(/\.hm-chips[^{]*\bi\b/)
  })
})

describe('服务端还没上新字段', () => {
  it('看板里没有波动行：照旧三类，「波动」筛出来是空', () => {
    const b = parseBoard({ generatedAtMs: 9, rows: [{ base: 'BTC', cat: 'oi', top: { kind: 'event', id: 'E:1', t: 'oiJump', atMs: 1, pct: 2 } }] })!
    expect(filterRows(b.rows, 'move')).toEqual([])
  })
  it('减仓榜 400（invalid_kind）/ 形状不对：解析给 null，页面只走「取不到 · 重试」', () => {
    expect(parseMarketBoard({ error: { code: 'invalid_kind' } })).toBeNull()
    expect(parseMarketBoard(null)).toBeNull()
  })
  it('未知的类与旧行不受影响', () => {
    const b = parseBoard({ generatedAtMs: 9, rows: [{ base: 'X', cat: 'whale', kind: 'moveUp', window: '1m', pct: 1 }, { base: 'BTC', cat: 'oi', top: { kind: 'event', id: 'E:1', t: 'oiJump', atMs: 1, pct: 2 } }] })!
    expect(b.rows.map((r: BoardRow) => r.key)).toEqual(['BTC'])
  })
})
