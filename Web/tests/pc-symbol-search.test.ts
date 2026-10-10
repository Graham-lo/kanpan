/* 电脑网页搜品种弹层按品种聚合（2026-10-10 审查 C2）：搜 ETH 原来一家一组出九行（币安 / OKX / Bybit 各三只），
 * 现在一个品种一行、交易所是行尾记号；回车 / 点行开默认那一家（匹配档 → 当前图那一家 → 自选 → 币安），
 * ← → / 悬停记号改选别家；美股 / 大宗 / 美元指数这类只一家有的照常一行。 */
// @ts-expect-error Web 的 tsconfig 不带 @types/node；vitest 把 .css?raw 处理成空串，只能直接读文件（同 b-contrast.test.ts）
import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { baseOf, cnOf, type Kind, type Sym } from '../src/market/symbols'
import { parseKey } from '../src/market/identity'
import { searchRows } from '../src/pages/searchGroups'
import { pickIndex, rowHTML, venueChips } from '../src/pages/symbolSearch'

function mk(symbol: string, vol: number, kind: Kind = 'crypto', extra: Partial<Sym> = {}): Sym {
  const base = extra.base ?? baseOf(symbol)
  return { symbol, venue: parseKey(symbol).venue, quote: 'USDT', base, code: base, kind, cn: cnOf(base, kind), dec: 2, color: '', price: 1, chg: 0, pct: 0.5, vol, fr: null, nextFunding: null, ...extra }
}
const POOL: Sym[] = [
  // 币安 / OKX / Bybit 各三只（ETH、ETHFI、ETHW）——原来搜 ETH 出九行
  mk('ETHUSDT', 4e9), mk('ETHFIUSDT', 2e7), mk('ETHWUSDT', 9e5),
  mk('okx/usd_m/ETHUSDT', 3e9), mk('okx/usd_m/ETHFIUSDT', 6e6), mk('okx/usd_m/ETHWUSDT', 5e5),
  mk('bybit/usd_m/ETHUSDT', 1.3e9), mk('bybit/usd_m/ETHFIUSDT', 7e6), mk('bybit/usd_m/ETHWUSDT', 1e5),
  mk('BTCUSDT', 9e9), mk('okx/usd_m/BTCUSDT', 5e9),
  // 带倍数前缀的同一个币
  mk('1000PEPEUSDT', 3e8), mk('hyperliquid/usd_m/KPEPE', 1e8, 'crypto', { quote: 'USDC', title: 'kPEPE', base: 'PEPE', code: 'PEPE' }),
  // 只一家有的：美股、大宗、美元指数
  mk('NVDAUSDT', 5e8, 'us'), mk('XAUUSDT', 4e8, 'com'),
  { ...mk('DXY', 0, 'idx'), venue: 'macro', quote: '', macro: true, base: 'DXY', code: 'DXY', cn: '美元指数' },
]
const none = () => false

describe('按品种聚合', () => {
  it('搜 ETH：三行（ETH、ETHFI、ETHW），ETH 一行带币安 · OKX · Bybit 三家，按注册表顺序', () => {
    const rows = searchRows(POOL, 'ETH', none)
    expect(rows.map(r => r.items[0].base)).toEqual(['ETH', 'ETHFI', 'ETHW'])
    expect(rows[0].items.map(s => s.symbol)).toEqual(['ETHUSDT', 'okx/usd_m/ETHUSDT', 'bybit/usd_m/ETHUSDT'])
    expect(rows.every(r => r.items.length === 3)).toBe(true)
  })
  it('回车开默认交易所：没有别的线索时是币安；当前图在 OKX 时是 OKX；自选里有 Bybit 那只时是 Bybit', () => {
    const at = (current = '', watched: (k: string) => boolean = none) => { const r = searchRows(POOL, 'eth', watched, current)[0]; return r.items[pickIndex(r)].symbol }
    expect(at()).toBe('ETHUSDT')
    expect(at('okx/usd_m/BTCUSDT')).toBe('okx/usd_m/ETHUSDT')
    expect(at('', k => k === 'bybit/usd_m/ETHUSDT')).toBe('bybit/usd_m/ETHUSDT')
    // 当前图那一家压过自选
    expect(at('okx/usd_m/SOLUSDT', k => k === 'bybit/usd_m/ETHUSDT')).toBe('okx/usd_m/ETHUSDT')
    // 当前图那一家这个币没有：退回币安
    expect(at('hyperliquid/usd_m/BTC')).toBe('ETHUSDT')
  })
  it('改选过（悬停记号 / ← →）：回车开改选的那一家；改选的键不在这一行里就回默认', () => {
    const r = searchRows(POOL, 'ETH', none)[0]
    expect(r.items[pickIndex(r, new Map([[r.id, 'bybit/usd_m/ETHUSDT']]))].symbol).toBe('bybit/usd_m/ETHUSDT')
    expect(r.items[pickIndex(r, new Map([[r.id, 'SOLUSDT']]))].symbol).toBe('ETHUSDT')
  })
  it('倍数前缀并进同一行（1000PEPE、kPEPE → PEPE）；打全了某一家的写法就默认开那一家', () => {
    const [pepe] = searchRows(POOL, 'pepe', none)
    expect(pepe.items.map(s => s.symbol)).toEqual(['1000PEPEUSDT', 'hyperliquid/usd_m/KPEPE'])
    const [k] = searchRows(POOL, 'kpepe', none)
    expect(k.items[pickIndex(k)].symbol).toBe('hyperliquid/usd_m/KPEPE')
  })
  it('只一家有的：美股、大宗、美元指数各一行一只', () => {
    for (const [q, sym] of [['NVDA', 'NVDAUSDT'], ['黄金', 'XAUUSDT'], ['DXY', 'DXY']] as const) {
      const rows = searchRows(POOL, q, none)
      expect(rows.length, q).toBe(1)
      expect(rows[0].items.map(s => s.symbol)).toEqual([sym])
    }
  })
  it('空查询：自选在前，其余按各家成交额之和', () => {
    const rows = searchRows(POOL, '', k => k === 'NVDAUSDT')
    expect(rows[0].items[0].symbol).toBe('NVDAUSDT')
    expect(rows[1].items[0].base).toBe('BTC')
  })
})

