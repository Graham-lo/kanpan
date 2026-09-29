/* Hkline Web · 主力订单流 · 逐单模型（逐条照 OrderFlowModel.swift）
 *
 * 一条大单 = 交易所 × 产品 × 侧 × 价格桶上的挂单，桶的美元名义 ≥ 该产品门槛就算。
 * 出现 / 消失各要两拍且首尾 ≥ 300 ms；跌到门槛 × 0.5 以下才算消失；成交只认同一本簿自己的逐笔、
 * 且要和这一档掉的量在 5 秒内对上（Matching）；消失量里成交 ≥ 八成记「已成交」，否则「已撤销」；
 * 簿断开 2 分钟以上按最后一次看到的时刻「失联结束」。服务端历史由 mergeHistory 并进来，以服务端为准。
 *
 * 网页版不落盘（手机端的 OrderFlowJournal 不搬）：刷新后由服务端 24 小时历史补回。
 */
import type { Action, BigOrder, BookSide, DepthMessage, Product, Thresholds, Trade, Venue } from './types'
import { orderId, usdOf, venueId } from './types'
import { D } from './settings'
import { BucketScheme } from './bucket'
import { VenueBook, bucketKey, keySide, keyIndex, type BucketValue } from './localBook'

export const STALE_MS = 120_000
export const REMOTE_FRESH_MS = 180_000

export interface VenueStatus { id: string; label: string; exchange: string; product: Product; instrument: string; ready: boolean }

export interface Snapshot {
  phase: 'loading' | 'ready'
  orders: BigOrder[]
  asOfMs: number
  thresholds: Thresholds
  venues: VenueStatus[]
}

export interface HistoryPage {
  base: string
  thresholds: Thresholds
  trackedSinceMs: number
  fromMs: number
  toMs: number
  orders: BigOrder[]
}

const num = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null)
const pos = (v: unknown): number | null => { const n = num(v); return n != null && n > 0 ? n : null }
const nonNeg = (v: unknown): number | null => { const n = num(v); return n != null && n >= 0 ? n : null }
const int = (v: unknown): number | null => { const n = num(v); return n != null && Math.abs(n) < 9e15 ? Math.trunc(n) : null }
const PRODUCT_SET = new Set(['spot', 'usdtPerp', 'coinPerp', 'delivery'])
const STATUS_SET = new Set(['live', 'filled', 'cancelled', 'lost'])

/** 解服务端 /v1/market/orderflow/history（照 OrderFlowHistoryPage.parse）。 */
export function parseHistory(root: unknown, fromMs: number, toMs: number): HistoryPage | null {
  if (!root || typeof root !== 'object') return null
  const r = root as Record<string, unknown>
  if (typeof r.base !== 'string' || !Array.isArray(r.orders)) return null
  const t = (r.thresholds && typeof r.thresholds === 'object' ? r.thresholds : {}) as Record<string, unknown>
  const thresholds: Thresholds = {}
  for (const k of ['spot', 'usdtPerp', 'coinPerp', 'delivery', 'step'] as const) { const v = pos(t[k]); if (v != null) thresholds[k] = v }
  const orders: BigOrder[] = []
  for (const row of r.orders as Record<string, unknown>[]) {
    if (!row || typeof row !== 'object') continue
    const venueID = row.venueID, exchange = row.exchange, product = row.product, side = row.side, status = row.status
    if (typeof venueID !== 'string' || !venueID || typeof exchange !== 'string') continue
    if (typeof product !== 'string' || !PRODUCT_SET.has(product)) continue
    if (side !== 'bid' && side !== 'ask') continue
    if (typeof status !== 'string' || !STATUS_SET.has(status)) continue
    const bucket = int(row.bucket), price = pos(row.price), first = int(row.firstSeenMs)
    const initial = pos(row.initialNotional), threshold = pos(row.threshold)
    if (bucket == null || price == null || first == null || initial == null || threshold == null) continue
    const end = int(row.endMs)
    if ((status === 'live') !== (end == null)) continue
    orders.push({
      venueID, exchange, product: product as Product, side, bucket, price, firstSeenMs: first,
      endMs: end == null ? null : Math.max(end, first), status: status as BigOrder['status'],
      initialNotional: initial, notional: nonNeg(row.notional) ?? initial,
      filledNotional: nonNeg(row.filledNotional) ?? 0, threshold, vanishedNotional: nonNeg(row.vanishedNotional),
    })
  }
  return { base: r.base, thresholds, trackedSinceMs: int(r.trackedSinceMs) ?? fromMs, fromMs, toMs, orders }
}

