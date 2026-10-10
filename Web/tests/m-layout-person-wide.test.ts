// 指标布局只有一份、跟人走（2026-10-03）：任何周期改了指标、参数、副图顺序与高度，换到任何周期都一样。
// 老档里 09-27~10-02 按周期分的叉（indicatorLayouts）2026-10-10 退役：读时整键忽略，布局就是顶层那份
import { describe, expect, it } from 'vitest'
import { defaultPrefs, normalizePrefs } from '../src/m/app/prefs'

describe('指标布局跟人走', () => {
  it('1 小时换了指标、调了副图高度与顺序，切 30 分、4 小时、日线都是同一份', () => {
    const p = defaultPrefs(); p.interval = '1h'
    p.subs = ['MACD', 'KDJ', 'VOL']
    p.overlays = ['BOLL']
    p.params = { ...p.params, MACD: [12, 26, 9] }
    p.subHeightOverrides = { MACD: 1.8, VOL: 0.6 }
    const want = { subs: p.subs, overlays: p.overlays, params: p.params, h: p.subHeightOverrides }
    for (const iv of ['30m', '4h', '1d', '1h'] as const) {
      p.interval = iv
      const back = normalizePrefs(JSON.parse(JSON.stringify(p)))
      expect({ subs: back.subs, overlays: back.overlays, params: back.params, h: back.subHeightOverrides }).toEqual(want)
    }
  })

  it('老档按周期分了叉：分叉整键忽略，布局就是顶层那份', () => {
    const d = defaultPrefs()
    const raw = {
      ...d, interval: '1h', subs: ['VOL', 'RSI'],
      indicatorLayouts: { others: { hour: { overlays: ['EMA'], subs: ['MACD', 'VOL'], params: {}, subHeightOverrides: { MACD: 1.8 }, candleKind: 'candle', priceMode: 'log' } } },
    }
    const p = normalizePrefs(raw)
    expect(p.subs).toEqual(['VOL', 'RSI'])
    expect(p.overlays).toEqual(d.overlays)
    expect(p.subHeightOverrides).toEqual({})
    expect('indicatorLayouts' in p).toBe(false)
  })
})
