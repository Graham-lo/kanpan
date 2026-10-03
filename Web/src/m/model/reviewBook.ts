/* 手机网页版 · 复盘本的纯逻辑（照 iOS ReviewModels / ReviewBookSections / RoundStats / TradeLabels）
 *
 * 不碰 DOM、不发请求，单元测试直接测：
 *   - 观点记录：现在的结果、要不要人处理（needsAction）、算不算已判定（isDecided）、
 *     列表分组（待处理 / 等答案 / 已判定）、战绩卡三个数、行上的字、修订记录的标题与行。
 *   - 交易回合：iOS RoundStats.summarize 原样（只算已平仓；净盈亏 > 0 赚、< 0 亏、= 0 不打断也不续连亏）、
 *     五种分组、上周周报；金额 / 百分比 / 持仓时长的写法照 TradeLabels。
 *   - 「我的」根上复盘本那两行字。
 * 时间一律上海时间（UTC+8 固定）；数额 K / M / B / T。
 */
import type { ChartRange, Match, RecordRevision, ReviewReflection, Round, TradeRecord, ViewRecordFull } from '../../review/types'
import { fmtDayTime, fmtFull, fmtVol, toFixed } from '../chart/format'
import { baseOf } from '../../market/symbols'

const SH = 480
const DAY = 864e5

/** 一条观点记录在本机的样子：服务端那份 + 待传队列叠上去的改动 + 被隔离下来的那次上传（只活在本机） */
export type LocalRecord = ViewRecordFull & { conflict?: OpConflict | null }

// ------------------------------------------------------------ 观点记录
export type Outcome = 'waiting' | 'realized' | 'unrealized' | 'needs_verification' | 'observation' | 'voided'
const KNOWN: Outcome[] = ['waiting', 'realized', 'unrealized', 'needs_verification', 'observation', 'voided']

export const OUTCOME_TITLE: Record<Outcome, string> = {
  waiting: '等答案', realized: '判对', unrealized: '判错', needs_verification: '待核实', observation: '只记录', voided: '已作废',
}
export const DIRECTION_TITLE: Record<string, string> = { long: '看多', short: '看空', observe: '只记录' }
export const ORIGIN_TITLE: Record<string, string> = { chart_first: '图在先', thought_first: '想法在先', interwoven: '两者交织', unknown: '不确定' }
export const CONFIRM_TITLE: Record<string, string> = { bar_close: '收盘确认', trade_touch: '触价确认' }

/** 服务端给的结论字符串 → 已知的几种；认不得的当「待核实」（和 iOS 解码失败时一样要人看一眼） */
export function normalizeOutcome(s: string | null | undefined): Outcome {
  return s && (KNOWN as string[]).includes(s) ? s as Outcome : 'needs_verification'
}

/** 现在的结果：作废优先；还没评估时，只记录的算「只记录」，其余「等答案」 */
export function outcome(r: ViewRecordFull): Outcome {
  if (r.voided) return 'voided'
  if (r.assessment) return normalizeOutcome(r.assessment.outcome)
  return r.draft.rule.direction === 'observe' ? 'observation' : 'waiting'
}

/** 详情外层带的两个裁定版本（列表里没有） */
export interface Revisions { assessmentRevision?: number | null; reflectionAssessmentRevision?: number | null }

/** 人写完复盘之后，服务端又改过结论 */
export function assessmentMoved(x?: Revisions | null): boolean {
  if (!x || x.assessmentRevision == null || x.reflectionAssessmentRevision == null) return false
  return x.assessmentRevision !== x.reflectionAssessmentRevision
}

const published = (r: ViewRecordFull): boolean => r.reflection?.publishedAt != null

/** 要人处理：等归并、同步出错、没能同步（冲突）、结果有更新、待核实、判出了对错却还没写完复盘 */
export function needsAction(r: LocalRecord, x?: Revisions | null): boolean {
  if (r.voided) return false
  const o = outcome(r)
  return r.groupPending === true || !!r.syncError || !!r.conflict || assessmentMoved(x) || o === 'needs_verification'
    || ((o === 'realized' || o === 'unrealized') && !published(r))
}

/** 「已判定」那一档：复盘写完了，也没别的事等人处理（和服务端 ?decided=true 同一口径） */
export function isDecided(r: LocalRecord, x?: Revisions | null): boolean {
  const o = outcome(r)
  return !r.voided && published(r) && r.groupPending !== true && !needsAction(r, x) && o !== 'waiting' && o !== 'needs_verification'
}

export interface BookSections { all: ViewRecordFull[]; pending: ViewRecordFull[]; waiting: ViewRecordFull[]; decided: ViewRecordFull[] }

/** 一趟分组（照 ReviewBookSections）：待处理 = needsAction；等答案 = 还在等又不欠人处理的 */
export function sections(rows: ViewRecordFull[]): BookSections {
  const s: BookSections = { all: [], pending: [], waiting: [], decided: [] }
  for (const r of rows) {
    s.all.push(r)
    if (needsAction(r)) s.pending.push(r)
    else if (outcome(r) === 'waiting') s.waiting.push(r)
    if (isDecided(r)) s.decided.push(r)
  }
  return s
}

