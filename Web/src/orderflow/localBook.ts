/* Hkline Web · 主力订单流 · 本地簿（逐行照 LocalBook.swift / VenueBook.swift）
 *
 * 序号规则四种：币安现货 rangeOverlap、币安合约 previousFinalOverlap、OKX previousFinalExact、
 * Coinbase strictIncrementing。只留中间价两侧 retainBps 以内的价位；「知不知道」一档（knows）
 * 用来区分「墙没了」和「墙在快照盖不到的地方」。
 */
import type { Action, BookDelta, BookLevel, BookSide, BookSnapshot, DepthMessage, SequenceModel, Venue } from './types'
import { usdOf } from './types'
import { D } from './settings'
import type { BucketScheme } from './bucket'

export type Quality = 'bootstrapping' | 'ready' | 'resyncing' | 'gapped'

export class BookError extends Error {}

function reaches(model: SequenceModel, lastUpdateID: number, d: BookDelta): boolean {
  return model === 'previousFinalOverlap' ? d.finalUpdateID >= lastUpdateID : d.finalUpdateID > lastUpdateID
}

const valid = (l: BookLevel): boolean => Number.isFinite(l.price) && l.price > 0 && Number.isFinite(l.quantity) && l.quantity >= 0

class SideLevels {
  levels = new Map<number, number>()
  touched = new Set<number>()
  private best: number | null = null
  private bestStale = false
  private worst: number | null = null
  private worstStale = false
  private _tracksWorst = false
  constructor(readonly isBid: boolean) {}

  get tracksWorst(): boolean { return this._tracksWorst }
  set tracksWorst(v: boolean) { if (v !== this._tracksWorst) { this._tracksWorst = v; this.worst = null; this.worstStale = v } }

  set(price: number, q: number): void {
    if (q === 0) {
      if (this.levels.delete(price)) {
        if (price === this.best) this.bestStale = true
        if (price === this.worst) this.worstStale = true
      }
      return
    }
    this.levels.set(price, q)
    if (this._tracksWorst && !this.worstStale) {
      if (this.worst != null) { if (this.isBid ? price < this.worst : price > this.worst) this.worst = price }
      else this.worst = price
    }
    if (this.bestStale) return
    if (this.best != null) { if (this.isBid ? price > this.best : price < this.best) this.best = price }
    else this.best = price
  }
  touch(p: number): void { this.touched.add(p) }
  forget(p: number): void { this.touched.delete(p) }
  pruneTouched(floor: number, ceiling: number): void {
    if (!this.touched.size) return
    for (const p of [...this.touched]) if (p < floor || p > ceiling) this.touched.delete(p)
  }
  removeAll(): void { this.levels.clear(); this.touched.clear(); this.best = null; this.bestStale = false; this.worst = null; this.worstStale = false }
  remove(prices: number[]): void {
    if (!prices.length) return
    for (const p of prices) { this.levels.delete(p); this.touched.delete(p) }
    if (this._tracksWorst) this.worstStale = true
  }
  private extreme(max: boolean): number | null {
    let out: number | null = null
    for (const p of this.levels.keys()) if (out == null || (max ? p > out : p < out)) out = p
    return out
  }
  worstPrice(): number | null {
    if (!this._tracksWorst) return this.extreme(!this.isBid)
    if (this.worstStale) { this.worst = this.extreme(!this.isBid); this.worstStale = false }
    return this.worst
  }
  bestPrice(): number | null {
    if (this.bestStale) { this.best = this.extreme(this.isBid); this.bestStale = false }
    return this.best
  }
}

interface Coverage { requestedLevels: number; bidLevels: number; askLevels: number; bidFloor: number | null; askCeiling: number | null }
const emptyCoverage = (): Coverage => ({ requestedLevels: 0, bidLevels: 0, askLevels: 0, bidFloor: null, askCeiling: null })

type Band = { floor: number; ceiling: number }

export class LocalBook {
  connection: number
  quality: Quality = 'bootstrapping'
  lastUpdateID: number | null = null
  coverage: Coverage = emptyCoverage()
  bids = new SideLevels(true)
  asks = new SideLevels(false)
  retainBps: number | null = null
  slidingWindow = false
  private retained: Band | null = null
  private trimmedBidFloor: number | null = null
  private trimmedAskCeiling: number | null = null

