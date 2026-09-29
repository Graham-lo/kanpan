/* Hkline Web · 复盘：数据整形（纯函数，不碰 DOM，单元测试直接测）
 *
 * 交易回合的统计照手机端 RoundStats：只算已平仓的回合；净盈亏 > 0 算赚；
 * 费用 = 手续费 − 资金费（资金费收到为正）；盈亏比 = 平均赚 ÷ |平均亏|；每笔期望 = 净盈亏合计 ÷ 回合数。
 * 分组（方向 / 品种 / 持仓时长 / 开仓时段 / 星期）与「上周」一律按上海时间切。
 * 观点记录的战绩不在这里算——服务端按相对口径分好组、算好对错，前端只展示。
 */
import { TZ_MS, pad, sh } from '../util/format'
import type { Round, StatGroup, Statistics, TradeRecord, ViewRecord } from './types'

const DAY = 864e5
const WEEK_CN = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']

/** 十进制字符串 → 数字；空串、null、非数字一律当 0 */
export function num(s: string | number | null | undefined): number {
  if (s == null || s === '') return 0
  const v = typeof s === 'number' ? s : Number(s)
  return isFinite(v) ? v : 0
}

/** 十进制字符串的小数位（「2656.81」→ 2），给价格按交易所原文的精度显示 */
export function decimalsOf(s: string | null | undefined): number {
  if (!s) return 0
  const i = s.indexOf('.')
  return i < 0 ? 0 : s.length - i - 1
}

/** 一个回合里价格的显示精度：取成交价原文里最长的小数位，夹在 0–8 */
export function roundDecimals(r: Pick<Round, 'fills'>): number {
  let d = 0
  for (const f of r.fills) d = Math.max(d, decimalsOf(f.price))
  return Math.min(8, d)
}

// ------------------------------------------------------------ 文案
export const OUTCOME_LABEL: Record<string, string> = {
  waiting: '等答案', realized: '判对', unrealized: '判错', needs_verification: '待核实', observation: '只记录', voided: '已作废',
}
export const VIEW_DIR_LABEL: Record<string, string> = { long: '看多', short: '看空', observe: '只记录' }
export const TRADE_DIR_LABEL: Record<string, string> = { long: '做多', short: '做空' }
export const ORIGIN_LABEL: Record<string, string> = { chart_first: '图在先', thought_first: '想法在先', interwoven: '两者交织', unknown: '不确定' }
export const CONFIRM_LABEL: Record<string, string> = { bar_close: '收盘确认', trade_touch: '触价确认' }
export const ROLE_LABEL: Record<string, string> = { open: '开仓', add: '加仓', reduce: '减仓', close: '平仓' }
export const VERDICT_LABEL: Record<string, string> = { insufficient: '样本不足' }

/** 一条观点记录现在的状态：作废优先；服务端还没评估时，只记录的算「只记录」，其余「等答案」 */
export function outcomeOf(r: ViewRecord): string {
  if (r.voided) return 'voided'
  return r.assessment?.outcome ?? (r.draft.rule.direction === 'observe' ? 'observation' : 'waiting')
}

/** 判断的时刻：上传到服务端的时间，没有就用写下的时间 */
export function judgedAt(r: ViewRecord): number { return r.submitted ?? r.draft.created }

/** 金额：「+1,234.56」「−86.04」（负号用全角减号，和原型一致） */
export function money(v: number, dec = 2): string {
  if (!isFinite(v)) return '—'
  const a = Math.abs(v).toLocaleString('en-US', { minimumFractionDigits: dec, maximumFractionDigits: dec })
  return (v > 0 ? '+' : v < 0 ? '−' : '') + a
}

/** 服务端给的比例字符串（「0.007647」）→ 百分数文字「+0.76%」 */
export function ratioPct(s: string | null | undefined, signed = true): string {
  if (s == null || s === '') return '—'
  const p = num(s) * 100
  return `${signed && p > 0 ? '+' : ''}${p.toFixed(2)}%`
}

