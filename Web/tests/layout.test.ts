/* 行情页布局与拖动：尺寸夹取、多图布局清单、降级门槛、侧栏拖动分配、行情连接池分配 */
import { describe, it, expect } from 'vitest'
import { LAYOUTS, LAYOUT_N, GRID, MAX_CELLS, clampActive, ensureCells, hydrate, FILL_SYMBOLS, type Layout, type CellCfg } from '../src/app/store'
import { REGIONS, clampSize, fitWidths, fitDrawer, trackFracs, dragTracks, CHART_MIN_W, CHART_MIN_H, DRAWER_MAX_FRAC } from '../src/app/sizes'
import { paneHeights, dragPane, paneRatiosOf, degradeFor, subDefaultH, MAIN_MIN_FRAC, SUB_MIN_H, FULL } from '../src/chart/panes'
import { planSidebar, dragSidebar, sideCanDrag, PARTS } from '../src/orderflow/sidebar'
import { assignStreams, PER_CONN, TOTAL } from '../src/market/stream'
import type { WidgetId } from '../src/app/store'

const sum = (xs: readonly number[]): number => xs.reduce((a, b) => a + b, 0)

describe('分隔条尺寸：夹取、按比例收、双击回默认', () => {
  it('三处默认值与范围', () => {
    expect(REGIONS.ladder).toMatchObject({ def: 240, min: 160, max: 480 })
    expect(REGIONS.panel).toMatchObject({ def: 400, min: 320, max: 640 })
    expect(REGIONS.drawer).toMatchObject({ def: 280, min: 160 })
    expect(DRAWER_MAX_FRAC).toBe(0.6)
  })
  it('拖出范围的值夹回来；没存过（双击删掉之后）= 默认', () => {
    expect(clampSize(90, REGIONS.ladder)).toBe(160)
    expect(clampSize(900, REGIONS.ladder)).toBe(480)
    expect(clampSize(333.4, REGIONS.panel)).toBe(333)
    expect(clampSize(undefined, REGIONS.panel)).toBe(400)
    expect(clampSize(Number.NaN, REGIONS.ladder)).toBe(240)
  })
  it('横向放得下时原样；放不下时梯子与面板按比例一起收，图表区留够 480，各自不低于下限', () => {
    expect(fitWidths(300, 500, 2400)).toEqual({ ladder: 300, panel: 500 })
    const w = fitWidths(480, 640, 1300)
    expect(w.ladder! + w.panel!).toBeLessThanOrEqual(1300 - CHART_MIN_W)
    expect(w.ladder! / w.panel!).toBeCloseTo(480 / 640, 1)
    const tiny = fitWidths(480, 640, 600)
    expect(tiny).toEqual({ ladder: 160, panel: 320 })
    expect(fitWidths(null, 640, 900)).toEqual({ ladder: null, panel: 420 })
  })
  it('抽屉不超过页面高 60%，并给图表区留 240', () => {
    expect(fitDrawer(280, 1300)).toBe(280)
    expect(fitDrawer(2000, 1300)).toBe(780)
    expect(fitDrawer(2000, 500)).toBe(500 - CHART_MIN_H)
    expect(fitDrawer(50, 1300)).toBe(160)
    expect(fitDrawer(undefined, 1300)).toBe(280)
  })
  it('多图网格：存的比例不对就回平均；拖只在相邻两条之间挪，各不小于下限', () => {
    expect(trackFracs(undefined, 4)).toEqual([0.25, 0.25, 0.25, 0.25])
    expect(trackFracs([1, 2], 3)).toEqual([1 / 3, 1 / 3, 1 / 3])
    expect(trackFracs([2, 1, 1], 3)).toEqual([0.5, 0.25, 0.25])
    const fr = dragTracks([0.25, 0.25, 0.25, 0.25], 1, 100, 2000, 240)
    expect(fr[1] * 2000).toBeCloseTo(600)
    expect(fr[2] * 2000).toBeCloseTo(400)
    expect(fr[0]).toBe(0.25); expect(fr[3]).toBe(0.25)
    const hard = dragTracks([0.25, 0.25, 0.25, 0.25], 0, -1000, 2000, 240)
    expect(hard[0] * 2000).toBeCloseTo(240)
    expect(sum(hard)).toBeCloseTo(1)
  })
})

