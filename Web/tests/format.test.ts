import { describe, expect, it } from 'vitest'
import { IV_MS, TZ_MS, clamp, crossTimeLabel, durText, fmt, fmtAxis, fmtCompact, fmtSub, hexA, niceStep, pad, sh } from '../src/util/format'

describe('fmtCompact：K / M / B / T', () => {
  it('边界', () => {
    expect(fmtCompact(999)).toBe('999')
    expect(fmtCompact(1000)).toBe('1.00K')
    expect(fmtCompact(1.5e6)).toBe('1.50M')
    expect(fmtCompact(2.35e9)).toBe('2.35B')
    expect(fmtCompact(1.2e12)).toBe('1.20T')
    expect(fmtCompact(999999)).toBe('1000.00K') // 原型行为：按量级判断，不进位到 M
  })
  it('小数：< 10 两位，10–999 取整', () => {
    expect(fmtCompact(5)).toBe('5.00')
    expect(fmtCompact(12.6)).toBe('13')
    expect(fmtCompact(0)).toBe('0.00')
  })
  it('负数', () => {
    expect(fmtCompact(-1.5e6)).toBe('-1.50M')
    expect(fmtCompact(-999)).toBe('-999')
    expect(fmtCompact(-3.2e9)).toBe('-3.20B')
  })
  it('空值', () => {
    expect(fmtCompact(null)).toBe('—')
    expect(fmtCompact(undefined)).toBe('—')
    expect(fmtCompact(NaN)).toBe('—')
    expect(fmtCompact(Infinity)).toBe('—')
  })
})

describe('fmt / fmtAxis', () => {
  it('fmt 按小数位、带千分位', () => {
    expect(fmt(1234.5, 2)).toBe('1,234.50')
    expect(fmt(1234.567, 0)).toBe('1,235')
    expect(fmt(0.000123, 6)).toBe('0.000123')
    expect(fmt(-65000.1, 1)).toBe('-65,000.1')
    expect(fmt(null, 2)).toBe('—')
    expect(fmt(NaN, 2)).toBe('—')
  })
  it('fmt 换成缓存的格式器后与 toLocaleString 一字不差（各小数位、正负、零、大数、半位进位）', () => {
    const vals = [0, -0, 0.5, 1.005, 2.675, -1234.5678, 84070.05, 1e12 + 0.125, 0.000123456, 99999.9999, -0.00004]
    for (let dec = 0; dec <= 8; dec++) for (const v of vals) {
      expect(fmt(v, dec)).toBe(v.toLocaleString('en-US', { minimumFractionDigits: dec, maximumFractionDigits: dec }))
    }
  })
  it('fmtAxis 带千分位（和梯子、侧栏一致），null 为空串', () => {
    expect(fmtAxis(1234.5, 2)).toBe('1,234.50')
    expect(fmtAxis(84070, 1)).toBe('84,070.0')
    expect(fmtAxis(0.1234567, 4)).toBe('0.1235')
    expect(fmtAxis(null, 2)).toBe('')
  })
})

describe('fmtSub：副图读数', () => {
  it('低价品种的 MACD / ATR 按价格精度取位，不再全是 0.00', () => {
    expect(fmtSub('macd', 0.000432, 5)).toBe('0.00043')
    expect(fmtSub('atr', 0.00912, 5)).toBe('0.00912')
    expect(fmtSub('macd', -0.0000071, 7)).toBe('-0.0000071')
    expect(fmtSub('macd', 0.0004, 5)).not.toBe('0.00')
  })
  it('高价品种照旧：BTC MACD 250.3 一位、< 10 两位、≥ 1000 用 K', () => {
    expect(fmtSub('macd', 250.34, 1)).toBe('250.3')
    expect(fmtSub('macd', 3.456, 1)).toBe('3.46')
    expect(fmtSub('atr', 1520, 1)).toBe('1.52K')
  })
  it('RSI / KDJ 取整，持仓量 K/M/B，其余两位，非有限值为空', () => {
    expect(fmtSub('rsi', 55.6, 5)).toBe('56')
    expect(fmtSub('kdj', 80.2, 5)).toBe('80')
    expect(fmtSub('oi', 2.5e9, 5)).toBe('2.50B')
    expect(fmtSub('cci', -120.44, 5)).toBe('-120.4')
    expect(fmtSub('wr', -3.2, 5)).toBe('-3.20')
    expect(fmtSub('macd', NaN, 5)).toBe('')
    expect(fmtSub('macd', 12, 12)).toBe('12.0000000000')
  })
})

