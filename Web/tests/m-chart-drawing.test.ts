// 移植自（纯数值 / 纯交互用例）：
//   KanpanCore/Tests/KanpanCoreTests/DrawingTests.swift、DrawingEditTests.swift（含 DrawingV2Tests）、
//   DrawingBookTests.swift、DrawingKindNameTests.swift、DrawingVariantTests.swift、DrawVolumeTests.swift、
//   DrawArchiveCapTests.swift（含 CapAge）
//   KanpanChart/Tests/KanpanChartTests/ChartDrawingTests.swift（含 DrawingBookBindingTests）、
//   ChartDrawingTapDisciplineTests.swift（含 LongPressLock）
//
// 跳过的（依赖 UIKit / CoreGraphics 位图或网页没有的东西）：
//   - computedToolsPaintInkOnlyWithASeries：往离屏 CGContext 画一笔数 alpha 像素；node 里没有 canvas。
//     「有 K 线才出几何、没 K 线只剩手柄」在上面 DrawVolumeTests 那组里按几何断言了。
//   - fixedProfilePreviewsItsBars：同上，靠 overlay.draw 数墨。
//   - threePointToolPreviewsItsFirstLeg 的「数墨」那半句：预览计划（两点、不 whole）照测，像素不测。
//   - midDragEvidence：取证截图写 PNG 进仓库，归真机 / 浏览器取证。
//   - indicatorColorsDoNotAffectValues：测的是渲染器的指标配色，不属画线模块。
//   - DrawingKindNameTests 里的提醒名（legacyAlertLineNames、alertNamesUseTheDisplaySymbol）：
//     网页的 draw/alert.ts 只移植了 AlertGeometry，提醒名归提醒模块。
//   - overlayForwardsTouches：网页没有独立的覆盖层视图，改测「interactive 开着时触摸经 view.drawingInput
//     转进控制器、关掉就摘下」。
//   - 长按锁定四条：Swift 用真定时器 + 轮询等；这里用 vi.useFakeTimers 把 400ms 长按定时器快进过去。
//
// 触摸的写法：Swift 用覆写 location(in:) 的假 UITouch；这里往 view.el 派 PointerEvent 形状的假事件，
// 走的是和手机浏览器同一条路（gesture.ts → view.drawingInput → DrawingController）。
// 同一帧里落下的两根手指在网页上是两次 pointerdown，同一时间戳。

import { describe, test, expect, vi, beforeAll, afterEach } from 'vitest'
import {
  type Drawing, type DrawHit, type DrawPart, type DrawPoint, type DrawingKind, type DrawBounds, type DrawFill,
  type DrawPixel, type DrawSnap, type DrawingBookChange, type DrawingFeedback,
  hitDraw, distSeg, makeDrawing, drawingA, drawingB, DrawingStore, cloneDrawing, encodeDrawing, decodeDrawing,
  drawingsEqual, drawingEquals, DrawKind, drawingWith, drawingIsValid, snapDrawPointSimple, movedDrawing, snapDrawPoint,
  DrawHistory, newDrawingID, DrawArchive, decodeArchive, encodeArchive, drawingGeometry, DrawGeometry,
  DrawingBook, canonicalInstrument, DrawingPreferences, styleOf, decodePreferences, encodePreferences, DrawAge,
  vwapTrail, volumeProfile, VolumeProfile, DRAW_PART_ANCHORS, ComputedMemo, computeVWAPTrail, computeVolumeProfile,
  DrawingController, DrawAxes, DrawingPreview, attachDrawing, drawAxesOf, DRAW_DRAG_SLOP_PT,
} from '../src/m/chart/drawing'
import { ViewWindow, priceRange, priceTransform, pOf, yOf, type Pane, type PriceRange } from '../src/m/chart/geometry'
import { BarSeries, INTERVAL_STEP, bar } from '../src/m/chart/series'
import { makeState, withInput, withOverlay, withViewport, type ChartState } from '../src/m/chart/state'
import { ChartView } from '../src/m/chart/view'
import { rows, coreFixture, Rng, synthSeries } from './m-chart-fixtures'

// ================================================================== DrawingTests（KanpanCore）

const idAxis = (v: number): number => v
const hit = (ds: Drawing[], px: number, py: number): DrawHit | null => hitDraw(ds, px, py, idAxis, idAxis)
const H = (id: string, part: DrawPart): DrawHit => ({ id, part })

describe('画线', () => {
  test('distSeg 与原型全等', () => {
    const rs = rows(coreFixture<{ cases: unknown }>('distseg').cases)
    expect(rs.length).toBe(120)
    for (const r of rs) expect(Math.abs(distSeg(r[0], r[1], r[2], r[3], r[4], r[5]) - r[6])).toBeLessThan(1e-12)
  })

  test('退化线段当点距算', () => {
    expect(Math.abs(distSeg(3, 4, 0, 0, 0, 0) - 5)).toBeLessThan(1e-12)
    expect(distSeg(0, 0, 0, 0, 0, 0)).toBe(0)
  })

  test('distSeg 的几何性质', () => {
    const r = new Rng(812)
    for (let k = 0; k < 20000; k++) {
      const x1 = r.d(-500, 500), y1 = r.d(-500, 500), x2 = r.d(-500, 500), y2 = r.d(-500, 500)
      const px = r.d(-500, 500), py = r.d(-500, 500)
      const d = distSeg(px, py, x1, y1, x2, y2)
      const t = r.d(0, 1)
      const da = Math.hypot(px - x1, py - y1), db = Math.hypot(px - x2, py - y2)
      const mx = x1 + t * (x2 - x1), my = y1 + t * (y2 - y1)
      const ok = d >= 0 && Number.isFinite(d)
        && distSeg(x1, y1, x1, y1, x2, y2) < 1e-9 && distSeg(x2, y2, x1, y1, x2, y2) < 1e-9
        && Math.abs(d - distSeg(px, py, x2, y2, x1, y1)) < 1e-9
        && d <= Math.min(da, db) + 1e-9
        && distSeg(mx, my, x1, y1, x2, y2) < 1e-9
      if (!ok) expect.fail(`第 ${k} 组不满足：${[px, py, x1, y1, x2, y2]}`)
    }
  })

  test('水平线命中', () => {
    const h = makeDrawing('hline', { t: 0, p: 100 }, null, null, 'h1')
    for (const x of [-1e6, 0, 37, 1e6]) {
      expect(hit([h], x, 100)).toEqual(H('h1', 'body'))
      expect(hit([h], x, 108.9)).toEqual(H('h1', 'body'))
      expect(hit([h], x, 91.1)).toEqual(H('h1', 'body'))
      expect(hit([h], x, 109.6)).toBeNull()
      expect(hit([h], x, 90.4)).toBeNull()
    }
    expect(hit([h], 0, 109.5)).toBeNull()
    expect(hit([h], 0, 90.5)).toBeNull()
  })

  test('趋势线线身命中', () => {
    const d = makeDrawing('trend', { t: 0, p: 0 }, { t: 100, p: 0 }, null, 't1')
    expect(hit([d], 50, 0)).toEqual(H('t1', 'body'))
    expect(hit([d], 50, 8.9)).toEqual(H('t1', 'body'))
    expect(hit([d], 50, 9.6)).toBeNull()
    expect(hit([d], 120, 0)).toBeNull()
    expect(hit([d], -20, 0)).toBeNull()
    // 缺第二点的 trend（数据脏了）直接跳过，不能崩
    const broken = makeDrawing('trend', { t: 0, p: 0 }, null, null, 't2')
    expect(hit([broken], 0, 0)).toBeNull()
  })

  test('手柄优先于线身', () => {
    const d = makeDrawing('trend', { t: 0, p: 0 }, { t: 200, p: 0 }, null, 't1')
    expect(hit([d], 0, 5)).toEqual(H('t1', 'a'))
    expect(hit([d], 200, 5)).toEqual(H('t1', 'b'))
    expect(hit([d], 0, 9)).toEqual(H('t1', 'a'))
    expect(hit([d], 200, -9)).toEqual(H('t1', 'b'))
    expect(hit([d], 0, 12.1)).toBeNull()
    expect(hit([d], 9, 0)).toEqual(H('t1', 'a'))
    expect(hit([d], 13, 0)).toEqual(H('t1', 'body'))
    const tiny = makeDrawing('trend', { t: 0, p: 0 }, { t: 2, p: 0 }, null, 't3')
    expect(hit([tiny], 1, 0)).toEqual(H('t3', 'a'))
  })

  test('后画的先命中', () => {
    const a = makeDrawing('hline', { t: 0, p: 100 }, null, null, 'd1')
    const b = makeDrawing('hline', { t: 0, p: 101 }, null, null, 'd2')
    expect(hit([a, b], 0, 100.5)?.id).toBe('d2')
    expect(hit([b, a], 0, 100.5)?.id).toBe('d1')
    expect(hit([], 0, 0)).toBeNull()
  })

  test('随机命中对拍', () => {
    const r = new Rng(1229)
    for (let n = 0; n < 3000; n++) {
      const ds: Drawing[] = []
      const count = r.i(1, 5)
      for (let k = 0; k < count; k++) {
        if (r.d() < 0.35) ds.push(makeDrawing('hline', { t: 0, p: r.d(-200, 200) }, null, null, `h${k}`))
        else {
          const at = r.d(-200, 200), ap = r.d(-200, 200), bt = r.d(-200, 200), bp = r.d(-200, 200)
          ds.push(makeDrawing('trend', { t: at, p: ap }, { t: bt, p: bp }, null, `t${k}`))
        }
      }
      const px = r.d(-220, 220), py = r.d(-220, 220)
      let want: DrawHit | null = null
      for (const d of ds.slice().reverse()) {
        const a = drawingA(d)
        if (d.kind === 'hline') {
          if (Math.abs(a.p - py) < 9.5) { want = H(d.id, 'body'); break }
          continue
        }
        const b = drawingB(d)!
        if (Math.hypot(px - a.t, py - a.p) < 9.5) { want = H(d.id, 'a'); break }
        if (Math.hypot(px - b.t, py - b.p) < 9.5) { want = H(d.id, 'b'); break }
        if (distSeg(px, py, a.t, a.p, b.t, b.p) < 9.5) { want = H(d.id, 'body'); break }
      }
      const got = hit(ds, px, py)
      if (JSON.stringify(got) !== JSON.stringify(want)) expect.fail(`第 ${n} 组：得到 ${JSON.stringify(got)}，应为 ${JSON.stringify(want)}`)
    }
  })

  test('水平线一点落成', () => {
    const s = new DrawingStore()
    s.place({ t: 1, p: 2 }, 'x')
    expect(s.items).toEqual([])
    s.tool = 'hline'
    s.place({ t: 1000, p: 50 }, 'h1')
    expect(s.items.length).toBe(1)
    expect(s.items[0].kind).toBe('hline')
    expect(drawingB(s.items[0])).toBeNull()
    expect(s.tool).toBeNull()
    expect(s.pending).toBeNull()
  })

  test('趋势线两点落成', () => {
    const s = new DrawingStore()
    s.tool = 'trend'
    s.place({ t: 1000, p: 50 }, 't1')
    expect(s.items).toEqual([])
    expect(s.pending).toEqual({ t: 1000, p: 50 })
    expect(s.tool).toBe('trend')
    s.place({ t: 2000, p: 60 }, 't1')
    expect(s.items.length).toBe(1)
    expect(drawingA(s.items[0])).toEqual({ t: 1000, p: 50 })
    expect(drawingB(s.items[0])).toEqual({ t: 2000, p: 60 })
    expect(s.pending).toBeNull()
    expect(s.tool).toBeNull()
  })

  test('删除与清空', () => {
    const s = new DrawingStore()
    s.tool = 'hline'; s.place({ t: 0, p: 1 }, 'a')
    s.tool = 'hline'; s.place({ t: 0, p: 2 }, 'b')
    s.tool = 'hline'; s.place({ t: 0, p: 3 }, 'c')
    s.removeSelected()
    expect(s.items.length).toBe(3)
    s.selected = 'b'
    s.removeSelected()
    expect(s.items.map(d => d.id)).toEqual(['a', 'c'])
    expect(s.selected).toBeNull()
    s.tool = 'trend'; s.place({ t: 0, p: 9 })
    s.selected = 'a'
    s.clear()
    expect(s.items.length === 0 && s.selected == null && s.pending == null).toBe(true)
  })

  test('拖动端点与整条', () => {
    const s = new DrawingStore()
    s.tool = 'trend'
    s.place({ t: 1000, p: 50 })
    s.place({ t: 2000, p: 60 })
    const start = cloneDrawing(s.items[0])
    const id = start.id
    s.move(id, 'a', start, 100, -5)
    expect(drawingA(s.items[0])).toEqual({ t: 1100, p: 45 })
    expect(drawingB(s.items[0])).toEqual(drawingB(start))
    s.move(id, 'b', start, -300, 7)
    expect(drawingB(s.items[0])).toEqual({ t: 1700, p: 67 })
    expect(drawingA(s.items[0])).toEqual({ t: 1100, p: 45 })
    s.move(id, 'body', start, 10, 1)
    s.move(id, 'body', start, 20, 2)
    expect(drawingA(s.items[0])).toEqual({ t: 1020, p: 52 })
    expect(drawingB(s.items[0])).toEqual({ t: 2020, p: 62 })

    const h = new DrawingStore()
    h.tool = 'hline'
    h.place({ t: 0, p: 100 }, 'h')
    const hs = cloneDrawing(h.items[0])
    h.move('h', 'body', hs, 500, -10)
    expect(drawingA(h.items[0])).toEqual({ t: 500, p: 90 })
    expect(drawingB(h.items[0])).toBeNull()
    h.move('h', 'b', hs, 1, 1)
    expect(drawingB(h.items[0])).toBeNull()
    h.move('nope', 'a', hs, 1, 1)
    expect(h.items.length).toBe(1)
  })

  test('画线价格进区间', () => {
    const s = new DrawingStore()
    expect(s.prices).toEqual([])
    s.tool = 'hline'; s.place({ t: 0, p: 100 })
    s.tool = 'trend'; s.place({ t: 0, p: 50 }); s.place({ t: 1, p: 150 })
    expect(s.prices.slice().sort((a, b) => a - b)).toEqual([50, 100, 150])
    const series = synthSeries(200, { interval: '1h', t0: 1_700_000_000_000, seed: 7 })
    const view = new ViewWindow(series.t0 + series.step * series.count, 100 * 3_600_000)
    const base = priceRange(view, series)
    const w = priceRange(view, series, { drawingPrices: s.prices })
    expect(w.lo).toBeLessThanOrEqual(Math.min(base.lo, 50) + 1e-9)
    expect(w.hi).toBeGreaterThanOrEqual(Math.max(base.hi, 150) - 1e-9)
  })

  test('默认 ID 不撞', () => {
    const s = new DrawingStore()
    for (let k = 0; k < 50; k++) { s.tool = 'hline'; s.place({ t: 0, p: 1 }) }
    expect(new Set(s.items.map(d => d.id)).size).toBe(50)
  })

  test('编解码来回', () => {
    const ds = [
      makeDrawing('hline', { t: 1e12, p: 0.00012345 }, null, null, 'h'),
      makeDrawing('trend', { t: 1, p: 2 }, { t: 3, p: 4 }, '#ff8800', 't'),
    ]
    const back = (JSON.parse(JSON.stringify(ds.map(encodeDrawing))) as unknown[]).map(decodeDrawing)
    expect(drawingsEqual(back, ds)).toBe(true)
    expect(back[1].color).toBe('#ff8800')
  })

  const keysOf = (d: Drawing): Record<string, unknown> => JSON.parse(JSON.stringify(encodeDrawing(d))) as Record<string, unknown>

  test('清空文字编码成空串，不是把键省掉', () => {
    const note = makeDrawing('note', { t: 1_800_000_000_000, p: 100 }, null, null, 'n')
    note.text = '顶背离'
    expect(keysOf(note).text).toBe('顶背离')
    note.text = ''
    const cleared = keysOf(note)
    expect('text' in cleared).toBe(true)
    expect(cleared.text).toBe('')
    expect(decodeDrawing(JSON.parse(JSON.stringify(encodeDrawing(note)))).text).toBe('')
    for (const kind of DrawKind.all) {
      if (!DrawKind.usesText(kind)) continue
      const d = drawingWith(kind, Array.from({ length: DrawKind.pointCount(kind) }, (_, i) => ({ t: 1e12 + i, p: 100 })), 'x')
      d.text = ''
      expect('text' in keysOf(d), kind).toBe(true)
    }
    expect('text' in keysOf(makeDrawing('trend', { t: 1, p: 2 }, { t: 3, p: 4 }, null, 't'))).toBe(false)
  })

  test('收到 text: null 也解成空文字', () => {
    const json = '{"id":"n","kind":"note","points":[{"t":1800000000000,"p":100}],"lineWidth":1.3,'
      + '"dash":"solid","filled":true,"locked":false,"hidden":false,"levels":[0],"text":null}'
    expect(decodeDrawing(JSON.parse(json)).text).toBe('')
  })

  test('60 个字素簇都算一个字', () => {
    const family = '👨‍👩‍👧‍👦'
    expect(new TextEncoder().encode(family).length).toBe(25)
    const note = makeDrawing('note', { t: 1_800_000_000_000, p: 100 }, null, null, 'n')
    note.text = family.repeat(60)
    expect(drawingIsValid(note)).toBe(true)
    note.text = family.repeat(61)
    expect(drawingIsValid(note)).toBe(false)
    note.text = '顶'.repeat(60)
    expect(drawingIsValid(note)).toBe(true)
  })

  test('换画法不改点数', () => {
    for (const kind of DrawKind.all) {
      for (const swap of DrawKind.swaps(kind)) {
        expect(swap.options.length, kind).toBeGreaterThan(0)
        expect(swap.options.some(o => o.kind === kind), kind).toBe(true)
        for (const o of swap.options) {
          expect(DrawKind.pointCount(o.kind), `${kind} → ${o.kind}`).toBe(DrawKind.pointCount(kind))
          expect(DrawKind.swaps(o.kind)[0]?.options.map(x => x.kind)).toEqual(swap.options.map(x => x.kind))
        }
      }
    }
  })

  test('面板上的十二把都画得出来', () => {
    expect(DrawKind.palette.length).toBe(12)
    expect(new Set(DrawKind.palette).size).toBe(12)
    for (const k of DrawKind.palette) {
      expect(DrawKind.placeCount(k)).toBeGreaterThanOrEqual(1)
      expect(DrawKind.placeCount(k)).toBeLessThanOrEqual(3)
    }
    for (const gone of ['rectangle', 'ray', 'hray', 'extended', 'crossLine', 'priceRange'] as DrawingKind[]) {
      expect(DrawKind.palette.includes(gone), gone).toBe(false)
    }
  })
})

