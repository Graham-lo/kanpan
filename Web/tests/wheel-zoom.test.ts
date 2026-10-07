// 滚轮 / 触控板缩放照 TradingView（lightweight-charts ChartWidget._onMousewheel + TimeScale.zoom）的纯函数验收
import { describe, expect, it } from 'vitest'
import {
  DEFAULT_SPACING, MAX_SPACING, MIN_SPACING, PAN_PX_PER_NOTCH, ZOOM_MS,
  anchoredRightBar, clampRightBar, clampSpacing, easeSpacing, isWinChromium, panPx, pinchFactor, timeAxisDragSpacing,
  wheelDelta, wheelSpeed, zoomFactor, zoomScale, zoomStart, zoomStep, type ZoomAnim,
} from '../src/chart/wheel'

const W = 2375, LAST = 1499
const xOf = (idx: number, rb: number, sp: number): number => W - (rb - idx) * sp
const idxAt = (x: number, rb: number, sp: number): number => rb - (W - x) / sp

/** 照 chart.ts 的接法跑：事件进来 zoomStart，60 Hz 的虚拟时钟一帧一个 zoomStep */
function run(events: { t: number; f: number; x: number }[], sp0 = DEFAULT_SPACING, rb0 = LAST + 10, until = 600) {
  let sp = sp0, rb = rb0, a: ZoomAnim | null = null
  const frames: { t: number; sp: number; rb: number; idx: number | null; x: number | null }[] = []
  let k = 0
  for (let t = 0; t <= until; t += 1000 / 60) {
    while (k < events.length && events[k].t <= t) { const e = events[k++]; a = zoomStart(a, sp, rb, e.f, idxAt(e.x, rb, sp), e.x, e.t) }
    if (a) { const r = zoomStep(a, t, W, LAST); sp = a.sp = r.spacing; rb = a.rb = r.rightBar; frames.push({ t, sp, rb, idx: a.idx, x: a.x }); if (r.done) a = null }
  }
  return { sp, rb, frames }
}

describe('deltaMode 折算与单次夹档（TV _determineWheelSpeedAdjustment / _onMousewheel）', () => {
  it('像素 1、行 32、页 120；Windows 上的 Chromium 像素再除 DPR', () => {
    expect(wheelSpeed(0)).toBe(1); expect(wheelSpeed(1)).toBe(32); expect(wheelSpeed(2)).toBe(120)
    expect(wheelSpeed(0, true, 1.5)).toBeCloseTo(1 / 1.5); expect(wheelSpeed(1, true, 2)).toBe(32)
    expect(isWinChromium('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36')).toBe(true)
    expect(isWinChromium('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36')).toBe(false)
  })
  it('一格滚轮：像素 100 / 页 1 满档 ×1.1 / ×0.9；按行 3 行 = 0.96 档 ×1.096（与 TV 同）', () => {
    const f = (d: number, m: number) => zoomFactor(zoomScale(wheelDelta({ deltaX: 0, deltaY: d, deltaMode: m }, wheelSpeed(m)).dy))
    expect(f(-100, 0)).toBeCloseTo(1.1, 12); expect(f(100, 0)).toBeCloseTo(0.9, 12)
    expect(f(-1, 2)).toBeCloseTo(1.1, 12); expect(f(1, 2)).toBeCloseTo(0.9, 12)
    expect(f(-3, 1)).toBeCloseTo(1.096, 12); expect(f(3, 1)).toBeCloseTo(0.904, 12)
  })
  it('单个事件夹在一档：再大的量也只 ×1.1 / ×0.9；触控板小量按比例', () => {
    expect(zoomScale(-7.2)).toBe(-1); expect(zoomScale(30)).toBe(1); expect(zoomScale(0.04)).toBeCloseTo(0.04)
    expect(zoomFactor(zoomScale(wheelDelta({ deltaX: 0, deltaY: -4, deltaMode: 0 }, 1).dy))).toBeCloseTo(1.004)
  })
  it('Ctrl / 捏合：e^dy 跟手，单个事件也夹在一档', () => {
    expect(pinchFactor(0.03)).toBeCloseTo(Math.exp(0.03)); expect(pinchFactor(-0.03)).toBeCloseTo(Math.exp(-0.03))
    expect(pinchFactor(-1)).toBeCloseTo(0.9); expect(pinchFactor(5)).toBeCloseTo(1.1)
  })
  it('横向：一格 80 px（TV scrollChart(-80·dx)）；Shift + 竖滚在没有 deltaX 时换成横滑，往下滚看更新的', () => {
    expect(panPx(wheelDelta({ deltaX: 100, deltaY: 0, deltaMode: 0 }, 1).dx)).toBe(PAN_PX_PER_NOTCH)
    const s = wheelDelta({ deltaX: 0, deltaY: 100, deltaMode: 0, shiftKey: true }, 1)
    expect(s.dy).toBe(0); expect(panPx(s.dx)).toBe(80)
    const s2 = wheelDelta({ deltaX: -100, deltaY: 0, deltaMode: 0, shiftKey: true }, 1) // 系统已经换过轴：原样用
    expect(panPx(s2.dx)).toBe(-80); expect(s2.dy === 0).toBe(true)
  })
})

