/* 手机网页版 · 行情页回放的纯逻辑（不碰 DOM，单测见 tests/m-replay-logic.test.ts）
 *
 * 照 iOS ReviewChartBridge（open / openTrade / track / ended / seek / restart / jumpToKey / updateReplay）
 * 与 ReviewDomain/ReviewReplayPolicy（ReviewReplayViewport.next、ReviewReplayTrack）：
 * - 意图（复盘本写进 sessionStorage 的那一份）先在这里验过形状，坏的、过期的一律不认；
 * - 进度线按「卷里第几根」算，不按时间算；
 * - 每推进一根的视野：人还跟着播放头就往前推、根宽不动；人拖去看别处就不拽回来；只有打开、重播、跳关键点才重设。
 * 播放条上没有逐根步进（2026-09-28 用户：「谁看行情也不是一根根点」），所以这里也不给「下一根」。
 */
import type { Plan, ReplayMark, TradePlan } from '../../review/replay'
import { INTERVAL_SHORT, INTERVAL_STEP, isIrregular, type Interval } from '../chart/series'
import { EXTERNAL_IDS } from '../chart/external.source'

export type IntentKind = 'revisit' | 'match' | 'trade'

/** 认领下来的回放意图 */
export interface ReplayIntent {
  kind: IntentKind
  at: number
  plan: Plan
  /** 「venue/market」（如 binance/usd_m）；旧的意图里没有 */
  market: string | null
}

/** 意图放在 sessionStorage 里太久（关页再开、隔天回来）就不认了：那时人早不在等这段回放 */
export const INTENT_TTL_MS = 10 * 60_000
/** 一卷最多几根（iOS fetchTape：超过就说区间太长） */
export const MAX_TAPE_BARS = 6000
/** 图上至少要有三根 */
export const MIN_BARS = 3
/** 视野兜底：80 根宽、右边留 6 根（ReviewReplayViewport） */
export const DEFAULT_BARS = 80
export const RIGHT_PAD_BARS = 6

const PLAN_KIND: Record<IntentKind, Plan['kind']> = { revisit: 'note', match: 'match', trade: 'trade' }
const fin = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v)

/** 验一份意图：形状不对、种类对不上、过期了都回 null */
export function parseIntent(raw: unknown, now: number): ReplayIntent | null {
  if (!raw || typeof raw !== 'object') return null
  const r = raw as Record<string, unknown>
  const kind = r.kind as IntentKind
  if (!(kind in PLAN_KIND)) return null
  if (!fin(r.at) || now - r.at > INTENT_TTL_MS || r.at - now > 60_000) return null
  const p = r.plan as Record<string, unknown> | null
  if (!p || typeof p !== 'object' || p.kind !== PLAN_KIND[kind]) return null
  if (typeof p.symbol !== 'string' || !/^[A-Z0-9]{2,40}$/.test(p.symbol)) return null
  if (typeof p.iv !== 'string' || !(p.iv in INTERVAL_STEP)) return null
  for (const k of ['step', 'startBar', 'stopBar', 'initialBar', 'fetchFrom', 'fetchTo', 'speed'] as const) if (!fin(p[k])) return null
  if (!((p.step as number) > 0) || (p.stopBar as number) < (p.startBar as number) || (p.fetchTo as number) <= (p.fetchFrom as number)) return null
  if (!Array.isArray(p.keys) || !p.keys.every(k => k && typeof k === 'object' && fin((k as { t: unknown }).t) && typeof (k as { label: unknown }).label === 'string')) return null
  if (!Array.isArray(p.ticks)) return null
  if (p.kind === 'trade') {
    if (!Array.isArray(p.marks) || !Array.isArray(p.avgSegs) || !fin(p.openBar) || !fin(p.closeBar)) return null
    if (p.direction !== 'long' && p.direction !== 'short') return null
    if (!p.marks.every(m => m && fin((m as ReplayMark).bar) && fin((m as ReplayMark).price) && fin((m as ReplayMark).qty))) return null
  } else if (p.kind === 'note') {
    const rule = p.rule as Record<string, unknown> | null
    if (!rule || !fin(rule.reference) || !fin(rule.target) || !fin(rule.invalidation)) return null
    if (!fin(p.judgeBar) || !fin(p.rangeStart) || !fin(p.rangeEnd)) return null
  } else if (!fin(p.rangeStart) || !fin(p.rangeEnd)) return null
  const market = typeof r.market === 'string' && r.market ? r.market.toLowerCase() : null
  return { kind, at: r.at, plan: p as unknown as Plan, market }
}

/** 网页版只取得到币安 U 本位合约的 K 线 */
export const replayableMarket = (market: string | null): boolean => market == null || market === 'binance/usd_m'

