// 搜索页对比模式的纯判定（照 iOS CompareSearchModeTests，2026-10-05）
import { describe, expect, it } from 'vitest'
import { CompareSearchMode, COMPARE_FULL_NOTICE, compareKeyOf } from '../src/m/model/compareMode'
import { listRowHTML, factsOf } from '../src/m/model/rowHTML'

describe('compareKeyOf：裸代号 / 规范键都归到规范键', () => {
  it('币安合约与美元指数', () => {
    expect(compareKeyOf('ETHUSDT')).toBe('binance/usd_m/ETHUSDT')
    expect(compareKeyOf('binance/usd_m/ETHUSDT')).toBe('binance/usd_m/ETHUSDT')
    expect(compareKeyOf('DXY')).toBe('macro/index/DXY')
    expect(compareKeyOf('macro/index/DXY')).toBe('macro/index/DXY')
    // 2026-10-08 起别家的完整键也认（原来只认币安与美元指数）
    expect(compareKeyOf('coinbase/spot/BTC-USD')).toBe('coinbase/spot/BTC-USD')
    expect(compareKeyOf('okx/usd_m/ETHUSDT')).toBe('okx/usd_m/ETHUSDT')
    expect(compareKeyOf('kraken/spot/BTC-USD')).toBeNull()
  })
})

describe('CompareSearchMode', () => {
  it('主图那只整行禁用、点了什么都不做', () => {
    const m = new CompareSearchMode([], 'BTCUSDT')
    expect(m.state('BTCUSDT')).toBe('main')
    expect(m.action('BTCUSDT')).toEqual({ kind: 'none' })
  })
  it('可加 → 加进集合；已加 → 再点拿掉', () => {
    const m = new CompareSearchMode(['binance/usd_m/ETHUSDT'], 'BTCUSDT')
    expect(m.state('SOLUSDT')).toBe('add')
    expect(m.state('ETHUSDT')).toBe('added')
    const add = m.action('DXY')
    expect(add).toEqual({ kind: 'add', key: 'macro/index/DXY' })
    expect(m.apply(add)).toEqual(['binance/usd_m/ETHUSDT', 'macro/index/DXY'])
    const rm = m.action('ETHUSDT')
    expect(rm).toEqual({ kind: 'remove', key: 'binance/usd_m/ETHUSDT' })
    expect(m.apply(rm)).toEqual([])
  })
  it('满三只：别的行退成禁用色，点了只提示；已加的仍能拿掉', () => {
    const m = new CompareSearchMode(['ETHUSDT', 'binance/usd_m/SOLUSDT', 'macro/index/DXY'], 'BTCUSDT')
    expect(m.isFull).toBe(true)
    expect(m.state('XRPUSDT')).toBe('full')
    expect(m.action('XRPUSDT')).toEqual({ kind: 'rejectFull' })
    expect(m.state('DXY')).toBe('added')
    expect(m.action('SOLUSDT').kind).toBe('remove')
    expect(COMPARE_FULL_NOTICE).toBe('最多对比 3 个品种')
  })
  it('主图是美元指数时，它那一行也是主图', () => {
    const m = new CompareSearchMode([], 'DXY')
    expect(m.state('DXY')).toBe('main')
    expect(m.state('macro/index/DXY')).toBe('main')
  })
})

describe('对比模式的行尾', () => {
  const html = (cmp?: 'add' | 'added' | 'full' | 'main') =>
    listRowHTML(factsOf('ETHUSDT', undefined), { price: 1, pct: 1, meta: 'ETHUSDT 永续', fav: false, cmp })
  it('普通搜索仍是星', () => {
    expect(html()).toContain('data-star="ETHUSDT"')
    expect(html()).not.toContain('data-cmp')
  })
  it('对比模式换成 ＋ / ✓，主图整行禁用', () => {
    expect(html('add')).toContain('class="sr-cmp add" data-cmp="ETHUSDT"')
    expect(html('add')).not.toContain('data-star')
    expect(html('added')).toContain('aria-label="移除对比"')
    expect(html('full')).toContain('aria-description="已满"')
    expect(html('main')).toContain('class="sr cmp-main"')
    expect(html('main')).toContain('aria-disabled="true"')
  })
})
