/* Hkline Web · 盘口要点（要点引擎）的接口与解析
 *
 * 服务端：kanpan-api 的 /v1/market/orderflow/highlights（单只）与 /highlights/board（首页跨品种排行），
 * 另有全市场榜单 /v1/market/board?kind=oi|gainers|losers&window=1h|4h|24h。口径见 PROJECT.md §79 与
 * docs/原型-手机首页异动与盘口要点-2026-10-10.html §11–12。
 * 解析宽进严出：缺字段的条目整条丢掉，不拿 0 补；数值一律有限数，金额非负。
 */
import { getJSON } from '../orderflow/feed'

export type FlowWindow = '15m' | '1h' | '4h' | 'range' | '24h'
export interface FlowRow { w: FlowWindow; netUsd: number | null; pxPct: number | null; oiPct: number | null; diverge: boolean; sinceMs: number | null }
export interface RangeBox { low: number; high: number; sinceMs: number; lowFillUsd: number; lowTests: number; highFillUsd: number; highTests: number }
export type LevelRef = 'dayHigh' | 'dayLow' | 'prevDayHigh' | 'prevDayLow' | 'vwap' | 'rangeHigh' | 'rangeLow'
export type WallState = 'live' | 'reducing' | 'broken'
export interface Level {
  id: string; low: number; high: number; side: 'bid' | 'ask'; distPct: number
  wallUsd: number; wallHeldMs: number; wallState: WallState | null
  /** 撤了多少（0…1）；服务端目前不给，给了就用 */
  cancelPct: number | null
  fillBuyUsd: number; fillSellUsd: number; liqUsd: number; tests: number
  touchMs: [number | null, number | null]; refs: LevelRef[]
}
export type OiCombo = 'oiUpPxUp' | 'oiDownPxUp' | 'oiUpPxDown' | 'oiDownPxDown'
export interface Position {
  show: boolean
  oi: { pct1h: number | null; combo: OiCombo | null; pctile: number | null }
  funding: { rate: number | null; pctile: number | null }
  spotPremium: { pct: number | null; pctile: number | null }
}
export type HlEvent =
  | { id: string; t: 'wallEaten' | 'wallCancel'; atMs: number; price: number; usd: number; side: 'buy' | 'sell'; distPct: number }
  | { id: string; t: 'flowBurst'; fromMs: number; toMs: number; netUsd: number; pxPct: number }
  | { id: string; t: 'liqWave'; fromMs: number; toMs: number; usd: number; side: 'long' | 'short'; pxPct: number }
  | { id: string; t: 'oiJump'; atMs: number; pct: number }
  | { id: string; t: 'levelBroken'; atMs: number; low: number; high: number; side: 'bid' | 'ask'; distPct: number }

export interface Highlights {
  base: string; generatedAtMs: number; tracked: boolean; staleMs: number | null
  /** 服务端从什么时候开始盯这只（第一次有人打开时补齐流向与持仓，价位与事件要攒一会）；partial = 还在补 */
  observingSinceMs: number | null; partial: boolean
  flow: FlowRow[] | null; range: RangeBox | null; levels: Level[]; position: Position | null; events: HlEvent[]
}

export type BoardCat = 'book' | 'oi' | 'funding' | 'move'
/** 波动（急涨 / 急跌）：1 分或 5 分窗里的涨跌幅与成交额；服务端行上没有 top，字段平铺在行上 */
export interface Move { dir: 'up' | 'down'; window: '1m' | '5m'; pct: number; volUsd: number | null }
export type BoardTop = ({ kind: 'level' } & Level) | ({ kind: 'event' } & HlEvent) | ({ kind: 'position' } & Position) | ({ kind: 'move' } & Move)
/** key：列表里认行的键——盘口 / 持仓 / 费率按币名（同一只换了类也在原位），波动单独一份（同一只可以既有盘口又有波动） */
export interface BoardRow { key: string; atMs: number; base: string; cat: BoardCat; changePct: number | null; count: number; favorite: boolean; price: number | null; tier: 1 | 2 | 3; top: BoardTop }
export interface Board { generatedAtMs: number; rows: BoardRow[] }