// ------------------------------------------------------------ 上海时间
/** 上海日期键「2026-09-29」 */
export function dayKey(t: number): string {
  const d = sh(t)
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`
}

/** 上海时间某天 0 点对应的 UTC 毫秒 */
export function dayStart(t: number): number { return Math.floor((t + TZ_MS) / DAY) * DAY - TZ_MS }

/** 分组标题：「今天」「昨天」「9月27日 周六」（跨年带年份） */
export function dayLabel(t: number, now: number): string {
  const d0 = dayStart(t), n0 = dayStart(now)
  if (d0 === n0) return '今天'
  if (d0 === n0 - DAY) return '昨天'
  const d = sh(t), n = sh(now)
  const y = d.getUTCFullYear() !== n.getUTCFullYear() ? `${d.getUTCFullYear()}年` : ''
  return `${y}${d.getUTCMonth() + 1}月${d.getUTCDate()}日 ${WEEK_CN[d.getUTCDay()]}`
}

export interface DayGroup<T> { key: string; label: string; items: T[] }

/** 按上海日期分组，保持传入顺序（传入是新到旧，组也是新到旧） */
export function groupByDay<T>(items: T[], timeOf: (x: T) => number, now: number): DayGroup<T>[] {
  const out: DayGroup<T>[] = []
  const at = new Map<string, DayGroup<T>>()
  for (const x of items) {
    const t = timeOf(x), k = dayKey(t)
    let g = at.get(k)
    if (!g) { g = { key: k, label: dayLabel(t, now), items: [] }; at.set(k, g); out.push(g) }
    g.items.push(x)
  }
  return out
}

/** 上周：[上周一 0 点, 本周一 0 点)，上海时间 */
export function lastWeekWindow(now: number): { from: number; to: number } {
  const today = dayStart(now)
  const wd = sh(now).getUTCDay() // 0 = 周日
  const monday = today - ((wd + 6) % 7) * DAY
  return { from: monday - 7 * DAY, to: monday }
}

// ------------------------------------------------------------ 交易回合统计
export interface RoundStats {
  count: number
  wins: number
  losses: number
  /** 净盈亏合计 */
  net: number
  /** 已实现盈亏合计（未扣费用） */
  realized: number
  commission: number
  funding: number
  /** 费用 = 手续费 − 资金费 */
  fees: number
  winRate: number | null
  avgWin: number | null
  avgLoss: number | null
  /** 平均赚 ÷ |平均亏|；没有亏的回合或没有赚的回合时为 null */
  rewardRisk: number | null
  /** 每笔期望：净盈亏 ÷ 回合数 */
  expectancy: number | null
  /** 最长连亏（按平仓时间先后） */
  maxLosingStreak: number
  avgHoldingMs: number | null
  /** 总盈利：赚钱回合的净盈亏合计（≥ 0） */
  grossProfit: number
  /** 总亏损：亏钱回合的净盈亏合计（≤ 0） */
  grossLoss: number
  /** 盈利因子 = 总盈利 ÷ |总亏损|；没有亏损（或没有回合）时为 null，界面写「—」，不写无穷大 */
  profitFactor: number | null
  maxDrawdown: Drawdown
  /** 最大一笔盈利；没有赚钱的回合时为 null */
  largestWin: LargestWin | null
  /** 这段时间的盈利主要来自这一笔：占净盈亏 ≥ DOMINANT_SHARE、净盈亏为正、至少两个已平回合 */
  dominant: boolean
}

/**
 * 最大回撤：按平仓先后把净盈亏累加成已实现资金曲线（从 0 起），取峰到谷最大的一段。
 * `pct` 的分母是那一段的峰值（当时的累计净盈亏）；峰值 ≤ 0（从一开始就在亏）时没有可比的本钱，为 null。
 * 可能超过 100%：把之前赚的全吐回去还倒亏。
 */
export interface Drawdown { amount: number; pct: number | null; peak: number; peakAt: number | null; troughAt: number | null }
export interface LargestWin { net: number; id: string; symbol: string; /** 占净盈亏的比例；净盈亏 ≤ 0 时为 null */ share: number | null }

/** 最大单笔占净盈亏到这个比例就提示「盈利主要来自 1 笔」 */
export const DOMINANT_SHARE = 0.5

export function closedRounds(list: Round[]): Round[] { return list.filter(r => r.status === 'closed' && r.closedAt != null) }

export function roundStats(list: Round[]): RoundStats {
  const rs = closedRounds(list).slice().sort((a, b) => (a.closedAt ?? 0) - (b.closedAt ?? 0))
  let net = 0, realized = 0, commission = 0, funding = 0, sumW = 0, sumL = 0, wins = 0, losses = 0, streak = 0, maxStreak = 0, hold = 0, holdN = 0
  // 资金曲线：peak 从 0 起（还没交易时的本钱线）
  let peak = 0, peakAt: number | null = null
  const dd: Drawdown = { amount: 0, pct: null, peak: 0, peakAt: null, troughAt: null }
  let best: Round | null = null, bestN = 0
  for (const r of rs) {
    const n = num(r.netPnl)
    net += n; realized += num(r.realizedPnl); commission += num(r.commission); funding += num(r.funding)
    if (n > 0) { wins++; sumW += n; streak = 0 } else { losses++; sumL += n; streak++; maxStreak = Math.max(maxStreak, streak) }
    if (n > 0 && n > bestN) { best = r; bestN = n }
    if (net > peak) { peak = net; peakAt = r.closedAt! }
    else if (peak - net > dd.amount) Object.assign(dd, { amount: peak - net, peak, peakAt, troughAt: r.closedAt!, pct: peak > 0 ? (peak - net) / peak : null })
    const h = r.holdingMs ?? ((r.closedAt ?? r.openedAt) - r.openedAt)
    if (h >= 0) { hold += h; holdN++ }
  }
  const count = rs.length
  const avgWin = wins ? sumW / wins : null
  const avgLoss = losses ? sumL / losses : null
  const share = best && net > 0 ? bestN / net : null
  return {
    count, wins, losses, net, realized, commission, funding, fees: commission - funding,
    winRate: count ? wins / count : null,
    avgWin, avgLoss,
    rewardRisk: avgWin != null && avgLoss != null && avgLoss !== 0 ? avgWin / Math.abs(avgLoss) : null,
    expectancy: count ? net / count : null,
    maxLosingStreak: maxStreak,
    avgHoldingMs: holdN ? hold / holdN : null,
    grossProfit: sumW, grossLoss: sumL,
    profitFactor: count && sumL < 0 ? sumW / -sumL : null,
    maxDrawdown: dd,
    largestWin: best ? { net: bestN, id: best.id, symbol: best.symbol, share } : null,
    dominant: share != null && share >= DOMINANT_SHARE && count >= 2,
  }
}

/** 多空拆分：做多、做空各自的统计（没有回合的那一边 count 为 0） */
export function sideStats(list: Round[]): Record<'long' | 'short', RoundStats> {
  const rs = closedRounds(list)
  return { long: roundStats(rs.filter(r => r.direction === 'long')), short: roundStats(rs.filter(r => r.direction === 'short')) }
}

export type GroupingId = 'direction' | 'symbol' | 'holding' | 'session' | 'weekday'
export const GROUPINGS: { id: GroupingId; title: string }[] = [
  { id: 'direction', title: '按方向' },
  { id: 'symbol', title: '按品种' },
  { id: 'holding', title: '按持仓时长' },
  { id: 'session', title: '按开仓时段' },
  { id: 'weekday', title: '按开仓星期' },
]

const HOLD_BUCKETS: [number, string][] = [[3600e3, '1 小时内'], [DAY, '1 天内'], [7 * DAY, '7 天内'], [Infinity, '7 天以上']]
export function holdingBucket(ms: number): string { return HOLD_BUCKETS.find(([lim]) => ms < lim)![1] }

const SESSIONS = ['凌晨 0–6 点', '上午 6–12 点', '下午 12–18 点', '晚上 18–24 点']
export function sessionOf(t: number): string { return SESSIONS[Math.floor(sh(t).getUTCHours() / 6)] }

const WEEK_ORDER = ['周一', '周二', '周三', '周四', '周五', '周六', '周日']
export function weekdayOf(t: number): string { return WEEK_CN[sh(t).getUTCDay()] }

export interface GroupRow { key: string; label: string; stats: RoundStats }

/** 按某一维把已平仓回合分组；方向、时长、时段、星期按固定顺序，品种按回合数从多到少 */
export function groupRounds(list: Round[], by: GroupingId): GroupRow[] {
  const rs = closedRounds(list)
  const keyOf = (r: Round): string => {
    switch (by) {
      case 'direction': return r.direction
      case 'symbol': return r.symbol
      case 'holding': return holdingBucket(r.holdingMs ?? ((r.closedAt ?? r.openedAt) - r.openedAt))
      case 'session': return sessionOf(r.openedAt)
      case 'weekday': return weekdayOf(r.openedAt)
    }
  }
  const m = new Map<string, Round[]>()
  for (const r of rs) { const k = keyOf(r); m.set(k, [...(m.get(k) || []), r]) }
  const order: string[] =
    by === 'direction' ? ['long', 'short'] :
    by === 'holding' ? HOLD_BUCKETS.map(b => b[1]) :
    by === 'session' ? SESSIONS :
    by === 'weekday' ? WEEK_ORDER :
    [...m.keys()].sort((a, b) => (m.get(b)!.length - m.get(a)!.length) || a.localeCompare(b))
  return order.filter(k => m.has(k)).map(k => ({ key: k, label: by === 'direction' ? TRADE_DIR_LABEL[k] ?? k : k, stats: roundStats(m.get(k)!) }))
}

/** 上周的回合（按平仓时间落在上周） */
export function lastWeekRounds(list: Round[], now: number): Round[] {
  const { from, to } = lastWeekWindow(now)
  return closedRounds(list).filter(r => r.closedAt! >= from && r.closedAt! < to)
}

/** 累计净盈亏曲线：按平仓时间从早到晚，第一个点是 0 */
export function equityCurve(list: Round[]): { t: number; v: number; id: string | null }[] {
  const rs = closedRounds(list).slice().sort((a, b) => a.closedAt! - b.closedAt!)
  let c = 0
  const out: { t: number; v: number; id: string | null }[] = [{ t: rs[0]?.openedAt ?? 0, v: 0, id: null }]
  for (const r of rs) { c += num(r.netPnl); out.push({ t: r.closedAt!, v: c, id: r.id }) }
  return out
}

/** 交易列表：作废的不要；持仓中的在最前，其余按平仓时间新到旧（和服务端顺序一致，这里再保一次） */
export function sortTrades(list: TradeRecord[]): TradeRecord[] {
  return list.filter(t => !t.voided).slice().sort((a, b) => {
    const ao = a.round.status === 'open', bo = b.round.status === 'open'
    if (ao !== bo) return ao ? -1 : 1
    return (b.round.closedAt ?? b.round.openedAt) - (a.round.closedAt ?? a.round.openedAt)
  })
}

/** 列表里出现过的品种，按回合数从多到少 */
export function symbolsOf(list: TradeRecord[]): string[] {
  const m = new Map<string, number>()
  for (const t of list) m.set(t.round.symbol, (m.get(t.round.symbol) || 0) + 1)
  return [...m.keys()].sort((a, b) => (m.get(b)! - m.get(a)!) || a.localeCompare(b))
}

// ------------------------------------------------------------ 观点记录
export interface ViewSummary { total: number; realized: number; unrealized: number; waiting: number; observation: number; other: number }

export function viewSummary(list: ViewRecord[]): ViewSummary {
  const s: ViewSummary = { total: 0, realized: 0, unrealized: 0, waiting: 0, observation: 0, other: 0 }
  for (const r of list) {
    const o = outcomeOf(r)
    if (o === 'voided') continue
    s.total++
    if (o === 'realized' || o === 'unrealized' || o === 'waiting' || o === 'observation') s[o]++
    else s.other++
  }
  return s
}

/** 观点列表：新到旧 */
export function sortViews(list: ViewRecord[]): ViewRecord[] {
  return list.slice().sort((a, b) => judgedAt(b) - judgedAt(a))
}

/** 服务端分组标题「ETHUSDT · 做空 · 收盘 · 目标≤ 0.5%」拆成一段段，界面上逐段排开 */
export function titleParts(title: string): string[] { return title.split(' · ').map(s => s.trim()).filter(Boolean) }

/** 目标 / 失效相对参考价的幅度（百分数，带符号） */
export function distPct(from: number, to: number): number | null { return from ? (to - from) / from * 100 : null }

/** 相似度文字：「相似 0.60」——服务端给的是 0–1 的分数，不是百分比，照原样两位小数 */
export function scoreText(s: number): string { return `相似 ${s.toFixed(2)}` }

// ------------------------------------------------------------ 观点战绩（照手机端 ReviewStatsResponse.resolvedGroups）
/**
 * 界面上只摆一份分组：服务端给了相对口径（comparableGroups）就用它，没给才退回 groups；
 * 再把对应那份证据里的判定状态「有才盖」地贴回每一组——一笔一组的 0% / 100% 不是战绩。
 */
export function resolvedGroups(s: Statistics | null | undefined): StatGroup[] {
  if (!s) return []
  const useComparable = Array.isArray(s.comparableGroups)
  const groups = (useComparable ? s.comparableGroups : s.groups) || []
  const table = (useComparable ? s.comparableProof : s.proof)?.compatible_groups || {}
  return groups.map(g => {
    const v: StatGroup = { ...g }
    const hit = table[g.id]
    if (!hit) return v
    if (hit.verdict_status) v.verdictStatus = hit.verdict_status
    if (hit.recheck != null) v.recheck = hit.recheck
    if (hit.denominator != null) v.total = hit.denominator
    if (hit.numerator != null) v.correct = hit.numerator
    if (!v.title && hit.title) v.title = hit.title
    return v
  })
}

/** 样本够了才给百分比，不够就写「样本不足」 */
export function groupRateText(g: StatGroup): string {
  if (g.verdictStatus === 'insufficient') return VERDICT_LABEL.insufficient
  if (!g.total) return '—'
  return `${Math.round(g.correct / g.total * 100)}%`
}