describe('上海时间', () => {
  it('sh()：读 UTC 字段即上海时间', () => {
    expect(TZ_MS).toBe(8 * 3600e3)
    const d = sh(Date.UTC(2026, 8, 28, 16, 30))
    expect([d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate(), d.getUTCHours(), d.getUTCMinutes()]).toEqual([2026, 9, 29, 0, 30])
  })
  it('crossTimeLabel：UTC 2026-09-28T16:30Z → 上海 09-29 周二 00:30', () => {
    const t = Date.UTC(2026, 8, 28, 16, 30)
    expect(crossTimeLabel(t, 36e5)).toBe('26-09-29 周二  00:30')
    expect(crossTimeLabel(t, 60e3)).toBe('26-09-29 周二  00:30')
  })
  it('crossTimeLabel：日线及以上不带时分；日线 bar（UTC 0 点）落在上海当天 08:00', () => {
    expect(crossTimeLabel(Date.UTC(2026, 8, 29), 864e5)).toBe('26-09-29 周二')
    expect(crossTimeLabel(Date.UTC(2026, 8, 29), 6048e5)).toBe('26-09-29 周二')
    expect(crossTimeLabel(Date.UTC(2026, 8, 29), 36e5)).toBe('26-09-29 周二  08:00')
  })
  it('crossTimeLabel：跨年', () => {
    expect(crossTimeLabel(Date.UTC(2026, 11, 31, 16, 0), 36e5)).toBe('27-01-01 周五  00:00')
  })
})

describe('durText', () => {
  it('分钟 / 小时 / 天', () => {
    expect(durText(0)).toBe('0 分钟')
    expect(durText(30 * 60e3)).toBe('30 分钟')
    expect(durText(59 * 60e3)).toBe('59 分钟')
    expect(durText(60 * 60e3)).toBe('1 小时')
    expect(durText(90 * 60e3)).toBe('1.5 小时')
    expect(durText(47 * 36e5)).toBe('47 小时')
    expect(durText(48 * 36e5)).toBe('2 天')
    expect(durText(60 * 36e5)).toBe('2.5 天')
  })
})

describe('小工具', () => {
  it('pad / clamp', () => {
    expect(pad(3)).toBe('03'); expect(pad(12)).toBe('12')
    expect(clamp(5, 0, 3)).toBe(3); expect(clamp(-1, 0, 3)).toBe(0); expect(clamp(2, 0, 3)).toBe(2)
  })
  it('hexA', () => {
    expect(hexA('#2962FF', 0.5)).toBe('rgba(41,98,255,0.5)')
    expect(hexA('#06B6D4', 1)).toBe('rgba(6,182,212,1)')
    expect(hexA('#fff', 0.3)).toBe('rgba(255,255,255,0.3)')
    expect(hexA('rgb(1,2,3)', 0.5)).toBe('rgb(1,2,3)')
    expect(hexA('', 0.5)).toBe('')
  })
  it('niceStep：1 / 2 / 2.5 / 5 / 10', () => {
    expect(niceStep(1)).toBe(1)
    expect(niceStep(1.7)).toBe(2)
    expect(niceStep(2.2)).toBe(2.5)
    expect(niceStep(23)).toBe(25)
    expect(niceStep(3)).toBe(5)
    expect(niceStep(7)).toBe(10)
    expect(niceStep(0.3)).toBeCloseTo(0.5, 12)
  })
  it('IV_MS', () => {
    expect(IV_MS['1m']).toBe(60e3)
    expect(IV_MS['4h']).toBe(144e5)
    expect(IV_MS['1d']).toBe(864e5)
    expect(IV_MS['1w']).toBe(6048e5)
    expect(IV_MS['1M']).toBe(2592e6)
    expect(Object.keys(IV_MS)).toEqual(['1m', '3m', '5m', '15m', '30m', '1h', '2h', '4h', '6h', '8h', '12h', '1d', '1w', '1M'])
  })
})