export type MarketKind = 'oi' | 'oidown' | 'gainers' | 'losers'
export type MarketWindow = '1h' | '4h' | '24h'
export interface MarketRow { base: string; changePct: number; oiUsd: number | null; price: number | null }
export interface MarketBoard { generatedAtMs: number; rows: MarketRow[] }

// ───────────────────────────── 解析

type Obj = Record<string, unknown>
const obj = (v: unknown): v is Obj => !!v && typeof v === 'object' && !Array.isArray(v)
const num = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v)
const numOr = (v: unknown): number | null => (num(v) ? v : null)
const amt = (v: unknown): number => (num(v) && v > 0 ? v : 0)
const str = (v: unknown): v is string => typeof v === 'string' && v.length > 0

const WINDOWS: readonly FlowWindow[] = ['15m', '1h', '4h', 'range', '24h']
const REFS: readonly LevelRef[] = ['dayHigh', 'dayLow', 'prevDayHigh', 'prevDayLow', 'vwap', 'rangeHigh', 'rangeLow']
const COMBOS: readonly OiCombo[] = ['oiUpPxUp', 'oiDownPxUp', 'oiUpPxDown', 'oiDownPxDown']

function parseFlowRow(v: unknown): FlowRow | null {
  if (!obj(v) || !WINDOWS.includes(v.w as FlowWindow)) return null
  return { w: v.w as FlowWindow, netUsd: numOr(v.netUsd), pxPct: numOr(v.pxPct), oiPct: numOr(v.oiPct), diverge: v.diverge === true, sinceMs: numOr(v.sinceMs) }
}

function parseRange(v: unknown): RangeBox | null {
  if (!obj(v) || !num(v.low) || !num(v.high) || !num(v.sinceMs) || !(v.low > 0) || v.high < v.low) return null
  return { low: v.low, high: v.high, sinceMs: v.sinceMs, lowFillUsd: amt(v.lowFillUsd), lowTests: amt(v.lowTests), highFillUsd: amt(v.highFillUsd), highTests: amt(v.highTests) }
}

export function parseLevel(v: unknown): Level | null {
  if (!obj(v) || !str(v.id) || !num(v.low) || !num(v.high) || !(v.low > 0) || v.high < v.low) return null
  if (v.side !== 'bid' && v.side !== 'ask') return null
  const ws = v.wallState
  const touch = Array.isArray(v.touchMs) ? v.touchMs : []
  const cancel = numOr(v.cancelPct)
  return {
    id: v.id, low: v.low, high: v.high, side: v.side, distPct: num(v.distPct) ? v.distPct : 0,
    wallUsd: amt(v.wallUsd), wallHeldMs: amt(v.wallHeldMs),
    wallState: ws === 'live' || ws === 'reducing' || ws === 'broken' ? ws : null,
    cancelPct: cancel != null && cancel >= 0 && cancel <= 1 ? cancel : null,
    fillBuyUsd: amt(v.fillBuyUsd), fillSellUsd: amt(v.fillSellUsd), liqUsd: amt(v.liqUsd), tests: Math.round(amt(v.tests)),
    touchMs: [numOr(touch[0]), numOr(touch[1])],
    refs: Array.isArray(v.refs) ? v.refs.filter((r): r is LevelRef => REFS.includes(r as LevelRef)) : [],
  }
}

export function parsePosition(v: unknown): Position | null {
  if (!obj(v)) return null
  const oi = obj(v.oi) ? v.oi : {}, fr = obj(v.funding) ? v.funding : {}, sp = obj(v.spotPremium) ? v.spotPremium : {}
  return {
    show: v.show === true,
    oi: { pct1h: numOr(oi.pct1h), combo: COMBOS.includes(oi.combo as OiCombo) ? oi.combo as OiCombo : null, pctile: numOr(oi.pctile) },
    funding: { rate: numOr(fr.rate), pctile: numOr(fr.pctile) },
    spotPremium: { pct: numOr(sp.pct), pctile: numOr(sp.pctile) },
  }
}

