/* 板块口径：用例与数字逐条照手机端
 *   KanpanCore/Tests/KanpanCoreTests/SectorTests.swift（「板块口径」「板块窗口」两组）
 *   Kanpan/KanpanTests/Sector/SectorRowTests.swift、SectorWindowChoiceTests.swift、SectorHistoryRetryTests.swift
 * 快照夹具直接读手机端那一份（2026-09-18 币安真实快照）。
 */
import { describe, expect, it } from 'vitest'
import FIXTURE from '../../KanpanCore/Tests/KanpanCoreTests/Fixtures/sectors.json'
import {
  EMPTY_HISTORY, TRADABLE_QUOTES, accepts, boardOrder, catalog, covered, decodeHistory, fallbackBuckets,
  hasEligible, historyRetryDelay, ingest, isFresh, isThin, jackknife, logReturn, median, memberSet, outperformCount,
  parseDay, prefers, quantile, quoteRank, rankable, resolveWindow, stats, subtitle, supersedes, symbolRows,
  windowMedian, windowReturn,
} from '../src/sectors/aggregate'
import type { Quotes, SectorBucket, SectorCloses, SectorHistory, SectorMarket, SectorQuote, SectorStat } from '../src/sectors/aggregate'

const TOL = 0.0051
const q = (base: string, pct: number, quoteVolume = 1, price = 1): SectorQuote => ({ base, pct, quoteVolume, price })
const quotesOf = (list: SectorQuote[]): Quotes => new Map(list.map(x => [x.base, x]))

interface FixtureMarket { quotes: Record<string, { chg?: number; vol?: number; price?: number }>; sectors: { id: string; name: string; n: number; median: number; vol: number; fallback: boolean }[]; fallbackBuckets: SectorBucket[] }
function snapshot(market: SectorMarket): { quotes: Quotes; rows: FixtureMarket['sectors']; buckets: SectorBucket[] } {
  const m = (FIXTURE as unknown as { markets: Record<string, FixtureMarket> }).markets[market]
  const quotes: Quotes = new Map()
  for (const [base, v] of Object.entries(m.quotes)) quotes.set(base, q(base, v.chg ?? 0, v.vol ?? 0, v.price ?? 0))
  return {
    quotes,
    rows: m.sectors.map(r => ({ id: r.id ?? '', name: r.name ?? '', n: r.n ?? 0, median: r.median ?? 0, vol: r.vol ?? 0, fallback: r.fallback ?? false })),
    buckets: m.fallbackBuckets.map(b => ({ id: b.id ?? '', name: b.name ?? '', members: b.members ?? [] })),
  }
}
/** 只给这几个 base 行情：市场池就是它们自己 */
const aggregate = (pcts: Record<string, number>): SectorStat[] =>
  stats('crypto', quotesOf(Object.entries(pcts).map(([b, p]) => q(b, p))), [])
const l1Of = (list: SectorStat[]): SectorStat => { const s = list.find(x => x.id === 'l1'); expect(s).toBeDefined(); return s! }