export const latestMs = (p: HistoryPage): number | null =>
  p.orders.length ? Math.max(...p.orders.map(o => Math.max(o.firstSeenMs, o.endMs ?? o.firstSeenMs))) : null

// ------------------------------------------------------------------ 对账

class Matching {
  fill = 0; fillSince: number | null = null
  drop = 0; dropSince: number | null = null
  constructor(public level: number, public vanished = 0) {}
  static restored(o: BigOrder): Matching {
    return new Matching(o.notional, o.vanishedNotional ?? Math.max(0, o.initialNotional - o.notional, o.filledNotional))
  }
  addFill(usd: number, now: number): void { if (!(usd > 0)) return; this.fill += usd; if (this.fillSince == null) this.fillSince = now }
  addDrop(usd: number, now: number): void { if (!(usd > 0)) return; this.drop += usd; this.vanished += usd; if (this.dropSince == null) this.dropSince = now }
  observe(notional: number, now: number): void { const n = Math.max(0, notional); this.addDrop(this.level - n, now); this.level = n }
  /** 对上的那部分返回（调用方加进 filledNotional）；超时的作废。 */
  settle(now: number): number {
    const m = Math.min(this.fill, this.drop)
    let out = 0
    if (m > 0) { out = m; this.fill -= m; this.drop -= m }
    if (this.fill <= 0) { this.fill = 0; this.fillSince = null }
    if (this.drop <= 0) { this.drop = 0; this.dropSince = null }
    if (this.fillSince != null && now - this.fillSince > D.fillMatchMs) { this.fill = 0; this.fillSince = null }
    if (this.dropSince != null && now - this.dropSince > D.fillMatchMs) { this.drop = 0; this.dropSince = null }
    return out
  }
}

interface Candidate { firstMs: number; samples: number; initial: number; notional: number; price: number; filled: number; dropped: number }
interface Pending { firstMs: number; samples: number; remaining: number }

const ckey = (venue: string, bkey: string): string => venue + '#' + bkey
const ckVenue = (ck: string): string => ck.slice(0, ck.lastIndexOf('#'))
const ckBucket = (ck: string): string => ck.slice(ck.lastIndexOf('#') + 1)

export function confirmed(samples: number, firstMs: number, nowMs: number): boolean {
  return samples >= D.confirmationSamples && nowMs - firstMs >= D.confirmationMs
}
export function chronological(a: BigOrder, b: BigOrder): number {
  if (a.firstSeenMs !== b.firstSeenMs) return a.firstSeenMs - b.firstSeenMs
  const ia = orderId(a), ib = orderId(b)
  return ia < ib ? -1 : ia > ib ? 1 : 0
}
export function overlaps(a: BigOrder, b: BigOrder): boolean {
  const aEnd = a.endMs == null ? Infinity : Math.max(a.endMs, a.firstSeenMs + 1)
  const bEnd = b.endMs == null ? Infinity : Math.max(b.endMs, b.firstSeenMs + 1)
  return a.firstSeenMs < bEnd && b.firstSeenMs < aEnd
}

export function evictionOrder(indices: number[], orders: BigOrder[], nowMs: number, window: [number, number] | null): number[] {
  const recent = nowMs - D.recentKeepMs
  const tier = (o: BigOrder): number => {
    const end = o.endMs ?? nowMs
    if (end >= recent) return 2
    if (window && o.firstSeenMs <= window[1] && end >= window[0]) return 1
    return 0
  }
  return indices.map(i => { const o = orders[i]; const end = o.endMs ?? nowMs; return [i, tier(o), end - o.firstSeenMs, end] as const })
    .sort((a, b) => a[1] - b[1] || a[2] - b[2] || a[3] - b[3] || a[0] - b[0]).map(k => k[0])
}

