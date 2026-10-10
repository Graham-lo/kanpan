/* Hkline Web · 盘口要点的字（纯函数，测试直接测）
 *
 * 数额 K / M / B / T（≥ 100 不带小数，其余一位、去掉 .0）；负号一律 U+2212；时刻按北京时间。
 * 数值要加粗的地方返回带 <b> 的 HTML 片段（数值已转义），其余是纯文字。
 */
import { HL, fill } from '../terms'
import type { BoardRow, FlowRow, HlEvent, Level, LevelRef, Position, RangeBox, WallState } from './api'

export const MINUS = '−'
const M = 60_000, H = 3_600_000, D = 86_400_000

const esc = (s: string): string => s.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!))
const b = (s: string): string => `<b>${esc(s)}</b>`

function trim1(x: number): string {
  const s = x >= 100 ? Math.round(x).toString() : (Math.round(x * 10) / 10).toFixed(1)
  return s.endsWith('.0') ? s.slice(0, -2) : s
}

/** 35M / 12.4M / 120M / 1.2B；不带正负号 */
export function usd(v: number): string {
  const a = Math.abs(v)
  if (!Number.isFinite(a)) return '—'
  if (a >= 1e12) return trim1(a / 1e12) + 'T'
  if (a >= 1e9) return trim1(a / 1e9) + 'B'
  if (a >= 1e6) return trim1(a / 1e6) + 'M'
  if (a >= 1e3) return trim1(a / 1e3) + 'K'
  return Math.round(a).toString()
}

/** +46M / −8M */
export const signedUsd = (v: number): string => (v < 0 && usd(v) !== '0' ? MINUS : '+') + usd(v)

/** +1.4% / −0.5%（默认一位小数；舍完是 0 不带负号） */
export function signedPct(v: number | null, digits = 1): string {
  if (v == null || !Number.isFinite(v)) return '—'
  const s = Math.abs(v).toFixed(digits)
  const zero = !/[1-9]/.test(s)
  return (v < 0 && !zero ? MINUS : '+') + s + '%'
}

/** 距离：0.4%（不带号，方向由「上方 / 下方」说） */
export const distText = (v: number): string => Math.abs(v).toFixed(Math.abs(v) < 1 ? 2 : 1).replace(/(\.\d)0$/, '$1') + '%'

/** 价位：约五位有效数字、千分位、去尾零（82,279 / 2.446 / 0.011915） */
export function levelPx(p: number): string {
  if (!(p > 0) || !Number.isFinite(p)) return '—'
  const d = Math.max(0, Math.min(10, 4 - Math.floor(Math.log10(p))))
  let s = p.toFixed(d)
  if (s.includes('.')) s = s.replace(/0+$/, '').replace(/\.$/, '')
  const [head, tail] = s.split('.')
  const g = head.replace(/\B(?=(\d{3})+(?!\d))/g, ',')
  return tail ? `${g}.${tail}` : g
}

export const bandPx = (lo: number, hi: number): string => (levelPx(lo) === levelPx(hi) ? levelPx(lo) : `${levelPx(lo)}–${levelPx(hi)}`)

/** 北京时间 HH:MM */
export const hhmm = (ms: number): string => new Date(ms + 8 * H).toISOString().slice(11, 16)

/** 时段：10:20–35（同一小时只写分钟）/ 09:40–10:05 */
export function spanText(from: number, to: number): string {
  const a = hhmm(from), z = hhmm(to)
  if (a === z) return a
  return a.slice(0, 2) === z.slice(0, 2) ? `${a}–${z.slice(3)}` : `${a}–${z}`
}

/** 撑了多久：48 分 / 10 时 / 3 天 */
export function heldText(ms: number): string {
  if (ms < H) return fill(HL.minutes, { n: Math.max(1, Math.round(ms / M)) })
  if (ms < D) return fill(HL.hours, { n: Math.floor(ms / H) })
  return fill(HL.days, { n: Math.floor(ms / D) })
}