// ================================================================== DrawingEditTests（KanpanCore）

describe('画线编辑', () => {
  test('磁吸开：时间吸根、价格吸开高低收', () => {
    const s = synthSeries(200, { interval: '1h', seed: 31 })
    const i = 57
    const t = s.time(i) + s.step * 0.31
    const want = s.high[i]
    const snap = snapDrawPointSimple(t, want * 1.0001, s, true)
    expect(snap.index).toBe(i)
    expect(snap.point.t).toBe(s.time(i))
    expect(snap.point.p).toBe(want)
    for (const p of [s.open[i], s.high[i], s.low[i], s.close[i]]) expect(snapDrawPointSimple(t, p, s, true).point.p).toBe(p)
  })

  test('磁吸关：原样落点', () => {
    const s = synthSeries(50, { seed: 3 })
    const snap = snapDrawPointSimple(1.5, 2.5, s, false)
    expect(snap.point).toEqual({ t: 1.5, p: 2.5 })
    expect(snap.index).toBe(-1)
  })

  test('空序列不吸也不崩', () => {
    const empty = new BarSeries({ symbol: 'X', interval: '1h', t0: 0, open: [], high: [], low: [], close: [], volume: [] })
    const snap = snapDrawPointSimple(9, 9, empty, true)
    expect(snap).toEqual({ point: { t: 9, p: 9 }, index: -1 })
  })

  test('不等距周期吸到真 openTime', () => {
    const times = [1_704_067_200_000, 1_706_745_600_000, 1_709_251_200_000, 1_711_929_600_000]
    const s = new BarSeries({
      symbol: 'X', interval: '1M', t0: times[0], step: INTERVAL_STEP['1M'],
      open: [1, 2, 3, 4], high: [2, 3, 4, 5], low: [0.5, 1.5, 2.5, 3.5], close: [1.5, 2.5, 3.5, 4.5], volume: [1, 1, 1, 1], openTime: times,
    })
    const snap = snapDrawPointSimple(times[2] + 5 * 86_400_000, 3.4, s, true)
    expect(snap.index).toBe(2)
    expect(snap.point.t).toBe(times[2])
    expect(snap.point.p).toBe(3.5)
  })

  test('拖端点 / 拖整条', () => {
    const d = makeDrawing('trend', { t: 1000, p: 10 }, { t: 2000, p: 20 }, null, 't')
    const shift = (p: number): number => p + 3
    const a = movedDrawing(d, 'a', 500, shift)
    expect(drawingA(a)).toEqual({ t: 1500, p: 13 })
    expect(drawingB(a)).toEqual(drawingB(d))
    const b = movedDrawing(d, 'b', -500, shift)
    expect(drawingB(b)).toEqual({ t: 1500, p: 23 })
    expect(drawingA(b)).toEqual(drawingA(d))
    const body = movedDrawing(d, 'body', 100, shift)
    expect(drawingA(body)).toEqual({ t: 1100, p: 13 })
    expect(drawingB(body)).toEqual({ t: 2100, p: 23 })
    const again = movedDrawing(d, 'body', 200, p => p + 6)
    expect(drawingA(again)).toEqual({ t: 1200, p: 16 })
  })

  test('水平线整条拖只动价格', () => {
    const h = makeDrawing('hline', { t: 1000, p: 10 }, null, null, 'h')
    const moved = movedDrawing(h, 'body', 9999, p => p - 2)
    expect(drawingA(moved)).toEqual({ t: 1000, p: 8 })
    expect(drawingB(moved)).toBeNull()
    expect(drawingEquals(movedDrawing(h, 'b', 1, p => p + 1), h)).toBe(true)
  })

  test('对数模式下按像素平移', () => {
    const pane: Pane = { indicator: null, y: 0, h: 400 }
    const r: PriceRange = { lo: 100, hi: 10_000, base: 100, inverted: false }
    const dy = 40
    const shift = (p: number): number => pOf(yOf(p, pane, r, 'log') + dy, pane, r, 'log')
    const d = makeDrawing('trend', { t: 0, p: 200 }, { t: 1, p: 5000 }, null, 't')
    const m = movedDrawing(d, 'body', 0, shift)
    const da = 200 - drawingA(m).p
    const db = drawingB(m)!.p
    expect(da > 0 && 5000 - db > 0).toBe(true)
    expect(5000 - db).toBeGreaterThan(da * 5)
    for (const [p0, p1] of [[200, drawingA(m).p], [5000, db]]) {
      expect(Math.abs(yOf(p1, pane, r, 'log') - yOf(p0, pane, r, 'log') - dy)).toBeLessThan(1e-6)
    }
  })

  const line = (n: number): Drawing => makeDrawing('hline', { t: 0, p: n }, null, null, `d${n}`)

  test('撤销重做走一圈', () => {
    const h = new DrawHistory()
    let items: Drawing[] = []
    expect(!h.canUndo && !h.canRedo).toBe(true)
    for (let n = 1; n <= 3; n++) { h.commit(items); items = items.concat([line(n)]) }
    expect(items.length === 3 && h.canUndo && !h.canRedo).toBe(true)
    items = h.undo(items)!
    expect(items.map(d => d.id)).toEqual(['d1', 'd2'])
    items = h.undo(items)!
    expect(items.map(d => d.id)).toEqual(['d1'])
    expect(h.canRedo).toBe(true)
    items = h.redo(items)!
    expect(items.map(d => d.id)).toEqual(['d1', 'd2'])
    items = h.redo(items)!
    expect(items.map(d => d.id)).toEqual(['d1', 'd2', 'd3'])
    expect(h.canRedo).toBe(false)
    expect(h.redo(items)).toBeNull()
  })

  test('撤销到底就停', () => {
    const h = new DrawHistory()
    expect(h.undo([])).toBeNull()
    h.commit([])
    expect(h.undo([makeDrawing('hline', { t: 0, p: 1 })])).not.toBeNull()
    expect(h.undo([])).toBeNull()
  })

  test('撤销之后再动一笔，重做作废', () => {
    const a = makeDrawing('hline', { t: 0, p: 1 }, null, null, 'a')
    const h = new DrawHistory()
    h.commit([])
    let items = [a]
    items = h.undo(items)!
    expect(h.canRedo).toBe(true)
    h.commit(items)
    expect(h.canRedo).toBe(false)
  })

  test('撤销栈有上限', () => {
    const h = new DrawHistory()
    for (let n = 0; n < DrawHistory.depth + 20; n++) h.commit([makeDrawing('hline', { t: 0, p: 1 }, null, null, `d${n}`)])
    expect(h.past.length).toBe(DrawHistory.depth)
    expect(h.past[0][0].id).toBe('d20')
  })

  test('clear 清两摞', () => {
    const h = new DrawHistory()
    h.commit([])
    h.undo([makeDrawing('hline', { t: 0, p: 1 })])
    h.clear()
    expect(!h.canUndo && !h.canRedo).toBe(true)
  })

  const hl = (p: number, id: string = newDrawingID()): Drawing => makeDrawing('hline', { t: 1_700_000_000_000, p }, null, null, id)

  test('按品种隔离', () => {
    const a = new DrawArchive()
    a.set('BTCUSDT', [hl(1), hl(2), hl(3)])
    expect(a.get('BTCUSDT').length).toBe(3)
    expect(a.get('ETHUSDT')).toEqual([])
    a.set('ETHUSDT', [hl(9)])
    expect(a.get('BTCUSDT').length === 3 && a.get('ETHUSDT').length === 1).toBe(true)
    a.set('ETHUSDT', [])
    expect(a.bySymbol['binance/usd_m/ETHUSDT']).toBeUndefined()
  })

  test('每品种上限 50', () => {
    const a = new DrawArchive()
    expect(DrawArchive.perSymbolLimit).toBe(50)
    a.set('BTCUSDT', Array.from({ length: 49 }, (_, n) => hl(n, `d${n}`)))
    expect(a.hasRoom('BTCUSDT')).toBe(true)
    a.set('BTCUSDT', a.get('BTCUSDT').concat([hl(49, 'd49')]))
    expect(a.get('BTCUSDT').length).toBe(50)
    expect(a.hasRoom('BTCUSDT')).toBe(false)
    a.set('BTCUSDT', Array.from({ length: 60 }, (_, n) => hl(n, `d${n}`)))
    expect(a.get('BTCUSDT').length).toBe(60)
    expect(a.get('BTCUSDT')[0].id).toBe('d0')
  })

  test('存档编解码来回', () => {
    const a = new DrawArchive()
    a.set('BTCUSDT', [hl(64_321.5, 'h1'), makeDrawing('trend', { t: 1, p: 2 }, { t: 3, p: 4 }, '#ff8800', 't1')])
    a.set('ETHUSDT', [hl(3210.25, 'h2')])
    const back = decodeArchive(JSON.parse(JSON.stringify(encodeArchive(a))))
    expect(back.equals(a)).toBe(true)
    expect(back.get('BTCUSDT').at(-1)?.color).toBe('#ff8800')
  })

  test('老存档缺字段也能读', () => {
    const bare = decodeArchive({})
    expect(bare.version).toBe(DrawArchive.currentVersion)
    expect(Object.keys(bare.bySymbol)).toEqual([])
    const noVersion = decodeArchive(JSON.parse('{"d":{"BTCUSDT":[{"id":"h","kind":"hline","a":{"t":1,"p":2}}]}}'))
    expect(noVersion.get('BTCUSDT').length).toBe(1)
  })

  test('存档里有一条不认识的工具，只丢那一条', () => {
    const json = `{"v":2,"d":{"BTCUSDT":[
      {"id":"a","kind":"hline","a":{"t":1,"p":2}},
      {"id":"b","kind":"telekinesis","a":{"t":3,"p":4}},
      {"id":"c","kind":"trend","a":{"t":5,"p":6},"b":{"t":7,"p":8}}
    ],"ETHUSDT":[{"id":"d","kind":"vline","a":{"t":9,"p":10}}]}}`
    const archive = decodeArchive(JSON.parse(json))
    expect(archive.get('BTCUSDT').map(d => d.id)).toEqual(['a', 'c'])
    expect(archive.get('ETHUSDT').length).toBe(1)
    const allUnknown = decodeArchive(JSON.parse('{"v":2,"d":{"BTCUSDT":[{"id":"x","kind":"telekinesis","a":{"t":1,"p":2}}]}}'))
    expect(Object.keys(allUnknown.bySymbol)).toEqual([])
  })
})

