import { describe, expect, it } from 'vitest'
import type { Bar } from '../src/chart/calc'
import * as M from '../src/replay/model'

const H = 36e5, Q = 9e5
const NOW = Date.UTC(2026, 9, 7, 4, 7, 30)   // 2026-10-07 12:07:30 上海
/** 周期 ms 的一串首尾相接的 K 线：开盘从 from 起，共 n 根 */
const series = (from: number, ms: number, n: number): Bar[] =>
  Array.from({ length: n }, (_, i) => ({ t: from + i * ms, o: 100 + i, h: 101 + i, l: 99 + i, c: 100.5 + i, v: 1 }) as Bar)

describe('回放 · K 线边界', () => {
  it('分钟 / 小时周期按周期长度取整', () => {
    expect(M.barOpen(NOW, '15m')).toBe(Date.UTC(2026, 9, 7, 4, 0))
    expect(M.barClose(Date.UTC(2026, 9, 7, 4, 0), '15m')).toBe(Date.UTC(2026, 9, 7, 4, 15))
    expect(M.barOpen(NOW, '4h')).toBe(Date.UTC(2026, 9, 7, 4, 0))
    expect(M.barOpen(NOW, '1d')).toBe(Date.UTC(2026, 9, 7))
  })
  it('周线从周一 00:00 UTC 开始', () => {
    // 2026-10-07 是周三，那一周从 10-05 周一开始
    expect(M.barOpen(NOW, '1w')).toBe(Date.UTC(2026, 9, 5))
    expect(new Date(M.barOpen(NOW, '1w')).getUTCDay()).toBe(1)
    expect(M.barClose(Date.UTC(2026, 9, 5), '1w')).toBe(Date.UTC(2026, 9, 12))
  })
  it('月线按 UTC 自然月，收线是下个月 1 号（不是固定 30 天）', () => {
    expect(M.barOpen(Date.UTC(2026, 1, 20), '1M')).toBe(Date.UTC(2026, 1, 1))
    expect(M.barClose(Date.UTC(2026, 1, 1), '1M')).toBe(Date.UTC(2026, 2, 1))
    expect(M.barClose(Date.UTC(2026, 11, 1), '1M')).toBe(Date.UTC(2027, 0, 1))
  })
})

describe('回放 · 定起点', () => {
  it('点中的那一根算可见：回放钟 = 它的收线时刻', () => {
    const t = Date.UTC(2026, 9, 4, 13, 30)   // 一根 15m 的开盘
    expect(M.clockAtStart(t, '15m')).toBe(t + Q)
    // 点在一根中间也一样落到这一根
    expect(M.clockAtStart(t + 5 * 60e3, '15m')).toBe(t + Q)
  })
  it('可见根数：收线时刻 ≤ 回放钟的才算', () => {
    const from = Date.UTC(2026, 9, 1), bars = series(from, Q, 100)
    expect(M.visibleCount(bars, from + 10 * Q, '15m')).toBe(10)
    expect(M.visibleCount(bars, from + 10 * Q + 1, '15m')).toBe(10)   // 第 11 根还没走完
    expect(M.visibleCount(bars, from, '15m')).toBe(0)
    expect(M.visibleCount(bars, from + 1000 * Q, '15m')).toBe(100)
    expect(M.visibleCount(bars, from + 50 * Q, '15m', 20)).toBe(20)   // 只数前 len 根
  })
  it('手里的数据够用：切成「历史 + 未来」，正在走的那根不进未来，切出来的是拷贝', () => {
    const end = M.barOpen(NOW, '15m'), n = 1500
    const bars = series(end - (n - 1) * Q, Q, n)          // 最后一根是正在走的
    const clock = M.clockAtStart(NOW - 3 * 864e5, '15m')
    const cut = M.splitAt(bars, clock, '15m', NOW)!
    expect(cut).not.toBeNull()
    expect(cut.hist[cut.hist.length - 1].t + Q).toBe(clock)
    expect(cut.future[0].t).toBe(clock)
    expect(cut.future[cut.future.length - 1].t).toBe(end - Q)
    expect(cut.hist.length + cut.future.length).toBe(n - 1)
    cut.hist[0].c = -1
    expect(bars[0].c).not.toBe(-1)
  })
  it('起点左边不到 300 根、或起点在手里最后一根之后：不切，去取', () => {
    const end = M.barOpen(NOW, '15m'), bars = series(end - 999 * Q, Q, 1000)
    expect(M.splitAt(bars, bars[250].t + Q, '15m', NOW)).toBeNull()
    expect(M.splitAt(bars, bars[299].t + Q, '15m', NOW)).not.toBeNull()
    expect(M.splitAt(bars, end + Q, '15m', NOW)).toBeNull()
  })
})

