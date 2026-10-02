/* 手机网页版 · 复盘本的纯逻辑（m/model/reviewBook.ts）：照 iOS ReviewModels / ReviewBookSections / RoundStats / TradeLabels 对账 */
import { describe, expect, it } from 'vitest'
import * as M from '../src/m/model/reviewBook'
import type { RecordRevision, Round, TradeRecord, ViewRecordFull } from '../src/review/types'

const T0 = Date.UTC(2026, 8, 30, 4, 0) // 2026-09-30 12:00 上海（周三）

function view(o: {
  id?: string; dir?: 'long' | 'short' | 'observe'; outcome?: string | null; published?: boolean; voided?: boolean
  groupPending?: boolean; syncError?: string | null; eligible?: boolean; text?: string; created?: number; submitted?: number | null
  originalClaimed?: number | null
} = {}): ViewRecordFull {
  const created = o.created ?? T0
  return {
    draft: {
      id: o.id ?? 'r1',
      range: { venue: 'binance', market: 'usd_m', symbol: 'BTCUSDT', interval: '1h', start: created - 3_600_000 * 20, end: created, bars: 20 },
      rule: { version: 'criteria-v2', direction: o.dir ?? 'long', confirmation: 'bar_close', reference: 100, target: 110, invalidation: 95, expires: created + 864e5 },
      text: o.text ?? '回踩不破', confidence: null, origin: 'chart_first', created,
      ...(o.originalClaimed !== undefined ? { originalClaimed: o.originalClaimed } : {}),
    },
    serverId: 'srv', submitted: o.submitted === undefined ? created : o.submitted, revision: 1,
    assessment: o.outcome ? { outcome: o.outcome, reason: '收盘到了目标', eventAt: null, assessedAt: created } : null,
    reflection: { note: o.published ? '对了' : '', nextTime: '', publishedAt: o.published ? created : null, revision: 0 },
    eligible: o.eligible ?? true, voided: o.voided ?? false, groupPending: o.groupPending ?? false, syncError: o.syncError ?? null,
  }
}

function round(o: Partial<Round> & { net: number; id: string }): Round {
  return {
    id: o.id, version: 1, venue: 'binance', market: 'usd_m', symbol: o.symbol ?? 'BTCUSDT', accountTag: 'a', positionSide: 'BOTH',
    direction: o.direction ?? 'long', status: o.status ?? 'closed', quoteAsset: 'USDT',
    openedAt: o.openedAt ?? T0 - 3_600_000, closedAt: o.closedAt === undefined ? T0 : o.closedAt, holdingMs: o.holdingMs === undefined ? 3_600_000 : o.holdingMs,
    openAvgPrice: '100', closeAvgPrice: '101', openedQty: '1', closedQty: '1', maxQty: '1', peakNotional: '100', leverage: 10,
    realizedPnl: o.realizedPnl ?? String(o.net + 1), commission: o.commission ?? '1', funding: o.funding ?? '0', netPnl: String(o.net), fills: [], updatedAt: T0,
  }
}
const trade = (r: Round, voided = false): TradeRecord => ({ kind: 'trade', id: r.id, revision: 1, submitted: r.openedAt, updated: r.openedAt, voided, round: r, result: null, note: null })