describe('Drawing v2 持久化与几何', () => {
  test('射线裁到边上、原点背后不命中', () => {
    const bounds: DrawBounds = { left: 0, top: 0, right: 300, bottom: 200 }
    const ray = makeDrawing('ray', { t: 100, p: 100 }, { t: 150, p: 100 })
    const g = drawingGeometry(ray, bounds, idAxis, idAxis)
    expect(g.segments.length).toBe(1)
    expect(g.segments[0].b).toEqual({ x: 300, y: 100 })
    expect(g.hit(250, 100)).toBe('body')
    expect(g.hit(50, 100)).toBeNull()
    const hidden = { ...ray, hidden: true }
    expect(drawingGeometry(hidden, bounds, idAxis, idAxis).hit(125, 100)).toBeNull()
  })

  test('关了填充：面不出填充、点框里不命中；箭头尖是实心记号一直在；测量框底色不听开关', () => {
    const bounds: DrawBounds = { left: 0, top: 0, right: 300, bottom: 300 }
    const rect = { ...makeDrawing('rectangle', { t: 50, p: 50 }, { t: 250, p: 250 }), filled: false }
    const rg = drawingGeometry(rect, bounds, idAxis, idAxis)
    expect(rg.fills).toEqual([])
    expect(rg.segments.length).toBeGreaterThan(0)
    const arrow = makeDrawing('arrowLine', { t: 50, p: 50 }, { t: 250, p: 200 })
    const heads = drawingGeometry(arrow, bounds, idAxis, idAxis).fills
    expect(heads.length).toBe(1)
    expect(heads[0].solid && heads[0].opacity === 1).toBe(true)
    expect(drawingGeometry({ ...arrow, filled: false }, bounds, idAxis, idAxis).fills.length).toBe(1)
    const callout = { ...makeDrawing('callout', { t: 50, p: 50 }, { t: 200, p: 150 }), text: '看这里', filled: false }
    const cf = drawingGeometry(callout, bounds, idAxis, idAxis).fills
    expect(cf.length > 0 && cf.every(f => f.solid)).toBe(true)
    const measure = { ...makeDrawing('measure', { t: 50, p: 250 }, { t: 250, p: 50 }), filled: false }
    expect(drawingGeometry(measure, bounds, idAxis, idAxis).fills.some(f => !f.solid)).toBe(true)
  })

  test('通道在对数坐标里平行', () => {
    const d = drawingWith('channel', [{ t: 20, p: 100 }, { t: 100, p: 300 }, { t: 50, p: 400 }])
    const g = drawingGeometry(d, { left: 0, top: 0, right: 300, bottom: 300 }, idAxis, p => Math.log(p) * 30)
    expect(g.segments.length).toBe(3)
    const slopes = g.segments.map(s => (s.b.y - s.a.y) / (s.b.x - s.a.x))
    expect(Math.abs(slopes[0] - slopes[1])).toBeLessThan(1e-10)
    expect(Math.abs(slopes[0] - slopes[2])).toBeLessThan(1e-10)
    const locked = { ...d, locked: true }
    expect(movedDrawing(locked, 'c', 10, p => p + 10)).toBe(locked)
  })

  test('吸住就别松：横扫锚点不在吸附点与手指之间逐帧翻面', () => {
    const bars = 22
    const step = INTERVAL_STEP['1h']
    const close = Array.from({ length: bars }, (_, i) => (i % 2 === 0 ? 91 : 112))
    const s = new BarSeries({
      symbol: 'X', interval: '1h', t0: 0, open: new Array(bars).fill(150), high: new Array(bars).fill(160),
      low: new Array(bars).fill(50), close, volume: new Array(bars).fill(1),
    })
    const barW = 8
    const x = (t: number): number => t / step * barW
    const y = (p: number): number => p
    const fingerP = 100
    const fingerT = (px: number): number => px / barW * step
    const sweep: number[] = []
    for (let px = 0; px <= barW * (bars - 2); px += 1) sweep.push(px)

    let flips = 0
    let was: boolean | null = null
    for (const px of sweep) {
      const on = snapDrawPoint(fingerT(px), fingerP, s, true, x, y).index >= 0
      if (was != null && was !== on) flips += 1
      was = on
    }
    expect(flips).toBeGreaterThan(5)

    let current: DrawSnap | null = null
    let attached = false
    let lastT = -Infinity
    const indexes: number[] = []
    for (const px of sweep) {
      const snap: DrawSnap = snapDrawPoint(fingerT(px), fingerP, s, true, x, y, 10, current)
      current = snap
      if (snap.index >= 0) attached = true
      if (!attached) continue
      expect(snap.index, `x=${px}`).toBeGreaterThanOrEqual(0)
      expect(snap.point.p, `x=${px}`).not.toBe(fingerP)
      expect(snap.point.t).toBeGreaterThanOrEqual(lastT)
      lastT = snap.point.t
      indexes.push(snap.index)
    }
    expect(indexes[0]).toBe(0)
    expect(indexes.at(-1) ?? -1).toBeGreaterThanOrEqual(bars - 4)
    const holding: DrawSnap = { point: { t: 0, p: 91 }, index: 0 }
    const hop = snapDrawPoint(fingerT(16), 91, s, true, x, y, 10, holding)
    expect(hop.index).toBe(2)
    expect(hop.point.t).toBe(step * 2)
    expect(snapDrawPoint(0, 105, s, true, x, y, 10, holding)).toEqual(holding)
    const outside = snapDrawPoint(0, 111, s, true, x, y, 10, holding)
    expect(outside).toEqual({ point: { t: 0, p: 111 }, index: -1 })
  })

  test('弱磁吸按像素', () => {
    const s = synthSeries(30, { seed: 3 })
    const i = 12, t = s.time(12), p = s.high[12]
    const x = (v: number): number => (v - t) / s.step * 8
    const y = (v: number): number => Math.log(v) * 300
    expect(snapDrawPoint(t, Math.exp(Math.log(p) + 0.01), s, true, x, y).index).toBe(i)
    const far = snapDrawPoint(t, p * 3, s, true, x, y)
    expect(far.index).toBe(-1)
    expect(far.point.p).toBe(p * 3)
    expect(snapDrawPoint(t + s.step * 100, p, s, true, x, y).index).toBe(-1)
  })
})

// ================================================================== DrawingBookTests（KanpanCore）

describe('画线真值', () => {
  const ln = (id: string, p = 100): Drawing => drawingWith('hline', [{ t: 1_000, p }], id)

  test('本地编辑：进撤销栈、发 edited，没变就什么都不发', () => {
    const book = new DrawingBook()
    const ear: DrawingBookChange[] = []
    book.observe(ear, c => ear.push(c))
    expect(book.commit([ln('a')], 'BTCUSDT')).toBe(true)
    expect(book.commit([ln('a')], 'BTCUSDT')).toBe(false)
    expect(ear).toEqual([{ kind: 'edited', key: canonicalInstrument('BTCUSDT') }])
    expect(book.history('BTCUSDT').canUndo).toBe(true)
    expect(book.undo('BTCUSDT')).toBe(true)
    expect(book.items('BTCUSDT')).toEqual([])
    expect(book.redo('BTCUSDT')).toBe(true)
    expect(drawingsEqual(book.items('BTCUSDT'), [ln('a')])).toBe(true)
    expect(ear.length).toBe(3)
  })

  test('一次收下整批：一步撤销，已有的 id 跳过；放不下就整批不写', () => {
    const book = new DrawingBook()
    expect(book.add([ln('a'), ln('b')], 'BTCUSDT')).toBe(true)
    expect(book.add([ln('a')], 'BTCUSDT')).toBe(true)
    expect(book.items('BTCUSDT').length).toBe(2)
    expect(book.undo('BTCUSDT') && book.items('BTCUSDT').length === 0).toBe(true)
    const many = Array.from({ length: DrawArchive.perSymbolLimit }, (_, n) => ln(`l${n}`, n))
    expect(book.add(many, 'ETHUSDT')).toBe(true)
    expect(book.hasRoom('ETHUSDT')).toBe(false)
    expect(book.add([ln('extra')], 'ETHUSDT')).toBe(false)
    expect(book.items('ETHUSDT').length).toBe(DrawArchive.perSymbolLimit)
  })

  test('整份替换：只有真变了的桶清撤销、在 replaced 里列出来', () => {
    const book = new DrawingBook()
    book.commit([ln('btc')], 'BTCUSDT')
    book.commit([ln('eth')], 'ETHUSDT')
    const ear: DrawingBookChange[] = []
    book.observe(ear, c => ear.push(c))
    const next = book.archive.clone()
    next.set('ETHUSDT', [ln('eth', 200)])
    book.replace(next)
    const eth = canonicalInstrument('ETHUSDT')
    expect(ear).toEqual([{ kind: 'replaced', keys: new Set([eth]) }])
    expect(book.history('BTCUSDT').canUndo).toBe(true)
    expect(book.history('ETHUSDT').canUndo).toBe(false)
    book.replace(next.clone())
    expect(ear.length).toBe(1)
    book.replace(next.clone(), true)
    expect(book.history('BTCUSDT').canUndo).toBe(false)
  })

  test('镜像不进撤销、不发通知；偏好改了也不发', () => {
    const book = new DrawingBook()
    const ear: DrawingBookChange[] = []
    book.observe(ear, c => ear.push(c))
    book.mirror([ln('snap')], 'BTCUSDT')
    book.preferences.magnet = !book.preferences.magnet
    expect(drawingsEqual(book.items('BTCUSDT'), [ln('snap')])).toBe(true)
    expect(book.history('BTCUSDT').canUndo).toBe(false)
    expect(ear).toEqual([])
  })

  test('观察者按登记顺序听，主人退订就摘掉；空撤销栈不占格子', () => {
    // Swift 靠弱引用在主人释放时自动摘掉；JS 没有确定时机的弱引用，宿主显式 stopObserving。
    const book = new DrawingBook()
    const order: string[] = []
    const first = {}, second = {}
    book.observe(first, () => order.push('first'))
    book.observe(second, () => order.push('second'))
    book.commit([ln('a')], 'BTCUSDT')
    expect(order).toEqual(['first', 'second'])
    book.stopObserving(second)
    book.commit([], 'BTCUSDT')
    expect(order).toEqual(['first', 'second', 'first'])
    book.setHistory(new DrawHistory(), 'BTCUSDT')
    expect(book.history('BTCUSDT').canUndo).toBe(false)
  })
})

// ================================================================== DrawingKindNameTests（KanpanCore）
// 两条 Alert 文案用例（legacyAlertLineNames / alertNamesUseTheDisplaySymbol）属 app 层提醒模块，不在图表引擎里，跳过。

describe('画线：画法在各处只有一个名字', () => {
  test('样式表那排按钮上的字就是这种画法的名字', () => {
    for (const head of DrawKind.palette) {
      for (const swap of DrawKind.swaps(head)) {
        for (const o of swap.options) if (o.kind !== head) expect(o.label, o.kind).toBe(DrawKind.title(o.kind))
      }
    }
  })

  test('面板上十二把工具各有一个名字，全是中文', () => {
    const names = DrawKind.palette.map(DrawKind.title)
    expect(new Set(names).size).toBe(names.length)
    expect(names.every(n => n.length > 0 && !n.includes('VWAP'))).toBe(true)
  })

  test('向右延伸 / 两端延伸 / 十字线', () => {
    expect(DrawKind.title('ray')).toBe('向右延伸')
    expect(DrawKind.title('extended')).toBe('两端延伸')
    expect(DrawKind.title('hray')).toBe('向右延伸')
    expect(DrawKind.title('crossLine')).toBe('十字线')
    expect(DrawKind.swaps('hline')[0]?.options.map(o => o.label)).toEqual(['整条', '向右延伸'])
    expect(DrawKind.swaps('trend')[0]?.options.map(o => o.label)).toEqual(['线段', '向右延伸', '两端延伸', '箭头'])
  })
})

// ================================================================== DrawingVariantTests（KanpanCore）

