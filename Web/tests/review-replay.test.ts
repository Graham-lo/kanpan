import { describe, expect, it } from 'vitest'
import {
  AFTER_MATCH_BARS, HISTORY_BARS, LEAD_BARS, TAIL_BARS,
  chooseInterval, chooseSpeed, planMatch, planNote, planTrade, positionAt, stepDelay, timeAtPos, trackPos, visibleMarks,
} from '../src/review/replay'
import type { Fill, Match, Round, TradeResult, ViewRecord } from '../src/review/types'

const M = 60e3, H = 3600e3, M5 = 5 * M
const T0 = Date.UTC(2026, 8, 20, 2, 0) // 整 5 分钟
const NOW = Date.UTC(2026, 8, 29, 4, 0)

function fill(time: number, side: 'BUY' | 'SELL', price: string, qty: string, role: string): Fill {
  return { id: String(time), orderId: 'o', time, side, positionSide: 'BOTH', price, qty, quoteQty: '0', commission: '0', commissionAsset: 'USDT', realizedPnl: '0', maker: false, role, split: false }
}
function round(fills: Fill[], p: Partial<Round> = {}): Round {
  const closed = p.status !== 'open'
  return {
    id: 'r', version: 1, venue: 'binance', market: 'usd_m', symbol: 'BTCUSDT', accountTag: 'a', positionSide: 'BOTH', direction: 'long',
    status: 'closed', quoteAsset: 'USDT', openedAt: fills[0].time, closedAt: closed ? fills[fills.length - 1].time : null, holdingMs: null,
    openAvgPrice: '0', closeAvgPrice: null, openedQty: '0', closedQty: '0', maxQty: '0', peakNotional: '0', leverage: null,
    realizedPnl: '0', commission: '0', funding: '0', netPnl: '0', fills, updatedAt: 0, ...p,
  }
}
const result = (iv: string): TradeResult => ({ after: { h1: null, h4: null, h24: null }, chart: { interval: iv, start: 0, end: 0 }, computedAt: 0, excursion: null, version: 1 })

// 做多：开 1 @100，30 分钟后加 1 @110，60 分钟减 1，90 分钟平掉剩下的
const LONG = round([
  fill(T0 + 2 * M, 'BUY', '100', '1', 'open'),
  fill(T0 + 32 * M, 'BUY', '110', '1', 'add'),
  fill(T0 + 61 * M, 'SELL', '112', '1', 'reduce'),
  fill(T0 + 91 * M, 'SELL', '108', '1', 'close'),
])

describe('周期与速度', () => {
  it('偏好周期能放下 10–200 根就用它', () => {
    expect(chooseInterval(0, 3 * H, '1m')).toBe('1m') // 180 根
    expect(chooseInterval(0, 3 * H, '1d', '5m')).toBe('5m') // 日线放不下，退回服务端周期
  })
  it('都没有时挑最接近 30–60 根的', () => {
    expect(chooseInterval(0, 3 * H)).toBe('5m')   // 36 根
    expect(chooseInterval(0, 45 * M)).toBe('1m')  // 45 根
    expect(chooseInterval(0, 48 * H)).toBe('1h')  // 48 根
    expect(chooseInterval(0, 60 * 864e5)).toBe('1d')
  })
  it('自动速度：总时长不超过 40 秒的最小一档', () => {
    expect(chooseSpeed(30)).toBe(1)
    expect(chooseSpeed(70)).toBe(2)
    expect(chooseSpeed(100)).toBe(4)
    expect(chooseSpeed(5000)).toBe(4)
  })
  it('每根的等待：1 秒 ÷ 速度，关键点多停 1.2 秒', () => {
    expect(stepDelay(2, false)).toBe(500)
    expect(stepDelay(1, true)).toBe(2200)
  })
})

describe('交易回放计划', () => {
  const p = planTrade(LONG, result('5m'), NOW, '  突破前高就上  ')
  it('周期取服务端结果的周期；从开仓前 20 根开始，平仓后 5 根停；往前多拉 300 根', () => {
    expect(p.iv).toBe('5m')
    expect(p.openBar).toBe(T0)
    expect(p.closeBar).toBe(T0 + 90 * M)
    expect(p.startBar).toBe(T0 - LEAD_BARS * M5)
    expect(p.stopBar).toBe(T0 + 90 * M + TAIL_BARS * M5)
    expect(p.fetchFrom).toBe(p.startBar - HISTORY_BARS * M5)
    expect(p.initialBar).toBe(p.openBar)
  })
  it('关键点只有开仓处与平仓处，两处都停；进度线上每笔成交一个刻度', () => {
    expect(p.keys.map(k => [k.id, k.label, k.pause])).toEqual([['open', '开仓处', true], ['close', '平仓处', true]])
    expect(p.ticks.map(t => t.kind)).toEqual(['entry', 'entry', 'exit', 'exit'])
    expect(p.note).toBe('突破前高就上')
  })
  it('开仓均价：每笔开 / 加仓之后重算，一段一段接上', () => {
    expect(p.avgSegs).toEqual([
      { from: T0, to: T0 + 30 * M, price: 100 },
      { from: T0 + 30 * M, to: T0 + 90 * M, price: 105 },
    ])
  })
  it('未来的成交不画：只露出已经放到的', () => {
    expect(visibleMarks(p, T0 - M5)).toHaveLength(0)
    expect(visibleMarks(p, T0 + 45 * M).map(m => m.role)).toEqual(['open', 'add'])
    expect(visibleMarks(p, p.stopBar)).toHaveLength(4)
  })
  it('持仓与浮动收益：开仓前与平仓后为空；减仓不动均价', () => {
    expect(positionAt(p, T0 - M5, 100)).toBeNull()
    expect(positionAt(p, T0 + 30 * M, 105 * 1.02)).toMatchObject({ qty: 2, avg: 105 })
    expect(positionAt(p, T0 + 30 * M, 107.1)!.floating).toBeCloseTo(0.02, 10)
    expect(positionAt(p, T0 + 60 * M, 100)).toMatchObject({ qty: 1, avg: 105 })
    expect(positionAt(p, T0 + 90 * M, 100)).toBeNull()
  })
  it('做空时价格下跌是浮盈', () => {
    const s = planTrade(round([fill(T0, 'SELL', '100', '1', 'open'), fill(T0 + H, 'BUY', '95', '1', 'close')], { direction: 'short' }), result('5m'), NOW)
    expect(positionAt(s, T0 + 10 * M, 98)!.floating).toBeCloseTo(0.02, 10)
  })
  it('持仓中的回合：放到现在为止，只有开仓处一个关键点', () => {
    const now = T0 + 2 * H + 7 * M
    const o = planTrade(round([fill(T0, 'BUY', '100', '1', 'open')], { status: 'open' }), null, now)
    expect(o.closed).toBe(false)
    expect(o.stopBar).toBe(Math.floor(now / M5) * M5)
    expect(o.keys.map(k => k.id)).toEqual(['open'])
    expect(positionAt(o, o.stopBar, 101)).toMatchObject({ qty: 1, avg: 100 })
  })
  it('刚平仓不久：停在「现在」而不是平仓后 5 根', () => {
    const now = T0 + 91 * M + 3 * M
    const q = planTrade(LONG, result('5m'), now)
    expect(q.stopBar).toBe(Math.floor(now / M5) * M5)
  })
})

