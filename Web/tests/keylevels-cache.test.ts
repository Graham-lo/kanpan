import { afterEach, describe, expect, it, vi } from 'vitest'

const calls: string[] = []
vi.mock('../src/market/rest', () => ({
  klines: vi.fn(async (sym: string, iv: string, endTime?: number, limit = 1500) => {
    calls.push(`${sym}:${iv}`)
    const DAY = 864e5, now = Date.now(), d0 = now - (now % DAY)
    if (iv === '1d') return { ok: true, bars: Array.from({ length: 16 }, (_, k) => ({ t: d0 - (15 - k) * DAY, o: 100, h: 110 + k, l: 90 - k, c: 101, v: 1000 })) }
    // 其余周期：到 endTime（没给就是现在）为止的 limit 根
    const ms = iv === '5m' ? 3e5 : iv === '15m' ? 9e5 : 36e5
    const end = Math.floor((endTime ?? now) / ms) * ms
    return { ok: true, bars: Array.from({ length: limit }, (_, k) => ({ t: end - (limit - k) * ms, o: 100, h: 101, l: 99, c: 100 + (k % 7) / 10, v: 500 + k })) }
  }),
}))

const { keyLevelsOf, resetKeyLevels } = await import('../src/chart/keyLevels')

afterEach(() => { resetKeyLevels(); calls.length = 0 })

const chartOf = (symbol: string) => ({ meta: { symbol }, iv: 36e5, bars: [], dead: false, dirty: false }) as never
const flush = () => new Promise(r => setTimeout(r, 0))

describe('关键价位缓存（2026-09-29 A 路压测：十六图每格一只时反复要数）', () => {
  it('十六图每格一只、连画几十帧：每只只要一次日线、一次 5 分钟线', async () => {
    const syms = Array.from({ length: 16 }, (_, k) => `S${k}USDT`)
    const charts = syms.map(chartOf)
    for (let frame = 0; frame < 30; frame++) {
      for (const ch of charts) keyLevelsOf(ch)
      await flush()
    }
    expect(calls.length).toBe(32)
    expect(new Set(calls).size).toBe(32)
  })
})

describe('累计量差的逐笔账（同上：九图各开一只时互相挤掉）', () => {
  it('十六只轮着取：每只拿到的一直是同一份', async () => {
    const { flowOf, resetFlows } = await import('../src/chart/tradeFlow')
    resetFlows()
    const syms = Array.from({ length: 16 }, (_, k) => `T${k}USDT`)
    const first = syms.map(s => flowOf(s))
    for (let round = 0; round < 5; round++) syms.forEach((s, k) => expect(flowOf(s)).toBe(first[k]))
    resetFlows()
  })
})

describe('成交量分布细 K 线缓存（同上：多格各开一只 4 小时时互相挤掉）', () => {
  it('八格各一只、4 小时开成交量分布：每只要够一次就不再要', async () => {
    const { fineSplit, resetFine } = await import('../src/chart/fineVolume')
    resetFine()
    const H4 = 4 * 36e5, now = Date.now(), t0 = now - (now % H4) - 60 * H4
    const bars = Array.from({ length: 61 }, (_, k) => ({ t: t0 + k * H4, o: 100, h: 101, l: 99, c: 100, v: 1 }))
    const syms = Array.from({ length: 8 }, (_, k) => `F${k}USDT`)
    for (let frame = 0; frame < 12; frame++) {
      for (const s of syms) fineSplit(s, H4, bars, 0, 60, () => {}, now)
      await new Promise(r => setTimeout(r, 300))
    }
    const per = new Map<string, number>()
    for (const c of calls) if (c.endsWith(':15m')) per.set(c, (per.get(c) || 0) + 1)
    expect(per.size).toBe(8)
    expect(Math.max(...per.values())).toBeLessThanOrEqual(1)
    resetFine()
  })
})