// ───────────────────────────── 取数

export type TapeProblem = 'tooLarge' | 'noHistory' | 'gap' | 'failed' | 'market'

/** 失败时说的那句话（iOS ReviewChartBridge.message：自己判出来的几种照原话，取数抛上来的一律「暂时取不到」） */
export const TAPE_MESSAGE: Record<TapeProblem, string> = {
  tooLarge: '区间过长，请缩短后重温',
  noHistory: '这段历史暂时无法获取',
  gap: '这段行情有缺口，暂不进入重温',
  failed: '这段历史暂时取不到，稍后再试',
  market: '这个市场暂未接入原生行情',
}

/** 这卷要拉多少根：超过上限就不拉了 */
export function tapeTooLarge(plan: Pick<Plan, 'fetchFrom' | 'fetchTo' | 'step'>): boolean {
  return (plan.fetchTo - plan.fetchFrom) / plan.step > MAX_TAPE_BARS
}

/** 拉回来的这卷能不能放：不到三根、交易回放开仓那根之后没有 K 线 → 没历史；中间断档 → 有缺口 */
export function checkTape(times: readonly number[], plan: Plan): TapeProblem | null {
  if (times.length < MIN_BARS) return 'noHistory'
  if (plan.kind === 'trade' && !times.some(t => t >= plan.openBar)) return 'noHistory'
  // 只查要放的那一段（起点往后）：垫底的 300 根历史里偶有交易所维护的断档，不该因此整段放不了
  if (!isIrregular(plan.iv as Interval)) {
    for (let i = 1; i < times.length; i++) if (times[i - 1] >= plan.startBar && times[i] - times[i - 1] !== plan.step) return 'gap'
  }
  return null
}

// ───────────────────────────── 游标与进度线

/** 卷里开盘时刻不晚于 t 的最后一根（最小是 2：图上至少三根） */
export function indexAtOrBefore(times: readonly number[], t: number): number {
  let lo = 0, hi = times.length - 1, ans = -1
  while (lo <= hi) {
    const mid = (lo + hi) >> 1
    if (times[mid] <= t) { ans = mid; lo = mid + 1 } else hi = mid - 1
  }
  return Math.min(Math.max(2, ans), Math.max(2, times.length - 1))
}

/** 卷里开盘时刻不早于 t 的第一根（最小是 2） */
export function indexAtOrAfter(times: readonly number[], t: number): number {
  let lo = 0, hi = times.length - 1, ans = times.length - 1
  while (lo <= hi) {
    const mid = (lo + hi) >> 1
    if (times[mid] >= t) { ans = mid; hi = mid - 1 } else lo = mid + 1
  }
  return Math.max(2, ans)
}

export interface Track { lower: number; upper: number; marks: number[] }

export function makeTrack(times: readonly number[], plan: Plan): Track {
  const at = (t: number) => indexAtOrBefore(times, t)
  const lower = at(plan.startBar), upper = Math.max(lower, at(plan.stopBar))
  const marks = plan.ticks.map(k => at(k.t)).filter((m, i, a) => a.indexOf(m) === i)
  return { lower, upper, marks }
}
export function fractionOf(track: Track, i: number): number {
  if (track.upper <= track.lower) return 1
  return Math.min(1, Math.max(0, (i - track.lower) / (track.upper - track.lower)))
}
export function indexAtFraction(track: Track, f: number): number {
  if (track.upper <= track.lower || !Number.isFinite(f)) return track.upper
  return track.lower + Math.round(Math.min(1, Math.max(0, f)) * (track.upper - track.lower))
}
export const markFractions = (track: Track): number[] =>
  track.marks.filter(m => m >= track.lower && m <= track.upper).map(m => fractionOf(track, m))
/** 拖过（或踩上）一个刻度：出发那根不算 */
export function crossesMark(track: Track, from: number, to: number): boolean {
  if (from === to) return false
  const lo = Math.min(from, to), hi = Math.max(from, to)
  return track.marks.some(m => m !== from && m >= lo && m <= hi)
}
export const clampToTrack = (track: Track, i: number): number => Math.min(track.upper, Math.max(track.lower, i))

