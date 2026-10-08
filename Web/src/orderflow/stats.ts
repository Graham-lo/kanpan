/* Hkline Web · 主力订单流 · 侧栏「24 小时流动性」「24 小时成交」与「每秒成交」（OpenMarket 通读 P1-4）
 *
 * 流动性：中间价 ±2.5% 以内的买、卖挂单名义，30 分钟一个点，最多 48 个点。
 *   · 历史从服务端深度快照补（一次要 24 小时、30 分钟一格、价格按这 24 小时的高低收窄），之后每 5 分钟只补最后两格；
 *     服务端没跟的品种回空，就只有打开这页之后的实时点（每 5 秒一次，同一格里取平均）。不造数据。
 *   · 每一格的「中间价」用参考家 30 分钟 K 线的 (高 + 低 + 收) ÷ 3；取不到就用这一格买卖的分界。
 * 成交：各家登记的 30 分钟 K 线（src/venues 的 klines30m）。K 线带主动买额的（takerSplit）拆出买、卖，其余只计总额。
 * 每秒成交：各家逐笔进来的笔数，最近 10 秒的平均，外加最近两分钟的小折线。
 * 金额一律美元名义（K 线的计价额；没有计价额的用成交量 × 收盘价）。
 */
import { EXCHANGE_CH, EXCHANGE_COUNT, midRank, venueAdapter, type DepthBook, type Kline } from '../venues'
import type { FineBook } from './aggregate'
import type { Thresholds } from './types'
import { getJSON } from './feed'
import { heatFetch, scopedHeatUrl, parseHeatSplit, colSum, type SplitCol } from './heatFetch'
import { snapFine, niceCeil } from './depthDelta'
import { ago } from '../util/clock'

export const SLOT_MS = 1_800_000
export const SLOTS = 48
export const LIQ_BAND = 0.025
const LIVE_EVERY_MS = 5_000
const LIQ_REFRESH_MS = 300_000
const VOL_REFRESH_MS = 60_000
const RETRY_MS = 30_000

export const slotOf = (t: number): number => Math.floor(t / SLOT_MS) * SLOT_MS

// ------------------------------------------------------------------ K 线（各家 30 分钟，请求与解析在 src/venues）

export type { Kline }
/** 一格：total 各家合计；buy / sell 是 K 线带主动买的那几家拆出的买、卖；ex[i] 是第 i 家（EXCHANGE_CH）的总额 */
export interface VolSlot { t: number; total: number; buy: number; sell: number; ex: number[] }

/** 几家的 K 线并成 48 格：带主动买的家拆买卖，其余只计总额。 */
export function mergeVol(src: { exchange: string; k: Kline[] }[], now: number): VolSlot[] {
  const first = slotOf(now) - (SLOTS - 1) * SLOT_MS
  const slots: VolSlot[] = []
  for (let i = 0; i < SLOTS; i++) slots.push({ t: first + i * SLOT_MS, total: 0, buy: 0, sell: 0, ex: new Array<number>(EXCHANGE_COUNT).fill(0) })
  for (const s of src) {
    const split = venueAdapter(s.exchange)?.takerSplit === true
    const ch = EXCHANGE_CH[s.exchange]
    for (const k of s.k) {
      const i = Math.round((slotOf(k.t) - first) / SLOT_MS)
      if (i < 0 || i >= SLOTS) continue
      const x = slots[i]
      x.total += k.quote
      if (ch != null) x.ex[ch] += k.quote
      if (split) { const b = k.buy ?? 0; x.buy += b; x.sell += Math.max(0, k.quote - b) }
    }
  }
  return slots
}

interface KlineReq { exchange: string; product: string; url: string; parse: (b: unknown) => Kline[] }

/** 这只品种各家 30 分钟 K 线的请求（各家登记的；只要现货与 U 本位永续，币本位、交割是张数计价，不并） */
export function klineRequests(books: DepthBook[], now: number): KlineReq[] {
  const out: KlineReq[] = []
  const seen = new Set<string>()
  for (const b of books) {
    const v = b.venue, key = `${v.exchange}|${v.product}|${v.instrument}`
    if (seen.has(key) || (v.product !== 'spot' && v.product !== 'usdtPerp')) continue
    seen.add(key)
    const r = venueAdapter(v.exchange)?.klines30m?.(b, now, SLOTS)
    if (r) out.push({ exchange: v.exchange, product: v.product, url: r.url, parse: r.parse })
  }
  return out
}

type Status = 'idle' | 'loading' | 'ok' | 'down'

/** 24 小时成交：每分钟刷一次各家 K 线。 */
export class VolSource {
  slots: VolSlot[] = []
  /** 各家各产品的 K 线（流动性用参考家的算每格中间价） */
  raw: { exchange: string; product: string; k: Kline[] }[] = []
  status: Status = 'idle'
  /** 这次并进来的有哪几家 */
  exchanges: string[] = []
  version = 0
  private at = 0
  private busy = false
  private gen = 0

