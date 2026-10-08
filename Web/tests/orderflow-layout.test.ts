/* 主力订单流 · 图上取舍（带的名额、浓淡、标签与记号的摆放）与侧栏高度分配、门槛设置第二层的位置 */
import { describe, expect, it } from 'vitest'
import {
  pickBands, liveAlpha, placeLabels, placeMark, overlaps,
  MAX_LIVE_BANDS, MAX_ENDED_BANDS, MAX_LABELS, LIVE_ALPHA, ENDED_LINE, type BandCand, type Rect, type LabelReq,
} from '../src/orderflow/bands'
import { planSidebar, partsFor, rowsThatFit, toggleCollapsed, PARTS, DETAIL_H_2COL, WATCH_ROW, WATCH_HEAD, WATCH_THEAD, SEP, TAPE_ROW, WALL_ROW, BOOK_ROW, WIDGET_HEAD } from '../src/orderflow/sidebar'
import { HEAT_MAX_ALPHA, heatAlpha, edgeFade } from '../src/orderflow/heat'
import { layerSpot } from '../src/orderflow/settings'
import type { WidgetId } from '../src/app/store'

const cand = (id: string, live: boolean, pk: number): BandCand => ({ id, live, pk })

describe('pickBands：图上只画峰值最大的几道', () => {
  const many = [
    ...Array.from({ length: 20 }, (_, i) => cand(`L${i}`, true, (i + 1) * 1e6)),
    ...Array.from({ length: 10 }, (_, i) => cand(`E${i}`, false, (i + 1) * 1e6)),
  ]

  it('挂着的最多 8 道、结束的最多 4 道，都按峰值从大到小', () => {
    const r = pickBands(many)
    expect(MAX_LIVE_BANDS).toBe(8)
    expect(MAX_ENDED_BANDS).toBe(4)
    expect(r.live.map(c => c.id)).toEqual(['L19', 'L18', 'L17', 'L16', 'L15', 'L14', 'L13', 'L12'])
    expect(r.ended.map(c => c.id)).toEqual(['E9', 'E8', 'E7', 'E6'])
  })

  it('不足名额时全画；空列表不出错', () => {
    const r = pickBands([cand('a', true, 1), cand('b', false, 2)])
    expect(r.live).toHaveLength(1)
    expect(r.ended).toHaveLength(1)
    expect(pickBands([])).toEqual({ live: [], ended: [] })
  })

  it('被点中的那道不占名额、总是画（排在最后）', () => {
    const r = pickBands(many, 'L0')
    expect(r.live).toHaveLength(9)
    expect(r.live[8].id).toBe('L0')
    const e = pickBands(many, 'E0')
    expect(e.ended.map(c => c.id)).toEqual(['E9', 'E8', 'E7', 'E6', 'E0'])
    // 本来就在名额里的不重复
    expect(pickBands(many, 'L19').live).toHaveLength(8)
    // 不在可见候选里的高亮不凭空加
    expect(pickBands(many, 'nope').live).toHaveLength(8)
  })

  it('同峰值按 id 排，输入顺序变了挑出来的也一样（每帧不闪）', () => {
    const tie = Array.from({ length: 12 }, (_, i) => cand(`t${String(i).padStart(2, '0')}`, true, 5e6))
    const a = pickBands(tie).live.map(c => c.id)
    const b = pickBands([...tie].reverse()).live.map(c => c.id)
    expect(a).toEqual(b)
    expect(a[0]).toBe('t00')
  })
})

describe('liveAlpha：挂着的带按涨跌色铺底，浅色 0.08–0.12，最大的最深', () => {
  it('浅色：第一道 0.12、最后一道 0.08，单调不增', () => {
    const n = 8
    const xs = Array.from({ length: n }, (_, i) => liveAlpha(i, n))
    expect(xs[0]).toBeCloseTo(LIVE_ALPHA.light.hi)
    expect(xs[n - 1]).toBeCloseTo(LIVE_ALPHA.light.lo)
    expect(LIVE_ALPHA.light.lo).toBeGreaterThanOrEqual(0.06)
    expect(LIVE_ALPHA.light.hi).toBeLessThanOrEqual(0.14)
    for (let i = 1; i < n; i++) expect(xs[i]).toBeLessThanOrEqual(xs[i - 1])
    for (const x of xs) { expect(x).toBeGreaterThanOrEqual(LIVE_ALPHA.light.lo); expect(x).toBeLessThanOrEqual(LIVE_ALPHA.light.hi) }
  })
  it('只有一道时取最深；深色皮肤一套自己的范围，也不超过 0.20', () => {
    expect(liveAlpha(0, 1)).toBe(LIVE_ALPHA.light.hi)
    expect(liveAlpha(0, 5, true)).toBe(LIVE_ALPHA.dark.hi)
    expect(liveAlpha(4, 5, true)).toBe(LIVE_ALPHA.dark.lo)
    expect(LIVE_ALPHA.dark.hi).toBeLessThanOrEqual(0.2)
  })
  it('结束的带只是一道线，不铺底色', () => {
    expect(ENDED_LINE.light).toBeLessThanOrEqual(1)
    expect(ENDED_LINE.dark).toBeLessThanOrEqual(1)
  })
})