describe('板块口径 · 1. 目录完整性', () => {
  it('加密只有定义文件里那 24 个 id', () => {
    const want = new Set(['btc-eco', 'eth-eco', 'sol-eco', 'l1', 'l2', 'zk', 'defi-blue', 'perp-dex', 'stable-yield', 'rwa', 'ai', 'depin', 'storage-data', 'oracle-bridge', 'privacy', 'pow', 'meme', 'meme-cn', 'gamefi', 'nft-social', 'metaverse', 'payment', 'fan-token', 'desci'])
    expect(new Set(catalog.sectors('crypto').map(d => d.id))).toEqual(want)
    expect(catalog.sectors('crypto').length).toBe(24)
  })
  it('美股 12 段，顺序钉死', () => {
    expect(catalog.sectors('us').map(d => d.id)).toEqual(['gpu', 'mem', 'equip', 'optic', 'hyper', 'neo', 'server', 'power', 'edge', 'robot', 'software', 'app'])
    expect(catalog.sector('hardware')).toBeUndefined()
    expect(catalog.sector('gpu')?.members.length).toBe(10)
    for (const b of ['ARM', 'AVGO', 'ALAB']) expect(catalog.sector('gpu')?.members).toContain(b)
  })
  it('目录先加密后美股，id 唯一', () => {
    const all = catalog.all()
    expect(all.length).toBe(36)
    expect(all.slice(0, 24).every(d => d.market === 'crypto')).toBe(true)
    expect(all.slice(24).every(d => d.market === 'us')).toBe(true)
    expect(new Set(all.map(d => d.id)).size).toBe(all.length)
    for (const d of all) expect(catalog.sector(d.id)).toBe(d)
    expect(catalog.sector('silicon')).toBeUndefined()
  })
  it('成员全大写、不重复、非空', () => {
    for (const d of catalog.all()) {
      expect(d.members.length).toBeGreaterThan(0)
      expect(new Set(d.members).size).toBe(d.members.length)
      for (const b of d.members) { expect(b).toBe(b.toUpperCase()); expect(b).not.toBe('') }
      expect(d.name).not.toBe('')
    }
  })
  it('一币多板块、反查认市场', () => {
    expect(new Set(catalog.sectorsFor('SOL', 'crypto').map(d => d.id))).toEqual(new Set(['sol-eco', 'l1']))
    expect(new Set(catalog.sectorsFor('qcom', 'us').map(d => d.id))).toEqual(new Set(['gpu', 'edge']))
    expect(catalog.sectorsFor('BTC', 'crypto').map(d => d.id)).toEqual(['btc-eco', 'pow'])
    const counts = new Map<string, number>()
    for (const d of catalog.sectors('crypto')) for (const b of d.members) counts.set(b, (counts.get(b) || 0) + 1)
    expect(Math.max(...counts.values())).toBeLessThanOrEqual(3)
    expect(catalog.sectorsFor('ANKR', 'crypto')).toEqual([])
    expect(catalog.sectorsFor('SOL', 'us')).toEqual([])
  })
  it('杠杆 / ETF / 非 AI 一个都不在美股表里；94 只', () => {
    const banned = ['SOXL', 'SOXS', 'TQQQ', 'SQQQ', 'NVDL', 'UVXY', 'CSOPSAMSUNG2L', 'QQQ', 'SPY', 'SMH', 'IWM', 'BITO', 'DRAM', 'BOT', 'STRC', 'COIN', 'MSTR', 'TSM_X', 'NFLX', 'LLY', 'UBER', 'PYPL', 'HK0700', 'PAYP', 'SKDD', 'SKUU', 'MUU', 'SNXX', 'MVLL', 'RAM', 'CSOPSKHYNIX2L']
    const inTable = new Set(catalog.sectors('us').flatMap(d => d.members))
    for (const b of banned) expect(inTable.has(b)).toBe(false)
    expect(inTable.size).toBe(94)
    expect(inTable.has('SKHYNIX') && inTable.has('TENCENT') && inTable.has('SKHY')).toBe(true)
  })
  it('每只美股都有中文名', () => {
    for (const b of new Set(catalog.sectors('us').flatMap(d => d.members))) expect(catalog.chineseName(b)).toBeTruthy()
    expect(catalog.chineseName('nvda')).toBe('英伟达')
    expect(catalog.chineseName('SOL')).toBeUndefined()
  })
})

