// 手机网页版画线审查补的回归用例（2026-09-30 深度审查）。
// 场地与触摸写法照 m-chart-drawing.test.ts：假 DOM 元素 + 往 view.el 派 PointerEvent 形状的假事件。

import { describe, test, expect, beforeAll, afterEach, vi } from 'vitest'
import {
  type Drawing, type DrawPixel, DrawingController, DrawingBook, DrawAxes, attachDrawing, drawAxesOf, drawingA,
  decodeDrawing, tryDecodeDrawing, decodeStyle, decodeArchive, decodePreferences,
} from '../src/m/chart/drawing'
import { ViewWindow } from '../src/m/chart/geometry'
import { BarSeries, INTERVAL_STEP } from '../src/m/chart/series'
import { makeState, withOverlay, withInput, type ChartState } from '../src/m/chart/state'
import { ChartView } from '../src/m/chart/view'

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
  getContext(kind: string): unknown
}

/** 数一数建过几张画布（放大镜底图）。 */
let canvases: FakeEl[] = []

function fakeEl(ctx: unknown = null): FakeEl {
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
    getContext: () => ctx,
  }
  return el
}

/** 什么都不画、但每个方法都在的 2D 上下文（放大镜底图要一张能画的画布）。 */
const nullCtx = new Proxy({}, {
  get: (_t, k) => (k === 'measureText' ? () => ({ width: 10 }) : () => undefined),
  set: () => true,
})

beforeAll(() => {
  const g = globalThis as Record<string, unknown>
  if (!g.document) g.document = { createElement: () => fakeEl() }
  if (!g.window) g.window = { devicePixelRatio: 2 }
  if (!g.ResizeObserver) g.ResizeObserver = class { observe() { /* 无 */ } unobserve() { /* 无 */ } disconnect() { /* 无 */ } }
  if (!g.requestAnimationFrame) g.requestAnimationFrame = () => 1
  if (!g.cancelAnimationFrame) g.cancelAnimationFrame = () => { /* 无 */ }
})

afterEach(() => { vi.useRealTimers(); vi.restoreAllMocks() })

function drawState(symbol = 'BTCUSDT', count = 400): ChartState {
  const o: number[] = [], h: number[] = [], l: number[] = [], c: number[] = [], vol: number[] = []
  let p = 62_000
  for (let k = 0; k < count; k++) {
    const open = p
    const close = open * (1 + Math.sin(k * 0.37) * 0.004)
    o.push(open); h.push(Math.max(open, close) * 1.002); l.push(Math.min(open, close) * 0.998); c.push(close); vol.push(500)
    p = close
  }
  const series = new BarSeries({
    symbol, interval: '1h', t0: 1_700_000_000_000, step: INTERVAL_STEP['1h'],
    open: o, high: h, low: l, close: c, volume: vol,
  })
  const span = series.step * 120
  return makeState({
    series, symbol: { symbol, base: 'BTC', priceDecimals: 2 },
    view: new ViewWindow(series.lastTime + span * 0.08, span), overlays: [], subs: [],
  })
}

