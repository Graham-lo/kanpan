import { describe, it, expect, vi, beforeEach } from 'vitest'

// 持仓变化那一列的取数：把行情层换成可控的假接口（只数请求、手动放行）
const h = vi.hoisted(() => ({ calls: [] as string[], pending: [] as { url: string; res: (v: unknown) => void; rej: (e: unknown) => void }[], detail: new Map<string, { t: number; oiChg?: number }>() }))
vi.mock('../src/market', () => ({
  REST: 'https://x',
  j: (url: string) => { h.calls.push(url); return new Promise((res, rej) => h.pending.push({ url, res, rej })) },
  detailOf: (k: string) => h.detail.get(k),
  isDefaultVenue: (k: string) => !k.includes('/'),
  parseKey: (k: string) => { const p = k.split('/'); return p.length === 3 ? { venue: p[0], market: p[1], symbol: p[2] } : { venue: 'binance', market: 'usdm', symbol: k } },
}))

import { MEMBER_SORTS, barScale, fundingText, parseSort, sortMembers, strengthBar } from '../src/sectors/view'
import { OI_MAX_PER_BOARD, loadOiChanges, oiChangeOf, oiChangePct, resetOiForTest } from '../src/sectors/oi'
import { marketReturn } from '../src/sectors/aggregate'
import type { Quotes } from '../src/sectors/aggregate'

describe('板块表强弱条', () => {
  it('满格 = 本表有限涨跌幅的最大绝对值；没有数或全 0 给 0', () => {
    expect(barScale([1.2, -6.4, 3, NaN, Infinity])).toBe(6.4)
    expect(barScale([])).toBe(0)
    expect(barScale([0, 0, NaN])).toBe(0)
  })
  it('涨从中线往右、跌从中线往左，半根轨道 = 满格', () => {
    expect(strengthBar(6.4, 6.4)).toEqual({ left: 50, width: 50, dir: 'up' })
    expect(strengthBar(-6.4, 6.4)).toEqual({ left: 0, width: 50, dir: 'down' })
    expect(strengthBar(3.2, 6.4)).toEqual({ left: 50, width: 25, dir: 'up' })
    expect(strengthBar(-1.6, 6.4)).toEqual({ left: 37.5, width: 12.5, dir: 'down' })
  })
  it('超出满格的按满格画；0、非数、满格为 0 时不画', () => {
    expect(strengthBar(9, 6)).toEqual({ left: 50, width: 50, dir: 'up' })
    expect(strengthBar(-9, 6)).toEqual({ left: 0, width: 50, dir: 'down' })
    for (const [p, s] of [[0, 5], [NaN, 5], [2, 0], [2, NaN]]) expect(strengthBar(p, s)).toEqual({ left: 50, width: 0, dir: '' })
  })
  it('宽度取一位小数（行内 style 不写出一长串小数）', () => {
    const b = strengthBar(1, 3)
    expect(b.width).toBe(16.7)
    expect(strengthBar(-1, 3)).toEqual({ left: 33.3, width: 16.7, dir: 'down' })
  })
})

describe('成分表排序', () => {
  const rows = [
    { base: 'AAA', pct: 2, quoteVolume: 10 },
    { base: 'BBB', pct: -1, quoteVolume: 300 },
    { base: 'CCC', pct: NaN, quoteVolume: NaN },
    { base: 'DDD', pct: 5, quoteVolume: 20 },
    { base: 'ABB', pct: 2, quoteVolume: 20 },
  ]
  const oi: Record<string, number | null> = { AAA: 1.5, BBB: 8, CCC: null, DDD: -2 }
  it('三档：涨跌幅 / 成交额 / 持仓变化', () => {
    expect(MEMBER_SORTS.map(s => s[1])).toEqual(['涨跌幅', '成交额', '持仓变化'])
  })
  it('按涨跌幅降序，缺数沉底，并列按代号', () => {
    expect(sortMembers(rows, 'pct').map(r => r.base)).toEqual(['DDD', 'AAA', 'ABB', 'BBB', 'CCC'])
  })
  it('按成交额降序', () => {
    expect(sortMembers(rows, 'vol').map(r => r.base)).toEqual(['BBB', 'ABB', 'DDD', 'AAA', 'CCC'])
  })
  it('按持仓变化降序，取不到 / 还没取到的沉底', () => {
    expect(sortMembers(rows, 'oi', r => oi[r.base]).map(r => r.base)).toEqual(['BBB', 'AAA', 'DDD', 'ABB', 'CCC'])
  })
  it('不改原数组', () => {
    const before = rows.map(r => r.base)
    sortMembers(rows, 'vol')
    expect(rows.map(r => r.base)).toEqual(before)
  })
  it('本机记的排序：认不得的值回到涨跌幅', () => {
    expect(parseSort('vol')).toBe('vol')
    expect(parseSort('oi')).toBe('oi')
    for (const x of ['pct', null, undefined, '', 'xx']) expect(parseSort(x)).toBe('pct')
  })
  it('费率写法和图表页详情块一致', () => {
    expect(fundingText(0.0001)).toBe('0.0100%')
    expect(fundingText(-0.000375)).toBe('-0.0375%')
    expect(fundingText(null)).toBe('—')
    expect(fundingText(undefined)).toBe('—')
  })
})