describe('板块口径 · 2. 中位数拿快照对数', () => {
  for (const market of ['crypto', 'us'] as const) {
    it(`${market} 每一段对得上快照`, () => {
      const snap = snapshot(market)
      const want = new Map(snap.rows.map(r => [r.id, r]))
      const got = stats(market, snap.quotes, snap.buckets)
      expect(got.length).toBeGreaterThan(0)
      for (const s of got) {
        const w = want.get(s.id)
        if (!w) { expect(s.id).toBe('desci'); continue }
        expect(Math.abs(s.pct - w.median), `${s.id}: ${s.pct} vs ${w.median}`).toBeLessThan(TOL)
        expect(s.memberCount).toBe(w.n)
        expect(Math.abs(s.quoteVolume - w.vol)).toBeLessThanOrEqual(Math.abs(w.vol) * 1e-9 + 1e-6)
        expect(s.isFallback).toBe(w.fallback)
      }
    })
  }
  it('24 段 + 4 桶，兜底桶排在后面；美股 12 段', () => {
    const snap = snapshot('crypto')
    const got = stats('crypto', snap.quotes, snap.buckets)
    expect(got.filter(s => !s.isFallback).length).toBe(24)
    expect(got.filter(s => s.isFallback).length).toBe(4)
    expect(got.findIndex(s => s.isFallback)).toBe(24)
    expect(stats('us', snapshot('us').quotes, []).length).toBe(12)
  })
  it('中位数', () => {
    expect(median([3, 1, 2])).toBe(2)
    expect(median([4, 1, 2, 3])).toBe(2.5)
    expect(median([7])).toBe(7)
    expect(median([1, 2, 3, 100])).toBe(2.5)
  })
  it('一只成员都没行情的板块直接消失', () => {
    const got = stats('crypto', quotesOf([q('SOL', 2, 10, 1)]), [])
    expect(new Set(got.map(s => s.id))).toEqual(new Set(['sol-eco', 'l1']))
    expect(got.every(s => s.memberCount === 1 && s.pct === 2)).toBe(true)
    expect(stats('crypto', new Map(), [])).toEqual([])
  })
  it('重复成员与非数行情丢掉', () => {
    const got = stats('crypto', quotesOf([q('ZZA', 5), q('ZZB', NaN)]), [{ id: 'fb-x', name: '其他', members: ['ZZA', 'zza', 'ZZB', 'ZZC'] }])
    expect(got).toEqual([{ id: 'fb-x', name: '其他', market: 'crypto', pct: 5, memberCount: 1, staticCount: 3, quoteVolume: 1, isFallback: true, breadth: 0, upCount: 1, frontier: [], jackknife: null }])
  })
})

describe('板块口径 · 3. 广度 / 领涨 / 删一', () => {
  it('一只暴涨进领涨，不进中位数', () => {
    const l1 = l1Of(aggregate({ ADA: -2, ALGO: -1, APT: 0, ATOM: 1, AVAX: 300 }))
    expect(l1.pct).toBe(0)
    expect(l1.memberCount).toBe(5)
    expect(l1.upCount).toBe(2)
    expect(outperformCount(l1)).toBe(1)
    expect(l1.breadth).toBe(0.2)
    expect(l1.frontier).toEqual(['AVAX'])
    expect(l1.jackknife).toEqual([-0.5, 0.5])
  })
  it('全部一样：没人跑赢、没有领涨、删一塌成一点', () => {
    const l1 = l1Of(aggregate({ ADA: 3, ALGO: 3, APT: 3, ATOM: 3, AVAX: 3 }))
    expect(l1.pct).toBe(3)
    expect(l1.upCount).toBe(5)
    expect(l1.breadth).toBe(0)
    expect(outperformCount(l1)).toBe(0)
    expect(l1.frontier).toEqual([])
    expect(l1.jackknife).toEqual([3, 3])
  })
  it('一两只有行情不算一个板块', () => {
    const counts = (p: Record<string, number>): boolean => hasEligible('crypto', quotesOf(Object.entries(p).map(([b, v]) => q(b, v))), 'today', EMPTY_HISTORY)
    const single = l1Of(aggregate({ ADA: 5 }))
    expect(single.memberCount === 1 && single.pct === 5).toBe(true)
    expect(single.jackknife).toBeNull()
    const pair = l1Of(aggregate({ ADA: 5, ALGO: 1 }))
    expect(pair.memberCount === 2 && pair.pct === 3).toBe(true)
    expect(pair.jackknife).toBeNull()
    expect(counts({ ADA: 5, ALGO: 1 })).toBe(false)
    const trio = l1Of(aggregate({ ADA: 5, ALGO: 1, APT: 3 }))
    expect(trio.memberCount).toBe(3)
    expect(trio.jackknife).not.toBeNull()
    expect(counts({ ADA: 5, ALGO: 1, APT: 3 })).toBe(true)
  })
  it('没行情的成员不拖中位数', () => {
    const l1 = l1Of(aggregate({ ADA: 4, ALGO: 2, APT: 6 }))
    const def = catalog.sectors('crypto').find(d => d.id === 'l1')!
    expect(l1.memberCount).toBe(3)
    expect(l1.staticCount).toBe(new Set(def.members).size)
    expect(l1.staticCount).toBe(88)
    expect(l1.staticCount).toBeGreaterThan(l1.memberCount)
    expect(l1.pct).toBe(4)
    expect(l1.quoteVolume).toBe(3)
    expect(l1.breadth * l1.memberCount).toBe(outperformCount(l1))
  })
  it('全场统一上浮：主数字抬，广度与领涨不动', () => {
    const raw: Record<string, number> = { ADA: -2, ALGO: -1, APT: 0, ATOM: 1, AVAX: 300 }
    const lifted = Object.fromEntries(Object.entries(raw).map(([k, v]) => [k, ((1 + v / 100) * 1.05 - 1) * 100]))
    const before = l1Of(aggregate(raw)), after = l1Of(aggregate(lifted))
    expect(after.frontier).toEqual(before.frontier)
    expect(Math.abs(after.breadth - before.breadth)).toBeLessThan(1e-12)
    expect(after.pct).toBeGreaterThan(before.pct)
    expect(before.upCount).toBe(2)
    expect(after.upCount).toBe(5)
  })
  it('分位数线性插值', () => {
    expect(quantile([1, 2, 3, 4], 0.9)).toBe(3.7)
    expect(quantile([1, 2], 0.5)).toBe(1.5)
    expect(quantile([7], 0.95)).toBe(7)
    expect(quantile([1, 2, 3, 4], 0)).toBe(1)
    expect(quantile([1, 2, 3, 4], 1)).toBe(4)
    expect(quantile([1, 2, 3, 4], 2)).toBe(4)
  })
  it('删一区间', () => {
    expect(jackknife([1, 2])).toBeNull()
    expect(jackknife([300, -2, 1, 0, -1])).toEqual([-0.5, 0.5])
  })
})

