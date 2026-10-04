// 深度审查 Web A 线（2026-10-05）：PC 图表引擎的回归用例。node 下没有 DOM——拿 Object.create(TVChart.prototype) 造一张
// 只带用到字段的图，直接调引擎的方法；画布用一个只记账的假 ctx
import { afterEach, describe, expect, it, vi } from 'vitest'

const kl = { ok: false }
vi.mock('../src/market/rest', () => ({
  klines: vi.fn(async () => (kl.ok ? { ok: true, bars: [] } : { ok: false, bars: [] })),
}))

const { TVChart, wheelPx } = await import('../src/chart/chart')
const { vwap, vwapAnchor } = await import('../src/chart/indicators')
const { vpvr } = await import('../src/chart/overlays')
const { anchoredVwap, avwapStart } = await import('../src/chart/drawTools')
const { flowOf, detachFlows, resetFlows } = await import('../src/chart/tradeFlow')
const { keyLevelsOf, keyLevelsWaiting, resetKeyLevels } = await import('../src/chart/keyLevels')
const { fmtAxis } = await import('../src/util/format')
const { BarSeries } = await import('../src/m/chart/series')
const { VWAPState } = await import('../src/m/indicator/engine')
type Bar = import('../src/chart/calc').Bar
type Chart = InstanceType<typeof TVChart>
type Any = Record<string, unknown>

const DAY = 864e5, H = 36e5
const P = TVChart.prototype as unknown as Record<string, (...a: unknown[]) => unknown>
function fake(fields: Any): Chart & Any { return Object.assign(Object.create(TVChart.prototype), fields) }
function bars(n: number, t0 = 1_700_006_400_000, iv = H, f: (k: number) => Partial<Bar> = () => ({})): Bar[] {
  return Array.from({ length: n }, (_, k) => ({ t: t0 + k * iv, o: 100 + k, h: 102 + k, l: 98 + k, c: 101 + k, v: 1000, ...f(k) }))
}
/** 只记账的画布上下文：方法调用逐条记下来，measureText 给个固定宽 */
function recCtx() {
  const calls: [string, unknown[]][] = []
  const ctx = new Proxy({} as Any, {
    get(o, k: string) {
      if (k in o) return o[k]
      if (k === 'measureText') return () => ({ width: 40 })
      return (...a: unknown[]) => { calls.push([k, a]) }
    },
    set(o, k: string, v) { o[k] = v; return true },
  })
  return { ctx, calls }
}
const COLORS = { cross: '#999', crossLabel: '#333', up: '#0a0', down: '#a00', text3: '#888', bg: '#fff' }

describe('十字线横线跟手、不吸开高低收（磁吸只管画线落点）', () => {
  it('磁吸开着：横线与价格标签都在鼠标那一行，标签的价 = crossPrice', () => {
    const { ctx, calls } = recCtx()
    const pane = { id: 'main', y: 0, h: 400 }, r = { min: 90, max: 110 }
    const ch = fake({ ctx, colors: COLORS, w: 600, aw: 60, h: 428, rightBar: 9, spacing: 20, bars: bars(10, 0, H, () => ({ o: 100, h: 109, l: 91, c: 100 })),
      iv: H, log: false, magnet: true, metaHeld: false, cross: { x: 500, y: 123.4, pane: 'main' }, extCross: null, font: '12px x', meta: { dec: 2 },
      _ranges: { main: r }, _panes: [pane] })
    ;(ch as unknown as { drawCrosshair(p: unknown[]): void }).drawCrosshair([pane])
    const horiz = calls.filter(([k, a]) => k === 'moveTo' && a[0] === 0)
    expect(horiz.map(([, a]) => a[1])).toEqual([123.5])
    const label = calls.find(([k, a]) => k === 'fillText' && a[2] === 123.4)
    expect(label?.[1][0]).toBe(fmtAxis(ch.crossPrice() as number, 2))
  })
})

