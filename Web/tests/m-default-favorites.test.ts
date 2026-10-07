// 手机网页默认自选（2026-10-07 名单）：金银在「加密」最上面，美股按点名顺序，只给一次。
import { describe, expect, it } from 'vitest'
import type { SymbolPrefs } from '../src/m/app/store'
import { seedDefaults } from '../src/m/model/favorites'
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
    expect(groupName(p, 'CLUSDT')).toBe('其他')
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
})