describe('板块口径 · 4. 中位数与广度走两条路', () => {
  it('人人腰斩的板块显示 −50，不是 −69.3', () => {
    const l1 = l1Of(aggregate({ ADA: -50, ALGO: -50, APT: -50 }))
    expect(l1.pct).toBe(-50)
    expect(l1.memberCount).toBe(3)
    expect(l1.breadth).toBe(0)
    expect(l1.upCount).toBe(0)
    expect(Math.abs(logReturn(-50) * 100 - -69.3147)).toBeLessThan(0.001)
  })
  it('广度来自对数池', () => {
    const l1 = l1Of(aggregate({ ADA: 10, ALGO: 10, APT: -10, ATOM: -10 }))
    expect(Math.abs(l1.pct)).toBeLessThan(1e-9)
    expect(Math.abs(l1.breadth - 0.5)).toBeLessThan(1e-9)
    expect(l1.upCount).toBe(2)
  })
})

describe('板块口径 · 5/6. 同 base 两张合约、缺成交额', () => {
  it('计价币档次压过成交额', () => {
    const usdt = quoteRank('USDT'), usdc = quoteRank('USDC')
    expect(prefers(usdt, 1, { rank: usdc, volume: 10 })).toBe(true)
    expect(prefers(usdc, 10, { rank: usdt, volume: 1 })).toBe(false)
    expect(prefers(usdt, 2, { rank: usdt, volume: 1 })).toBe(true)
    expect(prefers(usdt, 1, { rank: usdt, volume: 1 })).toBe(false)
    expect(quoteRank('usdt')).toBe(0)
    expect(usdc).toBe(1)
    expect(quoteRank('FDUSD')).toBe(2)
    expect(quoteRank('BTC')).toBe(TRADABLE_QUOTES.length)
  })
  it('缺成交额是缺，不是 0', () => {
    const r = quoteRank('USDT')
    expect(prefers(r, NaN, { rank: r, volume: 1 })).toBe(false)
    expect(prefers(r, 1, { rank: r, volume: NaN })).toBe(true)
    expect(prefers(r, NaN, { rank: r, volume: NaN })).toBe(false)
    expect(prefers(r, Infinity, { rank: r, volume: 1 })).toBe(false)
    const bucket = { id: 'fb-v', name: '其他', members: ['ZZA', 'ZZB', 'ZZC'] }
    const got = stats('crypto', quotesOf([q('ZZA', 1, NaN), q('ZZB', 2, 7), q('ZZC', 3, Infinity)]), [bucket])
    expect(got.length).toBe(1)
    expect(got[0].memberCount).toBe(3)
    expect(got[0].quoteVolume).toBe(7)
    const blank = stats('crypto', quotesOf([q('ZZA', 1, NaN), q('ZZB', 2, -1)]), [bucket])
    expect(Number.isNaN(blank[0].quoteVolume)).toBe(true)
    expect(blank[0].pct).toBe(1.5)
  })
  it('全量行情按档次挑合约（网页版的 ingest）', () => {
    const index = new Map([
      ['BTCUSDT', { symbol: 'BTCUSDT', baseAsset: 'BTC', quoteAsset: 'USDT' }],
      ['BTCUSDC', { symbol: 'BTCUSDC', baseAsset: 'BTC', quoteAsset: 'USDC' }],
      ['1000PEPEUSDT', { symbol: '1000PEPEUSDT', baseAsset: '1000PEPE', quoteAsset: 'USDT' }],
    ])
    const got = ingest([
      { symbol: 'BTCUSDC', pct: 9, quoteVolume: 100, price: 2 },
      { symbol: 'BTCUSDT', pct: 1, quoteVolume: 1, price: 1 },
      { symbol: '1000PEPEUSDT', pct: 3, quoteVolume: NaN, price: 1 },
      { symbol: 'GONEUSDT', pct: 3, quoteVolume: 1, price: 1 },
      { symbol: 'NANUSDT', pct: NaN, quoteVolume: 1, price: 1 },
    ], index)
    expect(got.get('BTC')?.pct).toBe(1)
    expect(got.get('1000PEPE')?.quoteVolume).toBeNaN()
    expect(got.has('GONE')).toBe(false)
    expect(got.size).toBe(2)
    // 品种表还没到：按后缀拆
    expect(ingest([{ symbol: 'ETHUSDT', pct: 1, quoteVolume: 1, price: 1 }]).get('ETH')?.pct).toBe(1)
  })
})

