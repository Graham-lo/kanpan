// 手机网页版拼音搜索（照 iOS SymbolAliases）：全拼前缀进中文名前缀那档，首字母前缀进中文名包含那档
import { describe, expect, it } from 'vitest'
import { aliasNames, CRYPTO_NAMES, matchOne, normalize, pinyinOf, rank, Tier } from '../src/m/model/search'
import { SEC } from '../src/market/symbols'

const HAN = /[㐀-䶿一-鿿]/
const sym = (symbol: string, vol = 1) => ({ symbol, vol, price: 1 })

describe('拼音搜索', () => {
  it('别名表里每个带汉字的名字都有拼音（漏跑 gen-pinyin.swift 会在这儿红）', () => {
    const names = Object.values(CRYPTO_NAMES).flat().concat(Object.values(SEC.usNames || {}))
    const missing = names.filter(n => HAN.test(n) && !pinyinOf(n))
    expect(missing).toEqual([])
  })

  it('bitebi / btb → BTC；tsl → TSLA；dabing → BTC', () => {
    expect(matchOne('BTCUSDT', 'BTC', normalize('bitebi'))?.tier).toBe(Tier.cnPrefix)
    expect(matchOne('BTCUSDT', 'BTC', normalize('bite'))?.tier).toBe(Tier.cnPrefix)
    expect(matchOne('BTCUSDT', 'BTC', normalize('btb'))?.tier).toBe(Tier.cnContains)
    expect(matchOne('BTCUSDT', 'BTC', normalize('dabing'))?.tier).toBe(Tier.cnPrefix)
    expect(aliasNames('TSLA')).toContain('特斯拉')
    expect(matchOne('TSLAUSDT', 'TSLA', normalize('tsl'))?.tier).toBe(Tier.cnContains)
  })

  it('一个字母不认拼音；纯英文名不产生首字母', () => {
    expect(matchOne('BTCUSDT', 'BTC', normalize('x'))).toBeNull()
    expect(pinyinOf('AMD')).toBeUndefined()
    expect(pinyinOf('SK 海力士')).toEqual(['HAILISHI', 'HLS'])
  })

  it('1000 倍合约也认拼音：peipei → 1000PEPEUSDT', () => {
    expect(matchOne('1000PEPEUSDT', '1000PEPE', normalize('peipei'))?.tier).toBe(Tier.cnPrefix)
  })

  it('排名：搜 yitai，以太坊排在只是代号碰巧含字母的品种前面', () => {
    const out = rank([sym('YGGUSDT', 9e9), sym('ETHUSDT', 1)], 'yitai')
    expect(out.map(r => r.item.symbol)).toEqual(['ETHUSDT'])
  })
})
