/* C15 挂机主线程占用：自选表只改看得见的行（RowGate）、屏幕外的画线不画（offPlot） */
import { describe, expect, it } from 'vitest'
import { RowGate } from '../src/watch/logic'
import { offPlot, type Pane } from '../src/chart/chart'

describe('RowGate：自选表滚出去的行推送来了不碰 DOM，滚进来时补一次', () => {
  it('还没报过可见性的行当看得见（刚画出来、观察器还没回调），照常改字', () => {
    const g = new RowGate()
    expect(g.offer('BTCUSDT')).toBe(true)
    expect(g.stats()).toEqual({ hidden: 0, owed: 0 })
  })
  it('看不见的行：推送只记欠着，多次推送只欠一笔', () => {
    const g = new RowGate()
    expect(g.seen('ETHUSDT', false)).toBe(false)
    expect(g.offer('ETHUSDT')).toBe(false)
    expect(g.offer('ETHUSDT')).toBe(false)
    expect(g.stats()).toEqual({ hidden: 1, owed: 1 })
  })
  it('滚进来：欠着的补写一次，之后推送照常直写；没欠的滚进来不写', () => {
    const g = new RowGate()
    g.seen('A', false); g.seen('B', false)
    g.offer('A')
    expect(g.seen('A', true)).toBe(true)
    expect(g.seen('A', true)).toBe(false)
    expect(g.seen('B', true)).toBe(false)
    expect(g.offer('A')).toBe(true)
    expect(g.stats()).toEqual({ hidden: 0, owed: 0 })
  })
  it('又滚出去：重新开始欠着', () => {
    const g = new RowGate()
    g.seen('A', true)
    expect(g.offer('A')).toBe(true)
    g.seen('A', false)
    expect(g.offer('A')).toBe(false)
    expect(g.seen('A', true)).toBe(true)
  })
  it('重画表格（reset）：之前的可见性和欠账都作废', () => {
    const g = new RowGate()
    g.seen('A', false); g.offer('A')
    g.reset()
    expect(g.stats()).toEqual({ hidden: 0, owed: 0 })
    expect(g.offer('A')).toBe(true)
  })
})

describe('offPlot：整条画线（带标签、提醒点、把手）都在主图外才不画', () => {
  const p: Pane = { id: 'main', y: 0, h: 300 }, PW = 500
  const at = (x: number, y: number) => ({ x, y })
  it('图里、压着边的都画', () => {
    expect(offPlot('trend', [at(10, 10), at(100, 100)], p, PW)).toBe(false)
    expect(offPlot('trend', [at(-500, 10), at(5, 100)], p, PW)).toBe(false) // 线段一头伸进图里
    expect(offPlot('rect', [at(-50, -50), at(600, 400)], p, PW)).toBe(false) // 矩形把整张图框住
    expect(offPlot('trend', [at(-10, 10), at(-12, 20)], p, PW)).toBe(false) // 离左边 16 以内：提醒点 / 把手还露着
  })
  it('整条在左边、右边、上面、下面：不画', () => {
    expect(offPlot('trend', [at(-300, 10), at(-100, 100)], p, PW)).toBe(true)
    expect(offPlot('rect', [at(600, 10), at(700, 100)], p, PW)).toBe(true)
    expect(offPlot('trend', [at(10, -200), at(100, -50)], p, PW)).toBe(true)
    expect(offPlot('vline', [at(-40, 0)], p, PW)).toBe(true)
  })
  it('斐波那契的读数写在左端再往左：左端刚出右边界还要画，出得够远才不画', () => {
    expect(offPlot('fib', [at(520, 50), at(800, 200)], p, PW)).toBe(false)
    expect(offPlot('fib', [at(800, 50), at(900, 200)], p, PW)).toBe(true)
    expect(offPlot('fib', [at(-300, 50), at(-100, 200)], p, PW)).toBe(true)
  })
  it('测量的读数框在上下 50 以内：框还露着就画', () => {
    expect(offPlot('measure', [at(100, -60), at(150, -20)], p, PW)).toBe(false)
    expect(offPlot('measure', [at(100, -600), at(150, -400)], p, PW)).toBe(true)
  })
  it('射线往外延伸不判；水平线只看高度', () => {
    expect(offPlot('ray', [at(-900, 10), at(-800, 20)], p, PW)).toBe(false)
    expect(offPlot('hline', [at(-900, 150)], p, PW)).toBe(false)
    expect(offPlot('hline', [at(100, 400)], p, PW)).toBe(true)
  })
  it('坐标算不出来（NaN）的照旧交给画的那段，不在这里吞掉', () => {
    expect(offPlot('trend', [at(NaN, 10), at(100, 20)], p, PW)).toBe(false)
  })
})