/** 按 id 去重追加（无限下滑接下一页时，同一条不出现两次） */
export function appendUnique(list: ViewRecordFull[], more: ViewRecordFull[]): ViewRecordFull[] {
  const seen = new Set(list.map(r => r.draft.id))
  return [...list, ...more.filter(r => !seen.has(r.draft.id) && (seen.add(r.draft.id), true))]
}

export interface Tally { live: number; realized: number; unrealized: number }

/** 战绩卡三个数：没作废的几条、其中判对 / 判错各几条 */
export function tally(rows: ViewRecordFull[]): Tally {
  const t: Tally = { live: 0, realized: 0, unrealized: 0 }
  for (const r of rows) {
    if (r.voided) continue
    t.live++
    const o = outcome(r)
    if (o === 'realized') t.realized++
    else if (o === 'unrealized') t.unrealized++
  }
  return t
}

/** 待判定的条数：角标、筛选胶囊、「我的」那一行同一个数 */
export function pendingCount(rows: ViewRecordFull[]): number {
  let n = 0
  for (const r of rows) if (needsAction(r)) n++
  return n
}

/** 结果文字的颜色：判对涨色、判错警示色、待核实次一级墨色，其余最浅 */
export function outcomeTone(o: Outcome): 'up' | 'danger' | 'ink2' | 'ink3' {
  return o === 'realized' ? 'up' : o === 'unrealized' ? 'danger' : o === 'needs_verification' ? 'ink2' : 'ink3'
}

/** 周期短名：1h → 1时；表里没有的按单位拼 */
export function intervalShort(iv: string): string {
  const T: Record<string, string> = { m: '分', h: '时', d: '日', w: '周', M: '月', y: '年' }
  const m = /^(\d+)([mhdwMy])$/.exec(iv)
  return m ? m[1] + T[m[2]] : iv
}

/** 短名：BTCUSDT → BTC */
export const shortSymbol = (symbol: string): string => baseOf(symbol)

/** 记录行第三行之后那一行：不进战绩的非「只记录」记录，写「补记」或「核验中」；其余不写 */
export function recordFootnote(r: ViewRecordFull): string | null {
  if (r.eligible || r.draft.rule.direction === 'observe') return null
  const late = r.draft.originalClaimed != null || (r.submitted != null && Math.abs(r.submitted - r.draft.created) > 60_000)
  return late ? '补记' : '核验中'
}

export interface RowText { symbol: string; interval: string; outcome: string; tone: ReturnType<typeof outcomeTone>; text: string; empty: boolean; direction: string; origin: string; time: string; foot: string | null }

/** 记录行上的全部字 */
export function rowText(r: ViewRecordFull): RowText {
  const o = outcome(r)
  return {
    symbol: shortSymbol(r.draft.range.symbol),
    interval: intervalShort(r.draft.range.interval),
    outcome: OUTCOME_TITLE[o], tone: outcomeTone(o),
    text: r.draft.text || '未写原话', empty: !r.draft.text,
    direction: DIRECTION_TITLE[r.draft.rule.direction] ?? r.draft.rule.direction,
    origin: ORIGIN_TITLE[r.draft.origin] ?? ORIGIN_TITLE.unknown,
    time: dayTime(r.draft.created),
    foot: recordFootnote(r),
  }
}

export const dayTime = (ms: number): string => fmtDayTime(ms, SH)
export const fullTime = (ms: number): string => fmtFull(ms, SH)

/** 「完成复盘」不许空着：先写一句 */
export function publishBlocked(note: string): boolean { return !note.trim() }

// ------------------------------------------------------------ 修订记录
type Json = Record<string, unknown>
const obj = (v: unknown): Json | null => v && typeof v === 'object' && !Array.isArray(v) ? v as Json : null
const str = (v: unknown): string | null => typeof v === 'string' ? v : null
const numv = (v: unknown): number | null => typeof v === 'number' && isFinite(v) ? v : null

/** 修订记录里不给人看的那几种（来源核验是后台的事） */
export function visibleRevisions(list: RecordRevision[]): RecordRevision[] { return list.filter(r => r.kind !== 'source_verified') }

export function revisionTitle(rev: RecordRevision): string {
  switch (rev.kind) {
    case 'created': return '规则'
    case 'assessment': return '判定'
    case 'reflection': return obj(obj(rev.body)?.body)?.publish === true ? '复盘 · 完成' : '复盘 · 草稿'
    case 'void': return '作废'
    case 'group': return '归并'
    default: return rev.kind
  }
}