describe('行的 HTML', () => {
  it('ETH 一行：行尾三颗记号，默认那一家 aria-pressed；价 / 涨跌 / 成交额是默认那一家的', () => {
    const r = searchRows(POOL, 'ETH', none, 'okx/usd_m/BTCUSDT')[0]
    const h = rowHTML(r, 0, { active: true, qq: 'ETH', pick: pickIndex(r), tail: '' })
    expect((h.match(/class="sr-v"/g) || []).length).toBe(3)
    expect(h).toMatch(/data-venue="okx" aria-pressed="true"/)
    expect(h).toMatch(/data-venue="binance" aria-pressed="false"/)
    expect(h).toContain('<mark>ETH</mark>')
    expect(h).toContain('3.00B')
    expect((h.match(/class="sr /g) || []).length).toBe(1)
  })
  it('美元指数没有交易所缩写：不出记号', () => {
    const r = searchRows(POOL, 'DXY', none)[0]
    expect(venueChips(r)).toBe('')
  })
})

describe('对比弹层（同一套 searchRows / rowHTML）', () => {
  it('选中那一家默认是已在对比里的那只（prefer），改选过的仍优先', () => {
    const r = searchRows(POOL, 'ETH', none)[0]
    const inCmp = (s: Sym) => s.symbol === 'bybit/usd_m/ETHUSDT'
    expect(r.items[pickIndex(r, new Map(), inCmp)].symbol).toBe('bybit/usd_m/ETHUSDT')
    expect(r.items[pickIndex(r, new Map([[r.id, 'okx/usd_m/ETHUSDT']]), inCmp)].symbol).toBe('okx/usd_m/ETHUSDT')
    expect(r.items[pickIndex(r, new Map(), () => false)].symbol).toBe('ETHUSDT')
  })
  it('已在对比里的那几家记号带 in；行尾一格、置灰类与 aria-disabled 照传', () => {
    const r = searchRows(POOL, 'ETH', none)[0]
    const h = rowHTML(r, 2, { active: false, qq: 'ETH', pick: 0, tail: '<span class="cmp-tag">主图</span>', cls: 'cmp-off', attrs: 'aria-disabled="true"', mark: s => s.symbol === 'okx/usd_m/ETHUSDT' })
    expect((h.match(/class="sr-v in"/g) || []).length).toBe(1)
    expect(h).toMatch(/class="sr-v in"[^>]*data-venue="okx"/)
    expect(h).toContain('class="sr  cmp-off"')
    expect(h).toContain('aria-disabled="true"')
    expect(h).toContain('data-i="2"')
    expect(h).toMatch(/<div class="sr-tail" data-tail><span class="cmp-tag">主图<\/span><\/div>/)
  })
  it('compare.ts 不再自己拼行：用 searchRows + rowHTML，没有旧的分组行', () => {
    const src = readFileSync(new URL('../src/pages/compare.ts', import.meta.url), 'utf8')
    expect(src).toContain('searchRows(')
    expect(src).toContain('rowHTML(')
    expect(src).not.toMatch(/searchGroups\(|resultName\(|groupHead\(/)
    expect(src).toContain("'search-dlg cmp-dlg sym-dlg'")
  })
})

describe('样式', () => {
  const css = readFileSync(new URL('../src/styles/app.css', import.meta.url), 'utf8')
  it('列宽只作用在 .sym-dlg（搜索 / 对比两个弹层），基础 .sr 不动', () => {
    expect(css).toMatch(/\.sym-dlg \.sr \{ grid-template-columns: [^}]*\}/)
    expect(css).not.toMatch(/^\.sr \{[^}]*228px/m)
  })
  it('多分辨率：弹层宽、列表高按视口夹，列在窄弹层里收；记号尺寸全跟字号令牌（em），不写 px 字号', () => {
    expect(css).toContain('.sym-dlg { width: min(900px, 92vw); }')
    expect(css).toMatch(/\.sym-dlg \.search-list \{ height: min\(520px, \d+vh\);/)
    expect(css).toMatch(/\.sym-dlg \.sr \{ grid-template-columns: var\(--h-sm\) minmax\(0, 1fr\)( minmax\(\d+px, \d+px\)){4} var\(--h-md\); \}/)
    const chip = css.match(/\.sr-v \{[^}]*\}/)![0]
    expect(chip).toContain('font-size: var(--t11)')
    expect(chip).not.toMatch(/(height|line-height|gap|padding): [^;]*\dpx/)
  })
  it('多分辨率：「我的」页导航按视口夹、窄视口折到上方', () => {
    expect(css).toMatch(/#page-me \{ grid-template-columns: clamp\(200px, \d+vw, 280px\) minmax\(0, 1040px\);/)
    expect(css).toMatch(/@media \(max-width: 900px\) \{\s*#page-me \{ grid-template-columns: minmax\(0, 1fr\);/)
  })
})