export class OrderFlowModel {
  thresholds: Thresholds
  scheme: BucketScheme | null
  orders: BigOrder[] = []
  books = new Map<string, VenueBook>()
  private venueOrder: string[] = []
  private candidates = new Map<string, Candidate>()
  private liveIndex = new Map<string, number>()
  private ending = new Map<string, Pending>()
  private lastSeen = new Map<string, number>()
  private matching = new Map<string, Matching>()
  private venueSeen = new Map<string, number>()
  private startedMs: number | null = null
  private remoteSeen = new Map<string, number>()
  private visibleWindow: [number, number] | null = null

  constructor(readonly symbol: string, thresholds: Thresholds) {
    this.thresholds = { ...thresholds }
    this.scheme = BucketScheme.make(thresholds.step)
  }

  /** 加一本簿，返回它的 id（同一本加两次无事发生）。 */
  addVenue(v: Venue): string {
    const id = venueId(v)
    if (this.books.has(id)) return id
    this.books.set(id, new VenueBook(v))
    this.venueOrder.push(id)
    return id
  }
  get venueIds(): string[] { return this.venueOrder.slice() }
  isReady(id: string): boolean { return this.books.get(id)?.isReady ?? false }

  calibrationDepth(bps: number = D.calibrationBandBps): { depth: number; ready: number; total: number } {
    let depth = 0, ready = 0
    for (const id of this.venueOrder) { const d = this.books.get(id)!.depthUSD(bps); if (d == null) continue; depth += d; ready++ }
    return { depth, ready, total: this.venueOrder.length }
  }

  connectionOpened(id: string): Action { return this.books.get(id)?.connectionOpened() ?? 'none' }
  disconnected(id: string): void { this.books.get(id)?.connectionOpened() }

  ingest(id: string, m: DepthMessage, nowMs: number): Action {
    const b = this.books.get(id)
    if (!b) return 'none'
    if (m.type === 'trade') { this.attribute(m.trade, id, b, nowMs); return 'none' }
    return b.ingest(m, nowMs)
  }
  applySnapshot(id: string, s: Parameters<VenueBook['applySnapshot']>[0], nowMs: number): Action {
    return this.books.get(id)?.applySnapshot(s, nowMs) ?? 'none'
  }

  private attribute(t: Trade, id: string, b: VenueBook, nowMs: number): void {
    if (!this.scheme) return
    const usd = usdOf(b.venue.notional, t.price, t.quantity)
    if (!(usd > 0)) return
    const ck = ckey(id, bucketKey(t.hitSide, this.scheme.index(t.price)))
    const i = this.liveIndex.get(ck)
    if (i != null && this.orders[i].status === 'live') this.matching.get(orderId(this.orders[i]))?.addFill(usd, nowMs)
    const c = this.candidates.get(ck)
    if (c) c.filled += usd
  }

  // ------------------------------------------------------------ 设置
  setThresholds(next: Thresholds): void {
    const nextScheme = BucketScheme.make(next.step)
    this.thresholds = { ...next }
    if ((nextScheme?.step ?? null) !== (this.scheme?.step ?? null)) {
      this.scheme = nextScheme
      this.orders = []
      this.candidates.clear(); this.ending.clear(); this.lastSeen.clear(); this.matching.clear(); this.remoteSeen.clear()
      this.reindex()
      return
    }
    this.requalify()
    this.reindex()
  }

  private requalify(): void {
    this.orders = this.orders.filter(o => { const t = this.thresholds[o.product]; return t != null && o.initialNotional >= t })
    for (const o of this.orders) o.threshold = this.thresholds[o.product] ?? o.threshold
    for (const k of [...this.candidates.keys()]) {
      const b = this.books.get(ckVenue(k))
      if (!b || this.thresholds[b.venue.product] == null) this.candidates.delete(k)
    }
    this.keepOnly(new Set(this.orders.map(orderId)))
  }

  private keepOnly(alive: Set<string>): void {
    for (const m of [this.ending, this.lastSeen, this.matching, this.remoteSeen] as Map<string, unknown>[])
      for (const k of [...m.keys()]) if (!alive.has(k)) m.delete(k)
  }

  private reindex(): void {
    this.liveIndex.clear()
    this.orders.forEach((o, i) => { if (o.status === 'live') this.liveIndex.set(ckey(o.venueID, bucketKey(o.side, o.bucket)), i) })
  }

  setVisibleWindow(w: [number, number] | null): void { this.visibleWindow = w }

