// 副图高度与顺序跟人走、不按周期分组（2026-10-03 用户：「在一小时周期调整了指标区域大小和顺序，切换周期发现又被改回去了」）
import { describe, expect, it } from 'vitest'
import { defaultPrefs, followOrder, layoutBook, layoutSnapshot, normalizePrefs, settleIndicatorLayouts, type Prefs } from '../src/m/app/prefs'

const edit = (p: Prefs, fn: (p: Prefs) => void) => { const before = layoutSnapshot(p); fn(p); return settleIndicatorLayouts(p, before) }

describe('副图高度与顺序跟人走', () => {
  it('1 小时里拖了副图高度、换了顺序，切到 30 分还是那样，而且不算分叉', () => {
    const p = defaultPrefs()
    edit(p, x => { x.interval = '1h' })
    edit(p, x => { x.subs = ['VOL', 'MACD', 'KDJ'] })      // 先开一个 KDJ：小时组分叉
    const order = [...p.subs].reverse()
    const forked = edit(p, x => { x.subHeightOverrides = { ...x.subHeightOverrides, MACD: 1.6 }; x.subs = order })
    expect(forked).toBeNull()
    edit(p, x => { x.interval = '30m' })
    expect(p.subHeightOverrides.MACD).toBe(1.6)
    // 分钟组没开 KDJ（指标开关仍按组记），共有的 VOL / MACD 按新顺序排
    expect(p.subs).toEqual(followOrder(defaultPrefs().subs, order))
    expect(p.subs.indexOf('MACD')).toBeLessThan(p.subs.indexOf('VOL'))
    edit(p, x => { x.interval = '1d' })
    expect(p.subHeightOverrides.MACD).toBe(1.6)
    expect(layoutBook(p).forks.minute).toBeUndefined()
  })

  it('只调高度不弹「单独记」：没有组分叉', () => {
    const p = defaultPrefs()
    const forked = edit(p, x => { x.subHeightOverrides = { VOL: 0.7 } })
    expect(forked).toBeNull()
    expect(p.indicatorLayouts.others).toEqual({})
    edit(p, x => { x.interval = '4h' })
    expect(p.subHeightOverrides.VOL).toBe(0.7)
  })

  it('把高度复原（删掉某个副图的倍率）也是三组一起', () => {
    const p = defaultPrefs()
    edit(p, x => { x.subHeightOverrides = { VOL: 0.7 } })
    edit(p, x => { x.interval = '1h' })
    edit(p, x => { const h = { ...x.subHeightOverrides }; delete h.VOL; x.subHeightOverrides = h })
    edit(p, x => { x.interval = '5m' })
    expect(p.subHeightOverrides.VOL).toBeUndefined()
  })

  it('老档里各组各记一份高度与顺序：读档时并成一份，以分了叉的组为准', () => {
    const d = defaultPrefs()
    const raw = { ...d, interval: '30m', subs: ['VOL', 'MACD'], subHeightOverrides: {},
      indicatorLayouts: { others: { hour: { ...d, subs: ['MACD', 'VOL'], subHeightOverrides: { MACD: 1.8, VOL: 0.6 } } } } }
    const p = normalizePrefs(JSON.parse(JSON.stringify(raw)))
    expect(p.subs).toEqual(['MACD', 'VOL'])
    expect(p.subHeightOverrides).toEqual({ MACD: 1.8, VOL: 0.6 })
    edit(p, x => { x.interval = '1h' })
    expect(p.subHeightOverrides).toEqual({ MACD: 1.8, VOL: 0.6 })
  })

  it('followOrder 只排共有的，别的留原位', () => {
    expect(followOrder(['VOL', 'KDJ', 'MACD'], ['MACD', 'VOL'])).toEqual(['MACD', 'KDJ', 'VOL'])
  })
})