describe('placeLabels：右端标签最多 8 个、互不重叠、不压价格轴', () => {
  const bounds = { top: 0, bottom: 800, maxRight: 1000 }
  const req = (y: number, prio: number, right = 1200, left = 0): LabelReq => ({ right, left, y, w: 90, h: 16, prio })

  it('越过价格轴的右沿被收回到 maxRight 以内', () => {
    const [r] = placeLabels([req(100, 1)], bounds)
    expect(r).not.toBeNull()
    expect(r!.x + r!.w).toBeLessThanOrEqual(1000)
  })

  it('同一高度的一串：大的先摆，后来的往左让，谁也不压谁', () => {
    const reqs = Array.from({ length: 5 }, (_, i) => req(200, 10 - i))
    const out = placeLabels(reqs, bounds)
    const placed = out.filter((r): r is Rect => !!r)
    expect(placed.length).toBe(5)
    expect(out[0]!.x + out[0]!.w).toBe(1000) // 最大的贴右端
    for (let i = 0; i < placed.length; i++) for (let j = i + 1; j < placed.length; j++) expect(overlaps(placed[i], placed[j])).toBe(false)
  })

  it('最多 8 个', () => {
    const reqs = Array.from({ length: 20 }, (_, i) => req(20 + i * 30, i))
    const out = placeLabels(reqs, bounds)
    expect(MAX_LABELS).toBe(8)
    expect(out.filter(Boolean)).toHaveLength(8)
    // 留下的是 prio 最大的 8 个
    expect(out.slice(12).every(Boolean)).toBe(true)
    expect(out.slice(0, 12).some(Boolean)).toBe(false)
  })

  it('压到蜡烛（blocked）就往左让；让到带的左端还不行就不标', () => {
    const candle: Rect = { x: 940, y: 180, w: 30, h: 60 }
    const [r] = placeLabels([req(200, 1, 1000, 700)], bounds, x => overlaps(x, candle))
    expect(r).not.toBeNull()
    expect(overlaps(r!, candle)).toBe(false)
    expect(r!.x).toBeGreaterThanOrEqual(700)
    const wall: Rect = { x: 0, y: 0, w: 1000, h: 800 }
    expect(placeLabels([req(200, 1)], bounds, x => overlaps(x, wall))[0]).toBeNull()
  })

  it('标签出了画布上下沿就不摆', () => {
    expect(placeLabels([req(4, 1), req(798, 1)], bounds)).toEqual([null, null])
  })
})

describe('placeMark：结束记号永远不盖在蜡烛上', () => {
  it('右端空着就放在右端', () => {
    expect(placeMark(500, 300, 7, 100, 10, () => false, 900)).toEqual({ x: 500, y: 300, onAxis: false })
  })
  it('右端压着蜡烛就沿带往左一根一根让', () => {
    const candle: Rect = { x: 495, y: 280, w: 10, h: 40 }
    const r = placeMark(500, 300, 7, 100, 10, b => overlaps(b, candle), 900)
    expect(r.onAxis).toBe(false)
    expect(r.x).toBeLessThan(495)
  })
  it('让不开（整段都是蜡烛）就落到时间轴上方', () => {
    const r = placeMark(500, 300, 7, 100, 10, () => true, 900)
    expect(r).toEqual({ x: 500, y: 900 - 3.5 - 2, onAxis: true })
  })
  it('往左让不越过带的左端', () => {
    const seen: number[] = []
    placeMark(500, 300, 7, 480, 10, b => { seen.push(b.x); return true }, 900)
    for (const x of seen) expect(x + 1 + 3.5).toBeGreaterThanOrEqual(480)
  })
})

