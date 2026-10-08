// 复盘本「观点 · 交易」开在哪一面（照 iOS ReviewSegmentChoiceTests，2026-10-08 走查）
import { describe, expect, it } from 'vitest'
import { preferredSegment } from '../src/m/model/reviewBook'

describe('复盘本：「观点 · 交易」开在哪一面', () => {
  it('观点空、交易有 → 交易；不论上次停在哪', () => {
    expect(preferredSegment('views', true, false)).toBe('trades')
    expect(preferredSegment('trades', true, false)).toBe('trades')
  })
  it('两面都有、两面都空、只有观点 → 留在上次那面', () => {
    for (const cur of ['views', 'trades'] as const) {
      expect(preferredSegment(cur, false, false)).toBe(cur)
      expect(preferredSegment(cur, true, true)).toBe(cur)
      expect(preferredSegment(cur, false, true)).toBe(cur)
    }
  })
})
