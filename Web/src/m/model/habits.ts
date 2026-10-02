/* 手机网页版 · 「自动适应」（个性化学习）的日志、推断与结论整理
 * 照 iOS Habits/HabitLog.swift、HabitInference.swift、LearnedDefaults.swift、HabitSettingsView.swift（LearnedItems）逐条移植。
 *
 * 行为日志只留在本机（一个档案一份），随账号同步的只有推出来的结论（Prefs.learnedDefaults）。
 * 四条规则：
 *   1. 品种的打开周期：这只品种上各周期的停留秒数按新近加权（半衰期 7 天）累计，取最多的；不到 120 秒不算学到。
 *   2. 类别的价格轴：线性 / 对数的停留同样累计；亲手切一次 = 此前这一类全部依据之和 + 120，立刻压过之前的一切。
 *   3. 板块页今日 / 5 日：每个市场最近 10 次选择里多的那个；不到 3 次、或者打平不算。
 *   4. 自选波动提醒的灵敏度：从 1 起在阶梯上走；响后 15 分钟内点开 → 降一档（更灵敏），连续两次没点开 → 升一档。
 * 时间一律 Unix 秒（和 iOS、服务端的 at 一致）。
 */
import type { LearnedChoice, LearnedDefaults, LearnedFactor } from '../app/prefs'
import { INTERVALS, emptyLearned, LEARNED_MAX_BYTES } from '../app/prefs'

export type HabitKind = 'interval' | 'axisDwell' | 'axisPick' | 'sectorWindow' | 'moveFired' | 'moveOpened'
export const HABIT_KINDS: readonly HabitKind[] = ['interval', 'axisDwell', 'axisPick', 'sectorWindow', 'moveFired', 'moveOpened']
/** 一条：时刻（秒）、种类、键、值、权重（停留秒数；别的种类恒为 1）。空值与权重 1 落盘时不写 */
export interface HabitEvent { t: number; kind: HabitKind; key: string; value?: string; w?: number }

export const H = {
  retention: 30 * 86_400,
  capacity: 2_000,
  coalesceWindow: 3_600,
  halfLife: 7 * 86_400,
  minDwell: 5,
  maxDwell: 30 * 60,
  intervalMinSeconds: 120,
  axisMinSeconds: 120,
  axisPickFloor: 120,
  sectorRecent: 10,
  sectorMinPicks: 3,
  moveOpenWindow: 15 * 60,
  moveIgnoredStreak: 2,
  factorLadder: [0.5, 0.63, 0.8, 1.0, 1.25, 1.6, 2.0] as readonly number[],
  factorStart: 3,
  maxSymbols: 80,
} as const

export const AXIS_VALUES: readonly string[] = ['linear', 'log']
export const SECTOR_VALUES: readonly string[] = ['today', 'd5']
export const CATEGORIES = ['crypto', 'equity', 'metal', 'index', 'other'] as const
export type HabitCategory = typeof CATEGORIES[number]
export const CATEGORY_TITLE: Record<HabitCategory, string> = { crypto: '加密', equity: '美股', metal: '贵金属', index: '指数', other: '其它' }

const val = (e: HabitEvent): string => e.value ?? ''
const weight = (e: HabitEvent): number => e.w ?? 1

// ───────── 日志 ─────────

/** 读盘：形状不对的条目丢掉，按时间排好 */
export function readLog(raw: unknown): HabitEvent[] {
  if (!Array.isArray(raw)) return []
  const out: HabitEvent[] = []
  for (const x of raw) {
    if (!x || typeof x !== 'object') continue
    const r = x as Record<string, unknown>
    if (typeof r.t !== 'number' || !Number.isFinite(r.t) || !HABIT_KINDS.includes(r.kind as HabitKind) || typeof r.key !== 'string') continue
    const e: HabitEvent = { t: r.t, kind: r.kind as HabitKind, key: r.key }
    if (typeof r.value === 'string' && r.value) e.value = r.value
    if (typeof r.w === 'number' && Number.isFinite(r.w) && r.w !== 1) e.w = r.w
    out.push(e)
  }
  return out.sort((a, b) => a.t - b.t)
}

/** 丢掉 30 天以前的；超出上限从最旧的丢（原地改） */
export function pruneLog(log: HabitEvent[], now: number): void {
  const cutoff = now - H.retention
  const first = log.findIndex(e => e.t >= cutoff)
  if (first < 0) log.length = 0
  else if (first > 0) log.splice(0, first)
  if (log.length > H.capacity) log.splice(0, log.length - H.capacity)
}

