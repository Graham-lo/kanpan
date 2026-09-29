import { describe, expect, it } from 'vitest'
import {
  dayKey, dayLabel, decimalsOf, equityCurve, groupByDay, groupRateText, groupRounds, lastWeekRounds, lastWeekWindow,
  money, num, outcomeOf, ratioPct, resolvedGroups, roundDecimals, roundStats, sortTrades, symbolsOf, titleParts, viewSummary,
} from '../src/review/model'
import type { Fill, Round, Statistics, TradeRecord, ViewRecord } from '../src/review/types'

const H = 3600e3
/** 上海时间 → UTC 毫秒（月份从 1 起） */
const SH = (y: number, mo: number, d: number, h = 0, mi = 0): number => Date.UTC(y, mo - 1, d, h - 8, mi)
// 2026-09-29 是周二
const NOW = SH(2026, 9, 29, 12)

function fill(time: number, side: 'BUY' | 'SELL', price: string, qty: string, role: string): Fill {
  return { id: String(time), orderId: 'o' + time, time, side, positionSide: 'BOTH', price, qty, quoteQty: '0', commission: '0', commissionAsset: 'USDT', realizedPnl: '0', maker: false, role, split: false }
}
let seq = 0
function round(p: Partial<Round> & { net?: string }): Round {
  const openedAt = p.openedAt ?? SH(2026, 9, 20, 10)
  const closedAt = p.status === 'open' ? null : (p.closedAt ?? openedAt + H)
  return {
    id: 'r' + (++seq), version: 1, venue: 'binance', market: 'usd_m', symbol: 'BTCUSDT', accountTag: 'a', positionSide: 'BOTH',
    direction: 'long', status: 'closed', quoteAsset: 'USDT', openedAt, closedAt, holdingMs: closedAt == null ? null : closedAt - openedAt,
    openAvgPrice: '100', closeAvgPrice: closedAt == null ? null : '101', openedQty: '1', closedQty: '1', maxQty: '1', peakNotional: '100',
    leverage: 10, realizedPnl: p.net ?? '0', commission: '0', funding: '0', netPnl: p.net ?? '0', fills: [], updatedAt: 0,
    ...p,
  }
}
const trade = (r: Round, extra: Partial<TradeRecord> = {}): TradeRecord => ({ kind: 'trade', id: 't-' + r.id, revision: 1, submitted: 0, updated: 0, voided: false, round: r, result: null, note: null, ...extra })

describe('数字与文案', () => {
  it('num：十进制字符串转数字，空与非法当 0', () => {
    expect(num('2656.81')).toBe(2656.81)
    expect(num('')).toBe(0)
    expect(num(null)).toBe(0)
    expect(num('abc')).toBe(0)
  })
  it('decimalsOf / roundDecimals：按成交价原文的最长小数位', () => {
    expect(decimalsOf('2656.81')).toBe(2)
    expect(decimalsOf('64000')).toBe(0)
    expect(roundDecimals({ fills: [fill(0, 'BUY', '0.1234', '1', 'open'), fill(1, 'SELL', '0.12', '1', 'close')] })).toBe(4)
  })
  it('money：千分位 + 符号，负号用全角减号', () => {
    expect(money(1234.5)).toBe('+1,234.50')
    expect(money(-86.04)).toBe('−86.04')
    expect(money(0)).toBe('0.00')
  })
  it('ratioPct：服务端比例字符串 → 百分数', () => {
    expect(ratioPct('0.007647')).toBe('+0.76%')
    expect(ratioPct('-0.0123')).toBe('-1.23%')
    expect(ratioPct(null)).toBe('—')
  })
  it('titleParts：服务端分组标题按「 · 」拆段', () => {
    expect(titleParts('BTCUSDT · 做多 · 触价 · 目标≤ 0.5%')).toEqual(['BTCUSDT', '做多', '触价', '目标≤ 0.5%'])
  })
})