export function parseEvent(v: unknown): HlEvent | null {
  if (!obj(v) || !str(v.id)) return null
  const id = v.id
  switch (v.t) {
    case 'wallEaten': case 'wallCancel':
      if (!num(v.atMs) || !num(v.price) || !(v.price > 0) || (v.side !== 'buy' && v.side !== 'sell')) return null
      return { id, t: v.t, atMs: v.atMs, price: v.price, usd: amt(v.usd), side: v.side, distPct: num(v.distPct) ? v.distPct : 0 }
    case 'flowBurst':
      if (!num(v.fromMs) || !num(v.toMs) || !num(v.netUsd)) return null
      return { id, t: 'flowBurst', fromMs: v.fromMs, toMs: Math.max(v.fromMs, v.toMs), netUsd: v.netUsd, pxPct: num(v.pxPct) ? v.pxPct : 0 }
    case 'liqWave':
      if (!num(v.fromMs) || !num(v.toMs) || (v.side !== 'long' && v.side !== 'short')) return null
      return { id, t: 'liqWave', fromMs: v.fromMs, toMs: Math.max(v.fromMs, v.toMs), usd: amt(v.usd), side: v.side, pxPct: num(v.pxPct) ? v.pxPct : 0 }
    case 'oiJump':
      if (!num(v.atMs) || !num(v.pct)) return null
      return { id, t: 'oiJump', atMs: v.atMs, pct: v.pct }
    case 'levelBroken':
      if (!num(v.atMs) || !num(v.low) || !num(v.high) || (v.side !== 'bid' && v.side !== 'ask')) return null
      return { id, t: 'levelBroken', atMs: v.atMs, low: v.low, high: Math.max(v.low, v.high), side: v.side, distPct: num(v.distPct) ? v.distPct : 0 }
    default: return null
  }
}

/** 事件的末刻：时段取结束，单点取那一刻（列表按它倒序） */
const endOf = (e: HlEvent): number => ('atMs' in e ? e.atMs : e.toMs)

const list = <T>(v: unknown, f: (x: unknown) => T | null): T[] => (Array.isArray(v) ? v.map(f).filter((x): x is T => x != null) : [])

export function parseHighlights(raw: unknown, base: string): Highlights | null {
  if (!obj(raw) || raw.base !== base || !num(raw.generatedAtMs) || typeof raw.tracked !== 'boolean') return null
  const flow = obj(raw.flow) && Array.isArray(raw.flow.rows) ? list(raw.flow.rows, parseFlowRow) : null
  return {
    base, generatedAtMs: raw.generatedAtMs, tracked: raw.tracked, staleMs: numOr(raw.staleMs),
    observingSinceMs: num(raw.observingSinceMs) && raw.observingSinceMs > 0 ? raw.observingSinceMs : null, partial: raw.partial === true,
    flow: flow && flow.length ? flow : null,
    range: parseRange(raw.range),
    levels: list(raw.levels, parseLevel).sort((a, b) => b.low - a.low),
    position: parsePosition(raw.position),
    events: list(raw.events, parseEvent).sort((a, b) => endOf(b) - endOf(a)),
  }
}

function parseTop(v: unknown): BoardTop | null {
  if (!obj(v)) return null
  if (v.kind === 'level') { const l = parseLevel(v); return l ? { kind: 'level', ...l } : null }
  if (v.kind === 'event') { const e = parseEvent(v); return e ? { kind: 'event', ...e } : null }
  if (v.kind === 'position') { const p = parsePosition(v); return p ? { kind: 'position', ...p } : null }
  return null
}

