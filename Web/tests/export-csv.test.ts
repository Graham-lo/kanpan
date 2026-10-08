import { describe, expect, it } from 'vitest'
import { buildCsv, csvFileName, indicatorColumns, num, shIso, shStamp } from '../src/chart/exportCsv'
import { Calc, type Bar } from '../src/chart/calc'

const H = 3600e3
const T0 = Date.UTC(2026, 9, 7, 0, 0) // 上海 08:00
const bars = (n: number, taker = true): Bar[] => Array.from({ length: n }, (_, i) => ({
  t: T0 + i * H, o: 62000 + i, h: 62100 + i, l: 61900 + i, c: 62050.5 + i, v: 1234567.891 + i, bv: 19.87654321, ...(taker ? { tb: i === 0 ? 0 : 600000.5 } : {}),
}) as Bar)
const rows = (csv: string): string[][] => csv.replace(/^﻿/, '').trimEnd().split('\r\n').map(l => l.split(','))

describe('CSV 导出', () => {
  it('上海时区 ISO 时间、文件名时刻', () => {
    expect(shIso(T0)).toBe('2026-10-07T08:00:00+08:00')
    expect(shIso(Date.UTC(2026, 9, 6, 16, 30))).toBe('2026-10-07T00:30:00+08:00')
    expect(shStamp(T0)).toBe('20261007-0800')
    expect(csvFileName('BTCUSDT', '15m', T0, T0 + 3 * H)).toBe('BTCUSDT_15m_20261007-0800_20261007-1100.csv')
  })

  it('数字去尾零、空值留空', () => {
    expect(num(1.5, 4)).toBe('1.5')
    expect(num(2, 2)).toBe('2')
    expect(num(0.000123456, 6)).toBe('0.000123')
    expect(num(null, 2)).toBe('')
    expect(num(Number.NaN, 2)).toBe('')
  })

  it('UTF-8 BOM、CRLF；列：时间、开高低收、成交量、成交额、主动买入额，再接指标', () => {
    const b = bars(3)
    const ma = [null, 62001, 62002]
    const csv = buildCsv({ bars: b, dec: 1, columns: [{ name: '均线 10', values: ma }] })
    expect(csv.startsWith('﻿')).toBe(true)
    expect(csv.endsWith('\r\n')).toBe(true)
    const r = rows(csv)
    expect(r[0]).toEqual(['时间', '开盘', '最高', '最低', '收盘', '成交量', '成交额', '主动买入额', '均线 10'])
    expect(r).toHaveLength(4)
    expect(r[1]).toEqual(['2026-10-07T08:00:00+08:00', '62000', '62100', '61900', '62050.5', '19.87654321', '1234567.89', '0', ''])
    expect(r[3][0]).toBe('2026-10-07T10:00:00+08:00')
    expect(r[3][8]).toBe('62002')
  })

  it('交易所没给主动买入额（或全是 0）时没有那一列', () => {
    expect(rows(buildCsv({ bars: bars(2, false), dec: 2 }))[0]).toEqual(['时间', '开盘', '最高', '最低', '收盘', '成交量', '成交额'])
    const zero = bars(2).map(x => ({ ...x, tb: 0 }))
    expect(rows(buildCsv({ bars: zero, dec: 2 }))[0]).not.toContain('主动买入额')
  })

  it('列名里有逗号、引号的加引号转义', () => {
    const csv = buildCsv({ bars: bars(1), dec: 2, columns: [{ name: '自定义(1,2) "x"', values: [1] }] })
    expect(csv.split('\r\n')[0].endsWith(',"自定义(1,2) ""x"""')).toBe(true)
  })

  it('指标列名：中文名 + 线名 / 周期；单线带参数；长度对不上的不导', () => {
    const b = bars(40)
    const ma = indicatorColumns('ma', Calc.ma(b, { periods: [5, 10] }, undefined as never), b.length, { periods: [5, 10] })
    expect(ma.map(c => c.name)).toEqual(['MA 5', 'MA 10'])
    const boll = indicatorColumns('boll', Calc.boll(b, { n: 20, k: 2 }, undefined as never), b.length, { n: 20, k: 2 })
    expect(boll.map(c => c.name)).toEqual(['BOLL 中轨', 'BOLL 上轨', 'BOLL 下轨'])
    const macd = indicatorColumns('macd', Calc.macd(b, { fast: 12, slow: 26, signal: 9 }, undefined as never), b.length, { fast: 12, slow: 26, signal: 9 })
    expect(macd.map(c => c.name)).toEqual(['MACD 快线', 'MACD 慢线', 'MACD 柱'])
    const rsi = indicatorColumns('rsi', [new Array(40).fill(50)], 40, { n: 14 })
    expect(rsi.map(c => c.name)).toEqual(['RSI(14)'])
    expect(indicatorColumns('rsi', [new Array(39).fill(50)], 40, { n: 14 })).toEqual([])
  })
})