describe('热力：p95 映射到 ≤ 0.40，回填与实时同一个归一', () => {
  it('最亮不超过 0.40，p95 以上封顶', () => {
    expect(HEAT_MAX_ALPHA).toBeLessThanOrEqual(0.4)
    expect(heatAlpha(100, 100)).toBeCloseTo(HEAT_MAX_ALPHA)
    expect(heatAlpha(1e9, 100)).toBeCloseTo(HEAT_MAX_ALPHA)
    expect(heatAlpha(0, 100)).toBe(0)
    expect(heatAlpha(5, 0)).toBe(0)
  })
  it('数据边沿淡入：起点一列最淡、span 格之后满浓度，上下沿对称', () => {
    expect(edgeFade(0, 0, Infinity, 3)).toBeCloseTo(0.25)
    expect(edgeFade(1, 0, Infinity, 3)).toBeCloseTo(0.5)
    expect(edgeFade(3, 0, Infinity, 3)).toBe(1)
    expect(edgeFade(50, 0, Infinity, 3)).toBe(1)
    expect(edgeFade(9, 0, 9, 3)).toBeCloseTo(0.25)
    expect(edgeFade(5, 0, 9, 0)).toBe(1)
  })
  it('同一个值在同一个 p95 下浓度一样（两段接缝没有硬边），且随值单调', () => {
    expect(heatAlpha(37, 120)).toBe(heatAlpha(37, 120))
    expect(heatAlpha(10, 100)).toBeLessThan(heatAlpha(50, 100))
  })
})