describe('锚点：鼠标下那根缩放前后不挪（< 0.5 px）', () => {
  it('一格放大 / 缩小，锚点在左、中、右；每一帧都不挪', () => {
    for (const x of [1, 600, 1187.3, 2200, W]) for (const f of [1.1, 0.9]) {
      const rb0 = LAST + 10, idx0 = idxAt(x, rb0, DEFAULT_SPACING)
      const { sp, rb, frames } = run([{ t: 0, f, x }])
      expect(sp).toBeCloseTo(DEFAULT_SPACING * f, 9)
      for (const fr of frames) expect(Math.abs(xOf(idx0, fr.rb, fr.sp) - x)).toBeLessThan(0.5)
      expect(Math.abs(xOf(idx0, rb, sp) - x)).toBeLessThan(1e-6)
    }
  })
  it('anchoredRightBar 把 idx 摆回 x', () => {
    const rb = anchoredRightBar(1234.56, 800, W, 7.3)
    expect(xOf(1234.56, rb, 7.3)).toBeCloseTo(800, 9)
  })
})

describe('上下限与视口夹', () => {
  it('间距夹在 [0.5, 50]，默认 6', () => {
    expect(MIN_SPACING).toBe(0.5); expect(MAX_SPACING).toBe(50); expect(DEFAULT_SPACING).toBe(6)
    expect(clampSpacing(0.1)).toBe(0.5); expect(clampSpacing(80)).toBe(50)
    let r = run(Array.from({ length: 80 }, (_, i) => ({ t: i * 30, f: 0.9, x: 1000 })), DEFAULT_SPACING, LAST + 10, 4000)
    expect(r.sp).toBe(MIN_SPACING)
    r = run(Array.from({ length: 80 }, (_, i) => ({ t: i * 30, f: 1.1, x: 1000 })), DEFAULT_SPACING, LAST + 10, 4000)
    expect(r.sp).toBe(MAX_SPACING)
  })
  it('到了上限再滚：不再起动画', () => {
    expect(zoomStart(null, MAX_SPACING, 100, 1.1, 50, 100, 0)).toBeNull()
    expect(zoomStart(null, MIN_SPACING, 100, 0.9, 50, 100, 0)).toBeNull()
  })
  it('右沿夹住：两头至少各留 2 根看得见（TV correctOffset）', () => {
    expect(clampRightBar(-500, LAST, W, 6)).toBe(1)
    expect(clampRightBar(1e6, LAST, W, 6)).toBeCloseTo(LAST + W / 6 - 2)
    expect(clampRightBar(LAST + 10, LAST, W, 6)).toBe(LAST + 10)
    expect(clampRightBar(5, -1, W, 6)).toBe(5) // 没数据不夹
  })
  it('时间轴拖动（TV scaleTo）：右沿不动，按下处那根跟着鼠标；往左拖放大，往右拖缩小', () => {
    expect(timeAxisDragSpacing(6, 2000, 1625, W)).toBeCloseTo(12) // 到右沿 375 → 750
    expect(timeAxisDragSpacing(6, 1625, 2000, W)).toBeCloseTo(3)
    expect(timeAxisDragSpacing(6, 2000, W + 10, W)).toBeNull()
    expect(timeAxisDragSpacing(6, 2374, 0, W)).toBe(MAX_SPACING)
  })
})

describe('顺滑与累加', () => {
  it('一格：60 Hz 下至少 3 帧中间帧，单调不回弹，ZOOM_MS（≤150 ms）内到位', () => {
    const { frames } = run([{ t: 0, f: 1.1, x: 1000 }])
    const mid = frames.filter(f => Math.abs(f.sp - DEFAULT_SPACING * 1.1) > 1e-9 && f.sp !== DEFAULT_SPACING)
    expect(mid.length).toBeGreaterThanOrEqual(3)
    for (let i = 1; i < frames.length; i++) expect(frames[i].sp).toBeGreaterThanOrEqual(frames[i - 1].sp)
    expect(frames[frames.length - 1].t).toBeLessThanOrEqual(150)
    expect(ZOOM_MS).toBeLessThanOrEqual(150)
  })
  it('没到位又滚一格：目标在原目标上再乘一格（三格 = ×1.331），停手后 ≤150 ms 到位', () => {
    const ev = [0, 40, 80].map(t => ({ t, f: 1.1, x: 1500 }))
    const { sp, frames } = run(ev)
    expect(sp).toBeCloseTo(DEFAULT_SPACING * 1.331, 9)
    expect(frames[frames.length - 1].t - 80).toBeLessThanOrEqual(150)
    for (let i = 1; i < frames.length; i++) expect(frames[i].sp).toBeGreaterThanOrEqual(frames[i - 1].sp - 1e-12)
  })
  it('累加中换了锚点：每一格都锚在那一刻鼠标下那根', () => {
    const r = run([{ t: 0, f: 1.1, x: 500 }, { t: 50, f: 1.1, x: 2000 }])
    const last = r.frames[r.frames.length - 1]
    expect(Math.abs(xOf(last.idx!, r.rb, r.sp) - 2000)).toBeLessThan(1e-6)
    expect(r.sp).toBeCloseTo(DEFAULT_SPACING * 1.21, 9)
  })
  it('反向滚：放大中途往回缩，目标按原目标算（1.1 × 0.9）', () => {
    expect(run([{ t: 0, f: 1.1, x: 1000 }, { t: 30, f: 0.9, x: 1000 }]).sp).toBeCloseTo(DEFAULT_SPACING * 0.99, 9)
  })
  it('插值在对数空间里走：放大缩小同一手感，两端不越界', () => {
    expect(easeSpacing(6, 12, 0)).toBe(6); expect(easeSpacing(6, 12, 1)).toBe(12); expect(easeSpacing(6, 12, 2)).toBe(12)
    const a = easeSpacing(6, 12, 0.3), b = easeSpacing(12, 6, 0.3)
    expect(Math.log(a / 6)).toBeCloseTo(Math.log(12 / b), 9)
  })
})