export function revisionLines(rev: RecordRevision, price: (v: number) => string): string[] {
  const body = obj(rev.body) ?? {}
  switch (rev.kind) {
    case 'created': {
      const draft = obj(body.draft), rule = obj(draft?.rule)
      if (!draft || !rule) return []
      const dir = str(rule.direction) ?? 'observe'
      const out = [DIRECTION_TITLE[dir] ?? DIRECTION_TITLE.observe]
      if (dir !== 'observe') {
        const target = numv(rule.target), inval = numv(rule.invalidation), conf = str(rule.confirmation), exp = numv(rule.expires)
        if (target != null) out.push('目标 ' + price(target))
        if (inval != null) out.push('失效 ' + price(inval))
        if (conf && CONFIRM_TITLE[conf]) out.push('判定 ' + CONFIRM_TITLE[conf])
        if (exp != null) out.push('到期 ' + fullTime(exp))
      }
      const text = str(draft.text)
      if (text) out.push('原话 ' + text)
      return out
    }
    case 'assessment': {
      const out = [OUTCOME_TITLE[normalizeOutcome(str(body.outcome))]]
      const reason = str(body.reason)
      if (reason != null) out.push(reason)
      return out
    }
    case 'reflection': {
      const refl = obj(obj(body.body)?.reflection)
      const note = str(refl?.note) ?? '', next = str(refl?.nextTime) ?? ''
      return ['现在怎么看：' + (note || '未写'), '下次怎么做：' + (next || '未写')]
    }
    case 'group': return [obj(body.body)?.sameEpisode === true ? '与上一笔是同一次判断' : '独立判断']
    default: return []
  }
}

// ------------------------------------------------------------ 交易：数怎么写（TradeLabels）
export function dec(s: string | number | null | undefined): number {
  if (s == null || s === '') return 0
  const v = typeof s === 'number' ? s : Number(s)
  return isFinite(v) ? v : 0
}

/** 金额：K / M / B / T，带符号（「+1.23K」「-86.04」）；不带符号时负数仍写「-」 */
export function money(v: number, signed = true): string {
  const body = fmtVol(Math.abs(v))
  if (!signed) return v < 0 ? '-' + body : body
  return v > 0 ? '+' + body : v < 0 ? '-' + body : body
}

/** 比值 → 百分比一位小数 */
export function percent(ratio: number | string | null | undefined, signed = false): string {
  if (ratio == null || ratio === '') return '—'
  const v = dec(ratio) * 100
  const text = toFixed(Math.abs(v), 1) + '%'
  if (!signed) return v < 0 ? '-' + text : text
  return (v > 0 ? '+' : v < 0 ? '-' : '') + text
}

export function ratio(v: number | string | null | undefined): string {
  if (v == null || v === '') return '—'
  return toFixed(dec(v), 2)
}

/** 持仓时长：「45 分」「3 小时 12 分」「2 天 5 小时」 */
export function holding(ms: number | null | undefined): string {
  if (ms == null || !isFinite(ms)) return '—'
  const minutes = Math.max(0, Math.trunc(ms / 60_000))
  if (minutes < 1) return '不到 1 分'
  if (minutes < 60) return `${minutes} 分`
  const hours = Math.trunc(minutes / 60)
  if (hours < 24) return minutes % 60 === 0 ? `${hours} 小时` : `${hours} 小时 ${minutes % 60} 分`
  return hours % 24 === 0 ? `${hours / 24} 天` : `${Math.trunc(hours / 24)} 天 ${hours % 24} 小时`
}

export const tradeDirection = (d: string): string => d === 'long' ? '多' : '空'
export const FILL_ROLE: Record<string, string> = { open: '开仓', add: '加仓', reduce: '减仓', close: '平仓' }
export const pnlTone = (v: number): 'up' | 'down' | 'ink2' => v > 0 ? 'up' : v < 0 ? 'down' : 'ink2'

// ------------------------------------------------------------ 交易：战绩（RoundStats）
export interface RoundSummary {
  count: number; wins: number; losses: number
  winRate: number | null
  netPnl: number; grossPnl: number; commission: number; funding: number; fees: number
  feeShareOfGross: number | null
  averageWin: number | null; averageLoss: number | null
  rewardRisk: number | null; expectancy: number | null
  longestLosingStreak: number
  averageHoldingMs: number | null
  best: Round | null; worst: Round | null
}

