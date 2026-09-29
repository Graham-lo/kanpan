/* 手机网页版收尾审查（同步与壳）：对比品种键与服务端 compare_key 同一条规则（能收藏就能对比） */
import { describe, expect, it } from 'vitest'
import { cleanCompare, defaultPrefs } from '../src/m/app/prefs'
import { applySettings, encodeSettings, settingsBody } from '../src/m/app/syncCodec'
import { compareKey, instrumentIdentity, validSymbol } from '../src/sync/codec'

describe('对比品种键（prefs.cleanCompare → sync/codec.compareKey）', () => {
  it('中文底名的币安合约能加进来（带前缀与裸代号两种写法）', () => {
    expect(cleanCompare(['binance/usd_m/币安人生USDT'])).toEqual(['binance/usd_m/币安人生USDT'])
    expect(cleanCompare(['币安人生USDT', 'ethusdt'])).toEqual(['binance/usd_m/币安人生USDT', 'binance/usd_m/ETHUSDT'])
  })

  it('按交易所分流：Coinbase 现货是 BASE-USD；别的交易所 / 市场、各自规则外的代号一律丢', () => {
    expect(cleanCompare(['coinbase/spot/BTC-USD'])).toEqual(['coinbase/spot/BTC-USD'])
    expect(cleanCompare([
      'coinbase/spot/币-USD',          // Coinbase 底名只有 ASCII
      'coinbase/spot/BTCUSDT',         // 币安代号挂在 Coinbase 下
      'binance/usd_m/BTC-USD',         // Coinbase 代号挂在币安下
      'okx/swap/BTCUSDT',              // 服务端只认两种
      'binance/spot/BTCUSDT',
      'binance/usd_m/USDT',            // 只有计价币
      'binance/usd_m/btcusdt',         // 带前缀的不改大小写
      'binance/usd_m/BTC_USDT',
      'binance/usd_m/BTC/USDT',
    ])).toEqual([])
  })

  it('长度按 UTF-8 字节算（服务端 s.len()），代号本身按字符数最多 40', () => {
    const base = '币'.repeat(36)                       // 36 + 4 = 40 字符、112 字节，整串 126 字节
    expect(validSymbol(base + 'USDT')).toBe(true)
    expect(compareKey('binance/usd_m/' + base + 'USDT')).toBe(true)
    expect(compareKey('binance/usd_m/' + '币'.repeat(37) + 'USDT')).toBe(false)
  })

  it('与自选同一套身份规则', () => {
    expect(instrumentIdentity('binance', 'usd_m', '币安人生USDT')).toBe(true)
    expect(instrumentIdentity('coinbase', 'spot', 'ETH-USD')).toBe(true)
    expect(instrumentIdentity('coinbase', 'usd_m', 'ETH-USD')).toBe(false)
  })

  it('能存能同步：进 settings 上云、另一台拉下来原样装回', () => {
    const a = defaultPrefs()
    a.compareSymbols = cleanCompare(['币安人生USDT', 'coinbase/spot/SOL-USD'])
    expect(settingsBody(a).compareSymbols).toEqual(['binance/usd_m/币安人生USDT', 'coinbase/spot/SOL-USD'])
    const cloud = encodeSettings(a, undefined, {})!
    const b = defaultPrefs()
    applySettings(b, cloud, {})
    expect(b.compareSymbols).toEqual(['binance/usd_m/币安人生USDT', 'coinbase/spot/SOL-USD'])
  })
})

describe('图上认得中文底名的对比键（m/chart/compare.source.compareSymbolOf）', () => {
  it('存下来的键图也取得到，不在引擎那层又被 ASCII 规则挡掉', async () => {
    const { compareSymbolOf, compareTargets } = await import('../src/m/chart/compare.source')
    expect(compareSymbolOf('binance/usd_m/币安人生USDT')).toBe('币安人生USDT')
    expect(compareTargets(cleanCompare(['币安人生USDT']), 'BTCUSDT').map(t => t.symbol)).toEqual(['币安人生USDT'])
  })
})