describe('回放 · 预取窗口', () => {
  it('历史一页取到回放钟为止，未来从下一根起取 600 根，最远到最后一根走完的', () => {
    const clock = Date.UTC(2026, 9, 4, 13, 45)
    const p = M.fetchPlan(clock, '15m', NOW)
    expect(p.histEnd).toBe(clock)
    expect(p.histLimit).toBe(1500)
    expect(p.futureFrom).toBe(clock)
    expect(p.futureLimit).toBe(600)
    expect(p.stop).toBe(Date.UTC(2026, 9, 7, 4, 0))
  })
  it('切到大周期时回放钟落在一根中间：历史只取到那一根之前（不把半根未来带进来）', () => {
    const clock = Date.UTC(2026, 9, 4, 13, 45)
    const p = M.fetchPlan(clock, '1h', NOW)
    expect(p.histEnd).toBe(Date.UTC(2026, 9, 4, 13, 0))
    expect(p.futureFrom).toBe(Date.UTC(2026, 9, 4, 13, 0))
  })
  it('没播的剩不到 200 根才补，补到最新就不再补', () => {
    const last = Date.UTC(2026, 9, 5)
    expect(M.needRefill(200, last, '15m', NOW)).toBe(false)
    expect(M.needRefill(199, last, '15m', NOW)).toBe(true)
    expect(M.needRefill(0, M.barOpen(NOW, '15m') - Q, '15m', NOW)).toBe(false)
    expect(M.refillFrom(last, '15m')).toBe(last + Q)
  })
  it('取回来的一页只留走完的整根', () => {
    const end = M.barOpen(NOW, '15m'), bars = series(end - 4 * Q, Q, 5)
    expect(M.completed(bars, '15m', NOW).map(b => b.t)).toEqual([end - 4 * Q, end - 3 * Q, end - 2 * Q, end - Q])
  })
})

describe('回放 · 速度与进度线', () => {
  it('1× 每秒一根，16× 每秒 16 根', () => {
    expect(M.REPLAY_SPEEDS).toEqual([1, 2, 4, 8, 16])
    expect(M.speedDelay(1)).toBe(1000)
    expect(M.speedDelay(4)).toBe(250)
    expect(M.speedDelay(16)).toBe(62.5)
    expect(M.speedDelay(0)).toBe(1000)
  })
  it('进度线位置 ↔ 回放钟：两端夹住，中间落到整根上', () => {
    const start = Date.UTC(2026, 9, 4, 14), stop = Date.UTC(2026, 9, 7, 4)
    expect(M.trackPos(start, start, stop)).toBe(0)
    expect(M.trackPos(stop, start, stop)).toBe(1)
    expect(M.trackPos(start - H, start, stop)).toBe(0)
    expect(M.clockAtPos(0, start, stop, '15m')).toBe(start)
    expect(M.clockAtPos(1, start, stop, '15m')).toBe(stop)
    expect(M.clockAtPos(-3, start, stop, '15m')).toBe(start)
    const mid = M.clockAtPos(0.5, start, stop, '15m')
    expect(mid % Q).toBe(0)
    expect(Math.abs(M.trackPos(mid, start, stop) - 0.5)).toBeLessThan(Q / (stop - start))
    expect(M.clockAtPos(0.5, start, stop, '1h') % H).toBe(0)
  })
})