export function summarize(rounds: Round[]): RoundSummary {
  const done = rounds.filter(r => r.status === 'closed')
    .sort((a, b) => ((a.closedAt ?? 0) - (b.closedAt ?? 0)) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
  const s: RoundSummary = {
    count: 0, wins: 0, losses: 0, winRate: null, netPnl: 0, grossPnl: 0, commission: 0, funding: 0, fees: 0, feeShareOfGross: null,
    averageWin: null, averageLoss: null, rewardRisk: null, expectancy: null, longestLosingStreak: 0, averageHoldingMs: null, best: null, worst: null,
  }
  if (!done.length) return s
  s.count = done.length
  let winSum = 0, lossSum = 0, hold = 0, streak = 0
  for (const r of done) {
    const net = dec(r.netPnl)
    s.netPnl += net; s.grossPnl += dec(r.realizedPnl); s.commission += dec(r.commission); s.funding += dec(r.funding)
    hold += r.holdingMs ?? 0
    if (net > 0) { s.wins++; winSum += net; streak = 0 }
    if (net < 0) { s.losses++; lossSum += net; streak++; s.longestLosingStreak = Math.max(s.longestLosingStreak, streak) }
    if (net === 0) streak = 0
    if (!s.best || net > dec(s.best.netPnl)) s.best = r
    if (!s.worst || net < dec(s.worst.netPnl)) s.worst = r
  }
  s.fees = s.commission - s.funding
  s.winRate = s.wins / s.count
  s.expectancy = s.netPnl / s.count
  s.feeShareOfGross = s.grossPnl > 0 ? s.fees / s.grossPnl : null
  s.averageWin = s.wins ? winSum / s.wins : null
  s.averageLoss = s.losses ? lossSum / s.losses : null
  if (s.averageWin != null && s.averageLoss != null && s.averageLoss !== 0) s.rewardRisk = s.averageWin / Math.abs(s.averageLoss)
  s.averageHoldingMs = Math.trunc(hold / s.count)
  return s
}

/** 上海时间的时刻拆件（小时、周几：0 = 周日） */
function shParts(ms: number): { hour: number; weekday: number } {
  const d = new Date(ms + SH * 60_000)
  return { hour: d.getUTCHours(), weekday: d.getUTCDay() }
}

export interface RoundGroup { key: string; title: string; summary: RoundSummary }

function groupBy(rounds: Round[], key: (r: Round) => string): Map<string, Round[]> {
  const m = new Map<string, Round[]>()
  for (const r of rounds) {
    if (r.status !== 'closed') continue
    const k = key(r)
    const list = m.get(k)
    if (list) list.push(r); else m.set(k, [r])
  }
  return m
}

/** 按品种：净盈亏从高到低，一样就按代号 */
export function bySymbol(rounds: Round[]): RoundGroup[] {
  return [...groupBy(rounds, r => r.symbol)].map(([k, v]) => ({ key: k, title: shortSymbol(k), summary: summarize(v) }))
    .sort((a, b) => a.summary.netPnl !== b.summary.netPnl ? b.summary.netPnl - a.summary.netPnl : (a.key < b.key ? -1 : 1))
}

export function byDirection(rounds: Round[]): RoundGroup[] {
  const m = groupBy(rounds, r => r.direction)
  return (['long', 'short'] as const).filter(k => m.has(k)).map(k => ({ key: k, title: k === 'long' ? '做多' : '做空', summary: summarize(m.get(k)!) }))
}

export const HOLDING_BUCKETS: [number, string][] = [[3_600_000, '1 小时内'], [DAY, '1 小时–1 天'], [7 * DAY, '1–7 天'], [Infinity, '7 天以上']]
export function holdingBucket(ms: number): string { return HOLDING_BUCKETS.find(([lim]) => ms < lim)![1] }

export function byHolding(rounds: Round[]): RoundGroup[] {
  const m = groupBy(rounds, r => holdingBucket(r.holdingMs ?? 0))
  return HOLDING_BUCKETS.map(b => b[1]).filter(k => m.has(k)).map(k => ({ key: k, title: k, summary: summarize(m.get(k)!) }))
}

export const SESSION_SLOTS = ['凌晨 0–6 点', '上午 6–12 点', '下午 12–18 点', '晚上 18–24 点']
export function sessionSlot(ms: number): string { const h = shParts(ms).hour; return SESSION_SLOTS[h < 6 ? 0 : h < 12 ? 1 : h < 18 ? 2 : 3] }

export function bySession(rounds: Round[]): RoundGroup[] {
  const m = groupBy(rounds, r => sessionSlot(r.openedAt))
  return SESSION_SLOTS.filter(k => m.has(k)).map(k => ({ key: k, title: k, summary: summarize(m.get(k)!) }))
}

export const WEEKDAYS = ['周一', '周二', '周三', '周四', '周五', '周六', '周日']
export function weekdayTitle(ms: number): string { return WEEKDAYS[(shParts(ms).weekday + 6) % 7] }

export function byWeekday(rounds: Round[]): RoundGroup[] {
  const m = groupBy(rounds, r => weekdayTitle(r.openedAt))
  return WEEKDAYS.filter(k => m.has(k)).map(k => ({ key: k, title: k, summary: summarize(m.get(k)!) }))
}

/** 上海时间某天 0 点（UTC 毫秒） */
export function shDayStart(ms: number): number { return Math.floor((ms + SH * 60_000) / DAY) * DAY - SH * 60_000 }

/** 上周：[上周一 0 点, 本周一 0 点)，上海时间 */
export function lastWeekBounds(now: number): { start: number; end: number } {
  const today = shDayStart(now)
  const monday = today - ((shParts(now).weekday + 6) % 7) * DAY
  return { start: monday - 7 * DAY, end: monday }
}

export interface WeeklyReport { start: number; end: number; summary: RoundSummary }

export function lastWeek(rounds: Round[], now: number): WeeklyReport {
  const { start, end } = lastWeekBounds(now)
  return { start, end, summary: summarize(rounds.filter(r => r.status === 'closed' && r.closedAt != null && r.closedAt >= start && r.closedAt < end)) }
}

/** 周报卡标题旁的日期：「9/22–9/28」 */
export function weekSpan(w: { start: number; end: number }): string {
  const md = (ms: number): string => { const d = new Date(ms + SH * 60_000); return `${d.getUTCMonth() + 1}/${d.getUTCDate()}` }
  return `${md(w.start)}–${md(w.end - 1)}`
}

const WEEK_CN = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']
/** 交易分组标题：「今天」「昨天」「9 月 27 日 周六」 */
export function tradeDayLabel(ms: number, now: number): string {
  const d0 = shDayStart(ms), n0 = shDayStart(now)
  if (d0 === n0) return '今天'
  if (d0 === n0 - DAY) return '昨天'
  const d = new Date(ms + SH * 60_000)
  return `${d.getUTCMonth() + 1} 月 ${d.getUTCDate()} 日 ${WEEK_CN[d.getUTCDay()]}`
}

export interface TradeSections { open: TradeRecord[]; days: { title: string; items: TradeRecord[] }[] }

/** 交易列表：作废的不要；持仓中一组，其余按平仓（没有就开仓）那天分组，新的在上 */
export function tradeSections(list: TradeRecord[], now: number): TradeSections {
  const live = list.filter(t => !t.voided)
  const open = live.filter(t => t.round.status === 'open')
  const closed = live.filter(t => t.round.status !== 'open')
    .sort((a, b) => (b.round.closedAt ?? b.round.openedAt) - (a.round.closedAt ?? a.round.openedAt))
  const days: { title: string; items: TradeRecord[] }[] = []
  const at = new Map<string, { title: string; items: TradeRecord[] }>()
  for (const t of closed) {
    const title = tradeDayLabel(t.round.closedAt ?? t.round.openedAt, now)
    let g = at.get(title)
    if (!g) { g = { title, items: [] }; at.set(title, g); days.push(g) }
    g.items.push(t)
  }
  return { open, days }
}

/** 按 id 去重追加交易 */
export function appendTrades(list: TradeRecord[], more: TradeRecord[]): TradeRecord[] {
  const seen = new Set(list.map(t => t.id))
  return [...list, ...more.filter(t => !seen.has(t.id) && (seen.add(t.id), true))]
}

// ------------------------------------------------------------ 「我的」根上那两行
export function rootLine1(signedIn: boolean, t: Tally, pending: number): string {
  if (!signedIn) return '登录后可用'
  const base = `观点 ${t.live} 条`
  return pending > 0 ? `${base} · 待判定 ${pending}` : base
}

/** 交易那半句：没有回合（网页上看不到交易所接没接，按有没有回合算）就是「接入交易所后自动生成」 */
export function rootLine2(signedIn: boolean, trades: TradeRecord[], now: number): string {
  if (!signedIn) return ''
  const live = trades.filter(t => !t.voided)
  if (!live.length) return '接入交易所后自动生成'
  const s = lastWeek(live.map(t => t.round), now).summary
  if (!s.count) return '交易 上周 0 笔'
  return `交易 上周 ${s.count} 笔 · 净盈亏 ${money(s.netPnl)} · 胜率 ${percent(s.winRate)}`
}

// ------------------------------------------------------------ 待传队列（照 iOS ReviewSyncEngine）
// 复盘、作废、归并先写进本机队列、先改本机这份，再逐条传；断网、服务端忙就留在队列里，
// 下次打开复盘本 / 回到前台 / 联网时再传。幂等键是这一次改动的编号，重发不会改两次。
// 服务端明确不收（409 冲突、400/404/422 等拒收）的那次改动隔离下来，不再自动重发，
// 在记录详情里给人「用我这份 / 用云端那份」（冲突）或「留在本机」（拒收）。

/** 被隔离的那次上传：为什么没传上去；retryable = 冲突，可以拿最新版本号重发 */
export interface OpConflict { reason: string; retryable: boolean }

export type OpKind = 'reflection' | 'void' | 'group'

export interface OpBody { expectedRevision: number; reflection?: ReviewReflection; publish?: boolean; sameEpisode?: boolean }

export interface PendingOp {
  /** 这一次改动的编号，同时当幂等键 */
  id: string
  recordId: string
  kind: OpKind
  body: OpBody
  /** 写进队列的时刻（完成复盘的 publishedAt 就记它） */
  at: number
  /** 在这之前不发（作废留 5 秒撤销） */
  holdUntil?: number
  /** 已经发出去过：幂等键定死了，不能再合并 / 撤销 */
  attempted?: boolean
  conflict?: OpConflict | null
  /** 人选了「留在本机」：不再发，本机照样叠着显示 */
  kept?: boolean
  /** 最近一次没传上去的原因（暂时性的，下一轮还会再试） */
  error?: string | null
}

export const PENDING_KEY = 'hkline-m-review-pending-v1'
export const VOID_HOLD_MS = 5000

export interface KV { getItem(k: string): string | null; setItem(k: string, v: string): void }

type PendingStore = Record<string, PendingOp[]>
function readStore(kv: KV): PendingStore {
  try {
    const v = JSON.parse(kv.getItem(PENDING_KEY) || '{}')
    return v && typeof v === 'object' && !Array.isArray(v) ? v as PendingStore : {}
  } catch { return {} }
}

/** 这个账号的待传队列（按写入顺序） */
export function readPending(kv: KV, user: string): PendingOp[] {
  const list = readStore(kv)[user]
  return Array.isArray(list) ? list.filter(o => o && typeof o.id === 'string' && typeof o.recordId === 'string') : []
}

export function writePending(kv: KV, user: string, ops: PendingOp[]): void {
  const all = readStore(kv)
  if (ops.length) all[user] = ops; else delete all[user]
  try { kv.setItem(PENDING_KEY, JSON.stringify(all)) } catch { /* 存满了：这一轮只活在内存里 */ }
}

/** 进队列：同一条记录的复盘只留最后一份（还没发过的、被隔离的、留在本机的都让位给新的）；
 *  作废重复点只留一份。已经发出去过、还没回音的那份不动——幂等键已经定了 */
export function enqueueOp(ops: PendingOp[], op: PendingOp): PendingOp[] {
  const superseded = (o: PendingOp): boolean => {
    if (o.recordId !== op.recordId || o.kind !== op.kind) return false
    if (op.kind === 'reflection') return !o.attempted || !!o.conflict || !!o.kept
    if (op.kind === 'void') return !o.attempted
    return false
  }
  return [...ops.filter(o => !superseded(o)), op]
}

/** 把队列里属于这条的改动按顺序叠到服务端那份上（不改入参） */
export function applyPending<T extends ViewRecordFull>(record: T, ops: PendingOp[]): T & { conflict?: OpConflict | null } {
  const mine = ops.filter(o => o.recordId === record.draft.id || (record.serverId != null && o.recordId === record.serverId))
  if (!mine.length) return record
  const r: T & { conflict?: OpConflict | null } = { ...record, reflectionHistory: record.reflectionHistory ? [...record.reflectionHistory] : record.reflectionHistory }
  for (const op of mine) {
    if (op.kind === 'reflection' && op.body.reflection) {
      const prev = r.reflection
      if (prev && prev.publishedAt != null) r.reflectionHistory = [prev, ...(r.reflectionHistory ?? [])].slice(0, 5)
      r.reflection = { ...op.body.reflection, publishedAt: op.body.publish ? op.at : null }
    } else if (op.kind === 'void') {
      r.voided = true
    } else if (op.kind === 'group') {
      r.groupPending = false
    }
    if (op.conflict) r.conflict = op.conflict
    else if (op.error) r.syncError = op.error
  }
  return r
}

/** 失败归哪一类：conflict 冲突（409）· rejected 服务端不收（重发也没用）· transient 暂时的（断网、超时、5xx、429） */
export type FailureVerdict = 'conflict' | 'rejected' | 'transient'
export interface FailureLike { code?: string; status?: number }

export function failureVerdict(e: FailureLike | null | undefined): FailureVerdict {
  const s = e?.status ?? 0
  if (s === 409) return 'conflict'
  if ([400, 404, 405, 410, 413, 415, 422].includes(s)) return 'rejected'
  return 'transient'
}

const FAILURE_BY_CODE: Record<string, string> = {
  record_revision_changed: '这条记录在别的设备上改过了',
  record_identity_conflict: '这条记录在别的设备上改过了',
  idempotency_mismatch: '这条记录在别的设备上改过了',
  record_voided: '这条记录已经作废，改不动了',
  group_already_resolved: '这一组已经归并过了',
  invalid_review_evidence: '这段行情服务端不收，换一段再记',
  invalid_chart_range: '这段行情服务端不收，换一段再记',
  invalid_chart_snapshot: '这一屏的设置或画线太大，服务端收不下',
  invalid_drawing_snapshot: '这一屏的设置或画线太大，服务端收不下',
  invalid_reflection: '这次改动服务端不收',
  invalid_change: '这次改动服务端不收',
  not_found: '服务端找不到这条记录',
  search_cancelled: '这次查找已取消',
  search_incomplete: '行情暂不完整，请稍后重试',
  search_timeout: '查找用时太长，已先停下，请稍后重试',
}

/** 没传上去 / 没找完的那句话（照 iOS ReviewSyncEngine.failureMessage：先看错误码，再按状态码兜底） */
export function failureMessage(e: FailureLike | null | undefined): string {
  const code = e?.code ?? '', s = e?.status ?? 0
  if (FAILURE_BY_CODE[code]) return FAILURE_BY_CODE[code]
  if (s === 401 || s === 403) return '连接凭证已失效，请重新连接'
  if (s === 409) return '这条记录在别的设备上改过了'
  if (s === 404) return '服务端还未提供此功能'
  if (s >= 500) return '服务端暂时不可用，稍后自动重试'
  return '同步暂未成功，请稍后重试'
}

/** 「记一笔」队列里还没传上去的那条，在复盘本里先按本机记录列出来（serverId 为空） */
export function localNoteRecord(draft: { id: string; range: ChartRange; rule: object; text: string; origin: string; created: number }): LocalRecord {
  return {
    draft: { id: draft.id, range: draft.range, rule: draft.rule as ViewRecordFull['draft']['rule'], text: draft.text, confidence: null, origin: draft.origin, created: draft.created },
    serverId: null, submitted: null, revision: 0, assessment: null, reflection: null, eligible: true, voided: false,
  }
}

// ------------------------------------------------------------ 找相似（照 iOS ReviewSearchModel）
export const MIN_SEARCH_BARS = 16
export const MIN_SEARCH_TEXT = '找相似至少框选 16 根 K 线'

/** 轮询节奏：起步 2 秒，进度没动就翻倍到 30 秒封顶；进度一动就回到 2 秒；总共 10 分钟 */
export class PollSchedule {
  private delay: number
  private lastChecked: number | null = null
  constructor(readonly base = 2000, readonly ceiling = 30000, readonly budget = 600000) { this.delay = base }
  /** 下一次等多久；预算用完回 null */
  next(checked: number, elapsed: number): number | null {
    if (elapsed >= this.budget) return null
    if (this.lastChecked !== null && checked !== this.lastChecked) this.delay = this.base
    this.lastChecked = checked
    const wait = Math.min(this.delay, this.budget - elapsed)
    this.delay = Math.min(this.delay * 2, this.ceiling)
    return wait
  }
}

/** 轮询中出的错：断网、限流、服务端忙都接着等，别的就停 */
export function keepsPolling(status: number): boolean { return status === 0 || status === 429 || status >= 500 }

export function searchProgressText(s: { checked: number; total: number } | null | undefined): string {
  if (!s || !(s.total > 0)) return '正在查找'
  return `正在比对 ${s.checked}/${s.total}`
}

export function appendMatches(list: Match[], more: Match[]): Match[] {
  const seen = new Set(list.map(m => m.id))
  return [...list, ...more.filter(m => !seen.has(m.id) && (seen.add(m.id), true))]
}

export function scoreText(score: number): string { return '相似 ' + toFixed(Math.max(0, Math.min(1, score)), 2) }

export interface MatchRowText { title: string; time: string; bars: string; score: string }
export function matchRowText(m: Match): MatchRowText {
  return {
    title: `${shortSymbol(m.range.symbol)} · ${intervalShort(m.range.interval)}`,
    time: fullTime(m.range.start), bars: `${m.range.bars} 根`, score: scoreText(m.score),
  }
}

// ------------------------------------------------------------ 观点 ↔ 交易（照 iOS ReviewLinks）
interface Span { start: number; end: number }
const overlaps = (a: Span, b: Span): boolean => a.start <= b.end && b.start <= a.end
const viewSpan = (r: ViewRecordFull): Span => ({ start: r.draft.created, end: Math.max(r.draft.created, r.draft.rule.expires) })
const tradeSpan = (x: Round, now: number): Span => ({ start: x.openedAt, end: Math.max(x.openedAt, x.closedAt ?? now) })

/** 这一笔交易持仓期间，同一品种上还活着的观点（按记下时间排） */
export function viewsForRound(round: Round, views: ViewRecordFull[], now: number): ViewRecordFull[] {
  const sym = round.symbol.toUpperCase(), span = tradeSpan(round, now)
  return views.filter(v => !v.voided && v.draft.range.symbol.toUpperCase() === sym && overlaps(viewSpan(v), span))
    .sort((a, b) => a.draft.created - b.draft.created)
}

/** 这条观点有效期里，同一品种上的交易（按开仓时间排）；作废的观点不挂交易 */
export function roundsForView(view: ViewRecordFull, trades: TradeRecord[], now: number): TradeRecord[] {
  if (view.voided) return []
  const sym = view.draft.range.symbol.toUpperCase(), span = viewSpan(view)
  return trades.filter(t => !t.voided && t.round.symbol.toUpperCase() === sym && overlaps(tradeSpan(t.round, now), span))
    .sort((a, b) => a.round.openedAt - b.round.openedAt)
}

// ------------------------------------------------------------ 交易那张图（照 iOS ExchangeReviewBridge.chartImage）
const IV_STEP: Record<string, number> = {
  '1m': 6e4, '3m': 18e4, '5m': 3e5, '15m': 9e5, '30m': 18e5, '1h': 36e5, '2h': 72e5, '4h': 144e5,
  '6h': 216e5, '8h': 288e5, '12h': 432e5, '1d': DAY, '3d': 3 * DAY, '1w': 7 * DAY,
}
export const ivStep = (iv: string): number | undefined => IV_STEP[iv]

/** 按持仓时长挑周期：4 小时内 5 分、2 天内 1 小时、两周内 4 小时，再长日线 */
export function holdingInterval(ms: number): string {
  if (ms <= 4 * 36e5) return '5m'
  if (ms <= 2 * DAY) return '1h'
  if (ms <= 14 * DAY) return '4h'
  return '1d'
}

export interface ChartSpec { interval: string; start: number; end: number }

/** 没有服务端结果时自己框：开仓前、平仓后各垫 max(10 根, 持仓的四分之一)，不超过现在 */
export function chartWindow(round: Round, now: number): ChartSpec {
  const close = round.closedAt ?? now
  const held = Math.max(0, close - round.openedAt)
  const interval = holdingInterval(held)
  const step = IV_STEP[interval]
  const pad = Math.max(10 * step, Math.trunc(held / 4))
  const floorTo = (t: number) => Math.floor(t / step) * step
  const ceilTo = (t: number) => Math.ceil(t / step) * step
  const start = floorTo(round.openedAt - pad)
  const end = Math.max(start, Math.min(ceilTo(close + pad), floorTo(now)))
  return { interval, start, end }
}

/** 服务端算结果时用的那段优先，不合法再自己框 */
export function chartSpecFor(round: Round, result: { chart: ChartSpec | null } | null | undefined, now: number): ChartSpec {
  const c = result?.chart
  if (c && IV_STEP[c.interval] && c.end > c.start) return { interval: c.interval, start: c.start, end: c.end }
  return chartWindow(round, now)
}

export interface TradeMarker { kind: 'markerUp' | 'markerDown' | 'hline'; t: number; p: number; id: string; dashed: boolean }

/** 图上的记号：每笔成交一个箭头（买向上、卖向下），开仓均价、平仓均价各一条虚线 */
export function tradeMarkers(round: Round): TradeMarker[] {
  const out: TradeMarker[] = []
  for (const f of round.fills) {
    const p = dec(f.price)
    if (p > 0) out.push({ kind: f.side === 'BUY' ? 'markerUp' : 'markerDown', t: f.time, p, id: 'fill-' + f.id, dashed: false })
  }
  const open = dec(round.openAvgPrice)
  if (open > 0) out.push({ kind: 'hline', t: round.openedAt, p: open, id: 'avg-open', dashed: true })
  const close = dec(round.closeAvgPrice)
  if (round.closeAvgPrice && close > 0) out.push({ kind: 'hline', t: round.openedAt, p: close, id: 'avg-close', dashed: true })
  return out
}

/** 品种表里没有小数位时，从收盘价里看出来（最多 8 位） */
export function decimalsOfCloses(closes: number[]): number | null {
  let best = -1
  for (const c of closes) {
    if (!(c > 0)) continue
    const s = String(c)
    if (s.includes('e')) continue
    const i = s.indexOf('.')
    best = Math.max(best, i < 0 ? 0 : s.length - i - 1)
  }
  return best < 0 ? null : Math.min(8, best)
}

// ------------------------------------------------------------ 补图（照 iOS ReviewAttachmentsView）
export const ATTACH_LIMIT = 3
export const ATTACH_MAX_BYTES = 5 * 1024 * 1024

/** 压 JPEG 的几轮：长边 2048、质量 0.82 起，每轮长边 × 0.75、质量 −0.1（不低于 0.5），共 6 轮 */
export function jpegSteps(): { side: number; quality: number }[] {
  const out: { side: number; quality: number }[] = []
  let side = 2048, quality = 0.82
  for (let i = 0; i < 6; i++) {
    out.push({ side: Math.round(side), quality: Math.round(quality * 100) / 100 })
    side *= 0.75
    quality = Math.max(0.5, quality - 0.1)
  }
  return out
}

/** 按长边缩放的比例（只缩不放） */
export function fitScale(w: number, h: number, side: number): number { return Math.min(1, side / Math.max(w, h, 1)) }

/** base64 解码后的字节数 */
export function base64Bytes(b64: string): number {
  const pad = b64.endsWith('==') ? 2 : b64.endsWith('=') ? 1 : 0
  return Math.floor(b64.length * 3 / 4) - pad
}

// ------------------------------------------------------------ 去图上看（复盘本 → 行情页）
// 在图上重温 / 打开相似片段 / 回放这笔交易：复盘本把回放计划写进 sessionStorage 并广播一个事件，
// 自己把行情页切到那只品种、那个周期；行情页认领这份意图后按计划回放（见交付说明里的接口）。
export const INTENT_KEY = 'hkline-m-review-intent'
export const INTENT_EVENT = 'hkline:review-intent'

export type IntentKind = 'revisit' | 'match' | 'trade'
export interface ReviewIntent<P = unknown> { kind: IntentKind; at: number; plan: P; market?: string | null }