  // ------------------------------------------------------------ 评估
  evaluate(nowMs: number): Snapshot {
    const scheme = this.scheme
    if (!scheme) return { phase: 'loading', orders: [], asOfMs: nowMs, thresholds: this.thresholds, venues: this.statuses() }
    if (this.startedMs == null) this.startedMs = nowMs
    const evaluated = new Set<string>()
    const touched = new Set<string>()
    let appended = false
    for (const id of this.venueOrder) {
      const book = this.books.get(id)!
      const threshold = this.thresholds[book.venue.product]
      if (threshold == null || !(threshold > 0)) continue
      const map = book.buckets(scheme, D.scanRadiusBps)
      const mid = book.mid()
      if (!map || mid == null) continue
      evaluated.add(id)
      this.venueSeen.set(id, nowMs)

      const beyond = (side: BookSide, price: number, bps: number): boolean => {
        const f = bps / 10_000
        return side === 'bid' ? price < mid * (1 - f) : price > mid * (1 + f)
      }
      const mine: [string, number][] = []
      for (const [ck, i] of this.liveIndex) if (ckVenue(ck) === id && this.orders[i].status === 'live') mine.push([ckBucket(ck), i])
      const outerKeys = new Set<string>()
      for (const [bk, i] of mine) {
        const side = keySide(bk), idx = keyIndex(bk)
        if (beyond(side, this.orders[i].price, D.exitRadiusBps)) continue
        const farEdge = scheme.low(side === 'bid' ? idx : idx + 1)
        if (beyond(side, farEdge, D.scanRadiusBps)) outerKeys.add(bk)
      }
      const outer = book.bucketsOnly(scheme, outerKeys)

      // 1. 还挂着的单
      const exitLine = threshold * D.exitRatio
      const liveKeys = new Set<string>()
      for (const [bk, i] of mine) {
        const o = this.orders[i]
        if (o.status !== 'live') continue
        const side = keySide(bk)
        liveKeys.add(bk)
        const oid = orderId(o)
        if (beyond(side, o.price, D.exitRadiusBps)) { this.endLost(i, this.lastSeen.get(oid) ?? o.firstSeenMs); continue }
        const here: BucketValue | undefined = outerKeys.has(bk) ? outer.get(bk) : map.get(bk)
        if (here && here.notional >= exitLine) {
          const m = this.matching.get(oid)
          m?.observe(here.notional, nowMs)
          o.notional = here.notional
          o.price = here.price
          if (m) o.filledNotional += m.settle(nowMs)
          this.lastSeen.set(oid, nowMs)
          this.ending.delete(oid)
        } else if (!book.knows(side, o.price)) {
          this.ending.delete(oid)
        } else {
          const p = this.ending.get(oid) ?? { firstMs: nowMs, samples: 0, remaining: 0 }
          p.samples += 1
          p.remaining = here?.notional ?? 0
          const m = this.matching.get(oid)
          m?.observe(p.remaining, nowMs)
          if (m) o.filledNotional += m.settle(nowMs)
          if (confirmed(p.samples, p.firstMs, nowMs)) { this.end(i, p.firstMs, p.remaining); this.ending.delete(oid) }
          else this.ending.set(oid, p)
        }
      }

      // 2. 新过门槛的桶
      for (const [bk, v] of map) {
        if (v.notional < threshold || liveKeys.has(bk)) continue
        const ck = ckey(id, bk)
        touched.add(ck)
        const c = this.candidates.get(ck) ?? { firstMs: nowMs, samples: 0, initial: v.notional, notional: v.notional, price: v.price, filled: 0, dropped: 0 }
        c.samples += 1
        c.dropped += Math.max(0, c.notional - v.notional)
        c.notional = v.notional
        c.price = v.price
        if (confirmed(c.samples, c.firstMs, nowMs)) {
          const order: BigOrder = {
            venueID: id, exchange: book.venue.label, product: book.venue.product, side: keySide(bk), bucket: keyIndex(bk),
            price: c.price, firstSeenMs: c.firstMs, endMs: null, status: 'live', initialNotional: c.initial,
            notional: c.notional, filledNotional: 0, threshold, vanishedNotional: null,
          }
          const m = new Matching(c.notional)
          m.addFill(c.filled, c.firstMs)
          m.addDrop(c.dropped, c.firstMs)
          order.filledNotional += m.settle(nowMs)
          this.orders.push(order)
          this.liveIndex.set(ck, this.orders.length - 1)
          appended = true
          const oid = orderId(order)
          this.lastSeen.set(oid, nowMs)
          this.matching.set(oid, m)
          this.candidates.delete(ck)
        } else {
          this.candidates.set(ck, c)
        }
      }
    }
    for (const k of [...this.candidates.keys()]) if (!touched.has(k) && evaluated.has(ckVenue(k))) this.candidates.delete(k)

    this.expireStale(nowMs)
    const pruned = this.prune(nowMs)
    if (appended) this.orders.sort(chronological)
    if (appended || pruned) this.reindex()
    const phase = this.venueSeen.size === 0 && this.orders.length === 0 ? 'loading' : 'ready'
    return { phase, orders: this.orders, asOfMs: nowMs, thresholds: this.thresholds, venues: this.statuses() }
  }