describe('板块窗口', () => {
  const sector = catalog.sectors('crypto').reduce((a, b) => b.members.length > a.members.length ? b : a)
  const quotesFor = (bases: string[], price: number): Quotes => quotesOf(bases.map(b => q(b, 1, 1, price)))
  const hist = (bases: string[], c5?: number, c20?: number, asof = '2026-09-18'): SectorHistory => {
    const closes = new Map<string, SectorCloses>()
    for (const b of bases) { const c: SectorCloses = {}; if (c5 != null) c.c5 = c5; if (c20 != null) c.c20 = c20; closes.set(b, c) }
    return { asof, closes }
  }
  const one = (asof: string, c: SectorCloses): SectorHistory => ({ asof, closes: new Map([['BTC', c]]) })

  it('5 日 = 现价 / 收盘 − 1', () => {
    const closes = { c5: 100, c20: 50 }
    expect(windowReturn(q('BTC', 1, 1, 110), 'today', closes)).toBe(1)
    expect(windowReturn(q('BTC', 1, 1, 110), 'd5', closes)).toBeCloseTo(10, 9)
    expect(windowReturn(q('BTC', 1, 1, 110), 'd20', closes)).toBeCloseTo(120, 9)
    expect(windowReturn(q('BTC', 1, 1, 121), 'd5', closes)).toBeCloseTo(21, 9)
  })
  it('缺收盘是缺，不是 0', () => {
    const x = q('BTC', 1, 1, 110)
    expect(windowReturn(x, 'd5', { c20: 50 })).toBeNull()
    expect(windowReturn(x, 'd5', undefined)).toBeNull()
    expect(windowReturn(x, 'd5', { c5: 0 })).toBeNull()
    expect(windowReturn(x, 'd5', { c5: -1 })).toBeNull()
    expect(windowReturn(q('BTC', 1, 1, NaN), 'd5', { c5: 1 })).toBeNull()
  })
  it('没有历史：5 日一个板块都排不出', () => {
    const quotes = quotesFor(sector.members, 110)
    expect(stats('crypto', quotes, [], 'd5', EMPTY_HISTORY)).toEqual([])
    expect(hasEligible('crypto', quotes, 'd5', EMPTY_HISTORY)).toBe(false)
    expect(hasEligible('crypto', quotes, 'today', EMPTY_HISTORY)).toBe(true)
  })
  it('覆盖不到八成：行还在，但不算数（网页版不进 5 日榜）', () => {
    const members = sector.members
    const quotes = quotesFor(members, 110)
    const isCovered = (h: SectorHistory): boolean => covered(memberSet(members, quotes, 'd5', h), 'd5')
    const half = members.slice(0, Math.floor(members.length / 2))
    const thin = stats('crypto', quotes, [], 'd5', hist(half, 100))
    const row = thin.find(s => s.id === sector.id)
    expect(row).toBeDefined()
    expect(row!.memberCount).toBe(half.length)
    expect(isCovered(hist(half, 100))).toBe(false)
    expect(rankable('crypto', row!, quotes, 'd5', hist(half, 100), [])).toBe(false)
    const wide = members.slice(0, Math.ceil(0.9 * members.length))
    expect(isCovered(hist(wide, 100))).toBe(true)
    const rowWide = stats('crypto', quotes, [], 'd5', hist(wide, 100)).find(s => s.id === sector.id)!
    expect(rankable('crypto', rowWide, quotes, 'd5', hist(wide, 100), [])).toBe(true)
  })
  it('中位数与广度跟窗口走', () => {
    const members = sector.members.slice(0, 4)
    const fiveDay = [10, 20, -10, -20]
    const quotes = quotesOf(members.map((b, i) => q(b, 1, 1, 100 + fiveDay[i])))
    const history: SectorHistory = { asof: '2026-09-18', closes: new Map(members.map(b => [b, { c5: 100, c20: 80 }])) }
    const today = stats('crypto', quotes, [], 'today', history).find(s => s.id === sector.id)!
    const five = stats('crypto', quotes, [], 'd5', history).find(s => s.id === sector.id)!
    expect(Math.abs(today.pct - 1)).toBeLessThan(1e-9)
    expect(Math.abs(five.pct)).toBeLessThan(1e-9)
    expect(outperformCount(today)).toBe(0)
    expect(outperformCount(five)).toBe(2)
    expect(windowMedian(members, quotes, history, 'd20')).toBeCloseTo(25, 9)
    const only5: SectorHistory = { asof: '2026-09-18', closes: new Map(members.map(b => [b, { c5: 100 }])) }
    expect(windowMedian(members, quotes, only5, 'd20')).toBeNull()
  })
  it('取历史失败不碰今日', () => {
    const snap = snapshot('crypto')
    const withHistory = stats('crypto', snap.quotes, snap.buckets, 'today', hist(['BTC'], 1, 2))
    const blind = stats('crypto', snap.quotes, snap.buckets, 'today', EMPTY_HISTORY)
    const legacy = stats('crypto', snap.quotes, snap.buckets)
    expect(withHistory).toEqual(blind)
    expect(blind).toEqual(legacy)
  })
  it('同一天那份不重算', () => {
    const held = one('2026-09-18', { c5: 1, c20: 2 })
    expect(supersedes(one('2026-09-18', { c5: 9 }), held)).toBe(false)
    expect(supersedes(one('2026-09-19', { c5: 1 }), held)).toBe(true)
    expect(supersedes(held, EMPTY_HISTORY)).toBe(true)
  })
  it('旧快照 / 坏快照一律不认', () => {
    const held = one('2026-09-18', { c5: 1, c20: 2 })
    for (const asof of ['2026-09-17', '2026-08-01', 'banana', '2026-13-01', '2026-02-30', '']) expect(supersedes(one(asof, { c5: 9 }), held)).toBe(false)
    expect(supersedes(one('banana', { c5: 9 }), EMPTY_HISTORY)).toBe(false)
    const thin = one('2026-09-18', { c5: 1 })
    const fat: SectorHistory = { asof: '2026-09-18', closes: new Map([['BTC', { c5: 1 }], ['ETH', { c5: 2 }]]) }
    expect(supersedes(fat, thin)).toBe(true)
    expect(supersedes(thin, fat)).toBe(false)
  })
  it('过期快照到不了界面', () => {
    const day = (s: string): number => parseDay(s)!
    const now = day('2026-09-19') + 12 * 3_600_000
    const snap = (asof: string): SectorHistory => one(asof, { c5: 1, c20: 2 })
    expect(accepts(EMPTY_HISTORY, snap('2026-09-19'), now)).toBe(true)
    expect(accepts(EMPTY_HISTORY, snap('2026-09-05'), now)).toBe(false)
    expect(accepts(EMPTY_HISTORY, snap('banana'), now)).toBe(false)
    expect(accepts(snap('2026-09-19'), snap('2026-09-11'), now)).toBe(false)
    const midnight = day('2026-09-19')
    expect(isFresh('2026-09-12', midnight)).toBe(true)
    expect(isFresh('2026-09-11', midnight)).toBe(false)
    expect(isFresh('2026-09-21', midnight)).toBe(true)
    expect(isFresh('2026-09-22', midnight)).toBe(false)
    expect(isFresh('banana', midnight)).toBe(false)
    expect(hasEligible('crypto', quotesFor(sector.members, 110), 'd5', EMPTY_HISTORY)).toBe(false)
  })
  it('日期只认真实存在的一天', () => {
    expect(parseDay('2026-09-19')).not.toBeNull()
    expect(parseDay('2028-02-29')).not.toBeNull()
    for (const s of ['2026-02-29', '2026-9-19', '2026-09-19T00:00:00Z', ' 2026-09-19', 'banana', '']) expect(parseDay(s)).toBeNull()
  })
})

