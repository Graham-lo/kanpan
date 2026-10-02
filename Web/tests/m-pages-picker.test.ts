import { describe, expect, it } from 'vitest'
import { isNewListing, factsOf, liuliRowHTML, listRowHTML, NEW_LISTING_MS } from '../src/m/model/rowHTML'
import { historyChange, miniCandles, RecentKeys, PREVIEW_SPAN_TEXT, type PreviewBar } from '../src/m/model/preview'
import { applyFilter, buildSections, countText, marketOf, marketTitle, moreNote, tagsOf, ALL_LIMIT, SEARCH_LIMIT, MARKET_ORDER, type PickerSym } from '../src/m/model/picker'

const NOW = Date.UTC(2026, 9, 3, 12, 0, 0)
const DAY = 86_400_000

describe('手机网页版 · 「新」字记号', () => {
  it('上线 30 天内才挂；没给、非正、在未来都不挂', () => {
    expect(isNewListing(NOW - 5 * DAY, NOW)).toBe(true)
    expect(isNewListing(NOW - NEW_LISTING_MS, NOW)).toBe(true)
    expect(isNewListing(NOW - NEW_LISTING_MS - 1, NOW)).toBe(false)
    expect(isNewListing(undefined, NOW)).toBe(false)
    expect(isNewListing(0, NOW)).toBe(false)
    expect(isNewListing(-1, NOW)).toBe(false)
    expect(isNewListing(NOW + DAY, NOW)).toBe(false)
  })
  it('行里在名字后面摆一个「新」，老品种不摆', () => {
    const fresh = factsOf('ABCUSDT', { kind: 'crypto', cn: '', onboard: NOW - DAY }, NOW)
    const old = factsOf('BTCUSDT', { kind: 'crypto', cn: '', onboard: NOW - 400 * DAY }, NOW)
    expect(fresh.isNew).toBe(true)
    expect(old.isNew).toBe(false)
    const d = { price: 1, pct: 1, vol: 1 }
    expect(liuliRowHTML(fresh, d, true)).toContain('class="row-new"')
    expect(liuliRowHTML(old, d, true)).not.toContain('row-new')
    expect(listRowHTML(fresh, { price: 1, pct: 1, meta: 'ABCUSDT 永续', fav: false })).toContain('>新</span>')
  })
})

describe('手机网页版 · 长按预览卡', () => {
  const minute = (t: number, o: number): PreviewBar => ({ t, o, h: o, l: o, c: o })
  it('近 N 小时涨跌：取开盘 ≤ 目标时刻的那根 1 分钟线，拿它的开盘价比现价', () => {
    const target = NOW - 3_600_000
    const bars = [minute(target - 60_000, 90), minute(target, 100), minute(target + 60_000, 120)]
    expect(historyChange(bars, 110, 1, NOW)).toBeCloseTo(10)
    // 目标时刻落在一根 K 线的中间：仍是那一根
    expect(historyChange(bars, 110, 1, NOW + 30_000)).toBeCloseTo(10)
  })
  it('逐分钟走势对不上（缺根、还没到、开盘价不对、没现价）就给 null，不拿别的凑', () => {
    const target = NOW - 4 * 3_600_000
    expect(historyChange([minute(target - 120_000, 100)], 110, 4, NOW)).toBeNull()
    expect(historyChange([minute(target + 60_000, 100)], 110, 4, NOW)).toBeNull()
    expect(historyChange([minute(target, 0)], 110, 4, NOW)).toBeNull()
    expect(historyChange([minute(target, 100)], null, 4, NOW)).toBeNull()
    expect(historyChange([], 110, 4, NOW)).toBeNull()
  })
  it('迷你 K 线：格宽 × 0.62 夹在 1.2…5，实体至少 1 高，收 ≥ 开算涨', () => {
    const bars: PreviewBar[] = [
      { t: 0, o: 10, h: 12, l: 8, c: 11 },
      { t: 1, o: 11, h: 11, l: 9, c: 11 },
      { t: 2, o: 11, h: 11.5, l: 9.5, c: 10 },
    ]
    const g = miniCandles(bars, 300, 100)
    expect(g).toHaveLength(3)
    expect(g[0].bodyW).toBe(5)
    expect(g[0].x).toBeCloseTo(50)
    expect(g[0].wickTop).toBeCloseTo(0)
    expect(g[0].wickBottom).toBeCloseTo(100)
    expect(g[0].up).toBe(true)
    expect(g[1].bodyH).toBe(1)
    expect(g[1].up).toBe(true)
    expect(g[2].up).toBe(false)
    expect(miniCandles(bars, 3, 100)[0].bodyW).toBe(1.2)
    expect(miniCandles(bars.slice(0, 1), 300, 100)).toEqual([])
    expect(miniCandles([{ t: 0, o: 1, h: 1, l: 1, c: 1 }, { t: 1, o: 1, h: 1, l: 1, c: 1 }], 300, 100)).toEqual([])
  })
  it('最近用过：touch 挪到最后，超出容量从前面扔并报出来', () => {
    const r = new RecentKeys(2)
    expect(r.touch('A')).toEqual([])
    expect(r.touch('B')).toEqual([])
    expect(r.touch('A')).toEqual([])
    expect(r.keys).toEqual(['B', 'A'])
    expect(r.touch('C')).toEqual(['B'])
    expect(r.keys).toEqual(['A', 'C'])
  })
  it('卡头第二行', () => { expect(PREVIEW_SPAN_TEXT).toBe('1时 · 近 60 根') })
})

