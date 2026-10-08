/* 极端 · 本机存档：别家整表很大（几千行）时
 *   电脑 saveUniverse 只记币安 + 美元指数，落盘体积有上限、读回来没有别家的行；
 *   手机行情缓存（m/model/quoteCache）只记币安整表 + 自选等几只别家的，跟着推送记的频率 ≤ 每 10 秒一次；
 * 旧存档（只有币安裸代号、没有 venue 字段）升级后读得出、不丢自选；完整三段写的币安键收回裸代号、不重复。 */
import { afterEach, describe, expect, it, vi } from 'vitest'
import { readUniverse, saveUniverse, UNIVERSE_CACHE_KEY } from '../src/market/rest'
import { hydrate } from '../src/app/store'
import { hydrate as mHydrate } from '../src/m/app/store'
import { expand, readQuotes, QUOTE_CACHE_KEY, QUOTE_SAVE_MS } from '../src/m/model/quoteCache'
import { parseKey } from '../src/market/identity'
import type { Sym } from '../src/market/symbols'

const NOW = 1_800_000_000_000
const mk = (symbol: string, i: number): Sym => ({
  symbol, venue: symbol === 'DXY' ? 'macro' : parseKey(symbol).venue, quote: 'USDT', base: `C${i}`, code: `C${i}`, kind: 'crypto', cn: '', dec: 4, color: '#123456',
  price: 1 + i, chg: 0.1, pct: 1.5, vol: 1e6 + i, fr: 0.0001, nextFunding: NOW + 3600e3, open: 1, hi: 2, lo: 0.5, count: 9, mark: 1, index: 1, pxAt: NOW, statAt: NOW, markAt: NOW,
  ...(symbol === 'DXY' ? { macro: true, kind: 'idx' as const, quote: '' } : {}),
})
/** 币安 700 只 + 美元指数 + 别家四家各 1500 只 */
function bigTable(): Map<string, Sym> {
  const m = new Map<string, Sym>()
  for (let i = 0; i < 700; i++) m.set(`C${i}USDT`, mk(`C${i}USDT`, i))
  m.set('DXY', mk('DXY', 0))
  for (let i = 0; i < 1500; i++) for (const k of [`okx/usd_m/C${i}USDT`, `bybit/usd_m/C${i}USDT`, `hyperliquid/usd_m/C${i}`, `coinbase/spot/C${i}-USD`]) m.set(k, { ...mk(k, i), raw: k, title: `c${i}` })
  return m
}
class MemStore {
  map = new Map<string, string>(); writes = 0; last = 0
  getItem(k: string): string | null { return this.map.get(k) ?? null }
  setItem(k: string, v: string): void { this.writes++; this.last = v.length; this.map.set(k, v) }
  removeItem(k: string): void { this.map.delete(k) }
  key(): null { return null }
  clear(): void { this.map.clear() }
  get length(): number { return this.map.size }
}

afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); vi.resetModules() })

describe('电脑：全市场表的本机副本', () => {
  it('别家 6000 行在 S.symbols 里：只记币安 701 行（含美元指数），体积 < 200 KB；读回来没有别家的行', () => {
    const store = new MemStore()
    const t = bigTable()
    expect(t.size).toBe(6701)
    expect(saveUniverse(t, store as unknown as Storage)).toBe(true)
    expect(store.writes).toBe(1)
    const saved = JSON.parse(store.getItem(UNIVERSE_CACHE_KEY)!) as { rows: unknown[][] }
    expect(saved.rows.length).toBe(701)
    expect(saved.rows.every(r => !String(r[0]).includes('/'))).toBe(true)
    expect(store.last).toBeLessThan(200_000)
    const back = readUniverse(store as unknown as Storage, Date.now())!
    expect(back.size).toBe(701)
    expect([...back.keys()].some(k => k.includes('/'))).toBe(false)
  })
  it('有人往这份里塞了别家的行（老版本 / 手改）：读的时候丢掉，不当币安的品种', () => {
    const store = new MemStore()
    store.setItem(UNIVERSE_CACHE_KEY, JSON.stringify({ v: 1, at: Date.now(), rows: [['BTCUSDT', 'BTC', 'COIN', 1, 0, '', 100, 0, 0], ['okx/usd_m/BTCUSDT', 'BTC', '', 1, 0, '', 100, 0, 0]] }))
    expect([...readUniverse(store as unknown as Storage)!.keys()]).toEqual(['BTCUSDT'])
  })
  it('旧格式的行（字段比现在少，没有 pxAt / supply / 美元指数中文名那几格）：照读，缺的给空', () => {
    const store = new MemStore()
    store.setItem(UNIVERSE_CACHE_KEY, JSON.stringify({ v: 1, at: Date.now(), rows: [['BTCUSDT', 'BTC', 'COIN', 1, 0, '', 100, 1, 1, 99, 101, 98, 5e9]] }))
    const s = readUniverse(store as unknown as Storage)!.get('BTCUSDT')!
    expect(s).toMatchObject({ symbol: 'BTCUSDT', venue: 'binance', quote: 'USDT', price: 100, vol: 5e9, pxAt: 0 })
  })
})