describe('planSidebar：2560×1440 下一屏放下、不滚动', () => {
  const ALL: WidgetId[] = ['watch', 'detail', 'book', 'tape', 'walls', 'alerts']
  const AVAIL = 1440 - 48 - 8 // 顶栏以下、上下留白以内
  const none = new Set<string>()
  const sum = (xs: number[]): number => xs.reduce((a, b) => a + b, 0)

  it('全开：总和不超过侧栏；自选 ≥ 8 行、盘口 ≥ 8 档、成交 ≥ 10 行、大单 ≥ 6 行', () => {
    const h = planSidebar(AVAIL, ALL, none)
    expect(sum(h)).toBeLessThanOrEqual(AVAIL)
    const [watch, detail, book, tape, walls] = h
    expect(Math.floor((watch - SEP - WATCH_HEAD - WATCH_THEAD) / WATCH_ROW)).toBeGreaterThanOrEqual(8)
    expect(detail).toBe(PARTS.detail.min)
    expect(detail).toBeGreaterThanOrEqual(220)
    expect(detail).toBeLessThanOrEqual(270)
    expect(Math.floor((book - SEP - WIDGET_HEAD - 44 - 94 - 20 - 4) / BOOK_ROW)).toBeGreaterThanOrEqual(8)
    expect(rowsThatFit(tape, WIDGET_HEAD, TAPE_ROW)).toBeGreaterThanOrEqual(10)
    expect(rowsThatFit(walls, WIDGET_HEAD, WALL_ROW)).toBeGreaterThanOrEqual(6)
  })

  it('默认两块（自选 + 详情）：自选吃掉余下全部，详情定高', () => {
    const h = planSidebar(AVAIL, ['watch', 'detail'], none)
    expect(sum(h)).toBe(AVAIL)
    expect(h[1]).toBe(PARTS.detail.min)
  })

  it('收起的只剩标题行；省下来的先补足各块最小，再平均分给能长的块', () => {
    const base = planSidebar(AVAIL, ALL, none)
    const h = planSidebar(AVAIL, ALL, new Set(['book', 'tape']))
    expect(h[2]).toBe(PARTS.book.head)
    expect(h[3]).toBe(PARTS.tape.head)
    expect(sum(h)).toBe(AVAIL)
    expect(h[1]).toBe(PARTS.detail.min) // 详情定高，不分
    const extra = [h[0] - PARTS.watch.min, h[4] - PARTS.walls.min, h[5] - PARTS.alerts.min]
    expect(Math.max(...extra) - Math.min(...extra)).toBeLessThanOrEqual(1) // 平分（余数给前面的）
    expect(h[0]).toBeGreaterThan(base[0])
  })

  it('全收起：每块都是标题高', () => {
    const h = planSidebar(AVAIL, ALL, new Set(ALL))
    expect(h).toEqual(ALL.map(id => PARTS[id].head))
  })

  it('放不下时按优先级往 floor 压：提醒先压，详情从不压', () => {
    const tight = sum(ALL.map(id => PARTS[id].min)) - 30
    const h = planSidebar(tight, ALL, none)
    expect(sum(h)).toBe(tight)
    expect(h[5]).toBe(PARTS.alerts.min - 26) // 提醒最多让 26（到 floor），剩下的由大单让
    expect(h[4]).toBe(PARTS.walls.min - 4)
    expect(h[1]).toBe(PARTS.detail.min)
    const tiny = planSidebar(300, ALL, none)
    ALL.forEach((id, i) => expect(tiny[i]).toBeGreaterThanOrEqual(PARTS[id].floor))
  })

  it('八块全开（含两块统计）：一屏放下，成交 ≥ 8 行、自选 ≥ 6 行、盘口 ≥ 4 档、大单 ≥ 3 行', () => {
    // 2026-09-29 压测：以前成交比盘口先压、floor 只有 5 行，八块全开时成交流只剩 5 行、盘口还留着整 8 档
    const EIGHT: WidgetId[] = ['watch', 'detail', 'book', 'tape', 'walls', 'liq', 'vol', 'alerts']
    expect(sum(EIGHT.map(id => PARTS[id].floor))).toBeLessThanOrEqual(AVAIL)
    const h = planSidebar(AVAIL, EIGHT, none)
    expect(sum(h)).toBe(AVAIL)
    const [watch, detail, book, tape, walls, liq, vol, alerts] = h
    expect(rowsThatFit(tape, WIDGET_HEAD, TAPE_ROW)).toBeGreaterThanOrEqual(8)
    expect(Math.floor((watch - SEP - WATCH_HEAD - WATCH_THEAD) / WATCH_ROW)).toBeGreaterThanOrEqual(6)
    expect(Math.floor((book - SEP - WIDGET_HEAD - 44 - 94 - 20 - 4) / BOOK_ROW)).toBeGreaterThanOrEqual(4)
    expect(rowsThatFit(walls, WIDGET_HEAD, WALL_ROW)).toBeGreaterThanOrEqual(3)
    expect(alerts).toBeGreaterThanOrEqual(PARTS.alerts.floor)
    expect(detail).toBe(PARTS.detail.min)
    expect(Math.min(liq, vol)).toBeGreaterThanOrEqual(PARTS.liq.floor)
  })

  it('窄侧栏：详情改两列、高 +48，八块全开仍然一屏放下、成交 ≥ 8 行', () => {
    const EIGHT: WidgetId[] = ['watch', 'detail', 'book', 'tape', 'walls', 'liq', 'vol', 'alerts']
    expect(partsFor(400)).toBe(PARTS)
    expect(partsFor(0)).toBe(PARTS)
    const narrow = partsFor(320)
    expect(narrow.detail.min).toBe(DETAIL_H_2COL + SEP)
    const h = planSidebar(AVAIL, EIGHT, none, narrow)
    expect(sum(h)).toBe(AVAIL)
    expect(h[1]).toBe(DETAIL_H_2COL + SEP)
    expect(rowsThatFit(h[3], WIDGET_HEAD, TAPE_ROW)).toBeGreaterThanOrEqual(8)
    EIGHT.forEach((id, i) => expect(h[i]).toBeGreaterThanOrEqual(narrow[id].floor))
  })

  it('不认识的块高度记 0', () => {
    expect(planSidebar(500, ['watch', 'x' as WidgetId], none)[1]).toBe(0)
  })

  it('toggleCollapsed 来回切', () => {
    const l: string[] = []
    expect(toggleCollapsed(l, 'book')).toEqual(['book'])
    expect(toggleCollapsed(l, 'tape')).toEqual(['book', 'tape'])
    expect(toggleCollapsed(l, 'book')).toEqual(['tape'])
  })
})

describe('门槛设置：指标面板的第二层', () => {
  const panel = { top: 200, right: 1700, height: 600 }
  const row = { top: 290, right: 1690, height: 44 }

  it('右边放得下：贴在面板右侧，顶端对着那一行，箭头指着行中线', () => {
    const r = layerSpot({ panel, row }, 360, 2560, 1440)
    expect(r.inside).toBe(false)
    expect(r.left).toBe(1712)
    expect(r.top).toBe(284)
    expect(r.top + r.arrow).toBe(312)
  })

  it('右边放不下：盖在面板右半边，不出视口', () => {
    const r = layerSpot({ panel: { ...panel, right: 1500 }, row }, 360, 1600, 900)
    expect(r.inside).toBe(true)
    expect(r.left + 520).toBeLessThanOrEqual(1500)
  })

  it('靠下时整层往上夹回视口', () => {
    const r = layerSpot({ panel, row: { ...row, top: 1380 } }, 400, 2560, 1440)
    expect(r.top + 400).toBeLessThanOrEqual(1440 - 16)
    expect(r.arrow).toBeLessThanOrEqual(400 - 16)
  })
})