describe('5 日收盘接口解码', () => {
  it('按计价币档次留一张；数字或字符串；缺的、非正的都丢', () => {
    const h = decodeHistory({ data: { asof: '2026-09-29', symbols: {
      BTCUSDC: { c5: 2, c20: 3 }, BTCUSDT: { c5: 1, c20: '1.5' }, ethusdt: { c5: '0', c20: 7 },
      DEADUSDT: { c5: null, c20: -1 }, ETHBTC: { c5: 0.03 }, '1000PEPEUSDT': { c5: 0.01 },
    } } })!
    expect(h.asof).toBe('2026-09-29')
    expect(h.closes.get('BTC')).toEqual({ c5: 1, c20: 1.5 })
    expect(h.closes.get('ETH')).toEqual({ c20: 7 })
    expect(h.closes.has('DEAD')).toBe(false)
    expect(h.closes.get('ETHBTC')).toEqual({ c5: 0.03 })
    expect(h.closes.get('1000PEPE')).toEqual({ c5: 0.01 })
  })
  it('坏形状、空表一律 null', () => {
    expect(decodeHistory(null)).toBeNull()
    expect(decodeHistory({ error: { code: 'temporarily_unavailable' } })).toBeNull()
    expect(decodeHistory({ data: { asof: 'banana', symbols: { BTCUSDT: { c5: 1 } } } })).toBeNull()
    expect(decodeHistory({ data: { asof: '2026-09-29', symbols: {} } })).toBeNull()
    expect(decodeHistory({ data: { asof: '2026-09-29', symbols: [] } })).toBeNull()
  })
  it('失败重试间隔 5、15、45…封顶 10 分钟', () => {
    expect(historyRetryDelay(0)).toBe(600)
    expect([1, 2, 3, 4, 5, 6, 7, 20].map(historyRetryDelay)).toEqual([5, 15, 45, 135, 405, 600, 600, 600])
  })
})