describe('画线：每一族记住上次选的画法', () => {
  const two: DrawPoint[] = [{ t: 1_000, p: 10 }, { t: 2_000, p: 12 }]
  const one: DrawPoint[] = [{ t: 1_000, p: 10 }]

  test('三族在面板上各有一格，族里每一种都认得回那一格', () => {
    const families: [DrawingKind, DrawingKind[]][] = [
      ['trend', ['trend', 'ray', 'extended', 'arrowLine']],
      ['hline', ['hline', 'hray']],
      ['vline', ['vline', 'crossLine']],
    ]
    for (const [head, members] of families) {
      expect(DrawKind.palette.includes(head)).toBe(true)
      for (const k of members) expect(DrawKind.paletteHead(k), k).toBe(head)
    }
    for (const k of ['channel', 'fibonacci', 'measure', 'note', 'position'] as DrawingKind[]) expect(DrawKind.paletteHead(k)).toBeNull()
  })

  test('换成两端延伸之后，面板点趋势线落下来的是两端延伸', () => {
    const prefs = new DrawingPreferences()
    expect(prefs.newDrawing('trend', two).kind).toBe('trend')
    expect(prefs.rememberSwap('trend', 'extended')).toBe(true)
    expect(prefs.variants).toEqual({ trend: 'extended' })
    const next = prefs.newDrawing('trend', two)
    expect(next.kind).toBe('extended')
    expect(drawingIsValid(next)).toBe(true)
    expect(prefs.rememberSwap('extended', 'ray')).toBe(true)
    expect(prefs.newDrawing('trend', two).kind).toBe('ray')
    expect(prefs.rememberSwap('ray', 'trend')).toBe(true)
    expect(prefs.newDrawing('trend', two).kind).toBe('trend')
    expect(prefs.rememberSwap('ray', 'trend')).toBe(false)
  })

  test('三族互不相干', () => {
    const prefs = new DrawingPreferences()
    prefs.rememberSwap('hline', 'hray')
    prefs.rememberSwap('vline', 'crossLine')
    expect(prefs.newDrawing('hline', one).kind).toBe('hray')
    expect(prefs.newDrawing('vline', one).kind).toBe('crossLine')
    expect(prefs.newDrawing('trend', two).kind).toBe('trend')
    expect(prefs.newDrawing('channel', two.concat(one)).kind).toBe('channel')
  })

  test('跨族的换法不记，坏值不用', () => {
    const prefs = new DrawingPreferences()
    expect(prefs.rememberSwap('trend', 'hray')).toBe(false)
    expect(prefs.rememberSwap('fibonacci', 'fibExtension')).toBe(false)
    expect(prefs.variants).toEqual({})
    prefs.variants = { trend: 'hray', hline: 'extended' }
    expect(prefs.kindFor('trend')).toBe('trend')
    expect(prefs.kindFor('hline')).toBe('hline')
    prefs.variants = { trend: 'extended' }
    expect(prefs.kindFor('ray')).toBe('ray')
  })

  test('样式各存各的：换过的那种有自己的就用自己的，没有就沿用面板那一格的', () => {
    const prefs = new DrawingPreferences()
    const red = drawingWith('trend', two); red.color = '#FF0000'; red.lineWidth = 3
    prefs.styles.trend = styleOf(red)
    prefs.rememberSwap('trend', 'extended')
    let next = prefs.newDrawing('trend', two)
    expect(next.kind).toBe('extended')
    expect(next.color).toBe('#FF0000')
    expect(next.lineWidth).toBe(3)
    const blue = drawingWith('extended', two); blue.color = '#0000FF'
    prefs.styles.extended = styleOf(blue)
    next = prefs.newDrawing('trend', two)
    expect(next.color).toBe('#0000FF')
    expect(prefs.styles.trend?.color).toBe('#FF0000')
  })

  test('线型与填充不再给选：记住的样式里存着虚线 / 不填充，新线也按实线、填充落', () => {
    const prefs = new DrawingPreferences()
    const old = drawingWith('rectangle', two)
    old.color = '#FF0000'; old.lineWidth = 2; old.dash = 'dotted'; old.filled = false
    prefs.styles.rectangle = styleOf(old)
    const next = prefs.newDrawing('rectangle', two)
    expect(next.color === '#FF0000' && next.lineWidth === 2).toBe(true)
    expect(next.dash === 'solid' && next.filled).toBe(true)
  })

  test('存档往返；老存档与云端缺 variants 键照常读；认不出的画法丢掉不整份抛', () => {
    const prefs = new DrawingPreferences()
    prefs.rememberSwap('trend', 'extended')
    prefs.rememberSwap('hline', 'hray')
    expect(decodePreferences(JSON.parse(JSON.stringify(encodePreferences(prefs)))).equals(prefs)).toBe(true)

    const legacy = decodePreferences(JSON.parse('{"favorites":["trend"],"magnet":false,"continuous":true,"styles":{}}'))
    expect(legacy.variants).toEqual({})
    expect(legacy.magnet).toBe(false)
    expect(legacy.kindFor('trend')).toBe('trend')

    const newer = decodePreferences(JSON.parse('{"variants":{"trend":"curvedTrend","vline":"crossLine"}}'))
    expect(newer.variants).toEqual({ vline: 'crossLine' })

    const mixed = '{"favorites":["trend","laserBeam"],"magnet":false,"styles":{'
      + '"trend":{"lineWidth":2,"dash":"solid","filled":true,"levels":[]},'
      + '"hline":{"lineWidth":2,"dash":"wavy","filled":true,"levels":[]}},'
      + '"variants":{"trend":"extended"}}'
    const tolerant = decodePreferences(JSON.parse(mixed))
    expect(tolerant.favorites).toEqual(['trend'])
    expect(tolerant.magnet).toBe(false)
    expect(Object.keys(tolerant.styles).sort()).toEqual(['trend'])
    expect(tolerant.styles.trend?.lineWidth).toBe(2)
    expect(tolerant.variants).toEqual({ trend: 'extended' })

    const lineD = drawingWith('hline', [{ t: 1, p: 2 }])
    const broken = `{"v":3,"preferences":{"magnet":"yes"},"d":{"BTCUSDT":[${JSON.stringify(encodeDrawing(lineD))}]}}`
    const kept = decodeArchive(JSON.parse(broken))
    expect(kept.get('BTCUSDT').map(d => d.id)).toEqual([lineD.id])
    expect(kept.preferences.equals(new DrawingPreferences())).toBe(true)

    const archive = new DrawArchive()
    archive.preferences = prefs
    const round = decodeArchive(JSON.parse(JSON.stringify(encodeArchive(archive))))
    expect(round.preferences.variants).toEqual({ trend: 'extended', hline: 'hray' })
  })
})

// ================================================================== DrawArchiveCapTests（KanpanCore）

describe('画线 · 进门上限', () => {
  const lines = (count: number, prefix: string): Drawing[] =>
    Array.from({ length: count }, (_, n) => drawingWith('hline', [{ t: 1, p: n }], `${prefix}${n}`))
  const total = (a: DrawArchive): number => Object.values(a.bySymbol).reduce((s, b) => s + b.length, 0)

  test('300 条的桶裁到 50 条，留数组尾上最新的；不满的桶一根不动；返回每只丢了几条', () => {
    const archive = new DrawArchive()
    archive.set('binance/usd_m/BTCUSDT', lines(300, 'b'))
    archive.set('binance/usd_m/ETHUSDT', lines(50, 'e'))
    archive.set('binance/usd_m/SOLUSDT', lines(3, 's'))
    expect(total(archive)).toBe(353)
    const dropped = archive.capToLimit()
    expect(total(archive)).toBe(103)
    expect(dropped).toEqual({ [canonicalInstrument('binance/usd_m/BTCUSDT')]: 250 })
    expect(archive.get('binance/usd_m/BTCUSDT').map(d => d.id)).toEqual(Array.from({ length: 50 }, (_, n) => `b${250 + n}`))
    expect(archive.get('binance/usd_m/ETHUSDT').length).toBe(50)
    expect(archive.get('binance/usd_m/SOLUSDT').length).toBe(3)
    expect(archive.capToLimit()).toEqual({})
  })

  test('一串线的最新 50 条', () => {
    expect(DrawArchive.newest(lines(51, 'x')).map(d => d.id)).toEqual(Array.from({ length: 50 }, (_, n) => `x${n + 1}`))
    expect(DrawArchive.newest(lines(7, 'x')).length).toBe(7)
  })

  test('有年龄的按年龄丢最老、没年龄的算最新；留下的保持桶里先后；重复裁不换批', () => {
    const all = lines(80, 'x')
    const age = (d: Drawing): DrawAge | null => {
      const n = Number(d.id.slice(1))
      return n >= 75 ? null : { timestamp: 1_000 - n, logical: 0 }
    }
    const a = new DrawArchive()
    a.set('BTCUSDT', all)
    expect(a.capToLimit(age)).toEqual({ [canonicalInstrument('BTCUSDT')]: 30 })
    const want = [...Array.from({ length: 45 }, (_, n) => `x${n}`), ...Array.from({ length: 5 }, (_, n) => `x${75 + n}`)]
    expect(a.get('BTCUSDT').map(d => d.id)).toEqual(want)
    const kept = a.get('BTCUSDT')
    const keptIDs = new Set(kept.map(d => d.id))
    a.set('BTCUSDT', kept.concat(all.filter(d => !keptIDs.has(d.id)).reverse()))
    a.capToLimit(age)
    expect(drawingsEqual(a.get('BTCUSDT'), kept)).toBe(true)
  })
})

// ================================================================== DrawVolumeTests（KanpanCore）

