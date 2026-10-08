/* 2026-10-08 · PC 网页持仓量副图不跟 K 线延长
 *   根因：attachOI 只在装载时取一次整段，推送来的 K 线不带 oi，新开的每一根都是空的，线停在装载那一刻；
 *        1m / 3m、周线以上根本不取（币安 period 只有 5m–1d）。
 *   改法：露着副图的格子每分钟拿最近两桶补尾巴（pages/chart.ts refreshOITail，limit 只要几个点）；新开一根先顺延上一根的值；
 *        细周期铺 5 分钟桶、粗周期取那根里最后一个日点（rest.ts attachOI / oiPeriod）。
 * 2026-10-08 · 1 时线之上一翻页持仓量就空：币安 openInterestHist 只留 30 天、原来只打一次 500 个点。
 *   改法：30 天内向左翻页翻到要的那一桶；更早的问自家归档 /oi/v1/metrics/{symbol}/range（张数 × 收盘价换成美元）。 */
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { Bar } from '../src/chart/calc'
import { OI_EPOCH, OI_LIVE_MS, attachOI, oiPeriod } from '../src/market/rest'
import { resetLimits } from '../src/market/limit'
import { TVChart } from '../src/chart/chart'

const M = 60e3, H = 36e5, D = 864e5
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
    vi.useFakeTimers(); vi.setSystemTime(t0 + D)
    const bars = mk(t0 + 3 * M, 8, M)                                // 桶 0 的后两根 + 桶 1 的五根 + 桶 2 的第一根
    const spy = vi.fn(async (_u: string) => rows([[t0, 100], [t0 + 5 * M, 200], [t0 + 10 * M, 300]]))
    vi.stubGlobal('fetch', spy)
    expect(await attachOI('BTCUSDT', '1m', bars)).toBe(true)
    const u = String(spy.mock.calls[0][0])
    expect(u).toContain('period=5m'); expect(u).toContain('limit=500'); expect(u).toContain(`endTime=${bars[bars.length - 1].t + 1}`)
    expect(bars.map(b => b.oi)).toEqual([100, 100, 200, 200, 200, 200, 200, 300])
  })

  it('1w：取那根里（到下一根开盘为止）最后一个日点；对不齐的留空；limit 可以只要几个点', async () => {
    const w0 = 1_700_000_000_000 - (1_700_000_000_000 % (7 * D))
    vi.useFakeTimers(); vi.setSystemTime(w0 + 25 * D)
    const bars = mk(w0, 3, 7 * D)
    const spy = vi.fn(async (_u: string) => rows([[w0 + 7 * D + 2 * D, 11], [w0 + 7 * D + 6 * D, 12], [w0 + 14 * D, 21]]))
    vi.stubGlobal('fetch', spy)
    expect(await attachOI('BTCUSDT', '1w', bars, undefined, 15)).toBe(true)
    const u = String(spy.mock.calls[0][0])
    expect(u).toContain('period=1d'); expect(u).toContain('limit=15'); expect(u).toContain(`endTime=${Math.min(w0 + 21 * D, Date.now())}`)
    expect(bars.map(b => b.oi)).toEqual([undefined, 12, 21])
    expect(spy).toHaveBeenCalledTimes(1)                               // 补尾巴：不翻页、不问归档
  })

  it('30 天内一页不够就向左翻页，翻到最早一根要的桶头为止；翻到的点都落到根上', async () => {
    const t0 = 1_700_000_000_000 - (1_700_000_000_000 % H)
    vi.useFakeTimers(); vi.setSystemTime(t0 + 1300 * H)
    const bars = mk(t0, 1200, H)                                        // 50 天 → 最早 20 天的根走归档，近 30 天 ≈ 708 个点 = 两页
    const pageOf = (end: number) => Array.from({ length: 500 }, (_, i) => [end - 1 - ((end - 1) % H) - (499 - i) * H, 1] as [number, number])
    const spy = vi.fn(async (u: string) => {
      if (u.includes('/oi/v1/metrics/')) return new Response('[]', { status: 200 })
      const end = +new URL(u).searchParams.get('endTime')!
      return rows(pageOf(end).map(([t]) => [t, t === t0 + 600 * H ? 600 : 1]))
    })
    vi.stubGlobal('fetch', spy)
    expect(await attachOI('BTCUSDT', '1h', bars)).toBe(true)
    const bn = spy.mock.calls.map(c => String(c[0])).filter(u => u.includes('openInterestHist'))
    expect(bn.length).toBe(2)
    expect(bn[0]).toContain(`endTime=${t0 + 1199 * H + 1}`)
    expect(+new URL(bn[1]).searchParams.get('endTime')!).toBeLessThan(+new URL(bn[0]).searchParams.get('endTime')! - 499 * H)
    expect(bars[600].oi).toBe(600)
    expect(bars[1199].oi).toBe(1)
  })

  it('30 天之前的根问自家归档：张数 × 这根收盘价换成美元；归档从 2020-09-01 起、再早不问', async () => {
    const t0 = 1_700_000_000_000 - (1_700_000_000_000 % D)
    const now = t0 + 100 * D
    vi.useFakeTimers(); vi.setSystemTime(now)
    const bars = mk(t0, 100, D); bars[3].c = 2
    const spy = vi.fn(async (u: string) => {
      if (u.includes('/oi/v1/metrics/BTCUSDT/range')) return new Response(JSON.stringify([[t0 + 3 * D, 50], [t0 + 69 * D, 70]]), { status: 200 })
      return rows([[t0 + 99 * D, 7]])
    })
    vi.stubGlobal('fetch', spy)
    expect(await attachOI('BTCUSDT', '1d', bars)).toBe(true)
    const ar = spy.mock.calls.map(c => String(c[0])).find(u => u.includes('/range'))!
    const q = new URL(ar).searchParams
    expect(q.get('interval')).toBe('1d'); expect(+q.get('from')!).toBe(t0)
    const split = bars.findIndex(b => b.t >= now - OI_LIVE_MS)
    expect(+q.get('to')!).toBe(bars[split - 1].t + D)
    expect(bars[3].oi).toBe(100)                                        // 50 张 × 收盘 2
    expect(bars[69].oi).toBe(70 * 1.5)
    expect(bars[99].oi).toBe(7)                                         // 币安那段是美元原值
    expect(spy).toHaveBeenCalledTimes(2)

    // 2020-09-01 之前的根没有归档可问
    vi.setSystemTime(OI_EPOCH + 40 * D)
    const early = mk(OI_EPOCH - 5 * D, 3, D)
    spy.mockClear()
    expect(await attachOI('BTCUSDT', '1d', early)).toBe(true)
    expect(spy).not.toHaveBeenCalled()
  })

  it('归档没答：币安那段照样落到根上，但返回 false 让下次再取', async () => {
    const t0 = 1_700_000_000_000 - (1_700_000_000_000 % D)
    vi.useFakeTimers(); vi.setSystemTime(t0 + 60 * D)
    const bars = mk(t0, 60, D)
    vi.stubGlobal('fetch', vi.fn(async (u: string) => u.includes('/range') ? new Response('{"error":"archive unavailable"}', { status: 502 }) : rows([[t0 + 59 * D, 9]])))
    expect(await attachOI('BTCUSDT', '1d', bars)).toBe(false)
    expect(bars[59].oi).toBe(9)
    expect(bars[0].oi).toBeUndefined()
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
