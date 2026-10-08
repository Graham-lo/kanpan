// 手机网页版体感优化（2026-10-07）：K 线先取一小页后台补满 + 共用缓存、换品种提示、上次的价与品种表、板块骨架
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  BAR_CACHE_KEY, BAR_DISK_KEYS, BAR_MEM_KEYS, BarCache, FIRST_PAGE, HISTORY_PAGE, backfillLimit, cacheConnects, pageExhausted,
} from '../src/m/chart/barCache'
import type { Bar } from '../src/m/chart/series'
import { switchCue } from '../src/m/pages/chart/logic'
import { SKELETON_ROWS, boardsWaiting, drillWaiting, skeletonRowsHTML } from '../src/m/model/sectorView'
import {
  QUOTE_CACHE_KEY, QUOTE_KEEP_MS, _resetQuoteCache, cachedSym, cachedTable, compact, expand, readQuotes, symForDisplay, symbolsForDisplay, writeQuotes,
} from '../src/m/model/quoteCache'
import { S } from '../src/market'
import type { Sym } from '../src/market/symbols'

class MemStore {
  m = new Map<string, string>()
  getItem(k: string): string | null { return this.m.get(k) ?? null }
  setItem(k: string, v: string): void { this.m.set(k, v) }
  removeItem(k: string): void { this.m.delete(k) }
}
let store: MemStore
beforeEach(() => { store = new MemStore(); (globalThis as { localStorage?: unknown }).localStorage = store })
afterEach(() => { delete (globalThis as { localStorage?: unknown }).localStorage; vi.useRealTimers() })

const H = 3_600_000
const bars = (n: number, last: number, step = H): Bar[] =>
  Array.from({ length: n }, (_, i) => { const c = 100 + i; return { openTime: last - (n - 1 - i) * step, open: c, high: c + 1, low: c - 1, close: c, volume: 10, takerBuy: i % 2 ? 4 : NaN } })

describe('B5 · 首屏一小页、后台补满', () => {
  it('首屏 300、补到 1500', () => {
    expect(FIRST_PAGE).toBe(300)
    expect(HISTORY_PAGE).toBe(1500)
  })
  it('已有不到 1500 根、左边没到头：补差额；够了 / 到头 / 换了取数口不补', () => {
    expect(backfillLimit(300, false, 300)).toBe(1200)
    expect(backfillLimit(1499, false, 300)).toBe(1)
    expect(backfillLimit(1500, false, 300)).toBeNull()
    expect(backfillLimit(300, true, 300)).toBeNull()
    expect(backfillLimit(300, false, null)).toBeNull()
    expect(backfillLimit(0, false, 300)).toBeNull()
  })
  it('取到的比要的少就是到头了', () => {
    expect(pageExhausted(120, 300)).toBe(true)
    expect(pageExhausted(300, 300)).toBe(false)
  })
  it('缓存接得上马上要取的那一小页才拿来先画', () => {
    const now = 1_000 * H
    expect(cacheConnects(now - 10 * H, '1h', now)).toBe(true)
    expect(cacheConnects(now - 279 * H, '1h', now)).toBe(true)
    expect(cacheConnects(now - 281 * H, '1h', now)).toBe(false)
    expect(cacheConnects(now - 2 * H, '1m', now)).toBe(true)
    expect(cacheConnects(now - 6 * H, '1m', now)).toBe(false)
    expect(cacheConnects(0, '1h', now)).toBe(false)
  })
})

