// G 线走查：电脑网页搜「BTC/USDT」「btc usdt」「ＢＴＣ」「eth-usdt」「大饼」「hj」全是「没有找到」，
// 手机网页搜全角「ｂｔｃ」也是「没有这个品种」——PC 只做了大写，手机只剥分隔符没折全角。
import { describe, it, expect } from 'vitest'
import { rankSearch, matchScore, type Sym } from '../src/market/symbols'
import { normalize, rank } from '../src/m/model/search'

const mk = (symbol: string, code: string, cn = '', vol = 1): Sym => ({ symbol, code, base: code, cn, vol, kind: 'crypto' } as unknown as Sym)
const pool: Sym[] = [
  mk('BTCUSDT', 'BTC', '比特币', 9e9), mk('BTCDOMUSDT', 'BTCDOM', '', 1e6), mk('ETHUSDT', 'ETH', '以太坊', 5e9), mk('ETHFIUSDT', 'ETHFI', '', 1e8),
  mk('龙虾USDT', '龙虾', '', 2e7), mk('XAUUSDT', 'XAU', '黄金', 3e8), mk('1000PEPEUSDT', 'PEPE', '佩佩', 4e8), mk('NVDAUSDT', 'NVDA', '英伟达', 2e8),
]
const top = (q: string) => rankSearch(pool, q)[0]?.symbol

describe('电脑网页搜品种的归一与别名', () => {
  it('分隔符、空格、全角、大小写都等于连写', () => {
    expect(top('BTC/USDT')).toBe('BTCUSDT')
    expect(top('btc usdt')).toBe('BTCUSDT')
    expect(top('ＢＴＣ')).toBe('BTCUSDT')
    expect(top('eth-usdt')).toBe('ETHUSDT')
    expect(top(' btc ')).toBe('BTCUSDT')
  })
  it('中文常用叫法与全拼 / 首字母也认（和手机、iOS 同一张表）', () => {
    expect(top('大饼')).toBe('BTCUSDT')
    expect(top('dabing')).toBe('BTCUSDT')
    expect(top('hj')).toBe('XAUUSDT')
    expect(top('英伟达')).toBe('NVDAUSDT')
  })
  it('去掉 1000 前缀的代号照代号前缀算，打全了排第一', () => {
    expect(top('pepe')).toBe('1000PEPEUSDT')
    expect(matchScore(pool[0], 'BTC')).toBeGreaterThan(matchScore(pool[1], 'BTC'))
  })
  it('空查询（含只有分隔符）不过滤', () => {
    expect(rankSearch(pool, '').length).toBe(pool.length)
    expect(rankSearch(pool, ' / ').length).toBe(pool.length)
  })
  it('不相干的字不命中', () => {
    expect(rankSearch(pool, 'zzzz')).toEqual([])
  })
})

describe('手机网页搜品种认全角', () => {
  it('normalize 把全角字母数字与符号折成半角', () => {
    expect(normalize('ｂｔｃ')).toBe('BTC')
    expect(normalize('ＢＴＣ／ＵＳＤＴ')).toBe('BTCUSDT')
    expect(normalize('１０００ｐｅｐｅ')).toBe('1000PEPE')
  })
  it('全角「ｂｔｃ」搜到 BTC', () => {
    const list = pool.map(s => ({ symbol: s.symbol, vol: s.vol, price: 1 }))
    expect(rank(list, 'ｂｔｃ')[0]?.item.symbol).toBe('BTCUSDT')
  })
})
