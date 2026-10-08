/* 2026-10-08 · PC 网页持仓量副图不跟 K 线延长
 *   根因：attachOI 只在装载时取一次整段，推送来的 K 线不带 oi，新开的每一根都是空的，线停在装载那一刻；
 *        1m / 3m、周线以上根本不取（币安 period 只有 5m–1d）。
 *   改法：露着副图的格子每分钟拿最近两桶补尾巴（pages/chart.ts refreshOITail，limit 只要几个点）；新开一根先顺延上一根的值；
 *        细周期铺 5 分钟桶、粗周期取那根里最后一个日点（rest.ts attachOI / oiPeriod）。 */
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { Bar } from '../src/chart/calc'
import { attachOI, oiPeriod } from '../src/market/rest'
import { resetLimits } from '../src/market/limit'
import { TVChart } from '../src/chart/chart'

const M = 60e3, D = 864e5
const mk = (t0: number, n: number, step: number): Bar[] => Array.from({ length: n }, (_, i) => ({ t: t0 + i * step, o: 1, h: 2, l: 0.5, c: 1.5, v: 10 }))
const rows = (pts: [number, number][]) => new Response(JSON.stringify(pts.map(([timestamp, v]) => ({ timestamp, sumOpenInterestValue: String(v) }))), { status: 200 })

afterEach(() => { resetLimits(); vi.useRealTimers(); vi.unstubAllGlobals() })

describe('attachOI：周期对桶（rest.ts）', () => {
  it('oiPeriod：币安有的原样；更细退 5m；更粗退 1d；秒级 / 自定义没有', () => {
    expect(oiPeriod('15m')).toBe('15m'); expect(oiPeriod('1d')).toBe('1d')
    expect(oiPeriod('1m')).toBe('5m'); expect(oiPeriod('3m')).toBe('5m')
    expect(oiPeriod('1w')).toBe('1d'); expect(oiPeriod('1M')).toBe('1d')
    expect(oiPeriod('5s')).toBeNull(); expect(oiPeriod('7m')).toBeNull()
  })

  it('1m：5 分钟那一桶的值铺到桶里每根，endTime 是最后一根的开盘时刻', async () => {
    const t0 = 1_700_000_000_000 - (1_700_000_000_000 % (5 * M)) // 桶头
    const bars = mk(t0 + 3 * M, 8, M)                                // 桶 0 的后两根 + 桶 1 的五根 + 桶 2 的第一根
    const spy = vi.fn(async (_u: string) => rows([[t0, 100], [t0 + 5 * M, 200], [t0 + 10 * M, 300]]))
    vi.stubGlobal('fetch', spy)
    expect(await attachOI('BTCUSDT', '1m', bars)).toBe(true)
    const u = String(spy.mock.calls[0][0])
    expect(u).toContain('period=5m'); expect(u).toContain('limit=500'); expect(u).toContain(`endTime=${bars[bars.length - 1].t + 1}`)
    expect(bars.map(b => b.oi)).toEqual([100, 100, 200, 200, 200, 200, 200, 300])
  })

  it('1w：取那根里（到下一根开盘为止）最后一个日点；对不齐的留空；limit 可以只要几个点', async () => {
    vi.useFakeTimers(); vi.setSystemTime(1_700_000_000_000 + 30 * D)
    const w0 = 1_700_000_000_000 - (1_700_000_000_000 % (7 * D))
    const bars = mk(w0, 3, 7 * D)
    const spy = vi.fn(async (_u: string) => rows([[w0 + 7 * D + 2 * D, 11], [w0 + 7 * D + 6 * D, 12], [w0 + 14 * D, 21]]))
    vi.stubGlobal('fetch', spy)
    expect(await attachOI('BTCUSDT', '1w', bars, undefined, 15)).toBe(true)
    const u = String(spy.mock.calls[0][0])
    expect(u).toContain('period=1d'); expect(u).toContain('limit=15'); expect(u).toContain(`endTime=${Math.min(w0 + 21 * D, Date.now())}`)
    expect(bars.map(b => b.oi)).toEqual([undefined, 12, 21])
  })
})

describe('updateBar：推送不带持仓量时不丢、新开一根先顺延（chart.ts）', () => {
  function chart(bars: Bar[]) {
    const ch = Object.create(TVChart.prototype) as TVChart & Record<string, unknown>
    Object.assign(ch, { bars, rightBar: bars.length - 1, drag: null, dirty: false, cross: null, legendDirty: false, recalcTail: () => {} })
    return ch
  }
  it('同一根：推送的字段盖上去，已有的 oi 留着；新一根没有 oi 就先用上一根的', () => {
    const bars = mk(0, 3, M); bars[2].oi = 777
    const ch = chart(bars)
    ch.updateBar({ t: 2 * M, o: 1, h: 3, l: 0.5, c: 2.5, v: 20 })
    expect(bars[2]).toMatchObject({ h: 3, c: 2.5, v: 20, oi: 777 })
    ch.updateBar({ t: 3 * M, o: 2.5, h: 2.6, l: 2.4, c: 2.5, v: 1 })
    expect(bars[3].oi).toBe(777)
    // 尾巴补取拿到真值后盖掉顺延的
    ch.updateBar({ t: 3 * M, o: 2.5, h: 2.6, l: 2.4, c: 2.5, v: 2, oi: 800 })
    expect(bars[3].oi).toBe(800)
  })
  it('上一根本来就没有（秒级 / 不支持的品种）：新一根也不造一个出来', () => {
    const bars = mk(0, 2, M)
    const ch = chart(bars)
    ch.updateBar({ t: 2 * M, o: 1, h: 2, l: 0.5, c: 1.5, v: 1 })
    expect(bars[2].oi).toBeUndefined()
  })
})