interface Rig { v: ChartView; c: DrawingController; axes: DrawAxes }
function rig(): Rig {
  const v = new ChartView(fakeEl() as unknown as HTMLElement)
  v.state = withOverlay(drawState(), { magnet: false })
  const c = attachDrawing(v)
  c.magnet = false
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
const elOf = (v: ChartView): FakeEl => v.el as unknown as FakeEl
const down = (v: ChartView, f: Finger, ms: number): void => elOf(v).dispatch('pointerdown', ev(f, ms))
const move = (v: ChartView, f: Finger, q: DrawPixel, ms: number): void => { f.x = q.x; f.y = q.y; elOf(v).dispatch('pointermove', ev(f, ms)) }
const up = (v: ChartView, f: Finger, ms: number): void => elOf(v).dispatch('pointerup', ev(f, ms))
function tap(v: ChartView, q: DrawPixel, ms = 10_000): void { const f = finger(q); down(v, f, ms); up(v, f, ms + 50) }

/** 画一条水平线并选中它（一次性模式落下即选中）。 */
function hlineAt(r: Rig, y: number, ms = 10_000): Drawing {
  r.c.setTool('hline')
  tap(r.v, { x: 180, y }, ms)
  const d = r.c.drawings[r.c.drawings.length - 1]
  expect(r.c.selected).toBe(d.id)
  return d
}

describe('画线审查：挂点生命周期', () => {
  test('同一张图摘下再装上：新控制器照样能画、能撤销', () => {
    const r = rig()
    const book = new DrawingBook()
    r.c.bindDrawings(book)
    hlineAt(r, 260)
    r.c.detach()
    const c2 = attachDrawing(r.v)
    c2.bindDrawings(book)
    c2.magnet = false
    expect(c2.canUndo, '换上来的控制器看不到这只品种的撤销栈').toBe(true)
    c2.setTool('hline')
    tap(r.v, { x: 180, y: 300 }, 20_000)
    expect(c2.drawings.length, '重新装上的控制器落不下线（投影键没接上）').toBe(2)
    expect(book.items('BTCUSDT').length).toBe(2)
  })

  test('视图换了投影函数就忘掉旧键：新控制器不靠 adoptKey 也会收到换键回调', () => {
    const r = rig()
    r.c.detach()
    const seen: (string | null)[] = []
    r.v.drawingKeyOf = () => 'BTCUSDT'
    r.v.onDrawingKeyChanged = from => { seen.push(from) }
    r.v.state = r.v.state
    expect(seen, '挂上新的投影函数后第一份 state 要当成第一次有了键').toEqual([null])
  })

  test('图销毁时画线控制器跟着摘下：退订本、停长按计时器，不再挂在全局本的观察者里', () => {
    vi.useFakeTimers()
    const r = rig()
    const book = new DrawingBook()
    r.c.bindDrawings(book)
    const observers = () => (book as unknown as { observers: unknown[] }).observers.length
    expect(observers()).toBe(1)
    hlineAt(r, 260)
    down(r.v, finger({ x: 180, y: 260 }), 30_000)
    expect(vi.getTimerCount(), '按住选中的线会起长按上锁的计时器').toBeGreaterThan(0)
    r.v.destroy()
    expect(observers(), '销毁之后控制器还挂在全局本上（强引用，整张图都放不掉）').toBe(0)
    expect(vi.getTimerCount(), '长按计时器还在').toBe(0)
    expect(r.v.drawingInput).toBeNull()
    expect(r.v.drawingProject).toBeNull()
  })
})

describe('画线审查：拖线途中被别的按钮改了线', () => {
  /** 画一条水平线，拖一次（进撤销栈），再按住开始第二次拖、挪到一半。 */
  function midDrag(): { r: Rig; f: Finger; first: Drawing; moved: Drawing } {
    const r = rig()
    const first = hlineAt(r, 260)
    const f1 = finger({ x: 180, y: 260 })
    down(r.v, f1, 11_000); move(r.v, f1, { x: 180, y: 280 }, 11_020); move(r.v, f1, { x: 180, y: 300 }, 11_040); up(r.v, f1, 11_060)
    const moved = r.c.drawings[0]
    expect(Math.abs(r.axes.y(drawingA(moved).p) - 300)).toBeLessThan(0.5)
    const f = finger({ x: 180, y: 300 })
    down(r.v, f, 12_000); move(r.v, f, { x: 180, y: 330 }, 12_020); move(r.v, f, { x: 180, y: 360 }, 12_040)
    expect(r.v.state!.overlay.drawingPreviewID, '第二次拖动没开始').toBe(first.id)
    return { r, f, first, moved }
  }

  test('拖到一半点「撤销」：抬手后底层照常画这条线，不留预览', () => {
    const { r, f, first } = midDrag()
    r.c.undo()
    up(r.v, f, 12_060)
    const d = r.c.drawings.find(x => x.id === first.id)!
    expect(Math.abs(r.axes.y(drawingA(d).p) - 260), '撤销没回到第一次拖动之前').toBeLessThan(0.5)
    expect(r.v.state!.overlay.drawingPreviewID, '预览 id 还挂着：底层一直跳过这条线').toBeNull()
    expect(r.c.preview, '覆盖层还拿着拖动的那份预览').toBeNull()
  })

  test('拖到一半点「删除」再撤销：删掉的线回来之后底层照常画', () => {
    const { r, f, first } = midDrag()
    r.c.deleteSelected()
    up(r.v, f, 12_060)
    r.c.undo()
    expect(r.c.drawings.some(x => x.id === first.id)).toBe(true)
    expect(r.v.state!.overlay.drawingPreviewID, '撤销回来的线被当成正在拖的那条，底层不画').toBeNull()
  })

  test('拖到一半点「全部隐藏」：抬手不把这条又显出来', () => {
    const { r, f, first } = midDrag()
    r.c.setAllHidden(true)
    up(r.v, f, 12_060)
    const d = r.c.drawings.find(x => x.id === first.id)!
    expect(d.hidden, '抬手把拖动前那份（没隐藏的）写回去了').toBe(true)
    expect(r.v.state!.overlay.drawingPreviewID).toBeNull()
  })

  test('拖到一半点「清空」再撤销：线回来且底层照常画', () => {
    const { r, f, first } = midDrag()
    r.c.clear()
    up(r.v, f, 12_060)
    expect(r.c.drawings).toEqual([])
    r.c.undo()
    expect(r.c.drawings.some(x => x.id === first.id)).toBe(true)
    expect(r.v.state!.overlay.drawingPreviewID).toBeNull()
  })
})

describe('画线审查：拖到一半摘下控制器', () => {
  test('摘下之后这条线底层照常画，不留「正在拖」的预览 id', () => {
    const r = rig()
    const d = hlineAt(r, 260)
    const f = finger({ x: 180, y: 260 })
    down(r.v, f, 12_000); move(r.v, f, { x: 180, y: 300 }, 12_020)
    expect(r.v.state!.overlay.drawingPreviewID).toBe(d.id)
    r.c.detach()
    expect(r.v.state!.overlay.drawingPreviewID, '摘下后预览 id 还挂着：底层一直跳过这条线，覆盖层也没了').toBeNull()
    expect(r.v.state!.overlay.drawings.some(x => x.id === d.id)).toBe(true)
  })
})

describe('画线审查：放大镜底图', () => {
  test('每按一下都截一张整屏底图，但画布只建一张、反复用；摘下时把位图放掉', () => {
    const r = rig()
    vi.spyOn(r.v.renderer!, 'drawPlot').mockImplementation(() => { /* 不真画 */ })
    const g = globalThis as { document: { createElement: (k: string) => unknown } }
    canvases = []
    vi.spyOn(g.document, 'createElement').mockImplementation(() => { const e = fakeEl(nullCtx); canvases.push(e); return e })
    for (let k = 0; k < 6; k++) {
      r.c.setTool('hline')
      tap(r.v, { x: 180, y: 200 + k * 20 }, 30_000 + k * 1000)
    }
    expect(r.c.drawings.length).toBe(6)
    // iOS Safari 的画布内存有总上限（几百 MB），一张 3 倍屏的整屏底图十几 MB；
    // 每按一下新建一张、等 GC 慢慢收，连着画几十下就会顶到上限，之后新画布拿不到上下文。
    expect(canvases.length, '放大镜底图每按一下都新建一张画布').toBe(1)
    expect(canvases[0].width).toBeGreaterThan(0)
    r.c.detach()
    expect(canvases[0].width, '摘下之后底图的位图还占着').toBe(0)
  })
})

describe('画线审查：颜色只收十六进制', () => {
  // 线的颜色会被页面拼进 innerHTML（样式面板的色块 style="--c:…"、取色器 value="…"）；
  // 云端同步与朋友分享来的线都走这条解码，颜色字段是外来的任意字符串就是一个注入口。
  // iOS 写出来的永远是 #RRGGBB，所以解码只收 #RRGGBB / #RRGGBBAA，其余当「没设颜色」，线本身留着。
  const bad = ['#D6A64F" autofocus onfocus="alert(1)', 'red', '#12345', 'url(javascript:1)', '#D6A64FZZ', '']
  const base = { id: 'x1', kind: 'hline', points: [{ t: 1_700_000_000_000, p: 100 }] }

  test('decodeDrawing：合法颜色原样留着', () => {
    for (const c of ['#D6A64F', '#d6a64f', '#D6A64F80']) expect(decodeDrawing({ ...base, color: c }).color).toBe(c)
    expect(decodeDrawing({ ...base, color: { value: '#112233' } }).color).toBe('#112233')
  })

  test('decodeDrawing：不是十六进制的颜色不收，线照样留着', () => {
    for (const c of bad) {
      const d = tryDecodeDrawing({ ...base, color: c })
      expect(d, `颜色 ${JSON.stringify(c)} 让整条线解不开`).not.toBeNull()
      expect(d!.color, `颜色 ${JSON.stringify(c)} 原样进了线`).toBeNull()
    }
  })

  test('decodeStyle / 偏好：记住的样式里的坏颜色同样不收', () => {
    const style = { lineWidth: 2, filled: false, dash: 'solid', levels: [] }
    expect(decodeStyle({ ...style, color: '#ABCDEF' })!.color).toBe('#ABCDEF')
    for (const c of bad) {
      const st = decodeStyle({ ...style, color: c })
      expect(st, `颜色 ${JSON.stringify(c)} 让整份样式丢了`).not.toBeNull()
      expect(st!.color).toBeNull()
    }
    const p = decodePreferences({ styles: { hline: { ...style, color: bad[0] } } })
    expect(p.styles.hline?.color ?? null).toBeNull()
  })

  test('存档：坏颜色的线读回来还在', () => {
    const a = decodeArchive({ v: 2, d: { 'binance/usd_m/BTCUSDT': [{ ...base, color: bad[0] }] } })
    const items = a.get('BTCUSDT')
    expect(items.length).toBe(1)
    expect(items[0].color).toBeNull()
  })
})

describe('画线审查：画到一半换品种 / 换周期 / 系统取消', () => {
  const cancelEv = (v: ChartView, f: Finger, ms: number): void => elOf(v).dispatch('pointercancel', ev(f, ms))

  test('握着工具按下、没抬手就换了品种：抬手不在新品种上落线，坐标轴不钉着', () => {
    const r = rig()
    const book = new DrawingBook()
    r.c.bindDrawings(book)
    r.c.setTool('hline')
    const f = finger({ x: 180, y: 260 })
    down(r.v, f, 10_000); move(r.v, f, { x: 180, y: 280 }, 10_020)
    r.v.state = drawState('ETHUSDT')
    move(r.v, f, { x: 180, y: 300 }, 10_040)
    up(r.v, f, 10_060)
    expect(book.items('ETHUSDT'), '换品种之后这一下落在了新品种上').toEqual([])
    expect(book.items('BTCUSDT')).toEqual([])
    expect(r.c.tool, '换品种应放下工具').toBeNull()
    expect(r.v.axesFrozen, '换品种之后坐标轴还钉着').toBe(false)
  })

  test('趋势线落了第一点后换周期：第二点照常落成，两点都按时间存', () => {
    const r = rig()
    r.c.setTool('trend')
    tap(r.v, { x: 120, y: 300 }, 10_000)
    const first = r.c.anchors[0]
    expect(first).toBeTruthy()
    const s = r.v.state!
    const s4 = drawState('BTCUSDT', 200)
    r.v.state = withInput(s, { series: new BarSeries({ ...s4.input.series, interval: '4h', step: INTERVAL_STEP['4h'] } as never) })
    expect(r.c.anchors.length, '换周期把第一点丢了（品种没变，Swift 也留着）').toBe(1)
    const a = drawAxesOf(r.v)!
    tap(r.v, { x: 280, y: 200 }, 12_000)
    const d = r.c.drawings[0]
    expect(d?.kind).toBe('trend')
    expect(d.points[0]).toEqual(first)
    expect(Number.isFinite(d.points[1].t) && Number.isFinite(d.points[1].p)).toBe(true)
    expect(Math.abs(a.x(d.points[1].t) - 280)).toBeLessThan(0.5)
  })

  test('握着工具按下、系统取消（pointercancel）：不落点、不留半截', () => {
    const r = rig()
    r.c.setTool('trend')
    const f = finger({ x: 120, y: 300 })
    down(r.v, f, 10_000); move(r.v, f, { x: 200, y: 260 }, 10_020)
    cancelEv(r.v, f, 10_040)
    expect(r.c.drawings).toEqual([])
    expect(r.c.anchors).toEqual([])
    expect(r.c.aim).toBeNull()
    expect(r.c.origin).toBeNull()
    expect(r.v.axesFrozen).toBe(false)
  })

  test('没有 K 线的图：握着工具点、画水平线都不落、不抛', () => {
    const v = new ChartView(fakeEl() as unknown as HTMLElement)
    v.state = drawState('BTCUSDT', 0)
    const c = attachDrawing(v)
    c.setTool('hline')
    tap(v, { x: 180, y: 260 })
    expect(c.drawings).toEqual([])
    expect(c.addHorizontalLine(100)).toBe(false)
    c.undo(); c.redo(); c.duplicateSelected(); c.clear()
  })
})