/** 记一条（原地改）：停留类同一只同一值一小时内再来一段，并进上一条（加秒数、挪时刻） */
export function appendLog(log: HabitEvent[], event: HabitEvent, now: number): void {
  if (event.kind === 'interval' || event.kind === 'axisDwell') {
    let i = -1
    for (let j = log.length - 1; j >= 0; j--) if (log[j].kind === event.kind && log[j].key === event.key) { i = j; break }
    const lastT = log.length ? log[log.length - 1].t : 0
    if (i >= 0 && val(log[i]) === val(event) && event.t >= lastT && event.t - log[i].t < H.coalesceWindow && i >= log.length - 8) {
      const merged = { ...log[i], t: event.t }
      const w = weight(log[i]) + weight(event)
      if (w !== 1) merged.w = w
      else delete merged.w
      log.splice(i, 1)
      log.push(merged)
      pruneLog(log, now)
      return
    }
  }
  const clean: HabitEvent = { t: event.t, kind: event.kind, key: event.key }
  if (event.value) clean.value = event.value
  if (event.w != null && event.w !== 1) clean.w = event.w
  // 时钟被往回拨过：插到该在的位置，保持有序
  if (log.length && event.t < log[log.length - 1].t) {
    const at = log.findIndex(e => e.t > event.t)
    log.splice(at < 0 ? log.length : at, 0, clean)
  } else log.push(clean)
  pruneLog(log, now)
}

// ───────── 推断 ─────────

export const decay = (age: number): number => Math.pow(0.5, Math.max(0, age) / H.halfLife)

class Tally {
  weights = new Map<string, number>()
  counts = new Map<string, number>()
  latest = 0
  picked = false
  get total(): number { let s = 0; this.weights.forEach(v => { s += v }); return s }
  add(value: string, w: number, t: number): void {
    this.weights.set(value, (this.weights.get(value) ?? 0) + w)
    this.counts.set(value, (this.counts.get(value) ?? 0) + 1)
    this.latest = Math.max(this.latest, t)
  }
  /** 最多的那个；打平按值的字面序取小的（和 iOS 的比较器同一个结果） */
  winner(minimum: number): LearnedChoice | null {
    let top: [string, number] | null = null
    for (const [k, v] of this.weights) {
      if (!top || v > top[1] || (v === top[1] && k < top[0])) top = [k, v]
    }
    if (!top || !(top[1] > 0) || !(top[1] >= minimum || this.picked)) return null
    return { v: top[0], n: this.counts.get(top[0]) ?? 0, at: this.latest }
  }
}

function tallyTable(m: Map<string, Tally>, minimum: number): Record<string, LearnedChoice> {
  const out: Record<string, LearnedChoice> = {}
  for (const [k, t] of m) { const w = t.winner(minimum); if (w) out[k] = w }
  return out
}

export function learnIntervals(events: readonly HabitEvent[], now: number): Record<string, LearnedChoice> {
  const m = new Map<string, Tally>()
  for (const e of events) {
    if (e.kind !== 'interval' || !(INTERVALS as readonly string[]).includes(val(e))) continue
    let t = m.get(e.key); if (!t) { t = new Tally(); m.set(e.key, t) }
    t.add(val(e), weight(e) * decay(now - e.t), e.t)
  }
  return tallyTable(m, H.intervalMinSeconds)
}

export function learnPriceAxis(events: readonly HabitEvent[], now: number): Record<string, LearnedChoice> {
  const m = new Map<string, Tally>()
  for (const e of events) {
    if (!AXIS_VALUES.includes(val(e))) continue
    if (e.kind !== 'axisDwell' && e.kind !== 'axisPick') continue
    let t = m.get(e.key); if (!t) { t = new Tally(); m.set(e.key, t) }
    if (e.kind === 'axisDwell') t.add(val(e), weight(e) * decay(now - e.t), e.t)
    else { t.add(val(e), t.total + H.axisPickFloor * decay(now - e.t), e.t); t.picked = true }
  }
  return tallyTable(m, H.axisMinSeconds)
}

