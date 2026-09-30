/* 行情推送与 K 线并行建连：K 线在路上时攒下的推送怎么并回去（chart/pushBuffer.ts） */
import { describe, expect, it } from 'vitest'
import { PushBuffer, PUSH_CAP, alignPushes, pushKey } from '../src/chart/pushBuffer'
import type { Bar } from '../src/chart/calc'

const H = 3600e3
const bar = (t: number, c: number, extra: Partial<Bar> = {}): Bar => ({ t, o: c, h: c, l: c, c, v: 1, ...extra })

describe('alignPushes：比最后一根早的丢、同一根的并、晚的接上', () => {
  it('早于最后一根的推送丢掉', () => {
    const bars = [bar(0, 1), bar(H, 2)]
    alignPushes(bars, [bar(0, 99)])
    expect(bars.map(b => b.c)).toEqual([1, 2])
  })
  it('等于最后一根：并进去（开高低收量盖掉，持仓量留着）', () => {
    const bars = [bar(0, 1), bar(H, 2, { oi: 5e6 })]
    alignPushes(bars, [bar(H, 3)])
    expect(bars).toHaveLength(2)
    expect(bars[1].c).toBe(3)
    expect(bars[1].oi).toBe(5e6)
  })
  it('晚于最后一根：接在后面，乱序来的也按时间排', () => {
    const bars = [bar(0, 1), bar(H, 2)]
    alignPushes(bars, [bar(3 * H, 5), bar(H, 3), bar(2 * H, 4)])
    expect(bars.map(b => [b.t / H, b.c])).toEqual([[0, 1], [1, 3], [2, 4], [3, 5]])
  })
  it('没有 K 线就不补（和实时 updateBar 的口径一样）', () => {
    expect(alignPushes([], [bar(0, 1)])).toEqual([])
  })
})

describe('PushBuffer：有人等才攒、换品种作废、取完撒手不漏', () => {
  it('没人等的 key 不攒', () => {
    const p = new PushBuffer()
    expect(p.offer(pushKey('BTCUSDT', '1h'), bar(0, 1))).toBe(false)
    expect(p.size()).toBe(0)
  })
  it('同一根只留最新一版，take 只给 ≥ 起点的并按时间排', () => {
    const p = new PushBuffer(), k = pushKey('btcusdt', '1h')
    p.open(k)
    p.offer(k, bar(H, 2)); p.offer(k, bar(0, 1)); p.offer(k, bar(H, 3))
    expect(p.take(k, H).map(b => b.c)).toEqual([3])
    expect(p.take(k, 0).map(b => b.t)).toEqual([0, H])
  })
  it('超过上限丢最早的', () => {
    const p = new PushBuffer(4), k = 'X|1m'
    p.open(k)
    for (let i = 0; i < 10; i++) p.offer(k, bar(i * 60e3, i))
    expect(p.take(k, 0).map(b => b.c)).toEqual([6, 7, 8, 9])
    expect(PUSH_CAP).toBeGreaterThanOrEqual(16)
  })
  it('切品种：旧 key 撒手后缓冲作废，旧品种再推来的不攒', () => {
    const p = new PushBuffer(), a = pushKey('BTCUSDT', '1h'), b = pushKey('ETHUSDT', '1h')
    p.open(a); p.offer(a, bar(H, 1))
    p.release(a); p.open(b)
    expect(p.offer(a, bar(2 * H, 2))).toBe(false)
    expect(p.take(a, 0)).toEqual([])
    expect(p.holding(b)).toBe(true)
    // 再切回来是一份新的，不带上次攒的
    p.release(b); p.open(a)
    expect(p.take(a, 0)).toEqual([])
  })
  it('两格同品种同周期共用一份：一格取完撒手，另一格还能取；都撒手后不留 key（取失败也一样撒手）', () => {
    const p = new PushBuffer(), k = pushKey('BTCUSDT', '1h')
    p.open(k); p.open(k)
    p.offer(k, bar(H, 7))
    expect(p.take(k, 0)).toHaveLength(1)
    p.release(k)
    expect(p.take(k, 0)).toHaveLength(1)
    p.release(k)
    expect(p.keys).toBe(0)
    p.release(k)   // 多撒一次不出错
    expect(p.keys).toBe(0)
  })
})
