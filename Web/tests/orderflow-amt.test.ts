// PC 订单流金额（梯子、大单卡、统计、设置里的门槛）：单位按舍入之后的样子挑，边界上不出「1000K」「1000」
import { describe, expect, it } from 'vitest'
import { amt } from '../src/orderflow/state'

describe('orderflow amt', () => {
  it('单位边界进位', () => {
    expect(amt(999.6)).toBe('1.0K')
    expect(amt(999_999)).toBe('1.0M')
    expect(amt(999_950)).toBe('1.0M')
    expect(amt(-999_999)).toBe('-1.0M')
    expect(amt(999_999_999)).toBe('1.0B')
    expect(amt(999_999_999_999)).toBe('1.0T')
  })
  it('原有档位不变', () => {
    expect(amt(0)).toBe('0')
    expect(amt(999)).toBe('999')
    expect(amt(1_000)).toBe('1.0K')
    expect(amt(12_345)).toBe('12.3K')
    expect(amt(123_456)).toBe('123K')
    expect(amt(5_000_000)).toBe('5.0M')
    expect(amt(2.5e15)).toBe('2500T')
    expect(amt(-0.2)).toBe('0')
    expect(amt(NaN)).toBe('—')
    expect(amt(null)).toBe('—')
  })
})