describe('观点记录的状态', () => {
  it('结果：作废优先；没评估时只记录的算「只记录」，其余「等答案」；认不得的当待核实', () => {
    expect(M.outcome(view({ voided: true, outcome: 'realized' }))).toBe('voided')
    expect(M.outcome(view({ dir: 'observe' }))).toBe('observation')
    expect(M.outcome(view())).toBe('waiting')
    expect(M.outcome(view({ outcome: 'something_new' }))).toBe('needs_verification')
  })
  it('needsAction / isDecided 照 iOS', () => {
    expect(M.needsAction(view({ outcome: 'realized' }))).toBe(true) // 判出来了还没写复盘
    expect(M.needsAction(view({ outcome: 'realized', published: true }))).toBe(false)
    expect(M.needsAction(view({ groupPending: true }))).toBe(true)
    expect(M.needsAction(view({ syncError: 'x' }))).toBe(true)
    expect(M.needsAction(view({ outcome: 'needs_verification', published: true }))).toBe(true)
    expect(M.needsAction(view({ outcome: 'realized', published: true }), { assessmentRevision: 3, reflectionAssessmentRevision: 2 })).toBe(true)
    expect(M.needsAction(view({ voided: true, outcome: 'realized' }))).toBe(false)
    expect(M.needsAction(view())).toBe(false)
    expect(M.isDecided(view({ outcome: 'unrealized', published: true }))).toBe(true)
    expect(M.isDecided(view({ outcome: 'waiting', published: true }))).toBe(false)
    expect(M.isDecided(view({ outcome: 'realized', published: true, groupPending: true }))).toBe(false)
  })
  it('结果有更新：两个版本都在且不同', () => {
    expect(M.assessmentMoved({ assessmentRevision: 2, reflectionAssessmentRevision: null })).toBe(false)
    expect(M.assessmentMoved({ assessmentRevision: 2, reflectionAssessmentRevision: 2 })).toBe(false)
    expect(M.assessmentMoved({ assessmentRevision: 3, reflectionAssessmentRevision: 2 })).toBe(true)
  })
  it('分组、战绩三个数、待判定条数', () => {
    const rows = [
      view({ id: 'a', outcome: 'realized' }),
      view({ id: 'b' }),
      view({ id: 'c', outcome: 'unrealized', published: true }),
      view({ id: 'd', voided: true, outcome: 'realized' }),
      view({ id: 'e', dir: 'observe' }),
    ]
    const s = M.sections(rows)
    expect(s.pending.map(r => r.draft.id)).toEqual(['a'])
    expect(s.waiting.map(r => r.draft.id)).toEqual(['b'])
    expect(s.decided.map(r => r.draft.id)).toEqual(['c'])
    expect(M.tally(rows)).toEqual({ live: 4, realized: 1, unrealized: 1 })
    expect(M.pendingCount(rows)).toBe(1)
    expect(M.appendUnique(rows.slice(0, 2), rows.slice(1, 3)).map(r => r.draft.id)).toEqual(['a', 'b', 'c'])
  })
  it('记录行：短名、周期短名、补记 / 核验中', () => {
    const r = M.rowText(view({ outcome: 'realized', text: '' }))
    expect(r.symbol).toBe('BTC')
    expect(r.interval).toBe('1时')
    expect(r.outcome).toBe('判对')
    expect(r.tone).toBe('up')
    expect(r.text).toBe('未写原话')
    expect(r.empty).toBe(true)
    expect(r.time).toBe('9/30 12:00')
    expect(r.foot).toBeNull()
    expect(M.recordFootnote(view({ eligible: false }))).toBe('核验中')
    expect(M.recordFootnote(view({ eligible: false, submitted: T0 + 120_000 }))).toBe('补记')
    expect(M.recordFootnote(view({ eligible: false, originalClaimed: T0 - 5 }))).toBe('补记')
    expect(M.recordFootnote(view({ eligible: false, dir: 'observe' }))).toBeNull()
    expect(M.intervalShort('15m')).toBe('15分')
    expect(M.intervalShort('1M')).toBe('1月')
    expect(M.outcomeTone('unrealized')).toBe('danger')
  })
  it('失败分类与说法（照 iOS ReviewSyncEngine）', () => {
    expect(M.failureVerdict({ code: 'record_revision_changed', status: 409 })).toBe('conflict')
    expect(M.failureVerdict({ code: 'invalid_reflection', status: 400 })).toBe('rejected')
    expect(M.failureVerdict({ code: 'not_found', status: 404 })).toBe('rejected')
    expect(M.failureVerdict({ code: 'network', status: 0 })).toBe('transient')
    expect(M.failureVerdict({ code: 'x', status: 503 })).toBe('transient')
    expect(M.failureMessage({ code: 'record_revision_changed', status: 409 })).toBe('这条记录在别的设备上改过了')
    expect(M.failureMessage({ code: 'record_voided', status: 409 })).toBe('这条记录已经作废，改不动了')
    expect(M.failureMessage({ code: 'whatever', status: 401 })).toBe('连接凭证已失效，请重新连接')
    expect(M.failureMessage({ code: 'whatever', status: 404 })).toBe('服务端还未提供此功能')
    expect(M.failureMessage({ code: 'whatever', status: 502 })).toBe('服务端暂时不可用，稍后自动重试')
    expect(M.failureMessage({ code: 'whatever', status: 418 })).toBe('同步暂未成功，请稍后重试')
    expect(M.publishBlocked('  ')).toBe(true)
  })
  it('冲突与本机记录都算「要人处理」', () => {
    expect(M.needsAction({ ...view({ outcome: 'waiting' }), conflict: { reason: 'x', retryable: true } })).toBe(true)
    const local = M.localNoteRecord({ id: 'n1', range: view().draft.range, rule: view().draft.rule, text: '本机', origin: 'chart_first', created: T0 })
    expect(local.serverId).toBeNull()
    expect(M.rowText(local).text).toBe('本机')
  })
})