describe('B5 · 共用 K 线缓存', () => {
  const now = 2_000 * H
  const mk = () => new BarCache(() => store, () => now, 10)

  it('记下拷一份、拿出来也是拷一份（引擎手里的序列被推送改不连累缓存）', () => {
    const c = mk()
    const src = bars(500, now - H)
    c.put('btcusdt', '1h', src)
    src[499].close = -1
    const a = c.take('BTCUSDT', '1h')!
    expect(a).toHaveLength(500)
    expect(a[499].close).toBe(599)
    a[0].close = -2
    expect(c.take('BTCUSDT', '1h')![0].close).toBe(100)
    c.clear()
  })

  it('内存里最多 1500 根、12 只', () => {
    const c = mk()
    c.put('A', '1h', bars(2000, now - H))
    expect(c.take('A', '1h')).toHaveLength(HISTORY_PAGE)
    for (let i = 0; i < BAR_MEM_KEYS + 3; i++) c.put(`S${i}`, '1h', bars(5, now - H))
    expect(c.has('S0', '1h')).toBe(false)
    expect(c.has(`S${BAR_MEM_KEYS + 2}`, '1h')).toBe(true)
    c.clear()
  })

  it('离开太久接不上的不给（免得先画旧图再整条跳）', () => {
    const c = mk()
    c.put('A', '1m', bars(300, now - 10 * H, 60_000))
    expect(c.take('A', '1m')).toBeNull()
    c.clear()
  })

  it('落盘最近 4 只、各末 300 根；重开页（新的一份）读得回来，主动买缺失照旧是 NaN', () => {
    vi.useFakeTimers()
    const c = mk()
    for (let i = 0; i < 6; i++) c.put(`S${i}`, '1h', bars(800, now - H))
    vi.advanceTimersByTime(20)
    const raw = JSON.parse(store.getItem(BAR_CACHE_KEY)!) as { e: { k: string; r: unknown[] }[] }
    expect(raw.e.map(x => x.k)).toEqual(['S2|1h', 'S3|1h', 'S4|1h', 'S5|1h'])
    expect(raw.e.every(x => x.r.length === FIRST_PAGE)).toBe(true)
    expect(BAR_DISK_KEYS).toBe(4)
    const again = mk()
    const got = again.take('S5', '1h')!
    expect(got).toHaveLength(FIRST_PAGE)
    expect(got[got.length - 1].openTime).toBe(now - H)
    expect(got[got.length - 1].takerBuy).toBe(4)
    expect(Number.isNaN(got[got.length - 2].takerBuy)).toBe(true)
    expect(again.take('S0', '1h')).toBeNull()
  })

  it('落盘那份坏了当没有', () => {
    store.setItem(BAR_CACHE_KEY, '{bad')
    expect(mk().take('A', '1h')).toBeNull()
  })
})

describe('B4 · 换品种 / 周期取数那一拍的提示', () => {
  const drawn = { symbol: 'BTCUSDT', interval: '1h' }
  it('图上还是上一只：淡下去 + 细条', () => {
    expect(switchCue({ loading: true, error: null }, drawn, 'ETHUSDT', '1h')).toEqual({ busy: true, fade: true })
    expect(switchCue({ loading: true, error: null }, drawn, 'BTCUSDT', '4h')).toEqual({ busy: true, fade: true })
  })
  it('图上就是这一只（缓存先画了）：不淡，只走细条；什么都没画也只走细条', () => {
    expect(switchCue({ loading: true, error: null }, drawn, 'btcusdt', '1h')).toEqual({ busy: true, fade: false })
    expect(switchCue({ loading: true, error: null }, null, 'BTCUSDT', '1h')).toEqual({ busy: true, fade: false })
  })
  it('取到了 / 出错了：立刻恢复', () => {
    expect(switchCue({ loading: false, error: null }, drawn, 'ETHUSDT', '1h')).toEqual({ busy: false, fade: false })
    expect(switchCue({ loading: false, error: 'x' }, drawn, 'ETHUSDT', '1h')).toEqual({ busy: false, fade: false })
  })
})

