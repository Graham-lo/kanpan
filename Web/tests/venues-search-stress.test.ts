/* 压测 / 极端 · 搜索按交易所分组：五家各上千只（共五千多只），查询串为空 / 单字 / 全角 / 拼音 / 中文 / 表情 / 超长。
 * 交叉测试：电脑版 pages/searchGroups（market/symbols groupSearch）与手机 m/model/search（rank + groupRanked）
 *   同一输入下组序、组内序、总数一致（组序同档按 iOS VenueRegistry.all：币安 · OKX · Bybit · Hyperliquid · Coinbase）。
 *   唯一有意的差别：电脑版多认「去掉 1000 / k 倍数前缀的代号」（PEPE 打全了算最匹配，tests/g-search-normalize），
 *   带倍数前缀的品种两边命中的是同一批、只是档次不同——这一条单独断言，不混进全等比较。
 * 预览轮流分配：组数 > 预算、某组为 0、只有一组、随机。 */
import { describe, expect, it } from 'vitest'
import { baseOf, cnOf, groupSearch, type Sym } from '../src/market/symbols'
import { SEARCH_ORDER as PC_ORDER, searchGroups } from '../src/pages/searchGroups'
import { SEARCH_ORDER as M_ORDER, SEARCH_PREVIEW, groupRanked, previewQuota, rank } from '../src/m/model/search'
import { pairOf } from '../src/m/model/symKey'
import { parseKey, wireSymbol } from '../src/market/identity'
import { matchOne, normalize } from '../src/market/searchText'
import { MARKET_VENUES } from '../src/venues'

function rng(seed: number) { return () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff } }
const REAL = ['BTC', 'ETH', 'SOL', 'XRP', 'DOGE', 'PEPE', 'SHIB', 'BONK', 'LINK', 'SUI', 'HYPE', 'TRUMP', 'WIF', 'ADA', 'AVAX', 'BNB', 'KAITO', 'ETHFI', 'BTCDOM', 'ZEC', 'XAU', 'NVDA']

/** 五家各 ≥ 1000 只；withPrefix：加上 1000PEPE / 1000BONK / kPEPE / 币安人生 这些带倍数前缀、非 ASCII 的 */
function pool(seed: number, withPrefix: boolean): Sym[] {
  const R = rng(seed)
  const out: Sym[] = []
  const mk = (symbol: string, quote: string, title?: string): Sym => {
    const base = baseOf(symbol)
    const price = R() < 0.05 ? null : 1 + R()
    return { symbol, venue: parseKey(symbol).venue, quote, title, base, code: base, kind: 'crypto', cn: cnOf(base, 'crypto'), dec: 2, color: '', price, chg: 0, pct: 0, vol: price == null ? 0 : Math.floor(R() * 1e6), fr: null, nextFunding: null }
  }
  const rand = () => 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'[Math.floor(R() * 26)] + Array.from({ length: 1 + Math.floor(R() * 6) }, () => 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'[Math.floor(R() * 36)]).join('')
  const bases = [...new Set([...REAL, ...Array.from({ length: 1200 }, rand)])]
  for (const b of bases) {
    out.push(mk(`${b}USDT`, 'USDT'))
    out.push(mk(`okx/usd_m/${b}USDT`, 'USDT'))
    out.push(mk(`bybit/usd_m/${b}USDT`, 'USDT'))
    out.push(mk(`hyperliquid/usd_m/${b}`, 'USDC'))
    out.push(mk(`coinbase/spot/${b}-USD`, 'USD'))
  }
  if (withPrefix) {
    out.push(mk('1000PEPEUSDT', 'USDT'), mk('1000BONKUSDT', 'USDT'), mk('bybit/usd_m/1000PEPEUSDT', 'USDT'), mk('bybit/usd_m/SHIB1000USDT', 'USDT'), mk('币安人生USDT', 'USDT'))
    const k = mk('hyperliquid/usd_m/KPEPE', 'USDC', 'kPEPE'); k.base = k.code = 'PEPE'; out.push(k)
  }
  out.push({ ...mk('DXY', ''), venue: 'macro', macro: true, kind: 'idx', cn: '美元指数', base: 'DXY', code: 'DXY' })
  return out
}

const QUERIES = ['', 'b', 'B', 'e', 'z', '1', 'btc', 'BTC', 'ＢＴＣ', 'ｂｔｃ／ｕｓｄｔ', 'btc/usdt', 'btc usdt', 'eth-usd', '比特币', '大饼', 'bitebi', 'btb', 'dabing', 'hj', '黄金', '币安', '😀', '😀btc', 'usd', 'usdt', 'x'.repeat(300), '/', '   ', 'pepe', 'kpepe', '1000', 'hype', 'trump', 'a1', 'ethfi']