describe('回放 · 切周期重新定位', () => {
  it('15m 播到 13:45 切 1h：图上留到 12:00 那根（13:00 那根还没走完），切回 15m 回到原处', () => {
    const clock = Date.UTC(2026, 9, 4, 13, 45)
    const h1 = series(Date.UTC(2026, 9, 1), H, 120)
    const n = M.visibleCount(h1, clock, '1h')
    expect(h1[n - 1].t).toBe(Date.UTC(2026, 9, 4, 12))
    expect(M.relocate(clock, '1h')).toBe(Date.UTC(2026, 9, 4, 13))
    const q15 = series(Date.UTC(2026, 9, 1), Q, 480)
    expect(q15[M.visibleCount(q15, clock, '15m') - 1].t).toBe(Date.UTC(2026, 9, 4, 13, 30))
  })
  it('切到日线 / 周线也按同一时刻数可见', () => {
    const clock = Date.UTC(2026, 9, 7, 3)
    expect(M.relocate(clock, '1d')).toBe(Date.UTC(2026, 9, 7))
    expect(M.relocate(clock, '1w')).toBe(Date.UTC(2026, 9, 5))
  })
  it('秒级周期不能回放', () => {
    expect(M.canReplay('1s')).toBe(false)
    expect(M.canReplay('15s')).toBe(false)
    expect(M.canReplay('1m')).toBe(true)
    expect(M.canReplay('7m')).toBe(true)
    expect(M.canReplay('1M')).toBe(true)
  })
})

describe('回放 · 头部报价', () => {
  it('当前那根的收盘，对比 24 小时前那一刻的收盘', () => {
    const bars = series(Date.UTC(2026, 9, 1), H, 100)
    const q = M.quoteAt(bars, 50, '1h')!
    expect(q.price).toBe(bars[49].c)
    expect(q.t).toBe(bars[49].t)
    // 第 50 根收线时刻往前 24h，最后一根走完的是第 26 根（下标 25）
    expect(q.chg).toBeCloseTo(bars[49].c - bars[25].c)
    expect(q.pct).toBeCloseTo((bars[49].c - bars[25].c) / bars[25].c * 100)
    expect(M.quoteAt(bars, 0, '1h')).toBeNull()
    // 不够 24 小时：对比第一根的开盘
    expect(M.quoteAt(bars, 3, '1h')!.chg).toBeCloseTo(bars[2].c - bars[0].o)
  })
})

describe('回放 · 起点时间输入（上海时间）', () => {
  it('常见写法都认', () => {
    const want = Date.UTC(2026, 9, 4, 13, 30)    // 上海 21:30
    expect(M.parseShTime('2026-10-04 21:30', NOW)).toBe(want)
    expect(M.parseShTime('2026/10/4 21:30', NOW)).toBe(want)
    expect(M.parseShTime('2026.10.04 21:30', NOW)).toBe(want)
    expect(M.parseShTime('2026-10-04T21:30', NOW)).toBe(want)
    expect(M.parseShTime('2026年10月4日 21时30分', NOW)).toBe(want)
    expect(M.parseShTime(' 10-04 21:30 ', NOW)).toBe(want)
    expect(M.parseShTime('2026-10-04', NOW)).toBe(Date.UTC(2026, 9, 3, 16))
    expect(M.parseShTime('2026-10-04 9：05', NOW)).toBe(Date.UTC(2026, 9, 4, 1, 5))
  })
  it('不像时间的、日期不存在的不认', () => {
    expect(M.parseShTime('', NOW)).toBeNull()
    expect(M.parseShTime('昨天', NOW)).toBeNull()
    expect(M.parseShTime('2026-02-30', NOW)).toBeNull()
    expect(M.parseShTime('2026-13-01', NOW)).toBeNull()
    expect(M.parseShTime('2026-10-04 24:00', NOW)).toBeNull()
  })
  it('格式化与解析互逆', () => {
    const t = Date.UTC(2026, 9, 4, 13, 30)
    expect(M.fmtShTime(t)).toBe('2026-10-04 21:30')
    expect(M.parseShTime(M.fmtShTime(t), NOW)).toBe(t)
  })
})
