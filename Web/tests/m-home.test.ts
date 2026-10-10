/* 手机网页版 · 首页「异动」列表的纯逻辑：不中途重排、新异动计数、胶囊计数、点行带去哪张卡、币名认品种 */
import { describe, expect, it } from 'vitest'
import type { BoardRow } from '../src/highlights/api'
import { chipCounts, favoriteBases, filterRows, focusOf, mergeBoard, symbolFor } from '../src/highlights/home'

const row = (base: string, cat: BoardRow['cat'], atMs: number, top: BoardRow['top'] = { kind: 'event', id: 'E:' + base, t: 'oiJump', atMs, pct: 3 }): BoardRow =>
  ({ key: cat === 'move' ? 'move:' + base : base, atMs, base, cat, changePct: 1, count: 1, favorite: false, price: 1, tier: 2, top })

describe('首页异动 · 合并', () => {
  it('已有的行换数不换位，新来的只计数', () => {
    const shown = [row('BTC', 'book', 10), row('ETH', 'oi', 10)]
    const latest = [row('SOL', 'book', 20), row('ETH', 'oi', 10), row('BTC', 'book', 10)]
    const m = mergeBoard(shown, latest)
    expect(m.rows.map(r => r.base)).toEqual(['BTC', 'ETH'])
    expect(m.fresh).toBe(1)
  })
  it('同一只有了更新的异动也算新的，并换上新数据', () => {
    const shown = [row('BTC', 'book', 10)]
    const latest = [row('BTC', 'funding', 30)]
    const m = mergeBoard(shown, latest)
    expect(m.fresh).toBe(1)
    expect(m.rows[0].cat).toBe('funding')
  })
  it('拉到的里头没了的行留着旧数据', () => {
    const m = mergeBoard([row('BTC', 'book', 10), row('DOGE', 'oi', 5)], [row('BTC', 'book', 10)])
    expect(m.rows.map(r => r.base)).toEqual(['BTC', 'DOGE'])
    expect(m.fresh).toBe(0)
  })
})

describe('首页异动 · 胶囊与筛选', () => {
  const rows = [row('A', 'book', 1), row('B', 'oi', 1), row('C', 'funding', 1), row('D', 'book', 1)]
  it('计数', () => expect(chipCounts(rows)).toEqual({ all: 4, book: 2, oi: 1, funding: 1, move: 0 }))
  it('筛选保序', () => expect(filterRows(rows, 'book').map(r => r.base)).toEqual(['A', 'D']))
})

describe('首页异动 · 点行', () => {
  it('价位 / 事件 / 仓位各带去对应的卡', () => {
    const level = { kind: 'level' as const, id: 'L:1', low: 1, high: 2, side: 'bid' as const, distPct: -0.2, wallUsd: 0, wallHeldMs: 0, wallState: null, cancelPct: null, fillBuyUsd: 0, fillSellUsd: 0, liqUsd: 0, tests: 0, touchMs: null, refs: [] }
    expect(focusOf(level as unknown as BoardRow['top'])).toEqual({ kind: 'level', id: 'L:1' })
    expect(focusOf({ kind: 'event', id: 'E:x', t: 'oiJump', atMs: 1, pct: 2 })).toEqual({ kind: 'event', id: 'E:x' })
    expect(focusOf({ kind: 'position' } as unknown as BoardRow['top'])).toEqual({ kind: 'position' })
  })
  it('币名认品种：自选优先，其次 <币>USDT，再次 1000<币>USDT', () => {
    const baseOf = (s: string): string => s.replace(/^OKX:/, '').replace(/^1000/, '').replace(/-?USDT.*$/, '')
    const has = (s: string): boolean => ['BTCUSDT', '1000PEPEUSDT'].includes(s)
    expect(symbolFor('ETH', ['OKX:ETH-USDT-SWAP'], baseOf, has)).toBe('OKX:ETH-USDT-SWAP')
    expect(symbolFor('BTC', [], baseOf, has)).toBe('BTCUSDT')
    expect(symbolFor('PEPE', [], baseOf, has)).toBe('1000PEPEUSDT')
    expect(symbolFor('NEW', [], baseOf, has)).toBe('NEWUSDT')
  })
  it('自选币名去重保序、最多 60 只', () => {
    const baseOf = (s: string): string => s.replace(/USDT$/, '')
    expect(favoriteBases(['BTCUSDT', 'ETHUSDT', 'BTCUSDT'], baseOf)).toEqual(['BTC', 'ETH'])
    expect(favoriteBases(Array.from({ length: 80 }, (_, i) => `A${i}USDT`), baseOf)).toHaveLength(60)
  })
})