  constructor(readonly sequenceModel: SequenceModel, connection = 0) { this.connection = connection }

  get levelCount(): number { return this.bids.levels.size + this.asks.levels.size }
  quantity(price: number, side: BookSide): number { return (side === 'bid' ? this.bids : this.asks).levels.get(price) ?? 0 }

  bootstrap(s: BookSnapshot, buffered: BookDelta[]): 'ready' | 'waitingForOverlap' {
    this.validateIdentity(s.connection)
    this.quality = 'bootstrapping'
    this.lastUpdateID = s.lastUpdateID
    if (s.requestedLevels <= 0 || s.bids.length > s.requestedLevels || s.asks.length > s.requestedLevels) this.failSequence('invalidSnapshotCoverage')
    this.coverage = coverageOf(s)
    this.slidingWindow = s.slidingWindow
    this.bids.removeAll(); this.asks.removeAll()
    this.bids.tracksWorst = this.slidingWindow; this.asks.tracksWorst = this.slidingWindow
    this.retained = null; this.trimmedBidFloor = null; this.trimmedAskCeiling = null
    write(s.bids, this.bids); write(s.asks, this.asks)
    this.validateNotCrossed()
    this.trimFarLevels()

    const L = s.lastUpdateID
    const firstIndex = buffered.findIndex(d => reaches(this.sequenceModel, L, d))
    if (firstIndex < 0) return 'waitingForOverlap'
    const first = buffered[firstIndex]
    this.validateIdentity(first.connection)
    switch (this.sequenceModel) {
      case 'rangeOverlap': {
        if (first.previousFinalUpdateID != null) this.failSequence('unexpectedPreviousFinalUpdateID')
        const req = L + 1
        if (first.firstUpdateID > req || first.finalUpdateID < req) this.failSequence('snapshotDoesNotOverlap')
        break
      }
      case 'previousFinalOverlap':
        if (first.previousFinalUpdateID == null) this.failSequence('missingPreviousFinalUpdateID')
        if (first.firstUpdateID > L || first.finalUpdateID < L) this.failSequence('snapshotDoesNotOverlap')
        break
      case 'previousFinalExact':
        if (first.previousFinalUpdateID !== L) this.failSequence('snapshotDoesNotOverlap')
        break
      case 'strictIncrementing':
        if (first.previousFinalUpdateID != null || first.finalUpdateID !== L + 1) this.failSequence('snapshotDoesNotOverlap')
        break
      case 'snapshotOnly':
        this.failSequence('unexpectedDelta')
    }
    this.applyLevels(first)
    this.lastUpdateID = first.finalUpdateID
    this.quality = 'ready'
    this.validateNotCrossed()
    for (const e of buffered.slice(firstIndex + 1)) this.apply(e)
    return 'ready'
  }

  apply(d: BookDelta): 'applied' | 'duplicateIgnored' {
    if (this.quality !== 'ready') throw new BookError('notReady')
    this.validateIdentity(d.connection)
    const prev = this.lastUpdateID
    if (prev == null) throw new BookError('missingLocalSequence')
    if (d.finalUpdateID <= prev) return 'duplicateIgnored'
    switch (this.sequenceModel) {
      case 'rangeOverlap': {
        if (d.previousFinalUpdateID != null) this.failSequence('unexpectedPreviousFinalUpdateID')
        const req = prev + 1
        if (d.firstUpdateID > req || d.finalUpdateID < req) this.failSequence('sequenceGap')
        break
      }
      case 'previousFinalOverlap':
      case 'previousFinalExact':
        if (d.previousFinalUpdateID !== prev) this.failSequence('sequenceGap')
        break
      case 'strictIncrementing':
        if (d.previousFinalUpdateID != null || d.firstUpdateID !== prev + 1 || d.finalUpdateID !== d.firstUpdateID) this.failSequence('sequenceGap')
        break
      case 'snapshotOnly':
        this.failSequence('unexpectedDelta')
    }
    this.applyLevels(d)
    this.lastUpdateID = d.finalUpdateID
    this.validateNotCrossed()
    return 'applied'
  }

