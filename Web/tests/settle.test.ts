/* 「品种停稳」闸：连切时非首屏请求只给最后停下的那只发（market/settle.ts） */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { Settle, SETTLE_MS } from '../src/market/settle'

describe('Settle', () => {
  beforeEach(() => { vi.useFakeTimers(); vi.setSystemTime(1_000_000) })
  afterEach(() => { vi.useRealTimers() })

  it('冷启动算停稳：登记了立刻做', () => {
    const s = new Settle(), f = vi.fn()
    expect(s.settled()).toBe(true)
    s.whenSettled('a', f)
    expect(f).toHaveBeenCalledTimes(1)
  })

  it('换了品种后半秒内不做，停稳才做', () => {
    const s = new Settle(), f = vi.fn()
    s.noteSwitch()
    s.whenSettled('a', f)
    vi.advanceTimersByTime(SETTLE_MS - 1)
    expect(f).not.toHaveBeenCalled()
    vi.advanceTimersByTime(1)
    expect(f).toHaveBeenCalledTimes(1)
    expect(s.settled()).toBe(true)
  })

  it('连切十只（每 150 ms 一下）：同一个 key 只做最后一次登记的，从最后一下起算半秒', () => {
    const s = new Settle(), done: number[] = []
    for (let i = 0; i < 10; i++) {
      s.noteSwitch()
      s.whenSettled('detail', () => done.push(i))
      vi.advanceTimersByTime(150)
    }
    expect(done).toEqual([])
    vi.advanceTimersByTime(SETTLE_MS - 150 - 1)
    expect(done).toEqual([])
    vi.advanceTimersByTime(1)
    expect(done).toEqual([9])
    expect(s.pending).toBe(0)
  })

  it('不同 key 各做各的；cancel 撤掉的不做', () => {
    const s = new Settle(), a = vi.fn(), b = vi.fn()
    s.noteSwitch()
    s.whenSettled('a', a); s.whenSettled('b', b); s.cancel('b')
    vi.advanceTimersByTime(SETTLE_MS)
    expect(a).toHaveBeenCalledTimes(1)
    expect(b).not.toHaveBeenCalled()
  })

  it('等着的时候又切了一下：顺延到新的半秒', () => {
    const s = new Settle(), f = vi.fn()
    s.noteSwitch(); s.whenSettled('a', f)
    vi.advanceTimersByTime(400)
    s.noteSwitch()
    vi.advanceTimersByTime(400)
    expect(f).not.toHaveBeenCalled()
    vi.advanceTimersByTime(100)
    expect(f).toHaveBeenCalledTimes(1)
  })
})