describe('主图 / 副图高度', () => {
  const H = 1200
  it('默认：副图 11% 夹 96–136，主图拿剩下的', () => {
    expect(subDefaultH(H)).toBe(132)
    const hs = paneHeights(H, ['macd', 'rsi'], null)
    expect(hs.slice(1)).toEqual([132, 132])
    expect(hs[0]).toBe(H - 264)
  })
  it('拖分隔线：主图 ≥ 40%、副图 ≥ 80；存成比例，窗口变了等比伸缩', () => {
    const hs = paneHeights(H, ['macd'], null)
    const up = dragPane(hs, 0, -2000, H)
    expect(up[0]).toBeGreaterThanOrEqual(H * MAIN_MIN_FRAC - 0.5)
    const down = dragPane(hs, 0, 2000, H)
    expect(down[1]).toBeGreaterThanOrEqual(SUB_MIN_H)
    const r = paneRatiosOf(['macd'], up, H)
    const again = paneHeights(H / 2, ['macd'], r)
    expect(again[1] / (H / 2)).toBeCloseTo(up[1] / H, 1)
  })
})

describe('多图布局清单与降级', () => {
  it('布局 1 / 2 / 2v / 3 / 4 / 6 / 8 / 9 / 12 / 16，格数与行列一致，最多 16 格', () => {
    expect([...LAYOUTS]).toEqual(['1', '2', '2v', '3', '4', '6', '8', '9', '12', '16'])
    expect(MAX_CELLS).toBe(16)
    for (const k of LAYOUTS) {
      const g = GRID[k]
      const n = g.areas ? new Set(g.areas.flat()).size : g.cols * g.rows
      expect(n).toBe(LAYOUT_N[k])
    }
    expect(GRID['16']).toEqual({ cols: 4, rows: 4 })
    expect(GRID['12']).toEqual({ cols: 4, rows: 3 })
    expect(GRID['9']).toEqual({ cols: 3, rows: 3 })
  })
  it('clampActive：16 格里第 15 格有效，换成四图收到第 3 格', () => {
    const s = { active: 15, layout: '16' as Layout }
    clampActive(s); expect(s.active).toBe(15)
    s.layout = '4'; clampActive(s); expect(s.active).toBe(3)
    expect(hydrate({ layout: '16', active: 12 }).active).toBe(12)
    expect(hydrate({ layout: '12', active: 14 }).active).toBe(11)
  })
  it('补齐到 16 格：各不相同、补洞、周期跟第 0 格；存档超过 16 格截掉', () => {
    const s = { cells: [{ symbol: 'BTCUSDT', iv: '4h' }] as CellCfg[] }
    ensureCells(s, 16)
    expect(s.cells).toHaveLength(16)
    expect(new Set(s.cells.map(c => c.symbol)).size).toBe(16)
    expect(s.cells.every(c => c.iv === '4h')).toBe(true)
    const holes = { cells: [{ symbol: 'BTCUSDT', iv: '1h' }, undefined, { symbol: 'ETHUSDT', iv: '5m' }] as unknown as CellCfg[] }
    ensureCells(holes, 3)
    expect(holes.cells[1].symbol).toBe('SOLUSDT')
    expect(holes.cells[2]).toEqual({ symbol: 'ETHUSDT', iv: '5m' })
    expect(FILL_SYMBOLS).toHaveLength(16)
    const many = hydrate({ layout: '16', cells: Array.from({ length: 20 }, () => ({ symbol: 'BTCUSDT', iv: '1h' })) })
    expect(many.cells.length).toBeLessThanOrEqual(16)
  })
  it('降级门槛：宽 < 640 或高 < 360 只留主图、图例一行、字小一档；宽 < 420 不画成交量', () => {
    expect(degradeFor(640, 360)).toEqual(FULL)
    expect(degradeFor(639, 800)).toMatchObject({ subs: false, compact: true, vol: true })
    expect(degradeFor(1000, 359)).toMatchObject({ subs: false, compact: true, vol: true })
    expect(degradeFor(419, 300)).toMatchObject({ subs: false, vol: false })
    expect(degradeFor(500, 300).font).toBeLessThan(FULL.font)
    // 2560×1440、面板开着的十六格：约 500 × 330，降级但成交量还在
    expect(degradeFor(500, 330)).toMatchObject({ subs: false, compact: true, vol: true })
  })
})