describe('手势中途数据换了：起拖记的东西作废', () => {
  const drawing = () => ({ id: 'a', type: 'trend', pts: [{ t: 0, p: 100 }, { t: H, p: 110 }] })
  function dragging(d: Any, extra: Any = {}) {
    const onDrawDrag = vi.fn(), copied = [d]
    const ch = fake({ meta: { symbol: 'AUSDT' }, iv: H, bars: bars(20), rightBar: 25, manual: null, auto: true, dirty: false,
      o: { onDrawDrag, onAutoChange: () => {} }, drawings: copied, selected: null, measure: null, draft: { type: 'trend' }, sepHs: null, pendingMenu: null,
      drag: { kind: 'drawing', hit: { d, handle: null }, orig: d.pts as unknown[], copied, moved: true, start: { t: 0, p: 100 } }, renderLegend: () => {}, ...extra })
    ;(d as { pts: unknown }).pts = [{ t: 5 * H, p: 140 }, { t: 6 * H, p: 150 }]
    return { ch, onDrawDrag, copied }
  }
  it('拖着画线换品种：线放回原处、⌘ 复制出来的那条撤掉、通知页面拖完了', () => {
    const d = drawing(), orig = d.pts.map(q => ({ ...q }))
    const { ch, onDrawDrag, copied } = dragging(d)
    ch.setData(bars(30), { symbol: 'BUSDT', iv: H } as never)
    expect(ch.drag).toBeNull(); expect((ch as Any).draft).toBeNull()
    expect(d.pts).toEqual(orig)
    expect(copied).not.toContain(d)
    expect(onDrawDrag).toHaveBeenCalledWith(false)
  })
  it('撤销 / 同步换了一份画线：同上；同一份数组再设不打断', () => {
    const d = drawing(), orig = d.pts.map(q => ({ ...q }))
    const { ch } = dragging(d)
    ch.setDrawings(ch.drawings)
    expect(ch.drag).not.toBeNull()
    ch.setDrawings([])
    expect(ch.drag).toBeNull(); expect(d.pts).toEqual(orig)
  })
  it('拖着平移时左边翻页补进历史：起拖记的右缘下标一起挪，视口不跳', () => {
    const ch = fake({ bars: bars(20, 100 * H), rightBar: 25, replay: null, dirty: false, drag: { kind: 'pan', x0: 0, right0: 25 } })
    ch.prependData(bars(7, 93 * H))
    expect(ch.rightBar).toBe(32)
    expect((ch.drag as unknown as { right0: number }).right0).toBe(32)
  })
  it('换画线不收平移；换品种收平移', () => {
    const ch = fake({ meta: { symbol: 'AUSDT' }, iv: H, bars: bars(20), rightBar: 25, manual: null, auto: true, o: {}, drawings: [], draft: null,
      sepHs: [1], pendingMenu: null, drag: { kind: 'pan', x0: 0, right0: 25 }, renderLegend: () => {} })
    ch.setDrawings([])
    expect(ch.drag).not.toBeNull()
    ch.setData(bars(20), { symbol: 'BUSDT', iv: H } as never)
    expect(ch.drag).toBeNull(); expect((ch as Any).sepHs).toBeNull()
  })
})