describe('锚定 VWAP 与成交量分布', () => {
  const t0 = 1_700_000_000_000
  const step = INTERVAL_STEP['1h']
  const time = (i: number): number => t0 + i * step
  type B5 = [number, number, number, number, number]
  const series = (bars: B5[]): BarSeries =>
    BarSeries.fromBars('TEST', '1h', bars.map((b, i) => bar(t0 + i * step, b[0], b[1], b[2], b[3], b[4])))
  const three = series([[10, 12, 8, 10, 100], [15, 22, 14, 18, 200], [25, 30, 24, 27, 300]])
  const bounds: DrawBounds = { left: 0, top: 0, right: 600, bottom: 400 }
  const x = (t: number): number => (t - t0) / step * 100 + 50
  const y = (p: number): number => 400 - p / 40 * 400
  const sum = (a: number[]): number => a.reduce((s, v) => s + v, 0)

  test('VWAP 逐根就是 Σ(hlc3·v)/Σv', () => {
    const trail = vwapTrail(time(0), three)!
    expect(trail.start).toBe(0)
    expect(trail.values.length).toBe(3)
    expect(Math.abs(trail.values[0] - 10)).toBeLessThan(1e-9)
    expect(Math.abs(trail.values[1] - 4600 / 300)).toBeLessThan(1e-9)
    expect(Math.abs(trail.values[2] - 12700 / 600)).toBeLessThan(1e-9)
    expect(Math.abs((trail.latest ?? 0) - 12700 / 600)).toBeLessThan(1e-9)
  })

  test('锚落在两根之间，从后面那根算起', () => {
    const trail = vwapTrail(time(0) + step / 2, three)!
    expect(trail.start).toBe(1)
    expect(trail.values.length).toBe(2)
    expect(Math.abs(trail.values[0] - 18)).toBeLessThan(1e-9)
    expect(Math.abs(trail.values[1] - (3600 + 8100) / 500)).toBeLessThan(1e-9)
  })

  test('锚在末根之后 → 没有轨迹', () => {
    expect(vwapTrail(time(2) + 1, three)).toBeNull()
    expect(vwapTrail(time(0), series([]))).toBeNull()
  })

  test('还没有成交的那一段是 NaN，不是 0', () => {
    const s = series([[10, 12, 8, 10, 0], [15, 22, 14, 18, 0], [25, 30, 24, 27, 50]])
    const trail = vwapTrail(time(0), s)!
    expect(trail.values[0]).toBeNaN()
    expect(trail.values[1]).toBeNaN()
    expect(Math.abs(trail.values[2] - 27)).toBeLessThan(1e-9)
  })

  test('按价格重叠摊量，总量守恒', () => {
    const s = series([[1, 12, 0, 10, 480], [13, 24, 12, 20, 240]])
    const vp = volumeProfile(time(0), time(1), s)!
    expect(vp.rowCount).toBe(VolumeProfile.rows)
    expect(Math.abs(vp.lo) < 1e-9 && Math.abs(vp.hi - 24) < 1e-9).toBe(true)
    expect(Math.abs(vp.total - 720)).toBeLessThan(1e-9)
    for (let row = 0; row < 12; row++) expect(Math.abs(vp.rowTotal(row) - 40), `第 ${row} 行`).toBeLessThan(1e-9)
    for (let row = 12; row < 24; row++) expect(Math.abs(vp.rowTotal(row) - 20), `第 ${row} 行`).toBeLessThan(1e-9)
  })

  test('一字线区间只有一行', () => {
    const vp = volumeProfile(time(0), time(1), series([[7, 7, 7, 7, 30], [7, 7, 7, 7, 70]]))!
    expect(vp.rowCount).toBe(1)
    expect(vp.rowHeight).toBe(0)
    expect(Math.abs(vp.total - 100)).toBeLessThan(1e-9)
    expect(vp.poc === 0 && vp.vaLow === 0 && vp.vaHigh === 0).toBe(true)
  })

  test('涨跌按蜡烛的口径拆', () => {
    const vp = volumeProfile(time(0), time(1), series([[2, 12, 0, 11, 120], [11, 12, 0, 2, 240]]))!
    expect(Math.abs(sum(vp.up) - 120)).toBeLessThan(1e-9)
    expect(Math.abs(sum(vp.down) - 240)).toBeLessThan(1e-9)
    const fp = volumeProfile(time(0), null, series([[5, 12, 0, 5, 60]]))!
    expect(Math.abs(sum(fp.up) - 60)).toBeLessThan(1e-9)
    expect(sum(fp.down)).toBe(0)
  })

  /** 把量精确地放进某一行：lo = 0、hi = 24 时一行正好 1 个价位。 */
  const peaks = (rs: [number, number][]): BarSeries => {
    const bars: B5[] = rs.map(([row, v]) => [row + 0.25, row + 0.75, row + 0.25, row + 0.75, v])
    bars.unshift([0, 0.5, 0, 0.5, 1])
    bars.push([23.5, 24, 23.5, 24, 1])
    return series(bars)
  }
  const fivePeaks = (): BarSeries => peaks([[12, 100], [13, 40], [14, 5], [11, 10], [10, 10]])

  test('三峰分布：POC 在最厚那层，价值区往量大的一侧扩', () => {
    const vp = volumeProfile(time(0), null, fivePeaks())!
    expect(Math.abs(vp.total - 167)).toBeLessThan(1e-9)
    expect(vp.poc).toBe(12)
    expect(Math.abs(vp.rowTotal(12) - 100)).toBeLessThan(1e-9)
    expect(vp.vaLow === 12 && vp.vaHigh === 14).toBe(true)
    let inside = 0
    for (let r = vp.vaLow; r <= vp.vaHigh; r++) inside += vp.rowTotal(r)
    expect(inside).toBeGreaterThanOrEqual(vp.total * VolumeProfile.valueArea)
  })

  test('toT 为空就一直算到末根', () => {
    const s = series([[1, 12, 0, 10, 480], [13, 24, 12, 20, 240], [20, 24, 18, 22, 60]])
    const open = volumeProfile(time(0), null, s)!
    expect(open.first === 0 && open.last === 2).toBe(true)
    expect(Math.abs(open.total - 780)).toBeLessThan(1e-9)
    const closed = volumeProfile(time(0), time(1), s)!
    expect(closed.last).toBe(1)
    expect(Math.abs(closed.total - 720)).toBeLessThan(1e-9)
    expect(volumeProfile(t0 - 1e9, time(0), s)?.first).toBe(0)
    expect(volumeProfile(time(2) + 1, null, s)).toBeNull()
  })

  test('VWAP 的几何：n-1 段 + 一枚读数 + 一个手柄', () => {
    const d = makeDrawing('anchoredVWAP', { t: time(0), p: 10 })
    const g = drawingGeometry(d, bounds, x, y, 2, three)
    expect(g.segments.length).toBe(2)
    expect(g.segments.every(s => !s.dashed)).toBe(true)
    expect(g.fills).toEqual([])
    expect(g.handles.length).toBe(1)
    expect(g.labels.length === 1 && g.labels[0].plate === 'chip').toBe(true)
    expect(g.labels[0].text).toBe('21.17')
    expect(Math.abs(g.segments[1].b.y - y(12700 / 600))).toBeLessThan(1e-9)
  })

  test('整段区间滚出图区就不画；水平射线起点滚出右沿时价签也不留', () => {
    const s = fivePeaks()
    const fixed = drawingWith('fixedVolumeProfile', [{ t: time(0), p: 20 }, { t: time(6), p: 4 }])
    const anchored = makeDrawing('anchoredVolumeProfile', { t: time(0), p: 20 })
    for (const d of [fixed, anchored]) {
      for (const shift of [-5000, 5000]) {
        const g = drawingGeometry(d, bounds, t => x(t) + shift, y, 2, s)
        expect(g.fills.length + g.segments.length + g.labels.length).toBe(0)
        expect(g.handles.length).toBe(d.points.length)
      }
      const half = drawingGeometry(d, bounds, t => x(t) - 300, y, 2, s)
      expect(half.fills.length > 0 && half.fills.every(f => f.points.every(p => p.x >= 0))).toBe(true)
    }
    const off = makeDrawing('hray', { t: time(10), p: 20 })
    const og = drawingGeometry(off, bounds, x, y, 2)
    expect(og.segments.length + og.labels.length).toBe(0)
    const on = drawingGeometry(makeDrawing('hray', { t: time(2), p: 20 }), bounds, x, y, 2)
    expect(on.segments.length === 1 && on.labels.length === 1).toBe(true)
  })

  test('计算结果按序列戳缓存：同一条序列只算一次，序列一改就重算，null 也记住（DrawVolumeTests · 待核实 3）', () => {
    let runs = 0
    const rev = 9_000_000_001
    ComputedMemo.trail(rev, 1, () => { runs++; return null })
    ComputedMemo.trail(rev, 1, () => { runs++; return null })
    expect(runs, '画不出（null）也是答案，下一帧不该再扫一遍').toBe(1)
    ComputedMemo.trail(rev + 1, 1, () => { runs++; return null })
    expect(runs, '换了戳就是另一条序列').toBe(2)
    ComputedMemo.profile(rev, 1, 2, () => { runs++; return null })
    ComputedMemo.profile(rev, 1, 3, () => { runs++; return null })
    ComputedMemo.profile(rev, 1, null, () => { runs++; return null })
    expect(runs, '锚点不同不能串').toBe(5)
    // 走公开入口：缓存给的和现算的一样；同一戳第二次拿到的是同一份；序列被改过之后不会拿到旧答案。
    const s = series([[10, 12, 8, 10, 100], [15, 22, 14, 18, 200], [25, 30, 24, 27, 300]])
    const before = vwapTrail(time(0), s)!
    expect(before).toEqual(computeVWAPTrail(time(0), s))
    expect(vwapTrail(time(0), s)).toBe(before)
    const vp = volumeProfile(time(0), null, s)
    expect(vp).toEqual(computeVolumeProfile(time(0), null, s))
    expect(volumeProfile(time(0), null, s)).toBe(vp)
    s.replaceLast(bar(time(2), 25, 40, 24, 36, 900))
    const after = vwapTrail(time(0), s)!
    expect(after.values).not.toEqual(before.values)
    expect(after).toEqual(computeVWAPTrail(time(0), s))
    expect(volumeProfile(time(0), null, s)).toEqual(computeVolumeProfile(time(0), null, s))
  })

  test('VWAP 只换算屏内那一段：和逐根全扫出来的线段、读数一模一样', () => {
    const bars: B5[] = []
    for (let i = 0; i < 3000; i++) {
      const c = 20 + Math.sin(i / 37) * 5
      bars.push([c - 0.3, c + 1, c - 1, c, i >= 1200 && i < 1210 ? 0 : 50 + (i % 7)])
    }
    const s = series(bars)
    const d = makeDrawing('anchoredVWAP', { t: time(5), p: 20 })
    for (const shift of [0, -900, -2380, -5800, 400, -7000]) {
      const xOf = (t: number): number => (t - t0) / step * 2 + shift
      const g = drawingGeometry(d, bounds, xOf, y, 2, s)
      const trail = computeVWAPTrail(time(5), s)!
      const want: [DrawPixel, DrawPixel][] = []
      let prev: DrawPixel | null = null
      trail.values.forEach((v, k) => {
        if (!Number.isFinite(v)) { prev = null; return }
        const p = { x: xOf(s.time(trail.start + k)), y: y(v) }
        const q = prev as DrawPixel | null
        if (q && Math.max(q.x, p.x) >= bounds.left - 2 && Math.min(q.x, p.x) <= bounds.right + 2) want.push([q, p])
        prev = p
      })
      expect(g.segments.map(sg => [sg.a, sg.b]), `shift ${shift}`).toEqual(want)
      expect(g.labels.length).toBe(1)
      expect(g.labels[0].text).toBe(trail.values[trail.values.length - 1].toFixed(2))
    }
  })

  test('分布的几何：柱子是填充，三条横线 + 边界竖线，一枚 POC 读数', () => {
    const s = fivePeaks()
    const fixed = drawingWith('fixedVolumeProfile', [{ t: time(0), p: 20 }, { t: time(6), p: 4 }])
    const g = drawingGeometry(fixed, bounds, x, y, 2, s)
    expect(g.fills.length > 0 && g.fills.length <= 2 * VolumeProfile.rows).toBe(true)
    expect(g.fills.every(f => f.points.length === 4 && f.opacity != null)).toBe(true)
    expect(g.segments.length).toBe(5)
    expect(g.segments.filter(sg => sg.dashed).length).toBe(4)
    expect(g.handles.length).toBe(2)
    expect(g.labels.length === 1 && g.labels[0].plate === 'chip').toBe(true)
    const anchored = makeDrawing('anchoredVolumeProfile', { t: time(0), p: 20 })
    const ag = drawingGeometry(anchored, bounds, x, y, 2, s)
    expect(ag.segments.length).toBe(4)
    expect(ag.handles.length).toBe(1)
  })

  test('点在柱子上就是点中了这条线', () => {
    const d = makeDrawing('anchoredVolumeProfile', { t: time(0), p: 20 })
    const g = drawingGeometry(d, bounds, x, y, 2, fivePeaks())
    const width = (f: DrawFill): number => f.points[1].x - f.points[0].x
    const widest = g.fills.reduce((m, f) => (width(f) > width(m) ? f : m))
    const cx = (widest.points[0].x + widest.points[1].x) / 2
    const cy = (widest.points[0].y + widest.points[2].y) / 2
    expect(g.nearestHandle(cx, cy)).toBeNull()
    expect(g.hit(cx, cy)).toBe('body')
  })

  test('拿不到 K 线时只剩手柄', () => {
    for (const kind of DrawKind.all) {
      if (!DrawKind.isComputed(kind)) continue
      const points = Array.from({ length: DrawKind.pointCount(kind) }, (_, i) => ({ t: time(i), p: 10 }))
      const g = drawingGeometry(drawingWith(kind, points), bounds, x, y, 2)
      expect(g.segments.length + g.fills.length + g.labels.length, kind).toBe(0)
      expect(g.handles.length).toBe(DrawKind.pointCount(kind))
    }
  })

  const digest = (g: DrawGeometry): string => {
    let out = ''
    for (const s of g.segments) out += `S ${s.a.x} ${s.a.y} ${s.b.x} ${s.b.y} ${s.tint} ${s.dashed}\n`
    for (const f of g.fills) out += `F ${f.tint} ${f.opacity} ${f.points.map(p => `${p.x},${p.y}`).join(' ')}\n`
    for (const h of g.handles) out += `H ${h.x} ${h.y}\n`
    for (const l of g.labels) out += `L ${l.point.x} ${l.point.y} ${l.text} ${l.tint} ${l.centered} ${l.plate}\n`
    return out
  }

  test('老工具对 series 完全无感', () => {
    for (const kind of DrawKind.all) {
      if (DrawKind.isComputed(kind)) continue
      const d = drawingWith(kind, Array.from({ length: DrawKind.pointCount(kind) }, (_, i) => ({ t: time(i * 2), p: 8 + i * 3 })))
      d.text = '记一笔'
      expect(digest(drawingGeometry(d, bounds, x, y, 2, three)), kind).toBe(digest(drawingGeometry(d, bounds, x, y, 2)))
    }
  })
})

// ================================================================== ChartDrawingTests（KanpanChart）
//
// 没有 jsdom：在 globalThis 上装一个最小的假 DOM（元素、画布、ResizeObserver、rAF），
// 触摸用 PointerEvent 形状的假事件从 view.el 派进去——和手机浏览器走的是同一条路：
// gesture.ts 的 pointerdown/move/up → view.drawingInput → DrawingController。
// 画布 getContext 返回 null，所以只测交互与模型，不测像素（数墨的几条见文件头）。

type Listener = (e: unknown) => void
interface FakeEl {
  style: Record<string, unknown> & { setProperty(k: string, v: string): void }
  dataset: Record<string, string>
  className: string
  children: FakeEl[]
  width: number
  height: number
  setAttribute(k: string, v: string): void
  appendChild(c: FakeEl): FakeEl
  remove(): void
  addEventListener(type: string, fn: Listener): void
  removeEventListener(type: string, fn: Listener): void
  dispatch(type: string, e: unknown): void
  setPointerCapture(id: number): void
  releasePointerCapture(id: number): void
  getBoundingClientRect(): { left: number; top: number; width: number; height: number; right: number; bottom: number; x: number; y: number }
  getContext(kind: string): null
}

function fakeEl(): FakeEl {
  const listeners = new Map<string, Set<Listener>>()
  const el: FakeEl = {
    style: Object.assign(Object.create(null) as Record<string, unknown>, { setProperty() { /* 不管样式 */ } }) as FakeEl['style'],
    dataset: {},
    className: '',
    children: [],
    width: 0,
    height: 0,
    setAttribute() { /* 无 */ },
    appendChild(c) { el.children.push(c); return c },
    remove() { /* 无 */ },
    addEventListener(type, fn) {
      if (!listeners.has(type)) listeners.set(type, new Set())
      listeners.get(type)!.add(fn)
    },
    removeEventListener(type, fn) { listeners.get(type)?.delete(fn) },
    dispatch(type, e) { for (const fn of [...(listeners.get(type) ?? [])]) fn(e) },
    setPointerCapture() { /* 无 */ },
    releasePointerCapture() { /* 无 */ },
    getBoundingClientRect: () => ({ left: 0, top: 0, width: 390, height: 700, right: 390, bottom: 700, x: 0, y: 0 }),
    getContext: () => null,
  }
  return el
}

beforeAll(() => {
  const g = globalThis as Record<string, unknown>
  if (!g.document) g.document = { createElement: () => fakeEl() }
  if (!g.window) g.window = { devicePixelRatio: 2 }
  if (!g.ResizeObserver) g.ResizeObserver = class { observe() { /* 无 */ } unobserve() { /* 无 */ } disconnect() { /* 无 */ } }
  // 帧循环永远不跑：只测模型与交互，不画
  if (!g.requestAnimationFrame) g.requestAnimationFrame = () => 1
  if (!g.cancelAnimationFrame) g.cancelAnimationFrame = () => { /* 无 */ }
})

afterEach(() => { vi.useRealTimers() })

/** 与 Swift 同一条 LCG（UInt64 回绕），800 根 1 小时 K 线从 62000 起走。 */
function drawState(count = 800): ChartState {
  let seed = 20_260_907n
  const M = 0xFFFFFFFFFFFFFFFFn
  const next = (): number => {
    seed = (seed * 6_364_136_223_846_793_005n + 1_442_695_040_888_963_407n) & M
    return Number((seed >> 33n) % 10_000n) / 10_000
  }
  const o: number[] = [], h: number[] = [], l: number[] = [], c: number[] = [], vol: number[] = []
  let p = 62_000
  for (let k = 0; k < count; k++) {
    const open = p
    const close = open * (1 + (next() - 0.5) * 0.01)
    o.push(open)
    h.push(Math.max(open, close) * (1 + next() * 0.003))
    l.push(Math.min(open, close) * (1 - next() * 0.003))
    c.push(close)
    vol.push(100 + next() * 900)
    p = close
  }
  const series = new BarSeries({
    symbol: 'BTCUSDT', interval: '1h', t0: 1_700_000_000_000, step: INTERVAL_STEP['1h'],
    open: o, high: h, low: l, close: c, volume: vol,
  })
  const span = series.step * 120
  return makeState({
    series, symbol: { symbol: 'BTCUSDT', base: 'BTC', priceDecimals: 2 },
    view: new ViewWindow(series.lastTime + span * 0.08, span), overlays: [], subs: ['MACD'],
  })
}

