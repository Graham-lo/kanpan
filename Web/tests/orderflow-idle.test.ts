/* Web 深度审查 C 线 2026-10-05 · 订单流数据层在标签页藏到后台后也要收掉
 * （PC orderflow/index.ts 原来藏着时一拍都不跑、永远不关；手机网页 createPagePort / createOrderFlowPort 只管页内切走） */
import { afterEach, describe, expect, it, vi } from 'vitest'
import { IdleGate, IDLE_STOP_MS, stopWhenHiddenLong } from '../src/orderflow/idle'

function fakeDocument() {
  const d = Object.assign(new EventTarget(), { visibilityState: 'visible' as 'visible' | 'hidden', hidden: false })
  const set = (v: 'visible' | 'hidden') => { d.visibilityState = v; d.hidden = v === 'hidden'; d.dispatchEvent(new Event('visibilitychange')) }
  return { d, set }
}

afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); vi.restoreAllMocks(); vi.resetModules() })

describe('IdleGate：离开（换页或藏到后台）一分钟就不要数据层', () => {
  it('在场一直要；离开 59 秒还要、60 秒不要；回来立刻又要、重新计时', () => {
    const g = new IdleGate()
    expect(g.want(false, 0)).toBe(true)
    expect(g.want(true, 1000)).toBe(true)
    expect(g.want(true, 1000 + IDLE_STOP_MS - 1)).toBe(true)
    expect(g.want(true, 1000 + IDLE_STOP_MS)).toBe(false)
    expect(g.want(false, 200_000)).toBe(true)
    expect(g.want(true, 200_001)).toBe(true)
  })
})

describe('stopWhenHiddenLong', () => {
  it('藏起来不到一分钟回来：不停不重开；超过一分钟：停一次，回来重开一次', () => {
    vi.useFakeTimers()
    const { d, set } = fakeDocument()
    vi.stubGlobal('document', d)
    const stop = vi.fn(), back = vi.fn()
    const off = stopWhenHiddenLong(stop, back)
    set('hidden'); vi.advanceTimersByTime(30_000); set('visible')
    vi.advanceTimersByTime(120_000)
    expect(stop).not.toHaveBeenCalled(); expect(back).not.toHaveBeenCalled()
    set('hidden'); vi.advanceTimersByTime(IDLE_STOP_MS + 10)
    expect(stop).toHaveBeenCalledTimes(1)
    set('hidden')   // 重复的 hidden 事件不再计一次
    vi.advanceTimersByTime(IDLE_STOP_MS + 10)
    expect(stop).toHaveBeenCalledTimes(1)
    set('visible')
    expect(back).toHaveBeenCalledTimes(1)
    off()
    set('hidden'); vi.advanceTimersByTime(IDLE_STOP_MS + 10)
    expect(stop).toHaveBeenCalledTimes(1)
  })
})

describe('手机网页行情页的订单流口（createPagePort）', () => {
  it('锁屏 / 切走一分钟：簿与成交的连接停掉；回到前台按原品种重开、视野照旧', async () => {
    vi.useFakeTimers()
    const { d, set } = fakeDocument()
    vi.stubGlobal('document', d)
    const { OrderFlowSource } = await import('../src/m/chart/orderflow.source')
    const start = vi.spyOn(OrderFlowSource.prototype, 'start').mockImplementation(function (this: any, sym: string) { this.symbol = sym })
    const stop = vi.spyOn(OrderFlowSource.prototype, 'stop').mockImplementation(function (this: any) { this.symbol = null })
    const vis = vi.spyOn(OrderFlowSource.prototype, 'setVisible').mockImplementation(() => {})
    const { createPagePort } = await import('../src/m/pages/chart/data')
    const port = createPagePort(() => {}, () => null)
    port.setWanted(true, 'btcusdt', '1h' as never)
    port.noteView({ from: 1000, to: 2000 } as never, { step: 60 } as never)
    expect(start).toHaveBeenCalledTimes(1)
    set('hidden'); vi.advanceTimersByTime(IDLE_STOP_MS + 10)
    expect(stop).toHaveBeenCalledTimes(1)
    port.setWanted(true, 'ETHUSDT', '1h' as never)   // 藏着时换了品种：记住，不开
    expect(start).toHaveBeenCalledTimes(1)
    set('visible')
    expect(start).toHaveBeenCalledTimes(2)
    expect(start.mock.calls[1][0]).toBe('ETHUSDT')
    port.dispose()
    vis.mockRestore()
  })

  it('页内已经 suspend（切到别的页）时回到前台：不擅自重开，等宿主 resume', async () => {
    vi.useFakeTimers()
    const { d, set } = fakeDocument()
    vi.stubGlobal('document', d)
    const { OrderFlowSource } = await import('../src/m/chart/orderflow.source')
    const start = vi.spyOn(OrderFlowSource.prototype, 'start').mockImplementation(function (this: any, sym: string) { this.symbol = sym })
    vi.spyOn(OrderFlowSource.prototype, 'stop').mockImplementation(function (this: any) { this.symbol = null })
    const { createPagePort } = await import('../src/m/pages/chart/data')
    const port = createPagePort(() => {}, () => null)
    port.setWanted(true, 'BTCUSDT', '1h' as never)
    port.suspend()
    set('hidden'); vi.advanceTimersByTime(IDLE_STOP_MS + 10); set('visible')
    expect(start).toHaveBeenCalledTimes(1)
    port.resume()
    expect(start).toHaveBeenCalledTimes(2)
    port.dispose()
  })
})

describe('默认订单流口（createOrderFlowPort）', () => {
  it('同样藏一分钟停、回来重开', async () => {
    vi.useFakeTimers()
    const { d, set } = fakeDocument()
    vi.stubGlobal('document', d)
    const mod = await import('../src/m/chart/orderflow.source')
    const start = vi.spyOn(mod.OrderFlowSource.prototype, 'start').mockImplementation(function (this: any, sym: string) { this.symbol = sym })
    const stop = vi.spyOn(mod.OrderFlowSource.prototype, 'stop').mockImplementation(function (this: any) { this.symbol = null })
    const port = mod.createOrderFlowPort(() => {})
    port.setWanted(true, 'BTCUSDT', '1h' as never)
    set('hidden'); vi.advanceTimersByTime(IDLE_STOP_MS + 10)
    expect(stop).toHaveBeenCalledTimes(1)
    set('visible')
    expect(start).toHaveBeenCalledTimes(2)
    port.dispose()
  })
})