export function learnSectorWindow(events: readonly HabitEvent[]): Record<string, LearnedChoice> {
  const picks = new Map<string, HabitEvent[]>()
  for (const e of events) {
    if (e.kind !== 'sectorWindow' || !SECTOR_VALUES.includes(val(e))) continue
    const a = picks.get(e.key) ?? []; a.push(e); picks.set(e.key, a)
  }
  const out: Record<string, LearnedChoice> = {}
  for (const [k, all] of picks) {
    const recent = [...all].sort((a, b) => a.t - b.t).slice(-H.sectorRecent)
    if (recent.length < H.sectorMinPicks) continue
    const counts = new Map<string, number>()
    for (const e of recent) counts.set(val(e), (counts.get(val(e)) ?? 0) + 1)
    const ranked = [...counts].sort((a, b) => b[1] - a[1])
    if (ranked.length > 1 && ranked[1][1] >= ranked[0][1]) continue
    out[k] = { v: ranked[0][0], n: ranked[0][1], at: recent[recent.length - 1].t }
  }
  return out
}

export type MoveOutcome = 'opened' | 'ignored'
/** 每一响的结局，按时间先后；还没满 15 分钟又没点开的那一响不在里面 */
export function moveOutcomes(fires: readonly number[], opens: readonly number[], now: number): { t: number; outcome: MoveOutcome }[] {
  const out: { t: number; outcome: MoveOutcome }[] = []
  for (const f of [...fires].sort((a, b) => a - b)) {
    if (opens.some(o => o >= f && o - f <= H.moveOpenWindow)) out.push({ t: f, outcome: 'opened' })
    else if (now - f >= H.moveOpenWindow) out.push({ t: f, outcome: 'ignored' })
  }
  return out
}
/** 在阶梯上走一遍，返回落在第几档 */
export function moveStep(outcomes: readonly MoveOutcome[]): number {
  let index: number = H.factorStart
  let streak = 0
  for (const o of outcomes) {
    if (o === 'opened') { index = Math.max(0, index - 1); streak = 0 } else {
      streak += 1
      if (streak >= H.moveIgnoredStreak) { index = Math.min(H.factorLadder.length - 1, index + 1); streak = 0 }
    }
  }
  return index
}
export function learnWatchMove(events: readonly HabitEvent[], now: number): Record<string, LearnedFactor> {
  const fires = new Map<string, number[]>()
  const opens = new Map<string, number[]>()
  for (const e of events) {
    const m = e.kind === 'moveFired' ? fires : e.kind === 'moveOpened' ? opens : null
    if (!m) continue
    const a = m.get(e.key) ?? []; a.push(e.t); m.set(e.key, a)
  }
  const out: Record<string, LearnedFactor> = {}
  for (const [k, times] of fires) {
    const resolved = moveOutcomes(times, opens.get(k) ?? [], now)
    if (!resolved.length) continue
    out[k] = { v: H.factorLadder[moveStep(resolved.map(r => r.outcome))], n: resolved.length, at: resolved[resolved.length - 1].t }
  }
  return out
}

/** 整份结论：只含日志里有依据的键 */
export function learn(log: readonly HabitEvent[], now: number): LearnedDefaults {
  const events = log.filter(e => e.t >= now - H.retention)
  return { intervals: learnIntervals(events, now), priceAxis: learnPriceAxis(events, now), sectorWindow: learnSectorWindow(events), watchMove: learnWatchMove(events, now) }
}

// ───────── 结论整理 ─────────

