import { describe, expect, it } from 'vitest'
import { clampActive, hydrate, type Layout } from '../src/app/store'

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
})