interface Rig { v: ChartView; c: DrawingController; axes: DrawAxes }

function makeView(magnet = false): Rig {
  const v = new ChartView(fakeEl() as unknown as HTMLElement)
  v.state = withOverlay(drawState(), { magnet })
  const c = attachDrawing(v)
  c.interactive = true
  c.magnet = magnet
  const axes = drawAxesOf(v)
  if (!axes) throw new Error('布局没建起来，后面都别测了')
  return { v, c, axes }
}

/** ChartDrawingTapDisciplineTests 的场地：磁吸留默认值（Swift 的 disciplineView 也不设）。 */
function disciplineView(): Rig {
  const v = new ChartView(fakeEl() as unknown as HTMLElement)
  v.state = drawState()
  const c = attachDrawing(v)
  c.interactive = true
  const axes = drawAxesOf(v)
  if (!axes) throw new Error('布局没建起来')
  return { v, c, axes }
}

let nextPointer = 1
interface Finger { id: number; x: number; y: number }
const finger = (q: DrawPixel): Finger => ({ id: nextPointer++, x: q.x, y: q.y })
const ev = (f: Finger, ms: number) => ({
  pointerType: 'touch', button: 0, pointerId: f.id, clientX: f.x, clientY: f.y, timeStamp: ms,
  preventDefault() { /* 无 */ },
})
const el = (v: ChartView): FakeEl => v.el as unknown as FakeEl
const down = (v: ChartView, f: Finger, ms: number): void => el(v).dispatch('pointerdown', ev(f, ms))
const move = (v: ChartView, f: Finger, q: DrawPixel, ms: number): void => { f.x = q.x; f.y = q.y; el(v).dispatch('pointermove', ev(f, ms)) }
const up = (v: ChartView, f: Finger, ms: number): void => el(v).dispatch('pointerup', ev(f, ms))
const cancel = (v: ChartView, f: Finger, ms: number): void => el(v).dispatch('pointercancel', ev(f, ms))

/** 一次轻点：按下到抬起 50ms、一动不动。 */
function tap(v: ChartView, q: DrawPixel, ms = 10_000): void {
  const f = finger(q)
  down(v, f, ms)
  up(v, f, ms + 50)
}

/** 按下、分四步挪到 b；lift 时再抬手。 */
function drag(v: ChartView, a: DrawPixel, b: DrawPixel, ms = 10_000, lift = true): Finger {
  const f = finger(a)
  let now = ms
  down(v, f, now)
  for (let k = 1; k <= 4; k++) {
    now += 16
    const r = k / 4
    move(v, f, { x: a.x + (b.x - a.x) * r, y: a.y + (b.y - a.y) * r }, now)
  }
  if (lift) up(v, f, now + 16)
  return f
}
const press = (v: ChartView, a: DrawPixel, b: DrawPixel, ms = 10_000): Finger => drag(v, a, b, ms, false)

const previewNow = (c: DrawingController): DrawingPreview | null =>
  DrawingPreview.plan(c.tool, c.anchors, c.origin?.point ?? null, c.moved, c.aim)
const at = (axes: DrawAxes, p: DrawPoint): DrawPixel => ({ x: axes.x(p.t), y: axes.y(p.p) })
const pt = (axes: DrawAxes, x: number, y: number): DrawPoint => ({ t: axes.t(x), p: axes.p(y) })
const axesNow = (v: ChartView): DrawAxes => {
  const a = drawAxesOf(v)
  if (!a) throw new Error('布局丢了')
  return a
}