describe('价格轴', () => {
  it('对数轴：布林下轨 / VWAP −2σ 穿到 0 以下也不把整条轴变 NaN', () => {
    const b = bars(10)
    const ch = fake({ manual: null, log: true, bars: b, hidden: new Set(), calcStale: false, _series: { boll: [b.map(() => 100), b.map(() => 120), b.map(() => -5)] } })
    const r = ch.rangeMain(0, 9)
    expect(Number.isFinite(r.min) && Number.isFinite(r.max) && r.min > 0 && r.max > r.min).toBe(true)
  })
  it('一字线、负价：上下沿不颠倒', () => {
    const ch = fake({ manual: null, log: false, bars: bars(5, 0, H, () => ({ o: -2, h: -2, l: -2, c: -2 })), hidden: new Set(), calcStale: false, _series: {} })
    const r = ch.rangeMain(0, 4)
    expect(r.min).toBeLessThan(-2); expect(r.max).toBeGreaterThan(-2)
  })
  it('副图混进 Infinity：不把区间撑成 Infinity', () => {
    const ch = fake({ calcStale: false, _series: { oi: [[5, Infinity, 7, NaN, 6]] } })
    const r = ch.rangeSub('oi' as never, 0, 4)
    expect(r.min).toBeLessThan(5); expect(r.max).toBeGreaterThan(7); expect(Number.isFinite(r.max)).toBe(true)
  })
  it('刻度：区间小到浮点分辨率以下也会停、不出重复价；不细过品种精度', () => {
    const ch = fake({ log: false, meta: { dec: 1 } })
    const t0 = performance.now()
    const a = ch.priceTicks({ id: 'oi', y: 0, h: 400 } as never, { min: 1e9, max: 1e9 + 1e-6 })
    expect(performance.now() - t0).toBeLessThan(50)
    expect(a.length).toBeLessThanOrEqual(64)
    const b = ch.priceTicks({ id: 'main', y: 0, h: 800 } as never, { min: 60000, max: 60000.6 })
    expect(new Set(b).size).toBe(b.length)
    for (const v of b) expect(Math.abs(v * 10 - Math.round(v * 10))).toBeLessThan(1e-6)
  })
  it('手动缩放夹在合理跨度里：一路缩不缩到浮点分辨率以下，一路放不溢出', () => {
    const ch = fake({ log: false, manual: null })
    expect(ch.scaleManual(100, 101, 100.5, 1e-12)).toBe(true)
    const m = ch.manual as unknown as { min: number; max: number }
    expect(m.max - m.min).toBeGreaterThanOrEqual(100.5 * 1e-6 * 0.999)
    ch.scaleManual(100, 101, 100.5, 1e300)
    const m2 = ch.manual as unknown as { min: number; max: number }
    expect(Number.isFinite(m2.min) && Number.isFinite(m2.max)).toBe(true)
    expect(ch.scaleManual(100, 100, 100, 2)).toBe(false)
  })
})

describe('成交量 / 成交量分布：一根坏量不毁整屏', () => {
  it('量柱：一根 Infinity 不画也不当顶，别的柱照常有高度', () => {
    const { ctx, calls } = recCtx()
    const b = bars(5, 0, H, k => ({ v: k === 2 ? Infinity : 100 }))
    const ch = fake({ ctx, colors: COLORS, bars: b, spacing: 10, rightBar: 5, w: 200, aw: 0 })
    ch.drawVolume({ id: 'main', y: 0, h: 400 } as never, 0, 4)
    const rects = calls.filter(([k]) => k === 'rect')
    expect(rects.length).toBe(4)
    for (const [, a] of rects) expect(a[3] as number).toBeGreaterThan(10)
  })
  it('VPVR：坏量跳过、总量有限', () => {
    const b = bars(10, 0, H, k => ({ v: k === 3 ? Infinity : k === 4 ? NaN : 100 }))
    const v = vpvr(b, 0, 9, 20)!
    expect(Number.isFinite(v.total)).toBe(true); expect(v.total).toBeCloseTo(800)
  })
})