describe('上海时间', () => {
  it('dayKey 按上海日期切：UTC 16:30 已经是上海第二天', () => {
    expect(dayKey(Date.UTC(2026, 8, 28, 16, 30))).toBe('2026-09-29')
    expect(dayKey(Date.UTC(2026, 8, 28, 15, 59))).toBe('2026-09-28')
  })
  it('dayLabel：今天 / 昨天 / 几月几日 周几；跨年带年份', () => {
    expect(dayLabel(SH(2026, 9, 29, 0, 30), NOW)).toBe('今天')
    expect(dayLabel(SH(2026, 9, 28, 23, 59), NOW)).toBe('昨天')
    expect(dayLabel(SH(2026, 9, 27, 10), NOW)).toBe('9月27日 周日')
    expect(dayLabel(SH(2025, 12, 31, 10), NOW)).toBe('2025年12月31日 周三')
  })
  it('groupByDay：保持传入顺序，同一上海日期并成一组', () => {
    const ts = [SH(2026, 9, 29, 9), SH(2026, 9, 29, 1), SH(2026, 9, 28, 23), SH(2026, 9, 27, 8)]
    const g = groupByDay(ts, t => t, NOW)
    expect(g.map(x => x.label)).toEqual(['今天', '昨天', '9月27日 周日'])
    expect(g[0].items).toEqual([ts[0], ts[1]])
  })
  it('lastWeekWindow：上周一 0 点到本周一 0 点（上海）', () => {
    const w = lastWeekWindow(NOW)
    expect(w.from).toBe(SH(2026, 9, 21))
    expect(w.to).toBe(SH(2026, 9, 28))
    // 周一当天也算「本周」
    expect(lastWeekWindow(SH(2026, 9, 28, 0, 1)).to).toBe(SH(2026, 9, 28))
    // 周日算上一周的最后一天
    expect(lastWeekWindow(SH(2026, 9, 27, 23)).to).toBe(SH(2026, 9, 21))
  })
})

describe('交易回合统计', () => {
  const base = SH(2026, 9, 21, 10)
  const rs = [
    round({ net: '100', closedAt: base + 1 * H, commission: '2', funding: '-1' }),
    round({ net: '-50', closedAt: base + 2 * H, commission: '1' }),
    round({ net: '-30', closedAt: base + 3 * H }),
    round({ net: '60', closedAt: base + 4 * H, funding: '3' }),
    round({ status: 'open', net: '999' }),
  ]
  it('只算已平仓；胜率、平均赚亏、盈亏比、每笔期望、最长连亏', () => {
    const s = roundStats(rs)
    expect(s.count).toBe(4)
    expect(s.wins).toBe(2); expect(s.losses).toBe(2)
    expect(s.net).toBe(80)
    expect(s.winRate).toBe(0.5)
    expect(s.avgWin).toBe(80); expect(s.avgLoss).toBe(-40)
    expect(s.rewardRisk).toBe(2)
    expect(s.expectancy).toBe(20)
    expect(s.maxLosingStreak).toBe(2)
    // 费用 = 手续费 − 资金费（收到为正）：3 − 2 = 1
    expect(s.fees).toBe(1)
  })
  it('没有亏的回合时盈亏比为空；没有回合时各项为空', () => {
    expect(roundStats([round({ net: '5' })]).rewardRisk).toBeNull()
    const e = roundStats([])
    expect(e.winRate).toBeNull(); expect(e.expectancy).toBeNull(); expect(e.avgHoldingMs).toBeNull()
  })
  it('净盈亏为 0 算亏（没赚到）', () => {
    expect(roundStats([round({ net: '0' })]).losses).toBe(1)
  })
  it('lastWeekRounds：按平仓时间落在上周', () => {
    const a = round({ net: '1', closedAt: SH(2026, 9, 21, 0, 1) })
    const b = round({ net: '1', closedAt: SH(2026, 9, 28, 0, 1) })
    const c = round({ net: '1', closedAt: SH(2026, 9, 20, 23) })
    expect(lastWeekRounds([a, b, c], NOW).map(r => r.id)).toEqual([a.id])
  })
})

describe('分组', () => {
  it('按方向：固定先做多后做空，标签中文', () => {
    const g = groupRounds([round({ direction: 'short', net: '1' }), round({ direction: 'long', net: '-1' })], 'direction')
    expect(g.map(x => x.label)).toEqual(['做多', '做空'])
    expect(g[1].stats.net).toBe(1)
  })
  it('按持仓时长：分档与顺序', () => {
    const t0 = SH(2026, 9, 1)
    const g = groupRounds([
      round({ openedAt: t0, closedAt: t0 + 3 * 864e5, net: '1' }),
      round({ openedAt: t0, closedAt: t0 + 30 * 60e3, net: '1' }),
      round({ openedAt: t0, closedAt: t0 + 10 * 864e5, net: '1' }),
    ], 'holding')
    expect(g.map(x => x.key)).toEqual(['1 小时内', '7 天内', '7 天以上'])
  })
  it('按开仓时段与星期：按上海时间', () => {
    // 上海 9 月 29 日（周二）凌晨 1 点 = UTC 28 日（周一）17 点
    const r = round({ openedAt: SH(2026, 9, 29, 1), closedAt: SH(2026, 9, 29, 2), net: '1' })
    expect(groupRounds([r], 'session')[0].key).toBe('凌晨 0–6 点')
    expect(groupRounds([r], 'weekday')[0].key).toBe('周二')
  })
  it('按品种：回合多的在前', () => {
    const g = groupRounds([round({ symbol: 'ETHUSDT', net: '1' }), round({ symbol: 'SOLUSDT', net: '1' }), round({ symbol: 'SOLUSDT', net: '1' })], 'symbol')
    expect(g.map(x => x.key)).toEqual(['SOLUSDT', 'ETHUSDT'])
  })
})