describe('画线交互', () => {
  test('A7.3：水平线一点即成，工具用完自动松开', () => {
    const { v, c, axes } = makeView()
    c.setTool('hline')
    tap(v, { x: 180, y: 260 })
    expect(c.drawings.length, '一点没成线').toBe(1)
    const d = c.drawings[0]
    expect(d.kind).toBe('hline')
    expect(Math.abs(axes.y(drawingA(d).p) - 260), '水平线没落在手指那个高度上').toBeLessThan(0.5)
    expect(c.tool, '画完一条工具该松开').toBeNull()
  })

  test('A7.2：趋势线点两下成线，第一点落下后报一点', () => {
    const { v, c, axes } = makeView()
    c.setTool('trend')
    expect(c.tool === 'trend' && c.placedAnchors === 0).toBe(true)
    tap(v, { x: 120, y: 300 }, 10_000)
    expect(c.drawings, '第一点不该直接成线').toEqual([])
    expect(c.pending).not.toBeNull()
    expect(c.placedAnchors).toBe(1)
    tap(v, { x: 280, y: 200 }, 12_000)
    const d = c.drawings[0]
    expect(d.kind).toBe('trend')
    expect(Math.abs(axes.x(drawingA(d).t) - 120) < 0.5 && Math.abs(axes.y(drawingA(d).p) - 300) < 0.5).toBe(true)
    const b = drawingB(d)!
    expect(Math.abs(axes.x(b.t) - 280) < 0.5 && Math.abs(axes.y(b.p) - 200) < 0.5).toBe(true)
    expect(c.tool == null && c.pending == null).toBe(true)
  })

  test('§10.8：第一点落下后预览点跟着手指走', () => {
    const { v, c, axes } = makeView()
    c.setTool('trend')
    tap(v, { x: 120, y: 300 })
    const f = finger({ x: 200, y: 250 })
    down(v, f, 12_000)
    const first = c.aim!
    expect(Math.abs(axes.x(first.t) - 200) < 0.5 && Math.abs(axes.y(first.p) - 250) < 0.5).toBe(true)
    move(v, f, { x: 300, y: 180 }, 12_016)
    const moved = c.aim!
    expect(Math.abs(axes.x(moved.t) - 300) < 0.5 && Math.abs(axes.y(moved.p) - 180) < 0.5, '预览没跟上手指').toBe(true)
    up(v, f, 12_032)
    expect(drawingB(c.drawings[0])).toEqual(moved)
  })

  test('A7.2：磁吸开着，落点吸到那根的 OHLC', () => {
    const { v, c, axes } = makeView(true)
    const s = v.state!.input.series
    c.setTool('hline')
    const i = s.index(axes.t(200))
    const q = { x: axes.x(s.time(i)), y: axes.y(s.high[i]) + 2 }
    tap(v, q)
    const d = c.drawings[0]
    expect([s.open[i], s.high[i], s.low[i], s.close[i]], '价格没吸到开高低收里的任何一个').toContain(drawingA(d).p)
    expect(drawingA(d).t, '时间没吸到这根的开盘时刻').toBe(s.time(i))
  })

  test('磁吸关掉就停在手指上', () => {
    const { v, c, axes } = makeView(false)
    c.setTool('hline')
    tap(v, { x: 200, y: 317 })
    expect(Math.abs(axes.y(drawingA(c.drawings[0]).p) - 317)).toBeLessThan(0.001)
  })

  // ---------------------------------------------------------------- 选中

  test('A7.4：轻点线身选中，空白处轻点取消', () => {
    const { v, c, axes } = makeView()
    const line = makeDrawing('trend', pt(axes, 100, 300), pt(axes, 300, 300))
    c.setDrawings([line])
    tap(v, { x: 200, y: 294 }, 10_000)
    expect(c.selected, '8pt 内没选中').toBe(line.id)
    tap(v, { x: 200, y: 500 }, 20_000)
    expect(c.selected, '空白处轻点没取消选中').toBeNull()
  })

  test('A7.4：离线太远的轻点不选中', () => {
    const { v, c, axes } = makeView()
    c.setDrawings([makeDrawing('trend', pt(axes, 100, 300), pt(axes, 300, 300))])
    tap(v, { x: 200, y: 312 })
    expect(c.selected).toBeNull()
  })

  // ---------------------------------------------------------------- 拖

  test('A7.4：拖手柄只改那一端', () => {
    const { v, c, axes } = makeView()
    const line = makeDrawing('trend', pt(axes, 100, 320), pt(axes, 300, 280))
    c.setDrawings([line])
    c.selected = line.id
    drag(v, at(axes, drawingA(line)), { x: 140, y: 360 })
    const d = c.drawings[0]
    const now = axesNow(v)
    expect(Math.abs(now.x(drawingA(d).t) - 140) < 1 && Math.abs(now.y(drawingA(d).p) - 360) < 1, '手柄没跟着手指').toBe(true)
    expect(drawingB(d), '拖一端把另一端也带走了').toEqual(drawingB(line))
  })

  test('A7.4：拖线身整条平移，两端位移一样', () => {
    const { v, c, axes } = makeView()
    const line = makeDrawing('trend', pt(axes, 100, 320), pt(axes, 300, 300))
    c.setDrawings([line])
    c.selected = line.id
    drag(v, { x: 200, y: 310 }, { x: 240, y: 340 })
    const d = c.drawings[0]
    const now = axesNow(v)
    const b = drawingB(d)!
    expect(Math.abs(now.x(drawingA(d).t) - 140) < 1 && Math.abs(now.x(b.t) - 340) < 1, '横向不是整条一起走').toBe(true)
    expect(Math.abs(now.y(drawingA(d).p) - 350) < 1 && Math.abs(now.y(b.p) - 330) < 1, '纵向不是整条一起走').toBe(true)
  })

  test('没选中的线拖不动，那一下是拖图', () => {
    const { v, c, axes } = makeView()
    const line = makeDrawing('trend', pt(axes, 100, 320), pt(axes, 300, 320))
    c.setDrawings([line])
    const before = v.state!.viewport.view
    drag(v, { x: 200, y: 320 }, { x: 120, y: 320 }, 10_000, false)
    expect(drawingEquals(c.drawings[0], line), '没选中的线身不该被拖走').toBe(true)
    expect(v.state!.viewport.view.from, '这一下应该是在拖图').not.toBe(before.from)
  })

  test('手机：没选中的端点一划是拖图；选中之后端点有 44pt 的触摸热区', () => {
    const { v, c, axes } = makeView()
    const line = makeDrawing('trend', pt(axes, 100, 300), pt(axes, 300, 260))
    c.setDrawings([line])
    drag(v, { x: 100, y: 300 }, { x: 50, y: 300 })
    expect(drawingsEqual(c.drawings, [line]), '划过没选中的端点不该改它').toBe(true)
    c.selected = line.id
    const cur = axesNow(v)
    const start = { x: cur.x(drawingA(line).t), y: cur.y(drawingA(line).p) + 17 }
    drag(v, start, { x: start.x + 25, y: start.y + 30 }, 20_000)
    expect(drawingA(c.drawings[0])).not.toEqual(drawingA(line))
    expect(drawingB(c.drawings[0])).toEqual(drawingB(line))
  })

  test('A7.5：对数模式下拖动按像素走，两端的像素位移一致', () => {
    const { v, c } = makeView()
    v.state = withViewport(v.state!, { price: priceTransform('log') })
    const axes = axesNow(v)
    const line = makeDrawing('trend', pt(axes, 100, 200), pt(axes, 300, 420))
    c.setDrawings([line])
    c.selected = line.id
    const y0a = axes.y(drawingA(line).p), y0b = axes.y(drawingB(line)!.p)
    drag(v, { x: 200, y: 310 }, { x: 200, y: 355 })
    const d = c.drawings[0]
    const now = axesNow(v)
    expect(Math.abs(now.y(drawingA(d).p) - (y0a + 45)), '高价那端的像素位移不对').toBeLessThan(1)
    expect(Math.abs(now.y(drawingB(d)!.p) - (y0b + 45)), '低价那端的像素位移不对').toBeLessThan(1)
    expect(Math.abs((drawingA(d).p - drawingA(line).p) - (drawingB(d)!.p - drawingB(line)!.p))).toBeGreaterThan(1e-6)
  })

  test('水平线整条拖只动价格，不动时间', () => {
    const { v, c, axes } = makeView()
    const line = makeDrawing('hline', pt(axes, 150, 300))
    c.setDrawings([line])
    c.selected = line.id
    drag(v, { x: 200, y: 300 }, { x: 260, y: 350 })
    const d = c.drawings[0]
    expect(drawingA(d).t, '水平线横着拖不该改时间').toBe(drawingA(line).t)
    expect(Math.abs(axesNow(v).y(drawingA(d).p) - 350)).toBeLessThan(1)
  })

  // ---------------------------------------------------------------- 视野

  test('A7.5：拖图缩放之后线还钉在同一对 (时间, 价格) 上', () => {
    const { v, c } = makeView()
    const s0 = v.state!
    v.state = withViewport(s0, { view: s0.viewport.view.dragged(300, v.chartLayout!.plotW) })
    const axes = axesNow(v)
    const line = makeDrawing('trend', pt(axes, 120, 300), pt(axes, 320, 260))
    c.setDrawings([line])
    drag(v, { x: 200, y: 500 }, { x: 140, y: 500 }, 10_000, false)
    expect(drawingEquals(c.drawings[0], line), '拖图把线的数值改了').toBe(true)
    expect(Math.abs(axesNow(v).x(drawingA(line).t) - 60), '线没跟着视野一起走').toBeLessThan(1)
    v.state = withViewport(v.state!, { price: priceTransform('percent') })
    expect(drawingEquals(c.drawings[0], line)).toBe(true)
  })

  // Swift 这条没挂 @Test（dragDrawsWithToolArmed），行为仍是现行规矩，这里照样跑
  test('A7.8：握着工具时单指按下—拖—抬手画的是一条线，不是平移', () => {
    const { v, c, axes } = makeView()
    c.setTool('trend')
    const before = v.state!.viewport.view
    drag(v, { x: 200, y: 300 }, { x: 120, y: 260 })
    expect(v.state!.viewport.view.from, '握着工具时单指还在平移').toBe(before.from)
    const d = c.drawings[0]
    expect(d?.kind, '按住拖一笔没画出线').toBe('trend')
    expect(Math.abs(axes.x(drawingA(d).t) - 200) < 1 && Math.abs(axes.y(drawingA(d).p) - 300) < 1, '起点不在按下处').toBe(true)
    const b = drawingB(d)!
    expect(Math.abs(axes.x(b.t) - 120) < 1 && Math.abs(axes.y(b.p) - 260) < 1, '终点不在抬手处').toBe(true)
    expect(c.tool, '画完一条该自动松手').toBeNull()
  })

  test('A7.8：两指照样能捏合', () => {
    const { v, c } = makeView()
    c.setTool('hline')
    const before = v.state!.viewport.view.span
    const a = finger({ x: 120, y: 300 }), b = finger({ x: 260, y: 300 })
    down(v, a, 10_000)
    down(v, b, 10_010)
    // 网页两根手指各发一次 pointermove（Swift 是同一次 touchesMoved 带两根）
    move(v, a, { x: 60, y: 300 }, 10_026)
    move(v, b, { x: 320, y: 300 }, 10_026)
    expect(v.state!.viewport.view.span, '捏开没把窗口缩窄').toBeLessThan(before)
    expect(c.drawings).toEqual([])
  })

  // ---------------------------------------------------------------- 删除 / 完成

  test('A7.6：删除只删选中的那条；完成退出画线态但线留着', () => {
    const { v, c, axes } = makeView()
    const one = makeDrawing('hline', pt(axes, 100, 300))
    const two = makeDrawing('hline', pt(axes, 100, 400))
    c.setDrawings([one, two])
    c.selected = two.id
    c.deleteSelected()
    expect(c.drawings.map(d => d.id)).toEqual([one.id])
    expect(c.selected).toBeNull()
    c.deleteSelected()
    expect(c.drawings.length, '没选中就点删除，不该删掉别的线').toBe(1)

    c.setTool('trend')
    tap(v, { x: 150, y: 250 })
    c.endDrawing()
    expect(c.tool == null && c.pending == null && c.selected == null).toBe(true)
    expect(c.placedAnchors).toBe(0)
    expect(c.drawings.length, '「完成」把线也清掉了').toBe(1)
  })

  // ---------------------------------------------------------------- 撤销

  test('撤销重做走一圈：画两条、撤两步、重做一步', () => {
    const { v, c } = makeView()
    c.setTool('hline')
    tap(v, { x: 120, y: 260 }, 10_000)
    c.setTool('hline')
    tap(v, { x: 120, y: 360 }, 20_000)
    expect(c.drawings.length).toBe(2)
    c.undo()
    expect(c.drawings.length).toBe(1)
    c.undo()
    expect(c.drawings.length === 0 && !c.canUndo).toBe(true)
    c.undo()
    expect(c.drawings, '撤到底了还能继续退').toEqual([])
    c.redo()
    expect(c.drawings.length === 1 && c.canRedo).toBe(true)
  })

  test('删除也能撤销回来', () => {
    const { c, axes } = makeView()
    const one = makeDrawing('hline', pt(axes, 100, 300))
    c.setDrawings([one])
    c.selected = one.id
    c.deleteSelected()
    expect(c.drawings).toEqual([])
    c.undo()
    expect(drawingEquals(c.drawings[0], one)).toBe(true)
  })

  // ---------------------------------------------------------------- 上限

  test('A7.7：一个品种画满 50 条就不再往里塞', () => {
    const { v, c, axes } = makeView()
    const full = Array.from({ length: 50 }, (_, i) => makeDrawing('hline', pt(axes, 100, 200 + i)))
    c.setDrawings(full)
    let hitLimit = false
    c.onFull = () => { hitLimit = true }
    c.setTool('hline')
    tap(v, { x: 200, y: axes.pane.y + 30 })
    expect(c.drawings.length).toBe(50)
    expect(hitLimit, '满了没吭声').toBe(true)
  })

  // ---------------------------------------------------------------- 接线

  test('覆盖层接触摸时，触摸从视图转进画线层；关掉就摘下', () => {
    const { v, c } = makeView()
    expect(c.interactive).toBe(true)
    expect(v.drawingInput).not.toBeNull()
    c.setTool('hline')
    tap(v, { x: 200, y: 300 })
    expect(c.drawings.length, '触摸没转给画线层').toBe(1)
    c.interactive = false
    expect(v.drawingInput).toBeNull()
  })

  test('换一批线（切品种）把选中、半截的线和撤销栈一起清掉', () => {
    const { v, c } = makeView()
    c.setTool('trend')
    tap(v, { x: 150, y: 250 })
    expect(c.pending).not.toBeNull()
    c.setDrawings([])
    expect(c.pending == null && c.selected == null && !c.canUndo).toBe(true)
  })

  test('线变了会叫外面存盘', () => {
    const { v, c } = makeView()
    const seen: Drawing[][] = []
    c.onChanged = items => { seen.push(items) }
    c.setTool('hline')
    tap(v, { x: 200, y: 300 })
    expect(seen.length).toBe(1)
    expect(seen[seen.length - 1].length).toBe(1)
  })

  test('每把工具都能画出来、撤销、重做', () => {
    for (const tool of DrawKind.all) {
      const { v, c, axes } = makeView()
      c.setTool(tool)
      // 点几下由 placeCount 定（回归通道点两下、第三点拟合）；坐标给够 8 个
      const coords = DRAW_PART_ANCHORS.map((_, i) => ({ x: 70 + i * 34, y: axes.pane.h * (i % 2 === 0 ? 0.65 : 0.3) }))
      for (let i = 0; i < DrawKind.placeCount(tool); i++) tap(v, coords[i], 10_000 + i * 1000)
      const result = c.drawings[0]
      expect(result, `缺 ${tool}`).toBeDefined()
      expect(result.kind === tool && result.points.length === DrawKind.pointCount(tool), tool).toBe(true)
      expect(c.selected, tool).toBe(result.id)
      c.undo(); expect(c.drawings, tool).toEqual([])
      c.redo(); expect(drawingsEqual(c.drawings, [result]), tool).toBe(true)
    }
  })

  test('拖动预览不改已提交的模型；取消与原地不动都不进撤销栈', () => {
    const { v, c, axes } = makeView()
    const line = makeDrawing('trend', pt(axes, 80, 120), pt(axes, 240, 180))
    c.setDrawings([line]); c.selected = line.id
    const f = finger({ x: 80, y: 120 })
    down(v, f, 10_000)
    move(v, f, { x: 110, y: 140 }, 10_020)
    expect(drawingsEqual(v.state!.overlay.drawings, [line])).toBe(true)
    expect(c.preview != null && !drawingEquals(c.preview, line)).toBe(true)
    cancel(v, f, 10_040)
    expect(drawingsEqual(c.drawings, [line]) && !c.canUndo).toBe(true)
    expect(v.state!.overlay.drawingPreviewID).toBeNull()
    tap(v, { x: 80, y: 120 }, 20_000)
    expect(c.canUndo).toBe(false)
  })

  // ChartDrawingPreviewResidueTests.deleteMidDragDropsTheDrag（iOS 633143a1，审查 B·拖动残留）
  test('拖到一半那条线在另一张图上被删掉：拖动当场作废，抬手不写回，下一笔落笔不被当成拖那条线', () => {
    const book = new DrawingBook()
    const A = makeView(), B = makeView()
    A.c.bindDrawings(book); B.c.bindDrawings(book)
    const line = makeDrawing('trend', pt(A.axes, 80, 120), pt(A.axes, 240, 180))
    A.c.setDrawings([line]); A.c.selected = line.id
    const f = finger({ x: 80, y: 120 })
    down(A.v, f, 10_000)
    move(A.v, f, { x: 110, y: 140 }, 10_020)
    expect(A.v.state!.overlay.drawingPreviewID).toBe(line.id)
    expect(A.c.preview).not.toBeNull()

    B.c.selected = line.id
    B.c.deleteSelected()
    expect(A.c.drawings).toEqual([])
    expect(A.c.preview, '覆盖层不许再画那条线的预览和读数').toBeNull()
    expect(A.v.state!.overlay.drawingPreviewID).toBeNull()

    move(A.v, f, { x: 140, y: 160 }, 10_040)
    expect(A.c.preview).toBeNull()
    up(A.v, f, 10_060)
    expect(A.c.drawings, '抬手不许把删掉的线写回来').toEqual([])
    expect(book.items('BTCUSDT')).toEqual([])

    A.c.setTool('trend')
    drag(A.v, { x: 100, y: 250 }, { x: 220, y: 200 }, 20_000)
    expect(A.c.drawings.length).toBe(1)
    expect(A.c.drawings[0].kind).toBe('trend')
    expect(A.c.drawings[0].id).not.toBe(line.id)
  })

  test('落点中途捏合：已落的锚点原样留着', () => {
    const { v, c } = makeView()
    c.setTool('channel')
    tap(v, { x: 80, y: 120 })
    const anchors = c.anchors.map(p => ({ ...p }))
    const a = finger({ x: 130, y: 160 }), b = finger({ x: 240, y: 160 })
    down(v, a, 11_000)
    down(v, b, 11_010)
    move(v, a, { x: 90, y: 160 }, 11_030)
    move(v, b, { x: 280, y: 160 }, 11_030)
    up(v, a, 11_050)
    up(v, b, 11_050)
    expect(c.anchors).toEqual(anchors)
    expect(c.drawings).toEqual([])
    c.undo()
    expect(c.pending).toBeNull()
  })

  test('锁定、隐藏、复制、样式都能撤销', () => {
    const { v, c, axes } = makeView()
    const line = makeDrawing('hline', pt(axes, 80, 120))
    c.setDrawings([line]); c.selected = line.id
    const edited: Drawing = { ...cloneDrawing(line), locked: true, color: '#4A90E2', lineWidth: 3 }
    c.updateDrawing(edited)
    drag(v, { x: 150, y: 120 }, { x: 170, y: 150 })
    expect(drawingsEqual(c.drawings, [edited])).toBe(true)
    c.selected = line.id; c.duplicateSelected()
    expect(c.drawings.length).toBe(2)
    const last = c.drawings[c.drawings.length - 1]
    expect(last.locked === false && last.color === edited.color).toBe(true)
    c.undo(); expect(drawingsEqual(c.drawings, [edited])).toBe(true)
    c.setAllHidden(true); expect(c.drawings[0].hidden).toBe(true)
    c.undo(); expect(c.drawings[0].hidden).toBe(false)
    c.clear(); expect(c.drawings).toEqual([])
    c.undo(); expect(drawingsEqual(c.drawings, [edited])).toBe(true)
  })

  test('远处的线不扭曲纵轴；隐藏的线选不中', () => {
    const { v, c, axes } = makeView()
    const before = v.chartPriceRange
    const line = makeDrawing('hline', { t: 0, p: 1e12 })
    c.setDrawings([line])
    expect(v.chartPriceRange).toEqual(before)
    const hidden: Drawing = { ...cloneDrawing(line), points: [{ t: 0, p: axes.p(120) }], hidden: true }
    c.setDrawings([hidden])
    tap(v, { x: 150, y: 120 })
    expect(c.selected).toBeNull()
  })

  // ---------------------------------------------------------------- 拖动中的实时预览

  test('按下拖动的一路上就有线：回撤抬手前已成两点，落地与预览是同一份点', () => {
    const { v, c, axes } = makeView()
    c.setTool('fibonacci')
    const a = { x: 120, y: 420 }, b = { x: 300, y: 200 }
    const f = finger(a)
    down(v, f, 10_000)
    expect(previewNow(c)?.points.length).toBe(1)
    move(v, f, b, 10_016)
    const plan = previewNow(c)
    expect(plan, '拖动中一条预览都没有').not.toBeNull()
    expect(plan!.points.length, '抬手前还是看不到线').toBe(2)
    expect(plan!.whole, '两点够了却没走整条线那一支').toBe(true)
    expect(Math.abs(axes.x(plan!.points[0].t) - a.x) < 1 && Math.abs(axes.y(plan!.points[0].p) - a.y) < 1, '预览的起点不在按下处').toBe(true)
    expect(Math.abs(axes.x(plan!.points[1].t) - b.x) < 1 && Math.abs(axes.y(plan!.points[1].p) - b.y) < 1, '预览的终点没跟上手指').toBe(true)
    const seen = plan!.points.map(p => ({ ...p }))
    up(v, f, 10_032)
    const d = c.drawings[0]
    expect(d?.kind, '抬手没落成线').toBe('fibonacci')
    expect(d.points, '落下的线和松手前看到的那条不是同一份点').toEqual(seen)
    expect(c.origin, '临时起点没清干净').toBeNull()
  })

  test('位移不够就还是轻点：抬手前不顶临时起点', () => {
    const { v, c } = makeView()
    c.setTool('fibonacci')
    const a = { x: 120, y: 420 }
    const f = finger(a)
    down(v, f, 10_000)
    move(v, f, { x: a.x + 2, y: a.y + 1 }, 10_016)
    expect(c.moved).toBeLessThan(DRAW_DRAG_SLOP_PT)
    expect(previewNow(c)?.points.length, '还没拖够就先画了一条并不存在的线').toBe(1)
    up(v, f, 10_032)
    expect(c.drawings, '一下轻点不该直接成线').toEqual([])
    expect(c.pending, '轻点该落下第一个锚').not.toBeNull()
  })

  test('三点工具拖第一笔：抬手前是两个点，不当成整条线', () => {
    const { v, c } = makeView()
    c.setTool('channel')
    press(v, { x: 120, y: 420 }, { x: 300, y: 220 })
    const plan = previewNow(c)!
    expect(plan.points.length).toBe(2)
    expect(plan.whole, '通道要三个点，两个点不该当成整条线画').toBe(false)
  })

  test('拖到一半取消：锚点、瞄准点和临时起点一个都不留', () => {
    const { v, c } = makeView()
    c.setTool('fibonacci')
    const f = press(v, { x: 120, y: 420 }, { x: 300, y: 220 })
    expect(previewNow(c)?.points.length).toBe(2)
    cancel(v, f, 10_100)
    expect(c.drawings).toEqual([])
    expect(c.anchors.length === 0 && c.aim == null && c.origin == null).toBe(true)
    expect(previewNow(c)).toBeNull()
  })

  test('拖到一半第二根手指落下：转捏合，半截预览全清', () => {
    const { v, c } = makeView()
    c.setTool('fibonacci')
    press(v, { x: 120, y: 420 }, { x: 220, y: 300 })
    expect(previewNow(c)?.points.length).toBe(2)
    down(v, finger({ x: 320, y: 300 }), 10_120)
    expect(c.origin == null && c.aim == null, '转捏合之后还留着半截预览').toBe(true)
    expect(previewNow(c)).toBeNull()
    expect(c.drawings, '二指介入不该落下一条线').toEqual([])
  })
})