describe('手机：行情缓存（只记币安整表 + 自选等几只别家）', () => {
  it('别家 6000 行、推送每 50 ms 一跳挂 2 分钟：最多每 10 秒落一次盘，每次只有 701 + 自选里那 3 只别家', async () => {
    vi.useFakeTimers({ now: NOW })
    const store = new MemStore()
    const listeners: Record<string, (() => void)[]> = {}
    vi.stubGlobal('localStorage', store)
    vi.stubGlobal('window', {})
    vi.stubGlobal('addEventListener', (t: string, f: () => void) => { (listeners[t] ??= []).push(f) })
    vi.stubGlobal('document', { hidden: false, visibilityState: 'visible', addEventListener: () => {} })
    vi.resetModules()
    const qc = await import('../src/m/model/quoteCache')
    const { S, emit } = await import('../src/market/state')
    S.symbols = bigTable(); S.live = true
    const extra = ['okx/usd_m/C1USDT', 'hyperliquid/usd_m/C2', 'coinbase/spot/C3-USD']
    qc.setQuoteCacheExtra(() => extra)
    qc.install()
    emit({ type: 'universe' })
    const before = store.writes
    for (let t = 0; t < 120_000; t += 50) { emit({ type: 'ticker', symbol: 'okx/usd_m/C1USDT', dir: 1 }); await vi.advanceTimersByTimeAsync(50) }
    const writes = store.writes - before
    expect(writes).toBeGreaterThan(0)
    expect(writes).toBeLessThanOrEqual(Math.ceil(120_000 / QUOTE_SAVE_MS) + 1)
    const saved = readQuotes(store, Date.now())!
    expect(saved.rows.length).toBe(701 + 3)
    expect(saved.rows.filter(r => r.symbol.includes('/')).map(r => r.symbol).sort()).toEqual([...extra].sort())
    expect(store.last).toBeLessThan(150_000)
    // 别家的行记着计价币与原名：表没到时「HL c2 / USDC」照样写得出来
    expect(saved.rows.find(r => r.symbol === 'hyperliquid/usd_m/C2')).toMatchObject({ raw: 'hyperliquid/usd_m/C2', title: 'c2' })
    // 关页补记一次
    const w = store.writes
    listeners.pagehide?.forEach(f => f())
    expect(store.writes).toBe(w + 1)
    qc._resetQuoteCache()
  })
  it('旧缓存（只有币安裸代号、没有 venue / quote）展开成币安 USDT；别家的行没记计价币时按注册表那一家', () => {
    expect(expand({ symbol: 'BTCUSDT', base: 'BTC', code: 'BTC', kind: 'crypto', cn: '', dec: 1, color: '', price: 1, chg: 0, pct: 0, vol: 0 })).toMatchObject({ venue: 'binance', quote: 'USDT' })
    expect(expand({ symbol: 'hyperliquid/usd_m/BTC', base: 'BTC', code: 'BTC', kind: 'crypto', cn: '', dec: 1, color: '', price: 1, chg: 0, pct: 0, vol: 0 })).toMatchObject({ venue: 'hyperliquid', quote: 'USDC' })
    expect(expand({ symbol: 'coinbase/spot/BTC-USD', base: 'BTC', code: 'BTC', kind: 'crypto', cn: '', dec: 1, color: '', price: 1, chg: 0, pct: 0, vol: 0 })).toMatchObject({ venue: 'coinbase', quote: 'USD' })
    expect(expand({ symbol: 'DXY', base: 'DXY', code: 'DXY', kind: 'idx', cn: '', dec: 1, color: '', price: 1, chg: 0, pct: 0, vol: 0, macro: true })).toMatchObject({ venue: 'macro', quote: '' })
    const store = new MemStore()
    store.setItem(QUOTE_CACHE_KEY, '{"at":1,"rows":[]}')
    expect(readQuotes(store, NOW)).toBeNull()   // 太老
    store.setItem(QUOTE_CACHE_KEY, '{bad')
    expect(readQuotes(store, NOW)).toBeNull()
  })
})

describe('旧存档升级：只有币安裸代号、没有 venue 字段', () => {
  it('电脑：自选、格子、对比照读；完整三段写的币安键收回裸代号并去重，别家完整键原样', () => {
    const s = hydrate({
      watch: { crypto: ['BTCUSDT', '1000PEPEUSDT', '币安人生USDT', 'binance/usd_m/BTCUSDT', 'okx/usd_m/BTCUSDT'], us: ['NVDAUSDT'], com: ['XAUUSDT'], idx: ['DXY', 'macro/index/DXY'] },
      cells: [{ symbol: 'ETHUSDT', iv: '4h' }, { symbol: 'binance/usd_m/SOLUSDT', iv: '1h' }],
      layout: '2',
      compareSymbols: ['ETHUSDT', 'okx/usd_m/BTCUSDT'],
    } as never)
    expect(s.watch.crypto).toEqual(['BTCUSDT', '1000PEPEUSDT', '币安人生USDT', 'okx/usd_m/BTCUSDT'])
    expect(s.watch.us).toEqual(['NVDAUSDT'])
    expect(s.watch.com).toEqual(['XAUUSDT'])
    expect(s.watch.idx).toEqual(['DXY'])
    expect(s.cells.slice(0, 2).map(c => c.symbol)).toEqual(['ETHUSDT', 'SOLUSDT'])
    expect(s.compareSymbols).toEqual(['binance/usd_m/ETHUSDT', 'okx/usd_m/BTCUSDT'])
  })
  it('手机：自选与分组归属照读', () => {
    const s = mHydrate({ symbols: { favorites: ['BTCUSDT', 'ETHUSDT', 'okx/usd_m/BTCUSDT'], recents: ['SOLUSDT'], groups: [{ id: 'g1', name: '加密' }], groupForSymbol: { BTCUSDT: 'g1' }, seeded: true }, symbol: 'ETHUSDT' })
    expect(s.symbols.favorites).toEqual(['BTCUSDT', 'ETHUSDT', 'okx/usd_m/BTCUSDT'])
    expect(s.symbols.groupForSymbol).toEqual({ BTCUSDT: 'g1' })
    expect(s.symbol).toBe('ETHUSDT')
  })
})