describe('修订记录', () => {
  const price = (v: number): string => v.toFixed(1)
  it('标题与行', () => {
    const created: RecordRevision = { kind: 'created', at: T0, body: { draft: view({ text: '回踩' }).draft } }
    expect(M.revisionTitle(created)).toBe('规则')
    expect(M.revisionLines(created, price)).toEqual(['看多', '目标 110.0', '失效 95.0', '判定 收盘确认', '到期 2026-10-01 12:00', '原话 回踩'])
    const refl: RecordRevision = { kind: 'reflection', at: T0, body: { body: { publish: true, reflection: { note: '对', nextTime: '' } } } }
    expect(M.revisionTitle(refl)).toBe('复盘 · 完成')
    expect(M.revisionLines(refl, price)).toEqual(['现在怎么看：对', '下次怎么做：未写'])
    expect(M.revisionTitle({ kind: 'reflection', at: T0, body: { body: { publish: false } } })).toBe('复盘 · 草稿')
    expect(M.revisionLines({ kind: 'assessment', at: T0, body: { outcome: 'weird', reason: 'r' } }, price)).toEqual(['待核实', 'r'])
    expect(M.revisionLines({ kind: 'group', at: T0, body: { body: { sameEpisode: true } } }, price)).toEqual(['与上一笔是同一次判断'])
    expect(M.visibleRevisions([created, { kind: 'source_verified', at: 0, body: {} }])).toHaveLength(1)
  })
})

describe('交易：写法（TradeLabels）', () => {
  it('金额、百分比、比值、持仓时长', () => {
    expect(M.money(1234.5)).toBe('+1.23K')
    expect(M.money(-86.04)).toBe('-86.04')
    expect(M.money(0)).toBe('0.00')
    expect(M.money(-5, false)).toBe('-5.00')
    expect(M.money(250, false)).toBe('250')
    expect(M.percent(0.5)).toBe('50.0%')
    expect(M.percent('-0.0123', true)).toBe('-1.2%')
    expect(M.percent('0.0123', true)).toBe('+1.2%')
    expect(M.percent(null)).toBe('—')
    expect(M.ratio('2.345')).toBe('2.35')
    expect(M.ratio(null)).toBe('—')
    expect(M.holding(30_000)).toBe('不到 1 分')
    expect(M.holding(45 * 60_000)).toBe('45 分')
    expect(M.holding(3 * 3_600_000)).toBe('3 小时')
    expect(M.holding(3 * 3_600_000 + 12 * 60_000)).toBe('3 小时 12 分')
    expect(M.holding(2 * 864e5)).toBe('2 天')
    expect(M.holding(2 * 864e5 + 5 * 3_600_000)).toBe('2 天 5 小时')
    expect(M.holding(null)).toBe('—')
  })
})

