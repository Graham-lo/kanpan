import { describe, it, expect } from 'vitest'
import { fmtCompact } from '../src/util/format'

describe('fmtCompact 进位与负零（B6）', () => {
  it('舍入后满 1000 进到下一个单位', () => {
    expect(fmtCompact(999_999)).toBe('1.00M')
    expect(fmtCompact(999_995)).toBe('1.00M')
    expect(fmtCompact(999.6)).toBe('1.00K')
    expect(fmtCompact(999_995_000)).toBe('1.00B')
    expect(fmtCompact(-999_999)).toBe('-1.00M')
  })
  it('舍成 0 的负数不带负号', () => {
    expect(fmtCompact(-0.001)).toBe('0.00')
    expect(fmtCompact(-0)).toBe('0.00')
  })
  it('原有写法不变', () => {
    expect(fmtCompact(1234)).toBe('1.23K')
    expect(fmtCompact(5.5)).toBe('5.50')
    expect(fmtCompact(56)).toBe('56')
    expect(fmtCompact(2.5e12)).toBe('2.50T')
    expect(fmtCompact(3.2e15)).toBe('3200.00T')
    expect(fmtCompact(null)).toBe('—')
    expect(fmtCompact(NaN)).toBe('—')
  })
})