describe('展示规则（手机 app 层）', () => {
  const st = (id: string, pct: number, memberCount = 5, breadth = 0): SectorStat => ({ id, name: id, market: 'crypto', pct, memberCount, staticCount: memberCount, quoteVolume: 1, isFallback: false, breadth, upCount: 0, frontier: [], jackknife: null })
  it('板块排序：降序、缺数沉底、并列按 id', () => {
    expect(boardOrder([st('b', 1), st('nan', NaN), st('a', 1), st('up', 7), st('down', -3)]).map(s => s.id)).toEqual(['up', 'a', 'b', 'down', 'nan'])
  })
  it('不到三家的整档沉底', () => {
    expect(boardOrder([st('desci', 38, 1), st('pair', 12, 2), st('ai', 4), st('meme', -2), st('nan', NaN)]).map(s => s.id)).toEqual(['ai', 'meme', 'nan', 'desci', 'pair'])
  })
  it('DeSci 只有 BIO 一只：涨得再多也排在所有够三家的板块之后，不算跑赢大盘（网页截图那一行）', () => {
    const { quotes, buckets } = snapshot('crypto')
    quotes.set('BIO', q('BIO', 38, 5_000_000, 0.1))
    const list = boardOrder(stats('crypto', quotes, buckets))
    const i = list.findIndex(s => s.id === 'desci')
    expect(i).toBeGreaterThan(-1)
    const desci = list[i]
    // 成员数只数有行情的（目录里 DeSci 本来就只有 BIO）
    expect(catalog.sectors('crypto').find(d => d.id === 'desci')?.members).toEqual(['BIO'])
    expect(desci.memberCount).toBe(1)
    expect(desci.pct).toBeCloseTo(38)
    expect(isThin(desci)).toBe(true)
    expect(subtitle(desci)).toBe('')
    // 前面全是够三家的，后面全是不够的
    expect(list.slice(0, i).every(s => !isThin(s))).toBe(true)
    expect(list.slice(i).every(s => isThin(s))).toBe(true)
    // 够三家的那一段仍按涨跌幅降序
    const fat = list.filter(s => !isThin(s)).map(s => s.pct)
    expect(fat).toEqual(fat.slice().sort((a, b) => b - a))
    expect(list.filter(s => s.pct > desci.pct && !isThin(s))).toEqual([])
  })
  it('有行情的不到三家就算薄（目录里成员多但只有两只在交易也算）', () => {
    const st2 = stats('crypto', quotesOf([q('BTC', 1), q('ETH', 2)]), [])
    expect(st2.every(s => s.memberCount <= 2 && isThin(s))).toBe(true)
  })
  it('副标题「x/N 跑赢大盘」；不到三家不画', () => {
    expect(subtitle(st('x', 1, 5, 0.6))).toBe('3/5 跑赢大盘')
    expect(subtitle(st('x', 1, 2, 0.5))).toBe('')
  })
  it('品种列表只按涨跌幅，两次排出来一样', () => {
    const quotes = quotesOf([q('AAA', 1, 9_000_000), q('BBB', 3, 5_000), q('CCC', 1, NaN), q('DDD', -2, 9_000)])
    const members = ['AAA', 'BBB', 'CCC', 'DDD']
    const first = symbolRows(members, quotes).map(r => r.base)
    expect(first).toEqual(['BBB', 'AAA', 'CCC', 'DDD'])
    expect(symbolRows(members.slice().reverse(), quotes).map(r => r.base)).toEqual(first)
  })
  it('缺涨跌幅的沉底，并列按代号；领涨打标', () => {
    const quotes = quotesOf([q('DDD', 4), q('BBB', -3), q('AAA', NaN), q('CCC', NaN)])
    const rows = symbolRows(['AAA', 'BBB', 'CCC', 'DDD'], quotes, ['DDD'])
    expect(rows.map(r => r.base)).toEqual(['DDD', 'BBB', 'AAA', 'CCC'])
    expect(rows[2].pct).toBeNaN()
    expect(rows[0].isFrontier).toBe(true)
    expect(rows[1].isFrontier).toBe(false)
  })
  it('5 日那一档：没数据就退回今日、整排不出现', () => {
    expect(resolveWindow('d5', false)).toEqual({ window: 'today', showsBar: false, title: '今日' })
    expect(resolveWindow('d5', true)).toEqual({ window: 'd5', showsBar: true, title: '5 日' })
    expect(resolveWindow('today', true)).toEqual({ window: 'today', showsBar: true, title: '今日' })
    expect(resolveWindow('d20', true).title).toBe('今日')
  })
})

