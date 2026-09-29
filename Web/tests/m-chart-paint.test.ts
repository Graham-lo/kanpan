// paint.ts：文字量宽与逐字落笔的每帧开销、细线的像素对齐（与 Swift Paint.swift / Geometry 的 hairline 对照）。
import { afterEach, describe, expect, it, vi } from 'vitest'

/** 装一块会记账的离屏 canvas（node 里没有 canvas），再重新载入 paint.ts 让它用上。 */
async function paintWithCountingCanvas() {
  const stats = { measure: 0, fontSets: 0 }
  class FakeOffscreen {
    getContext() {
      let font = ''
      return {
        get font() { return font },
        set font(v: string) { stats.fontSets++; font = v },
        measureText(t: string) { stats.measure++; return { width: [...t].length * (t === '1' ? 3 : 5) } },
      }
    }
  }
  vi.stubGlobal('OffscreenCanvas', FakeOffscreen)
  vi.resetModules()
  const paint = await import('../src/m/chart/paint')
  return { paint, stats }
}

function recordingCtx() {
  const calls: { text: string; x: number }[] = []
  const ctx = {
    font: '', fillStyle: '', textAlign: '', textBaseline: '',
    fillText(text: string, x: number) { calls.push({ text, x }) },
  }
  return { ctx: ctx as unknown as CanvasRenderingContext2D, calls }
}

afterEach(() => { vi.unstubAllGlobals(); vi.resetModules() })

describe('paint · 等宽数字逐字落笔', () => {
  it('同一串再画一遍不再量字：每个数字的字宽按字体缓存，不每帧 measureText', async () => {
    const { paint, stats } = await paintWithCountingCanvas()
    const { ctx, calls } = recordingCtx()
    paint.drawLeft(ctx, '12.10', 0, 0, paint.ChartFont.axis, '#000000')
    const first = stats.measure
    expect(first).toBeGreaterThan(0)
    calls.length = 0
    stats.fontSets = 0
    for (let i = 0; i < 60; i++) paint.drawLeft(ctx, '12.10', 0, 0, paint.ChartFont.axis, '#000000')
    expect(stats.measure).toBe(first)
    // 量字那块画布的字体也不该每次重设（canvas 每设一次 font 都要重新解析字体串）
    expect(stats.fontSets).toBe(0)
    // 落笔位置不变：'1' 窄（3），按 '0'（5）的格子居中
    const again = calls.slice(0, 5)
    expect(again.map(c => c.text)).toEqual(['1', '2', '.', '1', '0'])
    expect(again[0].x).toBe(1)
    expect(again[1].x).toBe(5)
  })
})

describe('paint · 细线落在像素中心（Swift hairline：取整 .5 远离零）', () => {
  it('负坐标的 .5 也和 Swift 一样往外取整', async () => {
    const { hairLine, hairLineV } = await import('../src/m/chart/paint')
    const pts: number[] = []
    const ctx = {
      strokeStyle: '', lineWidth: 0,
      beginPath() {}, stroke() {},
      moveTo(x: number, y: number) { pts.push(x, y) },
      lineTo(x: number, y: number) { pts.push(x, y) },
    } as unknown as CanvasRenderingContext2D
    hairLine(ctx, 0, 10, -0.5, 1, '#000000')
    // Swift：(-0.5).rounded() = -1 → -1 + 0.5 = -0.5；JS Math.round(-0.5) = -0 会给 0.5
    expect(pts[1]).toBe(-0.5)
    pts.length = 0
    hairLineV(ctx, -1.5, 0, 10, 1, '#000000')
    expect(pts[0]).toBe(-1.5)
  })
})