  private statuses(): VenueStatus[] {
    return this.venueOrder.map(id => {
      const b = this.books.get(id)!
      return { id, label: b.venue.label, exchange: b.venue.exchange, product: b.venue.product, instrument: b.venue.instrument, ready: b.isReady }
    })
  }

  private end(i: number, atMs: number, remaining: number): void {
    const o = this.orders[i]
    const oid = orderId(o)
    const m = this.matching.get(oid) ?? Matching.restored(o)
    m.observe(remaining, atMs)
    o.filledNotional += m.settle(atMs)
    const vanished = m.vanished
    o.filledNotional = Math.min(o.filledNotional, vanished)
    o.vanishedNotional = vanished
    o.status = vanished > 0 && o.filledNotional >= vanished * D.filledRatio ? 'filled' : 'cancelled'
    o.endMs = Math.max(o.firstSeenMs, atMs)
    this.lastSeen.delete(oid); this.matching.delete(oid); this.remoteSeen.delete(oid)
  }

  private expireStale(nowMs: number): void {
    const started = this.startedMs
    if (started == null || nowMs - started < STALE_MS) return
    this.orders.forEach((o, i) => {
      if (o.status !== 'live') return
      const oid = orderId(o)
      const remote = this.remoteSeen.get(oid)
      if (remote != null && nowMs - remote < REMOTE_FRESH_MS) return
      const seen = this.venueSeen.get(o.venueID) ?? started
      if (nowMs - seen < STALE_MS) return
      this.endLost(i, this.lastSeen.get(oid) ?? o.firstSeenMs)
    })
  }

  private endLost(i: number, atMs: number): void {
    const o = this.orders[i]
    const oid = orderId(o)
    o.status = 'lost'
    o.endMs = Math.max(o.firstSeenMs, atMs)
    o.vanishedNotional = null
    this.lastSeen.delete(oid); this.matching.delete(oid); this.ending.delete(oid); this.remoteSeen.delete(oid)
  }

  private prune(nowMs: number): boolean {
    const cutoff = nowMs - D.retentionMs
    const before = this.orders.length
    this.orders = this.orders.filter(o => o.status === 'live' || (o.endMs ?? o.firstSeenMs) >= cutoff)
    const ended = this.orders.flatMap((o, i) => (o.status === 'live' ? [] : [i]))
    if (ended.length > D.maxEndedOrders) {
      const keep = Math.floor(D.maxEndedOrders * D.trimRatio)
      const drop = new Set(evictionOrder(ended, this.orders, nowMs, this.visibleWindow).slice(0, ended.length - keep))
      this.orders = this.orders.filter((_, i) => !drop.has(i))
    }
    if (this.orders.length !== before) {
      this.keepOnly(new Set(this.orders.filter(o => o.status === 'live').map(orderId)))
      return true
    }
    return false
  }

