/* 电脑网页画线工具补全（2026-10-08）：契约里 41 种逐种验
 *   · 同步：编码 → 解码原样回来；网页写的手机（iOS 同一套编码）解得开、手机写的网页解得开（文字、刻度、填色都带上）
 *   · 几何：新加的 31 种走手机那套 drawingGeometry，画得出东西、手柄数对、点在线上 / 字块里 / 填色面里能选中
 *   · 分组：九组照 TradingView，每种工具只在一组、名字取三端同一份 DrawKind.title */
import { describe, expect, it } from 'vitest'
import type { Drawing, DrawingType, Pane, PriceRange, TVChart } from '../src/chart/chart'
import { offPlot } from '../src/chart/chart'
import {
  ANCHOR_COUNT, CONTRACT_KIND, DRAWING_TYPES, TOOL_GROUPS, bbox, familyOf, fitRegression, groupOf, placeCount, toolName, usesFill, usesLevels, usesText,
} from '../src/chart/drawTools'
import { GEOM, geomHandles, geomOf, hitGeom, toM } from '../src/chart/drawGeom'
import { decodeDrawings, encodeDrawings } from '../src/sync/codec'
import { decodeDrawingObject, encodeDrawingObject } from '../src/m/app/drawCodec'
import { DrawKind, drawingWith, type DrawingKind } from '../src/m/chart/draw/drawing'
import contract from '../../Backend/kanpan-api/contract/drawing-fields.json'

const T0 = 1_700_000_000_000, STEP = 60_000
const t = (i: number) => T0 + i * STEP
/** 每种工具一组合理的锚点：时间每隔 12 根，价格锯齿上行 */
const ptsFor = (type: DrawingType) => Array.from({ length: ANCHOR_COUNT[type] }, (_, i) => ({ t: t(40 + i * 12), p: 100 + (i % 2 ? 22 : 0) + i * 4 }))
const ALL = [...DRAWING_TYPES].filter(x => x !== 'measure') // 「测量」是 ⇧ 拖的临时尺子，不存不同步

/** 够几何用的一张假图：200 根，每根 8 px，价 50–200 映射到 0–600 px */
function fakeChart(): { ch: TVChart; p: Pane; r: PriceRange } {
  const bars = Array.from({ length: 200 }, (_, i) => ({ t: t(i), o: 100 + i * 0.1, h: 102 + i * 0.1 + (i % 7), l: 98 + i * 0.1 - (i % 5), c: 100 + i * 0.1 + Math.sin(i), v: 10 }))
  const p: Pane = { id: 'main', y: 0, h: 600 }, r: PriceRange = { min: 50, max: 200 }
  const ctx = { font: '', measureText: (s: string) => ({ width: s.length * 6 }) }
  const ch = {
    bars, iv: STEP, spacing: 8, meta: { dec: 2 }, font: '12px sans-serif', ctx, textRects: [],
    colors: { bg: '#ffffff', up: '#089981', down: '#F23645', alert: '#FF9800' },
    plotW: () => 1600, lastIndex: () => bars.length - 1,
    indexAt: (x: number) => (x - T0) / STEP, indexToX: (i: number) => i * 8, timeAt: (i: number) => t(i),
    priceToY: (v: number, pp: Pane, rr: PriceRange) => pp.y + (rr.max - v) / (rr.max - rr.min) * pp.h,
  } as unknown as TVChart
  return { ch, p, r }
}

