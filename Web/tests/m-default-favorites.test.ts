// 手机网页默认自选（2026-10-07 名单，照 iOS DefaultFavorites）：金银在「加密」最上面，点名六个币 + 成交额前五，美股按点名顺序，只给一次。
import { describe, expect, it } from 'vitest'
import type { SymbolPrefs } from '../src/m/app/store'
import { hotCoins, seedDefaults, type HotRow } from '../src/m/model/favorites'
import { DEFAULT_WATCH } from '../src/market/symbols'

const blank = (): SymbolPrefs => ({ favorites: [], recents: [], groups: [], groupForSymbol: {}, seeded: false })
const groupName = (p: SymbolPrefs, s: string): string | undefined =>
  p.groups.find(g => g.id === p.groupForSymbol[s])?.name

describe('手机网页默认自选', () => {
  it('金银排在最上面并归进「加密」，接着是点名的币，再是美股', () => {
    const p = blank()
    expect(seedDefaults(p)).toBe(true)
    expect(p.favorites.slice(0, 8)).toEqual(['XAUUSDT', 'XAGUSDT', 'BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'XRPUSDT', 'DOGEUSDT', 'ZECUSDT'])
    expect(groupName(p, 'XAUUSDT')).toBe('加密')
    expect(groupName(p, 'XAGUSDT')).toBe('加密')
    expect(groupName(p, 'BTCUSDT')).toBe('加密')
    const us = p.favorites.filter(s => groupName(p, s) === '美股')
    expect(us).toEqual(DEFAULT_WATCH.us)
    expect(us.slice(0, 3)).toEqual(['NVDAUSDT', 'QQQUSDT', 'SOXLUSDT'])
    expect(p.groups.map(g => g.name).slice(0, 2)).toEqual(['加密', '美股'])
    expect(p.groups.some(g => g.name === '贵金属')).toBe(false)
    // iOS 名单里没有原油（其他大宗不给）
    expect(p.favorites).not.toContain('CLUSDT')
    expect(p.groups.some(g => g.name === '其他')).toBe(false)
    expect(new Set(p.favorites).size).toBe(p.favorites.length)
  })

  it('交易所没有的代号跳过', () => {
    const p = blank()
    seedDefaults(p, s => s !== 'SPCXUSDT' && s !== 'XAGUSDT')
    expect(p.favorites).not.toContain('SPCXUSDT')
    expect(p.favorites).not.toContain('XAGUSDT')
    expect(p.favorites[0]).toBe('XAUUSDT')
    expect(p.favorites[1]).toBe('BTCUSDT')
  })

  it('只给一次；已有自选不覆盖', () => {
    const p = blank()
    seedDefaults(p)
    const n = p.favorites.length
    p.favorites.splice(0, 1)
    expect(seedDefaults(p)).toBe(false)
    expect(p.favorites.length).toBe(n - 1)

    const q = blank()
    q.favorites = ['TSLAUSDT']
    expect(seedDefaults(q)).toBe(true)
    expect(q.favorites).toEqual(['TSLAUSDT'])
    expect(q.seeded).toBe(true)
  })

  it('有品种表时：点名六个币之后接成交额前五（只认币、按 base 归并、点名的不算）', () => {
    const rows: HotRow[] = [
      { symbol: 'BTCUSDT', base: 'BTC', kind: 'crypto', vol: 9e9 },
      { symbol: 'TSLAUSDT', base: 'TSLA', kind: 'us', vol: 8e9 },
      { symbol: 'XAUUSDT', base: 'XAU', kind: 'com', vol: 7e9 },
      { symbol: 'BNBUSDT', base: 'BNB', kind: 'crypto', vol: 5e9 },
      { symbol: 'BNBUSDC', base: 'BNB', kind: 'crypto', vol: 1e9 },
      { symbol: '1000PEPEUSDT', base: 'PEPE', kind: 'crypto', vol: 4e9 },
      { symbol: 'PEPEUSDC', base: 'PEPE', kind: 'crypto', vol: 2e8 },
      { symbol: 'ADAUSDT', base: 'ADA', kind: 'crypto', vol: 3e9 },
      { symbol: 'AAVEUSDT', base: 'AAVE', kind: 'crypto', vol: 3e9 },
      { symbol: 'WIFUSDT', base: 'WIF', kind: 'crypto', vol: 2e9 },
      { symbol: 'TRXUSDT', base: 'TRX', kind: 'crypto', vol: 1e9 },
      { symbol: 'DEADUSDT', base: 'DEAD', kind: 'crypto', vol: 0 },
    ]
    const hot = hotCoins(rows)
    expect(hot).toEqual(['BNBUSDT', '1000PEPEUSDT', 'AAVEUSDT', 'ADAUSDT', 'WIFUSDT'])

    const p = blank()
    seedDefaults(p, null, hot)
    const crypto = p.favorites.filter(s => groupName(p, s) === '加密')
    expect(crypto).toEqual(['XAUUSDT', 'XAGUSDT', 'BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'XRPUSDT', 'DOGEUSDT', 'ZECUSDT', ...hot])
    expect(p.favorites).not.toContain('HYPEUSDT')
  })

  it('取不到成交额（表没到 / 都是 0）时退回出厂那几只', () => {
    expect(hotCoins([])).toEqual([])
    const p = blank()
    seedDefaults(p, null, null)
    expect(p.favorites.slice(8, 14)).toEqual(['HYPEUSDT', 'LINKUSDT', 'SUIUSDT', 'NEARUSDT', 'QNTUSDT', 'HBARUSDT'])
  })
})