  replaceFromStreamSnapshot(s: BookSnapshot): void {
    this.validateIdentity(s.connection)
    if (this.lastUpdateID != null && !s.restart && s.lastUpdateID < this.lastUpdateID) this.failSequence('regressedStreamSnapshot')
    if (s.requestedLevels <= 0 || s.bids.length > s.requestedLevels || s.asks.length > s.requestedLevels) this.failSequence('invalidSnapshotCoverage')
    this.beginResync(s.connection)
    this.coverage = coverageOf(s)
    this.slidingWindow = s.slidingWindow
    this.bids.tracksWorst = this.slidingWindow; this.asks.tracksWorst = this.slidingWindow
    write(s.bids, this.bids); write(s.asks, this.asks)
    this.lastUpdateID = s.lastUpdateID
    this.quality = 'ready'
    this.validateNotCrossed()
    this.trimFarLevels()
  }

  beginResync(connection: number): void {
    this.connection = connection
    this.quality = 'resyncing'
    this.lastUpdateID = null
    this.bids.removeAll(); this.asks.removeAll()
    this.retained = null; this.trimmedBidFloor = null; this.trimmedAskCeiling = null
    this.coverage = emptyCoverage()
  }

  failSequence(reason: string): never { this.markGapped(); throw new BookError(reason) }

  markGapped(): void {
    this.quality = 'gapped'
    this.lastUpdateID = null
    this.bids.removeAll(); this.asks.removeAll()
    this.retained = null; this.trimmedBidFloor = null; this.trimmedAskCeiling = null
    this.coverage = emptyCoverage()
  }

  bestBid(): number | null { return this.bids.bestPrice() }
  bestAsk(): number | null { return this.asks.bestPrice() }
  mid(): number | null {
    const b = this.bids.bestPrice(), a = this.asks.bestPrice()
    return b == null || a == null ? null : (b + a) / 2
  }

  /** 一侧 [low, high] 里的每一档，只读。 */
  forEachLevelIn(side: BookSide, low: number, high: number, body: (p: number, q: number) => void): void {
    if (!Number.isFinite(low) || !Number.isFinite(high) || low > high) return
    for (const [p, q] of (side === 'bid' ? this.bids : this.asks).levels) if (p >= low && p <= high) body(p, q)
  }

  /** 中间价两侧 bps 以内的每一档（不排序），顺手裁掉保留区间以外的价位。返回中间价。 */
  forEachLevel(bps: number, body: (side: BookSide, p: number, q: number) => void): number | null {
    const bb = this.bids.bestPrice(), ba = this.asks.bestPrice()
    if (!Number.isFinite(bps) || bps <= 0 || bb == null || ba == null) return null
    const mid = (bb + ba) / 2
    const f = bps / 10_000
    const floor = mid * (1 - f), ceiling = mid * (1 + f)
    const keep = this.retainedBand(mid, bb, ba)
    const farB: number[] = [], farA: number[] = []
    for (const [p, q] of this.bids.levels) { if (p >= floor) body('bid', p, q); else if (keep && p < keep.floor) farB.push(p) }
    for (const [p, q] of this.asks.levels) { if (p <= ceiling) body('ask', p, q); else if (keep && p > keep.ceiling) farA.push(p) }
    this.bids.remove(farB); this.asks.remove(farA)
    if (keep) {
      this.bids.pruneTouched(keep.floor, keep.ceiling)
      this.asks.pruneTouched(keep.floor, keep.ceiling)
      this.noteRetained(keep)
    }
    this.retained = keep
    return mid
  }

  /** 只读版：不裁，展示层（梯子、盘口、热力）用。 */
  scan(low: number, high: number, body: (side: BookSide, p: number, q: number) => void): void {
    for (const [p, q] of this.bids.levels) if (p >= low && p <= high) body('bid', p, q)
    for (const [p, q] of this.asks.levels) if (p >= low && p <= high) body('ask', p, q)
  }