  ensure(books: DepthBook[], now: number): void {
    if (this.busy || !books.length || ago(this.at, now) < (this.status === 'down' ? RETRY_MS : VOL_REFRESH_MS)) return
    const reqs = klineRequests(books, now)
    if (!reqs.length) return
    this.busy = true; this.at = now
    if (this.status === 'idle') this.status = 'loading'
    const gen = this.gen
    void Promise.all(reqs.map(r => getJSON(r.url, 10_000).then(x => (x.status === 200 ? { exchange: r.exchange, product: r.product, k: r.parse(x.body) } : null), () => null)))
      .then(res => {
        if (gen !== this.gen) return
        const ok = res.filter((x): x is { exchange: string; product: string; k: Kline[] } => !!x && x.k.length > 0)
        if (!ok.length) { this.status = 'down'; return }
        this.raw = ok
        this.exchanges = [...new Set(ok.map(x => x.exchange))]
        this.slots = mergeVol(ok, Date.now())
        this.status = 'ok'
        this.version++
      })
      .finally(() => { if (gen === this.gen) this.busy = false })
  }

  /** 每一格的参考中间价（图上的单位）：按注册表顺序，同一家永续在前、现货在后；(高 + 低 + 收) ÷ 3 */
  mids(): Map<number, number> {
    const src = [...this.raw].sort((a, b) => midRank(a.exchange, a.product) - midRank(b.exchange, b.product))
    const m = new Map<number, number>()
    for (const s of src) for (const k of s.k) { const t = slotOf(k.t); if (!m.has(t) && k.h > 0 && k.l > 0) m.set(t, (k.h + k.l + k.c) / 3) }
    return m
  }

  reset(): void { this.slots = []; this.raw = []; this.status = 'idle'; this.exchanges = []; this.at = 0; this.busy = false; this.gen++; this.version++ }
}

// ------------------------------------------------------------------ 24 小时流动性

export interface LiqPoint { t: number; bid: number; ask: number; src: 'server' | 'live' }

/** 一列（服务端 30 分钟均值）在中间价 m ±2.5% 以内的买卖；m 缺就用这一列买卖的分界。 */
export function liqOfCol(c: SplitCol, m: number | undefined): [number, number] | null {
  let mid = m
  if (!(mid && mid > 0)) {
    let topBid = -Infinity, lowAsk = Infinity
    for (let i = 0; i < c.n; i++) {
      if (c.bid[i] > 0) topBid = Math.max(topBid, (c.lo + i + 1) * c.step)
      if (c.ask[i] > 0 && lowAsk === Infinity) lowAsk = (c.lo + i) * c.step
    }
    if (!Number.isFinite(topBid) || !Number.isFinite(lowAsk)) return null
    mid = (topBid + lowAsk) / 2
  }
  return colSum(c, mid * (1 - LIQ_BAND), mid * (1 + LIQ_BAND))
}

/** 服务端的点优先，没有的格用实时点补；按时间排好，最多 48 个。 */
export function mergeLiq(srv: Map<number, [number, number]>, live: Map<number, { bid: number; ask: number; n: number }>, now: number): LiqPoint[] {
  const first = slotOf(now) - (SLOTS - 1) * SLOT_MS
  const out: LiqPoint[] = []
  for (let t = first; t <= slotOf(now); t += SLOT_MS) {
    const s = srv.get(t)
    if (s) { out.push({ t, bid: s[0], ask: s[1], src: 'server' }); continue }
    const l = live.get(t)
    if (l && l.n > 0) out.push({ t, bid: l.bid / l.n, ask: l.ask / l.n, src: 'live' })
  }
  return out
}

export class LiqSource {
  srv = new Map<number, [number, number]>()
  live = new Map<number, { bid: number; ask: number; n: number }>()
  status: 'idle' | 'loading' | 'ok' | 'empty' | 'down' = 'idle'
  /** 最近一次实时取样的买 / 卖（标题行显示「现在」） */
  now: [number, number] | null = null
  version = 0
  private range: { lo: number; hi: number; step: number } | null = null
  private at = 0
  private liveAt = 0
  private full = false
  private busy = false
  private gen = 0

  /** 每帧调：每 5 秒记一个实时点（中间价 ±2.5%，过滤口径与服务端一致）。 */
  sample(fine: FineBook, thresholds: Thresholds, now: number): void {
    if (ago(this.liveAt, now) < LIVE_EVERY_MS || fine.mid == null) return
    const col = snapFine(fine, thresholds, now, 0, LIQ_BAND * 1.2)
    if (!col) return
    this.liveAt = now
    const [b, a] = colSum(col, fine.mid * (1 - LIQ_BAND), fine.mid * (1 + LIQ_BAND))
    this.now = [b, a]
    const t = slotOf(now)
    const e = this.live.get(t)
    if (e) { e.bid += b; e.ask += a; e.n++ } else this.live.set(t, { bid: b, ask: a, n: 1 })
    for (const k of this.live.keys()) if (k < t - SLOTS * SLOT_MS) this.live.delete(k)
    this.version++
  }

