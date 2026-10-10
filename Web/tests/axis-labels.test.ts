/* UI 审查 2026-10-10 A4：价格轴标签让位（照 TV）——撞在一起的按离自己价位最近的空位推开、最新价不动、
 * 挤不下的低优先级不画、不出窗格；多图 ≥ 4 格不挂指标标签 */
import { describe, expect, it, vi } from 'vitest'
import { layoutAxisLabels, AXIS_LABEL_GAP } from '../src/chart/axisLabels'
import { axisIndicatorLabels, LAYOUTS, LAYOUT_N } from '../src/app/layouts'

vi.mock('../src/market/rest', () => ({ klines: vi.fn(async () => ({ ok: false, bars: [] })) }))
const { TVChart } = await import('../src/chart/chart')
type Any = Record<string, unknown>

const H = 20
/** 排好的标签两两不重叠（至少隔 1 px） */
function noOverlap(ys: (number | null)[]): boolean {
  const iv = ys.filter((y): y is number => y != null).map(y => [y - H / 2, y + H / 2]).sort((a, b) => a[0] - b[0])
  return iv.every((q, k) => k === 0 || q[0] >= iv[k - 1][1] + AXIS_LABEL_GAP - 1e-9)
}

describe('layoutAxisLabels', () => {
  it('不重叠的原样放在自己的价位上', () => {
    expect(layoutAxisLabels([{ y: 100, h: H, priority: 4 }, { y: 200, h: H, priority: 1 }], 0, 500)).toEqual([100, 200])
  })
  it('两枚重叠：最新价不动，均线标签往离自己近的那一侧推开，刚好不重叠 + 1 px', () => {
    // 最新价 100，均线 108（在下方 8 px）→ 推到最新价下沿 + 1 px：中心 100 + 20 + 1 = 121
    const ys = layoutAxisLabels([{ y: 100, h: H, priority: 4 }, { y: 108, h: H, priority: 1 }], 0, 500)
    expect(ys[0]).toBe(100)
    expect(ys[1]).toBe(100 + H + AXIS_LABEL_GAP)
    // 在上方的往上推
    const up = layoutAxisLabels([{ y: 100, h: H, priority: 4 }, { y: 95, h: H, priority: 1 }], 0, 500)
    expect(up).toEqual([100, 100 - H - AXIS_LABEL_GAP])
    expect(noOverlap(up)).toBe(true)
  })
  it('最新价传在后面也不挪（优先级决定谁先占位，不看顺序）', () => {
    const ys = layoutAxisLabels([{ y: 108, h: H, priority: 1 }, { y: 100, h: H, priority: 4 }], 0, 500)
    expect(ys[1]).toBe(100)
    expect(ys[0]).toBe(121)
  })
  it('三枚挤在一处：放不下（推开超过 1.5 枚高）的优先级低的被丢，最新价完整', () => {
    // 窗格上沿 90：最新价 100 占 [90,110]；均线 A 100 → 上面没地方，推到 121（推 21 ≤ 30）；
    // 前收盘 B 100（优先级更低）→ 只能到 142，推 42 > 30，丢
    const ys = layoutAxisLabels([
      { y: 100, h: H, priority: 1 },
      { y: 100, h: H, priority: 0 },
      { y: 100, h: H, priority: 4 },
    ], 90, 500)
    expect(ys[2]).toBe(100)
    expect(ys[0]).toBe(100 + H + AXIS_LABEL_GAP)
    expect(ys[1]).toBeNull()
    expect(noOverlap(ys)).toBe(true)
  })
  it('同优先级挤在一起时先传的先占位，后面的往空位推；推不开的丢掉', () => {
    const ys = layoutAxisLabels([
      { y: 300, h: H, priority: 1 }, { y: 302, h: H, priority: 1 }, { y: 298, h: H, priority: 1 }, { y: 301, h: H, priority: 1 },
    ], 0, 500)
    expect(ys[0]).toBe(300)
    expect(ys[1]).toBe(321) // 下方近
    expect(ys[2]).toBe(279) // 上方近
    expect(ys[3]).toBeNull() // 上下都要推 40+，丢
    expect(noOverlap(ys)).toBe(true)
  })
  it('靠近轴顶：不出界，往下让', () => {
    const ys = layoutAxisLabels([{ y: 5, h: H, priority: 4 }, { y: 6, h: H, priority: 1 }], 0, 500)
    expect(ys[0]).toBe(H / 2) // 最新价贴着上沿（夹住，不算推）
    expect(ys[1]).toBe(H / 2 + H + AXIS_LABEL_GAP)
    for (const y of ys) expect((y as number) - H / 2).toBeGreaterThanOrEqual(0)
  })
  it('靠近轴底：不出界，往上让；价位在窗格外的最新价贴在下沿', () => {
    const ys = layoutAxisLabels([{ y: 520, h: H, priority: 4 }, { y: 495, h: H, priority: 1 }], 0, 500)
    expect(ys[0]).toBe(500 - H / 2)
    expect(ys[1]).toBe(500 - H - AXIS_LABEL_GAP - H / 2)
    for (const y of ys) expect((y as number) + H / 2).toBeLessThanOrEqual(500)
  })
  it('窗格太矮放不下第二枚：丢掉，不出界', () => {
    const ys = layoutAxisLabels([{ y: 15, h: H, priority: 4 }, { y: 15, h: H, priority: 1 }], 0, 30)
    expect(ys[0]).toBe(15)
    expect(ys[1]).toBeNull()
  })
  it('一列很多枚：排完两两不重叠、都在窗格里', () => {
    const labels = Array.from({ length: 12 }, (_, k) => ({ y: 200 + k * 7, h: H, priority: k === 5 ? 4 : 1 }))
    const ys = layoutAxisLabels(labels, 0, 400)
    expect(ys[5]).toBe(235)
    expect(noOverlap(ys)).toBe(true)
    for (const y of ys) if (y != null) { expect(y - H / 2).toBeGreaterThanOrEqual(0); expect(y + H / 2).toBeLessThanOrEqual(400) }
    // 留下的每枚离自己价位不超过 1.5 枚高
    ys.forEach((y, k) => { if (y != null) expect(Math.abs(y - labels[k].y)).toBeLessThanOrEqual(1.5 * H + 1e-9) })
  })
})

