/* 手机网页版 · 行情页回放的纯逻辑（src/m/model/replayLogic.ts）。口径照 iOS ReviewChartBridge / ReviewReplayPolicy。 */
import { describe, expect, it } from 'vitest'
import * as R from '../src/m/model/replayLogic'
import { planTrade, type TradePlan } from '../src/review/replay'
import type { Round } from '../src/review/types'

const H = 3_600_000
const T0 = Date.UTC(2026, 8, 1, 0)
const round: Round = {
  id: 'r1', venue: 'binance', market: 'usd_m', symbol: 'BTCUSDT', direction: 'long', status: 'closed',
  openedAt: T0, closedAt: T0 + 30 * H,
  fills: [
    { time: T0 + 5 * 60_000, role: 'open', side: 'BUY', price: '100', qty: '1' },
    { time: T0 + 10 * H, role: 'add', side: 'BUY', price: '110', qty: '1' },
    { time: T0 + 20 * H, role: 'reduce', side: 'SELL', price: '120', qty: '1' },
    { time: T0 + 30 * H, role: 'close', side: 'SELL', price: '125', qty: '1' },
  ],
} as unknown as Round
const now = T0 + 400 * H
const plan = (): TradePlan => planTrade(round, null, now, '追突破', '1h')
const intent = (p: unknown = plan(), extra: Record<string, unknown> = {}) => JSON.parse(JSON.stringify({ kind: 'trade', at: now, plan: p, ...extra }))

describe('手机网页版 · 回放意图', () => {
  it('好的意图认下来，带上市场', () => {
    const got = R.parseIntent(intent(plan(), { market: 'binance/usd_m' }), now + 1000)
    expect(got?.kind).toBe('trade')
    expect(got?.plan.symbol).toBe('BTCUSDT')
    expect(got?.market).toBe('binance/usd_m')
    expect(R.parseIntent(intent(), now)?.market).toBeNull()
  })
  it('过期、种类对不上、形状坏的一律不认', () => {
    expect(R.parseIntent(intent(), now + R.INTENT_TTL_MS + 1)).toBeNull()
    expect(R.parseIntent({ ...intent(), kind: 'revisit' }, now)).toBeNull()
    expect(R.parseIntent({ ...intent(), plan: { ...plan(), iv: '7m' } }, now)).toBeNull()
    expect(R.parseIntent({ ...intent(), plan: { ...plan(), symbol: 'btc/usdt' } }, now)).toBeNull()
    expect(R.parseIntent({ ...intent(), plan: { ...plan(), marks: null } }, now)).toBeNull()
    expect(R.parseIntent({ ...intent(), plan: { ...plan(), stopBar: 0 } }, now)).toBeNull()
    expect(R.parseIntent(null, now)).toBeNull()
    expect(R.parseIntent('x', now)).toBeNull()
  })
  it('只放得了币安 U 本位', () => {
    expect(R.replayableMarket(null)).toBe(true)
    expect(R.replayableMarket('binance/usd_m')).toBe(true)
    expect(R.replayableMarket('okx/swap')).toBe(false)
  })
})

describe('手机网页版 · 回放的卷', () => {
  const p = plan()
  const times = (n: number, from = p.fetchFrom) => Array.from({ length: n }, (_, i) => from + i * p.step)
  it('超过 6000 根不拉', () => {
    expect(R.tapeTooLarge({ fetchFrom: 0, fetchTo: 6001 * H, step: H })).toBe(true)
    expect(R.tapeTooLarge(p)).toBe(false)
  })
  it('不到三根、开仓之后没有 K 线 → 没历史；断档 → 有缺口', () => {
    expect(R.checkTape(times(2), p)).toBe('noHistory')
    expect(R.checkTape(times(10, p.fetchFrom), p)).toBe('noHistory')
    const full = times(Math.round((p.fetchTo - p.fetchFrom) / p.step))
    expect(R.checkTape(full, p)).toBeNull()
    const gap = full.filter((_, i) => i !== 350)
    expect(R.checkTape(gap, p)).toBe('gap')
  })
})