  knows(side: BookSide, price: number): boolean {
    if (this.slidingWindow) {
      const w = this.coverage.requestedLevels
      const s = side === 'bid' ? this.bids : this.asks
      const deepest = w > 0 && s.levels.size >= w ? s.worstPrice() : null
      if (deepest == null) return true
      return side === 'bid' ? price >= deepest : price <= deepest
    }
    if (side === 'bid') {
      const floor = this.knownBidFloor()
      if (floor == null) return true
      return price >= floor || this.bids.levels.has(price) || this.bids.touched.has(price)
    }
    const ceiling = this.knownAskCeiling()
    if (ceiling == null) return true
    return price <= ceiling || this.asks.levels.has(price) || this.asks.touched.has(price)
  }

  // -------------------------------------------------------------- 内部
  private validateIdentity(actual: number): void {
    if (actual !== this.connection) throw new BookError('staleConnection')
  }
  private applyLevels(d: BookDelta): void {
    write(d.bids, this.bids, this.retained)
    write(d.asks, this.asks, this.retained)
    if (!this.slidingWindow) {
      const floor = this.knownBidFloor()
      if (floor != null) noteBeyond(d.bids, this.bids, p => p < floor, this.retained)
      const ceiling = this.knownAskCeiling()
      if (ceiling != null) noteBeyond(d.asks, this.asks, p => p > ceiling, this.retained)
    }
  }
  private get bidsLimited(): boolean { return this.coverage.requestedLevels > 0 && this.coverage.bidLevels >= this.coverage.requestedLevels }
  private get asksLimited(): boolean { return this.coverage.requestedLevels > 0 && this.coverage.askLevels >= this.coverage.requestedLevels }
  private knownBidFloor(): number | null {
    const a = this.bidsLimited ? this.coverage.bidFloor : null
    const b = this.trimmedBidFloor
    return a != null && b != null ? Math.max(a, b) : (a ?? b)
  }
  private knownAskCeiling(): number | null {
    const a = this.asksLimited ? this.coverage.askCeiling : null
    const b = this.trimmedAskCeiling
    return a != null && b != null ? Math.min(a, b) : (a ?? b)
  }
  private retainedBand(mid: number, bb: number, ba: number): Band | null {
    const bps = this.retainBps
    if (this.slidingWindow || bps == null || !Number.isFinite(bps) || bps <= 0) return null
    const f = bps / 10_000
    return { floor: Math.min(mid * (1 - f), bb), ceiling: Math.max(mid * (1 + f), ba) }
  }
  private trimFarLevels(): void {
    const bb = this.bids.bestPrice(), ba = this.asks.bestPrice()
    if (this.retainBps == null || bb == null || ba == null) return
    const keep = this.retainedBand((bb + ba) / 2, bb, ba)
    if (!keep) return
    this.bids.remove([...this.bids.levels.keys()].filter(p => p < keep.floor))
    this.asks.remove([...this.asks.levels.keys()].filter(p => p > keep.ceiling))
    this.bids.pruneTouched(keep.floor, keep.ceiling)
    this.asks.pruneTouched(keep.floor, keep.ceiling)
    this.noteRetained(keep)
    this.retained = keep
  }
  private noteRetained(k: Band): void {
    this.trimmedBidFloor = Math.max(this.trimmedBidFloor ?? k.floor, k.floor)
    this.trimmedAskCeiling = Math.min(this.trimmedAskCeiling ?? k.ceiling, k.ceiling)
  }
  private validateNotCrossed(): void {
    const b = this.bids.bestPrice(), a = this.asks.bestPrice()
    if (b != null && a != null && b >= a) this.failSequence('crossed')
  }
}

function write(levels: BookLevel[], side: SideLevels, band: Band | null = null): void {
  for (const l of levels) {
    if (!valid(l)) continue
    if (band && l.quantity > 0 && (l.price < band.floor || l.price > band.ceiling)) continue
    side.set(l.price, l.quantity)
  }
}
function noteBeyond(levels: BookLevel[], side: SideLevels, beyond: (p: number) => boolean, band: Band | null): void {
  for (const l of levels) {
    if (!valid(l) || !beyond(l.price)) continue
    const inBand = band ? l.price >= band.floor && l.price <= band.ceiling : true
    if (l.quantity === 0 && inBand) side.touch(l.price); else side.forget(l.price)
  }
}
function coverageOf(s: BookSnapshot): Coverage {
  let bf: number | null = null, ac: number | null = null
  for (const l of s.bids) if (bf == null || l.price < bf) bf = l.price
  for (const l of s.asks) if (ac == null || l.price > ac) ac = l.price
  return { requestedLevels: s.requestedLevels, bidLevels: s.bids.length, askLevels: s.asks.length, bidFloor: bf, askCeiling: ac }
}