describe('兜底桶', () => {
  it('按交易所标签分桶；目录里有的、贵金属、非美股股票都不进', () => {
    const e = (baseAsset: string, underlyingType: string, sub: string[] = []) => ({ symbol: baseAsset + 'USDT', baseAsset, quoteAsset: 'USDT', underlyingType, underlyingSubType: sub })
    const got = fallbackBuckets([
      e('ZZI', 'COIN', ['Infrastructure']), e('ZZA', 'COIN', ['Alpha', 'DeFi']), e('ZZD', 'COIN', ['DeFi']),
      e('ZZM', 'COIN', ['Meme']), e('ZZB', 'COIN'), e('ZZB', 'COIN', ['Alpha']), e('BTC', 'COIN', ['PoW']),
      e('XAU', 'COMMODITY'), e('SPY', 'EQUITY'), e('HK0700', 'HK_EQUITY'),
    ], 'crypto')
    expect(got).toEqual([
      { id: 'tag-infrastructure', name: '基础设施', members: ['ZZI'] },
      { id: 'tag-alpha', name: '币安 Alpha', members: ['ZZA'] },
      { id: 'tag-defi', name: 'DeFi 其他', members: ['ZZD'] },
      { id: 'misc', name: '其他', members: ['ZZB', 'ZZM'] },
    ])
    const us = fallbackBuckets([e('SPY', 'EQUITY', ['TradFi']), e('NVDA', 'EQUITY'), e('HK0700', 'HK_EQUITY'), e('ZZB', 'COIN')], 'us')
    expect(us).toEqual([{ id: 'misc', name: '其他', members: ['SPY'] }])
  })
})