describe('列表与曲线', () => {
  it('equityCurve：从 0 起，按平仓先后累加净盈亏', () => {
    const t = SH(2026, 9, 1)
    const e = equityCurve([round({ net: '5', closedAt: t + 2 * H }), round({ net: '-2', closedAt: t + H }), round({ status: 'open' })])
    expect(e.map(p => p.v)).toEqual([0, -2, 3])
  })
  it('sortTrades：作废的去掉，持仓中在前，其余平仓新到旧', () => {
    const t = SH(2026, 9, 1)
    const a = trade(round({ closedAt: t + H })), b = trade(round({ closedAt: t + 2 * H })), o = trade(round({ status: 'open' }))
    const v = trade(round({ closedAt: t + 3 * H }), { voided: true })
    expect(sortTrades([a, v, b, o]).map(x => x.id)).toEqual([o.id, b.id, a.id])
  })
  it('symbolsOf：按回合数从多到少', () => {
    expect(symbolsOf([trade(round({ symbol: 'ETHUSDT' })), trade(round({ symbol: 'SOLUSDT' })), trade(round({ symbol: 'SOLUSDT' }))])).toEqual(['SOLUSDT', 'ETHUSDT'])
  })
})

describe('观点记录', () => {
  const view = (dir: 'long' | 'short' | 'observe', outcome: string | null, voided = false): ViewRecord => ({
    draft: { id: 'v' + (++seq), range: { venue: 'binance', market: 'usd_m', symbol: 'BTCUSDT', interval: '1h', start: 0, end: 10 * H, bars: 10 }, rule: { version: 'v2', direction: dir, confirmation: 'bar_close', reference: 100, target: 102, invalidation: 99, expires: 20 * H }, text: '', confidence: null, origin: 'chart_first', created: 5 * H },
    serverId: null, submitted: null, revision: 1, assessment: outcome ? { outcome, reason: '', eventAt: null, assessedAt: 0 } : null, eligible: true, voided,
  })
  it('outcomeOf：作废优先；没评估时只记录算「只记录」，其余「等答案」', () => {
    expect(outcomeOf(view('long', 'realized', true))).toBe('voided')
    expect(outcomeOf(view('observe', null))).toBe('observation')
    expect(outcomeOf(view('short', null))).toBe('waiting')
  })
  it('viewSummary：按结果计数，作废不算', () => {
    const s = viewSummary([view('long', 'realized'), view('long', 'unrealized'), view('long', 'waiting'), view('observe', 'observation'), view('long', 'needs_verification'), view('long', 'realized', true)])
    expect(s).toEqual({ total: 5, realized: 1, unrealized: 1, waiting: 1, observation: 1, other: 1 })
  })
})

describe('观点战绩（服务端分组，照手机端 resolvedGroups）', () => {
  const stats: Statistics = {
    grouping: 'exact', comparableGrouping: 'relative', asOf: 0,
    groups: [{ id: 'g1', title: 'ETHUSDT · 想法在先 · 收盘', correct: 0, total: 1 }],
    comparableGroups: [
      { id: 'c1', title: 'BTCUSDT · 做多 · 触价', correct: 1, total: 1, verdictStatus: 'insufficient' },
      { id: 'c2', title: 'ETHUSDT · 做空 · 收盘', correct: 0, total: 0 },
    ],
    comparableProof: { compatible_groups: { c2: { denominator: 25, numerator: 15, verdict_status: 'verdict_due', recheck: true } } },
  }
  it('有相对口径就只用相对口径，证据里的判定「有才盖」', () => {
    const g = resolvedGroups(stats)
    expect(g.map(x => x.id)).toEqual(['c1', 'c2'])
    expect(g[0].verdictStatus).toBe('insufficient') // 证据里没写，不能抹掉
    expect(g[1]).toMatchObject({ total: 25, correct: 15, verdictStatus: 'verdict_due', recheck: true })
  })
  it('老服务端没有相对口径时退回 groups', () => {
    const old: Statistics = { ...stats, comparableGroups: undefined, proof: { compatible_groups: { g1: { verdict_status: 'insufficient' } } } }
    const g = resolvedGroups(old)
    expect(g.map(x => x.id)).toEqual(['g1'])
    expect(g[0].verdictStatus).toBe('insufficient')
  })
  it('groupRateText：样本不足不给百分比，够了才给', () => {
    const g = resolvedGroups(stats)
    expect(groupRateText(g[0])).toBe('样本不足')
    expect(groupRateText(g[1])).toBe('60%')
    expect(groupRateText({ id: 'x', title: '', correct: 0, total: 0 })).toBe('—')
    expect(resolvedGroups(null)).toEqual([])
  })
})