// ================================================================ VenueBook

export interface BucketValue { notional: number; topLevel: number; price: number }
/** 桶键：'b' / 'a' + 桶号 */
export const bucketKey = (side: BookSide, index: number): string => (side === 'bid' ? 'b' : 'a') + index
export const keySide = (k: string): BookSide => (k[0] === 'b' ? 'bid' : 'ask')
export const keyIndex = (k: string): number => +k.slice(1)

function addLevel(out: Map<string, BucketValue>, k: string, usd: number, p: number): void {
  let v = out.get(k)
  if (!v) { v = { notional: 0, topLevel: 0, price: 0 }; out.set(k, v) }
  v.notional += usd
  if (usd > v.topLevel) { v.topLevel = usd; v.price = p }
}

export class VenueBook {
  static readonly bufferCapacity = 5_000
  static readonly retainBps = 2 * D.scanRadiusBps
  book: LocalBook
  readySinceMs: number | null = null
  private buffered: BookDelta[] = []
  private pendingSnapshot: BookSnapshot | null = null
  private connection = 0
  /** 簿的版本：深度帧 / 快照 / 重连每来一次 +1（中间价、能不能用都只在这几处变） */
  private rev = 0
  /** 上一次分好的细桶（fineBuckets），按「版本 + 步长 + 半径」认 */
  private fine: { rev: number; step: number; bps: number; map: Map<string, BucketValue> | null } | null = null

  constructor(readonly venue: Venue) {
    this.book = new LocalBook(venue.sequenceModel)
    this.book.retainBps = VenueBook.retainBps
  }

  get isReady(): boolean { return this.book.quality === 'ready' }
  private get live(): boolean { return this.book.quality === 'ready' && this.readySinceMs != null }

  knows(side: BookSide, price: number): boolean { return this.live && this.book.knows(side, price) }

  connectionOpened(): Action {
    this.rev++
    this.connection += 1
    this.book.beginResync(this.connection)
    this.buffered = []
    this.pendingSnapshot = null
    this.readySinceMs = null
    return this.venue.snapshotInBand ? 'none' : 'fetchSnapshot'
  }

  ingest(m: DepthMessage, nowMs: number): Action {
    const inBand = this.venue.snapshotInBand
    if (m.type !== 'trade') this.rev++
    switch (m.type) {
      case 'snapshot': {
        const s = { ...m.snapshot, connection: this.connection }
        try { this.book.replaceFromStreamSnapshot(s); this.readySinceMs = nowMs; return 'none' }
        catch { this.readySinceMs = null; return inBand ? 'resubscribe' : 'fetchSnapshot' }
      }
      case 'delta': {
        const d = { ...m.delta, connection: this.connection }
        if (this.book.quality === 'ready') {
          try { this.book.apply(d); return 'none' }
          catch {
            this.readySinceMs = null
            if (inBand) return 'resubscribe'
            this.buffered = [d]
            this.pendingSnapshot = null
            return 'fetchSnapshot'
          }
        }
        if (inBand) return 'none'
        this.buffered.push(d)
        if (this.buffered.length > VenueBook.bufferCapacity) this.buffered.splice(0, this.buffered.length - VenueBook.bufferCapacity)
        if (this.pendingSnapshot && !reaches(this.book.sequenceModel, this.pendingSnapshot.lastUpdateID, d)) return 'none'
        return this.tryBootstrap(nowMs)
      }
      case 'trade': return 'none'
      case 'reset':
        this.book.markGapped()
        this.readySinceMs = null
        this.buffered = []
        this.pendingSnapshot = null
        return inBand ? 'resubscribe' : 'fetchSnapshot'
    }
  }

  applySnapshot(s: BookSnapshot, nowMs: number): Action {
    if (this.isReady) return 'none'
    this.rev++
    this.pendingSnapshot = { ...s, connection: this.connection }
    return this.tryBootstrap(nowMs)
  }