const sym = (symbol: string, over: Partial<PickerSym> = {}): PickerSym =>
  ({ symbol, base: symbol.replace(/USDT$/, ''), ut: 'COIN', vol: 0, price: 1, ...over })

describe('手机网页版 · 品种整页', () => {
  it('市场：贵金属按代号认，其余只看 underlyingType，缺了归「其他」不猜', () => {
    expect(marketOf({ base: 'XAU', ut: 'COMMODITY' })).toBe('metals')
    expect(marketOf({ base: 'BTC', ut: 'COIN' })).toBe('crypto')
    expect(marketOf({ base: 'NVDA', ut: 'EQUITY' })).toBe('us')
    expect(marketOf({ base: 'X', ut: 'HK_EQUITY' })).toBe('hk')
    expect(marketOf({ base: 'X', ut: 'KR_EQUITY' })).toBe('kr')
    expect(marketOf({ base: 'X', ut: 'CN_EQUITY' })).toBe('cn')
    expect(marketOf({ base: 'CL', ut: 'COMMODITY' })).toBe('commodities')
    expect(marketOf({ base: 'X', ut: 'INDEX' })).toBe('index')
    expect(marketOf({ base: 'X', ut: 'PREMARKET' })).toBe('premarket')
    expect(marketOf({ base: 'X', ut: 'FX' })).toBe('other')
    expect(marketOf({ base: 'X' })).toBe('other')
  })
  it('市场与板块的中文名；没收录的原样', () => {
    expect(marketTitle('all')).toBe('全部市场')
    expect(marketTitle('cn')).toBe('A股')
    expect(marketTitle('layer-1')).toBe('Layer 1')
    expect(marketTitle('chinese')).toBe('中国概念')
    expect(marketTitle('zk')).toBe('zk')
  })
  it('筛选：在场的市场按固定次序；板块从按市场筛过的那份里收，剔掉 crypto / tradfi', () => {
    const cat = [
      sym('BTCUSDT', { tags: ['PoW', 'crypto'] }),
      sym('DOGEUSDT', { tags: ['Meme', 'meme'] }),
      sym('NVDAUSDT', { ut: 'EQUITY', tags: ['TradFi', 'ai'] }),
      sym('XAUUSDT', { ut: 'COMMODITY' }),
    ]
    expect(tagsOf(cat[1])).toEqual(['meme'])
    const all = applyFilter(cat, 'all', null)
    expect(all.markets).toEqual(['crypto', 'us', 'metals'])
    expect(all.markets.every(m => (MARKET_ORDER as readonly string[]).includes(m))).toBe(true)
    expect(all.sectors).toEqual(['ai', 'meme', 'pow'])
    expect(all.list).toHaveLength(4)
    const crypto = applyFilter(cat, 'crypto', null)
    expect(crypto.sectors).toEqual(['meme', 'pow'])
    expect(crypto.list.map(s => s.symbol)).toEqual(['BTCUSDT', 'DOGEUSDT'])
    expect(applyFilter(cat, 'crypto', 'meme').list.map(s => s.symbol)).toEqual(['DOGEUSDT'])
  })
  it('没打字：自选 → 最近（剔掉自选）→ 全部合约（剔掉露过脸的，按成交额降序、同额保原序）', () => {
    const cat = [sym('AUSDT', { vol: 5 }), sym('BUSDT', { vol: 9 }), sym('CUSDT', { vol: 0 }), sym('DUSDT', { vol: 0 }), sym('EUSDT', { vol: 7 })]
    const secs = buildSections(cat, { query: '', favorites: ['BUSDT'], recents: ['BUSDT', 'EUSDT'], known: new Set(cat.map(s => s.symbol)) })
    expect(secs.map(s => s.title)).toEqual(['自选', '最近', '全部合约'])
    expect(secs[0].rows.map(r => r.symbol)).toEqual(['BUSDT'])
    expect(secs[1].rows.map(r => r.symbol)).toEqual(['EUSDT'])
    expect(secs[2].rows.map(r => r.symbol)).toEqual(['AUSDT', 'CUSDT', 'DUSDT'])
  })
  it('自选里品种表认得、只是被筛掉的不列；品种表不认得的（已下架）照旧列', () => {
    const cat = [sym('BTCUSDT'), sym('NVDAUSDT', { ut: 'EQUITY' })]
    const known = new Set(cat.map(s => s.symbol))
    const list = applyFilter(cat, 'crypto', null).list
    const secs = buildSections(list, { query: '', favorites: ['NVDAUSDT', 'GONEUSDT', 'BTCUSDT'], recents: [], known })
    expect(secs[0].rows.map(r => r.symbol)).toEqual(['GONEUSDT', 'BTCUSDT'])
    // 品种表还没到：自选照常列，不当它们是「不认得」
    expect(buildSections([], { query: '', favorites: ['BTCUSDT'], recents: [], known: new Set() })[0].rows.map(r => r.symbol)).toEqual(['BTCUSDT'])
  })
  it('全部合约 120 条封顶、搜索 160 条封顶，超出的给一行小字', () => {
    const cat = Array.from({ length: 200 }, (_, i) => sym(`S${i}XUSDT`, { vol: 200 - i }))
    const known = new Set(cat.map(s => s.symbol))
    const idle = buildSections(cat, { query: '', favorites: [], recents: [], known })
    expect(idle[0].rows).toHaveLength(ALL_LIMIT)
    expect(idle[0].more).toBe(80)
    expect(moreNote(idle[0].more)).toBe('还有 80 个，搜名字更快。')
    expect(moreNote(0)).toBeNull()
    const hit = buildSections(cat, { query: 'x', favorites: [], recents: [], known })
    expect(hit).toHaveLength(1)
    expect(hit[0].title).toBe('搜到 200 个')
    expect(hit[0].rows).toHaveLength(SEARCH_LIMIT)
    expect(hit[0].more).toBe(40)
  })
  it('打了字：只剩一组，先最匹配再按成交额，带高亮', () => {
    const cat = [sym('SOLUSDT', { vol: 1 }), sym('SOLVUSDT', { vol: 9 }), sym('ASOLUSDT', { vol: 99 })]
    const secs = buildSections(cat, { query: 'sol', favorites: ['ASOLUSDT'], recents: [], known: new Set(cat.map(s => s.symbol)) })
    expect(secs).toHaveLength(1)
    expect(secs[0].kind).toBe('search')
    expect(secs[0].rows.map(r => r.symbol)).toEqual(['SOLUSDT', 'SOLVUSDT', 'ASOLUSDT'])
    expect(secs[0].rows[0].hl).toEqual([0, 3])
    expect(buildSections(cat, { query: 'zzz', favorites: [], recents: [], known: new Set() })[0].rows).toEqual([])
  })
  it('页头计数', () => { expect(countText([sym('A'), sym('B')])).toBe('2 个永续合约') })
})
