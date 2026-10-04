/* 手机网页板块页：轮询回来整块重画时手指正按着，按着的那行不能被换掉（m/ui/dom pressGate / setHTML） */
import { afterEach, describe, expect, it, vi } from 'vitest'

type H = (e: any) => void
function target() {
  const hs: Record<string, H[]> = {}
  return { hs, addEventListener: (t: string, h: H) => { (hs[t] ??= []).push(h) }, fire: (t: string, e: any = {}) => (hs[t] ?? []).forEach(h => h(e)) }
}

afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers() })

describe('pressGate', () => {
  async function setup() {
    vi.useFakeTimers()
    const doc = target()
    vi.stubGlobal('document', doc)
    const { pressGate } = await import('../src/m/ui/dom')
    const root = target()
    const gate = pressGate(root as unknown as HTMLElement)
    return { doc, root, gate }
  }

  it('没按着：立刻跑', async () => {
    const { gate } = await setup()
    const fn = vi.fn(); gate(fn)
    expect(fn).toHaveBeenCalledTimes(1)
  })

  it('按着时来了两次重画：都不跑；松手（click 派发完之后）只跑最后那次', async () => {
    const { doc, root, gate } = await setup()
    root.fire('pointerdown', { pointerId: 1 })
    const a = vi.fn(), b = vi.fn()
    gate(a); gate(b)
    expect(a).not.toHaveBeenCalled(); expect(b).not.toHaveBeenCalled()
    doc.fire('pointerup', { pointerId: 1 })
    expect(b).not.toHaveBeenCalled() // 同一拍里 click 还没派发，不能先把行换掉
    vi.runAllTimers()
    expect(a).not.toHaveBeenCalled(); expect(b).toHaveBeenCalledTimes(1)
  })

  it('两指：两根都抬起来才跑；触摸转成滚动（pointercancel）也算松手', async () => {
    const { doc, root, gate } = await setup()
    root.fire('pointerdown', { pointerId: 1 }); root.fire('pointerdown', { pointerId: 2 })
    const fn = vi.fn(); gate(fn)
    doc.fire('pointerup', { pointerId: 1 }); vi.runAllTimers()
    expect(fn).not.toHaveBeenCalled()
    doc.fire('pointercancel', { pointerId: 2 }); vi.runAllTimers()
    expect(fn).toHaveBeenCalledTimes(1)
  })

  it('丢了松手事件（按住超过 5 秒）：不再挡', async () => {
    const { root, gate } = await setup()
    root.fire('pointerdown', { pointerId: 1 })
    vi.advanceTimersByTime(5100)
    const fn = vi.fn(); gate(fn)
    expect(fn).toHaveBeenCalledTimes(1)
  })
})

describe('setHTML / forgetHTML', () => {
  it('同一串不重写；forget 之后同一串照写（推送就地改过字）', async () => {
    const { setHTML, forgetHTML } = await import('../src/m/ui/dom')
    let writes = 0
    const node = { set innerHTML(_v: string) { writes++ } } as unknown as Element
    expect(setHTML(node, '<a>1</a>')).toBe(true)
    expect(setHTML(node, '<a>1</a>')).toBe(false)
    expect(setHTML(node, '<a>2</a>')).toBe(true)
    forgetHTML(node)
    expect(setHTML(node, '<a>2</a>')).toBe(true)
    expect(writes).toBe(3)
  })
})

describe('板块页接线（m/pages/sectors）', () => {
  it('重画都过 pressGate；下钻表没重写就不重绑长按', async () => {
    // @ts-expect-error Web 的 tsconfig 不带 @types/node，vitest 跑在 node 里有这个模块
    const { readFileSync } = await import('node:fs')
    const src: string = readFileSync(new URL('../src/m/pages/sectors.ts', import.meta.url), 'utf8')
    expect(src).toMatch(/const gate = pressGate\(root\)\s*\n\s*function render\(\): void \{ gate\(renderNow\) \}/)
    expect(src).toMatch(/if \(!setHTML\(drillList, html\.join\(''\)\)\) return\s*\n\s*unpress\.splice\(0\)/)
    expect(src.match(/\w+\.innerHTML = /g)).toEqual(["root.innerHTML = "]) // 只有建页那一次
  })
})