const pcGroups = (P: Sym[], q: string) => groupSearch(P, q, PC_ORDER, () => false, Infinity).map(g => ({ venue: g.venue, items: g.items.map(s => s.symbol) }))
const mGroups = (P: Sym[], q: string) => groupRanked(rank(P, q, s => pairOf(s.symbol, s).base, s => wireSymbol(s.symbol))).map(g => ({ venue: g.venue, items: g.hits.map(h => h.item.symbol) }))

describe('组序和 iOS 一致', () => {
  it('电脑与手机的组序是同一份：币安 · OKX · Bybit · Hyperliquid · Coinbase · 指数', () => {
    expect(PC_ORDER).toEqual(['binance', 'okx', 'bybit', 'hyperliquid', 'coinbase', 'macro'])
    expect(M_ORDER).toEqual(PC_ORDER)
    expect(PC_ORDER.slice(0, -1)).toEqual(MARKET_VENUES.map(v => v.key))
  })
})

describe('五家各上千只：电脑与手机同一输入同一结果（交叉）', () => {
  const P = pool(11, false)
  it('池子够大：每家 ≥ 1000 只', () => {
    for (const v of MARKET_VENUES) expect(P.filter(s => s.venue === v.key).length).toBeGreaterThanOrEqual(1000)
  })
  for (const q of QUERIES) {
    it(`查询 ${JSON.stringify(q.length > 20 ? q.slice(0, 8) + '…' : q)}：组序、组内序、总数一致`, () => {
      const pc = pcGroups(P, q), m = mGroups(P, q)
      expect(pc.map(g => g.venue)).toEqual(m.map(g => g.venue))
      expect(pc.map(g => g.items.length)).toEqual(m.map(g => g.items.length))
      for (let i = 0; i < pc.length; i++) expect(pc[i].items, `${q} ${pc[i].venue}`).toEqual(m[i].items)
      // 每组只装那一家；命中的每一只确实命中（空查询全收）
      for (const g of pc) expect(g.items.every(k => (k === 'DXY' ? 'macro' : parseKey(k).venue) === g.venue)).toBe(true)
      const Q = normalize(q)
      if (Q) for (const k of pc.flatMap(g => g.items)) {
        const s = P.find(x => x.symbol === k)!
        expect(matchOne(wireSymbol(k), pairOf(k, s).base, Q), k).not.toBeNull()
      }
      else expect(pc.reduce((a, g) => a + g.items.length, 0)).toBe(P.length)
    })
  }
  it('电脑版弹层封顶：有字每组 40、空查询每组 12，摊平的一列 = 各组之和（键盘上下用的下标）', () => {
    for (const q of ['', 'b', 'usd']) {
      const { groups, flat } = searchGroups(P, q, () => false)
      const cap = normalize(q) ? 40 : 12
      expect(groups.every(g => g.items.length <= cap)).toBe(true)
      expect(flat.length).toBe(groups.reduce((a, g) => a + g.items.length, 0))
      // 封顶只截尾：和不封顶的前缀一致
      const full = pcGroups(P, q)
      groups.forEach((g, i) => expect(g.items.map(s => s.symbol)).toEqual(full[i].items.slice(0, cap)))
    }
  })
  it('组序：先按组内最好的档；同档按注册表', () => {
    // 只有 Coinbase 有 ZZQ（整词）、别家只有包含 ZZQ 的：Coinbase 排第一
    const extra: Sym[] = [
      { ...P[0], symbol: 'coinbase/spot/ZZQ-USD', venue: 'coinbase', base: 'ZZQ', code: 'ZZQ', cn: '', price: 1, vol: 1 },
      { ...P[0], symbol: 'XZZQXUSDT', venue: 'binance', base: 'XZZQX', code: 'XZZQX', cn: '', price: 1, vol: 1e9 },
    ]
    for (const g of [pcGroups([...extra], 'zzq'), mGroups([...extra], 'zzq')]) expect(g.map(x => x.venue)).toEqual(['coinbase', 'binance'])
  })
})