/** 打开时游标落在哪：交易回放从开仓前 20 根自己播；重温 / 相似停在判断处 / 相似段末，人自己按播放 */
export const openTime = (plan: Plan): number => (plan.kind === 'trade' ? plan.startBar : plan.initialBar)
export const autoplays = (plan: Plan): boolean => plan.kind === 'trade'
/** 「重播」从哪儿起：交易是开仓前 20 根，重温是圈的那段起点，相似是相似段起点 */
export const restartTime = (plan: Plan): number => (plan.kind === 'note' ? plan.rangeStart : plan.startBar)
/** 回放条最右那颗跳到哪 */
export const keyTime = (plan: Plan): number => (plan.kind === 'trade' ? plan.openBar : plan.kind === 'note' ? plan.judgeBar : plan.initialBar)
export const keyTitle = (plan: Plan): string => (plan.kind === 'trade' ? '开仓处' : plan.kind === 'note' ? '判断处' : '相似段')
/** 播放经过这一根时停 1.2 秒 */
export const pausesAt = (plan: Plan, t: number): boolean => plan.keys.some(k => k.pause && k.t === t)
export const cycleSpeed = (s: number): number => (s >= 4 ? 1 : s * 2)
/** 计划给的倍速落回 1 / 2 / 4 三档 */
export const normalSpeed = (s: unknown): number => (s === 2 || s === 4 ? s : 1)

// ───────────────────────────── 视野

export interface ReplayWindow { to: number; span: number }

/** ReviewReplayViewport.next：reset 或没有视野 → 80 根、右边留 6 根；人还跟着播放头 → 往前推、根宽不动；拖去看别处 → 不动 */
export function nextWindow(current: ReplayWindow | null, prevLast: number | null, lastTime: number, step: number, reset: boolean): ReplayWindow {
  const fallback = { to: lastTime + step * RIGHT_PAD_BARS, span: step * DEFAULT_BARS }
  if (reset || !current || !(current.span > 0) || !Number.isFinite(current.to) || !Number.isFinite(current.span)) return fallback
  if (prevLast == null) return { to: fallback.to, span: current.span }
  if (current.to < prevLast) return current
  return { to: fallback.to, span: current.span }
}

// ───────────────────────────── 页头文字

export function replayTitle(plan: Plan): string {
  return plan.kind === 'trade' ? `回放 · ${plan.symbol} · ${INTERVAL_SHORT[plan.iv as Interval] ?? plan.iv}` : `重温 · ${plan.symbol}`
}

/** 浮动盈亏胶囊：+1.23% / -0.40%（TradeReplayCapsule.text） */
export function capsuleText(v: number): string {
  const pct = Math.round(v * 100 * 100) / 100
  return (pct < 0 ? '-' : '+') + Math.abs(pct).toFixed(2) + '%'
}

const DAY_UP = new Set(['1d', '1w', '1M', '1y'])
/** 游标那根的上海时刻：日线及以上只写日期 */
export function replayTime(ms: number, iv: string): string {
  const d = new Date(ms + 480 * 60_000)
  const p = (n: number) => (n < 10 ? '0' + n : String(n))
  const day = `${d.getUTCFullYear()}-${p(d.getUTCMonth() + 1)}-${p(d.getUTCDate())}`
  return DAY_UP.has(iv) ? day : `${day} ${p(d.getUTCHours())}:${p(d.getUTCMinutes())}`
}

/** 成交的叫法：进场头一笔「开」、之后「加」；离场最后一笔「平」、之前「减」（和详情页成交表同一套） */
export function tradeWord(plan: TradePlan, m: ReplayMark): string {
  const firstEntry = plan.marks.find(x => x.entry)
  let lastExit: ReplayMark | undefined
  for (const x of plan.marks) if (!x.entry) lastExit = x
  return m.entry ? (m === firstEntry ? '开' : '加') : (m === lastExit && plan.closed ? '平' : '减')
}

/** 回放图的副图：交易回放一个不留（这张图只讲这一笔）；重温 / 相似留人的副图，但去掉取实时外部数据的那几种 */
export function replaySubs<T extends string>(subs: readonly T[], kind: Plan['kind']): T[] {
  if (kind === 'trade') return []
  return subs.filter(id => !(EXTERNAL_IDS as readonly string[]).includes(id))
}

// ───────────────────────────── 成交标签的落位（TradeReplayPainter.placeLabel）

export interface Rect { x: number; y: number; w: number; h: number }
const hit = (a: Rect, b: Rect): boolean => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h

/**
 * 按候选的先后挑一个位置：不出图区、不压别的三角与标签；能不压蜡烛最好。
 * 先找「什么都不压」的，找不到再退一步只求不压三角与标签，再找不到就不画这条标签。
 */
export function placeLabel(cands: readonly Rect[], bounds: Rect, taken: readonly Rect[], candles: readonly Rect[]): Rect | null {
  const inside = (r: Rect) => r.x >= bounds.x && r.y >= bounds.y && r.x + r.w <= bounds.x + bounds.w && r.y + r.h <= bounds.y + bounds.h
  const ok = cands.filter(r => inside(r) && !taken.some(t => hit(r, t)))
  return ok.find(r => !candles.some(c => hit(r, c))) ?? ok[0] ?? null
}