describe('41 种：清单与契约', () => {
  it('网页认的种类 = 契约 anchorCounts（外加本机临时测量），锚点数一一相等', () => {
    const counts = (contract as { anchorCounts: Record<string, number> }).anchorCounts
    expect(Object.keys(counts).length).toBe(41)
    expect(ALL.length).toBe(41)
    for (const type of ALL) {
      const kind = CONTRACT_KIND[type]!
      expect(kind, type).toBeTruthy()
      expect(ANCHOR_COUNT[type], type).toBe(counts[kind])
    }
    expect(new Set(ALL.map(x => CONTRACT_KIND[x])).size).toBe(41)
  })

  it('九组照 TradingView 排，每种只在一组，组外只剩临时测量', () => {
    expect(TOOL_GROUPS.map(g => g.name)).toEqual(['线', '通道', '叉子与江恩', '斐波那契', '形态', '预测与测量', '形状', '注释', '成交量'])
    const seen = TOOL_GROUPS.flatMap(g => g.tools.map(x => x[0]))
    expect(new Set(seen).size).toBe(seen.length)
    expect([...seen].sort()).toEqual([...ALL].sort())
    for (const type of ALL) expect(familyOf(type)).toBe(groupOf(type)!.id)
    expect(familyOf('measure')).toBe('forecast')
  })

  it('名字取三端同一份 DrawKind.title（射线一族用手机样式表里的叫法）', () => {
    for (const type of ALL) {
      const name = toolName(type)
      expect(name, type).toMatch(/^[一-龥A-Z·（）\s]+$/)
      if (!['ray', 'hray', 'extended'].includes(type)) expect(name).toBe(DrawKind.title(CONTRACT_KIND[type]!))
    }
  })

  it('点几下：持仓 / 回归 / 测量两下，其余照锚点数', () => {
    for (const type of ALL) {
      const want = type === 'position' || type === 'regression' ? 2 : ANCHOR_COUNT[type]
      expect(placeCount(type), type).toBe(want)
    }
  })
})

describe('41 种：同步往返与三端互通', () => {
  const sample = (type: DrawingType): Drawing => {
    const d: Drawing = { id: 'k' + type, type, pts: ptsFor(type), color: '#F23645', width: 2 }
    if (usesText(type)) d.text = '关键位 ' + type
    if (usesLevels(type)) d.levels = [0, 0.5, 1, 1.618]
    if (usesFill(type)) d.filled = false
    return d
  }

  it('网页编码 → 网页解码：一个字不差', () => {
    for (const type of ALL) {
      const d = sample(type)
      const objs = encodeDrawings({ BTCUSDT: [d] }, [])
      expect(objs.length, type).toBe(1)
      expect(decodeDrawings(objs, {}).BTCUSDT, type).toEqual([d])
    }
  })

  it('网页写的，手机（iOS 编码）解得开：种类、锚点、文字、刻度、填色都对', () => {
    for (const type of ALL) {
      const d = sample(type)
      const [o] = encodeDrawings({ BTCUSDT: [d] }, [])
      const m = decodeDrawingObject(o)
      expect(m, type).not.toBeNull()
      expect(m!.d.kind).toBe(CONTRACT_KIND[type])
      expect(m!.d.points).toEqual(d.pts)
      expect(m!.d.filled).toBe(d.filled !== false)
      if (usesText(type)) expect(m!.d.text).toBe(d.text)
      if (usesLevels(type)) expect(m!.d.levels).toEqual(d.levels)
    }
  })

  it('手机写的，网页解得开（同一份锚点；带字的、自定义刻度的、不填色的都带过来）', () => {
    for (const type of ALL) {
      const kind = CONTRACT_KIND[type] as DrawingKind
      const m = drawingWith(kind, ptsFor(type), 'P' + type)
      if (DrawKind.usesText(kind)) m.text = '手机写的'
      if (DrawKind.usesLevels(kind)) m.levels = [0, 0.382, 1]
      if (DrawKind.usesFill(kind)) m.filled = false
      const o = encodeDrawingObject('binance/usd_m/ETHUSDT', m)
      const back = decodeDrawings([o], {}).ETHUSDT
      expect(back?.length, type).toBe(1)
      const d = back[0]
      expect(d.type).toBe(type)
      expect(d.pts).toEqual(m.points)
      if (DrawKind.usesText(kind)) expect(d.text).toBe('手机写的')
      if (DrawKind.usesLevels(kind)) expect(d.levels).toEqual([0, 0.382, 1])
      if (DrawKind.usesFill(kind)) expect(d.filled).toBe(false)
      // 网页没改：原样推回去，手机的字段一个不丢
      const [same] = encodeDrawings({ ETHUSDT: [d] }, [o])
      expect(same.body).toEqual(o.body)
    }
  })
})