describe('交易：战绩（RoundStats）', () => {
  it('summarize：胜率、盈亏比、期望、费用占毛利、最长连亏、最好最差', () => {
    const rs = [
      round({ id: '1', net: 100, closedAt: T0 - 5000, realizedPnl: '102', commission: '2' }),
      round({ id: '2', net: -40, closedAt: T0 - 4000, realizedPnl: '-39', commission: '1' }),
      round({ id: '3', net: -20, closedAt: T0 - 3000, realizedPnl: '-19', commission: '1' }),
      round({ id: '4', net: 0, closedAt: T0 - 2000, realizedPnl: '1', commission: '1' }),
      round({ id: '5', net: -10, closedAt: T0 - 1000, realizedPnl: '-9', commission: '1', funding: '0.5' }),
      round({ id: 'o', net: 999, status: 'open', closedAt: null }),
    ]
    const s = M.summarize(rs)
    expect(s.count).toBe(5)
    expect(s.wins).toBe(1)
    expect(s.losses).toBe(3)
    expect(s.winRate).toBeCloseTo(0.2)
    expect(s.netPnl).toBe(30)
    expect(s.longestLosingStreak).toBe(2)
    expect(s.averageLoss).toBeCloseTo(-70 / 3)
    expect(s.rewardRisk).toBeCloseTo(100 / (70 / 3))
    expect(s.expectancy).toBeCloseTo(6)
    expect(s.fees).toBeCloseTo(5.5)
    expect(s.feeShareOfGross).toBeCloseTo(5.5 / 36)
    expect(s.best?.id).toBe('1')
    expect(s.worst?.id).toBe('2')
    expect(M.summarize([]).winRate).toBeNull()
  })
  it('五种分组', () => {
    const mon9 = Date.UTC(2026, 8, 28, 1) // 周一 09:00 上海
    const rs = [
      round({ id: 'a', net: 10, symbol: 'ETHUSDT', openedAt: mon9, holdingMs: 10 * 60_000 }),
      round({ id: 'b', net: 50, symbol: 'BTCUSDT', direction: 'short', openedAt: mon9 + 10 * 3_600_000, holdingMs: 2 * 864e5 }),
      round({ id: 'c', net: -5, symbol: 'ETHUSDT', openedAt: mon9 - 7 * 3_600_000, holdingMs: 8 * 864e5 }),
    ]
    expect(M.bySymbol(rs).map(g => [g.title, g.summary.netPnl])).toEqual([['BTC', 50], ['ETH', 5]])
    expect(M.byDirection(rs).map(g => g.title)).toEqual(['做多', '做空'])
    expect(M.byHolding(rs).map(g => g.title)).toEqual(['1 小时内', '1–7 天', '7 天以上'])
    expect(M.bySession(rs).map(g => g.title)).toEqual(['凌晨 0–6 点', '上午 6–12 点', '晚上 18–24 点'])
    expect(M.byWeekday(rs).map(g => g.title)).toEqual(['周一'])
  })
  it('上周：上海时间周一 0 点起算，按平仓时间', () => {
    const b = M.lastWeekBounds(T0)
    expect(b.start).toBe(Date.UTC(2026, 8, 20, 16)) // 9/21 周一 00:00 上海
    expect(b.end).toBe(Date.UTC(2026, 8, 27, 16))
    expect(M.weekSpan(b)).toBe('9/21–9/27')
    const w = M.lastWeek([round({ id: 'x', net: 5, closedAt: b.start }), round({ id: 'y', net: 5, closedAt: b.end })], T0)
    expect(w.summary.count).toBe(1)
  })
  it('交易分组：持仓中一组，其余按平仓那天，作废的不要', () => {
    const list = [
      trade(round({ id: 'open', net: 0, status: 'open', closedAt: null })),
      trade(round({ id: 't', net: 1, closedAt: T0 - 60_000 })),
      trade(round({ id: 'y', net: 1, closedAt: T0 - 864e5 })),
      trade(round({ id: 'old', net: 1, closedAt: Date.UTC(2026, 8, 26, 4) })),
      trade(round({ id: 'v', net: 1, closedAt: T0 }), true),
    ]
    const s = M.tradeSections(list, T0)
    expect(s.open.map(t => t.id)).toEqual(['open'])
    expect(s.days.map(d => d.title)).toEqual(['今天', '昨天', '9 月 26 日 周六'])
  })
})

