import { describe, expect, it } from 'vitest'
import { clampActive, hydrate, type Layout } from '../src/app/store'
import { MAX_SUBS } from '../src/chart/calc'

describe('页面状态', () => {
  it('当前格收进布局格数以内：八图第 3 格改成一图 → 第 0 格（地址栏 ?layout=1&s=… 才落在看得见的格子上）', () => {
    const s = { active: 2, layout: '1' as Layout }
    clampActive(s)
    expect(s.active).toBe(0)
    const t = { active: 5, layout: '4' as Layout }
    clampActive(t)
    expect(t.active).toBe(3)
    const u = { active: Number.NaN, layout: '8' as Layout }
    clampActive(u)
    expect(u.active).toBe(0)
  })

  it('读盘时也收：存着 active 越界的老状态起来是第 0 格', () => {
    expect(hydrate({ layout: '2', active: 7 }).active).toBe(1)
    expect(hydrate({ layout: '1', active: 2 }).active).toBe(0)
  })

  it('副图上限三个（和手机端 Prefs.maxSubs 一致）：本机存着四个的收成前三个，成交量不占名额', () => {
    expect(MAX_SUBS).toBe(3)
    const s = hydrate({ ind: { ma: true, ema: false, boll: false, vol: true, subs: ['macd', 'rsi', 'kdj', 'oi'] } })
    expect(s.ind.subs).toEqual(['macd', 'rsi', 'kdj'])
    expect(s.ind.vol).toBe(true)
  })
})
