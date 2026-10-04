import { describe, expect, it, vi } from 'vitest'

const frames: (() => void)[] = []
vi.stubGlobal('requestAnimationFrame', (f: () => void) => { frames.push(f); return frames.length })
vi.stubGlobal('cancelAnimationFrame', (id: number) => { if (frames[id - 1]) frames[id - 1] = () => {} })
vi.stubGlobal('getComputedStyle', () => ({ getPropertyValue: () => '' }))
vi.stubGlobal('window', { devicePixelRatio: 1 })
const canvas = { className: '', width: 0, height: 0, style: {} as Record<string, string>, setAttribute: () => {}, remove: () => {},
  getContext: () => new Proxy({}, { get: () => () => {} }) }
vi.stubGlobal('document', { createElement: () => canvas, body: {} })

import { ReviewOverlay } from '../src/review/overlay'

/** 跑掉目前排着的帧，返回跑了几帧 */
function pump(): number { const f = frames.splice(0); f.forEach(x => x()); return f.length }

describe('复盘图上那层的逐帧循环', () => {
  it('复盘页切走后不再排帧，切回来接着跑', () => {
    const chart = { host: {}, _ranges: { main: { min: 0, max: 1 } }, rightBar: 0, spacing: 6, replay: null, w: 100, h: 100, aw: 40, bars: [], _panes: [], plotW: () => 60 }
    const o = new ReviewOverlay({ appendChild: () => {} } as unknown as HTMLElement, chart as never)
    expect(pump()).toBe(1)
    expect(pump()).toBe(1) // 开着时每帧比一次
    o.sleep()
    pump()
    expect(frames.length).toBe(0) // 修前：页面藏着照样每帧排下一帧
    o.wake()
    expect(pump()).toBe(1)
    expect(frames.length).toBe(1)
    o.destroy()
  })
})