/** 多久前：刚刚 / 12 分钟前 / 3 小时前 */
export function agoText(at: number, now: number): string {
  const d = Math.max(0, now - at)
  if (d < M) return HL.justNow
  if (d < H) return fill(HL.minutesAgo, { n: Math.floor(d / M) })
  return fill(HL.hoursAgo, { n: Math.floor(d / H) })
}

export function wallStateWord(s: WallState | null, cancelPct: number | null): string {
  if (s === 'live') return HL.wallLive
  if (s === 'broken') return HL.wallBroken
  if (s === 'reducing') return cancelPct != null ? fill(HL.wallReducingPct, { p: Math.round(cancelPct * 100) + '%' }) : HL.wallReducing
  return ''
}

const REF_WORD: Record<LevelRef, string> = {
  dayHigh: HL.refDayHigh, dayLow: HL.refDayLow, prevDayHigh: HL.refPrevDayHigh, prevDayLow: HL.refPrevDayLow,
  vwap: HL.refVwap, rangeHigh: HL.refRangeHigh, rangeLow: HL.refRangeLow,
}
export const refWord = (r: LevelRef): string => REF_WORD[r]

export const zoneWord = (side: 'bid' | 'ask'): string => (side === 'bid' ? HL.buyZone : HL.sellZone)
export const levelFill = (l: Level): number => l.fillBuyUsd + l.fillSellUsd
export const levelTotal = (l: Level): number => l.wallUsd + levelFill(l) + l.liqUsd

/** 价位一句话（入口条、首页行）：下方 <b>86,120</b> 买区 35M · 挂 48 分 · 测 2 次 */
export function levelSentence(l: Level, opts: { held?: boolean; tests?: boolean } = {}): string {
  const dir = l.distPct < 0 ? HL.below : HL.above
  const amount = l.wallUsd > 0 ? b(usd(l.wallUsd)) : `${HL.fill} ${b(usd(levelFill(l)))}`
  const parts = [`${dir} ${b(levelPx(l.low))} ${zoneWord(l.side)} ${amount}`]
  if (opts.held !== false && l.wallUsd > 0 && l.wallHeldMs > 0) parts.push(fill(HL.heldFor, { d: heldText(l.wallHeldMs) }))
  if (opts.tests !== false && l.tests > 0) parts.push(fill(HL.tests, { n: l.tests }))
  return parts.join(' · ')
}

/** 离现价最近的那条价位 */
export function nearestLevel(levels: readonly Level[]): Level | null {
  let best: Level | null = null
  for (const l of levels) if (!best || Math.abs(l.distPct) < Math.abs(best.distPct)) best = l
  return best
}

/** 事件的时刻列：12:33 / 10:20–35 */
export function eventTime(e: HlEvent): string {
  return 'atMs' in e ? hhmm(e.atMs) : spanText(e.fromMs, e.toMs)
}
/** 事件落在哪一刻（回图对中用）：时段取中点 */
export const eventAt = (e: HlEvent): number => ('atMs' in e ? e.atMs : (e.fromMs + e.toMs) / 2)
export const eventSpan = (e: HlEvent): [number, number] => ('atMs' in e ? [e.atMs, e.atMs] : [e.fromMs, e.toMs])

export type EventIcon = 'wall' | 'liq' | 'trade' | 'oi'
export function eventIcon(e: HlEvent): EventIcon {
  switch (e.t) {
    case 'wallEaten': case 'wallCancel': case 'levelBroken': return 'wall'
    case 'liqWave': return 'liq'
    case 'flowBurst': return 'trade'
    case 'oiJump': return 'oi'
  }
}