describe('成交均价（VWAP）与 iOS / 手机网页同口径', () => {
  it('锚点表：日内按 UTC 日、日线按自然月、周线按自然年、年线不归零', () => {
    const t = Date.UTC(2026, 4, 31, 23, 0), t2 = Date.UTC(2026, 5, 1, 1, 0)
    expect(vwapAnchor(t, H)).not.toBe(vwapAnchor(t2, H))
    expect(vwapAnchor(Date.UTC(2026, 4, 1), DAY)).toBe(vwapAnchor(Date.UTC(2026, 4, 31), DAY))
    expect(vwapAnchor(Date.UTC(2026, 4, 31), DAY)).not.toBe(vwapAnchor(Date.UTC(2026, 5, 1), DAY))
    expect(vwapAnchor(Date.UTC(2026, 0, 5), 7 * DAY)).toBe(vwapAnchor(Date.UTC(2026, 11, 28), 7 * DAY))
    expect(vwapAnchor(Date.UTC(2025, 11, 29), 7 * DAY)).not.toBe(vwapAnchor(Date.UTC(2026, 0, 5), 7 * DAY))
    expect(vwapAnchor(Date.UTC(2020, 0, 1), 400 * DAY)).toBe(vwapAnchor(Date.UTC(2026, 0, 1), 400 * DAY))
  })
  it('坏量那一根留白、累计往下传；整段零成交退回典型价', () => {
    const b = bars(6, Date.UTC(2026, 0, 1), H, k => (k === 2 ? { bv: Infinity, v: Infinity } : { bv: k === 3 ? -1 : 10 }))
    const [mid] = vwap(b, H)
    expect(mid[2]).toBeNull(); expect(mid[3]).toBeNull()
    expect(Number.isFinite(mid[5] as number)).toBe(true)
    const z = bars(3, Date.UTC(2026, 0, 1), H, () => ({ bv: 0 }))
    expect(vwap(z, H)[0]).toEqual(z.map(x => (x.h + x.l + x.c) / 3))
  })
  for (const [iv, step, n, t0] of [['1m', 6e4, 3000, Date.UTC(2026, 2, 3)], ['1h', H, 800, Date.UTC(2026, 2, 3)], ['4h', 4 * H, 600, Date.UTC(2026, 2, 3)],
    ['1d', DAY, 500, Date.UTC(2025, 1, 1)], ['1w', 7 * DAY, 400, Date.UTC(2018, 0, 1)]] as const) {
    it(`${iv}：PC 画出来的每一根都和手机网页（= iOS）一样`, () => {
      let s = 7
      const rnd = () => { s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648 }
      const b: Bar[] = []; let px = 100
      for (let k = 0; k < n; k++) {
        const o = px; px *= 1 + (rnd() - 0.5) * 0.03
        const bv = k % 97 === 5 ? 0 : 1000 * rnd()
        b.push({ t: t0 + k * step, o, h: Math.max(o, px) * 1.004, l: Math.min(o, px) * 0.996, c: px, v: bv * px, bv })
      }
      const ser = new BarSeries({ symbol: 'X', interval: iv, t0, step, open: b.map(x => x.o), high: b.map(x => x.h), low: b.map(x => x.l), close: b.map(x => x.c), volume: b.map(x => x.bv as number) })
      const m = new VWAPState(ser).out, [pc] = vwap(b, step)
      let compared = 0
      for (let i = 0; i < n; i++) {
        const x = pc[i]; if (x == null) continue
        compared++
        expect(Math.abs(x - m[i])).toBeLessThanOrEqual(1e-9 * Math.abs(m[i]))
      }
      expect(compared).toBeGreaterThan(n / 2)
    })
  }
  it('锚定 VWAP：坏量那根不进累计', () => {
    const b = bars(4, 0, H, k => ({ bv: k === 1 ? NaN : k === 2 ? Infinity : 10 }))
    const r = anchoredVwap(b, 0, 3)
    expect(r.mid.every(Number.isFinite)).toBe(true)
  })
  it('锚定 VWAP 的起算根：向下取整（换粗周期不漏锚点那根）；锚点早于已加载的第一根不画', () => {
    const ch = fake({ bars: bars(10, 10 * H), iv: H })
    expect(avwapStart(ch, { pts: [{ t: 13 * H + 37 * 6e4, p: 1 }] } as never)).toBe(3)
    expect(avwapStart(ch, { pts: [{ t: 13 * H, p: 1 }] } as never)).toBe(3)
    expect(avwapStart(ch, { pts: [{ t: 9 * H, p: 1 }] } as never)).toBeNull()
  })
})

