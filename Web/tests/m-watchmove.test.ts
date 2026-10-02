/* 手机网页版 · 自选波动提醒判定（m/model/watchMove.ts，照 iOS WatchMoveTests） */
import { describe, expect, it } from 'vitest'
import { autoThreshold, MoveGate, MoveSeries, MoveTracker, moveNotifyId, moveTitle, WM } from '../src/m/model/watchMove'

const M = 60_000

describe('autoThreshold', () => {
  it('不到 30 根用 1.5%', () => {
    expect(autoThreshold([])).toBe(WM.fallback)
    expect(autoThreshold(new Array(29).fill(0.001))).toBe(WM.fallback)
  })
  it('5σ 夹在 0.5%…10%', () => {
    // 中位绝对收益 0.001 → σ5 = √5 × 1.4826 × 0.001，5σ ≈ 1.6576%
    expect(autoThreshold(new Array(40).fill(0.001))).toBeCloseTo(5 * Math.sqrt(5) * 1.4826 * 0.1, 6)
    expect(autoThreshold(new Array(40).fill(0.00001))).toBe(WM.min)
    expect(autoThreshold(new Array(40).fill(0.05))).toBe(WM.max)
  })
  it('只看最近 1440 根，负收益取绝对值', () => {
    const r = [...new Array(2000).fill(0.05), ...new Array(1440).fill(-0.001)]
    expect(autoThreshold(r)).toBeCloseTo(autoThreshold(new Array(40).fill(0.001)), 6)
  })
})

describe('MoveSeries', () => {
  it('现价对 5 分钟前那根的收盘', () => {
    const s = new MoveSeries()
    for (let i = 0; i < 5; i++) expect(s.observe(i * M, 100, true)).toBeNull()
    expect(s.observe(5 * M, 103, false)).toBeCloseTo(0.03, 9)
  })
  it('没收盘的那根在下一根来时补上收盘', () => {
    const s = new MoveSeries()
    s.observe(0, 100, false)
    s.observe(0, 101, false)
    s.observe(M, 101, false)
    expect(s.closes.get(0)).toBe(101)
    expect(s.returns.length).toBe(0)
    s.observe(2 * M, 102, false)
    expect(s.returns.length).toBe(1)
  })
  it('回头的时间丢掉；切后台忘掉价', () => {
    const s = new MoveSeries()
    s.observe(5 * M, 100, true)
    expect(s.observe(4 * M, 50, true)).toBeNull()
    s.forgetPrices()
    expect(s.closes.size).toBe(0)
    expect(s.currentOpen).toBeNull()
  })
})

describe('MoveGate', () => {
  it('过门槛响一次，回到门槛内才重新上膛；同一窗口不响第二次', () => {
    const g = new MoveGate()
    expect(g.pass(0.03, 0.02, 0)).toBe(true)
    expect(g.pass(0.04, 0.02, 0)).toBe(false)
    expect(g.pass(0.01, 0.02, 0)).toBe(false)
    expect(g.pass(0.03, 0.02, 0)).toBe(false)
    expect(g.pass(0.01, 0.02, 300_000)).toBe(false)
    expect(g.pass(0.03, 0.02, 300_000)).toBe(true)
  })
})

describe('MoveTracker', () => {
  const warm = (t: MoveTracker, sym: string): void => { for (let i = 0; i < 5; i++) t.observe(sym, i * M, 100, true) }
  it('涨过门槛出事件，灵敏度乘在门槛上', () => {
    const t = new MoveTracker()
    warm(t, 'binance/usd_m/BTCUSDT')
    expect(t.observe('binance/usd_m/BTCUSDT', 5 * M, 101, false)).toBeNull() // 1% < 1.5%
    const t2 = new MoveTracker()
    warm(t2, 'X')
    const e = t2.observe('X', 5 * M, 101, false, 0.5) // 门槛 0.75%
    expect(e?.direction).toBe('up')
    expect(e?.window).toBe(300_000)
  })
  it('跌也报', () => {
    const t = new MoveTracker()
    warm(t, 'X')
    expect(t.observe('X', 5 * M, 97, false)?.direction).toBe('down')
  })
  it('keep 丢掉不在自选里的', () => {
    const t = new MoveTracker()
    warm(t, 'A'); warm(t, 'B')
    t.observe('A', 5 * M, 110, false)
    t.keep(['B'])
    expect([...t.series.keys()]).toEqual(['B'])
    expect([...t.gates.keys()].every(k => k.startsWith('B|'))).toBe(true)
  })
  it('标题与通知 id', () => {
    expect(moveTitle('BTC', { direction: 'up', change: 0.03214 })).toBe('BTC 五分钟涨 3.21%')
    expect(moveTitle('ETH', { direction: 'down', change: -0.05 })).toBe('ETH 五分钟跌 5.00%')
    expect(moveNotifyId({ symbol: 'S', direction: 'up', window: 9 })).toBe('move.S.up.9')
  })
})
