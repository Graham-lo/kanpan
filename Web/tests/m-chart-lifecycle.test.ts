// 行情页引擎的生命周期：心跳随页面藏 / 露停开（ChartBeat）、换品种时留旧图只留到取数有结果（holdsPrevious）。
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { AWAY_RESYNC_MS, ChartBeat } from '../src/m/chart/beat'

describe('ChartBeat · 行情页藏起来时心跳停', () => {
  let now = 1_700_000_000_000
  let ticks = 0, stops = 0, returns = 0
  const hooks = () => ({
    tick: () => { ticks++ },
    stopped: () => { stops++ },
    onReturn: () => { returns++ },
    now: () => now,
  })
  const advance = (ms: number) => { now += ms; vi.advanceTimersByTime(ms) }
  beforeEach(() => { vi.useFakeTimers(); ticks = 0; stops = 0; returns = 0 })
  afterEach(() => { vi.useRealTimers() })

  it('露着：建好立刻补一拍，之后每秒一拍', () => {
    const b = new ChartBeat(hooks(), false)
    expect(ticks).toBe(1)
    advance(3000)
    expect(ticks).toBe(4)
    b.dispose()
  })

  it('pause 之后不再跳（原来只在 document.hidden 时停，切到自选页仍每秒 refresh + 覆盖层重算）', () => {
    const b = new ChartBeat(hooks(), false)
    b.pause()
    expect(b.running).toBe(false)
    expect(stops).toBe(1)
    const before = ticks
    advance(60_000)
    expect(ticks).toBe(before)
    b.dispose()
  })

  it('建的时候就 pause（壳在后台先建页）：一拍都不跳', () => {
    const b = new ChartBeat(hooks(), false)
    b.pause()
    ticks = 0
    advance(10_000)
    expect(ticks).toBe(0)
    b.dispose()
  })

  it('resume 立刻补一拍；离开不到 5 秒不重拉，超过 5 秒补缺口', () => {
    const b = new ChartBeat(hooks(), false)
    b.pause(); ticks = 0
    advance(2000)
    b.resume()
    expect(ticks).toBe(1)
    expect(returns).toBe(0)
    b.pause()
    advance(AWAY_RESYNC_MS + 1)
    b.resume()
    expect(ticks).toBe(2)
    expect(returns).toBe(1)
    advance(1000)
    expect(ticks).toBe(3)
    b.dispose()
  })

  it('pause 与 document.hidden 叠着：两样都放开才跳；离开时长从最早停的那一刻算', () => {
    const b = new ChartBeat(hooks(), false)
    b.pause(); ticks = 0
    advance(1000)
    b.setHidden(true)
    advance(AWAY_RESYNC_MS)
    b.setHidden(false) // 页面仍 pause 着
    expect(ticks).toBe(0)
    expect(b.running).toBe(false)
    b.resume()
    expect(ticks).toBe(1)
    expect(returns).toBe(1)
    b.dispose()
  })

  it('重复 pause / resume 不叠定时器', () => {
    const b = new ChartBeat(hooks(), false)
    b.resume(); b.resume()
    ticks = 0
    advance(1000)
    expect(ticks).toBe(1)
    b.pause(); b.pause()
    expect(stops).toBe(1)
    b.dispose()
  })

  it('离线图（截图卡）从不跳；dispose 之后 resume 也不复活', () => {
    const off = new ChartBeat(hooks(), false, false)
    off.resume()
    advance(5000)
    expect(ticks).toBe(0)
    const b = new ChartBeat(hooks(), false)
    b.dispose(); ticks = 0
    b.resume()
    advance(5000)
    expect(ticks).toBe(0)
  })
})
