/* Hkline Web · 复盘：回放计划（纯函数，不碰 DOM）
 *
 * 照手机端 ReviewReplayPolicy / TradeReplayPlan / ReplayPace：
 *   交易回放   周期先看服务端算结果时用的周期，再按 30–60 根挑；从开仓前 20 根开始，平仓后 5 根停；
 *              往前多拉 300 根历史垫底，让均线、形态和当时屏幕上看到的一样。
 *              开仓、平仓两处各停 1.2 秒；速度按总时长 ≤ 40 秒在 1× / 2× / 4× 里自动挑。
 *   在图上重温  观点记录：从记录的图表区间起点开始，判断处停一下，一直放到答案出来（或到期）后 5 根。
 *   相似片段   相似段整段先摆出来，往后放「后来怎么走」40 根。
 * 播放条只有拖进度线与关键点跳转，没有逐根步进——这里也就不提供「下一根」这种接口。
 */
import { IV_MS } from '../util/format'
import { judgedAt, num, outcomeOf } from './model'
import type { Match, Round, TradeResult, ViewRecord, ViewRule } from './types'

export const LEAD_BARS = 20
export const TAIL_BARS = 5
export const HISTORY_BARS = 300
export const PAUSE_MS = 1200
export const HOLD_MS = 800
export const MAX_REPLAY_S = 40
export const SPEEDS = [1, 2, 4] as const
export const AFTER_MATCH_BARS = 40

const CANDIDATES = ['1m', '5m', '15m', '1h', '4h', '1d']

export function floorTo(t: number, step: number): number { return Math.floor(t / step) * step }

/** 回放用的周期：偏好周期能放下 10–200 根就用它；否则用服务端结果里的周期；否则在候选里挑最接近 30–60 根的（一样近取小周期） */
export function chooseInterval(from: number, to: number, preferred?: string | null, serverIv?: string | null): string {
  const span = Math.max(0, to - from)
  const barsOn = (iv: string) => span / IV_MS[iv]
  if (preferred && IV_MS[preferred]) { const n = barsOn(preferred); if (n >= 10 && n <= 200) return preferred }
  if (serverIv && IV_MS[serverIv]) return serverIv
  let best = CANDIDATES[0], bestD = Infinity
  for (const iv of CANDIDATES) {
    const n = barsOn(iv)
    const d = n < 30 ? 30 - n : n > 60 ? n - 60 : 0
    if (d < bestD) { best = iv; bestD = d }
  }
  return best
}

/** 自动速度：放完这些根 + 固定停顿不超过 40 秒的最小一档；都超就 4× */
export function chooseSpeed(bars: number, fixedMs = HOLD_MS + 2 * PAUSE_MS): number {
  for (const s of SPEEDS) if (bars / s + fixedMs / 1000 <= MAX_REPLAY_S) return s
  return SPEEDS[SPEEDS.length - 1]
}

/** 播放一根之后要等多久：基础 1 秒 ÷ 速度，停在关键点上再多等 1.2 秒 */
export function stepDelay(speed: number, pauseHere: boolean): number { return 1000 / speed + (pauseHere ? PAUSE_MS : 0) }

export interface KeyPoint {
  id: string
  label: string
  /** 所在 K 线的开盘时间 */
  t: number
  /** 播放经过时停一下 */
  pause: boolean
}

/** 进度线上的刻度 */
export interface Tick { t: number; kind: 'entry' | 'exit' | 'key' }

interface PlanBase {
  symbol: string
  iv: string
  step: number
  /** 回放起点（K 线开盘时间）；拖到最左就是它 */
  startBar: number
  /** 回放终点 */
  stopBar: number
  /** 打开时停在哪一根 */
  initialBar: number
  /** 要拉的 K 线窗口 */
  fetchFrom: number
  fetchTo: number
  keys: KeyPoint[]
  ticks: Tick[]
  speed: number
}

export interface ReplayMark {
  t: number
  bar: number
  role: string
  entry: boolean
  side: 'BUY' | 'SELL'
  price: number
  qty: number
}

/** 开仓均价的一段：从这笔开 / 加仓所在的 K 线，到下一笔开 / 加仓（或平仓）为止 */
export interface AvgSeg { from: number; to: number; price: number }