// ================================================================== DrawingBookBindingTests

describe('画线真值与投影', () => {
  test('两张图绑同一本真值：一张画的，另一张立刻看得见，撤销栈也是同一摞', () => {
    const book = new DrawingBook()
    const A = makeView(), B = makeView()
    A.c.bindDrawings(book); B.c.bindDrawings(book)
    expect(A.c.addHorizontalLine(62_000)).toBe(true)
    expect(drawingsEqual(B.c.drawings, A.c.drawings) && B.c.drawings.length === 1).toBe(true)
    expect(drawingsEqual(book.items('BTCUSDT'), A.c.drawings)).toBe(true)
    expect(B.c.canUndo, '撤销栈不在真值里').toBe(true)
    B.c.undo()
    expect(A.c.drawings.length === 0 && B.c.drawings.length === 0).toBe(true)
    expect(A.c.canRedo).toBe(true)
  })

  test('绑了真值的图不认外面灌进来的线', () => {
    const book = new DrawingBook()
    const own = drawingWith('hline', [{ t: 1_700_000_000_000, p: 62_000 }], 'own')
    book.replaceBucket([own], 'BTCUSDT')
    const { v, c } = makeView()
    c.bindDrawings(book)
    expect(drawingsEqual(c.drawings, [own])).toBe(true)
    v.state = withOverlay(v.state!, { drawings: [] })
    expect(drawingsEqual(c.drawings, [own]), '外面那份旧 state 把线抹了').toBe(true)
    expect(drawingsEqual(book.items('BTCUSDT'), [own])).toBe(true)
  })

  test('没绑宿主的图（复盘回放）照旧吃 state 里给的线，且不进撤销栈', () => {
    const { v, c } = makeView()
    const snap = drawingWith('hline', [{ t: 1_700_000_000_000, p: 61_000 }], 'snap')
    v.state = withOverlay(v.state!, { drawings: [snap] })
    expect(drawingsEqual(c.drawings, [snap])).toBe(true)
    expect(c.canUndo).toBe(false)
    v.state = withOverlay(v.state!, { drawings: [] })
    expect(c.drawings).toEqual([])
  })

  test('换品种：投影换桶，手上的工具和选中一并放下', () => {
    const book = new DrawingBook()
    const eth = drawingWith('hline', [{ t: 1_700_000_000_000, p: 3_000 }], 'eth')
    book.replaceBucket([eth], 'ETHUSDT')
    const { v, c } = makeView()
    c.bindDrawings(book)
    expect(c.addHorizontalLine(62_000)).toBe(true)
    c.setTool('trend')
    tap(v, { x: 120, y: 300 })
    expect(c.placedAnchors).toBe(1)
    const s = v.state!.input.series
    const ethSeries = new BarSeries({
      symbol: 'ETHUSDT', interval: s.interval, t0: s.t0, step: s.step,
      open: s.open, high: s.high, low: s.low, close: s.close, volume: s.volume,
    })
    v.state = withInput(v.state!, { series: ethSeries })
    expect(drawingsEqual(c.drawings, [eth])).toBe(true)
    expect(c.tool == null && c.placedAnchors === 0, '上一只品种画到一半的线跟过来了').toBe(true)
    expect(book.items('BTCUSDT').length, '换品种把上一只的线弄丢了').toBe(1)
  })

  test('整批替换这一桶：撤销栈清掉；别的桶变了不碰这只的撤销（A-07）', () => {
    const book = new DrawingBook()
    const { c } = makeView()
    c.bindDrawings(book)
    expect(c.addHorizontalLine(62_000)).toBe(true)
    const next = book.archive.clone()
    next.set('ETHUSDT', [drawingWith('hline', [{ t: 1, p: 3_000 }], 'eth')])
    book.replace(next.clone())
    expect(c.canUndo).toBe(true)
    next.set('BTCUSDT', [])
    book.replace(next.clone())
    expect(c.drawings.length === 0 && !c.canUndo).toBe(true)
  })

  test('满了不画：上限在真值里，图只报「满了」和一下「没落成」', () => {
    const book = new DrawingBook()
    const full = Array.from({ length: DrawArchive.perSymbolLimit },
      (_, i) => drawingWith('hline', [{ t: 1_700_000_000_000, p: 60_000 + i }], `l${i}`))
    book.replaceBucket(full, 'BTCUSDT')
    const { c } = makeView()
    c.bindDrawings(book)
    const events: DrawingFeedback[] = []
    let fullCalls = 0
    c.onFeedback = e => { events.push(e) }
    c.onFull = () => { fullCalls += 1 }
    expect(c.addHorizontalLine(62_000)).toBe(false)
    expect(events).toEqual(['rejected'])
    expect(fullCalls).toBe(1)
    expect(book.items('BTCUSDT').length).toBe(DrawArchive.perSymbolLimit)
    c.selected = 'l0'
    c.deleteSelected()
    expect(events[events.length - 1]).toBe('removed')
    expect(c.addHorizontalLine(62_000)).toBe(true)
    expect(events[events.length - 1]).toBe('snapped')
  })
})

// ================================================================== ChartDrawingTapDisciplineTests

describe('画线：一次点击落几条 / 什么时候才选中', () => {
  test('单锚点工具一次点击只落一条', () => {
    const kinds: DrawingKind[] = ['hline', 'vline', 'hray', 'note', 'crossLine', 'priceLabel', 'flag',
      'markerUp', 'markerDown', 'anchoredVWAP', 'anchoredVolumeProfile']
    for (const kind of kinds) {
      const { v, c } = disciplineView()
      c.setTool(kind)
      tap(v, { x: 180, y: 260 })
      expect(c.drawings.length, `${kind} 一次点击落了 ${c.drawings.length} 条`).toBe(1)
    }
  })

  test('点一条之后马上捏合：捏合不是第二条', () => {
    const { v, c } = disciplineView()
    c.continuous = true
    c.setTool('hline')
    tap(v, { x: 180, y: 260 }, 10_000)
    expect(c.drawings.length, '第一下就没画对').toBe(1)
    // Swift 两根一起进同一次 touchesBegan；网页是两次 pointerdown，同一毫秒
    const a = finger({ x: 140, y: 300 }), b = finger({ x: 240, y: 340 })
    down(v, a, 10_100)
    down(v, b, 10_100)
    up(v, a, 10_200)
    up(v, b, 10_260)
    expect(c.drawings.length, `捏合又落了一条，图上成了 ${c.drawings.length} 条`).toBe(1)
  })

  test('手指已经按在图上才拿起工具：这一下不落笔', () => {
    const { v, c } = disciplineView()
    const f = finger({ x: 180, y: 260 })
    down(v, f, 10_000)
    c.setTool('hline')
    up(v, f, 10_050)
    expect(c.drawings.length, `凭空落了 ${c.drawings.length} 条`).toBe(0)
  })

  const flat = (axes: DrawAxes): Drawing => makeDrawing('trend', pt(axes, 100, 300), pt(axes, 300, 300))

  test('不在画线态：点中一条已有的线不选中', () => {
    const { v, c, axes } = disciplineView()
    c.setDrawings([flat(axes)])
    c.editable = false
    tap(v, { x: 200, y: 294 })
    expect(c.selected, '不在画线态却把线选中了').toBeNull()
  })

  test('不在画线态：深链指过来的那条点一下能取消', () => {
    const { v, c, axes } = disciplineView()
    const line = flat(axes)
    c.setDrawings([line])
    c.editable = false
    c.selected = line.id
    tap(v, { x: 200, y: 500 })
    expect(c.selected, '高亮收不掉').toBeNull()
  })

  test('在画线态：点中还是照样选中', () => {
    const { v, c, axes } = disciplineView()
    const line = flat(axes)
    c.setDrawings([line])
    c.editable = true
    tap(v, { x: 200, y: 294 })
    expect(c.selected, '画线态下选不中了').toBe(line.id)
  })
})

// ================================================================== ChartDrawingLongPressLockTests

describe('画线：长按线锁定', () => {
  const lineView = (): Rig & { line: Drawing } => {
    vi.useFakeTimers()
    const rig = disciplineView()
    const line = makeDrawing('trend', pt(rig.axes, 100, 300), pt(rig.axes, 300, 300))
    rig.c.setDrawings([line])
    rig.c.editable = true
    return { ...rig, line }
  }

  /** 按住、（可选）挪一下、等过长按定时器（假时钟 450ms）再抬手。 */
  const hold = (v: ChartView, q: DrawPixel, ms = 10_000, moveTo?: DrawPixel): void => {
    const f = finger(q)
    down(v, f, ms)
    if (moveTo) move(v, f, moveTo, ms + 50)
    vi.advanceTimersByTime(450)
    up(v, f, ms + 3_000)
  }

  test('没选中的线：按住不动就锁上、选中它，再按一次解开，反馈分得出', () => {
    const { v, c, line } = lineView()
    const events: DrawingFeedback[] = []
    c.onFeedback = e => { events.push(e) }
    hold(v, { x: 200, y: 300 })
    expect(c.drawings[0].locked, '按住没锁上').toBe(true)
    expect(c.selected, '锁上之后要选中它').toBe(line.id)
    expect(v.state!.overlay.crosshair, '按在线上的长按归锁定，不该再出十字线').toBeNull()
    hold(v, { x: 200, y: 300 }, 20_000)
    expect(c.drawings[0].locked, '再按一次没解开').toBe(false)
    expect(events).toEqual(['locked', 'unlocked'])
    expect(c.drawings.length).toBe(1)
  })

  test('选中的线：按住不动锁上，端点不跟着手指走', () => {
    const { v, c, line } = lineView()
    c.selected = line.id
    hold(v, { x: 200, y: 300 })
    const locked = c.drawings[0]
    expect(locked.locked).toBe(true)
    expect(locked.points, '锁的那一下把线挪了').toEqual(line.points)
  })

  test('手指挪开了就不是长按：不锁', () => {
    const { v, c } = lineView()
    hold(v, { x: 200, y: 300 }, 10_000, { x: 240, y: 300 })
    vi.advanceTimersByTime(1_000)
    expect(c.drawings[0].locked).toBe(false)
  })

  test('空白处长按照旧出十字线，不碰线', () => {
    const { v, c } = lineView()
    const f = finger({ x: 200, y: 450 })
    down(v, f, 10_000)
    vi.advanceTimersByTime(450)
    expect(v.state!.overlay.crosshair, '空白处的长按不出十字线了').not.toBeNull()
    up(v, f, 10_700)
    expect(c.drawings[0].locked).toBe(false)
  })
})

describe('十字线跟手（2026-10-03）', () => {
  const plain = (): ChartView => {
    const v = new ChartView(fakeEl() as unknown as HTMLElement)
    v.state = drawState()
    return v
  }
  const center = (v: ChartView) => v.renderer!.crosshairCenter(v.width, v.height)!

  test('轻点出来的横线落在手指那个高度，不吸到收盘价', () => {
    const v = plain()
    tap(v, { x: 180, y: 120 })
    expect(Math.abs(center(v).y - 120)).toBeLessThan(0.5)
  })

  test('从交叉点旁边拎起来：十字线按手指的位移走，不往手指底下跳', () => {
    const v = plain()
    tap(v, { x: 180, y: 120 })
    const c0 = center(v)
    const f = drag(v, { x: c0.x + 12, y: c0.y + 12 }, { x: c0.x + 12, y: c0.y + 72 }, 12_000, false)
    expect(Math.abs(center(v).y - (c0.y + 60)), '横线没跟着手指走同样的距离').toBeLessThan(0.5)
    up(v, f, 12_200)
    expect(v.state!.overlay.crosshair).not.toBeNull()
  })

  test('拎着交叉点微调 5 点，松手十字线留在新位置', () => {
    const v = plain()
    tap(v, { x: 180, y: 120 })
    const c0 = center(v)
    drag(v, c0, { x: c0.x, y: c0.y - 5 }, 12_000)
    expect(v.state!.overlay.crosshair, '微调被当成轻点收掉了').not.toBeNull()
    expect(Math.abs(center(v).y - (c0.y - 5))).toBeLessThan(0.5)
  })

  test('按在横线远端竖拖挪价格线；横拖照旧拖图并收起十字线', () => {
    const v = plain()
    tap(v, { x: 180, y: 120 })
    const c0 = center(v)
    drag(v, { x: 30, y: c0.y + 6 }, { x: 30, y: c0.y - 54 }, 12_000)
    expect(Math.abs(center(v).y - (c0.y - 60))).toBeLessThan(0.5)
    const before = v.state!.viewport.view
    drag(v, { x: 30, y: c0.y - 60 }, { x: 120, y: c0.y - 60 }, 14_000)
    expect(v.state!.overlay.crosshair).toBeNull()
    expect(v.state!.viewport.view.equals(before)).toBe(false)
  })
})