/** 事件正文（HTML，数值加粗）：卖墙撤单 <b>19.6M</b> @ 86,880 · 距价 0.05% */
export function eventSentence(e: HlEvent): string {
  const wall = (side: 'buy' | 'sell'): string => (side === 'buy' ? HL.buyWall : HL.sellWall)
  const px = (v: number): string => esc(fill(HL.pricePct, { v: signedPct(v) }))
  switch (e.t) {
    case 'wallEaten':
      return `${esc(fill(HL.wallEaten, { w: wall(e.side) }))} ${b(usd(e.usd))} @ ${esc(levelPx(e.price))}`
    case 'wallCancel':
      return `${esc(fill(HL.wallCancel, { w: wall(e.side) }))} ${b(usd(e.usd))} @ ${esc(levelPx(e.price))} · ${esc(fill(HL.distPrice, { v: distText(e.distPct) }))}`
    case 'flowBurst':
      return `${e.netUsd >= 0 ? HL.takerBuy : HL.takerSell} ${b(signedUsd(e.netUsd))} · ${px(e.pxPct)}`
    case 'liqWave':
      return `${e.side === 'long' ? HL.longLiq : HL.shortLiq} ${b(usd(e.usd))} · ${px(e.pxPct)}`
    case 'oiJump':
      return `${HL.oi5m} ${b(signedPct(e.pct))}`
    case 'levelBroken':
      return `${zoneWord(e.side)} ${esc(bandPx(e.low, e.high))} ${HL.broken}`
  }
}

/** 流向表第一列 */
export function flowLabel(r: FlowRow, now: number): string {
  switch (r.w) {
    case '15m': return HL.w15m
    case '1h': return HL.w1h
    case '4h': return HL.w4h
    case '24h': return HL.w24h
    case 'range': return fill(HL.wRange, { h: r.sinceMs != null ? Math.max(1, Math.round((now - r.sinceMs) / H)) : '—' })
  }
}

/** 费率：0.0450% / −0.0501% */
export function fundingText(rate: number | null): string {
  if (rate == null || !Number.isFinite(rate)) return '—'
  const s = (Math.abs(rate) * 100).toFixed(4)
  const zero = !/[1-9]/.test(s)
  return (rate < 0 && !zero ? MINUS : '') + s + '%'
}

export interface TriCell { label: string; value: string; note: string; pctile: number | null }
export function positionCells(p: Position): TriCell[] {
  const pn = (n: number | null): string => (n == null ? '' : fill(HL.pctile, { n: Math.round(n) }))
  return [
    { label: HL.oi1h, value: signedPct(p.oi.pct1h), note: p.oi.combo ? HL[p.oi.combo] : pn(p.oi.pctile), pctile: p.oi.pctile },
    { label: HL.funding, value: fundingText(p.funding.rate), note: pn(p.funding.pctile), pctile: p.funding.pctile },
    { label: HL.spotPremium, value: signedPct(p.spotPremium.pct, 2), note: pn(p.spotPremium.pctile), pctile: p.spotPremium.pctile },
  ]
}

export function rangeHead(r: RangeBox, now: number): { band: string; hours: number } {
  return { band: bandPx(r.low, r.high), hours: Math.max(1, Math.round((now - r.sinceMs) / H)) }
}

/** 首页行第二行的事实（HTML） */
export function boardFact(r: BoardRow): string {
  const t = r.top
  if (t.kind === 'level') return levelSentence(t, { held: false, tests: false })
  if (t.kind === 'event') return eventSentence(t)
  if (r.cat === 'funding') {
    const n = t.funding.pctile
    return `${HL.funding} ${b(fundingText(t.funding.rate))}${n != null ? ' · ' + esc(fill(HL.pctile, { n: Math.round(n) })) : ''}`
  }
  return `${HL.oi1h} ${b(signedPct(t.oi.pct1h))}${t.oi.combo ? ' · ' + HL[t.oi.combo] : ''}`
}

/** 入口条那一句（HTML）；null = 没有要点，出 16 的抓手。
 *  有价位写离现价最近那条；没有价位但近 4 小时有事件，写「1 时净主动 +46M」；都没有就是抓手 */
export function stripSentence(levels: readonly Level[], events: readonly HlEvent[], flow: readonly FlowRow[] | null): string | null {
  const l = nearestLevel(levels)
  if (l) return levelSentence(l)
  if (!events.length) return null
  const h1 = flow?.find(r => r.w === '1h')?.netUsd
  if (h1 != null) return esc(fill(HL.flowLine, { v: '\u0001' })).replace('\u0001', b(signedUsd(h1)))
  const e = events[0]
  return `${esc(eventTime(e))} ${eventSentence(e)}`
}