describe('「我的」根上那两行', () => {
  it('第一行', () => {
    expect(M.rootLine1(false, { live: 0, realized: 0, unrealized: 0 }, 0)).toBe('登录后可用')
    expect(M.rootLine1(true, { live: 5, realized: 2, unrealized: 1 }, 0)).toBe('观点 5 条')
    expect(M.rootLine1(true, { live: 5, realized: 2, unrealized: 1 }, 2)).toBe('观点 5 条 · 待判定 2')
  })
  it('第二行', () => {
    expect(M.rootLine2(false, [], T0)).toBe('')
    expect(M.rootLine2(true, [], T0)).toBe('接入交易所后自动生成')
    expect(M.rootLine2(true, [trade(round({ id: 'a', net: 5 }))], T0)).toBe('交易 上周 0 笔')
    const lw = Date.UTC(2026, 8, 23, 4)
    expect(M.rootLine2(true, [trade(round({ id: 'a', net: 1500, closedAt: lw })), trade(round({ id: 'b', net: -500, closedAt: lw }))], T0))
      .toBe('交易 上周 2 笔 · 净盈亏 +1.00K · 胜率 50.0%')
  })
})

describe('待传队列', () => {
  const mem = (): M.KV & { data: Record<string, string> } => {
    const data: Record<string, string> = {}
    return { data, getItem: k => data[k] ?? null, setItem: (k, v) => { data[k] = v } }
  }
  const op = (o: Partial<M.PendingOp> & { id: string }): M.PendingOp => ({
    recordId: 'r1', kind: 'reflection', at: T0, body: { expectedRevision: 1, reflection: { note: 'a', nextTime: '', publishedAt: null, revision: 0 }, publish: false }, ...o,
  })
  it('按账号存取', () => {
    const kv = mem()
    M.writePending(kv, 'u1', [op({ id: 'a' })])
    M.writePending(kv, 'u2', [op({ id: 'b' })])
    expect(M.readPending(kv, 'u1').map(o => o.id)).toEqual(['a'])
    M.writePending(kv, 'u1', [])
    expect(M.readPending(kv, 'u1')).toEqual([])
    expect(M.readPending(kv, 'u2').map(o => o.id)).toEqual(['b'])
    kv.setItem(M.PENDING_KEY, 'garbage')
    expect(M.readPending(kv, 'u2')).toEqual([])
  })
  it('复盘只留最后一份；发出去过的不动；作废不重复', () => {
    let q = M.enqueueOp([], op({ id: 'a' }))
    q = M.enqueueOp(q, op({ id: 'b' }))
    expect(q.map(o => o.id)).toEqual(['b'])
    q = [{ ...q[0], attempted: true }]
    q = M.enqueueOp(q, op({ id: 'c' }))
    expect(q.map(o => o.id)).toEqual(['b', 'c'])
    q = [{ ...q[0], conflict: { reason: 'x', retryable: true } }, q[1]]
    q = M.enqueueOp(q, op({ id: 'd' }))
    expect(q.map(o => o.id)).toEqual(['d'])
    q = M.enqueueOp(q, op({ id: 'v1', kind: 'void', body: { expectedRevision: 1 } }))
    q = M.enqueueOp(q, op({ id: 'v2', kind: 'void', body: { expectedRevision: 1 } }))
    expect(q.map(o => o.id)).toEqual(['d', 'v2'])
    q = M.enqueueOp(q, op({ id: 'x', recordId: 'r2' }))
    expect(q.map(o => o.id)).toEqual(['d', 'v2', 'x'])
  })
  it('叠到服务端那份上：完成复盘把上一份已完成的挪进历史；作废、归并、冲突、错误', () => {
    const base: ViewRecordFull = { ...view({ published: true }), reflectionHistory: [] }
    const r = M.applyPending(base, [
      op({ id: 'a', at: T0 + 5, body: { expectedRevision: 1, reflection: { note: '新的', nextTime: '下次', publishedAt: null, revision: 0 }, publish: true } }),
      op({ id: 'g', kind: 'group', body: { expectedRevision: 1, sameEpisode: true } }),
    ])
    expect(r.reflection).toEqual({ note: '新的', nextTime: '下次', publishedAt: T0 + 5, revision: 0 })
    expect(r.reflectionHistory?.[0].note).toBe('对了')
    expect(r.groupPending).toBe(false)
    expect(base.reflection?.note).toBe('对了')
    expect(M.applyPending(view(), [op({ id: 'v', kind: 'void', body: { expectedRevision: 1 } })]).voided).toBe(true)
    expect(M.applyPending(view(), [op({ id: 'c', conflict: { reason: '改过了', retryable: true } })]).conflict?.reason).toBe('改过了')
    expect(M.applyPending(view(), [op({ id: 'e', error: '服务端暂时不可用' })]).syncError).toBe('服务端暂时不可用')
    expect(M.applyPending(view(), [op({ id: 'z', recordId: 'other' })])).toEqual(view())
    const h = { ...view({ published: true }), reflectionHistory: [1, 2, 3, 4, 5].map(i => ({ note: String(i), nextTime: '', publishedAt: i, revision: i })) }
    expect(M.applyPending(h, [op({ id: 'p', body: { expectedRevision: 1, reflection: { note: 'n', nextTime: '', publishedAt: null, revision: 0 }, publish: false } })]).reflectionHistory).toHaveLength(5)
  })
})

