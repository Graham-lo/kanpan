// 十字线读数挪进周期条那一行（2026-10-08，手机网页跟 iOS）：一行「时间 · 开 高 低 收 · 涨跌幅」，
// 放不下先收开高低、再收时间；收盘价与涨跌幅总在。移植自 Kanpan/KanpanTests/Main/CrosshairBandReadoutTests.swift。
// 负号照手机网页全站用 U+2212（iOS 那边是 ASCII 连字符）。
import { describe, expect, it } from 'vitest'
import { BarSeries } from '../src/m/chart/series'
import { crosshairBand, crosshairBandText } from '../src/m/pages/chart/logic'

// 2023-11-14 22:13:20 UTC = 2023-11-15 06:13 +08:00
const t0 = 1_700_000_000_000

function series(bars: [number, number, number, number][], interval: '1h' | '1d' = '1h'): BarSeries {
  return new BarSeries({
    symbol: 'BTCUSDT', interval, t0, step: interval === '1h' ? 3_600_000 : 86_400_000,
    open: bars.map(b => b[0]), high: bars.map(b => b[1]), low: bars.map(b => b[2]), close: bars.map(b => b[3]),
    volume: bars.map(() => 1),
  })
}
const bars: [number, number, number, number][] = [[100, 101, 99, 100], [100, 103, 99.5, 102]]

describe('十字线读数：周期条那一行', () => {
  it('三档文案：全量 → 收掉开高低 → 再收时间', () => {
    const r = crosshairBand(series(bars), 1, 1)!
    expect(r.time).toBe('11-15 07:13')
    const full = crosshairBandText(r, 'full'), close = crosshairBandText(r, 'closeOnly'), bare = crosshairBandText(r, 'bare')
    expect(full).toBe('11-15 07:13 · 开 100.0 高 103.0 低 99.5 收 102.0 · +2.00%')
    expect(close).toBe('11-15 07:13 · 收 102.0 · +2.00%')
    expect(bare).toBe('收 102.0 · +2.00%')
    expect(full.length).toBeGreaterThan(close.length)
    expect(close.length).toBeGreaterThan(bare.length)
  })

  it('涨跌幅相对上一根收盘；第一根相对自己开盘；平写 0.00%', () => {
    expect(crosshairBand(series(bars), 0, 1)!.change).toBe('0.00%')
    const down = series([[100, 100, 90, 100], [100, 100, 90, 95]])
    expect(crosshairBand(down, 1, 1)!.change).toBe('−5.00%')
  })

  it('日线及以上只写日期', () => {
    expect(crosshairBand(series(bars, '1d'), 0, 1)!.time).toBe('2023-11-15')
  })

  it('下标越界不给', () => {
    expect(crosshairBand(series(bars), 5, 1)).toBeNull()
    expect(crosshairBand(series(bars), -1, 1)).toBeNull()
  })
})
