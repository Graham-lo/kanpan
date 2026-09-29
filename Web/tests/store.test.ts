import { describe, expect, it } from 'vitest'
import { clampActive, hydrate, validIv, validSymbol, type Layout, type State } from '../src/app/store'
import { MAX_SUBS } from '../src/chart/calc'

describe('页面状态', () => {
  it('当前格收进布局格数以内：八图第 3 格改成一图 → 第 0 格（地址栏 ?layout=1&s=… 才落在看得见的格子上）', () => {
    const s = { active: 2, layout: '1' as Layout }
    clampActive(s)
    expect(s.active).toBe(0)
    const t = { active: 5, layout: '4' as Layout }
    clampActive(t)
    expect(t.active).toBe(3)
    const u = { active: Number.NaN, layout: '8' as Layout }
    clampActive(u)
    expect(u.active).toBe(0)
  })

  it('读盘时也收：存着 active 越界的老状态起来是第 0 格', () => {
    expect(hydrate({ layout: '2', active: 7 }).active).toBe(1)
    expect(hydrate({ layout: '1', active: 2 }).active).toBe(0)
  })

  it('副图上限三个（和手机端 Prefs.maxSubs 一致）：本机存着四个的收成前三个，成交量不占名额', () => {
    expect(MAX_SUBS).toBe(3)
    const s = hydrate({ ind: { ma: true, ema: false, boll: false, vol: true, subs: ['macd', 'rsi', 'kdj', 'oi'] } })
    expect(s.ind.subs).toEqual(['macd', 'rsi', 'kdj'])
    expect(s.ind.vol).toBe(true)
  })

  it('读坏存档逐项验形状：坏周期回第 0 格的、坏字段回默认、认不出的副图与小部件丢掉（2026-09-29 压测）', () => {
    const bad = {
      layout: 4, cells: [{ symbol: 'ETHUSDT', iv: '15m' }, { symbol: 'BTCUSDT', iv: '7x' }, null, { symbol: 42 }, 'x', { symbol: 'SOLUSDT', iv: '' }],
      pinned: 'abc', watch: { crypto: 'BTCUSDT', us: null, com: ['XAUUSDT', 5, 'XAUUSDT'] },
      ind: { ma: 'yes', vol: false, subs: ['macd', 'nope', 7, 'macd', 'rsi'] },
      params: { ma: 'x', macd: { fast: 'a', slow: 30 }, nope: { n: 3 } },
      panel: 'zzz', watchTab: 'zzz', lastPanel: 3, magnet: 'yes', drawColor: 'red',
      slots: { ladder: 'yes', drawer: 1, widgets: ['watch', 'zzz', 'detail', 'detail'] },
      drawStyles: { line: 'red', shape: { color: 5, width: 'x', dash: 'dashed' } }, toolLast: { line: 5, shape: 'rect' },
    } as unknown as Partial<State>
    const s = hydrate(bad)
    expect(s.layout).toBe('4')
    expect(s.cells.slice(0, 6).every(c => validIv(c.iv) && typeof c.symbol === 'string')).toBe(true)
    expect(s.cells[1]).toEqual({ symbol: 'BTCUSDT', iv: '15m' })
    expect(s.pinned).toEqual(['1m', '5m', '15m', '1h', '4h', '1d', '1w'])
    expect(s.watch.crypto.length).toBeGreaterThan(0)
    expect(s.watch.com).toEqual(['XAUUSDT'])
    expect(s.ind.ma).toBe(true)
    expect(s.ind.vol).toBe(false)
    expect(s.ind.subs).toEqual(['macd', 'rsi'])
    expect(s.params).toEqual({ macd: { fast: 12, slow: 30, signal: 9 } })
    expect(s.panel).toBe('watch'); expect(s.watchTab).toBe('crypto'); expect(s.lastPanel).toBe('watch')
    expect(s.magnet).toBe(false); expect(s.drawColor).toBe('#2962FF')
    expect(s.slots).toEqual({ ladder: false, drawer: false, widgets: ['watch', 'detail'] })
    expect(s.drawStyles).toEqual({ shape: { dash: 'dashed' } })
    expect(s.toolLast).toEqual({ shape: 'rect' })
    // 整份不是对象
    expect(hydrate([1, 2] as unknown as Partial<State>).layout).toBe('1')
    expect(hydrate(null as unknown as Partial<State>).cells[0]).toEqual({ symbol: 'BTCUSDT', iv: '1h' })
  })

  it('周期键：原生、秒级、自定义分钟认，重复原生的分钟数与乱写的不认', () => {
    for (const iv of ['1m', '4h', '1d', '1w', '1M', '1s', '15s', '45m', '7m']) expect(validIv(iv)).toBe(true)
    for (const iv of ['7x', '', '60m', '1m ', '1441m', 5, null]) expect(validIv(iv)).toBe(false)
  })

  it('品种代号：中文名的合约（币安人生USDT）也认，读存档时自选与格子都不丢', () => {
    for (const s of ['BTCUSDT', '1000PEPEUSDT', '币安人生USDT', '龙虾USDT']) expect(validSymbol(s)).toBe(true)
    for (const s of ['', 'B', 'BTC USDT', 'BTC/USDT', 42, null]) expect(validSymbol(s)).toBe(false)
    const s = hydrate({ watch: { crypto: ['BTCUSDT', '币安人生USDT'], us: [], com: [] }, cells: [{ symbol: '龙虾USDT', iv: '1h' }] } as unknown as Partial<State>)
    expect(s.watch.crypto).toEqual(['BTCUSDT', '币安人生USDT'])
    expect(s.cells[0].symbol).toBe('龙虾USDT')
  })
})