describe('找相似', () => {
  it('轮询节奏：2 秒起翻倍、30 秒封顶、进度一动回到 2 秒、10 分钟用完', () => {
    const p = new M.PollSchedule()
    expect(p.next(0, 0)).toBe(2000)
    expect(p.next(0, 2000)).toBe(4000)
    expect(p.next(0, 6000)).toBe(8000)
    expect(p.next(5, 14000)).toBe(2000)
    const q = new M.PollSchedule()
    let w = 0
    for (let i = 0; i < 10; i++) w = q.next(0, 1000) ?? -1
    expect(w).toBe(30000)
    expect(q.next(0, 590000)).toBe(10000)
    expect(q.next(0, 600000)).toBeNull()
  })
  it('轮询出错要不要接着等', () => {
    expect(M.keepsPolling(0)).toBe(true)
    expect(M.keepsPolling(429)).toBe(true)
    expect(M.keepsPolling(503)).toBe(true)
    expect(M.keepsPolling(404)).toBe(false)
  })
  it('进度、行上的字、去重', () => {
    expect(M.searchProgressText(null)).toBe('正在查找')
    expect(M.searchProgressText({ checked: 3, total: 0 })).toBe('正在查找')
    expect(M.searchProgressText({ checked: 3, total: 40 })).toBe('正在比对 3/40')
    const m = { id: 'm1', range: { ...view().draft.range, symbol: 'ETHUSDT', interval: '4h', start: T0, bars: 32 }, score: 0.8712, source: 'history' }
    expect(M.matchRowText(m)).toEqual({ title: 'ETH · 4时', time: '2026-09-30 12:00', bars: '32 根', score: '相似 0.87' })
    expect(M.appendMatches([m], [m, { ...m, id: 'm2' }]).map(x => x.id)).toEqual(['m1', 'm2'])
    expect(M.MIN_SEARCH_BARS).toBe(16)
  })
})

describe('观点 ↔ 交易', () => {
  it('同品种、时间段相交；作废的不算；排序', () => {
    const v1 = view({ id: 'v1', created: T0 - 2 * 3_600_000 })
    const v2 = view({ id: 'v2', created: T0 - 3 * 3_600_000 })
    const vOld = view({ id: 'old', created: T0 - 10 * 864e5 })
    const vVoid = view({ id: 'void', voided: true })
    const r = round({ id: 't1', net: 1, symbol: 'btcusdt' })
    expect(M.viewsForRound(r, [v1, vOld, vVoid, v2], T0).map(v => v.draft.id)).toEqual(['v2', 'v1'])
    const t2 = trade(round({ id: 't2', net: 1, openedAt: T0 - 7_200_000 }))
    const t3 = trade(round({ id: 't3', net: 1, openedAt: T0 - 3_600_000, status: 'open', closedAt: null }))
    const tEth = trade(round({ id: 't4', net: 1, symbol: 'ETHUSDT' }))
    expect(M.roundsForView(v1, [t3, tEth, t2, trade(r, true)], T0).map(t => t.id)).toEqual(['t2', 't3'])
    expect(M.roundsForView(vVoid, [t2], T0)).toEqual([])
  })
})