  // ------------------------------------------------------------ 服务端历史
  mergeHistory(page: HistoryPage, chartScale: number, nowMs: number): 'merged' | 'pending' | 'incompatible' {
    const scheme = this.scheme
    if (!scheme) return 'pending'
    const rs = page.thresholds.step
    if (rs == null || !Number.isFinite(chartScale) || chartScale <= 0 || Math.abs(rs * chartScale - scheme.step) > scheme.step * 1e-6) return 'incompatible'
    const incoming: BigOrder[] = []
    for (const src of page.orders) {
      const t = this.thresholds[src.product]
      if (t == null || src.initialNotional < t) continue
      const o = { ...src, price: src.price * chartScale }
      if (!Number.isFinite(o.price) || o.price <= 0) continue
      o.bucket = scheme.index(o.price)
      o.threshold = t
      incoming.push(o)
    }
    if (!incoming.length) return 'merged'

    const key = (o: BigOrder): string => ckey(o.venueID, bucketKey(o.side, o.bucket))
    const byKey = new Map<string, number[]>()
    this.orders.forEach((o, i) => { const k = key(o); const a = byKey.get(k); if (a) a.push(i); else byKey.set(k, [i]) })
    const removed = new Set<number>(), claimed = new Set<number>()
    const added: BigOrder[] = []

    for (const remote of incoming) {
      if (remote.status !== 'live') continue
      const matches = (byKey.get(key(remote)) ?? []).filter(i => !removed.has(i) && !claimed.has(i) && overlaps(this.orders[i], remote))
      const li = matches.find(i => this.orders[i].status === 'live')
      if (li != null) {
        this.adopt(li, remote, nowMs)
        claimed.add(li)
        for (const j of matches) if (j !== li) removed.add(j)
        continue
      }
      const endedLocal = matches.filter(i => this.orders[i].status === 'filled' || this.orders[i].status === 'cancelled')
      if (endedLocal.length) {
        const j = endedLocal.reduce((a, b) => ((this.orders[a].endMs ?? 0) < (this.orders[b].endMs ?? 0) ? b : a))
        const old = this.orders[j]
        const oldEnd = old.endMs
        old.firstSeenMs = Math.min(remote.firstSeenMs, oldEnd ?? remote.firstSeenMs)
        old.initialNotional = remote.initialNotional
        old.filledNotional = Math.max(old.filledNotional, remote.filledNotional)
        claimed.add(j)
        for (const k of matches) if (k !== j) removed.add(k)
        continue
      }
      for (const m of matches) removed.add(m)
      const taken = { ...remote }
      const m = Matching.restored(remote)
      taken.filledNotional = Math.min(taken.filledNotional, m.vanished)
      taken.vanishedNotional = null
      added.push(taken)
      const rid = orderId(remote)
      this.lastSeen.set(rid, nowMs); this.matching.set(rid, m); this.remoteSeen.set(rid, nowMs)
    }
    for (const remote of incoming) {
      if (remote.status === 'live') continue
      for (const i of byKey.get(key(remote)) ?? []) if (!claimed.has(i) && overlaps(this.orders[i], remote)) removed.add(i)
      added.push(remote)
    }
    if (removed.size) this.orders = this.orders.filter((_, i) => !removed.has(i))
    this.orders.push(...added)
    this.orders.sort(chronological)
    this.reindex()
    this.keepOnly(new Set(this.orders.filter(o => o.status === 'live').map(orderId)))
    for (const k of [...this.candidates.keys()]) if (this.liveIndex.has(k)) this.candidates.delete(k)
    this.prune(nowMs)
    this.reindex()
    return 'merged'
  }

  private adopt(i: number, remote: BigOrder, nowMs: number): void {
    const o = this.orders[i]
    const oldID = orderId(o)
    const oldNotional = o.notional
    o.firstSeenMs = remote.firstSeenMs
    o.initialNotional = remote.initialNotional
    o.filledNotional = Math.max(o.filledNotional, remote.filledNotional)
    const newID = orderId(o)
    if (newID !== oldID) {
      for (const m of [this.lastSeen, this.matching, this.ending] as Map<string, unknown>[]) {
        const v = m.get(oldID); m.delete(oldID); if (v !== undefined) m.set(newID, v)
      }
    }
    const m = this.matching.get(newID) ?? Matching.restored(o)
    m.vanished = Math.max(m.vanished, remote.vanishedNotional ?? (remote.initialNotional - oldNotional), o.filledNotional)
    this.matching.set(newID, m)
    if (!this.lastSeen.has(newID)) this.lastSeen.set(newID, nowMs)
    this.remoteSeen.delete(oldID)
    this.remoteSeen.set(newID, nowMs)
  }
}