describe('侧栏各块：用户拖过之后的分配', () => {
  const ALL: WidgetId[] = ['watch', 'detail', 'book', 'tape', 'walls', 'alerts']
  const AVAIL = 1384
  const none = new Set<string>()
  it('没拖过 = 原来的默认分配', () => {
    expect(planSidebar(AVAIL, ALL, none, PARTS, undefined)).toEqual(planSidebar(AVAIL, ALL, none))
    expect(planSidebar(AVAIL, ALL, none, PARTS, {})).toEqual(planSidebar(AVAIL, ALL, none))
  })
  it('拖一条线：只在上下两块之间挪，详情跟着走不变，总高不变', () => {
    const h0 = planSidebar(AVAIL, ALL, none)
    // 第 0 条线在自选与详情之间：详情定高，挪的是自选与盘口
    const h1 = dragSidebar(h0, ALL, none, 0, 60)
    expect(h1[0]).toBe(h0[0] + 60)
    expect(h1[1]).toBe(h0[1])
    expect(h1[2]).toBe(h0[2] - 60)
    expect(sum(h1)).toBe(sum(h0))
    // 夹到下限
    const h2 = dragSidebar(h0, ALL, none, 3, 5000)
    expect(h2[4]).toBe(PARTS.walls.floor)
    expect(sum(h2)).toBe(sum(h0))
  })
  it('记下来的高度：收起一块、窗口变高，按比例铺满，总高正好', () => {
    const h0 = planSidebar(AVAIL, ALL, none)
    const h1 = dragSidebar(h0, ALL, none, 2, 80)
    const user: Record<string, number> = {}
    ALL.forEach((id, i) => { if (id !== 'detail') user[id] = h1[i] })
    expect(planSidebar(AVAIL, ALL, none, PARTS, user)).toEqual(h1)
    const col = new Set(['tape'])
    const h2 = planSidebar(AVAIL, ALL, col, PARTS, user)
    expect(sum(h2)).toBe(AVAIL)
    expect(h2[3]).toBe(PARTS.tape.head)
    const h3 = planSidebar(AVAIL + 200, ALL, none, PARTS, user)
    expect(sum(h3)).toBe(AVAIL + 200)
    expect(h3[1]).toBe(PARTS.detail.min)
  })
  it('上下没有能挪的块时那条线不能拖', () => {
    expect(sideCanDrag(['watch', 'detail'], none, 0)).toBe(false)
    expect(sideCanDrag(ALL, none, 0)).toBe(true)
    expect(sideCanDrag(ALL, new Set(['watch']), 0)).toBe(false)
  })
})

describe('行情连接池：按每条上限分，流变少了收掉最空的那条', () => {
  const names = (n: number, p = 's'): string[] => Array.from({ length: n }, (_, i) => `${p}${i}@ticker`)
  it('每条上限：直连 200、网关 64（网关同一来源合计 160）', () => {
    expect(PER_CONN).toEqual({ direct: 200, gateway: 64 })
    expect(TOTAL.gateway).toBe(160)
  })
  it('16 格（每格两路 + 自选 + 提醒）在网关上分成 ⌈n / 64⌉ 条', () => {
    const want = names(100)
    const r = assignStreams([], want, 64)
    expect(r.keep).toEqual([])
    expect(r.open.map(x => x.length)).toEqual([64, 36])
  })
  it('已在连接上的流不挪；新的先填空位', () => {
    const cur = [names(60), names(10, 't')]
    const want = [...names(60), ...names(10, 't'), ...names(3, 'u')]
    const r = assignStreams(cur, want, 64)
    expect(r.keep[0]).toEqual([...names(60), ...names(3, 'u').slice(0, 3)].slice(0, 64))
    expect(r.keep[1]).toEqual(names(10, 't'))
    expect(r.open).toEqual([])
  })
  it('流变少了：连接数回到 ⌈n / 上限⌉，收掉最空的那条，它的流挪到别处', () => {
    const cur = [names(64), names(64, 't'), names(5, 'u')]
    const want = [...names(30), ...names(5, 'u')]
    const r = assignStreams(cur, want, 64)
    expect(r.keep.filter(Boolean)).toHaveLength(1)
    expect(new Set(r.keep.flatMap(x => x || []))).toEqual(new Set(want))
    expect(r.open).toEqual([])
    const none = assignStreams(cur, [], 64)
    expect(none.keep.every(x => x === null)).toBe(true)
  })
  it('20 次快速换布局（1 ↔ 16 格）连接数不涨', () => {
    let cur: string[][] = []
    const big = names(40), small = names(4)
    let max = 0
    for (let k = 0; k < 20; k++) {
      const want = k % 2 ? small : big
      const r = assignStreams(cur, want, 8)
      cur = [...r.keep.filter((x): x is string[] => !!x), ...r.open]
      expect(cur.length).toBe(Math.ceil(want.length / 8))
      max = Math.max(max, cur.length)
    }
    expect(max).toBe(5)
  })
})