describe('交易那张图', () => {
  it('按持仓时长挑周期（边界含）', () => {
    expect(M.holdingInterval(4 * 3_600_000)).toBe('5m')
    expect(M.holdingInterval(4 * 3_600_000 + 1)).toBe('1h')
    expect(M.holdingInterval(2 * 864e5)).toBe('1h')
    expect(M.holdingInterval(14 * 864e5)).toBe('4h')
    expect(M.holdingInterval(15 * 864e5)).toBe('1d')
  })
  it('自己框窗口：两头各垫 max(10 根, 持仓四分之一)，不超过现在', () => {
    const r = round({ id: 'w', net: 0, openedAt: T0 - 3_600_000, closedAt: T0 })
    const w = M.chartWindow(r, T0 + 864e5)
    expect(w.interval).toBe('5m')
    expect(w.start).toBe(T0 - 3_600_000 - 50 * 60_000)
    expect(w.end).toBe(T0 + 50 * 60_000)
    const live = M.chartWindow({ ...r, closedAt: null }, T0 + 60_000)
    expect(live.end).toBe(T0)
    expect(M.chartSpecFor(r, { chart: { interval: '15m', start: 1, end: 2 } }, T0)).toEqual({ interval: '15m', start: 1, end: 2 })
    expect(M.chartSpecFor(r, { chart: { interval: '7m', start: 1, end: 2 } }, T0 + 864e5)).toEqual(w)
    expect(M.chartSpecFor(r, { chart: { interval: '1h', start: 2, end: 2 } }, T0 + 864e5)).toEqual(w)
  })
  it('记号：成交箭头 + 均价虚线', () => {
    const r = round({ id: 'm', net: 0 })
    r.fills = [
      { id: 'f1', orderId: 'o', time: T0 - 3_600_000, side: 'BUY', positionSide: 'BOTH', price: '100', qty: '1', quoteQty: '100', commission: '0', commissionAsset: 'USDT', realizedPnl: '0', maker: false, role: 'open', split: false },
      { id: 'f2', orderId: 'o', time: T0, side: 'SELL', positionSide: 'BOTH', price: '101', qty: '1', quoteQty: '101', commission: '0', commissionAsset: 'USDT', realizedPnl: '1', maker: false, role: 'close', split: false },
    ]
    expect(M.tradeMarkers(r).map(m => [m.kind, m.id, m.p, m.dashed])).toEqual([
      ['markerUp', 'fill-f1', 100, false], ['markerDown', 'fill-f2', 101, false], ['hline', 'avg-open', 100, true], ['hline', 'avg-close', 101, true],
    ])
    expect(M.tradeMarkers({ ...r, fills: [], closeAvgPrice: null }).map(m => m.id)).toEqual(['avg-open'])
  })
  it('小数位从收盘价里看', () => {
    expect(M.decimalsOfCloses([1.5, 2.125, 3])).toBe(3)
    expect(M.decimalsOfCloses([100, 200])).toBe(0)
    expect(M.decimalsOfCloses([])).toBeNull()
  })
})

describe('补图', () => {
  it('压图的几轮', () => {
    const s = M.jpegSteps()
    expect(s).toHaveLength(6)
    expect(s[0]).toEqual({ side: 2048, quality: 0.82 })
    expect(s[1]).toEqual({ side: 1536, quality: 0.72 })
    expect(s[5].quality).toBe(0.5)
    expect(M.fitScale(4096, 1000, 2048)).toBe(0.5)
    expect(M.fitScale(100, 50, 2048)).toBe(1)
    expect(M.base64Bytes('QUJD')).toBe(3)
    expect(M.base64Bytes('QUI=')).toBe(2)
    expect(M.ATTACH_MAX_BYTES).toBe(5 * 1024 * 1024)
  })
})
