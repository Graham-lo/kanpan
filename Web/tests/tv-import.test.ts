/* 从 TradingView 导入自选：切分、去前缀后缀、按币安合约表匹配、分区映射、去重 */
import { describe, expect, it } from 'vitest'
import type { Kind } from '../src/market/symbols'
import { applyTv, importTv, matchTv, parseTv, sectionKind, stripTv } from '../src/watch/tvImport'
import type { TvUniverse } from '../src/watch/tvImport'

// 取自币安合约表的真实代号（2026-09-29 exchangeInfo）
const TABLE: Record<string, Kind> = {
  BTCUSDT: 'crypto', ETHUSDT: 'crypto', SOLUSDT: 'crypto', HYPEUSDT: 'crypto', '1000PEPEUSDT': 'crypto', '1000SHIBUSDT': 'crypto',
  '1000000MOGUSDT': 'crypto', NVDAUSDT: 'us', AAPLUSDT: 'us', QQQUSDT: 'us', XAUUSDT: 'com', XAGUSDT: 'com', CLUSDT: 'com', BZUSDT: 'com',
}
const U: TvUniverse = { has: s => s in TABLE, kindOf: s => TABLE[s] }
const empty = (): Record<Kind, string[]> => ({ crypto: [], us: [], com: [] })

describe('TradingView 代号', () => {
  it('去交易所前缀与永续后缀', () => {
    expect(stripTv('BINANCE:BTCUSDT.P')).toBe('BTCUSDT')
    expect(stripTv('binance:ethusdtperp')).toBe('ETHUSDT')
    expect(stripTv(' NASDAQ:NVDA ')).toBe('NVDA')
    expect(stripTv('BTC-USDT')).toBe('BTCUSDT')
  })
  it('按合约表匹配：原样、换计价、补 USDT、1000 前缀、大宗俗名', () => {
    expect(matchTv('BINANCE:BTCUSDT.P', U)).toBe('BTCUSDT')
    expect(matchTv('COINBASE:ETHUSD', U)).toBe('ETHUSDT')
    expect(matchTv('BINANCE:SOLUSDC', U)).toBe('SOLUSDT')
    expect(matchTv('HYPE', U)).toBe('HYPEUSDT')
    expect(matchTv('BINANCE:PEPEUSDT', U)).toBe('1000PEPEUSDT')
    expect(matchTv('BINANCE:1000PEPEUSDT.P', U)).toBe('1000PEPEUSDT')
    expect(matchTv('MOGUSDT', U)).toBe('1000000MOGUSDT')
    expect(matchTv('NASDAQ:NVDA', U)).toBe('NVDAUSDT')
    expect(matchTv('OANDA:XAUUSD', U)).toBe('XAUUSDT')
    expect(matchTv('TVC:GOLD', U)).toBe('XAUUSDT')
    expect(matchTv('TVC:UKOIL', U)).toBe('BZUSDT')
    expect(matchTv('COMEX:GC1!', U)).toBeNull()
    expect(matchTv('NASDAQ:ZZZZ', U)).toBeNull()
  })
  it('逗号、换行、分号都能切；###是分区', () => {
    expect(parseTv('###加密,BINANCE:BTCUSDT.P,\nETHUSDT; ###美股\nNVDA')).toEqual([
      { raw: 'BINANCE:BTCUSDT.P', section: '加密' }, { raw: 'ETHUSDT', section: '加密' }, { raw: 'NVDA', section: '美股' },
    ])
  })
  it('分区名映射到三个分类，映射不上返回 null', () => {
    expect(sectionKind('加密')).toBe('crypto')
    expect(sectionKind('Crypto')).toBe('crypto')
    expect(sectionKind('美股')).toBe('us')
    expect(sectionKind('Stocks')).toBe('us')
    expect(sectionKind('大宗')).toBe('com')
    expect(sectionKind('Commodities')).toBe('com')
    expect(sectionKind('短线观察')).toBeNull()
  })
})

describe('导入结果', () => {
  it('品种按自身类别入列；已在自选的跳过；重复只算一次；对不上的列出来', () => {
    const watch = { ...empty(), crypto: ['BTCUSDT'] }
    const text = '###短线观察,BINANCE:BTCUSDT.P,BINANCE:ETHUSDT.P,BINANCE:ETHUSDT,###美股,NASDAQ:NVDA,OANDA:XAUUSD,COMEX:GC1!,COMEX:GC1!'
    const r = importTv(text, U, watch)
    expect(r.added).toEqual({ crypto: ['ETHUSDT'], us: ['NVDAUSDT'], com: ['XAUUSDT'] })
    expect(r.already).toEqual(['BTCUSDT'])
    expect(r.unmatched).toEqual(['COMEX:GC1!'])
    expect(r.total).toBe(4)
    expect(r.sections).toEqual([
      { name: '短线观察', kind: 'crypto', mapped: false, count: 2 },
      { name: '美股', kind: 'us', mapped: true, count: 2 },
    ])
    // 不改传进来的自选
    expect(watch.crypto).toEqual(['BTCUSDT'])
  })
  it('并进自选：追加到各类末尾，返回新增数', () => {
    const watch = { crypto: ['BTCUSDT'], us: [], com: ['XAGUSDT'] } as Record<Kind, string[]>
    const r = importTv('SOL,AAPL,XAU,XAG', U, watch)
    expect(applyTv(watch, r)).toBe(3)
    expect(watch).toEqual({ crypto: ['BTCUSDT', 'SOLUSDT'], us: ['AAPLUSDT'], com: ['XAGUSDT', 'XAUUSDT'] })
  })
  it('空输入', () => {
    const r = importTv('  \n , ', U, empty())
    expect(r.total).toBe(0); expect(r.unmatched).toEqual([])
  })
})