describe('新加 31 种：几何、手柄、命中', () => {
  const geoTypes = ALL.filter(x => GEOM.has(x))
  it('走手机几何的正好是新加的 31 种（成交量分布一族走网页自己的统计）', () => {
    expect(geoTypes.length).toBe(31)
    for (const x of ['trend', 'ray', 'hline', 'vline', 'rect', 'fib', 'avwap', 'fvp', 'position', 'anchoredVolumeProfile'] as DrawingType[]) expect(GEOM.has(x)).toBe(false)
  })

  for (const type of geoTypes) {
    it(type, () => {
      const { ch, p, r } = fakeChart()
      let pts = ptsFor(type)
      if (type === 'regression') pts = fitRegression(ch.bars, pts[0], pts[1])!
      const d: Drawing = { id: 'g', type, pts, color: '#2962FF', width: 2 }
      if (usesText(type)) d.text = '写一句'
      const b = geomOf(ch, d, p, r)!
      expect(b).not.toBeNull()
      const g = b.g
      expect(g.segments.length + g.fills.length + b.placed.length, 'draws something').toBeGreaterThan(0)
      // 手柄：每个锚点一个（水平射线一族没有专门的手柄时退回锚点）
      expect(geomHandles(ch, d, p, r).length).toBe(ANCHOR_COUNT[type])
      // 点在墨迹上能选中：第一段线的中点 / 第一个字块中心 / 第一块面的重心
      const s = g.segments.find(q => Math.abs(q.a.x - q.b.x) + Math.abs(q.a.y - q.b.y) > 4)
      const probe = s ? { x: (s.a.x + s.b.x) / 2, y: (s.a.y + s.b.y) / 2 }
        : b.placed.length ? b.placed[0].center
        : { x: g.fills[0].points.reduce((a, q) => a + q.x, 0) / g.fills[0].points.length, y: g.fills[0].points.reduce((a, q) => a + q.y, 0) / g.fills[0].points.length }
      expect(hitGeom(ch, d, probe.x, probe.y, p, r), 'hit on ink').toBeLessThan(6)
      // 缓存：坐标没变 → 同一份结果；改了锚点 → 重算
      expect(geomOf(ch, d, p, r)).toBe(b)
      d.pts = d.pts.map(q => ({ ...q, p: q.p + 1 }))
      expect(geomOf(ch, d, p, r)).not.toBe(b)
      // 快捷条贴的包围框落在窗格里
      const box = bbox(ch, d, p, r)!
      expect(box.x1).toBeGreaterThanOrEqual(box.x0)
      expect(box.y1).toBeGreaterThanOrEqual(box.y0)
    })
  }

  it('离线条远的地方不选中（有界的几种）', () => {
    const { ch, p, r } = fakeChart()
    for (const type of ['triangle', 'ellipse', 'gannBox', 'xabcd', 'abcd', 'ptMeasure', 'datePriceRange', 'curve', 'markerUp', 'note'] as DrawingType[]) {
      const d: Drawing = { id: 'f', type, pts: ptsFor(type), color: '#2962FF', width: 2, text: usesText(type) ? '字' : undefined }
      expect(hitGeom(ch, d, 1500, 590, p, r), type).toBeGreaterThan(6)
    }
  })

  it('画到一半（点没点齐）的形态不写字、只出点过的手柄', () => {
    const { ch, p, r } = fakeChart()
    const d: Drawing = { id: 'h', type: 'xabcd', pts: ptsFor('xabcd').slice(0, 3), color: '#2962FF', width: 2 }
    expect(toM(d)!.padded).toBe(true)
    const b = geomOf(ch, d, p, r)!
    expect(b.placed.length).toBe(0)
    expect(b.g.handles.length).toBe(3)
  })

  it('不在屏上的不画：无界的（射线、扇、时间区）永远画，竖的只看横向', () => {
    const pane: Pane = { id: 'main', y: 0, h: 600 }
    const far = [{ x: -5000, y: -5000 }, { x: -4000, y: -4800 }]
    for (const x of ['ray', 'hray', 'extended', 'fibFan', 'gannFan', 'fibTimeZone', 'pitchfork', 'regression']) expect(offPlot(x, far, pane, 1600), x).toBe(false)
    for (const x of ['triangle', 'ellipse', 'note', 'xabcd']) expect(offPlot(x, far, pane, 1600), x).toBe(true)
    expect(offPlot('vline', [{ x: 300, y: -9000 }], pane, 1600)).toBe(false)
  })
})
