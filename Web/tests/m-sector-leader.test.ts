// 手机网页板块行「领涨 X」（照 iOS SectorAggregator.leader / SectorLeaderLabel，2026-10-08）
import { describe, expect, it } from 'vitest'
import { leaderLabel, leaderName, leaderOf } from '../src/m/model/sectorView'
import { EMPTY_HISTORY, type Quotes, type SectorQuote } from '../src/sectors/aggregate'

const quotes = (rows: [string, number][]): Quotes =>
  new Map(rows.map(([base, pct]) => [base, { base, symbol: base + 'USDT', price: 1, pct, quoteVolume: 1 } as SectorQuote]))

describe('leaderOf', () => {
  it('收益最高、而且在涨的那一只；并列取代号小的', () => {
    expect(leaderOf(['A', 'B', 'C'], [1, 3, 2])).toBe('B')
    expect(leaderOf(['Z', 'B'], [3, 3])).toBe('B')
    expect(leaderOf(['B', 'Z'], [3, 3])).toBe('B')
  })
  it('全员不涨、不到两只、长度对不上都没有', () => {
    expect(leaderOf(['A', 'B'], [-1, 0])).toBeNull()
    expect(leaderOf(['A'], [5])).toBeNull()
    expect(leaderOf(['A', 'B'], [5])).toBeNull()
    expect(leaderOf(['A', 'B'], [NaN, 2])).toBe('B')
  })
})

describe('leaderName', () => {
  it('短代号照写；长的截到 8 位', () => {
    expect(leaderName('BTC')).toBe('BTC')
    expect(leaderName('ABCDEFGHIJK')).toBe('ABCDEFGH')
  })
  it('读不出是谁的长代号换中文简称；短代号即使有简称也照写代号', () => {
    expect(leaderName('SKHYNIX')).toBe('SK 海力士')
    expect(leaderName('NVDA')).toBe('NVDA')
  })
})

describe('leaderLabel', () => {
  it('有行情成员够三家才写', () => {
    expect(leaderLabel(['A', 'B', 'C'], quotes([['A', 1], ['B', 4], ['C', -2]]), 'today', EMPTY_HISTORY)).toBe('领涨 B')
    expect(leaderLabel(['A', 'B'], quotes([['A', 1], ['B', 4]]), 'today', EMPTY_HISTORY)).toBe('')
  })
  it('没人在涨就不写', () => {
    expect(leaderLabel(['A', 'B', 'C'], quotes([['A', -1], ['B', -4], ['C', 0]]), 'today', EMPTY_HISTORY)).toBe('')
  })
})