describe('指标重算是惰性的：标脏不算，第一次读才算、只算一次', () => {
  it('一帧里推多次 / 屏幕外的格子：recalc 只标脏', () => {
    const spy = vi.spyOn(P as Any as { computeSeries(): void }, 'computeSeries')
    const ch = fake({ bars: bars(50), ind: { ma: true, ema: false, boll: false, vol: true, subs: [] }, params: { ma: { periods: [5] } }, deg: { subs: true },
      meta: { symbol: 'X' }, iv: H, env: null, dead: false, _series: {}, _notes: {}, calcStale: false, dirty: false })
    ch.recalc(); ch.recalc(); ch.recalc()
    expect(spy).not.toHaveBeenCalled()
    const a = ch.series, b = ch.series
    expect(spy).toHaveBeenCalledTimes(1)
    expect(a).toBe(b); expect(a.ma?.[0][4]).toBeCloseTo((101 + 102 + 103 + 104 + 105) / 5)
    spy.mockRestore()
  })
})

describe('量差 / 大单的逐笔账监听', () => {
  afterEach(() => resetFlows())
  it('换品种后从旧品种的账上摘掉（不再替旧品种重算、也不攥着关掉的图）', () => {
    const fn = () => {}
    flowOf('AUSDT').listeners.add(fn); flowOf('BUSDT').listeners.add(fn)
    detachFlows(fn)
    expect(flowOf('AUSDT').listeners.has(fn)).toBe(false); expect(flowOf('BUSDT').listeners.has(fn)).toBe(false)
  })
  it('监听里把自己摘掉再登记回去：通知照样只叫一遍、不死循环', () => {
    const f = flowOf('AUSDT'); let n = 0
    const fn = () => { n++; f.listeners.delete(fn); f.listeners.add(fn) }
    f.listeners.add(fn)
    f.notify()
    expect(n).toBe(1)
  })
})

describe('拖整条画线：对数轴上按比例挪', () => {
  it('往下拖一半：上下两点同比例变、不穿到 0 以下', () => {
    const ch = fake({ log: true, bars: bars(20), iv: H })
    const t = bars(20)[3].t
    const out = (ch as unknown as { dragBody(o: unknown[], s: unknown, n: unknown): { t: number; p: number }[] }).dragBody(
      [{ t, p: 100 }, { t, p: 200 }], { t, p: 100 }, { t, p: 50 })
    expect(out[0].p).toBeCloseTo(50); expect(out[1].p).toBeCloseTo(100)
    const lin = fake({ log: false, bars: bars(20), iv: H })
    const o2 = (lin as unknown as { dragBody(o: unknown[], s: unknown, n: unknown): { t: number; p: number }[] }).dragBody(
      [{ t, p: 100 }, { t, p: 200 }], { t, p: 100 }, { t: bars(20)[5].t, p: 50 })
    expect(o2.map(q => q.p)).toEqual([50, 150]); expect(o2[0].t).toBe(bars(20)[5].t)
  })
})

describe('滚轮按 deltaMode 折像素', () => {
  it('像素 / 行 / 页', () => {
    expect(wheelPx(0, 800)).toBe(1); expect(wheelPx(1, 800)).toBe(16); expect(wheelPx(2, 800)).toBe(800); expect(wheelPx(2, 0)).toBe(1)
  })
})

describe('关键价位：取数失败不把图攥在等待表里', () => {
  afterEach(() => resetKeyLevels())
  it('日线 / 5 分钟线都失败：叫醒一次、清空；冷却期内再画不登记', async () => {
    kl.ok = false
    const ch = { meta: { symbol: 'ZUSDT' }, iv: H, bars: [], dead: false, dirty: false } as never
    keyLevelsOf(ch)
    expect(keyLevelsWaiting()).toBe(1)
    await new Promise(r => setTimeout(r, 0))
    expect(keyLevelsWaiting()).toBe(0)
    expect((ch as { dirty: boolean }).dirty).toBe(true)
    keyLevelsOf(ch)
    expect(keyLevelsWaiting()).toBe(0)
  })
})