describe('手机网页版 · 回放的游标与进度线', () => {
  const ts = [0, 10, 20, 30, 40, 50, 60]
  it('atOrBefore / atOrAfter，最小是 2', () => {
    expect(R.indexAtOrBefore(ts, 35)).toBe(3)
    expect(R.indexAtOrBefore(ts, 30)).toBe(3)
    expect(R.indexAtOrBefore(ts, -5)).toBe(2)
    expect(R.indexAtOrBefore(ts, 999)).toBe(6)
    expect(R.indexAtOrAfter(ts, 35)).toBe(4)
    expect(R.indexAtOrAfter(ts, 5)).toBe(2)
  })
  it('进度线按根算：两头夹住，刻度按根落位', () => {
    const tr: R.Track = { lower: 2, upper: 6, marks: [3, 5] }
    expect(R.fractionOf(tr, 2)).toBe(0)
    expect(R.fractionOf(tr, 4)).toBe(0.5)
    expect(R.fractionOf(tr, 9)).toBe(1)
    expect(R.indexAtFraction(tr, 0.6)).toBe(4)
    expect(R.indexAtFraction(tr, -1)).toBe(2)
    expect(R.markFractions(tr)).toEqual([0.25, 0.75])
    expect(R.fractionOf({ lower: 3, upper: 3, marks: [] }, 3)).toBe(1)
  })
  it('拖过刻度才算，出发那根不算', () => {
    const tr: R.Track = { lower: 2, upper: 6, marks: [3, 5] }
    expect(R.crossesMark(tr, 2, 3)).toBe(true)
    expect(R.crossesMark(tr, 3, 4)).toBe(false)
    expect(R.crossesMark(tr, 6, 4)).toBe(true)
    expect(R.crossesMark(tr, 4, 4)).toBe(false)
  })
  it('交易回放的轨道：开仓前 20 根到平仓后 5 根，刻度在每笔成交', () => {
    const p = plan()
    const times = Array.from({ length: Math.round((p.fetchTo - p.fetchFrom) / p.step) }, (_, i) => p.fetchFrom + i * p.step)
    const tr = R.makeTrack(times, p)
    expect(times[tr.lower]).toBe(p.startBar)
    expect(times[tr.upper]).toBe(p.stopBar)
    expect(tr.marks.map(i => times[i])).toEqual(p.marks.map(m => m.bar))
  })
  it('打开、重播、关键点、速度', () => {
    const p = plan()
    expect(R.openTime(p)).toBe(p.startBar)
    expect(R.autoplays(p)).toBe(true)
    expect(R.restartTime(p)).toBe(p.startBar)
    expect(R.keyTime(p)).toBe(p.openBar)
    expect(R.keyTitle(p)).toBe('开仓处')
    expect(R.pausesAt(p, p.openBar)).toBe(true)
    expect(R.pausesAt(p, p.openBar + p.step)).toBe(false)
    expect([1, 2, 4].map(R.cycleSpeed)).toEqual([2, 4, 1])
  })
})

describe('手机网页版 · 回放视野（ReviewReplayViewport.next）', () => {
  const step = 10
  it('reset / 没视野 → 80 根、右边留 6 根', () => {
    expect(R.nextWindow(null, null, 1000, step, false)).toEqual({ to: 1060, span: 800 })
    expect(R.nextWindow({ to: 500, span: 300 }, 990, 1000, step, true)).toEqual({ to: 1060, span: 800 })
  })
  it('跟着播放头往前推、根宽不动；人拖去看别处就不拽回来', () => {
    expect(R.nextWindow({ to: 1050, span: 300 }, 990, 1000, step, false)).toEqual({ to: 1060, span: 300 })
    expect(R.nextWindow({ to: 500, span: 300 }, 990, 1000, step, false)).toEqual({ to: 500, span: 300 })
    expect(R.nextWindow({ to: 500, span: 300 }, null, 1000, step, false)).toEqual({ to: 1060, span: 300 })
  })
})

describe('手机网页版 · 回放页头文字', () => {
  it('标题、胶囊、时刻', () => {
    const p = plan()
    expect(R.replayTitle(p)).toBe('回放 · BTCUSDT · 1时')
    expect(R.capsuleText(0.01234)).toBe('+1.23%')
    expect(R.capsuleText(-0.004)).toBe('-0.40%')
    expect(R.capsuleText(-0.00001)).toBe('+0.00%')
    expect(R.replayTime(Date.UTC(2026, 8, 1, 0, 5), '1h')).toBe('2026-09-01 08:05')
    expect(R.replayTime(Date.UTC(2026, 8, 1, 0, 5), '1d')).toBe('2026-09-01')
  })
  it('成交叫法：开 / 加 / 减 / 平；没平完的最后一笔离场叫减', () => {
    const p = plan()
    expect(p.marks.map(m => R.tradeWord(p, m))).toEqual(['开', '加', '减', '平'])
    const open = { ...p, closed: false }
    expect(open.marks.map(m => R.tradeWord(open, m))).toEqual(['开', '加', '减', '减'])
  })
  it('副图：交易回放一个不留；其余去掉外部数据', () => {
    expect(R.replaySubs(['VOL', 'OI', 'MACD'], 'trade')).toEqual([])
    expect(R.replaySubs(['VOL', 'OI', 'MACD', 'LSR'], 'note')).toEqual(['VOL', 'MACD'])
  })
})

describe('手机网页版 · 成交标签落位', () => {
  const bounds = { x: 0, y: 0, w: 200, h: 200 }
  const right = { x: 110, y: 50, w: 40, h: 14 }, left = { x: 50, y: 50, w: 40, h: 14 }, below = { x: 80, y: 80, w: 40, h: 14 }
  it('先挑不压蜡烛的；都压就退一步；出界和压三角的不要', () => {
    expect(R.placeLabel([right, left], bounds, [], [])).toBe(right)
    expect(R.placeLabel([right, left], bounds, [], [{ x: 120, y: 40, w: 4, h: 40 }])).toBe(left)
    expect(R.placeLabel([right], bounds, [], [{ x: 120, y: 40, w: 4, h: 40 }])).toBe(right)
    expect(R.placeLabel([right, below], bounds, [{ x: 100, y: 45, w: 20, h: 20 }], [])).toBe(below)
    expect(R.placeLabel([{ x: 190, y: 0, w: 40, h: 14 }], bounds, [], [])).toBeNull()
  })
})