export interface TradePlan extends PlanBase {
  kind: 'trade'
  direction: 'long' | 'short'
  closed: boolean
  openBar: number
  closeBar: number
  marks: ReplayMark[]
  avgSegs: AvgSeg[]
  note: string | null
}

export interface NotePlan extends PlanBase {
  kind: 'note'
  rule: ViewRule
  rangeStart: number
  rangeEnd: number
  judgeBar: number
  judgeT: number
  eventBar: number | null
  expireBar: number | null
  outcome: string
  text: string
}

export interface MatchPlan extends PlanBase {
  kind: 'match'
  rangeStart: number
  rangeEnd: number
  score: number
}

export type Plan = TradePlan | NotePlan | MatchPlan

const isEntry = (role: string): boolean => role === 'open' || role === 'add'

/** 交易回放计划 */
export function planTrade(round: Round, result: TradeResult | null, now: number, note: string | null = null, preferred?: string | null): TradePlan {
  const fills = round.fills.slice().sort((a, b) => a.time - b.time)
  const closed = round.status === 'closed' && round.closedAt != null
  const openedAt = fills[0]?.time ?? round.openedAt
  const endAt = closed ? round.closedAt! : now
  const iv = chooseInterval(openedAt, endAt, preferred, result?.chart?.interval)
  const step = IV_MS[iv]
  const nowBar = floorTo(now, step)
  const marks: ReplayMark[] = fills.map(f => ({ t: f.time, bar: floorTo(f.time, step), role: f.role, entry: isEntry(f.role), side: f.side, price: num(f.price), qty: num(f.qty) }))
  const entries = marks.filter(m => m.entry), exits = marks.filter(m => !m.entry)
  const openBar = entries[0]?.bar ?? floorTo(openedAt, step)
  const closeBar = closed ? (exits.length ? exits[exits.length - 1].bar : floorTo(endAt, step)) : nowBar
  const startBar = openBar - LEAD_BARS * step
  const stopBar = closed ? Math.min(nowBar, closeBar + TAIL_BARS * step) : nowBar
  // 开仓均价：每笔开 / 加仓之后重算，减仓不动均价
  const avgSegs: AvgSeg[] = []
  let qty = 0, cost = 0
  for (const m of entries) {
    cost += m.price * m.qty; qty += m.qty
    const last = avgSegs[avgSegs.length - 1]
    if (last) last.to = m.bar
    avgSegs.push({ from: m.bar, to: closeBar, price: qty ? cost / qty : m.price })
  }
  const keys: KeyPoint[] = [{ id: 'open', label: '开仓处', t: openBar, pause: true }]
  if (closed) keys.push({ id: 'close', label: '平仓处', t: closeBar, pause: true })
  const ticks: Tick[] = marks.map(m => ({ t: m.bar, kind: m.entry ? 'entry' as const : 'exit' as const }))
  const playBars = Math.round((stopBar - startBar) / step)
  return {
    kind: 'trade', symbol: round.symbol, iv, step, direction: round.direction, closed,
    startBar, stopBar, initialBar: openBar, openBar, closeBar,
    fetchFrom: startBar - HISTORY_BARS * step, fetchTo: stopBar + step,
    keys, ticks, marks, avgSegs, note: note?.trim() || null,
    speed: chooseSpeed(playBars, HOLD_MS + (closed ? 2 : 1) * PAUSE_MS),
  }
}

/** 已经放到的这一根里能看到的成交：不许把后面的成交提前画出来 */
export function visibleMarks(plan: TradePlan, revealedBar: number): ReplayMark[] { return plan.marks.filter(m => m.bar <= revealedBar) }

/** 这一根收盘时的持仓与浮动收益：只在持仓中（开仓处之后、平仓处之前）有值 */
export function positionAt(plan: TradePlan, revealedBar: number, close: number): { qty: number; avg: number; floating: number } | null {
  if (revealedBar < plan.openBar) return null
  if (plan.closed && revealedBar >= plan.closeBar) return null
  let qty = 0, cost = 0
  for (const m of plan.marks) {
    if (m.bar > revealedBar) break
    if (m.entry) { cost += m.price * m.qty; qty += m.qty }
    else { const avg = qty ? cost / qty : 0; qty = Math.max(0, qty - m.qty); cost = avg * qty }
  }
  if (qty <= 0) return null
  const avg = cost / qty
  const sign = plan.direction === 'long' ? 1 : -1
  return { qty, avg, floating: avg ? (close - avg) / avg * sign : 0 }
}