describe('带倍数前缀 / 非 ASCII 代号的品种：两边命中同一批（档次是电脑版有意多认的一条）', () => {
  const P = pool(23, true)
  for (const q of ['pepe', 'bonk', 'shib', '1000', 'kpepe', '币安', '币安人生', 'b', '']) {
    it(`查询 ${JSON.stringify(q)}：每组命中的集合、总数一致`, () => {
      const pc = pcGroups(P, q), m = mGroups(P, q)
      const set = (gs: { venue: string; items: string[] }[]) => Object.fromEntries(gs.map(g => [g.venue, [...g.items].sort()]))
      expect(set(pc)).toEqual(set(m))
    })
  }
  it('打全了 PEPE：电脑版把 1000PEPE / kPEPE 算最匹配（g-search-normalize 定的），手机 / iOS 算包含——组序因此不同（报告里交代）', () => {
    // 真实的上架情况：币安、Bybit 只有 1000PEPEUSDT，HL 只有 kPEPE，OKX 与 Coinbase 是 PEPE 本名
    const real = ['1000PEPEUSDT', 'okx/usd_m/PEPEUSDT', 'bybit/usd_m/1000PEPEUSDT', 'hyperliquid/usd_m/KPEPE', 'coinbase/spot/PEPE-USD'].map(k => {
      const s = { ...P.find(x => x.symbol === k) ?? P.find(x => x.symbol === 'okx/usd_m/PEPEUSDT')!, symbol: k, venue: parseKey(k).venue }
      if (k.endsWith('KPEPE')) s.title = 'kPEPE'
      return s
    })
    const pc = pcGroups(real, 'pepe'), m = mGroups(real, 'pepe')
    expect(pc.map(g => g.venue)).toEqual(['binance', 'okx', 'bybit', 'hyperliquid', 'coinbase'])
    expect(m.map(g => g.venue)).toEqual(['okx', 'coinbase', 'binance', 'bybit', 'hyperliquid'])
  })
})

describe('极端查询不崩、结果有界', () => {
  const P = pool(5, true)
  it('表情、超长、只有分隔符、零宽字符、RTL 字符', () => {
    for (const q of ['😀', '👨‍👩‍👧', 'x'.repeat(10_000), '​', '‮BTC', '\ud83d', '%00', '<script>', '.*', '(', '\\']) {
      const pc = pcGroups(P, q), m = mGroups(P, q)
      expect(pc.reduce((a, g) => a + g.items.length, 0)).toBe(m.reduce((a, g) => a + g.items.length, 0))
      expect(pc.length).toBeLessThanOrEqual(6)
    }
  })
})

describe('预览轮流分配（previewQuota，同 iOS）', () => {
  it('组数 > 预算：每组照样一行；某组为 0 不占名额；只有一组拿满', () => {
    expect(previewQuota([5, 5, 5, 5, 5, 5, 5, 5], 6)).toEqual([1, 1, 1, 1, 1, 1, 1, 1])
    expect(previewQuota([5, 0, 5, 0, 5], 6)).toEqual([2, 0, 2, 0, 2])
    expect(previewQuota([0, 0, 9], 6)).toEqual([0, 0, 6])
    expect(previewQuota([1000], 6)).toEqual([6])
    expect(previewQuota([0], 6)).toEqual([0])
    expect(previewQuota([0, 0], 6)).toEqual([0, 0])
    expect(previewQuota([1, 1, 1, 1, 1, 1, 1], 6)).toEqual([1, 1, 1, 1, 1, 1, 1])
  })
  it('随机 2000 组：总数 = min(max(预算, 非空组数), 命中总数)；每组 ≤ 命中数；非空组 ≥ 1；轮流——没取完的组之间相差 ≤ 1', () => {
    const R = rng(99)
    for (let k = 0; k < 2000; k++) {
      const counts = Array.from({ length: Math.floor(R() * 8) }, () => (R() < 0.25 ? 0 : Math.floor(R() * 20)))
      const budget = Math.floor(R() * 10)
      const q = previewQuota(counts, budget)
      const total = counts.reduce((a, b) => a + b, 0), nonEmpty = counts.filter(n => n > 0).length
      expect(q.reduce((a, b) => a + b, 0)).toBe(Math.min(Math.max(budget, nonEmpty), total))
      q.forEach((x, i) => { expect(x).toBeLessThanOrEqual(counts[i]); if (counts[i] > 0 && (budget > 0 || nonEmpty > 0)) expect(x).toBeGreaterThanOrEqual(1) })
      const open = q.filter((x, i) => x < counts[i])
      if (open.length > 1) expect(Math.max(...open) - Math.min(...open)).toBeLessThanOrEqual(1)
      // 先到的组先拿：没取完的组里，排在前面的不比后面的少
      for (let i = 1; i < q.length; i++) if (q[i] < counts[i] && q[i - 1] < counts[i - 1]) expect(q[i - 1]).toBeGreaterThanOrEqual(q[i])
    }
  })
  it('手机搜索页：五家都命中时 6 行分成 [2, 1, 1, 1, 1]，组序按注册表', () => {
    const P = pool(3, false)
    const g = mGroups(P, 'btc')
    expect(g.map(x => x.venue)).toEqual(['binance', 'okx', 'bybit', 'hyperliquid', 'coinbase'])
    expect(previewQuota(g.map(x => x.items.length), SEARCH_PREVIEW)).toEqual([2, 1, 1, 1, 1])
  })
})