describe('多图格数与指标轴标签', () => {
  it('< 4 格挂指标标签，≥ 4 格不挂', () => {
    const on = Object.fromEntries(LAYOUTS.map(l => [l, axisIndicatorLabels(LAYOUT_N[l])]))
    expect(on).toEqual({ '1': true, '2': true, '2v': true, '3': true, '4': false, '6': false, '8': false, '9': false, '12': false, '16': false })
  })
})

describe('图上画的轴标签', () => {
  /** 只带画轴标签用到的字段的假图：主图 0–400，最新价 100（y 由 priceToY 直接给 = 价） */
  function fakeChart(): InstanceType<typeof TVChart> & Any {
    const noop = (): void => {}
    const ctx = { fillStyle: '', textAlign: '', font: '', fill: noop, fillText: noop, beginPath: noop, moveTo: noop, arcTo: noop, closePath: noop }
    const ma = Array.from({ length: 5 }, () => 108)
    return Object.assign(Object.create(TVChart.prototype), {
      ctx, aw: 70, w: 600, h: 400, font: '13px sans-serif', meta: { dec: 1, title: 'BTCUSDT' },
      bars: Array.from({ length: 5 }, (_, k) => ({ t: k * 36e5, o: 100, h: 101, l: 99, c: 100, v: 1 })),
      ind: { ma: true, subs: [] }, hidden: new Set<string>(), alerts: [], drag: null, compare: null, axisHoverY: null,
      _series: { ma: [ma] }, calcStale: false, axisInd: true, axisTagsDrawn: [], dirty: false,
      colors: { text2: '#888', text3: '#aaa', alert: '#f80', up: '#0a0', down: '#a00' },
      settings: undefined,
      priceToY: (v: number) => v, plotW: () => 530, lastColor: () => '#0a0', mainAxisText: (v: number) => v.toFixed(1),
      compareBase: () => null, compareViews: () => [],
    } as Any) as InstanceType<typeof TVChart> & Any
  }
  const pane = { id: 'main', y: 0, h: 400 }
  it('单图：均线标签被最新价推开、最新价在原位且最后画（压在最上面）', () => {
    const ch = fakeChart()
    ch.drawPriceLabels(pane as never, { lo: 0, hi: 400 } as never)
    const d = ch.axisTagsDrawn as { text: string; y: number; pri: number }[]
    expect(d.length).toBeGreaterThanOrEqual(2)
    const last = d[d.length - 1]
    expect(last.text).toBe('100.0')
    expect(last.y).toBe(100)
    const ma = d.find(t => t.text === '108.0')
    expect(ma?.y).toBe(121)
  })
  it('setAxisLabels({ indicators: false })：只剩最新价，图标脏了要重画；同值再设不弄脏', () => {
    const ch = fakeChart()
    ch.setAxisLabels({ indicators: false })
    expect(ch.dirty).toBe(true)
    expect(ch.axisIndicatorLabels).toBe(false)
    ch.drawPriceLabels(pane as never, { lo: 0, hi: 400 } as never)
    expect((ch.axisTagsDrawn as { text: string }[]).map(t => t.text)).toEqual(['100.0'])
    ch.dirty = false
    ch.setAxisLabels({ indicators: false })
    expect(ch.dirty).toBe(false)
  })
})