/** 在图上重温（观点记录） */
export function planNote(rec: ViewRecord, now: number): NotePlan {
  const range = rec.draft.range, rule = rec.draft.rule
  const iv = IV_MS[range.interval] ? range.interval : '1h'
  const step = IV_MS[iv]
  const nowBar = floorTo(now, step)
  const judgeT = judgedAt(rec)
  const judgeBar = Math.min(nowBar, floorTo(judgeT, step))
  const ev = rec.assessment?.eventAt ?? null
  const eventBar = ev != null ? floorTo(ev, step) : null
  const expireBar = rule.direction !== 'observe' && rule.expires <= now ? floorTo(rule.expires, step) : null
  // 放到哪儿：答案出来那根；还没答案就到期那根；还没到期就到现在
  const endBar = eventBar ?? expireBar ?? nowBar
  const stopBar = Math.min(nowBar, Math.max(judgeBar, endBar) + TAIL_BARS * step)
  const startBar = Math.min(range.start, judgeBar)
  const keys: KeyPoint[] = [{ id: 'judge', label: '判断处', t: judgeBar, pause: true }]
  if (eventBar != null && eventBar <= stopBar) keys.push({ id: 'event', label: '答案处', t: eventBar, pause: true })
  else if (expireBar != null && expireBar <= stopBar) keys.push({ id: 'expire', label: '到期处', t: expireBar, pause: true })
  return {
    kind: 'note', symbol: range.symbol, iv, step, rule,
    rangeStart: range.start, rangeEnd: range.end, judgeBar, judgeT, eventBar, expireBar,
    outcome: outcomeOf(rec), text: rec.draft.text,
    startBar, stopBar, initialBar: judgeBar,
    fetchFrom: startBar - HISTORY_BARS * step, fetchTo: stopBar + step,
    keys, ticks: keys.map(k => ({ t: k.t, kind: 'key' as const })),
    speed: chooseSpeed(Math.round((stopBar - judgeBar) / step), HOLD_MS + keys.length * PAUSE_MS),
  }
}

/** 相似片段：先摆出整段，往后放「后来怎么走」 */
export function planMatch(m: Match, now: number): MatchPlan {
  const iv = IV_MS[m.range.interval] ? m.range.interval : '1h'
  const step = IV_MS[iv]
  const lastBar = m.range.end - step // end 是区间右边界（不含），最后一根的开盘时间
  const stopBar = Math.min(floorTo(now, step), lastBar + AFTER_MATCH_BARS * step)
  return {
    kind: 'match', symbol: m.range.symbol, iv, step, score: m.score,
    rangeStart: m.range.start, rangeEnd: m.range.end,
    startBar: m.range.start, stopBar, initialBar: lastBar,
    fetchFrom: m.range.start - HISTORY_BARS * step, fetchTo: stopBar + step,
    keys: [{ id: 'segEnd', label: '相似段结束', t: lastBar, pause: false }],
    ticks: [{ t: lastBar, kind: 'key' }],
    speed: chooseSpeed(Math.round((stopBar - lastBar) / step), HOLD_MS),
  }
}

/** 时间 → 进度线上的位置（0–1） */
export function trackPos(plan: Pick<PlanBase, 'startBar' | 'stopBar'>, t: number): number {
  const span = plan.stopBar - plan.startBar
  if (span <= 0) return 1
  return Math.max(0, Math.min(1, (t - plan.startBar) / span))
}

/** 进度线上的位置 → 对齐到周期的时间 */
export function timeAtPos(plan: Pick<PlanBase, 'startBar' | 'stopBar' | 'step'>, pos: number): number {
  const n = Math.round((plan.stopBar - plan.startBar) / plan.step)
  return plan.startBar + Math.round(Math.max(0, Math.min(1, pos)) * n) * plan.step
}