describe('在图上重温（观点记录）', () => {
  const rec = (p: { direction?: 'long' | 'short' | 'observe'; eventAt?: number | null; outcome?: string; expires?: number }): ViewRecord => ({
    draft: {
      id: 'v', range: { venue: 'binance', market: 'usd_m', symbol: 'ETHUSDT', interval: '15m', start: T0 - 64 * 15 * M, end: T0, bars: 64 },
      rule: { version: 'v2', direction: p.direction ?? 'long', confirmation: 'trade_touch', reference: 100, target: 101, invalidation: 99, expires: p.expires ?? T0 + 12 * H },
      text: '回踩不破就多', confidence: null, origin: 'chart_first', created: T0 + 3 * M,
    },
    serverId: 's', submitted: T0 + 4 * M, revision: 1,
    assessment: p.outcome ? { outcome: p.outcome, reason: '', eventAt: p.eventAt ?? null, assessedAt: 0 } : null,
    eligible: true, voided: false,
  })
  it('从图表区间起点开始，停在判断处；答案出来那根后再放 5 根', () => {
    const p = planNote(rec({ outcome: 'realized', eventAt: T0 + 2 * H + 7 * M }), NOW)
    expect(p.iv).toBe('15m')
    expect(p.startBar).toBe(T0 - 64 * 15 * M)
    expect(p.judgeBar).toBe(T0)
    expect(p.initialBar).toBe(T0)
    expect(p.eventBar).toBe(T0 + 2 * H)
    expect(p.stopBar).toBe(T0 + 2 * H + TAIL_BARS * 15 * M)
    expect(p.keys.map(k => k.label)).toEqual(['判断处', '答案处'])
  })
  it('没答案但已到期：关键点是到期处', () => {
    const p = planNote(rec({ outcome: 'waiting', expires: T0 + 6 * H }), NOW)
    expect(p.expireBar).toBe(T0 + 6 * H)
    expect(p.keys.map(k => k.id)).toEqual(['judge', 'expire'])
  })
  it('只记录：没有到期，放到现在', () => {
    const now = T0 + 3 * H
    const p = planNote(rec({ direction: 'observe', outcome: 'observation' }), now)
    expect(p.expireBar).toBeNull()
    expect(p.stopBar).toBe(now)
    expect(p.keys.map(k => k.id)).toEqual(['judge'])
  })
})

describe('相似片段', () => {
  const m: Match = { id: 'm', score: 0.6, source: 'history', range: { venue: 'binance', market: 'usd_m', symbol: 'UNIUSDT', interval: '15m', start: T0, end: T0 + 64 * 15 * M, bars: 64 } }
  it('整段先摆出来，停在相似段最后一根；往后放 40 根', () => {
    const p = planMatch(m, NOW)
    const last = T0 + 63 * 15 * M
    expect(p.initialBar).toBe(last)
    expect(p.startBar).toBe(T0)
    expect(p.stopBar).toBe(last + AFTER_MATCH_BARS * 15 * M)
    expect(p.keys).toEqual([{ id: 'segEnd', label: '相似段结束', t: last, pause: false }])
  })
})

describe('进度线', () => {
  const p = { startBar: 1000, stopBar: 2000, step: 100 }
  it('trackPos 夹在 0–1', () => {
    expect(trackPos(p, 1500)).toBe(0.5)
    expect(trackPos(p, 0)).toBe(0)
    expect(trackPos(p, 9999)).toBe(1)
    expect(trackPos({ startBar: 5, stopBar: 5 }, 5)).toBe(1)
  })
  it('timeAtPos 对齐到周期，与 trackPos 互逆', () => {
    expect(timeAtPos(p, 0.54)).toBe(1500)
    expect(timeAtPos(p, -1)).toBe(1000)
    expect(timeAtPos(p, 2)).toBe(2000)
    for (let t = 1000; t <= 2000; t += 100) expect(timeAtPos(p, trackPos(p, t))).toBe(t)
  })
})
