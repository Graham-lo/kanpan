import { describe, expect, it } from 'vitest'
import { TIME_TICK_MIN_PX, timeAtFrom, timeTicks } from '../src/chart/timeAxis'
import type { TimeTick } from '../src/chart/timeAxis'
import { sh } from '../src/util/format'

const H = 36e5, D = 864e5
const series = (t0: number, n: number, iv: number) => Array.from({ length: n }, (_, i) => t0 + i * iv)
const brief = (ts: TimeTick[]) => ts.map(t => `${t.i}:${t.label}${t.bold ? '*' : ''}`)
/** 相邻刻度的像素间距都不小于 96 × 0.8 */
const gapsOk = (ts: TimeTick[], spacing: number) => ts.every((t, k) => k === 0 || (t.i - ts[k - 1].i) * spacing >= TIME_TICK_MIN_PX * 0.8)

describe('timeAtFrom', () => {
  it('数组内取原值，两头按周期外推', () => {
    const at = timeAtFrom([100, 200, 300], 100)
    expect(at(1)).toBe(200)
    expect(at(1.4)).toBe(200)
    expect(at(-2)).toBe(-100)
    expect(at(5)).toBe(600)
    expect(timeAtFrom([], 100)(3)).toBe(0)
  })
})

describe('timeTicks · 日线（bar 的 t 是 UTC 0 点 = 上海 08:00）', () => {
  it('日线 bar 按上海日期判断，10 月 1 日那根出「10月」并加粗', () => {
    const t0 = Date.UTC(2026, 8, 20) // 09-20 周日
    expect(sh(t0).getUTCHours()).toBe(8)
    const times = series(t0, 21, D) // 09-20 … 10-10
    // 间距 40 → 96px 至少 3 根 → 步长 7 天：只标周一和月初
    const ts = timeTicks(times, 0, 20, 40, D)
    expect(brief(ts)).toEqual(['1:21', '8:28', '11:10月*', '15:5'])
    expect(gapsOk(ts, 40)).toBe(true)
  })

  it('间距不够时，加粗的月初顶掉紧挨在前面的普通刻度', () => {
    const times = series(Date.UTC(2026, 8, 20), 21, D)
    // 间距 20：09-28（周一）到 10-01 只有 60px < 76.8 → 「28」被「10月」替换
    const ts = timeTicks(times, 0, 20, 20, D)
    expect(brief(ts)).toEqual(['1:21', '11:10月*', '15:5']) // 10-05 离 10-01 有 80px，照常出
    expect(gapsOk(ts, 20)).toBe(true)
  })

  it('年初显示年份（加粗）', () => {
    const times = series(Date.UTC(2026, 11, 25), 17, D) // 12-25 … 2027-01-10
    const ts = timeTicks(times, 0, 16, 40, D)
    const jan1 = ts.find(t => t.i === 7)
    expect(jan1).toEqual({ i: 7, label: '2027', bold: true })
  })

  it('间距很小时按季度标月份，1 月显示年份', () => {
    const t0 = Date.UTC(2026, 10, 1) // 2026-11-01
    const times = series(t0, 290, D) // 到 2027-08 中
    // 间距 2 → 96px 需 48 根 → 步长 91 天 → 每 3 个月（1/4/7/10 月）
    const ts = timeTicks(times, 0, 289, 2, D)
    expect(ts.map(t => t.label)).toEqual(['2027', '4月', '7月'])
    expect(ts.map(t => t.bold)).toEqual([true, false, false])
    const jan = ts[0]
    expect(sh(times[jan.i]).getUTCMonth()).toBe(0)
    expect(sh(times[jan.i]).getUTCDate()).toBe(1)
  })
})

describe('timeTicks · 1 小时', () => {
  it('上海 00:00（UTC 16:00）那根判为换日并加粗，其余按 6 小时步长标时分', () => {
    const t0 = Date.UTC(2026, 8, 28, 10) // 上海 09-28 18:00
    const times = series(t0, 30, H)
    // 间距 20 → 96px 需 5 根 → 步长 6 小时
    const ts = timeTicks(times, 0, 29, 20, H)
    expect(brief(ts)).toEqual(['0:18:00', '6:29*', '12:06:00', '18:12:00', '24:18:00'])
    expect(times[6]).toBe(Date.UTC(2026, 8, 28, 16))
    expect(gapsOk(ts, 20)).toBe(true)
  })

  it('UTC 0 点（上海 08:00）不是换日点', () => {
    const t0 = Date.UTC(2026, 8, 28, 20) // 上海 09-29 04:00
    const times = series(t0, 12, H) // 到上海 15:00，中间经过 UTC 0 点
    const ts = timeTicks(times, 0, 11, 40, H) // 间距 40 → 3 根 → 步长 3 小时
    expect(ts.some(t => t.bold)).toBe(false)
    expect(brief(ts)).toEqual(['2:06:00', '5:09:00', '8:12:00', '11:15:00'])
  })

  it('月初那天的换日刻度显示「N月」', () => {
    const t0 = Date.UTC(2026, 8, 30, 10) // 上海 09-30 18:00
    const times = series(t0, 12, H)
    const ts = timeTicks(times, 0, 11, 20, H)
    const oct = ts.find(t => t.bold)
    expect(oct).toEqual({ i: 6, label: '10月', bold: true })
    expect(times[6]).toBe(Date.UTC(2026, 8, 30, 16)) // = 上海 10-01 00:00
  })

  it('可见区可以伸到数据右边（按周期外推）；函数形式与数组形式结果一致', () => {
    const times = series(Date.UTC(2026, 8, 28, 10), 10, H)
    const a = timeTicks(times, 0, 20, 20, H)
    const b = timeTicks(timeAtFrom(times, H), 0, 20, 20, H)
    expect(a).toEqual(b)
    expect(a.some(t => t.i >= 10)).toBe(true)
  })

  it('空数据不出刻度', () => {
    expect(timeTicks([], 0, 10, 8, H)).toEqual([])
  })
})
