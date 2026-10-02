// 指标布局只有一份、跟人走（2026-10-03）：任何周期改了指标、参数、副图顺序与高度，换到任何周期都一样；
// 老档里按周期分了叉的，以当前周期所在组那份为准并成一份
import { describe, expect, it } from 'vitest'
import { defaultPrefs, layoutSnapshot, normalizePrefs, settleIndicatorLayouts, type Prefs } from '../src/m/app/prefs'

const edit = (p: Prefs, fn: (p: Prefs) => void): void => { const before = layoutSnapshot(p); fn(p); settleIndicatorLayouts(p, before) }

describe('指标布局跟人走', () => {
  it('1 小时换了指标、调了副图高度与顺序，切 30 分、4 小时、日线都是同一份，不留分叉', () => {
    const p = defaultPrefs(); p.interval = '1h'
    edit(p, x => {
      x.subs = ['MACD', 'KDJ', 'VOL']
      x.overlays = ['BOLL']
      x.params = { ...x.params, MACD: [12, 26, 9] }
      x.subHeightOverrides = { MACD: 1.8, VOL: 0.6 }
    })
    const want = { subs: p.subs, overlays: p.overlays, params: p.params, h: p.subHeightOverrides }
    for (const iv of ['30m', '4h', '1d', '1h'] as const) {
      edit(p, x => { x.interval = iv })
      expect({ subs: p.subs, overlays: p.overlays, params: p.params, h: p.subHeightOverrides }).toEqual(want)
      expect(p.indicatorLayouts).toEqual({ others: {} })
    }
  })

  it('老档按周期分了叉：以当前周期所在组那份为准并成一份', () => {
    const d = defaultPrefs()
    const hour = { ...d, subs: ['MACD', 'VOL'], subHeightOverrides: { MACD: 1.8 } }
    const raw = {
      ...d, interval: '30m', subs: ['VOL', 'RSI'],
      indicatorLayouts: { others: { hour: { overlays: hour.overlays, subs: hour.subs, params: hour.params, subHeightOverrides: hour.subHeightOverrides, candleKind: 'candle', priceMode: 'log' } } },
    }
    const p = normalizePrefs(raw)
    expect(p.subs).toEqual(['VOL', 'RSI'])
    expect(p.indicatorLayouts).toEqual({ others: {} })
    edit(p, x => { x.interval = '1h' })
    expect(p.subs).toEqual(['VOL', 'RSI'])
  })
})
