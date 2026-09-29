import { describe, expect, it } from 'vitest'
import { EMPTY_HISTORY, stats, type Quotes, type SectorHistory, type SectorQuote } from '../src/sectors/aggregate'
import { coveredCount, drillDecision } from '../src/m/model/sectorView'

const q = (base: string, pct: number, price = 100): SectorQuote => ({ base, pct, quoteVolume: 1, price })
const quotesOf = (list: SectorQuote[]): Quotes => new Map(list.map(x => [x.base, x]))

describe('手机网页版 · 板块页规模与下钻（照 iOS SectorPage / SectorDrillDecision）', () => {
  // ARM、QCOM 同时属于 gpu 与 edge；ALAB、QCOM 没有 5 日收盘价
  const quotes = quotesOf([q('ARM', 1), q('AVGO', 2), q('ALAB', 3), q('QCOM', -1)])
  const history: SectorHistory = { asof: '2026-09-29', closes: new Map([['ARM', { c5: 90 }], ['AVGO', { c5: 95 }]]) }

  it('5 日档：只数这段窗口上算得出收益的品种，缺收盘价的不算；跨板块的只数一次', () => {
    expect(coveredCount('us', quotes, [], 'today', EMPTY_HISTORY)).toBe(4)
    expect(coveredCount('us', quotes, [], 'd5', history)).toBe(2)
    // 旧写法（各板块成员里「有报价」的去重）在 5 日档会多数出 ALAB、QCOM
    const boards = stats('us', quotes, [], 'd5', history)
    expect(boards.length).toBeGreaterThan(0)
  })

  it('兜底桶的成员也算进规模', () => {
    const qs = quotesOf([q('ZZZ1', 1), q('ZZZ2', 2)])
    expect(coveredCount('crypto', qs, [{ id: 'fb:x', name: '其他', members: ['ZZZ1', 'ZZZ2'] }], 'today', EMPTY_HISTORY)).toBe(2)
  })

  it('下钻：有统计就画；目录或兜底桶认它就等；整帧皆空也等；只有确认没了才退回列表', () => {
    expect(drillDecision('gpu', [{ id: 'gpu' }], [])).toBe('show')
    expect(drillDecision('gpu', [{ id: 'edge' }], [])).toBe('wait')
    expect(drillDecision('fb:x', [{ id: 'edge' }], [{ id: 'fb:x' }])).toBe('wait')
    expect(drillDecision('fb:gone', [], [])).toBe('wait')
    expect(drillDecision('fb:gone', [{ id: 'edge' }], [])).toBe('pop')
  })
})