function newest<V extends { at: number }>(table: Record<string, V>, keep: number): Record<string, V> {
  const entries = Object.entries(table)
  if (entries.length <= keep) return table
  entries.sort((a, b) => a[1].at !== b[1].at ? b[1].at - a[1].at : a[0] < b[0] ? -1 : 1)
  return Object.fromEntries(entries.slice(0, keep))
}
const encodedSize = (l: LearnedDefaults): number => {
  const o: Record<string, unknown> = {}
  for (const k of ['intervals', 'priceAxis', 'sectorWindow', 'watchMove'] as const) if (Object.keys(l[k]).length) o[k] = l[k]
  return new TextEncoder().encode(JSON.stringify(o)).length
}
/** 30 天没新依据的丢掉；按品种的两张表各留最新 80 只；编码后超 16 KB 从最旧的品种条目开始丢 */
export function prunedLearned(l: LearnedDefaults, now: number): LearnedDefaults {
  const cutoff = now - H.retention
  const fresh = <V extends { at: number }>(t: Record<string, V>): Record<string, V> => Object.fromEntries(Object.entries(t).filter(e => e[1].at >= cutoff))
  const out: LearnedDefaults = {
    intervals: newest(fresh(l.intervals), H.maxSymbols),
    priceAxis: fresh(l.priceAxis),
    sectorWindow: fresh(l.sectorWindow),
    watchMove: newest(fresh(l.watchMove), H.maxSymbols),
  }
  while (encodedSize(out) > LEARNED_MAX_BYTES) {
    const oi = Object.entries(out.intervals).sort((a, b) => a[1].at - b[1].at)[0]
    const om = Object.entries(out.watchMove).sort((a, b) => a[1].at - b[1].at)[0]
    if (oi && om) { if (oi[1].at <= om[1].at) delete out.intervals[oi[0]]; else delete out.watchMove[om[0]] } else if (oi) delete out.intervals[oi[0]]
    else if (om) delete out.watchMove[om[0]]
    else break
  }
  return out
}
/** 本机推出来的并到同步来的那份上：同一个键谁的 at 新用谁（一样新用本机的）；只在一边有的照留 */
export function mergedLearned(synced: LearnedDefaults, local: LearnedDefaults, now: number): LearnedDefaults {
  const pick = <V extends { at: number }>(a: Record<string, V>, b: Record<string, V>): Record<string, V> => {
    const out = { ...a }
    for (const [k, v] of Object.entries(b)) if (!out[k] || v.at >= out[k].at) out[k] = v
    return out
  }
  return prunedLearned({
    intervals: pick(synced.intervals, local.intervals),
    priceAxis: pick(synced.priceAxis, local.priceAxis),
    sectorWindow: pick(synced.sectorWindow, local.sectorWindow),
    watchMove: pick(synced.watchMove, local.watchMove),
  }, now)
}
export const learnedEmpty = (l: LearnedDefaults): boolean =>
  !Object.keys(l.intervals).length && !Object.keys(l.priceAxis).length && !Object.keys(l.sectorWindow).length && !Object.keys(l.watchMove).length
export { emptyLearned }

// ───────── 「已学到的」那页的行 ─────────

const IV_SHORT: Record<string, string> = {
  '1m': '1分', '3m': '3分', '5m': '5分', '15m': '15分', '30m': '30分', '1h': '1时', '2h': '2时', '4h': '4时',
  '6h': '6时', '12h': '12时', '1d': '1日', '1w': '1周', '1M': '1月', '1y': '1年',
}
/** iOS Alert.name(of:)：规范键 / 代号 → 「BTC」；带「-」的（现货对）原样 */
export function habitName(key: string, baseOf: (s: string) => string): string {
  const sym = key.includes('/') ? key.slice(key.lastIndexOf('/') + 1) : key
  return sym.includes('-') ? sym.replace('-', '/') : baseOf(sym)
}
export interface LearnedRow { id: string; name: string; value: string; count: number }
export interface LearnedGroup { title: string; rows: LearnedRow[] }
export function learnedGroups(l: LearnedDefaults, baseOf: (s: string) => string): LearnedGroup[] {
  const sorted = <V extends { at: number }>(t: Record<string, V>): [string, V][] =>
    Object.entries(t).sort((a, b) => a[1].at !== b[1].at ? b[1].at - a[1].at : a[0] < b[0] ? -1 : 1)
  const intervals = sorted(l.intervals).filter(([, c]) => IV_SHORT[c.v]).map(([k, c]) => ({ id: 'interval.' + k, name: habitName(k, baseOf), value: IV_SHORT[c.v], count: c.n }))
  const axis = CATEGORIES.flatMap(cat => {
    const c = l.priceAxis[cat]
    return c && AXIS_VALUES.includes(c.v) ? [{ id: 'axis.' + cat, name: CATEGORY_TITLE[cat], value: c.v === 'log' ? '对数' : '线性', count: c.n }] : []
  })
  const sector = (['crypto', 'us'] as const).flatMap(m => {
    const c = l.sectorWindow[m]
    return c && SECTOR_VALUES.includes(c.v) ? [{ id: 'sector.' + m, name: m === 'crypto' ? '加密' : '美股', value: c.v === 'd5' ? '5 日' : '今日', count: c.n }] : []
  })
  // 倍数回到 1 的不列：那就是没调
  const moves = sorted(l.watchMove).filter(([, f]) => Math.abs(f.v - 1) > 0.001).map(([k, f]) => ({ id: 'move.' + k, name: habitName(k, baseOf), value: f.v < 1 ? '更灵敏' : '更迟钝', count: f.n }))
  return ([['周期', intervals], ['价格轴', axis], ['板块', sector], ['波动提醒', moves]] as [string, LearnedRow[]][])
    .filter(([, rows]) => rows.length).map(([title, rows]) => ({ title, rows }))
}
export const learnedCount = (l: LearnedDefaults, baseOf: (s: string) => string): number =>
  learnedGroups(l, baseOf).reduce((s, g) => s + g.rows.length, 0)