  /**
   * 向服务端补：头一次要 24 小时（30 分钟一格、价格按 24 小时高低 ±2.5% 收窄），之后每 5 分钟只补最后两格。
   * mids 是每格参考中间价（币安 K 线），还没到手时先等它（最多等到 K 线失败，那时按现价 ±15% 要）。
   */
  ensure(base: string, chartScale: number, fineStep: number, mid: number | null, mids: Map<number, number>, klinesDone: boolean, now: number): void {
    if (this.busy || !(fineStep > 0) || mid == null) return
    if (ago(this.at, now) < (this.status === 'down' ? RETRY_MS : this.full ? LIQ_REFRESH_MS : 0)) return
    if (!this.full && !mids.size && !klinesDone) return
    let lo: number, hi: number
    if (!this.range || mid < this.range.lo / (1 - LIQ_BAND) || mid > this.range.hi / (1 + LIQ_BAND)) {
      const vs = [...mids.values(), mid]
      lo = Math.min(...vs) * (1 - LIQ_BAND) * (mids.size ? 1 : 0.87)
      hi = Math.max(...vs) * (1 + LIQ_BAND) * (mids.size ? 1 : 1.13)
      // 价格格数 × 49 列不超过约 1.2 万行
      const step = fineStep * niceCeil((hi - lo) * (SLOTS + 1) / 12_000 / fineStep)
      this.range = { lo, hi, step }
    }
    const r = this.range
    const from = this.full ? slotOf(now) - SLOT_MS : slotOf(now) - (SLOTS - 1) * SLOT_MS
    const url = scopedHeatUrl(base, from, now, r.step, r.lo, r.hi, SLOT_MS, chartScale, 300_000)
    this.busy = true; this.at = now
    if (this.status === 'idle') this.status = 'loading'
    const gen = this.gen
    heatFetch(url, 60_000).then(res => {
      if (gen !== this.gen) return
      const h = res.status === 200 ? parseHeatSplit(res.body, chartScale, r.step) : null
      if (!h) { this.status = 'down'; return }
      for (const c of h.cols) {
        const t = slotOf(c.t)
        const v = liqOfCol(c, mids.get(t) ?? (t === slotOf(now) ? mid : undefined))
        if (v) this.srv.set(t, v)
      }
      for (const k of this.srv.keys()) if (k < slotOf(now) - SLOTS * SLOT_MS) this.srv.delete(k)
      this.full = true
      this.status = this.srv.size ? 'ok' : 'empty'
      this.version++
    }, () => { if (gen === this.gen) this.status = 'down' })
      .finally(() => { if (gen === this.gen) this.busy = false })
  }

  points(now: number): LiqPoint[] { return mergeLiq(this.srv, this.live, now) }

  reset(): void { this.srv.clear(); this.live.clear(); this.now = null; this.status = 'idle'; this.range = null; this.at = 0; this.liveAt = 0; this.full = false; this.busy = false; this.gen++; this.version++ }
}

// ------------------------------------------------------------------ 每秒成交

export class TpsMeter {
  static readonly SPAN = 120
  private counts = new Float64Array(TpsMeter.SPAN)
  private sec = 0
  private started = 0

  add(now: number, n = 1): void {
    const s = Math.floor(now / 1000)
    this.roll(s)
    if (!this.started) this.started = s
    this.counts[s % TpsMeter.SPAN] += n
  }
  private roll(s: number): void {
    if (!this.sec) { this.sec = s; return }
    if (s <= this.sec) return
    const gap = Math.min(TpsMeter.SPAN, s - this.sec)
    for (let i = 1; i <= gap; i++) this.counts[(this.sec + i) % TpsMeter.SPAN] = 0
    this.sec = s
  }
  /** 最近 10 个整秒的平均（刚开始不满 10 秒按实际秒数平均）；还没有成交给 null */
  rate(now: number): number | null {
    const s = Math.floor(now / 1000)
    this.roll(s)
    if (!this.started) return null
    const n = Math.max(1, Math.min(10, s - this.started))
    let sum = 0
    for (let i = 1; i <= n; i++) sum += this.counts[(s - i + TpsMeter.SPAN) % TpsMeter.SPAN]
    return sum / n
  }
  /** 最近 SPAN 个整秒（旧 → 新，不含正在走的这一秒） */
  series(now: number): number[] {
    const s = Math.floor(now / 1000)
    this.roll(s)
    const out: number[] = []
    for (let i = TpsMeter.SPAN - 1; i >= 1; i--) out.push(s - i >= this.started && this.started ? this.counts[(s - i + TpsMeter.SPAN) % TpsMeter.SPAN] : 0)
    return out
  }
  clear(): void { this.counts.fill(0); this.sec = 0; this.started = 0 }
}