describe('大盘涨跌幅', () => {
  it('= 全场等权池对数收益均值换回百分数；池空给 null', () => {
    const q = (base: string, pct: number) => ({ base, pct, quoteVolume: 1, price: 1 })
    const quotes: Quotes = new Map([['XA', q('XA', 10)], ['XB', q('XB', -10)]])
    const buckets = [{ id: 'x', name: 'X', members: ['XA', 'XB'] }]
    const want = (Math.exp((Math.log(1.1) + Math.log(0.9)) / 2) - 1) * 100
    expect(marketReturn('crypto', quotes, buckets)).toBeCloseTo(want, 9)
    expect(marketReturn('crypto', new Map(), [])).toBeNull()
  })
})

describe('持仓变化取数', () => {
  beforeEach(() => { resetOiForTest(); h.calls.length = 0; h.pending.length = 0; h.detail.clear() })
  const flush = () => new Promise(r => setTimeout(r, 0))

  it('24 小时变化 = 最新点 / 最早点 − 1；点不够、数不对给 null', () => {
    expect(oiChangePct([{ sumOpenInterestValue: '100' }, { sumOpenInterestValue: '110' }])).toBeCloseTo(10, 9)
    expect(oiChangePct([{ sumOpenInterestValue: '100' }])).toBeNull()
    expect(oiChangePct([{ sumOpenInterestValue: '0' }, { sumOpenInterestValue: '5' }])).toBeNull()
    expect(oiChangePct(null)).toBeNull()
  })

  it('同时最多 3 个在途、按给的顺序取；回来一只补一次', async () => {
    let n = 0
    loadOiChanges(['A', 'B', 'C', 'D'], () => n++)
    await flush()
    expect(h.calls.map(u => /symbol=(\w+)/.exec(u)?.[1])).toEqual(['A', 'B', 'C'])
    expect(h.calls[0]).toContain('/futures/data/openInterestHist?symbol=A&period=1h&limit=25')
    h.pending.shift()!.res([{ sumOpenInterestValue: '100' }, { sumOpenInterestValue: '102' }])
    await flush()
    expect(oiChangeOf('A')).toBeCloseTo(2, 9)
    expect(n).toBe(1)
    expect(h.calls.length).toBe(4)
  })

  it('同一批成员再调进来不重开、不重复发', async () => {
    loadOiChanges(['A', 'B'], () => {})
    loadOiChanges(['B', 'A'], () => {})
    await flush()
    expect(h.calls.length).toBe(2)
  })

  it('非币安合约、现货不发请求，直接记「取不到」；取失败也记「取不到」', async () => {
    loadOiChanges(['okx/swap/BTC-USDT-SWAP', 'binance/spot/BTCUSDT', 'E'], () => {})
    await flush()
    expect(h.calls.length).toBe(1)
    expect(oiChangeOf('okx/swap/BTC-USDT-SWAP')).toBeNull()
    expect(oiChangeOf('binance/spot/BTCUSDT')).toBeNull()
    h.pending.shift()!.rej(new Error('500'))
    await flush()
    expect(oiChangeOf('E')).toBeNull()
  })

  it('图表页详情刚取过的直接用它，不再发', async () => {
    h.detail.set('F', { t: Date.now(), oiChg: 3.5 })
    loadOiChanges(['F'], () => {})
    await flush()
    expect(h.calls.length).toBe(0)
    expect(oiChangeOf('F')).toBe(3.5)
  })

  it('一个板块最多取前 100 只', async () => {
    const many = Array.from({ length: OI_MAX_PER_BOARD + 20 }, (_, i) => 'S' + i)
    loadOiChanges(many, () => {})
    for (let i = 0; i < 200 && h.pending.length; i++) { h.pending.shift()!.res([]); await flush() }
    expect(h.calls.length).toBe(OI_MAX_PER_BOARD)
  })
})
