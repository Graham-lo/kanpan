/* 手机网页版深度审查 E 线 C5：拖排序途中表被重画（同步落地 / 品种表 / 回前台），松手按老下标套到新表上挪走别人，
 * 手里抬起的那行也被换掉（3f4ddc01 只修了「先按自选过滤再按下标挪」那一半）。
 * 修法：reorderable 把起拖那一刻的行快照交给 onMove(from, to, rows)，暴露 dragging；调用方拖的途中不重画、onEnd 补画。 */
import { afterEach, describe, expect, it, vi } from 'vitest'
import { reorderable } from '../src/m/ui/reorder'
import { moveVisible } from '../src/m/model/favorites'
import { moveSubAmong } from '../src/m/pages/chart/logic'
import favSource from '../src/m/pages/favorites.ts?raw'
import panelSource from '../src/m/pages/chart/panels.ts?raw'
import pickerSource from '../src/m/pages/symbolPicker.ts?raw'

afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers() })

type L = (e: unknown) => void
function fakeRow(sym: string, top: number) {
  const style: Record<string, string> = {}
  return {
    dataset: { sym }, style, offsetHeight: 50,
    classList: { add() {}, remove() {} },
    getBoundingClientRect: () => ({ top, height: 50 }),
    closest(sel: string) { return sel === '.lr' ? this : null },
  }
}
function harness(syms: string[]) {
  let rows = syms.map((s, i) => fakeRow(s, i * 50))
  const listL: Record<string, L[]> = {}, winL: Record<string, L[]> = {}
  const list = {
    parentElement: null,
    querySelectorAll: () => rows,
    contains: () => true,
    classList: { add() {}, remove() {} },
    addEventListener: (t: string, f: L) => { (listL[t] ??= []).push(f) },
    removeEventListener: () => {},
  }
  vi.stubGlobal('addEventListener', (t: string, f: L) => { (winL[t] ??= []).push(f) })
  vi.stubGlobal('removeEventListener', () => {})
  vi.stubGlobal('document', { scrollingElement: { scrollTop: 0 } })
  vi.stubGlobal('innerHeight', 2000)
  let frame: (() => void) | null = null
  vi.stubGlobal('requestAnimationFrame', (cb: () => void) => { frame = cb; return 1 })
  vi.stubGlobal('cancelAnimationFrame', () => {})
  vi.stubGlobal('window', { setTimeout, clearTimeout })
  const fire = (m: Record<string, L[]>, t: string, e: unknown) => (m[t] ?? []).forEach(f => f(e))
  return {
    list, get rows() { return rows }, set rows(v) { rows = v }, fakeRow,
    down(i: number) { const r = rows[i]; fire(listL, 'pointerdown', { button: 0, pointerId: 1, clientX: 10, clientY: r.getBoundingClientRect().top + 25, target: r }) },
    move(y: number) { fire(winL, 'pointermove', { pointerId: 1, clientX: 10, clientY: y, preventDefault() {} }); const f = frame; frame = null; f?.() },
    up() { fire(winL, 'pointerup', { pointerId: 1 }) },
  }
}

describe('拖排序按起拖那一刻的行挪', () => {
  it('复现：拖着 A 往下两行时另一台设备删了 B、表被重画——onMove 拿到的是起拖快照，按键挪不挪走别人', () => {
    vi.useFakeTimers()
    const h = harness(['A', 'B', 'C', 'D'])
    const onMove = vi.fn(), onEnd = vi.fn()
    // @ts-expect-error 假 DOM
    const r = reorderable(h.list, { item: '.lr', onMove, onEnd })
    h.down(0)
    vi.advanceTimersByTime(400)
    expect(r.dragging).toBe(true)
    h.move(25 + 110)                                           // 中线越过 B、C 的中线 → to = 2
    // 途中重画：B 没了，DOM 里是新的一组行
    h.rows = ['A', 'C', 'D'].map((s, i) => h.fakeRow(s, i * 50))
    h.up()
    expect(r.dragging).toBe(false)
    expect(onMove).toHaveBeenCalledTimes(1)
    const [from, to, rows] = onMove.mock.calls[0]
    expect([from, to]).toEqual([0, 2])
    expect(rows.map((x: { dataset: { sym: string } }) => x.dataset.sym)).toEqual(['A', 'B', 'C', 'D'])
    expect(onEnd).toHaveBeenCalledTimes(1)
    // 模型：按快照挪，A 落到 C 后面；以前拿重画后的 shown（A C D）套下标 → A 跑到 D 后面
    const p = { favorites: ['A', 'C', 'D'], groups: [], groupForSymbol: {} } as unknown as Parameters<typeof moveVisible>[0]
    moveVisible(p, rows.map((x: { dataset: { sym: string } }) => x.dataset.sym), from, to)
    expect(p.favorites).toEqual(['C', 'A', 'D'])
    const q = { favorites: ['A', 'C', 'D'], groups: [], groupForSymbol: {} } as unknown as Parameters<typeof moveVisible>[0]
    moveVisible(q, ['A', 'C', 'D'], from, to)
    expect(q.favorites).toEqual(['C', 'D', 'A'])            // 旧口径的错位
  })

  it('取消（pointercancel / destroy）也走 onEnd，不调 onMove', () => {
    vi.useFakeTimers()
    const h = harness(['A', 'B'])
    const onMove = vi.fn(), onEnd = vi.fn()
    // @ts-expect-error 假 DOM
    const r = reorderable(h.list, { item: '.lr', onMove, onEnd })
    h.down(0); vi.advanceTimersByTime(400); h.move(120)
    r.destroy()
    expect(onMove).not.toHaveBeenCalled()
    expect(onEnd).toHaveBeenCalledTimes(1)
    expect(r.dragging).toBe(false)
  })

  it('副图把手：途中加了一个副图，按快照挪、新来的原位不动', () => {
    expect(moveSubAmong(['VOL', 'OI', 'MACD'], ['VOL', 'OI', 'MACD'], 0, 2)).toEqual(['OI', 'MACD', 'VOL'])
    expect(moveSubAmong(['VOL', 'RSI', 'MACD'], ['VOL', 'OI', 'MACD'], 0, 2)).toEqual(['MACD', 'RSI', 'VOL'])
    expect(moveSubAmong(['VOL', 'OI'], ['VOL', 'OI', 'MACD'], 2, 0)).toEqual(['VOL', 'OI'])
  })

  it('三个调用方都按 rows 挪、拖的途中不重画、onEnd 补画', () => {
    for (const [name, src] of [['favorites', favSource], ['panels', panelSource], ['picker', pickerSource]] as const) {
      expect(src, name).toMatch(/onMove\(from, to, rows\)/)
      expect(src, name).toMatch(/if \((sorter|reorder)\?\.dragging\) \{ redrawAfterDrag = true; return \}/)
      expect(src, name).toMatch(/onEnd\(\) \{ if \(redrawAfterDrag\) \{ redrawAfterDrag = false;/)
    }
  })
})
