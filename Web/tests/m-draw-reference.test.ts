// 移植自 KanpanCoreTests/DrawReferenceTests.swift：「画线 · 代表价与周期」（2026-10-08 视觉整改）。
import { describe, expect, it } from 'vitest'
import { drawingWith, type DrawingKind } from '../src/m/chart/draw/drawing'
import { DrawArchive, decodeArchive, encodeArchive } from '../src/m/chart/draw/archive'
import { distancePercent, referencePrice } from '../src/m/chart/draw/reference'
import { changePercentText } from '../src/m/model/rowText'

const line = (kind: DrawingKind, pts: [number, number][], id = 'x') => drawingWith(kind, pts.map(([t, p]) => ({ t, p })), id)

describe('画线 · 代表价与周期', () => {
  it('水平线：代表价就是那一价，距现价带正负号', () => {
    const up = line('hline', [[0, 120]])
    expect(referencePrice(up, 50, 100)).toBe(120)
    expect(Math.abs(distancePercent(up, 50, 100)! - 20)).toBeLessThan(1e-9)
    const down = line('hline', [[0, 90]])
    expect(Math.abs(distancePercent(down, 50, 100)! + 10)).toBeLessThan(1e-9)
    expect(changePercentText(distancePercent(down, 50, 100))).toBe('−10.00%')
  })

  it('趋势线：投影到最新那根的时刻；落在线段外就夹到端点', () => {
    const trend = line('trend', [[0, 100], [100, 200]])
    expect(referencePrice(trend, 50, 140)).toBe(150)
    expect(referencePrice(trend, 300, 140)).toBe(200)
    expect(referencePrice(trend, -50, 140)).toBe(100)
  })

  it('射线向右延长：一直投影下去', () => {
    expect(referencePrice(line('ray', [[0, 100], [100, 200]]), 200, 250)).toBe(300)
  })

  it('矩形取离现价最近的那条边；没有提醒几何的线退到锚点', () => {
    const box = line('rectangle', [[0, 110], [100, 90]])
    expect(referencePrice(box, 50, 104)).toBe(110)
    expect(referencePrice(box, 50, 95)).toBe(90)
    expect(referencePrice(line('vline', [[10, 123]]), 50, 100)).toBe(123)
    expect(distancePercent(line('hline', [[0, 120]]), 0, 0)).toBeNull()
  })

  it('记周期：只补没记过的线，清掉已经不在的；空表不进存档', () => {
    const archive = new DrawArchive()
    const sym = 'binance/usd_m/BTCUSDT'
    archive.set(sym, [line('hline', [[0, 1]], 'a')])
    expect(archive.noteIntervals('15m', sym)).toBe(true)
    expect(archive.intervalOf('a')).toBe('15m')
    archive.set(sym, [...archive.get(sym), line('hline', [[0, 2]], 'b')])
    expect(archive.noteIntervals('1h', sym)).toBe(true)
    expect(archive.intervalOf('a')).toBe('15m')
    expect(archive.intervalOf('b')).toBe('1h')
    expect(archive.noteIntervals('4h', sym)).toBe(false)
    archive.set(sym, [line('hline', [[0, 3]], 'c')])
    expect(archive.noteIntervals('1d', sym)).toBe(true)
    expect(archive.intervalOf('a')).toBeNull()
    expect(archive.intervalOf('c')).toBe('1d')

    const back = decodeArchive(JSON.parse(JSON.stringify(encodeArchive(archive))))
    expect(back.intervalOf('c')).toBe('1d')
    expect(back.equals(archive)).toBe(true)
    expect(JSON.stringify(encodeArchive(new DrawArchive()))).not.toContain('"iv"')
  })

  it('周期表坏了不连累画线', () => {
    const archive = new DrawArchive()
    archive.set('binance/usd_m/BTCUSDT', [line('hline', [[0, 1]], 'a')])
    const json = JSON.parse(JSON.stringify(encodeArchive(archive))) as Record<string, unknown>
    json.iv = 42
    const back = decodeArchive(json)
    expect(back.get('binance/usd_m/BTCUSDT').map(d => d.id)).toEqual(['a'])
    expect(back.intervals).toEqual({})
  })
})

describe('画线列表副行与色板（drawingBench）', () => {
  it('周期 · 距现价 · 价位；周期没记过就不写，没现价只写价位', async () => {
    const { drawingListFacts, penSwatchesHTML } = await import('../src/m/pages/chart/drawingBench')
    const { BarSeries } = await import('../src/m/chart/series')
    const bars = [0, 1, 2].map(i => ({ openTime: i * 900_000, open: 100, high: 101, low: 99, close: 100, volume: 1, takerBuy: 0 }))
    const series = BarSeries.fromBars('BTCUSDT', '15m', bars)
    const trend = line('trend', [[0, 100], [1_800_000, 110]])
    expect(drawingListFacts(trend, '15m', series, 2)).toBe('15分 · 距现价 +10.00% · 110.00')
    expect(drawingListFacts(line('hline', [[0, 90]]), null, series, 2)).toBe('距现价 −10.00% · 90.00')
    expect(drawingListFacts(line('hline', [[0, 1234.5]]), '1h', null, 1)).toBe('1时 · 1,234.5')

    const t = { accent: '#2E7D6B', up: '#36B257', down: '#E64552', ink: '#14211B' }
    const html = penSwatchesHTML(null, t)
    expect(html.match(/data-act="pen"/g)?.length).toBe(5)
    expect(html).toMatch(/class="cp-cchip on"[^>]*data-role="skin"/)
    const custom = penSwatchesHTML('#4A90E2', t)
    expect(custom).toMatch(/data-role="custom"/)
    expect(custom).not.toMatch(/class="cp-cchip on"[^>]*data-role="skin"/)
    expect(penSwatchesHTML('#e64552', t)).toMatch(/class="cp-cchip on"[^>]*data-role="down"/)
  })
})