  private tryBootstrap(nowMs: number): Action {
    const s = this.pendingSnapshot
    if (!s) return 'none'
    try {
      if (this.book.bootstrap(s, this.buffered) === 'ready') {
        this.buffered = []
        this.pendingSnapshot = null
        this.readySinceMs = nowMs
      }
      return 'none'
    } catch {
      this.pendingSnapshot = null
      this.readySinceMs = null
      this.buffered = this.buffered.filter(d => d.finalUpdateID > s.lastUpdateID)
      return 'fetchSnapshot'
    }
  }

  /** fineBps（≤ radiusBps）：同一遍顺带把中间价两侧 fineBps 以内的也分一份存给 fineBuckets，展示层不用再扫一遍。
   *  内圈的边界、遍历顺序与单独 buckets(scheme, fineBps) 完全一样，结果逐位相同。 */
  buckets(scheme: BucketScheme, radiusBps: number, fineBps?: number): Map<string, BucketValue> | null {
    if (!this.live) return null
    const n = this.venue.notional
    const out = new Map<string, BucketValue>()
    const m0 = this.book.mid()
    const inner = fineBps != null && fineBps > 0 && fineBps <= radiusBps && m0 != null ? new Map<string, BucketValue>() : null
    const f = (fineBps ?? 0) / 10_000
    const floor = (m0 ?? 0) * (1 - f), ceiling = (m0 ?? 0) * (1 + f)
    const mid = this.book.forEachLevel(radiusBps, (side, p, q) => {
      const usd = usdOf(n, p, q)
      if (usd <= 0) return
      const k = bucketKey(side, scheme.index(p))
      addLevel(out, k, usd, p)
      if (inner && (side === 'bid' ? p >= floor : p <= ceiling)) addLevel(inner, k, usd, p)
    })
    if (inner) this.fine = { rev: this.rev, step: scheme.step, bps: fineBps!, map: mid == null ? null : inner }
    return mid == null ? null : out
  }

  /** 细桶（梯子、盘口、热力）：簿自上次分桶以来没动过（版本、步长、半径都一样）就直接复用——evaluate 那一遍通常已顺带分好。 */
  fineBuckets(scheme: BucketScheme, bps: number): Map<string, BucketValue> | null {
    const c = this.fine
    if (c && c.rev === this.rev && c.step === scheme.step && c.bps === bps) return c.map
    const map = this.buckets(scheme, bps)
    this.fine = { rev: this.rev, step: scheme.step, bps, map }
    return map
  }

  mid(): number | null { return this.live ? this.book.mid() : null }

  bucketsOnly(scheme: BucketScheme, keys: Set<string>): Map<string, BucketValue> {
    const out = new Map<string, BucketValue>()
    if (!this.live || !keys.size) return out
    const n = this.venue.notional
    for (const side of ['bid', 'ask'] as BookSide[]) {
      const wanted = new Set<number>()
      for (const k of keys) if (keySide(k) === side) wanted.add(keyIndex(k))
      if (!wanted.size) continue
      let lo = Infinity, hi = -Infinity
      for (const i of wanted) { if (i < lo) lo = i; if (i > hi) hi = i }
      const low = scheme.low(lo) * (1 - 1e-9), high = scheme.low(hi + 1) * (1 + 1e-9)
      this.book.forEachLevelIn(side, low, high, (p, q) => {
        const idx = scheme.index(p)
        if (!wanted.has(idx)) return
        const usd = usdOf(n, p, q)
        if (usd <= 0) return
        const k = bucketKey(side, idx)
        let v = out.get(k)
        if (!v) { v = { notional: 0, topLevel: 0, price: 0 }; out.set(k, v) }
        v.notional += usd
        if (usd > v.topLevel) { v.topLevel = usd; v.price = p }
      })
    }
    return out
  }

  depthUSD(bps: number): number | null {
    if (!this.live) return null
    const n = this.venue.notional
    let total = 0
    const mid = this.book.forEachLevel(bps, (_s, p, q) => { const u = usdOf(n, p, q); if (u > 0) total += u })
    return mid == null ? null : total
  }
}