/** 波动行：{ kind:"moveUp"|"moveDown", window:"1m"|"5m", pct, volUsd }；缺一样认不出就整行不要 */
export function parseMove(r: Record<string, unknown>): ({ kind: 'move' } & Move) | null {
  const dir = r.kind === 'moveUp' ? 'up' : r.kind === 'moveDown' ? 'down' : null
  const window = r.window === '1m' || r.window === '5m' ? r.window : null
  if (!dir || !window || !num(r.pct)) return null
  return { kind: 'move', dir, window, pct: r.pct, volUsd: num(r.volUsd) && r.volUsd > 0 ? r.volUsd : null }
}

export function parseBoard(raw: unknown): Board | null {
  if (!obj(raw) || !num(raw.generatedAtMs) || !Array.isArray(raw.rows)) return null
  const rows: BoardRow[] = []
  const seen = new Set<string>()
  for (const r of raw.rows) {
    if (!obj(r) || !str(r.base)) continue
    if (r.cat !== 'book' && r.cat !== 'oi' && r.cat !== 'funding' && r.cat !== 'move') continue
    const key = r.cat === 'move' ? `move:${r.base}` : r.base
    if (seen.has(key)) continue
    const top = r.cat === 'move' ? parseMove(r) : parseTop(r.top)
    if (!top) continue
    seen.add(key)
    const tier = num(r.tier) ? Math.max(1, Math.min(3, Math.round(r.tier))) as 1 | 2 | 3 : 1
    rows.push({
      key, atMs: num(r.atMs) ? r.atMs : raw.generatedAtMs, base: r.base, cat: r.cat, changePct: numOr(r.changePct),
      count: Math.max(1, Math.round(amt(r.count))), favorite: r.favorite === true, price: num(r.price) && r.price > 0 ? r.price : null, tier, top,
    })
  }
  return { generatedAtMs: raw.generatedAtMs, rows }
}

export function parseMarketBoard(raw: unknown): MarketBoard | null {
  if (!obj(raw) || !num(raw.generatedAtMs) || !Array.isArray(raw.rows)) return null
  const rows: MarketRow[] = []
  for (const r of raw.rows) {
    if (!obj(r) || !str(r.base) || !num(r.changePct)) continue
    rows.push({ base: r.base, changePct: r.changePct, oiUsd: num(r.oiUsd) && r.oiUsd > 0 ? r.oiUsd : null, price: num(r.price) && r.price > 0 ? r.price : null })
  }
  return { generatedAtMs: raw.generatedAtMs, rows }
}

// ───────────────────────────── 取数

export type Fetched<T> = { ok: true; data: T } | { ok: false; status: number }
const TIMEOUT = 8_000

async function fetchParsed<T>(url: string, parse: (b: unknown) => T | null): Promise<Fetched<T>> {
  try {
    const r = await getJSON(url, TIMEOUT)
    const data = r.status === 200 ? parse(r.body) : null
    return data ? { ok: true, data } : { ok: false, status: r.status }
  } catch {
    return { ok: false, status: 0 }
  }
}

export const highlightsUrl = (base: string): string => `/v1/market/orderflow/highlights?base=${encodeURIComponent(base)}`
export const boardUrl = (bases: readonly string[]): string =>
  bases.length ? `/v1/market/orderflow/highlights/board?bases=${bases.map(encodeURIComponent).join(',')}` : '/v1/market/orderflow/highlights/board'
export const marketBoardUrl = (kind: MarketKind, w: MarketWindow): string => `/v1/market/board?kind=${kind}&window=${w}`

export const fetchHighlights = (base: string): Promise<Fetched<Highlights>> => fetchParsed(highlightsUrl(base), b => parseHighlights(b, base))
export const fetchBoard = (bases: readonly string[]): Promise<Fetched<Board>> => fetchParsed(boardUrl(bases), parseBoard)
export const fetchMarketBoard = (kind: MarketKind, w: MarketWindow): Promise<Fetched<MarketBoard>> => fetchParsed(marketBoardUrl(kind, w), parseMarketBoard)