describe('B7 / B9 · 上次的价与品种表', () => {
  const sym = (symbol: string, price: number | null, pct: number | null): Sym => ({
    symbol, venue: 'binance', quote: 'USDT', base: symbol.replace(/USDT$/, ''), code: symbol.replace(/USDT$/, ''), kind: 'crypto', cn: '', dec: 2, color: '#000',
    price, chg: 1, pct, vol: 1e6, fr: 0.0001, nextFunding: 1, tags: ['layer-1'], onboard: 5, mark: 1, lastTick: 9,
  })
  beforeEach(() => { _resetQuoteCache(); S.symbols.clear(); S.live = null })
  afterEach(() => { _resetQuoteCache(); S.symbols.clear(); S.live = null })

  it('只记展示要用的那几列；实时字段（费率、标记价）不记', () => {
    const c = compact(sym('BTCUSDT', 62000, 1.5))
    expect(c).toMatchObject({ symbol: 'BTCUSDT', price: 62000, pct: 1.5, tags: ['layer-1'], onboard: 5 })
    expect('fr' in c || 'mark' in c || 'lastTick' in c).toBe(false)
    expect(expand(c)).toMatchObject({ fr: null, nextFunding: null, price: 62000 })
  })

  it('读写；太旧的不拿来顶', () => {
    const now = 1_000_000_000_000
    writeQuotes([compact(sym('BTCUSDT', 1, 1))], store, now)
    expect(readQuotes(store, now + 1000)?.rows).toHaveLength(1)
    expect(readQuotes(store, now + QUOTE_KEEP_MS + 1)).toBeNull()
    store.setItem(QUOTE_CACHE_KEY, 'nope')
    expect(readQuotes(store, now)).toBeNull()
  })

  it('实时表没到：用上次的（标 cached）；到了用实时的；到了却没有这只（下架）不拿旧价顶', () => {
    writeQuotes([compact(sym('BTCUSDT', 61000, -0.5)), compact(sym('ETHUSDT', 2500, 2))], store)
    expect(cachedSym('btcusdt')?.price).toBe(61000)
    expect(cachedTable()).toHaveLength(2)
    expect(symbolsForDisplay()).toMatchObject({ cached: true })
    expect(symForDisplay('BTCUSDT')).toMatchObject({ cached: true, s: { price: 61000 } })
    S.symbols.set('BTCUSDT', sym('BTCUSDT', 62000, 1))
    S.live = true
    expect(symForDisplay('BTCUSDT')).toMatchObject({ cached: false, s: { price: 62000 } })
    expect(symForDisplay('ETHUSDT')).toEqual({ s: null, cached: false })
    expect(symbolsForDisplay()).toMatchObject({ cached: false })
    expect(symbolsForDisplay().list).toHaveLength(1)
  })

  it('不往实时表里写', () => {
    writeQuotes([compact(sym('BTCUSDT', 61000, -0.5))], store)
    cachedTable(); cachedSym('BTCUSDT')
    expect(S.symbols.size).toBe(0)
  })
})

describe('B8 · 板块页骨架', () => {
  it('板块一行都没算出来、也没判定取不到：摆骨架；取不到就不摆', () => {
    expect(boardsWaiting(0, false)).toBe(true)
    expect(boardsWaiting(0, true)).toBe(false)
    expect(boardsWaiting(3, false)).toBe(false)
  })
  it('钻进去的板块：行情一只都还没到才摆', () => {
    expect(drillWaiting(0, 0)).toBe(true)
    expect(drillWaiting(0, 10)).toBe(false)
    expect(drillWaiting(5, 0)).toBe(false)
  })
  it('一屏 7 行，不可点、读屏跳过，第一行不画顶线', () => {
    expect(SKELETON_ROWS).toBe(7)
    const html = skeletonRowsHTML('board')
    expect(html.match(/class="sec-skel board/g)).toHaveLength(7)
    expect(html).toContain('sec-skel board first')
    expect(html).not.toContain('data-sec')
    expect(html.match(/aria-hidden="true"/g)).toHaveLength(7)
    const sym = skeletonRowsHTML('symbol', 8)
    expect(sym.match(/sk-pill/g)).toHaveLength(8)
    expect(sym).not.toContain('data-sym')
  })
})

describe('B7 · 上次的涨跌照写、退成弱墨', () => {
  it('休市 / 上次记下的：药丸写字（不是骨架），不着涨跌色', async () => {
    const { pillHTML } = await import('../src/m/model/rowHTML')
    const h = pillHTML(1.5, undefined, false, true)
    expect(h).toContain('m-pill none muted')
    expect(h).toContain('+1.50%')
    expect(h).not.toMatch(/m-pill (up|down)/)
    expect(pillHTML(null, undefined, false, true)).toBe(pillHTML(null))
  })
})
